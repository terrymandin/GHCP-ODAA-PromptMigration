#!/bin/bash
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration
# =============================================================================
# zdm_target_discovery.sh
# ZDM Migration - Target Database Discovery Script (Oracle Database@Azure)
# Project: ORADB
#
# PURPOSE: Collects read-only diagnostic information from the target Oracle
#          Database@Azure server to validate readiness for ZDM migration.
#
# USAGE:   bash zdm_target_discovery.sh [options]
#          Options:
#            -h, --help     Show this help message
#            -v, --verbose  Enable verbose output
#
# OUTPUT:  ./zdm_target_discovery_<hostname>_<timestamp>.txt
#          ./zdm_target_discovery_<hostname>_<timestamp>.json
#
# NOTES:   - All operations are strictly READ-ONLY
#          - Script runs as SSH admin user (opc); SQL via sudo -u oracle
#          - Target is typically an Exadata or ODA on Oracle Database@Azure
# =============================================================================

set -u

# ---------------------------------------------------------------------------
# Colour / logging helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

VERBOSE=false
HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname)"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
REPORT_FILE="./zdm_target_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_target_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"
ERRORS=()
WARNINGS=()

log_raw()     { echo "$*" | tee -a "$REPORT_FILE"; }
log_info()    { echo -e "${GREEN}[INFO]${RESET}  $*" | tee -a "$REPORT_FILE"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*" | tee -a "$REPORT_FILE"; WARNINGS+=("$*"); }
log_error()   { echo -e "${RED}[ERROR]${RESET} $*" | tee -a "$REPORT_FILE"; ERRORS+=("$*"); }
log_section() { echo -e "\n${CYAN}${BOLD}=== $* ===${RESET}" | tee -a "$REPORT_FILE"; }
log_debug()   { $VERBOSE && echo -e "[DEBUG] $*" | tee -a "$REPORT_FILE"; }

show_help() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -v, --verbose  Enable verbose output"
    echo ""
    echo "Environment variable overrides:"
    echo "  ORACLE_HOME_OVERRIDE  Override auto-detected ORACLE_HOME"
    echo "  ORACLE_SID_OVERRIDE   Override auto-detected ORACLE_SID"
    echo "  ORACLE_USER           Oracle software owner (default: oracle)"
    exit 0
}

for arg in "$@"; do
    case "$arg" in
        -h|--help)    show_help ;;
        -v|--verbose) VERBOSE=true ;;
    esac
done

mkdir -p "$(dirname "$REPORT_FILE")" 2>/dev/null || true
{
    echo "# ZDM Target Database Discovery Report"
    echo "# Generated: $(date)"
    echo "# Host:      $(hostname)"
    echo "# User:      $(whoami)"
    echo "# Script:    zdm_target_discovery.sh"
    echo "# Project:   ORADB"
    echo "# -------------------------------------------------------"
} > "$REPORT_FILE"

log_info "Target discovery started at $(date)"
log_info "Report file: $REPORT_FILE"

ORACLE_USER="${ORACLE_USER:-oracle}"

