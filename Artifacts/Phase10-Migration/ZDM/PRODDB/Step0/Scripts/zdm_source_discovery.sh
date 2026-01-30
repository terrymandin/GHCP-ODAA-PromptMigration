#!/bin/bash
#===============================================================================
# ZDM Source Database Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# Source: proddb01.corp.example.com
#
# Purpose: Gather comprehensive information from the source Oracle database
#          server to support ZDM migration planning.
#
# Execution: Run as ADMIN_USER (oracle) via SSH. SQL commands execute as ORACLE_USER.
#
# Output:
#   - Text report: ./zdm_source_discovery_<hostname>_<timestamp>.txt
#   - JSON summary: ./zdm_source_discovery_<hostname>_<timestamp>.json
#===============================================================================

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script variables
SCRIPT_NAME="zdm_source_discovery.sh"
HOSTNAME=$(hostname -s 2>/dev/null || hostname)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="./zdm_source_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_source_discovery_${HOSTNAME}_${TIMESTAMP}.json"

# User configuration - can be overridden via environment
ORACLE_USER="${ORACLE_USER:-oracle}"

# Error tracking
declare -a FAILED_SECTIONS=()
declare -a SUCCESS_SECTIONS=()

#===============================================================================
# FUNCTIONS
#===============================================================================

print_header() {
    local title="$1"
    echo -e "\n${BLUE}=================================================================================${NC}"
    echo -e "${CYAN}  $title${NC}"
    echo -e "${BLUE}=================================================================================${NC}"
}

