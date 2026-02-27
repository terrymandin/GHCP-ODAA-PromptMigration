#!/bin/bash
# =============================================================================
# ZDM Discovery Orchestration Script
# Project: ORADB
# Generated for: Oracle ZDM Migration - Step 0
#
# Purpose: Orchestrate discovery across source DB, target DB, and ZDM server.
#
# Usage:
#   ./zdm_orchestrate_discovery.sh             Run full discovery
#   ./zdm_orchestrate_discovery.sh -h          Show help
#   ./zdm_orchestrate_discovery.sh -c          Show configuration and exit
#   ./zdm_orchestrate_discovery.sh -t          Test connectivity only (no discovery)
#   ./zdm_orchestrate_discovery.sh -v          Verbose mode (detailed SSH output)
#
# Prerequisites:
#   - SSH access from this machine to SOURCE, TARGET, and ZDM servers
#   - Discovery scripts alongside this orchestrator:
#       zdm_source_discovery.sh
#       zdm_target_discovery.sh
#       zdm_server_discovery.sh
# =============================================================================

set -o nounset
set -o pipefail

# =============================================================================
# USER CONFIGURATION
# Edit these defaults or override via environment variables before running.
# =============================================================================

# Server hostnames / IPs
SOURCE_HOST="${SOURCE_HOST:-10.1.0.11}"
TARGET_HOST="${TARGET_HOST:-10.0.1.160}"
ZDM_HOST="${ZDM_HOST:-10.1.0.8}"

# SSH/Admin users for each server (Linux admin with sudo)
SOURCE_ADMIN_USER="${SOURCE_ADMIN_USER:-azureuser}"
TARGET_ADMIN_USER="${TARGET_ADMIN_USER:-opc}"
ZDM_ADMIN_USER="${ZDM_ADMIN_USER:-azureuser}"

# SSH key paths (separate keys per security domain)
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-~/.ssh/odaa.pem}"
TARGET_SSH_KEY="${TARGET_SSH_KEY:-~/.ssh/odaa.pem}"
ZDM_SSH_KEY="${ZDM_SSH_KEY:-~/.ssh/zdm.pem}"

# Application users
ORACLE_USER="${ORACLE_USER:-oracle}"
ZDM_USER="${ZDM_USER:-zdmuser}"

# Optional Oracle path overrides (leave blank for auto-detection)
SOURCE_REMOTE_ORACLE_HOME="${SOURCE_REMOTE_ORACLE_HOME:-}"
SOURCE_REMOTE_ORACLE_SID="${SOURCE_REMOTE_ORACLE_SID:-}"
TARGET_REMOTE_ORACLE_HOME="${TARGET_REMOTE_ORACLE_HOME:-}"
TARGET_REMOTE_ORACLE_SID="${TARGET_REMOTE_ORACLE_SID:-}"
ZDM_REMOTE_ZDM_HOME="${ZDM_REMOTE_ZDM_HOME:-}"
ZDM_REMOTE_JAVA_HOME="${ZDM_REMOTE_JAVA_HOME:-}"

# =============================================================================
# RUNTIME DEFAULTS (do not edit below unless necessary)
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATABASE_NAME="ORADB"
VERBOSE=false
TEST_ONLY=false

# Calculate repository root: Scripts → Step0 → ORADB → ZDM → Phase10-Migration → Artifacts → RepoRoot
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../../.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/Artifacts/Phase10-Migration/ZDM/${DATABASE_NAME}/Step0/Discovery}"

# SSH options base
SSH_BASE_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=15 -o BatchMode=yes"

# Track success/failure
declare -A SERVER_STATUS
SERVER_STATUS["source"]="not_run"
SERVER_STATUS["target"]="not_run"
SERVER_STATUS["server"]="not_run"

