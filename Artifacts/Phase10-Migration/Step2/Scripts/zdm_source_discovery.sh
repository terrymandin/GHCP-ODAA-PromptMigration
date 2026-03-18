#!/bin/bash
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration
#
# zdm_source_discovery.sh
# ZDM Step 2 — Source Oracle Database Server Discovery
#
# Purpose  : Collect read-only diagnostics from the source Oracle DB server.
# Auth     : SSH as SOURCE_ADMIN_USER (azureuser), then SQL as oracle via sudo.
# Outputs  : zdm_source_discovery_<hostname>_<ts>.txt
#            zdm_source_discovery_<hostname>_<ts>.json
# Run on   : ZDM server as zdmuser, or directly on source server as oracle/admin.
#
# NOTE: This script is intended to run remotely on the source server. The
# zdm_orchestrate_discovery.sh script handles SSH transport automatically.
# To run manually, SSH to the source server first:
#   ssh azureuser@10.200.1.12
#   sudo bash zdm_source_discovery.sh

set -u

# ---------------------------------------------------------------------------
# Configuration — override with environment variables when running standalone
# ---------------------------------------------------------------------------
SOURCE_REMOTE_ORACLE_HOME="${SOURCE_REMOTE_ORACLE_HOME:-/u01/app/oracle/product/19.0.0/dbhome_1}"
SOURCE_ORACLE_SID="${SOURCE_ORACLE_SID:-POCAKV}"
SOURCE_DATABASE_UNIQUE_NAME="${SOURCE_DATABASE_UNIQUE_NAME:-POCAKV}"
ORACLE_USER="${ORACLE_USER:-oracle}"

# ---------------------------------------------------------------------------
# Timing and output setup
# ---------------------------------------------------------------------------
ts="$(date +%Y%m%d-%H%M%S)"
run_host="$(hostname 2>/dev/null || echo unknown)"
run_user="$(id -un 2>/dev/null || echo unknown)"
output_dir="${OUTPUT_DIR:-$PWD}"
txt_report="${output_dir}/zdm_source_discovery_${run_host}_${ts}.txt"
json_report="${output_dir}/zdm_source_discovery_${run_host}_${ts}.json"

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
  [[ -z "${detected_home}" && -n "${SOURCE_REMOTE_ORACLE_HOME}" ]] && detected_home="${SOURCE_REMOTE_ORACLE_HOME}"
  [[ -z "${detected_sid}"  && -n "${SOURCE_ORACLE_SID}" ]]         && detected_sid="${SOURCE_ORACLE_SID}"

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
    for p in /u01/app/oracle/product/19.0.0/dbhome_1 /u01/app/oracle/product/12.2.0/dbhome_1 \
              /u01/app/oracle/product/12.1.0/dbhome_1 /oracle/product/19.0.0/dbhome_1; do
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
printf -- '# ZDM Step 2 — Source Discovery Report\n' > "${txt_report}"
printf -- 'Generated: %s\nHost: %s\nUser: %s\n' "${ts}" "${run_host}" "${run_user}" >> "${txt_report}"

# ---------------------------------------------------------------------------
# Section 1: Connectivity and auth context
# ---------------------------------------------------------------------------
section "1. Connectivity and Auth Context"
emit "Source host        : ${run_host}"
emit "Script run user    : ${run_user}"
emit "Oracle user        : ${ORACLE_USER}"
emit "SOURCE_ORACLE_SID  : ${SOURCE_ORACLE_SID}"
emit "SOURCE_UNIQUE_NAME : ${SOURCE_DATABASE_UNIQUE_NAME}"

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
  emit "--- DB Name / Unique Name / Role / Open Mode / Character Sets ---"
  run_sql_as_oracle "
SELECT name, db_unique_name, database_role, open_mode, log_mode
FROM   v\$database;
SELECT property_name, property_value FROM database_properties
WHERE  property_name IN ('NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET');
SELECT force_logging, supplemental_log_data_min, supplemental_log_data_pk,
       supplemental_log_data_ui, supplemental_log_data_fk, supplemental_log_data_all
FROM   v\$database;
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
SELECT con_id, name, open_mode, restricted FROM v\$pdbs;
" 2>&1 | tee -a "${txt_report}" || warn "Section 5 SQL query failed."
else
  warn "Skipping Section 5: Oracle environment not detected."
fi

# ---------------------------------------------------------------------------
# Section 6: TDE status
# ---------------------------------------------------------------------------
section "6. TDE Status"
if [[ -n "${ORACLE_HOME}" && -n "${ORACLE_SID}" ]]; then
  emit "--- Wallet Status ---"
  run_sql_as_oracle "
SELECT * FROM v\$encryption_wallet;
" 2>&1 | tee -a "${txt_report}" || warn "Section 6a wallet query failed."
  emit "--- Encrypted Tablespaces ---"
  run_sql_as_oracle "
