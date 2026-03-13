#!/bin/bash
# =============================================================================
# zdm_target_discovery.sh
# Phase 10 — ZDM Migration · Step 2: Target Database Discovery
#
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration
#
# Gathers OS, Oracle environment, ASM storage, OCI/Azure integration, and network
# configuration from the Oracle Database@Azure (ODAA / Exadata) target server.
# Executed via SSH as TARGET_ADMIN_USER (called by zdm_orchestrate_discovery.sh);
# all SQL runs under the oracle user via sudo.
#
# Output (current working directory):
#   zdm_target_discovery_<hostname>_<timestamp>.txt   — human-readable report
#   zdm_target_discovery_<hostname>_<timestamp>.json  — machine-parseable summary
#
# Usage (standalone / manual):
#   bash zdm_target_discovery.sh
#
# Override Oracle env before running if auto-detection fails:
#   TARGET_REMOTE_ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1 \
#   TARGET_ORACLE_SID=oradb011 bash zdm_target_discovery.sh
# =============================================================================

HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_TXT="./zdm_target_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
REPORT_JSON="./zdm_target_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

# Configuration — overridden via environment variables set by the orchestrator
ORACLE_USER="${ORACLE_USER:-oracle}"
TARGET_REMOTE_ORACLE_HOME="${TARGET_REMOTE_ORACLE_HOME:-}"
TARGET_ORACLE_SID="${TARGET_ORACLE_SID:-}"

# Tracked warnings for JSON summary
WARNINGS=()

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log_section() { printf '\n## %s\n\n' "$1" | tee -a "$REPORT_TXT"; }
log_info()    { printf '  %s\n' "$*"    | tee -a "$REPORT_TXT"; }
log_raw()     { printf '%s\n'   "$*"   >> "$REPORT_TXT"; }
add_warning() { WARNINGS+=("$*"); log_info "WARNING: $*"; }

# ---------------------------------------------------------------------------
# Initialize report header
# ---------------------------------------------------------------------------
{
    printf '# ZDM Target Discovery Report\n\n'
    printf '| Field | Value |\n'
    printf '|-------|-------|\n'
    printf '| Generated | %s |\n' "$(date)"
    printf '| Hostname  | %s |\n' "${HOSTNAME_SHORT}"
    printf '| Run by    | %s |\n' "$(whoami)"
    printf '\n'
} > "$REPORT_TXT"