# =============================================================================
# COLORS & LOGGING
# =============================================================================
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_debug()   { "$VERBOSE" && echo -e "${BLUE}[DEBUG]${NC} $*" || true; }
log_section() {
    local line="========================================================================"
    echo -e "\n${CYAN}${line}${NC}"
    echo -e "${CYAN}  $*${NC}"
    echo -e "${CYAN}${line}${NC}"
}

# =============================================================================
# HELPER: SSH OPTIONS
# =============================================================================
build_ssh_opts() {
    local key_path="$1"
    local opts="$SSH_BASE_OPTS -i $key_path"
    "$VERBOSE" && opts="$opts -v"
    echo "$opts"
}

# =============================================================================
# UPFRONT SSH KEY DIAGNOSTIC
# =============================================================================
diagnose_ssh_keys() {
    log_section "SSH KEY DIAGNOSTIC"
    log_info "Running as user: $(whoami)  Home: $HOME"

    log_info "PEM/KEY files found in ~/.ssh/:"
    local ssh_dir="$HOME/.ssh"
    if [ -d "$ssh_dir" ]; then
        local keys_found
        keys_found=$(find "$ssh_dir" -maxdepth 1 \( -name '*.pem' -o -name '*.key' -o -name 'id_*' \) 2>/dev/null)
        if [ -n "$keys_found" ]; then
            echo "$keys_found" | while read -r k; do
                log_info "  Found: $k"
            done
        else
            log_warn "  No .pem or .key files found in $ssh_dir"
        fi
    else
        log_warn "~/.ssh directory does not exist at: $ssh_dir"
    fi

    # Check each configured key
    local key_vars=("SOURCE_SSH_KEY:$SOURCE_SSH_KEY" "TARGET_SSH_KEY:$TARGET_SSH_KEY" "ZDM_SSH_KEY:$ZDM_SSH_KEY")
    for pair in "${key_vars[@]}"; do
        local var_name="${pair%%:*}"
        local raw_path="${pair#*:}"
        local expanded_path="${raw_path/#\~/$HOME}"
        if [ -f "$expanded_path" ]; then
            log_info "  $var_name resolved to: $expanded_path  [EXISTS]"
        else
            log_error "  $var_name resolved to: $expanded_path  [MISSING]"
            log_error "    Override: export $var_name=<correct_path>"
        fi
    done
}

# =============================================================================
# PREREQUISITES CHECK
# =============================================================================
validate_prerequisites() {
    log_section "VALIDATING PREREQUISITES"
    local errors=0

    # Check required scripts exist
    local scripts=("zdm_source_discovery.sh" "zdm_target_discovery.sh" "zdm_server_discovery.sh")
    for s in "${scripts[@]}"; do
        if [ -f "${SCRIPT_DIR}/${s}" ]; then
            log_info "Script found: $s"
        else
            log_error "Missing script: ${SCRIPT_DIR}/${s}"
            ((errors++)) || true
        fi
    done

    # Check SSH keys resolve
    for pair in "SOURCE:$SOURCE_SSH_KEY" "TARGET:$TARGET_SSH_KEY" "ZDM:$ZDM_SSH_KEY"; do
        local label="${pair%%:*}"
        local raw_path="${pair#*:}"
        local expanded="${raw_path/#\~/$HOME}"
        if [ ! -f "$expanded" ]; then
            log_error "${label} SSH key not found: $expanded"
            log_error "  Set ${label}_SSH_KEY environment variable to the correct path"
            ((errors++)) || true
        fi
    done

    if [ "$errors" -gt 0 ]; then
        log_error "$errors prerequisite(s) failed. Fix before proceeding."
        return 1
    fi
    log_info "All prerequisites satisfied."
}

# =============================================================================
# CONNECTIVITY TESTING
# =============================================================================
test_ssh_connection() {
    local label="$1"
    local host="$2"
    local user="$3"
    local key_path="${4/#\~/$HOME}"
    local ssh_opts
    ssh_opts=$(build_ssh_opts "$key_path")

    log_info "Testing SSH to $label ($user@$host)..."
    local output
    # shellcheck disable=SC2086
    output=$(ssh $ssh_opts "$user@$host" 'echo SSH_OK' 2>&1)
    if echo "$output" | grep -q 'SSH_OK'; then
        log_info "  $label: SSH connection OK"
        return 0
    else
        log_error "  $label: SSH connection FAILED"
        log_error "  Output: $output"
        return 1
    fi
}

