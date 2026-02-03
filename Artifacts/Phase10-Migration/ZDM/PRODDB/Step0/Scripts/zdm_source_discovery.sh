#!/bin/bash
#
# ZDM Source Database Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# Source: proddb01.corp.example.com
#
# Purpose: Gather comprehensive discovery information from the source Oracle database
#          for Zero Downtime Migration (ZDM) planning
#
# Usage: bash zdm_source_discovery.sh
#
# Output: 
#   - zdm_source_discovery_<hostname>_<timestamp>.txt (human-readable report)
#   - zdm_source_discovery_<hostname>_<timestamp>.json (machine-parseable JSON)
#

# ===========================================
# CONFIGURATION
# ===========================================

# Default oracle user if not set
ORACLE_USER="${ORACLE_USER:-oracle}"

# Timestamp for output files
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname -s 2>/dev/null || hostname)

# Output files (in current working directory)
TEXT_OUTPUT="./zdm_source_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_OUTPUT="./zdm_source_discovery_${HOSTNAME}_${TIMESTAMP}.json"

# ===========================================
# COLOR OUTPUT FUNCTIONS
# ===========================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "\n${BLUE}========================================${NC}"; echo -e "${BLUE}$1${NC}"; echo -e "${BLUE}========================================${NC}"; }

# ===========================================
# OUTPUT FUNCTIONS
# ===========================================

# Initialize output files
init_output() {
    echo "ZDM Source Database Discovery Report" > "$TEXT_OUTPUT"
    echo "Generated: $(date)" >> "$TEXT_OUTPUT"
    echo "Hostname: $HOSTNAME" >> "$TEXT_OUTPUT"
    echo "Project: PRODDB Migration to Oracle Database@Azure" >> "$TEXT_OUTPUT"
    echo "========================================" >> "$TEXT_OUTPUT"
    
    # Initialize JSON
    echo "{" > "$JSON_OUTPUT"
    echo "  \"report_type\": \"source_discovery\"," >> "$JSON_OUTPUT"
    echo "  \"generated\": \"$(date -Iseconds 2>/dev/null || date)\"," >> "$JSON_OUTPUT"
    echo "  \"hostname\": \"$HOSTNAME\"," >> "$JSON_OUTPUT"
    echo "  \"project\": \"PRODDB Migration to Oracle Database@Azure\"," >> "$JSON_OUTPUT"
}

write_section() {
    local section_name="$1"
    echo "" >> "$TEXT_OUTPUT"
    echo "========================================" >> "$TEXT_OUTPUT"
    echo "$section_name" >> "$TEXT_OUTPUT"
    echo "========================================" >> "$TEXT_OUTPUT"
}

write_text() {
    echo "$1" >> "$TEXT_OUTPUT"
}

