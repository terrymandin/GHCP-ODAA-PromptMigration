#!/bin/bash
# =============================================================================
# zdm_source_discovery.sh
# ZDM Migration - Source Database Discovery Script
# Project: ORADB
#
# Purpose: Gather technical context from the source Oracle database server.
#          Executed via SSH as SOURCE_ADMIN_USER; SQL commands run as oracle
#          user via sudo following the enterprise admin-user-with-sudo pattern.
#
# Usage: bash zdm_source_discovery.sh [-v] [-h]
#   -v  Verbose output
#   -h  Show usage
#
# Output:
#   ./zdm_source_discovery_<hostname>_<timestamp>.txt
#   ./zdm_source_discovery_<hostname>_<timestamp>.json
# =============================================================================

# --- Do NOT use set -e; individual sections handle their own errors ---

# -----------------------------------------------------------------------
# Colour helpers
# -----------------------------------------------------------------------
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

VERBOSE=false
for arg in "$@"; do
    case "$arg" in
        -v|--verbose) VERBOSE=true ;;
        -h|--help)
            echo "Usage: $0 [-v] [-h]"
            echo "  -v  Verbose output"
            echo "  -h  Show this help"
            exit 0
            ;;
    esac
done

# -----------------------------------------------------------------------
# Output file setup
# -----------------------------------------------------------------------
HOSTNAME_SHORT=$(hostname -s 2>/dev/null || hostname)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="./zdm_source_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_source_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

# Default oracle user
ORACLE_USER="${ORACLE_USER:-oracle}"

# -----------------------------------------------------------------------
# Logging functions
# -----------------------------------------------------------------------
log_info()    { echo -e "${GREEN}[INFO ]${RESET} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN ]${RESET} $*"; }
log_error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
log_debug()   { $VERBOSE && echo -e "${CYAN}[DEBUG]${RESET} $*" || true; }
log_section() { echo -e "\n${BOLD}${CYAN}=== $* ===${RESET}"; }

# log_raw: write a line to the text report file
log_raw() { echo "$*" >> "$REPORT_FILE"; }

