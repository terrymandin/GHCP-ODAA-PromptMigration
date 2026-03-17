#!/usr/bin/env bash

set -u
set -o pipefail

# Rendered from zdm-env.md at generation time. This script is runtime-independent.
SOURCE_HOST="10.200.1.12"
TARGET_HOST="10.200.0.250"
SOURCE_SSH_USER="azureuser"
TARGET_SSH_USER="opc"
SOURCE_SSH_KEY_RAW="~/.ssh/<source_key>.pem"
TARGET_SSH_KEY_RAW="~/.ssh/<target_key>.pem"
REQUIRED_RUN_USER="zdmuser"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEP1_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VALIDATION_DIR="$STEP1_DIR/Validation"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_MD="$VALIDATION_DIR/ssh-connectivity-report-$TIMESTAMP.md"
REPORT_JSON="$VALIDATION_DIR/ssh-connectivity-report-$TIMESTAMP.json"

SSH_OPTS=(
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=10
  -o PasswordAuthentication=no
)

mkdir -p "$VALIDATION_DIR"

failures=()
source_status="SKIPPED"
target_status="SKIPPED"
source_message="Not executed"
target_message="Not executed"
source_hostname=""
target_hostname=""
source_key_mode="agent/default"
target_key_mode="agent/default"

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\r//g; :a;N;$!ba;s/\n/\\n/g'
}

is_placeholder() {
  [[ "$1" == *"<"*">"* ]]
}

expand_home() {
  local p="$1"
  if [[ "$p" == ~/* ]]; then
    printf '%s\n' "${HOME}/${p#~/}"
  else
    printf '%s\n' "$p"
  fi
}

normalize_optional_key() {
  local raw="$1"
  if [[ -z "$raw" ]] || is_placeholder "$raw"; then
    printf '%s\n' ""
    return
  fi
  expand_home "$raw"
}

is_key_perm_strict() {
  local perm="$1"
  [[ "$perm" =~ ^[0-6]00$ ]]
}

validate_key_if_set() {
  local label="$1"
  local key_path="$2"

  if [[ -z "$key_path" ]]; then
    return 0
  fi

  if [[ ! -e "$key_path" ]]; then
    failures+=("$label key file not found: $key_path")
    return 1
  fi

  if [[ ! -r "$key_path" ]]; then
    failures+=("$label key file is not readable: $key_path")
    return 1
  fi

  local perm
  perm="$(stat -c '%a' "$key_path" 2>/dev/null || true)"
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
  local key_path="$4"

  if [[ -z "$user" || -z "$host" ]]; then
    printf '%s\n' "FAIL|Missing required user or host"
    return 1
  fi

  local output rc
  if [[ -n "$key_path" ]]; then
    output="$(ssh -i "$key_path" "${SSH_OPTS[@]}" "${user}@${host}" hostname 2>&1)"
  else
    output="$(ssh "${SSH_OPTS[@]}" "${user}@${host}" hostname 2>&1)"
  fi
  rc=$?

  if [[ $rc -ne 0 ]]; then
    failures+=("$label SSH failed for ${user}@${host}: $output")
    printf '%s\n' "FAIL|$output"
    return 1
  fi

  printf '%s\n' "PASS|$output"
  return 0
}

SOURCE_SSH_KEY="$(normalize_optional_key "$SOURCE_SSH_KEY_RAW")"
TARGET_SSH_KEY="$(normalize_optional_key "$TARGET_SSH_KEY_RAW")"

if [[ -n "$SOURCE_SSH_KEY" ]]; then
  source_key_mode="$SOURCE_SSH_KEY"
else
  source_key_mode="agent/default"
fi

if [[ -n "$TARGET_SSH_KEY" ]]; then
  target_key_mode="$TARGET_SSH_KEY"
else
  target_key_mode="agent/default"
fi

current_user="$(whoami)"
if [[ "$current_user" != "$REQUIRED_RUN_USER" ]]; then
  failures+=("Script must run as '$REQUIRED_RUN_USER' (current user: '$current_user')")
fi

validate_key_if_set "SOURCE" "$SOURCE_SSH_KEY" || true
validate_key_if_set "TARGET" "$TARGET_SSH_KEY" || true

result="$(run_ssh_check "SOURCE" "$SOURCE_SSH_USER" "$SOURCE_HOST" "$SOURCE_SSH_KEY")"
source_status="${result%%|*}"
source_message="${result#*|}"
if [[ "$source_status" == "PASS" ]]; then
  source_hostname="$source_message"
  source_message="SSH ok"
fi

result="$(run_ssh_check "TARGET" "$TARGET_SSH_USER" "$TARGET_HOST" "$TARGET_SSH_KEY")"
target_status="${result%%|*}"
target_message="${result#*|}"
if [[ "$target_status" == "PASS" ]]; then
  target_hostname="$target_message"
  target_message="SSH ok"
fi

overall_status="PASS"
if [[ ${#failures[@]} -gt 0 || "$source_status" != "PASS" || "$target_status" != "PASS" ]]; then
  overall_status="FAIL"
fi

{
  echo "# SSH Connectivity Report"
  echo
  echo "- Timestamp: $TIMESTAMP"
  echo "- Overall status: $overall_status"
  echo "- Executed by user: $current_user"
  echo
  echo "## Endpoint Results"
  echo
  echo "| Endpoint | User | Host | Key Mode | Status | Remote Hostname | Notes |"
  echo "|---|---|---|---|---|---|---|"
  echo "| SOURCE | ${SOURCE_SSH_USER:-N/A} | ${SOURCE_HOST:-N/A} | ${source_key_mode:-N/A} | ${source_status:-N/A} | ${source_hostname:-N/A} | ${source_message:-N/A} |"
  echo "| TARGET | ${TARGET_SSH_USER:-N/A} | ${TARGET_HOST:-N/A} | ${target_key_mode:-N/A} | ${target_status:-N/A} | ${target_hostname:-N/A} | ${target_message:-N/A} |"

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
  echo "  \"overall_status\": \"$(json_escape "$overall_status")\"," 
  echo "  \"executed_by\": \"$(json_escape "$current_user")\"," 
  echo "  \"results\": {"
  echo "    \"source\": {"
  echo "      \"user\": \"$(json_escape "$SOURCE_SSH_USER")\"," 
  echo "      \"host\": \"$(json_escape "$SOURCE_HOST")\"," 
  echo "      \"key_mode\": \"$(json_escape "$source_key_mode")\"," 
  echo "      \"status\": \"$(json_escape "$source_status")\"," 
  echo "      \"remote_hostname\": \"$(json_escape "$source_hostname")\"," 
  echo "      \"message\": \"$(json_escape "$source_message")\""
  echo "    },"
  echo "    \"target\": {"
  echo "      \"user\": \"$(json_escape "$TARGET_SSH_USER")\"," 
  echo "      \"host\": \"$(json_escape "$TARGET_HOST")\"," 
  echo "      \"key_mode\": \"$(json_escape "$target_key_mode")\"," 
  echo "      \"status\": \"$(json_escape "$target_status")\"," 
  echo "      \"remote_hostname\": \"$(json_escape "$target_hostname")\"," 
  echo "      \"message\": \"$(json_escape "$target_message")\""
  echo "    }"
  echo "  },"
  echo "  \"failures\": ["
  if [[ ${#failures[@]} -gt 0 ]]; then
    for i in "${!failures[@]}"; do
      comma=","
      if [[ "$i" -eq "$(( ${#failures[@]} - 1 ))" ]]; then
        comma=""
      fi
      echo "    \"$(json_escape "${failures[$i]}")\"$comma"
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