test_all_connections() {
    log_section "CONNECTIVITY TESTS"
    local all_ok=true

    test_ssh_connection "SOURCE DB" "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$SOURCE_SSH_KEY" || all_ok=false
    test_ssh_connection "TARGET DB" "$TARGET_HOST" "$TARGET_ADMIN_USER" "$TARGET_SSH_KEY" || all_ok=false
    test_ssh_connection "ZDM SERVER" "$ZDM_HOST" "$ZDM_ADMIN_USER" "$ZDM_SSH_KEY"         || all_ok=false

    if "$all_ok"; then
        log_info "All connectivity tests PASSED."
    else
        log_warn "Some connectivity tests FAILED. Discovery will continue for reachable servers."
    fi
}

# =============================================================================
# REMOTE SCRIPT EXECUTION
# =============================================================================
run_remote_discovery() {
    local label="$1"
    local host="$2"
    local user="$3"
    local key_path="${4/#\~/$HOME}"
    local script_path="$5"
    local output_subdir="$6"   # source / target / server
    local extra_env="${7:-}"   # Optional extra env vars (e.g. "SOURCE_HOST=x TARGET_HOST=y")

    log_section "RUNNING ${label} DISCOVERY"
    log_info "Host: $user@$host"
    log_info "Script: $script_path"

    local ssh_opts
    ssh_opts=$(build_ssh_opts "$key_path")
    local remote_dir="/tmp/zdm_discovery_$$_${output_subdir}"

    # Build env args string for remote execution
    local env_args=""
    env_args="${env_args}ORACLE_USER='${ORACLE_USER}' "
    env_args="${env_args}ZDM_USER='${ZDM_USER}' "
    [ -n "${SOURCE_REMOTE_ORACLE_HOME:-}" ] && env_args="${env_args}SOURCE_REMOTE_ORACLE_HOME='${SOURCE_REMOTE_ORACLE_HOME}' "
    [ -n "${SOURCE_REMOTE_ORACLE_SID:-}" ]  && env_args="${env_args}SOURCE_REMOTE_ORACLE_SID='${SOURCE_REMOTE_ORACLE_SID}' "
    [ -n "${TARGET_REMOTE_ORACLE_HOME:-}" ] && env_args="${env_args}TARGET_REMOTE_ORACLE_HOME='${TARGET_REMOTE_ORACLE_HOME}' "
    [ -n "${TARGET_REMOTE_ORACLE_SID:-}" ]  && env_args="${env_args}TARGET_REMOTE_ORACLE_SID='${TARGET_REMOTE_ORACLE_SID}' "
    [ -n "${ZDM_REMOTE_ZDM_HOME:-}" ]       && env_args="${env_args}ZDM_REMOTE_ZDM_HOME='${ZDM_REMOTE_ZDM_HOME}' "
    [ -n "${ZDM_REMOTE_JAVA_HOME:-}" ]      && env_args="${env_args}ZDM_REMOTE_JAVA_HOME='${ZDM_REMOTE_JAVA_HOME}' "
    [ -n "$extra_env" ]                     && env_args="${env_args}${extra_env} "

    log_info "Creating remote temp directory: $remote_dir"
    # shellcheck disable=SC2086
    local mkdir_output
    mkdir_output=$(ssh $ssh_opts "$user@$host" "mkdir -p '$remote_dir'" 2>&1)
    if [ $? -ne 0 ]; then
        log_error "Failed to create remote directory on $label"
        log_error "SSH output: $mkdir_output"
        SERVER_STATUS["$output_subdir"]="failed"
        return 1
    fi

    log_info "Executing discovery script on $label..."
    # CORRECT pattern: prepend 'cd' so bash -l profile sourcing cannot change directory away from remote_dir
    # shellcheck disable=SC2086
    local exec_output
    exec_output=$(ssh $ssh_opts "$user@$host" \
        "mkdir -p '$remote_dir' && ${env_args}bash -l -s" \
        < <(echo "cd '$remote_dir'" ; cat "$script_path") 2>&1)
    local exec_rc=$?

    if [ $exec_rc -ne 0 ]; then
        log_warn "$label discovery returned exit code $exec_rc (may still have output)"
        log_debug "Remote execution output (last 20 lines): $(echo "$exec_output" | tail -20)"
    else
        log_info "$label discovery script completed successfully"
    fi

    # List remote directory to verify output files before SCP
    log_info "Listing remote output directory: $remote_dir"
    # shellcheck disable=SC2086
    local list_output
    list_output=$(ssh $ssh_opts "$user@$host" "ls -la '$remote_dir'/" 2>&1)
    local list_rc=$?
    if [ $list_rc -ne 0 ]; then
        log_error "Remote directory listing failed — directory may not exist or is empty"
        log_error "Listing output: $list_output"
    else
        log_info "Remote directory contents:"
        echo "$list_output" | while read -r line; do log_raw "  $line"; done
    fi

    # Collect output files to local Artifacts directory
    local local_output_dir="${OUTPUT_DIR}/${output_subdir}"
    mkdir -p "$local_output_dir"
    log_info "Collecting output files to: $local_output_dir"
    # shellcheck disable=SC2086
    local scp_output
    scp_output=$(scp $ssh_opts -r "$user@$host:${remote_dir}/*" "$local_output_dir/" 2>&1)
    local scp_rc=$?
    if [ $scp_rc -ne 0 ]; then
        log_error "$label: SCP collection FAILED (exit code $scp_rc)"
        log_error "SCP output: $scp_output"
        SERVER_STATUS["$output_subdir"]="partial"
    else
        log_info "$label: Output files collected successfully"
        SERVER_STATUS["$output_subdir"]="success"
        ls -la "$local_output_dir/" 2>/dev/null | while read -r line; do log_raw "  $line"; done
    fi

    # Cleanup remote temp directory
    # shellcheck disable=SC2086
    ssh $ssh_opts "$user@$host" "rm -rf '$remote_dir'" 2>/dev/null || true
}

