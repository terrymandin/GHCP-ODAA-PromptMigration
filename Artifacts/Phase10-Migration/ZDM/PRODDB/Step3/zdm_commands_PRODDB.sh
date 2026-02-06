#!/bin/bash
#################################################################################
# ZDM Commands Script: PRODDB Migration
# Database: ORADB01 → Oracle Database@Azure
# Type: ONLINE_PHYSICAL
# Generated: February 5, 2026
#
# Usage:
#   ./zdm_commands_PRODDB.sh <command> [options]
#
# Commands:
#   init          - Initialize directories and environment template
#   create-creds  - Create password files from environment variables
#   cleanup-creds - Remove password files
#   eval          - Run migration evaluation (dry run)
#   migrate       - Execute the migration
#   status <id>   - Check job status
#   resume <id>   - Resume paused job
#   abort <id>    - Abort running job
#   query <id>    - Query detailed job information
#   help          - Show this help message
#################################################################################

set -e

#--------------------------------------------------------------------------------
# CONFIGURATION - Environment Variables
#--------------------------------------------------------------------------------

# ZDM Installation
ZDM_HOME="${ZDM_HOME:-/u01/app/zdmhome}"
ZDM_CLI="$ZDM_HOME/bin/zdmcli"

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RSP_FILE="${SCRIPT_DIR}/zdm_migrate_PRODDB.rsp"

# Credentials directory
CREDS_DIR="${HOME}/creds"

# OCI environment file
OCI_ENV_FILE="${HOME}/zdm_oci_env.sh"

#--------------------------------------------------------------------------------
# SOURCE DATABASE CONFIGURATION
#--------------------------------------------------------------------------------

SOURCEDB_DBNAME="oradb01"
SOURCEDB_UNIQUENAME="oradb01"
SOURCEDB_ORACLEHOME="/u01/app/oracle/product/19.0.0/dbhome_1"
SOURCENODE_HOST="temandin-oravm-vm01"
SOURCENODE_USER="oracle"
SOURCENODE_SSHPRIVATEKEY="/home/zdmuser/.ssh/zdm.pem"
SOURCEDB_PWDFILE="${SOURCEDB_ORACLEHOME}/dbs/orapworadb01"

# TDE Configuration
SOURCETDE_WALLETPATH="/u01/app/oracle/admin/oradb01/wallet/tde/"

#--------------------------------------------------------------------------------
# TARGET DATABASE CONFIGURATION
#--------------------------------------------------------------------------------

TARGETDB_UNIQUENAME="oradb01_oda"
TARGETDB_ORACLEHOME="/u02/app/oracle/product/19.0.0.0/dbhome_1"
TARGETNODE_HOST="tmodaauks-rqahk1"
TARGETNODE_USER="opc"
TARGETNODE_SSHPRIVATEKEY="/home/zdmuser/.ssh/odaa.pem"

# Target ASM Disk Groups
TARGET_DATADG="+DATAC3"
TARGET_RECODG="+RECOC3"

# Target SCAN
TARGET_SCAN="tmodaauks-rqahk-scan.odaaprisubnt.valoiaodaamain.oraclevcn.com"

#--------------------------------------------------------------------------------
# MIGRATION OPTIONS
#--------------------------------------------------------------------------------

MIGRATION_METHOD="ONLINE_PHYSICAL"
DG_PROTECTION_MODE="MAXIMUM_PERFORMANCE"
DG_REDO_TRANSPORT="ASYNC"
PAUSE_PHASE="ZDM_SWITCHOVER_SRC"

#--------------------------------------------------------------------------------
# OCI CONFIGURATION (from environment variables)
#--------------------------------------------------------------------------------

# These should be set via environment variables or ~/zdm_oci_env.sh:
# - TARGET_TENANCY_OCID
# - TARGET_USER_OCID
# - TARGET_FINGERPRINT
# - TARGET_COMPARTMENT_OCID
# - TARGET_DATABASE_OCID

OCI_API_KEY="/home/zdmuser/.oci/oci_api_key.pem"
OCI_REGION="uk-south-1"

#--------------------------------------------------------------------------------
# HELPER FUNCTIONS
#--------------------------------------------------------------------------------

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $*"
}

check_zdm() {
    if [ ! -f "$ZDM_CLI" ]; then
        log_error "ZDM CLI not found at: $ZDM_CLI"
        log_error "Please verify ZDM_HOME is set correctly: $ZDM_HOME"
        exit 1
    fi
}

