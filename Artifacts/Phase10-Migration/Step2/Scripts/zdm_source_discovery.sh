#!/bin/bash
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration

set -u
set -o pipefail

DISCOVERY_TYPE="source"
HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_TXT="./zdm_${DISCOVERY_TYPE}_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
REPORT_JSON="./zdm_${DISCOVERY_TYPE}_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"
ORACLE_USER="${ORACLE_USER:-oracle}"

SOURCE_REMOTE_ORACLE_HOME="${SOURCE_REMOTE_ORACLE_HOME:-}"
SOURCE_ORACLE_SID="${SOURCE_ORACLE_SID:-}"
SOURCE_DATABASE_UNIQUE_NAME="${SOURCE_DATABASE_UNIQUE_NAME:-}"

WARNINGS=()
ERRORS=()

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\r//g; :a;N;$!ba;s/\n/\\n/g'
}

append_report() {
  printf '%s\n' "$1" >> "$REPORT_TXT"
}

warn() {
  WARNINGS+=("$1")
  append_report "[WARN] $1"
}

error_note() {
  ERRORS+=("$1")
  append_report "[ERROR] $1"
}

section() {
  append_report ""
  append_report "==================== $1 ===================="
}

run_cmd() {
  local title="$1"
  local cmd="$2"
  section "$title"
  local out
  out="$(bash -lc "$cmd" 2>&1)"
  if [ $? -ne 0 ]; then
    warn "$title command failed"
  fi
  append_report "$out"
}

find_home_from_oratab() {
  awk -F: '!/^#/ && NF>=2 && $2 !~ /^$/ {print $2; exit}' /etc/oratab 2>/dev/null
}

find_sid_from_oratab() {
  awk -F: '!/^#/ && NF>=2 && $1 !~ /^$/ {print $1; exit}' /etc/oratab 2>/dev/null
}

find_sid_from_pmon() {
  ps -ef 2>/dev/null | grep ora_pmon_ | grep -v grep | head -n 1 | sed 's/.*ora_pmon_//'
}

