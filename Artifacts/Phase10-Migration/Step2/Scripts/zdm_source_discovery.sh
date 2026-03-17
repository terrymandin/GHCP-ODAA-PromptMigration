#!/bin/bash
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration

set -u
set -o pipefail

SOURCE_REMOTE_ORACLE_HOME_DEFAULT="/u01/app/oracle/product/19.0.0/dbhome_1"
SOURCE_ORACLE_SID_DEFAULT="POCAKV"
SOURCE_DATABASE_UNIQUE_NAME_DEFAULT="POCAKV"
ORACLE_USER="${ORACLE_USER:-oracle}"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)"
OUT_TXT="./zdm_source_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
OUT_JSON="./zdm_source_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

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

ORACLE_SID="${SOURCE_ORACLE_SID:-${ORACLE_SID:-$SOURCE_ORACLE_SID_DEFAULT}}"
ORACLE_HOME="${SOURCE_REMOTE_ORACLE_HOME:-${ORACLE_HOME:-$SOURCE_REMOTE_ORACLE_HOME_DEFAULT}}"

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
  echo "ZDM Step 2 Source Discovery"
  echo "Timestamp: $TIMESTAMP"
  echo "Host: $HOSTNAME_SHORT"
  echo "Rendered Source DB Unique Name: $SOURCE_DATABASE_UNIQUE_NAME_DEFAULT"
  echo "Detected ORACLE_HOME: ${ORACLE_HOME:-<empty>}"
  echo "Detected ORACLE_SID: ${ORACLE_SID:-<empty>}"
} > "$OUT_TXT"

append_command "OS - Hostname and IP" "hostname -f || hostname; ip -brief addr || ip addr"
append_command "OS - Version" "cat /etc/os-release"
append_command "OS - Disk Space" "df -h"

append_command "Oracle Environment - Process and Env" "echo ORACLE_HOME=$ORACLE_HOME; echo ORACLE_SID=$ORACLE_SID; echo ORACLE_BASE=${ORACLE_BASE:-}; ps -ef | grep -E 'pmon|tnslsnr' | grep -v grep"
append_command "Oracle Environment - Oracle Version" "[ -x \"$ORACLE_HOME/bin/sqlplus\" ] && \"$ORACLE_HOME/bin/sqlplus\" -v || echo sqlplus not found"

append_sql_section "Database Configuration" "
select name as db_name, db_unique_name, dbid, database_role, open_mode from v\$database;
select parameter, value from nls_database_parameters where parameter in ('NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET') order by parameter;
select log_mode, force_logging, supplemental_log_data_min, supplemental_log_data_pk, supplemental_log_data_ui, supplemental_log_data_fk, supplemental_log_data_all from v\$database;
"

append_sql_section "Container Database" "
select cdb from v\$database;
select con_id, name, open_mode from v\$pdbs order by con_id;
"

append_sql_section "TDE" "
select wallet_type, status, wallet_order, wrl_parameter from v\$encryption_wallet;
select tablespace_name, encrypted from dba_tablespaces where encrypted='YES' order by tablespace_name;
"

append_sql_section "Tablespaces" "
select tablespace_name, file_name, autoextensible,
       bytes/1024/1024 as current_mb,
       maxbytes/1024/1024 as max_mb,
       increment_by * (select value from v\$parameter where name='db_block_size') /1024/1024 as increment_mb
from dba_data_files
order by tablespace_name, file_name;
"

append_sql_section "Redo and Archive" "
select l.group#, l.thread#, l.bytes/1024/1024 as size_mb, l.members, lf.member
from v\$log l join v\$logfile lf on l.group# = lf.group#
order by l.group#, lf.member;
select dest_id, destination, status, target, schedule from v\$archive_dest where destination is not null order by dest_id;
"

