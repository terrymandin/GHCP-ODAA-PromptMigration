#!/bin/bash
#
# ZDM Target Database Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# Target Database: proddb-oda.eastus.azure.example.com
#
# This script gathers comprehensive information about the target Oracle Database@Azure
# for ZDM migration planning. It should be executed via SSH as the admin user (opc)
# with sudo privileges to run SQL commands as the oracle user.
#
# Usage: bash zdm_target_discovery.sh
#
# Output: 
#   - zdm_target_discovery_<hostname>_<timestamp>.txt (human-readable)
#   - zdm_target_discovery_<hostname>_<timestamp>.json (machine-parseable)
#

# =============================================================================
# CONFIGURATION
# =============================================================================

# Oracle user configuration
ORACLE_USER="${ORACLE_USER:-oracle}"

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Timestamp for output files
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME_SHORT=$(hostname -s)
OUTPUT_FILE="./zdm_target_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_target_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

log_section() {
    local title="$1"
    echo ""
    echo -e "${BLUE}=============================================================================${NC}"
    echo -e "${BLUE}  $title${NC}"
    echo -e "${BLUE}=============================================================================${NC}"
    echo ""
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_subsection() {
    echo ""
    echo -e "${CYAN}--- $1 ---${NC}"
    echo ""
}

# Auto-detect Oracle environment
detect_oracle_env() {
    # If already set, use existing values
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        log_info "Using pre-configured ORACLE_HOME=$ORACLE_HOME, ORACLE_SID=$ORACLE_SID"
        return 0
    fi
    
    log_info "Auto-detecting Oracle environment..."
    
    # Method 1: Parse /etc/oratab (most reliable)
    if [ -f /etc/oratab ]; then
        local oratab_entry
        if [ -n "${ORACLE_SID:-}" ]; then
            oratab_entry=$(grep "^${ORACLE_SID}:" /etc/oratab 2>/dev/null | head -1)
        else
            oratab_entry=$(grep -v '^#' /etc/oratab | grep -v '^$' | grep -v '^+' | head -1)
        fi
        if [ -n "$oratab_entry" ]; then
            export ORACLE_SID="${ORACLE_SID:-$(echo "$oratab_entry" | cut -d: -f1)}"
            export ORACLE_HOME="${ORACLE_HOME:-$(echo "$oratab_entry" | cut -d: -f2)}"
            log_info "Detected from /etc/oratab: ORACLE_SID=$ORACLE_SID, ORACLE_HOME=$ORACLE_HOME"
        fi
    fi
    
    # Method 2: Check running pmon process
    if [ -z "${ORACLE_SID:-}" ]; then
        local pmon_sid
        pmon_sid=$(ps -ef | grep 'ora_pmon_' | grep -v grep | head -1 | sed 's/.*ora_pmon_//')
        if [ -n "$pmon_sid" ]; then
            export ORACLE_SID="$pmon_sid"
            log_info "Detected ORACLE_SID from pmon process: $ORACLE_SID"
        fi
    fi
    
    # Method 3: Search common Oracle installation paths (Exadata/ODA specific)
    if [ -z "${ORACLE_HOME:-}" ]; then
        for path in /u02/app/oracle/product/*/dbhome_1 /u01/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1; do
            if [ -d "$path" ] && [ -f "$path/bin/sqlplus" ]; then
                export ORACLE_HOME="$path"
                log_info "Detected ORACLE_HOME from path search: $ORACLE_HOME"
                break
            fi
        done
    fi
    
    # Method 4: Try to get from oracle user environment
    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        local oracle_env
        oracle_env=$(sudo -u "$ORACLE_USER" -i bash -c 'echo "ORACLE_HOME=$ORACLE_HOME ORACLE_SID=$ORACLE_SID"' 2>/dev/null)
        if [ -n "$oracle_env" ]; then
            local extracted_home extracted_sid
            extracted_home=$(echo "$oracle_env" | grep -oP 'ORACLE_HOME=\K[^ ]+')
            extracted_sid=$(echo "$oracle_env" | grep -oP 'ORACLE_SID=\K[^ ]+')
            [ -z "${ORACLE_HOME:-}" ] && [ -n "$extracted_home" ] && export ORACLE_HOME="$extracted_home"
            [ -z "${ORACLE_SID:-}" ] && [ -n "$extracted_sid" ] && export ORACLE_SID="$extracted_sid"
            log_info "Detected from oracle user environment: ORACLE_HOME=$ORACLE_HOME, ORACLE_SID=$ORACLE_SID"
        fi
    fi
    
    # Apply explicit overrides if provided (highest priority)
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

# Run SQL and return single value
run_sql_value() {
    local sql_query="$1"
    local result
    result=$(run_sql "$sql_query" | grep -v '^$' | tail -1 | xargs)
    echo "$result"
}

# Initialize JSON output
init_json() {
    echo "{" > "$JSON_FILE"
    echo '  "discovery_type": "target",' >> "$JSON_FILE"
    echo "  \"hostname\": \"$HOSTNAME_SHORT\"," >> "$JSON_FILE"
    echo "  \"timestamp\": \"$TIMESTAMP\"," >> "$JSON_FILE"
    echo '  "project": "PRODDB Migration to Oracle Database@Azure",' >> "$JSON_FILE"
}

# Add JSON key-value pair
add_json() {
    local key="$1"
    local value="$2"
    local is_last="${3:-false}"
    # Escape special characters in value
    value=$(echo "$value" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g')
    if [ "$is_last" = "true" ]; then
        echo "  \"$key\": \"$value\"" >> "$JSON_FILE"
    else
        echo "  \"$key\": \"$value\"," >> "$JSON_FILE"
    fi
}

# Finalize JSON output
finalize_json() {
    echo "}" >> "$JSON_FILE"
}

# =============================================================================
# DISCOVERY FUNCTIONS
# =============================================================================

discover_os_info() {
    log_section "OS INFORMATION"
    
    log_subsection "Hostname and IP Addresses"
    echo "Hostname: $(hostname)"
    echo "Short hostname: $(hostname -s)"
    echo ""
    echo "IP Addresses:"
    ip addr show 2>/dev/null | grep 'inet ' | awk '{print "  " $2}' || hostname -I 2>/dev/null || echo "  Unable to determine"
    
    log_subsection "Operating System Version"
    if [ -f /etc/os-release ]; then
        cat /etc/os-release
    elif [ -f /etc/redhat-release ]; then
        cat /etc/redhat-release
    else
        uname -a
    fi
    
    log_subsection "Kernel Information"
    uname -r
}

discover_oracle_env() {
    log_section "ORACLE ENVIRONMENT"
    
    log_subsection "Environment Variables"
    echo "ORACLE_HOME: ${ORACLE_HOME:-NOT SET}"
    echo "ORACLE_SID: ${ORACLE_SID:-NOT SET}"
    echo "ORACLE_BASE: ${ORACLE_BASE:-NOT SET}"
    
    log_subsection "Oracle Version"
    if [ -n "${ORACLE_HOME:-}" ] && [ -f "$ORACLE_HOME/bin/sqlplus" ]; then
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            ORACLE_HOME="$ORACLE_HOME" "$ORACLE_HOME/bin/sqlplus" -v 2>/dev/null || echo "Unable to get sqlplus version"
        else
            sudo -u "$ORACLE_USER" ORACLE_HOME="$ORACLE_HOME" "$ORACLE_HOME/bin/sqlplus" -v 2>/dev/null || echo "Unable to get sqlplus version"
        fi
    else
        echo "ORACLE_HOME not set or sqlplus not found"
    fi
    
    log_subsection "Oracle Version from Database"
    run_sql "SELECT banner FROM v\$version WHERE ROWNUM = 1;"
    
    log_subsection "/etc/oratab Contents"
    if [ -f /etc/oratab ]; then
        cat /etc/oratab
    else
        echo "/etc/oratab not found"
    fi
}

discover_database_config() {
    log_section "DATABASE CONFIGURATION"
    
    log_subsection "Database Identification"
    run_sql "SELECT name, db_unique_name, dbid, created FROM v\$database;"
    
    log_subsection "Database Role and Status"
    run_sql "SELECT database_role, open_mode, protection_mode FROM v\$database;"
    
    log_subsection "Character Set Configuration"
    run_sql "SELECT parameter, value FROM nls_database_parameters WHERE parameter IN ('NLS_CHARACTERSET', 'NLS_NCHAR_CHARACTERSET', 'NLS_LANGUAGE', 'NLS_TERRITORY');"
}

discover_storage() {
    log_section "STORAGE CONFIGURATION"
    
    log_subsection "Tablespace Usage"
    run_sql "
SELECT tablespace_name,
       ROUND(SUM(bytes)/1024/1024/1024, 2) AS size_gb,
       ROUND(SUM(maxbytes)/1024/1024/1024, 2) AS max_gb,
       ROUND((SUM(maxbytes) - SUM(bytes))/1024/1024/1024, 2) AS free_gb
FROM dba_data_files
GROUP BY tablespace_name
ORDER BY tablespace_name;
"
    
    log_subsection "ASM Disk Groups (if applicable)"
    run_sql "SELECT name, state, type, total_mb, free_mb, ROUND(free_mb/total_mb*100, 2) AS pct_free FROM v\$asm_diskgroup;" 2>/dev/null || echo "ASM not configured or not accessible"
    
    log_subsection "Disk Space (OS Level)"
    df -h 2>/dev/null || df 2>/dev/null
}

discover_cdb_pdb() {
    log_section "CONTAINER DATABASE (CDB/PDB)"
    
    log_subsection "CDB Status"
    local cdb_status
    cdb_status=$(run_sql_value "SELECT cdb FROM v\$database;")
    echo "CDB Enabled: $cdb_status"
    
    if [ "$cdb_status" = "YES" ]; then
        log_subsection "PDB Information"
        run_sql "SELECT con_id, name, open_mode, restricted, total_size/1024/1024/1024 AS size_gb FROM v\$pdbs ORDER BY con_id;"
        
        log_subsection "PDB Services"
        run_sql "SELECT con_id, name, network_name FROM v\$services ORDER BY con_id;"
    else
        echo "Database is non-CDB"
    fi
}

discover_tde_config() {
    log_section "TDE (TRANSPARENT DATA ENCRYPTION)"
    
    log_subsection "Encryption Wallet Status"
    run_sql "SELECT wrl_type, wrl_parameter, status, wallet_type FROM v\$encryption_wallet;"
    
    log_subsection "Encrypted Tablespaces"
    run_sql "SELECT tablespace_name, encrypted FROM dba_tablespaces WHERE encrypted = 'YES';"
}

discover_network_config() {
    log_section "NETWORK CONFIGURATION"
    
    log_subsection "Listener Status"
    if [ -n "${ORACLE_HOME:-}" ]; then
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            ORACLE_HOME="$ORACLE_HOME" "$ORACLE_HOME/bin/lsnrctl" status 2>/dev/null || echo "Unable to get listener status"
        else
            sudo -u "$ORACLE_USER" ORACLE_HOME="$ORACLE_HOME" "$ORACLE_HOME/bin/lsnrctl" status 2>/dev/null || echo "Unable to get listener status"
        fi
    else
        echo "ORACLE_HOME not set"
    fi
    
    log_subsection "SCAN Listener (RAC)"
    if [ -n "${ORACLE_HOME:-}" ]; then
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            ORACLE_HOME="$ORACLE_HOME" srvctl status scan_listener 2>/dev/null || echo "SCAN listener not configured or srvctl not available"
        else
            sudo -u "$ORACLE_USER" ORACLE_HOME="$ORACLE_HOME" srvctl status scan_listener 2>/dev/null || echo "SCAN listener not configured or srvctl not available"
        fi
    fi
    
    log_subsection "tnsnames.ora"
    local tns_file="${ORACLE_HOME}/network/admin/tnsnames.ora"
    if [ -f "$tns_file" ]; then
        cat "$tns_file"
    else
        echo "tnsnames.ora not found at $tns_file"
    fi
    
    log_subsection "listener.ora"
    local listener_file="${ORACLE_HOME}/network/admin/listener.ora"
    if [ -f "$listener_file" ]; then
        cat "$listener_file"
    else
        echo "listener.ora not found at $listener_file"
    fi
}

discover_oci_azure_integration() {
    log_section "OCI/AZURE INTEGRATION"
    
    log_subsection "OCI CLI Version and Configuration"
    if command -v oci &> /dev/null; then
        oci --version 2>/dev/null || echo "Unable to get OCI CLI version"
        echo ""
        echo "OCI CLI Config:"
        if [ -f ~/.oci/config ]; then
            echo "Config file exists at ~/.oci/config"
            echo "Profiles configured:"
            grep '^\[' ~/.oci/config 2>/dev/null || echo "Unable to read profiles"
        else
            echo "OCI config file not found at ~/.oci/config"
        fi
    else
        echo "OCI CLI not installed"
    fi
    
    log_subsection "OCI Connectivity Test"
    if command -v oci &> /dev/null; then
        oci iam region list --output table 2>/dev/null | head -20 || echo "Unable to connect to OCI or not authenticated"
    fi
    
    log_subsection "OCI Instance Metadata"
    curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/ 2>/dev/null | head -50 || echo "OCI instance metadata not available"
    
    log_subsection "Azure Instance Metadata"
    curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" 2>/dev/null | head -50 || echo "Azure instance metadata not available"
}

discover_grid_infrastructure() {
    log_section "GRID INFRASTRUCTURE (RAC)"
    
    log_subsection "CRS Status"
    if command -v crsctl &> /dev/null; then
        crsctl check crs 2>/dev/null || echo "CRS not running or not installed"
    else
        # Try common Grid Infrastructure paths
        for gi_path in /u01/app/grid /u01/app/19.0.0/grid /opt/oracle/grid; do
            if [ -f "$gi_path/bin/crsctl" ]; then
                "$gi_path/bin/crsctl" check crs 2>/dev/null
                break
            fi
        done || echo "Grid Infrastructure not found"
    fi
    
    log_subsection "Cluster Nodes"
    if command -v olsnodes &> /dev/null; then
        olsnodes -n 2>/dev/null || echo "Not a RAC environment"
    fi
    
    log_subsection "Database Services"
    if [ -n "${ORACLE_HOME:-}" ]; then
        srvctl status database -d "${ORACLE_SID:-}" 2>/dev/null || echo "srvctl not available or database not registered"
    fi
}

discover_ssh_config() {
    log_section "SSH CONFIGURATION"
    
    log_subsection "SSH Directory Contents"
    local oracle_home_dir
    oracle_home_dir=$(eval echo ~$ORACLE_USER 2>/dev/null)
    if [ -n "$oracle_home_dir" ] && [ -d "$oracle_home_dir/.ssh" ]; then
        echo "Contents of $oracle_home_dir/.ssh:"
        ls -la "$oracle_home_dir/.ssh/" 2>/dev/null || sudo ls -la "$oracle_home_dir/.ssh/" 2>/dev/null || echo "Unable to list SSH directory"
    else
        echo "SSH directory not found for $ORACLE_USER user"
    fi
    
    log_subsection "Current User SSH"
    if [ -d ~/.ssh ]; then
        echo "Contents of ~/.ssh:"
        ls -la ~/.ssh/ 2>/dev/null
    fi
}

# =============================================================================
# ADDITIONAL DISCOVERY (Project-Specific Requirements)
# =============================================================================

discover_exadata_storage() {
    log_section "EXADATA STORAGE CAPACITY"
    
    log_subsection "Cell Storage Summary"
    run_sql "
SELECT cell_path, cell_name, 
       ROUND(total_size/1024/1024/1024, 2) AS total_gb,
       ROUND(free_size/1024/1024/1024, 2) AS free_gb
FROM v\$cell_config
WHERE conftype = 'CELLDISK';" 2>/dev/null || echo "Exadata cell storage info not available (may not be Exadata)"
    
    log_subsection "ASM Disk Groups (Exadata)"
    run_sql "
SELECT name, state, type, 
       ROUND(total_mb/1024, 2) AS total_gb,
       ROUND(free_mb/1024, 2) AS free_gb,
       ROUND(free_mb/total_mb*100, 1) AS pct_free
FROM v\$asm_diskgroup
ORDER BY name;" 2>/dev/null || echo "ASM not accessible"
    
    log_subsection "Database File Distribution"
    run_sql "
SELECT tablespace_name, 
       COUNT(*) AS file_count,
       ROUND(SUM(bytes)/1024/1024/1024, 2) AS total_gb,
       ROUND(SUM(maxbytes)/1024/1024/1024, 2) AS max_gb
FROM dba_data_files
GROUP BY tablespace_name
ORDER BY total_gb DESC;"
}

discover_preconfigured_pdbs() {
    log_section "PRE-CONFIGURED PDBs"
    
    log_subsection "All PDBs"
    run_sql "
SELECT pdb_id, pdb_name, status, con_id,
       creation_time, 
       ROUND(total_size/1024/1024/1024, 2) AS size_gb
FROM cdb_pdbs
ORDER BY pdb_id;"
    
    log_subsection "PDB Details"
    run_sql "
SELECT con_id, name, open_mode, restricted, 
       recovery_status, application_root
FROM v\$pdbs
ORDER BY con_id;"
    
    log_subsection "PDB Tablespaces"
    run_sql "
SELECT c.name AS pdb_name, t.tablespace_name, 
       ROUND(SUM(d.bytes)/1024/1024/1024, 2) AS size_gb
FROM v\$pdbs c
JOIN cdb_tablespaces t ON c.con_id = t.con_id
JOIN cdb_data_files d ON t.tablespace_name = d.tablespace_name AND t.con_id = d.con_id
GROUP BY c.name, t.tablespace_name
ORDER BY c.name, t.tablespace_name;" 2>/dev/null || echo "PDB tablespace query not supported"
}

discover_nsg_rules() {
    log_section "NETWORK SECURITY GROUP RULES"
    
    log_subsection "Azure NSG Rules (via metadata)"
    # Try to get network info from Azure metadata
    echo "Attempting to retrieve network security information..."
    local azure_network
    azure_network=$(curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance/network?api-version=2021-02-01" 2>/dev/null)
    if [ -n "$azure_network" ]; then
        echo "$azure_network" | python3 -m json.tool 2>/dev/null || echo "$azure_network"
    else
        echo "Azure network metadata not available"
    fi
    
    log_subsection "OCI Security Lists (via metadata)"
    local oci_network
    oci_network=$(curl -s -H "Authorization: Bearer Oracle" -L "http://169.254.169.254/opc/v2/vnics/" 2>/dev/null)
    if [ -n "$oci_network" ]; then
        echo "$oci_network" | python3 -m json.tool 2>/dev/null || echo "$oci_network"
    else
        echo "OCI network metadata not available"
    fi
    
    log_subsection "Firewall Rules (OS Level)"
    echo "iptables rules:"
    sudo iptables -L -n 2>/dev/null | head -30 || echo "Unable to retrieve iptables rules"
    echo ""
    echo "firewalld zones:"
    sudo firewall-cmd --list-all 2>/dev/null || echo "firewalld not available or not running"
    
    log_subsection "Listening Ports"
    ss -tlnp 2>/dev/null | head -30 || netstat -tlnp 2>/dev/null | head -30 || echo "Unable to list listening ports"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║       ZDM TARGET DATABASE DISCOVERY - PRODDB MIGRATION                    ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Timestamp: $(date)"
    echo "Output File: $OUTPUT_FILE"
    echo "JSON File: $JSON_FILE"
    echo ""
    
    # Detect Oracle environment
    detect_oracle_env
    
    if [ -z "${ORACLE_HOME:-}" ]; then
        log_warn "ORACLE_HOME not detected. Some discovery steps will be skipped."
    else
        log_info "Using ORACLE_HOME: $ORACLE_HOME"
    fi
    
    if [ -n "${ORACLE_SID:-}" ]; then
        log_info "Using ORACLE_SID: $ORACLE_SID"
    fi
    
    log_info "Running SQL commands as user: $ORACLE_USER"
    echo ""
    
    # Initialize JSON output
    init_json
    add_json "oracle_home" "${ORACLE_HOME:-NOT_SET}"
    add_json "oracle_sid" "${ORACLE_SID:-NOT_SET}"
    
    # Run discovery (all output tee'd to both console and file)
    {
        echo "ZDM TARGET DATABASE DISCOVERY"
        echo "Project: PRODDB Migration to Oracle Database@Azure"
        echo "Target: proddb-oda.eastus.azure.example.com"
        echo "Timestamp: $(date)"
        echo "ORACLE_HOME: ${ORACLE_HOME:-NOT SET}"
        echo "ORACLE_SID: ${ORACLE_SID:-NOT SET}"
        
        # Standard discovery
        discover_os_info
        discover_oracle_env
        discover_database_config
        discover_storage
        discover_cdb_pdb
        discover_tde_config
        discover_network_config
        discover_oci_azure_integration
        discover_grid_infrastructure
        discover_ssh_config
        
        # Additional project-specific discovery
        discover_exadata_storage
        discover_preconfigured_pdbs
        discover_nsg_rules
        
        echo ""
        log_section "DISCOVERY COMPLETE"
        echo "Output saved to: $OUTPUT_FILE"
        echo "JSON saved to: $JSON_FILE"
        
    } 2>&1 | tee "$OUTPUT_FILE"
    
    # Get key values for JSON
    local db_name db_unique_name cdb_status tde_status
    db_name=$(run_sql_value "SELECT name FROM v\$database;" 2>/dev/null)
    db_unique_name=$(run_sql_value "SELECT db_unique_name FROM v\$database;" 2>/dev/null)
    cdb_status=$(run_sql_value "SELECT cdb FROM v\$database;" 2>/dev/null)
    tde_status=$(run_sql_value "SELECT status FROM v\$encryption_wallet WHERE ROWNUM = 1;" 2>/dev/null)
    
    add_json "db_name" "${db_name:-UNKNOWN}"
    add_json "db_unique_name" "${db_unique_name:-UNKNOWN}"
    add_json "cdb_enabled" "${cdb_status:-UNKNOWN}"
    add_json "tde_status" "${tde_status:-NOT_CONFIGURED}"
    add_json "discovery_status" "COMPLETED" "true"
    finalize_json
    
    echo ""
    log_info "Discovery completed successfully!"
    echo ""
}

# Run main function
main "$@"
