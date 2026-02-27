#!/bin/bash
# =============================================================================
# zdm_source_discovery.sh
# ZDM Source Database Discovery Script
# Project: ORADB  |  Source Host: 10.1.0.11
# Generated: 2026-02-27
#
# USAGE:
#   Via orchestration: Executed automatically by zdm_orchestrate_discovery.sh
#   Manual SSH:        ssh -i ~/.ssh/odaa.pem azureuser@10.1.0.11 'bash -l -s' < zdm_source_discovery.sh
#   Local run:         ./zdm_source_discovery.sh
#
# ENVIRONMENT OVERRIDES (optional, set before running if auto-detection fails):
#   SOURCE_REMOTE_ORACLE_HOME  - Override ORACLE_HOME on source server
#   SOURCE_REMOTE_ORACLE_SID   - Override ORACLE_SID on source server
#   ORACLE_USER                - Oracle software owner user (default: oracle)
# =============================================================================

# --- Color Output ---
RED='\033[0;31m'; YELLOW='\033[0;33m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

log_info()    { echo -e "${GREEN}[INFO]${NC}  $*" >&2; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*" >&2; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_section() { echo -e "\n${BOLD}${CYAN}================================================================${NC}" >&2
                echo -e "${BOLD}${CYAN}  $*${NC}" >&2
                echo -e "${BOLD}${CYAN}================================================================${NC}" >&2; }

# --- Output Files ---
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME_SHORT=$(hostname -s)
OUTPUT_TXT="./zdm_source_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
OUTPUT_JSON="./zdm_source_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

# --- Oracle User default ---
ORACLE_USER="${ORACLE_USER:-oracle}"

# =============================================================================
# ENVIRONMENT DETECTION
# =============================================================================

