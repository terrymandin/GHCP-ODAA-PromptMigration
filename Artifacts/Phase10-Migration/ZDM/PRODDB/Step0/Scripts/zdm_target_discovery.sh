#!/bin/bash
################################################################################
# ZDM Target Database Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# Target: proddb-oda.eastus.azure.example.com (Oracle Database@Azure)
#
# Purpose: Discover target database configuration and environment details
# Execution: Run via SSH as ADMIN_USER (opc) with sudo privileges
################################################################################

# Configuration - User defaults
ORACLE_USER="${ORACLE_USER:-oracle}"

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Timestamp for output files
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname -f 2>/dev/null || hostname)

# Output files in current working directory
OUTPUT_TXT="./zdm_target_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
OUTPUT_JSON="./zdm_target_discovery_${HOSTNAME}_${TIMESTAMP}.json"

# Initialize JSON output
json_data="{}"

################################################################################
# Utility Functions
################################################################################

log_section() {
    local title="$1"
    echo "" | tee -a "$OUTPUT_TXT"
    echo "========================================" | tee -a "$OUTPUT_TXT"
    echo "$title" | tee -a "$OUTPUT_TXT"
    echo "========================================" | tee -a "$OUTPUT_TXT"
    echo -e "${BLUE}▶ $title${NC}"
}

log_info() {
    echo "$1" | tee -a "$OUTPUT_TXT"
    echo -e "${GREEN}  $1${NC}"
}

log_warn() {
    echo "WARNING: $1" | tee -a "$OUTPUT_TXT"
    echo -e "${YELLOW}  ⚠ WARNING: $1${NC}"
}

log_error() {
    echo "ERROR: $1" | tee -a "$OUTPUT_TXT"
    echo -e "${RED}  ✗ ERROR: $1${NC}"
}

add_json_field() {
    local key="$1"
    local value="$2"
    # Escape quotes in value
    value="${value//\"/\\\"}"
    json_data=$(echo "$json_data" | jq --arg k "$key" --arg v "$value" '. + {($k): $v}')
}

################################################################################
# Oracle Environment Auto-Detection
################################################################################

