#!/bin/bash
# =============================================================================
# ZDM Target Database Discovery Script
# =============================================================================
# Project  : ORADB Migration to Oracle Database@Azure
# Target   : proddb-oda.eastus.azure.example.com  (Oracle Database@Azure)
# Generated: 2026-02-26
#
# USAGE:
#   ./zdm_target_discovery.sh
#
# SSH as TARGET_ADMIN_USER (opc); SQL commands run as oracle via sudo if needed.
# ORACLE_HOME_OVERRIDE / ORACLE_SID_OVERRIDE can force specific values.
# =============================================================================

# NO set -e — continue even when individual checks fail
SECTION_ERRORS=0
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME_SHORT=$(hostname -s 2>/dev/null || hostname)
OUTPUT_FILE="./zdm_target_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_target_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

# ---------------------------------------------------------------------------
# User configuration (injected by orchestration script)
# ---------------------------------------------------------------------------
ORACLE_USER="${ORACLE_USER:-oracle}"

# ---------------------------------------------------------------------------
# Environment bootstrap (3-tier priority)
# ---------------------------------------------------------------------------
# Tier 1: explicit overrides from orchestration script
[ -n "${ORACLE_HOME_OVERRIDE:-}"  ] && export ORACLE_HOME="$ORACLE_HOME_OVERRIDE"
[ -n "${ORACLE_SID_OVERRIDE:-}"   ] && export ORACLE_SID="$ORACLE_SID_OVERRIDE"
[ -n "${GRID_HOME_OVERRIDE:-}"    ] && export GRID_HOME="$GRID_HOME_OVERRIDE"

# Tier 2: extract from shell profiles (bypasses interactive guards)
for _profile in /etc/profile /etc/profile.d/*.sh ~/.bash_profile ~/.bashrc; do
    [ -f "$_profile" ] || continue
    eval "$(grep -E '^export[[:space:]]+(ORACLE_HOME|ORACLE_SID|ORACLE_BASE|GRID_HOME|TNS_ADMIN|PATH)=' \
           "$_profile" 2>/dev/null)" 2>/dev/null || true
done

# Tier 3: auto-detect
detect_oracle_env() {
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then return 0; fi

    # Method 1: /etc/oratab
    if [ -f /etc/oratab ]; then
        local entry
        if [ -n "${ORACLE_SID:-}" ]; then
            entry=$(grep "^${ORACLE_SID}:" /etc/oratab 2>/dev/null | head -1)
        else
            entry=$(grep -v '^#' /etc/oratab | grep -v '^$' | grep ':' | head -1)
        fi
        if [ -n "$entry" ]; then
            export ORACLE_SID="${ORACLE_SID:-$(echo "$entry" | cut -d: -f1)}"
            export ORACLE_HOME="${ORACLE_HOME:-$(echo "$entry" | cut -d: -f2)}"
        fi
    fi

    # Method 2: running pmon process
    if [ -z "${ORACLE_SID:-}" ]; then
        local pmon_sid
        pmon_sid=$(ps -ef 2>/dev/null | grep 'ora_pmon_' | grep -v grep | head -1 | sed 's/.*ora_pmon_//')
        [ -n "$pmon_sid" ] && export ORACLE_SID="$pmon_sid"
    fi

    # Method 3: ODA/Exadata common paths
    if [ -z "${ORACLE_HOME:-}" ]; then
        for _path in /u01/app/oracle/product/*/dbhome_1 \
                     /u02/app/oracle/product/*/dbhome_1 \
                     /u01/app/oracle/product/*/dbhome_2 \
                     /opt/oracle/product/*/dbhome_1; do
            if [ -d "$_path" ] && [ -f "$_path/bin/sqlplus" ]; then
                export ORACLE_HOME="$_path"
                break
            fi
        done
    fi

    # Method 4: locate Grid/CRS home
    if [ -z "${GRID_HOME:-}" ]; then
        for _gpath in /u01/app/*/grid /u01/app/grid /grid; do
            if [ -d "$_gpath" ] && [ -f "$_gpath/bin/crsctl" ]; then
                export GRID_HOME="$_gpath"
                break
            fi
        done
    fi
}
detect_oracle_env

