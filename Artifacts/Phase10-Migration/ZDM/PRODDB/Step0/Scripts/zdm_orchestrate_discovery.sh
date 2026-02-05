#!/bin/bash
#
# ZDM Discovery Orchestration Script
# Project: PRODDB Migration to Oracle Database@Azure
#
# This script orchestrates the discovery process across all servers:
#   - Source Database: proddb01.corp.example.com
#   - Target Database: proddb-oda.eastus.azure.example.com
#   - ZDM Server: zdm-jumpbox.corp.example.com
#
# Usage:
#   ./zdm_orchestrate_discovery.sh           # Run full discovery
#   ./zdm_orchestrate_discovery.sh -h        # Show help
#   ./zdm_orchestrate_discovery.sh -c        # Show configuration
#   ./zdm_orchestrate_discovery.sh -t        # Test connectivity only
#

# =============================================================================
# CONFIGURATION
# =============================================================================

# Get script directory and calculate repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Navigate up 6 levels: Scripts -> Step0 -> PRODDB -> ZDM -> Phase10-Migration -> Artifacts -> RepoRoot
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../../.." && pwd)"

# Server hostnames
SOURCE_HOST="${SOURCE_HOST:-proddb01.corp.example.com}"
TARGET_HOST="${TARGET_HOST:-proddb-oda.eastus.azure.example.com}"
ZDM_HOST="${ZDM_HOST:-zdm-jumpbox.corp.example.com}"

# SSH/Admin users for each server (different per environment)
SOURCE_ADMIN_USER="${SOURCE_ADMIN_USER:-oracle}"
TARGET_ADMIN_USER="${TARGET_ADMIN_USER:-opc}"
ZDM_ADMIN_USER="${ZDM_ADMIN_USER:-azureuser}"

# Application users
ORACLE_USER="${ORACLE_USER:-oracle}"
ZDM_USER="${ZDM_USER:-zdmuser}"

# SSH key paths (separate keys for each security domain)
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-$HOME/.ssh/onprem_oracle_key}"
TARGET_SSH_KEY="${TARGET_SSH_KEY:-$HOME/.ssh/oci_opc_key}"
ZDM_SSH_KEY="${ZDM_SSH_KEY:-$HOME/.ssh/azure_key}"

# Output directory (relative to repository root)
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/Artifacts/Phase10-Migration/ZDM/PRODDB/Step0/Discovery}"

# SSH options
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=30 -o BatchMode=yes"

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Tracking variables
DISCOVERY_RESULTS=()
FAILED_SERVERS=()
SUCCESSFUL_SERVERS=()

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

show_banner() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║            ZDM DISCOVERY ORCHESTRATION - PRODDB MIGRATION                 ║${NC}"
    echo -e "${GREEN}╠═══════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║  Source: proddb01.corp.example.com                                        ║${NC}"
    echo -e "${GREEN}║  Target: proddb-oda.eastus.azure.example.com                              ║${NC}"
    echo -e "${GREEN}║  ZDM:    zdm-jumpbox.corp.example.com                                     ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

