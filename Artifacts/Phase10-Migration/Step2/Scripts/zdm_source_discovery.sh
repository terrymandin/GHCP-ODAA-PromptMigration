#!/bin/bash
# =============================================================================
# zdm_source_discovery.sh
# Phase 10 — ZDM Migration · Step 2: Source Database Discovery
#
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration
#
# Gathers OS, Oracle environment, and database configuration from the
# source database server. Executed via SSH as SOURCE_ADMIN_USER (called by
# zdm_orchestrate_discovery.sh); all SQL runs under the oracle user via sudo.
#
# Output (current working directory):
#   zdm_source_discovery_<hostname>_<timestamp>.txt   — human-readable report
#   zdm_source_discovery_<hostname>_<timestamp>.json  — machine-parseable summary
#
# Usage (standalone / manual):
#   bash zdm_source_discovery.sh
#
# Override Oracle env before running if auto-detection fails:
#   SOURCE_REMOTE_ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1 \
#   SOURCE_ORACLE_SID=oradb01 bash zdm_source_discovery.sh
# =============================================================================

HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_TXT="./zdm_source_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
REPORT_JSON="./zdm_source_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

# Configuration — overridden via environment variables set by the orchestrator
ORACLE_USER="${ORACLE_USER:-oracle}"
SOURCE_REMOTE_ORACLE_HOME="${SOURCE_REMOTE_ORACLE_HOME:-}"
SOURCE_ORACLE_SID="${SOURCE_ORACLE_SID:-}"

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
    printf '# ZDM Source Discovery Report\n\n'
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
# ---------------------------------------------------------------------------
detect_oracle_env() {
    local detected_home="${SOURCE_REMOTE_ORACLE_HOME:-}"
    local detected_sid="${SOURCE_ORACLE_SID:-}"

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

    # 4. Common installation paths
    if [[ -z "${detected_home}" ]]; then
        for pat in \
            /u01/app/oracle/product/*/dbhome_1 \
            /u01/app/oracle/product/*/* \
            /opt/oracle/product/*/dbhome_1 \
            /oracle/app/oracle/product/*/dbhome_1; do
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
    { cat /etc/os-release 2>/dev/null || cat /etc/redhat-release 2>/dev/null \
        || uname -a; } | tee -a "$REPORT_TXT"

    log_info ""
    log_info "Kernel: $(uname -r)"

    log_info ""
    log_info "Disk Space (df -h):"
    df -h 2>/dev/null | tee -a "$REPORT_TXT"
}

# ---------------------------------------------------------------------------
# Section 2: Oracle Environment
# ---------------------------------------------------------------------------
log_section "Oracle Environment"
log_info "ORACLE_HOME : ${ORACLE_HOME:-NOT DETECTED}"
log_info "ORACLE_SID  : ${ORACLE_SID:-NOT DETECTED}"
log_info "ORACLE_BASE : ${ORACLE_BASE:-}"

[[ -z "${ORACLE_HOME}" ]] && add_warning "ORACLE_HOME could not be auto-detected. SQL sections skipped."
[[ -z "${ORACLE_SID}"  ]] && add_warning "ORACLE_SID could not be auto-detected."

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
        add_warning "SQL*Plus connectivity test failed. SQL sections may be incomplete. Output: ${sql_test_out}"
    fi
fi

log_info "SQL*Plus connectivity: ${SQL_OK}"

# ---------------------------------------------------------------------------
# Section 3: Database Configuration
# ---------------------------------------------------------------------------
log_section "Database Configuration"
DB_NAME="" DB_UNIQUE_NAME="" LOG_MODE="" OPEN_MODE="" DB_CHARSET="" DB_NCSET=""

if [[ "${SQL_OK}" == "true" ]]; then
    run_sql "${SQL_FMT}
