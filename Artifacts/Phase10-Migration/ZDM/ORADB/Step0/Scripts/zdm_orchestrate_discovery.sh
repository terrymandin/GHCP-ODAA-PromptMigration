#!/bin/bash
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration
# ===================================================================================
# zdm_orchestrate_discovery.sh
# ZDM Migration - Master Discovery Orchestration
# Project: ORADB
# ===================================================================================
# Purpose: Orchestrate discovery across source DB, target DB (ODAA), and ZDM server.
#          Copies and executes discovery scripts remotely, then collects results.
#          ALL operations are strictly read-only.
#
# Usage:
#   chmod +x zdm_orchestrate_discovery.sh
#   ./zdm_orchestrate_discovery.sh [-h|--help] [-c|--config] [-t|--test] [-v|--verbose]
#
# Options:
#   -h, --help      Show this help message and exit
#   -c, --config    Show current configuration and exit
#   -t, --test      Test SSH connectivity only (no discovery)
#   -v, --verbose   Enable verbose mode (passed to SSH/SCP for detailed output)
#
# Environment Variable Overrides:
#   SOURCE_HOST, TARGET_HOST, ZDM_HOST          Server IPs/hostnames
#   SOURCE_ADMIN_USER, TARGET_ADMIN_USER, ZDM_ADMIN_USER  SSH admin users
#   SOURCE_SSH_KEY, TARGET_SSH_KEY, ZDM_SSH_KEY  SSH key paths
#   ORACLE_USER, ZDM_USER                        Software owners
#   OUTPUT_DIR                                  Override output directory
#
# ===================================================================================

set -o pipefail

# --------------------------------------------------------------------------
# Color codes
# --------------------------------------------------------------------------
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# --------------------------------------------------------------------------
# Script location and derived paths
# --------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Script is at: Artifacts/Phase10-Migration/ZDM/ORADB/Step0/Scripts/
# Levels up:    Scripts(1) -> Step0(2) -> ORADB(3) -> ZDM(4) -> Phase10-Migration(5) -> Artifacts(6) -> RepoRoot
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../../.." && pwd)"
DATABASE_NAME="ORADB"

# --------------------------------------------------------------------------
# ===========================================
# USER CONFIGURATION (from zdm-env.md)
# ===========================================

# Server hostnames / IPs
SOURCE_HOST="${SOURCE_HOST:-10.1.0.11}"
TARGET_HOST="${TARGET_HOST:-10.0.1.160}"
ZDM_HOST="${ZDM_HOST:-10.1.0.8}"

# SSH/Admin users for each server (Linux admin users with sudo privileges)
SOURCE_ADMIN_USER="${SOURCE_ADMIN_USER:-azureuser}"
TARGET_ADMIN_USER="${TARGET_ADMIN_USER:-opc}"
ZDM_ADMIN_USER="${ZDM_ADMIN_USER:-azureuser}"

# Oracle database software owner (for running SQL commands)
ORACLE_USER="${ORACLE_USER:-oracle}"

# ZDM software owner (for running ZDM CLI commands)
ZDM_USER="${ZDM_USER:-zdmuser}"

# SSH keys (separate keys per security domain)
# Keys must be in ~/.ssh/ under the account running this script (zdmuser recommended)
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-~/.ssh/odaa.pem}"
TARGET_SSH_KEY="${TARGET_SSH_KEY:-~/.ssh/odaa.pem}"
ZDM_SSH_KEY="${ZDM_SSH_KEY:-~/.ssh/zdm.pem}"

# OCI Configuration (non-sensitive identifiers)
OCI_COMPARTMENT_OCID="${OCI_COMPARTMENT_OCID:-ocid1.compartment.oc1..aaaaaaaas4upnqj72dfiivgwvn3uui5gkxo7ng6leeoifucbjiy326urbhmq}"
OCI_CONFIG_PATH="${OCI_CONFIG_PATH:-~/.oci/config}"

# Output directory (calculated from REPO_ROOT; override with OUTPUT_DIR env var)
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/Artifacts/Phase10-Migration/ZDM/${DATABASE_NAME}/Step0/Discovery}"

# --------------------------------------------------------------------------
# Runtime flags
# --------------------------------------------------------------------------
VERBOSE=0
TEST_ONLY=false
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Tracking
declare -A SERVER_STATUS
SERVER_STATUS["source"]="NOT_STARTED"
SERVER_STATUS["target"]="NOT_STARTED"
SERVER_STATUS["server"]="NOT_STARTED"

