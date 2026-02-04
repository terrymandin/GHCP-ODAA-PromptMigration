#!/bin/bash
# ===========================================
# ZDM CLI Commands
# Database: ORADB01
# Migration Type: ONLINE_PHYSICAL (Data Guard)
# Generated: 2026-02-04
# ===========================================
#
# Configuration values extracted from:
# - Source: zdm_source_discovery_temandin-oravm-vm01_20260203_135749.json
# - Target: zdm_target_discovery_tmodaauks-rqahk1_20260203_135834.json
# - ZDM Server: zdm_server_discovery_tm-vm-odaa-oracle-jumpbox_20260203_085856.json
# - Questionnaire: Migration-Questionnaire-PRODDB.md
#
# IMPORTANT: Login and Setup Instructions
# ========================================
# 1. SSH to ZDM server as the admin user:
#    ssh azureuser@tm-vm-odaa-oracle-jumpbox
#
# 2. Switch to zdmuser:
#    sudo su - zdmuser
#
# 3. Clone your fork if not already done:
#    cd ~
#    git clone https://github.com/terrymandin/GHCP-ODAA-PromptMigration.git
#
# 4. Navigate to the Step3 artifacts directory:
#    cd ~/GHCP-ODAA-PromptMigration/Artifacts/Phase10-Migration/ZDM/PRODDB/Step3
#
# 5. Make this script executable:
#    chmod +x zdm_commands_PRODDB.sh
#
# 6. First-time setup (creates ~/creds and ~/zdm_oci_env.sh):
#    ./zdm_commands_PRODDB.sh init
#
# 7. Edit ~/zdm_oci_env.sh with your actual OCI OCIDs
#
# 8. Source the OCI environment file:
#    source ~/zdm_oci_env.sh
#
# 9. Run the migration:
#    ./zdm_commands_PRODDB.sh eval      # Evaluation first
#    ./zdm_commands_PRODDB.sh migrate   # Actual migration
#
# ===========================================

set -e  # Exit on error

# -------------------------------------------
# MIGRATION CONFIGURATION VARIABLES
# -------------------------------------------
# NOTE: These variables use ZDM_MIG_ prefix to avoid conflicts with
# user environment variables from Step 0 discovery scripts
# (e.g., SOURCE_HOST, TARGET_HOST, SOURCE_USER, etc.)
#
# Values extracted from discovery files:
# - Source: zdm_source_discovery_temandin-oravm-vm01_20260203_135749.json
# - Target: zdm_target_discovery_tmodaauks-rqahk1_20260203_135834.json
# - ZDM Server: zdm_server_discovery_tm-vm-odaa-oracle-jumpbox_20260203_085856.json
# -------------------------------------------
export ZDM_HOME="/u01/app/zdmhome"  # From ZDM server discovery: zdm_home
export PATH="$ZDM_HOME/bin:$PATH"

# Source Database Configuration (from zdm_source_discovery_temandin-oravm-vm01_20260203_135749.json)
export ZDM_MIG_SOURCE_DB="ORADB01"                    # discovery: db_name
export ZDM_MIG_SOURCE_DB_UNIQUE_NAME="oradb01"        # discovery: db_unique_name
export ZDM_MIG_SOURCE_HOST="temandin-oravm-vm01"      # discovery: hostname
export ZDM_MIG_SOURCE_PORT="1521"                     # discovery: listener port
export ZDM_MIG_SOURCE_SERVICE="oradb01"               # discovery: service name
export ZDM_MIG_SOURCE_ORACLE_HOME="/u01/app/oracle/product/19.0.0/dbhome_1"  # discovery: oracle_home
export ZDM_MIG_SOURCE_SSH_USER="oracle"               # questionnaire: Source Admin User

