#!/bin/bash
###############################################################################
# ZDM Source Database Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# Source: proddb01.corp.example.com
# 
# Purpose: Discover source database configuration for ZDM migration
# Run as: oracle user on source database server
#
# Generated: 2026-01-29
###############################################################################

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Get hostname and timestamp for output files
HOSTNAME=$(hostname -s 2>/dev/null || hostname)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="./zdm_source_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_source_discovery_${HOSTNAME}_${TIMESTAMP}.json"

# Initialize JSON structure
declare -A JSON_DATA

###############################################################################
# Environment Variable Sourcing with Fallback
###############################################################################
source_environment() {
    echo -e "${BLUE}=== Sourcing Oracle Environment ===${NC}"
    
    # Method 1: Use explicit overrides if provided (passed via environment)
    if [ -n "${ORACLE_HOME_OVERRIDE:-}" ]; then
        export ORACLE_HOME="$ORACLE_HOME_OVERRIDE"
        echo -e "${GREEN}Using explicit ORACLE_HOME override: $ORACLE_HOME${NC}"
    fi
    if [ -n "${ORACLE_SID_OVERRIDE:-}" ]; then
        export ORACLE_SID="$ORACLE_SID_OVERRIDE"
        echo -e "${GREEN}Using explicit ORACLE_SID override: $ORACLE_SID${NC}"
    fi
    
    # Method 2: Source profiles - extract export statements
    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        for profile in /etc/profile ~/.bash_profile ~/.bashrc ~/.profile; do
            if [ -f "$profile" ]; then
                # Extract export statements without running interactive checks
                eval "$(grep -E '^export\s+' "$profile" 2>/dev/null)" || true
            fi
        done
    fi
    
    # Method 3: Try oraenv if available
    if [ -z "${ORACLE_HOME:-}" ] && [ -f /usr/local/bin/oraenv ]; then
        ORAENV_ASK=NO
        . /usr/local/bin/oraenv 2>/dev/null || true
    fi
    
    # Method 4: Search common Oracle installation locations
    if [ -z "${ORACLE_HOME:-}" ]; then
        for oh in /u01/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1; do
            if [ -d "$oh" ]; then
                export ORACLE_HOME="$oh"
                echo -e "${YELLOW}Auto-detected ORACLE_HOME: $ORACLE_HOME${NC}"
                break
            fi
        done
    fi
    
    # Set PATH if ORACLE_HOME is found
    if [ -n "${ORACLE_HOME:-}" ]; then
        export PATH=$ORACLE_HOME/bin:$PATH
        export LD_LIBRARY_PATH=$ORACLE_HOME/lib:${LD_LIBRARY_PATH:-}
    fi
    
    echo "ORACLE_HOME: ${ORACLE_HOME:-NOT SET}"
    echo "ORACLE_SID: ${ORACLE_SID:-NOT SET}"
    echo "ORACLE_BASE: ${ORACLE_BASE:-NOT SET}"
}

###############################################################################
# Helper Functions
###############################################################################
print_header() {
    local title="$1"
    echo ""
    echo -e "${CYAN}===============================================================================${NC}"
    echo -e "${CYAN}  $title${NC}"
    echo -e "${CYAN}===============================================================================${NC}"
    echo ""
}

print_section() {
    local title="$1"
    echo ""
    echo -e "${YELLOW}--- $title ---${NC}"
}

run_sql() {
    local sql="$1"
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        $ORACLE_HOME/bin/sqlplus -S "/ as sysdba" <<EOF
SET PAGESIZE 0
SET LINESIZE 200
SET FEEDBACK OFF
SET HEADING OFF
SET TRIMSPOOL ON
$sql
EOF
    else
        echo "ERROR: Oracle environment not set"
        return 1
    fi
}

run_sql_with_headers() {
    local sql="$1"
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        $ORACLE_HOME/bin/sqlplus -S "/ as sysdba" <<EOF
SET PAGESIZE 1000
SET LINESIZE 200
SET FEEDBACK OFF
SET HEADING ON
SET TRIMSPOOL ON
COLUMN name FORMAT A40
COLUMN value FORMAT A80
$sql
EOF
    else
        echo "ERROR: Oracle environment not set"
        return 1
    fi
}

escape_json() {
    local text="$1"
    echo "$text" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' ' '
}

###############################################################################
# Discovery Functions
###############################################################################

