#!/bin/bash
#===============================================================================
# ZDM Source Database Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
#
# Purpose: Discover source database configuration for ZDM migration planning.
#          Executed via SSH as admin user, SQL commands run as oracle user.
#
# Usage: ./zdm_source_discovery.sh
#
# Output:
#   - zdm_source_discovery_<hostname>_<timestamp>.txt (human-readable report)
#   - zdm_source_discovery_<hostname>_<timestamp>.json (machine-parseable)
#===============================================================================

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

# Output files (current working directory)
TEXT_REPORT="./zdm_source_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
JSON_REPORT="./zdm_source_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

# Default oracle user if not set
ORACLE_USER="${ORACLE_USER:-oracle}"

#===============================================================================
# ENVIRONMENT DETECTION
#===============================================================================

detect_oracle_env() {
    # If already set, use existing values
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        return 0
    fi
    
    # Method 1: Parse /etc/oratab (most reliable)
    if [ -f /etc/oratab ]; then
        local oratab_entry
        if [ -n "${ORACLE_SID:-}" ]; then
            oratab_entry=$(grep "^${ORACLE_SID}:" /etc/oratab 2>/dev/null | head -1)
        else
            oratab_entry=$(grep -v '^#' /etc/oratab | grep -v '^$' | grep -v '^*' | head -1)
        fi
        if [ -n "$oratab_entry" ]; then
            export ORACLE_SID="${ORACLE_SID:-$(echo "$oratab_entry" | cut -d: -f1)}"
            export ORACLE_HOME="${ORACLE_HOME:-$(echo "$oratab_entry" | cut -d: -f2)}"
        fi
    fi
    
    # Method 2: Check running pmon process
    if [ -z "${ORACLE_SID:-}" ]; then
        local pmon_sid
        pmon_sid=$(ps -ef | grep 'ora_pmon_' | grep -v grep | head -1 | sed 's/.*ora_pmon_//')
        [ -n "$pmon_sid" ] && export ORACLE_SID="$pmon_sid"
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
    
    # Method 4: Check oraenv/coraenv
    if [ -z "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        [ -f /usr/local/bin/oraenv ] && . /usr/local/bin/oraenv <<< "$ORACLE_SID" 2>/dev/null
    fi
    
    # Set ORACLE_BASE if not set
    if [ -z "${ORACLE_BASE:-}" ] && [ -n "${ORACLE_HOME:-}" ]; then
        export ORACLE_BASE=$(dirname $(dirname "$ORACLE_HOME"))
    fi
}

# Apply explicit overrides if provided (highest priority)
[ -n "${ORACLE_HOME_OVERRIDE:-}" ] && export ORACLE_HOME="$ORACLE_HOME_OVERRIDE"
[ -n "${ORACLE_SID_OVERRIDE:-}" ] && export ORACLE_SID="$ORACLE_SID_OVERRIDE"

# Detect Oracle environment
detect_oracle_env

#===============================================================================
# SQL EXECUTION FUNCTIONS
#===============================================================================

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
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            echo "$sql_script" | ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd 2>/dev/null | tr -d '[:space:]'
        else
            echo "$sql_script" | sudo -u "$ORACLE_USER" ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd 2>/dev/null | tr -d '[:space:]'
        fi
    else
        echo "ERROR"
        return 1
    fi
}

#===============================================================================
# OUTPUT FUNCTIONS
#===============================================================================

print_header() {
    local title="$1"
    echo "" >> "$TEXT_REPORT"
    echo "===============================================================================" >> "$TEXT_REPORT"
    echo "  $title" >> "$TEXT_REPORT"
    echo "===============================================================================" >> "$TEXT_REPORT"
    echo -e "${BLUE}=== $title ===${NC}"
}

print_section() {
    local title="$1"
    echo "" >> "$TEXT_REPORT"
    echo "--- $title ---" >> "$TEXT_REPORT"
    echo -e "${GREEN}--- $title ---${NC}"
}

print_info() {
    local label="$1"
    local value="$2"
    printf "%-30s: %s\n" "$label" "$value" >> "$TEXT_REPORT"
    printf "${CYAN}%-30s${NC}: %s\n" "$label" "$value"
}

print_output() {
    local output="$1"
    echo "$output" >> "$TEXT_REPORT"
    echo "$output"
}

#===============================================================================
# JSON BUILDER
#===============================================================================

declare -A JSON_DATA

