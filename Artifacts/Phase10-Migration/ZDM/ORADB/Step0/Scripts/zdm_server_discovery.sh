#!/bin/bash
# =============================================================================
# zdm_server_discovery.sh
# ZDM Migration - ZDM Jumpbox Server Discovery Script
# Project: ORADB
#
# Purpose: Gather technical context from the ZDM jumpbox server.
#          Executed via SSH as ZDM_ADMIN_USER; ZDM CLI commands run as
#          ZDM_USER (zdmuser) via sudo following enterprise security patterns.
#
# Environment variables (passed by orchestration script):
#   SOURCE_HOST  - Source database hostname for connectivity testing
#   TARGET_HOST  - Target database hostname for connectivity testing
#   ZDM_USER     - ZDM software owner (default: zdmuser)
#   ORACLE_USER  - Oracle user (default: oracle)
#
# Usage: bash zdm_server_discovery.sh [-v] [-h]
#   -v  Verbose output
#   -h  Show usage
#
# Output:
#   ./zdm_server_discovery_<hostname>_<timestamp>.txt
#   ./zdm_server_discovery_<hostname>_<timestamp>.json
#
# NOTE: zdmcli does NOT support a -version flag. ZDM version is verified
#       by checking if zdmcli exists and runs without arguments.
# =============================================================================

# --- Do NOT use set -e; individual sections handle their own errors ---

# -----------------------------------------------------------------------
# Colour helpers
# -----------------------------------------------------------------------
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

VERBOSE=false
for arg in "$@"; do
    case "$arg" in
        -v|--verbose) VERBOSE=true ;;
        -h|--help)
            echo "Usage: $0 [-v] [-h]"
            echo "  -v  Verbose output"
            echo "  -h  Show this help"
            exit 0
            ;;
    esac
done

# -----------------------------------------------------------------------
# Output file setup
# -----------------------------------------------------------------------
HOSTNAME_SHORT=$(hostname -s 2>/dev/null || hostname)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="./zdm_server_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_server_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

# Default users (may be overridden by orchestration script environment)
ZDM_USER="${ZDM_USER:-zdmuser}"
ORACLE_USER="${ORACLE_USER:-oracle}"

# Hosts for connectivity tests (passed from orchestration script)
SOURCE_HOST="${SOURCE_HOST:-}"
TARGET_HOST="${TARGET_HOST:-}"

# -----------------------------------------------------------------------
# Logging functions
# -----------------------------------------------------------------------
log_info()    { echo -e "${GREEN}[INFO ]${RESET} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN ]${RESET} $*"; }
log_error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
log_debug()   { $VERBOSE && echo -e "${CYAN}[DEBUG]${RESET} $*" || true; }
log_section() { echo -e "\n${BOLD}${CYAN}=== $* ===${RESET}"; }
log_raw()     { echo "$*" >> "$REPORT_FILE"; }

