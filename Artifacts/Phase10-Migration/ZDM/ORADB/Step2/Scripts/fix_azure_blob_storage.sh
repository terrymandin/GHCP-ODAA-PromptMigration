#!/usr/bin/env bash
# =============================================================================
# fix_azure_blob_storage.sh
# Purpose : Configure an Azure Blob Storage container as the ZDM staging
#           location for ONLINE_PHYSICAL migration.
#           Replaces fix_oci_cli_config.sh — OCI Object Storage path is not
#           available (federated user; no API key / IAM access).
# Run as  : zdmuser on the ZDM server (tm-vm-odaa-oracle-jumpbox / 10.1.0.8)
# Step    : ZDM Migration Step 2 — Fix Issues
# Issue   : Issue 1 (staging auth) + Issue 6 (staging container)
# =============================================================================

set -uo pipefail

# --- User guard: must run as zdmuser ---
if [[ "$(whoami)" != "zdmuser" ]]; then
  echo "ERROR: This script must be run as zdmuser. Current user: $(whoami)"
  echo "       Switch with: sudo su - zdmuser"
  exit 1
fi

# =============================================================================
# Defaults — override via environment variables before running or accept prompts
# =============================================================================
AZURE_STORAGE_ACCOUNT="${AZURE_STORAGE_ACCOUNT:-}"
AZURE_STORAGE_CONTAINER="${AZURE_STORAGE_CONTAINER:-zdm-oradb-migration}"
AZURE_STORAGE_KEY="${AZURE_STORAGE_KEY:-}"          # Storage account access key
AZURE_STORAGE_SAS="${AZURE_STORAGE_SAS:-}"          # SAS token (alternative to key)
# Auth type is auto-detected: key takes precedence over SAS
# If neither is set, you will be prompted interactively.

CREDS_DIR="${HOME}/.azure"
CREDS_FILE="${CREDS_DIR}/zdm_blob_creds"

LOG_DIR="${HOME}/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/fix_azure_blob_storage_$(date +%Y%m%d_%H%M%S).log"

# =============================================================================
# Logging helpers
# =============================================================================
log()  { echo "[$(date '+%H:%M:%S')] $*" | tee -a "${LOG_FILE}"; }
pass() { echo "[$(date '+%H:%M:%S')] ✅ PASS  $*" | tee -a "${LOG_FILE}"; }
fail() { echo "[$(date '+%H:%M:%S')] ❌ FAIL  $*" | tee -a "${LOG_FILE}"; fail_count=$((fail_count + 1)); }
warn() { echo "[$(date '+%H:%M:%S')] ⚠️  WARN  $*" | tee -a "${LOG_FILE}"; }
info() { echo "[$(date '+%H:%M:%S')] ℹ️  INFO  $*" | tee -a "${LOG_FILE}"; }

fail_count=0

log "================================================================"
log "fix_azure_blob_storage.sh — Azure Blob Storage Configuration"
log "Running as: $(whoami)  on  $(hostname)"
log "Log: ${LOG_FILE}"
log "================================================================"

# =============================================================================
# Step 1: Detect available tooling (az CLI or curl fallback)
# =============================================================================
log ""
log "--- Step 1: Detect available tooling ---"

USE_AZ_CLI=false
USE_CURL_SAS=false

if command -v az &>/dev/null; then
  AZ_VERSION=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
  pass "Azure CLI found: ${AZ_VERSION}"
  USE_AZ_CLI=true
else
  warn "Azure CLI (az) not found in PATH."
  info "To install Azure CLI on Oracle Linux / RHEL:"
  info "  sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc"
  info "  sudo dnf install -y https://packages.microsoft.com/config/rhel/8/packages-microsoft-prod.rpm"
  info "  sudo dnf install -y azure-cli"
  info ""
  info "Alternatively, if you have a SAS token, this script can verify using curl."
  info "Proceeding — will determine auth method based on credentials provided."
fi

# =============================================================================
# Step 2: Collect credentials interactively if not set via environment
# =============================================================================
log ""
log "--- Step 2: Collect Azure Blob Storage credentials ---"

