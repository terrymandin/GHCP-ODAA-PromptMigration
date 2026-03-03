#!/bin/bash
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration
# ===================================================================================
# zdm_server_discovery.sh
# ZDM Migration - ZDM Jumpbox Server Discovery
# Project: ORADB
# ===================================================================================
# Purpose: Gather technical context from the ZDM jumpbox server.
#          ALL operations are strictly read-only.
#
# Usage:
#   chmod +x zdm_server_discovery.sh
#   ./zdm_server_discovery.sh
#
# Environment Variable Overrides (optional):
#   ZDM_HOME             - Override auto-detected ZDM_HOME
#   JAVA_HOME            - Override auto-detected JAVA_HOME
#   ZDM_USER             - ZDM software owner (default: zdmuser)
#   OCI_CONFIG_PATH      - Path to OCI config (default: ~/.oci/config)
#   SOURCE_HOST          - Source DB host for connectivity test (passed by orchestrator)
#   TARGET_HOST          - Target DB host for connectivity test (passed by orchestrator)
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
REPORT_FILE="./zdm_server_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_server_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

ZDM_USER="${ZDM_USER:-zdmuser}"
OCI_CONFIG_PATH="${OCI_CONFIG_PATH:-~/.oci/config}"
SOURCE_HOST="${SOURCE_HOST:-}"
TARGET_HOST="${TARGET_HOST:-}"
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
# Auto-detect ZDM and Java environment
# --------------------------------------------------------------------------
detect_zdm_env() {
    if [ -n "${ZDM_HOME:-}" ] && [ -f "${ZDM_HOME}/bin/zdmcli" ]; then
        log_info "Using pre-set ZDM_HOME=$ZDM_HOME"
    else
        log_info "Auto-detecting ZDM environment..."

        # Method 1: Get ZDM_HOME from zdmuser's login shell environment
        if id "$ZDM_USER" &>/dev/null; then
            local zdm_home_from_user
            zdm_home_from_user=$(sudo -u "$ZDM_USER" -i bash -c 'echo $ZDM_HOME' 2>/dev/null)
            if [ -n "$zdm_home_from_user" ] && [ -f "$zdm_home_from_user/bin/zdmcli" ]; then
                export ZDM_HOME="$zdm_home_from_user"
                log_info "Method 1: Detected ZDM_HOME=$ZDM_HOME from zdmuser environment"
            fi
        fi

        # Method 2: Check zdmuser's home directory
        if [ -z "${ZDM_HOME:-}" ]; then
            local zdm_user_home
            zdm_user_home=$(eval echo "~${ZDM_USER}" 2>/dev/null)
            if [ -n "$zdm_user_home" ]; then
                for subdir in zdmhome zdm app/zdmhome zdmbase/zdmhome; do
                    local candidate="$zdm_user_home/$subdir"
                    if sudo test -d "$candidate" 2>/dev/null && sudo test -f "$candidate/bin/zdmcli" 2>/dev/null; then
                        export ZDM_HOME="$candidate"
                        log_info "Method 2: Detected ZDM_HOME=$ZDM_HOME from zdmuser home"
                        break
                    fi
                done
            fi
        fi

        # Method 3: Check common ZDM system paths
        if [ -z "${ZDM_HOME:-}" ]; then
            for path in /u01/app/zdmhome /u01/zdm /u01/app/zdm /opt/zdm \
                        /home/zdmuser/zdmhome /home/zdmuser/zdm \
                        "$HOME/zdmhome" "$HOME/zdm"; do
                if sudo test -d "$path" 2>/dev/null && sudo test -f "$path/bin/zdmcli" 2>/dev/null; then
                    export ZDM_HOME="$path"
                    log_info "Method 3: Detected ZDM_HOME=$ZDM_HOME from common paths"
                    break
                elif [ -d "$path" ] && [ -f "$path/bin/zdmcli" ]; then
                    export ZDM_HOME="$path"
                    log_info "Method 3: Detected ZDM_HOME=$ZDM_HOME from common paths (direct)"
                    break
                fi
            done
        fi

        # Method 4: Search for zdmcli binary
        if [ -z "${ZDM_HOME:-}" ]; then
            local zdmcli_path
            zdmcli_path=$(sudo find /u01 /opt /home -name "zdmcli" -type f 2>/dev/null | head -1)
            if [ -n "$zdmcli_path" ]; then
                export ZDM_HOME="$(dirname "$(dirname "$zdmcli_path")")"
                log_info "Method 4: Detected ZDM_HOME=$ZDM_HOME from zdmcli binary search"
            fi
        fi
    fi

    # Detect JAVA_HOME
    if [ -z "${JAVA_HOME:-}" ]; then
        # Method 1: ZDM bundled JDK
        if [ -n "${ZDM_HOME:-}" ] && [ -d "${ZDM_HOME}/jdk" ]; then
            export JAVA_HOME="${ZDM_HOME}/jdk"
            log_info "Detected JAVA_HOME=$JAVA_HOME from ZDM bundled JDK"

        # Method 2: alternatives
        elif command -v java >/dev/null 2>&1; then
            local java_path
            java_path=$(readlink -f "$(command -v java)" 2>/dev/null)
            if [ -n "$java_path" ]; then
                export JAVA_HOME="${java_path%/bin/java}"
                log_info "Detected JAVA_HOME=$JAVA_HOME from alternatives"
            fi

        # Method 3: Common paths
        else
            for path in /usr/java/latest /usr/java/jdk* /usr/lib/jvm/java-* /opt/java/jdk*; do
                if [ -d "$path" ] && [ -f "$path/bin/java" ]; then
                    export JAVA_HOME="$path"
                    log_info "Detected JAVA_HOME=$JAVA_HOME from common paths"
                    break
                fi
            done
        fi
    fi

    # Apply explicit overrides
    [ -n "${ZDM_HOME_OVERRIDE:-}" ]  && export ZDM_HOME="$ZDM_HOME_OVERRIDE"
    [ -n "${JAVA_HOME_OVERRIDE:-}" ] && export JAVA_HOME="$JAVA_HOME_OVERRIDE"
}

