#!/bin/bash
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration
# ===================================================================================
# zdm_target_discovery.sh
# ZDM Migration - Target Database Discovery (Oracle Database@Azure)
# Project: ORADB
# ===================================================================================
# Purpose: Gather technical context from the target Oracle Database@Azure server.
#          ALL operations are strictly read-only.
#
# Usage:
#   chmod +x zdm_target_discovery.sh
#   ./zdm_target_discovery.sh
#
# Environment Variable Overrides (optional):
#   ORACLE_HOME          - Override auto-detected ORACLE_HOME
#   ORACLE_SID           - Override auto-detected ORACLE_SID
#   ORACLE_USER          - Oracle software owner (default: oracle)
#   OCI_CONFIG_PATH      - Path to OCI config file (default: ~/.oci/config)
# ===================================================================================

set -o pipefail

# --------------------------------------------------------------------------
# Color codes
# --------------------------------------------------------------------------
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --------------------------------------------------------------------------
# Global state
# --------------------------------------------------------------------------
HOSTNAME_SHORT=$(hostname -s 2>/dev/null || hostname)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="./zdm_target_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_target_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

ORACLE_USER="${ORACLE_USER:-oracle}"
OCI_CONFIG_PATH="${OCI_CONFIG_PATH:-~/.oci/config}"
declare -A JSON_DATA

# --------------------------------------------------------------------------
# Logging helpers
# --------------------------------------------------------------------------
log_info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_section() { echo -e "\n${BOLD}${CYAN}=== $* ===${NC}"; }

log_raw() {
    echo "$*" >> "$REPORT_FILE"
}

report_section() {
    log_raw ""
    log_raw "=================================================================="
    log_raw "  $*"
    log_raw "=================================================================="
}

report_kv() {
    local key="$1"
    local val="$2"
    printf "  %-45s %s\n" "$key:" "$val" >> "$REPORT_FILE"
}

# --------------------------------------------------------------------------
# Auto-detect Oracle environment
# --------------------------------------------------------------------------
detect_oracle_env() {
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        log_info "Using pre-set ORACLE_HOME=$ORACLE_HOME ORACLE_SID=$ORACLE_SID"
        return 0
    fi

    log_info "Auto-detecting Oracle environment..."

    # Method 1: Parse /etc/oratab
    if [ -f /etc/oratab ]; then
        local oratab_entry
        if [ -n "${ORACLE_SID:-}" ]; then
            oratab_entry=$(grep "^${ORACLE_SID}:" /etc/oratab 2>/dev/null | head -1)
        else
            oratab_entry=$(grep -v '^#' /etc/oratab 2>/dev/null | grep -v '^$' | head -1)
        fi
        if [ -n "$oratab_entry" ]; then
            export ORACLE_SID="${ORACLE_SID:-$(echo "$oratab_entry" | cut -d: -f1)}"
            export ORACLE_HOME="${ORACLE_HOME:-$(echo "$oratab_entry" | cut -d: -f2)}"
            log_info "Detected from /etc/oratab: ORACLE_SID=$ORACLE_SID ORACLE_HOME=$ORACLE_HOME"
        fi
    fi

    # Method 2: Check running pmon process
    if [ -z "${ORACLE_SID:-}" ]; then
        local pmon_sid
        pmon_sid=$(ps -ef 2>/dev/null | grep 'ora_pmon_' | grep -v grep | head -1 | sed 's/.*ora_pmon_//')
        [ -n "$pmon_sid" ] && export ORACLE_SID="$pmon_sid" && log_info "Detected ORACLE_SID=$ORACLE_SID from pmon"
    fi

    # Method 3: Search common Oracle paths (Exadata / ExaDB-D paths)
    if [ -z "${ORACLE_HOME:-}" ]; then
        for path in /u01/app/oracle/product/*/dbhome_1 \
                    /u02/app/oracle/product/*/dbhome_1 \
                    /opt/oracle/product/*/dbhome_1 \
                    /oracle/product/*/dbhome_1; do
            if [ -d "$path" ] && [ -f "$path/bin/sqlplus" ]; then
                export ORACLE_HOME="$path"
                log_info "Detected ORACLE_HOME=$ORACLE_HOME from common paths"
                break
            fi
        done
    fi

    # Apply explicit overrides if provided
    [ -n "${ORACLE_HOME_OVERRIDE:-}" ] && export ORACLE_HOME="$ORACLE_HOME_OVERRIDE"
    [ -n "${ORACLE_SID_OVERRIDE:-}" ]  && export ORACLE_SID="$ORACLE_SID_OVERRIDE"
}

