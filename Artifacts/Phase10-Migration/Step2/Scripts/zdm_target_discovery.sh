#!/bin/bash
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration

set -u
set -o pipefail

TARGET_REMOTE_ORACLE_HOME_DEFAULT="/u02/app/oracle/product/19.0.0.0/dbhome_1"
TARGET_ORACLE_SID_DEFAULT="POKAKV1"
TARGET_DATABASE_UNIQUE_NAME_DEFAULT="POCAKV_ODAA"
ORACLE_USER="${ORACLE_USER:-oracle}"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)"
OUT_TXT="./zdm_target_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
OUT_JSON="./zdm_target_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

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

detect_sid_from_oratab() {
  awk -F: '!/^#/ && NF>=2 && $1!="" && $2!="" {print $1; exit}' /etc/oratab 2>/dev/null
}

detect_home_from_oratab() {
  local sid="$1"
  awk -F: -v sid="$sid" '$1==sid {print $2; exit}' /etc/oratab 2>/dev/null
}

detect_sid_from_pmon() {
  ps -ef 2>/dev/null | awk '/ora_pmon_/ && !/awk/ {sub(/^.*ora_pmon_/,"",$0); print $0; exit}'
}

detect_home_common() {
  ls -d /u01/app/oracle/product/*/dbhome_1 /u02/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1 2>/dev/null | head -n 1
}

detect_with_oraenv() {
  local sid="$1"
  local result=""
  if command -v oraenv >/dev/null 2>&1 && [ -n "$sid" ]; then
    result="$({
      ORACLE_SID="$sid"
      ORAENV_ASK=NO
      . oraenv >/dev/null 2>&1
      printf '%s\n' "$ORACLE_HOME"
    } 2>/dev/null)"
  fi
  printf '%s\n' "$result"
}

ORACLE_SID="${TARGET_ORACLE_SID:-${ORACLE_SID:-$TARGET_ORACLE_SID_DEFAULT}}"
ORACLE_HOME="${TARGET_REMOTE_ORACLE_HOME:-${ORACLE_HOME:-$TARGET_REMOTE_ORACLE_HOME_DEFAULT}}"

if [ -z "$ORACLE_SID" ]; then
  ORACLE_SID="$(detect_sid_from_oratab)"
fi
if [ -z "$ORACLE_SID" ]; then
  ORACLE_SID="$(detect_sid_from_pmon)"
fi
if [ -z "$ORACLE_HOME" ] && [ -n "$ORACLE_SID" ]; then
  ORACLE_HOME="$(detect_home_from_oratab "$ORACLE_SID")"
fi
if [ -z "$ORACLE_HOME" ]; then
  ORACLE_HOME="$(detect_home_common)"
fi
if [ -z "$ORACLE_HOME" ] && [ -n "$ORACLE_SID" ]; then
  ORACLE_HOME="$(detect_with_oraenv "$ORACLE_SID")"
fi

if [ -z "$ORACLE_SID" ]; then
  add_warning "ORACLE_SID could not be detected"
fi
if [ -z "$ORACLE_HOME" ]; then
  add_warning "ORACLE_HOME could not be detected"
fi

run_sql() {
  local sql="$1"
  local who
  who="$(whoami)"

  if [ -z "$ORACLE_HOME" ] || [ -z "$ORACLE_SID" ]; then
    add_warning "SQL skipped because ORACLE_HOME or ORACLE_SID is empty"
    return 1
  fi

  if [ "$who" = "$ORACLE_USER" ]; then
    ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" PATH="$ORACLE_HOME/bin:$PATH" \
      "$ORACLE_HOME/bin/sqlplus" -s / as sysdba <<SQL
set pages 500 lines 300 trimspool on feedback off verify off heading on
$sql
exit
SQL
  else
    sudo -u "$ORACLE_USER" -E ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" PATH="$ORACLE_HOME/bin:$PATH" \
      "$ORACLE_HOME/bin/sqlplus" -s / as sysdba <<SQL
set pages 500 lines 300 trimspool on feedback off verify off heading on
$sql
exit
SQL
  fi
}

append_sql_section() {
  local title="$1"
  local sql="$2"
  append_header "$title"
  {
    run_sql "$sql" 2>&1 || {
      local rc=$?
      echo "[WARN] SQL section failed with rc=$rc"
      add_warning "$title SQL failed"
    }
  } >> "$OUT_TXT"
}

{
  echo "ZDM Step 2 Target Discovery"
  echo "Timestamp: $TIMESTAMP"
  echo "Host: $HOSTNAME_SHORT"
  echo "Rendered Target DB Unique Name: $TARGET_DATABASE_UNIQUE_NAME_DEFAULT"
  echo "Detected ORACLE_HOME: ${ORACLE_HOME:-<empty>}"
  echo "Detected ORACLE_SID: ${ORACLE_SID:-<empty>}"
} > "$OUT_TXT"

append_command "OS - Hostname and IP" "hostname -f || hostname; ip -brief addr || ip addr"
append_command "OS - Version" "cat /etc/os-release"
append_command "OS - Disk Space" "df -h"

append_command "Oracle Environment - Process and Env" "echo ORACLE_HOME=$ORACLE_HOME; echo ORACLE_SID=$ORACLE_SID; ps -ef | grep -E 'pmon|tnslsnr|crsd' | grep -v grep"
append_command "Oracle Environment - Oracle Version" "[ -x \"$ORACLE_HOME/bin/sqlplus\" ] && \"$ORACLE_HOME/bin/sqlplus\" -v || echo sqlplus not found"

append_sql_section "Database Configuration" "
select name as db_name, db_unique_name, database_role, open_mode from v\$database;
select parameter, value from nls_database_parameters where parameter in ('NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET') order by parameter;
"

append_sql_section "Container Database" "
select cdb from v\$database;
select con_id, name, open_mode from v\$pdbs order by con_id;
"

append_sql_section "TDE" "
select wallet_type, status, wallet_order, wrl_parameter from v\$encryption_wallet;
"

append_sql_section "Storage - ASM" "
select name, total_mb, free_mb, type from v\$asm_diskgroup order by name;
select name, path, total_mb, free_mb, mount_status, state from v\$asm_disk order by name;
"

append_command "Storage - Exadata Cell/Grid (best effort)" "command -v asmcmd >/dev/null 2>&1 && asmcmd lsdg || echo asmcmd not found; command -v cellcli >/dev/null 2>&1 && sudo cellcli -e 'list griddisk attributes name,availableTo' || echo cellcli not available"

append_command "Network - Listener and Oracle Net" "lsnrctl status; command -v srvctl >/dev/null 2>&1 && srvctl status scan_listener || echo srvctl or scan listener not available; [ -f \"$ORACLE_HOME/network/admin/tnsnames.ora\" ] && cat \"$ORACLE_HOME/network/admin/tnsnames.ora\" || echo tnsnames.ora not found"

append_command "OCI and Azure Metadata" "[ -f ~/.oci/config ] && { echo '[INFO] ~/.oci/config found'; sed -E 's/(fingerprint|tenancy|user|key_file|region).*/\\1=***masked***/' ~/.oci/config; } || echo ~/.oci/config not found; curl -fsS -H Metadata:true 'http://169.254.169.254/metadata/instance?api-version=2021-02-01' || echo Azure metadata unavailable; curl -fsS -H 'Authorization: Bearer Oracle' 'http://169.254.169.254/opc/v2/instance/' || echo OCI metadata unavailable"

append_command "Grid Infrastructure" "command -v crsctl >/dev/null 2>&1 && crsctl stat res -t || echo crsctl not available"

append_command "Network Security" "(command -v iptables >/dev/null 2>&1 && iptables -L -n | grep -E 'dpt:(22|1521|2484)') || echo iptables rules not available for listener ports; (command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --list-all) || echo firewalld not available"

db_summary="$(run_sql "select name||'|'||db_unique_name||'|'||database_role||'|'||open_mode from v\$database;" 2>/dev/null | tail -n 1)"
if [ -z "$db_summary" ]; then
  add_warning "Unable to compute database summary for JSON"
  db_summary="unknown|unknown|unknown|unknown"
fi

db_name="${db_summary%%|*}"
rest="${db_summary#*|}"
db_unique_name="${rest%%|*}"
rest="${rest#*|}"
db_role="${rest%%|*}"
db_open_mode="${rest#*|}"

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
  echo "  \"database\": {"
  echo "    \"name\": \"$(json_escape "$db_name")\"," 
  echo "    \"unique_name\": \"$(json_escape "$db_unique_name")\"," 
  echo "    \"role\": \"$(json_escape "$db_role")\"," 
  echo "    \"open_mode\": \"$(json_escape "$db_open_mode")\""
  echo "  }"
  echo "}"
} > "$OUT_JSON"

echo "Target discovery text report: $OUT_TXT"
echo "Target discovery json report: $OUT_JSON"

exit 0
