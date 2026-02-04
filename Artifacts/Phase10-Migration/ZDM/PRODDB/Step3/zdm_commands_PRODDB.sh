#!/bin/bash
# ===========================================
# ZDM CLI Commands Script
# Database: PRODDB
# Migration Type: ONLINE_PHYSICAL (Data Guard)
# Generated: 2026-02-04
# ===========================================
#
# IMPORTANT: Login Instructions
# =============================
# 1. SSH to ZDM server as your admin user (e.g., azureuser, opc):
#      ssh azureuser@zdm-jumpbox.corp.example.com
# 2. Switch to zdmuser:
#      sudo su - zdmuser
# 3. Navigate to this script's directory
# 4. Run init command on first use:
#      ./zdm_commands_PRODDB.sh init
# 5. Edit ~/zdm_oci_env.sh with actual OCID values
# 6. Source the OCI environment:
#      source ~/zdm_oci_env.sh
# 7. Run commands as needed
#
# Usage:
#   ./zdm_commands_PRODDB.sh <command> [options]
#
# Commands:
#   init          - First-time setup (creates ~/creds dir and ~/zdm_oci_env.sh)
#   eval          - Run evaluation (dry run)
#   migrate       - Execute migration
#   status <id>   - Query job status
#   resume <id>   - Resume paused job
#   abort <id>    - Abort job (emergency)
#   create-creds  - Create password files from environment variables
#   cleanup-creds - Clean up password files
#   preflight     - Run preflight checks
#   help          - Show this help message
#
# ===========================================

set -e

# -------------------------------------------
# Environment Variables (from discovery)
# -------------------------------------------
export ZDM_HOME="/opt/oracle/zdm21c"
export PATH="$ZDM_HOME/bin:$PATH"

# Source Database Configuration
export SOURCE_DB="PRODDB"
export SOURCE_DB_UNIQUE_NAME="PRODDB_PRIMARY"
export SOURCE_HOST="proddb01.corp.example.com"
export SOURCE_PORT="1521"
export SOURCE_SERVICE="PRODDB.corp.example.com"
export SOURCE_ORACLE_HOME="/u01/app/oracle/product/19.21.0/dbhome_1"
export SOURCE_SSH_USER="oracle"

# Target Database Configuration
export TARGET_DB="PRODDB"
export TARGET_DB_UNIQUE_NAME="PRODDB_AZURE"
export TARGET_HOST="proddb-oda.eastus.azure.example.com"
export TARGET_PORT="1521"
export TARGET_SERVICE="PRODDB_AZURE.eastus.azure.example.com"
export TARGET_ORACLE_HOME="/u02/app/oracle/product/19.0.0.0/dbhome_1"
export TARGET_SSH_USER="oracle"

# ZDM Server Configuration
export ZDM_USER="zdmuser"
export SSH_KEY="/home/zdmuser/.ssh/zdm_migration_key"
export SUDO_LOCATION="/usr/bin/sudo"

# OCI Configuration
export OCI_API_KEY="/home/zdmuser/.oci/oci_api_key.pem"
export OCI_REGION="us-ashburn-1"
export OCI_ENV_FILE="${HOME}/zdm_oci_env.sh"

# Credential Files
export CREDS_DIR="${HOME}/creds"
export SOURCE_SYS_PWD_FILE="${CREDS_DIR}/source_sys_password.txt"
export TARGET_SYS_PWD_FILE="${CREDS_DIR}/target_sys_password.txt"
export TDE_PWD_FILE="${CREDS_DIR}/tde_password.txt"

# RSP File Location
export RSP_FILE="$(dirname "$0")/zdm_migrate_PRODDB.rsp"
export RSP_FILE_READY="$(dirname "$0")/zdm_migrate_PRODDB_ready.rsp"

# TDE Configuration
export TDE_ENABLED="true"
export TDE_WALLET_LOCATION="/u01/app/oracle/admin/PRODDB/wallet/tde"

# Migration Options
export PAUSE_AFTER="ZDM_CONFIGURE_DG_SRC"

# -------------------------------------------
# Color Codes for Output
# -------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -------------------------------------------
# Helper Functions
# -------------------------------------------

print_header() {
    echo ""
    echo "=========================================="
    echo "$1"
    echo "=========================================="
    echo ""
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}! $1${NC}"
}

