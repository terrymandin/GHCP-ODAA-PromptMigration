#!/bin/bash
# =============================================================================
# ZDM CLI Commands Script
# Database:       ORADB
# Project:        ORADB1 (Oracle 12.2.0.1 CDB, Azure IaaS) → oradb01 (Oracle 19c ExaDB-D, ODAA)
# Generated:      2026-03-05
# =============================================================================
#
# ============================================================
# IMPORTANT: LOGIN AND SETUP INSTRUCTIONS
# ============================================================
#
# 1. SSH to ZDM server as ZDM_ADMIN_USER (azureuser):
#      ssh -i ~/.ssh/zdm.pem azureuser@10.1.0.8
#
# 2. Switch to zdmuser (all ZDM operations run as zdmuser):
#      sudo su - zdmuser
#
# 3. Clone your fork of the migration repository (first time):
#      cd ~
#      git clone <your-fork-url>
#      cd GHCP-ODAA-PromptMigration/Artifacts/Phase10-Migration/ZDM/ORADB/Step3
#
# 4. Run init command (FIRST TIME ONLY — creates ~/creds and ~/zdm_oci_env.sh):
#      bash zdm_commands_ORADB.sh init
#
# 5. Populate ~/zdm_oci_env.sh with actual OCI OCIDs (edit the file created by init)
#
# 6. Before each migration session, source OCI environment variables:
#      source ~/zdm_oci_env.sh
#
# 7. Set password environment variables securely in the terminal (never save to file):
#      read -sp "Source SYS password: " SOURCE_SYS_PASSWORD; echo; export SOURCE_SYS_PASSWORD
#      read -sp "Target SYS password: " TARGET_SYS_PASSWORD; echo; export TARGET_SYS_PASSWORD
#      # If TDE is enabled:
#      # read -sp "TDE wallet password: " SOURCE_TDE_WALLET_PASSWORD; echo; export SOURCE_TDE_WALLET_PASSWORD
#
# 8. Source Azure Blob credentials:
#      source ~/.azure/zdm_blob_creds
#
# 9. Create temporary password files:
#      bash zdm_commands_ORADB.sh create-creds
#
# 10. Run evaluation first (dry run — no changes made):
#      bash zdm_commands_ORADB.sh eval
#
# 11. Execute migration:
#      bash zdm_commands_ORADB.sh migrate
#      # Note the JOB_ID in the output
#
# 12. Monitor:
#      bash zdm_commands_ORADB.sh status <JOB_ID>
#
# 13. Resume at pause point (ZDM_CONFIGURE_DG_SRC):
#      bash zdm_commands_ORADB.sh resume <JOB_ID>
#
# 14. Cleanup credentials after migration:
#      bash zdm_commands_ORADB.sh cleanup-creds
#
# ============================================================

set -euo pipefail

# =============================================================================
# STATIC CONFIGURATION — Values derived from discovery, questionnaire, and zdm-env.md
# =============================================================================

# ZDM Installation
ZDM_HOME="/u01/app/zdmhome"
ZDM_BIN="${ZDM_HOME}/bin/zdmcli"

# Source Database
SOURCE_DB="oradb1"                             # DB unique name (from source discovery)
SOURCE_HOST="10.1.0.11"                        # tm-oracle-iaas
SOURCE_SSH_USER="azureuser"                    # SSH admin user on source
SOURCE_SSH_KEY="/home/zdmuser/.ssh/odaa.pem"   # Confirmed working by verify_fixes.sh (Blocker 3)
SOURCE_ORACLE_HOME="/u01/app/oracle/product/12.2.0/dbhome_1"

# Target Database
TARGET_DB="oradb01"                            # DB unique name (inferred from listener services)
TARGET_HOST="10.0.1.160"                       # tmodaauks-rqahk1 Node 1 (confirmed reachable)
TARGET_SSH_USER="opc"                          # SSH admin user on ODAA target
TARGET_SSH_KEY="/home/zdmuser/.ssh/odaa.pem"   # Same key for both source and target
TARGET_ORACLE_HOME="/u02/app/oracle/product/19.0.0.0/dbhome_1"  # Confirmed via verify_fixes.sh (Issue 8)