# -----------------------------------------------------------------------
# Auto-detect ZDM environment
# -----------------------------------------------------------------------
detect_zdm_env() {
    if [ -n "${ZDM_HOME:-}" ] && [ -f "${ZDM_HOME}/bin/zdmcli" ]; then
        log_debug "ZDM_HOME already set and valid: $ZDM_HOME"
        return 0
    fi

    # Method 1: Get ZDM_HOME from zdmuser's login shell environment
    if id "$ZDM_USER" &>/dev/null; then
        local zdm_home_from_user
        zdm_home_from_user=$(sudo -u "$ZDM_USER" -i bash -c 'echo $ZDM_HOME' 2>/dev/null)
        if [ -n "$zdm_home_from_user" ] && [ -d "$zdm_home_from_user" ] && [ -f "$zdm_home_from_user/bin/zdmcli" ]; then
            export ZDM_HOME="$zdm_home_from_user"
            log_debug "Detected ZDM_HOME from zdmuser environment: $ZDM_HOME"
            return 0
        fi
    fi

    # Method 2: Check zdmuser's home directory
    if id "$ZDM_USER" &>/dev/null; then
        local zdm_user_home
        zdm_user_home=$(eval echo "~${ZDM_USER}" 2>/dev/null)
        if [ -n "$zdm_user_home" ]; then
            for subdir in zdmhome zdm app/zdmhome zdmbase/user_data/zdmhome; do
                local candidate="${zdm_user_home}/${subdir}"
                if sudo test -d "$candidate" 2>/dev/null && sudo test -f "$candidate/bin/zdmcli" 2>/dev/null; then
                    export ZDM_HOME="$candidate"
                    log_debug "Detected ZDM_HOME from zdmuser home: $ZDM_HOME"
                    return 0
                fi
            done
        fi
    fi

    # Method 3: Common system paths
    for p in /u01/app/zdmhome /u01/zdm /u01/app/zdm /opt/zdm /home/zdmuser/zdmhome \
              /home/zdmuser/zdm "$HOME/zdmhome" ~/zdm; do
        local p_expanded
        p_expanded=$(eval echo "$p" 2>/dev/null)
        if sudo test -d "$p_expanded" 2>/dev/null && sudo test -f "$p_expanded/bin/zdmcli" 2>/dev/null; then
            export ZDM_HOME="$p_expanded"
            log_debug "Detected ZDM_HOME from common path: $ZDM_HOME"
            return 0
        elif [ -d "$p_expanded" ] && [ -f "$p_expanded/bin/zdmcli" ]; then
            export ZDM_HOME="$p_expanded"
            log_debug "Detected ZDM_HOME from common path: $ZDM_HOME"
            return 0
        fi
    done

    # Method 4: Find zdmcli binary
    local zdmcli_path
    zdmcli_path=$(sudo find /u01 /opt /home -name "zdmcli" -type f 2>/dev/null | head -1)
    if [ -n "$zdmcli_path" ]; then
        export ZDM_HOME="$(dirname "$(dirname "$zdmcli_path")")"
        log_debug "Detected ZDM_HOME via find: $ZDM_HOME"
        return 0
    fi

    # Method 5: Check for ZDM bundled JDK as hint
    local jdk_path
    jdk_path=$(sudo find /u01 /opt /home -name "zdmcli" -maxdepth 8 2>/dev/null | head -1)
    if [ -n "$jdk_path" ]; then
        export ZDM_HOME="$(dirname "$(dirname "$jdk_path")")"
        return 0
    fi

    # Apply explicit override (highest priority)
    [ -n "${ZDM_HOME_OVERRIDE:-}" ] && export ZDM_HOME="$ZDM_HOME_OVERRIDE"

    log_warn "ZDM_HOME could not be detected"
    return 1
}

# -----------------------------------------------------------------------
# Auto-detect Java
# -----------------------------------------------------------------------
detect_java_env() {
    if [ -n "${JAVA_HOME:-}" ] && [ -f "${JAVA_HOME}/bin/java" ]; then
        return 0
    fi

    # Method 1: Check ZDM's bundled JDK
    if [ -n "${ZDM_HOME:-}" ] && [ -d "${ZDM_HOME}/jdk" ] && [ -f "${ZDM_HOME}/jdk/bin/java" ]; then
        export JAVA_HOME="${ZDM_HOME}/jdk"
        log_debug "Using ZDM bundled JDK: $JAVA_HOME"
        return 0
    fi

    # Method 2: alternatives
    if command -v java &>/dev/null; then
        local java_path
        java_path=$(readlink -f "$(command -v java)" 2>/dev/null)
        if [ -n "$java_path" ]; then
            export JAVA_HOME="${java_path%/bin/java}"
        fi
    fi

    # Method 3: common paths
    if [ -z "${JAVA_HOME:-}" ]; then
        for p in /usr/java/latest /usr/java/jdk* /usr/lib/jvm/java-* /opt/java/jdk*; do
            if [ -d "$p" ] && [ -f "$p/bin/java" ]; then
                export JAVA_HOME="$p"; break
            fi
        done
    fi

    [ -n "${JAVA_HOME_OVERRIDE:-}" ] && export JAVA_HOME="$JAVA_HOME_OVERRIDE"
}

