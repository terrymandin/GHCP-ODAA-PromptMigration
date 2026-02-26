#!/bin/bash
# =============================================================================
# ZDM Discovery Orchestration Script
# =============================================================================
# Project  : PRODDB Migration to Oracle Database@Azure
# Generated: 2026-02-26
#
# USAGE:
#   ./zdm_orchestrate_discovery.sh [OPTIONS]
#
# OPTIONS:
#   -h, --help      Show this help message
#   -c, --config    Print current configuration and exit
#   -t, --test      Test SSH connectivity only (no discovery)
#
# PREREQUISITES (before running):
#   - SSH access from this machine to SOURCE, TARGET, and ZDM servers
#   - SSH keys for each server available locally
#   - sudo privileges for SOURCE_ADMIN_USER (on source) and TARGET_ADMIN_USER (on target)
#   - sudo privileges for ZDM_ADMIN_USER (on ZDM server)
#
# ENVIRONMENT OVERRIDES (optional):
#   export SOURCE_REMOTE_ORACLE_HOME=/u01/app/oracle/product/19c/dbhome_1
#   export SOURCE_REMOTE_ORACLE_SID=PRODDB
#   export TARGET_REMOTE_ORACLE_HOME=/u01/app/oracle/product/19c/dbhome_1
#   export TARGET_REMOTE_ORACLE_SID=
#   export ZDM_REMOTE_ZDM_HOME=/home/zdmuser/zdmhome
#   export ZDM_REMOTE_JAVA_HOME=/usr/java/latest
# =============================================================================

set -o pipefail

# ---------------------------------------------------------------------------
# Script location and paths
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Script is at: Artifacts/Phase10-Migration/ZDM/PRODDB/Step0/Scripts/
# Navigate up 6 levels:  Scripts → Step0 → PRODDB → ZDM → Phase10-Migration → Artifacts → RepoRoot
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../../.." && pwd)"

# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
log_info()    { echo -e "${GREEN}[INFO ] $(date '+%H:%M:%S') $*${RESET}"; }
log_warn()    { echo -e "${YELLOW}[WARN ] $(date '+%H:%M:%S') $*${RESET}"; }
log_error()   { echo -e "${RED}[ERROR] $(date '+%H:%M:%S') $*${RESET}"; }
log_section() {
    local bar="================================================================"
    echo ""
    echo -e "${CYAN}${BOLD}${bar}${RESET}"
    echo -e "${CYAN}${BOLD}  $*${RESET}"
    echo -e "${CYAN}${BOLD}${bar}${RESET}"
    echo ""
}
log_success() { echo -e "${GREEN}${BOLD}[OK   ] $(date '+%H:%M:%S') $*${RESET}"; }

# ===========================================================================
# CONFIGURATION — Pre-populated for PRODDB migration project
# ===========================================================================

# ---------------------------------------------------------------------------
# Server hostnames
# ---------------------------------------------------------------------------
SOURCE_HOST="${SOURCE_HOST:-proddb01.corp.example.com}"
TARGET_HOST="${TARGET_HOST:-proddb-oda.eastus.azure.example.com}"
ZDM_HOST="${ZDM_HOST:-zdm-jumpbox.corp.example.com}"

# ---------------------------------------------------------------------------
# SSH/admin user for each server
# IMPORTANT: These are the OS admin users used for SSH connections.
#            SQL/ZDM commands are run via sudo to the application user.
# ---------------------------------------------------------------------------
SOURCE_ADMIN_USER="${SOURCE_ADMIN_USER:-oracle}"          # on-premise uses oracle as admin
TARGET_ADMIN_USER="${TARGET_ADMIN_USER:-opc}"             # OCI/ODA uses opc
ZDM_ADMIN_USER="${ZDM_ADMIN_USER:-azureuser}"             # Azure VM uses azureuser

# ---------------------------------------------------------------------------
# Application software owners
# ---------------------------------------------------------------------------
ORACLE_USER="${ORACLE_USER:-oracle}"                      # Oracle database software owner
ZDM_USER="${ZDM_USER:-zdmuser}"                           # ZDM software owner