# ---------------------------------------------------------------------------
# Auto-detect ORACLE_HOME and ORACLE_SID
# Priority: env override → /etc/oratab → pmon process → common paths → oraenv
# Note: On ODAA/Exadata RAC, /etc/oratab returns db_name (e.g. oradb01) but
#       the running SID is db_name + node number (e.g. oradb011).
#       Set TARGET_ORACLE_SID to the Node 1 instance SID to override.
# ---------------------------------------------------------------------------
detect_oracle_env() {
    local detected_home="${TARGET_REMOTE_ORACLE_HOME:-}"
    local detected_sid="${TARGET_ORACLE_SID:-}"

    # 2. Parse /etc/oratab
    if { [[ -z "${detected_home}" ]] || [[ -z "${detected_sid}" ]]; } && [[ -f /etc/oratab ]]; then
        while IFS=: read -r sid home _rest; do
            [[ "${sid}" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${sid}" || -z "${home}" || "${sid}" == "*" ]] && continue
            [[ -z "${detected_sid}"  ]] && detected_sid="${sid}"
            [[ -z "${detected_home}" ]] && detected_home="${home}"
            break
        done < /etc/oratab
    fi

    # 3. Running pmon process
    if [[ -z "${detected_sid}" ]]; then
        detected_sid="$(ps -ef 2>/dev/null | grep 'ora_pmon_' | grep -v grep \
            | sed 's/.*ora_pmon_//' | awk '{print $1}' | head -1)"
    fi

    # 4. Common installation paths (Exadata / ODAA layout)
    if [[ -z "${detected_home}" ]]; then
        for pat in \
            /u01/app/oracle/product/*/dbhome_1 \
            /u01/app/oracle/product/*/* \
            /opt/oracle/product/*/dbhome_1 \
            /u02/app/oracle/product/*/dbhome_1; do
            for p in ${pat}; do
                [[ -f "${p}/bin/sqlplus" ]] && { detected_home="${p}"; break 2; }
            done
        done
    fi

    # 5. oraenv
    if [[ -z "${detected_home}" ]]; then
        for oraenv_path in /usr/local/bin/oraenv /usr/bin/oraenv; do
            if [[ -f "${oraenv_path}" ]]; then
                local tmp_home
                tmp_home="$(ORACLE_SID="${detected_sid:-ORCL}" bash -c \
                    ". ${oraenv_path} </dev/null 2>/dev/null; echo \${ORACLE_HOME:-}" 2>/dev/null)"
                [[ -n "${tmp_home}" && -d "${tmp_home}" ]] && { detected_home="${tmp_home}"; break; }
            fi
        done
    fi

    ORACLE_HOME="${detected_home}"
    ORACLE_SID="${detected_sid}"
    export ORACLE_HOME ORACLE_SID
    [[ -n "${ORACLE_HOME}" ]] && export PATH="${ORACLE_HOME}/bin:${PATH}"
}

detect_oracle_env

# ---------------------------------------------------------------------------
# SQL execution helper — runs SQL*Plus as the oracle user
# ---------------------------------------------------------------------------
run_sql() {
    local sql_input="$1"
    if [[ "$(whoami)" == "${ORACLE_USER}" ]]; then
        "${ORACLE_HOME}/bin/sqlplus" -S / as sysdba <<< "${sql_input}" 2>&1
    else
        sudo -u "${ORACLE_USER}" \
            ORACLE_HOME="${ORACLE_HOME}" ORACLE_SID="${ORACLE_SID}" \
            "${ORACLE_HOME}/bin/sqlplus" -S / as sysdba <<< "${sql_input}" 2>&1
    fi
}

SQL_FMT="SET PAGESIZE 200 FEEDBACK OFF VERIFY OFF HEADING ON ECHO OFF LINESIZE 220 TRIMOUT ON TRIMSPOOL ON"

# ---------------------------------------------------------------------------
# Section 1: OS Information
# ---------------------------------------------------------------------------
log_section "OS Information"
{
    log_info "Hostname (FQDN): $(hostname -f 2>/dev/null || hostname)"
    log_info "Hostname (short): ${HOSTNAME_SHORT}"
    log_info ""
    log_info "IP Addresses:"
    ip addr show 2>/dev/null | grep 'inet ' | awk '{printf "    %s\n",$2}' | tee -a "$REPORT_TXT" \
        || ifconfig 2>/dev/null | grep 'inet ' | awk '{printf "    %s\n",$2}' | tee -a "$REPORT_TXT"

    log_info ""
    log_info "OS Release:"
    { cat /etc/os-release 2>/dev/null || cat /etc/redhat-release 2>/dev/null || uname -a; } \
        | tee -a "$REPORT_TXT"

    log_info ""
    log_info "Kernel: $(uname -r)"
}

# ---------------------------------------------------------------------------
# Section 2: Oracle Environment
# ---------------------------------------------------------------------------
log_section "Oracle Environment"
log_info "ORACLE_HOME : ${ORACLE_HOME:-NOT DETECTED}"
log_info "ORACLE_SID  : ${ORACLE_SID:-NOT DETECTED}"
log_info "ORACLE_BASE : ${ORACLE_BASE:-}"

[[ -z "${ORACLE_HOME}" ]] && add_warning "ORACLE_HOME could not be auto-detected. SQL sections skipped."
[[ -z "${ORACLE_SID}"  ]] && add_warning "ORACLE_SID could not be auto-detected. Set TARGET_ORACLE_SID to the Node 1 instance SID (e.g. oradb011)."

if [[ -n "${ORACLE_HOME}" && -f "${ORACLE_HOME}/bin/sqlplus" ]]; then
    ORACLE_VERSION_STR="$("${ORACLE_HOME}/bin/sqlplus" -V 2>/dev/null | grep -i 'release' | head -1)"
    log_info "Oracle version: ${ORACLE_VERSION_STR}"
fi

# ---------------------------------------------------------------------------
# Verify SQL*Plus connectivity
# ---------------------------------------------------------------------------
SQL_OK=false
if [[ -n "${ORACLE_HOME}" && -n "${ORACLE_SID}" && -f "${ORACLE_HOME}/bin/sqlplus" ]]; then
    sql_test_out="$(run_sql "SELECT 'SQLPLUS_OK' FROM DUAL; EXIT;" 2>&1)"
    if echo "${sql_test_out}" | grep -q 'SQLPLUS_OK'; then
        SQL_OK=true
    else
        add_warning "SQL*Plus connectivity test failed — Output: ${sql_test_out}"
        add_warning "If running on ODAA/Exadata RAC, set TARGET_ORACLE_SID to the Node 1 instance SID (confirmed via: ps -ef | grep pmon)"
    fi
fi

log_info "SQL*Plus connectivity: ${SQL_OK}"

# ---------------------------------------------------------------------------
# Section 3: Database Configuration
# ---------------------------------------------------------------------------
log_section "Database Configuration"
DB_NAME="" DB_UNIQUE_NAME="" DB_CHARSET="" OPEN_MODE="" CDB_STATUS=""

if [[ "${SQL_OK}" == "true" ]]; then
    run_sql "${SQL_FMT}
SELECT 'DB_NAME='        || NAME             AS PROPERTY FROM V\$DATABASE
UNION ALL
SELECT 'DB_UNIQUE_NAME=' || DB_UNIQUE_NAME   FROM V\$DATABASE
UNION ALL
SELECT 'DBID='           || DBID             FROM V\$DATABASE
UNION ALL
SELECT 'DATABASE_ROLE='  || DATABASE_ROLE    FROM V\$DATABASE
UNION ALL
SELECT 'OPEN_MODE='      || OPEN_MODE        FROM V\$DATABASE;
EXIT;" | tee -a "$REPORT_TXT"

    log_info ""
    log_info "NLS Parameters:"
    run_sql "${SQL_FMT}
SELECT PARAMETER, VALUE
FROM NLS_DATABASE_PARAMETERS
WHERE PARAMETER IN ('NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET','NLS_LANGUAGE','NLS_TERRITORY')
ORDER BY PARAMETER;
EXIT;" | tee -a "$REPORT_TXT"

    DB_NAME="$(run_sql "SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT NAME FROM V\$DATABASE; EXIT;" | tr -d '[:space:]')"
    DB_UNIQUE_NAME="$(run_sql "SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT DB_UNIQUE_NAME FROM V\$DATABASE; EXIT;" | tr -d '[:space:]')"
    OPEN_MODE="$(run_sql "SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT OPEN_MODE FROM V\$DATABASE; EXIT;" | tr -d '[:space:]')"
    DB_CHARSET="$(run_sql "SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT VALUE FROM NLS_DATABASE_PARAMETERS WHERE PARAMETER='NLS_CHARACTERSET'; EXIT;" | tr -d '[:space:]')"
else
    log_info "(Skipped — SQL connection unavailable)"
fi

# ---------------------------------------------------------------------------
# Section 4: Container Database (CDB / PDB)
# ---------------------------------------------------------------------------
log_section "Container Database (CDB / PDB)"
if [[ "${SQL_OK}" == "true" ]]; then
    CDB_STATUS="$(run_sql "SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT CDB FROM V\$DATABASE; EXIT;" | tr -d '[:space:]')"
    log_info "CDB: ${CDB_STATUS}"

    if [[ "${CDB_STATUS}" == "YES" ]]; then
        log_info ""
        log_info "All PDBs (including pre-created migration PDB):"
        run_sql "${SQL_FMT}
COLUMN PDB_NAME    FORMAT A35
COLUMN OPEN_MODE   FORMAT A15
COLUMN RESTRICTED  FORMAT A10
COLUMN STATUS      FORMAT A10
SELECT PDB_NAME, OPEN_MODE, RESTRICTED, STATUS
FROM   CDB_PDBS
ORDER  BY PDB_NAME;
EXIT;" | tee -a "$REPORT_TXT"
    else
        log_info "Non-CDB (traditional single-tenant)"
    fi
else
    log_info "(Skipped — SQL connection unavailable)"
fi

# ---------------------------------------------------------------------------
# Section 5: Transparent Data Encryption (TDE)
# ---------------------------------------------------------------------------
log_section "Transparent Data Encryption (TDE) — Wallet Status"
if [[ "${SQL_OK}" == "true" ]]; then
    run_sql "${SQL_FMT}
COLUMN WRL_TYPE      FORMAT A15
COLUMN WRL_PARAMETER FORMAT A60
COLUMN STATUS        FORMAT A20
SELECT WRL_TYPE, WRL_PARAMETER, STATUS FROM V\$ENCRYPTION_WALLET;
EXIT;" | tee -a "$REPORT_TXT"

    run_sql "${SQL_FMT}
SHOW PARAMETER wallet_root;
SHOW PARAMETER tde_configuration;
EXIT;" | tee -a "$REPORT_TXT"
else
    log_info "(Skipped — SQL connection unavailable)"
fi

# ---------------------------------------------------------------------------
# Section 6: ASM Storage (Disk Groups)
# ---------------------------------------------------------------------------
log_section "ASM Storage — Disk Groups"

# Detect GRID_HOME for asmcmd / crsctl
GRID_HOME=""
for p in \
    /u01/app/grid/product/*/grid \
    /u01/app/*/grid \
    /u01/app/grid \
    /opt/oracle/grid/*/; do
    for g in ${p}; do
        [[ -f "${g}/bin/asmcmd" ]] && { GRID_HOME="${g}"; break 2; }
    done
done

if [[ -n "${GRID_HOME}" ]]; then
    log_info "GRID_HOME detected: ${GRID_HOME}"
    log_info ""
    log_info "ASM Disk Groups (asmcmd lsdg):"
    "${GRID_HOME}/bin/asmcmd" lsdg 2>&1 | tee -a "$REPORT_TXT" \
        || log_info "(asmcmd lsdg failed)"
else
    log_info "Grid home not detected; trying SQL ASM query via V\$ASM_DISKGROUP..."
fi

if [[ "${SQL_OK}" == "true" ]]; then
    log_info ""
    log_info "ASM Disk Groups (V\$ASM_DISKGROUP):"
    run_sql "${SQL_FMT}
COLUMN GROUP_NUMBER FORMAT 999
COLUMN NAME         FORMAT A25
COLUMN STATE        FORMAT A10
COLUMN TYPE         FORMAT A10
COLUMN TOTAL_MB     FORMAT 9999999
COLUMN FREE_MB      FORMAT 9999999
SELECT GROUP_NUMBER, NAME, STATE, TYPE,
       ROUND(TOTAL_MB/1024,1) AS TOTAL_GB,
       ROUND(FREE_MB/1024,1)  AS FREE_GB
FROM   V\$ASM_DISKGROUP
ORDER  BY NAME;
EXIT;" | tee -a "$REPORT_TXT" || log_info "(V\$ASM_DISKGROUP query failed — may not be connected to ASM instance)"
fi

# ---------------------------------------------------------------------------
# Section 7: Network — Listener (includes SCAN listener for RAC)
# ---------------------------------------------------------------------------
log_section "Network — Listener Status"
lsnrctl status 2>&1 | tee -a "$REPORT_TXT" || log_info "(lsnrctl not found or not on PATH)"

if [[ -n "${GRID_HOME}" ]]; then
    log_info ""
    log_info "SCAN Listener Status:"
    "${GRID_HOME}/bin/srvctl" status scan_listener 2>&1 | tee -a "$REPORT_TXT" \
        || log_info "(srvctl scan_listener unavailable)"
fi

log_section "tnsnames.ora"
TNSNAMES_PATH=""
for p in \
    "${ORACLE_HOME}/network/admin/tnsnames.ora" \
    "${GRID_HOME}/network/admin/tnsnames.ora" \
    "${TNS_ADMIN:-}/tnsnames.ora" \
    "/etc/tnsnames.ora"; do
    [[ -n "${p}" && -f "${p}" ]] && { TNSNAMES_PATH="${p}"; break; }
done
if [[ -n "${TNSNAMES_PATH}" ]]; then
    log_info "Location: ${TNSNAMES_PATH}"
    cat "${TNSNAMES_PATH}" 2>&1 | tee -a "$REPORT_TXT"
else
    log_info "(tnsnames.ora not found)"
fi

# ---------------------------------------------------------------------------
# Section 8: OCI / Azure Integration
# ---------------------------------------------------------------------------
log_section "OCI CLI — Version and Configuration"
if command -v oci &>/dev/null; then
    oci --version 2>&1 | tee -a "$REPORT_TXT"
    log_info ""
    log_info "OCI config file location and masked contents (~/.oci/config):"
    if [[ -f ~/.oci/config ]]; then
        grep -E '^\[|^fingerprint|^region|^tenancy|^user' ~/.oci/config 2>/dev/null \
            | tee -a "$REPORT_TXT"
    else
        log_info "(~/.oci/config not found)"
    fi

    log_info ""
    log_info "OCI CLI connectivity test (iam get-user):"
    oci iam region list --output table 2>&1 | head -20 | tee -a "$REPORT_TXT" \
        || log_info "(OCI CLI connectivity test failed)"
else
    log_info "(OCI CLI not found in PATH)"
fi

log_section "Azure / OCI Instance Metadata"
log_info "OCI instance metadata (timeout 3s):"
curl -s --connect-timeout 3 \
    -H 'Authorization: Bearer Oracle' \
    http://169.254.169.254/opc/v2/instance/ 2>/dev/null \
    | tee -a "$REPORT_TXT" || log_info "(OCI metadata endpoint not available)"

# ---------------------------------------------------------------------------
# Section 9: Grid Infrastructure (RAC / Exadata)
# ---------------------------------------------------------------------------
log_section "Grid Infrastructure — CRS / Cluster Status"
if [[ -n "${GRID_HOME}" ]]; then
    log_info "CRS status (crsctl stat res -t):"
    "${GRID_HOME}/bin/crsctl" stat res -t 2>&1 | tee -a "$REPORT_TXT" \
        || log_info "(crsctl stat res failed)"

    log_info ""
    log_info "Cluster nodes:"
    "${GRID_HOME}/bin/olsnodes" -n 2>&1 | tee -a "$REPORT_TXT" \
        || log_info "(olsnodes unavailable)"
else
    log_info "(Grid home not detected — skipping CRS checks)"
fi

# ---------------------------------------------------------------------------
# Section 10: Network Security — Firewall and Port Rules
# ---------------------------------------------------------------------------
log_section "Network Security — Firewall Rules"
log_info "iptables rules (ports 22, 1521, 2484):"
iptables -L -n 2>/dev/null | grep -E '22|1521|2484|ACCEPT|REJECT|DROP' | tee -a "$REPORT_TXT" \
    || log_info "(iptables not available or no matching rules)"

log_info ""
log_info "firewalld status:"
firewall-cmd --list-all 2>/dev/null | tee -a "$REPORT_TXT" \
    || systemctl status firewalld 2>/dev/null | head -5 | tee -a "$REPORT_TXT" \
    || log_info "(firewalld not running or not installed)"

log_info ""
log_info "Port 1521 listening:"
ss -tlnp | grep ':1521\|:2484' | tee -a "$REPORT_TXT" \
    || netstat -tlnp 2>/dev/null | grep ':1521\|:2484' | tee -a "$REPORT_TXT" \
    || log_info "(ss/netstat not available)"

log_info ""
log_info "OCI NSG rules (if OCI CLI configured):"
if command -v oci &>/dev/null; then
    oci network nsg list --compartment-id "${OCI_COMPARTMENT_OCID:-}" \
        --output table 2>&1 | head -30 | tee -a "$REPORT_TXT" \
        || log_info "(OCI NSG query failed or OCI_COMPARTMENT_OCID not set)"
else
    log_info "(OCI CLI not available)"
fi

# ---------------------------------------------------------------------------
# Build JSON summary
# ---------------------------------------------------------------------------
WARNINGS_JSON="["
for i in "${!WARNINGS[@]}"; do
    [[ $i -gt 0 ]] && WARNINGS_JSON+=","
    escaped="${WARNINGS[$i]//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    WARNINGS_JSON+="\"${escaped}\""
done
WARNINGS_JSON+="]"

STATUS="success"
[[ ${#WARNINGS[@]} -gt 0 ]] && STATUS="partial"

cat > "${REPORT_JSON}" << JSONEOF
{
  "report":         "target-discovery",
  "phase":          "Phase10-ZDM-Step2",
  "generated":      "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "run_by":         "$(whoami)",
  "hostname":       "${HOSTNAME_SHORT}",
  "status":         "${STATUS}",
  "oracle_home":    "${ORACLE_HOME:-}",
  "oracle_sid":     "${ORACLE_SID:-}",
  "db_name":        "${DB_NAME:-}",
  "db_unique_name": "${DB_UNIQUE_NAME:-}",
  "open_mode":      "${OPEN_MODE:-}",
  "characterset":   "${DB_CHARSET:-}",
  "cdb":            "${CDB_STATUS:-}",
  "grid_home":      "${GRID_HOME:-}",
  "sql_connected":  ${SQL_OK},
  "warnings":       ${WARNINGS_JSON},
  "report_txt":     "${REPORT_TXT}"
}
JSONEOF

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "  ZDM Target Discovery — Complete"
echo "  Hostname : ${HOSTNAME_SHORT}"
echo "  Status   : ${STATUS}"
echo "  Warnings : ${#WARNINGS[@]}"
echo "  Reports  :"
echo "    ${REPORT_TXT}"
echo "    ${REPORT_JSON}"
echo "============================================================"
