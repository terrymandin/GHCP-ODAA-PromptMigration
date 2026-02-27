#!/usr/bin/env bash
# =============================================================================
# fix_05_rman_archive_config.sh
# =============================================================================
# Purpose : Configure RMAN on the source database and take a pre-migration
#           backup. Addresses the risk of having no backup before initiating
#           ZDM and ensures RMAN/FRA settings are in place.
#
# Actions : ACTION-08 (Archive Log Destination), ACTION-09 (RMAN Config)
#
# Run from: ZDM Server (10.1.0.8) as azureuser
# Run as  : azureuser  -->  sudo -u oracle  -->  rman target /
#
# PREREQUISITE: ACTION-01 must be complete (source must be in ARCHIVELOG mode).
#
# Usage   : bash fix_05_rman_archive_config.sh
#           bash fix_05_rman_archive_config.sh --config-only   (skip backup)
#           bash fix_05_rman_archive_config.sh --backup-only   (skip config)
#           bash fix_05_rman_archive_config.sh --check         (show RMAN status)
# =============================================================================

set -euo pipefail

# --- Configuration (from zdm-env.md) ----------------------------------------
SOURCE_HOST="10.1.0.11"
SOURCE_SSH_USER="azureuser"
SOURCE_SSH_KEY="${HOME}/.ssh/odaa.pem"
ORACLE_HOME="/u01/app/oracle/product/12.2.0/dbhome_1"
ORACLE_SID="oradb"
ORACLE_USER="oracle"

FRA_PATH="/u01/app/oracle/fast_recovery_area"
ARCHIVE_PATH="/u01/app/oracle/archive"
RMAN_RETENTION_DAYS=3
# ----------------------------------------------------------------------------

MODE="${1:---all}"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

log "================================================================"
log "fix_05_rman_archive_config.sh — RMAN Config + Pre-Migration Backup"
log "================================================================"
log "Source host  : ${SOURCE_HOST}"
log "Oracle SID   : ${ORACLE_SID}"
log "FRA path     : ${FRA_PATH}"
log "Archive path : ${ARCHIVE_PATH}"
log "Mode         : ${MODE}"
log "================================================================"

# --- Helper: run SQL/RMAN on source -----------------------------------------
run_ssh_cmd() {
  ssh -i "${SOURCE_SSH_KEY}" \
      -o StrictHostKeyChecking=no \
      -o ConnectTimeout=10 \
      "${SOURCE_SSH_USER}@${SOURCE_HOST}" \
      "sudo -u ${ORACLE_USER} bash -s"
}

# --- CHECK mode -------------------------------------------------------------
if [[ "${MODE}" == "--check" ]]; then
  log "Checking RMAN and archive log status on source..."
  run_ssh_cmd << EOF
export ORACLE_HOME=${ORACLE_HOME}
export ORACLE_SID=${ORACLE_SID}
export PATH=\${ORACLE_HOME}/bin:\${PATH}

echo "=== Archive Log Mode ==="
sqlplus -S / as sysdba << 'ENDSQL'
SELECT LOG_MODE, FORCE_LOGGING, SUPPLEMENTAL_LOG_DATA_MIN FROM V\$DATABASE;
SELECT DEST_ID, STATUS, DESTINATION FROM V\$ARCHIVE_DEST WHERE STATUS='VALID';
ARCHIVE LOG LIST;
EXIT;
ENDSQL

echo ""
echo "=== Disk Space ==="
df -h ${ARCHIVE_PATH} 2>/dev/null || df -h /u01
df -h ${FRA_PATH} 2>/dev/null || true

echo ""
echo "=== RMAN Configuration ==="
rman target / << 'ENDRMAN'
SHOW ALL;
LIST BACKUP SUMMARY;
EXIT;
ENDRMAN
EOF
  exit 0
fi

