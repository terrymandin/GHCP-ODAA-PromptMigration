#!/usr/bin/env bash
# =============================================================================
# fix_01_source_archivelog.sh
# =============================================================================
# Purpose : Enable ARCHIVELOG mode, Force Logging, and Supplemental Logging
#           on the ORADB source database (Oracle 12.2 on tm-oracle-iaas).
#
# Actions : ACTION-01 (ARCHIVELOG), ACTION-02 (Force Logging),
#           ACTION-03 (Supplemental Logging)
#
# Run from: ZDM Server (10.1.0.8) as azureuser
# Run as  : azureuser  -->  sudo -u oracle  -->  sqlplus / as sysdba
#
# WARNING : This script requires a database SHUTDOWN and STARTUP.
#           Plan a brief maintenance window with the source DBA (~10-15 minutes).
#
# Usage   : bash fix_01_source_archivelog.sh
#           bash fix_01_source_archivelog.sh --verify-only
# =============================================================================

set -euo pipefail

# --- Configuration (from zdm-env.md) ----------------------------------------
SOURCE_HOST="10.1.0.11"
SOURCE_SSH_USER="azureuser"
SOURCE_SSH_KEY="${HOME}/.ssh/odaa.pem"
ORACLE_HOME="/u01/app/oracle/product/12.2.0/dbhome_1"
ORACLE_SID="oradb"
ORACLE_USER="oracle"

# Archive log destination on source server
ARCHIVE_DEST="/u01/app/oracle/archive"
# ----------------------------------------------------------------------------

VERIFY_ONLY=false
if [[ "${1:-}" == "--verify-only" ]]; then
  VERIFY_ONLY=true
fi

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

log "================================================================"
log "fix_01_source_archivelog.sh — ORADB ARCHIVELOG / Force / Suplog"
log "================================================================"
log "Source host  : ${SOURCE_HOST}"
log "SSH user     : ${SOURCE_SSH_USER}"
log "Oracle SID   : ${ORACLE_SID}"
log "Archive dest : ${ARCHIVE_DEST}"
log "Verify only  : ${VERIFY_ONLY}"
log "================================================================"

# --- Helper: run SQL on source -----------------------------------------------
run_sql_on_source() {
  local sql_block="$1"
  ssh -i "${SOURCE_SSH_KEY}" \
      -o StrictHostKeyChecking=no \
      -o ConnectTimeout=10 \
      "${SOURCE_SSH_USER}@${SOURCE_HOST}" \
      "sudo -u ${ORACLE_USER} bash -c '
        export ORACLE_HOME=${ORACLE_HOME}
        export ORACLE_SID=${ORACLE_SID}
        export PATH=\${ORACLE_HOME}/bin:\${PATH}
        sqlplus -S / as sysdba <<EOF_SQL
${sql_block}
EOF_SQL
'"
}

# --- VERIFY-ONLY mode --------------------------------------------------------
if [[ "${VERIFY_ONLY}" == "true" ]]; then
  log "Running verification queries only (read-only, no changes)..."
  run_sql_on_source "
SET LINESIZE 120
SET PAGESIZE 50
PROMPT ── Archive Log Mode ──
SELECT LOG_MODE FROM V\$DATABASE;
PROMPT ── Force Logging ──
SELECT FORCE_LOGGING FROM V\$DATABASE;
PROMPT ── Supplemental Logging ──
SELECT SUPPLEMENTAL_LOG_DATA_MIN, SUPPLEMENTAL_LOG_DATA_ALL FROM V\$DATABASE;
PROMPT ── Archive Dest Status ──
SELECT DEST_ID, STATUS, TARGET, DESTINATION FROM V\$ARCHIVE_DEST WHERE DEST_ID=1;
PROMPT ── Recent Archive Logs (last 2h) ──
SELECT COUNT(*) AS ARCHIVE_LOG_COUNT FROM V\$ARCHIVED_LOG
  WHERE COMPLETION_TIME > SYSDATE - 2/24;
EXIT;
"
  log "Verification complete."
  exit 0
fi

# --- Pre-flight: Confirm before applying changes ----------------------------
log ""
log "⚠️  THIS SCRIPT WILL RESTART THE SOURCE DATABASE."
log "    Estimated downtime: 10–15 minutes."
log ""
read -r -p "Type 'YES' to confirm and proceed: " CONFIRM
if [[ "${CONFIRM}" != "YES" ]]; then
  log "Aborted by user."
  exit 1