# Run ZDM CLI as ZDM_USER
run_zdm_cmd() {
    local zdm_cmd="$1"
    if [ -z "${ZDM_HOME:-}" ]; then
        echo "ERROR: ZDM_HOME not set"
        return 1
    fi
    if [ "$(whoami)" = "$ZDM_USER" ]; then
        "$ZDM_HOME/bin/$zdm_cmd"
    else
        sudo -u "$ZDM_USER" -E ZDM_HOME="$ZDM_HOME" "$ZDM_HOME/bin/$zdm_cmd"
    fi
}

# --------------------------------------------------------------------------
# Section: OS Information
# --------------------------------------------------------------------------
discover_os_info() {
    log_section "OS Information"
    report_section "OS INFORMATION"

    local os_hostname os_ip os_version os_kernel current_user
    os_hostname=$(hostname -f 2>/dev/null || hostname)
    os_ip=$(hostname -I 2>/dev/null | tr ' ' ',')
    os_version=$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"' || uname -r)
    os_kernel=$(uname -r 2>/dev/null)
    current_user=$(whoami)

    report_kv "Hostname" "$os_hostname"
    report_kv "Current User" "$current_user"
    report_kv "IP Addresses" "$os_ip"
    report_kv "OS Version" "$os_version"
    report_kv "Kernel" "$os_kernel"

    if [ "$current_user" != "$ZDM_USER" ]; then
        log_warn "Running as '$current_user', not '$ZDM_USER'. ZDM CLI commands will use sudo."
        report_kv "WARNING" "Not running as $ZDM_USER - ZDM operations will use sudo"
    fi

    log_raw ""
    log_raw "  Disk Space (all mount points):"
    df -h 2>/dev/null | awk '{printf "    %s\n", $0}' >> "$REPORT_FILE"

    log_raw ""
    log_raw "  WARNING - Filesystems with < 50GB free:"
    df -h 2>/dev/null | awk 'NR>1 {
        avail_str = $4
        unit = substr(avail_str, length(avail_str))
        val = substr(avail_str, 1, length(avail_str)-1)+0
        if (unit=="G" && val < 50) printf "    WARNING: %s has only %s free\n", $6, $4
        if (unit=="M") printf "    WARNING: %s has only %s free (less than 1G)\n", $6, $4
    }' >> "$REPORT_FILE"

    JSON_DATA["hostname"]="$os_hostname"
    JSON_DATA["current_user"]="$current_user"
    JSON_DATA["ip_addresses"]="$os_ip"
    JSON_DATA["os_version"]="$os_version"
}

