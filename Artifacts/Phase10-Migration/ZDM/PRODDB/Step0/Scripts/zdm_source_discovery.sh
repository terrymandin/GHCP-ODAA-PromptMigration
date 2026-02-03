#!/bin/bash
################################################################################
# ZDM Source Database Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# Purpose: Discover source database configuration for ZDM migration
#
# This script is executed via SSH as an admin user with sudo privileges.
# SQL commands are executed as the oracle user via sudo.
#
# Output:
#   - Text report: ./zdm_source_discovery_<hostname>_<timestamp>.txt
#   - JSON summary: ./zdm_source_discovery_<hostname>_<timestamp>.json
################################################################################

# Configuration
ORACLE_USER="${ORACLE_USER:-oracle}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname -s)
OUTPUT_FILE="./zdm_source_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_source_discovery_${HOSTNAME}_${TIMESTAMP}.json"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Utility Functions
################################################################################

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
    echo "[INFO] $1" >> "$OUTPUT_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    echo "[WARN] $1" >> "$OUTPUT_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[ERROR] $1" >> "$OUTPUT_FILE"
}

log_section() {
    echo ""
    echo -e "${BLUE}=== $1 ===${NC}"
    echo "" >> "$OUTPUT_FILE"
    echo "=== $1 ===" >> "$OUTPUT_FILE"
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

# Run SQL command as oracle user
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
    run_sql "$sql_query" | grep -v '^$' | tail -1 | xargs
}

################################################################################
# Initialize
################################################################################

echo "ZDM Source Database Discovery Script" > "$OUTPUT_FILE"
echo "Generated: $(date)" >> "$OUTPUT_FILE"
echo "Hostname: $HOSTNAME" >> "$OUTPUT_FILE"
echo "========================================" >> "$OUTPUT_FILE"

# Detect Oracle environment
detect_oracle_env
apply_overrides

################################################################################
# OS Information Discovery
################################################################################

log_section "OS INFORMATION"

log_info "Hostname: $(hostname -f 2>/dev/null || hostname)"
echo "Hostname: $(hostname -f 2>/dev/null || hostname)" >> "$OUTPUT_FILE"

log_info "IP Addresses:"
ip addr show 2>/dev/null | grep 'inet ' | awk '{print $2}' >> "$OUTPUT_FILE" || \
    ifconfig 2>/dev/null | grep 'inet ' >> "$OUTPUT_FILE"

log_info "Operating System:"
if [ -f /etc/os-release ]; then
    cat /etc/os-release >> "$OUTPUT_FILE"
elif [ -f /etc/redhat-release ]; then
    cat /etc/redhat-release >> "$OUTPUT_FILE"
fi
uname -a >> "$OUTPUT_FILE"

log_info "Disk Space:"
df -h >> "$OUTPUT_FILE"

################################################################################
# Oracle Environment Discovery
################################################################################

log_section "ORACLE ENVIRONMENT"

if [ -z "${ORACLE_HOME:-}" ]; then
    log_error "ORACLE_HOME not detected"
else
    log_info "ORACLE_HOME: $ORACLE_HOME"
    echo "ORACLE_HOME: $ORACLE_HOME" >> "$OUTPUT_FILE"
fi

if [ -z "${ORACLE_SID:-}" ]; then
    log_error "ORACLE_SID not detected"
else
    log_info "ORACLE_SID: $ORACLE_SID"
    echo "ORACLE_SID: $ORACLE_SID" >> "$OUTPUT_FILE"
fi

ORACLE_BASE="${ORACLE_BASE:-$(dirname "$(dirname "$ORACLE_HOME")" 2>/dev/null)}"
log_info "ORACLE_BASE: $ORACLE_BASE"
echo "ORACLE_BASE: $ORACLE_BASE" >> "$OUTPUT_FILE"

# Oracle Version
log_info "Oracle Version:"
if [ -n "${ORACLE_HOME:-}" ] && [ -f "$ORACLE_HOME/bin/sqlplus" ]; then
    if [ "$(whoami)" = "$ORACLE_USER" ]; then
        ORACLE_HOME="$ORACLE_HOME" "$ORACLE_HOME/bin/sqlplus" -v 2>/dev/null >> "$OUTPUT_FILE"
    else
        sudo -u "$ORACLE_USER" ORACLE_HOME="$ORACLE_HOME" "$ORACLE_HOME/bin/sqlplus" -v 2>/dev/null >> "$OUTPUT_FILE"
    fi
