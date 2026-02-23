#!/bin/bash
################################################################################
# ZDM Discovery Orchestration Script
# Project: PRODDB Migration to Oracle Database@Azure
#
# Purpose: Orchestrate discovery across source, target, and ZDM servers
# Execution: Run from any machine with SSH access to all servers
################################################################################

# ===========================================
# SERVER CONFIGURATION
# ===========================================

# Source Database Server
SOURCE_HOST="${SOURCE_HOST:-proddb01.corp.example.com}"
SOURCE_ADMIN_USER="${SOURCE_ADMIN_USER:-oracle}"
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-~/.ssh/onprem_oracle_key}"

# Target Database Server (Oracle Database@Azure)
TARGET_HOST="${TARGET_HOST:-proddb-oda.eastus.azure.example.com}"
TARGET_ADMIN_USER="${TARGET_ADMIN_USER:-opc}"
TARGET_SSH_KEY="${TARGET_SSH_KEY:-~/.ssh/oci_opc_key}"

# ZDM Jumpbox Server
ZDM_HOST="${ZDM_HOST:-zdm-jumpbox.corp.example.com}"
ZDM_ADMIN_USER="${ZDM_ADMIN_USER:-azureuser}"
ZDM_SSH_KEY="${ZDM_SSH_KEY:-~/.ssh/azure_key}"

# ===========================================
# USER CONFIGURATION
# ===========================================

# Oracle database software owner (for running SQL commands)
ORACLE_USER="${ORACLE_USER:-oracle}"

# ZDM software owner (for running ZDM CLI commands)
ZDM_USER="${ZDM_USER:-zdmuser}"

# ===========================================
# OUTPUT CONFIGURATION
# ===========================================

# Get script directory and calculate repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Navigate up 6 levels to get to repository root
# Path: Scripts -> Step0 -> PRODDB -> ZDM -> Phase10-Migration -> Artifacts -> RepoRoot
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../../.." && pwd)"

# Set output directory (can be overridden by environment variable)
DEFAULT_OUTPUT_DIR="${REPO_ROOT}/Artifacts/Phase10-Migration/ZDM/PRODDB/Step0/Discovery"
OUTPUT_DIR="${ZDM_OUTPUT_DIR:-$DEFAULT_OUTPUT_DIR}"

# ===========================================
# SSH CONFIGURATION
# ===========================================

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

# ===========================================
# COLOR CODES
# ===========================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ===========================================
# TRACKING VARIABLES
# ===========================================

declare -a SUCCESS_SERVERS=()
declare -a FAILED_SERVERS=()

################################################################################
# Utility Functions
################################################################################

print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warn() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

################################################################################
# Help and Configuration Display
################################################################################

show_help() {
    cat <<EOF
ZDM Discovery Orchestration Script
Project: PRODDB Migration to Oracle Database@Azure

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help      Show this help message
    -c, --config    Display current configuration
    -t, --test      Test connectivity only (no discovery)

DESCRIPTION:
    This script orchestrates discovery across all ZDM migration servers:
    - Source Database Server
    - Target Database Server (Oracle Database@Azure)
    - ZDM Jumpbox Server

CONFIGURATION:
    Server hostnames, users, and SSH keys are configured via environment
    variables or use the defaults specified in this script.

    Current defaults:
    - Source: ${SOURCE_ADMIN_USER}@${SOURCE_HOST} (${SOURCE_SSH_KEY})
    - Target: ${TARGET_ADMIN_USER}@${TARGET_HOST} (${TARGET_SSH_KEY})
    - ZDM:    ${ZDM_ADMIN_USER}@${ZDM_HOST} (${ZDM_SSH_KEY})

    Output Directory: ${OUTPUT_DIR}

EXAMPLES:
    # Run discovery with default configuration
    $0

    # Display current configuration
    $0 --config

    # Test connectivity only
    $0 --test

    # Override configuration via environment variables
    SOURCE_HOST=mydb.example.com TARGET_HOST=targetdb.example.com $0

EOF
}

