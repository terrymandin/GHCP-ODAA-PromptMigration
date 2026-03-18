#!/bin/bash

set -u

# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration

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

TARGET_SCOPE="all"
VERBOSE=0

SSH_OPTS="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -o PasswordAuthentication=no"
SCP_OPTS="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -o PasswordAuthentication=no"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
step_dir="$(cd "$script_dir/.." && pwd)"
discovery_dir="$step_dir/Discovery"
source_out_dir="$discovery_dir/source"
target_out_dir="$discovery_dir/target"
server_out_dir="$discovery_dir/server"
mkdir -p "$source_out_dir" "$target_out_dir" "$server_out_dir"

timestamp="$(date +%Y%m%d-%H%M%S)"
iso_timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
summary_md="$discovery_dir/discovery-summary-$timestamp.md"
summary_json="$discovery_dir/discovery-summary-$timestamp.json"
run_log="$discovery_dir/discovery-run-$timestamp.log"

exec > >(tee -a "$run_log") 2>&1

STATUS_SOURCE="SKIPPED"
STATUS_TARGET="SKIPPED"
STATUS_SERVER="SKIPPED"

LOG_SOURCE="$source_out_dir/source-orchestrator-$timestamp.log"
LOG_TARGET="$target_out_dir/target-orchestrator-$timestamp.log"
LOG_SERVER="$server_out_dir/server-orchestrator-$timestamp.log"

SOURCE_RAW_FILE=""
SOURCE_JSON_FILE=""
TARGET_RAW_FILE=""
TARGET_JSON_FILE=""
SERVER_RAW_FILE=""
SERVER_JSON_FILE=""

WARNINGS_NL=""
warning_count=0

add_warning() {
  local message="$1"
  warning_count=$((warning_count + 1))
  WARNINGS_NL+="$message"$'\n'
  echo "[WARN] $message"
}

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

is_placeholder() { [[ "$1" == *"<"*">"* ]]; }