# -----------------------------------------------------------------------
# Auto-detect Oracle environment
# -----------------------------------------------------------------------
detect_oracle_env() {
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        log_debug "Oracle env already set: ORACLE_HOME=$ORACLE_HOME ORACLE_SID=$ORACLE_SID"
        return 0
    fi

    # Method 1: /etc/oratab
    if [ -f /etc/oratab ]; then
        local entry
        if [ -n "${ORACLE_SID:-}" ]; then
            entry=$(grep "^${ORACLE_SID}:" /etc/oratab 2>/dev/null | head -1)
        else
            entry=$(grep -v '^#' /etc/oratab 2>/dev/null | grep -v '^$' | head -1)
        fi
        if [ -n "$entry" ]; then
            export ORACLE_SID="${ORACLE_SID:-$(echo "$entry" | cut -d: -f1)}"
            export ORACLE_HOME="${ORACLE_HOME:-$(echo "$entry" | cut -d: -f2)}"
            log_debug "Detected via /etc/oratab: SID=$ORACLE_SID HOME=$ORACLE_HOME"
        fi
    fi

    # Method 2: pmon process
    if [ -z "${ORACLE_SID:-}" ]; then
        local pmon_sid
        pmon_sid=$(ps -ef 2>/dev/null | grep 'ora_pmon_' | grep -v grep | head -1 | sed 's/.*ora_pmon_//')
        [ -n "$pmon_sid" ] && export ORACLE_SID="$pmon_sid" && log_debug "Detected SID from pmon: $ORACLE_SID"
    fi

    # Method 3: common paths
    if [ -z "${ORACLE_HOME:-}" ]; then
        for p in /u01/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1 /oracle/product/*/dbhome_1; do
            if [ -d "$p" ] && [ -f "$p/bin/sqlplus" ]; then
                export ORACLE_HOME="$p"
                log_debug "Detected ORACLE_HOME from common path: $ORACLE_HOME"
                break
            fi
        done
    fi

    # Method 4: oraenv
    if [ -z "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ] && [ -f /usr/local/bin/oraenv ]; then
        ORACLE_PATH_UAP=YES
        export ORACLE_PATH_UAP
        . /usr/local/bin/oraenv <<< "$ORACLE_SID" 2>/dev/null || true
        log_debug "Tried oraenv for SID=$ORACLE_SID: ORACLE_HOME=${ORACLE_HOME:-unset}"
    fi

    # Apply explicit overrides (highest priority, passed from orchestration)
    [ -n "${ORACLE_HOME_OVERRIDE:-}" ] && export ORACLE_HOME="$ORACLE_HOME_OVERRIDE"
    [ -n "${ORACLE_SID_OVERRIDE:-}" ]  && export ORACLE_SID="$ORACLE_SID_OVERRIDE"

    export ORACLE_BASE="${ORACLE_BASE:-$(dirname "$(dirname "${ORACLE_HOME:-/u01/app/oracle/product/19.0.0/dbhome_1}")")}"
}

# -----------------------------------------------------------------------
# SQL execution helper - runs as ORACLE_USER via sudo if needed
# -----------------------------------------------------------------------
run_sql() {
    local sql_query="$1"
    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        echo "ERROR: ORACLE_HOME or ORACLE_SID not set"
        return 1
    fi
    local sqlplus_cmd="${ORACLE_HOME}/bin/sqlplus -s / as sysdba"
    local sql_script
    sql_script=$(printf 'SET PAGESIZE 1000\nSET LINESIZE 200\nSET FEEDBACK OFF\nSET HEADING ON\nSET ECHO OFF\nSET TRIMSPOOL ON\n%s\nEXIT;\n' "$sql_query")
    if [ "$(whoami)" = "$ORACLE_USER" ]; then
        echo "$sql_script" | $sqlplus_cmd 2>&1
    else
        echo "$sql_script" | sudo -u "$ORACLE_USER" -E ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd 2>&1
    fi
}

run_sql_value() {
    local sql_query="$1"
    run_sql "SET PAGESIZE 0
SET FEEDBACK OFF
SET HEADING OFF
SET ECHO OFF
$sql_query" | grep -v '^$' | head -1 | xargs 2>/dev/null || echo "UNKNOWN"
}

# -----------------------------------------------------------------------
# Section: Header
# -----------------------------------------------------------------------
write_header() {
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S %Z')
    log_section "ZDM Source Database Discovery"
    {
        echo "========================================================================"
        echo "  ZDM Source Database Discovery Report"
        echo "  Project : ORADB"
        echo "  Host    : $(hostname)"
        echo "  User    : $(whoami)"
        echo "  Started : $ts"
        echo "  Script  : $0"
        echo "========================================================================"
        echo ""
    } >> "$REPORT_FILE"
}

# -----------------------------------------------------------------------
# Section: OS Information
# -----------------------------------------------------------------------
collect_os_info() {
    log_section "OS Information"
    log_raw ""
    log_raw "### OS INFORMATION ###"
    log_raw "Hostname        : $(hostname -f 2>/dev/null || hostname)"
    log_raw "Short hostname  : $(hostname -s 2>/dev/null || hostname)"
    log_raw "Date/Time       : $(date '+%Y-%m-%d %H:%M:%S %Z')"
    log_raw "Current user    : $(whoami)"
    log_raw "ORACLE_USER     : $ORACLE_USER"

    # IP addresses
    log_raw ""
    log_raw "--- IP Addresses ---"
    if command -v ip &>/dev/null; then
        ip addr show 2>/dev/null | grep 'inet ' | awk '{print "  " $2}' >> "$REPORT_FILE" || true
    else
        ifconfig 2>/dev/null | grep 'inet ' | awk '{print "  " $2}' >> "$REPORT_FILE" || true
    fi

    # OS version
    log_raw ""
    log_raw "--- OS Version ---"
    if [ -f /etc/os-release ]; then
        cat /etc/os-release >> "$REPORT_FILE" 2>/dev/null || true
    elif [ -f /etc/redhat-release ]; then
        cat /etc/redhat-release >> "$REPORT_FILE" 2>/dev/null || true
    else
        uname -a >> "$REPORT_FILE" 2>/dev/null || true
    fi

    # Kernel
    log_raw ""
    log_raw "Kernel: $(uname -r 2>/dev/null || echo UNKNOWN)"

    # Disk space
    log_raw ""
    log_raw "--- Disk Space ---"
    df -h 2>/dev/null >> "$REPORT_FILE" || true

    log_info "OS information collected"
}

# -----------------------------------------------------------------------
# Section: Oracle Environment
# -----------------------------------------------------------------------
collect_oracle_env() {
    log_section "Oracle Environment"
    log_raw ""
    log_raw "### ORACLE ENVIRONMENT ###"

    detect_oracle_env

    log_raw "ORACLE_HOME     : ${ORACLE_HOME:-NOT DETECTED}"
    log_raw "ORACLE_SID      : ${ORACLE_SID:-NOT DETECTED}"
    log_raw "ORACLE_BASE     : ${ORACLE_BASE:-NOT DETECTED}"

    if [ -n "${ORACLE_HOME:-}" ]; then
        local ver
        ver=$("${ORACLE_HOME}/bin/sqlplus" -V 2>/dev/null | head -1 || echo "UNKNOWN")
        log_raw "Oracle version  : $ver"

        log_raw ""
        log_raw "--- /etc/oratab ---"
        cat /etc/oratab 2>/dev/null >> "$REPORT_FILE" || log_raw "(not found)"

        log_raw ""
        log_raw "--- Oracle Processes ---"
        ps -ef 2>/dev/null | grep -E 'ora_|asm_' | grep -v grep >> "$REPORT_FILE" || true
    else
        log_warn "ORACLE_HOME not detected - Oracle may not be installed or running"
        log_raw "WARNING: ORACLE_HOME not detected"
    fi

    log_info "Oracle environment collected"
}

# -----------------------------------------------------------------------
# Section: Database Configuration
# -----------------------------------------------------------------------
collect_db_config() {
    log_section "Database Configuration"
    log_raw ""
    log_raw "### DATABASE CONFIGURATION ###"

    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        log_warn "Skipping DB config - Oracle env not set"
        log_raw "SKIPPED: Oracle environment not available"
        return
    fi

    log_raw ""
    log_raw "--- Core Database Parameters ---"
    run_sql "
SELECT 'DB_NAME        : ' || NAME FROM V\$DATABASE;
SELECT 'DB_UNIQUE_NAME : ' || DB_UNIQUE_NAME FROM V\$DATABASE;
SELECT 'DBID           : ' || DBID FROM V\$DATABASE;
SELECT 'DB_ROLE        : ' || DATABASE_ROLE FROM V\$DATABASE;
SELECT 'OPEN_MODE      : ' || OPEN_MODE FROM V\$DATABASE;
SELECT 'LOG_MODE       : ' || LOG_MODE FROM V\$DATABASE;
SELECT 'FORCE_LOGGING  : ' || FORCE_LOGGING FROM V\$DATABASE;
SELECT 'CREATED        : ' || TO_CHAR(CREATED,'YYYY-MM-DD HH24:MI:SS') FROM V\$DATABASE;
SELECT 'PLATFORM       : ' || PLATFORM_NAME FROM V\$DATABASE;
" >> "$REPORT_FILE" 2>&1 || log_raw "ERROR: Could not query V\$DATABASE"

    log_raw ""
    log_raw "--- Character Sets ---"
    run_sql "
SELECT 'DB_CHARSET     : ' || VALUE FROM NLS_DATABASE_PARAMETERS WHERE PARAMETER='NLS_CHARACTERSET';
SELECT 'NCHAR_CHARSET  : ' || VALUE FROM NLS_DATABASE_PARAMETERS WHERE PARAMETER='NLS_NCHAR_CHARACTERSET';
" >> "$REPORT_FILE" 2>&1 || log_raw "ERROR: Could not query NLS_DATABASE_PARAMETERS"

    log_raw ""
    log_raw "--- Database Size ---"
    run_sql "
SELECT 'Data files size  (GB): ' || ROUND(SUM(BYTES)/1024/1024/1024,2) FROM DBA_DATA_FILES;
SELECT 'Temp files size  (GB): ' || ROUND(SUM(BYTES)/1024/1024/1024,2) FROM DBA_TEMP_FILES;
SELECT 'Online redo size (MB): ' || ROUND(SUM(BYTES)/1024/1024,2) FROM V\$LOG;
" >> "$REPORT_FILE" 2>&1 || log_raw "ERROR: Could not query database size"

    log_raw ""
    log_raw "--- Instance Information ---"
    run_sql "
SELECT 'INSTANCE_NAME  : ' || INSTANCE_NAME FROM V\$INSTANCE;
SELECT 'HOST_NAME      : ' || HOST_NAME FROM V\$INSTANCE;
SELECT 'VERSION        : ' || VERSION FROM V\$INSTANCE;
SELECT 'STATUS         : ' || STATUS FROM V\$INSTANCE;
SELECT 'STARTUP_TIME   : ' || TO_CHAR(STARTUP_TIME,'YYYY-MM-DD HH24:MI:SS') FROM V\$INSTANCE;
" >> "$REPORT_FILE" 2>&1 || log_raw "ERROR: Could not query V\$INSTANCE"

    log_info "Database configuration collected"
}

# -----------------------------------------------------------------------
# Section: Container Database (CDB/PDB)
# -----------------------------------------------------------------------
collect_cdb_info() {
    log_section "Container Database"
    log_raw ""
    log_raw "### CONTAINER DATABASE (CDB/PDB) ###"

    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        log_raw "SKIPPED: Oracle environment not available"; return
    fi

    run_sql "SELECT 'CDB: ' || CDB || '  CON_ID: ' || CON_ID FROM V\$DATABASE;" >> "$REPORT_FILE" 2>&1 || true

    log_raw ""
    log_raw "--- PDB List ---"
    run_sql "
SELECT CON_ID, NAME, OPEN_MODE, RESTRICTED, GUID
FROM V\$PDBS
ORDER BY CON_ID;
" >> "$REPORT_FILE" 2>&1 || log_raw "(not a CDB or V\$PDBS not accessible)"

    log_info "CDB/PDB information collected"
}

# -----------------------------------------------------------------------
# Section: TDE Configuration
# -----------------------------------------------------------------------
collect_tde_info() {
    log_section "TDE Configuration"
    log_raw ""
    log_raw "### TDE CONFIGURATION ###"

    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        log_raw "SKIPPED: Oracle environment not available"; return
    fi

    log_raw ""
    log_raw "--- Wallet Status ---"
    run_sql "
SELECT WRL_TYPE, WRL_PARAMETER, STATUS, WALLET_TYPE, CON_ID
FROM V\$ENCRYPTION_WALLET
ORDER BY CON_ID;
" >> "$REPORT_FILE" 2>&1 || log_raw "(V\$ENCRYPTION_WALLET not accessible)"

    log_raw ""
    log_raw "--- Encrypted Tablespaces ---"
    run_sql "
SELECT TABLESPACE_NAME, ENCRYPTED
FROM DBA_TABLESPACES
WHERE ENCRYPTED = 'YES'
ORDER BY TABLESPACE_NAME;
" >> "$REPORT_FILE" 2>&1 || log_raw "(no encrypted tablespaces found)"

    log_raw ""
    log_raw "--- Encryption Keys ---"
    run_sql "
SELECT COUNT(*) AS ENCRYPTED_OBJECTS FROM V\$ENCRYPTED_TABLESPACES;
" >> "$REPORT_FILE" 2>&1 || true

    log_raw ""
    log_raw "--- Wallet Location (sqlnet.ora) ---"
    if [ -n "${ORACLE_HOME:-}" ]; then
        local sqlnet="${ORACLE_HOME}/network/admin/sqlnet.ora"
        if [ -f "$sqlnet" ]; then
            grep -i 'wallet\|ENCRYPTION_WALLET' "$sqlnet" >> "$REPORT_FILE" 2>/dev/null || log_raw "(no wallet entry in sqlnet.ora)"
        fi
    fi

    log_info "TDE configuration collected"
}

# -----------------------------------------------------------------------
# Section: Supplemental Logging
# -----------------------------------------------------------------------
collect_supplemental_logging() {
    log_section "Supplemental Logging"
    log_raw ""
    log_raw "### SUPPLEMENTAL LOGGING ###"

    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        log_raw "SKIPPED: Oracle environment not available"; return
    fi

    run_sql "
SELECT LOG_MODE, SUPPLEMENTAL_LOG_DATA_MIN, SUPPLEMENTAL_LOG_DATA_PK,
       SUPPLEMENTAL_LOG_DATA_UI, SUPPLEMENTAL_LOG_DATA_FK, SUPPLEMENTAL_LOG_DATA_ALL
FROM V\$DATABASE;
" >> "$REPORT_FILE" 2>&1 || log_raw "ERROR: Could not query supplemental logging"

    log_raw ""
    log_raw "--- Supplemental Log Groups ---"
    run_sql "
SELECT LOG_GROUP_NAME, TABLE_NAME, LOG_GROUP_TYPE
FROM DBA_LOG_GROUP_COLUMNS
ORDER BY TABLE_NAME, LOG_GROUP_NAME;
" >> "$REPORT_FILE" 2>&1 || true

    log_info "Supplemental logging collected"
}

# -----------------------------------------------------------------------
# Section: Redo / Archive Configuration
# -----------------------------------------------------------------------
collect_redo_archive() {
    log_section "Redo / Archive Configuration"
    log_raw ""
    log_raw "### REDO / ARCHIVE CONFIGURATION ###"

    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        log_raw "SKIPPED: Oracle environment not available"; return
    fi

    log_raw ""
    log_raw "--- Redo Log Groups ---"
    run_sql "
SELECT l.GROUP#, l.MEMBERS, l.STATUS, l.ARCHIVED,
       ROUND(l.BYTES/1024/1024) AS SIZE_MB, lf.MEMBER
FROM V\$LOG l JOIN V\$LOGFILE lf ON l.GROUP# = lf.GROUP#
ORDER BY l.GROUP#;
" >> "$REPORT_FILE" 2>&1 || log_raw "ERROR: Could not query redo logs"

    log_raw ""
    log_raw "--- Archive Log Destinations ---"
    run_sql "
SELECT DEST_ID, STATUS, TARGET, ARCHIVER, SCHEDULE, DESTINATION, VALID_TYPE, DB_UNIQUE_NAME
FROM V\$ARCHIVE_DEST
WHERE STATUS != 'INACTIVE'
ORDER BY DEST_ID;
" >> "$REPORT_FILE" 2>&1 || log_raw "ERROR: Could not query archive destinations"

    log_raw ""
    log_raw "--- Archive Log Mode ---"
    run_sql "SELECT LOG_MODE FROM V\$DATABASE;" >> "$REPORT_FILE" 2>&1 || true

    log_raw ""
    log_raw "--- Recent Archive Logs ---"
    run_sql "
SELECT NAME, SEQUENCE#, TO_CHAR(FIRST_TIME,'YYYY-MM-DD HH24:MI:SS') AS FIRST_TIME,
       TO_CHAR(COMPLETION_TIME,'YYYY-MM-DD HH24:MI:SS') AS COMPLETION_TIME,
       ROUND(BLOCKS*BLOCK_SIZE/1024/1024,1) AS SIZE_MB
FROM V\$ARCHIVED_LOG
WHERE COMPLETION_TIME > SYSDATE - 1
ORDER BY SEQUENCE# DESC FETCH FIRST 10 ROWS ONLY;
" >> "$REPORT_FILE" 2>&1 || true

    log_info "Redo/archive configuration collected"
}

# -----------------------------------------------------------------------
# Section: Network Configuration
# -----------------------------------------------------------------------
collect_network_config() {
    log_section "Network Configuration"
    log_raw ""
    log_raw "### NETWORK CONFIGURATION ###"

    if [ -n "${ORACLE_HOME:-}" ]; then
        log_raw ""
        log_raw "--- Listener Status ---"
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            "${ORACLE_HOME}/bin/lsnrctl" status 2>&1 >> "$REPORT_FILE" || log_raw "(lsnrctl failed)"
        else
            sudo -u "$ORACLE_USER" -E ORACLE_HOME="$ORACLE_HOME" "${ORACLE_HOME}/bin/lsnrctl" status 2>&1 >> "$REPORT_FILE" || log_raw "(lsnrctl failed)"
        fi

        log_raw ""
        log_raw "--- tnsnames.ora ---"
        local tns="${ORACLE_HOME}/network/admin/tnsnames.ora"
        if [ -f "$tns" ]; then
            cat "$tns" >> "$REPORT_FILE" 2>/dev/null || true
        else
            log_raw "(not found at $tns)"
        fi

        log_raw ""
        log_raw "--- sqlnet.ora ---"
        local sqlnet="${ORACLE_HOME}/network/admin/sqlnet.ora"
        if [ -f "$sqlnet" ]; then
            cat "$sqlnet" >> "$REPORT_FILE" 2>/dev/null || true
        else
            log_raw "(not found at $sqlnet)"
        fi

        log_raw ""
        log_raw "--- listener.ora ---"
        local lsnr="${ORACLE_HOME}/network/admin/listener.ora"
        if [ -f "$lsnr" ]; then
            cat "$lsnr" >> "$REPORT_FILE" 2>/dev/null || true
        else
            log_raw "(not found at $lsnr)"
        fi
    fi

    log_info "Network configuration collected"
}

# -----------------------------------------------------------------------
# Section: Authentication / Password File
# -----------------------------------------------------------------------
collect_auth_info() {
    log_section "Authentication"
    log_raw ""
    log_raw "### AUTHENTICATION ###"

    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        log_raw ""
        log_raw "--- Password File Location ---"
        local pwfile
        for p in "${ORACLE_HOME}/dbs/orapw${ORACLE_SID}" "${ORACLE_HOME}/dbs/orapwd${ORACLE_SID}" \
                  "${ORACLE_BASE}/dbs/orapw${ORACLE_SID}"; do
            if [ -f "$p" ]; then
                log_raw "Password file: $p"
                break
            fi
        done

        log_raw ""
        log_raw "--- Database Authentication Mode ---"
        run_sql "
SELECT NAME, VALUE FROM V\$PARAMETER WHERE NAME IN ('remote_login_passwordfile','os_authent_prefix')
ORDER BY NAME;
" >> "$REPORT_FILE" 2>&1 || true
    fi

    log_raw ""
    log_raw "--- SSH Directory (oracle user) ---"
    if [ "$(whoami)" = "$ORACLE_USER" ]; then
        ls -la ~/.ssh/ 2>/dev/null >> "$REPORT_FILE" || log_raw "(~/.ssh not found for oracle)"
    else
        sudo -u "$ORACLE_USER" bash -c 'ls -la ~/.ssh/ 2>/dev/null' >> "$REPORT_FILE" 2>&1 || log_raw "(~/.ssh not found or not accessible for oracle)"
    fi

    log_info "Authentication information collected"
}

# -----------------------------------------------------------------------
# Section: Data Guard
# -----------------------------------------------------------------------
collect_dataguard_info() {
    log_section "Data Guard Configuration"
    log_raw ""
    log_raw "### DATA GUARD CONFIGURATION ###"

    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        log_raw "SKIPPED: Oracle environment not available"; return
    fi

    log_raw ""
    log_raw "--- DG Parameters ---"
    run_sql "
SELECT NAME, VALUE FROM V\$PARAMETER
WHERE NAME IN ('db_unique_name','log_archive_config','log_archive_dest_1','log_archive_dest_2',
               'fal_server','fal_client','standby_file_management','dg_broker_start',
               'dg_broker_config_file1','dg_broker_config_file2')
ORDER BY NAME;
" >> "$REPORT_FILE" 2>&1 || log_raw "ERROR: Could not query DG parameters"

    log_raw ""
    log_raw "--- Protection Mode ---"
    run_sql "SELECT PROTECTION_MODE, PROTECTION_LEVEL, DATABASE_ROLE FROM V\$DATABASE;" >> "$REPORT_FILE" 2>&1 || true

    log_info "Data Guard configuration collected"
}

# -----------------------------------------------------------------------
# Section: Schema Information
# -----------------------------------------------------------------------
collect_schema_info() {
    log_section "Schema Information"
    log_raw ""
    log_raw "### SCHEMA INFORMATION ###"

    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        log_raw "SKIPPED: Oracle environment not available"; return
    fi

    log_raw ""
    log_raw "--- Non-system Schemas > 100MB ---"
    run_sql "
SELECT s.OWNER, ROUND(SUM(s.BYTES)/1024/1024/1024,3) AS SIZE_GB
FROM DBA_SEGMENTS s
WHERE s.OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','DBSFWUSER',
                       'GGSYS','XDB','WMSYS','OJVMSYS','ORDSYS','ORDDATA',
                       'MDSYS','CTXSYS','OLAPSYS','LBACSYS','DVSYS','AUDSYS',
                       'GSMADMIN_INTERNAL','GSMUSER','XS\$NULL','REMOTE_SCHEDULER_AGENT',
                       'DIP','MDDATA','ORACLE_OCM','SPATIAL_CSW_ADMIN_USR',
                       'SPATIAL_WFS_ADMIN_USR','SYSBACKUP','SYSDG','SYSKM','SYSRAC',
                       'SI_INFORMTN_SCHEMA','FLOWS_FILES','APEX_040200','APEX_030200')
GROUP BY s.OWNER
HAVING SUM(s.BYTES)/1024/1024 > 100
ORDER BY SIZE_GB DESC;
" >> "$REPORT_FILE" 2>&1 || log_raw "ERROR: Could not query schema sizes"

    log_raw ""
    log_raw "--- Invalid Objects by Owner/Type ---"
    run_sql "
SELECT OWNER, OBJECT_TYPE, COUNT(*) AS INVALID_COUNT
FROM DBA_OBJECTS
WHERE STATUS = 'INVALID'
GROUP BY OWNER, OBJECT_TYPE
ORDER BY OWNER, OBJECT_TYPE;
" >> "$REPORT_FILE" 2>&1 || true

    log_info "Schema information collected"
}

# -----------------------------------------------------------------------
# Section: Tablespace Configuration
# -----------------------------------------------------------------------
collect_tablespace_info() {
    log_section "Tablespace Configuration"
    log_raw ""
    log_raw "### TABLESPACE CONFIGURATION ###"

    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        log_raw "SKIPPED: Oracle environment not available"; return
    fi

    log_raw ""
    log_raw "--- Tablespace Sizes and Autoextend ---"
    run_sql "
SELECT t.TABLESPACE_NAME,
       ROUND(NVL(SUM(d.BYTES),0)/1024/1024/1024,2) AS CURRENT_SIZE_GB,
       ROUND(NVL(SUM(d.MAXBYTES),0)/1024/1024/1024,2) AS MAX_SIZE_GB,
       MAX(d.AUTOEXTENSIBLE) AS AUTOEXTEND,
       t.STATUS, t.CONTENTS
FROM DBA_TABLESPACES t
LEFT JOIN DBA_DATA_FILES d ON t.TABLESPACE_NAME = d.TABLESPACE_NAME
GROUP BY t.TABLESPACE_NAME, t.STATUS, t.CONTENTS
UNION ALL
SELECT t.TABLESPACE_NAME,
       ROUND(NVL(SUM(d.BYTES),0)/1024/1024/1024,2),
       ROUND(NVL(SUM(d.MAXBYTES),0)/1024/1024/1024,2),
       MAX(d.AUTOEXTENSIBLE),
       t.STATUS, t.CONTENTS
FROM DBA_TABLESPACES t
LEFT JOIN DBA_TEMP_FILES d ON t.TABLESPACE_NAME = d.TABLESPACE_NAME
WHERE t.CONTENTS = 'TEMPORARY'
GROUP BY t.TABLESPACE_NAME, t.STATUS, t.CONTENTS
ORDER BY 1;
" >> "$REPORT_FILE" 2>&1 || log_raw "ERROR: Could not query tablespace info"

    log_raw ""
    log_raw "--- Data File Autoextend Detail ---"
    run_sql "
SELECT FILE_ID, TABLESPACE_NAME, FILE_NAME,
       ROUND(BYTES/1024/1024,0) AS CURRENT_MB,
       AUTOEXTENSIBLE,
       ROUND(MAXBYTES/1024/1024,0) AS MAX_MB,
       ROUND(INCREMENT_BY*8192/1024/1024,0) AS INCREMENT_MB
FROM DBA_DATA_FILES
ORDER BY TABLESPACE_NAME, FILE_ID;
" >> "$REPORT_FILE" 2>&1 || true

    log_info "Tablespace configuration collected"
}

# -----------------------------------------------------------------------
# Section: Backup Configuration
# -----------------------------------------------------------------------
collect_backup_config() {
    log_section "Backup Configuration"
    log_raw ""
    log_raw "### BACKUP CONFIGURATION ###"

    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        log_raw "SKIPPED: Oracle environment not available"; return
    fi

    log_raw ""
    log_raw "--- RMAN Configuration ---"
    run_sql "
SELECT NAME, VALUE FROM V\$RMAN_CONFIGURATION ORDER BY CONF#;
" >> "$REPORT_FILE" 2>&1 || log_raw "(could not query RMAN configuration)"

    log_raw ""
    log_raw "--- Last Successful Backup ---"
    run_sql "
SELECT TO_CHAR(MAX(COMPLETION_TIME),'YYYY-MM-DD HH24:MI:SS') AS LAST_BACKUP
FROM V\$BACKUP_SET WHERE STATUS='A';
" >> "$REPORT_FILE" 2>&1 || true

    log_raw ""
    log_raw "--- RMAN Backup Summary (last 7 days) ---"
    run_sql "
SELECT INPUT_TYPE, STATUS, TO_CHAR(START_TIME,'YYYY-MM-DD HH24:MI:SS') AS START_TIME,
       TO_CHAR(END_TIME,'YYYY-MM-DD HH24:MI:SS') AS END_TIME,
       ROUND(INPUT_BYTES/1024/1024/1024,2) AS INPUT_GB,
       ROUND(OUTPUT_BYTES/1024/1024/1024,2) AS OUTPUT_GB
FROM V\$RMAN_BACKUP_JOB_DETAILS
WHERE START_TIME > SYSDATE - 7
ORDER BY START_TIME DESC FETCH FIRST 20 ROWS ONLY;
" >> "$REPORT_FILE" 2>&1 || true

    log_raw ""
    log_raw "--- Crontab (oracle user) ---"
    if [ "$(whoami)" = "$ORACLE_USER" ]; then
        crontab -l 2>/dev/null >> "$REPORT_FILE" || log_raw "(no crontab for oracle)"
    else
        sudo -u "$ORACLE_USER" crontab -l 2>/dev/null >> "$REPORT_FILE" || log_raw "(no crontab for oracle or not accessible)"
    fi

    log_raw ""
    log_raw "--- DBMS_SCHEDULER Backup Jobs ---"
    run_sql "
SELECT OWNER, JOB_NAME, JOB_TYPE, STATE, ENABLED,
       TO_CHAR(LAST_START_DATE,'YYYY-MM-DD HH24:MI:SS') AS LAST_RUN,
       TO_CHAR(NEXT_RUN_DATE,'YYYY-MM-DD HH24:MI:SS') AS NEXT_RUN
FROM DBA_SCHEDULER_JOBS
WHERE UPPER(JOB_NAME) LIKE '%BACKUP%' OR UPPER(JOB_NAME) LIKE '%RMAN%'
ORDER BY OWNER, JOB_NAME;
" >> "$REPORT_FILE" 2>&1 || true

    log_info "Backup configuration collected"
}

# -----------------------------------------------------------------------
# Section: Database Links
# -----------------------------------------------------------------------
collect_db_links() {
    log_section "Database Links"
    log_raw ""
    log_raw "### DATABASE LINKS ###"

    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        log_raw "SKIPPED: Oracle environment not available"; return
    fi

    run_sql "
SELECT OWNER, DB_LINK, USERNAME, HOST, TO_CHAR(CREATED,'YYYY-MM-DD') AS CREATED
FROM DBA_DB_LINKS
ORDER BY OWNER, DB_LINK;
" >> "$REPORT_FILE" 2>&1 || log_raw "(no database links found)"

    log_info "Database links collected"
}

# -----------------------------------------------------------------------
# Section: Materialized Views
# -----------------------------------------------------------------------
collect_mviews() {
    log_section "Materialized Views"
    log_raw ""
    log_raw "### MATERIALIZED VIEWS ###"

    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        log_raw "SKIPPED: Oracle environment not available"; return
    fi

    run_sql "
SELECT OWNER, MVIEW_NAME, REFRESH_METHOD, REFRESH_MODE,
       TO_CHAR(LAST_REFRESH_DATE,'YYYY-MM-DD HH24:MI:SS') AS LAST_REFRESH,
       TO_CHAR(NEXT,'YYYY-MM-DD HH24:MI:SS') AS NEXT_REFRESH,
       STALENESS
FROM DBA_MVIEWS
ORDER BY OWNER, MVIEW_NAME;
" >> "$REPORT_FILE" 2>&1 || log_raw "(no materialized views found)"

    log_raw ""
    log_raw "--- Materialized View Logs ---"
    run_sql "
SELECT LOG_OWNER, MASTER, LOG_TABLE, LOG_TRIGGER, ROWIDS, PRIMARY_KEY, OBJECT_ID,
       FILTER_COLUMNS, SEQUENCE, INCLUDE_NEW_VALUES
FROM DBA_MVIEW_LOGS
ORDER BY LOG_OWNER, MASTER;
" >> "$REPORT_FILE" 2>&1 || true

    log_info "Materialized views collected"
}

# -----------------------------------------------------------------------
# Section: Scheduler Jobs
# -----------------------------------------------------------------------
collect_scheduler_jobs() {
    log_section "Scheduler Jobs"
    log_raw ""
    log_raw "### SCHEDULER JOBS ###"

    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        log_raw "SKIPPED: Oracle environment not available"; return
    fi

    run_sql "
SELECT OWNER, JOB_NAME, JOB_TYPE, JOB_CLASS, ENABLED, STATE,
       TO_CHAR(LAST_START_DATE,'YYYY-MM-DD HH24:MI:SS') AS LAST_RUN,
       TO_CHAR(NEXT_RUN_DATE,'YYYY-MM-DD HH24:MI:SS') AS NEXT_RUN
FROM DBA_SCHEDULER_JOBS
WHERE OWNER NOT IN ('SYS','SYSTEM','EXFSYS','ORACLE_OCM','XDB','WMSYS')
ORDER BY OWNER, JOB_NAME;
" >> "$REPORT_FILE" 2>&1 || log_raw "(no user scheduler jobs found)"

    log_raw ""
    log_raw "--- Jobs with External References ---"
    run_sql "
SELECT OWNER, JOB_NAME, JOB_ACTION
FROM DBA_SCHEDULER_JOBS
WHERE (UPPER(JOB_ACTION) LIKE '%HOST%' OR UPPER(JOB_ACTION) LIKE '%DBLINK%'
       OR UPPER(JOB_ACTION) LIKE '%UTL_FILE%' OR UPPER(JOB_ACTION) LIKE '%CREDENTIAL%')
AND OWNER NOT IN ('SYS','SYSTEM')
ORDER BY OWNER, JOB_NAME;
" >> "$REPORT_FILE" 2>&1 || true

    log_info "Scheduler jobs collected"
}

# -----------------------------------------------------------------------
# Section: JSON Summary
# -----------------------------------------------------------------------
write_json_summary() {
    log_section "Writing JSON Summary"
    local db_name db_version log_mode cdb_status tde_status
    local hostname_f
    hostname_f=$(hostname -f 2>/dev/null || hostname)

    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        db_name=$(run_sql_value "SELECT NAME FROM V\$DATABASE;")
        db_version=$(run_sql_value "SELECT VERSION FROM V\$INSTANCE;")
        log_mode=$(run_sql_value "SELECT LOG_MODE FROM V\$DATABASE;")
        cdb_status=$(run_sql_value "SELECT CDB FROM V\$DATABASE;")
        tde_status=$(run_sql_value "SELECT STATUS FROM V\$ENCRYPTION_WALLET WHERE ROWNUM=1;" 2>/dev/null || echo "UNKNOWN")
    else
        db_name="UNKNOWN"; db_version="UNKNOWN"; log_mode="UNKNOWN"
        cdb_status="UNKNOWN"; tde_status="UNKNOWN"
    fi

    cat > "$JSON_FILE" <<ENDJSON
{
  "discovery_type": "source",
  "project": "ORADB",
  "hostname": "${hostname_f}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "oracle": {
    "sid": "${ORACLE_SID:-UNKNOWN}",
    "home": "${ORACLE_HOME:-UNKNOWN}",
    "base": "${ORACLE_BASE:-UNKNOWN}",
    "version": "${db_version}",
    "db_name": "${db_name}",
    "log_mode": "${log_mode}",
    "cdb": "${cdb_status}",
    "tde_status": "${tde_status}"
  },
  "report_file": "$(basename "$REPORT_FILE")"
}
ENDJSON

    log_info "JSON summary written to $JSON_FILE"
}

# -----------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------
main() {
    # Initialise report file
    > "$REPORT_FILE"

    write_header

    collect_os_info
    collect_oracle_env
    collect_db_config
    collect_cdb_info
    collect_tde_info
    collect_supplemental_logging
    collect_redo_archive
    collect_network_config
    collect_auth_info
    collect_dataguard_info
    collect_schema_info
    collect_tablespace_info
    collect_backup_config
    collect_db_links
    collect_mviews
    collect_scheduler_jobs

    log_raw ""
    log_raw "========================================================================"
    log_raw "  Discovery completed: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    log_raw "========================================================================"

    write_json_summary

    log_section "Discovery Complete"
    log_info "Text report : $REPORT_FILE"
    log_info "JSON summary: $JSON_FILE"
    log_info "Orchestration script will collect these files."
}

main "$@"