write_json_field() {
    local field_name="$1"
    local field_value="$2"
    local is_last="${3:-false}"
    
    # Escape special characters in JSON
    field_value=$(echo "$field_value" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' ' ')
    
    if [ "$is_last" = "true" ]; then
        echo "  \"$field_name\": \"$field_value\"" >> "$JSON_OUTPUT"
    else
        echo "  \"$field_name\": \"$field_value\"," >> "$JSON_OUTPUT"
    fi
}

finalize_json() {
    echo "}" >> "$JSON_OUTPUT"
}

# ===========================================
# ORACLE ENVIRONMENT DETECTION
# ===========================================

detect_oracle_env() {
    log_info "Detecting Oracle environment..."
    
    # If already set, use existing values
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        log_info "Using pre-set ORACLE_HOME=$ORACLE_HOME, ORACLE_SID=$ORACLE_SID"
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
            log_info "Detected from /etc/oratab: ORACLE_SID=$ORACLE_SID, ORACLE_HOME=$ORACLE_HOME"
        fi
    fi
    
    # Method 2: Check running pmon process
    if [ -z "${ORACLE_SID:-}" ]; then
        local pmon_sid
        pmon_sid=$(ps -ef | grep 'ora_pmon_' | grep -v grep | head -1 | sed 's/.*ora_pmon_//')
        if [ -n "$pmon_sid" ]; then
            export ORACLE_SID="$pmon_sid"
            log_info "Detected ORACLE_SID from pmon: $ORACLE_SID"
        fi
    fi
    
    # Method 3: Search common Oracle installation paths
    if [ -z "${ORACLE_HOME:-}" ]; then
        for path in /u01/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1 /oracle/product/*/dbhome_1; do
            if [ -d "$path" ] && [ -f "$path/bin/sqlplus" ]; then
                export ORACLE_HOME="$path"
                log_info "Detected ORACLE_HOME from common path: $ORACLE_HOME"
                break
            fi
        done
    fi
    
    # Method 4: Try oraenv if available
    if [ -z "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        if [ -f /usr/local/bin/oraenv ]; then
            . /usr/local/bin/oraenv <<< "$ORACLE_SID" 2>/dev/null
        fi
    fi
    
    # Apply overrides if provided
    [ -n "${ORACLE_HOME_OVERRIDE:-}" ] && export ORACLE_HOME="$ORACLE_HOME_OVERRIDE"
    [ -n "${ORACLE_SID_OVERRIDE:-}" ] && export ORACLE_SID="$ORACLE_SID_OVERRIDE"
    
    # Detect ORACLE_BASE
    if [ -z "${ORACLE_BASE:-}" ] && [ -n "${ORACLE_HOME:-}" ]; then
        # Try to derive from ORACLE_HOME
        export ORACLE_BASE=$(echo "$ORACLE_HOME" | sed 's|/product/.*||')
    fi
}

# ===========================================
# SQL EXECUTION FUNCTIONS
# ===========================================

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
    run_sql "$sql_query" | grep -v "^$" | tail -1 | xargs
}

# ===========================================
# DISCOVERY FUNCTIONS
# ===========================================

discover_os_info() {
    log_section "OS Information"
    write_section "OS Information"
    
    # Hostname
    local hostname_full=$(hostname -f 2>/dev/null || hostname)
    write_text "Hostname: $hostname_full"
    write_json_field "hostname_full" "$hostname_full"
    
    # IP Addresses
    local ip_addresses=$(ip addr show 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | tr '\n' ',' | sed 's/,$//')
    if [ -z "$ip_addresses" ]; then
        ip_addresses=$(ifconfig 2>/dev/null | grep 'inet ' | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')
    fi
    write_text "IP Addresses: $ip_addresses"
    write_json_field "ip_addresses" "$ip_addresses"
    
    # OS Version
    local os_version=""
    if [ -f /etc/os-release ]; then
        os_version=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
    elif [ -f /etc/redhat-release ]; then
        os_version=$(cat /etc/redhat-release)
    else
        os_version=$(uname -a)
    fi
    write_text "OS Version: $os_version"
    write_json_field "os_version" "$os_version"
    
    # Disk Space
    write_text ""
    write_text "Disk Space:"
    df -h 2>/dev/null >> "$TEXT_OUTPUT"
    local disk_usage=$(df -h 2>/dev/null | grep -E '^/dev' | head -5 | tr '\n' ';')
    write_json_field "disk_space" "$disk_usage"
    
    log_info "OS information collected"
}

discover_oracle_environment() {
    log_section "Oracle Environment"
    write_section "Oracle Environment"
    
    write_text "ORACLE_HOME: ${ORACLE_HOME:-NOT SET}"
    write_text "ORACLE_SID: ${ORACLE_SID:-NOT SET}"
    write_text "ORACLE_BASE: ${ORACLE_BASE:-NOT SET}"
    
    write_json_field "oracle_home" "${ORACLE_HOME:-}"
    write_json_field "oracle_sid" "${ORACLE_SID:-}"
    write_json_field "oracle_base" "${ORACLE_BASE:-}"
    
    # Oracle Version
    if [ -n "${ORACLE_HOME:-}" ] && [ -f "$ORACLE_HOME/bin/sqlplus" ]; then
        local oracle_version=$(run_sql_value "SELECT banner FROM v\$version WHERE ROWNUM = 1;")
        write_text "Oracle Version: $oracle_version"
        write_json_field "oracle_version" "$oracle_version"
    fi
    
    log_info "Oracle environment collected"
}

discover_database_config() {
    log_section "Database Configuration"
    write_section "Database Configuration"
    
    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        log_error "Oracle environment not set - skipping database configuration"
        write_text "ERROR: Oracle environment not set"
        return 1
    fi
    
    # Database name and DBID
    local db_name=$(run_sql_value "SELECT name FROM v\$database;")
    local db_unique_name=$(run_sql_value "SELECT db_unique_name FROM v\$database;")
    local dbid=$(run_sql_value "SELECT dbid FROM v\$database;")
    
    write_text "Database Name: $db_name"
    write_text "DB Unique Name: $db_unique_name"
    write_text "DBID: $dbid"
    
    write_json_field "db_name" "$db_name"
    write_json_field "db_unique_name" "$db_unique_name"
    write_json_field "dbid" "$dbid"
    
    # Database role and mode
    local db_role=$(run_sql_value "SELECT database_role FROM v\$database;")
    local open_mode=$(run_sql_value "SELECT open_mode FROM v\$database;")
    
    write_text "Database Role: $db_role"
    write_text "Open Mode: $open_mode"
    
    write_json_field "database_role" "$db_role"
    write_json_field "open_mode" "$open_mode"
    
    # Log mode
    local log_mode=$(run_sql_value "SELECT log_mode FROM v\$database;")
    local force_logging=$(run_sql_value "SELECT force_logging FROM v\$database;")
    
    write_text "Log Mode: $log_mode"
    write_text "Force Logging: $force_logging"
    
    write_json_field "log_mode" "$log_mode"
    write_json_field "force_logging" "$force_logging"
    
    # Database size
    write_text ""
    write_text "Database Size:"
    run_sql "
SELECT 'Data Files' AS file_type, ROUND(SUM(bytes)/1024/1024/1024, 2) AS size_gb FROM dba_data_files
UNION ALL
SELECT 'Temp Files', ROUND(SUM(bytes)/1024/1024/1024, 2) FROM dba_temp_files
UNION ALL
SELECT 'Redo Logs', ROUND(SUM(bytes)/1024/1024/1024, 2) FROM v\$log;
" >> "$TEXT_OUTPUT"
    
    local data_size=$(run_sql_value "SELECT ROUND(SUM(bytes)/1024/1024/1024, 2) FROM dba_data_files;")
    write_json_field "data_files_size_gb" "$data_size"
    
    # Character set
    local character_set=$(run_sql_value "SELECT value FROM nls_database_parameters WHERE parameter = 'NLS_CHARACTERSET';")
    local nchar_set=$(run_sql_value "SELECT value FROM nls_database_parameters WHERE parameter = 'NLS_NCHAR_CHARACTERSET';")
    
    write_text ""
    write_text "Character Set: $character_set"
    write_text "National Character Set: $nchar_set"
    
    write_json_field "character_set" "$character_set"
    write_json_field "nchar_character_set" "$nchar_set"
    
    log_info "Database configuration collected"
}

discover_cdb_pdbs() {
    log_section "Container Database / PDBs"
    write_section "Container Database / PDBs"
    
    # CDB Status
    local cdb_status=$(run_sql_value "SELECT CDB FROM v\$database;")
    write_text "Is CDB: $cdb_status"
    write_json_field "is_cdb" "$cdb_status"
    
    if [ "$cdb_status" = "YES" ]; then
        write_text ""
        write_text "PDBs:"
        run_sql "
SELECT pdb_name, status, open_mode, con_id 
FROM cdb_pdbs 
ORDER BY con_id;
" >> "$TEXT_OUTPUT"
        
        local pdb_list=$(run_sql_value "SELECT LISTAGG(pdb_name, ',') WITHIN GROUP (ORDER BY con_id) FROM cdb_pdbs;")
        write_json_field "pdb_list" "$pdb_list"
    fi
    
    log_info "CDB/PDB information collected"
}

discover_tde_config() {
    log_section "TDE Configuration"
    write_section "TDE Configuration"
    
    # Check encryption wallet status
    write_text "Encryption Wallet Status:"
    run_sql "SELECT * FROM v\$encryption_wallet;" >> "$TEXT_OUTPUT" 2>/dev/null || write_text "Unable to query v\$encryption_wallet"
    
    # TDE enabled tablespaces
    write_text ""
    write_text "Encrypted Tablespaces:"
    run_sql "
SELECT tablespace_name, encrypted 
FROM dba_tablespaces 
WHERE encrypted = 'YES';
" >> "$TEXT_OUTPUT" 2>/dev/null || write_text "No encrypted tablespaces found"
    
    local encrypted_ts=$(run_sql_value "SELECT COUNT(*) FROM dba_tablespaces WHERE encrypted = 'YES';")
    write_json_field "encrypted_tablespace_count" "$encrypted_ts"
    
    # Wallet location from sqlnet.ora
    local wallet_location=""
    if [ -f "$ORACLE_HOME/network/admin/sqlnet.ora" ]; then
        wallet_location=$(grep -i "ENCRYPTION_WALLET_LOCATION" "$ORACLE_HOME/network/admin/sqlnet.ora" 2>/dev/null | head -1)
    fi
    write_text ""
    write_text "Wallet Location (from sqlnet.ora): $wallet_location"
    write_json_field "wallet_location_config" "$wallet_location"
    
    log_info "TDE configuration collected"
}

discover_supplemental_logging() {
    log_section "Supplemental Logging"
    write_section "Supplemental Logging"
    
    run_sql "
SELECT supplemental_log_data_min, supplemental_log_data_pk, 
       supplemental_log_data_ui, supplemental_log_data_fk, 
       supplemental_log_data_all 
FROM v\$database;
" >> "$TEXT_OUTPUT"
    
    local suplog_min=$(run_sql_value "SELECT supplemental_log_data_min FROM v\$database;")
    local suplog_pk=$(run_sql_value "SELECT supplemental_log_data_pk FROM v\$database;")
    
    write_json_field "supplemental_log_min" "$suplog_min"
    write_json_field "supplemental_log_pk" "$suplog_pk"
    
    log_info "Supplemental logging collected"
}

discover_redo_archive_config() {
    log_section "Redo/Archive Configuration"
    write_section "Redo/Archive Configuration"
    
    # Redo log groups
    write_text "Redo Log Groups:"
    run_sql "
SELECT group#, thread#, sequence#, bytes/1024/1024 AS size_mb, members, status 
FROM v\$log 
ORDER BY group#;
" >> "$TEXT_OUTPUT"
    
    # Redo log members
    write_text ""
    write_text "Redo Log Members:"
    run_sql "SELECT group#, member FROM v\$logfile ORDER BY group#;" >> "$TEXT_OUTPUT"
    
    # Archive destinations
    write_text ""
    write_text "Archive Log Destinations:"
    run_sql "
SELECT dest_id, dest_name, status, target, destination 
FROM v\$archive_dest 
WHERE status != 'INACTIVE';
" >> "$TEXT_OUTPUT"
    
    local redo_groups=$(run_sql_value "SELECT COUNT(*) FROM v\$log;")
    write_json_field "redo_log_groups" "$redo_groups"
    
    log_info "Redo/archive configuration collected"
}

discover_network_config() {
    log_section "Network Configuration"
    write_section "Network Configuration"
    
    # Listener status
    write_text "Listener Status:"
    if [ -n "${ORACLE_HOME:-}" ]; then
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            $ORACLE_HOME/bin/lsnrctl status 2>/dev/null >> "$TEXT_OUTPUT" || write_text "Unable to get listener status"
        else
            sudo -u "$ORACLE_USER" ORACLE_HOME="$ORACLE_HOME" $ORACLE_HOME/bin/lsnrctl status 2>/dev/null >> "$TEXT_OUTPUT" || write_text "Unable to get listener status"
        fi
    fi
    
    # tnsnames.ora
    write_text ""
    write_text "tnsnames.ora contents:"
    if [ -f "$ORACLE_HOME/network/admin/tnsnames.ora" ]; then
        cat "$ORACLE_HOME/network/admin/tnsnames.ora" >> "$TEXT_OUTPUT" 2>/dev/null
    else
        write_text "File not found: $ORACLE_HOME/network/admin/tnsnames.ora"
    fi
    
    # sqlnet.ora
    write_text ""
    write_text "sqlnet.ora contents:"
    if [ -f "$ORACLE_HOME/network/admin/sqlnet.ora" ]; then
        cat "$ORACLE_HOME/network/admin/sqlnet.ora" >> "$TEXT_OUTPUT" 2>/dev/null
    else
        write_text "File not found: $ORACLE_HOME/network/admin/sqlnet.ora"
    fi
    
    log_info "Network configuration collected"
}

discover_authentication() {
    log_section "Authentication Configuration"
    write_section "Authentication Configuration"
    
    # Password file
    write_text "Password File:"
    local pwfile_loc="${ORACLE_HOME}/dbs/orapw${ORACLE_SID}"
    if [ -f "$pwfile_loc" ]; then
        write_text "Password file exists: $pwfile_loc"
        ls -la "$pwfile_loc" >> "$TEXT_OUTPUT" 2>/dev/null
    else
        write_text "Password file not found at: $pwfile_loc"
        # Check ASM location
        write_text "Checking for password file in ASM or other locations..."
        run_sql "SELECT file_name FROM v\$passwordfile_info;" >> "$TEXT_OUTPUT" 2>/dev/null || write_text "Unable to query password file info"
    fi
    write_json_field "password_file_location" "$pwfile_loc"
    
    # SSH directory contents (for oracle user)
    write_text ""
    write_text "SSH Directory Contents (oracle user):"
    local oracle_home_dir=$(eval echo ~$ORACLE_USER 2>/dev/null)
    if [ -d "$oracle_home_dir/.ssh" ]; then
        ls -la "$oracle_home_dir/.ssh" 2>/dev/null >> "$TEXT_OUTPUT" || write_text "Unable to list SSH directory"
    else
        write_text "SSH directory not found for oracle user (this is normal if using admin user with sudo)"
    fi
    
    log_info "Authentication configuration collected"
}

discover_dataguard() {
    log_section "Data Guard Configuration"
    write_section "Data Guard Configuration"
    
    run_sql "
SELECT name, value 
FROM v\$parameter 
WHERE name IN ('log_archive_config', 'log_archive_dest_1', 'log_archive_dest_2',
               'log_archive_dest_state_1', 'log_archive_dest_state_2',
               'fal_server', 'fal_client', 'db_file_name_convert', 
               'log_file_name_convert', 'standby_file_management')
ORDER BY name;
" >> "$TEXT_OUTPUT"
    
    log_info "Data Guard configuration collected"
}

discover_schema_info() {
    log_section "Schema Information"
    write_section "Schema Information"
    
    # Schema sizes (non-system schemas > 100MB)
    write_text "Schema Sizes (> 100MB, excluding system schemas):"
    run_sql "
SELECT owner, ROUND(SUM(bytes)/1024/1024, 2) AS size_mb
FROM dba_segments
WHERE owner NOT IN ('SYS', 'SYSTEM', 'DBSNMP', 'OUTLN', 'ORACLE_OCM', 
                    'APPQOSSYS', 'WMSYS', 'EXFSYS', 'CTXSYS', 'XDB',
                    'ORDDATA', 'ORDSYS', 'MDSYS', 'OLAPSYS', 'GSMADMIN_INTERNAL')
GROUP BY owner
HAVING SUM(bytes)/1024/1024 > 100
ORDER BY size_mb DESC;
" >> "$TEXT_OUTPUT"
    
    # Invalid objects
    write_text ""
    write_text "Invalid Objects by Owner/Type:"
    run_sql "
SELECT owner, object_type, COUNT(*) AS invalid_count
FROM dba_objects
WHERE status = 'INVALID'
GROUP BY owner, object_type
ORDER BY owner, object_type;
" >> "$TEXT_OUTPUT"
    
    local invalid_count=$(run_sql_value "SELECT COUNT(*) FROM dba_objects WHERE status = 'INVALID';")
    write_json_field "invalid_object_count" "$invalid_count"
    
    log_info "Schema information collected"
}

# ===========================================
# ADDITIONAL DISCOVERY (PRODDB Specific)
# ===========================================

discover_tablespace_autoextend() {
    log_section "Tablespace Autoextend Settings"
    write_section "Tablespace Autoextend Settings"
    
    run_sql "
SELECT tablespace_name, file_name, 
       ROUND(bytes/1024/1024, 2) AS size_mb,
       ROUND(maxbytes/1024/1024, 2) AS max_size_mb,
       autoextensible, 
       ROUND(increment_by * (SELECT value FROM v\$parameter WHERE name = 'db_block_size') / 1024 / 1024, 2) AS increment_mb
FROM dba_data_files
ORDER BY tablespace_name, file_name;
" >> "$TEXT_OUTPUT"
    
    local autoextend_count=$(run_sql_value "SELECT COUNT(*) FROM dba_data_files WHERE autoextensible = 'YES';")
    write_json_field "autoextend_datafile_count" "$autoextend_count"
    
    log_info "Tablespace autoextend settings collected"
}

discover_backup_config() {
    log_section "Backup Schedule and Retention"
    write_section "Backup Schedule and Retention"
    
    # RMAN configuration
    write_text "RMAN Configuration:"
    run_sql "SELECT name, value FROM v\$rman_configuration ORDER BY name;" >> "$TEXT_OUTPUT"
    
    # Recent backups
    write_text ""
    write_text "Recent Backup History (last 7 days):"
    run_sql "
SELECT TO_CHAR(start_time, 'YYYY-MM-DD HH24:MI:SS') AS start_time,
       TO_CHAR(end_time, 'YYYY-MM-DD HH24:MI:SS') AS end_time,
       input_type, status, 
       ROUND(output_bytes/1024/1024/1024, 2) AS output_gb
FROM v\$rman_backup_job_details
WHERE start_time > SYSDATE - 7
ORDER BY start_time DESC;
" >> "$TEXT_OUTPUT"
    
    # Scheduler jobs for backups
    write_text ""
    write_text "Scheduler Jobs (Backup Related):"
    run_sql "
SELECT owner, job_name, job_type, state, enabled, 
       TO_CHAR(last_start_date, 'YYYY-MM-DD HH24:MI:SS') AS last_run,
       TO_CHAR(next_run_date, 'YYYY-MM-DD HH24:MI:SS') AS next_run,
       repeat_interval
FROM dba_scheduler_jobs
WHERE UPPER(job_name) LIKE '%BACKUP%' OR UPPER(job_action) LIKE '%BACKUP%' OR UPPER(job_action) LIKE '%RMAN%'
ORDER BY owner, job_name;
" >> "$TEXT_OUTPUT"
    
    log_info "Backup configuration collected"
}

discover_database_links() {
    log_section "Database Links"
    write_section "Database Links"
    
    run_sql "
SELECT owner, db_link, username, host, created
FROM dba_db_links
ORDER BY owner, db_link;
" >> "$TEXT_OUTPUT"
    
    local dblink_count=$(run_sql_value "SELECT COUNT(*) FROM dba_db_links;")
    write_json_field "database_link_count" "$dblink_count"
    
    # Test database link connectivity (optional - just report what exists)
    write_text ""
    write_text "Database Link Details:"
    run_sql "
SELECT owner, db_link, 
       CASE WHEN host IS NOT NULL THEN host ELSE 'TNS Entry' END AS connection_type,
       username AS remote_user
FROM dba_db_links
ORDER BY owner, db_link;
" >> "$TEXT_OUTPUT"
    
    log_info "Database links collected"
}

discover_materialized_views() {
    log_section "Materialized View Refresh Schedules"
    write_section "Materialized View Refresh Schedules"
    
    run_sql "
SELECT owner, mview_name, 
       refresh_mode, refresh_method, 
       build_mode, fast_refreshable,
       TO_CHAR(last_refresh_date, 'YYYY-MM-DD HH24:MI:SS') AS last_refresh,
       staleness
FROM dba_mviews
ORDER BY owner, mview_name;
" >> "$TEXT_OUTPUT"
    
    # Refresh groups
    write_text ""
    write_text "Materialized View Refresh Groups:"
    run_sql "
SELECT rowner, rname, refgroup, 
       TO_CHAR(next_date, 'YYYY-MM-DD HH24:MI:SS') AS next_refresh,
       interval, broken
FROM dba_refresh
ORDER BY rowner, rname;
" >> "$TEXT_OUTPUT"
    
    local mview_count=$(run_sql_value "SELECT COUNT(*) FROM dba_mviews;")
    write_json_field "materialized_view_count" "$mview_count"
    
    log_info "Materialized view schedules collected"
}

discover_scheduler_jobs() {
    log_section "Scheduler Jobs (All)"
    write_section "Scheduler Jobs (All)"
    
    run_sql "
SELECT owner, job_name, job_type, state, enabled,
       TO_CHAR(last_start_date, 'YYYY-MM-DD HH24:MI:SS') AS last_run,
       TO_CHAR(next_run_date, 'YYYY-MM-DD HH24:MI:SS') AS next_run,
       repeat_interval,
       SUBSTR(job_action, 1, 100) AS job_action_preview
FROM dba_scheduler_jobs
WHERE owner NOT IN ('SYS', 'SYSTEM', 'ORACLE_OCM', 'EXFSYS')
ORDER BY owner, job_name;
" >> "$TEXT_OUTPUT"
    
    # Job schedules
    write_text ""
    write_text "Job Schedules:"
    run_sql "
SELECT owner, schedule_name, schedule_type, 
       TO_CHAR(start_date, 'YYYY-MM-DD HH24:MI:SS') AS start_date,
       repeat_interval
FROM dba_scheduler_schedules
WHERE owner NOT IN ('SYS', 'SYSTEM')
ORDER BY owner, schedule_name;
" >> "$TEXT_OUTPUT"
    
    local job_count=$(run_sql_value "SELECT COUNT(*) FROM dba_scheduler_jobs WHERE owner NOT IN ('SYS', 'SYSTEM', 'ORACLE_OCM', 'EXFSYS');")
    write_json_field "scheduler_job_count" "$job_count"
    
    log_info "Scheduler jobs collected"
}

# ===========================================
# MAIN EXECUTION
# ===========================================

main() {
    log_info "Starting ZDM Source Database Discovery"
    log_info "Output will be saved to:"
    log_info "  Text: $TEXT_OUTPUT"
    log_info "  JSON: $JSON_OUTPUT"
    
    # Initialize output files
    init_output
    
    # Detect Oracle environment
    detect_oracle_env
    
    # Standard discovery sections
    discover_os_info || log_warn "OS information discovery failed - continuing"
    discover_oracle_environment || log_warn "Oracle environment discovery failed - continuing"
    discover_database_config || log_warn "Database configuration discovery failed - continuing"
    discover_cdb_pdbs || log_warn "CDB/PDB discovery failed - continuing"
    discover_tde_config || log_warn "TDE configuration discovery failed - continuing"
    discover_supplemental_logging || log_warn "Supplemental logging discovery failed - continuing"
    discover_redo_archive_config || log_warn "Redo/archive configuration discovery failed - continuing"
    discover_network_config || log_warn "Network configuration discovery failed - continuing"
    discover_authentication || log_warn "Authentication discovery failed - continuing"
    discover_dataguard || log_warn "Data Guard discovery failed - continuing"
    discover_schema_info || log_warn "Schema information discovery failed - continuing"
    
    # Additional PRODDB-specific discovery
    discover_tablespace_autoextend || log_warn "Tablespace autoextend discovery failed - continuing"
    discover_backup_config || log_warn "Backup configuration discovery failed - continuing"
    discover_database_links || log_warn "Database links discovery failed - continuing"
    discover_materialized_views || log_warn "Materialized view discovery failed - continuing"
    discover_scheduler_jobs || log_warn "Scheduler jobs discovery failed - continuing"
    
    # Finalize JSON output
    write_json_field "discovery_completed" "$(date -Iseconds 2>/dev/null || date)" "true"
    finalize_json
    
    log_info ""
    log_info "=========================================="
    log_info "Discovery Complete!"
    log_info "=========================================="
    log_info "Text Report: $TEXT_OUTPUT"
    log_info "JSON Summary: $JSON_OUTPUT"
}

# Run main function
main "$@"