# ---------------------------------------------------------------------------
# Auto-detect Oracle environment
# ---------------------------------------------------------------------------
detect_oracle_env() {
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        return 0
    fi
    log_info "Auto-detecting Oracle environment..."

    if [ -f /etc/oratab ]; then
        local oratab_entry=""
        if [ -n "${ORACLE_SID:-}" ]; then
            oratab_entry=$(grep "^${ORACLE_SID}:" /etc/oratab 2>/dev/null | head -1)
        else
            oratab_entry=$(grep -v '^#' /etc/oratab 2>/dev/null | grep -v '^$' | head -1)
        fi
        if [ -n "$oratab_entry" ]; then
            export ORACLE_SID="${ORACLE_SID:-$(echo "$oratab_entry" | cut -d: -f1)}"
            export ORACLE_HOME="${ORACLE_HOME:-$(echo "$oratab_entry" | cut -d: -f2)}"
            log_info "Oracle env from /etc/oratab: SID=$ORACLE_SID HOME=$ORACLE_HOME"
            return 0
        fi
    fi

    if [ -z "${ORACLE_SID:-}" ]; then
        local pmon_line
        pmon_line=$(ps -ef 2>/dev/null | grep 'ora_pmon_' | grep -v grep | head -1)
        [ -n "$pmon_line" ] && export ORACLE_SID="$(echo "$pmon_line" | sed 's/.*ora_pmon_//')"
    fi

    if [ -z "${ORACLE_HOME:-}" ]; then
        for path in /u01/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1 /oracle/product/*/dbhome_1; do
            if [ -d "$path" ] && [ -f "$path/bin/sqlplus" ]; then
                export ORACLE_HOME="$path"
                break
            fi
        done
    fi

    [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ] && \
        log_warn "Oracle auto-detect incomplete: HOME=${ORACLE_HOME:-UNSET} SID=${ORACLE_SID:-UNSET}"
}

detect_oracle_env
[ -n "${ORACLE_HOME_OVERRIDE:-}" ] && export ORACLE_HOME="$ORACLE_HOME_OVERRIDE"
[ -n "${ORACLE_SID_OVERRIDE:-}" ]  && export ORACLE_SID="$ORACLE_SID_OVERRIDE"
export ORACLE_HOME="${ORACLE_HOME:-}"
export ORACLE_SID="${ORACLE_SID:-}"
export PATH="$PATH:${ORACLE_HOME}/bin"

# ---------------------------------------------------------------------------
# SQL helpers
# ---------------------------------------------------------------------------
run_sql() {
    local sql_query="$1"
    [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ] && { echo "ERROR: ORACLE_HOME/SID not set"; return 1; }
    local sqlplus_cmd="${ORACLE_HOME}/bin/sqlplus -s / as sysdba"
    local sql_script
    sql_script=$(cat <<EOSQL
SET PAGESIZE 1000
SET LINESIZE 200
SET FEEDBACK OFF
SET HEADING ON
SET ECHO OFF
SET TRIMOUT ON
$sql_query
EXIT
EOSQL
    )
    if [ "$(whoami)" = "$ORACLE_USER" ]; then
        echo "$sql_script" | $sqlplus_cmd 2>&1
    else
        echo "$sql_script" | sudo -u "$ORACLE_USER" -E \
            ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" \
            $sqlplus_cmd 2>&1
    fi
}

run_sql_value() {
    run_sql "SET HEADING OFF
SET FEEDBACK OFF
$1" | grep -v '^$' | head -1 | xargs
}

declare -A JSON
JSON["timestamp"]="$(date -Iseconds 2>/dev/null || date)"
JSON["hostname"]="$HOSTNAME_SHORT"
JSON["project"]="ORADB"
JSON["script"]="zdm_target_discovery.sh"

# ---------------------------------------------------------------------------
# SECTION 1: OS Information
# ---------------------------------------------------------------------------
log_section "OS Information"
{
    log_raw "Hostname: $(hostname)"
    log_raw "IP addresses:"
    ip addr show 2>/dev/null | grep 'inet ' | awk '{print "  " $2}' | tee -a "$REPORT_FILE" || \
        ifconfig 2>/dev/null | grep 'inet ' | awk '{print "  " $2}' | tee -a "$REPORT_FILE"
    log_raw "OS version:"
    cat /etc/os-release 2>/dev/null | tee -a "$REPORT_FILE" || uname -a | tee -a "$REPORT_FILE"
    log_raw "Kernel: $(uname -r)"
} || log_error "OS information section failed"

# ---------------------------------------------------------------------------
# SECTION 2: Oracle Environment
# ---------------------------------------------------------------------------
log_section "Oracle Environment"
{
    log_raw "ORACLE_HOME: ${ORACLE_HOME:-NOT SET}"
    log_raw "ORACLE_SID:  ${ORACLE_SID:-NOT SET}"
    log_raw "ORACLE_BASE: ${ORACLE_BASE:-NOT SET}"
    [ -n "${ORACLE_HOME:-}" ] && "${ORACLE_HOME}/bin/sqlplus" -v 2>/dev/null | tee -a "$REPORT_FILE"
    log_raw "/etc/oratab:"
    cat /etc/oratab 2>/dev/null | tee -a "$REPORT_FILE" || log_warn "/etc/oratab not found"
} || log_error "Oracle environment section failed"

JSON["oracle_home"]="${ORACLE_HOME:-}"
JSON["oracle_sid"]="${ORACLE_SID:-}"

# ---------------------------------------------------------------------------
# SECTION 3: Database Configuration
# ---------------------------------------------------------------------------
log_section "Database Configuration"
{
    log_raw "--- Database Name and Unique Name ---"
    run_sql "SELECT name, db_unique_name FROM v\$database;" | tee -a "$REPORT_FILE"

    log_raw "--- Database Role and Open Mode ---"
    run_sql "SELECT database_role, open_mode, protection_mode FROM v\$database;" | tee -a "$REPORT_FILE"

    log_raw "--- Available Storage (Tablespaces) ---"
    run_sql "SELECT ts.tablespace_name, ts.status, ts.contents,
       ROUND(SUM(df.bytes)/1024/1024/1024,3)   AS current_gb,
       ROUND(SUM(DECODE(df.autoextensible,'YES',df.maxbytes,df.bytes))/1024/1024/1024,3) AS max_gb
FROM dba_tablespaces ts
JOIN dba_data_files df ON ts.tablespace_name = df.tablespace_name
GROUP BY ts.tablespace_name, ts.status, ts.contents
ORDER BY ts.tablespace_name;" | tee -a "$REPORT_FILE"

    log_raw "--- Character Sets ---"
    run_sql "SELECT parameter, value FROM nls_database_parameters WHERE parameter IN ('NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET');" | tee -a "$REPORT_FILE"

    log_raw "--- DB Version ---"
    run_sql "SELECT version FROM v\$instance;" | tee -a "$REPORT_FILE"
} || log_error "Database configuration section failed"

JSON["db_name"]="$(run_sql_value "SELECT name FROM v\$database;")"
JSON["db_version"]="$(run_sql_value "SELECT version FROM v\$instance;")"

# ---------------------------------------------------------------------------
# SECTION 4: Container Database (CDB/PDB)
# ---------------------------------------------------------------------------
log_section "Container Database (CDB/PDB)"
{
    run_sql "SELECT cdb, con_id FROM v\$database;" | tee -a "$REPORT_FILE"
    CDB_STATUS="$(run_sql_value "SELECT cdb FROM v\$database;")"
    JSON["is_cdb"]="$CDB_STATUS"
    if [ "$CDB_STATUS" = "YES" ]; then
        log_raw "--- Existing PDBs ---"
        run_sql "SELECT con_id, name, open_mode, restricted, creation_scn FROM v\$pdbs ORDER BY con_id;" | tee -a "$REPORT_FILE"
        log_raw "--- PDB Storage Limits ---"
        run_sql "SELECT pdb_name, max_size FROM cdb_pdbs WHERE max_size IS NOT NULL;" | tee -a "$REPORT_FILE" 2>/dev/null || \
            log_info "No PDB storage limits configured"
    fi
} || log_error "CDB/PDB section failed"

# ---------------------------------------------------------------------------
# SECTION 5: TDE Configuration
# ---------------------------------------------------------------------------
log_section "TDE / Wallet Status"
{
    run_sql "SELECT * FROM v\$encryption_wallet;" | tee -a "$REPORT_FILE"
} || log_error "TDE section failed"

# ---------------------------------------------------------------------------
# SECTION 6: Network Configuration
# ---------------------------------------------------------------------------
log_section "Network Configuration"
{
    log_raw "--- Listener Status ---"
    [ -n "${ORACLE_HOME:-}" ] && "${ORACLE_HOME}/bin/lsnrctl" status 2>&1 | tee -a "$REPORT_FILE" || \
        log_warn "lsnrctl status failed"

    log_raw "--- SCAN Listener (if RAC) ---"
    [ -n "${ORACLE_HOME:-}" ] && "${ORACLE_HOME}/bin/srvctl" status scan_listener 2>&1 | tee -a "$REPORT_FILE" || \
        log_info "srvctl not available (non-RAC or Grid not in path)"

    log_raw "--- tnsnames.ora ---"
    [ -n "${ORACLE_HOME:-}" ] && cat "${ORACLE_HOME}/network/admin/tnsnames.ora" 2>/dev/null | tee -a "$REPORT_FILE"

    log_raw "--- sqlnet.ora ---"
    [ -n "${ORACLE_HOME:-}" ] && cat "${ORACLE_HOME}/network/admin/sqlnet.ora" 2>/dev/null | tee -a "$REPORT_FILE"
} || log_error "Network section failed"

# ---------------------------------------------------------------------------
# SECTION 7: OCI / Azure Integration
# ---------------------------------------------------------------------------
log_section "OCI / Azure Integration"
{
    log_raw "--- OCI CLI Version ---"
    oci --version 2>&1 | tee -a "$REPORT_FILE" || log_warn "oci CLI not found"

    log_raw "--- OCI Config ---"
    cat ~/.oci/config 2>/dev/null | sed 's/key_file.*/key_file = [REDACTED]/' | tee -a "$REPORT_FILE" || \
        log_warn "~/.oci/config not found"

    log_raw "--- OCI Connectivity Test ---"
    oci iam region list 2>&1 | head -10 | tee -a "$REPORT_FILE" || log_warn "OCI connectivity test failed"

    log_raw "--- OCI Instance Metadata ---"
    curl -s -m 5 http://169.254.169.254/opc/v1/instance/ 2>/dev/null | tee -a "$REPORT_FILE" || \
        log_info "OCI instance metadata not available"

    log_raw "--- Azure Instance Metadata ---"
    curl -s -m 5 -H "Metadata: true" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" 2>/dev/null | tee -a "$REPORT_FILE" || \
        log_info "Azure instance metadata not available"
} || log_error "OCI/Azure integration section failed"

