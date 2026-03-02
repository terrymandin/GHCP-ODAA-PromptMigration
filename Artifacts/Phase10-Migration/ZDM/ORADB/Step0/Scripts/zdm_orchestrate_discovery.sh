#!/bin/bash
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration
# =============================================================================
# zdm_orchestrate_discovery.sh
# ZDM Migration - Master Orchestration Script
# Project: ORADB
#
# PURPOSE: Orchestrates discovery across source DB, target DB, and ZDM
#          jumpbox server by copying and executing discovery scripts remotely.
#          Collects all results into the local Artifacts directory.
#
# USAGE:   bash zdm_orchestrate_discovery.sh [options]
#   Options:
#     -h, --help     Show help message and exit
#     -c, --config   Show current configuration and exit
#     -t, --test     Test SSH connectivity to all servers and exit
#     -v, --verbose  Enable verbose output (passes -v to SSH/SCP)
#
# SCRIPT LOCATION:
#   Artifacts/Phase10-Migration/ZDM/ORADB/Step0/Scripts/
#
# OUTPUT DIRECTORY (auto-calculated):
#   Artifacts/Phase10-Migration/ZDM/ORADB/Step0/Discovery/
#
# =============================================================================

set -u

# ---------------------------------------------------------------------------
# Colour / logging  (NOTE: log_raw is NOT defined here — orchestrator uses
# log_info/log_warn/log_error/log_section/log_debug ONLY)
# ---------------------------------------------------------------------------
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

VERBOSE=false

log_info()    { echo -e "${GREEN}[INFO]${RESET}  $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${RESET} $*"; }
log_section() { echo -e "\n${CYAN}${BOLD}=== $* ===${RESET}"; }
log_debug()   { $VERBOSE && echo -e "[DEBUG] $*"; }

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Navigate up 6 levels: Scripts -> Step0 -> ORADB -> ZDM -> Phase10-Migration -> Artifacts -> RepoRoot
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../../../.." && pwd)"
DATABASE_NAME="ORADB"
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/Artifacts/Phase10-Migration/ZDM/${DATABASE_NAME}/Step0/Discovery}"

# ---------------------------------------------------------------------------
# Default configuration (override via environment variables or zdm-env)
# ---------------------------------------------------------------------------

# Server hostnames
SOURCE_HOST="${SOURCE_HOST:-10.1.0.11}"
TARGET_HOST="${TARGET_HOST:-10.0.1.160}"
ZDM_HOST="${ZDM_HOST:-10.1.0.8}"

# SSH admin users per server
SOURCE_ADMIN_USER="${SOURCE_ADMIN_USER:-azureuser}"
TARGET_ADMIN_USER="${TARGET_ADMIN_USER:-opc}"
ZDM_ADMIN_USER="${ZDM_ADMIN_USER:-azureuser}"

# Application users
ORACLE_USER="${ORACLE_USER:-oracle}"
ZDM_USER="${ZDM_USER:-zdmuser}"

# SSH keys per security domain
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-~/.ssh/odaa.pem}"
TARGET_SSH_KEY="${TARGET_SSH_KEY:-~/.ssh/odaa.pem}"
ZDM_SSH_KEY="${ZDM_SSH_KEY:-~/.ssh/zdm.pem}"

# Optional Oracle/ZDM path overrides (blank = auto-detect on remote server)
SOURCE_REMOTE_ORACLE_HOME="${SOURCE_REMOTE_ORACLE_HOME:-}"
SOURCE_ORACLE_SID="${SOURCE_ORACLE_SID:-}"
TARGET_REMOTE_ORACLE_HOME="${TARGET_REMOTE_ORACLE_HOME:-}"
TARGET_ORACLE_SID="${TARGET_ORACLE_SID:-}"
ZDM_REMOTE_ZDM_HOME="${ZDM_REMOTE_ZDM_HOME:-}"
ZDM_REMOTE_JAVA_HOME="${ZDM_REMOTE_JAVA_HOME:-}"

