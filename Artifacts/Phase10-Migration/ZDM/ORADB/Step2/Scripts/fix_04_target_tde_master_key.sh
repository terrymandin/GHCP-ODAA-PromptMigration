#!/usr/bin/env bash
# =============================================================================
# fix_04_target_tde_master_key.sh
#
# Purpose : Create a TDE master key in the target ODAA CDB wallet.
#           The wallet status is currently OPEN_NO_MASTER_KEY, which will
#           block ZDM from provisioning the migrated PDB.
#
# Target  : Target database server (10.0.1.160, Node 1) — executed FROM the
#           ZDM server via SSH. The script SSHes as TARGET_SSH_USER and
#           executes SQL as the oracle OS user via sudo.
#
# Run as  : azureuser on ZDM server (10.1.0.8)
# Usage   : TDE_WALLET_PASSWORD=<password> bash fix_04_target_tde_master_key.sh
#           OR run interactively — the script will prompt if not set.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — sourced from zdm-env.md values
# ---------------------------------------------------------------------------
TARGET_HOST="${TARGET_HOST:-10.0.1.160}"
TARGET_SSH_USER="${TARGET_SSH_USER:-opc}"
TARGET_SSH_KEY="${TARGET_SSH_KEY:-${HOME}/.ssh/odaa.pem}"
ORACLE_USER="${ORACLE_USER:-oracle}"
ORACLE_HOME="${TARGET_ORACLE_HOME:-/u02/app/oracle/product/19.0.0.0/dbhome_1}"
# TARGET_ORACLE_SID for the CDB — the target CDB name. Adjust if different.
# The target CDB name must be confirmed from the OCI Console / ODAA provisioning.
ORACLE_SID="${TARGET_ORACLE_SID:-}"

LOG_FILE="fix_04_$(date +%Y%m%d_%H%M%S).log"

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"; }
info() { log "INFO  $*"; }
warn() { log "WARN  $*"; }
fail() { log "ERROR $*"; exit 1; }
sep()  { log "----------------------------------------------------------------------"; }

# ---------------------------------------------------------------------------
# Prompt for wallet password if not set in environment
# ---------------------------------------------------------------------------
if [ -z "${TDE_WALLET_PASSWORD:-}" ]; then
  read -r -s -p "Enter the TDE wallet password for the target CDB: " TDE_WALLET_PASSWORD
  echo
fi
[ -n "${TDE_WALLET_PASSWORD}" ] || fail "TDE_WALLET_PASSWORD must not be empty."

# ---------------------------------------------------------------------------
# Determine CDB SID on target if not provided
# ---------------------------------------------------------------------------
sep
info "Starting fix_04: Configure TDE Master Key on Target CDB"
info "Target host : ${TARGET_HOST}"
info "SSH user    : ${TARGET_SSH_USER}"
info "Log file    : ${LOG_FILE}"
sep

info "Step 0: Testing SSH connectivity to target..."
ssh -i "${TARGET_SSH_KEY}" \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=15 \
    "${TARGET_SSH_USER}@${TARGET_HOST}" \
    "hostname" >> "${LOG_FILE}" 2>&1 || fail "Cannot SSH to ${TARGET_SSH_USER}@${TARGET_HOST}. Check key and connectivity."
info "SSH to target: OK"

# ---------------------------------------------------------------------------
# Detect CDB SID if not provided
# ---------------------------------------------------------------------------
if [ -z "${ORACLE_SID}" ]; then
  info "TARGET_ORACLE_SID not set — auto-detecting from /etc/oratab on target..."
  ORACLE_SID=$(ssh -i "${TARGET_SSH_KEY}" \
                   -o StrictHostKeyChecking=no \
                   -o ConnectTimeout=15 \
                   "${TARGET_SSH_USER}@${TARGET_HOST}" \
                   "grep -v '^#' /etc/oratab | grep -i ':${ORACLE_HOME}:' | head -1 | cut -d: -f1" 2>/dev/null) || true
  info "Detected ORACLE_SID: '${ORACLE_SID}'"
  [ -n "${ORACLE_SID}" ] || fail "Could not auto-detect ORACLE_SID from /etc/oratab. Set TARGET_ORACLE_SID manually."