show_config() {
    print_header "Current Configuration"
    echo "Source Database Server:"
    echo "  Host:      ${SOURCE_HOST}"
    echo "  User:      ${SOURCE_ADMIN_USER}"
    echo "  SSH Key:   ${SOURCE_SSH_KEY}"
    echo ""
    echo "Target Database Server:"
    echo "  Host:      ${TARGET_HOST}"
    echo "  User:      ${TARGET_ADMIN_USER}"
    echo "  SSH Key:   ${TARGET_SSH_KEY}"
    echo ""
    echo "ZDM Jumpbox Server:"
    echo "  Host:      ${ZDM_HOST}"
    echo "  User:      ${ZDM_ADMIN_USER}"
    echo "  SSH Key:   ${ZDM_SSH_KEY}"
    echo ""
    echo "Application Users:"
    echo "  Oracle User: ${ORACLE_USER}"
    echo "  ZDM User:    ${ZDM_USER}"
    echo ""
    echo "Output:"
    echo "  Directory: ${OUTPUT_DIR}"
    echo "  Repo Root: ${REPO_ROOT}"
    echo ""
}

################################################################################
# Connectivity Testing
################################################################################

test_connectivity() {
    local host="$1"
    local user="$2"
    local key="$3"
    local label="$4"
    
    print_info "Testing connectivity to $label ($user@$host)..."
    
    # Expand tilde in SSH key path
    key="${key/#\~/$HOME}"
    
    # Check if SSH key exists
    if [ ! -f "$key" ]; then
        print_error "SSH key not found: $key"
        return 1
    fi
    
    # Test SSH connection
    if ssh $SSH_OPTS -i "$key" "${user}@${host}" "echo 'Connection successful'" >/dev/null 2>&1; then
        print_success "Successfully connected to $label"
        return 0
    else
        print_error "Failed to connect to $label"
        return 1
    fi
}

test_all_connectivity() {
    print_header "Testing Connectivity"
    
    local all_success=true
    
    test_connectivity "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$SOURCE_SSH_KEY" "Source Database" || all_success=false
    test_connectivity "$TARGET_HOST" "$TARGET_ADMIN_USER" "$TARGET_SSH_KEY" "Target Database" || all_success=false
    test_connectivity "$ZDM_HOST" "$ZDM_ADMIN_USER" "$ZDM_SSH_KEY" "ZDM Server" || all_success=false
    
    echo ""
    if [ "$all_success" = true ]; then
        print_success "All connectivity tests passed"
        return 0
    else
        print_error "Some connectivity tests failed"
        return 1
    fi
}

################################################################################
# Discovery Functions
################################################################################

run_source_discovery() {
    print_header "Source Database Discovery"
    
    local script_name="zdm_source_discovery.sh"
    local script_path="$SCRIPT_DIR/$script_name"
    local output_subdir="$OUTPUT_DIR/source"
    
    # Expand tilde in SSH key path
    local key_path="${SOURCE_SSH_KEY/#\~/$HOME}"
    
    # Create output directory
    mkdir -p "$output_subdir"
    
    print_info "Running discovery on $SOURCE_HOST..."
    print_info "Admin User: $SOURCE_ADMIN_USER"
    print_info "Oracle User: $ORACLE_USER"
    
    # Copy and execute script remotely using login shell
    if ssh $SSH_OPTS -i "$key_path" "${SOURCE_ADMIN_USER}@${SOURCE_HOST}" "ORACLE_USER='$ORACLE_USER' bash -l -s" < "$script_path"; then
        print_success "Source discovery completed"
        
        # Collect output files
        print_info "Collecting output files..."
        scp $SSH_OPTS -i "$key_path" "${SOURCE_ADMIN_USER}@${SOURCE_HOST}:~/zdm_source_discovery_*.txt" "$output_subdir/" 2>/dev/null
        scp $SSH_OPTS -i "$key_path" "${SOURCE_ADMIN_USER}@${SOURCE_HOST}:~/zdm_source_discovery_*.json" "$output_subdir/" 2>/dev/null
        
        # Clean up remote files
        ssh $SSH_OPTS -i "$key_path" "${SOURCE_ADMIN_USER}@${SOURCE_HOST}" "rm -f ~/zdm_source_discovery_*.txt ~/zdm_source_discovery_*.json" 2>/dev/null
        
        print_success "Output files collected to $output_subdir/"
        SUCCESS_SERVERS+=("Source Database")
        return 0
    else
        print_error "Source discovery failed"
        FAILED_SERVERS+=("Source Database")
        return 1
    fi
}

