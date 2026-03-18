#!/bin/bash

set -u

# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration

SOURCE_HOST="${SOURCE_HOST:-10.200.1.12}"
TARGET_HOST="${TARGET_HOST:-10.200.0.250}"
ZDM_HOME="${ZDM_HOME:-/mnt/app/zdmhome}"
ZDM_USER="${ZDM_USER:-zdmuser}"

WARNINGS_NL=""
warning_count=0

add_warning() {
  local message="$1"
  warning_count=$((warning_count + 1))
  WARNINGS_NL+="$message"$'\n'
  echo "[WARN] $message" >&2
}

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

render_warning_array_json() {
  if [ "$warning_count" -eq 0 ]; then
    echo "[]"
    return 0
  fi

  local first=1
  local out="["
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    if [ $first -eq 0 ]; then
      out+=","
    fi
    out+="\"$(json_escape "$line")\""
    first=0
  done <<< "$WARNINGS_NL"
  out+="]"
  echo "$out"
}

CURRENT_USER="$(whoami)"
if [ "$CURRENT_USER" != "${ZDM_USER:-zdmuser}" ]; then
      echo "[ERROR] This script must run as '${ZDM_USER:-zdmuser}'. Currently running as '${CURRENT_USER}'."
      echo "        Switch to the correct user first: sudo su - ${ZDM_USER:-zdmuser}"
      exit 1
fi

hostname_short="$(hostname 2>/dev/null || echo unknown)"
timestamp="$(date +%Y%m%d-%H%M%S)"
iso_timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

raw_out="./zdm_server_discovery_${hostname_short}_${timestamp}.txt"
json_out="./zdm_server_discovery_${hostname_short}_${timestamp}.json"

system_hostname="$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo unknown)"
os_release="$(grep -E '^(PRETTY_NAME)=' /etc/os-release 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '"' || uname -s)"
kernel_info="$(uname -r 2>/dev/null || echo unknown)"
uptime_info="$(uptime -p 2>/dev/null || uptime 2>/dev/null || echo unknown)"
home_dir="${HOME:-$(getent passwd "$CURRENT_USER" | cut -d: -f6)}"

if [ ! -d "$ZDM_HOME" ]; then
  add_warning "ZDM_HOME does not exist: $ZDM_HOME"
fi

zdmcli_path=""
if [ -x "$ZDM_HOME/bin/zdmcli" ]; then
  zdmcli_path="$ZDM_HOME/bin/zdmcli"
else
  zdmcli_path="$(command -v zdmcli 2>/dev/null || true)"
fi
if [ -z "$zdmcli_path" ]; then
  add_warning "zdmcli executable not found in ZDM_HOME/bin or PATH"
fi

zdmcli_version=""
if [ -n "$zdmcli_path" ]; then
  zdmcli_version="$("$zdmcli_path" -build 2>&1 || "$zdmcli_path" -v 2>&1 || true)"
fi

java_home_effective="${JAVA_HOME:-}"
java_version=""
if [ -x "$ZDM_HOME/jdk/bin/java" ]; then
  java_version="$($ZDM_HOME/jdk/bin/java -version 2>&1 | head -n2)"
  [ -z "$java_home_effective" ] && java_home_effective="$ZDM_HOME/jdk"
elif command -v java >/dev/null 2>&1; then
  java_version="$(java -version 2>&1 | head -n2)"
else
  add_warning "Java executable not found"
fi

disk_summary="$(df -h 2>/dev/null || true)"
memory_summary="$(free -h 2>/dev/null || vm_stat 2>/dev/null || true)"

oci_config_path="$home_dir/.oci/config"
oci_key_candidates="$(find "$home_dir/.oci" -maxdepth 2 -type f \( -name '*.pem' -o -name '*.key' \) 2>/dev/null || true)"
if [ ! -f "$oci_config_path" ]; then
  add_warning "OCI config file not found at $oci_config_path"
fi

