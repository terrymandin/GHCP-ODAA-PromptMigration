#!/bin/bash
# =============================================================================
# zdm_orchestrate_discovery.sh
# ZDM Discovery Orchestration Script
# Project: ORADB
# Generated: 2026-02-27
#
# USAGE:
#   ./zdm_orchestrate_discovery.sh [OPTIONS]
#
# OPTIONS:
#   -h, --help      Show help and exit
#   -c, --config    Show current configuration and exit
#   -t, --test      Test SSH connectivity only (no discovery)
#
# DESCRIPTION:
#   Orchestrates discovery across source DB, target DB, and ZDM server.
#   Copies discovery scripts to each server, executes them, and collects
#   output files into the local Artifacts directory.
#
# PRE-REQUISITES:
#   - SSH access to all three servers
#   - SSH keys configured (see configuration below)
#   - Run from the Scripts/ directory or any directory with PATH to this script
#
# OUTPUT:
#   Artifacts/Phase10-Migration/ZDM/ORADB/Step0/Discovery/
#     source/   - Source database discovery results
#     target/   - Target database discovery results
#     server/   - ZDM server discovery results
# =============================================================================

# --- Color Output ---
RED='\033[0;31m'; YELLOW='\033[0;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

log_info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }
log_section() { echo -e "\n${BOLD}${CYAN}================================================================${NC}"
                echo -e "${BOLD}${CYAN}  $*${NC}"
                echo -e "${BOLD}${CYAN}================================================================${NC}"; }

# =============================================================================
# USER CONFIGURATION
# (Pre-populated from zdm-env.md - override with environment variables)
# =============================================================================

# --- Server Hostnames ---
SOURCE_HOST="${SOURCE_HOST:-10.1.0.11}"
TARGET_HOST="${TARGET_HOST:-10.0.1.160}"
ZDM_HOST="${ZDM_HOST:-10.1.0.8}"

# --- SSH Admin Users (separate user per server) ---
SOURCE_ADMIN_USER="${SOURCE_ADMIN_USER:-azureuser}"
TARGET_ADMIN_USER="${TARGET_ADMIN_USER:-opc}"
ZDM_ADMIN_USER="${ZDM_ADMIN_USER:-azureuser}"

# --- SSH Keys (separate keys per security domain) ---
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-${HOME}/.ssh/odaa.pem}"
TARGET_SSH_KEY="${TARGET_SSH_KEY:-${HOME}/.ssh/odaa.pem}"
ZDM_SSH_KEY="${ZDM_SSH_KEY:-${HOME}/.ssh/zdm.pem}"

# --- Application Users ---
ORACLE_USER="${ORACLE_USER:-oracle}"
ZDM_USER="${ZDM_USER:-zdmuser}"

# --- Oracle Path Overrides (leave blank for auto-detection) ---
SOURCE_REMOTE_ORACLE_HOME="${SOURCE_REMOTE_ORACLE_HOME:-}"
SOURCE_REMOTE_ORACLE_SID="${SOURCE_REMOTE_ORACLE_SID:-}"
TARGET_REMOTE_ORACLE_HOME="${TARGET_REMOTE_ORACLE_HOME:-}"
TARGET_REMOTE_ORACLE_SID="${TARGET_REMOTE_ORACLE_SID:-}"

# --- OCI Configuration ---
OCI_COMPARTMENT_OCID="${OCI_COMPARTMENT_OCID:-ocid1.compartment.oc1..aaaaaaaas4upnqj72dfiivgwvn3uui5gkxo7ng6leeoifucbjiy326urbhmq}"
TARGET_DATABASE_OCID="${TARGET_DATABASE_OCID:-ocid1.database.oc1.uk-london-1.anwgiljss56liuaatz45cjnpbvpgku7gkorvxg6lytoj5lxxruk2eqxzkzma}"
OCI_CONFIG_PATH="${OCI_CONFIG_PATH:-${HOME}/.oci/config}"

