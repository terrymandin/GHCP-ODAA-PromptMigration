#!/usr/bin/env bash
# =============================================================================
# zdm_source_discovery.sh
# Phase 10 — ZDM Migration · Step 2: Source Database Discovery
#
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration
#
# Runs on the SOURCE database server (via SSH as ADMIN_USER with sudo for oracle).
# Discovers OS, Oracle environment, database configuration, TDE, supplemental logging,
# redo/archive, network, authentication, Data Guard, schema info, tablespaces,
# backup config, database links, materialized views, and scheduler jobs.
#
# Outputs (written to current working directory):
#   zdm_source_discovery_<hostname>_<timestamp>.txt
#   zdm_source_discovery_<hostname>_<timestamp>.json
#
# Usage (typically invoked by zdm_orchestrate_discovery.sh):
#   bash zdm_source_discovery.sh
#
# Overrides (optional environment variables):
#   ORACLE_HOME  - Override auto-detected Oracle home
#   ORACLE_SID   - Override auto-detected Oracle SID
#   ORACLE_USER  - Oracle software owner (default: oracle)
# =============================================================================

# DO NOT use set -e globally — allows individual section failures without aborting
set -uo pipefail

# ---------------------------------------------------------------------------
# Configuration defaults
# ---------------------------------------------------------------------------
ORACLE_USER="${ORACLE_USER:-oracle}"

HOSTNAME_VAL="$(hostname -s 2>/dev/null || hostname)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_TXT="./zdm_source_discovery_${HOSTNAME_VAL}_${TIMESTAMP}.txt"
REPORT_JSON="./zdm_source_discovery_${HOSTNAME_VAL}_${TIMESTAMP}.json"

# ---------------------------------------------------------------------------
# Logging helpers (write to both stdout and report file)
# ---------------------------------------------------------------------------
log_raw() {
    local msg="$1"
    echo "$msg" | tee -a "${REPORT_TXT}"
}

log_section() {
    local title="$1"
    local line="============================================================"
    echo "" | tee -a "${REPORT_TXT}"
    echo "${line}" | tee -a "${REPORT_TXT}"
    echo "  ${title}" | tee -a "${REPORT_TXT}"
    echo "${line}" | tee -a "${REPORT_TXT}"
}

log_info() {
    log_raw "  [INFO]  $*"
}

log_warn() {
    log_raw "  [WARN]  $*"
}

log_error() {
    log_raw "  [ERROR] $*"
}