# ---------------------------------------------------------------------------
# Functions: show_help and show_config  (ONLY called from argument parsing)
# ---------------------------------------------------------------------------
show_help() {
    cat <<EOF

Usage: $(basename "$0") [options]

Options:
  -h, --help     Show this help message and exit
  -c, --config   Display current configuration and exit
  -t, --test     Test SSH connectivity to all servers and exit
  -v, --verbose  Enable verbose SSH/SCP output

Environment variable overrides:
  SOURCE_HOST, TARGET_HOST, ZDM_HOST
  SOURCE_ADMIN_USER, TARGET_ADMIN_USER, ZDM_ADMIN_USER
  ORACLE_USER, ZDM_USER
  SOURCE_SSH_KEY, TARGET_SSH_KEY, ZDM_SSH_KEY
  SOURCE_REMOTE_ORACLE_HOME, SOURCE_ORACLE_SID
  TARGET_REMOTE_ORACLE_HOME, TARGET_ORACLE_SID
  ZDM_REMOTE_ZDM_HOME, ZDM_REMOTE_JAVA_HOME
  OUTPUT_DIR  (override collection directory)

Example:
  SOURCE_SSH_KEY=~/.ssh/mykey.pem bash $(basename "$0") -v
EOF
    exit 0
}

show_config() {
    cat <<EOF

=== Current Configuration (ORADB) ===

SERVER HOSTNAMES
  SOURCE_HOST:             ${SOURCE_HOST}
  TARGET_HOST:             ${TARGET_HOST}
  ZDM_HOST:                ${ZDM_HOST}

SSH ADMIN USERS
  SOURCE_ADMIN_USER:       ${SOURCE_ADMIN_USER}
  TARGET_ADMIN_USER:       ${TARGET_ADMIN_USER}
  ZDM_ADMIN_USER:          ${ZDM_ADMIN_USER}

APPLICATION USERS
  ORACLE_USER:             ${ORACLE_USER}
  ZDM_USER:                ${ZDM_USER}

SSH KEYS
  SOURCE_SSH_KEY:          ${SOURCE_SSH_KEY}
  TARGET_SSH_KEY:          ${TARGET_SSH_KEY}
  ZDM_SSH_KEY:             ${ZDM_SSH_KEY}

PATH OVERRIDES (blank = auto-detect)
  SOURCE_REMOTE_ORACLE_HOME: ${SOURCE_REMOTE_ORACLE_HOME:-<auto-detect>}
  SOURCE_ORACLE_SID:         ${SOURCE_ORACLE_SID:-<auto-detect>}
  TARGET_REMOTE_ORACLE_HOME: ${TARGET_REMOTE_ORACLE_HOME:-<auto-detect>}
  TARGET_ORACLE_SID:         ${TARGET_ORACLE_SID:-<auto-detect>}
  ZDM_REMOTE_ZDM_HOME:       ${ZDM_REMOTE_ZDM_HOME:-<auto-detect>}
  ZDM_REMOTE_JAVA_HOME:      ${ZDM_REMOTE_JAVA_HOME:-<auto-detect>}

PATHS
  SCRIPT_DIR:              ${SCRIPT_DIR}
  REPO_ROOT:               ${REPO_ROOT}
  OUTPUT_DIR:              ${OUTPUT_DIR}

EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing  (the ONLY place show_help/show_config may be called)
# ---------------------------------------------------------------------------
TEST_ONLY=false
for arg in "$@"; do
    case "$arg" in
        -h|--help)    show_help ;;
        -c|--config)  show_config ;;
        -t|--test)    TEST_ONLY=true ;;
        -v|--verbose) VERBOSE=true ;;
    esac
done

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=15 -o BatchMode=yes"
$VERBOSE && SSH_OPTS="$SSH_OPTS -v"

# ---------------------------------------------------------------------------
# Expand tilde in SSH key paths
# ---------------------------------------------------------------------------
expand_path() {
    local path="$1"
    echo "${path/#\~/$HOME}"
}

SOURCE_SSH_KEY_EXPANDED="$(expand_path "$SOURCE_SSH_KEY")"
TARGET_SSH_KEY_EXPANDED="$(expand_path "$TARGET_SSH_KEY")"
ZDM_SSH_KEY_EXPANDED="$(expand_path "$ZDM_SSH_KEY")"

