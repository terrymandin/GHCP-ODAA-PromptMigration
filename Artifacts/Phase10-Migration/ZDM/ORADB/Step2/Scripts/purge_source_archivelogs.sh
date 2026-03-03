#!/usr/bin/env bash
# =============================================================================
#  purge_source_archivelogs.sh
#  ZDM Migration Step 2 — Issue 4 Remediation
#  Purges obsolete archivelogs from the source database's Fast Recovery Area
#  to reduce the root filesystem usage below safe threshold (< 75%).
#  Uses RMAN "DELETE ARCHIVELOG ALL BACKED UP" to avoid deleting logs
#  that have not yet been backed up.
#
#  Database  : ORADB (oradb / ORADB1)
#  Source    : tm-oracle-iaas (10.1.0.11)
#  Run as    : zdmuser on ZDM server (tm-vm-odaa-oracle-jumpbox / 10.1.0.8)
#
#  ⚠️  WARNING: RMAN archivelog deletion is IRREVERSIBLE.
#     This script only deletes logs already completed before SYSDATE-1 AND
#     backed up at least once. DO NOT run during an active ZDM migration.
# =============================================================================

set -euo pipefail

# ── User Guard ────────────────────────────────────────────────────────────────
if [[ "$(whoami)" != "zdmuser" ]]; then
  echo "ERROR: This script must be run as zdmuser. Current user: $(whoami)"
  echo "       Switch with: sudo su - zdmuser"
  exit 1
fi

# =============================================================================
# Configuration
# =============================================================================
DATABASE_NAME="ORADB"
SOURCE_HOST="10.1.0.11"
SOURCE_SSH_USER="azureuser"
SOURCE_SSH_KEY="${HOME}/.ssh/odaa.pem"
ORACLE_USER="oracle"
ORACLE_HOME="/u01/app/oracle/product/12.2.0/dbhome_1"
ORACLE_SID="oradb"

# Disk space threshold — warn if root FS still above this after purge
DISK_WARN_PCT=80
DISK_TARGET_PCT=75

LOG_DIR="${HOME}/Artifacts/Phase10-Migration/ZDM/${DATABASE_NAME}/Step2/Logs"
LOG_FILE="${LOG_DIR}/purge_source_archivelogs_$(date +%Y%m%d_%H%M%S).log"

mkdir -p "${LOG_DIR}"
exec > >(tee -a "${LOG_FILE}") 2>&1

# =============================================================================
# Helper functions
# =============================================================================
pass() { echo "  ✅ PASS: $1"; }
fail() { echo "  ❌ FAIL: $1"; }
warn() { echo "  ⚠️  WARN: $1"; }
info() { echo "  ℹ️  INFO: $1"; }
step() { echo ""; echo "── Step $1: $2 ──"; }

# ---------------------------------------------------------------------------
# run_rman_on_source — executes an RMAN script block on the source via SSH.
# Uses base64 encoding to safely pass the RMAN block through SSH+sudo quoting.
# ---------------------------------------------------------------------------
run_rman_on_source() {
  local rman_block="$1"
  local encoded_rman
  encoded_rman=$(printf '%s\n' "${rman_block}" | base64 -w 0)
  ssh -i "${SOURCE_SSH_KEY}" \
      -o StrictHostKeyChecking=no \
      -o ConnectTimeout=15 \
      "${SOURCE_SSH_USER}@${SOURCE_HOST}" \
      "sudo -u ${ORACLE_USER} bash -c '
        export ORACLE_HOME=${ORACLE_HOME}
        export ORACLE_SID=${ORACLE_SID}
        export PATH=\${ORACLE_HOME}/bin:\${PATH}
        echo \"${encoded_rman}\" | base64 -d | rman target /
      '"
}

# ---------------------------------------------------------------------------
# run_sql_on_source — executes a SQL block on source via SSH (base64-encoded).
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

