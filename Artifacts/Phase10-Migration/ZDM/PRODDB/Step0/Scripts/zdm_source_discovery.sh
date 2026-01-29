#!/bin/bash
#===============================================================================
# ZDM Source Database Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# Target: proddb01.corp.example.com
# Generated: 2026-01-29
#===============================================================================
# Usage: ./zdm_source_discovery.sh
# Run as: oracle user
# Output: Text report and JSON summary in /tmp/
#===============================================================================

# Exit on error
set -e

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname -s)
OUTPUT_FILE="/tmp/zdm_source_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_FILE="/tmp/zdm_source_discovery_${HOSTNAME}_${TIMESTAMP}.json"

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
log_header "ZDM Source Database Discovery"
echo "================================================================" > "$OUTPUT_FILE"
echo "= ZDM Source Database Discovery Report" >> "$OUTPUT_FILE"
echo "= Project: PRODDB Migration to Oracle Database@Azure" >> "$OUTPUT_FILE"
echo "= Host: $HOSTNAME" >> "$OUTPUT_FILE"
echo "= Date: $(date)" >> "$OUTPUT_FILE"
echo "================================================================" >> "$OUTPUT_FILE"

# Initialize JSON
echo "{" > "$JSON_FILE"
echo "  \"discovery_type\": \"source\"," >> "$JSON_FILE"
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
echo "TNS_ADMIN: ${TNS_ADMIN:-NOT SET}" >> "$OUTPUT_FILE"
echo "PATH: $PATH" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Oracle Version:" >> "$OUTPUT_FILE"
if [ -n "$ORACLE_HOME" ] && [ -f "$ORACLE_HOME/bin/sqlplus" ]; then
    $ORACLE_HOME/bin/sqlplus -v 2>/dev/null >> "$OUTPUT_FILE" || echo "Unable to get version" >> "$OUTPUT_FILE"
else
    echo "ORACLE_HOME not set or sqlplus not found" >> "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

# JSON: Oracle Environment
echo "  \"oracle_env\": {" >> "$JSON_FILE"
echo "    \"oracle_home\": \"${ORACLE_HOME:-NOT SET}\"," >> "$JSON_FILE"
echo "    \"oracle_sid\": \"${ORACLE_SID:-NOT SET}\"," >> "$JSON_FILE"
echo "    \"oracle_base\": \"${ORACLE_BASE:-NOT SET}\"" >> "$JSON_FILE"
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
       force_logging,
       flashback_on,
       created
FROM v\$database;
"
echo "" >> "$OUTPUT_FILE"

echo "Database Version:" >> "$OUTPUT_FILE"
run_sql_to_file "SELECT banner_full FROM v\$version WHERE banner_full IS NOT NULL;"
echo "" >> "$OUTPUT_FILE"

echo "Database Size Summary:" >> "$OUTPUT_FILE"
run_sql_to_file "
SELECT 
    'Data Files' as type,
    COUNT(*) as count,
    ROUND(SUM(bytes)/1024/1024/1024, 2) as size_gb
FROM dba_data_files
UNION ALL
SELECT 
    'Temp Files' as type,
    COUNT(*) as count,
    ROUND(SUM(bytes)/1024/1024/1024, 2) as size_gb
FROM dba_temp_files
UNION ALL
SELECT 
    'Redo Logs' as type,
    COUNT(*) as count,
    ROUND(SUM(bytes)/1024/1024/1024, 2) as size_gb
FROM v\$log;
"
echo "" >> "$OUTPUT_FILE"

echo "Character Set:" >> "$OUTPUT_FILE"
run_sql_to_file "
SELECT parameter, value 
FROM nls_database_parameters 
WHERE parameter IN ('NLS_CHARACTERSET', 'NLS_NCHAR_CHARACTERSET', 'NLS_LANGUAGE', 'NLS_TERRITORY');
"
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
SELECT con_id, name, open_mode, restricted, total_size/1024/1024/1024 as size_gb
FROM v\$pdbs
ORDER BY con_id;
" 2>/dev/null || echo "Not a CDB or no PDBs found" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# TDE Configuration
#-------------------------------------------------------------------------------
log_section "TDE CONFIGURATION"
echo "" >> "$OUTPUT_FILE"