# ---------------------------------------------------------------------------
# Upfront SSH key diagnostic
# ---------------------------------------------------------------------------
upfront_ssh_key_diagnostic() {
    log_section "SSH Key Diagnostic"
    log_info "Running as user: $(whoami)  (home: $HOME)"

    log_info "SSH keys found in ~/.ssh/:"
    if [ -d "$HOME/.ssh" ]; then
        local found_keys=false
        for f in "$HOME/.ssh/"*.pem "$HOME/.ssh/"*.key "$HOME/.ssh/id_"*; do
            [ -f "$f" ] && { log_info "  $f"; found_keys=true; }
        done
        $found_keys || log_warn "  No .pem or .key files found in $HOME/.ssh/"
    else
        log_warn "  ~/.ssh directory does not exist for $(whoami)"
    fi

    for var_name in SOURCE_SSH_KEY TARGET_SSH_KEY ZDM_SSH_KEY; do
        local raw_val; raw_val="$(eval echo "\$$var_name")"
        local expanded_val; expanded_val="$(expand_path "$raw_val")"
        if [ -f "$expanded_val" ]; then
            log_info "  $var_name: $expanded_val  [FOUND]"
        else
            log_warn "  $var_name: $expanded_val  [MISSING] — set ${var_name} to the correct path"
        fi
    done
}

upfront_ssh_key_diagnostic

# ---------------------------------------------------------------------------
# Prerequisites check
# ---------------------------------------------------------------------------
validate_prerequisites() {
    log_section "Prerequisites"
    local failed=false
    for cmd in ssh scp; do
        command -v "$cmd" &>/dev/null && log_info "$cmd: found" || { log_error "$cmd: NOT found"; failed=true; }
    done
    for key_path in "$SOURCE_SSH_KEY_EXPANDED" "$TARGET_SSH_KEY_EXPANDED" "$ZDM_SSH_KEY_EXPANDED"; do
        [ -f "$key_path" ] && log_info "Key file: $key_path  [OK]" || \
            log_warn "Key file not found: $key_path (will fail on SSH)"
    done
    $failed && { log_error "Required tools missing. Aborting."; exit 1; }
    log_info "Prerequisites OK"
}

# ---------------------------------------------------------------------------
# SSH connectivity test
# ---------------------------------------------------------------------------
test_single_connection() {
    local label="$1" host="$2" user="$3" key_path="$4"
    log_info "Testing $label: ${user}@${host} (key: $key_path)"
    local output
    output=$(ssh $SSH_OPTS -i "$key_path" "${user}@${host}" "echo CONNECTED" 2>&1)
    local rc=$?
    if [ $rc -eq 0 ] && echo "$output" | grep -q "CONNECTED"; then
        log_info "  $label: SUCCESS"
        return 0
    else
        log_error "  $label: FAILED (exit $rc)"
        log_error "  SSH output: $output"
        return 1
    fi
}

test_all_connections() {
    log_section "SSH Connectivity Tests"
    local failed=false
    test_single_connection "Source DB"  "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$SOURCE_SSH_KEY_EXPANDED" || failed=true
    test_single_connection "Target DB"  "$TARGET_HOST" "$TARGET_ADMIN_USER" "$TARGET_SSH_KEY_EXPANDED" || failed=true
    test_single_connection "ZDM Server" "$ZDM_HOST"    "$ZDM_ADMIN_USER"    "$ZDM_SSH_KEY_EXPANDED"    || failed=true
    $failed && log_warn "One or more connectivity tests failed" && return 1
    log_info "All connectivity tests passed"
    return 0
}

