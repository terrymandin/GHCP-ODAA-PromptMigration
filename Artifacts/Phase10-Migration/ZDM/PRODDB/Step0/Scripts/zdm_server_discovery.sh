#!/bin/bash
# =============================================================================
# ZDM Server Discovery Script
# =============================================================================
# Project  : PRODDB Migration to Oracle Database@Azure
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

# NO set -e  — continue even when individual checks fail
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
    # ZDM_HOME detection
    if [ -z "${ZDM_HOME:-}" ]; then

        # Method 1: Get ZDM_HOME from zdmuser's login shell environment
        if id "$ZDM_USER" &>/dev/null; then
            local zdm_home_from_user
            zdm_home_from_user=$(sudo -u "$ZDM_USER" -i bash -c 'echo $ZDM_HOME' 2>/dev/null)
            if [ -n "$zdm_home_from_user" ] && [ -f "${zdm_home_from_user}/bin/zdmcli" ]; then
                export ZDM_HOME="$zdm_home_from_user"
            fi
        fi

        # Method 2: Check zdmuser's home directory for common ZDM paths
        if [ -z "${ZDM_HOME:-}" ]; then
            local zdm_user_home
            zdm_user_home=$(eval echo "~$ZDM_USER" 2>/dev/null)
            if [ -n "$zdm_user_home" ]; then
                for _sub in zdmhome zdm app/zdmhome zdm_home; do
                    local _cand="$zdm_user_home/$_sub"
                    if [ -d "$_cand" ] && [ -f "$_cand/bin/zdmcli" ]; then
                        export ZDM_HOME="$_cand"
                        break
                    fi
                done
            fi
        fi

        # Method 3: Common system-wide installation locations
        if [ -z "${ZDM_HOME:-}" ]; then
            for _path in /u01/app/zdmhome /u01/zdm /u01/app/zdm /opt/zdm \
                         /home/zdmuser/zdmhome /home/zdmuser/zdm \
                         /home/azureuser/zdmhome "$HOME/zdmhome"; do
                if sudo test -f "$_path/bin/zdmcli" 2>/dev/null; then
                    export ZDM_HOME="$_path"
                    break
                elif [ -f "$_path/bin/zdmcli" ]; then
                    export ZDM_HOME="$_path"
                    break
                fi
            done
        fi

        # Method 4: Search for zdmcli binary
        if [ -z "${ZDM_HOME:-}" ]; then
            local zdmcli_path
            zdmcli_path=$(sudo find /u01 /opt /home -maxdepth 6 \
                -name "zdmcli" -type f 2>/dev/null | head -1)
            if [ -n "$zdmcli_path" ]; then
                export ZDM_HOME="$(dirname "$(dirname "$zdmcli_path")")"
            fi
        fi
    fi

    # JAVA_HOME detection
    if [ -z "${JAVA_HOME:-}" ]; then
        # Method 1: ZDM's bundled JDK
        if [ -n "${ZDM_HOME:-}" ] && [ -d "${ZDM_HOME}/jdk" ]; then
            export JAVA_HOME="${ZDM_HOME}/jdk"
        fi
        # Method 2: java alternatives
        if [ -z "${JAVA_HOME:-}" ] && command -v java >/dev/null 2>&1; then
            local java_real
            java_real=$(readlink -f "$(command -v java)" 2>/dev/null)
            [ -n "$java_real" ] && export JAVA_HOME="${java_real%/bin/java}"
        fi
        # Method 3: Common paths
        if [ -z "${JAVA_HOME:-}" ]; then
            for _jpath in /usr/java/latest /usr/java/jdk* /usr/lib/jvm/java-* /opt/java/jdk*; do
                if [ -d "$_jpath" ] && [ -f "$_jpath/bin/java" ]; then
                    export JAVA_HOME="$_jpath"
                    break
                fi
            done
        fi
    fi

    if [ -n "${ZDM_HOME:-}" ]; then
        export PATH="${ZDM_HOME}/bin:${JAVA_HOME:+$JAVA_HOME/bin:}$PATH"
    fi
}
detect_zdm_env

# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
log_info()    { echo -e "${GREEN}[INFO ] $*${RESET}"; }
log_warn()    { echo -e "${YELLOW}[WARN ] $*${RESET}"; }
log_error()   { echo -e "${RED}[ERROR] $*${RESET}"; }
log_section() {
    local bar="============================================================"
    echo "" | tee -a "$OUTPUT_FILE"
    echo -e "${CYAN}${BOLD}${bar}${RESET}" | tee -a "$OUTPUT_FILE"
    echo -e "${CYAN}${BOLD}  $*${RESET}"   | tee -a "$OUTPUT_FILE"
    echo -e "${CYAN}${BOLD}${bar}${RESET}" | tee -a "$OUTPUT_FILE"
    echo "" | tee -a "$OUTPUT_FILE"
}

# ---------------------------------------------------------------------------
# ZDM CLI helper — runs as ZDM_USER via sudo when needed
# ---------------------------------------------------------------------------
run_zdm_cmd() {
    local zdm_subcmd="$*"
    if [ -z "${ZDM_HOME:-}" ]; then
        echo "ERROR: ZDM_HOME not set — cannot run zdmcli"
        return 1
    fi
    if [ "$(id -un)" = "$ZDM_USER" ]; then
        "$ZDM_HOME/bin/zdmcli" $zdm_subcmd 2>&1
    else
        sudo -u "$ZDM_USER" \
            env ZDM_HOME="$ZDM_HOME" JAVA_HOME="${JAVA_HOME:-}" \
            PATH="${ZDM_HOME}/bin:${JAVA_HOME:+$JAVA_HOME/bin:}$PATH" \
            "$ZDM_HOME/bin/zdmcli" $zdm_subcmd 2>&1
    fi
}

run_zdm_service() {
    local subcmd="$1"
    if [ -z "${ZDM_HOME:-}" ]; then
        echo "ZDM_HOME not set"
        return 1
    fi
    if [ "$(id -un)" = "$ZDM_USER" ]; then
        "$ZDM_HOME/bin/zdmservice" "$subcmd" 2>&1
    else
        sudo -u "$ZDM_USER" \
            env ZDM_HOME="$ZDM_HOME" \
            "$ZDM_HOME/bin/zdmservice" "$subcmd" 2>&1
    fi
}

run_section() {
    local name="$1"; local fn="$2"
    log_section "$name"
    if ! $fn 2>&1 | tee -a "$OUTPUT_FILE"; then
        log_warn "Section '$name' reported errors (continuing)"
        SECTION_ERRORS=$((SECTION_ERRORS + 1))
    fi
}

# ===========================================================================
# DISCOVERY SECTIONS
# ===========================================================================

section_os_info() {
    echo "Hostname     : $(hostname -f 2>/dev/null || hostname)"
    echo "Short name   : $(hostname -s 2>/dev/null || hostname)"
    echo "Current user : $(id)"
    echo "Date/Time    : $(date)"
    echo "Uptime       : $(uptime)"
    echo ""
    echo "--- OS Version ---"
    cat /etc/os-release 2>/dev/null || cat /etc/redhat-release 2>/dev/null || uname -a
    echo ""
    echo "--- Kernel ---"
    uname -r
    echo ""
    echo "--- IP Addresses ---"
    ip addr show 2>/dev/null || ifconfig 2>/dev/null || echo "N/A"
}

section_zdm_installation() {
    echo "ZDM_HOME     : ${ZDM_HOME:-NOT FOUND}"
    echo "JAVA_HOME    : ${JAVA_HOME:-NOT FOUND}"
    echo ""

    if [ -z "${ZDM_HOME:-}" ]; then
        echo "ERROR: ZDM_HOME could not be determined."
        echo "Set ZDM_HOME_OVERRIDE environment variable and re-run:"
        echo "  export ZDM_HOME_OVERRIDE=/path/to/zdmhome"
        return 1
    fi

    echo "--- zdmcli Binary ---"
    if [ -f "$ZDM_HOME/bin/zdmcli" ]; then
        echo "FOUND: $ZDM_HOME/bin/zdmcli"
        ls -lh "$ZDM_HOME/bin/zdmcli" 2>/dev/null || true
    else
        echo "NOT FOUND: $ZDM_HOME/bin/zdmcli"
        return 1
    fi

    echo ""
    echo "--- ZDM Installation Verification (zdmcli with no args) ---"
    run_zdm_cmd 2>&1 | head -20 || echo "zdmcli invocation failed"

    echo ""
    echo "--- ZDM Service Status ---"
    run_zdm_service status || echo "zdmservice status check failed"

    echo ""
    echo "--- ZDM Response File Templates ---"
    if [ -d "$ZDM_HOME/rhp/zdm/template" ]; then
        ls -la "$ZDM_HOME/rhp/zdm/template/"*.rsp 2>/dev/null || \
            ls -la "$ZDM_HOME/rhp/zdm/template/" 2>/dev/null
    else
        # Try with sudo for restricted dirs
        sudo ls -la "$ZDM_HOME/rhp/zdm/template/" 2>/dev/null || \
        echo "Template directory not found at $ZDM_HOME/rhp/zdm/template"
    fi

    echo ""
    echo "--- Active Migration Jobs ---"
    run_zdm_cmd query jobid all 2>&1 || echo "No active jobs or zdmcli query failed"

    echo ""
    echo "--- ZDM Directory Structure ---"
    sudo ls -la "$ZDM_HOME/" 2>/dev/null | head -30 || ls -la "$ZDM_HOME/" 2>/dev/null | head -30
}

