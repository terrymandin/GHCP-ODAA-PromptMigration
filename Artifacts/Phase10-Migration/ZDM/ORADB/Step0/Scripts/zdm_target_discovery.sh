#!/bin/bash
# =============================================================================
# zdm_target_discovery.sh
# ZDM Migration - Target Database Discovery Script (Oracle Database@Azure)
# Project: ORADB
#
# Purpose: Gather technical context from the target Oracle Database@Azure server.
#          Executed via SSH as TARGET_ADMIN_USER (opc); SQL commands run as
#          oracle user via sudo following the enterprise admin-user-with-sudo pattern.
#
# Usage: bash zdm_target_discovery.sh [-v] [-h]
#   -v  Verbose output
#   -h  Show usage
#
# Output:
#   ./zdm_target_discovery_<hostname>_<timestamp>.txt
#   ./zdm_target_discovery_<hostname>_<timestamp>.json
# =============================================================================

# --- Do NOT use set -e; individual sections handle their own errors ---

# -----------------------------------------------------------------------
# Colour helpers
# -----------------------------------------------------------------------
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

VERBOSE=false
for arg in "$@"; do
    case "$arg" in
        -v|--verbose) VERBOSE=true ;;
        -h|--help)
            echo "Usage: $0 [-v] [-h]"
            echo "  -v  Verbose output"
            echo "  -h  Show this help"
            exit 0
            ;;
    esac
done

# -----------------------------------------------------------------------
# Output file setup
# -----------------------------------------------------------------------
HOSTNAME_SHORT=$(hostname -s 2>/dev/null || hostname)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="./zdm_target_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_target_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

# Default users
ORACLE_USER="${ORACLE_USER:-oracle}"

# -----------------------------------------------------------------------
# Logging functions
# -----------------------------------------------------------------------
log_info()    { echo -e "${GREEN}[INFO ]${RESET} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN ]${RESET} $*"; }
log_error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
log_debug()   { $VERBOSE && echo -e "${CYAN}[DEBUG]${RESET} $*" || true; }
log_section() { echo -e "\n${BOLD}${CYAN}=== $* ===${RESET}"; }
log_raw()     { echo "$*" >> "$REPORT_FILE"; }

