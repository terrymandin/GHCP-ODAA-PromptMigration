#!/bin/bash
################################################################################
# ZDM Target Database Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# Purpose: Discover target Oracle Database@Azure configuration for ZDM migration
#
# This script is executed via SSH as an admin user (opc) with sudo privileges.
# SQL commands are executed as the oracle user via sudo.
#
# Output:
#   - Text report: ./zdm_target_discovery_<hostname>_<timestamp>.txt
#   - JSON summary: ./zdm_target_discovery_<hostname>_<timestamp>.json
################################################################################

# Configuration
ORACLE_USER="${ORACLE_USER:-oracle}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname -s)
OUTPUT_FILE="./zdm_target_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_target_discovery_${HOSTNAME}_${TIMESTAMP}.json"

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
    
    # Method 3: Search common Oracle installation paths (ODA/Exadata specific)
    if [ -z "${ORACLE_HOME:-}" ]; then
        for path in /u02/app/oracle/product/*/dbhome_1 /u01/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1; do
            if [ -d "$path" ] && [ -f "$path/bin/sqlplus" ]; then
                export ORACLE_HOME="$path"
                break
            fi
        done
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

echo "ZDM Target Database Discovery Script" > "$OUTPUT_FILE"
echo "Generated: $(date)" >> "$OUTPUT_FILE"
echo "Hostname: $HOSTNAME" >> "$OUTPUT_FILE"
echo "Target Type: Oracle Database@Azure (Exadata)" >> "$OUTPUT_FILE"
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
    run_sql "SELECT NAME, DB_UNIQUE_NAME, DBID, DATABASE_ROLE, OPEN_MODE FROM V\$DATABASE;" >> "$OUTPUT_FILE"
    
    log_info "Database Version:"
    run_sql "SELECT VERSION_FULL FROM V\$INSTANCE;" >> "$OUTPUT_FILE" 2>/dev/null || \
    run_sql "SELECT VERSION FROM V\$INSTANCE;" >> "$OUTPUT_FILE"
    
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
# Storage and Tablespace Discovery
################################################################################

log_section "STORAGE AND TABLESPACES"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    
    log_info "Available Tablespace Storage:"
    run_sql "SELECT TABLESPACE_NAME, ROUND(SUM(BYTES)/1024/1024/1024, 2) AS SIZE_GB, ROUND(SUM(MAXBYTES)/1024/1024/1024, 2) AS MAX_SIZE_GB FROM DBA_DATA_FILES GROUP BY TABLESPACE_NAME ORDER BY TABLESPACE_NAME;" >> "$OUTPUT_FILE"
    
    log_info "ASM Disk Groups (if applicable):"
    run_sql "SELECT NAME, TOTAL_MB, FREE_MB, ROUND((FREE_MB/TOTAL_MB)*100, 2) AS FREE_PCT, STATE, TYPE FROM V\$ASM_DISKGROUP;" >> "$OUTPUT_FILE" 2>/dev/null
fi

################################################################################
# Additional Discovery: Exadata Storage Capacity
################################################################################

log_section "EXADATA STORAGE CAPACITY"

log_info "Checking Exadata storage capacity..."

# Check ASM disk group details for Exadata
if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    run_sql "SELECT DG.NAME AS DISKGROUP_NAME, DG.TOTAL_MB/1024 AS TOTAL_GB, DG.FREE_MB/1024 AS FREE_GB, DG.USABLE_FILE_MB/1024 AS USABLE_GB, DG.STATE, DG.TYPE FROM V\$ASM_DISKGROUP DG;" >> "$OUTPUT_FILE" 2>/dev/null
fi

# Disk space from OS level
log_info "Disk Space (OS level):"
df -h >> "$OUTPUT_FILE"

################################################################################
# Additional Discovery: Pre-configured PDBs
################################################################################

log_section "PRE-CONFIGURED PDBs"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    log_info "Existing PDBs with size and status:"
    run_sql "SELECT p.CON_ID, p.NAME, p.OPEN_MODE, p.RESTRICTED, ROUND(SUM(d.BYTES)/1024/1024/1024, 2) AS SIZE_GB FROM V\$PDBS p LEFT JOIN CDB_DATA_FILES d ON p.CON_ID = d.CON_ID GROUP BY p.CON_ID, p.NAME, p.OPEN_MODE, p.RESTRICTED ORDER BY p.CON_ID;" >> "$OUTPUT_FILE" 2>/dev/null
    
    log_info "PDB Services:"
    run_sql "SELECT CON_ID, NAME, PDB FROM V\$SERVICES WHERE PDB IS NOT NULL ORDER BY CON_ID;" >> "$OUTPUT_FILE" 2>/dev/null
fi

################################################################################
# TDE/Wallet Configuration Discovery
################################################################################

log_section "TDE WALLET CONFIGURATION"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    
    log_info "TDE Wallet Status:"
    run_sql "SELECT WRL_TYPE, WRL_PARAMETER, STATUS, WALLET_TYPE FROM V\$ENCRYPTION_WALLET;" >> "$OUTPUT_FILE"
    
    log_info "Encrypted Tablespaces:"
    run_sql "SELECT TABLESPACE_NAME, ENCRYPTED FROM DBA_TABLESPACES WHERE ENCRYPTED = 'YES';" >> "$OUTPUT_FILE"
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

log_info "SCAN Listener (if RAC):"
if [ -n "${ORACLE_HOME:-}" ]; then
    if [ "$(whoami)" = "$ORACLE_USER" ]; then
        ORACLE_HOME="$ORACLE_HOME" "$ORACLE_HOME/bin/srvctl" status scan_listener >> "$OUTPUT_FILE" 2>&1
    else
        sudo -u "$ORACLE_USER" ORACLE_HOME="$ORACLE_HOME" "$ORACLE_HOME/bin/srvctl" status scan_listener >> "$OUTPUT_FILE" 2>&1
    fi
fi

log_info "tnsnames.ora:"
TNS_ADMIN="${TNS_ADMIN:-$ORACLE_HOME/network/admin}"
if [ -f "$TNS_ADMIN/tnsnames.ora" ]; then
    cat "$TNS_ADMIN/tnsnames.ora" >> "$OUTPUT_FILE"
else
    echo "File not found: $TNS_ADMIN/tnsnames.ora" >> "$OUTPUT_FILE"
fi

################################################################################
# Additional Discovery: Network Security Group Rules
################################################################################

log_section "NETWORK SECURITY GROUP RULES"

log_info "Checking firewall/iptables rules (if accessible):"
iptables -L -n 2>/dev/null >> "$OUTPUT_FILE" || echo "Unable to read iptables rules (may require root)" >> "$OUTPUT_FILE"

log_info "Firewalld status (if applicable):"
systemctl status firewalld 2>/dev/null | head -10 >> "$OUTPUT_FILE" || echo "firewalld not available" >> "$OUTPUT_FILE"

log_info "Open listening ports:"
ss -tlnp 2>/dev/null >> "$OUTPUT_FILE" || netstat -tlnp 2>/dev/null >> "$OUTPUT_FILE"

################################################################################
# OCI/Azure Integration Discovery
################################################################################

log_section "OCI/AZURE INTEGRATION"

log_info "OCI CLI Version:"
oci --version >> "$OUTPUT_FILE" 2>&1 || echo "OCI CLI not installed or not in PATH" >> "$OUTPUT_FILE"

log_info "OCI CLI Configuration:"
if [ -f ~/.oci/config ]; then
    echo "OCI config file exists at ~/.oci/config" >> "$OUTPUT_FILE"
    # Show config but mask sensitive data
    grep -E '^\[|^user=|^fingerprint=|^tenancy=|^region=' ~/.oci/config 2>/dev/null >> "$OUTPUT_FILE"
else
    echo "OCI config file not found at ~/.oci/config" >> "$OUTPUT_FILE"
fi

log_info "OCI Connectivity Test:"
oci iam region list --output table 2>&1 | head -20 >> "$OUTPUT_FILE" || echo "OCI connectivity test failed or OCI CLI not configured" >> "$OUTPUT_FILE"

log_info "OCI Instance Metadata:"
curl -s -H "Authorization: Bearer Oracle" http://169.254.169.254/opc/v2/instance/ 2>/dev/null | head -50 >> "$OUTPUT_FILE" || echo "Unable to retrieve OCI instance metadata" >> "$OUTPUT_FILE"

log_info "Azure Instance Metadata:"
curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" 2>/dev/null | head -50 >> "$OUTPUT_FILE" || echo "Unable to retrieve Azure instance metadata" >> "$OUTPUT_FILE"

################################################################################
# Grid Infrastructure Discovery (if RAC)
################################################################################

log_section "GRID INFRASTRUCTURE"

log_info "CRS Status:"
if command -v crsctl >/dev/null 2>&1; then
    crsctl stat res -t >> "$OUTPUT_FILE" 2>&1
else
    # Try to find crsctl in common GI locations
    for gi_path in /u01/app/*/grid/bin /u01/app/grid/bin; do
        if [ -f "$gi_path/crsctl" ]; then
            sudo "$gi_path/crsctl" stat res -t >> "$OUTPUT_FILE" 2>&1
            break
        fi
    done
    if [ $? -ne 0 ]; then
        echo "crsctl not found - may not be RAC or Grid Infrastructure not installed" >> "$OUTPUT_FILE"
    fi
