#!/bin/bash
#===============================================================================
# ZDM Target Database Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# Target: proddb-oda.eastus.azure.example.com
# Generated: 2026-01-29
#===============================================================================
# Usage: ./zdm_target_discovery.sh
# Run as: opc or oracle user
# Output: Text report and JSON summary in /tmp/
#===============================================================================

# Exit on error
set -e

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname -s)
OUTPUT_FILE="/tmp/zdm_target_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_FILE="/tmp/zdm_target_discovery_${HOSTNAME}_${TIMESTAMP}.json"

#-------------------------------------------------------------------------------
# Color Codes
#-------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#-------------------------------------------------------------------------------
# Utility Functions
#-------------------------------------------------------------------------------
log_header() {
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BLUE}= $1${NC}"
    echo -e "${BLUE}================================================================${NC}"
    echo ""
}

log_section() {
    echo -e "\n${GREEN}--- $1 ---${NC}"
    echo "=== $1 ===" >> "$OUTPUT_FILE"
}

log_info() {
    echo -e "${NC}$1${NC}"
    echo "$1" >> "$OUTPUT_FILE"
}

log_warn() {
    echo -e "${YELLOW}WARNING: $1${NC}"
    echo "WARNING: $1" >> "$OUTPUT_FILE"
}

log_error() {
    echo -e "${RED}ERROR: $1${NC}"
    echo "ERROR: $1" >> "$OUTPUT_FILE"
}

run_sql() {
    local sql="$1"
    sqlplus -s / as sysdba <<EOF
SET PAGESIZE 1000
SET LINESIZE 300
SET FEEDBACK OFF
SET HEADING ON
SET TRIMSPOOL ON
COLUMN value FORMAT a80
COLUMN name FORMAT a50
$sql
EXIT;
EOF
}

run_sql_to_file() {
    local sql="$1"
    run_sql "$sql" >> "$OUTPUT_FILE" 2>&1
}

#-------------------------------------------------------------------------------
# Initialize Output Files
#-------------------------------------------------------------------------------
log_header "ZDM Target Database Discovery (Oracle Database@Azure)"
echo "================================================================" > "$OUTPUT_FILE"
echo "= ZDM Target Database Discovery Report" >> "$OUTPUT_FILE"
echo "= Project: PRODDB Migration to Oracle Database@Azure" >> "$OUTPUT_FILE"
echo "= Host: $HOSTNAME" >> "$OUTPUT_FILE"
echo "= Date: $(date)" >> "$OUTPUT_FILE"
echo "================================================================" >> "$OUTPUT_FILE"

# Initialize JSON
echo "{" > "$JSON_FILE"
echo "  \"discovery_type\": \"target\"," >> "$JSON_FILE"
echo "  \"project\": \"PRODDB Migration to Oracle Database@Azure\"," >> "$JSON_FILE"
echo "  \"hostname\": \"$HOSTNAME\"," >> "$JSON_FILE"
echo "  \"timestamp\": \"$(date -Iseconds)\"," >> "$JSON_FILE"

#-------------------------------------------------------------------------------
# OS Information
#-------------------------------------------------------------------------------
log_section "OS INFORMATION"
echo "" >> "$OUTPUT_FILE"

echo "Hostname: $(hostname)" >> "$OUTPUT_FILE"
echo "Hostname FQDN: $(hostname -f 2>/dev/null || echo 'N/A')" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "IP Addresses:" >> "$OUTPUT_FILE"
ip addr show 2>/dev/null | grep "inet " | awk '{print "  " $2}' >> "$OUTPUT_FILE" || hostname -I >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Operating System:" >> "$OUTPUT_FILE"
cat /etc/os-release 2>/dev/null | head -5 >> "$OUTPUT_FILE" || uname -a >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Kernel Version:" >> "$OUTPUT_FILE"
uname -r >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

log_section "DISK SPACE"
df -h >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# JSON: OS Info
echo "  \"os\": {" >> "$JSON_FILE"
echo "    \"hostname\": \"$(hostname)\"," >> "$JSON_FILE"
echo "    \"kernel\": \"$(uname -r)\"," >> "$JSON_FILE"
echo "    \"os_release\": \"$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"' || uname -s)\"" >> "$JSON_FILE"
echo "  }," >> "$JSON_FILE"

#-------------------------------------------------------------------------------
# Oracle Environment
#-------------------------------------------------------------------------------
log_section "ORACLE ENVIRONMENT"
echo "" >> "$OUTPUT_FILE"

