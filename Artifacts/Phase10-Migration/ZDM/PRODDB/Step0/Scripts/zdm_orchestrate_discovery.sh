#!/bin/bash
################################################################################
# ZDM Discovery Orchestration Script
# Project: PRODDB Migration to Oracle Database@Azure
# Purpose: Orchestrate discovery across source, target, and ZDM servers
#
# This script can be run from any machine with SSH access to all three servers.
# It copies discovery scripts to each server, executes them, and collects results.
#
# Usage:
#   ./zdm_orchestrate_discovery.sh              # Run discovery with defaults
#   ./zdm_orchestrate_discovery.sh -h           # Show help
#   ./zdm_orchestrate_discovery.sh -c           # Show configuration
#   ./zdm_orchestrate_discovery.sh -t           # Test connectivity only
################################################################################

# Determine script directory and repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Navigate up 6 levels: Scripts → Step0 → PRODDB → ZDM → Phase10-Migration → Artifacts → RepoRoot
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../../.." && pwd)"

################################################################################
# Default Configuration
################################################################################

# Server hostnames (MUST be configured for your environment)
SOURCE_HOST="${SOURCE_HOST:-proddb01.corp.example.com}"
TARGET_HOST="${TARGET_HOST:-proddb-oda.eastus.azure.example.com}"
ZDM_HOST="${ZDM_HOST:-zdm-jumpbox.corp.example.com}"

# SSH/Admin users for each server (can be different for each environment)
# These are Linux admin users with sudo privileges
SOURCE_ADMIN_USER="${SOURCE_ADMIN_USER:-oracle}"
TARGET_ADMIN_USER="${TARGET_ADMIN_USER:-opc}"
ZDM_ADMIN_USER="${ZDM_ADMIN_USER:-azureuser}"

# Oracle database software owner (for running SQL commands)
ORACLE_USER="${ORACLE_USER:-oracle}"

# ZDM software owner (for running ZDM CLI commands)
ZDM_USER="${ZDM_USER:-zdmuser}"

# SSH key paths (separate keys for each security domain)
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-$HOME/.ssh/onprem_oracle_key}"
TARGET_SSH_KEY="${TARGET_SSH_KEY:-$HOME/.ssh/oci_opc_key}"
ZDM_SSH_KEY="${ZDM_SSH_KEY:-$HOME/.ssh/azure_key}"

# Output directory (relative to repository root)
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/Artifacts/Phase10-Migration/ZDM/PRODDB/Step0/Discovery}"

# SSH options
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=30 -o BatchMode=yes"

# Database name for output organization
DB_NAME="${DB_NAME:-PRODDB}"

################################################################################
# Colors for terminal output
################################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

################################################################################
# Utility Functions
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
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
}

show_help() {
    cat <<EOF
ZDM Discovery Orchestration Script
Project: PRODDB Migration to Oracle Database@Azure

Usage: $(basename "$0") [OPTIONS]

Options:
  -h, --help        Show this help message
  -c, --config      Show current configuration
  -t, --test        Test SSH connectivity only (no discovery)
  -s, --source      Run source discovery only
  -T, --target      Run target discovery only  
  -z, --zdm         Run ZDM server discovery only

Environment Variables:
  SOURCE_HOST           Source database server hostname
  TARGET_HOST           Target Oracle Database@Azure hostname
  ZDM_HOST              ZDM jumpbox server hostname
  
  SOURCE_ADMIN_USER     Admin user for source server SSH (default: oracle)
  TARGET_ADMIN_USER     Admin user for target server SSH (default: opc)
  ZDM_ADMIN_USER        Admin user for ZDM server SSH (default: azureuser)
  
  ORACLE_USER           Oracle database software owner (default: oracle)
  ZDM_USER              ZDM software owner (default: zdmuser)
  
  SOURCE_SSH_KEY        SSH key for source server
  TARGET_SSH_KEY        SSH key for target server
  ZDM_SSH_KEY           SSH key for ZDM server
  
  OUTPUT_DIR            Output directory for discovery results

Example:
  # Run with defaults
  ./$(basename "$0")
  
  # Override source host
  SOURCE_HOST=mydb01.example.com ./$(basename "$0")
  
  # Test connectivity only
  ./$(basename "$0") -t

EOF
}