# =============================================================================
# SHOW HELP  (ONLY called from argument parsing — contains exit)
# =============================================================================
show_help() {
    cat <<EOF

ZDM Discovery Orchestration Script - Project: ORADB

Usage:
  $(basename "$0") [OPTIONS]

Options:
  -h, --help      Show this help message and exit
  -c, --config    Display current configuration and exit
  -t, --test      Test SSH connectivity only (no discovery scripts run)
  -v, --verbose   Enable verbose SSH output

Environment Variables (override defaults):
  SOURCE_HOST           Source DB host  (default: 10.1.0.11)
  TARGET_HOST           Target DB host  (default: 10.0.1.160)
  ZDM_HOST              ZDM server host (default: 10.1.0.8)
  SOURCE_ADMIN_USER     SSH user for source  (default: azureuser)
  TARGET_ADMIN_USER     SSH user for target  (default: opc)
  ZDM_ADMIN_USER        SSH user for ZDM     (default: azureuser)
  SOURCE_SSH_KEY        SSH key for source   (default: ~/.ssh/odaa.pem)
  TARGET_SSH_KEY        SSH key for target   (default: ~/.ssh/odaa.pem)
  ZDM_SSH_KEY           SSH key for ZDM      (default: ~/.ssh/zdm.pem)
  ORACLE_USER           Oracle OS user       (default: oracle)
  ZDM_USER              ZDM software owner   (default: zdmuser)
  OUTPUT_DIR            Output directory (default: REPO_ROOT/Artifacts/...)

Oracle Path Overrides (optional — auto-detection used if blank):
  SOURCE_REMOTE_ORACLE_HOME
  SOURCE_REMOTE_ORACLE_SID
  TARGET_REMOTE_ORACLE_HOME
  TARGET_REMOTE_ORACLE_SID
  ZDM_REMOTE_ZDM_HOME
  ZDM_REMOTE_JAVA_HOME

Examples:
  # Run with defaults
  ./$(basename "$0")

  # Override SSH user for target
  TARGET_ADMIN_USER=opc ./$(basename "$0")

  # Test connectivity only
  ./$(basename "$0") -t

  # Verbose mode
  ./$(basename "$0") -v

EOF
    exit 0
}

