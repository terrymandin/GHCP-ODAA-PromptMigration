#!/usr/bin/env bash
set -u

# ------------------------------------------------------------
# ZDM Step1 SSH Connectivity Validation Script
# Intended runtime host/user: jumpbox or ZDM server as zdmuser
# ------------------------------------------------------------

# Generated configuration values (generation-time input only)
SOURCE_HOST="10.200.1.12"
TARGET_HOST="10.200.0.250"
SOURCE_SSH_USER="azureuser"
TARGET_SSH_USER="opc"
SOURCE_SSH_KEY="~/.ssh/<source_key>.pem"
TARGET_SSH_KEY="~/.ssh/<target_key>.pem"

SSH_CONNECT_TIMEOUT=10
PROBE_COMMAND="hostname"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VALIDATION_DIR="$STEP_DIR/Validation"

TIMESTAMP="$(date -u +"%Y%m%dT%H%M%SZ")"
REPORT_MD="$VALIDATION_DIR/ssh-connectivity-report-${TIMESTAMP}.md"
REPORT_JSON="$VALIDATION_DIR/ssh-connectivity-report-${TIMESTAMP}.json"

OVERALL_STATUS="PASS"
FAIL_COUNT=0

trim() {
  local v="${1:-}"
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  printf '%s' "$v"
}

normalize_value() {
  local v
  v="$(trim "${1:-}")"
  if [[ -z "$v" ]]; then
    printf ''
    return
  fi
  if [[ "$v" == *"<"*">"* ]]; then
    printf ''
    return
  fi
  printf '%s' "$v"
}

normalize_key() {
  local k
  k="$(normalize_value "${1:-}")"
  if [[ -z "$k" ]]; then
    printf ''
    return
  fi
  printf '%s' "${k/#\~/$HOME}"
}

log_pass() {
  printf '[PASS] %s\n' "$1"
}

log_fail() {
  printf '[FAIL] %s\n' "$1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  OVERALL_STATUS="FAIL"
}

json_escape() {
  printf '%s' "${1:-}" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e ':a;N;$!ba;s/\n/\\n/g'
}

assert_required() {
  local key="$1"
  local val="$2"
  if [[ -z "$val" ]]; then
    printf '[FAIL] Missing required value: %s\n' "$key"
    OVERALL_STATUS="FAIL"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    log_pass "Required value present: ${key}=${val}"
  fi
}

