#!/bin/bash
# =============================================================================
# ZDM Target Database Discovery Script
# Project: ORADB
# Generated for: Oracle ZDM Migration - Step 0
#
# Purpose: Discover target Oracle Database@Azure configuration.
# Run as: SSH as TARGET_ADMIN_USER (opc), SQL runs via sudo -u oracle
#
# Usage: ./zdm_target_discovery.sh
# Output: ./zdm_target_discovery_<hostname>_<timestamp>.txt
#         ./zdm_target_discovery_<hostname>_<timestamp>.json
# =============================================================================

set -o nounset
set -o pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================
ORACLE_USER="${ORACLE_USER:-oracle}"
ORACLE_HOME="${ORACLE_HOME:-}"
ORACLE_SID="${ORACLE_SID:-}"

# =============================================================================
# COLORS & LOGGING
# =============================================================================
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname)"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_TEXT="./zdm_target_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
OUTPUT_JSON="./zdm_target_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

log_info()    { echo -e "${GREEN}[INFO]${NC}  $*" | tee -a "$OUTPUT_TEXT"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*" | tee -a "$OUTPUT_TEXT"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" | tee -a "$OUTPUT_TEXT"; }
log_section() {
    local line="========================================================================"
    echo -e "\n${CYAN}${line}${NC}" | tee -a "$OUTPUT_TEXT"
    echo -e "${CYAN}  $*${NC}" | tee -a "$OUTPUT_TEXT"
    echo -e "${CYAN}${line}${NC}" | tee -a "$OUTPUT_TEXT"
}
log_raw() { echo "$*" | tee -a "$OUTPUT_TEXT"; }

# =============================================================================
# AUTO-DETECTION
# =============================================================================
detect_oracle_env() {
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        log_info "Using pre-set ORACLE_HOME=$ORACLE_HOME  ORACLE_SID=$ORACLE_SID"
        return 0
    fi

    # Method 1: /etc/oratab
    if [ -f /etc/oratab ]; then
        local entry
        if [ -n "${ORACLE_SID:-}" ]; then
            entry=$(grep "^${ORACLE_SID}:" /etc/oratab 2>/dev/null | head -1)
        else
            entry=$(grep -v '^#' /etc/oratab | grep -v '^$' | grep -v '^+' | head -1)
        fi
        if [ -n "$entry" ]; then
            ORACLE_SID="${ORACLE_SID:-$(echo "$entry" | cut -d: -f1)}"
            ORACLE_HOME="${ORACLE_HOME:-$(echo "$entry" | cut -d: -f2)}"
        fi
    fi

    # Method 2: Running pmon process
    if [ -z "${ORACLE_SID:-}" ]; then
        local pmon_sid
        pmon_sid=$(ps -ef 2>/dev/null | grep 'ora_pmon_' | grep -v grep | head -1 | sed 's/.*ora_pmon_//')
        [ -n "$pmon_sid" ] && ORACLE_SID="$pmon_sid"
    fi

    # Method 3: Common paths (Exadata / ODA target)
    if [ -z "${ORACLE_HOME:-}" ]; then
        for p in /u01/app/oracle/product/*/dbhome_1 /u02/app/oracle/product/*/dbhome_1 \
                  /opt/oracle/product/*/dbhome_1 /oracle/product/*/dbhome_1; do
            if [ -d "$p" ] && [ -f "$p/bin/sqlplus" ]; then
                ORACLE_HOME="$p"
                break
            fi
        done
    fi

    # Apply explicit overrides
    [ -n "${TARGET_REMOTE_ORACLE_HOME:-}" ] && ORACLE_HOME="$TARGET_REMOTE_ORACLE_HOME"
    [ -n "${TARGET_REMOTE_ORACLE_SID:-}" ]  && ORACLE_SID="$TARGET_REMOTE_ORACLE_SID"

    export ORACLE_HOME ORACLE_SID

    if [ -n "$ORACLE_HOME" ] && [ -n "$ORACLE_SID" ]; then
        log_info "Detected ORACLE_HOME=$ORACLE_HOME  ORACLE_SID=$ORACLE_SID"
    else
        log_warn "Could not auto-detect Oracle environment. Set ORACLE_HOME and ORACLE_SID manually."
    fi
}

run_sql() {
    local sql_query="$1"
    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        echo "ORACLE_HOME or ORACLE_SID not set"
        return 1
    fi
    local sqlplus_cmd="$ORACLE_HOME/bin/sqlplus -s / as sysdba"
    local sql_script
    sql_script=$(printf 'SET PAGESIZE 5000\nSET LINESIZE 300\nSET FEEDBACK OFF\nSET HEADING ON\nSET ECHO OFF\nSET TRIMSPOOL ON\n%s\nEXIT;\n' "$sql_query")
    if [ "$(whoami)" = "$ORACLE_USER" ]; then
        echo "$sql_script" | ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd 2>&1
    else
        echo "$sql_script" | sudo -u "$ORACLE_USER" -E env ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd 2>&1
    fi
}