run_target_discovery() {
    print_header "Target Database Discovery"
    
    local script_name="zdm_target_discovery.sh"
    local script_path="$SCRIPT_DIR/$script_name"
    local output_subdir="$OUTPUT_DIR/target"
    
    # Expand tilde in SSH key path
    local key_path="${TARGET_SSH_KEY/#\~/$HOME}"
    
    # Create output directory
    mkdir -p "$output_subdir"
    
    print_info "Running discovery on $TARGET_HOST..."
    print_info "Admin User: $TARGET_ADMIN_USER"
    print_info "Oracle User: $ORACLE_USER"
    
    # Copy and execute script remotely using login shell
    if ssh $SSH_OPTS -i "$key_path" "${TARGET_ADMIN_USER}@${TARGET_HOST}" "ORACLE_USER='$ORACLE_USER' bash -l -s" < "$script_path"; then
        print_success "Target discovery completed"
        
        # Collect output files
        print_info "Collecting output files..."
        scp $SSH_OPTS -i "$key_path" "${TARGET_ADMIN_USER}@${TARGET_HOST}:~/zdm_target_discovery_*.txt" "$output_subdir/" 2>/dev/null
        scp $SSH_OPTS -i "$key_path" "${TARGET_ADMIN_USER}@${TARGET_HOST}:~/zdm_target_discovery_*.json" "$output_subdir/" 2>/dev/null
        
        # Clean up remote files
        ssh $SSH_OPTS -i "$key_path" "${TARGET_ADMIN_USER}@${TARGET_HOST}" "rm -f ~/zdm_target_discovery_*.txt ~/zdm_target_discovery_*.json" 2>/dev/null
        
        print_success "Output files collected to $output_subdir/"
        SUCCESS_SERVERS+=("Target Database")
        return 0
    else
        print_error "Target discovery failed"
        FAILED_SERVERS+=("Target Database")
        return 1
    fi
}

run_zdm_server_discovery() {
    print_header "ZDM Server Discovery"
    
    local script_name="zdm_server_discovery.sh"
    local script_path="$SCRIPT_DIR/$script_name"
    local output_subdir="$OUTPUT_DIR/server"
    
    # Expand tilde in SSH key path
    local key_path="${ZDM_SSH_KEY/#\~/$HOME}"
    
    # Create output directory
    mkdir -p "$output_subdir"
    
    print_info "Running discovery on $ZDM_HOST..."
    print_info "Admin User: $ZDM_ADMIN_USER"
    print_info "ZDM User: $ZDM_USER"
    
    # Copy and execute script remotely using login shell
    # IMPORTANT: Pass SOURCE_HOST and TARGET_HOST for connectivity tests
    if ssh $SSH_OPTS -i "$key_path" "${ZDM_ADMIN_USER}@${ZDM_HOST}" \
        "SOURCE_HOST='$SOURCE_HOST' TARGET_HOST='$TARGET_HOST' ZDM_USER='$ZDM_USER' bash -l -s" < "$script_path"; then
        print_success "ZDM server discovery completed"
        
        # Collect output files
        print_info "Collecting output files..."
        scp $SSH_OPTS -i "$key_path" "${ZDM_ADMIN_USER}@${ZDM_HOST}:~/zdm_server_discovery_*.txt" "$output_subdir/" 2>/dev/null
        scp $SSH_OPTS -i "$key_path" "${ZDM_ADMIN_USER}@${ZDM_HOST}:~/zdm_server_discovery_*.json" "$output_subdir/" 2>/dev/null
        
        # Clean up remote files
        ssh $SSH_OPTS -i "$key_path" "${ZDM_ADMIN_USER}@${ZDM_HOST}" "rm -f ~/zdm_server_discovery_*.txt ~/zdm_server_discovery_*.json" 2>/dev/null
        
        print_success "Output files collected to $output_subdir/"
        SUCCESS_SERVERS+=("ZDM Server")
        return 0
    else
        print_error "ZDM server discovery failed"
        FAILED_SERVERS+=("ZDM Server")
        return 1
    fi
}

