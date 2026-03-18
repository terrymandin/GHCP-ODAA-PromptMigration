#!/usr/bin/env bash

set -uo pipefail

# Generated from zdm-env.md at prompt time. Do not edit values unless your
# environment changes. This script does not read zdm-env.md at runtime.
SOURCE_HOST="10.200.1.12"
TARGET_HOST="10.200.0.250"
SOURCE_SSH_USER="azureuser"
TARGET_SSH_USER="opc"
SOURCE_SSH_KEY="~/.ssh/<source_key>.pem"
TARGET_SSH_KEY="~/.ssh/<target_key>.pem"

SSH_COMMON_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o PasswordAuthentication=no)

# Manual single-line tests (same options and hostname probe as script):
# Default key/agent mode:
#   ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o PasswordAuthentication=no azureuser@10.200.1.12 hostname
#   ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o PasswordAuthentication=no opc@10.200.0.250 hostname
# Explicit key mode:
#   ssh -i ~/.ssh/<source_key>.pem -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o PasswordAuthentication=no azureuser@10.200.1.12 hostname
#   ssh -i ~/.ssh/<target_key>.pem -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o PasswordAuthentication=no opc@10.200.0.250 hostname

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEP1_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VALIDATION_DIR="${STEP1_DIR}/Validation"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
REPORT_MD="${VALIDATION_DIR}/ssh-connectivity-report-${TIMESTAMP}.md"
REPORT_JSON="${VALIDATION_DIR}/ssh-connectivity-report-${TIMESTAMP}.json"
RUNTIME_HOST="$(hostname 2>/dev/null || echo unknown)"
RUNTIME_USER="$(id -un 2>/dev/null || echo unknown)"

FAILURES=0
SOURCE_PROBE_STATUS="fail"
TARGET_PROBE_STATUS="fail"
SOURCE_PROBE_OUTPUT=""
TARGET_PROBE_OUTPUT=""
SOURCE_KEY_MODE="default_or_agent"
TARGET_KEY_MODE="default_or_agent"
SOURCE_KEY_STATUS="not_applicable"
TARGET_KEY_STATUS="not_applicable"
SOURCE_KEY_PATH_EFFECTIVE=""
TARGET_KEY_PATH_EFFECTIVE=""
SOURCE_KEY_DETAIL="key not provided; using default/agent mode"
TARGET_KEY_DETAIL="key not provided; using default/agent mode"

is_placeholder_or_empty() {
  local value="${1:-}"
  [[ -z "${value}" || "${value}" == *"<"* || "${value}" == *">"* ]]
}

expand_path() {
  local p="${1:-}"
  if [[ "${p}" == ~* ]]; then
    printf "%s" "${HOME}${p:1}"
  else
    printf "%s" "${p}"
  fi
}

json_escape() {
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf "%s" "${s}"
}

print_check() {
  local label="$1"
  local status="$2"
  local detail="$3"
  printf "[%s] %s - %s\n" "${status}" "${label}" "${detail}"
}

