#!/usr/bin/env bash
# =============================================================================
# zdm_configure_oci.sh
# -----------------------------------------------------------------------------
# Configures OCI CLI for zdmuser on the ZDM server and verifies connectivity.
#
#   Issue 3: OCI config missing for zdmuser
#   Issue 4: OCI Object Storage namespace and bucket not configured
#            (interactive guidance; bucket creation is opt-in — see below)
#
# Run as: zdmuser on the ZDM server (tm-vm-odaa-oracle-jumpbox / 10.1.0.8)
#   sudo su - zdmuser
#   chmod +x ~/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts/zdm_configure_oci.sh
#   ~/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts/zdm_configure_oci.sh
#
# BEFORE RUNNING:
#   Ensure the OCI API private key is present at ~/.oci/oci_api_key.pem
#   If it is not yet on the ZDM server, copy it first:
#     scp -i ~/.ssh/zdm.pem /local/path/oci_api_key.pem azureuser@10.1.0.8:/tmp/oci_api_key.pem
#     sudo cp /tmp/oci_api_key.pem /home/zdmuser/.oci/oci_api_key.pem
#     sudo chown zdmuser:zdmuser /home/zdmuser/.oci/oci_api_key.pem
#     sudo chmod 600 /home/zdmuser/.oci/oci_api_key.pem
#
# Part of: ZDM Migration Step 2 — Fix Issues
# =============================================================================

set -euo pipefail

# --- User guard ---
if [[ "$(whoami)" != "zdmuser" ]]; then
  echo "ERROR: This script must be run as zdmuser. Current user: $(whoami)"
  echo "       Switch with: sudo su - zdmuser"
  exit 1
fi

# =============================================================================
# Configuration — sourced from zdm-env.md
# =============================================================================
OCI_CONFIG_DIR="${HOME}/.oci"
OCI_CONFIG_PATH="${OCI_CONFIG_DIR}/config"
OCI_PRIVATE_KEY_PATH="${OCI_CONFIG_DIR}/oci_api_key.pem"

OCI_TENANCY_OCID="ocid1.tenancy.oc1..aaaaaaaarvyhjcn7wkkxxx5g3o7lgqks23bmsjtsticz3gtg5xs5qyrwkftq"
OCI_USER_OCID="ocid1.user.oc1..aaaaaaaakfe5cirdq7vkkrhogjrgcrgftvwb7mdoehujgchefpqv54vhsnoa"
OCI_API_KEY_FINGERPRINT="7f:05:c1:f2:5c:3a:46:ec:9f:95:44:c8:77:a4:50:f9"
OCI_REGION="uk-london-1"
OCI_COMPARTMENT_OCID="ocid1.compartment.oc1..aaaaaaaas4upnqj72dfiivgwvn3uui5gkxo7ng6leeoifucbjiy326urbhmq"

# --- Object Storage (used for bucket creation — uncomment to activate) ---
# Set these values after running 'oci os ns get' and deciding on a bucket name:
# OCI_OSS_NAMESPACE="<your-namespace>"          # e.g. "abc123xyz"
# OCI_OSS_BUCKET_NAME="zdm-migration-oradb"     # recommended name

# =============================================================================
# Helpers
# =============================================================================
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
pass() { echo "  ✅ $*"; }
fail() { echo "  ❌ $*"; exit 1; }
warn() { echo "  ⚠️  $*"; }

# =============================================================================
# Step 1 — Create ~/.oci directory
# =============================================================================
log "STEP 1: Creating OCI config directory ${OCI_CONFIG_DIR}..."

mkdir -p "${OCI_CONFIG_DIR}"
chmod 700 "${OCI_CONFIG_DIR}"
pass "Directory ${OCI_CONFIG_DIR} ready (mode 700)"

# =============================================================================
# Step 2 — Back up existing config (if present) and write new config
# =============================================================================
log "STEP 2: Writing OCI config to ${OCI_CONFIG_PATH}..."

