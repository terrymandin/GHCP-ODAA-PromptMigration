#!/usr/bin/env bash
# =============================================================================
# fix_open_target_db.sh
# Purpose : Check the open mode of the ODAA target database (oradb011) and,
#           if it is in MOUNT state, offer to open it to READ WRITE.
# Run as  : zdmuser on the ZDM server (tm-vm-odaa-oracle-jumpbox / 10.1.0.8)
# Step    : ZDM Migration Step 2 — Fix Issues
# Issue   : Issue 3 (Target database not open during discovery)
# =============================================================================
# NOTE: Opening the target database to READ WRITE is required before ZDM can
#       run ZDM_VALIDATE_TGT. DBA approval should be obtained before proceeding
#       with the open step. This script prompts for confirmation before making
#       any changes.
# =============================================================================

set -euo pipefail

# --- User guard: must run as zdmuser ---
if [[ "$(whoami)" != "zdmuser" ]]; then
  echo "ERROR: This script must be run as zdmuser. Current user: $(whoami)"
  echo "       Switch with: sudo su - zdmuser"
  exit 1
fi

# =============================================================================
# Configuration — values from zdm-env.md
# =============================================================================
TARGET_HOST="10.0.1.160"
TARGET_SSH_USER="opc"
TARGET_SSH_KEY="${HOME}/.ssh/odaa.pem"
ORACLE_USER="oracle"
TARGET_ORACLE_HOME_BASE="/u02/app/oracle/product/19.0.0.0"
TARGET_INSTANCE_NAME="oradb011"

LOG_DIR="${HOME}/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/fix_open_target_db_$(date +%Y%m%d_%H%M%S).log"

# =============================================================================
# Logging helpers
# =============================================================================
log()  { echo "[$(date '+%H:%M:%S')] $*" | tee -a "${LOG_FILE}"; }
pass() { echo "[$(date '+%H:%M:%S')] ✅ PASS  $*" | tee -a "${LOG_FILE}"; }
fail() { echo "[$(date '+%H:%M:%S')] ❌ FAIL  $*" | tee -a "${LOG_FILE}"; }
warn() { echo "[$(date '+%H:%M:%S')] ⚠️  WARN  $*" | tee -a "${LOG_FILE}"; }
info() { echo "[$(date '+%H:%M:%S')] ℹ️  INFO  $*" | tee -a "${LOG_FILE}"; }

log "================================================================"
log "fix_open_target_db.sh — Open ODAA Target Database"
log "Running as: $(whoami)  on  $(hostname)"
log "Target:     ${TARGET_SSH_USER}@${TARGET_HOST}"
log "Instance:   ${TARGET_INSTANCE_NAME}"
log "Log:        ${LOG_FILE}"
log "================================================================"

# =============================================================================
# Step 1: Prompt for Oracle Home suffix
# =============================================================================
log ""
log "--- Step 1: Confirm Target Oracle Home Path ---"
echo "Enter Oracle Home suffix [1 or 2] (default: 1):"
read -r DBHOME_SUFFIX
DBHOME_SUFFIX="${DBHOME_SUFFIX:-1}"

if [[ "${DBHOME_SUFFIX}" != "1" && "${DBHOME_SUFFIX}" != "2" ]]; then
  fail "Invalid input '${DBHOME_SUFFIX}'. Must be 1 or 2. Exiting."
  exit 1
fi

TARGET_ORACLE_HOME="${TARGET_ORACLE_HOME_BASE}/dbhome_${DBHOME_SUFFIX}"
info "Using Oracle Home: ${TARGET_ORACLE_HOME}"
info "Using Oracle SID: ${TARGET_INSTANCE_NAME}"

# =============================================================================
# Step 2: Test SSH connectivity
# =============================================================================
log ""
log "--- Step 2: Test SSH connectivity to target (${TARGET_HOST}) ---"
if ! ssh -i "${TARGET_SSH_KEY}" \
         -o StrictHostKeyChecking=no \
         -o ConnectTimeout=10 \
         "${TARGET_SSH_USER}@${TARGET_HOST}" \
         "sudo -u ${ORACLE_USER} whoami" 2>>"${LOG_FILE}" | grep -q "^oracle$"; then
  fail "Cannot SSH to ${TARGET_SSH_USER}@${TARGET_HOST} and sudo to ${ORACLE_USER}."
  exit 1