# RSP File path (relative to this script's location, resolved to absolute below)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RSP_TEMPLATE="${SCRIPT_DIR}/zdm_migrate_ORADB.rsp"
RSP_RESOLVED="${HOME}/zdm_migrate_ORADB_resolved.rsp"

# Credentials directory
CREDS_DIR="${HOME}/creds"

# TDE Configuration — set to "true" only after DBA confirms TDE is required
# and TDE has been enabled on the source database (see Runbook Phase 2.4)
TDE_ENABLED="false"

# Sudo path on source and target
SUDO_PATH="/usr/bin/sudo"

# =============================================================================
# OCI ENVIRONMENT VARIABLE DOCUMENTATION
# =============================================================================
# The following variables must be set before running eval or migrate:
#   TARGET_TENANCY_OCID       ocid1.tenancy.oc1..aaaaaaaarvyhjcn7wk...
#   TARGET_USER_OCID          ocid1.user.oc1..aaaaaaaakfe5cirdq7vk...
#   TARGET_FINGERPRINT        OCI API key fingerprint (⚠️ blocked for current federated user)
#   TARGET_COMPARTMENT_OCID   ocid1.compartment.oc1..aaaaaaaas4upnqj7...
#   TARGET_DATABASE_OCID      ocid1.database.oc1.uk-london-1.anwgiljs...
#
# Source from: ~/zdm_oci_env.sh (created by 'init' command)
#
# Azure Blob variables (source from ~/.azure/zdm_blob_creds):
#   AZURE_STORAGE_AUTH_VALUE  Azure storage key or SAS token (secret — never commit)
#
# Password variables (set interactively at runtime):
#   SOURCE_SYS_PASSWORD       Source Oracle SYS password
#   TARGET_SYS_PASSWORD       Target Oracle SYS password
#   SOURCE_TDE_WALLET_PASSWORD TDE wallet password (only if TDE_ENABLED=true)

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# =============================================================================
# VALIDATE OCI ENVIRONMENT VARIABLES
# =============================================================================
validate_oci_environment() {
    local missing_vars=()
    local errors=0

    echo ""
    echo "=========================================="
    echo "VALIDATING OCI ENVIRONMENT VARIABLES"
    echo "=========================================="
    echo ""

    if [ -z "${TARGET_TENANCY_OCID:-}" ]; then
        missing_vars+=("TARGET_TENANCY_OCID")
        ((errors++))
        echo "  ✗ TARGET_TENANCY_OCID is NOT set"
    else
        echo "  ✓ TARGET_TENANCY_OCID is set"
    fi

    if [ -z "${TARGET_USER_OCID:-}" ]; then
        missing_vars+=("TARGET_USER_OCID")
        ((errors++))
        echo "  ✗ TARGET_USER_OCID is NOT set"
    else
        echo "  ✓ TARGET_USER_OCID is set"
    fi

    if [ -z "${TARGET_FINGERPRINT:-}" ]; then
        missing_vars+=("TARGET_FINGERPRINT")
        ((errors++))
        echo "  ✗ TARGET_FINGERPRINT is NOT set"
        echo "    ⚠️  NOTE: Current OCI user is a federated IDCSApp user — API keys are disabled."
        echo "       Contact OCI admin if ZDM requires OCI API auth."
    else
        echo "  ✓ TARGET_FINGERPRINT is set"
    fi

    if [ -z "${TARGET_COMPARTMENT_OCID:-}" ]; then
        missing_vars+=("TARGET_COMPARTMENT_OCID")
        ((errors++))
        echo "  ✗ TARGET_COMPARTMENT_OCID is NOT set"
    else
        echo "  ✓ TARGET_COMPARTMENT_OCID is set"
    fi

    if [ -z "${TARGET_DATABASE_OCID:-}" ]; then
        missing_vars+=("TARGET_DATABASE_OCID")
        ((errors++))
        echo "  ✗ TARGET_DATABASE_OCID is NOT set"
    else
        echo "  ✓ TARGET_DATABASE_OCID is set"
    fi

    # Azure Blob credentials check
    if [ -z "${AZURE_STORAGE_AUTH_VALUE:-}" ]; then
        missing_vars+=("AZURE_STORAGE_AUTH_VALUE")
        ((errors++))
        echo "  ✗ AZURE_STORAGE_AUTH_VALUE is NOT set"
        echo "    → Source it: source ~/.azure/zdm_blob_creds"
    else
        echo "  ✓ AZURE_STORAGE_AUTH_VALUE is set"
    fi

    if [ "${errors}" -gt 0 ]; then
        echo ""
        error "The following environment variables are not set:"
        printf '    - %s\n' "${missing_vars[@]}"
        echo ""
        echo "  To set OCI variables: source ~/zdm_oci_env.sh"
        echo "  To set Azure key:     source ~/.azure/zdm_blob_creds"
        echo ""
        return 1
    fi

    echo ""
    echo "  ✓ All OCI/Azure environment variables are set"
    echo ""
    return 0
}

