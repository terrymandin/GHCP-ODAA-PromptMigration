#!/bin/bash
# =============================================================================
# zdm_orchestrate_discovery.sh
# ZDM Migration - Master Orchestration Script
# Project: ORADB
#
# Purpose: Orchestrate discovery across source, target, and ZDM servers by
#          copying and executing discovery scripts remotely, then collecting
#          the output files into the local Artifacts directory.
#
# Usage:
#   bash zdm_orchestrate_discovery.sh [-v] [-h] [-c] [-t]
#
# Options:
#   -h, --help     Show this help message and exit
#   -c, --config   Display current configuration and exit
#   -t, --test     Run connectivity tests only (no discovery)
#   -v, --verbose  Enable verbose/debug output
#
# Prerequisites:
#   - SSH key access to source, target, and ZDM servers
#   - Discovery scripts in same directory as this script
#   - SSH keys at paths defined in configuration below
#
# Output:
#   Artifacts/Phase10-Migration/ZDM/ORADB/Step0/Discovery/
#     source/  - Source database discovery reports
#     target/  - Target database discovery reports
#     server/  - ZDM server discovery reports
# =============================================================================

# --- Do NOT use set -e; individual servers may fail without stopping all ---

# -----------------------------------------------------------------------
# Directory setup
# -----------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Script is at: Artifacts/Phase10-Migration/ZDM/ORADB/Step0/Scripts/
# Navigate up 6 levels: Scripts -> Step0 -> ORADB -> ZDM -> Phase10-Migration -> Artifacts -> RepoRoot
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../../../.." && pwd)"
DATABASE_NAME="ORADB"

# -----------------------------------------------------------------------
# Colour helpers
# -----------------------------------------------------------------------
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# -----------------------------------------------------------------------
# Logging functions
# NOTE: log_raw is NOT defined here - it exists only in the individual
#       discovery scripts. Use log_info for all orchestrator output.
# -----------------------------------------------------------------------
log_info()    { echo -e "${GREEN}[INFO ]${RESET} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN ]${RESET} $*"; }
log_error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
log_section() { echo -e "\n${BOLD}${CYAN}=====================================================================${RESET}"; \
                 echo -e "${BOLD}${CYAN}  $*${RESET}"; \
                 echo -e "${BOLD}${CYAN}=====================================================================${RESET}"; }

VERBOSE=false
log_debug() { $VERBOSE && echo -e "${CYAN}[DEBUG]${RESET} $*" || true; }

