#!/bin/bash
# =============================================================================
# ZDM Discovery Orchestration Script
# =============================================================================
# Project: PRODDB Migration to Oracle Database@Azure
# Generated: 2026-01-29
# =============================================================================
# This script orchestrates the discovery process across all servers:
# - Source database server
# - Target Oracle Database@Azure server
# - ZDM jumpbox server
# =============================================================================

# =============================================================================
# Color Output
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# =============================================================================
# Configuration - Pre-configured for PRODDB Migration
# =============================================================================
# Server hostnames
SOURCE_HOST="${SOURCE_HOST:-proddb01.corp.example.com}"
TARGET_HOST="${TARGET_HOST:-proddb-oda.eastus.azure.example.com}"
ZDM_HOST="${ZDM_HOST:-zdm-jumpbox.corp.example.com}"

# User accounts for each server
SOURCE_USER="${SOURCE_USER:-oracle}"
TARGET_USER="${TARGET_USER:-opc}"
ZDM_USER="${ZDM_USER:-zdmuser}"

# SSH Keys - typically different for each server environment
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-~/.ssh/source_db_key}"
TARGET_SSH_KEY="${TARGET_SSH_KEY:-~/.ssh/oda_azure_key}"
ZDM_SSH_KEY="${ZDM_SSH_KEY:-~/.ssh/zdm_jumpbox_key}"

# Explicit environment variable overrides (optional - use when auto-detection fails)
# These are passed to remote scripts via environment
ZDM_REMOTE_ZDM_HOME="${ZDM_REMOTE_ZDM_HOME:-}"
ZDM_REMOTE_JAVA_HOME="${ZDM_REMOTE_JAVA_HOME:-}"
SOURCE_REMOTE_ORACLE_HOME="${SOURCE_REMOTE_ORACLE_HOME:-}"
SOURCE_REMOTE_ORACLE_SID="${SOURCE_REMOTE_ORACLE_SID:-}"
TARGET_REMOTE_ORACLE_HOME="${TARGET_REMOTE_ORACLE_HOME:-}"
TARGET_REMOTE_ORACLE_SID="${TARGET_REMOTE_ORACLE_SID:-}"

# Output directory - default to Artifacts directory (relative to script location)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-$SCRIPT_DIR/../Discovery}"

# SSH options
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=30 -o BatchMode=yes"

# Remote working directory
REMOTE_WORK_DIR="/tmp/zdm_discovery"

# =============================================================================
# Error Tracking
# =============================================================================
SOURCE_SUCCESS=false
TARGET_SUCCESS=false
ZDM_SUCCESS=false

# =============================================================================
# Helper Functions
# =============================================================================
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

log_header() {
    echo ""
    echo -e "${BOLD}${CYAN}================================================================================${NC}"
    echo -e "${BOLD}${CYAN} $1${NC}"
    echo -e "${BOLD}${CYAN}================================================================================${NC}"
    echo ""
}

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

ZDM Discovery Orchestration Script for PRODDB Migration

Options:
  -h, --help        Show this help message
  -c, --config      Display current configuration
  -t, --test        Test SSH connectivity only (no discovery)
  -s, --source-only Run discovery on source server only
  -T, --target-only Run discovery on target server only
  -z, --zdm-only    Run discovery on ZDM server only
  -o, --output DIR  Set output directory (default: $OUTPUT_DIR)

Environment Variables:
  SOURCE_HOST              Source database hostname (default: proddb01.corp.example.com)
  TARGET_HOST              Target database hostname (default: proddb-oda.eastus.azure.example.com)
  ZDM_HOST                 ZDM server hostname (default: zdm-jumpbox.corp.example.com)
  SOURCE_USER              Source server user (default: oracle)
  TARGET_USER              Target server user (default: opc)
  ZDM_USER                 ZDM server user (default: zdmuser)
  SOURCE_SSH_KEY           SSH key for source server (default: ~/.ssh/source_db_key)
  TARGET_SSH_KEY           SSH key for target server (default: ~/.ssh/oda_azure_key)
  ZDM_SSH_KEY              SSH key for ZDM server (default: ~/.ssh/zdm_jumpbox_key)
  
  # Optional overrides for remote environments (use if auto-detection fails):
  SOURCE_REMOTE_ORACLE_HOME   Oracle home on source server
  SOURCE_REMOTE_ORACLE_SID    Oracle SID on source server
  TARGET_REMOTE_ORACLE_HOME   Oracle home on target server
  TARGET_REMOTE_ORACLE_SID    Oracle SID on target server
  ZDM_REMOTE_ZDM_HOME         ZDM home on ZDM server
  ZDM_REMOTE_JAVA_HOME        Java home on ZDM server