# Target Database Configuration (from zdm_target_discovery_tmodaauks-rqahk1_20260203_135834.json)
export ZDM_MIG_TARGET_DB="ORADB01"                    # target db name (same as source for migration)
export ZDM_MIG_TARGET_DB_UNIQUE_NAME="oradb01_tgt"    # questionnaire: target unique name
export ZDM_MIG_TARGET_HOST="tmodaauks-rqahk1"         # discovery: hostname
export ZDM_MIG_TARGET_PORT="1521"                     # discovery: listener port
export ZDM_MIG_TARGET_SERVICE="oradb01_tgt"           # target service name
export ZDM_MIG_TARGET_ORACLE_HOME="/u02/app/oracle/product/19.0.0.0/dbhome_1"  # discovery: oracle_home
export ZDM_MIG_TARGET_SSH_USER="opc"                  # questionnaire: Target Admin User

# ZDM Runtime Configuration (from zdm_server_discovery_tm-vm-odaa-oracle-jumpbox_20260203_085856.json)
export ZDM_MIG_ZDM_USER="zdmuser"                     # zdm software owner
export ZDM_MIG_SSH_KEY="/home/zdmuser/.ssh/zdm.pem"   # questionnaire: Source SSH Key Path
export ZDM_MIG_OCI_KEY="/home/zdmuser/.oci/odaa.pem"  # discovered OCI key

# RSP File (relative to script location)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export RSP_FILE="${SCRIPT_DIR}/zdm_migrate_PRODDB.rsp"

# Credentials directory
export CREDS_DIR="${HOME}/creds"

# TDE Configuration (from zdm_source_discovery - TDE wallet detected as OPEN)
export TDE_ENABLED="true"
export TDE_WALLET_LOCATION="/u01/app/oracle/admin/oradb01/wallet/tde"  # discovery: wallet location

# OCI Environment file
export OCI_ENV_FILE="${HOME}/zdm_oci_env.sh"

# -------------------------------------------
# OCI ENVIRONMENT VARIABLE VALIDATION
# -------------------------------------------
validate_oci_environment() {
    local missing_vars=()
    local errors=0
    
    echo ""
    echo "=========================================="
    echo "VALIDATING OCI ENVIRONMENT VARIABLES"
    echo "=========================================="
    echo ""
    
    # Check TARGET_TENANCY_OCID
    if [ -z "${TARGET_TENANCY_OCID:-}" ]; then
        missing_vars+=("TARGET_TENANCY_OCID")
        ((errors++))
        echo "  ✗ TARGET_TENANCY_OCID is NOT set"
    else
        echo "  ✓ TARGET_TENANCY_OCID is set: ${TARGET_TENANCY_OCID:0:30}..."
    fi
    
    # Check TARGET_USER_OCID
    if [ -z "${TARGET_USER_OCID:-}" ]; then
        missing_vars+=("TARGET_USER_OCID")
        ((errors++))
        echo "  ✗ TARGET_USER_OCID is NOT set"
    else
        echo "  ✓ TARGET_USER_OCID is set: ${TARGET_USER_OCID:0:30}..."
    fi
    
    # Check TARGET_FINGERPRINT
    if [ -z "${TARGET_FINGERPRINT:-}" ]; then
        missing_vars+=("TARGET_FINGERPRINT")
        ((errors++))
        echo "  ✗ TARGET_FINGERPRINT is NOT set"
    else
        echo "  ✓ TARGET_FINGERPRINT is set: ${TARGET_FINGERPRINT}"
    fi
    
    # Check TARGET_COMPARTMENT_OCID
    if [ -z "${TARGET_COMPARTMENT_OCID:-}" ]; then
        missing_vars+=("TARGET_COMPARTMENT_OCID")
        ((errors++))
        echo "  ✗ TARGET_COMPARTMENT_OCID is NOT set"
    else
        echo "  ✓ TARGET_COMPARTMENT_OCID is set: ${TARGET_COMPARTMENT_OCID:0:30}..."
    fi
    
    # Check TARGET_DATABASE_OCID
    if [ -z "${TARGET_DATABASE_OCID:-}" ]; then
        missing_vars+=("TARGET_DATABASE_OCID")
        ((errors++))
        echo "  ✗ TARGET_DATABASE_OCID is NOT set"
    else
        echo "  ✓ TARGET_DATABASE_OCID is set: ${TARGET_DATABASE_OCID:0:30}..."
    fi
    
    echo ""
    
    if [ $errors -gt 0 ]; then
        echo "ERROR: The following OCI environment variables are not set:"
        printf '  - %s\n' "${missing_vars[@]}"
        echo ""
        echo "To set these variables:"
        echo "  1. Edit ~/zdm_oci_env.sh with your actual OCI OCIDs"
        echo "  2. Run: source ~/zdm_oci_env.sh"
        echo ""
        echo "Where to find these values:"
        echo "  - TARGET_TENANCY_OCID: OCI Console > Profile > Tenancy Details"
        echo "  - TARGET_USER_OCID: OCI Console > Profile > User Settings"
        echo "  - TARGET_FINGERPRINT: OCI Console > Profile > API Keys"
        echo "  - TARGET_COMPARTMENT_OCID: OCI Console > Identity > Compartments"
        echo "  - TARGET_DATABASE_OCID: OCI Console > Databases > Your Database"
        return 1
    fi
    
    echo "✓ All required OCI environment variables are set"
    return 0
}

