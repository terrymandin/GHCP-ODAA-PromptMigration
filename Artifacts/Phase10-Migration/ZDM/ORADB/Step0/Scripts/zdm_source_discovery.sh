#!/bin/bash
# =============================================================================
# ZDM Source Database Discovery Script
# Project: ORADB
# Generated for: Oracle ZDM Migration - Step 0
#
# Purpose: Discover source database configuration for ZDM migration planning.
# Run as: SSH as SOURCE_ADMIN_USER, SQL runs via sudo -u oracle
#
# Usage: ./zdm_source_discovery.sh
# Output: ./zdm_source_discovery_<hostname>_<timestamp>.txt
#         ./zdm_source_discovery_<hostname>_<timestamp>.json
# =============================================================================

set -o nounset
set -o pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================
ORACLE_USER="${ORACLE_USER:-oracle}"
ORACLE_HOME="${ORACLE_HOME:-}"
ORACLE_SID="${ORACLE_SID:-}"
ORACLE_BASE="${ORACLE_BASE:-}"

# =============================================================================
# COLORS & LOGGING
# =============================================================================
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname)"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_TEXT="./zdm_source_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
OUTPUT_JSON="./zdm_source_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*" | tee -a "$OUTPUT_TEXT"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*" | tee -a "$OUTPUT_TEXT"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" | tee -a "$OUTPUT_TEXT"; }
log_section() {
    local line="========================================================================"
    echo -e "\n${CYAN}${line}${NC}" | tee -a "$OUTPUT_TEXT"
    echo -e "${CYAN}  $*${NC}" | tee -a "$OUTPUT_TEXT"
    echo -e "${CYAN}${line}${NC}" | tee -a "$OUTPUT_TEXT"
}
log_raw() { echo "$*" | tee -a "$OUTPUT_TEXT"; }