add_json() {
    local key="$1"
    local value="$2"
    JSON_DATA["$key"]="$value"
}

add_json_array() {
    local key="$1"
    shift
    local items=("$@")
    local json_array="["
    local first=true
    for item in "${items[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            json_array+=","
        fi
        json_array+="\"$item\""
    done
    json_array+="]"
    JSON_DATA["$key"]="$json_array"
}

write_json() {
    echo "{" > "$JSON_REPORT"
    local first=true
    for key in "${!JSON_DATA[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> "$JSON_REPORT"
        fi
        local value="${JSON_DATA[$key]}"
        # Check if value is already JSON (array or object)
        if [[ "$value" =~ ^\[.*\]$ ]] || [[ "$value" =~ ^\{.*\}$ ]]; then
            printf '  "%s": %s' "$key" "$value" >> "$JSON_REPORT"
        else
            printf '  "%s": "%s"' "$key" "$value" >> "$JSON_REPORT"
        fi
    done
    echo "" >> "$JSON_REPORT"
    echo "}" >> "$JSON_REPORT"
}

#===============================================================================
# DISCOVERY FUNCTIONS
#===============================================================================

discover_os_info() {
    print_header "OS INFORMATION"
    
    local hostname_full=$(hostname -f 2>/dev/null || hostname)
    local hostname_short=$(hostname -s)
    local ip_addresses=$(hostname -I 2>/dev/null || ip addr show | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | tr '\n' ' ')
    local os_version=$(cat /etc/os-release 2>/dev/null | grep "PRETTY_NAME" | cut -d'"' -f2 || uname -a)
    local kernel_version=$(uname -r)
    
    print_info "Hostname (Full)" "$hostname_full"
    print_info "Hostname (Short)" "$hostname_short"
    print_info "IP Addresses" "$ip_addresses"
    print_info "OS Version" "$os_version"
    print_info "Kernel Version" "$kernel_version"
    
    add_json "hostname_full" "$hostname_full"
    add_json "hostname_short" "$hostname_short"
    add_json "ip_addresses" "$ip_addresses"
    add_json "os_version" "$os_version"
    add_json "kernel_version" "$kernel_version"
    
    print_section "Disk Space"
    local disk_info=$(df -h 2>/dev/null | grep -E '^/dev|^Filesystem')
    print_output "$disk_info"
}

discover_oracle_env() {
    print_header "ORACLE ENVIRONMENT"
    
    print_info "ORACLE_HOME" "${ORACLE_HOME:-NOT SET}"
    print_info "ORACLE_SID" "${ORACLE_SID:-NOT SET}"
    print_info "ORACLE_BASE" "${ORACLE_BASE:-NOT SET}"
    
    add_json "oracle_home" "${ORACLE_HOME:-NOT SET}"
    add_json "oracle_sid" "${ORACLE_SID:-NOT SET}"
    add_json "oracle_base" "${ORACLE_BASE:-NOT SET}"
    
    if [ -n "${ORACLE_HOME:-}" ]; then
        local oracle_version=$($ORACLE_HOME/bin/sqlplus -v 2>/dev/null | grep -i "Release" | head -1)
        print_info "Oracle Version" "$oracle_version"
        add_json "oracle_version" "$oracle_version"
    fi
    
    print_section "/etc/oratab Contents"
    if [ -f /etc/oratab ]; then
        local oratab_content=$(grep -v '^#' /etc/oratab | grep -v '^$')
        print_output "$oratab_content"
    else
        print_output "File not found"
    fi
}

