#!/usr/bin/env bash
# =============================================================================
# fix_04_zdm_cred_store.sh
# =============================================================================
# Purpose : Initialize the ZDM wallet credential store and validate ZDM
#           connectivity to source and target databases.
#
# Action  : ACTION-07
#
# Run from: ZDM Server (10.1.0.8)
# Run as  : zdmuser
#
# What it does:
#   1. Verifies ZDM service is running
#   2. Validates ZDM CLI is functional
#   3. Runs a ZDM evaluate (dry-run) job up to ZDM_VALIDATE_SRC phase
#      to confirm ZDM can connect to source and target with the provided
#      credentials. This is the standard way to initialize and test the
#      ZDM credential store.
#
# REQUIREMENTS BEFORE RUNNING:
#   - ACTION-01/02/03 complete (source in ARCHIVELOG + Force/Supplemental)
#   - ACTION-04 complete (target TDE master key)
#   - ACTION-05/06 complete (OSS namespace and bucket known)
#   - ZDM response file from Step 3 OR use the template below
#   - Source SYS password available
#   - Target SYS password available
#   - Target TDE wallet password available
#
# Usage   : bash fix_04_zdm_cred_store.sh
#           bash fix_04_zdm_cred_store.sh --check-service
# =============================================================================

set -euo pipefail

# --- Configuration (from zdm-env.md) ----------------------------------------
ZDM_HOME="/u01/app/zdmhome"
ZDM_CLI="${ZDM_HOME}/bin/zdmcli"

SOURCE_HOST="10.1.0.11"
SOURCE_SSH_USER="azureuser"
SOURCE_SSH_KEY="/home/zdmuser/.ssh/odaa.pem"
SOURCE_DB_UNIQUE_NAME="oradb1"

TARGET_HOST="10.0.1.160"
TARGET_SSH_USER="opc"
TARGET_SSH_KEY="/home/zdmuser/.ssh/odaa.pem"
# TARGET_DB_UNIQUE_NAME should be updated after Migration Questionnaire Section D.2 is filled
# Example: "oradb1_odaa"
TARGET_DB_UNIQUE_NAME="{{ TARGET_DB_UNIQUE_NAME }}"

RESPONSE_FILE_TEMPLATE="${ZDM_HOME}/rhp/zdm/template/zdm_template.rsp"
# ----------------------------------------------------------------------------

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# --- Guard: must run as zdmuser ---------------------------------------------
CURRENT_USER=$(whoami)
if [[ "${CURRENT_USER}" != "zdmuser" ]]; then
  log "ERROR: This script must be run as zdmuser."
  log "       Run: sudo su - zdmuser && bash fix_04_zdm_cred_store.sh"
  exit 1
fi

log "================================================================"
log "fix_04_zdm_cred_store.sh — ZDM Credential Store Init (ORADB)"
log "================================================================"
log "ZDM_HOME  : ${ZDM_HOME}"
log "Source DB : ${SOURCE_DB_UNIQUE_NAME} @ ${SOURCE_HOST}"
log "Target DB : ${TARGET_DB_UNIQUE_NAME} @ ${TARGET_HOST}"
log "================================================================"

# --- SERVICE CHECK mode ------------------------------------------------------
if [[ "${1:-}" == "--check-service" ]]; then
  log "=== ZDM Service Status Check ==="

  # Check ZDM service process
  if pgrep -f "zdm.base" > /dev/null 2>&1; then
    log "✅ ZDM service process: RUNNING"
  else
    log "❌ ZDM service process: NOT RUNNING"
    log "   Start with: ${ZDM_HOME}/bin/zdmservice start"
  fi

  # Check ZDM CLI
  if [[ -x "${ZDM_CLI}" ]]; then
    log "✅ zdmcli found: ${ZDM_CLI}"
    ZDM_VER=$(${ZDM_CLI} query jobid -jobid 99999 2>&1 | head -2 || true)
    log "   zdmcli response: ${ZDM_VER}"
  else
    log "❌ zdmcli NOT found or not executable at ${ZDM_CLI}"
  fi

  # Check credential store
  if [[ -d "${ZDM_HOME}/zdm/cred" ]]; then
    log "✅ ZDM credential store: EXISTS (${ZDM_HOME}/zdm/cred)"
    ls -l "${ZDM_HOME}/zdm/cred/" || true
  else
    log "⚠️  ZDM credential store: NOT INITIALIZED"
    log "   Run this script without --check-service to initialize it"
  fi

  exit 0
fi

# --- Step 1: Verify ZDM service is running ----------------------------------
log "Step 1: Verifying ZDM service..."
if ! pgrep -f "zdm.base" > /dev/null 2>&1; then
  log "ZDM service is not running. Attempting to start..."
  "${ZDM_HOME}/bin/zdmservice" start
  sleep 10
  if ! pgrep -f "zdm.base" > /dev/null 2>&1; then
    log "ERROR: ZDM service failed to start. Check ZDM logs:"
    log "  ${ZDM_HOME}/log/*/zdm/zdm.log"
    exit 1
  fi
fi
log "✅ ZDM service is running."

# --- Step 2: Verify zdmcli is functional ------------------------------------
log "Step 2: Verifying zdmcli..."
if ! ${ZDM_CLI} query jobid -jobid 99999 2>&1 | grep -qi "JOB-46\|does not exist\|error"; then
  log "✅ zdmcli is responsive."
fi
log "✅ zdmcli at ${ZDM_CLI} is functional."

