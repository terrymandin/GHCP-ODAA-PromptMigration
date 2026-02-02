#!/bin/bash
#===============================================================================
# ZDM Discovery Orchestration Script
# Project: PRODDB Migration to Oracle Database@Azure
#
# This script orchestrates the discovery process across all servers:
# - Source Database: proddb01.corp.example.com
# - Target Database: proddb-oda.eastus.azure.example.com
# - ZDM Server: zdm-jumpbox.corp.example.com
#
# Usage: ./zdm_orchestrate_discovery.sh [options]
# Options:
#   -h, --help     Show help message
#   -c, --config   Display current configuration
#   -t, --test     Test connectivity only (no discovery)
#
# Environment Variables:
#   See configuration section below for all supported variables
#===============================================================================

#-------------------------------------------------------------------------------
# Color Output Functions
#-------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "\n${CYAN}${BOLD}=== $1 ===${NC}"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAILED]${NC} $1"; }

#-------------------------------------------------------------------------------
# Script Location and Repository Root
#-------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Navigate up 6 levels: Scripts → Step0 → PRODDB → ZDM → Phase10-Migration → Artifacts → RepoRoot
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../../.." && pwd)"

#-------------------------------------------------------------------------------
# Configuration - Server Hostnames
#-------------------------------------------------------------------------------
SOURCE_HOST="${SOURCE_HOST:-proddb01.corp.example.com}"
TARGET_HOST="${TARGET_HOST:-proddb-oda.eastus.azure.example.com}"
ZDM_HOST="${ZDM_HOST:-zdm-jumpbox.corp.example.com}"

#-------------------------------------------------------------------------------
# Configuration - SSH/Admin Users (different for each environment)
#-------------------------------------------------------------------------------
# These are Linux admin users with sudo privileges for SSH connections
SOURCE_ADMIN_USER="${SOURCE_ADMIN_USER:-oracle}"
TARGET_ADMIN_USER="${TARGET_ADMIN_USER:-opc}"
ZDM_ADMIN_USER="${ZDM_ADMIN_USER:-azureuser}"

#-------------------------------------------------------------------------------
# Configuration - Application Users
#-------------------------------------------------------------------------------
# Oracle database software owner (for running SQL commands)
ORACLE_USER="${ORACLE_USER:-oracle}"

# ZDM software owner (for running ZDM CLI commands)
ZDM_USER="${ZDM_USER:-zdmuser}"

#-------------------------------------------------------------------------------
# Configuration - SSH Keys (separate keys for each security domain)
#-------------------------------------------------------------------------------
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-$HOME/.ssh/onprem_oracle_key}"
TARGET_SSH_KEY="${TARGET_SSH_KEY:-$HOME/.ssh/oci_opc_key}"
ZDM_SSH_KEY="${ZDM_SSH_KEY:-$HOME/.ssh/azure_key}"

#-------------------------------------------------------------------------------
# Configuration - Output Directory
#-------------------------------------------------------------------------------
DB_NAME="PRODDB"
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/Artifacts/Phase10-Migration/ZDM/${DB_NAME}/Step0/Discovery}"

#-------------------------------------------------------------------------------
# Configuration - Optional Oracle/ZDM Path Overrides
#-------------------------------------------------------------------------------
# Set these if auto-detection fails on remote servers
SOURCE_REMOTE_ORACLE_HOME="${SOURCE_REMOTE_ORACLE_HOME:-}"
SOURCE_REMOTE_ORACLE_SID="${SOURCE_REMOTE_ORACLE_SID:-}"
TARGET_REMOTE_ORACLE_HOME="${TARGET_REMOTE_ORACLE_HOME:-}"
TARGET_REMOTE_ORACLE_SID="${TARGET_REMOTE_ORACLE_SID:-}"
ZDM_REMOTE_ZDM_HOME="${ZDM_REMOTE_ZDM_HOME:-}"
ZDM_REMOTE_JAVA_HOME="${ZDM_REMOTE_JAVA_HOME:-}"

#-------------------------------------------------------------------------------
# SSH Options
#-------------------------------------------------------------------------------
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=30 -o BatchMode=yes"

#-------------------------------------------------------------------------------
# Tracking Variables
#-------------------------------------------------------------------------------
DISCOVERY_RESULTS=()
FAILED_SERVERS=()
SUCCESSFUL_SERVERS=()

