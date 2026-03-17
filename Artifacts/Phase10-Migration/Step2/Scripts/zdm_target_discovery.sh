#!/usr/bin/env bash

set -u
set -o pipefail

# Rendered from zdm-env.md at generation time. Runtime does not depend on zdm-env.md.
TARGET_HOST="${TARGET_HOST:-10.200.0.250}"
TARGET_SSH_USER="${TARGET_SSH_USER:-opc}"
TARGET_SSH_KEY_RAW="${TARGET_SSH_KEY:-~/.ssh/<target_key>.pem}"
ORACLE_USER="${ORACLE_USER:-oracle}"
TARGET_REMOTE_ORACLE_HOME="${TARGET_REMOTE_ORACLE_HOME:-/u02/app/oracle/product/19.0.0.0/dbhome_1}"
TARGET_ORACLE_SID="${TARGET_ORACLE_SID:-POCAKV1}"
TARGET_DATABASE_UNIQUE_NAME="${TARGET_DATABASE_UNIQUE_NAME:-POCAKV_ODAA}"
REQUIRED_RUN_USER="${REQUIRED_RUN_USER:-zdmuser}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEP2_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DISCOVERY_DIR="$STEP2_DIR/Discovery/target"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
RAW_OUT="$DISCOVERY_DIR/target-discovery-$TIMESTAMP.raw.txt"
REPORT_MD="$DISCOVERY_DIR/target-discovery-$TIMESTAMP.md"
REPORT_JSON="$DISCOVERY_DIR/target-discovery-$TIMESTAMP.json"

SSH_OPTS=(
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=12
  -o PasswordAuthentication=no
)

mkdir -p "$DISCOVERY_DIR"

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\r//g; :a;N;$!ba;s/\n/\\n/g'
}

is_placeholder() {
  [[ "$1" == *"<"*">"* ]]
}

