#!/bin/bash
# =============================================================================
# zdm_target_discovery.sh
# Phase 10 â€” ZDM Migration Â· Step 2: Target Database Discovery
#
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration
#
# Discovers Oracle environment, database configuration, TDE, network, OCI/Azure
# integration, Grid Infrastructure, Exadata storage, pre-configured PDBs, and
# NSG rules on the TARGET Oracle Database@Azure server.
#
# Executed via SSH from the ZDM orchestration script.
# SSH as TARGET_ADMIN_USER (e.g., opc), SQL via sudo -u oracle.
#
# Outputs (written to current working directory):
#   zdm_target_discovery_<hostname>_<timestamp>.txt
#   zdm_target_discovery_<hostname>_<timestamp>.json
#
# Usage:
#   chmod +x zdm_target_discovery.sh
#   ./zdm_target_discovery.sh
#
# Run as: TARGET_ADMIN_USER on the Oracle Database@Azure server
#         (SQL commands automatically escalate to oracle via sudo)
# =============================================================================

# Do NOT use set -e globally â€” individual sections handle their own errors
set -uo pipefail

# ---------------------------------------------------------------------------
# Configuration overrides (set by orchestration script or environment)
# ---------------------------------------------------------------------------
ORACLE_USER="${ORACLE_USER:-oracle}"
ORACLE_HOME="${ORACLE_HOME:-}"
ORACLE_SID="${ORACLE_SID:-}"
ORACLE_BASE="${ORACLE_BASE:-}"

# Accept explicit overrides from orchestration script
[ -n "${TARGET_REMOTE_ORACLE_HOME:-}" ] && ORACLE_HOME="$TARGET_REMOTE_ORACLE_HOME"
[ -n "${TARGET_REMOTE_ORACLE_SID:-}"  ] && ORACLE_SID="$TARGET_REMOTE_ORACLE_SID"

# OCI configuration
OCI_CONFIG_PATH="${OCI_CONFIG_PATH:-~/.oci/config}"
OCI_COMPARTMENT_OCID="${OCI_COMPARTMENT_OCID:-}"

# ---------------------------------------------------------------------------
# Output paths (write to current working directory)
# ---------------------------------------------------------------------------
HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_TXT="./zdm_target_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
REPORT_JSON="./zdm_target_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log_raw() { echo "$1" | tee -a "$REPORT_TXT"; }
log_info() { echo "[INFO]  $1" | tee -a "$REPORT_TXT"; }
log_warn() { echo "[WARN]  $1" | tee -a "$REPORT_TXT"; }
log_error() { echo "[ERROR] $1" | tee -a "$REPORT_TXT"; }
log_section() {
    log_raw ""
    log_raw "============================================================"
    log_raw "  $1"
    log_raw "============================================================"
}

