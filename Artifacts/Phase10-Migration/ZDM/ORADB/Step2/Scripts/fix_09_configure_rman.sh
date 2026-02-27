#!/usr/bin/env bash
# =============================================================================
# fix_09_configure_rman.sh
#
# Purpose : Configure RMAN on the source database and take a pre-migration
#           backup to OCI Object Storage or local disk.
#           - No RMAN backup policy currently exists on the source.
#           - A full backup before ZDM migration is strongly recommended
#             as a fallback if migration must be abandoned.
#
# Target  : Source database server (10.1.0.11) — executed FROM the ZDM server
#           via SSH. Runs RMAN as oracle OS user via sudo.
#
# Run as  : azureuser on ZDM server (10.1.0.8)
# Usage   : bash fix_09_configure_rman.sh
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

# RMAN backup location — use a path with sufficient free space
# The fast_recovery_area must have enough space for the backup (source DB ~1.9 GB)
RMAN_BACKUP_DIR="${RMAN_BACKUP_DIR:-/u01/app/oracle/fast_recovery_area}"
RMAN_AUTOBACKUP_FORMAT="${RMAN_BACKUP_DIR}/%F"

LOG_FILE="fix_09_$(date +%Y%m%d_%H%M%S).log"

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"; }
info() { log "INFO  $*"; }
warn() { log "WARN  $*"; }
fail() { log "ERROR $*"; exit 1; }
sep()  { log "----------------------------------------------------------------------"; }

# ---------------------------------------------------------------------------
# Helper: run a shell command on source via SSH
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
# Helper: run RMAN script on source via SSH + sudo + heredoc via base64
# ---------------------------------------------------------------------------
run_rman_on_source() {
  local rman_script="$1"
  local encoded_script
  encoded_script=$(printf '%s\n' "${rman_script}" | base64 -w 0)
  ssh -i "${SOURCE_SSH_KEY}" \
      -o StrictHostKeyChecking=no \
      -o ConnectTimeout=300 \
      "${SOURCE_SSH_USER}@${SOURCE_HOST}" \
      "sudo -u ${ORACLE_USER} bash -c '
        export ORACLE_HOME=${ORACLE_HOME}
        export ORACLE_SID=${ORACLE_SID}
        export PATH=\${ORACLE_HOME}/bin:\${PATH}
        echo \"${encoded_script}\" | base64 -d | rman TARGET /
      '"
}

# ---------------------------------------------------------------------------
# Step 0: Preflight
# ---------------------------------------------------------------------------
sep
info "Starting fix_09: Configure RMAN and Take Pre-Migration Backup"
info "Source host     : ${SOURCE_HOST}"
info "Oracle SID      : ${ORACLE_SID}"
info "Backup location : ${RMAN_BACKUP_DIR}"
info "Log file        : ${LOG_FILE}"
sep

info "Step 0: Testing SSH connectivity..."
run_remote_cmd "hostname" >> "${LOG_FILE}" 2>&1 || fail "Cannot SSH to source."
info "SSH to source: OK"

info "Step 0: Checking disk space on source..."
run_remote_cmd "df -h" | tee -a "${LOG_FILE}"

# ---------------------------------------------------------------------------
# Step 1: Create backup directory on source
# ---------------------------------------------------------------------------
sep
info "Step 1: Creating RMAN backup/recovery area directory..."
run_remote_cmd "sudo -u ${ORACLE_USER} bash -c 'mkdir -p ${RMAN_BACKUP_DIR} && chmod 755 ${RMAN_BACKUP_DIR} && echo OK'" \
  | tee -a "${LOG_FILE}" || fail "Failed to create RMAN backup directory."

# ---------------------------------------------------------------------------
# Step 2: Configure RMAN settings
# ---------------------------------------------------------------------------
sep
info "Step 2: Configuring RMAN (control file autobackup, retention, compression)..."

RMAN_CONFIG="
CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 7 DAYS;
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '${RMAN_AUTOBACKUP_FORMAT}';
CONFIGURE DEFAULT DEVICE TYPE TO DISK;
CONFIGURE BACKUP OPTIMIZATION ON;
CONFIGURE COMPRESSION ALGORITHM 'BASIC' AS OF RELEASE 'DEFAULT' OPTIMIZE FOR LOAD TRUE;
SHOW ALL;
"
run_rman_on_source "${RMAN_CONFIG}" 2>&1 | tee -a "${LOG_FILE}" || \
  fail "RMAN configuration failed. Check Oracle SID and ORACLE_HOME settings."
info "RMAN configured successfully."

# ---------------------------------------------------------------------------
# Step 3: Take a full database backup (with archive logs)
# ---------------------------------------------------------------------------
sep
info "Step 3: Taking full RMAN backup (database + archive logs)..."
info "   This may take several minutes for the 1.9 GB source database."

RMAN_BACKUP="
BACKUP AS COMPRESSED BACKUPSET DATABASE PLUS ARCHIVELOG;
DELETE NOPROMPT OBSOLETE;
LIST BACKUP SUMMARY;
"
run_rman_on_source "${RMAN_BACKUP}" 2>&1 | tee -a "${LOG_FILE}" || \
  fail "RMAN backup failed. Check archive log mode (run fix_01 first) and disk space."
info "RMAN backup completed successfully."

# ---------------------------------------------------------------------------
# Step 4: Verify backup
# ---------------------------------------------------------------------------
sep
info "Step 4: Verifying backup completeness..."

RMAN_VERIFY="
VALIDATE DATABASE;
LIST BACKUP SUMMARY;
"
run_rman_on_source "${RMAN_VERIFY}" 2>&1 | tee -a "${LOG_FILE}"

info "Step 4: Checking disk space after backup..."
run_remote_cmd "df -h ${RMAN_BACKUP_DIR}" | tee -a "${LOG_FILE}"

sep
info "✅ Fix 09 complete."
info "   RMAN configured and initial backup taken."
info "   Backup location: ${RMAN_BACKUP_DIR} on source (${SOURCE_HOST})"
info "   Keep this backup until migration is verified complete on target."
sep
info "Log saved to: ${LOG_FILE}"
