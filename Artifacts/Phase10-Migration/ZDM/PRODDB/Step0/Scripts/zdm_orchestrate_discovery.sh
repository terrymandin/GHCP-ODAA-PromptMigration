#!/bin/bash
################################################################################
# ZDM Discovery Orchestration Script
# Project: PRODDB Migration to Oracle Database@Azure
# 
# Purpose: Orchestrate discovery across source, target, and ZDM servers
# 
# Usage: ./zdm_orchestrate_discovery.sh [options]
#   Options:
#     -h, --help     Show help message
#     -c, --config   Display current configuration
#     -t, --test     Test connectivity only (no discovery)
#
# Environment Variables (can be set before running):
#   - SOURCE_HOST, TARGET_HOST, ZDM_HOST: Server hostnames
#   - SOURCE_ADMIN_USER, TARGET_ADMIN_USER, ZDM_ADMIN_USER: SSH admin users
#   - SOURCE_SSH_KEY, TARGET_SSH_KEY, ZDM_SSH_KEY: SSH key paths
#   - ORACLE_USER, ZDM_SOFTWARE_USER: Application users
################################################################################

set -o pipefail

# ===========================================
# CONFIGURATION
# ===========================================

# Project name
PROJECT_NAME="PRODDB"

# Server hostnames
SOURCE_HOST="${SOURCE_HOST:-proddb01.corp.example.com}"
TARGET_HOST="${TARGET_HOST:-proddb-oda.eastus.azure.example.com}"
ZDM_HOST="${ZDM_HOST:-zdm-jumpbox.corp.example.com}"

# SSH/Admin users for each server (can be different for each environment)
SOURCE_ADMIN_USER="${SOURCE_ADMIN_USER:-oracle}"
TARGET_ADMIN_USER="${TARGET_ADMIN_USER:-opc}"
ZDM_ADMIN_USER="${ZDM_ADMIN_USER:-azureuser}"

# Oracle database software owner (for running SQL commands)
ORACLE_USER="${ORACLE_USER:-oracle}"

# ZDM software owner (for running ZDM CLI commands)
ZDM_SOFTWARE_USER="${ZDM_SOFTWARE_USER:-zdmuser}"

# SSH key paths (separate keys for each security domain)
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-$HOME/.ssh/onprem_oracle_key}"
TARGET_SSH_KEY="${TARGET_SSH_KEY:-$HOME/.ssh/oci_opc_key}"
ZDM_SSH_KEY="${ZDM_SSH_KEY:-$HOME/.ssh/azure_key}"

# SSH options
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=30 -o BatchMode=yes"

# Script directory and paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Calculate repository root (6 levels up: Scripts → Step0 → PRODDB → ZDM → Phase10-Migration → Artifacts → RepoRoot)
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../../.." && pwd)"

# Output directory (absolute path)
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/Artifacts/Phase10-Migration/ZDM/${PROJECT_NAME}/Step0/Discovery}"

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Error tracking
declare -A DISCOVERY_STATUS
DISCOVERY_STATUS[source]="NOT_RUN"
DISCOVERY_STATUS[target]="NOT_RUN"
DISCOVERY_STATUS[server]="NOT_RUN"

################################################################################
# Helper Functions
################################################################################

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_section() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

show_help() {
    cat << EOF
ZDM Discovery Orchestration Script
Project: ${PROJECT_NAME} Migration to Oracle Database@Azure

Usage: $0 [options]

Options:
  -h, --help     Show this help message
  -c, --config   Display current configuration
  -t, --test     Test SSH connectivity only (no discovery)

Environment Variables:
  SOURCE_HOST             Source database hostname (default: ${SOURCE_HOST})
  TARGET_HOST             Target database hostname (default: ${TARGET_HOST})
  ZDM_HOST                ZDM server hostname (default: ${ZDM_HOST})
  
  SOURCE_ADMIN_USER       SSH user for source server (default: ${SOURCE_ADMIN_USER})
  TARGET_ADMIN_USER       SSH user for target server (default: ${TARGET_ADMIN_USER})
  ZDM_ADMIN_USER          SSH user for ZDM server (default: ${ZDM_ADMIN_USER})
  
  SOURCE_SSH_KEY          SSH key for source server
  TARGET_SSH_KEY          SSH key for target server
  ZDM_SSH_KEY             SSH key for ZDM server
  
  ORACLE_USER             Oracle DB software owner (default: ${ORACLE_USER})
  ZDM_SOFTWARE_USER       ZDM software owner (default: ${ZDM_SOFTWARE_USER})

Examples:
  # Run full discovery with default settings
  $0

  # Test connectivity first
  $0 --test

  # Override environment variables
  SOURCE_HOST=mydb.example.com TARGET_HOST=targetdb.azure.com $0

EOF
}

