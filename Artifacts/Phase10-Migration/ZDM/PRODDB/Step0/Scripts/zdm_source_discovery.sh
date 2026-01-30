#!/bin/bash
#===============================================================================
# ZDM Source Database Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# Source Database: proddb01.corp.example.com
#
# Purpose: Gather discovery information from the source Oracle database server
#
# Usage: ./zdm_source_discovery.sh
#
# Output:
#   - zdm_source_discovery_<hostname>_<timestamp>.txt (human-readable report)
#   - zdm_source_discovery_<hostname>_<timestamp>.json (machine-parseable JSON)
#===============================================================================

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script variables
SCRIPT_VERSION="1.0.0"
HOSTNAME=$(hostname -s 2>/dev/null || hostname)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="./zdm_source_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_source_discovery_${HOSTNAME}_${TIMESTAMP}.json"

# User configuration - can be overridden via environment
ORACLE_USER="${ORACLE_USER:-oracle}"

# Error tracking
SECTION_ERRORS=0
TOTAL_ERRORS=0

#===============================================================================
# Functions
#===============================================================================

print_header() {
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}============================================================${NC}"
}

print_section() {
    echo -e "\n${BLUE}------------------------------------------------------------${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}------------------------------------------------------------${NC}"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info() {
    echo -e "${NC}$1${NC}"
}

# Auto-detect ORACLE_HOME and ORACLE_SID
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
            oratab_entry=$(grep -v '^#' /etc/oratab | grep -v '^$' | head -1)
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
}

# Apply explicit overrides if provided (highest priority)
apply_overrides() {
    [ -n "${ORACLE_HOME_OVERRIDE:-}" ] && export ORACLE_HOME="$ORACLE_HOME_OVERRIDE"
    [ -n "${ORACLE_SID_OVERRIDE:-}" ] && export ORACLE_SID="$ORACLE_SID_OVERRIDE"
}

# Run SQL command and return output
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

# Run SQL and get single value
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
SET TRIMOUT ON
$sql_query
EOSQL
)
        # Execute as oracle user - use sudo if current user is not oracle
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

# Write both to stdout and file
tee_output() {
    tee -a "$OUTPUT_FILE"
}