[ -n "${ORACLE_HOME:-}" ] && export PATH="${ORACLE_HOME}/bin:${PATH}"
[ -n "${GRID_HOME:-}"   ] && export PATH="${GRID_HOME}/bin:${PATH}"

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
log_info()    { echo -e "${GREEN}[INFO ] $(date '+%H:%M:%S') $*${RESET}" | tee -a "$OUTPUT_FILE"; }
log_warn()    { echo -e "${YELLOW}[WARN ] $(date '+%H:%M:%S') $*${RESET}" | tee -a "$OUTPUT_FILE"; }
log_error()   { echo -e "${RED}[ERROR] $(date '+%H:%M:%S') $*${RESET}" | tee -a "$OUTPUT_FILE"; }
log_section() {
    local bar="================================================================"
    echo "" | tee -a "$OUTPUT_FILE"
    echo -e "${CYAN}${BOLD}${bar}${RESET}" | tee -a "$OUTPUT_FILE"
    echo -e "${CYAN}${BOLD}  $*${RESET}" | tee -a "$OUTPUT_FILE"
    echo -e "${CYAN}${BOLD}${bar}${RESET}" | tee -a "$OUTPUT_FILE"
    echo "" | tee -a "$OUTPUT_FILE"
}
tee_out() { tee -a "$OUTPUT_FILE"; }

# ---------------------------------------------------------------------------
# SQL execution helper
# ---------------------------------------------------------------------------
run_sql() {
    local sql_query="$1"
    if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
        echo "ERROR: ORACLE_HOME or ORACLE_SID not set — cannot run SQL"
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
SET TRIMSPOOL ON
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
SET PAGESIZE 0
$sql_query" 2>/dev/null | grep -v '^$' | head -1 | xargs
}

# ===========================================================================
# DISCOVERY SECTIONS
# ===========================================================================

# ---------------------------------------------------------------------------
# 1. Script Header
# ---------------------------------------------------------------------------
{
echo "================================================================"
echo "  ZDM TARGET DATABASE DISCOVERY REPORT"
echo "================================================================"
echo "  Project    : ORADB Migration to Oracle Database@Azure"
echo "  Target Host: proddb-oda.eastus.azure.example.com"
echo "  Run Host   : $(hostname)"
echo "  Run User   : $(whoami)"
echo "  Oracle User: $ORACLE_USER"
echo "  Timestamp  : $(date)"
echo "  ORACLE_HOME: ${ORACLE_HOME:-NOT DETECTED}"
echo "  ORACLE_SID : ${ORACLE_SID:-NOT DETECTED}"
echo "  GRID_HOME  : ${GRID_HOME:-NOT DETECTED}"
echo "================================================================"
echo ""
} | tee "$OUTPUT_FILE"

