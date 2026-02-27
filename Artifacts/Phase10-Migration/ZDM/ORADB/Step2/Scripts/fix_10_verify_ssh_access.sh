#!/usr/bin/env bash
# =============================================================================
# fix_10_verify_ssh_access.sh
#
# Purpose : Verify all SSH paths required by ZDM from the ZDM server to the
#           source and target database servers. Tests both admin user SSH and
#           sudo-to-oracle capability.
#
# ZDM SSH model:
#   - ZDM SSHes to the admin user (azureuser on source, opc on target)
#   - ZDM then sudo-s to oracle for file-level operations
#   - Direct SSH as the oracle OS user is NOT required (and usually blocked)
#
# Target  : ZDM server (10.1.0.8) — run locally as zdmuser.
#
# Run as  : zdmuser on ZDM server (10.1.0.8)
# Usage   : bash fix_10_verify_ssh_access.sh
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — sourced from zdm-env.md values
# ---------------------------------------------------------------------------
SOURCE_HOST="${SOURCE_HOST:-10.1.0.11}"
SOURCE_SSH_USER="${SOURCE_SSH_USER:-azureuser}"
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-${HOME}/.ssh/odaa.pem}"

TARGET_HOST="${TARGET_HOST:-10.0.1.160}"
TARGET_SSH_USER="${TARGET_SSH_USER:-opc}"
TARGET_SSH_KEY="${TARGET_SSH_KEY:-${HOME}/.ssh/odaa.pem}"

ORACLE_USER="${ORACLE_USER:-oracle}"
ZDM_HOME="${ZDM_HOME:-/u01/app/zdmhome}"

