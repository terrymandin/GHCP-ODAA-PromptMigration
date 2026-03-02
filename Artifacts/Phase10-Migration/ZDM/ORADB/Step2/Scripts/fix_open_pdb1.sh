#!/usr/bin/env bash
# =============================================================================
# fix_open_pdb1.sh
# Purpose: Open PDB1 on the source Oracle database (ORADB1) in READ WRITE mode
#          and persist the state so it survives instance restarts.
# Target:  Run as zdmuser on the ZDM server; connects to source via SSH.
# Issue:   Issue 1 — PDB1 is currently MOUNTED, must be OPEN for ZDM migration.
# =============================================================================

set -euo pipefail

# --- User guard ---
if [[ "$(whoami)" != "zdmuser" ]]; then
  echo "ERROR: This script must be run as zdmuser. Current user: $(whoami)"
  echo "       Switch with: sudo su - zdmuser"
  exit 1
fi

# =============================================================================
# Configuration (sourced from discovery and zdm-env.md)
# =============================================================================
SOURCE_HOST="${SOURCE_HOST:-10.1.0.11}"
SOURCE_SSH_USER="${SOURCE_SSH_USER:-azureuser}"
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-~/.ssh/iaas.pem}"
ORACLE_USER="${ORACLE_USER:-oracle}"
ORACLE_SID="${ORACLE_SID:-oradb}"
ORACLE_HOME="${ORACLE_HOME:-/u01/app/oracle/product/12.2.0/dbhome_1}"
PDB_NAME="${PDB_NAME:-PDB1}"

# =============================================================================
# Helper: run SQL on source via SSH + sudo (base64-encoded to avoid quoting issues)
# =============================================================================
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
# Step 1: Verify SSH connectivity
# =============================================================================
echo "============================================================"
echo "  fix_open_pdb1.sh — Issue 1: Open PDB1 on source"
echo "============================================================"
echo ""
echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] Verifying SSH connectivity to ${SOURCE_HOST} ..."
ssh -i "${SOURCE_SSH_KEY}" \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=10 \
    "${SOURCE_SSH_USER}@${SOURCE_HOST}" \
    "echo 'SSH OK: connected as $(whoami) on $(hostname)'"
echo ""

# =============================================================================
# Step 2: Check current PDB state
# =============================================================================
echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] Checking current PDB state ..."

CURRENT_STATE_SQL="
SET PAGESIZE 100
SET LINESIZE 120
SET FEEDBACK OFF
COL NAME FORMAT A15
COL OPEN_MODE FORMAT A12
COL RESTRICTED FORMAT A10
SELECT NAME, OPEN_MODE, RESTRICTED
FROM   V\$PDBS
WHERE  NAME = UPPER('${PDB_NAME}');
EXIT;
"

run_sql_on_source "${CURRENT_STATE_SQL}"
echo ""

# =============================================================================
# Step 3: Open PDB and save state
# =============================================================================
echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] Opening ${PDB_NAME} and saving state ..."

OPEN_PDB_SQL="
SET FEEDBACK ON
ALTER PLUGGABLE DATABASE ${PDB_NAME} OPEN;
ALTER PLUGGABLE DATABASE ${PDB_NAME} SAVE STATE;
EXIT;
"

run_sql_on_source "${OPEN_PDB_SQL}"
echo ""

# =============================================================================
# Step 4: Verify PDB is now OPEN (READ WRITE)
# =============================================================================
echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] Verifying PDB state after fix ..."

VERIFY_SQL="
SET PAGESIZE 100
SET LINESIZE 120
SET FEEDBACK OFF
COL NAME FORMAT A15
COL OPEN_MODE FORMAT A12
COL RESTRICTED FORMAT A10
SELECT NAME, OPEN_MODE, RESTRICTED
FROM   V\$PDBS
WHERE  NAME = UPPER('${PDB_NAME}');
EXIT;
"

OUTPUT=$(run_sql_on_source "${VERIFY_SQL}")
echo "${OUTPUT}"
echo ""

# Check output contains READ WRITE
if echo "${OUTPUT}" | grep -q "READ WRITE"; then
  echo "✅ SUCCESS: ${PDB_NAME} is now OPEN (READ WRITE)"
  echo ""
  echo "Next step: Run fix_supplemental_logging.sh to resolve Issue 2."
else
  echo "❌ FAIL: ${PDB_NAME} does not appear to be in READ WRITE state."
  echo "   Review the output above and check the database alert log for errors."
  echo "   Alert log location: ${ORACLE_HOME}/../diag/rdbms/${ORACLE_SID}/${ORACLE_SID}/trace/alert_${ORACLE_SID}.log"
  exit 1
fi

echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] fix_open_pdb1.sh completed."
