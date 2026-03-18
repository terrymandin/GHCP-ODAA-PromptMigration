#!/bin/bash

# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DISCOVERY_DIR="${STEP_DIR}/Discovery"
SOURCE_OUT_DIR="${DISCOVERY_DIR}/source"
TARGET_OUT_DIR="${DISCOVERY_DIR}/target"
SERVER_OUT_DIR="${DISCOVERY_DIR}/server"
LOG_DIR="${DISCOVERY_DIR}/logs"
mkdir -p "${SOURCE_OUT_DIR}" "${TARGET_OUT_DIR}" "${SERVER_OUT_DIR}" "${LOG_DIR}" || {
  echo "[ERROR] Unable to create required discovery output directories under ${DISCOVERY_DIR}" >&2
  exit 1
}

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_MD="${DISCOVERY_DIR}/discovery-orchestration-report-${TIMESTAMP}.md"
REPORT_JSON="${DISCOVERY_DIR}/discovery-orchestration-report-${TIMESTAMP}.json"

SOURCE_SCRIPT="${SCRIPT_DIR}/zdm_source_discovery.sh"
TARGET_SCRIPT="${SCRIPT_DIR}/zdm_target_discovery.sh"
SERVER_SCRIPT="${SCRIPT_DIR}/zdm_server_discovery.sh"

SSH_OPTS=(
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=15
  -o PasswordAuthentication=no
)
SCP_OPTS=(
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=15
)

SOURCE_HOST="${SOURCE_HOST:-10.200.1.12}"
TARGET_HOST="${TARGET_HOST:-10.200.0.250}"
SOURCE_ADMIN_USER="${SOURCE_ADMIN_USER:-azureuser}"
TARGET_ADMIN_USER="${TARGET_ADMIN_USER:-opc}"
ORACLE_USER="${ORACLE_USER:-oracle}"
ZDM_USER="${ZDM_USER:-zdmuser}"
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-~/.ssh/<source_key>.pem}"
TARGET_SSH_KEY="${TARGET_SSH_KEY:-~/.ssh/<target_key>.pem}"

SOURCE_REMOTE_ORACLE_HOME="${SOURCE_REMOTE_ORACLE_HOME:-/u01/app/oracle/product/19.0.0/dbhome_1}"
SOURCE_ORACLE_SID="${SOURCE_ORACLE_SID:-POCAKV}"
TARGET_REMOTE_ORACLE_HOME="${TARGET_REMOTE_ORACLE_HOME:-/u02/app/oracle/product/19.0.0.0/dbhome_1}"
TARGET_ORACLE_SID="${TARGET_ORACLE_SID:-POCAKV1}"
SOURCE_DATABASE_UNIQUE_NAME="${SOURCE_DATABASE_UNIQUE_NAME:-POCAKV}"
TARGET_DATABASE_UNIQUE_NAME="${TARGET_DATABASE_UNIQUE_NAME:-POCAKV_ODAA}"
ZDM_HOME="${ZDM_HOME:-/mnt/app/zdmhome}"

VERBOSE=0
TARGET_SCOPE="all"

SOURCE_STATUS="SKIPPED"
TARGET_STATUS="SKIPPED"
SERVER_STATUS="SKIPPED"
OVERALL_STATUS="PASS"

SOURCE_LOG=""
TARGET_LOG=""
SERVER_LOG=""

SOURCE_TXT=""
SOURCE_JSON=""
TARGET_TXT=""
TARGET_JSON=""
SERVER_TXT=""
SERVER_JSON=""

WARNINGS=()

is_placeholder() { [[ "$1" == *"<"*">"* ]]; }

