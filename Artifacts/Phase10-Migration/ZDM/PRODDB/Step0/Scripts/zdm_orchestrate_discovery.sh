#!/bin/bash
#===============================================================================
# ZDM Discovery Orchestration Script
# Project: PRODDB Migration to Oracle Database@Azure
# Generated: 2026-01-29
#===============================================================================
# Usage: ./zdm_orchestrate_discovery.sh [OPTIONS]
# Options:
#   -h, --help     Show help message
#   -c, --config   Display current configuration
#   -t, --test     Test SSH connectivity only
#   -s, --source   Run source discovery only
#   -T, --target   Run target discovery only
#   -z, --zdm      Run ZDM server discovery only
#===============================================================================

#-------------------------------------------------------------------------------
# Configuration - MODIFY THESE VALUES FOR YOUR ENVIRONMENT
#-------------------------------------------------------------------------------
SOURCE_HOST="proddb01.corp.example.com"
SOURCE_USER="oracle"

TARGET_HOST="proddb-oda.eastus.azure.example.com"
TARGET_USER="opc"

ZDM_HOST="zdm-jumpbox.corp.example.com"
ZDM_USER="zdmuser"

SSH_KEY="~/.ssh/id_rsa"
SSH_OPTIONS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"

# Local output directory
OUTPUT_DIR="./Discovery"
SCRIPTS_DIR="$(dirname "$0")"

#-------------------------------------------------------------------------------
# Color Codes
#-------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

#-------------------------------------------------------------------------------
# Utility Functions
#-------------------------------------------------------------------------------
log_header() {
    echo ""
    echo -e "${BLUE}${BOLD}================================================================${NC}"
    echo -e "${BLUE}${BOLD}= $1${NC}"
    echo -e "${BLUE}${BOLD}================================================================${NC}"
    echo ""
}

log_section() {
    echo ""
    echo -e "${CYAN}--- $1 ---${NC}"
}

log_info() {
    echo -e "${NC}$1${NC}"
}

log_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

log_warn() {
    echo -e "${YELLOW}⚠ WARNING: $1${NC}"
}

log_error() {
    echo -e "${RED}✗ ERROR: $1${NC}"
}

show_help() {
    echo ""
    echo -e "${BOLD}ZDM Discovery Orchestration Script${NC}"
    echo ""
    echo -e "${BOLD}USAGE:${NC}"
    echo "    $0 [OPTIONS]"
    echo ""
    echo -e "${BOLD}OPTIONS:${NC}"
    echo "    -h, --help     Show this help message"
    echo "    -c, --config   Display current configuration"
    echo "    -t, --test     Test SSH connectivity only (no discovery)"
    echo "    -s, --source   Run source discovery only"
    echo "    -T, --target   Run target discovery only"
    echo "    -z, --zdm      Run ZDM server discovery only"
    echo "    (no options)   Run full discovery on all servers"
    echo ""
    echo -e "${BOLD}CONFIGURATION:${NC}"
    echo "    Edit this script to modify server hostnames, users, and SSH key path."
    echo ""
    echo -e "${BOLD}EXAMPLES:${NC}"
    echo "    $0              # Run full discovery on all servers"
    echo "    $0 --test       # Test connectivity before running discovery"
    echo "    $0 --source     # Run discovery on source server only"
    echo ""
}

show_config() {
    log_header "Current Configuration"
    echo -e "${BOLD}Source Database:${NC}"
    echo "    Host: $SOURCE_HOST"
    echo "    User: $SOURCE_USER"
    echo ""
    echo -e "${BOLD}Target Database (Oracle Database@Azure):${NC}"
    echo "    Host: $TARGET_HOST"
    echo "    User: $TARGET_USER"
    echo ""
    echo -e "${BOLD}ZDM Server:${NC}"
    echo "    Host: $ZDM_HOST"
    echo "    User: $ZDM_USER"
    echo ""
    echo -e "${BOLD}SSH Configuration:${NC}"
    echo "    Key: $SSH_KEY"
    echo "    Options: $SSH_OPTIONS"
    echo ""
    echo -e "${BOLD}Output Directory:${NC}"
    echo "    $OUTPUT_DIR"
    echo ""
}