section_java_configuration() {
    echo "JAVA_HOME    : ${JAVA_HOME:-NOT SET}"
    echo ""
    if [ -n "${JAVA_HOME:-}" ] && [ -f "$JAVA_HOME/bin/java" ]; then
        "$JAVA_HOME/bin/java" -version 2>&1
    elif command -v java >/dev/null 2>&1; then
        java -version 2>&1
    else
        echo "java not found in PATH"
    fi
    echo ""
    echo "--- Java Alternatives ---"
    alternatives --display java 2>/dev/null | head -20 || \
    update-alternatives --display java 2>/dev/null | head -20 || \
    echo "alternatives not available"
}

section_oci_cli() {
    echo "--- OCI CLI Version ---"
    oci --version 2>&1 || echo "OCI CLI not installed"

    echo ""
    echo "--- OCI Config File ---"
    if [ -f ~/.oci/config ]; then
        echo "Found at ~/.oci/config"
        grep -E '^\[|^region|^tenancy|^user|^fingerprint|^key_file' ~/.oci/config 2>/dev/null
    else
        echo "~/.oci/config not found — checking zdmuser:"
        local zdm_user_home
        zdm_user_home=$(eval echo "~$ZDM_USER" 2>/dev/null)
        if sudo test -f "$zdm_user_home/.oci/config" 2>/dev/null; then
            echo "Found at $zdm_user_home/.oci/config"
            sudo -u "$ZDM_USER" cat "$zdm_user_home/.oci/config" 2>/dev/null | \
                grep -E '^\[|^region|^tenancy|^user|^fingerprint|^key_file'
        else
            echo "OCI config not found for $ZDM_USER either"
        fi
    fi

    echo ""
    echo "--- Configured OCI Profiles/Regions ---"
    oci iam region list --output table 2>&1 | head -20 || \
    sudo -u "$ZDM_USER" oci iam region list --output table 2>&1 | head -20 || \
    echo "OCI connectivity test failed"

    echo ""
    echo "--- OCI API Key File ---"
    local oci_key_path
    oci_key_path=$(grep 'key_file' ~/.oci/config 2>/dev/null | head -1 | sed 's/key_file = //' | xargs)
    if [ -n "$oci_key_path" ]; then
        if [ -f "$oci_key_path" ]; then
            echo "API key file exists: $oci_key_path"
        else
            echo "WARNING: API key file referenced but not found: $oci_key_path"
        fi
    fi
}

