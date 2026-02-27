#!/bin/bash
# =============================================================================
# zdm_server_discovery.sh
# ZDM Server Discovery Script
# Project: ORADB  |  ZDM Host: 10.1.0.8
# Generated: 2026-02-27
#
# USAGE:
#   Via orchestration: Executed automatically by zdm_orchestrate_discovery.sh
#   Manual SSH:        ssh -i ~/.ssh/zdm.pem azureuser@10.1.0.8 \
#                        'SOURCE_HOST="10.1.0.11" TARGET_HOST="10.0.1.160" bash -l -s' \
#                        < zdm_server_discovery.sh
#   Local run:         SOURCE_HOST="10.1.0.11" TARGET_HOST="10.0.1.160" ./zdm_server_discovery.sh
#
# ENVIRONMENT VARIABLES (set by orchestration script):
#   SOURCE_HOST            - Source database hostname/IP (for connectivity tests)
#   TARGET_HOST            - Target database hostname/IP (for connectivity tests)
#   ZDM_USER               - ZDM software owner (default: zdmuser)
#   ZDM_HOME               - Override auto-detected ZDM_HOME
#   JAVA_HOME              - Override auto-detected JAVA_HOME
#
# ADDITIONAL REQUIREMENTS VERIFIED:
#   - Disk space for ZDM operations (minimum 25GB recommended)
#   - Network latency to source and target (detailed ping tests)
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
OUTPUT_TXT="./zdm_server_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
OUTPUT_JSON="./zdm_server_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

# --- ZDM User ---
ZDM_USER="${ZDM_USER:-zdmuser}"

# --- Connectivity test hosts (passed by orchestration script) ---
SOURCE_HOST="${SOURCE_HOST:-}"
TARGET_HOST="${TARGET_HOST:-}"

# Minimum recommended disk space for ZDM operations (GB)
ZDM_MIN_DISK_GB=25

# =============================================================================
# ENVIRONMENT DETECTION
# =============================================================================

