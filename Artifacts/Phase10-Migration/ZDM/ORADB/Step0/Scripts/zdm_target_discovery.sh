#!/bin/bash
# =============================================================================
# zdm_target_discovery.sh
# ZDM Target Database Discovery Script (Oracle Database@Azure)
# Project: ORADB  |  Target Host: 10.0.1.160
# Generated: 2026-02-27
#
# USAGE:
#   Via orchestration: Executed automatically by zdm_orchestrate_discovery.sh
#   Manual SSH:        ssh -i ~/.ssh/odaa.pem opc@10.0.1.160 'bash -l -s' < zdm_target_discovery.sh
#   Local run:         ./zdm_target_discovery.sh
#
# ENVIRONMENT OVERRIDES (optional, set before running if auto-detection fails):
#   TARGET_REMOTE_ORACLE_HOME  - Override ORACLE_HOME on target server
#   TARGET_REMOTE_ORACLE_SID   - Override ORACLE_SID on target server
#   ORACLE_USER                - Oracle software owner user (default: oracle)
#   OCI_COMPARTMENT_OCID       - OCI compartment OCID (for NSG queries)
#   OCI_CONFIG_PATH            - OCI CLI config path (default: ~/.oci/config)
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
OUTPUT_TXT="./zdm_target_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
OUTPUT_JSON="./zdm_target_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

# --- Oracle User default ---
ORACLE_USER="${ORACLE_USER:-oracle}"

# --- OCI Config ---
OCI_CONFIG_PATH="${OCI_CONFIG_PATH:-${HOME}/.oci/config}"
OCI_COMPARTMENT_OCID="${OCI_COMPARTMENT_OCID:-}"

# =============================================================================
# ENVIRONMENT DETECTION
# =============================================================================

