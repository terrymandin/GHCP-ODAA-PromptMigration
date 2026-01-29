#!/bin/bash
################################################################################
# ZDM Source Database Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# Target Server: proddb01.corp.example.com
# Generated: 2026-01-29
#
# Purpose: Discovers comprehensive information about the source Oracle database
#          for ZDM migration planning and execution.
#
# Usage: Run as oracle user on the source database server
#        ./zdm_source_discovery.sh
#
# Output: Text report and JSON summary in current working directory
################################################################################

# NO set -e - We want to continue even if some checks fail
SECTION_ERRORS=0
SCRIPT_VERSION="1.0.0"

# Source environment for ORACLE_HOME, ORACLE_SID, etc.
for profile in ~/.bash_profile ~/.bashrc /etc/profile ~/.profile /etc/profile.d/*.sh; do
    [ -f "$profile" ] && source "$profile" 2>/dev/null || true
done

# Initialize variables
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname -s 2>/dev/null || hostname)
OUTPUT_FILE="./zdm_source_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_source_discovery_${HOSTNAME}_${TIMESTAMP}.json"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Helper Functions
################################################################################

log_section() {
    local section_name="$1"
    echo ""
    echo "================================================================================" | tee -a "$OUTPUT_FILE"
    echo "= $section_name" | tee -a "$OUTPUT_FILE"
    echo "================================================================================" | tee -a "$OUTPUT_FILE"
    echo -e "${BLUE}[INFO]${NC} Discovering: $section_name"
}

log_subsection() {
    local subsection_name="$1"
    echo "" | tee -a "$OUTPUT_FILE"
    echo "--- $subsection_name ---" | tee -a "$OUTPUT_FILE"
}

log_info() {
    echo "$1" | tee -a "$OUTPUT_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$OUTPUT_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$OUTPUT_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

run_sql() {
    local sql="$1"
    if [ -n "$ORACLE_HOME" ] && [ -n "$ORACLE_SID" ]; then
        $ORACLE_HOME/bin/sqlplus -s / as sysdba <<EOF 2>&1
SET LINESIZE 200
SET PAGESIZE 1000
SET FEEDBACK OFF
SET HEADING ON
COLUMN name FORMAT A30
COLUMN value FORMAT A50
COLUMN tablespace_name FORMAT A30
COLUMN file_name FORMAT A60
COLUMN owner FORMAT A30
COLUMN object_type FORMAT A30
$sql
EXIT;
EOF
    else
        echo "ERROR: ORACLE_HOME or ORACLE_SID not set"
        return 1
    fi
}

# Initialize JSON output
init_json() {
    cat > "$JSON_FILE" << EOF
{
  "discovery_type": "source_database",
  "project": "PRODDB Migration to Oracle Database@Azure",
  "hostname": "$HOSTNAME",
  "timestamp": "$(date -Iseconds)",
  "script_version": "$SCRIPT_VERSION",
  "sections": {}
}
EOF
}

# Update JSON with section data
update_json_section() {
    local section="$1"
    local key="$2"
    local value="$3"
    # Simple approach - we'll build complete JSON at the end
    echo "${section}|${key}|${value}" >> "${JSON_FILE}.tmp"
}

################################################################################
# Discovery Functions
################################################################################

discover_os_info() {
    log_section "OPERATING SYSTEM INFORMATION"
    
    log_subsection "Hostname and IP Addresses"
    log_info "Hostname: $HOSTNAME"
    log_info "FQDN: $(hostname -f 2>/dev/null || echo 'N/A')"
    log_info ""
    log_info "IP Addresses:"
    ip addr show 2>/dev/null | grep -E "inet |inet6 " | tee -a "$OUTPUT_FILE" || \
        ifconfig 2>/dev/null | grep -E "inet |inet6 " | tee -a "$OUTPUT_FILE" || \
        log_warning "Could not retrieve IP addresses"
    
    log_subsection "Operating System Version"
    cat /etc/os-release 2>/dev/null | tee -a "$OUTPUT_FILE" || \
        cat /etc/redhat-release 2>/dev/null | tee -a "$OUTPUT_FILE" || \
        uname -a | tee -a "$OUTPUT_FILE"
    
    log_subsection "Kernel Version"
    uname -r | tee -a "$OUTPUT_FILE"
    
    log_subsection "Disk Space"
    df -h | tee -a "$OUTPUT_FILE"
    
    log_subsection "Memory"
    free -h 2>/dev/null | tee -a "$OUTPUT_FILE" || log_warning "Could not retrieve memory info"
}

discover_oracle_environment() {
    log_section "ORACLE ENVIRONMENT"
    
    log_subsection "Environment Variables"
    log_info "ORACLE_HOME: ${ORACLE_HOME:-NOT SET}"
    log_info "ORACLE_SID: ${ORACLE_SID:-NOT SET}"
    log_info "ORACLE_BASE: ${ORACLE_BASE:-NOT SET}"
    log_info "TNS_ADMIN: ${TNS_ADMIN:-NOT SET}"
    log_info "PATH: $PATH"
    
    if [ -z "$ORACLE_HOME" ]; then
        log_error "ORACLE_HOME is not set. Database discovery may be incomplete."
        return 1
    fi
    
    log_subsection "Oracle Version"
    $ORACLE_HOME/bin/sqlplus -v 2>/dev/null | tee -a "$OUTPUT_FILE" || log_warning "Could not get SQLPlus version"
    
    log_subsection "Oracle Inventory"
    if [ -f /etc/oraInst.loc ]; then
        cat /etc/oraInst.loc | tee -a "$OUTPUT_FILE"
    else
        log_warning "/etc/oraInst.loc not found"
    fi
}

discover_database_config() {
    log_section "DATABASE CONFIGURATION"
    
    log_subsection "Database Identification"
    run_sql "
    SELECT name, db_unique_name, dbid, created, 
           log_mode, force_logging, flashback_on
    FROM v\$database;
    " | tee -a "$OUTPUT_FILE"
    
    log_subsection "Instance Information"
    run_sql "
    SELECT instance_name, host_name, version_full, status,
           database_status, instance_role, active_state
    FROM v\$instance;
    " | tee -a "$OUTPUT_FILE"
    
    log_subsection "Database Role and Open Mode"
    run_sql "
    SELECT database_role, open_mode, protection_mode, 
           protection_level, switchover_status
    FROM v\$database;
    " | tee -a "$OUTPUT_FILE"
    
    log_subsection "Database Size"
    run_sql "
    SELECT 'Data Files' as type, 
           ROUND(SUM(bytes)/1024/1024/1024, 2) as size_gb 
    FROM dba_data_files
    UNION ALL
    SELECT 'Temp Files', 
           ROUND(SUM(bytes)/1024/1024/1024, 2) 
    FROM dba_temp_files
    UNION ALL
    SELECT 'Redo Logs', 
           ROUND(SUM(bytes)/1024/1024/1024, 2) 
    FROM v\$log;
    " | tee -a "$OUTPUT_FILE"
    
    log_subsection "Character Set"
    run_sql "
    SELECT parameter, value 
    FROM nls_database_parameters 
    WHERE parameter IN ('NLS_CHARACTERSET', 'NLS_NCHAR_CHARACTERSET', 
                        'NLS_LANGUAGE', 'NLS_TERRITORY');
    " | tee -a "$OUTPUT_FILE"
}

discover_cdb_pdb() {
    log_section "CONTAINER DATABASE CONFIGURATION"
    
    log_subsection "CDB Status"
    run_sql "SELECT cdb FROM v\$database;" | tee -a "$OUTPUT_FILE"
    
    log_subsection "PDB Information"
    run_sql "
    SELECT con_id, name, open_mode, restricted, 
           recovery_status, application_root
    FROM v\$pdbs ORDER BY con_id;
    " | tee -a "$OUTPUT_FILE"
    
    log_subsection "PDB Size"
    run_sql "
    SELECT c.name as pdb_name,
           ROUND(SUM(d.bytes)/1024/1024/1024, 2) as size_gb
    FROM v\$containers c
    JOIN cdb_data_files d ON c.con_id = d.con_id
    GROUP BY c.name
    ORDER BY c.name;
    " | tee -a "$OUTPUT_FILE"
}

discover_tde_config() {
    log_section "TDE CONFIGURATION"
    
    log_subsection "TDE Status"
    run_sql "
    SELECT wrl_type, wrl_parameter, status, wallet_type, 
           wallet_order, keystore_mode
    FROM v\$encryption_wallet;
    " | tee -a "$OUTPUT_FILE"
    
    log_subsection "Encrypted Tablespaces"
    run_sql "
    SELECT tablespace_name, encrypted, status
    FROM dba_tablespaces
    WHERE encrypted = 'YES'
    ORDER BY tablespace_name;
    " | tee -a "$OUTPUT_FILE"
    
    log_subsection "Encryption Keys"
    run_sql "
    SELECT key_id, keystore_type, creation_time, 
           activation_time, creator_dbname
    FROM v\$encryption_keys;
    " | tee -a "$OUTPUT_FILE"
    
    log_subsection "Wallet File Location"
    if [ -f "$ORACLE_BASE/admin/$ORACLE_SID/wallet" ]; then
        ls -la "$ORACLE_BASE/admin/$ORACLE_SID/wallet/" 2>/dev/null | tee -a "$OUTPUT_FILE"
    fi
    if [ -d "$ORACLE_HOME/admin/$ORACLE_SID/wallet" ]; then
        ls -la "$ORACLE_HOME/admin/$ORACLE_SID/wallet/" 2>/dev/null | tee -a "$OUTPUT_FILE"
    fi
    run_sql "SHOW PARAMETER wallet_root;" | tee -a "$OUTPUT_FILE"
    run_sql "SHOW PARAMETER tde_configuration;" | tee -a "$OUTPUT_FILE"
}

discover_supplemental_logging() {
    log_section "SUPPLEMENTAL LOGGING"
    
    log_subsection "Database Level Supplemental Logging"
    run_sql "
    SELECT supplemental_log_data_min as min_log,
           supplemental_log_data_pk as pk_log,
           supplemental_log_data_ui as ui_log,
           supplemental_log_data_fk as fk_log,
           supplemental_log_data_all as all_log
    FROM v\$database;
    " | tee -a "$OUTPUT_FILE"
}

discover_redo_archive() {
    log_section "REDO AND ARCHIVE CONFIGURATION"
    
    log_subsection "Redo Log Groups"
    run_sql "
    SELECT group#, thread#, sequence#, bytes/1024/1024 as size_mb,
           members, archived, status
    FROM v\$log ORDER BY group#;
    " | tee -a "$OUTPUT_FILE"
    
    log_subsection "Redo Log Members"
    run_sql "
    SELECT group#, member, type, status
    FROM v\$logfile ORDER BY group#;
    " | tee -a "$OUTPUT_FILE"
    
    log_subsection "Archive Log Mode"
    run_sql "SELECT log_mode FROM v\$database;" | tee -a "$OUTPUT_FILE"
    
    log_subsection "Archive Log Destinations"
    run_sql "
    SELECT dest_id, dest_name, status, target, 
           destination, schedule, process
    FROM v\$archive_dest
    WHERE status = 'VALID' OR destination IS NOT NULL;
    " | tee -a "$OUTPUT_FILE"
}

discover_network() {
    log_section "NETWORK CONFIGURATION"
    
    log_subsection "Listener Status"
    if [ -n "$ORACLE_HOME" ]; then
        $ORACLE_HOME/bin/lsnrctl status 2>&1 | tee -a "$OUTPUT_FILE" || \
            log_warning "Could not get listener status"
    fi
    
    log_subsection "tnsnames.ora"
    local tnsnames="${TNS_ADMIN:-$ORACLE_HOME/network/admin}/tnsnames.ora"
    if [ -f "$tnsnames" ]; then
        log_info "File: $tnsnames"
        cat "$tnsnames" 2>/dev/null | tee -a "$OUTPUT_FILE"
    else
        log_warning "tnsnames.ora not found at $tnsnames"
    fi
    
    log_subsection "sqlnet.ora"
    local sqlnet="${TNS_ADMIN:-$ORACLE_HOME/network/admin}/sqlnet.ora"
    if [ -f "$sqlnet" ]; then
        log_info "File: $sqlnet"
        cat "$sqlnet" 2>/dev/null | tee -a "$OUTPUT_FILE"
    else
        log_warning "sqlnet.ora not found at $sqlnet"
    fi
    
    log_subsection "listener.ora"
    local listener="${TNS_ADMIN:-$ORACLE_HOME/network/admin}/listener.ora"
    if [ -f "$listener" ]; then
        log_info "File: $listener"
        cat "$listener" 2>/dev/null | tee -a "$OUTPUT_FILE"
    else
        log_warning "listener.ora not found at $listener"
    fi
}

discover_authentication() {
    log_section "AUTHENTICATION CONFIGURATION"
    
    log_subsection "Password File"
    local pwfile="$ORACLE_HOME/dbs/orapw$ORACLE_SID"
    if [ -f "$pwfile" ]; then
        log_info "Password file exists: $pwfile"
        ls -la "$pwfile" | tee -a "$OUTPUT_FILE"
    else
        log_warning "Password file not found at $pwfile"
        # Check ASM location
        log_info "Checking for password file in ASM or alternative locations..."
        run_sql "SELECT file_type, status, format FROM v\$passwordfile_info;" | tee -a "$OUTPUT_FILE"
    fi
    
    log_subsection "SSH Directory"
    if [ -d ~/.ssh ]; then
        ls -la ~/.ssh/ 2>/dev/null | tee -a "$OUTPUT_FILE"
    else
        log_warning "~/.ssh directory not found"
    fi
}

discover_dataguard() {
    log_section "DATA GUARD CONFIGURATION"
    
    log_subsection "Data Guard Parameters"
    run_sql "
    SHOW PARAMETER log_archive_config;
    SHOW PARAMETER log_archive_dest_1;
    SHOW PARAMETER log_archive_dest_2;
    SHOW PARAMETER log_archive_dest_state_1;
    SHOW PARAMETER log_archive_dest_state_2;
    SHOW PARAMETER fal_server;
    SHOW PARAMETER fal_client;
    SHOW PARAMETER db_file_name_convert;
    SHOW PARAMETER log_file_name_convert;
    SHOW PARAMETER standby_file_management;
    " | tee -a "$OUTPUT_FILE"
    
    log_subsection "Data Guard Status"
    run_sql "
    SELECT database_role, protection_mode, protection_level,
           switchover_status, dataguard_broker
    FROM v\$database;
    " | tee -a "$OUTPUT_FILE"
}

discover_schema_info() {
    log_section "SCHEMA INFORMATION"
    
    log_subsection "Schema Sizes (Non-System Schemas > 100MB)"
    run_sql "
    SELECT owner, 
           ROUND(SUM(bytes)/1024/1024/1024, 2) as size_gb,
           COUNT(*) as segment_count
    FROM dba_segments
    WHERE owner NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS',
                        'DBSFWUSER','DIP','GGSYS','GSMADMIN_INTERNAL',
                        'GSMCATUSER','GSMUSER','LBACSYS','MDSYS','OJVMSYS',
                        'OLAPSYS','ORDDATA','ORDPLUGINS','ORDSYS','REMOTE_SCHEDULER_AGENT',
                        'SI_INFORMTN_SCHEMA','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR',
                        'SYS$UMF','SYSBACKUP','SYSDG','SYSKM','SYSRAC','WMSYS','XDB','ANONYMOUS',
                        'APEX_PUBLIC_USER','FLOWS_FILES','APEX_040000','APEX_050000',
                        'APEX_190100','APEX_200100','APEX_210100')
    GROUP BY owner
    HAVING SUM(bytes)/1024/1024 > 100
    ORDER BY size_gb DESC;
    " | tee -a "$OUTPUT_FILE"
    
    log_subsection "Invalid Objects Count by Owner/Type"
    run_sql "
    SELECT owner, object_type, COUNT(*) as invalid_count
    FROM dba_objects
    WHERE status = 'INVALID'
    GROUP BY owner, object_type
    ORDER BY owner, object_type;
    " | tee -a "$OUTPUT_FILE"
}

################################################################################
# Additional Custom Discovery (PRODDB Specific Requirements)
################################################################################

discover_tablespace_autoextend() {
    log_section "TABLESPACE AUTOEXTEND SETTINGS"
    
    log_subsection "Data File Autoextend Configuration"
    run_sql "
    SELECT tablespace_name, file_name, 
           ROUND(bytes/1024/1024/1024, 2) as current_size_gb,
           autoextensible as autoextend,
           ROUND(maxbytes/1024/1024/1024, 2) as max_size_gb,
           ROUND(increment_by * (SELECT value FROM v\$parameter WHERE name='db_block_size') /1024/1024, 2) as increment_mb
    FROM dba_data_files
    ORDER BY tablespace_name, file_name;
    " | tee -a "$OUTPUT_FILE"
    
    log_subsection "Temp File Autoextend Configuration"
    run_sql "
    SELECT tablespace_name, file_name,
           ROUND(bytes/1024/1024/1024, 2) as current_size_gb,
           autoextensible as autoextend,
           ROUND(maxbytes/1024/1024/1024, 2) as max_size_gb
    FROM dba_temp_files
    ORDER BY tablespace_name;
    " | tee -a "$OUTPUT_FILE"
}

discover_backup_schedule() {
    log_section "BACKUP SCHEDULE AND RETENTION"
    
    log_subsection "RMAN Configuration"
    if [ -n "$ORACLE_HOME" ] && [ -n "$ORACLE_SID" ]; then
        $ORACLE_HOME/bin/rman target / << EOF 2>&1 | tee -a "$OUTPUT_FILE"
SHOW ALL;
EXIT;
EOF
    else
        log_warning "Cannot query RMAN - ORACLE_HOME or ORACLE_SID not set"
    fi
    
    log_subsection "Backup History (Last 7 Days)"
    run_sql "
    SELECT session_key, input_type, status,
           TO_CHAR(start_time, 'YYYY-MM-DD HH24:MI:SS') as start_time,
           TO_CHAR(end_time, 'YYYY-MM-DD HH24:MI:SS') as end_time,
           ROUND(input_bytes/1024/1024/1024, 2) as input_gb,
           ROUND(output_bytes/1024/1024/1024, 2) as output_gb
    FROM v\$rman_backup_job_details
    WHERE start_time > SYSDATE - 7
    ORDER BY start_time DESC;
    " | tee -a "$OUTPUT_FILE"
    
    log_subsection "Recovery Window/Retention Policy"
    run_sql "
    SELECT name, value 
    FROM v\$rman_configuration
    WHERE name LIKE '%RETENTION%' OR name LIKE '%WINDOW%';
    " | tee -a "$OUTPUT_FILE"
}

discover_database_links() {
    log_section "DATABASE LINKS"
    
    log_subsection "All Database Links"
    run_sql "
    SELECT owner, db_link, username, host, created
    FROM dba_db_links
    ORDER BY owner, db_link;
    " | tee -a "$OUTPUT_FILE"
    
    log_subsection "Public Database Links"
    run_sql "
    SELECT db_link, username, host, created
    FROM dba_db_links
    WHERE owner = 'PUBLIC'
    ORDER BY db_link;
    " | tee -a "$OUTPUT_FILE"
}

discover_materialized_views() {
    log_section "MATERIALIZED VIEW REFRESH SCHEDULES"
    
    log_subsection "Materialized View Details"
    run_sql "
    SELECT owner, mview_name, container_name,
           refresh_mode, refresh_method,
           TO_CHAR(last_refresh_date, 'YYYY-MM-DD HH24:MI:SS') as last_refresh,
           staleness, compile_state
    FROM dba_mviews
    WHERE owner NOT IN ('SYS','SYSTEM')
    ORDER BY owner, mview_name;
    " | tee -a "$OUTPUT_FILE"
    
    log_subsection "Refresh Groups"
    run_sql "
    SELECT rowner, rname, refgroup, implicit_destroy,
           push_deferred_rpc, refresh_after_errors
    FROM dba_refresh
    ORDER BY rowner, rname;
    " | tee -a "$OUTPUT_FILE"
    
    log_subsection "Refresh Group Children (MView Schedules)"
    run_sql "
    SELECT rowner, rname, name as mview_name,
           TO_CHAR(next_date, 'YYYY-MM-DD HH24:MI:SS') as next_refresh,
           interval
    FROM dba_refresh_children
    ORDER BY rowner, rname;
    " | tee -a "$OUTPUT_FILE"
}

discover_scheduler_jobs() {
    log_section "SCHEDULER JOBS"
    
    log_subsection "All Scheduler Jobs"
    run_sql "
    SELECT owner, job_name, job_type, state, enabled,
           TO_CHAR(last_start_date, 'YYYY-MM-DD HH24:MI:SS') as last_start,
           TO_CHAR(next_run_date, 'YYYY-MM-DD HH24:MI:SS') as next_run,
           repeat_interval
    FROM dba_scheduler_jobs
    WHERE owner NOT IN ('SYS','SYSTEM','ORACLE_OCM','EXFSYS')
    ORDER BY owner, job_name;
    " | tee -a "$OUTPUT_FILE"
    
    log_subsection "Scheduler Job Details"
    run_sql "
    SELECT owner, job_name, job_action, schedule_type,
           number_of_arguments, auto_drop
    FROM dba_scheduler_jobs
    WHERE owner NOT IN ('SYS','SYSTEM','ORACLE_OCM','EXFSYS')
    ORDER BY owner, job_name;
    " | tee -a "$OUTPUT_FILE"
    
    log_subsection "DBMS_JOB Legacy Jobs"
    run_sql "
    SELECT job, log_user, priv_user, schema_user,
           TO_CHAR(last_date, 'YYYY-MM-DD HH24:MI:SS') as last_run,
           TO_CHAR(next_date, 'YYYY-MM-DD HH24:MI:SS') as next_run,
           interval, broken, what
    FROM dba_jobs
    ORDER BY job;
    " | tee -a "$OUTPUT_FILE"
}

################################################################################
# Main Execution
################################################################################

main() {
    echo "" | tee "$OUTPUT_FILE"
    echo "================================================================================" | tee -a "$OUTPUT_FILE"
    echo "= ZDM Source Database Discovery Report" | tee -a "$OUTPUT_FILE"
    echo "= Project: PRODDB Migration to Oracle Database@Azure" | tee -a "$OUTPUT_FILE"
    echo "= Server: proddb01.corp.example.com" | tee -a "$OUTPUT_FILE"
    echo "= Hostname: $HOSTNAME" | tee -a "$OUTPUT_FILE"
    echo "= Timestamp: $(date)" | tee -a "$OUTPUT_FILE"
    echo "= Script Version: $SCRIPT_VERSION" | tee -a "$OUTPUT_FILE"
    echo "================================================================================" | tee -a "$OUTPUT_FILE"
    
    init_json
    
    # Run all discovery functions - continue even if some fail
    discover_os_info || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_oracle_environment || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_database_config || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_cdb_pdb || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_tde_config || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_supplemental_logging || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_redo_archive || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_network || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_authentication || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_dataguard || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_schema_info || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    
    # Additional PRODDB-specific discovery
    discover_tablespace_autoextend || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_backup_schedule || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_database_links || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_materialized_views || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_scheduler_jobs || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    
    # Summary
    log_section "DISCOVERY SUMMARY"
    log_info "Discovery completed at: $(date)"
    log_info "Section errors encountered: $SECTION_ERRORS"
    log_info "Text report: $OUTPUT_FILE"
    log_info "JSON summary: $JSON_FILE"
    
    # Build final JSON
    cat > "$JSON_FILE" << EOF
{
  "discovery_type": "source_database",
  "project": "PRODDB Migration to Oracle Database@Azure",
  "target_server": "proddb01.corp.example.com",
  "hostname": "$HOSTNAME",
  "timestamp": "$(date -Iseconds 2>/dev/null || date)",
  "script_version": "$SCRIPT_VERSION",
  "oracle_home": "${ORACLE_HOME:-null}",
  "oracle_sid": "${ORACLE_SID:-null}",
  "section_errors": $SECTION_ERRORS,
  "output_files": {
    "text_report": "$OUTPUT_FILE",
    "json_summary": "$JSON_FILE"
  }
}
EOF
    
    echo ""
    log_success "Discovery complete!"
    echo ""
    echo "Output files:"
    echo "  Text Report: $OUTPUT_FILE"
    echo "  JSON Summary: $JSON_FILE"
    echo ""
    
    # Always exit 0 so orchestrator knows script completed
    exit 0
}

# Run main
main "$@"