# =============================================================================
# SHOW CONFIG  (ONLY called from argument parsing — contains exit)
# =============================================================================
show_config() {
    cat <<EOF

ZDM Orchestration Configuration - Project: ORADB
==========================================================
REPO_ROOT:            $REPO_ROOT
OUTPUT_DIR:           $OUTPUT_DIR
SOURCE_HOST:          $SOURCE_HOST
TARGET_HOST:          $TARGET_HOST
ZDM_HOST:             $ZDM_HOST
SOURCE_ADMIN_USER:    $SOURCE_ADMIN_USER  (KEY: $SOURCE_SSH_KEY)
TARGET_ADMIN_USER:    $TARGET_ADMIN_USER  (KEY: $TARGET_SSH_KEY)
ZDM_ADMIN_USER:       $ZDM_ADMIN_USER     (KEY: $ZDM_SSH_KEY)
ORACLE_USER:          $ORACLE_USER
ZDM_USER:             $ZDM_USER

Optional Oracle Home Overrides:
  SOURCE_REMOTE_ORACLE_HOME: ${SOURCE_REMOTE_ORACLE_HOME:-(auto-detect)}
  SOURCE_REMOTE_ORACLE_SID:  ${SOURCE_REMOTE_ORACLE_SID:-(auto-detect)}
  TARGET_REMOTE_ORACLE_HOME: ${TARGET_REMOTE_ORACLE_HOME:-(auto-detect)}
  TARGET_REMOTE_ORACLE_SID:  ${TARGET_REMOTE_ORACLE_SID:-(auto-detect)}
  ZDM_REMOTE_ZDM_HOME:       ${ZDM_REMOTE_ZDM_HOME:-(auto-detect)}
  ZDM_REMOTE_JAVA_HOME:      ${ZDM_REMOTE_JAVA_HOME:-(auto-detect)}
==========================================================
EOF
    exit 0
}

# =============================================================================
# LOG CONFIGURATION (no exit — safe to call from main body)
# =============================================================================
log_config_summary() {
    log_info "PROJECT:          $DATABASE_NAME"
    log_info "REPO_ROOT:        $REPO_ROOT"
    log_info "OUTPUT_DIR:       $OUTPUT_DIR"
    log_info "SOURCE_HOST:      $SOURCE_HOST  (user: $SOURCE_ADMIN_USER, key: $SOURCE_SSH_KEY)"
    log_info "TARGET_HOST:      $TARGET_HOST  (user: $TARGET_ADMIN_USER, key: $TARGET_SSH_KEY)"
    log_info "ZDM_HOST:         $ZDM_HOST     (user: $ZDM_ADMIN_USER, key: $ZDM_SSH_KEY)"
    log_info "ORACLE_USER:      $ORACLE_USER"
    log_info "ZDM_USER:         $ZDM_USER"
    log_info "VERBOSE:          $VERBOSE"
}

