#!/usr/bin/env bash
# =============================================================================
# fix_source_ORADB.sh
# ZDM Step 2 — Source database remediation for ORADB migration
#
# Resolves: ACTION-01 (ARCHIVELOG), ACTION-02 (Force Logging),
#           ACTION-03 (Supplemental Logging), ACTION-08 (Archive Destination),
#           ACTION-09 (RMAN)
#
# Run from: ZDM server (10.1.0.8) as azureuser
# Requires: SSH key ~/.ssh/odaa.pem and sudo access on source
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Environment — sourced from zdm-env.md
# ---------------------------------------------------------------------------
SOURCE_HOST="10.1.0.11"
SOURCE_SSH_USER="azureuser"
SOURCE_SSH_KEY="${HOME}/.ssh/odaa.pem"
ORACLE_USER="oracle"
ORACLE_HOME="/u01/app/oracle/product/12.2.0/dbhome_1"
ORACLE_SID="oradb"

# Archive log destination path (separate mount or existing path with space)
# Discovery showed archive dest configured to ORACLE_HOME/dbs/arch but disk is tight.
# Set to /u01/app/oracle/fast_recovery_area unless overridden.
ARCHIVE_DEST="/u01/app/oracle/fast_recovery_area"

LOG_FILE="$(dirname "$0")/../Logs/fix_source_ORADB_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")"

log() { echo "[$(date +%Y-%m-%dT%H:%M:%S)] $*" | tee -a "${LOG_FILE}"; }
log_section() { log ""; log "========================================"; log "$*"; log "========================================"; }

# ---------------------------------------------------------------------------
# Helper: run SQL on source via SSH + sudo, using base64 to avoid quoting issues
# ---------------------------------------------------------------------------
run_sql_on_source() {
  local sql_block="$1"
  local encoded_sql
  encoded_sql=$(printf '%s\n' "${sql_block}" | base64 -w 0)
  ssh -i "${SOURCE_SSH_KEY}" \
      -o StrictHostKeyChecking=no \
      -o ConnectTimeout=30 \
      "${SOURCE_SSH_USER}@${SOURCE_HOST}" \
      "sudo -u ${ORACLE_USER} bash -c '
        export ORACLE_HOME=${ORACLE_HOME}
        export ORACLE_SID=${ORACLE_SID}
        export PATH=\${ORACLE_HOME}/bin:\${PATH}
        echo \"${encoded_sql}\" | base64 -d | sqlplus -S / as sysdba
      '"
}

# Helper: run shell command on source via SSH
run_shell_on_source() {
  ssh -i "${SOURCE_SSH_KEY}" \
      -o StrictHostKeyChecking=no \
      -o ConnectTimeout=30 \
      "${SOURCE_SSH_USER}@${SOURCE_HOST}" \
      "$@"
}

# ---------------------------------------------------------------------------
# Verify SSH connectivity before doing anything
# ---------------------------------------------------------------------------
log_section "PRE-CHECK: Verify SSH connectivity to source"
if ! run_shell_on_source "echo 'SSH OK'"; then
  log "ERROR: Cannot SSH to ${SOURCE_SSH_USER}@${SOURCE_HOST} with key ${SOURCE_SSH_KEY}"
  exit 1
fi
log "SSH connection to source verified."

# ---------------------------------------------------------------------------
# PRE-CHECK: Current database mode
# ---------------------------------------------------------------------------
log_section "PRE-CHECK: Current source database status"
PRECHECK_SQL="
SET PAGESIZE 0 FEEDBACK OFF
SELECT 'LOG_MODE='||LOG_MODE FROM V\$DATABASE;
SELECT 'FORCE_LOGGING='||FORCE_LOGGING FROM V\$DATABASE;
SELECT 'SUPPLEMENTAL_MIN='||SUPPLEMENTAL_LOG_DATA_MIN FROM V\$DATABASE;
SELECT 'SUPPLEMENTAL_ALL='||SUPPLEMENTAL_LOG_DATA_ALL FROM V\$DATABASE;
SELECT 'OPEN_MODE='||OPEN_MODE FROM V\$DATABASE;
EXIT;
"
run_sql_on_source "${PRECHECK_SQL}" | tee -a "${LOG_FILE}"