show_config() {
    log_section "CURRENT CONFIGURATION"
    echo ""
    echo -e "${CYAN}Server Hostnames:${NC}"
    echo "  SOURCE_HOST:       ${SOURCE_HOST}"
    echo "  TARGET_HOST:       ${TARGET_HOST}"
    echo "  ZDM_HOST:          ${ZDM_HOST}"
    echo ""
    echo -e "${CYAN}SSH Admin Users:${NC}"
    echo "  SOURCE_ADMIN_USER: ${SOURCE_ADMIN_USER}"
    echo "  TARGET_ADMIN_USER: ${TARGET_ADMIN_USER}"
    echo "  ZDM_ADMIN_USER:    ${ZDM_ADMIN_USER}"
    echo ""
    echo -e "${CYAN}Application Users:${NC}"
    echo "  ORACLE_USER:       ${ORACLE_USER}"
    echo "  ZDM_SOFTWARE_USER: ${ZDM_SOFTWARE_USER}"
    echo ""
    echo -e "${CYAN}SSH Keys:${NC}"
    echo "  SOURCE_SSH_KEY:    ${SOURCE_SSH_KEY}"
    echo "  TARGET_SSH_KEY:    ${TARGET_SSH_KEY}"
    echo "  ZDM_SSH_KEY:       ${ZDM_SSH_KEY}"
    echo ""
    echo -e "${CYAN}Output Directory:${NC}"
    echo "  OUTPUT_DIR:        ${OUTPUT_DIR}"
    echo ""
}

validate_config() {
    local errors=0
    
    log_section "VALIDATING CONFIGURATION"
    
    # Check required hostnames
    if [ -z "$SOURCE_HOST" ]; then
        log_error "SOURCE_HOST is not set"
        errors=$((errors + 1))
    else
        log_info "SOURCE_HOST: $SOURCE_HOST"
    fi
    
    if [ -z "$TARGET_HOST" ]; then
        log_error "TARGET_HOST is not set"
        errors=$((errors + 1))
    else
        log_info "TARGET_HOST: $TARGET_HOST"
    fi
    
    if [ -z "$ZDM_HOST" ]; then
        log_error "ZDM_HOST is not set"
        errors=$((errors + 1))
    else
        log_info "ZDM_HOST: $ZDM_HOST"
    fi
    
    # Check SSH keys exist
    for key_var in SOURCE_SSH_KEY TARGET_SSH_KEY ZDM_SSH_KEY; do
        key_path="${!key_var}"
        if [ -n "$key_path" ] && [ -f "$key_path" ]; then
            log_info "$key_var: $key_path (exists)"
        elif [ -n "$key_path" ]; then
            log_warn "$key_var: $key_path (not found - will try default SSH key)"
        else
            log_warn "$key_var: not set (will use default SSH key)"
        fi
    done
    
    return $errors
}

test_ssh_connectivity() {
    local host="$1"
    local user="$2"
    local key_path="$3"
    local name="$4"
    
    log_info "Testing SSH connectivity to $name ($user@$host)..."
    
    local ssh_cmd="ssh $SSH_OPTS"
    if [ -n "$key_path" ] && [ -f "$key_path" ]; then
        ssh_cmd="$ssh_cmd -i $key_path"
    fi
    
    if $ssh_cmd "${user}@${host}" "echo 'SSH connection successful'" 2>/dev/null; then
        log_info "$name: SSH connection successful"
        return 0
    else
        log_error "$name: SSH connection failed"
        return 1
    fi
}

################################################################################
# Discovery Functions
################################################################################