# --------------------------------------------------------------------------
# SQL execution helper
# --------------------------------------------------------------------------
run_sql() {
    local sql_query="$1"
    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        echo "ERROR: ORACLE_HOME or ORACLE_SID not set"
        return 1
    fi
    local sqlplus_cmd="$ORACLE_HOME/bin/sqlplus -s / as sysdba"
    local sql_script
    sql_script=$(cat <<EOSQL
SET PAGESIZE 1000
SET LINESIZE 200
SET FEEDBACK OFF
SET HEADING ON
SET ECHO OFF
SET TRIMSPOOL ON
$sql_query
EOSQL
)
    if [ "$(whoami)" = "$ORACLE_USER" ]; then
        echo "$sql_script" | $sqlplus_cmd 2>/dev/null
    else
        echo "$sql_script" | sudo -u "$ORACLE_USER" -E ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd 2>/dev/null
    fi
}

run_sql_value() {
    local sql_query="$1"
    run_sql "SET HEADING OFF
$sql_query" 2>/dev/null | grep -v '^$' | head -1 | xargs
}

# --------------------------------------------------------------------------
# Section: OS Information
# --------------------------------------------------------------------------
discover_os_info() {
    log_section "OS Information"
    report_section "OS INFORMATION"

    local os_hostname os_short os_ip os_version os_kernel os_arch
    os_hostname=$(hostname -f 2>/dev/null || hostname)
    os_short=$(hostname -s 2>/dev/null || hostname)
    os_ip=$(hostname -I 2>/dev/null | tr ' ' ',')
    os_version=$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"' || uname -r)
    os_kernel=$(uname -r 2>/dev/null)
    os_arch=$(uname -m 2>/dev/null)

    report_kv "Hostname (FQDN)" "$os_hostname"
    report_kv "Hostname (short)" "$os_short"
    report_kv "IP Addresses" "$os_ip"
    report_kv "OS Version" "$os_version"
    report_kv "Kernel" "$os_kernel"
    report_kv "Architecture" "$os_arch"

    log_raw ""
    log_raw "  Disk Space:"
    df -h 2>/dev/null | grep -v tmpfs | awk '{printf "    %s\n", $0}' >> "$REPORT_FILE"

    JSON_DATA["hostname"]="$os_hostname"
    JSON_DATA["ip_addresses"]="$os_ip"
    JSON_DATA["os_version"]="$os_version"
    JSON_DATA["os_kernel"]="$os_kernel"

    log_info "OS info: $os_hostname / $os_version"
}

# --------------------------------------------------------------------------
# Section: Oracle Environment
# --------------------------------------------------------------------------
discover_oracle_env() {
    log_section "Oracle Environment"
    report_section "ORACLE ENVIRONMENT"

    detect_oracle_env

    if [ -z "${ORACLE_HOME:-}" ]; then
        log_warn "ORACLE_HOME could not be detected"
        report_kv "ORACLE_HOME" "NOT DETECTED"
        JSON_DATA["oracle_home"]="NOT DETECTED"
        return
    fi

    local ora_version
    ora_version=$(run_sql_value "SELECT version FROM v\$instance;" 2>/dev/null)

    report_kv "ORACLE_HOME" "$ORACLE_HOME"
    report_kv "ORACLE_SID" "${ORACLE_SID:-N/A}"
    report_kv "ORACLE_BASE" "${ORACLE_BASE:-N/A}"
    report_kv "Oracle Version" "${ora_version:-N/A}"

    JSON_DATA["oracle_home"]="$ORACLE_HOME"
    JSON_DATA["oracle_sid"]="${ORACLE_SID:-}"
    JSON_DATA["oracle_version"]="${ora_version:-}"
}