# --------------------------------------------------------------------------
# Logging helpers (orchestrator uses log_info, log_warn, log_error, log_debug, log_section ONLY)
# NOTE: log_raw must NOT be used here - it is only defined inside the individual discovery scripts
# --------------------------------------------------------------------------
log_info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_debug()   { [ "$VERBOSE" = "1" ] && echo -e "${BLUE}[DEBUG]${NC} $*"; }
log_section() { echo -e "\n${BOLD}${CYAN}=====================================${NC}"; \
                echo -e "${BOLD}${CYAN}  $*${NC}"; \
                echo -e "${BOLD}${CYAN}=====================================${NC}"; }

# --------------------------------------------------------------------------
# Help and config (these exit immediately — ONLY call from arg-parsing block)
# --------------------------------------------------------------------------
show_help() {
    cat <<EOHELP
${BOLD}${CYAN}ZDM Discovery Orchestration Script${NC}
Project: ${DATABASE_NAME}

${BOLD}Usage:${NC}
  $0 [OPTIONS]

${BOLD}Options:${NC}
  -h, --help      Show this help message and exit
  -c, --config    Show current configuration and exit
  -t, --test      Test SSH connectivity only (no discovery)
  -v, --verbose   Enable verbose SSH/SCP output

${BOLD}Configuration:${NC}
  Set environment variables before running to override defaults:
    SOURCE_HOST, TARGET_HOST, ZDM_HOST
    SOURCE_ADMIN_USER, TARGET_ADMIN_USER, ZDM_ADMIN_USER
    SOURCE_SSH_KEY, TARGET_SSH_KEY, ZDM_SSH_KEY
    ORACLE_USER, ZDM_USER
    OUTPUT_DIR

${BOLD}Examples:${NC}
  # Run with defaults from zdm-env.md
  ./zdm_orchestrate_discovery.sh

  # Test connectivity only
  ./zdm_orchestrate_discovery.sh --test

  # Override source host
  SOURCE_HOST=192.168.1.10 ./zdm_orchestrate_discovery.sh

${BOLD}Output:${NC}
  ${OUTPUT_DIR}

${BOLD}Security Notes:${NC}
  - All discovery scripts are READ-ONLY (no DB or OS changes)
  - SSH keys must be in ~/.ssh/ with permissions 600
  - Script should run as zdmuser (keys expected in /home/zdmuser/.ssh/)
EOHELP
    exit 0
}

show_config() {
    # Expand key paths for display
    local src_key_expanded tgt_key_expanded zdm_key_expanded
    src_key_expanded=$(eval echo "$SOURCE_SSH_KEY")
    tgt_key_expanded=$(eval echo "$TARGET_SSH_KEY")
    zdm_key_expanded=$(eval echo "$ZDM_SSH_KEY")

    cat <<EOCONFIG
${BOLD}${CYAN}=== Current Configuration ===${NC}

${BOLD}Project:${NC}         ${DATABASE_NAME}
${BOLD}Repo Root:${NC}       ${REPO_ROOT}
${BOLD}Output Dir:${NC}      ${OUTPUT_DIR}

${BOLD}Source Server:${NC}
  Host:          ${SOURCE_HOST}
  Admin User:    ${SOURCE_ADMIN_USER}
  SSH Key:       ${src_key_expanded}
  Key Exists:    $([ -f "$src_key_expanded" ] && echo "YES" || echo "NO - NOT FOUND")

${BOLD}Target Server (ODAA):${NC}
  Host:          ${TARGET_HOST}
  Admin User:    ${TARGET_ADMIN_USER}
  SSH Key:       ${tgt_key_expanded}
  Key Exists:    $([ -f "$tgt_key_expanded" ] && echo "YES" || echo "NO - NOT FOUND")

${BOLD}ZDM Server:${NC}
  Host:          ${ZDM_HOST}
  Admin User:    ${ZDM_ADMIN_USER}
  SSH Key:       ${zdm_key_expanded}
  Key Exists:    $([ -f "$zdm_key_expanded" ] && echo "YES" || echo "NO - NOT FOUND")

${BOLD}Application Users:${NC}
  Oracle User:   ${ORACLE_USER}
  ZDM User:      ${ZDM_USER}

${BOLD}OCI:${NC}
  Compartment OCID: ${OCI_COMPARTMENT_OCID}
  Config Path:   $(eval echo "$OCI_CONFIG_PATH")
EOCONFIG
    exit 0
}