fi

# ---------------------------------------------------------------------------
# Helper: run SQL on target via SSH + sudo + base64 encoding
# ---------------------------------------------------------------------------
run_sql_on_target() {
  local sql_block="$1"
  local encoded_sql
  encoded_sql=$(printf '%s\n' "${sql_block}" | base64 -w 0)
  ssh -i "${TARGET_SSH_KEY}" \
      -o StrictHostKeyChecking=no \
      -o ConnectTimeout=15 \
      "${TARGET_SSH_USER}@${TARGET_HOST}" \
      "sudo -u ${ORACLE_USER} bash -c '
        export ORACLE_HOME=${ORACLE_HOME}
        export ORACLE_SID=${ORACLE_SID}
        export PATH=\${ORACLE_HOME}/bin:\${PATH}
        echo \"${encoded_sql}\" | base64 -d | sqlplus -S / as sysdba
      '"
}

# ---------------------------------------------------------------------------
# Step 1: Check current wallet status
# ---------------------------------------------------------------------------
sep
info "Step 1: Checking current TDE wallet status..."

CHECK_SQL="
SET PAGESIZE 20 LINESIZE 120 FEEDBACK OFF
COLUMN WRL_PARAMETER FORMAT A50
COLUMN STATUS FORMAT A30
COLUMN WALLET_TYPE FORMAT A20
SELECT WRL_PARAMETER, STATUS, WALLET_TYPE FROM V\$ENCRYPTION_WALLET;
EXIT;
"
WALLET_STATUS=$(run_sql_on_target "${CHECK_SQL}" 2>&1)
info "Current wallet status:"
echo "${WALLET_STATUS}" | tee -a "${LOG_FILE}"

if echo "${WALLET_STATUS}" | grep -q "OPEN$\|OPEN "; then
  # Already has master key
  info "Wallet STATUS = OPEN (master key already set). Verifying..."
fi

# ---------------------------------------------------------------------------
# Step 2: Create TDE master key
# ---------------------------------------------------------------------------
sep
info "Step 2: Creating TDE master key in target CDB wallet..."
info "   (Using ADMINISTER KEY MANAGEMENT SET KEY FORCE KEYSTORE ...)"

# We must embed the wallet password using printf so we can base64-encode
# the SQL including the password literal safely.
TDE_SQL="
WHENEVER SQLERROR EXIT SQL.SQLCODE
ADMINISTER KEY MANAGEMENT SET KEY FORCE KEYSTORE IDENTIFIED BY \"${TDE_WALLET_PASSWORD}\" WITH BACKUP;
EXIT;
"
run_sql_on_target "${TDE_SQL}" 2>&1 | tee -a "${LOG_FILE}" || fail "Failed to create TDE master key. Check wallet password and wallet location."
info "TDE master key created successfully."

# ---------------------------------------------------------------------------
# Step 3: Verification
# ---------------------------------------------------------------------------
sep
info "Step 3: Verifying wallet status..."

VERIFY_SQL="
SET PAGESIZE 20 LINESIZE 120 FEEDBACK OFF
COLUMN WRL_PARAMETER FORMAT A50
COLUMN STATUS FORMAT A30
COLUMN WALLET_TYPE FORMAT A20
SELECT WRL_PARAMETER, STATUS, WALLET_TYPE FROM V\$ENCRYPTION_WALLET;
EXIT;
"
VERIFY_OUTPUT=$(run_sql_on_target "${VERIFY_SQL}" 2>&1)
info "Wallet status after remediation:"
echo "${VERIFY_OUTPUT}" | tee -a "${LOG_FILE}"

if echo "${VERIFY_OUTPUT}" | grep -qE "OPEN[[:space:]]"; then
  info "✅ TDE wallet is OPEN with a master key. Target CDB is ready for ZDM migration."
else
  warn "⚠️  Wallet status is not OPEN. Review output above and check wallet configuration."
fi

sep
info "Log saved to: ${LOG_FILE}"