find_home_common_paths() {
  ls -d /u01/app/oracle/product/*/dbhome_1 /u02/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1 2>/dev/null | head -n 1
}

detect_oracle_env() {
  ORACLE_HOME_DETECTED=""
  ORACLE_SID_DETECTED=""

  if [ -n "${SOURCE_REMOTE_ORACLE_HOME}" ]; then
    ORACLE_HOME_DETECTED="$SOURCE_REMOTE_ORACLE_HOME"
  elif [ -n "${ORACLE_HOME:-}" ]; then
    ORACLE_HOME_DETECTED="$ORACLE_HOME"
  else
    ORACLE_HOME_DETECTED="$(find_home_from_oratab)"
    [ -z "$ORACLE_HOME_DETECTED" ] && ORACLE_HOME_DETECTED="$(find_home_common_paths)"
  fi

  if [ -n "${SOURCE_ORACLE_SID}" ]; then
    ORACLE_SID_DETECTED="$SOURCE_ORACLE_SID"
  elif [ -n "${ORACLE_SID:-}" ]; then
    ORACLE_SID_DETECTED="$ORACLE_SID"
  else
    ORACLE_SID_DETECTED="$(find_sid_from_oratab)"
    [ -z "$ORACLE_SID_DETECTED" ] && ORACLE_SID_DETECTED="$(find_sid_from_pmon)"
  fi

  if [ -z "$ORACLE_HOME_DETECTED" ] || [ -z "$ORACLE_SID_DETECTED" ]; then
    local oraenv_sid
    oraenv_sid="${ORACLE_SID_DETECTED:-$(find_sid_from_oratab)}"
    if [ -n "$oraenv_sid" ]; then
      local oraenv_home
      oraenv_home="$(ORACLE_SID="$oraenv_sid" ORAENV_ASK=NO bash -lc '. oraenv >/dev/null 2>&1 || . coraenv >/dev/null 2>&1; echo ${ORACLE_HOME:-}' 2>/dev/null)"
      [ -z "$ORACLE_HOME_DETECTED" ] && ORACLE_HOME_DETECTED="$oraenv_home"
      [ -z "$ORACLE_SID_DETECTED" ] && ORACLE_SID_DETECTED="$oraenv_sid"
    fi
  fi

  [ -z "$ORACLE_HOME_DETECTED" ] && warn "Could not auto-detect ORACLE_HOME"
  [ -z "$ORACLE_SID_DETECTED" ] && warn "Could not auto-detect ORACLE_SID"
}

run_sql() {
  local title="$1"
  local sql="$2"
  section "$title"

  if [ -z "${ORACLE_HOME_DETECTED:-}" ] || [ -z "${ORACLE_SID_DETECTED:-}" ]; then
    warn "Skipping SQL section '$title' because ORACLE environment is incomplete"
    append_report "ORACLE_HOME='$ORACLE_HOME_DETECTED' ORACLE_SID='$ORACLE_SID_DETECTED'"
    return 1
  fi

  local sqlplus_cmd="\"${ORACLE_HOME_DETECTED}/bin/sqlplus\" -s / as sysdba"
  local payload
  payload="set pages 500 lines 300 long 50000 trimspool on verify off feedback off timing off; ${sql}; exit;"

  local output
  if [ "$(whoami)" != "$ORACLE_USER" ]; then
    output="$(printf '%s\n' "$payload" | sudo -u "$ORACLE_USER" -E ORACLE_HOME="$ORACLE_HOME_DETECTED" ORACLE_SID="$ORACLE_SID_DETECTED" PATH="$ORACLE_HOME_DETECTED/bin:$PATH" bash -lc "$sqlplus_cmd" 2>&1)"
  else
    output="$(printf '%s\n' "$payload" | ORACLE_HOME="$ORACLE_HOME_DETECTED" ORACLE_SID="$ORACLE_SID_DETECTED" PATH="$ORACLE_HOME_DETECTED/bin:$PATH" bash -lc "$sqlplus_cmd" 2>&1)"
  fi

  if [ $? -ne 0 ]; then
    warn "SQL section '$title' failed"
  fi
  append_report "$output"
}

write_json() {
  local status="success"
  if [ ${#ERRORS[@]} -gt 0 ] || [ ${#WARNINGS[@]} -gt 0 ]; then
    status="partial"
  fi

  {
    echo "{"
    echo "  \"status\": \"$(json_escape "$status")\"," 
    echo "  \"type\": \"$(json_escape "$DISCOVERY_TYPE")\"," 
    echo "  \"host\": \"$(json_escape "$HOSTNAME_SHORT")\"," 
    echo "  \"timestamp\": \"$(json_escape "$TIMESTAMP")\"," 
    echo "  \"oracle\": {"
    echo "    \"oracle_user\": \"$(json_escape "$ORACLE_USER")\"," 
    echo "    \"oracle_home\": \"$(json_escape "${ORACLE_HOME_DETECTED:-}")\"," 
    echo "    \"oracle_sid\": \"$(json_escape "${ORACLE_SID_DETECTED:-}")\"," 
    echo "    \"source_database_unique_name\": \"$(json_escape "${SOURCE_DATABASE_UNIQUE_NAME:-}")\""
    echo "  },"
    echo "  \"warnings\": ["
    if [ ${#WARNINGS[@]} -gt 0 ]; then
      for i in "${!WARNINGS[@]}"; do
        comma=","
        [ "$i" -eq "$((${#WARNINGS[@]} - 1))" ] && comma=""
        echo "    \"$(json_escape "${WARNINGS[$i]}")\"${comma}"
      done
    fi
    echo "  ],"
    echo "  \"errors\": ["
    if [ ${#ERRORS[@]} -gt 0 ]; then
      for i in "${!ERRORS[@]}"; do
        comma=","
        [ "$i" -eq "$((${#ERRORS[@]} - 1))" ] && comma=""
        echo "    \"$(json_escape "${ERRORS[$i]}")\"${comma}"
      done
    fi
    echo "  ]"
    echo "}"
  } > "$REPORT_JSON"
}

append_report "# Source Discovery Report"
append_report "Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
append_report "Host: $HOSTNAME_SHORT"
append_report "Running User: $(whoami)"
append_report "Read-only mode: enabled"

detect_oracle_env

section "Resolved Oracle Environment"
append_report "ORACLE_USER=$ORACLE_USER"
append_report "ORACLE_HOME=$ORACLE_HOME_DETECTED"
append_report "ORACLE_SID=$ORACLE_SID_DETECTED"
append_report "SOURCE_DATABASE_UNIQUE_NAME=${SOURCE_DATABASE_UNIQUE_NAME:-}"

run_cmd "OS: Host, IP, OS, Disk" "hostname -f 2>/dev/null; ip -br addr 2>/dev/null || ip addr 2>/dev/null; cat /etc/os-release 2>/dev/null; df -h"
run_cmd "Oracle Environment Variables" "env | egrep '^(ORACLE_|TNS_|LD_LIBRARY_PATH=)' | sort"
run_cmd "Oracle Version (binary)" "[ -n '$ORACLE_HOME_DETECTED' ] && '$ORACLE_HOME_DETECTED/bin/sqlplus' -v 2>/dev/null || echo 'sqlplus binary not found'"

run_sql "Database Configuration" "select name, db_unique_name, dbid, database_role, open_mode, log_mode, force_logging from v\$database; select parameter, value from nls_database_parameters where parameter in ('NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET') order by parameter;"
run_sql "Supplemental Logging" "select supplemental_log_data_min, supplemental_log_data_pk, supplemental_log_data_ui, supplemental_log_data_fk, supplemental_log_data_all from v\$database;"
run_sql "Container Database and PDBs" "select cdb from v\$database; select con_id, name, open_mode from v\$pdbs order by con_id;"
run_sql "TDE / Wallet / Encrypted Tablespaces" "select wrl_type, wrl_parameter, status, wallet_type from v\$encryption_wallet; select tablespace_name, encrypted from dba_tablespaces where encrypted='YES' order by tablespace_name;"
run_sql "Tablespaces and Datafiles" "select tablespace_name, file_name, autoextensible, bytes/1024/1024 mb, maxbytes/1024/1024 max_mb, increment_by from dba_data_files order by tablespace_name, file_name;"
run_sql "Redo and Archive" "select group#, thread#, bytes/1024/1024 size_mb, members, status from v\$log order by group#; select group#, member from v\$logfile order by group#, member; select dest_id, destination, status, target from v\$archive_dest order by dest_id;"
run_cmd "Network Files and Listener" "lsnrctl status 2>/dev/null; [ -n '$ORACLE_HOME_DETECTED' ] && cat '$ORACLE_HOME_DETECTED/network/admin/tnsnames.ora' 2>/dev/null; [ -n '$ORACLE_HOME_DETECTED' ] && cat '$ORACLE_HOME_DETECTED/network/admin/sqlnet.ora' 2>/dev/null"
run_cmd "Authentication Files" "[ -n '$ORACLE_HOME_DETECTED' ] && ls -l '$ORACLE_HOME_DETECTED/dbs/orapw'* 2>/dev/null; ls -la ~/.ssh 2>/dev/null"
run_sql "Schema Sizing and Invalid Objects" "select owner, round(sum(bytes)/1024/1024,2) size_mb from dba_segments where owner not in ('SYS','SYSTEM','XDB','CTXSYS','MDSYS','OUTLN','DBSNMP') group by owner having sum(bytes) > 100*1024*1024 order by size_mb desc; select owner, object_type, count(*) invalid_count from dba_objects where status='INVALID' group by owner, object_type order by owner, object_type;"
run_cmd "RMAN and Scheduler Backup Signals" "crontab -l 2>/dev/null | egrep -i 'rman|backup|archivelog' || true"
run_sql "Backup Metadata" "select to_char(max(completion_time),'YYYY-MM-DD HH24:MI:SS') last_backup from v\$backup_set_details; select name, value from v\$parameter where name in ('db_recovery_file_dest','db_recovery_file_dest_size');"
run_sql "Database Links" "select owner, db_link, username, host from dba_db_links order by owner, db_link;"
run_sql "Materialized Views and Logs" "select owner, mview_name, refresh_method, refresh_mode, to_char(last_refresh_date,'YYYY-MM-DD HH24:MI:SS') last_refresh, to_char(staleness) staleness from dba_mviews order by owner, mview_name; select log_owner, master, log_table from dba_mview_logs order by log_owner, master;"
run_sql "Scheduler Jobs" "select owner, job_name, job_type, enabled, state, to_char(last_start_date,'YYYY-MM-DD HH24:MI:SS') last_start, to_char(next_run_date,'YYYY-MM-DD HH24:MI:SS') next_run from dba_scheduler_jobs order by owner, job_name;"
run_sql "Potential External Dependency Jobs" "select owner, job_name, job_action from dba_scheduler_jobs where lower(nvl(job_action,'x')) like '%http%' or lower(nvl(job_action,'x')) like '%/%' or lower(nvl(job_action,'x')) like '%credential%' order by owner, job_name;"
run_sql "Data Guard Parameters" "select name, value from v\$parameter where name like 'log_archive_config' or name like 'db_file_name_convert' or name like 'log_file_name_convert' or name like 'fal_%' order by name;"

if [ -n "${SOURCE_DATABASE_UNIQUE_NAME:-}" ]; then
  run_sql "Database Unique Name Check" "select name, db_unique_name from v\$database;"
fi

if [ ${#WARNINGS[@]} -gt 0 ]; then
  section "Warnings"
  for w in "${WARNINGS[@]}"; do
    append_report "- $w"
  done
fi

if [ ${#ERRORS[@]} -gt 0 ]; then
  section "Errors"
  for e in "${ERRORS[@]}"; do
    append_report "- $e"
  done
fi

write_json

echo "Source discovery report: $REPORT_TXT"
echo "Source discovery summary: $REPORT_JSON"

exit 0
