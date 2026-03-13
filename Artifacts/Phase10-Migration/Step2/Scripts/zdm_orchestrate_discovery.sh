#!/bin/bash
# =============================================================================
# zdm_orchestrate_discovery.sh
# Phase 10 â€” ZDM Migration Â· Step 2: Orchestrate Discovery Across All Servers
#
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to any server or database
#
# Orchestrates discovery by:
#   1. SSHing to the source DB server and running zdm_source_discovery.sh
#   2. SSHing to the target Oracle DB@Azure server and running zdm_target_discovery.sh
#   3. Running zdm_server_discovery.sh locally on this ZDM server
#   4. SCP-collecting all output files into Artifacts/Phase10-Migration/Step2/Discovery/
#
# Usage:
#   ./zdm_orchestrate_discovery.sh [-h] [-c] [-t] [-v]
#
#   -h, --help     Show this help message
#   -c, --config   Show configuration and exit
#   -t, --test     Test SSH connectivity only (do not run discovery)
#   -v, --verbose  Verbose SSH/SCP output
#
# Run as: zdmuser on the ZDM server
# =============================================================================

# Do NOT use set -e globally â€” individual sections handle their own errors
set -uo pipefail

# =============================================================================
# USER CONFIGURATION  (from zdm-env.md)
# =============================================================================

# --- Hosts ---
SOURCE_HOST="${SOURCE_HOST:-10.1.0.11}"
TARGET_HOST="${TARGET_HOST:-10.0.1.160}"

# --- SSH/Admin users for remote servers (Linux admin users with sudo) ---
SOURCE_ADMIN_USER="${SOURCE_ADMIN_USER:-azureuser}"
TARGET_ADMIN_USER="${TARGET_ADMIN_USER:-opc}"

# --- Oracle database software owner (for running SQL commands) ---
ORACLE_USER="${ORACLE_USER:-oracle}"

# --- ZDM software owner (for running ZDM CLI commands) ---
ZDM_USER="${ZDM_USER:-zdmuser}"

# --- SSH key paths (optional â€” when empty, SSH agent or default key is used) ---
# Set only if the key is defined in zdm-env.md and is non-empty
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-${HOME}/.ssh/odaa.pem}"
TARGET_SSH_KEY="${TARGET_SSH_KEY:-${HOME}/.ssh/odaa.pem}"

# --- Oracle environment overrides (leave empty for auto-detection) ---
SOURCE_REMOTE_ORACLE_HOME="${SOURCE_REMOTE_ORACLE_HOME:-}"
SOURCE_REMOTE_ORACLE_SID="${SOURCE_REMOTE_ORACLE_SID:-}"
TARGET_REMOTE_ORACLE_HOME="${TARGET_REMOTE_ORACLE_HOME:-}"
TARGET_REMOTE_ORACLE_SID="${TARGET_REMOTE_ORACLE_SID:-}"
ZDM_REMOTE_ZDM_HOME="${ZDM_REMOTE_ZDM_HOME:-}"
ZDM_REMOTE_JAVA_HOME="${ZDM_REMOTE_JAVA_HOME:-}"

# =============================================================================
# INTERNAL CONFIGURATION
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/Artifacts/Phase10-Migration/Step2/Discovery}"

VERBOSE=false
TEST_ONLY=false
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

# Results tracking
SOURCE_STATUS="NOT_RUN"
TARGET_STATUS="NOT_RUN"
SERVER_STATUS="NOT_RUN"
FAILURES=()

# =============================================================================
# COLOR OUTPUT
# =============================================================================
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'  # No Color

