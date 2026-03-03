#!/usr/bin/env bash
# =============================================================================
#  verify_fixes.sh
#  ZDM Migration Step 2 — Final Verification
#  Verifies all required actions from the ORADB Discovery Summary are resolved
#  before proceeding to Step 3 (Generate Migration Artifacts).
#
#  Writes structured results to:
#    Step2/Verification-Results-ORADB.md   (commit to repo)
#    Step2/Verification/<log>.log          (local execution log)
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
ORACLE_SID="oradb"
DB_NAME_UPPER="${ORACLE_SID^^}"

SOURCE_HOST="10.1.0.11"
SOURCE_SSH_USER="azureuser"
SOURCE_SSH_KEY="${HOME}/.ssh/odaa.pem"

TARGET_HOST="10.0.1.160"
TARGET_SSH_USER="opc"
TARGET_SSH_KEY="${HOME}/.ssh/odaa.pem"

ZDM_HOST="10.1.0.8"

OCI_CONFIG_PATH="${HOME}/.oci/config"
OCI_REGION="uk-london-1"

# Expected bucket name pattern (yyyy-mm-dd is flexible)
EXPECTED_BUCKET_PREFIX="zdm-migration-oradb"

# Disk space threshold (%) — warn if above this
SOURCE_DISK_WARN_PCT=85
ZDM_DISK_WARN_PCT=90

VERIFY_DIR="${HOME}/Artifacts/Phase10-Migration/ZDM/${DATABASE_NAME}/Step2/Verification"
LOG_FILE="${VERIFY_DIR}/verify_fixes_$(date +%Y%m%d_%H%M%S).log"

mkdir -p "${VERIFY_DIR}"
exec > >(tee -a "${LOG_FILE}") 2>&1

# =============================================================================
# Per-issue status tracking (values: PASS | FAIL | WARN)
# =============================================================================
ISSUE1_STATUS="FAIL"; ISSUE1_DETAIL="Not checked"
ISSUE2_STATUS="FAIL"; ISSUE2_DETAIL="Not checked"
ISSUE3_STATUS="WARN"; ISSUE3_DETAIL="Not checked"
ISSUE4_STATUS="WARN"; ISSUE4_DETAIL="Not checked"
ISSUE5_STATUS="WARN"; ISSUE5_DETAIL="Not checked"

# =============================================================================
# Helper functions
# =============================================================================
FAIL_COUNT=0
WARN_COUNT=0

