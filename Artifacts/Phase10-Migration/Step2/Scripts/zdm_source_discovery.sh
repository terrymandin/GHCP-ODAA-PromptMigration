#!/bin/bash
# =============================================================================
# zdm_source_discovery.sh
# Phase 10 â€” ZDM Migration Â· Step 2: Source Database Discovery
#
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration
#
# Discovers Oracle environment, database configuration, TDE, supplemental logging,
# redo/archive, network, schema info, tablespaces, backups, db links, MVs, and
# scheduler jobs on the SOURCE database server.
#
# Executed via SSH from the ZDM orchestration script.
# SSH as SOURCE_ADMIN_USER (e.g., azureuser), SQL via sudo -u oracle.
#
# Outputs (written to current working directory):
#   zdm_source_discovery_<hostname>_<timestamp>.txt
#   zdm_source_discovery_<hostname>_<timestamp>.json
#
# Usage:
#   chmod +x zdm_source_discovery.sh
#   ./zdm_source_discovery.sh
#
# Run as: SOURCE_ADMIN_USER on the source database server
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
[ -n "${SOURCE_REMOTE_ORACLE_HOME:-}" ] && ORACLE_HOME="$SOURCE_REMOTE_ORACLE_HOME"
[ -n "${SOURCE_REMOTE_ORACLE_SID:-}"  ] && ORACLE_SID="$SOURCE_REMOTE_ORACLE_SID"

# ---------------------------------------------------------------------------
# Output paths (write to current working directory)
# ---------------------------------------------------------------------------
HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_TXT="./zdm_source_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
REPORT_JSON="./zdm_source_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

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
        for path in /u01/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1 /oracle/product/*/dbhome_1 /u02/app/oracle/product/*/dbhome_1; do
            if [ -d "$path" ] && [ -f "$path/bin/sqlplus" ]; then
                ORACLE_HOME="$path"
                break
            fi
        done
    fi

    # Method 4: Detect ORACLE_BASE from ORACLE_HOME parent structure
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

# ---------------------------------------------------------------------------
# Section collection helpers
# ---------------------------------------------------------------------------
SECTIONS_JSON=""
append_json_section() {
    local key="$1"
    local val="$2"
    # Escape double quotes in value
    val="${val//\"/\\\"}"
    SECTIONS_JSON="${SECTIONS_JSON}  \"${key}\": \"${val}\","$'\n'
}

# ============================================================================
# MAIN
# ============================================================================
# Initialize report file
: > "$REPORT_TXT"

log_raw "============================================================"
log_raw "  ZDM Step 2 â€” Source Database Discovery"
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

log_raw ""
log_info "--- Disk Space ---"
df -h 2>/dev/null | tee -a "$REPORT_TXT" || log_warn "df command failed"

append_json_section "os_hostname" "$OS_HOSTNAME"
append_json_section "os_ip_addresses" "$OS_IP_ADDRS"
append_json_section "os_version" "$OS_VERSION"

# ============================================================================
# 2. ORACLE ENVIRONMENT DETECTION
# ============================================================================
log_section "2. ORACLE ENVIRONMENT"

detect_oracle_env

if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
    log_info "ORACLE_HOME : $ORACLE_HOME"
    log_info "ORACLE_SID  : $ORACLE_SID"
    log_info "ORACLE_BASE : ${ORACLE_BASE:-auto-detect attempt}"

    ORA_VERSION="$(run_sql_value "SELECT version FROM v\$instance;")"
    log_info "Oracle Version : $ORA_VERSION"

    append_json_section "oracle_home" "$ORACLE_HOME"
    append_json_section "oracle_sid" "$ORACLE_SID"
    append_json_section "oracle_base" "${ORACLE_BASE:-}"
    append_json_section "oracle_version" "$ORA_VERSION"
else
    log_warn "ORACLE_HOME or ORACLE_SID could not be auto-detected."
    log_warn "Set SOURCE_REMOTE_ORACLE_HOME and SOURCE_REMOTE_ORACLE_SID env vars to override."
    append_json_section "oracle_home" "UNDETERMINED"
    append_json_section "oracle_sid" "UNDETERMINED"
