#!/bin/bash
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration
#
# zdm_orchestrate_discovery.sh
# ZDM Step 2 — Discovery Orchestrator
#
# Purpose  : Orchestrates source, target, and ZDM server discovery end-to-end.
# Auth     : Must run as zdmuser on ZDM server.
# Outputs  : Per-script .txt/.json discovery files (retrieved via SCP)
#            zdm_orchestrate_run_<ts>.log
#            zdm_orchestrate_report_<ts>.md
#
# Usage:
#   sudo su - zdmuser
#   ./zdm_orchestrate_discovery.sh           # standard run
#   ./zdm_orchestrate_discovery.sh -v        # verbose
#   ./zdm_orchestrate_discovery.sh -c        # show effective config and exit
#   ./zdm_orchestrate_discovery.sh -h        # show help and exit

set -u

# ---------------------------------------------------------------------------
# Configuration defaults — override via environment or -v arg
# ---------------------------------------------------------------------------
SOURCE_HOST="${SOURCE_HOST:-10.200.1.12}"
TARGET_HOST="${TARGET_HOST:-10.200.0.250}"
SOURCE_ADMIN_USER="${SOURCE_ADMIN_USER:-azureuser}"
TARGET_ADMIN_USER="${TARGET_ADMIN_USER:-opc}"
ORACLE_USER="${ORACLE_USER:-oracle}"
ZDM_USER="${ZDM_USER:-zdmuser}"
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-}"
TARGET_SSH_KEY="${TARGET_SSH_KEY:-}"

# DB-specific values forwarded to remote scripts
SOURCE_REMOTE_ORACLE_HOME="${SOURCE_REMOTE_ORACLE_HOME:-/u01/app/oracle/product/19.0.0/dbhome_1}"
SOURCE_ORACLE_SID="${SOURCE_ORACLE_SID:-POCAKV}"
SOURCE_DATABASE_UNIQUE_NAME="${SOURCE_DATABASE_UNIQUE_NAME:-POCAKV}"
TARGET_REMOTE_ORACLE_HOME="${TARGET_REMOTE_ORACLE_HOME:-/u02/app/oracle/product/19.0.0.0/dbhome_1}"
TARGET_ORACLE_SID="${TARGET_ORACLE_SID:-POCAKV1}"
TARGET_DATABASE_UNIQUE_NAME="${TARGET_DATABASE_UNIQUE_NAME:-POCAKV_ODAA}"
ZDM_HOME="${ZDM_HOME:-/mnt/app/zdmhome}"

VERBOSE=0

SSH_OPTS="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -o PasswordAuthentication=no"
SCP_OPTS="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -o PasswordAuthentication=no"

# ---------------------------------------------------------------------------
# SSH key placeholder normalization
# ---------------------------------------------------------------------------
is_placeholder() { [[ "$1" == *"<"*">"* ]]; }
[ -n "$SOURCE_SSH_KEY" ] && is_placeholder "$SOURCE_SSH_KEY" && SOURCE_SSH_KEY=""
[ -n "$TARGET_SSH_KEY" ] && is_placeholder "$TARGET_SSH_KEY" && TARGET_SSH_KEY=""

# ---------------------------------------------------------------------------
# Timing and output paths
# ---------------------------------------------------------------------------
ts="$(date +%Y%m%d-%H%M%S)"
run_host="$(hostname 2>/dev/null || echo unknown)"
run_user="$(id -un 2>/dev/null || echo unknown)"
orch_dir="${HOME}/zdm-step2-orch-${ts}"
mkdir -p "${orch_dir}"
log_file="${orch_dir}/zdm_orchestrate_run_${ts}.log"
report_file="${orch_dir}/zdm_orchestrate_report_${ts}.md"

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log()      { printf -- '[%s] %s\n' "$(date +%H:%M:%S)" "$1" | tee -a "${log_file}"; }
log_pass() { printf -- '[%s] [PASS] %s\n' "$(date +%H:%M:%S)" "$1" | tee -a "${log_file}"; }
log_fail() { printf -- '[%s] [FAIL] %s\n' "$(date +%H:%M:%S)" "$1" | tee -a "${log_file}" >&2; }
log_warn() { printf -- '[%s] [WARN] %s\n' "$(date +%H:%M:%S)" "$1" | tee -a "${log_file}"; }