# ---------------------------------------------------------------------------
# Oracle environment auto-detection
# ---------------------------------------------------------------------------
detect_oracle_env() {
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        return 0
    fi

    # Method 1: Parse /etc/oratab
    if [ -f /etc/oratab ]; then
        local oratab_entry
        if [ -n "${ORACLE_SID:-}" ]; then
            oratab_entry=$(grep "^${ORACLE_SID}:" /etc/oratab 2>/dev/null | head -1)
        else
            oratab_entry=$(grep -v '^#' /etc/oratab | grep -v '^$' | head -1)
        fi
        if [ -n "${oratab_entry:-}" ]; then
            export ORACLE_SID="${ORACLE_SID:-$(echo "$oratab_entry" | cut -d: -f1)}"
            export ORACLE_HOME="${ORACLE_HOME:-$(echo "$oratab_entry" | cut -d: -f2)}"
        fi
    fi

    # Method 2: Check running pmon process
    if [ -z "${ORACLE_SID:-}" ]; then
        local pmon_sid
        pmon_sid=$(ps -ef | grep 'ora_pmon_' | grep -v grep | head -1 | sed 's/.*ora_pmon_//' 2>/dev/null || true)
        [ -n "${pmon_sid:-}" ] && export ORACLE_SID="$pmon_sid"
    fi

    # Method 3: Search common Oracle installation paths
    if [ -z "${ORACLE_HOME:-}" ]; then
        for path in /u01/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1 /oracle/product/*/dbhome_1; do
            if [ -d "$path" ] && [ -f "$path/bin/sqlplus" ]; then
                export ORACLE_HOME="$path"
                break
            fi
        done
    fi

    # Method 4: Use oraenv
    if [ -z "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        [ -f /usr/local/bin/oraenv ] && ORACLE_SID="$ORACLE_SID" . /usr/local/bin/oraenv <<< "$ORACLE_SID" 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------
# SQL execution helper
# ---------------------------------------------------------------------------
run_sql() {
    local sql_query="$1"
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        local sqlplus_cmd="${ORACLE_HOME}/bin/sqlplus -s / as sysdba"
        local sql_script
        sql_script=$(printf 'SET PAGESIZE 1000\nSET LINESIZE 200\nSET FEEDBACK OFF\nSET HEADING ON\nSET ECHO OFF\n%s\n' "$sql_query")
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            echo "$sql_script" | $sqlplus_cmd 2>&1
        else
            echo "$sql_script" | sudo -u "$ORACLE_USER" -E ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd 2>&1
        fi
    else
        echo "SKIPPED: ORACLE_HOME or ORACLE_SID not set"
        return 1
    fi
}

run_sql_value() {
    local sql_query="$1"
    run_sql "SET PAGESIZE 0
SET FEEDBACK OFF
SET HEADING OFF
SET ECHO OFF
SET TRIMOUT ON
${sql_query}" 2>/dev/null | grep -v '^$' | head -1 | tr -d ' '
}

# ---------------------------------------------------------------------------
# Section: OS Information
# ---------------------------------------------------------------------------
section_os() {
    log_section "OS INFORMATION"
    log_info "Hostname:          $(hostname)"
    log_info "OS Release:        $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"' || uname -a)"
    log_info "Kernel:            $(uname -r)"
    log_info "Architecture:      $(uname -m)"
    log_info "Date/Time:         $(date)"
    log_info "Uptime:            $(uptime)"
    log_info ""
    log_info "-- IP Addresses --"
    ip addr show 2>/dev/null | grep 'inet ' | awk '{print "  " $2 " dev " $NF}' | tee -a "${REPORT_TXT}" || \
        ifconfig 2>/dev/null | grep 'inet ' | tee -a "${REPORT_TXT}" || log_warn "Could not retrieve IP addresses"
    log_info ""
    log_info "-- Disk Space --"
    df -h 2>/dev/null | tee -a "${REPORT_TXT}" || log_warn "df command failed"
}

# ---------------------------------------------------------------------------
# Section: Oracle Environment
# ---------------------------------------------------------------------------
section_oracle_env() {
    log_section "ORACLE ENVIRONMENT"
    log_info "ORACLE_HOME:       ${ORACLE_HOME:-NOT SET}"
    log_info "ORACLE_SID:        ${ORACLE_SID:-NOT SET}"
    log_info "ORACLE_BASE:       ${ORACLE_BASE:-NOT SET}"
    if [ -n "${ORACLE_HOME:-}" ] && [ -f "${ORACLE_HOME}/bin/sqlplus" ]; then
        local ver
        ver=$(${ORACLE_HOME}/bin/sqlplus -V 2>/dev/null | head -3 || echo "UNKNOWN")
        log_info "Oracle Version:    ${ver}"
    else
        log_warn "sqlplus not found at ${ORACLE_HOME:-UNKNOWN}/bin/sqlplus"
    fi
}

# ---------------------------------------------------------------------------
# Section: Database Configuration
# ---------------------------------------------------------------------------
section_db_config() {
    log_section "DATABASE CONFIGURATION"
    local db_name db_unique_name dbid db_role open_mode log_mode force_log
    db_name=$(run_sql_value "SELECT NAME FROM V\$DATABASE;" 2>/dev/null || echo "N/A")
    db_unique_name=$(run_sql_value "SELECT DB_UNIQUE_NAME FROM V\$DATABASE;" 2>/dev/null || echo "N/A")
    dbid=$(run_sql_value "SELECT DBID FROM V\$DATABASE;" 2>/dev/null || echo "N/A")
    db_role=$(run_sql_value "SELECT DATABASE_ROLE FROM V\$DATABASE;" 2>/dev/null || echo "N/A")
    open_mode=$(run_sql_value "SELECT OPEN_MODE FROM V\$DATABASE;" 2>/dev/null || echo "N/A")
    log_mode=$(run_sql_value "SELECT LOG_MODE FROM V\$DATABASE;" 2>/dev/null || echo "N/A")
    force_log=$(run_sql_value "SELECT FORCE_LOGGING FROM V\$DATABASE;" 2>/dev/null || echo "N/A")

    log_info "DB Name:           ${db_name}"
    log_info "DB Unique Name:    ${db_unique_name}"
    log_info "DBID:              ${dbid}"
    log_info "DB Role:           ${db_role}"
    log_info "Open Mode:         ${open_mode}"
    log_info "Log Mode:          ${log_mode}"
    log_info "Force Logging:     ${force_log}"

    log_info ""
    log_info "-- Database Size (Data Files) --"
    run_sql "SELECT TABLESPACE_NAME, ROUND(SUM(BYTES)/1073741824,2) AS SIZE_GB
FROM DBA_DATA_FILES
GROUP BY TABLESPACE_NAME
ORDER BY SIZE_GB DESC;" | tee -a "${REPORT_TXT}" || log_warn "Could not query data file sizes"

    log_info ""
    log_info "-- Database Size (Temp Files) --"
    run_sql "SELECT TABLESPACE_NAME, ROUND(SUM(BYTES)/1073741824,2) AS SIZE_GB
FROM DBA_TEMP_FILES
GROUP BY TABLESPACE_NAME;" | tee -a "${REPORT_TXT}" || log_warn "Could not query temp file sizes"

    log_info ""
    log_info "-- Character Set --"
    run_sql "SELECT PARAMETER, VALUE FROM NLS_DATABASE_PARAMETERS
WHERE PARAMETER IN ('NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET');" | tee -a "${REPORT_TXT}" || true
}

# ---------------------------------------------------------------------------
# Section: Container Database (CDB/PDB)
# ---------------------------------------------------------------------------
section_cdb() {
    log_section "CONTAINER DATABASE (CDB/PDB)"
    local cdb_status
    cdb_status=$(run_sql_value "SELECT CDB FROM V\$DATABASE;" 2>/dev/null || echo "N/A")
    log_info "CDB:               ${cdb_status}"
    if [ "${cdb_status}" = "YES" ]; then
        log_info ""
        log_info "-- PDB List --"
        run_sql "SELECT NAME, OPEN_MODE, RESTRICTED FROM V\$PDBS ORDER BY NAME;" | tee -a "${REPORT_TXT}" || true
    fi
}

# ---------------------------------------------------------------------------
# Section: TDE Configuration
# ---------------------------------------------------------------------------
section_tde() {
    log_section "TDE CONFIGURATION"
    log_info "-- Wallet Status --"
    run_sql "SELECT WRL_TYPE, WRL_PARAMETER, STATUS, WALLET_TYPE FROM V\$ENCRYPTION_WALLET;" \
        | tee -a "${REPORT_TXT}" || log_warn "Could not query TDE wallet (may not be configured)"

    log_info ""
    log_info "-- Encrypted Tablespaces --"
    run_sql "SELECT TABLESPACE_NAME, ENCRYPTED FROM DBA_TABLESPACES
WHERE ENCRYPTED = 'YES' ORDER BY TABLESPACE_NAME;" | tee -a "${REPORT_TXT}" || true

    log_info ""
    log_info "-- TDE Master Key Info --"
    run_sql "SELECT KEY_ID, CREATOR, CREATOR_DBNAME, CREATION_TIME, ACTIVATION_TIME
FROM V\$ENCRYPTION_KEYS ORDER BY CREATION_TIME DESC FETCH FIRST 5 ROWS ONLY;" \
        | tee -a "${REPORT_TXT}" || log_warn "Could not query V\$ENCRYPTION_KEYS"
}

# ---------------------------------------------------------------------------
# Section: Supplemental Logging
# ---------------------------------------------------------------------------
section_supplemental_logging() {
    log_section "SUPPLEMENTAL LOGGING"
    run_sql "SELECT LOG_MODE, SUPPLEMENTAL_LOG_DATA_MIN,
       SUPPLEMENTAL_LOG_DATA_PK, SUPPLEMENTAL_LOG_DATA_UI,
       SUPPLEMENTAL_LOG_DATA_FK, SUPPLEMENTAL_LOG_DATA_ALL
FROM V\$DATABASE;" | tee -a "${REPORT_TXT}" || log_warn "Could not query supplemental logging"
}

# ---------------------------------------------------------------------------
# Section: Redo / Archive Configuration
# ---------------------------------------------------------------------------
section_redo_archive() {
    log_section "REDO / ARCHIVE CONFIGURATION"
    log_info "-- Redo Log Groups --"
    run_sql "SELECT L.GROUP#, L.MEMBERS, L.STATUS, ROUND(L.BYTES/1048576,0) AS SIZE_MB
FROM V\$LOG L ORDER BY L.GROUP#;" | tee -a "${REPORT_TXT}" || true

    log_info ""
    log_info "-- Redo Log Members --"
    run_sql "SELECT GROUP#, MEMBER, STATUS FROM V\$LOGFILE ORDER BY GROUP#, MEMBER;" \
        | tee -a "${REPORT_TXT}" || true

    log_info ""
    log_info "-- Archive Log Destinations --"
    run_sql "SELECT DEST_ID, STATUS, TARGET, ARCHIVER, SCHEDULE, DESTINATION
FROM V\$ARCHIVE_DEST WHERE STATUS != 'INACTIVE' ORDER BY DEST_ID;" \
        | tee -a "${REPORT_TXT}" || true

    log_info ""
    log_info "-- Archive Log Mode --"
    run_sql "SELECT LOG_MODE FROM V\$DATABASE;" | tee -a "${REPORT_TXT}" || true
}

# ---------------------------------------------------------------------------
# Section: Network Configuration
# ---------------------------------------------------------------------------
section_network() {
    log_section "NETWORK CONFIGURATION"
    log_info "-- Listener Status --"
    if [ -n "${ORACLE_HOME:-}" ]; then
        "${ORACLE_HOME}/bin/lsnrctl" status 2>&1 | tee -a "${REPORT_TXT}" || log_warn "lsnrctl status failed"
    else
        log_warn "ORACLE_HOME not set; skipping lsnrctl"
    fi

    log_info ""
    log_info "-- tnsnames.ora --"
    local tns_file=""
    [ -n "${ORACLE_HOME:-}" ] && tns_file="${ORACLE_HOME}/network/admin/tnsnames.ora"
    if [ -n "${tns_file:-}" ] && [ -f "${tns_file}" ]; then
        cat "${tns_file}" | tee -a "${REPORT_TXT}"
    else
        log_warn "tnsnames.ora not found at ${tns_file:-UNKNOWN}"
    fi

    log_info ""
    log_info "-- sqlnet.ora --"
    local sqlnet_file=""
    [ -n "${ORACLE_HOME:-}" ] && sqlnet_file="${ORACLE_HOME}/network/admin/sqlnet.ora"
    if [ -n "${sqlnet_file:-}" ] && [ -f "${sqlnet_file}" ]; then
        cat "${sqlnet_file}" | tee -a "${REPORT_TXT}"
    else
        log_warn "sqlnet.ora not found at ${sqlnet_file:-UNKNOWN}"
    fi
}

# ---------------------------------------------------------------------------
# Section: Authentication
# ---------------------------------------------------------------------------
section_auth() {
    log_section "AUTHENTICATION"
    log_info "-- Password File Location --"
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        local pwfile
        pwfile=$(find "${ORACLE_HOME}/dbs" -name "orapw${ORACLE_SID}" -o -name "orapw${ORACLE_SID^^}" 2>/dev/null | head -1)
        if [ -n "${pwfile:-}" ]; then
            log_info "Password file: ${pwfile}"
            ls -lh "${pwfile}" 2>/dev/null | tee -a "${REPORT_TXT}" || true
        else
            log_warn "Password file not found in ${ORACLE_HOME}/dbs"
        fi
    fi

    log_info ""
    log_info "-- SSH Directory (oracle user) --"
    local oracle_home_dir
    oracle_home_dir=$(eval echo "~${ORACLE_USER}" 2>/dev/null || echo "/home/${ORACLE_USER}")
    if [ -d "${oracle_home_dir}/.ssh" ]; then
        ls -la "${oracle_home_dir}/.ssh/" 2>/dev/null | tee -a "${REPORT_TXT}" || true
    else
        log_warn ".ssh directory not found for ${ORACLE_USER} at ${oracle_home_dir}/.ssh"
    fi
}

# ---------------------------------------------------------------------------
# Section: Data Guard
# ---------------------------------------------------------------------------
section_data_guard() {
    log_section "DATA GUARD CONFIGURATION"
    log_info "-- Data Guard Parameters --"
    run_sql "SELECT NAME, VALUE FROM V\$PARAMETER
WHERE NAME IN (
    'log_archive_config','log_archive_dest_1','log_archive_dest_2',
    'db_unique_name','standby_file_management','fal_server','fal_client',
    'log_archive_dest_state_1','log_archive_dest_state_2'
)
ORDER BY NAME;" | tee -a "${REPORT_TXT}" || true

    log_info ""
    log_info "-- DG Broker Configuration (if any) --"
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        local dgmgrl_cmd="${ORACLE_HOME}/bin/dgmgrl"
        if [ -f "$dgmgrl_cmd" ]; then
            echo "show configuration;" | ( [ "$(whoami)" = "$ORACLE_USER" ] && \
                "$dgmgrl_cmd" -silent / || \
                sudo -u "$ORACLE_USER" -E ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" \
                    "$dgmgrl_cmd" -silent / ) 2>&1 | tee -a "${REPORT_TXT}" || true
        else
            log_warn "dgmgrl not found"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Section: Schema Information
# ---------------------------------------------------------------------------
section_schemas() {
    log_section "SCHEMA INFORMATION"
    log_info "-- Schema Sizes (non-system, > 100MB) --"
    run_sql "SELECT OWNER, ROUND(SUM(BYTES)/1073741824,3) AS SIZE_GB
FROM DBA_SEGMENTS
WHERE OWNER NOT IN (
    'SYS','SYSTEM','SYSAUX','OUTLN','DBSNMP','APPQOSSYS','DBSFWUSER',
    'GGSYS','ANONYMOUS','CTXSYS','DVSYS','DVF','GSMADMIN_INTERNAL',
    'MDSYS','OLAPSYS','ORDSYS','ORDPLUGINS','ORDDATA','SI_INFORMTN_SCHEMA',
    'LBACSYS','XDB','WMSYS','OJVMSYS','REMOTE_SCHEDULER_AGENT',
    'SH','BI','HR','OE','PM','IX','SCOTT'
)
GROUP BY OWNER
HAVING SUM(BYTES) > 104857600
ORDER BY SIZE_GB DESC;" | tee -a "${REPORT_TXT}" || true

    log_info ""
    log_info "-- Invalid Objects by Owner/Type --"
    run_sql "SELECT OWNER, OBJECT_TYPE, COUNT(*) AS INVALID_COUNT
FROM DBA_OBJECTS
WHERE STATUS = 'INVALID'
GROUP BY OWNER, OBJECT_TYPE
ORDER BY OWNER, OBJECT_TYPE;" | tee -a "${REPORT_TXT}" || true
}

# ---------------------------------------------------------------------------
# Section: Tablespace Configuration
# ---------------------------------------------------------------------------
section_tablespaces() {
    log_section "TABLESPACE CONFIGURATION"
    log_info "-- Autoextend Settings --"
    run_sql "SELECT D.TABLESPACE_NAME, D.FILE_NAME,
       ROUND(D.BYTES/1073741824,2) AS CURRENT_GB,
       D.AUTOEXTENSIBLE,
       ROUND(D.MAXBYTES/1073741824,2) AS MAX_GB,
       ROUND(D.INCREMENT_BY*8192/1048576,2) AS INCREMENT_MB
FROM DBA_DATA_FILES D
ORDER BY D.TABLESPACE_NAME, D.FILE_NAME;" | tee -a "${REPORT_TXT}" || true
}

# ---------------------------------------------------------------------------
# Section: Backup Configuration
# ---------------------------------------------------------------------------
section_backup() {
    log_section "BACKUP CONFIGURATION"
    log_info "-- RMAN Retention Policy --"
    run_sql "SELECT RMAN_FULL_SIZE_LIMIT_TYPE, RMAN_FULL_SIZE_LIMIT_DAYS
FROM V\$RMAN_CONFIGURATION WHERE NAME IN ('RETENTION POLICY');
SELECT RESTYPE, ROUND(CFGSIZE/1048576,0) AS CFG_MB
FROM V\$RMAN_CONFIGURATION WHERE 1=0;" 2>/dev/null | tee -a "${REPORT_TXT}" || true

    run_sql "SELECT RECID, NAME, VALUE FROM V\$RMAN_CONFIGURATION
WHERE NAME LIKE '%RETENTION%' OR NAME LIKE '%DELETE%' OR NAME LIKE '%BACKUP%'
ORDER BY NAME;" | tee -a "${REPORT_TXT}" || true

    log_info ""
    log_info "-- Last RMAN Backup --"
    run_sql "SELECT COMPLETION_TIME, INPUT_TYPE, STATUS,
       ROUND(INPUT_BYTES/1073741824,2) AS INPUT_GB,
       ROUND(OUTPUT_BYTES/1073741824,2) AS OUTPUT_GB,
       OUTPUT_DEVICE_TYPE
FROM V\$RMAN_BACKUP_JOB_DETAILS
ORDER BY COMPLETION_TIME DESC
FETCH FIRST 10 ROWS ONLY;" | tee -a "${REPORT_TXT}" || true

    log_info ""
    log_info "-- Crontab (RMAN-related) --"
    crontab -l 2>/dev/null | grep -i 'rman\|backup\|arch' | tee -a "${REPORT_TXT}" || \
        log_info "No RMAN cron entries found for current user"

    log_info ""
    log_info "-- DBMS_SCHEDULER Backup Jobs --"
    run_sql "SELECT JOB_NAME, OWNER, JOB_ACTION, ENABLED, LAST_START_DATE, NEXT_RUN_DATE
FROM DBA_SCHEDULER_JOBS
WHERE UPPER(JOB_NAME) LIKE '%BACKUP%' OR UPPER(JOB_ACTION) LIKE '%RMAN%'
ORDER BY OWNER, JOB_NAME;" | tee -a "${REPORT_TXT}" || true
}

# ---------------------------------------------------------------------------
# Section: Database Links
# ---------------------------------------------------------------------------
section_db_links() {
    log_section "DATABASE LINKS"
    run_sql "SELECT DB_LINK, OWNER, USERNAME, HOST, CREATED
FROM DBA_DB_LINKS
ORDER BY OWNER, DB_LINK;" | tee -a "${REPORT_TXT}" || true
}

# ---------------------------------------------------------------------------
# Section: Materialized Views
# ---------------------------------------------------------------------------
section_mviews() {
    log_section "MATERIALIZED VIEWS"
    log_info "-- Materialized Views --"
    run_sql "SELECT OWNER, MVIEW_NAME, REFRESH_MODE, REFRESH_METHOD, COMPILE_STATE, LAST_REFRESH_DATE, NEXT
FROM DBA_MVIEWS
ORDER BY OWNER, MVIEW_NAME;" | tee -a "${REPORT_TXT}" || true

    log_info ""
    log_info "-- Materialized View Logs --"
    run_sql "SELECT LOG_OWNER, MASTER, LOG_TABLE, ROWIDS, PRIMARY_KEY, SEQUENCE, INCLUDE_NEW_VALUES
FROM DBA_MVIEW_LOGS
ORDER BY LOG_OWNER, MASTER;" | tee -a "${REPORT_TXT}" || true
}

# ---------------------------------------------------------------------------
# Section: Scheduler Jobs
# ---------------------------------------------------------------------------
section_scheduler_jobs() {
    log_section "SCHEDULER JOBS"
    run_sql "SELECT OWNER, JOB_NAME, JOB_TYPE, SCHEDULE_TYPE, ENABLED,
       TO_CHAR(LAST_START_DATE,'YYYY-MM-DD HH24:MI') AS LAST_RUN,
       TO_CHAR(NEXT_RUN_DATE,'YYYY-MM-DD HH24:MI') AS NEXT_RUN,
       JOB_ACTION
FROM DBA_SCHEDULER_JOBS
WHERE OWNER NOT IN ('SYS','SYSTEM','EXFSYS','ORACLE_OCM','WMSYS','XDB','MDSYS','ORDDATA','ORDSYS')
ORDER BY OWNER, JOB_NAME;" | tee -a "${REPORT_TXT}" || true
}

# ---------------------------------------------------------------------------
# Build JSON summary
# ---------------------------------------------------------------------------
build_json() {
    local db_name db_unique_name dbid db_role open_mode log_mode force_log cdb_status
    db_name=$(run_sql_value "SELECT NAME FROM V\$DATABASE;" 2>/dev/null || echo "N/A")
    db_unique_name=$(run_sql_value "SELECT DB_UNIQUE_NAME FROM V\$DATABASE;" 2>/dev/null || echo "N/A")
    dbid=$(run_sql_value "SELECT DBID FROM V\$DATABASE;" 2>/dev/null || echo "N/A")
    db_role=$(run_sql_value "SELECT DATABASE_ROLE FROM V\$DATABASE;" 2>/dev/null || echo "N/A")
    open_mode=$(run_sql_value "SELECT OPEN_MODE FROM V\$DATABASE;" 2>/dev/null || echo "N/A")
    log_mode=$(run_sql_value "SELECT LOG_MODE FROM V\$DATABASE;" 2>/dev/null || echo "N/A")
    force_log=$(run_sql_value "SELECT FORCE_LOGGING FROM V\$DATABASE;" 2>/dev/null || echo "N/A")
    cdb_status=$(run_sql_value "SELECT CDB FROM V\$DATABASE;" 2>/dev/null || echo "N/A")
    local charset nchar_set tde_status
    charset=$(run_sql_value "SELECT VALUE FROM NLS_DATABASE_PARAMETERS WHERE PARAMETER='NLS_CHARACTERSET';" 2>/dev/null || echo "N/A")
    nchar_set=$(run_sql_value "SELECT VALUE FROM NLS_DATABASE_PARAMETERS WHERE PARAMETER='NLS_NCHAR_CHARACTERSET';" 2>/dev/null || echo "N/A")
    tde_status=$(run_sql_value "SELECT STATUS FROM V\$ENCRYPTION_WALLET WHERE ROWNUM=1;" 2>/dev/null || echo "N/A")

    cat > "${REPORT_JSON}" <<JSONEOF
{
  "report_type": "source_discovery",
  "hostname": "${HOSTNAME_VAL}",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "oracle_environment": {
    "oracle_home": "${ORACLE_HOME:-N/A}",
    "oracle_sid": "${ORACLE_SID:-N/A}",
    "oracle_base": "${ORACLE_BASE:-N/A}"
  },
  "database": {
    "db_name": "${db_name}",
    "db_unique_name": "${db_unique_name}",
    "dbid": "${dbid}",
    "db_role": "${db_role}",
    "open_mode": "${open_mode}",
    "log_mode": "${log_mode}",
    "force_logging": "${force_log}",
    "cdb": "${cdb_status}",
    "character_set": "${charset}",
    "nchar_character_set": "${nchar_set}"
  },
  "tde": {
    "wallet_status": "${tde_status}"
  },
  "report_files": {
    "text_report": "${REPORT_TXT}",
    "json_summary": "${REPORT_JSON}"
  }
}
JSONEOF
    log_info "JSON summary written to: ${REPORT_JSON}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    # Initialize report file
    echo "# ZDM Source Discovery Report" > "${REPORT_TXT}"
    echo "# Generated: $(date)" >> "${REPORT_TXT}"
    echo "# Host: $(hostname)" >> "${REPORT_TXT}"
    echo "# Run as: $(whoami)" >> "${REPORT_TXT}"

    log_section "ZDM SOURCE DISCOVERY — Phase 10 Step 2"
    log_info "Started:  $(date)"
    log_info "Run as:   $(whoami)@$(hostname)"
    log_info "Oracle User: ${ORACLE_USER}"

    # Detect Oracle environment
    detect_oracle_env
    log_info "ORACLE_HOME: ${ORACLE_HOME:-NOT DETECTED}"
    log_info "ORACLE_SID:  ${ORACLE_SID:-NOT DETECTED}"

    # Apply explicit overrides (highest priority)
    [ -n "${SOURCE_REMOTE_ORACLE_HOME:-}" ] && export ORACLE_HOME="$SOURCE_REMOTE_ORACLE_HOME"
    [ -n "${SOURCE_ORACLE_SID:-}" ]         && export ORACLE_SID="$SOURCE_ORACLE_SID"
    [ -n "${SOURCE_REMOTE_ORACLE_SID:-}" ]  && export ORACLE_SID="$SOURCE_REMOTE_ORACLE_SID"

    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        log_warn "Oracle environment not fully detected — SQL sections will be skipped"
    fi

    # Run all discovery sections (each continues on failure)
    section_os           || log_warn "OS section encountered errors"
    section_oracle_env   || log_warn "Oracle env section encountered errors"
    section_db_config    || log_warn "DB config section encountered errors"
    section_cdb          || log_warn "CDB section encountered errors"
    section_tde          || log_warn "TDE section encountered errors"
    section_supplemental_logging || log_warn "Supplemental logging section encountered errors"
    section_redo_archive || log_warn "Redo/archive section encountered errors"
    section_network      || log_warn "Network section encountered errors"
    section_auth         || log_warn "Authentication section encountered errors"
    section_data_guard   || log_warn "Data Guard section encountered errors"
    section_schemas      || log_warn "Schema section encountered errors"
    section_tablespaces  || log_warn "Tablespace section encountered errors"
    section_backup       || log_warn "Backup section encountered errors"
    section_db_links     || log_warn "DB links section encountered errors"
    section_mviews       || log_warn "MViews section encountered errors"
    section_scheduler_jobs || log_warn "Scheduler jobs section encountered errors"

    log_section "DISCOVERY COMPLETE"
    log_info "Finished: $(date)"
    log_info "Text report:  ${REPORT_TXT}"
    log_info "JSON summary: ${REPORT_JSON}"

    build_json
}

main "$@"
