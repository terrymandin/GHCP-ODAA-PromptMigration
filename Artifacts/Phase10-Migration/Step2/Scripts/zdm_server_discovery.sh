#!/bin/bash
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration

set -u
set -o pipefail

SOURCE_HOST="${SOURCE_HOST:-10.200.1.12}"
TARGET_HOST="${TARGET_HOST:-10.200.0.250}"
ZDM_USER="${ZDM_USER:-zdmuser}"
ZDM_HOME_DEFAULT="/mnt/app/zdmhome"

CURRENT_USER="$(whoami)"
if [ "$CURRENT_USER" != "$ZDM_USER" ]; then
  echo "[ERROR] This script must run as '${ZDM_USER}'. Currently running as '${CURRENT_USER}'."
  echo "        Switch to the correct user first: sudo su - ${ZDM_USER}"
  exit 1
fi

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)"
OUT_TXT="./zdm_server_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
OUT_JSON="./zdm_server_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

warnings=()
status="success"

add_warning() {
  warnings+=("$1")
  status="partial"
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\r//g; :a;N;$!ba;s/\n/\\n/g'
}

append_header() {
  local title="$1"
  {
    echo
    echo "================================================================================"
    echo "$title"
    echo "================================================================================"
  } >> "$OUT_TXT"
}

append_command() {
  local title="$1"
  local cmd="$2"
  append_header "$title"
  {
    echo "$ $cmd"
    bash -lc "$cmd" 2>&1 || {
      local rc=$?
      echo "[WARN] Command failed with rc=$rc"
      add_warning "$title command failed"
    }
  } >> "$OUT_TXT"
}

detect_zdm_home() {
  if [ -n "${ZDM_HOME:-}" ] && [ -d "${ZDM_HOME}" ]; then
    printf '%s\n' "${ZDM_HOME}"
    return
  fi
  if [ -d "$ZDM_HOME_DEFAULT" ]; then
    printf '%s\n' "$ZDM_HOME_DEFAULT"
    return
  fi
  for p in /u01/app/zdmhome /opt/zdmhome /app/zdmhome /u01/zdmhome; do
    if [ -d "$p" ]; then
      printf '%s\n' "$p"
      return
    fi
  done
  printf '%s\n' ""
}

ZDM_HOME_EFFECTIVE="$(detect_zdm_home)"
if [ -z "$ZDM_HOME_EFFECTIVE" ]; then
  add_warning "ZDM_HOME could not be detected"
fi

extract_zdm_version() {
  local home="$1"
  local v=""

  if [ -n "$home" ] && [ -f "$home/inventory/ContentsXML/comps.xml" ]; then
    v="$(grep -i 'zero.*downtime\|zdm' "$home/inventory/ContentsXML/comps.xml" 2>/dev/null | head -n 1 | sed -E 's/.*VER=\"([^\"]+)\".*/\1/')"
  fi
  if [ -z "$v" ] && [ -n "$home" ] && [ -x "$home/OPatch/opatch" ]; then
    v="$($home/OPatch/opatch lspatches 2>/dev/null | grep -Eo '[0-9]{2}\.[0-9]+' | head -n 1)"
  fi
  if [ -z "$v" ] && [ -n "$home" ] && [ -f "$home/version.txt" ]; then
    v="$(head -n 1 "$home/version.txt" 2>/dev/null)"
  fi
  if [ -z "$v" ] && [ -n "$home" ]; then
    v="$(echo "$home" | grep -Eo '[0-9]{2}\.[0-9]+' | head -n 1)"
  fi
  if [ -z "$v" ]; then
    v="UNDETERMINED"
  fi
  printf '%s\n' "$v"
}

ZDM_VERSION="$(extract_zdm_version "$ZDM_HOME_EFFECTIVE")"

{
  echo "ZDM Step 2 Server Discovery"
  echo "Timestamp: $TIMESTAMP"
  echo "Host: $HOSTNAME_SHORT"
  echo "Current User: $CURRENT_USER"
  echo "Detected ZDM_HOME: ${ZDM_HOME_EFFECTIVE:-<empty>}"
  echo "Detected ZDM Version: ${ZDM_VERSION}"
} > "$OUT_TXT"