# --- SSH Options ---
SSH_OPTS="-o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=30"

# --- Script Directory and Repository Root ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Scripts/ is 6 levels below RepoRoot:
# Scripts â†’ Step0 â†’ ORADB â†’ ZDM â†’ Phase10-Migration â†’ Artifacts â†’ RepoRoot
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd 2>/dev/null || echo "$SCRIPT_DIR/../../../../../../..")"

# --- Output Directory ---
# Default: relative to repo root. Can be overridden via OUTPUT_DIR env variable.
if [ -z "${OUTPUT_DIR:-}" ]; then
    OUTPUT_DIR="${REPO_ROOT}/Artifacts/Phase10-Migration/ZDM/ORADB/Step0/Discovery"
fi

# --- Status Tracking ---
SOURCE_STATUS="NOT_RUN"
TARGET_STATUS="NOT_RUN"
SERVER_STATUS="NOT_RUN"
OVERALL_ERRORS=0

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

TEST_ONLY=false

show_help() {
    cat <<HELPEOF
Usage: $0 [OPTIONS]

ZDM Discovery Orchestration Script - Project ORADB

Options:
  -h, --help      Show this help message and exit
  -c, --config    Display current configuration and exit
  -t, --test      Test SSH connectivity only (no discovery scripts run)

Description:
  Orchestrates ZDM discovery across all three servers:
    1. Source database server  (${SOURCE_HOST})
    2. Target database server  (${TARGET_HOST})
    3. ZDM server              (${ZDM_HOST})

  Discovery results are collected to:
    ${OUTPUT_DIR}/

Environment Variable Overrides:
  SOURCE_HOST / TARGET_HOST / ZDM_HOST
  SOURCE_ADMIN_USER / TARGET_ADMIN_USER / ZDM_ADMIN_USER
  SOURCE_SSH_KEY / TARGET_SSH_KEY / ZDM_SSH_KEY
  ORACLE_USER / ZDM_USER
  SOURCE_REMOTE_ORACLE_HOME / SOURCE_REMOTE_ORACLE_SID
  TARGET_REMOTE_ORACLE_HOME / TARGET_REMOTE_ORACLE_SID
  OCI_COMPARTMENT_OCID / TARGET_DATABASE_OCID
  OUTPUT_DIR (override output directory)

Security Notes:
  - SSH keys must be pre-configured (no password prompts)
  - SQL passwords are NOT used in discovery (read-only)
  - OCI CLI config must be set up on each server for OCI queries

HELPEOF
    exit 0
}

show_config() {
    cat <<CFGEOF
================================================================
  Configuration - ORADB Discovery
================================================================
  Source Host:         $SOURCE_HOST
  Source Admin User:   $SOURCE_ADMIN_USER
  Source SSH Key:      $SOURCE_SSH_KEY

  Target Host:         $TARGET_HOST
  Target Admin User:   $TARGET_ADMIN_USER
  Target SSH Key:      $TARGET_SSH_KEY

  ZDM Host:            $ZDM_HOST
  ZDM Admin User:      $ZDM_ADMIN_USER
  ZDM SSH Key:         $ZDM_SSH_KEY

  Oracle User:         $ORACLE_USER
  ZDM User:            $ZDM_USER

  Oracle Overrides:
    SOURCE_ORACLE_HOME: ${SOURCE_REMOTE_ORACLE_HOME:-auto-detect}
    SOURCE_ORACLE_SID:  ${SOURCE_REMOTE_ORACLE_SID:-auto-detect}
    TARGET_ORACLE_HOME: ${TARGET_REMOTE_ORACLE_HOME:-auto-detect}
    TARGET_ORACLE_SID:  ${TARGET_REMOTE_ORACLE_SID:-auto-detect}

  OCI Compartment:     ${OCI_COMPARTMENT_OCID:-not set}
  Target DB OCID:      ${TARGET_DATABASE_OCID:-not set}
  OCI Config:          $OCI_CONFIG_PATH

  Script Directory:    $SCRIPT_DIR
  Repository Root:     $REPO_ROOT
  Output Directory:    $OUTPUT_DIR
================================================================
CFGEOF
    exit 0
}

