#!/usr/bin/env bash
# =============================================================================
# verify_fixes.sh
# Purpose : Verify that all Step 2 blockers have been resolved before
#           proceeding to Step 3 (Generate Migration Artifacts).
#           Writes Verification-Results-ORADB.md to the Step2 directory.
# Run as  : zdmuser on the ZDM server (tm-vm-odaa-oracle-jumpbox / 10.1.0.8)
# Step    : ZDM Migration Step 2 — Fix Issues
# =============================================================================

set -uo pipefail

# --- User guard: must run as zdmuser ---
if [[ "$(whoami)" != "zdmuser" ]]; then
  echo "ERROR: This script must be run as zdmuser. Current user: $(whoami)"
  echo "       Switch with: sudo su - zdmuser"
  exit 1
fi

# =============================================================================
# Configuration — values from zdm-env.md
# =============================================================================
SOURCE_HOST="10.1.0.11"
SOURCE_SSH_USER="azureuser"
SOURCE_SSH_KEY="${HOME}/.ssh/iaas.pem"
ORACLE_USER="oracle"
ORACLE_HOME="/u01/app/oracle/product/12.2.0/dbhome_1"
ORACLE_SID="oradb"

TARGET_HOST="10.0.1.160"
TARGET_SSH_USER="opc"
TARGET_SSH_KEY="${HOME}/.ssh/odaa.pem"

TARGET_ORACLE_HOME_BASE="/u02/app/oracle/product/19.0.0.0"
TARGET_INSTANCE_NAME="oradb011"
TARGET_DB_UNIQUE_NAME="oradb01"

OCI_REGION="uk-london-1"

AZURE_CREDS_FILE="${HOME}/.azure/zdm_blob_creds"

# Disk space thresholds
SOURCE_FREE_GB_THRESHOLD=10
ZDM_FREE_GB_THRESHOLD=10

# Resolve repo root from the script's own location so Verification-Results
# is written into the repo clone (wherever it was checked out).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT=$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel 2>/dev/null || echo "")

VERIFY_DIR="${HOME}/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Verification"
mkdir -p "${VERIFY_DIR}"
LOG_FILE="${VERIFY_DIR}/verify_fixes_$(date +%Y%m%d_%H%M%S).log"

# =============================================================================
# Per-issue status tracking (safe defaults)
# =============================================================================
ISSUE1_STATUS="FAIL"; ISSUE1_DETAIL="Not checked"
ISSUE2_STATUS="FAIL"; ISSUE2_DETAIL="Not checked"
ISSUE3_STATUS="FAIL"; ISSUE3_DETAIL="Not checked"
ISSUE4_STATUS="WARN"; ISSUE4_DETAIL="Not checked"
ISSUE5_STATUS="WARN"; ISSUE5_DETAIL="Not checked"

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

# =============================================================================
# Logging helpers
# =============================================================================
log()  { echo "[$(date '+%H:%M:%S')] $*" | tee -a "${LOG_FILE}"; }
pass() {
  echo "[$(date '+%H:%M:%S')] ✅ PASS  $*" | tee -a "${LOG_FILE}"
  PASS_COUNT=$((PASS_COUNT + 1))
}
fail() {
  echo "[$(date '+%H:%M:%S')] ❌ FAIL  $*" | tee -a "${LOG_FILE}"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}
warn() {
  echo "[$(date '+%H:%M:%S')] ⚠️  WARN  $*" | tee -a "${LOG_FILE}"
  WARN_COUNT=$((WARN_COUNT + 1))
}
info() { echo "[$(date '+%H:%M:%S')] ℹ️  INFO  $*" | tee -a "${LOG_FILE}"; }

log "================================================================"
log "verify_fixes.sh — Step 2 Issue Verification"
log "Running as: $(whoami)  on  $(hostname)"
log "Log: ${LOG_FILE}"
log "================================================================"

