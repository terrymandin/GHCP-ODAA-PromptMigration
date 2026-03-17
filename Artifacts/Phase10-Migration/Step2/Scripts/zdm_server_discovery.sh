#!/usr/bin/env bash

set -u
set -o pipefail

# Rendered from zdm-env.md at generation time. Runtime does not depend on zdm-env.md.
ZDM_HOME="${ZDM_HOME:-/mnt/app/zdmhome}"
REQUIRED_RUN_USER="${REQUIRED_RUN_USER:-zdmuser}"
SOURCE_HOST="${SOURCE_HOST:-10.200.1.12}"
TARGET_HOST="${TARGET_HOST:-10.200.0.250}"
SOURCE_SSH_USER="${SOURCE_SSH_USER:-azureuser}"
TARGET_SSH_USER="${TARGET_SSH_USER:-opc}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEP2_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DISCOVERY_DIR="$STEP2_DIR/Discovery/server"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
RAW_OUT="$DISCOVERY_DIR/server-discovery-$TIMESTAMP.raw.txt"
REPORT_MD="$DISCOVERY_DIR/server-discovery-$TIMESTAMP.md"
REPORT_JSON="$DISCOVERY_DIR/server-discovery-$TIMESTAMP.json"

mkdir -p "$DISCOVERY_DIR"

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\r//g; :a;N;$!ba;s/\n/\\n/g'
}

CURRENT_USER="$(whoami)"
HOSTNAME_VAL="$(hostname 2>/dev/null || echo unknown)"
OS_PRETTY="$(grep -m1 '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"')"
KERNEL_VAL="$(uname -sr 2>/dev/null || echo unknown)"
UPTIME_VAL="$(uptime -p 2>/dev/null || uptime 2>/dev/null || echo unknown)"
ZDM_HOME_EXISTS="no"
ZDM_HOME_PERMS="unknown"
ZDMCLI_PATH=""
ZDMCLI_VERSION="not-found"

if [[ -d "$ZDM_HOME" ]]; then
  ZDM_HOME_EXISTS="yes"
  ZDM_HOME_PERMS="$(stat -c '%a' "$ZDM_HOME" 2>/dev/null || echo unknown)"
fi

if command -v zdmcli >/dev/null 2>&1; then
  ZDMCLI_PATH="$(command -v zdmcli)"
  ZDMCLI_VERSION="$(zdmcli -version 2>/dev/null | head -n1)"
elif [[ -x "$ZDM_HOME/bin/zdmcli" ]]; then
  ZDMCLI_PATH="$ZDM_HOME/bin/zdmcli"
  ZDMCLI_VERSION="$($ZDM_HOME/bin/zdmcli -version 2>/dev/null | head -n1)"
fi

DISK_ROOT="$(df -h / 2>/dev/null | tail -n1 || echo unknown)"
MEMORY_SUMMARY="$(free -h 2>/dev/null | awk '/^Mem:/ {print $2" total, "$7" available"}' || echo unknown)"

OVERALL_STATUS="PASS"
NOTES=""
if [[ "$CURRENT_USER" != "$REQUIRED_RUN_USER" ]]; then
  OVERALL_STATUS="WARN"
  NOTES="Expected user ${REQUIRED_RUN_USER}, current user is ${CURRENT_USER}."
fi

{
  echo "HOSTNAME=$HOSTNAME_VAL"
  echo "OS_PRETTY_NAME=$OS_PRETTY"
  echo "KERNEL=$KERNEL_VAL"
  echo "UPTIME=$UPTIME_VAL"
  echo "CURRENT_USER=$CURRENT_USER"
  echo "ZDM_HOME=$ZDM_HOME"
  echo "ZDM_HOME_EXISTS=$ZDM_HOME_EXISTS"
  echo "ZDM_HOME_PERMS=$ZDM_HOME_PERMS"
  echo "ZDMCLI_PATH=$ZDMCLI_PATH"
  echo "ZDMCLI_VERSION=$ZDMCLI_VERSION"
  echo "DISK_ROOT=$DISK_ROOT"
  echo "MEMORY_SUMMARY=$MEMORY_SUMMARY"
  echo "SOURCE_HOST=$SOURCE_HOST"
  echo "TARGET_HOST=$TARGET_HOST"
  echo "SOURCE_SSH_USER=$SOURCE_SSH_USER"
  echo "TARGET_SSH_USER=$TARGET_SSH_USER"
} > "$RAW_OUT"