# -----------------------------------------------------------------------
# Run ZDM CLI command as ZDM_USER
# -----------------------------------------------------------------------
run_zdm_cmd() {
    local zdm_args="$*"
    if [ -z "${ZDM_HOME:-}" ]; then
        echo "ERROR: ZDM_HOME not set"; return 1
    fi
    if [ "$(whoami)" = "$ZDM_USER" ]; then
        ${ZDM_HOME}/bin/zdmcli $zdm_args 2>&1
    else
        sudo -u "$ZDM_USER" -E ZDM_HOME="$ZDM_HOME" ${ZDM_HOME}/bin/zdmcli $zdm_args 2>&1
    fi
}

# -----------------------------------------------------------------------
# Header
# -----------------------------------------------------------------------
write_header() {
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S %Z')
    log_section "ZDM Server Discovery"
    {
        echo "========================================================================"
        echo "  ZDM Server Discovery Report"
        echo "  Project    : ORADB"
        echo "  Host       : $(hostname)"
        echo "  User       : $(whoami)"
        echo "  ZDM_USER   : $ZDM_USER"
        echo "  SOURCE_HOST: ${SOURCE_HOST:-NOT PROVIDED}"
        echo "  TARGET_HOST: ${TARGET_HOST:-NOT PROVIDED}"
        echo "  Started    : $ts"
        echo "========================================================================"
        echo ""
    } >> "$REPORT_FILE"
}

# -----------------------------------------------------------------------
# OS Information
# -----------------------------------------------------------------------
collect_os_info() {
    log_section "OS Information"
    log_raw ""
    log_raw "### OS INFORMATION ###"
    log_raw "Hostname    : $(hostname -f 2>/dev/null || hostname)"
    log_raw "Short host  : $(hostname -s 2>/dev/null || hostname)"
    log_raw "Date/Time   : $(date '+%Y-%m-%d %H:%M:%S %Z')"
    log_raw "Current user: $(whoami)"
    log_raw "User home   : $HOME"

    log_raw ""
    log_raw "--- IP Addresses ---"
    if command -v ip &>/dev/null; then
        ip addr show 2>/dev/null | grep 'inet ' | awk '{print "  " $2}' >> "$REPORT_FILE" || true
    else
        ifconfig 2>/dev/null | grep 'inet ' | awk '{print "  " $2}' >> "$REPORT_FILE" || true
    fi

    log_raw ""
    log_raw "--- OS Version ---"
    cat /etc/os-release 2>/dev/null >> "$REPORT_FILE" || uname -a >> "$REPORT_FILE" 2>/dev/null || true
    log_raw "Kernel: $(uname -r 2>/dev/null || echo UNKNOWN)"

    log_raw ""
    log_raw "--- Disk Space ---"
    log_raw "NOTE: ZDM_HOME and /tmp should have >= 50GB free (warning at < 50GB)"
    df -h 2>/dev/null | while IFS= read -r line; do
        echo "$line" >> "$REPORT_FILE"
        # Extract available GB and warn if < 50GB
        local available_g
        available_g=$(echo "$line" | awk '{print $4}' | grep -oE '[0-9]+' | head -1)
        local unit
        unit=$(echo "$line" | awk '{print $4}' | grep -oE '[A-Za-z]+' | head -1)
        if [[ "$unit" == "G" || "$unit" == "g" ]] && [ -n "$available_g" ] && [ "$available_g" -lt 50 ] 2>/dev/null; then
            echo "  WARNING: Low disk space on $(echo "$line" | awk '{print $6}') - only ${available_g}G available (< 50GB recommended)" >> "$REPORT_FILE"
        fi
    done 2>/dev/null || df -h >> "$REPORT_FILE" 2>/dev/null || true

    log_info "OS information collected"
}