# --------------------------------------------------------------------------
# Section: Database Configuration
# --------------------------------------------------------------------------
discover_db_config() {
    log_section "Database Configuration"
    report_section "DATABASE CONFIGURATION"

    local db_name db_unique db_role open_mode charset
    db_name=$(run_sql_value   "SELECT name FROM v\$database;")
    db_unique=$(run_sql_value "SELECT db_unique_name FROM v\$database;")
    db_role=$(run_sql_value   "SELECT database_role FROM v\$database;")
    open_mode=$(run_sql_value "SELECT open_mode FROM v\$database;")
    charset=$(run_sql_value   "SELECT value FROM nls_database_parameters WHERE parameter='NLS_CHARACTERSET';")

    report_kv "Database Name" "$db_name"
    report_kv "DB Unique Name" "$db_unique"
    report_kv "Database Role" "$db_role"
    report_kv "Open Mode" "$open_mode"
    report_kv "Character Set" "$charset"

    log_raw ""
    log_raw "  Available Storage - Tablespaces:"
    run_sql "SELECT t.tablespace_name, t.status,
                    ROUND(NVL(a.bytes,0)/1024/1024/1024,2) AS total_gb,
                    ROUND(NVL(f.bytes,0)/1024/1024/1024,2) AS free_gb
             FROM dba_tablespaces t
             LEFT JOIN (SELECT tablespace_name, SUM(bytes) AS bytes FROM dba_data_files GROUP BY tablespace_name) a
                    ON t.tablespace_name=a.tablespace_name
             LEFT JOIN (SELECT tablespace_name, SUM(bytes) AS bytes FROM dba_free_space GROUP BY tablespace_name) f
                    ON t.tablespace_name=f.tablespace_name
             WHERE t.contents <> 'TEMPORARY'
             ORDER BY t.tablespace_name;" >> "$REPORT_FILE" 2>/dev/null

    JSON_DATA["db_name"]="$db_name"
    JSON_DATA["db_unique_name"]="$db_unique"
    JSON_DATA["db_role"]="$db_role"
    JSON_DATA["charset"]="$charset"
}

# --------------------------------------------------------------------------
# Section: Container Database (CDB/PDB)
# --------------------------------------------------------------------------
discover_cdb_pdb() {
    log_section "Container Database (CDB/PDB)"
    report_section "CONTAINER DATABASE"

    local is_cdb
    is_cdb=$(run_sql_value "SELECT cdb FROM v\$database;")

    report_kv "CDB" "${is_cdb:-N/A}"
    JSON_DATA["is_cdb"]="${is_cdb:-}"

    if [ "${is_cdb^^}" = "YES" ]; then
        log_raw ""
        log_raw "  Existing PDBs (full list):"
        run_sql "SELECT con_id, name, open_mode, restricted,
                        dbid, creation_scn,
                        TO_CHAR(creation_time,'YYYY-MM-DD HH24:MI:SS') AS created
                 FROM v\$pdbs ORDER BY con_id;" >> "$REPORT_FILE" 2>/dev/null

        log_raw ""
        log_raw "  PDB Storage Limits:"
        run_sql "SELECT pdb_name,
                        ROUND(max_size/1024/1024/1024,2) AS max_size_gb
                 FROM cdb_pdbs WHERE max_size > 0 ORDER BY pdb_name;" >> "$REPORT_FILE" 2>/dev/null
    fi
}

# --------------------------------------------------------------------------
# Section: TDE Configuration
# --------------------------------------------------------------------------
discover_tde() {
    log_section "TDE Configuration"
    report_section "TDE CONFIGURATION"

    local wallet_status wallet_type wallet_location
    wallet_status=$(run_sql_value   "SELECT status FROM v\$encryption_wallet;" 2>/dev/null || echo "N/A")
    wallet_type=$(run_sql_value     "SELECT wallet_type FROM v\$encryption_wallet;" 2>/dev/null || echo "N/A")
    wallet_location=$(run_sql_value "SELECT wrl_parameter FROM v\$encryption_wallet WHERE rownum=1;" 2>/dev/null || echo "N/A")

    report_kv "Wallet Status" "$wallet_status"
    report_kv "Wallet Type" "$wallet_type"
    report_kv "Wallet Location" "$wallet_location"

    JSON_DATA["tde_wallet_status"]="$wallet_status"
    JSON_DATA["tde_wallet_type"]="$wallet_type"
}