#-------------------------------------------------------------------------------
# Usage/Help
#-------------------------------------------------------------------------------
show_help() {
    cat << EOF
ZDM Discovery Orchestration Script
Project: PRODDB Migration to Oracle Database@Azure

Usage: $(basename "$0") [options]

Options:
  -h, --help     Show this help message
  -c, --config   Display current configuration
  -t, --test     Test SSH connectivity only (no discovery)

Environment Variables:
  Server Hostnames:
    SOURCE_HOST          Source database server (default: proddb01.corp.example.com)
    TARGET_HOST          Target database server (default: proddb-oda.eastus.azure.example.com)
    ZDM_HOST             ZDM jumpbox server (default: zdm-jumpbox.corp.example.com)

  SSH/Admin Users:
    SOURCE_ADMIN_USER    Admin user for source SSH (default: oracle)
    TARGET_ADMIN_USER    Admin user for target SSH (default: opc)
    ZDM_ADMIN_USER       Admin user for ZDM SSH (default: azureuser)

  Application Users:
    ORACLE_USER          Oracle software owner (default: oracle)
    ZDM_USER             ZDM software owner (default: zdmuser)

  SSH Keys:
    SOURCE_SSH_KEY       SSH key for source (default: ~/.ssh/onprem_oracle_key)
    TARGET_SSH_KEY       SSH key for target (default: ~/.ssh/oci_opc_key)
    ZDM_SSH_KEY          SSH key for ZDM (default: ~/.ssh/azure_key)

  Output:
    OUTPUT_DIR           Discovery output directory

  Oracle/ZDM Path Overrides (if auto-detection fails):
    SOURCE_REMOTE_ORACLE_HOME    Oracle home on source
    SOURCE_REMOTE_ORACLE_SID     Oracle SID on source
    TARGET_REMOTE_ORACLE_HOME    Oracle home on target
    TARGET_REMOTE_ORACLE_SID     Oracle SID on target
    ZDM_REMOTE_ZDM_HOME          ZDM home on ZDM server
    ZDM_REMOTE_JAVA_HOME         Java home on ZDM server

Examples:
  # Run discovery with defaults
  ./$(basename "$0")

  # Test connectivity only
  ./$(basename "$0") --test

  # Override source host and user
  SOURCE_HOST=mydb.example.com SOURCE_ADMIN_USER=dbadmin ./$(basename "$0")

EOF
}

#-------------------------------------------------------------------------------
# Show Configuration
#-------------------------------------------------------------------------------
show_config() {
    log_section "Current Configuration"
    
    echo ""
    echo "Server Hostnames:"
    echo "  SOURCE_HOST:          $SOURCE_HOST"
    echo "  TARGET_HOST:          $TARGET_HOST"
    echo "  ZDM_HOST:             $ZDM_HOST"
    
    echo ""
    echo "SSH/Admin Users:"
    echo "  SOURCE_ADMIN_USER:    $SOURCE_ADMIN_USER"
    echo "  TARGET_ADMIN_USER:    $TARGET_ADMIN_USER"
    echo "  ZDM_ADMIN_USER:       $ZDM_ADMIN_USER"
    
    echo ""
    echo "Application Users:"
    echo "  ORACLE_USER:          $ORACLE_USER"
    echo "  ZDM_USER:             $ZDM_USER"
    
    echo ""
    echo "SSH Keys:"
    echo "  SOURCE_SSH_KEY:       $SOURCE_SSH_KEY"
    echo "  TARGET_SSH_KEY:       $TARGET_SSH_KEY"
    echo "  ZDM_SSH_KEY:          $ZDM_SSH_KEY"
    
    echo ""
    echo "Output Directory:"
    echo "  OUTPUT_DIR:           $OUTPUT_DIR"
    
    echo ""
    echo "Script Location:"
    echo "  SCRIPT_DIR:           $SCRIPT_DIR"
    echo "  REPO_ROOT:            $REPO_ROOT"
    
    if [ -n "$SOURCE_REMOTE_ORACLE_HOME" ] || [ -n "$TARGET_REMOTE_ORACLE_HOME" ] || [ -n "$ZDM_REMOTE_ZDM_HOME" ]; then
        echo ""
        echo "Path Overrides:"
        [ -n "$SOURCE_REMOTE_ORACLE_HOME" ] && echo "  SOURCE_REMOTE_ORACLE_HOME: $SOURCE_REMOTE_ORACLE_HOME"
        [ -n "$SOURCE_REMOTE_ORACLE_SID" ] && echo "  SOURCE_REMOTE_ORACLE_SID:  $SOURCE_REMOTE_ORACLE_SID"
        [ -n "$TARGET_REMOTE_ORACLE_HOME" ] && echo "  TARGET_REMOTE_ORACLE_HOME: $TARGET_REMOTE_ORACLE_HOME"
        [ -n "$TARGET_REMOTE_ORACLE_SID" ] && echo "  TARGET_REMOTE_ORACLE_SID:  $TARGET_REMOTE_ORACLE_SID"
        [ -n "$ZDM_REMOTE_ZDM_HOME" ] && echo "  ZDM_REMOTE_ZDM_HOME:       $ZDM_REMOTE_ZDM_HOME"
        [ -n "$ZDM_REMOTE_JAVA_HOME" ] && echo "  ZDM_REMOTE_JAVA_HOME:      $ZDM_REMOTE_JAVA_HOME"
    fi
}

