#!/bin/bash
# =============================================================================
# zdm_orchestrate_discovery.sh
# Phase 10 — ZDM Migration · Step 2: Discovery Orchestration
#
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration
#
# Master script that runs on the ZDM server as zdmuser. Copies the three
# discovery scripts to their respective servers via SCP, executes them via SSH
# (login shell), and collects the output files back to the local output directory.
#
# Usage:
#   bash zdm_orchestrate_discovery.sh            # full discovery
#   bash zdm_orchestrate_discovery.sh -t         # connectivity test only
#   bash zdm_orchestrate_discovery.sh -c         # show config and exit
#   bash zdm_orchestrate_discovery.sh -h         # show help and exit
#   bash zdm_orchestrate_discovery.sh -v         # verbose SSH output
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

# ---------------------------------------------------------------------------
# Environment Variables with defaults (from zdm-env.md)
# ---------------------------------------------------------------------------
SOURCE_HOST="${SOURCE_HOST:-10.1.0.11}"
TARGET_HOST="${TARGET_HOST:-10.0.1.160}"
SOURCE_ADMIN_USER="${SOURCE_ADMIN_USER:-azureuser}"
TARGET_ADMIN_USER="${TARGET_ADMIN_USER:-opc}"
ORACLE_USER="${ORACLE_USER:-oracle}"
ZDM_USER="${ZDM_USER:-zdmuser}"
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-${HOME}/.ssh/odaa.pem}"   # set empty to use SSH agent
TARGET_SSH_KEY="${TARGET_SSH_KEY:-${HOME}/.ssh/odaa.pem}"   # set empty to use SSH agent

# Optional Oracle env overrides (passed through to discovery scripts)
SOURCE_REMOTE_ORACLE_HOME="${SOURCE_REMOTE_ORACLE_HOME:-}"
SOURCE_ORACLE_SID="${SOURCE_ORACLE_SID:-}"
TARGET_REMOTE_ORACLE_HOME="${TARGET_REMOTE_ORACLE_HOME:-}"
TARGET_ORACLE_SID="${TARGET_ORACLE_SID:-}"

# Output directory (create relative to SCRIPT_DIR/../Discovery)
OUTPUT_BASE="${OUTPUT_BASE:-${SCRIPT_DIR}/../Discovery}"
REMOTE_TMP_DIR="${REMOTE_TMP_DIR:-/tmp/zdm_discovery_${TIMESTAMP}}"

# Script paths
SOURCE_DISCOVERY_SCRIPT="${SCRIPT_DIR}/zdm_source_discovery.sh"
TARGET_DISCOVERY_SCRIPT="${SCRIPT_DIR}/zdm_target_discovery.sh"
SERVER_DISCOVERY_SCRIPT="${SCRIPT_DIR}/zdm_server_discovery.sh"

# ---------------------------------------------------------------------------
# SSH / SCP options
# ---------------------------------------------------------------------------
SSH_BASE_OPTS="-o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=15"
SCP_BASE_OPTS="-o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=15"
VERBOSE=false

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log_info()  { printf '[%s] INFO:  %s\n' "$(date +%H:%M:%S)" "$*" ; }
log_warn()  { printf '[%s] WARN:  %s\n' "$(date +%H:%M:%S)" "$*" ; }
log_error() { printf '[%s] ERROR: %s\n' "$(date +%H:%M:%S)" "$*" >&2 ; }
log_ok()    { printf '[%s] OK:    %s\n' "$(date +%H:%M:%S)" "$*" ; }

