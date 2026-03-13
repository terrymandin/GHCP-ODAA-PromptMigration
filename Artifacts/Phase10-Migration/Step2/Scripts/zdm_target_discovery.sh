#!/usr/bin/env bash
# =============================================================================
# zdm_target_discovery.sh
# Phase 10 — ZDM Migration · Step 2: Target Database Discovery
#
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration
#
# Runs on the TARGET Oracle Database@Azure server (via SSH as ADMIN_USER with
# sudo for oracle). Discovers OS, Oracle environment, database configuration,
# TDE, CDB/PDB, network, OCI/Azure integration, Grid Infrastructure (RAC),
# Exadata/ASM storage, pre-configured PDBs, and NSG rules.
#
# Outputs (written to current working directory):
#   zdm_target_discovery_<hostname>_<timestamp>.txt
#   zdm_target_discovery_<hostname>_<timestamp>.json
#
# Usage (typically invoked by zdm_orchestrate_discovery.sh):
#   bash zdm_target_discovery.sh
#
# Overrides (optional environment variables):
#   ORACLE_HOME  - Override auto-detected Oracle home
#   ORACLE_SID   - Override auto-detected Oracle SID
#   ORACLE_USER  - Oracle software owner (default: oracle)
# =============================================================================

# DO NOT use set -e globally — allows individual section failures without aborting
set -uo pipefail

# ---------------------------------------------------------------------------
# Configuration defaults
# ---------------------------------------------------------------------------
ORACLE_USER="${ORACLE_USER:-oracle}"

HOSTNAME_VAL="$(hostname -s 2>/dev/null || hostname)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_TXT="./zdm_target_discovery_${HOSTNAME_VAL}_${TIMESTAMP}.txt"
REPORT_JSON="./zdm_target_discovery_${HOSTNAME_VAL}_${TIMESTAMP}.json"

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log_raw() {
    local msg="$1"
    echo "$msg" | tee -a "${REPORT_TXT}"
}

log_section() {
    local title="$1"
    local line="============================================================"
    echo "" | tee -a "${REPORT_TXT}"
    echo "${line}" | tee -a "${REPORT_TXT}"
    echo "  ${title}" | tee -a "${REPORT_TXT}"
    echo "${line}" | tee -a "${REPORT_TXT}"
}

log_info() {
    log_raw "  [INFO]  $*"
}

log_warn() {
    log_raw "  [WARN]  $*"
}

log_error() {
    log_raw "  [ERROR] $*"
}

