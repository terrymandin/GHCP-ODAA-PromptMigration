#!/bin/bash
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration
# =============================================================================
# zdm_server_discovery.sh
# ZDM Migration - ZDM Jumpbox Server Discovery Script
# Project: ORADB
#
# PURPOSE: Collects read-only diagnostic information from the ZDM jumpbox
#          server to validate readiness for executing ZDM-based migration.
#
# USAGE:   bash zdm_server_discovery.sh [options]
#          Options:
#            -h, --help     Show this help message
#            -v, --verbose  Enable verbose output
#
# ENVIRONMENT VARIABLES (set by orchestration script):
#   SOURCE_HOST          Source database host for connectivity tests
#   TARGET_HOST          Target database host for connectivity tests
#   ZDM_USER             ZDM software owner (default: zdmuser)
#   ZDM_HOME_OVERRIDE    Override auto-detected ZDM_HOME
#   JAVA_HOME_OVERRIDE   Override auto-detected JAVA_HOME
#
# OUTPUT:  ./zdm_server_discovery_<hostname>_<timestamp>.txt
#          ./zdm_server_discovery_<hostname>_<timestamp>.json
#
# NOTES:   - All operations are strictly READ-ONLY
#          - ZDM CLI commands executed via sudo -u zdmuser
#          - zdmcli does NOT accept a -version flag
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
REPORT_FILE="./zdm_server_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_server_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"
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
    echo "  ZDM_HOME_OVERRIDE   Override auto-detected ZDM_HOME"
    echo "  JAVA_HOME_OVERRIDE  Override auto-detected JAVA_HOME"
    echo "  ZDM_USER            ZDM software owner (default: zdmuser)"
    echo "  SOURCE_HOST         Source DB host for connectivity tests"
    echo "  TARGET_HOST         Target DB host for connectivity tests"
    exit 0
}

for arg in "$@"; do
    case "$arg" in
        -h|--help)    show_help ;;
        -v|--verbose) VERBOSE=true ;;
    esac
done

mkdir -p "$(dirname "$REPORT_FILE")" 2>/dev/null || true
{
    echo "# ZDM Server Discovery Report"
    echo "# Generated: $(date)"
    echo "# Host:      $(hostname)"
    echo "# User:      $(whoami)"
    echo "# Script:    zdm_server_discovery.sh"
    echo "# Project:   ORADB"
    echo "# -------------------------------------------------------"
} > "$REPORT_FILE"

log_info "ZDM server discovery started at $(date)"

ZDM_USER="${ZDM_USER:-zdmuser}"

