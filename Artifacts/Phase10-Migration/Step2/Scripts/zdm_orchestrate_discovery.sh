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
SOURCE_DATABASE_UNIQUE_NAME="${SOURCE_DATABASE_UNIQUE_NAME:-POCAKV}"
TARGET_DATABASE_UNIQUE_NAME="${TARGET_DATABASE_UNIQUE_NAME:-POCAKV_ODAA}"

VERBOSE=0
CONNECTIVITY_ONLY=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEP2_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DISCOVERY_DIR="$STEP2_DIR/Discovery"
SOURCE_OUT_DIR="$DISCOVERY_DIR/source"
TARGET_OUT_DIR="$DISCOVERY_DIR/target"
SERVER_OUT_DIR="$DISCOVERY_DIR/server"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

SSH_OPTS=(
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=15
)

SCP_OPTS=(
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=15
)

SOURCE_OK=0
TARGET_OK=0
SERVER_OK=0

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
  local raw="$1"
  if [ -z "$raw" ] || is_placeholder "$raw"; then
    printf '%s\n' ""
    return
  fi
  expand_home "$raw"
}

log_info() {
  printf '[INFO] %s\n' "$1"
}

log_warn() {
  printf '[WARN] %s\n' "$1"
}

log_error() {
  printf '[ERROR] %s\n' "$1" >&2
}

show_help() {
  cat <<'EOF'
Usage: bash zdm_orchestrate_discovery.sh [options]

Options:
  -h    Show help and exit
  -c    Show effective configuration and exit
  -t    Connectivity test only (no discovery execution)
  -v    Verbose output
EOF
  exit 0
}

show_config() {
  cat <<EOF
Effective Configuration:
  SOURCE_HOST=$SOURCE_HOST
  TARGET_HOST=$TARGET_HOST
  SOURCE_ADMIN_USER=$SOURCE_ADMIN_USER
  TARGET_ADMIN_USER=$TARGET_ADMIN_USER
  ORACLE_USER=$ORACLE_USER
  ZDM_USER=$ZDM_USER
  SOURCE_SSH_KEY=${SOURCE_SSH_KEY_NORM:-agent/default}
  TARGET_SSH_KEY=${TARGET_SSH_KEY_NORM:-agent/default}
  SOURCE_REMOTE_ORACLE_HOME=$SOURCE_REMOTE_ORACLE_HOME
  SOURCE_ORACLE_SID=$SOURCE_ORACLE_SID
  TARGET_REMOTE_ORACLE_HOME=$TARGET_REMOTE_ORACLE_HOME
  TARGET_ORACLE_SID=$TARGET_ORACLE_SID
  SOURCE_DATABASE_UNIQUE_NAME=$SOURCE_DATABASE_UNIQUE_NAME
  TARGET_DATABASE_UNIQUE_NAME=$TARGET_DATABASE_UNIQUE_NAME
EOF
  exit 0
}

run_ssh_probe() {
  local label="$1"
  local user="$2"
  local host="$3"
  local key_path="$4"

  local cmd=(ssh "${SSH_OPTS[@]}")
  if [ -n "$key_path" ]; then
    cmd+=( -i "$key_path" )
  fi
  cmd+=("${user}@${host}" "hostname")

  local output
  output="$("${cmd[@]}" 2>&1)"
  local rc=$?

  if [ $rc -ne 0 ]; then
    log_error "$label SSH probe failed: $output"
    return 1
  fi

  log_info "$label SSH probe succeeded (remote host: $output)"
  return 0
}