pass()  { echo "  ✅ PASS: $1"; }
fail()  { echo "  ❌ FAIL: $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
warn()  { echo "  ⚠️  WARN: $1"; WARN_COUNT=$((WARN_COUNT + 1)); }
info()  { echo "  ℹ️  INFO: $1"; }
check() { echo ""; echo "═══ Check $1: $2 ═══"; }

echo "=============================================================="
echo "  ZDM Step 2: Final Verification — ORADB"
echo "  Database   : ${DATABASE_NAME} (${ORACLE_SID})"
echo "  ZDM Server : ${ZDM_HOST}"
echo "  Source     : ${SOURCE_SSH_USER}@${SOURCE_HOST}"
echo "  Target     : ${TARGET_SSH_USER}@${TARGET_HOST}"
echo "  Timestamp  : $(date)"
echo "  Log        : ${LOG_FILE}"
echo "  Results    : $(dirname "${VERIFY_DIR}")/Verification-Results-${DB_NAME_UPPER}.md"
echo "=============================================================="

# =============================================================================
# ISSUE 1: OCI Object Storage bucket configured and accessible
# (Required for ONLINE_PHYSICAL migration)
# =============================================================================
check "1" "OCI Object Storage bucket configured and accessible"

ISSUE1_OCI_OK=false
ISSUE1_BUCKET_NAME=""
ISSUE1_NAMESPACE=""

# Step 1a: OCI CLI must be available
if ! command -v oci &>/dev/null; then
  fail "OCI CLI not found in PATH for zdmuser"
  ISSUE1_STATUS="FAIL"; ISSUE1_DETAIL="OCI CLI not found in PATH"
else
  OCI_VER=$(oci --version 2>&1 | head -1)
  info "OCI CLI found: ${OCI_VER}"

  # Step 1b: Config must exist
  if [[ ! -f "${OCI_CONFIG_PATH}" ]]; then
    fail "OCI config not found at ${OCI_CONFIG_PATH}"
    ISSUE1_STATUS="FAIL"; ISSUE1_DETAIL="OCI config not found — run verify_oci_cli_zdmuser.sh"
  else
    # Step 1c: Get namespace
    ISSUE1_NAMESPACE=$(oci os ns get \
      --config-file "${OCI_CONFIG_PATH}" \
      --query "data" \
      --raw-output 2>&1) || ISSUE1_NAMESPACE=""

    if [[ -z "${ISSUE1_NAMESPACE}" ]]; then
      fail "Could not retrieve OCI Object Storage namespace — check OCI CLI auth"
      ISSUE1_STATUS="FAIL"; ISSUE1_DETAIL="oci os ns get failed — verify OCI CLI config"
    else
      info "OCI OSS Namespace: ${ISSUE1_NAMESPACE}"

      # Step 1d: Find a bucket matching the expected prefix
      BUCKET_LIST=$(oci os bucket list \
        --namespace-name "${ISSUE1_NAMESPACE}" \
        --config-file "${OCI_CONFIG_PATH}" \
        --region "${OCI_REGION}" \
        --query "data[?starts_with(name, '${EXPECTED_BUCKET_PREFIX}')].name" \
        --raw-output 2>&1) || BUCKET_LIST=""

      # Clean up multiline JSON output to get first match
      ISSUE1_BUCKET_NAME=$(echo "${BUCKET_LIST}" | \
        grep -o "\"${EXPECTED_BUCKET_PREFIX}[^\"]*\"" | head -1 | tr -d '"' || echo "")

      if [[ -z "${ISSUE1_BUCKET_NAME}" ]]; then
        fail "No OCI bucket matching '${EXPECTED_BUCKET_PREFIX}*' found in ${OCI_REGION}"
        ISSUE1_STATUS="FAIL"
        ISSUE1_DETAIL="No bucket matching '${EXPECTED_BUCKET_PREFIX}*' found — run create_oci_bucket.sh and update zdm-env.md"
      else
        pass "OCI bucket found: '${ISSUE1_BUCKET_NAME}' (namespace: ${ISSUE1_NAMESPACE})"
        ISSUE1_STATUS="PASS"
        ISSUE1_DETAIL="Bucket '${ISSUE1_BUCKET_NAME}' exists in ${OCI_REGION} (namespace: ${ISSUE1_NAMESPACE})"
      fi
    fi
  fi
fi

# =============================================================================
# ISSUE 2: OCI CLI authentication for zdmuser
# =============================================================================
check "2" "OCI CLI authenticated for zdmuser on ZDM server"

if ! command -v oci &>/dev/null; then
  fail "OCI CLI not installed for zdmuser"
  ISSUE2_STATUS="FAIL"; ISSUE2_DETAIL="OCI CLI not found — install and configure via verify_oci_cli_zdmuser.sh"
elif [[ ! -f "${OCI_CONFIG_PATH}" ]]; then
  fail "OCI config missing at ${OCI_CONFIG_PATH}"
  ISSUE2_STATUS="FAIL"; ISSUE2_DETAIL="OCI config not found — run verify_oci_cli_zdmuser.sh"
else
  OCI_PRIVATE_KEY_PATH="${HOME}/.oci/oci_api_key.pem"

  # Check private key
  if [[ ! -f "${OCI_PRIVATE_KEY_PATH}" ]]; then
    fail "OCI private key not found at ${OCI_PRIVATE_KEY_PATH}"
    ISSUE2_STATUS="FAIL"; ISSUE2_DETAIL="Private key missing at ${OCI_PRIVATE_KEY_PATH}"
  else
    KEY_PERMS=$(stat -c "%a" "${OCI_PRIVATE_KEY_PATH}" 2>/dev/null || echo "0")
    if [[ "${KEY_PERMS}" != "600" ]]; then
      warn "Private key permissions are ${KEY_PERMS} (expected 600) — fix with: chmod 600 ${OCI_PRIVATE_KEY_PATH}"
    fi

    # Test OCI API connectivity
    IAM_TEST=$(oci iam region list \
      --config-file "${OCI_CONFIG_PATH}" \
      --query "data[?name=='${OCI_REGION}'].name" \
      --raw-output 2>&1) || IAM_TEST=""

    if [[ "${IAM_TEST}" == "${OCI_REGION}" ]]; then
      pass "OCI CLI is authenticated — oci iam region list returned '${OCI_REGION}'"
      ISSUE2_STATUS="PASS"; ISSUE2_DETAIL="oci iam region list succeeded for region '${OCI_REGION}'"
    else
      fail "OCI CLI connectivity test failed: ${IAM_TEST}"
      ISSUE2_STATUS="FAIL"; ISSUE2_DETAIL="oci iam region list failed — run verify_oci_cli_zdmuser.sh for diagnostics"
    fi
  fi
fi

# =============================================================================
# ISSUE 3: Source disk space (WARN if > threshold)
# =============================================================================
check "3" "Source root filesystem disk usage (threshold: ${SOURCE_DISK_WARN_PCT}%)"

SOURCE_DISK_OUTPUT=""
if ! SOURCE_DISK_OUTPUT=$(ssh -i "${SOURCE_SSH_KEY}" \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=10 \
    "${SOURCE_SSH_USER}@${SOURCE_HOST}" "df -h /" 2>&1); then
  warn "Cannot SSH to source ${SOURCE_HOST} to check disk space: ${SOURCE_DISK_OUTPUT}"
  ISSUE3_STATUS="WARN"; ISSUE3_DETAIL="SSH to ${SOURCE_HOST} failed — cannot verify disk space"
else
  SOURCE_DISK_LINE=$(echo "${SOURCE_DISK_OUTPUT}" | tail -1)
  SOURCE_DISK_PCT=$(echo "${SOURCE_DISK_LINE}" | awk '{print $5}' | tr -d '%')
  SOURCE_DISK_FREE=$(echo "${SOURCE_DISK_LINE}" | awk '{print $4}')

  info "Source / disk: ${SOURCE_DISK_LINE}"

  if [[ "${SOURCE_DISK_PCT}" -ge "${SOURCE_DISK_WARN_PCT}" ]]; then
    warn "Source root disk is at ${SOURCE_DISK_PCT}% (threshold: ${SOURCE_DISK_WARN_PCT}%). Free: ${SOURCE_DISK_FREE}"
    warn "Run purge_source_archivelogs.sh to free space before starting migration"
    ISSUE3_STATUS="WARN"
    ISSUE3_DETAIL="Root disk at ${SOURCE_DISK_PCT}% (threshold: ${SOURCE_DISK_WARN_PCT}%); free: ${SOURCE_DISK_FREE} — run purge_source_archivelogs.sh"
  else
    pass "Source root disk at ${SOURCE_DISK_PCT}% — within threshold (< ${SOURCE_DISK_WARN_PCT}%). Free: ${SOURCE_DISK_FREE}"
    ISSUE3_STATUS="PASS"
    ISSUE3_DETAIL="Root disk at ${SOURCE_DISK_PCT}%; free: ${SOURCE_DISK_FREE}"
  fi
fi

# =============================================================================
# ISSUE 4: ZDM server disk space (WARN only)
# =============================================================================
check "4" "ZDM server root filesystem disk usage (threshold: ${ZDM_DISK_WARN_PCT}%)"

ZDM_DISK_LINE=$(df -h / | tail -1)
ZDM_DISK_PCT=$(echo "${ZDM_DISK_LINE}" | awk '{print $5}' | tr -d '%')
ZDM_DISK_FREE=$(echo "${ZDM_DISK_LINE}" | awk '{print $4}')

info "ZDM / disk: ${ZDM_DISK_LINE}"

if [[ "${ZDM_DISK_PCT}" -ge "${ZDM_DISK_WARN_PCT}" ]]; then
  warn "ZDM root disk at ${ZDM_DISK_PCT}% (threshold: ${ZDM_DISK_WARN_PCT}%). Free: ${ZDM_DISK_FREE}"
  ISSUE4_STATUS="WARN"
  ISSUE4_DETAIL="ZDM root disk at ${ZDM_DISK_PCT}%; free: ${ZDM_DISK_FREE} — review before starting migration"
else
  pass "ZDM root disk at ${ZDM_DISK_PCT}% — within threshold. Free: ${ZDM_DISK_FREE}"
  ISSUE4_STATUS="PASS"
  ISSUE4_DETAIL="ZDM root disk at ${ZDM_DISK_PCT}%; free: ${ZDM_DISK_FREE}"
fi

# Note from discovery: 24 GB free on ZDM vs soft-recommendation of 50 GB.
# For a 2.14 GB source database, 24 GB is sufficient.
if [[ "${ZDM_DISK_PCT}" -lt 50 ]]; then
  info "ZDM disk advisory: 24 GB free is sufficient for ORADB (2.14 GB source). No action required."
fi

# =============================================================================
# ISSUE 5: SSH connectivity — ZDM → Target (cross-network WARN)
# =============================================================================
check "5" "SSH connectivity ZDM → Target (${TARGET_SSH_USER}@${TARGET_HOST}) [cross-network]"

TARGET_SSH_TEST=""
if TARGET_SSH_TEST=$(ssh -i "${TARGET_SSH_KEY}" \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=15 \
    "${TARGET_SSH_USER}@${TARGET_HOST}" "echo ok" 2>&1) && [[ "${TARGET_SSH_TEST}" == "ok" ]]; then
  pass "ZDM → Target SSH connectivity confirmed (${TARGET_SSH_USER}@${TARGET_HOST})"
  ISSUE5_STATUS="PASS"
  ISSUE5_DETAIL="SSH to ${TARGET_HOST} as ${TARGET_SSH_USER} succeeded"
else
  warn "ZDM → Target SSH failed or timed out: ${TARGET_SSH_TEST}"
  warn "Cross-network (Azure 10.1.x.x → OCI 10.0.x.x) — verify ExpressRoute/FastConnect and NSG rules"
  ISSUE5_STATUS="WARN"
  ISSUE5_DETAIL="SSH to ${TARGET_HOST} failed — verify network path (ExpressRoute/VPN) and OCI NSG rules for port 22"
fi

# =============================================================================
# Console Summary
# =============================================================================
echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  VERIFICATION SUMMARY — ${DB_NAME_UPPER}"
echo "══════════════════════════════════════════════════════════════"
echo ""
echo "  Required Actions (must be PASS before Step 3):"
echo "  ────────────────────────────────────────────────"

_icon() {
  case "$1" in
    PASS) echo "✅ PASS" ;;
    FAIL) echo "❌ FAIL" ;;
    WARN) echo "⚠️  WARN" ;;
    *)    echo "❓ UNKNOWN" ;;
  esac
}