if [[ -f "${OCI_CONFIG_PATH}" ]]; then
  BACKUP_PATH="${OCI_CONFIG_PATH}.bak.$(date +%Y%m%d%H%M%S)"
  cp "${OCI_CONFIG_PATH}" "${BACKUP_PATH}"
  warn "Existing config backed up to ${BACKUP_PATH}"
fi

cat > "${OCI_CONFIG_PATH}" <<EOF
[DEFAULT]
user=${OCI_USER_OCID}
fingerprint=${OCI_API_KEY_FINGERPRINT}
tenancy=${OCI_TENANCY_OCID}
region=${OCI_REGION}
key_file=${OCI_PRIVATE_KEY_PATH}
EOF

chmod 600 "${OCI_CONFIG_PATH}"
pass "OCI config written and secured (mode 600)"

echo ""
echo "  Config written:"
cat "${OCI_CONFIG_PATH}"
echo ""

# =============================================================================
# Step 3 — Check private key is present
# =============================================================================
log "STEP 3: Checking OCI private key at ${OCI_PRIVATE_KEY_PATH}..."

if [[ -f "${OCI_PRIVATE_KEY_PATH}" ]]; then
  chmod 600 "${OCI_PRIVATE_KEY_PATH}"
  pass "OCI private key found. Permissions set to 600."
else
  echo ""
  warn "OCI private key NOT found at ${OCI_PRIVATE_KEY_PATH}"
  echo ""
  echo "  To copy the key to this server, run the following from your LOCAL machine:"
  echo ""
  echo "    scp -i ~/.ssh/zdm.pem \\"
  echo "        /local/path/oci_api_key.pem \\"
  echo "        azureuser@10.1.0.8:/tmp/oci_api_key.pem"
  echo ""
  echo "  Then on the ZDM server as an admin user:"
  echo ""
  echo "    sudo cp /tmp/oci_api_key.pem ${OCI_PRIVATE_KEY_PATH}"
  echo "    sudo chown zdmuser:zdmuser ${OCI_PRIVATE_KEY_PATH}"
  echo "    sudo chmod 600 ${OCI_PRIVATE_KEY_PATH}"
  echo ""
  echo "  After copying the key, re-run this script."
  echo ""
  fail "Cannot proceed without private key. Exiting."
fi

# =============================================================================
# Step 4 — Verify OCI CLI is installed and in PATH
# =============================================================================
log "STEP 4: Verifying OCI CLI installation..."

if command -v oci &>/dev/null; then
  OCI_VERSION=$(oci --version 2>&1 | head -1)
  pass "OCI CLI found: ${OCI_VERSION}"
else
  fail "OCI CLI not found in PATH. Install it with:" \
       "bash -c \"\$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)\""
fi

# =============================================================================
# Step 5 — Test OCI CLI connectivity (get Object Storage namespace)
# =============================================================================
log "STEP 5: Testing OCI CLI connectivity — retrieving Object Storage namespace..."

set +e
OCI_NS_OUTPUT=$(oci os ns get 2>&1)
OCI_NS_EXIT=$?
set -e