remote_run_discovery() {
  local label="$1"
  local host="$2"
  local admin_user="$3"
  local key_path="$4"
  local local_script="$5"
  local out_dir="$6"

  local remote_dir="/tmp/zdm_step2_${label,,}_${TIMESTAMP}"
  local remote_script="$remote_dir/$(basename "$local_script")"

  log_info "$label: preparing remote directory $remote_dir"

  local ssh_cmd=(ssh "${SSH_OPTS[@]}")
  local scp_cmd=(scp "${SCP_OPTS[@]}")
  if [ -n "$key_path" ]; then
    ssh_cmd+=( -i "$key_path" )
    scp_cmd+=( -i "$key_path" )
  fi

  local mk_output
  mk_output="$("${ssh_cmd[@]}" "${admin_user}@${host}" "mkdir -p '$remote_dir'" 2>&1)"
  if [ $? -ne 0 ]; then
    log_error "$label: failed to create remote directory: $mk_output"
    return 1
  fi

  local cp_output
  cp_output="$("${scp_cmd[@]}" "$local_script" "${admin_user}@${host}:$remote_script" 2>&1)"
  if [ $? -ne 0 ]; then
    log_error "$label: failed to copy script: $cp_output"
    return 1
  fi

  log_info "$label: executing script via login shell"
  local exec_output
  exec_output="$("${ssh_cmd[@]}" "${admin_user}@${host}" "bash -l -s" < <(
    echo "cd '$remote_dir'"
    echo "chmod +x '$remote_script'"
    echo "ORACLE_USER='$ORACLE_USER' SOURCE_REMOTE_ORACLE_HOME='$SOURCE_REMOTE_ORACLE_HOME' SOURCE_ORACLE_SID='$SOURCE_ORACLE_SID' TARGET_REMOTE_ORACLE_HOME='$TARGET_REMOTE_ORACLE_HOME' TARGET_ORACLE_SID='$TARGET_ORACLE_SID' SOURCE_DATABASE_UNIQUE_NAME='$SOURCE_DATABASE_UNIQUE_NAME' TARGET_DATABASE_UNIQUE_NAME='$TARGET_DATABASE_UNIQUE_NAME' bash '$remote_script'"
  ) 2>&1)"
  local exec_rc=$?
  printf '%s\n' "$exec_output"

  if [ $exec_rc -ne 0 ]; then
    log_warn "$label: remote script returned non-zero exit code ($exec_rc)"
  fi

  log_info "$label: listing remote temp files"
  local list_output
  list_output="$("${ssh_cmd[@]}" "${admin_user}@${host}" "ls -la '$remote_dir'" 2>&1)"
  if [ $? -ne 0 ]; then
    log_warn "$label: unable to list remote temp directory: $list_output"
  else
    printf '%s\n' "$list_output"
  fi

  mkdir -p "$out_dir"

  log_info "$label: copying discovery output files"
  local fetch_output
  fetch_output="$("${scp_cmd[@]}" "${admin_user}@${host}:$remote_dir/zdm_*_discovery_*.txt" "$out_dir/" 2>&1)"
  if [ $? -ne 0 ]; then
    log_warn "$label: failed to copy text output: $fetch_output"
  fi

  fetch_output="$("${scp_cmd[@]}" "${admin_user}@${host}:$remote_dir/zdm_*_discovery_*.json" "$out_dir/" 2>&1)"
  if [ $? -ne 0 ]; then
    log_warn "$label: failed to copy JSON output: $fetch_output"
  fi

  if [ $exec_rc -eq 0 ]; then
    return 0
  fi

  return 1
}

run_server_local() {
  local server_script="$SCRIPT_DIR/zdm_server_discovery.sh"
  mkdir -p "$SERVER_OUT_DIR"

  if [ ! -x "$server_script" ]; then
    chmod +x "$server_script" 2>/dev/null || true
  fi

  log_info "SERVER: running local ZDM discovery"
  local output
  output="$(cd "$SERVER_OUT_DIR" && SOURCE_HOST="$SOURCE_HOST" TARGET_HOST="$TARGET_HOST" ZDM_USER="$ZDM_USER" bash "$server_script" 2>&1)"
  local rc=$?
  printf '%s\n' "$output"

  if [ $rc -ne 0 ]; then
    log_warn "SERVER: local discovery returned non-zero exit code ($rc)"
    return 1
  fi

  return 0
}