# -----------------------------------------------------------------------
# Parse arguments (ONLY place where show_help/show_config are called)
# -----------------------------------------------------------------------
TEST_ONLY=false
for arg in "$@"; do
    case "$arg" in
        -h|--help)
            echo ""
            echo "Usage: $0 [-v] [-h] [-c] [-t]"
            echo ""
            echo "ZDM Discovery Orchestration Script"
            echo "Project: $DATABASE_NAME"
            echo ""
            echo "Options:"
            echo "  -h, --help     Show this help and exit"
            echo "  -c, --config   Display configuration and exit"
            echo "  -t, --test     Connectivity test only"
            echo "  -v, --verbose  Verbose/debug output (also passes -v to SSH)"
            echo ""
            echo "Environment variable overrides:"
            echo "  SOURCE_HOST, TARGET_HOST, ZDM_HOST"
            echo "  SOURCE_ADMIN_USER, TARGET_ADMIN_USER, ZDM_ADMIN_USER"
            echo "  SOURCE_SSH_KEY, TARGET_SSH_KEY, ZDM_SSH_KEY"
            echo "  ORACLE_USER, ZDM_USER"
            echo "  OUTPUT_DIR  (absolute path override for discovery output)"
            echo ""
            echo "Path overrides (passed to remote scripts):"
            echo "  SOURCE_REMOTE_ORACLE_HOME, SOURCE_REMOTE_ORACLE_SID"
            echo "  TARGET_REMOTE_ORACLE_HOME, TARGET_REMOTE_ORACLE_SID"
            echo "  ZDM_REMOTE_ZDM_HOME, ZDM_REMOTE_JAVA_HOME"
            echo ""
            exit 0
            ;;
        -c|--config)
            # Load defaults first so config shows real values
            SOURCE_HOST="${SOURCE_HOST:-10.1.0.11}"
            TARGET_HOST="${TARGET_HOST:-10.0.1.160}"
            ZDM_HOST="${ZDM_HOST:-10.1.0.8}"
            SOURCE_ADMIN_USER="${SOURCE_ADMIN_USER:-azureuser}"
            TARGET_ADMIN_USER="${TARGET_ADMIN_USER:-opc}"
            ZDM_ADMIN_USER="${ZDM_ADMIN_USER:-azureuser}"
            SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-~/.ssh/odaa.pem}"
            TARGET_SSH_KEY="${TARGET_SSH_KEY:-~/.ssh/odaa.pem}"
            ZDM_SSH_KEY="${ZDM_SSH_KEY:-~/.ssh/zdm.pem}"
            ORACLE_USER="${ORACLE_USER:-oracle}"
            ZDM_USER="${ZDM_USER:-zdmuser}"
            echo ""
            echo "======================================================="
            echo "  ZDM Discovery Configuration"
            echo "  Project: $DATABASE_NAME"
            echo "======================================================="
            echo ""
            echo "Server Configuration:"
            echo "  SOURCE_HOST       : $SOURCE_HOST"
            echo "  TARGET_HOST       : $TARGET_HOST"
            echo "  ZDM_HOST          : $ZDM_HOST"
            echo ""
            echo "SSH Users:"
            echo "  SOURCE_ADMIN_USER : $SOURCE_ADMIN_USER"
            echo "  TARGET_ADMIN_USER : $TARGET_ADMIN_USER"
            echo "  ZDM_ADMIN_USER    : $ZDM_ADMIN_USER"
            echo ""
            echo "SSH Keys:"
            echo "  SOURCE_SSH_KEY    : $SOURCE_SSH_KEY"
            echo "  TARGET_SSH_KEY    : $TARGET_SSH_KEY"
            echo "  ZDM_SSH_KEY       : $ZDM_SSH_KEY"
            echo ""
            echo "Application Users:"
            echo "  ORACLE_USER       : $ORACLE_USER"
            echo "  ZDM_USER          : $ZDM_USER"
            echo ""
            echo "Paths:"
            echo "  SCRIPT_DIR        : $SCRIPT_DIR"
            echo "  REPO_ROOT         : $REPO_ROOT"
            echo ""
            exit 0
            ;;
        -t|--test)   TEST_ONLY=true ;;
        -v|--verbose) VERBOSE=true ;;
    esac
done

# -----------------------------------------------------------------------
# Configuration (defaults from zdm-env.md)
# ===========================================
# USER CONFIGURATION
# ===========================================
# SSH/Admin users for each server (can vary per environment)
SOURCE_ADMIN_USER="${SOURCE_ADMIN_USER:-azureuser}"
TARGET_ADMIN_USER="${TARGET_ADMIN_USER:-opc}"
ZDM_ADMIN_USER="${ZDM_ADMIN_USER:-azureuser}"

# Oracle database software owner (for running SQL)
ORACLE_USER="${ORACLE_USER:-oracle}"

# ZDM software owner (for running ZDM CLI)
ZDM_USER="${ZDM_USER:-zdmuser}"

# ===========================================
# SERVER CONFIGURATION
# ===========================================
SOURCE_HOST="${SOURCE_HOST:-10.1.0.11}"
TARGET_HOST="${TARGET_HOST:-10.0.1.160}"
ZDM_HOST="${ZDM_HOST:-10.1.0.8}"

# ===========================================
# SSH KEY PATHS
# ===========================================
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-~/.ssh/odaa.pem}"
TARGET_SSH_KEY="${TARGET_SSH_KEY:-~/.ssh/odaa.pem}"
ZDM_SSH_KEY="${ZDM_SSH_KEY:-~/.ssh/zdm.pem}"

# ===========================================
# OUTPUT DIRECTORY
# ===========================================
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/Artifacts/Phase10-Migration/ZDM/${DATABASE_NAME}/Step0/Discovery}"