fi

# /etc/oratab contents
log_info "/etc/oratab contents:"
if [ -f /etc/oratab ]; then
    cat /etc/oratab >> "$OUTPUT_FILE"
else
    echo "File not found: /etc/oratab" >> "$OUTPUT_FILE"
fi

################################################################################
# Database Configuration Discovery
################################################################################

log_section "DATABASE CONFIGURATION"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    
    log_info "Database Name and Configuration:"
    run_sql "SELECT NAME, DB_UNIQUE_NAME, DBID, DATABASE_ROLE, OPEN_MODE, LOG_MODE, FORCE_LOGGING FROM V\$DATABASE;" >> "$OUTPUT_FILE"
    
    log_info "Database Version:"
    run_sql "SELECT VERSION_FULL FROM V\$INSTANCE;" >> "$OUTPUT_FILE" 2>/dev/null || \
    run_sql "SELECT VERSION FROM V\$INSTANCE;" >> "$OUTPUT_FILE"
    
    log_info "Database Size (Data Files):"
    run_sql "SELECT ROUND(SUM(BYTES)/1024/1024/1024, 2) AS SIZE_GB FROM DBA_DATA_FILES;" >> "$OUTPUT_FILE"
    
    log_info "Database Size (Temp Files):"
    run_sql "SELECT ROUND(SUM(BYTES)/1024/1024/1024, 2) AS SIZE_GB FROM DBA_TEMP_FILES;" >> "$OUTPUT_FILE"
    
    log_info "Character Set:"
    run_sql "SELECT PARAMETER, VALUE FROM NLS_DATABASE_PARAMETERS WHERE PARAMETER IN ('NLS_CHARACTERSET', 'NLS_NCHAR_CHARACTERSET');" >> "$OUTPUT_FILE"
    
else
    log_error "Cannot discover database configuration - ORACLE_HOME or ORACLE_SID not set"
fi

################################################################################
# Container Database Discovery
################################################################################

log_section "CONTAINER DATABASE"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    
    CDB_STATUS=$(run_sql_value "SELECT CDB FROM V\$DATABASE;")
    log_info "CDB Status: $CDB_STATUS"
    echo "CDB Status: $CDB_STATUS" >> "$OUTPUT_FILE"
    
    if [ "$CDB_STATUS" = "YES" ]; then
        log_info "PDB Names and Status:"
        run_sql "SELECT CON_ID, NAME, OPEN_MODE, RESTRICTED FROM V\$PDBS ORDER BY CON_ID;" >> "$OUTPUT_FILE"
    fi
fi

################################################################################
# TDE Configuration Discovery
################################################################################

log_section "TDE CONFIGURATION"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    
    log_info "TDE Status:"
    run_sql "SELECT WRL_TYPE, WRL_PARAMETER, STATUS, WALLET_TYPE FROM V\$ENCRYPTION_WALLET;" >> "$OUTPUT_FILE"
    
    log_info "Encrypted Tablespaces:"
    run_sql "SELECT TABLESPACE_NAME, ENCRYPTED FROM DBA_TABLESPACES WHERE ENCRYPTED = 'YES';" >> "$OUTPUT_FILE"
    
    log_info "Encryption Keys:"
    run_sql "SELECT KEY_ID, CREATION_TIME, ACTIVATION_TIME, KEY_USE FROM V\$ENCRYPTION_KEYS;" >> "$OUTPUT_FILE" 2>/dev/null
fi

################################################################################
# Supplemental Logging Discovery
################################################################################

log_section "SUPPLEMENTAL LOGGING"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    
    log_info "Supplemental Log Settings:"
    run_sql "SELECT SUPPLEMENTAL_LOG_DATA_MIN, SUPPLEMENTAL_LOG_DATA_PK, SUPPLEMENTAL_LOG_DATA_UI, SUPPLEMENTAL_LOG_DATA_FK, SUPPLEMENTAL_LOG_DATA_ALL FROM V\$DATABASE;" >> "$OUTPUT_FILE"