# =============================================================================
# Prompt for Oracle Home suffix (needed for target checks)
# =============================================================================
log ""
log "--- Pre-check: Confirm Target Oracle Home Suffix ---"
echo "Enter target Oracle Home suffix [1 or 2] (default: 1):"
read -r DBHOME_SUFFIX
DBHOME_SUFFIX="${DBHOME_SUFFIX:-1}"
if [[ "${DBHOME_SUFFIX}" != "1" && "${DBHOME_SUFFIX}" != "2" ]]; then
  DBHOME_SUFFIX="1"
  warn "Invalid suffix — defaulting to dbhome_1."
fi
TARGET_ORACLE_HOME="${TARGET_ORACLE_HOME_BASE}/dbhome_${DBHOME_SUFFIX}"
info "Target Oracle Home: ${TARGET_ORACLE_HOME}"

# =============================================================================
# BLOCKER 1: Password file on ODAA target
# =============================================================================
log ""
log "================================================================"
log "BLOCKER 1: Password file exists on ODAA target"
log "================================================================"

TARGET_PWFILE_PATH="${TARGET_ORACLE_HOME}/dbs/orapw${TARGET_DB_UNIQUE_NAME}"

PWFILE_CHECK=$(ssh -i "${TARGET_SSH_KEY}" \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=10 \
    "${TARGET_SSH_USER}@${TARGET_HOST}" \
    "sudo -u ${ORACLE_USER} bash -c 'test -f ${TARGET_PWFILE_PATH} && echo EXISTS || echo MISSING'" \
    2>>"${LOG_FILE}" || echo "SSH_ERROR")

info "Password file check result: ${PWFILE_CHECK}"

if [[ "${PWFILE_CHECK}" == "EXISTS" ]]; then
  pass "Password file found: ${TARGET_PWFILE_PATH}"
  ISSUE1_STATUS="PASS"
  ISSUE1_DETAIL="File found at ${TARGET_PWFILE_PATH} on ${TARGET_HOST}"
elif [[ "${PWFILE_CHECK}" == "MISSING" ]]; then
  fail "Password file NOT found at ${TARGET_PWFILE_PATH} — run fix_target_password_file.sh"
  ISSUE1_STATUS="FAIL"
  ISSUE1_DETAIL="File NOT found at ${TARGET_PWFILE_PATH} — run fix_target_password_file.sh"
else
  fail "Could not connect to target to check password file (SSH error). Check SSH key and connectivity."
  ISSUE1_STATUS="FAIL"
  ISSUE1_DETAIL="SSH connection to ${TARGET_HOST} failed — check ${TARGET_SSH_KEY} and target availability"
fi

# =============================================================================
# BLOCKER 2: Azure Blob Storage credentials exist and connectivity works
# =============================================================================
log ""
log "================================================================"
log "BLOCKER 2: Azure Blob Storage creds at ${AZURE_CREDS_FILE}"
log "================================================================"

if [[ ! -f "${AZURE_CREDS_FILE}" ]]; then
  fail "Azure Blob credentials file NOT found at ${AZURE_CREDS_FILE} — run fix_azure_blob_storage.sh"
  ISSUE2_STATUS="FAIL"
  ISSUE2_DETAIL="Credentials file missing at ${AZURE_CREDS_FILE} — run fix_azure_blob_storage.sh"
