#!/bin/bash
#===============================================================================
# ZDM Target Database Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# Target: proddb-oda.eastus.azure.example.com
#
# This script discovers target database configuration for ZDM migration.
# It is executed via SSH as an admin user (opc), with SQL commands running
# as the oracle user via sudo.
#
# Usage: ./zdm_target_discovery.sh
# Output: zdm_target_discovery_<hostname>_<timestamp>.txt
#         zdm_target_discovery_<hostname>_<timestamp>.json
#===============================================================================

#-------------------------------------------------------------------------------
# Color Output Functions
#-------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "\n${CYAN}=== $1 ===${NC}"; }

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
HOSTNAME=$(hostname -s 2>/dev/null || hostname)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="./zdm_target_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_target_discovery_${HOSTNAME}_${TIMESTAMP}.json"

# User configuration
ORACLE_USER="${ORACLE_USER:-oracle}"

#-------------------------------------------------------------------------------
# Auto-detect Oracle Environment
#-------------------------------------------------------------------------------
detect_oracle_env() {
    log_info "Auto-detecting Oracle environment..."
    
    # If already set, use existing values
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        log_info "Using pre-configured ORACLE_HOME=$ORACLE_HOME, ORACLE_SID=$ORACLE_SID"
        return 0
    fi
    
    # Method 1: Parse /etc/oratab (most reliable)
    if [ -f /etc/oratab ]; then
        local oratab_entry
        if [ -n "${ORACLE_SID:-}" ]; then
            oratab_entry=$(grep "^${ORACLE_SID}:" /etc/oratab 2>/dev/null | head -1)
        else
            oratab_entry=$(grep -v '^#' /etc/oratab | grep -v '^$' | grep -v '^\*' | head -1)
        fi
        if [ -n "$oratab_entry" ]; then
            export ORACLE_SID="${ORACLE_SID:-$(echo "$oratab_entry" | cut -d: -f1)}"
            export ORACLE_HOME="${ORACLE_HOME:-$(echo "$oratab_entry" | cut -d: -f2)}"
            log_info "Detected from oratab: ORACLE_SID=$ORACLE_SID, ORACLE_HOME=$ORACLE_HOME"
        fi
    fi
    
    # Method 2: Check running pmon process
    if [ -z "${ORACLE_SID:-}" ]; then
        local pmon_sid
        pmon_sid=$(ps -ef | grep 'ora_pmon_' | grep -v grep | head -1 | sed 's/.*ora_pmon_//')
        if [ -n "$pmon_sid" ]; then
            export ORACLE_SID="$pmon_sid"
            log_info "Detected from pmon process: ORACLE_SID=$ORACLE_SID"
        fi
    fi
    
    # Method 3: Search common Oracle installation paths (ODA/Exadata paths)
    if [ -z "${ORACLE_HOME:-}" ]; then
        for path in /u02/app/oracle/product/*/dbhome_1 /u01/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1; do
            if [ -d "$path" ] && [ -f "$path/bin/sqlplus" ]; then
                export ORACLE_HOME="$path"
                log_info "Detected from common path: ORACLE_HOME=$ORACLE_HOME"
                break
            fi
        done
    fi
    
    # Method 4: Get from oracle user's environment
    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        if id "$ORACLE_USER" &>/dev/null; then
            local oracle_env
            oracle_env=$(sudo -u "$ORACLE_USER" -i bash -c 'echo "ORACLE_HOME=$ORACLE_HOME;ORACLE_SID=$ORACLE_SID"' 2>/dev/null)
            if [ -n "$oracle_env" ]; then
                eval "$oracle_env"
                [ -n "$ORACLE_HOME" ] && export ORACLE_HOME
                [ -n "$ORACLE_SID" ] && export ORACLE_SID
                log_info "Detected from oracle user environment: ORACLE_HOME=$ORACLE_HOME, ORACLE_SID=$ORACLE_SID"
            fi
        fi
    fi
    
    # Apply explicit overrides if provided (highest priority)
    [ -n "${ORACLE_HOME_OVERRIDE:-}" ] && export ORACLE_HOME="$ORACLE_HOME_OVERRIDE"
    [ -n "${ORACLE_SID_OVERRIDE:-}" ] && export ORACLE_SID="$ORACLE_SID_OVERRIDE"
}

#-------------------------------------------------------------------------------
# SQL Execution Functions
#-------------------------------------------------------------------------------
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
            result=$(echo "$sql_script" | ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd 2>/dev/null)
        else
            result=$(echo "$sql_script" | sudo -u "$ORACLE_USER" ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd 2>/dev/null)
        fi
        echo "$result" | sed '/^$/d' | head -1
    else
        echo "ERROR"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# Discovery Functions
#-------------------------------------------------------------------------------

discover_os_info() {
    log_section "OS Information"
    echo "Hostname: $(hostname)"
    echo "FQDN: $(hostname -f 2>/dev/null || echo 'N/A')"
    echo "IP Addresses:"
    ip addr show 2>/dev/null | grep 'inet ' | awk '{print "  " $2}' || hostname -I 2>/dev/null | tr ' ' '\n' | sed 's/^/  /'
    echo ""
    echo "Operating System:"
    cat /etc/os-release 2>/dev/null | grep -E '^(NAME|VERSION)=' || cat /etc/redhat-release 2>/dev/null
    echo ""
    echo "Kernel: $(uname -r)"
}

discover_oracle_env() {
    log_section "Oracle Environment"
    echo "ORACLE_HOME: ${ORACLE_HOME:-NOT SET}"
    echo "ORACLE_SID: ${ORACLE_SID:-NOT SET}"
    echo "ORACLE_BASE: ${ORACLE_BASE:-NOT SET}"
    
    if [ -n "${ORACLE_HOME:-}" ]; then
        if [ -f "$ORACLE_HOME/bin/sqlplus" ]; then
            echo ""
            echo "Oracle Version:"
            if [ "$(whoami)" = "$ORACLE_USER" ]; then
                $ORACLE_HOME/bin/sqlplus -V 2>/dev/null | head -3
            else
                sudo -u "$ORACLE_USER" ORACLE_HOME="$ORACLE_HOME" $ORACLE_HOME/bin/sqlplus -V 2>/dev/null | head -3
            fi
        fi
    fi
}

discover_db_config() {
    log_section "Database Configuration"
    
    run_sql "SELECT 'Database Name: ' || name FROM v\$database;"
    run_sql "SELECT 'DB Unique Name: ' || db_unique_name FROM v\$database;"
    run_sql "SELECT 'Database Role: ' || database_role FROM v\$database;"
    run_sql "SELECT 'Open Mode: ' || open_mode FROM v\$database;"
    
    echo ""
    echo "Character Set:"
    run_sql "SELECT 'Character Set: ' || value FROM nls_database_parameters WHERE parameter = 'NLS_CHARACTERSET';"
    run_sql "SELECT 'National Character Set: ' || value FROM nls_database_parameters WHERE parameter = 'NLS_NCHAR_CHARACTERSET';"
}

discover_storage() {
    log_section "Available Storage"
    
    echo "Tablespace Usage:"
    run_sql "
SELECT tablespace_name, 
       ROUND(SUM(bytes)/1024/1024/1024, 2) AS used_gb,
       ROUND(SUM(maxbytes)/1024/1024/1024, 2) AS max_gb
FROM dba_data_files
GROUP BY tablespace_name
ORDER BY tablespace_name;
"
    
    echo ""
    echo "ASM Disk Groups (if applicable):"
    run_sql "
SELECT name, state, type, 
       ROUND(total_mb/1024, 2) AS total_gb,
       ROUND(free_mb/1024, 2) AS free_gb,
       ROUND((total_mb - free_mb)/total_mb * 100, 1) AS pct_used
FROM v\$asm_diskgroup;
"
    
    echo ""
    echo "Disk Space (OS Level):"
    df -h 2>/dev/null | grep -E '^/|Filesystem'
}

discover_cdb_pdb() {
    log_section "Container Database Configuration"
    
    local cdb_status=$(run_sql_value "SELECT CDB FROM v\$database;")
    echo "CDB Status: $cdb_status"
    
    if [ "$cdb_status" = "YES" ]; then
        echo ""
        echo "PDB List:"
        run_sql "
SELECT con_id, name, open_mode, restricted, 
       ROUND(total_size/1024/1024/1024, 2) AS size_gb
FROM v\$pdbs
ORDER BY con_id;
"
    fi
}

discover_tde() {
    log_section "TDE/Wallet Configuration"
    
    echo "Encryption Wallet Status:"
    run_sql "
SELECT wrl_type, wrl_parameter, status, wallet_type, wallet_order
FROM v\$encryption_wallet;
"
}

discover_network_config() {
    log_section "Network Configuration"
    
    echo "Listener Status:"
    if [ -n "${ORACLE_HOME:-}" ]; then
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            ORACLE_HOME="$ORACLE_HOME" $ORACLE_HOME/bin/lsnrctl status 2>/dev/null | head -30
        else
            sudo -u "$ORACLE_USER" ORACLE_HOME="$ORACLE_HOME" $ORACLE_HOME/bin/lsnrctl status 2>/dev/null | head -30
        fi
    fi
    
    echo ""
    echo "SCAN Listener (if RAC):"
    if [ -n "${ORACLE_HOME:-}" ]; then
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            ORACLE_HOME="$ORACLE_HOME" $ORACLE_HOME/bin/srvctl status scan_listener 2>/dev/null || echo "Not a RAC configuration or srvctl not available"
        else
            sudo -u "$ORACLE_USER" ORACLE_HOME="$ORACLE_HOME" $ORACLE_HOME/bin/srvctl status scan_listener 2>/dev/null || echo "Not a RAC configuration or srvctl not available"
        fi
    fi
    
    echo ""
    echo "tnsnames.ora:"
    if [ -n "${ORACLE_HOME:-}" ] && [ -f "$ORACLE_HOME/network/admin/tnsnames.ora" ]; then
        cat "$ORACLE_HOME/network/admin/tnsnames.ora" 2>/dev/null
    else
        echo "File not found"
    fi
}

discover_oci_azure_integration() {
    log_section "OCI/Azure Integration"
    
    echo "OCI CLI Version:"
    oci --version 2>/dev/null || echo "OCI CLI not installed or not in PATH"
    
    echo ""
    echo "OCI Configuration:"
    if [ -f ~/.oci/config ]; then
        echo "OCI config file found at ~/.oci/config"
        echo "Configured profiles:"
        grep '^\[' ~/.oci/config 2>/dev/null | tr -d '[]'
        echo ""
        echo "Default region:"
        grep 'region' ~/.oci/config 2>/dev/null | head -1
    else
        echo "OCI config file not found"
    fi
    
    echo ""
    echo "OCI Connectivity Test:"
    if command -v oci &>/dev/null; then
        oci iam region list --query 'data[0].name' --raw-output 2>/dev/null && echo "OCI connectivity: SUCCESS" || echo "OCI connectivity: FAILED"
    else
        echo "OCI CLI not available for connectivity test"
    fi
    
    echo ""
    echo "Instance Metadata (OCI):"
    curl -s -H "Authorization: Bearer Oracle" http://169.254.169.254/opc/v2/instance/ 2>/dev/null | head -20 || echo "OCI instance metadata not available"
    
    echo ""
    echo "Instance Metadata (Azure):"
    curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" 2>/dev/null | head -20 || echo "Azure instance metadata not available"
}

discover_grid_infrastructure() {
    log_section "Grid Infrastructure (if RAC)"
    
    echo "CRS Status:"
    if [ -f /etc/oracle/olr.loc ]; then
        local crs_home=$(grep '^crs_home=' /etc/oracle/olr.loc 2>/dev/null | cut -d= -f2)
        if [ -n "$crs_home" ] && [ -f "$crs_home/bin/crsctl" ]; then
            sudo "$crs_home/bin/crsctl" check crs 2>/dev/null || echo "CRS check failed"
        else
            echo "CRS home not found or crsctl not available"
        fi
    else
        echo "Not a RAC/Grid Infrastructure configuration"
    fi
}

discover_ssh_config() {
    log_section "SSH Configuration"
    
    echo "SSH Directory Contents (for opc user):"
    if [ -d ~/.ssh ]; then
        ls -la ~/.ssh/ 2>/dev/null
    else
        echo "SSH directory not found"
    fi
    
    echo ""
    echo "Authorized Keys:"
    if [ -f ~/.ssh/authorized_keys ]; then
        echo "authorized_keys file exists with $(wc -l < ~/.ssh/authorized_keys) entries"
    else
        echo "No authorized_keys file found"
    fi
}

#-------------------------------------------------------------------------------
# Additional Discovery (Custom Requirements)
#-------------------------------------------------------------------------------

discover_exadata_storage() {
    log_section "Exadata Storage Capacity"
    
    echo "ASM Disk Group Details:"
    run_sql "
SELECT dg.name AS diskgroup_name,
       dg.type AS redundancy,
       ROUND(dg.total_mb/1024, 2) AS total_gb,
       ROUND(dg.free_mb/1024, 2) AS free_gb,
       ROUND((dg.total_mb - dg.free_mb)/dg.total_mb * 100, 1) AS pct_used,
       COUNT(d.disk_number) AS disk_count
FROM v\$asm_diskgroup dg
LEFT JOIN v\$asm_disk d ON dg.group_number = d.group_number
GROUP BY dg.name, dg.type, dg.total_mb, dg.free_mb
ORDER BY dg.name;
"
    
    echo ""
    echo "Cell Disk Information (Exadata):"
    run_sql "
SELECT cell_path, total_mb, free_mb
FROM v\$asm_disk
WHERE cell_path IS NOT NULL
ORDER BY cell_path;
" 2>/dev/null || echo "Not an Exadata configuration or cell information not available"
}

discover_preconfigured_pdbs() {
    log_section "Pre-configured PDBs"
    
    run_sql "
SELECT p.con_id, p.name AS pdb_name, p.open_mode, p.restricted,
       ROUND(p.total_size/1024/1024/1024, 2) AS total_size_gb,
       s.name AS service_name
FROM v\$pdbs p
LEFT JOIN v\$services s ON p.con_id = s.con_id AND s.name NOT LIKE 'SYS%'
ORDER BY p.con_id;
"
    
    echo ""
    echo "PDB Services:"
    run_sql "
SELECT con_id, name AS service_name, network_name, creation_date
FROM v\$services
WHERE con_id > 1
ORDER BY con_id, name;
"
}

discover_network_security() {
    log_section "Network Security Group Rules"
    
    echo "Firewall Rules (iptables):"
    sudo iptables -L -n 2>/dev/null | head -50 || echo "Unable to retrieve iptables rules"
    
    echo ""
    echo "Firewalld Status:"
    sudo systemctl status firewalld 2>/dev/null | head -10 || echo "Firewalld not installed or not running"
    
    echo ""
    echo "Active Network Connections (Oracle ports):"
    ss -tlnp 2>/dev/null | grep -E ':(1521|1522|1523|5500|5501)' || netstat -tlnp 2>/dev/null | grep -E ':(1521|1522|1523|5500|5501)'
    
    echo ""
    echo "Note: Azure NSG rules are managed at the Azure/OCI level and should be reviewed in the Azure portal or via OCI CLI"
}

#-------------------------------------------------------------------------------
# JSON Output Generation
#-------------------------------------------------------------------------------
generate_json_summary() {
    local db_name=$(run_sql_value "SELECT name FROM v\$database;")
    local db_unique_name=$(run_sql_value "SELECT db_unique_name FROM v\$database;")
    local db_role=$(run_sql_value "SELECT database_role FROM v\$database;")
    local open_mode=$(run_sql_value "SELECT open_mode FROM v\$database;")
    local cdb_status=$(run_sql_value "SELECT CDB FROM v\$database;")
    local charset=$(run_sql_value "SELECT value FROM nls_database_parameters WHERE parameter = 'NLS_CHARACTERSET';")
    local version=$(run_sql_value "SELECT version_full FROM v\$instance;" 2>/dev/null || run_sql_value "SELECT version FROM v\$instance;")
    local wallet_status=$(run_sql_value "SELECT status FROM v\$encryption_wallet WHERE ROWNUM = 1;")
    local asm_total=$(run_sql_value "SELECT ROUND(SUM(total_mb)/1024, 2) FROM v\$asm_diskgroup;" 2>/dev/null || echo "N/A")
    local asm_free=$(run_sql_value "SELECT ROUND(SUM(free_mb)/1024, 2) FROM v\$asm_diskgroup;" 2>/dev/null || echo "N/A")
    
    cat > "$JSON_FILE" <<EOF
{
  "discovery_type": "target",
  "discovery_timestamp": "$(date -Iseconds)",
  "hostname": "$HOSTNAME",
  "oracle_home": "${ORACLE_HOME:-}",
  "oracle_sid": "${ORACLE_SID:-}",
  "database": {
    "name": "$db_name",
    "unique_name": "$db_unique_name",
    "role": "$db_role",
    "open_mode": "$open_mode",
    "cdb": "$cdb_status",
    "version": "$version",
    "character_set": "$charset"
  },
  "tde": {
    "wallet_status": "$wallet_status"
  },
  "storage": {
    "asm_total_gb": "$asm_total",
    "asm_free_gb": "$asm_free"
  },
  "output_files": {
    "text_report": "$OUTPUT_FILE",
    "json_summary": "$JSON_FILE"
  }
}
EOF
    
    log_info "JSON summary written to: $JSON_FILE"
}

#-------------------------------------------------------------------------------
# Main Execution
#-------------------------------------------------------------------------------
main() {
    log_info "Starting ZDM Target Discovery on $HOSTNAME"
    log_info "Timestamp: $TIMESTAMP"
    log_info "Running as user: $(whoami)"
    log_info "Oracle user for SQL execution: $ORACLE_USER"
    
    # Detect Oracle environment
    detect_oracle_env
    
    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        log_warn "Oracle environment not fully detected. Some database discovery will be skipped."
    fi
    
    # Run all discovery sections with error handling
    {
        echo "==============================================================================="
        echo "ZDM Target Database Discovery Report"
        echo "Project: PRODDB Migration to Oracle Database@Azure"
        echo "Target: proddb-oda.eastus.azure.example.com"
        echo "Generated: $(date)"
        echo "Hostname: $HOSTNAME"
        echo "==============================================================================="
        
        # Standard discovery
        discover_os_info || log_warn "OS info discovery had errors"
        discover_oracle_env || log_warn "Oracle env discovery had errors"
        discover_db_config || log_warn "DB config discovery had errors"
        discover_storage || log_warn "Storage discovery had errors"
        discover_cdb_pdb || log_warn "CDB/PDB discovery had errors"
        discover_tde || log_warn "TDE discovery had errors"
        discover_network_config || log_warn "Network config discovery had errors"
        discover_oci_azure_integration || log_warn "OCI/Azure integration discovery had errors"
        discover_grid_infrastructure || log_warn "Grid infrastructure discovery had errors"
        discover_ssh_config || log_warn "SSH config discovery had errors"
        
        # Additional custom discovery requirements
        discover_exadata_storage || log_warn "Exadata storage discovery had errors"
        discover_preconfigured_pdbs || log_warn "Pre-configured PDBs discovery had errors"
        discover_network_security || log_warn "Network security discovery had errors"
        
        echo ""
        echo "==============================================================================="
        echo "End of Discovery Report"
        echo "==============================================================================="
    } 2>&1 | tee "$OUTPUT_FILE"
    
    # Generate JSON summary
    generate_json_summary
    
    log_info "Discovery complete!"
    log_info "Text report: $OUTPUT_FILE"
    log_info "JSON summary: $JSON_FILE"
}

# Execute main function
main "$@"