# =============================================================================
# VALIDATE PASSWORD ENVIRONMENT VARIABLES
# =============================================================================
validate_password_environment() {
    local missing_vars=()
    local errors=0

    echo ""
    echo "=========================================="
    echo "VALIDATING PASSWORD ENVIRONMENT VARIABLES"
    echo "=========================================="
    echo ""

    if [ -z "${SOURCE_SYS_PASSWORD:-}" ]; then
        missing_vars+=("SOURCE_SYS_PASSWORD")
        ((errors++))
        echo "  ✗ SOURCE_SYS_PASSWORD is NOT set"
    else
        echo "  ✓ SOURCE_SYS_PASSWORD is set"
    fi

    if [ -z "${TARGET_SYS_PASSWORD:-}" ]; then
        missing_vars+=("TARGET_SYS_PASSWORD")
        ((errors++))
        echo "  ✗ TARGET_SYS_PASSWORD is NOT set"
    else
        echo "  ✓ TARGET_SYS_PASSWORD is set"
    fi

    if [ "${TDE_ENABLED}" = "true" ]; then
        if [ -z "${SOURCE_TDE_WALLET_PASSWORD:-}" ]; then
            missing_vars+=("SOURCE_TDE_WALLET_PASSWORD")
            ((errors++))
            echo "  ✗ SOURCE_TDE_WALLET_PASSWORD is NOT set (required — TDE_ENABLED=true)"
        else
            echo "  ✓ SOURCE_TDE_WALLET_PASSWORD is set"
        fi
    else
        echo "  - SOURCE_TDE_WALLET_PASSWORD: not required (TDE_ENABLED=false)"
    fi

    if [ "${errors}" -gt 0 ]; then
        echo ""
        error "The following password environment variables are not set:"
        printf '    - %s\n' "${missing_vars[@]}"
        echo ""
        echo "  Set them securely using read:"
        for var in "${missing_vars[@]}"; do
            echo "    read -sp \"Enter ${var}: \" ${var}; echo; export ${var}"
        done
        echo ""
        return 1
    fi

    echo ""
    echo "  ✓ All required password environment variables are set"
    echo ""
    return 0
}