fi
pass "SSH connectivity to target confirmed."

# =============================================================================
# Step 3: Check current database open mode
#         Uses base64 to safely pass the SQL block through SSH/sudo quoting.
# =============================================================================
log ""
log "--- Step 3: Check current database open mode ---"

SQL_CHECK_OPEN="SELECT STATUS, OPEN_MODE FROM V\$INSTANCE, V\$DATABASE;"
ENCODED_SQL=$(printf '%s\n' "${SQL_CHECK_OPEN}" | base64 -w 0)

OPEN_MODE_OUTPUT=$(ssh -i "${TARGET_SSH_KEY}" \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=15 \
    "${TARGET_SSH_USER}@${TARGET_HOST}" \
    "sudo -u ${ORACLE_USER} bash -c '
      export ORACLE_HOME=${TARGET_ORACLE_HOME}
      export ORACLE_SID=${TARGET_INSTANCE_NAME}
      export PATH=\${ORACLE_HOME}/bin:\${PATH}
      echo \"${ENCODED_SQL}\" | base64 -d | sqlplus -S / as sysdba
    '" 2>&1 || true)

log "SQL output: ${OPEN_MODE_OUTPUT}"

# =============================================================================
# Step 4: Parse open mode
# =============================================================================
log ""
log "--- Step 4: Evaluate database status ---"

if echo "${OPEN_MODE_OUTPUT}" | grep -qiE "ORA-01034|ORA-01219|shutdown|idle"; then
  DB_STATE="SHUTDOWN"
elif echo "${OPEN_MODE_OUTPUT}" | grep -qi "MOUNTED"; then
  DB_STATE="MOUNTED"
elif echo "${OPEN_MODE_OUTPUT}" | grep -qi "READ WRITE"; then
  DB_STATE="OPEN"
elif echo "${OPEN_MODE_OUTPUT}" | grep -qi "READ ONLY"; then
  DB_STATE="READONLY"
else
  DB_STATE="UNKNOWN"
fi

info "Detected database state: ${DB_STATE}"

case "${DB_STATE}" in
  "OPEN")
    pass "Database ${TARGET_INSTANCE_NAME} is already in READ WRITE mode."
    pass "Issue 3 is NOT a blocker — database is open."
    log ""
    log "================================================================"
    log "SUMMARY: No action required. Database already open READ WRITE."
    log "================================================================"
    log "fix_open_target_db.sh completed. Log: ${LOG_FILE}"
    exit 0
    ;;
  "READONLY")
    warn "Database ${TARGET_INSTANCE_NAME} is in READ ONLY mode."
    warn "ZDM requires READ WRITE access. Proceed with opening READ WRITE below."
    ;;
  "MOUNTED")
    warn "Database ${TARGET_INSTANCE_NAME} is in MOUNT state. Must be opened before ZDM can validate."
    ;;
  "SHUTDOWN")
    warn "Database ${TARGET_INSTANCE_NAME} appears to be shut down or not started."
    warn "Startup and open will be attempted if you confirm."
    ;;
  *)
    warn "Could not determine database state from SQL output. Review raw output above."
    warn "Proceeding with open attempt if confirmed."
    ;;
esac

# =============================================================================
# Step 5: Prompt for DBA approval before making changes
# =============================================================================
log ""
log "--- Step 5: DBA Approval Required ---"
echo ""
echo "Current database state: ${DB_STATE}"
echo "Action to perform: Open ODAA target database (${TARGET_INSTANCE_NAME}) to READ WRITE"
echo ""
echo "This will run the following SQL as oracle on ${TARGET_HOST}:"
case "${DB_STATE}" in
  "MOUNTED"|"READONLY")
    echo "  ALTER DATABASE OPEN;"
    ;;
  "SHUTDOWN")
    echo "  STARTUP;"
    echo "  (or STARTUP MOUNT; ALTER DATABASE OPEN;)"
    ;;
