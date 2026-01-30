#!/bin/bash
#===============================================================================
# ZDM Discovery Orchestration Script
# Project: PRODDB Migration to Oracle Database@Azure
#
# Purpose: Orchestrate discovery across source, target, and ZDM servers.
#          Copy discovery scripts, execute remotely, and collect results.
#
# Usage:
#   ./zdm_orchestrate_discovery.sh              # Run full discovery
#   ./zdm_orchestrate_discovery.sh -t           # Test connectivity only
#   ./zdm_orchestrate_discovery.sh -c           # Show configuration
#   ./zdm_orchestrate_discovery.sh -h           # Show help
#
# Output: Discovery results collected to Artifacts directory
#===============================================================================

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Script directory (where this script is located)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#===============================================================================
# SERVER CONFIGURATION
#===============================================================================

# Server hostnames
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

# Separate SSH key paths for each environment
# (Typically different keys due to separate security domains)
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-$HOME/.ssh/onprem_oracle_key}"
TARGET_SSH_KEY="${TARGET_SSH_KEY:-$HOME/.ssh/oci_opc_key}"
ZDM_SSH_KEY="${ZDM_SSH_KEY:-$HOME/.ssh/azure_key}"

#===============================================================================
# OUTPUT CONFIGURATION
#===============================================================================

# Default output directory - relative to repository root
DEFAULT_OUTPUT_DIR="Artifacts/Phase10-Migration/ZDM/PRODDB/Step0/Discovery"

# Allow override via environment or command line
OUTPUT_DIR="${OUTPUT_DIR:-$DEFAULT_OUTPUT_DIR}"

# Discovery script names
SOURCE_SCRIPT="zdm_source_discovery.sh"
TARGET_SCRIPT="zdm_target_discovery.sh"
ZDM_SCRIPT="zdm_server_discovery.sh"

#===============================================================================
# ENVIRONMENT OVERRIDES (Optional - for non-standard installations)
#===============================================================================

# These can be set if auto-detection fails on remote servers
# SOURCE_REMOTE_ORACLE_HOME=""
# SOURCE_REMOTE_ORACLE_SID=""
# TARGET_REMOTE_ORACLE_HOME=""
# TARGET_REMOTE_ORACLE_SID=""
# ZDM_REMOTE_ZDM_HOME=""
# ZDM_REMOTE_JAVA_HOME=""

#===============================================================================
# STATUS TRACKING
#===============================================================================

declare -A SERVER_STATUS
declare -A SERVER_ERRORS

#===============================================================================
# FUNCTIONS
#===============================================================================

print_header() {
    local title="$1"
    echo -e "\n${BLUE}=================================================================================${NC}"
    echo -e "${CYAN}  $title${NC}"
    echo -e "${BLUE}=================================================================================${NC}"
}