detect_oracle_env() {
    log_info "Detecting Oracle environment..."

    # Apply explicit overrides first (highest priority)
    [ -n "${SOURCE_REMOTE_ORACLE_HOME:-}" ] && export ORACLE_HOME="$SOURCE_REMOTE_ORACLE_HOME"
    [ -n "${SOURCE_REMOTE_ORACLE_SID:-}"  ] && export ORACLE_SID="$SOURCE_REMOTE_ORACLE_SID"

    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        log_info "Using: ORACLE_HOME=$ORACLE_HOME  ORACLE_SID=$ORACLE_SID"
        export ORACLE_BASE="${ORACLE_BASE:-$(echo "$ORACLE_HOME" | sed 's|/product/.*||')}"
        return 0
    fi

    # Method 1: /etc/oratab
    if [ -f /etc/oratab ]; then
        local entry
        if [ -n "${ORACLE_SID:-}" ]; then
            entry=$(grep "^${ORACLE_SID}:" /etc/oratab 2>/dev/null | grep -v '^#' | head -1)
        else
            entry=$(grep -v '^#' /etc/oratab | grep -v '^$' | grep ':' | head -1)
        fi
        if [ -n "$entry" ]; then
            export ORACLE_SID="${ORACLE_SID:-$(echo "$entry" | cut -d: -f1)}"
            export ORACLE_HOME="${ORACLE_HOME:-$(echo "$entry" | cut -d: -f2)}"
            log_info "Detected from /etc/oratab: ORACLE_SID=$ORACLE_SID  ORACLE_HOME=$ORACLE_HOME"
        fi
    fi

    # Method 2: Running pmon process
    if [ -z "${ORACLE_SID:-}" ]; then
        local pmon_sid
        pmon_sid=$(ps -ef 2>/dev/null | grep 'ora_pmon_' | grep -v grep | head -1 | sed 's/.*ora_pmon_//')
        if [ -n "$pmon_sid" ]; then
            export ORACLE_SID="$pmon_sid"
            log_info "Detected ORACLE_SID from pmon: $ORACLE_SID"
        fi
    fi

    # Method 3: Common installation paths
    if [ -z "${ORACLE_HOME:-}" ]; then
        for path in /u01/app/oracle/product/*/dbhome_1 \
                    /u01/app/oracle/product/*/db_1 \
                    /opt/oracle/product/*/dbhome_1 \
                    /oracle/product/*/dbhome_1; do
            if [ -d "$path" ] && [ -f "$path/bin/sqlplus" ]; then
                export ORACLE_HOME="$path"
                log_info "Detected ORACLE_HOME from common path: $ORACLE_HOME"
                break
            fi
        done
    fi

    # Method 4: oraenv
    if [ -z "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ] && [ -f /usr/local/bin/oraenv ]; then
        ORAENV_ASK=NO . /usr/local/bin/oraenv 2>/dev/null
    fi

    # Derive ORACLE_BASE from ORACLE_HOME
    if [ -n "${ORACLE_HOME:-}" ]; then
        export ORACLE_BASE="${ORACLE_BASE:-$(echo "$ORACLE_HOME" | sed 's|/product/.*||')}"
    fi

    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        log_info "Final Oracle env: ORACLE_HOME=$ORACLE_HOME  ORACLE_SID=$ORACLE_SID  ORACLE_BASE=${ORACLE_BASE:-unknown}"
    else
        log_error "Could not detect Oracle environment. Set SOURCE_REMOTE_ORACLE_HOME and SOURCE_REMOTE_ORACLE_SID."
    fi
}

# =============================================================================
# SQL EXECUTION
# =============================================================================

run_sql() {
    local sql_query="$1"
    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        echo "  ERROR: ORACLE_HOME or ORACLE_SID not set - cannot execute SQL"
        return 1
    fi
    local sqlplus_cmd="$ORACLE_HOME/bin/sqlplus -s / as sysdba"
    local sql_script
    sql_script=$(cat <<EOSQL
WHENEVER SQLERROR CONTINUE
SET PAGESIZE 5000
SET LINESIZE 250
SET FEEDBACK OFF
SET HEADING ON
SET ECHO OFF
SET TRIMSPOOL ON
SET WRAP OFF
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

run_sql_noheading() {
    local sql_query="$1"
    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        echo "UNKNOWN"
        return 1
    fi
    local sqlplus_cmd="$ORACLE_HOME/bin/sqlplus -s / as sysdba"
    local sql_script
    sql_script=$(cat <<EOSQL
WHENEVER SQLERROR CONTINUE
SET PAGESIZE 0
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING OFF
SET ECHO OFF
SET TRIMSPOOL ON
$sql_query
EXIT
EOSQL
)
    local result
    if [ "$(whoami)" = "$ORACLE_USER" ]; then
        result=$(echo "$sql_script" | $sqlplus_cmd 2>&1)
    else
        result=$(echo "$sql_script" | sudo -u "$ORACLE_USER" -E \
            ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" \
            $sqlplus_cmd 2>&1)
    fi
    echo "$result" | grep -v '^$' | head -1 | xargs
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message and exit"
    echo ""
    echo "Environment Variable Overrides:"
    echo "  SOURCE_REMOTE_ORACLE_HOME  Override auto-detected ORACLE_HOME"
    echo "  SOURCE_REMOTE_ORACLE_SID   Override auto-detected ORACLE_SID"
    echo "  ORACLE_USER                Oracle software owner (default: oracle)"
    echo ""
    echo "Output files written to current directory:"
    echo "  zdm_source_discovery_<hostname>_<timestamp>.txt"
    echo "  zdm_source_discovery_<hostname>_<timestamp>.json"
    exit 0
}

for arg in "$@"; do
    case "$arg" in
        -h|--help) show_help ;;
    esac
done

# =============================================================================
# MAIN DISCOVERY FUNCTION
# =============================================================================

run_discovery() {

    echo "================================================================"
    echo "  ZDM Source Database Discovery Report"
    echo "  Project: ORADB"
    echo "  Generated: $(date)"
    echo "  Host: $(hostname -f)"
    echo "================================================================"
    echo ""

    detect_oracle_env

    # -----------------------------------------------------------------------
    # Section 1: OS Information
    # -----------------------------------------------------------------------
    echo ""
    echo "================================================================"
    echo "  Section 1: OS Information"
    echo "================================================================"
    echo "Hostname (FQDN):    $(hostname -f 2>/dev/null || hostname)"
    echo "Hostname (short):   $(hostname -s)"
    echo "Current User:       $(whoami)"
    echo "Oracle User:        $ORACLE_USER"
    echo ""
    echo "--- IP Addresses ---"
    ip addr show 2>/dev/null | grep -E 'inet |inet6 ' | awk '{print "  "$2, $NF}' \
        || ifconfig 2>/dev/null | grep -E 'inet addr:|inet ' \
        || echo "  ip/ifconfig not available"
    echo ""
    echo "--- OS Version ---"
    cat /etc/os-release 2>/dev/null \
        || cat /etc/redhat-release 2>/dev/null \
        || cat /etc/system-release 2>/dev/null \
        || uname -a
    echo "Kernel:   $(uname -r)"
    echo "Arch:     $(uname -m)"
    echo ""
    echo "--- Disk Space ---"
    df -hP 2>/dev/null || df -h

    # -----------------------------------------------------------------------
    # Section 2: Oracle Environment
    # -----------------------------------------------------------------------
    echo ""
    echo "================================================================"
    echo "  Section 2: Oracle Environment"
    echo "================================================================"
    echo "ORACLE_HOME:   ${ORACLE_HOME:-NOT DETECTED}"
    echo "ORACLE_SID:    ${ORACLE_SID:-NOT DETECTED}"
    echo "ORACLE_BASE:   ${ORACLE_BASE:-NOT DETECTED}"
    echo ""
    if [ -n "${ORACLE_HOME:-}" ]; then
        echo "--- Oracle Version ---"
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            "$ORACLE_HOME/bin/sqlplus" -v 2>/dev/null || echo "  sqlplus -v failed"
        else
            sudo -u "$ORACLE_USER" -E ORACLE_HOME="$ORACLE_HOME" \
                "$ORACLE_HOME/bin/sqlplus" -v 2>/dev/null || echo "  sqlplus -v failed"
        fi
        echo ""
        echo "--- /etc/oratab Contents ---"
        cat /etc/oratab 2>/dev/null || echo "  /etc/oratab not found"
    fi

    # -----------------------------------------------------------------------
    # Section 3: Database Configuration
    # -----------------------------------------------------------------------
    echo ""
    echo "================================================================"
    echo "  Section 3: Database Configuration"
    echo "================================================================"

    echo "--- Core Database Info ---"
    run_sql "
SELECT 'DB Name:         ' || name          FROM v\$database;
SELECT 'DB Unique Name:  ' || db_unique_name FROM v\$database;
SELECT 'DBID:            ' || dbid          FROM v\$database;
SELECT 'DB Role:         ' || database_role FROM v\$database;
SELECT 'Open Mode:       ' || open_mode     FROM v\$database;
SELECT 'Log Mode:        ' || log_mode      FROM v\$database;
SELECT 'Force Logging:   ' || force_logging  FROM v\$database;
SELECT 'Platform:        ' || platform_name  FROM v\$database;
SELECT 'Created:         ' || TO_CHAR(created,'YYYY-MM-DD HH24:MI:SS') FROM v\$database;
"

    echo ""
    echo "--- Database Size ---"
    run_sql "
SELECT 'Data Files (GB):    ' || ROUND(SUM(bytes)/1024/1024/1024,2) FROM dba_data_files;
SELECT 'Temp Files (GB):    ' || ROUND(SUM(bytes)/1024/1024/1024,2) FROM dba_temp_files;
SELECT 'Redo Logs (MB):     ' || ROUND(SUM(bytes)/1024/1024,0)
  FROM v\$log;
"

    echo ""
    echo "--- Character Set ---"
    run_sql "
SELECT parameter, value
FROM nls_database_parameters
WHERE parameter IN ('NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET','NLS_TERRITORY','NLS_LANGUAGE')
ORDER BY parameter;
"

    # -----------------------------------------------------------------------
    # Section 4: Container Database (CDB/PDB)
    # -----------------------------------------------------------------------
    echo ""
    echo "================================================================"
    echo "  Section 4: Container Database Status"
    echo "================================================================"
    run_sql "
SELECT 'CDB:         ' || cdb  FROM v\$database;
SELECT 'Con_ID:      ' || con_id FROM v\$database;
"

    echo ""
    echo "--- PDB List (if CDB) ---"
    run_sql "
SELECT pdb_id, pdb_name, status, open_mode, restricted
FROM cdb_pdbs
ORDER BY pdb_id;
" 2>/dev/null || echo "  Not a CDB or cdb_pdbs not accessible"

    # -----------------------------------------------------------------------
    # Section 5: TDE Configuration
    # -----------------------------------------------------------------------
    echo ""
    echo "================================================================"
    echo "  Section 5: TDE Configuration"
    echo "================================================================"
    echo "--- Encryption Wallet ---"
    run_sql "
SELECT status, wrl_type, wrl_parameter AS wallet_location
FROM v\$encryption_wallet;
"

    echo ""
    echo "--- Encrypted Tablespaces ---"
    run_sql "
SELECT tablespace_name, encrypted
FROM dba_tablespaces
WHERE encrypted = 'YES'
ORDER BY tablespace_name;
"

    echo ""
    echo "--- Encrypted Columns ---"
    run_sql "
SELECT owner, table_name, column_name, encryption_alg
FROM dba_encrypted_columns
ORDER BY owner, table_name, column_name
FETCH FIRST 50 ROWS ONLY;
"

    # -----------------------------------------------------------------------
    # Section 6: Supplemental Logging
    # -----------------------------------------------------------------------
    echo ""
    echo "================================================================"
    echo "  Section 6: Supplemental Logging"
    echo "================================================================"
    run_sql "
SELECT 'Supplemental Log (MIN): ' || supplemental_log_data_min FROM v\$database;
SELECT 'Supplemental Log (PK):  ' || supplemental_log_data_pk  FROM v\$database;
SELECT 'Supplemental Log (UI):  ' || supplemental_log_data_ui  FROM v\$database;
SELECT 'Supplemental Log (FK):  ' || supplemental_log_data_fk  FROM v\$database;
SELECT 'Supplemental Log (ALL): ' || supplemental_log_data_all FROM v\$database;
"

    # -----------------------------------------------------------------------
    # Section 7: Redo / Archive Configuration
    # -----------------------------------------------------------------------
    echo ""
    echo "================================================================"
    echo "  Section 7: Redo / Archive Configuration"
    echo "================================================================"
    echo "--- Redo Log Groups ---"
    run_sql "
SELECT l.group#, l.bytes/1024/1024 size_mb, l.members, l.status, lf.member
FROM v\$log l
JOIN v\$logfile lf ON l.group# = lf.group#
ORDER BY l.group#, lf.member;
"

    echo ""
    echo "--- Archive Log Destinations ---"
    run_sql "
SELECT dest_id, dest_name, status, target, archiver, schedule, destination
FROM v\$archive_dest
WHERE status != 'INACTIVE'
ORDER BY dest_id;
"

    echo ""
    echo "--- Archive Log Generation (last 24h) ---"
    run_sql "
SELECT COUNT(*) arch_count,
       ROUND(SUM(blocks*block_size)/1024/1024/1024,2) size_gb,
       MIN(first_time) oldest,
       MAX(next_time) newest
FROM v\$archived_log
WHERE first_time > SYSDATE-1
  AND standby_dest = 'NO';
"

    # -----------------------------------------------------------------------
    # Section 8: Network Configuration
    # -----------------------------------------------------------------------
    echo ""
    echo "================================================================"
    echo "  Section 8: Network Configuration"
    echo "================================================================"
    echo "--- Listener Status ---"
    if [ -n "${ORACLE_HOME:-}" ]; then
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            "$ORACLE_HOME/bin/lsnrctl" status 2>/dev/null || echo "  lsnrctl error"
        else
            sudo -u "$ORACLE_USER" -E ORACLE_HOME="$ORACLE_HOME" \
                "$ORACLE_HOME/bin/lsnrctl" status 2>/dev/null || echo "  lsnrctl error"
        fi
    else
        echo "  ORACLE_HOME not set - cannot run lsnrctl"
    fi

    echo ""
    echo "--- tnsnames.ora ---"
    local tns_found=false
    for tns_dir in "${ORACLE_HOME:-}/network/admin" "${TNS_ADMIN:-}" /etc "$HOME"; do
        [ -z "$tns_dir" ] && continue
        if [ -f "$tns_dir/tnsnames.ora" ]; then
            echo "  Location: $tns_dir/tnsnames.ora"
            cat "$tns_dir/tnsnames.ora"
            tns_found=true
            break
        fi
    done
    $tns_found || echo "  tnsnames.ora not found in standard locations"

    echo ""
    echo "--- sqlnet.ora ---"
    local sqlnet_found=false
    for tns_dir in "${ORACLE_HOME:-}/network/admin" "${TNS_ADMIN:-}" /etc; do
        [ -z "$tns_dir" ] && continue
        if [ -f "$tns_dir/sqlnet.ora" ]; then
            echo "  Location: $tns_dir/sqlnet.ora"
            cat "$tns_dir/sqlnet.ora"
            sqlnet_found=true
            break
        fi
    done
    $sqlnet_found || echo "  sqlnet.ora not found in standard locations"

    # -----------------------------------------------------------------------
    # Section 9: Authentication
    # -----------------------------------------------------------------------
    echo ""
    echo "================================================================"
    echo "  Section 9: Authentication"
    echo "================================================================"
    echo "--- Password File Location ---"
    if [ -n "${ORACLE_HOME:-}" ]; then
        find "${ORACLE_HOME}/dbs" -name "orapw${ORACLE_SID:-*}" -o -name "orapw*" 2>/dev/null | head -5
        [ -z "$(find "${ORACLE_HOME}/dbs" -name "orapw*" 2>/dev/null)" ] && \
            echo "  No password file found in $ORACLE_HOME/dbs"
    fi
    # Check ASM location
    find /u01/app/grid/dbs /u01/app/oracle/dbs -name "orapw*" 2>/dev/null | head -3

    echo ""
    echo "--- Oracle User SSH Directory ---"
    local oracle_home_dir
    oracle_home_dir=$(eval echo ~${ORACLE_USER} 2>/dev/null)
    if [ -n "$oracle_home_dir" ] && [ -d "$oracle_home_dir/.ssh" ]; then
        ls -la "$oracle_home_dir/.ssh/" 2>/dev/null || \
            sudo ls -la "$oracle_home_dir/.ssh/" 2>/dev/null || \
            echo "  Cannot read $oracle_home_dir/.ssh/"
    else
        echo "  $oracle_home_dir/.ssh not found or not accessible"
    fi

    # -----------------------------------------------------------------------
    # Section 10: Data Guard Parameters
    # -----------------------------------------------------------------------
    echo ""
    echo "================================================================"
    echo "  Section 10: Data Guard Configuration"
    echo "================================================================"
    run_sql "
SELECT name, value
FROM v\$parameter
WHERE name IN (
    'db_unique_name','log_archive_config','log_archive_dest_1',
    'log_archive_dest_2','fal_server','fal_client',
    'standby_file_management','db_file_name_convert',
    'log_file_name_convert','dg_broker_start','dg_broker_config_file1'
)
ORDER BY name;
"

    # -----------------------------------------------------------------------
    # Section 11: Schema Information
    # -----------------------------------------------------------------------
    echo ""
    echo "================================================================"
    echo "  Section 11: Schema Information"
    echo "================================================================"
    echo "--- Schema Sizes (non-system schemas > 100MB) ---"
    run_sql "
SELECT s.owner,
       ROUND(SUM(s.bytes)/1024/1024/1024,3) size_gb,
       COUNT(DISTINCT s.segment_type) segment_types,
       COUNT(*) segment_count
FROM dba_segments s
WHERE s.owner NOT IN (
    'SYS','SYSTEM','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS','DVSYS',
    'GSMADMIN_INTERNAL','LBACSYS','MDSYS','OJVMSYS','OLAPSYS',
    'ORDDATA','ORDSYS','OUTLN','WMSYS','XDB','ORACLE_OCM',
    'REMOTE_SCHEDULER_AGENT','GSMCATUSER','GSMUSER','SYSBACKUP',
    'SYSDG','SYSKM','SYSRAC')
GROUP BY s.owner
HAVING SUM(s.bytes) > 100*1024*1024
ORDER BY size_gb DESC;
"

    echo ""
    echo "--- Invalid Objects by Owner/Type ---"
    run_sql "
SELECT owner, object_type, COUNT(*) invalid_count
FROM dba_objects
WHERE status = 'INVALID'
GROUP BY owner, object_type
ORDER BY owner, object_type;
"

    # =======================================================================
    # SECTION 12-16: ADDITIONAL DISCOVERY REQUIREMENTS
    # =======================================================================

    # -----------------------------------------------------------------------
    # Section 12: Tablespace Autoextend Settings
    # -----------------------------------------------------------------------
    echo ""
    echo "================================================================"
    echo "  Section 12: Tablespace Autoextend Settings (Additional)"
    echo "================================================================"

    echo "--- All Tablespaces Summary ---"
    run_sql "
SELECT t.tablespace_name,
       t.status,
       t.contents,
       t.extent_management,
       t.allocation_type,
       ROUND(NVL(
           (SELECT SUM(bytes)/1024/1024 FROM dba_data_files d WHERE d.tablespace_name = t.tablespace_name),0
       ),0) AS allocated_mb
FROM dba_tablespaces t
ORDER BY t.tablespace_name;
"

    echo ""
    echo "--- Data Files: Autoextend ENABLED ---"
    run_sql "
SELECT tablespace_name,
       REGEXP_SUBSTR(file_name, '[^/]+\$') filename,
       ROUND(bytes/1024/1024,0)         current_mb,
       ROUND(maxbytes/1024/1024,0)      max_mb,
       ROUND(increment_by*8192/1024/1024,2) increment_mb,
       autoextensible
FROM dba_data_files
WHERE autoextensible = 'YES'
ORDER BY tablespace_name, filename;
"

    echo ""
    echo "--- Data Files: Autoextend DISABLED ---"
    run_sql "
SELECT tablespace_name,
       REGEXP_SUBSTR(file_name, '[^/]+\$') filename,
       ROUND(bytes/1024/1024,0) current_mb,
       autoextensible
FROM dba_data_files
WHERE autoextensible = 'NO'
ORDER BY tablespace_name, filename;
"

    echo ""
    echo "--- Temp Files: Autoextend Status ---"
    run_sql "
SELECT tablespace_name,
       REGEXP_SUBSTR(file_name, '[^/]+\$') filename,
       ROUND(bytes/1024/1024,0)         current_mb,
       ROUND(maxbytes/1024/1024,0)      max_mb,
       autoextensible
FROM dba_temp_files
ORDER BY tablespace_name, filename;
"

    # -----------------------------------------------------------------------
    # Section 13: Backup Schedule and Retention
    # -----------------------------------------------------------------------
    echo ""
    echo "================================================================"
    echo "  Section 13: Backup Schedule and Retention (Additional)"
    echo "================================================================"

    echo "--- RMAN Configuration (SHOW ALL) ---"
    local rman_show_sql="SHOW ALL;"
    if [ "$(whoami)" = "$ORACLE_USER" ]; then
        echo "$rman_show_sql" | "$ORACLE_HOME/bin/rman" target / 2>&1 \
            || echo "  RMAN SHOW ALL failed"
    else
        echo "$rman_show_sql" | sudo -u "$ORACLE_USER" -E \
            ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" \
            "$ORACLE_HOME/bin/rman" target / 2>&1 \
            || echo "  RMAN SHOW ALL failed"
    fi

    echo ""
    echo "--- RMAN Configuration from v\$rman_configuration ---"
    run_sql "
SELECT conf#, name, value
FROM v\$rman_configuration
ORDER BY conf#;
"

    echo ""
    echo "--- Backup Job History (Last 14 Days) ---"
    run_sql "
SELECT input_type,
       status,
       TO_CHAR(start_time,'YYYY-MM-DD HH24:MI') start_time,
       TO_CHAR(end_time,'YYYY-MM-DD HH24:MI')   end_time,
       ROUND(input_bytes/1024/1024/1024,2)       input_gb,
       ROUND(output_bytes/1024/1024/1024,2)      output_gb,
       time_taken_display
FROM v\$rman_backup_job_details
WHERE start_time > SYSDATE - 14
ORDER BY start_time DESC;
"

    echo ""
    echo "--- Recent Backup Sets (Last 7 Days) ---"
    run_sql "
SELECT bs.recid,
       bs.backup_type,
       bs.incremental_level,
       bs.status,
       TO_CHAR(bs.completion_time,'YYYY-MM-DD HH24:MI') completion_time,
       ROUND(bs.bytes/1024/1024/1024,2) size_gb
FROM v\$backup_set bs
WHERE bs.completion_time > SYSDATE - 7
ORDER BY bs.completion_time DESC;
"

    echo ""
    echo "--- Fast Recovery Area (FRA) Configuration ---"
    run_sql "
SELECT name, value
FROM v\$parameter
WHERE name IN ('db_recovery_file_dest','db_recovery_file_dest_size','db_flashback_retention_target')
ORDER BY name;
"
    run_sql "
SELECT name, space_limit/1024/1024/1024 limit_gb,
       space_used/1024/1024/1024 used_gb,
       space_reclaimable/1024/1024/1024 reclaimable_gb,
       number_of_files
FROM v\$recovery_file_dest;
"

    # -----------------------------------------------------------------------
    # Section 14: Database Links
    # -----------------------------------------------------------------------
    echo ""
    echo "================================================================"
    echo "  Section 14: Database Links (Additional)"
    echo "================================================================"

    echo "--- All Database Links ---"
    run_sql "
SELECT owner,
       db_link,
       username,
       host,
       TO_CHAR(created,'YYYY-MM-DD') created
FROM dba_db_links
ORDER BY owner, db_link;
"

    echo ""
    echo "--- Database Links Count by Owner ---"
    run_sql "
SELECT owner, COUNT(*) db_link_count
FROM dba_db_links
GROUP BY owner
ORDER BY owner;
"

    echo ""
    echo "--- Public Database Links ---"
    run_sql "
SELECT owner, db_link, username, host
FROM dba_db_links
WHERE owner = 'PUBLIC'
ORDER BY db_link;
" || echo "  No public database links found"

    # -----------------------------------------------------------------------
    # Section 15: Materialized View Refresh Schedules
    # -----------------------------------------------------------------------
    echo ""
    echo "================================================================"
    echo "  Section 15: Materialized View Refresh Schedules (Additional)"
    echo "================================================================"

    echo "--- All Materialized Views ---"
    run_sql "
SELECT owner,
       mview_name,
       refresh_method,
       refresh_mode,
       TO_CHAR(last_refresh_date,'YYYY-MM-DD HH24:MI') last_refresh,
       TO_CHAR(next_date,'YYYY-MM-DD HH24:MI')         next_refresh,
       staleness,
       compile_state
FROM dba_mviews
ORDER BY owner, mview_name;
"

    echo ""
    echo "--- Materialized View Refresh Groups ---"
    run_sql "
SELECT rname, owner, job,
       TO_CHAR(next_date,'YYYY-MM-DD HH24:MI') next_refresh,
       interval
FROM dba_refresh
ORDER BY owner, rname;
" 2>/dev/null || echo "  No refresh groups or dba_refresh not accessible"

    echo ""
    echo "--- Materialized View Logs (MV Logs for fast refresh) ---"
    run_sql "
SELECT log_owner, master, log_table, rowids, primary_key, object_id, filter_columns,
       TO_CHAR(current_snapshots,'YYYY-MM-DD HH24:MI') current_snapshots
FROM dba_mview_logs
ORDER BY log_owner, master;
"

    echo ""
    echo "--- Complete Refresh Timings (Last 7 days) ---"
    run_sql "
SELECT mv_owner,
       mview_name,
       refresh_method,
       TO_CHAR(start_time,'YYYY-MM-DD HH24:MI') start_time,
       elapsed_time,
       num_rows_ins, num_rows_upd, num_rows_del
FROM dba_mvref_stats
WHERE start_time > SYSDATE - 7
ORDER BY start_time DESC;
" 2>/dev/null || echo "  dba_mvref_stats not accessible (available from 12.2+)"

    # -----------------------------------------------------------------------
    # Section 16: Scheduler Jobs
    # -----------------------------------------------------------------------
    echo ""
    echo "================================================================"
    echo "  Section 16: Scheduler Jobs (Additional)"
    echo "================================================================"

    local sys_schemas="'SYS','SYSTEM','ORACLE_OCM','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
        'DVSYS','GSMADMIN_INTERNAL','LBACSYS','MDSYS','OJVMSYS','OLAPSYS',
        'ORDDATA','ORDSYS','OUTLN','WMSYS','XDB'"

    echo "--- All Scheduler Jobs (Non-System) ---"
    run_sql "
SELECT owner, job_name, job_type,
       enabled, state,
       TO_CHAR(start_date,'YYYY-MM-DD HH24:MI')    start_date,
       repeat_interval,
       TO_CHAR(last_start_date,'YYYY-MM-DD HH24:MI') last_start,
       TO_CHAR(next_run_date,'YYYY-MM-DD HH24:MI')   next_run,
       run_count, failure_count
FROM dba_scheduler_jobs
WHERE owner NOT IN ($sys_schemas)
ORDER BY owner, job_name;
"

    echo ""
    echo "--- Enabled Scheduler Jobs (Non-System) ---"
    run_sql "
SELECT owner, job_name, job_type, state,
       TO_CHAR(next_run_date,'YYYY-MM-DD HH24:MI') next_run,
       repeat_interval
FROM dba_scheduler_jobs
WHERE owner NOT IN ($sys_schemas)
  AND enabled = 'TRUE'
ORDER BY owner, job_name;
"

    echo ""
    echo "--- Scheduler Job Run History (Last 7 days, Non-System) ---"
    run_sql "
SELECT owner, job_name, status, error#,
       TO_CHAR(actual_start_date,'YYYY-MM-DD HH24:MI') actual_start,
       run_duration
FROM dba_scheduler_job_run_details
WHERE owner NOT IN ($sys_schemas)
  AND actual_start_date > SYSDATE - 7
ORDER BY actual_start_date DESC
FETCH FIRST 100 ROWS ONLY;
" 2>/dev/null || echo "  dba_scheduler_job_run_details not accessible"

    echo ""
    echo "--- Scheduler Programs (Non-System) ---"
    run_sql "
SELECT owner, program_name, program_type, enabled, number_of_arguments
FROM dba_scheduler_programs
WHERE owner NOT IN ($sys_schemas)
ORDER BY owner, program_name;
"

    echo ""
    echo "--- Scheduler Chains (Non-System) ---"
    run_sql "
SELECT owner, chain_name, rule_set_name, number_of_rules, enabled
FROM dba_scheduler_chains
WHERE owner NOT IN ($sys_schemas)
ORDER BY owner, chain_name;
" 2>/dev/null || echo "  No scheduler chains found"

    # =======================================================================
    # JSON SUMMARY
    # =======================================================================
    echo ""
    echo "================================================================"
    echo "  Discovery Summary"
    echo "================================================================"
    echo "Project:        ORADB"
    echo "Script:         zdm_source_discovery.sh"
    echo "Completed:      $(date)"
    echo "Host:           $(hostname -s)"
    echo "ORACLE_HOME:    ${ORACLE_HOME:-UNKNOWN}"
    echo "ORACLE_SID:     ${ORACLE_SID:-UNKNOWN}"
    echo "Output TXT:     $OUTPUT_TXT"
    echo "Output JSON:    $OUTPUT_JSON"

    # Build JSON summary
    local db_name
    local db_unique_name
    local db_log_mode
    local db_cdb
    local db_role
    local db_version
    db_name=$(run_sql_noheading "SELECT name FROM v\$database;")
    db_unique_name=$(run_sql_noheading "SELECT db_unique_name FROM v\$database;")
    db_log_mode=$(run_sql_noheading "SELECT log_mode FROM v\$database;")
    db_cdb=$(run_sql_noheading "SELECT cdb FROM v\$database;")
    db_role=$(run_sql_noheading "SELECT database_role FROM v\$database;")
    db_version=$(run_sql_noheading "SELECT version FROM v\$instance;")

    cat > "$OUTPUT_JSON" <<EOJSON
{
  "discovery_type": "source",
  "project": "ORADB",
  "hostname": "$(hostname -s)",
  "timestamp": "$TIMESTAMP",
  "oracle_env": {
    "oracle_home": "${ORACLE_HOME:-UNKNOWN}",
    "oracle_sid": "${ORACLE_SID:-UNKNOWN}",
    "oracle_base": "${ORACLE_BASE:-UNKNOWN}"
  },
  "database": {
    "db_name": "$db_name",
    "db_unique_name": "$db_unique_name",
    "log_mode": "$db_log_mode",
    "cdb": "$db_cdb",
    "role": "$db_role",
    "version": "$db_version"
  },
  "additional_discovery": {
    "tablespace_autoextend": "see txt report section 12",
    "backup_schedule": "see txt report section 13",
    "database_links": "see txt report section 14",
    "mview_refresh_schedules": "see txt report section 15",
    "scheduler_jobs": "see txt report section 16"
  },
  "output_txt": "$OUTPUT_TXT"
}
EOJSON

    log_info "Source discovery complete."
    log_info "TXT Report:  $(pwd)/$OUTPUT_TXT"
    log_info "JSON Report: $(pwd)/$OUTPUT_JSON"
}

# =============================================================================
# ENTRY POINT
# =============================================================================

run_discovery 2>&1 | tee "$OUTPUT_TXT"