# =============================================================================
# COMMAND: init
# First-time setup — creates ~/creds and ~/zdm_oci_env.sh template
# =============================================================================
cmd_init() {
    log "Running ZDM first-time initialization for ORADB migration..."
    echo ""

    # Create credentials directory
    if [ ! -d "${CREDS_DIR}" ]; then
        mkdir -p "${CREDS_DIR}"
        chmod 700 "${CREDS_DIR}"
        log "Created credentials directory: ${CREDS_DIR} (chmod 700)"
    else
        log "Credentials directory already exists: ${CREDS_DIR}"
    fi

    # Create OCI environment file template if it doesn't exist
    if [ ! -f "${HOME}/zdm_oci_env.sh" ]; then
        cat > "${HOME}/zdm_oci_env.sh" << 'EOF'
#!/bin/bash
# ZDM OCI Environment Variables — ORADB Migration
# Edit this file and fill in the actual values before running migration commands.
# Source it with: source ~/zdm_oci_env.sh

# Target OCI Configuration
# These values are pre-populated from zdm-env.md — confirm they are correct.
export TARGET_TENANCY_OCID="ocid1.tenancy.oc1..aaaaaaaarvyhjcn7wkkxxx5g3o7lgqks23bmsjtsticz3gtg5xs5qyrwkftq"
export TARGET_USER_OCID="ocid1.user.oc1..aaaaaaaakfe5cirdq7vkkrhogjrgcrgftvwb7mdoehujgchefpqv54vhsnoa"
export TARGET_COMPARTMENT_OCID="ocid1.compartment.oc1..aaaaaaaas4upnqj72dfiivgwvn3uui5gkxo7ng6leeoifucbjiy326urbhmq"
export TARGET_DATABASE_OCID="ocid1.database.oc1.uk-london-1.anwgiljss56liuaatz45cjnpbvpgku7gkorvxg6lytoj5lxxruk2eqxzkzma"

# OCI API Key Fingerprint
# ⚠️  WARNING: The current OCI user (temandin@microsoft.com) is a federated IDCSApp user.
#    API keys are currently DISABLED for this user.
#    Update this value only after an OCI admin provisions API key access or a service account.
export TARGET_FINGERPRINT="<OCI_API_KEY_FINGERPRINT_REPLACE_AFTER_OCI_ADMIN_PROVISIONS>"

# OCI Region
export TARGET_REGION="uk-london-1"
EOF
        chmod 600 "${HOME}/zdm_oci_env.sh"
        log "Created OCI environment template: ~/zdm_oci_env.sh"
        echo ""
        echo "  NEXT STEP: Edit ~/zdm_oci_env.sh and update TARGET_FINGERPRINT"
        echo "             once OCI admin provisions API key access."
        echo "             Then run: source ~/zdm_oci_env.sh"
    else
        log "OCI environment file already exists: ~/zdm_oci_env.sh"
    fi

    # Verify ZDM service is running
    echo ""
    log "Verifying ZDM installation..."
    if [ -f "${ZDM_BIN}" ]; then
        log "ZDM binary found: ${ZDM_BIN}"
        "${ZDM_HOME}/bin/zdmservice" status
    else
        error "ZDM binary not found at ${ZDM_BIN}. Verify ZDM installation."
        return 1
    fi

    echo ""
    log "Verifying SSH connectivity to source (10.1.0.11)..."
    if ssh -o BatchMode=yes -o ConnectTimeout=10 -i "${SOURCE_SSH_KEY}" \
        "${SOURCE_SSH_USER}@${SOURCE_HOST}" "echo 'Source SSH OK'" 2>/dev/null; then
        echo "  ✓ Source SSH connectivity: OK"
    else
        echo "  ✗ Source SSH connectivity: FAILED — check ${SOURCE_SSH_KEY} and network"
    fi

    log "Verifying SSH connectivity to target (10.0.1.160)..."
    if ssh -o BatchMode=yes -o ConnectTimeout=10 -i "${TARGET_SSH_KEY}" \
        "${TARGET_SSH_USER}@${TARGET_HOST}" "echo 'Target SSH OK'" 2>/dev/null; then
        echo "  ✓ Target SSH connectivity: OK"
    else
        echo "  ✗ Target SSH connectivity: FAILED — check ${TARGET_SSH_KEY} and network"
        echo "    NOTE: ICMP ping to target is expected to fail (ODAA network blocks ICMP)."
        echo "          TCP ports 22 and 1521 confirmed OPEN in Step2 verification."
    fi

    echo ""
    log "Init complete."
    echo ""
    echo "  ============================================="
    echo "  NEXT STEPS:"
    echo "    1. Edit ~/zdm_oci_env.sh with correct OCI OCID values"
    echo "    2. source ~/zdm_oci_env.sh"
    echo "    3. source ~/.azure/zdm_blob_creds"
    echo "    4. Set password variables at the terminal:"
    echo "         read -sp 'Source SYS: ' SOURCE_SYS_PASSWORD; echo; export SOURCE_SYS_PASSWORD"
    echo "         read -sp 'Target SYS: ' TARGET_SYS_PASSWORD; echo; export TARGET_SYS_PASSWORD"
    echo "    5. bash zdm_commands_ORADB.sh create-creds"
    echo "    6. bash zdm_commands_ORADB.sh eval"
    echo "  ============================================="
}