check_oci_env() {
    local missing=0
    
    if [ -z "$TARGET_TENANCY_OCID" ]; then
        log_error "TARGET_TENANCY_OCID not set"
        missing=1
    fi
    
    if [ -z "$TARGET_USER_OCID" ]; then
        log_error "TARGET_USER_OCID not set"
        missing=1
    fi
    
    if [ -z "$TARGET_FINGERPRINT" ]; then
        log_error "TARGET_FINGERPRINT not set"
        missing=1
    fi
    
    if [ -z "$TARGET_COMPARTMENT_OCID" ]; then
        log_error "TARGET_COMPARTMENT_OCID not set"
        missing=1
    fi
    
    if [ -z "$TARGET_DATABASE_OCID" ]; then
        log_error "TARGET_DATABASE_OCID not set"
        missing=1
    fi
    
    if [ $missing -eq 1 ]; then
        log_error "Please set OCI environment variables or source ~/zdm_oci_env.sh"
        exit 1
    fi
}

check_password_env() {
    local missing=0
    
    if [ -z "$SOURCE_SYS_PASSWORD" ]; then
        log_error "SOURCE_SYS_PASSWORD not set"
        missing=1
    fi
    
    if [ -z "$TARGET_SYS_PASSWORD" ]; then
        log_error "TARGET_SYS_PASSWORD not set"
        missing=1
    fi
    
    if [ -z "$SOURCE_TDE_WALLET_PASSWORD" ]; then
        log_error "SOURCE_TDE_WALLET_PASSWORD not set"
        missing=1
    fi
    
    if [ $missing -eq 1 ]; then
        log_error "Please set password environment variables"
        log_info "Use: read -sp 'Password: ' VAR; export VAR"
        exit 1
    fi
}

check_creds_files() {
    local missing=0
    
    if [ ! -f "${CREDS_DIR}/source_sys_password.txt" ]; then
        log_error "Source SYS password file not found"
        missing=1
    fi
    
    if [ ! -f "${CREDS_DIR}/target_sys_password.txt" ]; then
        log_error "Target SYS password file not found"
        missing=1
    fi
    
    if [ ! -f "${CREDS_DIR}/tde_password.txt" ]; then
        log_error "TDE password file not found"
        missing=1
    fi
    
    if [ $missing -eq 1 ]; then
        log_error "Please run: $0 create-creds"
        exit 1
    fi
}

#--------------------------------------------------------------------------------
# COMMAND FUNCTIONS
#--------------------------------------------------------------------------------

