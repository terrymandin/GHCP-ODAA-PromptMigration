#!/bin/bash
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration

set -u
set -o pipefail

ORACLE_USER="${ORACLE_USER:-oracle}"
SOURCE_REMOTE_ORACLE_HOME_DEFAULT="/u01/app/oracle/product/19.0.0/dbhome_1"
SOURCE_ORACLE_SID_DEFAULT="POCAKV"
SOURCE_DATABASE_UNIQUE_NAME_DEFAULT="POCAKV"

HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_TXT="./zdm_source_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
REPORT_JSON="./zdm_source_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

WARNINGS=()
FAILED_SECTIONS=()

log_header() {
  local title="$1"
  {
    echo
    echo "============================================================"
    echo "$title"
    echo "============================================================"
  } >> "$REPORT_TXT"
}

log_raw() {
  printf '%s\n' "$1" >> "$REPORT_TXT"
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\r//g; :a;N;$!ba;s/\n/\\n/g'
}

add_warning() {
  WARNINGS+=("$1")
  log_raw "[WARN] $1"
}

add_failure() {
  FAILED_SECTIONS+=("$1")
  log_raw "[ERROR] Section failed: $1"
}

run_cmd_section() {
  local section="$1"
  local cmd="$2"
  log_header "$section"
  bash -lc "$cmd" >> "$REPORT_TXT" 2>&1
  local rc=$?
  if [ $rc -ne 0 ]; then
    add_failure "$section"
  fi
}

resolve_oracle_sid() {
  if [ -n "${ORACLE_SID:-}" ]; then
    printf '%s\n' "$ORACLE_SID"
    return
  fi

  if [ -n "${SOURCE_ORACLE_SID:-}" ]; then
    printf '%s\n' "$SOURCE_ORACLE_SID"
    return
  fi

  if [ -n "$SOURCE_ORACLE_SID_DEFAULT" ]; then
    printf '%s\n' "$SOURCE_ORACLE_SID_DEFAULT"
    return
  fi

  local sid
  sid="$(awk -F: '$1 !~ /^#/ && NF >= 2 && $1 != "" && $2 != "" {print $1; exit}' /etc/oratab 2>/dev/null)"
  if [ -n "$sid" ]; then
    printf '%s\n' "$sid"
    return
  fi

  sid="$(ps -ef | grep ora_pmon_ | grep -v grep | head -n1 | sed 's/.*ora_pmon_//')"
  printf '%s\n' "$sid"
}