# --------------------------------------------------------------------------
# Section: ZDM Installation
# --------------------------------------------------------------------------
discover_zdm() {
    log_section "ZDM Installation"
    report_section "ZDM INSTALLATION"

    detect_zdm_env

    if [ -z "${ZDM_HOME:-}" ]; then
        log_warn "ZDM_HOME could not be detected"
        report_kv "ZDM_HOME" "NOT DETECTED"
        JSON_DATA["zdm_home"]="NOT DETECTED"
        JSON_DATA["zdm_installed"]="false"
        return
    fi

    report_kv "ZDM_HOME" "$ZDM_HOME"

    # Verify zdmcli binary
    if sudo test -f "$ZDM_HOME/bin/zdmcli" 2>/dev/null && sudo test -x "$ZDM_HOME/bin/zdmcli" 2>/dev/null; then
        report_kv "zdmcli Binary" "EXISTS and EXECUTABLE"
        JSON_DATA["zdm_installed"]="true"
    else
        report_kv "zdmcli Binary" "NOT FOUND or NOT EXECUTABLE"
        JSON_DATA["zdm_installed"]="false"
    fi

    # ZDM response file templates
    log_raw ""
    log_raw "  ZDM Response File Templates:"
    sudo find "$ZDM_HOME/rhp/zdm/template" -name "*.rsp" 2>/dev/null | \
        awk '{printf "    %s\n", $0}' >> "$REPORT_FILE" || \
        log_raw "    No templates found or path not accessible"

    # ZDM service status
    log_raw ""
    log_raw "  ZDM Service Status:"
    if id "$ZDM_USER" &>/dev/null; then
        sudo -u "$ZDM_USER" -E ZDM_HOME="$ZDM_HOME" "$ZDM_HOME/bin/zdmservice" status 2>/dev/null | \
            awk '{printf "    %s\n", $0}' >> "$REPORT_FILE" || \
            log_raw "    zdmservice status command failed"
    else
        log_raw "    $ZDM_USER user not found"
    fi

    # Verify ZDM CLI by running without arguments (shows usage if installed)
    log_raw ""
    log_raw "  ZDM CLI Help (installation verification):"
    if id "$ZDM_USER" &>/dev/null; then
        sudo -u "$ZDM_USER" -E ZDM_HOME="$ZDM_HOME" "$ZDM_HOME/bin/zdmcli" 2>&1 | \
            head -20 | awk '{printf "    %s\n", $0}' >> "$REPORT_FILE" || \
            log_raw "    zdmcli execution failed"
    fi

    # Active migration jobs
    log_raw ""
    log_raw "  Active Migration Jobs:"
    if id "$ZDM_USER" &>/dev/null; then
        sudo -u "$ZDM_USER" -E ZDM_HOME="$ZDM_HOME" "$ZDM_HOME/bin/zdmcli" query job 2>/dev/null | \
            awk '{printf "    %s\n", $0}' >> "$REPORT_FILE" || \
            log_raw "    zdmcli query job failed or no jobs"
    fi

    JSON_DATA["zdm_home"]="$ZDM_HOME"
    log_info "ZDM_HOME detected: $ZDM_HOME"
}