# -----------------------------------------------------------------------
# Auto-detect Oracle environment
# -----------------------------------------------------------------------
detect_oracle_env() {
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        log_debug "Oracle env already set: ORACLE_HOME=$ORACLE_HOME ORACLE_SID=$ORACLE_SID"
        return 0
    fi

    # Method 1: /etc/oratab
    if [ -f /etc/oratab ]; then
        local entry
        if [ -n "${ORACLE_SID:-}" ]; then
            entry=$(grep "^${ORACLE_SID}:" /etc/oratab 2>/dev/null | head -1)
        else
            entry=$(grep -v '^#' /etc/oratab 2>/dev/null | grep -v '^$' | head -1)
        fi
        if [ -n "$entry" ]; then
            export ORACLE_SID="${ORACLE_SID:-$(echo "$entry" | cut -d: -f1)}"
            export ORACLE_HOME="${ORACLE_HOME:-$(echo "$entry" | cut -d: -f2)}"
        fi
    fi

    # Method 2: pmon process
    if [ -z "${ORACLE_SID:-}" ]; then
        local pmon_sid
        pmon_sid=$(ps -ef 2>/dev/null | grep 'ora_pmon_' | grep -v grep | head -1 | sed 's/.*ora_pmon_//')
        [ -n "$pmon_sid" ] && export ORACLE_SID="$pmon_sid"
    fi

    # Method 3: common paths
    if [ -z "${ORACLE_HOME:-}" ]; then
        for p in /u01/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1 /oracle/product/*/dbhome_1; do
            if [ -d "$p" ] && [ -f "$p/bin/sqlplus" ]; then
                export ORACLE_HOME="$p"; break
            fi
        done
    fi

    # Method 4: oraenv
    if [ -z "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ] && [ -f /usr/local/bin/oraenv ]; then
        ORACLE_PATH_UAP=YES
        export ORACLE_PATH_UAP
        . /usr/local/bin/oraenv <<< "$ORACLE_SID" 2>/dev/null || true
    fi

    # Apply explicit overrides (highest priority)
    [ -n "${ORACLE_HOME_OVERRIDE:-}" ] && export ORACLE_HOME="$ORACLE_HOME_OVERRIDE"
    [ -n "${ORACLE_SID_OVERRIDE:-}" ]  && export ORACLE_SID="$ORACLE_SID_OVERRIDE"

    export ORACLE_BASE="${ORACLE_BASE:-$(dirname "$(dirname "${ORACLE_HOME:-/u01/app/oracle/product/19.0.0/dbhome_1}")")}"
}

# -----------------------------------------------------------------------
# SQL execution helper
# -----------------------------------------------------------------------
run_sql() {
    local sql_query="$1"
    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        echo "ERROR: ORACLE_HOME or ORACLE_SID not set"; return 1
    fi
    local sqlplus_cmd="${ORACLE_HOME}/bin/sqlplus -s / as sysdba"
    local sql_script
    sql_script=$(printf 'SET PAGESIZE 1000\nSET LINESIZE 200\nSET FEEDBACK OFF\nSET HEADING ON\nSET ECHO OFF\nSET TRIMSPOOL ON\n%s\nEXIT;\n' "$sql_query")
    if [ "$(whoami)" = "$ORACLE_USER" ]; then
        echo "$sql_script" | $sqlplus_cmd 2>&1
    else
        echo "$sql_script" | sudo -u "$ORACLE_USER" -E ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd 2>&1
    fi
}

run_sql_value() {
    local sql_query="$1"
    run_sql "SET PAGESIZE 0
SET FEEDBACK OFF
SET HEADING OFF
SET ECHO OFF
$sql_query" | grep -v '^$' | head -1 | xargs 2>/dev/null || echo "UNKNOWN"
}

# -----------------------------------------------------------------------
# Header
# -----------------------------------------------------------------------
write_header() {
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S %Z')
    log_section "ZDM Target Database Discovery"
    {
        echo "========================================================================"
        echo "  ZDM Target Database Discovery Report (Oracle Database@Azure)"
        echo "  Project : ORADB"
        echo "  Host    : $(hostname)"
        echo "  User    : $(whoami)"
        echo "  Started : $ts"
        echo "========================================================================"
        echo ""
    } >> "$REPORT_FILE"
}

# -----------------------------------------------------------------------
# OS Information
# -----------------------------------------------------------------------
collect_os_info() {
    log_section "OS Information"
    log_raw ""
    log_raw "### OS INFORMATION ###"
    log_raw "Hostname      : $(hostname -f 2>/dev/null || hostname)"
    log_raw "Short hostname: $(hostname -s 2>/dev/null || hostname)"
    log_raw "Date/Time     : $(date '+%Y-%m-%d %H:%M:%S %Z')"
    log_raw "Current user  : $(whoami)"

    log_raw ""
    log_raw "--- IP Addresses ---"
    if command -v ip &>/dev/null; then
        ip addr show 2>/dev/null | grep 'inet ' | awk '{print "  " $2}' >> "$REPORT_FILE" || true
    else
        ifconfig 2>/dev/null | grep 'inet ' | awk '{print "  " $2}' >> "$REPORT_FILE" || true
    fi

    log_raw ""
    log_raw "--- OS Version ---"
    cat /etc/os-release 2>/dev/null >> "$REPORT_FILE" || uname -a >> "$REPORT_FILE" 2>/dev/null || true
    log_raw "Kernel: $(uname -r 2>/dev/null || echo UNKNOWN)"

    log_info "OS information collected"
}

# -----------------------------------------------------------------------
# Oracle Environment
# -----------------------------------------------------------------------
collect_oracle_env() {
    log_section "Oracle Environment"
    log_raw ""
    log_raw "### ORACLE ENVIRONMENT ###"

    detect_oracle_env

    log_raw "ORACLE_HOME   : ${ORACLE_HOME:-NOT DETECTED}"
    log_raw "ORACLE_SID    : ${ORACLE_SID:-NOT DETECTED}"
    log_raw "ORACLE_BASE   : ${ORACLE_BASE:-NOT DETECTED}"

    if [ -n "${ORACLE_HOME:-}" ]; then
        log_raw "Oracle version: $("${ORACLE_HOME}/bin/sqlplus" -V 2>/dev/null | head -1 || echo UNKNOWN)"
        log_raw ""
        log_raw "--- /etc/oratab ---"
        cat /etc/oratab 2>/dev/null >> "$REPORT_FILE" || log_raw "(not found)"
    else
        log_warn "ORACLE_HOME not detected"
        log_raw "WARNING: ORACLE_HOME not detected"
    fi

    log_info "Oracle environment collected"
}

# -----------------------------------------------------------------------
# Database Configuration
# -----------------------------------------------------------------------
collect_db_config() {
    log_section "Database Configuration"
    log_raw ""
    log_raw "### DATABASE CONFIGURATION ###"

    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        log_raw "SKIPPED: Oracle environment not available"; return
    fi

    log_raw ""
    log_raw "--- Core Database Parameters ---"
    run_sql "
SELECT 'DB_NAME        : ' || NAME FROM V\$DATABASE;
SELECT 'DB_UNIQUE_NAME : ' || DB_UNIQUE_NAME FROM V\$DATABASE;
SELECT 'DB_ROLE        : ' || DATABASE_ROLE FROM V\$DATABASE;
SELECT 'OPEN_MODE      : ' || OPEN_MODE FROM V\$DATABASE;
SELECT 'LOG_MODE       : ' || LOG_MODE FROM V\$DATABASE;
SELECT 'PLATFORM       : ' || PLATFORM_NAME FROM V\$DATABASE;
SELECT 'CREATED        : ' || TO_CHAR(CREATED,'YYYY-MM-DD HH24:MI:SS') FROM V\$DATABASE;
" >> "$REPORT_FILE" 2>&1 || log_raw "ERROR: Could not query V\$DATABASE"

    log_raw ""
    log_raw "--- Character Sets ---"
    run_sql "
SELECT 'DB_CHARSET : ' || VALUE FROM NLS_DATABASE_PARAMETERS WHERE PARAMETER='NLS_CHARACTERSET';
SELECT 'NCHAR      : ' || VALUE FROM NLS_DATABASE_PARAMETERS WHERE PARAMETER='NLS_NCHAR_CHARACTERSET';
" >> "$REPORT_FILE" 2>&1 || true

    log_raw ""
    log_raw "--- Available Storage ---"
    run_sql "
SELECT TABLESPACE_NAME,
       ROUND(SUM(BYTES)/1024/1024/1024,2) AS CURRENT_GB,
       ROUND(SUM(MAXBYTES)/1024/1024/1024,2) AS MAX_GB,
       MAX(AUTOEXTENSIBLE) AS AUTOEXTEND
FROM DBA_DATA_FILES
GROUP BY TABLESPACE_NAME
UNION ALL
SELECT TABLESPACE_NAME,
       ROUND(SUM(BYTES)/1024/1024/1024,2),
       ROUND(SUM(MAXBYTES)/1024/1024/1024,2),
       MAX(AUTOEXTENSIBLE)
FROM DBA_TEMP_FILES
GROUP BY TABLESPACE_NAME
ORDER BY 1;
" >> "$REPORT_FILE" 2>&1 || true

    log_info "Database configuration collected"
}

# -----------------------------------------------------------------------
# Container Database (CDB/PDB)
# -----------------------------------------------------------------------
collect_cdb_info() {
    log_section "Container Database"
    log_raw ""
    log_raw "### CONTAINER DATABASE (CDB/PDB) ###"

    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        log_raw "SKIPPED: Oracle environment not available"; return
    fi

    run_sql "SELECT 'CDB: ' || CDB || '  CON_ID: ' || CON_ID FROM V\$DATABASE;" >> "$REPORT_FILE" 2>&1 || true

    log_raw ""
    log_raw "--- PDB List (Full Detail) ---"
    run_sql "
SELECT CON_ID, NAME, OPEN_MODE, RESTRICTED, GUID,
       TO_CHAR(CREATE_SCN) AS CREATION_SCN,
       TO_CHAR(OPEN_TIME,'YYYY-MM-DD HH24:MI:SS') AS OPEN_TIME
FROM V\$PDBS
ORDER BY CON_ID;
" >> "$REPORT_FILE" 2>&1 || log_raw "(not a CDB or V\$PDBS not accessible)"

    log_raw ""
    log_raw "--- PDB Storage Limits ---"
    run_sql "
SELECT CON_ID, CON_NAME, MAX_SIZE, MAX_SHARED_TEMP_SIZE
FROM DBA_PDBS
ORDER BY CON_ID;
" >> "$REPORT_FILE" 2>&1 || true

    log_info "CDB/PDB information collected"
}

# -----------------------------------------------------------------------
# TDE / Wallet Status
# -----------------------------------------------------------------------
collect_tde_info() {
    log_section "TDE Configuration"
    log_raw ""
    log_raw "### TDE / WALLET STATUS ###"

    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        log_raw "SKIPPED: Oracle environment not available"; return
    fi

    run_sql "
SELECT WRL_TYPE, WRL_PARAMETER, STATUS, WALLET_TYPE, CON_ID
FROM V\$ENCRYPTION_WALLET
ORDER BY CON_ID;
" >> "$REPORT_FILE" 2>&1 || log_raw "(V\$ENCRYPTION_WALLET not accessible)"

    log_info "TDE information collected"
}

# -----------------------------------------------------------------------
# Network Configuration
# -----------------------------------------------------------------------
collect_network_config() {
    log_section "Network Configuration"
    log_raw ""
    log_raw "### NETWORK CONFIGURATION ###"

    if [ -n "${ORACLE_HOME:-}" ]; then
        log_raw ""
        log_raw "--- Listener Status ---"
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            "${ORACLE_HOME}/bin/lsnrctl" status 2>&1 >> "$REPORT_FILE" || log_raw "(lsnrctl failed)"
        else
            sudo -u "$ORACLE_USER" -E ORACLE_HOME="$ORACLE_HOME" "${ORACLE_HOME}/bin/lsnrctl" status 2>&1 >> "$REPORT_FILE" || log_raw "(lsnrctl failed)"
        fi

        log_raw ""
        log_raw "--- SCAN Listener Status (if RAC) ---"
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            "${ORACLE_HOME}/bin/lsnrctl" status LISTENER_SCAN1 2>&1 >> "$REPORT_FILE" || log_raw "(no SCAN listener found)"
        else
            sudo -u "$ORACLE_USER" -E ORACLE_HOME="$ORACLE_HOME" "${ORACLE_HOME}/bin/lsnrctl" status LISTENER_SCAN1 2>&1 >> "$REPORT_FILE" || log_raw "(no SCAN listener found)"
        fi

        log_raw ""
        log_raw "--- tnsnames.ora ---"
        local tns="${ORACLE_HOME}/network/admin/tnsnames.ora"
        [ -f "$tns" ] && cat "$tns" >> "$REPORT_FILE" 2>/dev/null || log_raw "(not found)"

        log_raw ""
        log_raw "--- sqlnet.ora ---"
        local sqlnet="${ORACLE_HOME}/network/admin/sqlnet.ora"
        [ -f "$sqlnet" ] && cat "$sqlnet" >> "$REPORT_FILE" 2>/dev/null || log_raw "(not found)"
    fi

    log_raw ""
    log_raw "--- Firewall / iptables Rules ---"
    if command -v firewall-cmd &>/dev/null; then
        sudo firewall-cmd --list-all 2>/dev/null >> "$REPORT_FILE" || log_raw "(firewall-cmd failed)"
    elif command -v iptables &>/dev/null; then
        sudo iptables -L -n 2>/dev/null | grep -E '1521|2484|22|oracle' >> "$REPORT_FILE" || log_raw "(iptables query failed)"
    else
        log_raw "(no firewall tool found)"
    fi

    log_raw ""
    log_raw "--- OCI Network Security Groups (via OCI CLI) ---"
    if command -v oci &>/dev/null; then
        oci network nsg list 2>/dev/null | head -50 >> "$REPORT_FILE" || log_raw "(OCI CLI query failed or no NSGs)"
    else
        log_raw "(OCI CLI not available)"
    fi

    log_info "Network configuration collected"
}

# -----------------------------------------------------------------------
# OCI / Azure Integration
# -----------------------------------------------------------------------
collect_oci_azure_info() {
    log_section "OCI / Azure Integration"
    log_raw ""
    log_raw "### OCI / AZURE INTEGRATION ###"

    log_raw ""
    log_raw "--- OCI CLI Version ---"
    if command -v oci &>/dev/null; then
        oci --version 2>/dev/null >> "$REPORT_FILE" || log_raw "(oci --version failed)"
    else
        log_raw "(OCI CLI not found)"
    fi

    log_raw ""
    log_raw "--- OCI Config File ---"
    local oci_config="${OCI_CONFIG_PATH:-~/.oci/config}"
    local oci_config_expanded
    oci_config_expanded=$(eval echo "$oci_config")
    if [ -f "$oci_config_expanded" ]; then
        # Mask sensitive fields
        sed 's/\(key_file\|fingerprint\|tenancy\|user\).*/\1 = ***MASKED***/' "$oci_config_expanded" >> "$REPORT_FILE" 2>/dev/null || true
    else
        log_raw "(OCI config not found at $oci_config_expanded)"
    fi

    log_raw ""
    log_raw "--- OCI Connectivity Test ---"
    if command -v oci &>/dev/null; then
        oci iam region list 2>&1 | head -10 >> "$REPORT_FILE" || log_raw "(OCI connectivity test failed)"
    else
        log_raw "(OCI CLI not available)"
    fi

    log_raw ""
    log_raw "--- OCI Instance Metadata ---"
    if command -v curl &>/dev/null; then
        curl -sf -H "Authorization: Bearer Oracle" \
            http://169.254.169.254/opc/v2/instance/ 2>/dev/null | \
            python3 -m json.tool 2>/dev/null | head -30 >> "$REPORT_FILE" || \
            log_raw "(OCI instance metadata not available)"
    fi

    log_raw ""
    log_raw "--- Azure Instance Metadata ---"
    if command -v curl &>/dev/null; then
        curl -sf -H "Metadata: true" \
            "http://169.254.169.254/metadata/instance?api-version=2021-02-01" 2>/dev/null | \
            python3 -m json.tool 2>/dev/null | head -30 >> "$REPORT_FILE" || \
            log_raw "(Azure instance metadata not available)"
    fi

    log_info "OCI/Azure integration info collected"
}

