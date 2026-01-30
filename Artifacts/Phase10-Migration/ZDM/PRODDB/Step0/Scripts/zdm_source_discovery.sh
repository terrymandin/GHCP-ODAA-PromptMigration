#!/bin/bash
# ZDM Source Database Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# Target: proddb01.corp.example.com
# Generated: 2026-01-30

# NO set -e - We want to continue even if some checks fail
SECTION_ERRORS=0

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# ENVIRONMENT DETECTION AND SETUP
# =============================================================================

# Auto-detect Oracle environment
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
[ -n "${ORACLE_HOME_OVERRIDE:-}" ] && export ORACLE_HOME="$ORACLE_HOME_OVERRIDE"
[ -n "${ORACLE_SID_OVERRIDE:-}" ] && export ORACLE_SID="$ORACLE_SID_OVERRIDE"
[ -n "${ORACLE_BASE_OVERRIDE:-}" ] && export ORACLE_BASE="$ORACLE_BASE_OVERRIDE"

# Extract export statements from profiles (bypasses interactive guards)
for profile in /etc/profile ~/.bash_profile ~/.bashrc; do
    if [ -f "$profile" ]; then
        eval "$(grep -E '^export\s+(ORACLE_HOME|ORACLE_SID|ORACLE_BASE|TNS_ADMIN|PATH)=' "$profile" 2>/dev/null)" || true
    fi
done

# Run auto-detection
detect_oracle_env

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname)
OUTPUT_FILE="./zdm_source_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_source_discovery_${HOSTNAME}_${TIMESTAMP}.json"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

log_section() {
    local title="$1"
    echo -e "\n${BLUE}=================================================================================${NC}"
    echo -e "${BLUE}  $title${NC}"
    echo -e "${BLUE}=================================================================================${NC}\n"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Execute SQL as oracle user
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
        if [ "$(whoami)" = "oracle" ]; then
            echo "$sql_script" | $sqlplus_cmd
        else
            echo "$sql_script" | sudo -u oracle -E ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd
        fi
    else
        echo "ERROR: ORACLE_HOME or ORACLE_SID not set"
        return 1
    fi
}

# Get single SQL value
run_sql_value() {
    local sql_query="$1"
    run_sql "$sql_query" | grep -v '^$' | tail -1 | xargs
}

# Write to both terminal and output file
write_output() {
    echo "$1" | tee -a "$OUTPUT_FILE"
}

# =============================================================================
# DISCOVERY SECTIONS
# =============================================================================

