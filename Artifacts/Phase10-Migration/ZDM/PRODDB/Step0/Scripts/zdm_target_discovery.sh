#!/bin/bash
# =============================================================================
# ZDM Target Database Discovery Script (Oracle Database@Azure)
# =============================================================================
# Project: PRODDB Migration to Oracle Database@Azure
# Target Server: proddb-oda.eastus.azure.example.com
# Generated: 2026-01-30
#
# Purpose:
#   Gather comprehensive discovery information from the target Oracle 
#   Database@Azure server to support ZDM migration planning and execution.
#
# Execution:
#   This script is executed via SSH as the admin user (opc), with SQL 
#   commands running as the oracle user via sudo if needed.
#
# Output:
#   - Text report: ./zdm_target_discovery_<hostname>_<timestamp>.txt
#   - JSON summary: ./zdm_target_discovery_<hostname>_<timestamp>.json
# =============================================================================

# NO set -e - We want to continue even if some checks fail
SECTION_ERRORS=0

# =============================================================================
# COLOR CONFIGURATION
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# =============================================================================
# USER CONFIGURATION
# =============================================================================
# Oracle database software owner (for running SQL commands)
ORACLE_USER="${ORACLE_USER:-oracle}"

# =============================================================================
# ENVIRONMENT VARIABLE DISCOVERY
# =============================================================================

# CRITICAL: Handle environment variables in non-interactive SSH sessions
# .bashrc often has guards like '[ -z "$PS1" ] && return' that skip non-interactive shells

# Method 1: Accept explicit overrides (passed from orchestration script - highest priority)
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
    
    # Try oratab first (most reliable)
    if [ -f /etc/oratab ]; then
        local oratab_entry
        if [ -n "${ORACLE_SID:-}" ]; then
            oratab_entry=$(grep "^${ORACLE_SID}:" /etc/oratab 2>/dev/null | head -1)
        else
            oratab_entry=$(grep -v '^#' /etc/oratab | grep -v '^$' | grep ':' | grep -v '^+' | head -1)
        fi
        if [ -n "$oratab_entry" ]; then
            export ORACLE_SID="${ORACLE_SID:-$(echo "$oratab_entry" | cut -d: -f1)}"
            export ORACLE_HOME="${ORACLE_HOME:-$(echo "$oratab_entry" | cut -d: -f2)}"
        fi
    fi
    
    # Check running pmon process
    if [ -z "${ORACLE_SID:-}" ]; then
        local pmon_sid
        pmon_sid=$(ps -ef | grep 'ora_pmon_' | grep -v grep | grep -v '+ASM' | head -1 | sed 's/.*ora_pmon_//')
        [ -n "$pmon_sid" ] && export ORACLE_SID="$pmon_sid"
    fi
    
    # Search common Oracle installation paths (ODA paths)
    if [ -z "${ORACLE_HOME:-}" ]; then
        for path in /u01/app/oracle/product/*/dbhome_1 /u02/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1; do
            if [ -d "$path" ] && [ -f "$path/bin/sqlplus" ]; then
                export ORACLE_HOME="$path"
                break
            fi
        done
    fi
    
    # Derive ORACLE_BASE if not set
    if [ -z "${ORACLE_BASE:-}" ] && [ -n "${ORACLE_HOME:-}" ]; then
        export ORACLE_BASE=$(echo "$ORACLE_HOME" | sed 's|/product/.*||')
    fi
    
    # Detect Grid Infrastructure home
    if [ -z "${GRID_HOME:-}" ]; then
        # Check oratab for ASM entry
        local grid_entry
        grid_entry=$(grep '^+ASM' /etc/oratab 2>/dev/null | head -1)
        if [ -n "$grid_entry" ]; then
            export GRID_HOME=$(echo "$grid_entry" | cut -d: -f2)
        else
            # Search common Grid home locations
            for path in /u01/app/*/grid /u01/app/grid /opt/oracle/grid; do
                if [ -d "$path" ] && [ -f "$path/bin/crsctl" ]; then
                    export GRID_HOME="$path"
                    break
                fi
            done
        fi
    fi
}

detect_oracle_env

# =============================================================================
# OUTPUT CONFIGURATION
# =============================================================================
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname)
OUTPUT_FILE="./zdm_target_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_target_discovery_${HOSTNAME}_${TIMESTAMP}.json"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