# =============================================================================
# JSON BUILDER
# =============================================================================
JSON_SECTIONS=()
json_add() {
    local key="$1"
    local val="$2"
    local escaped
    escaped=$(printf '%s' "$val" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\r')
    JSON_SECTIONS+=("  \"${key}\": \"${escaped}\"")
}

# =============================================================================
# DISCOVERY SECTIONS
# =============================================================================

discover_os() {
    log_section "OS INFORMATION"
    log_raw "Hostname:       $(hostname -f 2>/dev/null || hostname)"
    log_raw "Short hostname: ${HOSTNAME_SHORT}"
    log_raw "IP addresses:"
    ip addr show 2>/dev/null | grep 'inet ' | awk '{print "  " $2}' | tee -a "$OUTPUT_TEXT" || true
    log_raw "OS version:"
    cat /etc/os-release 2>/dev/null | tee -a "$OUTPUT_TEXT" || true
    log_raw "Kernel: $(uname -r)"

    json_add "hostname" "$(hostname -f 2>/dev/null || hostname)"
    json_add "os_version" "$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2)"
}

discover_oracle_env() {
    log_section "ORACLE ENVIRONMENT"
    log_raw "ORACLE_HOME: ${ORACLE_HOME:-NOT SET}"
    log_raw "ORACLE_SID:  ${ORACLE_SID:-NOT SET}"
    log_raw "Oracle version:"
    if [ -f "${ORACLE_HOME:-}/bin/sqlplus" ]; then
        "${ORACLE_HOME}/bin/sqlplus" -version 2>&1 | tee -a "$OUTPUT_TEXT" || true
    else
        log_warn "sqlplus binary not found"
    fi
    json_add "oracle_home" "${ORACLE_HOME:-}"
    json_add "oracle_sid" "${ORACLE_SID:-}"
}

discover_db_config() {
    log_section "DATABASE CONFIGURATION"
    run_sql "
SELECT 'DB_NAME='||NAME FROM V\$DATABASE;
SELECT 'DB_UNIQUE_NAME='||DB_UNIQUE_NAME FROM V\$DATABASE;
SELECT 'DB_ROLE='||DATABASE_ROLE FROM V\$DATABASE;
SELECT 'OPEN_MODE='||OPEN_MODE FROM V\$DATABASE;
SELECT 'NLS_CHARACTERSET='||VALUE FROM NLS_DATABASE_PARAMETERS WHERE PARAMETER='NLS_CHARACTERSET';
SELECT 'NLS_NCHAR_CHARACTERSET='||VALUE FROM NLS_DATABASE_PARAMETERS WHERE PARAMETER='NLS_NCHAR_CHARACTERSET';
SELECT 'CDB='||CDB FROM V\$DATABASE;
" | tee -a "$OUTPUT_TEXT" || log_warn "Could not query V\$DATABASE"

    log_raw "--- Available Storage ---"
    run_sql "
SELECT TABLESPACE_NAME, STATUS,
       ROUND(SUM(BYTES)/1024/1024/1024,3) AS TOTAL_GB
FROM   DBA_DATA_FILES
GROUP  BY TABLESPACE_NAME, STATUS
ORDER  BY TABLESPACE_NAME;
" | tee -a "$OUTPUT_TEXT" || log_warn "Could not query tablespaces"
}

discover_cdb_pdbs() {
    log_section "CONTAINER DATABASE / PDB STATUS"
    local cdb
    cdb=$(run_sql "SELECT CDB FROM V\$DATABASE;" 2>/dev/null | grep -v '^$' | tail -1 | xargs) || cdb="UNKNOWN"
    log_raw "CDB: $cdb"

    run_sql "
SELECT P.CON_ID, P.NAME, P.OPEN_MODE, P.RESTRICTED,
       P.CREATION_SCN,
       T.MAX_SIZE AS PDB_MAX_SIZE_BYTES
FROM   V\$PDBS P
LEFT   JOIN CDB_PDB_HISTORY PH ON P.CON_ID = PH.CON_ID AND ROWNUM = 1
LEFT   JOIN DBA_PDB_SAVED_STATES T ON P.NAME = T.PDB_NAME
ORDER  BY P.CON_ID;
" | tee -a "$OUTPUT_TEXT" || log_warn "Could not list PDBs"

    # Simpler fallback
    run_sql "
SELECT CON_ID, NAME, OPEN_MODE, RESTRICTED FROM V\$PDBS ORDER BY CON_ID;
" | tee -a "$OUTPUT_TEXT" || true
}

discover_tde() {
    log_section "TDE / WALLET STATUS"
    run_sql "
SELECT WRL_TYPE, WRL_PARAMETER, STATUS, WALLET_TYPE
FROM   V\$ENCRYPTION_WALLET;
" | tee -a "$OUTPUT_TEXT" || log_warn "Could not query TDE wallet"
}

discover_network() {
    log_section "NETWORK CONFIGURATION"
    log_raw "--- Listener Status ---"
    if [ "$(whoami)" = "$ORACLE_USER" ]; then
        "${ORACLE_HOME:-}/bin/lsnrctl" status 2>&1 | tee -a "$OUTPUT_TEXT" || log_warn "lsnrctl not available"
    else
        sudo -u "$ORACLE_USER" -E env ORACLE_HOME="${ORACLE_HOME:-}" "${ORACLE_HOME:-}/bin/lsnrctl" status 2>&1 | tee -a "$OUTPUT_TEXT" || log_warn "lsnrctl not available"
    fi

    log_raw "--- SCAN Listener Status (RAC) ---"
    if [ "$(whoami)" = "$ORACLE_USER" ]; then
        "${ORACLE_HOME:-}/bin/lsnrctl" status LISTENER_SCAN1 2>&1 | tee -a "$OUTPUT_TEXT" || log_info "SCAN listener not found (single instance or different name)"
    else
        sudo -u "$ORACLE_USER" -E env ORACLE_HOME="${ORACLE_HOME:-}" "${ORACLE_HOME:-}/bin/lsnrctl" status LISTENER_SCAN1 2>&1 | tee -a "$OUTPUT_TEXT" || log_info "SCAN listener not found"
    fi

    log_raw "--- tnsnames.ora ---"
    local tns_file="${ORACLE_HOME:-}/network/admin/tnsnames.ora"
    [ -f "$tns_file" ] && cat "$tns_file" | tee -a "$OUTPUT_TEXT" || log_warn "tnsnames.ora not found at $tns_file"
}

discover_oci_azure() {
    log_section "OCI / AZURE INTEGRATION"
    log_raw "--- OCI CLI Version ---"
    oci --version 2>&1 | tee -a "$OUTPUT_TEXT" || log_warn "OCI CLI not found"

    log_raw "--- OCI Config ---"
    if [ -f ~/.oci/config ]; then
        # Mask private key paths and fingerprints
        sed 's/\(key_file\s*=\s*\).*/\1<masked>/; s/\(fingerprint\s*=\s*\).*/\1<masked>/' ~/.oci/config | tee -a "$OUTPUT_TEXT"
    else
        log_warn "OCI config not found at ~/.oci/config"
    fi

    log_raw "--- OCI Connectivity Test ---"
    if command -v oci &>/dev/null; then
        oci iam user list --limit 1 2>&1 | head -5 | tee -a "$OUTPUT_TEXT" || log_warn "OCI connectivity test failed"
    fi

    log_raw "--- OCI Instance Metadata ---"
    curl -s --connect-timeout 5 http://169.254.169.254/opc/v2/instance/ 2>/dev/null | tee -a "$OUTPUT_TEXT" || log_warn "OCI metadata service not reachable"

    log_raw "--- Azure Instance Metadata ---"
    curl -s --connect-timeout 5 -H "Metadata:true" \
        "http://169.254.169.254/metadata/instance?api-version=2021-02-01" 2>/dev/null | tee -a "$OUTPUT_TEXT" || log_info "Azure metadata service not reachable (expected on OCI)"
}

discover_grid() {
    log_section "GRID INFRASTRUCTURE (RAC/CRS)"
    log_raw "--- CRS Status ---"
    # Try grid home locations
    for grid_home in /u01/app/grid/product/*/grid /u01/app/19.0.0.0/grid /u01/app/21.0.0.0/grid \
                     /u01/grid/product/*/grid /opt/oracle/product/*/grid; do
        if [ -f "$grid_home/bin/crsctl" ]; then
            log_raw "Grid home: $grid_home"
            "$grid_home/bin/crsctl" stat res -t 2>&1 | tee -a "$OUTPUT_TEXT" || log_warn "crsctl failed"
            break
        fi
    done
    sudo -u oracle "$grid_home/bin/crsctl" check crs 2>/dev/null | tee -a "$OUTPUT_TEXT" || true
    json_add "grid_detected" "$([ -f "$grid_home/bin/crsctl" ] && echo YES || echo NO)"
}

discover_auth() {
    log_section "AUTHENTICATION (SSH)"
    if [ "$(whoami)" = "$ORACLE_USER" ]; then
        ls -la ~/.ssh/ 2>/dev/null | tee -a "$OUTPUT_TEXT" || log_warn "No ~/.ssh directory"
    else
        sudo -u "$ORACLE_USER" bash -c 'ls -la ~/.ssh/ 2>/dev/null' 2>&1 | tee -a "$OUTPUT_TEXT" || log_warn "Cannot list oracle SSH directory"
    fi
}

discover_asm() {
    log_section "EXADATA / ASM STORAGE CAPACITY"
    log_raw "--- ASM Disk Groups ---"
    run_sql "
SELECT GROUP_NUMBER, NAME, TYPE,
       ROUND(TOTAL_MB/1024,2)  AS TOTAL_GB,
       ROUND(FREE_MB/1024,2)   AS FREE_GB,
       ROUND((TOTAL_MB-FREE_MB)/1024,2) AS USED_GB,
       ROUND(FREE_MB/TOTAL_MB*100,1)    AS PCT_FREE
FROM   V\$ASM_DISKGROUP
ORDER  BY NAME;
" | tee -a "$OUTPUT_TEXT" || {
        # Try via +ASM instance
        log_info "Trying ASM via asmcmd..."
        if command -v asmcmd &>/dev/null; then
            echo 'lsdg' | asmcmd 2>&1 | tee -a "$OUTPUT_TEXT" || log_warn "asmcmd failed — ASM may not be accessible"
        else
            log_warn "ASM not accessible from this instance"
        fi
    }

    log_raw "--- Exadata Cell Storage (if available) ---"
    if command -v cellcli &>/dev/null; then
        cellcli -e 'list celldisk attributes name, status, freespace, size' 2>&1 | tee -a "$OUTPUT_TEXT" || log_warn "cellcli failed"
    else
        log_info "cellcli not available (not Exadata X8M+ or no access)"
    fi
}

discover_nsg_rules() {
    log_section "NETWORK SECURITY GROUP / FIREWALL RULES"
    log_raw "--- iptables rules (Oracle ports) ---"
    sudo iptables -L -n 2>/dev/null | grep -E '1521|2484|22|ACCEPT|DROP|REJECT' | tee -a "$OUTPUT_TEXT" || log_warn "iptables not accessible"

    log_raw "--- firewalld rules ---"
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --list-all 2>&1 | tee -a "$OUTPUT_TEXT" || log_warn "firewalld not accessible"
    else
        log_info "firewalld not installed"
    fi

    log_raw "--- OCI NSG Rules (via OCI CLI) ---"
    if command -v oci &>/dev/null && [ -f ~/.oci/config ]; then
        local compartment_ocid="ocid1.compartment.oc1..aaaaaaaas4upnqj72dfiivgwvn3uui5gkxo7ng6leeoifucbjiy326urbhmq"
        oci network nsg list --compartment-id "$compartment_ocid" 2>&1 | head -30 | tee -a "$OUTPUT_TEXT" || log_warn "OCI NSG list failed"
    else
        log_info "OCI CLI not configured - skipping OCI NSG rules"
    fi
}

# =============================================================================
# GENERATE JSON SUMMARY
# =============================================================================
write_json() {
    {
        echo "{"
        local first=true
        for entry in "${JSON_SECTIONS[@]}"; do
            [ "$first" = true ] && first=false || echo ","
            printf '%s' "$entry"
        done
        echo ""
        echo "}"
    } > "$OUTPUT_JSON"
    log_info "JSON summary written to: $OUTPUT_JSON"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    > "$OUTPUT_TEXT"

    log_section "ZDM TARGET DATABASE DISCOVERY (Oracle Database@Azure)"
    log_info "Start time: $(date)"
    log_info "Running as user: $(whoami)"
    log_info "ORACLE_USER: $ORACLE_USER"

    detect_oracle_env

    discover_os
    discover_oracle_env
    discover_db_config     || log_warn "DB config section failed"
    discover_cdb_pdbs      || log_warn "CDB/PDB section failed"
    discover_tde           || log_warn "TDE section failed"
    discover_network       || log_warn "Network section failed"
    discover_oci_azure     || log_warn "OCI/Azure section failed"
    discover_grid          || log_warn "Grid section failed"
    discover_auth          || log_warn "Auth section failed"
    discover_asm           || log_warn "ASM/Storage section failed"
    discover_nsg_rules     || log_warn "NSG/Firewall section failed"

    json_add "discovery_timestamp" "$TIMESTAMP"
    json_add "discovery_host" "$HOSTNAME_SHORT"
    write_json

    log_section "DISCOVERY COMPLETE"
    log_info "End time: $(date)"
    log_info "Text report: $OUTPUT_TEXT"
    log_info "JSON summary: $OUTPUT_JSON"
}

main "$@"