# ---------------------------------------------------------------------------
# show_help — called only from argument parsing, exits immediately
# ---------------------------------------------------------------------------
show_help() {
    cat << 'HELPEOF'
Usage: bash zdm_orchestrate_discovery.sh [OPTIONS]

Options:
  -h    Show this help message and exit
  -c    Display current configuration and exit
  -t    Run connectivity tests only (ping + port checks), then exit
  -v    Enable verbose SSH output

Environment variables (override defaults):
  SOURCE_HOST, TARGET_HOST
  SOURCE_ADMIN_USER, TARGET_ADMIN_USER
  SOURCE_SSH_KEY, TARGET_SSH_KEY          (empty = use SSH agent / default key)
  ORACLE_USER, ZDM_USER
  SOURCE_REMOTE_ORACLE_HOME, SOURCE_ORACLE_SID
  TARGET_REMOTE_ORACLE_HOME, TARGET_ORACLE_SID
  OUTPUT_BASE                             (default: ../Discovery)

Examples:
  bash zdm_orchestrate_discovery.sh
  SOURCE_SSH_KEY="" TARGET_SSH_KEY="" bash zdm_orchestrate_discovery.sh   # use SSH agent
  bash zdm_orchestrate_discovery.sh -t                                     # connectivity only
HELPEOF
    exit 0
}

# ---------------------------------------------------------------------------
# show_config — called only from argument parsing, exits immediately
# ---------------------------------------------------------------------------
show_config() {
    echo "=== ZDM Discovery Orchestrator — Current Configuration ==="
    echo "  SOURCE_HOST        : ${SOURCE_HOST}"
    echo "  SOURCE_ADMIN_USER  : ${SOURCE_ADMIN_USER}"
    echo "  SOURCE_SSH_KEY     : ${SOURCE_SSH_KEY:-<SSH agent / default key>}"
    echo "  SOURCE_ORACLE_HOME : ${SOURCE_REMOTE_ORACLE_HOME:-<auto-detect>}"
    echo "  SOURCE_ORACLE_SID  : ${SOURCE_ORACLE_SID:-<auto-detect>}"
    echo ""
    echo "  TARGET_HOST        : ${TARGET_HOST}"
    echo "  TARGET_ADMIN_USER  : ${TARGET_ADMIN_USER}"
    echo "  TARGET_SSH_KEY     : ${TARGET_SSH_KEY:-<SSH agent / default key>}"
    echo "  TARGET_ORACLE_HOME : ${TARGET_REMOTE_ORACLE_HOME:-<auto-detect>}"
    echo "  TARGET_ORACLE_SID  : ${TARGET_ORACLE_SID:-<auto-detect>}"
    echo ""
    echo "  ORACLE_USER        : ${ORACLE_USER}"
    echo "  ZDM_USER           : ${ZDM_USER}"
    echo "  OUTPUT_BASE        : ${OUTPUT_BASE}"
    echo "  REMOTE_TMP_DIR     : ${REMOTE_TMP_DIR}"
    echo "==========================================================="
    exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
CONNECTIVITY_TEST_ONLY=false
while getopts "hctv" opt; do
    case "${opt}" in
        h) show_help ;;
        c) show_config ;;
        t) CONNECTIVITY_TEST_ONLY=true ;;
        v) VERBOSE=true ;;
        *) echo "Unknown option: -${OPTARG}"; show_help ;;
    esac
done

# Build SSH/SCP options (append -v only if verbose)
SSH_OPTS="${SSH_BASE_OPTS}"
SCP_OPTS="${SCP_BASE_OPTS}"
if [[ "${VERBOSE}" == "true" ]]; then
    SSH_OPTS="${SSH_OPTS} -v"
    SCP_OPTS="${SCP_OPTS} -v"
fi

# ---------------------------------------------------------------------------
# Startup diagnostics
# ---------------------------------------------------------------------------
log_info "============================================================"
log_info " ZDM Step 2 — Discovery Orchestrator"
log_info " Started  : $(date)"
log_info " Run as   : $(whoami)@$(hostname)"
log_info " Home dir : ${HOME}"
log_info "============================================================"

# 1. Warn if not running as zdmuser
if [[ "$(whoami)" != "${ZDM_USER}" ]]; then
    log_warn "Running as '$(whoami)', not '${ZDM_USER}'. ZDM server discovery user guard will fail."
    log_warn "Switch to ${ZDM_USER} first: sudo su - ${ZDM_USER}"
fi

# 2. Check for PEM/key files in ~/.ssh/
log_info ""
log_info "SSH key check (~/.ssh/):"
pem_files="$(find "${HOME}/.ssh" -name '*.pem' -o -name '*.key' 2>/dev/null)"
if [[ -z "${pem_files}" ]]; then
    log_warn "No .pem or .key files found in ${HOME}/.ssh/"