cmd_init() {
    log_info "Initializing ZDM environment for PRODDB migration..."
    
    # Create credentials directory
    if [ ! -d "$CREDS_DIR" ]; then
        mkdir -p "$CREDS_DIR"
        chmod 700 "$CREDS_DIR"
        log_info "Created credentials directory: $CREDS_DIR"
    else
        log_info "Credentials directory exists: $CREDS_DIR"
    fi
    
    # Create OCI environment template
    if [ ! -f "$OCI_ENV_FILE" ]; then
        cat > "$OCI_ENV_FILE" << 'OCIENV'
#!/bin/bash
#################################################################################
# OCI Environment Variables for PRODDB Migration
# Edit this file with your actual OCI OCIDs
# Then run: source ~/zdm_oci_env.sh
#################################################################################

# Required: Your OCI tenancy OCID
export TARGET_TENANCY_OCID="ocid1.tenancy.oc1..your-tenancy-ocid"

# Required: Your OCI user OCID (user with API key configured)
export TARGET_USER_OCID="ocid1.user.oc1..your-user-ocid"

# Required: API key fingerprint (from OCI console)
export TARGET_FINGERPRINT="aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99"

# Required: Compartment OCID where database resides
export TARGET_COMPARTMENT_OCID="ocid1.compartment.oc1..your-compartment-ocid"

# Required: Target database OCID (from OCI console or Azure)
export TARGET_DATABASE_OCID="ocid1.database.oc1..your-database-ocid"

# Optional: Object Storage namespace (if using object storage for backup)
# export TARGET_OBJECT_STORAGE_NAMESPACE="your_namespace"

#################################################################################
# END OF OCI ENVIRONMENT FILE
#################################################################################
OCIENV
        chmod 600 "$OCI_ENV_FILE"
        log_info "Created OCI environment template: $OCI_ENV_FILE"
        log_warn "Please edit $OCI_ENV_FILE with your OCI OCIDs"
    else
        log_info "OCI environment file exists: $OCI_ENV_FILE"
    fi
    
    # Verify SSH keys
    log_info "Checking SSH keys..."
    
    if [ -f "$SOURCENODE_SSHPRIVATEKEY" ]; then
        log_info "Source SSH key found: $SOURCENODE_SSHPRIVATEKEY"
    else
        log_warn "Source SSH key NOT found: $SOURCENODE_SSHPRIVATEKEY"
    fi
    
    if [ -f "$TARGETNODE_SSHPRIVATEKEY" ]; then
        log_info "Target SSH key found: $TARGETNODE_SSHPRIVATEKEY"
    else
        log_warn "Target SSH key NOT found: $TARGETNODE_SSHPRIVATEKEY"
    fi
    
    if [ -f "$OCI_API_KEY" ]; then
        log_info "OCI API key found: $OCI_API_KEY"
    else
        log_warn "OCI API key NOT found: $OCI_API_KEY"
    fi
    
    log_info "Initialization complete!"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Edit $OCI_ENV_FILE with your OCI OCIDs"
    log_info "  2. Run: source $OCI_ENV_FILE"
    log_info "  3. Set password environment variables:"
    log_info "     read -sp 'SOURCE_SYS_PASSWORD: ' SOURCE_SYS_PASSWORD; export SOURCE_SYS_PASSWORD; echo"
    log_info "     read -sp 'TARGET_SYS_PASSWORD: ' TARGET_SYS_PASSWORD; export TARGET_SYS_PASSWORD; echo"
    log_info "     read -sp 'SOURCE_TDE_WALLET_PASSWORD: ' SOURCE_TDE_WALLET_PASSWORD; export SOURCE_TDE_WALLET_PASSWORD; echo"
    log_info "  4. Run: $0 create-creds"
    log_info "  5. Run: $0 eval"
}

cmd_create_creds() {
    log_info "Creating password files..."
    
    check_password_env
    
    # Create credentials directory if not exists
    mkdir -p "$CREDS_DIR"
    chmod 700 "$CREDS_DIR"
    
    # Write password files
    echo -n "$SOURCE_SYS_PASSWORD" > "${CREDS_DIR}/source_sys_password.txt"
    chmod 600 "${CREDS_DIR}/source_sys_password.txt"
    log_info "Created: ${CREDS_DIR}/source_sys_password.txt"
    
    echo -n "$TARGET_SYS_PASSWORD" > "${CREDS_DIR}/target_sys_password.txt"
    chmod 600 "${CREDS_DIR}/target_sys_password.txt"
    log_info "Created: ${CREDS_DIR}/target_sys_password.txt"
    
    echo -n "$SOURCE_TDE_WALLET_PASSWORD" > "${CREDS_DIR}/tde_password.txt"
    chmod 600 "${CREDS_DIR}/tde_password.txt"
    log_info "Created: ${CREDS_DIR}/tde_password.txt"
    
    log_info "Password files created successfully!"
    log_info "Files are stored in: $CREDS_DIR"
    log_warn "Remember to run 'cleanup-creds' after migration is complete"
}

cmd_cleanup_creds() {
    log_info "Cleaning up password files..."
    
    if [ -f "${CREDS_DIR}/source_sys_password.txt" ]; then
        shred -u "${CREDS_DIR}/source_sys_password.txt" 2>/dev/null || rm -f "${CREDS_DIR}/source_sys_password.txt"
        log_info "Removed: source_sys_password.txt"
    fi
    
    if [ -f "${CREDS_DIR}/target_sys_password.txt" ]; then
        shred -u "${CREDS_DIR}/target_sys_password.txt" 2>/dev/null || rm -f "${CREDS_DIR}/target_sys_password.txt"
        log_info "Removed: target_sys_password.txt"
    fi
    
    if [ -f "${CREDS_DIR}/tde_password.txt" ]; then
        shred -u "${CREDS_DIR}/tde_password.txt" 2>/dev/null || rm -f "${CREDS_DIR}/tde_password.txt"
        log_info "Removed: tde_password.txt"
    fi
    
    log_info "Credential cleanup complete!"
}