validate_config() {
    log_section "Validating Configuration"
    
    local errors=0
    
    # Check if SSH key exists
    SSH_KEY_EXPANDED="${SSH_KEY/#\~/$HOME}"
    if [ ! -f "$SSH_KEY_EXPANDED" ]; then
        log_error "SSH key not found: $SSH_KEY"
        errors=$((errors + 1))
    else
        log_success "SSH key found: $SSH_KEY"
    fi
    
    # Check if discovery scripts exist
    if [ ! -f "$SCRIPTS_DIR/zdm_source_discovery.sh" ]; then
        log_error "Source discovery script not found: $SCRIPTS_DIR/zdm_source_discovery.sh"
        errors=$((errors + 1))
    else
        log_success "Source discovery script found"
    fi
    
    if [ ! -f "$SCRIPTS_DIR/zdm_target_discovery.sh" ]; then
        log_error "Target discovery script not found: $SCRIPTS_DIR/zdm_target_discovery.sh"
        errors=$((errors + 1))
    else
        log_success "Target discovery script found"
    fi
    
    if [ ! -f "$SCRIPTS_DIR/zdm_server_discovery.sh" ]; then
        log_error "ZDM server discovery script not found: $SCRIPTS_DIR/zdm_server_discovery.sh"
        errors=$((errors + 1))
    else
        log_success "ZDM server discovery script found"
    fi
    
    return $errors
}

test_ssh_connectivity() {
    local host=$1
    local user=$2
    local description=$3
    
    echo -n "Testing SSH to $description ($user@$host)... "
    
    if ssh -i "$SSH_KEY_EXPANDED" $SSH_OPTIONS "$user@$host" "echo 'Connected'" >/dev/null 2>&1; then
        log_success "Connected"
        return 0
    else
        log_error "Failed"
        return 1
    fi
}

test_all_connectivity() {
    log_section "Testing SSH Connectivity"
    
    local failures=0
    
    test_ssh_connectivity "$SOURCE_HOST" "$SOURCE_USER" "Source Database" || failures=$((failures + 1))
    test_ssh_connectivity "$TARGET_HOST" "$TARGET_USER" "Target Database" || failures=$((failures + 1))
    test_ssh_connectivity "$ZDM_HOST" "$ZDM_USER" "ZDM Server" || failures=$((failures + 1))
    
    echo ""
    if [ $failures -eq 0 ]; then
        log_success "All SSH connections successful"
        return 0
    else
        log_error "$failures connection(s) failed"
        return 1
    fi
}

run_remote_discovery() {
    local host=$1
    local user=$2
    local script=$3
    local description=$4
    
    log_section "Running Discovery on $description"
    echo "Host: $user@$host"
    echo "Script: $script"
    echo ""
    
    # Copy script to remote host
    echo "Copying discovery script..."
    scp -i "$SSH_KEY_EXPANDED" $SSH_OPTIONS "$script" "$user@$host:/tmp/" 2>&1
    if [ $? -ne 0 ]; then
        log_error "Failed to copy script to $host"
        return 1
    fi
    log_success "Script copied"
    
    # Make script executable and run it
    local script_name=$(basename "$script")
    echo "Executing discovery script..."
    ssh -i "$SSH_KEY_EXPANDED" $SSH_OPTIONS "$user@$host" "chmod +x /tmp/$script_name && /tmp/$script_name" 2>&1
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        log_error "Discovery script failed on $host (exit code: $exit_code)"
        return 1
    fi
    log_success "Discovery completed"
    
    # Collect output files
    echo "Collecting output files..."
    mkdir -p "$OUTPUT_DIR"
    
    # Get the output files (text and JSON)
    scp -i "$SSH_KEY_EXPANDED" $SSH_OPTIONS "$user@$host:/tmp/zdm_*_discovery_*.txt" "$OUTPUT_DIR/" 2>&1
    scp -i "$SSH_KEY_EXPANDED" $SSH_OPTIONS "$user@$host:/tmp/zdm_*_discovery_*.json" "$OUTPUT_DIR/" 2>&1
    
    log_success "Output files collected to $OUTPUT_DIR"
    
    # Clean up remote files
    echo "Cleaning up remote files..."
    ssh -i "$SSH_KEY_EXPANDED" $SSH_OPTIONS "$user@$host" "rm -f /tmp/$script_name /tmp/zdm_*_discovery_*" 2>&1
    log_success "Remote cleanup completed"
    
    return 0
}

