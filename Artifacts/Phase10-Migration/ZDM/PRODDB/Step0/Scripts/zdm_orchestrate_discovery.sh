#!/bin/bash
# ZDM Discovery Orchestration Script
# Project: PRODDB Migration to Oracle Database@Azure
# Generated: 2026-01-30

# =============================================================================
# CONFIGURATION
# =============================================================================

# Server hostnames
SOURCE_HOST="${SOURCE_HOST:-proddb01.corp.example.com}"
TARGET_HOST="${TARGET_HOST:-proddb-oda.eastus.azure.example.com}"
ZDM_HOST="${ZDM_HOST:-zdm-jumpbox.corp.example.com}"

# SSH users
SOURCE_USER="${SOURCE_USER:-oracle}"
TARGET_USER="${TARGET_USER:-opc}"
ZDM_USER="${ZDM_USER:-zdmuser}"

# SSH keys (separate keys for each security domain)
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-~/.ssh/source_db_key}"
TARGET_SSH_KEY="${TARGET_SSH_KEY:-~/.ssh/oda_azure_key}"
ZDM_SSH_KEY="${ZDM_SSH_KEY:-~/.ssh/zdm_jumpbox_key}"

# Database name (for output directory)
DB_NAME="${DB_NAME:-PRODDB}"

# Output directory - defaults to Artifacts directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_BASE="${OUTPUT_DIR:-$(dirname "$SCRIPT_DIR")/Discovery}"

# Optional environment overrides (passed to remote scripts)
# These are used when auto-detection fails
# SOURCE_REMOTE_ORACLE_HOME - Oracle home on source server
# SOURCE_REMOTE_ORACLE_SID - Oracle SID on source server
# TARGET_REMOTE_ORACLE_HOME - Oracle home on target server
# TARGET_REMOTE_ORACLE_SID - Oracle SID on target server
# ZDM_REMOTE_ZDM_HOME - ZDM home on ZDM server
# ZDM_REMOTE_JAVA_HOME - Java home on ZDM server

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Tracking variables
ERRORS=0
SOURCE_SUCCESS=false
TARGET_SUCCESS=false
ZDM_SUCCESS=false

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

log_header() {
    echo -e "\n${CYAN}===============================================================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}===============================================================================${NC}\n"
}

log_section() {
    echo -e "\n${BLUE}>>> $1${NC}"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    cat <<EOF
ZDM Discovery Orchestration Script
Project: PRODDB Migration to Oracle Database@Azure

Usage: $0 [OPTIONS]

Options:
  -h, --help        Show this help message
  -c, --config      Display current configuration
  -t, --test        Test SSH connectivity only (no discovery)
  --source-only     Run discovery only on source server
  --target-only     Run discovery only on target server
  --zdm-only        Run discovery only on ZDM server

Environment Variables:
  SOURCE_HOST           Source database server hostname (default: proddb01.corp.example.com)
  TARGET_HOST           Target Oracle Database@Azure hostname (default: proddb-oda.eastus.azure.example.com)
  ZDM_HOST              ZDM jumpbox server hostname (default: zdm-jumpbox.corp.example.com)
  SOURCE_USER           SSH user for source server (default: oracle)
  TARGET_USER           SSH user for target server (default: opc)
  ZDM_USER              SSH user for ZDM server (default: zdmuser)
  SOURCE_SSH_KEY        SSH key for source server (default: ~/.ssh/source_db_key)
  TARGET_SSH_KEY        SSH key for target server (default: ~/.ssh/oda_azure_key)
  ZDM_SSH_KEY           SSH key for ZDM server (default: ~/.ssh/zdm_jumpbox_key)
  DB_NAME               Database name for output directory (default: PRODDB)
  OUTPUT_DIR            Output directory for discovery results

Optional Environment Overrides (when auto-detection fails):
  SOURCE_REMOTE_ORACLE_HOME    Oracle home path on source server
  SOURCE_REMOTE_ORACLE_SID     Oracle SID on source server
  TARGET_REMOTE_ORACLE_HOME    Oracle home path on target server
  TARGET_REMOTE_ORACLE_SID     Oracle SID on target server
  ZDM_REMOTE_ZDM_HOME          ZDM home path on ZDM server
  ZDM_REMOTE_JAVA_HOME         Java home path on ZDM server

Output:
  Discovery results are saved to:
  ${OUTPUT_BASE}/
    ├── source/   # Source server discovery results
    ├── target/   # Target server discovery results
    └── server/   # ZDM server discovery results

Examples:
  # Run full discovery with defaults
  $0

  # Test connectivity only
  $0 --test

  # Run with custom SSH key
  SOURCE_SSH_KEY=~/.ssh/custom_key $0

  # Override Oracle home when auto-detection fails
  SOURCE_REMOTE_ORACLE_HOME=/u01/app/oracle/product/19.0.0.0/dbhome_1 $0

EOF
}

