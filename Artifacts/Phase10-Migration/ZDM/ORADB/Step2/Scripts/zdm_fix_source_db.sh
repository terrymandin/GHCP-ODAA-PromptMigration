#!/usr/bin/env bash
# =============================================================================
# zdm_fix_source_db.sh
# -----------------------------------------------------------------------------
# Resolves two blockers on the ORADB source database before ZDM migration:
#
#   Issue 1: PDB1 is MOUNTED — opens it READ WRITE and saves state
#   Issue 2: ALL COLUMNS supplemental logging not enabled — enables it
#
# Run as: zdmuser on the ZDM server (tm-vm-odaa-oracle-jumpbox / 10.1.0.8)
#   sudo su - zdmuser
#   chmod +x ~/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts/zdm_fix_source_db.sh
#   ~/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts/zdm_fix_source_db.sh
#
# Part of: ZDM Migration Step 2 — Fix Issues
# =============================================================================

set -euo pipefail

# --- User guard ---
if [[ "$(whoami)" != "zdmuser" ]]; then
  echo "ERROR: This script must be run as zdmuser. Current user: $(whoami)"
  echo "       Switch with: sudo su - zdmuser"
  exit 1
fi

# =============================================================================
# Configuration — sourced from zdm-env.md and Discovery-Summary-ORADB.md
# =============================================================================
SOURCE_HOST="10.1.0.11"
SOURCE_SSH_USER="azureuser"
SOURCE_SSH_KEY="${HOME}/.ssh/iaas.pem"
ORACLE_USER="oracle"
ORACLE_HOME="/u01/app/oracle/product/12.2.0/dbhome_1"
ORACLE_SID="oradb"
PDB_NAME="PDB1"

# =============================================================================
# Helpers
# =============================================================================
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
pass() { echo "  ✅ $*"; }
fail() { echo "  ❌ $*"; exit 1; }
warn() { echo "  ⚠️  $*"; }

# run_sql_on_source <sql_block>
# Executes SQL on the source database via SSH → sudo → sqlplus.
# Uses base64 encoding so that SQL containing single-quoted string values
# (e.g. WHERE name = 'LOG_ARCHIVE_DEST_1') never conflict with shell quoting.
run_sql_on_source() {
  local sql_block="$1"
  local encoded_sql
  encoded_sql=$(printf '%s\n' "${sql_block}" | base64 -w 0)
  ssh -i "${SOURCE_SSH_KEY}" \
      -o StrictHostKeyChecking=no \
      -o ConnectTimeout=10 \
      "${SOURCE_SSH_USER}@${SOURCE_HOST}" \
      "sudo -u ${ORACLE_USER} bash -c '
         export ORACLE_HOME=${ORACLE_HOME}
         export ORACLE_SID=${ORACLE_SID}
         export PATH=\${ORACLE_HOME}/bin:\${PATH}
         echo \"${encoded_sql}\" | base64 -d | sqlplus -S / as sysdba
       '"
}

# =============================================================================
# Step 1 — Verify SSH / sudo connectivity
# =============================================================================
log "STEP 1: Verifying SSH connectivity to source (${SOURCE_SSH_USER}@${SOURCE_HOST})..."

WHOAMI=$(
  ssh -i "${SOURCE_SSH_KEY}" \
      -o StrictHostKeyChecking=no \
      -o ConnectTimeout=10 \
      "${SOURCE_SSH_USER}@${SOURCE_HOST}" \
      "sudo -u ${ORACLE_USER} whoami" 2>/dev/null
)

if [[ "${WHOAMI}" == "oracle" ]]; then
  pass "SSH connectivity OK — reached oracle via sudo"
else
  fail "Cannot reach oracle on source. Got: '${WHOAMI}'. Check SSH key (${SOURCE_SSH_KEY}) and sudo permissions."
fi

# =============================================================================
# Step 2 — Check current PDB1 state (before fix)
# =============================================================================
log "STEP 2: Checking current PDB1 open mode..."

run_sql_on_source "
SET PAGESIZE 20 LINESIZE 80 FEEDBACK OFF
COLUMN name      FORMAT A10
COLUMN open_mode FORMAT A15
COLUMN restricted FORMAT A10
SELECT name, open_mode, restricted
FROM   v\$pdbs
WHERE  name = '${PDB_NAME}';
EXIT;"

