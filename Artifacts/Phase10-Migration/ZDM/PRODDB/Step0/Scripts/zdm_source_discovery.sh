#!/bin/bash
################################################################################
# ZDM Source Database Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# Source: proddb01.corp.example.com
#
# Purpose: Discover source database configuration and environment details
# Execution: Run via SSH as ADMIN_USER (oracle) with sudo privileges
################################################################################

# Configuration - User defaults
ORACLE_USER="${ORACLE_USER:-oracle}"

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Timestamp for output files
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname -f 2>/dev/null || hostname)

# Output files in current working directory
OUTPUT_TXT="./zdm_source_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
OUTPUT_JSON="./zdm_source_discovery_${HOSTNAME}_${TIMESTAMP}.json"

# Initialize JSON output
json_data="{}"

################################################################################
# Utility Functions
################################################################################

log_section() {
    local title="$1"
    echo "" | tee -a "$OUTPUT_TXT"
    echo "========================================" | tee -a "$OUTPUT_TXT"
    echo "$title" | tee -a "$OUTPUT_TXT"
    echo "========================================" | tee -a "$OUTPUT_TXT"
    echo -e "${BLUE}▶ $title${NC}"
}

log_info() {
    echo "$1" | tee -a "$OUTPUT_TXT"
    echo -e "${GREEN}  $1${NC}"
}

log_warn() {
    echo "WARNING: $1" | tee -a "$OUTPUT_TXT"
    echo -e "${YELLOW}  ⚠ WARNING: $1${NC}"
}

log_error() {
    echo "ERROR: $1" | tee -a "$OUTPUT_TXT"
    echo -e "${RED}  ✗ ERROR: $1${NC}"
}

add_json_field() {
    local key="$1"
    local value="$2"
    # Escape quotes in value
    value="${value//\"/\\\"}"
    json_data=$(echo "$json_data" | jq --arg k "$key" --arg v "$value" '. + {($k): $v}')
}

################################################################################
# Oracle Environment Auto-Detection
################################################################################