show_config() {
    log_header "Current Configuration"
    echo "Source Server:"
    echo "  Host: $SOURCE_HOST"
    echo "  User: $SOURCE_USER"
    echo "  SSH Key: $SOURCE_SSH_KEY"
    echo ""
    echo "Target Server (Oracle Database@Azure):"
    echo "  Host: $TARGET_HOST"
    echo "  User: $TARGET_USER"
    echo "  SSH Key: $TARGET_SSH_KEY"
    echo ""
    echo "ZDM Server:"
    echo "  Host: $ZDM_HOST"
    echo "  User: $ZDM_USER"
    echo "  SSH Key: $ZDM_SSH_KEY"
    echo ""
    echo "Output Configuration:"
    echo "  Database Name: $DB_NAME"
    echo "  Output Directory: $OUTPUT_BASE"
    echo "  Script Directory: $SCRIPT_DIR"
    echo ""
    echo "Optional Overrides (if set):"
    echo "  SOURCE_REMOTE_ORACLE_HOME: ${SOURCE_REMOTE_ORACLE_HOME:-<not set>}"
    echo "  SOURCE_REMOTE_ORACLE_SID: ${SOURCE_REMOTE_ORACLE_SID:-<not set>}"
    echo "  TARGET_REMOTE_ORACLE_HOME: ${TARGET_REMOTE_ORACLE_HOME:-<not set>}"
    echo "  TARGET_REMOTE_ORACLE_SID: ${TARGET_REMOTE_ORACLE_SID:-<not set>}"
    echo "  ZDM_REMOTE_ZDM_HOME: ${ZDM_REMOTE_ZDM_HOME:-<not set>}"
    echo "  ZDM_REMOTE_JAVA_HOME: ${ZDM_REMOTE_JAVA_HOME:-<not set>}"
}

validate_config() {
    log_section "Validating Configuration"
    local valid=true
    
    # Check SSH keys exist
    local source_key=$(eval echo "$SOURCE_SSH_KEY")
    local target_key=$(eval echo "$TARGET_SSH_KEY")
    local zdm_key=$(eval echo "$ZDM_SSH_KEY")
    
    if [ ! -f "$source_key" ]; then
        log_error "Source SSH key not found: $source_key"
        valid=false
    else
        log_success "Source SSH key found: $source_key"
    fi
    
    if [ ! -f "$target_key" ]; then
        log_error "Target SSH key not found: $target_key"
        valid=false
    else
        log_success "Target SSH key found: $target_key"
    fi
    
    if [ ! -f "$zdm_key" ]; then
        log_error "ZDM SSH key not found: $zdm_key"
        valid=false
    else
        log_success "ZDM SSH key found: $zdm_key"
    fi
    
    # Check discovery scripts exist
    if [ ! -f "$SCRIPT_DIR/zdm_source_discovery.sh" ]; then
        log_error "Source discovery script not found: $SCRIPT_DIR/zdm_source_discovery.sh"
        valid=false
    else
        log_success "Source discovery script found"
    fi
    
    if [ ! -f "$SCRIPT_DIR/zdm_target_discovery.sh" ]; then
        log_error "Target discovery script not found: $SCRIPT_DIR/zdm_target_discovery.sh"
        valid=false
    else
        log_success "Target discovery script found"
    fi
    
    if [ ! -f "$SCRIPT_DIR/zdm_server_discovery.sh" ]; then
        log_error "ZDM server discovery script not found: $SCRIPT_DIR/zdm_server_discovery.sh"
        valid=false
    else
        log_success "ZDM server discovery script found"
    fi
    
    if [ "$valid" = false ]; then
        log_error "Configuration validation failed"
        return 1
    fi
    
    log_success "Configuration validation passed"
    return 0
}

test_ssh_connectivity() {
    local host="$1"
    local user="$2"
    local key="$3"
    local name="$4"
    
    local key_path=$(eval echo "$key")
    
    log_section "Testing SSH connectivity to $name ($user@$host)"
    
    if ssh -i "$key_path" -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no \
       "$user@$host" "echo 'SSH connection successful'" 2>/dev/null; then
        log_success "SSH connection to $name successful"
        return 0
    else
        log_error "SSH connection to $name failed"
        return 1
    fi
}

