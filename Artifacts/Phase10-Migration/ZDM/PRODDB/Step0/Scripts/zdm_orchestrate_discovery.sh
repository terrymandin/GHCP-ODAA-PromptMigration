#!/bin/bash
# =============================================================================
# ZDM Discovery Orchestration Script
# =============================================================================
# Project: PRODDB Migration to Oracle Database@Azure
# Generated: 2026-01-30
#
# Purpose:
#   Orchestrate discovery across source, target, and ZDM servers.
#   Copy scripts, execute remotely, and collect results.
#
# Usage:
#   ./zdm_orchestrate_discovery.sh [options]
#
# Options:
#   -h, --help      Show help message
#   -c, --config    Show current configuration
#   -t, --test      Test connectivity only (don't run discovery)
#   -o, --output    Specify output directory (default: ../Discovery/)
#
# =============================================================================

# NO set -e - We want to continue even if some servers fail
set +e

# =============================================================================
# COLOR CONFIGURATION
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# =============================================================================
# SERVER CONFIGURATION
# Pre-configured for PRODDB Migration
# =============================================================================

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

# =============================================================================
# APPLICATION USER CONFIGURATION
# =============================================================================

# Oracle database software owner (for running SQL commands on source/target)
ORACLE_USER="${ORACLE_USER:-oracle}"

# ZDM software owner (for running ZDM CLI commands)
ZDM_USER="${ZDM_USER:-zdmuser}"

# =============================================================================
# ENVIRONMENT VARIABLE OVERRIDES (Optional)
# Set these if auto-detection fails on remote servers
# =============================================================================

# Source server overrides
SOURCE_REMOTE_ORACLE_HOME="${SOURCE_REMOTE_ORACLE_HOME:-}"
SOURCE_REMOTE_ORACLE_SID="${SOURCE_REMOTE_ORACLE_SID:-}"

# Target server overrides
TARGET_REMOTE_ORACLE_HOME="${TARGET_REMOTE_ORACLE_HOME:-}"
TARGET_REMOTE_ORACLE_SID="${TARGET_REMOTE_ORACLE_SID:-}"

# ZDM server overrides
ZDM_REMOTE_ZDM_HOME="${ZDM_REMOTE_ZDM_HOME:-}"
ZDM_REMOTE_JAVA_HOME="${ZDM_REMOTE_JAVA_HOME:-}"

# =============================================================================
# OUTPUT CONFIGURATION
# =============================================================================

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Output directory - relative to script location by default
OUTPUT_DIR="${OUTPUT_DIR:-$SCRIPT_DIR/../Discovery}"

# Remote working directory
REMOTE_WORK_DIR="/tmp/zdm_discovery_$$"

# SSH options
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=30 -o BatchMode=yes"

# =============================================================================
# ERROR TRACKING
# =============================================================================
SOURCE_SUCCESS=false
TARGET_SUCCESS=false
ZDM_SUCCESS=false

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

print_banner() {
    echo ""
    echo -e "${BOLD}${BLUE}=============================================================================${NC}"
    echo -e "${BOLD}${BLUE} ZDM Discovery Orchestration${NC}"
    echo -e "${BOLD}${BLUE} Project: PRODDB Migration to Oracle Database@Azure${NC}"
    echo -e "${BOLD}${BLUE}=============================================================================${NC}"
    echo ""
}

log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
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

log_section() {
    echo ""
    echo -e "${BOLD}${CYAN}>>> $1${NC}"
    echo ""
}