# -----------------------------------------------------------------------
# ZDM Installation
# -----------------------------------------------------------------------
collect_zdm_installation() {
    log_section "ZDM Installation"
    log_raw ""
    log_raw "### ZDM INSTALLATION ###"

    detect_zdm_env

    log_raw "ZDM_HOME: ${ZDM_HOME:-NOT DETECTED}"
    log_raw ""

    if [ -z "${ZDM_HOME:-}" ]; then
        log_warn "ZDM_HOME not detected"
        log_raw "ERROR: ZDM_HOME could not be detected. Check ZDM installation."
        log_raw ""
        log_raw "Searched locations:"
        log_raw "  - zdmuser's login shell environment (sudo -u zdmuser -i bash -c 'echo \$ZDM_HOME')"
        log_raw "  - zdmuser's home directory subdirectories"
        log_raw "  - /u01/app/zdmhome, /u01/zdm, /u01/app/zdm, /opt/zdm"
        log_raw "  - find /u01 /opt /home -name zdmcli"
        log_raw ""
        log_raw "Override: set ZDM_HOME_OVERRIDE environment variable before running"
        return 1
    fi

    log_raw "--- ZDM CLI Check ---"
    if [ -f "${ZDM_HOME}/bin/zdmcli" ] && [ -x "${ZDM_HOME}/bin/zdmcli" ]; then
        log_raw "zdmcli found and executable: ${ZDM_HOME}/bin/zdmcli"
    else
        log_raw "ERROR: zdmcli not found or not executable at ${ZDM_HOME}/bin/zdmcli"
    fi

    log_raw ""
    log_raw "--- ZDM CLI Usage (no-args invocation for version verification) ---"
    run_zdm_cmd 2>&1 | head -20 >> "$REPORT_FILE" || log_raw "(zdmcli invocation failed)"

    log_raw ""
    log_raw "--- ZDM Response File Templates ---"
    if sudo test -d "${ZDM_HOME}/rhp/zdm/template" 2>/dev/null; then
        sudo ls -la "${ZDM_HOME}/rhp/zdm/template/" 2>/dev/null >> "$REPORT_FILE" || \
            ls -la "${ZDM_HOME}/rhp/zdm/template/" 2>/dev/null >> "$REPORT_FILE" || \
            log_raw "(could not list template directory)"
    else
        log_raw "(template directory not found at ${ZDM_HOME}/rhp/zdm/template)"
    fi

    log_raw ""
    log_raw "--- ZDM Service Status ---"
    if [ "$(whoami)" = "$ZDM_USER" ]; then
        "${ZDM_HOME}/bin/zdmservice" status 2>&1 >> "$REPORT_FILE" || log_raw "(zdmservice status failed)"
    else
        sudo -u "$ZDM_USER" -E ZDM_HOME="$ZDM_HOME" "${ZDM_HOME}/bin/zdmservice" status 2>&1 >> "$REPORT_FILE" || \
            log_raw "(zdmservice status failed - ensure sudo access to zdmuser)"
    fi

    log_raw ""
    log_raw "--- Active Migration Jobs ---"
    run_zdm_cmd query jobid ALL 2>&1 | head -50 >> "$REPORT_FILE" || log_raw "(could not query ZDM jobs)"

    log_info "ZDM installation info collected"
}

# -----------------------------------------------------------------------
# Java Configuration
# -----------------------------------------------------------------------
collect_java_info() {
    log_section "Java Configuration"
    log_raw ""
    log_raw "### JAVA CONFIGURATION ###"

    detect_java_env

    log_raw "JAVA_HOME: ${JAVA_HOME:-NOT DETECTED}"
    log_raw ""

    if [ -n "${JAVA_HOME:-}" ] && [ -f "${JAVA_HOME}/bin/java" ]; then
        log_raw "--- Java Version ---"
        "${JAVA_HOME}/bin/java" -version 2>&1 >> "$REPORT_FILE" || true
    elif command -v java &>/dev/null; then
        log_raw "--- System Java Version ---"
        java -version 2>&1 >> "$REPORT_FILE" || true
    else
        log_raw "WARNING: Java not found - ZDM requires Java"
    fi

    log_info "Java configuration collected"
}

