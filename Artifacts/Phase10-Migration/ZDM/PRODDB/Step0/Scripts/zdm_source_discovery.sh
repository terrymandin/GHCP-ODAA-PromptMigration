#!/bin/bash
# ===========================================
# ZDM Source Database Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# Target Server: proddb01.corp.example.com
# Generated: 2026-01-30
# ===========================================
#
# This script discovers source database configuration for ZDM migration.
# Run as: oracle user (or admin user with sudo to oracle)
#
# Usage:
#   ./zdm_source_discovery.sh
#
# Output:
#   - zdm_source_discovery_<hostname>_<timestamp>.txt (human-readable)
#   - zdm_source_discovery_<hostname>_<timestamp>.json (machine-parseable)
# ===========================================

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# User configuration
ORACLE_USER="${ORACLE_USER:-oracle}"

# Timestamp and hostname for output files
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME_SHORT=$(hostname -s)
OUTPUT_TXT="./zdm_source_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
OUTPUT_JSON="./zdm_source_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

# Initialize JSON object
declare -A JSON_DATA

# ===========================================
# HELPER FUNCTIONS
# ===========================================

log_section() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
    echo -e "\n=== $1 ===" >> "$OUTPUT_TXT"
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
    echo "[INFO] $1" >> "$OUTPUT_TXT"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    echo "[WARN] $1" >> "$OUTPUT_TXT"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[ERROR] $1" >> "$OUTPUT_TXT"
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
}

# Run SQL and return output
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
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            echo "$sql_script" | $sqlplus_cmd 2>/dev/null
        else
            echo "$sql_script" | sudo -u "$ORACLE_USER" ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd 2>/dev/null
        fi
    else
        echo "ERROR: ORACLE_HOME or ORACLE_SID not set"
        return 1
    fi
}

# Run SQL and return single value
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
        local result
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            result=$(echo "$sql_script" | $sqlplus_cmd 2>/dev/null | tr -d '[:space:]')
        else
            result=$(echo "$sql_script" | sudo -u "$ORACLE_USER" ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd 2>/dev/null | tr -d '[:space:]')
        fi
        echo "$result"
    else
        echo "ERROR"
        return 1
    fi
}

# ===========================================
# MAIN DISCOVERY
# ===========================================

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  ZDM Source Database Discovery${NC}"
echo -e "${BLUE}  Project: PRODDB Migration${NC}"
echo -e "${BLUE}=========================================${NC}"

# Initialize output file
echo "ZDM Source Database Discovery Report" > "$OUTPUT_TXT"
echo "Project: PRODDB Migration to Oracle Database@Azure" >> "$OUTPUT_TXT"
echo "Generated: $(date)" >> "$OUTPUT_TXT"
echo "Hostname: $(hostname)" >> "$OUTPUT_TXT"
echo "==========================================" >> "$OUTPUT_TXT"

# Detect Oracle environment
detect_oracle_env

# -------------------------------------------
# OS INFORMATION
# -------------------------------------------
log_section "OS Information"

HOSTNAME_FULL=$(hostname -f 2>/dev/null || hostname)
IP_ADDRESSES=$(hostname -I 2>/dev/null || ip addr show | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | tr '\n' ' ')
OS_VERSION=$(cat /etc/os-release 2>/dev/null | grep "PRETTY_NAME" | cut -d'"' -f2)
KERNEL_VERSION=$(uname -r)

log_info "Hostname: $HOSTNAME_FULL"
log_info "IP Addresses: $IP_ADDRESSES"
log_info "OS Version: $OS_VERSION"
log_info "Kernel: $KERNEL_VERSION"

echo "" >> "$OUTPUT_TXT"
echo "Disk Space:" >> "$OUTPUT_TXT"
df -h >> "$OUTPUT_TXT" 2>/dev/null

# -------------------------------------------
# ORACLE ENVIRONMENT
# -------------------------------------------
log_section "Oracle Environment"

log_info "ORACLE_HOME: ${ORACLE_HOME:-NOT SET}"
log_info "ORACLE_SID: ${ORACLE_SID:-NOT SET}"
log_info "ORACLE_BASE: ${ORACLE_BASE:-NOT SET}"

