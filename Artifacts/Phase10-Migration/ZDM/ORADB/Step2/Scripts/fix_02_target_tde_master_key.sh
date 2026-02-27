#!/usr/bin/env bash
# =============================================================================
# fix_02_target_tde_master_key.sh
# =============================================================================
# Purpose : Create a TDE Master Key in the target ODAA CDB.
#           The target currently shows OPEN_NO_MASTER_KEY — ZDM requires a
#           master key to exist before migration begins.
#
# Action  : ACTION-04
#
# Run from: ZDM Server (10.1.0.8) as azureuser
# Run as  : opc  -->  sudo -u oracle  -->  sqlplus / as sysdba
#
# WARNING : You must supply the TDE wallet password interactively.
#           Do NOT store the wallet password in this script or any file.
#
# Usage   : bash fix_02_target_tde_master_key.sh
#           bash fix_02_target_tde_master_key.sh --verify-only
# =============================================================================

set -euo pipefail

# --- Configuration (from zdm-env.md) ----------------------------------------
TARGET_HOST="10.0.1.160"
TARGET_SSH_USER="opc"
TARGET_SSH_KEY="${HOME}/.ssh/odaa.pem"
ORACLE_HOME="/u02/app/oracle/product/19.0.0.0/dbhome_1"
ORACLE_USER="oracle"
# ----------------------------------------------------------------------------

VERIFY_ONLY=false
if [[ "${1:-}" == "--verify-only" ]]; then
  VERIFY_ONLY=true
fi

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

log "================================================================"
log "fix_02_target_tde_master_key.sh — ORADB Target TDE Master Key"
log "================================================================"
log "Target host  : ${TARGET_HOST}"
log "SSH user     : ${TARGET_SSH_USER}"
log "Oracle HOME  : ${ORACLE_HOME}"
log "Verify only  : ${VERIFY_ONLY}"
log "================================================================"

