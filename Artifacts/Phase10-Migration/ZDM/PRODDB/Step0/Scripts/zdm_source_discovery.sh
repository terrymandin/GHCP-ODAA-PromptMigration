#!/bin/bash
# =============================================================================
# ZDM Source Database Discovery Script
# =============================================================================
# Project: PRODDB Migration to Oracle Database@Azure
# Target Server: proddb01.corp.example.com
# Generated: 2026-01-29
# =============================================================================
# This script discovers the source database configuration for ZDM migration.
# It gathers OS, Oracle, TDE, network, and schema information.
# =============================================================================

# NO set -e - We want to continue even if some checks fail
SECTION_ERRORS=0

# =============================================================================
# Color Output
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Environment Variable Discovery
# =============================================================================
# CRITICAL: Handle environment variables in non-interactive SSH sessions
# .bashrc often has guards like '[ -z "$PS1" ] && return' that skip non-interactive shells

# Method 1: Accept explicit overrides (passed from orchestration script)
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
    
    # Try to find Oracle from oratab
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
}

detect_oracle_env

# Set ORACLE_BASE if not set
if [ -z "${ORACLE_BASE:-}" ] && [ -n "${ORACLE_HOME:-}" ]; then
    export ORACLE_BASE=$(echo "$ORACLE_HOME" | sed 's|/product/.*||')
fi

# Update PATH
[ -n "$ORACLE_HOME" ] && export PATH="$ORACLE_HOME/bin:$PATH"

# =============================================================================
# Output Configuration
# =============================================================================
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname)
OUTPUT_FILE="./zdm_source_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_source_discovery_${HOSTNAME}_${TIMESTAMP}.json"

# =============================================================================
# Helper Functions
# =============================================================================
log_section() {
    local section_name="$1"
    echo ""
    echo "================================================================================"
    echo " $section_name"
    echo "================================================================================"
    echo ""
}

log_subsection() {
    local subsection_name="$1"
    echo ""
    echo "--- $subsection_name ---"
    echo ""
}

run_sql() {
    local sql_query="$1"
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        "$ORACLE_HOME/bin/sqlplus" -s / as sysdba <<EOF
SET PAGESIZE 1000
SET LINESIZE 200
SET FEEDBACK OFF
SET HEADING ON
SET ECHO OFF
$sql_query
EOF
    else
        echo "ERROR: ORACLE_HOME or ORACLE_SID not set"
        return 1
    fi
}

run_sql_value() {
    local sql_query="$1"
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        "$ORACLE_HOME/bin/sqlplus" -s / as sysdba <<EOF
SET PAGESIZE 0
SET LINESIZE 200
SET FEEDBACK OFF
SET HEADING OFF
SET ECHO OFF
SET TRIMSPOOL ON
$sql_query
EOF
    else
        echo "ERROR: ORACLE_HOME or ORACLE_SID not set"
        return 1
    fi
}

# =============================================================================
# Discovery Functions
# =============================================================================

discover_os_info() {
    log_section "OS INFORMATION"
    
    echo "Hostname: $(hostname)"
    echo "FQDN: $(hostname -f 2>/dev/null || hostname)"
    echo ""
    
    log_subsection "IP Addresses"
    ip addr show 2>/dev/null | grep "inet " || ifconfig 2>/dev/null | grep "inet " || echo "Could not determine IP addresses"
    
    log_subsection "Operating System"
    if [ -f /etc/os-release ]; then
        cat /etc/os-release
    elif [ -f /etc/redhat-release ]; then
        cat /etc/redhat-release
    else
        uname -a
    fi
    
    log_subsection "Kernel"
    uname -r
    
    log_subsection "Disk Space"
    df -h
    
    log_subsection "Memory"
    free -h 2>/dev/null || cat /proc/meminfo 2>/dev/null | head -10
    
    log_subsection "CPU Info"
    grep "model name" /proc/cpuinfo 2>/dev/null | head -1
    echo "CPU Cores: $(grep -c processor /proc/cpuinfo 2>/dev/null || echo 'Unknown')"
}

