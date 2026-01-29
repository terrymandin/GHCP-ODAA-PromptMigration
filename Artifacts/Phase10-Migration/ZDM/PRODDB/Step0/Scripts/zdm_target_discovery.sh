#!/bin/bash
################################################################################
# ZDM Target Database Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# Target Server: proddb-oda.eastus.azure.example.com
# Generated: 2026-01-29
#
# Purpose: Discovers comprehensive information about the target Oracle 
#          Database@Azure environment for ZDM migration planning.
#
# Usage: Run as opc or oracle user on the target Oracle Database@Azure server
#        ./zdm_target_discovery.sh
#
# Output: Text report and JSON summary in current working directory
################################################################################

# NO set -e - We want to continue even if some checks fail
SECTION_ERRORS=0
SCRIPT_VERSION="1.0.0"

# Source environment for ORACLE_HOME, ORACLE_SID, etc.
for profile in ~/.bash_profile ~/.bashrc /etc/profile ~/.profile /etc/profile.d/*.sh; do
    [ -f "$profile" ] && source "$profile" 2>/dev/null || true
done

# Initialize variables
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname -s 2>/dev/null || hostname)
OUTPUT_FILE="./zdm_target_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_target_discovery_${HOSTNAME}_${TIMESTAMP}.json"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Helper Functions
################################################################################

log_section() {
    local section_name="$1"
    echo ""
    echo "================================================================================" | tee -a "$OUTPUT_FILE"
    echo "= $section_name" | tee -a "$OUTPUT_FILE"
    echo "================================================================================" | tee -a "$OUTPUT_FILE"
    echo -e "${BLUE}[INFO]${NC} Discovering: $section_name"
}

log_subsection() {
    local subsection_name="$1"
    echo "" | tee -a "$OUTPUT_FILE"
    echo "--- $subsection_name ---" | tee -a "$OUTPUT_FILE"
}

log_info() {
    echo "$1" | tee -a "$OUTPUT_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$OUTPUT_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$OUTPUT_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

run_sql() {
    local sql="$1"
    if [ -n "$ORACLE_HOME" ] && [ -n "$ORACLE_SID" ]; then
        $ORACLE_HOME/bin/sqlplus -s / as sysdba <<EOF 2>&1
SET LINESIZE 200
SET PAGESIZE 1000
SET FEEDBACK OFF
SET HEADING ON
COLUMN name FORMAT A30
COLUMN value FORMAT A50
COLUMN tablespace_name FORMAT A30
COLUMN file_name FORMAT A60
COLUMN pdb_name FORMAT A30
$sql
EXIT;
EOF
    else
        echo "ERROR: ORACLE_HOME or ORACLE_SID not set"
        return 1
    fi
}

################################################################################
# Discovery Functions
################################################################################

discover_os_info() {
    log_section "OPERATING SYSTEM INFORMATION"
    
    log_subsection "Hostname and IP Addresses"
    log_info "Hostname: $HOSTNAME"
    log_info "FQDN: $(hostname -f 2>/dev/null || echo 'N/A')"
    log_info ""
    log_info "IP Addresses:"
    ip addr show 2>/dev/null | grep -E "inet |inet6 " | tee -a "$OUTPUT_FILE" || \
        ifconfig 2>/dev/null | grep -E "inet |inet6 " | tee -a "$OUTPUT_FILE" || \
        log_warning "Could not retrieve IP addresses"
    
    log_subsection "Operating System Version"
    cat /etc/os-release 2>/dev/null | tee -a "$OUTPUT_FILE" || \
        cat /etc/oracle-release 2>/dev/null | tee -a "$OUTPUT_FILE" || \
        uname -a | tee -a "$OUTPUT_FILE"
    
    log_subsection "Kernel Version"
    uname -r | tee -a "$OUTPUT_FILE"
    
    log_subsection "Disk Space"
    df -h | tee -a "$OUTPUT_FILE"
    
    log_subsection "Memory"
    free -h 2>/dev/null | tee -a "$OUTPUT_FILE" || log_warning "Could not retrieve memory info"
}

discover_oracle_environment() {
    log_section "ORACLE ENVIRONMENT"
    
    log_subsection "Environment Variables"
    log_info "ORACLE_HOME: ${ORACLE_HOME:-NOT SET}"
    log_info "ORACLE_SID: ${ORACLE_SID:-NOT SET}"
    log_info "ORACLE_BASE: ${ORACLE_BASE:-NOT SET}"
    log_info "GRID_HOME: ${GRID_HOME:-NOT SET}"
    log_info "TNS_ADMIN: ${TNS_ADMIN:-NOT SET}"
    log_info "PATH: $PATH"
    
    if [ -z "$ORACLE_HOME" ]; then
        log_error "ORACLE_HOME is not set. Database discovery may be incomplete."
        return 1
    fi
    
    log_subsection "Oracle Version"
    $ORACLE_HOME/bin/sqlplus -v 2>/dev/null | tee -a "$OUTPUT_FILE" || log_warning "Could not get SQLPlus version"
    
    log_subsection "Oracle Inventory"
    if [ -f /etc/oraInst.loc ]; then
        cat /etc/oraInst.loc | tee -a "$OUTPUT_FILE"
    else
        log_warning "/etc/oraInst.loc not found"
    fi
}

discover_database_config() {
    log_section "DATABASE CONFIGURATION"
    
    log_subsection "Database Identification"
    run_sql "
    SELECT name, db_unique_name, dbid, created,
           log_mode, force_logging
    FROM v\$database;
    " | tee -a "$OUTPUT_FILE"
    
    log_subsection "Instance Information"
    run_sql "
    SELECT instance_name, host_name, version_full, status,
           database_status, instance_role
    FROM v\$instance;
    " | tee -a "$OUTPUT_FILE"
    
    log_subsection "Database Role and Open Mode"
    run_sql "
    SELECT database_role, open_mode
    FROM v\$database;
    " | tee -a "$OUTPUT_FILE"
    
    log_subsection "Character Set"
    run_sql "
    SELECT parameter, value 
    FROM nls_database_parameters 
    WHERE parameter IN ('NLS_CHARACTERSET', 'NLS_NCHAR_CHARACTERSET',
                        'NLS_LANGUAGE', 'NLS_TERRITORY');
    " | tee -a "$OUTPUT_FILE"
}

discover_storage() {
    log_section "STORAGE CONFIGURATION"
    
    log_subsection "Tablespace Summary"
    run_sql "
    SELECT tablespace_name, status, contents, allocation_type,
           segment_space_management, encrypted
    FROM dba_tablespaces
    ORDER BY tablespace_name;
    " | tee -a "$OUTPUT_FILE"
    
    log_subsection "Tablespace Size and Free Space"
    run_sql "
    SELECT t.tablespace_name,
           ROUND(SUM(d.bytes)/1024/1024/1024, 2) as size_gb,
           ROUND(SUM(d.bytes)/1024/1024/1024 - NVL(f.free_gb, 0), 2) as used_gb,
           ROUND(NVL(f.free_gb, 0), 2) as free_gb,
           ROUND((SUM(d.bytes)/1024/1024/1024 - NVL(f.free_gb, 0)) / 
                 (SUM(d.bytes)/1024/1024/1024) * 100, 1) as pct_used
    FROM dba_data_files d
    JOIN dba_tablespaces t ON d.tablespace_name = t.tablespace_name
    LEFT JOIN (SELECT tablespace_name, 
                      ROUND(SUM(bytes)/1024/1024/1024, 2) as free_gb
               FROM dba_free_space 
               GROUP BY tablespace_name) f 
    ON t.tablespace_name = f.tablespace_name
    GROUP BY t.tablespace_name, f.free_gb
    ORDER BY t.tablespace_name;
    " | tee -a "$OUTPUT_FILE"
    
    log_subsection "ASM Disk Groups (if applicable)"
    run_sql "
    SELECT group_number, name, type, state,
           total_mb/1024 as total_gb,
           free_mb/1024 as free_gb,
           ROUND((total_mb - free_mb) / total_mb * 100, 1) as pct_used
    FROM v\$asm_diskgroup;
    " | tee -a "$OUTPUT_FILE"
    
    log_subsection "ASM Disk Details"
    run_sql "
    SELECT group_number, disk_number, name, path, 
           total_mb/1024 as total_gb, free_mb/1024 as free_gb
    FROM v\$asm_disk
    WHERE group_number > 0
    ORDER BY group_number, disk_number;
    " | tee -a "$OUTPUT_FILE"
}

discover_cdb_pdb() {
    log_section "CONTAINER DATABASE CONFIGURATION"
    
    log_subsection "CDB Status"
    run_sql "SELECT cdb FROM v\$database;" | tee -a "$OUTPUT_FILE"
    
    log_subsection "PDB Information"
    run_sql "
    SELECT con_id, name, open_mode, restricted,
           recovery_status, application_root
    FROM v\$pdbs ORDER BY con_id;
    " | tee -a "$OUTPUT_FILE"
    
    log_subsection "PDB Size Details"
    run_sql "
    SELECT c.name as pdb_name, c.con_id,
           ROUND(SUM(d.bytes)/1024/1024/1024, 2) as size_gb
    FROM v\$containers c
    LEFT JOIN cdb_data_files d ON c.con_id = d.con_id
    GROUP BY c.name, c.con_id
    ORDER BY c.con_id;
    " | tee -a "$OUTPUT_FILE"
    
    log_subsection "PDB Services"
    run_sql "
    SELECT name, pdb, network_name
    FROM v\$services
    WHERE pdb IS NOT NULL
    ORDER BY pdb, name;
    " | tee -a "$OUTPUT_FILE"
}

discover_tde_config() {
    log_section "TDE CONFIGURATION"
    
    log_subsection "TDE/Wallet Status"
    run_sql "
    SELECT wrl_type, wrl_parameter, status, wallet_type,
           wallet_order, keystore_mode
    FROM v\$encryption_wallet;
    " | tee -a "$OUTPUT_FILE"
    
    log_subsection "Encrypted Tablespaces"
    run_sql "
    SELECT tablespace_name, encrypted, status
    FROM dba_tablespaces
    WHERE encrypted = 'YES'
    ORDER BY tablespace_name;
    " | tee -a "$OUTPUT_FILE"
    
    log_subsection "TDE Parameters"
    run_sql "
    SHOW PARAMETER wallet_root;
    SHOW PARAMETER tde_configuration;
    " | tee -a "$OUTPUT_FILE"
}

discover_network() {
    log_section "NETWORK CONFIGURATION"
    
    log_subsection "Listener Status"
    if [ -n "$ORACLE_HOME" ]; then
        $ORACLE_HOME/bin/lsnrctl status 2>&1 | tee -a "$OUTPUT_FILE" || \
            log_warning "Could not get listener status"
    fi
    
    log_subsection "SCAN Listener (if RAC)"
    if [ -n "$GRID_HOME" ]; then
        $GRID_HOME/bin/srvctl status scan_listener 2>&1 | tee -a "$OUTPUT_FILE" || \
            log_warning "Could not get SCAN listener status"
    elif command -v srvctl &>/dev/null; then
        srvctl status scan_listener 2>&1 | tee -a "$OUTPUT_FILE" || \
            log_warning "Could not get SCAN listener status"
    else
        log_info "SCAN listener check skipped - not a RAC configuration or srvctl not found"
    fi
    
    log_subsection "tnsnames.ora"
    local tnsnames="${TNS_ADMIN:-$ORACLE_HOME/network/admin}/tnsnames.ora"
    if [ -f "$tnsnames" ]; then
        log_info "File: $tnsnames"
        cat "$tnsnames" 2>/dev/null | tee -a "$OUTPUT_FILE"
    else
        log_warning "tnsnames.ora not found at $tnsnames"
    fi
    
    log_subsection "sqlnet.ora"
    local sqlnet="${TNS_ADMIN:-$ORACLE_HOME/network/admin}/sqlnet.ora"
    if [ -f "$sqlnet" ]; then
        log_info "File: $sqlnet"
        cat "$sqlnet" 2>/dev/null | tee -a "$OUTPUT_FILE"
    else
        log_warning "sqlnet.ora not found at $sqlnet"
    fi
}

discover_oci_azure_integration() {
    log_section "OCI/AZURE INTEGRATION"
    
    log_subsection "OCI CLI Version"
    oci --version 2>&1 | tee -a "$OUTPUT_FILE" || log_warning "OCI CLI not installed or not in PATH"
    
    log_subsection "OCI Config"
    if [ -f ~/.oci/config ]; then
        log_info "OCI config file exists: ~/.oci/config"
        log_info "Configured profiles:"
        grep "^\[" ~/.oci/config 2>/dev/null | tee -a "$OUTPUT_FILE"
        log_info ""
        log_info "Configured regions:"
        grep "^region" ~/.oci/config 2>/dev/null | tee -a "$OUTPUT_FILE"
    else
        log_warning "OCI config not found at ~/.oci/config"
    fi
    
    log_subsection "OCI API Key"
    if [ -d ~/.oci ]; then
        log_info "OCI directory contents (keys masked):"
        ls -la ~/.oci/ 2>/dev/null | tee -a "$OUTPUT_FILE"
    fi
    
    log_subsection "OCI Connectivity Test"
    oci iam region list --output table 2>&1 | head -20 | tee -a "$OUTPUT_FILE" || \
        log_warning "OCI connectivity test failed"
    
    log_subsection "Instance Metadata - OCI"
    curl -s -H "Authorization: Bearer Oracle" \
         http://169.254.169.254/opc/v2/instance/ 2>/dev/null | \
         python3 -m json.tool 2>/dev/null | tee -a "$OUTPUT_FILE" || \
         log_warning "Could not retrieve OCI instance metadata"
    
    log_subsection "Instance Metadata - Azure"
    curl -s -H "Metadata:true" \
         "http://169.254.169.254/metadata/instance?api-version=2021-02-01" 2>/dev/null | \
         python3 -m json.tool 2>/dev/null | tee -a "$OUTPUT_FILE" || \
         log_warning "Could not retrieve Azure instance metadata"
}

discover_grid_infrastructure() {
    log_section "GRID INFRASTRUCTURE (if RAC)"
    
    log_subsection "CRS Status"
    if [ -n "$GRID_HOME" ]; then
        $GRID_HOME/bin/crsctl stat res -t 2>&1 | tee -a "$OUTPUT_FILE" || \
            log_warning "Could not get CRS status"
    elif command -v crsctl &>/dev/null; then
        crsctl stat res -t 2>&1 | tee -a "$OUTPUT_FILE" || \
            log_warning "Could not get CRS status"
    else
        log_info "CRS check skipped - Grid Infrastructure not found"
    fi
    
    log_subsection "Cluster Nodes"
    if [ -n "$GRID_HOME" ]; then
        $GRID_HOME/bin/olsnodes -n 2>&1 | tee -a "$OUTPUT_FILE" || \
            log_info "Not a cluster configuration"
    elif command -v olsnodes &>/dev/null; then
        olsnodes -n 2>&1 | tee -a "$OUTPUT_FILE" || \
            log_info "Not a cluster configuration"
    fi
    
    log_subsection "Database Services"
    if command -v srvctl &>/dev/null; then
        srvctl config database 2>&1 | tee -a "$OUTPUT_FILE" || \
            log_warning "Could not get database configuration"
    else
        log_info "srvctl not found - skipping service configuration"
    fi
}

discover_authentication() {
    log_section "AUTHENTICATION CONFIGURATION"
    
    log_subsection "SSH Directory"
    if [ -d ~/.ssh ]; then
        ls -la ~/.ssh/ 2>/dev/null | tee -a "$OUTPUT_FILE"
    else
        log_warning "~/.ssh directory not found"
    fi
    
    log_subsection "Authorized Keys"
    if [ -f ~/.ssh/authorized_keys ]; then
        log_info "authorized_keys exists with $(wc -l < ~/.ssh/authorized_keys) entries"
    else
        log_warning "No authorized_keys file found"
    fi
}

################################################################################
# Additional Custom Discovery (PRODDB Specific - Oracle Database@Azure)
################################################################################

discover_exadata_storage() {
    log_section "EXADATA STORAGE CAPACITY"
    
    log_subsection "Exadata Storage Overview"
    run_sql "
    SELECT name, type, state, 
           total_mb/1024 as total_gb,
           free_mb/1024 as free_gb,
           usable_file_mb/1024 as usable_gb
    FROM v\$asm_diskgroup
    ORDER BY name;
    " | tee -a "$OUTPUT_FILE"
    
    log_subsection "Available Space for Migration"
    run_sql "
    SELECT SUM(free_mb)/1024 as total_free_gb,
           SUM(usable_file_mb)/1024 as total_usable_gb
    FROM v\$asm_diskgroup
    WHERE type IN ('NORMAL', 'HIGH');
    " | tee -a "$OUTPUT_FILE"
    
    log_subsection "Exadata Cell Information (if available)"
    run_sql "
    SELECT cell_path, cell_name, status
    FROM v\$cell
    ORDER BY cell_name;
    " | tee -a "$OUTPUT_FILE" 2>/dev/null || log_info "Cell information not available (not Exadata or no privileges)"
    
    log_subsection "Flash Cache Configuration"
    run_sql "
    SELECT name, value
    FROM v\$parameter
    WHERE name LIKE '%flash%' OR name LIKE '%smart_flash%'
    ORDER BY name;
    " | tee -a "$OUTPUT_FILE"
}

discover_preconfigured_pdbs() {
    log_section "PRE-CONFIGURED PDBS"
    
    log_subsection "All PDB Details"
    run_sql "
    SELECT pdb_id, pdb_name, status, creation_time,
           con_id, con_uid, guid
    FROM cdb_pdbs
    ORDER BY pdb_id;
    " | tee -a "$OUTPUT_FILE"
    
    log_subsection "PDB Open Mode History"
    run_sql "
    SELECT name, open_mode, open_time
    FROM v\$pdbs
    ORDER BY con_id;
    " | tee -a "$OUTPUT_FILE"
    
    log_subsection "PDB Datafile Locations"
    run_sql "
    SELECT c.name as pdb_name, d.file_name,
           ROUND(d.bytes/1024/1024/1024, 2) as size_gb
    FROM v\$containers c
    JOIN cdb_data_files d ON c.con_id = d.con_id
    WHERE c.name != 'CDB\$ROOT'
    ORDER BY c.name, d.file_id;
    " | tee -a "$OUTPUT_FILE"
    
    log_subsection "PDB Resource Limits"
    run_sql "
    SELECT pdb_name, max_size_mb, max_iops, max_mbps
    FROM cdb_pdbs p
    LEFT JOIN v\$resource_limit r ON p.con_id = r.con_id
    ORDER BY pdb_name;
    " | tee -a "$OUTPUT_FILE" 2>/dev/null || log_info "Resource limits not configured"
}

discover_network_security() {
    log_section "NETWORK SECURITY GROUP RULES"
    
    log_subsection "Azure NSG via Metadata (if available)"
    # Try to get network info from Azure metadata
    curl -s -H "Metadata:true" \
         "http://169.254.169.254/metadata/instance/network?api-version=2021-02-01" 2>/dev/null | \
         python3 -m json.tool 2>/dev/null | tee -a "$OUTPUT_FILE" || \
         log_warning "Could not retrieve Azure network metadata"
    
    log_subsection "Network Interfaces"
    ip addr show 2>/dev/null | tee -a "$OUTPUT_FILE" || \
        ifconfig -a 2>/dev/null | tee -a "$OUTPUT_FILE" || \
        log_warning "Could not list network interfaces"
    
    log_subsection "Listening Ports"
    ss -tlnp 2>/dev/null | tee -a "$OUTPUT_FILE" || \
        netstat -tlnp 2>/dev/null | tee -a "$OUTPUT_FILE" || \
        log_warning "Could not list listening ports"
    
    log_subsection "Firewall Status"
    systemctl status firewalld 2>/dev/null | head -10 | tee -a "$OUTPUT_FILE" || \
        log_info "firewalld not running or not installed"
    
    iptables -L -n 2>/dev/null | head -30 | tee -a "$OUTPUT_FILE" || \
        log_info "Could not list iptables rules"
    
    log_subsection "OCI Security List (via CLI)"
    if command -v oci &>/dev/null; then
        # Get compartment and VCN info from metadata if possible
        COMPARTMENT_ID=$(curl -s -H "Authorization: Bearer Oracle" \
            http://169.254.169.254/opc/v2/instance/ 2>/dev/null | \
            python3 -c "import sys,json; print(json.load(sys.stdin).get('compartmentId',''))" 2>/dev/null)
        
        if [ -n "$COMPARTMENT_ID" ]; then
            log_info "Compartment ID: $COMPARTMENT_ID"
            log_info "Note: Full NSG rules require OCI Console or appropriate permissions"
        fi
    fi
}

################################################################################
# Main Execution
################################################################################

main() {
    echo "" | tee "$OUTPUT_FILE"
    echo "================================================================================" | tee -a "$OUTPUT_FILE"
    echo "= ZDM Target Database Discovery Report" | tee -a "$OUTPUT_FILE"
    echo "= Project: PRODDB Migration to Oracle Database@Azure" | tee -a "$OUTPUT_FILE"
    echo "= Server: proddb-oda.eastus.azure.example.com" | tee -a "$OUTPUT_FILE"
    echo "= Hostname: $HOSTNAME" | tee -a "$OUTPUT_FILE"
    echo "= Timestamp: $(date)" | tee -a "$OUTPUT_FILE"
    echo "= Script Version: $SCRIPT_VERSION" | tee -a "$OUTPUT_FILE"
    echo "================================================================================" | tee -a "$OUTPUT_FILE"
    
    # Run all discovery functions - continue even if some fail
    discover_os_info || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_oracle_environment || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_database_config || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_storage || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_cdb_pdb || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_tde_config || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_network || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_oci_azure_integration || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_grid_infrastructure || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_authentication || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    
    # Additional PRODDB-specific discovery for Oracle Database@Azure
    discover_exadata_storage || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_preconfigured_pdbs || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_network_security || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    
    # Summary
    log_section "DISCOVERY SUMMARY"
    log_info "Discovery completed at: $(date)"
    log_info "Section errors encountered: $SECTION_ERRORS"
    log_info "Text report: $OUTPUT_FILE"
    log_info "JSON summary: $JSON_FILE"
    
    # Build final JSON
    cat > "$JSON_FILE" << EOF
{
  "discovery_type": "target_database",
  "project": "PRODDB Migration to Oracle Database@Azure",
  "target_server": "proddb-oda.eastus.azure.example.com",
  "hostname": "$HOSTNAME",
  "timestamp": "$(date -Iseconds 2>/dev/null || date)",
  "script_version": "$SCRIPT_VERSION",
  "oracle_home": "${ORACLE_HOME:-null}",
  "oracle_sid": "${ORACLE_SID:-null}",
  "grid_home": "${GRID_HOME:-null}",
  "section_errors": $SECTION_ERRORS,
  "output_files": {
    "text_report": "$OUTPUT_FILE",
    "json_summary": "$JSON_FILE"
  }
}
EOF
    
    echo ""
    log_success "Discovery complete!"
    echo ""
    echo "Output files:"
    echo "  Text Report: $OUTPUT_FILE"
    echo "  JSON Summary: $JSON_FILE"
    echo ""
    
    # Always exit 0 so orchestrator knows script completed
    exit 0
}

# Run main
main "$@"
