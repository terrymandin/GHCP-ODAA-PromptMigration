#!/bin/bash
################################################################################
# ZDM Source Database Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# 
# Purpose: Discover source database configuration for ZDM migration
# 
# Usage: Run on source database server as admin user (oracle)
#        This script will execute SQL commands as the oracle user
#
# Output: 
#   - Text report: ./zdm_source_discovery_<hostname>_<timestamp>.txt
#   - JSON summary: ./zdm_source_discovery_<hostname>_<timestamp>.json
################################################################################

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Timestamp for output files
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME_SHORT=$(hostname -s 2>/dev/null || hostname)

# Output files (in current working directory)
TEXT_OUTPUT="./zdm_source_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
JSON_OUTPUT="./zdm_source_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

# User configuration
ORACLE_USER="${ORACLE_USER:-oracle}"

################################################################################
# Helper Functions
################################################################################

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
    echo "[INFO] $1" >> "$TEXT_OUTPUT"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    echo "[WARN] $1" >> "$TEXT_OUTPUT"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[ERROR] $1" >> "$TEXT_OUTPUT"
}

log_section() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo "" >> "$TEXT_OUTPUT"
    echo "========================================" >> "$TEXT_OUTPUT"
    echo "$1" >> "$TEXT_OUTPUT"
    echo "========================================" >> "$TEXT_OUTPUT"
}

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

# Apply explicit overrides if provided
apply_overrides() {
    [ -n "${ORACLE_HOME_OVERRIDE:-}" ] && export ORACLE_HOME="$ORACLE_HOME_OVERRIDE"
    [ -n "${ORACLE_SID_OVERRIDE:-}" ] && export ORACLE_SID="$ORACLE_SID_OVERRIDE"
}

# Execute SQL and return output
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
        # Execute as oracle user
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

# Execute SQL and return single value
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
        # Execute as oracle user
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            echo "$sql_script" | ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd 2>/dev/null | grep -v '^$' | head -1
        else
            echo "$sql_script" | sudo -u "$ORACLE_USER" ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd 2>/dev/null | grep -v '^$' | head -1
        fi
    else
        echo "ERROR: ORACLE_HOME or ORACLE_SID not set"
        return 1
    fi
}

################################################################################
# Initialize
################################################################################

# Initialize output file
echo "ZDM Source Database Discovery Report" > "$TEXT_OUTPUT"
echo "Generated: $(date)" >> "$TEXT_OUTPUT"
echo "Hostname: $(hostname)" >> "$TEXT_OUTPUT"
echo "" >> "$TEXT_OUTPUT"

# Detect and apply Oracle environment
detect_oracle_env
apply_overrides