# ---------------------------------------------------------------------------
# Auto-detect Oracle environment
# ---------------------------------------------------------------------------
detect_oracle_env() {
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        return 0
    fi

    # Method 1: Parse /etc/oratab
    if [ -f /etc/oratab ]; then
        local oratab_entry
        if [ -n "${ORACLE_SID:-}" ]; then
            oratab_entry=$(grep "^${ORACLE_SID}:" /etc/oratab 2>/dev/null | head -1)
        else
            oratab_entry=$(grep -v '^#' /etc/oratab | grep -v '^$' | head -1)
        fi
        if [ -n "$oratab_entry" ]; then
            ORACLE_SID="${ORACLE_SID:-$(echo "$oratab_entry" | cut -d: -f1)}"
            ORACLE_HOME="${ORACLE_HOME:-$(echo "$oratab_entry" | cut -d: -f2)}"
        fi
    fi

    # Method 2: Running pmon process
    if [ -z "${ORACLE_SID:-}" ]; then
        local pmon_sid
        pmon_sid=$(ps -ef | grep 'ora_pmon_' | grep -v grep | head -1 | sed 's/.*ora_pmon_//')
        [ -n "$pmon_sid" ] && ORACLE_SID="$pmon_sid"
    fi

    # Method 3: Common installation paths
    if [ -z "${ORACLE_HOME:-}" ]; then
        for path in /u01/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1 /u02/app/oracle/product/*/dbhome_1; do
            if [ -d "$path" ] && [ -f "$path/bin/sqlplus" ]; then
                ORACLE_HOME="$path"
                break
            fi
        done
    fi

    # Method 4: Derive ORACLE_BASE
    if [ -n "${ORACLE_HOME:-}" ] && [ -z "${ORACLE_BASE:-}" ]; then
        ORACLE_BASE="$(echo "$ORACLE_HOME" | sed 's|/product/.*||')"
    fi
}

# ---------------------------------------------------------------------------
# SQL execution helper
# ---------------------------------------------------------------------------
run_sql() {
    local sql_query="$1"
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        local sqlplus_cmd="$ORACLE_HOME/bin/sqlplus -s / as sysdba"
        local sql_script
        sql_script=$(printf 'SET PAGESIZE 1000\nSET LINESIZE 200\nSET FEEDBACK OFF\nSET HEADING ON\nSET ECHO OFF\n%s\n' "$sql_query")
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            echo "$sql_script" | $sqlplus_cmd 2>&1
        else
            echo "$sql_script" | sudo -u "$ORACLE_USER" -E ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd 2>&1
        fi
    else
        echo "SKIPPED: ORACLE_HOME or ORACLE_SID not set"
    fi
}

run_sql_value() {
    local sql_query="$1"
    run_sql "SET PAGESIZE 0
SET FEEDBACK OFF
SET HEADING OFF
SET ECHO OFF
SET TRIMSPOOL ON
$sql_query" 2>/dev/null | grep -v '^$' | head -1
}

# ============================================================================
# MAIN
# ============================================================================
: > "$REPORT_TXT"

log_raw "============================================================"
log_raw "  ZDM Step 2 â€” Target Database Discovery (Oracle DB@Azure)"
log_raw "  Generated : $(date)"
log_raw "  Run by    : $(whoami)@$(hostname)"
log_raw "============================================================"

# ============================================================================
# 1. OS INFORMATION
# ============================================================================
log_section "1. OS INFORMATION"

OS_HOSTNAME="$(hostname -f 2>/dev/null || hostname)"
OS_SHORT="$(hostname -s 2>/dev/null || hostname)"
log_info "Hostname (FQDN)    : $OS_HOSTNAME"
log_info "Hostname (short)   : $OS_SHORT"

OS_IP_ADDRS="$(ip addr show 2>/dev/null | grep 'inet ' | awk '{print $2}' | tr '\n' ' ')"
log_info "IP Addresses       : $OS_IP_ADDRS"

OS_VERSION="$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"' || uname -r)"
log_info "OS Version         : $OS_VERSION"
log_info "Current User       : $(whoami)"

# ============================================================================
# 2. ORACLE ENVIRONMENT DETECTION
# ============================================================================
log_section "2. ORACLE ENVIRONMENT"

detect_oracle_env

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    log_info "ORACLE_HOME : $ORACLE_HOME"
    log_info "ORACLE_SID  : $ORACLE_SID"
    log_info "ORACLE_BASE : ${ORACLE_BASE:-}"

    ORA_VERSION="$(run_sql_value "SELECT version FROM v\$instance;")"
    log_info "Oracle Version : $ORA_VERSION"
else
    log_warn "ORACLE_HOME or ORACLE_SID could not be auto-detected."
    log_warn "Set TARGET_REMOTE_ORACLE_HOME and TARGET_REMOTE_ORACLE_SID env vars to override."
    ORA_VERSION="UNDETERMINED"
fi

# ============================================================================
# 3. DATABASE CONFIGURATION
# ============================================================================
log_section "3. DATABASE CONFIGURATION"

{
    DB_NAME="$(run_sql_value "SELECT name FROM v\$database;")"
    DB_UNIQUE_NAME="$(run_sql_value "SELECT db_unique_name FROM v\$database;")"
    DB_ROLE="$(run_sql_value "SELECT database_role FROM v\$database;")"
    DB_OPEN_MODE="$(run_sql_value "SELECT open_mode FROM v\$database;")"
    DB_CHARSET="$(run_sql_value "SELECT value FROM nls_database_parameters WHERE parameter='NLS_CHARACTERSET';")"

    log_info "DB Name        : $DB_NAME"
    log_info "DB Unique Name : $DB_UNIQUE_NAME"
    log_info "Role           : $DB_ROLE"
    log_info "Open Mode      : $DB_OPEN_MODE"
    log_info "Character Set  : $DB_CHARSET"

    log_raw ""
    log_info "--- Available Tablespace Storage ---"
    run_sql "SELECT ts.tablespace_name, ts.contents,
    ROUND(NVL(df.total_mb,0),0) AS total_mb,
    ROUND(NVL(fr.free_mb,0),0) AS free_mb,
    ROUND((1 - NVL(fr.free_mb,0)/NULLIF(NVL(df.total_mb,0),0))*100,1) AS pct_used
FROM dba_tablespaces ts
LEFT JOIN (SELECT tablespace_name, SUM(bytes)/1048576 total_mb FROM dba_data_files GROUP BY tablespace_name) df
    ON ts.tablespace_name=df.tablespace_name
LEFT JOIN (SELECT tablespace_name, SUM(bytes)/1048576 free_mb FROM dba_free_space GROUP BY tablespace_name) fr
    ON ts.tablespace_name=fr.tablespace_name
ORDER BY ts.tablespace_name;" | tee -a "$REPORT_TXT"
} || log_warn "Database configuration discovery failed"

# ============================================================================
# 4. CONTAINER DATABASE (CDB) STATUS
# ============================================================================
log_section "4. CONTAINER DATABASE (CDB) STATUS"

{
    CDB_STATUS="$(run_sql_value "SELECT cdb FROM v\$database;")"
    log_info "CDB : $CDB_STATUS"

    if [ "$CDB_STATUS" = "YES" ]; then
        log_raw ""
        log_info "--- PDBs (including creation SCN, restricted, open mode) ---"
        run_sql "SELECT con_id, name, open_mode, restricted, creation_scn
FROM v\$pdbs ORDER BY con_id;" | tee -a "$REPORT_TXT"
    fi
} || log_warn "CDB status discovery failed"

# ============================================================================
# 5. TDE WALLET STATUS
# ============================================================================
log_section "5. TDE WALLET STATUS"

{
    run_sql "SELECT wrl_type, wrl_parameter, status, wallet_type FROM v\$encryption_wallet;" | tee -a "$REPORT_TXT"
    TDE_WALLET_STATUS="$(run_sql_value "SELECT status FROM v\$encryption_wallet WHERE rownum=1;")"
    TDE_WALLET_TYPE="$(run_sql_value "SELECT wallet_type FROM v\$encryption_wallet WHERE rownum=1;")"
} || log_warn "TDE wallet discovery failed"

# ============================================================================
# 6. NETWORK CONFIGURATION
# ============================================================================
log_section "6. NETWORK CONFIGURATION"

{
    log_info "--- Listener Status ---"
    lsnrctl status 2>&1 | tee -a "$REPORT_TXT" || log_warn "lsnrctl status failed"

    # SCAN listener (RAC)
    log_raw ""
    log_info "--- SCAN Listener (RAC) ---"
    lsnrctl status LISTENER_SCAN1 2>&1 | head -30 | tee -a "$REPORT_TXT" || log_info "SCAN listener not found (non-RAC environment)"

    log_raw ""
    log_info "--- tnsnames.ora ---"
    TNS_ADMIN="${TNS_ADMIN:-${ORACLE_HOME:-}/network/admin}"
    if [ -f "$TNS_ADMIN/tnsnames.ora" ]; then
        cat "$TNS_ADMIN/tnsnames.ora" 2>/dev/null | tee -a "$REPORT_TXT"
    else
        log_warn "tnsnames.ora not found at $TNS_ADMIN/tnsnames.ora"
    fi
} || log_warn "Network configuration discovery failed"

# ============================================================================
# 7. OCI / AZURE INTEGRATION
# ============================================================================
log_section "7. OCI / AZURE INTEGRATION"

{
    log_info "--- OCI CLI Version ---"
    oci --version 2>&1 | tee -a "$REPORT_TXT" || log_warn "OCI CLI not found"

    log_raw ""
    log_info "--- OCI Config File (masked) ---"
    OCI_CONFIG_EXP="${OCI_CONFIG_PATH/#\~/$HOME}"
    if [ -f "$OCI_CONFIG_EXP" ]; then
        # Mask sensitive key_file path value and fingerprint partially
        sed 's/\(key_file\s*=\s*\).*/\1<MASKED>/' "$OCI_CONFIG_EXP" | tee -a "$REPORT_TXT"
    else
        log_warn "OCI config file not found at $OCI_CONFIG_EXP"
    fi

    log_raw ""
    log_info "--- OCI Connectivity Test ---"
    if command -v oci >/dev/null 2>&1; then
        oci iam user get --user-id "${OCI_USER_OCID:-notset}" --config-file "$OCI_CONFIG_EXP" 2>&1 | head -5 | tee -a "$REPORT_TXT" || log_warn "OCI connectivity test failed (check config and OCID)"
    fi

    log_raw ""
    log_info "--- Azure/OCI Instance Metadata ---"
    curl -s -m 5 http://169.254.169.254/opc/v2/instance/ 2>/dev/null | head -30 | tee -a "$REPORT_TXT" || \
        curl -s -m 5 -H "Metadata:true" "http://169.254.169.254/metadata/instance?api-version=2021-02-01&format=text" 2>/dev/null | head -30 | tee -a "$REPORT_TXT" || \
        log_warn "Instance metadata endpoint not reachable"
} || log_warn "OCI/Azure integration discovery failed"

