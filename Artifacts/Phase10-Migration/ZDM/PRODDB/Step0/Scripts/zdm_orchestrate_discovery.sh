#!/bin/bash
# ===========================================
# ZDM Discovery Orchestration Script
# Project: PRODDB Migration to Oracle Database@Azure
# Generated: 2026-01-30
# ===========================================
#
# This script orchestrates discovery across all servers:
#   - Source: proddb01.corp.example.com
#   - Target: proddb-oda.eastus.azure.example.com
#   - ZDM: zdm-jumpbox.corp.example.com
#
# Usage:
#   ./zdm_orchestrate_discovery.sh [options]
#
# Options:
#   -h, --help      Show help message
#   -c, --config    Show current configuration
#   -t, --test      Test connectivity only (no discovery)
#   source          Run source discovery only
#   target          Run target discovery only
#   server          Run ZDM server discovery only
#   all             Run all discoveries (default)
#
# ===========================================

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ===========================================
# CONFIGURATION
# ===========================================

# Host Configuration
SOURCE_HOST="${SOURCE_HOST:-proddb01.corp.example.com}"
TARGET_HOST="${TARGET_HOST:-proddb-oda.eastus.azure.example.com}"
ZDM_HOST="${ZDM_HOST:-zdm-jumpbox.corp.example.com}"

# SSH/Admin users for each server (different for each environment)
SOURCE_ADMIN_USER="${SOURCE_ADMIN_USER:-oracle}"
TARGET_ADMIN_USER="${TARGET_ADMIN_USER:-opc}"
ZDM_ADMIN_USER="${ZDM_ADMIN_USER:-azureuser}"

# Application users
ORACLE_USER="${ORACLE_USER:-oracle}"
ZDM_USER="${ZDM_USER:-zdmuser}"

# SSH key paths (different for each environment)
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-~/.ssh/onprem_oracle_key}"
TARGET_SSH_KEY="${TARGET_SSH_KEY:-~/.ssh/oci_opc_key}"
ZDM_SSH_KEY="${ZDM_SSH_KEY:-~/.ssh/azure_key}"

# Database name for artifact paths
DB_NAME="${DB_NAME:-PRODDB}"

# Script location (this script's directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Calculate repository root (6 levels up from Scripts/)
# Scripts/ -> Step0/ -> PRODDB/ -> ZDM/ -> Phase10-Migration/ -> Artifacts/ -> RepoRoot
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../../.." && pwd)"

# Output directory (relative to repo root)
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/Artifacts/Phase10-Migration/ZDM/${DB_NAME}/Step0/Discovery}"

# SSH options
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"

# Track success/failure
declare -A RESULTS

# ===========================================
# HELPER FUNCTIONS
# ===========================================

print_header() {
    echo -e "\n${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}  ${CYAN}$1${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
}

