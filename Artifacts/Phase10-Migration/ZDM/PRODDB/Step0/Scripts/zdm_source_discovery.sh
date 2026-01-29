#!/bin/bash
#===============================================================================
# ZDM Source Database Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# Target Server: proddb01.corp.example.com
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
OUTPUT_FILE="/tmp/zdm_source_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_FILE="/tmp/zdm_source_discovery_${HOSTNAME}_${TIMESTAMP}.json"

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
    echo "ZDM Source Database Discovery Script"
    echo "Run this script as the oracle user on the source database server."
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help message"
    echo ""
    echo "Output files:"
    echo "  Text report: /tmp/zdm_source_discovery_<hostname>_<timestamp>.txt"
    echo "  JSON summary: /tmp/zdm_source_discovery_<hostname>_<timestamp>.json"
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

print_header "ZDM Source Database Discovery Script"
print_info "Project: PRODDB Migration to Oracle Database@Azure"
print_info "Started: $(date)"
print_info "Output: $OUTPUT_FILE"

# Initialize output file
echo "ZDM Source Database Discovery Report" > "$OUTPUT_FILE"
echo "Generated: $(date)" >> "$OUTPUT_FILE"
echo "Hostname: $HOSTNAME" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Initialize JSON
echo "{" > "$JSON_FILE"
echo '  "discovery_type": "source",' >> "$JSON_FILE"
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

echo "Disk Space:" | tee -a "$OUTPUT_FILE"
df -h | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Oracle Environment
#-------------------------------------------------------------------------------
print_section "Oracle Environment"

echo "ORACLE_HOME: ${ORACLE_HOME:-NOT SET}" | tee -a "$OUTPUT_FILE"
echo "ORACLE_SID: ${ORACLE_SID:-NOT SET}" | tee -a "$OUTPUT_FILE"
echo "ORACLE_BASE: ${ORACLE_BASE:-NOT SET}" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

if [ -n "$ORACLE_HOME" ]; then
    echo "Oracle Version:" | tee -a "$OUTPUT_FILE"
    $ORACLE_HOME/OPatch/opatch lspatches 2>/dev/null | head -20 | tee -a "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    # Get version from SQL
    ORACLE_VERSION=$(run_sql "SELECT banner FROM v\$version WHERE ROWNUM = 1;")
    echo "Database Version: $ORACLE_VERSION" | tee -a "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
fi

#-------------------------------------------------------------------------------
# Database Configuration
#-------------------------------------------------------------------------------
print_section "Database Configuration"

echo "Database Identification:" | tee -a "$OUTPUT_FILE"
run_sql_with_header "SELECT name, db_unique_name, dbid, database_role, open_mode, log_mode, force_logging FROM v\$database;" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Database Instance:" | tee -a "$OUTPUT_FILE"
run_sql_with_header "SELECT instance_name, host_name, version, status, startup_time FROM v\$instance;" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Database Size (Data Files):" | tee -a "$OUTPUT_FILE"
run_sql "SELECT ROUND(SUM(bytes)/1024/1024/1024, 2) || ' GB' AS datafile_size FROM dba_data_files;" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Database Size (Temp Files):" | tee -a "$OUTPUT_FILE"
run_sql "SELECT ROUND(SUM(bytes)/1024/1024/1024, 2) || ' GB' AS tempfile_size FROM dba_temp_files;" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Character Set:" | tee -a "$OUTPUT_FILE"
run_sql "SELECT parameter, value FROM nls_database_parameters WHERE parameter IN ('NLS_CHARACTERSET', 'NLS_NCHAR_CHARACTERSET');" | tee -a "$OUTPUT_FILE"
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
    run_sql_with_header "SELECT pdb_id, pdb_name, status, open_mode, restricted FROM cdb_pdbs ORDER BY pdb_id;" | tee -a "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# TDE Configuration
#-------------------------------------------------------------------------------
print_section "TDE Configuration"

echo "Encryption Wallet Status:" | tee -a "$OUTPUT_FILE"
run_sql_with_header "SELECT * FROM v\$encryption_wallet;" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "TDE Master Key:" | tee -a "$OUTPUT_FILE"
run_sql_with_header "SELECT key_id, keystore_type, creation_time, activation_time FROM v\$encryption_keys WHERE ROWNUM <= 5;" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Encrypted Tablespaces:" | tee -a "$OUTPUT_FILE"
run_sql_with_header "SELECT tablespace_name, encrypted FROM dba_tablespaces WHERE encrypted = 'YES';" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Wallet Location (from sqlnet.ora):" | tee -a "$OUTPUT_FILE"
if [ -f "$ORACLE_HOME/network/admin/sqlnet.ora" ]; then
    grep -i "ENCRYPTION_WALLET_LOCATION\|WALLET_LOCATION" "$ORACLE_HOME/network/admin/sqlnet.ora" 2>/dev/null | tee -a "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Supplemental Logging
#-------------------------------------------------------------------------------
print_section "Supplemental Logging"