print_section() {
    local title="$1"
    echo -e "\n${GREEN}--- $title ---${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

log_section_result() {
    local section="$1"
    local status="$2"
    if [ "$status" = "success" ]; then
        SUCCESS_SECTIONS+=("$section")
    else
        FAILED_SECTIONS+=("$section")
    fi
}

# Auto-detect Oracle environment
detect_oracle_env() {
    # If already set, use existing values
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        print_success "Using pre-configured ORACLE_HOME=$ORACLE_HOME, ORACLE_SID=$ORACLE_SID"
        return 0
    fi
    
    print_section "Auto-detecting Oracle Environment"
    
    # Method 1: Parse /etc/oratab (most reliable)
    if [ -f /etc/oratab ]; then
        local oratab_entry
        if [ -n "${ORACLE_SID:-}" ]; then
            oratab_entry=$(grep "^${ORACLE_SID}:" /etc/oratab 2>/dev/null | head -1)
        else
            oratab_entry=$(grep -v '^#' /etc/oratab | grep -v '^$' | grep ':Y$\|:N$' | head -1)
        fi
        if [ -n "$oratab_entry" ]; then
            export ORACLE_SID="${ORACLE_SID:-$(echo "$oratab_entry" | cut -d: -f1)}"
            export ORACLE_HOME="${ORACLE_HOME:-$(echo "$oratab_entry" | cut -d: -f2)}"
            print_success "Detected from /etc/oratab: ORACLE_SID=$ORACLE_SID, ORACLE_HOME=$ORACLE_HOME"
        fi
    fi
    
    # Method 2: Check running pmon process
    if [ -z "${ORACLE_SID:-}" ]; then
        local pmon_sid
        pmon_sid=$(ps -ef | grep 'ora_pmon_' | grep -v grep | head -1 | sed 's/.*ora_pmon_//')
        if [ -n "$pmon_sid" ]; then
            export ORACLE_SID="$pmon_sid"
            print_success "Detected ORACLE_SID from pmon process: $ORACLE_SID"
        fi
    fi
    
    # Method 3: Search common Oracle installation paths
    if [ -z "${ORACLE_HOME:-}" ]; then
        for path in /u01/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1 /oracle/product/*/dbhome_1; do
            if [ -d "$path" ] && [ -f "$path/bin/sqlplus" ]; then
                export ORACLE_HOME="$path"
                print_success "Detected ORACLE_HOME from common path: $ORACLE_HOME"
                break
            fi
        done
    fi
    
    # Method 4: Try oraenv if we have ORACLE_SID
    if [ -z "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        if [ -f /usr/local/bin/oraenv ]; then
            ORAENV_ASK=NO . /usr/local/bin/oraenv <<< "$ORACLE_SID" 2>/dev/null
            [ -n "${ORACLE_HOME:-}" ] && print_success "Detected ORACLE_HOME via oraenv: $ORACLE_HOME"
        fi
    fi
    
    # Apply explicit overrides if provided (highest priority)
    [ -n "${ORACLE_HOME_OVERRIDE:-}" ] && export ORACLE_HOME="$ORACLE_HOME_OVERRIDE"
    [ -n "${ORACLE_SID_OVERRIDE:-}" ] && export ORACLE_SID="$ORACLE_SID_OVERRIDE"
    
    # Set ORACLE_BASE
    if [ -n "${ORACLE_HOME:-}" ]; then
        export ORACLE_BASE="${ORACLE_BASE:-$(dirname $(dirname $ORACLE_HOME))}"
    fi
    
    # Validate
    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        print_error "Failed to detect Oracle environment"
        return 1
    fi
    
    return 0
}

# Execute SQL as oracle user
run_sql() {
    local sql_query="$1"
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        local sqlplus_cmd="$ORACLE_HOME/bin/sqlplus -s / as sysdba"
        local sql_script=$(cat <<EOSQL
SET PAGESIZE 1000
SET LINESIZE 200
SET FEEDBACK OFF
SET HEADING ON
SET ECHO OFF
SET TRIMSPOOL ON
$sql_query
EOSQL
)
        # Execute as oracle user - use sudo if current user is not oracle
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            echo "$sql_script" | ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd 2>/dev/null
        else
            echo "$sql_script" | sudo -u "$ORACLE_USER" ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd 2>/dev/null
        fi
    else
        echo "ERROR: ORACLE_HOME or ORACLE_SID not set"
        return 1
    fi
}

# Execute SQL and return single value
run_sql_value() {
    local sql_query="$1"
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        local sqlplus_cmd="$ORACLE_HOME/bin/sqlplus -s / as sysdba"
        local sql_script=$(cat <<EOSQL
SET PAGESIZE 0
SET LINESIZE 200
SET FEEDBACK OFF
SET HEADING OFF
SET ECHO OFF
SET TRIMSPOOL ON
$sql_query
EOSQL
)
        # Execute as oracle user
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            echo "$sql_script" | ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd 2>/dev/null | head -1 | xargs
        else
            echo "$sql_script" | sudo -u "$ORACLE_USER" ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd 2>/dev/null | head -1 | xargs
        fi
    else
        echo "ERROR: ORACLE_HOME or ORACLE_SID not set"
        return 1
    fi
}

#===============================================================================
# DISCOVERY SECTIONS
#===============================================================================

discover_os_info() {
    print_section "OS Information"
    {
        echo "=== OS INFORMATION ==="
        echo "Hostname: $(hostname -f 2>/dev/null || hostname)"
        echo "Short Hostname: $(hostname -s 2>/dev/null || hostname)"
        echo "IP Addresses:"
        ip addr show 2>/dev/null | grep 'inet ' | awk '{print "  " $2}' || ifconfig 2>/dev/null | grep 'inet ' | awk '{print "  " $2}'
        echo ""
        echo "Operating System:"
        cat /etc/os-release 2>/dev/null || cat /etc/redhat-release 2>/dev/null || uname -a
        echo ""
        echo "Kernel Version: $(uname -r)"
        echo "Architecture: $(uname -m)"
        echo ""
        echo "=== DISK SPACE ==="
        df -h
        echo ""
        echo "=== MEMORY ==="
        free -h 2>/dev/null || free -m
        echo ""
        log_section_result "OS Information" "success"
    } 2>&1 || log_section_result "OS Information" "failed"
}

discover_oracle_env() {
    print_section "Oracle Environment"
    {
        echo "=== ORACLE ENVIRONMENT ==="
        echo "ORACLE_HOME: ${ORACLE_HOME:-NOT SET}"
        echo "ORACLE_SID: ${ORACLE_SID:-NOT SET}"
        echo "ORACLE_BASE: ${ORACLE_BASE:-NOT SET}"
        echo ""
        echo "Oracle Version:"
        if [ -f "$ORACLE_HOME/bin/sqlplus" ]; then
            $ORACLE_HOME/bin/sqlplus -V 2>/dev/null | head -3
        fi
        echo ""
        echo "/etc/oratab contents:"
        cat /etc/oratab 2>/dev/null | grep -v '^#' | grep -v '^$' || echo "  File not found"
        echo ""
        log_section_result "Oracle Environment" "success"
    } 2>&1 || log_section_result "Oracle Environment" "failed"
}

discover_database_config() {
    print_section "Database Configuration"
    {
        echo "=== DATABASE CONFIGURATION ==="
        run_sql "
SELECT 'Database Name: ' || NAME FROM V\$DATABASE;
SELECT 'DB Unique Name: ' || DB_UNIQUE_NAME FROM V\$DATABASE;
SELECT 'DBID: ' || DBID FROM V\$DATABASE;
SELECT 'Database Role: ' || DATABASE_ROLE FROM V\$DATABASE;
SELECT 'Open Mode: ' || OPEN_MODE FROM V\$DATABASE;
SELECT 'Log Mode: ' || LOG_MODE FROM V\$DATABASE;
SELECT 'Force Logging: ' || FORCE_LOGGING FROM V\$DATABASE;
SELECT 'Flashback On: ' || FLASHBACK_ON FROM V\$DATABASE;
SELECT 'Platform Name: ' || PLATFORM_NAME FROM V\$DATABASE;
SELECT 'Created: ' || TO_CHAR(CREATED, 'YYYY-MM-DD HH24:MI:SS') FROM V\$DATABASE;
"
        echo ""
        echo "=== DATABASE SIZE ==="
        run_sql "
SELECT 'Data Files Size (GB): ' || ROUND(SUM(BYTES)/1024/1024/1024, 2) FROM DBA_DATA_FILES;
SELECT 'Temp Files Size (GB): ' || ROUND(SUM(BYTES)/1024/1024/1024, 2) FROM DBA_TEMP_FILES;
SELECT 'Total Used Space (GB): ' || ROUND(SUM(BYTES)/1024/1024/1024, 2) FROM DBA_SEGMENTS;
"
        echo ""
        echo "=== CHARACTER SET ==="
        run_sql "
SELECT 'Database Character Set: ' || VALUE FROM NLS_DATABASE_PARAMETERS WHERE PARAMETER = 'NLS_CHARACTERSET';
SELECT 'National Character Set: ' || VALUE FROM NLS_DATABASE_PARAMETERS WHERE PARAMETER = 'NLS_NCHAR_CHARACTERSET';
"
        echo ""
        log_section_result "Database Configuration" "success"
    } 2>&1 || log_section_result "Database Configuration" "failed"
}

discover_cdb_pdb() {
    print_section "Container Database / PDBs"
    {
        echo "=== CDB STATUS ==="
        local cdb_status
        cdb_status=$(run_sql_value "SELECT CDB FROM V\$DATABASE;")
        echo "CDB Enabled: $cdb_status"
        echo ""
        
        if [ "$cdb_status" = "YES" ]; then
            echo "=== PDB INFORMATION ==="
            run_sql "
COL NAME FORMAT A30
COL OPEN_MODE FORMAT A15
COL RESTRICTED FORMAT A10
COL TOTAL_SIZE_GB FORMAT 999,999.99
SELECT CON_ID, NAME, OPEN_MODE, RESTRICTED, 
       ROUND(TOTAL_SIZE/1024/1024/1024, 2) AS TOTAL_SIZE_GB
FROM V\$PDBS ORDER BY CON_ID;
"
        fi
        echo ""
        log_section_result "CDB/PDB Status" "success"
    } 2>&1 || log_section_result "CDB/PDB Status" "failed"
}

discover_tde_config() {
    print_section "TDE Configuration"
    {
        echo "=== TDE STATUS ==="
        run_sql "
COL WRL_TYPE FORMAT A10
COL WRL_PARAMETER FORMAT A60
COL STATUS FORMAT A15
COL WALLET_TYPE FORMAT A15
SELECT WRL_TYPE, WRL_PARAMETER, STATUS, WALLET_TYPE 
FROM V\$ENCRYPTION_WALLET;
"
        echo ""
        echo "=== ENCRYPTED TABLESPACES ==="
        run_sql "
COL TABLESPACE_NAME FORMAT A30
COL ENCRYPTED FORMAT A10
SELECT TABLESPACE_NAME, ENCRYPTED FROM DBA_TABLESPACES WHERE ENCRYPTED = 'YES';
"
        local enc_count
        enc_count=$(run_sql_value "SELECT COUNT(*) FROM DBA_TABLESPACES WHERE ENCRYPTED = 'YES';")
        echo "Encrypted Tablespace Count: $enc_count"
        echo ""
        
        echo "=== TDE WALLET LOCATION ==="
        run_sql "SHOW PARAMETER WALLET_ROOT;"
        run_sql "SHOW PARAMETER TDE_CONFIGURATION;"
        echo ""
        log_section_result "TDE Configuration" "success"
    } 2>&1 || log_section_result "TDE Configuration" "failed"
}

discover_supplemental_logging() {
    print_section "Supplemental Logging"
    {
        echo "=== SUPPLEMENTAL LOGGING ==="
        run_sql "
SELECT 'Minimal: ' || SUPPLEMENTAL_LOG_DATA_MIN FROM V\$DATABASE;
SELECT 'Primary Key: ' || SUPPLEMENTAL_LOG_DATA_PK FROM V\$DATABASE;
SELECT 'Unique Index: ' || SUPPLEMENTAL_LOG_DATA_UI FROM V\$DATABASE;
SELECT 'Foreign Key: ' || SUPPLEMENTAL_LOG_DATA_FK FROM V\$DATABASE;
SELECT 'All Columns: ' || SUPPLEMENTAL_LOG_DATA_ALL FROM V\$DATABASE;
"
        echo ""
        log_section_result "Supplemental Logging" "success"
    } 2>&1 || log_section_result "Supplemental Logging" "failed"
}

discover_redo_archive() {
    print_section "Redo/Archive Configuration"
    {
        echo "=== REDO LOG CONFIGURATION ==="
        run_sql "
COL GROUP# FORMAT 999
COL MEMBER FORMAT A60
COL SIZE_MB FORMAT 9999
COL STATUS FORMAT A10
SELECT L.GROUP#, LF.MEMBER, L.BYTES/1024/1024 AS SIZE_MB, L.STATUS
FROM V\$LOG L, V\$LOGFILE LF
WHERE L.GROUP# = LF.GROUP#
ORDER BY L.GROUP#, LF.MEMBER;
"
        echo ""
        echo "=== ARCHIVE LOG DESTINATIONS ==="
        run_sql "
COL DEST_NAME FORMAT A25
COL DESTINATION FORMAT A50
COL STATUS FORMAT A10
SELECT DEST_NAME, STATUS, DESTINATION 
FROM V\$ARCHIVE_DEST 
WHERE STATUS != 'INACTIVE' AND DESTINATION IS NOT NULL;
"
        echo ""
        echo "=== ARCHIVE LOG PARAMETERS ==="
        run_sql "SHOW PARAMETER LOG_ARCHIVE_DEST;"
        run_sql "SHOW PARAMETER LOG_ARCHIVE_FORMAT;"
        echo ""
        log_section_result "Redo/Archive Configuration" "success"
    } 2>&1 || log_section_result "Redo/Archive Configuration" "failed"
}

discover_network_config() {
    print_section "Network Configuration"
    {
        echo "=== LISTENER STATUS ==="
        if [ -n "${ORACLE_HOME:-}" ]; then
            $ORACLE_HOME/bin/lsnrctl status 2>&1 || echo "  Unable to get listener status"
        fi
        echo ""
        
        echo "=== TNSNAMES.ORA ==="
        for tns_file in "$ORACLE_HOME/network/admin/tnsnames.ora" "$TNS_ADMIN/tnsnames.ora" "/etc/tnsnames.ora"; do
            if [ -f "$tns_file" ]; then
                echo "File: $tns_file"
                cat "$tns_file"
                break
            fi
        done
        echo ""
        
        echo "=== SQLNET.ORA ==="
        for sqlnet_file in "$ORACLE_HOME/network/admin/sqlnet.ora" "$TNS_ADMIN/sqlnet.ora"; do
            if [ -f "$sqlnet_file" ]; then
                echo "File: $sqlnet_file"
                cat "$sqlnet_file"
                break
            fi
        done
        echo ""
        log_section_result "Network Configuration" "success"
    } 2>&1 || log_section_result "Network Configuration" "failed"
}

discover_authentication() {
    print_section "Authentication Configuration"
    {
        echo "=== PASSWORD FILE ==="
        run_sql "SHOW PARAMETER REMOTE_LOGIN_PASSWORDFILE;"
        echo ""
        echo "Password file location:"
        ls -la $ORACLE_HOME/dbs/orapw* 2>/dev/null || echo "  No password file found in \$ORACLE_HOME/dbs/"
        echo ""
        
        echo "=== SSH DIRECTORY ==="
        echo "SSH directory contents (oracle user):"
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            ls -la ~/.ssh/ 2>/dev/null || echo "  No .ssh directory"
        else
            sudo -u "$ORACLE_USER" ls -la ~$ORACLE_USER/.ssh/ 2>/dev/null || echo "  No .ssh directory or permission denied"
        fi
        echo ""
        log_section_result "Authentication Configuration" "success"
    } 2>&1 || log_section_result "Authentication Configuration" "failed"
}

discover_dataguard() {
    print_section "Data Guard Configuration"
    {
        echo "=== DATA GUARD STATUS ==="
        run_sql "SELECT DATABASE_ROLE, SWITCHOVER_STATUS, DATAGUARD_BROKER FROM V\$DATABASE;"
        echo ""
        echo "=== DATA GUARD PARAMETERS ==="
        run_sql "SHOW PARAMETER DG_BROKER;"
        run_sql "SHOW PARAMETER FAL_SERVER;"
        run_sql "SHOW PARAMETER FAL_CLIENT;"
        run_sql "SHOW PARAMETER LOG_ARCHIVE_CONFIG;"
        run_sql "SHOW PARAMETER DB_FILE_NAME_CONVERT;"
        run_sql "SHOW PARAMETER LOG_FILE_NAME_CONVERT;"
        run_sql "SHOW PARAMETER STANDBY_FILE_MANAGEMENT;"
        echo ""
        log_section_result "Data Guard Configuration" "success"
    } 2>&1 || log_section_result "Data Guard Configuration" "failed"
}

discover_schema_info() {
    print_section "Schema Information"
    {
        echo "=== SCHEMA SIZES (Non-system schemas > 100MB) ==="
        run_sql "
COL OWNER FORMAT A30
COL SIZE_GB FORMAT 999,999.99
SELECT OWNER, ROUND(SUM(BYTES)/1024/1024/1024, 2) AS SIZE_GB
FROM DBA_SEGMENTS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DIP','ORACLE_OCM','DBSNMP',
                    'APPQOSSYS','WMSYS','EXFSYS','CTXSYS','XDB','ORDDATA',
                    'ORDSYS','OLAPSYS','MDSYS','SPATIAL_CSW_ADMIN_USR',
                    'LBACSYS','DVSYS','DVF','SYSDG','SYSBACKUP','SYSKM',
                    'AUDSYS','GSMADMIN_INTERNAL','GSMUSER','DBSFWUSER',
                    'REMOTE_SCHEDULER_AGENT','PDBADMIN','SI_INFORMTN_SCHEMA',
                    'XS\$NULL','ORDPLUGINS','MDDATA','APEX_PUBLIC_USER')
GROUP BY OWNER
HAVING SUM(BYTES)/1024/1024 > 100
ORDER BY SIZE_GB DESC;
"
        echo ""
        echo "=== INVALID OBJECTS ==="
        run_sql "
COL OWNER FORMAT A30
COL OBJECT_TYPE FORMAT A20
SELECT OWNER, OBJECT_TYPE, COUNT(*) AS INVALID_COUNT
FROM DBA_OBJECTS
WHERE STATUS = 'INVALID'
GROUP BY OWNER, OBJECT_TYPE
ORDER BY OWNER, OBJECT_TYPE;
"
        echo ""
        log_section_result "Schema Information" "success"
    } 2>&1 || log_section_result "Schema Information" "failed"
}

#===============================================================================
# ADDITIONAL DISCOVERY (Project-specific requirements)
#===============================================================================

discover_tablespace_autoextend() {
    print_section "Tablespace Autoextend Settings"
    {
        echo "=== TABLESPACE AUTOEXTEND CONFIGURATION ==="
        run_sql "
COL TABLESPACE_NAME FORMAT A30
COL FILE_NAME FORMAT A60
COL SIZE_GB FORMAT 999,999.99
COL MAXSIZE_GB FORMAT 999,999.99
COL AUTOEXTEND FORMAT A10
COL INCREMENT_MB FORMAT 999,999
SELECT 
    TABLESPACE_NAME,
    FILE_NAME,
    ROUND(BYTES/1024/1024/1024, 2) AS SIZE_GB,
    CASE WHEN MAXBYTES = 0 THEN ROUND(BYTES/1024/1024/1024, 2)
         ELSE ROUND(MAXBYTES/1024/1024/1024, 2) END AS MAXSIZE_GB,
    AUTOEXTENSIBLE AS AUTOEXTEND,
    ROUND(INCREMENT_BY * (SELECT VALUE FROM V\$PARAMETER WHERE NAME = 'db_block_size') / 1024 / 1024) AS INCREMENT_MB
FROM DBA_DATA_FILES
ORDER BY TABLESPACE_NAME, FILE_NAME;
"
        echo ""
        echo "=== TEMP FILES AUTOEXTEND ==="
        run_sql "
COL TABLESPACE_NAME FORMAT A30
COL FILE_NAME FORMAT A60
COL SIZE_GB FORMAT 999,999.99
COL MAXSIZE_GB FORMAT 999,999.99
COL AUTOEXTEND FORMAT A10
SELECT 
    TABLESPACE_NAME,
    FILE_NAME,
    ROUND(BYTES/1024/1024/1024, 2) AS SIZE_GB,
    CASE WHEN MAXBYTES = 0 THEN ROUND(BYTES/1024/1024/1024, 2)
         ELSE ROUND(MAXBYTES/1024/1024/1024, 2) END AS MAXSIZE_GB,
    AUTOEXTENSIBLE AS AUTOEXTEND
FROM DBA_TEMP_FILES
ORDER BY TABLESPACE_NAME, FILE_NAME;
"
        echo ""
        log_section_result "Tablespace Autoextend" "success"
    } 2>&1 || log_section_result "Tablespace Autoextend" "failed"
}

discover_backup_schedule() {
    print_section "Backup Schedule and Retention"
    {
        echo "=== RMAN CONFIGURATION ==="
        run_sql "
COL NAME FORMAT A45
COL VALUE FORMAT A50
SELECT NAME, VALUE FROM V\$RMAN_CONFIGURATION ORDER BY NAME;
"
        echo ""
        echo "=== RECENT BACKUP HISTORY (Last 7 days) ==="
        run_sql "
COL START_TIME FORMAT A20
COL END_TIME FORMAT A20
COL INPUT_TYPE FORMAT A15
COL STATUS FORMAT A12
COL OUTPUT_GB FORMAT 999,999.99
SELECT 
    TO_CHAR(START_TIME, 'YYYY-MM-DD HH24:MI:SS') AS START_TIME,
    TO_CHAR(END_TIME, 'YYYY-MM-DD HH24:MI:SS') AS END_TIME,
    INPUT_TYPE,
    STATUS,
    ROUND(OUTPUT_BYTES/1024/1024/1024, 2) AS OUTPUT_GB
FROM V\$RMAN_BACKUP_JOB_DETAILS
WHERE START_TIME > SYSDATE - 7
ORDER BY START_TIME DESC;
"
        echo ""
        echo "=== CONTROLFILE AUTOBACKUP ==="
        run_sql "SHOW PARAMETER CONTROLFILE_RECORD_KEEP_TIME;"
        echo ""
        log_section_result "Backup Schedule" "success"
    } 2>&1 || log_section_result "Backup Schedule" "failed"
}

discover_database_links() {
    print_section "Database Links"
    {
        echo "=== DATABASE LINKS ==="
        run_sql "
COL OWNER FORMAT A20
COL DB_LINK FORMAT A40
COL USERNAME FORMAT A20
COL HOST FORMAT A50
SELECT OWNER, DB_LINK, USERNAME, HOST
FROM DBA_DB_LINKS
ORDER BY OWNER, DB_LINK;
"
        local link_count
        link_count=$(run_sql_value "SELECT COUNT(*) FROM DBA_DB_LINKS;")
        echo "Total Database Links: $link_count"
        echo ""
        
        echo "=== DATABASE LINK VALIDATION (Connection Test) ==="
        echo "Note: Run 'SELECT * FROM DUAL@<db_link>' to test each link"
        echo ""
        log_section_result "Database Links" "success"
    } 2>&1 || log_section_result "Database Links" "failed"
}

discover_materialized_views() {
    print_section "Materialized View Refresh Schedules"
    {
        echo "=== MATERIALIZED VIEWS ==="
        run_sql "
COL OWNER FORMAT A20
COL MVIEW_NAME FORMAT A35
COL REFRESH_MODE FORMAT A12
COL REFRESH_METHOD FORMAT A12
COL BUILD_MODE FORMAT A12
COL FAST_REFRESHABLE FORMAT A15
SELECT OWNER, MVIEW_NAME, REFRESH_MODE, REFRESH_METHOD, BUILD_MODE, FAST_REFRESHABLE
FROM DBA_MVIEWS
WHERE OWNER NOT IN ('SYS','SYSTEM')
ORDER BY OWNER, MVIEW_NAME;
"
        echo ""
        echo "=== MATERIALIZED VIEW REFRESH GROUPS ==="
        run_sql "
COL OWNER FORMAT A20
COL RNAME FORMAT A30
COL REFGROUP FORMAT 999999
COL IMPLICIT_DESTROY FORMAT A8
COL ROLLBACK_SEG FORMAT A20
COL JOB FORMAT 999999
SELECT OWNER, RNAME, REFGROUP, IMPLICIT_DESTROY, ROLLBACK_SEG, JOB
FROM DBA_REFRESH
WHERE OWNER NOT IN ('SYS','SYSTEM')
ORDER BY OWNER, RNAME;
"
        echo ""
        echo "=== MATERIALIZED VIEW REFRESH SCHEDULE ==="
        run_sql "
COL OWNER FORMAT A20
COL NAME FORMAT A35
COL NEXT_DATE FORMAT A20
COL INTERVAL FORMAT A30
SELECT ROWNER AS OWNER, NAME, 
       TO_CHAR(NEXT_DATE, 'YYYY-MM-DD HH24:MI:SS') AS NEXT_DATE,
       INTERVAL
FROM DBA_REFRESH_CHILDREN
WHERE ROWNER NOT IN ('SYS','SYSTEM')
ORDER BY ROWNER, NAME;
"
        echo ""
        log_section_result "Materialized Views" "success"
    } 2>&1 || log_section_result "Materialized Views" "failed"
}

discover_scheduler_jobs() {
    print_section "Scheduler Jobs"
    {
        echo "=== ACTIVE SCHEDULER JOBS ==="
        run_sql "
COL OWNER FORMAT A20
COL JOB_NAME FORMAT A35
COL JOB_TYPE FORMAT A15
COL ENABLED FORMAT A8
COL STATE FORMAT A15
COL NEXT_RUN_DATE FORMAT A25
SELECT OWNER, JOB_NAME, JOB_TYPE, ENABLED, STATE,
       TO_CHAR(NEXT_RUN_DATE, 'YYYY-MM-DD HH24:MI:SS') AS NEXT_RUN_DATE
FROM DBA_SCHEDULER_JOBS
WHERE OWNER NOT IN ('SYS','SYSTEM','ORACLE_OCM','EXFSYS')
  AND ENABLED = 'TRUE'
ORDER BY OWNER, JOB_NAME;
"
        echo ""
        echo "=== SCHEDULER JOB DETAILS ==="
        run_sql "
COL OWNER FORMAT A20
COL JOB_NAME FORMAT A35
COL REPEAT_INTERVAL FORMAT A50
SELECT OWNER, JOB_NAME, REPEAT_INTERVAL
FROM DBA_SCHEDULER_JOBS
WHERE OWNER NOT IN ('SYS','SYSTEM','ORACLE_OCM','EXFSYS')
  AND ENABLED = 'TRUE'
ORDER BY OWNER, JOB_NAME;
"
        echo ""
        echo "=== DBMS_JOB (Legacy Jobs) ==="
        run_sql "
COL JOB FORMAT 999999
COL SCHEMA_USER FORMAT A20
COL WHAT FORMAT A60
COL NEXT_DATE FORMAT A20
COL INTERVAL FORMAT A30
SELECT JOB, SCHEMA_USER, WHAT, 
       TO_CHAR(NEXT_DATE, 'YYYY-MM-DD HH24:MI:SS') AS NEXT_DATE,
       INTERVAL
FROM DBA_JOBS
WHERE BROKEN = 'N'
ORDER BY JOB;
"
        echo ""
        log_section_result "Scheduler Jobs" "success"
    } 2>&1 || log_section_result "Scheduler Jobs" "failed"
}

#===============================================================================
# JSON OUTPUT GENERATION
#===============================================================================

generate_json_summary() {
    print_section "Generating JSON Summary"
    
    local db_name db_unique_name dbid db_role open_mode log_mode force_logging
    local cdb_status data_size_gb charset tde_status
    
    db_name=$(run_sql_value "SELECT NAME FROM V\$DATABASE;")
    db_unique_name=$(run_sql_value "SELECT DB_UNIQUE_NAME FROM V\$DATABASE;")
    dbid=$(run_sql_value "SELECT DBID FROM V\$DATABASE;")
    db_role=$(run_sql_value "SELECT DATABASE_ROLE FROM V\$DATABASE;")
    open_mode=$(run_sql_value "SELECT OPEN_MODE FROM V\$DATABASE;")
    log_mode=$(run_sql_value "SELECT LOG_MODE FROM V\$DATABASE;")
    force_logging=$(run_sql_value "SELECT FORCE_LOGGING FROM V\$DATABASE;")
    cdb_status=$(run_sql_value "SELECT CDB FROM V\$DATABASE;")
    data_size_gb=$(run_sql_value "SELECT ROUND(SUM(BYTES)/1024/1024/1024, 2) FROM DBA_DATA_FILES;")
    charset=$(run_sql_value "SELECT VALUE FROM NLS_DATABASE_PARAMETERS WHERE PARAMETER = 'NLS_CHARACTERSET';")
    tde_status=$(run_sql_value "SELECT STATUS FROM V\$ENCRYPTION_WALLET WHERE ROWNUM = 1;")
    
    cat > "$JSON_FILE" << EOJSON
{
    "discovery_type": "source",
    "discovery_timestamp": "$(date -Iseconds)",
    "hostname": "$HOSTNAME",
    "oracle_home": "${ORACLE_HOME:-}",
    "oracle_sid": "${ORACLE_SID:-}",
    "database": {
        "name": "$db_name",
        "unique_name": "$db_unique_name",
        "dbid": "$dbid",
        "role": "$db_role",
        "open_mode": "$open_mode",
        "log_mode": "$log_mode",
        "force_logging": "$force_logging",
        "cdb": "$cdb_status",
        "data_size_gb": $data_size_gb,
        "character_set": "$charset"
    },
    "tde": {
        "status": "${tde_status:-NOT_CONFIGURED}"
    },
    "discovery_status": {
        "successful_sections": [$(printf '"%s",' "${SUCCESS_SECTIONS[@]}" | sed 's/,$//')]
        "failed_sections": [$(printf '"%s",' "${FAILED_SECTIONS[@]}" | sed 's/,$//')]
    }
}
EOJSON
    
    print_success "JSON summary written to: $JSON_FILE"
}

#===============================================================================
# MAIN EXECUTION
#===============================================================================

main() {
    print_header "ZDM Source Database Discovery"
    echo "Project: PRODDB Migration to Oracle Database@Azure"
    echo "Timestamp: $(date)"
    echo "Output File: $OUTPUT_FILE"
    echo ""
    
    # Detect Oracle environment
    detect_oracle_env
    if [ $? -ne 0 ]; then
        print_error "Cannot proceed without Oracle environment"
        exit 1
    fi
    
    # Run all discovery sections and capture to output file
    {
        echo "==============================================================================="
        echo "ZDM SOURCE DATABASE DISCOVERY REPORT"
        echo "==============================================================================="
        echo "Project: PRODDB Migration to Oracle Database@Azure"
        echo "Hostname: $HOSTNAME"
        echo "Timestamp: $(date)"
        echo "ORACLE_HOME: ${ORACLE_HOME:-NOT SET}"
        echo "ORACLE_SID: ${ORACLE_SID:-NOT SET}"
        echo "==============================================================================="
        echo ""
        
        # Standard discovery sections
        discover_os_info
        discover_oracle_env
        discover_database_config
        discover_cdb_pdb
        discover_tde_config
        discover_supplemental_logging
        discover_redo_archive
        discover_network_config
        discover_authentication
        discover_dataguard
        discover_schema_info
        
        # Additional discovery (project-specific)
        discover_tablespace_autoextend
        discover_backup_schedule
        discover_database_links
        discover_materialized_views
        discover_scheduler_jobs
        
        echo ""
        echo "==============================================================================="
        echo "DISCOVERY SUMMARY"
        echo "==============================================================================="
        echo "Successful Sections: ${#SUCCESS_SECTIONS[@]}"
        echo "Failed Sections: ${#FAILED_SECTIONS[@]}"
        if [ ${#FAILED_SECTIONS[@]} -gt 0 ]; then
            echo "Failed: ${FAILED_SECTIONS[*]}"
        fi
        echo "==============================================================================="
        
    } 2>&1 | tee "$OUTPUT_FILE"
    
    # Generate JSON summary
    generate_json_summary
    
    print_header "Discovery Complete"
    echo "Text Report: $OUTPUT_FILE"
    echo "JSON Summary: $JSON_FILE"
    echo ""
    
    if [ ${#FAILED_SECTIONS[@]} -gt 0 ]; then
        print_warning "Some sections failed. Check the output for details."
        exit 1
    else
        print_success "All discovery sections completed successfully"
        exit 0
    fi
}

# Run main function
main "$@"
