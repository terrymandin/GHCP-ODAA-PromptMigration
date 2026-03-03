#!/bin/bash
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration
# ===================================================================================
# zdm_source_discovery.sh
# ZDM Migration - Source Database Discovery
# Project: ORADB
# ===================================================================================
# Purpose: Gather technical context from the source database server.
#          ALL operations are strictly read-only.
#
# Usage:
#   chmod +x zdm_source_discovery.sh
#   ./zdm_source_discovery.sh
#
# Environment Variable Overrides (optional):
#   ORACLE_HOME          - Override auto-detected ORACLE_HOME
#   ORACLE_SID           - Override auto-detected ORACLE_SID
#   ORACLE_USER          - Oracle software owner (default: oracle)
# ===================================================================================

set -o pipefail

# --------------------------------------------------------------------------
# Color codes
# --------------------------------------------------------------------------
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --------------------------------------------------------------------------
# Global state
# --------------------------------------------------------------------------
HOSTNAME_SHORT=$(hostname -s 2>/dev/null || hostname)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="./zdm_source_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_source_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

ORACLE_USER="${ORACLE_USER:-oracle}"
declare -A JSON_DATA

# --------------------------------------------------------------------------
# Logging helpers
# --------------------------------------------------------------------------
log_info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_section() { echo -e "\n${BOLD}${CYAN}=== $* ===${NC}"; }

log_raw() {
    echo "$*" >> "$REPORT_FILE"
}

report_section() {
    log_raw ""
    log_raw "=================================================================="
    log_raw "  $*"
    log_raw "=================================================================="
}

report_kv() {
    local key="$1"
    local val="$2"
    printf "  %-45s %s\n" "$key:" "$val" >> "$REPORT_FILE"
}

