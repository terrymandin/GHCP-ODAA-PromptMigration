#!/usr/bin/env bash
# =============================================================================
# zdm_orchestrate_discovery.sh
# Phase 10 — ZDM Migration · Step 2: Orchestrate Discovery Across All Servers
#
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration
#
# Runs on the ZDM server as zdmuser. Copies and executes the individual discovery
# scripts on the source, target, and local ZDM server. Collects output files
# into the Artifacts/Phase10-Migration/Step2/Discovery/ directory.
#
# Usage:
#   chmod +x zdm_orchestrate_discovery.sh
#   ./zdm_orchestrate_discovery.sh            # full discovery
#   ./zdm_orchestrate_discovery.sh -t         # connectivity test only
#   ./zdm_orchestrate_discovery.sh -c         # display configuration
#   ./zdm_orchestrate_discovery.sh -h         # help
#   ./zdm_orchestrate_discovery.sh -v         # verbose SSH/SCP output
#
# Run as: zdmuser on the ZDM server
# =============================================================================

# DO NOT use set -e globally — resilient error handling across server failures
set -uo pipefail

# =============================================================================
# USER CONFIGURATION (from zdm-env.md)
# =============================================================================

# Source database server
SOURCE_HOST="${SOURCE_HOST:-10.1.0.11}"
SOURCE_ADMIN_USER="${SOURCE_ADMIN_USER:-azureuser}"
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-${HOME}/.ssh/odaa.pem}"

# Target Oracle Database@Azure server
TARGET_HOST="${TARGET_HOST:-10.0.1.160}"
TARGET_ADMIN_USER="${TARGET_ADMIN_USER:-opc}"
TARGET_SSH_KEY="${TARGET_SSH_KEY:-${HOME}/.ssh/odaa.pem}"

# Oracle database software owner (for running SQL commands via sudo)
ORACLE_USER="${ORACLE_USER:-oracle}"

# ZDM software owner (for running ZDM CLI commands via sudo)
ZDM_USER="${ZDM_USER:-zdmuser}"

# Oracle overrides (optional — leave empty to use auto-detection)
SOURCE_REMOTE_ORACLE_HOME="${SOURCE_REMOTE_ORACLE_HOME:-}"
SOURCE_ORACLE_SID="${SOURCE_ORACLE_SID:-}"
TARGET_REMOTE_ORACLE_HOME="${TARGET_REMOTE_ORACLE_HOME:-}"
TARGET_ORACLE_SID="${TARGET_ORACLE_SID:-}"

# ZDM server overrides (optional)
ZDM_REMOTE_ZDM_HOME="${ZDM_REMOTE_ZDM_HOME:-}"
ZDM_REMOTE_JAVA_HOME="${ZDM_REMOTE_JAVA_HOME:-}"

# ---------------------------------------------------------------------------
# Script locations and output paths
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/Artifacts/Phase10-Migration/Step2/Discovery}"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

# ---------------------------------------------------------------------------
# SSH/SCP options
# ---------------------------------------------------------------------------
SSH_COMMON_OPTS="-o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=15"
VERBOSE_MODE="false"
TEST_ONLY="false"

# ---------------------------------------------------------------------------
# Error tracking
# ---------------------------------------------------------------------------
SERVERS_SUCCESS=()
SERVERS_FAILED=()

# ---------------------------------------------------------------------------
# Color-coded terminal output
# ---------------------------------------------------------------------------
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'  # No Color

log_section() {
    echo ""
    echo -e "${CYAN}${BOLD}============================================================${NC}"
    echo -e "${CYAN}${BOLD}  $*${NC}"
    echo -e "${CYAN}${BOLD}============================================================${NC}"
}

log_info() {
    echo -e "  ${GREEN}[INFO]${NC}  $*"
}

log_warn() {
    echo -e "  ${YELLOW}[WARN]${NC}  $*"
}

log_error() {
    echo -e "  ${RED}[ERROR]${NC} $*"
}

log_debug() {
    [ "${VERBOSE_MODE:-false}" = "true" ] && echo -e "  [DEBUG] $*" || true
}

