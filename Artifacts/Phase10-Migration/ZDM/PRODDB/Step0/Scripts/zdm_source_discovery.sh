#!/bin/bash
# =============================================================================
# ZDM Source Database Discovery Script
# =============================================================================
# Project: PRODDB Migration to Oracle Database@Azure
# Source Server: proddb01.corp.example.com
# Generated: 2026-01-30
#
# Purpose:
#   Gather comprehensive discovery information from the source database server
#   to support ZDM migration planning and execution.
#
# Execution:
#   This script is executed via SSH as the admin user (oracle), with SQL 
#   commands running as the oracle user via sudo if needed.
#
# Output:
#   - Text report: ./zdm_source_discovery_<hostname>_<timestamp>.txt
#   - JSON summary: ./zdm_source_discovery_<hostname>_<timestamp>.json
# =============================================================================

# NO set -e - We want to continue even if some checks fail
SECTION_ERRORS=0

# =============================================================================
# COLOR CONFIGURATION
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# =============================================================================
# USER CONFIGURATION
# =============================================================================
# Oracle database software owner (for running SQL commands)
ORACLE_USER="${ORACLE_USER:-oracle}"

# =============================================================================
# ENVIRONMENT VARIABLE DISCOVERY
# =============================================================================

# CRITICAL: Handle environment variables in non-interactive SSH sessions
# .bashrc often has guards like '[ -z "$PS1" ] && return' that skip non-interactive shells

# Method 1: Accept explicit overrides (passed from orchestration script - highest priority)
[ -n "${ORACLE_HOME_OVERRIDE:-}" ] && export ORACLE_HOME="$ORACLE_HOME_OVERRIDE"
[ -n "${ORACLE_SID_OVERRIDE:-}" ] && export ORACLE_SID="$ORACLE_SID_OVERRIDE"
[ -n "${ORACLE_BASE_OVERRIDE:-}" ] && export ORACLE_BASE="$ORACLE_BASE_OVERRIDE"

# Method 2: Extract export statements from profiles (bypasses interactive guards)
for profile in /etc/profile ~/.bash_profile ~/.bashrc; do
    if [ -f "$profile" ]; then
        eval "$(grep -E '^export\s+(ORACLE_HOME|ORACLE_SID|ORACLE_BASE|TNS_ADMIN|PATH)=' "$profile" 2>/dev/null)" || true
    fi
done