test_all_connectivity() {
    log_header "Testing SSH Connectivity"
    local all_ok=true
    
    test_ssh_connectivity "$SOURCE_HOST" "$SOURCE_USER" "$SOURCE_SSH_KEY" "Source Server" || all_ok=false
    test_ssh_connectivity "$TARGET_HOST" "$TARGET_USER" "$TARGET_SSH_KEY" "Target Server" || all_ok=false
    test_ssh_connectivity "$ZDM_HOST" "$ZDM_USER" "$ZDM_SSH_KEY" "ZDM Server" || all_ok=false
    
    echo ""
    if [ "$all_ok" = true ]; then
        log_success "All connectivity tests passed"
        return 0
    else
        log_warning "Some connectivity tests failed"
        return 1
    fi
}

run_remote_discovery() {
    local host="$1"
    local user="$2"
    local key="$3"
    local script="$4"
    local output_subdir="$5"
    local name="$6"
    local env_overrides="$7"
    
    local key_path=$(eval echo "$key")
    local output_dir="${OUTPUT_BASE}/${output_subdir}"
    
    log_section "Running discovery on $name ($user@$host)"
    
    # Create output directory
    mkdir -p "$output_dir"
    
    # Copy discovery script to remote server
    log_success "Copying discovery script to $name..."
    if ! scp -i "$key_path" -o StrictHostKeyChecking=no \
         "$SCRIPT_DIR/$script" "$user@$host:/tmp/$script" 2>/dev/null; then
        log_error "Failed to copy discovery script to $name"
        return 1
    fi
    
    # Build remote command with environment overrides
    local remote_cmd="chmod +x /tmp/$script && cd /tmp && $env_overrides bash -l -c '/tmp/$script'"
    
    # Execute discovery script remotely
    log_success "Executing discovery on $name..."
    if ! ssh -i "$key_path" -o StrictHostKeyChecking=no \
         "$user@$host" "$remote_cmd" 2>&1 | tee "${output_dir}/discovery_execution.log"; then
        log_warning "Discovery script execution had issues on $name (continuing anyway)"
    fi
    
    # Collect results
    log_success "Collecting discovery results from $name..."
    if scp -i "$key_path" -o StrictHostKeyChecking=no \
       "$user@$host:/tmp/zdm_*_discovery_*.txt" "$output_dir/" 2>/dev/null; then
        log_success "Text report collected"
    else
        log_warning "No text report found on $name"
    fi
    
    if scp -i "$key_path" -o StrictHostKeyChecking=no \
       "$user@$host:/tmp/zdm_*_discovery_*.json" "$output_dir/" 2>/dev/null; then
        log_success "JSON summary collected"
    else
        log_warning "No JSON summary found on $name"
    fi
    
    # Cleanup remote files
    ssh -i "$key_path" -o StrictHostKeyChecking=no \
        "$user@$host" "rm -f /tmp/$script /tmp/zdm_*_discovery_*" 2>/dev/null || true
    
    log_success "Discovery completed on $name"
    return 0
}

run_source_discovery() {
    local env_overrides=""
    [ -n "${SOURCE_REMOTE_ORACLE_HOME:-}" ] && env_overrides="$env_overrides ORACLE_HOME_OVERRIDE='$SOURCE_REMOTE_ORACLE_HOME'"
    [ -n "${SOURCE_REMOTE_ORACLE_SID:-}" ] && env_overrides="$env_overrides ORACLE_SID_OVERRIDE='$SOURCE_REMOTE_ORACLE_SID'"
    
    if run_remote_discovery "$SOURCE_HOST" "$SOURCE_USER" "$SOURCE_SSH_KEY" \
       "zdm_source_discovery.sh" "source" "Source Server" "$env_overrides"; then
        SOURCE_SUCCESS=true
    else
        ERRORS=$((ERRORS + 1))
    fi
}

run_target_discovery() {
    local env_overrides=""
    [ -n "${TARGET_REMOTE_ORACLE_HOME:-}" ] && env_overrides="$env_overrides ORACLE_HOME_OVERRIDE='$TARGET_REMOTE_ORACLE_HOME'"
    [ -n "${TARGET_REMOTE_ORACLE_SID:-}" ] && env_overrides="$env_overrides ORACLE_SID_OVERRIDE='$TARGET_REMOTE_ORACLE_SID'"
    
    if run_remote_discovery "$TARGET_HOST" "$TARGET_USER" "$TARGET_SSH_KEY" \
       "zdm_target_discovery.sh" "target" "Target Server" "$env_overrides"; then
        TARGET_SUCCESS=true
    else
        ERRORS=$((ERRORS + 1))
    fi
}