show_config() {
    log_section "Current Configuration"
    echo ""
    echo -e "${CYAN}Server Hostnames:${NC}"
    echo "  SOURCE_HOST:        $SOURCE_HOST"
    echo "  TARGET_HOST:        $TARGET_HOST"
    echo "  ZDM_HOST:           $ZDM_HOST"
    echo ""
    echo -e "${CYAN}SSH Admin Users:${NC}"
    echo "  SOURCE_ADMIN_USER:  $SOURCE_ADMIN_USER"
    echo "  TARGET_ADMIN_USER:  $TARGET_ADMIN_USER"
    echo "  ZDM_ADMIN_USER:     $ZDM_ADMIN_USER"
    echo ""
    echo -e "${CYAN}Application Users:${NC}"
    echo "  ORACLE_USER:        $ORACLE_USER"
    echo "  ZDM_USER:           $ZDM_USER"
    echo ""
    echo -e "${CYAN}SSH Keys:${NC}"
    echo "  SOURCE_SSH_KEY:     $SOURCE_SSH_KEY"
    echo "  TARGET_SSH_KEY:     $TARGET_SSH_KEY"
    echo "  ZDM_SSH_KEY:        $ZDM_SSH_KEY"
    echo ""
    echo -e "${CYAN}Output:${NC}"
    echo "  SCRIPT_DIR:         $SCRIPT_DIR"
    echo "  REPO_ROOT:          $REPO_ROOT"
    echo "  OUTPUT_DIR:         $OUTPUT_DIR"
    echo ""
}

################################################################################
# Validation Functions
################################################################################

validate_config() {
    local errors=0
    
    log_section "Validating Configuration"
    
    # Check hostnames
    if [ -z "$SOURCE_HOST" ]; then
        log_error "SOURCE_HOST is not set"
        ((errors++))
    fi
    if [ -z "$TARGET_HOST" ]; then
        log_error "TARGET_HOST is not set"
        ((errors++))
    fi
    if [ -z "$ZDM_HOST" ]; then
        log_error "ZDM_HOST is not set"
        ((errors++))
    fi
    
    # Check SSH keys exist
    if [ ! -f "$SOURCE_SSH_KEY" ]; then
        log_warn "SOURCE_SSH_KEY not found: $SOURCE_SSH_KEY"
    fi
    if [ ! -f "$TARGET_SSH_KEY" ]; then
        log_warn "TARGET_SSH_KEY not found: $TARGET_SSH_KEY"
    fi
    if [ ! -f "$ZDM_SSH_KEY" ]; then
        log_warn "ZDM_SSH_KEY not found: $ZDM_SSH_KEY"
    fi
    
    # Check discovery scripts exist
    if [ ! -f "$SCRIPT_DIR/zdm_source_discovery.sh" ]; then
        log_error "Source discovery script not found: $SCRIPT_DIR/zdm_source_discovery.sh"
        ((errors++))
    fi
    if [ ! -f "$SCRIPT_DIR/zdm_target_discovery.sh" ]; then
        log_error "Target discovery script not found: $SCRIPT_DIR/zdm_target_discovery.sh"
        ((errors++))
    fi
    if [ ! -f "$SCRIPT_DIR/zdm_server_discovery.sh" ]; then
        log_error "ZDM server discovery script not found: $SCRIPT_DIR/zdm_server_discovery.sh"
        ((errors++))
    fi
    
    if [ $errors -gt 0 ]; then
        log_error "Configuration validation failed with $errors error(s)"
        return 1
    fi
    
    log_info "Configuration validation passed"
    return 0
}

################################################################################
# SSH Connectivity Test
################################################################################

test_ssh_connectivity() {
    local host="$1"
    local user="$2"
    local key="$3"
    local name="$4"
    
    log_info "Testing SSH connectivity to $name ($user@$host)..."
    
    if [ ! -f "$key" ]; then
        log_warn "SSH key not found: $key"
        return 1
    fi
    
    if ssh $SSH_OPTS -i "$key" "${user}@${host}" "echo 'SSH connection successful'" 2>/dev/null; then
        log_info "✓ SSH to $name: SUCCESS"
        return 0
    else
        log_error "✗ SSH to $name: FAILED"
        return 1
    fi
}