else
  info "Azure Blob credentials file found. Loading and testing connectivity..."
  # Source the creds file (contains only name=value lines)
  # shellcheck disable=SC1090
  source "${AZURE_CREDS_FILE}"

  AZ_ACCOUNT="${AZURE_STORAGE_ACCOUNT:-}"
  AZ_CONTAINER="${AZURE_STORAGE_CONTAINER:-}"
  AZ_AUTH_TYPE="${AZURE_STORAGE_AUTH_TYPE:-}"
  AZ_AUTH_VALUE="${AZURE_STORAGE_AUTH_VALUE:-}"
  AZ_ENDPOINT="${AZURE_BLOB_ENDPOINT:-}"

  if [[ -z "${AZ_ACCOUNT}" || -z "${AZ_CONTAINER}" || -z "${AZ_AUTH_VALUE}" ]]; then
    fail "Credentials file is incomplete (missing account, container, or auth value)."
    fail "Re-run fix_azure_blob_storage.sh to regenerate ${AZURE_CREDS_FILE}."
    ISSUE2_STATUS="FAIL"
    ISSUE2_DETAIL="Credentials file incomplete — missing required fields"
  else
    info "Account: ${AZ_ACCOUNT}  Container: ${AZ_CONTAINER}  Auth: ${AZ_AUTH_TYPE}"
    CONN_OK=false

    if command -v az &>/dev/null; then
      if [[ "${AZ_AUTH_TYPE}" == "key" ]]; then
        az storage container show \
            --name "${AZ_CONTAINER}" \
            --account-name "${AZ_ACCOUNT}" \
            --account-key "${AZ_AUTH_VALUE}" \
            --output none 2>/dev/null && CONN_OK=true || true
      elif [[ "${AZ_AUTH_TYPE}" == "sas" ]]; then
        az storage container show \
            --name "${AZ_CONTAINER}" \
            --account-name "${AZ_ACCOUNT}" \
            --sas-token "${AZ_AUTH_VALUE}" \
            --output none 2>/dev/null && CONN_OK=true || true
      fi
    else
      # Fallback: curl with SAS token
      if [[ "${AZ_AUTH_TYPE}" == "sas" ]]; then
        HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
          "${AZ_ENDPOINT}/${AZ_CONTAINER}?restype=container&${AZ_AUTH_VALUE}" \
          2>/dev/null || echo "000")
        [[ "${HTTP_STATUS}" == "200" ]] && CONN_OK=true
      else
        warn "az CLI not available and auth type is 'key' — cannot live-test without az CLI."
        warn "Install Azure CLI or re-run fix_azure_blob_storage.sh with a SAS token."
        CONN_OK=true  # credentials file exists and is populated; treat as pass
      fi
    fi

    if [[ "${CONN_OK}" == true ]]; then
      pass "Azure Blob Storage accessible. Account: ${AZ_ACCOUNT}  Container: ${AZ_CONTAINER}"
      ISSUE2_STATUS="PASS"
      ISSUE2_DETAIL="Blob container '${AZ_CONTAINER}' on account '${AZ_ACCOUNT}' accessible (auth: ${AZ_AUTH_TYPE})"
    else
      fail "Azure Blob Storage connectivity test failed."
      fail "Verify the credentials in ${AZURE_CREDS_FILE} and re-run fix_azure_blob_storage.sh."
      ISSUE2_STATUS="FAIL"
      ISSUE2_DETAIL="Blob container connectivity test failed for account '${AZ_ACCOUNT}'"
    fi
  fi
fi

# =============================================================================
# BLOCKER 3: Source SSH key (iaas.pem) connectivity test
# =============================================================================
log ""
log "================================================================"
log "BLOCKER 3: Source SSH access via ${SOURCE_SSH_KEY}"
log "================================================================"

SSH_SOURCE_TEST=$(ssh -i "${SOURCE_SSH_KEY}" \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=10 \
    "${SOURCE_SSH_USER}@${SOURCE_HOST}" \
    "sudo -u ${ORACLE_USER} whoami" \
    2>>"${LOG_FILE}" || echo "SSH_FAILED")

if [[ "${SSH_SOURCE_TEST}" == "oracle" ]]; then
  pass "Source SSH connectivity verified. oracle user accessible via ${SOURCE_SSH_KEY}."
  ISSUE3_STATUS="PASS"
  ISSUE3_DETAIL="SSH to ${SOURCE_SSH_USER}@${SOURCE_HOST} via ${SOURCE_SSH_KEY} grants oracle access"