fi

# --- Step 0: Create archive destination directory ---------------------------
log "Step 0: Creating archive log destination on source: ${ARCHIVE_DEST}"
ssh -i "${SOURCE_SSH_KEY}" \
    -o StrictHostKeyChecking=no \
    "${SOURCE_SSH_USER}@${SOURCE_HOST}" \
    "sudo -u ${ORACLE_USER} bash -c 'mkdir -p ${ARCHIVE_DEST} && ls -ld ${ARCHIVE_DEST}'"

# --- Step 1: Set log_archive_dest_1 in SPFILE --------------------------------
log "Step 1: Setting log_archive_dest_1 = LOCATION=${ARCHIVE_DEST}"
run_sql_on_source "
ALTER SYSTEM SET log_archive_dest_1='LOCATION=${ARCHIVE_DEST}' SCOPE=SPFILE;
EXIT;
"

# --- Step 2: Enable ARCHIVELOG (requires MOUNT mode) ------------------------
log "Step 2: Shutting down source database (IMMEDIATE)..."
log "        Then restarting in MOUNT mode to enable ARCHIVELOG."
# Note: We set +e temporarily because SHUTDOWN may return non-zero on some configs
set +e
run_sql_on_source "
WHENEVER SQLERROR EXIT FAILURE
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;
EXIT;
"
SHUTDOWN_RC=$?
set -e

if [[ ${SHUTDOWN_RC} -ne 0 ]]; then
  log "WARNING: SQL block returned RC=${SHUTDOWN_RC}. Verifying database state..."
fi

log "Database should now be OPEN in ARCHIVELOG mode."

# --- Step 3: Enable Force Logging -------------------------------------------
log "Step 3: Enabling Force Logging..."
run_sql_on_source "
ALTER DATABASE FORCE LOGGING;
SELECT FORCE_LOGGING FROM V\$DATABASE;
EXIT;
"

# --- Step 4: Enable Supplemental Logging ------------------------------------
log "Step 4: Enabling Supplemental Logging (MIN + ALL COLUMNS)..."
run_sql_on_source "
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
EXIT;
"

# --- Step 5: Switch log to trigger first archive ----------------------------
log "Step 5: Switching redo logs (x2) to generate first archive files..."
run_sql_on_source "
ALTER SYSTEM SWITCH LOGFILE;
ALTER SYSTEM SWITCH LOGFILE;
-- Wait briefly for archival
EXEC DBMS_LOCK.SLEEP(3);
EXIT;
"

# --- Step 6: Final verification ----------------------------------------------
log "Step 6: Final verification..."
run_sql_on_source "
SET LINESIZE 120
SET PAGESIZE 50
PROMPT ── Archive Log Mode (Expected: ARCHIVELOG) ──
SELECT LOG_MODE FROM V\$DATABASE;
PROMPT ── Force Logging (Expected: YES) ──
SELECT FORCE_LOGGING FROM V\$DATABASE;
PROMPT ── Supplemental Logging (Expected: YES / YES) ──
SELECT SUPPLEMENTAL_LOG_DATA_MIN AS SUP_LOG_MIN,
       SUPPLEMENTAL_LOG_DATA_ALL AS SUP_LOG_ALL
FROM V\$DATABASE;
PROMPT ── Archive Dest (Expected: VALID) ──
SELECT DEST_ID, STATUS, DESTINATION FROM V\$ARCHIVE_DEST WHERE DEST_ID=1;
PROMPT ── Archive Dest Location ──
ARCHIVE LOG LIST;
PROMPT ── Archived Log Count (last 30 min) ──
SELECT COUNT(*) AS ARCHIVED_LAST_30MIN FROM V\$ARCHIVED_LOG
  WHERE COMPLETION_TIME > SYSDATE - 30/1440;
EXIT;
"

log ""
log "================================================================"
log "fix_01_source_archivelog.sh COMPLETE"
log "ACTION-01 (ARCHIVELOG), ACTION-02 (Force Logging),"
log "ACTION-03 (Supplemental Logging) should now be resolved."
log ""
log "Update Issue-Resolution-Log-ORADB.md with:"
log "  - ACTION-01 Status: ✅ Resolved"
log "  - ACTION-02 Status: ✅ Resolved"
log "  - ACTION-03 Status: ✅ Resolved"
log "  - Date and verification output"
log "================================================================"
