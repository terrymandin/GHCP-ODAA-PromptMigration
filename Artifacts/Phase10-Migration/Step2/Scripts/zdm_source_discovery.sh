#!/bin/bash
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration

set -u
set -o pipefail

ORACLE_USER="${ORACLE_USER:-oracle}"
SOURCE_REMOTE_ORACLE_HOME_DEFAULT="/u01/app/oracle/product/19.0.0/dbhome_1"
SOURCE_ORACLE_SID_DEFAULT="POCAKV"
SOURCE_DATABASE_UNIQUE_NAME_DEFAULT="POCAKV"

SOURCE_REMOTE_ORACLE_HOME="${SOURCE_REMOTE_ORACLE_HOME:-$SOURCE_REMOTE_ORACLE_HOME_DEFAULT}"
SOURCE_ORACLE_SID="${SOURCE_ORACLE_SID:-$SOURCE_ORACLE_SID_DEFAULT}"
SOURCE_DATABASE_UNIQUE_NAME="${SOURCE_DATABASE_UNIQUE_NAME:-$SOURCE_DATABASE_UNIQUE_NAME_DEFAULT}"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname)"
TEXT_OUT="./zdm_source_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
JSON_OUT="./zdm_source_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

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

  # 1) Already-set environment values
  if [ -n "${ORACLE_SID:-}" ]; then
    sid="$ORACLE_SID"
  fi
  if [ -n "${ORACLE_HOME:-}" ]; then
    home="$ORACLE_HOME"
  fi

  # Explicit prompt-rendered overrides
  if [ -z "$sid" ]; then
    sid="$(normalize_optional "$SOURCE_ORACLE_SID")"
  fi
  if [ -z "$home" ]; then
    home="$(normalize_optional "$SOURCE_REMOTE_ORACLE_HOME")"
  fi

  # 2) /etc/oratab
  if { [ -z "$sid" ] || [ -z "$home" ]; } && [ -r /etc/oratab ]; then
    local entry
    entry="$(grep -Ev '^#|^$|^\+ASM' /etc/oratab | head -n1 || true)"
    if [ -n "$entry" ]; then
      [ -z "$sid" ] && sid="$(printf '%s' "$entry" | cut -d: -f1)"
      [ -z "$home" ] && home="$(printf '%s' "$entry" | cut -d: -f2)"
    fi
  fi

  # 3) PMON
  if [ -z "$sid" ]; then
    sid="$(ps -ef | awk '/ora_pmon_/ && !/grep/ {sub(/^.*ora_pmon_/, "", $0); print $0; exit}' || true)"
  fi

  # 4) Common paths
  if [ -z "$home" ]; then
    home="$(ls -d /u01/app/oracle/product/*/dbhome_1 /u02/app/oracle/product/*/dbhome_1 2>/dev/null | head -n1 || true)"
  fi

  # 5) oraenv/coraenv best effort
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
  tmp_sql="$(mktemp /tmp/zdm_source_sql_XXXX.sql)"
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
  echo "Rendered SOURCE_DATABASE_UNIQUE_NAME: $SOURCE_DATABASE_UNIQUE_NAME"
} | tee -a "$TEXT_OUT"

detect_oracle_env

log_section "Resolved Oracle Environment"
{
  echo "ORACLE_HOME: ${ORACLE_HOME_RESOLVED:-UNRESOLVED}"
  echo "ORACLE_SID: ${ORACLE_SID_RESOLVED:-UNRESOLVED}"
  echo "ORACLE_USER: $ORACLE_USER"
} | tee -a "$TEXT_OUT"

run_cmd "OS - Hostname, IP, OS Version" "hostname; hostname -I 2>/dev/null || true; cat /etc/os-release 2>/dev/null || uname -a"
run_cmd "OS - Disk Space" "df -h"
run_cmd "Oracle Environment - Shell Values" "env | grep -E '^(ORACLE_|TNS_ADMIN|PATH)=' || true"
run_cmd "Oracle Environment - Oracle Version" "${ORACLE_HOME_RESOLVED:-/bin}/bin/sqlplus -v 2>/dev/null || sqlplus -v 2>/dev/null || true"

run_sql "Database Configuration" "set pages 500 lines 300 trimspool on verify off
col name format a20
col db_unique_name format a30
col database_role format a20
col open_mode format a20
select name, db_unique_name, dbid, database_role, open_mode, log_mode, force_logging from v\$database;
select parameter, value from nls_database_parameters where parameter in ('NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET');
select supplemental_log_data_min, supplemental_log_data_pk, supplemental_log_data_ui, supplemental_log_data_fk, supplemental_log_data_all from v\$database;
"

run_sql "Container Database" "set pages 500 lines 300 trimspool on verify off
select cdb from v\$database;
select con_id, name, open_mode from v\$pdbs order by con_id;
"