discover_os_info() {
    print_header "OS INFORMATION"
    
    print_section "Hostname and IP Addresses"
    echo "Hostname: $(hostname)"
    echo "FQDN: $(hostname -f 2>/dev/null || echo 'N/A')"
    echo ""
    echo "IP Addresses:"
    ip addr show 2>/dev/null | grep 'inet ' | awk '{print "  " $2}' || ifconfig 2>/dev/null | grep 'inet ' | awk '{print "  " $2}'
    
    print_section "Operating System Version"
    if [ -f /etc/os-release ]; then
        cat /etc/os-release
    elif [ -f /etc/redhat-release ]; then
        cat /etc/redhat-release
    else
        uname -a
    fi
    
    print_section "Disk Space"
    df -h
    
    # Store in JSON
    JSON_DATA["hostname"]=$(hostname)
    JSON_DATA["os_version"]=$(cat /etc/redhat-release 2>/dev/null || uname -r)
}

discover_oracle_environment() {
    print_header "ORACLE ENVIRONMENT"
    
    print_section "Oracle Environment Variables"
    echo "ORACLE_HOME: ${ORACLE_HOME:-NOT SET}"
    echo "ORACLE_SID: ${ORACLE_SID:-NOT SET}"
    echo "ORACLE_BASE: ${ORACLE_BASE:-NOT SET}"
    
    print_section "Oracle Version"
    if [ -n "${ORACLE_HOME:-}" ]; then
        $ORACLE_HOME/bin/sqlplus -V 2>/dev/null || echo "Unable to determine version"
    else
        echo "ORACLE_HOME not set"
    fi
    
    JSON_DATA["oracle_home"]="${ORACLE_HOME:-}"
    JSON_DATA["oracle_sid"]="${ORACLE_SID:-}"
}

discover_database_config() {
    print_header "DATABASE CONFIGURATION"
    
    print_section "Database Instance Information"
    run_sql_with_headers "
SELECT name, db_unique_name, dbid, database_role, open_mode, log_mode, force_logging
FROM v\$database;
"
    
    # Capture key values for JSON
    local db_info=$(run_sql "SELECT name||','||db_unique_name||','||dbid||','||database_role||','||open_mode||','||log_mode||','||force_logging FROM v\$database;")
    JSON_DATA["db_name"]=$(echo "$db_info" | cut -d',' -f1)
    JSON_DATA["db_unique_name"]=$(echo "$db_info" | cut -d',' -f2)
    JSON_DATA["dbid"]=$(echo "$db_info" | cut -d',' -f3)
    JSON_DATA["database_role"]=$(echo "$db_info" | cut -d',' -f4)
    JSON_DATA["open_mode"]=$(echo "$db_info" | cut -d',' -f5)
    JSON_DATA["log_mode"]=$(echo "$db_info" | cut -d',' -f6)
    JSON_DATA["force_logging"]=$(echo "$db_info" | cut -d',' -f7)
    
    print_section "Database Size"
    run_sql_with_headers "
SELECT 'Data Files' AS type, ROUND(SUM(bytes)/1024/1024/1024, 2) AS size_gb FROM dba_data_files
UNION ALL
SELECT 'Temp Files', ROUND(SUM(bytes)/1024/1024/1024, 2) FROM dba_temp_files
UNION ALL
SELECT 'Redo Logs', ROUND(SUM(bytes)/1024/1024/1024, 2) FROM v\$log;
"
    
    print_section "Character Set"
    run_sql_with_headers "
SELECT parameter, value FROM nls_database_parameters
WHERE parameter IN ('NLS_CHARACTERSET', 'NLS_NCHAR_CHARACTERSET');
"
    
    local charset=$(run_sql "SELECT value FROM nls_database_parameters WHERE parameter='NLS_CHARACTERSET';")
    JSON_DATA["character_set"]=$(echo "$charset" | tr -d ' ')
}

discover_cdb_pdb() {
    print_header "CONTAINER DATABASE CONFIGURATION"
    
    print_section "CDB Status"
    local cdb_status=$(run_sql "SELECT CDB FROM v\$database;")
    echo "CDB: $cdb_status"
    JSON_DATA["is_cdb"]=$(echo "$cdb_status" | tr -d ' ')
    
    if [[ "$cdb_status" == *"YES"* ]]; then
        print_section "PDB Information"
        run_sql_with_headers "
SELECT pdb_id, pdb_name, status, open_mode
FROM cdb_pdbs
ORDER BY pdb_id;
"
        
        print_section "PDB Sizes"
        run_sql_with_headers "
SELECT con_id, ROUND(SUM(bytes)/1024/1024/1024, 2) AS size_gb
FROM cdb_data_files
GROUP BY con_id
ORDER BY con_id;
"
    else
        echo "Non-CDB database detected"
    fi
}