# =============================================================================
# COMMAND: create-creds
# Creates temporary password files from environment variables
# Run just before zdmcli eval or migrate — delete immediately after with cleanup-creds
# =============================================================================
cmd_create_creds() {
    log "Creating temporary password files from environment variables..."

    validate_password_environment || return 1

    # Ensure credentials directory exists with correct permissions
    mkdir -p "${CREDS_DIR}"
    chmod 700 "${CREDS_DIR}"

    # Create password files
    printf '%s' "${SOURCE_SYS_PASSWORD}" > "${CREDS_DIR}/source_sys_password.txt"
    chmod 600 "${CREDS_DIR}/source_sys_password.txt"
    log "Created: ${CREDS_DIR}/source_sys_password.txt"

    printf '%s' "${TARGET_SYS_PASSWORD}" > "${CREDS_DIR}/target_sys_password.txt"
    chmod 600 "${CREDS_DIR}/target_sys_password.txt"
    log "Created: ${CREDS_DIR}/target_sys_password.txt"

    if [ "${TDE_ENABLED}" = "true" ]; then
        printf '%s' "${SOURCE_TDE_WALLET_PASSWORD}" > "${CREDS_DIR}/tde_password.txt"
        chmod 600 "${CREDS_DIR}/tde_password.txt"
        log "Created: ${CREDS_DIR}/tde_password.txt"
    fi

    echo ""
    log "Password files created in ${CREDS_DIR} (chmod 600)."
    log "⚠️  Remember to run 'bash zdm_commands_ORADB.sh cleanup-creds' after migration."
}

# =============================================================================
# COMMAND: cleanup-creds
# Securely removes temporary password files — run immediately after migration
# =============================================================================
cmd_cleanup_creds() {
    log "Cleaning up temporary password files in ${CREDS_DIR}..."

    if [ -d "${CREDS_DIR}" ]; then
        find "${CREDS_DIR}" -name "*.txt" -exec shred -u {} \; 2>/dev/null || \
        find "${CREDS_DIR}" -name "*.txt" -exec rm -f {} \;
        log "Password files removed from ${CREDS_DIR}."
    else
        log "Credentials directory ${CREDS_DIR} does not exist — nothing to clean."
    fi
}

# =============================================================================
# COMMAND: generate-rsp
# Substitutes environment variables in the RSP template and writes resolved file
# =============================================================================
cmd_generate_rsp() {
    log "Generating resolved RSP file from template..."

    if [ ! -f "${RSP_TEMPLATE}" ]; then
        error "RSP template not found: ${RSP_TEMPLATE}"
        error "Ensure you are running this script from the Step3 directory."
        return 1
    fi

    validate_oci_environment || return 1

    envsubst < "${RSP_TEMPLATE}" > "${RSP_RESOLVED}"
    chmod 600 "${RSP_RESOLVED}"
    log "Resolved RSP written to: ${RSP_RESOLVED}"
    log "⚠️  This file contains substituted values — do not commit to git."

    # Validate that no unresolved ${...} placeholders remain in the RSP
    local unresolved
    unresolved=$(grep -oP '\$\{[^}]+\}' "${RSP_RESOLVED}" 2>/dev/null || true)
    if [ -n "${unresolved}" ]; then
        error "RSP contains unresolved placeholders after envsubst:"
        echo "${unresolved}" | while read -r v; do
            echo "    ${v}"
        done
        return 1
    fi
    log "RSP validation: no unresolved placeholders."
}

