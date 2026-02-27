#!/bin/bash
# =============================================================================
# ZDM Server Discovery Script
# =============================================================================
# Project  : ORADB Migration to Oracle Database@Azure
# ZDM Host : zdm-jumpbox.corp.example.com
# Generated: 2026-02-26
#
# USAGE:
#   ./zdm_server_discovery.sh
#
# SSH as ZDM_ADMIN_USER (azureuser); ZDM CLI runs as zdmuser via sudo.
# SOURCE_HOST and TARGET_HOST are injected by zdm_orchestrate_discovery.sh.
# Set ZDM_HOME_OVERRIDE / JAVA_HOME_OVERRIDE to force specific values.
# =============================================================================

# NO set -e — continue even when individual checks fail
SECTION_ERRORS=0
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME_SHORT=$(hostname -s 2>/dev/null || hostname)
OUTPUT_FILE="./zdm_server_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_server_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

# ---------------------------------------------------------------------------
# User configuration (injected by orchestration script)
# ---------------------------------------------------------------------------
ZDM_USER="${ZDM_USER:-zdmuser}"
SOURCE_HOST="${SOURCE_HOST:-}"   # Passed by orchestration script
TARGET_HOST="${TARGET_HOST:-}"   # Passed by orchestration script

# Minimum disk space required for ZDM operations (GB)
ZDM_MIN_DISK_GB=50

# ---------------------------------------------------------------------------
# Environment bootstrap (3-tier priority)
# ---------------------------------------------------------------------------
# Tier 1: explicit overrides
[ -n "${ZDM_HOME_OVERRIDE:-}"  ] && export ZDM_HOME="$ZDM_HOME_OVERRIDE"
[ -n "${JAVA_HOME_OVERRIDE:-}" ] && export JAVA_HOME="$JAVA_HOME_OVERRIDE"

# Tier 2: extract from shell profiles (bypasses interactive guards)
for _profile in /etc/profile /etc/profile.d/*.sh ~/.bash_profile ~/.bashrc; do
    [ -f "$_profile" ] || continue
    eval "$(grep -E '^export[[:space:]]+(ZDM_HOME|JAVA_HOME|PATH)=' \
           "$_profile" 2>/dev/null)" 2>/dev/null || true
done

# Tier 3: auto-detect ZDM_HOME and JAVA_HOME
detect_zdm_env() {
    # ---------- ZDM_HOME detection ----------
    if [ -z "${ZDM_HOME:-}" ]; then
        # Method 1: Get ZDM_HOME from zdmuser's login shell environment
        if id "$ZDM_USER" &>/dev/null; then
            local zdm_home_from_user
            zdm_home_from_user=$(sudo -u "$ZDM_USER" -i bash -c 'echo $ZDM_HOME' 2>/dev/null)
            if [ -n "$zdm_home_from_user" ] && [ -d "$zdm_home_from_user" ] \
               && [ -f "$zdm_home_from_user/bin/zdmcli" ]; then
                export ZDM_HOME="$zdm_home_from_user"
            fi
        fi

        # Method 2: Check zdmuser's home directory for common ZDM paths
        if [ -z "${ZDM_HOME:-}" ]; then
            local zdm_user_home
            zdm_user_home=$(eval echo "~${ZDM_USER}" 2>/dev/null)
            if [ -n "$zdm_user_home" ]; then
                for _subdir in zdmhome zdm app/zdmhome app/zdm; do
                    local _candidate="${zdm_user_home}/${_subdir}"
                    if [ -d "$_candidate" ] && [ -f "$_candidate/bin/zdmcli" ]; then
                        export ZDM_HOME="$_candidate"
                        break
                    fi
                done
            fi
        fi

        # Method 3: Common system-wide installation paths
        if [ -z "${ZDM_HOME:-}" ]; then
            for _path in /u01/app/zdmhome /u01/zdm /u01/app/zdm \
                         /opt/zdm /opt/zdmhome \
                         /home/zdmuser/zdmhome /home/*/zdmhome \
                         ~/zdmhome ~/zdm "$HOME/zdmhome"; do
                if sudo test -d "$_path" 2>/dev/null \
                   && sudo test -f "$_path/bin/zdmcli" 2>/dev/null; then
                    export ZDM_HOME="$_path"
                    break
                elif [ -d "$_path" ] && [ -f "$_path/bin/zdmcli" ]; then
                    export ZDM_HOME="$_path"
                    break
                fi
            done
        fi

        # Method 4: Find zdmcli binary and derive ZDM_HOME
        if [ -z "${ZDM_HOME:-}" ]; then
            local zdmcli_path
            zdmcli_path=$(sudo find /u01 /opt /home -name "zdmcli" -type f 2>/dev/null | head -1)
            if [ -n "$zdmcli_path" ]; then
                export ZDM_HOME="$(dirname "$(dirname "$zdmcli_path")")"
            fi
        fi
    fi

    # ---------- JAVA_HOME detection ----------
    if [ -z "${JAVA_HOME:-}" ]; then
        # Method 1: ZDM's bundled JDK (highest priority)
        if [ -n "${ZDM_HOME:-}" ] && [ -d "${ZDM_HOME}/jdk" ]; then
            export JAVA_HOME="${ZDM_HOME}/jdk"
        fi

        # Method 2: alternatives
        if [ -z "${JAVA_HOME:-}" ] && command -v java >/dev/null 2>&1; then
            local _java_path
            _java_path=$(readlink -f "$(command -v java)" 2>/dev/null)
            if [ -n "$_java_path" ]; then
                export JAVA_HOME="${_java_path%/bin/java}"
            fi
        fi

        # Method 3: common Java paths
        if [ -z "${JAVA_HOME:-}" ]; then
            for _jpath in /usr/java/latest /usr/java/jdk* \
                          /usr/lib/jvm/java-* /opt/java/jdk* \
                          /usr/lib/jvm/jdk*; do
                if [ -d "$_jpath" ] && [ -f "$_jpath/bin/java" ]; then
                    export JAVA_HOME="$_jpath"
                    break
                fi
            done
        fi
    fi
}
detect_zdm_env