run_source_discovery() {
    log_section "SOURCE DATABASE DISCOVERY"
    
    local script_path="$SCRIPT_DIR/zdm_source_discovery.sh"
    local output_subdir="$OUTPUT_DIR/source"
    
    if [ ! -f "$script_path" ]; then
        log_error "Source discovery script not found: $script_path"
        DISCOVERY_STATUS[source]="SCRIPT_NOT_FOUND"
        return 1
    fi
    
    # Create output directory
    mkdir -p "$output_subdir"
    
    log_info "Running source discovery on $SOURCE_HOST as $SOURCE_ADMIN_USER..."
    
    local ssh_cmd="ssh $SSH_OPTS"
    if [ -n "$SOURCE_SSH_KEY" ] && [ -f "$SOURCE_SSH_KEY" ]; then
        ssh_cmd="$ssh_cmd -i $SOURCE_SSH_KEY"
    fi
    
    # Run discovery script remotely using login shell
    if $ssh_cmd "${SOURCE_ADMIN_USER}@${SOURCE_HOST}" \
        "ORACLE_USER='$ORACLE_USER' bash -l -s" < "$script_path" 2>&1; then
        
        log_info "Source discovery completed, collecting results..."
        
        # Collect output files
        local scp_cmd="scp $SSH_OPTS"
        if [ -n "$SOURCE_SSH_KEY" ] && [ -f "$SOURCE_SSH_KEY" ]; then
            scp_cmd="$scp_cmd -i $SOURCE_SSH_KEY"
        fi
        
        # Get list of discovery files and copy them
        $scp_cmd "${SOURCE_ADMIN_USER}@${SOURCE_HOST}:./zdm_source_discovery_*" "$output_subdir/" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            log_info "Source discovery results saved to: $output_subdir"
            DISCOVERY_STATUS[source]="SUCCESS"
            
            # Cleanup remote files
            $ssh_cmd "${SOURCE_ADMIN_USER}@${SOURCE_HOST}" "rm -f ./zdm_source_discovery_*.txt ./zdm_source_discovery_*.json" 2>/dev/null
            return 0
        else
            log_warn "Could not collect source discovery files"
            DISCOVERY_STATUS[source]="COLLECT_FAILED"
            return 1
        fi
    else
        log_error "Source discovery failed"
        DISCOVERY_STATUS[source]="FAILED"
        return 1
    fi
}

run_target_discovery() {
    log_section "TARGET DATABASE DISCOVERY"
    
    local script_path="$SCRIPT_DIR/zdm_target_discovery.sh"
    local output_subdir="$OUTPUT_DIR/target"
    
    if [ ! -f "$script_path" ]; then
        log_error "Target discovery script not found: $script_path"
        DISCOVERY_STATUS[target]="SCRIPT_NOT_FOUND"
        return 1
    fi
    
    # Create output directory
    mkdir -p "$output_subdir"
    
    log_info "Running target discovery on $TARGET_HOST as $TARGET_ADMIN_USER..."
    
    local ssh_cmd="ssh $SSH_OPTS"
    if [ -n "$TARGET_SSH_KEY" ] && [ -f "$TARGET_SSH_KEY" ]; then
        ssh_cmd="$ssh_cmd -i $TARGET_SSH_KEY"
    fi
    
    # Run discovery script remotely using login shell
    if $ssh_cmd "${TARGET_ADMIN_USER}@${TARGET_HOST}" \
        "ORACLE_USER='$ORACLE_USER' bash -l -s" < "$script_path" 2>&1; then
        
        log_info "Target discovery completed, collecting results..."
        
        # Collect output files
        local scp_cmd="scp $SSH_OPTS"
        if [ -n "$TARGET_SSH_KEY" ] && [ -f "$TARGET_SSH_KEY" ]; then
            scp_cmd="$scp_cmd -i $TARGET_SSH_KEY"
        fi
        
        # Get list of discovery files and copy them
        $scp_cmd "${TARGET_ADMIN_USER}@${TARGET_HOST}:./zdm_target_discovery_*" "$output_subdir/" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            log_info "Target discovery results saved to: $output_subdir"
            DISCOVERY_STATUS[target]="SUCCESS"
            
            # Cleanup remote files
            $ssh_cmd "${TARGET_ADMIN_USER}@${TARGET_HOST}" "rm -f ./zdm_target_discovery_*.txt ./zdm_target_discovery_*.json" 2>/dev/null
            return 0
        else
            log_warn "Could not collect target discovery files"
            DISCOVERY_STATUS[target]="COLLECT_FAILED"
            return 1
        fi
    else
        log_error "Target discovery failed"
        DISCOVERY_STATUS[target]="FAILED"
        return 1
    fi
}