# =============================================================================
# COMMAND: check-service
# Verify ZDM service is running before executing zdmcli commands
# =============================================================================
cmd_check_service() {
    log "Checking ZDM service status..."
    if ! "${ZDM_HOME}/bin/zdmservice" status > /dev/null 2>&1; then
        echo ""
        error "ZDM service is NOT running."
        echo "  Start it with: ${ZDM_HOME}/bin/zdmservice start"
        echo "  Then re-run this command."
        return 1
    fi
    log "ZDM service is running."
    return 0
}

# =============================================================================
# COMMAND: eval
# ZDM evaluation (dry run — no changes made to source or target)
# =============================================================================
cmd_eval() {
    log "Starting ZDM evaluation (dry run) for ORADB migration..."
    echo ""

    cmd_check_service || return 1
    validate_oci_environment || return 1
    validate_password_environment || return 1

    # Generate resolved RSP
    cmd_generate_rsp || return 1

    log "Running ZDM EVAL command..."
    echo ""
    echo "  zdmcli command:"

    local TDE_ARG=""
    if [ "${TDE_ENABLED}" = "true" ]; then
        TDE_ARG="-tdekeystorepasswd ${CREDS_DIR}/tde_password.txt"
    fi

    "${ZDM_BIN}" migrate database \
        -sourcedb "${SOURCE_DB}" \
        -sourcenode "${SOURCE_HOST}" \
        -srcauth zdmauth \
        -srcarg1 "user:${SOURCE_SSH_USER}" \
        -srcarg2 "identity_file:${SOURCE_SSH_KEY}" \
        -srcarg3 "sudo_location:${SUDO_PATH}" \
        -targetnode "${TARGET_HOST}" \
        -tgtauth zdmauth \
        -tgtarg1 "user:${TARGET_SSH_USER}" \
        -tgtarg2 "identity_file:${TARGET_SSH_KEY}" \
        -tgtarg3 "sudo_location:${SUDO_PATH}" \
        -rsp "${RSP_RESOLVED}" \
        -targethome "${TARGET_ORACLE_HOME}" \
        ${TDE_ARG} \
        -eval

    local EXIT_CODE=$?
    echo ""
    if [ ${EXIT_CODE} -eq 0 ]; then
        log "ZDM evaluation submitted. Check status with:"
        echo "    bash zdm_commands_ORADB.sh status <JOB_ID>"
    else
        error "ZDM eval command returned exit code ${EXIT_CODE}."
        error "Review the output above and the ZDM log at: ${ZDM_HOME}/log/"
    fi
    return ${EXIT_CODE}
}