test_all_connectivity() {
    log_section "Testing SSH Connectivity"
    
    local source_ok=0
    local target_ok=0
    local zdm_ok=0
    
    test_ssh_connectivity "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$SOURCE_SSH_KEY" "Source" && source_ok=1
    test_ssh_connectivity "$TARGET_HOST" "$TARGET_ADMIN_USER" "$TARGET_SSH_KEY" "Target" && target_ok=1
    test_ssh_connectivity "$ZDM_HOST" "$ZDM_ADMIN_USER" "$ZDM_SSH_KEY" "ZDM Server" && zdm_ok=1
    
    echo ""
    log_section "Connectivity Summary"
    echo ""
    
    if [ $source_ok -eq 1 ]; then
        echo -e "  Source ($SOURCE_HOST):     ${GREEN}✓ Connected${NC}"
    else
        echo -e "  Source ($SOURCE_HOST):     ${RED}✗ Failed${NC}"
    fi
    
    if [ $target_ok -eq 1 ]; then
        echo -e "  Target ($TARGET_HOST):     ${GREEN}✓ Connected${NC}"
    else
        echo -e "  Target ($TARGET_HOST):     ${RED}✗ Failed${NC}"
    fi
    
    if [ $zdm_ok -eq 1 ]; then
        echo -e "  ZDM Server ($ZDM_HOST):    ${GREEN}✓ Connected${NC}"
    else
        echo -e "  ZDM Server ($ZDM_HOST):    ${RED}✗ Failed${NC}"
    fi
    
    echo ""
    
    # Return overall status
    if [ $source_ok -eq 1 ] && [ $target_ok -eq 1 ] && [ $zdm_ok -eq 1 ]; then
        return 0
    else
        return 1
    fi
}

################################################################################
# Discovery Execution Functions
################################################################################

run_remote_discovery() {
    local host="$1"
    local user="$2"
    local key="$3"
    local script_path="$4"
    local output_subdir="$5"
    local name="$6"
    local extra_env="$7"
    
    log_section "Running $name Discovery"
    
    # Create output subdirectory
    mkdir -p "$OUTPUT_DIR/$output_subdir"
    
    # Check SSH key
    if [ ! -f "$key" ]; then
        log_error "SSH key not found: $key"
        return 1
    fi
    
    # Check script exists
    if [ ! -f "$script_path" ]; then
        log_error "Discovery script not found: $script_path"
        return 1
    fi
    
    log_info "Connecting to $host as $user..."
    log_info "Running discovery script..."
    
    # Execute discovery script remotely using login shell
    # Pass environment variables for oracle user and extra environment
    local remote_cmd="ORACLE_USER='$ORACLE_USER' ZDM_USER='$ZDM_USER' $extra_env bash -l -s"
    
    if ssh $SSH_OPTS -i "$key" "${user}@${host}" "$remote_cmd" < "$script_path"; then
        log_info "Discovery script completed on $host"
        
        # Collect output files
        log_info "Collecting discovery results..."
        
        # Get the remote hostname for file naming
        local remote_hostname
        remote_hostname=$(ssh $SSH_OPTS -i "$key" "${user}@${host}" "hostname -s" 2>/dev/null)
        
        # Find and copy discovery output files
        local remote_files
        remote_files=$(ssh $SSH_OPTS -i "$key" "${user}@${host}" "ls -1 ./zdm_*_discovery_*.txt ./zdm_*_discovery_*.json 2>/dev/null" | head -10)
        
        if [ -n "$remote_files" ]; then
            for file in $remote_files; do
                local filename=$(basename "$file")
                scp $SSH_OPTS -i "$key" "${user}@${host}:$file" "$OUTPUT_DIR/$output_subdir/" 2>/dev/null
                if [ $? -eq 0 ]; then
                    log_info "Collected: $filename"
                else
                    log_warn "Failed to collect: $filename"
                fi
            done
            
            # Clean up remote files
            ssh $SSH_OPTS -i "$key" "${user}@${host}" "rm -f ./zdm_*_discovery_*.txt ./zdm_*_discovery_*.json" 2>/dev/null
        else
            log_warn "No discovery output files found on remote server"
        fi
        
        return 0
    else
        log_error "Discovery script failed on $host"
        return 1
    fi
}

################################################################################
# Main Execution
################################################################################

# Parse command line arguments
RUN_SOURCE=true
RUN_TARGET=true
RUN_ZDM=true

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
            test_all_connectivity
            exit $?
            ;;
        -s|--source)
            RUN_SOURCE=true
            RUN_TARGET=false
            RUN_ZDM=false
            shift
            ;;
        -T|--target)
            RUN_SOURCE=false
            RUN_TARGET=true
            RUN_ZDM=false
            shift
            ;;
        -z|--zdm)
            RUN_SOURCE=false
            RUN_TARGET=false
            RUN_ZDM=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Show banner
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║         ZDM Discovery Orchestration Script                       ║${NC}"
echo -e "${CYAN}║         Project: PRODDB Migration to Oracle Database@Azure       ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Show configuration
show_config