# --------------------------------------------------------------------------
# SSH key diagnostic (called from main body - does NOT exit)
# --------------------------------------------------------------------------
log_ssh_key_diagnostic() {
    log_section "SSH Key Diagnostic"

    local current_user current_home
    current_user=$(whoami)
    current_home="$HOME"

    log_info "Running as user:    $current_user"
    log_info "Home directory:     $current_home"

    if [ "$current_user" != "$ZDM_USER" ]; then
        log_warn "Script is running as '$current_user', not '$ZDM_USER'."
        log_warn "SSH keys must exist in /home/${ZDM_USER}/.ssh/ (not $current_home/.ssh/) for ZDM operations."
        log_warn "Ensure keys are deployed to zdmuser's home directory with permissions 600."
    fi

    log_info "Scanning ${current_home}/.ssh/ for .pem and .key files:"
    local ssh_keys_found=0
    if [ -d "$current_home/.ssh" ]; then
        while IFS= read -r -d '' key_file; do
            local perms
            perms=$(stat -c '%a' "$key_file" 2>/dev/null)
            log_info "  Found: $key_file (perms: $perms)"
            [ "$perms" != "600" ] && log_warn "    WARN: Permissions should be 600, found $perms"
            ssh_keys_found=$((ssh_keys_found + 1))
        done < <(find "$current_home/.ssh" -name "*.pem" -o -name "*.key" -print0 2>/dev/null)
        [ $ssh_keys_found -eq 0 ] && log_warn "No .pem or .key files found in $current_home/.ssh/"
    else
        log_warn "SSH directory $current_home/.ssh/ does NOT EXIST"
        log_warn "Create it and deploy your SSH keys before running discovery."
    fi

    # Check each configured key
    local src_key_exp tgt_key_exp zdm_key_exp
    src_key_exp=$(eval echo "$SOURCE_SSH_KEY")
    tgt_key_exp=$(eval echo "$TARGET_SSH_KEY")
    zdm_key_exp=$(eval echo "$ZDM_SSH_KEY")

    for config_var_name in SOURCE_SSH_KEY TARGET_SSH_KEY ZDM_SSH_KEY; do
        local key_val key_expanded
        key_val="${!config_var_name}"
        key_expanded=$(eval echo "$key_val")
        if [ -f "$key_expanded" ]; then
            log_info "  $config_var_name: $key_expanded — EXISTS"
        else
            log_warn "  $config_var_name: $key_expanded — MISSING"
            log_warn "    Override with: export $config_var_name=/path/to/key.pem"
        fi
    done
}

# --------------------------------------------------------------------------
# SSH options builder
# --------------------------------------------------------------------------
ssh_opts() {
    local opts="-o StrictHostKeyChecking=no -o ConnectTimeout=15 -o BatchMode=yes"
    [ "$VERBOSE" = "1" ] && opts="$opts -v"
    echo "$opts"
}

# --------------------------------------------------------------------------
# Test SSH connectivity
# --------------------------------------------------------------------------
test_ssh_connection() {
    local host="$1"
    local user="$2"
    local key="$3"
    local label="$4"

    local key_expanded
    key_expanded=$(eval echo "$key")
    local ssh_opts_str
    ssh_opts_str=$(ssh_opts)

    log_info "Testing SSH: ${user}@${host} (key: $key_expanded)"

    local ssh_output
    ssh_output=$(ssh $ssh_opts_str -i "$key_expanded" "${user}@${host}" \
        "echo SSH_OK && hostname" 2>&1)
    local rc=$?

    if [ $rc -eq 0 ] && echo "$ssh_output" | grep -q "SSH_OK"; then
        log_info "  $label: SSH connection SUCCESSFUL"
        return 0
    else
        log_error "  $label: SSH connection FAILED (exit code: $rc)"
        log_error "  SSH output: $ssh_output"
        log_error "  Check: key path '$key_expanded', user '$user', host '$host'"
        return 1
    fi
}

