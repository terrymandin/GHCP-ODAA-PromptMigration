#!/bin/bash
###############################################################################
# ZDM Target Database Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# Target: proddb-oda.eastus.azure.example.com
# 
# Purpose: Discover target Oracle Database@Azure configuration for ZDM migration
# Run as: opc or oracle user on target database server
#
# Generated: 2026-01-29
###############################################################################

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Get hostname and timestamp for output files
HOSTNAME=$(hostname -s 2>/dev/null || hostname)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="./zdm_target_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_target_discovery_${HOSTNAME}_${TIMESTAMP}.json"

# Initialize JSON structure
declare -A JSON_DATA

###############################################################################
# Environment Variable Sourcing with Fallback
###############################################################################
source_environment() {
    echo -e "${BLUE}=== Sourcing Oracle Environment ===${NC}"
    
    # Method 1: Use explicit overrides if provided (passed via environment)
    if [ -n "${ORACLE_HOME_OVERRIDE:-}" ]; then
        export ORACLE_HOME="$ORACLE_HOME_OVERRIDE"
        echo -e "${GREEN}Using explicit ORACLE_HOME override: $ORACLE_HOME${NC}"
    fi
    if [ -n "${ORACLE_SID_OVERRIDE:-}" ]; then
        export ORACLE_SID="$ORACLE_SID_OVERRIDE"
        echo -e "${GREEN}Using explicit ORACLE_SID override: $ORACLE_SID${NC}"
    fi
    
    # Method 2: Source profiles - extract export statements
    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        for profile in /etc/profile ~/.bash_profile ~/.bashrc ~/.profile; do
            if [ -f "$profile" ]; then
                eval "$(grep -E '^export\s+' "$profile" 2>/dev/null)" || true
            fi
        done
    fi
    
    # Method 3: Try oraenv if available
    if [ -z "${ORACLE_HOME:-}" ] && [ -f /usr/local/bin/oraenv ]; then
        ORAENV_ASK=NO
        . /usr/local/bin/oraenv 2>/dev/null || true
    fi
    
    # Method 4: Search common Oracle installation locations (ODA specific)
    if [ -z "${ORACLE_HOME:-}" ]; then
        for oh in /u01/app/oracle/product/*/dbhome_1 /u02/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1; do
            if [ -d "$oh" ]; then
                export ORACLE_HOME="$oh"
                echo -e "${YELLOW}Auto-detected ORACLE_HOME: $ORACLE_HOME${NC}"
                break
            fi
        done
    fi
    
    # Set PATH if ORACLE_HOME is found
    if [ -n "${ORACLE_HOME:-}" ]; then
        export PATH=$ORACLE_HOME/bin:$PATH
        export LD_LIBRARY_PATH=$ORACLE_HOME/lib:${LD_LIBRARY_PATH:-}
    fi
    
    echo "ORACLE_HOME: ${ORACLE_HOME:-NOT SET}"
    echo "ORACLE_SID: ${ORACLE_SID:-NOT SET}"
    echo "ORACLE_BASE: ${ORACLE_BASE:-NOT SET}"
}

###############################################################################
# Helper Functions
###############################################################################
print_header() {
    local title="$1"
    echo ""
    echo -e "${CYAN}===============================================================================${NC}"
    echo -e "${CYAN}  $title${NC}"
    echo -e "${CYAN}===============================================================================${NC}"
    echo ""
}

print_section() {
    local title="$1"
    echo ""
    echo -e "${YELLOW}--- $title ---${NC}"
}

run_sql() {
    local sql="$1"
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        $ORACLE_HOME/bin/sqlplus -S "/ as sysdba" <<EOF
SET PAGESIZE 0
SET LINESIZE 200
SET FEEDBACK OFF
SET HEADING OFF
SET TRIMSPOOL ON
$sql
EOF
    else
        echo "ERROR: Oracle environment not set"
        return 1
    fi
}

run_sql_with_headers() {
    local sql="$1"
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        $ORACLE_HOME/bin/sqlplus -S "/ as sysdba" <<EOF
SET PAGESIZE 1000
SET LINESIZE 200
SET FEEDBACK OFF
SET HEADING ON
SET TRIMSPOOL ON
COLUMN name FORMAT A40
COLUMN value FORMAT A80
$sql
EOF
    else
        echo "ERROR: Oracle environment not set"
        return 1
    fi
}

###############################################################################
# Discovery Functions
###############################################################################

discover_os_info() {
    print_header "OS INFORMATION"
    
    print_section "Hostname and IP Addresses"
    echo "Hostname: $(hostname)"
    echo "FQDN: $(hostname -f 2>/dev/null || echo 'N/A')"
    echo ""
    echo "IP Addresses:"
    ip addr show 2>/dev/null | grep 'inet ' | awk '{print "  " $2}' || ifconfig 2>/dev/null | grep 'inet ' | awk '{print "  " $2}'
    
    print_section "Operating System Version"
    if [ -f /etc/os-release ]; then
        cat /etc/os-release
    elif [ -f /etc/oracle-release ]; then
        cat /etc/oracle-release
    elif [ -f /etc/redhat-release ]; then
        cat /etc/redhat-release
    else
        uname -a
    fi
    
    JSON_DATA["hostname"]=$(hostname)
    JSON_DATA["os_version"]=$(cat /etc/oracle-release 2>/dev/null || cat /etc/redhat-release 2>/dev/null || uname -r)
}

discover_oracle_environment() {
    print_header "ORACLE ENVIRONMENT"
    
    print_section "Oracle Environment Variables"
    echo "ORACLE_HOME: ${ORACLE_HOME:-NOT SET}"
    echo "ORACLE_SID: ${ORACLE_SID:-NOT SET}"
    echo "ORACLE_BASE: ${ORACLE_BASE:-NOT SET}"
    
    print_section "Oracle Version"
    if [ -n "${ORACLE_HOME:-}" ]; then
        $ORACLE_HOME/bin/sqlplus -V 2>/dev/null || echo "Unable to determine version"
    else
        echo "ORACLE_HOME not set"
    fi
    
    JSON_DATA["oracle_home"]="${ORACLE_HOME:-}"
    JSON_DATA["oracle_sid"]="${ORACLE_SID:-}"
}

discover_database_config() {
    print_header "DATABASE CONFIGURATION"
    
    print_section "Database Instance Information"
    run_sql_with_headers "
SELECT name, db_unique_name, dbid, database_role, open_mode, log_mode
FROM v\$database;
"
    
    local db_info=$(run_sql "SELECT name||','||db_unique_name||','||database_role||','||open_mode FROM v\$database;")
    JSON_DATA["db_name"]=$(echo "$db_info" | cut -d',' -f1)
    JSON_DATA["db_unique_name"]=$(echo "$db_info" | cut -d',' -f2)
    JSON_DATA["database_role"]=$(echo "$db_info" | cut -d',' -f3)
    JSON_DATA["open_mode"]=$(echo "$db_info" | cut -d',' -f4)
    
    print_section "Available Tablespaces"
    run_sql_with_headers "
SELECT tablespace_name, 
       ROUND(SUM(bytes)/1024/1024/1024, 2) AS size_gb,
       ROUND(SUM(maxbytes)/1024/1024/1024, 2) AS max_size_gb,
       status
FROM dba_data_files
GROUP BY tablespace_name, status
ORDER BY tablespace_name;
"
    
    print_section "Character Set"
    run_sql_with_headers "
SELECT parameter, value FROM nls_database_parameters
WHERE parameter IN ('NLS_CHARACTERSET', 'NLS_NCHAR_CHARACTERSET');
"
    
    local charset=$(run_sql "SELECT value FROM nls_database_parameters WHERE parameter='NLS_CHARACTERSET';")
    JSON_DATA["character_set"]=$(echo "$charset" | tr -d ' ')
}

discover_cdb_pdb() {
    print_header "CONTAINER DATABASE CONFIGURATION"
    
    print_section "CDB Status"
    local cdb_status=$(run_sql "SELECT CDB FROM v\$database;")
    echo "CDB: $cdb_status"
    JSON_DATA["is_cdb"]=$(echo "$cdb_status" | tr -d ' ')
    
    if [[ "$cdb_status" == *"YES"* ]]; then
        print_section "PDB Information"
        run_sql_with_headers "
SELECT pdb_id, pdb_name, status, open_mode
FROM cdb_pdbs
ORDER BY pdb_id;
"
        
        print_section "PDB Sizes"
        run_sql_with_headers "
SELECT con_id, ROUND(SUM(bytes)/1024/1024/1024, 2) AS size_gb
FROM cdb_data_files
GROUP BY con_id
ORDER BY con_id;
"
    else
        echo "Non-CDB database detected"
    fi
}

discover_tde_config() {
    print_header "TDE/WALLET CONFIGURATION"
    
    print_section "TDE Status"
    run_sql_with_headers "
SELECT con_id, wallet_type, status, wallet_order
FROM v\$encryption_wallet;
"
    
    print_section "Wallet Location"
    run_sql "SELECT value FROM v\$parameter WHERE name = 'wallet_root';"
    
    local tde_status=$(run_sql "SELECT status FROM v\$encryption_wallet WHERE ROWNUM = 1;")
    JSON_DATA["tde_status"]=$(echo "$tde_status" | tr -d ' ')
}

discover_network_config() {
    print_header "NETWORK CONFIGURATION"
    
    print_section "Listener Status"
    if [ -n "${ORACLE_HOME:-}" ]; then
        $ORACLE_HOME/bin/lsnrctl status 2>/dev/null || echo "Unable to get listener status"
    fi
    
    print_section "SCAN Listener (if RAC)"
    if [ -n "${GRID_HOME:-}" ]; then
        $GRID_HOME/bin/srvctl status scan_listener 2>/dev/null || echo "Not a RAC configuration or unable to check"
    else
        # Try common Grid Infrastructure locations
        for gh in /u01/app/grid /u01/app/19.0.0.0/grid; do
            if [ -d "$gh" ] && [ -x "$gh/bin/srvctl" ]; then
                $gh/bin/srvctl status scan_listener 2>/dev/null || echo "SCAN listener check failed"
                break
            fi
        done
    fi
    
    print_section "tnsnames.ora"
    if [ -f "${ORACLE_HOME}/network/admin/tnsnames.ora" ]; then
        cat "${ORACLE_HOME}/network/admin/tnsnames.ora"
    elif [ -f "${TNS_ADMIN:-}/tnsnames.ora" ]; then
        cat "${TNS_ADMIN}/tnsnames.ora"
    else
        echo "tnsnames.ora not found"
    fi
}

discover_oci_azure_integration() {
    print_header "OCI/AZURE INTEGRATION"
    
    print_section "OCI CLI Version"
    oci --version 2>/dev/null || echo "OCI CLI not installed or not in PATH"
    
    print_section "OCI Configuration"
    if [ -f ~/.oci/config ]; then
        echo "OCI config file found at ~/.oci/config"
        echo "Configured profiles:"
        grep '^\[' ~/.oci/config 2>/dev/null || echo "Unable to read profiles"
    else
        echo "OCI config file not found"
    fi
    
    print_section "OCI Connectivity Test"
    oci iam region list --output table 2>/dev/null | head -20 || echo "Unable to connect to OCI or OCI CLI not configured"
    
    print_section "Instance Metadata (OCI)"
    curl -s -H "Authorization: Bearer Oracle" http://169.254.169.254/opc/v2/instance/ 2>/dev/null | head -50 || echo "Unable to retrieve OCI instance metadata"
    
    print_section "Instance Metadata (Azure)"
    curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" 2>/dev/null | head -50 || echo "Unable to retrieve Azure instance metadata"
}

discover_grid_infrastructure() {
    print_header "GRID INFRASTRUCTURE (if RAC)"
    
    print_section "CRS Status"
    for gh in /u01/app/grid /u01/app/19.0.0.0/grid ${GRID_HOME:-}; do
        if [ -d "$gh" ] && [ -x "$gh/bin/crsctl" ]; then
            echo "Grid Home found at: $gh"
            $gh/bin/crsctl stat res -t 2>/dev/null || echo "Unable to get CRS status"
            break
        fi
    done
    
    if [ ! -x "${GRID_HOME:-}/bin/crsctl" ]; then
        echo "Grid Infrastructure not detected or not accessible"
    fi
}

discover_authentication() {
    print_header "AUTHENTICATION CONFIGURATION"
    
    print_section "SSH Directory Contents"
    ls -la ~/.ssh/ 2>/dev/null || echo "No .ssh directory found"
}

###############################################################################
# ADDITIONAL DISCOVERY - Custom for PRODDB Migration (Oracle Database@Azure)
###############################################################################

discover_exadata_storage() {
    print_header "EXADATA STORAGE CAPACITY"
    
    print_section "ASM Diskgroups"
    run_sql_with_headers "
SELECT name, 
       type,
       ROUND(total_mb/1024, 2) AS total_gb,
       ROUND(free_mb/1024, 2) AS free_gb,
       ROUND((total_mb - free_mb)/total_mb * 100, 2) AS used_pct,
       state
FROM v\$asm_diskgroup
ORDER BY name;
"
    
    print_section "ASM Disk Detail"
    run_sql_with_headers "
SELECT dg.name AS diskgroup,
       COUNT(d.disk_number) AS disk_count,
       ROUND(SUM(d.total_mb)/1024, 2) AS total_gb,
       ROUND(SUM(d.free_mb)/1024, 2) AS free_gb
FROM v\$asm_diskgroup dg
JOIN v\$asm_disk d ON dg.group_number = d.group_number
GROUP BY dg.name
ORDER BY dg.name;
"
    
    print_section "Database File Distribution by Diskgroup"
    run_sql_with_headers "
SELECT SUBSTR(name, 1, INSTR(name, '/', 1, 2)-1) AS diskgroup,
       ROUND(SUM(bytes)/1024/1024/1024, 2) AS size_gb,
       COUNT(*) AS file_count
FROM v\$datafile
GROUP BY SUBSTR(name, 1, INSTR(name, '/', 1, 2)-1)
ORDER BY 1;
"
}

discover_preconfigured_pdbs() {
    print_header "PRE-CONFIGURED PDBS"
    
    print_section "PDB Details"
    run_sql_with_headers "
SELECT p.pdb_id, 
       p.pdb_name, 
       p.status,
       p.open_mode,
       TO_CHAR(p.creation_time, 'YYYY-MM-DD HH24:MI:SS') AS created,
       ROUND(
           (SELECT SUM(bytes)/1024/1024/1024 
            FROM cdb_data_files df 
            WHERE df.con_id = p.con_id), 2
       ) AS size_gb
FROM v\$pdbs p
ORDER BY p.pdb_id;
"
    
    print_section "PDB Services"
    run_sql_with_headers "
SELECT con_id, name, pdb AS pdb_name
FROM v\$services
WHERE con_id > 1
ORDER BY con_id, name;
"
    
    print_section "PDB Tablespaces"
    run_sql_with_headers "
SELECT con_id, tablespace_name, 
       ROUND(SUM(bytes)/1024/1024/1024, 2) AS size_gb,
       status
FROM cdb_data_files
GROUP BY con_id, tablespace_name, status
ORDER BY con_id, tablespace_name;
"
}

discover_network_security_groups() {
    print_header "NETWORK SECURITY GROUP RULES"
    
    print_section "Current Firewall Rules (iptables)"
    sudo iptables -L -n 2>/dev/null || iptables -L -n 2>/dev/null || echo "Unable to list iptables rules (may require sudo)"
    
    print_section "Current Firewall Rules (firewalld)"
    sudo firewall-cmd --list-all 2>/dev/null || firewall-cmd --list-all 2>/dev/null || echo "firewalld not active or unable to query"
    
    print_section "Listening Ports"
    ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null || echo "Unable to list listening ports"
    
    print_section "Oracle Net Ports"
    echo "Checking common Oracle ports..."
    for port in 1521 1522 1523 1525 5500 5501; do
        if ss -tln 2>/dev/null | grep -q ":$port "; then
            echo "Port $port: LISTENING"
        elif netstat -tln 2>/dev/null | grep -q ":$port "; then
            echo "Port $port: LISTENING"
        else
            echo "Port $port: not listening"
        fi
    done
    
    print_section "Azure NSG Rules (via Instance Metadata)"
    echo "Note: Full NSG rules must be verified in Azure Portal"
    echo "Checking if Azure metadata is available..."
    curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance/network?api-version=2021-02-01" 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "Azure metadata not available or not parseable"
}

###############################################################################
# Generate JSON Output
###############################################################################
generate_json() {
    cat > "$JSON_FILE" <<EOF
{
    "discovery_type": "target_database",
    "project": "PRODDB Migration to Oracle Database@Azure",
    "platform": "Oracle Database@Azure",
    "timestamp": "$(date -Iseconds)",
    "hostname": "${JSON_DATA["hostname"]:-}",
    "os_version": "${JSON_DATA["os_version"]:-}",
    "oracle_home": "${JSON_DATA["oracle_home"]:-}",
    "oracle_sid": "${JSON_DATA["oracle_sid"]:-}",
    "database": {
        "name": "${JSON_DATA["db_name"]:-}",
        "unique_name": "${JSON_DATA["db_unique_name"]:-}",
        "role": "${JSON_DATA["database_role"]:-}",
        "open_mode": "${JSON_DATA["open_mode"]:-}",
        "character_set": "${JSON_DATA["character_set"]:-}",
        "is_cdb": "${JSON_DATA["is_cdb"]:-}",
        "tde_status": "${JSON_DATA["tde_status"]:-}"
    },
    "discovery_complete": true
}
EOF
}

###############################################################################
# Main Execution
###############################################################################
main() {
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     ZDM Target Database Discovery Script                                 ║${NC}"
    echo -e "${GREEN}║     Project: PRODDB Migration to Oracle Database@Azure                  ║${NC}"
    echo -e "${GREEN}║     Target Platform: Oracle Database@Azure                              ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Discovery started at: $(date)"
    echo "Output files will be saved to current directory:"
    echo "  Text Report: $OUTPUT_FILE"
    echo "  JSON Summary: $JSON_FILE"
    echo ""
    
    # Source Oracle environment
    source_environment
    
    # Redirect all output to both terminal and file
    {
        echo "=================================================================="
        echo "ZDM Target Database Discovery Report"
        echo "Project: PRODDB Migration to Oracle Database@Azure"
        echo "Platform: Oracle Database@Azure"
        echo "Generated: $(date)"
        echo "Hostname: $(hostname)"
        echo "=================================================================="
        
        # Run all discovery functions with error trapping
        discover_os_info || echo -e "${RED}WARNING: OS info discovery failed${NC}"
        discover_oracle_environment || echo -e "${RED}WARNING: Oracle environment discovery failed${NC}"
        discover_database_config || echo -e "${RED}WARNING: Database config discovery failed${NC}"
        discover_cdb_pdb || echo -e "${RED}WARNING: CDB/PDB discovery failed${NC}"
        discover_tde_config || echo -e "${RED}WARNING: TDE config discovery failed${NC}"
        discover_network_config || echo -e "${RED}WARNING: Network config discovery failed${NC}"
        discover_oci_azure_integration || echo -e "${RED}WARNING: OCI/Azure integration discovery failed${NC}"
        discover_grid_infrastructure || echo -e "${RED}WARNING: Grid Infrastructure discovery failed${NC}"
        discover_authentication || echo -e "${RED}WARNING: Authentication discovery failed${NC}"
        
        # Additional discovery for Oracle Database@Azure
        discover_exadata_storage || echo -e "${RED}WARNING: Exadata storage discovery failed${NC}"
        discover_preconfigured_pdbs || echo -e "${RED}WARNING: Pre-configured PDBs discovery failed${NC}"
        discover_network_security_groups || echo -e "${RED}WARNING: Network security groups discovery failed${NC}"
        
        echo ""
        echo "=================================================================="
        echo "Discovery completed at: $(date)"
        echo "=================================================================="
        
    } 2>&1 | tee "$OUTPUT_FILE"
    
    # Generate JSON output
    generate_json
    
    echo ""
    echo -e "${GREEN}Discovery complete!${NC}"
    echo "Text Report: $OUTPUT_FILE"
    echo "JSON Summary: $JSON_FILE"
}

# Run main function
main "$@"
