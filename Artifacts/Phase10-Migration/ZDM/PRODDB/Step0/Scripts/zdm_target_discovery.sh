#!/bin/bash
# =============================================================================
# ZDM Target Database Discovery Script
# =============================================================================
# Project  : PRODDB Migration to Oracle Database@Azure
# Target   : proddb-oda.eastus.azure.example.com (Oracle Database@Azure)
# Generated: 2026-02-26
#
# USAGE:
#   ./zdm_target_discovery.sh
#
# SSH as TARGET_ADMIN_USER (opc); SQL runs as oracle via sudo.
# Set ORACLE_HOME_OVERRIDE / ORACLE_SID_OVERRIDE to force specific values.
# =============================================================================

# NO set -e  — continue even when individual checks fail
SECTION_ERRORS=0
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME_SHORT=$(hostname -s 2>/dev/null || hostname)
OUTPUT_FILE="./zdm_target_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_target_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

# ---------------------------------------------------------------------------
# Oracle user (can be overridden)
# ---------------------------------------------------------------------------
ORACLE_USER="${ORACLE_USER:-oracle}"

# ---------------------------------------------------------------------------
# Environment bootstrap (3-tier priority)
# ---------------------------------------------------------------------------
# Tier 1: explicit overrides
[ -n "${ORACLE_HOME_OVERRIDE:-}" ]  && export ORACLE_HOME="$ORACLE_HOME_OVERRIDE"
[ -n "${ORACLE_SID_OVERRIDE:-}"  ]  && export ORACLE_SID="$ORACLE_SID_OVERRIDE"
[ -n "${GRID_HOME_OVERRIDE:-}"   ]  && export GRID_HOME="$GRID_HOME_OVERRIDE"