# ---------------------------------------------------------------------------
# Oracle environment auto-detection
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
        if [ -n "${oratab_entry:-}" ]; then
            export ORACLE_SID="${ORACLE_SID:-$(echo "$oratab_entry" | cut -d: -f1)}"
            export ORACLE_HOME="${ORACLE_HOME:-$(echo "$oratab_entry" | cut -d: -f2)}"
        fi
    fi

    # Method 2: Check running pmon process
    if [ -z "${ORACLE_SID:-}" ]; then
        local pmon_sid
        pmon_sid=$(ps -ef | grep 'ora_pmon_' | grep -v grep | head -1 | sed 's/.*ora_pmon_//' 2>/dev/null || true)
        [ -n "${pmon_sid:-}" ] && export ORACLE_SID="$pmon_sid"
    fi

    # Method 3: Search common Oracle paths (including Exadata)
    if [ -z "${ORACLE_HOME:-}" ]; then
        for path in /u01/app/oracle/product/*/dbhome_1 \
                    /u02/app/oracle/product/*/dbhome_1 \
                    /opt/oracle/product/*/dbhome_1 \
                    /oracle/product/*/dbhome_1; do
            if [ -d "$path" ] && [ -f "$path/bin/sqlplus" ]; then
                export ORACLE_HOME="$path"
                break
            fi
        done
    fi

    # Method 4: Use oraenv
    if [ -z "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        [ -f /usr/local/bin/oraenv ] && ORACLE_SID="$ORACLE_SID" . /usr/local/bin/oraenv <<< "$ORACLE_SID" 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------
# SQL execution helper
# ---------------------------------------------------------------------------
run_sql() {
    local sql_query="$1"
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        local sqlplus_cmd="${ORACLE_HOME}/bin/sqlplus -s / as sysdba"
        local sql_script
        sql_script=$(printf 'SET PAGESIZE 1000\nSET LINESIZE 200\nSET FEEDBACK OFF\nSET HEADING ON\nSET ECHO OFF\n%s\n' "$sql_query")
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            echo "$sql_script" | $sqlplus_cmd 2>&1
        else
            echo "$sql_script" | sudo -u "$ORACLE_USER" -E ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd 2>&1
        fi
    else
        echo "SKIPPED: ORACLE_HOME or ORACLE_SID not set"
        return 1
    fi
}

run_sql_value() {
    local sql_query="$1"
    run_sql "SET PAGESIZE 0
SET FEEDBACK OFF
SET HEADING OFF
SET ECHO OFF
SET TRIMOUT ON
${sql_query}" 2>/dev/null | grep -v '^$' | head -1 | tr -d ' '
}

# ---------------------------------------------------------------------------
# Section: OS Information
# ---------------------------------------------------------------------------
section_os() {
    log_section "OS INFORMATION"
    log_info "Hostname:          $(hostname)"
    log_info "OS Release:        $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"' || uname -a)"
    log_info "Kernel:            $(uname -r)"
    log_info "Architecture:      $(uname -m)"
    log_info "Date/Time:         $(date)"
    log_info "Uptime:            $(uptime)"
    log_info ""
    log_info "-- IP Addresses --"
    ip addr show 2>/dev/null | grep 'inet ' | awk '{print "  " $2 " dev " $NF}' | tee -a "${REPORT_TXT}" || \
        ifconfig 2>/dev/null | grep 'inet ' | tee -a "${REPORT_TXT}" || log_warn "Could not retrieve IP addresses"
}

# ---------------------------------------------------------------------------
# Section: Oracle Environment
# ---------------------------------------------------------------------------
section_oracle_env() {
    log_section "ORACLE ENVIRONMENT"
    log_info "ORACLE_HOME:       ${ORACLE_HOME:-NOT SET}"
    log_info "ORACLE_SID:        ${ORACLE_SID:-NOT SET}"
    log_info "ORACLE_BASE:       ${ORACLE_BASE:-NOT SET}"
    if [ -n "${ORACLE_HOME:-}" ] && [ -f "${ORACLE_HOME}/bin/sqlplus" ]; then
        local ver
        ver=$(${ORACLE_HOME}/bin/sqlplus -V 2>/dev/null | head -3 || echo "UNKNOWN")
        log_info "Oracle Version:    ${ver}"
    else
        log_warn "sqlplus not found at ${ORACLE_HOME:-UNKNOWN}/bin/sqlplus"
    fi
    log_info ""
    log_info "-- /etc/oratab --"
    cat /etc/oratab 2>/dev/null | tee -a "${REPORT_TXT}" || log_warn "/etc/oratab not found"
}

# ---------------------------------------------------------------------------
# Section: Database Configuration
# ---------------------------------------------------------------------------
section_db_config() {
    log_section "DATABASE CONFIGURATION"
    local db_name db_unique_name db_role open_mode charset
    db_name=$(run_sql_value "SELECT NAME FROM V\$DATABASE;" 2>/dev/null || echo "N/A")
    db_unique_name=$(run_sql_value "SELECT DB_UNIQUE_NAME FROM V\$DATABASE;" 2>/dev/null || echo "N/A")
    db_role=$(run_sql_value "SELECT DATABASE_ROLE FROM V\$DATABASE;" 2>/dev/null || echo "N/A")
    open_mode=$(run_sql_value "SELECT OPEN_MODE FROM V\$DATABASE;" 2>/dev/null || echo "N/A")
    charset=$(run_sql_value "SELECT VALUE FROM NLS_DATABASE_PARAMETERS WHERE PARAMETER='NLS_CHARACTERSET';" 2>/dev/null || echo "N/A")

    log_info "DB Name:           ${db_name}"
    log_info "DB Unique Name:    ${db_unique_name}"
    log_info "DB Role:           ${db_role}"
    log_info "Open Mode:         ${open_mode}"
    log_info "Character Set:     ${charset}"

    log_info ""
    log_info "-- Available Tablespaces (Storage) --"
    run_sql "SELECT TABLESPACE_NAME, STATUS, CONTENTS,
       ROUND(NVL(SUM_BYTES,0)/1073741824,2) AS TOTAL_GB
FROM (
    SELECT T.TABLESPACE_NAME, T.STATUS, T.CONTENTS,
           SUM(D.BYTES) AS SUM_BYTES
    FROM DBA_TABLESPACES T
    LEFT JOIN DBA_DATA_FILES D ON T.TABLESPACE_NAME = D.TABLESPACE_NAME
    GROUP BY T.TABLESPACE_NAME, T.STATUS, T.CONTENTS
)
ORDER BY TABLESPACE_NAME;" | tee -a "${REPORT_TXT}" || true
}

# ---------------------------------------------------------------------------
# Section: Container Database (CDB/PDB)
# ---------------------------------------------------------------------------
section_cdb() {
    log_section "CONTAINER DATABASE (CDB/PDB)"
    local cdb_status
    cdb_status=$(run_sql_value "SELECT CDB FROM V\$DATABASE;" 2>/dev/null || echo "N/A")
    log_info "CDB:               ${cdb_status}"

    log_info ""
    log_info "-- All PDBs --"
    run_sql "SELECT NAME, OPEN_MODE, RESTRICTED, CREATE_SCN,
       CON_ID, PDB_ID
FROM V\$PDBS
ORDER BY NAME;" | tee -a "${REPORT_TXT}" || true

    log_info ""
    log_info "-- PDB Storage Limits --"
    run_sql "SELECT PDB_NAME, MAX_SIZE, MAX_SHARED_TEMP_SIZE
FROM DBA_PDBS
ORDER BY PDB_NAME;" | tee -a "${REPORT_TXT}" || log_warn "Could not query DBA_PDBS (may need higher privilege)"
}

# ---------------------------------------------------------------------------
# Section: TDE Configuration
# ---------------------------------------------------------------------------
section_tde() {
    log_section "TDE CONFIGURATION"
    log_info "-- Wallet Status --"
    run_sql "SELECT WRL_TYPE, WRL_PARAMETER, STATUS, WALLET_TYPE
FROM V\$ENCRYPTION_WALLET;" | tee -a "${REPORT_TXT}" || log_warn "Could not query TDE wallet"
}

# ---------------------------------------------------------------------------
# Section: Network Configuration
# ---------------------------------------------------------------------------
section_network() {
    log_section "NETWORK CONFIGURATION"
    log_info "-- Listener Status --"
    if [ -n "${ORACLE_HOME:-}" ]; then
        "${ORACLE_HOME}/bin/lsnrctl" status 2>&1 | tee -a "${REPORT_TXT}" || log_warn "lsnrctl status failed"
    else
        log_warn "ORACLE_HOME not set; skipping lsnrctl"
    fi

    log_info ""
    log_info "-- SCAN Listener (RAC) --"
    if [ -n "${ORACLE_HOME:-}" ]; then
        "${ORACLE_HOME}/bin/lsnrctl" status LISTENER_SCAN1 2>&1 | tee -a "${REPORT_TXT}" || \
            log_info "No SCAN listener found (may not be RAC)"
    fi

    log_info ""
    log_info "-- tnsnames.ora --"
    local tns_file=""
    [ -n "${ORACLE_HOME:-}" ] && tns_file="${ORACLE_HOME}/network/admin/tnsnames.ora"
    if [ -n "${tns_file:-}" ] && [ -f "${tns_file}" ]; then
        cat "${tns_file}" | tee -a "${REPORT_TXT}"
    else
        log_warn "tnsnames.ora not found"
    fi

    log_info ""
    log_info "-- Open Ports (Oracle) --"
    ss -tlnp 2>/dev/null | grep -E '1521|2484|1158' | tee -a "${REPORT_TXT}" || \
        netstat -tlnp 2>/dev/null | grep -E '1521|2484|1158' | tee -a "${REPORT_TXT}" || \
        log_warn "Could not query open ports"
}

# ---------------------------------------------------------------------------
# Section: OCI / Azure Integration
# ---------------------------------------------------------------------------
section_oci_azure() {
    log_section "OCI / AZURE INTEGRATION"
    log_info "-- OCI CLI Version --"
    oci --version 2>&1 | tee -a "${REPORT_TXT}" || log_warn "OCI CLI not found or not in PATH"

    log_info ""
    log_info "-- OCI Config File --"
    local oci_config="${OCI_CONFIG_PATH:-${HOME}/.oci/config}"
    if [ -f "${oci_config}" ]; then
        # Mask private key content and fingerprint values
        sed 's/\(key_file\s*=\s*\).*/\1[MASKED]/' "${oci_config}" | \
            sed 's/\(fingerprint\s*=\s*\).*/\1[MASKED]/' | \
            tee -a "${REPORT_TXT}"
    else
        log_warn "OCI config not found at ${oci_config}"
    fi

    log_info ""
    log_info "-- OCI Connectivity Test --"
    if command -v oci >/dev/null 2>&1; then
        oci iam region list --output table 2>&1 | head -10 | tee -a "${REPORT_TXT}" || \
            log_warn "OCI connectivity test failed (authentication may not be configured)"
    fi

    log_info ""
    log_info "-- Instance Metadata (OCI) --"
    curl -s -m 5 http://169.254.169.254/opc/v1/instance/ 2>/dev/null | \
        python3 -m json.tool 2>/dev/null | head -30 | tee -a "${REPORT_TXT}" || \
        log_info "OCI instance metadata not available (may be Azure)"

    log_info ""
    log_info "-- Instance Metadata (Azure) --"
    curl -s -m 5 -H "Metadata:true" \
        "http://169.254.169.254/metadata/instance?api-version=2021-02-01" 2>/dev/null | \
        python3 -m json.tool 2>/dev/null | head -30 | tee -a "${REPORT_TXT}" || \
        log_info "Azure instance metadata not available (may be OCI)"
}

# ---------------------------------------------------------------------------
# Section: Grid Infrastructure (RAC)
# ---------------------------------------------------------------------------
section_grid() {
    log_section "GRID INFRASTRUCTURE (RAC)"
    log_info "-- CRS Status --"
    local grid_home
    grid_home=$(cat /etc/oratab 2>/dev/null | grep 'ASM:' | cut -d: -f2 | head -1)
    if [ -z "${grid_home:-}" ]; then
        # Try common grid home paths
        for path in /u01/app/19.0.0.0/grid /u01/app/grid/product/*/grid /u01/grid; do
            [ -f "${path}/bin/crsctl" ] && grid_home="$path" && break
        done
    fi

    if [ -n "${grid_home:-}" ] && [ -f "${grid_home}/bin/crsctl" ]; then
        log_info "Grid Home: ${grid_home}"
        "${grid_home}/bin/crsctl" check cluster -all 2>&1 | tee -a "${REPORT_TXT}" || \
            log_warn "crsctl check failed"
        "${grid_home}/bin/crsctl" status resource -t 2>&1 | head -30 | tee -a "${REPORT_TXT}" || true
    else
        log_info "Grid Infrastructure not detected (single-instance or Grid Home not found)"
    fi
}

# ---------------------------------------------------------------------------
# Section: Exadata / ASM Storage Capacity
# ---------------------------------------------------------------------------
section_exadata_storage() {
    log_section "EXADATA / ASM STORAGE CAPACITY"
    log_info "-- ASM Disk Groups --"
    run_sql "SELECT GROUP_NUMBER, NAME, STATE, TYPE,
       ROUND(TOTAL_MB/1024,0) AS TOTAL_GB,
       ROUND(FREE_MB/1024,0) AS FREE_GB,
       ROUND((TOTAL_MB-FREE_MB)/TOTAL_MB*100,1) AS PCT_USED
FROM V\$ASM_DISKGROUP
ORDER BY NAME;" | tee -a "${REPORT_TXT}" || log_warn "Could not query ASM disk groups (may not be ASM)"

    log_info ""
    log_info "-- Cellcli (Exadata Smart Storage) --"
    if command -v cellcli >/dev/null 2>&1; then
        cellcli -e "list celldisk attributes name,freespace,size" 2>/dev/null | \
            tee -a "${REPORT_TXT}" || log_warn "cellcli query failed"
    else
        log_info "cellcli not available (non-Exadata environment)"
    fi

    log_info ""
    log_info "-- ASMCMD Space Usage --"
    if [ -n "${ORACLE_HOME:-}" ]; then
        local asm_base
        asm_base=$(ls /u01/app/*/grid/bin/asmcmd 2>/dev/null | head -1)
        [ -z "${asm_base:-}" ] && asm_base="${ORACLE_HOME%/dbhome*}/grid/bin/asmcmd" 2>/dev/null || true
        if [ -n "${asm_base:-}" ] && [ -f "${asm_base}" ]; then
            echo "lsdg" | sudo -u "$ORACLE_USER" ORACLE_HOME="$(dirname "$(dirname "${asm_base}")")" \
                ORACLE_SID="+ASM" "${asm_base}" 2>/dev/null | tee -a "${REPORT_TXT}" || \
                log_info "ASMCMD lsdg not available"
        else
            log_info "ASMCMD not found — ASM may not be installed"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Section: Network Security Group / Firewall Rules
# ---------------------------------------------------------------------------
section_nsg_firewall() {
    log_section "NETWORK SECURITY GROUP / FIREWALL RULES"
    log_info "-- iptables (Oracle Ports) --"
    iptables -L -n 2>/dev/null | grep -E '1521|2484|22|0\.0\.0\.0' | tee -a "${REPORT_TXT}" || \
        log_warn "iptables query failed (may need sudo or not installed)"

    log_info ""
    log_info "-- firewalld Status --"
    if command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --state 2>&1 | tee -a "${REPORT_TXT}" || true
        firewall-cmd --list-all 2>&1 | tee -a "${REPORT_TXT}" || true
    else
        log_info "firewalld not found"
    fi

    log_info ""
    log_info "-- OCI NSG Rules (via OCI CLI) --"
    if command -v oci >/dev/null 2>&1 && [ -n "${OCI_COMPARTMENT_OCID:-}" ]; then
        oci network nsg list --compartment-id "${OCI_COMPARTMENT_OCID}" \
            --output table 2>&1 | head -20 | tee -a "${REPORT_TXT}" || \
            log_warn "Could not list OCI NSGs (check OCI CLI config)"
    else
        log_info "OCI compartment OCID not set — skipping OCI NSG query"
    fi
}

# ---------------------------------------------------------------------------
# Section: Authentication
# ---------------------------------------------------------------------------
section_auth() {
    log_section "AUTHENTICATION"
    log_info "-- SSH Directory (oracle user) --"
    local oracle_home_dir
    oracle_home_dir=$(eval echo "~${ORACLE_USER}" 2>/dev/null || echo "/home/${ORACLE_USER}")
    if [ -d "${oracle_home_dir}/.ssh" ]; then
        ls -la "${oracle_home_dir}/.ssh/" 2>/dev/null | tee -a "${REPORT_TXT}" || true
    else
        log_warn ".ssh directory not found for ${ORACLE_USER}"
    fi
}

# ---------------------------------------------------------------------------
# Build JSON summary
# ---------------------------------------------------------------------------
build_json() {
    local db_name db_unique_name db_role open_mode cdb_status charset tde_status
    db_name=$(run_sql_value "SELECT NAME FROM V\$DATABASE;" 2>/dev/null || echo "N/A")
    db_unique_name=$(run_sql_value "SELECT DB_UNIQUE_NAME FROM V\$DATABASE;" 2>/dev/null || echo "N/A")
    db_role=$(run_sql_value "SELECT DATABASE_ROLE FROM V\$DATABASE;" 2>/dev/null || echo "N/A")
    open_mode=$(run_sql_value "SELECT OPEN_MODE FROM V\$DATABASE;" 2>/dev/null || echo "N/A")
    cdb_status=$(run_sql_value "SELECT CDB FROM V\$DATABASE;" 2>/dev/null || echo "N/A")
    charset=$(run_sql_value "SELECT VALUE FROM NLS_DATABASE_PARAMETERS WHERE PARAMETER='NLS_CHARACTERSET';" 2>/dev/null || echo "N/A")
    tde_status=$(run_sql_value "SELECT STATUS FROM V\$ENCRYPTION_WALLET WHERE ROWNUM=1;" 2>/dev/null || echo "N/A")

    local pdb_count
    pdb_count=$(run_sql_value "SELECT COUNT(*) FROM V\$PDBS WHERE NAME != 'PDB\$SEED';" 2>/dev/null || echo "0")

    cat > "${REPORT_JSON}" <<JSONEOF
{
  "report_type": "target_discovery",
  "hostname": "${HOSTNAME_VAL}",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "oracle_environment": {
    "oracle_home": "${ORACLE_HOME:-N/A}",
    "oracle_sid": "${ORACLE_SID:-N/A}",
    "oracle_base": "${ORACLE_BASE:-N/A}"
  },
  "database": {
    "db_name": "${db_name}",
    "db_unique_name": "${db_unique_name}",
    "db_role": "${db_role}",
    "open_mode": "${open_mode}",
    "cdb": "${cdb_status}",
    "pdb_count": "${pdb_count}",
    "character_set": "${charset}"
  },
  "tde": {
    "wallet_status": "${tde_status}"
  },
  "report_files": {
    "text_report": "${REPORT_TXT}",
    "json_summary": "${REPORT_JSON}"
  }
}
JSONEOF
    log_info "JSON summary written to: ${REPORT_JSON}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    echo "# ZDM Target Discovery Report" > "${REPORT_TXT}"
    echo "# Generated: $(date)" >> "${REPORT_TXT}"
    echo "# Host: $(hostname)" >> "${REPORT_TXT}"
    echo "# Run as: $(whoami)" >> "${REPORT_TXT}"

    log_section "ZDM TARGET DISCOVERY — Phase 10 Step 2"
    log_info "Started:     $(date)"
    log_info "Run as:      $(whoami)@$(hostname)"
    log_info "Oracle User: ${ORACLE_USER}"

    detect_oracle_env

    # Apply explicit overrides (highest priority)
    [ -n "${TARGET_REMOTE_ORACLE_HOME:-}" ] && export ORACLE_HOME="$TARGET_REMOTE_ORACLE_HOME"
    [ -n "${TARGET_ORACLE_SID:-}" ]         && export ORACLE_SID="$TARGET_ORACLE_SID"
    [ -n "${TARGET_REMOTE_ORACLE_SID:-}" ]  && export ORACLE_SID="$TARGET_REMOTE_ORACLE_SID"

    log_info "ORACLE_HOME: ${ORACLE_HOME:-NOT DETECTED}"
    log_info "ORACLE_SID:  ${ORACLE_SID:-NOT DETECTED}"

    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        log_warn "Oracle environment not fully detected — SQL sections will be skipped"
    fi

    section_os              || log_warn "OS section encountered errors"
    section_oracle_env      || log_warn "Oracle env section encountered errors"
    section_db_config       || log_warn "DB config section encountered errors"
    section_cdb             || log_warn "CDB section encountered errors"
    section_tde             || log_warn "TDE section encountered errors"
    section_network         || log_warn "Network section encountered errors"
    section_oci_azure       || log_warn "OCI/Azure section encountered errors"
    section_grid            || log_warn "Grid Infrastructure section encountered errors"
    section_exadata_storage || log_warn "Exadata/ASM storage section encountered errors"
    section_nsg_firewall    || log_warn "NSG/Firewall section encountered errors"
    section_auth            || log_warn "Authentication section encountered errors"

    log_section "DISCOVERY COMPLETE"
    log_info "Finished: $(date)"
    log_info "Text report:  ${REPORT_TXT}"
    log_info "JSON summary: ${REPORT_JSON}"

    build_json
}

main "$@"