esac
echo ""
echo "Do you have DBA approval to open this database? [yes/no] (default: no):"
read -r DBA_APPROVAL
DBA_APPROVAL="${DBA_APPROVAL:-no}"

if [[ "${DBA_APPROVAL,,}" != "yes" ]]; then
  warn "DBA approval not confirmed. No changes made."
  warn "Obtain DBA approval and re-run, or manually open the database."
  log "fix_open_target_db.sh aborted at DBA approval step. Log: ${LOG_FILE}"
  exit 0
fi

# =============================================================================
# Step 6: Open the database
# =============================================================================
log ""
log "--- Step 6: Open target database (DBA-approved) ---"

if [[ "${DB_STATE}" == "SHUTDOWN" ]]; then
  SQL_OPEN_BLOCK="STARTUP;
SELECT STATUS, OPEN_MODE FROM V\$INSTANCE, V\$DATABASE;
EXIT;"
else
  SQL_OPEN_BLOCK="ALTER DATABASE OPEN;
SELECT STATUS, OPEN_MODE FROM V\$INSTANCE, V\$DATABASE;
EXIT;"
fi

ENCODED_OPEN=$(printf '%s\n' "${SQL_OPEN_BLOCK}" | base64 -w 0)

OPEN_RESULT=$(ssh -i "${TARGET_SSH_KEY}" \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=60 \
    "${TARGET_SSH_USER}@${TARGET_HOST}" \
    "sudo -u ${ORACLE_USER} bash -c '
      export ORACLE_HOME=${TARGET_ORACLE_HOME}
      export ORACLE_SID=${TARGET_INSTANCE_NAME}
      export PATH=\${ORACLE_HOME}/bin:\${PATH}
      echo \"${ENCODED_OPEN}\" | base64 -d | sqlplus -S / as sysdba
    '" 2>&1 || true)

log "ALTER DATABASE OPEN output:"
log "${OPEN_RESULT}"

# =============================================================================
# Step 7: Verify the database is now open READ WRITE
# =============================================================================
log ""
log "--- Step 7: Verify database is now READ WRITE ---"

SQL_VERIFY="SELECT OPEN_MODE FROM V\$DATABASE;"
ENCODED_VERIFY=$(printf '%s\n' "${SQL_VERIFY}" | base64 -w 0)

VERIFY_OUTPUT=$(ssh -i "${TARGET_SSH_KEY}" \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=15 \
    "${TARGET_SSH_USER}@${TARGET_HOST}" \
    "sudo -u ${ORACLE_USER} bash -c '
      export ORACLE_HOME=${TARGET_ORACLE_HOME}
      export ORACLE_SID=${TARGET_INSTANCE_NAME}
      export PATH=\${ORACLE_HOME}/bin:\${PATH}
      echo \"${ENCODED_VERIFY}\" | base64 -d | sqlplus -S / as sysdba
    '" 2>&1 || true)

log "Verification output: ${VERIFY_OUTPUT}"

if echo "${VERIFY_OUTPUT}" | grep -qi "READ WRITE"; then
  pass "Database ${TARGET_INSTANCE_NAME} is now READ WRITE."
  ISSUE3_RESULT="RESOLVED"
else
  fail "Database does not appear to be READ WRITE. Review SQL output above."
  fail "You may need to check for ORA- errors and consult the DBA."
  ISSUE3_RESULT="FAILED"
fi

# =============================================================================
# Summary
# =============================================================================
log ""
log "================================================================"
log "SUMMARY"
log "================================================================"
if [[ "${ISSUE3_RESULT}" == "RESOLVED" ]]; then
  pass "Issue 3 RESOLVED: Target database ${TARGET_INSTANCE_NAME} is READ WRITE on ${TARGET_HOST}"
else
  fail "Issue 3 NOT RESOLVED: Database did not reach READ WRITE state. Manual intervention required."
fi
log ""
log "Next steps:"
log "  1. Run verify_fixes.sh to confirm all blocker checks pass."
log "  2. If TDE investigation is needed, consult Issue 4 in the Issue Resolution Log."
log ""
log "fix_open_target_db.sh completed. Log: ${LOG_FILE}"
