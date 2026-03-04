#!/usr/bin/env bash
# =============================================================================
# fix_oci_cli_config.sh
# Purpose : Create the OCI CLI config file for zdmuser on the ZDM server
#           and optionally create the OCI Object Storage bucket required for
#           ZDM ONLINE_PHYSICAL migration.
# Run as  : zdmuser on the ZDM server (tm-vm-odaa-oracle-jumpbox / 10.1.0.8)
# Step    : ZDM Migration Step 2 — Fix Issues
# Issue   : Issue 1 (OCI CLI config) + Issue 6 (Object Storage bucket)
# =============================================================================

set -euo pipefail

# --- User guard: must run as zdmuser ---
if [[ "$(whoami)" != "zdmuser" ]]; then
  echo "ERROR: This script must be run as zdmuser. Current user: $(whoami)"
  echo "       Switch with: sudo su - zdmuser"
  exit 1
fi

# =============================================================================
# Configuration — values from zdm-env.md
# =============================================================================
OCI_USER_OCID="ocid1.user.oc1..aaaaaaaakfe5cirdq7vkkrhogjrgcrgftvwb7mdoehujgchefpqv54vhsnoa"
OCI_TENANCY_OCID="ocid1.tenancy.oc1..aaaaaaaarvyhjcn7wkkxxx5g3o7lgqks23bmsjtsticz3gtg5xs5qyrwkftq"
OCI_FINGERPRINT="7f:05:c1:f2:5c:3a:46:ec:9f:95:44:c8:77:a4:50:f9"
OCI_REGION="uk-london-1"
OCI_CONFIG_DIR="${HOME}/.oci"
OCI_CONFIG_FILE="${OCI_CONFIG_DIR}/config"
OCI_PRIVATE_KEY_PATH="${OCI_CONFIG_DIR}/oci_api_key.pem"
OCI_COMPARTMENT_OCID="ocid1.compartment.oc1..aaaaaaaas4upnqj72dfiivgwvn3uui5gkxo7ng6leeoifucbjiy326urbhmq"
OCI_BUCKET_NAME="zdm-oradb-migration"

LOG_DIR="${HOME}/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/fix_oci_cli_config_$(date +%Y%m%d_%H%M%S).log"

# =============================================================================
# Logging helpers
# =============================================================================
log()  { echo "[$(date '+%H:%M:%S')] $*" | tee -a "${LOG_FILE}"; }
pass() { echo "[$(date '+%H:%M:%S')] ✅ PASS  $*" | tee -a "${LOG_FILE}"; }
fail() { echo "[$(date '+%H:%M:%S')] ❌ FAIL  $*" | tee -a "${LOG_FILE}"; }
warn() { echo "[$(date '+%H:%M:%S')] ⚠️  WARN  $*" | tee -a "${LOG_FILE}"; }
info() { echo "[$(date '+%H:%M:%S')] ℹ️  INFO  $*" | tee -a "${LOG_FILE}"; }

log "================================================================"
log "fix_oci_cli_config.sh — OCI CLI Configuration"
log "Running as: $(whoami)  on  $(hostname)"
log "Log: ${LOG_FILE}"
log "================================================================"

# =============================================================================
# Step 1: Check that the OCI CLI binary is available
# =============================================================================
log ""
log "--- Step 1: Verify OCI CLI binary ---"
if ! command -v oci &>/dev/null; then
  fail "OCI CLI binary not found in PATH."
  fail "Install OCI CLI first: bash -c \"\$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)\""
  exit 1
fi
OCI_VERSION=$(oci --version 2>/dev/null || echo "unknown")
pass "OCI CLI found: ${OCI_VERSION}"

# =============================================================================
# Step 2: Check that the private key exists
# =============================================================================
log ""
log "--- Step 2: Verify OCI API private key ---"
if [[ ! -f "${OCI_PRIVATE_KEY_PATH}" ]]; then
  fail "OCI API private key not found at: ${OCI_PRIVATE_KEY_PATH}"
  fail "Upload the private key to the ZDM server as zdmuser before running this script:"
  fail "  scp -i ~/.ssh/zdm.pem /path/to/oci_api_key.pem zdmuser@10.1.0.8:~/.oci/oci_api_key.pem"
  fail "  ssh -i ~/.ssh/zdm.pem zdmuser@10.1.0.8 'chmod 600 ~/.oci/oci_api_key.pem'"
  exit 1