echo "  Issue 1 — OCI OSS bucket configured      : $(_icon "${ISSUE1_STATUS}")"
echo "            ${ISSUE1_DETAIL}"
echo "  Issue 2 — OCI CLI auth for zdmuser        : $(_icon "${ISSUE2_STATUS}")"
echo "            ${ISSUE2_DETAIL}"
echo ""
echo "  Recommended Items:"
echo "  ────────────────────────────────────────────────"
echo "  Issue 3 — Source disk space               : $(_icon "${ISSUE3_STATUS}")"
echo "            ${ISSUE3_DETAIL}"
echo "  Issue 4 — ZDM disk space                  : $(_icon "${ISSUE4_STATUS}")"
echo "            ${ISSUE4_DETAIL}"
echo "  Issue 5 — ZDM → Target SSH connectivity   : $(_icon "${ISSUE5_STATUS}")"
echo "            ${ISSUE5_DETAIL}"
echo ""

REQUIRED_FAIL=0
[[ "${ISSUE1_STATUS}" == "FAIL" ]] && REQUIRED_FAIL=$((REQUIRED_FAIL + 1))
[[ "${ISSUE2_STATUS}" == "FAIL" ]] && REQUIRED_FAIL=$((REQUIRED_FAIL + 1))

REQUIRED_PASS=0
[[ "${ISSUE1_STATUS}" == "PASS" ]] && REQUIRED_PASS=$((REQUIRED_PASS + 1))
[[ "${ISSUE2_STATUS}" == "PASS" ]] && REQUIRED_PASS=$((REQUIRED_PASS + 1))

