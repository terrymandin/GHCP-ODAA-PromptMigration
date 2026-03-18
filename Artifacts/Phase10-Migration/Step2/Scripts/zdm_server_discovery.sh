#!/bin/bash
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration

set -u

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
HOSTNAME_SAFE="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)"
RAW_OUT="./zdm_server_discovery_${HOSTNAME_SAFE}_${TIMESTAMP}.txt"
JSON_OUT="./zdm_server_discovery_${HOSTNAME_SAFE}_${TIMESTAMP}.json"

SOURCE_HOST="${SOURCE_HOST:-}"
TARGET_HOST="${TARGET_HOST:-}"
ZDM_HOME="${ZDM_HOME:-/mnt/app/zdmhome}"
ZDM_USER="${ZDM_USER:-zdmuser}"

WARNINGS=()
SECTION_FAILS=0

log() { printf '%s\n' "$*" | tee -a "$RAW_OUT"; }
warn() {
  WARNINGS+=("$*")
  printf '[WARN] %s\n' "$*" | tee -a "$RAW_OUT"
}
section() { log ""; log "==== $* ===="; }

run_cmd() {
  local label="$1"
  shift
  log "[CMD] $label"
  if "$@" >>"$RAW_OUT" 2>&1; then
    return 0
  fi
  warn "Command failed: $label"
  SECTION_FAILS=$((SECTION_FAILS + 1))
  return 1
}

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/ }"
  printf '%s' "$s"
}

CURRENT_USER="$(whoami)"
if [ "$CURRENT_USER" != "${ZDM_USER:-zdmuser}" ]; then
      echo "[ERROR] This script must run as '${ZDM_USER:-zdmuser}'. Currently running as '${CURRENT_USER}'."
      echo "        Switch to the correct user first: sudo su - ${ZDM_USER:-zdmuser}"
      exit 1
fi

write_json_summary() {
  local status="success"
  if [ "$SECTION_FAILS" -gt 0 ]; then
    status="partial"
  fi

  {
    printf '{\n'
    printf '  "status": "%s",\n' "$status"
    printf '  "type": "server",\n'
    printf '  "host": "%s",\n' "$(json_escape "$HOSTNAME_SAFE")"
    printf '  "timestamp": "%s",\n' "$TIMESTAMP"
    printf '  "raw_output": "%s",\n' "$(json_escape "$RAW_OUT")"
    printf '  "warnings": ['
    if [ "${#WARNINGS[@]}" -gt 0 ]; then
      printf '\n'
      local i
      for i in "${!WARNINGS[@]}"; do
        printf '    "%s"' "$(json_escape "${WARNINGS[$i]}")"
        if [ "$i" -lt $(( ${#WARNINGS[@]} - 1 )) ]; then
          printf ','
        fi
        printf '\n'
      done
      printf '  '
    fi
    printf ']\n'
    printf '}\n'
  } >"$JSON_OUT"
}

main() {
  : >"$RAW_OUT"

  section "Local system details"
  run_cmd "hostname" hostname
  run_cmd "uname" uname -a
  run_cmd "uptime" uptime
  run_cmd "current user" whoami

  section "ZDM installation details"
  log "ZDM_HOME=$ZDM_HOME"
  run_cmd "zdm home permissions" bash -lc 'if [ -d "'"$ZDM_HOME"'" ]; then ls -ld "'"$ZDM_HOME"'"; else echo zdm-home-not-found; fi'
  run_cmd "zdmcli location" bash -lc 'if [ -x "'"$ZDM_HOME"'"/bin/zdmcli ]; then ls -l "'"$ZDM_HOME"'"/bin/zdmcli; else command -v zdmcli || echo zdmcli-not-found; fi'
  run_cmd "zdmcli version" bash -lc 'if [ -x "'"$ZDM_HOME"'"/bin/zdmcli ]; then "'"$ZDM_HOME"'"/bin/zdmcli -version; elif command -v zdmcli >/dev/null 2>&1; then zdmcli -version; else echo zdmcli-not-found; fi'

  section "Capacity snapshot"
  run_cmd "disk usage" df -h
  run_cmd "memory summary" bash -lc 'free -m 2>/dev/null || vm_stat 2>/dev/null || echo no-memory-tool'

  section "Java details"
  run_cmd "bundled jdk" bash -lc 'if [ -x "'"$ZDM_HOME"'"/jdk/bin/java ]; then "'"$ZDM_HOME"'"/jdk/bin/java -version; else echo bundled-jdk-not-found; fi'
  run_cmd "JAVA_HOME and system java" bash -lc 'echo JAVA_HOME=${JAVA_HOME:-unset}; java -version 2>&1 || echo java-not-found'

  section "OCI authentication configuration"
  run_cmd "oci config sanitized" bash -lc 'if [ -f ~/.oci/config ]; then sed -E "s#(key_file\s*=\s*).*#\1***#g" ~/.oci/config; else echo ~/.oci/config-not-found; fi'
  run_cmd "oci key permissions" bash -lc 'if [ -d ~/.oci ]; then ls -la ~/.oci; else echo ~/.oci-not-found; fi'

  section "SSH and credential inventory"
  run_cmd "ssh inventory" bash -lc 'ls -la ~/.ssh 2>/dev/null || echo ~/.ssh-not-found; ls -l ~/.ssh/*.pem ~/.ssh/*.key 2>/dev/null || true'

  section "Network context"
  run_cmd "ip and routing" bash -lc 'ip addr 2>/dev/null || ifconfig 2>/dev/null || true; ip route 2>/dev/null || netstat -rn 2>/dev/null || true'
  run_cmd "dns settings" bash -lc 'cat /etc/resolv.conf 2>/dev/null || echo resolv.conf-not-found'

  section "Optional source and target connectivity"
  if [ -n "$SOURCE_HOST" ]; then
    run_cmd "ping source" bash -lc 'ping -c 2 "'"$SOURCE_HOST"'"'
    run_cmd "source port 22" bash -lc 'timeout 5 bash -lc "</dev/tcp/'"$SOURCE_HOST"'/22" && echo open || echo closed'
  else
    log "source_host not set; skipping connectivity tests"
  fi

  if [ -n "$TARGET_HOST" ]; then
    run_cmd "ping target" bash -lc 'ping -c 2 "'"$TARGET_HOST"'"'
    run_cmd "target port 22" bash -lc 'timeout 5 bash -lc "</dev/tcp/'"$TARGET_HOST"'/22" && echo open || echo closed'
    run_cmd "target port 1521" bash -lc 'timeout 5 bash -lc "</dev/tcp/'"$TARGET_HOST"'/1521" && echo open || echo closed'
  else
    log "target_host not set; skipping connectivity tests"
  fi

  section "Endpoint traceability"
  log "source_host=$SOURCE_HOST"
  log "target_host=$TARGET_HOST"

  write_json_summary
  log ""
  log "Discovery complete"
  log "raw_output=$RAW_OUT"
  log "json_output=$JSON_OUT"
}

main "$@"