if [ -n "${ORACLE_HOME:-}" ] && [ -f "$ORACLE_HOME/bin/sqlplus" ]; then
    ORACLE_VERSION=$(run_sql_value "SELECT version FROM v\$instance;")
    log_info "Oracle Version: $ORACLE_VERSION"
else
    log_error "Oracle environment not properly configured"
    ORACLE_VERSION="UNKNOWN"
fi

# -------------------------------------------
# DATABASE CONFIGURATION
# -------------------------------------------
log_section "Database Configuration"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    DB_NAME=$(run_sql_value "SELECT name FROM v\$database;")
    DB_UNIQUE_NAME=$(run_sql_value "SELECT db_unique_name FROM v\$database;")
    DBID=$(run_sql_value "SELECT dbid FROM v\$database;")
    DB_ROLE=$(run_sql_value "SELECT database_role FROM v\$database;")
    OPEN_MODE=$(run_sql_value "SELECT open_mode FROM v\$database;")
    LOG_MODE=$(run_sql_value "SELECT log_mode FROM v\$database;")
    FORCE_LOGGING=$(run_sql_value "SELECT force_logging FROM v\$database;")
    PLATFORM=$(run_sql_value "SELECT platform_name FROM v\$database;")
    
    log_info "Database Name: $DB_NAME"
    log_info "DB Unique Name: $DB_UNIQUE_NAME"
    log_info "DBID: $DBID"
    log_info "Database Role: $DB_ROLE"
    log_info "Open Mode: $OPEN_MODE"
    log_info "Log Mode: $LOG_MODE"
    log_info "Force Logging: $FORCE_LOGGING"
    log_info "Platform: $PLATFORM"
    
    # Character Set
    echo "" >> "$OUTPUT_TXT"
    echo "Character Set:" >> "$OUTPUT_TXT"
    run_sql "SELECT parameter, value FROM nls_database_parameters WHERE parameter IN ('NLS_CHARACTERSET', 'NLS_NCHAR_CHARACTERSET');" >> "$OUTPUT_TXT"
    
    CHARACTERSET=$(run_sql_value "SELECT value FROM nls_database_parameters WHERE parameter = 'NLS_CHARACTERSET';")
    NCHAR_CHARACTERSET=$(run_sql_value "SELECT value FROM nls_database_parameters WHERE parameter = 'NLS_NCHAR_CHARACTERSET';")
    log_info "Character Set: $CHARACTERSET"
    log_info "National Character Set: $NCHAR_CHARACTERSET"
    
    # Database Size
    echo "" >> "$OUTPUT_TXT"
    echo "Database Size:" >> "$OUTPUT_TXT"
    run_sql "SELECT 'Data Files' AS file_type, ROUND(SUM(bytes)/1024/1024/1024, 2) AS size_gb FROM dba_data_files
             UNION ALL
             SELECT 'Temp Files', ROUND(SUM(bytes)/1024/1024/1024, 2) FROM dba_temp_files
             UNION ALL
             SELECT 'Redo Logs', ROUND(SUM(bytes)/1024/1024/1024, 2) FROM v\$log;" >> "$OUTPUT_TXT"
    
    DATAFILE_SIZE=$(run_sql_value "SELECT ROUND(SUM(bytes)/1024/1024/1024, 2) FROM dba_data_files;")
    TEMPFILE_SIZE=$(run_sql_value "SELECT ROUND(SUM(bytes)/1024/1024/1024, 2) FROM dba_temp_files;")
    log_info "Data File Size: ${DATAFILE_SIZE} GB"
    log_info "Temp File Size: ${TEMPFILE_SIZE} GB"
else
    log_error "Cannot query database - Oracle environment not set"
fi

# -------------------------------------------
# CONTAINER DATABASE STATUS
# -------------------------------------------
log_section "Container Database Status"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    CDB_STATUS=$(run_sql_value "SELECT CDB FROM v\$database;")
    log_info "CDB Status: $CDB_STATUS"
    
    if [ "$CDB_STATUS" = "YES" ]; then
        echo "" >> "$OUTPUT_TXT"
        echo "PDB Information:" >> "$OUTPUT_TXT"
        run_sql "SELECT pdb_name, status, open_mode FROM dba_pdbs ORDER BY pdb_name;" >> "$OUTPUT_TXT"
    fi