fi

# ============================================================================
# 3. DATABASE CONFIGURATION
# ============================================================================
log_section "3. DATABASE CONFIGURATION"

{
    DB_NAME="$(run_sql_value "SELECT name FROM v\$database;")"
    DB_UNIQUE_NAME="$(run_sql_value "SELECT db_unique_name FROM v\$database;")"
    DB_ID="$(run_sql_value "SELECT dbid FROM v\$database;")"
    DB_ROLE="$(run_sql_value "SELECT database_role FROM v\$database;")"
    DB_OPEN_MODE="$(run_sql_value "SELECT open_mode FROM v\$database;")"
    DB_LOG_MODE="$(run_sql_value "SELECT log_mode FROM v\$database;")"
    DB_FORCE_LOGGING="$(run_sql_value "SELECT force_logging FROM v\$database;")"
    DB_CHARSET="$(run_sql_value "SELECT value FROM nls_database_parameters WHERE parameter='NLS_CHARACTERSET';")"
    DB_NCHARSET="$(run_sql_value "SELECT value FROM nls_database_parameters WHERE parameter='NLS_NCHAR_CHARACTERSET';")"

    log_info "DB Name          : $DB_NAME"
    log_info "DB Unique Name   : $DB_UNIQUE_NAME"
    log_info "DBID             : $DB_ID"
    log_info "Role             : $DB_ROLE"
    log_info "Open Mode        : $DB_OPEN_MODE"
    log_info "Log Mode         : $DB_LOG_MODE"
    log_info "Force Logging    : $DB_FORCE_LOGGING"
    log_info "Character Set    : $DB_CHARSET"
    log_info "Nat. Char Set    : $DB_NCHARSET"

    # Database size
    log_raw ""
    log_info "--- Database Size ---"
    run_sql "SELECT 'Data Files' AS file_type, ROUND(SUM(bytes)/1073741824,2) AS size_gb FROM dba_data_files
UNION ALL
SELECT 'Temp Files', ROUND(SUM(bytes)/1073741824,2) FROM dba_temp_files;" | tee -a "$REPORT_TXT"

    append_json_section "db_name" "$DB_NAME"
    append_json_section "db_unique_name" "$DB_UNIQUE_NAME"
    append_json_section "db_id" "$DB_ID"
    append_json_section "db_role" "$DB_ROLE"
    append_json_section "db_open_mode" "$DB_OPEN_MODE"
    append_json_section "db_log_mode" "$DB_LOG_MODE"
    append_json_section "db_force_logging" "$DB_FORCE_LOGGING"
    append_json_section "db_characterset" "$DB_CHARSET"
    append_json_section "db_ncharacterset" "$DB_NCHARSET"
} || log_warn "Database configuration discovery failed"

# ============================================================================
# 4. CONTAINER DATABASE (CDB) STATUS
# ============================================================================
log_section "4. CONTAINER DATABASE (CDB) STATUS"

{
    CDB_STATUS="$(run_sql_value "SELECT cdb FROM v\$database;")"
    log_info "CDB : $CDB_STATUS"
    append_json_section "is_cdb" "$CDB_STATUS"

    if [ "$CDB_STATUS" = "YES" ]; then
        log_raw ""
        log_info "--- PDBs ---"
        run_sql "SELECT con_id, name, open_mode, restricted FROM v\$pdbs ORDER BY con_id;" | tee -a "$REPORT_TXT"
    fi
} || log_warn "CDB status discovery failed"

# ============================================================================
# 5. TDE CONFIGURATION
# ============================================================================
log_section "5. TDE CONFIGURATION"