# ---------------------------------------------------------------------------
# SECTION 8: Grid Infrastructure (if RAC)
# ---------------------------------------------------------------------------
log_section "Grid Infrastructure (CRS status)"
{
    which crsctl &>/dev/null && crsctl check crs 2>&1 | tee -a "$REPORT_FILE" || \
        log_info "crsctl not found — likely non-RAC installation"
    which olsnodes &>/dev/null && olsnodes -n 2>&1 | tee -a "$REPORT_FILE" || true
} || log_error "Grid Infrastructure section failed"

# ---------------------------------------------------------------------------
# SECTION 9: Authentication
# ---------------------------------------------------------------------------
log_section "Authentication"
{
    log_raw "--- SSH directory for $(whoami) ---"
    ls -la ~/.ssh/ 2>/dev/null | tee -a "$REPORT_FILE" || log_warn "~/.ssh not found"

    log_raw "--- Oracle user SSH directory ---"
    local orahome
    orahome=$(getent passwd "$ORACLE_USER" 2>/dev/null | cut -d: -f6)
    [ -n "$orahome" ] && sudo -u "$ORACLE_USER" ls -la "${orahome}/.ssh/" 2>/dev/null | tee -a "$REPORT_FILE" || \
        log_info "Oracle .ssh not accessible (not a blocker)"
} || log_error "Authentication section failed"