SELECT 'DB_NAME='         || NAME             AS PROPERTY FROM V\$DATABASE
UNION ALL
SELECT 'DB_UNIQUE_NAME='  || DB_UNIQUE_NAME   FROM V\$DATABASE
UNION ALL
SELECT 'DBID='            || DBID             FROM V\$DATABASE
UNION ALL
SELECT 'DATABASE_ROLE='   || DATABASE_ROLE    FROM V\$DATABASE
UNION ALL
SELECT 'OPEN_MODE='       || OPEN_MODE        FROM V\$DATABASE
UNION ALL
SELECT 'LOG_MODE='        || LOG_MODE         FROM V\$DATABASE
UNION ALL
SELECT 'FORCE_LOGGING='   || FORCE_LOGGING    FROM V\$DATABASE
UNION ALL
SELECT 'SUPPLEMENTAL_LOG_MIN='  || SUPPLEMENTAL_LOG_DATA_MIN  FROM V\$DATABASE
UNION ALL
SELECT 'SUPPLEMENTAL_LOG_PK='   || SUPPLEMENTAL_LOG_DATA_PK   FROM V\$DATABASE
UNION ALL
SELECT 'SUPPLEMENTAL_LOG_UI='   || SUPPLEMENTAL_LOG_DATA_UI   FROM V\$DATABASE
UNION ALL
SELECT 'SUPPLEMENTAL_LOG_FK='   || SUPPLEMENTAL_LOG_DATA_FK   FROM V\$DATABASE
UNION ALL
SELECT 'SUPPLEMENTAL_LOG_ALL='  || SUPPLEMENTAL_LOG_DATA_ALL  FROM V\$DATABASE;
EXIT;" | tee -a "$REPORT_TXT"

    log_info ""
    log_info "NLS Parameters:"
    run_sql "${SQL_FMT}
SELECT PARAMETER, VALUE
FROM NLS_DATABASE_PARAMETERS
WHERE PARAMETER IN ('NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET','NLS_LANGUAGE','NLS_TERRITORY')
ORDER BY PARAMETER;
EXIT;" | tee -a "$REPORT_TXT"

    # Capture individual values for JSON
    DB_NAME="$(run_sql "SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT NAME FROM V\$DATABASE; EXIT;" | tr -d '[:space:]')"
    DB_UNIQUE_NAME="$(run_sql "SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT DB_UNIQUE_NAME FROM V\$DATABASE; EXIT;" | tr -d '[:space:]')"
    LOG_MODE="$(run_sql "SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT LOG_MODE FROM V\$DATABASE; EXIT;" | tr -d '[:space:]')"
    OPEN_MODE="$(run_sql "SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT OPEN_MODE FROM V\$DATABASE; EXIT;" | tr -d '[:space:]')"
    DB_CHARSET="$(run_sql "SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT VALUE FROM NLS_DATABASE_PARAMETERS WHERE PARAMETER='NLS_CHARACTERSET'; EXIT;" | tr -d '[:space:]')"
    DB_NCSET="$(run_sql "SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT VALUE FROM NLS_DATABASE_PARAMETERS WHERE PARAMETER='NLS_NCHAR_CHARACTERSET'; EXIT;" | tr -d '[:space:]')"

    [[ "${LOG_MODE}" != "ARCHIVELOG" ]] && \
        add_warning "Database is NOT in ARCHIVELOG mode (current: ${LOG_MODE}). ZDM online migration requires ARCHIVELOG mode."
else
    log_info "(Skipped — SQL connection unavailable)"
fi

# ---------------------------------------------------------------------------
# Section 4: Container Database (CDB / PDB)
# ---------------------------------------------------------------------------
log_section "Container Database (CDB / PDB)"
CDB_STATUS="NO"
if [[ "${SQL_OK}" == "true" ]]; then
    CDB_STATUS="$(run_sql "SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT CDB FROM V\$DATABASE; EXIT;" | tr -d '[:space:]')"
    log_info "CDB: ${CDB_STATUS}"

    if [[ "${CDB_STATUS}" == "YES" ]]; then
        run_sql "${SQL_FMT}