# ===========================================
# OPTIONAL REMOTE PATH OVERRIDES
# (leave empty to use auto-detection)
# ===========================================
SOURCE_REMOTE_ORACLE_HOME="${SOURCE_REMOTE_ORACLE_HOME:-}"
SOURCE_REMOTE_ORACLE_SID="${SOURCE_REMOTE_ORACLE_SID:-}"
TARGET_REMOTE_ORACLE_HOME="${TARGET_REMOTE_ORACLE_HOME:-}"
TARGET_REMOTE_ORACLE_SID="${TARGET_REMOTE_ORACLE_SID:-}"
ZDM_REMOTE_ZDM_HOME="${ZDM_REMOTE_ZDM_HOME:-}"
ZDM_REMOTE_JAVA_HOME="${ZDM_REMOTE_JAVA_HOME:-}"

# SSH verbose flag (pass through when verbose is enabled)
SSH_V_FLAG=""
$VERBOSE && SSH_V_FLAG="-v"

# -----------------------------------------------------------------------
# SSH Options (shared across all connections)
# -----------------------------------------------------------------------
SSH_OPTS="-o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=30 ${SSH_V_FLAG}"

# -----------------------------------------------------------------------
# Error tracking
# -----------------------------------------------------------------------
DISCOVERY_ERRORS=0
declare -A SERVER_STATUS
SERVER_STATUS["source"]="NOT_STARTED"
SERVER_STATUS["target"]="NOT_STARTED"
SERVER_STATUS["server"]="NOT_STARTED"

# -----------------------------------------------------------------------
# Upfront SSH key diagnostic
# (runs before any connections to diagnose common key path issues)
# -----------------------------------------------------------------------
run_ssh_key_diagnostic() {
    log_section "SSH Key Diagnostic"
    log_info "Current user : $(whoami)"
    log_info "Home directory: $HOME"

    log_info ""
    log_info "PEM/KEY files in ~/.ssh/:"
    local ssh_dir="$HOME/.ssh"
    if [ -d "$ssh_dir" ]; then
        local found_keys
        found_keys=$(find "$ssh_dir" -maxdepth 1 \( -name "*.pem" -o -name "*.key" \) 2>/dev/null)
        if [ -n "$found_keys" ]; then
            while IFS= read -r keyfile; do
                log_info "  Found: $keyfile"
            done <<< "$found_keys"
        else
            log_warn "  No .pem or .key files found in $ssh_dir"
        fi
    else
        log_warn "  ~/.ssh directory not found: $ssh_dir"
        log_warn "  This is the most common failure cause - script may be running as"
        log_warn "  a different user than expected (e.g., zdmuser vs azureuser)"
    fi

    log_info ""
    log_info "Checking configured SSH keys:"
    local -A key_map
    key_map["SOURCE_SSH_KEY"]="$SOURCE_SSH_KEY"
    key_map["TARGET_SSH_KEY"]="$TARGET_SSH_KEY"
    key_map["ZDM_SSH_KEY"]="$ZDM_SSH_KEY"

    for var_name in SOURCE_SSH_KEY TARGET_SSH_KEY ZDM_SSH_KEY; do
        local key_path="${key_map[$var_name]}"
        local key_expanded
        key_expanded=$(eval echo "$key_path" 2>/dev/null)
        if [ -f "$key_expanded" ]; then
            log_info "  $var_name = $key_path  →  $key_expanded  [EXISTS]"
        else
            log_warn "  $var_name = $key_path  →  $key_expanded  [MISSING]"
            log_warn "    Fix: export $var_name=\"/correct/path/to/key.pem\""
        fi
    done
}

# -----------------------------------------------------------------------
# Validate prerequisites
# -----------------------------------------------------------------------
validate_prerequisites() {
    log_section "Validating Prerequisites"
    local errors=0

    # Check discovery scripts exist
    for script in zdm_source_discovery.sh zdm_target_discovery.sh zdm_server_discovery.sh; do
        if [ ! -f "${SCRIPT_DIR}/${script}" ]; then
            log_error "Discovery script not found: ${SCRIPT_DIR}/${script}"
            ((errors++))
        else
            log_info "Found: ${script}"
        fi
    done

    if [ $errors -gt 0 ]; then
        log_error "$errors prerequisite check(s) failed. Run from the Scripts directory."
        exit 1
    fi

    log_info "All prerequisites satisfied"
}