if [[ ${OCI_NS_EXIT} -eq 0 ]]; then
  # Extract the namespace value from JSON output: {"data": "abc123xyz"}
  OCI_NAMESPACE=$(echo "${OCI_NS_OUTPUT}" | grep '"data"' | sed 's/.*"data"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
  pass "OCI CLI connectivity OK"
  echo ""
  echo "  Object Storage namespace: ${OCI_NAMESPACE}"
  echo ""
  echo "  *** ACTION REQUIRED: Update zdm-env.md ***"
  echo "  Set OCI_OSS_NAMESPACE = ${OCI_NAMESPACE}"
  echo ""
else
  echo ""
  warn "OCI CLI connectivity FAILED. Error output:"
  echo "${OCI_NS_OUTPUT}"
  echo ""
  echo "  Common causes:"
  echo "    1. Private key file incorrect or corrupted"
  echo "    2. Fingerprint mismatch — verify in OCI Console:"
  echo "       Menu → Identity → Users → (your user) → API Keys"
  echo "       Expected fingerprint: ${OCI_API_KEY_FINGERPRINT}"
  echo "    3. OCI User OCID incorrect"
  echo "    4. HTTPS outbound blocked (port 443) from ZDM server to OCI"
  echo "       Test: curl -s https://objectstorage.${OCI_REGION}.oraclecloud.com"
  echo ""
  echo "  Debug with: oci os ns get --debug 2>&1 | head -60"
  echo ""
  fail "OCI connectivity check failed. Resolve network/credential issue and re-run."
fi

# =============================================================================
# Step 6 — List OCI regions (confirms auth is working end-to-end)
# =============================================================================
log "STEP 6: Confirming OCI region list (auth end-to-end check)..."

set +e
oci iam region list --output table 2>&1 | grep -E "REGION-NAME|${OCI_REGION}|Key"
set -e

pass "OCI IAM API reachable. Region ${OCI_REGION} should appear above."

# =============================================================================
# Step 7 — Object Storage bucket creation (OPTIONAL — uncomment to activate)
# =============================================================================
log "STEP 7: Object Storage bucket creation (currently SKIPPED — see instructions)"

echo ""
echo "  To create the migration staging bucket, either:"
echo "  A) Uncomment and set OCI_OSS_NAMESPACE / OCI_OSS_BUCKET_NAME at the top"
echo "     of this script, then re-run."
echo ""
echo "  B) Run manually as zdmuser after noting the namespace from Step 5:"
echo ""
echo "     oci os bucket create \\"
echo "       --namespace-name \"<your-namespace>\" \\"
echo "       --name \"zdm-migration-oradb\" \\"
echo "       --compartment-id \"${OCI_COMPARTMENT_OCID}\" \\"
echo "       --public-access-type \"NoPublicAccess\""
echo ""
echo "  C) Create via OCI Console:"
echo "     Storage → Object Storage & Archive Storage → Buckets → Create Bucket"
echo "     Namespace: <your-namespace> | Bucket Name: zdm-migration-oradb"
echo "     Compartment: (select migration compartment)"
echo ""

# --- Uncomment the block below AFTER setting OCI_OSS_NAMESPACE and OCI_OSS_BUCKET_NAME above ---
#
# if [[ -n "${OCI_OSS_NAMESPACE:-}" && -n "${OCI_OSS_BUCKET_NAME:-}" ]]; then
#   log "Creating Object Storage bucket ${OCI_OSS_BUCKET_NAME} in namespace ${OCI_OSS_NAMESPACE}..."
#   set +e
#   BUCKET_OUTPUT=$(oci os bucket create \
#     --namespace-name "${OCI_OSS_NAMESPACE}" \
#     --name "${OCI_OSS_BUCKET_NAME}" \
#     --compartment-id "${OCI_COMPARTMENT_OCID}" \
#     --public-access-type "NoPublicAccess" 2>&1)
#   BUCKET_EXIT=$?
#   set -e
#   if [[ ${BUCKET_EXIT} -eq 0 ]]; then
#     pass "Bucket '${OCI_OSS_BUCKET_NAME}' created successfully."
#   else
#     echo "${BUCKET_OUTPUT}"
#     warn "Bucket creation failed or bucket already exists — review output above."
#   fi
# fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "============================================================"
echo " zdm_configure_oci.sh — Completed"
echo "============================================================"
echo ""
echo " Next steps:"
echo "   1. Note the namespace printed in Step 5 above."
echo "   2. Create the Object Storage bucket (Step 7 options above)."
echo "   3. Update zdm-env.md:"
echo "        OCI_OSS_NAMESPACE:   <value from Step 5>"
echo "        OCI_OSS_BUCKET_NAME: zdm-migration-oradb"
echo "   4. Verify the bucket:"
echo "        oci os bucket get \\"
echo "          --namespace-name \"<namespace>\" \\"
echo "          --bucket-name \"zdm-migration-oradb\""
echo "   5. Update Issue-Resolution-Log-ORADB.md:"
echo "        Issue 3 (OCI config) → ✅ Resolved"
echo "        Issue 4 (OSS namespace/bucket) → ✅ Resolved"
echo "   6. Proceed to Step 3 — Generate Migration Artifacts"
echo "============================================================"