SELECT tablespace_name, encrypted FROM dba_tablespaces WHERE encrypted = 'YES';
" 2>&1 | tee -a "${txt_report}" || warn "Section 6b encrypted tablespaces query failed."

  emit "--- sqlnet.ora / encryption params ---"
  local sqlnet_path="${ORACLE_HOME}/network/admin/sqlnet.ora"
  if [[ -f "${sqlnet_path}" ]]; then
    grep -iE 'WALLET|ENCRYPT|SSL' "${sqlnet_path}" | tee -a "${txt_report}" || emit "(no matching entries)"
  else
    emit "(sqlnet.ora not found at ${sqlnet_path})"
  fi
else
  warn "Skipping Section 6: Oracle environment not detected."
fi

# ---------------------------------------------------------------------------
# Section 7: Tablespace / datafile posture
# ---------------------------------------------------------------------------
section "7. Tablespace and Datafile Posture"
if [[ -n "${ORACLE_HOME}" && -n "${ORACLE_SID}" ]]; then
  run_sql_as_oracle "
SELECT tablespace_name,
       ROUND(SUM(bytes)/1024/1024/1024,2)        AS size_gb,
       ROUND(SUM(maxbytes)/1024/1024/1024,2)     AS maxsize_gb,
       MAX(autoextensible)                        AS autoextend
FROM   dba_data_files
GROUP BY tablespace_name
ORDER BY tablespace_name;
SELECT file_name, bytes/1024/1024 AS mb, maxbytes/1024/1024 AS max_mb, autoextensible
FROM   dba_data_files
ORDER BY tablespace_name, file_name;
" 2>&1 | tee -a "${txt_report}" || warn "Section 7 SQL query failed."
else
  warn "Skipping Section 7: Oracle environment not detected."
fi

# ---------------------------------------------------------------------------
# Section 8: Redo / archive posture
# ---------------------------------------------------------------------------
section "8. Redo and Archive Posture"
if [[ -n "${ORACLE_HOME}" && -n "${ORACLE_SID}" ]]; then
  run_sql_as_oracle "
SELECT group#, members, bytes/1024/1024 AS mb, status FROM v\$log ORDER BY group#;
SELECT member FROM v\$logfile ORDER BY group#, member;
SELECT dest_name, status, target, archiver, destination FROM v\$archive_dest
WHERE  status != 'INACTIVE'
ORDER BY dest_id;
" 2>&1 | tee -a "${txt_report}" || warn "Section 8 SQL query failed."
else
  warn "Skipping Section 8: Oracle environment not detected."
fi

# ---------------------------------------------------------------------------
# Section 9: Network config
# ---------------------------------------------------------------------------
section "9. Network Configuration"
emit "--- Listener status ---"
if [[ -n "${ORACLE_HOME}" && -x "${ORACLE_HOME}/bin/lsnrctl" ]]; then
  "${ORACLE_HOME}/bin/lsnrctl" status 2>&1 | tee -a "${txt_report}" || emit "(lsnrctl status failed)"
else
  emit "(lsnrctl not found)"
fi
emit "--- tnsnames.ora ---"
local tns_path="${ORACLE_HOME:-}/network/admin/tnsnames.ora"
if [[ -f "${tns_path}" ]]; then
  cat "${tns_path}" | tee -a "${txt_report}"
else
  emit "(tnsnames.ora not found at ${tns_path})"
fi
emit "--- sqlnet.ora ---"
local sqlnet_path="${ORACLE_HOME:-}/network/admin/sqlnet.ora"
if [[ -f "${sqlnet_path}" ]]; then
  cat "${sqlnet_path}" | tee -a "${txt_report}"
else
  emit "(sqlnet.ora not found at ${sqlnet_path})"
fi

# ---------------------------------------------------------------------------
# Section 10: Authentication artifacts
# ---------------------------------------------------------------------------
section "10. Authentication Artifacts"
emit "--- Password file location ---"
local pfile="${ORACLE_HOME:-}/dbs/orapw${ORACLE_SID:-}"
if [[ -f "${pfile}" ]]; then
  ls -lh "${pfile}" | tee -a "${txt_report}"
else
  emit "(orapw${ORACLE_SID:-} not found at ${pfile:-<oracle_home>/dbs/})"
fi
emit "--- oracle user ~/.ssh directory ---"
if [[ -d "/home/${ORACLE_USER}/.ssh" ]]; then
  ls -la "/home/${ORACLE_USER}/.ssh" 2>/dev/null | tee -a "${txt_report}" || emit "(ls failed)"
elif [[ -d "/home/oracle/.ssh" ]]; then
  ls -la /home/oracle/.ssh 2>/dev/null | tee -a "${txt_report}" || emit "(ls failed)"
else
  emit "(.ssh directory not found for oracle user)"
fi

# ---------------------------------------------------------------------------
# Section 11: Schema posture
# ---------------------------------------------------------------------------
section "11. Schema Posture"
if [[ -n "${ORACLE_HOME}" && -n "${ORACLE_SID}" ]]; then
  run_sql_as_oracle "