detect_oracle_env() {
    log_section "Oracle Environment Detection"
    
    # If already set, use existing values
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        log_info "Using existing ORACLE_HOME: $ORACLE_HOME"
        log_info "Using existing ORACLE_SID: $ORACLE_SID"
        return 0
    fi
    
    # Method 1: Parse /etc/oratab (most reliable)
    if [ -f /etc/oratab ]; then
        log_info "Checking /etc/oratab..."
        local oratab_entry
        if [ -n "${ORACLE_SID:-}" ]; then
            oratab_entry=$(grep "^${ORACLE_SID}:" /etc/oratab 2>/dev/null | head -1)
        else
            oratab_entry=$(grep -v '^#' /etc/oratab | grep -v '^$' | head -1)
        fi
        if [ -n "$oratab_entry" ]; then
            export ORACLE_SID="${ORACLE_SID:-$(echo "$oratab_entry" | cut -d: -f1)}"
            export ORACLE_HOME="${ORACLE_HOME:-$(echo "$oratab_entry" | cut -d: -f2)}"
            log_info "Found from /etc/oratab - SID: $ORACLE_SID, HOME: $ORACLE_HOME"
        fi
    fi
    
    # Method 2: Check running pmon process
    if [ -z "${ORACLE_SID:-}" ]; then
        log_info "Checking running pmon processes..."
        local pmon_sid
        pmon_sid=$(ps -ef | grep 'ora_pmon_' | grep -v grep | head -1 | sed 's/.*ora_pmon_//')
        if [ -n "$pmon_sid" ]; then
            export ORACLE_SID="$pmon_sid"
            log_info "Found from pmon process - SID: $ORACLE_SID"
        fi
    fi
    
    # Method 3: Search common Oracle installation paths
    if [ -z "${ORACLE_HOME:-}" ]; then
        log_info "Searching common Oracle installation paths..."
        for path in /u01/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1 /oracle/product/*/dbhome_1; do
            if [ -d "$path" ] && [ -f "$path/bin/sqlplus" ]; then
                export ORACLE_HOME="$path"
                log_info "Found ORACLE_HOME: $ORACLE_HOME"
                break
            fi
        done
    fi
    
    # Apply explicit overrides if provided (highest priority)
    [ -n "${ORACLE_HOME_OVERRIDE:-}" ] && export ORACLE_HOME="$ORACLE_HOME_OVERRIDE"
    [ -n "${ORACLE_SID_OVERRIDE:-}" ] && export ORACLE_SID="$ORACLE_SID_OVERRIDE"
    
    # Set ORACLE_BASE if not already set
    if [ -n "${ORACLE_HOME:-}" ] && [ -z "${ORACLE_BASE:-}" ]; then
        export ORACLE_BASE=$(dirname $(dirname "$ORACLE_HOME"))
    fi
    
    # Verify detection
    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        log_error "Failed to detect Oracle environment"
        log_error "Please set ORACLE_HOME and ORACLE_SID environment variables"
        return 1
    fi
    
    log_info "✓ Oracle environment detected successfully"
    log_info "  ORACLE_HOME: $ORACLE_HOME"
    log_info "  ORACLE_SID: $ORACLE_SID"
    log_info "  ORACLE_BASE: ${ORACLE_BASE:-not set}"
    
    return 0
}

################################################################################
# SQL Execution Function
################################################################################

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
            echo "$sql_script" | $sqlplus_cmd 2>&1
        else
            echo "$sql_script" | sudo -u "$ORACLE_USER" -E ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd 2>&1
        fi
    else
        echo "ERROR: ORACLE_HOME or ORACLE_SID not set"
        return 1
    fi
}

run_sql_value() {
    local sql_query="$1"
    local result
    result=$(run_sql "$sql_query" | grep -v "^$" | tail -1)
    echo "$result"
}

################################################################################
# Main Discovery Functions
################################################################################

gather_os_info() {
    log_section "Operating System Information"
    
    log_info "Hostname: $(hostname -f 2>/dev/null || hostname)"
    add_json_field "hostname" "$(hostname -f 2>/dev/null || hostname)"
    
    log_info "IP Addresses:"
    ip addr show | grep 'inet ' | awk '{print "  " $2}' | tee -a "$OUTPUT_TXT"
    
    log_info "OS Version:"
    if [ -f /etc/os-release ]; then
        cat /etc/os-release | tee -a "$OUTPUT_TXT"
        os_version=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
        add_json_field "os_version" "$os_version"
    elif [ -f /etc/redhat-release ]; then
        cat /etc/redhat-release | tee -a "$OUTPUT_TXT"
        add_json_field "os_version" "$(cat /etc/redhat-release)"
    fi
    
    log_info "Disk Space:"
    df -h | tee -a "$OUTPUT_TXT"
    
    log_info "Memory:"
    free -h | tee -a "$OUTPUT_TXT"
}

gather_oracle_info() {
    log_section "Oracle Environment"
    
    log_info "ORACLE_HOME: ${ORACLE_HOME:-not set}"
    log_info "ORACLE_SID: ${ORACLE_SID:-not set}"
    log_info "ORACLE_BASE: ${ORACLE_BASE:-not set}"
    
    add_json_field "oracle_home" "${ORACLE_HOME:-}"
    add_json_field "oracle_sid" "${ORACLE_SID:-}"
    add_json_field "oracle_base" "${ORACLE_BASE:-}"
    
    if [ -n "${ORACLE_HOME:-}" ] && [ -f "$ORACLE_HOME/bin/sqlplus" ]; then
        log_info "Oracle Version:"
        local oracle_version
        oracle_version=$(run_sql_value "SELECT banner FROM v\$version WHERE ROWNUM = 1;")
        log_info "$oracle_version"
        add_json_field "oracle_version" "$oracle_version"
    fi
}

gather_database_config() {
    log_section "Database Configuration"
    
    # Database name and DBID
    local db_name=$(run_sql_value "SELECT name FROM v\$database;")
    local db_unique_name=$(run_sql_value "SELECT db_unique_name FROM v\$database;")
    local dbid=$(run_sql_value "SELECT dbid FROM v\$database;")
    
    log_info "Database Name: $db_name"
    log_info "DB Unique Name: $db_unique_name"
    log_info "DBID: $dbid"
    
    add_json_field "db_name" "$db_name"
    add_json_field "db_unique_name" "$db_unique_name"
    add_json_field "dbid" "$dbid"
    
    # Database role and open mode
    local db_role=$(run_sql_value "SELECT database_role FROM v\$database;")
    local open_mode=$(run_sql_value "SELECT open_mode FROM v\$database;")
    
    log_info "Database Role: $db_role"
    log_info "Open Mode: $open_mode"
    
    add_json_field "db_role" "$db_role"
    add_json_field "open_mode" "$open_mode"
    
    # Log mode and force logging
    local log_mode=$(run_sql_value "SELECT log_mode FROM v\$database;")
    local force_logging=$(run_sql_value "SELECT force_logging FROM v\$database;")
    
    log_info "Log Mode: $log_mode"
    log_info "Force Logging: $force_logging"
    
    add_json_field "log_mode" "$log_mode"
    add_json_field "force_logging" "$force_logging"
    
    # Character sets
    local charset=$(run_sql_value "SELECT value FROM nls_database_parameters WHERE parameter = 'NLS_CHARACTERSET';")
    local ncharset=$(run_sql_value "SELECT value FROM nls_database_parameters WHERE parameter = 'NLS_NCHAR_CHARACTERSET';")
    
    log_info "Character Set: $charset"
    log_info "National Character Set: $ncharset"
    
    add_json_field "character_set" "$charset"
    add_json_field "nchar_set" "$ncharset"
}

gather_database_size() {
    log_section "Database Size"
    
    log_info "Data Files:"
    run_sql "SELECT ROUND(SUM(bytes)/1024/1024/1024, 2) || ' GB' AS total_datafile_size FROM dba_data_files;" | tee -a "$OUTPUT_TXT"
    
    log_info "Temp Files:"
    run_sql "SELECT ROUND(SUM(bytes)/1024/1024/1024, 2) || ' GB' AS total_tempfile_size FROM dba_temp_files;" | tee -a "$OUTPUT_TXT"
    
    log_info "Total Database Size:"
    run_sql "SELECT ROUND((SELECT SUM(bytes) FROM dba_data_files)/1024/1024/1024 + (SELECT SUM(bytes) FROM dba_temp_files)/1024/1024/1024, 2) || ' GB' AS total_db_size FROM dual;" | tee -a "$OUTPUT_TXT"
}

gather_cdb_info() {
    log_section "Container Database Information"
    
    local cdb=$(run_sql_value "SELECT cdb FROM v\$database;")
    log_info "CDB: $cdb"
    add_json_field "cdb" "$cdb"
    
    if [ "$cdb" = "YES" ]; then
        log_info "PDBs:"
        run_sql "SELECT name, open_mode, restricted FROM v\$pdbs ORDER BY name;" | tee -a "$OUTPUT_TXT"
    fi
}

gather_tde_info() {
    log_section "TDE Configuration"
    
    # TDE wallet status
    log_info "Wallet Status:"
    run_sql "SELECT * FROM v\$encryption_wallet;" | tee -a "$OUTPUT_TXT"
    
    # Encrypted tablespaces
    log_info "Encrypted Tablespaces:"
    run_sql "SELECT tablespace_name, encrypted FROM dba_tablespaces WHERE encrypted = 'YES';" | tee -a "$OUTPUT_TXT"
    
    # Check for TDE encryption
    local tde_status=$(run_sql_value "SELECT COUNT(*) FROM v\$encrypted_tablespaces;")
    if [ "$tde_status" -gt 0 ]; then
        log_info "TDE is ENABLED"
        add_json_field "tde_enabled" "true"
    else
        log_info "TDE is NOT enabled"
        add_json_field "tde_enabled" "false"
    fi
}

gather_supplemental_logging() {
    log_section "Supplemental Logging"
    
    log_info "Supplemental Logging Status:"
    run_sql "SELECT supplemental_log_data_min, supplemental_log_data_pk, supplemental_log_data_ui, supplemental_log_data_fk, supplemental_log_data_all FROM v\$database;" | tee -a "$OUTPUT_TXT"
}

gather_redo_archive_config() {
    log_section "Redo and Archive Configuration"
    
    log_info "Redo Log Groups:"
    run_sql "SELECT group#, thread#, sequence#, bytes/1024/1024 AS size_mb, members, status FROM v\$log ORDER BY group#;" | tee -a "$OUTPUT_TXT"
    
    log_info "Redo Log Members:"
    run_sql "SELECT group#, member, type, status FROM v\$logfile ORDER BY group#, member;" | tee -a "$OUTPUT_TXT"
    
    log_info "Archive Log Destinations:"
    run_sql "SELECT dest_id, destination, status, binding FROM v\$archive_dest WHERE status != 'INACTIVE' ORDER BY dest_id;" | tee -a "$OUTPUT_TXT"
}

gather_network_config() {
    log_section "Network Configuration"
    
    # Listener status
    log_info "Listener Status:"
    if [ -n "${ORACLE_HOME:-}" ]; then
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            $ORACLE_HOME/bin/lsnrctl status 2>&1 | tee -a "$OUTPUT_TXT"
        else
            sudo -u "$ORACLE_USER" $ORACLE_HOME/bin/lsnrctl status 2>&1 | tee -a "$OUTPUT_TXT"
        fi
    fi
    
    # tnsnames.ora
    log_info "tnsnames.ora:"
    if [ -f "$ORACLE_HOME/network/admin/tnsnames.ora" ]; then
        cat "$ORACLE_HOME/network/admin/tnsnames.ora" | tee -a "$OUTPUT_TXT"
    else
        log_warn "tnsnames.ora not found"
    fi
    
    # sqlnet.ora
    log_info "sqlnet.ora:"
    if [ -f "$ORACLE_HOME/network/admin/sqlnet.ora" ]; then
        cat "$ORACLE_HOME/network/admin/sqlnet.ora" | tee -a "$OUTPUT_TXT"
    else
        log_warn "sqlnet.ora not found"
    fi
}

gather_data_guard_config() {
    log_section "Data Guard Configuration"
    
    log_info "Data Guard Parameters:"
    run_sql "SELECT name, value FROM v\$parameter WHERE name LIKE '%dg_%' OR name LIKE '%standby%' OR name LIKE '%log_archive%' ORDER BY name;" | tee -a "$OUTPUT_TXT"
}

gather_schema_info() {
    log_section "Schema Information"
    
    log_info "Schema Sizes (> 100MB):"
    run_sql "SELECT owner, ROUND(SUM(bytes)/1024/1024, 2) AS size_mb FROM dba_segments WHERE owner NOT IN ('SYS','SYSTEM','SYSAUX','XDB','APEX_030200','APEX_040000','APEX_040200','APPQOSSYS','AUDSYS','CTXSYS','DBSNMP','DIP','DVSYS','GSMADMIN_INTERNAL','LBACSYS','MDDATA','MDSYS','OJVMSYS','OLAPSYS','ORACLE_OCM','ORDDATA','ORDPLUGINS','ORDSYS','OUTLN','SCOTT','SI_INFORMTN_SCHEMA','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','SQLTXADMIN','SQLTXPLAIN','WMSYS','XS\$NULL') GROUP BY owner HAVING SUM(bytes)/1024/1024 > 100 ORDER BY 2 DESC;" | tee -a "$OUTPUT_TXT"
    
    log_info "Invalid Objects:"
    run_sql "SELECT owner, object_type, COUNT(*) AS count FROM dba_objects WHERE status = 'INVALID' GROUP BY owner, object_type ORDER BY owner, object_type;" | tee -a "$OUTPUT_TXT"
}

gather_tablespace_autoextend() {
    log_section "Tablespace Autoextend Settings"
    
    log_info "Tablespace Autoextend Configuration:"
    run_sql "SELECT tablespace_name, file_name, autoextensible, ROUND(bytes/1024/1024, 2) AS current_size_mb, ROUND(maxbytes/1024/1024, 2) AS max_size_mb, ROUND(increment_by * (SELECT value FROM v\$parameter WHERE name = 'db_block_size') / 1024 / 1024, 2) AS increment_mb FROM dba_data_files ORDER BY tablespace_name, file_name;" | tee -a "$OUTPUT_TXT"
}

gather_backup_config() {
    log_section "Backup Configuration"
    
    log_info "RMAN Configuration:"
    if [ -n "${ORACLE_HOME:-}" ]; then
        local rman_cmd="$ORACLE_HOME/bin/rman target /"
        local rman_script=$(cat <<EORMAN
SHOW ALL;
LIST BACKUP SUMMARY;
EXIT;
EORMAN
)
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            echo "$rman_script" | $rman_cmd 2>&1 | tee -a "$OUTPUT_TXT"
        else
            echo "$rman_script" | sudo -u "$ORACLE_USER" -E ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $rman_cmd 2>&1 | tee -a "$OUTPUT_TXT"
        fi
    fi
    
    log_info "Backup Schedule (from crontab if available):"
    if [ "$(whoami)" = "$ORACLE_USER" ]; then
        crontab -l 2>&1 | grep -i backup | tee -a "$OUTPUT_TXT" || log_info "No backup cron jobs found"
    else
        sudo -u "$ORACLE_USER" crontab -l 2>&1 | grep -i backup | tee -a "$OUTPUT_TXT" || log_info "No backup cron jobs found"
    fi
}

gather_database_links() {
    log_section "Database Links"
    
    log_info "Database Links:"
    run_sql "SELECT owner, db_link, username, host FROM dba_db_links ORDER BY owner, db_link;" | tee -a "$OUTPUT_TXT"
}

gather_materialized_views() {
    log_section "Materialized View Refresh Schedules"
    
    log_info "Materialized Views with Refresh Settings:"
    run_sql "SELECT owner, mview_name, refresh_mode, refresh_method, last_refresh_date, staleness, compile_state FROM dba_mviews WHERE owner NOT IN ('SYS','SYSTEM') ORDER BY owner, mview_name;" | tee -a "$OUTPUT_TXT"
}

gather_scheduler_jobs() {
    log_section "Scheduler Jobs"
    
    log_info "Scheduler Jobs that may need reconfiguration:"
    run_sql "SELECT owner, job_name, job_type, job_action, schedule_type, repeat_interval, enabled, state, last_start_date, next_run_date FROM dba_scheduler_jobs WHERE owner NOT IN ('SYS','ORACLE_OCM','EXFSYS','AUDSYS') ORDER BY owner, job_name;" | tee -a "$OUTPUT_TXT"
}

gather_authentication() {
    log_section "Authentication"
    
    # Password file location
    log_info "Password File:"
    if [ -n "${ORACLE_HOME:-}" ]; then
        local pwfile_dir="$ORACLE_HOME/dbs"
        if [ -d "$pwfile_dir" ]; then
            if [ "$(whoami)" = "$ORACLE_USER" ]; then
                ls -l "$pwfile_dir"/orapw* 2>&1 | tee -a "$OUTPUT_TXT"
            else
                sudo -u "$ORACLE_USER" ls -l "$pwfile_dir"/orapw* 2>&1 | tee -a "$OUTPUT_TXT"
            fi
        fi
    fi
    
    # SSH directory
    log_info "SSH Directory:"
    local oracle_home_dir
    if [ "$(whoami)" = "$ORACLE_USER" ]; then
        oracle_home_dir="$HOME"
    else
        oracle_home_dir=$(eval echo ~"$ORACLE_USER")
    fi
    
    if [ -d "$oracle_home_dir/.ssh" ]; then
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            ls -la "$oracle_home_dir/.ssh" 2>&1 | tee -a "$OUTPUT_TXT"
        else
            sudo -u "$ORACLE_USER" ls -la "$oracle_home_dir/.ssh" 2>&1 | tee -a "$OUTPUT_TXT"
        fi
    else
        log_warn "SSH directory not found for oracle user"
    fi
}

################################################################################
# Main Execution
################################################################################

main() {
    echo "========================================" | tee "$OUTPUT_TXT"
    echo "ZDM Source Database Discovery" | tee -a "$OUTPUT_TXT"
    echo "Project: PRODDB Migration to Oracle Database@Azure" | tee -a "$OUTPUT_TXT"
    echo "Timestamp: $(date)" | tee -a "$OUTPUT_TXT"
    echo "========================================" | tee -a "$OUTPUT_TXT"
    
    # Initialize JSON
    json_data=$(jq -n '{}')
    add_json_field "discovery_type" "source"
    add_json_field "timestamp" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    add_json_field "project" "PRODDB Migration to Oracle Database@Azure"
    
    # Detect Oracle environment first
    if ! detect_oracle_env; then
        log_error "Failed to detect Oracle environment. Cannot proceed with database queries."
        echo "$json_data" | jq '.' > "$OUTPUT_JSON"
        exit 1
    fi
    
    # Run all discovery functions with error handling
    gather_os_info || log_error "Failed to gather OS info"
    gather_oracle_info || log_error "Failed to gather Oracle info"
    gather_database_config || log_error "Failed to gather database config"
    gather_database_size || log_error "Failed to gather database size"
    gather_cdb_info || log_error "Failed to gather CDB info"
    gather_tde_info || log_error "Failed to gather TDE info"
    gather_supplemental_logging || log_error "Failed to gather supplemental logging"
    gather_redo_archive_config || log_error "Failed to gather redo/archive config"
    gather_network_config || log_error "Failed to gather network config"
    gather_data_guard_config || log_error "Failed to gather Data Guard config"
    gather_schema_info || log_error "Failed to gather schema info"
    gather_tablespace_autoextend || log_error "Failed to gather tablespace autoextend settings"
    gather_backup_config || log_error "Failed to gather backup configuration"
    gather_database_links || log_error "Failed to gather database links"
    gather_materialized_views || log_error "Failed to gather materialized views"
    gather_scheduler_jobs || log_error "Failed to gather scheduler jobs"
    gather_authentication || log_error "Failed to gather authentication info"
    
    # Write JSON output
    echo "$json_data" | jq '.' > "$OUTPUT_JSON"
    
    log_section "Discovery Complete"
    log_info "Text report: $OUTPUT_TXT"
    log_info "JSON summary: $OUTPUT_JSON"
    
    echo -e "\n${GREEN}✓ Source database discovery completed successfully${NC}"
}

# Run main function
main
