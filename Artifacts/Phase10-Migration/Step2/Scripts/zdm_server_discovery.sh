#!/bin/bash
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration

set -u
set -o pipefail

ZDM_USER="${ZDM_USER:-zdmuser}"
SOURCE_HOST="${SOURCE_HOST:-}"
TARGET_HOST="${TARGET_HOST:-}"

CURRENT_USER="$(whoami)"
if [ "$CURRENT_USER" != "${ZDM_USER:-zdmuser}" ]; then
    echo "[ERROR] This script must run as '${ZDM_USER:-zdmuser}'. Currently running as '${CURRENT_USER}'."
    echo "        Switch to the correct user first: sudo su - ${ZDM_USER:-zdmuser}"
    exit 1
fi

HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_TXT="./zdm_server_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
REPORT_JSON="./zdm_server_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

WARNINGS=()
FAILED_SECTIONS=()

log_header() {
  local title="$1"
  {
    echo
    echo "============================================================"
    echo "$title"
    echo "============================================================"
  } >> "$REPORT_TXT"
}

log_raw() {
  printf '%s\n' "$1" >> "$REPORT_TXT"
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\r//g; :a;N;$!ba;s/\n/\\n/g'
}

add_warning() {
  WARNINGS+=("$1")
  log_raw "[WARN] $1"
}

add_failure() {
  FAILED_SECTIONS+=("$1")
  log_raw "[ERROR] Section failed: $1"
}

run_cmd_section() {
  local section="$1"
  local cmd="$2"
  log_header "$section"
  bash -lc "$cmd" >> "$REPORT_TXT" 2>&1
  local rc=$?
  if [ $rc -ne 0 ]; then
    add_failure "$section"
  fi
}

resolve_zdm_home() {
  if [ -n "${ZDM_HOME:-}" ] && [ -d "$ZDM_HOME" ]; then
    printf '%s\n' "$ZDM_HOME"
    return
  fi

  if [ -n "${ORACLE_HOME:-}" ] && [ -x "${ORACLE_HOME}/bin/zdmcli" ]; then
    printf '%s\n' "$ORACLE_HOME"
    return
  fi

  for p in "/mnt/app/zdmhome" "$HOME/zdmhome" "/u01/app/zdmhome" "/opt/oracle/zdm"; do
    if [ -d "$p" ] && [ -x "$p/bin/zdmcli" ]; then
      printf '%s\n' "$p"
      return
    fi
  done

  local found
  found="$(find /mnt /u01 /opt -maxdepth 4 -type f -name zdmcli 2>/dev/null | head -n1)"
  if [ -n "$found" ]; then
    dirname "$(dirname "$found")"
    return
  fi

  printf '%s\n' ""
}

mask_oci_config() {
  local cfg="$1"
  if [ -f "$cfg" ]; then
    sed -E 's#(key_file|fingerprint|tenancy|user|pass_phrase) *=.*#\1 = ***MASKED***#g' "$cfg"
  fi
}

check_rtt_warning() {
  local host="$1"
  local avg
  avg="$(ping -c 10 "$host" 2>/dev/null | awk -F'/' '/^rtt|^round-trip/ {print $5}')"
  if [ -n "$avg" ]; then
    local avg_int
    avg_int="${avg%.*}"
    if [ "$avg_int" -gt 10 ] 2>/dev/null; then
      add_warning "Average RTT to $host is ${avg}ms (>10ms)"
    fi
  fi
}

port_check() {
  local host="$1"
  local port="$2"
  timeout 3 bash -lc "</dev/tcp/${host}/${port}" >/dev/null 2>&1
}

ZDM_HOME_EFFECTIVE="$(resolve_zdm_home)"

{
  echo "# ZDM Server Discovery Report"
  echo "# Host: $HOSTNAME_SHORT"
  echo "# Timestamp: $TIMESTAMP"
  echo "# Current user: $CURRENT_USER"
  echo "# Resolved ZDM_HOME: ${ZDM_HOME_EFFECTIVE:-<unset>}"
} > "$REPORT_TXT"

run_cmd_section "OS baseline" "hostname -f; whoami; cat /etc/os-release; df -h"

log_header "Disk free-space check (<50GB warning)"
df -BG | awk 'NR>1 {gsub(/G/,"",$4); if ($4 < 50) print $6 " has only " $4 "GB free"}' >> "$REPORT_TXT" 2>&1
if [ $? -ne 0 ]; then
  add_failure "Disk free-space check"
fi

if df -BG | awk 'NR>1 {gsub(/G/,"",$4); if ($4 < 50) print "warn"}' | grep -q warn; then
  add_warning "One or more filesystems have less than 50GB free"
fi

