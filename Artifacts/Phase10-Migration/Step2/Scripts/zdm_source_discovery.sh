#!/bin/bash
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration

set -u

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
HOSTNAME_SAFE="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)"
RAW_OUT="./zdm_source_discovery_${HOSTNAME_SAFE}_${TIMESTAMP}.txt"
JSON_OUT="./zdm_source_discovery_${HOSTNAME_SAFE}_${TIMESTAMP}.json"

SOURCE_HOST="${SOURCE_HOST:-}"
SOURCE_ADMIN_USER="${SOURCE_ADMIN_USER:-${SOURCE_SSH_USER:-azureuser}}"
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-}"
ORACLE_USER="${ORACLE_USER:-oracle}"
SOURCE_REMOTE_ORACLE_HOME="${SOURCE_REMOTE_ORACLE_HOME:-/u01/app/oracle/product/19.0.0/dbhome_1}"
SOURCE_ORACLE_SID="${SOURCE_ORACLE_SID:-POCAKV}"
SOURCE_DATABASE_UNIQUE_NAME="${SOURCE_DATABASE_UNIQUE_NAME:-POCAKV}"

WARNINGS=()
SECTION_FAILS=0

is_placeholder() { [[ "$1" == *"<"*">"* ]]; }
[ -n "$SOURCE_SSH_KEY" ] && is_placeholder "$SOURCE_SSH_KEY" && SOURCE_SSH_KEY=""

log() { printf '%s\n' "$*" | tee -a "$RAW_OUT"; }
warn() {
  WARNINGS+=("$*")
  printf '[WARN] %s\n' "$*" | tee -a "$RAW_OUT"
}
section() { log ""; log "==== $* ===="; }

run_cmd() {
  local label="$1"
  shift
  log "[CMD] $label"
  if "$@" >>"$RAW_OUT" 2>&1; then
    return 0
  fi
  warn "Command failed: $label"
  SECTION_FAILS=$((SECTION_FAILS + 1))
  return 1
}

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/ }"
  printf '%s' "$s"
}

find_oracle_sid() {
  if [ -n "${ORACLE_SID:-}" ]; then
    printf '%s' "$ORACLE_SID"
    return 0
  fi
  if [ -n "$SOURCE_ORACLE_SID" ] && ! is_placeholder "$SOURCE_ORACLE_SID"; then
    printf '%s' "$SOURCE_ORACLE_SID"
    return 0
  fi

  local sid
  sid="$(awk -F: '$1 !~ /^#/ && $1 != "" { print $1; exit }' /etc/oratab 2>/dev/null)"
  if [ -n "$sid" ]; then
    printf '%s' "$sid"
    return 0
  fi

  sid="$(ps -ef 2>/dev/null | awk '/ora_pmon_/ && !/awk/ { sub(/^.*ora_pmon_/, "", $NF); print $NF; exit }')"
  printf '%s' "$sid"
}

find_oracle_home() {
  local sid="$1"

  if [ -n "${ORACLE_HOME:-}" ] && [ -x "${ORACLE_HOME}/bin/sqlplus" ]; then
    printf '%s' "$ORACLE_HOME"
    return 0
  fi

  local from_oratab
  from_oratab="$(awk -F: -v sid="$sid" 'sid=="" || $1==sid { if ($2!="" && $2!="*") { print $2; exit } }' /etc/oratab 2>/dev/null)"
  if [ -n "$from_oratab" ] && [ -x "$from_oratab/bin/sqlplus" ]; then
    printf '%s' "$from_oratab"
    return 0
  fi

  local pmon_sid
  pmon_sid="$(ps -ef 2>/dev/null | awk '/ora_pmon_/ && !/awk/ { sub(/^.*ora_pmon_/, "", $NF); print $NF; exit }')"
  if [ -n "$pmon_sid" ]; then
    from_oratab="$(awk -F: -v sid="$pmon_sid" '$1==sid { if ($2!="" && $2!="*") { print $2; exit } }' /etc/oratab 2>/dev/null)"
    if [ -n "$from_oratab" ] && [ -x "$from_oratab/bin/sqlplus" ]; then
      printf '%s' "$from_oratab"
      return 0
    fi
  fi

  for p in \
    "$SOURCE_REMOTE_ORACLE_HOME" \
    /u01/app/oracle/product/19.0.0/dbhome_1 \
    /u01/app/oracle/product/21.0.0/dbhome_1 \
    /u02/app/oracle/product/19.0.0/dbhome_1 \
    /opt/oracle/product/19c/dbhome_1
  do
    if [ -n "$p" ] && [ -x "$p/bin/sqlplus" ]; then
      printf '%s' "$p"
      return 0
    fi
  done

  if command -v oraenv >/dev/null 2>&1; then
    printf '%s' "$(ORAENV_ASK=NO ORACLE_SID="$sid" . oraenv >/dev/null 2>&1; printf '%s' "${ORACLE_HOME:-}")"
    return 0
  fi
  if command -v coraenv >/dev/null 2>&1; then
    printf '%s' "$(ORAENV_ASK=NO ORACLE_SID="$sid" . coraenv >/dev/null 2>&1; printf '%s' "${ORACLE_HOME:-}")"
    return 0
  fi

  printf ''
}