# -----------------------------------------------------------------------
# Test SSH connectivity to a host
# Returns 0 on success, 1 on failure
# Captures and logs stderr on failure
# -----------------------------------------------------------------------
test_ssh_connection() {
    local host="$1"
    local user="$2"
    local key_path="$3"
    local label="$4"
    local key_expanded
    key_expanded=$(eval echo "$key_path")

    log_info "Testing SSH: ${user}@${host} (key: ${key_expanded})"

    local test_output
    test_output=$(ssh $SSH_OPTS -i "$key_expanded" "${user}@${host}" \
        "echo SSH_OK && hostname" 2>&1)
    local exit_code=$?

    if [ $exit_code -eq 0 ] && echo "$test_output" | grep -q "SSH_OK"; then
        log_info "  ${label}: SSH connection SUCCESSFUL"
        return 0
    else
        log_error "  ${label}: SSH connection FAILED (exit code: $exit_code)"
        log_error "  SSH output/error: $test_output"
        log_error "  Check: key path exists, host reachable, user has access"
        return 1
    fi
}

# -----------------------------------------------------------------------
# Test all connections
# -----------------------------------------------------------------------
test_all_connections() {
    log_section "SSH Connectivity Tests"
    local all_ok=true

    test_ssh_connection "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$SOURCE_SSH_KEY" "Source   " || all_ok=false
    test_ssh_connection "$TARGET_HOST" "$TARGET_ADMIN_USER" "$TARGET_SSH_KEY" "Target   " || all_ok=false
    test_ssh_connection "$ZDM_HOST"    "$ZDM_ADMIN_USER"    "$ZDM_SSH_KEY"    "ZDM Server" || all_ok=false

    if $all_ok; then
        log_info "All SSH connections successful"
    else
        log_warn "One or more SSH connections failed - discovery may be partial"
    fi
    $all_ok
}