echo "Wallet Status:" >> "$OUTPUT_FILE"
run_sql_to_file "SELECT * FROM v\$encryption_wallet;"
echo "" >> "$OUTPUT_FILE"

echo "Encrypted Tablespaces:" >> "$OUTPUT_FILE"
run_sql_to_file "
SELECT tablespace_name, encrypted
FROM dba_tablespaces
WHERE encrypted = 'YES';
"
echo "" >> "$OUTPUT_FILE"

echo "TDE Master Key:" >> "$OUTPUT_FILE"
run_sql_to_file "
SELECT key_id, creation_time, activation_time, key_use
FROM v\$encryption_keys
WHERE activation_time IS NOT NULL;
" 2>/dev/null || echo "No TDE keys found or TDE not configured" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Wallet Location (from sqlnet.ora):" >> "$OUTPUT_FILE"
if [ -n "$TNS_ADMIN" ] && [ -f "$TNS_ADMIN/sqlnet.ora" ]; then
    grep -i "ENCRYPTION_WALLET_LOCATION\|WALLET_LOCATION" "$TNS_ADMIN/sqlnet.ora" >> "$OUTPUT_FILE" 2>/dev/null || echo "Wallet location not found in sqlnet.ora" >> "$OUTPUT_FILE"
elif [ -n "$ORACLE_HOME" ] && [ -f "$ORACLE_HOME/network/admin/sqlnet.ora" ]; then
    grep -i "ENCRYPTION_WALLET_LOCATION\|WALLET_LOCATION" "$ORACLE_HOME/network/admin/sqlnet.ora" >> "$OUTPUT_FILE" 2>/dev/null || echo "Wallet location not found in sqlnet.ora" >> "$OUTPUT_FILE"
else
    echo "sqlnet.ora not found" >> "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Supplemental Logging
#-------------------------------------------------------------------------------
log_section "SUPPLEMENTAL LOGGING"
echo "" >> "$OUTPUT_FILE"

run_sql_to_file "
SELECT 
    supplemental_log_data_min as min,
    supplemental_log_data_pk as pk,
    supplemental_log_data_ui as ui,
    supplemental_log_data_fk as fk,
    supplemental_log_data_all as all_cols
FROM v\$database;
"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Redo/Archive Configuration
#-------------------------------------------------------------------------------
log_section "REDO AND ARCHIVE LOG CONFIGURATION"
echo "" >> "$OUTPUT_FILE"

echo "Redo Log Groups:" >> "$OUTPUT_FILE"
run_sql_to_file "
SELECT group#, thread#, sequence#, bytes/1024/1024 as size_mb, 
       members, status, archived
FROM v\$log
ORDER BY group#;
"
echo "" >> "$OUTPUT_FILE"

echo "Redo Log Members:" >> "$OUTPUT_FILE"
run_sql_to_file "
SELECT group#, member, type, status
FROM v\$logfile
ORDER BY group#, member;
"
echo "" >> "$OUTPUT_FILE"

echo "Archive Log Destinations:" >> "$OUTPUT_FILE"
run_sql_to_file "
SELECT dest_id, dest_name, status, destination, 
       binding, valid_now, valid_type
FROM v\$archive_dest
WHERE status != 'INACTIVE';
"
echo "" >> "$OUTPUT_FILE"

echo "Archive Log Mode:" >> "$OUTPUT_FILE"
run_sql_to_file "SELECT log_mode FROM v\$database;"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Network Configuration
#-------------------------------------------------------------------------------
log_section "NETWORK CONFIGURATION"
echo "" >> "$OUTPUT_FILE"

echo "Listener Status:" >> "$OUTPUT_FILE"
lsnrctl status >> "$OUTPUT_FILE" 2>&1 || echo "Unable to get listener status" >> "$OUTPUT_FILE"
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