LOG_FILE="fix_10_$(date +%Y%m%d_%H%M%S).log"
PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Logging / test helpers
# ---------------------------------------------------------------------------
log()     { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"; }
info()    { log "INFO  $*"; }
sep()     { log "----------------------------------------------------------------------"; }
result()  {
  local test_name="$1" status="$2" detail="${3:-}"
  if [ "${status}" = "PASS" ]; then
    log "  ✅ [PASS] ${test_name}${detail:+ — ${detail}}"
    PASS=$((PASS + 1))
  else
    log "  ❌ [FAIL] ${test_name}${detail:+ — ${detail}}"
    FAIL=$((FAIL + 1))
  fi
}

run_ssh_test() {
  local label="$1" key="$2" user="$3" host="$4" cmd="$5"
  local output
  output=$(ssh -i "${key}" \
               -o StrictHostKeyChecking=no \
               -o ConnectTimeout=10 \
               -o BatchMode=yes \
               "${user}@${host}" \
               "${cmd}" 2>&1) && \
    result "${label}" "PASS" "${output}" || \
    result "${label}" "FAIL" "${output}"
}

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------
sep
info "Starting fix_10: Verify SSH Access for ZDM"
info "Running as: $(whoami) on $(hostname)"
info "Log file  : ${LOG_FILE}"
sep
echo ""
echo "  Test plan:"
echo "  T01: SSH to source admin user (${SOURCE_SSH_USER}@${SOURCE_HOST})"
echo "  T02: SSH to source → sudo to oracle"
echo "  T03: SSH to source → oracle can connect to DB (sqlplus test)"
echo "  T04: SSH to target admin user (${TARGET_SSH_USER}@${TARGET_HOST})"
echo "  T05: SSH to target → sudo to oracle"
echo "  T06: SSH to target → oracle can connect to DB (sqlplus test)"
echo "  T07: zdmcli status check (ZDM service running)"
echo "  T08: OCI CLI functional (zdmuser oci config)"
echo ""

# ---------------------------------------------------------------------------
# T01: SSH to source admin user
# ---------------------------------------------------------------------------
sep
info "T01: SSH to source admin user (${SOURCE_SSH_USER}@${SOURCE_HOST})..."
run_ssh_test "T01: Source SSH as ${SOURCE_SSH_USER}" \
  "${SOURCE_SSH_KEY}" "${SOURCE_SSH_USER}" "${SOURCE_HOST}" "hostname"

# ---------------------------------------------------------------------------
# T02: SSH to source → sudo to oracle
# ---------------------------------------------------------------------------
sep
info "T02: SSH to source → sudo -u oracle whoami..."
run_ssh_test "T02: Source sudo to oracle" \
  "${SOURCE_SSH_KEY}" "${SOURCE_SSH_USER}" "${SOURCE_HOST}" "sudo -u ${ORACLE_USER} whoami"

# ---------------------------------------------------------------------------
# T03: SSH to source → oracle sqlplus connectivity
# ---------------------------------------------------------------------------
sep
info "T03: SSH to source → oracle sqlplus test..."
SOURCE_ORACLE_HOME="${SOURCE_ORACLE_HOME:-/u01/app/oracle/product/12.2.0/dbhome_1}"
SOURCE_ORACLE_SID="${SOURCE_ORACLE_SID:-oradb}"
run_ssh_test "T03: Source sqlplus connection" \
  "${SOURCE_SSH_KEY}" "${SOURCE_SSH_USER}" "${SOURCE_HOST}" \
  "sudo -u ${ORACLE_USER} bash -c 'ORACLE_HOME=${SOURCE_ORACLE_HOME} ORACLE_SID=${SOURCE_ORACLE_SID} PATH=${SOURCE_ORACLE_HOME}/bin:\$PATH sqlplus -S / as sysdba <<< \"SELECT 1 FROM DUAL;\" 2>&1 | grep -c 1'"

# ---------------------------------------------------------------------------
# T04: SSH to target admin user
# ---------------------------------------------------------------------------
sep
info "T04: SSH to target admin user (${TARGET_SSH_USER}@${TARGET_HOST})..."
run_ssh_test "T04: Target SSH as ${TARGET_SSH_USER}" \
  "${TARGET_SSH_KEY}" "${TARGET_SSH_USER}" "${TARGET_HOST}" "hostname"

# ---------------------------------------------------------------------------
# T05: SSH to target → sudo to oracle
# ---------------------------------------------------------------------------
sep
info "T05: SSH to target → sudo -u oracle whoami..."
run_ssh_test "T05: Target sudo to oracle" \
  "${TARGET_SSH_KEY}" "${TARGET_SSH_USER}" "${TARGET_HOST}" "sudo -u ${ORACLE_USER} whoami"

# ---------------------------------------------------------------------------
# T06: SSH to target → oracle executable check
# ---------------------------------------------------------------------------
sep
info "T06: SSH to target → oracle ORACLE_HOME check..."
TARGET_ORACLE_HOME="${TARGET_ORACLE_HOME:-/u02/app/oracle/product/19.0.0.0/dbhome_1}"
run_ssh_test "T06: Target Oracle binaries accessible" \
  "${TARGET_SSH_KEY}" "${TARGET_SSH_USER}" "${TARGET_HOST}" \
  "sudo -u ${ORACLE_USER} test -x ${TARGET_ORACLE_HOME}/bin/sqlplus && echo 'sqlplus found'"

# ---------------------------------------------------------------------------
# T07: ZDM service running
# ---------------------------------------------------------------------------
sep
info "T07: Checking ZDM service status..."
ZDM_STATUS=$("${ZDM_HOME}/bin/zdmcli" status 2>&1) || true
echo "${ZDM_STATUS}" | tee -a "${LOG_FILE}"
if echo "${ZDM_STATUS}" | grep -qi "Running\|RUNNING"; then
  result "T07: ZDM service status" "PASS" "Service RUNNING"
else
  result "T07: ZDM service status" "FAIL" "Service not running — start with: ${ZDM_HOME}/bin/zdmservice start"
fi

# ---------------------------------------------------------------------------
# T08: OCI CLI connectivity
# ---------------------------------------------------------------------------
sep
info "T08: Testing OCI CLI (oci os ns get)..."
OCI_CONFIG="${OCI_CONFIG_PATH:-${HOME}/.oci/config}"
OCI_OUTPUT=$(oci os ns get --config-file "${OCI_CONFIG}" 2>&1) && \
  result "T08: OCI CLI functional" "PASS" "Namespace reachable" || \
  result "T08: OCI CLI functional" "FAIL" "${OCI_OUTPUT}"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
sep
TOTAL=$((PASS + FAIL))
info "Test results: ${PASS}/${TOTAL} passed, ${FAIL} failed."
echo ""
if [ "${FAIL}" -eq 0 ]; then
  echo "  ✅ All SSH access tests passed. ZDM environment is ready for migration."
else
  echo "  ❌ ${FAIL} test(s) failed. Review and fix before running zdmcli migrate."
  echo ""
  echo "  Common resolutions:"
  echo "  - SSH key issues: ensure zdmuser ~/.ssh/ contains the correct key files"
  echo "  - sudo not granted: add 'azureuser ALL=(oracle) NOPASSWD: ALL' to sudoers on source"
  echo "  - ODAA target: 'opc ALL=(oracle) NOPASSWD: ALL' is normally pre-configured"
  echo "  - ZDM not running: ${ZDM_HOME}/bin/zdmservice start"
  echo "  - OCI CLI config: verify ~/.oci/config has correct user/key/fingerprint/region"
fi
sep
info "Log saved to: ${LOG_FILE}"