################################################################################
# Main Execution
################################################################################

main() {
    print_header "ZDM Discovery Orchestration"
    echo "Project: PRODDB Migration to Oracle Database@Azure"
    echo "Timestamp: $(date)"
    echo ""
    
    # Parse command-line arguments
    case "${1:-}" in
        -h|--help)
            show_help
            exit 0
            ;;
        -c|--config)
            show_config
            exit 0
            ;;
        -t|--test)
            test_all_connectivity
            exit $?
            ;;
    esac
    
    # Display configuration
    show_config
    
    # Validate discovery scripts exist
    print_header "Validating Discovery Scripts"
    
    local scripts=(
        "zdm_source_discovery.sh"
        "zdm_target_discovery.sh"
        "zdm_server_discovery.sh"
    )
    
    local all_scripts_exist=true
    for script in "${scripts[@]}"; do
        if [ -f "$SCRIPT_DIR/$script" ]; then
            print_success "$script found"
        else
            print_error "$script not found"
            all_scripts_exist=false
        fi
    done
    
    if [ "$all_scripts_exist" != true ]; then
        print_error "Some discovery scripts are missing. Cannot proceed."
        exit 1
    fi
    
    # Create output directory structure
    print_header "Preparing Output Directory"
    mkdir -p "$OUTPUT_DIR"/{source,target,server}
    print_success "Output directory created: $OUTPUT_DIR"
    
    # Test connectivity
    if ! test_all_connectivity; then
        print_warn "Connectivity tests failed. Discovery may not complete successfully."
        read -p "Do you want to continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Discovery aborted by user"
            exit 1
        fi
    fi
    
    # Run discovery on all servers (continue on failure)
    print_header "Running Discovery"
    
    run_source_discovery
    echo ""
    
    run_target_discovery
    echo ""
    
    run_zdm_server_discovery
    echo ""
    
    # Summary
    print_header "Discovery Summary"
    
    echo "Completed: ${#SUCCESS_SERVERS[@]} / 3 servers"
    echo ""
    
    if [ ${#SUCCESS_SERVERS[@]} -gt 0 ]; then
        print_success "Successful discoveries:"
        for server in "${SUCCESS_SERVERS[@]}"; do
            echo "  ✓ $server"
        done
        echo ""
    fi
    
    if [ ${#FAILED_SERVERS[@]} -gt 0 ]; then
        print_error "Failed discoveries:"
        for server in "${FAILED_SERVERS[@]}"; do
            echo "  ✗ $server"
        done
        echo ""
    fi
    
    print_info "Output location: $OUTPUT_DIR"
    echo ""
    
    # List collected files
    if [ -d "$OUTPUT_DIR" ]; then
        print_info "Collected files:"
        find "$OUTPUT_DIR" -type f \( -name "*.txt" -o -name "*.json" \) -exec ls -lh {} \; | awk '{print "  " $9 " (" $5 ")"}'
        echo ""
    fi
    
    # Exit status
    if [ ${#FAILED_SERVERS[@]} -eq 0 ]; then
        print_success "All discoveries completed successfully!"
        echo ""
        print_info "Next Steps:"
        echo "  1. Review the discovery outputs in: $OUTPUT_DIR"
        echo "  2. Proceed to Step 1: Discovery Questionnaire"
        exit 0
    elif [ ${#SUCCESS_SERVERS[@]} -gt 0 ]; then
        print_warn "Discovery completed with some failures"
        echo ""
        print_info "Next Steps:"
        echo "  1. Review the successful discovery outputs in: $OUTPUT_DIR"
        echo "  2. Investigate and retry failed discoveries"
        echo "  3. Once all discoveries are complete, proceed to Step 1"
        exit 1
    else
        print_error "All discoveries failed"
        echo ""
        print_info "Troubleshooting:"
        echo "  1. Verify SSH connectivity to all servers"
        echo "  2. Check SSH keys and permissions"
        echo "  3. Verify admin user accounts have sudo privileges"
        echo "  4. Review script execution logs"
        exit 1
    fi
}

# Run main function
main "$@"