# ---------------------------------------------------------------------------
# 2. OS Information
# ---------------------------------------------------------------------------
log_section "OS INFORMATION"
{
echo "--- Hostname & IPs ---"
hostname -f 2>/dev/null || hostname
ip addr show 2>/dev/null | grep 'inet ' | awk '{print $2}' \
    || ifconfig 2>/dev/null | grep 'inet ' | awk '{print $2}'
echo ""
echo "--- OS Version ---"
cat /etc/oracle-release 2>/dev/null \
    || cat /etc/redhat-release 2>/dev/null \
    || cat /etc/os-release 2>/dev/null \
    || uname -a
echo ""
echo "--- Kernel ---"
uname -r
echo ""
echo "--- CPU ---"
grep -m1 'model name' /proc/cpuinfo 2>/dev/null
nproc 2>/dev/null | xargs -I{} echo "CPU Count: {}"
echo ""
echo "--- Memory ---"
free -h 2>/dev/null
echo ""
echo "--- Disk Space ---"
df -h 2>/dev/null
} | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ---------------------------------------------------------------------------
# 3. Oracle Environment
# ---------------------------------------------------------------------------
log_section "ORACLE ENVIRONMENT"
{
echo "ORACLE_HOME : ${ORACLE_HOME:-NOT SET}"
echo "ORACLE_SID  : ${ORACLE_SID:-NOT SET}"
echo "ORACLE_BASE : ${ORACLE_BASE:-NOT SET}"
echo "GRID_HOME   : ${GRID_HOME:-NOT SET}"
echo "TNS_ADMIN   : ${TNS_ADMIN:-NOT SET}"
echo ""
echo "--- Oracle Version ---"
if [ -f "${ORACLE_HOME:-}/bin/sqlplus" ]; then
    "${ORACLE_HOME}/bin/sqlplus" -version 2>/dev/null
fi
echo ""
echo "--- oratab ---"
cat /etc/oratab 2>/dev/null || echo "No /etc/oratab found"
echo ""
echo "--- Running Oracle Processes ---"
ps -ef | grep -E '(pmon|smon|dbwr|lgwr|ckpt)' | grep -v grep
} | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ---------------------------------------------------------------------------
# 4. Database Configuration
# ---------------------------------------------------------------------------
log_section "DATABASE CONFIGURATION"
run_sql "
SELECT 'DB_NAME        : '||name FROM v\$database;
SELECT 'DB_UNIQUE_NAME : '||db_unique_name FROM v\$database;
SELECT 'DBID           : '||dbid FROM v\$database;
SELECT 'DB_ROLE        : '||database_role FROM v\$database;
SELECT 'OPEN_MODE      : '||open_mode FROM v\$database;
SELECT 'LOG_MODE       : '||log_mode FROM v\$database;
SELECT 'FORCE_LOGGING  : '||force_logging FROM v\$database;
SELECT 'PLATFORM_NAME  : '||platform_name FROM v\$database;
SELECT 'CREATED        : '||TO_CHAR(created,'YYYY-MM-DD HH24:MI:SS') FROM v\$database;
PROMPT
PROMPT --- CHARACTER SET ---
SELECT parameter, value FROM nls_database_parameters
WHERE parameter IN ('NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET','NLS_LANGUAGE','NLS_TERRITORY')
ORDER BY parameter;
PROMPT
PROMPT --- DATABASE SIZE ---
SELECT 'Data Files (GB) : '||ROUND(SUM(bytes)/1024/1024/1024,2) FROM dba_data_files;
SELECT 'Temp Files (GB) : '||ROUND(SUM(bytes)/1024/1024/1024,2) FROM dba_temp_files;
" 2>&1 | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ---------------------------------------------------------------------------
# 5. Container Database (CDB/PDB)
# ---------------------------------------------------------------------------
log_section "CONTAINER DATABASE STATUS"
run_sql "
SELECT 'CDB : '||cdb FROM v\$database;
PROMPT
PROMPT --- PDB Details ---
SELECT con_id, name, open_mode, restricted, open_time,
       total_size/1024/1024/1024 AS size_gb
FROM v\$pdbs
ORDER BY con_id;
PROMPT
PROMPT --- PDB Tablespaces ---
SELECT p.name AS pdb_name, t.tablespace_name, t.status, t.contents
FROM cdb_tablespaces t
JOIN v\$pdbs p ON t.con_id = p.con_id
WHERE p.name != 'PDB\$SEED'
ORDER BY p.name, t.tablespace_name;
" 2>&1 | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ---------------------------------------------------------------------------
# 6. Pre-Configured PDBs (additional requirement)
# ---------------------------------------------------------------------------
log_section "PRE-CONFIGURED PDBS (ADDITIONAL)"
run_sql "
PROMPT --- PDB Storage Limits ---
SELECT p.name AS pdb_name,
       p.max_size/1024/1024/1024      AS max_size_gb,
       p.total_size/1024/1024/1024    AS current_size_gb