echo "sqlnet.ora:" >> "$OUTPUT_FILE"
if [ -n "$TNS_ADMIN" ] && [ -f "$TNS_ADMIN/sqlnet.ora" ]; then
    cat "$TNS_ADMIN/sqlnet.ora" >> "$OUTPUT_FILE"
elif [ -n "$ORACLE_HOME" ] && [ -f "$ORACLE_HOME/network/admin/sqlnet.ora" ]; then
    cat "$ORACLE_HOME/network/admin/sqlnet.ora" >> "$OUTPUT_FILE"
else
    echo "sqlnet.ora not found" >> "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Authentication
#-------------------------------------------------------------------------------
log_section "AUTHENTICATION"
echo "" >> "$OUTPUT_FILE"

echo "Password File:" >> "$OUTPUT_FILE"
if [ -n "$ORACLE_HOME" ]; then
    ls -la "$ORACLE_HOME/dbs/orapw"* 2>/dev/null >> "$OUTPUT_FILE" || echo "No password file found in $ORACLE_HOME/dbs/" >> "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

echo "SSH Directory Contents:" >> "$OUTPUT_FILE"
ls -la ~/.ssh/ 2>/dev/null >> "$OUTPUT_FILE" || echo "No .ssh directory found" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Data Guard Parameters
#-------------------------------------------------------------------------------
log_section "DATA GUARD CONFIGURATION"
echo "" >> "$OUTPUT_FILE"

run_sql_to_file "
SELECT name, value
FROM v\$parameter
WHERE name LIKE '%log_archive_dest%'
   OR name LIKE '%standby%'
   OR name LIKE '%fal_%'
   OR name IN ('db_unique_name', 'log_archive_config', 'dg_broker_start')
ORDER BY name;
"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Schema Information
#-------------------------------------------------------------------------------
log_section "SCHEMA INFORMATION"
echo "" >> "$OUTPUT_FILE"

echo "Schema Sizes (Non-system, > 100MB):" >> "$OUTPUT_FILE"
run_sql_to_file "
SELECT owner, 
       COUNT(*) as object_count,
       ROUND(SUM(bytes)/1024/1024, 2) as size_mb
FROM dba_segments
WHERE owner NOT IN ('SYS', 'SYSTEM', 'DBSNMP', 'APPQOSSYS', 'DBSFWUSER', 
                    'REMOTE_SCHEDULER_AGENT', 'OUTLN', 'XDB', 'GSMADMIN_INTERNAL',
                    'GGSYS', 'DIP', 'ORACLE_OCM', 'WMSYS', 'AUDSYS', 'LBACSYS',
                    'DVSYS', 'DVF', 'ORDDATA', 'MDSYS', 'ORDPLUGINS', 'ORDSYS',
                    'SI_INFORMTN_SCHEMA', 'CTXSYS', 'OJVMSYS', 'OLAPSYS')
GROUP BY owner
HAVING SUM(bytes)/1024/1024 > 100
ORDER BY SUM(bytes) DESC;
"
echo "" >> "$OUTPUT_FILE"

echo "Invalid Objects by Owner/Type:" >> "$OUTPUT_FILE"
run_sql_to_file "
SELECT owner, object_type, COUNT(*) as invalid_count
FROM dba_objects
WHERE status = 'INVALID'
GROUP BY owner, object_type
ORDER BY owner, object_type;
"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# ADDITIONAL CUSTOM DISCOVERY - PRODDB Specific
#-------------------------------------------------------------------------------
log_section "TABLESPACE AUTOEXTEND SETTINGS"
echo "" >> "$OUTPUT_FILE"

run_sql_to_file "
SELECT tablespace_name, 
       file_name, 
       autoextensible,
       ROUND(bytes/1024/1024/1024, 2) as current_gb,
       ROUND(maxbytes/1024/1024/1024, 2) as max_gb,
       increment_by
FROM dba_data_files 
ORDER BY tablespace_name, file_name;
"
echo "" >> "$OUTPUT_FILE"

