#!/bin/bash
################################################################################
# ZDM Discovery Orchestration Script
# Project: PRODDB Migration to Oracle Database@Azure
# Generated: 2026-01-29
#
# Purpose: Orchestrates discovery across all servers (source, target, ZDM)
#          Copies scripts, executes remotely, and collects results.
#
# Usage: ./zdm_orchestrate_discovery.sh [OPTIONS]
#
# Options:
#   -h, --help     Show help message
#   -c, --config   Display current configuration
#   -t, --test     Test connectivity only (do not run discovery)
#   -o, --output   Specify output directory
#
# Environment Variables:
#   SOURCE_SSH_KEY  - SSH key for source database server
#   TARGET_SSH_KEY  - SSH key for target Oracle Database@Azure server
#   ZDM_SSH_KEY     - SSH key for ZDM jumpbox server
#   OUTPUT_DIR      - Directory for collected discovery files
################################################################################

set -o pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

################################################################################
# Configuration - Pre-configured for PRODDB Migration
################################################################################

# Source Database Server
SOURCE_HOST="${SOURCE_HOST:-proddb01.corp.example.com}"
SOURCE_USER="${SOURCE_USER:-oracle}"
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-~/.ssh/source_db_key}"

# Target Oracle Database@Azure Server
TARGET_HOST="${TARGET_HOST:-proddb-oda.eastus.azure.example.com}"
TARGET_USER="${TARGET_USER:-opc}"
TARGET_SSH_KEY="${TARGET_SSH_KEY:-~/.ssh/oda_azure_key}"

# ZDM Jumpbox Server
ZDM_HOST="${ZDM_HOST:-zdm-jumpbox.corp.example.com}"
ZDM_USER="${ZDM_USER:-zdmuser}"
ZDM_SSH_KEY="${ZDM_SSH_KEY:-~/.ssh/zdm_jumpbox_key}"

# Output directory - defaults to Artifacts location
OUTPUT_DIR="${OUTPUT_DIR:-$(dirname "$SCRIPT_DIR")/Discovery}"

# Script names
SOURCE_SCRIPT="zdm_source_discovery.sh"
TARGET_SCRIPT="zdm_target_discovery.sh"
ZDM_SCRIPT="zdm_server_discovery.sh"

# Remote working directory
REMOTE_WORK_DIR="/tmp/zdm_discovery"

# SSH options
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=30 -o BatchMode=yes"

# Error tracking for resilience
SOURCE_SUCCESS=false
TARGET_SUCCESS=false
ZDM_SUCCESS=false
TOTAL_ERRORS=0

################################################################################
# Helper Functions
################################################################################

print_header() {
    echo ""
    echo -e "${BOLD}${CYAN}================================================================================${NC}"
    echo -e "${BOLD}${CYAN}= $1${NC}"
    echo -e "${BOLD}${CYAN}================================================================================${NC}"
}

print_section() {
    echo ""
    echo -e "${BLUE}--- $1 ---${NC}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    cat << EOF
ZDM Discovery Orchestration Script
Project: PRODDB Migration to Oracle Database@Azure

Usage: $(basename "$0") [OPTIONS]

Options:
    -h, --help      Show this help message
    -c, --config    Display current configuration
    -t, --test      Test SSH connectivity only (do not run discovery)
    -o, --output    Specify output directory for collected files

Environment Variables:
    SOURCE_HOST     Source database hostname (default: proddb01.corp.example.com)
    SOURCE_USER     Source database user (default: oracle)
    SOURCE_SSH_KEY  SSH key for source server (default: ~/.ssh/source_db_key)
    
    TARGET_HOST     Target ODA@Azure hostname (default: proddb-oda.eastus.azure.example.com)
    TARGET_USER     Target database user (default: opc)
    TARGET_SSH_KEY  SSH key for target server (default: ~/.ssh/oda_azure_key)
    
    ZDM_HOST        ZDM jumpbox hostname (default: zdm-jumpbox.corp.example.com)
    ZDM_USER        ZDM user (default: zdmuser)
    ZDM_SSH_KEY     SSH key for ZDM server (default: ~/.ssh/zdm_jumpbox_key)
    
    OUTPUT_DIR      Output directory for collected files

Examples:
    # Run with defaults
    ./$(basename "$0")
    
    # Test connectivity only
    ./$(basename "$0") --test
    
    # Custom output directory
    ./$(basename "$0") -o /path/to/output
    
    # Override SSH keys
    SOURCE_SSH_KEY=~/.ssh/my_key ./$(basename "$0")

EOF
}

