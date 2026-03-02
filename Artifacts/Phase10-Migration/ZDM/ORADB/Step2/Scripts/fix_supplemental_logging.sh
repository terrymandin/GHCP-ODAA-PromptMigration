#!/usr/bin/env bash
# =============================================================================
# fix_supplemental_logging.sh
# Purpose: Enable ALL COLUMNS supplemental logging on the source Oracle database
#          (ORADB1) required for ZDM ONLINE_PHYSICAL migration.
# Target:  Run as zdmuser on the ZDM server; connects to source via SSH.
# Issue:   Issue 2 — Supplemental logging (ALL COLUMNS, PRIMARY KEY) not enabled.
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
echo "  fix_supplemental_logging.sh — Issue 2: Enable supplemental logging"
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
# Step 2: Show current supplemental logging state
# =============================================================================
echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] Checking current supplemental logging state ..."

CHECK_SQL="
SET PAGESIZE 100
SET LINESIZE 160
SET FEEDBACK OFF
COL MIN_LOGGING  FORMAT A12 HEADING 'MIN'
COL PK_LOGGING   FORMAT A12 HEADING 'PK'
COL UI_LOGGING   FORMAT A12 HEADING 'UNIQUE'
COL FK_LOGGING   FORMAT A12 HEADING 'FK'
COL ALL_LOGGING  FORMAT A12 HEADING 'ALL_COLS'
SELECT
  SUPPLEMENTAL_LOG_DATA_MIN AS MIN_LOGGING,
  SUPPLEMENTAL_LOG_DATA_PK  AS PK_LOGGING,
  SUPPLEMENTAL_LOG_DATA_UI  AS UI_LOGGING,
  SUPPLEMENTAL_LOG_DATA_FK  AS FK_LOGGING,
  SUPPLEMENTAL_LOG_DATA_ALL AS ALL_LOGGING
FROM V\$DATABASE;
EXIT;
"

run_sql_on_source "${CHECK_SQL}"
echo ""

# =============================================================================
# Step 3: Enable ALL COLUMNS and PRIMARY KEY supplemental logging
# =============================================================================
echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] Enabling ALL COLUMNS and PRIMARY KEY supplemental logging ..."

ENABLE_SQL="
SET FEEDBACK ON
-- Enable ALL COLUMNS supplemental logging (required for ONLINE_PHYSICAL migration)
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;

-- Enable PRIMARY KEY supplemental logging (additional requirement for ZDM)
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (PRIMARY KEY) COLUMNS;

-- Switch logfile to begin generating redo with the new supplemental logging level
ALTER SYSTEM SWITCH LOGFILE;

EXIT;
"

run_sql_on_source "${ENABLE_SQL}"
echo ""

# =============================================================================
# Step 4: Verify supplemental logging is now fully enabled
# =============================================================================
echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] Verifying supplemental logging state after fix ..."

VERIFY_SQL="
SET PAGESIZE 100
SET LINESIZE 160
SET FEEDBACK OFF
COL MIN_LOGGING  FORMAT A12 HEADING 'MIN'
COL PK_LOGGING   FORMAT A12 HEADING 'PK'
COL UI_LOGGING   FORMAT A12 HEADING 'UNIQUE'
COL FK_LOGGING   FORMAT A12 HEADING 'FK'
COL ALL_LOGGING  FORMAT A12 HEADING 'ALL_COLS'
SELECT
  SUPPLEMENTAL_LOG_DATA_MIN AS MIN_LOGGING,
  SUPPLEMENTAL_LOG_DATA_PK  AS PK_LOGGING,
  SUPPLEMENTAL_LOG_DATA_UI  AS UI_LOGGING,
  SUPPLEMENTAL_LOG_DATA_FK  AS FK_LOGGING,
  SUPPLEMENTAL_LOG_DATA_ALL AS ALL_LOGGING
FROM V\$DATABASE;
EXIT;
"

OUTPUT=$(run_sql_on_source "${VERIFY_SQL}")
echo "${OUTPUT}"
echo ""

# Check that ALL_COLS = YES
if echo "${OUTPUT}" | grep -qE "YES\s+YES\s+"; then
  echo "✅ SUCCESS: Supplemental logging (ALL COLUMNS + PRIMARY KEY) is now enabled."
  echo ""
  echo "Next step: Run fix_oci_config.sh to resolve Issue 3."
else
  echo "❌ FAIL: Supplemental logging may not be fully enabled."
  echo "   Review the output above. Verify ALL_COLS column shows YES."
  echo "   If the SQL produced errors, check the database alert log:"
  echo "   ${ORACLE_HOME}/../diag/rdbms/${ORACLE_SID}/${ORACLE_SID}/trace/alert_${ORACLE_SID}.log"
  exit 1
fi

echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] fix_supplemental_logging.sh completed."
