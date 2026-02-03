#!/bin/bash
#
# ZDM Target Database Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# Target: proddb-oda.eastus.azure.example.com
#
# Purpose: Gather comprehensive discovery information from the target Oracle Database@Azure
#          for Zero Downtime Migration (ZDM) planning
#
# Usage: bash zdm_target_discovery.sh
#
# Output: 
#   - zdm_target_discovery_<hostname>_<timestamp>.txt (human-readable report)
#   - zdm_target_discovery_<hostname>_<timestamp>.json (machine-parseable JSON)
#

# ===========================================
# CONFIGURATION
# ===========================================

# Default oracle user if not set
ORACLE_USER="${ORACLE_USER:-oracle}"

# Timestamp for output files
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname -s 2>/dev/null || hostname)

# Output files (in current working directory)
TEXT_OUTPUT="./zdm_target_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_OUTPUT="./zdm_target_discovery_${HOSTNAME}_${TIMESTAMP}.json"

# ===========================================
# COLOR OUTPUT FUNCTIONS
# ===========================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "\n${BLUE}========================================${NC}"; echo -e "${BLUE}$1${NC}"; echo -e "${BLUE}========================================${NC}"; }

# ===========================================
# OUTPUT FUNCTIONS
# ===========================================

init_output() {
    echo "ZDM Target Database Discovery Report" > "$TEXT_OUTPUT"
    echo "Generated: $(date)" >> "$TEXT_OUTPUT"
    echo "Hostname: $HOSTNAME" >> "$TEXT_OUTPUT"
    echo "Project: PRODDB Migration to Oracle Database@Azure" >> "$TEXT_OUTPUT"
    echo "========================================" >> "$TEXT_OUTPUT"
    
    # Initialize JSON
    echo "{" > "$JSON_OUTPUT"
    echo "  \"report_type\": \"target_discovery\"," >> "$JSON_OUTPUT"
    echo "  \"generated\": \"$(date -Iseconds 2>/dev/null || date)\"," >> "$JSON_OUTPUT"
    echo "  \"hostname\": \"$HOSTNAME\"," >> "$JSON_OUTPUT"
    echo "  \"project\": \"PRODDB Migration to Oracle Database@Azure\"," >> "$JSON_OUTPUT"
}

write_section() {
    local section_name="$1"
    echo "" >> "$TEXT_OUTPUT"
    echo "========================================" >> "$TEXT_OUTPUT"
    echo "$section_name" >> "$TEXT_OUTPUT"
    echo "========================================" >> "$TEXT_OUTPUT"
}

write_text() {
    echo "$1" >> "$TEXT_OUTPUT"
}

