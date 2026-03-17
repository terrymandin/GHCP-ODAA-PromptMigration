#!/bin/bash
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration

set -u
set -o pipefail

ORACLE_USER="${ORACLE_USER:-oracle}"
TARGET_REMOTE_ORACLE_HOME_DEFAULT="/u02/app/oracle/product/19.0.0.0/dbhome_1"
TARGET_ORACLE_SID_DEFAULT="POKAKV1"
TARGET_DATABASE_UNIQUE_NAME_DEFAULT="POCAKV_ODAA"

TARGET_REMOTE_ORACLE_HOME="${TARGET_REMOTE_ORACLE_HOME:-$TARGET_REMOTE_ORACLE_HOME_DEFAULT}"
TARGET_ORACLE_SID="${TARGET_ORACLE_SID:-$TARGET_ORACLE_SID_DEFAULT}"
TARGET_DATABASE_UNIQUE_NAME="${TARGET_DATABASE_UNIQUE_NAME:-$TARGET_DATABASE_UNIQUE_NAME_DEFAULT}"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname)"
TEXT_OUT="./zdm_target_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
JSON_OUT="./zdm_target_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

WARNINGS=()
PARTIAL=0
ORACLE_HOME_RESOLVED=""
ORACLE_SID_RESOLVED=""

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

normalize_optional() {
  local v="$1"
  if [ -z "$v" ] || [[ "$v" == *"<"*">"* ]]; then
    printf '%s' ""
  else
    printf '%s' "$v"
  fi
}

detect_oracle_env() {
  local sid=""
  local home=""

  if [ -n "${ORACLE_SID:-}" ]; then
    sid="$ORACLE_SID"
  fi
  if [ -n "${ORACLE_HOME:-}" ]; then
    home="$ORACLE_HOME"
  fi

  if [ -z "$sid" ]; then
    sid="$(normalize_optional "$TARGET_ORACLE_SID")"
  fi
  if [ -z "$home" ]; then
    home="$(normalize_optional "$TARGET_REMOTE_ORACLE_HOME")"
  fi

  if { [ -z "$sid" ] || [ -z "$home" ]; } && [ -r /etc/oratab ]; then
    local entry
    entry="$(grep -Ev '^#|^$|^\+ASM' /etc/oratab | head -n1 || true)"
    if [ -n "$entry" ]; then
      [ -z "$sid" ] && sid="$(printf '%s' "$entry" | cut -d: -f1)"
      [ -z "$home" ] && home="$(printf '%s' "$entry" | cut -d: -f2)"
    fi
  fi

  if [ -z "$sid" ]; then
    sid="$(ps -ef | awk '/ora_pmon_/ && !/grep/ {sub(/^.*ora_pmon_/, "", $0); print $0; exit}' || true)"
  fi

  if [ -z "$home" ]; then
    home="$(ls -d /u02/app/oracle/product/*/dbhome_1 /u01/app/oracle/product/*/dbhome_1 2>/dev/null | head -n1 || true)"
  fi

  if [ -n "$sid" ] && [ -z "$home" ] && [ -x /usr/local/bin/oraenv ]; then
    home="$(ORACLE_SID="$sid" ORAENV_ASK=NO /usr/local/bin/oraenv >/dev/null 2>&1; printf '%s' "${ORACLE_HOME:-}")"
  fi

  ORACLE_SID_RESOLVED="$sid"
  ORACLE_HOME_RESOLVED="$home"

  if [ -z "$ORACLE_SID_RESOLVED" ]; then
    add_warning "Unable to resolve ORACLE_SID"
  fi
  if [ -z "$ORACLE_HOME_RESOLVED" ]; then
    add_warning "Unable to resolve ORACLE_HOME"
  fi
}

run_sql() {
  local title="$1"
  local sql="$2"

  log_section "$title"

  if [ -z "$ORACLE_HOME_RESOLVED" ] || [ -z "$ORACLE_SID_RESOLVED" ]; then
    printf 'Skipped: ORACLE_HOME or ORACLE_SID not resolved.\n' | tee -a "$TEXT_OUT"
    add_warning "$title skipped due to missing Oracle environment"
    return
  fi

  if [ ! -x "$ORACLE_HOME_RESOLVED/bin/sqlplus" ]; then
    printf 'Skipped: sqlplus not found at %s/bin/sqlplus\n' "$ORACLE_HOME_RESOLVED" | tee -a "$TEXT_OUT"
    add_warning "$title skipped because sqlplus is missing"
    return
  fi

  local tmp_sql
  tmp_sql="$(mktemp /tmp/zdm_target_sql_XXXX.sql)"
  printf '%s\n' "$sql" > "$tmp_sql"

  local output rc
  if [ "$(whoami)" != "$ORACLE_USER" ]; then
    output="$(sudo -u "$ORACLE_USER" -E env ORACLE_HOME="$ORACLE_HOME_RESOLVED" ORACLE_SID="$ORACLE_SID_RESOLVED" PATH="$ORACLE_HOME_RESOLVED/bin:$PATH" "$ORACLE_HOME_RESOLVED/bin/sqlplus" -s / as sysdba @"$tmp_sql" 2>&1)"
    rc=$?
  else
    output="$(env ORACLE_HOME="$ORACLE_HOME_RESOLVED" ORACLE_SID="$ORACLE_SID_RESOLVED" PATH="$ORACLE_HOME_RESOLVED/bin:$PATH" "$ORACLE_HOME_RESOLVED/bin/sqlplus" -s / as sysdba @"$tmp_sql" 2>&1)"
    rc=$?
  fi

  rm -f "$tmp_sql"

  printf '%s\n' "$output" | tee -a "$TEXT_OUT"
  if [ $rc -ne 0 ]; then
    add_warning "$title SQL failed (rc=$rc)"
  fi
}