# --------------------------------------------------------------------------
# Section: Java Configuration
# --------------------------------------------------------------------------
discover_java() {
    log_section "Java Configuration"
    report_section "JAVA CONFIGURATION"

    if [ -n "${JAVA_HOME:-}" ]; then
        local java_version
        java_version=$("$JAVA_HOME/bin/java" -version 2>&1 | head -3)
        report_kv "JAVA_HOME" "$JAVA_HOME"
        log_raw ""
        log_raw "  Java Version:"
        echo "$java_version" | awk '{printf "    %s\n", $0}' >> "$REPORT_FILE"
        JSON_DATA["java_home"]="$JAVA_HOME"
    else
        log_warn "JAVA_HOME not detected"
        report_kv "JAVA_HOME" "NOT DETECTED"

        # Try system java anyway
        if command -v java >/dev/null 2>&1; then
            local java_version
            java_version=$(java -version 2>&1 | head -3)
            log_raw ""
            log_raw "  System Java (java -version):"
            echo "$java_version" | awk '{printf "    %s\n", $0}' >> "$REPORT_FILE"
        fi
        JSON_DATA["java_home"]="NOT DETECTED"
    fi
}

# --------------------------------------------------------------------------
# Section: OCI CLI Configuration
# --------------------------------------------------------------------------
discover_oci_cli() {
    log_section "OCI CLI Configuration"
    report_section "OCI CLI CONFIGURATION"

    local oci_version
    oci_version=$(oci --version 2>/dev/null || echo "NOT INSTALLED")
    report_kv "OCI CLI Version" "$oci_version"
    JSON_DATA["oci_cli_version"]="$oci_version"

    # OCI config
    local oci_config
    oci_config=$(eval echo "$OCI_CONFIG_PATH")
    if [ -f "$oci_config" ]; then
        log_raw ""
        log_raw "  OCI Config ($oci_config):"
        grep -v 'key_file\|private_key\|pass_phrase' "$oci_config" 2>/dev/null | \
            awk '{printf "    %s\n", $0}' >> "$REPORT_FILE"

        # Check for required fields
        local oci_region
        oci_region=$(grep '^region' "$oci_config" 2>/dev/null | head -1 | cut -d= -f2 | xargs)
        report_kv "OCI Region" "${oci_region:-NOT SET}"

        # Check API key
        local api_key_path
        api_key_path=$(grep 'key_file' "$oci_config" 2>/dev/null | head -1 | cut -d= -f2 | xargs)
        if [ -n "$api_key_path" ]; then
            api_key_path=$(eval echo "$api_key_path")
            if [ -f "$api_key_path" ]; then
                report_kv "OCI API Key" "EXISTS at $api_key_path"
                local key_perms
                key_perms=$(stat -c '%a' "$api_key_path" 2>/dev/null)
                report_kv "OCI API Key Perms" "${key_perms} (should be 600)"
            else
                report_kv "OCI API Key" "NOT FOUND at $api_key_path"
            fi
        fi
    else
        report_kv "OCI Config" "NOT FOUND at $oci_config"
    fi

    # OCI connectivity test
    log_raw ""
    log_raw "  OCI Connectivity Test (oci iam region list):"
    if command -v oci >/dev/null 2>&1; then
        if oci iam region list --output table 2>/dev/null | head -5 >> "$REPORT_FILE"; then
            JSON_DATA["oci_connectivity"]="OK"
            log_info "OCI connectivity: OK"
        else
            log_raw "    OCI connectivity test failed"
            JSON_DATA["oci_connectivity"]="FAILED"
        fi
    else
        log_raw "    OCI CLI not installed"
        JSON_DATA["oci_connectivity"]="NOT_INSTALLED"
    fi
}