append_command "OS - Host and Version" "hostname -f || hostname; cat /etc/os-release"
append_command "OS - Disk Space" "df -h"
append_command "OS - Users and Context" "whoami; id; echo HOME=$HOME"
append_command "OS - Network" "ip route; cat /etc/resolv.conf; ip -brief addr || ip addr"

append_command "ZDM Installation" "echo ZDM_HOME=$ZDM_HOME_EFFECTIVE; [ -x \"$ZDM_HOME_EFFECTIVE/bin/zdmcli\" ] && echo zdmcli=present || echo zdmcli=missing; [ -x \"$ZDM_HOME_EFFECTIVE/bin/zdmservice\" ] && \"$ZDM_HOME_EFFECTIVE/bin/zdmservice\" status || echo zdmservice not available"
append_command "ZDM Jobs and Templates" "[ -x \"$ZDM_HOME_EFFECTIVE/bin/zdmcli\" ] && \"$ZDM_HOME_EFFECTIVE/bin/zdmcli\" query job -all || echo zdmcli query skipped; [ -d \"$ZDM_HOME_EFFECTIVE/rhp/zdm/template\" ] && ls -la \"$ZDM_HOME_EFFECTIVE/rhp/zdm/template\" || echo template dir not found"

append_command "Java" "[ -x \"$ZDM_HOME_EFFECTIVE/jdk/bin/java\" ] && \"$ZDM_HOME_EFFECTIVE/jdk/bin/java\" -version || java -version"

append_command "OCI Authentication" "[ -f ~/.oci/config ] && { echo '[INFO] ~/.oci/config found'; sed -E 's/(fingerprint|tenancy|user|key_file|region).*/\\1=***masked***/' ~/.oci/config; } || echo ~/.oci/config not found"
append_command "SSH and Credentials" "ls -la ~/.ssh 2>/dev/null || echo ~/.ssh not found; ls -la ~/creds 2>/dev/null || echo ~/creds not found"

if [ -n "$SOURCE_HOST" ]; then
  append_command "Connectivity - SOURCE ping" "ping -c 10 $SOURCE_HOST"
  append_command "Connectivity - SOURCE ports" "timeout 5 bash -lc '</dev/tcp/$SOURCE_HOST/22' && echo 'SOURCE 22 open' || echo 'SOURCE 22 closed'; timeout 5 bash -lc '</dev/tcp/$SOURCE_HOST/1521' && echo 'SOURCE 1521 open' || echo 'SOURCE 1521 closed'"
fi

if [ -n "$TARGET_HOST" ]; then
  append_command "Connectivity - TARGET ping" "ping -c 10 $TARGET_HOST"
  append_command "Connectivity - TARGET ports" "timeout 5 bash -lc '</dev/tcp/$TARGET_HOST/22' && echo 'TARGET 22 open' || echo 'TARGET 22 closed'; timeout 5 bash -lc '</dev/tcp/$TARGET_HOST/1521' && echo 'TARGET 1521 open' || echo 'TARGET 1521 closed'"
fi

free_low_count="$(df -BG --output=avail,target 2>/dev/null | awk 'NR>1 {gsub(/G/,"",$1); if ($1+0 < 50) c++} END {print c+0}')"
if [ "${free_low_count:-0}" -gt 0 ]; then
  add_warning "One or more filesystems have less than 50GB free"
fi

{
  echo "{"
  echo "  \"status\": \"$(json_escape "$status")\"," 
  echo "  \"warnings\": ["
  if [ ${#warnings[@]} -gt 0 ]; then
    for i in "${!warnings[@]}"; do
      comma=","
      if [ "$i" -eq "$(( ${#warnings[@]} - 1 ))" ]; then
        comma=""
      fi
      echo "    \"$(json_escape "${warnings[$i]}")\"$comma"
    done
  fi
  echo "  ],"
  echo "  \"host\": \"$(json_escape "$HOSTNAME_SHORT")\"," 
  echo "  \"timestamp\": \"$(json_escape "$TIMESTAMP")\"," 
  echo "  \"zdm_home\": \"$(json_escape "${ZDM_HOME_EFFECTIVE:-}")\"," 
  echo "  \"zdm_version\": \"$(json_escape "$ZDM_VERSION")\""
  echo "}"
} > "$OUT_JSON"

echo "Server discovery text report: $OUT_TXT"
echo "Server discovery json report: $OUT_JSON"

exit 0