#-------------------------------------------------------------------------------
# Validate Configuration
#-------------------------------------------------------------------------------
validate_config() {
    log_section "Validating Configuration"
    local errors=0
    
    # Check SSH keys exist
    for key_var in SOURCE_SSH_KEY TARGET_SSH_KEY ZDM_SSH_KEY; do
        local key_path="${!key_var}"
        if [ ! -f "$key_path" ]; then
            log_error "SSH key not found: $key_var=$key_path"
            ((errors++))
        else
            log_info "SSH key found: $key_var"
        fi
    done
    
    # Check hostnames are set
    for host_var in SOURCE_HOST TARGET_HOST ZDM_HOST; do
        local host="${!host_var}"
        if [ -z "$host" ]; then
            log_error "Hostname not set: $host_var"
            ((errors++))
        else
            log_info "Hostname configured: $host_var=$host"
        fi
    done
    
    if [ $errors -gt 0 ]; then
        log_error "Configuration validation failed with $errors errors"
        return 1
    fi
    
    log_success "Configuration validation passed"
    return 0
}

#-------------------------------------------------------------------------------
# Test SSH Connectivity
#-------------------------------------------------------------------------------
test_ssh_connectivity() {
    local server_type="$1"
    local host="$2"
    local user="$3"
    local key_path="$4"
    
    log_info "Testing SSH connectivity to $server_type: $user@$host"
    
    if ssh $SSH_OPTS -i "$key_path" "${user}@${host}" "echo 'SSH connection successful'" 2>/dev/null; then
        log_success "$server_type SSH connectivity: OK"
        return 0
    else
        log_fail "$server_type SSH connectivity: FAILED"
        return 1
    fi
}

test_all_connectivity() {
    log_section "Testing SSH Connectivity"
    local all_ok=0
    
    test_ssh_connectivity "Source" "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$SOURCE_SSH_KEY" || all_ok=1
    test_ssh_connectivity "Target" "$TARGET_HOST" "$TARGET_ADMIN_USER" "$TARGET_SSH_KEY" || all_ok=1
    test_ssh_connectivity "ZDM" "$ZDM_HOST" "$ZDM_ADMIN_USER" "$ZDM_SSH_KEY" || all_ok=1
    
    return $all_ok
}

#-------------------------------------------------------------------------------
# Create Output Directories
#-------------------------------------------------------------------------------
create_output_dirs() {
    log_section "Creating Output Directories"
    
    mkdir -p "$OUTPUT_DIR/source"
    mkdir -p "$OUTPUT_DIR/target"
    mkdir -p "$OUTPUT_DIR/server"
    
    log_info "Created output directories under: $OUTPUT_DIR"
}

