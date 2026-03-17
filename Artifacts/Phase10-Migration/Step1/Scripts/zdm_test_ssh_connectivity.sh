#!/usr/bin/env bash

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEP1_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
ENV_FILE="${ZDM_ENV_FILE:-$PROJECT_ROOT/zdm-env.md}"
VALIDATION_DIR="$STEP1_DIR/Validation"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_MD="$VALIDATION_DIR/ssh-connectivity-report-$TIMESTAMP.md"
REPORT_JSON="$VALIDATION_DIR/ssh-connectivity-report-$TIMESTAMP.json"

mkdir -p "$VALIDATION_DIR"

failures=()

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\r//g; :a;N;$!ba;s/\n/\\n/g'
}

get_env_value() {
  local key="$1"
  local line
  line="$(grep -E "^- ${key}:" "$ENV_FILE" | head -n 1 || true)"
  line="${line#- ${key}:}"
  echo "${line}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

expand_home() {
  local p="$1"
  if [[ "$p" == ~/* ]]; then
    printf '%s\n' "${HOME}/${p#~/}"
  else
    printf '%s\n' "$p"
  fi
}

is_placeholder() {
  [[ "$1" == *"<"*">"* ]]
}

is_key_perm_strict() {
  local perm="$1"
  [[ "$perm" =~ ^[0-7]00$ ]]
}

check_key_file() {
  local label="$1"
  local key_path_raw="$2"
  local key_path
  local perm

  key_path="$(expand_home "$key_path_raw")"

  if [[ -z "$key_path_raw" ]]; then
    failures+=("$label key path is empty")
    return 1
  fi

  if is_placeholder "$key_path_raw"; then
    failures+=("$label key path still contains a placeholder: $key_path_raw")
    return 1
  fi

  if [[ ! -e "$key_path" ]]; then
    failures+=("$label key file not found: $key_path")
    return 1
  fi

  if [[ ! -r "$key_path" ]]; then
    failures+=("$label key file is not readable: $key_path")
    return 1
  fi

  perm="$(stat -c '%a' "$key_path" 2>/dev/null || stat -f '%Lp' "$key_path" 2>/dev/null || true)"
  if [[ -z "$perm" ]]; then
    failures+=("$label key permissions could not be determined: $key_path")
    return 1
  fi

  if ! is_key_perm_strict "$perm"; then
    failures+=("$label key permissions are too open ($perm): $key_path")
    return 1
  fi

  return 0
}

run_ssh_check() {
  local label="$1"
  local user="$2"
  local host="$3"
  local key_path_raw="$4"
  local key_path
  local output
  local rc

  key_path="$(expand_home "$key_path_raw")"
  output="$(ssh -i "$key_path" \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout=10 \
    -o PasswordAuthentication=no \
    "${user}@${host}" hostname 2>&1)"
  rc=$?

  if [[ $rc -ne 0 ]]; then
    failures+=("$label SSH failed for ${user}@${host}: $output")
    printf '%s\n' "fail|$output"
    return 1
  fi

  printf '%s\n' "pass|$output"
  return 0
}

overall_status="PASS"
source_status="SKIPPED"
target_status="SKIPPED"
source_message="Not executed"
target_message="Not executed"
source_hostname=""
target_hostname=""

if [[ ! -f "$ENV_FILE" ]]; then
  failures+=("Configuration file not found: $ENV_FILE")
else
  SOURCE_HOST="$(get_env_value SOURCE_HOST)"
  TARGET_HOST="$(get_env_value TARGET_HOST)"
  SOURCE_SSH_USER="$(get_env_value SOURCE_SSH_USER)"
  TARGET_SSH_USER="$(get_env_value TARGET_SSH_USER)"
  SOURCE_SSH_KEY="$(get_env_value SOURCE_SSH_KEY)"
  TARGET_SSH_KEY="$(get_env_value TARGET_SSH_KEY)"

  for var_name in SOURCE_HOST TARGET_HOST SOURCE_SSH_USER TARGET_SSH_USER SOURCE_SSH_KEY TARGET_SSH_KEY; do
    value="${!var_name:-}"
    if [[ -z "$value" ]]; then
      failures+=("Missing required configuration value: $var_name")
    fi
  done

  check_key_file "SOURCE" "$SOURCE_SSH_KEY" || true
  check_key_file "TARGET" "$TARGET_SSH_KEY" || true

  if [[ ${#failures[@]} -eq 0 ]]; then
    result="$(run_ssh_check "SOURCE" "$SOURCE_SSH_USER" "$SOURCE_HOST" "$SOURCE_SSH_KEY")"
    source_status="${result%%|*}"
    source_message="${result#*|}"
    if [[ "$source_status" == "pass" ]]; then
      source_status="PASS"
      source_hostname="$source_message"
      source_message="SSH ok"
    else
      source_status="FAIL"
    fi

    result="$(run_ssh_check "TARGET" "$TARGET_SSH_USER" "$TARGET_HOST" "$TARGET_SSH_KEY")"
    target_status="${result%%|*}"
    target_message="${result#*|}"
    if [[ "$target_status" == "pass" ]]; then
      target_status="PASS"
      target_hostname="$target_message"
      target_message="SSH ok"
    else
      target_status="FAIL"
    fi
  fi
fi

if [[ ${#failures[@]} -gt 0 || "$source_status" == "FAIL" || "$target_status" == "FAIL" ]]; then
  overall_status="FAIL"
fi

{
  echo "# SSH Connectivity Report"
  echo
  echo "- Timestamp: $TIMESTAMP"
  echo "- Env file: $ENV_FILE"
  echo "- Overall status: $overall_status"
  echo
  echo "## Endpoint Results"
  echo
  echo "| Endpoint | User | Host | Status | Remote Hostname | Notes |"
  echo "|---|---|---|---|---|---|"
  echo "| SOURCE | ${SOURCE_SSH_USER:-N/A} | ${SOURCE_HOST:-N/A} | $source_status | ${source_hostname:-N/A} | ${source_message:-N/A} |"
  echo "| TARGET | ${TARGET_SSH_USER:-N/A} | ${TARGET_HOST:-N/A} | $target_status | ${target_hostname:-N/A} | ${target_message:-N/A} |"

  if [[ ${#failures[@]} -gt 0 ]]; then
    echo
    echo "## Failures"
    echo
    for failure in "${failures[@]}"; do
      echo "- $failure"
    done
  fi
} > "$REPORT_MD"

{
  echo "{"
  echo "  \"timestamp\": \"$(json_escape "$TIMESTAMP")\"," 
  echo "  \"env_file\": \"$(json_escape "$ENV_FILE")\"," 
  echo "  \"overall_status\": \"$(json_escape "$overall_status")\"," 
  echo "  \"results\": {"
  echo "    \"source\": {"
  echo "      \"user\": \"$(json_escape "${SOURCE_SSH_USER:-}")\"," 
  echo "      \"host\": \"$(json_escape "${SOURCE_HOST:-}")\"," 
  echo "      \"status\": \"$(json_escape "$source_status")\"," 
  echo "      \"remote_hostname\": \"$(json_escape "$source_hostname")\"," 
  echo "      \"message\": \"$(json_escape "$source_message")\""
  echo "    },"
  echo "    \"target\": {"
  echo "      \"user\": \"$(json_escape "${TARGET_SSH_USER:-}")\"," 
  echo "      \"host\": \"$(json_escape "${TARGET_HOST:-}")\"," 
  echo "      \"status\": \"$(json_escape "$target_status")\"," 
  echo "      \"remote_hostname\": \"$(json_escape "$target_hostname")\"," 
  echo "      \"message\": \"$(json_escape "$target_message")\""
  echo "    }"
  echo "  },"
  echo "  \"failures\": ["
  if [[ ${#failures[@]} -gt 0 ]]; then
    for i in "${!failures[@]}"; do
      comma=","
      if [[ "$i" -eq "$((${#failures[@]} - 1))" ]]; then
        comma=""
      fi
      echo "    \"$(json_escape "${failures[$i]}")\"${comma}"
    done
  fi
  echo "  ]"
  echo "}"
} > "$REPORT_JSON"

echo "Markdown report: $REPORT_MD"
echo "JSON report: $REPORT_JSON"

if [[ "$overall_status" == "FAIL" ]]; then
  exit 1
fi

exit 0