# Method 3: Auto-detect Oracle environment
detect_oracle_env() {
    # If already set, use existing values
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        return 0
    fi
    
    # Try oratab first (most reliable)
    if [ -f /etc/oratab ]; then
        local oratab_entry
        if [ -n "${ORACLE_SID:-}" ]; then
            oratab_entry=$(grep "^${ORACLE_SID}:" /etc/oratab 2>/dev/null | head -1)
        else
            oratab_entry=$(grep -v '^#' /etc/oratab | grep -v '^$' | grep ':' | head -1)
        fi
        if [ -n "$oratab_entry" ]; then
            export ORACLE_SID="${ORACLE_SID:-$(echo "$oratab_entry" | cut -d: -f1)}"
            export ORACLE_HOME="${ORACLE_HOME:-$(echo "$oratab_entry" | cut -d: -f2)}"
        fi
    fi
    
    # Check running pmon process
    if [ -z "${ORACLE_SID:-}" ]; then
        local pmon_sid
        pmon_sid=$(ps -ef | grep 'ora_pmon_' | grep -v grep | head -1 | sed 's/.*ora_pmon_//')
        [ -n "$pmon_sid" ] && export ORACLE_SID="$pmon_sid"
    fi
    
    # Search common Oracle installation paths
    if [ -z "${ORACLE_HOME:-}" ]; then
        for path in /u01/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1 /oracle/product/*/dbhome_1; do
            if [ -d "$path" ] && [ -f "$path/bin/sqlplus" ]; then
                export ORACLE_HOME="$path"
                break
            fi
        done
    fi
    
    # Try oraenv if available
    if [ -z "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        [ -f /usr/local/bin/oraenv ] && . /usr/local/bin/oraenv <<< "$ORACLE_SID" 2>/dev/null
    fi
    
    # Derive ORACLE_BASE if not set
    if [ -z "${ORACLE_BASE:-}" ] && [ -n "${ORACLE_HOME:-}" ]; then
        export ORACLE_BASE=$(echo "$ORACLE_HOME" | sed 's|/product/.*||')
    fi
}

detect_oracle_env

# =============================================================================
# OUTPUT CONFIGURATION
# =============================================================================
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname)
OUTPUT_FILE="./zdm_source_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_source_discovery_${HOSTNAME}_${TIMESTAMP}.json"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

log_section() {
    local section_name="$1"
    echo "" | tee -a "$OUTPUT_FILE"
    echo "=============================================================================" | tee -a "$OUTPUT_FILE"
    echo " $section_name" | tee -a "$OUTPUT_FILE"
    echo "=============================================================================" | tee -a "$OUTPUT_FILE"
    echo -e "${CYAN}[SECTION]${NC} $section_name"
}

log_info() {
    echo "$1" | tee -a "$OUTPUT_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    echo "[SUCCESS] $1" >> "$OUTPUT_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "[WARNING] $1" >> "$OUTPUT_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[ERROR] $1" >> "$OUTPUT_FILE"
}

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
            echo "$sql_script" | ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd 2>&1
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
    run_sql "$sql_query" | grep -v '^$' | tail -1 | xargs
}

# =============================================================================
# INITIALIZE JSON OUTPUT
# =============================================================================
init_json() {
    cat > "$JSON_FILE" <<EOF
{
  "discovery_type": "source",
  "timestamp": "$(date -Iseconds)",
  "hostname": "$HOSTNAME",
  "project": "PRODDB Migration to Oracle Database@Azure",
  "source_server": "proddb01.corp.example.com",
EOF
}

append_json() {
    local key="$1"
    local value="$2"
    echo "  \"$key\": \"$value\"," >> "$JSON_FILE"
}

append_json_object() {
    local key="$1"
    local value="$2"
    echo "  \"$key\": $value," >> "$JSON_FILE"
}

finalize_json() {
    echo "  \"discovery_complete\": true" >> "$JSON_FILE"
    echo "}" >> "$JSON_FILE"
}

# =============================================================================
# DISCOVERY FUNCTIONS
# =============================================================================

discover_os_info() {
    log_section "OPERATING SYSTEM INFORMATION"
    
    log_info "Hostname: $(hostname)"
    log_info "FQDN: $(hostname -f 2>/dev/null || hostname)"
    log_info ""
    
    log_info "IP Addresses:"
    ip addr show 2>/dev/null | grep "inet " | awk '{print $2}' | tee -a "$OUTPUT_FILE" || \
        ifconfig 2>/dev/null | grep "inet " | awk '{print $2}' | tee -a "$OUTPUT_FILE" || \
        hostname -I 2>/dev/null | tee -a "$OUTPUT_FILE"
    log_info ""
    
    log_info "Operating System:"
    cat /etc/os-release 2>/dev/null | head -5 | tee -a "$OUTPUT_FILE" || \
        cat /etc/redhat-release 2>/dev/null | tee -a "$OUTPUT_FILE" || \
        uname -a | tee -a "$OUTPUT_FILE"
    log_info ""
    
    log_info "Kernel Version: $(uname -r)"
    log_info ""
    
    log_info "Disk Space:"
    df -h 2>/dev/null | tee -a "$OUTPUT_FILE"
    log_info ""
    
    log_info "Memory:"
    free -h 2>/dev/null | tee -a "$OUTPUT_FILE" || cat /proc/meminfo | head -3 | tee -a "$OUTPUT_FILE"
    
    append_json "hostname" "$HOSTNAME"
    append_json "os_version" "$(cat /etc/os-release 2>/dev/null | grep '^VERSION=' | cut -d= -f2 | tr -d '\"')"
}

discover_oracle_environment() {
    log_section "ORACLE ENVIRONMENT"
    
    log_info "ORACLE_HOME: ${ORACLE_HOME:-NOT SET}"
    log_info "ORACLE_SID: ${ORACLE_SID:-NOT SET}"
    log_info "ORACLE_BASE: ${ORACLE_BASE:-NOT SET}"
    log_info "TNS_ADMIN: ${TNS_ADMIN:-NOT SET (defaults to \$ORACLE_HOME/network/admin)}"
    log_info ""
    
    if [ -n "${ORACLE_HOME:-}" ] && [ -f "$ORACLE_HOME/bin/sqlplus" ]; then
        log_info "Oracle Version:"
        $ORACLE_HOME/bin/sqlplus -v 2>/dev/null | tee -a "$OUTPUT_FILE"
        
        local ora_version
        ora_version=$(run_sql_value "SELECT banner FROM v\$version WHERE rownum = 1;")
        log_info "Database Banner: $ora_version"
        
        append_json "oracle_home" "$ORACLE_HOME"
        append_json "oracle_sid" "$ORACLE_SID"
        append_json "oracle_version" "$ora_version"
    else
        log_warning "ORACLE_HOME not found or sqlplus not available"
    fi
    
    log_info ""
    log_info "oratab Contents:"
    cat /etc/oratab 2>/dev/null | grep -v '^#' | grep -v '^$' | tee -a "$OUTPUT_FILE" || log_info "oratab not found"
}

discover_database_config() {
    log_section "DATABASE CONFIGURATION"
    
    log_info "Database Name and Identity:"
    run_sql "SELECT name, db_unique_name, dbid, open_mode, database_role, log_mode, force_logging FROM v\$database;" | tee -a "$OUTPUT_FILE"
    
    local db_name=$(run_sql_value "SELECT name FROM v\$database;")
    local db_unique_name=$(run_sql_value "SELECT db_unique_name FROM v\$database;")
    local dbid=$(run_sql_value "SELECT dbid FROM v\$database;")
    local log_mode=$(run_sql_value "SELECT log_mode FROM v\$database;")
    local force_logging=$(run_sql_value "SELECT force_logging FROM v\$database;")
    
    append_json "database_name" "$db_name"
    append_json "database_unique_name" "$db_unique_name"
    append_json "dbid" "$dbid"
    append_json "log_mode" "$log_mode"
    append_json "force_logging" "$force_logging"
    
    log_info ""
    log_info "Database Size:"
    run_sql "
    SELECT 'Data Files' as file_type, ROUND(SUM(bytes)/1024/1024/1024, 2) as size_gb FROM dba_data_files
    UNION ALL
    SELECT 'Temp Files', ROUND(SUM(bytes)/1024/1024/1024, 2) FROM dba_temp_files
    UNION ALL
    SELECT 'Redo Logs', ROUND(SUM(bytes)/1024/1024/1024, 2) FROM v\$log;" | tee -a "$OUTPUT_FILE"
    
    log_info ""
    log_info "Character Set:"
    run_sql "SELECT parameter, value FROM nls_database_parameters WHERE parameter IN ('NLS_CHARACTERSET', 'NLS_NCHAR_CHARACTERSET');" | tee -a "$OUTPUT_FILE"
    
    local charset=$(run_sql_value "SELECT value FROM nls_database_parameters WHERE parameter = 'NLS_CHARACTERSET';")
    append_json "character_set" "$charset"
}

discover_cdb_pdb() {
    log_section "CONTAINER DATABASE (CDB/PDB)"
    
    local cdb_status=$(run_sql_value "SELECT cdb FROM v\$database;")
    log_info "CDB Status: $cdb_status"
    append_json "is_cdb" "$cdb_status"
    
    if [ "$cdb_status" = "YES" ]; then
        log_info ""
        log_info "Container Name:"
        run_sql "SELECT sys_context('USERENV', 'CON_NAME') as current_container FROM dual;" | tee -a "$OUTPUT_FILE"
        
        log_info ""
        log_info "PDB Status:"
        run_sql "SELECT con_id, name, open_mode, restricted FROM v\$pdbs ORDER BY con_id;" | tee -a "$OUTPUT_FILE"
        
        log_info ""
        log_info "PDB Services:"
        run_sql "SELECT pdb, name, network_name FROM cdb_services WHERE pdb IS NOT NULL ORDER BY pdb;" | tee -a "$OUTPUT_FILE"
    else
        log_info "Database is non-CDB"
    fi
}

discover_tde_config() {
    log_section "TDE CONFIGURATION"
    
    log_info "Encryption Wallet Status:"
    run_sql "SELECT wrl_type, wrl_parameter, status, wallet_type FROM v\$encryption_wallet;" | tee -a "$OUTPUT_FILE"
    
    local wallet_status=$(run_sql_value "SELECT status FROM v\$encryption_wallet WHERE rownum = 1;")
    local wallet_type=$(run_sql_value "SELECT wallet_type FROM v\$encryption_wallet WHERE rownum = 1;")
    append_json "tde_wallet_status" "$wallet_status"
    append_json "tde_wallet_type" "$wallet_type"
    
    log_info ""
    log_info "Encrypted Tablespaces:"
    run_sql "SELECT tablespace_name, encrypted FROM dba_tablespaces WHERE encrypted = 'YES';" | tee -a "$OUTPUT_FILE"
    
    log_info ""
    log_info "Encrypted Columns:"
    run_sql "SELECT owner, table_name, column_name, encryption_alg FROM dba_encrypted_columns ORDER BY owner, table_name;" | tee -a "$OUTPUT_FILE"
}

discover_supplemental_logging() {
    log_section "SUPPLEMENTAL LOGGING"
    
    run_sql "
    SELECT 
        supplemental_log_data_min as log_min,
        supplemental_log_data_pk as log_pk,
        supplemental_log_data_ui as log_ui,
        supplemental_log_data_fk as log_fk,
        supplemental_log_data_all as log_all
    FROM v\$database;" | tee -a "$OUTPUT_FILE"
    
    local supp_min=$(run_sql_value "SELECT supplemental_log_data_min FROM v\$database;")
    append_json "supplemental_logging_min" "$supp_min"
}

discover_redo_archive() {
    log_section "REDO LOG AND ARCHIVE CONFIGURATION"
    
    log_info "Redo Log Groups:"
    run_sql "SELECT group#, thread#, sequence#, bytes/1024/1024 as size_mb, members, status FROM v\$log ORDER BY group#;" | tee -a "$OUTPUT_FILE"
    
    log_info ""
    log_info "Redo Log Members:"
    run_sql "SELECT group#, member, type, status FROM v\$logfile ORDER BY group#, member;" | tee -a "$OUTPUT_FILE"
    
    log_info ""
    log_info "Archive Log Destinations:"
    run_sql "SELECT dest_id, dest_name, status, destination FROM v\$archive_dest WHERE status = 'VALID' OR destination IS NOT NULL;" | tee -a "$OUTPUT_FILE"
    
    log_info ""
    log_info "Archive Log Mode Parameters:"
    run_sql "SELECT name, value FROM v\$parameter WHERE name LIKE 'log_archive%' ORDER BY name;" | tee -a "$OUTPUT_FILE"
}

discover_network_config() {
    log_section "NETWORK CONFIGURATION"
    
    log_info "Listener Status:"
    if [ -n "${ORACLE_HOME:-}" ]; then
        $ORACLE_HOME/bin/lsnrctl status 2>&1 | tee -a "$OUTPUT_FILE" || log_warning "Could not get listener status"
    fi
    
    log_info ""
    log_info "tnsnames.ora:"
    local tns_admin="${TNS_ADMIN:-$ORACLE_HOME/network/admin}"
    if [ -f "$tns_admin/tnsnames.ora" ]; then
        cat "$tns_admin/tnsnames.ora" 2>/dev/null | tee -a "$OUTPUT_FILE"
    else
        log_warning "tnsnames.ora not found at $tns_admin/tnsnames.ora"
    fi
    
    log_info ""
    log_info "sqlnet.ora:"
    if [ -f "$tns_admin/sqlnet.ora" ]; then
        cat "$tns_admin/sqlnet.ora" 2>/dev/null | tee -a "$OUTPUT_FILE"
    else
        log_warning "sqlnet.ora not found at $tns_admin/sqlnet.ora"
    fi
    
    log_info ""
    log_info "listener.ora:"
    if [ -f "$tns_admin/listener.ora" ]; then
        cat "$tns_admin/listener.ora" 2>/dev/null | tee -a "$OUTPUT_FILE"
    else
        log_warning "listener.ora not found at $tns_admin/listener.ora"
    fi
}

discover_authentication() {
    log_section "AUTHENTICATION AND SSH"
    
    log_info "Password File:"
    if [ -n "${ORACLE_HOME:-}" ]; then
        ls -la "$ORACLE_HOME/dbs/orapw"* 2>/dev/null | tee -a "$OUTPUT_FILE" || \
            ls -la "$ORACLE_BASE/admin/*/dbs/orapw"* 2>/dev/null | tee -a "$OUTPUT_FILE" || \
            log_warning "Password file not found in standard locations"
    fi
    
    log_info ""
    log_info "SSH Directory (~/.ssh):"
    ls -la ~/.ssh/ 2>/dev/null | tee -a "$OUTPUT_FILE" || log_warning "SSH directory not found or not accessible"
    
    log_info ""
    log_info "SSH Authorized Keys:"
    if [ -f ~/.ssh/authorized_keys ]; then
        wc -l ~/.ssh/authorized_keys | tee -a "$OUTPUT_FILE"
    else
        log_warning "No authorized_keys file found"
    fi
}

