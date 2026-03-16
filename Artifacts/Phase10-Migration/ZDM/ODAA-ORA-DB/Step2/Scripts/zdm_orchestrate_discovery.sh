#!/bin/bash
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration
# ==============================================================================
# ZDM Step 2 — Master Discovery Orchestration Script
# Project  : ODAA-ORA-DB
# Generated: 2026-03-16
#
# Runs on ZDM server (10.200.1.13) as zdmuser.
# Copies each discovery script to its target server, executes it, and SCPs
# the output files back into the local Discovery/ directory.
#
# Usage:
#   bash zdm_orchestrate_discovery.sh [-h] [-c] [-t] [-v]
#
#   -h   Show help
#   -c   Show configuration and exit
#   -t   Connectivity test only (no discovery)
#   -v   Verbose SSH/SCP output
# ==============================================================================

# ── Environment variables with defaults ───────────────────────────────────────
SOURCE_HOST="${SOURCE_HOST:-10.200.1.12}"
TARGET_HOST="${TARGET_HOST:-10.200.0.250}"
SOURCE_ADMIN_USER="${SOURCE_ADMIN_USER:-azureuser}"
TARGET_ADMIN_USER="${TARGET_ADMIN_USER:-opc}"
ORACLE_USER="${ORACLE_USER:-oracle}"
ZDM_USER="${ZDM_USER:-zdmuser}"
# Empty = use SSH agent / default key (no -i flag)
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-}"
TARGET_SSH_KEY="${TARGET_SSH_KEY:-}"

# Optional Oracle overrides forwarded to remote scripts
SOURCE_REMOTE_ORACLE_HOME="${SOURCE_REMOTE_ORACLE_HOME:-}"
SOURCE_ORACLE_SID="${SOURCE_ORACLE_SID:-}"
TARGET_REMOTE_ORACLE_HOME="${TARGET_REMOTE_ORACLE_HOME:-}"
TARGET_ORACLE_SID="${TARGET_ORACLE_SID:-}"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARTIFACTS_BASE="$(dirname "$SCRIPT_DIR")"   # Step2/
DISCOVERY_BASE="${ARTIFACTS_BASE}/Discovery"
VERBOSE=false

# SSH / SCP shared options
SSH_OPTS_BASE=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new \
               -o ConnectTimeout=15 -o PasswordAuthentication=no)
SCP_OPTS_BASE=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new \
               -o ConnectTimeout=15 -o PasswordAuthentication=no)

# Remote temp directory
REMOTE_TMP_DIR="/tmp/zdm_discovery_${TIMESTAMP}"

# ── Logging ───────────────────────────────────────────────────────────────────
ORCH_LOG="${ARTIFACTS_BASE}/zdm_orchestration_${TIMESTAMP}.log"
log_info()  { echo "[$(date '+%H:%M:%S')] [INFO]  $*" | tee -a "$ORCH_LOG"; }
log_warn()  { echo "[$(date '+%H:%M:%S')] [WARN]  $*" | tee -a "$ORCH_LOG"; }
log_error() { echo "[$(date '+%H:%M:%S')] [ERROR] $*" | tee -a "$ORCH_LOG"; }
log_sep()   { echo "$(printf '─%.0s' {1..70})" | tee -a "$ORCH_LOG"; }

# ── show_help ─────────────────────────────────────────────────────────────────
show_help() {
    cat <<HELPEOF
Usage: bash zdm_orchestrate_discovery.sh [OPTIONS]

Options:
  -h   Show this help message and exit
  -c   Show current configuration and exit
  -t   Run connectivity tests only (ping + port checks)
  -v   Verbose: show full SSH/SCP command output

Environment variables (override defaults):
  SOURCE_HOST           Source server IP/hostname  (default: 10.200.1.12)
  TARGET_HOST           Target server IP/hostname  (default: 10.200.0.250)
  SOURCE_ADMIN_USER     SSH admin user for source  (default: azureuser)
  TARGET_ADMIN_USER     SSH admin user for target  (default: opc)
  SOURCE_SSH_KEY        Path to SSH key for source (default: empty = SSH agent)
  TARGET_SSH_KEY        Path to SSH key for target (default: empty = SSH agent)
  ORACLE_USER           Oracle OS user             (default: oracle)
  ZDM_USER              ZDM OS user                (default: zdmuser)
  SOURCE_REMOTE_ORACLE_HOME   Override ORACLE_HOME on source
  SOURCE_ORACLE_SID           Override ORACLE_SID on source
  TARGET_REMOTE_ORACLE_HOME   Override ORACLE_HOME on target
  TARGET_ORACLE_SID           Override ORACLE_SID on target

Examples:
  # Run full discovery with defaults
  bash zdm_orchestrate_discovery.sh

  # Override target SSH user
  TARGET_ADMIN_USER=azureuser bash zdm_orchestrate_discovery.sh

  # Connectivity test only
  bash zdm_orchestrate_discovery.sh -t

  # Verbose output
  bash zdm_orchestrate_discovery.sh -v
HELPEOF
    exit 0
}