discover_oracle_env() {
    log_section "ORACLE ENVIRONMENT"
    
    echo "ORACLE_HOME: ${ORACLE_HOME:-NOT SET}"
    echo "ORACLE_SID: ${ORACLE_SID:-NOT SET}"
    echo "ORACLE_BASE: ${ORACLE_BASE:-NOT SET}"
    echo "TNS_ADMIN: ${TNS_ADMIN:-NOT SET}"
    
    log_subsection "Oracle Version"
    if [ -n "${ORACLE_HOME:-}" ] && [ -f "$ORACLE_HOME/bin/sqlplus" ]; then
        "$ORACLE_HOME/bin/sqlplus" -v 2>/dev/null || echo "Could not determine Oracle version"
    else
        echo "Oracle not found or ORACLE_HOME not set"
    fi
    
    log_subsection "oratab Contents"
    if [ -f /etc/oratab ]; then
        cat /etc/oratab
    else
        echo "/etc/oratab not found"
    fi
    
    log_subsection "Running Oracle Processes"
    ps -ef | grep -E "ora_pmon|ora_smon|tnslsnr" | grep -v grep || echo "No Oracle processes found"
}

discover_database_config() {
    log_section "DATABASE CONFIGURATION"
    
    log_subsection "Database Identification"
    run_sql "
    SELECT name, db_unique_name, dbid, created, log_mode, 
           force_logging, open_mode, database_role
    FROM v\$database;
    " || echo "WARNING: Could not query database identification"
    
    log_subsection "Instance Information"
    run_sql "
    SELECT instance_name, host_name, version, status, 
           startup_time, instance_role
    FROM v\$instance;
    " || echo "WARNING: Could not query instance information"
    
    log_subsection "Database Version Details"
    run_sql "SELECT * FROM v\$version;" || echo "WARNING: Could not query version"
    
    log_subsection "Database Size"
    run_sql "
    SELECT 'Data Files' as type, 
           ROUND(SUM(bytes)/1024/1024/1024, 2) as size_gb
    FROM dba_data_files
    UNION ALL
    SELECT 'Temp Files' as type, 
           ROUND(SUM(bytes)/1024/1024/1024, 2) as size_gb
    FROM dba_temp_files
    UNION ALL
    SELECT 'Redo Logs' as type, 
           ROUND(SUM(bytes)/1024/1024/1024, 2) as size_gb
    FROM v\$log;
    " || echo "WARNING: Could not query database size"
    
    log_subsection "Character Set"
    run_sql "
    SELECT parameter, value 
    FROM nls_database_parameters 
    WHERE parameter IN ('NLS_CHARACTERSET', 'NLS_NCHAR_CHARACTERSET', 'NLS_LANGUAGE', 'NLS_TERRITORY');
    " || echo "WARNING: Could not query character set"
}

discover_cdb_pdb() {
    log_section "CONTAINER DATABASE CONFIGURATION"
    
    log_subsection "CDB Status"
    run_sql "SELECT cdb FROM v\$database;" || echo "WARNING: Could not determine CDB status"
    
    log_subsection "PDB Information"
    run_sql "
    SELECT con_id, name, open_mode, restricted, guid
    FROM v\$pdbs
    ORDER BY con_id;
    " 2>/dev/null || echo "NOTE: Not a CDB or could not query PDBs"
    
    log_subsection "Container Information"
    run_sql "
    SELECT con_id, name, dbid, con_uid, guid
    FROM v\$containers
    ORDER BY con_id;
    " 2>/dev/null || echo "NOTE: Not a CDB or could not query containers"
}

discover_tde() {
    log_section "TDE CONFIGURATION"
    
    log_subsection "Encryption Wallet Status"
    run_sql "
    SELECT wrl_type, wrl_parameter, status, wallet_type, wallet_order
    FROM v\$encryption_wallet;
    " || echo "WARNING: Could not query encryption wallet"
    
    log_subsection "Encrypted Tablespaces"
    run_sql "
    SELECT ts.name as tablespace_name, e.encryptedts, e.encryptionalg
    FROM v\$tablespace ts, v\$encrypted_tablespaces e
    WHERE ts.ts# = e.ts#;
    " || echo "NOTE: No encrypted tablespaces found or could not query"
    
    log_subsection "Encryption Keys"
    run_sql "
    SELECT key_id, keystore_type, creator, creator_pdbname, activating_pdbname
    FROM v\$encryption_keys;
    " || echo "WARNING: Could not query encryption keys"
}

discover_supplemental_logging() {
    log_section "SUPPLEMENTAL LOGGING"
    
    run_sql "
    SELECT supplemental_log_data_min,
           supplemental_log_data_pk,
           supplemental_log_data_ui,
           supplemental_log_data_fk,
           supplemental_log_data_all
    FROM v\$database;
    " || echo "WARNING: Could not query supplemental logging"
}