fi

################################################################################
# Redo/Archive Configuration Discovery
################################################################################

log_section "REDO AND ARCHIVE CONFIGURATION"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    
    log_info "Redo Log Groups:"
    run_sql "SELECT GROUP#, THREAD#, SEQUENCE#, BYTES/1024/1024 AS SIZE_MB, MEMBERS, STATUS FROM V\$LOG ORDER BY GROUP#;" >> "$OUTPUT_FILE"
    
    log_info "Redo Log Members:"
    run_sql "SELECT GROUP#, TYPE, MEMBER FROM V\$LOGFILE ORDER BY GROUP#;" >> "$OUTPUT_FILE"
    
    log_info "Archive Log Mode:"
    run_sql "SELECT LOG_MODE FROM V\$DATABASE;" >> "$OUTPUT_FILE"
    
    log_info "Archive Log Destinations:"
    run_sql "SELECT DEST_ID, DEST_NAME, STATUS, DESTINATION FROM V\$ARCHIVE_DEST WHERE STATUS = 'VALID';" >> "$OUTPUT_FILE"
fi

################################################################################
# Network Configuration Discovery
################################################################################

log_section "NETWORK CONFIGURATION"

log_info "Listener Status:"
if [ -n "${ORACLE_HOME:-}" ]; then
    if [ "$(whoami)" = "$ORACLE_USER" ]; then
        ORACLE_HOME="$ORACLE_HOME" "$ORACLE_HOME/bin/lsnrctl" status >> "$OUTPUT_FILE" 2>&1
    else
        sudo -u "$ORACLE_USER" ORACLE_HOME="$ORACLE_HOME" "$ORACLE_HOME/bin/lsnrctl" status >> "$OUTPUT_FILE" 2>&1
    fi
fi

log_info "tnsnames.ora:"
TNS_ADMIN="${TNS_ADMIN:-$ORACLE_HOME/network/admin}"
if [ -f "$TNS_ADMIN/tnsnames.ora" ]; then
    cat "$TNS_ADMIN/tnsnames.ora" >> "$OUTPUT_FILE"
else
    echo "File not found: $TNS_ADMIN/tnsnames.ora" >> "$OUTPUT_FILE"
fi

log_info "sqlnet.ora:"
if [ -f "$TNS_ADMIN/sqlnet.ora" ]; then
    cat "$TNS_ADMIN/sqlnet.ora" >> "$OUTPUT_FILE"
else
    echo "File not found: $TNS_ADMIN/sqlnet.ora" >> "$OUTPUT_FILE"
fi

################################################################################
# Authentication Discovery
################################################################################

log_section "AUTHENTICATION"

log_info "Password File Location:"
if [ -n "${ORACLE_HOME:-}" ]; then
    ls -la "$ORACLE_HOME/dbs/orapw"* 2>/dev/null >> "$OUTPUT_FILE" || echo "No password files found in $ORACLE_HOME/dbs/" >> "$OUTPUT_FILE"
fi

log_info "SSH Directory Contents (oracle user):"
ORACLE_HOME_DIR=$(eval echo ~$ORACLE_USER 2>/dev/null)
if [ -d "$ORACLE_HOME_DIR/.ssh" ]; then
    ls -la "$ORACLE_HOME_DIR/.ssh/" 2>/dev/null >> "$OUTPUT_FILE" || \
        sudo ls -la "$ORACLE_HOME_DIR/.ssh/" 2>/dev/null >> "$OUTPUT_FILE"
else
    echo "SSH directory not found for $ORACLE_USER user" >> "$OUTPUT_FILE"
fi

################################################################################
# Data Guard Configuration Discovery
################################################################################

log_section "DATA GUARD CONFIGURATION"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    
    log_info "Data Guard Parameters:"
    run_sql "SELECT NAME, VALUE FROM V\$PARAMETER WHERE NAME IN ('log_archive_config', 'log_archive_dest_1', 'log_archive_dest_2', 'log_archive_dest_state_1', 'log_archive_dest_state_2', 'fal_server', 'fal_client', 'db_file_name_convert', 'log_file_name_convert', 'standby_file_management');" >> "$OUTPUT_FILE"
fi

################################################################################
# Schema Information Discovery
################################################################################