# -----------------------------------------------------------------------
# OCI CLI Configuration
# -----------------------------------------------------------------------
collect_oci_config() {
    log_section "OCI CLI Configuration"
    log_raw ""
    log_raw "### OCI CLI CONFIGURATION ###"

    log_raw "--- OCI CLI Version ---"
    if command -v oci &>/dev/null; then
        oci --version 2>/dev/null >> "$REPORT_FILE" || log_raw "(oci --version failed)"
    else
        log_raw "OCI CLI not found in PATH"
        # Try sudo
        if sudo -u "$ZDM_USER" bash -c 'command -v oci' &>/dev/null 2>&1; then
            log_raw "OCI CLI found in zdmuser PATH"
            sudo -u "$ZDM_USER" oci --version 2>/dev/null >> "$REPORT_FILE" || true
        fi
    fi

    log_raw ""
    log_raw "--- OCI Config File ---"
    local oci_config="${OCI_CONFIG_PATH:-~/.oci/config}"
    local oci_config_expanded
    oci_config_expanded=$(eval echo "$oci_config")
    if [ -f "$oci_config_expanded" ]; then
        log_raw "Found: $oci_config_expanded"
        # Mask sensitive data
        sed 's/\(key_file\|fingerprint\|tenancy\|user\|pass_phrase\).*/\1 = ***MASKED***/' \
            "$oci_config_expanded" >> "$REPORT_FILE" 2>/dev/null || true
    else
        log_raw "(OCI config not found at $oci_config_expanded)"
        # Try zdmuser's OCI config
        local zdm_oci_config
        zdm_oci_config=$(eval echo "~${ZDM_USER}/.oci/config" 2>/dev/null)
        if sudo test -f "$zdm_oci_config" 2>/dev/null; then
            log_raw "Found zdmuser OCI config: $zdm_oci_config"
            sudo -u "$ZDM_USER" bash -c "sed 's/\(key_file\|fingerprint\|tenancy\|user\|pass_phrase\).*/\1 = ***MASKED***/' $zdm_oci_config" 2>/dev/null >> "$REPORT_FILE" || true
        fi
    fi

    log_raw ""
    log_raw "--- OCI API Key File Check ---"
    local oci_key="${OCI_PRIVATE_KEY_PATH:-~/.oci/oci_api_key.pem}"
    local oci_key_expanded
    oci_key_expanded=$(eval echo "$oci_key")
    if [ -f "$oci_key_expanded" ]; then
        log_raw "OCI API key found: $oci_key_expanded"
        log_raw "Permissions: $(stat -c '%a %U %G' "$oci_key_expanded" 2>/dev/null || ls -la "$oci_key_expanded" 2>/dev/null)"
    else
        log_raw "OCI API key NOT found at: $oci_key_expanded"
    fi

    log_raw ""
    log_raw "--- OCI Connectivity Test ---"
    if command -v oci &>/dev/null; then
        oci iam region list 2>&1 | head -5 >> "$REPORT_FILE" || log_raw "(OCI connectivity test failed)"
    else
        log_raw "(OCI CLI not available for connectivity test)"
    fi

    log_info "OCI CLI configuration collected"
}

