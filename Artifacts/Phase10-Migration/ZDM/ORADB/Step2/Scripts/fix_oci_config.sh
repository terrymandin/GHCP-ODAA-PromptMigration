#!/usr/bin/env bash
# =============================================================================
# fix_oci_config.sh
# Purpose: Create and validate the OCI CLI configuration (~/.oci/config) for
#          zdmuser on the ZDM server so ZDM can interact with OCI services.
# Target:  Run as zdmuser directly on the ZDM server (no SSH required).
# Issue:   Issue 3 — OCI config for zdmuser not verified; azureuser has none.
# =============================================================================

set -euo pipefail

# --- User guard ---
if [[ "$(whoami)" != "zdmuser" ]]; then
  echo "ERROR: This script must be run as zdmuser. Current user: $(whoami)"
  echo "       Switch with: sudo su - zdmuser"
  exit 1
fi

# =============================================================================
# Configuration (from zdm-env.md)
# Override any value by exporting the variable before running the script.
# =============================================================================
OCI_TENANCY_OCID="${OCI_TENANCY_OCID:-ocid1.tenancy.oc1..aaaaaaaarvyhjcn7wkkxxx5g3o7lgqks23bmsjtsticz3gtg5xs5qyrwkftq}"
OCI_USER_OCID="${OCI_USER_OCID:-ocid1.user.oc1..aaaaaaaakfe5cirdq7vkkrhogjrgcrgftvwb7mdoehujgchefpqv54vhsnoa}"
OCI_REGION="${OCI_REGION:-uk-london-1}"
OCI_FINGERPRINT="${OCI_FINGERPRINT:-7f:05:c1:f2:5c:3a:46:ec:9f:95:44:c8:77:a4:50:f9}"
OCI_PRIVATE_KEY_PATH="${OCI_PRIVATE_KEY_PATH:-${HOME}/.oci/oci_api_key.pem}"
OCI_CONFIG_DIR="${HOME}/.oci"
OCI_CONFIG_FILE="${OCI_CONFIG_DIR}/config"
TARGET_DATABASE_OCID="${TARGET_DATABASE_OCID:-ocid1.database.oc1.uk-london-1.anwgiljss56liuaatz45cjnpbvpgku7gkorvxg6lytoj5lxxruk2eqxzkzma}"

# =============================================================================
echo "============================================================"
echo "  fix_oci_config.sh — Issue 3: Configure OCI CLI for zdmuser"
echo "============================================================"
echo ""
echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] Running as: $(whoami) on $(hostname)"
echo ""

# =============================================================================
# Step 1: Verify OCI CLI is installed
# =============================================================================
echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] Checking OCI CLI installation ..."
if ! command -v oci &>/dev/null; then
  echo "❌ FAIL: OCI CLI not found in PATH."
  echo "   Install with: bash -c \"\$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)\""
  exit 1
fi
OCI_CLI_VERSION=$(oci --version 2>&1 || true)
echo "✅ OCI CLI found: ${OCI_CLI_VERSION}"
echo ""

# =============================================================================
# Step 2: Check if private key file exists
# =============================================================================
echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] Checking OCI API private key at: ${OCI_PRIVATE_KEY_PATH} ..."
if [[ ! -f "${OCI_PRIVATE_KEY_PATH}" ]]; then
  echo "❌ FAIL: OCI API private key not found at: ${OCI_PRIVATE_KEY_PATH}"
  echo ""
  echo "   To resolve:"
  echo "   1. Upload your OCI API private key to the ZDM server:"
  echo "      scp -i ~/.ssh/zdm.pem /path/to/oci_api_key.pem azureuser@10.1.0.8:/tmp/"
  echo "   2. As zdmuser, move it into place:"
  echo "      mkdir -p ~/.oci && mv /tmp/oci_api_key.pem ~/.oci/oci_api_key.pem && chmod 600 ~/.oci/oci_api_key.pem"
  echo "   3. Re-run this script."
  exit 1
fi

# Verify key permissions
KEY_PERMS=$(stat -c '%a' "${OCI_PRIVATE_KEY_PATH}" 2>/dev/null || stat -f '%A' "${OCI_PRIVATE_KEY_PATH}" 2>/dev/null || echo "unknown")
if [[ "${KEY_PERMS}" != "600" ]]; then
  echo "⚠️  WARNING: Private key permissions are ${KEY_PERMS}, expected 600. Fixing ..."
  chmod 600 "${OCI_PRIVATE_KEY_PATH}"
  echo "   Permissions updated to 600."
fi
echo "✅ OCI API private key found and permissions OK (${OCI_PRIVATE_KEY_PATH})"
echo ""

# =============================================================================
# Step 3: Create or overwrite ~/.oci/config
# =============================================================================
echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] Creating OCI config at: ${OCI_CONFIG_FILE} ..."

