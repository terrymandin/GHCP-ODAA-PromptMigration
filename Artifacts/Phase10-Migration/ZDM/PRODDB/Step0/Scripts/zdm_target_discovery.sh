#!/bin/bash
# =============================================================================
# ZDM Target Database Discovery Script
# =============================================================================
# Project: PRODDB Migration to Oracle Database@Azure
# Target Server: proddb-oda.eastus.azure.example.com
# Generated: 2026-01-29
# =============================================================================
# This script discovers the target Oracle Database@Azure configuration for
# ZDM migration. It gathers OS, Oracle, OCI/Azure, and Grid infrastructure info.
# =============================================================================

# NO set -e - We want to continue even if some checks fail
SECTION_ERRORS=0

# =============================================================================
# Color Output
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Environment Variable Discovery
# =============================================================================
# CRITICAL: Handle environment variables in non-interactive SSH sessions
# .bashrc often has guards like '[ -z "$PS1" ] && return' that skip non-interactive shells

# Method 1: Accept explicit overrides (passed from orchestration script)
[ -n "${ORACLE_HOME_OVERRIDE:-}" ] && export ORACLE_HOME="$ORACLE_HOME_OVERRIDE"
[ -n "${ORACLE_SID_OVERRIDE:-}" ] && export ORACLE_SID="$ORACLE_SID_OVERRIDE"
[ -n "${ORACLE_BASE_OVERRIDE:-}" ] && export ORACLE_BASE="$ORACLE_BASE_OVERRIDE"
[ -n "${GRID_HOME_OVERRIDE:-}" ] && export GRID_HOME="$GRID_HOME_OVERRIDE"

# Method 2: Extract export statements from profiles (bypasses interactive guards)
for profile in /etc/profile ~/.bash_profile ~/.bashrc; do
    if [ -f "$profile" ]; then
        eval "$(grep -E '^export\s+(ORACLE_HOME|ORACLE_SID|ORACLE_BASE|GRID_HOME|TNS_ADMIN|PATH)=' "$profile" 2>/dev/null)" || true
    fi
done

# Method 3: Auto-detect Oracle environment
detect_oracle_env() {
    # If already set, use existing values
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        return 0
    fi
    
    # For ODA@Azure, check common Oracle home locations
    if [ -z "${ORACLE_HOME:-}" ]; then
        for ora_path in /u01/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1 /u02/app/oracle/product/*/dbhome_1; do
            if [ -d "$ora_path" ] && [ -f "$ora_path/bin/sqlplus" ]; then
                export ORACLE_HOME="$ora_path"
                break
            fi
        done
    fi
    
    # Try oratab
    if [ -f /etc/oratab ]; then
        local oratab_entry
        if [ -n "${ORACLE_SID:-}" ]; then
            oratab_entry=$(grep "^${ORACLE_SID}:" /etc/oratab 2>/dev/null | head -1)
        else
            oratab_entry=$(grep -v '^#' /etc/oratab | grep -v '^$' | grep ':' | head -1)
        fi
        if [ -n "$oratab_entry" ]; then
            export ORACLE_SID="${ORACLE_SID:-$(echo "$oratab_entry" | cut -d: -f1)}"
            export ORACLE_HOME="${ORACLE_HOME:-$(echo "$oratab_entry" | cut -d: -f2)}"
        fi
    fi
    
    # Check running pmon process
    if [ -z "${ORACLE_SID:-}" ]; then
        local pmon_sid
        pmon_sid=$(ps -ef | grep 'ora_pmon_' | grep -v grep | head -1 | sed 's/.*ora_pmon_//')
        [ -n "$pmon_sid" ] && export ORACLE_SID="$pmon_sid"
    fi
}

detect_grid_home() {
    if [ -n "${GRID_HOME:-}" ]; then
        return 0
    fi
    
    # Check common Grid Infrastructure locations
    for grid_path in /u01/app/grid /u01/app/*/grid /opt/oracle/grid; do
        if [ -d "$grid_path" ] && [ -f "$grid_path/bin/crsctl" ]; then
            export GRID_HOME="$grid_path"
            break
        fi
    done
    
    # Try to get from olr.loc
    if [ -z "${GRID_HOME:-}" ] && [ -f /etc/oracle/olr.loc ]; then
        GRID_HOME=$(grep "^crs_home=" /etc/oracle/olr.loc 2>/dev/null | cut -d= -f2)
        [ -n "$GRID_HOME" ] && export GRID_HOME
    fi
}