# ── show_config ───────────────────────────────────────────────────────────────
show_config() {
    echo "======================================================================"
    echo " ZDM Discovery Configuration"
    echo "======================================================================"
    echo "  SOURCE_HOST        : ${SOURCE_HOST:-<not set>}"
    echo "  SOURCE_ADMIN_USER  : ${SOURCE_ADMIN_USER}"
    echo "  SOURCE_SSH_KEY     : ${SOURCE_SSH_KEY:-<empty — SSH agent/default key>}"
    echo ""
    echo "  TARGET_HOST        : ${TARGET_HOST:-<not set>}"
    echo "  TARGET_ADMIN_USER  : ${TARGET_ADMIN_USER}"
    echo "  TARGET_SSH_KEY     : ${TARGET_SSH_KEY:-<empty — SSH agent/default key>}"
    echo ""
    echo "  ORACLE_USER        : ${ORACLE_USER}"
    echo "  ZDM_USER           : ${ZDM_USER}"
    echo ""
    echo "  SOURCE_REMOTE_ORACLE_HOME : ${SOURCE_REMOTE_ORACLE_HOME:-<auto-detect>}"
    echo "  SOURCE_ORACLE_SID         : ${SOURCE_ORACLE_SID:-<auto-detect>}"
    echo "  TARGET_REMOTE_ORACLE_HOME : ${TARGET_REMOTE_ORACLE_HOME:-<auto-detect>}"
    echo "  TARGET_ORACLE_SID         : ${TARGET_ORACLE_SID:-<auto-detect>}"
    echo ""
    echo "  SCRIPT_DIR         : ${SCRIPT_DIR}"
    echo "  DISCOVERY_BASE     : ${DISCOVERY_BASE}"
    echo "  ORCH_LOG           : ${ORCH_LOG}"
    echo "======================================================================"
    exit 0
}

# ── Parse arguments ───────────────────────────────────────────────────────────
MODE="full"
while getopts "hctv" opt; do
    case "$opt" in
        h) show_help ;;
        c) show_config ;;
        t) MODE="connectivity" ;;
        v) VERBOSE=true ;;
        *) echo "Unknown option: $opt"; show_help ;;
    esac
done

# ── SSH options arrays (with optional -i) ─────────────────────────────────────
build_ssh_opts() {
    local key_path="$1"
    local opts=("${SSH_OPTS_BASE[@]}")
    if [[ -n "$key_path" ]]; then
        opts+=(-i "$key_path")
    fi
    $VERBOSE || opts+=(-q)
    echo "${opts[@]}"
}

build_scp_opts() {
    local key_path="$1"
    local opts=("${SCP_OPTS_BASE[@]}")
    if [[ -n "$key_path" ]]; then
        opts+=(-i "$key_path")
    fi
    $VERBOSE || opts+=(-q)
    echo "${opts[@]}"
}

# ── Startup diagnostic ────────────────────────────────────────────────────────
mkdir -p "$ARTIFACTS_BASE" "$DISCOVERY_BASE/source" "$DISCOVERY_BASE/target" "$DISCOVERY_BASE/server"
> "$ORCH_LOG"

echo "======================================================================"
echo " ZDM Step 2 — Discovery Orchestration"
echo " Project  : ODAA-ORA-DB"
echo " Timestamp: ${TIMESTAMP}"
echo " Mode     : ${MODE}"
echo "======================================================================"