else
    while IFS= read -r f; do
        perms="$(stat -c '%a' "${f}" 2>/dev/null || stat -f '%A' "${f}" 2>/dev/null)"
        log_info "  ${f}  [perms: ${perms}]"
    done <<< "${pem_files}"
fi

# 3. Report SSH key variable status
log_info ""
log_info "SSH key variable status:"
if [[ -z "${SOURCE_SSH_KEY}" ]]; then
    log_info "  SOURCE_SSH_KEY: empty — will use SSH agent / default key for source"
else
    if [[ -f "${SOURCE_SSH_KEY}" ]]; then
        log_ok   "  SOURCE_SSH_KEY: ${SOURCE_SSH_KEY} (file exists)"
    else
        log_warn "  SOURCE_SSH_KEY: ${SOURCE_SSH_KEY} (FILE NOT FOUND)"
    fi
fi
if [[ -z "${TARGET_SSH_KEY}" ]]; then
    log_info "  TARGET_SSH_KEY: empty — will use SSH agent / default key for target"
else
    if [[ -f "${TARGET_SSH_KEY}" ]]; then
        log_ok   "  TARGET_SSH_KEY: ${TARGET_SSH_KEY} (file exists)"
    else
        log_warn "  TARGET_SSH_KEY: ${TARGET_SSH_KEY} (FILE NOT FOUND)"
    fi
fi

# ---------------------------------------------------------------------------
# Verify required scripts exist
# ---------------------------------------------------------------------------
log_info ""
log_info "Verifying discovery scripts:"
SCRIPTS_OK=true
for script_path in "${SOURCE_DISCOVERY_SCRIPT}" "${TARGET_DISCOVERY_SCRIPT}" "${SERVER_DISCOVERY_SCRIPT}"; do
    if [[ -f "${script_path}" ]]; then
        log_ok   "  Found: ${script_path}"
    else
        log_error "  MISSING: ${script_path}"
        SCRIPTS_OK=false
    fi
done
if [[ "${SCRIPTS_OK}" != "true" ]]; then
    log_error "One or more required discovery scripts are missing. Cannot continue."
    exit 1
fi

# ---------------------------------------------------------------------------
# Helper: quick connectivity test (ping + port check)
# ---------------------------------------------------------------------------
test_connectivity() {
    local label="$1"
    local host="$2"
    local key_path="$3"
    local admin_user="$4"
    local overall=0

    log_info "--- ${label} connectivity test (${host}) ---"

    # Ping
    ping -c 3 -W 3 "${host}" &>/dev/null
    if [[ $? -eq 0 ]]; then
        log_ok "  Ping ${host}: OK"
    else
        log_warn "  Ping ${host}: FAILED"
        overall=1
    fi

    # Port 22
    timeout 5 bash -c "echo >/dev/tcp/${host}/22" 2>/dev/null
    if [[ $? -eq 0 ]]; then
        log_ok "  Port 22 (${host}): OPEN"
    else
        log_warn "  Port 22 (${host}): CLOSED or FILTERED"
        overall=1
    fi

    # Port 1521
    timeout 5 bash -c "echo >/dev/tcp/${host}/1521" 2>/dev/null
    if [[ $? -eq 0 ]]; then
        log_ok "  Port 1521 (${host}): OPEN"
    else
        log_warn "  Port 1521 (${host}): CLOSED or FILTERED"
        overall=1
    fi

    # SSH test
    ssh_out="$(ssh ${SSH_OPTS} ${key_path:+-i "${key_path}"} "${admin_user}@${host}" \
        "hostname" 2>&1)"
    ssh_exit=$?
    if [[ ${ssh_exit} -eq 0 ]]; then
        log_ok "  SSH ${admin_user}@${host}: OK (hostname=${ssh_out})"
    else
        log_warn "  SSH ${admin_user}@${host}: FAILED (exit ${ssh_exit}): ${ssh_out}"
        overall=1
    fi

    return ${overall}
}