# ---------------------------------------------------------------------------
# SSH key paths (separate keys for each security domain)
# ---------------------------------------------------------------------------
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-${HOME}/.ssh/onprem_oracle_key}"
TARGET_SSH_KEY="${TARGET_SSH_KEY:-${HOME}/.ssh/oci_opc_key}"
ZDM_SSH_KEY="${ZDM_SSH_KEY:-${HOME}/.ssh/azure_key}"

# ---------------------------------------------------------------------------
# Optional explicit path overrides (leave blank for auto-detection)
# ---------------------------------------------------------------------------
SOURCE_REMOTE_ORACLE_HOME="${SOURCE_REMOTE_ORACLE_HOME:-}"
SOURCE_REMOTE_ORACLE_SID="${SOURCE_REMOTE_ORACLE_SID:-}"
TARGET_REMOTE_ORACLE_HOME="${TARGET_REMOTE_ORACLE_HOME:-}"
TARGET_REMOTE_ORACLE_SID="${TARGET_REMOTE_ORACLE_SID:-}"
ZDM_REMOTE_ZDM_HOME="${ZDM_REMOTE_ZDM_HOME:-}"
ZDM_REMOTE_JAVA_HOME="${ZDM_REMOTE_JAVA_HOME:-}"

# ---------------------------------------------------------------------------
# Output directory (absolute path)
# ---------------------------------------------------------------------------
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/Artifacts/Phase10-Migration/ZDM/PRODDB/Step0/Discovery}"

# ---------------------------------------------------------------------------
# SSH options
# ---------------------------------------------------------------------------
SSH_OPTS="-o StrictHostKeyChecking=no \
          -o ConnectTimeout=30 \
          -o BatchMode=yes \
          -o ServerAliveInterval=60 \
          -o ServerAliveCountMax=5"

# ---------------------------------------------------------------------------
# Remote working directory on each server
# ---------------------------------------------------------------------------
REMOTE_WORK_DIR="/tmp/zdm_proddb_discovery_$$"

# ---------------------------------------------------------------------------
# Error tracking
# ---------------------------------------------------------------------------
SOURCE_SUCCESS=false
TARGET_SUCCESS=false
ZDM_SUCCESS=false

# ===========================================================================
# HELP / CONFIG
# ===========================================================================

show_help() {
    cat <<EOF

ZDM Discovery Orchestration Script
Project: PRODDB Migration to Oracle Database@Azure

USAGE:
  $0 [OPTIONS]

OPTIONS:
  -h, --help      Show this help message
  -c, --config    Print current configuration
  -t, --test      Test SSH connectivity only (no discovery)

ENVIRONMENT OVERRIDES (set before running):
  SOURCE_HOST               Source database hostname
  TARGET_HOST               Target Oracle Database@Azure hostname
  ZDM_HOST                  ZDM jumpbox hostname
  SOURCE_ADMIN_USER         SSH admin user for source (default: oracle)
  TARGET_ADMIN_USER         SSH admin user for target (default: opc)
  ZDM_ADMIN_USER            SSH admin user for ZDM server (default: azureuser)
  SOURCE_SSH_KEY            SSH private key for source
  TARGET_SSH_KEY            SSH private key for target
  ZDM_SSH_KEY               SSH private key for ZDM server
  OUTPUT_DIR                Output directory for discovery results

PATH OVERRIDES (when auto-detection fails):
  SOURCE_REMOTE_ORACLE_HOME
  SOURCE_REMOTE_ORACLE_SID
  TARGET_REMOTE_ORACLE_HOME
  TARGET_REMOTE_ORACLE_SID
  ZDM_REMOTE_ZDM_HOME
  ZDM_REMOTE_JAVA_HOME

EXAMPLES:
  # Run with defaults:
  ./zdm_orchestrate_discovery.sh

  # Test connectivity only:
  ./zdm_orchestrate_discovery.sh --test

  # Override Oracle SID (if auto-detection fails):
  SOURCE_REMOTE_ORACLE_SID=PRODDB ./zdm_orchestrate_discovery.sh

EOF
    exit 0
}