# --------------------------------------------------------------------------
# Auto-detect Oracle environment
# --------------------------------------------------------------------------
detect_oracle_env() {
    # If already set, use existing values
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        log_info "Using pre-set ORACLE_HOME=$ORACLE_HOME ORACLE_SID=$ORACLE_SID"
        return 0
    fi

    log_info "Auto-detecting Oracle environment..."

    # Method 1: Parse /etc/oratab
    if [ -f /etc/oratab ]; then
        local oratab_entry
        if [ -n "${ORACLE_SID:-}" ]; then
            oratab_entry=$(grep "^${ORACLE_SID}:" /etc/oratab 2>/dev/null | head -1)
        else
            oratab_entry=$(grep -v '^#' /etc/oratab 2>/dev/null | grep -v '^$' | head -1)
        fi
        if [ -n "$oratab_entry" ]; then
            export ORACLE_SID="${ORACLE_SID:-$(echo "$oratab_entry" | cut -d: -f1)}"
            export ORACLE_HOME="${ORACLE_HOME:-$(echo "$oratab_entry" | cut -d: -f2)}"
            log_info "Detected from /etc/oratab: ORACLE_SID=$ORACLE_SID ORACLE_HOME=$ORACLE_HOME"
        fi
    fi

    # Method 2: Check running pmon process
    if [ -z "${ORACLE_SID:-}" ]; then
        local pmon_sid
        pmon_sid=$(ps -ef 2>/dev/null | grep 'ora_pmon_' | grep -v grep | head -1 | sed 's/.*ora_pmon_//')
        if [ -n "$pmon_sid" ]; then
            export ORACLE_SID="$pmon_sid"
            log_info "Detected ORACLE_SID=$ORACLE_SID from pmon process"
        fi
    fi

    # Method 3: Search common Oracle installation paths
    if [ -z "${ORACLE_HOME:-}" ]; then
        for path in /u01/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1 /oracle/product/*/dbhome_1; do
            if [ -d "$path" ] && [ -f "$path/bin/sqlplus" ]; then
                export ORACLE_HOME="$path"
                log_info "Detected ORACLE_HOME=$ORACLE_HOME from common paths"
                break
            fi
        done
    fi

    # Method 4: Check oraenv
    if [ -z "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        if [ -f /usr/local/bin/oraenv ]; then
            export ORACLE_BASE="${ORACLE_BASE:-/u01/app/oracle}"
            ORACLE_HOME=$(echo "$ORACLE_SID" | /usr/local/bin/oraenv 2>/dev/null | grep ORACLE_HOME | awk '{print $NF}')
            [ -n "$ORACLE_HOME" ] && export ORACLE_HOME && log_info "Detected ORACLE_HOME=$ORACLE_HOME via oraenv"
        fi
    fi

    # Apply explicit overrides if provided
    [ -n "${ORACLE_HOME_OVERRIDE:-}" ] && export ORACLE_HOME="$ORACLE_HOME_OVERRIDE"
    [ -n "${ORACLE_SID_OVERRIDE:-}" ]  && export ORACLE_SID="$ORACLE_SID_OVERRIDE"
}

# --------------------------------------------------------------------------
# SQL execution helper - uses sudo if not already oracle user
# --------------------------------------------------------------------------
run_sql() {
    local sql_query="$1"
    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        echo "ERROR: ORACLE_HOME or ORACLE_SID not set"
        return 1
    fi
    local sqlplus_cmd="$ORACLE_HOME/bin/sqlplus -s / as sysdba"
    local sql_script
    sql_script=$(cat <<EOSQL
SET PAGESIZE 1000
SET LINESIZE 200
SET FEEDBACK OFF
SET HEADING ON
SET ECHO OFF
SET TRIMSPOOL ON
$sql_query
EOSQL
)
    if [ "$(whoami)" = "$ORACLE_USER" ]; then
        echo "$sql_script" | $sqlplus_cmd 2>/dev/null
    else
        echo "$sql_script" | sudo -u "$ORACLE_USER" -E ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd 2>/dev/null
    fi
}

run_sql_value() {
    local sql_query="$1"
    run_sql "SET HEADING OFF
$sql_query" 2>/dev/null | grep -v '^$' | head -1 | xargs
}

# --------------------------------------------------------------------------
# Section: OS Information
# --------------------------------------------------------------------------
discover_os_info() {
    log_section "OS Information"
    report_section "OS INFORMATION"

    local os_hostname
    os_hostname=$(hostname -f 2>/dev/null || hostname)
    local os_short
    os_short=$(hostname -s 2>/dev/null || hostname)
    local os_ip
    os_ip=$(hostname -I 2>/dev/null | tr ' ' ',')
    local os_version
    os_version=$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"' || uname -r)
    local os_kernel
    os_kernel=$(uname -r 2>/dev/null)
    local os_arch
    os_arch=$(uname -m 2>/dev/null)
    local disk_space
    disk_space=$(df -h 2>/dev/null | grep -v tmpfs | grep -v udev)

    report_kv "Hostname (FQDN)" "$os_hostname"
    report_kv "Hostname (short)" "$os_short"
    report_kv "IP Addresses" "$os_ip"
    report_kv "OS Version" "$os_version"
    report_kv "Kernel" "$os_kernel"
    report_kv "Architecture" "$os_arch"
    log_raw ""
    log_raw "  Disk Space:"
    log_raw "$disk_space" | awk '{printf "    %s\n", $0}'

    JSON_DATA["hostname"]="$os_hostname"
    JSON_DATA["ip_addresses"]="$os_ip"
    JSON_DATA["os_version"]="$os_version"
    JSON_DATA["os_kernel"]="$os_kernel"

    log_info "OS info captured: $os_hostname / $os_version"
}

# --------------------------------------------------------------------------
# Section: Oracle Environment
# --------------------------------------------------------------------------
discover_oracle_env() {
    log_section "Oracle Environment"
    report_section "ORACLE ENVIRONMENT"

    detect_oracle_env

    if [ -z "${ORACLE_HOME:-}" ]; then
        log_warn "ORACLE_HOME could not be detected"
        report_kv "ORACLE_HOME" "NOT DETECTED"
        JSON_DATA["oracle_home"]="NOT DETECTED"
        return
    fi

    local ora_version
    ora_version=$(run_sql_value "SELECT version FROM v\$instance;" 2>/dev/null)
    [ -z "$ora_version" ] && ora_version=$(strings "$ORACLE_HOME/bin/oracle" 2>/dev/null | grep 'CORE.*Production' | head -1 | awk '{print $2}')

    local ora_base="${ORACLE_BASE:-$(run_sql_value "SELECT value FROM v\$parameter WHERE name='db_create_file_dest';" 2>/dev/null)}"

    report_kv "ORACLE_HOME" "$ORACLE_HOME"
    report_kv "ORACLE_SID" "${ORACLE_SID:-N/A}"
    report_kv "ORACLE_BASE" "${ora_base:-N/A}"
    report_kv "Oracle Version" "${ora_version:-N/A}"

    JSON_DATA["oracle_home"]="$ORACLE_HOME"
    JSON_DATA["oracle_sid"]="${ORACLE_SID:-}"
    JSON_DATA["oracle_version"]="${ora_version:-}"

    log_info "Oracle env: ORACLE_HOME=$ORACLE_HOME SID=$ORACLE_SID VER=$ora_version"
}

# --------------------------------------------------------------------------
# Section: Database Configuration
# --------------------------------------------------------------------------
discover_db_config() {
    log_section "Database Configuration"
    report_section "DATABASE CONFIGURATION"

    local db_name db_unique log_mode force_log role open_mode dbid charset nls_ncharset
    db_name=$(run_sql_value     "SELECT name FROM v\$database;")
    db_unique=$(run_sql_value   "SELECT db_unique_name FROM v\$database;")
    dbid=$(run_sql_value        "SELECT dbid FROM v\$database;")
    role=$(run_sql_value        "SELECT database_role FROM v\$database;")
    open_mode=$(run_sql_value   "SELECT open_mode FROM v\$database;")
    log_mode=$(run_sql_value    "SELECT log_mode FROM v\$database;")
    force_log=$(run_sql_value   "SELECT force_logging FROM v\$database;")
    charset=$(run_sql_value     "SELECT value FROM nls_database_parameters WHERE parameter='NLS_CHARACTERSET';")
    nls_ncharset=$(run_sql_value "SELECT value FROM nls_database_parameters WHERE parameter='NLS_NCHAR_CHARACTERSET';")

    # Database size
    local data_size temp_size
    data_size=$(run_sql_value   "SELECT ROUND(SUM(bytes)/1024/1024/1024,2)||' GB' FROM dba_data_files;")
    temp_size=$(run_sql_value   "SELECT ROUND(SUM(bytes)/1024/1024/1024,2)||' GB' FROM dba_temp_files;")

    report_kv "Database Name" "$db_name"
    report_kv "DB Unique Name" "$db_unique"
    report_kv "DBID" "$dbid"
    report_kv "Database Role" "$role"
    report_kv "Open Mode" "$open_mode"
    report_kv "Log Mode" "$log_mode"
    report_kv "Force Logging" "$force_log"
    report_kv "Data Files Size" "$data_size"
    report_kv "Temp Files Size" "$temp_size"
    report_kv "Character Set" "$charset"
    report_kv "NLS National Charset" "$nls_ncharset"

    JSON_DATA["db_name"]="$db_name"
    JSON_DATA["db_unique_name"]="$db_unique"
    JSON_DATA["dbid"]="$dbid"
    JSON_DATA["db_role"]="$role"
    JSON_DATA["log_mode"]="$log_mode"
    JSON_DATA["force_logging"]="$force_log"
    JSON_DATA["db_size_gb"]="$data_size"
    JSON_DATA["charset"]="$charset"

    if [ "$log_mode" != "ARCHIVELOG" ]; then
        log_warn "Database is NOT in ARCHIVELOG mode - required for ZDM online migration"
    else
        log_info "Database is in ARCHIVELOG mode - OK"
    fi
}

# --------------------------------------------------------------------------
# Section: Container Database (CDB/PDB)
# --------------------------------------------------------------------------
discover_cdb_pdb() {
    log_section "Container Database (CDB/PDB)"
    report_section "CONTAINER DATABASE"

    local is_cdb
    is_cdb=$(run_sql_value "SELECT cdb FROM v\$database;")

    report_kv "CDB" "${is_cdb:-N/A}"
    JSON_DATA["is_cdb"]="${is_cdb:-}"

    if [ "${is_cdb^^}" = "YES" ]; then
        log_info "Database IS a CDB - discovering PDBs..."
        log_raw ""
        log_raw "  PDB List:"
        run_sql "SELECT name, open_mode, restricted, con_id FROM v\$pdbs ORDER BY con_id;" >> "$REPORT_FILE" 2>/dev/null
    else
        log_info "Database is NOT a CDB (non-container)"
        log_raw "  Non-container database (CDB=NO)"
    fi
}

# --------------------------------------------------------------------------
# Section: TDE Configuration
# --------------------------------------------------------------------------
discover_tde() {
    log_section "TDE Configuration"
    report_section "TDE CONFIGURATION"

    local wallet_status wallet_type wallet_location
    wallet_status=$(run_sql_value  "SELECT status FROM v\$encryption_wallet;" 2>/dev/null || echo "N/A")
    wallet_type=$(run_sql_value    "SELECT wallet_type FROM v\$encryption_wallet;" 2>/dev/null || echo "N/A")
    wallet_location=$(run_sql_value "SELECT wrl_parameter FROM v\$encryption_wallet WHERE rownum=1;" 2>/dev/null || echo "N/A")

    report_kv "Wallet Status" "$wallet_status"
    report_kv "Wallet Type" "$wallet_type"
    report_kv "Wallet Location" "$wallet_location"
    JSON_DATA["tde_wallet_status"]="$wallet_status"
    JSON_DATA["tde_wallet_type"]="$wallet_type"

    local tde_enabled="false"
    if [ "$wallet_status" = "OPEN" ] || [ "$wallet_status" = "OPEN_NO_MASTER_KEY" ]; then
        tde_enabled="true"
    fi
    JSON_DATA["tde_enabled"]="$tde_enabled"

    log_raw ""
    log_raw "  Encrypted Tablespaces:"
    run_sql "SELECT tablespace_name, encrypted FROM dba_tablespaces WHERE encrypted='YES' ORDER BY tablespace_name;" >> "$REPORT_FILE" 2>/dev/null
}

# --------------------------------------------------------------------------
# Section: Supplemental Logging
# --------------------------------------------------------------------------
discover_supplemental_logging() {
    log_section "Supplemental Logging"
    report_section "SUPPLEMENTAL LOGGING"

    run_sql "SELECT log_mode, supplemental_log_data_min, supplemental_log_data_pk,
                    supplemental_log_data_ui, supplemental_log_data_fk, supplemental_log_data_all
             FROM v\$database;" >> "$REPORT_FILE" 2>/dev/null

    local sup_min
    sup_min=$(run_sql_value "SELECT supplemental_log_data_min FROM v\$database;")
    JSON_DATA["suplog_min"]="$sup_min"

    if [ "$sup_min" != "YES" ]; then
        log_warn "Supplemental logging MINIMUM is not enabled - required for ZDM migration"
    else
        log_info "Supplemental logging minimum: $sup_min"
    fi
}

# --------------------------------------------------------------------------
# Section: Redo and Archive Configuration
# --------------------------------------------------------------------------
discover_redo_archive() {
    log_section "Redo/Archive Configuration"
    report_section "REDO AND ARCHIVE CONFIGURATION"

    log_raw "  Redo Log Groups:"
    run_sql "SELECT group#, thread#, sequence#, bytes/1024/1024 AS size_mb, members, status
             FROM v\$log ORDER BY group#;" >> "$REPORT_FILE" 2>/dev/null

    log_raw ""
    log_raw "  Redo Log Members:"
    run_sql "SELECT group#, member, status FROM v\$logfile ORDER BY group#, member;" >> "$REPORT_FILE" 2>/dev/null

    log_raw ""
    log_raw "  Archive Log Destinations:"
    run_sql "SELECT dest_id, dest_name, status, target, archiver, schedule,
                    destination, error
             FROM v\$archive_dest WHERE status <> 'INACTIVE' ORDER BY dest_id;" >> "$REPORT_FILE" 2>/dev/null

    log_raw ""
    log_raw "  Archive Log Summary (last 24h):"
    run_sql "SELECT TO_CHAR(completion_time,'YYYY-MM-DD HH24') AS hour,
                    COUNT(*) AS count, ROUND(SUM(blocks*block_size)/1024/1024/1024,2) AS size_gb
             FROM v\$archived_log
             WHERE completion_time > SYSDATE - 1 AND standby_dest = 'NO'
             GROUP BY TO_CHAR(completion_time,'YYYY-MM-DD HH24')
             ORDER BY 1;" >> "$REPORT_FILE" 2>/dev/null
}

# --------------------------------------------------------------------------
# Section: Network Configuration
# --------------------------------------------------------------------------
discover_network() {
    log_section "Network Configuration"
    report_section "NETWORK CONFIGURATION"

    log_raw "  IP Addresses:"
    ip addr 2>/dev/null | grep 'inet ' | awk '{printf "    %s\n", $0}' >> "$REPORT_FILE"

    log_raw ""
    log_raw "  Listener Status:"
    if [ "$(whoami)" = "$ORACLE_USER" ]; then
        "$ORACLE_HOME/bin/lsnrctl" status 2>/dev/null >> "$REPORT_FILE"
    else
        sudo -u "$ORACLE_USER" -E ORACLE_HOME="$ORACLE_HOME" TNS_ADMIN="${TNS_ADMIN:-$ORACLE_HOME/network/admin}" \
            "$ORACLE_HOME/bin/lsnrctl" status 2>/dev/null >> "$REPORT_FILE"
    fi

    log_raw ""
    log_raw "  tnsnames.ora:"
    local tns_admin="${TNS_ADMIN:-$ORACLE_HOME/network/admin}"
    if [ -f "$tns_admin/tnsnames.ora" ]; then
        cat "$tns_admin/tnsnames.ora" 2>/dev/null | awk '{printf "    %s\n", $0}' >> "$REPORT_FILE"
    else
        log_raw "    tnsnames.ora not found at $tns_admin/tnsnames.ora"
    fi

    log_raw ""
    log_raw "  sqlnet.ora:"
    if [ -f "$tns_admin/sqlnet.ora" ]; then
        cat "$tns_admin/sqlnet.ora" 2>/dev/null | awk '{printf "    %s\n", $0}' >> "$REPORT_FILE"
    else
        log_raw "    sqlnet.ora not found at $tns_admin/sqlnet.ora"
    fi

    JSON_DATA["tns_admin"]="$tns_admin"
}

# --------------------------------------------------------------------------
# Section: Authentication
# --------------------------------------------------------------------------
discover_auth() {
    log_section "Authentication"
    report_section "AUTHENTICATION"

    # Password file
    local pwfile
    pwfile=$(find "$ORACLE_HOME/dbs" -name "orapw*" 2>/dev/null | head -1)
    report_kv "Password File" "${pwfile:-NOT FOUND}"

    # SSH directory (as oracle user)
    log_raw ""
    log_raw "  Oracle user SSH directory:"
    if [ "$(whoami)" = "$ORACLE_USER" ]; then
        ls -la ~/.ssh 2>/dev/null | awk '{printf "    %s\n", $0}' >> "$REPORT_FILE" || log_raw "    ~/.ssh not found or not accessible"
    else
        sudo -u "$ORACLE_USER" ls -la "~${ORACLE_USER}/.ssh" 2>/dev/null | awk '{printf "    %s\n", $0}' >> "$REPORT_FILE" || log_raw "    SSH directory not accessible via sudo"
    fi

    JSON_DATA["password_file"]="${pwfile:-NOT FOUND}"
}

# --------------------------------------------------------------------------
# Section: Data Guard
# --------------------------------------------------------------------------
discover_dataguard() {
    log_section "Data Guard"
    report_section "DATA GUARD"

    log_raw "  Data Guard Parameters:"
    run_sql "SELECT name, value FROM v\$parameter
             WHERE name IN ('log_archive_config','log_archive_dest_1','log_archive_dest_2',
                            'log_archive_dest_3','db_unique_name','fal_server','fal_client',
                            'standby_file_management','dg_broker_config_file1','dg_broker_start')
             ORDER BY name;" >> "$REPORT_FILE" 2>/dev/null

    local dg_config
    dg_config=$(run_sql_value "SELECT value FROM v\$parameter WHERE name='log_archive_config';")
    JSON_DATA["dg_log_archive_config"]="${dg_config:-}"
}

# --------------------------------------------------------------------------
# Section: Schema Information
# --------------------------------------------------------------------------
discover_schemas() {
    log_section "Schema Information"
    report_section "SCHEMA INFORMATION"

    log_raw "  Non-System Schemas > 100MB:"
    run_sql "SELECT owner, ROUND(SUM(bytes)/1024/1024/1024,3) AS size_gb, COUNT(*) AS segments
             FROM dba_segments
             WHERE owner NOT IN ('SYS','SYSTEM','DBSNMP','SYSMAN','OUTLN','MDSYS','ORDSYS',
                                 'EXFSYS','DMSYS','WMSYS','CTXSYS','ANONYMOUS','XDB','XS\$NULL',
                                 'ORDPLUGINS','LBACSYS','OLAPSYS','AURORA\$JIS\$UTILITY\$',
                                 'SI_INFORMTN_SCHEMA','ORDDATA','APEX_040200','FLOWS_FILES',
                                 'APEX_PUBLIC_USER','FLOWS_30000','SPATIAL_WFS_ADMIN_USR',
                                 'SPATIAL_CSW_ADMIN_USR','MDDATA','DIP','ORACLE_OCM','GSMADMIN_INTERNAL',
                                 'GSMCATUSER','SYSBACKUP','SYSDG','SYSKM','APPQOSSYS','ORDS_METADATA')
             GROUP BY owner
             HAVING SUM(bytes)/1024/1024 > 100
             ORDER BY size_gb DESC;" >> "$REPORT_FILE" 2>/dev/null

    log_raw ""
    log_raw "  Invalid Objects by Owner/Type:"
    run_sql "SELECT owner, object_type, COUNT(*) AS invalid_count
             FROM dba_objects WHERE status='INVALID'
             GROUP BY owner, object_type ORDER BY owner, object_type;" >> "$REPORT_FILE" 2>/dev/null
}

# --------------------------------------------------------------------------
# Section: Tablespace Configuration
# --------------------------------------------------------------------------
discover_tablespaces() {
    log_section "Tablespace Configuration"
    report_section "TABLESPACE CONFIGURATION"

    log_raw "  Tablespace Autoextend Settings:"
    run_sql "SELECT d.tablespace_name, d.file_name,
                    ROUND(d.bytes/1024/1024/1024,2) AS current_gb,
                    ROUND(d.maxbytes/1024/1024/1024,2) AS max_gb,
                    ROUND(d.increment_by * 8192/1024/1024,2) AS increment_mb,
                    d.autoextensible
             FROM dba_data_files d ORDER BY d.tablespace_name, d.file_name;" >> "$REPORT_FILE" 2>/dev/null

    log_raw ""
    log_raw "  Tablespace Usage Summary:"
    run_sql "SELECT t.tablespace_name, t.status,
                    ROUND(NVL(a.bytes,0)/1024/1024/1024,2) AS total_gb,
                    ROUND(NVL(f.bytes,0)/1024/1024/1024,2) AS free_gb,
                    ROUND((NVL(a.bytes,0)-NVL(f.bytes,0))*100/NVL(a.bytes,1),1) AS pct_used
             FROM dba_tablespaces t
             LEFT JOIN (SELECT tablespace_name, SUM(bytes) AS bytes FROM dba_data_files GROUP BY tablespace_name) a
                    ON t.tablespace_name=a.tablespace_name
             LEFT JOIN (SELECT tablespace_name, SUM(bytes) AS bytes FROM dba_free_space GROUP BY tablespace_name) f
                    ON t.tablespace_name=f.tablespace_name
             WHERE t.contents <> 'TEMPORARY'
             ORDER BY t.tablespace_name;" >> "$REPORT_FILE" 2>/dev/null
}

# --------------------------------------------------------------------------
# Section: Backup Configuration
# --------------------------------------------------------------------------
discover_backup() {
    log_section "Backup Configuration"
    report_section "BACKUP CONFIGURATION"

    log_raw "  RMAN Configuration:"
    run_sql "SELECT name, value FROM v\$rman_configuration ORDER BY name;" >> "$REPORT_FILE" 2>/dev/null

    log_raw ""
    log_raw "  Last Successful Backup:"
    run_sql "SELECT session_key, session_recid, input_type,
                    TO_CHAR(start_time,'YYYY-MM-DD HH24:MI:SS') AS start_time,
                    TO_CHAR(end_time,'YYYY-MM-DD HH24:MI:SS') AS end_time,
                    status, input_bytes_display, output_bytes_display
             FROM v\$rman_backup_job_details
             WHERE status='COMPLETED'
             ORDER BY session_key DESC FETCH FIRST 5 ROWS ONLY;" >> "$REPORT_FILE" 2>/dev/null

    log_raw ""
    log_raw "  Backup-Related Crontab (current user):"
    crontab -l 2>/dev/null | grep -i 'rman\|backup' | awk '{printf "    %s\n", $0}' >> "$REPORT_FILE" || log_raw "    (no crontab or no backup entries)"

    log_raw ""
    log_raw "  Backup-Related DBMS_SCHEDULER Jobs:"
    run_sql "SELECT owner, job_name, job_action, repeat_interval, enabled, state,
                    TO_CHAR(last_start_date,'YYYY-MM-DD HH24:MI:SS') AS last_run,
                    TO_CHAR(next_run_date,'YYYY-MM-DD HH24:MI:SS') AS next_run
             FROM dba_scheduler_jobs
             WHERE UPPER(job_action) LIKE '%RMAN%' OR UPPER(job_name) LIKE '%BACKUP%'
             ORDER BY owner, job_name;" >> "$REPORT_FILE" 2>/dev/null
}

# --------------------------------------------------------------------------
# Section: Database Links
# --------------------------------------------------------------------------
discover_db_links() {
    log_section "Database Links"
    report_section "DATABASE LINKS"

    run_sql "SELECT owner, db_link, username, host, TO_CHAR(created,'YYYY-MM-DD') AS created
             FROM dba_db_links ORDER BY owner, db_link;" >> "$REPORT_FILE" 2>/dev/null

    local dblink_count
    dblink_count=$(run_sql_value "SELECT COUNT(*) FROM dba_db_links;")
    JSON_DATA["db_link_count"]="${dblink_count:-0}"
    log_info "Database links found: ${dblink_count:-0}"
}

# --------------------------------------------------------------------------
# Section: Materialized Views
# --------------------------------------------------------------------------
discover_mviews() {
    log_section "Materialized Views"
    report_section "MATERIALIZED VIEWS"

    log_raw "  Materialized Views:"
    run_sql "SELECT owner, mview_name, refresh_method, refresh_mode, staleness,
                    TO_CHAR(last_refresh_date,'YYYY-MM-DD HH24:MI:SS') AS last_refresh,
                    TO_CHAR(next,'YYYY-MM-DD HH24:MI:SS') AS next_refresh
             FROM dba_mviews ORDER BY owner, mview_name;" >> "$REPORT_FILE" 2>/dev/null

    log_raw ""
    log_raw "  Materialized View Logs:"
    run_sql "SELECT log_owner, master, log_table, primary_key, rowid, sequence
             FROM dba_mview_logs ORDER BY log_owner, master;" >> "$REPORT_FILE" 2>/dev/null

    local mview_count
    mview_count=$(run_sql_value "SELECT COUNT(*) FROM dba_mviews;")
    JSON_DATA["mview_count"]="${mview_count:-0}"
}

# --------------------------------------------------------------------------
# Section: Scheduler Jobs
# --------------------------------------------------------------------------
discover_scheduler_jobs() {
    log_section "Scheduler Jobs"
    report_section "SCHEDULER JOBS"

    run_sql "SELECT owner, job_name, job_type, schedule_type, enabled, state,
                    TO_CHAR(last_start_date,'YYYY-MM-DD HH24:MI:SS') AS last_run,
                    TO_CHAR(next_run_date,'YYYY-MM-DD HH24:MI:SS') AS next_run
             FROM dba_scheduler_jobs
             ORDER BY owner, job_name;" >> "$REPORT_FILE" 2>/dev/null

    log_raw ""
    log_raw "  Jobs referencing external resources (hostnames, file paths, credentials):"
    run_sql "SELECT owner, job_name, job_action
             FROM dba_scheduler_jobs
             WHERE job_action LIKE '%utl_file%'
                OR job_action LIKE '%UTL_TCP%'
                OR job_action LIKE '%UTL_HTTP%'
                OR job_action LIKE '%UTL_SMTP%'
                OR job_action LIKE '%DBMS_DATAPUMP%'
                OR job_action LIKE '%/home/%'
                OR job_action LIKE '%/u01/%'
                OR job_action LIKE '%/tmp/%'
             ORDER BY owner, job_name;" >> "$REPORT_FILE" 2>/dev/null

    local job_count
    job_count=$(run_sql_value "SELECT COUNT(*) FROM dba_scheduler_jobs;")
    JSON_DATA["scheduler_job_count"]="${job_count:-0}"
}

# --------------------------------------------------------------------------
# Write JSON summary
# --------------------------------------------------------------------------
write_json_summary() {
    log_section "Writing JSON Summary"

    cat > "$JSON_FILE" <<ENDJSON
{
  "discovery_type": "source",
  "project": "ORADB",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hostname": "${JSON_DATA[hostname]:-}",
  "ip_addresses": "${JSON_DATA[ip_addresses]:-}",
  "os_version": "${JSON_DATA[os_version]:-}",
  "os_kernel": "${JSON_DATA[os_kernel]:-}",
  "oracle_home": "${JSON_DATA[oracle_home]:-}",
  "oracle_sid": "${JSON_DATA[oracle_sid]:-}",
  "oracle_version": "${JSON_DATA[oracle_version]:-}",
  "db_name": "${JSON_DATA[db_name]:-}",
  "db_unique_name": "${JSON_DATA[db_unique_name]:-}",
  "dbid": "${JSON_DATA[dbid]:-}",
  "db_role": "${JSON_DATA[db_role]:-}",
  "log_mode": "${JSON_DATA[log_mode]:-}",
  "force_logging": "${JSON_DATA[force_logging]:-}",
  "db_size": "${JSON_DATA[db_size_gb]:-}",
  "charset": "${JSON_DATA[charset]:-}",
  "is_cdb": "${JSON_DATA[is_cdb]:-}",
  "tde_enabled": "${JSON_DATA[tde_enabled]:-}",
  "tde_wallet_status": "${JSON_DATA[tde_wallet_status]:-}",
  "tde_wallet_type": "${JSON_DATA[tde_wallet_type]:-}",
  "suplog_min": "${JSON_DATA[suplog_min]:-}",
  "tns_admin": "${JSON_DATA[tns_admin]:-}",
  "password_file": "${JSON_DATA[password_file]:-}",
  "db_link_count": "${JSON_DATA[db_link_count]:-0}",
  "mview_count": "${JSON_DATA[mview_count]:-0}",
  "scheduler_job_count": "${JSON_DATA[scheduler_job_count]:-0}",
  "report_file": "$(basename "$REPORT_FILE")"
}
ENDJSON

    log_info "JSON summary written to: $JSON_FILE"
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
main() {
    echo -e "${BOLD}${CYAN}"
    echo "============================================================"
    echo "  ZDM Source Database Discovery"
    echo "  Project: ORADB"
    echo "  Server:  $(hostname)"
    echo "  Date:    $(date)"
    echo "============================================================"
    echo -e "${NC}"

    # Initialize report
    cat > "$REPORT_FILE" <<EOHEADER
==================================================================
ZDM SOURCE DATABASE DISCOVERY REPORT
Project:   ORADB
Server:    $(hostname -f 2>/dev/null || hostname)
Date:      $(date)
Script:    $0
==================================================================
EOHEADER

    # Run all discovery sections (continue on failure)
    discover_os_info        || log_error "OS info discovery failed"
    discover_oracle_env     || log_error "Oracle env discovery failed"
    discover_db_config      || log_error "DB config discovery failed"
    discover_cdb_pdb        || log_error "CDB/PDB discovery failed"
    discover_tde            || log_error "TDE discovery failed"
    discover_supplemental_logging || log_error "Supplemental logging discovery failed"
    discover_redo_archive   || log_error "Redo/archive discovery failed"
    discover_network        || log_error "Network discovery failed"
    discover_auth           || log_error "Auth discovery failed"
    discover_dataguard      || log_error "Data Guard discovery failed"
    discover_schemas        || log_error "Schema discovery failed"
    discover_tablespaces    || log_error "Tablespace discovery failed"
    discover_backup         || log_error "Backup discovery failed"
    discover_db_links       || log_error "DB links discovery failed"
    discover_mviews         || log_error "Materialized views discovery failed"
    discover_scheduler_jobs || log_error "Scheduler jobs discovery failed"

    write_json_summary

    log_raw ""
    log_raw "=================================================================="
    log_raw "END OF SOURCE DISCOVERY REPORT"
    log_raw "Generated: $(date)"
    log_raw "=================================================================="

    echo ""
    log_info "Discovery complete."
    log_info "Text report: $REPORT_FILE"
    log_info "JSON summary: $JSON_FILE"
}

main "$@"