cmd_eval() {
    log_info "Starting ZDM migration evaluation (dry run)..."
    
    check_zdm
    check_oci_env
    check_creds_files
    
    log_info "Using response file: $RSP_FILE"
    log_info "This will validate configuration without making changes..."
    
    $ZDM_CLI migrate database \
        -sourcedb "$SOURCEDB_DBNAME" \
        -sourcenode "$SOURCENODE_HOST" \
        -srcauth zdmauth \
        -srcarg1 user:"$SOURCENODE_USER" \
        -srcarg2 identity_file:"$SOURCENODE_SSHPRIVATEKEY" \
        -srcarg3 sudo_location:/usr/bin/sudo \
        -targetnode "$TARGETNODE_HOST" \
        -tgtauth zdmauth \
        -tgtarg1 user:"$TARGETNODE_USER" \
        -tgtarg2 identity_file:"$TARGETNODE_SSHPRIVATEKEY" \
        -tgtarg3 sudo_location:/usr/bin/sudo \
        -rsp "$RSP_FILE" \
        -sourcedbpfile "${CREDS_DIR}/source_sys_password.txt" \
        -taboraclepwdfile "${CREDS_DIR}/target_sys_password.txt" \
        -taboraclewallet "${CREDS_DIR}/tde_password.txt" \
        -tdekeystorepasswd "${CREDS_DIR}/tde_password.txt" \
        -taboracledbwallet "${CREDS_DIR}/tde_password.txt" \
        -sourcetdekeypass "${CREDS_DIR}/tde_password.txt" \
        -eval
    
    log_info "Evaluation complete!"
}

cmd_migrate() {
    log_info "Starting ZDM migration..."
    
    check_zdm
    check_oci_env
    check_creds_files
    
    log_info "==================================================="
    log_info "IMPORTANT: Migration will pause at: $PAUSE_PHASE"
    log_info "==================================================="
    log_info ""
    log_info "Source: $SOURCEDB_DBNAME @ $SOURCENODE_HOST"
    log_info "Target: $TARGETDB_UNIQUENAME @ $TARGETNODE_HOST"
    log_info "Method: $MIGRATION_METHOD"
    log_info "Data Guard Mode: $DG_PROTECTION_MODE ($DG_REDO_TRANSPORT)"
    log_info ""
    
    read -p "Do you want to proceed? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        log_info "Migration cancelled."
        exit 0
    fi
    
    log_info "Starting migration..."
    
    $ZDM_CLI migrate database \
        -sourcedb "$SOURCEDB_DBNAME" \
        -sourcenode "$SOURCENODE_HOST" \
        -srcauth zdmauth \
        -srcarg1 user:"$SOURCENODE_USER" \
        -srcarg2 identity_file:"$SOURCENODE_SSHPRIVATEKEY" \
        -srcarg3 sudo_location:/usr/bin/sudo \
        -targetnode "$TARGETNODE_HOST" \
        -tgtauth zdmauth \
        -tgtarg1 user:"$TARGETNODE_USER" \
        -tgtarg2 identity_file:"$TARGETNODE_SSHPRIVATEKEY" \
        -tgtarg3 sudo_location:/usr/bin/sudo \
        -rsp "$RSP_FILE" \
        -sourcedbpfile "${CREDS_DIR}/source_sys_password.txt" \
        -taboraclepwdfile "${CREDS_DIR}/target_sys_password.txt" \
        -taboraclewallet "${CREDS_DIR}/tde_password.txt" \
        -tdekeystorepasswd "${CREDS_DIR}/tde_password.txt" \
        -taboracledbwallet "${CREDS_DIR}/tde_password.txt" \
        -sourcetdekeypass "${CREDS_DIR}/tde_password.txt" \
        -pauseafter "$PAUSE_PHASE"
    
    log_info "Migration job submitted!"
    log_info "Use '$0 status <JOB_ID>' to monitor progress"
}

cmd_status() {
    local job_id=$1
    
    if [ -z "$job_id" ]; then
        log_error "Job ID required"
        log_info "Usage: $0 status <JOB_ID>"
        log_info "To list all jobs: $ZDM_CLI query job -jobid all"
        exit 1
    fi
    
    check_zdm
    
    log_info "Querying job status for: $job_id"
    
    $ZDM_CLI query job -jobid "$job_id"
}