discover_dataguard() {
    log_section "DATA GUARD CONFIGURATION"
    
    log_info "Data Guard Parameters:"
    run_sql "
    SELECT name, value 
    FROM v\$parameter 
    WHERE name IN (
        'dg_broker_start', 'dg_broker_config_file1', 'dg_broker_config_file2',
        'log_archive_config', 'log_archive_dest_1', 'log_archive_dest_2',
        'log_archive_dest_state_1', 'log_archive_dest_state_2',
        'fal_server', 'fal_client', 'standby_file_management',
        'db_file_name_convert', 'log_file_name_convert'
    ) ORDER BY name;" | tee -a "$OUTPUT_FILE"
    
    log_info ""
    log_info "Archive Dest Status:"
    run_sql "SELECT dest_id, status, type, srl, database_mode, recovery_mode, destination FROM v\$archive_dest_status WHERE status != 'INACTIVE';" | tee -a "$OUTPUT_FILE"
}

discover_schema_info() {
    log_section "SCHEMA INFORMATION"
    
    log_info "Schema Sizes (non-system schemas > 100MB):"
    run_sql "
    SELECT owner, 
           ROUND(SUM(bytes)/1024/1024/1024, 2) as size_gb,
           COUNT(*) as segment_count
    FROM dba_segments
    WHERE owner NOT IN ('SYS','SYSTEM','OUTLN','DIP','ORACLE_OCM','DBSNMP','APPQOSSYS',
                        'WMSYS','EXFSYS','CTXSYS','XDB','ORDSYS','ORDDATA','MDSYS',
                        'OLAPSYS','SYSMAN','FLOWS_FILES','APEX_PUBLIC_USER','ANONYMOUS',
                        'XS\$NULL','GSMADMIN_INTERNAL','GGSYS','GGSHARDCAT','GSMCATUSER',
                        'GSMUSER','REMOTE_SCHEDULER_AGENT','SYSBACKUP','SYSDG','SYSKM','SYSRAC')
    GROUP BY owner
    HAVING SUM(bytes)/1024/1024 > 100
    ORDER BY SUM(bytes) DESC;" | tee -a "$OUTPUT_FILE"
    
    log_info ""
    log_info "Invalid Objects:"
    run_sql "
    SELECT owner, object_type, COUNT(*) as invalid_count
    FROM dba_objects
    WHERE status = 'INVALID'
    GROUP BY owner, object_type
    ORDER BY owner, object_type;" | tee -a "$OUTPUT_FILE"
}