# --- Pre-check: confirm ARCHIVELOG mode is active ---------------------------
log "Step 0: Verifying source is in ARCHIVELOG mode (prerequisite)..."
ARCH_MODE=$(ssh -i "${SOURCE_SSH_KEY}" \
    -o StrictHostKeyChecking=no \
    "${SOURCE_SSH_USER}@${SOURCE_HOST}" \
    "sudo -u ${ORACLE_USER} bash -c '
      export ORACLE_HOME=${ORACLE_HOME}
      export ORACLE_SID=${ORACLE_SID}
      export PATH=\${ORACLE_HOME}/bin:\${PATH}
      sqlplus -S / as sysdba <<EOF
SET PAGESIZE 0 FEEDBACK OFF HEADING OFF
SELECT LOG_MODE FROM V\\\$DATABASE;
EXIT;
EOF
'" 2>/dev/null | tr -d '[:space:]')

if [[ "${ARCH_MODE}" != "ARCHIVELOG" ]]; then
  log "ERROR: Source database is NOT in ARCHIVELOG mode (found: ${ARCH_MODE})."
  log "       Complete ACTION-01 (fix_01_source_archivelog.sh) first."
  exit 1
fi
log "✅ Source is in ARCHIVELOG mode."

# --- RMAN CONFIG step -------------------------------------------------------
if [[ "${MODE}" == "--all" || "${MODE}" == "--config-only" ]]; then
  log ""
  log "=== Configuring RMAN settings and archive log destination ==="

  run_ssh_cmd << EOF
export ORACLE_HOME=${ORACLE_HOME}
export ORACLE_SID=${ORACLE_SID}
export PATH=\${ORACLE_HOME}/bin:\${PATH}

# Ensure FRA and archive directories exist
mkdir -p ${FRA_PATH}
mkdir -p ${ARCHIVE_PATH}
ls -ld ${FRA_PATH} ${ARCHIVE_PATH}

# Set archive log destination (in case not already done by fix_01)
sqlplus -S / as sysdba << 'ENDSQL'
ALTER SYSTEM SET log_archive_dest_1='LOCATION=${ARCHIVE_PATH}' SCOPE=BOTH;
ALTER SYSTEM SET db_recovery_file_dest='${FRA_PATH}' SCOPE=BOTH;
ALTER SYSTEM SET db_recovery_file_dest_size=5G SCOPE=BOTH;
SELECT DEST_ID, STATUS, DESTINATION FROM V\$ARCHIVE_DEST WHERE DEST_ID=1;
EXIT;
ENDSQL

echo ""
echo "=== Configuring RMAN ==="
rman target / << 'ENDRMAN'
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '${FRA_PATH}/%F';
CONFIGURE DEFAULT DEVICE TYPE TO DISK;
CONFIGURE BACKUP OPTIMIZATION ON;
CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF ${RMAN_RETENTION_DAYS} DAYS;
CONFIGURE CHANNEL DEVICE TYPE DISK FORMAT '${FRA_PATH}/%U';
CONFIGURE ARCHIVELOG DELETION POLICY TO APPLIED ON ALL STANDBY;
SHOW ALL;
EXIT;
ENDRMAN
EOF
  log "✅ RMAN configuration applied."
fi

# --- BACKUP step ------------------------------------------------------------
if [[ "${MODE}" == "--all" || "${MODE}" == "--backup-only" ]]; then
  log ""
  log "=== Taking pre-migration RMAN backup ==="
  log "    This will back up the full database + current archive logs."
  log "    Estimated duration: 5–20 minutes for a ~1.9 GB database."
  log ""
  read -r -p "Press ENTER to start the backup (CTRL+C to skip)..."

  run_ssh_cmd << EOF
export ORACLE_HOME=${ORACLE_HOME}
export ORACLE_SID=${ORACLE_SID}
export PATH=\${ORACLE_HOME}/bin:\${PATH}

echo "=== Starting pre-migration backup at \$(date) ==="
rman target / << 'ENDRMAN'
BACKUP DATABASE PLUS ARCHIVELOG TAG 'PRE_ZDM_MIGRATION';
LIST BACKUP SUMMARY;
EXIT;
ENDRMAN
echo "=== Backup completed at \$(date) ==="
EOF
  log "✅ Pre-migration backup complete."
fi

# --- Final status -----------------------------------------------------------
log ""
log "=== Post-Fix Disk Space Check ==="
ssh -i "${SOURCE_SSH_KEY}" \
    -o StrictHostKeyChecking=no \
    "${SOURCE_SSH_USER}@${SOURCE_HOST}" \
    "sudo -u ${ORACLE_USER} bash -c 'df -h /u01; df -h ${FRA_PATH} 2>/dev/null || true'"

log ""
log "================================================================"
log "fix_05_rman_archive_config.sh COMPLETE"
log ""
log "Update Issue-Resolution-Log-ORADB.md:"
log "  - ACTION-08 Status: ✅ Resolved (archive log destination configured)"
log "  - ACTION-09 Status: ✅ Resolved (RMAN configured + backup taken)"
log "================================================================"
