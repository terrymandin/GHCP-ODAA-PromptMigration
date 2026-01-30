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

# Calculate repository root from script location
# Script is at: Artifacts/Phase10-Migration/ZDM/PRODDB/Step0/Scripts/
# Repository root is 6 levels up
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"

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

# Default output directory - absolute path based on repository root
DEFAULT_OUTPUT_DIR="${REPO_ROOT}/Artifacts/Phase10-Migration/ZDM/PRODDB/Step0/Discovery"

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
    echo "  REPO_ROOT:         $REPO_ROOT"
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
            print_warning "SSH key not found: $key_var=$key_path (will skip this server if key is required)"
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
    
    # Check if key exists first
    if [ ! -f "$key" ]; then
        print_warning "SSH key not found: $key - skipping $name"
        return 2
    fi
    
    if ssh -i "$key" -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
       "$user@$host" "echo 'SSH connection successful'" 2>/dev/null; then
        print_success "SSH connection to $name successful"
        return 0
    else
        print_error "SSH connection to $name failed"
        return 1
    fi
}

run_remote_discovery() {
    local host="$1"
    local user="$2"
    local key="$3"
    local script="$4"
    local server_type="$5"
    local env_vars="$6"
    
    print_section "Running Discovery on $server_type: $host"
    
    # Check if key exists first
    if [ ! -f "$key" ]; then
        print_error "SSH key not found: $key"
        SERVER_STATUS["$server_type"]="FAILED"
        SERVER_ERRORS["$server_type"]="SSH key not found"
        return 1
    fi
    
    # Create remote temp directory
    local remote_tmp_dir="/tmp/zdm_discovery_$$"
    
    # Copy script to remote server
    print_info "Copying discovery script to $host..."
    if ! scp -i "$key" -o ConnectTimeout=30 "$SCRIPT_DIR/$script" "$user@$host:$remote_tmp_dir/" 2>/dev/null; then
        # Try creating directory first
        ssh -i "$key" -o ConnectTimeout=30 "$user@$host" "mkdir -p $remote_tmp_dir" 2>/dev/null
        if ! scp -i "$key" -o ConnectTimeout=30 "$SCRIPT_DIR/$script" "$user@$host:$remote_tmp_dir/" 2>/dev/null; then
            print_error "Failed to copy script to $host"
            SERVER_STATUS["$server_type"]="FAILED"
            SERVER_ERRORS["$server_type"]="Failed to copy script"
            return 1
        fi
    fi
    
    # Execute discovery script remotely with login shell
    print_info "Executing discovery on $host..."
    local remote_cmd="cd $remote_tmp_dir && chmod +x $script && $env_vars ./$script"
    
    if ssh -i "$key" -o ConnectTimeout=300 "$user@$host" "bash -l -c '$remote_cmd'" 2>&1; then
        print_success "Discovery completed on $host"
    else
        print_warning "Discovery on $host may have had errors (continuing...)"
    fi
    
    # Collect results
    collect_results "$host" "$user" "$key" "$remote_tmp_dir" "$server_type"
    
    # Cleanup remote temp directory
    ssh -i "$key" -o ConnectTimeout=30 "$user@$host" "rm -rf $remote_tmp_dir" 2>/dev/null
    
    return 0
}