# =============================================================================
# ADDITIONAL CUSTOM DISCOVERY (per user requirements)
# =============================================================================

discover_tablespace_autoextend() {
    log_section "TABLESPACE AUTOEXTEND SETTINGS"
    
    run_sql "
    SELECT 
        tablespace_name,
        file_name,
        ROUND(bytes/1024/1024/1024, 2) as size_gb,
        autoextensible,
        ROUND(maxbytes/1024/1024/1024, 2) as max_size_gb,
        increment_by
    FROM dba_data_files
    ORDER BY tablespace_name, file_name;" | tee -a "$OUTPUT_FILE"
    
    log_info ""
    log_info "Temp Files Autoextend:"
    run_sql "
    SELECT 
        tablespace_name,
        file_name,
        ROUND(bytes/1024/1024/1024, 2) as size_gb,
        autoextensible,
        ROUND(maxbytes/1024/1024/1024, 2) as max_size_gb
    FROM dba_temp_files
    ORDER BY tablespace_name;" | tee -a "$OUTPUT_FILE"
}

discover_backup_config() {
    log_section "BACKUP SCHEDULE AND RETENTION"
    
    log_info "RMAN Configuration:"
    run_sql "SELECT name, value FROM v\$rman_configuration ORDER BY name;" | tee -a "$OUTPUT_FILE"
    
    log_info ""
    log_info "Recent Backup History (last 7 days):"
    run_sql "
    SELECT 
        input_type,
        status,
        TO_CHAR(start_time, 'YYYY-MM-DD HH24:MI') as start_time,
        TO_CHAR(end_time, 'YYYY-MM-DD HH24:MI') as end_time,
        ROUND(input_bytes/1024/1024/1024, 2) as input_gb,
        ROUND(output_bytes/1024/1024/1024, 2) as output_gb
    FROM v\$rman_backup_job_details
    WHERE start_time > SYSDATE - 7
    ORDER BY start_time DESC;" | tee -a "$OUTPUT_FILE"
    
    log_info ""
    log_info "Backup Retention Policy:"
    run_sql "SELECT * FROM v\$rman_configuration WHERE name LIKE '%RETENTION%';" | tee -a "$OUTPUT_FILE"
}