# Initialize JSON output
cat > "$JSON_OUTPUT" << 'EOJSON'
{
  "discovery_type": "source_database",
  "generated_timestamp": "TIMESTAMP_PLACEHOLDER",
  "hostname": "HOSTNAME_PLACEHOLDER",
EOJSON
sed -i "s/TIMESTAMP_PLACEHOLDER/$(date -Iseconds)/g" "$JSON_OUTPUT" 2>/dev/null || \
    sed -i '' "s/TIMESTAMP_PLACEHOLDER/$(date -Iseconds)/g" "$JSON_OUTPUT" 2>/dev/null
sed -i "s/HOSTNAME_PLACEHOLDER/$(hostname)/g" "$JSON_OUTPUT" 2>/dev/null || \
    sed -i '' "s/HOSTNAME_PLACEHOLDER/$(hostname)/g" "$JSON_OUTPUT" 2>/dev/null

################################################################################
# OS Information
################################################################################

log_section "OS INFORMATION"

log_info "Hostname: $(hostname)"
echo "Hostname: $(hostname)" >> "$TEXT_OUTPUT"

log_info "IP Addresses:"
ip addr show 2>/dev/null | grep 'inet ' | awk '{print $2}' | tee -a "$TEXT_OUTPUT" || \
    ifconfig 2>/dev/null | grep 'inet ' | awk '{print $2}' | tee -a "$TEXT_OUTPUT"

log_info "Operating System:"
if [ -f /etc/os-release ]; then
    cat /etc/os-release | tee -a "$TEXT_OUTPUT"
elif [ -f /etc/redhat-release ]; then
    cat /etc/redhat-release | tee -a "$TEXT_OUTPUT"
else
    uname -a | tee -a "$TEXT_OUTPUT"
fi

log_info "Disk Space:"
df -h | tee -a "$TEXT_OUTPUT"

################################################################################
# Oracle Environment
################################################################################

log_section "ORACLE ENVIRONMENT"

log_info "ORACLE_HOME: ${ORACLE_HOME:-NOT SET}"
echo "ORACLE_HOME: ${ORACLE_HOME:-NOT SET}" >> "$TEXT_OUTPUT"

log_info "ORACLE_SID: ${ORACLE_SID:-NOT SET}"
echo "ORACLE_SID: ${ORACLE_SID:-NOT SET}" >> "$TEXT_OUTPUT"

log_info "ORACLE_BASE: ${ORACLE_BASE:-NOT SET}"
echo "ORACLE_BASE: ${ORACLE_BASE:-NOT SET}" >> "$TEXT_OUTPUT"

if [ -n "${ORACLE_HOME:-}" ] && [ -f "$ORACLE_HOME/bin/sqlplus" ]; then
    log_info "Oracle Version:"
    if [ "$(whoami)" = "$ORACLE_USER" ]; then
        "$ORACLE_HOME/bin/sqlplus" -v 2>/dev/null | tee -a "$TEXT_OUTPUT"
    else
        sudo -u "$ORACLE_USER" "$ORACLE_HOME/bin/sqlplus" -v 2>/dev/null | tee -a "$TEXT_OUTPUT"
    fi
else
    log_warn "ORACLE_HOME not found or sqlplus not accessible"
fi

################################################################################
# Database Configuration
################################################################################

log_section "DATABASE CONFIGURATION"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    log_info "Database Name and Configuration:"
    run_sql "SELECT name, db_unique_name, dbid, database_role, open_mode, log_mode, force_logging FROM v\$database;" | tee -a "$TEXT_OUTPUT"
    
    log_info "Database Size (Data Files):"
    run_sql "SELECT ROUND(SUM(bytes)/1024/1024/1024, 2) AS size_gb FROM dba_data_files;" | tee -a "$TEXT_OUTPUT"
    
    log_info "Database Size (Temp Files):"
    run_sql "SELECT ROUND(SUM(bytes)/1024/1024/1024, 2) AS size_gb FROM dba_temp_files;" | tee -a "$TEXT_OUTPUT"
    
    log_info "Character Set:"
    run_sql "SELECT parameter, value FROM nls_database_parameters WHERE parameter IN ('NLS_CHARACTERSET', 'NLS_NCHAR_CHARACTERSET');" | tee -a "$TEXT_OUTPUT"
else
    log_warn "Cannot query database - Oracle environment not configured"
fi

################################################################################
# Container Database (CDB/PDB)
################################################################################

log_section "CONTAINER DATABASE CONFIGURATION"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    CDB_STATUS=$(run_sql_value "SELECT cdb FROM v\$database;")
    log_info "CDB Status: $CDB_STATUS"
    echo "CDB Status: $CDB_STATUS" >> "$TEXT_OUTPUT"
    
    if [ "$CDB_STATUS" = "YES" ]; then
        log_info "PDB List:"
        run_sql "SELECT pdb_name, status, open_mode FROM dba_pdbs ORDER BY pdb_name;" | tee -a "$TEXT_OUTPUT"
        
        log_info "PDB Details:"
        run_sql "SELECT con_id, name, open_mode FROM v\$pdbs ORDER BY con_id;" | tee -a "$TEXT_OUTPUT"
    else
        log_info "This is a non-CDB database"
    fi
else
    log_warn "Cannot query CDB status - Oracle environment not configured"
fi

################################################################################
# TDE Configuration
################################################################################

log_section "TDE CONFIGURATION"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    log_info "Encryption Wallet Status:"
    run_sql "SELECT wrl_type, wrl_parameter, status, wallet_type FROM v\$encryption_wallet;" | tee -a "$TEXT_OUTPUT"
    
    log_info "Encrypted Tablespaces:"
    run_sql "SELECT tablespace_name, encrypted FROM dba_tablespaces WHERE encrypted = 'YES';" | tee -a "$TEXT_OUTPUT"
    
    log_info "TDE Master Key Info:"
    run_sql "SELECT key_id, activation_time, creator FROM v\$encryption_keys WHERE activating_pdbid IS NOT NULL;" | tee -a "$TEXT_OUTPUT"
else
    log_warn "Cannot query TDE status - Oracle environment not configured"
fi

################################################################################
# Supplemental Logging
################################################################################

log_section "SUPPLEMENTAL LOGGING"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    log_info "Supplemental Logging Status:"
    run_sql "SELECT supplemental_log_data_min, supplemental_log_data_pk, supplemental_log_data_ui, supplemental_log_data_fk, supplemental_log_data_all FROM v\$database;" | tee -a "$TEXT_OUTPUT"
else
    log_warn "Cannot query supplemental logging - Oracle environment not configured"
fi

################################################################################
# Redo/Archive Configuration
################################################################################

log_section "REDO/ARCHIVE CONFIGURATION"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    log_info "Redo Log Groups:"
    run_sql "SELECT group#, thread#, bytes/1024/1024 AS size_mb, members, status FROM v\$log ORDER BY group#;" | tee -a "$TEXT_OUTPUT"
    
    log_info "Redo Log Members:"
    run_sql "SELECT group#, member, type FROM v\$logfile ORDER BY group#;" | tee -a "$TEXT_OUTPUT"
    
    log_info "Archive Log Destinations:"
    run_sql "SELECT dest_id, dest_name, status, destination FROM v\$archive_dest WHERE status != 'INACTIVE';" | tee -a "$TEXT_OUTPUT"
    
    log_info "Archive Log Mode:"
    run_sql "SELECT log_mode FROM v\$database;" | tee -a "$TEXT_OUTPUT"
else
    log_warn "Cannot query redo/archive config - Oracle environment not configured"
fi

################################################################################
# Network Configuration
################################################################################

log_section "NETWORK CONFIGURATION"

if [ -n "${ORACLE_HOME:-}" ]; then
    log_info "Listener Status:"
    if [ "$(whoami)" = "$ORACLE_USER" ]; then
        "$ORACLE_HOME/bin/lsnrctl" status 2>&1 | tee -a "$TEXT_OUTPUT" || log_warn "Could not get listener status"
    else
        sudo -u "$ORACLE_USER" "$ORACLE_HOME/bin/lsnrctl" status 2>&1 | tee -a "$TEXT_OUTPUT" || log_warn "Could not get listener status"
    fi
    
    log_info "tnsnames.ora:"
    if [ -f "$ORACLE_HOME/network/admin/tnsnames.ora" ]; then
        cat "$ORACLE_HOME/network/admin/tnsnames.ora" | tee -a "$TEXT_OUTPUT"
    else
        log_warn "tnsnames.ora not found at $ORACLE_HOME/network/admin/tnsnames.ora"
    fi
    
    log_info "sqlnet.ora:"
    if [ -f "$ORACLE_HOME/network/admin/sqlnet.ora" ]; then
        cat "$ORACLE_HOME/network/admin/sqlnet.ora" | tee -a "$TEXT_OUTPUT"
    else
        log_warn "sqlnet.ora not found at $ORACLE_HOME/network/admin/sqlnet.ora"
    fi
else
    log_warn "ORACLE_HOME not set - cannot check network configuration"
fi

################################################################################
# Authentication
################################################################################

log_section "AUTHENTICATION"

if [ -n "${ORACLE_HOME:-}" ]; then
    log_info "Password File Location:"
    PWFILE_PATH="$ORACLE_HOME/dbs/orapw${ORACLE_SID}"
    if [ -f "$PWFILE_PATH" ]; then
        ls -la "$PWFILE_PATH" | tee -a "$TEXT_OUTPUT"
    else
        log_warn "Password file not found at $PWFILE_PATH"
        # Check alternative locations
        find "$ORACLE_HOME/dbs" -name 'orapw*' 2>/dev/null | tee -a "$TEXT_OUTPUT"
    fi
fi

log_info "SSH Directory Contents (oracle user):"
ORACLE_SSH_DIR=$(eval echo ~$ORACLE_USER)/.ssh
if [ -d "$ORACLE_SSH_DIR" ]; then
    ls -la "$ORACLE_SSH_DIR" 2>/dev/null | tee -a "$TEXT_OUTPUT" || \
        sudo ls -la "$ORACLE_SSH_DIR" 2>/dev/null | tee -a "$TEXT_OUTPUT"
else
    log_warn "SSH directory not found for $ORACLE_USER"
fi

################################################################################
# Data Guard Configuration
################################################################################

log_section "DATA GUARD CONFIGURATION"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    log_info "Data Guard Parameters:"
    run_sql "SELECT name, value FROM v\$parameter WHERE name IN ('dg_broker_start', 'log_archive_config', 'log_archive_dest_1', 'log_archive_dest_2', 'log_archive_dest_state_1', 'log_archive_dest_state_2', 'fal_server', 'fal_client', 'standby_file_management', 'db_file_name_convert', 'log_file_name_convert') ORDER BY name;" | tee -a "$TEXT_OUTPUT"
    
    log_info "Database Role and Protection Mode:"
    run_sql "SELECT database_role, protection_mode, protection_level FROM v\$database;" | tee -a "$TEXT_OUTPUT"
else
    log_warn "Cannot query Data Guard config - Oracle environment not configured"
fi

################################################################################
# Schema Information
################################################################################

log_section "SCHEMA INFORMATION"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    log_info "Schema Sizes (non-system schemas > 100MB):"
    run_sql "SELECT owner, ROUND(SUM(bytes)/1024/1024, 2) AS size_mb FROM dba_segments WHERE owner NOT IN ('SYS', 'SYSTEM', 'OUTLN', 'DIP', 'ORACLE_OCM', 'DBSNMP', 'APPQOSSYS', 'WMSYS', 'XDB', 'CTXSYS', 'ANONYMOUS', 'MDSYS', 'OLAPSYS', 'ORDDATA', 'ORDSYS', 'SI_INFORMTN_SCHEMA', 'ORDPLUGINS', 'FLOWS_FILES', 'APEX_PUBLIC_USER', 'APEX_040200') GROUP BY owner HAVING SUM(bytes)/1024/1024 > 100 ORDER BY size_mb DESC;" | tee -a "$TEXT_OUTPUT"
    
    log_info "Invalid Objects by Owner/Type:"
    run_sql "SELECT owner, object_type, COUNT(*) AS invalid_count FROM dba_objects WHERE status = 'INVALID' GROUP BY owner, object_type ORDER BY owner, object_type;" | tee -a "$TEXT_OUTPUT"
else
    log_warn "Cannot query schema info - Oracle environment not configured"
fi

################################################################################
# ADDITIONAL DISCOVERY: Tablespace Autoextend Settings
################################################################################

log_section "TABLESPACE AUTOEXTEND SETTINGS"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    log_info "Tablespace Autoextend Configuration:"
    run_sql "SELECT tablespace_name, file_name, autoextensible, ROUND(bytes/1024/1024, 2) AS size_mb, ROUND(maxbytes/1024/1024, 2) AS max_size_mb, ROUND(increment_by * (SELECT value FROM v\$parameter WHERE name = 'db_block_size') / 1024 / 1024, 2) AS increment_mb FROM dba_data_files ORDER BY tablespace_name, file_name;" | tee -a "$TEXT_OUTPUT"
else
    log_warn "Cannot query tablespace settings - Oracle environment not configured"
fi

################################################################################
# ADDITIONAL DISCOVERY: Backup Schedule and Retention
################################################################################

log_section "BACKUP SCHEDULE AND RETENTION"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    log_info "RMAN Configuration:"
    run_sql "SELECT name, value FROM v\$rman_configuration ORDER BY name;" | tee -a "$TEXT_OUTPUT"
    
    log_info "Recent Backup Summary (last 7 days):"
    run_sql "SELECT input_type, status, TO_CHAR(start_time, 'YYYY-MM-DD HH24:MI:SS') AS start_time, TO_CHAR(end_time, 'YYYY-MM-DD HH24:MI:SS') AS end_time, ROUND(input_bytes/1024/1024/1024, 2) AS input_gb FROM v\$rman_backup_job_details WHERE start_time > SYSDATE - 7 ORDER BY start_time DESC;" | tee -a "$TEXT_OUTPUT"
    
    log_info "Backup Retention Policy:"
    run_sql "SELECT * FROM v\$rman_configuration WHERE name LIKE '%RETENTION%';" | tee -a "$TEXT_OUTPUT"
else
    log_warn "Cannot query backup info - Oracle environment not configured"
fi

################################################################################
# ADDITIONAL DISCOVERY: Database Links
################################################################################

log_section "DATABASE LINKS"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    log_info "All Database Links:"
    run_sql "SELECT owner, db_link, username, host, created FROM dba_db_links ORDER BY owner, db_link;" | tee -a "$TEXT_OUTPUT"
else
    log_warn "Cannot query database links - Oracle environment not configured"
fi

################################################################################
# ADDITIONAL DISCOVERY: Materialized View Refresh Schedules
################################################################################

log_section "MATERIALIZED VIEW REFRESH SCHEDULES"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    log_info "Materialized Views and Refresh Settings:"
    run_sql "SELECT owner, mview_name, refresh_mode, refresh_method, build_mode, fast_refreshable, last_refresh_type, TO_CHAR(last_refresh_date, 'YYYY-MM-DD HH24:MI:SS') AS last_refresh FROM dba_mviews ORDER BY owner, mview_name;" | tee -a "$TEXT_OUTPUT"
    
    log_info "Materialized View Refresh Groups:"
    run_sql "SELECT rowner, rname, refgroup, implicit_destroy, push_deferred_rpc, refresh_after_errors, job, TO_CHAR(next_date, 'YYYY-MM-DD HH24:MI:SS') AS next_date, interval FROM dba_refresh ORDER BY rowner, rname;" | tee -a "$TEXT_OUTPUT"
else
    log_warn "Cannot query materialized views - Oracle environment not configured"
fi

################################################################################
# ADDITIONAL DISCOVERY: Scheduler Jobs
################################################################################

log_section "SCHEDULER JOBS"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    log_info "Scheduler Jobs (enabled):"
    run_sql "SELECT owner, job_name, job_type, state, enabled, TO_CHAR(last_start_date, 'YYYY-MM-DD HH24:MI:SS') AS last_start, TO_CHAR(next_run_date, 'YYYY-MM-DD HH24:MI:SS') AS next_run, repeat_interval FROM dba_scheduler_jobs WHERE enabled = 'TRUE' ORDER BY owner, job_name;" | tee -a "$TEXT_OUTPUT"
    
    log_info "DBMS_JOBS (legacy jobs):"
    run_sql "SELECT job, schema_user, TO_CHAR(last_date, 'YYYY-MM-DD HH24:MI:SS') AS last_date, TO_CHAR(next_date, 'YYYY-MM-DD HH24:MI:SS') AS next_date, interval, broken, what FROM dba_jobs ORDER BY job;" | tee -a "$TEXT_OUTPUT"
else
    log_warn "Cannot query scheduler jobs - Oracle environment not configured"
fi

################################################################################
# Finalize JSON Output
################################################################################

log_section "FINALIZING DISCOVERY"

# Get key values for JSON
DB_NAME=$(run_sql_value "SELECT name FROM v\$database;" 2>/dev/null)
DB_VERSION=$(run_sql_value "SELECT version FROM v\$instance;" 2>/dev/null)
DB_SIZE=$(run_sql_value "SELECT ROUND(SUM(bytes)/1024/1024/1024, 2) FROM dba_data_files;" 2>/dev/null)
LOG_MODE=$(run_sql_value "SELECT log_mode FROM v\$database;" 2>/dev/null)
CDB_STATUS=$(run_sql_value "SELECT cdb FROM v\$database;" 2>/dev/null)
TDE_STATUS=$(run_sql_value "SELECT status FROM v\$encryption_wallet WHERE rownum = 1;" 2>/dev/null)
CHARSET=$(run_sql_value "SELECT value FROM nls_database_parameters WHERE parameter = 'NLS_CHARACTERSET';" 2>/dev/null)

# Complete JSON output
cat >> "$JSON_OUTPUT" << EOJSON
  "oracle_environment": {
    "oracle_home": "${ORACLE_HOME:-NOT SET}",
    "oracle_sid": "${ORACLE_SID:-NOT SET}",
    "oracle_base": "${ORACLE_BASE:-NOT SET}"
  },
  "database_configuration": {
    "database_name": "${DB_NAME:-UNKNOWN}",
    "version": "${DB_VERSION:-UNKNOWN}",
    "size_gb": "${DB_SIZE:-UNKNOWN}",
    "log_mode": "${LOG_MODE:-UNKNOWN}",
    "cdb_status": "${CDB_STATUS:-UNKNOWN}",
    "tde_status": "${TDE_STATUS:-NOT CONFIGURED}",
    "character_set": "${CHARSET:-UNKNOWN}"
  },
  "discovery_status": "COMPLETED"
}
EOJSON

log_info "Discovery completed successfully"
log_info "Text report: $TEXT_OUTPUT"
log_info "JSON summary: $JSON_OUTPUT"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Discovery Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo "Text report: $TEXT_OUTPUT"
echo "JSON summary: $JSON_OUTPUT"
