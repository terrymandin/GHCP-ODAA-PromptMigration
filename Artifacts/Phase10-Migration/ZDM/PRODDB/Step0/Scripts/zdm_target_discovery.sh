#!/bin/bash
#===============================================================================
# ZDM Target Database Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
#
# Purpose: Discover target Oracle Database@Azure configuration for ZDM migration.
#          Executed via SSH as admin user, SQL commands run as oracle user.
#
# Usage: ./zdm_target_discovery.sh
#
# Output:
#   - zdm_target_discovery_<hostname>_<timestamp>.txt (human-readable report)
#   - zdm_target_discovery_<hostname>_<timestamp>.json (machine-parseable)
#===============================================================================

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

# Output files (current working directory)
TEXT_REPORT="./zdm_target_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
JSON_REPORT="./zdm_target_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

# Default oracle user if not set
ORACLE_USER="${ORACLE_USER:-oracle}"

#===============================================================================
# ENVIRONMENT DETECTION
#===============================================================================

detect_oracle_env() {
    # If already set, use existing values
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        return 0
    fi
    
    # Method 1: Parse /etc/oratab
    if [ -f /etc/oratab ]; then
        local oratab_entry
        if [ -n "${ORACLE_SID:-}" ]; then
            oratab_entry=$(grep "^${ORACLE_SID}:" /etc/oratab 2>/dev/null | head -1)
        else
            oratab_entry=$(grep -v '^#' /etc/oratab | grep -v '^$' | grep -v '^*' | head -1)
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
    
    # Method 3: Search common Oracle installation paths (Exadata/ODA)
    if [ -z "${ORACLE_HOME:-}" ]; then
        for path in /u01/app/oracle/product/*/dbhome_1 /u02/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1; do
            if [ -d "$path" ] && [ -f "$path/bin/sqlplus" ]; then
                export ORACLE_HOME="$path"
                break
            fi
        done
    fi
    
    # Set ORACLE_BASE if not set
    if [ -z "${ORACLE_BASE:-}" ] && [ -n "${ORACLE_HOME:-}" ]; then
        export ORACLE_BASE=$(dirname $(dirname "$ORACLE_HOME"))
    fi
}

# Apply explicit overrides if provided
[ -n "${ORACLE_HOME_OVERRIDE:-}" ] && export ORACLE_HOME="$ORACLE_HOME_OVERRIDE"
[ -n "${ORACLE_SID_OVERRIDE:-}" ] && export ORACLE_SID="$ORACLE_SID_OVERRIDE"

# Detect Oracle environment
detect_oracle_env

#===============================================================================
# SQL EXECUTION FUNCTIONS
#===============================================================================

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
SET TRIMSPOOL ON
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
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            echo "$sql_script" | ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd 2>/dev/null | tr -d '[:space:]'
        else
            echo "$sql_script" | sudo -u "$ORACLE_USER" ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd 2>/dev/null | tr -d '[:space:]'
        fi
    else
        echo "ERROR"
        return 1
    fi
}

#===============================================================================
# OUTPUT FUNCTIONS
#===============================================================================

print_header() {
    local title="$1"
    echo "" >> "$TEXT_REPORT"
    echo "===============================================================================" >> "$TEXT_REPORT"
    echo "  $title" >> "$TEXT_REPORT"
    echo "===============================================================================" >> "$TEXT_REPORT"
    echo -e "${BLUE}=== $title ===${NC}"
}

print_section() {
    local title="$1"
    echo "" >> "$TEXT_REPORT"
    echo "--- $title ---" >> "$TEXT_REPORT"
    echo -e "${GREEN}--- $title ---${NC}"
}

print_info() {
    local label="$1"
    local value="$2"
    printf "%-30s: %s\n" "$label" "$value" >> "$TEXT_REPORT"
    printf "${CYAN}%-30s${NC}: %s\n" "$label" "$value"
}

print_output() {
    local output="$1"
    echo "$output" >> "$TEXT_REPORT"
    echo "$output"
}

#===============================================================================
# JSON BUILDER
#===============================================================================

declare -A JSON_DATA

add_json() {
    local key="$1"
    local value="$2"
    JSON_DATA["$key"]="$value"
}

add_json_array() {
    local key="$1"
    shift
    local items=("$@")
    local json_array="["
    local first=true
    for item in "${items[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            json_array+=","
        fi
        json_array+="\"$item\""
    done
    json_array+="]"
    JSON_DATA["$key"]="$json_array"
}

write_json() {
    echo "{" > "$JSON_REPORT"
    local first=true
    for key in "${!JSON_DATA[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> "$JSON_REPORT"
        fi
        local value="${JSON_DATA[$key]}"
        if [[ "$value" =~ ^\[.*\]$ ]] || [[ "$value" =~ ^\{.*\}$ ]]; then
            printf '  "%s": %s' "$key" "$value" >> "$JSON_REPORT"
        else
            printf '  "%s": "%s"' "$key" "$value" >> "$JSON_REPORT"
        fi
    done
    echo "" >> "$JSON_REPORT"
    echo "}" >> "$JSON_REPORT"
}

#===============================================================================
# DISCOVERY FUNCTIONS
#===============================================================================

discover_os_info() {
    print_header "OS INFORMATION"
    
    local hostname_full=$(hostname -f 2>/dev/null || hostname)
    local hostname_short=$(hostname -s)
    local ip_addresses=$(hostname -I 2>/dev/null || ip addr show | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | tr '\n' ' ')
    local os_version=$(cat /etc/os-release 2>/dev/null | grep "PRETTY_NAME" | cut -d'"' -f2 || uname -a)
    local kernel_version=$(uname -r)
    
    print_info "Hostname (Full)" "$hostname_full"
    print_info "Hostname (Short)" "$hostname_short"
    print_info "IP Addresses" "$ip_addresses"
    print_info "OS Version" "$os_version"
    print_info "Kernel Version" "$kernel_version"
    
    add_json "hostname_full" "$hostname_full"
    add_json "hostname_short" "$hostname_short"
    add_json "ip_addresses" "$ip_addresses"
    add_json "os_version" "$os_version"
    add_json "kernel_version" "$kernel_version"
}

discover_oracle_env() {
    print_header "ORACLE ENVIRONMENT"
    
    print_info "ORACLE_HOME" "${ORACLE_HOME:-NOT SET}"
    print_info "ORACLE_SID" "${ORACLE_SID:-NOT SET}"
    print_info "ORACLE_BASE" "${ORACLE_BASE:-NOT SET}"
    
    add_json "oracle_home" "${ORACLE_HOME:-NOT SET}"
    add_json "oracle_sid" "${ORACLE_SID:-NOT SET}"
    add_json "oracle_base" "${ORACLE_BASE:-NOT SET}"
    
    if [ -n "${ORACLE_HOME:-}" ]; then
        local oracle_version=$($ORACLE_HOME/bin/sqlplus -v 2>/dev/null | grep -i "Release" | head -1)
        print_info "Oracle Version" "$oracle_version"
        add_json "oracle_version" "$oracle_version"
    fi
}

discover_database_config() {
    print_header "DATABASE CONFIGURATION"
    
    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        print_output "ERROR: Oracle environment not configured"
        return 1
    fi
    
    local db_name=$(run_sql_value "SELECT name FROM v\$database;")
    local db_unique_name=$(run_sql_value "SELECT db_unique_name FROM v\$database;")
    local db_role=$(run_sql_value "SELECT database_role FROM v\$database;")
    local open_mode=$(run_sql_value "SELECT open_mode FROM v\$database;")
    
    print_info "Database Name" "$db_name"
    print_info "DB Unique Name" "$db_unique_name"
    print_info "Database Role" "$db_role"
    print_info "Open Mode" "$open_mode"
    
    add_json "db_name" "$db_name"
    add_json "db_unique_name" "$db_unique_name"
    add_json "database_role" "$db_role"
    add_json "open_mode" "$open_mode"
    
    print_section "Character Set"
    local charset=$(run_sql_value "SELECT value FROM nls_database_parameters WHERE parameter = 'NLS_CHARACTERSET';")
    print_info "Character Set" "$charset"
    add_json "character_set" "$charset"
}

discover_cdb_pdb() {
    print_header "CONTAINER DATABASE (CDB/PDB)"
    
    local cdb_status=$(run_sql_value "SELECT CDB FROM v\$database;")
    print_info "CDB Status" "$cdb_status"
    add_json "is_cdb" "$cdb_status"
    
    if [ "$cdb_status" = "YES" ]; then
        print_section "PDB Information"
        run_sql "
SELECT con_id, name, open_mode, restricted, total_size/1024/1024/1024 as size_gb
FROM v\$pdbs
ORDER BY con_id;
" >> "$TEXT_REPORT"
        
        local pdb_list=$(run_sql_value "SELECT LISTAGG(name, ',') WITHIN GROUP (ORDER BY con_id) FROM v\$pdbs WHERE name != 'PDB\$SEED';")
        add_json "pdb_list" "$pdb_list"
    fi
}

discover_storage() {
    print_header "STORAGE CONFIGURATION"
    
    print_section "Tablespace Usage"
    run_sql "
SELECT tablespace_name,
       ROUND(SUM(bytes)/1024/1024/1024, 2) as used_gb,
       ROUND(SUM(maxbytes)/1024/1024/1024, 2) as max_gb
FROM dba_data_files
GROUP BY tablespace_name
ORDER BY tablespace_name;
" >> "$TEXT_REPORT"
    
    print_section "ASM Disk Groups (if applicable)"
    run_sql "
SELECT name, state, type, total_mb/1024 as total_gb, free_mb/1024 as free_gb,
       ROUND((total_mb - free_mb)/total_mb * 100, 2) as pct_used
FROM v\$asm_diskgroup;
" >> "$TEXT_REPORT" 2>/dev/null || print_output "ASM not configured or not accessible"
    
    local total_storage=$(run_sql_value "SELECT ROUND(SUM(maxbytes)/1024/1024/1024, 2) FROM dba_data_files;")
    add_json "total_storage_gb" "$total_storage"
}

discover_tde_config() {
    print_header "TDE CONFIGURATION"
    
    local tde_enabled=$(run_sql_value "SELECT COUNT(*) FROM v\$encryption_wallet WHERE status = 'OPEN';")
    
    if [ "$tde_enabled" -gt 0 ] 2>/dev/null; then
        print_info "TDE Status" "ENABLED"
        add_json "tde_enabled" "true"
        
        print_section "Wallet Information"
        run_sql "SELECT * FROM v\$encryption_wallet;" >> "$TEXT_REPORT"
        
        local wallet_type=$(run_sql_value "SELECT wallet_type FROM v\$encryption_wallet WHERE rownum = 1;")
        print_info "Wallet Type" "$wallet_type"
        add_json "wallet_type" "$wallet_type"
    else
        print_info "TDE Status" "NOT ENABLED"
        add_json "tde_enabled" "false"
    fi
}

discover_network_config() {
    print_header "NETWORK CONFIGURATION"
    
    print_section "Listener Status"
    if [ -n "${ORACLE_HOME:-}" ]; then
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            $ORACLE_HOME/bin/lsnrctl status 2>&1 >> "$TEXT_REPORT" || echo "Unable to get listener status" >> "$TEXT_REPORT"
        else
            sudo -u "$ORACLE_USER" ORACLE_HOME="$ORACLE_HOME" $ORACLE_HOME/bin/lsnrctl status 2>&1 >> "$TEXT_REPORT" || echo "Unable to get listener status" >> "$TEXT_REPORT"
        fi
    fi
    
    print_section "SCAN Listener (RAC)"
    if command -v srvctl >/dev/null 2>&1; then
        srvctl status scan_listener 2>&1 >> "$TEXT_REPORT" || echo "SCAN listener not configured or not accessible" >> "$TEXT_REPORT"
    else
        print_output "srvctl not available - may not be RAC"
    fi
    
    print_section "tnsnames.ora"
    local tns_file="$ORACLE_HOME/network/admin/tnsnames.ora"
    if [ -f "$tns_file" ]; then
        cat "$tns_file" >> "$TEXT_REPORT"
    else
        print_output "File not found: $tns_file"
    fi
}

discover_oci_azure_integration() {
    print_header "OCI/AZURE INTEGRATION"
    
    print_section "OCI CLI"
    if command -v oci >/dev/null 2>&1; then
        local oci_version=$(oci --version 2>&1)
        print_info "OCI CLI Version" "$oci_version"
        add_json "oci_cli_version" "$oci_version"
        
        print_section "OCI Config"
        if [ -f ~/.oci/config ]; then
            # Mask sensitive data
            grep -v 'key_file\|fingerprint\|pass_phrase' ~/.oci/config 2>/dev/null >> "$TEXT_REPORT"
            print_info "OCI Config" "EXISTS"
            add_json "oci_config_exists" "true"
        else
            print_info "OCI Config" "NOT FOUND"
            add_json "oci_config_exists" "false"
        fi
        
        print_section "OCI Connectivity Test"
        if oci iam region list --output table 2>&1 | head -10 >> "$TEXT_REPORT"; then
            print_info "OCI Connectivity" "SUCCESS"
            add_json "oci_connectivity" "success"
        else
            print_info "OCI Connectivity" "FAILED"
            add_json "oci_connectivity" "failed"
        fi
    else
        print_info "OCI CLI" "NOT INSTALLED"
        add_json "oci_cli_installed" "false"
    fi
    
    print_section "Instance Metadata"
    # OCI Instance Metadata
    if curl -s -m 5 http://169.254.169.254/opc/v1/instance/ >/dev/null 2>&1; then
        print_output "OCI Instance Metadata:"
        curl -s http://169.254.169.254/opc/v1/instance/ 2>/dev/null | head -20 >> "$TEXT_REPORT"
        add_json "cloud_provider" "OCI"
    fi
    
    # Azure Instance Metadata
    if curl -s -m 5 -H "Metadata:true" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" >/dev/null 2>&1; then
        print_output "Azure Instance Metadata:"
        curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" 2>/dev/null | head -20 >> "$TEXT_REPORT"
        add_json "cloud_provider" "Azure"
    fi
}

discover_grid_infrastructure() {
    print_header "GRID INFRASTRUCTURE (RAC)"
    
    if command -v crsctl >/dev/null 2>&1; then
        print_section "CRS Status"
        crsctl check crs 2>&1 >> "$TEXT_REPORT" || echo "Unable to check CRS status" >> "$TEXT_REPORT"
        
        print_section "Cluster Nodes"
        olsnodes -n 2>&1 >> "$TEXT_REPORT" || echo "Unable to list cluster nodes" >> "$TEXT_REPORT"
        
        add_json "is_rac" "true"
    else
        print_info "RAC Status" "NOT RAC or Grid Infrastructure not configured"
        add_json "is_rac" "false"
    fi
}

discover_authentication() {
    print_header "AUTHENTICATION"
    
    print_section "SSH Directory Contents"
    if [ -d ~/.ssh ]; then
        ls -la ~/.ssh 2>/dev/null >> "$TEXT_REPORT"
    else
        print_output "SSH directory not found"
    fi
}

discover_exadata_storage() {
    print_header "EXADATA STORAGE CAPACITY"
    
    print_section "Exadata Cell Information"
    if command -v cellcli >/dev/null 2>&1; then
        cellcli -e "list cell detail" 2>&1 >> "$TEXT_REPORT" || echo "Unable to get cell information" >> "$TEXT_REPORT"
        
        print_section "Grid Disk Status"
        cellcli -e "list griddisk" 2>&1 >> "$TEXT_REPORT" || echo "Unable to list grid disks" >> "$TEXT_REPORT"
        
        add_json "is_exadata" "true"
    else
        # Check ASM for storage capacity
        print_section "ASM Disk Group Capacity"
        run_sql "
SELECT name, 
       state,
       type,
       ROUND(total_mb/1024, 2) as total_gb,
       ROUND(free_mb/1024, 2) as free_gb,
       ROUND(usable_file_mb/1024, 2) as usable_gb
FROM v\$asm_diskgroup
ORDER BY name;
" >> "$TEXT_REPORT" 2>/dev/null || print_output "ASM information not available"
        
        add_json "is_exadata" "false"
    fi
    
    print_section "Available Storage Summary"
    local asm_free=$(run_sql_value "SELECT ROUND(SUM(free_mb)/1024, 2) FROM v\$asm_diskgroup;" 2>/dev/null)
    if [ -n "$asm_free" ] && [ "$asm_free" != "ERROR" ]; then
        print_info "Total ASM Free Space (GB)" "$asm_free"
        add_json "asm_free_space_gb" "$asm_free"
    fi
}

discover_preconfigured_pdbs() {
    print_header "PRE-CONFIGURED PDBs"
    
    run_sql "
SELECT p.con_id, 
       p.name as pdb_name, 
       p.open_mode,
       ROUND(p.total_size/1024/1024/1024, 2) as size_gb,
       p.creation_time,
       (SELECT COUNT(*) FROM cdb_users u WHERE u.con_id = p.con_id AND u.oracle_maintained = 'N') as user_count,
       (SELECT COUNT(*) FROM cdb_tables t WHERE t.con_id = p.con_id AND t.owner NOT IN ('SYS','SYSTEM')) as table_count
FROM v\$pdbs p
ORDER BY p.con_id;
" >> "$TEXT_REPORT"
    
    print_section "PDB Services"
    run_sql "
SELECT con_id, name as service_name, network_name
FROM v\$services
WHERE con_id > 0
ORDER BY con_id, name;
" >> "$TEXT_REPORT"
}

discover_network_security() {
    print_header "NETWORK SECURITY"
    
    print_section "Firewall Status"
    if command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --state 2>&1 >> "$TEXT_REPORT"
        firewall-cmd --list-all 2>&1 >> "$TEXT_REPORT"
    elif command -v iptables >/dev/null 2>&1; then
        iptables -L -n 2>&1 >> "$TEXT_REPORT"
    else
        print_output "Firewall status unavailable"
    fi
    
    print_section "Listening Ports"
    ss -tlnp 2>/dev/null | grep -E ':(1521|1522|1523|5500|5501)' >> "$TEXT_REPORT" || \
    netstat -tlnp 2>/dev/null | grep -E ':(1521|1522|1523|5500|5501)' >> "$TEXT_REPORT" || \
    print_output "Port information unavailable"
    
    print_section "Network Security Group Rules (if available)"
    # This would require Azure CLI or OCI CLI access
    if command -v az >/dev/null 2>&1; then
        print_output "Azure CLI available - NSG rules can be queried via Azure Portal or CLI"
    fi
    if command -v oci >/dev/null 2>&1; then
        print_output "OCI CLI available - Security List rules can be queried via OCI Console or CLI"
    fi
}

#===============================================================================
# MAIN EXECUTION
#===============================================================================

main() {
    echo "ZDM Target Database Discovery Script" > "$TEXT_REPORT"
    echo "Generated: $(date)" >> "$TEXT_REPORT"
    echo "Hostname: $(hostname)" >> "$TEXT_REPORT"
    echo "User: $(whoami)" >> "$TEXT_REPORT"
    
    add_json "discovery_type" "target"
    add_json "discovery_timestamp" "$(date -Iseconds)"
    add_json "discovered_by" "$(whoami)"
    
    echo -e "${CYAN}Starting Target Database Discovery...${NC}"
    echo -e "${CYAN}Output files will be created in current directory${NC}"
    
    # Run all discovery functions (continue on error)
    discover_os_info || echo "Warning: OS info discovery had errors"
    discover_oracle_env || echo "Warning: Oracle env discovery had errors"
    discover_database_config || echo "Warning: Database config discovery had errors"
    discover_cdb_pdb || echo "Warning: CDB/PDB discovery had errors"
    discover_storage || echo "Warning: Storage discovery had errors"
    discover_tde_config || echo "Warning: TDE discovery had errors"
    discover_network_config || echo "Warning: Network config discovery had errors"
    discover_oci_azure_integration || echo "Warning: OCI/Azure integration discovery had errors"
    discover_grid_infrastructure || echo "Warning: Grid Infrastructure discovery had errors"
    discover_authentication || echo "Warning: Authentication discovery had errors"
    
    # Additional discovery requirements
    discover_exadata_storage || echo "Warning: Exadata storage discovery had errors"
    discover_preconfigured_pdbs || echo "Warning: Pre-configured PDB discovery had errors"
    discover_network_security || echo "Warning: Network security discovery had errors"
    
    # Write JSON report
    write_json
    
    echo ""
    echo -e "${GREEN}===============================================================================${NC}"
    echo -e "${GREEN}Discovery Complete${NC}"
    echo -e "${GREEN}===============================================================================${NC}"
    echo -e "Text Report: ${CYAN}$TEXT_REPORT${NC}"
    echo -e "JSON Report: ${CYAN}$JSON_REPORT${NC}"
}

# Run main function
main "$@"
