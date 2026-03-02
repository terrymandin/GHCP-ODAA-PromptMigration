#!/usr/bin/env bash
# =============================================================================
# verify_fixes.sh
# Purpose: Consolidated verification script — confirms all three critical
#          blockers from the ORADB Discovery Summary have been resolved:
#            Issue 1: PDB1 is OPEN (READ WRITE)
#            Issue 2: ALL COLUMNS supplemental logging is enabled
#            Issue 3: OCI CLI is configured and can reach OCI
#          Also checks recommended items (disk space).
#          Saves output to Step2/Verification/ for Step 3 reference.
# Target:  Run as zdmuser on the ZDM server.
# =============================================================================

set -uo pipefail    # note: no -e so we collect all failures before exiting

# --- User guard ---
if [[ "$(whoami)" != "zdmuser" ]]; then
  echo "ERROR: This script must be run as zdmuser. Current user: $(whoami)"
  echo "       Switch with: sudo su - zdmuser"
  exit 1
fi

# =============================================================================
# Configuration
# =============================================================================
SOURCE_HOST="${SOURCE_HOST:-10.1.0.11}"
SOURCE_SSH_USER="${SOURCE_SSH_USER:-azureuser}"
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-~/.ssh/iaas.pem}"
TARGET_HOST="${TARGET_HOST:-10.0.1.160}"
TARGET_SSH_USER="${TARGET_SSH_USER:-opc}"
TARGET_SSH_KEY="${TARGET_SSH_KEY:-~/.ssh/odaa.pem}"
ORACLE_USER="${ORACLE_USER:-oracle}"
ORACLE_SID="${ORACLE_SID:-oradb}"
ORACLE_HOME="${ORACLE_HOME:-/u01/app/oracle/product/12.2.0/dbhome_1}"
PDB_NAME="${PDB_NAME:-PDB1}"
ZDM_HOME="${ZDM_HOME:-/u01/app/zdmhome}"
TARGET_DATABASE_OCID="${TARGET_DATABASE_OCID:-ocid1.database.oc1.uk-london-1.anwgiljss56liuaatz45cjnpbvpgku7gkorvxg6lytoj5lxxruk2eqxzkzma}"

# Output directory for verification logs
VERIFY_DIR="${HOME}/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Verification"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${VERIFY_DIR}/verify_fixes_${TIMESTAMP}.log"

# Track pass/fail
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

# =============================================================================
# Helpers
# =============================================================================
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