# -----------------------------------------------------------------------
# Grid Infrastructure (RAC)
# -----------------------------------------------------------------------
collect_grid_info() {
    log_section "Grid Infrastructure"
    log_raw ""
    log_raw "### GRID INFRASTRUCTURE ###"

    local grid_home
    # Try to find Grid home
    for p in /u01/app/grid /u01/app/*/grid /u01/app/grid/product/*/grid_home; do
        if [ -d "$p" ] && [ -f "$p/bin/crsctl" ]; then
            grid_home="$p"; break
        fi
    done

    if [ -n "$grid_home" ]; then
        log_raw "Grid Home: $grid_home"
        log_raw ""
        log_raw "--- CRS Status ---"
        sudo "$grid_home/bin/crsctl" status res -t 2>/dev/null >> "$REPORT_FILE" || log_raw "(crsctl failed)"

        log_raw ""
        log_raw "--- Cluster Nodes ---"
        sudo "$grid_home/bin/olsnodes" -n 2>/dev/null >> "$REPORT_FILE" || log_raw "(olsnodes failed)"
    else
        log_raw "(No Grid Infrastructure detected - single-instance deployment)"
    fi

    log_info "Grid infrastructure info collected"
}

# -----------------------------------------------------------------------
# Authentication
# -----------------------------------------------------------------------
collect_auth_info() {
    log_section "Authentication"
    log_raw ""
    log_raw "### AUTHENTICATION ###"

    log_raw ""
    log_raw "--- SSH Directory (oracle user) ---"
    if [ "$(whoami)" = "$ORACLE_USER" ]; then
        ls -la ~/.ssh/ 2>/dev/null >> "$REPORT_FILE" || log_raw "(~/.ssh not found for oracle)"
    else
        sudo -u "$ORACLE_USER" bash -c 'ls -la ~/.ssh/ 2>/dev/null' >> "$REPORT_FILE" 2>&1 || log_raw "(~/.ssh not accessible for oracle)"
    fi

    log_raw ""
    log_raw "--- Current User SSH Directory ---"
    ls -la ~/.ssh/ 2>/dev/null >> "$REPORT_FILE" || log_raw "(~/.ssh not found for current user)"

    log_info "Authentication info collected"
}