#-------------------------------------------------------------------------------
# Run Remote Discovery
#-------------------------------------------------------------------------------
run_source_discovery() {
    log_section "Running Source Database Discovery"
    log_info "Host: $SOURCE_HOST"
    log_info "User: $SOURCE_ADMIN_USER"
    
    local script_path="$SCRIPT_DIR/zdm_source_discovery.sh"
    
    if [ ! -f "$script_path" ]; then
        log_error "Source discovery script not found: $script_path"
        FAILED_SERVERS+=("source")
        return 1
    fi
    
    # Build environment variable string for remote execution
    local env_vars="ORACLE_USER='$ORACLE_USER'"
    [ -n "$SOURCE_REMOTE_ORACLE_HOME" ] && env_vars="$env_vars ORACLE_HOME_OVERRIDE='$SOURCE_REMOTE_ORACLE_HOME'"
    [ -n "$SOURCE_REMOTE_ORACLE_SID" ] && env_vars="$env_vars ORACLE_SID_OVERRIDE='$SOURCE_REMOTE_ORACLE_SID'"
    
    log_info "Executing source discovery script..."
    
    # Execute script remotely using login shell to ensure environment is sourced
    if ssh $SSH_OPTS -i "$SOURCE_SSH_KEY" "${SOURCE_ADMIN_USER}@${SOURCE_HOST}" \
        "$env_vars bash -l -s" < "$script_path" > "$OUTPUT_DIR/source/discovery_output.log" 2>&1; then
        log_success "Source discovery script executed successfully"
    else
        log_warn "Source discovery script completed with warnings or errors (check log)"
    fi
    
    # Collect output files from remote server
    log_info "Collecting discovery output files..."
    
    # Find and copy the generated files
    local remote_files
    remote_files=$(ssh $SSH_OPTS -i "$SOURCE_SSH_KEY" "${SOURCE_ADMIN_USER}@${SOURCE_HOST}" \
        "ls -t ./zdm_source_discovery_*.txt ./zdm_source_discovery_*.json 2>/dev/null | head -2")
    
    if [ -n "$remote_files" ]; then
        for file in $remote_files; do
            scp $SSH_OPTS -i "$SOURCE_SSH_KEY" "${SOURCE_ADMIN_USER}@${SOURCE_HOST}:$file" "$OUTPUT_DIR/source/" 2>/dev/null
        done
        log_success "Source discovery files collected to: $OUTPUT_DIR/source/"
        SUCCESSFUL_SERVERS+=("source")
        return 0
    else
        log_warn "No discovery output files found on source server"
        FAILED_SERVERS+=("source")
        return 1
    fi
}

run_target_discovery() {
    log_section "Running Target Database Discovery"
    log_info "Host: $TARGET_HOST"
    log_info "User: $TARGET_ADMIN_USER"
    
    local script_path="$SCRIPT_DIR/zdm_target_discovery.sh"
    
    if [ ! -f "$script_path" ]; then
        log_error "Target discovery script not found: $script_path"
        FAILED_SERVERS+=("target")
        return 1
    fi
    
    # Build environment variable string for remote execution
    local env_vars="ORACLE_USER='$ORACLE_USER'"
    [ -n "$TARGET_REMOTE_ORACLE_HOME" ] && env_vars="$env_vars ORACLE_HOME_OVERRIDE='$TARGET_REMOTE_ORACLE_HOME'"
    [ -n "$TARGET_REMOTE_ORACLE_SID" ] && env_vars="$env_vars ORACLE_SID_OVERRIDE='$TARGET_REMOTE_ORACLE_SID'"
    
    log_info "Executing target discovery script..."
    
    # Execute script remotely using login shell
    if ssh $SSH_OPTS -i "$TARGET_SSH_KEY" "${TARGET_ADMIN_USER}@${TARGET_HOST}" \
        "$env_vars bash -l -s" < "$script_path" > "$OUTPUT_DIR/target/discovery_output.log" 2>&1; then
        log_success "Target discovery script executed successfully"
    else
        log_warn "Target discovery script completed with warnings or errors (check log)"
    fi
    
    # Collect output files from remote server
    log_info "Collecting discovery output files..."
    
    local remote_files
    remote_files=$(ssh $SSH_OPTS -i "$TARGET_SSH_KEY" "${TARGET_ADMIN_USER}@${TARGET_HOST}" \
        "ls -t ./zdm_target_discovery_*.txt ./zdm_target_discovery_*.json 2>/dev/null | head -2")
    
    if [ -n "$remote_files" ]; then
        for file in $remote_files; do
            scp $SSH_OPTS -i "$TARGET_SSH_KEY" "${TARGET_ADMIN_USER}@${TARGET_HOST}:$file" "$OUTPUT_DIR/target/" 2>/dev/null
        done
        log_success "Target discovery files collected to: $OUTPUT_DIR/target/"
        SUCCESSFUL_SERVERS+=("target")
        return 0
    else
        log_warn "No discovery output files found on target server"
        FAILED_SERVERS+=("target")
        return 1
    fi
}

