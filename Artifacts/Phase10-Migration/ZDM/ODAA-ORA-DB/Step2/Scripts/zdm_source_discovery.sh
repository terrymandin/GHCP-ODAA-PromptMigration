#!/bin/bash
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration
# ==============================================================================
# ZDM Step 2 — Source Database Discovery
# Project  : ODAA-ORA-DB
# Generated: 2026-03-16
#
# Runs on SOURCE server (10.200.1.12) as azureuser.
# SQL executed via: sudo -u oracle (when whoami != oracle)
#
# Outputs (written to CWD — orchestrator SCPs them back):
#   zdm_source_discovery_<hostname>_<timestamp>.txt
#   zdm_source_discovery_<hostname>_<timestamp>.json
# ==============================================================================

ORACLE_USER="${ORACLE_USER:-oracle}"
SOURCE_REMOTE_ORACLE_HOME="${SOURCE_REMOTE_ORACLE_HOME:-}"
SOURCE_ORACLE_SID="${SOURCE_ORACLE_SID:-}"

HOSTNAME_LOCAL="$(hostname)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OUTPUT_DIR="$(pwd)"
REPORT_TXT="${OUTPUT_DIR}/zdm_source_discovery_${HOSTNAME_LOCAL}_${TIMESTAMP}.txt"
REPORT_JSON="${OUTPUT_DIR}/zdm_source_discovery_${HOSTNAME_LOCAL}_${TIMESTAMP}.json"

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
    # Priority 1: explicit overrides
    if [[ -n "$SOURCE_REMOTE_ORACLE_HOME" ]]; then
        ORACLE_HOME="$SOURCE_REMOTE_ORACLE_HOME"
        log_info "ORACLE_HOME set by override: $ORACLE_HOME"
    fi
    if [[ -n "$SOURCE_ORACLE_SID" ]]; then
        ORACLE_SID="$SOURCE_ORACLE_SID"
        log_info "ORACLE_SID set by override: $ORACLE_SID"
    fi

    # Priority 2: environment already set
    if [[ -z "$ORACLE_HOME" && -n "${ORACLE_HOME:-}" ]]; then
        log_info "ORACLE_HOME from environment: $ORACLE_HOME"
    fi
    if [[ -z "$ORACLE_SID" && -n "${ORACLE_SID:-}" ]]; then
        log_info "ORACLE_SID from environment: $ORACLE_SID"
    fi

    # Priority 3: /etc/oratab
    if [[ -z "$ORACLE_HOME" || -z "$ORACLE_SID" ]]; then
        if [[ -f /etc/oratab ]]; then
            ORATAB_ENTRY=$(grep -v '^#' /etc/oratab | grep -v '^$' | grep ':Y$\|:y$' | head -1)
            if [[ -z "$ORATAB_ENTRY" ]]; then
                ORATAB_ENTRY=$(grep -v '^#' /etc/oratab | grep -v '^$' | head -1)
            fi
            if [[ -n "$ORATAB_ENTRY" ]]; then
                [[ -z "$ORACLE_SID"  ]] && ORACLE_SID="$(echo "$ORATAB_ENTRY"  | cut -d: -f1)"
                [[ -z "$ORACLE_HOME" ]] && ORACLE_HOME="$(echo "$ORATAB_ENTRY" | cut -d: -f2)"
                log_info "ORACLE_SID/HOME from /etc/oratab: $ORACLE_SID / $ORACLE_HOME"
            fi
        fi
    fi

    # Priority 4: running pmon process
    if [[ -z "$ORACLE_SID" ]]; then
        PMON_SID=$(ps -ef | grep ora_pmon_ | grep -v grep | head -1 | sed 's/.*ora_pmon_//')
        if [[ -n "$PMON_SID" ]]; then
            ORACLE_SID="$PMON_SID"
            log_info "ORACLE_SID from pmon: $ORACLE_SID"
        fi
    fi

    # Priority 5: common paths
    if [[ -z "$ORACLE_HOME" ]]; then
        for p in /u01/app/oracle/product/*/dbhome_1 /u01/app/oracle/product/*/db_home \
                  /opt/oracle/product/*/dbhome_1 /oracle/product/*/dbhome_1; do
            EXPANDED=$(ls -d $p 2>/dev/null | head -1)
            if [[ -n "$EXPANDED" && -x "${EXPANDED}/bin/sqlplus" ]]; then
                ORACLE_HOME="$EXPANDED"
                log_info "ORACLE_HOME from common path: $ORACLE_HOME"
                break
            fi
        done
    fi

    export ORACLE_HOME ORACLE_SID
    if [[ -z "$ORACLE_HOME" || -z "$ORACLE_SID" ]]; then
        log_warn "Could not fully detect ORACLE_HOME/ORACLE_SID. SQL sections may fail."
    fi
}