fi
KEY_PERMS=$(stat -c "%a" "${OCI_PRIVATE_KEY_PATH}")
if [[ "${KEY_PERMS}" != "600" ]]; then
  warn "Private key permissions are ${KEY_PERMS}, expected 600. Fixing..."
  chmod 600 "${OCI_PRIVATE_KEY_PATH}"
  pass "Private key permissions set to 600."
else
  pass "Private key found at ${OCI_PRIVATE_KEY_PATH} with permissions 600."
fi

# =============================================================================
# Step 3: Create OCI config directory and config file
# =============================================================================
log ""
log "--- Step 3: Create OCI config directory and config file ---"

mkdir -p "${OCI_CONFIG_DIR}"
chmod 700 "${OCI_CONFIG_DIR}"
info "Directory ${OCI_CONFIG_DIR} ready."

if [[ -f "${OCI_CONFIG_FILE}" ]]; then
  warn "Existing config found at ${OCI_CONFIG_FILE} — backing up to ${OCI_CONFIG_FILE}.bak"
  cp "${OCI_CONFIG_FILE}" "${OCI_CONFIG_FILE}.bak"
fi

cat > "${OCI_CONFIG_FILE}" << EOF
[DEFAULT]
user=${OCI_USER_OCID}
fingerprint=${OCI_FINGERPRINT}
tenancy=${OCI_TENANCY_OCID}
region=${OCI_REGION}
key_file=${OCI_PRIVATE_KEY_PATH}
EOF

chmod 600 "${OCI_CONFIG_FILE}"
pass "OCI config written to ${OCI_CONFIG_FILE} with permissions 600."

log ""
log "Config contents:"
cat "${OCI_CONFIG_FILE}" | tee -a "${LOG_FILE}"

# =============================================================================
# Step 4: Verify OCI connectivity — get Object Storage namespace
# =============================================================================
log ""
log "--- Step 4: Verify OCI connectivity (get Object Storage namespace) ---"
OCI_NS=""
if OCI_NS=$(oci os ns get --config-file "${OCI_CONFIG_FILE}" --query 'data' --raw-output 2>&1); then
  pass "OCI connectivity verified. Object Storage namespace: ${OCI_NS}"
else
  fail "OCI connectivity test failed. Output:"
  fail "${OCI_NS}"
  fail "Check: fingerprint, tenancy OCID, user OCID, and private key contents match the OCI console."
  exit 1
fi

# =============================================================================
# Step 5: Create OCI Object Storage bucket (Issue 6)
# =============================================================================
log ""
log "--- Step 5: Create OCI Object Storage bucket (${OCI_BUCKET_NAME}) ---"

BUCKET_EXISTS=""
if oci os bucket get \
    --config-file "${OCI_CONFIG_FILE}" \
    --namespace "${OCI_NS}" \
    --bucket-name "${OCI_BUCKET_NAME}" \
    --region "${OCI_REGION}" \
    &>/dev/null; then
  BUCKET_EXISTS="yes"
fi

if [[ "${BUCKET_EXISTS}" == "yes" ]]; then
  warn "Bucket '${OCI_BUCKET_NAME}' already exists in namespace '${OCI_NS}'. Skipping creation."
else
  info "Creating bucket '${OCI_BUCKET_NAME}' in compartment..."
  if oci os bucket create \
      --config-file "${OCI_CONFIG_FILE}" \
      --compartment-id "${OCI_COMPARTMENT_OCID}" \
      --name "${OCI_BUCKET_NAME}" \
      --region "${OCI_REGION}" \
      --versioning Disabled \
      &>>"${LOG_FILE}"; then
    pass "Bucket '${OCI_BUCKET_NAME}' created successfully."
  else
    fail "Failed to create bucket. Check compartment OCID and region, then re-run."
    exit 1
  fi
fi

# =============================================================================
# Summary
# =============================================================================
log ""
log "================================================================"
log "SUMMARY"
log "================================================================"
pass "Issue 1 RESOLVED: OCI CLI config created at ${OCI_CONFIG_FILE}"
pass "Issue 6 RESOLVED: OCI Object Storage bucket '${OCI_BUCKET_NAME}' is ready"
log ""
log "Next steps:"
log "  1. Update zdm-env.md with:"
log "       OCI_OSS_NAMESPACE: ${OCI_NS}"
log "       OCI_OSS_BUCKET_NAME: ${OCI_BUCKET_NAME}"
log "  2. Run verify_fixes.sh to confirm all blocker checks pass."
log ""
log "fix_oci_cli_config.sh completed. Log: ${LOG_FILE}"
