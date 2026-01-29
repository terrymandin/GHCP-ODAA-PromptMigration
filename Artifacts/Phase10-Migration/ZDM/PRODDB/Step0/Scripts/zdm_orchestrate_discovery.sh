#!/bin/bash
###############################################################################
# ZDM Discovery Orchestration Script
# Project: PRODDB Migration to Oracle Database@Azure
#
# Purpose: Orchestrate discovery across source, target, and ZDM servers
# Run from: Any machine with SSH access to all three servers
#
# Generated: 2026-01-29
###############################################################################

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color
BOLD='\033[1m'

###############################################################################
# Configuration - Customize for PRODDB Migration
###############################################################################

# Project Configuration
PROJECT_NAME="PRODDB"
DB_NAME="PRODDB"

# Server Configuration
SOURCE_HOST="${SOURCE_HOST:-proddb01.corp.example.com}"
SOURCE_USER="${SOURCE_USER:-oracle}"
TARGET_HOST="${TARGET_HOST:-proddb-oda.eastus.azure.example.com}"
TARGET_USER="${TARGET_USER:-opc}"
ZDM_HOST="${ZDM_HOST:-zdm-jumpbox.corp.example.com}"
ZDM_USER="${ZDM_USER:-zdmuser}"

# SSH Key Configuration (separate keys for each environment)
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-~/.ssh/source_db_key}"
TARGET_SSH_KEY="${TARGET_SSH_KEY:-~/.ssh/oda_azure_key}"
ZDM_SSH_KEY="${ZDM_SSH_KEY:-~/.ssh/zdm_jumpbox_key}"

# SSH Options
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=30 -o BatchMode=yes"

# Explicit Environment Variable Overrides (use if profile sourcing fails)
# Source server overrides
SOURCE_REMOTE_ORACLE_HOME="${SOURCE_REMOTE_ORACLE_HOME:-/u01/app/oracle/product/19.0.0.0/dbhome_1}"
SOURCE_REMOTE_ORACLE_SID="${SOURCE_REMOTE_ORACLE_SID:-PRODDB}"

# Target server overrides
TARGET_REMOTE_ORACLE_HOME="${TARGET_REMOTE_ORACLE_HOME:-/u01/app/oracle/product/19.0.0.0/dbhome_1}"
TARGET_REMOTE_ORACLE_SID="${TARGET_REMOTE_ORACLE_SID:-PRODDB}"

# ZDM server overrides
ZDM_REMOTE_ZDM_HOME="${ZDM_REMOTE_ZDM_HOME:-/home/zdmuser/zdmhome}"
ZDM_REMOTE_JAVA_HOME="${ZDM_REMOTE_JAVA_HOME:-/usr/java/jdk1.8.0_391}"

# Output Directory Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_BASE="${OUTPUT_DIR:-${SCRIPT_DIR}/../Discovery}"

# Tracking variables
FAILURES=0
SUCCESSES=0
declare -a FAILED_SERVERS
declare -a SUCCESS_SERVERS

###############################################################################
# Helper Functions
###############################################################################

print_banner() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                                           ║${NC}"
    echo -e "${GREEN}║     ${BOLD}ZDM Discovery Orchestration${NC}${GREEN}                                          ║${NC}"
    echo -e "${GREEN}║     Project: PRODDB Migration to Oracle Database@Azure                  ║${NC}"
    echo -e "${GREEN}║                                                                           ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_header() {
    echo ""
    echo -e "${CYAN}===============================================================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}===============================================================================${NC}"
    echo ""
}