: > "$TEXT_OUT"

log_section "Script Metadata"
{
  echo "Timestamp: $TIMESTAMP"
  echo "Host: $HOSTNAME_SHORT"
  echo "Run user: $(whoami)"
  echo "Rendered TARGET_DATABASE_UNIQUE_NAME: $TARGET_DATABASE_UNIQUE_NAME"
} | tee -a "$TEXT_OUT"

detect_oracle_env

log_section "Resolved Oracle Environment"
{
  echo "ORACLE_HOME: ${ORACLE_HOME_RESOLVED:-UNRESOLVED}"
  echo "ORACLE_SID: ${ORACLE_SID_RESOLVED:-UNRESOLVED}"
  echo "ORACLE_USER: $ORACLE_USER"
} | tee -a "$TEXT_OUT"

run_cmd "OS - Hostname, IP, OS Version" "hostname; hostname -I 2>/dev/null || true; cat /etc/os-release 2>/dev/null || uname -a"
run_cmd "Oracle Environment - Shell Values" "env | grep -E '^(ORACLE_|TNS_ADMIN|PATH)=' || true"
run_cmd "Oracle Environment - Oracle Version" "${ORACLE_HOME_RESOLVED:-/bin}/bin/sqlplus -v 2>/dev/null || sqlplus -v 2>/dev/null || true"

run_sql "Database Configuration" "set pages 500 lines 300 trimspool on verify off
col name format a20
col db_unique_name format a30
col database_role format a20
col open_mode format a20
select name, db_unique_name, database_role, open_mode, log_mode from v\$database;
select parameter, value from nls_database_parameters where parameter in ('NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET');
"

run_sql "Container Database" "set pages 500 lines 300 trimspool on verify off
select cdb from v\$database;
select con_id, name, open_mode from v\$pdbs order by con_id;
"

run_sql "TDE Wallet" "set pages 500 lines 300 trimspool on verify off
select wallet_type, status, wallet_order, wrl_type, wrl_parameter from v\$encryption_wallet;
"

run_sql "ASM Diskgroup" "set pages 1000 lines 300 trimspool on verify off
select name, state, type redundancy, total_mb, free_mb, usable_file_mb from v\$asm_diskgroup;
"

run_cmd "Storage - ASM and Exadata free space" "asmcmd lsdg 2>/dev/null || true; cellcli -e 'list griddisk attributes name,size,freespace' 2>/dev/null || true; cellcli -e 'list celldisk attributes name,size,freespace' 2>/dev/null || true"
run_cmd "Network - Listener and SCAN" "lsnrctl status; srvctl status scan_listener 2>/dev/null || true"
run_cmd "Network - tnsnames" "for f in \"$ORACLE_HOME_RESOLVED/network/admin/tnsnames.ora\" \"$ORACLE_HOME_RESOLVED/network/admin/sqlnet.ora\"; do echo \"--- $f ---\"; [ -r \"$f\" ] && cat \"$f\" || echo 'not found'; done"

run_cmd "OCI/Azure Integration - Metadata" "echo '--- OCI config ---'; for f in ~/.oci/config /home/oracle/.oci/config /root/.oci/config; do if [ -f \"$f\" ]; then echo \"$f\"; sed -E 's/(key_file|fingerprint|tenancy|user)=.*/\\1=<masked>/g' \"$f\"; fi; done; echo '--- OCI metadata ---'; curl -s --connect-timeout 2 -H 'Authorization: Bearer Oracle' http://169.254.169.254/opc/v2/instance/ 2>/dev/null || true; echo; echo '--- Azure metadata ---'; curl -s --connect-timeout 2 -H Metadata:true 'http://169.254.169.254/metadata/instance?api-version=2021-02-01' 2>/dev/null || true"

run_cmd "Grid Infrastructure" "crsctl stat res -t 2>/dev/null || true; srvctl status database -d ${ORACLE_SID_RESOLVED} 2>/dev/null || true"

run_cmd "Network Security" "iptables -S 2>/dev/null || true; firewall-cmd --list-all 2>/dev/null || true; ss -lntp | grep -E ':(22|1521|2484)\\b' || true"

STATUS="success"
if [ "$PARTIAL" -ne 0 ]; then
  STATUS="partial"
fi

{
  echo "{" 
  echo "  \"status\": \"$(json_escape "$STATUS")\"," 
  echo "  \"host\": \"$(json_escape "$HOSTNAME_SHORT")\"," 
  echo "  \"timestamp\": \"$(json_escape "$TIMESTAMP")\"," 
  echo "  \"oracle_home\": \"$(json_escape "${ORACLE_HOME_RESOLVED:-}")\"," 
  echo "  \"oracle_sid\": \"$(json_escape "${ORACLE_SID_RESOLVED:-}")\"," 
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

echo "Target discovery text report: $TEXT_OUT"
echo "Target discovery JSON report: $JSON_OUT"

if [ "$STATUS" = "partial" ]; then
  exit 1
fi

exit 0