COLUMN PDB_NAME  FORMAT A30
COLUMN OPEN_MODE FORMAT A15
COLUMN RESTRICTED FORMAT A10
SELECT PDB_NAME, OPEN_MODE, RESTRICTED
FROM   CDB_PDBS
ORDER  BY PDB_NAME;
EXIT;" | tee -a "$REPORT_TXT"
    else
        log_info "Non-CDB (traditional single-tenant database)"
    fi
else
    log_info "(Skipped — SQL connection unavailable)"
fi

# ---------------------------------------------------------------------------
# Section 5: Transparent Data Encryption (TDE)
# ---------------------------------------------------------------------------
log_section "Transparent Data Encryption (TDE)"
if [[ "${SQL_OK}" == "true" ]]; then
    log_info "Wallet Status:"
    run_sql "${SQL_FMT}
COLUMN WRL_TYPE  FORMAT A15
COLUMN WRL_PARAMETER FORMAT A60
COLUMN STATUS    FORMAT A20
SELECT WRL_TYPE, WRL_PARAMETER, STATUS FROM V\$ENCRYPTION_WALLET;
EXIT;" | tee -a "$REPORT_TXT"

    log_info ""
    log_info "TDE Parameters:"
    run_sql "${SQL_FMT}
SHOW PARAMETER wallet_root;
SHOW PARAMETER tde_configuration;
SHOW PARAMETER encrypt_new_tablespaces;
EXIT;" | tee -a "$REPORT_TXT"

    log_info ""
    log_info "Encrypted Tablespaces:"
    run_sql "${SQL_FMT}
COLUMN TABLESPACE_NAME FORMAT A30
COLUMN ENCRYPTEDTS     FORMAT A12
COLUMN ENCRYPT_ALG     FORMAT A15
SELECT TABLESPACE_NAME, ENCRYPTEDTS, ENCRYPT_ALG
FROM   DBA_TABLESPACES
WHERE  ENCRYPTEDTS = 'YES'
ORDER  BY TABLESPACE_NAME;
EXIT;" | tee -a "$REPORT_TXT"
else
    log_info "(Skipped — SQL connection unavailable)"
fi

# ---------------------------------------------------------------------------
# Section 6: Tablespaces — Autoextend and Sizing
# ---------------------------------------------------------------------------
log_section "Tablespaces — Data Files, Autoextend, and Sizing"
if [[ "${SQL_OK}" == "true" ]]; then
    run_sql "${SQL_FMT}
COLUMN TABLESPACE_NAME FORMAT A30
COLUMN FILE_NAME       FORMAT A60
COLUMN STATUS          FORMAT A10
COLUMN AE              FORMAT A5 HEADING 'AE?'
COLUMN SIZE_GB         FORMAT 9999.99
COLUMN MAX_GB          FORMAT 9999.99
COLUMN INC_MB          FORMAT 9999.99
SELECT DF.TABLESPACE_NAME,
       DF.FILE_NAME,
       ROUND(DF.BYTES      / 1073741824, 2) AS SIZE_GB,
       DF.AUTOEXTENSIBLE                    AS AE,
       ROUND(DF.MAXBYTES   / 1073741824, 2) AS MAX_GB,
       ROUND(DF.INCREMENT_BY * TS.BLOCK_SIZE / 1048576, 2) AS INC_MB,
       DF.STATUS
FROM   DBA_DATA_FILES  DF
JOIN   DBA_TABLESPACES TS ON TS.TABLESPACE_NAME = DF.TABLESPACE_NAME
ORDER  BY DF.TABLESPACE_NAME, DF.FILE_NAME;
EXIT;" | tee -a "$REPORT_TXT"

    log_info ""
    log_info "Tablespace Summary (current vs max):"
    run_sql "${SQL_FMT}