normalize_key() {
  local raw="$1"
  if [[ -z "$raw" ]]; then
    printf '%s\n' ""
    return 0
  fi
  if is_placeholder "$raw"; then
    printf '%s\n' ""
    return 0
  fi
  if [[ "$raw" == ~/* ]]; then
    printf '%s\n' "${HOME}/${raw#~/}"
    return 0
  fi
  printf '%s\n' "$raw"
}

SOURCE_SSH_KEY="$(normalize_key "$SOURCE_SSH_KEY")"
TARGET_SSH_KEY="$(normalize_key "$TARGET_SSH_KEY")"

escape_json() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

add_warning() {
  WARNINGS+=("$1")
  OVERALL_STATUS="FAIL"
}

log_info() {
  local msg="$1"
  printf '[INFO] %s\n' "$msg"
}

log_error() {
  local msg="$1"
  printf '[ERROR] %s\n' "$msg" >&2
}

show_help() {
  cat <<'EOF'
Usage: zdm_orchestrate_discovery.sh [-h] [-c] [-t all|source|target|server] [-v]

Options:
  -h  Show help and exit
  -c  Show effective configuration and exit
  -t  Target scope to run (default: all)
  -v  Verbose output
EOF
  exit 0
}

show_config() {
  cat <<EOF
Effective runtime configuration:
  SOURCE_HOST=${SOURCE_HOST}
  TARGET_HOST=${TARGET_HOST}
  SOURCE_ADMIN_USER=${SOURCE_ADMIN_USER}
  TARGET_ADMIN_USER=${TARGET_ADMIN_USER}
  ORACLE_USER=${ORACLE_USER}
  ZDM_USER=${ZDM_USER}
  SOURCE_SSH_KEY=${SOURCE_SSH_KEY:-<unset>}
  TARGET_SSH_KEY=${TARGET_SSH_KEY:-<unset>}
  SOURCE_REMOTE_ORACLE_HOME=${SOURCE_REMOTE_ORACLE_HOME}
  SOURCE_ORACLE_SID=${SOURCE_ORACLE_SID}
  TARGET_REMOTE_ORACLE_HOME=${TARGET_REMOTE_ORACLE_HOME}
  TARGET_ORACLE_SID=${TARGET_ORACLE_SID}
  SOURCE_DATABASE_UNIQUE_NAME=${SOURCE_DATABASE_UNIQUE_NAME}
  TARGET_DATABASE_UNIQUE_NAME=${TARGET_DATABASE_UNIQUE_NAME}
  ZDM_HOME=${ZDM_HOME}
  TARGET_SCOPE=${TARGET_SCOPE}
EOF
  exit 0
}

while getopts ":hct:v" opt; do
  case "${opt}" in
    h)
      show_help
      ;;
    c)
      show_config
      ;;
    t)
      TARGET_SCOPE="${OPTARG}"
      ;;
    v)
      VERBOSE=1
      ;;
    :) 
      log_error "Option -${OPTARG} requires an argument"
      exit 2
      ;;
    \?)
      log_error "Unknown option: -${OPTARG}"
      show_help
      ;;
  esac
done

if [[ "${TARGET_SCOPE}" != "all" && "${TARGET_SCOPE}" != "source" && "${TARGET_SCOPE}" != "target" && "${TARGET_SCOPE}" != "server" ]]; then
  log_error "Invalid -t value: ${TARGET_SCOPE}. Expected all|source|target|server"
  exit 2
fi

startup_diagnostics() {
  log_info "Startup diagnostics"
  log_info "Current user: $(whoami 2>/dev/null || echo unknown)"
  log_info "Home directory: ${HOME}"
  log_info "PEM/KEY inventory under ${HOME}/.ssh"
  ls -la "${HOME}/.ssh"/*.pem "${HOME}/.ssh"/*.key 2>/dev/null || true

  log_info "Normalized key resolution"
  if [[ -n "${SOURCE_SSH_KEY}" ]]; then
    if [[ -f "${SOURCE_SSH_KEY}" ]]; then
      log_info "SOURCE_SSH_KEY exists: ${SOURCE_SSH_KEY}"
    else
      log_error "SOURCE_SSH_KEY does not exist: ${SOURCE_SSH_KEY}"
      add_warning "SOURCE_SSH_KEY file not found: ${SOURCE_SSH_KEY}"
    fi
  else
    log_info "SOURCE_SSH_KEY is unset; default/agent auth will be used"
  fi

  if [[ -n "${TARGET_SSH_KEY}" ]]; then
    if [[ -f "${TARGET_SSH_KEY}" ]]; then
      log_info "TARGET_SSH_KEY exists: ${TARGET_SSH_KEY}"
    else
      log_error "TARGET_SSH_KEY does not exist: ${TARGET_SSH_KEY}"
      add_warning "TARGET_SSH_KEY file not found: ${TARGET_SSH_KEY}"
    fi
  else
    log_info "TARGET_SSH_KEY is unset; default/agent auth will be used"
  fi
}

fail_if_missing_scripts() {
  local missing=0
  [[ -f "${SOURCE_SCRIPT}" ]] || { log_error "Missing source script: ${SOURCE_SCRIPT}"; missing=1; }
  [[ -f "${TARGET_SCRIPT}" ]] || { log_error "Missing target script: ${TARGET_SCRIPT}"; missing=1; }
  [[ -f "${SERVER_SCRIPT}" ]] || { log_error "Missing server script: ${SERVER_SCRIPT}"; missing=1; }
  if [[ ${missing} -ne 0 ]]; then
    exit 1
  fi
}

run_remote_discovery() {
  local dtype="$1"
  local host="$2"
  local admin_user="$3"
  local key_path="$4"
  local script_path="$5"
  local out_dir="$6"
  local log_file="$7"

  local remote_dir="$HOME/zdm-step2-${dtype}-${TIMESTAMP}"
  local remote_cmd=(ssh "${SSH_OPTS[@]}")
  local scp_cmd=(scp "${SCP_OPTS[@]}")

  if [[ -n "$key_path" ]]; then
    remote_cmd+=( -i "$key_path" )
    scp_cmd+=( -i "$key_path" )
  fi

  log_info "Running ${dtype} discovery on ${admin_user}@${host}"

  if ! "${remote_cmd[@]}" "${admin_user}@${host}" "mkdir -p $remote_dir && bash -l -s" \
      < <(
        printf 'cd %q\n' "$remote_dir"
        printf 'export ORACLE_USER=%q\n' "$ORACLE_USER"
        if [[ "$dtype" == "source" ]]; then
          printf 'export SOURCE_HOST=%q\n' "$SOURCE_HOST"
          printf 'export SOURCE_ADMIN_USER=%q\n' "$SOURCE_ADMIN_USER"
          printf 'export SOURCE_SSH_KEY=%q\n' "$SOURCE_SSH_KEY"
          printf 'export SOURCE_REMOTE_ORACLE_HOME=%q\n' "$SOURCE_REMOTE_ORACLE_HOME"
          printf 'export SOURCE_ORACLE_SID=%q\n' "$SOURCE_ORACLE_SID"
          printf 'export SOURCE_DATABASE_UNIQUE_NAME=%q\n' "$SOURCE_DATABASE_UNIQUE_NAME"
        fi
        if [[ "$dtype" == "target" ]]; then
          printf 'export TARGET_HOST=%q\n' "$TARGET_HOST"
          printf 'export TARGET_ADMIN_USER=%q\n' "$TARGET_ADMIN_USER"
          printf 'export TARGET_SSH_KEY=%q\n' "$TARGET_SSH_KEY"
          printf 'export TARGET_REMOTE_ORACLE_HOME=%q\n' "$TARGET_REMOTE_ORACLE_HOME"
          printf 'export TARGET_ORACLE_SID=%q\n' "$TARGET_ORACLE_SID"
          printf 'export TARGET_DATABASE_UNIQUE_NAME=%q\n' "$TARGET_DATABASE_UNIQUE_NAME"
        fi
        cat "$script_path"
      ) >"$log_file" 2>&1; then
    log_error "Remote execution failed for ${dtype}. See ${log_file}"
    add_warning "${dtype} discovery failed during remote execution"
    return 1
  fi

  if ! "${remote_cmd[@]}" "${admin_user}@${host}" "ls -1 ${remote_dir}/zdm_${dtype}_discovery_*_${TIMESTAMP}.txt ${remote_dir}/zdm_${dtype}_discovery_*_${TIMESTAMP}.json" >>"$log_file" 2>&1; then
    log_error "Remote output file check failed for ${dtype}. See ${log_file}"
    add_warning "${dtype} discovery output files were not found on remote host"
    return 1
  fi

  if ! "${scp_cmd[@]}" "${admin_user}@${host}:${remote_dir}/zdm_${dtype}_discovery_*_${TIMESTAMP}.txt" "$out_dir/" >>"$log_file" 2>&1; then
    log_error "Failed to SCP txt output for ${dtype}. See ${log_file}"
    add_warning "${dtype} txt output retrieval failed"
    return 1
  fi

  if ! "${scp_cmd[@]}" "${admin_user}@${host}:${remote_dir}/zdm_${dtype}_discovery_*_${TIMESTAMP}.json" "$out_dir/" >>"$log_file" 2>&1; then
    log_error "Failed to SCP json output for ${dtype}. See ${log_file}"
    add_warning "${dtype} json output retrieval failed"
    return 1
  fi

  return 0
}

find_latest() {
  local pattern="$1"
  local latest
  latest="$(ls -1t $pattern 2>/dev/null | head -n 1 || true)"
  printf '%s\n' "$latest"
}

run_server_discovery() {
  local log_file="$1"
  (
    cd "$SERVER_OUT_DIR" || exit 1
    SOURCE_HOST="$SOURCE_HOST" TARGET_HOST="$TARGET_HOST" ZDM_USER="$ZDM_USER" ZDM_HOME="$ZDM_HOME" ORACLE_USER="$ORACLE_USER" bash "$SERVER_SCRIPT"
  ) >"$log_file" 2>&1
}

write_reports() {
  {
    echo "# ZDM Step2 Discovery Orchestration Report"
    echo ""
    echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Runtime User: $(id -un 2>/dev/null || echo unknown)"
    echo "Runtime Host: $(hostname 2>/dev/null || echo unknown)"
    echo ""
    echo "## Effective Runtime Configuration"
    echo "SOURCE_HOST=${SOURCE_HOST}"
    echo "TARGET_HOST=${TARGET_HOST}"
    echo "SOURCE_ADMIN_USER=${SOURCE_ADMIN_USER}"
    echo "TARGET_ADMIN_USER=${TARGET_ADMIN_USER}"
    echo "ORACLE_USER=${ORACLE_USER}"
    echo "ZDM_USER=${ZDM_USER}"
    echo "SOURCE_SSH_KEY=${SOURCE_SSH_KEY:-<unset>}"
    echo "TARGET_SSH_KEY=${TARGET_SSH_KEY:-<unset>}"
    echo ""
    echo "## Script Execution Status"
    echo "source: ${SOURCE_STATUS}"
    echo "source_log: ${SOURCE_LOG}"
    echo "target: ${TARGET_STATUS}"
    echo "target_log: ${TARGET_LOG}"
    echo "server: ${SERVER_STATUS}"
    echo "server_log: ${SERVER_LOG}"
    echo ""
    echo "## Output References"
    echo "source_txt: ${SOURCE_TXT:-<missing>}"
    echo "source_json: ${SOURCE_JSON:-<missing>}"
    echo "target_txt: ${TARGET_TXT:-<missing>}"
    echo "target_json: ${TARGET_JSON:-<missing>}"
    echo "server_txt: ${SERVER_TXT:-<missing>}"
    echo "server_json: ${SERVER_JSON:-<missing>}"
    echo ""
    echo "## Overall"
    echo "overall_status: ${OVERALL_STATUS}"
    echo "warnings_count: ${#WARNINGS[@]}"
    if [[ ${#WARNINGS[@]} -gt 0 ]]; then
      echo ""
      echo "### Warnings"
      i=0
      while [[ $i -lt ${#WARNINGS[@]} ]]; do
        echo "- ${WARNINGS[$i]}"
        i=$((i + 1))
      done
    fi
  } > "$REPORT_MD"

  {
    printf '{\n'
    printf '  "timestamp": "%s",\n' "$(escape_json "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
    printf '  "status": "%s",\n' "$( [[ "$OVERALL_STATUS" == "PASS" ]] && echo success || echo partial )"
    printf '  "effective_config": {\n'
    printf '    "source_host": "%s",\n' "$(escape_json "$SOURCE_HOST")"
    printf '    "target_host": "%s",\n' "$(escape_json "$TARGET_HOST")"
    printf '    "source_admin_user": "%s",\n' "$(escape_json "$SOURCE_ADMIN_USER")"
    printf '    "target_admin_user": "%s",\n' "$(escape_json "$TARGET_ADMIN_USER")"
    printf '    "oracle_user": "%s",\n' "$(escape_json "$ORACLE_USER")"
    printf '    "zdm_user": "%s"\n' "$(escape_json "$ZDM_USER")"
    printf '  },\n'
    printf '  "scripts": {\n'
    printf '    "source": {"status": "%s", "log": "%s"},\n' "$(escape_json "$SOURCE_STATUS")" "$(escape_json "$SOURCE_LOG")"
    printf '    "target": {"status": "%s", "log": "%s"},\n' "$(escape_json "$TARGET_STATUS")" "$(escape_json "$TARGET_LOG")"
    printf '    "server": {"status": "%s", "log": "%s"}\n' "$(escape_json "$SERVER_STATUS")" "$(escape_json "$SERVER_LOG")"
    printf '  },\n'
    printf '  "outputs": {\n'
    printf '    "source_txt": "%s",\n' "$(escape_json "${SOURCE_TXT:-}")"
    printf '    "source_json": "%s",\n' "$(escape_json "${SOURCE_JSON:-}")"
    printf '    "target_txt": "%s",\n' "$(escape_json "${TARGET_TXT:-}")"
    printf '    "target_json": "%s",\n' "$(escape_json "${TARGET_JSON:-}")"
    printf '    "server_txt": "%s",\n' "$(escape_json "${SERVER_TXT:-}")"
    printf '    "server_json": "%s"\n' "$(escape_json "${SERVER_JSON:-}")"
    printf '  },\n'
    printf '  "warnings": ['
    i=0
    while [[ $i -lt ${#WARNINGS[@]} ]]; do
      if [[ $i -gt 0 ]]; then
        printf ', '
      fi
      printf '"%s"' "$(escape_json "${WARNINGS[$i]}")"
      i=$((i + 1))
    done
    printf ']\n'
    printf '}\n'
  } > "$REPORT_JSON"
}

startup_diagnostics
fail_if_missing_scripts

if [[ "${TARGET_SCOPE}" == "all" || "${TARGET_SCOPE}" == "source" ]]; then
  SOURCE_LOG="${LOG_DIR}/source-discovery-${TIMESTAMP}.log"
  SOURCE_STATUS="FAIL"
  if run_remote_discovery "source" "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$SOURCE_SSH_KEY" "$SOURCE_SCRIPT" "$SOURCE_OUT_DIR" "$SOURCE_LOG"; then
    SOURCE_STATUS="PASS"
    SOURCE_TXT="$(find_latest "${SOURCE_OUT_DIR}/zdm_source_discovery_*_${TIMESTAMP}.txt")"
    SOURCE_JSON="$(find_latest "${SOURCE_OUT_DIR}/zdm_source_discovery_*_${TIMESTAMP}.json")"
  fi
fi

if [[ "${TARGET_SCOPE}" == "all" || "${TARGET_SCOPE}" == "target" ]]; then
  TARGET_LOG="${LOG_DIR}/target-discovery-${TIMESTAMP}.log"
  TARGET_STATUS="FAIL"
  if run_remote_discovery "target" "$TARGET_HOST" "$TARGET_ADMIN_USER" "$TARGET_SSH_KEY" "$TARGET_SCRIPT" "$TARGET_OUT_DIR" "$TARGET_LOG"; then
    TARGET_STATUS="PASS"
    TARGET_TXT="$(find_latest "${TARGET_OUT_DIR}/zdm_target_discovery_*_${TIMESTAMP}.txt")"
    TARGET_JSON="$(find_latest "${TARGET_OUT_DIR}/zdm_target_discovery_*_${TIMESTAMP}.json")"
  fi
fi

if [[ "${TARGET_SCOPE}" == "all" || "${TARGET_SCOPE}" == "server" ]]; then
  SERVER_LOG="${LOG_DIR}/server-discovery-${TIMESTAMP}.log"
  SERVER_STATUS="FAIL"
  if run_server_discovery "$SERVER_LOG"; then
    SERVER_STATUS="PASS"
    SERVER_TXT="$(find_latest "${SERVER_OUT_DIR}/zdm_server_discovery_*_${TIMESTAMP}.txt")"
    SERVER_JSON="$(find_latest "${SERVER_OUT_DIR}/zdm_server_discovery_*_${TIMESTAMP}.json")"
  else
    add_warning "server discovery execution failed"
  fi
fi

if [[ "${SOURCE_STATUS}" == "FAIL" || "${TARGET_STATUS}" == "FAIL" || "${SERVER_STATUS}" == "FAIL" ]]; then
  OVERALL_STATUS="FAIL"
fi

write_reports

log_info "Step2 discovery orchestration completed"
log_info "Overall status: ${OVERALL_STATUS}"
log_info "Markdown report: ${REPORT_MD}"
log_info "JSON report: ${REPORT_JSON}"

if [[ "$OVERALL_STATUS" == "PASS" ]]; then
  exit 0
fi

exit 1