# ---------------------------------------------------------------------------
# Auto-detect ZDM environment
# ---------------------------------------------------------------------------
detect_zdm_env() {
    if [ -n "${ZDM_HOME:-}" ] && [ -n "${JAVA_HOME:-}" ]; then
        log_debug "ZDM_HOME and JAVA_HOME already set"
        return 0
    fi
    log_info "Auto-detecting ZDM environment..."

    # Method 1: Get ZDM_HOME from zdmuser's login shell
    if [ -z "${ZDM_HOME:-}" ]; then
        if id "$ZDM_USER" &>/dev/null; then
            local zdm_home_from_user
            zdm_home_from_user=$(sudo -u "$ZDM_USER" -i bash -c 'echo $ZDM_HOME' 2>/dev/null) || true
            if [ -n "$zdm_home_from_user" ] && [ -f "${zdm_home_from_user}/bin/zdmcli" ]; then
                export ZDM_HOME="$zdm_home_from_user"
                log_info "ZDM_HOME from ${ZDM_USER} environment: $ZDM_HOME"
            fi
        fi
    fi

    # Method 2: Check zdmuser's home directory for common locations
    if [ -z "${ZDM_HOME:-}" ]; then
        local zdm_user_home
        zdm_user_home=$(getent passwd "$ZDM_USER" 2>/dev/null | cut -d: -f6) || \
            zdm_user_home=$(eval echo "~$ZDM_USER" 2>/dev/null)
        if [ -n "$zdm_user_home" ]; then
            for subdir in zdmhome zdm app/zdmhome; do
                local candidate="${zdm_user_home}/${subdir}"
                if sudo test -d "$candidate" 2>/dev/null && sudo test -f "${candidate}/bin/zdmcli" 2>/dev/null; then
                    export ZDM_HOME="$candidate"
                    log_info "ZDM_HOME from ${ZDM_USER} home: $ZDM_HOME"
                    break
                fi
            done
        fi
    fi

    # Method 3: Common system-wide paths
    if [ -z "${ZDM_HOME:-}" ]; then
        for path in /u01/app/zdmhome /u01/zdm /u01/app/zdm /opt/zdm /home/zdmuser/zdmhome; do
            if sudo test -d "$path" 2>/dev/null && sudo test -f "${path}/bin/zdmcli" 2>/dev/null; then
                export ZDM_HOME="$path"
                log_info "ZDM_HOME from path search: $ZDM_HOME"
                break
            fi
        done
    fi

    # Method 4: Search for zdmcli binary
    if [ -z "${ZDM_HOME:-}" ]; then
        local zdmcli_path
        zdmcli_path=$(sudo find /u01 /opt /home -name "zdmcli" -type f 2>/dev/null | head -1) || true
        if [ -n "$zdmcli_path" ]; then
            export ZDM_HOME="$(dirname "$(dirname "$zdmcli_path")")"
            log_info "ZDM_HOME derived from zdmcli binary: $ZDM_HOME"
        fi
    fi

    # Detect JAVA_HOME
    if [ -z "${JAVA_HOME:-}" ]; then
        # Method 1: ZDM bundled JDK
        if [ -n "${ZDM_HOME:-}" ] && [ -d "${ZDM_HOME}/jdk" ]; then
            export JAVA_HOME="${ZDM_HOME}/jdk"
        elif command -v java &>/dev/null; then
            local java_path
            java_path=$(readlink -f "$(command -v java)" 2>/dev/null) || true
            [ -n "$java_path" ] && export JAVA_HOME="${java_path%/bin/java}"
        else
            for path in /usr/java/latest /usr/java/jdk* /usr/lib/jvm/java-*; do
                if [ -d "$path" ] && [ -f "$path/bin/java" ]; then
                    export JAVA_HOME="$path"; break
                fi
            done
        fi
    fi

    if [ -z "${ZDM_HOME:-}" ]; then
        log_warn "Could not auto-detect ZDM_HOME"
    fi
}

detect_zdm_env
[ -n "${ZDM_HOME_OVERRIDE:-}" ]  && export ZDM_HOME="$ZDM_HOME_OVERRIDE"  && log_info "ZDM_HOME overridden"
[ -n "${JAVA_HOME_OVERRIDE:-}" ] && export JAVA_HOME="$JAVA_HOME_OVERRIDE" && log_info "JAVA_HOME overridden"
export ZDM_HOME="${ZDM_HOME:-}"
export JAVA_HOME="${JAVA_HOME:-}"

declare -A JSON
JSON["timestamp"]="$(date -Iseconds 2>/dev/null || date)"
JSON["hostname"]="$HOSTNAME_SHORT"
JSON["project"]="ORADB"
JSON["script"]="zdm_server_discovery.sh"
JSON["zdm_home"]="${ZDM_HOME:-}"
JSON["java_home"]="${JAVA_HOME:-}"