# =============================================================================
# COMMAND: migrate
# Full ZDM migration execution
# ⚠️  Only run after successful evaluation with no blocking issues
# The job will pause at ZDM_CONFIGURE_DG_SRC for manual DG validation
# =============================================================================
cmd_migrate() {
    log "Starting ZDM ONLINE_PHYSICAL migration for ORADB..."
    echo ""

    cmd_check_service || return 1
    validate_oci_environment || return 1
    validate_password_environment || return 1

    # Confirm password files exist
    if [ ! -f "${CREDS_DIR}/source_sys_password.txt" ] || [ ! -f "${CREDS_DIR}/target_sys_password.txt" ]; then
        error "Password files not found in ${CREDS_DIR}."
        error "Run: bash zdm_commands_ORADB.sh create-creds"
        return 1
    fi

    # Generate resolved RSP
    cmd_generate_rsp || return 1

    echo ""
    echo "  ⚠️  MIGRATION CHECKLIST — confirm before continuing:"
    echo "     [ ] Evaluation completed successfully (no blocking issues)"
    echo "     [ ] TDE strategy confirmed (or TDE_ENABLED=false confirmed safe)"
    echo "     [ ] Source disk space sufficient (≥ 10 GB free — Issue 7)"
    echo "     [ ] Application team notified of maintenance window"
    echo "     [ ] Rollback plan reviewed (Runbook Phase 7)"
    echo ""
    read -rp "  Type 'MIGRATE' to confirm and start the migration: " CONFIRM
    if [ "${CONFIRM}" != "MIGRATE" ]; then
        log "Migration cancelled."
        return 0
    fi

    log "Submitting ZDM ONLINE_PHYSICAL migration job..."
    echo ""

    local TDE_ARG=""
    if [ "${TDE_ENABLED}" = "true" ]; then
        TDE_ARG="-tdekeystorepasswd ${CREDS_DIR}/tde_password.txt"
    fi

    "${ZDM_BIN}" migrate database \
        -sourcedb "${SOURCE_DB}" \
        -sourcenode "${SOURCE_HOST}" \
        -srcauth zdmauth \
        -srcarg1 "user:${SOURCE_SSH_USER}" \
        -srcarg2 "identity_file:${SOURCE_SSH_KEY}" \
        -srcarg3 "sudo_location:${SUDO_PATH}" \
        -targetnode "${TARGET_HOST}" \
        -tgtauth zdmauth \
        -tgtarg1 "user:${TARGET_SSH_USER}" \
        -tgtarg2 "identity_file:${TARGET_SSH_KEY}" \
        -tgtarg3 "sudo_location:${SUDO_PATH}" \
        -rsp "${RSP_RESOLVED}" \
        -targethome "${TARGET_ORACLE_HOME}" \
        ${TDE_ARG}

    local EXIT_CODE=$?
    echo ""
    if [ ${EXIT_CODE} -eq 0 ]; then
        log "ZDM migration job submitted."
        log ""
        log "⚠️  The job will PAUSE at ZDM_CONFIGURE_DG_SRC."
        log "   Monitor with: bash zdm_commands_ORADB.sh status <JOB_ID>"
        log "   After DG validation, resume with: bash zdm_commands_ORADB.sh resume <JOB_ID>"
        log "   See ZDM-Migration-Runbook-ORADB.md Phase 5 for full steps."
    else
        error "ZDM migration command returned exit code ${EXIT_CODE}."
        error "Review output above and: ${ZDM_HOME}/log/"
    fi
    return ${EXIT_CODE}
}

# =============================================================================
# COMMAND: status <JOB_ID>
# Query ZDM job status
# =============================================================================
cmd_status() {
    local JOB_ID="${1:-}"
    if [ -z "${JOB_ID}" ]; then
        error "Usage: bash zdm_commands_ORADB.sh status <JOB_ID>"
        echo ""
        echo "  To list all jobs:"
        echo "    ${ZDM_BIN} query jobid -all"
        return 1
    fi

    log "Querying ZDM job ${JOB_ID}..."
    "${ZDM_BIN}" query job -jobid "${JOB_ID}"
}

# =============================================================================
# COMMAND: resume <JOB_ID>
# Resume a paused ZDM job
# =============================================================================
cmd_resume() {
    local JOB_ID="${1:-}"
    if [ -z "${JOB_ID}" ]; then
        error "Usage: bash zdm_commands_ORADB.sh resume <JOB_ID>"
        return 1
    fi

    log "Resuming ZDM job ${JOB_ID}..."
    echo ""
    echo "  ⚠️  Before resuming, confirm:"
    echo "     [ ] Data Guard configured correctly on target (if paused at ZDM_CONFIGURE_DG_SRC)"
    echo "     [ ] Redo transport and apply lag are at acceptable levels"
    echo "     [ ] Application team notified if near switchover"
    echo ""
    read -rp "  Type 'RESUME' to confirm: " CONFIRM
    if [ "${CONFIRM}" != "RESUME" ]; then
        log "Resume cancelled."
        return 0
    fi

    "${ZDM_BIN}" resume job -jobid "${JOB_ID}"
}