# ============================================================================
# 8. GRID INFRASTRUCTURE (RAC)
# ============================================================================
log_section "8. GRID INFRASTRUCTURE (RAC)"

{
    log_info "--- CRS Status ---"
    if command -v crsctl >/dev/null 2>&1; then
        crsctl check cluster -all 2>&1 | tee -a "$REPORT_TXT" || log_warn "crsctl check cluster failed"
    else
        sudo su - oracle -c "which crsctl" 2>/dev/null && \
            sudo su - oracle -c "crsctl check cluster -all" 2>&1 | tee -a "$REPORT_TXT" || \
            log_info "CRS not found â€” likely single-instance database"
    fi
} || log_warn "Grid Infrastructure discovery failed"

# ============================================================================
# 9. EXADATA / ASM STORAGE CAPACITY
# ============================================================================
log_section "9. EXADATA / ASM STORAGE CAPACITY"

{
    log_info "--- ASM Disk Groups ---"
    if command -v asmcmd >/dev/null 2>&1 || sudo -u "$ORACLE_USER" -E ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="+ASM" which asmcmd 2>/dev/null; then
        sudo -u "$ORACLE_USER" -E ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="+ASM1" \
            "$ORACLE_HOME/bin/asmcmd" lsdg 2>&1 | tee -a "$REPORT_TXT" || \
        log_info "ASMCMD lsdg not accessible â€” trying SQL query on ASM"
    fi

    log_raw ""
    log_info "--- ASM Disk Groups via SQL ---"
    run_sql "SELECT group_number, name, type, total_mb, free_mb, usable_file_mb, state
FROM v\$asm_diskgroup
ORDER BY name;" | tee -a "$REPORT_TXT" || log_info "v\$asm_diskgroup not accessible (may need ASM instance connection)"

    log_raw ""
    log_info "--- Exadata Cell Storage (if accessible) ---"
    if command -v cellcli >/dev/null 2>&1; then
        cellcli -e "list celldisk attributes name, errorcount, freeSpace, size" 2>&1 | head -40 | tee -a "$REPORT_TXT"
    else
        log_info "cellcli not accessible from this node"
    fi

    ASM_FREE="$(run_sql_value "SELECT ROUND(SUM(usable_file_mb)/1024,1) FROM v\$asm_diskgroup WHERE name='DATA';")"
    log_info "Estimated ASM DATA free (GB): ${ASM_FREE:-UNDETERMINED}"
} || log_warn "Exadata/ASM storage discovery failed"