fi

################################################################################
# Authentication Discovery
################################################################################

log_section "AUTHENTICATION"

log_info "SSH Directory Contents (opc user):"
if [ -d ~/.ssh ]; then
    ls -la ~/.ssh/ 2>/dev/null >> "$OUTPUT_FILE"
else
    echo "SSH directory not found for current user" >> "$OUTPUT_FILE"
fi

log_info "SSH Directory Contents (oracle user):"
ORACLE_HOME_DIR=$(eval echo ~$ORACLE_USER 2>/dev/null)
if [ -d "$ORACLE_HOME_DIR/.ssh" ]; then
    sudo ls -la "$ORACLE_HOME_DIR/.ssh/" 2>/dev/null >> "$OUTPUT_FILE"
else
    echo "SSH directory not found for $ORACLE_USER user" >> "$OUTPUT_FILE"
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
CDB_STATUS=$(run_sql_value "SELECT CDB FROM V\$DATABASE;")
TDE_STATUS=$(run_sql_value "SELECT STATUS FROM V\$ENCRYPTION_WALLET WHERE ROWNUM = 1;")
WALLET_TYPE=$(run_sql_value "SELECT WALLET_TYPE FROM V\$ENCRYPTION_WALLET WHERE ROWNUM = 1;")
CHARACTER_SET=$(run_sql_value "SELECT VALUE FROM NLS_DATABASE_PARAMETERS WHERE PARAMETER = 'NLS_CHARACTERSET';")