# -----------------------------------------------------------------------
# Run discovery on a single remote server
# Resilient: failures are tracked but do not stop other servers
# -----------------------------------------------------------------------
run_remote_discovery() {
    local server_type="$1"   # source | target | server
    local host="$2"
    local admin_user="$3"
    local key_path="$4"
    local script_name="$5"
    local output_subdir="$6"
    local env_args="$7"      # Extra env vars to pass (e.g. "ORACLE_USER=oracle ORACLE_HOME_OVERRIDE=...")

    local key_expanded
    key_expanded=$(eval echo "$key_path")
    local script_path="${SCRIPT_DIR}/${script_name}"
    local remote_dir="/tmp/zdm_discovery_$$_${server_type}"
    local local_output_dir="${OUTPUT_DIR}/${output_subdir}"

    log_section "Running ${server_type} Discovery: ${host}"
    SERVER_STATUS["$server_type"]="IN_PROGRESS"

    # --- Verify key exists ---
    if [ ! -f "$key_expanded" ]; then
        log_error "SSH key not found: $key_expanded (${key_path})"
        log_error "Set ${server_type^^}_SSH_KEY to the correct path and retry"
        SERVER_STATUS["$server_type"]="FAILED"
        ((DISCOVERY_ERRORS++))
        return 1
    fi

    # --- Verify local script exists ---
    if [ ! -f "$script_path" ]; then
        log_error "Discovery script not found: $script_path"
        SERVER_STATUS["$server_type"]="FAILED"
        ((DISCOVERY_ERRORS++))
        return 1
    fi

    # --- Create remote temp directory and run script ---
    log_info "Creating remote directory: $remote_dir"
    local mkdir_output
    mkdir_output=$(ssh $SSH_OPTS -i "$key_expanded" "${admin_user}@${host}" \
        "mkdir -p $remote_dir && echo MKDIR_OK" 2>&1)
    local mkdir_exit=$?
    if [ $mkdir_exit -ne 0 ] || ! echo "$mkdir_output" | grep -q "MKDIR_OK"; then
        log_error "Failed to create remote directory on ${host}: $mkdir_output"
        SERVER_STATUS["$server_type"]="FAILED"
        ((DISCOVERY_ERRORS++))
        return 1
    fi

    log_info "Executing discovery script on ${host}..."
    # Use bash -l (login shell) with cd prepended to ensure correct working directory.
    # The cd is injected as the FIRST command so bash -l's profile sourcing cannot
    # override the working directory with cd commands from .bash_profile.
    local ssh_env_args="${env_args}"
    $VERBOSE && ssh_env_args="${ssh_env_args} VERBOSE=true"

    local run_output
    run_output=$(ssh $SSH_OPTS -i "$key_expanded" "${admin_user}@${host}" \
        "mkdir -p $remote_dir && ${ssh_env_args} bash -l -s" \
        < <(echo "cd '${remote_dir}'" ; cat "$script_path") 2>&1)
    local run_exit=$?

    if [ $run_exit -ne 0 ]; then
        log_warn "Discovery script returned exit code $run_exit on ${host}"
        log_warn "Script output (last 20 lines):"
        echo "$run_output" | tail -20 | while IFS= read -r line; do log_warn "  $line"; done
        # Continue - output files may still have been written
    else
        log_info "Discovery script completed on ${host}"
        $VERBOSE && echo "$run_output" | tail -10 | while IFS= read -r line; do log_debug "  $line"; done
    fi

    # --- List remote directory before collecting (diagnostic) ---
    log_info "Listing remote output directory: $remote_dir"
    local dir_list_output
    dir_list_output=$(ssh $SSH_OPTS -i "$key_expanded" "${admin_user}@${host}" \
        "ls -lh '${remote_dir}/' 2>/dev/null || echo 'DIRECTORY NOT FOUND OR EMPTY'" 2>&1)
    local dir_list_exit=$?
    if [ $dir_list_exit -ne 0 ]; then
        log_warn "Could not list remote directory: $dir_list_output"
    else
        while IFS= read -r line; do
            log_info "  [remote] $line"
        done <<< "$dir_list_output"
    fi

    # --- Check if output files were created ---
    local file_count
    file_count=$(ssh $SSH_OPTS -i "$key_expanded" "${admin_user}@${host}" \
        "ls ${remote_dir}/*.txt ${remote_dir}/*.json 2>/dev/null | wc -l" 2>&1 | tr -d ' ')
    if [ "${file_count:-0}" -eq 0 ] 2>/dev/null; then
        log_error "No output files found in ${remote_dir} on ${host}"
        log_error "The discovery script may have failed. Check verbose output for details."
        SERVER_STATUS["$server_type"]="FAILED"
        ((DISCOVERY_ERRORS++))
        # Cleanup remote dir
        ssh $SSH_OPTS -i "$key_expanded" "${admin_user}@${host}" "rm -rf $remote_dir" 2>&1 | \
            while IFS= read -r l; do log_debug "  [cleanup] $l"; done || true
        return 1
    fi

    # --- Create local output directory ---
    mkdir -p "$local_output_dir"
    log_info "Collecting output files to: $local_output_dir"

    # --- SCP output files - do NOT suppress stderr ---
    local scp_output
    scp_output=$(scp $SSH_OPTS -i "$key_expanded" \
        "${admin_user}@${host}:${remote_dir}/*.txt" \
        "${admin_user}@${host}:${remote_dir}/*.json" \
        "$local_output_dir/" 2>&1)
    local scp_exit=$?

    if [ $scp_exit -ne 0 ]; then
        log_error "SCP transfer failed (exit code: $scp_exit)"
        log_error "SCP output: $scp_output"
        SERVER_STATUS["$server_type"]="FAILED"
        ((DISCOVERY_ERRORS++))
        # Cleanup remote dir
        ssh $SSH_OPTS -i "$key_expanded" "${admin_user}@${host}" "rm -rf $remote_dir" 2>&1 | \
            while IFS= read -r l; do log_debug "  [cleanup] $l"; done || true
        return 1
    fi

    log_info "Files collected successfully"
    $VERBOSE && ls -lh "$local_output_dir/" | while IFS= read -r l; do log_debug "  $l"; done

    # --- Cleanup remote temp directory ---
    local cleanup_output
    cleanup_output=$(ssh $SSH_OPTS -i "$key_expanded" "${admin_user}@${host}" \
        "rm -rf '$remote_dir' && echo CLEANUP_OK" 2>&1)
    if echo "$cleanup_output" | grep -q "CLEANUP_OK"; then
        log_debug "Remote temp directory cleaned up"
    else
        log_warn "Remote cleanup may have failed: $cleanup_output"
    fi

    SERVER_STATUS["$server_type"]="SUCCESS"
    log_info "${server_type} discovery: COMPLETE"
    return 0
}

