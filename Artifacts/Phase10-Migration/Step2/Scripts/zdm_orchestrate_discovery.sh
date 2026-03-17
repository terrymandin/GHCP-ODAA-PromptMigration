#!/bin/bash
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration

set -u
set -o pipefail

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
TARGET_ORACLE_SID="${TARGET_ORACLE_SID:-POKAKV1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEP2_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_OUTPUT_DIR="$STEP2_DIR/Discovery/source"
TARGET_OUTPUT_DIR="$STEP2_DIR/Discovery/target"
SERVER_OUTPUT_DIR="$STEP2_DIR/Discovery/server"

VERBOSE=0
CONNECTIVITY_ONLY=0

SSH_OPTS=(
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=20
)
SCP_OPTS=(
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=20
)

FAILED_TARGETS=()
SUCCESS_TARGETS=()

log_info() {
  echo "[INFO] $*"
}

log_warn() {
  echo "[WARN] $*"
}

log_error() {
  echo "[ERROR] $*" >&2
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

normalize_key() {
  local key_raw="$1"
  if [ -z "$key_raw" ] || is_placeholder "$key_raw"; then
    printf '%s\n' ""
  else
    expand_home "$key_raw"
  fi
}

show_help() {
  cat <<'EOF'
Usage: bash zdm_orchestrate_discovery.sh [options]

Options:
  -h    Show help and exit
  -c    Show effective configuration and exit
  -t    Connectivity test only
  -v    Verbose output
EOF
  exit 0
}

show_config() {
  cat <<EOF
SOURCE_HOST=$SOURCE_HOST
TARGET_HOST=$TARGET_HOST
SOURCE_ADMIN_USER=$SOURCE_ADMIN_USER
TARGET_ADMIN_USER=$TARGET_ADMIN_USER
ORACLE_USER=$ORACLE_USER
ZDM_USER=$ZDM_USER
SOURCE_SSH_KEY=${SOURCE_SSH_KEY:-<agent/default>}
TARGET_SSH_KEY=${TARGET_SSH_KEY:-<agent/default>}
SOURCE_REMOTE_ORACLE_HOME=$SOURCE_REMOTE_ORACLE_HOME
SOURCE_ORACLE_SID=$SOURCE_ORACLE_SID
TARGET_REMOTE_ORACLE_HOME=$TARGET_REMOTE_ORACLE_HOME
TARGET_ORACLE_SID=$TARGET_ORACLE_SID
EOF
  exit 0
}

while getopts ":hctv" opt; do
  case "$opt" in
    h) show_help ;;
    c) show_config ;;
    t) CONNECTIVITY_ONLY=1 ;;
    v) VERBOSE=1 ;;
    :) log_error "Option -$OPTARG requires an argument"; exit 1 ;;
    \?) log_error "Unknown option: -$OPTARG"; exit 1 ;;
  esac
done

SOURCE_SSH_KEY="$(normalize_key "$SOURCE_SSH_KEY")"
TARGET_SSH_KEY="$(normalize_key "$TARGET_SSH_KEY")"

mkdir -p "$SOURCE_OUTPUT_DIR" "$TARGET_OUTPUT_DIR" "$SERVER_OUTPUT_DIR"

startup_diagnostics() {
  log_info "Current user: $(whoami)"
  log_info "Home directory: $HOME"

  if [ "$(whoami)" != "$ZDM_USER" ]; then
    log_warn "This script is expected to run as $ZDM_USER"
  fi

  local key_files
  key_files="$(find "$HOME/.ssh" -maxdepth 1 -type f \( -name '*.pem' -o -name '*.key' \) 2>/dev/null || true)"
  if [ -z "$key_files" ]; then
    log_warn "No .pem/.key files found under $HOME/.ssh"
  else
    log_info "Detected key files in $HOME/.ssh:"
    printf '%s\n' "$key_files"
  fi

  for var_name in SOURCE_SSH_KEY TARGET_SSH_KEY; do
    local value
    value="${!var_name}"
    if [ -z "$value" ]; then
      log_info "$var_name: using SSH agent/default key"
    else
      if [ -f "$value" ]; then
        log_info "$var_name: $value (exists)"
      else
        log_warn "$var_name: $value (missing)"
      fi
    fi
  done
}

ssh_exec_script() {
  local host="$1"
  local admin_user="$2"
  local key_path="$3"
  local local_script_path="$4"
  local remote_dir="$5"
  local env_prefix="$6"

  local ssh_cmd=(ssh "${SSH_OPTS[@]}")
  if [ -n "$key_path" ]; then
    ssh_cmd+=( -i "$key_path" )
  fi

  "${ssh_cmd[@]}" "${admin_user}@${host}" \
    "mkdir -p '$remote_dir' && ${env_prefix} bash -l -s" \
    < <(echo "cd '$remote_dir'"; cat "$local_script_path")
}

scp_to_remote() {
  local key_path="$1"
  local local_file="$2"
  local remote_target="$3"

  local scp_cmd=(scp "${SCP_OPTS[@]}")
  if [ -n "$key_path" ]; then
    scp_cmd+=( -i "$key_path" )
  fi
  "${scp_cmd[@]}" "$local_file" "$remote_target"
}

scp_from_remote() {
  local key_path="$1"
  local remote_source="$2"
  local local_dest="$3"

  local scp_cmd=(scp "${SCP_OPTS[@]}")
  if [ -n "$key_path" ]; then
    scp_cmd+=( -i "$key_path" )
  fi
  "${scp_cmd[@]}" "$remote_source" "$local_dest"
}