{
    log_raw ""
    log_info "--- Wallet Status ---"
    run_sql "SELECT wrl_type, wrl_parameter, status, wallet_type FROM v\$encryption_wallet;" | tee -a "$REPORT_TXT"

    log_raw ""
    log_info "--- Encrypted Tablespaces ---"
    run_sql "SELECT tablespace_name, encrypted FROM dba_tablespaces WHERE encrypted='YES' ORDER BY 1;" | tee -a "$REPORT_TXT"

    TDE_WALLET_STATUS="$(run_sql_value "SELECT status FROM v\$encryption_wallet WHERE rownum=1;")"
    TDE_WALLET_TYPE="$(run_sql_value "SELECT wallet_type FROM v\$encryption_wallet WHERE rownum=1;")"
    append_json_section "tde_wallet_status" "$TDE_WALLET_STATUS"
    append_json_section "tde_wallet_type" "$TDE_WALLET_TYPE"
} || log_warn "TDE configuration discovery failed"

# ============================================================================
# 6. SUPPLEMENTAL LOGGING
# ============================================================================
log_section "6. SUPPLEMENTAL LOGGING"

{
    run_sql "SELECT log_mode,
    supplemental_log_data_min AS min_suplog,
    supplemental_log_data_pk  AS pk_suplog,
    supplemental_log_data_ui  AS ui_suplog,
    supplemental_log_data_fk  AS fk_suplog,
    supplemental_log_data_all AS all_suplog
FROM v\$database;" | tee -a "$REPORT_TXT"

    SUPLOG_MIN="$(run_sql_value "SELECT supplemental_log_data_min FROM v\$database;")"
    SUPLOG_ALL="$(run_sql_value "SELECT supplemental_log_data_all FROM v\$database;")"
    append_json_section "supplemental_log_min" "$SUPLOG_MIN"
    append_json_section "supplemental_log_all" "$SUPLOG_ALL"
} || log_warn "Supplemental logging discovery failed"

# ============================================================================
# 7. REDO / ARCHIVE CONFIGURATION
# ============================================================================
log_section "7. REDO / ARCHIVE CONFIGURATION"

{
    log_info "--- Redo Log Groups ---"
    run_sql "SELECT l.group#, l.members, l.bytes/1048576 AS size_mb, l.status, m.member
FROM v\$log l JOIN v\$logfile m ON l.group#=m.group#
ORDER BY l.group#, m.member;" | tee -a "$REPORT_TXT"

    log_raw ""
    log_info "--- Archive Log Destinations ---"
    run_sql "SELECT dest_id, dest_name, status, target, archiver, schedule, destination
FROM v\$archive_dest WHERE status!='INACTIVE' ORDER BY dest_id;" | tee -a "$REPORT_TXT"

    ARCHIVE_DEST="$(run_sql_value "SELECT destination FROM v\$archive_dest WHERE dest_id=1 AND status='VALID';")"
    append_json_section "archive_log_dest1" "$ARCHIVE_DEST"
} || log_warn "Redo/archive configuration discovery failed"

# ============================================================================
# 8. NETWORK CONFIGURATION
# ============================================================================
log_section "8. NETWORK CONFIGURATION"

{
    log_info "--- Listener Status ---"
    lsnrctl status 2>&1 | tee -a "$REPORT_TXT" || log_warn "lsnrctl status failed"

    log_raw ""
    log_info "--- tnsnames.ora ---"
    TNS_ADMIN="${TNS_ADMIN:-${ORACLE_HOME:-}/network/admin}"
    if [ -f "$TNS_ADMIN/tnsnames.ora" ]; then
        cat "$TNS_ADMIN/tnsnames.ora" 2>/dev/null | tee -a "$REPORT_TXT"
    else
        log_warn "tnsnames.ora not found at $TNS_ADMIN/tnsnames.ora"
    fi

    log_raw ""
    log_info "--- sqlnet.ora ---"
    if [ -f "$TNS_ADMIN/sqlnet.ora" ]; then
        cat "$TNS_ADMIN/sqlnet.ora" 2>/dev/null | tee -a "$REPORT_TXT"
    else
        log_warn "sqlnet.ora not found at $TNS_ADMIN/sqlnet.ora"
    fi
} || log_warn "Network configuration discovery failed"