fi

# -------------------------------------------
# TDE CONFIGURATION
# -------------------------------------------
log_section "TDE Configuration"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    TDE_STATUS=$(run_sql_value "SELECT status FROM v\$encryption_wallet WHERE rownum = 1;")
    WALLET_TYPE=$(run_sql_value "SELECT wallet_type FROM v\$encryption_wallet WHERE rownum = 1;")
    
    log_info "TDE Wallet Status: ${TDE_STATUS:-NOT CONFIGURED}"
    log_info "Wallet Type: ${WALLET_TYPE:-N/A}"
    
    # Wallet location from sqlnet.ora
    if [ -f "$ORACLE_HOME/network/admin/sqlnet.ora" ]; then
        WALLET_LOC=$(grep -i "ENCRYPTION_WALLET_LOCATION" "$ORACLE_HOME/network/admin/sqlnet.ora" 2>/dev/null | head -1)
        log_info "Wallet Location Config: ${WALLET_LOC:-NOT FOUND}"
    fi
    
    # Check for wallet directory
    for wallet_path in "$ORACLE_BASE/admin/$ORACLE_SID/wallet" "/etc/ORACLE/WALLETS/$ORACLE_SID" "$ORACLE_HOME/admin/$ORACLE_SID/wallet"; do
        if [ -d "$wallet_path" ]; then
            log_info "Wallet Directory Found: $wallet_path"
            TDE_WALLET_LOCATION="$wallet_path"
            break
        fi
    done
    
    # Encrypted tablespaces
    echo "" >> "$OUTPUT_TXT"
    echo "Encrypted Tablespaces:" >> "$OUTPUT_TXT"
    run_sql "SELECT tablespace_name, encrypted FROM dba_tablespaces WHERE encrypted = 'YES';" >> "$OUTPUT_TXT"
fi

# -------------------------------------------
# SUPPLEMENTAL LOGGING
# -------------------------------------------
log_section "Supplemental Logging"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    SUPP_LOG_MIN=$(run_sql_value "SELECT supplemental_log_data_min FROM v\$database;")
    SUPP_LOG_PK=$(run_sql_value "SELECT supplemental_log_data_pk FROM v\$database;")
    SUPP_LOG_UI=$(run_sql_value "SELECT supplemental_log_data_ui FROM v\$database;")
    SUPP_LOG_FK=$(run_sql_value "SELECT supplemental_log_data_fk FROM v\$database;")
    SUPP_LOG_ALL=$(run_sql_value "SELECT supplemental_log_data_all FROM v\$database;")
    
    log_info "Supplemental Log Data Min: $SUPP_LOG_MIN"
    log_info "Supplemental Log Data PK: $SUPP_LOG_PK"
    log_info "Supplemental Log Data UI: $SUPP_LOG_UI"
    log_info "Supplemental Log Data FK: $SUPP_LOG_FK"
    log_info "Supplemental Log Data ALL: $SUPP_LOG_ALL"
fi

# -------------------------------------------
# REDO/ARCHIVE CONFIGURATION
# -------------------------------------------
log_section "Redo and Archive Configuration"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    echo "" >> "$OUTPUT_TXT"
    echo "Redo Log Groups:" >> "$OUTPUT_TXT"
    run_sql "SELECT group#, thread#, sequence#, bytes/1024/1024 AS size_mb, members, status FROM v\$log ORDER BY group#;" >> "$OUTPUT_TXT"
    
    echo "" >> "$OUTPUT_TXT"
    echo "Redo Log Members:" >> "$OUTPUT_TXT"
    run_sql "SELECT group#, member, type FROM v\$logfile ORDER BY group#;" >> "$OUTPUT_TXT"
    
    echo "" >> "$OUTPUT_TXT"
    echo "Archive Log Destinations:" >> "$OUTPUT_TXT"
    run_sql "SELECT dest_id, status, destination, binding FROM v\$archive_dest WHERE status != 'INACTIVE';" >> "$OUTPUT_TXT"