log_info()    { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_debug()   { $VERBOSE && echo -e "${CYAN}[DEBUG]${NC} $1" || true; }
log_section() { echo -e "\n${BOLD}${CYAN}============================================================${NC}"; \
                echo -e "${BOLD}${CYAN}  $1${NC}"; \
                echo -e "${BOLD}${CYAN}============================================================${NC}"; }

# =============================================================================
# ARGUMENT PARSING  â€” show_help / show_config ONLY called from here
# =============================================================================
show_help() {
    cat <<HELP
Usage: $(basename "$0") [OPTIONS]

Orchestrates ZDM discovery across source, target, and ZDM server.

Options:
  -h, --help     Show this help message and exit
  -c, --config   Show current configuration and exit
  -t, --test     Test SSH connectivity only (do not run discovery)
  -v, --verbose  Enable verbose SSH/SCP output

Environment variables (override defaults):
  SOURCE_HOST            Source database host (default: $SOURCE_HOST)
  TARGET_HOST            Target database host (default: $TARGET_HOST)
  SOURCE_ADMIN_USER      SSH admin user for source server (default: $SOURCE_ADMIN_USER)
  TARGET_ADMIN_USER      SSH admin user for target server (default: $TARGET_ADMIN_USER)
  SOURCE_SSH_KEY         SSH key for source (default: $SOURCE_SSH_KEY)
  TARGET_SSH_KEY         SSH key for target (default: $TARGET_SSH_KEY)
  OUTPUT_DIR             Output directory (default: $OUTPUT_DIR)

Output:
  Discovery files saved to: \$OUTPUT_DIR/{source,target,server}/

HELP
    exit 0
}

show_config() {
    cat <<CONFIG
=== Current Configuration ===
SOURCE_HOST         : $SOURCE_HOST
TARGET_HOST         : $TARGET_HOST
SOURCE_ADMIN_USER   : $SOURCE_ADMIN_USER
TARGET_ADMIN_USER   : $TARGET_ADMIN_USER
ORACLE_USER         : $ORACLE_USER
ZDM_USER            : $ZDM_USER
SOURCE_SSH_KEY      : ${SOURCE_SSH_KEY:-<not set â€” using SSH agent>}
TARGET_SSH_KEY      : ${TARGET_SSH_KEY:-<not set â€” using SSH agent>}
OUTPUT_DIR          : $OUTPUT_DIR
REPO_ROOT           : $REPO_ROOT
VERBOSE             : $VERBOSE
CONFIG
    exit 0
}

for arg in "$@"; do
    case "$arg" in
        -h|--help)    show_help ;;
        -c|--config)  show_config ;;
        -t|--test)    TEST_ONLY=true ;;
        -v|--verbose) VERBOSE=true ;;
        *) log_warn "Unknown option: $arg (ignored)" ;;
    esac
done

# =============================================================================
# SSH OPTIONS
# =============================================================================
SSH_BASE_OPTS="-o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=15"
SCP_BASE_OPTS="-o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=15"
$VERBOSE && SSH_BASE_OPTS="$SSH_BASE_OPTS -v" && SCP_BASE_OPTS="$SCP_BASE_OPTS -v"

# =============================================================================
# SSH KEY DIAGNOSTICS  (run before any connections)
# =============================================================================
log_upfront_ssh_diagnostics() {
    log_section "SSH KEY DIAGNOSTICS"

    log_info "Running as user     : $(whoami)"
    log_info "HOME directory      : $HOME"

    if [ "$(whoami)" != "$ZDM_USER" ]; then
        log_warn "IMPORTANT: This script should run as '$ZDM_USER'."
        log_warn "  Currently running as '$(whoami)'. SSH keys must exist under /home/$ZDM_USER/.ssh/ with permissions 600."
    fi

    # List SSH keys in ~/.ssh/
    if [ -d "${HOME}/.ssh" ]; then
        PEM_KEYS="$(find "${HOME}/.ssh" -name '*.pem' -o -name '*.key' 2>/dev/null | tr '\n' ' ')"
        if [ -n "$PEM_KEYS" ]; then
            log_info "SSH .pem/.key files found in ${HOME}/.ssh/: $PEM_KEYS"
        else
            log_warn "No .pem or .key files in ${HOME}/.ssh/ â€” SSH agent or default key must be active."
        fi
    else
        log_warn "SSH directory ${HOME}/.ssh/ does not exist."
    fi

    # Check SOURCE_SSH_KEY
    if [ -z "${SOURCE_SSH_KEY:-}" ]; then
        log_info "SOURCE_SSH_KEY: not configured â€” SSH agent or default key will be used for source"
    else
        local src_key_exp="${SOURCE_SSH_KEY/#\~/$HOME}"
        if [ -f "$src_key_exp" ]; then
            log_info "SOURCE_SSH_KEY: $src_key_exp â€” EXISTS"
        else
            log_warn "SOURCE_SSH_KEY: $src_key_exp â€” FILE NOT FOUND"
            log_warn "  Check the SOURCE_SSH_KEY path is correct and the file exists under $(whoami)'s home."
            log_warn "  Override: export SOURCE_SSH_KEY=\"/path/to/your/key.pem\""
        fi
    fi

    # Check TARGET_SSH_KEY
    if [ -z "${TARGET_SSH_KEY:-}" ]; then
        log_info "TARGET_SSH_KEY: not configured â€” SSH agent or default key will be used for target"
    else
        local tgt_key_exp="${TARGET_SSH_KEY/#\~/$HOME}"
        if [ -f "$tgt_key_exp" ]; then
            log_info "TARGET_SSH_KEY: $tgt_key_exp â€” EXISTS"
        else
            log_warn "TARGET_SSH_KEY: $tgt_key_exp â€” FILE NOT FOUND"
            log_warn "  Override: export TARGET_SSH_KEY=\"/path/to/your/key.pem\""
        fi
    fi
}

