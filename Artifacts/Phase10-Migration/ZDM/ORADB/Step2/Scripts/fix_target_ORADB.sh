#!/usr/bin/env bash
# =============================================================================
# fix_target_ORADB.sh
# ZDM Step 2 — Target database remediation for ORADB migration
#
# Resolves: ACTION-04 (TDE Master Key on target CDB)
#
# Run from: ZDM server (10.1.0.8) as azureuser
# Requires: SSH key ~/.ssh/odaa.pem and sudo access on target node 1
#
# IMPORTANT: You must supply the TDE wallet password interactively or via env var.
#            Do NOT hardcode passwords in this script.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Environment — sourced from zdm-env.md
# ---------------------------------------------------------------------------
TARGET_HOST="10.0.1.160"
TARGET_SSH_USER="opc"
TARGET_SSH_KEY="${HOME}/.ssh/odaa.pem"
ORACLE_USER="oracle"
ORACLE_HOME="/u02/app/oracle/product/19.0.0.0/dbhome_1"
# ORACLE_SID for target CDB — discovered as the pre-provisioned CDB
# ZDM creates a new CDB; the existing target DB (wrapping OCID) is identified below.
# Node 1 SID is typically the first node SID; check /etc/oratab on target.
TARGET_ORACLE_SID="$(ssh -i "${HOME}/.ssh/odaa.pem" -o StrictHostKeyChecking=no opc@${TARGET_HOST} \
  "sudo cat /etc/oratab 2>/dev/null | grep -v '^#' | grep -v '^$' | head -1 | cut -d: -f1" 2>/dev/null || echo "")"

LOG_FILE="$(dirname "$0")/../Logs/fix_target_ORADB_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")"

log() { echo "[$(date +%Y-%m-%dT%H:%M:%S)] $*" | tee -a "${LOG_FILE}"; }
log_section() { log ""; log "========================================"; log "$*"; log "========================================"; }

# ---------------------------------------------------------------------------
# Helper: run SQL on target via SSH + sudo, using base64 to avoid quoting issues
# ---------------------------------------------------------------------------
run_sql_on_target() {
  local sql_block="$1"
  local oracle_sid="${2:-${TARGET_ORACLE_SID}}"
  local encoded_sql
  encoded_sql=$(printf '%s\n' "${sql_block}" | base64 -w 0)
  ssh -i "${TARGET_SSH_KEY}" \
      -o StrictHostKeyChecking=no \
      -o ConnectTimeout=30 \
      "${TARGET_SSH_USER}@${TARGET_HOST}" \
      "sudo -u ${ORACLE_USER} bash -c '
        export ORACLE_HOME=${ORACLE_HOME}
        export ORACLE_SID=${oracle_sid}
        export PATH=\${ORACLE_HOME}/bin:\${PATH}
        echo \"${encoded_sql}\" | base64 -d | sqlplus -S / as sysdba
      '"
}

# Helper: run shell command on target
run_shell_on_target() {
  ssh -i "${TARGET_SSH_KEY}" \
      -o StrictHostKeyChecking=no \
      -o ConnectTimeout=30 \
      "${TARGET_SSH_USER}@${TARGET_HOST}" \
      "$@"
}

# ---------------------------------------------------------------------------
# Verify SSH connectivity
# ---------------------------------------------------------------------------
log_section "PRE-CHECK: Verify SSH connectivity to target"
if ! run_shell_on_target "echo 'SSH OK'"; then
  log "ERROR: Cannot SSH to ${TARGET_SSH_USER}@${TARGET_HOST}"
  exit 1
fi
log "SSH to target verified."

# ---------------------------------------------------------------------------
# Discover target CDB SID from /etc/oratab
# ---------------------------------------------------------------------------
log_section "PRE-CHECK: Discover target CDB SID"
ORATAB_ENTRIES=$(run_shell_on_target "sudo cat /etc/oratab 2>/dev/null | grep -v '^#' | grep -v '^\$' | grep -v 'GRID_HOME\\|#'" || echo "")
log "Contents of /etc/oratab (non-comment):"
echo "${ORATAB_ENTRIES}" | tee -a "${LOG_FILE}"

# If TARGET_ORACLE_SID is empty, prompt user
if [[ -z "${TARGET_ORACLE_SID}" ]]; then
  log "Could not auto-detect target CDB SID from /etc/oratab."
  read -rp "Enter the target CDB ORACLE_SID (the pre-provisioned CDB for ORADB migration): " TARGET_ORACLE_SID
fi
log "Using TARGET_ORACLE_SID=${TARGET_ORACLE_SID}"

# ---------------------------------------------------------------------------
# PRE-CHECK: Current TDE wallet status on target
# ---------------------------------------------------------------------------
log_section "PRE-CHECK: Target TDE wallet status"
TDE_CHECK_SQL="
SET PAGESIZE 0 FEEDBACK OFF
SELECT 'WALLET_STATUS='||STATUS||' WALLET_TYPE='||WALLET_TYPE
  FROM V\$ENCRYPTION_WALLET
 WHERE ROWNUM = 1;