detect_oracle_env() {
    log_section "Oracle Environment Detection"
    
    # If already set, use existing values
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        log_info "Using existing ORACLE_HOME: $ORACLE_HOME"
        log_info "Using existing ORACLE_SID: $ORACLE_SID"
        return 0
    fi
    
    # Method 1: Parse /etc/oratab (most reliable)
    if [ -f /etc/oratab ]; then
        log_info "Checking /etc/oratab..."
        local oratab_entry
        if [ -n "${ORACLE_SID:-}" ]; then
            oratab_entry=$(grep "^${ORACLE_SID}:" /etc/oratab 2>/dev/null | head -1)
        else
            oratab_entry=$(grep -v '^#' /etc/oratab | grep -v '^$' | head -1)
        fi
        if [ -n "$oratab_entry" ]; then
            export ORACLE_SID="${ORACLE_SID:-$(echo "$oratab_entry" | cut -d: -f1)}"
            export ORACLE_HOME="${ORACLE_HOME:-$(echo "$oratab_entry" | cut -d: -f2)}"
            log_info "Found from /etc/oratab - SID: $ORACLE_SID, HOME: $ORACLE_HOME"
        fi
    fi
    
    # Method 2: Check running pmon process
    if [ -z "${ORACLE_SID:-}" ]; then
        log_info "Checking running pmon processes..."
        local pmon_sid
        pmon_sid=$(ps -ef | grep 'ora_pmon_' | grep -v grep | head -1 | sed 's/.*ora_pmon_//')
        if [ -n "$pmon_sid" ]; then
            export ORACLE_SID="$pmon_sid"
            log_info "Found from pmon process - SID: $ORACLE_SID"
        fi
    fi
    
    # Method 3: Search common Oracle installation paths
    if [ -z "${ORACLE_HOME:-}" ]; then
        log_info "Searching common Oracle installation paths..."
        for path in /u01/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1 /oracle/product/*/dbhome_1; do
            if [ -d "$path" ] && [ -f "$path/bin/sqlplus" ]; then
                export ORACLE_HOME="$path"
                log_info "Found ORACLE_HOME: $ORACLE_HOME"
                break
            fi
        done
    fi
    
    # Apply explicit overrides if provided (highest priority)
    [ -n "${ORACLE_HOME_OVERRIDE:-}" ] && export ORACLE_HOME="$ORACLE_HOME_OVERRIDE"
    [ -n "${ORACLE_SID_OVERRIDE:-}" ] && export ORACLE_SID="$ORACLE_SID_OVERRIDE"
    
    # Set ORACLE_BASE if not already set
    if [ -n "${ORACLE_HOME:-}" ] && [ -z "${ORACLE_BASE:-}" ]; then
        export ORACLE_BASE=$(dirname $(dirname "$ORACLE_HOME"))
    fi
    
    # Verify detection
    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        log_error "Failed to detect Oracle environment"
        log_error "Please set ORACLE_HOME and ORACLE_SID environment variables"
        return 1
    fi
    
    log_info "✓ Oracle environment detected successfully"
    log_info "  ORACLE_HOME: $ORACLE_HOME"
    log_info "  ORACLE_SID: $ORACLE_SID"
    log_info "  ORACLE_BASE: ${ORACLE_BASE:-not set}"
    
    return 0
}

################################################################################
# SQL Execution Function
################################################################################

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
            echo "$sql_script" | $sqlplus_cmd 2>&1
        else
            echo "$sql_script" | sudo -u "$ORACLE_USER" -E ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd 2>&1
        fi
    else
        echo "ERROR: ORACLE_HOME or ORACLE_SID not set"
        return 1
    fi
}

run_sql_value() {
    local sql_query="$1"
    local result
    result=$(run_sql "$sql_query" | grep -v "^$" | tail -1)
    echo "$result"
}

################################################################################
# Main Discovery Functions
################################################################################

gather_os_info() {
    log_section "Operating System Information"
    
    log_info "Hostname: $(hostname -f 2>/dev/null || hostname)"
    add_json_field "hostname" "$(hostname -f 2>/dev/null || hostname)"
    
    log_info "IP Addresses:"
    ip addr show | grep 'inet ' | awk '{print "  " $2}' | tee -a "$OUTPUT_TXT"
    
    log_info "OS Version:"
    if [ -f /etc/os-release ]; then
        cat /etc/os-release | tee -a "$OUTPUT_TXT"
        os_version=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
        add_json_field "os_version" "$os_version"
    elif [ -f /etc/oracle-release ]; then
        cat /etc/oracle-release | tee -a "$OUTPUT_TXT"
        add_json_field "os_version" "$(cat /etc/oracle-release)"
    fi
    
    log_info "Disk Space:"
    df -h | tee -a "$OUTPUT_TXT"
    
    log_info "Memory:"
    free -h | tee -a "$OUTPUT_TXT"
}

gather_oracle_info() {
    log_section "Oracle Environment"
    
    log_info "ORACLE_HOME: ${ORACLE_HOME:-not set}"
    log_info "ORACLE_SID: ${ORACLE_SID:-not set}"
    log_info "ORACLE_BASE: ${ORACLE_BASE:-not set}"
    
    add_json_field "oracle_home" "${ORACLE_HOME:-}"
    add_json_field "oracle_sid" "${ORACLE_SID:-}"
    add_json_field "oracle_base" "${ORACLE_BASE:-}"
    
    if [ -n "${ORACLE_HOME:-}" ] && [ -f "$ORACLE_HOME/bin/sqlplus" ]; then
        log_info "Oracle Version:"
        local oracle_version
        oracle_version=$(run_sql_value "SELECT banner FROM v\$version WHERE ROWNUM = 1;")
        log_info "$oracle_version"
        add_json_field "oracle_version" "$oracle_version"
    fi
}

gather_database_config() {
    log_section "Database Configuration"
    
    # Database name and DB unique name
    local db_name=$(run_sql_value "SELECT name FROM v\$database;")
    local db_unique_name=$(run_sql_value "SELECT db_unique_name FROM v\$database;")
    
    log_info "Database Name: $db_name"
    log_info "DB Unique Name: $db_unique_name"
    
    add_json_field "db_name" "$db_name"
    add_json_field "db_unique_name" "$db_unique_name"
    
    # Database role and open mode
    local db_role=$(run_sql_value "SELECT database_role FROM v\$database;")
    local open_mode=$(run_sql_value "SELECT open_mode FROM v\$database;")
    
    log_info "Database Role: $db_role"
    log_info "Open Mode: $open_mode"
    
    add_json_field "db_role" "$db_role"
    add_json_field "open_mode" "$open_mode"
    
    # Character set
    local charset=$(run_sql_value "SELECT value FROM nls_database_parameters WHERE parameter = 'NLS_CHARACTERSET';")
    
    log_info "Character Set: $charset"
    add_json_field "character_set" "$charset"
}

gather_storage_info() {
    log_section "Available Storage"
    
    log_info "Tablespaces and Space:"
    run_sql "SELECT tablespace_name, ROUND(SUM(bytes)/1024/1024/1024, 2) AS allocated_gb, ROUND(SUM(maxbytes)/1024/1024/1024, 2) AS max_gb, COUNT(*) AS files FROM dba_data_files GROUP BY tablespace_name ORDER BY tablespace_name;" | tee -a "$OUTPUT_TXT"
    
    # Check if ASM is in use
    log_info "ASM Configuration:"
    if command -v asmcmd &> /dev/null; then
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            asmcmd lsdg 2>&1 | tee -a "$OUTPUT_TXT"
        else
            sudo -u "$ORACLE_USER" asmcmd lsdg 2>&1 | tee -a "$OUTPUT_TXT"
        fi
    else
        log_info "ASM command not available"
    fi
}

gather_exadata_storage() {
    log_section "Exadata Storage Capacity"
    
    log_info "Checking Exadata storage..."
    
    # Check for Exadata-specific views
    local is_exadata=$(run_sql_value "SELECT COUNT(*) FROM dba_tables WHERE owner = 'SYS' AND table_name = 'V\$CELL';")
    
    if [ "$is_exadata" -gt 0 ]; then
        log_info "Exadata environment detected"
        add_json_field "is_exadata" "true"
        
        log_info "Cell Disk Space:"
        run_sql "SELECT name, total_size/1024/1024/1024 AS total_gb, free_size/1024/1024/1024 AS free_gb FROM v\$cell ORDER BY name;" | tee -a "$OUTPUT_TXT"
        
        log_info "Flash Cache Statistics:"
        run_sql "SELECT name, flash_cache_size/1024/1024/1024 AS flash_cache_gb FROM v\$cell ORDER BY name;" | tee -a "$OUTPUT_TXT"
    else
        log_info "Not an Exadata environment"
        add_json_field "is_exadata" "false"
    fi
}

gather_cdb_info() {
    log_section "Container Database Information"
    
    local cdb=$(run_sql_value "SELECT cdb FROM v\$database;")
    log_info "CDB: $cdb"
    add_json_field "cdb" "$cdb"
    
    if [ "$cdb" = "YES" ]; then
        log_info "Pre-configured PDBs:"
        run_sql "SELECT con_id, name, open_mode, restricted, open_time, total_size/1024/1024/1024 AS size_gb FROM v\$pdbs ORDER BY name;" | tee -a "$OUTPUT_TXT"
        
        log_info "PDB Tablespaces:"
        run_sql "SELECT t.con_id, p.name AS pdb_name, t.tablespace_name, t.status FROM cdb_tablespaces t JOIN v\$pdbs p ON t.con_id = p.con_id WHERE t.con_id > 2 ORDER BY t.con_id, t.tablespace_name;" | tee -a "$OUTPUT_TXT"
    fi
}

gather_tde_info() {
    log_section "TDE Configuration"
    
    log_info "Wallet Status:"
    run_sql "SELECT * FROM v\$encryption_wallet;" | tee -a "$OUTPUT_TXT"
}

gather_network_config() {
    log_section "Network Configuration"
    
    # Listener status
    log_info "Listener Status:"
    if [ -n "${ORACLE_HOME:-}" ]; then
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            $ORACLE_HOME/bin/lsnrctl status 2>&1 | tee -a "$OUTPUT_TXT"
        else
            sudo -u "$ORACLE_USER" $ORACLE_HOME/bin/lsnrctl status 2>&1 | tee -a "$OUTPUT_TXT"
        fi
    fi
    
    # Check for SCAN listener (RAC)
    log_info "SCAN Listener Configuration:"
    if [ -n "${ORACLE_HOME:-}" ]; then
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            $ORACLE_HOME/bin/srvctl config scan 2>&1 | tee -a "$OUTPUT_TXT" || log_info "Not a RAC environment"
        else
            sudo -u "$ORACLE_USER" $ORACLE_HOME/bin/srvctl config scan 2>&1 | tee -a "$OUTPUT_TXT" || log_info "Not a RAC environment"
        fi
    fi
    
    # tnsnames.ora
    log_info "tnsnames.ora:"
    if [ -f "$ORACLE_HOME/network/admin/tnsnames.ora" ]; then
        cat "$ORACLE_HOME/network/admin/tnsnames.ora" | tee -a "$OUTPUT_TXT"
    else
        log_warn "tnsnames.ora not found"
    fi
}

gather_network_security() {
    log_section "Network Security Group Rules"
    
    log_info "Firewall Status:"
    if command -v firewall-cmd &> /dev/null; then
        sudo firewall-cmd --list-all 2>&1 | tee -a "$OUTPUT_TXT"
    else
        log_info "firewall-cmd not available"
    fi
    
    log_info "Active Network Connections:"
    netstat -tuln 2>&1 | grep LISTEN | tee -a "$OUTPUT_TXT"
    
    log_info "IPTables Rules (if applicable):"
    sudo iptables -L -n 2>&1 | tee -a "$OUTPUT_TXT" || log_info "iptables not available or not permitted"
}

gather_oci_integration() {
    log_section "OCI/Azure Integration"
    
    # OCI CLI version
    log_info "OCI CLI Version:"
    if command -v oci &> /dev/null; then
        oci --version 2>&1 | tee -a "$OUTPUT_TXT"
        add_json_field "oci_cli_installed" "true"
        
        log_info "OCI Configuration:"
        if [ -f ~/.oci/config ]; then
            log_info "OCI config file exists"
            # Show config but mask sensitive data
            grep -E "^\[|^user|^tenancy|^region" ~/.oci/config 2>&1 | tee -a "$OUTPUT_TXT"
        else
            log_warn "OCI config file not found"
        fi
        
        log_info "OCI Connectivity Test:"
        oci iam region list 2>&1 | head -10 | tee -a "$OUTPUT_TXT" || log_warn "OCI connectivity test failed"
    else
        log_warn "OCI CLI not installed"
        add_json_field "oci_cli_installed" "false"
    fi
    
    # Instance metadata (OCI)
    log_info "OCI Instance Metadata:"
    curl -s -H "Authorization: Bearer Oracle" -m 5 http://169.254.169.254/opc/v2/instance/ 2>&1 | tee -a "$OUTPUT_TXT" || log_info "Not an OCI instance or metadata service unavailable"
    
    # Azure metadata
    log_info "Azure Instance Metadata:"
    curl -s -H "Metadata:true" -m 5 "http://169.254.169.254/metadata/instance?api-version=2021-02-01" 2>&1 | tee -a "$OUTPUT_TXT" || log_info "Not an Azure instance or metadata service unavailable"
}

gather_grid_infrastructure() {
    log_section "Grid Infrastructure"
    
    log_info "Checking for Grid Infrastructure..."
    
    if command -v crsctl &> /dev/null; then
        log_info "CRS Status:"
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            crsctl check crs 2>&1 | tee -a "$OUTPUT_TXT"
            crsctl status resource -t 2>&1 | tee -a "$OUTPUT_TXT"
        else
            sudo -u "$ORACLE_USER" crsctl check crs 2>&1 | tee -a "$OUTPUT_TXT"
            sudo -u "$ORACLE_USER" crsctl status resource -t 2>&1 | tee -a "$OUTPUT_TXT"
        fi
        add_json_field "grid_infrastructure" "true"
    else
        log_info "Grid Infrastructure not detected"
        add_json_field "grid_infrastructure" "false"
    fi
}

gather_authentication() {
    log_section "Authentication"
    
    # SSH directory
    log_info "SSH Directory:"
    local oracle_home_dir
    if [ "$(whoami)" = "$ORACLE_USER" ]; then
        oracle_home_dir="$HOME"
    else
        oracle_home_dir=$(eval echo ~"$ORACLE_USER")
    fi
    
    if [ -d "$oracle_home_dir/.ssh" ]; then
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            ls -la "$oracle_home_dir/.ssh" 2>&1 | tee -a "$OUTPUT_TXT"
        else
            sudo -u "$ORACLE_USER" ls -la "$oracle_home_dir/.ssh" 2>&1 | tee -a "$OUTPUT_TXT"
        fi
    else
        log_warn "SSH directory not found for oracle user"
    fi
}

################################################################################
# Main Execution
################################################################################

main() {
    echo "========================================" | tee "$OUTPUT_TXT"
    echo "ZDM Target Database Discovery" | tee -a "$OUTPUT_TXT"
    echo "Project: PRODDB Migration to Oracle Database@Azure" | tee -a "$OUTPUT_TXT"
    echo "Target: proddb-oda.eastus.azure.example.com" | tee -a "$OUTPUT_TXT"
    echo "Timestamp: $(date)" | tee -a "$OUTPUT_TXT"
    echo "========================================" | tee -a "$OUTPUT_TXT"
    
    # Initialize JSON
    json_data=$(jq -n '{}')
    add_json_field "discovery_type" "target"
    add_json_field "timestamp" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    add_json_field "project" "PRODDB Migration to Oracle Database@Azure"
    add_json_field "target_host" "proddb-oda.eastus.azure.example.com"
    
    # Detect Oracle environment first
    if ! detect_oracle_env; then
        log_error "Failed to detect Oracle environment. Cannot proceed with database queries."
        echo "$json_data" | jq '.' > "$OUTPUT_JSON"
        exit 1
    fi
    
    # Run all discovery functions with error handling
    gather_os_info || log_error "Failed to gather OS info"
    gather_oracle_info || log_error "Failed to gather Oracle info"
    gather_database_config || log_error "Failed to gather database config"
    gather_storage_info || log_error "Failed to gather storage info"
    gather_exadata_storage || log_error "Failed to gather Exadata storage info"
    gather_cdb_info || log_error "Failed to gather CDB info"
    gather_tde_info || log_error "Failed to gather TDE info"
    gather_network_config || log_error "Failed to gather network config"
    gather_network_security || log_error "Failed to gather network security info"
    gather_oci_integration || log_error "Failed to gather OCI integration info"
    gather_grid_infrastructure || log_error "Failed to gather Grid Infrastructure info"
    gather_authentication || log_error "Failed to gather authentication info"
    
    # Write JSON output
    echo "$json_data" | jq '.' > "$OUTPUT_JSON"
    
    log_section "Discovery Complete"
    log_info "Text report: $OUTPUT_TXT"
    log_info "JSON summary: $OUTPUT_JSON"
    
    echo -e "\n${GREEN}✓ Target database discovery completed successfully${NC}"
}

# Run main function
main