COLUMN TABLESPACE_NAME FORMAT A30
COLUMN USED_GB  FORMAT 9999.99
COLUMN FREE_GB  FORMAT 9999.99
COLUMN MAX_GB   FORMAT 9999.99
SELECT TS.TABLESPACE_NAME,
       ROUND(NVL(USED.USED_BYTES,0)  / 1073741824, 2) AS USED_GB,
       ROUND(NVL(FREE.FREE_BYTES,0)  / 1073741824, 2) AS FREE_GB,
       ROUND(NVL(DF.MAX_BYTES,0)     / 1073741824, 2) AS MAX_GB
FROM   DBA_TABLESPACES TS
LEFT JOIN (
    SELECT TABLESPACE_NAME, SUM(BYTES) AS USED_BYTES FROM DBA_SEGMENTS GROUP BY TABLESPACE_NAME
) USED ON USED.TABLESPACE_NAME = TS.TABLESPACE_NAME
LEFT JOIN (
    SELECT TABLESPACE_NAME, SUM(BYTES) AS FREE_BYTES FROM DBA_FREE_SPACE  GROUP BY TABLESPACE_NAME
) FREE ON FREE.TABLESPACE_NAME = TS.TABLESPACE_NAME
LEFT JOIN (
    SELECT TABLESPACE_NAME, SUM(MAXBYTES) AS MAX_BYTES FROM DBA_DATA_FILES GROUP BY TABLESPACE_NAME
) DF   ON DF.TABLESPACE_NAME   = TS.TABLESPACE_NAME
ORDER  BY TS.TABLESPACE_NAME;
EXIT;" | tee -a "$REPORT_TXT"
else
    log_info "(Skipped — SQL connection unavailable)"
fi

# ---------------------------------------------------------------------------
# Section 7: Redo Logs and Archive Log Configuration
# ---------------------------------------------------------------------------
log_section "Redo Logs and Archive Log Configuration"
if [[ "${SQL_OK}" == "true" ]]; then
    log_info "Redo Log Groups:"
    run_sql "${SQL_FMT}
COLUMN STATUS   FORMAT A15
COLUMN ARCHIVED FORMAT A8
SELECT GROUP#, MEMBERS, ROUND(BYTES/1048576,0) AS SIZE_MB, STATUS, ARCHIVED
FROM   V\$LOG
ORDER  BY GROUP#;
EXIT;" | tee -a "$REPORT_TXT"

    log_info ""
    log_info "Redo Log Members:"
    run_sql "${SQL_FMT}
COLUMN MEMBER  FORMAT A70
SELECT L.GROUP#, LF.MEMBER, LF.STATUS
FROM   V\$LOG L JOIN V\$LOGFILE LF ON L.GROUP# = LF.GROUP#
ORDER  BY L.GROUP#, LF.MEMBER;
EXIT;" | tee -a "$REPORT_TXT"

    log_info ""
    log_info "Archive Destinations:"
    run_sql "${SQL_FMT}
COLUMN DEST_NAME FORMAT A30
COLUMN DEST      FORMAT A60
COLUMN STATUS    FORMAT A10
COLUMN TARGET    FORMAT A10
SELECT DEST_ID, DEST_NAME, STATUS, TARGET, DESTINATION
FROM   V\$ARCHIVE_DEST
WHERE  STATUS != 'INACTIVE'
ORDER  BY DEST_ID;
EXIT;" | tee -a "$REPORT_TXT"
else
    log_info "(Skipped — SQL connection unavailable)"
fi

# ---------------------------------------------------------------------------
# Section 8: Network — Listener, tnsnames.ora, sqlnet.ora
# ---------------------------------------------------------------------------
log_section "Network — Listener Status"
lsnrctl status 2>&1 | tee -a "$REPORT_TXT" || log_info "(lsnrctl not found or not on PATH)"

log_section "tnsnames.ora"
TNSNAMES_PATH=""
for p in \
    "${ORACLE_HOME}/network/admin/tnsnames.ora" \
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

log_section "sqlnet.ora"
SQLNET_PATH=""
for p in \
    "${ORACLE_HOME}/network/admin/sqlnet.ora" \
    "${TNS_ADMIN:-}/sqlnet.ora" \
    "/etc/sqlnet.ora"; do
    [[ -n "${p}" && -f "${p}" ]] && { SQLNET_PATH="${p}"; break; }