# ---------------------------------------------------------------------------
# Help and config display (must only be called from argument parsing)
# ---------------------------------------------------------------------------
show_help() {
    echo ""
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help      Show this help message and exit"
    echo "  -c, --config    Display current configuration and exit"
    echo "  -t, --test      Test SSH connectivity only (no discovery)"
    echo "  -v, --verbose   Verbose SSH/SCP output"
    echo ""
    echo "Environment variable overrides:"
    echo "  SOURCE_HOST           Source hostname or IP"
    echo "  SOURCE_ADMIN_USER     Admin user for SSH to source"
    echo "  SOURCE_SSH_KEY        SSH key path for source (empty = use SSH agent)"
    echo "  TARGET_HOST           Target hostname or IP"
    echo "  TARGET_ADMIN_USER     Admin user for SSH to target"
    echo "  TARGET_SSH_KEY        SSH key path for target (empty = use SSH agent)"
    echo "  ORACLE_USER           Oracle software owner (default: oracle)"
    echo "  ZDM_USER              ZDM software owner (default: zdmuser)"
    echo "  OUTPUT_DIR            Override output directory"
    echo ""
    echo "Examples:"
    echo "  ./$(basename "$0")                      # run full discovery"
    echo "  ./$(basename "$0") -t                   # test connectivity only"
    echo "  SOURCE_HOST=10.1.0.11 ./$(basename "$0") -v  # override host, verbose"
    echo ""
    exit 0
}

show_config() {
    echo ""
    echo "=== Current Configuration ==="
    echo "  SOURCE_HOST:           ${SOURCE_HOST}"
    echo "  SOURCE_ADMIN_USER:     ${SOURCE_ADMIN_USER}"
    echo "  SOURCE_SSH_KEY:        ${SOURCE_SSH_KEY:-<not set — using SSH agent>}"
    echo "  TARGET_HOST:           ${TARGET_HOST}"
    echo "  TARGET_ADMIN_USER:     ${TARGET_ADMIN_USER}"
    echo "  TARGET_SSH_KEY:        ${TARGET_SSH_KEY:-<not set — using SSH agent>}"
    echo "  ORACLE_USER:           ${ORACLE_USER}"
    echo "  ZDM_USER:              ${ZDM_USER}"
    echo "  OUTPUT_DIR:            ${OUTPUT_DIR}"
    echo "  SCRIPT_DIR:            ${SCRIPT_DIR}"
    echo "  REPO_ROOT:             ${REPO_ROOT}"
    echo ""
    exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
for arg in "$@"; do
    case "$arg" in
        -h|--help)    show_help ;;
        -c|--config)  show_config ;;
        -t|--test)    TEST_ONLY="true" ;;
        -v|--verbose) VERBOSE_MODE="true" ;;
        *) log_warn "Unknown option: ${arg}" ;;
    esac
done

# Build SSH/SCP option strings (verbose adds -v flag)
if [ "${VERBOSE_MODE}" = "true" ]; then
    SSH_OPTS="${SSH_COMMON_OPTS} -v"
    SCP_OPTS="-o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=15 -v"
else
    SSH_OPTS="${SSH_COMMON_OPTS}"
    SCP_OPTS="-o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=15"
fi