discover_database_links() {
    log_section "DATABASE LINKS"
    
    log_info "All Database Links:"
    run_sql "
    SELECT 
        owner,
        db_link,
        username,
        host,
        created
    FROM dba_db_links
    ORDER BY owner, db_link;" | tee -a "$OUTPUT_FILE"
    
    log_info ""
    log_info "Database Link Connection Testing (names only):"
    run_sql "SELECT db_link FROM dba_db_links;" | tee -a "$OUTPUT_FILE"
}

discover_materialized_views() {
    log_section "MATERIALIZED VIEW REFRESH SCHEDULES"
    
    log_info "Materialized Views:"
    run_sql "
    SELECT 
        owner,
        mview_name,
        refresh_mode,
        refresh_method,
        build_mode,
        fast_refreshable,
        last_refresh_type,
        TO_CHAR(last_refresh_date, 'YYYY-MM-DD HH24:MI:SS') as last_refresh
    FROM dba_mviews
    ORDER BY owner, mview_name;" | tee -a "$OUTPUT_FILE"
    
    log_info ""
    log_info "Materialized View Refresh Groups:"
    run_sql "
    SELECT 
        rowner,
        rname,
        job,
        next_date,
        interval,
        broken
    FROM dba_refresh
    ORDER BY rowner, rname;" | tee -a "$OUTPUT_FILE"
    
    log_info ""
    log_info "Materialized View Logs:"
    run_sql "
    SELECT 
        log_owner,
        master,
        log_table,
        rowids,
        primary_key,
        object_id,
        filter_columns,
        sequence,
        include_new_values
    FROM dba_mview_logs
    ORDER BY log_owner, master;" | tee -a "$OUTPUT_FILE"
}