done
if [[ -n "${SQLNET_PATH}" ]]; then
    log_info "Location: ${SQLNET_PATH}"
    cat "${SQLNET_PATH}" 2>&1 | tee -a "$REPORT_TXT"
else
    log_info "(sqlnet.ora not found)"
fi

# ---------------------------------------------------------------------------
# Section 9: Authentication — Password File and SSH
# ---------------------------------------------------------------------------
log_section "Authentication — Password File and SSH Directory"
log_info "Password file location:"
if [[ -n "${ORACLE_HOME}" ]]; then
    find "${ORACLE_HOME}/dbs" -name "orapw*" 2>/dev/null | tee -a "$REPORT_TXT" \
        || log_info "(none found under ${ORACLE_HOME}/dbs)"
else
    log_info "(ORACLE_HOME not set — skipped)"
fi

log_info ""
log_info "SSH directory (~/.ssh/):"
ls -la ~/.ssh/ 2>/dev/null | tee -a "$REPORT_TXT" || log_info "(~/.ssh/ not found or inaccessible)"

# ---------------------------------------------------------------------------
# Section 10: Schema Information — Sizes and Invalid Objects
# ---------------------------------------------------------------------------
log_section "Schema Information — Non-System Schemas > 100 MB"
if [[ "${SQL_OK}" == "true" ]]; then
    run_sql "${SQL_FMT}
COLUMN OWNER          FORMAT A30
COLUMN TOTAL_SIZE_MB  FORMAT 9999999999
SELECT OWNER, ROUND(SUM(BYTES)/1048576, 0) AS TOTAL_SIZE_MB
FROM   DBA_SEGMENTS
WHERE  OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','DBSFWUSER','GGSYS','ANONYMOUS',
    'CTXSYS','DVSYS','DVF','GSMADMIN_INTERNAL','LBACSYS','MDSYS','OJVMSYS',
    'OLAPSYS','ORACLE_OCM','ORDDATA','ORDSYS','REMOTE_SCHEDULER_AGENT',
    'SI_INFORMTN_SCHEMA','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR',
    'WMSYS','XDB','XS\$NULL','AUDSYS','DIP','ORDPLUGINS','SCOTT','MGMT_VIEW')
GROUP  BY OWNER
HAVING ROUND(SUM(BYTES)/1048576, 0) > 100
ORDER  BY TOTAL_SIZE_MB DESC;
EXIT;" | tee -a "$REPORT_TXT"

    log_info ""
    log_info "Invalid Objects by Owner and Type:"
    run_sql "${SQL_FMT}
COLUMN OWNER       FORMAT A30
COLUMN OBJECT_TYPE FORMAT A30
SELECT OWNER, OBJECT_TYPE, COUNT(*) AS INVALID_COUNT
FROM   DBA_OBJECTS
WHERE  STATUS = 'INVALID'
GROUP  BY OWNER, OBJECT_TYPE
ORDER  BY OWNER, OBJECT_TYPE;
EXIT;" | tee -a "$REPORT_TXT"
else
    log_info "(Skipped — SQL connection unavailable)"
fi

# ---------------------------------------------------------------------------
# Section 11: Backup Configuration — RMAN and Scheduler
# ---------------------------------------------------------------------------
log_section "Backup Configuration — RMAN"
if [[ "${SQL_OK}" == "true" ]]; then
    log_info "RMAN Configuration:"
    run_sql "${SQL_FMT}
COLUMN NAME  FORMAT A40
COLUMN VALUE FORMAT A80
SELECT NAME, VALUE FROM V\$RMAN_CONFIGURATION ORDER BY NAME;
EXIT;" | tee -a "$REPORT_TXT"

    log_info ""
    log_info "Last 5 RMAN Backup Jobs:"
    run_sql "${SQL_FMT}