# =============================================================================
# Step 3 — Open PDB1 READ WRITE and save state
# =============================================================================
log "STEP 3: Opening ${PDB_NAME} READ WRITE and saving state..."

run_sql_on_source "
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER PLUGGABLE DATABASE ${PDB_NAME} OPEN READ WRITE;
ALTER PLUGGABLE DATABASE ${PDB_NAME} SAVE STATE;
EXIT;"

pass "ALTER PLUGGABLE DATABASE ${PDB_NAME} OPEN READ WRITE → issued"
pass "ALTER PLUGGABLE DATABASE ${PDB_NAME} SAVE STATE → issued"

# =============================================================================
# Step 4 — Enable ALL COLUMNS supplemental logging
# =============================================================================
log "STEP 4: Enabling ALL COLUMNS supplemental logging..."

run_sql_on_source "
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
EXIT;"

pass "ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS → issued"

# =============================================================================
# Step 5 — Switch logfile to activate supplemental logging immediately
# =============================================================================
log "STEP 5: Switching logfile to activate supplemental logging..."

run_sql_on_source "
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SYSTEM SWITCH LOGFILE;
EXIT;"

pass "ALTER SYSTEM SWITCH LOGFILE → issued"

# =============================================================================
# Step 6 — Verify PDB1 open mode (after fix)
# =============================================================================
log "STEP 6: Verifying PDB1 open mode..."

PDB_STATE=$(
  run_sql_on_source "
SET PAGESIZE 0 FEEDBACK OFF HEADING OFF TRIMOUT ON
SELECT open_mode
FROM   v\$pdbs
WHERE  name = '${PDB_NAME}';
EXIT;" 2>/dev/null | tr -d '[:space:]'
)

if [[ "${PDB_STATE}" == "READWRITE" ]]; then
  pass "PDB1 open_mode = READ WRITE ✅"
else
  warn "PDB1 open_mode appears to be: '${PDB_STATE}'"
  warn "Re-run the verification below manually to confirm."
fi

# =============================================================================
# Step 7 — Verify supplemental logging (after fix)
# =============================================================================
log "STEP 7: Verifying supplemental logging status..."

run_sql_on_source "
SET PAGESIZE 20 LINESIZE 120 FEEDBACK OFF
COLUMN supp_min FORMAT A8
COLUMN supp_pk  FORMAT A8
COLUMN supp_ui  FORMAT A8
COLUMN supp_fk  FORMAT A8
COLUMN supp_all FORMAT A8
SELECT log_mode,
       supplemental_log_data_min AS supp_min,
       supplemental_log_data_pk  AS supp_pk,
       supplemental_log_data_ui  AS supp_ui,
       supplemental_log_data_fk  AS supp_fk,
       supplemental_log_data_all AS supp_all
FROM   v\$database;
EXIT;"

# =============================================================================
# Step 8 — Check FRA usage (advisory — disk space warning)
# =============================================================================
log "STEP 8: Checking FRA (Fast Recovery Area) usage..."

run_sql_on_source "
SET PAGESIZE 20 LINESIZE 120 FEEDBACK OFF
COLUMN name               FORMAT A40
COLUMN limit_gb           FORMAT 999.99
COLUMN used_gb            FORMAT 999.99
COLUMN reclaimable_gb     FORMAT 999.99
SELECT name,
       ROUND(space_limit    / 1073741824, 2) AS limit_gb,
       ROUND(space_used     / 1073741824, 2) AS used_gb,
       ROUND(space_reclaimable / 1073741824, 2) AS reclaimable_gb,
       number_of_files
FROM   v\$recovery_file_dest;
EXIT;"

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "============================================================"
echo " zdm_fix_source_db.sh — Completed"
echo "============================================================"
echo ""
echo " Verify the output above:"
echo "   Step 6: PDB1 open_mode should be READ WRITE"
echo "   Step 7: supp_all should be YES"
echo ""
echo " If both are confirmed, update Issue-Resolution-Log-ORADB.md:"
echo "   Issue 1 (PDB1 open) → ✅ Resolved"
echo "   Issue 2 (Supplemental logging) → ✅ Resolved"
echo ""
echo " Next: Run zdm_configure_oci.sh to resolve Issue 3 (OCI config)"
echo "============================================================"