echo "ORACLE_HOME: ${ORACLE_HOME:-NOT SET}" >> "$OUTPUT_FILE"
echo "ORACLE_SID: ${ORACLE_SID:-NOT SET}" >> "$OUTPUT_FILE"
echo "ORACLE_BASE: ${ORACLE_BASE:-NOT SET}" >> "$OUTPUT_FILE"
echo "GRID_HOME: ${GRID_HOME:-NOT SET}" >> "$OUTPUT_FILE"
echo "TNS_ADMIN: ${TNS_ADMIN:-NOT SET}" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Oracle Version:" >> "$OUTPUT_FILE"
if [ -n "$ORACLE_HOME" ] && [ -f "$ORACLE_HOME/bin/sqlplus" ]; then
    $ORACLE_HOME/bin/sqlplus -v 2>/dev/null >> "$OUTPUT_FILE" || echo "Unable to get version" >> "$OUTPUT_FILE"
else
    echo "ORACLE_HOME not set or sqlplus not found" >> "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

# Check for oraenv and list available databases
echo "Available Oracle Databases (from /etc/oratab):" >> "$OUTPUT_FILE"
cat /etc/oratab 2>/dev/null | grep -v "^#" | grep -v "^$" >> "$OUTPUT_FILE" || echo "Unable to read /etc/oratab" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# JSON: Oracle Environment
echo "  \"oracle_env\": {" >> "$JSON_FILE"
echo "    \"oracle_home\": \"${ORACLE_HOME:-NOT SET}\"," >> "$JSON_FILE"
echo "    \"oracle_sid\": \"${ORACLE_SID:-NOT SET}\"," >> "$JSON_FILE"
echo "    \"oracle_base\": \"${ORACLE_BASE:-NOT SET}\"," >> "$JSON_FILE"
echo "    \"grid_home\": \"${GRID_HOME:-NOT SET}\"" >> "$JSON_FILE"
echo "  }," >> "$JSON_FILE"

#-------------------------------------------------------------------------------
# Database Configuration
#-------------------------------------------------------------------------------
log_section "DATABASE CONFIGURATION"
echo "" >> "$OUTPUT_FILE"

echo "Database Instance Information:" >> "$OUTPUT_FILE"
run_sql_to_file "
SELECT name as db_name, 
       db_unique_name, 
       dbid,
       database_role,
       open_mode,
       log_mode,
       created
FROM v\$database;
"
echo "" >> "$OUTPUT_FILE"

echo "Database Version:" >> "$OUTPUT_FILE"
run_sql_to_file "SELECT banner_full FROM v\$version WHERE banner_full IS NOT NULL;"
echo "" >> "$OUTPUT_FILE"

echo "Character Set:" >> "$OUTPUT_FILE"
run_sql_to_file "
SELECT parameter, value 
FROM nls_database_parameters 
WHERE parameter IN ('NLS_CHARACTERSET', 'NLS_NCHAR_CHARACTERSET', 'NLS_LANGUAGE', 'NLS_TERRITORY');
"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Storage - Tablespaces and ASM
#-------------------------------------------------------------------------------
log_section "STORAGE CONFIGURATION"
echo "" >> "$OUTPUT_FILE"

echo "Tablespace Usage:" >> "$OUTPUT_FILE"
run_sql_to_file "
SELECT tablespace_name,
       ROUND(SUM(bytes)/1024/1024/1024, 2) as size_gb,
       ROUND(SUM(maxbytes)/1024/1024/1024, 2) as maxsize_gb
FROM dba_data_files
GROUP BY tablespace_name
ORDER BY tablespace_name;
"
echo "" >> "$OUTPUT_FILE"

echo "ASM Disk Groups (if applicable):" >> "$OUTPUT_FILE"
run_sql_to_file "
SELECT name, type, state, 
       ROUND(total_mb/1024, 2) as total_gb,
       ROUND(free_mb/1024, 2) as free_gb,
       ROUND((total_mb - free_mb)/total_mb * 100, 2) as pct_used
FROM v\$asm_diskgroup;
" 2>/dev/null || echo "ASM not configured or not accessible" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Container Database
#-------------------------------------------------------------------------------
log_section "CONTAINER DATABASE STATUS"
echo "" >> "$OUTPUT_FILE"

run_sql_to_file "SELECT cdb FROM v\$database;"
echo "" >> "$OUTPUT_FILE"