# Argument parsing ONLY - show_help and show_config must only be called here
for arg in "$@"; do
    case "$arg" in
        -h|--help)   show_help ;;
        -c|--config) show_config ;;
        -t|--test)   TEST_ONLY=true ;;
        *)           log_warn "Unknown option: $arg  (use -h for help)" ;;
    esac
done

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

validate_prerequisites() {
    log_section "Validating Prerequisites"
    local errors=0

    # Check SSH keys exist
    for key_label in "SOURCE:$SOURCE_SSH_KEY" "TARGET:$TARGET_SSH_KEY" "ZDM:$ZDM_SSH_KEY"; do
        local label="${key_label%%:*}"
        local key_path="${key_label#*:}"
        key_path=$(eval echo "$key_path")
        if [ -f "$key_path" ]; then
            log_success "$label SSH key found: $key_path"
        else
            log_error "$label SSH key NOT found: $key_path"
            errors=$((errors + 1))
        fi
    done

    # Check discovery scripts exist
    for script in zdm_source_discovery.sh zdm_target_discovery.sh zdm_server_discovery.sh; do
        if [ -f "${SCRIPT_DIR}/${script}" ]; then
            log_success "Script found: $script"
        else
            log_error "Script NOT found: ${SCRIPT_DIR}/${script}"
            errors=$((errors + 1))
        fi
    done

    # Warn if OCI not configured (non-fatal)
    if [ -z "${OCI_COMPARTMENT_OCID:-}" ]; then
        log_warn "OCI_COMPARTMENT_OCID not set - OCI queries in target discovery will be limited"
    fi

    if [ "$errors" -gt 0 ]; then
        log_error "Prerequisite check failed with $errors error(s)"
        log_error "Fix the above errors before running discovery"
        exit 1
    fi
    log_success "All prerequisites satisfied"
}

test_ssh_connection() {
    local host="$1"
    local user="$2"
    local key="$3"
    local label="$4"
    local key_expanded
    key_expanded=$(eval echo "$key")

    log_info "Testing SSH: ${user}@${host} (key: $key_expanded)"
    if ssh $SSH_OPTS -i "$key_expanded" "${user}@${host}" "echo 'SSH OK' && hostname" 2>/dev/null; then
        log_success "$label SSH: OK"
        return 0
    else
        log_error "$label SSH: FAILED (${user}@${host} with key $key_expanded)"
        return 1
    fi
}

test_all_connections() {
    log_section "Testing SSH Connectivity"
    local conn_errors=0

    test_ssh_connection "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$SOURCE_SSH_KEY" "Source" \
        || conn_errors=$((conn_errors + 1))
    test_ssh_connection "$TARGET_HOST" "$TARGET_ADMIN_USER" "$TARGET_SSH_KEY" "Target" \
        || conn_errors=$((conn_errors + 1))
    test_ssh_connection "$ZDM_HOST" "$ZDM_ADMIN_USER" "$ZDM_SSH_KEY" "ZDM Server" \
        || conn_errors=$((conn_errors + 1))

    if [ "$conn_errors" -gt 0 ]; then
        log_warn "$conn_errors SSH connection(s) failed"
        log_warn "Discovery will continue for reachable servers"
    else
        log_success "All SSH connections successful"
    fi

    return $conn_errors
}

