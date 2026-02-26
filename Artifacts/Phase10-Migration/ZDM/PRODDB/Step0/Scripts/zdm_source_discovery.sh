#!/bin/bash
# =============================================================================
# ZDM Source Database Discovery Script
# =============================================================================
# Project  : PRODDB Migration to Oracle Database@Azure
# Source   : proddb01.corp.example.com
# Generated: 2026-02-26
#
# USAGE:
#   ./zdm_source_discovery.sh
#
# Admin user SSHs in; SQL runs as oracle via sudo if needed.
# Set ORACLE_HOME_OVERRIDE / ORACLE_SID_OVERRIDE to force specific values.
# =============================================================================

# NO set -e  — continue even when individual checks fail
SECTION_ERRORS=0
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME_SHORT=$(hostname -s 2>/dev/null || hostname)
OUTPUT_FILE="./zdm_source_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_source_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

# ---------------------------------------------------------------------------
# Oracle user (can be overridden)
# ---------------------------------------------------------------------------
ORACLE_USER="${ORACLE_USER:-oracle}"

# ---------------------------------------------------------------------------
# Environment bootstrap (3-tier priority)
# ---------------------------------------------------------------------------
# Tier 1: explicit overrides from orchestration script
[ -n "${ORACLE_HOME_OVERRIDE:-}" ]  && export ORACLE_HOME="$ORACLE_HOME_OVERRIDE"
[ -n "${ORACLE_SID_OVERRIDE:-}"  ]  && export ORACLE_SID="$ORACLE_SID_OVERRIDE"
[ -n "${ORACLE_BASE_OVERRIDE:-}" ]  && export ORACLE_BASE="$ORACLE_BASE_OVERRIDE"

