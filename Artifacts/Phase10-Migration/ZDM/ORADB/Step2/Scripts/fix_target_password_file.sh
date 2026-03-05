#!/usr/bin/env bash
# =============================================================================
# fix_target_password_file.sh
# Purpose : Create the Oracle password file on the ODAA target node
#           (tmodaauks-rqahk1 / 10.0.1.160) to allow SYS authentication
#           required by ZDM ONLINE_PHYSICAL migration.
# Run as  : zdmuser on the ZDM server (tm-vm-odaa-oracle-jumpbox / 10.1.0.8)
# Step    : ZDM Migration Step 2 — Fix Issues
# Issue   : Issue 2 (Password file missing on ODAA target)
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
TARGET_HOST="10.0.1.160"
TARGET_SSH_USER="opc"
TARGET_SSH_KEY="${HOME}/.ssh/odaa.pem"
ORACLE_USER="oracle"

# Target Oracle config — confirm dbhome path before running
# (Issue 8: dbhome_1 or dbhome_2 must be confirmed)
TARGET_ORACLE_HOME_BASE="/u02/app/oracle/product/19.0.0.0"
TARGET_DB_UNIQUE_NAME="oradb01"
TARGET_INSTANCE_NAME="oradb011"

LOG_DIR="${HOME}/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/fix_target_password_file_$(date +%Y%m%d_%H%M%S).log"

# =============================================================================
# Logging helpers
# =============================================================================
log()  { echo "[$(date '+%H:%M:%S')] $*" | tee -a "${LOG_FILE}"; }
pass() { echo "[$(date '+%H:%M:%S')] ✅ PASS  $*" | tee -a "${LOG_FILE}"; }
fail() { echo "[$(date '+%H:%M:%S')] ❌ FAIL  $*" | tee -a "${LOG_FILE}"; }
warn() { echo "[$(date '+%H:%M:%S')] ⚠️  WARN  $*" | tee -a "${LOG_FILE}"; }
info() { echo "[$(date '+%H:%M:%S')] ℹ️  INFO  $*" | tee -a "${LOG_FILE}"; }

log "================================================================"
log "fix_target_password_file.sh — Create Password File on ODAA Target"
log "Running as: $(whoami)  on  $(hostname)"
log "Log: ${LOG_FILE}"
log "================================================================"

# =============================================================================
# Step 1: Prompt for Oracle Home path (dbhome_1 or dbhome_2)
# =============================================================================
log ""
log "--- Step 1: Confirm Target Oracle Home Path ---"
log "Prior successful EVAL jobs used dbhome_1. Recent ORADB jobs used dbhome_2."
log "Run the following to check which home contains the active instance:"
log "  ssh -i ${TARGET_SSH_KEY} ${TARGET_SSH_USER}@${TARGET_HOST} \"sudo -u ${ORACLE_USER} bash -c 'cat /etc/oratab | grep oradb'\""
echo ""
echo "Enter Oracle Home suffix [1 or 2] (default: 1):"
read -r DBHOME_SUFFIX
DBHOME_SUFFIX="${DBHOME_SUFFIX:-1}"

if [[ "${DBHOME_SUFFIX}" != "1" && "${DBHOME_SUFFIX}" != "2" ]]; then
  fail "Invalid input '${DBHOME_SUFFIX}'. Must be 1 or 2. Exiting."
  exit 1
fi

TARGET_ORACLE_HOME="${TARGET_ORACLE_HOME_BASE}/dbhome_${DBHOME_SUFFIX}"
TARGET_PWFILE_PATH="${TARGET_ORACLE_HOME}/dbs/orapw${TARGET_DB_UNIQUE_NAME}"
info "Using Oracle Home: ${TARGET_ORACLE_HOME}"
info "Password file will be created at: ${TARGET_PWFILE_PATH}"

# =============================================================================
# Step 2: Test SSH connectivity to target
# =============================================================================
log ""
log "--- Step 2: Test SSH connectivity to target (${TARGET_HOST}) ---"
if ! ssh -i "${TARGET_SSH_KEY}" \
         -o StrictHostKeyChecking=no \
         -o ConnectTimeout=10 \
         "${TARGET_SSH_USER}@${TARGET_HOST}" \
         "sudo -u ${ORACLE_USER} whoami" 2>>"${LOG_FILE}" | grep -q "^oracle$"; then
  fail "Cannot connect to ${TARGET_SSH_USER}@${TARGET_HOST} via ${TARGET_SSH_KEY} and sudo to ${ORACLE_USER}."
  fail "Verify SSH key and sudo permissions before re-running."
  exit 1