discover_redo_archive() {
    log_section "REDO AND ARCHIVE CONFIGURATION"
    
    log_subsection "Redo Log Groups"
    run_sql "
    SELECT group#, thread#, sequence#, bytes/1024/1024 as size_mb, 
           members, archived, status
    FROM v\$log
    ORDER BY group#;
    " || echo "WARNING: Could not query redo log groups"
    
    log_subsection "Redo Log Members"
    run_sql "
    SELECT group#, type, member, is_recovery_dest_file
    FROM v\$logfile
    ORDER BY group#;
    " || echo "WARNING: Could not query redo log members"
    
    log_subsection "Archive Log Destinations"
    run_sql "
    SELECT dest_id, dest_name, status, target, destination,
           binding, valid_type, valid_role
    FROM v\$archive_dest
    WHERE status != 'INACTIVE';
    " || echo "WARNING: Could not query archive destinations"
    
    log_subsection "Archive Log Parameters"
    run_sql "
    SELECT name, value 
    FROM v\$parameter 
    WHERE name LIKE 'log_archive%' OR name = 'archive_lag_target'
    ORDER BY name;
    " || echo "WARNING: Could not query archive parameters"
}

discover_network() {
    log_section "NETWORK CONFIGURATION"
    
    log_subsection "Listener Status"
    if [ -n "${ORACLE_HOME:-}" ]; then
        "$ORACLE_HOME/bin/lsnrctl" status 2>&1 || echo "Could not get listener status"
    else
        echo "ORACLE_HOME not set, cannot check listener"
    fi
    
    log_subsection "tnsnames.ora"
    for tns_file in "$TNS_ADMIN/tnsnames.ora" "$ORACLE_HOME/network/admin/tnsnames.ora" "/etc/tnsnames.ora"; do
        if [ -f "$tns_file" ]; then
            echo "Found: $tns_file"
            cat "$tns_file"
            break
        fi
    done
    
    log_subsection "sqlnet.ora"
    for sqlnet_file in "$TNS_ADMIN/sqlnet.ora" "$ORACLE_HOME/network/admin/sqlnet.ora" "/etc/sqlnet.ora"; do
        if [ -f "$sqlnet_file" ]; then
            echo "Found: $sqlnet_file"
            cat "$sqlnet_file"
            break
        fi
    done
    
    log_subsection "listener.ora"
    for listener_file in "$TNS_ADMIN/listener.ora" "$ORACLE_HOME/network/admin/listener.ora" "/etc/listener.ora"; do
        if [ -f "$listener_file" ]; then
            echo "Found: $listener_file"
            cat "$listener_file"
            break
        fi
    done
}

discover_authentication() {
    log_section "AUTHENTICATION CONFIGURATION"
    
    log_subsection "Password File"
    if [ -n "${ORACLE_HOME:-}" ]; then
        ls -la "$ORACLE_HOME/dbs/orapw"* 2>/dev/null || echo "No password file found in $ORACLE_HOME/dbs/"
    fi
    
    log_subsection "SSH Directory"
    echo "Contents of ~/.ssh/:"
    ls -la ~/.ssh/ 2>/dev/null || echo "~/.ssh directory not found or not accessible"
    
    log_subsection "SSH Public Keys"
    cat ~/.ssh/authorized_keys 2>/dev/null | head -20 || echo "No authorized_keys file found"
}

discover_dataguard() {
    log_section "DATA GUARD CONFIGURATION"
    
    log_subsection "Data Guard Parameters"
    run_sql "
    SELECT name, value 
    FROM v\$parameter 
    WHERE name LIKE '%standby%' 
       OR name LIKE '%log_archive_dest%'
       OR name = 'db_unique_name'
       OR name = 'db_name'
       OR name = 'fal_server'
       OR name = 'fal_client'
    ORDER BY name;
    " || echo "WARNING: Could not query Data Guard parameters"
    
    log_subsection "Standby Redo Logs"
    run_sql "
    SELECT group#, thread#, sequence#, bytes/1024/1024 as size_mb
    FROM v\$standby_log;
    " || echo "NOTE: No standby redo logs configured"
}