append_report() { printf -- '%s\n' "$1" >> "${report_file}"; }

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
show_help() {
  cat <<HELP
Usage: $(basename "$0") [OPTIONS]

Options:
  -h    Show this help message and exit
  -c    Show effective configuration and exit
  -v    Enable verbose output
  -t    Run connectivity tests only (ping/port checks)

HELP
  exit 0
}

show_config() {
  echo "=== Effective Configuration ==="
  echo "SOURCE_HOST           : ${SOURCE_HOST}"
  echo "TARGET_HOST           : ${TARGET_HOST}"
  echo "SOURCE_ADMIN_USER     : ${SOURCE_ADMIN_USER}"
  echo "TARGET_ADMIN_USER     : ${TARGET_ADMIN_USER}"
  echo "ORACLE_USER           : ${ORACLE_USER}"
  echo "ZDM_USER              : ${ZDM_USER}"
  echo "SOURCE_SSH_KEY        : ${SOURCE_SSH_KEY:-<not set — using SSH agent/default>}"
  echo "TARGET_SSH_KEY        : ${TARGET_SSH_KEY:-<not set — using SSH agent/default>}"
  echo "SOURCE_ORACLE_SID     : ${SOURCE_ORACLE_SID}"
  echo "SOURCE_REMOTE_ORACLE_HOME : ${SOURCE_REMOTE_ORACLE_HOME}"
  echo "TARGET_ORACLE_SID     : ${TARGET_ORACLE_SID}"
  echo "TARGET_REMOTE_ORACLE_HOME : ${TARGET_REMOTE_ORACLE_HOME}"
  echo "ZDM_HOME              : ${ZDM_HOME}"
  exit 0
}

while getopts "hcvt" opt; do
  case "${opt}" in
    h) show_help ;;
    c) show_config ;;
    v) VERBOSE=1 ;;
    t) echo "Connectivity test mode — run zdm_server_discovery.sh for port checks." ; exit 0 ;;
    *) show_help ;;
  esac
done

# ---------------------------------------------------------------------------
# User guard — must run as zdmuser
# ---------------------------------------------------------------------------
if [ "${run_user}" != "${ZDM_USER}" ]; then
  echo "[ERROR] This script must run as '${ZDM_USER}'. Currently running as '${run_user}'."
  echo "        Switch to the correct user first: sudo su - ${ZDM_USER}"
  exit 1
fi

# ---------------------------------------------------------------------------
# Startup diagnostics
# ---------------------------------------------------------------------------
log "=== ZDM Step 2 Discovery Orchestrator ==="
log "Run user    : ${run_user}"
log "Run host    : ${run_host}"
log "Home        : ${HOME}"
log "Timestamp   : ${ts}"
log "Log file    : ${log_file}"
log "Report file : ${report_file}"
log ""