Examples:
  # Run full discovery with default configuration
  ./$(basename "$0")
  
  # Test connectivity before running discovery
  ./$(basename "$0") --test
  
  # Run with custom SSH keys
  SOURCE_SSH_KEY=~/.ssh/id_rsa TARGET_SSH_KEY=~/.ssh/id_rsa ./$(basename "$0")
  
  # Run only source discovery with explicit Oracle home
  SOURCE_REMOTE_ORACLE_HOME=/u01/app/oracle/product/19c/dbhome_1 ./$(basename "$0") --source-only

EOF
}

show_config() {
    log_header "Current Configuration"
    
    echo "Server Configuration:"
    echo "  Source Host:        $SOURCE_HOST"
    echo "  Source User:        $SOURCE_USER"
    echo "  Source SSH Key:     $SOURCE_SSH_KEY"
    echo ""
    echo "  Target Host:        $TARGET_HOST"
    echo "  Target User:        $TARGET_USER"
    echo "  Target SSH Key:     $TARGET_SSH_KEY"
    echo ""
    echo "  ZDM Host:           $ZDM_HOST"
    echo "  ZDM User:           $ZDM_USER"
    echo "  ZDM SSH Key:        $ZDM_SSH_KEY"
    echo ""
    echo "Output Directory:     $OUTPUT_DIR"
    echo ""
    echo "Environment Overrides (if set):"
    echo "  SOURCE_REMOTE_ORACLE_HOME: ${SOURCE_REMOTE_ORACLE_HOME:-<not set>}"
    echo "  SOURCE_REMOTE_ORACLE_SID:  ${SOURCE_REMOTE_ORACLE_SID:-<not set>}"
    echo "  TARGET_REMOTE_ORACLE_HOME: ${TARGET_REMOTE_ORACLE_HOME:-<not set>}"
    echo "  TARGET_REMOTE_ORACLE_SID:  ${TARGET_REMOTE_ORACLE_SID:-<not set>}"
    echo "  ZDM_REMOTE_ZDM_HOME:       ${ZDM_REMOTE_ZDM_HOME:-<not set>}"
    echo "  ZDM_REMOTE_JAVA_HOME:      ${ZDM_REMOTE_JAVA_HOME:-<not set>}"
}

# =============================================================================
# SSH Connectivity Test
# =============================================================================
test_ssh_connectivity() {
    local host=$1
    local user=$2
    local ssh_key=$3
    local name=$4
    
    echo -n "  Testing $name ($user@$host)... "
    
    # Expand tilde in ssh_key path
    ssh_key="${ssh_key/#\~/$HOME}"
    
    if [ ! -f "$ssh_key" ]; then
        echo -e "${RED}FAILED${NC} (SSH key not found: $ssh_key)"
        return 1
    fi
    
    if ssh $SSH_OPTS -i "$ssh_key" "$user@$host" "echo 'OK'" 2>/dev/null; then
        echo -e "${GREEN}OK${NC}"
        return 0
    else
        echo -e "${RED}FAILED${NC}"
        return 1
    fi
}

test_all_connectivity() {
    log_header "Testing SSH Connectivity"
    
    local all_ok=true
    
    test_ssh_connectivity "$SOURCE_HOST" "$SOURCE_USER" "$SOURCE_SSH_KEY" "Source" || all_ok=false
    test_ssh_connectivity "$TARGET_HOST" "$TARGET_USER" "$TARGET_SSH_KEY" "Target" || all_ok=false
    test_ssh_connectivity "$ZDM_HOST" "$ZDM_USER" "$ZDM_SSH_KEY" "ZDM" || all_ok=false
    
    echo ""
    if $all_ok; then
        log_success "All connectivity tests passed"
        return 0
    else
        log_warning "Some connectivity tests failed"
        return 1
    fi
}

