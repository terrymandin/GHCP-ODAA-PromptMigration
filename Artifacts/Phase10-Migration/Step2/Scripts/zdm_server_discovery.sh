#!/bin/bash
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration

set -u
set -o pipefail

ZDM_USER="${ZDM_USER:-zdmuser}"
ZDM_HOME_HINT="${ZDM_HOME:-/mnt/app/zdmhome}"
SOURCE_HOST="${SOURCE_HOST:-}"
TARGET_HOST="${TARGET_HOST:-}"

CURRENT_USER="$(whoami)"
if [ "$CURRENT_USER" != "${ZDM_USER:-zdmuser}" ]; then
    echo "[ERROR] This script must run as '${ZDM_USER:-zdmuser}'. Currently running as '${CURRENT_USER}'."
    echo "        Switch to the correct user first: sudo su - ${ZDM_USER:-zdmuser}"
    exit 1
fi

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname)"
TEXT_OUT="./zdm_server_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
JSON_OUT="./zdm_server_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

WARNINGS=()
PARTIAL=0
RESOLVED_ZDM_HOME=""

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\r//g; :a;N;$!ba;s/\n/\\n/g'
}

add_warning() {
  WARNINGS+=("$1")
  PARTIAL=1
}

log_section() {
  printf '\n===== %s =====\n' "$1" | tee -a "$TEXT_OUT"
}

run_cmd() {
  local title="$1"
  local cmd="$2"
  log_section "$title"
  printf '$ %s\n' "$cmd" | tee -a "$TEXT_OUT"
  local output
  output="$(bash -lc "$cmd" 2>&1)"
  local rc=$?
  printf '%s\n' "$output" | tee -a "$TEXT_OUT"
  if [ $rc -ne 0 ]; then
    add_warning "$title failed (rc=$rc)"
  fi
}

find_zdm_home() {
  local candidate=""

  if [ -n "${ZDM_HOME_HINT:-}" ] && [ -d "$ZDM_HOME_HINT" ]; then
    candidate="$ZDM_HOME_HINT"
  fi

  if [ -z "$candidate" ] && [ -n "${ZDM_HOME:-}" ] && [ -d "$ZDM_HOME" ]; then
    candidate="$ZDM_HOME"
  fi

  if [ -z "$candidate" ]; then
    for p in /u01/app /u02/app /mnt/app /opt /home; do
      if [ -d "$p" ]; then
        candidate="$(find "$p" -maxdepth 4 -type f -name zdmcli 2>/dev/null | head -n1 | sed 's#/rhp/bin/zdmcli##')"
        [ -n "$candidate" ] && break
      fi
    done
  fi

  RESOLVED_ZDM_HOME="$candidate"
  if [ -z "$RESOLVED_ZDM_HOME" ]; then
    add_warning "Unable to auto-detect ZDM_HOME"
  fi
}

collect_disk_warning() {
  log_section "OS - Disk Space"
  df -Pk | tee -a "$TEXT_OUT"
  while read -r fs kb used avail pct mountp; do
    [ "$fs" = "Filesystem" ] && continue
    if [ "$avail" -lt 52428800 ]; then
      add_warning "Filesystem $mountp has less than 50 GB free"
    fi
  done < <(df -Pk)
}

check_connectivity() {
  local label="$1"
  local host="$2"

  if [ -z "$host" ]; then
    log_section "Connectivity - $label"
    echo "Skipped: $label host not provided" | tee -a "$TEXT_OUT"
    return
  fi

  log_section "Connectivity - $label ping"
  local ping_out avg_rtt
  ping_out="$(ping -c 10 "$host" 2>&1)"
  echo "$ping_out" | tee -a "$TEXT_OUT"
  if ! echo "$ping_out" | grep -q "min/avg/max"; then
    add_warning "$label ping failed"
  else
    avg_rtt="$(echo "$ping_out" | awk -F'/' '/min\/avg\/max/ {print $5}')"
    if [ -n "$avg_rtt" ]; then
      awk -v avg="$avg_rtt" 'BEGIN {if (avg > 10.0) exit 1; exit 0}' || add_warning "$label average RTT is above 10 ms ($avg_rtt ms)"
    fi
  fi

  log_section "Connectivity - $label ports"
  for port in 22 1521; do
    if bash -lc "timeout 3 bash -c '</dev/tcp/$host/$port'" 2>/dev/null; then
      echo "Port $port on $host: open" | tee -a "$TEXT_OUT"
    else
      echo "Port $port on $host: closed/unreachable" | tee -a "$TEXT_OUT"
      add_warning "$label port $port is closed or unreachable"
    fi
  done
}

: > "$TEXT_OUT"

log_section "Script Metadata"
{
  echo "Timestamp: $TIMESTAMP"
  echo "Host: $HOSTNAME_SHORT"
  echo "Run user: $CURRENT_USER"
} | tee -a "$TEXT_OUT"