# ============================================================================
# 9. AUTHENTICATION
# ============================================================================
log_section "9. AUTHENTICATION"

{
    log_info "--- Password File ---"
    PWD_FILE_PATHS=("${ORACLE_HOME:-}/dbs/orapw${ORACLE_SID:-}" "${ORACLE_HOME:-}/dbs/orapwd" "${ORACLE_BASE:-}/dbs/orapw${ORACLE_SID:-}")
    PWD_FILE_FOUND="none"
    for pf in "${PWD_FILE_PATHS[@]}"; do
        if [ -f "$pf" ]; then
            log_info "Password file found: $pf"
            PWD_FILE_FOUND="$pf"
        fi
    done
    [ "$PWD_FILE_FOUND" = "none" ] && log_warn "Password file not found in standard locations"

    log_raw ""
    log_info "--- SSH Directory (~oracle) ---"
    sudo ls -la /home/"$ORACLE_USER"/.ssh/ 2>/dev/null | tee -a "$REPORT_TXT" || \
        ls -la ~/.ssh/ 2>/dev/null | tee -a "$REPORT_TXT" || \
        log_warn "SSH directory listing failed"

    append_json_section "password_file" "$PWD_FILE_FOUND"
} || log_warn "Authentication discovery failed"

# ============================================================================
# 10. DATA GUARD
# ============================================================================
log_section "10. DATA GUARD"

{
    run_sql "SELECT name, value FROM v\$parameter
WHERE name IN ('db_unique_name','log_archive_config','log_archive_dest_1','log_archive_dest_2',
               'fal_server','fal_client','standby_file_management','db_file_name_convert',
               'log_file_name_convert','dg_broker_start','dg_broker_config_file1')
ORDER BY name;" | tee -a "$REPORT_TXT"
} || log_warn "Data Guard configuration discovery failed"

# ============================================================================
# 11. SCHEMA INFORMATION
# ============================================================================
log_section "11. SCHEMA INFORMATION"

{
    log_info "--- Schema Sizes (non-system > 100MB) ---"
    run_sql "SELECT owner, ROUND(SUM(bytes)/1073741824,3) AS size_gb
FROM dba_segments
WHERE owner NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','WMSYS','OJVMSYS',
                    'DBSFWUSER','ORACLE_OCM','XDB','APEX_PUBLIC_USER','GSMADMIN_INTERNAL',
                    'GGSYS','ORDDATA','LBACSYS','CTXSYS','MDSYS','DVSYS','EXFSYS')
GROUP BY owner HAVING SUM(bytes) > 104857600
ORDER BY size_gb DESC;" | tee -a "$REPORT_TXT"

    log_raw ""
    log_info "--- Invalid Objects by Owner/Type ---"
    run_sql "SELECT owner, object_type, COUNT(*) AS invalid_count
FROM dba_objects WHERE status='INVALID'
GROUP BY owner, object_type ORDER BY owner, object_type;" | tee -a "$REPORT_TXT"
} || log_warn "Schema information discovery failed"

# ============================================================================
# 12. TABLESPACE CONFIGURATION (AUTOEXTEND)
# ============================================================================
log_section "12. TABLESPACE CONFIGURATION"