show_config() {
    cat <<EOF

============================================================
  CURRENT CONFIGURATION
============================================================
  Project       : PRODDB Migration to Oracle Database@Azure
  Script Dir    : $SCRIPT_DIR
  Repo Root     : $REPO_ROOT
  Output Dir    : $OUTPUT_DIR

  SOURCE_HOST         : $SOURCE_HOST
  SOURCE_ADMIN_USER   : $SOURCE_ADMIN_USER
  SOURCE_SSH_KEY      : $SOURCE_SSH_KEY
  SOURCE_ORACLE_HOME  : ${SOURCE_REMOTE_ORACLE_HOME:-"(auto-detect)"}
  SOURCE_ORACLE_SID   : ${SOURCE_REMOTE_ORACLE_SID:-"(auto-detect)"}

  TARGET_HOST         : $TARGET_HOST
  TARGET_ADMIN_USER   : $TARGET_ADMIN_USER
  TARGET_SSH_KEY      : $TARGET_SSH_KEY
  TARGET_ORACLE_HOME  : ${TARGET_REMOTE_ORACLE_HOME:-"(auto-detect)"}
  TARGET_ORACLE_SID   : ${TARGET_REMOTE_ORACLE_SID:-"(auto-detect)"}

  ZDM_HOST            : $ZDM_HOST
  ZDM_ADMIN_USER      : $ZDM_ADMIN_USER
  ZDM_SSH_KEY         : $ZDM_SSH_KEY
  ZDM_REMOTE_ZDM_HOME : ${ZDM_REMOTE_ZDM_HOME:-"(auto-detect)"}
  ZDM_REMOTE_JAVA_HOME: ${ZDM_REMOTE_JAVA_HOME:-"(auto-detect)"}

  ORACLE_USER         : $ORACLE_USER
  ZDM_USER            : $ZDM_USER
============================================================

EOF
    exit 0
}

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        -h|--help)   show_help ;;
        -c|--config) show_config ;;
        -t|--test)   TEST_ONLY=true ;;
    esac
done

# ===========================================================================
# VALIDATION
# ===========================================================================

validate_prerequisites() {
    log_section "VALIDATING PREREQUISITES"
    local errors=0

    # Check SSH keys exist
    for _key_var in SOURCE_SSH_KEY TARGET_SSH_KEY ZDM_SSH_KEY; do
        local _key_val="${!_key_var}"
        _key_val="${_key_val/#\~/$HOME}"   # expand ~
        if [ ! -f "$_key_val" ]; then
            log_warn "SSH key not found: ${_key_var}=${_key_val}"
            log_warn "  → Ensure the key exists, or set ${_key_var} to the correct path"
            errors=$((errors + 1))
        else
            log_info "SSH key found: ${_key_var}=${_key_val}"
            chmod 600 "$_key_val" 2>/dev/null || true
        fi
    done

    # Check discovery scripts exist
    for _script in zdm_source_discovery.sh zdm_target_discovery.sh zdm_server_discovery.sh; do
        if [ ! -f "$SCRIPT_DIR/$_script" ]; then
            log_error "Discovery script missing: $SCRIPT_DIR/$_script"
            errors=$((errors + 1))
        else
            log_info "Discovery script found: $_script"
        fi
    done

    if [ "$errors" -gt 0 ]; then
        log_warn "$errors prerequisite warnings. Discovery will continue but some servers may fail."
        log_warn "Run with --config to review settings."
    fi
    return 0
}

# ===========================================================================
# SSH CONNECTIVITY TEST
# ===========================================================================

