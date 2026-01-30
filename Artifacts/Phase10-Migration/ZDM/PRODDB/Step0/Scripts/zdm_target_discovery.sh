#!/bin/bash
# ===========================================
# ZDM Target Database Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# Target Server: proddb-oda.eastus.azure.example.com
# Generated: 2026-01-30
# ===========================================
#
# This script discovers target Oracle Database@Azure configuration for ZDM migration.
# Run as: opc user (or admin user with sudo to oracle)
#
# Usage:
#   ./zdm_target_discovery.sh
#
# Output:
#   - zdm_target_discovery_<hostname>_<timestamp>.txt (human-readable)
#   - zdm_target_discovery_<hostname>_<timestamp>.json (machine-parseable)
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
OUTPUT_TXT="./zdm_target_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
OUTPUT_JSON="./zdm_target_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

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
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        return 0
    fi
    
    # Method 1: Parse /etc/oratab
    if [ -f /etc/oratab ]; then
        local oratab_entry
        oratab_entry=$(grep -v '^#' /etc/oratab | grep -v '^$' | head -1)
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
    
    # Method 3: Search common Oracle installation paths (including Exadata paths)
    if [ -z "${ORACLE_HOME:-}" ]; then
        for path in /u02/app/oracle/product/*/dbhome_1 /u01/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1; do
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
echo -e "${BLUE}  ZDM Target Database Discovery${NC}"
echo -e "${BLUE}  Project: PRODDB Migration${NC}"
echo -e "${BLUE}  Oracle Database@Azure (Exadata)${NC}"
echo -e "${BLUE}=========================================${NC}"

# Initialize output file
echo "ZDM Target Database Discovery Report" > "$OUTPUT_TXT"
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
    log_warn "Oracle environment not fully configured or database not running"
    ORACLE_VERSION="UNKNOWN"
fi

# -------------------------------------------
# DATABASE CONFIGURATION
# -------------------------------------------
log_section "Database Configuration"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    DB_NAME=$(run_sql_value "SELECT name FROM v\$database;")
    DB_UNIQUE_NAME=$(run_sql_value "SELECT db_unique_name FROM v\$database;")
    DB_ROLE=$(run_sql_value "SELECT database_role FROM v\$database;")
    OPEN_MODE=$(run_sql_value "SELECT open_mode FROM v\$database;")
    
    if [ -n "$DB_NAME" ] && [ "$DB_NAME" != "ERROR" ]; then
        log_info "Database Name: $DB_NAME"
        log_info "DB Unique Name: $DB_UNIQUE_NAME"
        log_info "Database Role: $DB_ROLE"
        log_info "Open Mode: $OPEN_MODE"
        
        # Character Set
        CHARACTERSET=$(run_sql_value "SELECT value FROM nls_database_parameters WHERE parameter = 'NLS_CHARACTERSET';")
        log_info "Character Set: $CHARACTERSET"
    else
        log_warn "Database not open or not yet created (expected for new target)"
        DB_NAME="NOT_CREATED"
        DB_ROLE="N/A"
        OPEN_MODE="N/A"
    fi
fi

# -------------------------------------------
# CONTAINER DATABASE STATUS
# -------------------------------------------
log_section "Container Database Status"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ] && [ "$DB_NAME" != "NOT_CREATED" ]; then
    CDB_STATUS=$(run_sql_value "SELECT CDB FROM v\$database;")
    log_info "CDB Status: $CDB_STATUS"
    
    if [ "$CDB_STATUS" = "YES" ]; then
        echo "" >> "$OUTPUT_TXT"
        echo "PDB Information:" >> "$OUTPUT_TXT"
        run_sql "SELECT pdb_name, status, open_mode FROM dba_pdbs ORDER BY pdb_name;" >> "$OUTPUT_TXT"
    fi
else
    log_info "CDB Status: Database not yet created"
    CDB_STATUS="PENDING"
fi

# -------------------------------------------
# TDE/WALLET STATUS
# -------------------------------------------
log_section "TDE/Wallet Configuration"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ] && [ "$DB_NAME" != "NOT_CREATED" ]; then
    TDE_STATUS=$(run_sql_value "SELECT status FROM v\$encryption_wallet WHERE rownum = 1;")
    WALLET_TYPE=$(run_sql_value "SELECT wallet_type FROM v\$encryption_wallet WHERE rownum = 1;")
    
    log_info "TDE Wallet Status: ${TDE_STATUS:-NOT CONFIGURED}"
    log_info "Wallet Type: ${WALLET_TYPE:-N/A}"
else
    log_info "TDE Status: Database not yet created"
    TDE_STATUS="PENDING"
fi

# -------------------------------------------
# EXADATA STORAGE CAPACITY (CUSTOM REQUIREMENT)
# -------------------------------------------
log_section "Exadata Storage Capacity"

# Check for ASM disk groups
if [ -n "${ORACLE_HOME:-}" ]; then
    GRID_HOME=$(cat /etc/oratab 2>/dev/null | grep "^+ASM" | cut -d: -f2 | head -1)
    
    if [ -n "$GRID_HOME" ] && [ -f "$GRID_HOME/bin/asmcmd" ]; then
        echo "" >> "$OUTPUT_TXT"
        echo "ASM Disk Groups:" >> "$OUTPUT_TXT"
        if [ "$(whoami)" = "grid" ]; then
            $GRID_HOME/bin/asmcmd lsdg >> "$OUTPUT_TXT" 2>&1
        else
            sudo -u grid ORACLE_HOME="$GRID_HOME" $GRID_HOME/bin/asmcmd lsdg >> "$OUTPUT_TXT" 2>&1 || log_warn "Could not query ASM disk groups"
        fi
    fi
    
    # Query v$asm_diskgroup if database is available
    if [ "$DB_NAME" != "NOT_CREATED" ]; then
        echo "" >> "$OUTPUT_TXT"
        echo "ASM Disk Group Space (from database):" >> "$OUTPUT_TXT"
        run_sql "SELECT name, 
                 ROUND(total_mb/1024, 2) AS total_gb,
                 ROUND(free_mb/1024, 2) AS free_gb,
                 ROUND((total_mb-free_mb)/1024, 2) AS used_gb,
                 ROUND(((total_mb-free_mb)/total_mb)*100, 1) AS pct_used,
                 state, type
                 FROM v\$asm_diskgroup
                 ORDER BY name;" >> "$OUTPUT_TXT"
    fi
fi

# -------------------------------------------
# PRE-CONFIGURED PDBs (CUSTOM REQUIREMENT)
# -------------------------------------------
log_section "Pre-Configured PDBs"

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ] && [ "$DB_NAME" != "NOT_CREATED" ]; then
    if [ "$CDB_STATUS" = "YES" ]; then
        echo "" >> "$OUTPUT_TXT"
        echo "Existing PDBs:" >> "$OUTPUT_TXT"
        run_sql "SELECT con_id, pdb_name, status, open_mode, 
                 ROUND(total_size/1024/1024/1024, 2) AS size_gb,
                 creation_time
                 FROM dba_pdbs
                 ORDER BY con_id;" >> "$OUTPUT_TXT"
    else
        log_info "Database is non-CDB, no PDBs"
    fi
else
    log_info "Database not yet created - no PDBs"
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

# SCAN listener (if RAC/Exadata)
echo "" >> "$OUTPUT_TXT"
echo "SCAN Listener (if RAC):" >> "$OUTPUT_TXT"
if [ -n "$GRID_HOME" ]; then
    sudo -u grid ORACLE_HOME="$GRID_HOME" $GRID_HOME/bin/srvctl status scan_listener >> "$OUTPUT_TXT" 2>&1 || echo "Not a RAC configuration or SCAN not configured" >> "$OUTPUT_TXT"
fi

# tnsnames.ora
echo "" >> "$OUTPUT_TXT"
echo "tnsnames.ora:" >> "$OUTPUT_TXT"
if [ -f "$ORACLE_HOME/network/admin/tnsnames.ora" ]; then
    cat "$ORACLE_HOME/network/admin/tnsnames.ora" >> "$OUTPUT_TXT" 2>/dev/null
else
    echo "File not found" >> "$OUTPUT_TXT"
fi

# -------------------------------------------
# NETWORK SECURITY GROUP RULES (CUSTOM REQUIREMENT)
# -------------------------------------------
log_section "Network Security (NSG/Firewall)"

# Check iptables/firewalld
echo "" >> "$OUTPUT_TXT"
echo "Firewall Status:" >> "$OUTPUT_TXT"
if command -v firewall-cmd &>/dev/null; then
    sudo firewall-cmd --state >> "$OUTPUT_TXT" 2>&1
    echo "" >> "$OUTPUT_TXT"
    echo "Open Ports:" >> "$OUTPUT_TXT"
    sudo firewall-cmd --list-ports >> "$OUTPUT_TXT" 2>&1
    echo "" >> "$OUTPUT_TXT"
    echo "Allowed Services:" >> "$OUTPUT_TXT"
    sudo firewall-cmd --list-services >> "$OUTPUT_TXT" 2>&1
fi

# Check listening ports
echo "" >> "$OUTPUT_TXT"
echo "Listening Ports (Oracle-related):" >> "$OUTPUT_TXT"
ss -tlnp 2>/dev/null | grep -E ':(1521|1522|1523|5500|5501)' >> "$OUTPUT_TXT" || netstat -tlnp 2>/dev/null | grep -E ':(1521|1522|1523|5500|5501)' >> "$OUTPUT_TXT"

# -------------------------------------------
# OCI/AZURE INTEGRATION
# -------------------------------------------
log_section "OCI/Azure Integration"

# OCI CLI
if command -v oci &>/dev/null; then
    OCI_VERSION=$(oci --version 2>&1)
    log_info "OCI CLI Version: $OCI_VERSION"
    
    # Test OCI connectivity
    echo "" >> "$OUTPUT_TXT"
    echo "OCI Connectivity Test:" >> "$OUTPUT_TXT"
    oci os ns get >> "$OUTPUT_TXT" 2>&1 && log_info "OCI connectivity: OK" || log_warn "OCI connectivity: FAILED"
else
    log_info "OCI CLI: Not installed"
    OCI_VERSION="NOT INSTALLED"
fi

# Azure Instance Metadata
echo "" >> "$OUTPUT_TXT"
echo "Azure Instance Metadata:" >> "$OUTPUT_TXT"
curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" 2>/dev/null | python3 -m json.tool >> "$OUTPUT_TXT" 2>/dev/null || echo "Not running on Azure or metadata service unavailable" >> "$OUTPUT_TXT"

# OCI Instance Metadata
echo "" >> "$OUTPUT_TXT"
echo "OCI Instance Metadata:" >> "$OUTPUT_TXT"
curl -s -H "Authorization: Bearer Oracle" "http://169.254.169.254/opc/v2/instance/" 2>/dev/null | python3 -m json.tool >> "$OUTPUT_TXT" 2>/dev/null || echo "OCI metadata service unavailable" >> "$OUTPUT_TXT"

# -------------------------------------------
# GRID INFRASTRUCTURE STATUS
# -------------------------------------------
log_section "Grid Infrastructure Status"

if [ -n "$GRID_HOME" ]; then
    echo "" >> "$OUTPUT_TXT"
    echo "CRS Status:" >> "$OUTPUT_TXT"
    sudo -u grid ORACLE_HOME="$GRID_HOME" $GRID_HOME/bin/crsctl stat res -t >> "$OUTPUT_TXT" 2>&1 || log_warn "Could not get CRS status"
else
    log_info "Grid Infrastructure: Not detected"
fi

# -------------------------------------------
# SSH CONFIGURATION
# -------------------------------------------
log_section "SSH Configuration"

echo "" >> "$OUTPUT_TXT"
echo "SSH Directory Contents (~/.ssh/):" >> "$OUTPUT_TXT"
ls -la ~/.ssh/ >> "$OUTPUT_TXT" 2>/dev/null || echo "SSH directory not found" >> "$OUTPUT_TXT"

# Check oracle user's SSH
echo "" >> "$OUTPUT_TXT"
echo "Oracle user SSH Directory (~oracle/.ssh/):" >> "$OUTPUT_TXT"
sudo ls -la ~oracle/.ssh/ >> "$OUTPUT_TXT" 2>/dev/null || echo "Oracle SSH directory not found" >> "$OUTPUT_TXT"

# -------------------------------------------
# GENERATE JSON OUTPUT
# -------------------------------------------
log_section "Generating JSON Output"

cat > "$OUTPUT_JSON" << EOJSON
{
  "discovery_type": "target",
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
    "oracle_sid": "${ORACLE_SID:-NOT SET}"
  },
  "database": {
    "name": "${DB_NAME:-NOT_CREATED}",
    "unique_name": "${DB_UNIQUE_NAME:-N/A}",
    "role": "${DB_ROLE:-N/A}",
    "open_mode": "${OPEN_MODE:-N/A}",
    "characterset": "${CHARACTERSET:-N/A}"
  },
  "cdb": {
    "is_cdb": "${CDB_STATUS:-PENDING}"
  },
  "tde": {
    "status": "${TDE_STATUS:-PENDING}"
  },
  "oci_cli": {
    "version": "${OCI_VERSION:-NOT INSTALLED}"
  },
  "platform": "Oracle Database@Azure (Exadata)",
  "ready_for_migration": $([ "$DB_NAME" = "NOT_CREATED" ] && echo "true" || echo "false")
}
EOJSON

log_info "JSON output saved to: $OUTPUT_JSON"

# -------------------------------------------
# SUMMARY
# -------------------------------------------
log_section "Discovery Summary"

echo ""
echo -e "${GREEN}Target discovery completed!${NC}"
echo ""
echo "Output files:"
echo "  - Text report: $OUTPUT_TXT"
echo "  - JSON summary: $OUTPUT_JSON"
echo ""
echo "Target Status:"
echo "  - Database: $([ "$DB_NAME" = "NOT_CREATED" ] && echo -e "${YELLOW}Not yet created (ready for migration)${NC}" || echo -e "${GREEN}$DB_NAME${NC}")"
echo "  - Oracle Version: ${ORACLE_VERSION:-UNKNOWN}"
echo "  - OCI CLI: $([ "$OCI_VERSION" != "NOT INSTALLED" ] && echo -e "${GREEN}Installed${NC}" || echo -e "${YELLOW}Not installed${NC}")"
echo ""