{
    log_info "--- Tablespace Autoextend Settings ---"
    run_sql "SELECT df.tablespace_name, df.file_name,
    ROUND(df.bytes/1073741824,2) AS current_size_gb,
    df.autoextensible AS autoextend,
    ROUND(df.maxbytes/1073741824,2) AS max_size_gb,
    ROUND(df.increment_by * 8192/1048576,2) AS increment_mb
FROM dba_data_files df
ORDER BY df.tablespace_name, df.file_name;" | tee -a "$REPORT_TXT"

    log_raw ""
    log_info "--- Tablespace Space Summary ---"
    run_sql "SELECT ts.tablespace_name, ts.block_size,
    ROUND(NVL(f.bytes,0)/1073741824,2) AS free_gb,
    ROUND(NVL(d.bytes,0)/1073741824,2) AS used_gb,
    ROUND(NVL(d.bytes,0)/(NVL(d.bytes,0)+NVL(f.bytes,0))*100,1) AS pct_used
FROM dba_tablespaces ts
LEFT JOIN (SELECT tablespace_name, SUM(bytes) bytes FROM dba_free_space GROUP BY tablespace_name) f
    ON ts.tablespace_name=f.tablespace_name
LEFT JOIN (SELECT tablespace_name, SUM(bytes) bytes FROM dba_segments GROUP BY tablespace_name) d
    ON ts.tablespace_name=d.tablespace_name
ORDER BY ts.tablespace_name;" | tee -a "$REPORT_TXT"
} || log_warn "Tablespace configuration discovery failed"

# ============================================================================
# 13. BACKUP CONFIGURATION
# ============================================================================
log_section "13. BACKUP CONFIGURATION"

{
    log_info "--- RMAN Retention Policy ---"
    run_sql "SELECT rman_status, name FROM v\$rman_configuration;" | tee -a "$REPORT_TXT" || true

    log_raw ""
    log_info "--- RMAN Configuration ---"
    run_sql "SELECT name, value FROM v\$rman_configuration ORDER BY conf#;" | tee -a "$REPORT_TXT"

    log_raw ""
    log_info "--- Last RMAN Backup Summary ---"
    run_sql "SELECT input_type, status, start_time, end_time, output_mbytes
FROM v\$rman_backup_job_details
ORDER BY start_time DESC
FETCH FIRST 10 ROWS ONLY;" | tee -a "$REPORT_TXT"

    log_raw ""
    log_info "--- Crontab Backup Entries ---"
    crontab -l 2>/dev/null | grep -i -E 'rman|backup|arch' | tee -a "$REPORT_TXT" || log_info "No backup-related crontab entries found (or no crontab)"

    log_raw ""
    log_info "--- DBMS_SCHEDULER Backup Jobs ---"
    run_sql "SELECT owner, job_name, enabled, last_start_date, next_run_date
FROM dba_scheduler_jobs
WHERE UPPER(job_name) LIKE '%BACKUP%' OR UPPER(job_name) LIKE '%RMAN%'
ORDER BY owner, job_name;" | tee -a "$REPORT_TXT"
} || log_warn "Backup configuration discovery failed"

# ============================================================================
# 14. DATABASE LINKS
# ============================================================================
log_section "14. DATABASE LINKS"

{
    run_sql "SELECT owner, db_link, host, username, created, valid
FROM dba_db_links
ORDER BY owner, db_link;" | tee -a "$REPORT_TXT"

    DB_LINK_COUNT="$(run_sql_value "SELECT COUNT(*) FROM dba_db_links;")"
    log_info "Total DB Links: $DB_LINK_COUNT"
    append_json_section "db_link_count" "$DB_LINK_COUNT"
} || log_warn "Database links discovery failed"

# ============================================================================
# 15. MATERIALIZED VIEWS
# ============================================================================
log_section "15. MATERIALIZED VIEWS"

{
    run_sql "SELECT owner, mview_name, refresh_method, refresh_mode, next_refresh_date, staleness
FROM dba_mviews
ORDER BY owner, mview_name;" | tee -a "$REPORT_TXT"

    log_raw ""
    log_info "--- Materialized View Logs ---"
    run_sql "SELECT log_owner, master, log_table, primary_key, rowid AS rowid_log, sequence AS seq_log
FROM dba_mview_logs
ORDER BY log_owner, master;" | tee -a "$REPORT_TXT"

    MV_COUNT="$(run_sql_value "SELECT COUNT(*) FROM dba_mviews;")"
    log_info "Total Materialized Views: $MV_COUNT"
    append_json_section "mview_count" "$MV_COUNT"
} || log_warn "Materialized view discovery failed"

# ============================================================================
# 16. SCHEDULER JOBS
# ============================================================================
log_section "16. SCHEDULER JOBS"