# =============================================================================
# Discovery Execution
# =============================================================================
run_discovery() {
    local host=$1
    local user=$2
    local ssh_key=$3
    local script=$4
    local target_type=$5
    local env_overrides=$6
    local output_subdir=$7
    
    log_info "Running discovery on $target_type ($host)..."
    
    # Expand tilde in ssh_key path
    ssh_key="${ssh_key/#\~/$HOME}"
    
    # Verify SSH key exists
    if [ ! -f "$ssh_key" ]; then
        log_error "SSH key not found: $ssh_key"
        return 1
    fi
    
    # Create remote working directory
    log_info "Creating remote working directory..."
    if ! ssh $SSH_OPTS -i "$ssh_key" "$user@$host" "mkdir -p $REMOTE_WORK_DIR" 2>/dev/null; then
        log_error "Failed to create remote directory on $host"
        return 1
    fi
    
    # Copy discovery script to remote server
    log_info "Copying discovery script to $host..."
    if ! scp $SSH_OPTS -i "$ssh_key" "$SCRIPT_DIR/$script" "$user@$host:$REMOTE_WORK_DIR/" 2>/dev/null; then
        log_error "Failed to copy script to $host"
        return 1
    fi
    
    # Execute discovery script using login shell
    # This ensures .bash_profile and .bashrc are sourced properly
    log_info "Executing discovery script..."
    ssh $SSH_OPTS -i "$ssh_key" "$user@$host" "bash -l -c '
        # Apply explicit environment overrides if provided
        $env_overrides
        
        # Change to working directory and run script
        cd $REMOTE_WORK_DIR
        chmod +x $script
        ./$script
    '" 2>&1
    
    local exit_code=$?
    
    # Collect results
    log_info "Collecting discovery results..."
    mkdir -p "$OUTPUT_DIR/$output_subdir"
    
    # Copy output files
    scp $SSH_OPTS -i "$ssh_key" "$user@$host:$REMOTE_WORK_DIR/zdm_*_discovery_*.txt" "$OUTPUT_DIR/$output_subdir/" 2>/dev/null
    scp $SSH_OPTS -i "$ssh_key" "$user@$host:$REMOTE_WORK_DIR/zdm_*_discovery_*.json" "$OUTPUT_DIR/$output_subdir/" 2>/dev/null
    
    # Clean up remote working directory
    log_info "Cleaning up remote directory..."
    ssh $SSH_OPTS -i "$ssh_key" "$user@$host" "rm -rf $REMOTE_WORK_DIR" 2>/dev/null
    
    if [ $exit_code -eq 0 ]; then
        log_success "Discovery completed for $target_type"
        return 0
    else
        log_warning "Discovery completed with warnings for $target_type (exit code: $exit_code)"
        return 0  # Still return 0 since script completed
    fi
}

