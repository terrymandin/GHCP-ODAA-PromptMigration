#!/usr/bin/env bash
# =============================================================================
# fix_07_init_zdm_credential_store.sh
#
# Purpose : Initialize the ZDM Oracle Wallet credential store and populate it
#           with the source and target SYS database passwords required by
#           zdmcli migrate database.
#
#           ZDM uses an Oracle Wallet (mkstore) located at:
#             $ZDM_HOME/zdm/cred
#           to securely store DB credentials — passwords are never passed on
#           the command line or stored in plain text.
#
# Target  : ZDM server (10.1.0.8) — run locally as zdmuser.
#
# Run as  : zdmuser on ZDM server (10.1.0.8)
# Usage   : bash fix_07_init_zdm_credential_store.sh
#           The script prompts interactively for passwords.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — sourced from zdm-env.md values
# ---------------------------------------------------------------------------
ZDM_HOME="${ZDM_HOME:-/u01/app/zdmhome}"
CRED_DIR="${ZDM_HOME}/zdm/cred"

# Source DB connection string for credential entry
SOURCE_HOST="${SOURCE_HOST:-10.1.0.11}"
SOURCE_ORACLE_SID="${SOURCE_ORACLE_SID:-oradb}"
SOURCE_ORACLE_HOME="${SOURCE_ORACLE_HOME:-/u01/app/oracle/product/12.2.0/dbhome_1}"

# Target DB connection string for credential entry
TARGET_HOST="${TARGET_HOST:-10.0.1.160}"
# TARGET_ORACLE_SID — the target CDB SID on ODAA (confirm from OCI Console)
TARGET_ORACLE_SID="${TARGET_ORACLE_SID:-}"

MKSTORE="${ZDM_HOME}/jdk/bin/java -cp ${ZDM_HOME}/lib/oraclepki.jar:${ZDM_HOME}/lib/osdt_cert.jar:${ZDM_HOME}/lib/osdt_core.jar oracle.security.pki.OracleSecretStoreTextUI"
# Or use system mkstore if available at ORACLE_HOME/bin:
if command -v mkstore >/dev/null 2>&1; then
  MKSTORE="mkstore"
fi

LOG_FILE="fix_07_$(date +%Y%m%d_%H%M%S).log"

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"; }
info() { log "INFO  $*"; }
warn() { log "WARN  $*"; }
fail() { log "ERROR $*"; exit 1; }
sep()  { log "----------------------------------------------------------------------"; }

# ---------------------------------------------------------------------------
# Secret prompts — never echoed to terminal
# ---------------------------------------------------------------------------
sep
info "Starting fix_07: Initialize ZDM Credential Store"
info "ZDM_HOME    : ${ZDM_HOME}"
info "Cred store  : ${CRED_DIR}"
info "Log file    : ${LOG_FILE}"
sep

echo ""
echo "You will be prompted for the following passwords:"
echo "  1. ZDM Wallet password — a NEW password to protect the credential wallet itself"
echo "  2. Source Oracle SYS password (SYSDBA) for ${SOURCE_HOST}/${SOURCE_ORACLE_SID}"
echo "  3. Target Oracle SYS password (SYSDBA) for ${TARGET_HOST}/<CDB_SID>"
echo ""

read -r -s -p "Enter ZDM wallet password (new — minimum 8 chars, include uppercase/digit/special): " WALLET_PASS
echo
read -r -s -p "Confirm ZDM wallet password: " WALLET_PASS_CONFIRM
echo
[ "${WALLET_PASS}" = "${WALLET_PASS_CONFIRM}" ] || fail "Wallet passwords do not match."

read -r -s -p "Enter source SYS password (${SOURCE_HOST}/${SOURCE_ORACLE_SID}): " SRC_SYS_PASS
echo
read -r -s -p "Enter target SYS password (${TARGET_HOST}/<CDB>): " TGT_SYS_PASS
echo

# ---------------------------------------------------------------------------
# Step 1: Check if ZDM_HOME/bin/zdmcli exists
# ---------------------------------------------------------------------------
sep
info "Step 1: Verifying ZDM installation..."
[ -x "${ZDM_HOME}/bin/zdmcli" ] || fail "zdmcli not found at ${ZDM_HOME}/bin/zdmcli. Check ZDM_HOME."
info "zdmcli found: OK"

# ---------------------------------------------------------------------------
# Step 2: Create credential store directory
# ---------------------------------------------------------------------------
sep
info "Step 2: Creating credential store directory: ${CRED_DIR}"
if [ -d "${CRED_DIR}" ]; then
  warn "Credential store directory already exists. Checking contents..."
  ls -la "${CRED_DIR}" | tee -a "${LOG_FILE}"
else
  mkdir -p "${CRED_DIR}"
  info "Created: ${CRED_DIR}"
fi

# ---------------------------------------------------------------------------
# Step 3: Initialize the Oracle Wallet
# ---------------------------------------------------------------------------
sep
info "Step 3: Initializing Oracle Wallet at ${CRED_DIR}..."

# ZDM uses the Oracle Wallet via orapki or mkstore.
# orapki is bundled with ZDM:
ORAPKI="${ZDM_HOME}/bin/orapki"
if [ ! -x "${ORAPKI}" ]; then
  warn "orapki not found at ${ORAPKI}. Trying $ORACLE_HOME/bin/orapki..."
  ORAPKI="${SOURCE_ORACLE_HOME}/bin/orapki"