# -----------------------------------------------------------------------
# SSH Configuration
# -----------------------------------------------------------------------
collect_ssh_info() {
    log_section "SSH Configuration"
    log_raw ""
    log_raw "### SSH CONFIGURATION ###"

    log_raw "--- Current User SSH Keys ---"
    log_raw "User: $(whoami)  Home: $HOME"
    if [ -d "$HOME/.ssh" ]; then
        ls -la "$HOME/.ssh/" 2>/dev/null >> "$REPORT_FILE" || true
        log_raw ""
        log_raw "Public keys:"
        for f in "$HOME/.ssh/"*.pub; do
            [ -f "$f" ] && { log_raw "  $f:"; cat "$f" >> "$REPORT_FILE" 2>/dev/null; } || true
        done
    else
        log_raw "(~/.ssh not found for current user)"
    fi

    log_raw ""
    log_raw "--- ZDM User ($ZDM_USER) SSH Keys ---"
    if id "$ZDM_USER" &>/dev/null; then
        sudo -u "$ZDM_USER" bash -c 'ls -la ~/.ssh/ 2>/dev/null && echo "---" && for f in ~/.ssh/*.pub; do [ -f "$f" ] && cat "$f"; done' 2>/dev/null >> "$REPORT_FILE" || \
            log_raw "(Could not access zdmuser SSH directory)"
    fi

    log_info "SSH configuration collected"
}

# -----------------------------------------------------------------------
# Credential Files
# -----------------------------------------------------------------------
collect_credential_files() {
    log_section "Credential Files"
    log_raw ""
    log_raw "### CREDENTIAL FILES ###"

    log_raw "NOTE: Searching for credential/password files (not showing content)"
    log_raw ""

    # Search for files that may contain credentials (names only)
    find /u01 /opt /home "$HOME" 2>/dev/null -name "*.pwd" -o -name "*password*" -o \
         -name "*passwd*" -o -name "*secret*" -o -name "*wallet*" -o \
         -name "*.p12" -o -name "*.jks" -o -name "*.wallet" 2>/dev/null | \
        grep -v '.git' | grep -v 'node_modules' | head -30 >> "$REPORT_FILE" 2>/dev/null || \
        log_raw "(search returned no results)"

    log_raw ""
    log_raw "--- ZDM Credential Store ---"
    if [ -n "${ZDM_HOME:-}" ]; then
        local zdm_cred_dir="${ZDM_HOME}/zdm/cred"
        if sudo test -d "$zdm_cred_dir" 2>/dev/null; then
            sudo ls -la "$zdm_cred_dir" 2>/dev/null >> "$REPORT_FILE" || \
                ls -la "$zdm_cred_dir" 2>/dev/null >> "$REPORT_FILE" || \
                log_raw "(could not list credential directory)"
        else
            log_raw "(ZDM credential directory not found at $zdm_cred_dir)"
        fi
    fi

    log_info "Credential files info collected"
}

# -----------------------------------------------------------------------
# Network Configuration
# -----------------------------------------------------------------------
collect_network_config() {
    log_section "Network Configuration"
    log_raw ""
    log_raw "### NETWORK CONFIGURATION ###"

    log_raw ""
    log_raw "--- IP Addresses ---"
    ip addr show 2>/dev/null | grep -E 'inet |link' | awk '{print "  " $0}' >> "$REPORT_FILE" || \
        ifconfig 2>/dev/null >> "$REPORT_FILE" || true

    log_raw ""
    log_raw "--- Routing Table ---"
    ip route show 2>/dev/null >> "$REPORT_FILE" || route -n 2>/dev/null >> "$REPORT_FILE" || true

    log_raw ""
    log_raw "--- DNS Configuration ---"
    cat /etc/resolv.conf 2>/dev/null >> "$REPORT_FILE" || log_raw "(resolv.conf not found)"
    log_raw ""
    cat /etc/hosts 2>/dev/null | grep -v '^#' | grep -v '^$' >> "$REPORT_FILE" || true

    log_info "Network configuration collected"
}