FROM v\$pdbs p
ORDER BY p.name;
PROMPT
PROMPT --- PDB Services ---
SELECT p.name AS pdb_name, s.name AS service_name,
       s.network_name, s.status
FROM cdb_services s
JOIN v\$pdbs p ON s.con_id = p.con_id
WHERE p.name != 'PDB\$SEED'
ORDER BY p.name, s.name;
PROMPT
PROMPT --- PDB Users (non-system) ---
SELECT p.name AS pdb_name, u.username, u.account_status,
       u.default_tablespace, u.created
FROM cdb_users u
JOIN v\$pdbs p ON u.con_id = p.con_id
WHERE p.name != 'PDB\$SEED'
  AND u.username NOT IN ('SYS','SYSTEM','XDB','ANONYMOUS','OUTLN','DBSNMP',
      'APPQOSSYS','WMSYS','CTXSYS','OJVMSYS','ORDSYS','ORDPLUGINS',
      'SI_INFORMTN_SCHEMA','MDSYS')
ORDER BY p.name, u.username;
" 2>&1 | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ---------------------------------------------------------------------------
# 7. Tablespace and Storage
# ---------------------------------------------------------------------------
log_section "TABLESPACE AND STORAGE"
run_sql "
PROMPT --- Tablespace Usage ---
SELECT t.tablespace_name,
       t.status, t.contents, t.bigfile,
       ROUND(NVL(f.free_space,0)/1024/1024/1024,2)  AS free_gb,
       ROUND(d.total_space/1024/1024/1024,2)         AS total_gb,
       ROUND((1 - NVL(f.free_space,0)/d.total_space)*100,1) AS pct_used
FROM dba_tablespaces t
JOIN (SELECT tablespace_name, SUM(bytes) AS total_space FROM dba_data_files GROUP BY tablespace_name) d
     ON t.tablespace_name = d.tablespace_name
LEFT JOIN (SELECT tablespace_name, SUM(bytes) AS free_space FROM dba_free_space GROUP BY tablespace_name) f
     ON t.tablespace_name = f.tablespace_name
ORDER BY pct_used DESC NULLS LAST;
" 2>&1 | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ---------------------------------------------------------------------------
# 8. Exadata / ASM Storage (additional requirement)
# ---------------------------------------------------------------------------
log_section "EXADATA AND ASM STORAGE CAPACITY (ADDITIONAL)"
{
echo "--- ASM Disk Groups ---"
if [ -n "${GRID_HOME:-}" ] && [ -f "${GRID_HOME}/bin/asmcmd" ]; then
    sudo -u grid -E ORACLE_HOME="$GRID_HOME" ORACLE_SID="+ASM" \
        "${GRID_HOME}/bin/asmcmd" lsdg 2>/dev/null \
    || echo "Could not query ASM disk groups via asmcmd"
else
    echo "GRID_HOME not set or asmcmd not found — checking via SQL"
fi
echo ""
echo "--- ASM Details via V\$ASM_DISKGROUP ---"
} | tee_out

run_sql "
SELECT name AS diskgroup,
       state,
       type,
       ROUND(total_mb/1024,1)                    AS total_gb,
       ROUND(free_mb/1024,1)                     AS free_gb,
       ROUND((total_mb-free_mb)*100/total_mb,1)  AS pct_used,
       voting_files
FROM v\$asm_diskgroup
ORDER BY name;
PROMPT
PROMPT --- ASM Disks ---
SELECT name, path, header_status, mode_status,
       ROUND(total_mb/1024,1) AS total_gb,
       ROUND(free_mb/1024,1)  AS free_gb
FROM v\$asm_disk
ORDER BY name;
" 2>&1 | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