show_help() {
    cat << EOF
ZDM Discovery Orchestration Script
Project: PRODDB Migration to Oracle Database@Azure

Usage: $0 [options]

Options:
  -h, --help      Show this help message
  -c, --config    Show current configuration
  -t, --test      Test connectivity only (don't run discovery)
  -o, --output    Specify output directory

Environment Variables:
  Server Configuration (pre-configured for this migration):
    SOURCE_HOST           Source database server (default: proddb01.corp.example.com)
    SOURCE_ADMIN_USER     SSH user for source (default: oracle)
    SOURCE_SSH_KEY        SSH key for source (default: ~/.ssh/onprem_oracle_key)
    
    TARGET_HOST           Target ODA@Azure server (default: proddb-oda.eastus.azure.example.com)
    TARGET_ADMIN_USER     SSH user for target (default: opc)
    TARGET_SSH_KEY        SSH key for target (default: ~/.ssh/oci_opc_key)
    
    ZDM_HOST              ZDM jumpbox server (default: zdm-jumpbox.corp.example.com)
    ZDM_ADMIN_USER        SSH user for ZDM (default: azureuser)
    ZDM_SSH_KEY           SSH key for ZDM (default: ~/.ssh/azure_key)

  Application Users:
    ORACLE_USER           Oracle software owner (default: oracle)
    ZDM_USER              ZDM software owner (default: zdmuser)

  Optional Overrides (when auto-detection fails):
    SOURCE_REMOTE_ORACLE_HOME    Override ORACLE_HOME on source
    SOURCE_REMOTE_ORACLE_SID     Override ORACLE_SID on source
    TARGET_REMOTE_ORACLE_HOME    Override ORACLE_HOME on target
    TARGET_REMOTE_ORACLE_SID     Override ORACLE_SID on target
    ZDM_REMOTE_ZDM_HOME          Override ZDM_HOME on ZDM server
    ZDM_REMOTE_JAVA_HOME         Override JAVA_HOME on ZDM server

Examples:
  # Run with default configuration
  $0

  # Test connectivity only
  $0 --test

  # Show current configuration
  $0 --config

  # Specify custom output directory
  $0 --output /path/to/output

  # With environment overrides
  SOURCE_REMOTE_ORACLE_SID=PRODDB $0

EOF
}

show_config() {
    print_banner
    echo -e "${BOLD}Current Configuration:${NC}"
    echo ""
    echo "Source Database Server:"
    echo "  HOST:       $SOURCE_HOST"
    echo "  ADMIN_USER: $SOURCE_ADMIN_USER"
    echo "  SSH_KEY:    $SOURCE_SSH_KEY"
    echo "  ORACLE_HOME Override: ${SOURCE_REMOTE_ORACLE_HOME:-<auto-detect>}"
    echo "  ORACLE_SID Override:  ${SOURCE_REMOTE_ORACLE_SID:-<auto-detect>}"
    echo ""
    echo "Target Database Server (Oracle Database@Azure):"
    echo "  HOST:       $TARGET_HOST"
    echo "  ADMIN_USER: $TARGET_ADMIN_USER"
    echo "  SSH_KEY:    $TARGET_SSH_KEY"
    echo "  ORACLE_HOME Override: ${TARGET_REMOTE_ORACLE_HOME:-<auto-detect>}"
    echo "  ORACLE_SID Override:  ${TARGET_REMOTE_ORACLE_SID:-<auto-detect>}"
    echo ""
    echo "ZDM Jumpbox Server:"
    echo "  HOST:       $ZDM_HOST"
    echo "  ADMIN_USER: $ZDM_ADMIN_USER"
    echo "  SSH_KEY:    $ZDM_SSH_KEY"
    echo "  ZDM_HOME Override:  ${ZDM_REMOTE_ZDM_HOME:-<auto-detect>}"
    echo "  JAVA_HOME Override: ${ZDM_REMOTE_JAVA_HOME:-<auto-detect>}"
    echo ""
    echo "Application Users:"
    echo "  ORACLE_USER: $ORACLE_USER"
    echo "  ZDM_USER:    $ZDM_USER"
    echo ""
    echo "Output:"
    echo "  OUTPUT_DIR: $OUTPUT_DIR"
    echo ""
}

# Expand tilde in path
expand_path() {
    local path="$1"
    eval echo "$path"
}

test_connectivity() {
    local host="$1"
    local user="$2"
    local key="$3"
    local name="$4"
    
    key=$(expand_path "$key")
    
    log_info "Testing connectivity to $name ($host)..."
    
    # Check if SSH key exists
    if [ ! -f "$key" ]; then
        log_error "SSH key not found: $key"
        return 1
    fi
    
    # Test SSH connection
    if ssh $SSH_OPTS -i "$key" "$user@$host" "echo 'Connection successful'" 2>/dev/null; then
        log_success "$name: SSH connection OK"
        return 0
    else
        log_error "$name: SSH connection FAILED"
        return 1
    fi
}

run_discovery() {
    local host="$1"
    local user="$2"
    local key="$3"
    local script="$4"
    local target_type="$5"
    local env_overrides="$6"
    
    key=$(expand_path "$key")
    
    log_section "Running Discovery on $target_type ($host)"
    
    # Create remote working directory
    log_info "Creating remote working directory..."
    ssh $SSH_OPTS -i "$key" "$user@$host" "mkdir -p $REMOTE_WORK_DIR" 2>/dev/null
    if [ $? -ne 0 ]; then
        log_error "Failed to create remote directory on $host"
        return 1
    fi
    
    # Copy discovery script to remote server
    log_info "Copying discovery script to $host..."
    scp $SSH_OPTS -i "$key" "$SCRIPT_DIR/$script" "$user@$host:$REMOTE_WORK_DIR/" 2>/dev/null
    if [ $? -ne 0 ]; then
        log_error "Failed to copy script to $host"
        return 1
    fi
    
    # Execute discovery script remotely
    # Use bash -l -c to ensure login shell and environment variables
    log_info "Executing discovery script on $host..."
    ssh $SSH_OPTS -i "$key" "$user@$host" "bash -l -c '
        # Set environment variable overrides if provided
        $env_overrides
        
        # Set application users
        export ORACLE_USER=\"$ORACLE_USER\"
        export ZDM_USER=\"$ZDM_USER\"
        export SOURCE_HOST=\"$SOURCE_HOST\"
        export TARGET_HOST=\"$TARGET_HOST\"
        
        # Change to working directory and run script
        cd $REMOTE_WORK_DIR
        chmod +x $script
        ./$script
    '" 2>&1
    
    local exit_code=$?
    
    # Collect results even if script had some warnings
    log_info "Collecting results from $host..."
    
    # Create local output directory for this target type
    local local_output_dir="$OUTPUT_DIR/$target_type"
    mkdir -p "$local_output_dir"
    
    # Copy result files back
    scp $SSH_OPTS -i "$key" "$user@$host:$REMOTE_WORK_DIR/zdm_*_discovery_*.txt" "$local_output_dir/" 2>/dev/null
    scp $SSH_OPTS -i "$key" "$user@$host:$REMOTE_WORK_DIR/zdm_*_discovery_*.json" "$local_output_dir/" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        log_success "Results collected to $local_output_dir/"
    else
        log_warning "Some result files may not have been collected"
    fi
    
    # Cleanup remote working directory
    log_info "Cleaning up remote working directory..."
    ssh $SSH_OPTS -i "$key" "$user@$host" "rm -rf $REMOTE_WORK_DIR" 2>/dev/null
    
    return 0
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

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
    
    # Show configuration and exit if requested
    if [ "$show_config_only" = true ]; then
        show_config
        exit 0
    fi
    
    print_banner
    
    # Show current configuration summary
    echo -e "${BOLD}Configuration Summary:${NC}"
    echo "  Source:  $SOURCE_ADMIN_USER@$SOURCE_HOST"
    echo "  Target:  $TARGET_ADMIN_USER@$TARGET_HOST"
    echo "  ZDM:     $ZDM_ADMIN_USER@$ZDM_HOST"
    echo "  Output:  $OUTPUT_DIR"
    echo ""
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR/source"
    mkdir -p "$OUTPUT_DIR/target"
    mkdir -p "$OUTPUT_DIR/server"
    
    # Test connectivity to all servers
    log_section "Testing Connectivity"
    
    local source_conn=false
    local target_conn=false
    local zdm_conn=false
    
    test_connectivity "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$SOURCE_SSH_KEY" "Source" && source_conn=true
    test_connectivity "$TARGET_HOST" "$TARGET_ADMIN_USER" "$TARGET_SSH_KEY" "Target" && target_conn=true
    test_connectivity "$ZDM_HOST" "$ZDM_ADMIN_USER" "$ZDM_SSH_KEY" "ZDM" && zdm_conn=true
    
    echo ""
    echo -e "${BOLD}Connectivity Summary:${NC}"
    [ "$source_conn" = true ] && echo -e "  Source: ${GREEN}OK${NC}" || echo -e "  Source: ${RED}FAILED${NC}"
    [ "$target_conn" = true ] && echo -e "  Target: ${GREEN}OK${NC}" || echo -e "  Target: ${RED}FAILED${NC}"
    [ "$zdm_conn" = true ] && echo -e "  ZDM:    ${GREEN}OK${NC}" || echo -e "  ZDM:    ${RED}FAILED${NC}"
    echo ""
    
    if [ "$test_only" = true ]; then
        log_info "Test mode - skipping discovery execution"
        exit 0
    fi
    
    # Check if any server is reachable
    if [ "$source_conn" = false ] && [ "$target_conn" = false ] && [ "$zdm_conn" = false ]; then
        log_error "No servers are reachable. Please check your configuration and SSH keys."
        exit 1
    fi
    
    # Run discovery on each reachable server
    # Build environment override strings for each server type
    
    local source_env_overrides=""
    [ -n "$SOURCE_REMOTE_ORACLE_HOME" ] && source_env_overrides="export ORACLE_HOME_OVERRIDE='$SOURCE_REMOTE_ORACLE_HOME'; "
    [ -n "$SOURCE_REMOTE_ORACLE_SID" ] && source_env_overrides="${source_env_overrides}export ORACLE_SID_OVERRIDE='$SOURCE_REMOTE_ORACLE_SID'; "
    
    local target_env_overrides=""
    [ -n "$TARGET_REMOTE_ORACLE_HOME" ] && target_env_overrides="export ORACLE_HOME_OVERRIDE='$TARGET_REMOTE_ORACLE_HOME'; "
    [ -n "$TARGET_REMOTE_ORACLE_SID" ] && target_env_overrides="${target_env_overrides}export ORACLE_SID_OVERRIDE='$TARGET_REMOTE_ORACLE_SID'; "
    
    local zdm_env_overrides=""
    [ -n "$ZDM_REMOTE_ZDM_HOME" ] && zdm_env_overrides="export ZDM_HOME_OVERRIDE='$ZDM_REMOTE_ZDM_HOME'; "
    [ -n "$ZDM_REMOTE_JAVA_HOME" ] && zdm_env_overrides="${zdm_env_overrides}export JAVA_HOME_OVERRIDE='$ZDM_REMOTE_JAVA_HOME'; "
    
    # Run discoveries - continue even if some fail
    if [ "$source_conn" = true ]; then
        run_discovery "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$SOURCE_SSH_KEY" \
            "zdm_source_discovery.sh" "source" "$source_env_overrides" && SOURCE_SUCCESS=true
    else
        log_warning "Skipping source discovery - server not reachable"
    fi
    
    if [ "$target_conn" = true ]; then
        run_discovery "$TARGET_HOST" "$TARGET_ADMIN_USER" "$TARGET_SSH_KEY" \
            "zdm_target_discovery.sh" "target" "$target_env_overrides" && TARGET_SUCCESS=true
    else
        log_warning "Skipping target discovery - server not reachable"
    fi
    
    if [ "$zdm_conn" = true ]; then
        run_discovery "$ZDM_HOST" "$ZDM_ADMIN_USER" "$ZDM_SSH_KEY" \
            "zdm_server_discovery.sh" "server" "$zdm_env_overrides" && ZDM_SUCCESS=true
    else
        log_warning "Skipping ZDM discovery - server not reachable"
    fi
    
    # Print final summary
    echo ""
    echo -e "${BOLD}${BLUE}=============================================================================${NC}"
    echo -e "${BOLD}${BLUE} Discovery Summary${NC}"
    echo -e "${BOLD}${BLUE}=============================================================================${NC}"
    echo ""
    
    [ "$SOURCE_SUCCESS" = true ] && echo -e "  Source Discovery:  ${GREEN}COMPLETED${NC}" || echo -e "  Source Discovery:  ${RED}FAILED/SKIPPED${NC}"
    [ "$TARGET_SUCCESS" = true ] && echo -e "  Target Discovery:  ${GREEN}COMPLETED${NC}" || echo -e "  Target Discovery:  ${RED}FAILED/SKIPPED${NC}"
    [ "$ZDM_SUCCESS" = true ] && echo -e "  ZDM Discovery:     ${GREEN}COMPLETED${NC}" || echo -e "  ZDM Discovery:     ${RED}FAILED/SKIPPED${NC}"
    
    echo ""
    echo "Output Directory: $OUTPUT_DIR"
    echo ""
    
    if [ "$SOURCE_SUCCESS" = true ] || [ "$TARGET_SUCCESS" = true ] || [ "$ZDM_SUCCESS" = true ]; then
        echo "Collected Files:"
        ls -la "$OUTPUT_DIR"/source/*.txt 2>/dev/null | head -5
        ls -la "$OUTPUT_DIR"/target/*.txt 2>/dev/null | head -5
        ls -la "$OUTPUT_DIR"/server/*.txt 2>/dev/null | head -5
        echo ""
    fi
    
    # Count successes
    local success_count=0
    [ "$SOURCE_SUCCESS" = true ] && success_count=$((success_count + 1))
    [ "$TARGET_SUCCESS" = true ] && success_count=$((success_count + 1))
    [ "$ZDM_SUCCESS" = true ] && success_count=$((success_count + 1))
    
    if [ $success_count -eq 3 ]; then
        log_success "All discovery scripts completed successfully!"
        echo ""
        echo "Next Steps:"
        echo "  1. Review discovery output files in $OUTPUT_DIR/"
        echo "  2. Proceed to Step 1: Discovery Questionnaire"
        echo "     - Use Step1-Discovery-Questionnaire.prompt.md"
        echo "     - Attach discovery files from $OUTPUT_DIR/"
        echo ""
        exit 0
    elif [ $success_count -gt 0 ]; then
        log_warning "Discovery completed with partial success ($success_count/3 servers)"
        echo ""
        echo "Review the output and troubleshoot failed servers before proceeding."
        echo ""
        exit 0
    else
        log_error "All discovery scripts failed"
        exit 1
    fi
}

# Run main function with all arguments
main "$@"