detect_oracle_env
detect_grid_home

# Set ORACLE_BASE if not set
if [ -z "${ORACLE_BASE:-}" ] && [ -n "${ORACLE_HOME:-}" ]; then
    export ORACLE_BASE=$(echo "$ORACLE_HOME" | sed 's|/product/.*||')
fi

# Update PATH
[ -n "$ORACLE_HOME" ] && export PATH="$ORACLE_HOME/bin:$PATH"
[ -n "$GRID_HOME" ] && export PATH="$GRID_HOME/bin:$PATH"

# =============================================================================
# Output Configuration
# =============================================================================
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname)
OUTPUT_FILE="./zdm_target_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_target_discovery_${HOSTNAME}_${TIMESTAMP}.json"

# =============================================================================
# Helper Functions
# =============================================================================
log_section() {
    local section_name="$1"
    echo ""
    echo "================================================================================"
    echo " $section_name"
    echo "================================================================================"
    echo ""
}

log_subsection() {
    local subsection_name="$1"
    echo ""
    echo "--- $subsection_name ---"
    echo ""
}

run_sql() {
    local sql_query="$1"
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        "$ORACLE_HOME/bin/sqlplus" -s / as sysdba <<EOF
SET PAGESIZE 1000
SET LINESIZE 200
SET FEEDBACK OFF
SET HEADING ON
SET ECHO OFF
$sql_query
EOF
    else
        echo "ERROR: ORACLE_HOME or ORACLE_SID not set"
        return 1
    fi
}

run_sql_value() {
    local sql_query="$1"
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        "$ORACLE_HOME/bin/sqlplus" -s / as sysdba <<EOF
SET PAGESIZE 0
SET LINESIZE 200
SET FEEDBACK OFF
SET HEADING OFF
SET ECHO OFF
SET TRIMSPOOL ON
$sql_query
EOF
    else
        echo "ERROR: ORACLE_HOME or ORACLE_SID not set"
        return 1
    fi
}

# =============================================================================
# Discovery Functions
# =============================================================================

discover_os_info() {
    log_section "OS INFORMATION"
    
    echo "Hostname: $(hostname)"
    echo "FQDN: $(hostname -f 2>/dev/null || hostname)"
    echo ""
    
    log_subsection "IP Addresses"
    ip addr show 2>/dev/null | grep "inet " || ifconfig 2>/dev/null | grep "inet " || echo "Could not determine IP addresses"
    
    log_subsection "Operating System"
    if [ -f /etc/os-release ]; then
        cat /etc/os-release
    elif [ -f /etc/redhat-release ]; then
        cat /etc/redhat-release
    else
        uname -a
    fi
    
    log_subsection "Kernel"
    uname -r
    
    log_subsection "Disk Space"
    df -h
    
    log_subsection "Memory"
    free -h 2>/dev/null || cat /proc/meminfo 2>/dev/null | head -10
    
    log_subsection "CPU Info"
    grep "model name" /proc/cpuinfo 2>/dev/null | head -1
    echo "CPU Cores: $(grep -c processor /proc/cpuinfo 2>/dev/null || echo 'Unknown')"
}

discover_oracle_env() {
    log_section "ORACLE ENVIRONMENT"
    
    echo "ORACLE_HOME: ${ORACLE_HOME:-NOT SET}"
    echo "ORACLE_SID: ${ORACLE_SID:-NOT SET}"
    echo "ORACLE_BASE: ${ORACLE_BASE:-NOT SET}"
    echo "GRID_HOME: ${GRID_HOME:-NOT SET}"
    echo "TNS_ADMIN: ${TNS_ADMIN:-NOT SET}"
    
    log_subsection "Oracle Version"
    if [ -n "${ORACLE_HOME:-}" ] && [ -f "$ORACLE_HOME/bin/sqlplus" ]; then
        "$ORACLE_HOME/bin/sqlplus" -v 2>/dev/null || echo "Could not determine Oracle version"
    else
        echo "Oracle not found or ORACLE_HOME not set"
    fi
    
    log_subsection "oratab Contents"
    if [ -f /etc/oratab ]; then
        cat /etc/oratab
    else
        echo "/etc/oratab not found"
    fi
    
    log_subsection "Running Oracle Processes"
    ps -ef | grep -E "ora_pmon|ora_smon|tnslsnr|d.bin" | grep -v grep || echo "No Oracle processes found"
}