print_info() {
    echo -e "${BLUE}→ $1${NC}"
}

# -------------------------------------------
# OCI Environment Variable Validation
# -------------------------------------------

validate_oci_environment() {
    local missing_vars=()
    local errors=0
    
    print_header "VALIDATING OCI ENVIRONMENT VARIABLES"
    
    # Check TARGET_TENANCY_OCID
    if [ -z "${TARGET_TENANCY_OCID:-}" ]; then
        missing_vars+=("TARGET_TENANCY_OCID")
        ((errors++))
        print_error "TARGET_TENANCY_OCID is NOT set"
    else
        print_success "TARGET_TENANCY_OCID is set"
    fi
    
    # Check TARGET_USER_OCID
    if [ -z "${TARGET_USER_OCID:-}" ]; then
        missing_vars+=("TARGET_USER_OCID")
        ((errors++))
        print_error "TARGET_USER_OCID is NOT set"
    else
        print_success "TARGET_USER_OCID is set"
    fi
    
    # Check TARGET_FINGERPRINT
    if [ -z "${TARGET_FINGERPRINT:-}" ]; then
        missing_vars+=("TARGET_FINGERPRINT")
        ((errors++))
        print_error "TARGET_FINGERPRINT is NOT set"
    else
        print_success "TARGET_FINGERPRINT is set"
    fi
    
    # Check TARGET_COMPARTMENT_OCID
    if [ -z "${TARGET_COMPARTMENT_OCID:-}" ]; then
        missing_vars+=("TARGET_COMPARTMENT_OCID")
        ((errors++))
        print_error "TARGET_COMPARTMENT_OCID is NOT set"
    else
        print_success "TARGET_COMPARTMENT_OCID is set"
    fi
    
    # Check TARGET_DATABASE_OCID
    if [ -z "${TARGET_DATABASE_OCID:-}" ]; then
        missing_vars+=("TARGET_DATABASE_OCID")
        ((errors++))
        print_error "TARGET_DATABASE_OCID is NOT set"
    else
        print_success "TARGET_DATABASE_OCID is set"
    fi
    
    # Check TARGET_OBJECT_STORAGE_NAMESPACE (optional for ONLINE_PHYSICAL)
    if [ -z "${TARGET_OBJECT_STORAGE_NAMESPACE:-}" ]; then
        print_warning "TARGET_OBJECT_STORAGE_NAMESPACE is NOT set (optional for ONLINE_PHYSICAL)"
    else
        print_success "TARGET_OBJECT_STORAGE_NAMESPACE is set"
    fi
    
    if [ $errors -gt 0 ]; then
        echo ""
        print_error "The following OCI environment variables are not set:"
        printf '  - %s\n' "${missing_vars[@]}"
        echo ""
        echo "Please set these variables before running the migration script:"
        printf '  export %s="<value>"\n' "${missing_vars[@]}"
        echo ""
        echo "Obtain values from OCI Console:"
        echo "  - TARGET_TENANCY_OCID: Profile > Tenancy Details"
        echo "  - TARGET_USER_OCID: Profile > User Settings"
        echo "  - TARGET_FINGERPRINT: Profile > API Keys"
        echo "  - TARGET_COMPARTMENT_OCID: Identity > Compartments"
        echo "  - TARGET_DATABASE_OCID: Databases > Your Database"
        return 1
    fi
    
    print_success "All required OCI environment variables are set"
    return 0
}

# -------------------------------------------
# Password Environment Variable Validation
# -------------------------------------------

