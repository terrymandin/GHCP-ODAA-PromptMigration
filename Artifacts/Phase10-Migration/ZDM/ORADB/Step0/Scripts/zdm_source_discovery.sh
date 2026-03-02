#!/bin/bash
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration
# =============================================================================
# zdm_source_discovery.sh
# ZDM Migration - Source Database Discovery Script
# Project: ORADB
#
# PURPOSE: Collects read-only diagnostic information from the source Oracle
#          database server to support ZDM migration planning.
#
# USAGE:   bash zdm_source_discovery.sh [options]
#          Options:
#            -h, --help     Show this help message
#            -v, --verbose  Enable verbose output
#
# OUTPUT:  ./zdm_source_discovery_<hostname>_<timestamp>.txt
#          ./zdm_source_discovery_<hostname>_<timestamp>.json
#
# NOTES:   - All operations are strictly READ-ONLY
#          - Script runs as SSH admin user; SQL executed via sudo -u oracle
#          - Requires: bash, sudo, sqlplus (via oracle user), standard Linux tools
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
REPORT_FILE="./zdm_source_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_source_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"
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

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        -h|--help)    show_help ;;
        -v|--verbose) VERBOSE=true ;;
    esac
done

# ---------------------------------------------------------------------------
# Initialise report file
# ---------------------------------------------------------------------------
mkdir -p "$(dirname "$REPORT_FILE")" 2>/dev/null || true
{
    echo "# ZDM Source Database Discovery Report"
    echo "# Generated: $(date)"
    echo "# Host:      $(hostname)"
    echo "# User:      $(whoami)"
    echo "# Script:    zdm_source_discovery.sh"
    echo "# Project:   ORADB"
    echo "# -------------------------------------------------------"
} > "$REPORT_FILE"

log_info "Source discovery started at $(date)"
log_info "Report file: $REPORT_FILE"
log_info "JSON file:   $JSON_FILE"

# ---------------------------------------------------------------------------
# Default users (overridable)
# ---------------------------------------------------------------------------
ORACLE_USER="${ORACLE_USER:-oracle}"