# ── SQL runner ────────────────────────────────────────────────────────────────
run_sql() {
    local sqltext="$1"
    if [[ "$(whoami)" != "$ORACLE_USER" ]]; then
        echo "$sqltext" | sudo -u "$ORACLE_USER" \
            env ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" \
            "$ORACLE_HOME/bin/sqlplus" -s / as sysdba 2>&1
    else
        echo "$sqltext" | \
            env ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" \
            "$ORACLE_HOME/bin/sqlplus" -s / as sysdba 2>&1
    fi
}

SQL_HEADER="SET LINESIZE 200 PAGESIZE 200 FEEDBACK OFF HEADING ON TRIMSPOOL ON"
SQL_NOHEAD="SET LINESIZE 200 PAGESIZE 0 FEEDBACK OFF HEADING OFF TRIMSPOOL ON"

# ── Header ────────────────────────────────────────────────────────────────────
> "$REPORT_TXT"
log_raw "ZDM SOURCE DISCOVERY REPORT"
log_raw "Project  : ODAA-ORA-DB"
log_raw "Host     : ${HOSTNAME_LOCAL}"
log_raw "Timestamp: ${TIMESTAMP}"
log_raw "Run by   : $(whoami)"
log_raw "$(printf '=%.0s' {1..70})"

detect_oracle_env

# ══════════════════════════════════════════════════════════════════════════════
section "1. OS INFORMATION"
# ══════════════════════════════════════════════════════════════════════════════
log_info "Hostname     : $(hostname -f 2>/dev/null || hostname)"
log_info "Short name   : $(hostname -s 2>/dev/null || hostname)"
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
log_info "ORACLE_BASE  :"
if [[ -n "$ORACLE_HOME" ]]; then
    OB=$("$ORACLE_HOME/bin/orabase" 2>/dev/null || echo "${ORACLE_BASE:-unknown}")
    log_raw "  $OB"
fi
log_raw "Oracle version:"
if [[ -n "$ORACLE_HOME" && -x "$ORACLE_HOME/bin/sqlplus" ]]; then
    run_sql "${SQL_NOHEAD}
