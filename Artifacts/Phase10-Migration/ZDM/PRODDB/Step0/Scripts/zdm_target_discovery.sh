#!/bin/bash
#===============================================================================
# ZDM Target Database Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# Target: proddb-oda.eastus.azure.example.com
#
# Purpose: Gather comprehensive information from the target Oracle Database@Azure
#          server to support ZDM migration planning.
#
# Execution: Run as ADMIN_USER (opc) via SSH. SQL commands execute as ORACLE_USER.
#
# Output:
#   - Text report: ./zdm_target_discovery_<hostname>_<timestamp>.txt
#   - JSON summary: ./zdm_target_discovery_<hostname>_<timestamp>.json
#===============================================================================

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script variables
SCRIPT_NAME="zdm_target_discovery.sh"
HOSTNAME=$(hostname -s 2>/dev/null || hostname)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="./zdm_target_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_target_discovery_${HOSTNAME}_${TIMESTAMP}.json"

# User configuration - can be overridden via environment
ORACLE_USER="${ORACLE_USER:-oracle}"

# Error tracking
declare -a FAILED_SECTIONS=()
declare -a SUCCESS_SECTIONS=()

#===============================================================================
# FUNCTIONS
#===============================================================================

print_header() {
    local title="$1"
    echo -e "\n${BLUE}=================================================================================${NC}"
    echo -e "${CYAN}  $title${NC}"
    echo -e "${BLUE}=================================================================================${NC}"
}