# ---------------------------------------------------------------------------
# ACTION-08: Ensure archive destination directory exists on source
#            (must be done BEFORE enabling ARCHIVELOG)
# ---------------------------------------------------------------------------
log_section "ACTION-08: Prepare archive log destination directory"
log "Target archive destination: ${ARCHIVE_DEST}"

# Check disk space first
run_shell_on_source "df -h /u01/app/oracle" | tee -a "${LOG_FILE}"

# Create directory if it doesn't exist
run_shell_on_source "sudo -u ${ORACLE_USER} bash -c '
  mkdir -p ${ARCHIVE_DEST}
  chmod 750 ${ARCHIVE_DEST}
  echo \"Directory ${ARCHIVE_DEST} ready. Free space:\"
  df -h ${ARCHIVE_DEST}
'"

log "ACTION-08 complete."

# ---------------------------------------------------------------------------
# ACTION-01: Enable ARCHIVELOG mode (requires database restart)
# ---------------------------------------------------------------------------
log_section "ACTION-01: Enable ARCHIVELOG Mode (requires database restart)"
log "⚠️  This will restart the source database. Coordinate with stakeholders before proceeding."
log "Sleeping 10s — press Ctrl+C to abort..."
sleep 10

ARCHIVELOG_SQL="
SET PAGESIZE 0 FEEDBACK OFF
-- Set archive destination before enabling ARCHIVELOG
ALTER SYSTEM SET log_archive_dest_1='LOCATION=${ARCHIVE_DEST}' SCOPE=SPFILE;
-- Restart sequence
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;
-- Switch one logfile to generate first archive log
ALTER SYSTEM SWITCH LOGFILE;
EXIT;
"
run_sql_on_source "${ARCHIVELOG_SQL}" | tee -a "${LOG_FILE}"

# Verify ARCHIVELOG
log "Verifying ARCHIVELOG mode..."
VERIFY_ARCHIVELOG_SQL="
SET PAGESIZE 0 FEEDBACK OFF
SELECT 'LOG_MODE='||LOG_MODE FROM V\$DATABASE;
SELECT 'OPEN_MODE='||OPEN_MODE FROM V\$DATABASE;
EXIT;
"
RESULT=$(run_sql_on_source "${VERIFY_ARCHIVELOG_SQL}")
echo "${RESULT}" | tee -a "${LOG_FILE}"
if echo "${RESULT}" | grep -q "LOG_MODE=ARCHIVELOG"; then
  log "✅ ACTION-01 VERIFIED: Database is in ARCHIVELOG mode."
else
  log "❌ ACTION-01 FAILED: Database does not appear to be in ARCHIVELOG mode. Check logs."
  exit 1
fi

# ---------------------------------------------------------------------------
# ACTION-02: Enable Force Logging
# ---------------------------------------------------------------------------
log_section "ACTION-02: Enable Force Logging"
FORCE_LOGGING_SQL="
SET PAGESIZE 0 FEEDBACK OFF
ALTER DATABASE FORCE LOGGING;
SELECT 'FORCE_LOGGING='||FORCE_LOGGING FROM V\$DATABASE;
EXIT;
"
run_sql_on_source "${FORCE_LOGGING_SQL}" | tee -a "${LOG_FILE}"