{
  echo "# ZDM Server Discovery Report"
  echo
  echo "- Timestamp: $TIMESTAMP"
  echo "- Status: $OVERALL_STATUS"
  echo
  echo "## Captured Values"
  echo
  echo "| Field | Value |"
  echo "|---|---|"
  echo "| Hostname | ${HOSTNAME_VAL:-N/A} |"
  echo "| OS | ${OS_PRETTY:-N/A} |"
  echo "| Kernel | ${KERNEL_VAL:-N/A} |"
  echo "| Uptime | ${UPTIME_VAL:-N/A} |"
  echo "| Current user | ${CURRENT_USER:-N/A} |"
  echo "| ZDM_HOME | ${ZDM_HOME:-N/A} |"
  echo "| ZDM_HOME exists | ${ZDM_HOME_EXISTS:-N/A} |"
  echo "| ZDM_HOME perms | ${ZDM_HOME_PERMS:-N/A} |"
  echo "| zdmcli path | ${ZDMCLI_PATH:-N/A} |"
  echo "| zdmcli version | ${ZDMCLI_VERSION:-N/A} |"
  echo "| Disk root | ${DISK_ROOT:-N/A} |"
  echo "| Memory summary | ${MEMORY_SUMMARY:-N/A} |"
  echo "| Source endpoint | ${SOURCE_SSH_USER}@${SOURCE_HOST} |"
  echo "| Target endpoint | ${TARGET_SSH_USER}@${TARGET_HOST} |"
  if [[ -n "$NOTES" ]]; then
    echo
    echo "## Notes"
    echo
    echo "- $NOTES"
  fi
  echo
  echo "Raw output: $RAW_OUT"
} > "$REPORT_MD"

{
  echo "{"
  echo "  \"timestamp\": \"$(json_escape "$TIMESTAMP")\"," 
  echo "  \"status\": \"$(json_escape "$OVERALL_STATUS")\"," 
  echo "  \"captured\": {"
  echo "    \"hostname\": \"$(json_escape "$HOSTNAME_VAL")\"," 
  echo "    \"os_pretty_name\": \"$(json_escape "$OS_PRETTY")\"," 
  echo "    \"kernel\": \"$(json_escape "$KERNEL_VAL")\"," 
  echo "    \"uptime\": \"$(json_escape "$UPTIME_VAL")\"," 
  echo "    \"current_user\": \"$(json_escape "$CURRENT_USER")\"," 
  echo "    \"zdm_home\": \"$(json_escape "$ZDM_HOME")\"," 
  echo "    \"zdm_home_exists\": \"$(json_escape "$ZDM_HOME_EXISTS")\"," 
  echo "    \"zdm_home_perms\": \"$(json_escape "$ZDM_HOME_PERMS")\"," 
  echo "    \"zdmcli_path\": \"$(json_escape "$ZDMCLI_PATH")\"," 
  echo "    \"zdmcli_version\": \"$(json_escape "$ZDMCLI_VERSION")\"," 
  echo "    \"disk_root\": \"$(json_escape "$DISK_ROOT")\"," 
  echo "    \"memory_summary\": \"$(json_escape "$MEMORY_SUMMARY")\""
  echo "  },"
  echo "  \"notes\": \"$(json_escape "$NOTES")\""
  echo "}"
} > "$REPORT_JSON"

echo "Server markdown report: $REPORT_MD"
echo "Server json report: $REPORT_JSON"

exit 0
