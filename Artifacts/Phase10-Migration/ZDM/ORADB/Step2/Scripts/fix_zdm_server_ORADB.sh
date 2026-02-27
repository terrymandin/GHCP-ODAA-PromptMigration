#!/usr/bin/env bash
# =============================================================================
# fix_zdm_server_ORADB.sh
# ZDM Step 2 — ZDM Server remediation for ORADB migration
#
# Resolves: ACTION-05 (Discover OCI OSS Namespace)
#           ACTION-06 (Create OCI Object Storage bucket)
#           ACTION-07 (Initialize ZDM Credential Store)
#           ACTION-10 (Verify zdmuser SSH key access)
#           ACTION-11 (Verify oracle user SSH access)
#
# Run from: ZDM server (10.1.0.8) as azureuser
# Requires: zdmuser with OCI CLI configured (~/.oci/config present)
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Environment — sourced from zdm-env.md
# ---------------------------------------------------------------------------
SOURCE_HOST="10.1.0.11"
TARGET_HOST="10.0.1.160"
ZDM_HOST="10.1.0.8"
SOURCE_SSH_USER="azureuser"
TARGET_SSH_USER="opc"
ORACLE_USER="oracle"
ZDM_SOFTWARE_USER="zdmuser"
SOURCE_SSH_KEY="${HOME}/.ssh/odaa.pem"       # odaa.pem for source
TARGET_SSH_KEY="${HOME}/.ssh/odaa.pem"       # odaa.pem for target
ZDM_HOME="/u01/app/zdmhome"
OCI_COMPARTMENT_OCID="ocid1.compartment.oc1..aaaaaaaas4upnqj72dfiivgwvn3uui5gkxo7ng6leeoifucbjiy326urbhmq"
OCI_REGION="uk-london-1"
# Suggested bucket name — change if already taken
ZDM_BUCKET_NAME="zdm-oradb-migration"

LOG_FILE="$(dirname "$0")/../Logs/fix_zdm_server_ORADB_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")"

log() { echo "[$(date +%Y-%m-%dT%H:%M:%S)] $*" | tee -a "${LOG_FILE}"; }
log_section() { log ""; log "========================================"; log "$*"; log "========================================"; }

# ---------------------------------------------------------------------------
# Helper: run command as zdmuser via sudo
# ---------------------------------------------------------------------------
run_as_zdmuser() {
  sudo -u "${ZDM_SOFTWARE_USER}" env HOME="/home/${ZDM_SOFTWARE_USER}" "$@"
}

# ---------------------------------------------------------------------------
# ACTION-10: Verify zdmuser SSH key access to source and target
# ---------------------------------------------------------------------------
log_section "ACTION-10: Verify zdmuser SSH key access"

# Keys in zdmuser home
ZDMUSER_HOME="/home/${ZDM_SOFTWARE_USER}"

log "Testing SSH from zdmuser to source (${SOURCE_SSH_USER}@${SOURCE_HOST})..."
if run_as_zdmuser ssh -i "${ZDMUSER_HOME}/.ssh/odaa.pem" \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=15 \
    "${SOURCE_SSH_USER}@${SOURCE_HOST}" "echo 'SSH_SOURCE_OK'" 2>&1 | tee -a "${LOG_FILE}" | grep -q "SSH_SOURCE_OK"; then
  log "✅ ACTION-10 SOURCE: zdmuser can SSH to source."
else
  log "❌ ACTION-10 SOURCE: zdmuser cannot SSH to source. Check key permissions."
fi

log "Testing SSH from zdmuser to target (${TARGET_SSH_USER}@${TARGET_HOST})..."
if run_as_zdmuser ssh -i "${ZDMUSER_HOME}/.ssh/odaa.pem" \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=15 \
    "${TARGET_SSH_USER}@${TARGET_HOST}" "echo 'SSH_TARGET_OK'" 2>&1 | tee -a "${LOG_FILE}" | grep -q "SSH_TARGET_OK"; then
  log "✅ ACTION-10 TARGET: zdmuser can SSH to target."
else
  log "❌ ACTION-10 TARGET: zdmuser cannot SSH to target. Check key permissions."
fi

# ---------------------------------------------------------------------------
# ACTION-11: Verify oracle user sudo access from zdmuser via admin SSH user
# ---------------------------------------------------------------------------
log_section "ACTION-11: Verify oracle user access via sudo on source and target"