section_ssh_configuration() {
    echo "--- SSH Directory (current user: $(id -un)) ---"
    ls -la ~/.ssh/ 2>/dev/null || echo "No .ssh directory for current user"

    echo ""
    echo "--- SSH Keys Available ---"
    ls -la ~/.ssh/*.pub ~/.ssh/id_* 2>/dev/null || echo "No standard SSH key files found"

    echo ""
    echo "--- SSH Directory for $ZDM_USER ---"
    local zdm_home_dir
    zdm_home_dir=$(eval echo "~$ZDM_USER" 2>/dev/null)
    sudo -u "$ZDM_USER" ls -la "$zdm_home_dir/.ssh/" 2>/dev/null || \
        echo "Cannot list $ZDM_USER SSH directory"

    echo ""
    echo "--- SSH Agent ---"
    ssh-add -l 2>&1 || echo "No SSH agent or no loaded keys"
}

section_credential_files() {
    echo "--- Searching for Credential/Password Files ---"
    # Check common locations where ZDM credentials might be stored
    for _cred_path in "$HOME" "/home/$ZDM_USER" /etc/zdm /opt/zdm \
                      "${ZDM_HOME:-/nonexistent}/rhp/zdm"; do
        sudo find "$_cred_path" -maxdepth 3 \
            \( -name '*.wallet' -o -name '*.jks' -o -name 'cwallet.sso' \
               -o -name 'ewallet.p12' -o -name '*.pass' \
               -o -name 'zdm.cfg' -o -name 'zdm_*.conf' \) \
            -type f 2>/dev/null
    done

    echo ""
    echo "--- ZDM Wallet/Credential Store ---"
    if [ -n "${ZDM_HOME:-}" ]; then
        sudo find "$ZDM_HOME" -name 'cwallet.sso' -o -name 'ewallet.p12' \
             -o -name '*.wallet' 2>/dev/null | head -10
    fi
}

section_network_config() {
    echo "--- IP Addresses ---"
    ip addr 2>/dev/null | grep -E 'inet |ether'

    echo ""
    echo "--- Routing Table ---"
    ip route 2>/dev/null || route -n 2>/dev/null

    echo ""
    echo "--- DNS Configuration ---"
    cat /etc/resolv.conf 2>/dev/null

    echo ""
    echo "--- /etc/hosts (relevant entries) ---"
    grep -v '^#' /etc/hosts 2>/dev/null | grep -v '^$'
}

section_zdm_logs() {
    echo "--- ZDM Log Directory ---"
    if [ -n "${ZDM_HOME:-}" ]; then
        local zdm_log_dir
        for _logdir in "$ZDM_HOME/log" "$ZDM_HOME/logs" "$ZDM_HOME/rhp/zdm/log"; do
            if sudo test -d "$_logdir" 2>/dev/null; then
                zdm_log_dir="$_logdir"
                echo "Log directory: $zdm_log_dir"
                sudo ls -lhrt "$zdm_log_dir/" 2>/dev/null | tail -20
                break
            fi
        done
        [ -z "${zdm_log_dir:-}" ] && echo "ZDM log directory not found under $ZDM_HOME"
    else
        echo "ZDM_HOME not set — cannot locate log directory"
    fi

    echo ""
    echo "--- ZDM zdmsrv Log (last 50 lines) ---"
    if [ -n "${ZDM_HOME:-}" ]; then
        local srv_log
        srv_log=$(sudo find "$ZDM_HOME" -name 'zdmsrv*.log' -type f 2>/dev/null | \
                  xargs ls -t 2>/dev/null | head -1)
        if [ -n "$srv_log" ]; then
            echo "Latest log: $srv_log"
            sudo tail -50 "$srv_log" 2>/dev/null
        else
            echo "zdmsrv log not found"
        fi
    fi
}

# -----------------------------------------------------------------------
# ADDITIONAL ZDM SERVER DISCOVERY (user-requested)
# -----------------------------------------------------------------------

section_disk_space() {
    echo "--- File System Disk Usage ---"
    df -hP 2>/dev/null | column -t || df -h 2>/dev/null

    echo ""
    echo "=== ZDM Disk Space Requirement Check (minimum ${ZDM_MIN_DISK_GB}GB) ==="
    echo ""

    # Check space on the filesystem where ZDM_HOME resides
    if [ -n "${ZDM_HOME:-}" ]; then
        local zdm_fs zdm_free_gb
        zdm_fs=$(df -P "$ZDM_HOME" 2>/dev/null | tail -1 | awk '{print $6}')
        zdm_free_gb=$(df -P "$ZDM_HOME" 2>/dev/null | tail -1 | awk '{print $4}')
        zdm_free_gb=$((${zdm_free_gb:-0} / 1048576))  # 1K blocks -> GB
        echo "ZDM_HOME filesystem : $zdm_fs"
        echo "Available (GB)      : $zdm_free_gb"
        if [ "$zdm_free_gb" -ge "$ZDM_MIN_DISK_GB" ]; then
            echo "STATUS: OK — ${zdm_free_gb}GB available (minimum ${ZDM_MIN_DISK_GB}GB required)"
        else
            echo "STATUS: WARNING — Only ${zdm_free_gb}GB available; ${ZDM_MIN_DISK_GB}GB recommended"
            SECTION_ERRORS=$((SECTION_ERRORS + 1))
        fi
    else
        echo "ZDM_HOME not set — checking most likely locations"
    fi

    echo ""
    echo "--- Top Filesystems by Usage ---"
    df -hP 2>/dev/null | sort -k5 -rn | head -10

    echo ""
    echo "--- Large Directories (potential cleanup candidates) ---"
    sudo du -sh /u01/* /opt/* /home/* /tmp/* /var/log/* 2>/dev/null | \
        sort -rh | head -20 || \
    du -sh /tmp /var/log /home 2>/dev/null

    echo ""
    echo "--- ZDM Staging Area Disk Space ---"
    # ZDM needs space for backup sets, dumps, etc.
    for _staging_dir in /u01 /u02 /tmp /var/tmp /zdm_staging; do
        if [ -d "$_staging_dir" ]; then
            local staging_free_gb
            staging_free_gb=$(df -P "$_staging_dir" 2>/dev/null | tail -1 | awk '{print $4}')
            staging_free_gb=$((${staging_free_gb:-0} / 1048576))
            echo "$_staging_dir : ${staging_free_gb}GB available"
        fi
    done
}

section_network_latency() {
    echo "=== Network Connectivity & Latency Tests ==="
    echo ""

    # -----------------------------------------------------------------------
    # Source connectivity
    # -----------------------------------------------------------------------
    if [ -n "${SOURCE_HOST:-}" ]; then
        echo "--- Connectivity to SOURCE: ${SOURCE_HOST} ---"

        echo "  ICMP Ping (5 packets):"
        if ping -c 5 -W 3 "$SOURCE_HOST" 2>/dev/null; then
            SOURCE_PING="SUCCESS"
        else
            SOURCE_PING="FAILED"
            echo "  WARNING: Ping to source failed (ICMP may be blocked — check port tests below)"
        fi
        echo "  Ping result: $SOURCE_PING"

        echo ""
        echo "  Port Connectivity Tests:"
        for _port in 22 1521; do
            if timeout 5 bash -c "echo >/dev/tcp/${SOURCE_HOST}/${_port}" 2>/dev/null; then
                echo "  Port ${_port} ($([ $_port -eq 22 ] && echo SSH || echo Oracle)): OPEN"
            else
                echo "  Port ${_port} ($([ $_port -eq 22 ] && echo SSH || echo Oracle)): BLOCKED or unreachable"
            fi
        done

        echo ""
        echo "  Traceroute to source (first 15 hops):"
        traceroute -m 15 "$SOURCE_HOST" 2>&1 | head -20 || \
        tracepath -m 15 "$SOURCE_HOST" 2>&1 | head -20 || \
        echo "  traceroute/tracepath not available"

    else
        echo "SOURCE_HOST not provided — skipping source connectivity tests"
        echo "(Set SOURCE_HOST env variable or use orchestration script)"
        SOURCE_PING="SKIPPED"
    fi

    echo ""

    # -----------------------------------------------------------------------
    # Target connectivity
    # -----------------------------------------------------------------------
    if [ -n "${TARGET_HOST:-}" ]; then
        echo "--- Connectivity to TARGET: ${TARGET_HOST} ---"

        echo "  ICMP Ping (5 packets):"
        if ping -c 5 -W 3 "$TARGET_HOST" 2>/dev/null; then
            TARGET_PING="SUCCESS"
        else
            TARGET_PING="FAILED"
            echo "  WARNING: Ping to target failed (ICMP may be blocked — check port tests below)"
        fi
        echo "  Ping result: $TARGET_PING"

        echo ""
        echo "  Port Connectivity Tests:"
        for _port in 22 1521; do
            if timeout 5 bash -c "echo >/dev/tcp/${TARGET_HOST}/${_port}" 2>/dev/null; then
                echo "  Port ${_port} ($([ $_port -eq 22 ] && echo SSH || echo Oracle)): OPEN"
            else
                echo "  Port ${_port} ($([ $_port -eq 22 ] && echo SSH || echo Oracle)): BLOCKED or unreachable"
            fi
        done

        echo ""
        echo "  Traceroute to target (first 15 hops):"
        traceroute -m 15 "$TARGET_HOST" 2>&1 | head -20 || \
        tracepath -m 15 "$TARGET_HOST" 2>&1 | head -20 || \
        echo "  traceroute/tracepath not available"

    else
        echo "TARGET_HOST not provided — skipping target connectivity tests"
        echo "(Set TARGET_HOST env variable or use orchestration script)"
        TARGET_PING="SKIPPED"
    fi

    echo ""
    echo "--- ZDM Server Internet Connectivity (OCI/Azure endpoints) ---"
    for _endpoint in "objectstorage.us-ashburn-1.oraclecloud.com" \
                     "management.azure.com" \
                     "login.microsoftonline.com"; do
        if timeout 5 bash -c "echo >/dev/tcp/${_endpoint}/443" 2>/dev/null; then
            echo "  ${_endpoint}:443 — OPEN"
        else
            echo "  ${_endpoint}:443 — BLOCKED or unreachable"
        fi
    done

    echo ""
    echo "--- Bandwidth Estimation (using /dev/null) ---"
    # Quick throughput test if dd available
    echo "  Note: For accurate bandwidth testing, use iperf3 between servers"
    dd if=/dev/zero bs=1M count=100 2>&1 | grep -E 'copied|bytes' || true
}

# ===========================================================================
# JSON SUMMARY
# ===========================================================================

generate_json_summary() {
    local hostname
    hostname=$(hostname -f 2>/dev/null || hostname)
    local zdm_installed="false"
    [ -f "${ZDM_HOME:-/nonexistent}/bin/zdmcli" ] && zdm_installed="true"

    cat > "$JSON_FILE" <<EOJSON
{
  "discovery_type"   : "zdm_server",
  "project"          : "PRODDB Migration to Oracle Database@Azure",
  "generated_at"     : "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hostname"         : "${hostname}",
  "zdm_home"         : "${ZDM_HOME:-unknown}",
  "zdm_installed"    : ${zdm_installed},
  "java_home"        : "${JAVA_HOME:-unknown}",
  "zdm_user"         : "${ZDM_USER}",
  "source_host"      : "${SOURCE_HOST:-not_provided}",
  "target_host"      : "${TARGET_HOST:-not_provided}",
  "source_ping"      : "${SOURCE_PING:-SKIPPED}",
  "target_ping"      : "${TARGET_PING:-SKIPPED}",
  "section_errors"   : ${SECTION_ERRORS},
  "output_text_file" : "${OUTPUT_FILE}"
}
EOJSON
    echo "JSON summary written to: $JSON_FILE"
}

# ===========================================================================
# MAIN
# ===========================================================================

{
echo "============================================================"
echo "  ZDM SERVER DISCOVERY"
echo "  Project    : PRODDB Migration to Oracle Database@Azure"
echo "  Host       : $(hostname -f 2>/dev/null || hostname)"
echo "  Started    : $(date)"
echo "  Run by     : $(id)"
echo "  ZDM_HOME   : ${ZDM_HOME:-NOT FOUND}"
echo "  ZDM_USER   : ${ZDM_USER}"
echo "  SOURCE_HOST: ${SOURCE_HOST:-NOT PROVIDED}"
echo "  TARGET_HOST: ${TARGET_HOST:-NOT PROVIDED}"
echo "============================================================"
} | tee "$OUTPUT_FILE"

run_section "1. OS INFORMATION"                    section_os_info
run_section "2. ZDM INSTALLATION"                  section_zdm_installation
run_section "3. JAVA CONFIGURATION"                section_java_configuration
run_section "4. OCI CLI CONFIGURATION"             section_oci_cli
run_section "5. SSH CONFIGURATION"                 section_ssh_configuration
run_section "6. CREDENTIAL FILES"                  section_credential_files
run_section "7. NETWORK CONFIGURATION"             section_network_config
run_section "8. ZDM LOGS"                          section_zdm_logs
run_section "9. DISK SPACE (min ${ZDM_MIN_DISK_GB}GB required)" section_disk_space
run_section "10. NETWORK LATENCY TO SOURCE/TARGET" section_network_latency

generate_json_summary

{
echo ""
echo "============================================================"
echo "  DISCOVERY COMPLETE"
echo "  Sections with errors : $SECTION_ERRORS"
echo "  Text report : $OUTPUT_FILE"
echo "  JSON summary: $JSON_FILE"
echo "  Finished    : $(date)"
echo "============================================================"
} | tee -a "$OUTPUT_FILE"

exit 0