if [[ "${REQUIRED_FAIL}" -eq 0 ]]; then
  PROCEED_LINE="✅ YES — all 2 required actions resolved"
  COMMIT_MSG_BODY="Step2 verification passed: all required actions resolved for ${DB_NAME_UPPER}"
else
  PROCEED_LINE="❌ NO — ${REQUIRED_FAIL} required action(s) still pending"
  COMMIT_MSG_BODY="Step2 verification: ${REQUIRED_PASS}/2 required actions resolved for ${DB_NAME_UPPER}"
fi

echo "  ────────────────────────────────────────────────"
echo "  Required Pass : ${REQUIRED_PASS}/2"
echo "  Failures      : ${REQUIRED_FAIL}"
echo "  Warnings      : ${WARN_COUNT}"
echo "  Proceed to Step 3: ${PROCEED_LINE}"
echo "══════════════════════════════════════════════════════════════"
echo ""

echo "verify_fixes.sh completed at $(date)"
echo ""

# =============================================================================
# Write structured Markdown results file (commit to repo for Step 3)
# =============================================================================
RESULTS_FILE="$(dirname "${VERIFY_DIR}")/Verification-Results-${DB_NAME_UPPER}.md"

ISSUE1_ICON=$(_icon "${ISSUE1_STATUS}")
ISSUE2_ICON=$(_icon "${ISSUE2_STATUS}")
ISSUE3_ICON=$(_icon "${ISSUE3_STATUS}")
ISSUE4_ICON=$(_icon "${ISSUE4_STATUS}")
ISSUE5_ICON=$(_icon "${ISSUE5_STATUS}")