fi

# -------------------------------------------
# NETWORK CONFIGURATION
# -------------------------------------------
log_section "Network Configuration"

# Listener status
echo "" >> "$OUTPUT_TXT"
echo "Listener Status:" >> "$OUTPUT_TXT"
if [ -n "${ORACLE_HOME:-}" ]; then
    if [ "$(whoami)" = "$ORACLE_USER" ]; then
        $ORACLE_HOME/bin/lsnrctl status >> "$OUTPUT_TXT" 2>&1 || log_warn "Could not get listener status"
    else
        sudo -u "$ORACLE_USER" ORACLE_HOME="$ORACLE_HOME" $ORACLE_HOME/bin/lsnrctl status >> "$OUTPUT_TXT" 2>&1 || log_warn "Could not get listener status"
    fi
fi

# tnsnames.ora
echo "" >> "$OUTPUT_TXT"
echo "tnsnames.ora:" >> "$OUTPUT_TXT"
if [ -f "$ORACLE_HOME/network/admin/tnsnames.ora" ]; then
    cat "$ORACLE_HOME/network/admin/tnsnames.ora" >> "$OUTPUT_TXT" 2>/dev/null
else
    echo "File not found" >> "$OUTPUT_TXT"
fi

# sqlnet.ora
echo "" >> "$OUTPUT_TXT"
echo "sqlnet.ora:" >> "$OUTPUT_TXT"
if [ -f "$ORACLE_HOME/network/admin/sqlnet.ora" ]; then
    cat "$ORACLE_HOME/network/admin/sqlnet.ora" >> "$OUTPUT_TXT" 2>/dev/null
else
    echo "File not found" >> "$OUTPUT_TXT"
fi

# -------------------------------------------
# AUTHENTICATION
# -------------------------------------------
log_section "Authentication"

# Password file
if [ -n "${ORACLE_HOME:-}" ]; then
    PWD_FILE=$(ls -la "$ORACLE_HOME/dbs/orapw"* 2>/dev/null | head -1)
    if [ -n "$PWD_FILE" ]; then
        log_info "Password File: $PWD_FILE"
    else
        log_warn "Password file not found in $ORACLE_HOME/dbs/"
    fi
fi

# SSH directory
echo "" >> "$OUTPUT_TXT"
echo "SSH Directory Contents (~/.ssh/):" >> "$OUTPUT_TXT"
ls -la ~/.ssh/ >> "$OUTPUT_TXT" 2>/dev/null || echo "SSH directory not found" >> "$OUTPUT_TXT"

# -------------------------------------------
# DATA GUARD CONFIGURATION
# -------------------------------------------
log_section "Data Guard Configuration"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    echo "" >> "$OUTPUT_TXT"
    echo "Data Guard Parameters:" >> "$OUTPUT_TXT"
    run_sql "SELECT name, value FROM v\$parameter WHERE name IN ('log_archive_config', 'log_archive_dest_1', 'log_archive_dest_2', 'log_archive_dest_state_1', 'log_archive_dest_state_2', 'fal_server', 'fal_client', 'db_file_name_convert', 'log_file_name_convert', 'standby_file_management') ORDER BY name;" >> "$OUTPUT_TXT"
fi

# -------------------------------------------
# SCHEMA INFORMATION
# -------------------------------------------
log_section "Schema Information"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    echo "" >> "$OUTPUT_TXT"
    echo "Schema Sizes (non-system schemas > 100MB):" >> "$OUTPUT_TXT"
    run_sql "SELECT owner, ROUND(SUM(bytes)/1024/1024, 2) AS size_mb 
             FROM dba_segments 
             WHERE owner NOT IN ('SYS','SYSTEM','DBSNMP','OUTLN','APPQOSSYS','DBSFWUSER','GGSYS','GSMADMIN_INTERNAL','GSMCATUSER','GSMUSER','OJVMSYS','OLAPSYS','ORDDATA','ORDPLUGINS','ORDSYS','SI_INFORMTN_SCHEMA','WMSYS','XDB','LBACSYS','DVSYS','DVF','CTXSYS','MDSYS','APEX_040200','APEX_PUBLIC_USER','FLOWS_FILES') 
             GROUP BY owner 
             HAVING SUM(bytes)/1024/1024 > 100 
             ORDER BY size_mb DESC;" >> "$OUTPUT_TXT"
    
    echo "" >> "$OUTPUT_TXT"
    echo "Invalid Objects by Owner/Type:" >> "$OUTPUT_TXT"
    run_sql "SELECT owner, object_type, COUNT(*) as invalid_count 
             FROM dba_objects 
             WHERE status = 'INVALID' 
             GROUP BY owner, object_type 
             ORDER BY owner, invalid_count DESC;" >> "$OUTPUT_TXT"
