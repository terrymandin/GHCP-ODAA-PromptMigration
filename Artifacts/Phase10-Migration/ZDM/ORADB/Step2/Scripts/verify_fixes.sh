#!/usr/bin/env bash
# ==============================================================
# verify_fixes.sh
#
# Verifies that all three Step 2 blockers have been resolved:
#   Issue 1 — PDB1 is READ WRITE on source
#   Issue 2 — ALL COLUMNS supplemental logging is enabled on source
#   Issue 3 — OCI CLI works as zdmuser on ZDM server
#
# Run from:  ZDM server (tm-vm-odaa-oracle-jumpbox) as zdmuser
#            after running all three fix_* scripts.
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

PASS=0
FAIL=0
ISSUES=()

echo "================================================================"
echo " verify_fixes.sh — Step 2 Blocker Verification"
echo " Source: ${SOURCE_HOST}  SID: ${ORACLE_SID}"
echo " Date:   $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "================================================================"
echo ""

# ── Check 1: PDB1 open_mode ───────────────────────────────────────
echo "---- Check 1: PDB1 Open Mode -----------------------------------"
PDB_STATUS=$(run_sql_on_source "
SET HEADING OFF
SET FEEDBACK OFF
SET PAGES 0
SELECT open_mode FROM v\$pdbs WHERE name = 'PDB1';
EXIT;
" | tr -d '[:space:]')

echo "   PDB1 open_mode: ${PDB_STATUS}"
if [[ "${PDB_STATUS}" == "READWRITE" ]]; then
  echo "   ✅ PASS — PDB1 is READ WRITE"
  ((PASS++))
else
  echo "   ❌ FAIL — PDB1 is NOT READ WRITE (got: ${PDB_STATUS})"
  echo "            Run: Scripts/fix_pdb1_open.sh"
  ISSUES+=("Issue 1: PDB1 open_mode = ${PDB_STATUS} (expected READ WRITE)")
  ((FAIL++))
fi

# ── Check 2: ALL COLUMNS supplemental logging ─────────────────────
echo ""
echo "---- Check 2: ALL COLUMNS Supplemental Logging -----------------"
SUPLOG_ALL=$(run_sql_on_source "
SET HEADING OFF
SET FEEDBACK OFF
SET PAGES 0
SELECT supplemental_log_data_all FROM v\$database;
EXIT;
" | tr -d '[:space:]')

echo "   supplemental_log_data_all: ${SUPLOG_ALL}"
if [[ "${SUPLOG_ALL}" == "YES" ]]; then
  echo "   ✅ PASS — ALL COLUMNS supplemental logging is enabled"
  ((PASS++))
else
  echo "   ❌ FAIL — ALL COLUMNS supplemental logging is NOT enabled (got: ${SUPLOG_ALL})"
  echo "            Run: Scripts/fix_supplemental_logging.sh"
  ISSUES+=("Issue 2: supplemental_log_data_all = ${SUPLOG_ALL} (expected YES)")
  ((FAIL++))
fi

# ── Check 3: OCI CLI connectivity ────────────────────────────────
echo ""
echo "---- Check 3: OCI CLI Connectivity (as $(whoami)) -------------"
if ! command -v oci &>/dev/null; then
  echo "   ❌ FAIL — 'oci' command not found in PATH"
  ISSUES+=("Issue 3: OCI CLI not in PATH")
  ((FAIL++))
else
  OCI_OUTPUT=$(oci os ns get 2>&1) || true
  if echo "${OCI_OUTPUT}" | grep -q '"data"'; then
    OCI_NAMESPACE=$(echo "${OCI_OUTPUT}" | grep '"data"' | awk -F'"' '{print $4}')
    echo "   ✅ PASS — OCI CLI connectivity confirmed"
    echo "   Object Storage Namespace: ${OCI_NAMESPACE}"
    ((PASS++))
  else
    echo "   ❌ FAIL — OCI CLI returned an error:"
    echo "   ${OCI_OUTPUT}" | head -5
    echo "            Run: Scripts/fix_oci_config_zdmuser.sh"
    ISSUES+=("Issue 3: OCI CLI connectivity failed")
    ((FAIL++))
  fi
fi

# ── Summary ───────────────────────────────────────────────────────
echo ""
echo "================================================================"
echo " Summary"
echo "================================================================"
echo "   Passed: ${PASS}/3"
echo "   Failed: ${FAIL}/3"
echo ""

if [[ ${FAIL} -eq 0 ]]; then
  echo "   🎉 ALL BLOCKERS RESOLVED — ready to proceed to Step 3"
  echo ""
  echo "   Next steps:"
  echo "   1. Update Issue-Resolution-Log-ORADB.md with resolution notes"
  echo "   2. Re-run source discovery and save to Step2/Verification/"
  echo "   3. Run Step3-Generate-Migration-Artifacts.prompt.md"
else
  echo "   ❌ ${FAIL} blocker(s) remain — fix before proceeding to Step 3:"
  for issue in "${ISSUES[@]}"; do
    echo "      • ${issue}"
  done
fi
echo "================================================================"
