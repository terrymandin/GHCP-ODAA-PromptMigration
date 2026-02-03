#!/bin/bash
# ===========================================
# ZDM CLI Commands
# Database: PRODDB (oradb01)
# Migration Type: ONLINE_PHYSICAL
# Generated: 2026-02-03
# ===========================================

# -------------------------------------------
# ENVIRONMENT VARIABLES
# -------------------------------------------
export ZDM_HOME="/u01/app/zdmhome"
export PATH="$ZDM_HOME/bin:$PATH"

# Source Database Configuration
export SOURCE_DB="oradb01"
export SOURCE_DB_UNIQUE_NAME="oradb01"
export SOURCE_HOST="temandin-oravm-vm01"
export SOURCE_IP="10.1.0.10"
export SOURCE_PORT="1521"
export SOURCE_ORACLE_HOME="/u01/app/oracle/product/19.0.0/dbhome_1"
export SOURCE_SSH_USER="azureuser"
export SOURCE_SSH_KEY="/home/zdmuser/.ssh/zdm.pem"

# Target Database Configuration
export TARGET_HOST="tmodaauks-rqahk1"
export TARGET_IP="10.0.1.160"
export TARGET_PORT="1521"
export TARGET_ORACLE_HOME="/u02/app/oracle/product/19.0.0.0/dbhome_1"
export TARGET_SSH_USER="opc"
export TARGET_SSH_KEY="/home/zdmuser/.ssh/odaa.pem"

# ZDM Configuration
export RSP_FILE="${HOME}/step3/zdm_migrate_PRODDB.rsp"
export CREDS_DIR="${HOME}/creds"
export TDE_WALLET_LOCATION="/u01/app/oracle/admin/oradb01/wallet/tde/"

# TDE Enabled Flag (set based on source database)
export TDE_ENABLED="true"

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
    if [ "${TDE_ENABLED:-false}" = "true" ]; then
        if [ -z "${SOURCE_TDE_WALLET_PASSWORD:-}" ]; then
            missing_vars+=("SOURCE_TDE_WALLET_PASSWORD")
            ((errors++))
            echo "  ✗ SOURCE_TDE_WALLET_PASSWORD is NOT set (TDE is enabled)"
        else
            echo "  ✓ SOURCE_TDE_WALLET_PASSWORD is set"
        fi
    else
        echo "  ℹ TDE is not enabled, skipping TDE password check"
    fi
    
    if [ $errors -gt 0 ]; then
        echo ""
        echo "=========================================="
        echo "ERROR: Missing required password variables"
        echo "=========================================="
        echo ""
        echo "The following required password environment variables are not set:"
        printf '  - %s\n' "${missing_vars[@]}"
        echo ""
        echo "Please set these variables before running the migration script:"
        echo ""
        echo "  # Secure password entry (recommended):"
        echo "  read -sp \"Enter Source SYS Password: \" SOURCE_SYS_PASSWORD; echo"
        echo "  export SOURCE_SYS_PASSWORD"
        echo ""
        echo "  read -sp \"Enter Target SYS Password: \" TARGET_SYS_PASSWORD; echo"
        echo "  export TARGET_SYS_PASSWORD"
        echo ""
        if [ "${TDE_ENABLED:-false}" = "true" ]; then
            echo "  read -sp \"Enter TDE Wallet Password: \" SOURCE_TDE_WALLET_PASSWORD; echo"
            echo "  export SOURCE_TDE_WALLET_PASSWORD"
            echo ""
        fi
        echo "=========================================="
        return 1
    fi
    
    echo ""
    echo "✓ All required password environment variables are set"
    echo ""
    return 0
}

# -------------------------------------------
# PASSWORD FILE MANAGEMENT
# -------------------------------------------