log_section() {
    local section_name="$1"
    echo "" | tee -a "$OUTPUT_FILE"
    echo "=============================================================================" | tee -a "$OUTPUT_FILE"
    echo " $section_name" | tee -a "$OUTPUT_FILE"
    echo "=============================================================================" | tee -a "$OUTPUT_FILE"
    echo -e "${CYAN}[SECTION]${NC} $section_name"
}

log_info() {
    echo "$1" | tee -a "$OUTPUT_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    echo "[SUCCESS] $1" >> "$OUTPUT_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "[WARNING] $1" >> "$OUTPUT_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[ERROR] $1" >> "$OUTPUT_FILE"
}

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
            echo "$sql_script" | ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd 2>&1
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
    run_sql "$sql_query" | grep -v '^$' | tail -1 | xargs
}

run_grid_cmd() {
    local cmd="$1"
    if [ -n "${GRID_HOME:-}" ]; then
        if [ "$(whoami)" = "grid" ]; then
            $GRID_HOME/bin/$cmd 2>&1
        else
            sudo -u grid $GRID_HOME/bin/$cmd 2>&1 || $GRID_HOME/bin/$cmd 2>&1
        fi
    else
        echo "GRID_HOME not set"
        return 1
    fi
}

# =============================================================================
# INITIALIZE JSON OUTPUT
# =============================================================================
init_json() {
    cat > "$JSON_FILE" <<EOF
{
  "discovery_type": "target",
  "timestamp": "$(date -Iseconds)",
  "hostname": "$HOSTNAME",
  "project": "PRODDB Migration to Oracle Database@Azure",
  "target_server": "proddb-oda.eastus.azure.example.com",
  "platform": "Oracle Database@Azure",
EOF
}

append_json() {
    local key="$1"
    local value="$2"
    echo "  \"$key\": \"$value\"," >> "$JSON_FILE"
}

append_json_object() {
    local key="$1"
    local value="$2"
    echo "  \"$key\": $value," >> "$JSON_FILE"
}

finalize_json() {
    echo "  \"discovery_complete\": true" >> "$JSON_FILE"
    echo "}" >> "$JSON_FILE"
}

# =============================================================================
# DISCOVERY FUNCTIONS
# =============================================================================

discover_os_info() {
    log_section "OPERATING SYSTEM INFORMATION"
    
    log_info "Hostname: $(hostname)"
    log_info "FQDN: $(hostname -f 2>/dev/null || hostname)"
    log_info ""
    
    log_info "IP Addresses:"
    ip addr show 2>/dev/null | grep "inet " | awk '{print $2}' | tee -a "$OUTPUT_FILE" || \
        ifconfig 2>/dev/null | grep "inet " | awk '{print $2}' | tee -a "$OUTPUT_FILE" || \
        hostname -I 2>/dev/null | tee -a "$OUTPUT_FILE"
    log_info ""
    
    log_info "Operating System:"
    cat /etc/os-release 2>/dev/null | head -5 | tee -a "$OUTPUT_FILE" || \
        cat /etc/oracle-release 2>/dev/null | tee -a "$OUTPUT_FILE" || \
        uname -a | tee -a "$OUTPUT_FILE"
    log_info ""
    
    log_info "Kernel Version: $(uname -r)"
    
    append_json "hostname" "$HOSTNAME"
    append_json "os_version" "$(cat /etc/os-release 2>/dev/null | grep '^VERSION=' | cut -d= -f2 | tr -d '\"')"
}

discover_oracle_environment() {
    log_section "ORACLE ENVIRONMENT"
    
    log_info "ORACLE_HOME: ${ORACLE_HOME:-NOT SET}"
    log_info "ORACLE_SID: ${ORACLE_SID:-NOT SET}"
    log_info "ORACLE_BASE: ${ORACLE_BASE:-NOT SET}"
    log_info "GRID_HOME: ${GRID_HOME:-NOT SET}"
    log_info "TNS_ADMIN: ${TNS_ADMIN:-NOT SET (defaults to \$ORACLE_HOME/network/admin)}"
    log_info ""
    
    if [ -n "${ORACLE_HOME:-}" ] && [ -f "$ORACLE_HOME/bin/sqlplus" ]; then
        log_info "Oracle Version:"
        $ORACLE_HOME/bin/sqlplus -v 2>/dev/null | tee -a "$OUTPUT_FILE"
        
        local ora_version
        ora_version=$(run_sql_value "SELECT banner FROM v\$version WHERE rownum = 1;")
        log_info "Database Banner: $ora_version"
        
        append_json "oracle_home" "$ORACLE_HOME"
        append_json "oracle_sid" "$ORACLE_SID"
        append_json "oracle_version" "$ora_version"
    else
        log_warning "ORACLE_HOME not found or sqlplus not available"
    fi
    
    log_info ""
    log_info "oratab Contents:"
    cat /etc/oratab 2>/dev/null | grep -v '^#' | grep -v '^$' | tee -a "$OUTPUT_FILE" || log_info "oratab not found"
}

discover_database_config() {
    log_section "DATABASE CONFIGURATION"
    
    log_info "Database Name and Identity:"
    run_sql "SELECT name, db_unique_name, dbid, open_mode, database_role, log_mode FROM v\$database;" | tee -a "$OUTPUT_FILE"
    
    local db_name=$(run_sql_value "SELECT name FROM v\$database;")
    local db_unique_name=$(run_sql_value "SELECT db_unique_name FROM v\$database;")
    local open_mode=$(run_sql_value "SELECT open_mode FROM v\$database;")
    
    append_json "database_name" "$db_name"
    append_json "database_unique_name" "$db_unique_name"
    append_json "open_mode" "$open_mode"
    
    log_info ""
    log_info "Character Set:"
    run_sql "SELECT parameter, value FROM nls_database_parameters WHERE parameter IN ('NLS_CHARACTERSET', 'NLS_NCHAR_CHARACTERSET');" | tee -a "$OUTPUT_FILE"
    
    local charset=$(run_sql_value "SELECT value FROM nls_database_parameters WHERE parameter = 'NLS_CHARACTERSET';")
    append_json "character_set" "$charset"
}

discover_storage() {
    log_section "STORAGE CONFIGURATION"
    
    log_info "Tablespace Usage:"
    run_sql "
    SELECT 
        tablespace_name,
        ROUND(SUM(bytes)/1024/1024/1024, 2) as used_gb,
        ROUND(SUM(maxbytes)/1024/1024/1024, 2) as max_gb
    FROM dba_data_files
    GROUP BY tablespace_name
    ORDER BY tablespace_name;" | tee -a "$OUTPUT_FILE"
    
    log_info ""
    log_info "ASM Disk Groups (if applicable):"
    run_sql "
    SELECT 
        name,
        state,
        type,
        ROUND(total_mb/1024, 2) as total_gb,
        ROUND(free_mb/1024, 2) as free_gb,
        ROUND((total_mb - free_mb)/total_mb * 100, 1) as pct_used
    FROM v\$asm_diskgroup;" | tee -a "$OUTPUT_FILE"
    
    log_info ""
    log_info "Disk Space (OS Level):"
    df -h 2>/dev/null | tee -a "$OUTPUT_FILE"
}

discover_cdb_pdb() {
    log_section "CONTAINER DATABASE (CDB/PDB)"
    
    local cdb_status=$(run_sql_value "SELECT cdb FROM v\$database;")
    log_info "CDB Status: $cdb_status"
    append_json "is_cdb" "$cdb_status"
    
    if [ "$cdb_status" = "YES" ]; then
        log_info ""
        log_info "Container Name:"
        run_sql "SELECT sys_context('USERENV', 'CON_NAME') as current_container FROM dual;" | tee -a "$OUTPUT_FILE"
        
        log_info ""
        log_info "PDB Status:"
        run_sql "SELECT con_id, name, open_mode, restricted FROM v\$pdbs ORDER BY con_id;" | tee -a "$OUTPUT_FILE"
        
        log_info ""
        log_info "PDB Services:"
        run_sql "SELECT pdb, name, network_name FROM cdb_services WHERE pdb IS NOT NULL ORDER BY pdb;" | tee -a "$OUTPUT_FILE"
    else
        log_info "Database is non-CDB"
    fi
}

discover_tde_config() {
    log_section "TDE/WALLET CONFIGURATION"
    
    log_info "Encryption Wallet Status:"
    run_sql "SELECT wrl_type, wrl_parameter, status, wallet_type FROM v\$encryption_wallet;" | tee -a "$OUTPUT_FILE"
    
    local wallet_status=$(run_sql_value "SELECT status FROM v\$encryption_wallet WHERE rownum = 1;")
    local wallet_type=$(run_sql_value "SELECT wallet_type FROM v\$encryption_wallet WHERE rownum = 1;")
    append_json "tde_wallet_status" "$wallet_status"
    append_json "tde_wallet_type" "$wallet_type"
    
    log_info ""
    log_info "Key Management:"
    run_sql "SELECT key_id, keystore_type, origin, creator FROM v\$encryption_keys WHERE rownum <= 5;" | tee -a "$OUTPUT_FILE"
}

discover_network_config() {
    log_section "NETWORK CONFIGURATION"
    
    log_info "Listener Status:"
    if [ -n "${ORACLE_HOME:-}" ]; then
        $ORACLE_HOME/bin/lsnrctl status 2>&1 | tee -a "$OUTPUT_FILE" || log_warning "Could not get listener status"
    fi
    
    log_info ""
    log_info "SCAN Listener (if RAC):"
    if [ -n "${GRID_HOME:-}" ]; then
        run_grid_cmd "srvctl status scan_listener" 2>&1 | tee -a "$OUTPUT_FILE" || log_info "Not a RAC configuration or SCAN not configured"
    fi
    
    log_info ""
    log_info "tnsnames.ora:"
    local tns_admin="${TNS_ADMIN:-$ORACLE_HOME/network/admin}"
    if [ -f "$tns_admin/tnsnames.ora" ]; then
        cat "$tns_admin/tnsnames.ora" 2>/dev/null | tee -a "$OUTPUT_FILE"
    else
        log_warning "tnsnames.ora not found at $tns_admin/tnsnames.ora"
    fi
    
    log_info ""
    log_info "sqlnet.ora:"
    if [ -f "$tns_admin/sqlnet.ora" ]; then
        cat "$tns_admin/sqlnet.ora" 2>/dev/null | tee -a "$OUTPUT_FILE"
    else
        log_warning "sqlnet.ora not found"
    fi
}

discover_grid_infrastructure() {
    log_section "GRID INFRASTRUCTURE / RAC"
    
    if [ -n "${GRID_HOME:-}" ]; then
        log_info "Grid Home: $GRID_HOME"
        
        log_info ""
        log_info "CRS Status:"
        run_grid_cmd "crsctl check crs" 2>&1 | tee -a "$OUTPUT_FILE"
        
        log_info ""
        log_info "Cluster Resources:"
        run_grid_cmd "crsctl stat res -t" 2>&1 | tee -a "$OUTPUT_FILE"
        
        log_info ""
        log_info "Database Services:"
        if [ -n "${ORACLE_SID:-}" ]; then
            local db_name=$(echo "$ORACLE_SID" | sed 's/[0-9]*$//')
            run_grid_cmd "srvctl status database -d $db_name" 2>&1 | tee -a "$OUTPUT_FILE"
        fi
    else
        log_info "Grid Infrastructure not detected - likely single instance"
    fi
}

discover_oci_azure_integration() {
    log_section "OCI/AZURE INTEGRATION"
    
    log_info "OCI CLI Version:"
    oci --version 2>&1 | tee -a "$OUTPUT_FILE" || log_warning "OCI CLI not installed or not in PATH"
    
    log_info ""
    log_info "OCI Config Check:"
    if [ -f ~/.oci/config ]; then
        log_info "OCI config file exists at ~/.oci/config"
        log_info "Configured profiles:"
        grep '^\[' ~/.oci/config 2>/dev/null | tee -a "$OUTPUT_FILE"
        
        log_info ""
        log_info "Configured regions:"
        grep '^region' ~/.oci/config 2>/dev/null | tee -a "$OUTPUT_FILE"
    else
        log_warning "OCI config file not found at ~/.oci/config"
    fi
    
    log_info ""
    log_info "OCI Connectivity Test:"
    timeout 10 oci iam region list --query "data[0].name" 2>&1 | head -5 | tee -a "$OUTPUT_FILE" || \
        log_warning "OCI connectivity test failed or timed out"
    
    log_info ""
    log_info "Instance Metadata (OCI):"
    curl -s -H "Authorization: Bearer Oracle" http://169.254.169.254/opc/v2/instance/ 2>/dev/null | head -20 | tee -a "$OUTPUT_FILE" || \
        log_info "OCI instance metadata not available"
    
    log_info ""
    log_info "Instance Metadata (Azure):"
    curl -s -H "Metadata: true" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" 2>/dev/null | head -20 | tee -a "$OUTPUT_FILE" || \
        log_info "Azure instance metadata not available"
}

discover_authentication() {
    log_section "AUTHENTICATION AND SSH"
    
    log_info "SSH Directory (~/.ssh):"
    ls -la ~/.ssh/ 2>/dev/null | tee -a "$OUTPUT_FILE" || log_warning "SSH directory not found or not accessible"
    
    log_info ""
    log_info "SSH Authorized Keys:"
    if [ -f ~/.ssh/authorized_keys ]; then
        wc -l ~/.ssh/authorized_keys | tee -a "$OUTPUT_FILE"
    else
        log_warning "No authorized_keys file found"
    fi
}

# =============================================================================
# ADDITIONAL CUSTOM DISCOVERY (per user requirements)
# =============================================================================

discover_exadata_storage() {
    log_section "EXADATA STORAGE CAPACITY"
    
    log_info "Checking for Exadata environment..."
    
    # Check if this is Exadata
    local is_exadata=$(run_sql_value "SELECT COUNT(*) FROM v\$cell WHERE rownum = 1;" 2>/dev/null)
    
    if [ "$is_exadata" != "" ] && [ "$is_exadata" != "0" ]; then
        log_info "Exadata environment detected"
        
        log_info ""
        log_info "Cell Storage Summary:"
        run_sql "SELECT * FROM v\$cell;" | tee -a "$OUTPUT_FILE"
        
        log_info ""
        log_info "Flash Cache Status:"
        run_sql "SELECT * FROM v\$cell_state WHERE statistics_type = 'FLASHCACHE';" | tee -a "$OUTPUT_FILE"
        
        append_json "is_exadata" "true"
    else
        log_info "Not an Exadata environment or cell information not accessible"
        append_json "is_exadata" "false"
    fi
    
    log_info ""
    log_info "ASM Disk Group Free Space:"
    run_sql "
    SELECT 
        name as diskgroup_name,
        type as redundancy,
        ROUND(total_mb/1024, 2) as total_gb,
        ROUND(free_mb/1024, 2) as free_gb,
        ROUND(usable_file_mb/1024, 2) as usable_gb
    FROM v\$asm_diskgroup
    ORDER BY name;" | tee -a "$OUTPUT_FILE"
    
    log_info ""
    log_info "Database Files by ASM Disk Group:"
    run_sql "
    SELECT 
        REGEXP_SUBSTR(name, '^\+[^/]+') as diskgroup,
        file_type,
        COUNT(*) as file_count,
        ROUND(SUM(bytes)/1024/1024/1024, 2) as total_gb
    FROM (
        SELECT name, 'DATAFILE' as file_type, bytes FROM v\$datafile
        UNION ALL
        SELECT name, 'TEMPFILE', bytes FROM v\$tempfile
        UNION ALL
        SELECT member, 'REDOLOG', bytes FROM v\$logfile lf, v\$log l WHERE lf.group# = l.group#
    )
    GROUP BY REGEXP_SUBSTR(name, '^\+[^/]+'), file_type
    ORDER BY 1, 2;" | tee -a "$OUTPUT_FILE"
}

discover_preconfigured_pdbs() {
    log_section "PRE-CONFIGURED PDBs"
    
    local cdb_status=$(run_sql_value "SELECT cdb FROM v\$database;")
    
    if [ "$cdb_status" = "YES" ]; then
        log_info "Existing PDBs with Details:"
        run_sql "
        SELECT 
            p.con_id,
            p.name as pdb_name,
            p.open_mode,
            p.restricted,
            TO_CHAR(p.creation_time, 'YYYY-MM-DD HH24:MI:SS') as created,
            ROUND(SUM(d.bytes)/1024/1024/1024, 2) as size_gb
        FROM v\$pdbs p
        LEFT JOIN cdb_data_files d ON p.con_id = d.con_id
        GROUP BY p.con_id, p.name, p.open_mode, p.restricted, p.creation_time
        ORDER BY p.con_id;" | tee -a "$OUTPUT_FILE"
        
        log_info ""
        log_info "PDB Services:"
        run_sql "
        SELECT 
            pdb,
            name as service_name,
            network_name,
            enabled
        FROM cdb_services 
        WHERE pdb IS NOT NULL AND pdb != 'CDB\$ROOT'
        ORDER BY pdb, name;" | tee -a "$OUTPUT_FILE"
        
        log_info ""
        log_info "PDB Tablespaces:"
        run_sql "
        SELECT 
            c.name as pdb_name,
            t.tablespace_name,
            t.status,
            t.contents,
            ROUND(SUM(d.bytes)/1024/1024/1024, 2) as size_gb
        FROM v\$pdbs c
        JOIN cdb_tablespaces t ON c.con_id = t.con_id
        LEFT JOIN cdb_data_files d ON t.tablespace_name = d.tablespace_name AND t.con_id = d.con_id
        WHERE c.name != 'PDB\$SEED'
        GROUP BY c.name, t.tablespace_name, t.status, t.contents
        ORDER BY c.name, t.tablespace_name;" | tee -a "$OUTPUT_FILE"
    else
        log_info "Database is non-CDB - no PDBs to discover"
    fi
}

discover_network_security() {
    log_section "NETWORK SECURITY GROUP RULES"
    
    log_info "Note: NSG rules are managed at the Azure/OCI infrastructure level"
    log_info "This section captures network-related database and OS settings"
    log_info ""
    
    log_info "Firewall Status (OS Level):"
    systemctl status firewalld 2>/dev/null | head -10 | tee -a "$OUTPUT_FILE" || \
        service iptables status 2>/dev/null | head -10 | tee -a "$OUTPUT_FILE" || \
        log_info "Firewall status not available"
    
    log_info ""
    log_info "Active Listening Ports:"
    ss -tlnp 2>/dev/null | grep -E "1521|1522|1523|5500|5501" | tee -a "$OUTPUT_FILE" || \
        netstat -tlnp 2>/dev/null | grep -E "1521|1522|1523|5500|5501" | tee -a "$OUTPUT_FILE" || \
        log_info "Port information not available"
    
    log_info ""
    log_info "Valid Node Check (if RAC):"
    if [ -n "${ORACLE_HOME:-}" ]; then
        cat "${ORACLE_HOME}/network/admin/sqlnet.ora" 2>/dev/null | grep -i "tcp.validnode" | tee -a "$OUTPUT_FILE" || \
            log_info "No TCP valid node checking configured"
    fi
    
    log_info ""
    log_info "Database Audit Settings:"
    run_sql "SELECT parameter_name, parameter_value FROM dba_audit_mgmt_config_params WHERE audit_trail = 'UNIFIED AUDIT TRAIL';" | tee -a "$OUTPUT_FILE"
    
    log_info ""
    log_info "To view full NSG rules, use Azure Portal or CLI:"
    log_info "  az network nsg rule list --nsg-name <nsg-name> --resource-group <rg-name>"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    echo "============================================================================="
    echo " ZDM Target Database Discovery (Oracle Database@Azure)"
    echo " Project: PRODDB Migration to Oracle Database@Azure"
    echo " Server: proddb-oda.eastus.azure.example.com"
    echo " Timestamp: $(date)"
    echo "============================================================================="
    
    # Initialize output files
    echo "ZDM Target Database Discovery Report" > "$OUTPUT_FILE"
    echo "Generated: $(date)" >> "$OUTPUT_FILE"
    echo "Hostname: $HOSTNAME" >> "$OUTPUT_FILE"
    echo "Project: PRODDB Migration to Oracle Database@Azure" >> "$OUTPUT_FILE"
    echo "Platform: Oracle Database@Azure" >> "$OUTPUT_FILE"
    
    init_json
    
    # Run discovery sections - continue even if some fail
    discover_os_info || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_oracle_environment || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_database_config || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_storage || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_cdb_pdb || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_tde_config || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_network_config || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_grid_infrastructure || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_oci_azure_integration || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_authentication || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    
    # Additional custom discovery per user requirements
    discover_exadata_storage || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_preconfigured_pdbs || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_network_security || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    
    # Finalize
    finalize_json
    
    echo ""
    echo "============================================================================="
    if [ $SECTION_ERRORS -gt 0 ]; then
        echo -e "${YELLOW}Discovery completed with $SECTION_ERRORS section(s) having warnings/errors${NC}"
    else
        echo -e "${GREEN}Discovery completed successfully${NC}"
    fi
    echo "Output files:"
    echo "  Text report: $OUTPUT_FILE"
    echo "  JSON summary: $JSON_FILE"
    echo "============================================================================="
    
    # Always exit 0 so orchestrator knows script completed
    exit 0
}

# Run main
main "$@"