# --------------------------------------------------------------------------
# Section: SSH Configuration
# --------------------------------------------------------------------------
discover_ssh() {
    log_section "SSH Configuration"
    report_section "SSH CONFIGURATION"

    local ssh_dir="$HOME/.ssh"
    log_raw "  SSH directory ($ssh_dir):"
    if [ -d "$ssh_dir" ]; then
        ls -la "$ssh_dir" 2>/dev/null | awk '{printf "    %s\n", $0}' >> "$REPORT_FILE"

        log_raw ""
        log_raw "  Available SSH Keys:"
        find "$ssh_dir" -name "*.pem" -o -name "*.key" -o -name "id_rsa" \
                        -o -name "id_ed25519" -o -name "id_ecdsa" 2>/dev/null | \
            while read -r key_file; do
                local perms
                perms=$(stat -c '%a' "$key_file" 2>/dev/null)
                printf "    %s (perms: %s)\n" "$key_file" "$perms" >> "$REPORT_FILE"
                [ "$perms" != "600" ] && \
                    printf "      WARNING: Key permissions should be 600, found %s\n" "$perms" >> "$REPORT_FILE"
            done
    else
        log_raw "    $ssh_dir not found"
        log_warn "SSH directory not found at $ssh_dir"
    fi

    # Check zdmuser SSH directory
    if [ "$(whoami)" != "$ZDM_USER" ]; then
        log_raw ""
        log_raw "  zdmuser SSH directory:"
        local zdm_ssh
        zdm_ssh=$(eval echo "~${ZDM_USER}/.ssh")
        sudo ls -la "$zdm_ssh" 2>/dev/null | awk '{printf "    %s\n", $0}' >> "$REPORT_FILE" || \
            log_raw "    Cannot access $zdm_ssh (sudo required or directory missing)"
    fi
}

# --------------------------------------------------------------------------
# Section: Credential Files
# --------------------------------------------------------------------------
discover_credentials() {
    log_section "Credential Files"
    report_section "CREDENTIAL FILES"

    log_raw "  Searching for credential/password files (names only, not contents):"
    find "$HOME" /home -maxdepth 4 \( -name "*.pwf" -o -name "*.wallet" \
        -o -name "*.p12" -o -name "*.jks" -o -name "*.sso" \
        -o -name "wallet" -o -name "cwallet.sso" -o -name "ewallet.p12" \) 2>/dev/null | \
        awk '{printf "    %s\n", $0}' >> "$REPORT_FILE"

    log_raw ""
    log_raw "  OCI Key Files:"
    find "$HOME" /home -maxdepth 5 -name "*.pem" 2>/dev/null | grep -i 'oci\|api' | \
        awk '{printf "    %s (existence confirmed, contents not shown)\n", $0}' >> "$REPORT_FILE"
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
    log_raw "  Routing Table:"
    ip route 2>/dev/null | awk '{printf "    %s\n", $0}' >> "$REPORT_FILE"

    log_raw ""
    log_raw "  DNS Configuration (/etc/resolv.conf):"
    cat /etc/resolv.conf 2>/dev/null | awk '{printf "    %s\n", $0}' >> "$REPORT_FILE"

    log_raw ""
    log_raw "  /etc/hosts (relevant entries):"
    grep -v '^#' /etc/hosts 2>/dev/null | grep -v '^$' | awk '{printf "    %s\n", $0}' >> "$REPORT_FILE"
}