# ---------------------------------------------------------------------------
# SECTION 1: OS Information
# ---------------------------------------------------------------------------
log_section "OS Information"
{
    log_raw "Hostname:    $(hostname)"
    log_raw "Current user: $(whoami)"
    log_raw "IP addresses:"
    ip addr show 2>/dev/null | grep 'inet ' | awk '{print "  " $2}' | tee -a "$REPORT_FILE" || \
        ifconfig 2>/dev/null | grep 'inet ' | awk '{print "  " $2}' | tee -a "$REPORT_FILE"
    log_raw "OS version:"
    cat /etc/os-release 2>/dev/null | tee -a "$REPORT_FILE" || uname -a | tee -a "$REPORT_FILE"
    log_raw "Kernel: $(uname -r)"

    log_raw ""
    log_raw "--- Disk space (WARNING if filesystem < 50GB free) ---"
    df -hP 2>/dev/null | tee -a "$REPORT_FILE"
    df -hP 2>/dev/null | awk 'NR>1 {avail=$4; unit=substr(avail,length(avail)); size=avail+0;
        if (unit=="G" && size < 50) print "  WARNING: " $6 " has only " avail " free (< 50GB recommended for ZDM)";
        if (unit=="M") print "  WARNING: " $6 " has only " avail " free (< 50GB recommended for ZDM)"}' | tee -a "$REPORT_FILE"
} || log_error "OS information section failed"

# ---------------------------------------------------------------------------
# SECTION 2: ZDM Installation
# ---------------------------------------------------------------------------
log_section "ZDM Installation"
{
    log_raw "ZDM_HOME: ${ZDM_HOME:-NOT DETECTED}"
    log_raw "ZDM_USER: $ZDM_USER"

    if [ -n "${ZDM_HOME:-}" ]; then
        log_raw "--- zdmcli binary check ---"
        sudo ls -la "${ZDM_HOME}/bin/zdmcli" 2>&1 | tee -a "$REPORT_FILE"

        # NOTE: zdmcli does NOT accept -version — display usage info instead
        log_raw "--- zdmcli usage (no -version flag supported) ---"
        sudo -u "$ZDM_USER" -E ZDM_HOME="$ZDM_HOME" \
            "${ZDM_HOME}/bin/zdmcli" 2>&1 | head -30 | tee -a "$REPORT_FILE" || \
            log_warn "zdmcli invocation failed"

        log_raw "--- ZDM response file templates ---"
        sudo ls -la "${ZDM_HOME}/rhp/zdm/template/"*.rsp 2>/dev/null | tee -a "$REPORT_FILE" || \
            log_warn "No ZDM response file templates found at ${ZDM_HOME}/rhp/zdm/template/"

        log_raw "--- ZDM service status ---"
        sudo -u "$ZDM_USER" -E ZDM_HOME="$ZDM_HOME" \
            "${ZDM_HOME}/bin/zdmservice" status 2>&1 | tee -a "$REPORT_FILE" || \
            log_warn "zdmservice status failed"

        log_raw "--- Active ZDM migration jobs ---"
        sudo -u "$ZDM_USER" -E ZDM_HOME="$ZDM_HOME" \
            "${ZDM_HOME}/bin/zdmcli" query job 2>&1 | tee -a "$REPORT_FILE" || \
            log_info "No active ZDM jobs or zdmcli query not supported"
    else
        log_warn "ZDM_HOME not detected — skipping ZDM-specific checks"
    fi
} || log_error "ZDM installation section failed"

# ---------------------------------------------------------------------------
# SECTION 3: Java Configuration
# ---------------------------------------------------------------------------
log_section "Java Configuration"
{
    log_raw "JAVA_HOME: ${JAVA_HOME:-NOT SET}"
    if [ -n "${JAVA_HOME:-}" ]; then
        "${JAVA_HOME}/bin/java" -version 2>&1 | tee -a "$REPORT_FILE"
    elif command -v java &>/dev/null; then
        java -version 2>&1 | tee -a "$REPORT_FILE"
    else
        log_warn "java not found in PATH"
    fi
    log_raw "which java: $(which java 2>/dev/null || echo 'not found')"
} || log_error "Java configuration section failed"

JSON["java_version"]="$(java -version 2>&1 | head -1)"