connectivity_report=""
check_endpoint() {
  local endpoint_name="$1"
  local endpoint_host="$2"

  if [ -z "$endpoint_host" ]; then
    echo "$endpoint_name: not configured"
    return 0
  fi

  local ping_out=""
  local port22=""
  local port1521=""

  ping_out="$(ping -c 1 "$endpoint_host" 2>&1 || true)"

  if command -v nc >/dev/null 2>&1; then
    port22="$(nc -zv "$endpoint_host" 22 2>&1 || true)"
    port1521="$(nc -zv "$endpoint_host" 1521 2>&1 || true)"
  else
    port22="nc not available"
    port1521="nc not available"
  fi

  echo "$endpoint_name host: $endpoint_host"
  echo "$endpoint_name ping: $ping_out"
  echo "$endpoint_name tcp/22: $port22"
  echo "$endpoint_name tcp/1521: $port1521"
}

connectivity_report+="$(check_endpoint SOURCE "$SOURCE_HOST")"$'\n'
connectivity_report+="$(check_endpoint TARGET "$TARGET_HOST")"$'\n'

network_summary=""
network_summary+="$(ip -brief addr 2>/dev/null || ifconfig 2>/dev/null || true)"$'\n'
network_summary+="$(ip route 2>/dev/null || netstat -rn 2>/dev/null || true)"$'\n'
network_summary+="$(cat /etc/resolv.conf 2>/dev/null || true)"$'\n'

{
  echo "ZDM Step2 Server Discovery"
  echo "Timestamp: $iso_timestamp"
  echo "Host: $system_hostname"
  echo "Current User: $CURRENT_USER"
  echo "Home: $home_dir"
  echo "Configured SOURCE_HOST: $SOURCE_HOST"
  echo "Configured TARGET_HOST: $TARGET_HOST"
  echo "Configured ZDM_HOME: $ZDM_HOME"
  echo
  echo "=== Local System ==="
  echo "OS: $os_release"
  echo "Kernel: $kernel_info"
  echo "Uptime: $uptime_info"
  echo
  echo "=== ZDM Installation ==="
  echo "zdmcli path: ${zdmcli_path:-<not found>}"
  echo "zdmcli version: ${zdmcli_version:-<unavailable>}"
  ls -ld "$ZDM_HOME" 2>/dev/null || true
  ls -ld "$ZDM_HOME/bin" 2>/dev/null || true
  echo
  echo "=== Capacity ==="
  echo "$disk_summary"
  echo
  echo "$memory_summary"
  echo
  echo "=== Java ==="
  echo "JAVA_HOME: ${java_home_effective:-<unset>}"
  echo "$java_version"
  echo
  echo "=== OCI Authentication Metadata ==="
  echo "OCI config: $oci_config_path"
  if [ -f "$oci_config_path" ]; then
    sed -E 's/(fingerprint|key_file|tenancy|user)=.*/\1=<masked>/g' "$oci_config_path"
  else
    echo "<not found>"
  fi
  echo "OCI key files:"
  echo "${oci_key_candidates:-<none>}"
  echo
  echo "=== SSH and Credential Inventory ==="
  ls -la "$home_dir/.ssh" 2>/dev/null || echo "<no ~/.ssh directory>"
  echo
  echo "=== Network Context ==="
  echo "$network_summary"
  echo
  echo "=== Optional Connectivity Tests ==="
  echo "$connectivity_report"
  echo
  echo "=== Warnings ==="
  if [ "$warning_count" -eq 0 ]; then
    echo "none"
  else
    printf '%s' "$WARNINGS_NL"
  fi
} > "$raw_out"

status="success"
if [ "$warning_count" -gt 0 ]; then
  status="partial"
fi

{
  echo "{"
  echo "  \"status\": \"$status\"," 
  echo "  \"warnings\": $(render_warning_array_json),"
  echo "  \"timestamp\": \"$(json_escape "$iso_timestamp")\"," 
  echo "  \"host\": \"$(json_escape "$system_hostname")\"," 
  echo "  \"discovery_type\": \"server\"," 
  echo "  \"zdm_user\": \"$(json_escape "$CURRENT_USER")\"," 
  echo "  \"zdm_home\": \"$(json_escape "$ZDM_HOME")\"," 
  echo "  \"zdmcli_path\": \"$(json_escape "$zdmcli_path")\"," 
  echo "  \"source_host\": \"$(json_escape "$SOURCE_HOST")\"," 
  echo "  \"target_host\": \"$(json_escape "$TARGET_HOST")\"," 
  echo "  \"raw_output_file\": \"$(json_escape "$raw_out")\""
  echo "}"
} > "$json_out"

echo "[INFO] Server discovery raw output: $raw_out"
echo "[INFO] Server discovery JSON summary: $json_out"