detect_zdm_env() {
    log_info "Detecting ZDM environment..."

    # Apply explicit overrides (highest priority)
    [ -n "${ZDM_HOME_OVERRIDE:-}" ] && export ZDM_HOME="$ZDM_HOME_OVERRIDE"
    [ -n "${JAVA_HOME_OVERRIDE:-}" ] && export JAVA_HOME="$JAVA_HOME_OVERRIDE"

    if [ -n "${ZDM_HOME:-}" ] && [ -f "${ZDM_HOME}/bin/zdmcli" ]; then
        log_info "Using provided ZDM_HOME=$ZDM_HOME"
    else
        # Method 1: Get ZDM_HOME from zdmuser's login shell
        if id "$ZDM_USER" &>/dev/null; then
            local zdm_home_from_user
            zdm_home_from_user=$(sudo -u "$ZDM_USER" -i bash -c 'echo $ZDM_HOME' 2>/dev/null)
            if [ -n "$zdm_home_from_user" ] && [ -d "$zdm_home_from_user" ] && \
               [ -f "$zdm_home_from_user/bin/zdmcli" ]; then
                export ZDM_HOME="$zdm_home_from_user"
                log_info "Detected ZDM_HOME from zdmuser environment: $ZDM_HOME"
            fi
        fi

        # Method 2: Check zdmuser's home directory
        if [ -z "${ZDM_HOME:-}" ]; then
            local zdm_user_home
            zdm_user_home=$(eval echo ~${ZDM_USER} 2>/dev/null)
            if [ -n "$zdm_user_home" ]; then
                for subdir in zdmhome zdm app/zdmhome zdmbase/zdmhome; do
                    local candidate="$zdm_user_home/$subdir"
                    if sudo test -d "$candidate" 2>/dev/null && \
                       sudo test -f "$candidate/bin/zdmcli" 2>/dev/null; then
                        export ZDM_HOME="$candidate"
                        log_info "Detected ZDM_HOME from zdmuser home: $ZDM_HOME"
                        break
                    fi
                done
            fi
        fi

        # Method 3: Common system paths
        if [ -z "${ZDM_HOME:-}" ]; then
            for path in /u01/app/zdmhome /u01/zdm /u01/app/zdm /opt/zdm \
                        /home/zdmuser/zdmhome /u01/app/grid/zdmhome; do
                if sudo test -d "$path" 2>/dev/null && \
                   sudo test -f "$path/bin/zdmcli" 2>/dev/null; then
                    export ZDM_HOME="$path"
                    log_info "Detected ZDM_HOME from common path: $ZDM_HOME"
                    break
                elif [ -d "$path" ] && [ -f "$path/bin/zdmcli" ]; then
                    export ZDM_HOME="$path"
                    log_info "Detected ZDM_HOME: $ZDM_HOME"
                    break
                fi
            done
        fi

        # Method 4: Find zdmcli binary
        if [ -z "${ZDM_HOME:-}" ]; then
            local zdmcli_path
            zdmcli_path=$(sudo find /u01 /opt /home -name "zdmcli" -type f 2>/dev/null | head -1)
            if [ -n "$zdmcli_path" ]; then
                export ZDM_HOME="$(dirname "$(dirname "$zdmcli_path")")"
                log_info "Detected ZDM_HOME from zdmcli find: $ZDM_HOME"
            fi
        fi
    fi

    # Detect JAVA_HOME
    if [ -z "${JAVA_HOME:-}" ]; then
        # Method 1: ZDM's bundled JDK
        if [ -n "${ZDM_HOME:-}" ] && [ -d "${ZDM_HOME}/jdk" ]; then
            export JAVA_HOME="${ZDM_HOME}/jdk"
            log_info "Using ZDM bundled JDK: $JAVA_HOME"
        fi
        # Method 2: java alternatives
        if [ -z "${JAVA_HOME:-}" ] && command -v java &>/dev/null; then
            local java_real
            java_real=$(readlink -f "$(command -v java)" 2>/dev/null)
            if [ -n "$java_real" ]; then
                export JAVA_HOME="${java_real%/bin/java}"
            fi
        fi
        # Method 3: Common paths
        if [ -z "${JAVA_HOME:-}" ]; then
            for path in /usr/java/latest /usr/lib/jvm/java-11-openjdk* \
                        /usr/lib/jvm/java-8-openjdk* /opt/java/jdk*; do
                if [ -d "$path" ] && [ -f "$path/bin/java" ]; then
                    export JAVA_HOME="$path"
                    break
                fi
            done
        fi
    fi

    if [ -n "${ZDM_HOME:-}" ]; then
        log_info "ZDM_HOME:  $ZDM_HOME"
    else
        log_error "ZDM_HOME not detected. Set ZDM_HOME_OVERRIDE before running."
    fi
    log_info "ZDM_USER:  $ZDM_USER"
    log_info "JAVA_HOME: ${JAVA_HOME:-NOT DETECTED}"
}