# -------------------------------------------
# PASSWORD ENVIRONMENT VARIABLE VALIDATION
# -------------------------------------------
validate_password_environment() {
    local missing_vars=()
    local errors=0
    
    echo ""
    echo "=========================================="
    echo "VALIDATING PASSWORD ENVIRONMENT VARIABLES"
    echo "=========================================="
    echo ""
    
    # Check SOURCE_SYS_PASSWORD
    if [ -z "${SOURCE_SYS_PASSWORD:-}" ]; then
        missing_vars+=("SOURCE_SYS_PASSWORD")
        ((errors++))
        echo "  ✗ SOURCE_SYS_PASSWORD is NOT set"
    else
        echo "  ✓ SOURCE_SYS_PASSWORD is set"
    fi
    
    # Check TARGET_SYS_PASSWORD
    if [ -z "${TARGET_SYS_PASSWORD:-}" ]; then
        missing_vars+=("TARGET_SYS_PASSWORD")
        ((errors++))
        echo "  ✗ TARGET_SYS_PASSWORD is NOT set"
    else
        echo "  ✓ TARGET_SYS_PASSWORD is set"
    fi
    
    # Check SOURCE_TDE_WALLET_PASSWORD (only if TDE is enabled)
    if [ "${TDE_ENABLED}" = "true" ]; then
        if [ -z "${SOURCE_TDE_WALLET_PASSWORD:-}" ]; then
            missing_vars+=("SOURCE_TDE_WALLET_PASSWORD")
            ((errors++))
            echo "  ✗ SOURCE_TDE_WALLET_PASSWORD is NOT set (TDE is enabled)"
        else
            echo "  ✓ SOURCE_TDE_WALLET_PASSWORD is set"
        fi
    fi
    
    echo ""
    
    if [ $errors -gt 0 ]; then
        echo "ERROR: The following password environment variables are not set:"
        printf '  - %s\n' "${missing_vars[@]}"
        echo ""
        echo "To set passwords securely (will not echo to screen):"
        echo '  read -sp "Enter SOURCE SYS password: " SOURCE_SYS_PASSWORD; echo; export SOURCE_SYS_PASSWORD'
        echo '  read -sp "Enter TARGET SYS password: " TARGET_SYS_PASSWORD; echo; export TARGET_SYS_PASSWORD'
        if [ "${TDE_ENABLED}" = "true" ]; then
            echo '  read -sp "Enter TDE wallet password: " SOURCE_TDE_WALLET_PASSWORD; echo; export SOURCE_TDE_WALLET_PASSWORD'
        fi
        return 1
    fi
    
    echo "✓ All required password environment variables are set"
    return 0
}