run_cmd_section "ZDM installation and status" "echo ZDM_HOME=${ZDM_HOME_EFFECTIVE:-}; [ -n '$ZDM_HOME_EFFECTIVE' ] && ls -la '$ZDM_HOME_EFFECTIVE' || true; [ -n '$ZDM_HOME_EFFECTIVE' ] && grep -R 'version' '$ZDM_HOME_EFFECTIVE/inventory' '$ZDM_HOME_EFFECTIVE/rhp' 2>/dev/null | head -n 20 || true; [ -n '$ZDM_HOME_EFFECTIVE' ] && '$ZDM_HOME_EFFECTIVE/bin/zdmservice' status 2>/dev/null || true; [ -n '$ZDM_HOME_EFFECTIVE' ] && '$ZDM_HOME_EFFECTIVE/bin/zdmcli' query job 2>/dev/null || true; [ -n '$ZDM_HOME_EFFECTIVE' ] && ls -la '$ZDM_HOME_EFFECTIVE/rhp/zdm/template/' 2>/dev/null || true"

run_cmd_section "Java runtime" "if [ -n '$ZDM_HOME_EFFECTIVE' ] && [ -x '$ZDM_HOME_EFFECTIVE/jdk/bin/java' ]; then '$ZDM_HOME_EFFECTIVE/jdk/bin/java' -version; echo JAVA_HOME=$ZDM_HOME_EFFECTIVE/jdk; else java -version 2>&1; echo JAVA_HOME=${JAVA_HOME:-}; fi"

run_cmd_section "OCI authentication and keys" "[ -f '$HOME/.oci/config' ] && sed -E 's#(key_file|fingerprint|tenancy|user|pass_phrase) *=.*#\\1 = ***MASKED***#g' '$HOME/.oci/config' || echo 'No ~/.oci/config found'; [ -f '$HOME/.oci/config' ] && awk -F= '/key_file/ {gsub(/ /, "", $2); print $2}' '$HOME/.oci/config' | while read -r f; do [ -f \"$f\" ] && stat -c '%a %n' \"$f\" || echo \"MISSING $f\"; done"

run_cmd_section "SSH and credential files" "ls -la '$HOME/.ssh' 2>/dev/null; find '$HOME' -maxdepth 2 -type f \( -name '*cred*' -o -name '*pass*' -o -name '*.pwd' \) 2>/dev/null"
run_cmd_section "Network baseline" "ip -o -4 addr show; ip route; cat /etc/resolv.conf"

if [ -n "$SOURCE_HOST" ] || [ -n "$TARGET_HOST" ]; then
  log_header "Connectivity tests"

  for host in "$SOURCE_HOST" "$TARGET_HOST"; do
    if [ -z "$host" ]; then
      continue
    fi

    {
      echo "--- Host: $host ---"
      ping -c 10 "$host"
    } >> "$REPORT_TXT" 2>&1

    check_rtt_warning "$host"

    for port in 22 1521; do
      if port_check "$host" "$port"; then
        echo "TCP $host:$port reachable" >> "$REPORT_TXT"
      else
        echo "TCP $host:$port not reachable" >> "$REPORT_TXT"
        add_warning "TCP $host:$port not reachable"
      fi
    done
  done
else
  add_warning "SOURCE_HOST and TARGET_HOST were not provided; connectivity tests skipped"
fi

STATUS="success"
if [ ${#FAILED_SECTIONS[@]} -gt 0 ] || [ ${#WARNINGS[@]} -gt 0 ]; then
  STATUS="partial"
fi

{
  echo "{"
  echo "  \"status\": \"$(json_escape "$STATUS")\","
  echo "  \"host\": \"$(json_escape "$HOSTNAME_SHORT")\","
  echo "  \"timestamp\": \"$(json_escape "$TIMESTAMP")\","
  echo "  \"zdm_home\": \"$(json_escape "$ZDM_HOME_EFFECTIVE")\","
  echo "  \"warnings\": ["
  if [ ${#WARNINGS[@]} -gt 0 ]; then
    for i in "${!WARNINGS[@]}"; do
      comma=","
      if [ "$i" -eq "$(( ${#WARNINGS[@]} - 1 ))" ]; then
        comma=""
      fi
      echo "    \"$(json_escape "${WARNINGS[$i]}")\"$comma"
    done
  fi
  echo "  ],"
  echo "  \"failed_sections\": ["
  if [ ${#FAILED_SECTIONS[@]} -gt 0 ]; then
    for i in "${!FAILED_SECTIONS[@]}"; do
      comma=","
      if [ "$i" -eq "$(( ${#FAILED_SECTIONS[@]} - 1 ))" ]; then
        comma=""
      fi
      echo "    \"$(json_escape "${FAILED_SECTIONS[$i]}")\"$comma"
    done
  fi
  echo "  ]"
  echo "}"
} > "$REPORT_JSON"

echo "Text report: $REPORT_TXT"
echo "JSON report: $REPORT_JSON"

exit 0