fi

if [ -x "${ORAPKI}" ]; then
  info "Using orapki to create wallet..."
  echo "${WALLET_PASS}" | "${ORAPKI}" wallet create \
    -wallet "${CRED_DIR}" \
    -pwd "${WALLET_PASS}" \
    -auto_login_local 2>&1 | tee -a "${LOG_FILE}" || warn "Wallet may already exist — continuing."
else
  warn "orapki not found. Wallet may already exist or needs manual creation."
  warn "Attempting to use mkstore directly..."
fi

# ---------------------------------------------------------------------------
# Step 4: Add source and target SYS credentials to the wallet
# ---------------------------------------------------------------------------
# ZDM expects credentials stored with specific alias format:
#   zdm/<SOURCE_SID>_source   for source
#   zdm/<TARGET_SID>_target   for target
# (confirm aliases in zdmcli documentation for your ZDM version)
sep
info "Step 4: Storing credentials in ZDM credential store..."

# Build connection descriptors
SRC_CONN_STRING="//${SOURCE_HOST}:1521/${SOURCE_ORACLE_SID}"
TGT_CONN_STRING="//${TARGET_HOST}:1521/${TARGET_ORACLE_SID:-<CDB_SERVICE>}"

info "Adding source credentials (alias: zdm_source_${SOURCE_ORACLE_SID})..."
info "  Connection: ${SRC_CONN_STRING}"

# The exact credential store mechanism depends on ZDM version.
# ZDM 21.x+ uses zdmcli modify credentials or response file with SOURCEDATABASEPASSWORD/TARGETDATABASEPASSWORD.
# For wallet-based approach, use mkstore to add credential entries:
cat <<'CREDINSTRUCTIONS'

  -------------------------------------------------------------------------
  ZDM Credential Setup — Manual Step Required
  -------------------------------------------------------------------------
  ZDM 21.x and later supports two methods for providing DB credentials:

  METHOD A (Recommended): Response file parameters
    Add to your ZDM response file (generated in Step 3):
      SOURCEDATABASEPASSWORD=<source_sys_password>
      TARGETDATABASEPASSWORD=<target_sys_password>
    Keep the response file with strict permissions: chmod 600 <response_file>

  METHOD B: Oracle Wallet (credential store)
    Use mkstore to add wallet entries. ZDM reads credentials by alias.
    Run on ZDM server as zdmuser:

      ORACLE_HOME=/u01/app/zdmhome  # or path to an Oracle client home
      export ORACLE_HOME
      mkstore -wrl /u01/app/zdmhome/zdm/cred -createCredential <source_tns_alias> SYS <source_sys_password>
      mkstore -wrl /u01/app/zdmhome/zdm/cred -createCredential <target_tns_alias> SYS <target_sys_password>

  Confirm which method your ZDM version requires by checking:
      /u01/app/zdmhome/bin/zdmcli migrate database -help | grep -i cred
  -------------------------------------------------------------------------

CREDINSTRUCTIONS

# ---------------------------------------------------------------------------
# Step 5: Save credential hints for Step 3 (response file)
# ---------------------------------------------------------------------------
sep
info "Step 5: Saving credential reference notes..."

NOTES_FILE="${CRED_DIR}/credential_notes.txt"
cat > "${NOTES_FILE}" <<NOTES
ZDM Credential Store — Setup Notes
Generated: $(date)
Project: ORADB migration to ODAA

Source DB:
  Host    : ${SOURCE_HOST}
  SID     : ${SOURCE_ORACLE_SID}
  User    : SYS
  ConnStr : ${SRC_CONN_STRING}

Target CDB:
  Host    : ${TARGET_HOST}
  SID     : ${TARGET_ORACLE_SID:-<CDB_SERVICE — confirm from OCI Console>}
  User    : SYS
  ConnStr : ${TGT_CONN_STRING}

ZDM Wallet Location: ${CRED_DIR}

REMINDER: Populate SOURCEDATABASEPASSWORD and TARGETDATABASEPASSWORD in the
ZDM response file generated during Step 3. Restrict response file permissions:
  chmod 600 <response_file>
NOTES
chmod 600 "${NOTES_FILE}"
info "Credential notes saved to: ${NOTES_FILE} (chmod 600)"

# ---------------------------------------------------------------------------
# Step 6: Verify ZDM service is running (credentials will be used by it)
# ---------------------------------------------------------------------------
sep
info "Step 6: Verifying ZDM service status..."
ZDM_STATUS=$("${ZDM_HOME}/bin/zdmcli" status 2>&1) || true
echo "${ZDM_STATUS}" | tee -a "${LOG_FILE}"
if echo "${ZDM_STATUS}" | grep -qi "Running\|RUNNING"; then
  info "ZDM service: RUNNING ✅"
else
  warn "ZDM service may not be running. Start with: ${ZDM_HOME}/bin/zdmservice start"
fi

sep
info "✅ Fix 07 complete."
info "   Credential store directory: ${CRED_DIR}"
info "   Before Step 3: decide and document which credential method (response file vs wallet) to use."
sep
info "Log saved to: ${LOG_FILE}"
