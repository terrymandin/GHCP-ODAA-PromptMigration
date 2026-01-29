#!/bin/bash
#===============================================================================
# ZDM Target Database Discovery Script (Oracle Database@Azure)
# Project: PRODDB Migration to Oracle Database@Azure
# Target Server: proddb-oda.eastus.azure.example.com
# Generated: 2026-01-29
#===============================================================================

set -e

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script variables
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname)
OUTPUT_FILE="/tmp/zdm_target_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_FILE="/tmp/zdm_target_discovery_${HOSTNAME}_${TIMESTAMP}.json"

#===============================================================================
# Functions
#===============================================================================

print_header() {
    echo -e "${BLUE}===============================================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${BLUE}===============================================================================${NC}"
}

print_section() {
    echo -e "\n${GREEN}>>> $1${NC}"
    echo "===============================================================================" >> "$OUTPUT_FILE"
    echo "$1" >> "$OUTPUT_FILE"
    echo "===============================================================================" >> "$OUTPUT_FILE"
}

print_info() {
    echo -e "${YELLOW}$1${NC}"
}

print_error() {
    echo -e "${RED}ERROR: $1${NC}"
}

run_sql() {
    sqlplus -s / as sysdba <<EOF
SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
SET LINESIZE 500 TRIMSPOOL ON
$1
EXIT;
EOF
}

run_sql_with_header() {
    sqlplus -s / as sysdba <<EOF
SET PAGESIZE 1000 FEEDBACK OFF VERIFY OFF HEADING ON ECHO OFF
SET LINESIZE 500 TRIMSPOOL ON
COLUMN $2
$1
EXIT;
EOF
}

#===============================================================================
# Usage
#===============================================================================