# Tier 2: extract export statements from shell profiles (bypasses interactive guards)
for _profile in /etc/profile /etc/profile.d/*.sh ~/.bash_profile ~/.bashrc; do
    [ -f "$_profile" ] || continue
    eval "$(grep -E '^export[[:space:]]+(ORACLE_HOME|ORACLE_SID|ORACLE_BASE|TNS_ADMIN|PATH)=' \
           "$_profile" 2>/dev/null)" 2>/dev/null || true
done

# Tier 3: auto-detect from oratab / pmon / common paths
detect_oracle_env() {
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then return 0; fi

    if [ -f /etc/oratab ]; then
        local entry
        if [ -n "${ORACLE_SID:-}" ]; then
            entry=$(grep -v '^#' /etc/oratab | grep "^${ORACLE_SID}:" | head -1)
        else
            entry=$(grep -v '^#' /etc/oratab | grep ':' | grep -v '^$' | head -1)
        fi
        if [ -n "$entry" ]; then
            export ORACLE_SID="${ORACLE_SID:-$(echo "$entry" | cut -d: -f1)}"
            export ORACLE_HOME="${ORACLE_HOME:-$(echo "$entry" | cut -d: -f2)}"
        fi
    fi

    if [ -z "${ORACLE_SID:-}" ]; then
        local pmon_sid
        pmon_sid=$(ps -ef 2>/dev/null | grep 'ora_pmon_' | grep -v grep | head -1 | sed 's/.*ora_pmon_//')
        [ -n "$pmon_sid" ] && export ORACLE_SID="$pmon_sid"
    fi

    if [ -z "${ORACLE_HOME:-}" ]; then
        for _path in /u01/app/oracle/product/*/dbhome_1 \
                     /u02/app/oracle/product/*/dbhome_1 \
                     /opt/oracle/product/*/dbhome_1 \
                     /oracle/product/*/dbhome_1; do
            if [ -d "$_path" ] && [ -f "$_path/bin/sqlplus" ]; then
                export ORACLE_HOME="$_path"
                break
            fi
        done
    fi

    if [ -n "${ORACLE_HOME:-}" ]; then
        export PATH="$ORACLE_HOME/bin:$PATH"
        export LD_LIBRARY_PATH="${ORACLE_HOME}/lib:${LD_LIBRARY_PATH:-}"
    fi
}
detect_oracle_env

# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
log_info()  { echo -e "${GREEN}[INFO ] $*${RESET}";  }
log_warn()  { echo -e "${YELLOW}[WARN ] $*${RESET}"; }
log_error() { echo -e "${RED}[ERROR] $*${RESET}";   }
log_section() {
    local bar="============================================================"
    echo ""
    echo -e "${CYAN}${BOLD}${bar}${RESET}" | tee -a "$OUTPUT_FILE"
    echo -e "${CYAN}${BOLD}  $*${RESET}"   | tee -a "$OUTPUT_FILE"
    echo -e "${CYAN}${BOLD}${bar}${RESET}" | tee -a "$OUTPUT_FILE"
    echo ""
}
tee_out() { tee -a "$OUTPUT_FILE"; }

# ---------------------------------------------------------------------------
# SQL helper — runs as ORACLE_USER via sudo when needed
# ---------------------------------------------------------------------------
run_sql() {
    local sql_query="$1"
    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        echo "ERROR: ORACLE_HOME or ORACLE_SID not set — skipping SQL query"
        return 1
    fi
    local sqlplus_cmd="$ORACLE_HOME/bin/sqlplus -s / as sysdba"
    local sql_script
    sql_script=$(cat <<EOSQL
SET PAGESIZE 5000
SET LINESIZE 220
SET FEEDBACK OFF
SET HEADING ON
SET ECHO OFF
SET TRIMSPOOL ON
COLUMN name FORMAT A40
COLUMN value FORMAT A60
$sql_query
EXIT
EOSQL
)
    if [ "$(id -un)" = "$ORACLE_USER" ]; then
        echo "$sql_script" | $sqlplus_cmd 2>&1
    else
        echo "$sql_script" | sudo -u "$ORACLE_USER" \
            env ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" \
            LD_LIBRARY_PATH="${ORACLE_HOME}/lib" PATH="$ORACLE_HOME/bin:$PATH" \
            $sqlplus_cmd 2>&1
    fi
}

run_sql_value() {
    local sql="$1"
    run_sql "
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
$sql
" 2>/dev/null | grep -v '^$' | head -1 | xargs
}

# ---------------------------------------------------------------------------
# Section wrapper — records failures but always continues
# ---------------------------------------------------------------------------
run_section() {
    local section_name="$1"
    local section_fn="$2"
    log_section "$section_name"
    if ! $section_fn 2>&1 | tee -a "$OUTPUT_FILE"; then
        log_warn "Section '$section_name' reported errors (continuing)"
        SECTION_ERRORS=$((SECTION_ERRORS + 1))
    fi
}

# ===========================================================================
# DISCOVERY SECTIONS
# ===========================================================================

section_os_info() {
    echo "Hostname     : $(hostname -f 2>/dev/null || hostname)"
    echo "Short name   : $(hostname -s 2>/dev/null || hostname)"
    echo "Date/Time    : $(date)"
    echo "Uptime       : $(uptime)"
    echo ""
    echo "--- IP Addresses ---"
    ip addr show 2>/dev/null || ifconfig 2>/dev/null || echo "N/A"
    echo ""
    echo "--- OS Version ---"
    cat /etc/os-release 2>/dev/null || cat /etc/redhat-release 2>/dev/null || uname -a
    echo ""
    echo "--- Kernel ---"
    uname -r
    echo ""
    echo "--- Disk Space ---"
    df -hP 2>/dev/null | column -t
    echo ""
    echo "--- Memory ---"
    free -h 2>/dev/null || vmstat 2>/dev/null | head -4
    echo ""
    echo "--- CPU ---"
    nproc 2>/dev/null && grep 'model name' /proc/cpuinfo 2>/dev/null | head -1
}

section_oracle_env() {
    echo "ORACLE_HOME  : ${ORACLE_HOME:-NOT SET}"
    echo "ORACLE_SID   : ${ORACLE_SID:-NOT SET}"
    echo "ORACLE_BASE  : ${ORACLE_BASE:-NOT SET}"
    echo "TNS_ADMIN    : ${TNS_ADMIN:-NOT SET}"
    echo "PATH         : $PATH"
    echo ""
    if [ -n "${ORACLE_HOME:-}" ]; then
        echo "--- Oracle Binary Version ---"
        "$ORACLE_HOME/bin/sqlplus" -V 2>&1 || echo "sqlplus not found"
        echo ""
        echo "--- /etc/oratab ---"
        cat /etc/oratab 2>/dev/null || echo "Not found"
    fi
    echo ""
    echo "--- Running Oracle Processes ---"
    ps -ef 2>/dev/null | grep '[o]ra_pmon' | awk '{print $NF, $1}' || echo "None found"
}

section_db_config() {
    echo "--- Core Database Parameters ---"
    run_sql "
SELECT name, value FROM v\$parameter
WHERE name IN ('db_name','db_unique_name','db_domain','instance_name',
               'log_archive_dest_1','log_archive_format',
               'enable_pluggable_database','db_block_size',
               'nls_characterset','nls_nchar_characterset',
               'compatible','undo_tablespace','audit_trail',
               'memory_target','pga_aggregate_target','sga_target')
ORDER BY name;"

    echo ""
    echo "--- Database Identity ---"
    run_sql "SELECT name, db_unique_name, dbid, log_mode, open_mode,
    force_logging, flashback_on, database_role, platform_name
FROM v\$database;"

    echo ""
    echo "--- Database Size ---"
    run_sql "
SELECT 'Data Files (GB)'  AS component,
       ROUND(SUM(bytes)/1024/1024/1024,2) AS size_gb
FROM   dba_data_files
UNION ALL
SELECT 'Temp Files (GB)',
       ROUND(SUM(bytes)/1024/1024/1024,2)
FROM   dba_temp_files
UNION ALL
SELECT 'Redo Logs (MB)',
       ROUND(SUM(bytes)/1024/1024,2)
FROM   v\$log;"

    echo ""
    echo "--- Character Sets ---"
    run_sql "
SELECT parameter, value FROM nls_database_parameters
WHERE parameter IN ('NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET','NLS_LANGUAGE','NLS_TERRITORY')
ORDER BY parameter;"
}

section_cdb_pdb() {
    echo "--- CDB Status ---"
    local cdb_flag
    cdb_flag=$(run_sql_value "SELECT cdb FROM v\$database;")
    echo "CDB: $cdb_flag"
    echo ""
    if [ "$cdb_flag" = "YES" ]; then
        echo "--- PDB List ---"
        run_sql "SELECT con_id, name, open_mode, restricted FROM v\$pdbs ORDER BY con_id;"
        echo ""
        echo "--- PDB Sizes ---"
        run_sql "
SELECT p.name AS pdb_name,
       ROUND(SUM(df.bytes)/1024/1024/1024,2) AS size_gb
FROM   v\$pdbs p
JOIN   cdb_data_files df ON df.con_id = p.con_id
GROUP  BY p.name
ORDER  BY p.name;"
    else
        echo "Not a CDB — standard (non-container) database"
    fi
}

section_tde() {
    echo "--- TDE Wallet Status ---"
    run_sql "
SELECT wrl_type, wrl_parameter, status, wallet_type, con_id
FROM   v\$encryption_wallet ORDER BY con_id;"

    echo ""
    echo "--- Encrypted Tablespaces ---"
    run_sql "
SELECT tablespace_name, encrypted FROM dba_tablespaces
WHERE encrypted = 'YES' ORDER BY tablespace_name;"

    echo ""
    echo "--- TDE Master Key ---"
    run_sql "
SELECT key_id, creation_time, activation_time, status, backed_up, con_id
FROM   v\$encryption_keys ORDER BY creation_time DESC;" 2>/dev/null || echo "v\$encryption_keys not accessible"

    echo ""
    echo "--- sqlnet.ora / Wallet Location ---"
    local tns_admin="${TNS_ADMIN:-${ORACLE_HOME}/network/admin}"
    cat "$tns_admin/sqlnet.ora" 2>/dev/null || echo "sqlnet.ora not found at $tns_admin"
}

section_supplemental_logging() {
    echo "--- Supplemental Logging Status ---"
    run_sql "
SELECT supplemental_log_data_min AS min_,
       supplemental_log_data_pk  AS pk_,
       supplemental_log_data_ui  AS ui_,
       supplemental_log_data_fk  AS fk_,
       supplemental_log_data_all AS all_
FROM   v\$database;"

    echo ""
    echo "--- Supplemental Log Groups (if any) ---"
    run_sql "
SELECT log_group_name, table_name, log_group_type FROM dba_log_groups
ORDER BY table_name, log_group_name;"
}

section_redo_archive() {
    echo "--- Redo Log Groups ---"
    run_sql "
SELECT l.group#, l.members, l.status,
       ROUND(l.bytes/1024/1024,0) AS size_mb,
       lf.member
FROM   v\$log l JOIN v\$logfile lf ON l.group# = lf.group#
ORDER  BY l.group#, lf.member;"

    echo ""
    echo "--- Archive Log Destinations ---"
    run_sql "
SELECT dest_id, dest_name, target, archiver, schedule,
       destination, status, db_unique_name
FROM   v\$archive_dest WHERE status != 'INACTIVE'
ORDER  BY dest_id;" 2>/dev/null

    echo ""
    echo "--- Archive Log Mode & Last Sequence ---"
    run_sql "
SELECT log_mode, current_scn,
       to_char(SYSDATE,'YYYY-MM-DD HH24:MI:SS') AS sysdate_now
FROM   v\$database;"

    run_sql "
SELECT MAX(sequence#) AS last_archlog_seq FROM v\$archived_log
WHERE  standby_dest = 'NO';" 2>/dev/null
}

section_network_config() {
    local tns_admin="${TNS_ADMIN:-${ORACLE_HOME}/network/admin}"
    echo "--- Listener Status ---"
    if [ -n "${ORACLE_HOME:-}" ]; then
        "$ORACLE_HOME/bin/lsnrctl" status 2>&1 || echo "lsnrctl not available"
    else
        echo "ORACLE_HOME not set"
    fi

    echo ""
    echo "--- tnsnames.ora ($tns_admin) ---"
    cat "$tns_admin/tnsnames.ora" 2>/dev/null || echo "Not found"

    echo ""
    echo "--- sqlnet.ora ($tns_admin) ---"
    cat "$tns_admin/sqlnet.ora" 2>/dev/null || echo "Not found"

    echo ""
    echo "--- listener.ora ($tns_admin) ---"
    cat "$tns_admin/listener.ora" 2>/dev/null || echo "Not found"

    echo ""
    echo "--- Open TCP Ports (Oracle-related) ---"
    ss -tlnp 2>/dev/null | grep -E '1521|1522|5500|1158' || \
    netstat -tlnp 2>/dev/null | grep -E '1521|1522|5500|1158' || echo "N/A"
}

section_auth() {
    echo "--- Password File ---"
    if [ -n "${ORACLE_HOME:-}" ]; then
        find "$ORACLE_HOME/dbs" -name 'orapw*' -o -name 'PWD*' 2>/dev/null | head -10
        ls -la "$ORACLE_HOME/dbs"/orapw* "$ORACLE_HOME/dbs"/PWD* 2>/dev/null || echo "No password file found in dbs"
    fi
    echo ""
    echo "--- SSH Directory for $ORACLE_USER ---"
    if sudo test -d "${HOME}/.ssh" 2>/dev/null; then
        sudo ls -la "${HOME}/.ssh/" 2>/dev/null || echo "Cannot list SSH dir"
    fi
    local oracle_home_dir
    oracle_home_dir=$(eval echo "~$ORACLE_USER" 2>/dev/null)
    if [ -d "$oracle_home_dir/.ssh" ] 2>/dev/null; then
        echo "Oracle user SSH dir: $oracle_home_dir/.ssh"
        sudo -u "$ORACLE_USER" ls -la "$oracle_home_dir/.ssh/" 2>/dev/null || \
            ls -la "$oracle_home_dir/.ssh/" 2>/dev/null || echo "Cannot list oracle SSH dir"
    else
        echo "Oracle user SSH dir not found (this is NOT a blocker — sudo pattern is used)"
    fi
}

section_data_guard() {
    echo "--- Data Guard Configuration ---"
    run_sql "
SELECT name, value FROM v\$parameter
WHERE name IN ('log_archive_config','log_archive_dest_1','log_archive_dest_2',
               'fal_server','fal_client','standby_file_management',
               'db_file_name_convert','log_file_name_convert',
               'dg_broker_start','dg_broker_config_file1','dg_broker_config_file2')
ORDER BY name;" 2>/dev/null

    echo ""
    echo "--- DG Broker Status (if available) ---"
    if [ -n "${ORACLE_HOME:-}" ]; then
        echo "EXIT" | sudo -u "$ORACLE_USER" env ORACLE_HOME="$ORACLE_HOME" \
            ORACLE_SID="$ORACLE_SID" \
            "$ORACLE_HOME/bin/dgmgrl" / "show configuration" 2>/dev/null || \
        echo "DG Broker not configured or not accessible"
    fi
}

section_schema_info() {
    echo "--- Schema Sizes (non-system schemas > 100MB) ---"
    run_sql "
SELECT owner,
       ROUND(SUM(bytes)/1024/1024/1024,3) AS size_gb,
       COUNT(*) AS segment_count
FROM   dba_segments
WHERE  owner NOT IN ('SYS','SYSTEM','DBSNMP','APPQOSSYS','AUDSYS',
                     'CTXSYS','DVSYS','GSMADMIN_INTERNAL','LBACSYS',
                     'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS',
                     'OUTLN','WMSYS','XDB','EXFSYS','FLOWS_FILES')
GROUP  BY owner
HAVING SUM(bytes) > 100*1024*1024
ORDER  BY size_gb DESC;"

    echo ""
    echo "--- Invalid Objects by Owner/Type ---"
    run_sql "
SELECT owner, object_type, COUNT(*) AS invalid_count
FROM   dba_objects
WHERE  status = 'INVALID'
GROUP  BY owner, object_type
ORDER  BY owner, object_type;"

    echo ""
    echo "--- Top 20 Largest Segments ---"
    run_sql "
SELECT owner, segment_name, segment_type,
       ROUND(bytes/1024/1024/1024,3) AS size_gb
FROM   dba_segments
ORDER  BY bytes DESC FETCH FIRST 20 ROWS ONLY;"
}

# -----------------------------------------------------------------------
# ADDITIONAL SOURCE DISCOVERY (user-requested)
# -----------------------------------------------------------------------

section_tablespace_autoextend() {
    echo "--- Tablespace Autoextend Settings (Data Files) ---"
    run_sql "
SELECT tablespace_name, file_id, file_name, autoextensible,
       ROUND(bytes/1024/1024,0)    AS cur_size_mb,
       ROUND(maxbytes/1024/1024,0) AS max_size_mb,
       ROUND(increment_by * 8192/1024/1024, 0) AS increment_mb
FROM   dba_data_files
ORDER  BY tablespace_name, file_id;"

    echo ""
    echo "--- Tablespace Autoextend Settings (Temp Files) ---"
    run_sql "
SELECT tablespace_name, file_id, file_name, autoextensible,
       ROUND(bytes/1024/1024,0)    AS cur_size_mb,
       ROUND(maxbytes/1024/1024,0) AS max_size_mb,
       ROUND(increment_by * 8192/1024/1024, 0) AS increment_mb
FROM   dba_temp_files
ORDER  BY tablespace_name, file_id;"

    echo ""
    echo "--- Tablespace Summary ---"
    run_sql "
SELECT t.tablespace_name,
       t.status, t.contents, t.extent_management,
       t.logging, t.bigfile,
       ROUND(NVL(f.used_bytes,0)/1024/1024/1024,2) AS used_gb,
       ROUND(NVL(f.free_bytes,0)/1024/1024/1024,2) AS free_gb,
       ROUND(NVL(f.total_bytes,0)/1024/1024/1024,2) AS total_gb
FROM   dba_tablespaces t
LEFT JOIN (
    SELECT tablespace_name,
           SUM(bytes) AS total_bytes,
           SUM(DECODE(autoextensible,'NO',bytes,maxbytes)) AS max_bytes,
           SUM(bytes) AS used_bytes,  0 AS free_bytes
    FROM   dba_data_files GROUP BY tablespace_name
) f ON t.tablespace_name = f.tablespace_name
ORDER  BY t.tablespace_name;"
}

section_backup_schedule() {
    echo "--- RMAN Configuration ---"
    run_sql "
SELECT name, value FROM v\$rman_configuration ORDER BY conf#;" 2>/dev/null

    echo ""
    echo "--- Recent RMAN Jobs (last 14 days) ---"
    run_sql "
SELECT session_key, input_type, status,
       to_char(start_time,'YYYY-MM-DD HH24:MI:SS') AS start_time,
       to_char(end_time,'YYYY-MM-DD HH24:MI:SS')   AS end_time,
       ROUND(output_bytes/1024/1024/1024,2)         AS output_gb,
       elapsed_seconds
FROM   v\$rman_backup_job_details
WHERE  start_time > SYSDATE - 14
ORDER  BY start_time DESC
FETCH  FIRST 30 ROWS ONLY;" 2>/dev/null

    echo ""
    echo "--- Backup Piece Retention Window ---"
    run_sql "
SELECT record_type, record_size,
       to_char(first_time,'YYYY-MM-DD') AS oldest_backup,
       to_char(last_time,'YYYY-MM-DD')  AS newest_backup,
       records_total, records_used
FROM   v\$backup_files
WHERE  ROWNUM <= 5;" 2>/dev/null || echo "v\$backup_files not accessible"

    echo ""
    echo "--- DBMS_SCHEDULER Backup Jobs ---"
    run_sql "
SELECT owner, job_name, job_type, enabled, state,
       to_char(last_start_date,'YYYY-MM-DD HH24:MI:SS') AS last_run,
       to_char(next_run_date,'YYYY-MM-DD HH24:MI:SS')   AS next_run,
       repeat_interval
FROM   dba_scheduler_jobs
WHERE  UPPER(job_name) LIKE '%BACKUP%'
   OR  UPPER(job_name) LIKE '%RMAN%'
   OR  UPPER(job_name) LIKE '%ARCH%'
ORDER  BY owner, job_name;"

    echo ""
    echo "--- OS Cron Jobs (search for rman/backup) ---"
    crontab -l 2>/dev/null | grep -iE 'rman|backup|arch' || echo "No matching cron entries for current user"
    cat /etc/cron.d/* 2>/dev/null | grep -iE 'rman|backup|arch' | head -20 || echo "No matching /etc/cron.d entries"
    ls /etc/cron.daily /etc/cron.weekly 2>/dev/null | head -20
}

section_database_links() {
    echo "--- All Database Links ---"
    run_sql "
SELECT owner, db_link, username, host,
       to_char(created,'YYYY-MM-DD HH24:MI:SS') AS created
FROM   dba_db_links
ORDER  BY owner, db_link;"

    echo ""
    echo "--- Public Database Links ---"
    run_sql "
SELECT db_link, username, host FROM dba_db_links
WHERE  owner = 'PUBLIC'
ORDER  BY db_link;"
}

section_materialized_views() {
    echo "--- Materialized Views with Refresh Schedules ---"
    run_sql "
SELECT owner, mview_name, refresh_method, refresh_mode,
       start_with, next, last_refresh_type,
       to_char(last_refresh_date,'YYYY-MM-DD HH24:MI:SS') AS last_refresh,
       staleness, compile_state
FROM   dba_mviews
ORDER  BY owner, mview_name;"

    echo ""
    echo "--- Materialized View Refresh Groups ---"
    run_sql "
SELECT rowner, rname, job, next_date, interval,
       broken, failures
FROM   dba_refresh
ORDER  BY rowner, rname;" 2>/dev/null

    echo ""
    echo "--- Materialized View Logs ---"
    run_sql "
SELECT log_owner, master, log_table,
       rowids, primary_key, object_id, filter_columns,
       sequence, include_new_values
FROM   dba_mview_logs
ORDER  BY log_owner, master;"
}

section_scheduler_jobs() {
    echo "--- All Scheduler Jobs (non-Oracle internal) ---"
    run_sql "
SELECT owner, job_name, job_type, enabled, state,
       schedule_type,
       to_char(start_date,'YYYY-MM-DD HH24:MI:SS')       AS start_date,
       to_char(next_run_date,'YYYY-MM-DD HH24:MI:SS')    AS next_run,
       to_char(last_start_date,'YYYY-MM-DD HH24:MI:SS')  AS last_run,
       repeat_interval, failure_count, run_count
FROM   dba_scheduler_jobs
WHERE  owner NOT IN ('SYS','SYSTEM','DBSNMP','APPQOSSYS','AUDSYS',
                     'CTXSYS','DVSYS','GSMADMIN_INTERNAL','LBACSYS',
                     'MDSYS','OJVMSYS','OLAPSYS','ORDSYS','OUTLN',
                     'WMSYS','XDB','EXFSYS')
ORDER  BY owner, job_name;"

    echo ""
    echo "--- Scheduler Programs (user-defined) ---"
    run_sql "
SELECT owner, program_name, program_type, enabled
FROM   dba_scheduler_programs
WHERE  owner NOT IN ('SYS','SYSTEM','ORACLE_OCM','DVSYS','MDSYS','XDB','WMSYS','EXFSYS')
ORDER  BY owner, program_name;"

    echo ""
    echo "--- Scheduler Chains (if any) ---"
    run_sql "
SELECT owner, chain_name, enabled
FROM   dba_scheduler_chains
WHERE  owner NOT IN ('SYS','SYSTEM')
ORDER  BY owner, chain_name;" 2>/dev/null

    echo ""
    echo "--- Scheduler Job Run History (last 7 days, failures) ---"
    run_sql "
SELECT owner, job_name, status,
       to_char(actual_start_date,'YYYY-MM-DD HH24:MI:SS') AS run_date,
       run_duration, additional_info
FROM   dba_scheduler_job_run_details
WHERE  actual_start_date > SYSDATE - 7
  AND  status != 'SUCCEEDED'
ORDER  BY actual_start_date DESC
FETCH  FIRST 50 ROWS ONLY;" 2>/dev/null || echo "dba_scheduler_job_run_details not accessible"
}

# ===========================================================================
# JSON SUMMARY
# ===========================================================================

generate_json_summary() {
    local db_name db_unique hostname db_version db_role log_mode force_log cdb_flag
    db_name=$(run_sql_value "SELECT name FROM v\$database;")
    db_unique=$(run_sql_value "SELECT db_unique_name FROM v\$database;")
    hostname=$(hostname -f 2>/dev/null || hostname)
    db_version=$(run_sql_value "SELECT version FROM v\$instance;")
    db_role=$(run_sql_value "SELECT database_role FROM v\$database;")
    log_mode=$(run_sql_value "SELECT log_mode FROM v\$database;")
    force_log=$(run_sql_value "SELECT force_logging FROM v\$database;")
    cdb_flag=$(run_sql_value "SELECT cdb FROM v\$database;")

    cat > "$JSON_FILE" <<EOJSON
{
  "discovery_type"     : "source_database",
  "project"            : "PRODDB Migration to Oracle Database@Azure",
  "generated_at"       : "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hostname"           : "${hostname}",
  "oracle_home"        : "${ORACLE_HOME:-unknown}",
  "oracle_sid"         : "${ORACLE_SID:-unknown}",
  "db_name"            : "${db_name:-unknown}",
  "db_unique_name"     : "${db_unique:-unknown}",
  "db_version"         : "${db_version:-unknown}",
  "database_role"      : "${db_role:-unknown}",
  "log_mode"           : "${log_mode:-unknown}",
  "force_logging"      : "${force_log:-unknown}",
  "cdb"                : "${cdb_flag:-unknown}",
  "section_errors"     : ${SECTION_ERRORS},
  "output_text_file"   : "${OUTPUT_FILE}"
}
EOJSON
    echo "JSON summary written to: $JSON_FILE"
}

# ===========================================================================
# MAIN
# ===========================================================================

{
echo "============================================================"
echo "  ZDM SOURCE DATABASE DISCOVERY"
echo "  Project : PRODDB Migration to Oracle Database@Azure"
echo "  Host    : $(hostname -f 2>/dev/null || hostname)"
echo "  Started : $(date)"
echo "  Run by  : $(id)"
echo "  ORACLE_HOME : ${ORACLE_HOME:-NOT SET}"
echo "  ORACLE_SID  : ${ORACLE_SID:-NOT SET}"
echo "============================================================"
} | tee "$OUTPUT_FILE"

run_section "1. OS INFORMATION"                    section_os_info
run_section "2. ORACLE ENVIRONMENT"                section_oracle_env
run_section "3. DATABASE CONFIGURATION"            section_db_config
run_section "4. CONTAINER DATABASE (CDB/PDB)"     section_cdb_pdb
run_section "5. TDE CONFIGURATION"                section_tde
run_section "6. SUPPLEMENTAL LOGGING"             section_supplemental_logging
run_section "7. REDO & ARCHIVE CONFIGURATION"     section_redo_archive
run_section "8. NETWORK CONFIGURATION"            section_network_config
run_section "9. AUTHENTICATION"                   section_auth
run_section "10. DATA GUARD"                       section_data_guard
run_section "11. SCHEMA INFORMATION"               section_schema_info
run_section "12. TABLESPACE AUTOEXTEND SETTINGS"  section_tablespace_autoextend
run_section "13. BACKUP SCHEDULE & RETENTION"     section_backup_schedule
run_section "14. DATABASE LINKS"                   section_database_links
run_section "15. MATERIALIZED VIEW REFRESH"        section_materialized_views
run_section "16. SCHEDULER JOBS"                   section_scheduler_jobs

generate_json_summary

{
echo ""
echo "============================================================"
echo "  DISCOVERY COMPLETE"
echo "  Sections with errors : $SECTION_ERRORS"
echo "  Text report : $OUTPUT_FILE"
echo "  JSON summary: $JSON_FILE"
echo "  Finished    : $(date)"
echo "============================================================"
} | tee -a "$OUTPUT_FILE"

exit 0
