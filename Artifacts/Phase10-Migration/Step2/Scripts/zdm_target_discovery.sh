#!/bin/bash
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration
#
# zdm_target_discovery.sh
# ZDM Step 2 — Target Oracle Database Server Discovery
#
# Purpose  : Collect read-only diagnostics from the target Oracle DB server.
# Auth     : SSH as TARGET_ADMIN_USER (opc), then SQL as oracle via sudo.
# Outputs  : zdm_target_discovery_<hostname>_<ts>.txt
#            zdm_target_discovery_<hostname>_<ts>.json
# Run on   : ZDM server as zdmuser, or directly on target server as oracle/admin.
#
# NOTE: This script is intended to run remotely on the target server. The
# zdm_orchestrate_discovery.sh script handles SSH transport automatically.
# To run manually, SSH to the target server first:
#   ssh opc@10.200.0.250
#   sudo bash zdm_target_discovery.sh

set -u

# ---------------------------------------------------------------------------
# Configuration — override with environment variables when running standalone
# ---------------------------------------------------------------------------
TARGET_REMOTE_ORACLE_HOME="${TARGET_REMOTE_ORACLE_HOME:-/u02/app/oracle/product/19.0.0.0/dbhome_1}"
TARGET_ORACLE_SID="${TARGET_ORACLE_SID:-POCAKV1}"
TARGET_DATABASE_UNIQUE_NAME="${TARGET_DATABASE_UNIQUE_NAME:-POCAKV_ODAA}"
ORACLE_USER="${ORACLE_USER:-oracle}"

# ---------------------------------------------------------------------------
# Timing and output setup
# ---------------------------------------------------------------------------
ts="$(date +%Y%m%d-%H%M%S)"
run_host="$(hostname 2>/dev/null || echo unknown)"
run_user="$(id -un 2>/dev/null || echo unknown)"
output_dir="${OUTPUT_DIR:-$PWD}"
txt_report="${output_dir}/zdm_target_discovery_${run_host}_${ts}.txt"
json_report="${output_dir}/zdm_target_discovery_${run_host}_${ts}.json"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
escape_json() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\r'/}"; s="${s//$'\t'/\\t}"
  printf -- '%s' "${s}"
}

section() { printf -- '\n=== %s ===\n' "$1" | tee -a "${txt_report}"; }
emit()    { printf -- '%s\n' "$1" | tee -a "${txt_report}"; }

warnings=()
warn() { warnings+=("$1"); emit "[WARN] $1"; }

# ---------------------------------------------------------------------------
# Oracle environment detection
# ---------------------------------------------------------------------------
detect_oracle_env() {
  local detected_home="" detected_sid=""

  # 1. Existing environment
  [[ -n "${ORACLE_HOME:-}" ]] && detected_home="${ORACLE_HOME}"
  [[ -n "${ORACLE_SID:-}"  ]] && detected_sid="${ORACLE_SID}"

  # 2. Configured values
  [[ -z "${detected_home}" && -n "${TARGET_REMOTE_ORACLE_HOME}" ]] && detected_home="${TARGET_REMOTE_ORACLE_HOME}"
  [[ -z "${detected_sid}"  && -n "${TARGET_ORACLE_SID}" ]]         && detected_sid="${TARGET_ORACLE_SID}"

  # 3. /etc/oratab
  if [[ -z "${detected_home}" || -z "${detected_sid}" ]] && [[ -f /etc/oratab ]]; then
    local first_entry
    first_entry=$(grep -v '^#' /etc/oratab | grep -v '^[[:space:]]*$' | head -1)
    if [[ -n "${first_entry}" ]]; then
      local oratab_sid oratab_home
      oratab_sid="${first_entry%%:*}"
      oratab_home="$(echo "${first_entry}" | cut -d: -f2)"
      [[ -z "${detected_sid}"  ]] && detected_sid="${oratab_sid}"
      [[ -z "${detected_home}" ]] && detected_home="${oratab_home}"
    fi
  fi

  # 4. PMON process detection
  if [[ -z "${detected_sid}" ]]; then
    local pmon_sid
    pmon_sid=$(ps -ef 2>/dev/null | grep 'ora_pmon_' | grep -v grep | head -1 | sed 's/.*ora_pmon_//')
    [[ -n "${pmon_sid}" ]] && detected_sid="${pmon_sid}"
  fi

  # 5. Common Oracle home paths
  if [[ -z "${detected_home}" ]]; then
    for p in /u02/app/oracle/product/19.0.0.0/dbhome_1 /u01/app/oracle/product/19.0.0/dbhome_1 \
              /u01/app/oracle/product/12.2.0/dbhome_1 /oracle/product/19.0.0/dbhome_1; do
      if [[ -d "${p}" ]]; then
        detected_home="${p}"
        break
      fi
    done
  fi

  ORACLE_HOME="${detected_home}"
  ORACLE_SID="${detected_sid}"
  export ORACLE_HOME ORACLE_SID
}