create_password_files() {
    echo ""
    echo "Creating password files..."
    
    # Validate environment variables first
    validate_password_environment || return 1
    
    # Create credentials directory
    mkdir -p "$CREDS_DIR"
    chmod 700 "$CREDS_DIR"
    
    # Create password files from environment variables
    echo "$SOURCE_SYS_PASSWORD" > "$CREDS_DIR/source_sys_password.txt"
    chmod 600 "$CREDS_DIR/source_sys_password.txt"
    echo "  ✓ Created source_sys_password.txt"
    
    echo "$TARGET_SYS_PASSWORD" > "$CREDS_DIR/target_sys_password.txt"
    chmod 600 "$CREDS_DIR/target_sys_password.txt"
    echo "  ✓ Created target_sys_password.txt"
    
    if [ "${TDE_ENABLED:-false}" = "true" ]; then
        echo "$SOURCE_TDE_WALLET_PASSWORD" > "$CREDS_DIR/tde_password.txt"
        chmod 600 "$CREDS_DIR/tde_password.txt"
        echo "  ✓ Created tde_password.txt"
    fi
    
    echo ""
    echo "✓ Password files created in $CREDS_DIR"
    echo ""
}

cleanup_password_files() {
    echo ""
    echo "Cleaning up password files..."
    
    if [ -d "$CREDS_DIR" ]; then
        rm -f "$CREDS_DIR/source_sys_password.txt"
        rm -f "$CREDS_DIR/target_sys_password.txt"
        rm -f "$CREDS_DIR/tde_password.txt"
        echo "  ✓ Password files removed"
    else
        echo "  ℹ Credentials directory does not exist"
    fi
    
    echo ""
}

# -------------------------------------------
# PRE-FLIGHT CHECKS
# -------------------------------------------

run_preflight_checks() {
    echo ""
    echo "=========================================="
    echo "RUNNING PRE-FLIGHT CHECKS"
    echo "=========================================="
    echo ""
    
    local errors=0
    
    # Check ZDM installation
    echo "Checking ZDM installation..."
    if [ -x "$ZDM_HOME/bin/zdmcli" ]; then
        echo "  ✓ ZDM CLI found at $ZDM_HOME/bin/zdmcli"
    else
        echo "  ✗ ZDM CLI not found or not executable"
        ((errors++))
    fi
    
    # Check RSP file
    echo "Checking RSP file..."
    if [ -f "$RSP_FILE" ]; then
        echo "  ✓ RSP file found at $RSP_FILE"
        
        # Check for placeholders
        if grep -q '<YOUR_' "$RSP_FILE" || grep -q '<TARGET_' "$RSP_FILE" || grep -q '<OBJECT_' "$RSP_FILE"; then
            echo "  ⚠ WARNING: RSP file contains placeholder values that need to be replaced"
            echo "    Run: grep '<' $RSP_FILE"
        fi
    else
        echo "  ✗ RSP file not found at $RSP_FILE"
        ((errors++))
    fi
    
    # Check SSH keys
    echo "Checking SSH keys..."
    if [ -f "$SOURCE_SSH_KEY" ]; then
        echo "  ✓ Source SSH key found"
    else
        echo "  ✗ Source SSH key not found at $SOURCE_SSH_KEY"
        ((errors++))
    fi
    
    if [ -f "$TARGET_SSH_KEY" ]; then
        echo "  ✓ Target SSH key found"
    else
        echo "  ✗ Target SSH key not found at $TARGET_SSH_KEY"
        ((errors++))
    fi
    
    # Check OCI configuration
    echo "Checking OCI configuration..."
    if [ -f "${HOME}/.oci/config" ]; then
        echo "  ✓ OCI config found"
        if oci os ns get --query 'data' --raw-output >/dev/null 2>&1; then
            echo "  ✓ OCI connectivity verified"
        else
            echo "  ⚠ WARNING: OCI connectivity test failed"
        fi
    else
        echo "  ✗ OCI config not found at ${HOME}/.oci/config"
        ((errors++))
    fi
    
    # Check disk space
    echo "Checking disk space..."
    local available_gb=$(df -BG "$ZDM_HOME" | tail -1 | awk '{print $4}' | tr -d 'G')
    if [ "$available_gb" -ge 20 ]; then
        echo "  ✓ Sufficient disk space: ${available_gb}GB available"
    else
        echo "  ⚠ WARNING: Low disk space: ${available_gb}GB available (20GB recommended)"
    fi
    
    echo ""
    if [ $errors -gt 0 ]; then
        echo "=========================================="
        echo "PRE-FLIGHT CHECKS FAILED: $errors error(s)"
        echo "=========================================="
        return 1
    else
        echo "=========================================="
        echo "PRE-FLIGHT CHECKS PASSED"
        echo "=========================================="
        return 0
    fi
}