# -----------------------------------------------------------------------
# Log current configuration (non-exiting, for use in main body)
# -----------------------------------------------------------------------
log_config_summary() {
    log_section "Discovery Configuration - ORADB"
    log_info "Run by       : $(whoami) on $(hostname)"
    log_info "Script dir   : $SCRIPT_DIR"
    log_info "Repo root    : $REPO_ROOT"
    log_info "Output dir   : $OUTPUT_DIR"
    log_info ""
    log_info "Source       : ${SOURCE_ADMIN_USER}@${SOURCE_HOST}  (key: $SOURCE_SSH_KEY)"
    log_info "Target       : ${TARGET_ADMIN_USER}@${TARGET_HOST}  (key: $TARGET_SSH_KEY)"
    log_info "ZDM Server   : ${ZDM_ADMIN_USER}@${ZDM_HOST}  (key: $ZDM_SSH_KEY)"
    log_info ""
    log_info "Oracle user  : $ORACLE_USER"
    log_info "ZDM user     : $ZDM_USER"
    if [ -n "$SOURCE_REMOTE_ORACLE_HOME" ]; then
        log_info "Source ORACLE_HOME override : $SOURCE_REMOTE_ORACLE_HOME"
    fi
    if [ -n "$SOURCE_REMOTE_ORACLE_SID" ]; then
        log_info "Source ORACLE_SID override  : $SOURCE_REMOTE_ORACLE_SID"
    fi
    if [ -n "$TARGET_REMOTE_ORACLE_HOME" ]; then
        log_info "Target ORACLE_HOME override : $TARGET_REMOTE_ORACLE_HOME"
    fi
    if [ -n "$TARGET_REMOTE_ORACLE_SID" ]; then
        log_info "Target ORACLE_SID override  : $TARGET_REMOTE_ORACLE_SID"
    fi
    if [ -n "$ZDM_REMOTE_ZDM_HOME" ]; then
        log_info "ZDM_HOME override           : $ZDM_REMOTE_ZDM_HOME"
    fi
}

# -----------------------------------------------------------------------
# Print final summary
# -----------------------------------------------------------------------
print_summary() {
    log_section "Discovery Summary"

    for server_type in source target server; do
        local status="${SERVER_STATUS[$server_type]}"
        case "$status" in
            SUCCESS)     log_info "  ✓ ${server_type^} discovery  : $status" ;;
            FAILED)      log_error " ✗ ${server_type^} discovery  : $status" ;;
            NOT_STARTED) log_warn "  - ${server_type^} discovery  : $status (skipped)" ;;
            *)           log_warn "  ? ${server_type^} discovery  : $status" ;;
        esac
    done

    log_info ""
    if [ $DISCOVERY_ERRORS -eq 0 ]; then
        log_info "All discoveries completed successfully."
    else
        log_warn "$DISCOVERY_ERRORS server(s) failed. Partial results available."
        log_warn "Review errors above and re-run for failed servers."
    fi

    log_info ""
    log_info "Output directory: $OUTPUT_DIR"
    if [ -d "$OUTPUT_DIR" ]; then
        log_info "Collected files:"
        find "$OUTPUT_DIR" -name "*.txt" -o -name "*.json" 2>/dev/null | sort | \
            while IFS= read -r f; do
                log_info "  $(ls -lh "$f" 2>/dev/null | awk '{print $5, $9}' || echo "$f")"
            done
    fi

    log_info ""
    log_info "Next Step: Proceed to Step 1 (Discovery Questionnaire)"
    log_info "  Review discovery outputs in: $OUTPUT_DIR"
    log_info "  Then run: prompts/Phase10-Migration/ZDM/Step1-Discovery-Questionnaire.prompt.md"
}