discover_database_config() {
    print_header "DATABASE CONFIGURATION"
    
    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        print_output "ERROR: Oracle environment not configured"
        return 1
    fi
    
    local db_name=$(run_sql_value "SELECT name FROM v\$database;")
    local db_unique_name=$(run_sql_value "SELECT db_unique_name FROM v\$database;")
    local dbid=$(run_sql_value "SELECT dbid FROM v\$database;")
    local db_role=$(run_sql_value "SELECT database_role FROM v\$database;")
    local open_mode=$(run_sql_value "SELECT open_mode FROM v\$database;")
    local log_mode=$(run_sql_value "SELECT log_mode FROM v\$database;")
    local force_logging=$(run_sql_value "SELECT force_logging FROM v\$database;")
    local platform=$(run_sql_value "SELECT platform_name FROM v\$database;")
    
    print_info "Database Name" "$db_name"
    print_info "DB Unique Name" "$db_unique_name"
    print_info "DBID" "$dbid"
    print_info "Database Role" "$db_role"
    print_info "Open Mode" "$open_mode"
    print_info "Log Mode" "$log_mode"
    print_info "Force Logging" "$force_logging"
    print_info "Platform" "$platform"
    
    add_json "db_name" "$db_name"
    add_json "db_unique_name" "$db_unique_name"
    add_json "dbid" "$dbid"
    add_json "database_role" "$db_role"
    add_json "open_mode" "$open_mode"
    add_json "log_mode" "$log_mode"
    add_json "force_logging" "$force_logging"
    add_json "platform" "$platform"
    
    print_section "Database Size"
    run_sql "
SELECT 'Data Files' as type, ROUND(SUM(bytes)/1024/1024/1024, 2) as size_gb FROM dba_data_files
UNION ALL
SELECT 'Temp Files', ROUND(SUM(bytes)/1024/1024/1024, 2) FROM dba_temp_files
UNION ALL
SELECT 'Redo Logs', ROUND(SUM(bytes)/1024/1024/1024, 2) FROM v\$log;
" >> "$TEXT_REPORT"
    
    local total_size=$(run_sql_value "SELECT ROUND(SUM(bytes)/1024/1024/1024, 2) FROM dba_data_files;")
    add_json "database_size_gb" "$total_size"
    
    print_section "Character Set"
    local charset=$(run_sql_value "SELECT value FROM nls_database_parameters WHERE parameter = 'NLS_CHARACTERSET';")
    local ncharset=$(run_sql_value "SELECT value FROM nls_database_parameters WHERE parameter = 'NLS_NCHAR_CHARACTERSET';")
    print_info "Character Set" "$charset"
    print_info "National Character Set" "$ncharset"
    add_json "character_set" "$charset"
    add_json "nchar_character_set" "$ncharset"
}

discover_cdb_pdb() {
    print_header "CONTAINER DATABASE (CDB/PDB)"
    
    local cdb_status=$(run_sql_value "SELECT CDB FROM v\$database;")
    print_info "CDB Status" "$cdb_status"
    add_json "is_cdb" "$cdb_status"
    
    if [ "$cdb_status" = "YES" ]; then
        print_section "PDB Information"
        run_sql "
SELECT con_id, name, open_mode, restricted, total_size/1024/1024 as size_mb
FROM v\$pdbs
ORDER BY con_id;
" >> "$TEXT_REPORT"
        
        local pdb_list=$(run_sql_value "SELECT LISTAGG(name, ',') WITHIN GROUP (ORDER BY con_id) FROM v\$pdbs WHERE name != 'PDB\$SEED';")
        add_json "pdb_list" "$pdb_list"
    fi
}

discover_tde_config() {
    print_header "TDE CONFIGURATION"
    
    local tde_enabled=$(run_sql_value "SELECT COUNT(*) FROM v\$encryption_wallet WHERE status = 'OPEN';")
    
    if [ "$tde_enabled" -gt 0 ] 2>/dev/null; then
        print_info "TDE Status" "ENABLED"
        add_json "tde_enabled" "true"
        
        print_section "Wallet Information"
        run_sql "SELECT * FROM v\$encryption_wallet;" >> "$TEXT_REPORT"
        
        local wallet_type=$(run_sql_value "SELECT wallet_type FROM v\$encryption_wallet WHERE rownum = 1;")
        local wallet_location=$(run_sql_value "SELECT wrl_parameter FROM v\$encryption_wallet WHERE rownum = 1;")
        print_info "Wallet Type" "$wallet_type"
        print_info "Wallet Location" "$wallet_location"
        add_json "wallet_type" "$wallet_type"
        add_json "wallet_location" "$wallet_location"
        
        print_section "Encrypted Tablespaces"
        run_sql "
SELECT tablespace_name, encrypted, status
FROM dba_tablespaces
WHERE encrypted = 'YES';
" >> "$TEXT_REPORT"
        
        local encrypted_ts=$(run_sql_value "SELECT LISTAGG(tablespace_name, ',') WITHIN GROUP (ORDER BY tablespace_name) FROM dba_tablespaces WHERE encrypted = 'YES';")
        add_json "encrypted_tablespaces" "$encrypted_ts"
    else
        print_info "TDE Status" "NOT ENABLED"
        add_json "tde_enabled" "false"
    fi
}

