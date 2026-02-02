#!/bin/bash
#===============================================================================
# ZDM Source Database Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# Source: proddb01.corp.example.com
#
# This script discovers source database configuration for ZDM migration.
# It is executed via SSH as an admin user, with SQL commands running as
# the oracle user via sudo.
#
# Usage: ./zdm_source_discovery.sh
# Output: zdm_source_discovery_<hostname>_<timestamp>.txt
#         zdm_source_discovery_<hostname>_<timestamp>.json
#===============================================================================

#-------------------------------------------------------------------------------
# Color Output Functions
#-------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "\n${CYAN}=== $1 ===${NC}"; }

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
HOSTNAME=$(hostname -s 2>/dev/null || hostname)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="./zdm_source_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_source_discovery_${HOSTNAME}_${TIMESTAMP}.json"

# User configuration
ORACLE_USER="${ORACLE_USER:-oracle}"

#-------------------------------------------------------------------------------
# Auto-detect Oracle Environment
#-------------------------------------------------------------------------------
detect_oracle_env() {
    log_info "Auto-detecting Oracle environment..."
    
    # If already set, use existing values
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        log_info "Using pre-configured ORACLE_HOME=$ORACLE_HOME, ORACLE_SID=$ORACLE_SID"
        return 0
    fi
    
    # Method 1: Parse /etc/oratab (most reliable)
    if [ -f /etc/oratab ]; then
        local oratab_entry
        if [ -n "${ORACLE_SID:-}" ]; then
            oratab_entry=$(grep "^${ORACLE_SID}:" /etc/oratab 2>/dev/null | head -1)
        else
            oratab_entry=$(grep -v '^#' /etc/oratab | grep -v '^$' | grep -v '^\*' | head -1)
        fi
        if [ -n "$oratab_entry" ]; then
            export ORACLE_SID="${ORACLE_SID:-$(echo "$oratab_entry" | cut -d: -f1)}"
            export ORACLE_HOME="${ORACLE_HOME:-$(echo "$oratab_entry" | cut -d: -f2)}"
            log_info "Detected from oratab: ORACLE_SID=$ORACLE_SID, ORACLE_HOME=$ORACLE_HOME"
        fi
    fi
    
    # Method 2: Check running pmon process
    if [ -z "${ORACLE_SID:-}" ]; then
        local pmon_sid
        pmon_sid=$(ps -ef | grep 'ora_pmon_' | grep -v grep | head -1 | sed 's/.*ora_pmon_//')
        if [ -n "$pmon_sid" ]; then
            export ORACLE_SID="$pmon_sid"
            log_info "Detected from pmon process: ORACLE_SID=$ORACLE_SID"
        fi
    fi
    
    # Method 3: Search common Oracle installation paths
    if [ -z "${ORACLE_HOME:-}" ]; then
        for path in /u01/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1 /oracle/product/*/dbhome_1; do
            if [ -d "$path" ] && [ -f "$path/bin/sqlplus" ]; then
                export ORACLE_HOME="$path"
                log_info "Detected from common path: ORACLE_HOME=$ORACLE_HOME"
                break
            fi
        done
    fi
    
    # Method 4: Get from oracle user's environment
    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        if id "$ORACLE_USER" &>/dev/null; then
            local oracle_env
            oracle_env=$(sudo -u "$ORACLE_USER" -i bash -c 'echo "ORACLE_HOME=$ORACLE_HOME;ORACLE_SID=$ORACLE_SID"' 2>/dev/null)
            if [ -n "$oracle_env" ]; then
                eval "$oracle_env"
                [ -n "$ORACLE_HOME" ] && export ORACLE_HOME
                [ -n "$ORACLE_SID" ] && export ORACLE_SID
                log_info "Detected from oracle user environment: ORACLE_HOME=$ORACLE_HOME, ORACLE_SID=$ORACLE_SID"
            fi
        fi
    fi
    
    # Apply explicit overrides if provided (highest priority)
    [ -n "${ORACLE_HOME_OVERRIDE:-}" ] && export ORACLE_HOME="$ORACLE_HOME_OVERRIDE"
    [ -n "${ORACLE_SID_OVERRIDE:-}" ] && export ORACLE_SID="$ORACLE_SID_OVERRIDE"
}

#-------------------------------------------------------------------------------
# SQL Execution Functions
#-------------------------------------------------------------------------------
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
        local result
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            result=$(echo "$sql_script" | ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd 2>/dev/null)
        else
            result=$(echo "$sql_script" | sudo -u "$ORACLE_USER" ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd 2>/dev/null)
        fi
        echo "$result" | sed '/^$/d' | head -1
    else
        echo "ERROR"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# Discovery Functions
#-------------------------------------------------------------------------------

discover_os_info() {
    log_section "OS Information"
    echo "Hostname: $(hostname)"
    echo "FQDN: $(hostname -f 2>/dev/null || echo 'N/A')"
    echo "IP Addresses:"
    ip addr show 2>/dev/null | grep 'inet ' | awk '{print "  " $2}' || hostname -I 2>/dev/null | tr ' ' '\n' | sed 's/^/  /'
    echo ""
    echo "Operating System:"
    cat /etc/os-release 2>/dev/null | grep -E '^(NAME|VERSION)=' || cat /etc/redhat-release 2>/dev/null
    echo ""
    echo "Kernel: $(uname -r)"
    echo ""
    echo "Disk Space:"
    df -h 2>/dev/null | grep -E '^/|Filesystem'
}

discover_oracle_env() {
    log_section "Oracle Environment"
    echo "ORACLE_HOME: ${ORACLE_HOME:-NOT SET}"
    echo "ORACLE_SID: ${ORACLE_SID:-NOT SET}"
    echo "ORACLE_BASE: ${ORACLE_BASE:-NOT SET}"
    
    if [ -n "${ORACLE_HOME:-}" ]; then
        if [ -f "$ORACLE_HOME/bin/sqlplus" ]; then
            echo ""
            echo "Oracle Version:"
            if [ "$(whoami)" = "$ORACLE_USER" ]; then
                $ORACLE_HOME/bin/sqlplus -V 2>/dev/null | head -3
            else
                sudo -u "$ORACLE_USER" ORACLE_HOME="$ORACLE_HOME" $ORACLE_HOME/bin/sqlplus -V 2>/dev/null | head -3
            fi
        fi
    fi
}

discover_db_config() {
    log_section "Database Configuration"
    
    run_sql "SELECT 'Database Name: ' || name FROM v\$database;"
    run_sql "SELECT 'DB Unique Name: ' || db_unique_name FROM v\$database;"
    run_sql "SELECT 'DBID: ' || dbid FROM v\$database;"
    run_sql "SELECT 'Database Role: ' || database_role FROM v\$database;"
    run_sql "SELECT 'Open Mode: ' || open_mode FROM v\$database;"
    run_sql "SELECT 'Log Mode: ' || log_mode FROM v\$database;"
    run_sql "SELECT 'Force Logging: ' || force_logging FROM v\$database;"
    run_sql "SELECT 'Flashback On: ' || flashback_on FROM v\$database;"
    
    echo ""
    echo "Database Size:"
    run_sql "
SELECT 'Data Files: ' || ROUND(SUM(bytes)/1024/1024/1024, 2) || ' GB' 
FROM dba_data_files;
"
    run_sql "
SELECT 'Temp Files: ' || ROUND(SUM(bytes)/1024/1024/1024, 2) || ' GB' 
FROM dba_temp_files;
"
    
    echo ""
    echo "Character Set:"
    run_sql "SELECT 'Character Set: ' || value FROM nls_database_parameters WHERE parameter = 'NLS_CHARACTERSET';"
    run_sql "SELECT 'National Character Set: ' || value FROM nls_database_parameters WHERE parameter = 'NLS_NCHAR_CHARACTERSET';"
}

discover_cdb_pdb() {
    log_section "Container Database Configuration"
    
    local cdb_status=$(run_sql_value "SELECT CDB FROM v\$database;")
    echo "CDB Status: $cdb_status"
    
    if [ "$cdb_status" = "YES" ]; then
        echo ""
        echo "PDB List:"
        run_sql "
SELECT con_id, name, open_mode, restricted, total_size/1024/1024 AS size_mb
FROM v\$pdbs
ORDER BY con_id;
"
    fi
}

discover_tde() {
    log_section "TDE Configuration"
    
    echo "Encryption Wallet Status:"
    run_sql "
SELECT wrl_type, wrl_parameter, status, wallet_type, wallet_order
FROM v\$encryption_wallet;
"
    
    echo ""
    echo "Encrypted Tablespaces:"
    run_sql "
SELECT tablespace_name, encrypted, status
FROM dba_tablespaces
WHERE encrypted = 'YES';
"
    
    echo ""
    echo "TDE Master Key Info:"
    run_sql "
SELECT key_id, activation_time, creator, key_use
FROM v\$encryption_keys
WHERE ROWNUM <= 5;
"
}

discover_supplemental_logging() {
    log_section "Supplemental Logging"
    
    run_sql "
SELECT 'Supplemental Log Data Min: ' || supplemental_log_data_min,
       'Supplemental Log Data PK: ' || supplemental_log_data_pk,
       'Supplemental Log Data UI: ' || supplemental_log_data_ui,
       'Supplemental Log Data FK: ' || supplemental_log_data_fk,
       'Supplemental Log Data All: ' || supplemental_log_data_all
FROM v\$database;
"
}

discover_redo_archive() {
    log_section "Redo and Archive Configuration"
    
    echo "Redo Log Groups:"
    run_sql "
SELECT group#, thread#, sequence#, bytes/1024/1024 AS size_mb, 
       members, archived, status
FROM v\$log
ORDER BY group#;
"
    
    echo ""
    echo "Redo Log Members:"
    run_sql "
SELECT group#, member, type, status
FROM v\$logfile
ORDER BY group#;
"
    
    echo ""
    echo "Archive Log Destinations:"
    run_sql "
SELECT dest_id, dest_name, status, type, destination
FROM v\$archive_dest
WHERE status = 'VALID' OR destination IS NOT NULL;
"
    
    echo ""
    echo "Archive Log Mode:"
    run_sql "SELECT 'Archive Mode: ' || log_mode FROM v\$database;"
}

discover_network_config() {
    log_section "Network Configuration"
    
    echo "Listener Status:"
    if [ -n "${ORACLE_HOME:-}" ]; then
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            ORACLE_HOME="$ORACLE_HOME" $ORACLE_HOME/bin/lsnrctl status 2>/dev/null | head -30
        else
            sudo -u "$ORACLE_USER" ORACLE_HOME="$ORACLE_HOME" $ORACLE_HOME/bin/lsnrctl status 2>/dev/null | head -30
        fi
    fi
    
    echo ""
    echo "tnsnames.ora:"
    if [ -n "${ORACLE_HOME:-}" ] && [ -f "$ORACLE_HOME/network/admin/tnsnames.ora" ]; then
        cat "$ORACLE_HOME/network/admin/tnsnames.ora" 2>/dev/null
    else
        echo "File not found"
    fi
    
    echo ""
    echo "sqlnet.ora:"
    if [ -n "${ORACLE_HOME:-}" ] && [ -f "$ORACLE_HOME/network/admin/sqlnet.ora" ]; then
        cat "$ORACLE_HOME/network/admin/sqlnet.ora" 2>/dev/null
    else
        echo "File not found"
    fi
}

discover_auth_config() {
    log_section "Authentication Configuration"
    
    echo "Password File Location:"
    if [ -n "${ORACLE_HOME:-}" ]; then
        ls -la "$ORACLE_HOME/dbs/orapw"* 2>/dev/null || echo "No password file found in \$ORACLE_HOME/dbs/"
    fi
    
    echo ""
    echo "SSH Directory Contents (for oracle user):"
    local oracle_home_dir=$(eval echo ~$ORACLE_USER)
    if [ -d "$oracle_home_dir/.ssh" ]; then
        ls -la "$oracle_home_dir/.ssh/" 2>/dev/null
    else
        echo "SSH directory not found for $ORACLE_USER user (this is expected when using admin user with sudo)"
    fi
}

discover_dataguard() {
    log_section "Data Guard Configuration"
    
    run_sql "
SELECT name, value 
FROM v\$parameter 
WHERE name IN (
    'log_archive_config',
    'log_archive_dest_1',
    'log_archive_dest_2',
    'log_archive_dest_state_1',
    'log_archive_dest_state_2',
    'fal_server',
    'fal_client',
    'standby_file_management',
    'db_file_name_convert',
    'log_file_name_convert'
)
ORDER BY name;
"
}

discover_schema_info() {
    log_section "Schema Information"
    
    echo "Schema Sizes (non-system schemas > 100MB):"
    run_sql "
SELECT owner, ROUND(SUM(bytes)/1024/1024, 2) AS size_mb
FROM dba_segments
WHERE owner NOT IN ('SYS', 'SYSTEM', 'OUTLN', 'DIP', 'ORACLE_OCM', 
                    'DBSNMP', 'APPQOSSYS', 'WMSYS', 'EXFSYS', 'CTXSYS',
                    'XDB', 'ORDDATA', 'ORDSYS', 'MDSYS', 'OLAPSYS',
                    'GSMADMIN_INTERNAL', 'AUDSYS', 'DBSFWUSER', 'REMOTE_SCHEDULER_AGENT')
GROUP BY owner
HAVING SUM(bytes) > 100*1024*1024
ORDER BY size_mb DESC;
"
    
    echo ""
    echo "Invalid Objects by Owner/Type:"
    run_sql "
SELECT owner, object_type, COUNT(*) AS invalid_count
FROM dba_objects
WHERE status = 'INVALID'
AND owner NOT IN ('SYS', 'SYSTEM', 'OUTLN', 'PUBLIC')
GROUP BY owner, object_type
ORDER BY owner, object_type;
"
}

#-------------------------------------------------------------------------------
# Additional Discovery (Custom Requirements)
#-------------------------------------------------------------------------------

discover_tablespace_autoextend() {
    log_section "Tablespace Autoextend Settings"
    
    run_sql "
SELECT tablespace_name, file_name, 
       ROUND(bytes/1024/1024, 2) AS size_mb,
       ROUND(maxbytes/1024/1024, 2) AS max_size_mb,
       autoextensible,
       ROUND(increment_by * (SELECT value FROM v\$parameter WHERE name = 'db_block_size') / 1024 / 1024, 2) AS increment_mb
FROM dba_data_files
ORDER BY tablespace_name, file_name;
"
}

discover_backup_schedule() {
    log_section "Backup Schedule and Retention"
    
    echo "RMAN Configuration:"
    run_sql "SELECT name, value FROM v\$rman_configuration ORDER BY name;"
    
    echo ""
    echo "Recent Backup History (last 7 days):"
    run_sql "
SELECT TO_CHAR(start_time, 'YYYY-MM-DD HH24:MI') AS start_time,
       TO_CHAR(end_time, 'YYYY-MM-DD HH24:MI') AS end_time,
       input_type, status, 
       ROUND(input_bytes/1024/1024/1024, 2) AS input_gb,
       ROUND(output_bytes/1024/1024/1024, 2) AS output_gb
FROM v\$rman_backup_job_details
WHERE start_time > SYSDATE - 7
ORDER BY start_time DESC;
"
}

discover_db_links() {
    log_section "Database Links"
    
    run_sql "
SELECT owner, db_link, username, host, created
FROM dba_db_links
ORDER BY owner, db_link;
"
}

discover_materialized_views() {
    log_section "Materialized View Refresh Schedules"
    
    run_sql "
SELECT owner, mview_name, refresh_mode, refresh_method,
       build_mode, fast_refreshable,
       last_refresh_type, 
       TO_CHAR(last_refresh_date, 'YYYY-MM-DD HH24:MI:SS') AS last_refresh
FROM dba_mviews
WHERE owner NOT IN ('SYS', 'SYSTEM')
ORDER BY owner, mview_name;
"
    
    echo ""
    echo "Materialized View Refresh Groups:"
    run_sql "
SELECT rowner, rname, refgroup, implicit_destroy, 
       push_deferred_rpc, refresh_after_errors,
       job, next_date, interval
FROM dba_refresh
ORDER BY rowner, rname;
"
}

discover_scheduler_jobs() {
    log_section "Scheduler Jobs"
    
    run_sql "
SELECT owner, job_name, job_type, state, enabled,
       TO_CHAR(start_date, 'YYYY-MM-DD HH24:MI') AS start_date,
       repeat_interval,
       TO_CHAR(last_start_date, 'YYYY-MM-DD HH24:MI') AS last_start,
       TO_CHAR(next_run_date, 'YYYY-MM-DD HH24:MI') AS next_run
FROM dba_scheduler_jobs
WHERE owner NOT IN ('SYS', 'SYSTEM', 'ORACLE_OCM', 'EXFSYS')
ORDER BY owner, job_name;
"
    
    echo ""
    echo "DBMS_JOB Jobs (Legacy):"
    run_sql "
SELECT job, log_user, schema_user, 
       TO_CHAR(last_date, 'YYYY-MM-DD HH24:MI') AS last_date,
       TO_CHAR(next_date, 'YYYY-MM-DD HH24:MI') AS next_date,
       interval, broken, failures, what
FROM dba_jobs
ORDER BY job;
"
}

#-------------------------------------------------------------------------------
# JSON Output Generation
#-------------------------------------------------------------------------------
generate_json_summary() {
    local db_name=$(run_sql_value "SELECT name FROM v\$database;")
    local db_unique_name=$(run_sql_value "SELECT db_unique_name FROM v\$database;")
    local dbid=$(run_sql_value "SELECT dbid FROM v\$database;")
    local db_role=$(run_sql_value "SELECT database_role FROM v\$database;")
    local open_mode=$(run_sql_value "SELECT open_mode FROM v\$database;")
    local log_mode=$(run_sql_value "SELECT log_mode FROM v\$database;")
    local force_logging=$(run_sql_value "SELECT force_logging FROM v\$database;")
    local cdb_status=$(run_sql_value "SELECT CDB FROM v\$database;")
    local charset=$(run_sql_value "SELECT value FROM nls_database_parameters WHERE parameter = 'NLS_CHARACTERSET';")
    local version=$(run_sql_value "SELECT version_full FROM v\$instance;" 2>/dev/null || run_sql_value "SELECT version FROM v\$instance;")
    local data_size=$(run_sql_value "SELECT ROUND(SUM(bytes)/1024/1024/1024, 2) FROM dba_data_files;")
    local wallet_status=$(run_sql_value "SELECT status FROM v\$encryption_wallet WHERE ROWNUM = 1;")
    local supp_log_min=$(run_sql_value "SELECT supplemental_log_data_min FROM v\$database;")
    
    cat > "$JSON_FILE" <<EOF
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
    "version": "$version",
    "character_set": "$charset",
    "data_size_gb": "$data_size"
  },
  "tde": {
    "wallet_status": "$wallet_status"
  },
  "supplemental_logging": {
    "minimal": "$supp_log_min"
  },
  "output_files": {
    "text_report": "$OUTPUT_FILE",
    "json_summary": "$JSON_FILE"
  }
}
EOF
    
    log_info "JSON summary written to: $JSON_FILE"
}

#-------------------------------------------------------------------------------
# Main Execution
#-------------------------------------------------------------------------------
main() {
    log_info "Starting ZDM Source Discovery on $HOSTNAME"
    log_info "Timestamp: $TIMESTAMP"
    log_info "Running as user: $(whoami)"
    log_info "Oracle user for SQL execution: $ORACLE_USER"
    
    # Detect Oracle environment
    detect_oracle_env
    
    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        log_error "Failed to detect Oracle environment. Please set ORACLE_HOME and ORACLE_SID."
        exit 1
    fi
    
    # Run all discovery sections with error handling
    {
        echo "==============================================================================="
        echo "ZDM Source Database Discovery Report"
        echo "Project: PRODDB Migration to Oracle Database@Azure"
        echo "Source: proddb01.corp.example.com"
        echo "Generated: $(date)"
        echo "Hostname: $HOSTNAME"
        echo "==============================================================================="
        
        # Standard discovery
        discover_os_info || log_warn "OS info discovery had errors"
        discover_oracle_env || log_warn "Oracle env discovery had errors"
        discover_db_config || log_warn "DB config discovery had errors"
        discover_cdb_pdb || log_warn "CDB/PDB discovery had errors"
        discover_tde || log_warn "TDE discovery had errors"
        discover_supplemental_logging || log_warn "Supplemental logging discovery had errors"
        discover_redo_archive || log_warn "Redo/Archive discovery had errors"
        discover_network_config || log_warn "Network config discovery had errors"
        discover_auth_config || log_warn "Auth config discovery had errors"
        discover_dataguard || log_warn "Data Guard discovery had errors"
        discover_schema_info || log_warn "Schema info discovery had errors"
        
        # Additional custom discovery requirements
        discover_tablespace_autoextend || log_warn "Tablespace autoextend discovery had errors"
        discover_backup_schedule || log_warn "Backup schedule discovery had errors"
        discover_db_links || log_warn "Database links discovery had errors"
        discover_materialized_views || log_warn "Materialized views discovery had errors"
        discover_scheduler_jobs || log_warn "Scheduler jobs discovery had errors"
        
        echo ""
        echo "==============================================================================="
        echo "End of Discovery Report"
        echo "==============================================================================="
    } 2>&1 | tee "$OUTPUT_FILE"
    
    # Generate JSON summary
    generate_json_summary
    
    log_info "Discovery complete!"
    log_info "Text report: $OUTPUT_FILE"
    log_info "JSON summary: $JSON_FILE"
}

# Execute main function
main "$@"