cat > "${RESULTS_FILE}" << RESULTS_EOF
# Step 2 Verification Results: ${DB_NAME_UPPER}

**Verified:** $(date -u '+%Y-%m-%d %H:%M:%S UTC')
**Verified By:** $(whoami) on $(hostname)
**Log:** \`$(basename "${LOG_FILE}")\` (in \`Step2/Verification/\`)

---

## Required Actions (Must Be Resolved Before Step 3)

| # | Issue | Status | Detail |
|---|-------|--------|--------|
| 1 | OCI Object Storage bucket configured | ${ISSUE1_ICON} | ${ISSUE1_DETAIL} |
| 2 | OCI CLI authenticated for zdmuser on ZDM server | ${ISSUE2_ICON} | ${ISSUE2_DETAIL} |

## Recommended Items

| # | Item | Status | Detail |
|---|------|--------|--------|
| 3 | Source root disk space | ${ISSUE3_ICON} | ${ISSUE3_DETAIL} |
| 4 | ZDM server root disk space | ${ISSUE4_ICON} | ${ISSUE4_DETAIL} |
| 5 | ZDM → Target SSH connectivity (cross-network) | ${ISSUE5_ICON} | ${ISSUE5_DETAIL} |

---

## Summary

- **Required Actions Resolved:** ${REQUIRED_PASS}/2
- **Proceed to Step 3:** ${PROCEED_LINE}

## Manual Decision Items (Not Script-Checkable)

The following items must be confirmed in the Migration Questionnaire before Step 3:

| # | Item | Action Required |
|---|------|----------------|
| 3 | Target \`DB_UNIQUE_NAME\` confirmed (no conflict with \`oradb01m\`) | Update Migration-Questionnaire-ORADB.md Section A.4 |
| 5 | Target PDB name for \`PDB1\` decided | Update Migration-Questionnaire-ORADB.md Section A.3 |
| 6 | \`SYS.SYS_HUB\` DB link reviewed (keep/drop decision) | Note in Issue-Resolution-Log-ORADB.md Issue 6 |

---

*Generated by verify_fixes.sh — ZDM Migration Step 2 | ORADB*
RESULTS_EOF

echo "  📄 Verification results written to:"
echo "  ${RESULTS_FILE}"
echo ""
echo "  Copy the results file to your repo and commit when ready to proceed to Step 3:"
echo "    # From developer workstation — copy file from ZDM server to repo:"
echo "    scp -i <zdm_key> azureuser@10.1.0.8:/home/zdmuser/Artifacts/Phase10-Migration/ZDM/${DB_NAME_UPPER}/Step2/Verification-Results-${DB_NAME_UPPER}.md \\"
echo "        Artifacts/Phase10-Migration/ZDM/${DB_NAME_UPPER}/Step2/Verification-Results-${DB_NAME_UPPER}.md"
echo ""
echo "    # Then commit:"
echo "    git add Artifacts/Phase10-Migration/ZDM/${DB_NAME_UPPER}/Step2/Verification-Results-${DB_NAME_UPPER}.md"
echo "    git commit -m \"${COMMIT_MSG_BODY}\""
echo ""

if [[ "${REQUIRED_FAIL}" -gt 0 ]]; then
  echo "  ❌ ${REQUIRED_FAIL} required action(s) unresolved. Resolve and re-run verify_fixes.sh."
  echo ""
  exit 1
fi