discover_supplemental_logging() {
    print_header "SUPPLEMENTAL LOGGING"
    
    local supp_log_min=$(run_sql_value "SELECT supplemental_log_data_min FROM v\$database;")
    local supp_log_pk=$(run_sql_value "SELECT supplemental_log_data_pk FROM v\$database;")
    local supp_log_ui=$(run_sql_value "SELECT supplemental_log_data_ui FROM v\$database;")
    local supp_log_fk=$(run_sql_value "SELECT supplemental_log_data_fk FROM v\$database;")
    local supp_log_all=$(run_sql_value "SELECT supplemental_log_data_all FROM v\$database;")
    
    print_info "Minimal" "$supp_log_min"
    print_info "Primary Key" "$supp_log_pk"
    print_info "Unique Index" "$supp_log_ui"
    print_info "Foreign Key" "$supp_log_fk"
    print_info "All Columns" "$supp_log_all"
    
    add_json "supplemental_log_min" "$supp_log_min"
    add_json "supplemental_log_pk" "$supp_log_pk"
    add_json "supplemental_log_ui" "$supp_log_ui"
    add_json "supplemental_log_fk" "$supp_log_fk"
    add_json "supplemental_log_all" "$supp_log_all"
}

discover_redo_archive() {
    print_header "REDO AND ARCHIVE CONFIGURATION"
    
    print_section "Redo Log Groups"
    run_sql "
SELECT group#, thread#, sequence#, bytes/1024/1024 as size_mb, members, status
FROM v\$log
ORDER BY group#;
" >> "$TEXT_REPORT"
    
    print_section "Redo Log Members"
    run_sql "
SELECT group#, member, type, status
FROM v\$logfile
ORDER BY group#;
" >> "$TEXT_REPORT"
    
    print_section "Archive Log Destinations"
    run_sql "
SELECT dest_id, dest_name, status, destination, binding
FROM v\$archive_dest
WHERE status != 'INACTIVE';
" >> "$TEXT_REPORT"
    
    local redo_size=$(run_sql_value "SELECT bytes/1024/1024 FROM v\$log WHERE rownum = 1;")
    local redo_groups=$(run_sql_value "SELECT COUNT(*) FROM v\$log;")
    add_json "redo_log_size_mb" "$redo_size"
    add_json "redo_log_groups" "$redo_groups"
}

discover_network_config() {
    print_header "NETWORK CONFIGURATION"
    
    print_section "Listener Status"
    if [ -n "${ORACLE_HOME:-}" ]; then
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            $ORACLE_HOME/bin/lsnrctl status 2>&1 >> "$TEXT_REPORT" || echo "Unable to get listener status" >> "$TEXT_REPORT"
        else
            sudo -u "$ORACLE_USER" ORACLE_HOME="$ORACLE_HOME" $ORACLE_HOME/bin/lsnrctl status 2>&1 >> "$TEXT_REPORT" || echo "Unable to get listener status" >> "$TEXT_REPORT"
        fi
    fi
    
    print_section "tnsnames.ora"
    local tns_file="$ORACLE_HOME/network/admin/tnsnames.ora"
    if [ -f "$tns_file" ]; then
        cat "$tns_file" >> "$TEXT_REPORT"
    else
        print_output "File not found: $tns_file"
    fi
    
    print_section "sqlnet.ora"
    local sqlnet_file="$ORACLE_HOME/network/admin/sqlnet.ora"
    if [ -f "$sqlnet_file" ]; then
        cat "$sqlnet_file" >> "$TEXT_REPORT"
    else
        print_output "File not found: $sqlnet_file"
    fi
}

discover_authentication() {
    print_header "AUTHENTICATION"
    
    print_section "Password File"
    local orapwd_file=$(find $ORACLE_HOME/dbs -name "orapw*" 2>/dev/null | head -1)
    if [ -n "$orapwd_file" ]; then
        print_info "Password File" "$orapwd_file"
        ls -la "$orapwd_file" >> "$TEXT_REPORT"
        add_json "password_file" "$orapwd_file"
    else
        print_info "Password File" "NOT FOUND"
        add_json "password_file" "NOT FOUND"
    fi
    
    print_section "SSH Directory Contents"
    if [ -d ~/.ssh ]; then
        ls -la ~/.ssh 2>/dev/null >> "$TEXT_REPORT"
    else
        print_output "SSH directory not found"
    fi
}

discover_dataguard() {
    print_header "DATA GUARD CONFIGURATION"
    
    print_section "DG Parameters"
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
" >> "$TEXT_REPORT"
}