run_sql_as_oracle() {
  local sql="$1"
  if [[ "${run_user}" == "${ORACLE_USER}" ]]; then
    ORACLE_HOME="${ORACLE_HOME}" ORACLE_SID="${ORACLE_SID}" \
      "${ORACLE_HOME}/bin/sqlplus" -s /nolog <<EOF
connect / as sysdba
set pagesize 200
set linesize 200
set feedback off
set heading on
${sql}
exit
EOF
  else
    sudo -u "${ORACLE_USER}" \
      env ORACLE_HOME="${ORACLE_HOME}" ORACLE_SID="${ORACLE_SID}" \
      "${ORACLE_HOME}/bin/sqlplus" -s /nolog <<EOF
connect / as sysdba
set pagesize 200
set linesize 200
set feedback off
set heading on
${sql}
exit
EOF
  fi
}

# ---------------------------------------------------------------------------
# Initialize report
# ---------------------------------------------------------------------------
mkdir -p "${output_dir}"
printf -- '# ZDM Step 2 — Target Discovery Report\n' > "${txt_report}"
printf -- 'Generated: %s\nHost: %s\nUser: %s\n' "${ts}" "${run_host}" "${run_user}" >> "${txt_report}"

# ---------------------------------------------------------------------------
# Section 1: Connectivity and auth context
# ---------------------------------------------------------------------------
section "1. Connectivity and Auth Context"
emit "Target host        : ${run_host}"
emit "Script run user    : ${run_user}"
emit "Oracle user        : ${ORACLE_USER}"
emit "TARGET_ORACLE_SID  : ${TARGET_ORACLE_SID}"
emit "TARGET_UNIQUE_NAME : ${TARGET_DATABASE_UNIQUE_NAME}"

# ---------------------------------------------------------------------------
# Section 2: Remote system details
# ---------------------------------------------------------------------------
section "2. Remote System Details"
emit "Hostname : $(hostname -f 2>/dev/null || hostname)"
emit "OS       : $(uname -a)"
if [[ -f /etc/os-release ]]; then
  emit "OS Release:"
  cat /etc/os-release | tee -a "${txt_report}" || true
fi
emit "Kernel   : $(uname -r)"
emit "Uptime   : $(uptime 2>/dev/null || echo 'unavailable')"

# ---------------------------------------------------------------------------
# Section 3: Oracle environment details
# ---------------------------------------------------------------------------
section "3. Oracle Environment Details"
detect_oracle_env
emit "ORACLE_HOME (resolved) : ${ORACLE_HOME:-not detected}"
emit "ORACLE_SID  (resolved) : ${ORACLE_SID:-not detected}"

if [[ -z "${ORACLE_HOME}" ]]; then
  warn "ORACLE_HOME could not be detected; SQL sections will be skipped."
fi
if [[ -z "${ORACLE_SID}" ]]; then
  warn "ORACLE_SID could not be detected; SQL sections will be skipped."
fi

emit ""
emit "--- /etc/oratab entries ---"
if [[ -f /etc/oratab ]]; then
  cat /etc/oratab | grep -v '^#' | grep -v '^[[:space:]]*$' | tee -a "${txt_report}" || true
else
  emit "(not found)"
fi

emit ""
emit "--- PMON SIDs detected ---"
ps -ef 2>/dev/null | grep 'ora_pmon_' | grep -v grep | tee -a "${txt_report}" || emit "(no pmon processes found)"

emit ""
emit "--- sqlplus version ---"
if [[ -n "${ORACLE_HOME}" && -x "${ORACLE_HOME}/bin/sqlplus" ]]; then
  "${ORACLE_HOME}/bin/sqlplus" -V 2>&1 | tee -a "${txt_report}" || emit "(sqlplus -V failed)"
else
  emit "(sqlplus not found)"
fi

