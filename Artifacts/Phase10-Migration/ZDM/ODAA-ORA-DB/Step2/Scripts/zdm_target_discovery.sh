#!/bin/bash
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration
# ==============================================================================
# ZDM Step 2 — Target Database Discovery (Oracle Database@Azure / Exadata)
# Project  : ODAA-ORA-DB
# Generated: 2026-03-16
#
# Runs on TARGET server (10.200.0.250) as opc.
# SQL executed via: sudo -u oracle (when whoami != oracle)
#
# Outputs (written to CWD — orchestrator SCPs them back):
#   zdm_target_discovery_<hostname>_<timestamp>.txt
#   zdm_target_discovery_<hostname>_<timestamp>.json
# ==============================================================================

ORACLE_USER="${ORACLE_USER:-oracle}"
TARGET_REMOTE_ORACLE_HOME="${TARGET_REMOTE_ORACLE_HOME:-}"
TARGET_ORACLE_SID="${TARGET_ORACLE_SID:-}"

HOSTNAME_LOCAL="$(hostname)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OUTPUT_DIR="$(pwd)"
REPORT_TXT="${OUTPUT_DIR}/zdm_target_discovery_${HOSTNAME_LOCAL}_${TIMESTAMP}.txt"
REPORT_JSON="${OUTPUT_DIR}/zdm_target_discovery_${HOSTNAME_LOCAL}_${TIMESTAMP}.json"

WARNINGS=()
SECTION_STATUSES=()

# ── Logging ───────────────────────────────────────────────────────────────────
log_info()  { echo "[INFO]  $*" | tee -a "$REPORT_TXT"; }
log_warn()  { echo "[WARN]  $*" | tee -a "$REPORT_TXT"; WARNINGS+=("$*"); }
log_error() { echo "[ERROR] $*" | tee -a "$REPORT_TXT"; }
log_raw()   { echo "$*"         | tee -a "$REPORT_TXT"; }
section()   { log_raw ""; log_raw "$(printf '=%.0s' {1..70})"; log_raw "  $*"; log_raw "$(printf '=%.0s' {1..70})"; }

# ── Oracle environment detection ──────────────────────────────────────────────
detect_oracle_env() {
    if [[ -n "$TARGET_REMOTE_ORACLE_HOME" ]]; then
        ORACLE_HOME="$TARGET_REMOTE_ORACLE_HOME"
        log_info "ORACLE_HOME set by override: $ORACLE_HOME"
    fi
    if [[ -n "$TARGET_ORACLE_SID" ]]; then
        ORACLE_SID="$TARGET_ORACLE_SID"
        log_info "ORACLE_SID set by override: $ORACLE_SID"
    fi

    if [[ -z "${ORACLE_HOME:-}" ]]; then
        if [[ -f /etc/oratab ]]; then
            ORATAB_ENTRY=$(grep -v '^#' /etc/oratab | grep -v '^$' | grep ':Y$\|:y$' | head -1)
            if [[ -z "$ORATAB_ENTRY" ]]; then
                ORATAB_ENTRY=$(grep -v '^#' /etc/oratab | grep -v '^$' | grep -v '^\+ASM' | head -1)
            fi
            if [[ -n "$ORATAB_ENTRY" ]]; then
                [[ -z "${ORACLE_SID:-}"  ]] && ORACLE_SID="$(echo "$ORATAB_ENTRY"  | cut -d: -f1)"
                [[ -z "${ORACLE_HOME:-}" ]] && ORACLE_HOME="$(echo "$ORATAB_ENTRY" | cut -d: -f2)"
                log_info "ORACLE_SID/HOME from /etc/oratab: $ORACLE_SID / $ORACLE_HOME"
            fi
        fi
    fi

    if [[ -z "${ORACLE_SID:-}" ]]; then
        PMON_SID=$(ps -ef | grep ora_pmon_ | grep -v grep | grep -v ASM | head -1 | sed 's/.*ora_pmon_//')
        if [[ -n "$PMON_SID" ]]; then
            ORACLE_SID="$PMON_SID"
            log_info "ORACLE_SID from pmon: $ORACLE_SID"
        fi
    fi

    if [[ -z "${ORACLE_HOME:-}" ]]; then
        for p in /u01/app/oracle/product/*/dbhome_1 /u02/app/oracle/product/*/dbhome_1 \
                  /u01/app/oracle/product/*/db_home /opt/oracle/product/*/dbhome_1; do
            EXPANDED=$(ls -d $p 2>/dev/null | head -1)
            if [[ -n "$EXPANDED" && -x "${EXPANDED}/bin/sqlplus" ]]; then
                ORACLE_HOME="$EXPANDED"
                log_info "ORACLE_HOME from common path: $ORACLE_HOME"
                break
            fi
        done
    fi

    export ORACLE_HOME ORACLE_SID
    if [[ -z "${ORACLE_HOME:-}" || -z "${ORACLE_SID:-}" ]]; then
        log_warn "Could not fully detect ORACLE_HOME/ORACLE_SID. SQL sections may fail."
    fi
}