[ -n "${JAVA_HOME:-}"  ] && export PATH="${JAVA_HOME}/bin:${PATH}"
[ -n "${ZDM_HOME:-}"   ] && export PATH="${ZDM_HOME}/bin:${PATH}"

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
# ZDM CLI helper — runs zdmcli as ZDM_USER
# ---------------------------------------------------------------------------
run_zdm() {
    local zdm_cmd="$1"
    if [ -z "${ZDM_HOME:-}" ]; then
        echo "ERROR: ZDM_HOME not set — cannot run ZDM CLI"
        return 1
    fi
    if [ "$(whoami)" = "$ZDM_USER" ]; then
        ZDM_HOME="$ZDM_HOME" "${ZDM_HOME}/bin/${zdm_cmd}" 2>&1
    else
        sudo -u "$ZDM_USER" -E ZDM_HOME="$ZDM_HOME" \
            "${ZDM_HOME}/bin/${zdm_cmd}" 2>&1
    fi
}

# ===========================================================================
# DISCOVERY SECTIONS
# ===========================================================================

# ---------------------------------------------------------------------------
# 1. Script Header
# ---------------------------------------------------------------------------
{
echo "================================================================"
echo "  ZDM SERVER DISCOVERY REPORT"
echo "================================================================"
echo "  Project    : ORADB Migration to Oracle Database@Azure"
echo "  ZDM Host   : zdm-jumpbox.corp.example.com"
echo "  Run Host   : $(hostname)"
echo "  Run User   : $(whoami)"
echo "  ZDM User   : $ZDM_USER"
echo "  Source Host: ${SOURCE_HOST:-NOT PROVIDED}"
echo "  Target Host: ${TARGET_HOST:-NOT PROVIDED}"
echo "  Timestamp  : $(date)"
echo "  ZDM_HOME   : ${ZDM_HOME:-NOT DETECTED}"
echo "  JAVA_HOME  : ${JAVA_HOME:-NOT DETECTED}"
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
} | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ---------------------------------------------------------------------------
# 3. Disk Space (additional requirement: minimum 50GB check)
# ---------------------------------------------------------------------------
log_section "DISK SPACE FOR ZDM OPERATIONS (ADDITIONAL)"
{
echo "--- Filesystem Usage ---"
df -h 2>/dev/null
echo ""
echo "--- ZDM Minimum Disk Requirement Check (${ZDM_MIN_DISK_GB}GB) ---"

# Check partition hosting ORACLE_HOME area for zdmuser or /home/zdmuser
for _check_path in "${ZDM_HOME:-/tmp}" "/home/${ZDM_USER}" /var/log /tmp; do
    if [ -d "$_check_path" ]; then
        local_avail_gb=$(df "$_check_path" 2>/dev/null | tail -1 | awk '{printf "%.1f", $4/1024/1024}')
        echo "  $_check_path — available: ${local_avail_gb} GB"
        if awk "BEGIN {exit !(${local_avail_gb:-0} >= ${ZDM_MIN_DISK_GB})}"; then
            echo "    STATUS: PASS (>= ${ZDM_MIN_DISK_GB}GB)"
        else
            echo "    STATUS: WARNING — less than ${ZDM_MIN_DISK_GB}GB available"
            SECTION_ERRORS=$((SECTION_ERRORS + 1))
        fi
    fi
done
} | tee_out

