#!/bin/bash
#
# ZDM Source Database Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# Source Database: proddb01.corp.example.com
#
# This script gathers comprehensive information about the source Oracle database
# for ZDM migration planning. It should be executed via SSH as the admin user
# with sudo privileges to run SQL commands as the oracle user.
#
# Usage: bash zdm_source_discovery.sh
#
# Output: 
#   - zdm_source_discovery_<hostname>_<timestamp>.txt (human-readable)
#   - zdm_source_discovery_<hostname>_<timestamp>.json (machine-parseable)
#

# =============================================================================
# CONFIGURATION
# =============================================================================

# Oracle user configuration
ORACLE_USER="${ORACLE_USER:-oracle}"

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Timestamp for output files
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME_SHORT=$(hostname -s)
OUTPUT_FILE="./zdm_source_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_source_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

log_section() {
    local title="$1"
    echo ""
    echo -e "${BLUE}=============================================================================${NC}"
    echo -e "${BLUE}  $title${NC}"
    echo -e "${BLUE}=============================================================================${NC}"
    echo ""
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_subsection() {
    echo ""
    echo -e "${CYAN}--- $1 ---${NC}"
    echo ""
}

# Auto-detect Oracle environment
detect_oracle_env() {
    # If already set, use existing values
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        log_info "Using pre-configured ORACLE_HOME=$ORACLE_HOME, ORACLE_SID=$ORACLE_SID"
        return 0
    fi
    
    log_info "Auto-detecting Oracle environment..."
    
    # Method 1: Parse /etc/oratab (most reliable)
    if [ -f /etc/oratab ]; then
        local oratab_entry
        if [ -n "${ORACLE_SID:-}" ]; then
            oratab_entry=$(grep "^${ORACLE_SID}:" /etc/oratab 2>/dev/null | head -1)
        else
            oratab_entry=$(grep -v '^#' /etc/oratab | grep -v '^$' | grep -v '^+' | head -1)
        fi
        if [ -n "$oratab_entry" ]; then
            export ORACLE_SID="${ORACLE_SID:-$(echo "$oratab_entry" | cut -d: -f1)}"
            export ORACLE_HOME="${ORACLE_HOME:-$(echo "$oratab_entry" | cut -d: -f2)}"
            log_info "Detected from /etc/oratab: ORACLE_SID=$ORACLE_SID, ORACLE_HOME=$ORACLE_HOME"
        fi
    fi
    
    # Method 2: Check running pmon process
    if [ -z "${ORACLE_SID:-}" ]; then
        local pmon_sid
        pmon_sid=$(ps -ef | grep 'ora_pmon_' | grep -v grep | head -1 | sed 's/.*ora_pmon_//')
        if [ -n "$pmon_sid" ]; then
            export ORACLE_SID="$pmon_sid"
            log_info "Detected ORACLE_SID from pmon process: $ORACLE_SID"
        fi
    fi
    
    # Method 3: Search common Oracle installation paths
    if [ -z "${ORACLE_HOME:-}" ]; then
        for path in /u01/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1 /oracle/product/*/dbhome_1; do
            if [ -d "$path" ] && [ -f "$path/bin/sqlplus" ]; then
                export ORACLE_HOME="$path"
                log_info "Detected ORACLE_HOME from path search: $ORACLE_HOME"
                break
            fi
        done
    fi
    
    # Method 4: Try to get from oracle user environment
    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        local oracle_env
        oracle_env=$(sudo -u "$ORACLE_USER" -i bash -c 'echo "ORACLE_HOME=$ORACLE_HOME ORACLE_SID=$ORACLE_SID"' 2>/dev/null)
        if [ -n "$oracle_env" ]; then
            local extracted_home extracted_sid
            extracted_home=$(echo "$oracle_env" | grep -oP 'ORACLE_HOME=\K[^ ]+')
            extracted_sid=$(echo "$oracle_env" | grep -oP 'ORACLE_SID=\K[^ ]+')
            [ -z "${ORACLE_HOME:-}" ] && [ -n "$extracted_home" ] && export ORACLE_HOME="$extracted_home"
            [ -z "${ORACLE_SID:-}" ] && [ -n "$extracted_sid" ] && export ORACLE_SID="$extracted_sid"
            log_info "Detected from oracle user environment: ORACLE_HOME=$ORACLE_HOME, ORACLE_SID=$ORACLE_SID"
        fi
    fi
    
    # Apply explicit overrides if provided (highest priority)
    [ -n "${ORACLE_HOME_OVERRIDE:-}" ] && export ORACLE_HOME="$ORACLE_HOME_OVERRIDE"
    [ -n "${ORACLE_SID_OVERRIDE:-}" ] && export ORACLE_SID="$ORACLE_SID_OVERRIDE"
}

# Run SQL command as oracle user
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

# Run SQL and return single value
run_sql_value() {
    local sql_query="$1"
    local result
    result=$(run_sql "$sql_query" | grep -v '^$' | tail -1 | xargs)
    echo "$result"
}

# Initialize JSON output
init_json() {
    echo "{" > "$JSON_FILE"
    echo '  "discovery_type": "source",' >> "$JSON_FILE"
    echo "  \"hostname\": \"$HOSTNAME_SHORT\"," >> "$JSON_FILE"
    echo "  \"timestamp\": \"$TIMESTAMP\"," >> "$JSON_FILE"
    echo '  "project": "PRODDB Migration to Oracle Database@Azure",' >> "$JSON_FILE"
}

# Add JSON key-value pair
add_json() {
    local key="$1"
    local value="$2"
    local is_last="${3:-false}"
    # Escape special characters in value
    value=$(echo "$value" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g')
    if [ "$is_last" = "true" ]; then
        echo "  \"$key\": \"$value\"" >> "$JSON_FILE"
    else
        echo "  \"$key\": \"$value\"," >> "$JSON_FILE"
    fi
}

# Finalize JSON output
finalize_json() {
    echo "}" >> "$JSON_FILE"
}

# =============================================================================
# DISCOVERY FUNCTIONS
# =============================================================================

discover_os_info() {
    log_section "OS INFORMATION"
    
    log_subsection "Hostname and IP Addresses"
    echo "Hostname: $(hostname)"
    echo "Short hostname: $(hostname -s)"
    echo ""
    echo "IP Addresses:"
    ip addr show 2>/dev/null | grep 'inet ' | awk '{print "  " $2}' || hostname -I 2>/dev/null || echo "  Unable to determine"
    
    log_subsection "Operating System Version"
    if [ -f /etc/os-release ]; then
        cat /etc/os-release
    elif [ -f /etc/redhat-release ]; then
        cat /etc/redhat-release
    else
        uname -a
    fi
    
    log_subsection "Kernel Information"
    uname -r
    
    log_subsection "Disk Space"
    df -h 2>/dev/null || df 2>/dev/null
    
    log_subsection "Memory Information"
    free -h 2>/dev/null || free 2>/dev/null || cat /proc/meminfo | head -10
}

discover_oracle_env() {
    log_section "ORACLE ENVIRONMENT"
    
    log_subsection "Environment Variables"
    echo "ORACLE_HOME: ${ORACLE_HOME:-NOT SET}"
    echo "ORACLE_SID: ${ORACLE_SID:-NOT SET}"
    echo "ORACLE_BASE: ${ORACLE_BASE:-NOT SET}"
    
    log_subsection "Oracle Version"
    if [ -n "${ORACLE_HOME:-}" ] && [ -f "$ORACLE_HOME/bin/sqlplus" ]; then
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            ORACLE_HOME="$ORACLE_HOME" "$ORACLE_HOME/bin/sqlplus" -v 2>/dev/null || echo "Unable to get sqlplus version"
        else
            sudo -u "$ORACLE_USER" ORACLE_HOME="$ORACLE_HOME" "$ORACLE_HOME/bin/sqlplus" -v 2>/dev/null || echo "Unable to get sqlplus version"
        fi
    else
        echo "ORACLE_HOME not set or sqlplus not found"
    fi
    
    log_subsection "Oracle Version from Database"
    run_sql "SELECT banner FROM v\$version WHERE ROWNUM = 1;"
    
    log_subsection "/etc/oratab Contents"
    if [ -f /etc/oratab ]; then
        cat /etc/oratab
    else
        echo "/etc/oratab not found"
    fi
}

discover_database_config() {
    log_section "DATABASE CONFIGURATION"
    
    log_subsection "Database Identification"
    run_sql "SELECT name, db_unique_name, dbid, created FROM v\$database;"
    
    log_subsection "Database Role and Status"
    run_sql "SELECT database_role, open_mode, protection_mode, switchover_status FROM v\$database;"
    
    log_subsection "Log Mode and Force Logging"
    run_sql "SELECT log_mode, force_logging FROM v\$database;"
    
    log_subsection "Database Size Summary"
    run_sql "
SELECT 'Data Files' AS component, 
       ROUND(SUM(bytes)/1024/1024/1024, 2) AS size_gb
FROM dba_data_files
UNION ALL
SELECT 'Temp Files', ROUND(SUM(bytes)/1024/1024/1024, 2)
FROM dba_temp_files
UNION ALL
SELECT 'Redo Logs', ROUND(SUM(bytes)/1024/1024/1024, 2)
FROM v\$log;
"
    
    log_subsection "Character Set Configuration"
    run_sql "SELECT parameter, value FROM nls_database_parameters WHERE parameter IN ('NLS_CHARACTERSET', 'NLS_NCHAR_CHARACTERSET', 'NLS_LANGUAGE', 'NLS_TERRITORY');"
    
    log_subsection "Database Parameters (Key Migration-Related)"
    run_sql "
SELECT name, value FROM v\$parameter 
WHERE name IN (
    'db_name', 'db_unique_name', 'db_domain', 'global_names',
    'compatible', 'enable_pluggable_database',
    'remote_login_passwordfile', 'db_block_size',
    'processes', 'sessions', 'sga_target', 'pga_aggregate_target',
    'db_recovery_file_dest', 'db_recovery_file_dest_size'
)
ORDER BY name;
"
}

discover_cdb_pdb() {
    log_section "CONTAINER DATABASE (CDB/PDB)"
    
    log_subsection "CDB Status"
    local cdb_status
    cdb_status=$(run_sql_value "SELECT cdb FROM v\$database;")
    echo "CDB Enabled: $cdb_status"
    
    if [ "$cdb_status" = "YES" ]; then
        log_subsection "PDB Information"
        run_sql "SELECT con_id, name, open_mode, restricted, total_size/1024/1024/1024 AS size_gb FROM v\$pdbs ORDER BY con_id;"
        
        log_subsection "PDB Services"
        run_sql "SELECT con_id, name, network_name FROM v\$services ORDER BY con_id;"
    else
        echo "Database is non-CDB"
    fi
}

discover_tde_config() {
    log_section "TDE (TRANSPARENT DATA ENCRYPTION)"
    
    log_subsection "Encryption Wallet Status"
    run_sql "SELECT wrl_type, wrl_parameter, status, wallet_type FROM v\$encryption_wallet;"
    
    log_subsection "Encrypted Tablespaces"
    run_sql "SELECT tablespace_name, encrypted FROM dba_tablespaces WHERE encrypted = 'YES';"
    
    log_subsection "Encryption Keys"
    run_sql "SELECT key_id, activation_time, creator, key_use FROM v\$encryption_keys;" 2>/dev/null || echo "Unable to query encryption keys"
    
    log_subsection "TDE Master Key Info"
    run_sql "SELECT * FROM v\$encryption_wallet;" 2>/dev/null || echo "No TDE wallet configured"
}

discover_supplemental_logging() {
    log_section "SUPPLEMENTAL LOGGING"
    
    run_sql "
SELECT 'Minimal' AS log_type, supplemental_log_data_min AS status FROM v\$database
UNION ALL
SELECT 'Primary Key', supplemental_log_data_pk FROM v\$database
UNION ALL
SELECT 'Unique Index', supplemental_log_data_ui FROM v\$database
UNION ALL
SELECT 'Foreign Key', supplemental_log_data_fk FROM v\$database
UNION ALL
SELECT 'All Columns', supplemental_log_data_all FROM v\$database;
"
}

discover_redo_archive() {
    log_section "REDO AND ARCHIVE CONFIGURATION"
    
    log_subsection "Redo Log Groups"
    run_sql "SELECT group#, thread#, sequence#, bytes/1024/1024 AS size_mb, members, status FROM v\$log ORDER BY group#;"
    
    log_subsection "Redo Log Members"
    run_sql "SELECT group#, member, type, status FROM v\$logfile ORDER BY group#;"
    
    log_subsection "Archive Log Mode"
    run_sql "SELECT log_mode FROM v\$database;"
    
    log_subsection "Archive Destinations"
    run_sql "SELECT dest_id, dest_name, status, target, destination FROM v\$archive_dest WHERE status = 'VALID' OR destination IS NOT NULL;"
    
    log_subsection "Archive Log History (Last 24 Hours)"
    run_sql "SELECT thread#, sequence#, first_time, next_time, archived, status FROM v\$archived_log WHERE first_time > SYSDATE - 1 ORDER BY sequence# DESC FETCH FIRST 20 ROWS ONLY;" 2>/dev/null || \
    run_sql "SELECT * FROM (SELECT thread#, sequence#, first_time, next_time, archived, status FROM v\$archived_log WHERE first_time > SYSDATE - 1 ORDER BY sequence# DESC) WHERE ROWNUM <= 20;"
}

discover_network_config() {
    log_section "NETWORK CONFIGURATION"
    
    log_subsection "Listener Status"
    if [ -n "${ORACLE_HOME:-}" ]; then
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            ORACLE_HOME="$ORACLE_HOME" "$ORACLE_HOME/bin/lsnrctl" status 2>/dev/null || echo "Unable to get listener status"
        else
            sudo -u "$ORACLE_USER" ORACLE_HOME="$ORACLE_HOME" "$ORACLE_HOME/bin/lsnrctl" status 2>/dev/null || echo "Unable to get listener status"
        fi
    else
        echo "ORACLE_HOME not set"
    fi
    
    log_subsection "tnsnames.ora"
    local tns_file="${ORACLE_HOME}/network/admin/tnsnames.ora"
    if [ -f "$tns_file" ]; then
        cat "$tns_file"
    else
        echo "tnsnames.ora not found at $tns_file"
        # Try TNS_ADMIN location
        if [ -n "${TNS_ADMIN:-}" ] && [ -f "${TNS_ADMIN}/tnsnames.ora" ]; then
            echo "Found at TNS_ADMIN: ${TNS_ADMIN}/tnsnames.ora"
            cat "${TNS_ADMIN}/tnsnames.ora"
        fi
    fi
    
    log_subsection "sqlnet.ora"
    local sqlnet_file="${ORACLE_HOME}/network/admin/sqlnet.ora"
    if [ -f "$sqlnet_file" ]; then
        cat "$sqlnet_file"
    else
        echo "sqlnet.ora not found at $sqlnet_file"
    fi
    
    log_subsection "listener.ora"
    local listener_file="${ORACLE_HOME}/network/admin/listener.ora"
    if [ -f "$listener_file" ]; then
        cat "$listener_file"
    else
        echo "listener.ora not found at $listener_file"
    fi
}

discover_authentication() {
    log_section "AUTHENTICATION CONFIGURATION"
    
    log_subsection "Password File Location"
    run_sql "SELECT value FROM v\$parameter WHERE name = 'remote_login_passwordfile';"
    
    # Find password file
    echo ""
    echo "Password file search:"
    if [ -n "${ORACLE_HOME:-}" ]; then
        ls -la "$ORACLE_HOME/dbs/orapw"* 2>/dev/null || echo "No password file found in $ORACLE_HOME/dbs/"
    fi
    
    log_subsection "SSH Directory Contents"
    local oracle_home_dir
    oracle_home_dir=$(eval echo ~$ORACLE_USER 2>/dev/null)
    if [ -n "$oracle_home_dir" ] && [ -d "$oracle_home_dir/.ssh" ]; then
        echo "Contents of $oracle_home_dir/.ssh:"
        ls -la "$oracle_home_dir/.ssh/" 2>/dev/null || sudo ls -la "$oracle_home_dir/.ssh/" 2>/dev/null || echo "Unable to list SSH directory"
    else
        echo "SSH directory not found for $ORACLE_USER user"
    fi
}

discover_dataguard() {
    log_section "DATA GUARD CONFIGURATION"
    
    log_subsection "Data Guard Status"
    run_sql "SELECT database_role, protection_mode, protection_level, switchover_status FROM v\$database;"
    
    log_subsection "Standby File Management"
    run_sql "SELECT name, value FROM v\$parameter WHERE name LIKE 'standby%' OR name LIKE '%standby%';"
    
    log_subsection "Log Archive Dest Parameters"
    run_sql "SELECT name, value FROM v\$parameter WHERE name LIKE 'log_archive_dest%' AND value IS NOT NULL;"
    
    log_subsection "DG Broker Configuration"
    run_sql "SELECT name, value FROM v\$parameter WHERE name = 'dg_broker_start';"
}

discover_schemas() {
    log_section "SCHEMA INFORMATION"
    
    log_subsection "Schema Sizes (Non-System, > 100MB)"
    run_sql "
SELECT owner, 
       ROUND(SUM(bytes)/1024/1024, 2) AS size_mb,
       COUNT(*) AS segment_count
FROM dba_segments
WHERE owner NOT IN ('SYS', 'SYSTEM', 'OUTLN', 'DIP', 'ORACLE_OCM', 'DBSNMP', 
                    'APPQOSSYS', 'WMSYS', 'EXFSYS', 'CTXSYS', 'XDB', 'ANONYMOUS',
                    'ORDSYS', 'ORDDATA', 'ORDPLUGINS', 'SI_INFORMTN_SCHEMA', 'MDSYS',
                    'OLAPSYS', 'MDDATA', 'SPATIAL_WFS_ADMIN_USR', 'SPATIAL_CSW_ADMIN_USR',
                    'SYSMAN', 'MGMT_VIEW', 'APEX_030200', 'APEX_PUBLIC_USER', 'FLOWS_FILES',
                    'OWBSYS', 'OWBSYS_AUDIT', 'SCOTT')
GROUP BY owner
HAVING SUM(bytes)/1024/1024 > 100
ORDER BY size_mb DESC;
"
    
    log_subsection "Invalid Objects by Owner and Type"
    run_sql "
SELECT owner, object_type, COUNT(*) AS invalid_count
FROM dba_objects
WHERE status = 'INVALID'
GROUP BY owner, object_type
ORDER BY owner, invalid_count DESC;
"
}

# =============================================================================
# ADDITIONAL DISCOVERY (Project-Specific Requirements)
# =============================================================================

discover_tablespace_autoextend() {
    log_section "TABLESPACE AUTOEXTEND SETTINGS"
    
    run_sql "
SELECT tablespace_name, file_name, 
       ROUND(bytes/1024/1024, 2) AS size_mb,
       ROUND(maxbytes/1024/1024, 2) AS maxsize_mb,
       autoextensible,
       ROUND(increment_by * (SELECT value FROM v\$parameter WHERE name = 'db_block_size') / 1024 / 1024, 2) AS increment_mb
FROM dba_data_files
ORDER BY tablespace_name, file_name;
"
    
    log_subsection "Temp Files Autoextend"
    run_sql "
SELECT tablespace_name, file_name,
       ROUND(bytes/1024/1024, 2) AS size_mb,
       ROUND(maxbytes/1024/1024, 2) AS maxsize_mb,
       autoextensible
FROM dba_temp_files
ORDER BY tablespace_name;
"
}

discover_backup_config() {
    log_section "BACKUP SCHEDULE AND RETENTION"
    
    log_subsection "RMAN Configuration"
    run_sql "SELECT name, value FROM v\$rman_configuration ORDER BY name;"
    
    log_subsection "Recent Backup History"
    run_sql "
SELECT start_time, end_time, input_type, status, 
       ROUND(input_bytes/1024/1024/1024, 2) AS input_gb,
       ROUND(output_bytes/1024/1024/1024, 2) AS output_gb
FROM v\$rman_backup_job_details
WHERE start_time > SYSDATE - 7
ORDER BY start_time DESC;
"
    
    log_subsection "Controlfile Autobackup"
    run_sql "SELECT value FROM v\$rman_configuration WHERE name = 'CONTROLFILE AUTOBACKUP';"
}

discover_database_links() {
    log_section "DATABASE LINKS"
    
    run_sql "
SELECT owner, db_link, username, host, created
FROM dba_db_links
ORDER BY owner, db_link;
"
}

discover_mview_schedules() {
    log_section "MATERIALIZED VIEW REFRESH SCHEDULES"
    
    run_sql "
SELECT owner, mview_name, refresh_mode, refresh_method,
       last_refresh_type, last_refresh_date,
       next_date AS next_refresh
FROM dba_mviews m
LEFT JOIN dba_jobs j ON m.owner = j.schema_user AND j.what LIKE '%' || m.mview_name || '%'
WHERE owner NOT IN ('SYS', 'SYSTEM')
ORDER BY owner, mview_name;
"
    
    log_subsection "Materialized View Logs"
    run_sql "
SELECT log_owner, master, log_table, rowids, primary_key, sequence, include_new_values
FROM dba_mview_logs
ORDER BY log_owner, master;
"
}

discover_scheduler_jobs() {
    log_section "SCHEDULER JOBS (May Need Reconfiguration)"
    
    run_sql "
SELECT owner, job_name, job_type, enabled, state, 
       repeat_interval, last_start_date, next_run_date
FROM dba_scheduler_jobs
WHERE owner NOT IN ('SYS', 'SYSTEM', 'ORACLE_OCM', 'EXFSYS')
ORDER BY owner, job_name;
"
    
    log_subsection "Scheduler Job Details"
    run_sql "
SELECT owner, job_name, program_name, job_action
FROM dba_scheduler_jobs
WHERE owner NOT IN ('SYS', 'SYSTEM', 'ORACLE_OCM', 'EXFSYS')
ORDER BY owner, job_name;
"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         ZDM SOURCE DATABASE DISCOVERY - PRODDB MIGRATION                  ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Timestamp: $(date)"
    echo "Output File: $OUTPUT_FILE"
    echo "JSON File: $JSON_FILE"
    echo ""
    
    # Detect Oracle environment
    detect_oracle_env
    
    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        log_error "Failed to detect Oracle environment. Set ORACLE_HOME and ORACLE_SID manually."
        exit 1
    fi
    
    log_info "Using ORACLE_HOME: $ORACLE_HOME"
    log_info "Using ORACLE_SID: $ORACLE_SID"
    log_info "Running SQL commands as user: $ORACLE_USER"
    echo ""
    
    # Initialize JSON output
    init_json
    add_json "oracle_home" "$ORACLE_HOME"
    add_json "oracle_sid" "$ORACLE_SID"
    
    # Run discovery (all output tee'd to both console and file)
    {
        echo "ZDM SOURCE DATABASE DISCOVERY"
        echo "Project: PRODDB Migration to Oracle Database@Azure"
        echo "Source: proddb01.corp.example.com"
        echo "Timestamp: $(date)"
        echo "ORACLE_HOME: $ORACLE_HOME"
        echo "ORACLE_SID: $ORACLE_SID"
        
        # Standard discovery
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
        discover_schemas
        
        # Additional project-specific discovery
        discover_tablespace_autoextend
        discover_backup_config
        discover_database_links
        discover_mview_schedules
        discover_scheduler_jobs
        
        echo ""
        log_section "DISCOVERY COMPLETE"
        echo "Output saved to: $OUTPUT_FILE"
        echo "JSON saved to: $JSON_FILE"
        
    } 2>&1 | tee "$OUTPUT_FILE"
    
    # Get key values for JSON
    local db_name db_unique_name log_mode cdb_status tde_status
    db_name=$(run_sql_value "SELECT name FROM v\$database;")
    db_unique_name=$(run_sql_value "SELECT db_unique_name FROM v\$database;")
    log_mode=$(run_sql_value "SELECT log_mode FROM v\$database;")
    cdb_status=$(run_sql_value "SELECT cdb FROM v\$database;")
    tde_status=$(run_sql_value "SELECT status FROM v\$encryption_wallet WHERE ROWNUM = 1;")
    
    add_json "db_name" "${db_name:-UNKNOWN}"
    add_json "db_unique_name" "${db_unique_name:-UNKNOWN}"
    add_json "log_mode" "${log_mode:-UNKNOWN}"
    add_json "cdb_enabled" "${cdb_status:-UNKNOWN}"
    add_json "tde_status" "${tde_status:-NOT_CONFIGURED}"
    add_json "discovery_status" "COMPLETED" "true"
    finalize_json
    
    echo ""
    log_info "Discovery completed successfully!"
    echo ""
}

# Run main function
main "$@"
