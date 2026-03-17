#!/bin/bash
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEP2_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DISCOVERY_DIR="$STEP2_DIR/Discovery"
SOURCE_OUT_DIR="$DISCOVERY_DIR/source"
TARGET_OUT_DIR="$DISCOVERY_DIR/target"
SERVER_OUT_DIR="$DISCOVERY_DIR/server"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$STEP2_DIR/discovery-orchestrator-$TIMESTAMP.log"

SOURCE_HOST="${SOURCE_HOST:-}"
TARGET_HOST="${TARGET_HOST:-}"
SOURCE_ADMIN_USER="${SOURCE_ADMIN_USER:-${SOURCE_SSH_USER:-azureuser}}"
TARGET_ADMIN_USER="${TARGET_ADMIN_USER:-${TARGET_SSH_USER:-azureuser}}"
ORACLE_USER="${ORACLE_USER:-oracle}"
ZDM_USER="${ZDM_USER:-zdmuser}"
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-}"
TARGET_SSH_KEY="${TARGET_SSH_KEY:-}"

VERBOSE=0
TEST_ONLY=0

SOURCE_OK=0
TARGET_OK=0
SERVER_OK=0

log_info() {
  local msg="$1"
  printf '[INFO] %s\n' "$msg" | tee -a "$LOG_FILE"
}

log_warn() {
  local msg="$1"
  printf '[WARN] %s\n' "$msg" | tee -a "$LOG_FILE"
}

log_error() {
  local msg="$1"
  printf '[ERROR] %s\n' "$msg" | tee -a "$LOG_FILE"
}

show_help() {
  cat <<'EOF'
Usage: bash zdm_orchestrate_discovery.sh [options]

Options:
  -h    Show help and exit
  -c    Show resolved configuration and exit
  -t    Connectivity test only (no discovery execution)
  -v    Verbose output
EOF
  exit 0
}

show_config() {
  cat <<EOF
Resolved configuration:
  SOURCE_HOST=$SOURCE_HOST
  TARGET_HOST=$TARGET_HOST
  SOURCE_ADMIN_USER=$SOURCE_ADMIN_USER
  TARGET_ADMIN_USER=$TARGET_ADMIN_USER
  ORACLE_USER=$ORACLE_USER
  ZDM_USER=$ZDM_USER
  SOURCE_SSH_KEY=${SOURCE_SSH_KEY:-<empty - using agent/default key>}
  TARGET_SSH_KEY=${TARGET_SSH_KEY:-<empty - using agent/default key>}
  SCRIPT_DIR=$SCRIPT_DIR
  STEP2_DIR=$STEP2_DIR
  DISCOVERY_DIR=$DISCOVERY_DIR
EOF
  exit 0
}