# -----------------------------------------------------------------------
# Exadata / Storage Capacity
# -----------------------------------------------------------------------
collect_storage_info() {
    log_section "Exadata / Storage Capacity"
    log_raw ""
    log_raw "### EXADATA / STORAGE CAPACITY ###"

    log_raw ""
    log_raw "--- ASM Disk Groups ---"
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        run_sql "
SELECT GROUP_NUMBER, NAME, TYPE, STATE,
       ROUND(TOTAL_MB/1024,2) AS TOTAL_GB,
       ROUND(FREE_MB/1024,2) AS FREE_GB,
       ROUND((TOTAL_MB - FREE_MB)/1024,2) AS USED_GB
FROM V\$ASM_DISKGROUP
ORDER BY NAME;
" >> "$REPORT_FILE" 2>&1 || log_raw "(V\$ASM_DISKGROUP not accessible - may not be ASM instance)"
    fi

    log_raw ""
    log_raw "--- asmcmd lsdg (if available) ---"
    if command -v asmcmd &>/dev/null; then
        sudo -u "$ORACLE_USER" asmcmd lsdg 2>/dev/null >> "$REPORT_FILE" || log_raw "(asmcmd not available)"
    elif [ -n "${ORACLE_HOME:-}" ] && [ -f "${ORACLE_HOME}/bin/asmcmd" ]; then
        sudo -u "$ORACLE_USER" -E ORACLE_HOME="$ORACLE_HOME" \
            "${ORACLE_HOME}/bin/asmcmd" lsdg 2>/dev/null >> "$REPORT_FILE" || log_raw "(asmcmd failed)"
    else
        log_raw "(asmcmd not found)"
    fi

    log_raw ""
    log_raw "--- OS Filesystem Space ---"
    df -h 2>/dev/null >> "$REPORT_FILE" || true

    log_info "Storage capacity info collected"
}