# =============================================================================
# PREREQUISITES
# =============================================================================
validate_prerequisites() {
    log_section "VALIDATING PREREQUISITES"

    local errors=0

    [ -z "$SOURCE_HOST" ] && { log_error "SOURCE_HOST is not set"; ((errors++)); }
    [ -z "$TARGET_HOST" ] && { log_error "TARGET_HOST is not set"; ((errors++)); }
    [ -z "$SOURCE_ADMIN_USER" ] && { log_error "SOURCE_ADMIN_USER is not set"; ((errors++)); }
    [ -z "$TARGET_ADMIN_USER" ] && { log_error "TARGET_ADMIN_USER is not set"; ((errors++)); }

    if [ $errors -gt 0 ]; then
        log_error "$errors prerequisite check(s) failed. Aborting."
        exit 1
    fi

    log_info "Prerequisites validated."
}

# =============================================================================
# CONNECTIVITY TESTS
# =============================================================================
test_ssh_connection() {
    local label="$1"
    local host="$2"
    local user="$3"
    local key_path="$4"

    log_info "Testing SSH: $label ($user@$host)..."
    # Resolve ~ in key path
    local key_exp="${key_path/#\~/$HOME}"

    local ssh_out
    local ssh_exit=0
    ssh_out="$(ssh $SSH_BASE_OPTS ${key_path:+-i "$key_exp"} "${user}@${host}" "hostname" 2>&1)" || ssh_exit=$?

    if [ $ssh_exit -eq 0 ]; then
        log_info "  SSH $label: SUCCESS (remote hostname: $ssh_out)"
        return 0
    else
        log_error "  SSH $label: FAILED (exit $ssh_exit)"
        log_error "  Output: $ssh_out"
        return 1
    fi
}

