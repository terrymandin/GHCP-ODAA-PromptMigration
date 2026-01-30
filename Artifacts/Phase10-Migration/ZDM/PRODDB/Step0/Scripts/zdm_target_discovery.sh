#!/bin/bash
# ZDM Target Database Discovery Script (Oracle Database@Azure)
# Project: PRODDB Migration to Oracle Database@Azure
# Target: proddb-oda.eastus.azure.example.com
# Generated: 2026-01-30

# NO set -e - We want to continue even if some checks fail
SECTION_ERRORS=0

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# ENVIRONMENT DETECTION AND SETUP
# =============================================================================

# Auto-detect Oracle environment
detect_oracle_env() {
    # If already set, use existing values
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        return 0
    fi
    
    # Method 1: Parse /etc/oratab (most reliable)
    if [ -f /etc/oratab ]; then
        local oratab_entry
        if [ -n "${ORACLE_SID:-}" ]; then
            oratab_entry=$(grep "^${ORACLE_SID}:" /etc/oratab 2>/dev/null | head -1)
        else
            oratab_entry=$(grep -v '^#' /etc/oratab | grep -v '^$' | head -1)
        fi
        if [ -n "$oratab_entry" ]; then
            export ORACLE_SID="${ORACLE_SID:-$(echo "$oratab_entry" | cut -d: -f1)}"
            export ORACLE_HOME="${ORACLE_HOME:-$(echo "$oratab_entry" | cut -d: -f2)}"
        fi
    fi
    
    # Method 2: Check running pmon process
    if [ -z "${ORACLE_SID:-}" ]; then
        local pmon_sid
        pmon_sid=$(ps -ef | grep 'ora_pmon_' | grep -v grep | head -1 | sed 's/.*ora_pmon_//')
        [ -n "$pmon_sid" ] && export ORACLE_SID="$pmon_sid"
    fi
    
    # Method 3: Search common Oracle installation paths (Exadata/ODA paths)
    if [ -z "${ORACLE_HOME:-}" ]; then
        for path in /u01/app/oracle/product/*/dbhome_1 /u02/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1; do
            if [ -d "$path" ] && [ -f "$path/bin/sqlplus" ]; then
                export ORACLE_HOME="$path"
                break
            fi
        done
    fi
    
    # Method 4: Check oraenv/coraenv
    if [ -z "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        [ -f /usr/local/bin/oraenv ] && . /usr/local/bin/oraenv <<< "$ORACLE_SID" 2>/dev/null
    fi
}

# Apply explicit overrides if provided (highest priority)
[ -n "${ORACLE_HOME_OVERRIDE:-}" ] && export ORACLE_HOME="$ORACLE_HOME_OVERRIDE"
[ -n "${ORACLE_SID_OVERRIDE:-}" ] && export ORACLE_SID="$ORACLE_SID_OVERRIDE"
[ -n "${ORACLE_BASE_OVERRIDE:-}" ] && export ORACLE_BASE="$ORACLE_BASE_OVERRIDE"

# Extract export statements from profiles (bypasses interactive guards)
for profile in /etc/profile ~/.bash_profile ~/.bashrc; do
    if [ -f "$profile" ]; then
        eval "$(grep -E '^export\s+(ORACLE_HOME|ORACLE_SID|ORACLE_BASE|TNS_ADMIN|GRID_HOME|PATH)=' "$profile" 2>/dev/null)" || true
    fi
done

# Run auto-detection
detect_oracle_env

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname)
OUTPUT_FILE="./zdm_target_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_target_discovery_${HOSTNAME}_${TIMESTAMP}.json"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

log_section() {
    local title="$1"
    echo -e "\n${BLUE}=================================================================================${NC}"
    echo -e "${BLUE}  $title${NC}"
    echo -e "${BLUE}=================================================================================${NC}\n"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
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
$sql_query
EOSQL
)
        # Execute as oracle user - use sudo if current user is not oracle
        if [ "$(whoami)" = "oracle" ]; then
            echo "$sql_script" | $sqlplus_cmd
        else
            echo "$sql_script" | sudo -u oracle -E ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd
        fi
    else
        echo "ERROR: ORACLE_HOME or ORACLE_SID not set"
        return 1
    fi
}

# Get single SQL value
run_sql_value() {
    local sql_query="$1"
    run_sql "$sql_query" | grep -v '^$' | tail -1 | xargs
}

# Write to both terminal and output file
write_output() {
    echo "$1" | tee -a "$OUTPUT_FILE"
}

# =============================================================================
# DISCOVERY SECTIONS
# =============================================================================

discover_os_info() {
    log_section "OS INFORMATION"
    {
        echo "=== OS INFORMATION ==="
        echo "Hostname: $(hostname)"
        echo "IP Addresses:"
        ip addr show 2>/dev/null | grep 'inet ' | awk '{print "  " $2}' || hostname -I 2>/dev/null | tr ' ' '\n' | sed 's/^/  /'
        echo ""
        echo "Operating System:"
        cat /etc/os-release 2>/dev/null || cat /etc/oracle-release 2>/dev/null || uname -a
        echo ""
        echo "Kernel Version: $(uname -r)"
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "OS information collected"
}

discover_oracle_env() {
    log_section "ORACLE ENVIRONMENT"
    {
        echo "=== ORACLE ENVIRONMENT ==="
        echo "ORACLE_HOME: ${ORACLE_HOME:-NOT SET}"
        echo "ORACLE_SID: ${ORACLE_SID:-NOT SET}"
        echo "ORACLE_BASE: ${ORACLE_BASE:-NOT SET}"
        echo "GRID_HOME: ${GRID_HOME:-NOT SET}"
        echo "TNS_ADMIN: ${TNS_ADMIN:-NOT SET}"
        echo ""
        if [ -n "${ORACLE_HOME:-}" ]; then
            echo "Oracle Version:"
            $ORACLE_HOME/bin/sqlplus -v 2>/dev/null || echo "Unable to determine Oracle version"
        fi
        echo ""
        echo "/etc/oratab contents:"
        cat /etc/oratab 2>/dev/null | grep -v '^#' | grep -v '^$' || echo "No oratab found"
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "Oracle environment collected"
}

discover_db_config() {
    log_section "DATABASE CONFIGURATION"
    {
        echo "=== DATABASE CONFIGURATION ==="
        echo ""
        echo "Database Identity:"
        run_sql "SELECT name, db_unique_name, dbid, created FROM v\$database;"
        echo ""
        echo "Database Role and Mode:"
        run_sql "SELECT database_role, open_mode, log_mode, force_logging FROM v\$database;"
        echo ""
        echo "Instance Status:"
        run_sql "SELECT instance_name, host_name, version, status, startup_time FROM v\$instance;"
        echo ""
        echo "Character Set:"
        run_sql "SELECT parameter, value FROM nls_database_parameters WHERE parameter IN ('NLS_CHARACTERSET', 'NLS_NCHAR_CHARACTERSET');"
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "Database configuration collected"
}

discover_storage() {
    log_section "STORAGE CONFIGURATION"
    {
        echo "=== STORAGE CONFIGURATION ==="
        echo ""
        echo "Tablespaces and Available Space:"
        run_sql "SELECT tablespace_name, status, contents, ROUND(SUM(bytes)/1024/1024/1024, 2) as \"Size (GB)\", ROUND(SUM(maxbytes)/1024/1024/1024, 2) as \"Max Size (GB)\" FROM dba_data_files GROUP BY tablespace_name, status, contents ORDER BY tablespace_name;"
        echo ""
        echo "ASM Disk Groups (if applicable):"
        run_sql "SELECT name, state, type, total_mb, free_mb, ROUND((free_mb/total_mb)*100, 2) as \"Free %\" FROM v\$asm_diskgroup;" 2>/dev/null || echo "ASM not configured or not accessible"
        echo ""
        echo "Disk Space:"
        df -h 2>/dev/null | head -20
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "Storage configuration collected"
}

discover_cdb_pdb() {
    log_section "CONTAINER DATABASE / PDB"
    {
        echo "=== CONTAINER DATABASE / PDB ==="
        echo ""
        echo "CDB Status:"
        run_sql "SELECT cdb FROM v\$database;"
        echo ""
        echo "PDB Information:"
        run_sql "SELECT con_id, name, open_mode, restricted, creation_time FROM v\$pdbs ORDER BY con_id;" 2>/dev/null || echo "Not a CDB or no PDBs found"
        echo ""
        echo "PDB Storage:"
        run_sql "SELECT p.name as pdb_name, ROUND(SUM(d.bytes)/1024/1024/1024, 2) as \"Size (GB)\" FROM v\$pdbs p, cdb_data_files d WHERE p.con_id = d.con_id GROUP BY p.name ORDER BY p.name;" 2>/dev/null || echo "Not a CDB"
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "CDB/PDB information collected"
}

discover_tde() {
    log_section "TDE CONFIGURATION"
    {
        echo "=== TDE CONFIGURATION ==="
        echo ""
        echo "Encryption Wallet Status:"
        run_sql "SELECT wrl_type, wrl_parameter, status, wallet_type FROM v\$encryption_wallet;"
        echo ""
        echo "Encrypted Tablespaces:"
        run_sql "SELECT tablespace_name, encrypted FROM dba_tablespaces WHERE encrypted = 'YES';" 2>/dev/null || echo "No encrypted tablespaces found"
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "TDE configuration collected"
}

discover_network() {
    log_section "NETWORK CONFIGURATION"
    {
        echo "=== NETWORK CONFIGURATION ==="
        echo ""
        echo "Listener Status:"
        if [ -n "${ORACLE_HOME:-}" ]; then
            $ORACLE_HOME/bin/lsnrctl status 2>/dev/null || echo "Unable to get listener status"
        fi
        echo ""
        echo "SCAN Listener (if RAC):"
        if [ -n "${GRID_HOME:-}" ]; then
            $GRID_HOME/bin/srvctl status scan_listener 2>/dev/null || echo "SCAN listener not found or not RAC"
        elif command -v srvctl >/dev/null 2>&1; then
            srvctl status scan_listener 2>/dev/null || echo "SCAN listener not found or not RAC"
        else
            echo "srvctl not available"
        fi
        echo ""
        echo "tnsnames.ora contents:"
        if [ -n "${TNS_ADMIN:-}" ] && [ -f "${TNS_ADMIN}/tnsnames.ora" ]; then
            cat "${TNS_ADMIN}/tnsnames.ora"
        elif [ -n "${ORACLE_HOME:-}" ] && [ -f "${ORACLE_HOME}/network/admin/tnsnames.ora" ]; then
            cat "${ORACLE_HOME}/network/admin/tnsnames.ora"
        else
            echo "tnsnames.ora not found"
        fi
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "Network configuration collected"
}

discover_oci_azure() {
    log_section "OCI/AZURE INTEGRATION"
    {
        echo "=== OCI/AZURE INTEGRATION ==="
        echo ""
        echo "OCI CLI Version:"
        oci --version 2>/dev/null || echo "OCI CLI not installed"
        echo ""
        echo "OCI Configuration:"
        if [ -f ~/.oci/config ]; then
            echo "OCI config file found at ~/.oci/config"
            echo "Configured profiles:"
            grep '^\[' ~/.oci/config 2>/dev/null || echo "No profiles found"
        else
            echo "OCI config file not found"
        fi
        echo ""
        echo "OCI Connectivity Test:"
        oci iam region list --output table 2>/dev/null | head -10 || echo "OCI connectivity test failed or OCI CLI not configured"
        echo ""
        echo "Azure Instance Metadata:"
        curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "Azure metadata not available"
        echo ""
        echo "OCI Instance Metadata:"
        curl -s -H "Authorization: Bearer Oracle" "http://169.254.169.254/opc/v2/instance/" 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "OCI metadata not available"
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "OCI/Azure integration collected"
}

discover_grid_infrastructure() {
    log_section "GRID INFRASTRUCTURE (RAC)"
    {
        echo "=== GRID INFRASTRUCTURE (RAC) ==="
        echo ""
        echo "CRS Status:"
        if [ -n "${GRID_HOME:-}" ]; then
            $GRID_HOME/bin/crsctl stat res -t 2>/dev/null || echo "CRS not running or not RAC"
        elif command -v crsctl >/dev/null 2>&1; then
            crsctl stat res -t 2>/dev/null || echo "CRS not running or not RAC"
        else
            echo "Grid Infrastructure not detected"
        fi
        echo ""
        echo "Cluster Nodes:"
        if [ -n "${GRID_HOME:-}" ]; then
            $GRID_HOME/bin/olsnodes -n 2>/dev/null || echo "Not a RAC cluster"
        elif command -v olsnodes >/dev/null 2>&1; then
            olsnodes -n 2>/dev/null || echo "Not a RAC cluster"
        else
            echo "olsnodes not available"
        fi
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "Grid Infrastructure information collected"
}

discover_auth() {
    log_section "AUTHENTICATION"
    {
        echo "=== AUTHENTICATION ==="
        echo ""
        echo "SSH Directory Contents:"
        ls -la ~/.ssh/ 2>/dev/null || echo "No .ssh directory found"
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "Authentication configuration collected"
}

# =============================================================================
# ADDITIONAL DISCOVERY REQUIREMENTS FOR PRODDB TARGET
# =============================================================================

discover_exadata_storage() {
    log_section "EXADATA STORAGE CAPACITY"
    {
        echo "=== EXADATA STORAGE CAPACITY ==="
        echo ""
        echo "Cell Disk Information:"
        run_sql "SELECT cell_name, disk_name, status, size_mb, free_mb FROM v\$cell_disk ORDER BY cell_name, disk_name;" 2>/dev/null || echo "Not an Exadata system or cell metrics not available"
        echo ""
        echo "ASM Disk Groups with Exadata Details:"
        run_sql "SELECT name, state, type, total_mb/1024 as \"Total (GB)\", free_mb/1024 as \"Free (GB)\", ROUND(usable_file_mb/1024, 2) as \"Usable (GB)\" FROM v\$asm_diskgroup ORDER BY name;" 2>/dev/null || echo "ASM not configured"
        echo ""
        echo "Flash Cache Statistics:"
        run_sql "SELECT * FROM v\$cell_state WHERE statistics_type = 'FLASHCACHE';" 2>/dev/null || echo "Flash cache stats not available"
        echo ""
        echo "Disk Space Summary:"
        df -h 2>/dev/null
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "Exadata storage capacity collected"
}

discover_preconfigured_pdbs() {
    log_section "PRE-CONFIGURED PDBs"
    {
        echo "=== PRE-CONFIGURED PDBs ==="
        echo ""
        echo "All PDBs with Details:"
        run_sql "SELECT con_id, name, open_mode, restricted, recovery_status, snapshot_parent_con_id, application_root, application_pdb, application_seed, application_root_con_id, proxy_pdb FROM v\$pdbs ORDER BY con_id;" 2>/dev/null || echo "Not a CDB or PDBs not accessible"
        echo ""
        echo "PDB Services:"
        run_sql "SELECT p.name as pdb_name, s.name as service_name, s.network_name FROM v\$pdbs p, cdb_services s WHERE p.con_id = s.con_id AND s.con_id > 2 ORDER BY p.name;" 2>/dev/null || echo "No PDB services found"
        echo ""
        echo "PDB Storage Limits:"
        run_sql "SELECT pdb_name, max_size, max_shared_temp_size FROM cdb_pdbs WHERE max_size > 0 OR max_shared_temp_size > 0;" 2>/dev/null || echo "No storage limits configured"
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "Pre-configured PDBs collected"
}

discover_network_security() {
    log_section "NETWORK SECURITY GROUP RULES"
    {
        echo "=== NETWORK SECURITY GROUP RULES ==="
        echo ""
        echo "Note: NSG rules are typically managed at Azure/OCI level, not within the OS."
        echo ""
        echo "Firewall Status (if iptables/firewalld):"
        systemctl status firewalld 2>/dev/null | head -10 || echo "firewalld not running"
        echo ""
        echo "IPTables Rules:"
        iptables -L -n 2>/dev/null | head -30 || echo "iptables not accessible"
        echo ""
        echo "Listening Ports:"
        ss -tlnp 2>/dev/null | grep -E ':(1521|1522|5500|3872)' || netstat -tlnp 2>/dev/null | grep -E ':(1521|1522|5500|3872)' || echo "No Oracle-related ports found listening"
        echo ""
        echo "Network Connections to Oracle Ports:"
        ss -an 2>/dev/null | grep -E ':(1521|1522)' | head -20 || echo "No active connections found"
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "Network security information collected"
}

# =============================================================================
# JSON OUTPUT GENERATION
# =============================================================================

generate_json_summary() {
    log_section "GENERATING JSON SUMMARY"
    
    # Collect key values for JSON
    local db_name=$(run_sql_value "SELECT name FROM v\$database;")
    local db_unique_name=$(run_sql_value "SELECT db_unique_name FROM v\$database;")
    local dbid=$(run_sql_value "SELECT dbid FROM v\$database;")
    local db_role=$(run_sql_value "SELECT database_role FROM v\$database;")
    local open_mode=$(run_sql_value "SELECT open_mode FROM v\$database;")
    local is_cdb=$(run_sql_value "SELECT cdb FROM v\$database;")
    local oracle_version=$(run_sql_value "SELECT version FROM v\$instance;")
    local charset=$(run_sql_value "SELECT value FROM nls_database_parameters WHERE parameter = 'NLS_CHARACTERSET';")
    local wallet_status=$(run_sql_value "SELECT status FROM v\$encryption_wallet WHERE rownum = 1;")
    local pdb_count=$(run_sql_value "SELECT COUNT(*) FROM v\$pdbs WHERE con_id > 2;")
    
    cat > "$JSON_FILE" <<EOF
{
  "discovery_type": "target",
  "discovery_timestamp": "$(date -Iseconds)",
  "hostname": "$HOSTNAME",
  "project": "PRODDB Migration to Oracle Database@Azure",
  "target_type": "Oracle Database@Azure",
  "oracle_environment": {
    "oracle_home": "${ORACLE_HOME:-unknown}",
    "oracle_sid": "${ORACLE_SID:-unknown}",
    "oracle_base": "${ORACLE_BASE:-unknown}",
    "grid_home": "${GRID_HOME:-unknown}",
    "oracle_version": "${oracle_version:-unknown}"
  },
  "database_config": {
    "db_name": "${db_name:-unknown}",
    "db_unique_name": "${db_unique_name:-unknown}",
    "dbid": "${dbid:-unknown}",
    "database_role": "${db_role:-unknown}",
    "open_mode": "${open_mode:-unknown}",
    "is_cdb": "${is_cdb:-unknown}",
    "pdb_count": "${pdb_count:-0}",
    "character_set": "${charset:-unknown}"
  },
  "tde_config": {
    "wallet_status": "${wallet_status:-unknown}"
  },
  "section_errors": $SECTION_ERRORS,
  "output_files": {
    "text_report": "$OUTPUT_FILE",
    "json_summary": "$JSON_FILE"
  }
}
EOF
    log_success "JSON summary generated: $JSON_FILE"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    echo -e "${GREEN}=============================================================================${NC}"
    echo -e "${GREEN}  ZDM Target Database Discovery Script (Oracle Database@Azure)${NC}"
    echo -e "${GREEN}  Project: PRODDB Migration to Oracle Database@Azure${NC}"
    echo -e "${GREEN}  Host: $HOSTNAME${NC}"
    echo -e "${GREEN}  Timestamp: $(date)${NC}"
    echo -e "${GREEN}=============================================================================${NC}"
    
    # Initialize output file
    echo "ZDM Target Database Discovery Report (Oracle Database@Azure)" > "$OUTPUT_FILE"
    echo "==============================================================" >> "$OUTPUT_FILE"
    echo "Project: PRODDB Migration to Oracle Database@Azure" >> "$OUTPUT_FILE"
    echo "Host: $HOSTNAME" >> "$OUTPUT_FILE"
    echo "Generated: $(date)" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    # Run all discovery sections (continue on failure)
    discover_os_info || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_oracle_env || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_db_config || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_storage || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_cdb_pdb || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_tde || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_network || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_oci_azure || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_grid_infrastructure || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_auth || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    
    # Additional PRODDB target-specific discovery
    discover_exadata_storage || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_preconfigured_pdbs || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_network_security || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    
    # Generate JSON summary
    generate_json_summary
    
    echo ""
    echo -e "${GREEN}=============================================================================${NC}"
    echo -e "${GREEN}  Discovery Complete${NC}"
    echo -e "${GREEN}=============================================================================${NC}"
    echo -e "Text Report: ${BLUE}$OUTPUT_FILE${NC}"
    echo -e "JSON Summary: ${BLUE}$JSON_FILE${NC}"
    if [ $SECTION_ERRORS -gt 0 ]; then
        echo -e "${YELLOW}Warning: $SECTION_ERRORS section(s) encountered errors${NC}"
    fi
}

# Show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "ZDM Target Database Discovery Script (Oracle Database@Azure)"
    echo "Project: PRODDB Migration to Oracle Database@Azure"
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help message"
    echo ""
    echo "Environment Variables (optional overrides):"
    echo "  ORACLE_HOME_OVERRIDE    Override auto-detected ORACLE_HOME"
    echo "  ORACLE_SID_OVERRIDE     Override auto-detected ORACLE_SID"
    echo "  ORACLE_BASE_OVERRIDE    Override auto-detected ORACLE_BASE"
    echo ""
    echo "Output:"
    echo "  ./zdm_target_discovery_<hostname>_<timestamp>.txt"
    echo "  ./zdm_target_discovery_<hostname>_<timestamp>.json"
}

# Parse command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    *)
        main
        ;;
esac