expand_home() {
  local p="$1"
  if [[ "$p" == ~/* ]]; then
    printf '%s\n' "${HOME}/${p#~/}"
  else
    printf '%s\n' "$p"
  fi
}

print_startup_diagnostics() {
  log_info "Startup diagnostics"
  log_info "Current user: $(whoami)"
  log_info "Home directory: $HOME"

  local key_files
  key_files="$(find "$HOME/.ssh" -maxdepth 1 -type f \( -name '*.pem' -o -name '*.key' \) 2>/dev/null)"
  if [ -z "$key_files" ]; then
    log_warn "No .pem or .key files found in $HOME/.ssh"
  else
    log_info "SSH key files found in $HOME/.ssh:"
    while IFS= read -r k; do
      [ -n "$k" ] && log_info "  - $k"
    done <<< "$key_files"
  fi

  for key_name in SOURCE_SSH_KEY TARGET_SSH_KEY; do
    key_val="${!key_name:-}"
    if [ -z "$key_val" ]; then
      log_info "$key_name is empty; SSH agent/default key will be used"
    else
      resolved="$(expand_home "$key_val")"
      if [ -f "$resolved" ]; then
        log_info "$key_name resolves to existing file: $resolved"
      else
        log_warn "$key_name resolves to missing file: $resolved"
      fi
    fi
  done
}

connectivity_test() {
  local host="$1"
  local admin_user="$2"
  local key_path="$3"

  if [ -z "$host" ]; then
    log_warn "Skipping connectivity check: host is empty"
    return 1
  fi

  local ssh_out ssh_rc
  ssh_out="$(ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new ${key_path:+-i "$key_path"} "${admin_user}@${host}" "hostname" 2>&1)"
  ssh_rc=$?
  if [ $ssh_rc -ne 0 ]; then
    log_error "SSH connectivity failed for ${admin_user}@${host}: $ssh_out"
    return 1
  fi
  log_info "SSH connectivity OK for ${admin_user}@${host} (remote hostname: $ssh_out)"
  return 0
}

run_remote_discovery() {
  local label="$1"
  local host="$2"
  local admin_user="$3"
  local key_path="$4"
  local local_script="$5"
  local remote_dir="/tmp/zdm_discovery_${label}_${TIMESTAMP}"
  local log_copy="$STEP2_DIR/${label}-orchestrate-$TIMESTAMP.log"

  if [ -z "$host" ]; then
    log_warn "${label}: host is empty; skipping"
    return 1
  fi

  local prep_out prep_rc
  prep_out="$(ssh -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new ${key_path:+-i "$key_path"} "${admin_user}@${host}" "mkdir -p '$remote_dir'" 2>&1)"
  prep_rc=$?
  if [ $prep_rc -ne 0 ]; then
    log_error "${label}: failed to prepare remote temp directory: $prep_out"
    return 1
  fi

  local copy_out copy_rc
  copy_out="$(scp -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new ${key_path:+-i "$key_path"} "$local_script" "${admin_user}@${host}:$remote_dir/" 2>&1)"
  copy_rc=$?
  if [ $copy_rc -ne 0 ]; then
    log_error "${label}: failed to copy script: $copy_out"
    return 1
  fi

  local remote_script
  remote_script="$(basename "$local_script")"

  local run_out run_rc
  run_out="$(ssh -o BatchMode=yes -o ConnectTimeout=30 -o StrictHostKeyChecking=accept-new ${key_path:+-i "$key_path"} "${admin_user}@${host}" "mkdir -p '$remote_dir' && bash -l -s" < <(echo "cd '$remote_dir'"; cat "$local_script") 2>&1)"
  run_rc=$?
  printf '%s\n' "$run_out" > "$log_copy"
  if [ $run_rc -ne 0 ]; then
    log_error "${label}: remote script execution failed. See $log_copy"
    return 1
  fi

  local ls_out
  ls_out="$(ssh -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new ${key_path:+-i "$key_path"} "${admin_user}@${host}" "ls -la '$remote_dir'" 2>&1)"
  log_info "${label}: remote temp directory contents:"
  printf '%s\n' "$ls_out" | tee -a "$LOG_FILE"

  local out_dir
  if [ "$label" = "source" ]; then
    out_dir="$SOURCE_OUT_DIR"
  else
    out_dir="$TARGET_OUT_DIR"
  fi

  local fetch_out fetch_rc
  fetch_out="$(scp -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new ${key_path:+-i "$key_path"} "${admin_user}@${host}:$remote_dir/zdm_${label}_discovery_*.txt" "$out_dir/" 2>&1; scp -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new ${key_path:+-i "$key_path"} "${admin_user}@${host}:$remote_dir/zdm_${label}_discovery_*.json" "$out_dir/" 2>&1)"
  fetch_rc=$?
  if [ $fetch_rc -ne 0 ]; then
    log_error "${label}: failed to fetch output files: $fetch_out"
    return 1
  fi

  log_info "${label}: discovery output fetched to $out_dir"
  return 0
}

run_server_discovery() {
  local local_script="$SCRIPT_DIR/zdm_server_discovery.sh"
  local out

  out="$(cd "$SERVER_OUT_DIR" && SOURCE_HOST="$SOURCE_HOST" TARGET_HOST="$TARGET_HOST" ZDM_USER="$ZDM_USER" bash "$local_script" 2>&1)"
  local rc=$?
  printf '%s\n' "$out" | tee -a "$LOG_FILE"

  if [ $rc -ne 0 ]; then
    log_error "server: local server discovery failed"
    return 1
  fi

  log_info "server: local server discovery completed"
  return 0
}

mkdir -p "$SOURCE_OUT_DIR" "$TARGET_OUT_DIR" "$SERVER_OUT_DIR"

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

if [ "$(whoami)" != "$ZDM_USER" ]; then
  log_warn "Recommended to run as '$ZDM_USER' (current user: $(whoami))"
fi

print_startup_diagnostics

RESOLVED_SOURCE_KEY=""
RESOLVED_TARGET_KEY=""
[ -n "$SOURCE_SSH_KEY" ] && RESOLVED_SOURCE_KEY="$(expand_home "$SOURCE_SSH_KEY")"
[ -n "$TARGET_SSH_KEY" ] && RESOLVED_TARGET_KEY="$(expand_home "$TARGET_SSH_KEY")"

if [ $TEST_ONLY -eq 1 ]; then
  log_info "Running connectivity test only"
  connectivity_test "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$RESOLVED_SOURCE_KEY"
  connectivity_test "$TARGET_HOST" "$TARGET_ADMIN_USER" "$RESOLVED_TARGET_KEY"
  exit 0
fi

run_remote_discovery "source" "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$RESOLVED_SOURCE_KEY" "$SCRIPT_DIR/zdm_source_discovery.sh"
if [ $? -eq 0 ]; then
  SOURCE_OK=1
fi

run_remote_discovery "target" "$TARGET_HOST" "$TARGET_ADMIN_USER" "$RESOLVED_TARGET_KEY" "$SCRIPT_DIR/zdm_target_discovery.sh"
if [ $? -eq 0 ]; then
  TARGET_OK=1
fi

run_server_discovery
if [ $? -eq 0 ]; then
  SERVER_OK=1
fi

log_info ""
log_info "Discovery summary:"
log_info "  source: $([ $SOURCE_OK -eq 1 ] && echo success || echo failed)"
log_info "  target: $([ $TARGET_OK -eq 1 ] && echo success || echo failed)"
log_info "  server: $([ $SERVER_OK -eq 1 ] && echo success || echo failed)"
log_info "Orchestration log: $LOG_FILE"

if [ $SOURCE_OK -eq 1 ] && [ $TARGET_OK -eq 1 ] && [ $SERVER_OK -eq 1 ]; then
  exit 0
fi

exit 1