# --------------------------------------------------------------------------
# Section: Network Connectivity Tests
# --------------------------------------------------------------------------
discover_connectivity() {
    log_section "Network Connectivity Tests"
    report_section "NETWORK CONNECTIVITY TESTS"

    if [ -z "$SOURCE_HOST" ] && [ -z "$TARGET_HOST" ]; then
        log_warn "SOURCE_HOST and TARGET_HOST not provided - skipping connectivity tests"
        log_raw "  SOURCE_HOST and TARGET_HOST env vars not set - tests skipped"
        log_raw "  (These should be passed by the orchestration script)"
        JSON_DATA["source_connectivity"]="SKIPPED"
        JSON_DATA["target_connectivity"]="SKIPPED"
        return
    fi

    test_host_connectivity() {
        local host="$1"
        local label="$2"
        local connectivity_result="FAILED"

        if [ -z "$host" ]; then
            log_raw "  $label: HOST NOT PROVIDED - skipping"
            echo "SKIPPED"
            return
        fi

        log_raw ""
        log_raw "  ---- $label ($host) ----"

        # Ping test with latency
        log_raw "  Ping test (10 packets):"
        local ping_output
        ping_output=$(ping -c 10 "$host" 2>&1)
        local ping_rc=$?
        echo "$ping_output" | awk '{printf "    %s\n", $0}' >> "$REPORT_FILE"

        if [ $ping_rc -eq 0 ]; then
            local avg_rtt
            avg_rtt=$(echo "$ping_output" | grep 'rtt\|round-trip' | awk -F'/' '{print $5}' | awk -F'.' '{print $1}')
            if [ -n "$avg_rtt" ] && [ "$avg_rtt" -gt 10 ] 2>/dev/null; then
                log_raw "    WARNING: Average RTT ${avg_rtt}ms > 10ms threshold"
                log_warn "$label ping avg RTT ${avg_rtt}ms (>10ms may impact online migration performance)"
            else
                log_raw "    Ping: SUCCESS (avg RTT ${avg_rtt:-?}ms)"
            fi
            connectivity_result="OK"
        else
            log_raw "    Ping: FAILED"
            log_warn "$label ping FAILED to $host"
            connectivity_result="PING_FAILED"
        fi

        # Port tests
        for port in 22 1521; do
            log_raw ""
            log_raw "  Port $port test:"
            if timeout 5 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
                log_raw "    Port $port: OPEN"
                log_info "$label port $port: OPEN"
            else
                log_raw "    Port $port: BLOCKED or unreachable"
                log_warn "$label port $port: BLOCKED or unreachable on $host"
                [ "$connectivity_result" = "OK" ] && connectivity_result="PORT_BLOCKED"
            fi
        done

        echo "$connectivity_result"
    }

    local src_result tgt_result
    src_result=$(test_host_connectivity "$SOURCE_HOST" "Source DB")
    tgt_result=$(test_host_connectivity "$TARGET_HOST" "Target DB (ODAA)")

    JSON_DATA["source_connectivity"]="${src_result:-SKIPPED}"
    JSON_DATA["target_connectivity"]="${tgt_result:-SKIPPED}"
    log_info "Source connectivity: ${src_result:-SKIPPED}"
    log_info "Target connectivity: ${tgt_result:-SKIPPED}"
}

# --------------------------------------------------------------------------
# Section: ZDM Logs
# --------------------------------------------------------------------------
discover_zdm_logs() {
    log_section "ZDM Logs"
    report_section "ZDM LOGS"

    if [ -z "${ZDM_HOME:-}" ]; then
        log_raw "  ZDM_HOME not set - cannot locate logs"
        return
    fi

    # Common ZDM log locations
    local log_dirs=(
        "$ZDM_HOME/log"
        "$ZDM_HOME/zdm/log"
        "${ORACLE_BASE:-/u01/app/oracle}/diag/zdm"
        "/home/$ZDM_USER/zdmbase/zdm/log"
        "/u01/zdmbase/zdm/log"
    )

    for log_dir in "${log_dirs[@]}"; do
        if sudo test -d "$log_dir" 2>/dev/null; then
            report_kv "Log Directory Found" "$log_dir"
            log_raw ""
            log_raw "  Recent log files in $log_dir:"
            sudo find "$log_dir" -name "*.log" -newer /tmp -type f 2>/dev/null | \
                head -10 | awk '{printf "    %s\n", $0}' >> "$REPORT_FILE"
            log_raw ""
            log_raw "  Latest log snippet (last 20 lines):"
            local latest_log
            latest_log=$(sudo find "$log_dir" -name "*.log" -type f 2>/dev/null | \
                xargs ls -t 2>/dev/null | head -1)
            if [ -n "$latest_log" ]; then
                sudo tail -20 "$latest_log" 2>/dev/null | awk '{printf "    %s\n", $0}' >> "$REPORT_FILE"
            fi
            JSON_DATA["zdm_log_dir"]="$log_dir"
            return
        fi
    done

    log_raw "  No ZDM log directory found in known locations"
}