check_key_file() {
  local label="$1"
  local key_path="$2"
  local prefix="$3"

  printf -v "${prefix}_KEY_MODE" '%s' "default_or_agent"
  printf -v "${prefix}_KEY_EXISTS" '%s' "N/A"
  printf -v "${prefix}_KEY_READABLE" '%s' "N/A"
  printf -v "${prefix}_KEY_PERMISSION_OK" '%s' "N/A"

  if [[ -z "$key_path" ]]; then
    log_pass "${label}: key not provided; using default key/agent mode"
    return 0
  fi

  printf -v "${prefix}_KEY_MODE" '%s' "explicit_key"

  if [[ -f "$key_path" ]]; then
    printf -v "${prefix}_KEY_EXISTS" '%s' "PASS"
    log_pass "${label}: key file exists: $key_path"
  else
    printf -v "${prefix}_KEY_EXISTS" '%s' "FAIL"
    log_fail "${label}: key file does not exist: $key_path"
    return 1
  fi

  if [[ -r "$key_path" ]]; then
    printf -v "${prefix}_KEY_READABLE" '%s' "PASS"
    log_pass "${label}: key file is readable"
  else
    printf -v "${prefix}_KEY_READABLE" '%s' "FAIL"
    log_fail "${label}: key file is not readable"
    return 1
  fi

  local perm
  perm="$(stat -c '%a' "$key_path" 2>/dev/null || true)"
  if [[ -z "$perm" ]]; then
    printf -v "${prefix}_KEY_PERMISSION_OK" '%s' "FAIL"
    log_fail "${label}: unable to read key permissions with stat"
    return 1
  fi

  local perm_oct user_bits group_other_bits
  perm_oct=$((8#$perm))
  user_bits=$(((perm_oct >> 6) & 7))
  group_other_bits=$((perm_oct & 63))

  if [[ $group_other_bits -eq 0 && ( $user_bits -eq 6 || $user_bits -eq 4 ) ]]; then
    printf -v "${prefix}_KEY_PERMISSION_OK" '%s' "PASS"
    log_pass "${label}: key permissions are secure (${perm})"
  else
    printf -v "${prefix}_KEY_PERMISSION_OK" '%s' "FAIL"
    log_fail "${label}: key permissions are too open (${perm}); expected 600 or 400"
    return 1
  fi

  return 0
}

run_probe() {
  local label="$1"
  local user="$2"
  local host="$3"
  local key_path="$4"
  local prefix="$5"

  local -a ssh_opts
  ssh_opts=(
    -o BatchMode=yes
    -o StrictHostKeyChecking=accept-new
    -o ConnectTimeout="$SSH_CONNECT_TIMEOUT"
    -o PasswordAuthentication=no
  )

  local cmd_default cmd_with_key
  cmd_default="ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=${SSH_CONNECT_TIMEOUT} -o PasswordAuthentication=no ${user}@${host} ${PROBE_COMMAND}"
  cmd_with_key="ssh -i ${key_path:-<key_path>} -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=${SSH_CONNECT_TIMEOUT} -o PasswordAuthentication=no ${user}@${host} ${PROBE_COMMAND}"

  printf -v "${prefix}_MANUAL_DEFAULT_CMD" '%s' "$cmd_default"
  printf -v "${prefix}_MANUAL_KEY_CMD" '%s' "$cmd_with_key"

  local output rc=0
  if [[ -n "$key_path" ]]; then
    output="$(ssh -i "$key_path" "${ssh_opts[@]}" "${user}@${host}" "$PROBE_COMMAND" 2>&1)" || rc=$?
  else
    output="$(ssh "${ssh_opts[@]}" "${user}@${host}" "$PROBE_COMMAND" 2>&1)" || rc=$?
  fi

  printf -v "${prefix}_PROBE_EXIT_CODE" '%s' "$rc"
  printf -v "${prefix}_PROBE_OUTPUT" '%s' "$output"

  if [[ $rc -eq 0 ]]; then
    printf -v "${prefix}_PROBE_STATUS" '%s' "PASS"
    log_pass "${label}: SSH probe succeeded (${user}@${host} -> $(trim "$output"))"
  else
    printf -v "${prefix}_PROBE_STATUS" '%s' "FAIL"
    log_fail "${label}: SSH probe failed (${user}@${host}); rc=${rc}; output=$(trim "$output")"
  fi
}

print_manual_commands() {
  printf '\nManual single-line SSH test commands:\n'
  printf 'SOURCE default/agent mode: %s\n' "$SOURCE_MANUAL_DEFAULT_CMD"
  printf 'SOURCE explicit key mode : %s\n' "$SOURCE_MANUAL_KEY_CMD"
  printf 'TARGET default/agent mode: %s\n' "$TARGET_MANUAL_DEFAULT_CMD"
  printf 'TARGET explicit key mode : %s\n\n' "$TARGET_MANUAL_KEY_CMD"
}

write_markdown_report() {
  local runtime_host runtime_user
  runtime_host="$(hostname 2>/dev/null || echo unknown)"
  runtime_user="$(whoami 2>/dev/null || echo unknown)"

  {
    printf '# SSH Connectivity Report\n\n'
    printf '## Execution Metadata\n'
    printf '- Timestamp (UTC): %s\n' "$TIMESTAMP"
    printf '- Runtime host: %s\n' "$runtime_host"
    printf '- Effective user: %s\n' "$runtime_user"
    printf '\n'
    printf '## Endpoint Configuration\n'
    printf '- Source endpoint: `%s@%s`\n' "$SOURCE_SSH_USER" "$SOURCE_HOST"
    printf '- Source key mode: %s\n' "$SOURCE_KEY_MODE"
    printf '- Target endpoint: `%s@%s`\n' "$TARGET_SSH_USER" "$TARGET_HOST"
    printf '- Target key mode: %s\n' "$TARGET_KEY_MODE"
    printf '\n'
    printf '## Key Checks\n'
    printf '- Source key exists: %s\n' "$SOURCE_KEY_EXISTS"
    printf '- Source key readable: %s\n' "$SOURCE_KEY_READABLE"
    printf '- Source key permission check: %s\n' "$SOURCE_KEY_PERMISSION_OK"
    printf '- Target key exists: %s\n' "$TARGET_KEY_EXISTS"
    printf '- Target key readable: %s\n' "$TARGET_KEY_READABLE"
    printf '- Target key permission check: %s\n' "$TARGET_KEY_PERMISSION_OK"
    printf '\n'
    printf '## Connectivity Probe Results\n'
    printf '- Source probe status: %s\n' "$SOURCE_PROBE_STATUS"
    printf '- Source probe exit code: %s\n' "$SOURCE_PROBE_EXIT_CODE"
    printf '- Source probe output: `%s`\n' "$(trim "$SOURCE_PROBE_OUTPUT")"
    printf '- Target probe status: %s\n' "$TARGET_PROBE_STATUS"
    printf '- Target probe exit code: %s\n' "$TARGET_PROBE_EXIT_CODE"
    printf '- Target probe output: `%s`\n' "$(trim "$TARGET_PROBE_OUTPUT")"
    printf '\n'
    printf '## Manual Commands\n'
    printf '- Source default/agent mode: `%s`\n' "$SOURCE_MANUAL_DEFAULT_CMD"
    printf '- Source explicit key mode: `%s`\n' "$SOURCE_MANUAL_KEY_CMD"
    printf '- Target default/agent mode: `%s`\n' "$TARGET_MANUAL_DEFAULT_CMD"
    printf '- Target explicit key mode: `%s`\n' "$TARGET_MANUAL_KEY_CMD"
    printf '\n'
    printf '## Final Summary\n'
    printf '- Overall status: **%s**\n' "$OVERALL_STATUS"
    printf '- Failure count: %s\n' "$FAIL_COUNT"
    if [[ "$runtime_user" != "zdmuser" ]]; then
      printf '- Runtime user note: expected `zdmuser`, current user is `%s`.\n' "$runtime_user"
    fi
  } > "$REPORT_MD"
}

write_json_report() {
  local runtime_host runtime_user
  runtime_host="$(hostname 2>/dev/null || echo unknown)"
  runtime_user="$(whoami 2>/dev/null || echo unknown)"

  {
    printf '{\n'
    printf '  "timestamp_utc": "%s",\n' "$(json_escape "$TIMESTAMP")"
    printf '  "runtime_host": "%s",\n' "$(json_escape "$runtime_host")"
    printf '  "effective_user": "%s",\n' "$(json_escape "$runtime_user")"
    printf '  "endpoints": {\n'
    printf '    "source": {\n'
    printf '      "user": "%s",\n' "$(json_escape "$SOURCE_SSH_USER")"
    printf '      "host": "%s",\n' "$(json_escape "$SOURCE_HOST")"
    printf '      "key_mode": "%s",\n' "$(json_escape "$SOURCE_KEY_MODE")"
    printf '      "key_checks": {\n'
    printf '        "exists": "%s",\n' "$(json_escape "$SOURCE_KEY_EXISTS")"
    printf '        "readable": "%s",\n' "$(json_escape "$SOURCE_KEY_READABLE")"
    printf '        "permission_ok": "%s"\n' "$(json_escape "$SOURCE_KEY_PERMISSION_OK")"
    printf '      },\n'
    printf '      "probe": {\n'
    printf '        "status": "%s",\n' "$(json_escape "$SOURCE_PROBE_STATUS")"
    printf '        "exit_code": %s,\n' "$SOURCE_PROBE_EXIT_CODE"
    printf '        "output": "%s"\n' "$(json_escape "$(trim "$SOURCE_PROBE_OUTPUT")")"
    printf '      },\n'
    printf '      "manual_default_command": "%s",\n' "$(json_escape "$SOURCE_MANUAL_DEFAULT_CMD")"
    printf '      "manual_explicit_key_command": "%s"\n' "$(json_escape "$SOURCE_MANUAL_KEY_CMD")"
    printf '    },\n'
    printf '    "target": {\n'
    printf '      "user": "%s",\n' "$(json_escape "$TARGET_SSH_USER")"
    printf '      "host": "%s",\n' "$(json_escape "$TARGET_HOST")"
    printf '      "key_mode": "%s",\n' "$(json_escape "$TARGET_KEY_MODE")"
    printf '      "key_checks": {\n'
    printf '        "exists": "%s",\n' "$(json_escape "$TARGET_KEY_EXISTS")"
    printf '        "readable": "%s",\n' "$(json_escape "$TARGET_KEY_READABLE")"
    printf '        "permission_ok": "%s"\n' "$(json_escape "$TARGET_KEY_PERMISSION_OK")"
    printf '      },\n'
    printf '      "probe": {\n'
    printf '        "status": "%s",\n' "$(json_escape "$TARGET_PROBE_STATUS")"
    printf '        "exit_code": %s,\n' "$TARGET_PROBE_EXIT_CODE"
    printf '        "output": "%s"\n' "$(json_escape "$(trim "$TARGET_PROBE_OUTPUT")")"
    printf '      },\n'
    printf '      "manual_default_command": "%s",\n' "$(json_escape "$TARGET_MANUAL_DEFAULT_CMD")"
    printf '      "manual_explicit_key_command": "%s"\n' "$(json_escape "$TARGET_MANUAL_KEY_CMD")"
    printf '    }\n'
    printf '  },\n'
    printf '  "summary": {\n'
    printf '    "overall_status": "%s",\n' "$(json_escape "$OVERALL_STATUS")"
    printf '    "failure_count": %s\n' "$FAIL_COUNT"
    printf '  }\n'
    printf '}\n'
  } > "$REPORT_JSON"
}

main() {
  mkdir -p "$VALIDATION_DIR"

  SOURCE_HOST="$(normalize_value "$SOURCE_HOST")"
  TARGET_HOST="$(normalize_value "$TARGET_HOST")"
  SOURCE_SSH_USER="$(normalize_value "$SOURCE_SSH_USER")"
  TARGET_SSH_USER="$(normalize_value "$TARGET_SSH_USER")"
  SOURCE_SSH_KEY="$(normalize_key "$SOURCE_SSH_KEY")"
  TARGET_SSH_KEY="$(normalize_key "$TARGET_SSH_KEY")"

  printf 'Running ZDM Step1 SSH connectivity validation...\n'
  printf 'Validation output directory: %s\n\n' "$VALIDATION_DIR"

  assert_required "SOURCE_HOST" "$SOURCE_HOST"
  assert_required "TARGET_HOST" "$TARGET_HOST"
  assert_required "SOURCE_SSH_USER" "$SOURCE_SSH_USER"
  assert_required "TARGET_SSH_USER" "$TARGET_SSH_USER"

  check_key_file "SOURCE" "$SOURCE_SSH_KEY" "SOURCE"
  check_key_file "TARGET" "$TARGET_SSH_KEY" "TARGET"

  run_probe "SOURCE" "$SOURCE_SSH_USER" "$SOURCE_HOST" "$SOURCE_SSH_KEY" "SOURCE"
  run_probe "TARGET" "$TARGET_SSH_USER" "$TARGET_HOST" "$TARGET_SSH_KEY" "TARGET"

  print_manual_commands
  write_markdown_report
  write_json_report

  printf 'Markdown report: %s\n' "$REPORT_MD"
  printf 'JSON report: %s\n' "$REPORT_JSON"

  if [[ "$OVERALL_STATUS" == "PASS" ]]; then
    printf '\nOverall result: PASS\n'
    exit 0
  fi

  printf '\nOverall result: FAIL (failures=%s)\n' "$FAIL_COUNT"
  exit 1
}

main "$@"
