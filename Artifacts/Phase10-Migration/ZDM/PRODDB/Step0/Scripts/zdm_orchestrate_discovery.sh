#!/bin/bash
#
# ZDM Discovery Orchestration Script
# Project: PRODDB Migration to Oracle Database@Azure
#
# Purpose: Orchestrate discovery across source, target, and ZDM servers
#          by copying and executing discovery scripts remotely
#
# Usage: 
#   ./zdm_orchestrate_discovery.sh [options]
#
# Options:
#   -h, --help     Show this help message
#   -c, --config   Display current configuration
#   -t, --test     Test connectivity only (don't run discovery)
#

# ===========================================
# STRICT MODE (selective)
# ===========================================
# Note: We do NOT use 'set -e' globally to allow partial success

# ===========================================
# SCRIPT LOCATION AND PATHS
# ===========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Calculate repository root (6 levels up from Scripts directory)
# Scripts → Step0 → PRODDB → ZDM → Phase10-Migration → Artifacts → RepoRoot
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../../.." && pwd)"

# ===========================================
# SERVER CONFIGURATION
# ===========================================

# Server hostnames
SOURCE_HOST="${SOURCE_HOST:-proddb01.corp.example.com}"
TARGET_HOST="${TARGET_HOST:-proddb-oda.eastus.azure.example.com}"
ZDM_HOST="${ZDM_HOST:-zdm-jumpbox.corp.example.com}"

# ===========================================
# USER CONFIGURATION
# ===========================================

# SSH/Admin users for each server (can be different for each environment)
# These are Linux admin users with sudo privileges
SOURCE_ADMIN_USER="${SOURCE_ADMIN_USER:-oracle}"
TARGET_ADMIN_USER="${TARGET_ADMIN_USER:-opc}"
ZDM_ADMIN_USER="${ZDM_ADMIN_USER:-azureuser}"

# Oracle database software owner (for running SQL commands)
ORACLE_USER="${ORACLE_USER:-oracle}"

# ZDM software owner (for running ZDM CLI commands)
ZDM_USER="${ZDM_USER:-zdmuser}"

# ===========================================
# SSH KEY CONFIGURATION
# ===========================================

# Separate SSH keys for each security domain
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-$HOME/.ssh/onprem_oracle_key}"
TARGET_SSH_KEY="${TARGET_SSH_KEY:-$HOME/.ssh/oci_opc_key}"
ZDM_SSH_KEY="${ZDM_SSH_KEY:-$HOME/.ssh/azure_key}"

# SSH options
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=30 -o BatchMode=yes"

# ===========================================
# OUTPUT CONFIGURATION
# ===========================================

# Default output directory relative to repository root
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/Artifacts/Phase10-Migration/ZDM/PRODDB/Step0/Discovery}"

# ===========================================
# OPTIONAL ENVIRONMENT OVERRIDES
# ===========================================

# These can be set if auto-detection fails on remote servers
# SOURCE_REMOTE_ORACLE_HOME=""
# SOURCE_REMOTE_ORACLE_SID=""
# TARGET_REMOTE_ORACLE_HOME=""
# TARGET_REMOTE_ORACLE_SID=""
# ZDM_REMOTE_ZDM_HOME=""
# ZDM_REMOTE_JAVA_HOME=""

# ===========================================
# COLOR OUTPUT FUNCTIONS
# ===========================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "\n${CYAN}========================================${NC}"; echo -e "${CYAN}$1${NC}"; echo -e "${CYAN}========================================${NC}"; }

# ===========================================
# HELP AND USAGE
# ===========================================

