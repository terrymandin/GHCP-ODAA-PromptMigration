#!/usr/bin/env bash
# =============================================================================
# fix_08_configure_archive_destination.sh
#
# Purpose : Configure the Oracle archive log destination on the source
#           database to point to a path with adequate free space.
#           Source disk has ~8.6 GB free — with ARCHIVELOG mode active,
#           archive logs can fill the default destination quickly during
#           an active migration with Data Guard redo shipping.
#
# Target  : Source database server (10.1.0.11) — executed FROM the ZDM server
#           via SSH. Runs SQL as oracle OS user via sudo.
#
# Run as  : azureuser on ZDM server (10.1.0.8)
# Usage   : ARCHIVE_DEST=/u01/app/oracle/archive bash fix_08_configure_archive_destination.sh
#           OR edit ARCHIVE_DEST below and run directly.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — sourced from zdm-env.md values
# ---------------------------------------------------------------------------
SOURCE_HOST="${SOURCE_HOST:-10.1.0.11}"
SOURCE_SSH_USER="${SOURCE_SSH_USER:-azureuser}"
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-${HOME}/.ssh/odaa.pem}"
ORACLE_USER="${ORACLE_USER:-oracle}"
ORACLE_HOME="${SOURCE_ORACLE_HOME:-/u01/app/oracle/product/12.2.0/dbhome_1}"
ORACLE_SID="${SOURCE_ORACLE_SID:-oradb}"

# Archive log destination — override with env var or edit here
# Choose a path with >= 10 GB free. The /mnt disk on ZDM has 15 GB but source has /u01.
# Check 'df -h' on source first (run_remote_cmd below).
ARCHIVE_DEST="${ARCHIVE_DEST:-/u01/app/oracle/archive}"

LOG_FILE="fix_08_$(date +%Y%m%d_%H%M%S).log"

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"; }
info() { log "INFO  $*"; }
warn() { log "WARN  $*"; }
fail() { log "ERROR $*"; exit 1; }
sep()  { log "----------------------------------------------------------------------"; }

# ---------------------------------------------------------------------------
# Helper: run a remote command as SOURCE_SSH_USER (no sudo-to-oracle needed for shell)
# ---------------------------------------------------------------------------
run_remote_cmd() {
  local cmd="$1"
  ssh -i "${SOURCE_SSH_KEY}" \
      -o StrictHostKeyChecking=no \
      -o ConnectTimeout=15 \
      "${SOURCE_SSH_USER}@${SOURCE_HOST}" \
      "${cmd}" 2>&1
}

# ---------------------------------------------------------------------------
# Helper: run SQL on source via SSH + sudo + base64 encoding
# ---------------------------------------------------------------------------
run_sql_on_source() {
  local sql_block="$1"
  local encoded_sql
  encoded_sql=$(printf '%s\n' "${sql_block}" | base64 -w 0)
  ssh -i "${SOURCE_SSH_KEY}" \
      -o StrictHostKeyChecking=no \
      -o ConnectTimeout=15 \
      "${SOURCE_SSH_USER}@${SOURCE_HOST}" \
      "sudo -u ${ORACLE_USER} bash -c '
        export ORACLE_HOME=${ORACLE_HOME}
        export ORACLE_SID=${ORACLE_SID}
        export PATH=\${ORACLE_HOME}/bin:\${PATH}
        echo \"${encoded_sql}\" | base64 -d | sqlplus -S / as sysdba
      '"
}

# ---------------------------------------------------------------------------
# Step 0: Preflight
# ---------------------------------------------------------------------------
sep
info "Starting fix_08: Configure Archive Log Destination on Source"
info "Source host    : ${SOURCE_HOST}"
info "Archive dest   : ${ARCHIVE_DEST}"
info "Log file       : ${LOG_FILE}"
sep

info "Step 0: Testing SSH connectivity to source..."
run_remote_cmd "hostname" >> "${LOG_FILE}" 2>&1 || fail "Cannot SSH to ${SOURCE_SSH_USER}@${SOURCE_HOST}."
info "SSH to source: OK"

# ---------------------------------------------------------------------------
# Step 1: Check disk space on source
# ---------------------------------------------------------------------------
sep
info "Step 1: Checking disk space on source..."
run_remote_cmd "df -h" | tee -a "${LOG_FILE}"

# ---------------------------------------------------------------------------
# Step 2: Create archive log directory on source
# ---------------------------------------------------------------------------
sep
info "Step 2: Creating archive log directory '${ARCHIVE_DEST}' on source..."
run_remote_cmd "sudo -u ${ORACLE_USER} bash -c 'mkdir -p ${ARCHIVE_DEST} && chmod 750 ${ARCHIVE_DEST} && ls -lad ${ARCHIVE_DEST}'" \
  | tee -a "${LOG_FILE}" || fail "Failed to create archive log directory ${ARCHIVE_DEST} on source."
info "Archive log directory created/verified: ${ARCHIVE_DEST}"

# ---------------------------------------------------------------------------
# Step 3: Set LOG_ARCHIVE_DEST_1 in the database
# ---------------------------------------------------------------------------
sep
info "Step 3: Setting LOG_ARCHIVE_DEST_1 to '${ARCHIVE_DEST}'..."

# Note: LOCATION= value must be embedded here. We base64-encode the whole SQL block
# to avoid single-quote conflicts in the SSH command chain.
ARCHIVE_SQL="
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SYSTEM SET LOG_ARCHIVE_DEST_1='LOCATION=${ARCHIVE_DEST}' SCOPE=BOTH;
ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE_1=ENABLE SCOPE=BOTH;
-- Switch logfile to force archiving to new destination
ALTER SYSTEM SWITCH LOGFILE;
-- Verify
SHOW PARAMETER LOG_ARCHIVE_DEST_1;
ARCHIVE LOG LIST;
EXIT;
"
run_sql_on_source "${ARCHIVE_SQL}" 2>&1 | tee -a "${LOG_FILE}" || \
  fail "Failed to set LOG_ARCHIVE_DEST_1. Check database is in ARCHIVELOG mode (run fix_01 first)."
info "LOG_ARCHIVE_DEST_1 set to: ${ARCHIVE_DEST}"

# ---------------------------------------------------------------------------
# Step 4: Verify archive log is writing to new destination
# ---------------------------------------------------------------------------
sep
info "Step 4: Verifying archive logs are written to new destination..."

VERIFY_SQL="
SET PAGESIZE 20 LINESIZE 120 FEEDBACK OFF
COLUMN NAME FORMAT A60
COLUMN VALUE FORMAT A80
SHOW PARAMETER LOG_ARCHIVE_DEST_1;
ARCHIVE LOG LIST;
EXIT;
"
run_sql_on_source "${VERIFY_SQL}" 2>&1 | tee -a "${LOG_FILE}"

info "Step 4: Checking disk space after logfile switch..."
run_remote_cmd "df -h ${ARCHIVE_DEST}" | tee -a "${LOG_FILE}"

sep
info "✅ Fix 08 complete."
info "   Archive log destination: ${ARCHIVE_DEST}"
info "   Monitor disk usage on source during migration — archive logs will accumulate."
info "   Recommend adding a cron job to purge archived logs older than the standby lag."
sep
info "Log saved to: ${LOG_FILE}"