discover_tde_config() {
    print_header "TDE CONFIGURATION"
    
    print_section "TDE Status"
    run_sql_with_headers "
SELECT con_id, wallet_type, status, wallet_order
FROM v\$encryption_wallet;
"
    
    print_section "Encrypted Tablespaces"
    run_sql_with_headers "
SELECT tablespace_name, encrypted
FROM dba_tablespaces
WHERE encrypted = 'YES';
"
    
    print_section "Wallet Location"
    run_sql "SELECT value FROM v\$parameter WHERE name = 'wallet_root';"
    
    local tde_status=$(run_sql "SELECT status FROM v\$encryption_wallet WHERE ROWNUM = 1;")
    JSON_DATA["tde_status"]=$(echo "$tde_status" | tr -d ' ')
}

discover_supplemental_logging() {
    print_header "SUPPLEMENTAL LOGGING"
    
    run_sql_with_headers "
SELECT supplemental_log_data_min AS min,
       supplemental_log_data_pk AS pk,
       supplemental_log_data_ui AS ui,
       supplemental_log_data_fk AS fk,
       supplemental_log_data_all AS all_cols
FROM v\$database;
"
    
    local supp_log=$(run_sql "SELECT supplemental_log_data_min FROM v\$database;")
    JSON_DATA["supplemental_logging"]=$(echo "$supp_log" | tr -d ' ')
}

discover_redo_archive() {
    print_header "REDO AND ARCHIVE LOG CONFIGURATION"
    
    print_section "Redo Log Groups"
    run_sql_with_headers "
SELECT group#, thread#, sequence#, bytes/1024/1024 AS size_mb, members, status
FROM v\$log
ORDER BY group#;
"
    
    print_section "Redo Log Members"
    run_sql_with_headers "
SELECT group#, member, type
FROM v\$logfile
ORDER BY group#;
"
    
    print_section "Archive Log Destinations"
    run_sql_with_headers "
SELECT dest_id, dest_name, status, destination
FROM v\$archive_dest
WHERE status != 'INACTIVE';
"
    
    print_section "Archive Log Mode Details"
    run_sql_with_headers "
SELECT name, value FROM v\$parameter
WHERE name LIKE 'log_archive%'
ORDER BY name;
"
}

discover_network_config() {
    print_header "NETWORK CONFIGURATION"
    
    print_section "Listener Status"
    if [ -n "${ORACLE_HOME:-}" ]; then
        $ORACLE_HOME/bin/lsnrctl status 2>/dev/null || echo "Unable to get listener status"
    fi
    
    print_section "tnsnames.ora"
    if [ -f "${ORACLE_HOME}/network/admin/tnsnames.ora" ]; then
        cat "${ORACLE_HOME}/network/admin/tnsnames.ora"
    elif [ -f "${TNS_ADMIN:-}/tnsnames.ora" ]; then
        cat "${TNS_ADMIN}/tnsnames.ora"
    else
        echo "tnsnames.ora not found"
    fi
    
    print_section "sqlnet.ora"
    if [ -f "${ORACLE_HOME}/network/admin/sqlnet.ora" ]; then
        cat "${ORACLE_HOME}/network/admin/sqlnet.ora"
    elif [ -f "${TNS_ADMIN:-}/sqlnet.ora" ]; then
        cat "${TNS_ADMIN}/sqlnet.ora"
    else
        echo "sqlnet.ora not found"
    fi
}

discover_authentication() {
    print_header "AUTHENTICATION CONFIGURATION"
    
    print_section "Password File Location"
    if [ -n "${ORACLE_HOME:-}" ]; then
        ls -la ${ORACLE_HOME}/dbs/orapw* 2>/dev/null || echo "No password file found in default location"
    fi
    
    print_section "SSH Directory Contents"
    ls -la ~/.ssh/ 2>/dev/null || echo "No .ssh directory found"
}

discover_data_guard() {
    print_header "DATA GUARD CONFIGURATION"
    
    run_sql_with_headers "
SELECT name, value
FROM v\$parameter
WHERE name IN ('dg_broker_start', 'log_archive_config', 'log_archive_dest_1', 
               'log_archive_dest_2', 'log_archive_dest_state_1', 'log_archive_dest_state_2',
               'fal_server', 'fal_client', 'standby_file_management', 'db_file_name_convert',
               'log_file_name_convert')
ORDER BY name;
"
}