run_zdm_discovery() {
    local env_overrides=""
    [ -n "${ZDM_REMOTE_ZDM_HOME:-}" ] && env_overrides="$env_overrides ZDM_HOME_OVERRIDE='$ZDM_REMOTE_ZDM_HOME'"
    [ -n "${ZDM_REMOTE_JAVA_HOME:-}" ] && env_overrides="$env_overrides JAVA_HOME_OVERRIDE='$ZDM_REMOTE_JAVA_HOME'"
    
    if run_remote_discovery "$ZDM_HOST" "$ZDM_USER" "$ZDM_SSH_KEY" \
       "zdm_server_discovery.sh" "server" "ZDM Server" "$env_overrides"; then
        ZDM_SUCCESS=true
    else
        ERRORS=$((ERRORS + 1))
    fi
}

print_summary() {
    log_header "Discovery Summary"
    
    echo "Results saved to: $OUTPUT_BASE"
    echo ""
    echo "Server Status:"
    if [ "$SOURCE_SUCCESS" = true ]; then
        echo -e "  Source Server:  ${GREEN}✓ SUCCESS${NC}"
    else
        echo -e "  Source Server:  ${RED}✗ FAILED${NC}"
    fi
    
    if [ "$TARGET_SUCCESS" = true ]; then
        echo -e "  Target Server:  ${GREEN}✓ SUCCESS${NC}"
    else
        echo -e "  Target Server:  ${RED}✗ FAILED${NC}"
    fi
    
    if [ "$ZDM_SUCCESS" = true ]; then
        echo -e "  ZDM Server:     ${GREEN}✓ SUCCESS${NC}"
    else
        echo -e "  ZDM Server:     ${RED}✗ FAILED${NC}"
    fi
    
    echo ""
    echo "Output Files:"
    ls -la "$OUTPUT_BASE"/source/*.txt 2>/dev/null || echo "  (No source reports)"
    ls -la "$OUTPUT_BASE"/target/*.txt 2>/dev/null || echo "  (No target reports)"
    ls -la "$OUTPUT_BASE"/server/*.txt 2>/dev/null || echo "  (No ZDM server reports)"
    
    echo ""
    if [ $ERRORS -eq 0 ]; then
        echo -e "${GREEN}All discovery operations completed successfully!${NC}"
    else
        echo -e "${YELLOW}Discovery completed with $ERRORS error(s).${NC}"
        echo "Review the individual discovery logs for details."
    fi
    
    echo ""
    echo "Next Steps:"
    echo "  1. Review the discovery reports in $OUTPUT_BASE"
    echo "  2. Proceed to Step 1: Discovery Questionnaire"
    echo "     Use the discovery data to complete the questionnaire"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    log_header "ZDM Discovery Orchestration"
    echo "Project: PRODDB Migration to Oracle Database@Azure"
    echo "Timestamp: $(date)"
    echo ""
    
    # Validate configuration
    if ! validate_config; then
        log_error "Please fix configuration issues before running discovery"
        exit 1
    fi
    
    # Create output directories
    mkdir -p "$OUTPUT_BASE/source"
    mkdir -p "$OUTPUT_BASE/target"
    mkdir -p "$OUTPUT_BASE/server"
    
    # Test connectivity first
    test_all_connectivity
    
    # Run discoveries (continue on failure)
    log_header "Running Discovery Scripts"
    
    run_source_discovery
    run_target_discovery
    run_zdm_discovery
    
    # Print summary
    print_summary
    
    # Exit with error code if any failures
    if [ $ERRORS -gt 0 ]; then
        exit 1
    fi
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

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
        validate_config && test_all_connectivity
        exit $?
        ;;
    --source-only)
        log_header "ZDM Discovery - Source Server Only"
        validate_config || exit 1
        mkdir -p "$OUTPUT_BASE/source"
        run_source_discovery
        print_summary
        exit $ERRORS
        ;;
    --target-only)
        log_header "ZDM Discovery - Target Server Only"
        validate_config || exit 1
        mkdir -p "$OUTPUT_BASE/target"
        run_target_discovery
        print_summary
        exit $ERRORS
        ;;
    --zdm-only)
        log_header "ZDM Discovery - ZDM Server Only"
        validate_config || exit 1
        mkdir -p "$OUTPUT_BASE/server"
        run_zdm_discovery
        print_summary
        exit $ERRORS
        ;;
    *)
        main
        ;;
esac