log_section "SCHEMA INFORMATION"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    
    log_info "Schema Sizes (non-system schemas > 100MB):"
    run_sql "SELECT OWNER, ROUND(SUM(BYTES)/1024/1024, 2) AS SIZE_MB FROM DBA_SEGMENTS WHERE OWNER NOT IN ('SYS', 'SYSTEM', 'DBSNMP', 'OUTLN', 'APPQOSSYS', 'DBSFWUSER', 'GGSYS', 'GSMADMIN_INTERNAL', 'XDB', 'WMSYS', 'ORDSYS', 'ORDDATA', 'MDSYS', 'LBACSYS', 'DVSYS', 'CTXSYS', 'AUDSYS', 'OJVMSYS', 'OLAPSYS') GROUP BY OWNER HAVING SUM(BYTES)/1024/1024 > 100 ORDER BY SIZE_MB DESC;" >> "$OUTPUT_FILE"
    
    log_info "Invalid Objects Count by Owner/Type:"
    run_sql "SELECT OWNER, OBJECT_TYPE, COUNT(*) AS INVALID_COUNT FROM DBA_OBJECTS WHERE STATUS = 'INVALID' GROUP BY OWNER, OBJECT_TYPE ORDER BY OWNER, OBJECT_TYPE;" >> "$OUTPUT_FILE"
fi

################################################################################
# Additional Discovery Requirements (Custom for PRODDB)
################################################################################

log_section "TABLESPACE AUTOEXTEND SETTINGS"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    log_info "Tablespace Autoextend Settings:"
    run_sql "SELECT TABLESPACE_NAME, FILE_NAME, BYTES/1024/1024 AS SIZE_MB, MAXBYTES/1024/1024 AS MAX_SIZE_MB, AUTOEXTENSIBLE, INCREMENT_BY FROM DBA_DATA_FILES ORDER BY TABLESPACE_NAME;" >> "$OUTPUT_FILE"
fi

log_section "BACKUP SCHEDULE AND RETENTION"

log_info "RMAN Configuration:"
if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    if [ "$(whoami)" = "$ORACLE_USER" ]; then
        echo "SHOW ALL;" | ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" "$ORACLE_HOME/bin/rman" target / 2>/dev/null >> "$OUTPUT_FILE"
    else
        echo "SHOW ALL;" | sudo -u "$ORACLE_USER" ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" "$ORACLE_HOME/bin/rman" target / 2>/dev/null >> "$OUTPUT_FILE"
    fi
fi

log_info "Recent Backup History:"
run_sql "SELECT INPUT_TYPE, STATUS, START_TIME, END_TIME, ELAPSED_SECONDS FROM V\$RMAN_BACKUP_JOB_DETAILS WHERE START_TIME > SYSDATE - 30 ORDER BY START_TIME DESC;" >> "$OUTPUT_FILE" 2>/dev/null

log_section "DATABASE LINKS"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    log_info "Database Links Configured:"
    run_sql "SELECT OWNER, DB_LINK, USERNAME, HOST FROM DBA_DB_LINKS ORDER BY OWNER, DB_LINK;" >> "$OUTPUT_FILE"
fi

log_section "MATERIALIZED VIEW REFRESH SCHEDULES"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    log_info "Materialized Views and Refresh Settings:"
    run_sql "SELECT OWNER, MVIEW_NAME, REFRESH_MODE, REFRESH_METHOD, LAST_REFRESH_DATE, NEXT_DATE FROM DBA_MVIEWS m LEFT JOIN DBA_REFRESH_CHILDREN r ON m.OWNER = r.OWNER AND m.MVIEW_NAME = r.NAME ORDER BY OWNER, MVIEW_NAME;" >> "$OUTPUT_FILE" 2>/dev/null || \
    run_sql "SELECT OWNER, MVIEW_NAME, REFRESH_MODE, REFRESH_METHOD, LAST_REFRESH_DATE FROM DBA_MVIEWS ORDER BY OWNER, MVIEW_NAME;" >> "$OUTPUT_FILE"
fi