log_info ""
log_info "Running connectivity pre-checks..."
SOURCE_CONN_OK=0; TARGET_CONN_OK=0
test_connectivity "SOURCE" "${SOURCE_HOST}" "${SOURCE_SSH_KEY}" "${SOURCE_ADMIN_USER}" \
    && SOURCE_CONN_OK=1 || SOURCE_CONN_OK=0
test_connectivity "TARGET" "${TARGET_HOST}" "${TARGET_SSH_KEY}" "${TARGET_ADMIN_USER}" \
    && TARGET_CONN_OK=1 || TARGET_CONN_OK=0

if [[ "${CONNECTIVITY_TEST_ONLY}" == "true" ]]; then
    log_info ""
    log_info "Connectivity test complete (-t flag set — skipping discovery)."
    log_info "  Source: $([ "${SOURCE_CONN_OK}" -eq 1 ] && echo "OK" || echo "ISSUES DETECTED")"
    log_info "  Target: $([ "${TARGET_CONN_OK}" -eq 1 ] && echo "OK" || echo "ISSUES DETECTED")"
    exit 0
fi

# ---------------------------------------------------------------------------
# Create local output directories
# ---------------------------------------------------------------------------
mkdir -p "${OUTPUT_BASE}/source" "${OUTPUT_BASE}/target" "${OUTPUT_BASE}/server"
log_info ""
log_info "Output directories created: ${OUTPUT_BASE}/{source,target,server}"

# Track success/failure per server
SOURCE_SUCCESS=false
TARGET_SUCCESS=false
SERVER_SUCCESS=false