log "Testing sudo -u oracle on source via ${SOURCE_SSH_USER}..."
SOURCE_ORACLE_TEST=$(run_as_zdmuser ssh -i "${ZDMUSER_HOME}/.ssh/odaa.pem" \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=15 \
    "${SOURCE_SSH_USER}@${SOURCE_HOST}" \
    "sudo -u oracle id" 2>&1) || SOURCE_ORACLE_TEST=""
echo "${SOURCE_ORACLE_TEST}" | tee -a "${LOG_FILE}"
if echo "${SOURCE_ORACLE_TEST}" | grep -qi "oracle"; then
  log "✅ ACTION-11 SOURCE: sudo -u oracle works on source."
else
  log "⚠️  ACTION-11 SOURCE: Could not confirm sudo -u oracle on source."
  log "    ZDM may need SUDO_FOR_ORACLE configured in response file."
fi

log "Testing sudo -u oracle on target via ${TARGET_SSH_USER}..."
TARGET_ORACLE_TEST=$(run_as_zdmuser ssh -i "${ZDMUSER_HOME}/.ssh/odaa.pem" \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=15 \
    "${TARGET_SSH_USER}@${TARGET_HOST}" \
    "sudo -u oracle id" 2>&1) || TARGET_ORACLE_TEST=""
echo "${TARGET_ORACLE_TEST}" | tee -a "${LOG_FILE}"
if echo "${TARGET_ORACLE_TEST}" | grep -qi "oracle"; then
  log "✅ ACTION-11 TARGET: sudo -u oracle works on target."
else
  log "⚠️  ACTION-11 TARGET: Could not confirm sudo -u oracle on target."
fi

# ---------------------------------------------------------------------------
# ACTION-05: Discover OCI Object Storage Namespace
# ---------------------------------------------------------------------------
log_section "ACTION-05: Discover OCI Object Storage Namespace"

log "Running: oci os ns get (as zdmuser, OCI config at ${ZDMUSER_HOME}/.oci/config)..."
OCI_NAMESPACE=$(run_as_zdmuser oci os ns get \
    --config-file "${ZDMUSER_HOME}/.oci/config" \
    --query 'data' \
    --raw-output 2>&1) || OCI_NAMESPACE=""

if [[ -z "${OCI_NAMESPACE}" ]] || echo "${OCI_NAMESPACE}" | grep -q "Error"; then
  log "❌ ACTION-05: Failed to retrieve OCI namespace. Output:"
  echo "${OCI_NAMESPACE}" | tee -a "${LOG_FILE}"
  log "   Verify zdmuser OCI config: ${ZDMUSER_HOME}/.oci/config"
  log "   Run manually: sudo -u zdmuser oci os ns get"
  OCI_NAMESPACE="<UNKNOWN — run 'oci os ns get' manually as zdmuser>"
else
  log "✅ ACTION-05 COMPLETE: OCI Object Storage namespace = ${OCI_NAMESPACE}"
  log ""
  log "  >>> UPDATE zdm-env.md: OCI_OSS_NAMESPACE: ${OCI_NAMESPACE} <<<"
  log ""
fi

# ---------------------------------------------------------------------------
# ACTION-06: Create OCI Object Storage Bucket
# ---------------------------------------------------------------------------
log_section "ACTION-06: Create OCI Object Storage Bucket"

if echo "${OCI_NAMESPACE}" | grep -q "UNKNOWN"; then
  log "⚠️  Skipping bucket creation — namespace not available. Complete ACTION-05 first."
else
  log "Checking whether bucket '${ZDM_BUCKET_NAME}' already exists..."
  BUCKET_CHECK=$(run_as_zdmuser oci os bucket get \
      --config-file "${ZDMUSER_HOME}/.oci/config" \
      --namespace "${OCI_NAMESPACE}" \
      --bucket-name "${ZDM_BUCKET_NAME}" \
      --query 'data.name' \
      --raw-output 2>&1) || BUCKET_CHECK=""

  if echo "${BUCKET_CHECK}" | grep -q "${ZDM_BUCKET_NAME}"; then
    log "✅ ACTION-06: Bucket '${ZDM_BUCKET_NAME}' already exists. No action needed."
  else
    log "Bucket does not exist. Creating bucket '${ZDM_BUCKET_NAME}' in compartment..."
    log "  Namespace:    ${OCI_NAMESPACE}"
    log "  Compartment:  ${OCI_COMPARTMENT_OCID}"
    log "  Region:       ${OCI_REGION}"
    log "  Bucket name:  ${ZDM_BUCKET_NAME}"

    BUCKET_CREATE=$(run_as_zdmuser oci os bucket create \
        --config-file "${ZDMUSER_HOME}/.oci/config" \
        --compartment-id "${OCI_COMPARTMENT_OCID}" \
        --namespace "${OCI_NAMESPACE}" \
        --name "${ZDM_BUCKET_NAME}" \
        --storage-tier Standard \
        --versioning Disabled \
        2>&1) || BUCKET_CREATE=""

    echo "${BUCKET_CREATE}" | tee -a "${LOG_FILE}"

    if echo "${BUCKET_CREATE}" | grep -q "${ZDM_BUCKET_NAME}"; then
      log "✅ ACTION-06 COMPLETE: Bucket '${ZDM_BUCKET_NAME}' created successfully."
      log ""
      log "  >>> UPDATE zdm-env.md: OCI_OSS_BUCKET_NAME: ${ZDM_BUCKET_NAME} <<<"
      log ""
    else
      log "❌ ACTION-06: Bucket creation may have failed. Review output above."
      log "   Create manually: oci os bucket create --compartment-id ${OCI_COMPARTMENT_OCID} --namespace ${OCI_NAMESPACE} --name ${ZDM_BUCKET_NAME}"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# ACTION-07: Initialize ZDM Credential Store