collect_results() {
    local host="$1"
    local user="$2"
    local key="$3"
    local remote_tmp_dir="$4"
    local server_type="$5"
    
    print_info "Collecting results from $host..."
    
    # Create local output directory
    local local_output_dir="$OUTPUT_DIR/$server_type"
    mkdir -p "$local_output_dir"
    
    # Copy result files
    if scp -i "$key" -o ConnectTimeout=60 "$user@$host:$remote_tmp_dir/zdm_*_discovery_*.txt" "$local_output_dir/" 2>/dev/null; then
        print_success "Text report collected"
    else
        print_warning "No text report found"
    fi
    
    if scp -i "$key" -o ConnectTimeout=60 "$user@$host:$remote_tmp_dir/zdm_*_discovery_*.json" "$local_output_dir/" 2>/dev/null; then
        print_success "JSON report collected"
    else
        print_warning "No JSON report found"
    fi
    
    # Check if we got any results
    local result_count=$(ls -1 "$local_output_dir"/*.txt 2>/dev/null | wc -l)
    if [ "$result_count" -gt 0 ]; then
        SERVER_STATUS["$server_type"]="SUCCESS"
        print_success "Discovery results saved to $local_output_dir"
    else
        SERVER_STATUS["$server_type"]="PARTIAL"
        SERVER_ERRORS["$server_type"]="No output files collected"
        print_warning "No discovery output files were collected"
    fi
}

print_summary() {
    print_header "Discovery Summary"
    
    echo -e "\n${MAGENTA}Server Status:${NC}"
    for server in "source" "target" "server"; do
        local status="${SERVER_STATUS[$server]:-NOT RUN}"
        local error="${SERVER_ERRORS[$server]:-}"
        
        case "$status" in
            "SUCCESS")
                echo -e "  $server: ${GREEN}$status${NC}"
                ;;
            "PARTIAL")
                echo -e "  $server: ${YELLOW}$status${NC} - $error"
                ;;
            "FAILED")
                echo -e "  $server: ${RED}$status${NC} - $error"
                ;;
            *)
                echo -e "  $server: ${CYAN}$status${NC}"
                ;;
        esac
    done
    
    echo -e "\n${MAGENTA}Output Location:${NC}"
    echo "  $OUTPUT_DIR/"
    
    if [ -d "$OUTPUT_DIR" ]; then
        echo -e "\n${MAGENTA}Collected Files:${NC}"
        find "$OUTPUT_DIR" -type f \( -name "*.txt" -o -name "*.json" \) 2>/dev/null | while read -r file; do
            echo "  - ${file#$OUTPUT_DIR/}"
        done
    fi
    
    # Count successes
    local success_count=0
    local total_count=0
    for server in "source" "target" "server"; do
        ((total_count++))
        if [ "${SERVER_STATUS[$server]:-}" = "SUCCESS" ]; then
            ((success_count++))
        fi
    done
    
    echo ""
    if [ $success_count -eq $total_count ]; then
        echo -e "${GREEN}All discovery tasks completed successfully!${NC}"
    elif [ $success_count -gt 0 ]; then
        echo -e "${YELLOW}Discovery completed with $success_count out of $total_count servers successful.${NC}"
    else
        echo -e "${RED}Discovery failed on all servers.${NC}"
    fi
    
    echo -e "\n${MAGENTA}Next Steps:${NC}"
    echo "  1. Review discovery reports in $OUTPUT_DIR/"
    echo "  2. Proceed to Step 1: Discovery Questionnaire"
    echo "  3. Complete the questionnaire with business decisions"
}

#===============================================================================
# MAIN EXECUTION
#===============================================================================

# Parse command line arguments
RUN_SOURCE=true
RUN_TARGET=true
RUN_ZDM=true
TEST_ONLY=false

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
            TEST_ONLY=true
            shift
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -s|--source-only)
            RUN_TARGET=false
            RUN_ZDM=false
            shift
            ;;
        -d|--target-only)
            RUN_SOURCE=false
            RUN_ZDM=false
            shift
            ;;
        -z|--zdm-only)
            RUN_SOURCE=false
            RUN_TARGET=false
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Main execution
print_header "ZDM Discovery Orchestration"
echo "Project: PRODDB Migration to Oracle Database@Azure"
echo "Started: $(date)"

# Validate prerequisites
if ! validate_prerequisites; then
    print_error "Prerequisites validation failed. Please fix the errors and try again."
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Test connectivity
print_header "Testing SSH Connectivity"

if [ "$RUN_SOURCE" = true ]; then
    test_ssh_connectivity "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$SOURCE_SSH_KEY" "Source"
    SOURCE_SSH_OK=$?
fi

if [ "$RUN_TARGET" = true ]; then
    test_ssh_connectivity "$TARGET_HOST" "$TARGET_ADMIN_USER" "$TARGET_SSH_KEY" "Target"
    TARGET_SSH_OK=$?
fi

if [ "$RUN_ZDM" = true ]; then
    test_ssh_connectivity "$ZDM_HOST" "$ZDM_ADMIN_USER" "$ZDM_SSH_KEY" "ZDM Server"
    ZDM_SSH_OK=$?
fi

if [ "$TEST_ONLY" = true ]; then
    print_info "Connectivity test complete. Exiting (--test mode)."
    exit 0
fi

# Run discovery on each server
print_header "Running Discovery"

if [ "$RUN_SOURCE" = true ] && [ "${SOURCE_SSH_OK:-1}" -eq 0 ]; then
    # Build environment variables string for source
    local source_env="ORACLE_USER=$ORACLE_USER"
    [ -n "${SOURCE_REMOTE_ORACLE_HOME:-}" ] && source_env="$source_env ORACLE_HOME_OVERRIDE=$SOURCE_REMOTE_ORACLE_HOME"
    [ -n "${SOURCE_REMOTE_ORACLE_SID:-}" ] && source_env="$source_env ORACLE_SID_OVERRIDE=$SOURCE_REMOTE_ORACLE_SID"
    
    run_remote_discovery "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$SOURCE_SSH_KEY" \
        "$SOURCE_SCRIPT" "source" "$source_env"
elif [ "$RUN_SOURCE" = true ]; then
    print_warning "Skipping source discovery (SSH connectivity failed)"
    SERVER_STATUS["source"]="SKIPPED"
    SERVER_ERRORS["source"]="SSH connectivity failed"
fi

if [ "$RUN_TARGET" = true ] && [ "${TARGET_SSH_OK:-1}" -eq 0 ]; then
    # Build environment variables string for target
    local target_env="ORACLE_USER=$ORACLE_USER"
    [ -n "${TARGET_REMOTE_ORACLE_HOME:-}" ] && target_env="$target_env ORACLE_HOME_OVERRIDE=$TARGET_REMOTE_ORACLE_HOME"
    [ -n "${TARGET_REMOTE_ORACLE_SID:-}" ] && target_env="$target_env ORACLE_SID_OVERRIDE=$TARGET_REMOTE_ORACLE_SID"
    
    run_remote_discovery "$TARGET_HOST" "$TARGET_ADMIN_USER" "$TARGET_SSH_KEY" \
        "$TARGET_SCRIPT" "target" "$target_env"
elif [ "$RUN_TARGET" = true ]; then
    print_warning "Skipping target discovery (SSH connectivity failed)"
    SERVER_STATUS["target"]="SKIPPED"
    SERVER_ERRORS["target"]="SSH connectivity failed"
fi

if [ "$RUN_ZDM" = true ] && [ "${ZDM_SSH_OK:-1}" -eq 0 ]; then
    # Build environment variables string for ZDM
    local zdm_env="ZDM_USER=$ZDM_USER SOURCE_HOST=$SOURCE_HOST TARGET_HOST=$TARGET_HOST"
    [ -n "${ZDM_REMOTE_ZDM_HOME:-}" ] && zdm_env="$zdm_env ZDM_HOME_OVERRIDE=$ZDM_REMOTE_ZDM_HOME"
    [ -n "${ZDM_REMOTE_JAVA_HOME:-}" ] && zdm_env="$zdm_env JAVA_HOME_OVERRIDE=$ZDM_REMOTE_JAVA_HOME"
    
    run_remote_discovery "$ZDM_HOST" "$ZDM_ADMIN_USER" "$ZDM_SSH_KEY" \
        "$ZDM_SCRIPT" "server" "$zdm_env"
elif [ "$RUN_ZDM" = true ]; then
    print_warning "Skipping ZDM server discovery (SSH connectivity failed)"
    SERVER_STATUS["server"]="SKIPPED"
    SERVER_ERRORS["server"]="SSH connectivity failed"
fi

# Print summary
print_summary

echo ""
echo "Completed: $(date)"