startup_diagnostics() {
  log_info "Current user: $(whoami)"
  log_info "Home directory: $HOME"
  if [ "$(whoami)" != "$ZDM_USER" ]; then
    log_warn "Script should normally run as $ZDM_USER"
  fi

  local ssh_list
  ssh_list="$(ls -1 "$HOME/.ssh"/*.{pem,key} 2>/dev/null || true)"
  if [ -z "$ssh_list" ]; then
    log_warn "No .pem or .key files found in $HOME/.ssh"
  else
    log_info "Discovered SSH key files in $HOME/.ssh:"
    printf '%s\n' "$ssh_list"
  fi

  if [ -z "$SOURCE_SSH_KEY_NORM" ]; then
    log_info "SOURCE_SSH_KEY: using SSH agent/default key"
  else
    if [ -f "$SOURCE_SSH_KEY_NORM" ]; then
      log_info "SOURCE_SSH_KEY resolved and found: $SOURCE_SSH_KEY_NORM"
    else
      log_warn "SOURCE_SSH_KEY resolved but missing: $SOURCE_SSH_KEY_NORM"
    fi
  fi

  if [ -z "$TARGET_SSH_KEY_NORM" ]; then
    log_info "TARGET_SSH_KEY: using SSH agent/default key"
  else
    if [ -f "$TARGET_SSH_KEY_NORM" ]; then
      log_info "TARGET_SSH_KEY resolved and found: $TARGET_SSH_KEY_NORM"
    else
      log_warn "TARGET_SSH_KEY resolved but missing: $TARGET_SSH_KEY_NORM"
    fi
  fi
}

while getopts ":hctv" opt; do
  case "$opt" in
    h)
      show_help
      ;;
    c)
      CONNECTIVITY_ONLY=0
      ;;
    t)
      CONNECTIVITY_ONLY=1
      ;;
    v)
      VERBOSE=1
      ;;
    :) 
      log_error "Option -$OPTARG requires an argument"
      exit 1
      ;;
    \?)
      log_error "Invalid option: -$OPTARG"
      exit 1
      ;;
  esac
done

SOURCE_SSH_KEY_NORM="$(normalize_key "$SOURCE_SSH_KEY")"
TARGET_SSH_KEY_NORM="$(normalize_key "$TARGET_SSH_KEY")"

if printf '%s' "$*" | grep -q -- ' -c'; then
  show_config
fi

mkdir -p "$SOURCE_OUT_DIR" "$TARGET_OUT_DIR" "$SERVER_OUT_DIR"

startup_diagnostics

if [ -z "$SOURCE_HOST" ] || [ -z "$TARGET_HOST" ]; then
  log_error "SOURCE_HOST and TARGET_HOST must be set"
  exit 1
fi

log_info "Testing source and target SSH connectivity"
run_ssh_probe "SOURCE" "$SOURCE_ADMIN_USER" "$SOURCE_HOST" "$SOURCE_SSH_KEY_NORM" || true
run_ssh_probe "TARGET" "$TARGET_ADMIN_USER" "$TARGET_HOST" "$TARGET_SSH_KEY_NORM" || true

if [ "$CONNECTIVITY_ONLY" -eq 1 ]; then
  log_info "Connectivity test mode complete"
  exit 0
fi

if remote_run_discovery "SOURCE" "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$SOURCE_SSH_KEY_NORM" "$SCRIPT_DIR/zdm_source_discovery.sh" "$SOURCE_OUT_DIR"; then
  SOURCE_OK=1
else
  SOURCE_OK=0
fi

if remote_run_discovery "TARGET" "$TARGET_HOST" "$TARGET_ADMIN_USER" "$TARGET_SSH_KEY_NORM" "$SCRIPT_DIR/zdm_target_discovery.sh" "$TARGET_OUT_DIR"; then
  TARGET_OK=1
else
  TARGET_OK=0
fi

if run_server_local; then
  SERVER_OK=1
else
  SERVER_OK=0
fi

log_info "Discovery Summary"
log_info "SOURCE: $([ "$SOURCE_OK" -eq 1 ] && echo SUCCESS || echo FAILED)"
log_info "TARGET: $([ "$TARGET_OK" -eq 1 ] && echo SUCCESS || echo FAILED)"
log_info "SERVER: $([ "$SERVER_OK" -eq 1 ] && echo SUCCESS || echo FAILED)"

if [ "$SOURCE_OK" -eq 1 ] && [ "$TARGET_OK" -eq 1 ] && [ "$SERVER_OK" -eq 1 ]; then
  log_info "Step2 discovery completed successfully"
  exit 0
fi

log_warn "Step2 discovery completed with failures. Review logs and outputs in $DISCOVERY_DIR"
exit 1