pass() { echo "  ✅ PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  ❌ FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
warn() { echo "  ⚠️  WARN: $*"; WARN_COUNT=$((WARN_COUNT + 1)); }
header() { echo ""; echo "--- $* ---"; }

# =============================================================================
# Create output directory
# =============================================================================
mkdir -p "${VERIFY_DIR}"

# Tee all output to log file
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "============================================================"
echo "  verify_fixes.sh — ORADB Step 2 Verification"
echo "============================================================"
echo ""
echo "  Timestamp : $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "  Running as: $(whoami) on $(hostname)"
echo "  Log file  : ${LOG_FILE}"
echo ""

# =============================================================================
# CHECK 1: SSH connectivity to source
# =============================================================================
header "Check 1 of 8: SSH connectivity to source (${SOURCE_HOST})"
if ssh -i "${SOURCE_SSH_KEY}" \
       -o StrictHostKeyChecking=no \
       -o ConnectTimeout=10 \
       "${SOURCE_SSH_USER}@${SOURCE_HOST}" \
       "echo OK" &>/dev/null; then
  pass "SSH to ${SOURCE_SSH_USER}@${SOURCE_HOST} using ${SOURCE_SSH_KEY}"
else
  fail "Cannot SSH to ${SOURCE_SSH_USER}@${SOURCE_HOST} using ${SOURCE_SSH_KEY}"
fi

# =============================================================================
# CHECK 2: PDB1 is OPEN (READ WRITE) — Issue 1 resolution
# =============================================================================
header "Check 2 of 8: PDB1 open state (Issue 1)"
PDB_SQL="
SET FEEDBACK OFF
SET PAGESIZE 0
SELECT OPEN_MODE FROM V\$PDBS WHERE NAME = UPPER('${PDB_NAME}');
EXIT;
"

PDB_OUTPUT=$(run_sql_on_source "${PDB_SQL}" 2>&1) || true
PDB_OPEN_MODE=$(echo "${PDB_OUTPUT}" | grep -v '^$' | grep -v SQL | tail -1 | xargs)

echo "  PDB ${PDB_NAME} OPEN_MODE: '${PDB_OPEN_MODE}'"
if [[ "${PDB_OPEN_MODE}" == "READ WRITE" ]]; then
  pass "PDB1 is OPEN (READ WRITE) — Issue 1 resolved"
elif [[ -z "${PDB_OPEN_MODE}" ]]; then
  fail "Could not determine PDB1 open mode — check source DB connectivity"
else
  fail "PDB1 open mode is '${PDB_OPEN_MODE}' (expected: READ WRITE) — run fix_open_pdb1.sh"
fi

# =============================================================================
# CHECK 3: ALL COLUMNS supplemental logging — Issue 2 resolution
# =============================================================================
header "Check 3 of 8: Supplemental logging (Issue 2)"
SUPLOG_SQL="
SET FEEDBACK OFF
SET PAGESIZE 0
SELECT SUPPLEMENTAL_LOG_DATA_ALL FROM V\$DATABASE;
EXIT;
"

SUPLOG_OUTPUT=$(run_sql_on_source "${SUPLOG_SQL}" 2>&1) || true
SUPLOG_ALL=$(echo "${SUPLOG_OUTPUT}" | grep -E "^(YES|NO)\s*$" | xargs || echo "UNKNOWN")

echo "  SUPPLEMENTAL_LOG_DATA_ALL: '${SUPLOG_ALL}'"
if [[ "${SUPLOG_ALL}" == "YES" ]]; then
  pass "ALL COLUMNS supplemental logging is enabled — Issue 2 resolved"
else
  fail "ALL COLUMNS supplemental logging is '${SUPLOG_ALL}' (expected: YES) — run fix_supplemental_logging.sh"
fi

# Also check PRIMARY KEY logging
SUPLOG_PK_SQL="
SET FEEDBACK OFF
SET PAGESIZE 0
SELECT SUPPLEMENTAL_LOG_DATA_PK FROM V\$DATABASE;
EXIT;
"
SUPLOG_PK_OUTPUT=$(run_sql_on_source "${SUPLOG_PK_SQL}" 2>&1) || true
SUPLOG_PK=$(echo "${SUPLOG_PK_OUTPUT}" | grep -E "^(YES|NO)\s*$" | xargs || echo "UNKNOWN")
echo "  SUPPLEMENTAL_LOG_DATA_PK:  '${SUPLOG_PK}'"
if [[ "${SUPLOG_PK}" == "YES" ]]; then
  pass "PRIMARY KEY supplemental logging is enabled"
else
  warn "PRIMARY KEY supplemental logging is '${SUPLOG_PK}' — run fix_supplemental_logging.sh"
fi

# =============================================================================
# CHECK 4: OCI CLI config and connectivity — Issue 3 resolution
# =============================================================================
header "Check 4 of 8: OCI CLI config and connectivity (Issue 3)"

if [[ ! -f "${HOME}/.oci/config" ]]; then
  fail "~/.oci/config does not exist — run fix_oci_config.sh"
else
  pass "~/.oci/config exists"

  NS_OUTPUT=$(oci os ns get 2>&1) || true
  if echo "${NS_OUTPUT}" | grep -q '"data"'; then
    OCI_NS=$(echo "${NS_OUTPUT}" | grep -oP '(?<="data": ")[^"]+' || echo "unknown")
    pass "OCI CLI connectivity confirmed — Object Storage namespace: ${OCI_NS}"
    echo "  ⚠️  ACTION: Record namespace '${OCI_NS}' in Migration Questionnaire Section C."
  else
    fail "OCI CLI 'oci os ns get' failed — check ~/.oci/config and API key"
    echo "  Output: ${NS_OUTPUT}"
  fi
fi

# =============================================================================
# CHECK 5: Source database is in ARCHIVELOG mode (sanity re-check)
# =============================================================================
header "Check 5 of 8: Source ARCHIVELOG mode (sanity)"
ARCH_SQL="
SET FEEDBACK OFF
SET PAGESIZE 0
SELECT LOG_MODE FROM V\$DATABASE;
EXIT;
"
ARCH_OUTPUT=$(run_sql_on_source "${ARCH_SQL}" 2>&1) || true
ARCH_MODE=$(echo "${ARCH_OUTPUT}" | grep -E "^ARCHIVELOG\s*$" | xargs || echo "NOARCHIVELOG")

if [[ "${ARCH_MODE}" == "ARCHIVELOG" ]]; then
  pass "Source database is in ARCHIVELOG mode ✅"
else
  fail "Source database is NOT in ARCHIVELOG mode ('${ARCH_MODE}') — critical prerequisite"
fi

# =============================================================================
# CHECK 6: Source root disk space
# =============================================================================
header "Check 6 of 8: Source root disk free space"
DISK_OUTPUT=$(ssh -i "${SOURCE_SSH_KEY}" \
    -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
    "${SOURCE_SSH_USER}@${SOURCE_HOST}" \
    "df -BG / | awk 'NR==2{print \$4}'" 2>/dev/null) || true

SOURCE_FREE_GB=$(echo "${DISK_OUTPUT}" | tr -d 'G' | xargs || echo "0")
echo "  Source root free space: ${SOURCE_FREE_GB} GB"
if [[ "${SOURCE_FREE_GB:-0}" -ge 10 ]]; then
  pass "Source root filesystem has ${SOURCE_FREE_GB} GB free (≥10 GB threshold)"
else
  warn "Source root filesystem has only ${SOURCE_FREE_GB} GB free — monitor archive log growth during migration"
fi

# =============================================================================
# CHECK 7: ZDM server disk space
# =============================================================================
header "Check 7 of 8: ZDM server root disk free space"
ZDM_ROOT_FREE=$(df -BG / | awk 'NR==2{print $4}' | tr -d 'G')
echo "  ZDM root free space: ${ZDM_ROOT_FREE} GB"
if [[ "${ZDM_ROOT_FREE:-0}" -ge 20 ]]; then
  pass "ZDM root filesystem has ${ZDM_ROOT_FREE} GB free (≥20 GB threshold)"
else
  warn "ZDM root filesystem has only ${ZDM_ROOT_FREE} GB free — ZDM recommends 50+ GB"
fi

# =============================================================================
# CHECK 8: ZDM service is running
# =============================================================================
header "Check 8 of 8: ZDM service status"
ZDM_STATUS=$(${ZDM_HOME}/bin/zdmcli query job 2>&1 | head -5 || true)
if echo "${ZDM_STATUS}" | grep -qiE "(Job ID|SUCCEEDED|FAILED|no jobs)"; then
  pass "ZDM service is responding (zdmcli query job succeeded)"
elif pgrep -f zdmservice &>/dev/null; then
  pass "ZDM service process is running"
else
  warn "Could not confirm ZDM service status — check manually: ${ZDM_HOME}/bin/zdmcli query job"
fi

# =============================================================================
# Results summary
# =============================================================================
echo ""
echo "============================================================"
echo "  Verification Summary"
echo "============================================================"
echo ""
printf "  ✅ Passed : %d\n" "${PASS_COUNT}"
printf "  ❌ Failed : %d\n" "${FAIL_COUNT}"
printf "  ⚠️  Warnings: %d\n" "${WARN_COUNT}"
echo ""

if [[ "${FAIL_COUNT}" -eq 0 ]]; then
  echo "  🎉 All critical checks PASSED."
  echo "     All three blockers are resolved. You may proceed to Step 3."
  echo ""
  echo "  Next step: Step3-Generate-Migration-Artifacts.prompt.md"
else
  echo "  ❌ ${FAIL_COUNT} check(s) FAILED. Resolve failures before proceeding to Step 3."
  echo ""
  for i in $(seq 1 "${FAIL_COUNT}"); do
    echo "  Review the output above for the failed checks and re-run the appropriate fix script."
  done
fi

echo ""
echo "  Verification log saved to:"
echo "  ${LOG_FILE}"
echo ""
echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] verify_fixes.sh completed."

# Exit with non-zero if any critical check failed
if [[ "${FAIL_COUNT}" -gt 0 ]]; then
  exit 1
fi