# ---------------------------------------------------------------------------
# Run discovery on a single server
# ---------------------------------------------------------------------------
run_discovery() {
    local label="$1"
    local host="$2"
    local admin_user="$3"
    local key_path="$4"
    local script_path="$5"
    local output_subdir="$6"
    local env_args="${7:-}"  # Extra env vars to pass (e.g., SOURCE_HOST=... TARGET_HOST=...)

    log_section "Running ${label} Discovery"

    if [ ! -f "$script_path" ]; then
        log_error "Discovery script not found: $script_path"
        return 1
    fi

    local remote_dir="/tmp/zdm_discovery_$$_${label// /_}"
    local local_dir="${OUTPUT_DIR}/${output_subdir}"
    mkdir -p "$local_dir"

    # Create temp dir and execute discovery script using login shell
    # cd is prepended to the piped content so it runs after bash -l profiles source
    log_info "Executing ${label} discovery on ${admin_user}@${host}..."
    local exec_output exec_rc
    exec_output=$(
        ssh $SSH_OPTS -i "$key_path" "${admin_user}@${host}" \
            "mkdir -p ${remote_dir} && ${env_args}bash -l -s" \
        < <(echo "cd '${remote_dir}'" ; cat "$script_path") 2>&1
    )
    exec_rc=$?

    if [ $exec_rc -ne 0 ]; then
        log_error "${label} discovery script returned exit code $exec_rc"
        log_error "SSH/script output: $exec_output"
        # Continue — attempt to collect any partial output
    else
        log_info "${label} discovery script completed (exit 0)"
    fi

    # List remote directory before collecting files
    log_info "Listing remote temp directory ${remote_dir} on ${host}:"
    local ls_output ls_rc
    ls_output=$(ssh $SSH_OPTS -i "$key_path" "${admin_user}@${host}" \
        "ls -la '${remote_dir}/' 2>&1" 2>&1)
    ls_rc=$?
    if [ $ls_rc -eq 0 ]; then
        while IFS= read -r line; do
            log_info "  $line"
        done <<< "$ls_output"
    else
        log_info "  Could not list remote directory (exit $ls_rc): $ls_output"
    fi

    # Collect output files via SCP
    log_info "Collecting output files from ${host}:${remote_dir}/ to ${local_dir}/"
    local scp_output scp_rc
    scp_output=$(scp $SSH_OPTS -i "$key_path" \
        "${admin_user}@${host}:${remote_dir}/*.txt" "${local_dir}/" 2>&1)
    scp_rc=$?
    [ $scp_rc -ne 0 ] && { log_error "SCP of .txt files failed (exit $scp_rc): $scp_output"; }

    scp_output=$(scp $SSH_OPTS -i "$key_path" \
        "${admin_user}@${host}:${remote_dir}/*.json" "${local_dir}/" 2>&1)
    scp_rc=$?
    [ $scp_rc -ne 0 ] && { log_error "SCP of .json files failed (exit $scp_rc): $scp_output"; }

    # Verify files were collected
    local collected
    collected=$(ls -1 "${local_dir}"/*.txt "${local_dir}"/*.json 2>/dev/null | wc -l)
    if [ "$collected" -gt 0 ]; then
        log_info "${label}: Collected ${collected} output file(s) to ${local_dir}/"
        ls -la "${local_dir}/"
        return 0
    else
        log_error "${label}: No output files collected from remote server"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    log_section "ZDM Discovery Orchestration — ORADB"
    log_info "Script directory: $SCRIPT_DIR"
    log_info "Repository root:  $REPO_ROOT"
    log_info "Output directory: $OUTPUT_DIR"
    log_info "Started at:       $(date)"

    validate_prerequisites

    if $TEST_ONLY; then
        test_all_connections
        local rc=$?
        [ $rc -eq 0 ] && log_info "All connectivity tests passed. Run without -t to execute discovery." \
                       || log_warn "Some connectivity tests failed. Fix SSH access before running discovery."
        exit $rc
    fi

    # Create output directories
    mkdir -p "${OUTPUT_DIR}/source" "${OUTPUT_DIR}/target" "${OUTPUT_DIR}/server"

    # Track results
    declare -A RESULTS
    RESULTS["source"]="NOT_RUN"
    RESULTS["target"]="NOT_RUN"
    RESULTS["server"]="NOT_RUN"

    # -----------------------------------------------------------------------
    # Source DB discovery
    # -----------------------------------------------------------------------
    local src_env_args=""
    [ -n "$SOURCE_REMOTE_ORACLE_HOME" ] && src_env_args+="ORACLE_HOME_OVERRIDE='${SOURCE_REMOTE_ORACLE_HOME}' "
    [ -n "$SOURCE_ORACLE_SID" ]          && src_env_args+="ORACLE_SID_OVERRIDE='${SOURCE_ORACLE_SID}' "
    src_env_args+="ORACLE_USER='${ORACLE_USER}' "

    if run_discovery \
        "Source DB" "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$SOURCE_SSH_KEY_EXPANDED" \
        "${SCRIPT_DIR}/zdm_source_discovery.sh" "source" "$src_env_args"; then
        RESULTS["source"]="SUCCESS"
    else
        RESULTS["source"]="FAILED"
        log_warn "Source discovery failed — continuing with remaining servers"
    fi

    # -----------------------------------------------------------------------
    # Target DB discovery
    # -----------------------------------------------------------------------
    local tgt_env_args=""
    [ -n "$TARGET_REMOTE_ORACLE_HOME" ] && tgt_env_args+="ORACLE_HOME_OVERRIDE='${TARGET_REMOTE_ORACLE_HOME}' "
    [ -n "$TARGET_ORACLE_SID" ]          && tgt_env_args+="ORACLE_SID_OVERRIDE='${TARGET_ORACLE_SID}' "
    tgt_env_args+="ORACLE_USER='${ORACLE_USER}' "

    if run_discovery \
        "Target DB" "$TARGET_HOST" "$TARGET_ADMIN_USER" "$TARGET_SSH_KEY_EXPANDED" \
        "${SCRIPT_DIR}/zdm_target_discovery.sh" "target" "$tgt_env_args"; then
        RESULTS["target"]="SUCCESS"
    else
        RESULTS["target"]="FAILED"
        log_warn "Target discovery failed — continuing with remaining servers"
    fi

    # -----------------------------------------------------------------------
    # ZDM server discovery
    # Pass SOURCE_HOST and TARGET_HOST for connectivity tests inside the script
    # -----------------------------------------------------------------------
    local zdm_env_args="SOURCE_HOST='${SOURCE_HOST}' TARGET_HOST='${TARGET_HOST}' ZDM_USER='${ZDM_USER}' "
    [ -n "$ZDM_REMOTE_ZDM_HOME" ]  && zdm_env_args+="ZDM_HOME_OVERRIDE='${ZDM_REMOTE_ZDM_HOME}' "
    [ -n "$ZDM_REMOTE_JAVA_HOME" ] && zdm_env_args+="JAVA_HOME_OVERRIDE='${ZDM_REMOTE_JAVA_HOME}' "

    if run_discovery \
        "ZDM Server" "$ZDM_HOST" "$ZDM_ADMIN_USER" "$ZDM_SSH_KEY_EXPANDED" \
        "${SCRIPT_DIR}/zdm_server_discovery.sh" "server" "$zdm_env_args"; then
        RESULTS["server"]="SUCCESS"
    else
        RESULTS["server"]="FAILED"
        log_warn "ZDM server discovery failed"
    fi

    # -----------------------------------------------------------------------
    # Final summary
    # -----------------------------------------------------------------------
    log_section "Orchestration Complete"
    log_info "Results:"
    log_info "  Source DB  : ${RESULTS["source"]}"
    log_info "  Target DB  : ${RESULTS["target"]}"
    log_info "  ZDM Server : ${RESULTS["server"]}"
    log_info ""
    log_info "Output directory: $OUTPUT_DIR"
    log_info "  source/  :" && ls -1 "${OUTPUT_DIR}/source/" 2>/dev/null | while read -r f; do log_info "    $f"; done
    log_info "  target/  :" && ls -1 "${OUTPUT_DIR}/target/" 2>/dev/null | while read -r f; do log_info "    $f"; done
    log_info "  server/  :" && ls -1 "${OUTPUT_DIR}/server/" 2>/dev/null | while read -r f; do log_info "    $f"; done
    log_info ""
    log_info "Completed at: $(date)"

    local success_count=0
    for k in source target server; do
        [ "${RESULTS[$k]}" = "SUCCESS" ] && ((success_count++)) || true
    done

    if [ $success_count -eq 3 ]; then
        log_info "All 3 server discoveries SUCCEEDED."
        log_info "Next step: Proceed to Step 1 — Discovery Questionnaire"
        exit 0
    elif [ $success_count -gt 0 ]; then
        log_warn "${success_count}/3 server discoveries succeeded. Review errors above before proceeding."
        exit 1
    else
        log_error "All server discoveries FAILED. Check SSH connectivity and key paths."
        exit 2
    fi
}

main "$@"