# ---------------------------------------------------------------------------
# 4. ZDM Installation
# ---------------------------------------------------------------------------
log_section "ZDM INSTALLATION"
{
echo "--- ZDM_HOME ---"
echo "  ZDM_HOME: ${ZDM_HOME:-NOT DETECTED}"
echo ""
if [ -n "${ZDM_HOME:-}" ]; then
    echo "--- zdmcli Executable ---"
    ls -la "${ZDM_HOME}/bin/zdmcli" 2>/dev/null || echo "zdmcli not found at \$ZDM_HOME/bin/zdmcli"
    echo ""
    echo "--- ZDM Directory Contents ---"
    ls -la "${ZDM_HOME}/" 2>/dev/null || echo "Cannot list ZDM_HOME"
    echo ""
    echo "--- ZDM Response File Templates ---"
    ls -la "${ZDM_HOME}/rhp/zdm/template/"*.rsp 2>/dev/null \
        || ls -la "${ZDM_HOME}/template/"*.rsp 2>/dev/null \
        || echo "No .rsp templates found"
fi
} | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ---------------------------------------------------------------------------
# 5. ZDM Service Status
# ---------------------------------------------------------------------------
log_section "ZDM SERVICE STATUS"
{
echo "--- ZDM Service Status ---"
if [ -n "${ZDM_HOME:-}" ]; then
    if [ "$(whoami)" = "$ZDM_USER" ]; then
        "${ZDM_HOME}/bin/zdmservice" status 2>/dev/null \
            || echo "zdmservice returned non-zero (may be stopped)"
    else
        sudo -u "$ZDM_USER" -E ZDM_HOME="$ZDM_HOME" \
            "${ZDM_HOME}/bin/zdmservice" status 2>/dev/null \
            || echo "zdmservice returned non-zero (may be stopped)"
    fi
else
    echo "ZDM_HOME not set — cannot check service status"
fi

echo ""
echo "--- zdmcli invocation (installation check) ---"
# ZDM does NOT support -version; running without args shows usage if installed
run_zdm "zdmcli" 2>&1 | head -20 || echo "zdmcli not accessible"

echo ""
echo "--- ZDM User Process Check ---"
ps -ef | grep -E 'zdm' | grep -v grep || echo "No ZDM processes found"
} | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ---------------------------------------------------------------------------
# 6. Active ZDM Migration Jobs
# ---------------------------------------------------------------------------
log_section "ACTIVE ZDM MIGRATION JOBS"
{
if [ -n "${ZDM_HOME:-}" ]; then
    echo "--- zdmcli query jobid (list all jobs) ---"
    if [ "$(whoami)" = "$ZDM_USER" ]; then
        "${ZDM_HOME}/bin/zdmcli" query jobid -all 2>/dev/null \
            || echo "No active jobs or zdmcli not responding"
    else
        sudo -u "$ZDM_USER" -E ZDM_HOME="$ZDM_HOME" \
            "${ZDM_HOME}/bin/zdmcli" query jobid -all 2>/dev/null \
            || echo "No active jobs or zdmcli not responding"
    fi
else
    echo "ZDM_HOME not set — cannot query jobs"
fi
} | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ---------------------------------------------------------------------------
# 7. Java Configuration
# ---------------------------------------------------------------------------
log_section "JAVA CONFIGURATION"
{
echo "JAVA_HOME: ${JAVA_HOME:-NOT SET}"
echo ""
echo "--- Java Version ---"
if [ -n "${JAVA_HOME:-}" ]; then
    "${JAVA_HOME}/bin/java" -version 2>&1
elif command -v java >/dev/null 2>&1; then
    java -version 2>&1
else
    echo "java not found in PATH and JAVA_HOME not set"
fi
echo ""
echo "--- ZDM Bundled JDK Check ---"
if [ -n "${ZDM_HOME:-}" ]; then
    ls -la "${ZDM_HOME}/jdk/bin/java" 2>/dev/null \
        && "${ZDM_HOME}/jdk/bin/java" -version 2>&1 \
        || echo "No bundled JDK at \$ZDM_HOME/jdk"
fi
} | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ---------------------------------------------------------------------------
# 8. OCI CLI Configuration
# ---------------------------------------------------------------------------
log_section "OCI CLI CONFIGURATION"
{
echo "--- OCI CLI Version ---"
oci --version 2>/dev/null || echo "OCI CLI not found in PATH"
echo ""
echo "--- OCI Version (as zdmuser) ---"
if [ "$(whoami)" != "$ZDM_USER" ]; then
    sudo -u "$ZDM_USER" -i bash -c 'oci --version 2>/dev/null || echo "oci not in zdmuser PATH"' 2>/dev/null
fi
echo ""
echo "--- OCI Config Location ---"
for _cfg in ~/.oci/config "/home/${ZDM_USER}/.oci/config"; do
    if [ -f "$_cfg" ]; then
        echo "Found OCI config: $_cfg"
        grep -v 'key_file\|key=' "$_cfg" | head -30
    fi
done
[ ! -f ~/.oci/config ] && echo "No ~/.oci/config for current user"
echo ""
echo "--- OCI API Key Files ---"
ls -la ~/.oci/*.pem 2>/dev/null || echo "No .pem files in ~/.oci/"
echo ""
echo "--- OCI Connectivity Test ---"
oci os ns get 2>/dev/null && echo "OCI connectivity: OK" \
    || echo "OCI connectivity: FAILED or not configured"
} | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ---------------------------------------------------------------------------
# 9. SSH Configuration
# ---------------------------------------------------------------------------
log_section "SSH CONFIGURATION"
{
echo "--- SSH Keys (current user: $(whoami)) ---"
ls -la ~/.ssh/ 2>/dev/null || echo "No .ssh directory for current user"
echo ""
echo "--- SSH Keys (zdmuser) ---"
if [ "$(whoami)" != "$ZDM_USER" ]; then
    sudo -u "$ZDM_USER" bash -c 'ls -la ~/.ssh/ 2>/dev/null || echo "No .ssh for zdmuser"' 2>/dev/null
fi
echo ""
echo "--- SSH Config ---"
cat ~/.ssh/config 2>/dev/null || echo "No ~/.ssh/config"
echo ""
echo "--- SSH Known Hosts (relevant entries) ---"
grep -E "(proddb01|proddb-oda|zdm-jumpbox)" ~/.ssh/known_hosts 2>/dev/null \
    || echo "No matching entries in known_hosts"
} | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ---------------------------------------------------------------------------
# 10. ZDM Log Directory
# ---------------------------------------------------------------------------
log_section "ZDM LOG DIRECTORY"
{
if [ -n "${ZDM_HOME:-}" ]; then
    local _zdm_log_base="${ZDM_HOME}/log"
    [ ! -d "$_zdm_log_base" ] && _zdm_log_base="${ZDM_HOME}/zdm/log"
    echo "--- ZDM Log Directory: ${_zdm_log_base} ---"
    if sudo test -d "$_zdm_log_base" 2>/dev/null; then
        sudo ls -lht "$_zdm_log_base" 2>/dev/null | head -20
        echo ""
        echo "--- Most Recent Log (last 20 lines) ---"
        local _latest_log
        _latest_log=$(sudo ls -t "$_zdm_log_base"/*.log 2>/dev/null | head -1)
        [ -n "$_latest_log" ] && sudo tail -20 "$_latest_log" 2>/dev/null \
            || echo "No .log files found"
    else
        echo "Log directory not found or not accessible"
    fi
else
    echo "ZDM_HOME not set — cannot locate logs"
fi
} | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ---------------------------------------------------------------------------
# 11. Credential / Password File Search
# ---------------------------------------------------------------------------
log_section "CREDENTIAL FILES SEARCH"
{
echo "--- Searching for ZDM credential files ---"
find /home /u01 /opt -name "*.wallet" -o -name "*.sso" -o \
     -name "cwallet.sso" -o -name "ewallet.p12" 2>/dev/null | head -20 \
    || echo "No wallet files found (or permission denied)"
echo ""
echo "--- Searching for OCI key files ---"
find /home -name "*.pem" -o -name "oci_api_key*" 2>/dev/null | head -10 \
    || echo "No .pem files found"
} | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ---------------------------------------------------------------------------
# 12. Network Configuration
# ---------------------------------------------------------------------------
log_section "NETWORK CONFIGURATION"
{
echo "--- IP Addresses ---"
ip addr show 2>/dev/null | grep -E '(inet |inet6 )' | awk '{print $2}' \
    || ifconfig 2>/dev/null | grep 'inet '
echo ""
echo "--- Routing Table ---"
ip route show 2>/dev/null || route -n 2>/dev/null || netstat -rn 2>/dev/null
echo ""
echo "--- DNS Configuration ---"
cat /etc/resolv.conf 2>/dev/null
echo ""
echo "--- /etc/hosts (relevant entries) ---"
grep -E "(proddb01|proddb-oda|zdm-jumpbox|oracle|localhost)" /etc/hosts 2>/dev/null \
    || cat /etc/hosts 2>/dev/null | head -20
} | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ---------------------------------------------------------------------------
# 13. Network Latency to Source and Target (additional requirement)
# ---------------------------------------------------------------------------
log_section "NETWORK LATENCY TO SOURCE AND TARGET (ADDITIONAL)"
{
# --- Source server tests ---
if [ -n "${SOURCE_HOST:-}" ]; then
    echo "================================================================"
    echo "  CONNECTIVITY TO SOURCE: ${SOURCE_HOST}"
    echo "================================================================"
    echo ""
    echo "--- Ping (ICMP) ---"
    if ping -c 5 -W 3 "${SOURCE_HOST}" 2>/dev/null; then
        SOURCE_PING="SUCCESS"
    else
        echo "ICMP ping failed (may be blocked by firewall)"
        SOURCE_PING="FAILED"
    fi
    echo ""
    echo "--- Port Tests (TCP) ---"
    for _port in 22 1521; do
        if timeout 5 bash -c "echo >/dev/tcp/${SOURCE_HOST}/${_port}" 2>/dev/null; then
            echo "  ${SOURCE_HOST}:${_port} — OPEN"
        else
            echo "  ${SOURCE_HOST}:${_port} — BLOCKED or unreachable"
        fi
    done
    echo ""
    echo "--- Traceroute to Source ---"
    traceroute -m 15 -w 2 "${SOURCE_HOST}" 2>/dev/null | head -20 \
        || tracepath "${SOURCE_HOST}" 2>/dev/null | head -20 \
        || echo "traceroute/tracepath not available"
else
    echo "SOURCE_HOST not provided — skipping source connectivity tests"
    SOURCE_PING="SKIPPED"
fi

echo ""

# --- Target server tests ---
if [ -n "${TARGET_HOST:-}" ]; then
    echo "================================================================"
    echo "  CONNECTIVITY TO TARGET: ${TARGET_HOST}"
    echo "================================================================"
    echo ""
    echo "--- Ping (ICMP) ---"
    if ping -c 5 -W 3 "${TARGET_HOST}" 2>/dev/null; then
        TARGET_PING="SUCCESS"
    else
        echo "ICMP ping failed (may be blocked by firewall)"
        TARGET_PING="FAILED"
    fi
    echo ""
    echo "--- Port Tests (TCP) ---"
    for _port in 22 1521; do
        if timeout 5 bash -c "echo >/dev/tcp/${TARGET_HOST}/${_port}" 2>/dev/null; then
            echo "  ${TARGET_HOST}:${_port} — OPEN"
        else
            echo "  ${TARGET_HOST}:${_port} — BLOCKED or unreachable"
        fi
    done
    echo ""
    echo "--- Traceroute to Target ---"
    traceroute -m 15 -w 2 "${TARGET_HOST}" 2>/dev/null | head -20 \
        || tracepath "${TARGET_HOST}" 2>/dev/null | head -20 \
        || echo "traceroute/tracepath not available"
else
    echo "TARGET_HOST not provided — skipping target connectivity tests"
    TARGET_PING="SKIPPED"
fi
} | tee_out || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# Capture ping results for JSON (set defaults if not yet set)
SOURCE_PING="${SOURCE_PING:-SKIPPED}"
TARGET_PING="${TARGET_PING:-SKIPPED}"

# ===========================================================================
# JSON SUMMARY
# ===========================================================================
ZDM_INSTALLED="false"
[ -n "${ZDM_HOME:-}" ] && [ -f "${ZDM_HOME}/bin/zdmcli" ] && ZDM_INSTALLED="true"

OCI_CLI_VER=$(oci --version 2>/dev/null || echo "not installed")
JAVA_VER=""
[ -n "${JAVA_HOME:-}" ] && JAVA_VER=$("${JAVA_HOME}/bin/java" -version 2>&1 | head -1) || true
AVAIL_DISK_GB=$(df "${ZDM_HOME:-/home}" 2>/dev/null | tail -1 | awk '{printf "%.1f", $4/1024/1024}')

cat > "$JSON_FILE" <<EOJSON
{
  "discovery_type": "zdm_server",
  "project": "ORADB Migration to Oracle Database@Azure",
  "zdm_host": "zdm-jumpbox.corp.example.com",
  "run_host": "$(hostname)",
  "run_user": "$(whoami)",
  "zdm_user": "${ZDM_USER}",
  "source_host": "${SOURCE_HOST:-}",
  "target_host": "${TARGET_HOST:-}",
  "timestamp": "$(date -Iseconds)",
  "zdm": {
    "zdm_home": "${ZDM_HOME:-}",
    "installed": ${ZDM_INSTALLED}
  },
  "java": {
    "java_home": "${JAVA_HOME:-}",
    "version": "${JAVA_VER}"
  },
  "storage": {
    "available_gb": "${AVAIL_DISK_GB}",
    "minimum_required_gb": ${ZDM_MIN_DISK_GB}
  },
  "connectivity": {
    "source_ping": "${SOURCE_PING}",
    "target_ping": "${TARGET_PING}"
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
echo ""
echo "  ZDM_HOME  : ${ZDM_HOME:-NOT DETECTED}"
echo "  JAVA_HOME : ${JAVA_HOME:-NOT DETECTED}"
echo "  Source ping: ${SOURCE_PING}"
echo "  Target ping: ${TARGET_PING}"
} | tee_out

exit 0