show_config() {
    print_header "Current Configuration"
    
    echo ""
    echo "Source Database Server:"
    echo "  Host:     $SOURCE_HOST"
    echo "  User:     $SOURCE_USER"
    echo "  SSH Key:  $SOURCE_SSH_KEY"
    echo ""
    echo "Target Oracle Database@Azure Server:"
    echo "  Host:     $TARGET_HOST"
    echo "  User:     $TARGET_USER"
    echo "  SSH Key:  $TARGET_SSH_KEY"
    echo ""
    echo "ZDM Jumpbox Server:"
    echo "  Host:     $ZDM_HOST"
    echo "  User:     $ZDM_USER"
    echo "  SSH Key:  $ZDM_SSH_KEY"
    echo ""
    echo "Output Directory:"
    echo "  $OUTPUT_DIR"
    echo ""
    echo "Script Directory:"
    echo "  $SCRIPT_DIR"
    echo ""
}

validate_config() {
    print_section "Validating Configuration"
    
    local errors=0
    
    # Expand SSH key paths
    SOURCE_SSH_KEY=$(eval echo "$SOURCE_SSH_KEY")
    TARGET_SSH_KEY=$(eval echo "$TARGET_SSH_KEY")
    ZDM_SSH_KEY=$(eval echo "$ZDM_SSH_KEY")
    
    # Check SSH keys exist
    if [ ! -f "$SOURCE_SSH_KEY" ]; then
        log_error "Source SSH key not found: $SOURCE_SSH_KEY"
        errors=$((errors + 1))
    else
        log_success "Source SSH key found: $SOURCE_SSH_KEY"
    fi
    
    if [ ! -f "$TARGET_SSH_KEY" ]; then
        log_error "Target SSH key not found: $TARGET_SSH_KEY"
        errors=$((errors + 1))
    else
        log_success "Target SSH key found: $TARGET_SSH_KEY"
    fi
    
    if [ ! -f "$ZDM_SSH_KEY" ]; then
        log_error "ZDM SSH key not found: $ZDM_SSH_KEY"
        errors=$((errors + 1))
    else
        log_success "ZDM SSH key found: $ZDM_SSH_KEY"
    fi
    
    # Check discovery scripts exist
    if [ ! -f "$SCRIPT_DIR/$SOURCE_SCRIPT" ]; then
        log_error "Source discovery script not found: $SCRIPT_DIR/$SOURCE_SCRIPT"
        errors=$((errors + 1))
    else
        log_success "Source discovery script found"
    fi
    
    if [ ! -f "$SCRIPT_DIR/$TARGET_SCRIPT" ]; then
        log_error "Target discovery script not found: $SCRIPT_DIR/$TARGET_SCRIPT"
        errors=$((errors + 1))
    else
        log_success "Target discovery script found"
    fi
    
    if [ ! -f "$SCRIPT_DIR/$ZDM_SCRIPT" ]; then
        log_error "ZDM discovery script not found: $SCRIPT_DIR/$ZDM_SCRIPT"
        errors=$((errors + 1))
    else
        log_success "ZDM discovery script found"
    fi
    
    TOTAL_ERRORS=$((TOTAL_ERRORS + errors))
    return $errors
}

test_ssh_connectivity() {
    local host=$1
    local user=$2
    local ssh_key=$3
    local label=$4
    
    log_info "Testing SSH to $label ($user@$host)..."
    
    if ssh $SSH_OPTS -i "$ssh_key" "$user@$host" "echo 'SSH connection successful'" 2>/dev/null; then
        log_success "SSH connectivity OK: $label"
        return 0
    else
        log_error "SSH connectivity FAILED: $label"
        return 1
    fi
}

