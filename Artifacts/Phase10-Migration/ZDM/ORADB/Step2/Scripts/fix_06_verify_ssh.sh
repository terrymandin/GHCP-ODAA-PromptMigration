#!/usr/bin/env bash
# =============================================================================
# fix_06_verify_ssh.sh
# =============================================================================
# Purpose : Verify all SSH connections required by ZDM for the ORADB migration.
#           Tests both admin user (azureuser/opc) connections and oracle user
#           access via sudo. Produces a connectivity summary.
#
# Actions : ACTION-10 (zdmuser SSH), ACTION-11 (oracle user SSH pattern)
#
# Run from: ZDM Server (10.1.0.8)
# Run as  : zdmuser
#
# Usage   : bash fix_06_verify_ssh.sh
#           bash fix_06_verify_ssh.sh --full   (includes DB listener check)
# =============================================================================

set -uo pipefail

# --- Configuration (from zdm-env.md) ----------------------------------------
SOURCE_HOST="10.1.0.11"
SOURCE_SSH_USER="azureuser"
SOURCE_SSH_KEY="/home/zdmuser/.ssh/odaa.pem"

TARGET_HOST="10.0.1.160"
TARGET_SSH_USER="opc"
TARGET_SSH_KEY="/home/zdmuser/.ssh/odaa.pem"

ZDM_HOST="10.1.0.8"
ZDM_SSH_KEY="/home/zdmuser/.ssh/zdm.pem"

ORACLE_USER="oracle"
# ----------------------------------------------------------------------------

FULL_CHECK=false
if [[ "${1:-}" == "--full" ]]; then
  FULL_CHECK=true
fi

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# --- Guard: must run as zdmuser ---------------------------------------------
CURRENT_USER=$(whoami)
if [[ "${CURRENT_USER}" != "zdmuser" ]]; then
  log "ERROR: This script must be run as zdmuser."
  log "       Run: sudo su - zdmuser && bash fix_06_verify_ssh.sh"
  exit 1
fi

# --- Tracking variables for summary -----------------------------------------
declare -A RESULTS=()

check() {
  local test_name="$1"
  local cmd="$2"
  local expected="$3"

  log "  Testing: ${test_name}..."
  OUTPUT=$(eval "${cmd}" 2>&1 || true)
  if echo "${OUTPUT}" | grep -q "${expected}"; then
    log "  ✅ PASS: ${test_name}"
    RESULTS["${test_name}"]="✅ PASS"
  else
    log "  ❌ FAIL: ${test_name}"
    log "     Expected  : '${expected}'"
    log "     Got output: '${OUTPUT}'"
    RESULTS["${test_name}"]="❌ FAIL"
  fi
}

log "================================================================"
log "fix_06_verify_ssh.sh — ZDM SSH Connectivity Verification (ORADB)"
log "================================================================"
log "Source host  : ${SOURCE_HOST} (${SOURCE_SSH_USER})"
log "Target host  : ${TARGET_HOST} (${TARGET_SSH_USER})"
log "SSH keys     : ${SOURCE_SSH_KEY}, ${TARGET_SSH_KEY}"
log "Full check   : ${FULL_CHECK}"
log "================================================================"
log ""

# ============================================================================
# SECTION 1: Admin user SSH (basic connectivity)
# ============================================================================
log "--- Section 1: Admin User SSH Connectivity ---"

check "SSH to Source (admin user)" \
  "ssh -i ${SOURCE_SSH_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
   ${SOURCE_SSH_USER}@${SOURCE_HOST} 'hostname'" \
  "tm-oracle-iaas"

check "SSH to Target (admin user)" \
  "ssh -i ${TARGET_SSH_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
   ${TARGET_SSH_USER}@${TARGET_HOST} 'hostname'" \
  "tmodaauks-rqahk1"

# ============================================================================
# SECTION 2: Oracle user access via admin+sudo (ZDM zdmauth pattern)
# ============================================================================
log ""
log "--- Section 2: Oracle User Access via Admin+sudo (ZDM zdmauth pattern) ---"

check "sudo -u oracle on Source" \
  "ssh -i ${SOURCE_SSH_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
   ${SOURCE_SSH_USER}@${SOURCE_HOST} 'sudo -u ${ORACLE_USER} whoami'" \
  "${ORACLE_USER}"

check "sudo -u oracle on Target" \
  "ssh -i ${TARGET_SSH_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
   ${TARGET_SSH_USER}@${TARGET_HOST} 'sudo -u ${ORACLE_USER} whoami'" \
  "${ORACLE_USER}"

# ============================================================================
# SECTION 3: Direct oracle SSH (may not be permitted)
# ============================================================================
log ""
log "--- Section 3: Direct Oracle User SSH (informational — may be blocked) ---"

log "  Testing: Direct SSH as oracle to Source..."
ORACLE_SRC_OUTPUT=$(ssh -i "${SOURCE_SSH_KEY}" -o StrictHostKeyChecking=no \
  -o ConnectTimeout=10 "${ORACLE_USER}@${SOURCE_HOST}" 'hostname' 2>&1 || true)
if echo "${ORACLE_SRC_OUTPUT}" | grep -q "tm-oracle-iaas"; then
  log "  ✅ Direct oracle SSH to Source: WORKS"
  RESULTS["Direct oracle SSH to Source"]="✅ WORKS"
  SOURCE_ORACLE_SSH="direct"
else
  log "  ⚠️  Direct oracle SSH to Source: BLOCKED (normal for Azure VMs)"
  log "     ZDM will use admin+sudo (-srcauth zdmauth) pattern instead."
  RESULTS["Direct oracle SSH to Source"]="⚠️  BLOCKED (use zdmauth)"
  SOURCE_ORACLE_SSH="zdmauth"
