#!/bin/bash
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration

set -u
set -o pipefail

DISCOVERY_TYPE="server"
HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_TXT="./zdm_${DISCOVERY_TYPE}_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
REPORT_JSON="./zdm_${DISCOVERY_TYPE}_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"
ZDM_USER="${ZDM_USER:-zdmuser}"
SOURCE_HOST="${SOURCE_HOST:-}"
TARGET_HOST="${TARGET_HOST:-}"

WARNINGS=()
ERRORS=()

CURRENT_USER="$(whoami)"
if [ "$CURRENT_USER" != "${ZDM_USER:-zdmuser}" ]; then
    echo "[ERROR] This script must run as '${ZDM_USER:-zdmuser}'. Currently running as '${CURRENT_USER}'."
    echo "        Switch to the correct user first: sudo su - ${ZDM_USER:-zdmuser}"
    exit 1
fi

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\r//g; :a;N;$!ba;s/\n/\\n/g'
}

append_report() {
  printf '%s\n' "$1" >> "$REPORT_TXT"
}

warn() {
  WARNINGS+=("$1")
  append_report "[WARN] $1"
}

section() {
  append_report ""
  append_report "==================== $1 ===================="
}

run_cmd() {
  local title="$1"
  local cmd="$2"
  section "$title"
  local out
  out="$(bash -lc "$cmd" 2>&1)"
  if [ $? -ne 0 ]; then
    warn "$title command failed"
  fi
  append_report "$out"
}

detect_zdm_home() {
  local candidates=()
  [ -n "${ZDM_HOME:-}" ] && candidates+=("$ZDM_HOME")
  [ -n "${RHP_HOME:-}" ] && candidates+=("$RHP_HOME")
  candidates+=("$HOME/zdmhome" "/u01/app/zdmhome" "/u02/app/zdmhome" "/mnt/app/zdmhome" "/opt/oracle/zdmhome")

  for p in "${candidates[@]}"; do
    if [ -d "$p" ] && [ -x "$p/bin/zdmcli" ]; then
      echo "$p"
      return 0
    fi
  done

  find "$HOME" /u01 /u02 /mnt /opt -maxdepth 4 -type f -name zdmcli 2>/dev/null | head -n 1 | sed 's#/bin/zdmcli##'
}

detect_zdm_version() {
  local zhome="$1"
  local v=""

  if [ -f "$zhome/inventory/ContentsXML/comps.xml" ]; then
    v="$(grep -Eo '([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)' "$zhome/inventory/ContentsXML/comps.xml" | head -n 1)"
  fi

  if [ -z "$v" ] && [ -x "$zhome/OPatch/opatch" ]; then
    v="$("$zhome/OPatch/opatch" lspatches 2>/dev/null | grep -Eo '([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)' | head -n 1)"
  fi

  if [ -z "$v" ]; then
    v="$(grep -Eor '([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)' "$zhome"/version.txt "$zhome"/rhp/zdmbase/* 2>/dev/null | head -n 1)"
  fi

  if [ -z "$v" ]; then
    v="$(echo "$zhome" | grep -Eo '[0-9]{2}\.[0-9]' | head -n 1)"
  fi

  echo "$v"
}

connectivity_checks() {
  local host="$1"
  [ -z "$host" ] && return 0

  section "Connectivity to $host"

  local ping_out
  ping_out="$(ping -c 10 "$host" 2>&1)"
  append_report "$ping_out"
  if [ $? -ne 0 ]; then
    warn "Ping to $host failed"
  fi

  local avg
  avg="$(echo "$ping_out" | awk -F'/' '/^rtt|^round-trip/ {print $5}' | head -n 1)"
  if [ -n "$avg" ]; then
    append_report "Average RTT to $host: ${avg} ms"
    awk 'BEGIN{if ('"${avg:-0}"' > 10) exit 1; else exit 0}' >/dev/null 2>&1
    if [ $? -ne 0 ]; then
      warn "Average RTT to $host is greater than 10 ms"
    fi
  fi

  for p in 22 1521; do
    if timeout 5 bash -lc "</dev/tcp/$host/$p" 2>/dev/null; then
      append_report "TCP port $p on $host: reachable"
    else
      warn "TCP port $p on $host: unreachable"
    fi
  done
}