log_info "Current user     : $(whoami)"
log_info "Home directory   : ${HOME}"
if [[ "$(whoami)" != "$ZDM_USER" ]]; then
    log_warn "Expected to run as '$ZDM_USER' — currently '$(whoami)'"
fi

log_info "Script directory : ${SCRIPT_DIR}"
log_sep

log_info "SSH key diagnostics:"
PEM_COUNT=$(ls ~/.ssh/*.pem ~/.ssh/*.key 2>/dev/null | wc -l)
if [[ "${PEM_COUNT:-0}" -gt 0 ]]; then
    ls ~/.ssh/*.pem ~/.ssh/*.key 2>/dev/null | while IFS= read -r f; do
        PERMS=$(stat -c "%a" "$f" 2>/dev/null || stat -f "%OLp" "$f" 2>/dev/null || echo "unknown")
        log_info "  found: $f  (permissions: $PERMS)"
    done
else
    log_warn "  No .pem or .key files found in ~/.ssh/"
fi

for VAR_NAME in SOURCE_SSH_KEY TARGET_SSH_KEY; do
    VAR_VALUE="${!VAR_NAME}"
    if [[ -z "$VAR_VALUE" ]]; then
        log_info "  ${VAR_NAME}: empty — SSH agent / default key (~/.ssh/id_rsa) will be used"
    else
        EXPANDED="${VAR_VALUE/#\~/$HOME}"
        if [[ -f "$EXPANDED" ]]; then
            log_info "  ${VAR_NAME}: $VAR_VALUE  — file EXISTS"
        else
            log_warn "  ${VAR_NAME}: $VAR_VALUE  — file NOT FOUND"
        fi
    fi
done
log_sep

# ── Connectivity-only mode ────────────────────────────────────────────────────
run_connectivity_test() {
    local host="$1" port="$2" label="$3"
    if (echo >/dev/tcp/"$host"/"$port") 2>/dev/null; then
        log_info "  [OPEN]   ${label} port ${port} on ${host}"
        return 0
    else
        log_warn "  [CLOSED] ${label} port ${port} on ${host}"
        return 1
    fi
}

if [[ "$MODE" == "connectivity" ]]; then
    log_info "Running connectivity tests only ..."
    for SERVER in SOURCE TARGET; do
        HOST="${SOURCE_HOST}"
        [[ "$SERVER" == "TARGET" ]] && HOST="${TARGET_HOST}"
        log_info ""
        log_info "--- ${SERVER}: ${HOST} ---"
        ping -c 10 -W 2 "$HOST" 2>&1 | tail -3 | while IFS= read -r l; do log_info "$l"; done
        run_connectivity_test "$HOST" 22   "$SERVER"
        run_connectivity_test "$HOST" 1521 "$SERVER"
    done
    log_info "Connectivity test complete."
    exit 0
fi

# ── Tracking ──────────────────────────────────────────────────────────────────
SUCCEEDED_SERVERS=()
FAILED_SERVERS=()

# ══════════════════════════════════════════════════════════════════════════════
# Helper: run a discovery script on a remote server
# Usage: run_remote_discovery <server_label> <host> <admin_user> <ssh_key> <script_path> <output_dir>
# ══════════════════════════════════════════════════════════════════════════════
run_remote_discovery() {
    local label="$1"
    local host="$2"
    local admin_user="$3"
    local key_path="$4"
    local script_path="$5"
    local output_dir="$6"

    log_sep
    log_info "Starting ${label} discovery on ${admin_user}@${host}"

    # Build SSH/SCP opts
    local SSH_OPTS_ARR=("${SSH_OPTS_BASE[@]}")
    local SCP_OPTS_ARR=("${SCP_OPTS_BASE[@]}")
    if [[ -n "$key_path" ]]; then
        SSH_OPTS_ARR+=(-i "$key_path")
        SCP_OPTS_ARR+=(-i "$key_path")
    fi
    $VERBOSE || { SSH_OPTS_ARR+=(-q); SCP_OPTS_ARR+=(-q); }

    # Create remote temp directory
    log_info "Creating remote temp dir: ${REMOTE_TMP_DIR}"
    if ! ssh "${SSH_OPTS_ARR[@]}" "${admin_user}@${host}" \
             "mkdir -p '${REMOTE_TMP_DIR}'" 2>&1; then
        log_error "Failed to create remote temp dir on ${host}"
        FAILED_SERVERS+=("$label")
        return 1
    fi

    # SCP the script to the remote server
    log_info "Copying ${script_path} to ${admin_user}@${host}:${REMOTE_TMP_DIR}/"
    if ! scp "${SCP_OPTS_ARR[@]}" "$script_path" \
              "${admin_user}@${host}:${REMOTE_TMP_DIR}/" 2>&1; then
        log_error "Failed to SCP script to ${host}"
        FAILED_SERVERS+=("$label")
        return 1
    fi

    local script_name
    script_name="$(basename "$script_path")"

    # Execute via login shell — cd to workdir first so output files land there
    log_info "Executing ${script_name} on ${host} (login shell) ..."
    local RC=0
    REMOTE_EXEC_OUTPUT=$(ssh "${SSH_OPTS_ARR[@]}" "${admin_user}@${host}" \
        "bash -l -s" < <(
            echo "cd '${REMOTE_TMP_DIR}'"
            echo "export ORACLE_USER='${ORACLE_USER}'"
            [[ -n "$SOURCE_REMOTE_ORACLE_HOME" ]] && \
                echo "export SOURCE_REMOTE_ORACLE_HOME='${SOURCE_REMOTE_ORACLE_HOME}'"
            [[ -n "$SOURCE_ORACLE_SID" ]] && \
                echo "export SOURCE_ORACLE_SID='${SOURCE_ORACLE_SID}'"
            [[ -n "$TARGET_REMOTE_ORACLE_HOME" ]] && \
                echo "export TARGET_REMOTE_ORACLE_HOME='${TARGET_REMOTE_ORACLE_HOME}'"
            [[ -n "$TARGET_ORACLE_SID" ]] && \
                echo "export TARGET_ORACLE_SID='${TARGET_ORACLE_SID}'"
            cat "$script_path"
        ) 2>&1) || RC=$?

    echo "$REMOTE_EXEC_OUTPUT" | tee -a "$ORCH_LOG"

    if [[ $RC -ne 0 ]]; then
        log_warn "${label} discovery script exited with RC=${RC} — may be partial"
    fi

    # Confirm output files exist on remote before SCP
    log_info "Listing remote output files:"
    ssh "${SSH_OPTS_ARR[@]}" "${admin_user}@${host}" \
        "ls -la '${REMOTE_TMP_DIR}/'*.txt '${REMOTE_TMP_DIR}/'*.json 2>/dev/null || echo '(none found)'" \
        2>&1 | tee -a "$ORCH_LOG"

    # SCP results back
    log_info "Retrieving output files to ${output_dir}/"
    mkdir -p "$output_dir"
    if scp "${SCP_OPTS_ARR[@]}" \
           "${admin_user}@${host}:${REMOTE_TMP_DIR}/*.txt" \
           "${admin_user}@${host}:${REMOTE_TMP_DIR}/*.json" \
           "${output_dir}/" 2>&1 | tee -a "$ORCH_LOG"; then
        log_info "${label} discovery files retrieved successfully:"
        ls -la "${output_dir}"/ 2>/dev/null | grep -E '\.txt$|\.json$' | \
            while IFS= read -r l; do log_info "  $l"; done
        SUCCEEDED_SERVERS+=("$label")
    else
        log_error "Failed to SCP results from ${host} — check remote directory"
        FAILED_SERVERS+=("$label")
    fi

    # Clean up remote temp directory
    log_info "Cleaning up remote temp dir on ${host}"
    ssh "${SSH_OPTS_ARR[@]}" "${admin_user}@${host}" \
        "rm -rf '${REMOTE_TMP_DIR}'" 2>&1 | tee -a "$ORCH_LOG" || true
}

# ══════════════════════════════════════════════════════════════════════════════
# A. SOURCE DISCOVERY
# ══════════════════════════════════════════════════════════════════════════════
SOURCE_SCRIPT="${SCRIPT_DIR}/zdm_source_discovery.sh"

if [[ -f "$SOURCE_SCRIPT" ]]; then
    run_remote_discovery "SOURCE" \
        "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$SOURCE_SSH_KEY" \
        "$SOURCE_SCRIPT" "${DISCOVERY_BASE}/source"
else
    log_error "Source discovery script not found: ${SOURCE_SCRIPT}"
    FAILED_SERVERS+=("SOURCE")
fi

# ══════════════════════════════════════════════════════════════════════════════
# B. TARGET DISCOVERY
# ══════════════════════════════════════════════════════════════════════════════
TARGET_SCRIPT="${SCRIPT_DIR}/zdm_target_discovery.sh"

if [[ -f "$TARGET_SCRIPT" ]]; then
    run_remote_discovery "TARGET" \
        "$TARGET_HOST" "$TARGET_ADMIN_USER" "$TARGET_SSH_KEY" \
        "$TARGET_SCRIPT" "${DISCOVERY_BASE}/target"
else
    log_error "Target discovery script not found: ${TARGET_SCRIPT}"
    FAILED_SERVERS+=("TARGET")
fi

# ══════════════════════════════════════════════════════════════════════════════
# C. ZDM SERVER DISCOVERY (runs locally as zdmuser)
# ══════════════════════════════════════════════════════════════════════════════
log_sep
log_info "Starting ZDM SERVER discovery (local execution as $(whoami))"

ZDM_SERVER_SCRIPT="${SCRIPT_DIR}/zdm_server_discovery.sh"

if [[ -f "$ZDM_SERVER_SCRIPT" ]]; then
    mkdir -p "${DISCOVERY_BASE}/server"
    pushd "${DISCOVERY_BASE}/server" > /dev/null
    ZDM_SERVER_RC=0
    SOURCE_HOST="$SOURCE_HOST" TARGET_HOST="$TARGET_HOST" ZDM_USER="$ZDM_USER" \
        bash "$ZDM_SERVER_SCRIPT" 2>&1 | tee -a "$ORCH_LOG" || ZDM_SERVER_RC=$?
    popd > /dev/null

    if [[ $ZDM_SERVER_RC -ne 0 ]]; then
        log_warn "ZDM server discovery exited with RC=${ZDM_SERVER_RC}"
    fi

    log_info "ZDM server discovery output:"
    ls -la "${DISCOVERY_BASE}/server"/ 2>/dev/null | grep -E '\.txt$|\.json$' | \
        while IFS= read -r l; do log_info "  $l"; done
    SUCCEEDED_SERVERS+=("ZDM_SERVER")
else
    log_error "ZDM server discovery script not found: ${ZDM_SERVER_SCRIPT}"
    FAILED_SERVERS+=("ZDM_SERVER")
fi

# ══════════════════════════════════════════════════════════════════════════════
# FINAL SUMMARY
# ══════════════════════════════════════════════════════════════════════════════
log_sep
echo ""
echo "======================================================================"
echo " DISCOVERY ORCHESTRATION COMPLETE"
echo "======================================================================"
log_info "Succeeded : ${SUCCEEDED_SERVERS[*]:-<none>}"
log_info "Failed    : ${FAILED_SERVERS[*]:-<none>}"
log_info ""
log_info "Output files:"
find "${DISCOVERY_BASE}" -type f \( -name "*.txt" -o -name "*.json" \) 2>/dev/null | \
    sort | while IFS= read -r f; do log_info "  $f"; done
log_info ""
log_info "Orchestration log: ${ORCH_LOG}"

if [[ ${#FAILED_SERVERS[@]} -gt 0 ]]; then
    log_warn ""
    log_warn "One or more servers failed. Review the log above and re-run after fixing issues."
    echo ""
    echo " RESULT: PARTIAL — failed servers: ${FAILED_SERVERS[*]}"
    echo "======================================================================"
    exit 1
else
    log_info ""
    log_info "All servers discovered successfully."
    echo ""
    echo " RESULT: SUCCESS — all discovery scripts completed"
    echo " Next step: @Phase10-ZDM-Step3-Discovery-Questionnaire"
    echo "======================================================================"
    exit 0
fi