# --------------------------------------------------------------------------
# Section: Network Configuration
# --------------------------------------------------------------------------
discover_network() {
    log_section "Network Configuration"
    report_section "NETWORK CONFIGURATION"

    log_raw "  IP Addresses:"
    ip addr 2>/dev/null | grep 'inet ' | awk '{printf "    %s\n", $0}' >> "$REPORT_FILE"

    log_raw ""
    log_raw "  Listener Status:"
    if [ -n "${ORACLE_HOME:-}" ]; then
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            "$ORACLE_HOME/bin/lsnrctl" status 2>/dev/null >> "$REPORT_FILE"
        else
            sudo -u "$ORACLE_USER" -E ORACLE_HOME="$ORACLE_HOME" TNS_ADMIN="${TNS_ADMIN:-$ORACLE_HOME/network/admin}" \
                "$ORACLE_HOME/bin/lsnrctl" status 2>/dev/null >> "$REPORT_FILE"
        fi
    fi

    # SCAN listeners (if RAC)
    log_raw ""
    log_raw "  SCAN Listener (if Grid/RAC):"
    if command -v srvctl >/dev/null 2>&1; then
        srvctl status scan_listener 2>/dev/null | awk '{printf "    %s\n", $0}' >> "$REPORT_FILE" || \
            log_raw "    srvctl not available or failed"
    elif [ -n "${GRID_HOME:-}" ] && [ -f "${GRID_HOME}/bin/srvctl" ]; then
        "${GRID_HOME}/bin/srvctl" status scan_listener 2>/dev/null | awk '{printf "    %s\n", $0}' >> "$REPORT_FILE"
    else
        log_raw "    srvctl not found in PATH (may need GRID_HOME)"
    fi

    # tnsnames
    local tns_admin="${TNS_ADMIN:-$ORACLE_HOME/network/admin}"
    log_raw ""
    log_raw "  tnsnames.ora ($tns_admin):"
    if [ -f "$tns_admin/tnsnames.ora" ]; then
        cat "$tns_admin/tnsnames.ora" 2>/dev/null | awk '{printf "    %s\n", $0}' >> "$REPORT_FILE"
    else
        log_raw "    tnsnames.ora not found at $tns_admin/tnsnames.ora"
    fi

    JSON_DATA["tns_admin"]="$tns_admin"
}

# --------------------------------------------------------------------------
# Section: OCI/Azure Integration
# --------------------------------------------------------------------------
discover_oci_azure() {
    log_section "OCI/Azure Integration"
    report_section "OCI/AZURE INTEGRATION"

    # OCI CLI
    local oci_version
    oci_version=$(oci --version 2>/dev/null || echo "NOT INSTALLED")
    report_kv "OCI CLI Version" "$oci_version"
    JSON_DATA["oci_cli_version"]="$oci_version"

    # OCI config
    local oci_config
    oci_config=$(eval echo "$OCI_CONFIG_PATH")
    if [ -f "$oci_config" ]; then
        log_raw ""
        log_raw "  OCI Config ($oci_config):"
        grep -v 'key_file\|private_key\|pass_phrase' "$oci_config" 2>/dev/null | \
            awk '{printf "    %s\n", $0}' >> "$REPORT_FILE"
    else
        report_kv "OCI Config" "NOT FOUND at $oci_config"
    fi

    # OCI connectivity test
    log_raw ""
    log_raw "  OCI Connectivity Test:"
    if oci iam region list --output table 2>/dev/null | head -5 >> "$REPORT_FILE"; then
        log_info "OCI connectivity: OK"
        JSON_DATA["oci_connectivity"]="OK"
    else
        log_warn "OCI connectivity test failed"
        JSON_DATA["oci_connectivity"]="FAILED"
    fi

    # Azure Instance Metadata
    log_raw ""
    log_raw "  Azure Instance Metadata:"
    if curl -s -m 5 -H "Metadata:true" \
        "http://169.254.169.254/metadata/instance?api-version=2021-02-01" 2>/dev/null | \
        python3 -m json.tool 2>/dev/null | head -30 >> "$REPORT_FILE"; then
        log_info "Azure metadata: accessible"
    else
        log_raw "    Azure metadata service not accessible (expected on non-Azure VMs)"
    fi

    # OCI Instance Metadata
    log_raw ""
    log_raw "  OCI Instance Metadata:"
    if curl -s -m 5 "http://169.254.169.254/opc/v1/instance/" 2>/dev/null | \
        python3 -m json.tool 2>/dev/null | head -30 >> "$REPORT_FILE"; then
        log_info "OCI metadata: accessible"
    else
        log_raw "    OCI metadata service not accessible"
    fi
}