{
echo ""
echo "--- Exadata Cell Configuration ---"
which cellcli 2>/dev/null && cellcli -e list cell detail 2>/dev/null \
    || echo "cellcli not available (not Exadata, or not in PATH for this user)"
echo ""
echo "--- Exadata Storage Server IPs ---"
cat /etc/oracle/cell/network-config/cellinit.ora 2>/dev/null \
    || cat /etc/oracle/olr.loc 2>/dev/null \
    || echo "No Exadata cell config found (may be VM shape)"
} | tee_out

# ---------------------------------------------------------------------------
# 9. TDE Configuration
# ---------------------------------------------------------------------------
log_section "TDE CONFIGURATION"
run_sql "
PROMPT --- Wallet Status ---
SELECT * FROM v\$encryption_wallet;
PROMPT
PROMPT --- Encrypted Tablespaces ---
SELECT tablespace_name, encrypted FROM dba_tablespaces WHERE encrypted='YES';
PROMPT
PROMPT --- TDE Master Keys ---
SELECT con_id, key_id, creator,
       TO_CHAR(creation_time,'YYYY-MM-DD HH24:MI') AS created,
       activating_dbname
FROM v\$encryption_keys ORDER BY creation_time;
" 2>&1 | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ---------------------------------------------------------------------------
# 10. Grid Infrastructure / RAC
# ---------------------------------------------------------------------------
log_section "GRID INFRASTRUCTURE AND RAC STATUS"
{
echo "--- CRS Status ---"
if [ -n "${GRID_HOME:-}" ] && [ -f "${GRID_HOME}/bin/crsctl" ]; then
    sudo -u grid -E ORACLE_HOME="$GRID_HOME" \
        "${GRID_HOME}/bin/crsctl" status resource -t 2>/dev/null \
    || echo "Could not get CRS status"
    echo ""
    echo "--- Cluster Nodes ---"
    sudo -u grid -E ORACLE_HOME="$GRID_HOME" \
        "${GRID_HOME}/bin/olsnodes" -n 2>/dev/null || echo "olsnodes not available"
    echo ""
    echo "--- OCR/Voting Disk Location ---"
    sudo -u grid -E ORACLE_HOME="$GRID_HOME" \
        "${GRID_HOME}/bin/ocrcheck" 2>/dev/null || echo "ocrcheck not available"
else
    echo "GRID_HOME not set — skipping CRS checks"
    echo "Checking for single-instance Oracle..."
    echo "RAC_STATUS: Single Instance (no GRID_HOME detected)"
fi
} | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