cmd_resume() {
    local job_id=$1
    
    if [ -z "$job_id" ]; then
        log_error "Job ID required"
        log_info "Usage: $0 resume <JOB_ID>"
        exit 1
    fi
    
    check_zdm
    check_creds_files
    
    log_info "==================================================="
    log_warn "WARNING: This will perform the switchover!"
    log_warn "Source database will become standby"
    log_warn "Target database will become primary"
    log_info "==================================================="
    log_info ""
    
    read -p "Are you sure you want to resume and perform switchover? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        log_info "Resume cancelled."
        exit 0
    fi
    
    log_info "Resuming migration job: $job_id"
    
    $ZDM_CLI resume job -jobid "$job_id"
    
    log_info "Migration resumed!"
    log_info "Use '$0 status $job_id' to monitor progress"
}

cmd_abort() {
    local job_id=$1
    
    if [ -z "$job_id" ]; then
        log_error "Job ID required"
        log_info "Usage: $0 abort <JOB_ID>"
        exit 1
    fi
    
    check_zdm
    
    log_warn "WARNING: This will abort the migration job!"
    
    read -p "Are you sure you want to abort job $job_id? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        log_info "Abort cancelled."
        exit 0
    fi
    
    log_info "Aborting job: $job_id"
    
    $ZDM_CLI abort job -jobid "$job_id"
    
    log_info "Job abort initiated."
}

cmd_query() {
    local job_id=$1
    
    if [ -z "$job_id" ]; then
        log_info "Listing all jobs..."
        $ZDM_CLI query job -jobid all
    else
        log_info "Detailed query for job: $job_id"
        $ZDM_CLI query job -jobid "$job_id" -listphases
    fi
}

cmd_help() {
    cat << 'HELPTEXT'
ZDM Commands Script: PRODDB Migration
=====================================

Usage: ./zdm_commands_PRODDB.sh <command> [options]

Commands:
  init            Initialize environment (creates directories, templates)
  create-creds    Create password files from environment variables
  cleanup-creds   Securely remove password files
  eval            Run migration evaluation (dry run, no changes)
  migrate         Execute the actual migration
  status <id>     Check status of a migration job
  resume <id>     Resume a paused migration job
  abort <id>      Abort a running migration job
  query [id]      Query job details (or list all jobs)
  help            Show this help message

Workflow:
  1. ./zdm_commands_PRODDB.sh init
  2. Edit ~/zdm_oci_env.sh with OCI OCIDs
  3. source ~/zdm_oci_env.sh
  4. Set password environment variables:
     read -sp 'Password: ' SOURCE_SYS_PASSWORD; export SOURCE_SYS_PASSWORD; echo
     read -sp 'Password: ' TARGET_SYS_PASSWORD; export TARGET_SYS_PASSWORD; echo
     read -sp 'Password: ' SOURCE_TDE_WALLET_PASSWORD; export SOURCE_TDE_WALLET_PASSWORD; echo
  5. ./zdm_commands_PRODDB.sh create-creds
  6. ./zdm_commands_PRODDB.sh eval
  7. ./zdm_commands_PRODDB.sh migrate
  8. (Wait for pause at ZDM_SWITCHOVER_SRC)
  9. ./zdm_commands_PRODDB.sh resume <JOB_ID>
  10. ./zdm_commands_PRODDB.sh cleanup-creds

Environment Variables (Required before create-creds):
  SOURCE_SYS_PASSWORD        - SYS password for source database
  TARGET_SYS_PASSWORD        - SYS password for target database
  SOURCE_TDE_WALLET_PASSWORD - TDE wallet password

OCI Environment Variables (Required, set in ~/zdm_oci_env.sh):
  TARGET_TENANCY_OCID        - OCI Tenancy OCID
  TARGET_USER_OCID           - OCI User OCID
  TARGET_FINGERPRINT         - OCI API Key Fingerprint
  TARGET_COMPARTMENT_OCID    - Compartment OCID
  TARGET_DATABASE_OCID       - Target Database OCID

HELPTEXT
}

#--------------------------------------------------------------------------------
# MAIN
#--------------------------------------------------------------------------------

case "${1:-help}" in
    init)
        cmd_init
        ;;
    create-creds)
        cmd_create_creds
        ;;
    cleanup-creds)
        cmd_cleanup_creds
        ;;
    eval)
        cmd_eval
        ;;
    migrate)
        cmd_migrate
        ;;
    status)
        cmd_status "$2"
        ;;
    resume)
        cmd_resume "$2"
        ;;
    abort)
        cmd_abort "$2"
        ;;
    query)
        cmd_query "$2"
        ;;
    help|--help|-h)
        cmd_help
        ;;
    *)
        log_error "Unknown command: $1"
        cmd_help
        exit 1
        ;;
esac
