#!/usr/bin/env bash

set -u

# ZDM Step 1 SSH connectivity precheck script
# Runtime target: jumpbox/ZDM server under zdmuser account

SOURCE_HOST="<SOURCE_HOST_IP_OR_FQDN>"
TARGET_HOST="<TARGET_HOST_IP_OR_FQDN>"
SOURCE_SSH_USER="<SOURCE_SSH_USER>"
TARGET_SSH_USER="<TARGET_SSH_USER>"
SOURCE_SSH_KEY="~/.ssh/<source_key>.pem"
TARGET_SSH_KEY="~/.ssh/<target_key>.pem"

SSH_COMMON_OPTS=(
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=10
  -o PasswordAuthentication=no
)

failure_count=0
status="PASS"

source_probe_status="FAIL"
target_probe_status="FAIL"

runtime_user_status="PASS"
runtime_user_reason=""

source_key_provided="no"
source_key_exists="n/a"
source_key_readable="n/a"
source_key_perm_ok="n/a"

source_key_mode="default_or_agent"
source_key_path_effective=""
source_probe_output=""

source_cmd_default=""
source_cmd_explicit=""

target_key_provided="no"
target_key_exists="n/a"
target_key_readable="n/a"
target_key_perm_ok="n/a"

target_key_mode="default_or_agent"
target_key_path_effective=""
target_probe_output=""

target_cmd_default=""
target_cmd_explicit=""

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
step_dir="$(cd "${script_dir}/.." && pwd)"
validation_dir="${step_dir}/Validation"
mkdir -p "${validation_dir}" || {
  echo "[FAIL] Unable to create validation directory: ${validation_dir}" >&2
  exit 1
}

ts="$(date +%Y%m%d-%H%M%S)"
iso_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
run_host="$(hostname 2>/dev/null || echo unknown)"
run_user="$(id -un 2>/dev/null || echo unknown)"

md_report="${validation_dir}/ssh-connectivity-report-${ts}.md"
json_report="${validation_dir}/ssh-connectivity-report-${ts}.json"
log_file="${validation_dir}/ssh-connectivity-run-${ts}.log"

exec > >(tee -a "${log_file}") 2>&1

append_md() {
  local line="$1"
  printf -- '%s\n' "${line}" >> "${md_report}"
}