# ---------------------------------------------------------------------------
# Section 4: Database configuration
# ---------------------------------------------------------------------------
section "4. Database Configuration"
if [[ -n "${ORACLE_HOME}" && -n "${ORACLE_SID}" ]]; then
  emit "--- DB Name / Unique Name / Role / Open Mode / Character Set ---"
  run_sql_as_oracle "
SELECT name, db_unique_name, database_role, open_mode, log_mode FROM v\$database;
SELECT property_name, property_value FROM database_properties
WHERE  property_name IN ('NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET');
" 2>&1 | tee -a "${txt_report}" || warn "Section 4 SQL query failed."
else
  warn "Skipping Section 4: Oracle environment not detected."
fi

# ---------------------------------------------------------------------------
# Section 5: CDB / PDB posture
# ---------------------------------------------------------------------------
section "5. CDB/PDB Posture"
if [[ -n "${ORACLE_HOME}" && -n "${ORACLE_SID}" ]]; then
  run_sql_as_oracle "
SELECT cdb, con_id FROM v\$database;
SELECT con_id, name, open_mode, restricted FROM v\$pdbs ORDER BY con_id;
" 2>&1 | tee -a "${txt_report}" || warn "Section 5 SQL query failed."
else
  warn "Skipping Section 5: Oracle environment not detected."
fi

# ---------------------------------------------------------------------------
# Section 6: TDE wallet status
# ---------------------------------------------------------------------------
section "6. TDE Wallet Status"
if [[ -n "${ORACLE_HOME}" && -n "${ORACLE_SID}" ]]; then
  run_sql_as_oracle "
SELECT * FROM v\$encryption_wallet;
SELECT tablespace_name, encrypted FROM dba_tablespaces WHERE encrypted = 'YES';
" 2>&1 | tee -a "${txt_report}" || warn "Section 6 TDE query failed."
else
  warn "Skipping Section 6: Oracle environment not detected."
fi

# ---------------------------------------------------------------------------
# Section 7: Storage posture (ASM / Exadata)
# ---------------------------------------------------------------------------
section "7. Storage Posture"
emit "--- ASM disk groups ---"
if [[ -n "${ORACLE_HOME}" && -n "${ORACLE_SID}" ]]; then
  run_sql_as_oracle "
SELECT group_number, name, state, type, total_mb, free_mb,
       ROUND((free_mb/NULLIF(total_mb,0))*100,1) AS pct_free
FROM   v\$asm_diskgroup
ORDER BY name;
" 2>&1 | tee -a "${txt_report}" || warn "Section 7a ASM query failed (may be expected if no ASM)."
fi

emit "--- Disk / filesystem summary ---"
df -h 2>/dev/null | tee -a "${txt_report}" || emit "(df failed)"

emit "--- Exadata cell / grid disk details (if applicable) ---"
if command -v cellcli &>/dev/null; then
  cellcli -e list celldisk attributes name,disktype,size,freeSpace 2>&1 | tee -a "${txt_report}" || emit "(cellcli query failed)"
else
  emit "(cellcli not found — not an Exadata cell)"
fi

# ---------------------------------------------------------------------------
# Section 8: Network posture
# ---------------------------------------------------------------------------
section "8. Network Posture"
emit "--- Listener status ---"
if [[ -n "${ORACLE_HOME}" && -x "${ORACLE_HOME}/bin/lsnrctl" ]]; then
  "${ORACLE_HOME}/bin/lsnrctl" status 2>&1 | tee -a "${txt_report}" || emit "(lsnrctl status failed)"
else
  emit "(lsnrctl not found)"
fi

emit "--- SCAN listener (if applicable) ---"
if [[ -n "${ORACLE_HOME}" && -x "${ORACLE_HOME}/bin/lsnrctl" ]]; then
  "${ORACLE_HOME}/bin/lsnrctl" status LISTENER_SCAN1 2>&1 | tee -a "${txt_report}" || emit "(SCAN listener not found)"
fi

emit "--- tnsnames.ora ---"
local tns_path="${ORACLE_HOME:-}/network/admin/tnsnames.ora"
if [[ -f "${tns_path}" ]]; then
  cat "${tns_path}" | tee -a "${txt_report}"
else
  emit "(tnsnames.ora not found at ${tns_path})"
fi

emit "--- Network interfaces ---"
ip addr 2>/dev/null | tee -a "${txt_report}" || ifconfig 2>/dev/null | tee -a "${txt_report}" || emit "(ip/ifconfig unavailable)"