# ============================================================================
# 10. PRE-CONFIGURED PDBs (Full Detail)
# ============================================================================
log_section "10. PRE-CONFIGURED PDBs"

{
    run_sql "SELECT con_id, name, open_mode, restricted, creation_scn,
    ROUND(NVL(max_size,0)/1073741824,2) AS max_size_gb
FROM v\$pdbs
ORDER BY con_id;" | tee -a "$REPORT_TXT"

    PDB_COUNT="$(run_sql_value "SELECT COUNT(*) FROM v\$pdbs WHERE name NOT LIKE '%\$%';")"
    log_info "Total PDBs (non-system): $PDB_COUNT"
} || log_warn "PDB discovery failed"

# ============================================================================
# 11. NETWORK SECURITY GROUP / FIREWALL RULES
# ============================================================================
log_section "11. NETWORK SECURITY / FIREWALL RULES"

{
    log_info "--- iptables Rules (Oracle ports) ---"
    sudo iptables -L -n 2>/dev/null | grep -E '1521|2484|22|ACCEPT|DROP|REJECT' | head -40 | tee -a "$REPORT_TXT" || \
        log_info "iptables not accessible (may use firewalld)"

    log_raw ""
    log_info "--- firewalld Status ---"
    sudo firewall-cmd --list-all 2>/dev/null | head -30 | tee -a "$REPORT_TXT" || log_info "firewalld not active"

    log_raw ""
    log_info "--- OCI NSG Rules (if OCI CLI available) ---"
    if command -v oci >/dev/null 2>&1 && [ -n "${OCI_COMPARTMENT_OCID:-}" ]; then
        oci network nsg list --compartment-id "$OCI_COMPARTMENT_OCID" 2>&1 | head -40 | tee -a "$REPORT_TXT" || log_warn "OCI NSG list failed"
    else
        log_info "OCI_COMPARTMENT_OCID not set or OCI CLI not available â€” skipping OCI NSG list"
    fi

    log_raw ""
    log_info "--- Port Listening Status (1521, 2484, 22) ---"
    ss -tlnp 2>/dev/null | grep -E ':1521|:2484|:22' | tee -a "$REPORT_TXT" || \
        netstat -tlnp 2>/dev/null | grep -E ':1521|:2484|:22' | tee -a "$REPORT_TXT" || \
        log_warn "ss/netstat not accessible"
} || log_warn "Network security discovery failed"

