#!/usr/bin/env bash
# =============================================================================
# fix_03_oci_oss_setup.sh
# =============================================================================
# Purpose : Discover OCI Object Storage namespace and create the ZDM migration
#           bucket in OCI region uk-london-1.
#
# Actions : ACTION-05 (Discover OSS Namespace),
#           ACTION-06 (Create OCI OSS Bucket)
#
# Run from: ZDM Server (10.1.0.8)
# Run as  : zdmuser  (OCI CLI already configured under /home/zdmuser/.oci/config)
#
# Usage   : bash fix_03_oci_oss_setup.sh
#           bash fix_03_oci_oss_setup.sh --verify-only
# =============================================================================

set -euo pipefail

# --- Configuration (from zdm-env.md) ----------------------------------------
OCI_CONFIG_FILE="/home/zdmuser/.oci/config"
OCI_PROFILE="DEFAULT"
OCI_REGION="uk-london-1"
OCI_COMPARTMENT_OCID="ocid1.compartment.oc1..aaaaaaaas4upnqj72dfiivgwvn3uui5gkxo7ng6leeoifucbjiy326urbhmq"

# Suggested bucket name (update zdm-env.md after creation)
BUCKET_NAME="zdm-oradb-migration"
# ----------------------------------------------------------------------------

VERIFY_ONLY=false
if [[ "${1:-}" == "--verify-only" ]]; then
  VERIFY_ONLY=true
fi

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# --- Guard: must run as zdmuser ---------------------------------------------
CURRENT_USER=$(whoami)
if [[ "${CURRENT_USER}" != "zdmuser" ]]; then
  log "ERROR: This script must be run as zdmuser."
  log "       Run: sudo su - zdmuser && bash fix_03_oci_oss_setup.sh"
  exit 1
fi

log "================================================================"
log "fix_03_oci_oss_setup.sh — OCI Object Storage Setup (ORADB)"
log "================================================================"
log "OCI Config   : ${OCI_CONFIG_FILE}"
log "Region       : ${OCI_REGION}"
log "Compartment  : ${OCI_COMPARTMENT_OCID}"
log "Bucket name  : ${BUCKET_NAME}"
log "================================================================"

OCI_BASE="oci --config-file ${OCI_CONFIG_FILE} --profile ${OCI_PROFILE} --region ${OCI_REGION}"

# --- Step 1: Verify OCI CLI connectivity ------------------------------------
log "Step 1: Verifying OCI CLI connectivity..."
OCI_TEST=$(${OCI_BASE} iam region list --query "data[?name=='${OCI_REGION}'].name" --raw-output 2>&1)
if echo "${OCI_TEST}" | grep -q "${OCI_REGION}"; then
  log "OCI CLI connectivity: ✅ OK (region ${OCI_REGION} confirmed)"
else
  log "ERROR: OCI CLI test failed. Output:"
  echo "${OCI_TEST}"
  log "Check: oci setup config, API key fingerprint, and key file at ${OCI_CONFIG_FILE}"
  exit 1
fi

# --- Step 2: Discover OCI Object Storage namespace --------------------------
log "Step 2: Discovering OCI Object Storage namespace..."
OSS_NAMESPACE=$(${OCI_BASE} os ns get --query data --raw-output 2>&1)

if [[ -z "${OSS_NAMESPACE}" ]]; then
  log "ERROR: Could not retrieve OSS namespace. Check OCI config and tenancy permissions."
  exit 1
fi

log "✅ OCI Object Storage namespace: ${OSS_NAMESPACE}"
log ""
log "ACTION-05 COMPLETE: Update zdm-env.md with:"
log "  OCI_OSS_NAMESPACE: ${OSS_NAMESPACE}"
log ""

# --- VERIFY-ONLY mode -------------------------------------------------------
if [[ "${VERIFY_ONLY}" == "true" ]]; then
  log "Verify-only mode: Checking if bucket '${BUCKET_NAME}' exists..."
  BUCKET_STATUS=$(${OCI_BASE} os bucket get \
    --namespace "${OSS_NAMESPACE}" \
    --bucket-name "${BUCKET_NAME}" \
    --query "data.name" --raw-output 2>&1 || echo "NOT_FOUND")

  if echo "${BUCKET_STATUS}" | grep -q "${BUCKET_NAME}"; then
    log "✅ Bucket '${BUCKET_NAME}' EXISTS in namespace '${OSS_NAMESPACE}'"
  else
    log "⚠️  Bucket '${BUCKET_NAME}' NOT FOUND. Run without --verify-only to create it."
  fi
  exit 0