test_all_connectivity() {
    print_section "Testing SSH Connectivity"
    
    local source_ok=false
    local target_ok=false
    local zdm_ok=false
    
    test_ssh_connectivity "$SOURCE_HOST" "$SOURCE_USER" "$SOURCE_SSH_KEY" "Source DB" && source_ok=true
    test_ssh_connectivity "$TARGET_HOST" "$TARGET_USER" "$TARGET_SSH_KEY" "Target ODA@Azure" && target_ok=true
    test_ssh_connectivity "$ZDM_HOST" "$ZDM_USER" "$ZDM_SSH_KEY" "ZDM Server" && zdm_ok=true
    
    echo ""
    echo "Connectivity Summary:"
    echo "  Source Database:      $([ "$source_ok" = true ] && echo -e "${GREEN}OK${NC}" || echo -e "${RED}FAILED${NC}")"
    echo "  Target ODA@Azure:     $([ "$target_ok" = true ] && echo -e "${GREEN}OK${NC}" || echo -e "${RED}FAILED${NC}")"
    echo "  ZDM Server:           $([ "$zdm_ok" = true ] && echo -e "${GREEN}OK${NC}" || echo -e "${RED}FAILED${NC}")"
    
    # Return success if at least one connection works (for resilience)
    [ "$source_ok" = true ] || [ "$target_ok" = true ] || [ "$zdm_ok" = true ]
}