validate_password_environment() {
    local missing_vars=()
    local errors=0
    
    print_header "VALIDATING PASSWORD ENVIRONMENT VARIABLES"
    
    # Check SOURCE_SYS_PASSWORD
    if [ -z "${SOURCE_SYS_PASSWORD:-}" ]; then
        missing_vars+=("SOURCE_SYS_PASSWORD")
        ((errors++))
        print_error "SOURCE_SYS_PASSWORD is NOT set"
    else
        print_success "SOURCE_SYS_PASSWORD is set"
    fi
    
    # Check TARGET_SYS_PASSWORD
    if [ -z "${TARGET_SYS_PASSWORD:-}" ]; then
        missing_vars+=("TARGET_SYS_PASSWORD")
        ((errors++))
        print_error "TARGET_SYS_PASSWORD is NOT set"
    else
        print_success "TARGET_SYS_PASSWORD is set"
    fi
    
    # Check SOURCE_TDE_WALLET_PASSWORD (only if TDE is enabled)
    if [ "${TDE_ENABLED:-false}" = "true" ]; then
        if [ -z "${SOURCE_TDE_WALLET_PASSWORD:-}" ]; then
            missing_vars+=("SOURCE_TDE_WALLET_PASSWORD")
            ((errors++))
            print_error "SOURCE_TDE_WALLET_PASSWORD is NOT set (required - TDE is enabled)"
        else
            print_success "SOURCE_TDE_WALLET_PASSWORD is set"
        fi
    fi
    
    if [ $errors -gt 0 ]; then
        echo ""
        print_error "The following password environment variables are not set:"
        printf '  - %s\n' "${missing_vars[@]}"
        echo ""
        echo "For secure password entry, use:"
        echo '  read -sp "Enter Source SYS Password: " SOURCE_SYS_PASSWORD; echo; export SOURCE_SYS_PASSWORD'
        echo '  read -sp "Enter Target SYS Password: " TARGET_SYS_PASSWORD; echo; export TARGET_SYS_PASSWORD'
        if [ "${TDE_ENABLED:-false}" = "true" ]; then
            echo '  read -sp "Enter TDE Wallet Password: " SOURCE_TDE_WALLET_PASSWORD; echo; export SOURCE_TDE_WALLET_PASSWORD'
        fi
        return 1
    fi
    
    print_success "All required password environment variables are set"
    return 0
}

# -------------------------------------------
# Create Password Files from Environment
# -------------------------------------------