discover_database_config() {
    log_section "DATABASE CONFIGURATION"
    
    log_subsection "Database Identification"
    run_sql "
    SELECT name, db_unique_name, dbid, created, log_mode, 
           force_logging, open_mode, database_role
    FROM v\$database;
    " || echo "WARNING: Could not query database identification"
    
    log_subsection "Instance Information"
    run_sql "
    SELECT instance_name, host_name, version, status, 
           startup_time, instance_role
    FROM v\$instance;
    " || echo "WARNING: Could not query instance information"
    
    log_subsection "Database Version Details"
    run_sql "SELECT * FROM v\$version;" || echo "WARNING: Could not query version"
    
    log_subsection "Character Set"
    run_sql "
    SELECT parameter, value 
    FROM nls_database_parameters 
    WHERE parameter IN ('NLS_CHARACTERSET', 'NLS_NCHAR_CHARACTERSET', 'NLS_LANGUAGE', 'NLS_TERRITORY');
    " || echo "WARNING: Could not query character set"
}

discover_storage() {
    log_section "STORAGE CONFIGURATION"
    
    log_subsection "Tablespaces"
    run_sql "
    SELECT tablespace_name, status, contents, extent_management,
           segment_space_management, bigfile
    FROM dba_tablespaces
    ORDER BY tablespace_name;
    " || echo "WARNING: Could not query tablespaces"
    
    log_subsection "Tablespace Space Usage"
    run_sql "
    SELECT tablespace_name, 
           ROUND(SUM(bytes)/1024/1024/1024, 2) as used_gb,
           ROUND(SUM(maxbytes)/1024/1024/1024, 2) as max_gb
    FROM dba_data_files
    GROUP BY tablespace_name
    ORDER BY tablespace_name;
    " || echo "WARNING: Could not query tablespace usage"
    
    log_subsection "ASM Diskgroups"
    run_sql "
    SELECT name, state, type, total_mb, free_mb,
           ROUND(free_mb/total_mb*100, 2) as pct_free
    FROM v\$asm_diskgroup;
    " 2>/dev/null || echo "NOTE: ASM not configured or could not query diskgroups"
    
    log_subsection "ASM Disks"
    run_sql "
    SELECT group_number, disk_number, name, path, 
           total_mb, free_mb, state
    FROM v\$asm_disk
    ORDER BY group_number, disk_number;
    " 2>/dev/null || echo "NOTE: ASM not configured or could not query disks"
}

discover_cdb_pdb() {
    log_section "CONTAINER DATABASE CONFIGURATION"
    
    log_subsection "CDB Status"
    run_sql "SELECT cdb FROM v\$database;" || echo "WARNING: Could not determine CDB status"
    
    log_subsection "PDB Information"
    run_sql "
    SELECT con_id, name, open_mode, restricted, guid
    FROM v\$pdbs
    ORDER BY con_id;
    " 2>/dev/null || echo "NOTE: Not a CDB or could not query PDBs"
    
    log_subsection "Container Information"
    run_sql "
    SELECT con_id, name, dbid, con_uid, guid
    FROM v\$containers
    ORDER BY con_id;
    " 2>/dev/null || echo "NOTE: Not a CDB or could not query containers"
    
    log_subsection "PDB Datafile Locations"
    run_sql "
    SELECT con_id, tablespace_name, file_name
    FROM cdb_data_files
    ORDER BY con_id, tablespace_name;
    " 2>/dev/null || echo "NOTE: Could not query PDB datafiles"
}

discover_tde() {
    log_section "TDE CONFIGURATION"
    
    log_subsection "Encryption Wallet Status"
    run_sql "
    SELECT wrl_type, wrl_parameter, status, wallet_type, wallet_order
    FROM v\$encryption_wallet;
    " || echo "WARNING: Could not query encryption wallet"
    
    log_subsection "Encryption Keys"
    run_sql "
    SELECT key_id, keystore_type, creator, creator_pdbname, activating_pdbname
    FROM v\$encryption_keys;
    " || echo "WARNING: Could not query encryption keys"
}