validate_key_if_set() {
  local endpoint="$1"
  local key_raw="$2"
  local key_mode_var="$3"
  local key_status_var="$4"
  local key_path_var="$5"
  local key_detail_var="$6"

  if is_placeholder_or_empty "${key_raw}"; then
    printf -v "${key_mode_var}" "%s" "default_or_agent"
    printf -v "${key_status_var}" "%s" "not_applicable"
    printf -v "${key_path_var}" "%s" ""
    printf -v "${key_detail_var}" "%s" "key not provided; using default/agent mode"
    print_check "${endpoint} key check" "PASS" "no explicit key required"
    return 0
  fi

  local key_expanded
  key_expanded="$(expand_path "${key_raw}")"
  printf -v "${key_mode_var}" "%s" "explicit_key"
  printf -v "${key_path_var}" "%s" "${key_expanded}"

  if [[ ! -e "${key_expanded}" ]]; then
    printf -v "${key_status_var}" "%s" "missing"
    printf -v "${key_detail_var}" "%s" "key file not found: ${key_expanded}"
    print_check "${endpoint} key check" "FAIL" "key file missing (${key_expanded})"
    FAILURES=$((FAILURES + 1))
    return 1
  fi

  if [[ ! -r "${key_expanded}" ]]; then
    printf -v "${key_status_var}" "%s" "unreadable"
    printf -v "${key_detail_var}" "%s" "key file is not readable: ${key_expanded}"
    print_check "${endpoint} key check" "FAIL" "key file unreadable (${key_expanded})"
    FAILURES=$((FAILURES + 1))
    return 1
  fi

  local perm_oct
  perm_oct="$(stat -c '%a' "${key_expanded}" 2>/dev/null || echo unknown)"
  if [[ "${perm_oct}" == "unknown" ]]; then
    printf -v "${key_status_var}" "%s" "perm_unknown"
    printf -v "${key_detail_var}" "%s" "unable to read key permissions: ${key_expanded}"
    print_check "${endpoint} key check" "FAIL" "could not determine key permissions"
    FAILURES=$((FAILURES + 1))
    return 1
  fi

  local perm_dec=$((8#${perm_oct}))
  if (( (perm_dec & 63) != 0 )); then
    printf -v "${key_status_var}" "%s" "perm_too_open"
    printf -v "${key_detail_var}" "%s" "permissions too open (${perm_oct}); expected 600 or stricter"
    print_check "${endpoint} key check" "FAIL" "permissions ${perm_oct} are too open"
    FAILURES=$((FAILURES + 1))
    return 1
  fi

  printf -v "${key_status_var}" "%s" "ok"
  printf -v "${key_detail_var}" "%s" "key exists/readable with permissions ${perm_oct}"
  print_check "${endpoint} key check" "PASS" "${key_expanded} (perm ${perm_oct})"
  return 0
}

run_ssh_probe() {
  local endpoint="$1"
  local user="$2"
  local host="$3"
  local key_mode="$4"
  local key_path="$5"
  local output_var="$6"
  local status_var="$7"

  local -a cmd=(ssh)
  if [[ "${key_mode}" == "explicit_key" && -n "${key_path}" ]]; then
    cmd+=( -i "${key_path}" )
  fi
  cmd+=( "${SSH_COMMON_OPTS[@]}" )

  local probe_output
  probe_output="$("${cmd[@]}" "${user}@${host}" hostname 2>&1)"
  local rc=$?

  printf -v "${output_var}" "%s" "${probe_output}"
  if [[ ${rc} -eq 0 ]]; then
    printf -v "${status_var}" "%s" "pass"
    print_check "${endpoint} connectivity" "PASS" "hostname: ${probe_output}"
  else
    printf -v "${status_var}" "%s" "fail"
    print_check "${endpoint} connectivity" "FAIL" "ssh probe failed (rc=${rc})"
    FAILURES=$((FAILURES + 1))
  fi
}

printf "Starting SSH connectivity validation...\n"
printf "Runtime host: %s | Runtime user: %s | Timestamp (UTC): %s\n" "${RUNTIME_HOST}" "${RUNTIME_USER}" "${TIMESTAMP}"

mkdir -p "${VALIDATION_DIR}"

validate_key_if_set "Source" "${SOURCE_SSH_KEY}" SOURCE_KEY_MODE SOURCE_KEY_STATUS SOURCE_KEY_PATH_EFFECTIVE SOURCE_KEY_DETAIL
validate_key_if_set "Target" "${TARGET_SSH_KEY}" TARGET_KEY_MODE TARGET_KEY_STATUS TARGET_KEY_PATH_EFFECTIVE TARGET_KEY_DETAIL

run_ssh_probe "Source" "${SOURCE_SSH_USER}" "${SOURCE_HOST}" "${SOURCE_KEY_MODE}" "${SOURCE_KEY_PATH_EFFECTIVE}" SOURCE_PROBE_OUTPUT SOURCE_PROBE_STATUS
run_ssh_probe "Target" "${TARGET_SSH_USER}" "${TARGET_HOST}" "${TARGET_KEY_MODE}" "${TARGET_KEY_PATH_EFFECTIVE}" TARGET_PROBE_OUTPUT TARGET_PROBE_STATUS

OVERALL_STATUS="PASS"
if (( FAILURES > 0 )); then
  OVERALL_STATUS="FAIL"
fi

cat > "${REPORT_MD}" <<EOF
# SSH Connectivity Validation Report

- Timestamp (UTC): ${TIMESTAMP}
- Runtime Host: ${RUNTIME_HOST}
- Runtime User: ${RUNTIME_USER}
- Script Path: ${SCRIPT_DIR}

## Effective SSH Model

### Source Endpoint
- User: ${SOURCE_SSH_USER}
- Host: ${SOURCE_HOST}
- Mode: ${SOURCE_KEY_MODE}
- Key Path: ${SOURCE_KEY_PATH_EFFECTIVE:-N/A}
- Key Check: ${SOURCE_KEY_STATUS}
- Key Detail: ${SOURCE_KEY_DETAIL}

### Target Endpoint
- User: ${TARGET_SSH_USER}
- Host: ${TARGET_HOST}
- Mode: ${TARGET_KEY_MODE}
- Key Path: ${TARGET_KEY_PATH_EFFECTIVE:-N/A}
- Key Check: ${TARGET_KEY_STATUS}
- Key Detail: ${TARGET_KEY_DETAIL}

## Connectivity Probes

- Source Probe Status: ${SOURCE_PROBE_STATUS}
- Source Probe Output: ${SOURCE_PROBE_OUTPUT}
- Target Probe Status: ${TARGET_PROBE_STATUS}
- Target Probe Output: ${TARGET_PROBE_OUTPUT}

## Manual Single-Line SSH Tests

Default key/agent mode:
- ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o PasswordAuthentication=no ${SOURCE_SSH_USER}@${SOURCE_HOST} hostname
- ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o PasswordAuthentication=no ${TARGET_SSH_USER}@${TARGET_HOST} hostname

Explicit key mode:
- ssh -i ${SOURCE_SSH_KEY} -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o PasswordAuthentication=no ${SOURCE_SSH_USER}@${SOURCE_HOST} hostname
- ssh -i ${TARGET_SSH_KEY} -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o PasswordAuthentication=no ${TARGET_SSH_USER}@${TARGET_HOST} hostname

## Final Summary

- Failures: ${FAILURES}
- Overall Status: ${OVERALL_STATUS}
EOF

cat > "${REPORT_JSON}" <<EOF
{
  "timestamp_utc": "$(json_escape "${TIMESTAMP}")",
  "runtime_host": "$(json_escape "${RUNTIME_HOST}")",
  "runtime_user": "$(json_escape "${RUNTIME_USER}")",
  "source": {
    "user": "$(json_escape "${SOURCE_SSH_USER}")",
    "host": "$(json_escape "${SOURCE_HOST}")",
    "mode": "$(json_escape "${SOURCE_KEY_MODE}")",
    "key_path": "$(json_escape "${SOURCE_KEY_PATH_EFFECTIVE}")",
    "key_check": "$(json_escape "${SOURCE_KEY_STATUS}")",
    "key_detail": "$(json_escape "${SOURCE_KEY_DETAIL}")",
    "probe_status": "$(json_escape "${SOURCE_PROBE_STATUS}")",
    "probe_output": "$(json_escape "${SOURCE_PROBE_OUTPUT}")"
  },
  "target": {
    "user": "$(json_escape "${TARGET_SSH_USER}")",
    "host": "$(json_escape "${TARGET_HOST}")",
    "mode": "$(json_escape "${TARGET_KEY_MODE}")",
    "key_path": "$(json_escape "${TARGET_KEY_PATH_EFFECTIVE}")",
    "key_check": "$(json_escape "${TARGET_KEY_STATUS}")",
    "key_detail": "$(json_escape "${TARGET_KEY_DETAIL}")",
    "probe_status": "$(json_escape "${TARGET_PROBE_STATUS}")",
    "probe_output": "$(json_escape "${TARGET_PROBE_OUTPUT}")"
  },
  "failures": ${FAILURES},
  "overall_status": "$(json_escape "${OVERALL_STATUS}")"
}
EOF

printf "\nValidation reports generated:\n"
printf "- %s\n" "${REPORT_MD}"
printf "- %s\n" "${REPORT_JSON}"

if (( FAILURES > 0 )); then
  printf "\n[FAIL] SSH connectivity validation completed with %d failure(s).\n" "${FAILURES}"
  exit 1
fi

printf "\n[PASS] SSH connectivity validation completed successfully.\n"
exit 0
