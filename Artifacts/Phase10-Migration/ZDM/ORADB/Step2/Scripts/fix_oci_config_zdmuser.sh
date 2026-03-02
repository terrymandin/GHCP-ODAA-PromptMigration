#!/usr/bin/env bash
# ==============================================================
# fix_oci_config_zdmuser.sh
#
# Creates ~/.oci/config for zdmuser on the ZDM server, then
# validates OCI CLI connectivity using "oci os ns get".
#
# Run from:  ZDM server (tm-vm-odaa-oracle-jumpbox) AS zdmuser
#
# Prerequisites:
#   1. The OCI API private key file must already exist at
#      /home/zdmuser/.oci/oci_api_key.pem   (chmod 600)
#
#   To upload from your workstation:
#     scp -i ~/.ssh/zdm.pem /path/to/oci_api_key.pem \
#         azureuser@10.1.0.8:/tmp/oci_api_key.pem
#
#   Then on the ZDM server (as azureuser):
#     sudo mkdir -p /home/zdmuser/.oci
#     sudo mv /tmp/oci_api_key.pem /home/zdmuser/.oci/oci_api_key.pem
#     sudo chown zdmuser:zdmuser /home/zdmuser/.oci/oci_api_key.pem
#     sudo chmod 600 /home/zdmuser/.oci/oci_api_key.pem
# ==============================================================
set -euo pipefail

# ── Configuration (from zdm-env.md) ──────────────────────────────
OCI_USER_OCID="${OCI_USER_OCID:-ocid1.user.oc1..aaaaaaaakfe5cirdq7vkkrhogjrgcrgftvwb7mdoehujgchefpqv54vhsnoa}"
OCI_TENANCY_OCID="${OCI_TENANCY_OCID:-ocid1.tenancy.oc1..aaaaaaaarvyhjcn7wkkxxx5g3o7lgqks23bmsjtsticz3gtg5xs5qyrwkftq}"
OCI_REGION="${OCI_REGION:-uk-london-1}"
OCI_FINGERPRINT="${OCI_FINGERPRINT:-7f:05:c1:f2:5c:3a:46:ec:9f:95:44:c8:77:a4:50:f9}"
OCI_PRIVATE_KEY_PATH="${OCI_PRIVATE_KEY_PATH:-${HOME}/.oci/oci_api_key.pem}"

OCI_CONFIG_DIR="${HOME}/.oci"
OCI_CONFIG_FILE="${OCI_CONFIG_DIR}/config"

echo "================================================================"
echo " fix_oci_config_zdmuser.sh — Create ~/.oci/config for zdmuser"
echo " Running as: $(whoami)  on  $(hostname)"
echo "================================================================"
echo ""

# ── Step 1: Verify running as zdmuser ────────────────────────────
echo "---- Step 1: Verify user identity ------------------------------"
CURRENT_USER=$(whoami)
if [[ "${CURRENT_USER}" != "zdmuser" ]]; then
  echo "⚠️  WARNING: This script should be run as zdmuser."
  echo "   Current user: ${CURRENT_USER}"
  echo "   Switch user:  sudo su - zdmuser"
  echo ""
  echo "   The ~/.oci/config will be created for the current user (${CURRENT_USER})."
  echo "   ZDM requires the config under the zdmuser home directory."
fi
echo "   User: ${CURRENT_USER}"
echo "   Home: ${HOME}"

# ── Step 2: Create .oci directory ────────────────────────────────
echo ""
echo "---- Step 2: Create ~/.oci directory ---------------------------"
mkdir -p "${OCI_CONFIG_DIR}"
chmod 700 "${OCI_CONFIG_DIR}"
echo "   ✅ Directory: ${OCI_CONFIG_DIR}"

# ── Step 3: Check API private key ────────────────────────────────
echo ""
echo "---- Step 3: Check API private key -----------------------------"
if [[ -f "${OCI_PRIVATE_KEY_PATH}" ]]; then
  chmod 600 "${OCI_PRIVATE_KEY_PATH}"
  echo "   ✅ Private key found: ${OCI_PRIVATE_KEY_PATH}"