echo "=============================================================="
echo "  ZDM Step 2: Purge Source Archivelogs"
echo "  Database  : ${DATABASE_NAME} (${ORACLE_SID})"
echo "  Source    : ${SOURCE_SSH_USER}@${SOURCE_HOST}"
echo "  Timestamp : $(date)"
echo "  Log       : ${LOG_FILE}"
echo "=============================================================="
echo ""
echo "  ⚠️  This script deletes archivelogs that have been backed up"
echo "     and are older than 1 day. DO NOT run during an active ZDM migration."
echo ""
echo "  Press Ctrl+C within 5 seconds to cancel..."
sleep 5

# =============================================================================
# Step 1: Check SSH connectivity to source
# =============================================================================
step "1" "Checking SSH connectivity to source (${SOURCE_HOST})"

if ! ssh -i "${SOURCE_SSH_KEY}" \
         -o StrictHostKeyChecking=no \
         -o ConnectTimeout=10 \
         "${SOURCE_SSH_USER}@${SOURCE_HOST}" "echo ok" &>/dev/null; then
  fail "Cannot SSH to source ${SOURCE_SSH_USER}@${SOURCE_HOST}"
  echo "    Verify SSH key: ${SOURCE_SSH_KEY}"
  echo "    Test: ssh -i ${SOURCE_SSH_KEY} ${SOURCE_SSH_USER}@${SOURCE_HOST} echo ok"
  exit 1
fi
pass "SSH connectivity to source confirmed"

# =============================================================================
# Step 2: Check current disk usage on source
# =============================================================================
step "2" "Checking current disk usage on source /"

DISK_BEFORE=$(ssh -i "${SOURCE_SSH_KEY}" \
  -o StrictHostKeyChecking=no \
  -o ConnectTimeout=10 \
  "${SOURCE_SSH_USER}@${SOURCE_HOST}" "df -h /" 2>/dev/null | tail -1)

DISK_PCT_BEFORE=$(echo "${DISK_BEFORE}" | awk '{print $5}' | tr -d '%')

info "Disk before purge: ${DISK_BEFORE}"

if [[ "${DISK_PCT_BEFORE}" -lt "${DISK_TARGET_PCT}" ]]; then
  info "Disk is at ${DISK_PCT_BEFORE}% — already below target of ${DISK_TARGET_PCT}%. Proceeding anyway."
fi

# =============================================================================
# Step 3: Show archivelog status before purge
# =============================================================================
step "3" "Querying archivelog status on source"