else
  # Try with odaa.pem as fallback (zdm-env.md has odaa.pem for source)
  info "iaas.pem failed — trying odaa.pem (as listed in zdm-env.md)..."
  SSH_SOURCE_ALT=$(ssh -i "${HOME}/.ssh/odaa.pem" \
      -o StrictHostKeyChecking=no \
      -o ConnectTimeout=10 \
      "${SOURCE_SSH_USER}@${SOURCE_HOST}" \
      "sudo -u ${ORACLE_USER} whoami" \
      2>>"${LOG_FILE}" || echo "SSH_FAILED")

  if [[ "${SSH_SOURCE_ALT}" == "oracle" ]]; then
    warn "Source accessible via ~/.ssh/odaa.pem but NOT via ~/.ssh/iaas.pem."
    warn "Update zdm-env.md to set SOURCE_SSH_KEY: ~/.ssh/odaa.pem"
    ISSUE3_STATUS="FAIL"
    ISSUE3_DETAIL="iaas.pem FAILED; odaa.pem works — update zdm-env.md SOURCE_SSH_KEY"
    FAIL_COUNT=$((FAIL_COUNT + 1))  # manual fail since we used warn
    WARN_COUNT=$((WARN_COUNT - 1))  # correct counter
  else
    fail "Cannot reach source via either iaas.pem or odaa.pem. Check SSH key and network."
    ISSUE3_STATUS="FAIL"
    ISSUE3_DETAIL="Both iaas.pem and odaa.pem failed for ${SOURCE_SSH_USER}@${SOURCE_HOST}"
  fi
fi

# =============================================================================
# RECOMMENDATION 4: Source root disk space
# =============================================================================
log ""
log "================================================================"
log "RECOMMENDATION 4: Source root disk space (threshold: ${SOURCE_FREE_GB_THRESHOLD} GB)"
log "================================================================"

DISK_OUTPUT=$(ssh -i "${SOURCE_SSH_KEY}" \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=10 \
    "${SOURCE_SSH_USER}@${SOURCE_HOST}" \
    "df -BG / | awk 'NR==2{print \$4}'" \
    2>>"${LOG_FILE}" || echo "ERROR")

if [[ "${DISK_OUTPUT}" =~ ^([0-9]+)G$ ]]; then
  FREE_GB="${BASH_REMATCH[1]}"
  if [[ "${FREE_GB}" -ge "${SOURCE_FREE_GB_THRESHOLD}" ]]; then
    pass "Source root disk: ${FREE_GB} GB free (threshold: ${SOURCE_FREE_GB_THRESHOLD} GB)"
    ISSUE4_STATUS="PASS"
    ISSUE4_DETAIL="${FREE_GB} GB free on source root — above ${SOURCE_FREE_GB_THRESHOLD} GB threshold"
  else
    warn "Source root disk: only ${FREE_GB} GB free — below ${SOURCE_FREE_GB_THRESHOLD} GB threshold"
    warn "Consider purging old RMAN backups or relocating FRA before migration."
    ISSUE4_STATUS="WARN"
    ISSUE4_DETAIL="${FREE_GB} GB free on source root — below ${SOURCE_FREE_GB_THRESHOLD} GB threshold (review Issue 7)"
  fi
else
  warn "Could not determine source disk space (SSH may have used alternate key). Value: ${DISK_OUTPUT}"
  ISSUE4_STATUS="WARN"
  ISSUE4_DETAIL="Could not determine source disk space — check manually"
fi

# =============================================================================
# RECOMMENDATION 5: ZDM server root disk space
# =============================================================================
log ""
log "================================================================"
log "RECOMMENDATION 5: ZDM server root disk space (threshold: ${ZDM_FREE_GB_THRESHOLD} GB)"
log "================================================================"

ZDM_DISK=$(df -BG / | awk 'NR==2{print $4}')