# Initialize JSON output
init_json() {
    cat > "$JSON_FILE" <<EOF
{
  "discovery_type": "source",
  "hostname": "$HOSTNAME",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "script_version": "$SCRIPT_VERSION",
EOF
}

# Close JSON output
close_json() {
    # Remove trailing comma and close JSON
    sed -i '$ s/,$//' "$JSON_FILE" 2>/dev/null || true
    echo "}" >> "$JSON_FILE"
}

# Add JSON section
add_json() {
    local key="$1"
    local value="$2"
    local is_object="${3:-false}"
    
    if [ "$is_object" = "true" ]; then
        echo "  \"$key\": $value," >> "$JSON_FILE"
    else
        # Escape special characters in value
        value=$(echo "$value" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' | tr '\n' ' ')
        echo "  \"$key\": \"$value\"," >> "$JSON_FILE"
    fi
}

#===============================================================================
# Discovery Sections
#===============================================================================

discover_os_info() {
    print_section "OS INFORMATION"
    
    echo "Hostname: $HOSTNAME"
    echo "IP Addresses:"
    ip addr show 2>/dev/null | grep 'inet ' | awk '{print "  " $2}' || hostname -I 2>/dev/null | tr ' ' '\n' | sed 's/^/  /'
    
    echo ""
    echo "Operating System:"
    if [ -f /etc/os-release ]; then
        cat /etc/os-release | grep -E "^(NAME|VERSION|ID)=" | sed 's/^/  /'
    elif [ -f /etc/redhat-release ]; then
        echo "  $(cat /etc/redhat-release)"
    fi
    
    echo ""
    echo "Kernel Version: $(uname -r)"
    
    echo ""
    echo "Disk Space:"
    df -h | grep -v tmpfs | head -20
    
    # Add to JSON
    add_json "hostname" "$HOSTNAME"
    add_json "os_version" "$(cat /etc/os-release 2>/dev/null | grep '^VERSION=' | cut -d= -f2 | tr -d '\"')"
    add_json "kernel" "$(uname -r)"
}

discover_oracle_env() {
    print_section "ORACLE ENVIRONMENT"
    
    echo "ORACLE_HOME: ${ORACLE_HOME:-NOT SET}"
    echo "ORACLE_SID: ${ORACLE_SID:-NOT SET}"
    echo "ORACLE_BASE: ${ORACLE_BASE:-NOT SET}"
    
    if [ -n "${ORACLE_HOME:-}" ]; then
        echo ""
        echo "Oracle Version:"
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            $ORACLE_HOME/bin/sqlplus -v 2>/dev/null || echo "  Unable to determine version"
        else
            sudo -u "$ORACLE_USER" $ORACLE_HOME/bin/sqlplus -v 2>/dev/null || echo "  Unable to determine version"
        fi
        
        local ora_version
        ora_version=$(run_sql_value "SELECT banner FROM v\$version WHERE banner LIKE 'Oracle%' AND ROWNUM = 1;")
        echo "  $ora_version"
    fi
    
    echo ""
    echo "/etc/oratab contents:"
    if [ -f /etc/oratab ]; then
        grep -v '^#' /etc/oratab | grep -v '^$' | sed 's/^/  /'
    else
        echo "  /etc/oratab not found"
    fi
    
    add_json "oracle_home" "${ORACLE_HOME:-}"
    add_json "oracle_sid" "${ORACLE_SID:-}"
}

discover_database_config() {
    print_section "DATABASE CONFIGURATION"
    
    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        print_warning "ORACLE_HOME or ORACLE_SID not set - skipping database discovery"
        return 1
    fi
    
    echo "Database Name: $(run_sql_value "SELECT name FROM v\$database;")"
    echo "DB Unique Name: $(run_sql_value "SELECT db_unique_name FROM v\$database;")"
    echo "DBID: $(run_sql_value "SELECT dbid FROM v\$database;")"
    echo "Database Role: $(run_sql_value "SELECT database_role FROM v\$database;")"
    echo "Open Mode: $(run_sql_value "SELECT open_mode FROM v\$database;")"
    echo "Log Mode: $(run_sql_value "SELECT log_mode FROM v\$database;")"
    echo "Force Logging: $(run_sql_value "SELECT force_logging FROM v\$database;")"
    
    echo ""
    echo "Database Size (GB):"
    run_sql "SELECT 'Data Files' AS type, ROUND(SUM(bytes)/1024/1024/1024, 2) AS size_gb FROM dba_data_files
UNION ALL
SELECT 'Temp Files', ROUND(SUM(bytes)/1024/1024/1024, 2) FROM dba_temp_files
UNION ALL
SELECT 'Redo Logs', ROUND(SUM(bytes)/1024/1024/1024, 2) FROM v\$log;"
    
    echo ""
    echo "Character Set:"
    run_sql "SELECT parameter, value FROM nls_database_parameters WHERE parameter LIKE '%CHARACTERSET%';"
    
    # Add key values to JSON
    add_json "database_name" "$(run_sql_value "SELECT name FROM v\$database;")"
    add_json "db_unique_name" "$(run_sql_value "SELECT db_unique_name FROM v\$database;")"
    add_json "dbid" "$(run_sql_value "SELECT dbid FROM v\$database;")"
    add_json "log_mode" "$(run_sql_value "SELECT log_mode FROM v\$database;")"
    add_json "force_logging" "$(run_sql_value "SELECT force_logging FROM v\$database;")"
}

discover_cdb_pdb() {
    print_section "CONTAINER DATABASE / PDB CONFIGURATION"
    
    local cdb_status
    cdb_status=$(run_sql_value "SELECT CDB FROM v\$database;")
    echo "CDB Status: $cdb_status"
    
    if [ "$cdb_status" = "YES" ]; then
        echo ""
        echo "PDB List:"
        run_sql "SELECT con_id, name, open_mode, restricted FROM v\$pdbs ORDER BY con_id;"
    fi
    
    add_json "is_cdb" "$cdb_status"
}

discover_tde() {
    print_section "TDE CONFIGURATION"
    
    echo "TDE Wallet Status:"
    run_sql "SELECT wrl_type, wrl_parameter, status, wallet_type FROM v\$encryption_wallet;"
    
    echo ""
    echo "Encrypted Tablespaces:"
    run_sql "SELECT tablespace_name, encrypted FROM dba_tablespaces WHERE encrypted = 'YES';"
    
    echo ""
    echo "Encryption Keys:"
    run_sql "SELECT key_id, tag, creation_time, activation_time FROM v\$encryption_keys WHERE ROWNUM <= 10;"
    
    local wallet_status
    wallet_status=$(run_sql_value "SELECT status FROM v\$encryption_wallet WHERE ROWNUM = 1;")
    add_json "tde_wallet_status" "$wallet_status"
}

discover_supplemental_logging() {
    print_section "SUPPLEMENTAL LOGGING"
    
    run_sql "SELECT supplemental_log_data_min, supplemental_log_data_pk, supplemental_log_data_ui, 
       supplemental_log_data_fk, supplemental_log_data_all 
FROM v\$database;"
}

discover_redo_archive() {
    print_section "REDO/ARCHIVE CONFIGURATION"
    
    echo "Redo Log Groups:"
    run_sql "SELECT group#, thread#, sequence#, bytes/1024/1024 AS size_mb, members, status 
FROM v\$log ORDER BY group#;"
    
    echo ""
    echo "Redo Log Members:"
    run_sql "SELECT group#, type, member FROM v\$logfile ORDER BY group#;"
    
    echo ""
    echo "Archive Log Destinations:"
    run_sql "SELECT dest_id, dest_name, status, destination FROM v\$archive_dest WHERE status != 'INACTIVE';"
    
    echo ""
    echo "Archive Log Mode Parameters:"
    run_sql "SELECT name, value FROM v\$parameter WHERE name LIKE 'log_archive%' ORDER BY name;"
}

discover_network() {
    print_section "NETWORK CONFIGURATION"
    
    echo "Listener Status:"
    if [ -n "${ORACLE_HOME:-}" ]; then
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            $ORACLE_HOME/bin/lsnrctl status 2>/dev/null | head -30 || echo "  Listener check failed"
        else
            sudo -u "$ORACLE_USER" $ORACLE_HOME/bin/lsnrctl status 2>/dev/null | head -30 || echo "  Listener check failed"
        fi
    fi
    
    echo ""
    echo "tnsnames.ora:"
    if [ -f "$ORACLE_HOME/network/admin/tnsnames.ora" ]; then
        cat "$ORACLE_HOME/network/admin/tnsnames.ora" 2>/dev/null | head -50
    else
        echo "  tnsnames.ora not found"
    fi
    
    echo ""
    echo "sqlnet.ora:"
    if [ -f "$ORACLE_HOME/network/admin/sqlnet.ora" ]; then
        cat "$ORACLE_HOME/network/admin/sqlnet.ora" 2>/dev/null
    else
        echo "  sqlnet.ora not found"
    fi
}

discover_auth() {
    print_section "AUTHENTICATION"
    
    echo "Password File:"
    if [ -n "${ORACLE_HOME:-}" ]; then
        ls -la "$ORACLE_HOME/dbs/orapw"* 2>/dev/null || echo "  No password files found in ORACLE_HOME/dbs"
    fi
    
    echo ""
    echo "SSH Directory (oracle user):"
    if [ -d ~oracle/.ssh ]; then
        ls -la ~oracle/.ssh/ 2>/dev/null | head -10
    else
        echo "  ~oracle/.ssh not found"
    fi
}

discover_dataguard() {
    print_section "DATA GUARD CONFIGURATION"
    
    echo "DG Parameters:"
    run_sql "SELECT name, value FROM v\$parameter 
WHERE name IN ('dg_broker_start', 'log_archive_config', 'log_archive_dest_1', 'log_archive_dest_2',
               'fal_server', 'fal_client', 'standby_file_management', 'db_file_name_convert', 
               'log_file_name_convert') ORDER BY name;"
}

discover_schemas() {
    print_section "SCHEMA INFORMATION"
    
    echo "Schema Sizes (non-system schemas > 100MB):"
    run_sql "SELECT owner, ROUND(SUM(bytes)/1024/1024, 2) AS size_mb 
FROM dba_segments 
WHERE owner NOT IN ('SYS','SYSTEM','DBSNMP','OUTLN','MDSYS','ORDSYS','EXFSYS','DMSYS','WMSYS','CTXSYS',
                   'ANONYMOUS','XDB','ORDPLUGINS','OLAPSYS','APPQOSSYS','GSMADMIN_INTERNAL','ORDDATA',
                   'LBACSYS','APEX_PUBLIC_USER','FLOWS_FILES','APEX_030200','APEX_040200','APEX_050000',
                   'APEX_190200','OJVMSYS','XS\$NULL','AUDSYS','REMOTE_SCHEDULER_AGENT')
GROUP BY owner 
HAVING SUM(bytes)/1024/1024 > 100 
ORDER BY size_mb DESC;"
    
    echo ""
    echo "Invalid Objects Count:"
    run_sql "SELECT owner, object_type, COUNT(*) as invalid_count 
FROM dba_objects 
WHERE status = 'INVALID' 
GROUP BY owner, object_type 
HAVING COUNT(*) > 0 
ORDER BY owner, invalid_count DESC;"
}

# Additional discovery for PRODDB migration project
discover_tablespace_autoextend() {
    print_section "TABLESPACE AUTOEXTEND SETTINGS"
    
    run_sql "SELECT tablespace_name, file_name, autoextensible, 
       ROUND(bytes/1024/1024, 2) AS current_size_mb,
       ROUND(maxbytes/1024/1024, 2) AS max_size_mb,
       ROUND(increment_by * (SELECT value FROM v\$parameter WHERE name = 'db_block_size') / 1024 / 1024, 2) AS increment_mb
FROM dba_data_files 
ORDER BY tablespace_name;"
}

discover_backup_schedule() {
    print_section "BACKUP SCHEDULE AND RETENTION"
    
    echo "RMAN Configuration:"
    run_sql "SELECT name, value FROM v\$rman_configuration ORDER BY name;"
    
    echo ""
    echo "Recent Backup Jobs (last 7 days):"
    run_sql "SELECT session_key, start_time, end_time, status, input_type, 
       ROUND(input_bytes/1024/1024/1024, 2) AS input_gb,
       ROUND(output_bytes/1024/1024/1024, 2) AS output_gb
FROM v\$rman_backup_job_details 
WHERE start_time > SYSDATE - 7 
ORDER BY start_time DESC;"
    
    echo ""
    echo "Backup Retention:"
    run_sql "SELECT * FROM v\$backup_obsolete_summary;"
}

discover_database_links() {
    print_section "DATABASE LINKS"
    
    run_sql "SELECT owner, db_link, username, host, created 
FROM dba_db_links 
ORDER BY owner, db_link;"
}

discover_materialized_views() {
    print_section "MATERIALIZED VIEW REFRESH SCHEDULES"
    
    run_sql "SELECT owner, mview_name, refresh_mode, refresh_method, 
       last_refresh_type, last_refresh_date, 
       next_refresh_date, staleness
FROM dba_mviews 
WHERE owner NOT IN ('SYS','SYSTEM')
ORDER BY owner, mview_name;"
    
    echo ""
    echo "Materialized View Refresh Groups:"
    run_sql "SELECT rowner, rname, refgroup, next_date, interval 
FROM dba_refresh 
ORDER BY rowner, rname;"
}

discover_scheduler_jobs() {
    print_section "SCHEDULER JOBS"
    
    run_sql "SELECT owner, job_name, job_type, state, enabled, 
       last_start_date, next_run_date, 
       repeat_interval
FROM dba_scheduler_jobs 
WHERE owner NOT IN ('SYS','SYSTEM','ORACLE_OCM','EXFSYS')
ORDER BY owner, job_name;"
    
    echo ""
    echo "DBMS_JOB Jobs (legacy):"
    run_sql "SELECT job, schema_user, last_date, last_sec, next_date, next_sec, 
       broken, failures, interval, what 
FROM dba_jobs 
ORDER BY job;"
}

#===============================================================================
# Main Execution
#===============================================================================

main() {
    # Initialize environment
    detect_oracle_env
    apply_overrides
    
    # Start output file
    print_header "ZDM Source Database Discovery Report" | tee "$OUTPUT_FILE"
    echo "Generated: $(date)" | tee -a "$OUTPUT_FILE"
    echo "Hostname: $HOSTNAME" | tee -a "$OUTPUT_FILE"
    echo "Script Version: $SCRIPT_VERSION" | tee -a "$OUTPUT_FILE"
    echo "" | tee -a "$OUTPUT_FILE"
    
    # Initialize JSON
    init_json
    
    # Run discovery sections (continue on failure)
    {
        discover_os_info || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_oracle_env || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_database_config || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_cdb_pdb || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_tde || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_supplemental_logging || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_redo_archive || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_network || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_auth || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_dataguard || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_schemas || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        
        # Additional discovery for PRODDB project
        discover_tablespace_autoextend || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_backup_schedule || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_database_links || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_materialized_views || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_scheduler_jobs || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    } 2>&1 | tee -a "$OUTPUT_FILE"
    
    # Add errors to JSON and close
    add_json "section_errors" "$SECTION_ERRORS"
    close_json
    
    # Summary
    echo "" | tee -a "$OUTPUT_FILE"
    print_header "DISCOVERY COMPLETE" | tee -a "$OUTPUT_FILE"
    echo "Text Report: $OUTPUT_FILE" | tee -a "$OUTPUT_FILE"
    echo "JSON Summary: $JSON_FILE" | tee -a "$OUTPUT_FILE"
    
    if [ $SECTION_ERRORS -gt 0 ]; then
        print_warning "$SECTION_ERRORS section(s) had errors" | tee -a "$OUTPUT_FILE"
    else
        print_success "All sections completed successfully" | tee -a "$OUTPUT_FILE"
    fi
}

# Run main function
main "$@"