run_remote_discovery() {
    local host=$1
    local user=$2
    local ssh_key=$3
    local script=$4
    local label=$5
    local output_subdir=$6
    
    print_section "Running Discovery on $label"
    
    log_info "Host: $host"
    log_info "User: $user"
    log_info "Script: $script"
    
    # Create remote working directory
    log_info "Creating remote working directory..."
    if ! ssh $SSH_OPTS -i "$ssh_key" "$user@$host" "mkdir -p $REMOTE_WORK_DIR" 2>/dev/null; then
        log_error "Failed to create remote directory on $label"
        return 1
    fi
    
    # Copy script to remote server
    log_info "Copying discovery script to remote server..."
    if ! scp $SSH_OPTS -i "$ssh_key" "$SCRIPT_DIR/$script" "$user@$host:$REMOTE_WORK_DIR/" 2>/dev/null; then
        log_error "Failed to copy script to $label"
        return 1
    fi
    
    # Execute discovery script on remote server
    # Source environment files before running to ensure ZDM_HOME, ORACLE_HOME, etc. are available
    log_info "Executing discovery script..."
    if ! ssh $SSH_OPTS -i "$ssh_key" "$user@$host" "
        # Source common profile files for environment variables
        for profile in ~/.bash_profile ~/.bashrc /etc/profile ~/.profile; do
            [ -f \"\$profile\" ] && source \"\$profile\" 2>/dev/null || true
        done
        
        # Change to work directory and run script
        cd $REMOTE_WORK_DIR && chmod +x $script && ./$script
    " 2>&1; then
        log_warning "Discovery script completed with warnings on $label"
        # Continue anyway - script is designed to be resilient
    fi
    
    log_success "Discovery completed on $label"
    
    # Create local output directory
    local local_output="$OUTPUT_DIR/$output_subdir"
    mkdir -p "$local_output"
    
    # Collect results
    log_info "Collecting discovery results..."
    
    # Get list of output files
    local output_files=$(ssh $SSH_OPTS -i "$ssh_key" "$user@$host" "ls $REMOTE_WORK_DIR/zdm_*_discovery_*.txt $REMOTE_WORK_DIR/zdm_*_discovery_*.json 2>/dev/null" 2>/dev/null)
    
    if [ -n "$output_files" ]; then
        for remote_file in $output_files; do
            local filename=$(basename "$remote_file")
            log_info "  Collecting: $filename"
            if scp $SSH_OPTS -i "$ssh_key" "$user@$host:$remote_file" "$local_output/" 2>/dev/null; then
                log_success "  Saved to: $local_output/$filename"
            else
                log_warning "  Failed to collect: $filename"
            fi
        done
    else
        log_warning "No discovery output files found on $label"
    fi
    
    # Cleanup remote files (optional - comment out to keep on remote)
    log_info "Cleaning up remote files..."
    ssh $SSH_OPTS -i "$ssh_key" "$user@$host" "rm -rf $REMOTE_WORK_DIR" 2>/dev/null || true
    
    return 0
}

################################################################################
# Main Execution
################################################################################

main() {
    local test_only=false
    local show_config_only=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -c|--config)
                show_config_only=true
                shift
                ;;
            -t|--test)
                test_only=true
                shift
                ;;
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Show header
    print_header "ZDM Discovery Orchestration"
    echo ""
    echo "Project:  PRODDB Migration to Oracle Database@Azure"
    echo "Version:  $SCRIPT_VERSION"
    echo "Date:     $(date)"
    
    # Show config only if requested
    if [ "$show_config_only" = true ]; then
        show_config
        exit 0
    fi
    
    show_config
    
    # Validate configuration
    if ! validate_config; then
        log_error "Configuration validation failed. Please fix the errors above."
        log_info "Continuing with available resources (resilient mode)..."
    fi
    
    # Test connectivity
    if ! test_all_connectivity; then
        log_error "No servers are reachable. Please check network connectivity and SSH keys."
        exit 1
    fi
    
    # Exit if test only
    if [ "$test_only" = true ]; then
        log_info "Test mode complete. Exiting without running discovery."
        exit 0
    fi
    
    # Create output directory structure
    print_section "Preparing Output Directory"
    mkdir -p "$OUTPUT_DIR/source" "$OUTPUT_DIR/target" "$OUTPUT_DIR/server"
    log_success "Created output directory: $OUTPUT_DIR"
    
    # Run discovery on each server (continue even if some fail)
    print_header "Running Discovery on All Servers"
    
    # Source Database Discovery
    if run_remote_discovery "$SOURCE_HOST" "$SOURCE_USER" "$SOURCE_SSH_KEY" \
                           "$SOURCE_SCRIPT" "Source Database" "source"; then
        SOURCE_SUCCESS=true
    else
        log_warning "Source database discovery failed - continuing with other servers"
    fi
    
    # Target Database Discovery
    if run_remote_discovery "$TARGET_HOST" "$TARGET_USER" "$TARGET_SSH_KEY" \
                           "$TARGET_SCRIPT" "Target Oracle Database@Azure" "target"; then
        TARGET_SUCCESS=true
    else
        log_warning "Target database discovery failed - continuing with other servers"
    fi
    
    # ZDM Server Discovery
    if run_remote_discovery "$ZDM_HOST" "$ZDM_USER" "$ZDM_SSH_KEY" \
                           "$ZDM_SCRIPT" "ZDM Server" "server"; then
        ZDM_SUCCESS=true
    else
        log_warning "ZDM server discovery failed"
    fi
    
    # Summary
    print_header "Discovery Summary"
    echo ""
    echo "Results:"
    echo "  Source Database:      $([ "$SOURCE_SUCCESS" = true ] && echo -e "${GREEN}SUCCESS${NC}" || echo -e "${RED}FAILED${NC}")"
    echo "  Target ODA@Azure:     $([ "$TARGET_SUCCESS" = true ] && echo -e "${GREEN}SUCCESS${NC}" || echo -e "${RED}FAILED${NC}")"
    echo "  ZDM Server:           $([ "$ZDM_SUCCESS" = true ] && echo -e "${GREEN}SUCCESS${NC}" || echo -e "${RED}FAILED${NC}")"
    echo ""
    echo "Output Directory: $OUTPUT_DIR"
    echo ""
    
    # List collected files
    echo "Collected Files:"
    if [ -d "$OUTPUT_DIR" ]; then
        find "$OUTPUT_DIR" -name "zdm_*.txt" -o -name "zdm_*.json" | while read file; do
            echo "  $file"
        done
    fi
    
    echo ""
    
    # Determine exit status
    local success_count=0
    [ "$SOURCE_SUCCESS" = true ] && success_count=$((success_count + 1))
    [ "$TARGET_SUCCESS" = true ] && success_count=$((success_count + 1))
    [ "$ZDM_SUCCESS" = true ] && success_count=$((success_count + 1))
    
    if [ $success_count -eq 3 ]; then
        log_success "All discoveries completed successfully!"
        echo ""
        echo "Next Steps:"
        echo "  1. Review discovery output files in $OUTPUT_DIR"
        echo "  2. Proceed to Step 1: Complete the Discovery Questionnaire"
        echo "     Use: Step1-Discovery-Questionnaire.prompt.md"
        exit 0
    elif [ $success_count -gt 0 ]; then
        log_warning "Partial success: $success_count of 3 discoveries completed"
        echo ""
        echo "Next Steps:"
        echo "  1. Review available discovery output in $OUTPUT_DIR"
        echo "  2. Troubleshoot failed discoveries and re-run if needed"
        echo "  3. Proceed to Step 1 with available data"
        exit 0
    else
        log_error "All discoveries failed!"
        exit 1
    fi
}

# Run main
main "$@"