discover_schemas() {
    log_section "SCHEMA INFORMATION"
    
    log_subsection "Large Schemas (>100MB)"
    run_sql "
    SELECT owner, 
           ROUND(SUM(bytes)/1024/1024, 2) as size_mb,
           COUNT(*) as segment_count
    FROM dba_segments
    WHERE owner NOT IN ('SYS','SYSTEM','DBSNMP','APPQOSSYS','AUDSYS',
                        'CTXSYS','DVSYS','GSMADMIN_INTERNAL','LBACSYS',
                        'MDSYS','OLAPSYS','ORDDATA','ORDSYS','OUTLN',
                        'WMSYS','XDB','GGSYS','ANONYMOUS','GSMCATUSER',
                        'GSMUSER','MDDATA','OJVMSYS','REMOTE_SCHEDULER_AGENT',
                        'SI_INFORMTN_SCHEMA','SYS\$UMF','SYSBACKUP','SYSDG',
                        'SYSKM','SYSRAC')
    GROUP BY owner
    HAVING SUM(bytes) > 100*1024*1024
    ORDER BY SUM(bytes) DESC;
    " || echo "WARNING: Could not query schema sizes"
    
    log_subsection "Invalid Objects by Owner"
    run_sql "
    SELECT owner, object_type, COUNT(*) as invalid_count
    FROM dba_objects
    WHERE status = 'INVALID'
    GROUP BY owner, object_type
    ORDER BY owner, object_type;
    " || echo "WARNING: Could not query invalid objects"
}

# =============================================================================
# Additional Discovery (Custom for PRODDB)
# =============================================================================

discover_tablespace_autoextend() {
    log_section "TABLESPACE AUTOEXTEND SETTINGS"
    
    run_sql "
    SELECT tablespace_name, 
           file_name,
           autoextensible,
           ROUND(bytes/1024/1024/1024, 2) as current_size_gb,
           ROUND(maxbytes/1024/1024/1024, 2) as max_size_gb,
           increment_by * (SELECT value FROM v\$parameter WHERE name = 'db_block_size') / 1024/1024 as increment_mb
    FROM dba_data_files
    ORDER BY tablespace_name, file_name;
    " || echo "WARNING: Could not query tablespace autoextend settings"
}

discover_backup_config() {
    log_section "BACKUP SCHEDULE AND RETENTION"
    
    log_subsection "RMAN Configuration"
    run_sql "
    SELECT name, value 
    FROM v\$rman_configuration 
    ORDER BY name;
    " || echo "WARNING: Could not query RMAN configuration"
    
    log_subsection "Recent Backup History"
    run_sql "
    SELECT start_time, end_time, input_type, status, 
           ROUND(output_bytes/1024/1024/1024, 2) as output_gb
    FROM v\$rman_backup_job_details
    WHERE start_time > SYSDATE - 7
    ORDER BY start_time DESC;
    " || echo "WARNING: Could not query backup history"
    
    log_subsection "Backup Scheduler Jobs"
    run_sql "
    SELECT owner, job_name, enabled, state, last_start_date, next_run_date
    FROM dba_scheduler_jobs
    WHERE job_name LIKE '%BACKUP%' OR job_name LIKE '%RMAN%'
    ORDER BY owner, job_name;
    " || echo "NOTE: No backup scheduler jobs found or could not query"
}

discover_database_links() {
    log_section "DATABASE LINKS"
    
    run_sql "
    SELECT owner, db_link, username, host, created
    FROM dba_db_links
    ORDER BY owner, db_link;
    " || echo "NOTE: No database links found or could not query"
}

discover_materialized_views() {
    log_section "MATERIALIZED VIEW REFRESH SCHEDULES"
    
    run_sql "
    SELECT owner, mview_name, refresh_mode, refresh_method,
           last_refresh_date, next_refresh_date,
           staleness, compile_state
    FROM dba_mviews
    WHERE owner NOT IN ('SYS','SYSTEM')
    ORDER BY owner, mview_name;
    " || echo "NOTE: No materialized views found or could not query"
    
    log_subsection "Materialized View Refresh Groups"
    run_sql "
    SELECT rowner, rname, refgroup, implicit_destroy,
           rollback_seg, push_deferred_rpc, refresh_after_errors
    FROM dba_refresh
    WHERE rowner NOT IN ('SYS','SYSTEM')
    ORDER BY rowner, rname;
    " || echo "NOTE: No refresh groups found or could not query"
}