# -----------------------------------------------------------------------
# JSON Summary
# -----------------------------------------------------------------------
write_json_summary() {
    log_section "Writing JSON Summary"
    local db_name db_version cdb_status tde_status
    local hostname_f; hostname_f=$(hostname -f 2>/dev/null || hostname)

    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        db_name=$(run_sql_value "SELECT NAME FROM V\$DATABASE;")
        db_version=$(run_sql_value "SELECT VERSION FROM V\$INSTANCE;")
        cdb_status=$(run_sql_value "SELECT CDB FROM V\$DATABASE;")
        tde_status=$(run_sql_value "SELECT STATUS FROM V\$ENCRYPTION_WALLET WHERE ROWNUM=1;" 2>/dev/null || echo "UNKNOWN")
    else
        db_name="UNKNOWN"; db_version="UNKNOWN"; cdb_status="UNKNOWN"; tde_status="UNKNOWN"
    fi

    local oci_cli_ver="NOT_FOUND"
    command -v oci &>/dev/null && oci_cli_ver=$(oci --version 2>/dev/null | head -1 || echo "ERROR")

    cat > "$JSON_FILE" <<ENDJSON
{
  "discovery_type": "target",
  "project": "ORADB",
  "hostname": "${hostname_f}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "oracle": {
    "sid": "${ORACLE_SID:-UNKNOWN}",
    "home": "${ORACLE_HOME:-UNKNOWN}",
    "version": "${db_version}",
    "db_name": "${db_name}",
    "cdb": "${cdb_status}",
    "tde_status": "${tde_status}"
  },
  "oci_cli_version": "${oci_cli_ver}",
  "report_file": "$(basename "$REPORT_FILE")"
}
ENDJSON

    log_info "JSON summary written to $JSON_FILE"
}

# -----------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------
main() {
    > "$REPORT_FILE"

    write_header
    collect_os_info
    collect_oracle_env
    collect_db_config
    collect_cdb_info
    collect_tde_info
    collect_network_config
    collect_oci_azure_info
    collect_grid_info
    collect_auth_info
    collect_storage_info

    log_raw ""
    log_raw "========================================================================"
    log_raw "  Discovery completed: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    log_raw "========================================================================"

    write_json_summary

    log_section "Discovery Complete"
    log_info "Text report : $REPORT_FILE"
    log_info "JSON summary: $JSON_FILE"
    log_info "Orchestration script will collect these files."
}

main "$@"