run_source_discovery() {
    run_remote_discovery "$SOURCE_HOST" "$SOURCE_USER" "$SCRIPTS_DIR/zdm_source_discovery.sh" "Source Database"
}

run_target_discovery() {
    run_remote_discovery "$TARGET_HOST" "$TARGET_USER" "$SCRIPTS_DIR/zdm_target_discovery.sh" "Target Database (Oracle Database@Azure)"
}

run_zdm_discovery() {
    run_remote_discovery "$ZDM_HOST" "$ZDM_USER" "$SCRIPTS_DIR/zdm_server_discovery.sh" "ZDM Server"
}

run_full_discovery() {
    log_header "ZDM Discovery Orchestration"
    echo "Project: PRODDB Migration to Oracle Database@Azure"
    echo "Date: $(date)"
    echo ""
    
    # Validate configuration
    validate_config
    if [ $? -ne 0 ]; then
        log_error "Configuration validation failed. Please fix the errors above."
        exit 1
    fi
    
    # Test connectivity
    test_all_connectivity
    if [ $? -ne 0 ]; then
        log_error "SSH connectivity tests failed. Please fix the connection issues."
        exit 1
    fi
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # Run discovery on each server
    local failures=0
    
    run_source_discovery || failures=$((failures + 1))
    run_target_discovery || failures=$((failures + 1))
    run_zdm_discovery || failures=$((failures + 1))
    
    # Summary
    log_header "Discovery Summary"
    
    if [ $failures -eq 0 ]; then
        log_success "All discoveries completed successfully"
    else
        log_error "$failures discovery operation(s) failed"
    fi
    
    echo ""
    echo -e "${BOLD}Output Files:${NC}"
    ls -la "$OUTPUT_DIR"/*.txt "$OUTPUT_DIR"/*.json 2>/dev/null || echo "  No output files found"
    
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "1. Review all discovery reports in $OUTPUT_DIR"
    echo "2. Identify any issues or missing requirements"
    echo "3. Proceed to Step 1: Discovery Questionnaire"
    echo ""
    
    return $failures
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------

# Expand SSH key path
SSH_KEY_EXPANDED="${SSH_KEY/#\~/$HOME}"

# Parse command line arguments
case "$1" in
    -h|--help)
        show_help
        exit 0
        ;;
    -c|--config)
        show_config
        exit 0
        ;;
    -t|--test)
        log_header "SSH Connectivity Test"
        validate_config
        test_all_connectivity
        exit $?
        ;;
    -s|--source)
        log_header "Source Discovery Only"
        validate_config
        test_ssh_connectivity "$SOURCE_HOST" "$SOURCE_USER" "Source Database"
        if [ $? -eq 0 ]; then
            mkdir -p "$OUTPUT_DIR"
            run_source_discovery
        fi
        exit $?
        ;;
    -T|--target)
        log_header "Target Discovery Only"
        validate_config
        test_ssh_connectivity "$TARGET_HOST" "$TARGET_USER" "Target Database"
        if [ $? -eq 0 ]; then
            mkdir -p "$OUTPUT_DIR"
            run_target_discovery
        fi
        exit $?
        ;;
    -z|--zdm)
        log_header "ZDM Server Discovery Only"
        validate_config
        test_ssh_connectivity "$ZDM_HOST" "$ZDM_USER" "ZDM Server"
        if [ $? -eq 0 ]; then
            mkdir -p "$OUTPUT_DIR"
            run_zdm_discovery
        fi
        exit $?
        ;;
    "")
        # No arguments - run full discovery
        run_full_discovery
        exit $?
        ;;
    *)
        log_error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac
