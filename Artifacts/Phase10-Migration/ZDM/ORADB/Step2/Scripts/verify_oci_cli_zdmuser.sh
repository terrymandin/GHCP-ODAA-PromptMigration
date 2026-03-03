#!/usr/bin/env bash
# =============================================================================
#  verify_oci_cli_zdmuser.sh
#  ZDM Migration Step 2 — Issue 2 Remediation
#  Verifies that the OCI CLI is installed and correctly configured under
#  the zdmuser account on the ZDM server. Provides remediation guidance
#  if any check fails.
#
#  Database : ORADB
#  Run as   : zdmuser on ZDM server (tm-vm-odaa-oracle-jumpbox / 10.1.0.8)
# =============================================================================

set -euo pipefail

# ── User Guard ────────────────────────────────────────────────────────────────
if [[ "$(whoami)" != "zdmuser" ]]; then
  echo "ERROR: This script must be run as zdmuser. Current user: $(whoami)"
  echo "       Switch with: sudo su - zdmuser"
  exit 1
fi

# =============================================================================
# Configuration
# =============================================================================
DATABASE_NAME="ORADB"
OCI_CONFIG_PATH="${HOME}/.oci/config"
OCI_PRIVATE_KEY_PATH="${HOME}/.oci/oci_api_key.pem"
OCI_REGION="uk-london-1"

# Known values from zdm-env.md (for interactive setup guidance)
KNOWN_USER_OCID="ocid1.user.oc1..aaaaaaaakfe5cirdq7vkkrhogjrgcrgftvwb7mdoehujgchefpqv54vhsnoa"
KNOWN_TENANCY_OCID="ocid1.tenancy.oc1..aaaaaaaarvyhjcn7wkkxxx5g3o7lgqks23bmsjtsticz3gtg5xs5qyrwkftq"
KNOWN_FINGERPRINT="7f:05:c1:f2:5c:3a:46:ec:9f:95:44:c8:77:a4:50:f9"

LOG_DIR="${HOME}/Artifacts/Phase10-Migration/ZDM/${DATABASE_NAME}/Step2/Logs"
LOG_FILE="${LOG_DIR}/verify_oci_cli_zdmuser_$(date +%Y%m%d_%H%M%S).log"

mkdir -p "${LOG_DIR}"
exec > >(tee -a "${LOG_FILE}") 2>&1

# =============================================================================
# Helper functions
# =============================================================================
FAIL_COUNT=0
WARN_COUNT=0