{
    run_sql "SELECT owner, job_name, job_type, schedule_type, enabled,
    last_start_date, next_run_date, state
FROM dba_scheduler_jobs
WHERE owner NOT IN ('SYS','ORACLE_OCM','EXFSYS','WMSYS','MDSYS')
ORDER BY owner, job_name;" | tee -a "$REPORT_TXT"

    log_raw ""
    log_info "--- Jobs Referencing External Paths or Credentials ---"
    run_sql "SELECT j.owner, j.job_name, p.argument_position, p.argument_name, p.value
FROM dba_scheduler_jobs j
JOIN dba_scheduler_job_args p ON j.owner=p.owner AND j.job_name=p.job_name
WHERE UPPER(p.value) LIKE '%HOST%' OR UPPER(p.value) LIKE '/%' OR UPPER(p.value) LIKE '%CRED%'
ORDER BY j.owner, j.job_name;" | tee -a "$REPORT_TXT"

    JOB_COUNT="$(run_sql_value "SELECT COUNT(*) FROM dba_scheduler_jobs WHERE owner NOT IN ('SYS','ORACLE_OCM','EXFSYS','WMSYS','MDSYS');")"
    log_info "Total User Scheduler Jobs: $JOB_COUNT"
    append_json_section "scheduler_job_count" "$JOB_COUNT"
} || log_warn "Scheduler job discovery failed"

# ============================================================================
# WRITE JSON SUMMARY
# ============================================================================
log_section "WRITING JSON SUMMARY"

{
cat > "$REPORT_JSON" <<JSON
{
  "report_type": "source_discovery",
  "generated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "run_by": "$(whoami)",
  "hostname": "$OS_HOSTNAME",
  "timestamp": "$TIMESTAMP",
  "oracle_environment": {
    "oracle_home": "${ORACLE_HOME:-UNDETERMINED}",
    "oracle_sid": "${ORACLE_SID:-UNDETERMINED}",
    "oracle_base": "${ORACLE_BASE:-UNDETERMINED}",
    "oracle_version": "${ORA_VERSION:-UNDETERMINED}",
    "oracle_user": "${ORACLE_USER}"
  },
  "database": {
    "db_name": "${DB_NAME:-UNDETERMINED}",
    "db_unique_name": "${DB_UNIQUE_NAME:-UNDETERMINED}",
    "dbid": "${DB_ID:-UNDETERMINED}",
    "role": "${DB_ROLE:-UNDETERMINED}",
    "open_mode": "${DB_OPEN_MODE:-UNDETERMINED}",
    "log_mode": "${DB_LOG_MODE:-UNDETERMINED}",
    "force_logging": "${DB_FORCE_LOGGING:-UNDETERMINED}",
    "characterset": "${DB_CHARSET:-UNDETERMINED}",
    "ncharacterset": "${DB_NCHARSET:-UNDETERMINED}",
    "is_cdb": "${CDB_STATUS:-UNDETERMINED}"
  },
  "tde": {
    "wallet_status": "${TDE_WALLET_STATUS:-UNDETERMINED}",
    "wallet_type": "${TDE_WALLET_TYPE:-UNDETERMINED}"
  },
  "supplemental_logging": {
    "min": "${SUPLOG_MIN:-UNDETERMINED}",
    "all": "${SUPLOG_ALL:-UNDETERMINED}"
  },
  "counts": {
    "db_links": "${DB_LINK_COUNT:-0}",
    "materialized_views": "${MV_COUNT:-0}",
    "scheduler_jobs": "${JOB_COUNT:-0}"
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
log_raw "  Source Discovery COMPLETE"
log_raw "  Text report : $REPORT_TXT"
log_raw "  JSON summary: $REPORT_JSON"
log_raw "  Completed   : $(date)"
log_raw "============================================================"

echo ""
echo "[DONE] Source discovery complete."
echo "  Text : $REPORT_TXT"
echo "  JSON : $REPORT_JSON"