print_section() {
    echo ""
    echo -e "${YELLOW}--- $1 ---${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

usage() {
    cat << EOF
${BOLD}ZDM Discovery Orchestration Script${NC}
Project: PRODDB Migration to Oracle Database@Azure

${BOLD}Usage:${NC}
    $(basename "$0") [options]

${BOLD}Options:${NC}
    -h, --help              Show this help message
    -c, --config            Display current configuration
    -t, --test              Test SSH connectivity only (no discovery)
    -s, --source-only       Run discovery on source server only
    -T, --target-only       Run discovery on target server only
    -z, --zdm-only          Run discovery on ZDM server only
    -o, --output DIR        Override output directory
    -v, --verbose           Enable verbose output

${BOLD}Environment Variables:${NC}
    SOURCE_HOST             Source database hostname (default: proddb01.corp.example.com)
    SOURCE_USER             Source SSH user (default: oracle)
    SOURCE_SSH_KEY          Source SSH private key path
    TARGET_HOST             Target database hostname (default: proddb-oda.eastus.azure.example.com)
    TARGET_USER             Target SSH user (default: opc)
    TARGET_SSH_KEY          Target SSH private key path
    ZDM_HOST                ZDM server hostname (default: zdm-jumpbox.corp.example.com)
    ZDM_USER                ZDM SSH user (default: zdmuser)
    ZDM_SSH_KEY             ZDM SSH private key path
    OUTPUT_DIR              Output directory for discovery results

${BOLD}Environment Override Variables (for non-interactive shell issues):${NC}
    SOURCE_REMOTE_ORACLE_HOME   Explicit Oracle home path on source
    SOURCE_REMOTE_ORACLE_SID    Explicit Oracle SID on source
    TARGET_REMOTE_ORACLE_HOME   Explicit Oracle home path on target
    TARGET_REMOTE_ORACLE_SID    Explicit Oracle SID on target
    ZDM_REMOTE_ZDM_HOME         Explicit ZDM home path on ZDM server
    ZDM_REMOTE_JAVA_HOME        Explicit Java home path on ZDM server

${BOLD}Examples:${NC}
    # Run full discovery
    $(basename "$0")

    # Test connectivity only
    $(basename "$0") --test

    # Run with custom SSH keys
    SOURCE_SSH_KEY=~/.ssh/prod_key TARGET_SSH_KEY=~/.ssh/azure_key $(basename "$0")

    # Run source discovery only
    $(basename "$0") --source-only

EOF
}

show_config() {
    print_header "Current Configuration"
    
    echo -e "${BOLD}Project:${NC}"
    echo "  Project Name: $PROJECT_NAME"
    echo "  Database Name: $DB_NAME"
    echo ""
    
    echo -e "${BOLD}Source Database:${NC}"
    echo "  Host: $SOURCE_HOST"
    echo "  User: $SOURCE_USER"
    echo "  SSH Key: $SOURCE_SSH_KEY"
    echo "  Remote ORACLE_HOME: $SOURCE_REMOTE_ORACLE_HOME"
    echo "  Remote ORACLE_SID: $SOURCE_REMOTE_ORACLE_SID"
    echo ""
    
    echo -e "${BOLD}Target Database (Oracle Database@Azure):${NC}"
    echo "  Host: $TARGET_HOST"
    echo "  User: $TARGET_USER"
    echo "  SSH Key: $TARGET_SSH_KEY"
    echo "  Remote ORACLE_HOME: $TARGET_REMOTE_ORACLE_HOME"
    echo "  Remote ORACLE_SID: $TARGET_REMOTE_ORACLE_SID"
    echo ""
    
    echo -e "${BOLD}ZDM Server:${NC}"
    echo "  Host: $ZDM_HOST"
    echo "  User: $ZDM_USER"
    echo "  SSH Key: $ZDM_SSH_KEY"
    echo "  Remote ZDM_HOME: $ZDM_REMOTE_ZDM_HOME"
    echo "  Remote JAVA_HOME: $ZDM_REMOTE_JAVA_HOME"
    echo ""
    
    echo -e "${BOLD}Output:${NC}"
    echo "  Output Directory: $OUTPUT_BASE"
    echo ""
}

validate_config() {
    print_header "Validating Configuration"
    local errors=0
    
    # Check SSH keys exist
    for key_var in SOURCE_SSH_KEY TARGET_SSH_KEY ZDM_SSH_KEY; do
        key_path="${!key_var}"
        key_path="${key_path/#\~/$HOME}"
        if [ ! -f "$key_path" ]; then
            print_error "$key_var: File not found: $key_path"
            ((errors++))
        else
            print_success "$key_var: $key_path (found)"
        fi
    done
    
    # Check discovery scripts exist
    for script in zdm_source_discovery.sh zdm_target_discovery.sh zdm_server_discovery.sh; do
        if [ ! -f "$SCRIPT_DIR/$script" ]; then
            print_error "Discovery script not found: $SCRIPT_DIR/$script"
            ((errors++))
        else
            print_success "Discovery script found: $script"
        fi
    done
    
    if [ $errors -gt 0 ]; then
        print_error "Configuration validation failed with $errors error(s)"
        return 1
    fi
    
    print_success "Configuration validation passed"
    return 0
}

test_ssh_connectivity() {
    local host="$1"
    local user="$2"
    local key="$3"
    local label="$4"
    
    key="${key/#\~/$HOME}"
    
    print_section "Testing SSH connectivity to $label ($user@$host)"
    
    if ssh $SSH_OPTS -i "$key" "$user@$host" "echo 'SSH connection successful'; hostname; whoami" 2>&1; then
        print_success "SSH connectivity to $label: OK"
        return 0
    else
        print_error "SSH connectivity to $label: FAILED"
        return 1
    fi
}

test_all_connectivity() {
    print_header "Testing SSH Connectivity"
    local failures=0
    
    test_ssh_connectivity "$SOURCE_HOST" "$SOURCE_USER" "$SOURCE_SSH_KEY" "Source Database" || ((failures++))
    test_ssh_connectivity "$TARGET_HOST" "$TARGET_USER" "$TARGET_SSH_KEY" "Target Database" || ((failures++))
    test_ssh_connectivity "$ZDM_HOST" "$ZDM_USER" "$ZDM_SSH_KEY" "ZDM Server" || ((failures++))
    
    echo ""
    if [ $failures -eq 0 ]; then
        print_success "All SSH connectivity tests passed"
        return 0
    else
        print_error "$failures SSH connectivity test(s) failed"
        return 1
    fi
}

###############################################################################
# Discovery Execution Functions
###############################################################################

run_source_discovery() {
    print_header "Source Database Discovery"
    print_info "Host: $SOURCE_USER@$SOURCE_HOST"
    
    local key="${SOURCE_SSH_KEY/#\~/$HOME}"
    local script_name="zdm_source_discovery.sh"
    local remote_dir="/tmp/zdm_discovery_$$"
    local output_dir="$OUTPUT_BASE/source"
    
    mkdir -p "$output_dir"
    
    # Build environment override exports
    local env_exports=""
    [ -n "$SOURCE_REMOTE_ORACLE_HOME" ] && env_exports+="export ORACLE_HOME_OVERRIDE='$SOURCE_REMOTE_ORACLE_HOME'; "
    [ -n "$SOURCE_REMOTE_ORACLE_SID" ] && env_exports+="export ORACLE_SID_OVERRIDE='$SOURCE_REMOTE_ORACLE_SID'; "
    
    print_section "Copying discovery script to source server"
    if ! scp $SSH_OPTS -i "$key" "$SCRIPT_DIR/$script_name" "$SOURCE_USER@$SOURCE_HOST:$remote_dir/" 2>&1; then
        # Create remote directory first
        ssh $SSH_OPTS -i "$key" "$SOURCE_USER@$SOURCE_HOST" "mkdir -p $remote_dir" 2>&1
        scp $SSH_OPTS -i "$key" "$SCRIPT_DIR/$script_name" "$SOURCE_USER@$SOURCE_HOST:$remote_dir/" 2>&1 || {
            print_error "Failed to copy discovery script to source server"
            FAILED_SERVERS+=("Source: $SOURCE_HOST")
            ((FAILURES++))
            return 1
        }
    fi
    print_success "Script copied successfully"
    
    print_section "Executing discovery script on source server"
    print_info "Using bash -l for login shell to source environment"
    
    # Execute with login shell and environment overrides
    if ssh $SSH_OPTS -i "$key" "$SOURCE_USER@$SOURCE_HOST" \
        "cd $remote_dir && ${env_exports} bash -l -c 'chmod +x $script_name && ./$script_name'" 2>&1; then
        print_success "Discovery script executed successfully"
    else
        print_warning "Discovery script completed with warnings (some sections may have failed)"
    fi
    
    print_section "Collecting discovery output"
    scp $SSH_OPTS -i "$key" "$SOURCE_USER@$SOURCE_HOST:$remote_dir/zdm_source_discovery_*.txt" "$output_dir/" 2>&1 || print_warning "No .txt output found"
    scp $SSH_OPTS -i "$key" "$SOURCE_USER@$SOURCE_HOST:$remote_dir/zdm_source_discovery_*.json" "$output_dir/" 2>&1 || print_warning "No .json output found"
    
    # Cleanup remote directory
    ssh $SSH_OPTS -i "$key" "$SOURCE_USER@$SOURCE_HOST" "rm -rf $remote_dir" 2>/dev/null
    
    # Check if files were collected
    if ls "$output_dir"/zdm_source_discovery_*.txt 1>/dev/null 2>&1; then
        print_success "Source discovery output collected to: $output_dir"
        SUCCESS_SERVERS+=("Source: $SOURCE_HOST")
        ((SUCCESSES++))
        return 0
    else
        print_error "No discovery output files collected from source"
        FAILED_SERVERS+=("Source: $SOURCE_HOST")
        ((FAILURES++))
        return 1
    fi
}

run_target_discovery() {
    print_header "Target Database Discovery (Oracle Database@Azure)"
    print_info "Host: $TARGET_USER@$TARGET_HOST"
    
    local key="${TARGET_SSH_KEY/#\~/$HOME}"
    local script_name="zdm_target_discovery.sh"
    local remote_dir="/tmp/zdm_discovery_$$"
    local output_dir="$OUTPUT_BASE/target"
    
    mkdir -p "$output_dir"
    
    # Build environment override exports
    local env_exports=""
    [ -n "$TARGET_REMOTE_ORACLE_HOME" ] && env_exports+="export ORACLE_HOME_OVERRIDE='$TARGET_REMOTE_ORACLE_HOME'; "
    [ -n "$TARGET_REMOTE_ORACLE_SID" ] && env_exports+="export ORACLE_SID_OVERRIDE='$TARGET_REMOTE_ORACLE_SID'; "
    
    print_section "Copying discovery script to target server"
    ssh $SSH_OPTS -i "$key" "$TARGET_USER@$TARGET_HOST" "mkdir -p $remote_dir" 2>&1
    if ! scp $SSH_OPTS -i "$key" "$SCRIPT_DIR/$script_name" "$TARGET_USER@$TARGET_HOST:$remote_dir/" 2>&1; then
        print_error "Failed to copy discovery script to target server"
        FAILED_SERVERS+=("Target: $TARGET_HOST")
        ((FAILURES++))
        return 1
    fi
    print_success "Script copied successfully"
    
    print_section "Executing discovery script on target server"
    print_info "Using bash -l for login shell to source environment"
    
    # For ODA, we may need to switch to oracle user
    if ssh $SSH_OPTS -i "$key" "$TARGET_USER@$TARGET_HOST" \
        "cd $remote_dir && ${env_exports} bash -l -c 'chmod +x $script_name && ./$script_name'" 2>&1; then
        print_success "Discovery script executed successfully"
    else
        print_warning "Discovery script completed with warnings (some sections may have failed)"
    fi
    
    print_section "Collecting discovery output"
    scp $SSH_OPTS -i "$key" "$TARGET_USER@$TARGET_HOST:$remote_dir/zdm_target_discovery_*.txt" "$output_dir/" 2>&1 || print_warning "No .txt output found"
    scp $SSH_OPTS -i "$key" "$TARGET_USER@$TARGET_HOST:$remote_dir/zdm_target_discovery_*.json" "$output_dir/" 2>&1 || print_warning "No .json output found"
    
    # Cleanup remote directory
    ssh $SSH_OPTS -i "$key" "$TARGET_USER@$TARGET_HOST" "rm -rf $remote_dir" 2>/dev/null
    
    # Check if files were collected
    if ls "$output_dir"/zdm_target_discovery_*.txt 1>/dev/null 2>&1; then
        print_success "Target discovery output collected to: $output_dir"
        SUCCESS_SERVERS+=("Target: $TARGET_HOST")
        ((SUCCESSES++))
        return 0
    else
        print_error "No discovery output files collected from target"
        FAILED_SERVERS+=("Target: $TARGET_HOST")
        ((FAILURES++))
        return 1
    fi
}

run_zdm_discovery() {
    print_header "ZDM Server Discovery"
    print_info "Host: $ZDM_USER@$ZDM_HOST"
    
    local key="${ZDM_SSH_KEY/#\~/$HOME}"
    local script_name="zdm_server_discovery.sh"
    local remote_dir="/tmp/zdm_discovery_$$"
    local output_dir="$OUTPUT_BASE/server"
    
    mkdir -p "$output_dir"
    
    # Build environment override exports
    local env_exports=""
    [ -n "$ZDM_REMOTE_ZDM_HOME" ] && env_exports+="export ZDM_HOME_OVERRIDE='$ZDM_REMOTE_ZDM_HOME'; "
    [ -n "$ZDM_REMOTE_JAVA_HOME" ] && env_exports+="export JAVA_HOME_OVERRIDE='$ZDM_REMOTE_JAVA_HOME'; "
    # Pass source and target hosts for connectivity tests
    env_exports+="export SOURCE_HOST='$SOURCE_HOST'; export TARGET_HOST='$TARGET_HOST'; "
    
    print_section "Copying discovery script to ZDM server"
    ssh $SSH_OPTS -i "$key" "$ZDM_USER@$ZDM_HOST" "mkdir -p $remote_dir" 2>&1
    if ! scp $SSH_OPTS -i "$key" "$SCRIPT_DIR/$script_name" "$ZDM_USER@$ZDM_HOST:$remote_dir/" 2>&1; then
        print_error "Failed to copy discovery script to ZDM server"
        FAILED_SERVERS+=("ZDM: $ZDM_HOST")
        ((FAILURES++))
        return 1
    fi
    print_success "Script copied successfully"
    
    print_section "Executing discovery script on ZDM server"
    print_info "Using bash -l for login shell to source environment"
    
    if ssh $SSH_OPTS -i "$key" "$ZDM_USER@$ZDM_HOST" \
        "cd $remote_dir && ${env_exports} bash -l -c 'chmod +x $script_name && ./$script_name'" 2>&1; then
        print_success "Discovery script executed successfully"
    else
        print_warning "Discovery script completed with warnings (some sections may have failed)"
    fi
    
    print_section "Collecting discovery output"
    scp $SSH_OPTS -i "$key" "$ZDM_USER@$ZDM_HOST:$remote_dir/zdm_server_discovery_*.txt" "$output_dir/" 2>&1 || print_warning "No .txt output found"
    scp $SSH_OPTS -i "$key" "$ZDM_USER@$ZDM_HOST:$remote_dir/zdm_server_discovery_*.json" "$output_dir/" 2>&1 || print_warning "No .json output found"
    
    # Cleanup remote directory
    ssh $SSH_OPTS -i "$key" "$ZDM_USER@$ZDM_HOST" "rm -rf $remote_dir" 2>/dev/null
    
    # Check if files were collected
    if ls "$output_dir"/zdm_server_discovery_*.txt 1>/dev/null 2>&1; then
        print_success "ZDM server discovery output collected to: $output_dir"
        SUCCESS_SERVERS+=("ZDM: $ZDM_HOST")
        ((SUCCESSES++))
        return 0
    else
        print_error "No discovery output files collected from ZDM server"
        FAILED_SERVERS+=("ZDM: $ZDM_HOST")
        ((FAILURES++))
        return 1
    fi
}

print_summary() {
    print_header "Discovery Summary"
    
    echo -e "${BOLD}Results:${NC}"
    echo "  Successful: $SUCCESSES"
    echo "  Failed: $FAILURES"
    echo ""
    
    if [ ${#SUCCESS_SERVERS[@]} -gt 0 ]; then
        echo -e "${GREEN}Successful Discoveries:${NC}"
        for server in "${SUCCESS_SERVERS[@]}"; do
            echo "  ✓ $server"
        done
        echo ""
    fi
    
    if [ ${#FAILED_SERVERS[@]} -gt 0 ]; then
        echo -e "${RED}Failed Discoveries:${NC}"
        for server in "${FAILED_SERVERS[@]}"; do
            echo "  ✗ $server"
        done
        echo ""
    fi
    
    echo -e "${BOLD}Output Location:${NC}"
    echo "  $OUTPUT_BASE"
    echo ""
    
    if [ -d "$OUTPUT_BASE" ]; then
        echo -e "${BOLD}Collected Files:${NC}"
        find "$OUTPUT_BASE" -type f -name "*.txt" -o -name "*.json" 2>/dev/null | while read file; do
            echo "  $(basename "$file")"
        done
    fi
    
    echo ""
    if [ $FAILURES -eq 0 ]; then
        echo -e "${GREEN}${BOLD}All discoveries completed successfully!${NC}"
    elif [ $SUCCESSES -gt 0 ]; then
        echo -e "${YELLOW}${BOLD}Partial success: $SUCCESSES of $((SUCCESSES + FAILURES)) discoveries completed${NC}"
    else
        echo -e "${RED}${BOLD}All discoveries failed${NC}"
    fi
    
    echo ""
    echo -e "${BOLD}Next Steps:${NC}"
    echo "  1. Review discovery output files in $OUTPUT_BASE"
    echo "  2. Proceed to Step 1: Discovery Questionnaire"
    echo "     - Use the discovery data to complete the migration questionnaire"
    echo ""
}

###############################################################################
# Main Execution
###############################################################################

main() {
    # Parse command line arguments
    local run_source=true
    local run_target=true
    local run_zdm=true
    local test_only=false
    local verbose=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -c|--config)
                print_banner
                show_config
                exit 0
                ;;
            -t|--test)
                test_only=true
                shift
                ;;
            -s|--source-only)
                run_source=true
                run_target=false
                run_zdm=false
                shift
                ;;
            -T|--target-only)
                run_source=false
                run_target=true
                run_zdm=false
                shift
                ;;
            -z|--zdm-only)
                run_source=false
                run_target=false
                run_zdm=true
                shift
                ;;
            -o|--output)
                OUTPUT_BASE="$2"
                shift 2
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Print banner
    print_banner
    
    # Show configuration
    show_config
    
    # Validate configuration
    if ! validate_config; then
        echo ""
        print_error "Please fix configuration errors and try again"
        exit 1
    fi
    
    # Test connectivity
    if ! test_all_connectivity; then
        if [ "$test_only" = true ]; then
            exit 1
        fi
        echo ""
        print_warning "Some SSH connectivity tests failed"
        print_info "Discovery will continue but may fail for unreachable servers"
        echo ""
    fi
    
    # If test only, exit here
    if [ "$test_only" = true ]; then
        echo ""
        print_info "Connectivity test complete. Use without --test to run full discovery."
        exit 0
    fi
    
    # Create output directory
    mkdir -p "$OUTPUT_BASE"
    
    # Run discoveries (continue on failure)
    if [ "$run_source" = true ]; then
        run_source_discovery || true
    fi
    
    if [ "$run_target" = true ]; then
        run_target_discovery || true
    fi
    
    if [ "$run_zdm" = true ]; then
        run_zdm_discovery || true
    fi
    
    # Print summary
    print_summary
    
    # Exit with appropriate code
    if [ $FAILURES -eq 0 ]; then
        exit 0
    elif [ $SUCCESSES -gt 0 ]; then
        exit 2  # Partial success
    else
        exit 1  # Complete failure
    fi
}

# Run main function
main "$@"