run_sql "
SELECT 'CLUSTER_DATABASE : '||value FROM v\$parameter WHERE name='cluster_database';
SELECT 'INSTANCE_NAME    : '||instance_name FROM v\$instance;
SELECT 'INSTANCE_NUMBER  : '||instance_number FROM v\$instance;
SELECT 'HOST_NAME        : '||host_name FROM v\$instance;
PROMPT
PROMPT --- All RAC Instances ---
SELECT instance_number, instance_name, host_name, status, thread#
FROM gv\$instance ORDER BY instance_number;
" 2>&1 | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ---------------------------------------------------------------------------
# 11. Network Configuration
# ---------------------------------------------------------------------------
log_section "NETWORK CONFIGURATION"
{
echo "--- Listener Status ---"
if [ -n "${ORACLE_HOME:-}" ]; then
    "${ORACLE_HOME}/bin/lsnrctl" status 2>/dev/null || echo "lsnrctl not available"
    echo ""
    echo "--- SCAN Listener (if RAC) ---"
    "${ORACLE_HOME}/bin/lsnrctl" status LISTENER_SCAN1 2>/dev/null || true
    "${ORACLE_HOME}/bin/lsnrctl" status LISTENER_SCAN2 2>/dev/null || true
    "${ORACLE_HOME}/bin/lsnrctl" status LISTENER_SCAN3 2>/dev/null || true
fi
echo ""
echo "--- tnsnames.ora ---"
for _f in "${TNS_ADMIN:-${ORACLE_HOME:-}/network/admin}/tnsnames.ora" /etc/tnsnames.ora; do
    [ -f "$_f" ] && { echo "File: $_f"; cat "$_f"; } || true
done
echo ""
echo "--- sqlnet.ora ---"
for _f in "${TNS_ADMIN:-${ORACLE_HOME:-}/network/admin}/sqlnet.ora" /etc/sqlnet.ora; do
    [ -f "$_f" ] && { echo "File: $_f"; cat "$_f"; } || true
done
} | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ---------------------------------------------------------------------------
# 12. OCI / Azure Integration
# ---------------------------------------------------------------------------
log_section "OCI AND AZURE INTEGRATION"
{
echo "--- OCI CLI Version ---"
oci --version 2>/dev/null || echo "OCI CLI not found in PATH"
echo ""
echo "--- OCI Config ---"
if [ -f ~/.oci/config ]; then
    echo "OCI config exists: ~/.oci/config"
    # Mask key_file content, show rest
    grep -v 'key_file' ~/.oci/config 2>/dev/null | grep -v 'key=' | head -20
else
    echo "No ~/.oci/config found"
fi
echo ""
echo "--- OCI Connectivity Test ---"
oci os ns get 2>/dev/null && echo "OCI connectivity: OK" \
    || echo "OCI connectivity: FAILED or not configured"
echo ""
echo "--- Azure Instance Metadata ---"
curl -s -m 5 -H Metadata:true \
    "http://169.254.169.254/metadata/instance?api-version=2021-02-01" 2>/dev/null \
    | python3 -m json.tool 2>/dev/null \
    || curl -s -m 5 -H Metadata:true \
       "http://169.254.169.254/metadata/instance?api-version=2021-02-01" 2>/dev/null \
    || echo "Azure IMDS not reachable"
echo ""
echo "--- OCI Instance Metadata ---"
curl -s -m 5 http://169.254.169.254/opc/v1/instance/ 2>/dev/null \
    || echo "OCI IMDS not reachable"
} | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ---------------------------------------------------------------------------
# 13. Network Security Group Rules (additional requirement)
# ---------------------------------------------------------------------------
log_section "NETWORK SECURITY GROUP RULES (ADDITIONAL)"
{
echo "--- iptables Rules ---"
sudo iptables -L -n -v 2>/dev/null || echo "Cannot read iptables (may need sudo)"
echo ""
echo "--- firewalld Status ---"
sudo firewall-cmd --list-all 2>/dev/null \
    || systemctl status firewalld 2>/dev/null \
    || echo "firewalld not running or not installed"
echo ""
echo "--- Open Ports (ss) ---"
ss -tlnp 2>/dev/null | grep -E ':1521|:22|:443|:80|:5500' \
    || netstat -tlnp 2>/dev/null | grep -E ':1521|:22|:443|:80|:5500' \
    || echo "ss/netstat not available"
echo ""
echo "--- TCP Connectivity from Target to Source (port 1521, 22) ---"
for _host in proddb01.corp.example.com; do
    for _port in 22 1521; do
        if timeout 5 bash -c "echo >/dev/tcp/$_host/$_port" 2>/dev/null; then
            echo "  $_host:$_port — OPEN"
        else
            echo "  $_host:$_port — BLOCKED or unreachable"
        fi
    done
done
echo ""
echo "NOTE: Cloud-level NSG/Security Group rules should be verified via"
echo "the Azure portal or OCI console — they are not visible from the OS."
} | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ---------------------------------------------------------------------------
# 14. Authentication
# ---------------------------------------------------------------------------
log_section "AUTHENTICATION"
{
echo "--- Password File ---"
ls -la "${ORACLE_HOME:-}/dbs/orapw${ORACLE_SID:-}" 2>/dev/null \
    || find "${ORACLE_HOME:-}/dbs" -name 'orapw*' -ls 2>/dev/null \
    || echo "No password file found in ORACLE_HOME/dbs"
echo ""
echo "--- SSH Directory (opc user) ---"
ls -la ~/.ssh/ 2>/dev/null || echo "No .ssh directory"
echo ""
echo "--- Authorized Keys ---"
cat ~/.ssh/authorized_keys 2>/dev/null | head -20 || echo "No authorized_keys"
} | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ---------------------------------------------------------------------------
# 15. ZDM-Relevant Parameters
# ---------------------------------------------------------------------------
log_section "ZDM-RELEVANT INIT PARAMETERS"
run_sql "
SELECT name, value FROM v\$parameter
WHERE name IN (
    'db_name','db_unique_name','enable_pluggable_database',
    'enable_goldengate_replication',
    'undo_tablespace','sga_target','pga_aggregate_target',
    'memory_target','memory_max_target',
    'processes','sessions','open_cursors',
    'db_block_size','compatible','cluster_database',
    'dg_broker_start','log_archive_config',
    'log_archive_dest_1','log_archive_dest_2'
)
ORDER BY name;
" 2>&1 | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ===========================================================================
# JSON SUMMARY
# ===========================================================================
DB_NAME=$(run_sql_value "SELECT name FROM v\$database;")
DB_UNIQUE=$(run_sql_value "SELECT db_unique_name FROM v\$database;")
DB_ROLE=$(run_sql_value "SELECT database_role FROM v\$database;")
OPEN_MODE=$(run_sql_value "SELECT open_mode FROM v\$database;")
IS_CDB=$(run_sql_value "SELECT cdb FROM v\$database;")
CHARSET=$(run_sql_value "SELECT value FROM nls_database_parameters WHERE parameter='NLS_CHARACTERSET';")
RAC_ENABLED=$(run_sql_value "SELECT value FROM v\$parameter WHERE name='cluster_database';")
COMPAT=$(run_sql_value "SELECT value FROM v\$parameter WHERE name='compatible';")
WALLET_STATUS=$(run_sql_value "SELECT status FROM v\$encryption_wallet WHERE rownum=1;")
OCI_CLI_VER=$(oci --version 2>/dev/null || echo "not installed")