print_section() {
    local title="$1"
    echo -e "\n${GREEN}--- $title ---${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

log_section_result() {
    local section="$1"
    local status="$2"
    if [ "$status" = "success" ]; then
        SUCCESS_SECTIONS+=("$section")
    else
        FAILED_SECTIONS+=("$section")
    fi
}

# Auto-detect Oracle environment
detect_oracle_env() {
    # If already set, use existing values
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        print_success "Using pre-configured ORACLE_HOME=$ORACLE_HOME, ORACLE_SID=$ORACLE_SID"
        return 0
    fi
    
    print_section "Auto-detecting Oracle Environment"
    
    # Method 1: Parse /etc/oratab (most reliable)
    if [ -f /etc/oratab ]; then
        local oratab_entry
        if [ -n "${ORACLE_SID:-}" ]; then
            oratab_entry=$(grep "^${ORACLE_SID}:" /etc/oratab 2>/dev/null | head -1)
        else
            oratab_entry=$(grep -v '^#' /etc/oratab | grep -v '^$' | grep ':Y$\|:N$' | head -1)
        fi
        if [ -n "$oratab_entry" ]; then
            export ORACLE_SID="${ORACLE_SID:-$(echo "$oratab_entry" | cut -d: -f1)}"
            export ORACLE_HOME="${ORACLE_HOME:-$(echo "$oratab_entry" | cut -d: -f2)}"
            print_success "Detected from /etc/oratab: ORACLE_SID=$ORACLE_SID, ORACLE_HOME=$ORACLE_HOME"
        fi
    fi
    
    # Method 2: Check running pmon process
    if [ -z "${ORACLE_SID:-}" ]; then
        local pmon_sid
        pmon_sid=$(ps -ef | grep 'ora_pmon_' | grep -v grep | head -1 | sed 's/.*ora_pmon_//')
        if [ -n "$pmon_sid" ]; then
            export ORACLE_SID="$pmon_sid"
            print_success "Detected ORACLE_SID from pmon process: $ORACLE_SID"
        fi
    fi
    
    # Method 3: Search common Oracle installation paths (including ODA paths)
    if [ -z "${ORACLE_HOME:-}" ]; then
        for path in /u02/app/oracle/product/*/dbhome_1 /u01/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1; do
            if [ -d "$path" ] && [ -f "$path/bin/sqlplus" ]; then
                export ORACLE_HOME="$path"
                print_success "Detected ORACLE_HOME from common path: $ORACLE_HOME"
                break
            fi
        done
    fi
    
    # Method 4: Try oraenv if we have ORACLE_SID
    if [ -z "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        if [ -f /usr/local/bin/oraenv ]; then
            ORAENV_ASK=NO . /usr/local/bin/oraenv <<< "$ORACLE_SID" 2>/dev/null
            [ -n "${ORACLE_HOME:-}" ] && print_success "Detected ORACLE_HOME via oraenv: $ORACLE_HOME"
        fi
    fi
    
    # Apply explicit overrides if provided (highest priority)
    [ -n "${ORACLE_HOME_OVERRIDE:-}" ] && export ORACLE_HOME="$ORACLE_HOME_OVERRIDE"
    [ -n "${ORACLE_SID_OVERRIDE:-}" ] && export ORACLE_SID="$ORACLE_SID_OVERRIDE"
    
    # Set ORACLE_BASE
    if [ -n "${ORACLE_HOME:-}" ]; then
        export ORACLE_BASE="${ORACLE_BASE:-$(dirname $(dirname $ORACLE_HOME))}"
    fi
    
    # Validate
    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        print_error "Failed to detect Oracle environment"
        return 1
    fi
    
    return 0
}

# Execute SQL as oracle user
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

# Execute SQL and return single value
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
        # Execute as oracle user
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            echo "$sql_script" | ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd 2>/dev/null | head -1 | xargs
        else
            echo "$sql_script" | sudo -u "$ORACLE_USER" ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd 2>/dev/null | head -1 | xargs
        fi
    else
        echo "ERROR: ORACLE_HOME or ORACLE_SID not set"
        return 1
    fi
}

#===============================================================================
# DISCOVERY SECTIONS
#===============================================================================

discover_os_info() {
    print_section "OS Information"
    {
        echo "=== OS INFORMATION ==="
        echo "Hostname: $(hostname -f 2>/dev/null || hostname)"
        echo "Short Hostname: $(hostname -s 2>/dev/null || hostname)"
        echo "IP Addresses:"
        ip addr show 2>/dev/null | grep 'inet ' | awk '{print "  " $2}' || ifconfig 2>/dev/null | grep 'inet ' | awk '{print "  " $2}'
        echo ""
        echo "Operating System:"
        cat /etc/os-release 2>/dev/null || cat /etc/oracle-release 2>/dev/null || uname -a
        echo ""
        echo "Kernel Version: $(uname -r)"
        echo "Architecture: $(uname -m)"
        echo ""
        log_section_result "OS Information" "success"
    } 2>&1 || log_section_result "OS Information" "failed"
}

discover_oracle_env() {
    print_section "Oracle Environment"
    {
        echo "=== ORACLE ENVIRONMENT ==="
        echo "ORACLE_HOME: ${ORACLE_HOME:-NOT SET}"
        echo "ORACLE_SID: ${ORACLE_SID:-NOT SET}"
        echo "ORACLE_BASE: ${ORACLE_BASE:-NOT SET}"
        echo ""
        echo "Oracle Version:"
        if [ -f "$ORACLE_HOME/bin/sqlplus" ]; then
            $ORACLE_HOME/bin/sqlplus -V 2>/dev/null | head -3
        fi
        echo ""
        echo "/etc/oratab contents:"
        cat /etc/oratab 2>/dev/null | grep -v '^#' | grep -v '^$' || echo "  File not found"
        echo ""
        log_section_result "Oracle Environment" "success"
    } 2>&1 || log_section_result "Oracle Environment" "failed"
}

discover_database_config() {
    print_section "Database Configuration"
    {
        echo "=== DATABASE CONFIGURATION ==="
        run_sql "
SELECT 'Database Name: ' || NAME FROM V\$DATABASE;
SELECT 'DB Unique Name: ' || DB_UNIQUE_NAME FROM V\$DATABASE;
SELECT 'DBID: ' || DBID FROM V\$DATABASE;
SELECT 'Database Role: ' || DATABASE_ROLE FROM V\$DATABASE;
SELECT 'Open Mode: ' || OPEN_MODE FROM V\$DATABASE;
SELECT 'Log Mode: ' || LOG_MODE FROM V\$DATABASE;
SELECT 'Force Logging: ' || FORCE_LOGGING FROM V\$DATABASE;
SELECT 'Platform Name: ' || PLATFORM_NAME FROM V\$DATABASE;
"
        echo ""
        echo "=== CHARACTER SET ==="
        run_sql "
SELECT 'Database Character Set: ' || VALUE FROM NLS_DATABASE_PARAMETERS WHERE PARAMETER = 'NLS_CHARACTERSET';
SELECT 'National Character Set: ' || VALUE FROM NLS_DATABASE_PARAMETERS WHERE PARAMETER = 'NLS_NCHAR_CHARACTERSET';
"
        echo ""
        log_section_result "Database Configuration" "success"
    } 2>&1 || log_section_result "Database Configuration" "failed"
}

discover_storage() {
    print_section "Storage Configuration"
    {
        echo "=== TABLESPACE INFORMATION ==="
        run_sql "
COL TABLESPACE_NAME FORMAT A30
COL SIZE_GB FORMAT 999,999.99
COL FREE_GB FORMAT 999,999.99
COL USED_PCT FORMAT 999.9
SELECT 
    DDF.TABLESPACE_NAME,
    ROUND(DDF.BYTES/1024/1024/1024, 2) AS SIZE_GB,
    ROUND(NVL(DFS.FREE_BYTES, 0)/1024/1024/1024, 2) AS FREE_GB,
    ROUND((DDF.BYTES - NVL(DFS.FREE_BYTES, 0)) / DDF.BYTES * 100, 1) AS USED_PCT
FROM 
    (SELECT TABLESPACE_NAME, SUM(BYTES) BYTES FROM DBA_DATA_FILES GROUP BY TABLESPACE_NAME) DDF
LEFT JOIN
    (SELECT TABLESPACE_NAME, SUM(BYTES) FREE_BYTES FROM DBA_FREE_SPACE GROUP BY TABLESPACE_NAME) DFS
ON DDF.TABLESPACE_NAME = DFS.TABLESPACE_NAME
ORDER BY TABLESPACE_NAME;
"
        echo ""
        echo "=== ASM DISK GROUPS (if applicable) ==="
        run_sql "
COL NAME FORMAT A20
COL TOTAL_GB FORMAT 999,999.99
COL FREE_GB FORMAT 999,999.99
COL USABLE_GB FORMAT 999,999.99
COL TYPE FORMAT A10
COL STATE FORMAT A12
SELECT NAME, 
       ROUND(TOTAL_MB/1024, 2) AS TOTAL_GB,
       ROUND(FREE_MB/1024, 2) AS FREE_GB,
       ROUND(USABLE_FILE_MB/1024, 2) AS USABLE_GB,
       TYPE, STATE
FROM V\$ASM_DISKGROUP;
"
        echo ""
        echo "=== DISK SPACE (OS Level) ==="
        df -h 2>/dev/null
        echo ""
        log_section_result "Storage Configuration" "success"
    } 2>&1 || log_section_result "Storage Configuration" "failed"
}

discover_cdb_pdb() {
    print_section "Container Database / PDBs"
    {
        echo "=== CDB STATUS ==="
        local cdb_status
        cdb_status=$(run_sql_value "SELECT CDB FROM V\$DATABASE;")
        echo "CDB Enabled: $cdb_status"
        echo ""
        
        if [ "$cdb_status" = "YES" ]; then
            echo "=== PDB INFORMATION ==="
            run_sql "
COL NAME FORMAT A30
COL OPEN_MODE FORMAT A15
COL RESTRICTED FORMAT A10
COL TOTAL_SIZE_GB FORMAT 999,999.99
SELECT CON_ID, NAME, OPEN_MODE, RESTRICTED, 
       ROUND(TOTAL_SIZE/1024/1024/1024, 2) AS TOTAL_SIZE_GB
FROM V\$PDBS ORDER BY CON_ID;
"
        fi
        echo ""
        log_section_result "CDB/PDB Status" "success"
    } 2>&1 || log_section_result "CDB/PDB Status" "failed"
}

discover_tde_wallet() {
    print_section "TDE/Wallet Configuration"
    {
        echo "=== TDE WALLET STATUS ==="
        run_sql "
COL WRL_TYPE FORMAT A10
COL WRL_PARAMETER FORMAT A60
COL STATUS FORMAT A15
COL WALLET_TYPE FORMAT A15
SELECT WRL_TYPE, WRL_PARAMETER, STATUS, WALLET_TYPE 
FROM V\$ENCRYPTION_WALLET;
"
        echo ""
        echo "=== WALLET PARAMETERS ==="
        run_sql "SHOW PARAMETER WALLET_ROOT;"
        run_sql "SHOW PARAMETER TDE_CONFIGURATION;"
        echo ""
        log_section_result "TDE/Wallet Configuration" "success"
    } 2>&1 || log_section_result "TDE/Wallet Configuration" "failed"
}

discover_network_config() {
    print_section "Network Configuration"
    {
        echo "=== LISTENER STATUS ==="
        if [ -n "${ORACLE_HOME:-}" ]; then
            $ORACLE_HOME/bin/lsnrctl status 2>&1 || echo "  Unable to get listener status"
        fi
        echo ""
        
        echo "=== SCAN LISTENER (if RAC) ==="
        if [ -f /u01/app/grid/*/bin/srvctl ]; then
            /u01/app/grid/*/bin/srvctl status scan_listener 2>&1 || echo "  No SCAN listener or not RAC"
        else
            echo "  Grid Infrastructure not found (may be single instance)"
        fi
        echo ""
        
        echo "=== TNSNAMES.ORA ==="
        for tns_file in "$ORACLE_HOME/network/admin/tnsnames.ora" "$TNS_ADMIN/tnsnames.ora" "/etc/tnsnames.ora"; do
            if [ -f "$tns_file" ]; then
                echo "File: $tns_file"
                cat "$tns_file"
                break
            fi
        done
        echo ""
        log_section_result "Network Configuration" "success"
    } 2>&1 || log_section_result "Network Configuration" "failed"
}

discover_oci_azure_integration() {
    print_section "OCI/Azure Integration"
    {
        echo "=== OCI CLI VERSION ==="
        oci --version 2>&1 || echo "  OCI CLI not installed"
        echo ""
        
        echo "=== OCI CONFIG ==="
        if [ -f ~/.oci/config ]; then
            echo "OCI config found at: ~/.oci/config"
            echo "Profiles:"
            grep '^\[' ~/.oci/config 2>/dev/null
            echo ""
            echo "Config (sensitive data masked):"
            cat ~/.oci/config 2>/dev/null | sed 's/key_file=.*/key_file=***MASKED***/g' | sed 's/fingerprint=.*/fingerprint=***MASKED***/g'
        else
            echo "  No OCI config found at ~/.oci/config"
        fi
        echo ""
        
        echo "=== OCI CONNECTIVITY TEST ==="
        if command -v oci >/dev/null 2>&1; then
            timeout 10 oci iam region list --output table 2>&1 | head -20 || echo "  OCI connectivity test failed or timed out"
        else
            echo "  OCI CLI not available"
        fi
        echo ""
        
        echo "=== INSTANCE METADATA (OCI) ==="
        curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/ 2>/dev/null | head -50 || echo "  Unable to retrieve OCI instance metadata"
        echo ""
        
        echo "=== INSTANCE METADATA (Azure) ==="
        curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" 2>/dev/null | head -50 || echo "  Unable to retrieve Azure instance metadata"
        echo ""
        log_section_result "OCI/Azure Integration" "success"
    } 2>&1 || log_section_result "OCI/Azure Integration" "failed"
}

