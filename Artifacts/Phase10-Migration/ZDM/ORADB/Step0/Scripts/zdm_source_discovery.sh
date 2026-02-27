#!/bin/bash
# =============================================================================
# ZDM Source Database Discovery Script
# =============================================================================
# Project  : ORADB Migration to Oracle Database@Azure
# Source   : proddb01.corp.example.com
# Generated: 2026-02-26
#
# USAGE:
#   ./zdm_source_discovery.sh
#
# SSH as SOURCE_ADMIN_USER (oracle); SQL commands run as oracle via sudo if needed.
# ORACLE_HOME_OVERRIDE / ORACLE_SID_OVERRIDE can force specific values.
# =============================================================================

# NO set -e — continue even when individual checks fail
SECTION_ERRORS=0
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME_SHORT=$(hostname -s 2>/dev/null || hostname)
OUTPUT_FILE="./zdm_source_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_source_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

# ---------------------------------------------------------------------------
# User configuration (injected by orchestration script)
# ---------------------------------------------------------------------------
ORACLE_USER="${ORACLE_USER:-oracle}"

# ---------------------------------------------------------------------------
# Environment bootstrap (3-tier priority)
# ---------------------------------------------------------------------------
# Tier 1: explicit overrides from orchestration script
[ -n "${ORACLE_HOME_OVERRIDE:-}"  ] && export ORACLE_HOME="$ORACLE_HOME_OVERRIDE"
[ -n "${ORACLE_SID_OVERRIDE:-}"   ] && export ORACLE_SID="$ORACLE_SID_OVERRIDE"
[ -n "${ORACLE_BASE_OVERRIDE:-}"  ] && export ORACLE_BASE="$ORACLE_BASE_OVERRIDE"

