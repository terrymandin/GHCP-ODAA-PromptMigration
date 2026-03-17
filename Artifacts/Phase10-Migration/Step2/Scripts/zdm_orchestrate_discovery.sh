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
VERBOSE=0
TEST_ONLY=0

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
  -o PasswordAuthentication=no
)
SCP_OPTS=(
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=15
  -o PasswordAuthentication=no
)

is_placeholder() { [[ "$1" == *"<"*">"* ]]; }

normalize_key() {
  local key="$1"
  if [ -z "$key" ]; then
    printf '%s\n' ""
    return
  fi
  if is_placeholder "$key"; then
    printf '%s\n' ""
    return
  fi
  if [[ "$key" == ~/* ]]; then
    printf '%s\n' "${HOME}/${key#~/}"
    return
  fi
  printf '%s\n' "$key"
}

SOURCE_SSH_KEY="$(normalize_key "$SOURCE_SSH_KEY")"
TARGET_SSH_KEY="$(normalize_key "$TARGET_SSH_KEY")"

log_info() {
  echo "[INFO] $*"
}

log_warn() {
  echo "[WARN] $*"
}

log_error() {
  echo "[ERROR] $*"
}

show_help() {
  cat <<'EOF'
Usage: bash zdm_orchestrate_discovery.sh [options]

Options:
  -h    Show help and exit
  -c    Show effective configuration and exit
  -t    Connectivity tests only
  -v    Verbose logging
EOF
  exit 0
}

show_config() {
  echo "SOURCE_HOST=$SOURCE_HOST"
  echo "TARGET_HOST=$TARGET_HOST"
  echo "SOURCE_ADMIN_USER=$SOURCE_ADMIN_USER"
  echo "TARGET_ADMIN_USER=$TARGET_ADMIN_USER"
  echo "ORACLE_USER=$ORACLE_USER"
  echo "ZDM_USER=$ZDM_USER"
  if [ -n "$SOURCE_SSH_KEY" ]; then
    echo "SOURCE_SSH_KEY=$SOURCE_SSH_KEY"
  else
    echo "SOURCE_SSH_KEY=(agent/default)"
  fi
  if [ -n "$TARGET_SSH_KEY" ]; then
    echo "TARGET_SSH_KEY=$TARGET_SSH_KEY"
  else
    echo "TARGET_SSH_KEY=(agent/default)"
  fi
  exit 0
}

while getopts ":hctv" opt; do
  case "$opt" in
    h)
      show_help
      ;;
    c)
      show_config
      ;;
    t)
      TEST_ONLY=1
      ;;
    v)
      VERBOSE=1
      ;;
    ?)
      log_error "Invalid option: -$OPTARG"
      show_help
      ;;
  esac
done

mkdir -p "$SOURCE_OUT_DIR" "$TARGET_OUT_DIR" "$SERVER_OUT_DIR"

log_info "Startup diagnostic"
log_info "Current user: $(whoami)"
log_info "Home directory: $HOME"
if [ "$(whoami)" != "$ZDM_USER" ]; then
  log_warn "This script is expected to run as $ZDM_USER"
fi

ssh_key_files="$(find "$HOME/.ssh" -maxdepth 1 -type f \( -name '*.pem' -o -name '*.key' \) 2>/dev/null)"
if [ -z "$ssh_key_files" ]; then
  log_warn "No .pem or .key files found in $HOME/.ssh"
else
  log_info "Key files detected in $HOME/.ssh:"
  echo "$ssh_key_files"
fi

if [ -n "$SOURCE_SSH_KEY" ]; then
  if [ -f "$SOURCE_SSH_KEY" ]; then
    log_info "SOURCE_SSH_KEY exists: $SOURCE_SSH_KEY"
  else
    log_warn "SOURCE_SSH_KEY is set but missing: $SOURCE_SSH_KEY"
  fi
else
  log_info "SOURCE_SSH_KEY empty/placeholder: using SSH agent or default key"
fi

if [ -n "$TARGET_SSH_KEY" ]; then
  if [ -f "$TARGET_SSH_KEY" ]; then
    log_info "TARGET_SSH_KEY exists: $TARGET_SSH_KEY"
  else
    log_warn "TARGET_SSH_KEY is set but missing: $TARGET_SSH_KEY"
  fi
else
  log_info "TARGET_SSH_KEY empty/placeholder: using SSH agent or default key"
fi

test_connectivity_host() {
  local label="$1"
  local host="$2"
  local admin_user="$3"
  local key_path="$4"

  log_info "Testing SSH connectivity to $label ($admin_user@$host)"
  if ssh "${SSH_OPTS[@]}" ${key_path:+-i "$key_path"} "${admin_user}@${host}" "echo connected to $(hostname -f || hostname)"; then
    log_info "$label connectivity test passed"
    return 0
  fi
  log_error "$label connectivity test failed"
  return 1
}

if [ "$TEST_ONLY" -eq 1 ]; then
  failed=0
  test_connectivity_host "SOURCE" "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$SOURCE_SSH_KEY" || failed=$((failed + 1))
  test_connectivity_host "TARGET" "$TARGET_HOST" "$TARGET_ADMIN_USER" "$TARGET_SSH_KEY" || failed=$((failed + 1))

  if [ "$failed" -gt 0 ]; then
    log_error "Connectivity test-only mode finished with failures: $failed"
    exit 1
  fi

  log_info "Connectivity test-only mode completed successfully"
  exit 0
fi

run_remote_discovery() {
  local type="$1"
  local host="$2"
  local admin_user="$3"
  local key_path="$4"
  local local_script="$5"
  local local_output_dir="$6"
  local remote_dir="/tmp/zdm_step2_${type}_${TIMESTAMP}"

  if [ ! -f "$local_script" ]; then
    log_error "Missing local script: $local_script"
    return 1
  fi

  log_info "Preparing remote directory on $type host: $remote_dir"
  if ! ssh "${SSH_OPTS[@]}" ${key_path:+-i "$key_path"} "${admin_user}@${host}" "mkdir -p '$remote_dir'"; then
    log_error "Failed to create remote directory on $type host"
    return 1
  fi

  log_info "Copying $local_script to $type host"
  if ! scp "${SCP_OPTS[@]}" ${key_path:+-i "$key_path"} "$local_script" "${admin_user}@${host}:$remote_dir/"; then
    log_error "SCP failed for $type script"
    return 1
  fi

  log_info "Executing $type discovery script via login shell"
  if ! ssh "${SSH_OPTS[@]}" ${key_path:+-i "$key_path"} "${admin_user}@${host}" "mkdir -p '$remote_dir' && bash -l -s" < <(echo "cd '$remote_dir'"; cat "$local_script"); then
    log_error "$type discovery script execution failed"
    return 1
  fi

  log_info "Listing remote output files for $type"
  if ! ssh "${SSH_OPTS[@]}" ${key_path:+-i "$key_path"} "${admin_user}@${host}" "ls -la '$remote_dir'"; then
    log_warn "Could not list remote output directory for $type"
  fi

  log_info "Copying $type outputs to $local_output_dir"
  if ! scp "${SCP_OPTS[@]}" ${key_path:+-i "$key_path"} "${admin_user}@${host}:$remote_dir/zdm_${type}_discovery_*" "$local_output_dir/"; then
    log_error "Failed to copy $type outputs from remote host"
    return 1
  fi

  log_info "$type discovery completed successfully"
  return 0
}

run_local_zdm_discovery() {
  local local_script="$1"
  local local_output_dir="$2"
  local tmp_dir="/tmp/zdm_step2_server_${TIMESTAMP}"

  mkdir -p "$tmp_dir"
  cp "$local_script" "$tmp_dir/"

  log_info "Running server discovery locally as $ZDM_USER"
  if ! (cd "$tmp_dir" && SOURCE_HOST="$SOURCE_HOST" TARGET_HOST="$TARGET_HOST" ZDM_USER="$ZDM_USER" bash "$(basename "$local_script")"); then
    log_error "Local server discovery failed"
    return 1
  fi

  log_info "Listing local server temporary output files"
  ls -la "$tmp_dir" || true

  log_info "Copying server outputs to $local_output_dir"
  if ! cp "$tmp_dir"/zdm_server_discovery_* "$local_output_dir/"; then
    log_error "Failed to copy server discovery outputs"
    return 1
  fi

  log_info "Server discovery completed successfully"
  return 0
}

source_result="FAILED"
target_result="FAILED"
server_result="FAILED"

run_remote_discovery \
  "source" \
  "$SOURCE_HOST" \
  "$SOURCE_ADMIN_USER" \
  "$SOURCE_SSH_KEY" \
  "$SCRIPT_DIR/zdm_source_discovery.sh" \
  "$SOURCE_OUT_DIR" && source_result="SUCCESS"

run_remote_discovery \
  "target" \
  "$TARGET_HOST" \
  "$TARGET_ADMIN_USER" \
  "$TARGET_SSH_KEY" \
  "$SCRIPT_DIR/zdm_target_discovery.sh" \
  "$TARGET_OUT_DIR" && target_result="SUCCESS"

run_local_zdm_discovery \
  "$SCRIPT_DIR/zdm_server_discovery.sh" \
  "$SERVER_OUT_DIR" && server_result="SUCCESS"

log_info "Discovery orchestration summary"
log_info "Source: $source_result"
log_info "Target: $target_result"
log_info "Server: $server_result"
log_info "Outputs:"
log_info "  Source -> $SOURCE_OUT_DIR"
log_info "  Target -> $TARGET_OUT_DIR"
log_info "  Server -> $SERVER_OUT_DIR"

if [ "$source_result" != "SUCCESS" ] || [ "$target_result" != "SUCCESS" ] || [ "$server_result" != "SUCCESS" ]; then
  log_warn "One or more discovery runs failed; review logs and re-run as needed"
  exit 1
fi

exit 0