# =============================================================================
# FINAL REPORT
# =============================================================================
print_final_report() {
    log_section "DISCOVERY SUMMARY"
    local all_success=true
    for srv in source target server; do
        local status="${SERVER_STATUS[$srv]}"
        case "$status" in
            success) log_info  "  ${srv^^} server:  SUCCESS" ;;
            partial) log_warn  "  ${srv^^} server:  PARTIAL (some files may be missing)" ; all_success=false ;;
            failed)  log_error "  ${srv^^} server:  FAILED" ; all_success=false ;;
            not_run) log_warn  "  ${srv^^} server:  NOT RUN (skipped or connectivity failed)" ; all_success=false ;;
        esac
    done

    echo ""
    log_info "Output directory: $OUTPUT_DIR"
    if [ -d "$OUTPUT_DIR" ]; then
        find "$OUTPUT_DIR" -type f | sort | while read -r f; do
            log_info "  $(basename "$f")"
        done
    fi

    echo ""
    if "$all_success"; then
        log_info "All discovery runs COMPLETED SUCCESSFULLY."
        log_info "Next step: Run Step 1 (Discovery Questionnaire) with the collected outputs."
    else
        log_warn "Discovery completed with some failures. Review errors above."
        log_warn "You can proceed to Step 1 with the successfully collected outputs."
    fi
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    # -------------------------------------------------------------------
    # Argument parsing — the ONLY place show_help and show_config are called
    # -------------------------------------------------------------------
    for arg in "$@"; do
        case "$arg" in
            -h|--help)    show_help    ;;   # exits
            -c|--config)  show_config  ;;   # exits
            -t|--test)    TEST_ONLY=true ;;
            -v|--verbose) VERBOSE=true ;;
            *)
                log_warn "Unknown option: $arg  (use -h for help)"
                ;;
        esac
    done

    log_section "ZDM DISCOVERY ORCHESTRATION  —  Project: $DATABASE_NAME"
    log_info "Start time: $(date)"
    log_info "Script dir: $SCRIPT_DIR"

    # Log config summary (no exit — safe in main body)
    log_config_summary

    # Upfront SSH key diagnostic
    diagnose_ssh_keys

    # Validate prerequisites
    validate_prerequisites || {
        log_error "Pre-flight checks failed. Exiting."
        exit 1
    }

    # Create output directory structure
    mkdir -p "${OUTPUT_DIR}/source" "${OUTPUT_DIR}/target" "${OUTPUT_DIR}/server"
    log_info "Output directories created under: $OUTPUT_DIR"

    # Connectivity tests
    test_all_connections

    if "$TEST_ONLY"; then
        log_info "Test-only mode (-t): skipping discovery script execution."
        exit 0
    fi

    # -------------------------------------------------------------------
    # Run discovery on each server (continue on failure)
    # -------------------------------------------------------------------
    log_section "STARTING SOURCE DATABASE DISCOVERY"
    run_remote_discovery \
        "SOURCE DB" \
        "$SOURCE_HOST" \
        "$SOURCE_ADMIN_USER" \
        "$SOURCE_SSH_KEY" \
        "${SCRIPT_DIR}/zdm_source_discovery.sh" \
        "source" \
        "" \
    || log_warn "Source database discovery encountered errors (continuing)"

    log_section "STARTING TARGET DATABASE DISCOVERY"
    run_remote_discovery \
        "TARGET DB (ODA)" \
        "$TARGET_HOST" \
        "$TARGET_ADMIN_USER" \
        "$TARGET_SSH_KEY" \
        "${SCRIPT_DIR}/zdm_target_discovery.sh" \
        "target" \
        "" \
    || log_warn "Target database discovery encountered errors (continuing)"

    log_section "STARTING ZDM SERVER DISCOVERY"
    # Pass SOURCE_HOST and TARGET_HOST so zdm_server_discovery can test connectivity
    run_remote_discovery \
        "ZDM SERVER" \
        "$ZDM_HOST" \
        "$ZDM_ADMIN_USER" \
        "$ZDM_SSH_KEY" \
        "${SCRIPT_DIR}/zdm_server_discovery.sh" \
        "server" \
        "SOURCE_HOST='${SOURCE_HOST}' TARGET_HOST='${TARGET_HOST}'" \
    || log_warn "ZDM server discovery encountered errors (continuing)"

    print_final_report
    log_info "End time: $(date)"
}

main "$@"
