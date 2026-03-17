#!/bin/bash
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration

set -u
set -o pipefail

ZDM_HOME_DEFAULT="/mnt/app/zdmhome"
ZDM_USER="${ZDM_USER:-zdmuser}"
SOURCE_HOST="${SOURCE_HOST:-}"
TARGET_HOST="${TARGET_HOST:-}"

CURRENT_USER="$(whoami)"
if [ "$CURRENT_USER" != "${ZDM_USER:-zdmuser}" ]; then
    echo "[ERROR] This script must run as '${ZDM_USER:-zdmuser}'. Currently running as '${CURRENT_USER}'."
    echo "        Switch to the correct user first: sudo su - ${ZDM_USER:-zdmuser}"
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

find_zdm_home() {
  if [ -n "${ZDM_HOME:-}" ] && [ -d "$ZDM_HOME" ]; then
    printf '%s\n' "$ZDM_HOME"
    return
  fi
  if [ -d "$ZDM_HOME_DEFAULT" ]; then
    printf '%s\n' "$ZDM_HOME_DEFAULT"
    return
  fi
  for p in "$HOME/zdmhome" "$HOME/app/zdmhome" "/u01/app/zdmhome" "/opt/oracle/zdm"; do
    if [ -d "$p" ]; then
      printf '%s\n' "$p"
      return
    fi
  done
  find /u01 /u02 /opt /mnt -maxdepth 4 -type d -name 'zdm*home*' 2>/dev/null | head -n 1
}

resolve_zdm_version() {
  local home="$1"

  if [ -f "$home/inventory/ContentsXML/comps.xml" ]; then
    awk -F'"' '/COMP NAME="oracle\.zdm"/ {for (i=1;i<=NF;i++) if ($i ~ /VER=/) {print $(i+1); exit}}' "$home/inventory/ContentsXML/comps.xml" 2>/dev/null
    return
  fi

  if [ -x "$home/OPatch/opatch" ]; then
    "$home/OPatch/opatch" lspatches 2>/dev/null | head -n 3
    return
  fi

  for f in "$home/version.txt" "$home/rhp/zdm/version.txt" "$home/zdmbase/build.txt"; do
    if [ -f "$f" ]; then
      head -n 5 "$f"
      return
    fi
  done

  echo "$home" | sed -n 's#.*zdm\([0-9]\+\).*#\1#p'
}

check_latency() {
  local label="$1"
  local host="$2"

  if [ -z "$host" ]; then
    add_warning "$label host not provided; ping and port checks skipped"
    return 0
  fi

  append_header "Connectivity - $label ping"
  {
    echo "$ ping -c 10 $host"
    ping -c 10 "$host" 2>&1 || add_warning "$label ping failed"
  } >> "$OUT_TXT"

  local avg
  avg="$(ping -c 5 "$host" 2>/dev/null | awk -F'/' '/^rtt|^round-trip/ {print $5}' | tail -n 1)"
  if [ -n "$avg" ]; then
    awk -v a="$avg" 'BEGIN {if (a > 10) exit 1; exit 0}' || add_warning "$label average RTT is greater than 10 ms: $avg"
  fi

  for port in 22 1521; do
    append_header "Connectivity - $label port $port"
    {
      echo "$ timeout 5 bash -lc '</dev/tcp/$host/$port'"
      timeout 5 bash -lc "</dev/tcp/$host/$port" 2>&1 || add_warning "$label port $port not reachable"
    } >> "$OUT_TXT"
  done
}

ZDM_HOME="$(find_zdm_home)"
if [ -z "$ZDM_HOME" ]; then
  add_warning "ZDM_HOME could not be detected"
fi

{
  echo "ZDM Step 2 ZDM Server Discovery"
  echo "Timestamp: $TIMESTAMP"
  echo "Host: $HOSTNAME_SHORT"
  echo "Current User: $CURRENT_USER"
  echo "Detected ZDM_HOME: ${ZDM_HOME:-<empty>}"
} > "$OUT_TXT"

append_command "OS - Host/User/IP" "hostname -f || hostname; whoami; ip -brief addr || ip addr"
append_command "OS - Version" "cat /etc/os-release"
append_command "OS - Disk Space" "df -h"

append_header "OS - Filesystems under 50 GB free"
{
  echo "$ df -BG"
  df -BG | awk 'NR==1 || ($4+0) < 50 {print}'
} >> "$OUT_TXT"

append_header "ZDM Installation"
{
  echo "ZDM_HOME: ${ZDM_HOME:-not found}"
  echo "ZDM Version (best effort):"
  if [ -n "$ZDM_HOME" ]; then
    resolve_zdm_version "$ZDM_HOME"
  else
    echo "not available"
  fi

  if [ -n "$ZDM_HOME" ] && [ -x "$ZDM_HOME/bin/zdmcli" ]; then
    echo "zdmcli exists and is executable: $ZDM_HOME/bin/zdmcli"
  else
    echo "zdmcli not found or not executable"
    add_warning "zdmcli executable not found"
  fi

  if [ -n "$ZDM_HOME" ] && [ -x "$ZDM_HOME/bin/zdmservice" ]; then
    "$ZDM_HOME/bin/zdmservice" status 2>&1 || add_warning "zdmservice status command failed"
  else
    echo "zdmservice not found"
    add_warning "zdmservice not found"
  fi

  if [ -n "$ZDM_HOME" ] && [ -x "$ZDM_HOME/bin/zdmcli" ]; then
    "$ZDM_HOME/bin/zdmcli" query job 2>&1 || add_warning "zdmcli query job failed"
  fi

  if [ -n "$ZDM_HOME" ]; then
    ls -la "$ZDM_HOME/rhp/zdm/template/" 2>&1 || add_warning "ZDM template directory not found"
  fi
} >> "$OUT_TXT"

append_header "Java"
{
  if [ -n "$ZDM_HOME" ] && [ -x "$ZDM_HOME/jdk/bin/java" ]; then
    echo "JAVA_HOME=$ZDM_HOME/jdk"
    "$ZDM_HOME/jdk/bin/java" -version 2>&1
  elif command -v java >/dev/null 2>&1; then
    echo "JAVA_HOME=${JAVA_HOME:-not set}"
    java -version 2>&1
  else
    echo "java not found"
    add_warning "java runtime not found"
  fi
} >> "$OUT_TXT"

append_header "OCI Authentication Configuration"
{
  if [ -f "$HOME/.oci/config" ]; then
    echo "OCI config: $HOME/.oci/config"
    sed -E 's/(fingerprint|tenancy|user|key_file|region).*/\1=***masked***/' "$HOME/.oci/config"
  else
    echo "OCI config file not found"
    add_warning "OCI config file not found"
  fi

  for key in "$HOME/.oci/oci_api_key.pem" "$HOME/.oci/oci_api_key.key" "$HOME/.oci/*.pem"; do
    ls -l $key 2>/dev/null || true
  done
} >> "$OUT_TXT"

append_command "SSH and Credential Files" "ls -la $HOME/.ssh 2>/dev/null || echo ~/.ssh not found; ls -la $HOME | grep -Ei 'cred|pass|wallet|key' || true"
append_command "Network" "ip route; cat /etc/resolv.conf"

check_latency "SOURCE" "$SOURCE_HOST"
check_latency "TARGET" "$TARGET_HOST"

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
  echo "  \"zdm_home\": \"$(json_escape "${ZDM_HOME:-}")\""
  echo "}"
} > "$OUT_JSON"

echo "ZDM server discovery text report: $OUT_TXT"
echo "ZDM server discovery json report: $OUT_JSON"

exit 0