normalize_key() {
  local raw="$1"
  if [[ -z "${raw}" ]]; then
    printf -- '%s\n' ""
    return 0
  fi
  if [[ "${raw}" == *"<"* && "${raw}" == *">"* ]]; then
    printf -- '%s\n' ""
    return 0
  fi
  if [[ "${raw}" == ~/* ]]; then
    printf -- '%s\n' "${HOME}/${raw#~/}"
    return 0
  fi
  printf -- '%s\n' "${raw}"
}

is_key_perm_ok() {
  local key_file="$1"
  local mode
  mode="$(stat -c '%a' "${key_file}" 2>/dev/null || true)"
  if [[ -z "${mode}" ]]; then
    return 1
  fi

  mode="${mode: -3}"
  case "${mode}" in
    400|600)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

escape_json() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/}"
  s="${s//$'\t'/\\t}"
  printf -- '%s' "${s}"
}

mark_fail() {
  local message="$1"
  echo "[FAIL] ${message}" >&2
  failure_count=$((failure_count + 1))
}

mark_pass() {
  local message="$1"
  echo "[PASS] ${message}" >&2
}

build_manual_commands() {
  source_cmd_default="ssh ${SSH_COMMON_OPTS[*]} ${SOURCE_SSH_USER}@${SOURCE_HOST} hostname"
  source_cmd_explicit="ssh -i ${source_key_path_effective:-<source_key_path>} ${SSH_COMMON_OPTS[*]} ${SOURCE_SSH_USER}@${SOURCE_HOST} hostname"

  target_cmd_default="ssh ${SSH_COMMON_OPTS[*]} ${TARGET_SSH_USER}@${TARGET_HOST} hostname"
  target_cmd_explicit="ssh -i ${target_key_path_effective:-<target_key_path>} ${SSH_COMMON_OPTS[*]} ${TARGET_SSH_USER}@${TARGET_HOST} hostname"
}

run_endpoint_check() {
  local endpoint="$1"
  local ssh_user="$2"
  local ssh_host="$3"
  local normalized_key="$4"

  local provided="no"
  local exists="n/a"
  local readable="n/a"
  local perm_ok="n/a"
  local key_mode="default_or_agent"
  local probe_status="FAIL"
  local probe_output=""

  local ssh_cmd=(ssh "${SSH_COMMON_OPTS[@]}")

  if [[ -n "${normalized_key}" ]]; then
    provided="yes"
    key_mode="explicit_key"

    if [[ -f "${normalized_key}" ]]; then
      exists="pass"
    else
      exists="fail"
      mark_fail "${endpoint} key file not found: ${normalized_key}"
    fi

    if [[ -r "${normalized_key}" ]]; then
      readable="pass"
    else
      readable="fail"
      mark_fail "${endpoint} key file not readable: ${normalized_key}"
    fi

    if [[ -f "${normalized_key}" ]] && is_key_perm_ok "${normalized_key}"; then
      perm_ok="pass"
    else
      perm_ok="fail"
      mark_fail "${endpoint} key permissions must be 600 or stricter (recommended 600 or 400): ${normalized_key}"
    fi

    if [[ "${exists}" == "pass" && "${readable}" == "pass" && "${perm_ok}" == "pass" ]]; then
      ssh_cmd+=( -i "${normalized_key}" )
    fi
  fi

  if probe_output="$("${ssh_cmd[@]}" "${ssh_user}@${ssh_host}" hostname 2>&1)"; then
    probe_status="PASS"
    mark_pass "${endpoint} connectivity probe succeeded (${ssh_user}@${ssh_host})"
  else
    probe_status="FAIL"
    mark_fail "${endpoint} connectivity probe failed (${ssh_user}@${ssh_host})"
  fi

  printf -- '%s\n' "${provided}" "${exists}" "${readable}" "${perm_ok}" "${key_mode}" "${probe_status}" "${probe_output}"
}

write_reports() {
  : > "${md_report}" || return 1

  append_md "# ZDM Step 1 SSH Connectivity Report" || return 1
  append_md "" || return 1
  append_md "Timestamp: ${iso_ts}" || return 1
  append_md "Runtime Host: ${run_host}" || return 1
  append_md "Effective User: ${run_user}" || return 1
  append_md "Runtime User Check: ${runtime_user_status}${runtime_user_reason:+ (${runtime_user_reason})}" || return 1
  append_md "" || return 1
  append_md "## Source Endpoint" || return 1
  append_md "Source Endpoint User: ${SOURCE_SSH_USER}" || return 1
  append_md "Source Endpoint Host: ${SOURCE_HOST}" || return 1
  append_md "Source Key Mode: ${source_key_mode}" || return 1
  append_md "Source Key Path: ${source_key_path_effective:-<unset>}" || return 1
  append_md "Source Key Provided: ${source_key_provided}" || return 1
  append_md "Source Key Exists: ${source_key_exists}" || return 1
  append_md "Source Key Readable: ${source_key_readable}" || return 1
  append_md "Source Key Permission Check: ${source_key_perm_ok}" || return 1
  append_md "Source Hostname Probe Status: ${source_probe_status}" || return 1
  append_md "Source Hostname Probe Output: ${source_probe_output}" || return 1
  append_md "" || return 1
  append_md "## Target Endpoint" || return 1
  append_md "Target Endpoint User: ${TARGET_SSH_USER}" || return 1
  append_md "Target Endpoint Host: ${TARGET_HOST}" || return 1
  append_md "Target Key Mode: ${target_key_mode}" || return 1
  append_md "Target Key Path: ${target_key_path_effective:-<unset>}" || return 1
  append_md "Target Key Provided: ${target_key_provided}" || return 1
  append_md "Target Key Exists: ${target_key_exists}" || return 1
  append_md "Target Key Readable: ${target_key_readable}" || return 1
  append_md "Target Key Permission Check: ${target_key_perm_ok}" || return 1
  append_md "Target Hostname Probe Status: ${target_probe_status}" || return 1
  append_md "Target Hostname Probe Output: ${target_probe_output}" || return 1
  append_md "" || return 1
  append_md "## Summary" || return 1
  append_md "Overall Status: ${status}" || return 1
  append_md "Failure Count: ${failure_count}" || return 1

  {
    printf -- '{\n'
    printf -- '  "timestamp": "%s",\n' "$(escape_json "${iso_ts}")"
    printf -- '  "runtime_host": "%s",\n' "$(escape_json "${run_host}")"
    printf -- '  "effective_user": "%s",\n' "$(escape_json "${run_user}")"
    printf -- '  "runtime_user_check": {"status": "%s", "reason": "%s"},\n' \
      "$(escape_json "${runtime_user_status}")" "$(escape_json "${runtime_user_reason}")"
    printf -- '  "source": {\n'
    printf -- '    "user": "%s",\n' "$(escape_json "${SOURCE_SSH_USER}")"
    printf -- '    "host": "%s",\n' "$(escape_json "${SOURCE_HOST}")"
    printf -- '    "key_mode": "%s",\n' "$(escape_json "${source_key_mode}")"
    printf -- '    "key_path": "%s",\n' "$(escape_json "${source_key_path_effective:-<unset>}")"
    printf -- '    "key_provided": "%s",\n' "$(escape_json "${source_key_provided}")"
    printf -- '    "key_exists": "%s",\n' "$(escape_json "${source_key_exists}")"
    printf -- '    "key_readable": "%s",\n' "$(escape_json "${source_key_readable}")"
    printf -- '    "key_permission_check": "%s",\n' "$(escape_json "${source_key_perm_ok}")"
    printf -- '    "hostname_probe_status": "%s",\n' "$(escape_json "${source_probe_status}")"
    printf -- '    "hostname_probe_output": "%s"\n' "$(escape_json "${source_probe_output}")"
    printf -- '  },\n'
    printf -- '  "target": {\n'
    printf -- '    "user": "%s",\n' "$(escape_json "${TARGET_SSH_USER}")"
    printf -- '    "host": "%s",\n' "$(escape_json "${TARGET_HOST}")"
    printf -- '    "key_mode": "%s",\n' "$(escape_json "${target_key_mode}")"
    printf -- '    "key_path": "%s",\n' "$(escape_json "${target_key_path_effective:-<unset>}")"
    printf -- '    "key_provided": "%s",\n' "$(escape_json "${target_key_provided}")"
    printf -- '    "key_exists": "%s",\n' "$(escape_json "${target_key_exists}")"
    printf -- '    "key_readable": "%s",\n' "$(escape_json "${target_key_readable}")"
    printf -- '    "key_permission_check": "%s",\n' "$(escape_json "${target_key_perm_ok}")"
    printf -- '    "hostname_probe_status": "%s",\n' "$(escape_json "${target_probe_status}")"
    printf -- '    "hostname_probe_output": "%s"\n' "$(escape_json "${target_probe_output}")"
    printf -- '  },\n'
    printf -- '  "summary": {"overall_status": "%s", "failure_count": %d}\n' \
      "$(escape_json "${status}")" "${failure_count}"
    printf -- '}\n'
  } > "${json_report}" || return 1

  return 0
}

verify_reports() {
  local verify_failed=0

  if [[ ! -s "${md_report}" ]]; then
    echo "[FAIL] Markdown report is missing or empty: ${md_report}"
    verify_failed=1
  fi

  if [[ ! -s "${json_report}" ]]; then
    echo "[FAIL] JSON report is missing or empty: ${json_report}"
    verify_failed=1
  fi

  local required_md_prefixes=(
    "Timestamp: "
    "Runtime Host: "
    "Effective User: "
    "Runtime User Check: "
    "Source Endpoint User: "
    "Source Endpoint Host: "
    "Source Key Mode: "
    "Source Hostname Probe Status: "
    "Target Endpoint User: "
    "Target Endpoint Host: "
    "Target Key Mode: "
    "Target Hostname Probe Status: "
    "Overall Status: "
    "Failure Count: "
  )

  local prefix
  for prefix in "${required_md_prefixes[@]}"; do
    if ! grep -Eq "^${prefix}.+" "${md_report}"; then
      echo "[FAIL] Markdown report section is missing populated value line: ${prefix}"
      verify_failed=1
    fi
  done

  local md_status md_failures json_status json_failures
  md_status="$(grep -E '^Overall Status: ' "${md_report}" | tail -n1 | sed 's/^Overall Status: //')"
  md_failures="$(grep -E '^Failure Count: ' "${md_report}" | tail -n1 | sed 's/^Failure Count: //')"

  json_status="$(grep -E '"overall_status"' "${json_report}" | head -n1 | sed -E 's/.*"overall_status"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
  json_failures="$(grep -E '"failure_count"' "${json_report}" | head -n1 | sed -E 's/.*"failure_count"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/')"

  if [[ -z "${md_status}" || -z "${md_failures}" || -z "${json_status}" || -z "${json_failures}" ]]; then
    echo "[FAIL] Could not extract summary fields for markdown/json parity validation."
    verify_failed=1
  elif [[ "${md_status}" != "${json_status}" || "${md_failures}" != "${json_failures}" ]]; then
    echo "[FAIL] Markdown/JSON summary mismatch. md(status=${md_status}, failures=${md_failures}) vs json(status=${json_status}, failures=${json_failures})"
    verify_failed=1
  fi

  if [[ ${verify_failed} -ne 0 ]]; then
    echo "[FAIL] Report verification checks failed."
    return 1
  fi

  echo "[PASS] Report verification checks passed."
  return 0
}

echo "=== ZDM Step 1 SSH Connectivity Validation ==="
echo "Runtime host: ${run_host}"
echo "Runtime user: ${run_user}"
echo ""

if [[ "${run_user}" != "zdmuser" ]]; then
  runtime_user_status="FAIL"
  runtime_user_reason="Script should be executed as zdmuser on jumpbox/ZDM server"
  mark_fail "Runtime user must be zdmuser (current: ${run_user})"
else
  runtime_user_status="PASS"
  runtime_user_reason=""
  mark_pass "Runtime user is zdmuser"
fi

source_key_path_effective="$(normalize_key "${SOURCE_SSH_KEY}")"
target_key_path_effective="$(normalize_key "${TARGET_SSH_KEY}")"

mapfile -t source_results < <(run_endpoint_check "SOURCE" "${SOURCE_SSH_USER}" "${SOURCE_HOST}" "${source_key_path_effective}")
source_key_provided="${source_results[0]}"
source_key_exists="${source_results[1]}"
source_key_readable="${source_results[2]}"
source_key_perm_ok="${source_results[3]}"
source_key_mode="${source_results[4]}"
source_probe_status="${source_results[5]}"
source_probe_output="${source_results[6]}"

mapfile -t target_results < <(run_endpoint_check "TARGET" "${TARGET_SSH_USER}" "${TARGET_HOST}" "${target_key_path_effective}")
target_key_provided="${target_results[0]}"
target_key_exists="${target_results[1]}"
target_key_readable="${target_results[2]}"
target_key_perm_ok="${target_results[3]}"
target_key_mode="${target_results[4]}"
target_probe_status="${target_results[5]}"
target_probe_output="${target_results[6]}"

if [[ ${failure_count} -gt 0 ]]; then
  status="FAIL"
fi

build_manual_commands

echo ""
echo "Manual SSH test commands (same options and hostname probe):"
echo "SOURCE default/agent: ${source_cmd_default}"
echo "SOURCE explicit key: ${source_cmd_explicit}"
echo "TARGET default/agent: ${target_cmd_default}"
echo "TARGET explicit key: ${target_cmd_explicit}"

echo ""
echo "Writing reports..."
if ! write_reports; then
  echo "[FAIL] Failed to generate report files. Check write permissions under ${validation_dir}."
  exit 1
fi

if ! verify_reports; then
  exit 1
fi

echo ""
echo "Final Summary: ${status} (failures=${failure_count})"
echo "Markdown report: ${md_report}"
echo "JSON report: ${json_report}"
echo "Execution log: ${log_file}"

if [[ "${status}" == "PASS" ]]; then
  exit 0
fi

exit 1