# Tier 2: extract export statements from shell profiles (bypasses interactive guards)
for _profile in /etc/profile /etc/profile.d/*.sh ~/.bash_profile ~/.bashrc; do
    [ -f "$_profile" ] || continue
    eval "$(grep -E '^export[[:space:]]+(ORACLE_HOME|ORACLE_SID|ORACLE_BASE|GRID_HOME|TNS_ADMIN|PATH)=' \
           "$_profile" 2>/dev/null)" 2>/dev/null || true
done

# Tier 3: auto-detect for Oracle Database@Azure / Exadata / ODA
detect_oracle_env() {
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then return 0; fi

    # /etc/oratab
    if [ -f /etc/oratab ]; then
        local entry
        if [ -n "${ORACLE_SID:-}" ]; then
            entry=$(grep -v '^#' /etc/oratab | grep "^${ORACLE_SID}:" | head -1)
        else
            entry=$(grep -v '^#' /etc/oratab | grep ':' | grep -v '^$' | head -1)
        fi
        if [ -n "$entry" ]; then
            export ORACLE_SID="${ORACLE_SID:-$(echo "$entry" | cut -d: -f1)}"
            export ORACLE_HOME="${ORACLE_HOME:-$(echo "$entry" | cut -d: -f2)}"
        fi
    fi

    # pmon
    if [ -z "${ORACLE_SID:-}" ]; then
        local pmon_sid
        pmon_sid=$(ps -ef 2>/dev/null | grep 'ora_pmon_' | grep -v grep | head -1 | sed 's/.*ora_pmon_//')
        [ -n "$pmon_sid" ] && export ORACLE_SID="$pmon_sid"
    fi

    # Common Oracle Database@Azure / Exadata paths
    if [ -z "${ORACLE_HOME:-}" ]; then
        for _path in /u01/app/oracle/product/*/dbhome_1 \
                     /u02/app/oracle/product/*/dbhome_1 \
                     /u01/app/oracle/product/*/dbhome_2 \
                     /opt/oracle/product/*/dbhome_1; do
            if [ -d "$_path" ] && [ -f "$_path/bin/sqlplus" ]; then
                export ORACLE_HOME="$_path"
                break
            fi
        done
    fi

    # Grid Infrastructure (ASM)
    if [ -z "${GRID_HOME:-}" ]; then
        for _gpath in /u01/app/grid/product/*/grid \
                      /u01/app/*/grid /u01/app/grid /u01/grid; do
            if [ -d "$_gpath" ] && [ -f "$_gpath/bin/crsctl" ]; then
                export GRID_HOME="$_gpath"
                break
            fi
        done
    fi

    if [ -n "${ORACLE_HOME:-}" ]; then
        export PATH="$ORACLE_HOME/bin:${GRID_HOME:+$GRID_HOME/bin:}$PATH"
        export LD_LIBRARY_PATH="${ORACLE_HOME}/lib:${LD_LIBRARY_PATH:-}"
    fi
}
detect_oracle_env

# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
log_info()    { echo -e "${GREEN}[INFO ] $*${RESET}";  }
log_warn()    { echo -e "${YELLOW}[WARN ] $*${RESET}"; }
log_error()   { echo -e "${RED}[ERROR] $*${RESET}";   }
log_section() {
    local bar="============================================================"
    echo "" | tee -a "$OUTPUT_FILE"
    echo -e "${CYAN}${BOLD}${bar}${RESET}"  | tee -a "$OUTPUT_FILE"
    echo -e "${CYAN}${BOLD}  $*${RESET}"    | tee -a "$OUTPUT_FILE"
    echo -e "${CYAN}${BOLD}${bar}${RESET}"  | tee -a "$OUTPUT_FILE"
    echo "" | tee -a "$OUTPUT_FILE"
}

# ---------------------------------------------------------------------------
# SQL helper
# ---------------------------------------------------------------------------
run_sql() {
    local sql_query="$1"
    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        echo "ERROR: ORACLE_HOME or ORACLE_SID not set — skipping SQL"
        return 1
    fi
    local sqlplus_cmd="$ORACLE_HOME/bin/sqlplus -s / as sysdba"
    local sql_script
    sql_script=$(cat <<EOSQL
SET PAGESIZE 5000
SET LINESIZE 220
SET FEEDBACK OFF
SET HEADING ON
SET ECHO OFF
SET TRIMSPOOL ON
$sql_query
EXIT
EOSQL
)
    if [ "$(id -un)" = "$ORACLE_USER" ]; then
        echo "$sql_script" | $sqlplus_cmd 2>&1
    else
        echo "$sql_script" | sudo -u "$ORACLE_USER" \
            env ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" \
            LD_LIBRARY_PATH="${ORACLE_HOME}/lib" PATH="$ORACLE_HOME/bin:$PATH" \
            $sqlplus_cmd 2>&1
    fi
}

run_sql_value() {
    run_sql "SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
$1" 2>/dev/null | grep -v '^$' | head -1 | xargs
}

# ---------------------------------------------------------------------------
# ASM helper — runs asmcmd as grid/oracle user
# ---------------------------------------------------------------------------
run_asmcmd() {
    local cmd="$1"
    local grid_user="${GRID_USER:-oracle}"
    if [ -n "${GRID_HOME:-}" ] && [ -f "$GRID_HOME/bin/asmcmd" ]; then
        if [ "$(id -un)" = "$grid_user" ]; then
            echo "$cmd" | ORACLE_HOME="$GRID_HOME" "$GRID_HOME/bin/asmcmd" 2>&1
        else
            echo "$cmd" | sudo -u "$grid_user" \
                env ORACLE_HOME="$GRID_HOME" \
                LD_LIBRARY_PATH="$GRID_HOME/lib" \
                PATH="$GRID_HOME/bin:$PATH" \
                "$GRID_HOME/bin/asmcmd" 2>&1
        fi
    else
        echo "GRID_HOME not set or asmcmd not found"
    fi
}

run_section() {
    local name="$1"; local fn="$2"
    log_section "$name"
    if ! $fn 2>&1 | tee -a "$OUTPUT_FILE"; then
        log_warn "Section '$name' reported errors (continuing)"
        SECTION_ERRORS=$((SECTION_ERRORS + 1))
    fi
}

# ===========================================================================
# DISCOVERY SECTIONS
# ===========================================================================

section_os_info() {
    echo "Hostname     : $(hostname -f 2>/dev/null || hostname)"
    echo "Short name   : $(hostname -s 2>/dev/null || hostname)"
    echo "Date/Time    : $(date)"
    echo "Uptime       : $(uptime)"
    echo ""
    echo "--- IP Addresses ---"
    ip addr show 2>/dev/null || ifconfig 2>/dev/null || echo "N/A"
    echo ""
    echo "--- OS Version ---"
    cat /etc/os-release 2>/dev/null || cat /etc/redhat-release 2>/dev/null || uname -a
    echo ""
    echo "--- Kernel ---"
    uname -r
    echo ""
    echo "--- Memory ---"
    free -h 2>/dev/null
    echo ""
    echo "--- CPU ---"
    nproc 2>/dev/null && grep 'model name' /proc/cpuinfo 2>/dev/null | head -1
}

section_oracle_env() {
    echo "ORACLE_HOME  : ${ORACLE_HOME:-NOT SET}"
    echo "ORACLE_SID   : ${ORACLE_SID:-NOT SET}"
    echo "ORACLE_BASE  : ${ORACLE_BASE:-NOT SET}"
    echo "GRID_HOME    : ${GRID_HOME:-NOT SET}"
    echo ""
    if [ -n "${ORACLE_HOME:-}" ]; then
        echo "--- Oracle Version ---"
        "$ORACLE_HOME/bin/sqlplus" -V 2>&1
    fi
    echo ""
    echo "--- /etc/oratab ---"
    cat /etc/oratab 2>/dev/null || echo "Not found"
    echo ""
    echo "--- Running Oracle Processes ---"
    ps -ef 2>/dev/null | grep -E '[o]ra_pmon|[o]cr_|[o]has' | awk '{print $1, $NF}'
}

section_db_config() {
    echo "--- Database Identity ---"
    run_sql "
SELECT name, db_unique_name, dbid, log_mode, open_mode,
       force_logging, flashback_on, database_role, platform_name
FROM   v\$database;"

    echo ""
    echo "--- Key Parameters ---"
    run_sql "
SELECT name, value FROM v\$parameter
WHERE name IN ('db_name','db_unique_name','enable_pluggable_database',
               'db_block_size','compatible','memory_target',
               'pga_aggregate_target','sga_target','undo_tablespace',
               'archive_dest_1','log_archive_config')
ORDER BY name;"

    echo ""
    echo "--- Database Size ---"
    run_sql "
SELECT 'Data Files (GB)'  AS component,
       ROUND(SUM(bytes)/1024/1024/1024,2) AS size_gb
FROM   dba_data_files
UNION ALL
SELECT 'Temp Files (GB)',ROUND(SUM(bytes)/1024/1024/1024,2) FROM dba_temp_files
UNION ALL
SELECT 'Redo Logs (MB)',ROUND(SUM(bytes)/1024/1024,2) FROM v\$log;"

    echo ""
    echo "--- Character Sets ---"
    run_sql "
SELECT parameter, value FROM nls_database_parameters
WHERE parameter IN ('NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET')
ORDER BY parameter;"
}

section_cdb_pdb() {
    echo "--- CDB Status ---"
    local cdb_flag
    cdb_flag=$(run_sql_value "SELECT cdb FROM v\$database;")
    echo "CDB: $cdb_flag"
    echo ""
    if [ "$cdb_flag" = "YES" ]; then
        echo "--- PDB List ---"
        run_sql "SELECT con_id, name, open_mode, restricted, guid FROM v\$pdbs ORDER BY con_id;"
        echo ""
        echo "--- PDB Sizes ---"
        run_sql "
SELECT p.name AS pdb_name,
       ROUND(SUM(df.bytes)/1024/1024/1024,2) AS size_gb
FROM   v\$pdbs p
JOIN   cdb_data_files df ON df.con_id = p.con_id
GROUP  BY p.name ORDER BY p.name;"
        echo ""
        echo "--- PDB Services ---"
        run_sql "
SELECT con_id, name, network_name FROM cdb_services
ORDER BY con_id, name;"
    else
        echo "Not a CDB — standard database"
    fi
}

section_tde() {
    echo "--- TDE / Wallet Status ---"
    run_sql "
SELECT wrl_type, wrl_parameter, status, wallet_type, con_id
FROM   v\$encryption_wallet ORDER BY con_id;"

    echo ""
    echo "--- Encrypted Tablespaces ---"
    run_sql "SELECT tablespace_name, encrypted FROM dba_tablespaces WHERE encrypted='YES' ORDER BY 1;"
}

section_network_config() {
    local tns_admin="${TNS_ADMIN:-${ORACLE_HOME}/network/admin}"
    echo "--- Listener Status ---"
    if [ -n "${ORACLE_HOME:-}" ]; then
        "$ORACLE_HOME/bin/lsnrctl" status 2>&1 || echo "lsnrctl not available"
    fi

    echo ""
    echo "--- SCAN Listener (RAC) ---"
    if [ -n "${GRID_HOME:-}" ]; then
        sudo -u oracle env ORACLE_HOME="$GRID_HOME" "$GRID_HOME/bin/srvctl" status scan_listener 2>&1 || \
        sudo -u grid   env ORACLE_HOME="$GRID_HOME" "$GRID_HOME/bin/srvctl" status scan_listener 2>&1 || \
        echo "SCAN listener check failed or not RAC"
    fi

    echo ""
    echo "--- tnsnames.ora ---"
    cat "$tns_admin/tnsnames.ora" 2>/dev/null || echo "Not found at $tns_admin"
    # Also check Grid TNS admin
    if [ -n "${GRID_HOME:-}" ]; then
        cat "$GRID_HOME/network/admin/tnsnames.ora" 2>/dev/null | head -40 || true
    fi

    echo ""
    echo "--- Open Ports (Oracle-related) ---"
    ss -tlnp 2>/dev/null | grep -E '1521|1522|5500|6200' || \
    netstat -tlnp 2>/dev/null | grep -E '1521|1522|5500|6200' || echo "N/A"
}

section_oci_azure_integration() {
    echo "--- OCI CLI ---"
    oci --version 2>&1 || echo "OCI CLI not installed or not in PATH"

    echo ""
    echo "--- OCI Config ---"
    if [ -f ~/.oci/config ]; then
        echo "File exists: ~/.oci/config"
        grep -E '^\[|^region|^tenancy|^user|^fingerprint' ~/.oci/config 2>/dev/null
    else
        echo "~/.oci/config not found"
    fi

    echo ""
    echo "--- OCI Connectivity Test ---"
    oci iam region list --output table 2>&1 | head -20 || echo "OCI connectivity test failed"

    echo ""
    echo "--- Azure Instance Metadata (IMDS) ---"
    curl -s -H "Metadata:true" \
        "http://169.254.169.254/metadata/instance?api-version=2021-02-01" \
        --connect-timeout 5 2>&1 | python3 -m json.tool 2>/dev/null || \
    echo "Azure IMDS not reachable (may not be Azure VM or curl not available)"

    echo ""
    echo "--- OCI Instance Metadata ---"
    curl -s http://169.254.169.254/opc/v1/instance/ \
        --connect-timeout 5 2>&1 || echo "OCI IMDS not reachable"
}

section_grid_infrastructure() {
    if [ -z "${GRID_HOME:-}" ]; then
        echo "GRID_HOME not set — skipping Grid Infrastructure checks"
        return 0
    fi

    echo "--- CRS/HAS Status ---"
    sudo "$GRID_HOME/bin/crsctl" check crs 2>&1 || \
    sudo "$GRID_HOME/bin/crsctl" check has 2>&1 || echo "CRS/HAS check failed"

    echo ""
    echo "--- Cluster Nodes ---"
    sudo "$GRID_HOME/bin/olsnodes" -n 2>&1 || echo "olsnodes not available"

    echo ""
    echo "--- RAC Database Status ---"
    sudo -u oracle env ORACLE_HOME="$GRID_HOME" \
        "$GRID_HOME/bin/srvctl" status database -d "${ORACLE_SID:-}" 2>&1 || \
    echo "srvctl status check failed"

    echo ""
    echo "--- SCAN Addresses ---"
    sudo -u oracle env ORACLE_HOME="$GRID_HOME" \
        "$GRID_HOME/bin/srvctl" config scan 2>&1 || echo "SCAN config check failed"
}

section_auth() {
    echo "--- SSH Directory ---"
    ls -la ~/.ssh/ 2>/dev/null || echo "No .ssh directory for current user"

    echo ""
    echo "--- Oracle User SSH Directory ---"
    local oracle_home_dir
    oracle_home_dir=$(eval echo "~$ORACLE_USER" 2>/dev/null)
    if sudo test -d "$oracle_home_dir/.ssh" 2>/dev/null; then
        sudo -u "$ORACLE_USER" ls -la "$oracle_home_dir/.ssh/" 2>/dev/null || echo "Cannot list"
    else
        echo "Oracle user SSH dir not found (not a blocker — sudo pattern used)"
    fi

    echo ""
    echo "--- sudoers for oracle (relevant entries) ---"
    sudo grep -E 'oracle|opc|azureuser' /etc/sudoers /etc/sudoers.d/* 2>/dev/null | \
        grep -v '^#' | head -20 || echo "Cannot read sudoers"
}

# -----------------------------------------------------------------------
# ADDITIONAL TARGET DISCOVERY (user-requested)
# -----------------------------------------------------------------------

section_exadata_storage() {
    echo "--- ASM Disk Groups (Exadata Storage) ---"
    run_asmcmd "lsdg --discovery"
    echo ""
    run_sql "
SELECT group_number, name, type, total_mb, free_mb,
       ROUND((total_mb - free_mb)/total_mb * 100, 1) AS pct_used,
       state, offline_disks
FROM   v\$asm_diskgroup
ORDER  BY name;" 2>/dev/null

    echo ""
    echo "--- ASM Disks Summary ---"
    run_sql "
SELECT dg.name AS disk_group,
       COUNT(d.disk_number) AS disk_count,
       SUM(d.total_mb) AS total_mb,
       SUM(d.free_mb) AS free_mb
FROM   v\$asm_disk d JOIN v\$asm_diskgroup dg ON d.group_number = dg.group_number
WHERE  dg.state = 'MOUNTED'
GROUP  BY dg.name ORDER BY dg.name;" 2>/dev/null

    echo ""
    echo "--- Exadata Cell / Smart Scan (if applicable) ---"
    if [ -f /etc/oracle/cell/network-config/cellinit.ora ]; then
        echo "Exadata cell config found:"
        cat /etc/oracle/cell/network-config/cellinit.ora
    else
        echo "Not configured as Exadata cell (may be ODA or BM Exadata VM)"
    fi

    echo ""
    echo "--- Datafile Locations (ASM) ---"
    run_sql "
SELECT tablespace_name,
       SUBSTR(file_name,1,50) AS file_name_prefix,
       ROUND(bytes/1024/1024/1024,2) AS size_gb,
       autoextensible
FROM   dba_data_files ORDER BY tablespace_name FETCH FIRST 30 ROWS ONLY;"

    echo ""
    echo "--- Available Tablespace Space ---"
    run_sql "
SELECT t.tablespace_name,
       t.status, t.contents, t.bigfile,
       ROUND(SUM(df.bytes)/1024/1024/1024,2) AS allocated_gb,
       ROUND(NVL(fs.free_gb,0),2) AS free_gb
FROM   dba_tablespaces t
LEFT JOIN dba_data_files df ON df.tablespace_name = t.tablespace_name
LEFT JOIN (
    SELECT tablespace_name, ROUND(SUM(bytes)/1024/1024/1024,2) AS free_gb
    FROM   dba_free_space GROUP BY tablespace_name
) fs ON fs.tablespace_name = t.tablespace_name
GROUP  BY t.tablespace_name, t.status, t.contents, t.bigfile, fs.free_gb
ORDER  BY t.tablespace_name;"
}

section_preconfigured_pdbs() {
    echo "--- Pre-configured PDBs on Target ---"
    run_sql "
SELECT con_id, name, open_mode, restricted, create_scn,
       to_char(creation_time,'YYYY-MM-DD HH24:MI:SS') AS created
FROM   v\$pdbs ORDER BY con_id;"

    echo ""
    echo "--- PDB Options and Features ---"
    run_sql "
SELECT con_id, comp_name, status
FROM   cdb_registry
ORDER  BY con_id, comp_name;" 2>/dev/null || echo "cdb_registry not accessible (may need SYSDBA to CDB root)"

    echo ""
    echo "--- Default Services per PDB ---"
    run_sql "
SELECT con_id, name, network_name, pdb
FROM   cdb_services WHERE con_id > 2 ORDER BY con_id, name;" 2>/dev/null

    echo ""
    echo "--- PDB Tablespaces (per PDB) ---"
    run_sql "
SELECT con_id, tablespace_name, status, contents, bigfile
FROM   cdb_tablespaces WHERE con_id > 2 ORDER BY con_id, tablespace_name;" 2>/dev/null
}

section_nsg_rules() {
    echo "--- Azure Network Security Groups (via Azure CLI) ---"
    if command -v az >/dev/null 2>&1; then
        echo "Azure CLI available: $(az --version 2>&1 | head -1)"
        echo ""
        echo "Listing NSG rules affecting this VM:"
        VM_NAME=$(curl -s -H "Metadata:true" \
            "http://169.254.169.254/metadata/instance/compute/name?api-version=2021-02-01&format=text" \
            --connect-timeout 5 2>/dev/null) || VM_NAME="unknown"
        RG=$(curl -s -H "Metadata:true" \
            "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-02-01&format=text" \
            --connect-timeout 5 2>/dev/null) || RG="unknown"
        echo "VM Name: $VM_NAME  Resource Group: $RG"
        if [ "$VM_NAME" != "unknown" ] && [ "$RG" != "unknown" ]; then
            az network nic list-effective-nsg \
                --resource-group "$RG" --vm-name "$VM_NAME" \
                --output table 2>&1 | head -60 || echo "Unable to list NSG rules (check Azure login)"
        else
            echo "Unable to determine VM name/resource group automatically"
            echo "Manual command to run with appropriate credentials:"
            echo "  az network nic list-effective-nsg --resource-group <RG> --vm-name <VM>"
        fi
    else
        echo "Azure CLI (az) not installed on this host"
        echo "To check NSG rules, run from Azure Cloud Shell or a machine with az CLI:"
        echo "  az network nsg list --resource-group <RG> --output table"
        echo "  az network nsg rule list --nsg-name <NSG_NAME> --resource-group <RG> --output table"
    fi

    echo ""
    echo "--- OCI Security Lists / NSGs (via OCI CLI) ---"
    if command -v oci >/dev/null 2>&1; then
        echo "OCI CLI available: $(oci --version 2>&1)"
        echo "Manual command to check:"
        echo "  oci network nsg list --compartment-id <COMPARTMENT_OCID> --output table"
        echo "  oci network security-list list --compartment-id <COMPARTMENT_OCID> --output table"
        oci network nsg list --all --output table 2>&1 | head -30 || \
            echo "Unable to list OCI NSGs without compartment OCID"
    else
        echo "OCI CLI not installed"
    fi

    echo ""
    echo "--- iptables / firewalld Rules (host-level) ---"
    if command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --list-all 2>&1 || echo "firewalld not running"
    else
        iptables -L -n --line-numbers 2>/dev/null | head -60 || echo "iptables not accessible"
    fi
}

# ===========================================================================
# JSON SUMMARY
# ===========================================================================

generate_json_summary() {
    local db_name db_unique hostname db_version db_role cdb_flag
    db_name=$(run_sql_value "SELECT name FROM v\$database;")
    db_unique=$(run_sql_value "SELECT db_unique_name FROM v\$database;")
    hostname=$(hostname -f 2>/dev/null || hostname)
    db_version=$(run_sql_value "SELECT version FROM v\$instance;")
    db_role=$(run_sql_value "SELECT database_role FROM v\$database;")
    cdb_flag=$(run_sql_value "SELECT cdb FROM v\$database;")

    cat > "$JSON_FILE" <<EOJSON
{
  "discovery_type"   : "target_database",
  "project"          : "PRODDB Migration to Oracle Database@Azure",
  "generated_at"     : "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hostname"         : "${hostname}",
  "oracle_home"      : "${ORACLE_HOME:-unknown}",
  "oracle_sid"       : "${ORACLE_SID:-unknown}",
  "grid_home"        : "${GRID_HOME:-unknown}",
  "db_name"          : "${db_name:-unknown}",
  "db_unique_name"   : "${db_unique:-unknown}",
  "db_version"       : "${db_version:-unknown}",
  "database_role"    : "${db_role:-unknown}",
  "cdb"              : "${cdb_flag:-unknown}",
  "section_errors"   : ${SECTION_ERRORS},
  "output_text_file" : "${OUTPUT_FILE}"
}
EOJSON
    echo "JSON summary written to: $JSON_FILE"
}

# ===========================================================================
# MAIN
# ===========================================================================

{
echo "============================================================"
echo "  ZDM TARGET DATABASE DISCOVERY"
echo "  Project : PRODDB Migration to Oracle Database@Azure"
echo "  Host    : $(hostname -f 2>/dev/null || hostname)"
echo "  Started : $(date)"
echo "  Run by  : $(id)"
echo "  ORACLE_HOME  : ${ORACLE_HOME:-NOT SET}"
echo "  ORACLE_SID   : ${ORACLE_SID:-NOT SET}"
echo "  GRID_HOME    : ${GRID_HOME:-NOT SET}"
echo "============================================================"
} | tee "$OUTPUT_FILE"

run_section "1. OS INFORMATION"                        section_os_info
run_section "2. ORACLE ENVIRONMENT"                    section_oracle_env
run_section "3. DATABASE CONFIGURATION"                section_db_config
run_section "4. CONTAINER DATABASE (CDB/PDB)"          section_cdb_pdb
run_section "5. TDE CONFIGURATION"                     section_tde
run_section "6. NETWORK CONFIGURATION"                 section_network_config
run_section "7. OCI / AZURE INTEGRATION"               section_oci_azure_integration
run_section "8. GRID INFRASTRUCTURE (RAC/ASM)"         section_grid_infrastructure
run_section "9. AUTHENTICATION"                        section_auth
run_section "10. EXADATA STORAGE CAPACITY"             section_exadata_storage
run_section "11. PRE-CONFIGURED PDBs"                  section_preconfigured_pdbs
run_section "12. NETWORK SECURITY GROUP RULES"         section_nsg_rules

generate_json_summary

{
echo ""
echo "============================================================"
echo "  DISCOVERY COMPLETE"
echo "  Sections with errors : $SECTION_ERRORS"
echo "  Text report : $OUTPUT_FILE"
echo "  JSON summary: $JSON_FILE"
echo "  Finished    : $(date)"
echo "============================================================"
} | tee -a "$OUTPUT_FILE"

exit 0