SELECT version FROM v\$instance;" | tee -a "$REPORT_TXT"
    DB_VERSION=$(run_sql "${SQL_NOHEAD}
SELECT version FROM v\$instance;" 2>/dev/null | tr -d ' ')
    run_sql "${SQL_NOHEAD}
SELECT banner FROM v\$version WHERE rownum=1;" | tee -a "$REPORT_TXT"
    SECTION_STATUSES+=("oracle_env:success")
else
    log_warn "sqlplus not found at ${ORACLE_HOME:-UNKNOWN}/bin/sqlplus — skipping Oracle version"
    SECTION_STATUSES+=("oracle_env:partial")
fi

# ══════════════════════════════════════════════════════════════════════════════
section "3. DATABASE CONFIGURATION"
# ══════════════════════════════════════════════════════════════════════════════
DB_NAME=""
DB_UNIQUE_NAME=""
DB_ROLE=""
OPEN_MODE=""
LOG_MODE=""
IS_CDB=""
DB_CHARSET=""
DB_NLS_NCHARSET=""
DBID=""

if [[ -n "$ORACLE_HOME" ]]; then
    DB_INFO=$(run_sql "${SQL_HEADER}
SELECT name, db_unique_name, dbid, database_role, open_mode,
       log_mode, cdb, platform_name
FROM   v\$database;")
    log_raw "$DB_INFO" | tee -a "$REPORT_TXT"

    DB_NAME=$(run_sql "${SQL_NOHEAD}
SELECT name FROM v\$database;" 2>/dev/null | tr -d ' \n')
    DB_UNIQUE_NAME=$(run_sql "${SQL_NOHEAD}
SELECT db_unique_name FROM v\$database;" 2>/dev/null | tr -d ' \n')
    DBID=$(run_sql "${SQL_NOHEAD}
SELECT dbid FROM v\$database;" 2>/dev/null | tr -d ' \n')
    DB_ROLE=$(run_sql "${SQL_NOHEAD}
SELECT database_role FROM v\$database;" 2>/dev/null | tr -d ' \n')
    OPEN_MODE=$(run_sql "${SQL_NOHEAD}
SELECT open_mode FROM v\$database;" 2>/dev/null | tr -d ' \n')
    LOG_MODE=$(run_sql "${SQL_NOHEAD}
SELECT log_mode FROM v\$database;" 2>/dev/null | tr -d ' \n')
    IS_CDB=$(run_sql "${SQL_NOHEAD}
SELECT cdb FROM v\$database;" 2>/dev/null | tr -d ' \n')

    [[ "$LOG_MODE" != "ARCHIVELOG" ]] && log_warn "Database is NOT in ARCHIVELOG mode — required for online ZDM migration"

    log_raw ""
    log_raw "Character Sets:"
    run_sql "${SQL_HEADER}
SELECT parameter, value FROM nls_database_parameters
WHERE  parameter IN ('NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET');" | tee -a "$REPORT_TXT"

    DB_CHARSET=$(run_sql "${SQL_NOHEAD}
SELECT value FROM nls_database_parameters WHERE parameter='NLS_CHARACTERSET';" 2>/dev/null | tr -d ' \n')
    DB_NLS_NCHARSET=$(run_sql "${SQL_NOHEAD}
SELECT value FROM nls_database_parameters WHERE parameter='NLS_NCHAR_CHARACTERSET';" 2>/dev/null | tr -d ' \n')

    log_raw ""
    log_raw "Supplemental Logging:"
    run_sql "${SQL_HEADER}
SELECT log_mode, supplemental_log_data_min, supplemental_log_data_pk,
       supplemental_log_data_ui, supplemental_log_data_fk, supplemental_log_data_all
FROM   v\$database;" | tee -a "$REPORT_TXT"

    log_raw ""
    log_raw "Force Logging:"
    run_sql "${SQL_NOHEAD}
SELECT force_logging FROM v\$database;" | tee -a "$REPORT_TXT"

    SECTION_STATUSES+=("db_config:success")
else
    log_warn "Skipping database configuration — Oracle not detected"
    SECTION_STATUSES+=("db_config:skipped")
fi

# ══════════════════════════════════════════════════════════════════════════════
section "4. CONTAINER DATABASE (CDB/PDB)"
# ══════════════════════════════════════════════════════════════════════════════
if [[ -n "$ORACLE_HOME" ]]; then
    if [[ "$IS_CDB" == "YES" ]]; then
        log_info "Database IS a CDB"
        run_sql "${SQL_HEADER}
SELECT con_id, name, open_mode, restricted FROM v\$pdbs ORDER BY con_id;" | tee -a "$REPORT_TXT"
    else
        log_info "Database is NOT a CDB (traditional non-container database)"
    fi
    SECTION_STATUSES+=("cdb_pdb:success")
else
    log_warn "Skipping CDB/PDB check — Oracle not detected"
    SECTION_STATUSES+=("cdb_pdb:skipped")
fi

# ══════════════════════════════════════════════════════════════════════════════
section "5. TDE (TRANSPARENT DATA ENCRYPTION)"
# ══════════════════════════════════════════════════════════════════════════════
if [[ -n "$ORACLE_HOME" ]]; then
    log_raw "Wallet status:"
    run_sql "${SQL_HEADER}
SELECT wrl_type, wrl_parameter, status, wallet_type FROM v\$encryption_wallet;" | tee -a "$REPORT_TXT"

    log_raw ""
    log_raw "Encrypted tablespaces:"
    run_sql "${SQL_HEADER}
SELECT tablespace_name, encrypted FROM dba_tablespaces
WHERE  encrypted='YES' ORDER BY tablespace_name;" | tee -a "$REPORT_TXT"

    log_raw ""
    log_raw "sqlnet.ora / wallet location:"
    for f in "$ORACLE_HOME/network/admin/sqlnet.ora" \
              "$ORACLE_BASE/admin/$ORACLE_SID/network/sqlnet.ora" \
              "/etc/oracle/wallet/sqlnet.ora"; do
        if [[ -f "$f" ]]; then
            log_raw "  File: $f"
            grep -i 'wallet\|encrypt\|ssl' "$f" 2>/dev/null | tee -a "$REPORT_TXT" || true
        fi
    done
    SECTION_STATUSES+=("tde:success")
else
    log_warn "Skipping TDE check — Oracle not detected"
    SECTION_STATUSES+=("tde:skipped")
fi

# ══════════════════════════════════════════════════════════════════════════════
section "6. TABLESPACES"
# ══════════════════════════════════════════════════════════════════════════════
if [[ -n "$ORACLE_HOME" ]]; then
    log_raw "Tablespace summary (size, autoextend):"
    run_sql "${SQL_HEADER}
SELECT df.tablespace_name,
       ROUND(SUM(df.bytes)/1024/1024/1024,2)        total_gb,
       ROUND(SUM(NVL(fs.bytes,0))/1024/1024/1024,2) free_gb,
       MAX(df.autoextensible)                        autoextend,
       ROUND(SUM(CASE WHEN df.autoextensible='YES'
                      THEN df.maxbytes ELSE df.bytes END)
             /1024/1024/1024,2)                      max_gb
FROM   dba_data_files df
LEFT JOIN (SELECT file_id, SUM(bytes) bytes FROM dba_free_space GROUP BY file_id) fs
       ON fs.file_id = df.file_id
GROUP  BY df.tablespace_name
ORDER  BY total_gb DESC;" | tee -a "$REPORT_TXT"

    log_raw ""
    log_raw "Datafiles with autoextend detail:"
    run_sql "${SQL_HEADER}
SELECT tablespace_name, file_name,
       ROUND(bytes/1024/1024/1024,2)    size_gb,
       autoextensible,
       ROUND(maxbytes/1024/1024/1024,2) max_gb,
       ROUND(increment_by*8192/1024/1024,0) increment_mb
FROM   dba_data_files
ORDER  BY tablespace_name, file_name;" | tee -a "$REPORT_TXT"

    SECTION_STATUSES+=("tablespaces:success")
else
    log_warn "Skipping tablespace check — Oracle not detected"
    SECTION_STATUSES+=("tablespaces:skipped")
fi

# ══════════════════════════════════════════════════════════════════════════════
section "7. REDO LOGS AND ARCHIVE"
# ══════════════════════════════════════════════════════════════════════════════
if [[ -n "$ORACLE_HOME" ]]; then
    log_raw "Redo log groups:"
    run_sql "${SQL_HEADER}
SELECT l.group#, l.members, ROUND(l.bytes/1024/1024,0) size_mb, l.status,
       lm.member
FROM   v\$log l
JOIN   v\$logfile lm ON lm.group# = l.group#
ORDER  BY l.group#;" | tee -a "$REPORT_TXT"

    log_raw ""
    log_raw "Archive log destinations:"
    run_sql "${SQL_HEADER}
SELECT dest_id, dest_name, status, target, archiver, schedule,
       destination, db_unique_name
FROM   v\$archive_dest
WHERE  status='VALID'
ORDER  BY dest_id;" | tee -a "$REPORT_TXT"

    log_raw ""
    log_raw "Recent archive log activity (last 24 h):"
    run_sql "${SQL_HEADER}
SELECT TRUNC(completion_time,'HH24') hour,
       COUNT(*)                       count,
       ROUND(SUM(blocks*block_size)/1024/1024/1024,2) total_gb
FROM   v\$archived_log
WHERE  completion_time > SYSDATE - 1
AND    standby_dest='NO'
GROUP  BY TRUNC(completion_time,'HH24')
ORDER  BY 1;" | tee -a "$REPORT_TXT"

    SECTION_STATUSES+=("redo_archive:success")
else
    log_warn "Skipping redo/archive — Oracle not detected"
    SECTION_STATUSES+=("redo_archive:skipped")
fi

# ══════════════════════════════════════════════════════════════════════════════
section "8. NETWORK (LISTENER / TNS)"
# ══════════════════════════════════════════════════════════════════════════════
log_raw "Listener status:"
if [[ -n "$ORACLE_HOME" && -x "$ORACLE_HOME/bin/lsnrctl" ]]; then
    "$ORACLE_HOME/bin/lsnrctl" status 2>&1 | tee -a "$REPORT_TXT"
fi

log_raw ""
log_raw "tnsnames.ora:"
for f in "$ORACLE_HOME/network/admin/tnsnames.ora" \
          "$ORACLE_BASE/admin/$ORACLE_SID/network/tnsnames.ora" \
          "/etc/tnsnames.ora"; do
    if [[ -f "$f" ]]; then
        log_raw "  File: $f"
        cat "$f" 2>/dev/null | tee -a "$REPORT_TXT"
    fi
done

log_raw ""
log_raw "sqlnet.ora:"
for f in "$ORACLE_HOME/network/admin/sqlnet.ora" \
          "$ORACLE_BASE/admin/$ORACLE_SID/network/sqlnet.ora"; do
    if [[ -f "$f" ]]; then
        log_raw "  File: $f"
        cat "$f" 2>/dev/null | tee -a "$REPORT_TXT"
    fi
done
SECTION_STATUSES+=("network:success")

# ══════════════════════════════════════════════════════════════════════════════
section "9. AUTHENTICATION"
# ══════════════════════════════════════════════════════════════════════════════
log_raw "Password file:"
if [[ -n "$ORACLE_HOME" ]]; then
    ls -la "$ORACLE_HOME/dbs/orapw"* 2>/dev/null | tee -a "$REPORT_TXT" || \
    ls -la "$ORACLE_HOME/dbs/PWD"*   2>/dev/null | tee -a "$REPORT_TXT" || \
    log_info "(no password file found at $ORACLE_HOME/dbs/)"
fi

log_raw ""
log_raw "~/.ssh directory ($(whoami)):"
ls -la ~/.ssh/ 2>/dev/null | tee -a "$REPORT_TXT" || log_info "(~/.ssh not found or empty)"
SECTION_STATUSES+=("auth:success")

# ══════════════════════════════════════════════════════════════════════════════
section "10. SCHEMA INFORMATION"
# ══════════════════════════════════════════════════════════════════════════════
if [[ -n "$ORACLE_HOME" ]]; then
    log_raw "Non-system schemas > 100 MB:"
    run_sql "${SQL_HEADER}
SELECT owner,
       ROUND(SUM(bytes)/1024/1024/1024,3) size_gb,
       COUNT(DISTINCT segment_name)       segment_count
FROM   dba_segments
WHERE  owner NOT IN ('SYS','SYSTEM','DBSNMP','SYSMAN','OUTLN','MDSYS',
                     'ORDSYS','EXFSYS','DMSYS','WMSYS','CTXSYS','ANONYMOUS',
                     'XDB','ORDPLUGINS','OLAPSYS','PUBLIC','APEX_030200',
                     'APEX_040000','APEX_040100','APEX_040200','XS\$NULL',
                     'FLOWS_FILES','LBACSYS','APPQOSSYS','OJVMSYS','AUDSYS',
                     'GSMADMIN_INTERNAL','GGSYS','REMOTE_SCHEDULER_AGENT')
GROUP  BY owner
HAVING SUM(bytes)/1024/1024 > 100
ORDER  BY size_gb DESC;" | tee -a "$REPORT_TXT"

    log_raw ""
    log_raw "Invalid objects by owner/type:"
    run_sql "${SQL_HEADER}
SELECT owner, object_type, COUNT(*) invalid_count
FROM   dba_objects
WHERE  status = 'INVALID'
GROUP  BY owner, object_type
ORDER  BY owner, object_type;" | tee -a "$REPORT_TXT"

    SECTION_STATUSES+=("schemas:success")
else
    log_warn "Skipping schema info — Oracle not detected"
    SECTION_STATUSES+=("schemas:skipped")
fi

# ══════════════════════════════════════════════════════════════════════════════
section "11. BACKUP CONFIGURATION"
# ══════════════════════════════════════════════════════════════════════════════
if [[ -n "$ORACLE_HOME" ]]; then
    log_raw "RMAN configuration:"
    run_sql "${SQL_HEADER}
SELECT name, value FROM v\$rman_configuration ORDER BY conf#;" | tee -a "$REPORT_TXT"

    log_raw ""
    log_raw "Last successful backup:"
    run_sql "${SQL_HEADER}
SELECT input_type, status, start_time, end_time,
       ROUND(output_bytes/1024/1024/1024,2) output_gb,
       output_device_type
FROM   v\$rman_backup_job_details
WHERE  status='COMPLETED'
ORDER  BY start_time DESC
FETCH FIRST 5 ROWS ONLY;" | tee -a "$REPORT_TXT"

    log_raw ""
    log_raw "DBMS_SCHEDULER backup jobs:"
    run_sql "${SQL_HEADER}
SELECT owner, job_name, job_type, schedule_type, state,
       enabled, last_start_date, next_run_date
FROM   dba_scheduler_jobs
WHERE  UPPER(job_name) LIKE '%BACKUP%'
   OR  UPPER(job_name) LIKE '%RMAN%'
ORDER  BY owner, job_name;" | tee -a "$REPORT_TXT"

    log_raw ""
    log_raw "Crontab (backup-related):"
    crontab -l 2>/dev/null | grep -i 'rman\|backup\|archive' | tee -a "$REPORT_TXT" || \
        log_info "(no backup crontab entries found)"

    SECTION_STATUSES+=("backup:success")
else
    log_warn "Skipping backup config — Oracle not detected"
    SECTION_STATUSES+=("backup:skipped")
fi

# ══════════════════════════════════════════════════════════════════════════════
section "12. DATABASE LINKS"
# ══════════════════════════════════════════════════════════════════════════════
if [[ -n "$ORACLE_HOME" ]]; then
    run_sql "${SQL_HEADER}
SELECT owner, db_link, username, host, created
FROM   dba_db_links
ORDER  BY owner, db_link;" | tee -a "$REPORT_TXT"
    DBLINK_COUNT=$(run_sql "${SQL_NOHEAD}
SELECT COUNT(*) FROM dba_db_links;" 2>/dev/null | tr -d ' \n')
    [[ "${DBLINK_COUNT:-0}" -gt 0 ]] && \
        log_warn "${DBLINK_COUNT} database link(s) found — review host references for post-migration update"
    SECTION_STATUSES+=("dblinks:success")
else
    log_warn "Skipping DB links — Oracle not detected"
    SECTION_STATUSES+=("dblinks:skipped")
fi

# ══════════════════════════════════════════════════════════════════════════════
section "13. MATERIALIZED VIEWS"
# ══════════════════════════════════════════════════════════════════════════════
if [[ -n "$ORACLE_HOME" ]]; then
    log_raw "Materialized views:"
    run_sql "${SQL_HEADER}
SELECT owner, mview_name, refresh_method, refresh_mode,
       next_refresh as next_refresh_date
FROM   dba_mviews
ORDER  BY owner, mview_name;" | tee -a "$REPORT_TXT"

    log_raw ""
    log_raw "Materialized view logs:"
    run_sql "${SQL_HEADER}
SELECT log_owner, master, log_table, log_type, include_new_values
FROM   dba_mview_logs
ORDER  BY log_owner, master;" | tee -a "$REPORT_TXT"
    SECTION_STATUSES+=("mviews:success")
else
    log_warn "Skipping materialized views — Oracle not detected"
    SECTION_STATUSES+=("mviews:skipped")
fi

# ══════════════════════════════════════════════════════════════════════════════
section "14. SCHEDULER JOBS"
# ══════════════════════════════════════════════════════════════════════════════
if [[ -n "$ORACLE_HOME" ]]; then
    log_raw "All DBMS_SCHEDULER jobs:"
    run_sql "${SQL_HEADER}
SELECT owner, job_name, job_type, schedule_type, state,
       enabled, last_start_date, next_run_date
FROM   dba_scheduler_jobs
ORDER  BY owner, job_name;" | tee -a "$REPORT_TXT"

    log_raw ""
    log_raw "Jobs referencing external resources (hostname/file/credential):"
    run_sql "${SQL_HEADER}
SELECT j.owner, j.job_name, j.job_action
FROM   dba_scheduler_jobs j
WHERE  UPPER(j.job_action) LIKE '%http%'
    OR UPPER(j.job_action) LIKE '%ftp%'
    OR UPPER(j.job_action) LIKE '%/u01%'
    OR UPPER(j.job_action) LIKE '%/home%'
    OR j.credential_name IS NOT NULL
ORDER  BY j.owner, j.job_name;" | tee -a "$REPORT_TXT"

    log_warn "Review scheduler jobs above for external hostname/path references that need post-migration updates"
    SECTION_STATUSES+=("scheduler:success")
else
    log_warn "Skipping scheduler jobs — Oracle not detected"
    SECTION_STATUSES+=("scheduler:skipped")
fi

# ══════════════════════════════════════════════════════════════════════════════
section "15. DATA GUARD CONFIGURATION"
# ══════════════════════════════════════════════════════════════════════════════
if [[ -n "$ORACLE_HOME" ]]; then
    DG_CONFIG=$(run_sql "${SQL_NOHEAD}
SELECT value FROM v\$parameter WHERE name='log_archive_dest_2';" 2>/dev/null | tr -d ' \n')
    if [[ -n "$DG_CONFIG" && "$DG_CONFIG" != "0" ]]; then
        log_info "Data Guard may be configured (log_archive_dest_2 is set)"
        run_sql "${SQL_HEADER}
SELECT name, value FROM v\$parameter
WHERE  name IN ('db_unique_name','log_archive_config','log_archive_dest_1',
                'log_archive_dest_2','log_archive_dest_state_1',
                'log_archive_dest_state_2','fal_server','fal_client',
                'standby_file_management','db_file_name_convert',
                'log_file_name_convert')
ORDER  BY name;" | tee -a "$REPORT_TXT"
    else
        log_info "No Data Guard configuration detected"
    fi
    SECTION_STATUSES+=("dataguard:success")
else
    log_warn "Skipping Data Guard check — Oracle not detected"
    SECTION_STATUSES+=("dataguard:skipped")
fi

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
log_raw ""
log_raw "Report: $REPORT_TXT"
log_raw "JSON  : $REPORT_JSON"

# ── JSON output ───────────────────────────────────────────────────────────────
_esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g'; }
_arr() { local out; for v in "$@"; do out+="\"$(_esc "$v")\","; done; echo "[${out%,}]"; }

WARN_JSON=$(_arr "${WARNINGS[@]+"${WARNINGS[@]}"}")

cat > "$REPORT_JSON" <<JSONEOF
{
  "report": "zdm_source_discovery",
  "project": "ODAA-ORA-DB",
  "timestamp": "${TIMESTAMP}",
  "hostname": "$(_esc "$HOSTNAME_LOCAL")",
  "run_by": "$(whoami)",
  "overall_status": "${OVERALL_STATUS}",
  "oracle": {
    "oracle_home": "$(_esc "${ORACLE_HOME:-}")",
    "oracle_sid": "$(_esc "${ORACLE_SID:-}")",
    "db_version": "$(_esc "${DB_VERSION:-}")",
    "db_name": "$(_esc "${DB_NAME:-}")",
    "db_unique_name": "$(_esc "${DB_UNIQUE_NAME:-}")",
    "dbid": "$(_esc "${DBID:-}")",
    "db_role": "$(_esc "${DB_ROLE:-}")",
    "open_mode": "$(_esc "${OPEN_MODE:-}")",
    "log_mode": "$(_esc "${LOG_MODE:-}")",
    "is_cdb": "$(_esc "${IS_CDB:-}")",
    "charset": "$(_esc "${DB_CHARSET:-}")",
    "nchar_charset": "$(_esc "${DB_NLS_NCHARSET:-}")"
  },
  "sections": $(printf '['; printf '"%s",' "${SECTION_STATUSES[@]}"; printf ']' | sed 's/,]$/]/'),
  "warnings": ${WARN_JSON},
  "report_txt": "$(_esc "$REPORT_TXT")"
}
JSONEOF

echo ""
echo "======================================================================"
echo " SOURCE DISCOVERY COMPLETE — ${OVERALL_STATUS^^}"
echo " Reports: ${OUTPUT_DIR}"
echo "======================================================================"