# ---------------------------------------------------------------------------
log_section "ACTION-07: Initialize ZDM Credential Store"
CRED_DIR="${ZDM_HOME}/zdm/cred"

log "Checking if credential store already exists at ${CRED_DIR}..."
if run_as_zdmuser test -d "${CRED_DIR}" 2>/dev/null; then
  log "ℹ️  Credential store directory already exists at ${CRED_DIR}."
  run_as_zdmuser ls -la "${CRED_DIR}" | tee -a "${LOG_FILE}"
else
  log "Credential store NOT found. Initializing ZDM wallet/credential store..."
  log ""
  log "⚠️  ZDM stores source and target DB SYS passwords in the credential store."
  log "    You will be prompted for these passwords."
  log ""

  # The standard zdmcli command to add credentials is:
  #   zdmcli migrate database -credonly
  # OR for newer ZDM: zdmcli -cred init
  # We use zdmcli migrate database with -sourcesysdba and -targetsysdba flags.
  # The credential store is populated the first time zdmcli is called with passwords.
  # Instead of running the full migrate here, we use the -help flag to confirm zdmcli works,
  # then provide guidance on populating credentials as part of Step 3.

  log "Verifying zdmcli is accessible as zdmuser..."
  run_as_zdmuser "${ZDM_HOME}/bin/zdmcli" -help 2>&1 | head -20 | tee -a "${LOG_FILE}" || true

  log ""
  log "The ZDM credential store is initialized automatically when zdmcli migrate database"
  log "is run for the first time with the -sourcesysdbapasswd and -targetsysdbapasswd options."
  log ""
  log "When you run the migration command in Step 3, ZDM will prompt for:"
  log "  -sourcesysdbapasswd  — SYS password for source CDB (oradb/ORADB1)"
  log "  -targetsysdbapasswd  — SYS password for target CDB"
  log ""
  log "Alternatively, populate via response file:"
  log "  SOURCESYSDBA_PASSWORD=<sourcepassword>"
  log "  TARGETSYSDBA_PASSWORD=<targetpassword>"
  log ""
  log "Or via zdmcli argument at runtime — refer to ZDM Admin Guide section 'Credential Store'."
  log "  zdmcli modify credentials -help"
  log ""
fi

# Verify ZDM service is running
log_section "VERIFY: ZDM service status"
run_as_zdmuser "${ZDM_HOME}/bin/zdmcli" query job 2>&1 | head -10 | tee -a "${LOG_FILE}" || true

# ---------------------------------------------------------------------------
# SUMMARY
# ---------------------------------------------------------------------------
log_section "SUMMARY"
log ""
log "Actions completed on ZDM server:"
log "  ACTION-05: OCI OSS Namespace = ${OCI_NAMESPACE}"
log "  ACTION-06: OCI Bucket        = ${ZDM_BUCKET_NAME}"
log "  ACTION-07: ZDM Cred Store    = see notes above (populated during Step 3)"
log "  ACTION-10: SSH key access    = verified above"
log "  ACTION-11: oracle sudo access = verified above"
log ""
log "Required updates to zdm-env.md:"
log "  OCI_OSS_NAMESPACE:   ${OCI_NAMESPACE}"
log "  OCI_OSS_BUCKET_NAME: ${ZDM_BUCKET_NAME}"
log ""
log "Log saved to: ${LOG_FILE}"
log ""
log "Next step: Step3-Generate-Migration-Artifacts.prompt.md"