discover_schema_info() {
    print_header "SCHEMA INFORMATION"
    
    print_section "Schema Sizes (Non-System Schemas > 100MB)"
    run_sql_with_headers "
SELECT owner, ROUND(SUM(bytes)/1024/1024, 2) AS size_mb
FROM dba_segments
WHERE owner NOT IN ('SYS','SYSTEM','OUTLN','DIP','ORACLE_OCM','DBSNMP','APPQOSSYS',
                    'WMSYS','EXFSYS','CTXSYS','ANONYMOUS','XDB','MDSYS','ORDDATA',
                    'ORDSYS','OLAPSYS','DVSYS','LBACSYS','DVF','GSMADMIN_INTERNAL',
                    'AUDSYS','OJVMSYS','XS\$NULL','GSMCATUSER','GSMUSER','REMOTE_SCHEDULER_AGENT')
GROUP BY owner
HAVING SUM(bytes)/1024/1024 > 100
ORDER BY 2 DESC;
"
    
    print_section "Invalid Objects Count by Owner/Type"
    run_sql_with_headers "
SELECT owner, object_type, COUNT(*) AS invalid_count
FROM dba_objects
WHERE status = 'INVALID'
GROUP BY owner, object_type
ORDER BY owner, object_type;
"
}

###############################################################################
# ADDITIONAL DISCOVERY - Custom for PRODDB Migration
###############################################################################

discover_tablespace_autoextend() {
    print_header "TABLESPACE AUTOEXTEND SETTINGS"
    
    run_sql_with_headers "
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
    print_header "BACKUP SCHEDULE AND RETENTION"
    
    print_section "RMAN Configuration"
    if [ -n "${ORACLE_HOME:-}" ]; then
        $ORACLE_HOME/bin/rman target / <<EOF 2>/dev/null || echo "Unable to connect to RMAN"
SHOW ALL;
EXIT;
EOF
    fi
    
    print_section "Recent Backup History"
    run_sql_with_headers "
SELECT session_key, input_type, status, 
       TO_CHAR(start_time, 'YYYY-MM-DD HH24:MI:SS') AS start_time,
       TO_CHAR(end_time, 'YYYY-MM-DD HH24:MI:SS') AS end_time,
       elapsed_seconds
FROM v\$rman_backup_job_details
WHERE start_time > SYSDATE - 7
ORDER BY start_time DESC;
"
    
    print_section "Backup Retention Policy"
    run_sql_with_headers "
SELECT name, value FROM v\$rman_configuration
WHERE name LIKE '%RETENTION%';
"
}

discover_database_links() {
    print_header "DATABASE LINKS"
    
    run_sql_with_headers "
SELECT owner, db_link, username, host, created
FROM dba_db_links
ORDER BY owner, db_link;
"
    
    print_section "Database Link Count by Owner"
    run_sql_with_headers "
SELECT owner, COUNT(*) AS link_count
FROM dba_db_links
GROUP BY owner
ORDER BY link_count DESC;
"
}

discover_materialized_views() {
    print_header "MATERIALIZED VIEW REFRESH SCHEDULES"
    
    run_sql_with_headers "
SELECT owner, mview_name, refresh_mode, refresh_method, 
       last_refresh_type, last_refresh_date,
       staleness
FROM dba_mviews
ORDER BY owner, mview_name;
"
    
    print_section "Materialized View Refresh Groups"
    run_sql_with_headers "
SELECT rowner, rname, refgroup, 
       implicit_destroy, push_deferred_rpc, refresh_after_errors
FROM dba_refresh
ORDER BY rowner, rname;
"
}

discover_scheduler_jobs() {
    print_header "SCHEDULER JOBS"
    
    run_sql_with_headers "
SELECT owner, job_name, job_type, state, enabled,
       TO_CHAR(last_start_date, 'YYYY-MM-DD HH24:MI:SS') AS last_start,
       TO_CHAR(next_run_date, 'YYYY-MM-DD HH24:MI:SS') AS next_run,
       repeat_interval
FROM dba_scheduler_jobs
WHERE owner NOT IN ('SYS', 'SYSTEM', 'ORACLE_OCM', 'EXFSYS')
ORDER BY owner, job_name;
"
    
    print_section "Legacy DBMS_JOB Jobs"
    run_sql_with_headers "
SELECT job, schema_user, 
       TO_CHAR(last_date, 'YYYY-MM-DD HH24:MI:SS') AS last_run,
       TO_CHAR(next_date, 'YYYY-MM-DD HH24:MI:SS') AS next_run,
       broken, interval, what
FROM dba_jobs
ORDER BY job;
"
}