ARCHIVELOG_STATUS=$(run_sql_on_source "
SET PAGESIZE 50
SET LINESIZE 100
SET HEADING ON
COLUMN LOG_MODE FORMAT A15
COLUMN ARCHIVELOG_CHANGE# FORMAT 999999999999
SELECT LOG_MODE, ARCHIVELOG_CHANGE# FROM V\$DATABASE;
SELECT DEST_NAME, STATUS, DEST_ID FROM V\$ARCHIVE_DEST WHERE STATUS='VALID' AND TARGET='PRIMARY';
EXIT;
")
echo "${ARCHIVELOG_STATUS}"

# =============================================================================
# Step 4: Show FRA usage before purge
# =============================================================================
step "4" "Checking Fast Recovery Area usage"

FRA_STATUS=$(run_sql_on_source "
SET PAGESIZE 50
SET LINESIZE 120
COLUMN NAME FORMAT A60
COLUMN SPACE_LIMIT FORMAT 9999999999
COLUMN SPACE_USED FORMAT 9999999999
COLUMN SPACE_RECLAIMABLE FORMAT 9999999999
COLUMN NUMBER_OF_FILES FORMAT 999
SELECT NAME,
       SPACE_LIMIT/1024/1024 AS LIMIT_MB,
       SPACE_USED/1024/1024 AS USED_MB,
       SPACE_RECLAIMABLE/1024/1024 AS RECLAIMABLE_MB,
       NUMBER_OF_FILES
FROM V\$RECOVERY_FILE_DEST;
EXIT;
")
echo "${FRA_STATUS}"

# =============================================================================
# Step 5: Count archivelogs eligible for deletion
# =============================================================================
step "5" "Counting archivelogs eligible for deletion (BACKED UP, completed before SYSDATE-1)"

ARCHIVELOG_COUNT=$(run_rman_on_source "
LIST ARCHIVELOG ALL BACKED UP 1 TIMES COMPLETED BEFORE 'SYSDATE-1';
EXIT;
")
echo "${ARCHIVELOG_COUNT}"

# =============================================================================
# Step 6: Execute RMAN archivelog purge
# =============================================================================
step "6" "Executing RMAN archivelog purge"

info "Deleting archivelogs: BACKED UP 1+ times AND completed before SYSDATE-1"

RMAN_OUTPUT=$(run_rman_on_source "
CROSSCHECK ARCHIVELOG ALL;
DELETE NOPROMPT ARCHIVELOG ALL BACKED UP 1 TIMES COMPLETED BEFORE 'SYSDATE-1';
EXIT;
")
echo "${RMAN_OUTPUT}"

# Check for RMAN errors
if echo "${RMAN_OUTPUT}" | grep -qi "RMAN-\|ORA-"; then
  RMAN_ERRORS=$(echo "${RMAN_OUTPUT}" | grep -i "RMAN-\|ORA-" || true)
  warn "RMAN reported errors/warnings — review output above:"
  echo "    ${RMAN_ERRORS}"
else
  pass "RMAN purge completed without errors"
fi

# =============================================================================
# Step 7: Check disk usage after purge
# =============================================================================
step "7" "Checking disk usage after purge"

DISK_AFTER=$(ssh -i "${SOURCE_SSH_KEY}" \
  -o StrictHostKeyChecking=no \
  -o ConnectTimeout=10 \
  "${SOURCE_SSH_USER}@${SOURCE_HOST}" "df -h /" 2>/dev/null | tail -1)

DISK_PCT_AFTER=$(echo "${DISK_AFTER}" | awk '{print $5}' | tr -d '%')

info "Disk after purge:  ${DISK_AFTER}"
info "Disk before purge: ${DISK_BEFORE}"

FREED_PCT=$((DISK_PCT_BEFORE - DISK_PCT_AFTER))
if [[ "${FREED_PCT}" -gt 0 ]]; then
  pass "Freed approximately ${FREED_PCT}% disk space (${DISK_PCT_BEFORE}% → ${DISK_PCT_AFTER}%)"
else
  info "No significant disk space reclaimed — archivelogs may not have been backed up yet"
fi

if [[ "${DISK_PCT_AFTER}" -gt "${DISK_WARN_PCT}" ]]; then
  warn "Source root disk is still at ${DISK_PCT_AFTER}% (threshold: ${DISK_WARN_PCT}%)"
  echo ""
  echo "  Additional options to free space:"
  echo "    1. Expand the Azure VM OS disk (requires VM restart or online resize)"
  echo "    2. Delete other large files on /"
  echo "    3. Move Oracle FRA to a separate mount point"
  echo ""
  echo "  Check largest directories:"
  ssh -i "${SOURCE_SSH_KEY}" \
    -o StrictHostKeyChecking=no \
    "${SOURCE_SSH_USER}@${SOURCE_HOST}" \
    "sudo du -sh /u01/app/oracle/fast_recovery_area/* 2>/dev/null | sort -rh | head -10" || true
else
  pass "Source root disk is at ${DISK_PCT_AFTER}% — within safe threshold (< ${DISK_WARN_PCT}%)"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "=============================================================="
echo "  Archivelog Purge Complete"
echo "  Source disk before : ${DISK_PCT_BEFORE}%"
echo "  Source disk after  : ${DISK_PCT_AFTER}%"
if [[ "${DISK_PCT_AFTER}" -le "${DISK_WARN_PCT}" ]]; then
  echo "  Status             : ✅ Disk within safe threshold"
else
  echo "  Status             : ⚠️  Disk still above ${DISK_WARN_PCT}% — monitor closely"
fi
echo "  Log                : ${LOG_FILE}"
echo "=============================================================="
echo ""
echo "purge_source_archivelogs.sh completed at $(date)"