log_section() {
    local title="$1"
    echo ""
    echo -e "${BLUE}=============================================================================${NC}"
    echo -e "${BLUE}  $title${NC}"
    echo -e "${BLUE}=============================================================================${NC}"
    echo ""
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

show_help() {
    cat << EOF
ZDM Discovery Orchestration Script
Project: PRODDB Migration to Oracle Database@Azure

Usage: $(basename "$0") [OPTIONS]

Options:
    -h, --help      Show this help message
    -c, --config    Display current configuration
    -t, --test      Test SSH connectivity only (no discovery)

Environment Variables:
    SOURCE_HOST         Source database hostname (default: proddb01.corp.example.com)
    TARGET_HOST         Target database hostname (default: proddb-oda.eastus.azure.example.com)
    ZDM_HOST            ZDM server hostname (default: zdm-jumpbox.corp.example.com)
    
    SOURCE_ADMIN_USER   Admin user for source server (default: oracle)
    TARGET_ADMIN_USER   Admin user for target server (default: opc)
    ZDM_ADMIN_USER      Admin user for ZDM server (default: azureuser)
    
    ORACLE_USER         Oracle database software owner (default: oracle)
    ZDM_USER            ZDM software owner (default: zdmuser)
    
    SOURCE_SSH_KEY      SSH key for source server (default: ~/.ssh/onprem_oracle_key)
    TARGET_SSH_KEY      SSH key for target server (default: ~/.ssh/oci_opc_key)
    ZDM_SSH_KEY         SSH key for ZDM server (default: ~/.ssh/azure_key)
    
    OUTPUT_DIR          Output directory for discovery files

Examples:
    # Run full discovery with defaults
    ./$(basename "$0")
    
    # Test connectivity only
    ./$(basename "$0") -t
    
    # Use custom configuration
    SOURCE_HOST=mydb.example.com TARGET_HOST=targetdb.example.com ./$(basename "$0")

EOF
}

show_config() {
    log_section "CURRENT CONFIGURATION"
    
    echo -e "${CYAN}Server Hostnames:${NC}"
    echo "  SOURCE_HOST:        $SOURCE_HOST"
    echo "  TARGET_HOST:        $TARGET_HOST"
    echo "  ZDM_HOST:           $ZDM_HOST"
    echo ""
    
    echo -e "${CYAN}Admin Users (SSH):${NC}"
    echo "  SOURCE_ADMIN_USER:  $SOURCE_ADMIN_USER"
    echo "  TARGET_ADMIN_USER:  $TARGET_ADMIN_USER"
    echo "  ZDM_ADMIN_USER:     $ZDM_ADMIN_USER"
    echo ""
    
    echo -e "${CYAN}Application Users:${NC}"
    echo "  ORACLE_USER:        $ORACLE_USER"
    echo "  ZDM_USER:           $ZDM_USER"
    echo ""
    
    echo -e "${CYAN}SSH Keys:${NC}"
    echo "  SOURCE_SSH_KEY:     $SOURCE_SSH_KEY $([ -f "$SOURCE_SSH_KEY" ] && echo -e "${GREEN}[EXISTS]${NC}" || echo -e "${RED}[NOT FOUND]${NC}")"
    echo "  TARGET_SSH_KEY:     $TARGET_SSH_KEY $([ -f "$TARGET_SSH_KEY" ] && echo -e "${GREEN}[EXISTS]${NC}" || echo -e "${RED}[NOT FOUND]${NC}")"
    echo "  ZDM_SSH_KEY:        $ZDM_SSH_KEY $([ -f "$ZDM_SSH_KEY" ] && echo -e "${GREEN}[EXISTS]${NC}" || echo -e "${RED}[NOT FOUND]${NC}")"
    echo ""
    
    echo -e "${CYAN}Paths:${NC}"
    echo "  SCRIPT_DIR:         $SCRIPT_DIR"
    echo "  REPO_ROOT:          $REPO_ROOT"
    echo "  OUTPUT_DIR:         $OUTPUT_DIR"
    echo ""
}

validate_config() {
    log_section "VALIDATING CONFIGURATION"
    
    local errors=0
    
    # Check SSH keys exist
    if [ ! -f "$SOURCE_SSH_KEY" ]; then
        log_warn "Source SSH key not found: $SOURCE_SSH_KEY"
        errors=$((errors + 1))
    else
        log_success "Source SSH key found: $SOURCE_SSH_KEY"
    fi
    
    if [ ! -f "$TARGET_SSH_KEY" ]; then
        log_warn "Target SSH key not found: $TARGET_SSH_KEY"
        errors=$((errors + 1))
    else
        log_success "Target SSH key found: $TARGET_SSH_KEY"
    fi
    
    if [ ! -f "$ZDM_SSH_KEY" ]; then
        log_warn "ZDM SSH key not found: $ZDM_SSH_KEY"
        errors=$((errors + 1))
    else
        log_success "ZDM SSH key found: $ZDM_SSH_KEY"
    fi
    
    # Check discovery scripts exist
    local scripts=("zdm_source_discovery.sh" "zdm_target_discovery.sh" "zdm_server_discovery.sh")
    for script in "${scripts[@]}"; do
        if [ -f "$SCRIPT_DIR/$script" ]; then
            log_success "Discovery script found: $script"
        else
            log_error "Discovery script not found: $SCRIPT_DIR/$script"
            errors=$((errors + 1))
        fi
    done
    
    # Create output directories
    mkdir -p "$OUTPUT_DIR/source" "$OUTPUT_DIR/target" "$OUTPUT_DIR/server"
    log_success "Output directories created: $OUTPUT_DIR"
    
    echo ""
    if [ $errors -gt 0 ]; then
        log_warn "$errors configuration warning(s) found. Discovery may not complete successfully for all servers."
    else
        log_success "All configuration checks passed!"
    fi
    
    return 0
}

test_ssh_connectivity() {
    local host="$1"
    local user="$2"
    local key="$3"
    local label="$4"
    
    echo -n "  Testing SSH to $label ($user@$host)... "
    
    if [ ! -f "$key" ]; then
        echo -e "${RED}FAILED${NC} (SSH key not found: $key)"
        return 1
    fi
    
    if ssh $SSH_OPTS -i "$key" "${user}@${host}" "echo OK" &>/dev/null; then
        echo -e "${GREEN}SUCCESS${NC}"
        return 0
    else
        echo -e "${RED}FAILED${NC}"
        return 1
    fi
}

test_all_connectivity() {
    log_section "TESTING SSH CONNECTIVITY"
    
    local success=0
    local failed=0
    
    if test_ssh_connectivity "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$SOURCE_SSH_KEY" "Source"; then
        success=$((success + 1))
    else
        failed=$((failed + 1))
    fi
    
    if test_ssh_connectivity "$TARGET_HOST" "$TARGET_ADMIN_USER" "$TARGET_SSH_KEY" "Target"; then
        success=$((success + 1))
    else
        failed=$((failed + 1))
    fi
    
    if test_ssh_connectivity "$ZDM_HOST" "$ZDM_ADMIN_USER" "$ZDM_SSH_KEY" "ZDM"; then
        success=$((success + 1))
    else
        failed=$((failed + 1))
    fi
    
    echo ""
    echo "Connectivity Results: $success successful, $failed failed"
    
    if [ $failed -gt 0 ]; then
        log_warn "Some servers are not reachable. Discovery will skip unreachable servers."
    fi
    
    return 0
}

# =============================================================================
# DISCOVERY FUNCTIONS
# =============================================================================

run_source_discovery() {
    log_section "SOURCE DATABASE DISCOVERY"
    
    local script_path="$SCRIPT_DIR/zdm_source_discovery.sh"
    local output_dir="$OUTPUT_DIR/source"
    
    log_info "Server: $SOURCE_HOST"
    log_info "User: $SOURCE_ADMIN_USER"
    log_info "SSH Key: $SOURCE_SSH_KEY"
    echo ""
    
    # Test connectivity first
    if ! test_ssh_connectivity "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$SOURCE_SSH_KEY" "Source"; then
        log_error "Cannot connect to source server. Skipping discovery."
        FAILED_SERVERS+=("source:$SOURCE_HOST")
        return 1
    fi
    
    log_info "Running discovery script on source server..."
    
    # Copy and execute discovery script
    # Use bash -l to ensure login shell sources environment
    if ssh $SSH_OPTS -i "$SOURCE_SSH_KEY" "${SOURCE_ADMIN_USER}@${SOURCE_HOST}" \
        "ORACLE_USER='$ORACLE_USER' bash -l -s" < "$script_path"; then
        
        log_success "Discovery script completed on source server"
        
        # Collect output files
        log_info "Collecting discovery output files..."
        scp $SSH_OPTS -i "$SOURCE_SSH_KEY" "${SOURCE_ADMIN_USER}@${SOURCE_HOST}:./zdm_source_discovery_*.txt" "$output_dir/" 2>/dev/null
        scp $SSH_OPTS -i "$SOURCE_SSH_KEY" "${SOURCE_ADMIN_USER}@${SOURCE_HOST}:./zdm_source_discovery_*.json" "$output_dir/" 2>/dev/null
        
        # List collected files
        local collected_files=$(ls -1 "$output_dir"/zdm_source_discovery_*.txt 2>/dev/null | wc -l)
        if [ "$collected_files" -gt 0 ]; then
            log_success "Collected $collected_files file(s) to $output_dir/"
            ls -la "$output_dir"/*.txt 2>/dev/null
            SUCCESSFUL_SERVERS+=("source:$SOURCE_HOST")
        else
            log_warn "No output files collected from source server"
            FAILED_SERVERS+=("source:$SOURCE_HOST")
            return 1
        fi
    else
        log_error "Discovery script failed on source server"
        FAILED_SERVERS+=("source:$SOURCE_HOST")
        return 1
    fi
    
    return 0
}

run_target_discovery() {
    log_section "TARGET DATABASE DISCOVERY"
    
    local script_path="$SCRIPT_DIR/zdm_target_discovery.sh"
    local output_dir="$OUTPUT_DIR/target"
    
    log_info "Server: $TARGET_HOST"
    log_info "User: $TARGET_ADMIN_USER"
    log_info "SSH Key: $TARGET_SSH_KEY"
    echo ""
    
    # Test connectivity first
    if ! test_ssh_connectivity "$TARGET_HOST" "$TARGET_ADMIN_USER" "$TARGET_SSH_KEY" "Target"; then
        log_error "Cannot connect to target server. Skipping discovery."
        FAILED_SERVERS+=("target:$TARGET_HOST")
        return 1
    fi
    
    log_info "Running discovery script on target server..."
    
    # Copy and execute discovery script
    if ssh $SSH_OPTS -i "$TARGET_SSH_KEY" "${TARGET_ADMIN_USER}@${TARGET_HOST}" \
        "ORACLE_USER='$ORACLE_USER' bash -l -s" < "$script_path"; then
        
        log_success "Discovery script completed on target server"
        
        # Collect output files
        log_info "Collecting discovery output files..."
        scp $SSH_OPTS -i "$TARGET_SSH_KEY" "${TARGET_ADMIN_USER}@${TARGET_HOST}:./zdm_target_discovery_*.txt" "$output_dir/" 2>/dev/null
        scp $SSH_OPTS -i "$TARGET_SSH_KEY" "${TARGET_ADMIN_USER}@${TARGET_HOST}:./zdm_target_discovery_*.json" "$output_dir/" 2>/dev/null
        
        # List collected files
        local collected_files=$(ls -1 "$output_dir"/zdm_target_discovery_*.txt 2>/dev/null | wc -l)
        if [ "$collected_files" -gt 0 ]; then
            log_success "Collected $collected_files file(s) to $output_dir/"
            ls -la "$output_dir"/*.txt 2>/dev/null
            SUCCESSFUL_SERVERS+=("target:$TARGET_HOST")
        else
            log_warn "No output files collected from target server"
            FAILED_SERVERS+=("target:$TARGET_HOST")
            return 1
        fi
    else
        log_error "Discovery script failed on target server"
        FAILED_SERVERS+=("target:$TARGET_HOST")
        return 1
    fi
    
    return 0
}

run_server_discovery() {
    log_section "ZDM SERVER DISCOVERY"
    
    local script_path="$SCRIPT_DIR/zdm_server_discovery.sh"
    local output_dir="$OUTPUT_DIR/server"
    
    log_info "Server: $ZDM_HOST"
    log_info "User: $ZDM_ADMIN_USER"
    log_info "SSH Key: $ZDM_SSH_KEY"
    log_info "Connectivity tests: SOURCE_HOST=$SOURCE_HOST, TARGET_HOST=$TARGET_HOST"
    echo ""
    
    # Test connectivity first
    if ! test_ssh_connectivity "$ZDM_HOST" "$ZDM_ADMIN_USER" "$ZDM_SSH_KEY" "ZDM"; then
        log_error "Cannot connect to ZDM server. Skipping discovery."
        FAILED_SERVERS+=("server:$ZDM_HOST")
        return 1
    fi
    
    log_info "Running discovery script on ZDM server..."
    
    # Copy and execute discovery script
    # Pass SOURCE_HOST and TARGET_HOST for connectivity testing
    if ssh $SSH_OPTS -i "$ZDM_SSH_KEY" "${ZDM_ADMIN_USER}@${ZDM_HOST}" \
        "SOURCE_HOST='$SOURCE_HOST' TARGET_HOST='$TARGET_HOST' ZDM_USER='$ZDM_USER' bash -l -s" < "$script_path"; then
        
        log_success "Discovery script completed on ZDM server"
        
        # Collect output files
        log_info "Collecting discovery output files..."
        scp $SSH_OPTS -i "$ZDM_SSH_KEY" "${ZDM_ADMIN_USER}@${ZDM_HOST}:./zdm_server_discovery_*.txt" "$output_dir/" 2>/dev/null
        scp $SSH_OPTS -i "$ZDM_SSH_KEY" "${ZDM_ADMIN_USER}@${ZDM_HOST}:./zdm_server_discovery_*.json" "$output_dir/" 2>/dev/null
        
        # List collected files
        local collected_files=$(ls -1 "$output_dir"/zdm_server_discovery_*.txt 2>/dev/null | wc -l)
        if [ "$collected_files" -gt 0 ]; then
            log_success "Collected $collected_files file(s) to $output_dir/"
            ls -la "$output_dir"/*.txt 2>/dev/null
            SUCCESSFUL_SERVERS+=("server:$ZDM_HOST")
        else
            log_warn "No output files collected from ZDM server"
            FAILED_SERVERS+=("server:$ZDM_HOST")
            return 1
        fi
    else
        log_error "Discovery script failed on ZDM server"
        FAILED_SERVERS+=("server:$ZDM_HOST")
        return 1
    fi
    
    return 0
}

show_summary() {
    log_section "DISCOVERY SUMMARY"
    
    echo -e "${CYAN}Successful Servers:${NC}"
    if [ ${#SUCCESSFUL_SERVERS[@]} -eq 0 ]; then
        echo "  None"
    else
        for server in "${SUCCESSFUL_SERVERS[@]}"; do
            echo -e "  ${GREEN}✓${NC} $server"
        done
    fi
    echo ""
    
    echo -e "${CYAN}Failed Servers:${NC}"
    if [ ${#FAILED_SERVERS[@]} -eq 0 ]; then
        echo "  None"
    else
        for server in "${FAILED_SERVERS[@]}"; do
            echo -e "  ${RED}✗${NC} $server"
        done
    fi
    echo ""
    
    echo -e "${CYAN}Output Directory:${NC}"
    echo "  $OUTPUT_DIR"
    echo ""
    
    echo -e "${CYAN}Collected Files:${NC}"
    find "$OUTPUT_DIR" -name "*.txt" -o -name "*.json" 2>/dev/null | while read -r file; do
        echo "  $file"
    done
    echo ""
    
    # Overall status
    local total_servers=3
    local success_count=${#SUCCESSFUL_SERVERS[@]}
    
    if [ $success_count -eq $total_servers ]; then
        echo -e "${GREEN}═══════════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}  DISCOVERY COMPLETED SUCCESSFULLY ($success_count/$total_servers servers)${NC}"
        echo -e "${GREEN}═══════════════════════════════════════════════════════════════════════════${NC}"
    elif [ $success_count -gt 0 ]; then
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}  DISCOVERY PARTIALLY COMPLETED ($success_count/$total_servers servers)${NC}"
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════════════${NC}"
    else
        echo -e "${RED}═══════════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${RED}  DISCOVERY FAILED (0/$total_servers servers)${NC}"
        echo -e "${RED}═══════════════════════════════════════════════════════════════════════════${NC}"
    fi
    echo ""
    
    echo "Next Steps:"
    echo "  1. Review discovery output files in $OUTPUT_DIR"
    echo "  2. Address any issues identified in the discovery"
    echo "  3. Proceed to Step 1: Discovery Questionnaire"
    echo ""
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    # Parse command line arguments
    case "${1:-}" in
        -h|--help)
            show_help
            exit 0
            ;;
        -c|--config)
            show_banner
            show_config
            exit 0
            ;;
        -t|--test)
            show_banner
            test_all_connectivity
            exit 0
            ;;
    esac
    
    # Show banner
    show_banner
    
    echo "Timestamp: $(date)"
    echo ""
    
    # Validate configuration
    validate_config
    
    # Test connectivity
    test_all_connectivity
    
    # Run discovery on each server (continue on failure)
    run_source_discovery || true
    run_target_discovery || true
    run_server_discovery || true
    
    # Show summary
    show_summary
    
    # Return appropriate exit code
    if [ ${#FAILED_SERVERS[@]} -eq 0 ]; then
        exit 0
    elif [ ${#SUCCESSFUL_SERVERS[@]} -gt 0 ]; then
        exit 1  # Partial success
    else
        exit 2  # Complete failure
    fi
}

# Run main function
main "$@"