discover_network() {
    log_section "NETWORK CONFIGURATION"
    
    log_subsection "Listener Status"
    if [ -n "${ORACLE_HOME:-}" ]; then
        "$ORACLE_HOME/bin/lsnrctl" status 2>&1 || echo "Could not get listener status"
    else
        echo "ORACLE_HOME not set, cannot check listener"
    fi
    
    log_subsection "SCAN Listener Status"
    if [ -n "${GRID_HOME:-}" ]; then
        "$GRID_HOME/bin/srvctl" status scan_listener 2>&1 || echo "Could not get SCAN listener status"
    else
        echo "GRID_HOME not set, cannot check SCAN listener"
    fi
    
    log_subsection "tnsnames.ora"
    for tns_file in "$TNS_ADMIN/tnsnames.ora" "$ORACLE_HOME/network/admin/tnsnames.ora" "$GRID_HOME/network/admin/tnsnames.ora"; do
        if [ -f "$tns_file" ]; then
            echo "Found: $tns_file"
            cat "$tns_file"
            break
        fi
    done
}

discover_oci_azure() {
    log_section "OCI/AZURE INTEGRATION"
    
    log_subsection "OCI CLI Version"
    if command -v oci >/dev/null 2>&1; then
        oci --version 2>&1 || echo "Could not determine OCI CLI version"
    else
        echo "OCI CLI not installed"
    fi
    
    log_subsection "OCI Configuration"
    if [ -f ~/.oci/config ]; then
        echo "OCI config file found at ~/.oci/config"
        echo "Profiles:"
        grep "^\[" ~/.oci/config 2>/dev/null || echo "Could not parse profiles"
        echo ""
        echo "Regions configured:"
        grep "^region" ~/.oci/config 2>/dev/null || echo "No region configured"
    else
        echo "OCI config file not found"
    fi
    
    log_subsection "OCI Connectivity Test"
    if command -v oci >/dev/null 2>&1; then
        oci iam region list --output table 2>&1 | head -10 || echo "OCI connectivity test failed"
    else
        echo "OCI CLI not available for connectivity test"
    fi
    
    log_subsection "OCI Instance Metadata"
    curl -s -H "Authorization: Bearer Oracle" http://169.254.169.254/opc/v2/instance/ 2>/dev/null | head -50 || echo "Could not retrieve OCI instance metadata"
    
    log_subsection "Azure Instance Metadata"
    curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" 2>/dev/null | head -50 || echo "Could not retrieve Azure instance metadata"
    
    log_subsection "Azure CLI Version"
    if command -v az >/dev/null 2>&1; then
        az --version 2>&1 | head -5 || echo "Could not determine Azure CLI version"
    else
        echo "Azure CLI not installed"
    fi
}

discover_grid_infrastructure() {
    log_section "GRID INFRASTRUCTURE (RAC)"
    
    if [ -z "${GRID_HOME:-}" ]; then
        echo "GRID_HOME not set - Grid Infrastructure may not be installed"
        return 0
    fi
    
    log_subsection "CRS Status"
    "$GRID_HOME/bin/crsctl" stat res -t 2>&1 || echo "Could not get CRS status"
    
    log_subsection "Cluster Nodes"
    "$GRID_HOME/bin/olsnodes" -n 2>&1 || echo "Could not get cluster nodes"
    
    log_subsection "Database Configuration"
    "$GRID_HOME/bin/srvctl" config database 2>&1 || echo "Could not get database configuration"
    
    log_subsection "SCAN Configuration"
    "$GRID_HOME/bin/srvctl" config scan 2>&1 || echo "Could not get SCAN configuration"
}

discover_authentication() {
    log_section "AUTHENTICATION CONFIGURATION"
    
    log_subsection "SSH Directory"
    echo "Contents of ~/.ssh/:"
    ls -la ~/.ssh/ 2>/dev/null || echo "~/.ssh directory not found or not accessible"
    
    log_subsection "SSH Public Keys"
    cat ~/.ssh/authorized_keys 2>/dev/null | head -20 || echo "No authorized_keys file found"
}