# ---------------------------------------------------------------------------
# Auto-detect Oracle environment
# ---------------------------------------------------------------------------
detect_oracle_env() {
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        log_debug "ORACLE_HOME and ORACLE_SID already set from environment"
        return 0
    fi

    log_info "Auto-detecting Oracle environment..."

    # Method 1: /etc/oratab
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

    # Method 2: Running pmon
    if [ -z "${ORACLE_SID:-}" ]; then
        local pmon_line
        pmon_line=$(ps -ef 2>/dev/null | grep 'ora_pmon_' | grep -v grep | head -1)
        if [ -n "$pmon_line" ]; then
            export ORACLE_SID="$(echo "$pmon_line" | sed 's/.*ora_pmon_//')"
            log_info "Oracle SID from pmon: $ORACLE_SID"
        fi
    fi

    # Method 3: Common paths
    if [ -z "${ORACLE_HOME:-}" ]; then
        for path in /u01/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1 /oracle/product/*/dbhome_1; do
            if [ -d "$path" ] && [ -f "$path/bin/sqlplus" ]; then
                export ORACLE_HOME="$path"
                log_info "ORACLE_HOME from path search: $ORACLE_HOME"
                break
            fi
        done
    fi

    # Method 4: oraenv
    if [ -z "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ] && [ -f /usr/local/bin/oraenv ]; then
        ORACLE_HOME=$(. /usr/local/bin/oraenv <<< "$ORACLE_SID" 2>/dev/null; echo "$ORACLE_HOME")
        [ -n "$ORACLE_HOME" ] && log_info "ORACLE_HOME from oraenv: $ORACLE_HOME"
    fi

    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        log_warn "Could not fully auto-detect Oracle environment (HOME=${ORACLE_HOME:-UNSET} SID=${ORACLE_SID:-UNSET})"
        return 1
    fi
    return 0
}

detect_oracle_env

# Apply explicit overrides (highest priority)
[ -n "${ORACLE_HOME_OVERRIDE:-}" ] && export ORACLE_HOME="$ORACLE_HOME_OVERRIDE" && log_info "ORACLE_HOME overridden: $ORACLE_HOME"
[ -n "${ORACLE_SID_OVERRIDE:-}" ]  && export ORACLE_SID="$ORACLE_SID_OVERRIDE"   && log_info "ORACLE_SID overridden: $ORACLE_SID"

export ORACLE_HOME="${ORACLE_HOME:-}"
export ORACLE_SID="${ORACLE_SID:-}"
export PATH="$PATH:${ORACLE_HOME}/bin"

# ---------------------------------------------------------------------------
# SQL execution helper
# ---------------------------------------------------------------------------
run_sql() {
    local sql_query="$1"
    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        echo "ERROR: ORACLE_HOME or ORACLE_SID not set; cannot run SQL"
        return 1
    fi
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
    local sql_query="$1"
    run_sql "SET HEADING OFF
SET FEEDBACK OFF
$sql_query" | grep -v '^$' | grep -v '^\s*$' | head -1 | xargs
}

# ---------------------------------------------------------------------------
# Declare JSON accumulators
# ---------------------------------------------------------------------------
declare -A JSON

json_set() { JSON["$1"]="$2"; }
json_set "timestamp"  "$(date -Iseconds 2>/dev/null || date)"
json_set "hostname"   "$HOSTNAME_SHORT"
json_set "report_file" "$REPORT_FILE"
json_set "project"    "ORADB"
json_set "script"     "zdm_source_discovery.sh"

# ---------------------------------------------------------------------------
# SECTION 1: OS Information
# ---------------------------------------------------------------------------
log_section "OS Information"
{
    log_raw "Hostname:        $(hostname)"
    log_raw "Short hostname:  $HOSTNAME_SHORT"
    log_raw "IP addresses:"
    ip addr show 2>/dev/null | grep 'inet ' | awk '{print "  " $2}' | tee -a "$REPORT_FILE" || \
        ifconfig 2>/dev/null | grep 'inet ' | awk '{print "  " $2}' | tee -a "$REPORT_FILE"
    log_raw "OS version:"
    cat /etc/os-release 2>/dev/null | tee -a "$REPORT_FILE" || uname -a | tee -a "$REPORT_FILE"
    log_raw "Kernel:          $(uname -r)"
    log_raw "Architecture:    $(uname -m)"
    log_raw ""
    log_raw "Disk space:"
    df -h 2>/dev/null | tee -a "$REPORT_FILE"
    log_raw ""
    log_raw "Memory:"
    free -h 2>/dev/null | tee -a "$REPORT_FILE"
} || log_error "OS information section failed"

json_set "os_hostname"   "$(hostname)"
json_set "os_kernel"     "$(uname -r)"

# ---------------------------------------------------------------------------
# SECTION 2: Oracle Environment
# ---------------------------------------------------------------------------
log_section "Oracle Environment"
{
    log_raw "ORACLE_HOME:  ${ORACLE_HOME:-NOT SET}"
    log_raw "ORACLE_SID:   ${ORACLE_SID:-NOT SET}"
    log_raw "ORACLE_BASE:  ${ORACLE_BASE:-NOT SET}"
    if [ -n "${ORACLE_HOME:-}" ]; then
        log_raw "Oracle Version:"
        "${ORACLE_HOME}/bin/sqlplus" -v 2>/dev/null | tee -a "$REPORT_FILE" || \
            cat "${ORACLE_HOME}/bin/oracle" 2>/dev/null | strings 2>/dev/null | grep 'RDBMS' | head -3 | tee -a "$REPORT_FILE"
    fi
    log_raw "Oracle binaries (ls -la \$ORACLE_HOME/bin/oracle):"
    ls -la "${ORACLE_HOME}/bin/oracle" 2>/dev/null | tee -a "$REPORT_FILE" || log_warn "Cannot stat oracle binary"
    log_raw "/etc/oratab contents:"
    cat /etc/oratab 2>/dev/null | tee -a "$REPORT_FILE" || log_warn "/etc/oratab not found"
} || log_error "Oracle environment section failed"

json_set "oracle_home"    "${ORACLE_HOME:-}"
json_set "oracle_sid"     "${ORACLE_SID:-}"
json_set "oracle_base"    "${ORACLE_BASE:-}"

# ---------------------------------------------------------------------------
# SECTION 3: Database Configuration
# ---------------------------------------------------------------------------
log_section "Database Configuration"
{
    log_raw "--- Database Name, Unique Name, DBID ---"
    run_sql "SELECT name, db_unique_name, dbid, created FROM v\$database;" | tee -a "$REPORT_FILE"

    log_raw "--- Database Role and Open Mode ---"
    run_sql "SELECT name, db_unique_name, database_role, open_mode, protection_mode FROM v\$database;" | tee -a "$REPORT_FILE"

    log_raw "--- Log Mode ---"
    run_sql "SELECT log_mode FROM v\$database;" | tee -a "$REPORT_FILE"

    log_raw "--- Force Logging ---"
    run_sql "SELECT force_logging FROM v\$database;" | tee -a "$REPORT_FILE"

    log_raw "--- Database Size (data files) ---"
    run_sql "SELECT ROUND(SUM(bytes)/1024/1024/1024,2) AS total_gb FROM dba_data_files;" | tee -a "$REPORT_FILE"

    log_raw "--- Temp File Size ---"
    run_sql "SELECT ROUND(SUM(bytes)/1024/1024/1024,2) AS temp_gb FROM dba_temp_files;" | tee -a "$REPORT_FILE"

    log_raw "--- Character Sets ---"
    run_sql "SELECT parameter, value FROM nls_database_parameters WHERE parameter IN ('NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET');" | tee -a "$REPORT_FILE"

    log_raw "--- DB Version ---"
    run_sql "SELECT version FROM v\$instance;" | tee -a "$REPORT_FILE"
} || log_error "Database configuration section failed"

json_set "db_name"       "$(run_sql_value "SELECT name FROM v\$database;")"
json_set "db_unique_name" "$(run_sql_value "SELECT db_unique_name FROM v\$database;")"
json_set "db_role"       "$(run_sql_value "SELECT database_role FROM v\$database;")"
json_set "log_mode"      "$(run_sql_value "SELECT log_mode FROM v\$database;")"
json_set "db_version"    "$(run_sql_value "SELECT version FROM v\$instance;")"

# ---------------------------------------------------------------------------
# SECTION 4: Container Database (CDB/PDB)
# ---------------------------------------------------------------------------
log_section "Container Database (CDB/PDB)"
{
    log_raw "--- CDB Status ---"
    run_sql "SELECT cdb, con_id FROM v\$database;" | tee -a "$REPORT_FILE"

    CDB_STATUS="$(run_sql_value "SELECT cdb FROM v\$database;")"
    json_set "is_cdb" "$CDB_STATUS"

    if [ "$CDB_STATUS" = "YES" ]; then
        log_raw "--- PDB Names and Status ---"
        run_sql "SELECT con_id, name, open_mode, restricted FROM v\$pdbs ORDER BY con_id;" | tee -a "$REPORT_FILE"
    else
        log_raw "Non-CDB database - no PDBs"
    fi
} || log_error "CDB/PDB section failed"

# ---------------------------------------------------------------------------
# SECTION 5: TDE Configuration
# ---------------------------------------------------------------------------
log_section "TDE Configuration"
{
    log_raw "--- TDE Wallet Status ---"
    run_sql "SELECT * FROM v\$encryption_wallet;" | tee -a "$REPORT_FILE"

    log_raw "--- Encrypted Tablespaces ---"
    run_sql "SELECT tablespace_name, encrypted FROM dba_tablespaces ORDER BY tablespace_name;" | tee -a "$REPORT_FILE"

    log_raw "--- Encryption Key Info ---"
    run_sql "SELECT key_id, tag, creation_time, key_use, keystore_type, origin, creator_dbname FROM v\$encryption_keys;" | tee -a "$REPORT_FILE" 2>/dev/null || log_warn "v\$encryption_keys not accessible"

    log_raw "--- sqlnet.ora (wallet location) ---"
    if [ -n "${ORACLE_HOME:-}" ]; then
        for f in "${ORACLE_HOME}/network/admin/sqlnet.ora" /etc/oracle/sqlnet.ora; do
            [ -f "$f" ] && { log_raw "File: $f"; cat "$f" | tee -a "$REPORT_FILE"; }
        done
    fi
} || log_error "TDE section failed"

# ---------------------------------------------------------------------------
# SECTION 6: Supplemental Logging
# ---------------------------------------------------------------------------
log_section "Supplemental Logging"
{
    run_sql "SELECT supplemental_log_data_min, supplemental_log_data_pk, supplemental_log_data_ui, supplemental_log_data_fk, supplemental_log_data_all FROM v\$database;" | tee -a "$REPORT_FILE"
} || log_error "Supplemental logging section failed"

# ---------------------------------------------------------------------------
# SECTION 7: Redo / Archive Configuration
# ---------------------------------------------------------------------------
log_section "Redo / Archive Configuration"
{
    log_raw "--- Redo Log Groups ---"
    run_sql "SELECT l.group#, l.members, l.bytes/1024/1024 AS size_mb, l.status FROM v\$log l ORDER BY l.group#;" | tee -a "$REPORT_FILE"

    log_raw "--- Redo Log Members ---"
    run_sql "SELECT group#, member, status FROM v\$logfile ORDER BY group#, member;" | tee -a "$REPORT_FILE"

    log_raw "--- Archive Log Destinations ---"
    run_sql "SELECT dest_id, dest_name, status, target, archiver, log_sequence, error FROM v\$archive_dest WHERE status != 'INACTIVE' ORDER BY dest_id;" | tee -a "$REPORT_FILE"

    log_raw "--- Archive Log Location ---"
    run_sql "SHOW PARAMETER log_archive_dest;" | tee -a "$REPORT_FILE"

    log_raw "--- Archive Log Format ---"
    run_sql "SHOW PARAMETER log_archive_format;" | tee -a "$REPORT_FILE"
} || log_error "Redo/archive section failed"

# ---------------------------------------------------------------------------
# SECTION 8: Network Configuration
# ---------------------------------------------------------------------------
log_section "Network Configuration"
{
    log_raw "--- Listener Status ---"
    if [ -n "${ORACLE_HOME:-}" ]; then
        "${ORACLE_HOME}/bin/lsnrctl" status 2>&1 | tee -a "$REPORT_FILE" || log_warn "lsnrctl status failed"
    fi

    log_raw "--- tnsnames.ora ---"
    if [ -n "${ORACLE_HOME:-}" ]; then
        for f in "${ORACLE_HOME}/network/admin/tnsnames.ora" /etc/oracle/tnsnames.ora; do
            [ -f "$f" ] && { log_raw "File: $f"; cat "$f" | tee -a "$REPORT_FILE"; }
        done
    fi

    log_raw "--- listener.ora ---"
    if [ -n "${ORACLE_HOME:-}" ]; then
        for f in "${ORACLE_HOME}/network/admin/listener.ora" /etc/oracle/listener.ora; do
            [ -f "$f" ] && { log_raw "File: $f"; cat "$f" | tee -a "$REPORT_FILE"; }
        done
    fi

    log_raw "--- sqlnet.ora ---"
    if [ -n "${ORACLE_HOME:-}" ]; then
        for f in "${ORACLE_HOME}/network/admin/sqlnet.ora" /etc/oracle/sqlnet.ora; do
            [ -f "$f" ] && { log_raw "File: $f"; cat "$f" | tee -a "$REPORT_FILE"; }
        done
    fi
} || log_error "Network configuration section failed"

# ---------------------------------------------------------------------------
# SECTION 9: Authentication
# ---------------------------------------------------------------------------
log_section "Authentication"
{
    log_raw "--- Password File Location ---"
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        for f in "${ORACLE_HOME}/dbs/orapw${ORACLE_SID}" "${ORACLE_HOME}/dbs/orapw"; do
            if [ -f "$f" ]; then
                log_raw "Password file found: $f"
                ls -la "$f" | tee -a "$REPORT_FILE"
            fi
        done
    fi

    log_raw "--- Oracle user SSH directory ---"
    local oracle_home_dir
    oracle_home_dir=$(eval echo "~${ORACLE_USER}" 2>/dev/null || getent passwd "$ORACLE_USER" | cut -d: -f6)
    if [ -d "${oracle_home_dir}/.ssh" ]; then
        ls -la "${oracle_home_dir}/.ssh/" 2>/dev/null | tee -a "$REPORT_FILE" || \
            sudo -u "$ORACLE_USER" ls -la ~/.ssh/ 2>/dev/null | tee -a "$REPORT_FILE"
    else
        log_warn "Oracle user .ssh directory not found at ${oracle_home_dir}/.ssh (not a blocker)"
    fi

    log_raw "--- Current user SSH keys ---"
    ls -la ~/.ssh/ 2>/dev/null | tee -a "$REPORT_FILE" || log_warn "~/.ssh not found for $(whoami)"
} || log_error "Authentication section failed"

# ---------------------------------------------------------------------------
# SECTION 10: Data Guard Parameters
# ---------------------------------------------------------------------------
log_section "Data Guard Parameters"
{
    run_sql "SELECT name, value FROM v\$parameter WHERE name LIKE 'log_archive_dest%' OR name LIKE 'dg_broker%' OR name LIKE 'db_unique_name' OR name LIKE 'standby%' ORDER BY name;" | tee -a "$REPORT_FILE"
    run_sql "SELECT * FROM v\$dataguard_config;" | tee -a "$REPORT_FILE" 2>/dev/null || log_info "v\$dataguard_config not available (no DG configured)"
} || log_error "Data Guard section failed"

# ---------------------------------------------------------------------------
# SECTION 11: Schema Information
# ---------------------------------------------------------------------------
log_section "Schema Information (non-system schemas > 100MB)"
{
    run_sql "SELECT owner, ROUND(SUM(bytes)/1024/1024/1024,3) AS size_gb
FROM dba_segments
WHERE owner NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','DBSFWUSER','GGSYS','ANONYMOUS',
                    'CTXSYS','DVSYS','DVF','GSMADMIN_INTERNAL','MDSYS','OLAPSYS','ORDDATA',
                    'ORDSYS','ORDPLUGINS','SI_INFORMTN_SCHEMA','WMSYS','XDB','APEX_030200',
                    'APEX_040000','APEX_040200','FLOWS_FILES','ORACLE_OCM','DBAAS_MONITORING',
                    'REMOTE_SCHEDULER_AGENT','AUDSYS','DIP','OJVMSYS','LBACSYS','MDDATA',
                    'SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','EXFSYS','TSMSYS','XS\$NULL')
GROUP BY owner
HAVING SUM(bytes)/1024/1024 > 100
ORDER BY size_gb DESC;" | tee -a "$REPORT_FILE"

    log_raw "--- Invalid Object Count by Owner/Type ---"
    run_sql "SELECT owner, object_type, COUNT(*) AS invalid_count
FROM dba_objects
WHERE status = 'INVALID'
GROUP BY owner, object_type
ORDER BY owner, object_type;" | tee -a "$REPORT_FILE"
} || log_error "Schema information section failed"

# ---------------------------------------------------------------------------
# SECTION 12: Tablespace Configuration (Autoextend & Sizes)
# ---------------------------------------------------------------------------
log_section "Tablespace Configuration"
{
    log_raw "--- Tablespace Summary ---"
    run_sql "SELECT ts.tablespace_name, ts.status, ts.contents, ts.logging,
       ROUND(SUM(df.bytes)/1024/1024/1024,3)   AS current_gb,
       ROUND(SUM(DECODE(df.autoextensible,'YES',df.maxbytes,df.bytes))/1024/1024/1024,3) AS max_gb
FROM dba_tablespaces ts
JOIN dba_data_files df ON ts.tablespace_name = df.tablespace_name
GROUP BY ts.tablespace_name, ts.status, ts.contents, ts.logging
ORDER BY ts.tablespace_name;" | tee -a "$REPORT_FILE"

    log_raw "--- Data File Autoextend Settings ---"
    run_sql "SELECT file_id, tablespace_name, file_name, autoextensible,
       ROUND(bytes/1024/1024/1024,3) AS current_gb,
       ROUND(maxbytes/1024/1024/1024,3) AS max_gb,
       ROUND(increment_by*8192/1024/1024,1) AS increment_mb
FROM dba_data_files
ORDER BY tablespace_name, file_id;" | tee -a "$REPORT_FILE"
} || log_error "Tablespace section failed"

# ---------------------------------------------------------------------------
# SECTION 13: Backup Configuration
# ---------------------------------------------------------------------------
log_section "Backup Configuration"
{
    log_raw "--- RMAN Retention Policy ---"
    run_sql "SELECT * FROM v\$rman_configuration;" | tee -a "$REPORT_FILE"

    log_raw "--- Last Successful Backup ---"
    run_sql "SELECT input_type, status, start_time, end_time, input_bytes_display, output_bytes_display
FROM v\$rman_backup_job_details
WHERE status = 'COMPLETED'
ORDER BY end_time DESC
FETCH FIRST 5 ROWS ONLY;" | tee -a "$REPORT_FILE" 2>/dev/null || \
    run_sql "SELECT input_type, status, start_time, end_time FROM v\$rman_backup_job_details WHERE status='COMPLETED' ORDER BY end_time DESC;" | head -20 | tee -a "$REPORT_FILE"

    log_raw "--- RMAN Archive Log Deletion Policy ---"
    run_sql "SELECT name, value FROM v\$rman_configuration WHERE name LIKE '%ARCHIVELOG%';" | tee -a "$REPORT_FILE"

    log_raw "--- Crontab (backup jobs) ---"
    crontab -l 2>/dev/null | tee -a "$REPORT_FILE" || log_info "No crontab for $(whoami)"
    sudo -u "$ORACLE_USER" crontab -l 2>/dev/null | tee -a "$REPORT_FILE" || log_info "No crontab for $ORACLE_USER"

    log_raw "--- DBMS_SCHEDULER Backup Jobs ---"
    run_sql "SELECT owner, job_name, job_type, enabled, state, last_start_date, next_run_date
FROM dba_scheduler_jobs
WHERE UPPER(job_name) LIKE '%BACKUP%' OR UPPER(job_name) LIKE '%RMAN%'
ORDER BY owner, job_name;" | tee -a "$REPORT_FILE"
} || log_error "Backup configuration section failed"

# ---------------------------------------------------------------------------
# SECTION 14: Database Links
# ---------------------------------------------------------------------------
log_section "Database Links"
{
    run_sql "SELECT owner, db_link, username, host, created
FROM dba_db_links
ORDER BY owner, db_link;" | tee -a "$REPORT_FILE"
} || log_error "Database links section failed"

# ---------------------------------------------------------------------------
# SECTION 15: Materialized Views
# ---------------------------------------------------------------------------
log_section "Materialized Views"
{
    run_sql "SELECT owner, mview_name, refresh_method, refresh_mode, last_refresh_type, last_refresh_date, next
FROM dba_mviews
ORDER BY owner, mview_name;" | tee -a "$REPORT_FILE"

    log_raw "--- Materialized View Logs ---"
    run_sql "SELECT log_owner, master, log_table, rowids, primary_key, log_date, sequence, include_new_values
FROM dba_mview_logs
ORDER BY log_owner, master;" | tee -a "$REPORT_FILE"
} || log_error "Materialized views section failed"

# ---------------------------------------------------------------------------
# SECTION 16: Scheduler Jobs
# ---------------------------------------------------------------------------
log_section "Scheduler Jobs"
{
    run_sql "SELECT owner, job_name, job_type, job_action, schedule_type, enabled, state,
       last_start_date, next_run_date
FROM dba_scheduler_jobs
ORDER BY owner, job_name;" | tee -a "$REPORT_FILE"

    log_raw "--- Jobs Referencing External Paths or Credentials ---"
    run_sql "SELECT owner, job_name, job_action
FROM dba_scheduler_jobs
WHERE job_action LIKE '%/home/%'
   OR job_action LIKE '%/tmp/%'
   OR job_action LIKE '%hostname%'
   OR job_action LIKE '%@%'
ORDER BY owner, job_name;" | tee -a "$REPORT_FILE"
} || log_error "Scheduler jobs section failed"

# ---------------------------------------------------------------------------
# Summary and JSON output
# ---------------------------------------------------------------------------
log_section "Discovery Summary"
log_raw "Errors encountered: ${#ERRORS[@]}"
for e in "${ERRORS[@]}"; do log_raw "  ERROR: $e"; done
log_raw "Warnings encountered: ${#WARNINGS[@]}"
for w in "${WARNINGS[@]}"; do log_raw "  WARN:  $w"; done
log_raw "Report file:  $REPORT_FILE"
log_raw "JSON file:    $JSON_FILE"
log_raw "Completed at: $(date)"

json_set "error_count"   "${#ERRORS[@]}"
json_set "warning_count" "${#WARNINGS[@]}"
json_set "completed_at"  "$(date -Iseconds 2>/dev/null || date)"

# Write JSON
{
    echo "{"
    first=true
    for key in "${!JSON[@]}"; do
        val="${JSON[$key]}"
        # Escape value for JSON
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

log_info "Source discovery complete. Output files:"
log_info "  Text:  $REPORT_FILE"
log_info "  JSON:  $JSON_FILE"