# -------------------------------------------
# INITIALIZATION FUNCTION
# -------------------------------------------
init() {
    echo ""
    echo "=========================================="
    echo "INITIALIZING ZDM MIGRATION ENVIRONMENT"
    echo "=========================================="
    echo ""
    
    # Create credentials directory
    echo "Creating credentials directory: ${CREDS_DIR}"
    mkdir -p "${CREDS_DIR}"
    chmod 700 "${CREDS_DIR}"
    echo "  ✓ Created ${CREDS_DIR} with permissions 700"
    
    # Create OCI environment file template
    if [ ! -f "${OCI_ENV_FILE}" ]; then
        echo ""
        echo "Creating OCI environment file template: ${OCI_ENV_FILE}"
        cat > "${OCI_ENV_FILE}" << 'OCIEOF'
#!/bin/bash
# ===========================================
# OCI Environment Variables for PRODDB Migration
# Generated: 2026-02-04
# ===========================================
#
# INSTRUCTIONS:
# 1. Replace the placeholder values below with your actual OCI OCIDs
# 2. Save this file
# 3. Source it before running migration: source ~/zdm_oci_env.sh
#
# WHERE TO FIND THESE VALUES:
# - TARGET_TENANCY_OCID: OCI Console > Profile > Tenancy Details
# - TARGET_USER_OCID: OCI Console > Profile > User Settings  
# - TARGET_FINGERPRINT: OCI Console > Profile > API Keys
# - TARGET_COMPARTMENT_OCID: OCI Console > Identity > Compartments
# - TARGET_DATABASE_OCID: OCI Console > Databases > Your Database
# ===========================================

# Target OCI Configuration (REQUIRED)
export TARGET_TENANCY_OCID="ocid1.tenancy.oc1..aaaaaaaabcdefghijklmnopqrstuvwxyz123456789"
export TARGET_USER_OCID="ocid1.user.oc1..aaaaaaaaxyz987654321abcdefghijklmnopqrstuv"
export TARGET_FINGERPRINT="aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99"
export TARGET_COMPARTMENT_OCID="ocid1.compartment.oc1..aaaa_REPLACE_WITH_YOUR_COMPARTMENT_OCID"
export TARGET_DATABASE_OCID="ocid1.database.oc1.iad..aaaaaaaaproddbazure67890"

# Object Storage Configuration (OPTIONAL for ONLINE_PHYSICAL to Oracle Database@Azure)
# Uncomment and set only if you need Object Storage staging
# export TARGET_OBJECT_STORAGE_NAMESPACE="examplecorp"

# Source OCI Configuration (if source is also in OCI - usually not needed)
# export SOURCE_TENANCY_OCID="ocid1.tenancy.oc1..aaaa..."
# export SOURCE_COMPARTMENT_OCID="ocid1.compartment.oc1..aaaa..."
# export SOURCE_DATABASE_OCID="ocid1.database.oc1..aaaa..."

echo "OCI environment variables loaded for PRODDB migration"
OCIEOF
        chmod 600 "${OCI_ENV_FILE}"
        echo "  ✓ Created ${OCI_ENV_FILE} with template values"
        echo ""
        echo "  ⚠️  IMPORTANT: Edit ${OCI_ENV_FILE} with your actual OCI OCIDs!"
    else
        echo "  ⚠️  ${OCI_ENV_FILE} already exists - not overwriting"
    fi
    
    # Verify ZDM installation
    echo ""
    echo "Verifying ZDM installation..."
    if [ -x "${ZDM_HOME}/bin/zdmcli" ]; then
        echo "  ✓ ZDM CLI found at ${ZDM_HOME}/bin/zdmcli"
        "${ZDM_HOME}/bin/zdmcli" -version 2>/dev/null || echo "  (version check skipped)"
    else
        echo "  ✗ ZDM CLI not found or not executable at ${ZDM_HOME}/bin/zdmcli"
        echo "    Please verify ZDM_HOME is set correctly"
    fi
    
    # Verify SSH key
    echo ""
    echo "Verifying SSH key..."
    if [ -f "${ZDM_MIG_SSH_KEY}" ]; then
        echo "  ✓ SSH key found at ${ZDM_MIG_SSH_KEY}"
    else
        echo "  ✗ SSH key not found at ${ZDM_MIG_SSH_KEY}"
        echo "    Please ensure the SSH key exists and is accessible"
    fi
    
    # Verify OCI API key
    echo ""
    echo "Verifying OCI API key..."
    if [ -f "${ZDM_MIG_OCI_KEY}" ]; then
        echo "  ✓ OCI API key found at ${ZDM_MIG_OCI_KEY}"
    else
        echo "  ✗ OCI API key not found at ${ZDM_MIG_OCI_KEY}"
        echo "    Please ensure the OCI API key exists"
    fi
    
    echo ""
    echo "=========================================="
    echo "INITIALIZATION COMPLETE"
    echo "=========================================="
    echo ""
    echo "Next steps:"
    echo "  1. Edit ${OCI_ENV_FILE} with your actual OCI OCIDs"
    echo "  2. Source the environment: source ${OCI_ENV_FILE}"
    echo "  3. Set password variables securely"
    echo "  4. Run evaluation: ./zdm_commands_PRODDB.sh eval"
    echo ""
}