echo "Temp File Autoextend:" >> "$OUTPUT_FILE"
run_sql_to_file "
SELECT tablespace_name, 
       file_name, 
       autoextensible,
       ROUND(bytes/1024/1024/1024, 2) as current_gb,
       ROUND(maxbytes/1024/1024/1024, 2) as max_gb
FROM dba_temp_files 
ORDER BY tablespace_name;
"
echo "" >> "$OUTPUT_FILE"

log_section "BACKUP SCHEDULE AND RETENTION"
echo "" >> "$OUTPUT_FILE"

echo "RMAN Configuration:" >> "$OUTPUT_FILE"
rman target / <<EOF >> "$OUTPUT_FILE" 2>&1 || echo "Unable to connect to RMAN" >> "$OUTPUT_FILE"
SHOW ALL;
EXIT;
EOF
echo "" >> "$OUTPUT_FILE"

echo "Recent Backup History (last 7 days):" >> "$OUTPUT_FILE"
run_sql_to_file "
SELECT session_key, input_type, status, 
       TO_CHAR(start_time, 'YYYY-MM-DD HH24:MI:SS') as start_time,
       TO_CHAR(end_time, 'YYYY-MM-DD HH24:MI:SS') as end_time,
       elapsed_seconds
FROM v\$rman_backup_job_details
WHERE start_time > SYSDATE - 7
ORDER BY start_time DESC;
"
echo "" >> "$OUTPUT_FILE"

log_section "DATABASE LINKS"
echo "" >> "$OUTPUT_FILE"

run_sql_to_file "
SELECT owner, db_link, username, host, created
FROM dba_db_links
ORDER BY owner, db_link;
"
echo "" >> "$OUTPUT_FILE"

log_section "MATERIALIZED VIEW REFRESH SCHEDULES"
echo "" >> "$OUTPUT_FILE"

run_sql_to_file "
SELECT owner, mview_name, 
       refresh_mode, refresh_method,
       last_refresh_type,
       TO_CHAR(last_refresh_date, 'YYYY-MM-DD HH24:MI:SS') as last_refresh,
       next_refresh_date
FROM dba_mviews
ORDER BY owner, mview_name;
"
echo "" >> "$OUTPUT_FILE"

echo "Materialized View Refresh Groups:" >> "$OUTPUT_FILE"
run_sql_to_file "
SELECT rowner, rname, 
       TO_CHAR(next_date, 'YYYY-MM-DD HH24:MI:SS') as next_date,
       interval, broken
FROM dba_refresh
ORDER BY rowner, rname;
"
echo "" >> "$OUTPUT_FILE"

log_section "SCHEDULER JOBS"
echo "" >> "$OUTPUT_FILE"

run_sql_to_file "
SELECT owner, job_name, job_type, 
       state, enabled,
       TO_CHAR(last_start_date, 'YYYY-MM-DD HH24:MI:SS') as last_start,
       TO_CHAR(next_run_date, 'YYYY-MM-DD HH24:MI:SS') as next_run,
       repeat_interval,
       job_action
FROM dba_scheduler_jobs
WHERE owner NOT IN ('SYS', 'SYSTEM', 'ORACLE_OCM', 'EXFSYS')
ORDER BY owner, job_name;
"
echo "" >> "$OUTPUT_FILE"

echo "DBMS_JOBS (Legacy Jobs):" >> "$OUTPUT_FILE"
run_sql_to_file "
SELECT job, log_user, priv_user,
       what,
       TO_CHAR(next_date, 'YYYY-MM-DD HH24:MI:SS') as next_date,
       interval, broken
FROM dba_jobs
ORDER BY job;
"
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
echo -e "${GREEN}= Discovery Complete${NC}"
echo -e "${GREEN}================================================================${NC}"
echo -e "Text Report: ${BLUE}$OUTPUT_FILE${NC}"
echo -e "JSON Summary: ${BLUE}$JSON_FILE${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Review the discovery report"
echo "2. Copy output files to the ZDM server"
echo "3. Run discovery on target and ZDM servers"
echo ""