test_ssh_connection() {
    local host="$1"
    local user="$2"
    local key="$3"
    local label="$4"
    local expanded_key="${key/#\~/$HOME}"

    echo -n "  Testing SSH ${label} (${user}@${host})... "
    if ssh $SSH_OPTS -i "$expanded_key" "${user}@${host}" \
            "echo 'SSH_OK' && id && hostname" 2>/dev/null | grep -q 'SSH_OK'; then
        echo -e "${GREEN}OK${RESET}"
        return 0
    else
        echo -e "${RED}FAILED${RESET}"
        log_warn "    → Check: key=${expanded_key}, user=${user}, host=${host}"
        log_warn "    → Ensure passwordless sudo is configured for this user"
        return 1
    fi
}

test_all_connections() {
    log_section "SSH CONNECTIVITY TESTS"
    local conn_errors=0

    test_ssh_connection "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$SOURCE_SSH_KEY" "Source" || conn_errors=$((conn_errors + 1))
    test_ssh_connection "$TARGET_HOST" "$TARGET_ADMIN_USER" "$TARGET_SSH_KEY" "Target" || conn_errors=$((conn_errors + 1))
    test_ssh_connection "$ZDM_HOST"    "$ZDM_ADMIN_USER"    "$ZDM_SSH_KEY"    "ZDM"    || conn_errors=$((conn_errors + 1))

    echo ""
    if [ "$conn_errors" -eq 0 ]; then
        log_success "All SSH connections successful"
    else
        log_warn "$conn_errors SSH connection(s) failed. Discovery will still run on reachable servers."
    fi
}

if [ "${TEST_ONLY:-false}" = "true" ]; then
    test_all_connections
    exit 0
fi

# ===========================================================================
# DISCOVERY EXECUTION
# ===========================================================================

create_output_dirs() {
    log_info "Creating output directories under: $OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR/source" "$OUTPUT_DIR/target" "$OUTPUT_DIR/server" || {
        log_error "Failed to create output directories"
        exit 1
    }
}