discover_scheduler_jobs() {
    log_section "SCHEDULER JOBS"
    
    log_info "Scheduler Jobs (may need reconfiguration):"
    run_sql "
    SELECT 
        owner,
        job_name,
        job_type,
        state,
        enabled,
        TO_CHAR(last_start_date, 'YYYY-MM-DD HH24:MI:SS') as last_run,
        TO_CHAR(next_run_date, 'YYYY-MM-DD HH24:MI:SS') as next_run,
        repeat_interval
    FROM dba_scheduler_jobs
    WHERE owner NOT IN ('SYS','SYSTEM','ORACLE_OCM','EXFSYS')
    ORDER BY owner, job_name;" | tee -a "$OUTPUT_FILE"
    
    log_info ""
    log_info "Legacy DBMS_JOBS:"
    run_sql "
    SELECT 
        job,
        log_user,
        schema_user,
        what,
        next_date,
        interval,
        broken
    FROM dba_jobs
    ORDER BY job;" | tee -a "$OUTPUT_FILE"
    
    log_info ""
    log_info "Scheduler Programs:"
    run_sql "
    SELECT 
        owner,
        program_name,
        program_type,
        program_action,
        enabled
    FROM dba_scheduler_programs
    WHERE owner NOT IN ('SYS','SYSTEM')
    ORDER BY owner, program_name;" | tee -a "$OUTPUT_FILE"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    echo "============================================================================="
    echo " ZDM Source Database Discovery"
    echo " Project: PRODDB Migration to Oracle Database@Azure"
    echo " Server: proddb01.corp.example.com"
    echo " Timestamp: $(date)"
    echo "============================================================================="
    
    # Initialize output files
    echo "ZDM Source Database Discovery Report" > "$OUTPUT_FILE"
    echo "Generated: $(date)" >> "$OUTPUT_FILE"
    echo "Hostname: $HOSTNAME" >> "$OUTPUT_FILE"
    echo "Project: PRODDB Migration to Oracle Database@Azure" >> "$OUTPUT_FILE"
    
    init_json
    
    # Run discovery sections - continue even if some fail
    discover_os_info || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_oracle_environment || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_database_config || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_cdb_pdb || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_tde_config || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_supplemental_logging || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_redo_archive || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_network_config || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_authentication || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_dataguard || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_schema_info || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    
    # Additional custom discovery per user requirements
    discover_tablespace_autoextend || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_backup_config || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_database_links || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_materialized_views || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_scheduler_jobs || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    
    # Finalize
    finalize_json
    
    echo ""
    echo "============================================================================="
    if [ $SECTION_ERRORS -gt 0 ]; then
        echo -e "${YELLOW}Discovery completed with $SECTION_ERRORS section(s) having warnings/errors${NC}"
    else
        echo -e "${GREEN}Discovery completed successfully${NC}"
    fi
    echo "Output files:"
    echo "  Text report: $OUTPUT_FILE"
    echo "  JSON summary: $JSON_FILE"
    echo "============================================================================="
    
    # Always exit 0 so orchestrator knows script completed
    exit 0
}

# Run main
main "$@"