fi

# -------------------------------------------
# ADDITIONAL DISCOVERY (CUSTOM REQUIREMENTS)
# -------------------------------------------
log_section "Additional Discovery (Custom Requirements)"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    # Tablespace autoextend settings
    echo "" >> "$OUTPUT_TXT"
    echo "Tablespace Autoextend Settings:" >> "$OUTPUT_TXT"
    run_sql "SELECT tablespace_name, file_name, autoextensible, 
             ROUND(bytes/1024/1024, 2) AS current_size_mb,
             ROUND(maxbytes/1024/1024, 2) AS max_size_mb,
             ROUND(increment_by * (SELECT value FROM v\$parameter WHERE name = 'db_block_size') / 1024 / 1024, 2) AS increment_mb
             FROM dba_data_files
             ORDER BY tablespace_name, file_name;" >> "$OUTPUT_TXT"
    
    # Database Links
    echo "" >> "$OUTPUT_TXT"
    echo "Database Links:" >> "$OUTPUT_TXT"
    run_sql "SELECT owner, db_link, username, host, created FROM dba_db_links ORDER BY owner, db_link;" >> "$OUTPUT_TXT"
    
    # Materialized View Refresh Schedules
    echo "" >> "$OUTPUT_TXT"
    echo "Materialized View Refresh Schedules:" >> "$OUTPUT_TXT"
    run_sql "SELECT owner, mview_name, refresh_mode, refresh_method, 
             last_refresh_date, next_refresh_date
             FROM dba_mviews
             WHERE owner NOT IN ('SYS', 'SYSTEM')
             ORDER BY owner, mview_name;" >> "$OUTPUT_TXT"
    
    # Scheduler Jobs
    echo "" >> "$OUTPUT_TXT"
    echo "Scheduler Jobs:" >> "$OUTPUT_TXT"
    run_sql "SELECT owner, job_name, job_type, state, enabled, 
             last_start_date, next_run_date, repeat_interval
             FROM dba_scheduler_jobs
             WHERE owner NOT IN ('SYS', 'SYSTEM', 'ORACLE_OCM', 'EXFSYS')
             ORDER BY owner, job_name;" >> "$OUTPUT_TXT"
    
    # RMAN Backup Configuration
    echo "" >> "$OUTPUT_TXT"
    echo "RMAN Backup Configuration:" >> "$OUTPUT_TXT"
    run_sql "SELECT name, value FROM v\$rman_configuration ORDER BY name;" >> "$OUTPUT_TXT"
    
    # Recent Backups
    echo "" >> "$OUTPUT_TXT"
    echo "Recent Backups (last 7 days):" >> "$OUTPUT_TXT"
    run_sql "SELECT TO_CHAR(start_time, 'YYYY-MM-DD HH24:MI') AS start_time,
             TO_CHAR(end_time, 'YYYY-MM-DD HH24:MI') AS end_time,
             input_type, status, output_device_type,
             ROUND(input_bytes/1024/1024/1024, 2) AS input_gb,
             ROUND(output_bytes/1024/1024/1024, 2) AS output_gb
             FROM v\$rman_backup_job_details
             WHERE start_time > SYSDATE - 7
             ORDER BY start_time DESC;" >> "$OUTPUT_TXT"
fi

# -------------------------------------------
# GENERATE JSON OUTPUT
# -------------------------------------------
log_section "Generating JSON Output"