# ── ASM environment detection ─────────────────────────────────────────────────
detect_asm_env() {
    GRID_HOME=""
    for p in /u01/app/grid/product/* /u01/app/*/grid /u02/app/grid/product/* \
              /opt/oracle/grid /u01/grid; do
        EXPANDED=$(ls -d $p 2>/dev/null | head -1)
        if [[ -n "$EXPANDED" && -x "${EXPANDED}/bin/asmcmd" ]]; then
            GRID_HOME="$EXPANDED"
            break
        fi
    done
    ASM_SID=$(ps -ef | grep asm_pmon_ | grep -v grep | head -1 | sed 's/.*asm_pmon_//')
    export GRID_HOME ASM_SID
}

# ── SQL runner ────────────────────────────────────────────────────────────────
run_sql() {
    local sqltext="$1"
    if [[ "$(whoami)" != "$ORACLE_USER" ]]; then
        echo "$sqltext" | sudo -u "$ORACLE_USER" \
            env ORACLE_HOME="${ORACLE_HOME:-}" ORACLE_SID="${ORACLE_SID:-}" \
            "${ORACLE_HOME:-/usr}/bin/sqlplus" -s / as sysdba 2>&1
    else
        echo "$sqltext" | \
            env ORACLE_HOME="${ORACLE_HOME:-}" ORACLE_SID="${ORACLE_SID:-}" \
            "${ORACLE_HOME:-/usr}/bin/sqlplus" -s / as sysdba 2>&1
    fi
}

run_asmcmd() {
    local cmd="$1"
    if [[ -n "$GRID_HOME" && -x "$GRID_HOME/bin/asmcmd" ]]; then
        if [[ "$(whoami)" != "grid" && "$(whoami)" != "$ORACLE_USER" ]]; then
            sudo -u grid env ORACLE_HOME="$GRID_HOME" ORACLE_SID="${ASM_SID:-+ASM1}" \
                "$GRID_HOME/bin/asmcmd" $cmd 2>&1
        else
            env ORACLE_HOME="$GRID_HOME" ORACLE_SID="${ASM_SID:-+ASM1}" \
                "$GRID_HOME/bin/asmcmd" $cmd 2>&1
        fi
    else
        echo "(asmcmd not available)"
    fi
}

SQL_HEADER="SET LINESIZE 200 PAGESIZE 200 FEEDBACK OFF HEADING ON TRIMSPOOL ON"
SQL_NOHEAD="SET LINESIZE 200 PAGESIZE 0 FEEDBACK OFF HEADING OFF TRIMSPOOL ON"

# ── Header ────────────────────────────────────────────────────────────────────
> "$REPORT_TXT"
log_raw "ZDM TARGET DISCOVERY REPORT"
log_raw "Project  : ODAA-ORA-DB"
log_raw "Host     : ${HOSTNAME_LOCAL}"
log_raw "Timestamp: ${TIMESTAMP}"
log_raw "Run by   : $(whoami)"
log_raw "$(printf '=%.0s' {1..70})"

detect_oracle_env
detect_asm_env

IS_CDB=""
DB_NAME=""
DB_UNIQUE_NAME=""
DB_ROLE=""
OPEN_MODE=""
DB_CHARSET=""

# ══════════════════════════════════════════════════════════════════════════════
section "1. OS INFORMATION"
# ══════════════════════════════════════════════════════════════════════════════
log_info "Hostname     : $(hostname -f 2>/dev/null || hostname)"
log_raw  "IP Addresses :"
ip addr show 2>/dev/null | grep 'inet ' | awk '{print "  " $2}' | tee -a "$REPORT_TXT" || \
    ifconfig 2>/dev/null | grep 'inet ' | awk '{print "  " $2}' | tee -a "$REPORT_TXT"
log_raw  "OS Version   :"
cat /etc/os-release 2>/dev/null | tee -a "$REPORT_TXT" || uname -a | tee -a "$REPORT_TXT"
log_raw  "Kernel       : $(uname -r)"
log_raw  "Disk Space   :"
df -h 2>/dev/null | tee -a "$REPORT_TXT"
SECTION_STATUSES+=("os:success")

# ══════════════════════════════════════════════════════════════════════════════
section "2. ORACLE ENVIRONMENT"
# ══════════════════════════════════════════════════════════════════════════════
log_info "ORACLE_HOME  : ${ORACLE_HOME:-NOT DETECTED}"
log_info "ORACLE_SID   : ${ORACLE_SID:-NOT DETECTED}"
log_info "GRID_HOME    : ${GRID_HOME:-NOT DETECTED}"
log_info "ASM_SID      : ${ASM_SID:-NOT DETECTED}"

if [[ -n "${ORACLE_HOME:-}" ]]; then
    log_raw "Oracle version:"
    run_sql "${SQL_NOHEAD}
SELECT banner FROM v\$version WHERE rownum=1;" | tee -a "$REPORT_TXT"
    SECTION_STATUSES+=("oracle_env:success")
else
    log_warn "sqlplus not found — skipping Oracle version"
    SECTION_STATUSES+=("oracle_env:partial")
fi

# ══════════════════════════════════════════════════════════════════════════════
section "3. DATABASE CONFIGURATION"
# ══════════════════════════════════════════════════════════════════════════════
if [[ -n "${ORACLE_HOME:-}" ]]; then
    run_sql "${SQL_HEADER}
SELECT name, db_unique_name, database_role, open_mode, log_mode, cdb, platform_name
FROM   v\$database;" | tee -a "$REPORT_TXT"

    DB_NAME=$(run_sql "${SQL_NOHEAD}
SELECT name FROM v\$database;" 2>/dev/null | tr -d ' \n')
    DB_UNIQUE_NAME=$(run_sql "${SQL_NOHEAD}
SELECT db_unique_name FROM v\$database;" 2>/dev/null | tr -d ' \n')
    DB_ROLE=$(run_sql "${SQL_NOHEAD}
SELECT database_role FROM v\$database;" 2>/dev/null | tr -d ' \n')
    OPEN_MODE=$(run_sql "${SQL_NOHEAD}
SELECT open_mode FROM v\$database;" 2>/dev/null | tr -d ' \n')
    IS_CDB=$(run_sql "${SQL_NOHEAD}
SELECT cdb FROM v\$database;" 2>/dev/null | tr -d ' \n')
    DB_CHARSET=$(run_sql "${SQL_NOHEAD}
SELECT value FROM nls_database_parameters WHERE parameter='NLS_CHARACTERSET';" 2>/dev/null | tr -d ' \n')

    log_raw ""
    log_raw "Character Sets:"
    run_sql "${SQL_HEADER}
SELECT parameter, value FROM nls_database_parameters
WHERE  parameter IN ('NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET');" | tee -a "$REPORT_TXT"

    SECTION_STATUSES+=("db_config:success")
else
    log_warn "Skipping database configuration — Oracle not detected"
    SECTION_STATUSES+=("db_config:skipped")
fi

# ══════════════════════════════════════════════════════════════════════════════
section "4. CONTAINER DATABASE (CDB/PDB)"
# ══════════════════════════════════════════════════════════════════════════════
if [[ -n "${ORACLE_HOME:-}" ]]; then
    if [[ "$IS_CDB" == "YES" ]]; then
        log_info "Database IS a CDB"
        run_sql "${SQL_HEADER}
SELECT con_id, name, open_mode, restricted FROM v\$pdbs ORDER BY con_id;" | tee -a "$REPORT_TXT"

        log_raw ""
        log_raw "Pre-created PDB check (any MOUNTED or READ WRITE PDB other than PDB\$SEED):"
        run_sql "${SQL_HEADER}
SELECT con_id, name, open_mode FROM v\$pdbs
WHERE  name != 'PDB\$SEED'
ORDER  BY con_id;" | tee -a "$REPORT_TXT"
    else
        log_info "Database is NOT a CDB"
    fi
    SECTION_STATUSES+=("cdb_pdb:success")
else
    log_warn "Skipping CDB/PDB — Oracle not detected"
    SECTION_STATUSES+=("cdb_pdb:skipped")
fi

# ══════════════════════════════════════════════════════════════════════════════
section "5. TDE STATUS"
# ══════════════════════════════════════════════════════════════════════════════
if [[ -n "${ORACLE_HOME:-}" ]]; then
    run_sql "${SQL_HEADER}
SELECT wrl_type, wrl_parameter, status, wallet_type FROM v\$encryption_wallet;" | tee -a "$REPORT_TXT"
    SECTION_STATUSES+=("tde:success")
else
    log_warn "Skipping TDE — Oracle not detected"
    SECTION_STATUSES+=("tde:skipped")
fi

# ══════════════════════════════════════════════════════════════════════════════
section "6. ASM STORAGE"
# ══════════════════════════════════════════════════════════════════════════════
if [[ -n "${ORACLE_HOME:-}" ]]; then
    log_raw "ASM disk groups (via v\$asm_diskgroup):"
    run_sql "${SQL_HEADER}
SELECT group_number, name,
       ROUND(total_mb/1024,2)  total_gb,
       ROUND(free_mb/1024,2)   free_gb,
       ROUND((total_mb-free_mb)*100/NULLIF(total_mb,0),1) pct_used,
       type redundancy, state
FROM v\$asm_diskgroup
ORDER BY name;" | tee -a "$REPORT_TXT"
fi

log_raw ""
log_raw "asmcmd lsdg:"
run_asmcmd "lsdg" | tee -a "$REPORT_TXT"

log_raw ""
log_raw "Tablespace / ASM file storage:"
if [[ -n "${ORACLE_HOME:-}" ]]; then
    run_sql "${SQL_HEADER}
SELECT tablespace_name,
       ROUND(SUM(bytes)/1024/1024/1024,2) total_gb,
       MAX(autoextensible)                autoextend
FROM   dba_data_files
GROUP  BY tablespace_name
ORDER  BY total_gb DESC;" | tee -a "$REPORT_TXT"
fi
SECTION_STATUSES+=("storage:success")

# ══════════════════════════════════════════════════════════════════════════════
section "7. NETWORK (LISTENER / TNS)"
# ══════════════════════════════════════════════════════════════════════════════
log_raw "Listener status:"
if [[ -n "${ORACLE_HOME:-}" && -x "${ORACLE_HOME}/bin/lsnrctl" ]]; then
    "${ORACLE_HOME}/bin/lsnrctl" status 2>&1 | tee -a "$REPORT_TXT"
fi

log_raw ""
log_raw "SCAN listener (if RAC):"
if [[ -n "$GRID_HOME" && -x "$GRID_HOME/bin/lsnrctl" ]]; then
    "$GRID_HOME/bin/lsnrctl" status LISTENER_SCAN1 2>&1 | tee -a "$REPORT_TXT" || true
    "$GRID_HOME/bin/lsnrctl" status LISTENER_SCAN2 2>&1 | tee -a "$REPORT_TXT" || true
fi

log_raw ""
log_raw "tnsnames.ora:"
for f in "${ORACLE_HOME:-/dev/null}/network/admin/tnsnames.ora" \
          "/etc/tnsnames.ora"; do
    if [[ -f "$f" ]]; then
        log_raw "  File: $f"
        cat "$f" 2>/dev/null | tee -a "$REPORT_TXT"
    fi
done
SECTION_STATUSES+=("network:success")

# ══════════════════════════════════════════════════════════════════════════════
section "8. OCI / AZURE INTEGRATION"
# ══════════════════════════════════════════════════════════════════════════════
log_raw "OCI CLI version:"
oci --version 2>&1 | tee -a "$REPORT_TXT" || log_info "(oci CLI not installed or not in PATH)"

log_raw ""
log_raw "OCI config (~/.oci/config) - masked:"
if [[ -f ~/.oci/config ]]; then
    grep -v 'key_file\|fingerprint' ~/.oci/config 2>/dev/null | tee -a "$REPORT_TXT"
    grep 'fingerprint' ~/.oci/config | sed 's/=.*/= ***MASKED***/' | tee -a "$REPORT_TXT" || true
else
    log_info "(~/.oci/config not found)"
fi

log_raw ""
log_raw "OCI API key file:"
OCI_KEY_PATH=$(grep 'key_file' ~/.oci/config 2>/dev/null | head -1 | cut -d= -f2 | tr -d ' ')
if [[ -n "$OCI_KEY_PATH" && -f "$OCI_KEY_PATH" ]]; then
    ls -la "$OCI_KEY_PATH" 2>/dev/null | tee -a "$REPORT_TXT"
else
    log_info "(OCI API key path not found or config missing)"
fi

log_raw ""
log_raw "OCI connectivity test:"
oci iam region list --output table 2>&1 | head -10 | tee -a "$REPORT_TXT" || \
    log_warn "OCI CLI connectivity test failed — check ~/.oci/config and API key"

log_raw ""
log_raw "Azure IMDS (instance metadata):"
curl -s -H "Metadata: true" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" \
     --connect-timeout 5 2>/dev/null | \
     python3 -m json.tool 2>/dev/null | head -30 | tee -a "$REPORT_TXT" || \
    log_info "(Azure IMDS not available)"

SECTION_STATUSES+=("oci_azure:success")

# ══════════════════════════════════════════════════════════════════════════════
section "9. GRID INFRASTRUCTURE / CRS"
# ══════════════════════════════════════════════════════════════════════════════
if [[ -n "$GRID_HOME" ]]; then
    log_raw "CRS status:"
    "$GRID_HOME/bin/crsctl" status resource -t 2>&1 | tee -a "$REPORT_TXT" || true

    log_raw ""
    log_raw "Cluster node list:"
    "$GRID_HOME/bin/olsnodes" -n 2>&1 | tee -a "$REPORT_TXT" || true

    log_raw ""
    log_raw "RAC instances:"
    if [[ -n "${ORACLE_HOME:-}" ]]; then
        run_sql "${SQL_HEADER}
SELECT inst_id, instance_name, host_name, status, database_status
FROM   gv\$instance
ORDER  BY inst_id;" | tee -a "$REPORT_TXT"
    fi
    SECTION_STATUSES+=("grid:success")
else
    log_info "Grid Infrastructure not detected (single-instance or Grid not in common paths)"
    SECTION_STATUSES+=("grid:skipped")
fi

# ══════════════════════════════════════════════════════════════════════════════
section "10. NETWORK SECURITY (FIREWALL / NSG)"
# ══════════════════════════════════════════════════════════════════════════════
log_raw "iptables rules (Oracle ports 22, 1521, 2484):"
iptables -L INPUT -n 2>/dev/null | grep -E '22|1521|2484|ACCEPT|DROP|REJECT' | \
    tee -a "$REPORT_TXT" || log_info "(iptables not available or no matching rules)"

log_raw ""
log_raw "firewalld status:"
systemctl is-active firewalld 2>/dev/null | tee -a "$REPORT_TXT" || true
firewall-cmd --list-ports 2>/dev/null | tee -a "$REPORT_TXT" || true
firewall-cmd --list-services 2>/dev/null | tee -a "$REPORT_TXT" || true

log_raw ""
log_raw "OCI NSG rules (requires OCI CLI):"
OCI_INST_OCID=$(curl -s -H "opc-request-id: zdmdiscovery" \
    "http://169.254.169.254/opc/v1/instance/" --connect-timeout 5 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null || echo "")
if [[ -n "$OCI_INST_OCID" ]]; then
    log_info "OCI instance OCID: $OCI_INST_OCID"
    oci compute instance get --instance-id "$OCI_INST_OCID" \
        --query 'data."source-details"' 2>/dev/null | head -10 | tee -a "$REPORT_TXT" || true
else
    log_info "(OCI instance metadata not available — skipping NSG query)"
fi
SECTION_STATUSES+=("firewall:success")

# ══════════════════════════════════════════════════════════════════════════════
section "SUMMARY"
# ══════════════════════════════════════════════════════════════════════════════
OVERALL_STATUS="success"
if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    OVERALL_STATUS="partial"
    log_raw ""
    log_raw "WARNINGS requiring attention:"
    for w in "${WARNINGS[@]}"; do
        log_raw "  [!] $w"
    done
fi
log_raw ""
log_raw "Section statuses: ${SECTION_STATUSES[*]}"
log_raw "Report: $REPORT_TXT"
log_raw "JSON  : $REPORT_JSON"

# ── JSON output ───────────────────────────────────────────────────────────────
_esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g'; }
_arr() { local out; for v in "$@"; do out+="\"$(_esc "$v")\","; done; echo "[${out%,}]"; }
WARN_JSON=$(_arr "${WARNINGS[@]+"${WARNINGS[@]}"}")

cat > "$REPORT_JSON" <<JSONEOF
{
  "report": "zdm_target_discovery",
  "project": "ODAA-ORA-DB",
  "timestamp": "${TIMESTAMP}",
  "hostname": "$(_esc "$HOSTNAME_LOCAL")",
  "run_by": "$(whoami)",
  "overall_status": "${OVERALL_STATUS}",
  "oracle": {
    "oracle_home": "$(_esc "${ORACLE_HOME:-}")",
    "oracle_sid": "$(_esc "${ORACLE_SID:-}")",
    "grid_home": "$(_esc "${GRID_HOME:-}")",
    "asm_sid": "$(_esc "${ASM_SID:-}")",
    "db_name": "$(_esc "${DB_NAME:-}")",
    "db_unique_name": "$(_esc "${DB_UNIQUE_NAME:-}")",
    "db_role": "$(_esc "${DB_ROLE:-}")",
    "open_mode": "$(_esc "${OPEN_MODE:-}")",
    "is_cdb": "$(_esc "${IS_CDB:-}")",
    "charset": "$(_esc "${DB_CHARSET:-}")"
  },
  "sections": $(printf '['; printf '"%s",' "${SECTION_STATUSES[@]}"; printf ']' | sed 's/,]$/]/'),
  "warnings": ${WARN_JSON},
  "report_txt": "$(_esc "$REPORT_TXT")"
}
JSONEOF

echo ""
echo "======================================================================"
echo " TARGET DISCOVERY COMPLETE — ${OVERALL_STATUS^^}"
echo " Reports: ${OUTPUT_DIR}"
echo "======================================================================"
