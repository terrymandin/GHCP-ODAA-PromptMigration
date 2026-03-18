#!/bin/bash
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration

set -u

show_help() {
  cat <<'HELP'
Usage: zdm_orchestrate_discovery.sh [-h] [-c] [-t TARGET] [-v]
  -h  Show help and exit
  -c  Show effective configuration and exit
  -t  Run only one target: source|target|server|all (default all)
  -v  Verbose startup diagnostics
HELP
  exit 0
}

SOURCE_HOST="${SOURCE_HOST:-10.200.1.12}"
TARGET_HOST="${TARGET_HOST:-10.200.0.250}"
SOURCE_ADMIN_USER="${SOURCE_ADMIN_USER:-${SOURCE_SSH_USER:-azureuser}}"
TARGET_ADMIN_USER="${TARGET_ADMIN_USER:-${TARGET_SSH_USER:-opc}}"
ORACLE_USER="${ORACLE_USER:-oracle}"
ZDM_USER="${ZDM_USER:-zdmuser}"
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-}"
TARGET_SSH_KEY="${TARGET_SSH_KEY:-}"

is_placeholder() { [[ "$1" == *"<"*">"* ]]; }
[ -n "$SOURCE_SSH_KEY" ] && is_placeholder "$SOURCE_SSH_KEY" && SOURCE_SSH_KEY=""
[ -n "$TARGET_SSH_KEY" ] && is_placeholder "$TARGET_SSH_KEY" && TARGET_SSH_KEY=""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STEP2_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_ROOT="${OUTPUT_ROOT:-$STEP2_DIR/Discovery}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
RUN_TARGET="all"
VERBOSE=0

show_config() {
  cat <<CFG
Effective configuration:
  SOURCE_HOST=$SOURCE_HOST
  TARGET_HOST=$TARGET_HOST
  SOURCE_ADMIN_USER=$SOURCE_ADMIN_USER
  TARGET_ADMIN_USER=$TARGET_ADMIN_USER
  ORACLE_USER=$ORACLE_USER
  ZDM_USER=$ZDM_USER
  SOURCE_SSH_KEY=${SOURCE_SSH_KEY:-<unset>}
  TARGET_SSH_KEY=${TARGET_SSH_KEY:-<unset>}
  OUTPUT_ROOT=$OUTPUT_ROOT
  RUN_TARGET=$RUN_TARGET
CFG
  exit 0
}

while getopts ":hct:v" opt; do
  case "$opt" in
    h) show_help ;;
    c) show_config ;;
    t) RUN_TARGET="$OPTARG" ;;
    v) VERBOSE=1 ;;
    :) echo "[ERROR] Option -$OPTARG requires an argument"; exit 2 ;;
    \?) echo "[ERROR] Unknown option -$OPTARG"; exit 2 ;;
  esac
done

mkdir -p "$OUTPUT_ROOT/source" "$OUTPUT_ROOT/target" "$OUTPUT_ROOT/server"
LOG_FILE="$OUTPUT_ROOT/discovery_orchestrator_${TIMESTAMP}.log"
REPORT_MD="$OUTPUT_ROOT/discovery_orchestrator_${TIMESTAMP}.md"
REPORT_JSON="$OUTPUT_ROOT/discovery_orchestrator_${TIMESTAMP}.json"

PASS_LIST=()
FAIL_LIST=()
WARNINGS=()

log() {
  printf '%s\n' "$*" | tee -a "$LOG_FILE"
}

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/ }"
  printf '%s' "$s"
}

record_pass() { PASS_LIST+=("$1|$2"); }
record_fail() { FAIL_LIST+=("$1|$2"); WARNINGS+=("$1 failed: $2"); }