# --------------------------------------------------------------------------
# Section: Grid Infrastructure / RAC
# --------------------------------------------------------------------------
discover_grid_infra() {
    log_section "Grid Infrastructure"
    report_section "GRID INFRASTRUCTURE"

    # Check for CRS
    local crs_found="false"
    if command -v crsctl >/dev/null 2>&1; then
        crs_found="true"
    elif [ -n "${GRID_HOME:-}" ] && [ -f "${GRID_HOME}/bin/crsctl" ]; then
        crs_found="true"
        export PATH="${GRID_HOME}/bin:$PATH"
    fi

    if [ "$crs_found" = "true" ]; then
        log_raw "  CRS Status:"
        crsctl check crs 2>/dev/null | awk '{printf "    %s\n", $0}' >> "$REPORT_FILE"
        log_raw ""
        log_raw "  Cluster Resources:"
        crsctl stat res -t 2>/dev/null | head -60 >> "$REPORT_FILE"
    else
        log_raw "  crsctl not found - this may be a single-instance database"
        report_kv "Grid Infrastructure" "Not detected (single-instance or CRS not in PATH)"
    fi

    JSON_DATA["grid_found"]="$crs_found"
}

# --------------------------------------------------------------------------
# Section: Authentication
# --------------------------------------------------------------------------
discover_auth() {
    log_section "Authentication"
    report_section "AUTHENTICATION"

    local pwfile
    pwfile=$(find "${ORACLE_HOME:-/u01}/dbs" -name "orapw*" 2>/dev/null | head -1)
    report_kv "Password File" "${pwfile:-NOT FOUND}"

    log_raw ""
    log_raw "  Oracle user SSH directory:"
    if [ "$(whoami)" = "$ORACLE_USER" ]; then
        ls -la ~/.ssh 2>/dev/null | awk '{printf "    %s\n", $0}' >> "$REPORT_FILE" || \
            log_raw "    ~/.ssh not found"
    else
        sudo -u "$ORACLE_USER" bash -c 'ls -la ~/.ssh 2>/dev/null' | \
            awk '{printf "    %s\n", $0}' >> "$REPORT_FILE" || \
            log_raw "    SSH directory not accessible via sudo"
    fi
}

# --------------------------------------------------------------------------
# Section: Exadata / ASM Storage
# --------------------------------------------------------------------------
discover_exadata_storage() {
    log_section "Exadata / ASM Storage"
    report_section "EXADATA / ASM STORAGE"

    # ASM disk groups
    log_raw "  ASM Disk Groups:"
    run_sql "SELECT group_number, name, type, state, total_mb, free_mb,
                    ROUND((total_mb-free_mb)*100/NULLIF(total_mb,0),1) AS pct_used
             FROM v\$asm_diskgroup ORDER BY name;" >> "$REPORT_FILE" 2>/dev/null || {
        # Try asmcmd
        if command -v asmcmd >/dev/null 2>&1; then
            log_raw ""
            log_raw "  ASM via asmcmd:"
            echo "lsdg" | asmcmd 2>/dev/null | awk '{printf "    %s\n", $0}' >> "$REPORT_FILE"
        else
            log_raw "    ASM not accessible or not applicable"
        fi
    }

    # Exadata cell check
    log_raw ""
    log_raw "  Exadata Cell Check (if applicable):"
    if command -v cellcli >/dev/null 2>&1; then
        cellcli -e "list cell attributes name, status, freeSpace" 2>/dev/null | \
            awk '{printf "    %s\n", $0}' >> "$REPORT_FILE" || \
            log_raw "    cellcli not accessible"
    else
        log_raw "    cellcli not found - may not be an Exadata cell / cellcli not in PATH"
    fi
}

# --------------------------------------------------------------------------
# Section: Network Security / Firewall
# --------------------------------------------------------------------------
discover_nsg_firewall() {
    log_section "Network Security / Firewall"
    report_section "NETWORK SECURITY / FIREWALL"

    log_raw "  iptables (Oracle-relevant ports 1521, 2484, 22):"
    iptables -L -n 2>/dev/null | grep -E '1521|2484|22|ACCEPT|DROP|REJECT' | \
        awk '{printf "    %s\n", $0}' >> "$REPORT_FILE" || log_raw "    iptables not accessible"

    log_raw ""
    log_raw "  firewalld status:"
    if command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --state 2>/dev/null | awk '{printf "    %s\n", $0}' >> "$REPORT_FILE"
        firewall-cmd --list-ports 2>/dev/null | awk '{printf "    Open ports: %s\n", $0}' >> "$REPORT_FILE"
    else
        log_raw "    firewalld not found"
    fi

    log_raw ""
    log_raw "  ss (listening sockets on Oracle ports):"
    ss -tlnp 2>/dev/null | grep -E '1521|2484|22' | \
        awk '{printf "    %s\n", $0}' >> "$REPORT_FILE" || log_raw "    ss not available"

    # OCI NSG query
    log_raw ""
    log_raw "  OCI NSG List (if OCI CLI configured):"
    if command -v oci >/dev/null 2>&1 && [ -f "$(eval echo "$OCI_CONFIG_PATH")" ]; then
        oci network nsg list --compartment-id "${OCI_COMPARTMENT_OCID:-}" \
            --output table 2>/dev/null | head -30 >> "$REPORT_FILE" || \
            log_raw "    OCI NSG query failed (OCI_COMPARTMENT_OCID may not be set)"
    else
        log_raw "    OCI CLI not available or not configured"
    fi
}