discover_scheduler_jobs() {
    log_section "SCHEDULER JOBS"
    
    run_sql "
    SELECT owner, job_name, job_type, job_action,
           enabled, state, run_count, failure_count,
           last_start_date, next_run_date, repeat_interval
    FROM dba_scheduler_jobs
    WHERE owner NOT IN ('SYS','SYSTEM','DBSNMP','APPQOSSYS','AUDSYS',
                        'CTXSYS','DVSYS','GSMADMIN_INTERNAL','LBACSYS',
                        'MDSYS','OLAPSYS','ORDDATA','ORDSYS','OUTLN',
                        'WMSYS','XDB')
    ORDER BY owner, job_name;
    " || echo "NOTE: No scheduler jobs found or could not query"
    
    log_subsection "Job Classes"
    run_sql "
    SELECT job_class_name, resource_consumer_group, service, logging_level
    FROM dba_scheduler_job_classes
    ORDER BY job_class_name;
    " || echo "WARNING: Could not query job classes"
}

# =============================================================================
# JSON Summary Generation
# =============================================================================
generate_json_summary() {
    local db_name=$(run_sql_value "SELECT name FROM v\$database;")
    local db_unique_name=$(run_sql_value "SELECT db_unique_name FROM v\$database;")
    local dbid=$(run_sql_value "SELECT dbid FROM v\$database;")
    local log_mode=$(run_sql_value "SELECT log_mode FROM v\$database;")
    local force_logging=$(run_sql_value "SELECT force_logging FROM v\$database;")
    local open_mode=$(run_sql_value "SELECT open_mode FROM v\$database;")
    local database_role=$(run_sql_value "SELECT database_role FROM v\$database;")
    local version=$(run_sql_value "SELECT version FROM v\$instance;")
    local cdb=$(run_sql_value "SELECT cdb FROM v\$database;")
    local tde_status=$(run_sql_value "SELECT status FROM v\$encryption_wallet WHERE ROWNUM = 1;")
    local charset=$(run_sql_value "SELECT value FROM nls_database_parameters WHERE parameter = 'NLS_CHARACTERSET';")
    local data_size=$(run_sql_value "SELECT ROUND(SUM(bytes)/1024/1024/1024, 2) FROM dba_data_files;")
    
    cat > "$JSON_FILE" <<EOF
{
  "discovery_type": "source",
  "timestamp": "$TIMESTAMP",
  "hostname": "$HOSTNAME",
  "project": "PRODDB Migration to Oracle Database@Azure",
  "oracle_environment": {
    "oracle_home": "${ORACLE_HOME:-NOT SET}",
    "oracle_sid": "${ORACLE_SID:-NOT SET}",
    "oracle_base": "${ORACLE_BASE:-NOT SET}"
  },
  "database": {
    "name": "${db_name:-UNKNOWN}",
    "unique_name": "${db_unique_name:-UNKNOWN}",
    "dbid": "${dbid:-UNKNOWN}",
    "version": "${version:-UNKNOWN}",
    "log_mode": "${log_mode:-UNKNOWN}",
    "force_logging": "${force_logging:-UNKNOWN}",
    "open_mode": "${open_mode:-UNKNOWN}",
    "database_role": "${database_role:-UNKNOWN}",
    "is_cdb": "${cdb:-UNKNOWN}",
    "character_set": "${charset:-UNKNOWN}",
    "data_size_gb": "${data_size:-UNKNOWN}"
  },
  "tde": {
    "wallet_status": "${tde_status:-NOT CONFIGURED}"
  },
  "section_errors": $SECTION_ERRORS
}
EOF
    echo "JSON summary saved to: $JSON_FILE"
}

# =============================================================================
# Main Execution
# =============================================================================
main() {
    echo "================================================================================"
    echo " ZDM Source Database Discovery"
    echo " Project: PRODDB Migration to Oracle Database@Azure"
    echo " Server: proddb01.corp.example.com"
    echo " Timestamp: $(date)"
    echo "================================================================================"
    
    # Run all discovery sections with error handling
    {
        discover_os_info || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_oracle_env || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_database_config || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_cdb_pdb || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_tde || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_supplemental_logging || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_redo_archive || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_network || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_authentication || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_dataguard || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_schemas || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        
        # Additional custom discovery for PRODDB
        discover_tablespace_autoextend || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_backup_config || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_database_links || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_materialized_views || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_scheduler_jobs || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        
    } 2>&1 | tee "$OUTPUT_FILE"
    
    # Generate JSON summary
    generate_json_summary
    
    echo ""
    echo "================================================================================"
    echo " DISCOVERY COMPLETE"
    echo "================================================================================"
    echo " Text report: $OUTPUT_FILE"
    echo " JSON summary: $JSON_FILE"
    echo " Sections with errors: $SECTION_ERRORS"
    echo "================================================================================"
}

# Run main
main

# Always exit 0 so orchestrator knows script completed
exit 0