run_sql_with_header "SELECT supplemental_log_data_min, supplemental_log_data_pk, supplemental_log_data_ui, supplemental_log_data_fk, supplemental_log_data_all FROM v\$database;" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Redo/Archive Configuration
#-------------------------------------------------------------------------------
print_section "Redo and Archive Configuration"

echo "Redo Log Groups:" | tee -a "$OUTPUT_FILE"
run_sql_with_header "SELECT group#, thread#, sequence#, bytes/1024/1024 AS size_mb, members, status FROM v\$log ORDER BY group#;" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Redo Log Members:" | tee -a "$OUTPUT_FILE"
run_sql_with_header "SELECT group#, member, type, status FROM v\$logfile ORDER BY group#;" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Archive Log Destinations:" | tee -a "$OUTPUT_FILE"
run_sql_with_header "SELECT dest_id, dest_name, status, destination FROM v\$archive_dest WHERE status != 'INACTIVE';" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Archive Log Mode:" | tee -a "$OUTPUT_FILE"
run_sql "SELECT log_mode FROM v\$database;" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Tablespace Information (Including Autoextend - Custom Request)
#-------------------------------------------------------------------------------
print_section "Tablespace Information"

echo "Tablespace Details:" | tee -a "$OUTPUT_FILE"
run_sql_with_header "SELECT tablespace_name, status, contents, extent_management, segment_space_management FROM dba_tablespaces ORDER BY tablespace_name;" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Tablespace Autoextend Settings (Custom Discovery):" | tee -a "$OUTPUT_FILE"
run_sql_with_header "SELECT tablespace_name, file_name, bytes/1024/1024 AS size_mb, maxbytes/1024/1024 AS max_mb, autoextensible, increment_by FROM dba_data_files ORDER BY tablespace_name;" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Tablespace Usage:" | tee -a "$OUTPUT_FILE"
run_sql_with_header "
SELECT a.tablespace_name,
       ROUND(a.bytes/1024/1024/1024, 2) AS size_gb,
       ROUND((a.bytes - NVL(b.bytes, 0))/1024/1024/1024, 2) AS used_gb,
       ROUND(NVL(b.bytes, 0)/1024/1024/1024, 2) AS free_gb,
       ROUND((a.bytes - NVL(b.bytes, 0))/a.bytes * 100, 2) AS pct_used
FROM (SELECT tablespace_name, SUM(bytes) bytes FROM dba_data_files GROUP BY tablespace_name) a
LEFT JOIN (SELECT tablespace_name, SUM(bytes) bytes FROM dba_free_space GROUP BY tablespace_name) b
ON a.tablespace_name = b.tablespace_name
ORDER BY pct_used DESC;" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Network Configuration
#-------------------------------------------------------------------------------
print_section "Network Configuration"

echo "Listener Status:" | tee -a "$OUTPUT_FILE"
lsnrctl status 2>/dev/null | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "tnsnames.ora:" | tee -a "$OUTPUT_FILE"
if [ -f "$ORACLE_HOME/network/admin/tnsnames.ora" ]; then
    cat "$ORACLE_HOME/network/admin/tnsnames.ora" | tee -a "$OUTPUT_FILE"
else
    echo "File not found: $ORACLE_HOME/network/admin/tnsnames.ora" | tee -a "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

echo "sqlnet.ora:" | tee -a "$OUTPUT_FILE"
if [ -f "$ORACLE_HOME/network/admin/sqlnet.ora" ]; then
    cat "$ORACLE_HOME/network/admin/sqlnet.ora" | tee -a "$OUTPUT_FILE"
else
    echo "File not found: $ORACLE_HOME/network/admin/sqlnet.ora" | tee -a "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Authentication
#-------------------------------------------------------------------------------
print_section "Authentication"

echo "Password File Location:" | tee -a "$OUTPUT_FILE"
find "$ORACLE_HOME/dbs" -name "orapw*" 2>/dev/null | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "SSH Directory Contents:" | tee -a "$OUTPUT_FILE"
ls -la ~/.ssh/ 2>/dev/null | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Data Guard Configuration
#-------------------------------------------------------------------------------
print_section "Data Guard Configuration"

echo "Data Guard Parameters:" | tee -a "$OUTPUT_FILE"
run_sql_with_header "SELECT name, value FROM v\$parameter WHERE name LIKE 'log_archive_dest%' OR name LIKE 'fal_%' OR name LIKE 'standby%' OR name = 'db_unique_name' ORDER BY name;" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Data Guard Status:" | tee -a "$OUTPUT_FILE"
run_sql_with_header "SELECT database_role, protection_mode, protection_level, switchover_status FROM v\$database;" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Database Links (Custom Request)
#-------------------------------------------------------------------------------
print_section "Database Links (Custom Discovery)"

echo "Database Links:" | tee -a "$OUTPUT_FILE"
run_sql_with_header "SELECT owner, db_link, username, host FROM dba_db_links ORDER BY owner, db_link;" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Materialized Views (Custom Request)
#-------------------------------------------------------------------------------
print_section "Materialized View Refresh Schedules (Custom Discovery)"