write_json() {
  local status="success"
  if [ ${#WARNINGS[@]} -gt 0 ] || [ ${#ERRORS[@]} -gt 0 ]; then
    status="partial"
  fi

  {
    echo "{"
    echo "  \"status\": \"$(json_escape "$status")\"," 
    echo "  \"type\": \"$(json_escape "$DISCOVERY_TYPE")\"," 
    echo "  \"host\": \"$(json_escape "$HOSTNAME_SHORT")\"," 
    echo "  \"timestamp\": \"$(json_escape "$TIMESTAMP")\"," 
    echo "  \"zdm\": {"
    echo "    \"user\": \"$(json_escape "$ZDM_USER")\"," 
    echo "    \"zdm_home\": \"$(json_escape "${ZDM_HOME_DETECTED:-}")\"," 
    echo "    \"zdm_version\": \"$(json_escape "${ZDM_VERSION_DETECTED:-}")\""
    echo "  },"
    echo "  \"warnings\": ["
    if [ ${#WARNINGS[@]} -gt 0 ]; then
      for i in "${!WARNINGS[@]}"; do
        comma=","
        [ "$i" -eq "$((${#WARNINGS[@]} - 1))" ] && comma=""
        echo "    \"$(json_escape "${WARNINGS[$i]}")\"${comma}"
      done
    fi
    echo "  ],"
    echo "  \"errors\": ["
    if [ ${#ERRORS[@]} -gt 0 ]; then
      for i in "${!ERRORS[@]}"; do
        comma=","
        [ "$i" -eq "$((${#ERRORS[@]} - 1))" ] && comma=""
        echo "    \"$(json_escape "${ERRORS[$i]}")\"${comma}"
      done
    fi
    echo "  ]"
    echo "}"
  } > "$REPORT_JSON"
}

append_report "# ZDM Server Discovery Report"
append_report "Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
append_report "Host: $HOSTNAME_SHORT"
append_report "Running User: $CURRENT_USER"
append_report "Read-only mode: enabled"

run_cmd "OS: Host, User, OS" "hostname -f 2>/dev/null; whoami; cat /etc/os-release 2>/dev/null"
run_cmd "Disk Space" "df -BG"

section "Disk Space Warning Check (< 50GB free)"
while IFS= read -r line; do
  avail="$(echo "$line" | awk '{print $4}' | tr -d 'G')"
  mp="$(echo "$line" | awk '{print $6}')"
  if echo "$avail" | grep -Eq '^[0-9]+$'; then
    if [ "$avail" -lt 50 ]; then
      warn "Filesystem $mp has less than 50GB free ($avail GB)"
    fi
  fi
done < <(df -BG | awk 'NR>1')

ZDM_HOME_DETECTED="$(detect_zdm_home)"
if [ -z "$ZDM_HOME_DETECTED" ]; then
  warn "ZDM_HOME could not be auto-detected"
else
  ZDM_VERSION_DETECTED="$(detect_zdm_version "$ZDM_HOME_DETECTED")"
fi

section "ZDM Installation"
append_report "ZDM_HOME=$ZDM_HOME_DETECTED"
append_report "ZDM_VERSION=$ZDM_VERSION_DETECTED"

run_cmd "zdmcli existence" "[ -n '$ZDM_HOME_DETECTED' ] && ls -l '$ZDM_HOME_DETECTED/bin/zdmcli' || echo 'zdmcli not found in detected home'"
run_cmd "zdmservice status" "[ -n '$ZDM_HOME_DETECTED' ] && '$ZDM_HOME_DETECTED/bin/zdmservice' status 2>/dev/null || echo 'zdmservice unavailable'"
run_cmd "zdmcli query job" "[ -n '$ZDM_HOME_DETECTED' ] && '$ZDM_HOME_DETECTED/bin/zdmcli' query job 2>/dev/null || echo 'zdmcli query job unavailable'"
run_cmd "Response templates" "[ -n '$ZDM_HOME_DETECTED' ] && ls -l '$ZDM_HOME_DETECTED/rhp/zdm/template/' 2>/dev/null || true"

run_cmd "Java version" "if [ -n '$ZDM_HOME_DETECTED' ] && [ -x '$ZDM_HOME_DETECTED/jdk/bin/java' ]; then '$ZDM_HOME_DETECTED/jdk/bin/java' -version; else java -version 2>&1; fi"
run_cmd "OCI config (masked)" "for f in ~/.oci/config; do if [ -f \"$f\" ]; then echo \"[CONFIG] $f\"; sed -E 's/(fingerprint|user|tenancy|region|key_file)[[:space:]]*=.*/\\1=***masked***/g' \"$f\"; fi; done"
run_cmd "OCI API key permissions" "ls -l ~/.oci/*.pem ~/.oci/*.key 2>/dev/null || true"
run_cmd "SSH and credentials in home" "ls -la ~/.ssh 2>/dev/null; ls -la ~ | egrep -i 'cred|pass|wallet|secret' || true"
run_cmd "Network details" "ip -br addr 2>/dev/null || ip addr 2>/dev/null; ip route 2>/dev/null; cat /etc/resolv.conf 2>/dev/null"

if [ -n "$SOURCE_HOST" ] || [ -n "$TARGET_HOST" ]; then
  section "Connectivity Tests"
  [ -n "$SOURCE_HOST" ] && connectivity_checks "$SOURCE_HOST" || append_report "SOURCE_HOST not set; skipping."
  [ -n "$TARGET_HOST" ] && connectivity_checks "$TARGET_HOST" || append_report "TARGET_HOST not set; skipping."
else
  section "Connectivity Tests"
  append_report "SOURCE_HOST/TARGET_HOST not set; skipping connectivity checks."
fi

if [ ${#WARNINGS[@]} -gt 0 ]; then
  section "Warnings"
  for w in "${WARNINGS[@]}"; do
    append_report "- $w"
  done
fi

write_json

echo "Server discovery report: $REPORT_TXT"
echo "Server discovery summary: $REPORT_JSON"

exit 0