# ---------------------------------------------------------------------------
# SECTION 4: OCI CLI Configuration
# ---------------------------------------------------------------------------
log_section "OCI CLI Configuration"
{
    log_raw "--- OCI CLI Version ---"
    oci --version 2>&1 | tee -a "$REPORT_FILE" || log_warn "oci CLI not found in PATH"

    log_raw "--- OCI Config File ---"
    for config_path in ~/.oci/config /home/zdmuser/.oci/config; do
        if [ -f "$config_path" ]; then
            log_raw "File: $config_path"
            cat "$config_path" 2>/dev/null | sed 's/key_file.*/key_file = [REDACTED]/' | tee -a "$REPORT_FILE"
        fi
    done

    log_raw "--- OCI API Key File Existence ---"
    for key_path in ~/.oci/oci_api_key.pem /home/zdmuser/.oci/oci_api_key.pem; do
        if [ -f "$key_path" ]; then
            log_raw "API key found: $key_path"
            ls -la "$key_path" | tee -a "$REPORT_FILE"
        fi
    done

    log_raw "--- OCI Connectivity Test ---"
    oci iam region list 2>&1 | head -10 | tee -a "$REPORT_FILE" || \
        log_warn "OCI connectivity test failed — check OCI CLI config and API key"
} || log_error "OCI CLI section failed"