# Run discovery on a single server
# Args: host user key script subdirname env_overrides
run_server_discovery() {
    local host="$1"
    local user="$2"
    local key="$3"
    local script_name="$4"
    local subdir="$5"
    local env_overrides="$6"

    local expanded_key="${key/#\~/$HOME}"
    local script_path="$SCRIPT_DIR/$script_name"
    local dest_dir="$OUTPUT_DIR/$subdir"

    log_section "RUNNING DISCOVERY: $host ($user)"

    # ---- Step 1: Create remote work directory ----
    log_info "Creating remote work directory: $REMOTE_WORK_DIR"
    if ! ssh $SSH_OPTS -i "$expanded_key" "${user}@${host}" \
            "mkdir -p '${REMOTE_WORK_DIR}'" 2>&1; then
        log_error "Cannot create remote work directory on $host — skipping"
        return 1
    fi

    # ---- Step 2: Copy discovery script ----
    log_info "Copying $script_name to ${user}@${host}:${REMOTE_WORK_DIR}/"
    if ! scp -q $SSH_OPTS -i "$expanded_key" \
            "$script_path" "${user}@${host}:${REMOTE_WORK_DIR}/${script_name}" 2>&1; then
        log_error "Failed to copy $script_name to $host — skipping"
        return 1
    fi

    # ---- Step 3: Execute discovery script (login shell for full env sourcing) ----
    log_info "Executing $script_name on $host..."
    local env_setup="export ORACLE_USER='${ORACLE_USER}'; export ZDM_USER='${ZDM_USER}'; ${env_overrides}"

    local remote_exit_code
    ssh $SSH_OPTS -i "$expanded_key" "${user}@${host}" \
        "bash -l -c '
            cd \"${REMOTE_WORK_DIR}\" || exit 1
            chmod +x \"${script_name}\"
            ${env_setup}
            ./${script_name}
            echo \"EXIT_CODE:\$?\"
        '" 2>&1 | tee -a "$dest_dir/${script_name%.sh}_console.log"
    remote_exit_code=${PIPESTATUS[0]}

    if [ "$remote_exit_code" -ne 0 ]; then
        log_warn "Script exited with non-zero code ($remote_exit_code) on $host — may be partial results"
    fi

    # ---- Step 4: Collect output files ----
    log_info "Collecting discovery output files from ${user}@${host}..."
    scp -q $SSH_OPTS -i "$expanded_key" \
        "${user}@${host}:${REMOTE_WORK_DIR}/*.txt" \
        "${user}@${host}:${REMOTE_WORK_DIR}/*.json" \
        "$dest_dir/" 2>/dev/null && \
    log_success "Discovery files collected to: $dest_dir" || \
    log_warn "Some output files may be missing from $host"

    # ---- Step 5: Clean up remote work directory ----
    log_info "Cleaning up remote work directory on $host..."
    ssh $SSH_OPTS -i "$expanded_key" "${user}@${host}" \
        "rm -rf '${REMOTE_WORK_DIR}'" 2>/dev/null || \
    log_warn "Could not remove $REMOTE_WORK_DIR on $host (non-critical)"

    # Check that we got at least a text file
    local collected_files
    collected_files=$(ls "$dest_dir"/*.txt 2>/dev/null | wc -l)
    if [ "$collected_files" -gt 0 ]; then
        log_success "SUCCESS: $collected_files output file(s) collected for $host"
        ls -lh "$dest_dir"/*.txt "$dest_dir"/*.json 2>/dev/null
        return 0
    else
        log_warn "No output files collected for $host"
        return 1
    fi
}

# ===========================================================================
# MAIN
# ===========================================================================

log_section "ZDM DISCOVERY ORCHESTRATION — PRODDB"
echo "  Started  : $(date)"
echo "  Repo root: $REPO_ROOT"
echo "  Output   : $OUTPUT_DIR"
echo ""

show_config > /dev/null 2>&1  # suppress output but validate config

validate_prerequisites
test_all_connections
create_output_dirs

# ---------------------------------------------------------------------------
# SOURCE DATABASE DISCOVERY
# ---------------------------------------------------------------------------
log_section "SOURCE DATABASE DISCOVERY"
SOURCE_ENV_OVERRIDES="export ORACLE_HOME_OVERRIDE='${SOURCE_REMOTE_ORACLE_HOME}'; \
                      export ORACLE_SID_OVERRIDE='${SOURCE_REMOTE_ORACLE_SID}'"
if run_server_discovery \
       "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$SOURCE_SSH_KEY" \
       "zdm_source_discovery.sh" "source" \
       "$SOURCE_ENV_OVERRIDES"; then
    SOURCE_SUCCESS=true
    log_success "Source discovery SUCCEEDED"
else
    log_error "Source discovery FAILED — check ${OUTPUT_DIR}/source/ for partial results"
fi

# ---------------------------------------------------------------------------
# TARGET DATABASE DISCOVERY
# ---------------------------------------------------------------------------
log_section "TARGET DATABASE DISCOVERY"
TARGET_ENV_OVERRIDES="export ORACLE_HOME_OVERRIDE='${TARGET_REMOTE_ORACLE_HOME}'; \
                      export ORACLE_SID_OVERRIDE='${TARGET_REMOTE_ORACLE_SID}'"
if run_server_discovery \
       "$TARGET_HOST" "$TARGET_ADMIN_USER" "$TARGET_SSH_KEY" \
       "zdm_target_discovery.sh" "target" \
       "$TARGET_ENV_OVERRIDES"; then
    TARGET_SUCCESS=true
    log_success "Target discovery SUCCEEDED"
else
    log_error "Target discovery FAILED — check ${OUTPUT_DIR}/target/ for partial results"
fi

# ---------------------------------------------------------------------------
# ZDM SERVER DISCOVERY
# Note: SOURCE_HOST and TARGET_HOST are passed so the server discovery script
#       can run network latency/connectivity tests to both endpoints.
# ---------------------------------------------------------------------------
log_section "ZDM SERVER DISCOVERY"
ZDM_ENV_OVERRIDES="export ZDM_HOME_OVERRIDE='${ZDM_REMOTE_ZDM_HOME}'; \
                   export JAVA_HOME_OVERRIDE='${ZDM_REMOTE_JAVA_HOME}'; \
                   export SOURCE_HOST='${SOURCE_HOST}'; \
                   export TARGET_HOST='${TARGET_HOST}'; \
                   export ZDM_USER='${ZDM_USER}'"
if run_server_discovery \
       "$ZDM_HOST" "$ZDM_ADMIN_USER" "$ZDM_SSH_KEY" \
       "zdm_server_discovery.sh" "server" \
       "$ZDM_ENV_OVERRIDES"; then
    ZDM_SUCCESS=true
    log_success "ZDM server discovery SUCCEEDED"
else
    log_error "ZDM server discovery FAILED — check ${OUTPUT_DIR}/server/ for partial results"
fi

# ===========================================================================
# SUMMARY
# ===========================================================================

log_section "DISCOVERY SUMMARY"
echo "  Project      : PRODDB Migration to Oracle Database@Azure"
echo "  Completed    : $(date)"
echo "  Output Dir   : $OUTPUT_DIR"
echo ""
echo "  ┌─────────────────────────────────────────────────────────┐"
echo "  │  Server         │ Status                                │"
echo "  ├─────────────────────────────────────────────────────────┤"

if [ "$SOURCE_SUCCESS" = "true" ]; then
    echo -e "  │  Source (${SOURCE_HOST:0:25}) │ ${GREEN}SUCCESS${RESET}                               │"
else
    echo -e "  │  Source (${SOURCE_HOST:0:25}) │ ${RED}FAILED${RESET}                                │"
fi

if [ "$TARGET_SUCCESS" = "true" ]; then
    echo -e "  │  Target (${TARGET_HOST:0:25}) │ ${GREEN}SUCCESS${RESET}                               │"
else
    echo -e "  │  Target (${TARGET_HOST:0:25}) │ ${RED}FAILED${RESET}                                │"
fi

if [ "$ZDM_SUCCESS" = "true" ]; then
    echo -e "  │  ZDM    (${ZDM_HOST:0:25})   │ ${GREEN}SUCCESS${RESET}                               │"
else
    echo -e "  │  ZDM    (${ZDM_HOST:0:25})   │ ${RED}FAILED${RESET}                                │"
fi

echo "  └─────────────────────────────────────────────────────────┘"
echo ""

TOTAL_SUCCESS=0
[ "$SOURCE_SUCCESS" = "true" ] && TOTAL_SUCCESS=$((TOTAL_SUCCESS + 1))
[ "$TARGET_SUCCESS" = "true" ] && TOTAL_SUCCESS=$((TOTAL_SUCCESS + 1))
[ "$ZDM_SUCCESS"    = "true" ] && TOTAL_SUCCESS=$((TOTAL_SUCCESS + 1))

echo "  $TOTAL_SUCCESS of 3 discoveries successful"
echo ""

echo "  Collected files:"
find "$OUTPUT_DIR" -type f \( -name '*.txt' -o -name '*.json' \) | \
    sort | xargs ls -lh 2>/dev/null | awk '{print "    "$NF, $5}'

echo ""
if [ "$TOTAL_SUCCESS" -gt 0 ]; then
    echo -e "  ${GREEN}${BOLD}Proceed to Step 1: Discovery Questionnaire${RESET}"
    echo "  Attach files from: $OUTPUT_DIR"
    echo "  Prompt: prompts/Phase10-Migration/ZDM/Step1-Discovery-Questionnaire.prompt.md"
else
    echo -e "  ${RED}${BOLD}All discoveries failed.${RESET}"
    echo "  • Run --test to diagnose SSH connectivity"
    echo "  • Run --config to review settings"
    echo "  • Check server-specific logs above for details"
fi

echo ""

# Exit with non-zero only if ALL discoveries failed
if [ "$TOTAL_SUCCESS" -eq 0 ]; then
    exit 1
fi
exit 0