# =============================================================================
# AUTO-DETECTION
# =============================================================================
detect_oracle_env() {
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        log_info "Using pre-set ORACLE_HOME=$ORACLE_HOME ORACLE_SID=$ORACLE_SID"
        return 0
    fi

    # Method 1: /etc/oratab
    if [ -f /etc/oratab ]; then
        local entry
        if [ -n "${ORACLE_SID:-}" ]; then
            entry=$(grep "^${ORACLE_SID}:" /etc/oratab 2>/dev/null | head -1)
        else
            entry=$(grep -v '^#' /etc/oratab | grep -v '^$' | grep -v '^+' | head -1)
        fi
        if [ -n "$entry" ]; then
            ORACLE_SID="${ORACLE_SID:-$(echo "$entry" | cut -d: -f1)}"
            ORACLE_HOME="${ORACLE_HOME:-$(echo "$entry" | cut -d: -f2)}"
        fi
    fi

    # Method 2: Running pmon process
    if [ -z "${ORACLE_SID:-}" ]; then
        local pmon_sid
        pmon_sid=$(ps -ef 2>/dev/null | grep 'ora_pmon_' | grep -v grep | head -1 | sed 's/.*ora_pmon_//')
        [ -n "$pmon_sid" ] && ORACLE_SID="$pmon_sid"
    fi

    # Method 3: Common paths
    if [ -z "${ORACLE_HOME:-}" ]; then
        for p in /u01/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1 /oracle/product/*/dbhome_1; do
            if [ -d "$p" ] && [ -f "$p/bin/sqlplus" ]; then
                ORACLE_HOME="$p"
                break
            fi
        done
    fi

    # Method 4: oraenv
    if [ -z "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ] && [ -f /usr/local/bin/oraenv ]; then
        # shellcheck disable=SC1091
        ORACLE_SID="$ORACLE_SID" . /usr/local/bin/oraenv </dev/null 2>/dev/null || true
    fi

    # Apply explicit overrides (highest priority)
    [ -n "${SOURCE_REMOTE_ORACLE_HOME:-}" ] && ORACLE_HOME="$SOURCE_REMOTE_ORACLE_HOME"
    [ -n "${SOURCE_REMOTE_ORACLE_SID:-}" ]  && ORACLE_SID="$SOURCE_REMOTE_ORACLE_SID"

    export ORACLE_HOME ORACLE_SID

    if [ -n "$ORACLE_HOME" ] && [ -n "$ORACLE_SID" ]; then
        log_info "Detected ORACLE_HOME=$ORACLE_HOME  ORACLE_SID=$ORACLE_SID"
    else
        log_warn "Could not auto-detect Oracle environment. Set ORACLE_HOME and ORACLE_SID manually."
    fi
}

# Execute SQL as oracle user
run_sql() {
    local sql_query="$1"
    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        echo "ORACLE_HOME or ORACLE_SID not set"
        return 1
    fi
    local sqlplus_cmd="$ORACLE_HOME/bin/sqlplus -s / as sysdba"
    local sql_script
    sql_script=$(printf 'SET PAGESIZE 5000\nSET LINESIZE 300\nSET FEEDBACK OFF\nSET HEADING ON\nSET ECHO OFF\nSET TRIMSPOOL ON\n%s\nEXIT;\n' "$sql_query")
    if [ "$(whoami)" = "$ORACLE_USER" ]; then
        echo "$sql_script" | ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd 2>&1
    else
        echo "$sql_script" | sudo -u "$ORACLE_USER" -E env ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd 2>&1
    fi
}

run_sql_value() {
    run_sql "$1" | grep -v '^$' | grep -v '^-' | tail -1 | xargs 2>/dev/null
}

# =============================================================================
# JSON BUILDER
# =============================================================================
JSON_SECTIONS=()
json_add() {
    local key="$1"
    local val="$2"
    # Escape for JSON
    local escaped
    escaped=$(printf '%s' "$val" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g' | tr -d '\r')
    JSON_SECTIONS+=("  \"${key}\": \"${escaped}\"")
}

# =============================================================================
# DISCOVERY SECTIONS
# =============================================================================

discover_os() {
    log_section "OS INFORMATION"
    log_raw "Hostname:       $(hostname -f 2>/dev/null || hostname)"
    log_raw "Short hostname: ${HOSTNAME_SHORT}"
    log_raw "IP addresses:"
    ip addr show 2>/dev/null | grep 'inet ' | awk '{print "  " $2}' | tee -a "$OUTPUT_TEXT" || true
    log_raw "OS version:"
    cat /etc/os-release 2>/dev/null | tee -a "$OUTPUT_TEXT" || true
    log_raw "Kernel: $(uname -r)"
    log_raw "Disk space:"
    df -h 2>/dev/null | tee -a "$OUTPUT_TEXT" || true

    json_add "hostname" "$(hostname -f 2>/dev/null || hostname)"
    json_add "os_version" "$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2)"
    json_add "kernel" "$(uname -r)"
}

discover_oracle_env() {
    log_section "ORACLE ENVIRONMENT"
    log_raw "ORACLE_HOME: ${ORACLE_HOME:-NOT SET}"
    log_raw "ORACLE_SID:  ${ORACLE_SID:-NOT SET}"
    log_raw "ORACLE_BASE: ${ORACLE_BASE:-}"
    log_raw "Oracle version:"
    if [ -f "${ORACLE_HOME:-}/bin/oracle" ]; then
        "${ORACLE_HOME}/bin/oracle" -version 2>&1 | tee -a "$OUTPUT_TEXT" || true
    elif [ -f "${ORACLE_HOME:-}/bin/sqlplus" ]; then
        "${ORACLE_HOME}/bin/sqlplus" -version 2>&1 | tee -a "$OUTPUT_TEXT" || true
    else
        log_warn "Cannot determine Oracle version - binaries not found"
    fi
    json_add "oracle_home" "${ORACLE_HOME:-}"
    json_add "oracle_sid" "${ORACLE_SID:-}"
}

discover_db_config() {
    log_section "DATABASE CONFIGURATION"

    local sql="
SELECT 'DB_NAME='||NAME FROM V\$DATABASE;
SELECT 'DB_UNIQUE_NAME='||DB_UNIQUE_NAME FROM V\$DATABASE;
SELECT 'DBID='||DBID FROM V\$DATABASE;
SELECT 'DB_ROLE='||DATABASE_ROLE FROM V\$DATABASE;
SELECT 'OPEN_MODE='||OPEN_MODE FROM V\$DATABASE;
SELECT 'LOG_MODE='||LOG_MODE FROM V\$DATABASE;
SELECT 'FORCE_LOGGING='||FORCE_LOGGING FROM V\$DATABASE;
SELECT 'SUPPLEMENTAL_LOG_DATA_MIN='||SUPPLEMENTAL_LOG_DATA_MIN FROM V\$DATABASE;
SELECT 'CDB='||CDB FROM V\$DATABASE;
SELECT 'NLS_CHARACTERSET='||VALUE FROM NLS_DATABASE_PARAMETERS WHERE PARAMETER='NLS_CHARACTERSET';
SELECT 'NLS_NCHAR_CHARACTERSET='||VALUE FROM NLS_DATABASE_PARAMETERS WHERE PARAMETER='NLS_NCHAR_CHARACTERSET';
"
    local result
    result=$(run_sql "$sql" 2>&1) || { log_error "Failed to query V\$DATABASE: $result"; return; }
    echo "$result" | tee -a "$OUTPUT_TEXT"

    log_raw "--- Database Size ---"
    run_sql "
SELECT 'DATAFILE_SIZE_GB='||ROUND(SUM(BYTES)/1024/1024/1024,2) FROM DBA_DATA_FILES;
SELECT 'TEMPFILE_SIZE_GB='||ROUND(SUM(BYTES)/1024/1024/1024,2) FROM DBA_TEMP_FILES;
" | tee -a "$OUTPUT_TEXT" || log_warn "Could not get database size"

    json_add "db_name" "$(echo "$result" | grep '^DB_NAME=' | cut -d= -f2)"
    json_add "db_unique_name" "$(echo "$result" | grep '^DB_UNIQUE_NAME=' | cut -d= -f2)"
    json_add "db_role" "$(echo "$result" | grep '^DB_ROLE=' | cut -d= -f2)"
    json_add "open_mode" "$(echo "$result" | grep '^OPEN_MODE=' | cut -d= -f2)"
    json_add "log_mode" "$(echo "$result" | grep '^LOG_MODE=' | cut -d= -f2)"
    json_add "force_logging" "$(echo "$result" | grep '^FORCE_LOGGING=' | cut -d= -f2)"
    json_add "cdb" "$(echo "$result" | grep '^CDB=' | cut -d= -f2)"
}

discover_cdb() {
    log_section "CONTAINER DATABASE (CDB/PDB)"
    local cdb
    cdb=$(run_sql_value "SELECT CDB FROM V\$DATABASE;") || cdb="UNKNOWN"
    log_raw "CDB: $cdb"
    if [ "$cdb" = "YES" ]; then
        run_sql "
SELECT NAME, OPEN_MODE, RESTRICTED, CON_ID
FROM   V\$PDBS
ORDER  BY CON_ID;
" | tee -a "$OUTPUT_TEXT" || log_warn "Could not list PDBs"
    else
        log_raw "Non-CDB (traditional database)"
    fi
    json_add "is_cdb" "$cdb"
}

discover_tde() {
    log_section "TDE CONFIGURATION"
    run_sql "
SELECT WRL_TYPE, WRL_PARAMETER, STATUS, WALLET_TYPE
FROM   V\$ENCRYPTION_WALLET;
" | tee -a "$OUTPUT_TEXT" || log_warn "Could not query TDE wallet"

    run_sql "
SELECT COUNT(*) AS ENCRYPTED_TABLESPACE_COUNT
FROM   V\$ENCRYPTED_TABLESPACES;
" | tee -a "$OUTPUT_TEXT" || log_warn "Could not query encrypted tablespaces"

    run_sql "
SELECT TABLESPACE_NAME, ENCRYPTIONALG
FROM   V\$ENCRYPTED_TABLESPACES;
" | tee -a "$OUTPUT_TEXT" || log_warn "Could not list encrypted tablespaces"
}

discover_supplemental_logging() {
    log_section "SUPPLEMENTAL LOGGING"
    run_sql "
SELECT SUPPLEMENTAL_LOG_DATA_MIN  AS MIN,
       SUPPLEMENTAL_LOG_DATA_PK   AS PK,
       SUPPLEMENTAL_LOG_DATA_UI   AS UI,
       SUPPLEMENTAL_LOG_DATA_FK   AS FK,
       SUPPLEMENTAL_LOG_DATA_ALL  AS ALL_COLS
FROM   V\$DATABASE;
" | tee -a "$OUTPUT_TEXT" || log_warn "Could not query supplemental logging"
}

discover_redo() {
    log_section "REDO / ARCHIVE CONFIGURATION"
    log_raw "--- Redo Log Groups ---"
    run_sql "
SELECT L.GROUP#, L.MEMBERS, ROUND(L.BYTES/1024/1024) AS SIZE_MB, L.STATUS, LF.MEMBER
FROM   V\$LOG L
JOIN   V\$LOGFILE LF ON L.GROUP# = LF.GROUP#
ORDER  BY L.GROUP#;
" | tee -a "$OUTPUT_TEXT" || log_warn "Could not query redo logs"

    log_raw "--- Archive Log Destinations ---"
    run_sql "
SELECT DEST_ID, DEST_NAME, STATUS, TARGET, ARCHIVER, DESTINATION
FROM   V\$ARCHIVE_DEST
WHERE  STATUS != 'INACTIVE'
ORDER  BY DEST_ID;
" | tee -a "$OUTPUT_TEXT" || log_warn "Could not query archive destinations"
}

discover_network() {
    log_section "NETWORK CONFIGURATION"
    log_raw "--- Listener Status ---"
    if [ "$(whoami)" = "$ORACLE_USER" ]; then
        "${ORACLE_HOME:-/u01/app/oracle/product/19.0.0/dbhome_1}/bin/lsnrctl" status 2>&1 | tee -a "$OUTPUT_TEXT" || log_warn "lsnrctl not available"
    else
        sudo -u "$ORACLE_USER" -E env ORACLE_HOME="${ORACLE_HOME:-}" "${ORACLE_HOME:-}/bin/lsnrctl" status 2>&1 | tee -a "$OUTPUT_TEXT" || log_warn "lsnrctl not available"
    fi

    log_raw "--- tnsnames.ora ---"
    local tns_file="${ORACLE_HOME:-}/network/admin/tnsnames.ora"
    if [ -f "$tns_file" ]; then
        cat "$tns_file" | tee -a "$OUTPUT_TEXT"
    else
        log_warn "tnsnames.ora not found at $tns_file"
        find / -name tnsnames.ora 2>/dev/null | head -3 | tee -a "$OUTPUT_TEXT" || true
    fi

    log_raw "--- sqlnet.ora ---"
    local sqlnet_file="${ORACLE_HOME:-}/network/admin/sqlnet.ora"
    if [ -f "$sqlnet_file" ]; then
        cat "$sqlnet_file" | tee -a "$OUTPUT_TEXT"
    else
        log_warn "sqlnet.ora not found at $sqlnet_file"
    fi
}

discover_auth() {
    log_section "AUTHENTICATION"
    log_raw "--- Password file ---"
    local pwd_file="${ORACLE_HOME:-}/dbs/orapw${ORACLE_SID:-}"
    if [ -f "$pwd_file" ]; then
        log_raw "Password file: $pwd_file  ($(ls -la "$pwd_file" 2>/dev/null))"
    else
        log_warn "Password file not found at $pwd_file"
        find "${ORACLE_HOME:-}/dbs" -name 'orapw*' 2>/dev/null | head -5 | tee -a "$OUTPUT_TEXT" || true
    fi

    log_raw "--- SSH directory (oracle user) ---"
    if [ "$(whoami)" = "$ORACLE_USER" ]; then
        ls -la ~/.ssh/ 2>/dev/null | tee -a "$OUTPUT_TEXT" || log_warn "No ~/.ssh directory found"
    else
        sudo -u "$ORACLE_USER" bash -c 'ls -la ~/.ssh/ 2>/dev/null' 2>&1 | tee -a "$OUTPUT_TEXT" || log_warn "Cannot list oracle SSH directory"
    fi
}

discover_dataguard() {
    log_section "DATA GUARD CONFIGURATION"
    run_sql "
SELECT NAME, VALUE
FROM   V\$PARAMETER
WHERE  NAME IN ('log_archive_dest_1','log_archive_dest_2','log_archive_dest_3',
                'log_archive_dest_state_1','log_archive_dest_state_2',
                'db_unique_name','db_file_name_convert','log_file_name_convert',
                'fal_server','fal_client','standby_file_management',
                'dg_broker_start','dg_broker_config_file1','dg_broker_config_file2')
ORDER  BY NAME;
" | tee -a "$OUTPUT_TEXT" || log_warn "Could not query Data Guard parameters"
}

discover_schemas() {
    log_section "SCHEMA INFORMATION"
    log_raw "--- Non-system schemas > 100MB ---"
    run_sql "
SELECT OWNER,
       ROUND(SUM(BYTES)/1024/1024/1024, 3) AS SIZE_GB
FROM   DBA_SEGMENTS
WHERE  OWNER NOT IN ('SYS','SYSTEM','DBSNMP','SYSMAN','OUTLN','XDB','WMSYS',
                     'APEX_040200','APEX_050000','APEX_180100','APEX_190100',
                     'APEX_200100','APEX_210100','MDSYS','CTXSYS','ORDSYS',
                     'ORDPLUGINS','ORDS_METADATA','SI_INFORMTN_SCHEMA',
                     'ANONYMOUS','FLOWS_FILES','OJVMSYS','OLAPSYS','OWBSYS',
                     'SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','LBACSYS',
                     'AUDSYS','GSMADMIN_INTERNAL','GSMCATUSER','GSMUSER',
                     'SYSBACKUP','SYSDG','SYSKM','SYSRAC','DIP','DVF','DVSYS',
                     'OJVMSYS','PERFSTAT','SQLTXPLAIN','STDBYPERF','SH','OE',
                     'HR','IX','PM','BI','SCOTT')
GROUP  BY OWNER
HAVING SUM(BYTES)/1024/1024 > 100
ORDER  BY SIZE_GB DESC;
" | tee -a "$OUTPUT_TEXT" || log_warn "Could not query schema sizes"

    log_raw "--- Invalid objects by owner/type ---"
    run_sql "
SELECT OWNER, OBJECT_TYPE, COUNT(*) AS INVALID_COUNT
FROM   DBA_OBJECTS
WHERE  STATUS = 'INVALID'
  AND  OWNER NOT IN ('SYS','SYSTEM','XDB','MDSYS','CTXSYS','ORDSYS','WMSYS')
GROUP  BY OWNER, OBJECT_TYPE
ORDER  BY OWNER, OBJECT_TYPE;
" | tee -a "$OUTPUT_TEXT" || log_warn "Could not query invalid objects"
}

discover_tablespaces() {
    log_section "TABLESPACE CONFIGURATION"
    run_sql "
SELECT DF.TABLESPACE_NAME,
       DF.FILE_NAME,
       ROUND(DF.BYTES/1024/1024/1024,3)   AS SIZE_GB,
       ROUND(DF.MAXBYTES/1024/1024/1024,3) AS MAXSIZE_GB,
       DF.AUTOEXTENSIBLE,
       ROUND(DF.INCREMENT_BY * 8192 / 1024 / 1024, 1) AS INCREMENT_MB
FROM   DBA_DATA_FILES DF
ORDER  BY DF.TABLESPACE_NAME, DF.FILE_NAME;
" | tee -a "$OUTPUT_TEXT" || log_warn "Could not query tablespace config"
}

discover_backup() {
    log_section "BACKUP CONFIGURATION"
    log_raw "--- RMAN retention policy ---"
    run_sql "
SELECT POLICY_TYPE, VALUE, COMMENTS FROM V\$RMAN_CONFIGURATION
WHERE  POLICY_TYPE IN ('RETENTION POLICY','ARCHIVELOG DELETION POLICY')
       OR NAME LIKE '%RETENTION%' OR NAME LIKE '%DELETION%';
" | tee -a "$OUTPUT_TEXT" || true

    run_sql "
SELECT CONF#, NAME, VALUE FROM V\$RMAN_CONFIGURATION ORDER BY CONF#;
" | tee -a "$OUTPUT_TEXT" || log_warn "Could not query RMAN config"

    log_raw "--- Last successful backup ---"
    run_sql "
SELECT INPUT_TYPE, STATUS,
       TO_CHAR(START_TIME,'YYYY-MM-DD HH24:MI:SS') AS START_TIME,
       TO_CHAR(END_TIME,'YYYY-MM-DD HH24:MI:SS')   AS END_TIME,
       OUTPUT_DEVICE_TYPE
FROM   V\$RMAN_BACKUP_JOB_DETAILS
WHERE  STATUS = 'COMPLETED'
ORDER  BY START_TIME DESC
FETCH FIRST 5 ROWS ONLY;
" | tee -a "$OUTPUT_TEXT" || log_warn "Could not query RMAN backup history"

    log_raw "--- Crontab (backup jobs) ---"
    crontab -l 2>/dev/null | grep -i 'rman\|backup\|arch' | tee -a "$OUTPUT_TEXT" || log_info "No RMAN crontab entries found"
    if [ "$(whoami)" != "$ORACLE_USER" ]; then
        sudo -u "$ORACLE_USER" crontab -l 2>/dev/null | grep -i 'rman\|backup\|arch' | tee -a "$OUTPUT_TEXT" || true
    fi

    log_raw "--- DBMS_SCHEDULER backup jobs ---"
    run_sql "
SELECT OWNER, JOB_NAME, JOB_TYPE, ENABLED,
       TO_CHAR(LAST_START_DATE,'YYYY-MM-DD HH24:MI:SS') AS LAST_RUN,
       TO_CHAR(NEXT_RUN_DATE,'YYYY-MM-DD HH24:MI:SS')   AS NEXT_RUN
FROM   DBA_SCHEDULER_JOBS
WHERE  UPPER(JOB_NAME) LIKE '%RMAN%' OR UPPER(JOB_NAME) LIKE '%BACKUP%' OR UPPER(COMMENTS) LIKE '%BACKUP%'
ORDER  BY OWNER, JOB_NAME;
" | tee -a "$OUTPUT_TEXT" || log_warn "Could not query scheduler backup jobs"
}

discover_db_links() {
    log_section "DATABASE LINKS"
    run_sql "
SELECT OWNER, DB_LINK, USERNAME, HOST, CREATED, STATUS
FROM   DBA_DB_LINKS
ORDER  BY OWNER, DB_LINK;
" | tee -a "$OUTPUT_TEXT" || log_warn "Could not query database links"
}

discover_mviews() {
    log_section "MATERIALIZED VIEWS"
    run_sql "
SELECT OWNER, MVIEW_NAME, REFRESH_METHOD, REFRESH_MODE,
       TO_CHAR(NEXT_STATEMENT,'YYYY-MM-DD HH24:MI:SS') AS NEXT_REFRESH,
       STALENESS
FROM   DBA_MVIEWS
ORDER  BY OWNER, MVIEW_NAME;
" | tee -a "$OUTPUT_TEXT" || log_warn "Could not query materialized views"

    run_sql "
SELECT LOG_OWNER, MASTER, LOG_TABLE
FROM   DBA_MVIEW_LOGS
ORDER  BY LOG_OWNER, MASTER;
" | tee -a "$OUTPUT_TEXT" || log_warn "Could not query materialized view logs"
}

discover_scheduler_jobs() {
    log_section "SCHEDULER JOBS"
    run_sql "
SELECT OWNER, JOB_NAME, JOB_TYPE, SCHEDULE_NAME, ENABLED,
       TO_CHAR(LAST_START_DATE,'YYYY-MM-DD HH24:MI:SS') AS LAST_START,
       TO_CHAR(NEXT_RUN_DATE,'YYYY-MM-DD HH24:MI:SS')   AS NEXT_RUN,
       STATE
FROM   DBA_SCHEDULER_JOBS
WHERE  OWNER NOT IN ('SYS','SYSTEM','DBSNMP','SYSMAN','MDSYS','CTXSYS',
                     'ORDDATA','ORDSYS','XDB','WMSYS','AUDSYS','LBACSYS',
                     'GSMADMIN_INTERNAL','ORACLE_OCM')
ORDER  BY OWNER, JOB_NAME;
" | tee -a "$OUTPUT_TEXT" || log_warn "Could not query scheduler jobs"

    log_raw "--- Jobs referencing external hosts/paths/credentials ---"
    run_sql "
SELECT OWNER, JOB_NAME, JOB_ACTION
FROM   DBA_SCHEDULER_JOBS
WHERE  UPPER(JOB_ACTION) LIKE '%/@%'
    OR UPPER(JOB_ACTION) LIKE '%UTL_FILE%'
    OR UPPER(JOB_ACTION) LIKE '%UTL_HTTP%'
    OR UPPER(JOB_ACTION) LIKE '%DBMS_CREDENTIAL%'
ORDER  BY OWNER, JOB_NAME
FETCH FIRST 50 ROWS ONLY;
" | tee -a "$OUTPUT_TEXT" || log_warn "Could not query external-ref scheduler jobs"
}

# =============================================================================
# GENERATE JSON SUMMARY
# =============================================================================
write_json() {
    {
        echo "{"
        local first=true
        for entry in "${JSON_SECTIONS[@]}"; do
            if [ "$first" = true ]; then
                first=false
            else
                echo ","
            fi
            printf '%s' "$entry"
        done
        echo ""
        echo "}"
    } > "$OUTPUT_JSON"
    log_info "JSON summary written to: $OUTPUT_JSON"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    # Initialize text output file
    > "$OUTPUT_TEXT"

    log_section "ZDM SOURCE DATABASE DISCOVERY"
    log_info "Start time: $(date)"
    log_info "Running as user: $(whoami)"
    log_info "ORACLE_USER: $ORACLE_USER"

    detect_oracle_env

    discover_os
    discover_oracle_env
    discover_db_config     || log_warn "DB config section failed"
    discover_cdb           || log_warn "CDB section failed"
    discover_tde           || log_warn "TDE section failed"
    discover_supplemental_logging || log_warn "Supplemental logging section failed"
    discover_redo          || log_warn "Redo section failed"
    discover_network       || log_warn "Network section failed"
    discover_auth          || log_warn "Auth section failed"
    discover_dataguard     || log_warn "Data Guard section failed"
    discover_schemas       || log_warn "Schema section failed"
    discover_tablespaces   || log_warn "Tablespace section failed"
    discover_backup        || log_warn "Backup section failed"
    discover_db_links      || log_warn "DB Links section failed"
    discover_mviews        || log_warn "Materialized Views section failed"
    discover_scheduler_jobs || log_warn "Scheduler Jobs section failed"

    json_add "discovery_timestamp" "$TIMESTAMP"
    json_add "discovery_host" "$HOSTNAME_SHORT"
    write_json

    log_section "DISCOVERY COMPLETE"
    log_info "End time: $(date)"
    log_info "Text report: $OUTPUT_TEXT"
    log_info "JSON summary: $OUTPUT_JSON"
}

main "$@"