normalize_optional_key() {
  local raw="${1:-}"
  [ -z "$raw" ] && echo "" && return 0
  is_placeholder "$raw" && echo "" && return 0
  if [[ "$raw" == ~/* ]]; then
    echo "${HOME}/${raw#~/}"
    return 0
  fi
  echo "$raw"
}

show_help() {
  cat <<'HELP'
Usage: zdm_orchestrate_discovery.sh [-h] [-c] [-t scope] [-v]

Options:
  -h          Show help and exit
  -c          Show effective configuration and exit
  -t scope    Target scope: all|source|target|server
  -v          Verbose mode
HELP
  exit 0
}

show_config() {
  cat <<CFG
Effective configuration:
  SOURCE_HOST=$SOURCE_HOST
  TARGET_HOST=$TARGET_HOST
  SOURCE_ADMIN_USER=$SOURCE_ADMIN_USER
  TARGET_ADMIN_USER=$TARGET_ADMIN_USER
  ORACLE_USER=$ORACLE_USER
  ZDM_USER=$ZDM_USER
  SOURCE_SSH_KEY=$SOURCE_SSH_KEY
  TARGET_SSH_KEY=$TARGET_SSH_KEY
  SOURCE_REMOTE_ORACLE_HOME=$SOURCE_REMOTE_ORACLE_HOME
  SOURCE_ORACLE_SID=$SOURCE_ORACLE_SID
  TARGET_REMOTE_ORACLE_HOME=$TARGET_REMOTE_ORACLE_HOME
  TARGET_ORACLE_SID=$TARGET_ORACLE_SID
  SOURCE_DATABASE_UNIQUE_NAME=$SOURCE_DATABASE_UNIQUE_NAME
  TARGET_DATABASE_UNIQUE_NAME=$TARGET_DATABASE_UNIQUE_NAME
  ZDM_HOME=$ZDM_HOME
  TARGET_SCOPE=$TARGET_SCOPE
CFG
  exit 0
}

while getopts ":hct:v" opt; do
  case "$opt" in
    h)
      show_help
      ;;
    c)
      show_config
      ;;
    t)
      TARGET_SCOPE="$OPTARG"
      ;;
    v)
      VERBOSE=1
      ;;
    :)
      echo "[ERROR] Option -$OPTARG requires an argument."
      show_help
      ;;
    \?)
      echo "[ERROR] Unknown option: -$OPTARG"
      show_help
      ;;
  esac
done

if [[ "$TARGET_SCOPE" != "all" && "$TARGET_SCOPE" != "source" && "$TARGET_SCOPE" != "target" && "$TARGET_SCOPE" != "server" ]]; then
  echo "[ERROR] Invalid -t scope: $TARGET_SCOPE"
  show_help
fi

SOURCE_SSH_KEY="$(normalize_optional_key "${SOURCE_SSH_KEY:-}")"
TARGET_SSH_KEY="$(normalize_optional_key "${TARGET_SSH_KEY:-}")"

echo "=== ZDM Step2 Discovery Orchestrator ==="
echo "Timestamp: $iso_timestamp"
echo "Current user: $(whoami)"
echo "Home directory: ${HOME:-<unset>}"
echo "Scope: $TARGET_SCOPE"
echo

echo "=== SSH Key Diagnostics ==="
echo "~/.ssh inventory (.pem/.key):"
find "${HOME:-.}/.ssh" -maxdepth 1 -type f \( -name '*.pem' -o -name '*.key' \) 2>/dev/null || echo "No .pem/.key files found"
if [ -n "$SOURCE_SSH_KEY" ]; then
  echo "SOURCE_SSH_KEY (normalized): $SOURCE_SSH_KEY"
  [ -f "$SOURCE_SSH_KEY" ] || add_warning "SOURCE_SSH_KEY is set but file does not exist: $SOURCE_SSH_KEY"
else
  echo "SOURCE_SSH_KEY (normalized): <unset> (default/agent mode)"
fi
if [ -n "$TARGET_SSH_KEY" ]; then
  echo "TARGET_SSH_KEY (normalized): $TARGET_SSH_KEY"
  [ -f "$TARGET_SSH_KEY" ] || add_warning "TARGET_SSH_KEY is set but file does not exist: $TARGET_SSH_KEY"
else
  echo "TARGET_SSH_KEY (normalized): <unset> (default/agent mode)"
fi
echo

run_remote_discovery() {
  local dtype="$1"
  local host="$2"
  local admin_user="$3"
  local key_path="$4"
  local script_path="$5"
  local out_dir="$6"
  local status_var="$7"
  local log_file="$8"

  local remote_dir="~/zdm-step2-${dtype}-${timestamp}"
  local copied_script_name
  copied_script_name="$(basename "$script_path")"

  echo "[INFO] Running $dtype discovery on $admin_user@$host"

  if [ ! -f "$script_path" ]; then
    echo "[ERROR] Script not found: $script_path"
    eval "$status_var=FAIL"
    return 1
  fi

  ssh $SSH_OPTS ${key_path:+-i "$key_path"} "${admin_user}@${host}" \
      "mkdir -p $remote_dir && bash -l -s" \
      < <(echo "cd '$remote_dir'" ; cat "$script_path") > "$log_file" 2>&1
  local ssh_rc=$?
  if [ $ssh_rc -ne 0 ]; then
    echo "[ERROR] Remote execution failed for $dtype on $host (rc=$ssh_rc). See $log_file"
    eval "$status_var=FAIL"
    return 1
  fi

  local remote_txt
  local remote_json
  remote_txt="$(ssh $SSH_OPTS ${key_path:+-i "$key_path"} "${admin_user}@${host}" "ls -1t $remote_dir/zdm_${dtype}_discovery_*.txt 2>/dev/null | head -n1")"
  remote_json="$(ssh $SSH_OPTS ${key_path:+-i "$key_path"} "${admin_user}@${host}" "ls -1t $remote_dir/zdm_${dtype}_discovery_*.json 2>/dev/null | head -n1")"

  if [ -z "$remote_txt" ] || [ -z "$remote_json" ]; then
    echo "[ERROR] Could not confirm remote output files for $dtype on $host"
    eval "$status_var=FAIL"
    return 1
  fi

  scp $SCP_OPTS ${key_path:+-i "$key_path"} "${admin_user}@${host}:$remote_txt" "$out_dir/"
  local scp_txt_rc=$?
  scp $SCP_OPTS ${key_path:+-i "$key_path"} "${admin_user}@${host}:$remote_json" "$out_dir/"
  local scp_json_rc=$?

  if [ $scp_txt_rc -ne 0 ] || [ $scp_json_rc -ne 0 ]; then
    echo "[ERROR] SCP retrieval failed for $dtype on $host"
    eval "$status_var=FAIL"
    return 1
  fi

  if [ "$dtype" = "source" ]; then
    SOURCE_RAW_FILE="$out_dir/$(basename "$remote_txt")"
    SOURCE_JSON_FILE="$out_dir/$(basename "$remote_json")"
  elif [ "$dtype" = "target" ]; then
    TARGET_RAW_FILE="$out_dir/$(basename "$remote_txt")"
    TARGET_JSON_FILE="$out_dir/$(basename "$remote_json")"
  fi

  eval "$status_var=PASS"
  return 0
}

run_server_discovery() {
  local script_path="$1"
  local out_dir="$2"
  local status_var="$3"
  local log_file="$4"

  if [ ! -f "$script_path" ]; then
    echo "[ERROR] Script not found: $script_path"
    eval "$status_var=FAIL"
    return 1
  fi

  pushd "$out_dir" >/dev/null || {
    echo "[ERROR] Cannot access output directory: $out_dir"
    eval "$status_var=FAIL"
    return 1
  }

  SOURCE_HOST="$SOURCE_HOST" TARGET_HOST="$TARGET_HOST" ZDM_USER="$ZDM_USER" bash "$script_path" > "$log_file" 2>&1
  local rc=$?

  SERVER_RAW_FILE="$(ls -1t "$out_dir"/zdm_server_discovery_*.txt 2>/dev/null | head -n1 || true)"
  SERVER_JSON_FILE="$(ls -1t "$out_dir"/zdm_server_discovery_*.json 2>/dev/null | head -n1 || true)"

  popd >/dev/null || true

  if [ $rc -ne 0 ] || [ -z "$SERVER_RAW_FILE" ] || [ -z "$SERVER_JSON_FILE" ]; then
    echo "[ERROR] Server discovery failed (rc=$rc). See $log_file"
    eval "$status_var=FAIL"
    return 1
  fi

  eval "$status_var=PASS"
  return 0
}

source_script="$script_dir/zdm_source_discovery.sh"
target_script="$script_dir/zdm_target_discovery.sh"
server_script="$script_dir/zdm_server_discovery.sh"

if [ "$TARGET_SCOPE" = "all" ] || [ "$TARGET_SCOPE" = "source" ]; then
  run_remote_discovery "source" "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$SOURCE_SSH_KEY" "$source_script" "$source_out_dir" STATUS_SOURCE "$LOG_SOURCE" || true
fi

if [ "$TARGET_SCOPE" = "all" ] || [ "$TARGET_SCOPE" = "target" ]; then
  run_remote_discovery "target" "$TARGET_HOST" "$TARGET_ADMIN_USER" "$TARGET_SSH_KEY" "$target_script" "$target_out_dir" STATUS_TARGET "$LOG_TARGET" || true
fi

if [ "$TARGET_SCOPE" = "all" ] || [ "$TARGET_SCOPE" = "server" ]; then
  run_server_discovery "$server_script" "$server_out_dir" STATUS_SERVER "$LOG_SERVER" || true
fi

overall_status="PASS"
if [ "$TARGET_SCOPE" = "all" ] || [ "$TARGET_SCOPE" = "source" ]; then
  [ "$STATUS_SOURCE" = "PASS" ] || overall_status="FAIL"
fi
if [ "$TARGET_SCOPE" = "all" ] || [ "$TARGET_SCOPE" = "target" ]; then
  [ "$STATUS_TARGET" = "PASS" ] || overall_status="FAIL"
fi
if [ "$TARGET_SCOPE" = "all" ] || [ "$TARGET_SCOPE" = "server" ]; then
  [ "$STATUS_SERVER" = "PASS" ] || overall_status="FAIL"
fi

if [ "$warning_count" -gt 0 ] && [ "$overall_status" = "PASS" ]; then
  overall_status="PARTIAL"
fi

{
  echo "# Step2 Discovery Orchestration Summary"
  echo
  echo "- Timestamp: $iso_timestamp"
  echo "- Scope: $TARGET_SCOPE"
  echo "- Effective SOURCE_HOST: $SOURCE_HOST"
  echo "- Effective TARGET_HOST: $TARGET_HOST"
  echo "- Effective SOURCE_ADMIN_USER: $SOURCE_ADMIN_USER"
  echo "- Effective TARGET_ADMIN_USER: $TARGET_ADMIN_USER"
  echo "- Effective ORACLE_USER: $ORACLE_USER"
  echo "- Effective ZDM_USER: $ZDM_USER"
  echo "- Effective SOURCE_REMOTE_ORACLE_HOME: $SOURCE_REMOTE_ORACLE_HOME"
  echo "- Effective SOURCE_ORACLE_SID: $SOURCE_ORACLE_SID"
  echo "- Effective TARGET_REMOTE_ORACLE_HOME: $TARGET_REMOTE_ORACLE_HOME"
  echo "- Effective TARGET_ORACLE_SID: $TARGET_ORACLE_SID"
  echo
  echo "## Per-Script Status"
  echo "- source: $STATUS_SOURCE (log: $LOG_SOURCE)"
  echo "- target: $STATUS_TARGET (log: $LOG_TARGET)"
  echo "- server: $STATUS_SERVER (log: $LOG_SERVER)"
  echo
  echo "## Output References"
  echo "- Source raw text: ${SOURCE_RAW_FILE:-<none>}"
  echo "- Source JSON: ${SOURCE_JSON_FILE:-<none>}"
  echo "- Target raw text: ${TARGET_RAW_FILE:-<none>}"
  echo "- Target JSON: ${TARGET_JSON_FILE:-<none>}"
  echo "- Server raw text: ${SERVER_RAW_FILE:-<none>}"
  echo "- Server JSON: ${SERVER_JSON_FILE:-<none>}"
  echo "- Summary markdown report: $summary_md"
  echo "- Summary JSON report: $summary_json"
  echo "- Raw runtime logs: $run_log, $LOG_SOURCE, $LOG_TARGET, $LOG_SERVER"
  echo
  echo "## Overall Status"
  echo "- $overall_status"
} > "$summary_md"

{
  echo "{"
  echo "  \"status\": \"$( [ "$overall_status" = "PASS" ] && echo "success" || echo "partial" )\"," 
  echo "  \"warnings\": ["
  first=1
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    if [ $first -eq 0 ]; then
      echo ","
    fi
    printf '    "%s"' "$(json_escape "$line")"
    first=0
  done <<< "$WARNINGS_NL"
  echo
  echo "  ],"
  echo "  \"timestamp\": \"$(json_escape "$iso_timestamp")\"," 
  echo "  \"scope\": \"$(json_escape "$TARGET_SCOPE")\"," 
  echo "  \"script_status\": {"
  echo "    \"source\": \"$STATUS_SOURCE\"," 
  echo "    \"target\": \"$STATUS_TARGET\"," 
  echo "    \"server\": \"$STATUS_SERVER\""
  echo "  },"
  echo "  \"logs\": {"
  echo "    \"orchestrator\": \"$(json_escape "$run_log")\"," 
  echo "    \"source\": \"$(json_escape "$LOG_SOURCE")\"," 
  echo "    \"target\": \"$(json_escape "$LOG_TARGET")\"," 
  echo "    \"server\": \"$(json_escape "$LOG_SERVER")\""
  echo "  },"
  echo "  \"outputs\": {"
  echo "    \"source_txt\": \"$(json_escape "$SOURCE_RAW_FILE")\"," 
  echo "    \"source_json\": \"$(json_escape "$SOURCE_JSON_FILE")\"," 
  echo "    \"target_txt\": \"$(json_escape "$TARGET_RAW_FILE")\"," 
  echo "    \"target_json\": \"$(json_escape "$TARGET_JSON_FILE")\"," 
  echo "    \"server_txt\": \"$(json_escape "$SERVER_RAW_FILE")\"," 
  echo "    \"server_json\": \"$(json_escape "$SERVER_JSON_FILE")\""
  echo "  }"
  echo "}"
} > "$summary_json"

echo "[INFO] Summary markdown: $summary_md"
echo "[INFO] Summary JSON: $summary_json"
echo "[INFO] Overall Step2 discovery status: $overall_status"

if [ "$overall_status" = "PASS" ]; then
  exit 0
fi

exit 1