discover_os_info() {
    log_section "OS INFORMATION"
    {
        echo "=== OS INFORMATION ==="
        echo "Hostname: $(hostname)"
        echo "IP Addresses:"
        ip addr show 2>/dev/null | grep 'inet ' | awk '{print "  " $2}' || hostname -I 2>/dev/null | tr ' ' '\n' | sed 's/^/  /'
        echo ""
        echo "Operating System:"
        cat /etc/os-release 2>/dev/null || cat /etc/redhat-release 2>/dev/null || uname -a
        echo ""
        echo "Kernel Version: $(uname -r)"
        echo ""
        echo "Disk Space:"
        df -h 2>/dev/null | head -20
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "OS information collected"
}

discover_oracle_env() {
    log_section "ORACLE ENVIRONMENT"
    {
        echo "=== ORACLE ENVIRONMENT ==="
        echo "ORACLE_HOME: ${ORACLE_HOME:-NOT SET}"
        echo "ORACLE_SID: ${ORACLE_SID:-NOT SET}"
        echo "ORACLE_BASE: ${ORACLE_BASE:-NOT SET}"
        echo "TNS_ADMIN: ${TNS_ADMIN:-NOT SET}"
        echo ""
        if [ -n "${ORACLE_HOME:-}" ]; then
            echo "Oracle Version:"
            $ORACLE_HOME/bin/sqlplus -v 2>/dev/null || echo "Unable to determine Oracle version"
        fi
        echo ""
        echo "/etc/oratab contents:"
        cat /etc/oratab 2>/dev/null | grep -v '^#' | grep -v '^$' || echo "No oratab found"
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "Oracle environment collected"
}

discover_db_config() {
    log_section "DATABASE CONFIGURATION"
    {
        echo "=== DATABASE CONFIGURATION ==="
        echo ""
        echo "Database Identity:"
        run_sql "SELECT name, db_unique_name, dbid, created FROM v\$database;"
        echo ""
        echo "Database Role and Mode:"
        run_sql "SELECT database_role, open_mode, log_mode, force_logging FROM v\$database;"
        echo ""
        echo "Instance Status:"
        run_sql "SELECT instance_name, host_name, version, status, startup_time FROM v\$instance;"
        echo ""
        echo "Database Size - Data Files:"
        run_sql "SELECT ROUND(SUM(bytes)/1024/1024/1024, 2) as \"Size (GB)\" FROM dba_data_files;"
        echo ""
        echo "Database Size - Temp Files:"
        run_sql "SELECT ROUND(SUM(bytes)/1024/1024/1024, 2) as \"Size (GB)\" FROM dba_temp_files;"
        echo ""
        echo "Character Set:"
        run_sql "SELECT parameter, value FROM nls_database_parameters WHERE parameter IN ('NLS_CHARACTERSET', 'NLS_NCHAR_CHARACTERSET');"
        echo ""
        echo "Database Parameters:"
        run_sql "SELECT name, value FROM v\$parameter WHERE name IN ('compatible', 'db_block_size', 'db_files', 'processes', 'sessions', 'memory_target', 'sga_target', 'pga_aggregate_target') ORDER BY name;"
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "Database configuration collected"
}

discover_cdb_pdb() {
    log_section "CONTAINER DATABASE / PDB"
    {
        echo "=== CONTAINER DATABASE / PDB ==="
        echo ""
        echo "CDB Status:"
        run_sql "SELECT cdb FROM v\$database;"
        echo ""
        echo "PDB Information:"
        run_sql "SELECT con_id, name, open_mode, restricted FROM v\$pdbs ORDER BY con_id;" 2>/dev/null || echo "Not a CDB or no PDBs found"
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "CDB/PDB information collected"
}

discover_tde() {
    log_section "TDE CONFIGURATION"
    {
        echo "=== TDE CONFIGURATION ==="
        echo ""
        echo "Encryption Wallet Status:"
        run_sql "SELECT wrl_type, wrl_parameter, status, wallet_type FROM v\$encryption_wallet;"
        echo ""
        echo "Encrypted Tablespaces:"
        run_sql "SELECT tablespace_name, encrypted FROM dba_tablespaces WHERE encrypted = 'YES';" 2>/dev/null || echo "No encrypted tablespaces found"
        echo ""
        echo "TDE Master Key:"
        run_sql "SELECT key_id, creator, key_use, creation_time FROM v\$encryption_keys WHERE activation_time IS NOT NULL;" 2>/dev/null || echo "No TDE keys found"
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "TDE configuration collected"
}

discover_supplemental_logging() {
    log_section "SUPPLEMENTAL LOGGING"
    {
        echo "=== SUPPLEMENTAL LOGGING ==="
        echo ""
        echo "Database Supplemental Logging:"
        run_sql "SELECT supplemental_log_data_min, supplemental_log_data_pk, supplemental_log_data_ui, supplemental_log_data_fk, supplemental_log_data_all FROM v\$database;"
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "Supplemental logging collected"
}

discover_redo_archive() {
    log_section "REDO AND ARCHIVE CONFIGURATION"
    {
        echo "=== REDO AND ARCHIVE CONFIGURATION ==="
        echo ""
        echo "Redo Log Groups:"
        run_sql "SELECT group#, thread#, sequence#, bytes/1024/1024 as \"Size (MB)\", members, status FROM v\$log ORDER BY group#;"
        echo ""
        echo "Redo Log Members:"
        run_sql "SELECT group#, member, type FROM v\$logfile ORDER BY group#;"
        echo ""
        echo "Archive Log Mode:"
        run_sql "SELECT log_mode FROM v\$database;"
        echo ""
        echo "Archive Destinations:"
        run_sql "SELECT dest_id, dest_name, status, destination FROM v\$archive_dest WHERE status = 'VALID';"
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "Redo/Archive configuration collected"
}

discover_network() {
    log_section "NETWORK CONFIGURATION"
    {
        echo "=== NETWORK CONFIGURATION ==="
        echo ""
        echo "Listener Status:"
        if [ -n "${ORACLE_HOME:-}" ]; then
            $ORACLE_HOME/bin/lsnrctl status 2>/dev/null || echo "Unable to get listener status"
        fi
        echo ""
        echo "tnsnames.ora contents:"
        if [ -n "${TNS_ADMIN:-}" ] && [ -f "${TNS_ADMIN}/tnsnames.ora" ]; then
            cat "${TNS_ADMIN}/tnsnames.ora"
        elif [ -n "${ORACLE_HOME:-}" ] && [ -f "${ORACLE_HOME}/network/admin/tnsnames.ora" ]; then
            cat "${ORACLE_HOME}/network/admin/tnsnames.ora"
        else
            echo "tnsnames.ora not found"
        fi
        echo ""
        echo "sqlnet.ora contents:"
        if [ -n "${TNS_ADMIN:-}" ] && [ -f "${TNS_ADMIN}/sqlnet.ora" ]; then
            cat "${TNS_ADMIN}/sqlnet.ora"
        elif [ -n "${ORACLE_HOME:-}" ] && [ -f "${ORACLE_HOME}/network/admin/sqlnet.ora" ]; then
            cat "${ORACLE_HOME}/network/admin/sqlnet.ora"
        else
            echo "sqlnet.ora not found"
        fi
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "Network configuration collected"
}

discover_auth() {
    log_section "AUTHENTICATION"
    {
        echo "=== AUTHENTICATION ==="
        echo ""
        echo "Password File Location:"
        if [ -n "${ORACLE_HOME:-}" ]; then
            ls -la ${ORACLE_HOME}/dbs/orapw* 2>/dev/null || echo "No password file found in ORACLE_HOME/dbs"
        fi
        echo ""
        echo "SSH Directory Contents:"
        ls -la ~/.ssh/ 2>/dev/null || echo "No .ssh directory found"
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "Authentication configuration collected"
}

discover_dataguard() {
    log_section "DATA GUARD CONFIGURATION"
    {
        echo "=== DATA GUARD CONFIGURATION ==="
        echo ""
        echo "Data Guard Parameters:"
        run_sql "SELECT name, value FROM v\$parameter WHERE name LIKE 'log_archive_dest%' OR name LIKE 'fal_%' OR name LIKE 'standby%' OR name = 'db_file_name_convert' OR name = 'log_file_name_convert' ORDER BY name;"
        echo ""
        echo "Data Guard Status:"
        run_sql "SELECT database_role, protection_mode, protection_level, switchover_status FROM v\$database;"
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "Data Guard configuration collected"
}

discover_schemas() {
    log_section "SCHEMA INFORMATION"
    {
        echo "=== SCHEMA INFORMATION ==="
        echo ""
        echo "Schema Sizes (> 100MB):"
        run_sql "SELECT owner, ROUND(SUM(bytes)/1024/1024, 2) as \"Size (MB)\" FROM dba_segments WHERE owner NOT IN ('SYS', 'SYSTEM', 'OUTLN', 'DBSNMP', 'APPQOSSYS', 'WMSYS', 'XDB', 'CTXSYS', 'ORDDATA', 'ORDSYS', 'MDSYS', 'OJVMSYS', 'AUDSYS', 'OLAPSYS', 'LBACSYS', 'DVSYS', 'GSMADMIN_INTERNAL') GROUP BY owner HAVING SUM(bytes)/1024/1024 > 100 ORDER BY 2 DESC;"
        echo ""
        echo "Invalid Objects by Owner/Type:"
        run_sql "SELECT owner, object_type, COUNT(*) as invalid_count FROM dba_objects WHERE status = 'INVALID' GROUP BY owner, object_type ORDER BY owner, object_type;"
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "Schema information collected"
}

# =============================================================================
# ADDITIONAL DISCOVERY REQUIREMENTS FOR PRODDB
# =============================================================================

discover_tablespace_autoextend() {
    log_section "TABLESPACE AUTOEXTEND SETTINGS"
    {
        echo "=== TABLESPACE AUTOEXTEND SETTINGS ==="
        echo ""
        echo "Datafile Autoextend Configuration:"
        run_sql "SELECT tablespace_name, file_name, ROUND(bytes/1024/1024, 2) as \"Current Size (MB)\", autoextensible, ROUND(maxbytes/1024/1024, 2) as \"Max Size (MB)\", ROUND(increment_by*8192/1024/1024, 2) as \"Increment (MB)\" FROM dba_data_files ORDER BY tablespace_name;"
        echo ""
        echo "Tempfile Autoextend Configuration:"
        run_sql "SELECT tablespace_name, file_name, ROUND(bytes/1024/1024, 2) as \"Current Size (MB)\", autoextensible, ROUND(maxbytes/1024/1024, 2) as \"Max Size (MB)\" FROM dba_temp_files ORDER BY tablespace_name;"
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "Tablespace autoextend settings collected"
}

discover_backup_schedule() {
    log_section "BACKUP SCHEDULE AND RETENTION"
    {
        echo "=== BACKUP SCHEDULE AND RETENTION ==="
        echo ""
        echo "RMAN Configuration:"
        run_sql "SELECT name, value FROM v\$rman_configuration ORDER BY name;"
        echo ""
        echo "Recent Backup Summary (Last 7 Days):"
        run_sql "SELECT input_type, status, to_char(start_time, 'YYYY-MM-DD HH24:MI:SS') as start_time, to_char(end_time, 'YYYY-MM-DD HH24:MI:SS') as end_time, ROUND(elapsed_seconds/60, 2) as \"Duration (min)\" FROM v\$rman_backup_job_details WHERE start_time > SYSDATE - 7 ORDER BY start_time DESC;"
        echo ""
        echo "Backup Retention Settings:"
        run_sql "SELECT * FROM v\$backup_set WHERE completion_time > SYSDATE - 30 ORDER BY completion_time DESC FETCH FIRST 20 ROWS ONLY;"
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "Backup schedule and retention collected"
}

discover_database_links() {
    log_section "DATABASE LINKS"
    {
        echo "=== DATABASE LINKS ==="
        echo ""
        echo "All Database Links:"
        run_sql "SELECT owner, db_link, username, host, created FROM dba_db_links ORDER BY owner, db_link;"
        echo ""
        echo "Public Database Links:"
        run_sql "SELECT db_link, username, host, created FROM dba_db_links WHERE owner = 'PUBLIC' ORDER BY db_link;"
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "Database links collected"
}

discover_materialized_views() {
    log_section "MATERIALIZED VIEW REFRESH SCHEDULES"
    {
        echo "=== MATERIALIZED VIEW REFRESH SCHEDULES ==="
        echo ""
        echo "Materialized Views and Refresh Settings:"
        run_sql "SELECT owner, mview_name, refresh_mode, refresh_method, build_mode, fast_refreshable, last_refresh_type, to_char(last_refresh_date, 'YYYY-MM-DD HH24:MI:SS') as last_refresh FROM dba_mviews ORDER BY owner, mview_name;"
        echo ""
        echo "Materialized View Refresh Groups:"
        run_sql "SELECT rowner, rname, refgroup, implicit_destroy, push_deferred_rpc, refresh_after_errors, rollback_seg, job, broken, next_date, interval FROM dba_refresh ORDER BY rowner, rname;"
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "Materialized view refresh schedules collected"
}

discover_scheduler_jobs() {
    log_section "SCHEDULER JOBS"
    {
        echo "=== SCHEDULER JOBS ==="
        echo ""
        echo "Enabled Scheduler Jobs:"
        run_sql "SELECT owner, job_name, job_type, enabled, state, repeat_interval, next_run_date FROM dba_scheduler_jobs WHERE enabled = 'TRUE' ORDER BY owner, job_name;"
        echo ""
        echo "All Scheduler Jobs (with action):"
        run_sql "SELECT owner, job_name, job_type, enabled, state, job_action FROM dba_scheduler_jobs ORDER BY owner, job_name;"
        echo ""
        echo "DBMS_JOB entries:"
        run_sql "SELECT job, log_user, priv_user, schema_user, what, next_date, interval, broken FROM dba_jobs ORDER BY job;"
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "Scheduler jobs collected"
}

# =============================================================================
# JSON OUTPUT GENERATION
# =============================================================================

generate_json_summary() {
    log_section "GENERATING JSON SUMMARY"
    
    # Collect key values for JSON
    local db_name=$(run_sql_value "SELECT name FROM v\$database;")
    local db_unique_name=$(run_sql_value "SELECT db_unique_name FROM v\$database;")
    local dbid=$(run_sql_value "SELECT dbid FROM v\$database;")
    local db_role=$(run_sql_value "SELECT database_role FROM v\$database;")
    local open_mode=$(run_sql_value "SELECT open_mode FROM v\$database;")
    local log_mode=$(run_sql_value "SELECT log_mode FROM v\$database;")
    local force_logging=$(run_sql_value "SELECT force_logging FROM v\$database;")
    local is_cdb=$(run_sql_value "SELECT cdb FROM v\$database;")
    local oracle_version=$(run_sql_value "SELECT version FROM v\$instance;")
    local charset=$(run_sql_value "SELECT value FROM nls_database_parameters WHERE parameter = 'NLS_CHARACTERSET';")
    local ncharset=$(run_sql_value "SELECT value FROM nls_database_parameters WHERE parameter = 'NLS_NCHAR_CHARACTERSET';")
    local db_size_gb=$(run_sql_value "SELECT ROUND(SUM(bytes)/1024/1024/1024, 2) FROM dba_data_files;")
    local wallet_status=$(run_sql_value "SELECT status FROM v\$encryption_wallet WHERE rownum = 1;")
    
    cat > "$JSON_FILE" <<EOF
{
  "discovery_type": "source",
  "discovery_timestamp": "$(date -Iseconds)",
  "hostname": "$HOSTNAME",
  "project": "PRODDB Migration to Oracle Database@Azure",
  "oracle_environment": {
    "oracle_home": "${ORACLE_HOME:-unknown}",
    "oracle_sid": "${ORACLE_SID:-unknown}",
    "oracle_base": "${ORACLE_BASE:-unknown}",
    "oracle_version": "${oracle_version:-unknown}"
  },
  "database_config": {
    "db_name": "${db_name:-unknown}",
    "db_unique_name": "${db_unique_name:-unknown}",
    "dbid": "${dbid:-unknown}",
    "database_role": "${db_role:-unknown}",
    "open_mode": "${open_mode:-unknown}",
    "log_mode": "${log_mode:-unknown}",
    "force_logging": "${force_logging:-unknown}",
    "is_cdb": "${is_cdb:-unknown}",
    "character_set": "${charset:-unknown}",
    "national_character_set": "${ncharset:-unknown}",
    "database_size_gb": "${db_size_gb:-unknown}"
  },
  "tde_config": {
    "wallet_status": "${wallet_status:-unknown}"
  },
  "section_errors": $SECTION_ERRORS,
  "output_files": {
    "text_report": "$OUTPUT_FILE",
    "json_summary": "$JSON_FILE"
  }
}
EOF
    log_success "JSON summary generated: $JSON_FILE"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    echo -e "${GREEN}=============================================================================${NC}"
    echo -e "${GREEN}  ZDM Source Database Discovery Script${NC}"
    echo -e "${GREEN}  Project: PRODDB Migration to Oracle Database@Azure${NC}"
    echo -e "${GREEN}  Host: $HOSTNAME${NC}"
    echo -e "${GREEN}  Timestamp: $(date)${NC}"
    echo -e "${GREEN}=============================================================================${NC}"
    
    # Initialize output file
    echo "ZDM Source Database Discovery Report" > "$OUTPUT_FILE"
    echo "=====================================" >> "$OUTPUT_FILE"
    echo "Project: PRODDB Migration to Oracle Database@Azure" >> "$OUTPUT_FILE"
    echo "Host: $HOSTNAME" >> "$OUTPUT_FILE"
    echo "Generated: $(date)" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    # Run all discovery sections (continue on failure)
    discover_os_info || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_oracle_env || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_db_config || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_cdb_pdb || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_tde || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_supplemental_logging || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_redo_archive || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_network || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_auth || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_dataguard || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_schemas || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    
    # Additional PRODDB-specific discovery
    discover_tablespace_autoextend || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_backup_schedule || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_database_links || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_materialized_views || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_scheduler_jobs || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    
    # Generate JSON summary
    generate_json_summary
    
    echo ""
    echo -e "${GREEN}=============================================================================${NC}"
    echo -e "${GREEN}  Discovery Complete${NC}"
    echo -e "${GREEN}=============================================================================${NC}"
    echo -e "Text Report: ${BLUE}$OUTPUT_FILE${NC}"
    echo -e "JSON Summary: ${BLUE}$JSON_FILE${NC}"
    if [ $SECTION_ERRORS -gt 0 ]; then
        echo -e "${YELLOW}Warning: $SECTION_ERRORS section(s) encountered errors${NC}"
    fi
}

# Show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "ZDM Source Database Discovery Script"
    echo "Project: PRODDB Migration to Oracle Database@Azure"
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help message"
    echo ""
    echo "Environment Variables (optional overrides):"
    echo "  ORACLE_HOME_OVERRIDE    Override auto-detected ORACLE_HOME"
    echo "  ORACLE_SID_OVERRIDE     Override auto-detected ORACLE_SID"
    echo "  ORACLE_BASE_OVERRIDE    Override auto-detected ORACLE_BASE"
    echo ""
    echo "Output:"
    echo "  ./zdm_source_discovery_<hostname>_<timestamp>.txt"
    echo "  ./zdm_source_discovery_<hostname>_<timestamp>.json"
}

# Parse command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    *)
        main
        ;;
esac