COLUMN STATUS          FORMAT A10
COLUMN INPUT_TYPE      FORMAT A20
COLUMN COMPLETION_TIME FORMAT A25
COLUMN INPUT_GB        FORMAT 9999.99
SELECT STATUS, INPUT_TYPE, COMPLETION_TIME,
       ROUND(INPUT_BYTES_PER_SEC_DISPLAY,2) AS INPUT_GB
FROM   V\$RMAN_BACKUP_JOB_DETAILS
ORDER  BY COMPLETION_TIME DESC
FETCH  FIRST 5 ROWS ONLY;
EXIT;" | tee -a "$REPORT_TXT"

    log_info ""
    log_info "Backup-related Scheduler Jobs:"
    run_sql "${SQL_FMT}
COLUMN JOB_NAME        FORMAT A40
COLUMN ENABLED         FORMAT A8
COLUMN LAST_START_DATE FORMAT A25
COLUMN NEXT_RUN_DATE   FORMAT A25
SELECT JOB_NAME, ENABLED, LAST_START_DATE, NEXT_RUN_DATE
FROM   DBA_SCHEDULER_JOBS
WHERE  UPPER(JOB_NAME) LIKE '%RMAN%' OR UPPER(JOB_NAME) LIKE '%BACKUP%'
ORDER  BY JOB_NAME;
EXIT;" | tee -a "$REPORT_TXT"

    log_info ""
    log_info "Crontab backup entries:"
    crontab -l 2>/dev/null | grep -iE 'rman|backup' | tee -a "$REPORT_TXT" \
        || log_info "(none found or crontab not accessible)"
else
    log_info "(Skipped — SQL connection unavailable)"
fi

# ---------------------------------------------------------------------------
# Section 12: Database Links
# ---------------------------------------------------------------------------
log_section "Database Links"
if [[ "${SQL_OK}" == "true" ]]; then
    run_sql "${SQL_FMT}
COLUMN OWNER    FORMAT A20
COLUMN DB_LINK  FORMAT A35
COLUMN HOST     FORMAT A45
COLUMN USERNAME FORMAT A20
SELECT OWNER, DB_LINK, HOST, USERNAME, CREATED
FROM   DBA_DB_LINKS
ORDER  BY OWNER, DB_LINK;
EXIT;" | tee -a "$REPORT_TXT"
else
    log_info "(Skipped — SQL connection unavailable)"
fi

# ---------------------------------------------------------------------------
# Section 13: Materialized Views
# ---------------------------------------------------------------------------
log_section "Materialized Views"
if [[ "${SQL_OK}" == "true" ]]; then
    log_info "Materialized View Definitions:"
    run_sql "${SQL_FMT}
COLUMN OWNER          FORMAT A20
COLUMN MVIEW_NAME     FORMAT A40
COLUMN REFRESH_METHOD FORMAT A15
COLUMN REFRESH_MODE   FORMAT A15
COLUMN NEXT           FORMAT A25
SELECT OWNER, MVIEW_NAME, REFRESH_METHOD, REFRESH_MODE, NEXT
FROM   DBA_MVIEWS
ORDER  BY OWNER, MVIEW_NAME;
EXIT;" | tee -a "$REPORT_TXT"

    log_info ""
    log_info "Materialized View Logs:"
    run_sql "${SQL_FMT}
COLUMN LOG_OWNER    FORMAT A20
COLUMN MASTER       FORMAT A40
COLUMN LOG_TABLE    FORMAT A40
COLUMN PRIMARY_KEY  FORMAT A11
COLUMN ROWIDS       FORMAT A6
SELECT LOG_OWNER, MASTER, LOG_TABLE, PRIMARY_KEY, ROWIDS
FROM   DBA_MVIEW_LOGS
ORDER  BY LOG_OWNER, MASTER;
EXIT;" | tee -a "$REPORT_TXT"
else
    log_info "(Skipped — SQL connection unavailable)"
fi