# --- Helper: detect active CDB SID on target --------------------------------
get_target_sid() {
  ssh -i "${TARGET_SSH_KEY}" \
      -o StrictHostKeyChecking=no \
      -o ConnectTimeout=10 \
      "${TARGET_SSH_USER}@${TARGET_HOST}" \
      "sudo -u ${ORACLE_USER} bash -c '
        SID=\$(grep -v \"^#\" /etc/oratab | grep -i \"dbhome_1\" | grep -v \"^\\$\" | head -1 | cut -d: -f1)
        echo \${SID}
      '"
}

# --- VERIFY-ONLY mode -------------------------------------------------------
if [[ "${VERIFY_ONLY}" == "true" ]]; then
  log "Fetching TDE wallet status from target (read-only)..."
  TARGET_SID=$(get_target_sid)
  log "Target CDB SID detected: ${TARGET_SID}"

  ssh -i "${TARGET_SSH_KEY}" \
      -o StrictHostKeyChecking=no \
      "${TARGET_SSH_USER}@${TARGET_HOST}" \
      "sudo -u ${ORACLE_USER} bash -c '
        export ORACLE_HOME=${ORACLE_HOME}
        export ORACLE_SID=${TARGET_SID}
        export PATH=\${ORACLE_HOME}/bin:\${PATH}
        sqlplus -S / as sysdba <<EOF_SQL
SET LINESIZE 120
SET PAGESIZE 50
PROMPT ── TDE Wallet Status (Should NOT be OPEN_NO_MASTER_KEY) ──
SELECT WRL_TYPE, STATUS, WALLET_TYPE, CON_ID
FROM V\\\$ENCRYPTION_WALLET
ORDER BY CON_ID;
PROMPT ── CDB / PDB Summary ──
SELECT CON_ID, NAME, OPEN_MODE FROM V\\\$PDBS ORDER BY CON_ID;
EXIT;
EOF_SQL
'"
  log "Verification complete."
  exit 0
fi

# --- Detect target CDB SID --------------------------------------------------
log "Detecting active CDB SID on target..."
TARGET_SID=$(get_target_sid)
if [[ -z "${TARGET_SID}" ]]; then
  log "ERROR: Could not detect a CDB SID from /etc/oratab on target."
  log "       Check that a database using ${ORACLE_HOME} is registered."
  exit 1
fi
log "Target CDB SID: ${TARGET_SID}"

# --- Check current status ----------------------------------------------------
log "Checking current TDE wallet status on target..."
CURRENT_STATUS=$(ssh -i "${TARGET_SSH_KEY}" \
    -o StrictHostKeyChecking=no \
    "${TARGET_SSH_USER}@${TARGET_HOST}" \
    "sudo -u ${ORACLE_USER} bash -c '
      export ORACLE_HOME=${ORACLE_HOME}
      export ORACLE_SID=${TARGET_SID}
      export PATH=\${ORACLE_HOME}/bin:\${PATH}
      sqlplus -S / as sysdba <<EOF_SQL
SET PAGESIZE 0 FEEDBACK OFF HEADING OFF
SELECT STATUS FROM V\\\$ENCRYPTION_WALLET WHERE ROWNUM=1;
EXIT;
EOF_SQL
'" 2>/dev/null | tr -d '[:space:]')

log "Current TDE status: ${CURRENT_STATUS}"

if [[ "${CURRENT_STATUS}" == "OPEN" ]]; then
  log "TDE wallet status is already OPEN. Checking for master key..."
  WALLET_TYPE=$(ssh -i "${TARGET_SSH_KEY}" \
      -o StrictHostKeyChecking=no \
      "${TARGET_SSH_USER}@${TARGET_HOST}" \
      "sudo -u ${ORACLE_USER} bash -c '
        export ORACLE_HOME=${ORACLE_HOME}
        export ORACLE_SID=${TARGET_SID}
        export PATH=\${ORACLE_HOME}/bin:\${PATH}
        sqlplus -S / as sysdba <<EOF_SQL
SET PAGESIZE 0 FEEDBACK OFF HEADING OFF
SELECT WALLET_TYPE FROM V\\\$ENCRYPTION_WALLET WHERE ROWNUM=1;
EXIT;
EOF_SQL
'" 2>/dev/null | tr -d '[:space:]')

  if [[ "${CURRENT_STATUS}" == "OPEN" && "${WALLET_TYPE}" != "OPEN_NO_MASTER_KEY" ]]; then
    log "TDE master key already exists. No action required."
    log "Run with --verify-only to see full details."
    exit 0
  fi
fi

# --- Prompt for TDE wallet password (NEVER store in files) ------------------
log ""
log "The TDE master key creation requires the target wallet password."
log "This is the wallet password set when the ODAA Exadata DB Service was provisioned."
log ""
read -r -s -p "Enter target TDE wallet password: " TDE_PASSWORD
echo ""
read -r -s -p "Confirm target TDE wallet password: " TDE_PASSWORD_CONFIRM
echo ""

if [[ "${TDE_PASSWORD}" != "${TDE_PASSWORD_CONFIRM}" ]]; then
  log "ERROR: Passwords do not match. Aborting."
  exit 1
fi

if [[ -z "${TDE_PASSWORD}" ]]; then
  log "ERROR: Password cannot be empty. Aborting."
  exit 1
fi

# --- Create TDE master key --------------------------------------------------
log ""
log "Creating TDE master key in target CDB (${TARGET_SID})..."
log "(Running: ADMINISTER KEY MANAGEMENT SET KEY FORCE KEYSTORE IDENTIFIED BY *** WITH BACKUP)"

ssh -i "${TARGET_SSH_KEY}" \
    -o StrictHostKeyChecking=no \
    "${TARGET_SSH_USER}@${TARGET_HOST}" \
    "sudo -u ${ORACLE_USER} bash -c '
      export ORACLE_HOME=${ORACLE_HOME}
      export ORACLE_SID=${TARGET_SID}
      export PATH=\${ORACLE_HOME}/bin:\${PATH}
      sqlplus -S / as sysdba
    '" << EOF_INTERACT
ADMINISTER KEY MANAGEMENT SET KEY FORCE KEYSTORE IDENTIFIED BY "${TDE_PASSWORD}" WITH BACKUP;
SELECT STATUS, WALLET_TYPE FROM V\$ENCRYPTION_WALLET WHERE ROWNUM=1;
EXIT;
EOF_INTERACT

# Unset password variable
unset TDE_PASSWORD TDE_PASSWORD_CONFIRM

# --- Verify ------------------------------------------------------------------
log ""
log "=== Post-Fix TDE Wallet Verification ==="
ssh -i "${TARGET_SSH_KEY}" \
    -o StrictHostKeyChecking=no \
    "${TARGET_SSH_USER}@${TARGET_HOST}" \
    "sudo -u ${ORACLE_USER} bash -c '
      export ORACLE_HOME=${ORACLE_HOME}
      export ORACLE_SID=${TARGET_SID}
      export PATH=\${ORACLE_HOME}/bin:\${PATH}
      sqlplus -S / as sysdba <<EOF_SQL
SET LINESIZE 120 PAGESIZE 50
PROMPT ── TDE Wallet Status (must NOT be OPEN_NO_MASTER_KEY) ──
SELECT WRL_TYPE, STATUS, WALLET_TYPE, CON_ID FROM V\\\$ENCRYPTION_WALLET ORDER BY CON_ID;
EXIT;
EOF_SQL
'"

log ""
log "================================================================"
log "fix_02_target_tde_master_key.sh COMPLETE"
log "ACTION-04 (TDE Master Key) should now be resolved."
log ""
log "Update Issue-Resolution-Log-ORADB.md:"
log "  - ACTION-04 Status: ✅ Resolved"
log "  - Record date and verification output"
log "================================================================"