fi
pass "SSH connectivity to target confirmed — oracle user accessible."

# =============================================================================
# Step 3: Check if password file already exists
# =============================================================================
log ""
log "--- Step 3: Check for existing password file ---"
PWFILE_EXISTS=$(ssh -i "${TARGET_SSH_KEY}" \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=10 \
    "${TARGET_SSH_USER}@${TARGET_HOST}" \
    "sudo -u ${ORACLE_USER} bash -c 'test -f ${TARGET_PWFILE_PATH} && echo yes || echo no'" 2>>"${LOG_FILE}")

if [[ "${PWFILE_EXISTS}" == "yes" ]]; then
  warn "Password file already exists at ${TARGET_PWFILE_PATH} on target."
  warn "If you want to regenerate it (e.g. to change SYS password), continue."
  warn "If the existing file is correct, exit now (Ctrl+C)."
  echo ""
  echo "Press Enter to continue and overwrite, or Ctrl+C to abort:"
  read -r
fi

# =============================================================================
# Step 4: Prompt for SYS password
# =============================================================================
log ""
log "--- Step 4: Enter SYS password for the target database password file ---"
echo "Enter the SYS password for the target database (will NOT be logged):"
read -rs SYS_PASSWORD
echo ""
echo "Confirm SYS password:"
read -rs SYS_PASSWORD_CONFIRM
echo ""

if [[ "${SYS_PASSWORD}" != "${SYS_PASSWORD_CONFIRM}" ]]; then
  fail "Passwords do not match. Aborting."
  exit 1
fi

if [[ ${#SYS_PASSWORD} -lt 8 ]]; then
  fail "Password must be at least 8 characters. Aborting."
  exit 1
fi

# =============================================================================
# Step 5: Create the password file on the target via SSH
#         Uses base64 encoding to safely pass the password through SSH layers.
# =============================================================================
log ""
log "--- Step 5: Create password file on target ---"

ENCODED_PW=$(printf '%s' "${SYS_PASSWORD}" | base64 -w 0)

ORAPWD_RESULT=$(ssh -i "${TARGET_SSH_KEY}" \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=10 \
    "${TARGET_SSH_USER}@${TARGET_HOST}" \
    "sudo -u ${ORACLE_USER} bash -c '
      export ORACLE_HOME=${TARGET_ORACLE_HOME}
      export PATH=\${ORACLE_HOME}/bin:\${PATH}
      DECODED_PW=\$(echo \"${ENCODED_PW}\" | base64 -d)
      orapwd file=${TARGET_PWFILE_PATH} password=\"\${DECODED_PW}\" entries=20 force=y
      echo ORAPWD_RC=\$?
    '" 2>&1)

log "orapwd output: ${ORAPWD_RESULT}"

if echo "${ORAPWD_RESULT}" | grep -q "ORAPWD_RC=0"; then
  pass "Password file created successfully at ${TARGET_PWFILE_PATH}"
else
  fail "orapwd command failed. Output:"
  fail "${ORAPWD_RESULT}"
  exit 1
fi

# =============================================================================
# Step 6: Verify the password file was created with correct permissions
# =============================================================================
log ""
log "--- Step 6: Verify password file on target ---"
PWFILE_STAT=$(ssh -i "${TARGET_SSH_KEY}" \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=10 \
    "${TARGET_SSH_USER}@${TARGET_HOST}" \
    "sudo -u ${ORACLE_USER} bash -c 'ls -la ${TARGET_PWFILE_PATH}'" 2>&1)

log "File stat: ${PWFILE_STAT}"

if echo "${PWFILE_STAT}" | grep -q "orapw${TARGET_DB_UNIQUE_NAME}"; then
  pass "Password file verified: ${PWFILE_STAT}"
else
  fail "Password file not found after creation. Check Oracle Home path."
  exit 1
fi

# =============================================================================
# Summary
# =============================================================================
log ""
log "================================================================"
log "SUMMARY"
log "================================================================"
pass "Issue 2 RESOLVED: Password file created at ${TARGET_PWFILE_PATH} on ${TARGET_HOST}"
log ""
log "Next steps:"
log "  1. Record the SYS password securely — needed for ZDM -srcpdb and -tgtpdb parameters."
log "  2. Confirm Oracle Home path is correct:"
log "       ${TARGET_ORACLE_HOME}"
log "     Update zdm-env.md TARGET_REMOTE_ORACLE_HOME if needed."
log "  3. Run verify_fixes.sh to confirm all blocker checks pass."
log ""
log "fix_target_password_file.sh completed. Log: ${LOG_FILE}"