# ---------------------------------------------------------------------------
# SECTION 10: Exadata / ASM Storage Capacity
# ---------------------------------------------------------------------------
log_section "Exadata / ASM Storage Capacity"
{
    log_raw "--- ASM Disk Groups ---"
    run_sql "SELECT group_number, name, state, type,
       ROUND(total_mb/1024,2) AS total_gb,
       ROUND(free_mb/1024,2)  AS free_gb,
       ROUND((total_mb-free_mb)*100.0/NULLIF(total_mb,0),1) AS pct_used
FROM v\$asm_diskgroup
ORDER BY name;" | tee -a "$REPORT_FILE" 2>/dev/null || log_info "v\$asm_diskgroup not accessible (may need ASM instance)"

    log_raw "--- asmcmd lsdg (disk group free space) ---"
    which asmcmd &>/dev/null && sudo -u "$ORACLE_USER" asmcmd lsdg 2>&1 | tee -a "$REPORT_FILE" || \
        log_info "asmcmd not available from this path"

    log_raw "--- cellcli (Exadata cells) ---"
    which cellcli &>/dev/null && sudo cellcli -e "list celldisk attributes name, freeSpace" 2>&1 | tee -a "$REPORT_FILE" || \
        log_info "cellcli not available (not an Exadata X-series cell)"
} || log_error "Exadata/ASM storage section failed"

# ---------------------------------------------------------------------------
# SECTION 11: Network Security Group / Firewall Rules
# ---------------------------------------------------------------------------
log_section "Network Security Group / Firewall Rules"
{
    log_raw "--- iptables rules (Oracle listener ports) ---"
    sudo iptables -L -n 2>/dev/null | grep -E '1521|2484|22' | tee -a "$REPORT_FILE" || \
        log_info "iptables not accessible or no matching rules"

    log_raw "--- firewalld status ---"
    sudo firewall-cmd --list-all 2>/dev/null | tee -a "$REPORT_FILE" || \
        log_info "firewalld not active"

    log_raw "--- OCI NSG Rules (via OCI CLI) ---"
    if command -v oci &>/dev/null && [ -n "${OCI_COMPARTMENT_OCID:-}" ]; then
        oci network nsg list --compartment-id "$OCI_COMPARTMENT_OCID" \
            --all 2>&1 | head -50 | tee -a "$REPORT_FILE"
    else
        log_info "OCI_COMPARTMENT_OCID not set or oci CLI unavailable — skipping NSG query"
    fi
} || log_error "NSG/Firewall section failed"

# ---------------------------------------------------------------------------
# Summary and JSON output
# ---------------------------------------------------------------------------
log_section "Discovery Summary"
log_raw "Errors:   ${#ERRORS[@]}"
for e in "${ERRORS[@]}"; do log_raw "  ERROR: $e"; done
log_raw "Warnings: ${#WARNINGS[@]}"
for w in "${WARNINGS[@]}"; do log_raw "  WARN:  $w"; done
log_raw "Completed at: $(date)"

JSON["error_count"]="${#ERRORS[@]}"
JSON["warning_count"]="${#WARNINGS[@]}"
JSON["completed_at"]="$(date -Iseconds 2>/dev/null || date)"

{
    echo "{"
    first=true
    for key in "${!JSON[@]}"; do
        val="${JSON[$key]}"
        val="${val//\\/\\\\}"
        val="${val//\"/\\\"}"
        val="${val//$'\n'/ }"
        $first || echo ","
        printf '  "%s": "%s"' "$key" "$val"
        first=false
    done
    echo ""
    echo "}"
} > "$JSON_FILE"

log_info "Target discovery complete."
log_info "  Text: $REPORT_FILE"
log_info "  JSON: $JSON_FILE"