# ---------------------------------------------------------------------------
# Section 14: Scheduler Jobs (DBMS_SCHEDULER)
# ---------------------------------------------------------------------------
log_section "Scheduler Jobs (DBMS_SCHEDULER)"
if [[ "${SQL_OK}" == "true" ]]; then
    run_sql "${SQL_FMT}
COLUMN OWNER          FORMAT A20
COLUMN JOB_NAME       FORMAT A40
COLUMN JOB_TYPE       FORMAT A20
COLUMN SCHEDULE_TYPE  FORMAT A15
COLUMN ENABLED        FORMAT A8
COLUMN LAST_START_DATE FORMAT A25
COLUMN NEXT_RUN_DATE  FORMAT A25
SELECT OWNER, JOB_NAME, JOB_TYPE, SCHEDULE_TYPE, ENABLED,
       LAST_START_DATE, NEXT_RUN_DATE
FROM   DBA_SCHEDULER_JOBS
ORDER  BY OWNER, JOB_NAME;
EXIT;" | tee -a "$REPORT_TXT"

    log_info ""
    log_info "Jobs referencing external resources (file paths / credentials / hostnames):"
    run_sql "${SQL_FMT}
COLUMN OWNER      FORMAT A20
COLUMN JOB_NAME   FORMAT A40
COLUMN JOB_ACTION FORMAT A100
SELECT OWNER, JOB_NAME, JOB_ACTION
FROM   DBA_SCHEDULER_JOBS
WHERE  JOB_ACTION LIKE '%/@%'
    OR JOB_ACTION LIKE '%/home/%'
    OR JOB_ACTION LIKE '%/opt/%'
    OR JOB_ACTION LIKE '%/u01/%'
    OR JOB_ACTION LIKE '%UTL_FILE%'
ORDER  BY OWNER, JOB_NAME;
EXIT;" | tee -a "$REPORT_TXT"
else
    log_info "(Skipped — SQL connection unavailable)"
fi

# ---------------------------------------------------------------------------
# Section 15: Data Guard Configuration
# ---------------------------------------------------------------------------
log_section "Data Guard Configuration Parameters"
if [[ "${SQL_OK}" == "true" ]]; then
    run_sql "${SQL_FMT}
SHOW PARAMETER log_archive_config;
SHOW PARAMETER log_archive_dest_1;
SHOW PARAMETER log_archive_dest_2;
SHOW PARAMETER fal_server;
SHOW PARAMETER fal_client;
SHOW PARAMETER standby_file_management;
SHOW PARAMETER db_unique_name;
EXIT;" | tee -a "$REPORT_TXT"
else
    log_info "(Skipped — SQL connection unavailable)"
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
  "report":          "source-discovery",
  "phase":           "Phase10-ZDM-Step2",
  "generated":       "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "run_by":          "$(whoami)",
  "hostname":        "${HOSTNAME_SHORT}",
  "status":          "${STATUS}",
  "oracle_home":     "${ORACLE_HOME:-}",
  "oracle_sid":      "${ORACLE_SID:-}",
  "db_name":         "${DB_NAME:-}",
  "db_unique_name":  "${DB_UNIQUE_NAME:-}",
  "log_mode":        "${LOG_MODE:-}",
  "open_mode":       "${OPEN_MODE:-}",
  "characterset":    "${DB_CHARSET:-}",
  "nchar_charset":   "${DB_NCSET:-}",
  "cdb":             "${CDB_STATUS:-}",
  "sql_connected":   ${SQL_OK},
  "warnings":        ${WARNINGS_JSON},
  "report_txt":      "${REPORT_TXT}"
}
JSONEOF

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "  ZDM Source Discovery — Complete"
echo "  Hostname : ${HOSTNAME_SHORT}"
echo "  Status   : ${STATUS}"
echo "  Warnings : ${#WARNINGS[@]}"
echo "  Reports  :"
echo "    ${REPORT_TXT}"
echo "    ${REPORT_JSON}"
echo "============================================================"