EXIT;
"
run_sql_on_target "${TDE_CHECK_SQL}" | tee -a "${LOG_FILE}"

# ---------------------------------------------------------------------------
# ACTION-04: Create TDE Master Key in target CDB
# ---------------------------------------------------------------------------
log_section "ACTION-04: Configure TDE Master Key on target CDB"
log "The target wallet shows OPEN_NO_MASTER_KEY — a master key must be created."
log ""
log "⚠️  You will be prompted for the TDE wallet password."
log "    This is the wallet password set during Exadata provisioning."
log "    It is NOT stored in this script."
log ""

# Prompt for wallet password securely
read -rsp "Enter target CDB TDE wallet password: " TDE_WALLET_PASSWORD
echo ""
read -rsp "Confirm TDE wallet password: " TDE_WALLET_PASSWORD_CONFIRM
echo ""

if [[ "${TDE_WALLET_PASSWORD}" != "${TDE_WALLET_PASSWORD_CONFIRM}" ]]; then
  log "ERROR: Passwords do not match. Aborting."
  exit 1
fi

# We CANNOT pass the password through base64 SQL because the ADMINISTER KEY
# MANAGEMENT statement requires an interactive or directly embedded password.
# Instead, we use a temporary script file on the target to avoid shell quoting issues.
log "Creating temporary SQL script on target node..."
TDE_TMP_SCRIPT="/tmp/tde_set_key_$$.sql"

# Write the script content via SSH, then execute and clean up
run_shell_on_target "sudo -u ${ORACLE_USER} bash -c '
  cat > ${TDE_TMP_SCRIPT} <<SQLEOF
SET PAGESIZE 0 FEEDBACK OFF
ADMINISTER KEY MANAGEMENT SET KEY FORCE KEYSTORE IDENTIFIED BY \"${TDE_WALLET_PASSWORD}\" WITH BACKUP;
SELECT STATUS, WALLET_TYPE FROM V\$ENCRYPTION_WALLET WHERE ROWNUM = 1;
EXIT;
SQLEOF
  chmod 600 ${TDE_TMP_SCRIPT}
'"

log "Executing TDE master key creation..."
run_shell_on_target "sudo -u ${ORACLE_USER} bash -c '
  export ORACLE_HOME=${ORACLE_HOME}
  export ORACLE_SID=${TARGET_ORACLE_SID}
  export PATH=\${ORACLE_HOME}/bin:\${PATH}
  sqlplus -S / as sysdba @${TDE_TMP_SCRIPT}
  rm -f ${TDE_TMP_SCRIPT}
'" | tee -a "${LOG_FILE}"

# Unset password from memory
unset TDE_WALLET_PASSWORD TDE_WALLET_PASSWORD_CONFIRM

# Verify TDE status
log "Verifying TDE wallet status post-remediation..."
VERIFY_TDE_SQL="
SET PAGESIZE 0 FEEDBACK OFF
SELECT 'WALLET_STATUS='||STATUS||' WALLET_TYPE='||WALLET_TYPE
  FROM V\$ENCRYPTION_WALLET
 WHERE ROWNUM = 1;
EXIT;
"
RESULT=$(run_sql_on_target "${VERIFY_TDE_SQL}")
echo "${RESULT}" | tee -a "${LOG_FILE}"

if echo "${RESULT}" | grep -qE "WALLET_STATUS=OPEN"; then
  if echo "${RESULT}" | grep -q "OPEN_NO_MASTER_KEY"; then
    log "❌ ACTION-04: Wallet is still OPEN_NO_MASTER_KEY — master key may not have been created."
    log "   Check the output above for errors. You may need to re-run with the correct wallet password."
    exit 1
  else
    log "✅ ACTION-04 VERIFIED: TDE wallet is OPEN with a master key."
  fi
else
  log "⚠️  ACTION-04: Wallet status unexpected — review output above."
fi

# ---------------------------------------------------------------------------
# ADDITIONAL CHECK: Review offline databases on /u02 (Risk R-07)
# ---------------------------------------------------------------------------
log_section "ADVISORY — R-07: Disk space on /u02 (offline DBs)"
log "Discovery showed migdb, mydb, oradb01m all OFFLINE on target."
log "These consume ~57 GB on /u02 (only 14 GB currently free)."
log ""
run_shell_on_target "df -h /u02" | tee -a "${LOG_FILE}"
run_shell_on_target "sudo du -sh /u02/app/oracle/oradata/* 2>/dev/null || echo 'Cannot enumerate (permission or path)'" | tee -a "${LOG_FILE}" || true

log ""
log "ACTION REQUIRED: Coordinate with ODAA DBA to drop or clean up offline databases"
log "(migdb, mydb, oradb01m) before ZDM creates the new ORADB on /u02."
log "Each DB can be dropped with: srvctl remove database -db <dbname> -noprompt"
log "Followed by: rm -rf /u02/app/oracle/oradata/<dbname>"

log ""
log "fix_target_ORADB.sh completed. Log saved to: ${LOG_FILE}"
