#!/usr/bin/env bash
# =============================================================================
#  create_oci_bucket.sh
#  ZDM Migration Step 2 — Issue 1 Remediation
#  Creates the OCI Object Storage bucket required for ONLINE_PHYSICAL migration
#  and prints the namespace + bucket name values to update in zdm-env.md.
#
#  Database : ORADB
#  Target   : OCI Object Storage (uk-london-1)
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
OCI_COMPARTMENT_OCID="ocid1.compartment.oc1..aaaaaaaas4upnqj72dfiivgwvn3uui5gkxo7ng6leeoifucbjiy326urbhmq"
OCI_REGION="uk-london-1"
BUCKET_NAME="zdm-migration-oradb-$(date +%Y%m%d)"
OCI_CONFIG_PATH="${HOME}/.oci/config"

LOG_DIR="${HOME}/Artifacts/Phase10-Migration/ZDM/${DATABASE_NAME}/Step2/Logs"
LOG_FILE="${LOG_DIR}/create_oci_bucket_$(date +%Y%m%d_%H%M%S).log"

mkdir -p "${LOG_DIR}"
exec > >(tee -a "${LOG_FILE}") 2>&1

# =============================================================================
# Helper functions
# =============================================================================
pass() { echo "  ✅ PASS: $1"; }
fail() { echo "  ❌ FAIL: $1"; }
info() { echo "  ℹ️  INFO: $1"; }
step() { echo ""; echo "── Step $1: $2 ──"; }

echo "=============================================================="
echo "  ZDM Step 2: Create OCI Object Storage Bucket"
echo "  Database  : ${DATABASE_NAME}"
echo "  Region    : ${OCI_REGION}"
echo "  Compartment: ${OCI_COMPARTMENT_OCID}"
echo "  Timestamp : $(date)"
echo "  Log       : ${LOG_FILE}"
echo "=============================================================="

# =============================================================================
# Step 1: Verify OCI CLI is installed and config exists
# =============================================================================
step "1" "Verifying OCI CLI prerequisites"

if ! command -v oci &>/dev/null; then
  fail "OCI CLI binary not found in PATH."
  echo ""
  echo "  Install OCI CLI first:"
  echo "    bash -c \"\$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)\""
  echo "  Then run verify_oci_cli_zdmuser.sh before re-running this script."
  exit 1
fi
OCI_VER=$(oci --version 2>&1 | head -1)
pass "OCI CLI found: ${OCI_VER}"

if [[ ! -f "${OCI_CONFIG_PATH}" ]]; then
  fail "OCI CLI config not found at ${OCI_CONFIG_PATH}"
  echo ""
  echo "  Run verify_oci_cli_zdmuser.sh to set up the OCI CLI config for zdmuser."
  exit 1
fi
pass "OCI config found at ${OCI_CONFIG_PATH}"

# =============================================================================
# Step 2: Retrieve Object Storage namespace
# =============================================================================
step "2" "Retrieving Object Storage namespace"

OSS_NAMESPACE=""
OSS_NAMESPACE=$(oci os ns get \
  --config-file "${OCI_CONFIG_PATH}" \
  --query "data" \
  --raw-output 2>&1) || {
  fail "Failed to retrieve Object Storage namespace: ${OSS_NAMESPACE}"
  echo "  Verify OCI CLI connectivity with: oci iam region list"
  exit 1
}

if [[ -z "${OSS_NAMESPACE}" ]]; then
  fail "Object Storage namespace returned empty. Check OCI CLI config and permissions."
  exit 1
fi

pass "Object Storage namespace: ${OSS_NAMESPACE}"

# =============================================================================
# Step 3: Check if bucket already exists
# =============================================================================
step "3" "Checking if bucket '${BUCKET_NAME}' already exists"

BUCKET_EXISTS="false"
BUCKET_CHECK=$(oci os bucket get \
  --namespace-name "${OSS_NAMESPACE}" \
  --bucket-name "${BUCKET_NAME}" \
  --config-file "${OCI_CONFIG_PATH}" \
  --region "${OCI_REGION}" 2>&1) && BUCKET_EXISTS="true" || true

if [[ "${BUCKET_EXISTS}" == "true" ]]; then
  info "Bucket '${BUCKET_NAME}' already exists — skipping creation."
else
  # =============================================================================
  # Step 4: Create the bucket
  # =============================================================================
  step "4" "Creating bucket '${BUCKET_NAME}' in ${OCI_REGION}"

  CREATE_RESULT=$(oci os bucket create \
    --config-file "${OCI_CONFIG_PATH}" \
    --compartment-id "${OCI_COMPARTMENT_OCID}" \
    --name "${BUCKET_NAME}" \
    --region "${OCI_REGION}" 2>&1) || {
    fail "Failed to create bucket: ${CREATE_RESULT}"
    exit 1
  }

  pass "Bucket '${BUCKET_NAME}' created successfully in ${OCI_REGION}"
fi

# =============================================================================
# Step 5: Verify bucket is accessible
# =============================================================================
step "5" "Verifying bucket is accessible"

VERIFY_RESULT=$(oci os bucket get \
  --namespace-name "${OSS_NAMESPACE}" \
  --bucket-name "${BUCKET_NAME}" \
  --config-file "${OCI_CONFIG_PATH}" \
  --region "${OCI_REGION}" \
  --query "data.name" \
  --raw-output 2>&1) || {
  fail "Could not verify bucket exists: ${VERIFY_RESULT}"
  exit 1
}
pass "Bucket verified: ${VERIFY_RESULT}"

# =============================================================================
# Output: values to update in zdm-env.md
# =============================================================================
echo ""
echo "=============================================================="
echo "  ✅ SUCCESS — Bucket created and verified"
echo ""
echo "  ACTION REQUIRED: Update zdm-env.md with these values"
echo "  File: prompts/Phase10-Migration/ZDM/zdm-env.md"
echo ""
echo "  OCI_OSS_NAMESPACE: ${OSS_NAMESPACE}"
echo "  OCI_OSS_BUCKET_NAME: ${BUCKET_NAME}"
echo ""
echo "  Replace the lines:"
echo "    - OCI_OSS_NAMESPACE: "
echo "    - OCI_OSS_BUCKET_NAME: "
echo "  With:"
echo "    - OCI_OSS_NAMESPACE: ${OSS_NAMESPACE}"
echo "    - OCI_OSS_BUCKET_NAME: ${BUCKET_NAME}"
echo "=============================================================="
echo ""
echo "  To delete bucket if created in error (must be empty):"
echo "    oci os bucket delete \\"
echo "      --namespace-name ${OSS_NAMESPACE} \\"
echo "      --bucket-name ${BUCKET_NAME} \\"
echo "      --config-file ${OCI_CONFIG_PATH} \\"
echo "      --region ${OCI_REGION} \\"
echo "      --force"
echo "=============================================================="
echo ""
echo "create_oci_bucket.sh completed at $(date)"
echo "Log written to: ${LOG_FILE}"