startup_diagnostics() {
  log "==== Startup diagnostics ===="
  log "current_user=$(whoami)"
  log "home=$HOME"
  log "source_key_normalized=${SOURCE_SSH_KEY:-unset}"
  log "target_key_normalized=${TARGET_SSH_KEY:-unset}"
  [ -n "$SOURCE_SSH_KEY" ] && [ -f "$SOURCE_SSH_KEY" ] && log "source_key_exists=yes" || log "source_key_exists=no"
  [ -n "$TARGET_SSH_KEY" ] && [ -f "$TARGET_SSH_KEY" ] && log "target_key_exists=yes" || log "target_key_exists=no"
  log "pem_and_key_inventory:"
  ls -l "$HOME"/.ssh/*.pem "$HOME"/.ssh/*.key 2>/dev/null | tee -a "$LOG_FILE" || true
  if [ "$VERBOSE" -eq 1 ]; then
    log "verbose enabled"
    env | sort | grep -E '^(SOURCE|TARGET|ORACLE|ZDM|OUTPUT_ROOT|HOME)=' | tee -a "$LOG_FILE" || true
  fi
}

run_remote_discovery() {
  local dtype="$1"
  local host="$2"
  local admin_user="$3"
  local key_path="$4"
  local script_path="$SCRIPT_DIR/zdm_${dtype}_discovery.sh"
  local out_dir="$OUTPUT_ROOT/$dtype"
  local remote_dir="$HOME/zdm-step2-${dtype}-${TIMESTAMP}"
  local remote_log="zdm_${dtype}_remote_exec_${TIMESTAMP}.log"

  if [ ! -f "$script_path" ]; then
    record_fail "$dtype" "missing script $script_path"
    return 1
  fi

  log "==== Running $dtype discovery on $host ===="

  if ! ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new ${key_path:+-i "$key_path"} "${admin_user}@${host}" "mkdir -p $remote_dir"; then
    record_fail "$dtype" "remote working-directory setup failed on $host"
    return 1
  fi

  if ! scp -o BatchMode=yes -o StrictHostKeyChecking=accept-new ${key_path:+-i "$key_path"} "$script_path" "${admin_user}@${host}:$remote_dir/"; then
    record_fail "$dtype" "scp script failed to $host"
    return 1
  fi

  if ! ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new ${key_path:+-i "$key_path"} "${admin_user}@${host}" \
      "mkdir -p $remote_dir && bash -l -s" \
      < <(printf 'cd %q\nchmod +x %q\n./%q > %q 2>&1\n' "$remote_dir" "zdm_${dtype}_discovery.sh" "zdm_${dtype}_discovery.sh" "$remote_log"); then
    record_fail "$dtype" "remote execution failed on $host"
    return 1
  fi

  if ! ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new ${key_path:+-i "$key_path"} "${admin_user}@${host}" \
      "cd $remote_dir && ls zdm_${dtype}_discovery_*.txt zdm_${dtype}_discovery_*.json >/dev/null 2>&1"; then
    record_fail "$dtype" "remote output files missing on $host"
    return 1
  fi

  if ! scp -o BatchMode=yes -o StrictHostKeyChecking=accept-new ${key_path:+-i "$key_path"} \
      "${admin_user}@${host}:$remote_dir/zdm_${dtype}_discovery_*.txt" "$out_dir/"; then
    record_fail "$dtype" "failed to copy raw output from $host"
    return 1
  fi

  if ! scp -o BatchMode=yes -o StrictHostKeyChecking=accept-new ${key_path:+-i "$key_path"} \
      "${admin_user}@${host}:$remote_dir/zdm_${dtype}_discovery_*.json" "$out_dir/"; then
    record_fail "$dtype" "failed to copy json output from $host"
    return 1
  fi

  scp -o BatchMode=yes -o StrictHostKeyChecking=accept-new ${key_path:+-i "$key_path"} \
      "${admin_user}@${host}:$remote_dir/$remote_log" "$out_dir/" >/dev/null 2>&1 || true

  record_pass "$dtype" "$out_dir"
  return 0
}

run_server_discovery() {
  local dtype="server"
  local script_path="$SCRIPT_DIR/zdm_server_discovery.sh"
  local out_dir="$OUTPUT_ROOT/server"

  if [ ! -f "$script_path" ]; then
    record_fail "$dtype" "missing script $script_path"
    return 1
  fi

  log "==== Running server discovery locally ===="
  if SOURCE_HOST="$SOURCE_HOST" TARGET_HOST="$TARGET_HOST" ZDM_USER="$ZDM_USER" bash "$script_path"; then
    mv ./zdm_server_discovery_*.txt "$out_dir/" 2>/dev/null || true
    mv ./zdm_server_discovery_*.json "$out_dir/" 2>/dev/null || true
    record_pass "$dtype" "$out_dir"
    return 0
  fi

  record_fail "$dtype" "local script execution failed"
  return 1
}

write_reports() {
  local overall="PASS"
  [ "${#FAIL_LIST[@]}" -gt 0 ] && overall="FAIL"

  {
    echo "# Step2 Discovery Orchestration Report"
    echo ""
    echo "- Timestamp: $TIMESTAMP"
    echo "- Overall status: $overall"
    echo "- Raw orchestrator log: $LOG_FILE"
    echo "- Output formats: raw text (.txt), markdown report (.md), JSON report (.json)"
    echo ""
    echo "## Effective runtime configuration"
    echo "- SOURCE_HOST: $SOURCE_HOST"
    echo "- TARGET_HOST: $TARGET_HOST"
    echo "- SOURCE_ADMIN_USER: $SOURCE_ADMIN_USER"
    echo "- TARGET_ADMIN_USER: $TARGET_ADMIN_USER"
    echo "- ORACLE_USER: $ORACLE_USER"
    echo "- ZDM_USER: $ZDM_USER"
    echo "- SOURCE_SSH_KEY: ${SOURCE_SSH_KEY:-<unset>}"
    echo "- TARGET_SSH_KEY: ${TARGET_SSH_KEY:-<unset>}"
    echo ""
    echo "## Per-script status"
    if [ "${#PASS_LIST[@]}" -gt 0 ]; then
      for item in "${PASS_LIST[@]}"; do
        IFS='|' read -r name path <<<"$item"
        echo "- PASS: $name (outputs in $path)"
      done
    fi
    if [ "${#FAIL_LIST[@]}" -gt 0 ]; then
      for item in "${FAIL_LIST[@]}"; do
        IFS='|' read -r name msg <<<"$item"
        echo "- FAIL: $name ($msg)"
      done
    fi
  } >"$REPORT_MD"

  {
    printf '{\n'
    printf '  "status": "%s",\n' "$([ "$overall" = "PASS" ] && echo success || echo partial)"
    printf '  "timestamp": "%s",\n' "$TIMESTAMP"
    printf '  "log": "%s",\n' "$(json_escape "$LOG_FILE")"
    printf '  "markdown_report": "%s",\n' "$(json_escape "$REPORT_MD")"
    printf '  "warnings": ['
    if [ "${#WARNINGS[@]}" -gt 0 ]; then
      printf '\n'
      for i in "${!WARNINGS[@]}"; do
        printf '    "%s"' "$(json_escape "${WARNINGS[$i]}")"
        [ "$i" -lt $(( ${#WARNINGS[@]} - 1 )) ] && printf ','
        printf '\n'
      done
      printf '  '
    fi
    printf ']\n'
    printf '}\n'
  } >"$REPORT_JSON"

  log "==== Step2 discovery complete ===="
  log "overall_status=$overall"
  log "orchestrator_log=$LOG_FILE"
  log "markdown_report=$REPORT_MD"
  log "json_report=$REPORT_JSON"
}

main() {
  : >"$LOG_FILE"
  startup_diagnostics

  case "$RUN_TARGET" in
    all)
      run_remote_discovery source "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$SOURCE_SSH_KEY"
      run_remote_discovery target "$TARGET_HOST" "$TARGET_ADMIN_USER" "$TARGET_SSH_KEY"
      run_server_discovery
      ;;
    source)
      run_remote_discovery source "$SOURCE_HOST" "$SOURCE_ADMIN_USER" "$SOURCE_SSH_KEY"
      ;;
    target)
      run_remote_discovery target "$TARGET_HOST" "$TARGET_ADMIN_USER" "$TARGET_SSH_KEY"
      ;;
    server)
      run_server_discovery
      ;;
    *)
      echo "[ERROR] Invalid -t value: $RUN_TARGET" >&2
      exit 2
      ;;
  esac

  write_reports
  [ "${#FAIL_LIST[@]}" -gt 0 ] && exit 1
  exit 0
}

main "$@"