# ---------------------------------------------------------------------------
# SSH key diagnostic — must run BEFORE any connections
# ---------------------------------------------------------------------------
run_ssh_key_diagnostic() {
    log_section "SSH KEY DIAGNOSTIC"

    local current_user
    current_user="$(whoami)"
    local home_dir="$HOME"
    log_info "Running as:   ${current_user} (home: ${home_dir})"

    if [ "${current_user}" != "${ZDM_USER}" ]; then
        log_warn "Script is running as '${current_user}', not '${ZDM_USER}'."
        log_warn "SSH keys should be in /home/${ZDM_USER}/.ssh/ with permissions 600."
        log_warn "Current user's home is ${home_dir} — key paths may not resolve as expected."
    fi

    log_info ""
    log_info "-- SSH key files found in ~/.ssh/ --"
    if [ -d "${home_dir}/.ssh" ]; then
        local found_keys
        found_keys=$(find "${home_dir}/.ssh" -name "*.pem" -o -name "*.key" 2>/dev/null || true)
        if [ -n "${found_keys:-}" ]; then
            echo "${found_keys}" | while read -r kf; do
                local perms
                perms=$(stat -c '%a' "$kf" 2>/dev/null || stat -f '%A' "$kf" 2>/dev/null || echo "unknown")
                log_info "  ${kf}  (permissions: ${perms})"
            done
        else
            log_warn "No .pem or .key files found in ${home_dir}/.ssh/"
        fi
    else
        log_warn "~/.ssh directory not found at ${home_dir}/.ssh"
    fi

    log_info ""
    # Validate SOURCE_SSH_KEY
    if [ -z "${SOURCE_SSH_KEY:-}" ]; then
        log_info "SOURCE_SSH_KEY: not configured — SSH agent or default key will be used for source"
    else
        local expanded_src_key="${SOURCE_SSH_KEY/#\~/$HOME}"
        if [ -f "${expanded_src_key}" ]; then
            log_info "SOURCE_SSH_KEY: ${expanded_src_key} (EXISTS)"
        else
            log_warn "SOURCE_SSH_KEY: ${expanded_src_key} — FILE NOT FOUND"
            log_warn "  Correct with: export SOURCE_SSH_KEY=<path>"
        fi
    fi

    # Validate TARGET_SSH_KEY
    if [ -z "${TARGET_SSH_KEY:-}" ]; then
        log_info "TARGET_SSH_KEY: not configured — SSH agent or default key will be used for target"
    else
        local expanded_tgt_key="${TARGET_SSH_KEY/#\~/$HOME}"
        if [ -f "${expanded_tgt_key}" ]; then
            log_info "TARGET_SSH_KEY: ${expanded_tgt_key} (EXISTS)"
        else
            log_warn "TARGET_SSH_KEY: ${expanded_tgt_key} — FILE NOT FOUND"
            log_warn "  Correct with: export TARGET_SSH_KEY=<path>"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Prerequisites validation
# ---------------------------------------------------------------------------
validate_prerequisites() {
    log_section "VALIDATING PREREQUISITES"

    # Check required scripts exist
    local scripts=("zdm_source_discovery.sh" "zdm_target_discovery.sh" "zdm_server_discovery.sh")
    for script in "${scripts[@]}"; do
        if [ ! -f "${SCRIPT_DIR}/${script}" ]; then
            log_error "Required script not found: ${SCRIPT_DIR}/${script}"
            return 1
        fi
        log_info "Found: ${script}"
    done

    # Create output directories
    mkdir -p "${OUTPUT_DIR}/source" "${OUTPUT_DIR}/target" "${OUTPUT_DIR}/server"
    log_info "Output directory: ${OUTPUT_DIR}"
    return 0
}

# ---------------------------------------------------------------------------
# SSH connectivity test
# ---------------------------------------------------------------------------
test_ssh_connection() {
    local label="$1"
    local host="$2"
    local user="$3"
    local key_path="${4:-}"

    local result
    local captured_output
    local exit_code=0
    captured_output=$(ssh $SSH_OPTS \
        ${key_path:+-i "$key_path"} \
        "${user}@${host}" \
        "hostname" 2>&1) || exit_code=$?

    if [ $exit_code -eq 0 ]; then
        log_info "${label} (${host}): SSH OK — remote hostname: ${captured_output}"
        return 0
    else
        log_error "${label} (${host}): SSH FAILED (exit ${exit_code})"
        log_error "  Captured output: ${captured_output}"
        return 1
    fi
}

test_all_connections() {
    log_section "SSH CONNECTIVITY TESTS"
    local all_ok=0

    test_ssh_connection "SOURCE" "${SOURCE_HOST}" "${SOURCE_ADMIN_USER}" "${SOURCE_SSH_KEY:-}" || all_ok=1
    test_ssh_connection "TARGET" "${TARGET_HOST}" "${TARGET_ADMIN_USER}" "${TARGET_SSH_KEY:-}" || all_ok=1

    if [ $all_ok -eq 0 ]; then
        log_info "All SSH connections successful."
    else
        log_warn "One or more SSH connections failed. Discovery may be partial."
    fi
    return $all_ok
}

# ---------------------------------------------------------------------------
# Run discovery on a remote host
# ---------------------------------------------------------------------------
run_remote_discovery() {
    local label="$1"
    local host="$2"
    local admin_user="$3"
    local key_path="${4:-}"
    local script_path="$5"
    local local_output_dir="$6"
    local env_args="${7:-}"

    local script_name
    script_name="$(basename "$script_path")"
    local remote_dir="/tmp/zdm_discovery_$$"

    log_section "RUNNING ${label} DISCOVERY"
    log_info "Host:         ${host}"
    log_info "Admin user:   ${admin_user}"
    log_info "Script:       ${script_name}"
    log_info "Remote dir:   ${remote_dir}"

    # 1. Create remote temp directory
    local mk_output
    local mk_exit=0
    mk_output=$(ssh $SSH_OPTS ${key_path:+-i "$key_path"} \
        "${admin_user}@${host}" \
        "mkdir -p ${remote_dir} && chmod 700 ${remote_dir} && echo OK" 2>&1) || mk_exit=$?
    if [ $mk_exit -ne 0 ] || [ "${mk_output}" != "OK" ]; then
        log_error "Failed to create remote temp directory on ${host}"
        log_error "  Output: ${mk_output}"
        SERVERS_FAILED+=("${label}")
        return 1
    fi
    log_info "Remote temp directory created."

    # 2. Copy discovery script via SCP
    local scp_output
    local scp_exit=0
    scp_output=$(scp $SCP_OPTS \
        ${key_path:+-i "$key_path"} \
        "$script_path" \
        "${admin_user}@${host}:${remote_dir}/" 2>&1) || scp_exit=$?
    if [ $scp_exit -ne 0 ]; then
        log_error "SCP failed to copy ${script_name} to ${host}:${remote_dir}/"
        log_error "  Captured: ${scp_output}"
        SERVERS_FAILED+=("${label}")
        return 1
    fi
    log_info "Script copied to remote host."

    # 3. Execute discovery script via bash -l (login shell)
    #    cd is prepended to the piped content so bash -l profile sourcing
    #    cannot change the working directory away from remote_dir.
    log_info "Executing ${script_name} on ${host}..."
    local exec_output
    local exec_exit=0
    exec_output=$(ssh $SSH_OPTS ${key_path:+-i "$key_path"} \
        "${admin_user}@${host}" \
        "chmod +x ${remote_dir}/${script_name} && ${env_args}bash -l -s" \
        < <(echo "cd '${remote_dir}'" ; cat "${script_path}") 2>&1) || exec_exit=$?

    if [ $exec_exit -ne 0 ]; then
        log_warn "Discovery script exited with code ${exec_exit} on ${host} — may have partial output"
        log_warn "  Last output: $(echo "${exec_output}" | tail -5)"
    else
        log_info "Discovery script completed successfully."
    fi

    # 4. List remote dir before collecting — makes it visible if files were produced
    log_info "-- Remote directory listing (${remote_dir}) --"
    local ls_output
    local ls_exit=0
    ls_output=$(ssh $SSH_OPTS ${key_path:+-i "$key_path"} \
        "${admin_user}@${host}" \
        "ls -lh ${remote_dir}/ 2>/dev/null || echo 'DIRECTORY_NOT_FOUND'" 2>&1) || ls_exit=$?
    if [ $ls_exit -ne 0 ]; then
        log_info "Could not list remote directory (exit ${ls_exit})"
    else
        echo "${ls_output}" | while IFS= read -r line; do log_info "  ${line}"; done
    fi

    if echo "${ls_output}" | grep -q "DIRECTORY_NOT_FOUND" 2>/dev/null; then
        log_error "Remote temp directory not found after execution — discovery may have failed"
        SERVERS_FAILED+=("${label}")
        return 1
    fi

    # 5. Collect output files via SCP
    mkdir -p "${local_output_dir}"
    local collect_output
    local collect_exit=0
    collect_output=$(scp $SCP_OPTS \
        ${key_path:+-i "$key_path"} \
        "${admin_user}@${host}:${remote_dir}/*.txt" \
        "${admin_user}@${host}:${remote_dir}/*.json" \
        "${local_output_dir}/" 2>&1) || collect_exit=$?

    if [ $collect_exit -ne 0 ]; then
        log_warn "SCP collection encountered issues (exit ${collect_exit})"
        log_warn "  Captured: ${collect_output}"
    fi

    local collected_files
    collected_files=$(ls -1 "${local_output_dir}"/*.txt "${local_output_dir}"/*.json 2>/dev/null || true)
    if [ -n "${collected_files:-}" ]; then
        log_info "Collected output files:"
        echo "${collected_files}" | while IFS= read -r f; do log_info "  ${f}"; done
        SERVERS_SUCCESS+=("${label}")
    else
        log_warn "No output files found in ${local_output_dir}"
        # Partial success — server ran but maybe no files produced
        if [ $exec_exit -eq 0 ]; then
            SERVERS_FAILED+=("${label}")
        else
            SERVERS_FAILED+=("${label}")
        fi
        return 1
    fi

    # 6. Clean up remote temp directory
    ssh $SSH_OPTS ${key_path:+-i "$key_path"} \
        "${admin_user}@${host}" \
        "rm -rf ${remote_dir}" 2>/dev/null || true
    log_info "Remote temp directory cleaned up."
    return 0
}

# ---------------------------------------------------------------------------
# Run local ZDM server discovery
# ---------------------------------------------------------------------------
run_local_discovery() {
    log_section "RUNNING ZDM SERVER DISCOVERY (LOCAL)"

    local script_path="${SCRIPT_DIR}/zdm_server_discovery.sh"
    local local_output_dir="${OUTPUT_DIR}/server"
    local orig_dir="$PWD"

    mkdir -p "${local_output_dir}"

    # Execute from the output directory so files land there directly
    pushd "${local_output_dir}" > /dev/null

    local exec_exit=0
    SOURCE_HOST="${SOURCE_HOST}" \
    TARGET_HOST="${TARGET_HOST}" \
    ZDM_USER="${ZDM_USER}" \
    ${ZDM_REMOTE_ZDM_HOME:+ZDM_HOME="${ZDM_REMOTE_ZDM_HOME}"} \
    ${ZDM_REMOTE_JAVA_HOME:+JAVA_HOME="${ZDM_REMOTE_JAVA_HOME}"} \
        bash "${script_path}" || exec_exit=$?

    popd > /dev/null

    if [ $exec_exit -eq 0 ]; then
        log_info "ZDM server discovery completed."
        SERVERS_SUCCESS+=("ZDM_SERVER")
    else
        log_warn "ZDM server discovery exited with code ${exec_exit} — may have partial output"
        SERVERS_SUCCESS+=("ZDM_SERVER(partial)")
    fi

    local collected
    collected=$(ls -1 "${local_output_dir}"/*.txt "${local_output_dir}"/*.json 2>/dev/null || true)
    if [ -n "${collected:-}" ]; then
        log_info "ZDM server discovery files:"
        echo "${collected}" | while IFS= read -r f; do log_info "  ${f}"; done
    else
        log_warn "No ZDM server discovery files produced"
        SERVERS_FAILED+=("ZDM_SERVER")
    fi
}

# ---------------------------------------------------------------------------
# Print configuration summary (non-exiting, for use in main body)
# ---------------------------------------------------------------------------
log_config_summary() {
    log_section "CONFIGURATION SUMMARY"
    log_info "SOURCE_HOST:           ${SOURCE_HOST}"
    log_info "SOURCE_ADMIN_USER:     ${SOURCE_ADMIN_USER}"
    log_info "SOURCE_SSH_KEY:        ${SOURCE_SSH_KEY:-<not set>}"
    log_info "TARGET_HOST:           ${TARGET_HOST}"
    log_info "TARGET_ADMIN_USER:     ${TARGET_ADMIN_USER}"
    log_info "TARGET_SSH_KEY:        ${TARGET_SSH_KEY:-<not set>}"
    log_info "ORACLE_USER:           ${ORACLE_USER}"
    log_info "ZDM_USER:              ${ZDM_USER}"
    log_info "OUTPUT_DIR:            ${OUTPUT_DIR}"
    log_info "REPO_ROOT:             ${REPO_ROOT}"
    log_info "SCRIPT_DIR:            ${SCRIPT_DIR}"
    log_info "TIMESTAMP:             ${TIMESTAMP}"
}

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------
print_summary() {
    log_section "DISCOVERY SUMMARY"
    echo ""
    echo -e "  ${GREEN}Successful:${NC}"
    if [ ${#SERVERS_SUCCESS[@]} -gt 0 ]; then
        for s in "${SERVERS_SUCCESS[@]}"; do
            echo -e "    ${GREEN}✅ ${s}${NC}"
        done
    else
        echo "    (none)"
    fi
    echo ""
    echo -e "  ${RED}Failed:${NC}"
    if [ ${#SERVERS_FAILED[@]} -gt 0 ]; then
        for s in "${SERVERS_FAILED[@]}"; do
            echo -e "    ${RED}❌ ${s}${NC}"
        done
    else
        echo -e "    ${GREEN}(none)${NC}"
    fi
    echo ""
    log_info "Output directory: ${OUTPUT_DIR}"
    log_info ""
    if [ ${#SERVERS_FAILED[@]} -eq 0 ]; then
        log_info "All servers discovered successfully."
        log_info "Next step: @Phase10-ZDM-Step3-Discovery-Questionnaire"
    else
        log_warn "Some servers failed. Review errors above and retry."
        log_warn "Partial results are saved in ${OUTPUT_DIR}"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    log_section "ZDM ORCHESTRATED DISCOVERY — Phase 10 Step 2"
    log_info "Started:  $(date)"
    log_info "Run as:   $(whoami)@$(hostname)"

    log_config_summary

    # SSH key diagnostic
    run_ssh_key_diagnostic

    # Validate prerequisites
    if ! validate_prerequisites; then
        log_error "Prerequisites validation failed — aborting"
        exit 1
    fi

    # Expand ~ in SSH key paths
    SOURCE_SSH_KEY="${SOURCE_SSH_KEY/#\~/$HOME}"
    TARGET_SSH_KEY="${TARGET_SSH_KEY/#\~/$HOME}"

    # Connectivity test
    test_all_connections || true   # Don't abort on connectivity failure — continue to attempt discovery

    if [ "${TEST_ONLY}" = "true" ]; then
        log_info "Connectivity test complete (--test mode). Exiting."
        exit 0
    fi

    # Build environment args for remote scripts (pass overrides)
    local src_env_args=""
    [ -n "${SOURCE_REMOTE_ORACLE_HOME:-}" ] && src_env_args+="SOURCE_REMOTE_ORACLE_HOME='${SOURCE_REMOTE_ORACLE_HOME}' "
    [ -n "${SOURCE_ORACLE_SID:-}" ]         && src_env_args+="SOURCE_ORACLE_SID='${SOURCE_ORACLE_SID}' "
    src_env_args+="ORACLE_USER='${ORACLE_USER}' "

    local tgt_env_args="ORACLE_USER='${ORACLE_USER}' "
    [ -n "${TARGET_REMOTE_ORACLE_HOME:-}" ] && tgt_env_args+="TARGET_REMOTE_ORACLE_HOME='${TARGET_REMOTE_ORACLE_HOME}' "
    [ -n "${TARGET_ORACLE_SID:-}" ]         && tgt_env_args+="TARGET_ORACLE_SID='${TARGET_ORACLE_SID}' "

    # Run source discovery (continue on failure)
    run_remote_discovery \
        "SOURCE" \
        "${SOURCE_HOST}" \
        "${SOURCE_ADMIN_USER}" \
        "${SOURCE_SSH_KEY:-}" \
        "${SCRIPT_DIR}/zdm_source_discovery.sh" \
        "${OUTPUT_DIR}/source" \
        "${src_env_args}" || true

    # Run target discovery (continue on failure)
    run_remote_discovery \
        "TARGET" \
        "${TARGET_HOST}" \
        "${TARGET_ADMIN_USER}" \
        "${TARGET_SSH_KEY:-}" \
        "${SCRIPT_DIR}/zdm_target_discovery.sh" \
        "${OUTPUT_DIR}/target" \
        "${tgt_env_args}" || true

    # Run local ZDM server discovery (continue on failure)
    run_local_discovery || true

    # Final summary
    print_summary

    # Exit non-zero if any servers failed
    [ ${#SERVERS_FAILED[@]} -eq 0 ] && exit 0 || exit 1
}

main "$@"