run_sql "TDE" "set pages 500 lines 300 trimspool on verify off
select wallet_type, status, wallet_order, wrl_type, wrl_parameter from v\$encryption_wallet;
select tablespace_name, encrypted from dba_tablespaces order by tablespace_name;
"

run_sql "Tablespaces" "set pages 1000 lines 300 trimspool on verify off
col file_name format a80
select tablespace_name, file_name, autoextensible, bytes/1024/1024 current_mb, maxbytes/1024/1024 max_mb, increment_by from dba_data_files order by tablespace_name, file_name;
"

run_sql "Redo and Archive" "set pages 1000 lines 300 trimspool on verify off
select l.group#, l.thread#, l.bytes/1024/1024 size_mb, l.members, l.archived, l.status from v\$log l order by l.group#;
select group#, member from v\$logfile order by group#, member;
select dest_id, destination, target, status, valid_now from v\$archive_dest where destination is not null order by dest_id;
"

run_cmd "Network - Listener Status" "lsnrctl status"
run_cmd "Network - tnsnames/sqlnet" "for f in \"$ORACLE_HOME_RESOLVED/network/admin/tnsnames.ora\" \"$ORACLE_HOME_RESOLVED/network/admin/sqlnet.ora\"; do echo \"--- $f ---\"; [ -r \"$f\" ] && cat \"$f\" || echo 'not found'; done"
run_cmd "Authentication - Password File and SSH" "ls -l $ORACLE_HOME_RESOLVED/dbs/orapw* 2>/dev/null || true; ls -la ~/.ssh 2>/dev/null || true"

run_sql "Schema Information" "set pages 1000 lines 300 trimspool on verify off
col owner format a30
select owner, round(sum(bytes)/1024/1024,2) size_mb from dba_segments where owner not in ('SYS','SYSTEM','SYSMAN','XDB','MDSYS','CTXSYS','DBSNMP','WMSYS','OUTLN') group by owner having sum(bytes) > 100*1024*1024 order by size_mb desc;
select owner, object_type, count(*) invalid_count from dba_objects where status <> 'VALID' group by owner, object_type order by owner, object_type;
"

run_sql "Backup Configuration" "set pages 1000 lines 300 trimspool on verify off
select name, value from v\$parameter where name in ('db_recovery_file_dest','db_recovery_file_dest_size');
select * from v\$rman_configuration;
select max(end_time) as last_backup_end_time from v\$rman_backup_job_details where status='COMPLETED';
select output_device_type, max(end_time) as last_success from v\$rman_backup_job_details where status='COMPLETED' group by output_device_type;
select owner, job_name, enabled, state, repeat_interval from dba_scheduler_jobs where lower(job_name) like '%backup%' or lower(job_action) like '%backup%' order by owner, job_name;
"

run_cmd "Backup Configuration - Crontab" "(crontab -l 2>/dev/null || true) | grep -Ei 'rman|backup|arch' || true"

run_sql "Database Links" "set pages 1000 lines 300 trimspool on verify off
col owner format a30
col db_link format a50
col host format a60
select owner, db_link, host, username from dba_db_links order by owner, db_link;
"

run_sql "Materialized Views and Logs" "set pages 1000 lines 300 trimspool on verify off
col owner format a30
col mview_name format a40
select owner, mview_name, refresh_method, refresh_mode, to_char(last_refresh_date,'YYYY-MM-DD HH24:MI:SS') last_refresh, to_char(staleness) staleness from dba_mviews order by owner, mview_name;
select log_owner, master, log_table from dba_mview_logs order by log_owner, master;
"

run_sql "Scheduler Jobs" "set pages 1000 lines 300 trimspool on verify off
col owner format a30
col job_name format a40
select owner, job_name, job_type, enabled, state, to_char(last_start_date,'YYYY-MM-DD HH24:MI:SS') last_start, to_char(next_run_date,'YYYY-MM-DD HH24:MI:SS') next_run, repeat_interval from dba_scheduler_jobs order by owner, job_name;
select owner, job_name, regexp_substr(lower(nvl(job_action,'')), '(https?://[^ ]+|/[^ ''\"]+|credential[^ ]*)') possible_external_ref from dba_scheduler_jobs where regexp_like(lower(nvl(job_action,'')), '(https?://|/|credential)') order by owner, job_name;
"

run_sql "Data Guard Parameters" "set pages 1000 lines 300 trimspool on verify off
select name, value from v\$parameter where name in (
'log_archive_config','log_archive_dest_1','log_archive_dest_2','fal_client','fal_server',
'db_file_name_convert','log_file_name_convert','standby_file_management'
) order by name;
"

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

echo "Source discovery text report: $TEXT_OUT"
echo "Source discovery JSON report: $JSON_OUT"

if [ "$STATUS" = "partial" ]; then
  exit 1
fi

exit 0