usage() {
    echo "Usage: $0 [-h|--help]"
    echo ""
    echo "ZDM Target Database Discovery Script (Oracle Database@Azure)"
    echo "Run this script as the opc or oracle user on the target database server."
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help message"
    echo ""
    echo "Output files:"
    echo "  Text report: /tmp/zdm_target_discovery_<hostname>_<timestamp>.txt"
    echo "  JSON summary: /tmp/zdm_target_discovery_<hostname>_<timestamp>.json"
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
    shift
done

#===============================================================================
# Main Script
#===============================================================================

print_header "ZDM Target Database Discovery Script (Oracle Database@Azure)"
print_info "Project: PRODDB Migration to Oracle Database@Azure"
print_info "Started: $(date)"
print_info "Output: $OUTPUT_FILE"

# Initialize output file
echo "ZDM Target Database Discovery Report (Oracle Database@Azure)" > "$OUTPUT_FILE"
echo "Generated: $(date)" >> "$OUTPUT_FILE"
echo "Hostname: $HOSTNAME" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Initialize JSON
echo "{" > "$JSON_FILE"
echo '  "discovery_type": "target",' >> "$JSON_FILE"
echo '  "platform": "Oracle Database@Azure",' >> "$JSON_FILE"
echo "  \"hostname\": \"$HOSTNAME\"," >> "$JSON_FILE"
echo "  \"timestamp\": \"$(date -Iseconds)\"," >> "$JSON_FILE"

#-------------------------------------------------------------------------------
# OS Information
#-------------------------------------------------------------------------------
print_section "OS Information"

echo "Hostname: $(hostname)" | tee -a "$OUTPUT_FILE"
echo "Hostname FQDN: $(hostname -f 2>/dev/null || hostname)" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "IP Addresses:" | tee -a "$OUTPUT_FILE"
ip addr show 2>/dev/null | grep "inet " | awk '{print "  " $2}' | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Operating System:" | tee -a "$OUTPUT_FILE"
cat /etc/os-release 2>/dev/null | grep -E "^NAME=|^VERSION=" | tee -a "$OUTPUT_FILE"
uname -a | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Oracle Environment
#-------------------------------------------------------------------------------
print_section "Oracle Environment"

echo "ORACLE_HOME: ${ORACLE_HOME:-NOT SET}" | tee -a "$OUTPUT_FILE"
echo "ORACLE_SID: ${ORACLE_SID:-NOT SET}" | tee -a "$OUTPUT_FILE"
echo "ORACLE_BASE: ${ORACLE_BASE:-NOT SET}" | tee -a "$OUTPUT_FILE"
echo "GRID_HOME: ${GRID_HOME:-NOT SET}" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

if [ -n "$ORACLE_HOME" ]; then
    echo "Oracle Version:" | tee -a "$OUTPUT_FILE"
    $ORACLE_HOME/OPatch/opatch lspatches 2>/dev/null | head -20 | tee -a "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    ORACLE_VERSION=$(run_sql "SELECT banner FROM v\$version WHERE ROWNUM = 1;")
    echo "Database Version: $ORACLE_VERSION" | tee -a "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
fi

#-------------------------------------------------------------------------------
# Database Configuration
#-------------------------------------------------------------------------------
print_section "Database Configuration"

echo "Database Identification:" | tee -a "$OUTPUT_FILE"
run_sql_with_header "SELECT name, db_unique_name, dbid, database_role, open_mode, log_mode FROM v\$database;" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Database Instance:" | tee -a "$OUTPUT_FILE"
run_sql_with_header "SELECT instance_name, host_name, version, status, startup_time FROM v\$instance;" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Character Set:" | tee -a "$OUTPUT_FILE"
run_sql "SELECT parameter, value FROM nls_database_parameters WHERE parameter IN ('NLS_CHARACTERSET', 'NLS_NCHAR_CHARACTERSET');" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Available Storage
#-------------------------------------------------------------------------------
print_section "Available Storage"

echo "Tablespace Storage:" | tee -a "$OUTPUT_FILE"
run_sql_with_header "
SELECT tablespace_name,
       ROUND(SUM(bytes)/1024/1024/1024, 2) AS size_gb,
       ROUND(SUM(maxbytes)/1024/1024/1024, 2) AS max_gb
FROM dba_data_files
GROUP BY tablespace_name
ORDER BY tablespace_name;" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Check for ASM
echo "ASM Disk Groups (if applicable):" | tee -a "$OUTPUT_FILE"
run_sql_with_header "SELECT name, state, type, total_mb/1024 AS total_gb, free_mb/1024 AS free_gb FROM v\$asm_diskgroup;" 2>/dev/null | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Exadata Storage Capacity (Custom Request)
#-------------------------------------------------------------------------------
print_section "Exadata Storage Capacity (Custom Discovery)"

echo "Exadata Cell Disk Information:" | tee -a "$OUTPUT_FILE"
run_sql_with_header "SELECT cell_path, name, status, size_mb/1024 AS size_gb FROM v\$cell_disk;" 2>/dev/null | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Exadata Grid Disk Information:" | tee -a "$OUTPUT_FILE"
run_sql_with_header "SELECT cell_path, name, state, total_mb/1024 AS total_gb, free_mb/1024 AS free_gb FROM v\$asm_disk WHERE cell_path IS NOT NULL;" 2>/dev/null | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "ASM Diskgroup Space (Exadata):" | tee -a "$OUTPUT_FILE"
run_sql_with_header "
SELECT name, 
       total_mb/1024 AS total_gb, 
       free_mb/1024 AS free_gb,
       ROUND((free_mb/total_mb)*100, 2) AS pct_free,
       type,
       state
FROM v\$asm_diskgroup
ORDER BY name;" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Container Database (CDB/PDB)
#-------------------------------------------------------------------------------
print_section "Container Database Configuration"

CDB_STATUS=$(run_sql "SELECT CDB FROM v\$database;")
echo "CDB Status: $CDB_STATUS" | tee -a "$OUTPUT_FILE"

if [ "$CDB_STATUS" = "YES" ]; then
    echo "" >> "$OUTPUT_FILE"
    echo "PDB List:" | tee -a "$OUTPUT_FILE"
    run_sql_with_header "SELECT pdb_id, pdb_name, status, open_mode, restricted, con_uid FROM cdb_pdbs ORDER BY pdb_id;" | tee -a "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    echo "PDB Services:" | tee -a "$OUTPUT_FILE"
    run_sql_with_header "SELECT con_id, name, network_name, pdb FROM v\$services ORDER BY con_id;" | tee -a "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Pre-configured PDBs (Custom Request)
#-------------------------------------------------------------------------------
print_section "Pre-configured PDBs (Custom Discovery)"

echo "PDB Details with Storage:" | tee -a "$OUTPUT_FILE"
run_sql_with_header "
SELECT p.pdb_id, p.pdb_name, p.status, p.open_mode,
       NVL(ROUND(SUM(d.bytes)/1024/1024/1024, 2), 0) AS used_gb
FROM cdb_pdbs p
LEFT JOIN cdb_data_files d ON p.con_id = d.con_id
GROUP BY p.pdb_id, p.pdb_name, p.status, p.open_mode
ORDER BY p.pdb_id;" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Available PDB Templates:" | tee -a "$OUTPUT_FILE"
run_sql_with_header "SELECT pdb_name, status FROM cdb_pdbs WHERE pdb_name LIKE '%SEED%';" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# TDE Configuration
#-------------------------------------------------------------------------------
print_section "TDE Configuration"

echo "Encryption Wallet Status:" | tee -a "$OUTPUT_FILE"
run_sql_with_header "SELECT * FROM v\$encryption_wallet;" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "TDE Master Key:" | tee -a "$OUTPUT_FILE"
run_sql_with_header "SELECT key_id, keystore_type, creation_time FROM v\$encryption_keys WHERE ROWNUM <= 5;" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Network Configuration
#-------------------------------------------------------------------------------
print_section "Network Configuration"

echo "Listener Status:" | tee -a "$OUTPUT_FILE"
lsnrctl status 2>/dev/null | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Check for SCAN listener (RAC)
echo "SCAN Listener (if RAC):" | tee -a "$OUTPUT_FILE"
srvctl status scan_listener 2>/dev/null | tee -a "$OUTPUT_FILE" || echo "Not a RAC configuration or srvctl not available" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "tnsnames.ora:" | tee -a "$OUTPUT_FILE"
if [ -f "$ORACLE_HOME/network/admin/tnsnames.ora" ]; then
    cat "$ORACLE_HOME/network/admin/tnsnames.ora" | tee -a "$OUTPUT_FILE"
else
    echo "File not found: $ORACLE_HOME/network/admin/tnsnames.ora" | tee -a "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Network Security Group Rules (Custom Request - Azure)
#-------------------------------------------------------------------------------
print_section "Network Security Group Rules (Custom Discovery)"

echo "Azure Network Configuration:" | tee -a "$OUTPUT_FILE"
echo "Note: NSG rules are managed at the Azure portal/CLI level." | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Local Firewall Rules (firewalld):" | tee -a "$OUTPUT_FILE"
if command -v firewall-cmd &> /dev/null; then
    firewall-cmd --list-all 2>/dev/null | tee -a "$OUTPUT_FILE"
else
    echo "firewall-cmd not available" >> "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

echo "iptables Rules:" | tee -a "$OUTPUT_FILE"
iptables -L -n 2>/dev/null | head -50 | tee -a "$OUTPUT_FILE" || echo "Unable to list iptables rules" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Network Interfaces:" | tee -a "$OUTPUT_FILE"
ip addr show | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Routing Table:" | tee -a "$OUTPUT_FILE"
ip route show | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# OCI/Azure Integration
#-------------------------------------------------------------------------------
print_section "OCI/Azure Integration"

echo "OCI CLI Version:" | tee -a "$OUTPUT_FILE"
oci --version 2>/dev/null | tee -a "$OUTPUT_FILE" || echo "OCI CLI not installed" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "OCI Configuration:" | tee -a "$OUTPUT_FILE"
if [ -f ~/.oci/config ]; then
    echo "OCI config file found at ~/.oci/config" | tee -a "$OUTPUT_FILE"
    grep -E "^\[|^region|^tenancy" ~/.oci/config 2>/dev/null | tee -a "$OUTPUT_FILE"
else
    echo "OCI config file not found" | tee -a "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

echo "OCI Connectivity Test:" | tee -a "$OUTPUT_FILE"
oci os ns get 2>/dev/null | tee -a "$OUTPUT_FILE" || echo "OCI connectivity test failed or OCI CLI not configured" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Instance Metadata (OCI):" | tee -a "$OUTPUT_FILE"
curl -s -H "Authorization: Bearer Oracle" http://169.254.169.254/opc/v2/instance/ 2>/dev/null | head -50 | tee -a "$OUTPUT_FILE" || echo "Unable to retrieve OCI instance metadata" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Instance Metadata (Azure):" | tee -a "$OUTPUT_FILE"
curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" 2>/dev/null | head -50 | tee -a "$OUTPUT_FILE" || echo "Unable to retrieve Azure instance metadata" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Grid Infrastructure (RAC)
#-------------------------------------------------------------------------------
print_section "Grid Infrastructure"

echo "CRS Status:" | tee -a "$OUTPUT_FILE"
if [ -n "$GRID_HOME" ]; then
    $GRID_HOME/bin/crsctl status res -t 2>/dev/null | tee -a "$OUTPUT_FILE" || echo "Unable to get CRS status" >> "$OUTPUT_FILE"
else
    crsctl status res -t 2>/dev/null | tee -a "$OUTPUT_FILE" || echo "CRS not available or GRID_HOME not set" >> "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

echo "Database Service Status:" | tee -a "$OUTPUT_FILE"
srvctl status database -d "$ORACLE_SID" 2>/dev/null | tee -a "$OUTPUT_FILE" || echo "srvctl not available or database not registered" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Authentication
#-------------------------------------------------------------------------------
print_section "Authentication"

echo "SSH Directory Contents:" | tee -a "$OUTPUT_FILE"
ls -la ~/.ssh/ 2>/dev/null | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Authorized Keys:" | tee -a "$OUTPUT_FILE"
if [ -f ~/.ssh/authorized_keys ]; then
    echo "authorized_keys file exists with $(wc -l < ~/.ssh/authorized_keys) entries" | tee -a "$OUTPUT_FILE"
else
    echo "authorized_keys file not found" | tee -a "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Generate JSON Summary
#-------------------------------------------------------------------------------
print_section "Generating JSON Summary"

# Get key values for JSON
DB_NAME=$(run_sql "SELECT name FROM v\$database;")
DB_UNIQUE_NAME=$(run_sql "SELECT db_unique_name FROM v\$database;")
DBID=$(run_sql "SELECT dbid FROM v\$database;")
DB_ROLE=$(run_sql "SELECT database_role FROM v\$database;")
CDB=$(run_sql "SELECT CDB FROM v\$database;")
TDE_STATUS=$(run_sql "SELECT status FROM v\$encryption_wallet WHERE ROWNUM = 1;")
PDB_COUNT=$(run_sql "SELECT COUNT(*) FROM cdb_pdbs WHERE pdb_name != 'PDB\$SEED';")

# Continue JSON file
cat >> "$JSON_FILE" <<EOF
  "os": {
    "hostname": "$HOSTNAME",
    "os_version": "$(cat /etc/os-release 2>/dev/null | grep '^VERSION=' | cut -d= -f2 | tr -d '"')"
  },
  "oracle_environment": {
    "oracle_home": "${ORACLE_HOME:-NOT SET}",
    "oracle_sid": "${ORACLE_SID:-NOT SET}",
    "oracle_base": "${ORACLE_BASE:-NOT SET}",
    "grid_home": "${GRID_HOME:-NOT SET}"
  },
  "database": {
    "name": "$DB_NAME",
    "unique_name": "$DB_UNIQUE_NAME",
    "dbid": "$DBID",
    "role": "$DB_ROLE",
    "cdb": "$CDB",
    "pdb_count": "$PDB_COUNT",
    "tde_status": "$TDE_STATUS"
  },
  "output_files": {
    "text_report": "$OUTPUT_FILE",
    "json_summary": "$JSON_FILE"
  }
}
EOF

#-------------------------------------------------------------------------------
# Complete
#-------------------------------------------------------------------------------
print_header "Discovery Complete"
print_info "Text Report: $OUTPUT_FILE"
print_info "JSON Summary: $JSON_FILE"
print_info "Completed: $(date)"

echo ""
echo "===============================================================================" >> "$OUTPUT_FILE"
echo "Discovery completed at $(date)" >> "$OUTPUT_FILE"
echo "===============================================================================" >> "$OUTPUT_FILE"

exit 0