echo "Materialized Views:" | tee -a "$OUTPUT_FILE"
run_sql_with_header "SELECT owner, mview_name, refresh_mode, refresh_method, last_refresh_date, next_refresh_date FROM dba_mviews ORDER BY owner, mview_name;" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Materialized View Refresh Groups:" | tee -a "$OUTPUT_FILE"
run_sql_with_header "SELECT rowner, rname, job, next_date, interval, broken FROM dba_refresh ORDER BY rowner, rname;" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Scheduler Jobs (Custom Request)
#-------------------------------------------------------------------------------
print_section "Scheduler Jobs (Custom Discovery)"

echo "Scheduler Jobs:" | tee -a "$OUTPUT_FILE"
run_sql_with_header "SELECT owner, job_name, job_type, state, enabled, last_start_date, next_run_date, repeat_interval FROM dba_scheduler_jobs WHERE owner NOT IN ('SYS', 'SYSTEM', 'ORACLE_OCM') ORDER BY owner, job_name;" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "DBMS_JOB Jobs:" | tee -a "$OUTPUT_FILE"
run_sql_with_header "SELECT job, schema_user, last_date, next_date, broken, interval, what FROM dba_jobs ORDER BY job;" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Backup Schedule and Retention (Custom Request)
#-------------------------------------------------------------------------------
print_section "Backup Schedule and Retention (Custom Discovery)"

echo "RMAN Configuration:" | tee -a "$OUTPUT_FILE"
rman target / <<EOF 2>/dev/null | tee -a "$OUTPUT_FILE"
SHOW ALL;
EXIT;
EOF
echo "" >> "$OUTPUT_FILE"

echo "Recent Backup History:" | tee -a "$OUTPUT_FILE"
run_sql_with_header "SELECT session_key, input_type, status, start_time, end_time, elapsed_seconds, input_bytes/1024/1024/1024 AS input_gb FROM v\$rman_backup_job_details WHERE start_time > SYSDATE - 7 ORDER BY start_time DESC;" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Backup Retention Policy:" | tee -a "$OUTPUT_FILE"
run_sql_with_header "SELECT name, value FROM v\$rman_configuration WHERE name LIKE '%RETENTION%';" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Schema Information
#-------------------------------------------------------------------------------
print_section "Schema Information"

echo "Schema Sizes (Non-System > 100MB):" | tee -a "$OUTPUT_FILE"
run_sql_with_header "
SELECT owner, 
       ROUND(SUM(bytes)/1024/1024, 2) AS size_mb,
       COUNT(*) AS segment_count
FROM dba_segments 
WHERE owner NOT IN ('SYS', 'SYSTEM', 'OUTLN', 'DIP', 'ORACLE_OCM', 'DBSNMP', 
                    'APPQOSSYS', 'WMSYS', 'XDB', 'ANONYMOUS', 'XS\$NULL',
                    'MDDATA', 'MDSYS', 'SPATIAL_WFS_ADMIN_USR', 'SPATIAL_CSW_ADMIN_USR',
                    'LBACSYS', 'EXFSYS', 'DVSYS', 'DVF', 'SI_INFORMTN_SCHEMA',
                    'ORDPLUGINS', 'ORDDATA', 'ORDSYS', 'CTXSYS', 'OLAPSYS',
                    'GSMADMIN_INTERNAL', 'AUDSYS')
GROUP BY owner
HAVING SUM(bytes)/1024/1024 > 100
ORDER BY size_mb DESC;" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Invalid Objects by Owner and Type:" | tee -a "$OUTPUT_FILE"
run_sql_with_header "
SELECT owner, object_type, COUNT(*) AS invalid_count
FROM dba_objects
WHERE status = 'INVALID'
GROUP BY owner, object_type
ORDER BY owner, object_type;" | tee -a "$OUTPUT_FILE"
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
LOG_MODE=$(run_sql "SELECT log_mode FROM v\$database;")
CDB=$(run_sql "SELECT CDB FROM v\$database;")
DB_SIZE_GB=$(run_sql "SELECT ROUND(SUM(bytes)/1024/1024/1024, 2) FROM dba_data_files;")
TDE_STATUS=$(run_sql "SELECT status FROM v\$encryption_wallet WHERE ROWNUM = 1;")

# Continue JSON file
cat >> "$JSON_FILE" <<EOF
  "os": {
    "hostname": "$HOSTNAME",
    "os_version": "$(cat /etc/os-release 2>/dev/null | grep '^VERSION=' | cut -d= -f2 | tr -d '"')"
  },
  "oracle_environment": {
    "oracle_home": "${ORACLE_HOME:-NOT SET}",
    "oracle_sid": "${ORACLE_SID:-NOT SET}",
    "oracle_base": "${ORACLE_BASE:-NOT SET}"
  },
  "database": {
    "name": "$DB_NAME",
    "unique_name": "$DB_UNIQUE_NAME",
    "dbid": "$DBID",
    "role": "$DB_ROLE",
    "log_mode": "$LOG_MODE",
    "cdb": "$CDB",
    "size_gb": "$DB_SIZE_GB",
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