# -----------------------------------------------------------------------
# Build environment args string for remote execution
# -----------------------------------------------------------------------
build_source_env_args() {
    local args="ORACLE_USER='${ORACLE_USER}'"
    [ -n "$SOURCE_REMOTE_ORACLE_HOME" ] && args="${args} ORACLE_HOME_OVERRIDE='${SOURCE_REMOTE_ORACLE_HOME}'"
    [ -n "$SOURCE_REMOTE_ORACLE_SID"  ] && args="${args} ORACLE_SID_OVERRIDE='${SOURCE_REMOTE_ORACLE_SID}'"
    echo "$args "
}

build_target_env_args() {
    local args="ORACLE_USER='${ORACLE_USER}'"
    [ -n "$TARGET_REMOTE_ORACLE_HOME" ] && args="${args} ORACLE_HOME_OVERRIDE='${TARGET_REMOTE_ORACLE_HOME}'"
    [ -n "$TARGET_REMOTE_ORACLE_SID"  ] && args="${args} ORACLE_SID_OVERRIDE='${TARGET_REMOTE_ORACLE_SID}'"
    echo "$args "
}

build_zdm_env_args() {
    # Pass SOURCE_HOST and TARGET_HOST to the ZDM server discovery for connectivity testing
    local args="ZDM_USER='${ZDM_USER}' ORACLE_USER='${ORACLE_USER}'"
    args="${args} SOURCE_HOST='${SOURCE_HOST}'"
    args="${args} TARGET_HOST='${TARGET_HOST}'"
    [ -n "$ZDM_REMOTE_ZDM_HOME"  ] && args="${args} ZDM_HOME_OVERRIDE='${ZDM_REMOTE_ZDM_HOME}'"
    [ -n "$ZDM_REMOTE_JAVA_HOME" ] && args="${args} JAVA_HOME_OVERRIDE='${ZDM_REMOTE_JAVA_HOME}'"
    echo "$args "
}

# -----------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------
main() {
    echo -e "${BOLD}"
    echo "  =================================================================="
    echo "  ZDM Discovery Orchestration"
    echo "  Project: ${DATABASE_NAME}"
    echo "  $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "  =================================================================="
    echo -e "${RESET}"

    log_config_summary
    run_ssh_key_diagnostic
    validate_prerequisites

    # Create output directory structure
    mkdir -p "${OUTPUT_DIR}/source" "${OUTPUT_DIR}/target" "${OUTPUT_DIR}/server"
    log_info "Output directories created under: $OUTPUT_DIR"

    if $TEST_ONLY; then
        log_section "Connectivity Test Mode"
        test_all_connections
        log_info "Test-only mode complete. Exiting without running discovery."
        exit 0
    fi

    # --- Run discovery on each server (independently; failures don't stop others) ---

    run_remote_discovery \
        "source" \
        "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$SOURCE_SSH_KEY" \
        "zdm_source_discovery.sh" \
        "source" \
        "$(build_source_env_args)" || log_warn "Source discovery failed - continuing with remaining servers"

    run_remote_discovery \
        "target" \
        "$TARGET_HOST" "$TARGET_ADMIN_USER" "$TARGET_SSH_KEY" \
        "zdm_target_discovery.sh" \
        "target" \
        "$(build_target_env_args)" || log_warn "Target discovery failed - continuing with remaining servers"

    run_remote_discovery \
        "server" \
        "$ZDM_HOST" "$ZDM_ADMIN_USER" "$ZDM_SSH_KEY" \
        "zdm_server_discovery.sh" \
        "server" \
        "$(build_zdm_env_args)" || log_warn "ZDM server discovery failed"

    print_summary

    if [ $DISCOVERY_ERRORS -gt 0 ]; then
        exit 1
    fi
    exit 0
}

main "$@"