# Check OCI CLI availability
OCI_VERSION=$(oci --version 2>/dev/null || echo "NOT_INSTALLED")

cat > "$JSON_FILE" <<EOF
{
  "discovery_type": "target",
  "discovery_timestamp": "$(date -Iseconds)",
  "hostname": "$HOSTNAME",
  "target_type": "Oracle Database@Azure",
  "oracle_home": "${ORACLE_HOME:-NOT_DETECTED}",
  "oracle_sid": "${ORACLE_SID:-NOT_DETECTED}",
  "database": {
    "name": "${DB_NAME:-UNKNOWN}",
    "unique_name": "${DB_UNIQUE_NAME:-UNKNOWN}",
    "dbid": "${DBID:-UNKNOWN}",
    "role": "${DB_ROLE:-UNKNOWN}",
    "open_mode": "${OPEN_MODE:-UNKNOWN}",
    "character_set": "${CHARACTER_SET:-UNKNOWN}"
  },
  "container_database": {
    "is_cdb": "${CDB_STATUS:-NO}"
  },
  "tde": {
    "status": "${TDE_STATUS:-UNKNOWN}",
    "wallet_type": "${WALLET_TYPE:-UNKNOWN}"
  },
  "oci_integration": {
    "oci_cli_version": "${OCI_VERSION}"
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
echo -e "${GREEN}Target database discovery complete!${NC}"
echo "Output files created in current directory:"
echo "  - $OUTPUT_FILE"
echo "  - $JSON_FILE"
