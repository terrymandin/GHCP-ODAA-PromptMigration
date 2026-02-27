#!/usr/bin/env bash
# =============================================================================
# fix_06_create_oci_bucket.sh
#
# Purpose : Create the OCI Object Storage bucket used by ZDM to transfer
#           RMAN backup sets from the source database to the target ODAA system.
#
# Target  : ZDM server (10.1.0.8) — run locally as zdmuser.
#           OCI CLI must be configured for zdmuser (~/.oci/config present).
#           OCI_OSS_NAMESPACE must be known (run fix_05 first).
#
# Run as  : zdmuser on ZDM server (10.1.0.8)
# Usage   : OCI_OSS_NAMESPACE=<namespace> bash fix_06_create_oci_bucket.sh
#           OR set OCI_OSS_NAMESPACE in environment before running.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — sourced from zdm-env.md values
# ---------------------------------------------------------------------------
OCI_CONFIG_PATH="${OCI_CONFIG_PATH:-${HOME}/.oci/config}"
OCI_COMPARTMENT_OCID="${OCI_COMPARTMENT_OCID:-ocid1.compartment.oc1..aaaaaaaas4upnqj72dfiivgwvn3uui5gkxo7ng6leeoifucbjiy326urbhmq}"
OCI_OSS_NAMESPACE="${OCI_OSS_NAMESPACE:-}"
OCI_REGION="${OCI_REGION:-uk-london-1}"
BUCKET_NAME="${OCI_OSS_BUCKET_NAME:-zdm-oradb-migration}"

LOG_FILE="fix_06_$(date +%Y%m%d_%H%M%S).log"

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"; }
info() { log "INFO  $*"; }
warn() { log "WARN  $*"; }
fail() { log "ERROR $*"; exit 1; }
sep()  { log "----------------------------------------------------------------------"; }

# ---------------------------------------------------------------------------
# Resolve namespace if not provided
# ---------------------------------------------------------------------------
sep
info "Starting fix_06: Create OCI Object Storage Bucket"
info "OCI config     : ${OCI_CONFIG_PATH}"
info "Compartment    : ${OCI_COMPARTMENT_OCID}"
info "Region         : ${OCI_REGION}"
info "Bucket name    : ${BUCKET_NAME}"
info "Log file       : ${LOG_FILE}"
sep

if [ -z "${OCI_OSS_NAMESPACE}" ]; then
  info "OCI_OSS_NAMESPACE not set — retrieving automatically..."
  OCI_OSS_NAMESPACE=$(oci os ns get --config-file "${OCI_CONFIG_PATH}" 2>/dev/null | \
    python3 -c "import sys,json; print(json.load(sys.stdin)['data'])" 2>/dev/null) || \
    fail "Could not auto-detect OCI_OSS_NAMESPACE. Run fix_05_discover_oci_namespace.sh first."
  info "Detected namespace: ${OCI_OSS_NAMESPACE}"
fi

info "Namespace      : ${OCI_OSS_NAMESPACE}"

# ---------------------------------------------------------------------------
# Step 0: Preflight checks
# ---------------------------------------------------------------------------
command -v oci >/dev/null 2>&1 || fail "OCI CLI not found. Run as zdmuser."
[ -f "${OCI_CONFIG_PATH}" ]     || fail "OCI config not found at ${OCI_CONFIG_PATH}."

# ---------------------------------------------------------------------------
# Step 1: Check if bucket already exists
# ---------------------------------------------------------------------------
sep
info "Step 1: Checking if bucket '${BUCKET_NAME}' already exists..."
BUCKET_EXISTS=$(oci os bucket get \
  --config-file "${OCI_CONFIG_PATH}" \
  --bucket-name "${BUCKET_NAME}" \
  --namespace "${OCI_OSS_NAMESPACE}" \
  2>&1) && BUCKET_FOUND=true || BUCKET_FOUND=false

if [ "${BUCKET_FOUND}" = "true" ]; then
  warn "Bucket '${BUCKET_NAME}' ALREADY EXISTS. Skipping creation."
  info "${BUCKET_EXISTS}"
else
  info "Bucket does not exist — will create it."
fi

# ---------------------------------------------------------------------------
# Step 2: Create the bucket
# ---------------------------------------------------------------------------
if [ "${BUCKET_FOUND}" = "false" ]; then
  sep
  info "Step 2: Creating bucket '${BUCKET_NAME}' in region '${OCI_REGION}'..."
  oci os bucket create \
    --config-file "${OCI_CONFIG_PATH}" \
    --compartment-id "${OCI_COMPARTMENT_OCID}" \
    --name "${BUCKET_NAME}" \
    --namespace "${OCI_OSS_NAMESPACE}" \
    --versioning "Disabled" \
    2>&1 | tee -a "${LOG_FILE}" || fail "Failed to create bucket '${BUCKET_NAME}'."
  info "Bucket '${BUCKET_NAME}' created successfully."
fi

# ---------------------------------------------------------------------------
# Step 3: Verification — bucket must be accessible
# ---------------------------------------------------------------------------
sep
info "Step 3: Verifying bucket accessibility..."
oci os bucket get \
  --config-file "${OCI_CONFIG_PATH}" \
  --bucket-name "${BUCKET_NAME}" \
  --namespace "${OCI_OSS_NAMESPACE}" \
  2>&1 | tee -a "${LOG_FILE}" || fail "Bucket verification failed. Bucket may not be accessible."

sep
echo ""
echo "============================================================"
echo "  OCI Object Storage Bucket Ready"
echo "  Bucket Name : ${BUCKET_NAME}"
echo "  Namespace   : ${OCI_OSS_NAMESPACE}"
echo "  Region      : ${OCI_REGION}"
echo ""
echo "  ACTION REQUIRED: Update zdm-env.md with these values:"
echo "  - OCI_OSS_NAMESPACE:   ${OCI_OSS_NAMESPACE}"
echo "  - OCI_OSS_BUCKET_NAME: ${BUCKET_NAME}"
echo ""
echo "  File: prompts/Phase10-Migration/ZDM/zdm-env.md"
echo "============================================================"
echo ""

info "✅ Fix 06 complete. Update zdm-env.md with bucket details."
sep
info "Log saved to: ${LOG_FILE}"