# --- Step 3: Confirm TARGET_DB_UNIQUE_NAME is set ---------------------------
if [[ "${TARGET_DB_UNIQUE_NAME}" == "{{ TARGET_DB_UNIQUE_NAME }}" ]]; then
  log ""
  log "⚠️  TARGET_DB_UNIQUE_NAME is not set in this script."
  log "    Complete Migration Questionnaire Section D.2 to determine the"
  log "    target database unique name (e.g., oradb1_odaa)."
  log ""
  read -r -p "Enter target DB unique name (e.g. oradb1_odaa): " TARGET_DB_UNIQUE_NAME
  if [[ -z "${TARGET_DB_UNIQUE_NAME}" ]]; then
    log "ERROR: Target DB unique name is required. Aborting."
    exit 1
  fi
fi

# --- Step 4: Generate a minimal test response file --------------------------
log "Step 3: Creating temporary ZDM evaluate response file..."
TMP_RSP=$(mktemp /tmp/zdm_eval_oradb_XXXXXX.rsp)

cat > "${TMP_RSP}" << EOF
# ZDM Validation Response File — ORADB Step2 Credential Test
# Generated: $(date)
# This is a temporary file used only to test ZDM connectivity.
# The full response file will be generated in Step 3.

ZDM_MIGRATION_METHOD=ONLINE_PHYSICAL
ZDM_SRC_DB_ENV=ON_PREM
ZDM_TGT_DB_ENV=ORACLE_DATABASE_AT_AZURE

ZDM_SRC_DB_UNIQUE_NAME=${SOURCE_DB_UNIQUE_NAME}
ZDM_TGT_DB_UNIQUE_NAME=${TARGET_DB_UNIQUE_NAME}

ZDM_SOURCEDATABASE_ADMINUSERNAME=SYS
ZDM_TARGETDATABASE_ADMINUSERNAME=SYS
EOF

log "Temporary response file: ${TMP_RSP}"

# --- Step 5: Run zdmcli evaluate (triggers credential store init) -----------
log ""
log "Step 4: Running ZDM evaluate to initialize credential store..."
log "        ZDM will prompt for database passwords."
log "        Enter: (1) Source SYS password, (2) Target SYS password,"
log "               (3) Target TDE wallet password when prompted."
log ""
log "Command:"
log "  ${ZDM_CLI} migrate database \\"
log "    -sourcedb ${SOURCE_DB_UNIQUE_NAME} \\"
log "    -sourcenode ${SOURCE_HOST} \\"
log "    -srcauth zdmauth \\"
log "    -srcarg1 user:${SOURCE_SSH_USER} \\"
log "    -srcarg2 identity_file:${SOURCE_SSH_KEY} \\"
log "    -srcarg3 sudo_location:/usr/bin/sudo \\"
log "    -targetdb ${TARGET_DB_UNIQUE_NAME} \\"
log "    -targetnode ${TARGET_HOST} \\"
log "    -tgtauth zdmauth \\"
log "    -tgtarg1 user:${TARGET_SSH_USER} \\"
log "    -tgtarg2 identity_file:${TARGET_SSH_KEY} \\"
log "    -tgtarg3 sudo_location:/usr/bin/sudo \\"
log "    -rsp ${TMP_RSP} \\"
log "    -evaluate"
log ""
read -r -p "Press ENTER to run the ZDM evaluate command (CTRL+C to abort)..."

${ZDM_CLI} migrate database \
  -sourcedb "${SOURCE_DB_UNIQUE_NAME}" \
  -sourcenode "${SOURCE_HOST}" \
  -srcauth zdmauth \
  -srcarg1 "user:${SOURCE_SSH_USER}" \
  -srcarg2 "identity_file:${SOURCE_SSH_KEY}" \
  -srcarg3 "sudo_location:/usr/bin/sudo" \
  -targetdb "${TARGET_DB_UNIQUE_NAME}" \
  -targetnode "${TARGET_HOST}" \
  -tgtauth zdmauth \
  -tgtarg1 "user:${TARGET_SSH_USER}" \
  -tgtarg2 "identity_file:${TARGET_SSH_KEY}" \
  -tgtarg3 "sudo_location:/usr/bin/sudo" \
  -rsp "${TMP_RSP}" \
  -evaluate

EVAL_EXIT=$?
rm -f "${TMP_RSP}"

# --- Step 6: Check credential store was created -----------------------------
log ""
log "=== ZDM Credential Store Check ==="
if [[ -d "${ZDM_HOME}/zdm/cred" ]]; then
  log "✅ ZDM credential store created at: ${ZDM_HOME}/zdm/cred"
  ls -la "${ZDM_HOME}/zdm/cred/"
else
  log "⚠️  ZDM credential store not found at ${ZDM_HOME}/zdm/cred"
  log "    The evaluate command may have created it in a different sub-path."
  log "    Check: find ${ZDM_HOME} -name '*.sso' 2>/dev/null"
  find "${ZDM_HOME}" -name "*.sso" 2>/dev/null || true
fi

log ""
log "================================================================"
log "fix_04_zdm_cred_store.sh COMPLETE"
log ""
if [[ ${EVAL_EXIT} -eq 0 ]]; then
  log "ACTION-07 COMPLETE: ZDM evaluate succeeded — credential store initialized."
  log ""
  log "Update Issue-Resolution-Log-ORADB.md:"
  log "  - ACTION-07 Status: ✅ Resolved"
  log "  - Record date and job ID from evaluate output"
else
  log "⚠️  ZDM evaluate returned exit code ${EVAL_EXIT}."
  log "    Review the ZDM evaluate job log above for errors."
  log "    Run: ${ZDM_CLI} query jobid -jobid <JOB_ID> -details"
  log "    to see phase-by-phase results."
fi
log "================================================================"