# -----------------------------------------------------------------------
# Network Connectivity Tests
# -----------------------------------------------------------------------
collect_connectivity_tests() {
    log_section "Network Connectivity Tests"
    log_raw ""
    log_raw "### NETWORK CONNECTIVITY TESTS ###"

    if [ -z "${SOURCE_HOST:-}" ] && [ -z "${TARGET_HOST:-}" ]; then
        log_warn "SOURCE_HOST and TARGET_HOST not provided - skipping connectivity tests"
        log_raw "SKIPPED: SOURCE_HOST and TARGET_HOST environment variables not set"
        log_raw "These are passed by the orchestration script automatically."
        return
    fi

    # Test a host
    test_host_connectivity() {
        local host="$1"
        local label="$2"

        log_raw ""
        log_raw "--- ${label} (${host}) ---"

        # Ping test with latency measurement
        log_raw "Ping test (10 packets):"
        local ping_output
        ping_output=$(ping -c 10 -W 5 "$host" 2>&1)
        local ping_exit=$?
        echo "$ping_output" >> "$REPORT_FILE"

        if [ $ping_exit -eq 0 ]; then
            # Extract avg RTT
            local avg_rtt
            avg_rtt=$(echo "$ping_output" | grep -oE 'rtt.*' | grep -oE '[0-9]+\.[0-9]+/[0-9]+\.[0-9]+/[0-9]+\.[0-9]+' | cut -d/ -f2 2>/dev/null || echo "")
            log_raw "Ping result: SUCCESS"
            if [ -n "$avg_rtt" ]; then
                log_raw "Average RTT: ${avg_rtt}ms"
                # Warn if avg RTT > 10ms
                local avg_int
                avg_int=$(echo "$avg_rtt" | cut -d. -f1 2>/dev/null || echo "0")
                if [ "$avg_int" -gt 10 ] 2>/dev/null; then
                    log_raw "WARNING: Average RTT ${avg_rtt}ms > 10ms threshold - may impact ZDM online migration performance"
                else
                    log_raw "OK: Average RTT ${avg_rtt}ms is within 10ms threshold"
                fi
            fi
        else
            log_raw "Ping result: FAILED - host may be unreachable or ICMP blocked"
        fi

        # Port connectivity tests
        log_raw ""
        log_raw "Port tests:"
        for port in 22 1521; do
            local port_result
            if timeout 5 bash -c "echo >/dev/tcp/${host}/${port}" 2>/dev/null; then
                log_raw "  Port ${port}: OPEN (SUCCESS)"
            else
                log_raw "  Port ${port}: FAILED (BLOCKED or unreachable)"
            fi
        done
    }

    if [ -n "${SOURCE_HOST:-}" ]; then
        test_host_connectivity "$SOURCE_HOST" "Source Database Server"
    else
        log_raw "SOURCE_HOST not provided - skipping source connectivity test"
    fi

    if [ -n "${TARGET_HOST:-}" ]; then
        test_host_connectivity "$TARGET_HOST" "Target Oracle Database@Azure"
    else
        log_raw "TARGET_HOST not provided - skipping target connectivity test"
    fi

    log_info "Connectivity tests completed"
}