echo "PDB Information (if CDB):" >> "$OUTPUT_FILE"
run_sql_to_file "
SELECT con_id, name, open_mode, restricted, 
       ROUND(total_size/1024/1024/1024, 2) as size_gb
FROM v\$pdbs
ORDER BY con_id;
" 2>/dev/null || echo "Not a CDB or no PDBs found" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# TDE/Wallet Status
#-------------------------------------------------------------------------------
log_section "TDE/WALLET STATUS"
echo "" >> "$OUTPUT_FILE"

echo "Wallet Status:" >> "$OUTPUT_FILE"
run_sql_to_file "SELECT * FROM v\$encryption_wallet;"
echo "" >> "$OUTPUT_FILE"

echo "Wallet Location:" >> "$OUTPUT_FILE"
run_sql_to_file "
SELECT wrl_type, wrl_parameter, status, wallet_type
FROM v\$encryption_wallet;
"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Network Configuration
#-------------------------------------------------------------------------------
log_section "NETWORK CONFIGURATION"
echo "" >> "$OUTPUT_FILE"

echo "Listener Status:" >> "$OUTPUT_FILE"
lsnrctl status >> "$OUTPUT_FILE" 2>&1 || echo "Unable to get listener status" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "SCAN Listener (if RAC):" >> "$OUTPUT_FILE"
srvctl status scan_listener 2>&1 >> "$OUTPUT_FILE" || echo "Not a RAC configuration or srvctl not available" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "tnsnames.ora:" >> "$OUTPUT_FILE"
if [ -n "$TNS_ADMIN" ] && [ -f "$TNS_ADMIN/tnsnames.ora" ]; then
    cat "$TNS_ADMIN/tnsnames.ora" >> "$OUTPUT_FILE"
elif [ -n "$ORACLE_HOME" ] && [ -f "$ORACLE_HOME/network/admin/tnsnames.ora" ]; then
    cat "$ORACLE_HOME/network/admin/tnsnames.ora" >> "$OUTPUT_FILE"
else
    echo "tnsnames.ora not found" >> "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# OCI/Azure Integration
#-------------------------------------------------------------------------------
log_section "OCI/AZURE INTEGRATION"
echo "" >> "$OUTPUT_FILE"

echo "OCI CLI Version:" >> "$OUTPUT_FILE"
oci --version 2>&1 >> "$OUTPUT_FILE" || echo "OCI CLI not installed or not in PATH" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "OCI Configuration:" >> "$OUTPUT_FILE"
if [ -f ~/.oci/config ]; then
    echo "OCI config file found at ~/.oci/config" >> "$OUTPUT_FILE"
    # Show profiles without sensitive data
    grep "^\[" ~/.oci/config >> "$OUTPUT_FILE" 2>/dev/null || true
    grep "^region" ~/.oci/config >> "$OUTPUT_FILE" 2>/dev/null || true
else
    echo "OCI config file not found" >> "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

echo "OCI Connectivity Test:" >> "$OUTPUT_FILE"
oci iam region list --query "data[0].name" 2>&1 >> "$OUTPUT_FILE" || echo "OCI connectivity test failed" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Instance Metadata (OCI):" >> "$OUTPUT_FILE"
curl -s -H "Authorization: Bearer Oracle" http://169.254.169.254/opc/v2/instance/ 2>/dev/null | head -20 >> "$OUTPUT_FILE" || echo "Unable to retrieve OCI instance metadata" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Instance Metadata (Azure):" >> "$OUTPUT_FILE"
curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" 2>/dev/null | head -20 >> "$OUTPUT_FILE" || echo "Unable to retrieve Azure instance metadata" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Grid Infrastructure (if RAC)
#-------------------------------------------------------------------------------
log_section "GRID INFRASTRUCTURE"
echo "" >> "$OUTPUT_FILE"

echo "CRS Status:" >> "$OUTPUT_FILE"
if [ -n "$GRID_HOME" ]; then
    $GRID_HOME/bin/crsctl stat res -t 2>&1 >> "$OUTPUT_FILE" || echo "Unable to get CRS status" >> "$OUTPUT_FILE"
else
    crsctl stat res -t 2>&1 >> "$OUTPUT_FILE" || echo "Grid Infrastructure not configured or crsctl not available" >> "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