run_cmd "OS - Hostname/User/OS Version" "hostname; whoami; cat /etc/os-release 2>/dev/null || uname -a"
collect_disk_warning

find_zdm_home
log_section "ZDM Installation - Home Detection"
echo "ZDM_HOME resolved: ${RESOLVED_ZDM_HOME:-UNRESOLVED}" | tee -a "$TEXT_OUT"

run_cmd "ZDM Installation - Version Sources" "if [ -n '$RESOLVED_ZDM_HOME' ]; then find '$RESOLVED_ZDM_HOME' -maxdepth 4 -type f \( -name 'inventory.xml' -o -name 'version.txt' -o -name '*build*' \) 2>/dev/null | head -n 20; fi"
run_cmd "ZDM Installation - Oracle Inventory XML" "if [ -n '$RESOLVED_ZDM_HOME' ]; then grep -Rin 'zdm\|version' '$RESOLVED_ZDM_HOME'/*inventory* 2>/dev/null | head -n 20; fi"
run_cmd "ZDM Installation - OPatch lspatches" "if [ -n '$RESOLVED_ZDM_HOME' ] && [ -x '$RESOLVED_ZDM_HOME/OPatch/opatch' ]; then '$RESOLVED_ZDM_HOME/OPatch/opatch' lspatches; else echo 'OPatch not found'; fi"
run_cmd "ZDM Installation - zdmcli executable" "if [ -n '$RESOLVED_ZDM_HOME' ] && [ -x '$RESOLVED_ZDM_HOME/rhp/bin/zdmcli' ]; then ls -l '$RESOLVED_ZDM_HOME/rhp/bin/zdmcli'; else command -v zdmcli || echo 'zdmcli not found'; fi"
run_cmd "ZDM Service Status" "if [ -n '$RESOLVED_ZDM_HOME' ] && [ -x '$RESOLVED_ZDM_HOME/rhp/bin/zdmservice' ]; then '$RESOLVED_ZDM_HOME/rhp/bin/zdmservice' status; else zdmservice status 2>/dev/null || echo 'zdmservice command not found'; fi"
run_cmd "ZDM Active Jobs" "if [ -n '$RESOLVED_ZDM_HOME' ] && [ -x '$RESOLVED_ZDM_HOME/rhp/bin/zdmcli' ]; then '$RESOLVED_ZDM_HOME/rhp/bin/zdmcli' query job; else zdmcli query job 2>/dev/null || echo 'zdmcli command not found'; fi"
run_cmd "ZDM Templates" "if [ -n '$RESOLVED_ZDM_HOME' ]; then ls -la '$RESOLVED_ZDM_HOME/rhp/zdm/template/' 2>/dev/null || true; fi"

run_cmd "Java - Version and JAVA_HOME" "if [ -n '$RESOLVED_ZDM_HOME' ] && [ -x '$RESOLVED_ZDM_HOME/jdk/bin/java' ]; then '$RESOLVED_ZDM_HOME/jdk/bin/java' -version; echo 'JAVA_HOME=$RESOLVED_ZDM_HOME/jdk'; else java -version; echo \"JAVA_HOME=${JAVA_HOME:-unset}\"; fi"

run_cmd "OCI Authentication Config" "for f in ~/.oci/config /home/$CURRENT_USER/.oci/config; do if [ -f \"$f\" ]; then echo \"--- $f ---\"; sed -E 's/(key_file|fingerprint|tenancy|user)=.*/\\1=<masked>/g' \"$f\"; fi; done"
run_cmd "OCI API Key Permissions" "find ~/.oci -maxdepth 2 -type f -name '*.pem' -exec ls -l {} + 2>/dev/null || true"
run_cmd "SSH and Credential Files" "ls -la ~/.ssh 2>/dev/null || true; find ~ -maxdepth 2 -type f \( -name '*cred*' -o -name '*pass*' -o -name '*.pwd' \) 2>/dev/null || true"

run_cmd "Network - IP, Route, DNS" "hostname -I 2>/dev/null || true; ip route 2>/dev/null || route -n 2>/dev/null || true; cat /etc/resolv.conf 2>/dev/null || true"

check_connectivity "SOURCE" "$SOURCE_HOST"
check_connectivity "TARGET" "$TARGET_HOST"

STATUS="success"
if [ "$PARTIAL" -ne 0 ]; then
  STATUS="partial"
fi

{
  echo "{" 
  echo "  \"status\": \"$(json_escape "$STATUS")\"," 
  echo "  \"host\": \"$(json_escape "$HOSTNAME_SHORT")\"," 
  echo "  \"timestamp\": \"$(json_escape "$TIMESTAMP")\"," 
  echo "  \"zdm_home\": \"$(json_escape "${RESOLVED_ZDM_HOME:-}")\"," 
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
  echo "  ]"
  echo "}"
} > "$JSON_OUT"

echo "Server discovery text report: $TEXT_OUT"
echo "Server discovery JSON report: $JSON_OUT"

if [ "$STATUS" = "partial" ]; then
  exit 1
fi

exit 0
