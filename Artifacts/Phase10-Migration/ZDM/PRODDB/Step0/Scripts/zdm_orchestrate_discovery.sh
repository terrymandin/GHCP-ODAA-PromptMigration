#!/bin/bash
#===============================================================================
# ZDM Discovery Orchestration Script
# Project: PRODDB Migration to Oracle Database@Azure
#
# Purpose: Orchestrate discovery across source, target, and ZDM servers
#
# Usage: 
#   ./zdm_orchestrate_discovery.sh                    # Run full discovery
#   ./zdm_orchestrate_discovery.sh -t                 # Test connectivity only
#   ./zdm_orchestrate_discovery.sh -c                 # Show configuration
#   ./zdm_orchestrate_discovery.sh -h                 # Show help
#
# Output:
#   Discovery files collected to: Artifacts/Phase10-Migration/ZDM/PRODDB/Step0/Discovery/
#===============================================================================

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Script variables
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#===============================================================================
# SERVER CONFIGURATION
#===============================================================================
SOURCE_HOST="${SOURCE_HOST:-proddb01.corp.example.com}"
TARGET_HOST="${TARGET_HOST:-proddb-oda.eastus.azure.example.com}"
ZDM_HOST="${ZDM_HOST:-zdm-jumpbox.corp.example.com}"

#===============================================================================
# USER CONFIGURATION
#===============================================================================
# SSH/Admin users for each server (can be different for each environment)
# These are Linux admin users with sudo privileges
SOURCE_ADMIN_USER="${SOURCE_ADMIN_USER:-oracle}"
TARGET_ADMIN_USER="${TARGET_ADMIN_USER:-opc}"
ZDM_ADMIN_USER="${ZDM_ADMIN_USER:-azureuser}"

# Oracle database software owner (for running SQL commands)
ORACLE_USER="${ORACLE_USER:-oracle}"

# ZDM software owner (for running ZDM CLI commands)
ZDM_USER="${ZDM_USER:-zdmuser}"

#===============================================================================
# SSH KEY CONFIGURATION
#===============================================================================
# Separate SSH keys for each security domain
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-$HOME/.ssh/onprem_oracle_key}"
TARGET_SSH_KEY="${TARGET_SSH_KEY:-$HOME/.ssh/oci_opc_key}"
ZDM_SSH_KEY="${ZDM_SSH_KEY:-$HOME/.ssh/azure_key}"

#===============================================================================
# OUTPUT CONFIGURATION
#===============================================================================
# Default output directory - can be overridden via OUTPUT_DIR environment variable
DEFAULT_OUTPUT_DIR="${SCRIPT_DIR}/../Discovery"
OUTPUT_DIR="${OUTPUT_DIR:-$DEFAULT_OUTPUT_DIR}"

#===============================================================================
# OPTIONAL ENVIRONMENT OVERRIDES
#===============================================================================
# These can be set if auto-detection fails on remote servers
# SOURCE_REMOTE_ORACLE_HOME - Path to Oracle home on source server
# SOURCE_REMOTE_ORACLE_SID - Oracle SID on source server
# TARGET_REMOTE_ORACLE_HOME - Path to Oracle home on target server
# TARGET_REMOTE_ORACLE_SID - Oracle SID on target server
# ZDM_REMOTE_ZDM_HOME - Path to ZDM home on ZDM server
# ZDM_REMOTE_JAVA_HOME - Path to Java home on ZDM server

# Tracking variables
ERRORS=0
SUCCESS_COUNT=0
FAIL_COUNT=0

#===============================================================================
# Functions
#===============================================================================

print_header() {
    echo -e "\n${CYAN}${BOLD}================================================================${NC}"
    echo -e "${CYAN}${BOLD}$1${NC}"
    echo -e "${CYAN}${BOLD}================================================================${NC}\n"
}