# SSH key file inventory
log "=== SSH Key Inventory ==="
if ls "${HOME}/.ssh"/*.pem "${HOME}/.ssh"/*.key 2>/dev/null | head -20 | tee -a "${log_file}"; then
  : # at least one key found
else
  log_warn "No .pem or .key files found in ${HOME}/.ssh/"
fi

# Normalized key resolution
log ""
log "=== SSH Key Resolution ==="
if [[ -n "${SOURCE_SSH_KEY}" ]]; then
  log "SOURCE_SSH_KEY (resolved) : ${SOURCE_SSH_KEY}"
  if [[ -f "${SOURCE_SSH_KEY}" ]]; then
    log "  existence check: PASS"
  else
    log_warn "  existence check: FAIL — file not found: ${SOURCE_SSH_KEY}"
  fi
else
  log "SOURCE_SSH_KEY : <not set — SSH agent/default key will be used>"
fi

if [[ -n "${TARGET_SSH_KEY}" ]]; then
  log "TARGET_SSH_KEY (resolved) : ${TARGET_SSH_KEY}"
  if [[ -f "${TARGET_SSH_KEY}" ]]; then
    log "  existence check: PASS"
  else
    log_warn "  existence check: FAIL — file not found: ${TARGET_SSH_KEY}"
  fi
else
  log "TARGET_SSH_KEY : <not set — SSH agent/default key will be used>"
fi

# ---------------------------------------------------------------------------
# Track per-script results
# ---------------------------------------------------------------------------
source_status="PENDING"
target_status="PENDING"
server_status="PENDING"
source_txt="" source_json="" source_log=""
target_txt="" target_json="" target_log=""
server_txt="" server_json="" server_log=""

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Helper: run remote discovery script via SSH
# ---------------------------------------------------------------------------
run_remote_discovery() {
  local dtype="$1"         # source or target
  local host="$2"
  local admin_user="$3"
  local key_path="$4"
  local script_name="$5"
  local extra_env="$6"

  local local_script="${script_dir}/${script_name}"

  if [[ ! -f "${local_script}" ]]; then
    log_fail "${dtype}: script not found locally: ${local_script}"
    printf -- 'FAIL'
    return 1
  fi

  # Resolve $HOME on the remote host — the remote user (e.g. azureuser, opc) has a
  # different home than the local zdmuser, so we must NOT use the local $HOME here.
  local remote_home
  remote_home=$(ssh ${SSH_OPTS} ${key_path:+-i "${key_path}"} "${admin_user}@${host}" \
      'echo $HOME' 2>>"${log_file}")
  if [[ -z "${remote_home}" ]]; then
    log_fail "${dtype}: Could not determine remote home directory for ${admin_user}@${host}. Aborting ${dtype} discovery."
    printf -- 'FAIL'
    return 1
  fi
  local remote_dir="${remote_home}/zdm-step2-${dtype}-${ts}"

  log "---"
  log "${dtype}: Remote home resolved to ${remote_home} for ${admin_user}@${host}"
  log "${dtype}: Copying ${script_name} to ${admin_user}@${host}:${remote_dir}/"

  # Setup remote working directory — fail fast if this fails
  if ! ssh ${SSH_OPTS} ${key_path:+-i "${key_path}"} "${admin_user}@${host}" \
      "mkdir -p ${remote_dir}" 2>>"${log_file}"; then
    log_fail "${dtype}: Failed to create remote working directory ${remote_dir} on ${host}. Aborting ${dtype} discovery."
    printf -- 'FAIL'
    return 1
  fi

  # Copy script to remote
  if ! scp ${SCP_OPTS} ${key_path:+-i "${key_path}"} \
      "${local_script}" "${admin_user}@${host}:${remote_dir}/" 2>>"${log_file}"; then
    log_fail "${dtype}: SCP of ${script_name} to ${host} failed."
    printf -- 'FAIL'
    return 1
  fi

  log "${dtype}: Running ${script_name} on ${admin_user}@${host} (login shell)"

  # Execute with login shell, using $HOME-based absolute path (not quoted tilde)
  if ! ssh ${SSH_OPTS} ${key_path:+-i "${key_path}"} "${admin_user}@${host}" \
      "bash -l -s" < <(printf 'cd %q\n' "${remote_dir}"; \
        printf '%s\n' "OUTPUT_DIR=${remote_dir} ${extra_env} bash ${remote_dir}/${script_name}") \
      2>>"${log_file}" | tee -a "${log_file}"; then
    log_fail "${dtype}: Remote execution of ${script_name} on ${host} failed."
    printf -- 'FAIL'
    return 1
  fi

  # Verify remote output files exist before SCP retrieval
  log "${dtype}: Checking remote output files exist..."
  local remote_files
  if ! remote_files=$(ssh ${SSH_OPTS} ${key_path:+-i "${key_path}"} "${admin_user}@${host}" \
      "ls ${remote_dir}/zdm_${dtype}_discovery_*.txt ${remote_dir}/zdm_${dtype}_discovery_*.json 2>/dev/null" \
      2>>"${log_file}"); then
    log_fail "${dtype}: Remote output files not found in ${remote_dir} on ${host}."
    printf -- 'FAIL'
    return 1
  fi

  if [[ -z "${remote_files}" ]]; then
    log_fail "${dtype}: Remote output files empty listing from ${host}:${remote_dir}."
    printf -- 'FAIL'
    return 1
  fi

  log "${dtype}: Retrieving output files from ${host}..."
  local local_out_dir="${HOME}/zdm-step2-${dtype}-${ts}"
  mkdir -p "${local_out_dir}"
  if ! scp ${SCP_OPTS} ${key_path:+-i "${key_path}"} \
      "${admin_user}@${host}:${remote_dir}/zdm_${dtype}_discovery_*" \
      "${local_out_dir}/" 2>>"${log_file}"; then
    log_fail "${dtype}: SCP retrieval of output files from ${host} failed."
    printf -- 'FAIL'
    return 1
  fi

  log_pass "${dtype} discovery completed. Outputs in ${local_out_dir}/"
  printf -- 'PASS'
  return 0
}

# ---------------------------------------------------------------------------
# Source discovery
# ---------------------------------------------------------------------------
log "=== Running Source Discovery ==="
source_extra_env="SOURCE_REMOTE_ORACLE_HOME=${SOURCE_REMOTE_ORACLE_HOME} SOURCE_ORACLE_SID=${SOURCE_ORACLE_SID} SOURCE_DATABASE_UNIQUE_NAME=${SOURCE_DATABASE_UNIQUE_NAME} ORACLE_USER=${ORACLE_USER}"
source_status=$(run_remote_discovery "source" "${SOURCE_HOST}" "${SOURCE_ADMIN_USER}" "${SOURCE_SSH_KEY}" "zdm_source_discovery.sh" "${source_extra_env}")
if [[ "${source_status}" == "PASS" ]]; then
  source_txt=$(ls "${HOME}/zdm-step2-source-${ts}/zdm_source_discovery_"*.txt 2>/dev/null | head -1 || echo "")
  source_json=$(ls "${HOME}/zdm-step2-source-${ts}/zdm_source_discovery_"*.json 2>/dev/null | head -1 || echo "")
fi

# ---------------------------------------------------------------------------
# Target discovery
# ---------------------------------------------------------------------------
log "=== Running Target Discovery ==="
target_extra_env="TARGET_REMOTE_ORACLE_HOME=${TARGET_REMOTE_ORACLE_HOME} TARGET_ORACLE_SID=${TARGET_ORACLE_SID} TARGET_DATABASE_UNIQUE_NAME=${TARGET_DATABASE_UNIQUE_NAME} ORACLE_USER=${ORACLE_USER}"
target_status=$(run_remote_discovery "target" "${TARGET_HOST}" "${TARGET_ADMIN_USER}" "${TARGET_SSH_KEY}" "zdm_target_discovery.sh" "${target_extra_env}")
if [[ "${target_status}" == "PASS" ]]; then
  target_txt=$(ls "${HOME}/zdm-step2-target-${ts}/zdm_target_discovery_"*.txt 2>/dev/null | head -1 || echo "")
  target_json=$(ls "${HOME}/zdm-step2-target-${ts}/zdm_target_discovery_"*.json 2>/dev/null | head -1 || echo "")
fi

# ---------------------------------------------------------------------------
# Server discovery (local)
# ---------------------------------------------------------------------------
log "=== Running ZDM Server Discovery ==="
server_out_dir="${HOME}/zdm-step2-server-${ts}"
mkdir -p "${server_out_dir}"

if [[ ! -f "${script_dir}/zdm_server_discovery.sh" ]]; then
  log_fail "server: zdm_server_discovery.sh not found at ${script_dir}/"
  server_status="FAIL"
else
  if SOURCE_HOST="${SOURCE_HOST}" TARGET_HOST="${TARGET_HOST}" ZDM_USER="${ZDM_USER}" \
      ZDM_HOME="${ZDM_HOME}" OUTPUT_DIR="${server_out_dir}" \
      bash "${script_dir}/zdm_server_discovery.sh" 2>>"${log_file}" | tee -a "${log_file}"; then
    server_status="PASS"
    server_txt=$(ls "${server_out_dir}/zdm_server_discovery_"*.txt 2>/dev/null | head -1 || echo "")
    server_json=$(ls "${server_out_dir}/zdm_server_discovery_"*.json 2>/dev/null | head -1 || echo "")
    log_pass "server discovery completed. Outputs in ${server_out_dir}/"
  else
    log_fail "server: zdm_server_discovery.sh exited non-zero."
    server_status="FAIL"
  fi
fi

# ---------------------------------------------------------------------------
# Overall status
# ---------------------------------------------------------------------------
overall="PASS"
[[ "${source_status}" != "PASS" || "${target_status}" != "PASS" || "${server_status}" != "PASS" ]] && overall="PARTIAL"
[[ "${source_status}" == "FAIL" && "${target_status}" == "FAIL" && "${server_status}" == "FAIL" ]] && overall="FAIL"

# ---------------------------------------------------------------------------
# Markdown report
# ---------------------------------------------------------------------------
{
  echo "# ZDM Step 2 Discovery — Orchestration Report"
  echo ""
  echo "**Generated:** ${ts}  "
  echo "**Host:** ${run_host}  "
  echo "**User:** ${run_user}  "
  echo ""
  echo "## Effective Runtime Configuration"
  echo ""
  echo "| Variable | Value |"
  echo "|----------|-------|"
  echo "| SOURCE_HOST | \`${SOURCE_HOST}\` |"
  echo "| TARGET_HOST | \`${TARGET_HOST}\` |"
  echo "| SOURCE_ADMIN_USER | \`${SOURCE_ADMIN_USER}\` |"
  echo "| TARGET_ADMIN_USER | \`${TARGET_ADMIN_USER}\` |"
  echo "| SOURCE_SSH_KEY | \`${SOURCE_SSH_KEY:-<not set>}\` |"
  echo "| TARGET_SSH_KEY | \`${TARGET_SSH_KEY:-<not set>}\` |"
  echo "| SOURCE_ORACLE_SID | \`${SOURCE_ORACLE_SID}\` |"
  echo "| TARGET_ORACLE_SID | \`${TARGET_ORACLE_SID}\` |"
  echo "| ZDM_HOME | \`${ZDM_HOME}\` |"
  echo ""
  echo "## Per-Script Execution Status"
  echo ""
  echo "| Script | Status | Output Files |"
  echo "|--------|--------|-------------|"
  echo "| zdm_source_discovery.sh | **${source_status}** | ${source_txt:-N/A} |"
  echo "| zdm_target_discovery.sh | **${target_status}** | ${target_txt:-N/A} |"
  echo "| zdm_server_discovery.sh | **${server_status}** | ${server_txt:-N/A} |"
  echo ""
  echo "## Output Format References"
  echo ""
  echo "Each discovery script produces:"
  echo "- \`zdm_<type>_discovery_<hostname>_<ts>.txt\` — human-readable text report"
  echo "- \`zdm_<type>_discovery_<hostname>_<ts>.json\` — structured JSON summary with \`status\` and \`warnings\` array"
  echo ""
  echo "## Overall Step 2 Discovery Status"
  echo ""
  echo "**${overall}**"
  echo ""
  echo "---"
  echo ""
  echo "_Log file: ${log_file}_"
} > "${report_file}"

# ---------------------------------------------------------------------------
# Final console summary
# ---------------------------------------------------------------------------
log ""
log "=== Step 2 Discovery Summary ==="
log "Source discovery : ${source_status}${source_txt:+  → ${source_txt}}"
log "Target discovery : ${target_status}${target_txt:+  → ${target_txt}}"
log "Server discovery : ${server_status}${server_txt:+  → ${server_txt}}"
log ""
log "Orchestrator log    : ${log_file}"
log "Orchestrator report : ${report_file}"
log ""
log "Overall Step2 Discovery Status: ${overall}"

if [[ "${overall}" == "PASS" ]]; then
  log ""
  log "All discovery scripts completed successfully."
  log "Copy outputs to Artifacts/Phase10-Migration/Step2/Discovery/{source,target,server}/ for review."
  log "Then continue with: @Phase10-ZDM-Step3-Discovery-Questionnaire"
else
  log ""
  log_warn "One or more discovery scripts did not complete successfully."
  log_warn "Review [FAIL] entries in log file: ${log_file}"
fi

[[ "${overall}" == "FAIL" ]] && exit 1
exit 0