# =============================================================================
# COMMAND: abort <JOB_ID>
# Abort a ZDM job (use before switchover only)
# ⚠️  Never abort during or after switchover — coordinate with Oracle support
# =============================================================================
cmd_abort() {
    local JOB_ID="${1:-}"
    if [ -z "${JOB_ID}" ]; then
        error "Usage: bash zdm_commands_ORADB.sh abort <JOB_ID>"
        return 1
    fi

    echo ""
    echo "  ⚠️  WARNING: Only abort jobs that have NOT started the switchover phase."
    echo "     Aborting during or after ZDM_SWITCHOVER_SRC can leave databases in"
    echo "     an inconsistent state. Coordinate with Oracle support if in doubt."
    echo ""
    read -rp "  Type 'ABORT' to confirm aborting job ${JOB_ID}: " CONFIRM
    if [ "${CONFIRM}" != "ABORT" ]; then
        log "Abort cancelled."
        return 0
    fi

    log "Aborting ZDM job ${JOB_ID}..."
    "${ZDM_BIN}" abort job -jobid "${JOB_ID}"
}

# =============================================================================
# COMMAND: list-jobs
# List all ZDM jobs
# =============================================================================
cmd_list_jobs() {
    log "Listing all ZDM jobs..."
    "${ZDM_BIN}" query jobid -all
}

# =============================================================================
# COMMAND: show-rsp
# Display the RSP template with current environment variable values shown
# =============================================================================
cmd_show_rsp() {
    log "Showing RSP template: ${RSP_TEMPLATE}"
    echo ""
    cat "${RSP_TEMPLATE}"
}

# =============================================================================
# COMMAND: help
# =============================================================================
cmd_help() {
    echo ""
    echo "ZDM Commands Script — ORADB Migration"
    echo "======================================"
    echo ""
    echo "Usage: bash zdm_commands_ORADB.sh <command> [args]"
    echo ""
    echo "Commands:"
    echo "  init                  First-time setup: create ~/creds and ~/zdm_oci_env.sh template"
    echo "  create-creds          Create temporary password files from environment variables"
    echo "  cleanup-creds         Securely delete temporary password files after migration"
    echo "  eval                  Run ZDM evaluation (dry run — no changes made)"
    echo "  migrate               Execute ZDM ONLINE_PHYSICAL migration"
    echo "  status <JOB_ID>       Query status of a ZDM job"
    echo "  resume <JOB_ID>       Resume a paused ZDM job"
    echo "  abort <JOB_ID>        Abort a ZDM job (⚠️  before switchover only)"
    echo "  list-jobs             List all ZDM jobs"
    echo "  show-rsp              Show the RSP template file"
    echo "  help                  Show this help"
    echo ""
    echo "Typical workflow:"
    echo "  1. bash zdm_commands_ORADB.sh init               (first time only)"
    echo "  2. source ~/zdm_oci_env.sh                       (each session)"
    echo "  3. source ~/.azure/zdm_blob_creds                (each session)"
    echo "  4. read -sp '...' SOURCE_SYS_PASSWORD; ...       (each session)"
    echo "  5. bash zdm_commands_ORADB.sh create-creds"
    echo "  6. bash zdm_commands_ORADB.sh eval"
    echo "  7. bash zdm_commands_ORADB.sh migrate"
    echo "  8. bash zdm_commands_ORADB.sh status <JOB_ID>"
    echo "  9. bash zdm_commands_ORADB.sh resume <JOB_ID>    (at pause point)"
    echo " 10. bash zdm_commands_ORADB.sh cleanup-creds"
    echo ""
    echo "See README.md and ZDM-Migration-Runbook-ORADB.md for full instructions."
    echo ""
}

# =============================================================================
# MAIN COMMAND DISPATCH
# =============================================================================

COMMAND="${1:-help}"
shift || true

case "${COMMAND}" in
    init)           cmd_init ;;
    create-creds)   cmd_create_creds ;;
    cleanup-creds)  cmd_cleanup_creds ;;
    generate-rsp)   cmd_generate_rsp ;;
    check-service)  cmd_check_service ;;
    eval)           cmd_eval ;;
    migrate)        cmd_migrate ;;
    status)         cmd_status "${1:-}" ;;
    resume)         cmd_resume "${1:-}" ;;
    abort)          cmd_abort "${1:-}" ;;
    list-jobs)      cmd_list_jobs ;;
    show-rsp)       cmd_show_rsp ;;
    help|--help|-h) cmd_help ;;
    *)
        error "Unknown command: ${COMMAND}"
        cmd_help
        exit 1
        ;;
esac