create_password_files() {
    print_header "CREATING PASSWORD FILES"
    
    # Validate password environment variables first
    validate_password_environment || return 1
    
    # Create credentials directory
    mkdir -p "${CREDS_DIR}"
    chmod 700 "${CREDS_DIR}"
    
    # Create password files from environment variables
    echo "${SOURCE_SYS_PASSWORD}" > "${SOURCE_SYS_PWD_FILE}"
    print_success "Created ${SOURCE_SYS_PWD_FILE}"
    
    echo "${TARGET_SYS_PASSWORD}" > "${TARGET_SYS_PWD_FILE}"
    print_success "Created ${TARGET_SYS_PWD_FILE}"
    
    if [ "${TDE_ENABLED:-false}" = "true" ]; then
        echo "${SOURCE_TDE_WALLET_PASSWORD}" > "${TDE_PWD_FILE}"
        print_success "Created ${TDE_PWD_FILE}"
    fi
    
    # Secure the files
    chmod 600 "${CREDS_DIR}"/*.txt
    
    echo ""
    print_success "Password files created in ${CREDS_DIR}"
    echo ""
    print_warning "Remember to clean up password files after migration:"
    echo "  ./zdm_commands_PRODDB.sh cleanup-creds"
    
    return 0
}

# -------------------------------------------
# Clean Up Password Files
# -------------------------------------------

cleanup_password_files() {
    print_header "CLEANING UP PASSWORD FILES"
    
    if [ -d "${CREDS_DIR}" ]; then
        if [ -f "${SOURCE_SYS_PWD_FILE}" ]; then
            rm -f "${SOURCE_SYS_PWD_FILE}"
            print_success "Removed ${SOURCE_SYS_PWD_FILE}"
        fi
        
        if [ -f "${TARGET_SYS_PWD_FILE}" ]; then
            rm -f "${TARGET_SYS_PWD_FILE}"
            print_success "Removed ${TARGET_SYS_PWD_FILE}"
        fi
        
        if [ -f "${TDE_PWD_FILE}" ]; then
            rm -f "${TDE_PWD_FILE}"
            print_success "Removed ${TDE_PWD_FILE}"
        fi
        
        print_success "Password files cleaned up"
    else
        print_info "Credentials directory does not exist: ${CREDS_DIR}"
    fi
    
    return 0
}

# -------------------------------------------
# First-Time Setup (init command)
# -------------------------------------------

init_environment() {
    print_header "FIRST-TIME SETUP"
    
    echo "This command will:"
    echo "  1. Create credentials directory (${CREDS_DIR})"
    echo "  2. Create OCI environment file template (${OCI_ENV_FILE})"
    echo ""
    
    # Create credentials directory
    if [ ! -d "${CREDS_DIR}" ]; then
        mkdir -p "${CREDS_DIR}"
        chmod 700 "${CREDS_DIR}"
        print_success "Created credentials directory: ${CREDS_DIR}"
    else
        print_info "Credentials directory already exists: ${CREDS_DIR}"
    fi
    
    # Create OCI environment file template
    if [ ! -f "${OCI_ENV_FILE}" ]; then
        cat > "${OCI_ENV_FILE}" << 'EOF'
#!/bin/bash
# ===========================================
# OCI Environment Variables for ZDM Migration
# Database: PRODDB
# Generated: $(date +%Y-%m-%d)
# ===========================================
#
# INSTRUCTIONS:
# 1. Edit this file with your actual OCID values
# 2. Save the file
# 3. Source it before running migration commands:
#      source ~/zdm_oci_env.sh
#
# HOW TO OBTAIN VALUES:
# - TARGET_TENANCY_OCID: OCI Console > Profile > Tenancy Details
# - TARGET_USER_OCID: OCI Console > Profile > User Settings
# - TARGET_FINGERPRINT: OCI Console > Profile > API Keys
# - TARGET_COMPARTMENT_OCID: OCI Console > Identity > Compartments
# - TARGET_DATABASE_OCID: OCI Console > Databases > Your Database
# - TARGET_OBJECT_STORAGE_NAMESPACE: OCI Console > Profile > Tenancy Details
#   (or run: oci os ns get)
#
# ===========================================

# Required OCI Configuration
export TARGET_TENANCY_OCID="ocid1.tenancy.oc1..____________________"
export TARGET_USER_OCID="ocid1.user.oc1..____________________"
export TARGET_FINGERPRINT="aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99"
export TARGET_COMPARTMENT_OCID="ocid1.compartment.oc1..____________________"
export TARGET_DATABASE_OCID="ocid1.database.oc1..____________________"

# Optional for ONLINE_PHYSICAL to Oracle Database@Azure
# (Object Storage is NOT required for ONLINE_PHYSICAL - uses direct Data Guard)
# Uncomment and set only if you need Object Storage staging
# export TARGET_OBJECT_STORAGE_NAMESPACE="your_namespace"

# Confirmation message when sourced
echo "OCI environment variables loaded from ~/zdm_oci_env.sh"
EOF
        chmod 600 "${OCI_ENV_FILE}"
        print_success "Created OCI environment file template: ${OCI_ENV_FILE}"
    else
        print_info "OCI environment file already exists: ${OCI_ENV_FILE}"
    fi
    
    echo ""
    print_header "NEXT STEPS"
    echo "1. Edit ${OCI_ENV_FILE} with your actual OCID values:"
    echo "     vi ${OCI_ENV_FILE}"
    echo ""
    echo "2. Source the OCI environment file:"
    echo "     source ${OCI_ENV_FILE}"
    echo ""
    echo "3. Set password environment variables:"
    echo "     read -sp 'Enter SOURCE_SYS_PASSWORD: ' SOURCE_SYS_PASSWORD; echo; export SOURCE_SYS_PASSWORD"
    echo "     read -sp 'Enter TARGET_SYS_PASSWORD: ' TARGET_SYS_PASSWORD; echo; export TARGET_SYS_PASSWORD"
    echo "     read -sp 'Enter SOURCE_TDE_WALLET_PASSWORD: ' SOURCE_TDE_WALLET_PASSWORD; echo; export SOURCE_TDE_WALLET_PASSWORD"
    echo ""
    echo "4. Create password files:"
    echo "     ./zdm_commands_PRODDB.sh create-creds"
    echo ""
    echo "5. Run preflight checks:"
    echo "     ./zdm_commands_PRODDB.sh preflight"
    echo ""
    
    return 0
}

# -------------------------------------------
# Generate RSP File with Substituted Variables
# -------------------------------------------

generate_rsp_file() {
    print_header "GENERATING RSP FILE WITH SUBSTITUTIONS"
    
    if [ ! -f "${RSP_FILE}" ]; then
        print_error "RSP template file not found: ${RSP_FILE}"
        return 1
    fi
    
    # Validate OCI environment first
    validate_oci_environment || return 1
    
    # Use envsubst to replace environment variables
    envsubst < "${RSP_FILE}" > "${RSP_FILE_READY}"
    
    print_success "RSP file generated: ${RSP_FILE_READY}"
    
    # Verify substitution worked (check for remaining ${...} patterns)
    if grep -q '\${' "${RSP_FILE_READY}"; then
        print_warning "Some environment variables may not be substituted:"
        grep '\${' "${RSP_FILE_READY}" | head -5
        echo ""
        print_warning "Please verify the generated RSP file before proceeding"
    fi
    
    return 0
}

# -------------------------------------------
# Verify Prerequisites
# -------------------------------------------

verify_prerequisites() {
    print_header "VERIFYING PREREQUISITES"
    local errors=0
    
    # Check ZDM_HOME
    if [ ! -d "${ZDM_HOME}" ]; then
        print_error "ZDM_HOME not found: ${ZDM_HOME}"
        ((errors++))
    else
        print_success "ZDM_HOME exists: ${ZDM_HOME}"
    fi
    
    # Check ZDM CLI
    if [ ! -x "${ZDM_HOME}/bin/zdmcli" ]; then
        print_error "ZDM CLI not executable: ${ZDM_HOME}/bin/zdmcli"
        ((errors++))
    else
        print_success "ZDM CLI is executable"
    fi
    
    # Check SSH key
    if [ ! -f "${SSH_KEY}" ]; then
        print_error "SSH key not found: ${SSH_KEY}"
        ((errors++))
    else
        print_success "SSH key exists: ${SSH_KEY}"
    fi
    
    # Check OCI API key
    if [ ! -f "${OCI_API_KEY}" ]; then
        print_error "OCI API key not found: ${OCI_API_KEY}"
        ((errors++))
    else
        print_success "OCI API key exists: ${OCI_API_KEY}"
    fi
    
    # Check RSP file
    if [ ! -f "${RSP_FILE}" ]; then
        print_error "RSP file not found: ${RSP_FILE}"
        ((errors++))
    else
        print_success "RSP file exists: ${RSP_FILE}"
    fi
    
    if [ $errors -gt 0 ]; then
        print_error "Prerequisites check failed with $errors error(s)"
        return 1
    fi
    
    print_success "All prerequisites verified"
    return 0
}

# -------------------------------------------
# Run Evaluation (Dry Run)
# -------------------------------------------

run_evaluation() {
    print_header "RUNNING ZDM EVALUATION (DRY RUN)"
    
    # Verify prerequisites
    verify_prerequisites || return 1
    
    # Validate OCI environment
    validate_oci_environment || return 1
    
    # Generate RSP file with substitutions
    generate_rsp_file || return 1
    
    print_info "Starting evaluation..."
    echo ""
    
    ${ZDM_HOME}/bin/zdmcli migrate database \
        -sourcesid ${SOURCE_DB} \
        -sourcenode ${SOURCE_HOST} \
        -srcauth zdmauth \
        -srcarg1 user:${SOURCE_SSH_USER} \
        -srcarg2 identity_file:${SSH_KEY} \
        -srcarg3 sudo_location:${SUDO_LOCATION} \
        -targetnode ${TARGET_HOST} \
        -tgtauth zdmauth \
        -tgtarg1 user:${TARGET_SSH_USER} \
        -tgtarg2 identity_file:${SSH_KEY} \
        -tgtarg3 sudo_location:${SUDO_LOCATION} \
        -rsp ${RSP_FILE_READY} \
        -eval
    
    local rc=$?
    
    echo ""
    if [ $rc -eq 0 ]; then
        print_success "Evaluation completed successfully"
        echo ""
        print_info "Review the evaluation results above"
        print_info "If successful, proceed with: ./zdm_commands_PRODDB.sh migrate"
    else
        print_error "Evaluation failed with exit code: $rc"
        print_info "Review the errors above and correct any issues before retrying"
    fi
    
    return $rc
}

# -------------------------------------------
# Execute Migration
# -------------------------------------------

run_migration() {
    print_header "EXECUTING ZDM MIGRATION"
    
    # Verify prerequisites
    verify_prerequisites || return 1
    
    # Validate OCI environment
    validate_oci_environment || return 1
    
    # Check if password files exist
    if [ ! -f "${SOURCE_SYS_PWD_FILE}" ] || [ ! -f "${TARGET_SYS_PWD_FILE}" ]; then
        print_error "Password files not found. Run 'create-creds' first:"
        echo "  ./zdm_commands_PRODDB.sh create-creds"
        return 1
    fi
    
    # Generate RSP file with substitutions
    generate_rsp_file || return 1
    
    print_info "Starting migration..."
    print_warning "Migration will pause at: ${PAUSE_AFTER}"
    print_warning "Use 'resume <JOB_ID>' to continue after validation"
    echo ""
    
    # Confirmation prompt
    read -p "Are you sure you want to start the migration? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        print_info "Migration cancelled"
        return 0
    fi
    
    ${ZDM_HOME}/bin/zdmcli migrate database \
        -sourcesid ${SOURCE_DB} \
        -sourcenode ${SOURCE_HOST} \
        -srcauth zdmauth \
        -srcarg1 user:${SOURCE_SSH_USER} \
        -srcarg2 identity_file:${SSH_KEY} \
        -srcarg3 sudo_location:${SUDO_LOCATION} \
        -targetnode ${TARGET_HOST} \
        -tgtauth zdmauth \
        -tgtarg1 user:${TARGET_SSH_USER} \
        -tgtarg2 identity_file:${SSH_KEY} \
        -tgtarg3 sudo_location:${SUDO_LOCATION} \
        -rsp ${RSP_FILE_READY} \
        -pauseafter ${PAUSE_AFTER}
    
    local rc=$?
    
    echo ""
    if [ $rc -eq 0 ]; then
        print_success "Migration job submitted successfully"
        echo ""
        print_info "IMPORTANT: Save the Job ID from the output above!"
        print_info "Monitor progress: ./zdm_commands_PRODDB.sh status <JOB_ID>"
        print_info "Resume after pause: ./zdm_commands_PRODDB.sh resume <JOB_ID>"
    else
        print_error "Migration submission failed with exit code: $rc"
    fi
    
    return $rc
}

# -------------------------------------------
# Query Job Status
# -------------------------------------------

query_status() {
    local job_id=$1
    
    if [ -z "${job_id}" ]; then
        print_error "Job ID required. Usage: ./zdm_commands_PRODDB.sh status <JOB_ID>"
        return 1
    fi
    
    print_header "QUERYING JOB STATUS: ${job_id}"
    
    ${ZDM_HOME}/bin/zdmcli query job -jobid ${job_id}
    
    return $?
}

# -------------------------------------------
# Resume Paused Job
# -------------------------------------------

resume_job() {
    local job_id=$1
    
    if [ -z "${job_id}" ]; then
        print_error "Job ID required. Usage: ./zdm_commands_PRODDB.sh resume <JOB_ID>"
        return 1
    fi
    
    print_header "RESUMING JOB: ${job_id}"
    
    # Confirmation prompt
    print_warning "This will resume the migration and may initiate SWITCHOVER"
    read -p "Are you sure you want to resume job ${job_id}? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        print_info "Resume cancelled"
        return 0
    fi
    
    ${ZDM_HOME}/bin/zdmcli resume job -jobid ${job_id}
    
    local rc=$?
    
    if [ $rc -eq 0 ]; then
        print_success "Job resumed successfully"
        print_info "Monitor progress: ./zdm_commands_PRODDB.sh status ${job_id}"
    else
        print_error "Resume failed with exit code: $rc"
    fi
    
    return $rc
}

# -------------------------------------------
# Abort Job (Emergency)
# -------------------------------------------

abort_job() {
    local job_id=$1
    
    if [ -z "${job_id}" ]; then
        print_error "Job ID required. Usage: ./zdm_commands_PRODDB.sh abort <JOB_ID>"
        return 1
    fi
    
    print_header "ABORTING JOB: ${job_id}"
    
    print_error "WARNING: This will abort the migration job!"
    print_warning "Data Guard configuration may need manual cleanup"
    read -p "Are you SURE you want to abort job ${job_id}? (type ABORT to confirm): " confirm
    if [ "$confirm" != "ABORT" ]; then
        print_info "Abort cancelled"
        return 0
    fi
    
    ${ZDM_HOME}/bin/zdmcli abort job -jobid ${job_id}
    
    local rc=$?
    
    if [ $rc -eq 0 ]; then
        print_success "Job aborted"
        print_warning "Review cleanup requirements in the runbook"
    else
        print_error "Abort failed with exit code: $rc"
    fi
    
    return $rc
}

# -------------------------------------------
# List All Jobs
# -------------------------------------------

list_jobs() {
    print_header "LISTING ALL ZDM JOBS"
    
    ${ZDM_HOME}/bin/zdmcli query jobs
    
    return $?
}

# -------------------------------------------
# Show Help
# -------------------------------------------

show_help() {
    echo ""
    echo "ZDM Migration Script for PRODDB"
    echo "================================"
    echo ""
    echo "Usage: ./zdm_commands_PRODDB.sh <command> [options]"
    echo ""
    echo "IMPORTANT: Login Instructions"
    echo "-----------------------------"
    echo "1. SSH as admin user:    ssh azureuser@zdm-jumpbox.corp.example.com"
    echo "2. Switch to zdmuser:    sudo su - zdmuser"
    echo "3. Navigate to script:   cd /path/to/Step3"
    echo "4. Run init (first use): ./zdm_commands_PRODDB.sh init"
    echo ""
    echo "Commands:"
    echo "  init            First-time setup (creates ~/creds and ~/zdm_oci_env.sh)"
    echo "  eval            Run evaluation (dry run) - always run this first"
    echo "  migrate         Execute migration"
    echo "  status <id>     Query job status"
    echo "  resume <id>     Resume paused job"
    echo "  abort <id>      Abort job (emergency)"
    echo "  list-jobs       List all ZDM jobs"
    echo "  create-creds    Create password files from environment variables"
    echo "  cleanup-creds   Clean up password files"
    echo "  preflight       Verify prerequisites and OCI environment"
    echo "  help            Show this help message"
    echo ""
    echo "Typical workflow:"
    echo "  1. ./zdm_commands_PRODDB.sh init                   (first time only)"
    echo "  2. vi ~/zdm_oci_env.sh                              (edit with actual OCIDs)"
    echo "  3. source ~/zdm_oci_env.sh                          (load OCI env vars)"
    echo "  4. Set password env vars (see below)"
    echo "  5. ./zdm_commands_PRODDB.sh create-creds"
    echo "  6. ./zdm_commands_PRODDB.sh preflight"
    echo "  7. ./zdm_commands_PRODDB.sh eval"
    echo "  8. ./zdm_commands_PRODDB.sh migrate"
    echo "  9. ./zdm_commands_PRODDB.sh status <JOB_ID>"
    echo "  10. (After validation) ./zdm_commands_PRODDB.sh resume <JOB_ID>"
    echo "  11. ./zdm_commands_PRODDB.sh cleanup-creds"
    echo ""
    echo "Setting password environment variables (secure entry):"
    echo "  read -sp 'Enter Source SYS Password: ' SOURCE_SYS_PASSWORD; echo; export SOURCE_SYS_PASSWORD"
    echo "  read -sp 'Enter Target SYS Password: ' TARGET_SYS_PASSWORD; echo; export TARGET_SYS_PASSWORD"
    echo "  read -sp 'Enter TDE Wallet Password: ' SOURCE_TDE_WALLET_PASSWORD; echo; export SOURCE_TDE_WALLET_PASSWORD"
    echo ""
}

# -------------------------------------------
# Main Entry Point
# -------------------------------------------

main() {
    local command="${1:-help}"
    local arg2="${2:-}"
    
    case "$command" in
        init|setup)
            init_environment
            ;;
        eval|evaluate)
            run_evaluation
            ;;
        migrate|migration)
            run_migration
            ;;
        status|query)
            query_status "$arg2"
            ;;
        resume)
            resume_job "$arg2"
            ;;
        abort)
            abort_job "$arg2"
            ;;
        list-jobs|jobs)
            list_jobs
            ;;
        create-creds|creds)
            create_password_files
            ;;
        cleanup-creds|cleanup)
            cleanup_password_files
            ;;
        preflight|verify)
# Run main function with all arguments
main "$@"