run_server_discovery() {
    log_section "ZDM SERVER DISCOVERY"
    
    local script_path="$SCRIPT_DIR/zdm_server_discovery.sh"
    local output_subdir="$OUTPUT_DIR/server"
    
    if [ ! -f "$script_path" ]; then
        log_error "ZDM server discovery script not found: $script_path"
        DISCOVERY_STATUS[server]="SCRIPT_NOT_FOUND"
        return 1
    fi
    
    # Create output directory
    mkdir -p "$output_subdir"
    
    log_info "Running ZDM server discovery on $ZDM_HOST as $ZDM_ADMIN_USER..."
    
    local ssh_cmd="ssh $SSH_OPTS"
    if [ -n "$ZDM_SSH_KEY" ] && [ -f "$ZDM_SSH_KEY" ]; then
        ssh_cmd="$ssh_cmd -i $ZDM_SSH_KEY"
    fi
    
    # Run discovery script remotely, passing SOURCE_HOST and TARGET_HOST for connectivity tests
    if $ssh_cmd "${ZDM_ADMIN_USER}@${ZDM_HOST}" \
        "SOURCE_HOST='$SOURCE_HOST' TARGET_HOST='$TARGET_HOST' ZDM_USER='$ZDM_SOFTWARE_USER' bash -l -s" < "$script_path" 2>&1; then
        
        log_info "ZDM server discovery completed, collecting results..."
        
        # Collect output files
        local scp_cmd="scp $SSH_OPTS"
        if [ -n "$ZDM_SSH_KEY" ] && [ -f "$ZDM_SSH_KEY" ]; then
            scp_cmd="$scp_cmd -i $ZDM_SSH_KEY"
        fi
        
        # Get list of discovery files and copy them
        $scp_cmd "${ZDM_ADMIN_USER}@${ZDM_HOST}:./zdm_server_discovery_*" "$output_subdir/" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            log_info "ZDM server discovery results saved to: $output_subdir"
            DISCOVERY_STATUS[server]="SUCCESS"
            
            # Cleanup remote files
            $ssh_cmd "${ZDM_ADMIN_USER}@${ZDM_HOST}" "rm -f ./zdm_server_discovery_*.txt ./zdm_server_discovery_*.json" 2>/dev/null
            return 0
        else
            log_warn "Could not collect ZDM server discovery files"
            DISCOVERY_STATUS[server]="COLLECT_FAILED"
            return 1
        fi
    else
        log_error "ZDM server discovery failed"
        DISCOVERY_STATUS[server]="FAILED"
        return 1
    fi
}

show_summary() {
    log_section "DISCOVERY SUMMARY"
    
    local success_count=0
    local total_count=3
    
    echo ""
    echo -e "${CYAN}Discovery Results:${NC}"
    echo ""
    
    for server in source target server; do
        local status="${DISCOVERY_STATUS[$server]}"
        case $status in
            "SUCCESS")
                echo -e "  ${server}: ${GREEN}SUCCESS${NC}"
                success_count=$((success_count + 1))
                ;;
            "NOT_RUN")
                echo -e "  ${server}: ${YELLOW}NOT RUN${NC}"
                ;;
            *)
                echo -e "  ${server}: ${RED}${status}${NC}"
                ;;
        esac
    done
    
    echo ""
    echo -e "${CYAN}Summary: ${success_count}/${total_count} discoveries completed successfully${NC}"
    echo ""
    
    if [ $success_count -gt 0 ]; then
        echo -e "${CYAN}Output Location:${NC}"
        echo "  $OUTPUT_DIR"
        echo ""
        
        if [ -d "$OUTPUT_DIR" ]; then
            echo -e "${CYAN}Discovery Files:${NC}"
            find "$OUTPUT_DIR" -type f -name "*.txt" -o -name "*.json" 2>/dev/null | while read f; do
                echo "  $f"
            done
        fi
    fi
    
    echo ""
    
    if [ $success_count -eq $total_count ]; then
        echo -e "${GREEN}All discoveries completed successfully!${NC}"
        echo ""
        echo "Next Steps:"
        echo "  1. Review the discovery output files in $OUTPUT_DIR"
        echo "  2. Proceed to Step 1: Discovery Questionnaire"
        return 0
    elif [ $success_count -gt 0 ]; then
        echo -e "${YELLOW}Partial success - some discoveries completed.${NC}"
        echo ""
        echo "Review the failed discoveries and retry if needed."
        return 1
    else
        echo -e "${RED}All discoveries failed!${NC}"
        echo ""
        echo "Check SSH connectivity and server configuration."
        return 2
    fi
}

################################################################################
# Main
################################################################################

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -c|--config)
                show_config
                exit 0
                ;;
            -t|--test)
                log_section "SSH CONNECTIVITY TEST"
                test_ssh_connectivity "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$SOURCE_SSH_KEY" "Source Database"
                test_ssh_connectivity "$TARGET_HOST" "$TARGET_ADMIN_USER" "$TARGET_SSH_KEY" "Target Database"
                test_ssh_connectivity "$ZDM_HOST" "$ZDM_ADMIN_USER" "$ZDM_SSH_KEY" "ZDM Server"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
        shift
    done
    
    # Display banner
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     ZDM Discovery Orchestration - ${PROJECT_NAME}              ║${NC}"
    echo -e "${CYAN}║     Migration to Oracle Database@Azure                     ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Validate configuration
    validate_config
    if [ $? -ne 0 ]; then
        log_error "Configuration validation failed"
        exit 1
    fi
    
    # Create output directory structure
    log_info "Creating output directory: $OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR/source" "$OUTPUT_DIR/target" "$OUTPUT_DIR/server"
    
    # Run discoveries (continue on failure)
    run_source_discovery || true
    run_target_discovery || true
    run_server_discovery || true
    
    # Show summary
    show_summary
    exit $?
}

# Run main function
main "$@"