# -------------------------------------------
# ZDM EVALUATION COMMAND
# -------------------------------------------

run_evaluation() {
    echo ""
    echo "=========================================="
    echo "RUNNING ZDM EVALUATION (DRY RUN)"
    echo "=========================================="
    echo ""
    
    # Validate passwords and create files
    create_password_files || return 1
    
    # Run pre-flight checks
    run_preflight_checks || return 1
    
    echo "Starting evaluation..."
    echo ""
    
    $ZDM_HOME/bin/zdmcli migrate database \
        -rsp "$RSP_FILE" \
        -sourcedb "$SOURCE_DB" \
        -sourcenode "$SOURCE_HOST" \
        -srcauth zdmauth \
        -srcarg1 user:$SOURCE_SSH_USER \
        -srcarg2 identity_file:$SOURCE_SSH_KEY \
        -srcarg3 sudo_location:/usr/bin/sudo \
        -targetnode "$TARGET_HOST" \
        -tgtauth zdmauth \
        -tgtarg1 user:$TARGET_SSH_USER \
        -tgtarg2 identity_file:$TARGET_SSH_KEY \
        -tgtarg3 sudo_location:/usr/bin/sudo \
        -tdekeyloc "$TDE_WALLET_LOCATION" \
        -sourcesyswallet "$CREDS_DIR/source_sys_password.txt" \
        -eval
    
    local result=$?
    
    # Cleanup password files after evaluation
    cleanup_password_files
    
    return $result
}

# -------------------------------------------
# ZDM MIGRATION COMMAND
# -------------------------------------------

run_migration() {
    echo ""
    echo "=========================================="
    echo "RUNNING ZDM MIGRATION"
    echo "=========================================="
    echo ""
    echo "⚠ WARNING: This will start the actual migration!"
    echo "  - Source Database: $SOURCE_DB on $SOURCE_HOST"
    echo "  - Target: Oracle Database@Azure on $TARGET_HOST"
    echo "  - Migration will pause before switchover for validation"
    echo ""
    read -p "Do you want to proceed? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        echo "Migration cancelled."
        return 1
    fi
    
    # Validate passwords and create files
    create_password_files || return 1
    
    # Run pre-flight checks
    run_preflight_checks || return 1
    
    echo ""
    echo "Starting migration..."
    echo ""
    
    $ZDM_HOME/bin/zdmcli migrate database \
        -rsp "$RSP_FILE" \
        -sourcedb "$SOURCE_DB" \
        -sourcenode "$SOURCE_HOST" \
        -srcauth zdmauth \
        -srcarg1 user:$SOURCE_SSH_USER \
        -srcarg2 identity_file:$SOURCE_SSH_KEY \
        -srcarg3 sudo_location:/usr/bin/sudo \
        -targetnode "$TARGET_HOST" \
        -tgtauth zdmauth \
        -tgtarg1 user:$TARGET_SSH_USER \
        -tgtarg2 identity_file:$TARGET_SSH_KEY \
        -tgtarg3 sudo_location:/usr/bin/sudo \
        -tdekeyloc "$TDE_WALLET_LOCATION" \
        -sourcesyswallet "$CREDS_DIR/source_sys_password.txt" \
        -targetsyswallet "$CREDS_DIR/target_sys_password.txt" \
        -tdepassword "$CREDS_DIR/tde_password.txt" \
        -pauseafter ZDM_SWITCHOVER_SRC
    
    local result=$?
    
    echo ""
    echo "=========================================="
    echo "Migration initiated. Note the JOB_ID above."
    echo "Use 'status <JOB_ID>' to monitor progress."
    echo "=========================================="
    echo ""
    echo "⚠ Password files are still present in $CREDS_DIR"
    echo "   Run 'cleanup' after migration completes to remove them."
    
    return $result
}

# -------------------------------------------
# JOB STATUS COMMAND
# -------------------------------------------

query_job_status() {
    local job_id=$1
    
    if [ -z "$job_id" ]; then
        echo ""
        echo "Usage: $0 status <JOB_ID>"
        echo ""
        echo "To list all jobs:"
        $ZDM_HOME/bin/zdmcli query job -listall
        return 1
    fi
    
    echo ""
    echo "=========================================="
    echo "JOB STATUS: $job_id"
    echo "=========================================="
    echo ""
    
    $ZDM_HOME/bin/zdmcli query job -jobid "$job_id"
}