run_server_discovery() {
    log_section "Running ZDM Server Discovery"
    log_info "Host: $ZDM_HOST"
    log_info "User: $ZDM_ADMIN_USER"
    
    local script_path="$SCRIPT_DIR/zdm_server_discovery.sh"
    
    if [ ! -f "$script_path" ]; then
        log_error "ZDM server discovery script not found: $script_path"
        FAILED_SERVERS+=("server")
        return 1
    fi
    
    # Build environment variable string for remote execution
    # IMPORTANT: Pass SOURCE_HOST and TARGET_HOST for connectivity testing
    local env_vars="ZDM_USER='$ZDM_USER' SOURCE_HOST='$SOURCE_HOST' TARGET_HOST='$TARGET_HOST'"
    [ -n "$ZDM_REMOTE_ZDM_HOME" ] && env_vars="$env_vars ZDM_HOME_OVERRIDE='$ZDM_REMOTE_ZDM_HOME'"
    [ -n "$ZDM_REMOTE_JAVA_HOME" ] && env_vars="$env_vars JAVA_HOME_OVERRIDE='$ZDM_REMOTE_JAVA_HOME'"
    
    log_info "Executing ZDM server discovery script..."
    
    # Execute script remotely using login shell
    if ssh $SSH_OPTS -i "$ZDM_SSH_KEY" "${ZDM_ADMIN_USER}@${ZDM_HOST}" \
        "$env_vars bash -l -s" < "$script_path" > "$OUTPUT_DIR/server/discovery_output.log" 2>&1; then
        log_success "ZDM server discovery script executed successfully"
    else
        log_warn "ZDM server discovery script completed with warnings or errors (check log)"
    fi
    
    # Collect output files from remote server
    log_info "Collecting discovery output files..."
    
    local remote_files
    remote_files=$(ssh $SSH_OPTS -i "$ZDM_SSH_KEY" "${ZDM_ADMIN_USER}@${ZDM_HOST}" \
        "ls -t ./zdm_server_discovery_*.txt ./zdm_server_discovery_*.json 2>/dev/null | head -2")
    
    if [ -n "$remote_files" ]; then
        for file in $remote_files; do
            scp $SSH_OPTS -i "$ZDM_SSH_KEY" "${ZDM_ADMIN_USER}@${ZDM_HOST}:$file" "$OUTPUT_DIR/server/" 2>/dev/null
        done
        log_success "ZDM server discovery files collected to: $OUTPUT_DIR/server/"
        SUCCESSFUL_SERVERS+=("server")
        return 0
    else
        log_warn "No discovery output files found on ZDM server"
        FAILED_SERVERS+=("server")
        return 1
    fi
}

#-------------------------------------------------------------------------------
# Print Summary
#-------------------------------------------------------------------------------
print_summary() {
    log_section "Discovery Summary"
    
    echo ""
    echo "Successful Discoveries:"
    if [ ${#SUCCESSFUL_SERVERS[@]} -gt 0 ]; then
        for server in "${SUCCESSFUL_SERVERS[@]}"; do
            echo "  ✓ $server"
        done
    else
        echo "  (none)"
    fi
    
    echo ""
    echo "Failed Discoveries:"
    if [ ${#FAILED_SERVERS[@]} -gt 0 ]; then
        for server in "${FAILED_SERVERS[@]}"; do
            echo "  ✗ $server"
        done
    else
        echo "  (none)"
    fi
    
    echo ""
    echo "Output Location: $OUTPUT_DIR"
    
    echo ""
    echo "Discovery Files:"
    find "$OUTPUT_DIR" -type f -name "*.txt" -o -name "*.json" 2>/dev/null | while read -r file; do
        echo "  - $(basename "$file")"
    done
    
    echo ""
    if [ ${#FAILED_SERVERS[@]} -eq 0 ]; then
        log_success "All discoveries completed successfully!"
        echo ""
        echo "Next Steps:"
        echo "  1. Review the discovery reports in $OUTPUT_DIR"
        echo "  2. Proceed to Step 1: Discovery Questionnaire"
        echo "     Use: @Step1-Discovery-Questionnaire.prompt.md"
        return 0
    else
        log_warn "Some discoveries failed. Review logs and retry if needed."
        echo ""
        echo "Troubleshooting:"
        echo "  - Check SSH connectivity: ./$(basename "$0") --test"
        echo "  - Review logs in $OUTPUT_DIR/*/discovery_output.log"
        echo "  - Verify environment variables and SSH keys"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# Main Execution
#-------------------------------------------------------------------------------
main() {
    echo ""
    echo "==============================================================================="
    echo " ZDM Discovery Orchestration"
    echo " Project: PRODDB Migration to Oracle Database@Azure"
    echo " Timestamp: $(date)"
    echo "==============================================================================="
    
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
            show_config
            validate_config || exit 1
            test_all_connectivity
            exit $?
            ;;
    esac
    
    # Run full discovery
    show_config
    
    validate_config || exit 1
    
    test_all_connectivity || log_warn "Some connectivity tests failed - will attempt discovery anyway"
    
    create_output_dirs
    
    # Run discoveries - continue even if one fails
    run_source_discovery || true
    run_target_discovery || true
    run_server_discovery || true
    
    # Print summary and exit with appropriate code
    print_summary
    exit $?
}

# Execute main function
main "$@"