if [[ -z "${AZURE_STORAGE_ACCOUNT}" ]]; then
  echo ""
  echo "Enter Azure Storage Account name (e.g. mystorageaccount):"
  read -r AZURE_STORAGE_ACCOUNT
  if [[ -z "${AZURE_STORAGE_ACCOUNT}" ]]; then
    fail "Storage account name is required."
    exit 1
  fi
fi
info "Storage account: ${AZURE_STORAGE_ACCOUNT}"

echo ""
echo "Enter container name [default: ${AZURE_STORAGE_CONTAINER}]:"
read -r INPUT_CONTAINER
AZURE_STORAGE_CONTAINER="${INPUT_CONTAINER:-${AZURE_STORAGE_CONTAINER}}"
info "Container: ${AZURE_STORAGE_CONTAINER}"

if [[ -z "${AZURE_STORAGE_KEY}" && -z "${AZURE_STORAGE_SAS}" ]]; then
  echo ""
  echo "Select authentication method:"
  echo "  1) Storage account access key (full access)"
  echo "  2) SAS token (scoped access — recommended)"
  read -r AUTH_CHOICE
  case "${AUTH_CHOICE}" in
    1)
      echo "Enter storage account access key (input hidden):"
      read -rs AZURE_STORAGE_KEY
      echo ""
      if [[ -z "${AZURE_STORAGE_KEY}" ]]; then
        fail "Storage account key is required for option 1."
        exit 1
      fi
      ;;
    2)
      echo "Enter SAS token (starts with 'sv=' or '?sv=', input hidden):"
      read -rs AZURE_STORAGE_SAS
      echo ""
      # Strip leading '?' if present
      AZURE_STORAGE_SAS="${AZURE_STORAGE_SAS#\?}"
      if [[ -z "${AZURE_STORAGE_SAS}" ]]; then
        fail "SAS token is required for option 2."
        exit 1
      fi
      USE_CURL_SAS=true
      ;;
    *)
      fail "Invalid selection '${AUTH_CHOICE}' — must be 1 or 2."
      exit 1
      ;;
  esac
fi

# Determine auth type if set via environment
if [[ -n "${AZURE_STORAGE_KEY}" ]]; then
  info "Auth method: storage account access key"
elif [[ -n "${AZURE_STORAGE_SAS}" ]]; then
  info "Auth method: SAS token"
  USE_CURL_SAS=true
fi

# =============================================================================
# Step 3: Test connectivity — container exists or can be created
# =============================================================================
log ""
log "--- Step 3: Test Azure Blob Storage connectivity ---"

BLOB_ENDPOINT="https://${AZURE_STORAGE_ACCOUNT}.blob.core.windows.net"
info "Blob endpoint: ${BLOB_ENDPOINT}"

CONTAINER_EXISTS=false

if [[ "${USE_AZ_CLI}" == true && -n "${AZURE_STORAGE_KEY}" ]]; then
  # --- az CLI with account key ---
  info "Testing connectivity via az storage container show..."
  if az storage container show \
      --name "${AZURE_STORAGE_CONTAINER}" \
      --account-name "${AZURE_STORAGE_ACCOUNT}" \
      --account-key "${AZURE_STORAGE_KEY}" \
      --output none 2>>"${LOG_FILE}"; then
    pass "Container '${AZURE_STORAGE_CONTAINER}' exists and is accessible."
    CONTAINER_EXISTS=true
  else
    info "Container '${AZURE_STORAGE_CONTAINER}' not found — will attempt to create."
  fi

elif [[ "${USE_AZ_CLI}" == true && -n "${AZURE_STORAGE_SAS}" ]]; then
  # --- az CLI with SAS token ---
  info "Testing connectivity via az storage container show (SAS)..."
  if az storage container show \
      --name "${AZURE_STORAGE_CONTAINER}" \
      --account-name "${AZURE_STORAGE_ACCOUNT}" \
      --sas-token "${AZURE_STORAGE_SAS}" \
      --output none 2>>"${LOG_FILE}"; then
    pass "Container '${AZURE_STORAGE_CONTAINER}' exists and is accessible via SAS token."
    CONTAINER_EXISTS=true
  else
    info "Container '${AZURE_STORAGE_CONTAINER}' not found — will attempt to create."
  fi