cat > "$JSON_FILE" <<EOJSON
{
  "discovery_type": "target",
  "project": "ORADB Migration to Oracle Database@Azure",
  "target_host": "proddb-oda.eastus.azure.example.com",
  "run_host": "$(hostname)",
  "run_user": "$(whoami)",
  "timestamp": "$(date -Iseconds)",
  "oracle_home": "${ORACLE_HOME:-}",
  "oracle_sid": "${ORACLE_SID:-}",
  "grid_home": "${GRID_HOME:-}",
  "database": {
    "name": "${DB_NAME}",
    "unique_name": "${DB_UNIQUE}",
    "role": "${DB_ROLE}",
    "open_mode": "${OPEN_MODE}",
    "is_cdb": "${IS_CDB}",
    "charset": "${CHARSET}",
    "rac_enabled": "${RAC_ENABLED}",
    "compatible": "${COMPAT}"
  },
  "tde": {
    "wallet_status": "${WALLET_STATUS:-NOT_CONFIGURED}"
  },
  "oci_cli_version": "${OCI_CLI_VER}",
  "section_errors": ${SECTION_ERRORS}
}
EOJSON

# ===========================================================================
# FOOTER
# ===========================================================================
log_section "DISCOVERY COMPLETE"
{
echo "  Output file : $OUTPUT_FILE"
echo "  JSON file   : $JSON_FILE"
echo "  Completed   : $(date)"
echo "  Section errors: $SECTION_ERRORS (non-critical; some checks may have failed)"
echo ""
if [ "$SECTION_ERRORS" -gt 0 ]; then
    echo "  WARN: $SECTION_ERRORS section(s) encountered errors. Review output above."
else
    echo "  SUCCESS: All sections completed without errors."
fi
} | tee_out

exit 0