# -------------------------------------------
# RESUME JOB COMMAND
# -------------------------------------------

resume_job() {
    local job_id=$1
    
    if [ -z "$job_id" ]; then
        echo "Usage: $0 resume <JOB_ID>"
        return 1
    fi
    
    echo ""
    echo "=========================================="
    echo "RESUMING JOB: $job_id"
    echo "=========================================="
    echo ""
    echo "⚠ WARNING: This will resume the migration and proceed with switchover!"
    echo "  Ensure all validations are complete before proceeding."
    echo ""
    read -p "Do you want to resume? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        echo "Resume cancelled."
        return 1
    fi
    
    $ZDM_HOME/bin/zdmcli resume job -jobid "$job_id"
}

# -------------------------------------------
# ABORT JOB COMMAND
# -------------------------------------------

abort_job() {
    local job_id=$1
    
    if [ -z "$job_id" ]; then
        echo "Usage: $0 abort <JOB_ID>"
        return 1
    fi
    
    echo ""
    echo "=========================================="
    echo "ABORTING JOB: $job_id"
    echo "=========================================="
    echo ""
    echo "⚠ WARNING: This will abort the migration!"
    echo ""
    read -p "Are you sure you want to abort? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        echo "Abort cancelled."
        return 1
    fi
    
    $ZDM_HOME/bin/zdmcli abort job -jobid "$job_id"
    
    # Cleanup password files
    cleanup_password_files
}

# -------------------------------------------
# SUSPEND JOB COMMAND
# -------------------------------------------

suspend_job() {
    local job_id=$1
    
    if [ -z "$job_id" ]; then
        echo "Usage: $0 suspend <JOB_ID>"
        return 1
    fi
    
    echo ""
    echo "Suspending job: $job_id"
    echo ""
    
    $ZDM_HOME/bin/zdmcli suspend job -jobid "$job_id"
}

# -------------------------------------------
# LIST ALL JOBS COMMAND
# -------------------------------------------

list_jobs() {
    echo ""
    echo "=========================================="
    echo "ALL ZDM JOBS"
    echo "=========================================="
    echo ""
    
    $ZDM_HOME/bin/zdmcli query job -listall
}

# -------------------------------------------
# HELP COMMAND
# -------------------------------------------

show_help() {
    echo ""
    echo "=========================================="
    echo "ZDM Migration Commands for PRODDB"
    echo "=========================================="
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  preflight           Run pre-flight checks"
    echo "  eval                Run migration evaluation (dry run)"
    echo "  migrate             Start the actual migration"
    echo "  status <JOB_ID>     Query job status"
    echo "  list                List all jobs"
    echo "  resume <JOB_ID>     Resume a paused job"
    echo "  suspend <JOB_ID>    Suspend a running job"
    echo "  abort <JOB_ID>      Abort a running job"
    echo "  cleanup             Remove password files"
    echo "  help                Show this help message"
    echo ""
    echo "Before running migration, set password environment variables:"
    echo ""
    echo "  export SOURCE_SYS_PASSWORD='<password>'"
    echo "  export TARGET_SYS_PASSWORD='<password>'"
    echo "  export SOURCE_TDE_WALLET_PASSWORD='<password>'"
    echo ""
    echo "For secure password entry (recommended):"
    echo ""
    echo "  read -sp \"Enter Source SYS Password: \" SOURCE_SYS_PASSWORD; echo"
    echo "  export SOURCE_SYS_PASSWORD"
    echo ""
    echo "=========================================="
}

# -------------------------------------------
# MAIN COMMAND HANDLER
# -------------------------------------------

case "${1:-help}" in
    preflight)
        run_preflight_checks
        ;;
    eval|evaluate)
        run_evaluation
        ;;
    migrate|run)
        run_migration
        ;;
    status|query)
        query_job_status "$2"
        ;;
    list|listall)
        list_jobs
        ;;
    resume)
        resume_job "$2"
        ;;
    suspend)
        suspend_job "$2"
        ;;
    abort)
        abort_job "$2"
        ;;
    cleanup)
        cleanup_password_files
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

# ===========================================
# END OF SCRIPT
# ===========================================