# -------------------------------------------
# CREATE PASSWORD FILES
# -------------------------------------------
create_creds() {
    echo ""
    echo "=========================================="
    echo "CREATING PASSWORD FILES"
    echo "=========================================="
    echo ""
    
    # Validate password environment variables first
    validate_password_environment || return 1
    
    # Create credentials directory if not exists
    mkdir -p "${CREDS_DIR}"
    chmod 700 "${CREDS_DIR}"
    
    # Create source SYS password file
    echo "${SOURCE_SYS_PASSWORD}" > "${CREDS_DIR}/source_sys_password.txt"
    chmod 600 "${CREDS_DIR}/source_sys_password.txt"
    echo "  ✓ Created ${CREDS_DIR}/source_sys_password.txt"
    
    # Create target SYS password file
    echo "${TARGET_SYS_PASSWORD}" > "${CREDS_DIR}/target_sys_password.txt"
    chmod 600 "${CREDS_DIR}/target_sys_password.txt"
    echo "  ✓ Created ${CREDS_DIR}/target_sys_password.txt"
    
    # Create TDE password file if TDE is enabled
    if [ "${TDE_ENABLED}" = "true" ]; then
        echo "${SOURCE_TDE_WALLET_PASSWORD}" > "${CREDS_DIR}/tde_password.txt"
        chmod 600 "${CREDS_DIR}/tde_password.txt"
        echo "  ✓ Created ${CREDS_DIR}/tde_password.txt"
    fi
    
    echo ""
    echo "✓ Password files created in ${CREDS_DIR}"
    echo ""
    echo "  ⚠️  SECURITY: Remember to run 'cleanup-creds' after migration"
}

# -------------------------------------------
# CLEANUP PASSWORD FILES
# -------------------------------------------
cleanup_creds() {
    echo ""
    echo "=========================================="
    echo "CLEANING UP PASSWORD FILES"
    echo "=========================================="
    echo ""
    
    if [ -d "${CREDS_DIR}" ]; then
        if [ -f "${CREDS_DIR}/source_sys_password.txt" ]; then
            rm -f "${CREDS_DIR}/source_sys_password.txt"
            echo "  ✓ Removed source_sys_password.txt"
        fi
        if [ -f "${CREDS_DIR}/target_sys_password.txt" ]; then
            rm -f "${CREDS_DIR}/target_sys_password.txt"
            echo "  ✓ Removed target_sys_password.txt"
        fi
        if [ -f "${CREDS_DIR}/tde_password.txt" ]; then
            rm -f "${CREDS_DIR}/tde_password.txt"
            echo "  ✓ Removed tde_password.txt"
        fi
        echo ""
        echo "✓ Password files cleaned up"
    else
        echo "  No credentials directory found at ${CREDS_DIR}"
    fi
}