discover_grid_crs() {
    print_section "Grid Infrastructure / CRS"
    {
        echo "=== GRID INFRASTRUCTURE STATUS ==="
        if [ -f /u01/app/grid/*/bin/crsctl ]; then
            echo "Grid Infrastructure found"
            /u01/app/grid/*/bin/crsctl stat res -t 2>&1 || echo "  Unable to get CRS status"
        else
            echo "  Grid Infrastructure not found (may be single instance)"
        fi
        echo ""
        
        echo "=== ORACLE RESTART STATUS (if applicable) ==="
        if [ -f "$ORACLE_HOME/bin/srvctl" ]; then
            $ORACLE_HOME/bin/srvctl status database -d ${ORACLE_SID:-ORCL} 2>&1 || echo "  Unable to get database status via srvctl"
        fi
        echo ""
        log_section_result "Grid/CRS Status" "success"
    } 2>&1 || log_section_result "Grid/CRS Status" "failed"
}

discover_authentication() {
    print_section "Authentication Configuration"
    {
        echo "=== PASSWORD FILE ==="
        run_sql "SHOW PARAMETER REMOTE_LOGIN_PASSWORDFILE;"
        echo ""
        echo "Password file location:"
        ls -la $ORACLE_HOME/dbs/orapw* 2>/dev/null || echo "  No password file found in \$ORACLE_HOME/dbs/"
        echo ""
        
        echo "=== SSH DIRECTORY ==="
        echo "SSH directory contents (current user):"
        ls -la ~/.ssh/ 2>/dev/null || echo "  No .ssh directory"
        echo ""
        
        echo "SSH directory contents (oracle user):"
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            ls -la ~/.ssh/ 2>/dev/null || echo "  No .ssh directory"
        else
            sudo -u "$ORACLE_USER" ls -la ~$ORACLE_USER/.ssh/ 2>/dev/null || echo "  No .ssh directory or permission denied"
        fi
        echo ""
        log_section_result "Authentication Configuration" "success"
    } 2>&1 || log_section_result "Authentication Configuration" "failed"
}

#===============================================================================
# ADDITIONAL DISCOVERY (Project-specific requirements)
#===============================================================================

discover_exadata_storage() {
    print_section "Exadata Storage Capacity"
    {
        echo "=== EXADATA STORAGE (if applicable) ==="
        run_sql "
COL NAME FORMAT A20
COL TYPE FORMAT A10
COL TOTAL_GB FORMAT 999,999.99
COL FREE_GB FORMAT 999,999.99
COL STATE FORMAT A15
SELECT NAME, TYPE, 
       ROUND(TOTAL_MB/1024, 2) AS TOTAL_GB,
       ROUND(FREE_MB/1024, 2) AS FREE_GB,
       STATE
FROM V\$ASM_DISKGROUP
ORDER BY NAME;
"
        echo ""
        
        echo "=== AVAILABLE STORAGE FOR NEW DATABASES ==="
        run_sql "
SELECT 'Total Free Space in ASM (GB): ' || ROUND(SUM(FREE_MB)/1024, 2) 
FROM V\$ASM_DISKGROUP 
WHERE STATE = 'MOUNTED';
"
        echo ""
        
        echo "=== EXADATA CELL STATUS (if applicable) ==="
        if command -v cellcli >/dev/null 2>&1; then
            cellcli -e list cell detail 2>&1 || echo "  Unable to get cell status"
        else
            echo "  cellcli not available (may not be Exadata)"
        fi
        echo ""
        log_section_result "Exadata Storage" "success"
    } 2>&1 || log_section_result "Exadata Storage" "failed"
}

discover_preconfigured_pdbs() {
    print_section "Pre-configured PDBs"
    {
        echo "=== EXISTING PDBs ==="
        run_sql "
COL PDB_NAME FORMAT A30
COL STATUS FORMAT A15
COL OPEN_MODE FORMAT A15
COL CREATION_TIME FORMAT A25
SELECT PDB_NAME, STATUS, OPEN_MODE, 
       TO_CHAR(CREATION_TIME, 'YYYY-MM-DD HH24:MI:SS') AS CREATION_TIME
FROM DBA_PDBS
ORDER BY CON_ID;
"
        echo ""
        
        echo "=== PDB DATAFILES ==="
        run_sql "
COL PDB_NAME FORMAT A20
COL FILE_NAME FORMAT A60
COL SIZE_GB FORMAT 999,999.99
SELECT P.PDB_NAME, D.FILE_NAME, 
       ROUND(D.BYTES/1024/1024/1024, 2) AS SIZE_GB
FROM DBA_PDBS P, CDB_DATA_FILES D
WHERE P.CON_ID = D.CON_ID
ORDER BY P.PDB_NAME, D.FILE_NAME;
"
        echo ""
        
        echo "=== PDB SERVICES ==="
        run_sql "
COL PDB_NAME FORMAT A20
COL SERVICE_NAME FORMAT A40
COL NETWORK_NAME FORMAT A40
SELECT P.PDB_NAME, S.NAME AS SERVICE_NAME, S.NETWORK_NAME
FROM DBA_PDBS P, CDB_SERVICES S
WHERE P.CON_ID = S.CON_ID
  AND S.NAME NOT LIKE 'SYS%'
ORDER BY P.PDB_NAME, S.NAME;
"
        echo ""
        log_section_result "Pre-configured PDBs" "success"
    } 2>&1 || log_section_result "Pre-configured PDBs" "failed"
}

discover_network_security() {
    print_section "Network Security Group Rules"
    {
        echo "=== FIREWALL STATUS (OS Level) ==="
        systemctl status firewalld 2>&1 | head -10 || echo "  firewalld not available"
        echo ""
        
        echo "=== IPTABLES RULES ==="
        iptables -L -n 2>&1 | head -30 || echo "  Unable to list iptables rules (may require root)"
        echo ""
        
        echo "=== LISTENING PORTS ==="
        ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null || echo "  Unable to list listening ports"
        echo ""
        
        echo "=== NSG RULES (from Azure metadata if available) ==="
        # Try to get network info from Azure IMDS
        curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance/network?api-version=2021-02-01" 2>/dev/null | head -30 || echo "  Unable to retrieve Azure network metadata"
        echo ""
        
        echo "=== OCI SECURITY LISTS (if applicable) ==="
        if command -v oci >/dev/null 2>&1; then
            echo "Note: Use OCI Console or CLI with compartment ID to view NSG/Security List rules"
        fi
        echo ""
        log_section_result "Network Security" "success"
    } 2>&1 || log_section_result "Network Security" "failed"
}

#===============================================================================
# JSON OUTPUT GENERATION
#===============================================================================

generate_json_summary() {
    print_section "Generating JSON Summary"
    
    local db_name db_unique_name db_role open_mode cdb_status charset tde_status
    local asm_free_gb pdb_count
    
    db_name=$(run_sql_value "SELECT NAME FROM V\$DATABASE;")
    db_unique_name=$(run_sql_value "SELECT DB_UNIQUE_NAME FROM V\$DATABASE;")
    db_role=$(run_sql_value "SELECT DATABASE_ROLE FROM V\$DATABASE;")
    open_mode=$(run_sql_value "SELECT OPEN_MODE FROM V\$DATABASE;")
    cdb_status=$(run_sql_value "SELECT CDB FROM V\$DATABASE;")
    charset=$(run_sql_value "SELECT VALUE FROM NLS_DATABASE_PARAMETERS WHERE PARAMETER = 'NLS_CHARACTERSET';")
    tde_status=$(run_sql_value "SELECT STATUS FROM V\$ENCRYPTION_WALLET WHERE ROWNUM = 1;")
    asm_free_gb=$(run_sql_value "SELECT ROUND(SUM(FREE_MB)/1024, 2) FROM V\$ASM_DISKGROUP WHERE STATE = 'MOUNTED';")
    pdb_count=$(run_sql_value "SELECT COUNT(*) FROM DBA_PDBS WHERE STATUS != 'UNUSABLE';")
    
    cat > "$JSON_FILE" << EOJSON
{
    "discovery_type": "target",
    "discovery_timestamp": "$(date -Iseconds)",
    "hostname": "$HOSTNAME",
    "oracle_home": "${ORACLE_HOME:-}",
    "oracle_sid": "${ORACLE_SID:-}",
    "database": {
        "name": "$db_name",
        "unique_name": "$db_unique_name",
        "role": "$db_role",
        "open_mode": "$open_mode",
        "cdb": "$cdb_status",
        "pdb_count": ${pdb_count:-0},
        "character_set": "$charset"
    },
    "storage": {
        "asm_free_gb": ${asm_free_gb:-0}
    },
    "tde": {
        "status": "${tde_status:-NOT_CONFIGURED}"
    },
    "discovery_status": {
        "successful_sections": [$(printf '"%s",' "${SUCCESS_SECTIONS[@]}" | sed 's/,$//')]
        "failed_sections": [$(printf '"%s",' "${FAILED_SECTIONS[@]}" | sed 's/,$//')]
    }
}
EOJSON
    
    print_success "JSON summary written to: $JSON_FILE"
}

#===============================================================================
# MAIN EXECUTION
#===============================================================================

main() {
    print_header "ZDM Target Database Discovery"
    echo "Project: PRODDB Migration to Oracle Database@Azure"
    echo "Timestamp: $(date)"
    echo "Output File: $OUTPUT_FILE"
    echo ""
    
    # Detect Oracle environment
    detect_oracle_env
    if [ $? -ne 0 ]; then
        print_warning "Oracle environment not fully detected - continuing with available checks"
    fi
    
    # Run all discovery sections and capture to output file
    {
        echo "==============================================================================="
        echo "ZDM TARGET DATABASE DISCOVERY REPORT"
        echo "==============================================================================="
        echo "Project: PRODDB Migration to Oracle Database@Azure"
        echo "Hostname: $HOSTNAME"
        echo "Timestamp: $(date)"
        echo "ORACLE_HOME: ${ORACLE_HOME:-NOT SET}"
        echo "ORACLE_SID: ${ORACLE_SID:-NOT SET}"
        echo "==============================================================================="
        echo ""
        
        # Standard discovery sections
        discover_os_info
        discover_oracle_env
        discover_database_config
        discover_storage
        discover_cdb_pdb
        discover_tde_wallet
        discover_network_config
        discover_oci_azure_integration
        discover_grid_crs
        discover_authentication
        
        # Additional discovery (project-specific)
        discover_exadata_storage
        discover_preconfigured_pdbs
        discover_network_security
        
        echo ""
        echo "==============================================================================="
        echo "DISCOVERY SUMMARY"
        echo "==============================================================================="
        echo "Successful Sections: ${#SUCCESS_SECTIONS[@]}"
        echo "Failed Sections: ${#FAILED_SECTIONS[@]}"
        if [ ${#FAILED_SECTIONS[@]} -gt 0 ]; then
            echo "Failed: ${FAILED_SECTIONS[*]}"
        fi
        echo "==============================================================================="
        
    } 2>&1 | tee "$OUTPUT_FILE"
    
    # Generate JSON summary
    generate_json_summary
    
    print_header "Discovery Complete"
    echo "Text Report: $OUTPUT_FILE"
    echo "JSON Summary: $JSON_FILE"
    echo ""
    
    if [ ${#FAILED_SECTIONS[@]} -gt 0 ]; then
        print_warning "Some sections failed. Check the output for details."
        exit 1
    else
        print_success "All discovery sections completed successfully"
        exit 0
    fi
}

# Run main function
main "$@"