# Backup existing config if it exists
if [[ -f "${OCI_CONFIG_FILE}" ]]; then
  BACKUP="${OCI_CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
  cp "${OCI_CONFIG_FILE}" "${BACKUP}"
  echo "   Existing config backed up to: ${BACKUP}"
fi

mkdir -p "${OCI_CONFIG_DIR}"
chmod 700 "${OCI_CONFIG_DIR}"

cat > "${OCI_CONFIG_FILE}" <<EOF
[DEFAULT]
user=${OCI_USER_OCID}
fingerprint=${OCI_FINGERPRINT}
tenancy=${OCI_TENANCY_OCID}
region=${OCI_REGION}
key_file=${OCI_PRIVATE_KEY_PATH}
EOF

chmod 600 "${OCI_CONFIG_FILE}"
echo "✅ ~/.oci/config written successfully."
echo ""

# =============================================================================
# Step 4: Display the config for review (mask sensitive OCID values partially)
# =============================================================================
echo "--- Config summary (${OCI_CONFIG_FILE}) ---"
echo "[DEFAULT]"
echo "  user        = ${OCI_USER_OCID:0:30}..."
echo "  fingerprint = ${OCI_FINGERPRINT}"
echo "  tenancy     = ${OCI_TENANCY_OCID:0:30}..."
echo "  region      = ${OCI_REGION}"
echo "  key_file    = ${OCI_PRIVATE_KEY_PATH}"
echo ""

# =============================================================================
# Step 5: Validate OCI CLI connectivity — get tenancy namespace
# =============================================================================
echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] Testing OCI CLI connectivity (oci os ns get) ..."
NS_OUTPUT=$(oci os ns get 2>&1) || {
  echo ""
  echo "❌ FAIL: 'oci os ns get' returned an error:"
  echo "${NS_OUTPUT}"
  echo ""
  echo "Common causes:"
  echo "  1. Wrong API key fingerprint — verify in OCI Console → Identity → Users → API Keys"
  echo "  2. Wrong private key file — ensure ${OCI_PRIVATE_KEY_PATH} matches the uploaded public key"
  echo "  3. Wrong region — confirm target region is '${OCI_REGION}'"
  echo "  4. User not authorised for Object Storage — check IAM policies"
  exit 1
}

OCI_NAMESPACE=$(echo "${NS_OUTPUT}" | grep -oP '(?<="data": ")[^"]+' || echo "(parse error — check output above)")
echo "✅ OCI CLI connectivity confirmed."
echo "   Object Storage Namespace: ${OCI_NAMESPACE}"
echo ""
echo "   ⚠️  ACTION REQUIRED: Record this namespace in the Migration Questionnaire"
echo "   (Section C — Object Storage Configuration, OCI_OSS_NAMESPACE field)."
echo "   Namespace value: ${OCI_NAMESPACE}"
echo ""

# =============================================================================
# Step 6: Validate target database OCID is accessible
# =============================================================================
echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] Verifying target database OCID access ..."
DB_OUTPUT=$(oci db database get --database-id "${TARGET_DATABASE_OCID}" 2>&1) || {
  echo "⚠️  WARNING: Could not retrieve target database via OCID."
  echo "   Output: ${DB_OUTPUT}"
  echo "   This may indicate:"
  echo "     - Insufficient IAM policy for the OCI user on the target DB"
  echo "     - Incorrect TARGET_DATABASE_OCID"
  echo "   OCI CLI connectivity itself is working (namespace test passed)."
  echo "   Investigate IAM policies before proceeding to Step 3."
  echo ""
}

if echo "${DB_OUTPUT}" | grep -q '"lifecycle-state"'; then
  DB_STATE=$(echo "${DB_OUTPUT}" | grep -oP '(?<="lifecycle-state": ")[^"]+' || echo "UNKNOWN")
  echo "✅ Target database accessible via OCI API. Lifecycle state: ${DB_STATE}"
fi
echo ""

# =============================================================================
# Summary
# =============================================================================
echo "============================================================"
echo "  fix_oci_config.sh — Summary"
echo "============================================================"
echo ""
echo "✅ OCI config created at ${OCI_CONFIG_FILE}"
echo "✅ OCI CLI can authenticate and reach OCI Object Storage"
echo ""
echo "Object Storage Namespace: ${OCI_NAMESPACE}"
echo ""
echo "Next steps:"
echo "  1. Update Migration Questionnaire Section C with:"
echo "     OCI_OSS_NAMESPACE  = ${OCI_NAMESPACE}"
echo "     OCI_OSS_BUCKET_NAME = zdm-migration-oradb (or your chosen name)"
echo "  2. Create the Object Storage bucket if it does not exist:"
echo "     oci os bucket create \\"
echo "       --compartment-id ${OCI_TENANCY_OCID:0:20}... \\"
echo "       --name zdm-migration-oradb \\"
echo "       --namespace-name ${OCI_NAMESPACE}"
echo "  3. Run verify_fixes.sh to confirm all three blockers are resolved."
echo ""
echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] fix_oci_config.sh completed."