else
  echo "   ❌ Private key NOT found: ${OCI_PRIVATE_KEY_PATH}"
  echo ""
  echo "   Upload your OCI API private key before this script will work:"
  echo "   (From your workstation):"
  echo "     scp -i ~/.ssh/zdm.pem /path/to/oci_api_key.pem \\"
  echo "         azureuser@10.1.0.8:/tmp/oci_api_key.pem"
  echo "   (On ZDM server as azureuser):"
  echo "     sudo mkdir -p /home/zdmuser/.oci"
  echo "     sudo mv /tmp/oci_api_key.pem /home/zdmuser/.oci/oci_api_key.pem"
  echo "     sudo chown zdmuser:zdmuser /home/zdmuser/.oci/oci_api_key.pem"
  echo "     sudo chmod 600 /home/zdmuser/.oci/oci_api_key.pem"
  echo ""
  echo "   Config will be written now; re-run script after uploading the key."
fi

# ── Step 4: Write ~/.oci/config ──────────────────────────────────
echo ""
echo "---- Step 4: Write ~/.oci/config --------------------------------"
if [[ -f "${OCI_CONFIG_FILE}" ]]; then
  BACKUP="${OCI_CONFIG_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
  cp "${OCI_CONFIG_FILE}" "${BACKUP}"
  echo "   ⚠️  Existing config backed up to: ${BACKUP}"
fi

cat > "${OCI_CONFIG_FILE}" <<EOF
[DEFAULT]
user=${OCI_USER_OCID}
tenancy=${OCI_TENANCY_OCID}
region=${OCI_REGION}
fingerprint=${OCI_FINGERPRINT}
key_file=${OCI_PRIVATE_KEY_PATH}
EOF

chmod 600 "${OCI_CONFIG_FILE}"
echo "   ✅ Config written: ${OCI_CONFIG_FILE}"

# ── Step 5: Verify OCI CLI connectivity ──────────────────────────
echo ""
echo "---- Step 5: Verify OCI CLI connectivity -----------------------"
echo "   Running: oci os ns get"
echo ""

if ! command -v oci &>/dev/null; then
  echo "   ❌ 'oci' command not found. Ensure OCI CLI is installed and in PATH."
  exit 1
fi

OCI_NS_OUTPUT=$(oci os ns get 2>&1) || true
if echo "${OCI_NS_OUTPUT}" | grep -q '"data"'; then
  OCI_NAMESPACE=$(echo "${OCI_NS_OUTPUT}" | grep '"data"' | awk -F'"' '{print $4}')
  echo "   ✅ OCI CLI connectivity confirmed"
  echo "   Object Storage Namespace: ${OCI_NAMESPACE}"
  echo ""
  echo "   *** ACTION REQUIRED: Update zdm-env.md with the namespace: ***"
  echo "   OCI_OSS_NAMESPACE: ${OCI_NAMESPACE}"
else
  echo "   ❌ OCI CLI connectivity failed. Output:"
  echo "   ${OCI_NS_OUTPUT}"
  echo ""
  echo "   Troubleshooting checklist:"
  echo "   1. Private key exists at ${OCI_PRIVATE_KEY_PATH} (chmod 600)"
  echo "   2. Fingerprint '${OCI_FINGERPRINT}' matches the key in OCI Console"
  echo "      (OCI Console → Profile → API Keys)"
  echo "   3. User OCID is correct"
  echo "   4. Network: ZDM server can reach OCI endpoints (HTTPS/443)"
  echo "      Test: curl -I https://objectstorage.uk-london-1.oraclecloud.com"
  exit 1
fi

echo ""
echo "================================================================"
echo " Done."
echo " OCI config created at: ${OCI_CONFIG_FILE}"
echo " OCI Namespace:         ${OCI_NAMESPACE}"
echo ""
echo " Next steps:"
echo "  1. Update zdm-env.md: OCI_OSS_NAMESPACE: ${OCI_NAMESPACE}"
echo "  2. Decide on Object Storage bucket name (recommend: zdm-migration-oradb)"
echo "  3. Create the bucket if it does not exist:"
echo "     oci os bucket create \\"
echo "       --compartment-id ocid1.compartment.oc1..aaaaaaaas4upnqj72dfiivgwvn3uui5gkxo7ng6leeoifucbjiy326urbhmq \\"
echo "       --name zdm-migration-oradb \\"
echo "       --namespace ${OCI_NAMESPACE}"
echo "================================================================"