print_section() {
    local title="$1"
    echo -e "\n${GREEN}--- $title ---${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

show_help() {
    cat << EOF
ZDM Discovery Orchestration Script
Project: PRODDB Migration to Oracle Database@Azure

Usage: $(basename "$0") [OPTIONS]

Options:
  -h, --help        Show this help message
  -c, --config      Display current configuration
  -t, --test        Test SSH connectivity only (don't run discovery)
  -o, --output DIR  Set output directory for discovery results
  -s, --source-only Run discovery on source server only
  -d, --target-only Run discovery on target server only
  -z, --zdm-only    Run discovery on ZDM server only

Environment Variables:
  SOURCE_HOST           Source database server hostname
  TARGET_HOST           Target Oracle Database@Azure hostname
  ZDM_HOST              ZDM jumpbox server hostname
  
  SOURCE_ADMIN_USER     SSH admin user for source server (default: oracle)
  TARGET_ADMIN_USER     SSH admin user for target server (default: opc)
  ZDM_ADMIN_USER        SSH admin user for ZDM server (default: azureuser)
  
  ORACLE_USER           Oracle database software owner (default: oracle)
  ZDM_USER              ZDM software owner (default: zdmuser)
  
  SOURCE_SSH_KEY        Path to SSH key for source server
  TARGET_SSH_KEY        Path to SSH key for target server
  ZDM_SSH_KEY           Path to SSH key for ZDM server
  
  OUTPUT_DIR            Output directory for discovery results

Examples:
  # Run full discovery
  ./$(basename "$0")
  
  # Test connectivity first
  ./$(basename "$0") -t
  
  # Run only source discovery
  ./$(basename "$0") -s
  
  # Set custom output directory
  ./$(basename "$0") -o /path/to/output

EOF
}

show_config() {
    print_header "Current Configuration"
    
    echo -e "\n${MAGENTA}Server Hostnames:${NC}"
    echo "  SOURCE_HOST:       $SOURCE_HOST"
    echo "  TARGET_HOST:       $TARGET_HOST"
    echo "  ZDM_HOST:          $ZDM_HOST"
    
    echo -e "\n${MAGENTA}SSH Admin Users:${NC}"
    echo "  SOURCE_ADMIN_USER: $SOURCE_ADMIN_USER"
    echo "  TARGET_ADMIN_USER: $TARGET_ADMIN_USER"
    echo "  ZDM_ADMIN_USER:    $ZDM_ADMIN_USER"
    
    echo -e "\n${MAGENTA}Application Users:${NC}"
    echo "  ORACLE_USER:       $ORACLE_USER"
    echo "  ZDM_USER:          $ZDM_USER"
    
    echo -e "\n${MAGENTA}SSH Keys:${NC}"
    echo "  SOURCE_SSH_KEY:    $SOURCE_SSH_KEY"
    if [ -f "$SOURCE_SSH_KEY" ]; then
        echo -e "                     ${GREEN}[EXISTS]${NC}"
    else
        echo -e "                     ${RED}[NOT FOUND]${NC}"
    fi
    
    echo "  TARGET_SSH_KEY:    $TARGET_SSH_KEY"
    if [ -f "$TARGET_SSH_KEY" ]; then
        echo -e "                     ${GREEN}[EXISTS]${NC}"
    else
        echo -e "                     ${RED}[NOT FOUND]${NC}"
    fi
    
    echo "  ZDM_SSH_KEY:       $ZDM_SSH_KEY"
    if [ -f "$ZDM_SSH_KEY" ]; then
        echo -e "                     ${GREEN}[EXISTS]${NC}"
    else
        echo -e "                     ${RED}[NOT FOUND]${NC}"
    fi
    
    echo -e "\n${MAGENTA}Output:${NC}"
    echo "  OUTPUT_DIR:        $OUTPUT_DIR"
    echo "  SCRIPT_DIR:        $SCRIPT_DIR"
    
    echo -e "\n${MAGENTA}Discovery Scripts:${NC}"
    for script in "$SOURCE_SCRIPT" "$TARGET_SCRIPT" "$ZDM_SCRIPT"; do
        if [ -f "$SCRIPT_DIR/$script" ]; then
            echo -e "  $script: ${GREEN}[EXISTS]${NC}"
        else
            echo -e "  $script: ${RED}[NOT FOUND]${NC}"
        fi
    done
    
    echo ""
}

validate_prerequisites() {
    print_section "Validating Prerequisites"
    
    local errors=0
    
    # Check SSH keys exist
    for key_var in SOURCE_SSH_KEY TARGET_SSH_KEY ZDM_SSH_KEY; do
        local key_path="${!key_var}"
        if [ ! -f "$key_path" ]; then
            print_error "SSH key not found: $key_var=$key_path"
            ((errors++))
        else
            print_success "SSH key exists: $key_var"
        fi
    done
    
    # Check discovery scripts exist
    for script in "$SOURCE_SCRIPT" "$TARGET_SCRIPT" "$ZDM_SCRIPT"; do
        if [ ! -f "$SCRIPT_DIR/$script" ]; then
            print_error "Discovery script not found: $SCRIPT_DIR/$script"
            ((errors++))
        else
            print_success "Discovery script exists: $script"
        fi
    done
    
    # Check SSH command is available
    if ! command -v ssh >/dev/null 2>&1; then
        print_error "SSH command not found"
        ((errors++))
    else
        print_success "SSH command available"
    fi
    
    # Check SCP command is available
    if ! command -v scp >/dev/null 2>&1; then
        print_error "SCP command not found"
        ((errors++))
    else
        print_success "SCP command available"
    fi
    
    if [ $errors -gt 0 ]; then
        print_error "Prerequisites check failed with $errors error(s)"
        return 1
    fi
    
    print_success "All prerequisites validated"
    return 0
}

test_ssh_connectivity() {
    local host="$1"
    local user="$2"
    local key="$3"
    local name="$4"
    
    print_info "Testing SSH connectivity to $name ($user@$host)..."
    
    if ssh -i "$key" -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
       "$user@$host" "echo 'SSH connection successful'" 2>/dev/null; then
        print_success "SSH connection to $name successful"
        return 0
    else
        print_error "SSH connection to $name failed"
        return 1
    fi
}

test_all_connectivity() {
    print_section "Testing SSH Connectivity"
    
    local success=0
    local failed=0
    
    if test_ssh_connectivity "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$SOURCE_SSH_KEY" "Source Database"; then
        ((success++))
        SERVER_STATUS["source"]="reachable"
    else
        ((failed++))
        SERVER_STATUS["source"]="unreachable"
        SERVER_ERRORS["source"]="SSH connection failed"
    fi
    
    if test_ssh_connectivity "$TARGET_HOST" "$TARGET_ADMIN_USER" "$TARGET_SSH_KEY" "Target Database"; then
        ((success++))
        SERVER_STATUS["target"]="reachable"
    else
        ((failed++))
        SERVER_STATUS["target"]="unreachable"
        SERVER_ERRORS["target"]="SSH connection failed"
    fi
    
    if test_ssh_connectivity "$ZDM_HOST" "$ZDM_ADMIN_USER" "$ZDM_SSH_KEY" "ZDM Server"; then
        ((success++))
        SERVER_STATUS["zdm"]="reachable"
    else
        ((failed++))
        SERVER_STATUS["zdm"]="unreachable"
        SERVER_ERRORS["zdm"]="SSH connection failed"
    fi
    
    echo ""
    print_info "Connectivity Summary: $success successful, $failed failed"
    
    if [ $failed -gt 0 ]; then
        return 1
    fi
    return 0
}

run_remote_discovery() {
    local host="$1"
    local user="$2"
    local key="$3"
    local script="$4"
    local name="$5"
    local server_type="$6"  # source, target, or zdm
    
    print_section "Running Discovery on $name"
    print_info "Host: $host"
    print_info "User: $user"
    print_info "Script: $script"
    
    # Create temporary directory on remote server
    local remote_tmp_dir="/tmp/zdm_discovery_$$"
    
    # Build environment variables to pass
    local env_vars="ORACLE_USER=$ORACLE_USER ZDM_USER=$ZDM_USER"
    
    # Add overrides if specified
    if [ "$server_type" = "source" ]; then
        [ -n "${SOURCE_REMOTE_ORACLE_HOME:-}" ] && env_vars="$env_vars ORACLE_HOME_OVERRIDE=$SOURCE_REMOTE_ORACLE_HOME"
        [ -n "${SOURCE_REMOTE_ORACLE_SID:-}" ] && env_vars="$env_vars ORACLE_SID_OVERRIDE=$SOURCE_REMOTE_ORACLE_SID"
    elif [ "$server_type" = "target" ]; then
        [ -n "${TARGET_REMOTE_ORACLE_HOME:-}" ] && env_vars="$env_vars ORACLE_HOME_OVERRIDE=$TARGET_REMOTE_ORACLE_HOME"
        [ -n "${TARGET_REMOTE_ORACLE_SID:-}" ] && env_vars="$env_vars ORACLE_SID_OVERRIDE=$TARGET_REMOTE_ORACLE_SID"
    elif [ "$server_type" = "zdm" ]; then
        [ -n "${ZDM_REMOTE_ZDM_HOME:-}" ] && env_vars="$env_vars ZDM_HOME_OVERRIDE=$ZDM_REMOTE_ZDM_HOME"
        [ -n "${ZDM_REMOTE_JAVA_HOME:-}" ] && env_vars="$env_vars JAVA_HOME_OVERRIDE=$ZDM_REMOTE_JAVA_HOME"
    fi
    
    # Step 1: Create temp directory and copy script
    print_info "Copying discovery script to remote server..."
    if ! ssh -i "$key" -o ConnectTimeout=30 "$user@$host" "mkdir -p $remote_tmp_dir" 2>/dev/null; then
        print_error "Failed to create temp directory on $name"
        SERVER_STATUS["$server_type"]="failed"
        SERVER_ERRORS["$server_type"]="Failed to create temp directory"
        return 1
    fi
    
    if ! scp -i "$key" -o ConnectTimeout=30 "$SCRIPT_DIR/$script" "$user@$host:$remote_tmp_dir/" 2>/dev/null; then
        print_error "Failed to copy script to $name"
        SERVER_STATUS["$server_type"]="failed"
        SERVER_ERRORS["$server_type"]="Failed to copy discovery script"
        return 1
    fi
    
    # Step 2: Execute discovery script with login shell
    print_info "Executing discovery script..."
    if ! ssh -i "$key" -o ConnectTimeout=300 "$user@$host" \
         "cd $remote_tmp_dir && chmod +x $script && bash -l -c '$env_vars ./$script'" 2>&1; then
        print_warning "Discovery script returned non-zero exit code on $name"
        # Continue anyway - partial results may still be useful
    fi
    
    # Step 3: Collect results
    print_info "Collecting discovery results..."
    local local_output_dir="$OUTPUT_DIR/$server_type"
    mkdir -p "$local_output_dir"
    
    # Copy all output files
    if scp -i "$key" -o ConnectTimeout=60 "$user@$host:$remote_tmp_dir/zdm_*_discovery_*.txt" "$local_output_dir/" 2>/dev/null; then
        print_success "Text report collected"
    else
        print_warning "No text report found"
    fi
    
    if scp -i "$key" -o ConnectTimeout=60 "$user@$host:$remote_tmp_dir/zdm_*_discovery_*.json" "$local_output_dir/" 2>/dev/null; then
        print_success "JSON summary collected"
    else
        print_warning "No JSON summary found"
    fi
    
    # Step 4: Cleanup remote temp directory
    print_info "Cleaning up remote temp files..."
    ssh -i "$key" -o ConnectTimeout=30 "$user@$host" "rm -rf $remote_tmp_dir" 2>/dev/null || true
    
    # Check if we got any results
    local result_count
    result_count=$(ls -1 "$local_output_dir"/*.txt 2>/dev/null | wc -l)
    
    if [ "$result_count" -gt 0 ]; then
        print_success "Discovery completed for $name"
        SERVER_STATUS["$server_type"]="success"
        return 0
    else
        print_warning "Discovery completed but no results collected for $name"
        SERVER_STATUS["$server_type"]="no_results"
        SERVER_ERRORS["$server_type"]="No output files collected"
        return 1
    fi
}

print_summary() {
    print_header "Discovery Summary"
    
    echo -e "\n${MAGENTA}Server Discovery Status:${NC}"
    
    for server in source target zdm; do
        local status="${SERVER_STATUS[$server]:-not_run}"
        local error="${SERVER_ERRORS[$server]:-}"
        
        case "$status" in
            success)
                echo -e "  ${server^} Server: ${GREEN}SUCCESS${NC}"
                ;;
            failed)
                echo -e "  ${server^} Server: ${RED}FAILED${NC} - $error"
                ;;
            unreachable)
                echo -e "  ${server^} Server: ${RED}UNREACHABLE${NC} - $error"
                ;;
            no_results)
                echo -e "  ${server^} Server: ${YELLOW}NO RESULTS${NC} - $error"
                ;;
            *)
                echo -e "  ${server^} Server: ${YELLOW}NOT RUN${NC}"
                ;;
        esac
    done
    
    echo -e "\n${MAGENTA}Output Location:${NC}"
    echo "  $OUTPUT_DIR/"
    
    if [ -d "$OUTPUT_DIR" ]; then
        echo ""
        echo "Collected files:"
        find "$OUTPUT_DIR" -type f -name "*.txt" -o -name "*.json" 2>/dev/null | while read -r file; do
            echo "  - ${file#$OUTPUT_DIR/}"
        done
    fi
    
    echo ""
    
    # Determine overall status
    local success_count=0
    local total_count=0
    
    for server in source target zdm; do
        if [ -n "${SERVER_STATUS[$server]:-}" ]; then
            ((total_count++))
            [ "${SERVER_STATUS[$server]}" = "success" ] && ((success_count++))
        fi
    done
    
    if [ $success_count -eq $total_count ] && [ $total_count -gt 0 ]; then
        print_success "All discovery tasks completed successfully!"
        echo ""
        echo "Next Steps:"
        echo "  1. Review discovery reports in $OUTPUT_DIR/"
        echo "  2. Proceed to Step 1: Complete the Discovery Questionnaire"
        return 0
    elif [ $success_count -gt 0 ]; then
        print_warning "Partial discovery completed ($success_count of $total_count servers)"
        echo ""
        echo "Review successful results and retry failed servers if needed."
        return 1
    else
        print_error "Discovery failed for all servers"
        return 2
    fi
}

#===============================================================================
# MAIN EXECUTION
#===============================================================================

main() {
    # Parse command line arguments
    local run_source=true
    local run_target=true
    local run_zdm=true
    local test_only=false
    local show_config_only=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
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
            -s|--source-only)
                run_target=false
                run_zdm=false
                shift
                ;;
            -d|--target-only)
                run_source=false
                run_zdm=false
                shift
                ;;
            -z|--zdm-only)
                run_source=false
                run_target=false
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Show configuration if requested
    if [ "$show_config_only" = true ]; then
        show_config
        exit 0
    fi
    
    print_header "ZDM Discovery Orchestration"
    echo "Project: PRODDB Migration to Oracle Database@Azure"
    echo "Timestamp: $(date)"
    echo ""
    
    # Show current configuration summary
    echo -e "${MAGENTA}Servers:${NC}"
    echo "  Source: $SOURCE_ADMIN_USER@$SOURCE_HOST"
    echo "  Target: $TARGET_ADMIN_USER@$TARGET_HOST"
    echo "  ZDM:    $ZDM_ADMIN_USER@$ZDM_HOST"
    echo ""
    
    # Validate prerequisites
    if ! validate_prerequisites; then
        print_error "Prerequisite validation failed. Run with -c to see configuration."
        exit 1
    fi
    
    # Test connectivity
    test_all_connectivity
    local connectivity_result=$?
    
    if [ "$test_only" = true ]; then
        if [ $connectivity_result -eq 0 ]; then
            print_success "Connectivity test completed successfully"
            exit 0
        else
            print_error "Connectivity test failed"
            exit 1
        fi
    fi
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR/source"
    mkdir -p "$OUTPUT_DIR/target"
    mkdir -p "$OUTPUT_DIR/server"
    
    # Run discovery (continue on failures)
    local discovery_errors=0
    
    if [ "$run_source" = true ] && [ "${SERVER_STATUS[source]}" = "reachable" ]; then
        run_remote_discovery "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$SOURCE_SSH_KEY" \
                            "$SOURCE_SCRIPT" "Source Database" "source" || ((discovery_errors++))
    elif [ "$run_source" = true ]; then
        print_warning "Skipping source discovery (server unreachable)"
    fi
    
    if [ "$run_target" = true ] && [ "${SERVER_STATUS[target]}" = "reachable" ]; then
        run_remote_discovery "$TARGET_HOST" "$TARGET_ADMIN_USER" "$TARGET_SSH_KEY" \
                            "$TARGET_SCRIPT" "Target Database" "target" || ((discovery_errors++))
    elif [ "$run_target" = true ]; then
        print_warning "Skipping target discovery (server unreachable)"
    fi
    
    if [ "$run_zdm" = true ] && [ "${SERVER_STATUS[zdm]}" = "reachable" ]; then
        run_remote_discovery "$ZDM_HOST" "$ZDM_ADMIN_USER" "$ZDM_SSH_KEY" \
                            "$ZDM_SCRIPT" "ZDM Server" "server" || ((discovery_errors++))
    elif [ "$run_zdm" = true ]; then
        print_warning "Skipping ZDM discovery (server unreachable)"
    fi
    
    # Print summary
    print_summary
    exit_code=$?
    
    exit $exit_code
}

# Run main function
main "$@"
