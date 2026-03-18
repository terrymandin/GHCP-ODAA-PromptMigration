#!/bin/bash

# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration

set -u

ZDM_HOME="${ZDM_HOME:-/mnt/app/zdmhome}"
ZDM_USER="${ZDM_USER:-zdmuser}"
SOURCE_HOST="${SOURCE_HOST:-}"
TARGET_HOST="${TARGET_HOST:-}"

CURRENT_USER="$(whoami)"
if [ "$CURRENT_USER" != "${ZDM_USER:-zdmuser}" ]; then
      echo "[ERROR] This script must run as '${ZDM_USER:-zdmuser}'. Currently running as '${CURRENT_USER}'."
      echo "        Switch to the correct user first: sudo su - ${ZDM_USER:-zdmuser}"
      exit 1
fi

DISCOVERY_TYPE="server"
HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OUT_TXT="./zdm_${DISCOVERY_TYPE}_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
OUT_JSON="./zdm_${DISCOVERY_TYPE}_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

STATUS="success"
WARNINGS=()

escape_json() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

add_warning() {
  WARNINGS+=("$1")
  STATUS="partial"
}

log_section() {
  local title="$1"
  {
    echo ""
    echo "===== ${title} ====="
  } >> "$OUT_TXT"
}

run_cmd() {
  local title="$1"
  shift
  log_section "$title"
  {
    echo "$ $*"
    "$@"
  } >> "$OUT_TXT" 2>&1 || add_warning "Command failed: ${title}"
}

{
  echo "ZDM Step2 Server Discovery"
  echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Discovery Type: ${DISCOVERY_TYPE}"
  echo "Host: ${HOSTNAME_SHORT}"
  echo "Current User: ${CURRENT_USER}"
} > "$OUT_TXT"

run_cmd "Local System Details" uname -a
run_cmd "OS Release" bash -lc 'cat /etc/os-release 2>/dev/null || true'
run_cmd "Uptime" uptime

log_section "ZDM Installation Details"
{
  echo "ZDM_HOME=${ZDM_HOME}"
  if [[ -d "$ZDM_HOME" ]]; then
    echo "ZDM_HOME_EXISTS=yes"
    ls -ld "$ZDM_HOME"
  else
    echo "ZDM_HOME_EXISTS=no"
    add_warning "Configured ZDM_HOME does not exist: ${ZDM_HOME}"
  fi

  if [[ -x "$ZDM_HOME/bin/zdmcli" ]]; then
    echo "ZDMCLI_PATH=${ZDM_HOME}/bin/zdmcli"
    "$ZDM_HOME/bin/zdmcli" -version 2>&1 || add_warning "Unable to execute zdmcli -version"
  else
    echo "ZDMCLI_PATH=<not-found>"
    add_warning "zdmcli not found under ${ZDM_HOME}/bin"
  fi
} >> "$OUT_TXT"

run_cmd "Capacity Snapshot" bash -lc 'df -h; free -h'

log_section "Java Details"
{
  if [[ -x "$ZDM_HOME/jdk/bin/java" ]]; then
    echo "JAVA_HOME=${ZDM_HOME}/jdk"
    "$ZDM_HOME/jdk/bin/java" -version 2>&1
  elif command -v java >/dev/null 2>&1; then
    echo "JAVA_HOME=${JAVA_HOME:-<unset>}"
    java -version 2>&1
  else
    echo "java-not-found"
    add_warning "Java not found in bundled JDK or PATH"
  fi
} >> "$OUT_TXT"

run_cmd "OCI Authentication Configuration" bash -lc '
  if [ -f ~/.oci/config ]; then
    echo "OCI_CONFIG=~/.oci/config"
    awk -F= '/\[|region|fingerprint|tenancy|user|key_file/ {print $1"="$2}' ~/.oci/config | sed -E "s/(fingerprint|tenancy|user)=.*/\1=<masked>/"
  else
    echo "OCI config not found"
  fi

  if [ -f ~/.oci/oci_api_key.pem ]; then
    ls -l ~/.oci/oci_api_key.pem
  fi
'

run_cmd "SSH and Credential Inventory" bash -lc '
  ls -la ~/.ssh 2>/dev/null || true
  find ~ -maxdepth 3 -type f \( -name "*.pem" -o -name "*.key" -o -name "*.p12" -o -name "*.wallet" \) 2>/dev/null | head -n 100
'

run_cmd "Network Context" bash -lc 'ip addr; ip route; cat /etc/resolv.conf 2>/dev/null || true'

run_cmd "Optional Connectivity Tests" bash -lc '
  if [ -n "${SOURCE_HOST}" ]; then
    echo "SOURCE_HOST=${SOURCE_HOST}"
    ping -c 2 "${SOURCE_HOST}" 2>/dev/null || true
    timeout 3 bash -lc "</dev/tcp/${SOURCE_HOST}/22" 2>/dev/null && echo "SOURCE_SSH_PORT_22=open" || echo "SOURCE_SSH_PORT_22=closed_or_filtered"
  else
    echo "SOURCE_HOST not provided"
  fi

  if [ -n "${TARGET_HOST}" ]; then
    echo "TARGET_HOST=${TARGET_HOST}"
    ping -c 2 "${TARGET_HOST}" 2>/dev/null || true
    timeout 3 bash -lc "</dev/tcp/${TARGET_HOST}/22" 2>/dev/null && echo "TARGET_SSH_PORT_22=open" || echo "TARGET_SSH_PORT_22=closed_or_filtered"
    timeout 3 bash -lc "</dev/tcp/${TARGET_HOST}/1521" 2>/dev/null && echo "TARGET_LISTENER_1521=open" || echo "TARGET_LISTENER_1521=closed_or_filtered"
  else
    echo "TARGET_HOST not provided"
  fi
'

log_section "Endpoint Traceability"
{
  echo "SOURCE_HOST=${SOURCE_HOST:-<unset>}"
  echo "TARGET_HOST=${TARGET_HOST:-<unset>}"
  echo "ZDM_USER=${ZDM_USER}"
} >> "$OUT_TXT"

{
  echo ""
  echo "===== Summary ====="
  echo "status=${STATUS}"
  echo "warnings_count=${#WARNINGS[@]}"
} >> "$OUT_TXT"

{
  printf '{\n'
  printf '  "discovery_type": "server",\n'
  printf '  "timestamp": "%s",\n' "$(escape_json "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
  printf '  "host": "%s",\n' "$(escape_json "$HOSTNAME_SHORT")"
  printf '  "current_user": "%s",\n' "$(escape_json "$CURRENT_USER")"
  printf '  "zdm_home": "%s",\n' "$(escape_json "$ZDM_HOME")"
  printf '  "status": "%s",\n' "$(escape_json "$STATUS")"
  printf '  "warnings": ['

  i=0
  while [[ $i -lt ${#WARNINGS[@]} ]]; do
    if [[ $i -gt 0 ]]; then
      printf ', '
    fi
    printf '"%s"' "$(escape_json "${WARNINGS[$i]}")"
    i=$((i + 1))
  done

  printf ']\n'
  printf '}\n'
} > "$OUT_JSON"

echo "[INFO] Server discovery text output: ${OUT_TXT}"
echo "[INFO] Server discovery json output: ${OUT_JSON}"