run_remote_discovery() {
    local host="$1"
    local user="$2"
    local key="$3"
    local script_name="$4"
    local output_subdir="$5"
    local extra_env="$6"   # Optional: extra env vars to pass (space-separated KEY=VALUE pairs)
    local label="$7"

    local key_expanded
    key_expanded=$(eval echo "$key")
    local remote_dir="/tmp/zdm_discovery_$$"
    local local_output_dir="${OUTPUT_DIR}/${output_subdir}"
    local script_path="${SCRIPT_DIR}/${script_name}"

    log_info "Running $script_name on $host ($user)..."

    # Build env var argument string
    local env_arg=""
    [ -n "${extra_env:-}" ] && env_arg="$extra_env "

    # Execute the discovery script via SSH using login shell
    ssh $SSH_OPTS -i "$key_expanded" "${user}@${host}" \
        "mkdir -p $remote_dir && cd $remote_dir && ${env_arg}ORACLE_USER='$ORACLE_USER' ZDM_USER='$ZDM_USER' bash -l -s" \
        < "$script_path"
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        log_warn "$label: Script exited with code $exit_code (may still have produced output)"
    fi

    # Collect output files
    log_info "Collecting output files from $host:$remote_dir ..."
    mkdir -p "$local_output_dir"
    scp $SSH_OPTS -i "$key_expanded" "${user}@${host}:${remote_dir}/*.txt" \
        "$local_output_dir/" 2>/dev/null
    scp $SSH_OPTS -i "$key_expanded" "${user}@${host}:${remote_dir}/*.json" \
        "$local_output_dir/" 2>/dev/null

    local collected_files
    collected_files=$(ls "$local_output_dir"/*.txt "$local_output_dir"/*.json 2>/dev/null | wc -l | tr -d ' ')

    if [ "$collected_files" -gt 0 ]; then
        log_success "$label: $collected_files output file(s) collected to $local_output_dir"
        ls -la "$local_output_dir"/*.txt "$local_output_dir"/*.json 2>/dev/null
    else
        log_warn "$label: No output files collected - discovery may have failed"
        OVERALL_ERRORS=$((OVERALL_ERRORS + 1))
    fi

    # Cleanup remote temp directory
    ssh $SSH_OPTS -i "$key_expanded" "${user}@${host}" "rm -rf '$remote_dir'" 2>/dev/null

    return $exit_code
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    log_section "ZDM Discovery Orchestration  |  Project: ORADB"
    echo "  Start Time:     $(date)"
    echo "  Source Host:    ${SOURCE_ADMIN_USER}@${SOURCE_HOST}"
    echo "  Target Host:    ${TARGET_ADMIN_USER}@${TARGET_HOST}"
    echo "  ZDM Host:       ${ZDM_ADMIN_USER}@${ZDM_HOST}"
    echo "  Output Dir:     ${OUTPUT_DIR}"
    echo ""

    # ---------- Prerequisites ----------
    validate_prerequisites

    # ---------- Connectivity Test ----------
    test_all_connections
    local conn_result=$?

    if $TEST_ONLY; then
        log_section "Test Mode Complete"
        log_info "SSH connectivity test completed (no discovery scripts run)"
        log_info "Run without --test to execute full discovery"
        exit $conn_result
    fi

    # ---------- Create Output Directories ----------
    log_section "Creating Output Directories"
    mkdir -p "${OUTPUT_DIR}/source" "${OUTPUT_DIR}/target" "${OUTPUT_DIR}/server"
    log_success "Output directories created: ${OUTPUT_DIR}/{source,target,server}"

    # ---------- Source Discovery ----------
    log_section "Running Source Database Discovery"
    SOURCE_ENV=""
    [ -n "${SOURCE_REMOTE_ORACLE_HOME:-}" ] && \
        SOURCE_ENV="${SOURCE_ENV}SOURCE_REMOTE_ORACLE_HOME='$SOURCE_REMOTE_ORACLE_HOME' "
    [ -n "${SOURCE_REMOTE_ORACLE_SID:-}" ] && \
        SOURCE_ENV="${SOURCE_ENV}SOURCE_REMOTE_ORACLE_SID='$SOURCE_REMOTE_ORACLE_SID' "

    if run_remote_discovery \
        "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$SOURCE_SSH_KEY" \
        "zdm_source_discovery.sh" "source" \
        "${SOURCE_ENV}" "Source"; then
        SOURCE_STATUS="SUCCESS"
        log_success "Source discovery: COMPLETE"
    else
        SOURCE_STATUS="PARTIAL or FAILED"
        log_warn "Source discovery: completed with warnings"
    fi

    # ---------- Target Discovery ----------
    log_section "Running Target Database Discovery"
    TARGET_ENV=""
    [ -n "${TARGET_REMOTE_ORACLE_HOME:-}" ] && \
        TARGET_ENV="${TARGET_ENV}TARGET_REMOTE_ORACLE_HOME='$TARGET_REMOTE_ORACLE_HOME' "
    [ -n "${TARGET_REMOTE_ORACLE_SID:-}" ] && \
        TARGET_ENV="${TARGET_ENV}TARGET_REMOTE_ORACLE_SID='$TARGET_REMOTE_ORACLE_SID' "
    [ -n "${OCI_COMPARTMENT_OCID:-}" ] && \
        TARGET_ENV="${TARGET_ENV}OCI_COMPARTMENT_OCID='$OCI_COMPARTMENT_OCID' "
    [ -n "${TARGET_DATABASE_OCID:-}" ] && \
        TARGET_ENV="${TARGET_ENV}TARGET_DATABASE_OCID='$TARGET_DATABASE_OCID' "
    [ -n "${OCI_CONFIG_PATH:-}" ] && \
        TARGET_ENV="${TARGET_ENV}OCI_CONFIG_PATH='$OCI_CONFIG_PATH' "

    if run_remote_discovery \
        "$TARGET_HOST" "$TARGET_ADMIN_USER" "$TARGET_SSH_KEY" \
        "zdm_target_discovery.sh" "target" \
        "${TARGET_ENV}" "Target"; then
        TARGET_STATUS="SUCCESS"
        log_success "Target discovery: COMPLETE"
    else
        TARGET_STATUS="PARTIAL or FAILED"
        log_warn "Target discovery: completed with warnings"
    fi

    # ---------- ZDM Server Discovery ----------
    log_section "Running ZDM Server Discovery"
    # Pass SOURCE_HOST and TARGET_HOST so the server script can run connectivity tests
    ZDM_ENV="SOURCE_HOST='$SOURCE_HOST' TARGET_HOST='$TARGET_HOST' "

    if run_remote_discovery \
        "$ZDM_HOST" "$ZDM_ADMIN_USER" "$ZDM_SSH_KEY" \
        "zdm_server_discovery.sh" "server" \
        "${ZDM_ENV}" "ZDM Server"; then
        SERVER_STATUS="SUCCESS"
        log_success "ZDM Server discovery: COMPLETE"
    else
        SERVER_STATUS="PARTIAL or FAILED"
        log_warn "ZDM Server discovery: completed with warnings"
    fi

    # ---------- Final Report ----------
    log_section "Discovery Orchestration Complete"
    echo ""
    echo "  Results Summary:"
    printf "  %-20s %s\n" "Source Discovery:"  "${SOURCE_STATUS}"
    printf "  %-20s %s\n" "Target Discovery:"  "${TARGET_STATUS}"
    printf "  %-20s %s\n" "ZDM Server:      "  "${SERVER_STATUS}"
    echo ""
    echo "  Output Files:"
    if [ -d "${OUTPUT_DIR}" ]; then
        find "${OUTPUT_DIR}" -name "*.txt" -o -name "*.json" 2>/dev/null | sort | \
            while read -r f; do
                printf "    %s\n" "$f"
            done
    fi
    echo ""
    echo "  Total errors: $OVERALL_ERRORS"
    echo "  End Time: $(date)"
    echo ""
    echo "  Next Step:"
    echo "    Review the discovery output files in:"
    echo "    ${OUTPUT_DIR}/"
    echo ""
    echo "    Then run Step 1: Discovery Questionnaire"
    echo "    prompts/Phase10-Migration/ZDM/Step1-Discovery-Questionnaire.prompt.md"
    echo ""

    return $OVERALL_ERRORS
}

main "$@"