fi

# --- Step 3: Check if bucket already exists ----------------------------------
log "Step 3: Checking if bucket '${BUCKET_NAME}' already exists..."
EXISTING=$(${OCI_BASE} os bucket get \
  --namespace "${OSS_NAMESPACE}" \
  --bucket-name "${BUCKET_NAME}" \
  --query "data.name" --raw-output 2>&1 || echo "NOT_FOUND")

if echo "${EXISTING}" | grep -q "${BUCKET_NAME}"; then
  log "✅ Bucket '${BUCKET_NAME}' already exists. Skipping creation."
else
  # --- Step 4: Create bucket ------------------------------------------------
  log "Step 4: Creating OCI Object Storage bucket: ${BUCKET_NAME}"
  log "        Namespace   : ${OSS_NAMESPACE}"
  log "        Compartment : ${OCI_COMPARTMENT_OCID}"
  log "        Region      : ${OCI_REGION}"

  ${OCI_BASE} os bucket create \
    --namespace "${OSS_NAMESPACE}" \
    --compartment-id "${OCI_COMPARTMENT_OCID}" \
    --name "${BUCKET_NAME}" \
    --versioning Disabled \
    --public-access-type NoPublicAccess \
    --storage-tier Standard

  log "✅ Bucket created: ${BUCKET_NAME}"
fi

# --- Step 5: Verify bucket access -------------------------------------------
log "Step 5: Verifying bucket access..."
BUCKET_INFO=$(${OCI_BASE} os bucket get \
  --namespace "${OSS_NAMESPACE}" \
  --bucket-name "${BUCKET_NAME}" 2>&1)

echo "${BUCKET_INFO}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
b = data.get('data', {})
print('  Name         :', b.get('name',''))
print('  Namespace    :', b.get('namespace',''))
print('  Compartment  :', b.get('compartment-id',''))
print('  Storage Tier :', b.get('storage-tier',''))
print('  Versioning   :', b.get('versioning',''))
print('  Public Access:', b.get('public-access-type',''))
" 2>/dev/null || echo "${BUCKET_INFO}"

# --- Step 6: Test write/read to bucket (functional test) --------------------
log "Step 6: Functional test — upload and delete a test object..."
TEST_OBJECT="zdm-connectivity-test-$(date +%Y%m%d%H%M%S).txt"
echo "ZDM OSS connectivity test for ORADB migration" > /tmp/"${TEST_OBJECT}"

${OCI_BASE} os object put \
  --namespace "${OSS_NAMESPACE}" \
  --bucket-name "${BUCKET_NAME}" \
  --name "${TEST_OBJECT}" \
  --file /tmp/"${TEST_OBJECT}" \
  --no-overwrite 2>/dev/null \
  && log "  ✅ Test upload succeeded" \
  || log "  ❌ Test upload FAILED — check IAM policies on compartment"

${OCI_BASE} os object delete \
  --namespace "${OSS_NAMESPACE}" \
  --bucket-name "${BUCKET_NAME}" \
  --name "${TEST_OBJECT}" \
  --force 2>/dev/null \
  && log "  ✅ Test object deleted" \
  || true

rm -f /tmp/"${TEST_OBJECT}"

# --- Summary ----------------------------------------------------------------
log ""
log "================================================================"
log "fix_03_oci_oss_setup.sh COMPLETE"
log ""
log "ACTION-05 COMPLETE → OCI_OSS_NAMESPACE = ${OSS_NAMESPACE}"
log "ACTION-06 COMPLETE → OCI_OSS_BUCKET_NAME = ${BUCKET_NAME}"
log ""
log "REQUIRED: Update prompts/Phase10-Migration/ZDM/zdm-env.md:"
log "  - OCI_OSS_NAMESPACE: ${OSS_NAMESPACE}"
log "  - OCI_OSS_BUCKET_NAME: ${BUCKET_NAME}"
log ""
log "Update Issue-Resolution-Log-ORADB.md:"
log "  - ACTION-05 Status: ✅ Resolved"
log "  - ACTION-06 Status: ✅ Resolved"
log "  - ACTION-12 Status: ✅ Resolved (after updating zdm-env.md)"
log "================================================================"