test_all_connections() {
    log_section "Testing SSH Connections"
    local all_ok=0

    test_ssh_connection "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$SOURCE_SSH_KEY" "Source" || all_ok=1
    test_ssh_connection "$TARGET_HOST" "$TARGET_ADMIN_USER" "$TARGET_SSH_KEY" "Target (ODAA)" || all_ok=1
    test_ssh_connection "$ZDM_HOST"    "$ZDM_ADMIN_USER"    "$ZDM_SSH_KEY"    "ZDM Server" || all_ok=1

    if [ $all_ok -ne 0 ]; then
        log_warn "One or more SSH connections failed. Review errors above."
    else
        log_info "All SSH connections successful."
    fi

    return $all_ok
}

# --------------------------------------------------------------------------
# Validate prerequisites
# --------------------------------------------------------------------------
validate_prerequisites() {
    log_section "Validating Prerequisites"
    local errors=0

    # Check required commands
    for cmd in ssh scp; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "Required command not found: $cmd"
            errors=$((errors + 1))
        fi
    done

    # Check discovery scripts exist
    for script in zdm_source_discovery.sh zdm_target_discovery.sh zdm_server_discovery.sh; do
        local script_path="$SCRIPT_DIR/$script"
        if [ ! -f "$script_path" ]; then
            log_error "Discovery script not found: $script_path"
            errors=$((errors + 1))
        fi
    done

    # Check SSH key paths exist
    for config_var_name in SOURCE_SSH_KEY TARGET_SSH_KEY ZDM_SSH_KEY; do
        local key_val key_expanded
        key_val="${!config_var_name}"
        key_expanded=$(eval echo "$key_val")
        if [ ! -f "$key_expanded" ]; then
            log_warn "SSH key not found: $key_expanded (set via $config_var_name)"
        fi
    done

    [ $errors -gt 0 ] && log_error "$errors prerequisite check(s) failed" && return 1

    log_info "All prerequisites validated."
    return 0
}