elif [[ "${USE_CURL_SAS}" == true && -n "${AZURE_STORAGE_SAS}" ]]; then
  # --- curl fallback with SAS token ---
  info "Testing connectivity via curl (no az CLI)..."
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    "${BLOB_ENDPOINT}/${AZURE_STORAGE_CONTAINER}?restype=container&${AZURE_STORAGE_SAS}" \
    2>>"${LOG_FILE}" || echo "000")
  if [[ "${HTTP_STATUS}" == "200" ]]; then
    pass "Container '${AZURE_STORAGE_CONTAINER}' exists and is accessible (HTTP ${HTTP_STATUS})."
    CONTAINER_EXISTS=true
  elif [[ "${HTTP_STATUS}" == "404" ]]; then
    info "Container '${AZURE_STORAGE_CONTAINER}' not found (HTTP 404) — will attempt to create."
  elif [[ "${HTTP_STATUS}" == "403" ]]; then
    fail "Access denied (HTTP 403). SAS token may lack required permissions (need: read, write, delete, list, create)."
    fail "Regenerate the SAS token with full container permissions and re-run."
    exit 1
  else
    fail "Unexpected HTTP status from Blob endpoint: ${HTTP_STATUS}"
    fail "Verify the storage account name, endpoint, and SAS token."
    exit 1
  fi

else
  fail "No valid auth method available. Ensure az CLI is installed or provide a SAS token."
  exit 1
fi

# =============================================================================
# Step 4: Create container if it does not already exist
# =============================================================================
log ""
log "--- Step 4: Create container '${AZURE_STORAGE_CONTAINER}' if absent ---"

if [[ "${CONTAINER_EXISTS}" == true ]]; then
  warn "Container '${AZURE_STORAGE_CONTAINER}' already exists — skipping creation."

elif [[ "${USE_AZ_CLI}" == true && -n "${AZURE_STORAGE_KEY}" ]]; then
  info "Creating container via az CLI (access key)..."
  if az storage container create \
      --name "${AZURE_STORAGE_CONTAINER}" \
      --account-name "${AZURE_STORAGE_ACCOUNT}" \
      --account-key "${AZURE_STORAGE_KEY}" \
      --public-access off \
      --output none 2>>"${LOG_FILE}"; then
    pass "Container '${AZURE_STORAGE_CONTAINER}' created successfully (private access)."
  else
    fail "Failed to create container. Check account name, key, and permissions."
    exit 1
  fi

elif [[ "${USE_AZ_CLI}" == true && -n "${AZURE_STORAGE_SAS}" ]]; then
  info "Creating container via az CLI (SAS)..."
  if az storage container create \
      --name "${AZURE_STORAGE_CONTAINER}" \
      --account-name "${AZURE_STORAGE_ACCOUNT}" \
      --sas-token "${AZURE_STORAGE_SAS}" \
      --public-access off \
      --output none 2>>"${LOG_FILE}"; then
    pass "Container '${AZURE_STORAGE_CONTAINER}' created successfully (private access)."
  else
    fail "Failed to create container via SAS. Ensure SAS has create + write permissions."
    exit 1
  fi

elif [[ "${USE_CURL_SAS}" == true && -n "${AZURE_STORAGE_SAS}" ]]; then
  info "Creating container via curl (SAS)..."
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -X PUT \
    "${BLOB_ENDPOINT}/${AZURE_STORAGE_CONTAINER}?restype=container&${AZURE_STORAGE_SAS}" \
    2>>"${LOG_FILE}" || echo "000")
  if [[ "${HTTP_STATUS}" == "201" ]]; then
    pass "Container '${AZURE_STORAGE_CONTAINER}' created successfully (HTTP 201)."
  else
    fail "Container creation via curl returned HTTP ${HTTP_STATUS}."
    fail "Ensure the SAS token has 'Create' and 'Write' permissions on the container."
    exit 1
  fi
