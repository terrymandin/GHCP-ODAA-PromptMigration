#!/usr/bin/env bash
# ==============================================================
# fix_supplemental_logging.sh
#
# Enables ALL COLUMNS supplemental logging on the source Oracle
# 12.2 CDB (ORADB / SID: oradb).  Required for ZDM ONLINE_PHYSICAL
# migration so redo contains full column values for Data Guard apply.
#
# Run from:  ZDM server (tm-vm-odaa-oracle-jumpbox) as zdmuser
# ==============================================================
set -euo pipefail

# ── Configuration (override via environment variables if needed) ──
SOURCE_HOST="${SOURCE_HOST:-10.1.0.11}"
SOURCE_SSH_USER="${SOURCE_SSH_USER:-azureuser}"
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-/home/zdmuser/iaas.pem}"
ORACLE_USER="${ORACLE_USER:-oracle}"
ORACLE_HOME="${ORACLE_HOME:-/u01/app/oracle/product/12.2.0/dbhome_1}"
ORACLE_SID="${ORACLE_SID:-oradb}"

# ── Helper: run SQL on source using base64 encoding ──────────────
# Base64 encoding ensures SQL with single-quoted strings is never
# misinterpreted by intermediate shells (avoids ORA-00922 parse errors).
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

echo "================================================================"
echo " fix_supplemental_logging.sh — Enable ALL COLUMNS suplog"
echo " Source: ${SOURCE_HOST}  SID: ${ORACLE_SID}"
echo "================================================================"
echo ""

# ── Step 1: Show current supplemental logging state ──────────────
echo "---- Step 1: Current supplemental logging status ---------------"
run_sql_on_source "
SET LINESIZE 120
SELECT
  log_mode,
  supplemental_log_data_min  AS log_min,
  supplemental_log_data_pk   AS log_pk,
  supplemental_log_data_ui   AS log_ui,
  supplemental_log_data_fk   AS log_fk,
  supplemental_log_data_all  AS log_all
FROM v\$database;
EXIT;
"

# ── Step 2: Enable ALL COLUMNS supplemental logging ──────────────
echo ""
echo "---- Step 2: Enable ALL COLUMNS supplemental logging -----------"
run_sql_on_source "
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER SYSTEM SWITCH LOGFILE;
EXIT;
"

# ── Step 3: Verify ───────────────────────────────────────────────
echo ""
echo "---- Step 3: Verify supplemental logging -----------------------"
run_sql_on_source "
SET LINESIZE 120
SELECT
  supplemental_log_data_min  AS log_min,
  supplemental_log_data_pk   AS log_pk,
  supplemental_log_data_ui   AS log_ui,
  supplemental_log_data_fk   AS log_fk,
  supplemental_log_data_all  AS log_all
FROM v\$database;
EXIT;
"

echo ""
echo "================================================================"
echo " Done."
echo " Expected result: log_all = YES"
echo ""
echo " Note: ALL COLUMNS supplemental logging increases redo volume."
echo " Monitor archive log disk usage at:"
echo "   /u01/app/oracle/fast_recovery_area"
echo " See Issue 4 in Issue-Resolution-Log-ORADB.md for disk guidance."
echo "================================================================"