# =============================================================================
# Additional Discovery (Custom for PRODDB - Oracle Database@Azure)
# =============================================================================

discover_exadata_storage() {
    log_section "EXADATA STORAGE CAPACITY"
    
    log_subsection "Cell Configuration"
    if command -v cellcli >/dev/null 2>&1; then
        cellcli -e "list cell detail" 2>&1 || echo "Could not query cell configuration"
        cellcli -e "list celldisk detail" 2>&1 || echo "Could not query cell disks"
        cellcli -e "list griddisk detail" 2>&1 || echo "Could not query grid disks"
    else
        echo "cellcli not available - checking ASM diskgroups instead"
    fi
    
    log_subsection "ASM Storage Summary"
    run_sql "
    SELECT name, 
           state,
           type,
           ROUND(total_mb/1024, 2) as total_gb,
           ROUND(free_mb/1024, 2) as free_gb,
           ROUND((total_mb - free_mb)/1024, 2) as used_gb,
           ROUND(free_mb/total_mb*100, 2) as pct_free
    FROM v\$asm_diskgroup
    ORDER BY name;
    " || echo "WARNING: Could not query ASM diskgroups"
    
    log_subsection "Storage Capacity by Diskgroup"
    run_sql "
    SELECT dg.name as diskgroup,
           ROUND(SUM(f.bytes)/1024/1024/1024, 2) as datafiles_gb
    FROM v\$asm_diskgroup dg, dba_data_files f
    WHERE f.file_name LIKE '%' || dg.name || '%'
    GROUP BY dg.name;
    " 2>/dev/null || echo "NOTE: Could not calculate per-diskgroup usage"
}

discover_preconfigured_pdbs() {
    log_section "PRE-CONFIGURED PDBs"
    
    run_sql "
    SELECT c.con_id, 
           c.name as pdb_name, 
           c.open_mode,
           ROUND(SUM(d.bytes)/1024/1024/1024, 2) as size_gb
    FROM v\$containers c
    LEFT JOIN cdb_data_files d ON c.con_id = d.con_id
    WHERE c.con_id > 1
    GROUP BY c.con_id, c.name, c.open_mode
    ORDER BY c.con_id;
    " || echo "WARNING: Could not query pre-configured PDBs"
    
    log_subsection "PDB Services"
    run_sql "
    SELECT con_id, name, network_name, creation_date
    FROM cdb_services
    WHERE con_id > 1
    ORDER BY con_id, name;
    " 2>/dev/null || echo "NOTE: Could not query PDB services"
}