append_command "Network - Listener and Oracle Net Files" "lsnrctl status; [ -f \"$ORACLE_HOME/network/admin/tnsnames.ora\" ] && cat \"$ORACLE_HOME/network/admin/tnsnames.ora\" || echo tnsnames.ora not found; [ -f \"$ORACLE_HOME/network/admin/sqlnet.ora\" ] && cat \"$ORACLE_HOME/network/admin/sqlnet.ora\" || echo sqlnet.ora not found"

append_command "Authentication - Password File and SSH Contents" "ls -l \"$ORACLE_HOME/dbs\"/orapw* 2>/dev/null || echo password file not found in $ORACLE_HOME/dbs; ls -la ~/.ssh 2>/dev/null || echo ~/.ssh not accessible"

append_sql_section "Schema Information" "
select owner, round(sum(bytes)/1024/1024,2) as schema_mb
from dba_segments
where owner not in ('SYS','SYSTEM','XDB','OUTLN','CTXSYS','MDSYS','WMSYS','DBSNMP','SYSMAN')
group by owner
having sum(bytes) > 100*1024*1024
order by schema_mb desc;
select owner, object_type, count(*) as invalid_count
from dba_objects
where status='INVALID'
group by owner, object_type
order by owner, object_type;
"

append_command "Backup Configuration - OS and RMAN" "sudo -u $ORACLE_USER crontab -l 2>/dev/null || echo no oracle crontab entries; [ -x \"$ORACLE_HOME/bin/rman\" ] && sudo -u $ORACLE_USER -E ORACLE_HOME=\"$ORACLE_HOME\" ORACLE_SID=\"$ORACLE_SID\" PATH=\"$ORACLE_HOME/bin:$PATH\" \"$ORACLE_HOME/bin/rman\" target / <<'RMAN'\nshow all;\nexit\nRMAN"

append_sql_section "Backup Configuration - Scheduler and Last Backup" "
select owner, job_name, enabled, state, repeat_interval
from dba_scheduler_jobs
where upper(job_name) like '%BACKUP%' or upper(job_action) like '%RMAN%'
order by owner, job_name;
select to_char(max(completion_time),'YYYY-MM-DD HH24:MI:SS') as last_backup_time,
       max(input_type) keep (dense_rank last order by completion_time) as last_input_type,
       max(output_device_type) keep (dense_rank last order by completion_time) as last_output_device
from v\$rman_backup_job_details
where status='COMPLETED';
"

append_sql_section "Database Links" "
select owner, db_link, host, username from dba_db_links order by owner, db_link;
"

append_sql_section "Materialized Views" "
select owner, mview_name, refresh_method, refresh_mode,
       to_char(last_refresh_date,'YYYY-MM-DD HH24:MI:SS') as last_refresh,
       to_char(next,'YYYY-MM-DD HH24:MI:SS') as next_refresh
from dba_mviews
order by owner, mview_name;
select log_owner, master, log_table from dba_mview_logs order by log_owner, master;
"

append_sql_section "Scheduler Jobs" "
select owner, job_name, job_type, enabled, state, repeat_interval,
       to_char(last_start_date,'YYYY-MM-DD HH24:MI:SS') as last_start,
       to_char(next_run_date,'YYYY-MM-DD HH24:MI:SS') as next_run,
       case
         when regexp_like(lower(nvl(job_action,'')||' '||nvl(program_name,'')||' '||nvl(schedule_name,'')), '(https?://|/|\\\\|credential|host|@)')
         then 'POTENTIAL_EXTERNAL_DEPENDENCY'
         else 'NONE'
       end as migration_flag
from dba_scheduler_jobs
order by owner, job_name;
"

append_sql_section "Data Guard Parameters" "
select name, value from v\$parameter
where name in ('db_unique_name','log_archive_config','log_archive_dest_1','log_archive_dest_2','fal_server','fal_client','standby_file_management')
order by name;
"

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

echo "Source discovery text report: $OUT_TXT"
echo "Source discovery json report: $OUT_JSON"

exit 0
