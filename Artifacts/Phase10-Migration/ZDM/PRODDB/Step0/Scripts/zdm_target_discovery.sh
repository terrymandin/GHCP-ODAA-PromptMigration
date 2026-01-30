#!/bin/bash
#===============================================================================
# ZDM Target Database Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# Target Database: proddb-oda.eastus.azure.example.com
#
# Purpose: Gather discovery information from the target Oracle Database@Azure server
#
# Usage: ./zdm_target_discovery.sh
#
# Output:
#   - zdm_target_discovery_<hostname>_<timestamp>.txt (human-readable report)
#   - zdm_target_discovery_<hostname>_<timestamp>.json (machine-parseable JSON)
#===============================================================================

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script variables
SCRIPT_VERSION="1.0.0"
HOSTNAME=$(hostname -s 2>/dev/null || hostname)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="./zdm_target_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_target_discovery_${HOSTNAME}_${TIMESTAMP}.json"

# User configuration - can be overridden via environment
ORACLE_USER="${ORACLE_USER:-oracle}"

# Error tracking
SECTION_ERRORS=0
TOTAL_ERRORS=0

#===============================================================================
# Functions
#===============================================================================

print_header() {
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}============================================================${NC}"
}

print_section() {
    echo -e "\n${BLUE}------------------------------------------------------------${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}------------------------------------------------------------${NC}"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info() {
    echo -e "${NC}$1${NC}"
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
    
    # Method 3: Search common Oracle installation paths (ODA specific paths)
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

# Apply explicit overrides if provided (highest priority)
apply_overrides() {
    [ -n "${ORACLE_HOME_OVERRIDE:-}" ] && export ORACLE_HOME="$ORACLE_HOME_OVERRIDE"
    [ -n "${ORACLE_SID_OVERRIDE:-}" ] && export ORACLE_SID="$ORACLE_SID_OVERRIDE"
}

# Run SQL command and return output
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
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        local sqlplus_cmd="$ORACLE_HOME/bin/sqlplus -s / as sysdba"
        local sql_script=$(cat <<EOSQL
SET PAGESIZE 0
SET LINESIZE 200
SET FEEDBACK OFF
SET HEADING OFF
SET ECHO OFF
SET TRIMSPOOL ON
SET TRIMOUT ON
$sql_query
EOSQL
)
        # Execute as oracle user - use sudo if current user is not oracle
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

# Initialize JSON output
init_json() {
    cat > "$JSON_FILE" <<EOF
{
  "discovery_type": "target",
  "hostname": "$HOSTNAME",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "script_version": "$SCRIPT_VERSION",
EOF
}

# Close JSON output
close_json() {
    # Remove trailing comma and close JSON
    sed -i '$ s/,$//' "$JSON_FILE" 2>/dev/null || true
    echo "}" >> "$JSON_FILE"
}

# Add JSON section
add_json() {
    local key="$1"
    local value="$2"
    local is_object="${3:-false}"
    
    if [ "$is_object" = "true" ]; then
        echo "  \"$key\": $value," >> "$JSON_FILE"
    else
        # Escape special characters in value
        value=$(echo "$value" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' | tr '\n' ' ')
        echo "  \"$key\": \"$value\"," >> "$JSON_FILE"
    fi
}

#===============================================================================
# Discovery Sections
#===============================================================================

discover_os_info() {
    print_section "OS INFORMATION"
    
    echo "Hostname: $HOSTNAME"
    echo "IP Addresses:"
    ip addr show 2>/dev/null | grep 'inet ' | awk '{print "  " $2}' || hostname -I 2>/dev/null | tr ' ' '\n' | sed 's/^/  /'
    
    echo ""
    echo "Operating System:"
    if [ -f /etc/os-release ]; then
        cat /etc/os-release | grep -E "^(NAME|VERSION|ID)=" | sed 's/^/  /'
    elif [ -f /etc/redhat-release ]; then
        echo "  $(cat /etc/redhat-release)"
    fi
    
    echo ""
    echo "Kernel Version: $(uname -r)"
    
    # Add to JSON
    add_json "hostname" "$HOSTNAME"
    add_json "os_version" "$(cat /etc/os-release 2>/dev/null | grep '^VERSION=' | cut -d= -f2 | tr -d '\"')"
    add_json "kernel" "$(uname -r)"
}

discover_oracle_env() {
    print_section "ORACLE ENVIRONMENT"
    
    echo "ORACLE_HOME: ${ORACLE_HOME:-NOT SET}"
    echo "ORACLE_SID: ${ORACLE_SID:-NOT SET}"
    echo "ORACLE_BASE: ${ORACLE_BASE:-NOT SET}"
    
    if [ -n "${ORACLE_HOME:-}" ]; then
        echo ""
        echo "Oracle Version:"
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            $ORACLE_HOME/bin/sqlplus -v 2>/dev/null || echo "  Unable to determine version"
        else
            sudo -u "$ORACLE_USER" $ORACLE_HOME/bin/sqlplus -v 2>/dev/null || echo "  Unable to determine version"
        fi
        
        local ora_version
        ora_version=$(run_sql_value "SELECT banner FROM v\$version WHERE banner LIKE 'Oracle%' AND ROWNUM = 1;")
        echo "  $ora_version"
    fi
    
    echo ""
    echo "/etc/oratab contents:"
    if [ -f /etc/oratab ]; then
        grep -v '^#' /etc/oratab | grep -v '^$' | sed 's/^/  /'
    else
        echo "  /etc/oratab not found"
    fi
    
    add_json "oracle_home" "${ORACLE_HOME:-}"
    add_json "oracle_sid" "${ORACLE_SID:-}"
}

discover_database_config() {
    print_section "DATABASE CONFIGURATION"
    
    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        print_warning "ORACLE_HOME or ORACLE_SID not set - skipping database discovery"
        return 1
    fi
    
    echo "Database Name: $(run_sql_value "SELECT name FROM v\$database;")"
    echo "DB Unique Name: $(run_sql_value "SELECT db_unique_name FROM v\$database;")"
    echo "Database Role: $(run_sql_value "SELECT database_role FROM v\$database;")"
    echo "Open Mode: $(run_sql_value "SELECT open_mode FROM v\$database;")"
    
    echo ""
    echo "Character Set:"
    run_sql "SELECT parameter, value FROM nls_database_parameters WHERE parameter LIKE '%CHARACTERSET%';"
    
    # Add key values to JSON
    add_json "database_name" "$(run_sql_value "SELECT name FROM v\$database;")"
    add_json "db_unique_name" "$(run_sql_value "SELECT db_unique_name FROM v\$database;")"
}

discover_storage() {
    print_section "STORAGE CONFIGURATION"
    
    echo "Tablespace Usage:"
    run_sql "SELECT tablespace_name, 
       ROUND(SUM(bytes)/1024/1024/1024, 2) AS size_gb,
       ROUND(SUM(maxbytes)/1024/1024/1024, 2) AS max_size_gb
FROM dba_data_files 
GROUP BY tablespace_name 
ORDER BY size_gb DESC;"
    
    echo ""
    echo "ASM Disk Groups (if applicable):"
    run_sql "SELECT name, type, total_mb, free_mb, 
       ROUND(free_mb/total_mb*100, 2) AS pct_free,
       state
FROM v\$asm_diskgroup;" 2>/dev/null || echo "  ASM not configured or not accessible"
    
    echo ""
    echo "Disk Space:"
    df -h | grep -v tmpfs | head -20
}

discover_cdb_pdb() {
    print_section "CONTAINER DATABASE / PDB CONFIGURATION"
    
    local cdb_status
    cdb_status=$(run_sql_value "SELECT CDB FROM v\$database;")
    echo "CDB Status: $cdb_status"
    
    if [ "$cdb_status" = "YES" ]; then
        echo ""
        echo "PDB List:"
        run_sql "SELECT con_id, name, open_mode, restricted FROM v\$pdbs ORDER BY con_id;"
    fi
    
    add_json "is_cdb" "$cdb_status"
}

discover_tde() {
    print_section "TDE/WALLET CONFIGURATION"
    
    echo "TDE Wallet Status:"
    run_sql "SELECT wrl_type, wrl_parameter, status, wallet_type FROM v\$encryption_wallet;"
    
    echo ""
    echo "Encrypted Tablespaces:"
    run_sql "SELECT tablespace_name, encrypted FROM dba_tablespaces WHERE encrypted = 'YES';"
    
    local wallet_status
    wallet_status=$(run_sql_value "SELECT status FROM v\$encryption_wallet WHERE ROWNUM = 1;")
    add_json "tde_wallet_status" "$wallet_status"
}

discover_network() {
    print_section "NETWORK CONFIGURATION"
    
    echo "Listener Status:"
    if [ -n "${ORACLE_HOME:-}" ]; then
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            $ORACLE_HOME/bin/lsnrctl status 2>/dev/null | head -30 || echo "  Listener check failed"
        else
            sudo -u "$ORACLE_USER" $ORACLE_HOME/bin/lsnrctl status 2>/dev/null | head -30 || echo "  Listener check failed"
        fi
    fi
    
    echo ""
    echo "SCAN Listener (if RAC):"
    srvctl status scan_listener 2>/dev/null || echo "  SCAN listener not configured or srvctl not available"
    
    echo ""
    echo "tnsnames.ora:"
    if [ -f "$ORACLE_HOME/network/admin/tnsnames.ora" ]; then
        cat "$ORACLE_HOME/network/admin/tnsnames.ora" 2>/dev/null | head -50
    else
        echo "  tnsnames.ora not found"
    fi
}

discover_oci_azure() {
    print_section "OCI/AZURE INTEGRATION"
    
    echo "OCI CLI Version:"
    oci --version 2>/dev/null || echo "  OCI CLI not installed"
    
    echo ""
    echo "OCI Configuration:"
    if [ -f ~/.oci/config ]; then
        echo "  OCI config file exists at ~/.oci/config"
        echo "  Profiles:"
        grep '^\[' ~/.oci/config 2>/dev/null | sed 's/^/    /'
    else
        echo "  OCI config not found at ~/.oci/config"
    fi
    
    echo ""
    echo "OCI Connectivity Test:"
    oci iam region list --query 'data[0].name' --raw-output 2>/dev/null && echo "  OCI connectivity: OK" || echo "  OCI connectivity: FAILED or not configured"
    
    echo ""
    echo "Azure Instance Metadata (if available):"
    curl -s -H Metadata:true --max-time 5 "http://169.254.169.254/metadata/instance?api-version=2021-02-01" 2>/dev/null | head -20 || echo "  Azure metadata not available"
    
    echo ""
    echo "OCI Instance Metadata (if available):"
    curl -s -H "Authorization: Bearer Oracle" --max-time 5 "http://169.254.169.254/opc/v2/instance/" 2>/dev/null | head -20 || echo "  OCI metadata not available"
}

discover_grid() {
    print_section "GRID INFRASTRUCTURE (if RAC)"
    
    echo "CRS Status:"
    crsctl stat res -t 2>/dev/null | head -50 || echo "  CRS not installed or not accessible"
    
    echo ""
    echo "Cluster Nodes:"
    olsnodes 2>/dev/null || echo "  Not a RAC configuration or olsnodes not available"
}

discover_auth() {
    print_section "AUTHENTICATION"
    
    echo "SSH Directory (opc user):"
    if [ -d ~/.ssh ]; then
        ls -la ~/.ssh/ 2>/dev/null | head -10
    else
        echo "  ~/.ssh not found"
    fi
    
    echo ""
    echo "SSH Directory (oracle user):"
    if [ -d ~oracle/.ssh ]; then
        ls -la ~oracle/.ssh/ 2>/dev/null | head -10
    else
        echo "  ~oracle/.ssh not found"
    fi
}

# Additional discovery for PRODDB migration project
discover_exadata_storage() {
    print_section "EXADATA STORAGE CAPACITY"
    
    echo "Exadata Cell Disk Information:"
    run_sql "SELECT name, disk_type, total_mb, free_mb 
FROM v\$cell_disk_summary;" 2>/dev/null || echo "  Not Exadata or cell disks not accessible"
    
    echo ""
    echo "ASM Diskgroup Details:"
    run_sql "SELECT name, type, state, total_mb, free_mb, 
       ROUND((total_mb - free_mb)/total_mb * 100, 2) AS pct_used,
       required_mirror_free_mb, usable_file_mb
FROM v\$asm_diskgroup 
ORDER BY name;" 2>/dev/null || echo "  ASM not configured"
    
    echo ""
    echo "Disk Space Summary:"
    df -h | grep -E "^/dev|DATA|RECO|FRA" | head -20
}

discover_preconfigured_pdbs() {
    print_section "PRE-CONFIGURED PDBs"
    
    local cdb_status
    cdb_status=$(run_sql_value "SELECT CDB FROM v\$database;")
    
    if [ "$cdb_status" = "YES" ]; then
        echo "Available PDBs:"
        run_sql "SELECT con_id, name, open_mode, restricted, 
       creation_time, total_size/1024/1024/1024 AS size_gb
FROM v\$pdbs 
ORDER BY con_id;"
        
        echo ""
        echo "PDB Services:"
        run_sql "SELECT pdb, name, network_name, enabled 
FROM cdb_services 
WHERE pdb IS NOT NULL 
ORDER BY pdb, name;"
    else
        echo "Not a CDB - no PDBs available"
    fi
}

discover_network_security() {
    print_section "NETWORK SECURITY GROUP RULES"
    
    echo "Local Firewall Rules (firewalld):"
    firewall-cmd --list-all 2>/dev/null || echo "  firewalld not running or not accessible"
    
    echo ""
    echo "iptables Rules:"
    iptables -L -n 2>/dev/null | head -30 || echo "  iptables not accessible"
    
    echo ""
    echo "Listening Ports:"
    ss -tlnp 2>/dev/null | head -20 || netstat -tlnp 2>/dev/null | head -20
    
    echo ""
    echo "Network Security (from OCI metadata if available):"
    echo "Note: Full NSG rules should be checked via OCI Console or CLI"
    oci network nsg rules list --nsg-id "$(curl -s -H "Authorization: Bearer Oracle" http://169.254.169.254/opc/v2/vnics/ 2>/dev/null | grep -o '"nsgIds":\[[^]]*\]' | head -1)" 2>/dev/null | head -30 || echo "  OCI NSG rules not accessible from instance"
}

#===============================================================================
# Main Execution
#===============================================================================

main() {
    # Initialize environment
    detect_oracle_env
    apply_overrides
    
    # Start output file
    print_header "ZDM Target Database Discovery Report" | tee "$OUTPUT_FILE"
    echo "Generated: $(date)" | tee -a "$OUTPUT_FILE"
    echo "Hostname: $HOSTNAME" | tee -a "$OUTPUT_FILE"
    echo "Script Version: $SCRIPT_VERSION" | tee -a "$OUTPUT_FILE"
    echo "" | tee -a "$OUTPUT_FILE"
    
    # Initialize JSON
    init_json
    
    # Run discovery sections (continue on failure)
    {
        discover_os_info || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_oracle_env || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_database_config || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_storage || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_cdb_pdb || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_tde || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_network || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_oci_azure || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_grid || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_auth || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        
        # Additional discovery for PRODDB project
        discover_exadata_storage || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_preconfigured_pdbs || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_network_security || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    } 2>&1 | tee -a "$OUTPUT_FILE"
    
    # Add errors to JSON and close
    add_json "section_errors" "$SECTION_ERRORS"
    close_json
    
    # Summary
    echo "" | tee -a "$OUTPUT_FILE"
    print_header "DISCOVERY COMPLETE" | tee -a "$OUTPUT_FILE"
    echo "Text Report: $OUTPUT_FILE" | tee -a "$OUTPUT_FILE"
    echo "JSON Summary: $JSON_FILE" | tee -a "$OUTPUT_FILE"
    
    if [ $SECTION_ERRORS -gt 0 ]; then
        print_warning "$SECTION_ERRORS section(s) had errors" | tee -a "$OUTPUT_FILE"
    else
        print_success "All sections completed successfully" | tee -a "$OUTPUT_FILE"
    fi
}

# Run main function
main "$@"