discover_network_security() {
    log_section "NETWORK SECURITY GROUP RULES"
    
    log_subsection "Firewall Status"
    systemctl status firewalld 2>&1 | head -10 || echo "Could not check firewall status"
    
    log_subsection "iptables Rules"
    iptables -L -n 2>/dev/null | head -50 || echo "Could not list iptables rules (may require root)"
    
    log_subsection "Listening Ports"
    ss -tlnp 2>/dev/null | grep -E "LISTEN|State" || netstat -tlnp 2>/dev/null | grep -E "LISTEN|Proto" || echo "Could not list listening ports"
    
    log_subsection "Azure NSG (from metadata)"
    echo "Note: Azure NSG rules are managed at the Azure portal level."
    echo "Use Azure CLI or portal to review NSG rules for this VM."
    if command -v az >/dev/null 2>&1; then
        # Try to get VM name from metadata
        VM_NAME=$(curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance/compute/name?api-version=2021-02-01&format=text" 2>/dev/null)
        RG_NAME=$(curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-02-01&format=text" 2>/dev/null)
        if [ -n "$VM_NAME" ] && [ -n "$RG_NAME" ]; then
            echo "VM Name: $VM_NAME"
            echo "Resource Group: $RG_NAME"
            echo ""
            echo "To view NSG rules, run:"
            echo "  az network nsg list -g $RG_NAME -o table"
        fi
    fi
    
    log_subsection "Oracle Net Security (sqlnet.ora)"
    for sqlnet_file in "$TNS_ADMIN/sqlnet.ora" "$ORACLE_HOME/network/admin/sqlnet.ora"; do
        if [ -f "$sqlnet_file" ]; then
            echo "Found: $sqlnet_file"
            grep -E "^(TCP|SQLNET|SSL)" "$sqlnet_file" 2>/dev/null || echo "No security-related entries found"
            break
        fi
    done
}

# =============================================================================
# JSON Summary Generation
# =============================================================================
generate_json_summary() {
    local db_name=$(run_sql_value "SELECT name FROM v\$database;" 2>/dev/null)
    local db_unique_name=$(run_sql_value "SELECT db_unique_name FROM v\$database;" 2>/dev/null)
    local dbid=$(run_sql_value "SELECT dbid FROM v\$database;" 2>/dev/null)
    local open_mode=$(run_sql_value "SELECT open_mode FROM v\$database;" 2>/dev/null)
    local database_role=$(run_sql_value "SELECT database_role FROM v\$database;" 2>/dev/null)
    local version=$(run_sql_value "SELECT version FROM v\$instance;" 2>/dev/null)
    local cdb=$(run_sql_value "SELECT cdb FROM v\$database;" 2>/dev/null)
    local tde_status=$(run_sql_value "SELECT status FROM v\$encryption_wallet WHERE ROWNUM = 1;" 2>/dev/null)
    local charset=$(run_sql_value "SELECT value FROM nls_database_parameters WHERE parameter = 'NLS_CHARACTERSET';" 2>/dev/null)
    local pdb_count=$(run_sql_value "SELECT COUNT(*) FROM v\$pdbs WHERE con_id > 2;" 2>/dev/null)
    
    cat > "$JSON_FILE" <<EOF
{
  "discovery_type": "target",
  "timestamp": "$TIMESTAMP",
  "hostname": "$HOSTNAME",
  "project": "PRODDB Migration to Oracle Database@Azure",
  "target_platform": "Oracle Database@Azure",
  "oracle_environment": {
    "oracle_home": "${ORACLE_HOME:-NOT SET}",
    "oracle_sid": "${ORACLE_SID:-NOT SET}",
    "oracle_base": "${ORACLE_BASE:-NOT SET}",
    "grid_home": "${GRID_HOME:-NOT SET}"
  },
  "database": {
    "name": "${db_name:-UNKNOWN}",
    "unique_name": "${db_unique_name:-UNKNOWN}",
    "dbid": "${dbid:-UNKNOWN}",
    "version": "${version:-UNKNOWN}",
    "open_mode": "${open_mode:-UNKNOWN}",
    "database_role": "${database_role:-UNKNOWN}",
    "is_cdb": "${cdb:-UNKNOWN}",
    "character_set": "${charset:-UNKNOWN}",
    "pdb_count": "${pdb_count:-0}"
  },
  "tde": {
    "wallet_status": "${tde_status:-NOT CONFIGURED}"
  },
  "section_errors": $SECTION_ERRORS
}
EOF
    echo "JSON summary saved to: $JSON_FILE"
}

# =============================================================================
# Main Execution
# =============================================================================
main() {
    echo "================================================================================"
    echo " ZDM Target Database Discovery"
    echo " Project: PRODDB Migration to Oracle Database@Azure"
    echo " Server: proddb-oda.eastus.azure.example.com"
    echo " Timestamp: $(date)"
    echo "================================================================================"
    
    # Run all discovery sections with error handling
    {
        discover_os_info || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_oracle_env || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_database_config || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_storage || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_cdb_pdb || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_tde || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_network || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_oci_azure || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_grid_infrastructure || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_authentication || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        
        # Additional custom discovery for PRODDB (Oracle Database@Azure)
        discover_exadata_storage || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_preconfigured_pdbs || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_network_security || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        
    } 2>&1 | tee "$OUTPUT_FILE"
    
    # Generate JSON summary
    generate_json_summary
    
    echo ""
    echo "================================================================================"
    echo " DISCOVERY COMPLETE"
    echo "================================================================================"
    echo " Text report: $OUTPUT_FILE"
    echo " JSON summary: $JSON_FILE"
    echo " Sections with errors: $SECTION_ERRORS"
    echo "================================================================================"
}

# Run main
main

# Always exit 0 so orchestrator knows script completed
exit 0