###############################################################################
# Generate JSON Output
###############################################################################
generate_json() {
    cat > "$JSON_FILE" <<EOF
{
    "discovery_type": "source_database",
    "project": "PRODDB Migration to Oracle Database@Azure",
    "timestamp": "$(date -Iseconds)",
    "hostname": "${JSON_DATA["hostname"]:-}",
    "os_version": "${JSON_DATA["os_version"]:-}",
    "oracle_home": "${JSON_DATA["oracle_home"]:-}",
    "oracle_sid": "${JSON_DATA["oracle_sid"]:-}",
    "database": {
        "name": "${JSON_DATA["db_name"]:-}",
        "unique_name": "${JSON_DATA["db_unique_name"]:-}",
        "dbid": "${JSON_DATA["dbid"]:-}",
        "role": "${JSON_DATA["database_role"]:-}",
        "open_mode": "${JSON_DATA["open_mode"]:-}",
        "log_mode": "${JSON_DATA["log_mode"]:-}",
        "force_logging": "${JSON_DATA["force_logging"]:-}",
        "character_set": "${JSON_DATA["character_set"]:-}",
        "is_cdb": "${JSON_DATA["is_cdb"]:-}",
        "tde_status": "${JSON_DATA["tde_status"]:-}",
        "supplemental_logging": "${JSON_DATA["supplemental_logging"]:-}"
    },
    "discovery_complete": true
}
EOF
}

###############################################################################
# Main Execution
###############################################################################
main() {
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     ZDM Source Database Discovery Script                                 ║${NC}"
    echo -e "${GREEN}║     Project: PRODDB Migration to Oracle Database@Azure                  ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Discovery started at: $(date)"
    echo "Output files will be saved to current directory:"
    echo "  Text Report: $OUTPUT_FILE"
    echo "  JSON Summary: $JSON_FILE"
    echo ""
    
    # Source Oracle environment
    source_environment
    
    # Redirect all output to both terminal and file
    {
        echo "=================================================================="
        echo "ZDM Source Database Discovery Report"
        echo "Project: PRODDB Migration to Oracle Database@Azure"
        echo "Generated: $(date)"
        echo "Hostname: $(hostname)"
        echo "=================================================================="
        
        # Run all discovery functions with error trapping
        discover_os_info || echo -e "${RED}WARNING: OS info discovery failed${NC}"
        discover_oracle_environment || echo -e "${RED}WARNING: Oracle environment discovery failed${NC}"
        discover_database_config || echo -e "${RED}WARNING: Database config discovery failed${NC}"
        discover_cdb_pdb || echo -e "${RED}WARNING: CDB/PDB discovery failed${NC}"
        discover_tde_config || echo -e "${RED}WARNING: TDE config discovery failed${NC}"
        discover_supplemental_logging || echo -e "${RED}WARNING: Supplemental logging discovery failed${NC}"
        discover_redo_archive || echo -e "${RED}WARNING: Redo/Archive discovery failed${NC}"
        discover_network_config || echo -e "${RED}WARNING: Network config discovery failed${NC}"
        discover_authentication || echo -e "${RED}WARNING: Authentication discovery failed${NC}"
        discover_data_guard || echo -e "${RED}WARNING: Data Guard discovery failed${NC}"
        discover_schema_info || echo -e "${RED}WARNING: Schema info discovery failed${NC}"
        
        # Additional discovery for PRODDB
        discover_tablespace_autoextend || echo -e "${RED}WARNING: Tablespace autoextend discovery failed${NC}"
        discover_backup_schedule || echo -e "${RED}WARNING: Backup schedule discovery failed${NC}"
        discover_database_links || echo -e "${RED}WARNING: Database links discovery failed${NC}"
        discover_materialized_views || echo -e "${RED}WARNING: Materialized views discovery failed${NC}"
        discover_scheduler_jobs || echo -e "${RED}WARNING: Scheduler jobs discovery failed${NC}"
        
        echo ""
        echo "=================================================================="
        echo "Discovery completed at: $(date)"
        echo "=================================================================="
        
    } 2>&1 | tee "$OUTPUT_FILE"
    
    # Generate JSON output
    generate_json
    
    echo ""
    echo -e "${GREEN}Discovery complete!${NC}"
    echo "Text Report: $OUTPUT_FILE"
    echo "JSON Summary: $JSON_FILE"
}

# Run main function
main "$@"