# ---------------------------------------------------------------------------
# Helper: run discovery on a remote server
# ---------------------------------------------------------------------------
run_remote_discovery() {
    local label="$1"        # SOURCE or TARGET
    local host="$2"
    local admin_user="$3"
    local key_path="$4"
    local script_path="$5"
    local local_output_dir="$6"
    local extra_env="$7"    # extra env vars to export on remote (key=value pairs, space-separated)

    log_info ""
    log_info "=========================================="
    log_info " Running ${label} discovery on ${host}"
    log_info "=========================================="

    # 1. Create remote temp dir and copy script
    log_info "  Creating remote temp dir: ${REMOTE_TMP_DIR}"
    ssh_create_out="$(ssh ${SSH_OPTS} ${key_path:+-i "${key_path}"} "${admin_user}@${host}" \
        "mkdir -p ${REMOTE_TMP_DIR}" 2>&1)"
    if [[ $? -ne 0 ]]; then
        log_error "  Failed to create remote temp dir on ${host}: ${ssh_create_out}"
        return 1
    fi

    log_info "  Copying script to ${host}:${REMOTE_TMP_DIR}/"
    scp_out="$(scp ${SCP_OPTS} ${key_path:+-i "${key_path}"} \
        "${script_path}" "${admin_user}@${host}:${REMOTE_TMP_DIR}/" 2>&1)"
    if [[ $? -ne 0 ]]; then
        log_error "  SCP failed: ${scp_out}"
        return 1
    fi
    log_ok "  Script copied successfully."

    # 2. Execute via login shell (so .bash_profile is sourced)
    log_info "  Executing discovery script (login shell)..."
    local script_name
    script_name="$(basename "${script_path}")"

    ssh_exec_exit=0
    ssh ${SSH_OPTS} ${key_path:+-i "${key_path}"} "${admin_user}@${host}" \
        "mkdir -p ${REMOTE_TMP_DIR} && bash -l -s" \
        < <(
            echo "cd '${REMOTE_TMP_DIR}'"
            [[ -n "${extra_env}" ]] && echo "export ${extra_env}"
            cat "${script_path}"
        ) 2>&1 | tee -a /dev/stdout
    ssh_exec_exit=${PIPESTATUS[0]}

    if [[ ${ssh_exec_exit} -ne 0 ]]; then
        log_warn "  Discovery script on ${host} exited with code ${ssh_exec_exit} (partial results may still be present)"
    fi

    # 3. Verify output files were created before attempting SCP
    log_info "  Verifying output files on remote host..."
    remote_files_out="$(ssh ${SSH_OPTS} ${key_path:+-i "${key_path}"} "${admin_user}@${host}" \
        "ls -la ${REMOTE_TMP_DIR}/" 2>&1)"
    log_info "  Remote directory contents:"
    echo "${remote_files_out}" | while IFS= read -r line; do log_raw "    ${line}"; done
    echo "${remote_files_out}" >> /dev/null  # suppress unused variable warning

    txt_count="$(ssh ${SSH_OPTS} ${key_path:+-i "${key_path}"} "${admin_user}@${host}" \
        "ls ${REMOTE_TMP_DIR}/*.txt 2>/dev/null | wc -l" 2>/dev/null | tr -d '[:space:]')"
    if [[ "${txt_count:-0}" -eq 0 ]]; then
        log_warn "  No .txt output files found on ${host}:${REMOTE_TMP_DIR}/ — discovery may have failed"
    fi

    # 4. SCP results back
    log_info "  Copying results from ${host} to ${local_output_dir}/"
    scp_back_out="$(scp ${SCP_OPTS} ${key_path:+-i "${key_path}"} \
        "${admin_user}@${host}:${REMOTE_TMP_DIR}/*.txt" \
        "${admin_user}@${host}:${REMOTE_TMP_DIR}/*.json" \
        "${local_output_dir}/" 2>&1)"
    scp_back_exit=$?

    if [[ ${scp_back_exit} -ne 0 ]]; then
        log_warn "  SCP of results encountered issues (exit ${scp_back_exit}): ${scp_back_out}"
        log_warn "  Some output files may be missing from ${local_output_dir}/"
        return 1
    fi

    log_ok "  Results collected in ${local_output_dir}/"
    ls -la "${local_output_dir}/" | grep "zdm_" | while IFS= read -r line; do
        log_info "    ${line}"
    done

    return 0
}

# ---------------------------------------------------------------------------
# Helper: run ZDM server discovery locally
# ---------------------------------------------------------------------------
run_server_discovery() {
    log_info ""
    log_info "=========================================="
    log_info " Running ZDM server discovery (local)"
    log_info "=========================================="

    local server_output_dir="${OUTPUT_BASE}/server"
    local tmp_dir="/tmp/zdm_server_discovery_${TIMESTAMP}"
    mkdir -p "${tmp_dir}"

    log_info "  Running ${SERVER_DISCOVERY_SCRIPT} in ${tmp_dir}..."

    # Run server discovery, passing host env vars for connectivity tests
    (
        cd "${tmp_dir}" || exit 1
        SOURCE_HOST="${SOURCE_HOST}" \
        TARGET_HOST="${TARGET_HOST}" \
        ZDM_USER="${ZDM_USER}" \
        bash "${SERVER_DISCOVERY_SCRIPT}"
    )
    local run_exit=$?

    if [[ ${run_exit} -ne 0 ]]; then
        log_warn "  ZDM server discovery exited with code ${run_exit}"
    fi

    # Verify output files
    log_info "  Output files in ${tmp_dir}:"
    ls -la "${tmp_dir}/" | grep "zdm_" | while IFS= read -r line; do
        log_info "    ${line}"
    done

    # Copy to server output dir
    txt_count="$(ls "${tmp_dir}"/*.txt 2>/dev/null | wc -l | tr -d '[:space:]')"
    if [[ "${txt_count:-0}" -gt 0 ]]; then
        cp "${tmp_dir}"/*.txt "${tmp_dir}"/*.json "${server_output_dir}/" 2>/dev/null
        log_ok "  Results collected in ${server_output_dir}/"
        ls -la "${server_output_dir}/" | grep "zdm_" | while IFS= read -r line; do
            log_info "    ${line}"
        done
        return 0
    else
        log_warn "  No output files found in ${tmp_dir}/ — server discovery may have failed"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Run source discovery
# ---------------------------------------------------------------------------
SOURCE_EXTRA_ENV=""
[[ -n "${SOURCE_REMOTE_ORACLE_HOME}" ]] && SOURCE_EXTRA_ENV="${SOURCE_EXTRA_ENV} SOURCE_REMOTE_ORACLE_HOME=${SOURCE_REMOTE_ORACLE_HOME}"
[[ -n "${SOURCE_ORACLE_SID}"         ]] && SOURCE_EXTRA_ENV="${SOURCE_EXTRA_ENV} SOURCE_ORACLE_SID=${SOURCE_ORACLE_SID}"
[[ -n "${ORACLE_USER}"               ]] && SOURCE_EXTRA_ENV="${SOURCE_EXTRA_ENV} ORACLE_USER=${ORACLE_USER}"

run_remote_discovery \
    "SOURCE" \
    "${SOURCE_HOST}" \
    "${SOURCE_ADMIN_USER}" \
    "${SOURCE_SSH_KEY}" \
    "${SOURCE_DISCOVERY_SCRIPT}" \
    "${OUTPUT_BASE}/source" \
    "${SOURCE_EXTRA_ENV# }" \
    && SOURCE_SUCCESS=true || log_warn "Source discovery encountered errors — continuing to target..."

# ---------------------------------------------------------------------------
# Run target discovery
# ---------------------------------------------------------------------------
TARGET_EXTRA_ENV=""
[[ -n "${TARGET_REMOTE_ORACLE_HOME}" ]] && TARGET_EXTRA_ENV="${TARGET_EXTRA_ENV} TARGET_REMOTE_ORACLE_HOME=${TARGET_REMOTE_ORACLE_HOME}"
[[ -n "${TARGET_ORACLE_SID}"         ]] && TARGET_EXTRA_ENV="${TARGET_EXTRA_ENV} TARGET_ORACLE_SID=${TARGET_ORACLE_SID}"
[[ -n "${ORACLE_USER}"               ]] && TARGET_EXTRA_ENV="${TARGET_EXTRA_ENV} ORACLE_USER=${ORACLE_USER}"

run_remote_discovery \
    "TARGET" \
    "${TARGET_HOST}" \
    "${TARGET_ADMIN_USER}" \
    "${TARGET_SSH_KEY}" \
    "${TARGET_DISCOVERY_SCRIPT}" \
    "${OUTPUT_BASE}/target" \
    "${TARGET_EXTRA_ENV# }" \
    && TARGET_SUCCESS=true || log_warn "Target discovery encountered errors — continuing to ZDM server..."

# ---------------------------------------------------------------------------
# Run ZDM server discovery (local)
# ---------------------------------------------------------------------------
run_server_discovery \
    && SERVER_SUCCESS=true || log_warn "ZDM server discovery encountered errors."

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "  ZDM Step 2 Discovery Orchestrator — Complete"
echo "  Finished : $(date)"
echo "============================================================"
echo "  Server Results:"
echo "    Source (${SOURCE_HOST})  : $([ "${SOURCE_SUCCESS}" == "true" ] && echo "SUCCESS" || echo "PARTIAL/FAILED")"
echo "    Target (${TARGET_HOST}) : $([ "${TARGET_SUCCESS}" == "true" ] && echo "SUCCESS" || echo "PARTIAL/FAILED")"
echo "    ZDM server (local)      : $([ "${SERVER_SUCCESS}" == "true" ] && echo "SUCCESS" || echo "PARTIAL/FAILED")"
echo ""
echo "  Discovery output saved to:"
echo "    ${OUTPUT_BASE}/source/"
echo "    ${OUTPUT_BASE}/target/"
echo "    ${OUTPUT_BASE}/server/"
echo ""
echo "  Next steps:"
echo "    1. Review discovery reports in the Discovery/ directories"
echo "    2. Commit the discovery output files to the repository"
echo "    3. Continue with: @Phase10-ZDM-Step3-Discovery-Questionnaire"
echo "============================================================"

# Exit non-zero if any discovery failed
if [[ "${SOURCE_SUCCESS}" != "true" || "${TARGET_SUCCESS}" != "true" || "${SERVER_SUCCESS}" != "true" ]]; then
    exit 1
fi
exit 0