# -------------------------------------------
# GENERATE RSP FILE WITH SUBSTITUTED VARIABLES
# -------------------------------------------
generate_rsp() {
    echo ""
    echo "=========================================="
    echo "GENERATING RSP FILE WITH SUBSTITUTED VALUES"
    echo "=========================================="
    echo ""
    
    # Validate OCI environment first
    validate_oci_environment || return 1
    
    local template_rsp="${RSP_FILE}"
    local generated_rsp="${CREDS_DIR}/zdm_migrate_PRODDB_resolved.rsp"
    
    if [ ! -f "${template_rsp}" ]; then
        echo "ERROR: Template RSP file not found: ${template_rsp}"
        return 1
    fi
    
    # Use envsubst to substitute environment variables
    envsubst < "${template_rsp}" > "${generated_rsp}"
    chmod 600 "${generated_rsp}"
    
    echo "✓ RSP file generated: ${generated_rsp}"
    echo ""
    echo "Substituted values:"
    grep -E "^TARGET|^OCI" "${generated_rsp}" | head -10
}

# -------------------------------------------
# EVALUATION COMMAND
# -------------------------------------------
eval_migration() {
    echo ""
    echo "=========================================="
    echo "RUNNING ZDM MIGRATION EVALUATION"
    echo "=========================================="
    echo ""
    echo "Source: ${ZDM_MIG_SOURCE_DB} on ${ZDM_MIG_SOURCE_HOST}"
    echo "Target: ${ZDM_MIG_TARGET_DB} on ${ZDM_MIG_TARGET_HOST}"
    echo ""
    
    # Validate environment
    validate_oci_environment || return 1
    validate_password_environment || return 1
    
    # Check if password files exist
    if [ ! -f "${CREDS_DIR}/source_sys_password.txt" ]; then
        echo "ERROR: Password files not found. Run './zdm_commands_PRODDB.sh create-creds' first."
        return 1
    fi
    
    # Generate RSP with substituted values
    generate_rsp || return 1
    
    local resolved_rsp="${CREDS_DIR}/zdm_migrate_PRODDB_resolved.rsp"
    
    echo ""
    echo "Executing ZDM evaluation..."
    echo ""
    
    "${ZDM_HOME}/bin/zdmcli" migrate database \
        -sourcedb "${ZDM_MIG_SOURCE_DB}" \
        -sourcenode "${ZDM_MIG_SOURCE_HOST}" \
        -srcauth zdmauth \
        -srcarg1 user:"${ZDM_MIG_SOURCE_SSH_USER}" \
        -srcarg2 identity_file:"${ZDM_MIG_SSH_KEY}" \
        -srcarg3 sudo_location:/usr/bin/sudo \
        -targetnode "${ZDM_MIG_TARGET_HOST}" \
        -tgtauth zdmauth \
        -tgtarg1 user:"${ZDM_MIG_TARGET_SSH_USER}" \
        -tgtarg2 identity_file:"${ZDM_MIG_SSH_KEY}" \
        -tgtarg3 sudo_location:/usr/bin/sudo \
        -rsp "${resolved_rsp}" \
        -eval
    
    echo ""
    echo "Evaluation complete. Review the output above for any warnings or errors."
}