show_help() {
    cat << EOF
ZDM Discovery Orchestration Script
Project: PRODDB Migration to Oracle Database@Azure

Usage: $0 [options]

Options:
  -h, --help     Show this help message
  -c, --config   Display current configuration
  -t, --test     Test SSH connectivity only (don't run discovery)

Environment Variables:
  SERVER HOSTNAMES:
    SOURCE_HOST           Source database server (default: proddb01.corp.example.com)
    TARGET_HOST           Target Oracle Database@Azure server (default: proddb-oda.eastus.azure.example.com)
    ZDM_HOST              ZDM jumpbox server (default: zdm-jumpbox.corp.example.com)

  SSH/ADMIN USERS:
    SOURCE_ADMIN_USER     Admin user for SSH to source (default: oracle)
    TARGET_ADMIN_USER     Admin user for SSH to target (default: opc)
    ZDM_ADMIN_USER        Admin user for SSH to ZDM server (default: azureuser)

  APPLICATION USERS:
    ORACLE_USER           Oracle database software owner (default: oracle)
    ZDM_USER              ZDM software owner (default: zdmuser)

  SSH KEYS:
    SOURCE_SSH_KEY        SSH key for source server (default: ~/.ssh/onprem_oracle_key)
    TARGET_SSH_KEY        SSH key for target server (default: ~/.ssh/oci_opc_key)
    ZDM_SSH_KEY           SSH key for ZDM server (default: ~/.ssh/azure_key)

  OUTPUT:
    OUTPUT_DIR            Discovery output directory

Example:
  # Run with default configuration
  ./zdm_orchestrate_discovery.sh

  # Run with custom source host
  SOURCE_HOST=mydb.example.com ./zdm_orchestrate_discovery.sh

  # Test connectivity only
  ./zdm_orchestrate_discovery.sh --test

EOF
}

show_config() {
    log_section "Current Configuration"
    echo ""
    echo "SERVER HOSTNAMES:"
    echo "  Source:     $SOURCE_HOST"
    echo "  Target:     $TARGET_HOST"
    echo "  ZDM:        $ZDM_HOST"
    echo ""
    echo "SSH/ADMIN USERS:"
    echo "  Source:     $SOURCE_ADMIN_USER"
    echo "  Target:     $TARGET_ADMIN_USER"
    echo "  ZDM:        $ZDM_ADMIN_USER"
    echo ""
    echo "APPLICATION USERS:"
    echo "  Oracle:     $ORACLE_USER"
    echo "  ZDM:        $ZDM_USER"
    echo ""
    echo "SSH KEYS:"
    echo "  Source:     $SOURCE_SSH_KEY"
    echo "  Target:     $TARGET_SSH_KEY"
    echo "  ZDM:        $ZDM_SSH_KEY"
    echo ""
    echo "OUTPUT:"
    echo "  Directory:  $OUTPUT_DIR"
    echo ""
    echo "PATHS:"
    echo "  Script Dir: $SCRIPT_DIR"
    echo "  Repo Root:  $REPO_ROOT"
    echo ""
}

# ===========================================
# VALIDATION FUNCTIONS
# ===========================================

validate_config() {
    log_section "Validating Configuration"
    local errors=0
    
    # Check SSH keys exist
    for key_var in SOURCE_SSH_KEY TARGET_SSH_KEY ZDM_SSH_KEY; do
        local key_path="${!key_var}"
        key_path=$(eval echo "$key_path")
        if [ ! -f "$key_path" ]; then
            log_warn "SSH key not found: $key_var=$key_path"
            ((errors++))
        else
            log_info "SSH key exists: $key_var"
        fi
    done
    
    # Check discovery scripts exist
    for script in zdm_source_discovery.sh zdm_target_discovery.sh zdm_server_discovery.sh; do
        if [ ! -f "$SCRIPT_DIR/$script" ]; then
            log_error "Discovery script not found: $SCRIPT_DIR/$script"
            ((errors++))
        else
            log_info "Discovery script exists: $script"
        fi
    done
    
    if [ $errors -gt 0 ]; then
        log_warn "Configuration validation completed with $errors warning(s)"
    else
        log_info "Configuration validation passed"
    fi
    
    return 0  # Always return success to allow partial runs
}

# ===========================================
# SSH CONNECTIVITY FUNCTIONS
# ===========================================

test_ssh_connection() {
    local host="$1"
    local user="$2"
    local key_path="$3"
    local name="$4"
    
    key_path=$(eval echo "$key_path")
    
    log_info "Testing SSH connection to $name ($user@$host)..."
    
    if [ ! -f "$key_path" ]; then
        log_error "SSH key not found: $key_path"
        return 1
    fi
    
    if ssh $SSH_OPTS -i "$key_path" "${user}@${host}" "echo 'SSH connection successful'" 2>/dev/null; then
        log_info "$name: SSH connection successful"
        return 0
    else
        log_error "$name: SSH connection failed"
        return 1
    fi
}

test_all_connections() {
    log_section "Testing SSH Connectivity"
    local success=0
    local failed=0
    
    if test_ssh_connection "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$SOURCE_SSH_KEY" "Source"; then
        ((success++))
    else
        ((failed++))
    fi
    
    if test_ssh_connection "$TARGET_HOST" "$TARGET_ADMIN_USER" "$TARGET_SSH_KEY" "Target"; then
        ((success++))
    else
        ((failed++))
    fi
    
    if test_ssh_connection "$ZDM_HOST" "$ZDM_ADMIN_USER" "$ZDM_SSH_KEY" "ZDM"; then
        ((success++))
    else
        ((failed++))
    fi
    
    echo ""
    log_info "Connectivity Summary: $success succeeded, $failed failed"
    
    return $failed
}

# ===========================================
# DISCOVERY EXECUTION FUNCTIONS
# ===========================================

run_remote_discovery() {
    local host="$1"
    local user="$2"
    local key_path="$3"
    local script_name="$4"
    local output_subdir="$5"
    local server_type="$6"
    local extra_env="${7:-}"
    
    key_path=$(eval echo "$key_path")
    local script_path="$SCRIPT_DIR/$script_name"
    local output_path="$OUTPUT_DIR/$output_subdir"
    
    log_section "Running Discovery: $server_type"
    log_info "Host: $host"
    log_info "User: $user"
    log_info "Script: $script_name"
    
    # Check prerequisites
    if [ ! -f "$key_path" ]; then
        log_error "SSH key not found: $key_path"
        return 1
    fi
    
    if [ ! -f "$script_path" ]; then
        log_error "Script not found: $script_path"
        return 1
    fi
    
    # Create output directory
    mkdir -p "$output_path"
    
    # Build environment variables to pass
    local env_vars="ORACLE_USER='$ORACLE_USER' ZDM_USER='$ZDM_USER'"
    if [ -n "$extra_env" ]; then
        env_vars="$env_vars $extra_env"
    fi
    
    # Add optional overrides if set
    if [ -n "${SOURCE_REMOTE_ORACLE_HOME:-}" ] && [ "$server_type" = "source" ]; then
        env_vars="$env_vars ORACLE_HOME_OVERRIDE='$SOURCE_REMOTE_ORACLE_HOME'"
    fi
    if [ -n "${SOURCE_REMOTE_ORACLE_SID:-}" ] && [ "$server_type" = "source" ]; then
        env_vars="$env_vars ORACLE_SID_OVERRIDE='$SOURCE_REMOTE_ORACLE_SID'"
    fi
    if [ -n "${TARGET_REMOTE_ORACLE_HOME:-}" ] && [ "$server_type" = "target" ]; then
        env_vars="$env_vars ORACLE_HOME_OVERRIDE='$TARGET_REMOTE_ORACLE_HOME'"
    fi
    if [ -n "${TARGET_REMOTE_ORACLE_SID:-}" ] && [ "$server_type" = "target" ]; then
        env_vars="$env_vars ORACLE_SID_OVERRIDE='$TARGET_REMOTE_ORACLE_SID'"
    fi
    if [ -n "${ZDM_REMOTE_ZDM_HOME:-}" ] && [ "$server_type" = "server" ]; then
        env_vars="$env_vars ZDM_HOME_OVERRIDE='$ZDM_REMOTE_ZDM_HOME'"
    fi
    if [ -n "${ZDM_REMOTE_JAVA_HOME:-}" ] && [ "$server_type" = "server" ]; then
        env_vars="$env_vars JAVA_HOME_OVERRIDE='$ZDM_REMOTE_JAVA_HOME'"
    fi
    
    # Execute script remotely via stdin (using login shell for proper environment)
    log_info "Executing discovery script on $host..."
    if ssh $SSH_OPTS -i "$key_path" "${user}@${host}" "$env_vars bash -l -s" < "$script_path"; then
        log_info "Discovery script completed successfully"
    else
        log_warn "Discovery script completed with warnings or errors"
    fi
    
    # Collect output files
    log_info "Collecting discovery output files..."
    
    # Find and copy the most recent discovery files
    local remote_files=$(ssh $SSH_OPTS -i "$key_path" "${user}@${host}" "ls -t ./zdm_*_discovery_*.txt ./zdm_*_discovery_*.json 2>/dev/null | head -2")
    
    if [ -n "$remote_files" ]; then
        for file in $remote_files; do
            local filename=$(basename "$file")
            log_info "Copying: $filename"
            scp $SSH_OPTS -i "$key_path" "${user}@${host}:$file" "$output_path/" 2>/dev/null
            
            # Clean up remote file
            ssh $SSH_OPTS -i "$key_path" "${user}@${host}" "rm -f '$file'" 2>/dev/null
        done
        log_info "Discovery files saved to: $output_path"
        return 0
    else
        log_warn "No discovery output files found on remote host"
        return 1
    fi
}

# ===========================================
# MAIN ORCHESTRATION
# ===========================================

run_discovery() {
    local results=()
    local success_count=0
    local fail_count=0
    
    log_section "Starting ZDM Discovery Orchestration"
    log_info "Project: PRODDB Migration to Oracle Database@Azure"
    log_info "Timestamp: $(date)"
    
    # Create output directories
    mkdir -p "$OUTPUT_DIR/source"
    mkdir -p "$OUTPUT_DIR/target"
    mkdir -p "$OUTPUT_DIR/server"
    
    # Run source discovery
    if run_remote_discovery "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$SOURCE_SSH_KEY" \
        "zdm_source_discovery.sh" "source" "source"; then
        results+=("Source: SUCCESS")
        ((success_count++))
    else
        results+=("Source: FAILED")
        ((fail_count++))
    fi
    
    # Run target discovery
    if run_remote_discovery "$TARGET_HOST" "$TARGET_ADMIN_USER" "$TARGET_SSH_KEY" \
        "zdm_target_discovery.sh" "target" "target"; then
        results+=("Target: SUCCESS")
        ((success_count++))
    else
        results+=("Target: FAILED")
        ((fail_count++))
    fi
    
    # Run ZDM server discovery (pass SOURCE_HOST and TARGET_HOST for connectivity tests)
    local zdm_extra_env="SOURCE_HOST='$SOURCE_HOST' TARGET_HOST='$TARGET_HOST'"
    if run_remote_discovery "$ZDM_HOST" "$ZDM_ADMIN_USER" "$ZDM_SSH_KEY" \
        "zdm_server_discovery.sh" "server" "server" "$zdm_extra_env"; then
        results+=("ZDM Server: SUCCESS")
        ((success_count++))
    else
        results+=("ZDM Server: FAILED")
        ((fail_count++))
    fi
    
    # Summary
    log_section "Discovery Summary"
    echo ""
    for result in "${results[@]}"; do
        if [[ "$result" == *"SUCCESS"* ]]; then
            echo -e "  ${GREEN}✓${NC} $result"
        else
            echo -e "  ${RED}✗${NC} $result"
        fi
    done
    echo ""
    log_info "Total: $success_count succeeded, $fail_count failed"
    log_info "Output directory: $OUTPUT_DIR"
    echo ""
    
    # List generated files
    log_info "Generated files:"
    find "$OUTPUT_DIR" -type f -name "*.txt" -o -name "*.json" 2>/dev/null | while read -r file; do
        echo "  $file"
    done
    
    # Next steps
    echo ""
    log_section "Next Steps"
    echo ""
    echo "1. Review the discovery reports in: $OUTPUT_DIR"
    echo "2. Proceed to Step 1: Discovery Questionnaire"
    echo "   Use the discovery data to complete the full questionnaire"
    echo "3. Reference prompt: @Step1-Discovery-Questionnaire.prompt.md"
    echo ""
    
    if [ $fail_count -eq 0 ]; then
        return 0
    elif [ $success_count -gt 0 ]; then
        log_warn "Partial success: Some discoveries failed but results are available"
        return 0
    else
        return 1
    fi
}

# ===========================================
# MAIN ENTRY POINT
# ===========================================

main() {
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
            validate_config
            test_all_connections
            exit $?
            ;;
        "")
            # Default: run full discovery
            validate_config
            run_discovery
            exit $?
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