# --------------------------------------------------------------------------
# Write JSON summary
# --------------------------------------------------------------------------
write_json_summary() {
    log_section "Writing JSON Summary"

    cat > "$JSON_FILE" <<ENDJSON
{
  "discovery_type": "zdm_server",
  "project": "ORADB",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hostname": "${JSON_DATA[hostname]:-}",
  "current_user": "${JSON_DATA[current_user]:-}",
  "ip_addresses": "${JSON_DATA[ip_addresses]:-}",
  "os_version": "${JSON_DATA[os_version]:-}",
  "zdm_home": "${JSON_DATA[zdm_home]:-}",
  "zdm_installed": "${JSON_DATA[zdm_installed]:-false}",
  "java_home": "${JSON_DATA[java_home]:-}",
  "oci_cli_version": "${JSON_DATA[oci_cli_version]:-}",
  "oci_connectivity": "${JSON_DATA[oci_connectivity]:-}",
  "source_connectivity": "${JSON_DATA[source_connectivity]:-}",
  "target_connectivity": "${JSON_DATA[target_connectivity]:-}",
  "zdm_log_dir": "${JSON_DATA[zdm_log_dir]:-}",
  "source_host_tested": "${SOURCE_HOST:-}",
  "target_host_tested": "${TARGET_HOST:-}",
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
    echo "  ZDM Server Discovery"
    echo "  Project: ORADB"
    echo "  Server:  $(hostname)"
    echo "  Date:    $(date)"
    echo "  Running as: $(whoami)"
    [ -n "$SOURCE_HOST" ] && echo "  Source Host: $SOURCE_HOST"
    [ -n "$TARGET_HOST" ] && echo "  Target Host: $TARGET_HOST"
    echo "============================================================"
    echo -e "${NC}"

    # Initialize report
    cat > "$REPORT_FILE" <<EOHEADER
==================================================================
ZDM SERVER DISCOVERY REPORT
Project:   ORADB
Server:    $(hostname -f 2>/dev/null || hostname)
User:      $(whoami)
Date:      $(date)
Script:    $0
SOURCE_HOST: ${SOURCE_HOST:-NOT SET}
TARGET_HOST: ${TARGET_HOST:-NOT SET}
==================================================================
EOHEADER

    discover_os_info       || log_error "OS info discovery failed"
    discover_zdm           || log_error "ZDM discovery failed"
    discover_java          || log_error "Java discovery failed"
    discover_oci_cli       || log_error "OCI CLI discovery failed"
    discover_ssh           || log_error "SSH discovery failed"
    discover_credentials   || log_error "Credentials discovery failed"
    discover_network       || log_error "Network discovery failed"
    discover_connectivity  || log_error "Connectivity tests failed"
    discover_zdm_logs      || log_error "ZDM logs discovery failed"

    write_json_summary

    log_raw ""
    log_raw "=================================================================="
    log_raw "END OF ZDM SERVER DISCOVERY REPORT"
    log_raw "Generated: $(date)"
    log_raw "=================================================================="

    echo ""
    log_info "Discovery complete."
    log_info "Text report: $REPORT_FILE"
    log_info "JSON summary: $JSON_FILE"
}

main "$@"