# -------------------------------------------
# MIGRATION COMMAND
# -------------------------------------------
run_migration() {
    echo ""
    echo "=========================================="
    echo "STARTING ZDM MIGRATION"
    echo "=========================================="
    echo ""
    echo "Source: ${ZDM_MIG_SOURCE_DB} on ${ZDM_MIG_SOURCE_HOST}"
    echo "Target: ${ZDM_MIG_TARGET_DB} on ${ZDM_MIG_TARGET_HOST}"
    echo "Migration Type: ONLINE_PHYSICAL (Data Guard)"
    echo "Pause Point: ZDM_CONFIGURE_DG_SRC"
    echo ""
    
    # Validate environment
    validate_oci_environment || return 1
    validate_password_environment || return 1
    
    # Check if password files exist
    if [ ! -f "${CREDS_DIR}/source_sys_password.txt" ]; then
        echo "ERROR: Password files not found. Run './zdm_commands_PRODDB.sh create-creds' first."
        return 1
    fi
    
    # Generate RSP with substituted values
    generate_rsp || return 1
    
    local resolved_rsp="${CREDS_DIR}/zdm_migrate_PRODDB_resolved.rsp"
    
    echo "⚠️  WARNING: This will start the actual migration process."
    echo "    The migration will PAUSE at ZDM_CONFIGURE_DG_SRC for validation."
    echo ""
    read -p "Continue with migration? (yes/no): " confirm
    
    if [ "${confirm}" != "yes" ]; then
        echo "Migration cancelled."
        return 1
    fi
    
    echo ""
    echo "Executing ZDM migration..."
    echo ""
    
    "${ZDM_HOME}/bin/zdmcli" migrate database \
        -sourcedb "${ZDM_MIG_SOURCE_DB}" \
        -sourcenode "${ZDM_MIG_SOURCE_HOST}" \
        -srcauth zdmauth \
        -srcarg1 user:"${ZDM_MIG_SOURCE_SSH_USER}" \
        -srcarg2 identity_file:"${ZDM_MIG_SSH_KEY}" \
        -srcarg3 sudo_location:/usr/bin/sudo \
        -targetnode "${ZDM_MIG_TARGET_HOST}" \
        -tgtauth zdmauth \
        -tgtarg1 user:"${ZDM_MIG_TARGET_SSH_USER}" \
        -tgtarg2 identity_file:"${ZDM_MIG_SSH_KEY}" \
        -tgtarg3 sudo_location:/usr/bin/sudo \
        -rsp "${resolved_rsp}"
    
    echo ""
    echo "Migration started. Use 'status <JOB_ID>' to monitor progress."
}

# -------------------------------------------
# STATUS COMMAND
# -------------------------------------------
check_status() {
    local job_id="$1"
    
    if [ -z "${job_id}" ]; then
        echo "Usage: ./zdm_commands_PRODDB.sh status <JOB_ID>"
        echo ""
        echo "To list all jobs:"
        "${ZDM_HOME}/bin/zdmcli" query job -all
        return 1
    fi
    
    echo ""
    echo "=========================================="
    echo "ZDM JOB STATUS: ${job_id}"
    echo "=========================================="
    echo ""
    
    "${ZDM_HOME}/bin/zdmcli" query job -jobid "${job_id}"
}

# -------------------------------------------
# DETAILED STATUS COMMAND
# -------------------------------------------
check_status_long() {
    local job_id="$1"
    
    if [ -z "${job_id}" ]; then
        echo "Usage: ./zdm_commands_PRODDB.sh status-long <JOB_ID>"
        return 1
    fi
    
    echo ""
    echo "=========================================="
    echo "ZDM JOB DETAILED STATUS: ${job_id}"
    echo "=========================================="
    echo ""
    
    "${ZDM_HOME}/bin/zdmcli" query job -jobid "${job_id}" -output long
}

