#!/bin/bash
################################################################################
# ZDM Target Database Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# 
# Purpose: Discover target Oracle Database@Azure configuration for ZDM migration
# 
# Usage: Run on target database server as admin user (opc)
#        This script will execute SQL commands as the oracle user
#
# Output: 
#   - Text report: ./zdm_target_discovery_<hostname>_<timestamp>.txt
#   - JSON summary: ./zdm_target_discovery_<hostname>_<timestamp>.json
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
TEXT_OUTPUT="./zdm_target_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
JSON_OUTPUT="./zdm_target_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

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
    
    # Method 3: Search common Oracle Database@Azure installation paths
    if [ -z "${ORACLE_HOME:-}" ]; then
        for path in /u02/app/oracle/product/*/dbhome_1 /u01/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1; do
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
echo "ZDM Target Database Discovery Report (Oracle Database@Azure)" > "$TEXT_OUTPUT"
echo "Generated: $(date)" >> "$TEXT_OUTPUT"
echo "Hostname: $(hostname)" >> "$TEXT_OUTPUT"
echo "" >> "$TEXT_OUTPUT"

# Detect and apply Oracle environment
detect_oracle_env
apply_overrides

# Initialize JSON output
cat > "$JSON_OUTPUT" << 'EOJSON'
{
  "discovery_type": "target_database",
  "platform": "Oracle Database@Azure",
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
    run_sql "SELECT name, db_unique_name, database_role, open_mode FROM v\$database;" | tee -a "$TEXT_OUTPUT"
    
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
# ADDITIONAL DISCOVERY: Pre-configured PDBs
################################################################################

log_section "PRE-CONFIGURED PDBs"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    log_info "PDB Storage and Configuration Details:"
    run_sql "SELECT p.con_id, p.name AS pdb_name, p.open_mode, ROUND(SUM(d.bytes)/1024/1024/1024, 2) AS used_gb FROM v\$pdbs p LEFT JOIN cdb_data_files d ON p.con_id = d.con_id GROUP BY p.con_id, p.name, p.open_mode ORDER BY p.con_id;" | tee -a "$TEXT_OUTPUT"
    
    log_info "PDB Services:"
    run_sql "SELECT con_id, name, pdb FROM v\$services WHERE pdb IS NOT NULL ORDER BY con_id;" | tee -a "$TEXT_OUTPUT"
else
    log_warn "Cannot query PDB details - Oracle environment not configured"
fi

################################################################################
# Available Storage
################################################################################

log_section "AVAILABLE STORAGE"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    log_info "Tablespace Storage Summary:"
    run_sql "SELECT tablespace_name, ROUND(SUM(bytes)/1024/1024/1024, 2) AS used_gb, ROUND(SUM(maxbytes)/1024/1024/1024, 2) AS max_gb, ROUND((SUM(maxbytes) - SUM(bytes))/1024/1024/1024, 2) AS free_gb FROM dba_data_files GROUP BY tablespace_name ORDER BY tablespace_name;" | tee -a "$TEXT_OUTPUT"
    
    log_info "ASM Disk Groups (if applicable):"
    run_sql "SELECT name, state, type, ROUND(total_mb/1024, 2) AS total_gb, ROUND(free_mb/1024, 2) AS free_gb, ROUND((free_mb/total_mb)*100, 2) AS pct_free FROM v\$asm_diskgroup ORDER BY name;" | tee -a "$TEXT_OUTPUT" || log_info "ASM not configured or not accessible"
else
    log_warn "Cannot query storage - Oracle environment not configured"
fi

################################################################################
# ADDITIONAL DISCOVERY: Exadata Storage Capacity
################################################################################

log_section "EXADATA STORAGE CAPACITY"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    log_info "Exadata Cell Disk Information:"
    run_sql "SELECT cell_path, disk_name, ROUND(total_size/1024/1024/1024, 2) AS total_gb, ROUND(free_size/1024/1024/1024, 2) AS free_gb FROM v\$cell_disk_summary ORDER BY cell_path, disk_name;" | tee -a "$TEXT_OUTPUT" 2>/dev/null || log_info "Exadata cell disk views not available"
    
    log_info "ASM Diskgroup Details (Exadata):"
    run_sql "SELECT dg.name AS diskgroup_name, dg.type, dg.state, ROUND(dg.total_mb/1024, 2) AS total_gb, ROUND(dg.free_mb/1024, 2) AS free_gb, ROUND(dg.usable_file_mb/1024, 2) AS usable_gb, dg.offline_disks FROM v\$asm_diskgroup dg ORDER BY dg.name;" | tee -a "$TEXT_OUTPUT"
    
    log_info "Storage Server (Cell) Status:"
    # This may require specific Exadata views
    run_sql "SELECT * FROM v\$cell_state WHERE statistics_type = 'CELL';" | tee -a "$TEXT_OUTPUT" 2>/dev/null || log_info "Cell state views not available"
else
    log_warn "Cannot query Exadata storage - Oracle environment not configured"
fi

################################################################################
# TDE Configuration
################################################################################

log_section "TDE CONFIGURATION"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    log_info "Encryption Wallet Status:"
    run_sql "SELECT wrl_type, wrl_parameter, status, wallet_type FROM v\$encryption_wallet;" | tee -a "$TEXT_OUTPUT"
else
    log_warn "Cannot query TDE status - Oracle environment not configured"
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
    
    log_info "SCAN Listener (if RAC):"
    if [ "$(whoami)" = "$ORACLE_USER" ]; then
        "$ORACLE_HOME/bin/srvctl" status scan_listener 2>&1 | tee -a "$TEXT_OUTPUT" || log_info "SCAN listener not configured or not a RAC environment"
    else
        sudo -u "$ORACLE_USER" "$ORACLE_HOME/bin/srvctl" status scan_listener 2>&1 | tee -a "$TEXT_OUTPUT" || log_info "SCAN listener not configured or not a RAC environment"
    fi
    
    log_info "tnsnames.ora:"
    if [ -f "$ORACLE_HOME/network/admin/tnsnames.ora" ]; then
        cat "$ORACLE_HOME/network/admin/tnsnames.ora" | tee -a "$TEXT_OUTPUT"
    else
        log_warn "tnsnames.ora not found at $ORACLE_HOME/network/admin/tnsnames.ora"
    fi
else
    log_warn "ORACLE_HOME not set - cannot check network configuration"
fi

################################################################################
# ADDITIONAL DISCOVERY: Network Security Group Rules
################################################################################

log_section "NETWORK SECURITY GROUP RULES"

log_info "Checking Azure NSG rules via Azure Instance Metadata Service..."

# Check if Azure IMDS is accessible
AZURE_TOKEN=$(curl -s -H "Metadata:true" "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/" 2>/dev/null | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)

if [ -n "$AZURE_TOKEN" ]; then
    log_info "Azure managed identity available - can query NSG rules via Azure API"
    # Get subscription and resource group from instance metadata
    AZURE_METADATA=$(curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" 2>/dev/null)
    echo "Azure Instance Metadata:" >> "$TEXT_OUTPUT"
    echo "$AZURE_METADATA" | tee -a "$TEXT_OUTPUT"
else
    log_info "Azure managed identity not available - listing local firewall rules instead"
fi

log_info "Local Firewall Rules (iptables):"
sudo iptables -L -n 2>/dev/null | tee -a "$TEXT_OUTPUT" || log_warn "Cannot list iptables rules"

log_info "Listening Ports:"
ss -tlnp 2>/dev/null | tee -a "$TEXT_OUTPUT" || netstat -tlnp 2>/dev/null | tee -a "$TEXT_OUTPUT"

################################################################################
# OCI/Azure Integration
################################################################################

log_section "OCI/AZURE INTEGRATION"

log_info "OCI CLI Version:"
oci --version 2>&1 | tee -a "$TEXT_OUTPUT" || log_warn "OCI CLI not installed"

log_info "OCI Config File:"
if [ -f ~/.oci/config ]; then
    # Mask sensitive data
    grep -E '^\[|^region|^tenancy|^user' ~/.oci/config 2>/dev/null | tee -a "$TEXT_OUTPUT"
    log_info "OCI config file exists (sensitive data masked)"
else
    log_warn "OCI config file not found at ~/.oci/config"
fi

log_info "OCI Connectivity Test:"
oci iam region list --query 'data[0].name' --raw-output 2>&1 | tee -a "$TEXT_OUTPUT" || log_warn "OCI connectivity test failed"

log_info "OCI Instance Metadata:"
curl -s -H "Authorization: Bearer Oracle" http://169.254.169.254/opc/v2/instance/ 2>/dev/null | tee -a "$TEXT_OUTPUT" || log_info "OCI instance metadata not available"

log_info "Azure Instance Metadata:"
curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" 2>/dev/null | tee -a "$TEXT_OUTPUT" || log_info "Azure instance metadata not available"

################################################################################
# Grid Infrastructure (if RAC)
################################################################################

log_section "GRID INFRASTRUCTURE"

# Check for Grid Infrastructure
GRID_HOME=""
if [ -f /etc/oracle/olr.loc ]; then
    GRID_HOME=$(grep '^crs_home=' /etc/oracle/olr.loc 2>/dev/null | cut -d= -f2)
fi

if [ -n "$GRID_HOME" ] && [ -d "$GRID_HOME" ]; then
    log_info "Grid Home: $GRID_HOME"
    echo "Grid Home: $GRID_HOME" >> "$TEXT_OUTPUT"
    
    log_info "CRS Status:"
    if [ "$(whoami)" = "root" ]; then
        "$GRID_HOME/bin/crsctl" stat res -t 2>&1 | tee -a "$TEXT_OUTPUT" || log_warn "Could not get CRS status"
    else
        sudo "$GRID_HOME/bin/crsctl" stat res -t 2>&1 | tee -a "$TEXT_OUTPUT" || log_warn "Could not get CRS status"
    fi
    
    log_info "Cluster Nodes:"
    "$GRID_HOME/bin/olsnodes" -n 2>&1 | tee -a "$TEXT_OUTPUT" || log_warn "Could not get cluster nodes"
else
    log_info "Grid Infrastructure not detected - likely single instance"
fi

################################################################################
# Authentication
################################################################################

log_section "AUTHENTICATION"

log_info "SSH Directory Contents (opc user):"
if [ -d ~/.ssh ]; then
    ls -la ~/.ssh 2>/dev/null | tee -a "$TEXT_OUTPUT"
else
    log_warn "SSH directory not found"
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
# Finalize JSON Output
################################################################################

log_section "FINALIZING DISCOVERY"

# Get key values for JSON
DB_NAME=$(run_sql_value "SELECT name FROM v\$database;" 2>/dev/null)
DB_VERSION=$(run_sql_value "SELECT version FROM v\$instance;" 2>/dev/null)
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
    "cdb_status": "${CDB_STATUS:-UNKNOWN}",
    "tde_status": "${TDE_STATUS:-NOT CONFIGURED}",
    "character_set": "${CHARSET:-UNKNOWN}"
  },
  "grid_infrastructure": {
    "grid_home": "${GRID_HOME:-NOT DETECTED}"
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