discover_schemas() {
    print_header "SCHEMA INFORMATION"
    
    print_section "Large Schemas (> 100MB)"
    run_sql "
SELECT owner, ROUND(SUM(bytes)/1024/1024, 2) as size_mb
FROM dba_segments
WHERE owner NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','DBSFWUSER','GGSYS','GSMADMIN_INTERNAL','LBACSYS','MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','REMOTE_SCHEDULER_AGENT','WMSYS','XDB','CTXSYS','DVSYS','DVF','AUDSYS')
GROUP BY owner
HAVING SUM(bytes)/1024/1024 > 100
ORDER BY size_mb DESC;
" >> "$TEXT_REPORT"
    
    print_section "Invalid Objects"
    run_sql "
SELECT owner, object_type, COUNT(*) as invalid_count
FROM dba_objects
WHERE status = 'INVALID'
AND owner NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP')
GROUP BY owner, object_type
ORDER BY owner, object_type;
" >> "$TEXT_REPORT"
}

discover_tablespace_autoextend() {
    print_header "TABLESPACE AUTOEXTEND SETTINGS"
    
    run_sql "
SELECT tablespace_name, file_name, 
       ROUND(bytes/1024/1024, 2) as current_size_mb,
       ROUND(maxbytes/1024/1024, 2) as max_size_mb,
       autoextensible,
       ROUND(increment_by * (SELECT value FROM v\$parameter WHERE name = 'db_block_size') / 1024/1024, 2) as increment_mb
FROM dba_data_files
ORDER BY tablespace_name, file_name;
" >> "$TEXT_REPORT"
    
    print_section "Tablespace Usage Summary"
    run_sql "
SELECT tablespace_name,
       ROUND(SUM(bytes)/1024/1024/1024, 2) as used_gb,
       ROUND(SUM(maxbytes)/1024/1024/1024, 2) as max_gb,
       ROUND(SUM(bytes)/SUM(maxbytes)*100, 2) as pct_used
FROM dba_data_files
WHERE maxbytes > 0
GROUP BY tablespace_name
ORDER BY tablespace_name;
" >> "$TEXT_REPORT"
}

discover_backup_config() {
    print_header "BACKUP CONFIGURATION"
    
    print_section "RMAN Configuration"
    run_sql "
SELECT name, value
FROM v\$rman_configuration
ORDER BY name;
" >> "$TEXT_REPORT"
    
    print_section "Recent Backup History (Last 7 Days)"
    run_sql "
SELECT TO_CHAR(start_time, 'YYYY-MM-DD HH24:MI') as start_time,
       TO_CHAR(end_time, 'YYYY-MM-DD HH24:MI') as end_time,
       input_type,
       status,
       ROUND(input_bytes/1024/1024/1024, 2) as input_gb,
       ROUND(output_bytes/1024/1024/1024, 2) as output_gb
FROM v\$rman_backup_job_details
WHERE start_time > SYSDATE - 7
ORDER BY start_time DESC;
" >> "$TEXT_REPORT"
    
    print_section "Backup Retention"
    run_sql "
SELECT * FROM v\$backup_redolog WHERE rownum <= 10;
" >> "$TEXT_REPORT"
}

discover_database_links() {
    print_header "DATABASE LINKS"
    
    run_sql "
SELECT owner, db_link, username, host, created
FROM dba_db_links
ORDER BY owner, db_link;
" >> "$TEXT_REPORT"
    
    local dblink_count=$(run_sql_value "SELECT COUNT(*) FROM dba_db_links;")
    add_json "database_link_count" "$dblink_count"
    
    print_section "Database Link Details"
    run_sql "
SELECT owner, db_link, 
       CASE WHEN username IS NULL THEN 'CURRENT_USER' ELSE username END as connect_user,
       host as connect_string
FROM dba_db_links
ORDER BY owner, db_link;
" >> "$TEXT_REPORT"
}

discover_materialized_views() {
    print_header "MATERIALIZED VIEWS"
    
    run_sql "
SELECT owner, mview_name, 
       refresh_mode, refresh_method,
       last_refresh_type, 
       TO_CHAR(last_refresh_date, 'YYYY-MM-DD HH24:MI:SS') as last_refresh,
       staleness
FROM dba_mviews
WHERE owner NOT IN ('SYS','SYSTEM')
ORDER BY owner, mview_name;
" >> "$TEXT_REPORT"
    
    print_section "Materialized View Refresh Jobs"
    run_sql "
SELECT rowner, rname, refgroup, 
       TO_CHAR(next_date, 'YYYY-MM-DD HH24:MI:SS') as next_refresh,
       interval
FROM dba_refresh
ORDER BY rowner, rname;
" >> "$TEXT_REPORT"
    
    local mview_count=$(run_sql_value "SELECT COUNT(*) FROM dba_mviews WHERE owner NOT IN ('SYS','SYSTEM');")
    add_json "materialized_view_count" "$mview_count"
}