# ---------------------------------------------------------------------------
# Section 9: OCI / Azure integration metadata
# ---------------------------------------------------------------------------
section "9. OCI / Azure Integration Metadata (sanitized)"
if command -v oci &>/dev/null; then
  emit "--- OCI CLI version ---"
  oci --version 2>&1 | tee -a "${txt_report}" || emit "(oci --version failed)"
  emit "--- OCI config profiles (masked) ---"
  if [[ -f ~/.oci/config ]]; then
    grep -E '^\[|^region|^tenancy' ~/.oci/config | tee -a "${txt_report}" || true
  else
    emit "(~/.oci/config not found)"
  fi
else
  emit "(OCI CLI not installed — not required for ZDM migration execution)"
fi

emit "--- Azure IMDS metadata (sanitized, if applicable) ---"
if command -v curl &>/dev/null; then
  curl -s -m 3 -H "Metadata: true" \
    "http://169.254.169.254/metadata/instance?api-version=2021-02-01" 2>/dev/null \
    | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    keep = {k: d.get(k,'') for k in ['location','vmId','name','resourceGroupName','subscriptionId']}
    print(json.dumps(keep, indent=2))
except Exception:
    pass
" 2>/dev/null | tee -a "${txt_report}" || emit "(Azure IMDS not available)"
else
  emit "(curl not available for IMDS check)"
fi

# ---------------------------------------------------------------------------
# Section 10: Grid Infrastructure status (RAC / Exadata)
# ---------------------------------------------------------------------------
section "10. Grid Infrastructure Status"
gi_home="${ORACLE_HOME%/dbhome_*}/grid"
if [[ -d "${gi_home}" ]]; then
  emit "GI home detected: ${gi_home}"
  if [[ -x "${gi_home}/bin/crsctl" ]]; then
    "${gi_home}/bin/crsctl" status res -t 2>&1 | tee -a "${txt_report}" || emit "(crsctl query failed)"
    "${gi_home}/bin/olsnodes" 2>&1 | tee -a "${txt_report}" || emit "(olsnodes failed)"
  else
    emit "(crsctl not found at ${gi_home}/bin/)"
  fi
else
  emit "(Grid Infrastructure home not detected — single-instance assumed)"
fi

# ---------------------------------------------------------------------------
# Section 11: Network security checks
# ---------------------------------------------------------------------------
section "11. Network Security Checks"
emit "--- Port 22 (SSH) listening ---"
ss -tlnp 2>/dev/null | grep ':22' | tee -a "${txt_report}" || \
  netstat -tlnp 2>/dev/null | grep ':22' | tee -a "${txt_report}" || emit "(port check unavailable)"

emit "--- Port 1521 (Oracle listener) listening ---"
ss -tlnp 2>/dev/null | grep ':1521' | tee -a "${txt_report}" || \
  netstat -tlnp 2>/dev/null | grep ':1521' | tee -a "${txt_report}" || emit "(port check unavailable)"

# ---------------------------------------------------------------------------
# JSON summary
# ---------------------------------------------------------------------------
overall_status="success"
[[ ${#warnings[@]} -gt 0 ]] && overall_status="partial"

warnings_json=""
for w in "${warnings[@]}"; do
  warnings_json+="\"$(escape_json "${w}")\","
done
warnings_json="${warnings_json%,}"

cat > "${json_report}" <<JSON
{
  "step": "Step2-Target-Discovery",
  "status": "${overall_status}",
  "timestamp": "${ts}",
  "host": "$(escape_json "${run_host}")",
  "run_user": "$(escape_json "${run_user}")",
  "oracle_home": "$(escape_json "${ORACLE_HOME:-}")",
  "oracle_sid": "$(escape_json "${ORACLE_SID:-}")",
  "target_unique_name": "$(escape_json "${TARGET_DATABASE_UNIQUE_NAME}")",
  "txt_report": "$(escape_json "${txt_report}")",
  "warnings_count": ${#warnings[@]},
  "warnings": [${warnings_json}]
}
JSON

emit ""
emit "=== Discovery Complete ==="
emit "Status  : ${overall_status}"
emit "Report  : ${txt_report}"
emit "JSON    : ${json_report}"
[[ ${#warnings[@]} -gt 0 ]] && emit "Warnings: ${#warnings[@]} — review above [WARN] entries."

exit 0