fi

# =============================================================================
# Step 5: Write credentials file for use in Step 3 / ZDM RSP generation
# =============================================================================
log ""
log "--- Step 5: Write credentials file ${CREDS_FILE} ---"

mkdir -p "${CREDS_DIR}"
chmod 700 "${CREDS_DIR}"

if [[ -f "${CREDS_FILE}" ]]; then
  warn "Existing creds file found — backing up to ${CREDS_FILE}.bak"
  cp "${CREDS_FILE}" "${CREDS_FILE}.bak"
fi

# Determine which credential to store
if [[ -n "${AZURE_STORAGE_KEY}" ]]; then
  CREDS_AUTH_TYPE="key"
  CREDS_AUTH_VALUE="${AZURE_STORAGE_KEY}"
else
  CREDS_AUTH_TYPE="sas"
  CREDS_AUTH_VALUE="${AZURE_STORAGE_SAS}"
fi

cat > "${CREDS_FILE}" << EOF
# ZDM Azure Blob Storage credentials
# Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
# Used by: Step 3 ZDM RSP generation
AZURE_STORAGE_ACCOUNT="${AZURE_STORAGE_ACCOUNT}"
AZURE_STORAGE_CONTAINER="${AZURE_STORAGE_CONTAINER}"
AZURE_STORAGE_AUTH_TYPE="${CREDS_AUTH_TYPE}"
AZURE_STORAGE_AUTH_VALUE="${CREDS_AUTH_VALUE}"
AZURE_BLOB_ENDPOINT="${BLOB_ENDPOINT}"
EOF

chmod 600 "${CREDS_FILE}"
pass "Credentials written to ${CREDS_FILE} (permissions 600)."

# =============================================================================
# Summary
# =============================================================================
log ""
log "================================================================"
log "SUMMARY"
log "================================================================"

if [[ "${fail_count}" -eq 0 ]]; then
  pass "Issue 1 RESOLVED: Azure Blob Storage credentials configured at ${CREDS_FILE}"
  pass "Issue 6 RESOLVED: Azure Blob container '${AZURE_STORAGE_CONTAINER}' is ready at ${BLOB_ENDPOINT}"
  log ""
  log "Next steps:"
  log "  1. Update zdm-env.md with:"
  log "       AZURE_STORAGE_ACCOUNT_NAME: ${AZURE_STORAGE_ACCOUNT}"
  log "       AZURE_STORAGE_CONTAINER_NAME: ${AZURE_STORAGE_CONTAINER}"
  log "       AZURE_BLOB_ENDPOINT: ${BLOB_ENDPOINT}"
  log "       AZURE_STORAGE_AUTH_TYPE: ${CREDS_AUTH_TYPE}"
  log "       (Do NOT commit the key or SAS token to the repo)"
  log ""
  log "  2. ZDM response file parameters for Step 3 (confirm against ZDM 21.5 docs):"
  log "       COMMON_BACKUP_AZURE_ACCOUNT_NAME=${AZURE_STORAGE_ACCOUNT}"
  log "       COMMON_BACKUP_AZURE_CONTAINER_NAME=${AZURE_STORAGE_CONTAINER}"
  log "       COMMON_BACKUP_AZURE_ENDPOINT=${BLOB_ENDPOINT}"
  if [[ "${CREDS_AUTH_TYPE}" == "key" ]]; then
    log "       COMMON_BACKUP_AZURE_ACCOUNT_KEY=<from ${CREDS_FILE}>"
  else
    log "       COMMON_BACKUP_AZURE_SAS_TOKEN=<from ${CREDS_FILE}>"
  fi
  log ""
  log "  3. Run verify_fixes.sh to confirm all blocker checks pass."
  log ""
  log "fix_azure_blob_storage.sh completed successfully. Log: ${LOG_FILE}"
else
  log ""
  log "❌ Script completed with ${fail_count} failure(s). Review log: ${LOG_FILE}"
  exit 1
fi