# ============================================================================
# 12. SSH AUTHENTICATION
# ============================================================================
log_section "12. SSH AUTHENTICATION"

{
    log_info "--- SSH Directory Contents ---"
    ls -la ~/.ssh/ 2>/dev/null | tee -a "$REPORT_TXT" || log_warn "SSH directory listing failed"
} || log_warn "Authentication discovery failed"

# ============================================================================
# WRITE JSON SUMMARY
# ============================================================================
log_section "WRITING JSON SUMMARY"

{
cat > "$REPORT_JSON" <<JSON
{
  "report_type": "target_discovery",
  "generated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "run_by": "$(whoami)",
  "hostname": "$OS_HOSTNAME",
  "timestamp": "$TIMESTAMP",
  "oracle_environment": {
    "oracle_home": "${ORACLE_HOME:-UNDETERMINED}",
    "oracle_sid": "${ORACLE_SID:-UNDETERMINED}",
    "oracle_version": "${ORA_VERSION:-UNDETERMINED}",
    "oracle_user": "${ORACLE_USER}"
  },
  "database": {
    "db_name": "${DB_NAME:-UNDETERMINED}",
    "db_unique_name": "${DB_UNIQUE_NAME:-UNDETERMINED}",
    "role": "${DB_ROLE:-UNDETERMINED}",
    "open_mode": "${DB_OPEN_MODE:-UNDETERMINED}",
    "characterset": "${DB_CHARSET:-UNDETERMINED}",
    "is_cdb": "${CDB_STATUS:-UNDETERMINED}",
    "pdb_count": "${PDB_COUNT:-0}"
  },
  "tde": {
    "wallet_status": "${TDE_WALLET_STATUS:-UNDETERMINED}",
    "wallet_type": "${TDE_WALLET_TYPE:-UNDETERMINED}"
  },
  "storage": {
    "asm_data_free_gb": "${ASM_FREE:-UNDETERMINED}"
  },
  "output_files": {
    "text_report": "$REPORT_TXT",
    "json_summary": "$REPORT_JSON"
  }
}
JSON
    log_info "JSON summary written to: $REPORT_JSON"
} || log_warn "Failed to write JSON summary"

# ============================================================================
# COMPLETION
# ============================================================================
log_raw ""
log_raw "============================================================"
log_raw "  Target Discovery COMPLETE"
log_raw "  Text report : $REPORT_TXT"
log_raw "  JSON summary: $REPORT_JSON"
log_raw "  Completed   : $(date)"
log_raw "============================================================"

echo ""
echo "[DONE] Target discovery complete."
echo "  Text : $REPORT_TXT"
echo "  JSON : $REPORT_JSON"