VERIFY_FL=$(run_sql_on_source "SET PAGESIZE 0 FEEDBACK OFF
SELECT 'FORCE_LOGGING='||FORCE_LOGGING FROM V\$DATABASE;
EXIT;")
echo "${VERIFY_FL}" | tee -a "${LOG_FILE}"
if echo "${VERIFY_FL}" | grep -q "FORCE_LOGGING=YES"; then
  log "✅ ACTION-02 VERIFIED: Force logging is enabled."
else
  log "❌ ACTION-02 FAILED: Force logging not enabled. Check V\$DATABASE."
  exit 1
fi

# ---------------------------------------------------------------------------
# ACTION-03: Enable Minimum + All Supplemental Logging
# ---------------------------------------------------------------------------
log_section "ACTION-03: Enable Supplemental Logging"
SUPPLEMENTAL_SQL="
SET PAGESIZE 0 FEEDBACK OFF
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER SYSTEM SWITCH LOGFILE;
SELECT 'SUPPLEMENTAL_MIN='||SUPPLEMENTAL_LOG_DATA_MIN FROM V\$DATABASE;
SELECT 'SUPPLEMENTAL_ALL='||SUPPLEMENTAL_LOG_DATA_ALL FROM V\$DATABASE;
EXIT;
"
run_sql_on_source "${SUPPLEMENTAL_SQL}" | tee -a "${LOG_FILE}"

VERIFY_SL=$(run_sql_on_source "SET PAGESIZE 0 FEEDBACK OFF
SELECT 'SUPPLEMENTAL_MIN='||SUPPLEMENTAL_LOG_DATA_MIN,
       'SUPPLEMENTAL_ALL='||SUPPLEMENTAL_LOG_DATA_ALL
FROM V\$DATABASE;
EXIT;")
echo "${VERIFY_SL}" | tee -a "${LOG_FILE}"
if echo "${VERIFY_SL}" | grep -q "SUPPLEMENTAL_MIN=YES"; then
  log "✅ ACTION-03 VERIFIED: Supplemental logging is enabled."
else
  log "❌ ACTION-03 FAILED: Supplemental logging not confirmed. Check V\$DATABASE."
  exit 1
fi

# ---------------------------------------------------------------------------
# ACTION-09: Configure RMAN on source (backup safety net before migration)
# ---------------------------------------------------------------------------
log_section "ACTION-09: Configure RMAN on source"
FRA_PATH="/u01/app/oracle/fast_recovery_area"
run_sql_on_source "SET PAGESIZE 0 FEEDBACK OFF
ALTER SYSTEM SET db_recovery_file_dest='${FRA_PATH}' SCOPE=BOTH;
ALTER SYSTEM SET db_recovery_file_dest_size=5G SCOPE=BOTH;
EXIT;" | tee -a "${LOG_FILE}"

# Configure RMAN via SSH (rman does not use SQL*Plus)
run_shell_on_source "sudo -u ${ORACLE_USER} bash -c '
  export ORACLE_HOME=${ORACLE_HOME}
  export ORACLE_SID=${ORACLE_SID}
  export PATH=\${ORACLE_HOME}/bin:\${PATH}
  rman TARGET / <<EOF
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO \"${FRA_PATH}/%F\";
CONFIGURE DEFAULT DEVICE TYPE TO DISK;
CONFIGURE BACKUP OPTIMIZATION ON;
CONFIGURE RETENTION POLICY TO REDUNDANCY 1;
SHOW ALL;
EXIT;
EOF
'" | tee -a "${LOG_FILE}"

log "✅ ACTION-09 COMPLETE: RMAN configured with FRA at ${FRA_PATH}."

# ---------------------------------------------------------------------------
# FINAL STATUS CHECK
# ---------------------------------------------------------------------------
log_section "FINAL STATUS: Source database configuration summary"
FINAL_SQL="
SET PAGESIZE 100 LINESIZE 120 FEEDBACK OFF
COL property_name FORMAT A35
COL value FORMAT A25
SELECT
  'LOG_MODE'               AS property_name, LOG_MODE               AS value FROM V\$DATABASE UNION ALL
SELECT
  'FORCE_LOGGING'          , FORCE_LOGGING          FROM V\$DATABASE UNION ALL
SELECT
  'SUPPLEMENTAL_LOG_MIN'   , SUPPLEMENTAL_LOG_DATA_MIN FROM V\$DATABASE UNION ALL
SELECT
  'SUPPLEMENTAL_LOG_ALL'   , SUPPLEMENTAL_LOG_DATA_ALL FROM V\$DATABASE UNION ALL
SELECT
  'OPEN_MODE'              , OPEN_MODE              FROM V\$DATABASE UNION ALL
SELECT
  'DB_NAME'                , NAME                   FROM V\$DATABASE;
EXIT;
"
run_sql_on_source "${FINAL_SQL}" | tee -a "${LOG_FILE}"

log ""
log "fix_source_ORADB.sh completed. Log saved to: ${LOG_FILE}"
log ""
log "Next steps:"
log "  1. Run fix_target_ORADB.sh  — configure TDE master key on target"
log "  2. Run fix_zdm_server_ORADB.sh — discover OSS namespace, create bucket, init cred store"
log "  3. Update Issue-Resolution-Log-ORADB.md with results"