# -----------------------------------------------------------------------
# ZDM Logs
# -----------------------------------------------------------------------
collect_zdm_logs() {
    log_section "ZDM Logs"
    log_raw ""
    log_raw "### ZDM LOGS ###"

    if [ -z "${ZDM_HOME:-}" ]; then
        log_raw "SKIPPED: ZDM_HOME not detected"; return
    fi

    # Find log directory
    local log_dirs=("${ZDM_HOME}/log" "${ZDM_HOME}/zdm/log" "/u01/app/zdmbase/zdm/log")
    for log_dir in "${log_dirs[@]}"; do
        if sudo test -d "$log_dir" 2>/dev/null || [ -d "$log_dir" ]; then
            log_raw "Log directory: $log_dir"
            log_raw ""
            log_raw "--- Recent Log Files ---"
            sudo ls -lth "$log_dir" 2>/dev/null | head -20 >> "$REPORT_FILE" || \
                ls -lth "$log_dir" 2>/dev/null | head -20 >> "$REPORT_FILE" || true

            log_raw ""
            log_raw "--- Last 50 lines of most recent log ---"
            local latest_log
            latest_log=$(sudo ls -t "$log_dir/"*.log 2>/dev/null | head -1 || ls -t "$log_dir/"*.log 2>/dev/null | head -1)
            if [ -n "$latest_log" ]; then
                log_raw "File: $latest_log"
                sudo tail -50 "$latest_log" 2>/dev/null >> "$REPORT_FILE" || \
                    tail -50 "$latest_log" 2>/dev/null >> "$REPORT_FILE" || true
            fi
            break
        fi
    done

    if [ ${#log_dirs[@]} -eq 0 ] || [ -z "$(ls -d "${log_dirs[@]}" 2>/dev/null)" ]; then
        log_raw "(ZDM log directory not found)"
    fi

    log_info "ZDM logs collected"
}

# -----------------------------------------------------------------------
# JSON Summary
# -----------------------------------------------------------------------
write_json_summary() {
    log_section "Writing JSON Summary"
    local hostname_f; hostname_f=$(hostname -f 2>/dev/null || hostname)
    local zdm_cli_found="false"
    local zdm_service_status="UNKNOWN"
    local oci_cli_ver="NOT_FOUND"
    local java_ver="NOT_FOUND"

    [ -n "${ZDM_HOME:-}" ] && [ -f "${ZDM_HOME}/bin/zdmcli" ] && zdm_cli_found="true"
    command -v oci &>/dev/null && oci_cli_ver=$(oci --version 2>/dev/null | head -1 || echo "ERROR")
    command -v java &>/dev/null && java_ver=$(java -version 2>&1 | head -1 || echo "ERROR")

    # Ping summaries
    local source_ping="SKIPPED"; local target_ping="SKIPPED"
    [ -n "${SOURCE_HOST:-}" ] && ping -c 1 -W 3 "$SOURCE_HOST" &>/dev/null && source_ping="SUCCESS" || \
        { [ -n "${SOURCE_HOST:-}" ] && source_ping="FAILED"; }
    [ -n "${TARGET_HOST:-}" ] && ping -c 1 -W 3 "$TARGET_HOST" &>/dev/null && target_ping="SUCCESS" || \
        { [ -n "${TARGET_HOST:-}" ] && target_ping="FAILED"; }

    cat > "$JSON_FILE" <<ENDJSON
{
  "discovery_type": "zdm_server",
  "project": "ORADB",
  "hostname": "${hostname_f}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "zdm": {
    "home": "${ZDM_HOME:-UNKNOWN}",
    "cli_found": ${zdm_cli_found},
    "service_status": "${zdm_service_status}",
    "user": "${ZDM_USER}"
  },
  "java": {
    "home": "${JAVA_HOME:-UNKNOWN}",
    "version": "${java_ver}"
  },
  "oci_cli_version": "${oci_cli_ver}",
  "connectivity": {
    "source_host": "${SOURCE_HOST:-NOT_PROVIDED}",
    "source_ping": "${source_ping}",
    "target_host": "${TARGET_HOST:-NOT_PROVIDED}",
    "target_ping": "${target_ping}"
  },
  "report_file": "$(basename "$REPORT_FILE")"
}
ENDJSON

    log_info "JSON summary written to $JSON_FILE"
}

# -----------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------
main() {
    > "$REPORT_FILE"

    write_header
    collect_os_info
    collect_zdm_installation
    collect_java_info
    collect_oci_config
    collect_ssh_info
    collect_credential_files
    collect_network_config
    collect_connectivity_tests
    collect_zdm_logs

    log_raw ""
    log_raw "========================================================================"
    log_raw "  Discovery completed: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    log_raw "========================================================================"

    write_json_summary

    log_section "Discovery Complete"
    log_info "Text report : $REPORT_FILE"
    log_info "JSON summary: $JSON_FILE"
    log_info "Orchestration script will collect these files."
}

main "$@"