# Tier 2: extract from shell profiles (bypasses interactive guards)
for _profile in /etc/profile /etc/profile.d/*.sh ~/.bash_profile ~/.bashrc; do
    [ -f "$_profile" ] || continue
    eval "$(grep -E '^export[[:space:]]+(ORACLE_HOME|ORACLE_SID|ORACLE_BASE|TNS_ADMIN|PATH)=' \
           "$_profile" 2>/dev/null)" 2>/dev/null || true
done

# Tier 3: auto-detect
detect_oracle_env() {
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then return 0; fi

    # Method 1: /etc/oratab
    if [ -f /etc/oratab ]; then
        local entry
        if [ -n "${ORACLE_SID:-}" ]; then
            entry=$(grep "^${ORACLE_SID}:" /etc/oratab 2>/dev/null | head -1)
        else
            entry=$(grep -v '^#' /etc/oratab | grep -v '^$' | grep ':' | head -1)
        fi
        if [ -n "$entry" ]; then
            export ORACLE_SID="${ORACLE_SID:-$(echo "$entry" | cut -d: -f1)}"
            export ORACLE_HOME="${ORACLE_HOME:-$(echo "$entry" | cut -d: -f2)}"
        fi
    fi

    # Method 2: running pmon process
    if [ -z "${ORACLE_SID:-}" ]; then
        local pmon_sid
        pmon_sid=$(ps -ef 2>/dev/null | grep 'ora_pmon_' | grep -v grep | head -1 | sed 's/.*ora_pmon_//')
        [ -n "$pmon_sid" ] && export ORACLE_SID="$pmon_sid"
    fi

    # Method 3: common installation paths
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

    # Method 4: oraenv
    if [ -z "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ] && [ -f /usr/local/bin/oraenv ]; then
        . /usr/local/bin/oraenv <<< "$ORACLE_SID" 2>/dev/null || true
    fi
}
detect_oracle_env

# Update PATH
[ -n "${ORACLE_HOME:-}" ] && export PATH="${ORACLE_HOME}/bin:${PATH}"

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
log_info()    { echo -e "${GREEN}[INFO ] $(date '+%H:%M:%S') $*${RESET}" | tee -a "$OUTPUT_FILE"; }
log_warn()    { echo -e "${YELLOW}[WARN ] $(date '+%H:%M:%S') $*${RESET}" | tee -a "$OUTPUT_FILE"; }
log_error()   { echo -e "${RED}[ERROR] $(date '+%H:%M:%S') $*${RESET}" | tee -a "$OUTPUT_FILE"; }
log_section() {
    local bar="================================================================"
    echo "" | tee -a "$OUTPUT_FILE"
    echo -e "${CYAN}${BOLD}${bar}${RESET}" | tee -a "$OUTPUT_FILE"
    echo -e "${CYAN}${BOLD}  $*${RESET}" | tee -a "$OUTPUT_FILE"
    echo -e "${CYAN}${BOLD}${bar}${RESET}" | tee -a "$OUTPUT_FILE"
    echo "" | tee -a "$OUTPUT_FILE"
}
tee_out() { tee -a "$OUTPUT_FILE"; }

# ---------------------------------------------------------------------------
# SQL execution helper
# ---------------------------------------------------------------------------
run_sql() {
    local sql_query="$1"
    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        echo "ERROR: ORACLE_HOME or ORACLE_SID not set — cannot run SQL"
        return 1
    fi
    local sqlplus_cmd="${ORACLE_HOME}/bin/sqlplus -s / as sysdba"
    local sql_script
    sql_script=$(cat <<EOSQL
SET PAGESIZE 1000
SET LINESIZE 200
SET FEEDBACK OFF
SET HEADING ON
SET ECHO OFF
SET TRIMSPOOL ON
$sql_query
EXIT
EOSQL
)
    if [ "$(whoami)" = "$ORACLE_USER" ]; then
        echo "$sql_script" | $sqlplus_cmd 2>&1
    else
        echo "$sql_script" | sudo -u "$ORACLE_USER" -E \
            ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" \
            $sqlplus_cmd 2>&1
    fi
}

run_sql_value() {
    local sql_query="$1"
    run_sql "SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
$sql_query" 2>/dev/null | grep -v '^$' | head -1 | xargs
}

# ===========================================================================
# DISCOVERY SECTIONS
# ===========================================================================

# ---------------------------------------------------------------------------
# 1. Script Header
# ---------------------------------------------------------------------------
{
echo "================================================================"
echo "  ZDM SOURCE DATABASE DISCOVERY REPORT"
echo "================================================================"
echo "  Project    : ORADB Migration to Oracle Database@Azure"
echo "  Source Host: proddb01.corp.example.com"
echo "  Run Host   : $(hostname)"
echo "  Run User   : $(whoami)"
echo "  Oracle User: $ORACLE_USER"
echo "  Timestamp  : $(date)"
echo "  ORACLE_HOME: ${ORACLE_HOME:-NOT DETECTED}"
echo "  ORACLE_SID : ${ORACLE_SID:-NOT DETECTED}"
echo "================================================================"
echo ""
} | tee "$OUTPUT_FILE"

# ---------------------------------------------------------------------------
# 2. OS Information
# ---------------------------------------------------------------------------
log_section "OS INFORMATION"
{
echo "--- Hostname & IP ---"
hostname -f 2>/dev/null || hostname
ip addr show 2>/dev/null | grep 'inet ' | awk '{print $2}' \
    || ifconfig 2>/dev/null | grep 'inet ' | awk '{print $2}'
echo ""
echo "--- OS Version ---"
cat /etc/oracle-release 2>/dev/null \
    || cat /etc/redhat-release 2>/dev/null \
    || cat /etc/os-release 2>/dev/null \
    || uname -a
echo ""
echo "--- Kernel ---"
uname -r
echo ""
echo "--- CPU ---"
grep -m1 'model name' /proc/cpuinfo 2>/dev/null
nproc 2>/dev/null | xargs -I{} echo "CPU Count: {}"
echo ""
echo "--- Memory ---"
free -h 2>/dev/null
echo ""
echo "--- Disk Space ---"
df -h 2>/dev/null
} | tee_out
SECTION_ERRORS=$((SECTION_ERRORS + $?)) || true

# ---------------------------------------------------------------------------
# 3. Oracle Environment
# ---------------------------------------------------------------------------
log_section "ORACLE ENVIRONMENT"
{
echo "ORACLE_HOME : ${ORACLE_HOME:-NOT SET}"
echo "ORACLE_SID  : ${ORACLE_SID:-NOT SET}"
echo "ORACLE_BASE : ${ORACLE_BASE:-NOT SET}"
echo "TNS_ADMIN   : ${TNS_ADMIN:-NOT SET}"
echo ""
echo "--- Oracle Version ---"
if [ -f "${ORACLE_HOME:-}/bin/sqlplus" ]; then
    "${ORACLE_HOME}/bin/sqlplus" -version 2>/dev/null
fi
echo ""
echo "--- oratab ---"
cat /etc/oratab 2>/dev/null || echo "No /etc/oratab found"
echo ""
echo "--- Running Oracle Processes ---"
ps -ef | grep -E '(pmon|smon|dbwr|lgwr|ckpt)' | grep -v grep
} | tee_out
SECTION_ERRORS=$((SECTION_ERRORS + $?)) || true

# ---------------------------------------------------------------------------
# 4. Database Configuration
# ---------------------------------------------------------------------------
log_section "DATABASE CONFIGURATION"
run_sql "
SELECT 'DB_NAME        : '||name FROM v\$database;
SELECT 'DB_UNIQUE_NAME : '||db_unique_name FROM v\$database;
SELECT 'DBID           : '||dbid FROM v\$database;
SELECT 'DB_ROLE        : '||database_role FROM v\$database;
SELECT 'OPEN_MODE      : '||open_mode FROM v\$database;
SELECT 'LOG_MODE       : '||log_mode FROM v\$database;
SELECT 'FORCE_LOGGING  : '||force_logging FROM v\$database;
SELECT 'PLATFORM_NAME  : '||platform_name FROM v\$database;
SELECT 'CREATED        : '||TO_CHAR(created,'YYYY-MM-DD HH24:MI:SS') FROM v\$database;
SELECT 'RESETLOGS_TIME : '||TO_CHAR(resetlogs_time,'YYYY-MM-DD HH24:MI:SS') FROM v\$database;
SELECT 'PROTECTION_MODE: '||protection_mode FROM v\$database;
PROMPT
PROMPT --- CHARACTER SET ---
SELECT parameter, value FROM nls_database_parameters
WHERE parameter IN ('NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET','NLS_LANGUAGE','NLS_TERRITORY')
ORDER BY parameter;
PROMPT
PROMPT --- DATABASE SIZE ---
SELECT 'Data Files (GB) : '||ROUND(SUM(bytes)/1024/1024/1024,2) FROM dba_data_files;
SELECT 'Temp Files (GB) : '||ROUND(SUM(bytes)/1024/1024/1024,2) FROM dba_temp_files;
SELECT 'Redo Logs (GB)  : '||ROUND(SUM(bytes)/1024/1024/1024,2) FROM v\$log;
SELECT 'Total DB (GB)   : '||ROUND(
    (SELECT SUM(bytes) FROM dba_data_files)+
    (SELECT SUM(bytes) FROM dba_temp_files),1024*1024*1024) FROM dual;
" 2>&1 | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ---------------------------------------------------------------------------
# 5. Container Database (CDB/PDB)
# ---------------------------------------------------------------------------
log_section "CONTAINER DATABASE STATUS"
run_sql "
SELECT 'CDB : '||cdb FROM v\$database;
SELECT 'CON_ID : '||con_id||'  NAME : '||name||'  OPEN_MODE : '||open_mode
FROM v\$pdbs
ORDER BY con_id;
" 2>&1 | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ---------------------------------------------------------------------------
# 6. TDE Configuration
# ---------------------------------------------------------------------------
log_section "TDE CONFIGURATION"
run_sql "
PROMPT --- Wallet Status ---
SELECT * FROM v\$encryption_wallet;
PROMPT
PROMPT --- Encrypted Tablespaces ---
SELECT tablespace_name, encrypted FROM dba_tablespaces WHERE encrypted='YES';
PROMPT
PROMPT --- TDE Master Key Info ---
SELECT con_id, key_id, creator, creation_time, activating_dbname
FROM v\$encryption_keys ORDER BY creation_time;
" 2>&1 | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

{
echo ""
echo "--- Wallet Files ---"
for _walletdir in "${ORACLE_BASE:-/u01/app/oracle}/admin/${ORACLE_SID:-*}/wallet" \
                  "${ORACLE_BASE:-/u01/app/oracle}/admin/${ORACLE_SID:-*}/tde_wallet" \
                  /etc/oracle/wallets/*; do
    if ls $_walletdir 2>/dev/null; then
        echo "Found wallet dir: $_walletdir"
        ls -la $_walletdir 2>/dev/null
    fi
done
} | tee_out

# ---------------------------------------------------------------------------
# 7. Supplemental Logging
# ---------------------------------------------------------------------------
log_section "SUPPLEMENTAL LOGGING"
run_sql "
SELECT log_mode, supplemental_log_data_min AS min_suplog,
       supplemental_log_data_pk  AS pk_suplog,
       supplemental_log_data_ui  AS ui_suplog,
       supplemental_log_data_fk  AS fk_suplog,
       supplemental_log_data_all AS all_suplog
FROM v\$database;
" 2>&1 | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ---------------------------------------------------------------------------
# 8. Redo / Archive Configuration
# ---------------------------------------------------------------------------
log_section "REDO AND ARCHIVE CONFIGURATION"
run_sql "
PROMPT --- Redo Log Groups ---
SELECT l.group#, l.members, l.bytes/1024/1024 AS size_mb,
       l.status, l.archived
FROM v\$log l ORDER BY l.group#;
PROMPT
PROMPT --- Redo Log Members ---
SELECT lf.group#, lf.member, lf.status FROM v\$logfile lf ORDER BY lf.group#, lf.member;
PROMPT
PROMPT --- Archive Log Destinations ---
SELECT dest_id, dest_name, status, target, archiver, schedule,
       destination, applied, error
FROM v\$archive_dest WHERE status != 'INACTIVE' ORDER BY dest_id;
PROMPT
PROMPT --- Recent Archive Logs ---
SELECT name, ROUND(blocks*block_size/1024/1024,1) AS size_mb,
       TO_CHAR(first_time,'YYYY-MM-DD HH24:MI') AS first_time,
       TO_CHAR(next_time,'YYYY-MM-DD HH24:MI')  AS next_time
FROM v\$archived_log
WHERE standby_dest='NO' AND first_time > SYSDATE-1
ORDER BY sequence# DESC FETCH FIRST 20 ROWS ONLY;
" 2>&1 | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ---------------------------------------------------------------------------
# 9. Network Configuration
# ---------------------------------------------------------------------------
log_section "NETWORK CONFIGURATION"
{
echo "--- Listener Status ---"
if [ -n "${ORACLE_HOME:-}" ]; then
    "${ORACLE_HOME}/bin/lsnrctl" status 2>/dev/null || echo "lsnrctl not available"
fi
echo ""
echo "--- tnsnames.ora ---"
for _f in "${TNS_ADMIN:-${ORACLE_HOME:-}/network/admin}/tnsnames.ora" \
           /etc/tnsnames.ora; do
    [ -f "$_f" ] && { echo "File: $_f"; cat "$_f"; } || true
done
echo ""
echo "--- sqlnet.ora ---"
for _f in "${TNS_ADMIN:-${ORACLE_HOME:-}/network/admin}/sqlnet.ora" \
           /etc/sqlnet.ora; do
    [ -f "$_f" ] && { echo "File: $_f"; cat "$_f"; } || true
done
echo ""
echo "--- listener.ora ---"
for _f in "${TNS_ADMIN:-${ORACLE_HOME:-}/network/admin}/listener.ora"; do
    [ -f "$_f" ] && { echo "File: $_f"; cat "$_f"; } || true
done
} | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ---------------------------------------------------------------------------
# 10. Authentication
# ---------------------------------------------------------------------------
log_section "AUTHENTICATION"
{
echo "--- Password File ---"
ls -la "${ORACLE_HOME:-}/dbs/orapw${ORACLE_SID:-}" 2>/dev/null \
    || find "${ORACLE_HOME:-}/dbs" -name 'orapw*' -ls 2>/dev/null \
    || echo "No password file found in ORACLE_HOME/dbs"
echo ""
echo "--- SSH Directory (oracle user) ---"
if [ "$(whoami)" = "$ORACLE_USER" ]; then
    ls -la ~/.ssh/ 2>/dev/null || echo "No .ssh directory"
else
    sudo -u "$ORACLE_USER" bash -c 'ls -la ~/.ssh/ 2>/dev/null || echo "No .ssh directory"' 2>/dev/null
fi
} | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ---------------------------------------------------------------------------
# 11. Data Guard Configuration
# ---------------------------------------------------------------------------
log_section "DATA GUARD CONFIGURATION"
run_sql "
SELECT name, value FROM v\$parameter
WHERE name IN (
    'log_archive_config',
    'log_archive_dest_1',
    'log_archive_dest_2',
    'log_archive_dest_state_1',
    'log_archive_dest_state_2',
    'db_unique_name',
    'fal_server',
    'fal_client',
    'standby_file_management',
    'db_file_name_convert',
    'log_file_name_convert'
)
ORDER BY name;
" 2>&1 | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ---------------------------------------------------------------------------
# 12. Schema Information
# ---------------------------------------------------------------------------
log_section "SCHEMA INFORMATION"
run_sql "
PROMPT --- Schema Sizes (non-system, > 100MB) ---
SELECT owner,
       ROUND(SUM(bytes)/1024/1024/1024,3) AS size_gb,
       COUNT(*)                            AS segment_count
FROM dba_segments
WHERE owner NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','WMSYS','EXFSYS',
    'CTXSYS','XDB','ANONYMOUS','ORDPLUGINS','ORDSYS','SI_INFORMTN_SCHEMA',
    'MDSYS','OLAPSYS','SYSMAN','MGMT_VIEW','APEX_030200','APEX_PUBLIC_USER',
    'FLOWS_FILES','DIP','ORACLE_OCM','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR',
    'DVSYS','LBACSYS','DVF','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS','GGSYS'
)
GROUP BY owner
HAVING SUM(bytes)/1024/1024 > 100
ORDER BY size_gb DESC;
PROMPT
PROMPT --- Invalid Objects by Owner and Type ---
SELECT owner, object_type, COUNT(*) AS cnt
FROM dba_objects WHERE status='INVALID'
GROUP BY owner, object_type ORDER BY owner, object_type;
PROMPT
PROMPT --- Object Count by Type (all schemas) ---
SELECT object_type, COUNT(*) FROM dba_objects
WHERE owner NOT IN ('SYS','SYSTEM')
GROUP BY object_type ORDER BY COUNT(*) DESC;
" 2>&1 | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ---------------------------------------------------------------------------
# 13. Tablespace Information
# ---------------------------------------------------------------------------
log_section "TABLESPACE INFORMATION"
run_sql "
PROMPT --- Tablespace Usage ---
SELECT t.tablespace_name,
       t.status,
       t.contents,
       ROUND(NVL(f.free_space,0)/1024/1024/1024,2) AS free_gb,
       ROUND(d.total_space/1024/1024/1024,2)        AS total_gb,
       ROUND((1 - NVL(f.free_space,0)/d.total_space)*100,1) AS pct_used
FROM dba_tablespaces t
JOIN (SELECT tablespace_name, SUM(bytes) AS total_space FROM dba_data_files GROUP BY tablespace_name) d
     ON t.tablespace_name = d.tablespace_name
LEFT JOIN (SELECT tablespace_name, SUM(bytes) AS free_space  FROM dba_free_space GROUP BY tablespace_name) f
     ON t.tablespace_name = f.tablespace_name
ORDER BY pct_used DESC NULLS LAST;
" 2>&1 | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ---------------------------------------------------------------------------
# 14. Tablespace Autoextend Settings (additional requirement)
# ---------------------------------------------------------------------------
log_section "TABLESPACE AUTOEXTEND SETTINGS"
run_sql "
SELECT tablespace_name,
       file_name,
       ROUND(bytes/1024/1024/1024,2)    AS current_gb,
       autoextensible,
       ROUND(maxbytes/1024/1024/1024,2) AS max_gb,
       ROUND(increment_by*8192/1024/1024,0) AS increment_mb
FROM dba_data_files
ORDER BY tablespace_name, file_name;
PROMPT
PROMPT --- Temp File Autoextend ---
SELECT tablespace_name,
       file_name,
       ROUND(bytes/1024/1024/1024,2)    AS current_gb,
       autoextensible,
       ROUND(maxbytes/1024/1024/1024,2) AS max_gb
FROM dba_temp_files
ORDER BY tablespace_name;
" 2>&1 | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ---------------------------------------------------------------------------
# 15. Backup Schedule and Retention (additional requirement)
# ---------------------------------------------------------------------------
log_section "BACKUP SCHEDULE AND RETENTION"
run_sql "
PROMPT --- RMAN Configuration ---
SELECT name, value FROM v\$rman_configuration ORDER BY conf#;
PROMPT
PROMPT --- Recent RMAN Jobs (last 7 days) ---
SELECT TO_CHAR(start_time,'YYYY-MM-DD HH24:MI') AS start_time,
       TO_CHAR(end_time,'YYYY-MM-DD HH24:MI')   AS end_time,
       input_type,
       status,
       ROUND(input_bytes/1024/1024/1024,2)       AS input_gb,
       ROUND(output_bytes/1024/1024/1024,2)      AS output_gb
FROM v\$rman_backup_job_details
WHERE start_time > SYSDATE - 7
ORDER BY start_time DESC;
PROMPT
PROMPT --- Backup Sets Summary ---
SELECT backup_type,
       incremental_level,
       status,
       COUNT(*)                                  AS set_count,
       ROUND(SUM(output_bytes)/1024/1024/1024,2) AS total_gb
FROM v\$backup_set_details
WHERE start_time > SYSDATE - 30
GROUP BY backup_type, incremental_level, status
ORDER BY backup_type, incremental_level;
" 2>&1 | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

{
echo ""
echo "--- RMAN registered catalogs / targets ---"
cat "${ORACLE_HOME:-}/dbs/target.rman" 2>/dev/null || true
echo ""
echo "--- Cron backup jobs ---"
crontab -l 2>/dev/null | grep -iE '(rman|backup|bkp)' || echo "No cron backup jobs for current user"
if [ "$(whoami)" != "$ORACLE_USER" ]; then
    sudo -u "$ORACLE_USER" crontab -l 2>/dev/null | grep -iE '(rman|backup|bkp)' \
        || echo "No cron backup jobs for oracle user"
fi
} | tee_out

# ---------------------------------------------------------------------------
# 16. Database Links (additional requirement)
# ---------------------------------------------------------------------------
log_section "DATABASE LINKS"
run_sql "
SELECT owner, db_link, username, host,
       TO_CHAR(created,'YYYY-MM-DD') AS created
FROM dba_db_links
ORDER BY owner, db_link;
" 2>&1 | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ---------------------------------------------------------------------------
# 17. Materialized View Refresh Schedules (additional requirement)
# ---------------------------------------------------------------------------
log_section "MATERIALIZED VIEWS AND REFRESH SCHEDULES"
run_sql "
PROMPT --- Materialized Views ---
SELECT owner, mview_name, refresh_method, refresh_mode,
       last_refresh_type,
       TO_CHAR(last_refresh_date,'YYYY-MM-DD HH24:MI') AS last_refresh,
       staleness
FROM dba_mviews
WHERE owner NOT IN ('SYS','SYSTEM')
ORDER BY owner, mview_name;
PROMPT
PROMPT --- MView Refresh Groups ---
SELECT rg.rname, rg.job, rg.broken, rg.interval,
       TO_CHAR(rg.next_date,'YYYY-MM-DD HH24:MI') AS next_refresh
FROM dba_refresh rg
ORDER BY rg.rname;
PROMPT
PROMPT --- MView Logs ---
SELECT log_owner, master, log_table, log_trigger,
       rowids, primary_key, object_id, filter_columns, sequence
FROM dba_mview_logs
ORDER BY log_owner, master;
" 2>&1 | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ---------------------------------------------------------------------------
# 18. Scheduler Jobs (additional requirement)
# ---------------------------------------------------------------------------
log_section "SCHEDULER JOBS"
run_sql "
PROMPT --- DBMS Scheduler Jobs (non-system) ---
SELECT owner, job_name, job_type, job_action,
       schedule_type,
       TO_CHAR(start_date,'YYYY-MM-DD HH24:MI') AS start_date,
       repeat_interval,
       TO_CHAR(last_start_date,'YYYY-MM-DD HH24:MI') AS last_start,
       TO_CHAR(next_run_date,'YYYY-MM-DD HH24:MI')   AS next_run,
       state, enabled
FROM dba_scheduler_jobs
WHERE owner NOT IN ('SYS','SYSTEM','EXFSYS','MDSYS','ORDSYS','CTXSYS','XDB',
                    'WMSYS','DBSNMP','SYSMAN','ORACLE_OCM','GSMADMIN_INTERNAL')
ORDER BY owner, job_name;
PROMPT
PROMPT --- Scheduler Programs (non-system) ---
SELECT owner, program_name, program_type, enabled
FROM dba_scheduler_programs
WHERE owner NOT IN ('SYS','SYSTEM')
ORDER BY owner, program_name;
PROMPT
PROMPT --- Scheduler Chains (non-system) ---
SELECT owner, chain_name, rule_set_name, enabled
FROM dba_scheduler_chains
WHERE owner NOT IN ('SYS','SYSTEM')
ORDER BY owner, chain_name;
PROMPT
PROMPT --- DBMS_JOB entries ---
SELECT job, what, interval,
       TO_CHAR(last_date,'YYYY-MM-DD HH24:MI') AS last_run,
       TO_CHAR(next_date,'YYYY-MM-DD HH24:MI') AS next_run,
       broken
FROM dba_jobs
WHERE schema_user NOT IN ('SYS','SYSTEM')
ORDER BY job;
" 2>&1 | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ---------------------------------------------------------------------------
# 19. Additional ZDM-Relevant Parameters
# ---------------------------------------------------------------------------
log_section "ZDM-RELEVANT INIT PARAMETERS"
run_sql "
SELECT name, value, description
FROM v\$parameter
WHERE name IN (
    'db_name','db_unique_name','enable_pluggable_database',
    'enable_goldengate_replication','log_archive_dest_1',
    'log_archive_dest_2','log_archive_config','undo_tablespace',
    'sga_target','pga_aggregate_target','sga_max_size',
    'memory_target','memory_max_target','parallel_max_servers',
    'open_cursors','session_cached_cursors','processes','sessions',
    'db_block_size','compatible','cluster_database',
    'dg_broker_start','dg_broker_config_file1','dg_broker_config_file2'
)
ORDER BY name;
" 2>&1 | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ===========================================================================
# JSON SUMMARY
# ===========================================================================
DB_NAME=$(run_sql_value "SELECT name FROM v\$database;")
DB_UNIQUE=$(run_sql_value "SELECT db_unique_name FROM v\$database;")
DB_ROLE=$(run_sql_value "SELECT database_role FROM v\$database;")
OPEN_MODE=$(run_sql_value "SELECT open_mode FROM v\$database;")
LOG_MODE=$(run_sql_value "SELECT log_mode FROM v\$database;")
FORCE_LOG=$(run_sql_value "SELECT force_logging FROM v\$database;")
IS_CDB=$(run_sql_value "SELECT cdb FROM v\$database;")
CHARSET=$(run_sql_value "SELECT value FROM nls_database_parameters WHERE parameter='NLS_CHARACTERSET';")
NCHARSET=$(run_sql_value "SELECT value FROM nls_database_parameters WHERE parameter='NLS_NCHAR_CHARACTERSET';")
DB_SIZE_GB=$(run_sql_value "SELECT ROUND(SUM(bytes)/1024/1024/1024,2) FROM dba_data_files;")
SUPLOG_MIN=$(run_sql_value "SELECT supplemental_log_data_min FROM v\$database;")
SUPLOG_ALL=$(run_sql_value "SELECT supplemental_log_data_all FROM v\$database;")
WALLET_STATUS=$(run_sql_value "SELECT status FROM v\$encryption_wallet WHERE rownum=1;")
COMPAT=$(run_sql_value "SELECT value FROM v\$parameter WHERE name='compatible';")

cat > "$JSON_FILE" <<EOJSON
{
  "discovery_type": "source",
  "project": "ORADB Migration to Oracle Database@Azure",
  "source_host": "proddb01.corp.example.com",
  "run_host": "$(hostname)",
  "run_user": "$(whoami)",
  "timestamp": "$(date -Iseconds)",
  "oracle_home": "${ORACLE_HOME:-}",
  "oracle_sid": "${ORACLE_SID:-}",
  "database": {
    "name": "${DB_NAME}",
    "unique_name": "${DB_UNIQUE}",
    "role": "${DB_ROLE}",
    "open_mode": "${OPEN_MODE}",
    "log_mode": "${LOG_MODE}",
    "force_logging": "${FORCE_LOG}",
    "is_cdb": "${IS_CDB}",
    "charset": "${CHARSET}",
    "ncharset": "${NCHARSET}",
    "size_gb": "${DB_SIZE_GB}",
    "compatible": "${COMPAT}"
  },
  "supplemental_logging": {
    "min": "${SUPLOG_MIN}",
    "all": "${SUPLOG_ALL}"
  },
  "tde": {
    "wallet_status": "${WALLET_STATUS:-NOT_CONFIGURED}"
  },
  "section_errors": ${SECTION_ERRORS}
}
EOJSON

# ===========================================================================
# FOOTER
# ===========================================================================
log_section "DISCOVERY COMPLETE"
{
echo "  Output file : $OUTPUT_FILE"
echo "  JSON file   : $JSON_FILE"
echo "  Completed   : $(date)"
echo "  Section errors: $SECTION_ERRORS (non-critical; some checks may have failed)"
echo ""
if [ "$SECTION_ERRORS" -gt 0 ]; then
    echo "  WARN: $SECTION_ERRORS section(s) encountered errors. Review output above."
else
    echo "  SUCCESS: All sections completed without errors."
fi
} | tee_out

exit 0
