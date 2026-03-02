#!/usr/bin/env bash
# ==============================================================
# fix_pdb1_open.sh
#
# Opens PDB1 on the source Oracle 12.2 CDB (ORADB / SID: oradb)
# and saves its state so it re-opens automatically after restarts.
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
echo " fix_pdb1_open.sh — Open PDB1 on ${SOURCE_HOST}"
echo "================================================================"
echo ""

# ── Step 1: Check current PDB1 open_mode ─────────────────────────
echo "---- Step 1: Current PDB status --------------------------------"
run_sql_on_source "
SET LINESIZE 120
COL name      FORMAT A10
COL open_mode FORMAT A12
COL restricted FORMAT A10
SELECT name, open_mode, restricted
FROM   v\$pdbs
WHERE  name = 'PDB1';
EXIT;
"

# ── Step 2: Open PDB1 and save state ─────────────────────────────
echo ""
echo "---- Step 2: Open PDB1 and save state --------------------------"
run_sql_on_source "
ALTER PLUGGABLE DATABASE PDB1 OPEN;
ALTER PLUGGABLE DATABASE PDB1 SAVE STATE;
EXIT;
"

# ── Step 3: Verify ───────────────────────────────────────────────
echo ""
echo "---- Step 3: Verify PDB1 status --------------------------------"
run_sql_on_source "
SET LINESIZE 120
COL name      FORMAT A10
COL open_mode FORMAT A12
COL restricted FORMAT A10
SELECT name, open_mode, restricted
FROM   v\$pdbs
WHERE  name = 'PDB1';
EXIT;
"

echo ""
echo "================================================================"
echo " Done."
echo " Expected result: PDB1 | open_mode=READ WRITE | restricted=NO"
echo " If open_mode is still MOUNTED, check Oracle alert log:"
echo "   /u01/app/oracle/diag/rdbms/oradb1/oradb/trace/alert_oradb.log"
echo "================================================================"