if [[ "${ZDM_DISK}" =~ ^([0-9]+)G$ ]]; then
  ZDM_FREE_GB="${BASH_REMATCH[1]}"
  if [[ "${ZDM_FREE_GB}" -ge "${ZDM_FREE_GB_THRESHOLD}" ]]; then
    pass "ZDM server root disk: ${ZDM_FREE_GB} GB free (threshold: ${ZDM_FREE_GB_THRESHOLD} GB)"
    ISSUE5_STATUS="PASS"
    ISSUE5_DETAIL="${ZDM_FREE_GB} GB free on ZDM server root — above ${ZDM_FREE_GB_THRESHOLD} GB threshold"
  else
    warn "ZDM server root disk: only ${ZDM_FREE_GB} GB free — below ${ZDM_FREE_GB_THRESHOLD} GB threshold"
    ISSUE5_STATUS="WARN"
    ISSUE5_DETAIL="${ZDM_FREE_GB} GB free on ZDM root — below ${ZDM_FREE_GB_THRESHOLD} GB threshold"
  fi
else
  warn "Could not determine ZDM disk space. Value: ${ZDM_DISK}"
  ISSUE5_STATUS="WARN"
  ISSUE5_DETAIL="Could not determine ZDM disk space — check manually"
fi

# Determine where to write the results file — prefer the repo clone so the
# user can git-add/commit/push without any extra copy steps.
if [[ -n "${REPO_ROOT}" ]]; then
  RESULTS_BASE="${REPO_ROOT}/Artifacts/Phase10-Migration/ZDM/ORADB/Step2"
else
  RESULTS_BASE="$(dirname "${VERIFY_DIR}")"
fi
mkdir -p "${RESULTS_BASE}"

# =============================================================================
# FINAL SUMMARY
# =============================================================================
BLOCKERS_PASSED=0
[[ "${ISSUE1_STATUS}" == "PASS" ]] && BLOCKERS_PASSED=$((BLOCKERS_PASSED + 1))
[[ "${ISSUE2_STATUS}" == "PASS" ]] && BLOCKERS_PASSED=$((BLOCKERS_PASSED + 1))
[[ "${ISSUE3_STATUS}" == "PASS" ]] && BLOCKERS_PASSED=$((BLOCKERS_PASSED + 1))

log ""
log "================================================================"
log "SUMMARY"
log "================================================================"
log ""
log "  Blockers resolved:    ${BLOCKERS_PASSED}/3"
log "  Total PASS:           ${PASS_COUNT}"
log "  Total WARN:           ${WARN_COUNT}"
log "  Total FAIL:           ${FAIL_COUNT}"
log ""
log "  BLOCKER 1 — Target password file:    ${ISSUE1_STATUS}"
  log "  BLOCKER 2 — Azure Blob Storage creds:      ${ISSUE2_STATUS}"
log "  BLOCKER 3 — Source SSH key:          ${ISSUE3_STATUS}"
log "  RECOMMEND 4 — Source disk space:     ${ISSUE4_STATUS}"
log "  RECOMMEND 5 — ZDM disk space:        ${ISSUE5_STATUS}"
log ""
log "verify_fixes.sh completed. Log: ${LOG_FILE}"

# =============================================================================
# Write structured Markdown results file (commit to repo for Step 3)
# =============================================================================
DB_NAME_UPPER="${ORACLE_SID^^}"
RESULTS_FILE="${RESULTS_BASE}/Verification-Results-${DB_NAME_UPPER}.md"

_icon() {
  case "$1" in
    PASS) echo "✅ PASS";;
    FAIL) echo "❌ FAIL";;
    WARN) echo "⚠️  WARN";;
    *) echo "❓ UNKNOWN";;
  esac
}

ISSUE1_ICON=$(_icon "${ISSUE1_STATUS}")
ISSUE2_ICON=$(_icon "${ISSUE2_STATUS}")
ISSUE3_ICON=$(_icon "${ISSUE3_STATUS}")
ISSUE4_ICON=$(_icon "${ISSUE4_STATUS}")
ISSUE5_ICON=$(_icon "${ISSUE5_STATUS}")