resolve_oracle_home() {
  if [ -n "${ORACLE_HOME:-}" ]; then
    printf '%s\n' "$ORACLE_HOME"
    return
  fi

  if [ -n "${SOURCE_REMOTE_ORACLE_HOME:-}" ]; then
    printf '%s\n' "$SOURCE_REMOTE_ORACLE_HOME"
    return
  fi

  if [ -n "$SOURCE_REMOTE_ORACLE_HOME_DEFAULT" ]; then
    printf '%s\n' "$SOURCE_REMOTE_ORACLE_HOME_DEFAULT"
    return
  fi

  local sid="${1:-}"
  local home
  if [ -n "$sid" ]; then
    home="$(awk -F: -v sid="$sid" '$1 == sid {print $2; exit}' /etc/oratab 2>/dev/null)"
    if [ -n "$home" ]; then
      printf '%s\n' "$home"
      return
    fi
  fi

  for p in /u01/app/oracle/product/*/dbhome_1 /u02/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1; do
    if [ -d "$p" ]; then
      printf '%s\n' "$p"
      return
    fi
  done

  if [ -f /usr/local/bin/oraenv ] || [ -f /usr/bin/oraenv ]; then
    home="$(ORAENV_ASK=NO ORACLE_SID="${sid:-}" . oraenv >/dev/null 2>&1; printf '%s' "${ORACLE_HOME:-}")"
    if [ -n "$home" ]; then
      printf '%s\n' "$home"
      return
    fi
  fi

  printf '%s\n' ""
}

run_sql_section() {
  local section="$1"
  local sql_text="$2"

  log_header "$section"

  if [ -z "$EFFECTIVE_ORACLE_HOME" ] || [ -z "$EFFECTIVE_ORACLE_SID" ]; then
    add_failure "$section"
    add_warning "Skipped SQL for '$section' because ORACLE_HOME/ORACLE_SID could not be resolved"
    return
  fi

  if [ ! -x "$EFFECTIVE_ORACLE_HOME/bin/sqlplus" ]; then
    add_failure "$section"
    add_warning "sqlplus not executable at $EFFECTIVE_ORACLE_HOME/bin/sqlplus"
    return
  fi

  if [ "$(whoami)" != "$ORACLE_USER" ]; then
    printf '%s\n' "$sql_text" | sudo -u "$ORACLE_USER" -E env ORACLE_HOME="$EFFECTIVE_ORACLE_HOME" ORACLE_SID="$EFFECTIVE_ORACLE_SID" PATH="$EFFECTIVE_ORACLE_HOME/bin:$PATH" "$EFFECTIVE_ORACLE_HOME/bin/sqlplus" -s / as sysdba >> "$REPORT_TXT" 2>&1
  else
    printf '%s\n' "$sql_text" | env ORACLE_HOME="$EFFECTIVE_ORACLE_HOME" ORACLE_SID="$EFFECTIVE_ORACLE_SID" PATH="$EFFECTIVE_ORACLE_HOME/bin:$PATH" "$EFFECTIVE_ORACLE_HOME/bin/sqlplus" -s / as sysdba >> "$REPORT_TXT" 2>&1
  fi

  local rc=$?
  if [ $rc -ne 0 ]; then
    add_failure "$section"
  fi
}

EFFECTIVE_ORACLE_SID="$(resolve_oracle_sid)"
EFFECTIVE_ORACLE_HOME="$(resolve_oracle_home "$EFFECTIVE_ORACLE_SID")"

{
  echo "# ZDM Source Discovery Report"
  echo "# Host: $HOSTNAME_SHORT"
  echo "# Timestamp: $TIMESTAMP"
  echo "# Oracle user: $ORACLE_USER"
  echo "# Resolved ORACLE_SID: ${EFFECTIVE_ORACLE_SID:-<unset>}"
  echo "# Resolved ORACLE_HOME: ${EFFECTIVE_ORACLE_HOME:-<unset>}"
  echo "# Source DB Unique Name (rendered): $SOURCE_DATABASE_UNIQUE_NAME_DEFAULT"
} > "$REPORT_TXT"

if [ -z "$EFFECTIVE_ORACLE_SID" ]; then
  add_warning "ORACLE_SID could not be resolved"
fi
if [ -z "$EFFECTIVE_ORACLE_HOME" ]; then
  add_warning "ORACLE_HOME could not be resolved"
fi

run_cmd_section "OS - Host, IP, OS version, disk" "hostname -f; ip -o -4 addr show; cat /etc/os-release; df -h"
run_cmd_section "Oracle Environment - runtime variables" "echo ORACLE_HOME=${EFFECTIVE_ORACLE_HOME:-}; echo ORACLE_SID=${EFFECTIVE_ORACLE_SID:-}; echo ORACLE_BASE=${ORACLE_BASE:-}"
run_cmd_section "Network files" "if [ -n '$EFFECTIVE_ORACLE_HOME' ]; then lsnrctl status; cat '$EFFECTIVE_ORACLE_HOME/network/admin/tnsnames.ora' 2>/dev/null; cat '$EFFECTIVE_ORACLE_HOME/network/admin/sqlnet.ora' 2>/dev/null; fi"
run_cmd_section "Authentication files" "ls -la ~/.ssh 2>/dev/null; if [ -n '$EFFECTIVE_ORACLE_HOME' ]; then ls -la '$EFFECTIVE_ORACLE_HOME/dbs/orapw*' 2>/dev/null; fi"

run_sql_section "Database configuration" "set pages 200 lines 300
col name format a20
col db_unique_name format a30
select name, db_unique_name, dbid, database_role, open_mode, log_mode, force_logging, cdb from v\$database;
select parameter, value from nls_database_parameters where parameter in ('NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET');
select supplemental_log_data_min, supplemental_log_data_pk, supplemental_log_data_ui, supplemental_log_data_fk, supplemental_log_data_all from v\$database;
exit"

run_sql_section "Container database details" "set pages 200 lines 300
select name, open_mode from v\$pdbs;
exit"

run_sql_section "TDE and wallet status" "set pages 200 lines 300
select wallet_type, status, wallet_order, con_id from v\$encryption_wallet;
select tablespace_name, encrypted from dba_tablespaces where encrypted='YES';
exit"

run_sql_section "Tablespace and autoextend" "set pages 200 lines 300
col file_name format a80
select tablespace_name, autoextensible, bytes/1024/1024 current_mb, maxbytes/1024/1024 max_mb, increment_by from dba_data_files order by tablespace_name, file_name;
exit"

run_sql_section "Redo and archive destinations" "set pages 200 lines 300
select group#, thread#, bytes/1024/1024 size_mb, members, status from v\$log order by group#;
select dest_id, destination, status, target from v\$archive_dest where destination is not null;
exit"

run_sql_section "Schema sizing and invalid objects" "set pages 200 lines 300
col owner format a30
select owner, round(sum(bytes)/1024/1024,2) size_mb from dba_segments group by owner having sum(bytes) > 100*1024*1024 and owner not in ('SYS','SYSTEM','XDB','SYSMAN','DBSNMP') order by size_mb desc;
select owner, object_type, count(*) cnt from dba_objects where status='INVALID' group by owner, object_type order by owner, object_type;
exit"

run_sql_section "Backup configuration and recent backup" "set pages 200 lines 300
select name, value from v\$parameter where name in ('db_recovery_file_dest','db_recovery_file_dest_size','log_archive_dest_1');
select completion_time, input_type, status, output_device_type from v\$rman_backup_job_details order by completion_time desc fetch first 20 rows only;
select owner, job_name, enabled, state, repeat_interval from dba_scheduler_jobs where upper(job_name) like '%BACKUP%' order by owner, job_name;
exit"

run_sql_section "Database links" "set pages 200 lines 300
col db_link format a40
select owner, db_link, host, username from dba_db_links order by owner, db_link;
exit"

run_sql_section "Materialized views and logs" "set pages 200 lines 300
select owner, mview_name, refresh_mode, refresh_method, staleness, last_refresh_type from dba_mviews order by owner, mview_name;
select log_owner, master, log_table from dba_mview_logs order by log_owner, master;
exit"

run_sql_section "Scheduler jobs" "set pages 200 lines 300
select owner, job_name, job_type, enabled, state, last_start_date, next_run_date from dba_scheduler_jobs order by owner, job_name;
select owner, job_name from dba_scheduler_jobs where lower(job_action) like '%/%' or lower(job_action) like '%http%' or lower(job_action) like '%host%' order by owner, job_name;
exit"

run_sql_section "Data Guard parameters" "set pages 200 lines 300
select name, value from v\$parameter where name like 'log_archive_config' or name like 'fal_%' or name like 'dg_broker_start';
exit"

STATUS="success"
if [ ${#FAILED_SECTIONS[@]} -gt 0 ] || [ ${#WARNINGS[@]} -gt 0 ]; then
  STATUS="partial"
fi

{
  echo "{"
  echo "  \"status\": \"$(json_escape "$STATUS")\"," 
  echo "  \"host\": \"$(json_escape "$HOSTNAME_SHORT")\"," 
  echo "  \"timestamp\": \"$(json_escape "$TIMESTAMP")\"," 
  echo "  \"oracle_sid\": \"$(json_escape "$EFFECTIVE_ORACLE_SID")\"," 
  echo "  \"oracle_home\": \"$(json_escape "$EFFECTIVE_ORACLE_HOME")\"," 
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
  echo "  ],"
  echo "  \"failed_sections\": ["
  if [ ${#FAILED_SECTIONS[@]} -gt 0 ]; then
    for i in "${!FAILED_SECTIONS[@]}"; do
      comma=","
      if [ "$i" -eq "$(( ${#FAILED_SECTIONS[@]} - 1 ))" ]; then
        comma=""
      fi
      echo "    \"$(json_escape "${FAILED_SECTIONS[$i]}")\"$comma"
    done
  fi
  echo "  ]"
  echo "}"
} > "$REPORT_JSON"

echo "Text report: $REPORT_TXT"
echo "JSON report: $REPORT_JSON"

exit 0