detect_oracle_env() {
    log_info "Detecting Oracle environment on target..."

    # Apply explicit overrides (highest priority)
    [ -n "${TARGET_REMOTE_ORACLE_HOME:-}" ] && export ORACLE_HOME="$TARGET_REMOTE_ORACLE_HOME"
    [ -n "${TARGET_REMOTE_ORACLE_SID:-}"  ] && export ORACLE_SID="$TARGET_REMOTE_ORACLE_SID"

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
        [ -n "$pmon_sid" ] && export ORACLE_SID="$pmon_sid"
    fi

    # Method 3: Common paths (ExaDB/DBCS typical locations)
    if [ -z "${ORACLE_HOME:-}" ]; then
        for path in /u01/app/oracle/product/*/dbhome_1 \
                    /u01/app/oracle/product/*/db_1 \
                    /u02/app/oracle/product/*/dbhome_1 \
                    /opt/oracle/product/*/dbhome_1; do
            if [ -d "$path" ] && [ -f "$path/bin/sqlplus" ]; then
                export ORACLE_HOME="$path"
                log_info "Detected ORACLE_HOME: $ORACLE_HOME"
                break
            fi
        done
    fi

    # Method 4: oraenv
    if [ -z "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ] && [ -f /usr/local/bin/oraenv ]; then
        ORAENV_ASK=NO . /usr/local/bin/oraenv 2>/dev/null
    fi

    if [ -n "${ORACLE_HOME:-}" ]; then
        export ORACLE_BASE="${ORACLE_BASE:-$(echo "$ORACLE_HOME" | sed 's|/product/.*||')}"
    fi

    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        log_info "Final Oracle env: ORACLE_HOME=$ORACLE_HOME  ORACLE_SID=$ORACLE_SID"
    else
        log_error "Could not detect Oracle environment. Set TARGET_REMOTE_ORACLE_HOME and TARGET_REMOTE_ORACLE_SID."
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
        echo "UNKNOWN"; return 1
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

# OCI CLI helper
run_oci() {
    if command -v oci &>/dev/null; then
        oci "$@" 2>&1
    else
        echo "  OCI CLI not found - skipping OCI command: oci $*"
        return 1
    fi
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
    echo "  TARGET_REMOTE_ORACLE_HOME  Override auto-detected ORACLE_HOME"
    echo "  TARGET_REMOTE_ORACLE_SID   Override auto-detected ORACLE_SID"
    echo "  ORACLE_USER                Oracle software owner (default: oracle)"
    echo "  OCI_COMPARTMENT_OCID       OCI compartment OCID for NSG queries"
    echo "  OCI_CONFIG_PATH            OCI CLI config path (default: ~/.oci/config)"
    echo ""
    echo "Output files written to current directory:"
    echo "  zdm_target_discovery_<hostname>_<timestamp>.txt"
    echo "  zdm_target_discovery_<hostname>_<timestamp>.json"
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
    echo "  ZDM Target Database Discovery Report (Oracle Database@Azure)"
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
        || ifconfig 2>/dev/null | grep -E 'inet addr:|inet '
    echo ""
    echo "--- OS Version ---"
    cat /etc/os-release 2>/dev/null \
        || cat /etc/redhat-release 2>/dev/null \
        || uname -a
    echo "Kernel:   $(uname -r)"
    echo "Arch:     $(uname -m)"

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
            "$ORACLE_HOME/bin/sqlplus" -v 2>/dev/null
        else
            sudo -u "$ORACLE_USER" -E ORACLE_HOME="$ORACLE_HOME" \
                "$ORACLE_HOME/bin/sqlplus" -v 2>/dev/null
        fi
        echo ""
        echo "--- /etc/oratab ---"
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
SELECT 'DB Name:         ' || name           FROM v\$database;
SELECT 'DB Unique Name:  ' || db_unique_name  FROM v\$database;
SELECT 'DBID:            ' || dbid            FROM v\$database;
SELECT 'DB Role:         ' || database_role   FROM v\$database;
SELECT 'Open Mode:       ' || open_mode       FROM v\$database;
SELECT 'Log Mode:        ' || log_mode        FROM v\$database;
SELECT 'Platform:        ' || platform_name   FROM v\$database;
"

    echo ""
    echo "--- Character Set ---"
    run_sql "
SELECT parameter, value
FROM nls_database_parameters
WHERE parameter IN ('NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET')
ORDER BY parameter;
"

    echo ""
    echo "--- Available Storage (Non-ASM Tablespaces) ---"
    run_sql "
SELECT t.tablespace_name,
       t.contents,
       ROUND(NVL(d.used_mb,0)/1024,2) used_gb,
       ROUND(NVL(d.free_mb,0)/1024,2) free_gb,
       ROUND(NVL(d.total_mb,0)/1024,2) total_gb,
       t.status
FROM dba_tablespaces t
LEFT JOIN (
    SELECT tablespace_name,
           SUM(bytes)/1024/1024 total_mb,
           0 free_mb,
           SUM(bytes)/1024/1024 used_mb
    FROM dba_data_files
    GROUP BY tablespace_name
) d ON t.tablespace_name = d.tablespace_name
ORDER BY t.tablespace_name;
"

    # -----------------------------------------------------------------------
    # Section 4: Container Database (CDB/PDB)
    # -----------------------------------------------------------------------
    echo ""
    echo "================================================================"
    echo "  Section 4: Container Database Status"
    echo "================================================================"
    run_sql "
SELECT 'CDB:         ' || cdb    FROM v\$database;
SELECT 'Con_ID:      ' || con_id  FROM v\$database;
"

    echo ""
    echo "--- PDB List ---"
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
    echo "  Section 5: TDE / Wallet Status"
    echo "================================================================"
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

    # -----------------------------------------------------------------------
    # Section 6: Network Configuration
    # -----------------------------------------------------------------------
    echo ""
    echo "================================================================"
    echo "  Section 6: Network Configuration"
    echo "================================================================"
    echo "--- Listener Status ---"
    if [ -n "${ORACLE_HOME:-}" ]; then
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            "$ORACLE_HOME/bin/lsnrctl" status 2>/dev/null || echo "  lsnrctl error"
        else
            sudo -u "$ORACLE_USER" -E ORACLE_HOME="$ORACLE_HOME" \
                "$ORACLE_HOME/bin/lsnrctl" status 2>/dev/null || echo "  lsnrctl error"
        fi
    fi

    echo ""
    echo "--- SCAN Listener (RAC/Exadata) ---"
    if [ -n "${ORACLE_HOME:-}" ]; then
        if [ "$(whoami)" = "$ORACLE_USER" ]; then
            "$ORACLE_HOME/bin/lsnrctl" status LISTENER_SCAN1 2>/dev/null \
                || echo "  No SCAN listener found (may be single instance)"
        else
            sudo -u "$ORACLE_USER" -E ORACLE_HOME="$ORACLE_HOME" \
                "$ORACLE_HOME/bin/lsnrctl" status LISTENER_SCAN1 2>/dev/null \
                || echo "  No SCAN listener found (may be single instance)"
        fi
    fi

    echo ""
    echo "--- tnsnames.ora ---"
    local tns_found=false
    for tns_dir in "${ORACLE_HOME:-}/network/admin" "${TNS_ADMIN:-}" /etc; do
        [ -z "$tns_dir" ] && continue
        if [ -f "$tns_dir/tnsnames.ora" ]; then
            echo "  Location: $tns_dir/tnsnames.ora"
            cat "$tns_dir/tnsnames.ora"
            tns_found=true
            break
        fi
    done
    $tns_found || echo "  tnsnames.ora not found in standard locations"

    # -----------------------------------------------------------------------
    # Section 7: OCI / Azure Integration
    # -----------------------------------------------------------------------
    echo ""
    echo "================================================================"
    echo "  Section 7: OCI / Azure Integration"
    echo "================================================================"
    echo "--- OCI CLI Version ---"
    if command -v oci &>/dev/null; then
        oci --version 2>&1
        echo ""
        echo "--- OCI Config ---"
        echo "  Config path: $OCI_CONFIG_PATH"
        if [ -f "$OCI_CONFIG_PATH" ]; then
            # Mask private key content
            grep -v 'key_file' "$OCI_CONFIG_PATH" | \
                sed 's/\(pass_phrase\s*=\s*\).*/\1***MASKED***/'
        else
            echo "  OCI config not found at $OCI_CONFIG_PATH"
        fi
        echo ""
        echo "--- OCI Connectivity Test ---"
        oci iam region list --output table 2>&1 | head -20 \
            || echo "  OCI connectivity test failed - check OCI CLI config"
    else
        echo "  OCI CLI not installed or not in PATH"
    fi

    echo ""
    echo "--- Instance Metadata (OCI/Azure) ---"
    # OCI IMDS
    if curl -s -m 5 http://169.254.169.254/opc/v2/instance/ -H "Authorization: Bearer Oracle" &>/dev/null; then
        echo "  OCI Instance Metadata:"
        curl -s -m 5 http://169.254.169.254/opc/v2/instance/ -H "Authorization: Bearer Oracle" 2>/dev/null \
            | python3 -m json.tool 2>/dev/null \
            || curl -s -m 5 http://169.254.169.254/opc/v2/instance/ -H "Authorization: Bearer Oracle"
    else
        echo "  OCI IMDS not reachable"
    fi
    # Azure IMDS
    if curl -s -m 5 "http://169.254.169.254/metadata/instance?api-version=2021-02-01" -H "Metadata: true" &>/dev/null; then
        echo ""
        echo "  Azure Instance Metadata:"
        curl -s -m 5 "http://169.254.169.254/metadata/instance?api-version=2021-02-01" -H "Metadata: true" 2>/dev/null \
            | python3 -m json.tool 2>/dev/null \
            || curl -s -m 5 "http://169.254.169.254/metadata/instance?api-version=2021-02-01" -H "Metadata: true"
    fi

    # -----------------------------------------------------------------------
    # Section 8: Grid Infrastructure
    # -----------------------------------------------------------------------
    echo ""
    echo "================================================================"
    echo "  Section 8: Grid Infrastructure (RAC/Exadata)"
    echo "================================================================"
    # Check for Grid Infrastructure
    local grid_home=""
    for path in /u01/app/grid /u01/app/19.0.0.0/grid /u01/app/21.0.0.0/grid \
                /u01/app/grid/product/*/grid; do
        if [ -d "$path" ] && [ -f "$path/bin/crsctl" ]; then
            grid_home="$path"
            break
        fi
    done

    if [ -n "$grid_home" ]; then
        echo "  Grid Home: $grid_home"
        echo ""
        echo "--- CRS Status ---"
        sudo "$grid_home/bin/crsctl" status res -t 2>/dev/null \
            || "$grid_home/bin/crsctl" status res -t 2>/dev/null \
            || echo "  crsctl not accessible"
        echo ""
        echo "--- Cluster Nodes ---"
        sudo "$grid_home/bin/olsnodes" -n 2>/dev/null \
            || "$grid_home/bin/olsnodes" -n 2>/dev/null \
            || echo "  olsnodes not accessible"
    else
        echo "  Grid Infrastructure not found - may be single instance"
        echo "  Checking CRS via common paths..."
        for crs_path in /u01/app/grid/bin/crsctl /u01/app/19*/grid/bin/crsctl; do
            if [ -f "$crs_path" ]; then
                echo "  Found crsctl at: $crs_path"
                sudo "$crs_path" check cluster 2>/dev/null || echo "  CRS check failed"
                break
            fi
        done
    fi

    # -----------------------------------------------------------------------
    # Section 9: Authentication
    # -----------------------------------------------------------------------
    echo ""
    echo "================================================================"
    echo "  Section 9: Authentication"
    echo "================================================================"
    echo "--- SSH Directory Contents ---"
    local oracle_home_dir
    oracle_home_dir=$(eval echo ~${ORACLE_USER} 2>/dev/null)
    if [ -d "${oracle_home_dir}/.ssh" ]; then
        ls -la "${oracle_home_dir}/.ssh/" 2>/dev/null \
            || sudo ls -la "${oracle_home_dir}/.ssh/" 2>/dev/null \
            || echo "  Cannot read ${oracle_home_dir}/.ssh/"
    else
        echo "  ${oracle_home_dir}/.ssh not found"
    fi

    # =======================================================================
    # ADDITIONAL DISCOVERY (Project-Specific Requirements)
    # =======================================================================

    # -----------------------------------------------------------------------
    # Section 10: Exadata Storage Capacity (Additional)
    # -----------------------------------------------------------------------
    echo ""
    echo "================================================================"
    echo "  Section 10: Exadata/ASM Storage Capacity (Additional)"
    echo "================================================================"

    echo "--- ASM Disk Groups ---"
    run_sql "
SELECT name,
       state,
       type,
       ROUND(total_mb/1024,2)       total_gb,
       ROUND(free_mb/1024,2)        free_gb,
       ROUND(usable_file_mb/1024,2) usable_gb,
       ROUND((total_mb - free_mb)/total_mb * 100, 1) pct_used
FROM v\$asm_diskgroup
ORDER BY name;
" 2>/dev/null || echo "  ASM disk groups not accessible (may not be ASM or not connected as sysasm)"

    echo ""
    echo "--- ASM Disk Details ---"
    run_sql "
SELECT dg.name AS diskgroup_name,
       d.name  AS disk_name,
       d.path  AS disk_path,
       d.state,
       ROUND(d.total_mb/1024,2) total_gb,
       ROUND(d.free_mb/1024,2)  free_gb,
       d.header_status
FROM v\$asm_disk d
JOIN v\$asm_diskgroup dg ON d.group_number = dg.group_number
WHERE d.header_status NOT IN ('FORMER','CANDIDATE')
ORDER BY dg.name, d.name;
" 2>/dev/null || echo "  ASM disk details not accessible"

    echo ""
    echo "--- Exadata Cell Configuration (cellcli) ---"
    if command -v cellcli &>/dev/null; then
        echo "  Running: cellcli -e 'list cell detail'"
        cellcli -e "list cell detail" 2>&1 || echo "  cellcli failed - may need root/celladmin access"
        echo ""
        echo "  Running: cellcli -e 'list griddisk attributes name,disktype,size,freespace'"
        cellcli -e "list griddisk attributes name,disktype,size,freespace" 2>/dev/null \
            || echo "  cellcli griddisk query failed"
    else
        echo "  cellcli not found in PATH (trying common locations...)"
        for cellcli_path in /usr/local/bin/cellcli /opt/oracle/exadata/exac-config/cellcli \
                            /root/cellcli; do
            if [ -f "$cellcli_path" ]; then
                echo "  Found cellcli at: $cellcli_path"
                sudo "$cellcli_path" -e "list cell detail" 2>/dev/null \
                    || echo "  cellcli execution failed - check permissions"
                break
            fi
        done
        [ -z "$(command -v cellcli 2>/dev/null)" ] && \
            echo "  cellcli not found - this may be ExaDB-D or non-Exadata target"
    fi

    echo ""
    echo "--- ExaDB-D Storage (if applicable) ---"
    # For Oracle Exadata Database Service on Dedicated Infrastructure (ExaDB-D)
    # storage info is in the OCI console, but we can get what's visible from the DB
    run_sql "
SELECT name, space_limit/1024/1024/1024 limit_gb,
       space_used/1024/1024/1024   used_gb,
       space_reclaimable/1024/1024/1024 reclaimable_gb,
       number_of_files
FROM v\$recovery_file_dest;
" 2>/dev/null || echo "  FRA query failed"

    echo ""
    echo "--- OCI Storage Volumes (via OCI CLI) ---"
    if command -v oci &>/dev/null && [ -n "${OCI_COMPARTMENT_OCID:-}" ]; then
        echo "  Querying OCI block volumes in compartment..."
        oci bv volume list \
            --compartment-id "$OCI_COMPARTMENT_OCID" \
            --output table \
            --query "data[*].{Name:\"display-name\",Size:\"size-in-gbs\",State:\"lifecycle-state\"}" \
            2>&1 | head -30
    else
        echo "  OCI CLI not available or OCI_COMPARTMENT_OCID not set - skipping OCI storage query"
        echo "  Set OCI_COMPARTMENT_OCID to enable this query"
    fi

    # -----------------------------------------------------------------------
    # Section 11: Pre-Configured PDBs (Additional - Detailed PDB Inventory)
    # -----------------------------------------------------------------------
    echo ""
    echo "================================================================"
    echo "  Section 11: Pre-Configured PDBs - Detailed Inventory (Additional)"
    echo "================================================================"

    echo "--- PDB Summary from CDB_PDBS ---"
    run_sql "
SELECT pdb_id,
       pdb_name,
       status,
       open_mode,
       restricted,
       TO_CHAR(creation_time,'YYYY-MM-DD HH24:MI:SS') creation_time
FROM cdb_pdbs
ORDER BY pdb_id;
" 2>/dev/null || echo "  cdb_pdbs not accessible (not a CDB?)"

    echo ""
    echo "--- PDB Open Mode from V\$PDBS ---"
    run_sql "
SELECT con_id, name, open_mode, restricted, open_time
FROM v\$pdbs
ORDER BY con_id;
" 2>/dev/null || echo "  v\$pdbs not accessible"

    echo ""
    echo "--- PDB Storage Quotas ---"
    run_sql "
SELECT pdb_name, count(*) tablespace_count
FROM cdb_tablespaces
WHERE con_id > 2
GROUP BY pdb_name
ORDER BY pdb_name;
" 2>/dev/null || echo "  cdb_tablespaces con_id query not accessible"

    echo ""
    echo "--- PDB Services ---"
    run_sql "
SELECT pdb, name, network_name, creation_date
FROM cdb_services
WHERE pdb != 'CDB\$ROOT'
ORDER BY pdb, name;
" 2>/dev/null || echo "  cdb_services PDB query not accessible"

    echo ""
    echo "--- Application Root/Seed PDBs ---"
    run_sql "
SELECT p.pdb_name, p.application_root, p.application_pdb, p.application_seed,
       p.is_proxy, p.status
FROM cdb_pdbs p
WHERE p.application_root = 'YES' OR p.application_pdb = 'YES'
ORDER BY p.pdb_name;
" 2>/dev/null || echo "  Application container check skipped (pre-12.2 or not available)"

    # -----------------------------------------------------------------------
    # Section 12: Network Security Group Rules (Additional)
    # -----------------------------------------------------------------------
    echo ""
    echo "================================================================"
    echo "  Section 12: Network Security Group (NSG) Rules (Additional)"
    echo "================================================================"

    if ! command -v oci &>/dev/null; then
        echo "  OCI CLI not found - cannot query NSG rules"
        echo "  Install OCI CLI to enable this section"
    else
        echo "--- OCI CLI Version ---"
        oci --version 2>&1

        echo ""
        echo "--- Network Security Groups in Compartment ---"
        if [ -n "${OCI_COMPARTMENT_OCID:-}" ]; then
            local nsg_list
            nsg_list=$(oci network nsg list \
                --compartment-id "$OCI_COMPARTMENT_OCID" \
                --output json 2>/dev/null)
            if [ -n "$nsg_list" ]; then
                echo "$nsg_list" | python3 -m json.tool 2>/dev/null || echo "$nsg_list"
                echo ""
                echo "--- NSG Rules for Each NSG ---"
                # Extract NSG IDs and query rules for each
                local nsg_ids
                nsg_ids=$(echo "$nsg_list" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for item in data.get('data', []):
    print(item.get('id',''))
" 2>/dev/null)
                if [ -n "$nsg_ids" ]; then
                    while IFS= read -r nsg_id; do
                        [ -z "$nsg_id" ] && continue
                        local nsg_name
                        nsg_name=$(echo "$nsg_list" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for item in data.get('data', []):
    if item.get('id') == '$nsg_id':
        print(item.get('display-name','UNKNOWN'))
" 2>/dev/null)
                        echo ""
                        echo "  NSG: $nsg_name ($nsg_id)"
                        echo "  Rules:"
                        oci network nsg rules list \
                            --nsg-id "$nsg_id" \
                            --output table 2>&1 || echo "    Could not retrieve rules for NSG $nsg_id"
                    done <<< "$nsg_ids"
                else
                    echo "  Could not parse NSG IDs from response"
                fi
            else
                echo "  No NSGs found or OCI CLI error"
                echo "  Check: oci network nsg list --compartment-id <COMPARTMENT_OCID>"
            fi
        else
            echo "  OCI_COMPARTMENT_OCID not set - cannot list NSGs"
            echo "  Set OCI_COMPARTMENT_OCID before running this script"
            echo ""
            echo "  Manual NSG query commands:"
            echo "    oci network nsg list --compartment-id <COMPARTMENT_OCID> --output table"
            echo "    oci network nsg rules list --nsg-id <NSG_OCID> --output table"
        fi

        echo ""
        echo "--- Security Lists in VCN (if applicable) ---"
        if [ -n "${OCI_COMPARTMENT_OCID:-}" ]; then
            echo "  Querying VCNs in compartment..."
            local vcn_list
            vcn_list=$(oci network vcn list \
                --compartment-id "$OCI_COMPARTMENT_OCID" \
                --output table \
                --query "data[*].{VCN:\"display-name\",OCID:id,CIDR:\"cidr-block\",State:\"lifecycle-state\"}" \
                2>&1)
            echo "$vcn_list" | head -30

            echo ""
            echo "  Querying Subnets in compartment..."
            oci network subnet list \
                --compartment-id "$OCI_COMPARTMENT_OCID" \
                --output table \
                --query "data[*].{Name:\"display-name\",CIDR:\"cidr-block\",State:\"lifecycle-state\",Public:\"prohibit-public-ip-on-vnic\"}" \
                2>&1 | head -30
        fi

        echo ""
        echo "--- DB Security Rules (OCI DB System) ---"
        local target_db_ocid="${TARGET_DATABASE_OCID:-}"
        if [ -n "$target_db_ocid" ]; then
            echo "  DB System OCID: $target_db_ocid"
            oci db system get --db-system-id "$target_db_ocid" \
                --query "data.{Name:\"display-name\",Shape:shape,NodeCount:\"node-count\",State:\"lifecycle-state\",NSGs:\"nsg-ids\"}" \
                --output table 2>&1 || echo "  Could not retrieve DB system details - check TARGET_DATABASE_OCID"
        else
            echo "  TARGET_DATABASE_OCID not set - set this variable to query DB system NSG associations"
        fi
    fi

    # =======================================================================
    # JSON SUMMARY
    # =======================================================================
    echo ""
    echo "================================================================"
    echo "  Discovery Summary"
    echo "================================================================"
    echo "Project:        ORADB"
    echo "Script:         zdm_target_discovery.sh"
    echo "Completed:      $(date)"
    echo "Host:           $(hostname -s)"
    echo "ORACLE_HOME:    ${ORACLE_HOME:-UNKNOWN}"
    echo "ORACLE_SID:     ${ORACLE_SID:-UNKNOWN}"
    echo "Output TXT:     $OUTPUT_TXT"
    echo "Output JSON:    $OUTPUT_JSON"

    local db_name db_unique_name db_role db_cdb db_version
    db_name=$(run_sql_noheading "SELECT name FROM v\$database;")
    db_unique_name=$(run_sql_noheading "SELECT db_unique_name FROM v\$database;")
    db_role=$(run_sql_noheading "SELECT database_role FROM v\$database;")
    db_cdb=$(run_sql_noheading "SELECT cdb FROM v\$database;")
    db_version=$(run_sql_noheading "SELECT version FROM v\$instance;")

    cat > "$OUTPUT_JSON" <<EOJSON
{
  "discovery_type": "target",
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
    "role": "$db_role",
    "cdb": "$db_cdb",
    "version": "$db_version"
  },
  "additional_discovery": {
    "exadata_storage_capacity": "see txt report section 10",
    "pre_configured_pdbs": "see txt report section 11",
    "nsg_rules": "see txt report section 12"
  },
  "output_txt": "$OUTPUT_TXT"
}
EOJSON

    log_info "Target discovery complete."
    log_info "TXT Report:  $(pwd)/$OUTPUT_TXT"
    log_info "JSON Report: $(pwd)/$OUTPUT_JSON"
}

# =============================================================================
# ENTRY POINT
# =============================================================================

run_discovery 2>&1 | tee "$OUTPUT_TXT"