# --------------------------------------------------------------------------
# Run discovery on a remote server
# --------------------------------------------------------------------------
run_remote_discovery() {
    local host="$1"
    local admin_user="$2"
    local ssh_key="$3"
    local script_name="$4"
    local output_subdir="$5"
    local label="$6"
    local extra_env="${7:-}"   # optional extra env vars for this server

    local key_expanded
    key_expanded=$(eval echo "$ssh_key")
    local ssh_opts_str
    ssh_opts_str=$(ssh_opts)
    local script_path="$SCRIPT_DIR/$script_name"
    local local_output_dir="$OUTPUT_DIR/$output_subdir"
    local remote_dir="/tmp/zdm_discovery_$$_${output_subdir}"

    log_section "Discovering: $label ($host)"
    log_info "Script:      $script_name"
    log_info "Remote dir:  $remote_dir"
    log_info "Output dir:  $local_output_dir"

    mkdir -p "$local_output_dir"

    # Step 1: Create remote temp directory
    log_info "Creating remote temp directory..."
    local mkdir_output
    mkdir_output=$(ssh $ssh_opts_str -i "$key_expanded" "${admin_user}@${host}" \
        "mkdir -p $remote_dir && chmod 700 $remote_dir && echo MKDIR_OK" 2>&1)
    local mkdir_rc=$?
    if [ $mkdir_rc -ne 0 ] || ! echo "$mkdir_output" | grep -q "MKDIR_OK"; then
        log_error "Failed to create remote temp directory on $host"
        log_error "SSH output: $mkdir_output"
        SERVER_STATUS["$output_subdir"]="FAILED"
        return 1
    fi
    log_info "Remote temp directory created."

    # Step 2: Copy discovery script to remote server
    log_info "Copying $script_name to ${admin_user}@${host}:${remote_dir}/"
    local scp_output
    scp_output=$(scp $ssh_opts_str -i "$key_expanded" "$script_path" \
        "${admin_user}@${host}:${remote_dir}/${script_name}" 2>&1)
    local scp_rc=$?
    if [ $scp_rc -ne 0 ]; then
        log_error "SCP to $host failed (exit code: $scp_rc)"
        log_error "SCP output: $scp_output"
        SERVER_STATUS["$output_subdir"]="FAILED"
        return 1
    fi
    log_info "Script copied successfully."

    # Step 3: Make script executable
    local chmod_output
    chmod_output=$(ssh $ssh_opts_str -i "$key_expanded" "${admin_user}@${host}" \
        "chmod +x ${remote_dir}/${script_name} && echo CHMOD_OK" 2>&1)
    if ! echo "$chmod_output" | grep -q "CHMOD_OK"; then
        log_error "Failed to chmod script on $host: $chmod_output"
        SERVER_STATUS["$output_subdir"]="FAILED"
        return 1
    fi

    # Step 4: Execute discovery script using login shell (bash -l -s)
    # cd is prepended to the piped script so it runs in remote_dir after profile is sourced
    log_info "Executing $script_name on $host..."
    local exec_output
    exec_output=$(ssh $ssh_opts_str -i "$key_expanded" "${admin_user}@${host}" \
        "mkdir -p $remote_dir && ${extra_env:+$extra_env }ORACLE_USER=${ORACLE_USER} ZDM_USER=${ZDM_USER} OCI_COMPARTMENT_OCID=${OCI_COMPARTMENT_OCID} bash -l -s" \
        < <(echo "cd '${remote_dir}'" ; cat "$script_path") 2>&1)
    local exec_rc=$?

    if [ $exec_rc -ne 0 ]; then
        log_warn "Discovery script on $host exited with code $exec_rc (partial results may exist)"
        log_warn "Exec output tail: $(echo "$exec_output" | tail -10)"
    else
        log_info "Discovery script completed successfully on $host."
    fi

    # Log script output at debug level
    if [ "$VERBOSE" = "1" ]; then
        echo "$exec_output" | while IFS= read -r line; do
            log_debug "  [REMOTE] $line"
        done
    fi

    # Step 5: List remote directory contents before collecting
    log_info "Listing remote directory contents before collection:"
    local ls_output
    ls_output=$(ssh $ssh_opts_str -i "$key_expanded" "${admin_user}@${host}" \
        "ls -lh ${remote_dir}/" 2>&1)
    local ls_rc=$?
    if [ $ls_rc -eq 0 ]; then
        echo "$ls_output" | while IFS= read -r line; do
            log_info "  $line"
        done
    else
        log_info "  Remote directory not found or listing failed: $ls_output"
    fi

    # Step 6: Collect output files
    log_info "Collecting output files from $host..."
    local collect_output
    collect_output=$(scp $ssh_opts_str -i "$key_expanded" \
        "${admin_user}@${host}:${remote_dir}/*.txt" \
        "${admin_user}@${host}:${remote_dir}/*.json" \
        "$local_output_dir/" 2>&1)
    local collect_rc=$?

    if [ $collect_rc -ne 0 ]; then
        log_warn "SCP collection from $host completed with warnings: $collect_output"
        # Check if any files actually arrived
        local file_count
        file_count=$(ls -1 "$local_output_dir"/*.txt "$local_output_dir"/*.json 2>/dev/null | wc -l)
        if [ "$file_count" -gt 0 ]; then
            log_info "  $file_count file(s) collected despite SCP warnings."
            SERVER_STATUS["$output_subdir"]="PARTIAL"
        else
            log_error "  No output files collected from $host"
            SERVER_STATUS["$output_subdir"]="FAILED"
            return 1
        fi
    else
        log_info "Output files collected to: $local_output_dir"
        ls -lh "$local_output_dir"/*.txt "$local_output_dir"/*.json 2>/dev/null | \
            while IFS= read -r line; do log_info "  $line"; done
        SERVER_STATUS["$output_subdir"]="SUCCESS"
    fi

    # Step 7: Cleanup remote temp directory
    log_info "Cleaning up remote temp directory..."
    local rm_output
    rm_output=$(ssh $ssh_opts_str -i "$key_expanded" "${admin_user}@${host}" \
        "rm -rf '${remote_dir}' && echo RM_OK" 2>&1)
    if echo "$rm_output" | grep -q "RM_OK"; then
        log_debug "Remote temp directory cleaned up."
    else
        log_warn "Remote cleanup may have failed: $rm_output"
    fi

    return 0
}

# --------------------------------------------------------------------------
# Print final summary
# --------------------------------------------------------------------------
print_summary() {
    log_section "Discovery Summary"

    local total=0 success=0 failed=0 partial=0

    for server in source target server; do
        local status="${SERVER_STATUS[$server]}"
        total=$((total + 1))
        case "$status" in
            SUCCESS) success=$((success + 1))
                log_info "  $server: ${GREEN}SUCCESS${NC}" ;;
            PARTIAL) partial=$((partial + 1))
                log_warn "  $server: PARTIAL (some files may be missing)" ;;
            FAILED)  failed=$((failed + 1))
                log_error "  $server: FAILED" ;;
            *) log_warn "  $server: $status" ;;
        esac
    done

    echo ""
    log_info "Results: $success/$total succeeded, $failed failed, $partial partial"
    log_info "Output directory: $OUTPUT_DIR"

    if [ $success -gt 0 ]; then
        echo ""
        log_info "Collected files:"
        find "$OUTPUT_DIR" -name "*.txt" -o -name "*.json" 2>/dev/null | sort | \
            while IFS= read -r f; do
                log_info "  $(basename "$(dirname "$f")")/$(basename "$f")"
            done
    fi

    echo ""
    if [ $failed -eq 0 ] && [ $partial -eq 0 ]; then
        log_info "${GREEN}All servers discovered successfully.${NC}"
        log_info "Next step: Proceed to Step 1 - Discovery Questionnaire"
        log_info "           prompts/Phase10-Migration/ZDM/Step1-Discovery-Questionnaire.prompt.md"
        return 0
    elif [ $success -gt 0 ]; then
        log_warn "Discovery partially complete ($failed failed)."
        log_warn "Review errors above and re-run for failed servers, or proceed with partial data."
        return 1
    else
        log_error "All discovery attempts failed. Review SSH key configuration and connectivity."
        return 2
    fi
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
main() {
    # ---- Argument parsing (ONLY place show_help / show_config are called) ----
    for arg in "$@"; do
        case "$arg" in
            -h|--help)    show_help ;;    # exits
            -c|--config)  show_config ;;  # exits
            -t|--test)    TEST_ONLY=true ;;
            -v|--verbose) VERBOSE=1 ;;
            *) log_warn "Unknown option: $arg (use -h for help)" ;;
        esac
    done

    # ---- Banner ----
    echo -e "${BOLD}${CYAN}"
    echo "========================================================================"
    echo "  ZDM Discovery Orchestration"
    echo "  Project: ${DATABASE_NAME}"
    echo "  Date:    $(date)"
    echo "  Output:  ${OUTPUT_DIR}"
    echo "========================================================================"
    echo -e "${NC}"

    # ---- SSH key diagnostic (non-exiting, for visibility) ----
    log_ssh_key_diagnostic

    # ---- Validate prerequisites ----
    validate_prerequisites || {
        log_error "Prerequisite validation failed. Resolve errors above before continuing."
        exit 1
    }

    # ---- Test connections ----
    test_all_connections
    local conn_rc=$?

    if [ "$TEST_ONLY" = "true" ]; then
        log_info "Connectivity test complete (--test mode). Exiting without running discovery."
        exit $conn_rc
    fi

    if [ $conn_rc -ne 0 ]; then
        log_warn "Some SSH connections failed. Discovery will continue but failed servers will be skipped."
    fi

    # ---- Create output directory structure ----
    log_section "Preparing Output Directories"
    mkdir -p "$OUTPUT_DIR/source" "$OUTPUT_DIR/target" "$OUTPUT_DIR/server"
    log_info "Output directories created under: $OUTPUT_DIR"

    # ---- Run source database discovery ----
    run_remote_discovery \
        "$SOURCE_HOST" \
        "$SOURCE_ADMIN_USER" \
        "$SOURCE_SSH_KEY" \
        "zdm_source_discovery.sh" \
        "source" \
        "Source Database (${SOURCE_HOST})" \
        "" || \
        log_warn "Source discovery failed - continuing with remaining servers"

    # ---- Run target database discovery ----
    run_remote_discovery \
        "$TARGET_HOST" \
        "$TARGET_ADMIN_USER" \
        "$TARGET_SSH_KEY" \
        "zdm_target_discovery.sh" \
        "target" \
        "Target Database ODAA (${TARGET_HOST})" \
        "" || \
        log_warn "Target discovery failed - continuing with remaining servers"

    # ---- Run ZDM server discovery (pass source/target hosts for connectivity testing) ----
    run_remote_discovery \
        "$ZDM_HOST" \
        "$ZDM_ADMIN_USER" \
        "$ZDM_SSH_KEY" \
        "zdm_server_discovery.sh" \
        "server" \
        "ZDM Server (${ZDM_HOST})" \
        "SOURCE_HOST='${SOURCE_HOST}' TARGET_HOST='${TARGET_HOST}'" || \
        log_warn "ZDM server discovery failed"

    # ---- Final summary ----
    print_summary
    local summary_rc=$?

    exit $summary_rc
}

main "$@"