expand_home() {
  local p="$1"
  if [[ "$p" == ~/* ]]; then
    printf '%s\n' "${HOME}/${p#~/}"
  else
    printf '%s\n' "$p"
  fi
}

normalize_optional_key() {
  local raw="$1"
  if [[ -z "$raw" ]] || is_placeholder "$raw"; then
    printf '%s\n' ""
    return
  fi
  expand_home "$raw"
}

extract_kv() {
  local key="$1"
  local file="$2"
  local value
  value="$(grep -m1 "^${key}=" "$file" 2>/dev/null | sed "s/^${key}=//")"
  printf '%s\n' "$value"
}

TARGET_SSH_KEY="$(normalize_optional_key "$TARGET_SSH_KEY_RAW")"
KEY_MODE="agent/default"
if [[ -n "$TARGET_SSH_KEY" ]]; then
  KEY_MODE="$TARGET_SSH_KEY"
fi

CURRENT_USER="$(whoami)"
OVERALL_STATUS="PASS"
NOTES=""

if [[ "$CURRENT_USER" != "$REQUIRED_RUN_USER" ]]; then
  OVERALL_STATUS="WARN"
  NOTES="Expected user ${REQUIRED_RUN_USER}, current user is ${CURRENT_USER}."
fi

if [[ -n "$TARGET_SSH_KEY" && ! -r "$TARGET_SSH_KEY" ]]; then
  OVERALL_STATUS="FAIL"
  NOTES="SSH key file is not readable: $TARGET_SSH_KEY"
fi

REMOTE_OUTPUT=""
REMOTE_RC=0

if [[ "$OVERALL_STATUS" != "FAIL" ]]; then
  SSH_CMD=(ssh "${SSH_OPTS[@]}")
  if [[ -n "$TARGET_SSH_KEY" ]]; then
    SSH_CMD+=( -i "$TARGET_SSH_KEY" )
  fi
  SSH_CMD+=("${TARGET_SSH_USER}@${TARGET_HOST}" "bash -s -- '$ORACLE_USER' '$TARGET_REMOTE_ORACLE_HOME' '$TARGET_ORACLE_SID' '$TARGET_DATABASE_UNIQUE_NAME'")

  REMOTE_OUTPUT="$(${SSH_CMD[@]} <<'REMOTE_SCRIPT' 2>&1
ORACLE_USER="$1"
CFG_ORACLE_HOME="$2"
CFG_ORACLE_SID="$3"
CFG_DB_UNIQUE_NAME="$4"

pick_first_non_empty() {
  local a="$1"
  local b="$2"
  if [[ -n "$a" ]]; then
    printf '%s\n' "$a"
  else
    printf '%s\n' "$b"
  fi
}

detect_sid_from_pmon() {
  ps -ef 2>/dev/null | awk '/pmon/ && !/grep/ {sub(/.*pmon_/,"",$0); print $0}' | head -n1
}

detect_oracle_home_from_oratab() {
  if [[ -r /etc/oratab ]]; then
    awk -F: '/^[^#].*:.+:.+/ {print $2; exit}' /etc/oratab
  fi
}

HOSTNAME_VAL="$(hostname 2>/dev/null || echo unknown)"
OS_PRETTY="$(grep -m1 '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"')"
KERNEL_VAL="$(uname -sr 2>/dev/null || echo unknown)"
UPTIME_VAL="$(uptime -p 2>/dev/null || uptime 2>/dev/null || echo unknown)"
ORATAB_ENTRIES="$(grep -Ev '^(#|$)' /etc/oratab 2>/dev/null | tr '\n' ';' | sed 's/;$/\n/' )"
PMON_SIDS="$(ps -ef 2>/dev/null | awk '/pmon/ && !/grep/ {sub(/.*pmon_/,"",$0); print $0}' | tr '\n' ';' | sed 's/;$/\n/')"

RUNTIME_SID="$(pick_first_non_empty "$CFG_ORACLE_SID" "$(detect_sid_from_pmon)")"
RUNTIME_OH="$(pick_first_non_empty "$CFG_ORACLE_HOME" "$(detect_oracle_home_from_oratab)")"
SQLPLUS_VERSION="not-found"
if [[ -n "$RUNTIME_OH" && -x "$RUNTIME_OH/bin/sqlplus" ]]; then
  SQLPLUS_VERSION="$($RUNTIME_OH/bin/sqlplus -v 2>/dev/null | head -n1)"
fi

printf 'HOSTNAME=%s\n' "$HOSTNAME_VAL"
printf 'OS_PRETTY_NAME=%s\n' "$OS_PRETTY"
printf 'KERNEL=%s\n' "$KERNEL_VAL"
printf 'UPTIME=%s\n' "$UPTIME_VAL"
printf 'ORACLE_USER=%s\n' "$ORACLE_USER"
printf 'ORATAB_ENTRIES=%s\n' "$ORATAB_ENTRIES"
printf 'PMON_SIDS=%s\n' "$PMON_SIDS"
printf 'ORACLE_HOME_IN_USE=%s\n' "$RUNTIME_OH"
printf 'ORACLE_SID_IN_USE=%s\n' "$RUNTIME_SID"
printf 'DB_UNIQUE_NAME_CONFIG=%s\n' "$CFG_DB_UNIQUE_NAME"
printf 'SQLPLUS_VERSION=%s\n' "$SQLPLUS_VERSION"
REMOTE_SCRIPT
)"
  REMOTE_RC=$?
fi

if [[ $REMOTE_RC -ne 0 ]]; then
  OVERALL_STATUS="FAIL"
  if [[ -n "$NOTES" ]]; then
    NOTES+=" "
  fi
  NOTES+="Remote discovery failed: $REMOTE_OUTPUT"
fi

printf '%s\n' "$REMOTE_OUTPUT" > "$RAW_OUT"

REMOTE_HOSTNAME="$(extract_kv "HOSTNAME" "$RAW_OUT")"
REMOTE_OS="$(extract_kv "OS_PRETTY_NAME" "$RAW_OUT")"
REMOTE_KERNEL="$(extract_kv "KERNEL" "$RAW_OUT")"
REMOTE_UPTIME="$(extract_kv "UPTIME" "$RAW_OUT")"
REMOTE_ORATAB="$(extract_kv "ORATAB_ENTRIES" "$RAW_OUT")"
REMOTE_PMON="$(extract_kv "PMON_SIDS" "$RAW_OUT")"
REMOTE_ORACLE_HOME="$(extract_kv "ORACLE_HOME_IN_USE" "$RAW_OUT")"
REMOTE_ORACLE_SID="$(extract_kv "ORACLE_SID_IN_USE" "$RAW_OUT")"
REMOTE_DB_UNQ="$(extract_kv "DB_UNIQUE_NAME_CONFIG" "$RAW_OUT")"
REMOTE_SQLPLUS="$(extract_kv "SQLPLUS_VERSION" "$RAW_OUT")"

{
  echo "# Target Discovery Report"
  echo
  echo "- Timestamp: $TIMESTAMP"
  echo "- Status: $OVERALL_STATUS"
  echo "- Target host: $TARGET_HOST"
  echo "- SSH user: $TARGET_SSH_USER"
  echo "- SSH key mode: $KEY_MODE"
  echo
  echo "## Captured Values"
  echo
  echo "| Field | Value |"
  echo "|---|---|"
  echo "| Remote hostname | ${REMOTE_HOSTNAME:-N/A} |"
  echo "| Remote OS | ${REMOTE_OS:-N/A} |"
  echo "| Kernel | ${REMOTE_KERNEL:-N/A} |"
  echo "| Uptime | ${REMOTE_UPTIME:-N/A} |"
  echo "| /etc/oratab entries | ${REMOTE_ORATAB:-N/A} |"
  echo "| PMON SIDs | ${REMOTE_PMON:-N/A} |"
  echo "| Oracle home in use | ${REMOTE_ORACLE_HOME:-N/A} |"
  echo "| Oracle SID in use | ${REMOTE_ORACLE_SID:-N/A} |"
  echo "| DB unique name (config) | ${REMOTE_DB_UNQ:-N/A} |"
  echo "| sqlplus version | ${REMOTE_SQLPLUS:-N/A} |"
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
  echo "  \"target_host\": \"$(json_escape "$TARGET_HOST")\"," 
  echo "  \"ssh_user\": \"$(json_escape "$TARGET_SSH_USER")\"," 
  echo "  \"ssh_key_mode\": \"$(json_escape "$KEY_MODE")\"," 
  echo "  \"captured\": {"
  echo "    \"hostname\": \"$(json_escape "$REMOTE_HOSTNAME")\"," 
  echo "    \"os_pretty_name\": \"$(json_escape "$REMOTE_OS")\"," 
  echo "    \"kernel\": \"$(json_escape "$REMOTE_KERNEL")\"," 
  echo "    \"uptime\": \"$(json_escape "$REMOTE_UPTIME")\"," 
  echo "    \"oratab_entries\": \"$(json_escape "$REMOTE_ORATAB")\"," 
  echo "    \"pmon_sids\": \"$(json_escape "$REMOTE_PMON")\"," 
  echo "    \"oracle_home_in_use\": \"$(json_escape "$REMOTE_ORACLE_HOME")\"," 
  echo "    \"oracle_sid_in_use\": \"$(json_escape "$REMOTE_ORACLE_SID")\"," 
  echo "    \"db_unique_name_config\": \"$(json_escape "$REMOTE_DB_UNQ")\"," 
  echo "    \"sqlplus_version\": \"$(json_escape "$REMOTE_SQLPLUS")\""
  echo "  },"
  echo "  \"notes\": \"$(json_escape "$NOTES")\""
  echo "}"
} > "$REPORT_JSON"

echo "Target markdown report: $REPORT_MD"
echo "Target json report: $REPORT_JSON"

if [[ "$OVERALL_STATUS" == "FAIL" ]]; then
  exit 1
fi

exit 0