# Validate configuration
if ! validate_config; then
    log_error "Please fix configuration errors and retry"
    exit 1
fi

# Create output directory structure
log_section "Creating Output Directory Structure"
mkdir -p "$OUTPUT_DIR/source"
mkdir -p "$OUTPUT_DIR/target"
mkdir -p "$OUTPUT_DIR/server"
log_info "Output directory: $OUTPUT_DIR"

# Track results
SOURCE_RESULT="SKIPPED"
TARGET_RESULT="SKIPPED"
ZDM_RESULT="SKIPPED"

# Run source discovery
if [ "$RUN_SOURCE" = true ]; then
    if run_remote_discovery "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$SOURCE_SSH_KEY" \
        "$SCRIPT_DIR/zdm_source_discovery.sh" "source" "Source Database" ""; then
        SOURCE_RESULT="SUCCESS"
    else
        SOURCE_RESULT="FAILED"
    fi
fi

# Run target discovery
if [ "$RUN_TARGET" = true ]; then
    if run_remote_discovery "$TARGET_HOST" "$TARGET_ADMIN_USER" "$TARGET_SSH_KEY" \
        "$SCRIPT_DIR/zdm_target_discovery.sh" "target" "Target Database" ""; then
        TARGET_RESULT="SUCCESS"
    else
        TARGET_RESULT="FAILED"
    fi
fi

# Run ZDM server discovery (pass SOURCE_HOST and TARGET_HOST for connectivity tests)
if [ "$RUN_ZDM" = true ]; then
    ZDM_EXTRA_ENV="SOURCE_HOST='$SOURCE_HOST' TARGET_HOST='$TARGET_HOST'"
    if run_remote_discovery "$ZDM_HOST" "$ZDM_ADMIN_USER" "$ZDM_SSH_KEY" \
        "$SCRIPT_DIR/zdm_server_discovery.sh" "server" "ZDM Server" "$ZDM_EXTRA_ENV"; then
        ZDM_RESULT="SUCCESS"
    else
        ZDM_RESULT="FAILED"
    fi
fi

################################################################################
# Summary
################################################################################

log_section "Discovery Summary"
echo ""
echo -e "${CYAN}Results:${NC}"

if [ "$SOURCE_RESULT" = "SUCCESS" ]; then
    echo -e "  Source Discovery:     ${GREEN}✓ SUCCESS${NC}"
elif [ "$SOURCE_RESULT" = "FAILED" ]; then
    echo -e "  Source Discovery:     ${RED}✗ FAILED${NC}"
else
    echo -e "  Source Discovery:     ${YELLOW}○ SKIPPED${NC}"
fi

if [ "$TARGET_RESULT" = "SUCCESS" ]; then
    echo -e "  Target Discovery:     ${GREEN}✓ SUCCESS${NC}"
elif [ "$TARGET_RESULT" = "FAILED" ]; then
    echo -e "  Target Discovery:     ${RED}✗ FAILED${NC}"
else
    echo -e "  Target Discovery:     ${YELLOW}○ SKIPPED${NC}"
fi

if [ "$ZDM_RESULT" = "SUCCESS" ]; then
    echo -e "  ZDM Server Discovery: ${GREEN}✓ SUCCESS${NC}"
elif [ "$ZDM_RESULT" = "FAILED" ]; then
    echo -e "  ZDM Server Discovery: ${RED}✗ FAILED${NC}"
else
    echo -e "  ZDM Server Discovery: ${YELLOW}○ SKIPPED${NC}"
fi

echo ""
echo -e "${CYAN}Output Location:${NC}"
echo "  $OUTPUT_DIR"
echo ""

# List collected files
echo -e "${CYAN}Collected Files:${NC}"
find "$OUTPUT_DIR" -type f -name "*.txt" -o -name "*.json" 2>/dev/null | while read file; do
    echo "  $(basename "$file")"
done

echo ""
echo -e "${CYAN}Next Steps:${NC}"
echo "  1. Review discovery output files in $OUTPUT_DIR"
echo "  2. Proceed to Step 1: Discovery Questionnaire"
echo "     @Step1-Discovery-Questionnaire.prompt.md"
echo ""

# Exit with appropriate code
if [ "$SOURCE_RESULT" = "FAILED" ] || [ "$TARGET_RESULT" = "FAILED" ] || [ "$ZDM_RESULT" = "FAILED" ]; then
    log_warn "One or more discoveries failed. Review errors above."
    exit 1
fi

log_info "Discovery orchestration completed successfully!"
exit 0