log_section "SCHEDULER JOBS"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    log_info "Scheduler Jobs that may need reconfiguration:"
    run_sql "SELECT OWNER, JOB_NAME, JOB_TYPE, STATE, ENABLED, LAST_START_DATE, NEXT_RUN_DATE, REPEAT_INTERVAL FROM DBA_SCHEDULER_JOBS WHERE OWNER NOT IN ('SYS', 'SYSTEM', 'ORACLE_OCM', 'EXFSYS') ORDER BY OWNER, JOB_NAME;" >> "$OUTPUT_FILE"
fi

################################################################################
# Generate JSON Summary
################################################################################

log_section "GENERATING JSON SUMMARY"

# Collect key values for JSON
DB_NAME=$(run_sql_value "SELECT NAME FROM V\$DATABASE;")
DB_UNIQUE_NAME=$(run_sql_value "SELECT DB_UNIQUE_NAME FROM V\$DATABASE;")
DBID=$(run_sql_value "SELECT DBID FROM V\$DATABASE;")
DB_ROLE=$(run_sql_value "SELECT DATABASE_ROLE FROM V\$DATABASE;")
OPEN_MODE=$(run_sql_value "SELECT OPEN_MODE FROM V\$DATABASE;")
LOG_MODE=$(run_sql_value "SELECT LOG_MODE FROM V\$DATABASE;")
FORCE_LOGGING=$(run_sql_value "SELECT FORCE_LOGGING FROM V\$DATABASE;")
CDB_STATUS=$(run_sql_value "SELECT CDB FROM V\$DATABASE;")
DB_SIZE_GB=$(run_sql_value "SELECT ROUND(SUM(BYTES)/1024/1024/1024, 2) FROM DBA_DATA_FILES;")
TDE_STATUS=$(run_sql_value "SELECT STATUS FROM V\$ENCRYPTION_WALLET WHERE ROWNUM = 1;")
WALLET_TYPE=$(run_sql_value "SELECT WALLET_TYPE FROM V\$ENCRYPTION_WALLET WHERE ROWNUM = 1;")
CHARACTER_SET=$(run_sql_value "SELECT VALUE FROM NLS_DATABASE_PARAMETERS WHERE PARAMETER = 'NLS_CHARACTERSET';")
SUPP_LOG_MIN=$(run_sql_value "SELECT SUPPLEMENTAL_LOG_DATA_MIN FROM V\$DATABASE;")

cat > "$JSON_FILE" <<EOF
{
  "discovery_type": "source",
  "discovery_timestamp": "$(date -Iseconds)",
  "hostname": "$HOSTNAME",
  "oracle_home": "${ORACLE_HOME:-NOT_DETECTED}",
  "oracle_sid": "${ORACLE_SID:-NOT_DETECTED}",
  "database": {
    "name": "${DB_NAME:-UNKNOWN}",
    "unique_name": "${DB_UNIQUE_NAME:-UNKNOWN}",
    "dbid": "${DBID:-UNKNOWN}",
    "role": "${DB_ROLE:-UNKNOWN}",
    "open_mode": "${OPEN_MODE:-UNKNOWN}",
    "log_mode": "${LOG_MODE:-UNKNOWN}",
    "force_logging": "${FORCE_LOGGING:-UNKNOWN}",
    "size_gb": "${DB_SIZE_GB:-0}",
    "character_set": "${CHARACTER_SET:-UNKNOWN}"
  },
  "container_database": {
    "is_cdb": "${CDB_STATUS:-NO}"
  },
  "tde": {
    "status": "${TDE_STATUS:-UNKNOWN}",
    "wallet_type": "${WALLET_TYPE:-UNKNOWN}"
  },
  "supplemental_logging": {
    "min_enabled": "${SUPP_LOG_MIN:-UNKNOWN}"
  },
  "output_files": {
    "text_report": "$OUTPUT_FILE",
    "json_summary": "$JSON_FILE"
  }
}
EOF

log_info "JSON summary written to: $JSON_FILE"

################################################################################
# Summary
################################################################################

log_section "DISCOVERY COMPLETE"

log_info "Text report: $OUTPUT_FILE"
log_info "JSON summary: $JSON_FILE"

echo ""
echo -e "${GREEN}Source database discovery complete!${NC}"
echo "Output files created in current directory:"
echo "  - $OUTPUT_FILE"
echo "  - $JSON_FILE"