# ---------------------------------------------------------------------------
# SECTION 5: SSH Configuration
# ---------------------------------------------------------------------------
log_section "SSH Configuration"
{
    log_raw "--- SSH keys for $(whoami) ---"
    ls -la ~/.ssh/ 2>/dev/null | tee -a "$REPORT_FILE" || log_warn "~/.ssh not found for $(whoami)"

    log_raw "--- SSH keys for $ZDM_USER ---"
    sudo -u "$ZDM_USER" ls -la ~/.ssh/ 2>/dev/null | tee -a "$REPORT_FILE" || \
        log_warn "~/.ssh not accessible for $ZDM_USER"

    log_raw "--- SSH public keys ---"
    for keyfile in ~/.ssh/*.pub ~/.ssh/id_rsa.pub ~/.ssh/id_ed25519.pub ~/.ssh/authorized_keys; do
        [ -f "$keyfile" ] && { log_raw "--- $keyfile ---"; cat "$keyfile" | tee -a "$REPORT_FILE"; }
    done
} || log_error "SSH configuration section failed"

# ---------------------------------------------------------------------------
# SECTION 6: Credential Files
# ---------------------------------------------------------------------------
log_section "Credential Files"
{
    log_raw "--- Searching for password/wallet files (names only, not contents) ---"
    sudo find /home /u01 /opt 2>/dev/null \
        \( -name "*.sso" -o -name "cwallet.sso" -o -name "ewallet.p12" \
        -o -name "*.wallet" -o -name "tnsnames.ora" -o -name "sqlnet.ora" \) \
        -type f 2>/dev/null | head -30 | tee -a "$REPORT_FILE"
} || log_error "Credential files section failed"

# ---------------------------------------------------------------------------
# SECTION 7: Network Configuration
# ---------------------------------------------------------------------------
log_section "Network Configuration"
{
    log_raw "--- IP addresses ---"
    ip addr show 2>/dev/null | tee -a "$REPORT_FILE"

    log_raw "--- Routing table ---"
    ip route show 2>/dev/null | tee -a "$REPORT_FILE" || route -n 2>/dev/null | tee -a "$REPORT_FILE"

    log_raw "--- DNS configuration ---"
    cat /etc/resolv.conf 2>/dev/null | tee -a "$REPORT_FILE"

    log_raw "--- /etc/hosts ---"
    cat /etc/hosts 2>/dev/null | tee -a "$REPORT_FILE"
} || log_error "Network configuration section failed"

# ---------------------------------------------------------------------------
# SECTION 8: Network Connectivity Tests (to Source and Target)
# ---------------------------------------------------------------------------
log_section "Network Connectivity Tests"
{
    SOURCE_HOST="${SOURCE_HOST:-}"
    TARGET_HOST="${TARGET_HOST:-}"

    if [ -z "$SOURCE_HOST" ] && [ -z "$TARGET_HOST" ]; then
        log_info "SOURCE_HOST and TARGET_HOST not provided — skipping connectivity tests"
    fi

    for host_var in SOURCE_HOST TARGET_HOST; do
        local host_val="${!host_var:-}"
        [ -z "$host_val" ] && { log_info "${host_var} not set — skipping"; continue; }

        log_raw "--- Connectivity to ${host_var}=${host_val} ---"

        # Ping test (10 packets, measure latency)
        log_raw "  Ping test (10 packets):"
        local ping_output
        ping_output=$(ping -c 10 "$host_val" 2>&1)
        local ping_rc=$?
        echo "$ping_output" | tee -a "$REPORT_FILE"
        if [ $ping_rc -eq 0 ]; then
            local avg_rtt
            avg_rtt=$(echo "$ping_output" | grep 'rtt\|round-trip' | grep -oP 'avg\s*=?\s*\K[\d.]+' | head -1)
            log_raw "  Ping result: SUCCESS (avg RTT ~${avg_rtt:-unknown} ms)"
            if [ -n "$avg_rtt" ] && awk "BEGIN{exit !($avg_rtt > 10) }"; then
                log_warn "  Average RTT to ${host_val} is ${avg_rtt}ms (> 10ms threshold — may impact ZDM online migration)"
            fi
        else
            log_warn "  Ping to ${host_val}: FAILED"
        fi

        # Port connectivity tests
        for port in 22 1521; do
            if timeout 5 bash -c "echo >/dev/tcp/${host_val}/${port}" 2>/dev/null; then
                log_raw "  Port ${port}: OPEN"
            else
                log_warn "  Port ${port} to ${host_val}: BLOCKED or unreachable"
            fi
        done
    done
} || log_error "Network connectivity section failed"

# ---------------------------------------------------------------------------
# SECTION 9: ZDM Logs
# ---------------------------------------------------------------------------
log_section "ZDM Logs"
{
    if [ -n "${ZDM_HOME:-}" ]; then
        log_raw "--- ZDM log directory ---"
        sudo -u "$ZDM_USER" ls -lt "${ZDM_HOME}/log/" 2>/dev/null | head -20 | tee -a "$REPORT_FILE" || \
            sudo ls -lt "${ZDM_HOME}/log/" 2>/dev/null | head -20 | tee -a "$REPORT_FILE" || \
            log_warn "Cannot list ZDM log directory"

        log_raw "--- Most recent ZDM log tail (last 50 lines) ---"
        local latest_log
        latest_log=$(sudo ls -t "${ZDM_HOME}/log/"*.log 2>/dev/null | head -1) || \
            latest_log=$(sudo -u "$ZDM_USER" ls -t "${ZDM_HOME}/log/"*.log 2>/dev/null | head -1) || true
        if [ -n "$latest_log" ]; then
            log_raw "Log file: $latest_log"
            sudo tail -50 "$latest_log" 2>/dev/null | tee -a "$REPORT_FILE" || \
                sudo -u "$ZDM_USER" tail -50 "$latest_log" 2>/dev/null | tee -a "$REPORT_FILE"
        else
            log_info "No ZDM log files found"
        fi
    else
        log_warn "ZDM_HOME not set — skipping ZDM log section"
    fi
} || log_error "ZDM logs section failed"

# ---------------------------------------------------------------------------
# Summary and JSON output
# ---------------------------------------------------------------------------
log_section "Discovery Summary"
log_raw "Errors:   ${#ERRORS[@]}"
for e in "${ERRORS[@]}"; do log_raw "  ERROR: $e"; done
log_raw "Warnings: ${#WARNINGS[@]}"
for w in "${WARNINGS[@]}"; do log_raw "  WARN:  $w"; done
log_raw "Completed at: $(date)"

JSON["zdm_detected"]="$( [ -n "${ZDM_HOME:-}" ] && echo 'true' || echo 'false' )"
JSON["error_count"]="${#ERRORS[@]}"
JSON["warning_count"]="${#WARNINGS[@]}"
JSON["completed_at"]="$(date -Iseconds 2>/dev/null || date)"

{
    echo "{"
    first=true
    for key in "${!JSON[@]}"; do
        val="${JSON[$key]}"
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

log_info "ZDM server discovery complete."
log_info "  Text: $REPORT_FILE"
log_info "  JSON: $JSON_FILE"
