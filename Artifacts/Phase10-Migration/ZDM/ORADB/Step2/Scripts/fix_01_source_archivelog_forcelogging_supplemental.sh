#!/usr/bin/env bash
# =============================================================================
# fix_01_source_archivelog_forcelogging_supplemental.sh
#
# Purpose : Enable ARCHIVELOG mode, Force Logging, and Supplemental Logging
#           on the source Oracle database (ORADB).
#
# Target  : Source database server (10.1.0.11) — executed FROM the ZDM server
#           via SSH. The script SSHes to the source as SOURCE_SSH_USER and
#           runs SQL as the oracle OS user via sudo.
#
# ⚠️  IMPORTANT: This script requires a brief database restart to enable
#     ARCHIVELOG mode. Schedule during a maintenance window.
#
# Run as  : azureuser on ZDM server (10.1.0.8)
# Usage   : bash fix_01_source_archivelog_forcelogging_supplemental.sh
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

LOG_FILE="fix_01_$(date +%Y%m%d_%H%M%S).log"

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"; }
info() { log "INFO  $*"; }
warn() { log "WARN  $*"; }
fail() { log "ERROR $*"; exit 1; }
sep()  { log "----------------------------------------------------------------------"; }

# ---------------------------------------------------------------------------
# Helper: run a SQL block on the source via SSH + sudo, using base64 encoding
# to avoid shell quoting conflicts with single-quoted SQL strings.
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
# Step 0: Preflight — confirm SSH connectivity
# ---------------------------------------------------------------------------
sep
info "Starting fix_01: Enable ARCHIVELOG, Force Logging, Supplemental Logging"
info "Source host : ${SOURCE_HOST}"
info "SSH user    : ${SOURCE_SSH_USER}"
info "Oracle SID  : ${ORACLE_SID}"
info "Log file    : ${LOG_FILE}"
sep

info "Step 0: Testing SSH connectivity to source..."
ssh -i "${SOURCE_SSH_KEY}" \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=15 \
    "${SOURCE_SSH_USER}@${SOURCE_HOST}" \
    "hostname" >> "${LOG_FILE}" 2>&1 || fail "Cannot SSH to ${SOURCE_SSH_USER}@${SOURCE_HOST}. Check key and connectivity."
info "SSH to source: OK"

# ---------------------------------------------------------------------------
# Step 1: Check current database mode
# ---------------------------------------------------------------------------
sep
info "Step 1: Checking current database mode..."

CHECK_SQL="
SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF TRIMOUT ON;
SELECT 'LOG_MODE='||LOG_MODE||
       ' FORCE_LOGGING='||FORCE_LOGGING||
       ' SUPLOG_MIN='||SUPPLEMENTAL_LOG_DATA_MIN||
       ' SUPLOG_ALL='||SUPPLEMENTAL_LOG_DATA_ALL
FROM V\$DATABASE;
EXIT;
"
STATUS_OUTPUT=$(run_sql_on_source "${CHECK_SQL}" 2>&1) || true
info "Current status: ${STATUS_OUTPUT}"

if echo "${STATUS_OUTPUT}" | grep -q "LOG_MODE=ARCHIVELOG"; then
  warn "Database is already in ARCHIVELOG mode — skipping STARTUP MOUNT step."
  ALREADY_ARCHIVELOG=true
else
  ALREADY_ARCHIVELOG=false
fi

# ---------------------------------------------------------------------------
# Step 2 (conditional): Enable ARCHIVELOG mode — requires DB restart
# ---------------------------------------------------------------------------
sep
if [ "${ALREADY_ARCHIVELOG}" = "false" ]; then
  info "Step 2: Enabling ARCHIVELOG mode (requires brief DB restart)..."
  info "⚠️  Shutting down source database ${ORACLE_SID}..."

  ARCHIVELOG_SQL="
WHENEVER SQLERROR EXIT SQL.SQLCODE
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;
EXIT;
"
  run_sql_on_source "${ARCHIVELOG_SQL}" 2>&1 | tee -a "${LOG_FILE}" || fail "Failed to enable ARCHIVELOG mode."
  info "ARCHIVELOG mode enabled successfully."
else
  info "Step 2: ARCHIVELOG already enabled — skipping restart."
fi

# ---------------------------------------------------------------------------
# Step 3: Enable Force Logging
# ---------------------------------------------------------------------------
sep
info "Step 3: Enabling Force Logging..."

FORCE_LOGGING_SQL="
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER DATABASE FORCE LOGGING;
EXIT;
"
run_sql_on_source "${FORCE_LOGGING_SQL}" 2>&1 | tee -a "${LOG_FILE}" || fail "Failed to enable Force Logging."
info "Force Logging enabled successfully."

# ---------------------------------------------------------------------------
# Step 4: Enable Supplemental Logging
# ---------------------------------------------------------------------------
sep
info "Step 4: Enabling Supplemental Logging (ALL columns)..."

SUPPLEMENTAL_SQL="
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER SYSTEM SWITCH LOGFILE;
EXIT;
"
run_sql_on_source "${SUPPLEMENTAL_SQL}" 2>&1 | tee -a "${LOG_FILE}" || fail "Failed to enable Supplemental Logging."
info "Supplemental Logging enabled successfully."

# ---------------------------------------------------------------------------
# Step 5: Verification
# ---------------------------------------------------------------------------
sep
info "Step 5: Verification..."

VERIFY_SQL="
SET PAGESIZE 50 LINESIZE 120 FEEDBACK OFF
COLUMN LOG_MODE FORMAT A15
COLUMN FORCE_LOGGING FORMAT A15
COLUMN SUPPLEMENTAL_LOG_DATA_MIN FORMAT A25
COLUMN SUPPLEMENTAL_LOG_DATA_ALL FORMAT A25
SELECT LOG_MODE,
       FORCE_LOGGING,
       SUPPLEMENTAL_LOG_DATA_MIN,
       SUPPLEMENTAL_LOG_DATA_ALL
FROM V\$DATABASE;
ARCHIVE LOG LIST;
EXIT;
"
VERIFY_OUTPUT=$(run_sql_on_source "${VERIFY_SQL}" 2>&1)
info "Verification output:"
echo "${VERIFY_OUTPUT}" | tee -a "${LOG_FILE}"

# Check expected values
PASS=true
echo "${VERIFY_OUTPUT}" | grep -q "ARCHIVELOG"   || { warn "ARCHIVELOG not confirmed in output."; PASS=false; }
echo "${VERIFY_OUTPUT}" | grep -q "YES"          || { warn "FORCE_LOGGING YES not confirmed in output."; PASS=false; }

sep
if [ "${PASS}" = "true" ]; then
  info "✅ All checks passed. Source database is ready for ZDM ONLINE_PHYSICAL migration."
  info "   Next: Run fix_04_target_tde_master_key.sh and fix_05/06 for OCI Object Storage setup."
else
  warn "⚠️  Some checks did not pass. Review the log: ${LOG_FILE}"
  warn "   Inspect V\$DATABASE manually on the source before proceeding."
fi
sep
info "Log saved to: ${LOG_FILE}"