# -------------------------------------------
# RESUME COMMAND
# -------------------------------------------
resume_job() {
    local job_id="$1"
    
    if [ -z "${job_id}" ]; then
        echo "Usage: ./zdm_commands_PRODDB.sh resume <JOB_ID>"
        return 1
    fi
    
    echo ""
    echo "=========================================="
    echo "RESUMING ZDM JOB: ${job_id}"
    echo "=========================================="
    echo ""
    
    echo "⚠️  WARNING: Resuming may trigger the switchover phase."
    echo "    Ensure you have validated the Data Guard sync status."
    echo ""
    read -p "Continue with resume? (yes/no): " confirm
    
    if [ "${confirm}" != "yes" ]; then
        echo "Resume cancelled."
        return 1
    fi
    
    "${ZDM_HOME}/bin/zdmcli" resume job -jobid "${job_id}"
}

# -------------------------------------------
# ABORT COMMAND (EMERGENCY)
# -------------------------------------------
abort_job() {
    local job_id="$1"
    
    if [ -z "${job_id}" ]; then
        echo "Usage: ./zdm_commands_PRODDB.sh abort <JOB_ID>"
        return 1
    fi
    
    echo ""
    echo "=========================================="
    echo "ABORTING ZDM JOB: ${job_id}"
    echo "=========================================="
    echo ""
    
    echo "⚠️  WARNING: This will ABORT the migration job."
    echo "    Use only in emergency situations."
    echo ""
    read -p "Are you sure you want to abort? (yes/no): " confirm
    
    if [ "${confirm}" != "yes" ]; then
        echo "Abort cancelled."
        return 1
    fi
    
    "${ZDM_HOME}/bin/zdmcli" abort job -jobid "${job_id}"
}

# -------------------------------------------
# LIST ALL JOBS
# -------------------------------------------
list_jobs() {
    echo ""
    echo "=========================================="
    echo "ALL ZDM JOBS"
    echo "=========================================="
    echo ""
    
    "${ZDM_HOME}/bin/zdmcli" query job -all
}

# -------------------------------------------
# HELP
# -------------------------------------------
show_help() {
    echo ""
    echo "ZDM Commands for PRODDB Migration"
    echo "=================================="
    echo ""
    echo "Usage: ./zdm_commands_PRODDB.sh <command> [options]"
    echo ""
    echo "Setup Commands:"
    echo "  init           Initialize environment (create ~/creds, ~/zdm_oci_env.sh)"
    echo "  create-creds   Create password files from environment variables"
    echo "  cleanup-creds  Remove password files (run after migration)"
    echo ""
    echo "Migration Commands:"
    echo "  eval           Run migration evaluation (dry run)"
    echo "  migrate        Start the actual migration"
    echo "  status <ID>    Check job status"
    echo "  status-long <ID>  Check detailed job status"
    echo "  resume <ID>    Resume a paused job"
    echo "  abort <ID>     Abort a running job (emergency)"
    echo "  jobs           List all jobs"
    echo ""
    echo "Before running migration:"
    echo "  1. Run: ./zdm_commands_PRODDB.sh init"
    echo "  2. Edit ~/zdm_oci_env.sh with your OCI OCIDs"
    echo "  3. Run: source ~/zdm_oci_env.sh"
    echo "  4. Set password environment variables"
    echo "  5. Run: ./zdm_commands_PRODDB.sh create-creds"
    echo "  6. Run: ./zdm_commands_PRODDB.sh eval"
    echo ""
}

# -------------------------------------------
# MAIN COMMAND ROUTER
# -------------------------------------------
case "${1:-help}" in
    init)
        init
        ;;
    create-creds)
        create_creds
        ;;
    cleanup-creds)
        cleanup_creds
        ;;
    generate-rsp)
        generate_rsp
        ;;
    eval)
        eval_migration
        ;;
    migrate)
        run_migration
        ;;
    status)
        check_status "$2"
        ;;
    status-long)
        check_status_long "$2"
        ;;
    resume)
        resume_job "$2"
        ;;
    abort)
        abort_job "$2"
        ;;
    jobs)
        list_jobs
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Unknown command: $1"
        show_help
        exit 1
        ;;
esac