pass() { echo "  ✅ PASS: $1"; }
fail() { echo "  ❌ FAIL: $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
warn() { echo "  ⚠️  WARN: $1"; WARN_COUNT=$((WARN_COUNT + 1)); }
info() { echo "  ℹ️  INFO: $1"; }
step() { echo ""; echo "── Check $1: $2 ──"; }

echo "=============================================================="
echo "  ZDM Step 2: Verify OCI CLI Config for zdmuser"
echo "  Database  : ${DATABASE_NAME}"
echo "  User      : $(whoami)"
echo "  HOME      : ${HOME}"
echo "  Timestamp : $(date)"
echo "  Log       : ${LOG_FILE}"
echo "=============================================================="

# =============================================================================
# Check 1: OCI CLI binary
# =============================================================================
step "1" "OCI CLI binary in PATH"

if command -v oci &>/dev/null; then
  OCI_VER=$(oci --version 2>&1 | head -1)
  pass "OCI CLI found: ${OCI_VER}"
else
  fail "OCI CLI not found in PATH for user $(whoami)."
  echo ""
  echo "  Install OCI CLI (run as zdmuser):"
  echo "    bash -c \"\$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)\""
  echo "  Or if already installed for another user, add to PATH:"
  echo "    export PATH=\$PATH:/home/azureuser/bin/oci  # adjust path"
fi

# =============================================================================
# Check 2: OCI config file exists
# =============================================================================
step "2" "OCI config file at ${OCI_CONFIG_PATH}"

if [[ -f "${OCI_CONFIG_PATH}" ]]; then
  pass "OCI config file exists at ${OCI_CONFIG_PATH}"
else
  fail "OCI config not found at ${OCI_CONFIG_PATH}"
  echo ""
  echo "  Option A — Copy from azureuser (if already configured there):"
  echo "    sudo cp -r /home/azureuser/.oci ${HOME}/.oci"
  echo "    sudo chown -R zdmuser:zdmuser ${HOME}/.oci"
  echo "    chmod 700 ${HOME}/.oci"
  echo "    chmod 600 ${HOME}/.oci/config ${HOME}/.oci/oci_api_key.pem"
  echo ""
  echo "  Option B — Run OCI setup interactively:"
  echo "    oci setup config"
  echo ""
  echo "  Interactive prompts — use these values:"
  echo "    User OCID        : ${KNOWN_USER_OCID}"
  echo "    Tenancy OCID     : ${KNOWN_TENANCY_OCID}"
  echo "    Region           : ${OCI_REGION}"
  echo "    API Key Fingerprint: ${KNOWN_FINGERPRINT}"
  echo "    Private key path : ${OCI_PRIVATE_KEY_PATH}"
fi

# =============================================================================
# Check 3: OCI private key exists and has correct permissions
# =============================================================================
step "3" "OCI private key at ${OCI_PRIVATE_KEY_PATH}"

if [[ -f "${OCI_PRIVATE_KEY_PATH}" ]]; then
  KEY_PERMS=$(stat -c "%a" "${OCI_PRIVATE_KEY_PATH}" 2>/dev/null || echo "unknown")
  if [[ "${KEY_PERMS}" == "600" ]]; then
    pass "Private key exists with correct permissions (600)"
  else
    warn "Private key exists but permissions are ${KEY_PERMS} (expected 600)"
    echo "    Fix with: chmod 600 ${OCI_PRIVATE_KEY_PATH}"
  fi
else
  fail "OCI private key not found at ${OCI_PRIVATE_KEY_PATH}"
  echo ""
  echo "  Copy the private key from a secure location:"
  echo "    scp -i ~/.ssh/zdm.pem /secure/path/oci_api_key.pem zdmuser@10.1.0.8:${OCI_PRIVATE_KEY_PATH}"
  echo "  Then set permissions:"
  echo "    chmod 600 ${OCI_PRIVATE_KEY_PATH}"
fi

# =============================================================================
# Check 4: OCI config references correct key path
# =============================================================================
step "4" "OCI config key_file references correct path"

if [[ -f "${OCI_CONFIG_PATH}" ]]; then
  CONFIG_KEY_FILE=$(grep -E "^key_file" "${OCI_CONFIG_PATH}" | head -1 | awk -F= '{print $2}' | xargs 2>/dev/null || echo "not found")
  CONFIG_KEY_FILE_EXPANDED="${CONFIG_KEY_FILE/#\~/$HOME}"
  if [[ -f "${CONFIG_KEY_FILE_EXPANDED}" ]]; then
    pass "Config key_file '${CONFIG_KEY_FILE}' resolves to an existing file"
  else
    fail "Config key_file '${CONFIG_KEY_FILE}' does not exist at '${CONFIG_KEY_FILE_EXPANDED}'"
    echo "    Update ${OCI_CONFIG_PATH}: set key_file=${OCI_PRIVATE_KEY_PATH}"
  fi
else
  info "Skipping key_file check — config does not exist (see Check 2)"
fi

# =============================================================================
# Check 5: OCI directory permissions
# =============================================================================
step "5" "~/.oci directory permissions"

if [[ -d "${HOME}/.oci" ]]; then
  DIR_PERMS=$(stat -c "%a" "${HOME}/.oci" 2>/dev/null || echo "unknown")
  if [[ "${DIR_PERMS}" == "700" ]]; then
    pass "~/.oci directory permissions correct (700)"
  else
    warn "~/.oci directory permissions are ${DIR_PERMS} (expected 700)"
    echo "    Fix with: chmod 700 ${HOME}/.oci"
  fi
else
  info "~/.oci directory not found — will be created when config is set up"
fi

# =============================================================================
# Check 6: OCI CLI connectivity test
# =============================================================================
step "6" "OCI CLI connectivity — oci iam region list"

if [[ "${FAIL_COUNT}" -gt 0 ]]; then
  info "Skipping connectivity test — fix the ${FAIL_COUNT} failure(s) above first."
else
  REGION_OUTPUT=""
  if REGION_OUTPUT=$(oci iam region list \
    --config-file "${OCI_CONFIG_PATH}" \
    --query "data[?name=='${OCI_REGION}'].name" \
    --raw-output 2>&1); then
    if [[ "${REGION_OUTPUT}" == "${OCI_REGION}" ]]; then
      pass "OCI CLI authenticated and can reach OCI API (region '${OCI_REGION}' confirmed)"
    else
      warn "oci iam region list succeeded but region '${OCI_REGION}' not found in output: ${REGION_OUTPUT}"
    fi
  else
    fail "OCI CLI connectivity test failed: ${REGION_OUTPUT}"
    echo ""
    echo "  Debug with verbose output:"
    echo "    oci iam region list --config-file ${OCI_CONFIG_PATH} --debug 2>&1 | head -50"
    echo ""
    echo "  Common causes:"
    echo "    - Private key mismatch (fingerprint in config doesn't match actual key)"
    echo "    - Wrong tenancy/user OCID"
    echo "    - Network: ZDM server cannot reach https://identity.uk-london-1.oraclecloud.com"
    echo "    - Time drift: NTP sync required (OCI API requires accurate clock)"
  fi
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "=============================================================="
if [[ "${FAIL_COUNT}" -eq 0 && "${WARN_COUNT}" -eq 0 ]]; then
  echo "  ✅ All OCI CLI checks PASSED — Issue 2 is resolved"
  echo "  OCI CLI is correctly configured for zdmuser."
  echo "  You may now run create_oci_bucket.sh"
elif [[ "${FAIL_COUNT}" -eq 0 ]]; then
  echo "  ⚠️  ${WARN_COUNT} warning(s) — review and fix before migration"
  echo "  OCI CLI appears functional but has minor configuration issues."
else
  echo "  ❌ ${FAIL_COUNT} check(s) FAILED — resolve above before running verify_fixes.sh"
fi
echo ""
echo "  Checks: $((6)) total | FAIL: ${FAIL_COUNT} | WARN: ${WARN_COUNT}"
echo "  Log: ${LOG_FILE}"
echo "=============================================================="
echo ""
echo "verify_oci_cli_zdmuser.sh completed at $(date)"