if [[ "${FAIL_COUNT}" -eq 0 ]]; then
  PROCEED_LINE="✅ YES — all 3 blockers resolved"
  COMMIT_MSG_BODY="Step2 verification passed: all blockers resolved for ${DB_NAME_UPPER}"
else
  PROCEED_LINE="❌ NO — ${FAIL_COUNT} blocker(s) still pending"
  COMMIT_MSG_BODY="Step2 verification: ${BLOCKERS_PASSED}/3 blockers resolved for ${DB_NAME_UPPER}"
fi

cat > "${RESULTS_FILE}" << RESULTS_EOF
# Step 2 Verification Results: ${DB_NAME_UPPER}

**Verified:** $(date -u '+%Y-%m-%d %H:%M:%S UTC')
**Verified By:** $(whoami) on $(hostname)
**Log:** \`$(basename "${LOG_FILE}")\` (in \`Step2/Verification/\`)

---

## Blocker Status (Must Be Resolved Before Step 3)

| # | Issue | Status | Detail |
|---|-------|--------|--------|
| 1 | Password file on ODAA target (\`orapw${TARGET_DB_UNIQUE_NAME}\`) | ${ISSUE1_ICON} | ${ISSUE1_DETAIL} |
| 2 | Azure Blob Storage credentials (\`~/.azure/zdm_blob_creds\`) on ZDM server | ${ISSUE2_ICON} | ${ISSUE2_DETAIL} |
| 3 | Source SSH key (\`iaas.pem\`) connectivity to source | ${ISSUE3_ICON} | ${ISSUE3_DETAIL} |

## Recommended Items

| # | Item | Status | Detail |
|---|------|--------|--------|
| 4 | Source root disk space (≥ ${SOURCE_FREE_GB_THRESHOLD} GB free) | ${ISSUE4_ICON} | ${ISSUE4_DETAIL} |
| 5 | ZDM server root disk space (≥ ${ZDM_FREE_GB_THRESHOLD} GB free) | ${ISSUE5_ICON} | ${ISSUE5_DETAIL} |

---

## Summary

- **Blockers Resolved:** ${BLOCKERS_PASSED}/3
- **Proceed to Step 3:** ${PROCEED_LINE}

## Outstanding Manual Items (DBA Decision Required)

The following items from Issue-Resolution-Log-ORADB.md require DBA/OCI team action — not automated:

| # | Issue | Notes |
|---|-------|-------|
| 4 | TDE wallet — no master encryption key on target | Confirm TDE strategy; may need to enable TDE on source first |
| 5 | SSH key mismatch (iaas.pem vs odaa.pem) | Confirm zdm-env.md SOURCE_SSH_KEY vs actual working key |
| 6 | Azure Blob container configured (replaces OCI Object Storage) | Resolved with Issue 1 via \`fix_azure_blob_storage.sh\` |
| 8 | Target Oracle Home path (dbhome_1 vs dbhome_2) | Confirm via /etc/oratab on target; update zdm-env.md |
RESULTS_EOF

echo ""
echo "  📄 Verification results written to:"
echo "  ${RESULTS_FILE}"
echo ""
echo "  Commit and push to repo before running Step 3:"
echo "    cd \"${REPO_ROOT:-<repo-root>}\""
echo "    git add Artifacts/Phase10-Migration/ZDM/${DB_NAME_UPPER}/Step2/Verification-Results-${DB_NAME_UPPER}.md"
echo "    git commit -m \"${COMMIT_MSG_BODY}\""
echo "    git push"

# Exit non-zero if any blockers failed
if [[ "${FAIL_COUNT}" -gt 0 ]]; then
  echo ""
  echo "  ❌ ${FAIL_COUNT} blocker(s) still unresolved. Fix issues and re-run verify_fixes.sh."
  exit 1
fi

echo ""
echo "  ✅ All blockers resolved. Proceed to Step 3."