SELECT owner,
       ROUND(SUM(bytes)/1024/1024/1024,3) AS size_gb,
       COUNT(*) AS segment_count
FROM   dba_segments
WHERE  owner NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','ORACLE_OCM',
                     'DIP','XDB','WMSYS','EXFSYS','CTXSYS','MDSYS','ORDDATA',
                     'ORDPLUGINS','ORDSYS','SI_INFORMTN_SCHEMA','LBACSYS','OLAPSYS',
                     'OWBSYS','SYSMAN','MGMT_VIEW')
GROUP BY owner
ORDER BY size_gb DESC;
SELECT status, COUNT(*) AS cnt FROM dba_objects
WHERE  owner NOT IN ('SYS','SYSTEM')
GROUP BY status
ORDER BY status;
" 2>&1 | tee -a "${txt_report}" || warn "Section 11 SQL query failed."
else
  warn "Skipping Section 11: Oracle environment not detected."
fi

# ---------------------------------------------------------------------------
# Section 12: Backup posture
# ---------------------------------------------------------------------------
section "12. Backup Posture"
if [[ -n "${ORACLE_HOME}" && -n "${ORACLE_SID}" ]]; then
  run_sql_as_oracle "
SELECT input_type, status, start_time, end_time, output_bytes/1024/1024 AS mb
FROM   v\$rman_backup_job_details
ORDER BY start_time DESC
FETCH FIRST 5 ROWS ONLY;
" 2>&1 | tee -a "${txt_report}" || warn "Section 12 SQL query failed (v\$rman_backup_job_details)."
  if [[ -x "${ORACLE_HOME}/bin/rman" ]]; then
    emit "--- RMAN show all config (read-only) ---"
    if [[ "${run_user}" == "${ORACLE_USER}" ]]; then
      ORACLE_HOME="${ORACLE_HOME}" ORACLE_SID="${ORACLE_SID}" \
        "${ORACLE_HOME}/bin/rman" target / <<'RMAN_EOF' 2>&1 | tee -a "${txt_report}"
show all;
exit;
RMAN_EOF
    else
      sudo -u "${ORACLE_USER}" env ORACLE_HOME="${ORACLE_HOME}" ORACLE_SID="${ORACLE_SID}" \
        "${ORACLE_HOME}/bin/rman" target / <<'RMAN_EOF' 2>&1 | tee -a "${txt_report}"
show all;
exit;
RMAN_EOF
    fi
  else
    emit "(rman not found)"
  fi
else
  warn "Skipping Section 12: Oracle environment not detected."
fi

# ---------------------------------------------------------------------------
# Section 13: Integration objects
# ---------------------------------------------------------------------------
section "13. Integration Objects"
if [[ -n "${ORACLE_HOME}" && -n "${ORACLE_SID}" ]]; then
  run_sql_as_oracle "
SELECT owner, db_link, username, host FROM dba_db_links ORDER BY owner, db_link;
SELECT owner, mview_name, refresh_mode, refresh_method, last_refresh_date
FROM   dba_mviews ORDER BY owner, mview_name;
SELECT owner, log_table, master FROM dba_mview_logs ORDER BY owner, master;
SELECT owner, job_name, job_type, state, last_start_date, next_run_date
FROM   dba_scheduler_jobs
WHERE  owner NOT IN ('SYS','SYSTEM')
ORDER BY owner, job_name;
" 2>&1 | tee -a "${txt_report}" || warn "Section 13 SQL query failed."
else
  warn "Skipping Section 13: Oracle environment not detected."
fi

# ---------------------------------------------------------------------------
# Section 14: Data Guard parameters
# ---------------------------------------------------------------------------
section "14. Data Guard Parameters"
if [[ -n "${ORACLE_HOME}" && -n "${ORACLE_SID}" ]]; then
  run_sql_as_oracle "
SELECT name, value FROM v\$parameter
WHERE  name IN ('log_archive_dest_1','log_archive_dest_2','log_archive_dest_state_1',
                'log_archive_dest_state_2','db_unique_name','log_archive_config',
                'fal_server','fal_client','standby_file_management',
                'log_file_name_convert','db_file_name_convert');
SELECT * FROM v\$dataguard_config;
" 2>&1 | tee -a "${txt_report}" || warn "Section 14 SQL query failed (may be expected if no DG)."
else
  warn "Skipping Section 14: Oracle environment not detected."
fi

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
  "step": "Step2-Source-Discovery",
  "status": "${overall_status}",
  "timestamp": "${ts}",
  "host": "$(escape_json "${run_host}")",
  "run_user": "$(escape_json "${run_user}")",
  "oracle_home": "$(escape_json "${ORACLE_HOME:-}")",
  "oracle_sid": "$(escape_json "${ORACLE_SID:-}")",
  "source_unique_name": "$(escape_json "${SOURCE_DATABASE_UNIQUE_NAME}")",
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