record_result() {
  local target="$1"
  local rc="$2"
  if [ "$rc" -eq 0 ]; then
    SUCCESS_TARGETS+=("$target")
  else
    FAILED_TARGETS+=("$target")
  fi
}

run_remote_discovery() {
  local label="$1"
  local host="$2"
  local admin_user="$3"
  local key_path="$4"
  local script_name="$5"
  local local_output_dir="$6"
  local env_prefix="$7"

  if [ -z "$host" ] || [ -z "$admin_user" ]; then
    log_error "$label host/user is not configured"
    record_result "$label" 1
    return
  fi

  local remote_dir="/tmp/zdm_discovery_${label,,}_$(date +%s)"
  local local_script="$SCRIPT_DIR/$script_name"

  if ! ssh "${SSH_OPTS[@]}" ${key_path:+-i "$key_path"} "${admin_user}@${host}" "mkdir -p '$remote_dir'" 2>"$local_output_dir/${label,,}_mkdir.stderr"; then
    log_error "[$label] Failed to create remote directory $remote_dir"
    record_result "$label" 1
    return
  fi

  log_info "[$label] Copying script to $admin_user@$host:$remote_dir"
  if ! scp_to_remote "$key_path" "$local_script" "${admin_user}@${host}:${remote_dir}/" 2>"$local_output_dir/${label,,}_scp_upload.stderr"; then
    log_error "[$label] Failed to copy script"
    record_result "$label" 1
    return
  fi

  log_info "[$label] Executing remote script with login shell"
  ssh_exec_script "$host" "$admin_user" "$key_path" "$local_script" "$remote_dir" "$env_prefix" 2>"$local_output_dir/${label,,}_exec.stderr"
  local exec_rc=$?

  log_info "[$label] Listing remote output directory contents"
  ssh "${SSH_OPTS[@]}" ${key_path:+-i "$key_path"} "${admin_user}@${host}" "ls -la '$remote_dir'" >"$local_output_dir/${label,,}_remote_ls.txt" 2>"$local_output_dir/${label,,}_ls.stderr"

  log_info "[$label] Downloading discovery outputs"
  if ! scp_from_remote "$key_path" "${admin_user}@${host}:${remote_dir}/zdm_*_discovery_*.txt" "$local_output_dir/" 2>"$local_output_dir/${label,,}_scp_txt.stderr"; then
    log_warn "[$label] No txt report copied (or copy failed)"
  fi
  if ! scp_from_remote "$key_path" "${admin_user}@${host}:${remote_dir}/zdm_*_discovery_*.json" "$local_output_dir/" 2>"$local_output_dir/${label,,}_scp_json.stderr"; then
    log_warn "[$label] No json report copied (or copy failed)"
  fi

  record_result "$label" "$exec_rc"
}

connectivity_test_only() {
  local rc=0

  for pair in "SOURCE:$SOURCE_HOST:$SOURCE_ADMIN_USER:$SOURCE_SSH_KEY" "TARGET:$TARGET_HOST:$TARGET_ADMIN_USER:$TARGET_SSH_KEY"; do
    IFS=':' read -r label host user key_path <<< "$pair"
    log_info "Connectivity test for $label ($user@$host)"
    if ! ssh "${SSH_OPTS[@]}" ${key_path:+-i "$key_path"} "${user}@${host}" "hostname"; then
      log_error "$label connectivity test failed"
      rc=1
    fi
  done

  return $rc
}

startup_diagnostics

if [ "$CONNECTIVITY_ONLY" -eq 1 ]; then
  connectivity_test_only
  exit $?
fi

run_remote_discovery "SOURCE" "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$SOURCE_SSH_KEY" "zdm_source_discovery.sh" "$SOURCE_OUTPUT_DIR" "ORACLE_USER='$ORACLE_USER' SOURCE_REMOTE_ORACLE_HOME='$SOURCE_REMOTE_ORACLE_HOME' SOURCE_ORACLE_SID='$SOURCE_ORACLE_SID'"
run_remote_discovery "TARGET" "$TARGET_HOST" "$TARGET_ADMIN_USER" "$TARGET_SSH_KEY" "zdm_target_discovery.sh" "$TARGET_OUTPUT_DIR" "ORACLE_USER='$ORACLE_USER' TARGET_REMOTE_ORACLE_HOME='$TARGET_REMOTE_ORACLE_HOME' TARGET_ORACLE_SID='$TARGET_ORACLE_SID'"

log_info "[SERVER] Running local zdm_server_discovery.sh"
SOURCE_HOST="$SOURCE_HOST" TARGET_HOST="$TARGET_HOST" ZDM_USER="$ZDM_USER" bash "$SCRIPT_DIR/zdm_server_discovery.sh"
server_rc=$?
if ls -1 "$SCRIPT_DIR"/zdm_server_discovery_*.txt >/dev/null 2>&1; then
  cp "$SCRIPT_DIR"/zdm_server_discovery_*.txt "$SERVER_OUTPUT_DIR/" 2>/dev/null || true
fi
if ls -1 "$SCRIPT_DIR"/zdm_server_discovery_*.json >/dev/null 2>&1; then
  cp "$SCRIPT_DIR"/zdm_server_discovery_*.json "$SERVER_OUTPUT_DIR/" 2>/dev/null || true
fi
record_result "SERVER" "$server_rc"

log_info "Discovery orchestration complete"
log_info "Successful targets: ${SUCCESS_TARGETS[*]:-none}"
if [ ${#FAILED_TARGETS[@]} -gt 0 ]; then
  log_warn "Failed targets: ${FAILED_TARGETS[*]}"
  exit 1
fi

exit 0