print_section() {
    echo -e "\n${YELLOW}▶ $1${NC}"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

show_help() {
    cat << EOF
ZDM Discovery Orchestration Script
===================================

Usage: $(basename "$0") [options] [target]

Options:
  -h, --help      Show this help message
  -c, --config    Show current configuration
  -t, --test      Test SSH connectivity only (no discovery)

Targets:
  source          Run source database discovery only
  target          Run target database discovery only
  server          Run ZDM server discovery only
  all             Run all discoveries (default)

Environment Variables:
  SOURCE_HOST          Source database hostname (default: proddb01.corp.example.com)
  TARGET_HOST          Target database hostname (default: proddb-oda.eastus.azure.example.com)
  ZDM_HOST             ZDM server hostname (default: zdm-jumpbox.corp.example.com)
  SOURCE_ADMIN_USER    SSH user for source (default: oracle)
  TARGET_ADMIN_USER    SSH user for target (default: opc)
  ZDM_ADMIN_USER       SSH user for ZDM (default: azureuser)
  SOURCE_SSH_KEY       SSH key for source (default: ~/.ssh/onprem_oracle_key)
  TARGET_SSH_KEY       SSH key for target (default: ~/.ssh/oci_opc_key)
  ZDM_SSH_KEY          SSH key for ZDM (default: ~/.ssh/azure_key)
  ORACLE_USER          Oracle database owner (default: oracle)
  ZDM_USER             ZDM software owner (default: zdmuser)
  OUTPUT_DIR           Discovery output directory

Examples:
  # Run all discoveries with defaults
  ./$(basename "$0")

  # Test connectivity only
  ./$(basename "$0") --test

  # Run only source discovery
  ./$(basename "$0") source

  # Override SSH user for source
  SOURCE_ADMIN_USER=opc ./$(basename "$0") source

EOF
}

show_config() {
    print_header "Current Configuration"
    
    echo ""
    echo "Hosts:"
    echo "  Source:  $SOURCE_HOST"
    echo "  Target:  $TARGET_HOST"
    echo "  ZDM:     $ZDM_HOST"
    echo ""
    echo "SSH Users:"
    echo "  Source:  $SOURCE_ADMIN_USER (SSH key: $SOURCE_SSH_KEY)"
    echo "  Target:  $TARGET_ADMIN_USER (SSH key: $TARGET_SSH_KEY)"
    echo "  ZDM:     $ZDM_ADMIN_USER (SSH key: $ZDM_SSH_KEY)"
    echo ""
    echo "Application Users:"
    echo "  Oracle:  $ORACLE_USER"
    echo "  ZDM:     $ZDM_USER"
    echo ""
    echo "Paths:"
    echo "  Script Dir:  $SCRIPT_DIR"
    echo "  Repo Root:   $REPO_ROOT"
    echo "  Output Dir:  $OUTPUT_DIR"
    echo ""
}

test_ssh() {
    local host="$1"
    local user="$2"
    local key="$3"
    local expanded_key=$(eval echo "$key")
    
    if [ ! -f "$expanded_key" ]; then
        log_error "SSH key not found: $key"
        return 1
    fi
    
    if ssh $SSH_OPTS -i "$expanded_key" "${user}@${host}" "echo 'SSH OK'" &>/dev/null; then
        log_success "SSH to ${user}@${host} - OK"
        return 0
    else
        log_error "SSH to ${user}@${host} - FAILED"
        return 1
    fi
}

test_connectivity() {
    print_header "Testing SSH Connectivity"
    
    local all_ok=true
    
    print_section "Source Server ($SOURCE_HOST)"
    if ! test_ssh "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$SOURCE_SSH_KEY"; then
        all_ok=false
    fi
    
    print_section "Target Server ($TARGET_HOST)"
    if ! test_ssh "$TARGET_HOST" "$TARGET_ADMIN_USER" "$TARGET_SSH_KEY"; then
        all_ok=false
    fi
    
    print_section "ZDM Server ($ZDM_HOST)"
    if ! test_ssh "$ZDM_HOST" "$ZDM_ADMIN_USER" "$ZDM_SSH_KEY"; then
        all_ok=false
    fi
    
    echo ""
    if [ "$all_ok" = true ]; then
        log_success "All connectivity tests passed!"
        return 0
    else
        log_error "Some connectivity tests failed. Please check SSH configuration."
        return 1
    fi
}

# ===========================================
# DISCOVERY FUNCTIONS
# ===========================================

run_source_discovery() {
    print_header "Source Database Discovery"
    log_info "Host: $SOURCE_HOST"
    log_info "User: $SOURCE_ADMIN_USER"
    log_info "Oracle User: $ORACLE_USER"
    
    local key_path=$(eval echo "$SOURCE_SSH_KEY")
    local script_path="$SCRIPT_DIR/zdm_source_discovery.sh"
    local output_subdir="$OUTPUT_DIR/source"
    
    # Create output directory
    mkdir -p "$output_subdir"
    
    # Check script exists
    if [ ! -f "$script_path" ]; then
        log_error "Source discovery script not found: $script_path"
        RESULTS["source"]="FAILED"
        return 1
    fi
    
    # Check SSH key
    if [ ! -f "$key_path" ]; then
        log_error "SSH key not found: $SOURCE_SSH_KEY"
        RESULTS["source"]="FAILED"
        return 1
    fi
    
    print_section "Running discovery script on source..."
    
    # Copy script to remote and execute with login shell
    # Pass ORACLE_USER environment variable
    if ssh $SSH_OPTS -i "$key_path" "${SOURCE_ADMIN_USER}@${SOURCE_HOST}" \
        "ORACLE_USER='$ORACLE_USER' bash -l -s" < "$script_path"; then
        
        log_success "Discovery script completed on source"
        
        # Collect output files
        print_section "Collecting discovery output files..."
        
        local remote_files=$(ssh $SSH_OPTS -i "$key_path" "${SOURCE_ADMIN_USER}@${SOURCE_HOST}" \
            "ls -1 ./zdm_source_discovery_*.txt ./zdm_source_discovery_*.json 2>/dev/null")
        
        if [ -n "$remote_files" ]; then
            for file in $remote_files; do
                scp $SSH_OPTS -i "$key_path" \
                    "${SOURCE_ADMIN_USER}@${SOURCE_HOST}:$file" \
                    "$output_subdir/" 2>/dev/null && \
                    log_success "Collected: $(basename $file)"
            done
            
            # Clean up remote files
            ssh $SSH_OPTS -i "$key_path" "${SOURCE_ADMIN_USER}@${SOURCE_HOST}" \
                "rm -f ./zdm_source_discovery_*.txt ./zdm_source_discovery_*.json" 2>/dev/null
            
            RESULTS["source"]="SUCCESS"
            log_success "Source discovery completed successfully"
        else
            log_error "No output files found on source"
            RESULTS["source"]="FAILED"
            return 1
        fi
    else
        log_error "Discovery script failed on source"
        RESULTS["source"]="FAILED"
        return 1
    fi
}

run_target_discovery() {
    print_header "Target Database Discovery"
    log_info "Host: $TARGET_HOST"
    log_info "User: $TARGET_ADMIN_USER"
    log_info "Oracle User: $ORACLE_USER"
    
    local key_path=$(eval echo "$TARGET_SSH_KEY")
    local script_path="$SCRIPT_DIR/zdm_target_discovery.sh"
    local output_subdir="$OUTPUT_DIR/target"
    
    # Create output directory
    mkdir -p "$output_subdir"
    
    # Check script exists
    if [ ! -f "$script_path" ]; then
        log_error "Target discovery script not found: $script_path"
        RESULTS["target"]="FAILED"
        return 1
    fi
    
    # Check SSH key
    if [ ! -f "$key_path" ]; then
        log_error "SSH key not found: $TARGET_SSH_KEY"
        RESULTS["target"]="FAILED"
        return 1
    fi
    
    print_section "Running discovery script on target..."
    
    # Copy script to remote and execute with login shell
    if ssh $SSH_OPTS -i "$key_path" "${TARGET_ADMIN_USER}@${TARGET_HOST}" \
        "ORACLE_USER='$ORACLE_USER' bash -l -s" < "$script_path"; then
        
        log_success "Discovery script completed on target"
        
        # Collect output files
        print_section "Collecting discovery output files..."
        
        local remote_files=$(ssh $SSH_OPTS -i "$key_path" "${TARGET_ADMIN_USER}@${TARGET_HOST}" \
            "ls -1 ./zdm_target_discovery_*.txt ./zdm_target_discovery_*.json 2>/dev/null")
        
        if [ -n "$remote_files" ]; then
            for file in $remote_files; do
                scp $SSH_OPTS -i "$key_path" \
                    "${TARGET_ADMIN_USER}@${TARGET_HOST}:$file" \
                    "$output_subdir/" 2>/dev/null && \
                    log_success "Collected: $(basename $file)"
            done
            
            # Clean up remote files
            ssh $SSH_OPTS -i "$key_path" "${TARGET_ADMIN_USER}@${TARGET_HOST}" \
                "rm -f ./zdm_target_discovery_*.txt ./zdm_target_discovery_*.json" 2>/dev/null
            
            RESULTS["target"]="SUCCESS"
            log_success "Target discovery completed successfully"
        else
            log_error "No output files found on target"
            RESULTS["target"]="FAILED"
            return 1
        fi
    else
        log_error "Discovery script failed on target"
        RESULTS["target"]="FAILED"
        return 1
    fi
}

run_server_discovery() {
    print_header "ZDM Server Discovery"
    log_info "Host: $ZDM_HOST"
    log_info "User: $ZDM_ADMIN_USER"
    log_info "ZDM User: $ZDM_USER"
    
    local key_path=$(eval echo "$ZDM_SSH_KEY")
    local script_path="$SCRIPT_DIR/zdm_server_discovery.sh"
    local output_subdir="$OUTPUT_DIR/server"
    
    # Create output directory
    mkdir -p "$output_subdir"
    
    # Check script exists
    if [ ! -f "$script_path" ]; then
        log_error "Server discovery script not found: $script_path"
        RESULTS["server"]="FAILED"
        return 1
    fi
    
    # Check SSH key
    if [ ! -f "$key_path" ]; then
        log_error "SSH key not found: $ZDM_SSH_KEY"
        RESULTS["server"]="FAILED"
        return 1
    fi
    
    print_section "Running discovery script on ZDM server..."
    
    # Copy script to remote and execute with login shell
    if ssh $SSH_OPTS -i "$key_path" "${ZDM_ADMIN_USER}@${ZDM_HOST}" \
        "ZDM_USER='$ZDM_USER' bash -l -s" < "$script_path"; then
        
        log_success "Discovery script completed on ZDM server"
        
        # Collect output files
        print_section "Collecting discovery output files..."
        
        local remote_files=$(ssh $SSH_OPTS -i "$key_path" "${ZDM_ADMIN_USER}@${ZDM_HOST}" \
            "ls -1 ./zdm_server_discovery_*.txt ./zdm_server_discovery_*.json 2>/dev/null")
        
        if [ -n "$remote_files" ]; then
            for file in $remote_files; do
                scp $SSH_OPTS -i "$key_path" \
                    "${ZDM_ADMIN_USER}@${ZDM_HOST}:$file" \
                    "$output_subdir/" 2>/dev/null && \
                    log_success "Collected: $(basename $file)"
            done
            
            # Clean up remote files
            ssh $SSH_OPTS -i "$key_path" "${ZDM_ADMIN_USER}@${ZDM_HOST}" \
                "rm -f ./zdm_server_discovery_*.txt ./zdm_server_discovery_*.json" 2>/dev/null
            
            RESULTS["server"]="SUCCESS"
            log_success "ZDM server discovery completed successfully"
        else
            log_error "No output files found on ZDM server"
            RESULTS["server"]="FAILED"
            return 1
        fi
    else
        log_error "Discovery script failed on ZDM server"
        RESULTS["server"]="FAILED"
        return 1
    fi
}

print_summary() {
    print_header "Discovery Summary"
    
    echo ""
    echo "Results:"
    
    local total=0
    local success=0
    
    for server in source target server; do
        total=$((total + 1))
        if [ "${RESULTS[$server]}" = "SUCCESS" ]; then
            success=$((success + 1))
            echo -e "  ${GREEN}✓${NC} $server: SUCCESS"
        elif [ "${RESULTS[$server]}" = "FAILED" ]; then
            echo -e "  ${RED}✗${NC} $server: FAILED"
        else
            echo -e "  ${YELLOW}○${NC} $server: SKIPPED"
        fi
    done
    
    echo ""
    echo "Output Directory: $OUTPUT_DIR"
    echo ""
    
    if [ -d "$OUTPUT_DIR" ]; then
        echo "Discovery Files:"
        find "$OUTPUT_DIR" -type f -name "*.txt" -o -name "*.json" 2>/dev/null | while read f; do
            echo "  - $(basename $f)"
        done
    fi
    
    echo ""
    if [ "$success" -eq "$total" ]; then
        log_success "All discoveries completed successfully ($success/$total)"
        echo ""
        echo "Next Steps:"
        echo "  1. Review discovery output files in $OUTPUT_DIR"
        echo "  2. Run Step1-Discovery-Questionnaire.prompt.md to analyze results"
        return 0
    elif [ "$success" -gt 0 ]; then
        log_warn "Partial success ($success/$total discoveries completed)"
        echo ""
        echo "Review failed discoveries and re-run if needed."
        return 1
    else
        log_error "All discoveries failed ($success/$total)"
        echo ""
        echo "Check SSH connectivity and server access."
        return 1
    fi
}

# ===========================================
# MAIN
# ===========================================

main() {
    print_header "ZDM Discovery Orchestration"
    echo "Project: PRODDB Migration to Oracle Database@Azure"
    echo "Date: $(date)"
    
    local target="${1:-all}"
    
    case "$target" in
        -h|--help)
            show_help
            exit 0
            ;;
        -c|--config)
            show_config
            exit 0
            ;;
        -t|--test)
            test_connectivity
            exit $?
            ;;
        source)
            run_source_discovery
            print_summary
            ;;
        target)
            run_target_discovery
            print_summary
            ;;
        server)
            run_server_discovery
            print_summary
            ;;
        all)
            # Run all discoveries, continue on failure
            run_source_discovery || true
            run_target_discovery || true
            run_server_discovery || true
            print_summary
            ;;
        *)
            log_error "Unknown target: $target"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
}

# Run main with all arguments
main "$@"