write_json_field() {
    local field_name="$1"
    local field_value="$2"
    local is_last="${3:-false}"
    
    # Escape special characters in JSON
    field_value=$(echo "$field_value" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' ' ')
    
    if [ "$is_last" = "true" ]; then
        echo "  \"$field_name\": \"$field_value\"" >> "$JSON_OUTPUT"
    else
        echo "  \"$field_name\": \"$field_value\"," >> "$JSON_OUTPUT"
    fi
}

finalize_json() {
    echo "}" >> "$JSON_OUTPUT"
}

# ===========================================
# ORACLE ENVIRONMENT DETECTION
# ===========================================

detect_oracle_env() {
    log_info "Detecting Oracle environment..."
    
    # If already set, use existing values
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        log_info "Using pre-set ORACLE_HOME=$ORACLE_HOME, ORACLE_SID=$ORACLE_SID"
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
            log_info "Detected from /etc/oratab: ORACLE_SID=$ORACLE_SID, ORACLE_HOME=$ORACLE_HOME"
        fi
    fi
    
    # Method 2: Check running pmon process
    if [ -z "${ORACLE_SID:-}" ]; then
        local pmon_sid
        pmon_sid=$(ps -ef | grep 'ora_pmon_' | grep -v grep | head -1 | sed 's/.*ora_pmon_//')
        if [ -n "$pmon_sid" ]; then
            export ORACLE_SID="$pmon_sid"
            log_info "Detected ORACLE_SID from pmon: $ORACLE_SID"
        fi
    fi
    
    # Method 3: Search common Oracle installation paths (Exadata specific)
    if [ -z "${ORACLE_HOME:-}" ]; then
        for path in /u02/app/oracle/product/*/dbhome_1 /u01/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1; do
            if [ -d "$path" ] && [ -f "$path/bin/sqlplus" ]; then
                export ORACLE_HOME="$path"
                log_info "Detected ORACLE_HOME from common path: $ORACLE_HOME"
                break
            fi
        done
    fi
    
    # Apply overrides if provided
    [ -n "${ORACLE_HOME_OVERRIDE:-}" ] && export ORACLE_HOME="$ORACLE_HOME_OVERRIDE"
    [ -n "${ORACLE_SID_OVERRIDE:-}" ] && export ORACLE_SID="$ORACLE_SID_OVERRIDE"
    
    # Detect ORACLE_BASE
    if [ -z "${ORACLE_BASE:-}" ] && [ -n "${ORACLE_HOME:-}" ]; then
        export ORACLE_BASE=$(echo "$ORACLE_HOME" | sed 's|/product/.*||')
    fi
}

# ===========================================
# SQL EXECUTION FUNCTIONS
# ===========================================

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
    run_sql "$sql_query" | grep -v "^$" | tail -1 | xargs
}

# ===========================================
# DISCOVERY FUNCTIONS
# ===========================================

discover_os_info() {
    log_section "OS Information"
    write_section "OS Information"
    
    # Hostname
    local hostname_full=$(hostname -f 2>/dev/null || hostname)
    write_text "Hostname: $hostname_full"
    write_json_field "hostname_full" "$hostname_full"
    
    # IP Addresses
    local ip_addresses=$(ip addr show 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | tr '\n' ',' | sed 's/,$//')
    if [ -z "$ip_addresses" ]; then
        ip_addresses=$(ifconfig 2>/dev/null | grep 'inet ' | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')
    fi
    write_text "IP Addresses: $ip_addresses"
    write_json_field "ip_addresses" "$ip_addresses"
    
    # OS Version
    local os_version=""
    if [ -f /etc/os-release ]; then
        os_version=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
    elif [ -f /etc/redhat-release ]; then
        os_version=$(cat /etc/redhat-release)
    else
        os_version=$(uname -a)
    fi
    write_text "OS Version: $os_version"
    write_json_field "os_version" "$os_version"
    
    log_info "OS information collected"
}

discover_oracle_environment() {
    log_section "Oracle Environment"
    write_section "Oracle Environment"
    
    write_text "ORACLE_HOME: ${ORACLE_HOME:-NOT SET}"
    write_text "ORACLE_SID: ${ORACLE_SID:-NOT SET}"
    write_text "ORACLE_BASE: ${ORACLE_BASE:-NOT SET}"
    
    write_json_field "oracle_home" "${ORACLE_HOME:-}"
    write_json_field "oracle_sid" "${ORACLE_SID:-}"
    write_json_field "oracle_base" "${ORACLE_BASE:-}"
    
    # Oracle Version
    if [ -n "${ORACLE_HOME:-}" ] && [ -f "$ORACLE_HOME/bin/sqlplus" ]; then
        local oracle_version=$(run_sql_value "SELECT banner FROM v\$version WHERE ROWNUM = 1;")
        write_text "Oracle Version: $oracle_version"
        write_json_field "oracle_version" "$oracle_version"
    fi
    
    log_info "Oracle environment collected"
}

discover_database_config() {
    log_section "Database Configuration"
    write_section "Database Configuration"
    
    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        log_error "Oracle environment not set - skipping database configuration"
        write_text "ERROR: Oracle environment not set"
        return 1
    fi
    
    # Database name
    local db_name=$(run_sql_value "SELECT name FROM v\$database;")
    local db_unique_name=$(run_sql_value "SELECT db_unique_name FROM v\$database;")
    
    write_text "Database Name: $db_name"
    write_text "DB Unique Name: $db_unique_name"
    
    write_json_field "db_name" "$db_name"
    write_json_field "db_unique_name" "$db_unique_name"
    
    # Database role and mode
    local db_role=$(run_sql_value "SELECT database_role FROM v\$database;")
    local open_mode=$(run_sql_value "SELECT open_mode FROM v\$database;")
    
    write_text "Database Role: $db_role"
    write_text "Open Mode: $open_mode"
    
    write_json_field "database_role" "$db_role"
    write_json_field "open_mode" "$open_mode"
    
    # Character set
    local character_set=$(run_sql_value "SELECT value FROM nls_database_parameters WHERE parameter = 'NLS_CHARACTERSET';")
    write_text "Character Set: $character_set"
    write_json_field "character_set" "$character_set"
    
    log_info "Database configuration collected"
}

discover_storage() {
    log_section "Storage Configuration"
    write_section "Storage Configuration"
    
    # Tablespace information
    write_text "Tablespace Space Usage:"
    run_sql "
SELECT tablespace_name, 
       ROUND(SUM(bytes)/1024/1024/1024, 2) AS used_gb,
       ROUND(SUM(maxbytes)/1024/1024/1024, 2) AS max_gb,
       COUNT(*) AS file_count
FROM dba_data_files
GROUP BY tablespace_name
ORDER BY tablespace_name;
" >> "$TEXT_OUTPUT"
    
    # ASM diskgroups (if applicable)
    write_text ""
    write_text "ASM Disk Groups:"
    run_sql "
SELECT name, state, type, 
       ROUND(total_mb/1024, 2) AS total_gb, 
       ROUND(free_mb/1024, 2) AS free_gb,
       ROUND((total_mb - free_mb)/total_mb * 100, 2) AS pct_used
FROM v\$asm_diskgroup;
" >> "$TEXT_OUTPUT" 2>/dev/null || write_text "ASM not available or not accessible"
    
    local total_storage=$(run_sql_value "SELECT ROUND(SUM(bytes)/1024/1024/1024, 2) FROM dba_data_files;")
    write_json_field "total_data_storage_gb" "$total_storage"
    
    log_info "Storage configuration collected"
}

discover_cdb_pdbs() {
    log_section "Container Database / PDBs"
    write_section "Container Database / PDBs"
    
    # CDB Status
    local cdb_status=$(run_sql_value "SELECT CDB FROM v\$database;")
    write_text "Is CDB: $cdb_status"
    write_json_field "is_cdb" "$cdb_status"
    
    if [ "$cdb_status" = "YES" ]; then
        write_text ""
        write_text "PDBs:"
        run_sql "
SELECT pdb_name, status, open_mode, con_id,
       ROUND(total_size/1024/1024/1024, 2) AS size_gb
FROM cdb_pdbs p
LEFT JOIN (SELECT con_id, SUM(bytes) as total_size FROM cdb_data_files GROUP BY con_id) d
ON p.con_id = d.con_id
ORDER BY p.con_id;
" >> "$TEXT_OUTPUT"
        
        local pdb_list=$(run_sql_value "SELECT LISTAGG(pdb_name, ',') WITHIN GROUP (ORDER BY con_id) FROM cdb_pdbs;")
        write_json_field "pdb_list" "$pdb_list"
        
        local pdb_count=$(run_sql_value "SELECT COUNT(*) FROM cdb_pdbs;")
        write_json_field "pdb_count" "$pdb_count"
    fi
    
    log_info "CDB/PDB information collected"
}

discover_tde_config() {
    log_section "TDE/Wallet Configuration"
    write_section "TDE/Wallet Configuration"
    
    # Encryption wallet status
    write_text "Encryption Wallet Status:"
    run_sql "SELECT * FROM v\$encryption_wallet;" >> "$TEXT_OUTPUT" 2>/dev/null || write_text "Unable to query v\$encryption_wallet"
    
    local wallet_status=$(run_sql_value "SELECT status FROM v\$encryption_wallet WHERE ROWNUM = 1;")
    write_json_field "wallet_status" "$wallet_status"
    
    log_info "TDE configuration collected"
}

discover_network_config() {
    log_section "Network Configuration"
    write_section "Network Configuration"
    
    # Listener status
    write_text "Listener Status:"
    if [ -n "${ORACLE_HOME:-}" ]; then
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            $ORACLE_HOME/bin/lsnrctl status 2>/dev/null >> "$TEXT_OUTPUT" || write_text "Unable to get listener status"
        else
            sudo -u "$ORACLE_USER" ORACLE_HOME="$ORACLE_HOME" $ORACLE_HOME/bin/lsnrctl status 2>/dev/null >> "$TEXT_OUTPUT" || write_text "Unable to get listener status"
        fi
    fi
    
    # SCAN listener (for RAC)
    write_text ""
    write_text "SCAN Listener (if RAC):"
    if [ -n "${ORACLE_HOME:-}" ]; then
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            $ORACLE_HOME/bin/srvctl status scan_listener 2>/dev/null >> "$TEXT_OUTPUT" || write_text "SCAN listener not configured or not accessible"
        else
            sudo -u "$ORACLE_USER" ORACLE_HOME="$ORACLE_HOME" $ORACLE_HOME/bin/srvctl status scan_listener 2>/dev/null >> "$TEXT_OUTPUT" || write_text "SCAN listener not configured or not accessible"
        fi
    fi
    
    # tnsnames.ora
    write_text ""
    write_text "tnsnames.ora contents:"
    if [ -f "$ORACLE_HOME/network/admin/tnsnames.ora" ]; then
        cat "$ORACLE_HOME/network/admin/tnsnames.ora" >> "$TEXT_OUTPUT" 2>/dev/null
    else
        write_text "File not found: $ORACLE_HOME/network/admin/tnsnames.ora"
    fi
    
    log_info "Network configuration collected"
}

discover_oci_azure_integration() {
    log_section "OCI/Azure Integration"
    write_section "OCI/Azure Integration"
    
    # OCI CLI version
    write_text "OCI CLI Version:"
    if command -v oci &>/dev/null; then
        oci --version 2>&1 >> "$TEXT_OUTPUT"
        local oci_version=$(oci --version 2>&1)
        write_json_field "oci_cli_version" "$oci_version"
    else
        write_text "OCI CLI not installed"
        write_json_field "oci_cli_version" "NOT_INSTALLED"
    fi
    
    # OCI config
    write_text ""
    write_text "OCI Config File Location:"
    if [ -f ~/.oci/config ]; then
        write_text "~/.oci/config exists"
        write_text ""
        write_text "OCI Profiles (sensitive data masked):"
        grep -E '^\[|^region|^tenancy' ~/.oci/config 2>/dev/null >> "$TEXT_OUTPUT" || write_text "Unable to read OCI config"
    else
        write_text "OCI config file not found at ~/.oci/config"
    fi
    
    # OCI connectivity test
    write_text ""
    write_text "OCI Connectivity Test:"
    if command -v oci &>/dev/null; then
        if oci iam region list --output table 2>/dev/null | head -10 >> "$TEXT_OUTPUT"; then
            write_text "OCI connectivity: SUCCESS"
            write_json_field "oci_connectivity" "SUCCESS"
        else
            write_text "OCI connectivity: FAILED"
            write_json_field "oci_connectivity" "FAILED"
        fi
    fi
    
    # Instance metadata (OCI)
    write_text ""
    write_text "OCI Instance Metadata:"
    if curl -s -m 5 http://169.254.169.254/opc/v1/instance/ 2>/dev/null | head -20 >> "$TEXT_OUTPUT"; then
        write_text "(OCI metadata retrieved)"
    else
        write_text "Unable to retrieve OCI instance metadata (may not be running on OCI)"
    fi
    
    # Azure metadata (for hybrid environments)
    write_text ""
    write_text "Azure Instance Metadata:"
    if curl -s -m 5 -H "Metadata:true" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" 2>/dev/null | head -20 >> "$TEXT_OUTPUT"; then
        write_text "(Azure metadata retrieved)"
    else
        write_text "Unable to retrieve Azure instance metadata"
    fi
    
    log_info "OCI/Azure integration collected"
}

discover_grid_infrastructure() {
    log_section "Grid Infrastructure / RAC"
    write_section "Grid Infrastructure / RAC"
    
    # Check if Grid Infrastructure is installed
    local grid_home=""
    if [ -f /etc/oracle/olr.loc ]; then
        grid_home=$(grep crs_home /etc/oracle/olr.loc 2>/dev/null | cut -d= -f2)
    fi
    
    if [ -n "$grid_home" ] && [ -d "$grid_home" ]; then
        write_text "Grid Home: $grid_home"
        write_json_field "grid_home" "$grid_home"
        
        # CRS status
        write_text ""
        write_text "CRS Status:"
        if [ "$(whoami)" = "root" ]; then
            $grid_home/bin/crsctl stat res -t 2>/dev/null >> "$TEXT_OUTPUT" || write_text "Unable to get CRS status"
        else
            sudo $grid_home/bin/crsctl stat res -t 2>/dev/null >> "$TEXT_OUTPUT" || write_text "Unable to get CRS status"
        fi
        
        # Cluster nodes
        write_text ""
        write_text "Cluster Nodes:"
        if [ "$(whoami)" = "root" ]; then
            $grid_home/bin/olsnodes -n 2>/dev/null >> "$TEXT_OUTPUT" || write_text "Unable to get cluster nodes"
        else
            sudo $grid_home/bin/olsnodes -n 2>/dev/null >> "$TEXT_OUTPUT" || write_text "Unable to get cluster nodes"
        fi
    else
        write_text "Grid Infrastructure not detected (single instance)"
        write_json_field "grid_home" "NOT_CONFIGURED"
    fi
    
    log_info "Grid infrastructure collected"
}

discover_ssh_config() {
    log_section "SSH Configuration"
    write_section "SSH Configuration"
    
    # SSH directory contents for current user
    write_text "SSH Directory Contents (current user):"
    if [ -d ~/.ssh ]; then
        ls -la ~/.ssh 2>/dev/null >> "$TEXT_OUTPUT" || write_text "Unable to list SSH directory"
    else
        write_text "SSH directory not found for current user"
    fi
    
    # SSH directory for oracle user
    write_text ""
    write_text "SSH Directory Contents (oracle user):"
    local oracle_home_dir=$(eval echo ~$ORACLE_USER 2>/dev/null)
    if [ -d "$oracle_home_dir/.ssh" ]; then
        ls -la "$oracle_home_dir/.ssh" 2>/dev/null >> "$TEXT_OUTPUT" || write_text "Unable to list oracle SSH directory"
    else
        write_text "SSH directory not found for oracle user"
    fi
    
    log_info "SSH configuration collected"
}

# ===========================================
# ADDITIONAL DISCOVERY (PRODDB Specific)
# ===========================================

discover_exadata_storage() {
    log_section "Exadata Storage Capacity"
    write_section "Exadata Storage Capacity"
    
    # Exadata cell information
    write_text "Exadata Cell Information:"
    run_sql "
SELECT cell_name, cell_version, status 
FROM v\$cell 
ORDER BY cell_name;
" >> "$TEXT_OUTPUT" 2>/dev/null || write_text "Not running on Exadata or v\$cell not accessible"
    
    # Exadata diskgroup details
    write_text ""
    write_text "Exadata Disk Groups (Detailed):"
    run_sql "
SELECT name, state, type,
       ROUND(total_mb/1024, 2) AS total_gb,
       ROUND(free_mb/1024, 2) AS free_gb,
       ROUND(usable_file_mb/1024, 2) AS usable_gb,
       ROUND((1 - free_mb/total_mb) * 100, 2) AS pct_used
FROM v\$asm_diskgroup
ORDER BY name;
" >> "$TEXT_OUTPUT" 2>/dev/null || write_text "ASM disk groups not accessible"
    
    # Exadata storage summary
    write_text ""
    write_text "Exadata Storage Summary:"
    run_sql "
SELECT 
    ROUND(SUM(total_mb)/1024, 2) AS total_storage_gb,
    ROUND(SUM(free_mb)/1024, 2) AS free_storage_gb,
    ROUND(SUM(usable_file_mb)/1024, 2) AS usable_storage_gb
FROM v\$asm_diskgroup;
" >> "$TEXT_OUTPUT" 2>/dev/null
    
    local total_exadata_storage=$(run_sql_value "SELECT ROUND(SUM(total_mb)/1024, 2) FROM v\$asm_diskgroup;" 2>/dev/null)
    local free_exadata_storage=$(run_sql_value "SELECT ROUND(SUM(free_mb)/1024, 2) FROM v\$asm_diskgroup;" 2>/dev/null)
    
    write_json_field "exadata_total_storage_gb" "${total_exadata_storage:-N/A}"
    write_json_field "exadata_free_storage_gb" "${free_exadata_storage:-N/A}"
    
    log_info "Exadata storage capacity collected"
}

discover_preconfigured_pdbs() {
    log_section "Pre-configured PDBs"
    write_section "Pre-configured PDBs"
    
    # Detailed PDB information
    write_text "PDB Details:"
    run_sql "
SELECT p.pdb_name, p.status, p.open_mode, p.con_id,
       TO_CHAR(p.creation_time, 'YYYY-MM-DD HH24:MI:SS') AS created,
       ROUND(d.total_size/1024/1024/1024, 2) AS size_gb,
       ROUND(t.total_temp/1024/1024/1024, 2) AS temp_gb
FROM cdb_pdbs p
LEFT JOIN (SELECT con_id, SUM(bytes) AS total_size FROM cdb_data_files GROUP BY con_id) d ON p.con_id = d.con_id
LEFT JOIN (SELECT con_id, SUM(bytes) AS total_temp FROM cdb_temp_files GROUP BY con_id) t ON p.con_id = t.con_id
ORDER BY p.con_id;
" >> "$TEXT_OUTPUT"
    
    # PDB services
    write_text ""
    write_text "PDB Services:"
    run_sql "
SELECT pdb, name AS service_name, network_name, enabled, 
       failover_method, failover_type
FROM cdb_services
WHERE pdb IS NOT NULL
ORDER BY pdb, name;
" >> "$TEXT_OUTPUT" 2>/dev/null || write_text "Unable to query PDB services"
    
    # PDB resource limits
    write_text ""
    write_text "PDB Resource Limits:"
    run_sql "
SELECT pdb_name, 
       max_cpu, max_memory_percent, max_iops, max_mbps
FROM dba_pdbs p
LEFT JOIN cdb_cdb_rsrc_plan_directives d ON p.pdb_id = d.pluggable_database
ORDER BY pdb_name;
" >> "$TEXT_OUTPUT" 2>/dev/null || write_text "Unable to query PDB resource limits"
    
    log_info "Pre-configured PDBs collected"
}

discover_nsg_rules() {
    log_section "Network Security Group Rules"
    write_section "Network Security Group Rules"
    
    # Note: NSG rules are typically managed at the Azure/OCI level, not inside the VM
    # We can check what ports are open and listening
    
    write_text "Listening Ports (relevant to Oracle):"
    ss -tlnp 2>/dev/null | grep -E ':(22|1521|1522|1523|5500|5501)' >> "$TEXT_OUTPUT" || \
    netstat -tlnp 2>/dev/null | grep -E ':(22|1521|1522|1523|5500|5501)' >> "$TEXT_OUTPUT" || \
    write_text "Unable to list listening ports"
    
    # Firewall rules (if firewalld is running)
    write_text ""
    write_text "Firewall Rules (if applicable):"
    if command -v firewall-cmd &>/dev/null; then
        write_text "Firewalld zones and services:"
        firewall-cmd --list-all 2>/dev/null >> "$TEXT_OUTPUT" || write_text "Unable to query firewalld"
    elif command -v iptables &>/dev/null; then
        write_text "IPTables rules (relevant ports):"
        iptables -L -n 2>/dev/null | grep -E '22|1521|1522' >> "$TEXT_OUTPUT" || write_text "Unable to query iptables"
    else
        write_text "No local firewall detected"
    fi
    
    # Check for OCI Security Lists (via metadata or CLI)
    write_text ""
    write_text "OCI/Azure Network Configuration Note:"
    write_text "NSG rules are managed at the cloud infrastructure level."
    write_text "Use OCI Console or Azure Portal to review actual NSG rules."
    write_text "Ensure the following ports are open:"
    write_text "  - SSH (22)"
    write_text "  - Oracle Listener (1521)"
    write_text "  - Oracle EM (5500)"
    
    log_info "Network security information collected"
}

# ===========================================
# MAIN EXECUTION
# ===========================================

main() {
    log_info "Starting ZDM Target Database Discovery"
    log_info "Output will be saved to:"
    log_info "  Text: $TEXT_OUTPUT"
    log_info "  JSON: $JSON_OUTPUT"
    
    # Initialize output files
    init_output
    
    # Detect Oracle environment
    detect_oracle_env
    
    # Standard discovery sections
    discover_os_info || log_warn "OS information discovery failed - continuing"
    discover_oracle_environment || log_warn "Oracle environment discovery failed - continuing"
    discover_database_config || log_warn "Database configuration discovery failed - continuing"
    discover_storage || log_warn "Storage discovery failed - continuing"
    discover_cdb_pdbs || log_warn "CDB/PDB discovery failed - continuing"
    discover_tde_config || log_warn "TDE configuration discovery failed - continuing"
    discover_network_config || log_warn "Network configuration discovery failed - continuing"
    discover_oci_azure_integration || log_warn "OCI/Azure integration discovery failed - continuing"
    discover_grid_infrastructure || log_warn "Grid infrastructure discovery failed - continuing"
    discover_ssh_config || log_warn "SSH configuration discovery failed - continuing"
    
    # Additional PRODDB-specific discovery
    discover_exadata_storage || log_warn "Exadata storage discovery failed - continuing"
    discover_preconfigured_pdbs || log_warn "Pre-configured PDBs discovery failed - continuing"
    discover_nsg_rules || log_warn "NSG rules discovery failed - continuing"
    
    # Finalize JSON output
    write_json_field "discovery_completed" "$(date -Iseconds 2>/dev/null || date)" "true"
    finalize_json
    
    log_info ""
    log_info "=========================================="
    log_info "Discovery Complete!"
    log_info "=========================================="
    log_info "Text Report: $TEXT_OUTPUT"
    log_info "JSON Summary: $JSON_OUTPUT"
}

# Run main function
main "$@"