# Run ZDM CLI as zdmuser
run_zdm_cmd() {
    local zdm_cmd="$1"
    shift
    if [ -z "${ZDM_HOME:-}" ]; then
        echo "  ERROR: ZDM_HOME not set - cannot run zdmcli"
        return 1
    fi
    if [ "$(whoami)" = "$ZDM_USER" ]; then
        "$ZDM_HOME/bin/$zdm_cmd" "$@" 2>&1
    else
        sudo -u "$ZDM_USER" -E ZDM_HOME="$ZDM_HOME" \
            JAVA_HOME="${JAVA_HOME:-}" \
            "$ZDM_HOME/bin/$zdm_cmd" "$@" 2>&1
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
    echo "Environment Variables:"
    echo "  SOURCE_HOST        Source DB hostname/IP for connectivity tests"
    echo "  TARGET_HOST        Target DB hostname/IP for connectivity tests"
    echo "  ZDM_USER           ZDM software owner (default: zdmuser)"
    echo "  ZDM_HOME_OVERRIDE  Override auto-detected ZDM_HOME"
    echo "  JAVA_HOME_OVERRIDE Override auto-detected JAVA_HOME"
    echo ""
    echo "Output files written to current directory:"
    echo "  zdm_server_discovery_<hostname>_<timestamp>.txt"
    echo "  zdm_server_discovery_<hostname>_<timestamp>.json"
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
    echo "  ZDM Server Discovery Report"
    echo "  Project: ORADB"
    echo "  Generated: $(date)"
    echo "  Host: $(hostname -f)"
    echo "================================================================"
    echo ""
    echo "Connectivity Test Targets:"
    echo "  SOURCE_HOST:  ${SOURCE_HOST:-NOT SET}"
    echo "  TARGET_HOST:  ${TARGET_HOST:-NOT SET}"
    echo ""

    detect_zdm_env

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
    echo "ZDM User:           $ZDM_USER"
    echo ""
    echo "--- OS Version ---"
    cat /etc/os-release 2>/dev/null \
        || cat /etc/redhat-release 2>/dev/null \
        || uname -a
    echo "Kernel:   $(uname -r)"
    echo "Arch:     $(uname -m)"

    # -----------------------------------------------------------------------
    # Section 2: ZDM Installation
    # -----------------------------------------------------------------------
    echo ""
    echo "================================================================"
    echo "  Section 2: ZDM Installation"
    echo "================================================================"
    echo "ZDM_HOME:   ${ZDM_HOME:-NOT DETECTED}"
    echo "ZDM_USER:   $ZDM_USER"
    echo ""

    echo "--- ZDM Binary Verification ---"
    if [ -n "${ZDM_HOME:-}" ]; then
        if sudo test -f "${ZDM_HOME}/bin/zdmcli" 2>/dev/null || \
           [ -f "${ZDM_HOME}/bin/zdmcli" ]; then
            echo "  zdmcli:    FOUND at $ZDM_HOME/bin/zdmcli"
            local zdmcli_perms
            zdmcli_perms=$(sudo ls -la "${ZDM_HOME}/bin/zdmcli" 2>/dev/null || \
                           ls -la "${ZDM_HOME}/bin/zdmcli" 2>/dev/null)
            echo "  Perms:     $zdmcli_perms"
        else
            echo "  zdmcli:    NOT FOUND at $ZDM_HOME/bin/zdmcli"
        fi

        echo ""
        echo "--- ZDM Response File Templates ---"
        sudo ls "${ZDM_HOME}/rhp/zdm/template/" 2>/dev/null \
            || ls "${ZDM_HOME}/rhp/zdm/template/" 2>/dev/null \
            || echo "  Templates not found at $ZDM_HOME/rhp/zdm/template/"

        echo ""
        echo "--- ZDM CLI (invoked without args to verify installation) ---"
        run_zdm_cmd "zdmcli" 2>&1 | head -30 || echo "  zdmcli invocation failed"
    else
        echo "  ZDM_HOME not detected - cannot verify ZDM installation"
    fi

    echo ""
    echo "--- ZDM Service Status ---"
    if command -v zdmservice &>/dev/null; then
        zdmservice status 2>&1 || echo "  zdmservice status failed"
    elif [ -n "${ZDM_HOME:-}" ] && sudo test -f "${ZDM_HOME}/bin/zdmservice" 2>/dev/null; then
        sudo -u "$ZDM_USER" "${ZDM_HOME}/bin/zdmservice" status 2>&1 \
            || "${ZDM_HOME}/bin/zdmservice" status 2>&1 \
            || echo "  zdmservice status failed"
    else
        echo "  zdmservice not found - checking systemd..."
        systemctl status zdm 2>/dev/null || \
        systemctl status zdmservice 2>/dev/null || \
        echo "  No zdm systemd service found"
    fi

    echo ""
    echo "--- Active Migration Jobs ---"
    if [ -n "${ZDM_HOME:-}" ]; then
        run_zdm_cmd "zdmcli" query job 2>&1 | head -50 \
            || echo "  Could not query ZDM jobs"
    fi

    # -----------------------------------------------------------------------
    # Section 3: Java Configuration
    # -----------------------------------------------------------------------
    echo ""
    echo "================================================================"
    echo "  Section 3: Java Configuration"
    echo "================================================================"
    echo "JAVA_HOME:   ${JAVA_HOME:-NOT DETECTED}"
    echo ""
    if [ -n "${JAVA_HOME:-}" ] && [ -f "${JAVA_HOME}/bin/java" ]; then
        echo "  Java version:"
        "${JAVA_HOME}/bin/java" -version 2>&1
    elif command -v java &>/dev/null; then
        echo "  Java version (from PATH):"
        java -version 2>&1
    else
        echo "  Java not found in JAVA_HOME or PATH"
    fi
    echo ""
    echo "  Java alternatives:"
    update-alternatives --list java 2>/dev/null || \
        ls /usr/lib/jvm/ 2>/dev/null || echo "  No alternatives found"

    # -----------------------------------------------------------------------
    # Section 4: OCI CLI Configuration
    # -----------------------------------------------------------------------
    echo ""
    echo "================================================================"
    echo "  Section 4: OCI CLI Configuration"
    echo "================================================================"
    echo "--- OCI CLI Version ---"
    if command -v oci &>/dev/null; then
        oci --version 2>&1
        echo ""
        echo "--- OCI Config File ---"
        local oci_config="${HOME}/.oci/config"
        if [ -f "$oci_config" ]; then
            echo "  Location: $oci_config"
            # Mask sensitive data
            grep -v '^\s*key_file\s*=' "$oci_config" | \
                sed 's/\(pass_phrase\s*=\s*\).*/\1***MASKED***/' | \
                sed 's/\(fingerprint\s*=\s*\).*/\1***SHOWN***/'
        else
            echo "  OCI config not found at $oci_config"
            find "$HOME" -name "config" -path "*/.oci/*" 2>/dev/null | head -3
        fi
        echo ""
        echo "--- OCI API Key File ---"
        if [ -f "$oci_config" ]; then
            local key_file
            key_file=$(grep 'key_file' "$oci_config" 2>/dev/null | head -1 | sed 's/.*=\s*//' | xargs)
            if [ -n "$key_file" ]; then
                key_file=$(eval echo "$key_file")
                if [ -f "$key_file" ]; then
                    echo "  API Key:  FOUND at $key_file"
                    ls -la "$key_file" 2>/dev/null
                else
                    echo "  API Key:  NOT FOUND at $key_file"
                fi
            fi
        fi
        echo ""
        echo "--- OCI Connectivity Test ---"
        oci iam region list --output table 2>&1 | head -20 \
            || echo "  OCI connectivity test failed"
    else
        echo "  OCI CLI not installed or not in PATH"
        echo "  Searching common locations..."
        for oci_path in /usr/local/bin/oci /usr/bin/oci "$HOME/bin/oci" \
                        "$HOME/.local/bin/oci"; do
            [ -f "$oci_path" ] && echo "  Found at: $oci_path"
        done
    fi

    # -----------------------------------------------------------------------
    # Section 5: SSH Configuration
    # -----------------------------------------------------------------------
    echo ""
    echo "================================================================"
    echo "  Section 5: SSH Configuration"
    echo "================================================================"
    echo "--- Current User SSH Keys ---"
    ls -la "${HOME}/.ssh/" 2>/dev/null || echo "  ~/.ssh not found"
    echo ""
    echo "--- ZDM User SSH Keys ---"
    local zdm_user_home
    zdm_user_home=$(eval echo ~${ZDM_USER} 2>/dev/null)
    sudo ls -la "${zdm_user_home}/.ssh/" 2>/dev/null \
        || echo "  Cannot read ${zdm_user_home}/.ssh/ (access denied or not found)"

    # -----------------------------------------------------------------------
    # Section 6: Credential Files
    # -----------------------------------------------------------------------
    echo ""
    echo "================================================================"
    echo "  Section 6: Credential Files"
    echo "================================================================"
    echo "--- Searching for Password / Credential Files ---"
    sudo find "${HOME}" "${zdm_user_home:-/home/zdmuser}" /u01 \
        -maxdepth 6 \
        \( -name "*.pwd" -o -name "*.password" -o -name "*.passwd" \
           -o -name "*.cred" -o -name "wallet*" -o -name "*wallet*" \
           -o -name "cwallet.sso" -o -name "ewallet.p12" \) \
        -type f 2>/dev/null | head -20 || \
        echo "  No credential files found or search not permitted"

    # -----------------------------------------------------------------------
    # Section 7: Network Configuration
    # -----------------------------------------------------------------------
    echo ""
    echo "================================================================"
    echo "  Section 7: Network Configuration"
    echo "================================================================"
    echo "--- IP Addresses ---"
    ip addr show 2>/dev/null | grep -E 'inet |inet6 ' | awk '{print "  "$2, $NF}' \
        || ifconfig 2>/dev/null | grep -E 'inet |inet addr:'
    echo ""
    echo "--- Routing Table ---"
    ip route show 2>/dev/null || route -n 2>/dev/null
    echo ""
    echo "--- DNS Configuration ---"
    cat /etc/resolv.conf 2>/dev/null || echo "  /etc/resolv.conf not found"

    # -----------------------------------------------------------------------
    # Section 8: ZDM Logs
    # -----------------------------------------------------------------------
    echo ""
    echo "================================================================"
    echo "  Section 8: ZDM Logs"
    echo "================================================================"
    if [ -n "${ZDM_HOME:-}" ]; then
        local log_dir="${ZDM_HOME}/log"
        echo "  Expected log directory: $log_dir"
        if sudo test -d "$log_dir" 2>/dev/null || [ -d "$log_dir" ]; then
            echo ""
            echo "--- Recent Log Files (last 5) ---"
            sudo find "$log_dir" -name "*.log" -type f 2>/dev/null | \
                sudo xargs ls -lt 2>/dev/null | head -10 \
                || find "$log_dir" -name "*.log" -type f | xargs ls -lt 2>/dev/null | head -10 \
                || echo "  No log files found"
        else
            echo "  Log directory not found at $log_dir"
            echo "  Searching for ZDM log files..."
            sudo find /u01 /home -name "*.log" -path "*zdm*" -type f 2>/dev/null | head -10 \
                || echo "  No ZDM log files found"
        fi
    else
        echo "  ZDM_HOME not detected - cannot locate log directory"
    fi

    # =======================================================================
    # ADDITIONAL DISCOVERY (Project-Specific Requirements)
    # =======================================================================

    # -----------------------------------------------------------------------
    # Section 9: Disk Space for ZDM Operations (Additional)
    # -----------------------------------------------------------------------
    echo ""
    echo "================================================================"
    echo "  Section 9: Disk Space for ZDM Operations (Additional)"
    echo "  Minimum recommended: ${ZDM_MIN_DISK_GB}GB"
    echo "================================================================"

    echo "--- Full Disk Usage (all filesystems) ---"
    df -hP 2>/dev/null || df -h
    echo ""

    echo "--- ZDM Home Disk Space ---"
    if [ -n "${ZDM_HOME:-}" ]; then
        echo "  Filesystem containing ZDM_HOME ($ZDM_HOME):"
        df -hP "$ZDM_HOME" 2>/dev/null || df -h "$ZDM_HOME" 2>/dev/null \
            || echo "  Cannot determine filesystem for $ZDM_HOME"
        echo ""
        echo "  ZDM_HOME directory size:"
        sudo du -sh "$ZDM_HOME" 2>/dev/null || du -sh "$ZDM_HOME" 2>/dev/null \
            || echo "  Cannot measure $ZDM_HOME size"
    else
        echo "  ZDM_HOME not detected"
    fi

    echo ""
    echo "--- Key Filesystem Free Space Assessment ---"
    # Check each mounted filesystem and flag those below threshold
    echo "  Threshold: ${ZDM_MIN_DISK_GB}GB minimum recommended for ZDM operations"
    echo ""
    echo "  MOUNT_POINT           TOTAL   USED    FREE    PCT   STATUS"
    echo "  -------------------------------------------------------------------"
    df -hP 2>/dev/null | tail -n +2 | while IFS= read -r line; do
        local mnt avail pct
        mnt=$(echo "$line" | awk '{print $NF}')
        avail=$(echo "$line" | awk '{print $4}')
        pct=$(echo "$line" | awk '{print $5}' | tr -d '%')
        # Only report relevant mount points (skip tmpfs, devtmpfs, etc.)
        local fstype
        fstype=$(echo "$line" | awk '{print $1}')
        case "$fstype" in
            tmpfs|devtmpfs|devfs|sysfs|proc|cgroup*|overlay) continue ;;
        esac
        local status="OK"
        [ "${pct:-0}" -ge 90 ] 2>/dev/null && status="WARNING: >90% full"
        printf "  %-22s %-7s %-7s %-7s %-5s%% %s\n" \
            "$mnt" \
            "$(echo "$line" | awk '{print $2}')" \
            "$(echo "$line" | awk '{print $3}')" \
            "$avail" \
            "${pct:-?}" \
            "$status"
    done

    echo ""
    echo "--- Checking ZDM-Relevant Paths for Min ${ZDM_MIN_DISK_GB}GB ---"
    check_path_space() {
        local path="$1"
        local label="$2"
        if [ -d "$path" ] || sudo test -d "$path" 2>/dev/null; then
            local free_kb
            free_kb=$(df -kP "$path" 2>/dev/null | tail -1 | awk '{print $4}')
            if [ -n "$free_kb" ]; then
                local free_gb
                free_gb=$(echo "scale=1; $free_kb / 1024 / 1024" | bc 2>/dev/null || \
                          awk "BEGIN{printf \"%.1f\", $free_kb/1024/1024}")
                local status="OK"
                local required_kb
                required_kb=$((ZDM_MIN_DISK_GB * 1024 * 1024))
                [ "$free_kb" -lt "$required_kb" ] 2>/dev/null && \
                    status="WARNING: Below ${ZDM_MIN_DISK_GB}GB minimum (${free_gb}GB free)"
                printf "  %-35s %sGB free  [%s]\n" "$label" "$free_gb" "$status"
            else
                echo "  $label: Cannot determine free space"
            fi
        else
            echo "  $label ($path): Path not found"
        fi
    }

    check_path_space "${ZDM_HOME:-/u01/app/zdmhome}"    "ZDM_HOME"
    check_path_space "/u01"                             "/u01 (typical ZDM partition)"
    check_path_space "/tmp"                             "/tmp"
    check_path_space "${HOME}"                          "Current user home"

    # -----------------------------------------------------------------------
    # Section 10: Network Connectivity with Latency Tests (Additional)
    # -----------------------------------------------------------------------
    echo ""
    echo "================================================================"
    echo "  Section 10: Network Connectivity and Latency Tests (Additional)"
    echo "================================================================"
    echo "  Source Host: ${SOURCE_HOST:-NOT SET}"
    echo "  Target Host: ${TARGET_HOST:-NOT SET}"
    echo ""

    test_host_connectivity() {
        local host="$1"
        local label="$2"

        if [ -z "$host" ]; then
            echo "  [$label] SKIPPED - host not provided"
            return
        fi

        echo "  --- $label ($host) ---"

        # Ping test - 10 packets for statistics
        echo "  Ping Test (10 packets):"
        if ping -c 10 -i 0.2 "$host" 2>/dev/null; then
            echo "    Ping Result: SUCCESS"
        else
            echo "    Ping Result: FAILED (ICMP may be blocked)"
        fi

        # Detailed ping stats
        echo ""
        echo "  Ping Statistics (5 packets with timestamps):"
        ping -c 5 -i 1 -D "$host" 2>/dev/null || \
            ping -c 5 -i 1 "$host" 2>/dev/null || \
            echo "    Ping failed - ICMP may be blocked by firewall"

        # Port connectivity tests
        echo ""
        echo "  Port Connectivity Tests:"
        for port in 22 1521 1522 2484; do
            local port_label
            case $port in
                22)   port_label="SSH" ;;
                1521) port_label="Oracle Listener" ;;
                1522) port_label="Oracle Listener Alt" ;;
                2484) port_label="Oracle SSL Listener" ;;
                *)    port_label="Port" ;;
            esac
            if timeout 5 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
                printf "    Port %-5s (%s): OPEN\n" "$port" "$port_label"
            else
                printf "    Port %-5s (%s): CLOSED or UNREACHABLE\n" "$port" "$port_label"
            fi
        done

        # Traceroute (limited hops)
        echo ""
        echo "  Network Path (traceroute, max 15 hops):"
        if command -v traceroute &>/dev/null; then
            traceroute -m 15 -w 3 "$host" 2>&1 | head -20
        elif command -v tracepath &>/dev/null; then
            tracepath -m 15 "$host" 2>&1 | head -20
        else
            echo "    traceroute/tracepath not available"
        fi

        # DNS resolution check
        echo ""
        echo "  DNS Resolution:"
        if nslookup "$host" 2>/dev/null | grep -E 'Address:|Name:'; then
            echo "    DNS: OK"
        elif host "$host" 2>/dev/null; then
            echo "    DNS: OK"
        else
            echo "    DNS: FAILED or host is IP address"
        fi

        echo ""
    }

    # Source connectivity with latency
    if [ -n "${SOURCE_HOST:-}" ]; then
        test_host_connectivity "$SOURCE_HOST" "Source Database Server"
    else
        echo "  SOURCE_HOST not set - skipping source connectivity tests"
        echo "  Set SOURCE_HOST environment variable to enable connectivity tests"
    fi

    # Target connectivity with latency
    if [ -n "${TARGET_HOST:-}" ]; then
        test_host_connectivity "$TARGET_HOST" "Target Oracle Database@Azure"
    else
        echo "  TARGET_HOST not set - skipping target connectivity tests"
        echo "  Set TARGET_HOST environment variable to enable connectivity tests"
    fi

    # Network latency summary
    echo ""
    echo "--- Latency Summary ---"
    if [ -n "${SOURCE_HOST:-}" ]; then
        local src_rtt
        src_rtt=$(ping -c 5 -q "$SOURCE_HOST" 2>/dev/null | grep 'rtt\|round-trip' | \
                  sed 's/.*= //' | sed 's/ ms//')
        echo "  Source  ($SOURCE_HOST): RTT = ${src_rtt:-FAILED (ICMP blocked or host unreachable)}"
    fi
    if [ -n "${TARGET_HOST:-}" ]; then
        local tgt_rtt
        tgt_rtt=$(ping -c 5 -q "$TARGET_HOST" 2>/dev/null | grep 'rtt\|round-trip' | \
                  sed 's/.*= //' | sed 's/ ms//')
        echo "  Target  ($TARGET_HOST): RTT = ${tgt_rtt:-FAILED (ICMP blocked or host unreachable)}"
    fi

    # =======================================================================
    # JSON SUMMARY
    # =======================================================================
    echo ""
    echo "================================================================"
    echo "  Discovery Summary"
    echo "================================================================"
    echo "Project:        ORADB"
    echo "Script:         zdm_server_discovery.sh"
    echo "Completed:      $(date)"
    echo "Host:           $(hostname -s)"
    echo "ZDM_HOME:       ${ZDM_HOME:-UNKNOWN}"
    echo "ZDM_USER:       $ZDM_USER"
    echo "JAVA_HOME:      ${JAVA_HOME:-UNKNOWN}"
    echo "Source Host:    ${SOURCE_HOST:-NOT SET}"
    echo "Target Host:    ${TARGET_HOST:-NOT SET}"
    echo "Output TXT:     $OUTPUT_TXT"
    echo "Output JSON:    $OUTPUT_JSON"

    cat > "$OUTPUT_JSON" <<EOJSON
{
  "discovery_type": "zdm_server",
  "project": "ORADB",
  "hostname": "$(hostname -s)",
  "timestamp": "$TIMESTAMP",
  "zdm": {
    "zdm_home": "${ZDM_HOME:-UNKNOWN}",
    "zdm_user": "$ZDM_USER",
    "java_home": "${JAVA_HOME:-UNKNOWN}"
  },
  "connectivity": {
    "source_host": "${SOURCE_HOST:-NOT SET}",
    "target_host": "${TARGET_HOST:-NOT SET}"
  },
  "additional_discovery": {
    "disk_space_check": "see txt report section 9 (min ${ZDM_MIN_DISK_GB}GB required)",
    "network_latency": "see txt report section 10"
  },
  "output_txt": "$OUTPUT_TXT"
}
EOJSON

    log_info "ZDM Server discovery complete."
    log_info "TXT Report:  $(pwd)/$OUTPUT_TXT"
    log_info "JSON Report: $(pwd)/$OUTPUT_JSON"
}

# =============================================================================
# ENTRY POINT
# =============================================================================

run_discovery 2>&1 | tee "$OUTPUT_TXT"