cat > "$OUTPUT_JSON" << EOJSON
{
  "discovery_type": "source",
  "project": "PRODDB Migration to Oracle Database@Azure",
  "timestamp": "$(date -Iseconds)",
  "hostname": "$HOSTNAME_FULL",
  "ip_addresses": "$IP_ADDRESSES",
  "os": {
    "version": "$OS_VERSION",
    "kernel": "$KERNEL_VERSION"
  },
  "oracle": {
    "version": "${ORACLE_VERSION:-UNKNOWN}",
    "oracle_home": "${ORACLE_HOME:-NOT SET}",
    "oracle_sid": "${ORACLE_SID:-NOT SET}",
    "oracle_base": "${ORACLE_BASE:-NOT SET}"
  },
  "database": {
    "name": "${DB_NAME:-UNKNOWN}",
    "unique_name": "${DB_UNIQUE_NAME:-UNKNOWN}",
    "dbid": "${DBID:-UNKNOWN}",
    "role": "${DB_ROLE:-UNKNOWN}",
    "open_mode": "${OPEN_MODE:-UNKNOWN}",
    "log_mode": "${LOG_MODE:-UNKNOWN}",
    "force_logging": "${FORCE_LOGGING:-UNKNOWN}",
    "platform": "${PLATFORM:-UNKNOWN}",
    "characterset": "${CHARACTERSET:-UNKNOWN}",
    "nchar_characterset": "${NCHAR_CHARACTERSET:-UNKNOWN}",
    "datafile_size_gb": "${DATAFILE_SIZE:-0}",
    "tempfile_size_gb": "${TEMPFILE_SIZE:-0}"
  },
  "cdb": {
    "is_cdb": "${CDB_STATUS:-NO}"
  },
  "tde": {
    "status": "${TDE_STATUS:-NOT CONFIGURED}",
    "wallet_type": "${WALLET_TYPE:-N/A}",
    "wallet_location": "${TDE_WALLET_LOCATION:-NOT FOUND}"
  },
  "supplemental_logging": {
    "min": "${SUPP_LOG_MIN:-NO}",
    "pk": "${SUPP_LOG_PK:-NO}",
    "ui": "${SUPP_LOG_UI:-NO}",
    "fk": "${SUPP_LOG_FK:-NO}",
    "all": "${SUPP_LOG_ALL:-NO}"
  },
  "migration_readiness": {
    "archivelog_enabled": $([ "$LOG_MODE" = "ARCHIVELOG" ] && echo "true" || echo "false"),
    "force_logging_enabled": $([ "$FORCE_LOGGING" = "YES" ] && echo "true" || echo "false"),
    "tde_enabled": $([ -n "$TDE_STATUS" ] && [ "$TDE_STATUS" != "NOT CONFIGURED" ] && echo "true" || echo "false"),
    "supplemental_logging_enabled": $([ "$SUPP_LOG_MIN" = "YES" ] && echo "true" || echo "false")
  }
}
EOJSON

log_info "JSON output saved to: $OUTPUT_JSON"

# -------------------------------------------
# SUMMARY
# -------------------------------------------
log_section "Discovery Summary"

echo ""
echo -e "${GREEN}Discovery completed successfully!${NC}"
echo ""
echo "Output files:"
echo "  - Text report: $OUTPUT_TXT"
echo "  - JSON summary: $OUTPUT_JSON"
echo ""
echo "Migration Readiness:"
echo "  - ARCHIVELOG Mode: $([ "$LOG_MODE" = "ARCHIVELOG" ] && echo -e "${GREEN}YES${NC}" || echo -e "${RED}NO${NC}")"
echo "  - Force Logging: $([ "$FORCE_LOGGING" = "YES" ] && echo -e "${GREEN}YES${NC}" || echo -e "${RED}NO${NC}")"
echo "  - TDE Enabled: $([ -n "$TDE_STATUS" ] && [ "$TDE_STATUS" != "NOT CONFIGURED" ] && echo -e "${GREEN}YES${NC}" || echo -e "${YELLOW}NO${NC}")"
echo "  - Supplemental Logging: $([ "$SUPP_LOG_MIN" = "YES" ] && echo -e "${GREEN}YES${NC}" || echo -e "${RED}NO${NC}")"
echo ""