print_section() {
    echo -e "\n${BLUE}----------------------------------------------------------------${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}----------------------------------------------------------------${NC}"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info() {
    echo -e "${NC}$1${NC}"
}

show_help() {
    cat << EOF
ZDM Discovery Orchestration Script v${SCRIPT_VERSION}
Project: PRODDB Migration to Oracle Database@Azure

USAGE:
    $(basename "$0") [OPTIONS]

OPTIONS:
    -h, --help          Show this help message
    -c, --config        Display current configuration
    -t, --test          Test SSH connectivity only (no discovery)
    -s, --source-only   Run discovery on source server only
    -g, --target-only   Run discovery on target server only
    -z, --zdm-only      Run discovery on ZDM server only

ENVIRONMENT VARIABLES:
    Server Hostnames:
        SOURCE_HOST         Source database server (default: proddb01.corp.example.com)
        TARGET_HOST         Target Oracle Database@Azure (default: proddb-oda.eastus.azure.example.com)
        ZDM_HOST            ZDM jumpbox server (default: zdm-jumpbox.corp.example.com)

    SSH Admin Users (for SSH connections):
        SOURCE_ADMIN_USER   Admin user for source server (default: oracle)
        TARGET_ADMIN_USER   Admin user for target server (default: opc)
        ZDM_ADMIN_USER      Admin user for ZDM server (default: azureuser)

    Application Users:
        ORACLE_USER         Oracle database software owner (default: oracle)
        ZDM_USER            ZDM software owner (default: zdmuser)

    SSH Keys:
        SOURCE_SSH_KEY      SSH key for source server (default: ~/.ssh/onprem_oracle_key)
        TARGET_SSH_KEY      SSH key for target server (default: ~/.ssh/oci_opc_key)
        ZDM_SSH_KEY         SSH key for ZDM server (default: ~/.ssh/azure_key)

    Output:
        OUTPUT_DIR          Directory to store discovery results

    Environment Overrides (if auto-detection fails):
        SOURCE_REMOTE_ORACLE_HOME   Oracle home path on source
        SOURCE_REMOTE_ORACLE_SID    Oracle SID on source
        TARGET_REMOTE_ORACLE_HOME   Oracle home path on target
        TARGET_REMOTE_ORACLE_SID    Oracle SID on target
        ZDM_REMOTE_ZDM_HOME         ZDM home path on ZDM server
        ZDM_REMOTE_JAVA_HOME        Java home path on ZDM server

EXAMPLES:
    # Run full discovery with defaults
    ./$(basename "$0")

    # Test connectivity only
    ./$(basename "$0") -t

    # Run with custom source server
    SOURCE_HOST=mydb.example.com ./$(basename "$0")

    # Run discovery on source only
    ./$(basename "$0") -s

EOF
}

show_config() {
    print_header "Current Configuration"
    
    echo "Server Configuration:"
    echo "  SOURCE_HOST:        $SOURCE_HOST"
    echo "  TARGET_HOST:        $TARGET_HOST"
    echo "  ZDM_HOST:           $ZDM_HOST"
    
    echo ""
    echo "SSH Admin User Configuration:"
    echo "  SOURCE_ADMIN_USER:  $SOURCE_ADMIN_USER"
    echo "  TARGET_ADMIN_USER:  $TARGET_ADMIN_USER"
    echo "  ZDM_ADMIN_USER:     $ZDM_ADMIN_USER"
    
    echo ""
    echo "Application User Configuration:"
    echo "  ORACLE_USER:        $ORACLE_USER"
    echo "  ZDM_USER:           $ZDM_USER"
    
    echo ""
    echo "SSH Key Configuration:"
    echo "  SOURCE_SSH_KEY:     $SOURCE_SSH_KEY"
    if [ -f "$SOURCE_SSH_KEY" ]; then
        echo "                      (exists)"
    else
        echo "                      (NOT FOUND)"
    fi
    
    echo "  TARGET_SSH_KEY:     $TARGET_SSH_KEY"
    if [ -f "$TARGET_SSH_KEY" ]; then
        echo "                      (exists)"
    else
        echo "                      (NOT FOUND)"
    fi
    
    echo "  ZDM_SSH_KEY:        $ZDM_SSH_KEY"
    if [ -f "$ZDM_SSH_KEY" ]; then
        echo "                      (exists)"
    else
        echo "                      (NOT FOUND)"
    fi
    
    echo ""
    echo "Output Configuration:"
    echo "  OUTPUT_DIR:         $OUTPUT_DIR"
    
    echo ""
    echo "Environment Overrides (if set):"
    echo "  SOURCE_REMOTE_ORACLE_HOME: ${SOURCE_REMOTE_ORACLE_HOME:-<not set>}"
    echo "  SOURCE_REMOTE_ORACLE_SID:  ${SOURCE_REMOTE_ORACLE_SID:-<not set>}"
    echo "  TARGET_REMOTE_ORACLE_HOME: ${TARGET_REMOTE_ORACLE_HOME:-<not set>}"
    echo "  TARGET_REMOTE_ORACLE_SID:  ${TARGET_REMOTE_ORACLE_SID:-<not set>}"
    echo "  ZDM_REMOTE_ZDM_HOME:       ${ZDM_REMOTE_ZDM_HOME:-<not set>}"
    echo "  ZDM_REMOTE_JAVA_HOME:      ${ZDM_REMOTE_JAVA_HOME:-<not set>}"
}

validate_config() {
    print_section "Validating Configuration"
    
    local validation_errors=0
    
    # Check SSH keys exist
    if [ ! -f "$SOURCE_SSH_KEY" ]; then
        print_warning "Source SSH key not found: $SOURCE_SSH_KEY"
        validation_errors=$((validation_errors + 1))
    fi
    
    if [ ! -f "$TARGET_SSH_KEY" ]; then
        print_warning "Target SSH key not found: $TARGET_SSH_KEY"
        validation_errors=$((validation_errors + 1))
    fi
    
    if [ ! -f "$ZDM_SSH_KEY" ]; then
        print_warning "ZDM SSH key not found: $ZDM_SSH_KEY"
        validation_errors=$((validation_errors + 1))
    fi
    
    # Check discovery scripts exist
    if [ ! -f "$SCRIPT_DIR/zdm_source_discovery.sh" ]; then
        print_error "Source discovery script not found: $SCRIPT_DIR/zdm_source_discovery.sh"
        validation_errors=$((validation_errors + 1))
    fi
    
    if [ ! -f "$SCRIPT_DIR/zdm_target_discovery.sh" ]; then
        print_error "Target discovery script not found: $SCRIPT_DIR/zdm_target_discovery.sh"
        validation_errors=$((validation_errors + 1))
    fi
    
    if [ ! -f "$SCRIPT_DIR/zdm_server_discovery.sh" ]; then
        print_error "ZDM server discovery script not found: $SCRIPT_DIR/zdm_server_discovery.sh"
        validation_errors=$((validation_errors + 1))
    fi
    
    if [ $validation_errors -eq 0 ]; then
        print_success "Configuration validation passed"
    else
        print_warning "Configuration has $validation_errors warning(s)"
    fi
    
    return 0  # Continue even with warnings
}

test_ssh_connectivity() {
    local host="$1"
    local user="$2"
    local key="$3"
    local description="$4"
    
    echo -n "  Testing $description ($user@$host)... "
    
    if [ ! -f "$key" ]; then
        echo -e "${RED}FAILED${NC} (SSH key not found)"
        return 1
    fi
    
    if ssh -i "$key" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
        "$user@$host" "echo 'SSH OK'" >/dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
        return 0
    else
        echo -e "${RED}FAILED${NC}"
        return 1
    fi
}

test_all_connectivity() {
    print_section "Testing SSH Connectivity"
    
    local source_ok=0
    local target_ok=0
    local zdm_ok=0
    
    test_ssh_connectivity "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$SOURCE_SSH_KEY" "Source Server" && source_ok=1
    test_ssh_connectivity "$TARGET_HOST" "$TARGET_ADMIN_USER" "$TARGET_SSH_KEY" "Target Server" && target_ok=1
    test_ssh_connectivity "$ZDM_HOST" "$ZDM_ADMIN_USER" "$ZDM_SSH_KEY" "ZDM Server" && zdm_ok=1
    
    echo ""
    local total=$((source_ok + target_ok + zdm_ok))
    if [ $total -eq 3 ]; then
        print_success "All servers accessible"
    elif [ $total -gt 0 ]; then
        print_warning "$total of 3 servers accessible"
    else
        print_error "No servers accessible"
    fi
    
    return 0  # Don't fail the script, just report
}

run_remote_discovery() {
    local host="$1"
    local user="$2"
    local key="$3"
    local script="$4"
    local output_subdir="$5"
    local description="$6"
    local env_overrides="$7"
    
    print_section "Running Discovery: $description"
    
    # Check SSH key
    if [ ! -f "$key" ]; then
        print_error "SSH key not found: $key"
        return 1
    fi
    
    # Check discovery script
    if [ ! -f "$script" ]; then
        print_error "Discovery script not found: $script"
        return 1
    fi
    
    # Create output subdirectory
    local output_path="$OUTPUT_DIR/$output_subdir"
    mkdir -p "$output_path"
    
    echo "  Host: $host"
    echo "  User: $user"
    echo "  Key:  $key"
    echo "  Output: $output_path"
    echo ""
    
    # Copy script to remote server
    echo "  Copying discovery script..."
    if ! scp -i "$key" -o StrictHostKeyChecking=no -o ConnectTimeout=30 \
        "$script" "$user@$host:/tmp/" 2>/dev/null; then
        print_error "Failed to copy script to $host"
        return 1
    fi
    
    # Execute script remotely with environment overrides
    echo "  Executing discovery (this may take a few minutes)..."
    local remote_cmd="cd /tmp && chmod +x $(basename $script)"
    
    # Add environment overrides if provided
    if [ -n "$env_overrides" ]; then
        remote_cmd="$env_overrides $remote_cmd"
    fi
    
    # Add user environment variables
    remote_cmd="ORACLE_USER=$ORACLE_USER ZDM_USER=$ZDM_USER $remote_cmd"
    
    # Execute with login shell for proper environment
    remote_cmd="$remote_cmd && ./$(basename $script)"
    
    if ! ssh -i "$key" -o StrictHostKeyChecking=no -o ConnectTimeout=30 \
        "$user@$host" "bash -l -c '$remote_cmd'" 2>&1; then
        print_warning "Discovery completed with some errors"
    fi
    
    # Collect output files
    echo ""
    echo "  Collecting results..."
    if scp -i "$key" -o StrictHostKeyChecking=no \
        "$user@$host:/tmp/zdm_*_discovery_*.txt" \
        "$user@$host:/tmp/zdm_*_discovery_*.json" \
        "$output_path/" 2>/dev/null; then
        print_success "Results collected to $output_path"
        
        # List collected files
        echo "  Files:"
        ls -la "$output_path/"zdm_*_discovery_*.{txt,json} 2>/dev/null | sed 's/^/    /'
    else
        print_warning "Some or all result files could not be collected"
    fi
    
    # Cleanup remote files
    ssh -i "$key" -o StrictHostKeyChecking=no \
        "$user@$host" "rm -f /tmp/zdm_*_discovery_*.txt /tmp/zdm_*_discovery_*.json /tmp/zdm_*_discovery.sh" 2>/dev/null
    
    return 0
}

run_source_discovery() {
    local env_overrides=""
    
    # Build environment override string if set
    [ -n "${SOURCE_REMOTE_ORACLE_HOME:-}" ] && env_overrides="${env_overrides}ORACLE_HOME_OVERRIDE='$SOURCE_REMOTE_ORACLE_HOME' "
    [ -n "${SOURCE_REMOTE_ORACLE_SID:-}" ] && env_overrides="${env_overrides}ORACLE_SID_OVERRIDE='$SOURCE_REMOTE_ORACLE_SID' "
    
    run_remote_discovery \
        "$SOURCE_HOST" \
        "$SOURCE_ADMIN_USER" \
        "$SOURCE_SSH_KEY" \
        "$SCRIPT_DIR/zdm_source_discovery.sh" \
        "source" \
        "Source Database Server" \
        "$env_overrides"
    
    return $?
}

run_target_discovery() {
    local env_overrides=""
    
    # Build environment override string if set
    [ -n "${TARGET_REMOTE_ORACLE_HOME:-}" ] && env_overrides="${env_overrides}ORACLE_HOME_OVERRIDE='$TARGET_REMOTE_ORACLE_HOME' "
    [ -n "${TARGET_REMOTE_ORACLE_SID:-}" ] && env_overrides="${env_overrides}ORACLE_SID_OVERRIDE='$TARGET_REMOTE_ORACLE_SID' "
    
    run_remote_discovery \
        "$TARGET_HOST" \
        "$TARGET_ADMIN_USER" \
        "$TARGET_SSH_KEY" \
        "$SCRIPT_DIR/zdm_target_discovery.sh" \
        "target" \
        "Target Database Server (Oracle Database@Azure)" \
        "$env_overrides"
    
    return $?
}

run_zdm_discovery() {
    local env_overrides=""
    
    # Build environment override string if set
    [ -n "${ZDM_REMOTE_ZDM_HOME:-}" ] && env_overrides="${env_overrides}ZDM_HOME_OVERRIDE='$ZDM_REMOTE_ZDM_HOME' "
    [ -n "${ZDM_REMOTE_JAVA_HOME:-}" ] && env_overrides="${env_overrides}JAVA_HOME_OVERRIDE='$ZDM_REMOTE_JAVA_HOME' "
    
    run_remote_discovery \
        "$ZDM_HOST" \
        "$ZDM_ADMIN_USER" \
        "$ZDM_SSH_KEY" \
        "$SCRIPT_DIR/zdm_server_discovery.sh" \
        "server" \
        "ZDM Jumpbox Server" \
        "$env_overrides"
    
    return $?
}

run_all_discovery() {
    print_header "ZDM Discovery Orchestration"
    echo "Project: PRODDB Migration to Oracle Database@Azure"
    echo "Started: $(date)"
    echo ""
    
    # Validate configuration
    validate_config
    
    # Test connectivity
    test_all_connectivity
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # Run discovery on each server (continue on failure)
    echo ""
    
    if run_source_discovery; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    
    if run_target_discovery; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    
    if run_zdm_discovery; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    
    # Print summary
    print_header "Discovery Summary"
    echo "Completed: $(date)"
    echo ""
    echo "Results:"
    echo "  Successful: $SUCCESS_COUNT"
    echo "  Failed:     $FAIL_COUNT"
    echo ""
    echo "Output Directory: $OUTPUT_DIR"
    echo ""
    
    if [ -d "$OUTPUT_DIR" ]; then
        echo "Collected Files:"
        find "$OUTPUT_DIR" -name "*.txt" -o -name "*.json" 2>/dev/null | sort | sed 's/^/  /'
    fi
    
    echo ""
    if [ $FAIL_COUNT -eq 0 ]; then
        print_success "All discovery tasks completed successfully"
        echo ""
        echo "Next Steps:"
        echo "  1. Review the discovery reports in $OUTPUT_DIR"
        echo "  2. Proceed to Step 1: Discovery Questionnaire"
    else
        print_warning "$FAIL_COUNT of 3 discovery tasks had issues"
        echo ""
        echo "Next Steps:"
        echo "  1. Review the errors above and fix connectivity issues"
        echo "  2. Re-run the failed discovery tasks"
        echo "  3. Proceed to Step 1 when all discovery is complete"
    fi
}

#===============================================================================
# Main Execution
#===============================================================================

main() {
    # Parse command line arguments
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
            print_header "SSH Connectivity Test"
            show_config
            test_all_connectivity
            exit 0
            ;;
        -s|--source-only)
            print_header "Source Server Discovery Only"
            validate_config
            run_source_discovery
            exit $?
            ;;
        -g|--target-only)
            print_header "Target Server Discovery Only"
            validate_config
            run_target_discovery
            exit $?
            ;;
        -z|--zdm-only)
            print_header "ZDM Server Discovery Only"
            validate_config
            run_zdm_discovery
            exit $?
            ;;
        "")
            run_all_discovery
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