# --------------------------------------------------------------------------
# Write JSON summary
# --------------------------------------------------------------------------
write_json_summary() {
    log_section "Writing JSON Summary"

    cat > "$JSON_FILE" <<ENDJSON
{
  "discovery_type": "target",
  "project": "ORADB",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hostname": "${JSON_DATA[hostname]:-}",
  "ip_addresses": "${JSON_DATA[ip_addresses]:-}",
  "os_version": "${JSON_DATA[os_version]:-}",
  "os_kernel": "${JSON_DATA[os_kernel]:-}",
  "oracle_home": "${JSON_DATA[oracle_home]:-}",
  "oracle_sid": "${JSON_DATA[oracle_sid]:-}",
  "oracle_version": "${JSON_DATA[oracle_version]:-}",
  "db_name": "${JSON_DATA[db_name]:-}",
  "db_unique_name": "${JSON_DATA[db_unique_name]:-}",
  "db_role": "${JSON_DATA[db_role]:-}",
  "charset": "${JSON_DATA[charset]:-}",
  "is_cdb": "${JSON_DATA[is_cdb]:-}",
  "tde_wallet_status": "${JSON_DATA[tde_wallet_status]:-}",
  "tde_wallet_type": "${JSON_DATA[tde_wallet_type]:-}",
  "tns_admin": "${JSON_DATA[tns_admin]:-}",
  "oci_cli_version": "${JSON_DATA[oci_cli_version]:-}",
  "oci_connectivity": "${JSON_DATA[oci_connectivity]:-}",
  "grid_found": "${JSON_DATA[grid_found]:-}",
  "report_file": "$(basename "$REPORT_FILE")"
}
ENDJSON

    log_info "JSON summary written to: $JSON_FILE"
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
main() {
    echo -e "${BOLD}${CYAN}"
    echo "============================================================"
    echo "  ZDM Target Database Discovery (Oracle Database@Azure)"
    echo "  Project: ORADB"
    echo "  Server:  $(hostname)"
    echo "  Date:    $(date)"
    echo "============================================================"
    echo -e "${NC}"

    # Initialize report
    cat > "$REPORT_FILE" <<EOHEADER
==================================================================
ZDM TARGET DATABASE DISCOVERY REPORT
Project:   ORADB
Server:    $(hostname -f 2>/dev/null || hostname)
Date:      $(date)
Script:    $0
==================================================================
EOHEADER

    discover_os_info          || log_error "OS info discovery failed"
    discover_oracle_env       || log_error "Oracle env discovery failed"
    discover_db_config        || log_error "DB config discovery failed"
    discover_cdb_pdb          || log_error "CDB/PDB discovery failed"
    discover_tde              || log_error "TDE discovery failed"
    discover_network          || log_error "Network discovery failed"
    discover_oci_azure        || log_error "OCI/Azure integration discovery failed"
    discover_grid_infra       || log_error "Grid infra discovery failed"
    discover_auth             || log_error "Auth discovery failed"
    discover_exadata_storage  || log_error "Exadata/ASM storage discovery failed"
    discover_nsg_firewall     || log_error "NSG/firewall discovery failed"

    write_json_summary

    log_raw ""
    log_raw "=================================================================="
    log_raw "END OF TARGET DISCOVERY REPORT"
    log_raw "Generated: $(date)"
    log_raw "=================================================================="

    echo ""
    log_info "Discovery complete."
    log_info "Text report: $REPORT_FILE"
    log_info "JSON summary: $JSON_FILE"
}

main "$@"