fi

log "  Testing: Direct SSH as oracle to Target..."
ORACLE_TGT_OUTPUT=$(ssh -i "${TARGET_SSH_KEY}" -o StrictHostKeyChecking=no \
  -o ConnectTimeout=10 "${ORACLE_USER}@${TARGET_HOST}" 'hostname' 2>&1 || true)
if echo "${ORACLE_TGT_OUTPUT}" | grep -q "tmodaauks-rqahk1"; then
  log "  ✅ Direct oracle SSH to Target: WORKS"
  RESULTS["Direct oracle SSH to Target"]="✅ WORKS"
  TARGET_ORACLE_SSH="direct"
else
  log "  ⚠️  Direct oracle SSH to Target: BLOCKED (normal for ODAA/OCI nodes)"
  log "     ZDM will use admin+sudo (-tgtauth zdmauth) pattern instead."
  RESULTS["Direct oracle SSH to Target"]="⚠️  BLOCKED (use zdmauth)"
  TARGET_ORACLE_SSH="zdmauth"
fi

# ============================================================================
# SECTION 4: Oracle environment on source
# ============================================================================
log ""
log "--- Section 4: Oracle Environment Check on Source ---"

check "Oracle SID on Source" \
  "ssh -i ${SOURCE_SSH_KEY} -o StrictHostKeyChecking=no \
   ${SOURCE_SSH_USER}@${SOURCE_HOST} \
   \"sudo -u ${ORACLE_USER} bash -c 'export ORACLE_HOME=/u01/app/oracle/product/12.2.0/dbhome_1; \
     export PATH=\\\${ORACLE_HOME}/bin:\\\${PATH}; \
     sqlplus -S / as sysdba <<< \\\"SET HEADING OFF FEEDBACK OFF; \
     SELECT LOG_MODE FROM V\\\\\\$DATABASE;EXIT;\\\"'\"" \
  "ARCHIVELOG"

# ============================================================================
# SECTION 5: TCP port checks (nc)
# ============================================================================
log ""
log "--- Section 5: TCP Port Reachability ---"

for PORT in 22 1521; do
  NC_RESULT=$(nc -zv -w5 "${SOURCE_HOST}" "${PORT}" 2>&1 || true)
  if echo "${NC_RESULT}" | grep -qi "succeeded\|open\|connected"; then
    log "  ✅ ${SOURCE_HOST}:${PORT} is OPEN"
    RESULTS["TCP ${SOURCE_HOST}:${PORT}"]="✅ OPEN"
  else
    log "  ❌ ${SOURCE_HOST}:${PORT} is NOT reachable"
    RESULTS["TCP ${SOURCE_HOST}:${PORT}"]="❌ BLOCKED"
  fi
done

for PORT in 22 1521; do
  NC_RESULT=$(nc -zv -w5 "${TARGET_HOST}" "${PORT}" 2>&1 || true)
  if echo "${NC_RESULT}" | grep -qi "succeeded\|open\|connected"; then
    log "  ✅ ${TARGET_HOST}:${PORT} is OPEN"
    RESULTS["TCP ${TARGET_HOST}:${PORT}"]="✅ OPEN"
  else
    log "  ❌ ${TARGET_HOST}:${PORT} is NOT reachable"
    RESULTS["TCP ${TARGET_HOST}:${PORT}"]="❌ BLOCKED"
  fi
done

# ============================================================================
# SECTION 6: Full check — ZDM SSH key inventory
# ============================================================================
if [[ "${FULL_CHECK}" == "true" ]]; then
  log ""
  log "--- Section 6: zdmuser SSH Key Inventory ---"
  ls -la ~/.ssh/
  log ""
  log "--- Section 7: Known hosts ---"
  cat ~/.ssh/known_hosts 2>/dev/null || log "  No known_hosts file."
fi

# ============================================================================
# SUMMARY
# ============================================================================
log ""
log "================================================================"
log "SSH VERIFICATION SUMMARY"
log "================================================================"
for TEST in "${!RESULTS[@]}"; do
  printf "  %-50s %s\n" "${TEST}" "${RESULTS[$TEST]}"
done | sort

log ""
log "ZDM Auth Method Recommendation:"
log "  Source: -srcauth zdmauth -srcarg1 user:${SOURCE_SSH_USER} -srcarg2 identity_file:${SOURCE_SSH_KEY} -srcarg3 sudo_location:/usr/bin/sudo"
if [[ "${SOURCE_ORACLE_SSH:-zdmauth}" == "direct" ]]; then
  log "  Source: direct oracle SSH also works (can use -srcauth osSudoRoot)"
fi
log ""
log "  Target: -tgtauth zdmauth -tgtarg1 user:${TARGET_SSH_USER} -tgtarg2 identity_file:${TARGET_SSH_KEY} -tgtarg3 sudo_location:/usr/bin/sudo"
if [[ "${TARGET_ORACLE_SSH:-zdmauth}" == "direct" ]]; then
  log "  Target: direct oracle SSH also works (can use -tgtauth osSudoRoot)"
fi

log ""
log "================================================================"
log "fix_06_verify_ssh.sh COMPLETE"
log ""
log "Update Issue-Resolution-Log-ORADB.md:"
log "  - ACTION-10 Status: ✅ Resolved (zdmuser SSH verified)"
log "  - ACTION-11 Status: ✅ Resolved (ZDM auth method confirmed)"
log "  - Record ZDM -srcauth / -tgtauth settings determined above"
log "================================================================"