run_sql() {
  local label="$1"
  local sql_text="$2"
  local oh="$3"
  local sid="$4"

  log "[SQL] $label"
  if [ -z "$oh" ] || [ -z "$sid" ] || [ ! -x "$oh/bin/sqlplus" ]; then
    warn "Skipping SQL section '$label' (ORACLE_HOME/ORACLE_SID/sqlplus unresolved)"
    SECTION_FAILS=$((SECTION_FAILS + 1))
    return 1
  fi

  if ! printf '%s\n' "$sql_text" | sudo -u "$ORACLE_USER" env ORACLE_HOME="$oh" ORACLE_SID="$sid" PATH="$oh/bin:$PATH" bash -lc '
set -u
cat | "$ORACLE_HOME/bin/sqlplus" -s / as sysdba
' >>"$RAW_OUT" 2>&1; then
    warn "SQL section failed: $label"
    SECTION_FAILS=$((SECTION_FAILS + 1))
    return 1
  fi

  return 0
}

write_json_summary() {
  local status="success"
  if [ "$SECTION_FAILS" -gt 0 ]; then
    status="partial"
  fi

  {
    printf '{\n'
    printf '  "status": "%s",\n' "$status"
    printf '  "type": "source",\n'
    printf '  "host": "%s",\n' "$(json_escape "$HOSTNAME_SAFE")"
    printf '  "timestamp": "%s",\n' "$TIMESTAMP"
    printf '  "raw_output": "%s",\n' "$(json_escape "$RAW_OUT")"
    printf '  "warnings": ['
    if [ "${#WARNINGS[@]}" -gt 0 ]; then
      printf '\n'
      local i
      for i in "${!WARNINGS[@]}"; do
        printf '    "%s"' "$(json_escape "${WARNINGS[$i]}")"
        if [ "$i" -lt $(( ${#WARNINGS[@]} - 1 )) ]; then
          printf ','
        fi
        printf '\n'
      done
      printf '  '
    fi
    printf ']\n'
    printf '}\n'
  } >"$JSON_OUT"
}

main() {
  : >"$RAW_OUT"

  section "Connectivity and auth context"
  log "source_host=${SOURCE_HOST:-unset}"
  log "source_admin_user=$SOURCE_ADMIN_USER"
  log "source_ssh_key_mode=$([ -n "$SOURCE_SSH_KEY" ] && echo explicit || echo default-agent)"

  section "Remote system details"
  run_cmd "hostname" hostname
  run_cmd "uname" uname -a
  run_cmd "uptime" uptime
  run_cmd "os-release" bash -lc 'if [ -f /etc/os-release ]; then cat /etc/os-release; else echo /etc/os-release not found; fi'

  local sid
  local oh
  sid="$(find_oracle_sid)"
  oh="$(find_oracle_home "$sid")"

  section "Oracle environment details"
  log "oracle_sid=$sid"
  log "oracle_home=$oh"
  log "database_unique_name_config=$SOURCE_DATABASE_UNIQUE_NAME"
  run_cmd "/etc/oratab" bash -lc 'if [ -f /etc/oratab ]; then grep -v "^#" /etc/oratab; else echo /etc/oratab not found; fi'
  run_cmd "PMON" bash -lc 'ps -ef | awk "/ora_pmon_/ && !/awk/ {print \$NF}"'
  run_cmd "sqlplus version" bash -lc 'if [ -x "'"$oh"'"/bin/sqlplus" ]; then "'"$oh"'"/bin/sqlplus -v; else echo sqlplus-not-found; fi'

  section "Database core configuration"
  run_sql "db identity and mode" "set pages 200 lines 300 trimspool on feedback on
select name, db_unique_name, database_role, open_mode, platform_name from v\$database;
select parameter, value from nls_database_parameters where parameter in ('NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET');
select log_mode, force_logging, supplemental_log_data_min, supplemental_log_data_pk, supplemental_log_data_ui from v\$database;
" "$oh" "$sid"

  section "CDB and PDB posture"
  run_sql "cdb pdb status" "set pages 200 lines 300 trimspool on feedback on
select cdb from v\$database;
select name, open_mode from v\$pdbs;
" "$oh" "$sid"

  section "TDE status"
  run_sql "wallet and encrypted tablespaces" "set pages 200 lines 300 trimspool on feedback on
select wallet_type, wallet_order, status, wallet_type from v\$encryption_wallet;
select tablespace_name, encrypted from dba_tablespaces order by tablespace_name;
" "$oh" "$sid"

  section "Tablespace and datafile posture"
  run_sql "tablespace sizing" "set pages 400 lines 300 trimspool on feedback on
select tablespace_name, autoextensible, sum(bytes)/1024/1024 current_mb, sum(maxbytes)/1024/1024 max_mb
from dba_data_files
group by tablespace_name, autoextensible
order by tablespace_name;
" "$oh" "$sid"

  section "Redo and archive posture"
  run_sql "redo groups and archive destinations" "set pages 400 lines 300 trimspool on feedback on
select group#, thread#, sequence#, bytes/1024/1024 size_mb, archived, status from v\$log order by group#;
select group#, member from v\$logfile order by group#, member;
select dest_id, status, destination, target from v\$archive_dest where status <> 'INACTIVE' order by dest_id;
" "$oh" "$sid"

  section "Network config"
  run_cmd "listener status" bash -lc 'if command -v lsnrctl >/dev/null 2>&1; then lsnrctl status; else echo lsnrctl-not-found; fi'
  run_cmd "tnsnames.ora" bash -lc 'if [ -n "'"$oh"'" ] && [ -f "'"$oh"'"/network/admin/tnsnames.ora ]; then cat "'"$oh"'"/network/admin/tnsnames.ora; else echo tnsnames.ora-not-found; fi'
  run_cmd "sqlnet.ora" bash -lc 'if [ -n "'"$oh"'" ] && [ -f "'"$oh"'"/network/admin/sqlnet.ora ]; then cat "'"$oh"'"/network/admin/sqlnet.ora; else echo sqlnet.ora-not-found; fi'

  section "Authentication artifacts"
  run_cmd "password files" bash -lc 'ls -l "'"$oh"'"/dbs/orapw* 2>/dev/null || true; ls -l /etc/oracle/orapw* 2>/dev/null || true'
  run_cmd "ssh directory" bash -lc 'ls -la ~/.ssh 2>/dev/null || echo ~/.ssh-not-found'

  section "Schema posture"
  run_sql "schema sizes and invalid objects" "set pages 400 lines 300 trimspool on feedback on
select owner, round(sum(bytes)/1024/1024,2) mb from dba_segments
where owner not in ('SYS','SYSTEM','XDB','SYSMAN','DBSNMP','GSMADMIN_INTERNAL')
group by owner order by mb desc;
select owner, object_type, count(*) invalid_count from dba_objects
where status='INVALID'
group by owner, object_type order by invalid_count desc;
" "$oh" "$sid"

  section "Backup posture"
  run_cmd "crontab oracle" bash -lc 'crontab -u "'"$ORACLE_USER"'" -l 2>/dev/null || echo no-crontab'
  run_sql "rman backup evidence" "set pages 200 lines 300 trimspool on feedback on
select input_type, status, start_time, end_time from v\$rman_backup_job_details
order by start_time desc fetch first 20 rows only;
" "$oh" "$sid"

  section "Integration and data guard objects"
  run_sql "db links, mviews, scheduler jobs, dataguard params" "set pages 500 lines 300 trimspool on feedback on
select owner, db_link, host from dba_db_links order by owner, db_link;
select owner, mview_name, rewrite_enabled from dba_mviews order by owner, mview_name;
select log_owner, master from dba_mview_logs order by log_owner, master;
select owner, job_name, enabled, state from dba_scheduler_jobs order by owner, job_name;
select name, value from v\$parameter where name in ('db_unique_name','log_archive_config','fal_server','fal_client') order by name;
" "$oh" "$sid"

  write_json_summary
  log ""
  log "Discovery complete"
  log "raw_output=$RAW_OUT"
  log "json_output=$JSON_OUT"
}

main "$@"