# =============================================================================
# Main Execution
# =============================================================================
main() {
    local run_source=true
    local run_target=true
    local run_zdm=true
    local test_only=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -c|--config)
                show_config
                exit 0
                ;;
            -t|--test)
                test_only=true
                shift
                ;;
            -s|--source-only)
                run_target=false
                run_zdm=false
                shift
                ;;
            -T|--target-only)
                run_source=false
                run_zdm=false
                shift
                ;;
            -z|--zdm-only)
                run_source=false
                run_target=false
                shift
                ;;
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    log_header "ZDM Discovery Orchestration"
    echo "Project: PRODDB Migration to Oracle Database@Azure"
    echo "Timestamp: $(date)"
    echo ""
    
    # Show configuration
    show_config
    
    # Test connectivity
    if ! test_all_connectivity; then
        if $test_only; then
            exit 1
        fi
        log_warning "Proceeding despite connectivity failures (will skip failed servers)"
    fi
    
    if $test_only; then
        log_info "Test mode - exiting without running discovery"
        exit 0
    fi
    
    # Create output directory structure
    log_info "Creating output directory structure..."
    mkdir -p "$OUTPUT_DIR/source"
    mkdir -p "$OUTPUT_DIR/target"
    mkdir -p "$OUTPUT_DIR/server"
    
    # Run discoveries
    if $run_source; then
        log_header "Source Database Discovery"
        local source_env=""
        [ -n "$SOURCE_REMOTE_ORACLE_HOME" ] && source_env="export ORACLE_HOME_OVERRIDE='$SOURCE_REMOTE_ORACLE_HOME'; "
        [ -n "$SOURCE_REMOTE_ORACLE_SID" ] && source_env="${source_env}export ORACLE_SID_OVERRIDE='$SOURCE_REMOTE_ORACLE_SID'; "
        
        if run_discovery "$SOURCE_HOST" "$SOURCE_USER" "$SOURCE_SSH_KEY" "zdm_source_discovery.sh" "Source" "$source_env" "source"; then
            SOURCE_SUCCESS=true
        fi
    fi
    
    if $run_target; then
        log_header "Target Database Discovery"
        local target_env=""
        [ -n "$TARGET_REMOTE_ORACLE_HOME" ] && target_env="export ORACLE_HOME_OVERRIDE='$TARGET_REMOTE_ORACLE_HOME'; "
        [ -n "$TARGET_REMOTE_ORACLE_SID" ] && target_env="${target_env}export ORACLE_SID_OVERRIDE='$TARGET_REMOTE_ORACLE_SID'; "
        
        if run_discovery "$TARGET_HOST" "$TARGET_USER" "$TARGET_SSH_KEY" "zdm_target_discovery.sh" "Target" "$target_env" "target"; then
            TARGET_SUCCESS=true
        fi
    fi
    
    if $run_zdm; then
        log_header "ZDM Server Discovery"
        local zdm_env=""
        [ -n "$ZDM_REMOTE_ZDM_HOME" ] && zdm_env="export ZDM_HOME_OVERRIDE='$ZDM_REMOTE_ZDM_HOME'; "
        [ -n "$ZDM_REMOTE_JAVA_HOME" ] && zdm_env="${zdm_env}export JAVA_HOME_OVERRIDE='$ZDM_REMOTE_JAVA_HOME'; "
        
        if run_discovery "$ZDM_HOST" "$ZDM_USER" "$ZDM_SSH_KEY" "zdm_server_discovery.sh" "ZDM" "$zdm_env" "server"; then
            ZDM_SUCCESS=true
        fi
    fi
    
    # Summary
    log_header "Discovery Summary"
    
    echo "Results:"
    if $run_source; then
        if $SOURCE_SUCCESS; then
            echo -e "  Source:  ${GREEN}SUCCESS${NC}"
        else
            echo -e "  Source:  ${RED}FAILED${NC}"
        fi
    else
        echo -e "  Source:  ${YELLOW}SKIPPED${NC}"
    fi
    
    if $run_target; then
        if $TARGET_SUCCESS; then
            echo -e "  Target:  ${GREEN}SUCCESS${NC}"
        else
            echo -e "  Target:  ${RED}FAILED${NC}"
        fi
    else
        echo -e "  Target:  ${YELLOW}SKIPPED${NC}"
    fi
    
    if $run_zdm; then
        if $ZDM_SUCCESS; then
            echo -e "  ZDM:     ${GREEN}SUCCESS${NC}"
        else
            echo -e "  ZDM:     ${RED}FAILED${NC}"
        fi
    else
        echo -e "  ZDM:     ${YELLOW}SKIPPED${NC}"
    fi
    
    echo ""
    echo "Output Directory: $OUTPUT_DIR"
    echo ""
    echo "Discovery files:"
    ls -la "$OUTPUT_DIR"/source/*.txt "$OUTPUT_DIR"/target/*.txt "$OUTPUT_DIR"/server/*.txt 2>/dev/null || echo "  (No output files found)"
    
    log_header "Next Steps"
    echo "1. Review discovery output files in $OUTPUT_DIR"
    echo "2. Proceed to Step 1: Discovery Questionnaire"
    echo "   - Use prompts/Phase10-Migration/ZDM/Step1-Discovery-Questionnaire.prompt.md"
    echo "   - Attach discovery output files"
    echo "3. Complete all questionnaire sections including business decisions"
    echo "4. Save to Artifacts/Phase10-Migration/ZDM/PRODDB/Step1/"
}

# Run main
main "$@"