echo "Cluster Nodes:" >> "$OUTPUT_FILE"
olsnodes 2>&1 >> "$OUTPUT_FILE" || echo "Not a RAC configuration" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Authentication
#-------------------------------------------------------------------------------
log_section "AUTHENTICATION"
echo "" >> "$OUTPUT_FILE"

echo "SSH Directory Contents:" >> "$OUTPUT_FILE"
ls -la ~/.ssh/ 2>/dev/null >> "$OUTPUT_FILE" || echo "No .ssh directory found" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# ADDITIONAL CUSTOM DISCOVERY - Oracle Database@Azure Specific
#-------------------------------------------------------------------------------
log_section "EXADATA STORAGE CAPACITY"
echo "" >> "$OUTPUT_FILE"

echo "Exadata Cell Disk Information:" >> "$OUTPUT_FILE"
run_sql_to_file "
SELECT cell_path, cell_name, 
       ROUND(total_mb/1024, 2) as total_gb,
       ROUND(free_mb/1024, 2) as free_gb
FROM v\$asm_disk
ORDER BY cell_name;
" 2>/dev/null || echo "Exadata cell information not available" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "ASM Disk Group Free Space:" >> "$OUTPUT_FILE"
run_sql_to_file "
SELECT name as diskgroup_name, 
       type,
       ROUND(total_mb/1024, 2) as total_gb,
       ROUND(free_mb/1024, 2) as free_gb,
       ROUND(usable_file_mb/1024, 2) as usable_gb,
       ROUND((1 - free_mb/total_mb) * 100, 2) as pct_used
FROM v\$asm_diskgroup
ORDER BY name;
" 2>/dev/null || echo "ASM not configured" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

log_section "PRE-CONFIGURED PDBs"
echo "" >> "$OUTPUT_FILE"

run_sql_to_file "
SELECT pdb_id, pdb_name, status, 
       con_id, con_uid,
       TO_CHAR(creation_time, 'YYYY-MM-DD HH24:MI:SS') as created,
       ROUND(total_size/1024/1024/1024, 2) as size_gb
FROM cdb_pdbs
ORDER BY pdb_id;
" 2>/dev/null || echo "Not a CDB or PDB information not available" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "PDB Services:" >> "$OUTPUT_FILE"
run_sql_to_file "
SELECT pdb, name as service_name, network_name, enabled
FROM cdb_services
WHERE pdb IS NOT NULL
ORDER BY pdb, name;
" 2>/dev/null || echo "PDB services information not available" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

log_section "NETWORK SECURITY GROUP RULES"
echo "" >> "$OUTPUT_FILE"

echo "Note: NSG rules should be checked via Azure Portal or Azure CLI" >> "$OUTPUT_FILE"
echo "Checking local firewall rules (iptables):" >> "$OUTPUT_FILE"
sudo iptables -L -n 2>&1 >> "$OUTPUT_FILE" || echo "Unable to list iptables rules (may require sudo)" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Checking firewalld (if active):" >> "$OUTPUT_FILE"
sudo firewall-cmd --list-all 2>&1 >> "$OUTPUT_FILE" || echo "firewalld not available or not running" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Listening Ports:" >> "$OUTPUT_FILE"
ss -tlnp 2>/dev/null >> "$OUTPUT_FILE" || netstat -tlnp 2>/dev/null >> "$OUTPUT_FILE" || echo "Unable to list listening ports" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Finalize JSON Output
#-------------------------------------------------------------------------------
echo "  \"discovery_complete\": true" >> "$JSON_FILE"
echo "}" >> "$JSON_FILE"

#-------------------------------------------------------------------------------
# Summary
#-------------------------------------------------------------------------------
log_section "DISCOVERY COMPLETE"
echo "" >> "$OUTPUT_FILE"
echo "Output Files:" >> "$OUTPUT_FILE"
echo "  Text Report: $OUTPUT_FILE" >> "$OUTPUT_FILE"
echo "  JSON Summary: $JSON_FILE" >> "$OUTPUT_FILE"

echo ""
echo -e "${GREEN}================================================================${NC}"
echo -e "${GREEN}= Target Discovery Complete (Oracle Database@Azure)${NC}"
echo -e "${GREEN}================================================================${NC}"
echo -e "Text Report: ${BLUE}$OUTPUT_FILE${NC}"
echo -e "JSON Summary: ${BLUE}$JSON_FILE${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Review the discovery report"
echo "2. Copy output files to the ZDM server"
echo "3. Verify NSG rules via Azure Portal"
echo ""