test_all_connections() {
    log_section "CONNECTIVITY TESTS"

    test_ssh_connection "SOURCE" "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$SOURCE_SSH_KEY" || FAILURES+=("SSH SOURCE")
    test_ssh_connection "TARGET" "$TARGET_HOST" "$TARGET_ADMIN_USER" "$TARGET_SSH_KEY" || FAILURES+=("SSH TARGET")

    if [ ${#FAILURES[@]} -gt 0 ]; then
        log_warn "Some connectivity tests failed: ${FAILURES[*]}"
        log_warn "Discovery will be attempted for each server independently."
    else
        log_info "All connectivity tests passed."
    fi
}

# =============================================================================
# REMOTE DISCOVERY EXECUTION
# =============================================================================
run_remote_discovery() {
    local label="$1"
    local host="$2"
    local user="$3"
    local key_path="$4"
    local script_path="$5"
    local env_args="$6"
    local results_dir="$7"

    local key_exp="${key_path/#\~/$HOME}"
    local script_name
    script_name="$(basename "$script_path")"
    local remote_dir="/tmp/zdm_discovery_$$_${label,,}"

    log_section "RUNNING $label DISCOVERY"
    log_info "Host   : $host"
    log_info "User   : $user"
    log_info "Script : $script_name"
    log_info "Remote : $remote_dir"

    # Step 1: Copy discovery script to remote
    log_info "Uploading $script_name to $user@$host:$remote_dir/ ..."
    local scp_out
    local scp_exit=0
    scp_out="$(scp $SCP_BASE_OPTS ${key_path:+-i "$key_exp"} \
        "$script_path" \
        "${user}@${host}:${script_name}.tmp" 2>&1)" || scp_exit=$?

    if [ $scp_exit -ne 0 ]; then
        log_error "SCP upload FAILED for $label (exit $scp_exit)"
        log_error "SCP output: $scp_out"
        return 1
    fi
    log_info "  Upload successful."

    # Step 2: Execute discovery remotely (login shell + cd to remote_dir first)
    log_info "Executing $script_name on $host ..."
    local exec_out
    local exec_exit=0
    exec_out="$(ssh $SSH_BASE_OPTS ${key_path:+-i "$key_exp"} "${user}@${host}" \
        "${env_args}bash -l -s" \
        < <(echo "mkdir -p '$remote_dir' && cd '$remote_dir' && chmod +x ~/${script_name}.tmp && cp ~/${script_name}.tmp $remote_dir/$script_name" ; \
            echo "cd '$remote_dir'" ; \
            cat "$script_path") 2>&1)" || exec_exit=$?

    if [ $exec_exit -ne 0 ]; then
        log_warn "Remote execution for $label returned exit code $exec_exit"
        log_warn "Output:"
        echo "$exec_out" | head -50
    else
        log_info "Remote execution completed successfully."
    fi
    log_debug "Full remote output:\n$exec_out"

    # Step 3: List remote output directory before collecting
    log_info "Listing remote output directory ($remote_dir) ..."
    local ls_out
    local ls_exit=0
    ls_out="$(ssh $SSH_BASE_OPTS ${key_path:+-i "$key_exp"} "${user}@${host}" \
        "ls -la '$remote_dir'/ 2>/dev/null || echo 'DIRECTORY NOT FOUND: $remote_dir'" 2>&1)" || ls_exit=$?
    echo "$ls_out" | while IFS= read -r line; do log_info "  $line"; done

    # Step 4: SCP collect output files
    mkdir -p "$results_dir"
    log_info "Collecting output files to $results_dir ..."
    local collect_out
    local collect_exit=0
    collect_out="$(scp $SCP_BASE_OPTS ${key_path:+-i "$key_exp"} \
        "${user}@${host}:${remote_dir}/*.txt" \
        "${user}@${host}:${remote_dir}/*.json" \
        "$results_dir/" 2>&1)" || collect_exit=$?

    if [ $collect_exit -ne 0 ]; then
        log_warn "SCP collection encountered issues (exit $collect_exit). Partial results may exist."
        log_warn "SCP output: $collect_out"
    else
        log_info "Output files collected:"
        ls -la "$results_dir/" | while IFS= read -r line; do log_info "  $line"; done
    fi

    # Step 5: Cleanup remote temp files
    ssh $SSH_BASE_OPTS ${key_path:+-i "$key_exp"} "${user}@${host}" \
        "rm -rf '$remote_dir' ~/${script_name}.tmp" 2>/dev/null || true

    # Return success if we got any output files
    local count
    count=$(ls "$results_dir/"*.txt "$results_dir/"*.json 2>/dev/null | wc -l)
    if [ "$count" -gt 0 ]; then
        log_info "$label discovery: $count output file(s) collected."
        return 0
    else
        log_warn "$label discovery: No output files collected."
        return 1
    fi
}

run_local_discovery() {
    local script_path="$1"
    local results_dir="$2"

    local script_name
    script_name="$(basename "$script_path")"
    local local_dir="/tmp/zdm_discovery_$$_server"

    log_section "RUNNING ZDM SERVER DISCOVERY (local)"
    log_info "Script : $script_name"
    log_info "Output : $results_dir"

    mkdir -p "$local_dir"
    mkdir -p "$results_dir"

    # Build env args to pass host connectivity variables
    local env_args="SOURCE_HOST='${SOURCE_HOST}' TARGET_HOST='${TARGET_HOST}' ZDM_USER='${ZDM_USER}'"
    [ -n "${ZDM_REMOTE_ZDM_HOME:-}" ]  && env_args="$env_args ZDM_HOME='${ZDM_REMOTE_ZDM_HOME}'"
    [ -n "${ZDM_REMOTE_JAVA_HOME:-}" ] && env_args="$env_args JAVA_HOME='${ZDM_REMOTE_JAVA_HOME}'"
    [ -n "${ORACLE_USER:-}" ]          && env_args="$env_args ORACLE_USER='${ORACLE_USER}'"

    log_info "Executing $script_name locally in $local_dir ..."
    local exec_exit=0
    (
        cd "$local_dir"
        eval "export $env_args"
        bash "$script_path"
    ) || exec_exit=$?

    if [ $exec_exit -ne 0 ]; then
        log_warn "Local ZDM server discovery returned exit code $exec_exit"
    fi

    # Collect output files
    log_info "Listing output directory ($local_dir) ..."
    ls -la "$local_dir"/ 2>/dev/null | while IFS= read -r line; do log_info "  $line"; done

    if ls "$local_dir/"*.txt "$local_dir/"*.json 2>/dev/null | grep -q .; then
        cp "$local_dir/"*.txt "$local_dir/"*.json "$results_dir/" 2>/dev/null && \
            log_info "Output files collected to $results_dir"
        ls -la "$results_dir/" | while IFS= read -r line; do log_info "  $line"; done
    else
        log_warn "No output files found in $local_dir"
    fi

    rm -rf "$local_dir" 2>/dev/null || true

    local count
    count=$(ls "$results_dir/"*.txt "$results_dir/"*.json 2>/dev/null | wc -l)
    [ "$count" -gt 0 ] && return 0 || return 1
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    echo ""
    echo -e "${BOLD}${CYAN}============================================================${NC}"
    echo -e "${BOLD}${CYAN}  ZDM Phase 10 â€” Step 2: Discovery Orchestration${NC}"
    echo -e "${BOLD}${CYAN}  Started  : $(date)${NC}"
    echo -e "${BOLD}${CYAN}  Run by   : $(whoami)@$(hostname)${NC}"
    echo -e "${BOLD}${CYAN}============================================================${NC}"

    # SSH key diagnostics (most common failure source)
    log_upfront_ssh_diagnostics

    # Configuration summary (no exit â€” different from show_config)
    log_section "CONFIGURATION SUMMARY"
    log_info "SOURCE_HOST        : $SOURCE_HOST"
    log_info "TARGET_HOST        : $TARGET_HOST"
    log_info "SOURCE_ADMIN_USER  : $SOURCE_ADMIN_USER"
    log_info "TARGET_ADMIN_USER  : $TARGET_ADMIN_USER"
    log_info "ORACLE_USER        : $ORACLE_USER"
    log_info "ZDM_USER           : $ZDM_USER"
    log_info "SOURCE_SSH_KEY     : ${SOURCE_SSH_KEY:-<not set>}"
    log_info "TARGET_SSH_KEY     : ${TARGET_SSH_KEY:-<not set>}"
    log_info "OUTPUT_DIR         : $OUTPUT_DIR"
    log_info "REPO_ROOT          : $REPO_ROOT"
    log_info "VERBOSE            : $VERBOSE"

    validate_prerequisites
    test_all_connections

    if $TEST_ONLY; then
        log_section "TEST-ONLY MODE: Skipping discovery execution"
        exit 0
    fi

    # Create output subdirectories
    mkdir -p "$OUTPUT_DIR/source" "$OUTPUT_DIR/target" "$OUTPUT_DIR/server"

    # Build env args for overrides
    SOURCE_ENV_ARGS=""
    [ -n "${SOURCE_REMOTE_ORACLE_HOME:-}" ] && SOURCE_ENV_ARGS="SOURCE_REMOTE_ORACLE_HOME='$SOURCE_REMOTE_ORACLE_HOME' "
    [ -n "${SOURCE_REMOTE_ORACLE_SID:-}"  ] && SOURCE_ENV_ARGS="${SOURCE_ENV_ARGS}SOURCE_REMOTE_ORACLE_SID='$SOURCE_REMOTE_ORACLE_SID' "
    [ -n "${ORACLE_USER:-}" ]               && SOURCE_ENV_ARGS="${SOURCE_ENV_ARGS}ORACLE_USER='$ORACLE_USER' "

    TARGET_ENV_ARGS=""
    [ -n "${TARGET_REMOTE_ORACLE_HOME:-}" ] && TARGET_ENV_ARGS="TARGET_REMOTE_ORACLE_HOME='$TARGET_REMOTE_ORACLE_HOME' "
    [ -n "${TARGET_REMOTE_ORACLE_SID:-}"  ] && TARGET_ENV_ARGS="${TARGET_ENV_ARGS}TARGET_REMOTE_ORACLE_SID='$TARGET_REMOTE_ORACLE_SID' "
    [ -n "${ORACLE_USER:-}" ]               && TARGET_ENV_ARGS="${TARGET_ENV_ARGS}ORACLE_USER='$ORACLE_USER' "

    # --- Run source discovery ---
    SOURCE_SCRIPT="$SCRIPT_DIR/zdm_source_discovery.sh"
    if [ -f "$SOURCE_SCRIPT" ]; then
        run_remote_discovery \
            "SOURCE" \
            "$SOURCE_HOST" \
            "$SOURCE_ADMIN_USER" \
            "$SOURCE_SSH_KEY" \
            "$SOURCE_SCRIPT" \
            "$SOURCE_ENV_ARGS" \
            "$OUTPUT_DIR/source" \
        && SOURCE_STATUS="SUCCESS" || { SOURCE_STATUS="FAILED"; FAILURES+=("SOURCE discovery"); }
    else
        log_error "Source discovery script not found: $SOURCE_SCRIPT"
        SOURCE_STATUS="FAILED"
        FAILURES+=("SOURCE script missing")
    fi

    # --- Run target discovery ---
    TARGET_SCRIPT="$SCRIPT_DIR/zdm_target_discovery.sh"
    if [ -f "$TARGET_SCRIPT" ]; then
        run_remote_discovery \
            "TARGET" \
            "$TARGET_HOST" \
            "$TARGET_ADMIN_USER" \
            "$TARGET_SSH_KEY" \
            "$TARGET_SCRIPT" \
            "$TARGET_ENV_ARGS" \
            "$OUTPUT_DIR/target" \
        && TARGET_STATUS="SUCCESS" || { TARGET_STATUS="FAILED"; FAILURES+=("TARGET discovery"); }
    else
        log_error "Target discovery script not found: $TARGET_SCRIPT"
        TARGET_STATUS="FAILED"
        FAILURES+=("TARGET script missing")
    fi

    # --- Run ZDM server discovery (local) ---
    SERVER_SCRIPT="$SCRIPT_DIR/zdm_server_discovery.sh"
    if [ -f "$SERVER_SCRIPT" ]; then
        run_local_discovery \
            "$SERVER_SCRIPT" \
            "$OUTPUT_DIR/server" \
        && SERVER_STATUS="SUCCESS" || { SERVER_STATUS="FAILED"; FAILURES+=("SERVER discovery"); }
    else
        log_error "Server discovery script not found: $SERVER_SCRIPT"
        SERVER_STATUS="FAILED"
        FAILURES+=("SERVER script missing")
    fi

    # =========================================================================
    # FINAL SUMMARY
    # =========================================================================
    log_section "DISCOVERY SUMMARY"

    local success_icon fail_icon
    success_icon="âœ…"
    fail_icon="âŒ"

    echo ""
    printf "  %-20s  %s\n" "Server" "Status"
    printf "  %-20s  %s\n" "--------------------" "-------"
    printf "  %-20s  %s\n" "Source (${SOURCE_HOST})" \
        "$([ "$SOURCE_STATUS" = "SUCCESS" ] && echo "$success_icon SUCCESS" || echo "$fail_icon FAILED")"
    printf "  %-20s  %s\n" "Target (${TARGET_HOST})" \
        "$([ "$TARGET_STATUS" = "SUCCESS" ] && echo "$success_icon SUCCESS" || echo "$fail_icon FAILED")"
    printf "  %-20s  %s\n" "ZDM Server (local)" \
        "$([ "$SERVER_STATUS" = "SUCCESS" ] && echo "$success_icon SUCCESS" || echo "$fail_icon FAILED")"
    echo ""

    log_info "Output directory: $OUTPUT_DIR"
    echo ""
    log_info "Collected files:"
    find "$OUTPUT_DIR" -name '*.txt' -o -name '*.json' 2>/dev/null | sort | while IFS= read -r f; do
        log_info "  $f"
    done

    if [ ${#FAILURES[@]} -gt 0 ]; then
        log_warn "Failures encountered: ${FAILURES[*]}"
        log_warn "Review logs above for details. Partial discovery results have been saved."
        echo ""
        echo -e "${YELLOW}âš ï¸  Discovery completed with failures.${NC}"
        echo    "   Commit the available results and review failures before proceeding."
        echo    "   Next step: @Phase10-ZDM-Step3-Discovery-Questionnaire"
        exit 1
    else
        echo -e "${GREEN}âœ… Discovery completed successfully for all servers.${NC}"
        echo    "   Commit the discovery output before proceeding."
        echo    "   Next step: @Phase10-ZDM-Step3-Discovery-Questionnaire"
        exit 0
    fi
}

main "$@"