discover_scheduler_jobs() {
    print_header "SCHEDULER JOBS"
    
    run_sql "
SELECT owner, job_name, job_type, 
       state, enabled,
       TO_CHAR(last_start_date, 'YYYY-MM-DD HH24:MI:SS') as last_run,
       TO_CHAR(next_run_date, 'YYYY-MM-DD HH24:MI:SS') as next_run,
       repeat_interval
FROM dba_scheduler_jobs
WHERE owner NOT IN ('SYS','SYSTEM','ORACLE_OCM','EXFSYS')
ORDER BY owner, job_name;
" >> "$TEXT_REPORT"
    
    print_section "DBMS_JOB Jobs (Legacy)"
    run_sql "
SELECT job, log_user, schema_user,
       TO_CHAR(last_date, 'YYYY-MM-DD HH24:MI:SS') as last_run,
       TO_CHAR(next_date, 'YYYY-MM-DD HH24:MI:SS') as next_run,
       interval, what
FROM dba_jobs
ORDER BY job;
" >> "$TEXT_REPORT"
    
    local scheduler_job_count=$(run_sql_value "SELECT COUNT(*) FROM dba_scheduler_jobs WHERE owner NOT IN ('SYS','SYSTEM','ORACLE_OCM','EXFSYS');")
    local legacy_job_count=$(run_sql_value "SELECT COUNT(*) FROM dba_jobs;")
    add_json "scheduler_job_count" "$scheduler_job_count"
    add_json "legacy_job_count" "$legacy_job_count"
}

#===============================================================================
# MAIN EXECUTION
#===============================================================================

main() {
    echo "ZDM Source Database Discovery Script" > "$TEXT_REPORT"
    echo "Generated: $(date)" >> "$TEXT_REPORT"
    echo "Hostname: $(hostname)" >> "$TEXT_REPORT"
    echo "User: $(whoami)" >> "$TEXT_REPORT"
    
    add_json "discovery_type" "source"
    add_json "discovery_timestamp" "$(date -Iseconds)"
    add_json "discovered_by" "$(whoami)"
    
    echo -e "${CYAN}Starting Source Database Discovery...${NC}"
    echo -e "${CYAN}Output files will be created in current directory${NC}"
    
    # Run all discovery functions (continue on error)
    discover_os_info || echo "Warning: OS info discovery had errors"
    discover_oracle_env || echo "Warning: Oracle env discovery had errors"
    discover_database_config || echo "Warning: Database config discovery had errors"
    discover_cdb_pdb || echo "Warning: CDB/PDB discovery had errors"
    discover_tde_config || echo "Warning: TDE discovery had errors"
    discover_supplemental_logging || echo "Warning: Supplemental logging discovery had errors"
    discover_redo_archive || echo "Warning: Redo/Archive discovery had errors"
    discover_network_config || echo "Warning: Network config discovery had errors"
    discover_authentication || echo "Warning: Authentication discovery had errors"
    discover_dataguard || echo "Warning: Data Guard discovery had errors"
    discover_schemas || echo "Warning: Schema discovery had errors"
    
    # Additional discovery requirements
    discover_tablespace_autoextend || echo "Warning: Tablespace autoextend discovery had errors"
    discover_backup_config || echo "Warning: Backup config discovery had errors"
    discover_database_links || echo "Warning: Database links discovery had errors"
    discover_materialized_views || echo "Warning: Materialized views discovery had errors"
    discover_scheduler_jobs || echo "Warning: Scheduler jobs discovery had errors"
    
    # Write JSON report
    write_json
    
    echo ""
    echo -e "${GREEN}===============================================================================${NC}"
    echo -e "${GREEN}Discovery Complete${NC}"
    echo -e "${GREEN}===============================================================================${NC}"
    echo -e "Text Report: ${CYAN}$TEXT_REPORT${NC}"
    echo -e "JSON Report: ${CYAN}$JSON_REPORT${NC}"
}

# Run main function
main "$@"
