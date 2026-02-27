#!/bin/bash
# =============================================================================
# ZDM Server Discovery Script
# Project: ORADB
# Generated for: Oracle ZDM Migration - Step 0
#
# Purpose: Discover ZDM jumpbox server configuration for migration planning.
# Run as: SSH as ZDM_ADMIN_USER (azureuser), ZDM CLI runs via sudo -u zdmuser
#
# Usage: ./zdm_server_discovery.sh
#   Environment variables (passed from orchestration script):
#     SOURCE_HOST   - Source database hostname for connectivity testing
#     TARGET_HOST   - Target database hostname for connectivity testing
#     ZDM_USER      - ZDM software owner (default: zdmuser)
#
# Output: ./zdm_server_discovery_<hostname>_<timestamp>.txt
#         ./zdm_server_discovery_<hostname>_<timestamp>.json
# =============================================================================

set -o nounset
set -o pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================
ZDM_USER="${ZDM_USER:-zdmuser}"
ZDM_HOME="${ZDM_HOME:-}"
JAVA_HOME="${JAVA_HOME:-}"
SOURCE_HOST="${SOURCE_HOST:-}"
TARGET_HOST="${TARGET_HOST:-}"

# =============================================================================
# COLORS & LOGGING
# =============================================================================
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname)"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_TEXT="./zdm_server_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
OUTPUT_JSON="./zdm_server_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

log_info()    { echo -e "${GREEN}[INFO]${NC}  $*" | tee -a "$OUTPUT_TEXT"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*" | tee -a "$OUTPUT_TEXT"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" | tee -a "$OUTPUT_TEXT"; }
log_section() {
    local line="========================================================================"
    echo -e "\n${CYAN}${line}${NC}" | tee -a "$OUTPUT_TEXT"
    echo -e "${CYAN}  $*${NC}" | tee -a "$OUTPUT_TEXT"
    echo -e "${CYAN}${line}${NC}" | tee -a "$OUTPUT_TEXT"
}
log_raw() { echo "$*" | tee -a "$OUTPUT_TEXT"; }

# =============================================================================
# ZDM AUTO-DETECTION
# =============================================================================
detect_zdm_env() {
    if [ -n "${ZDM_HOME:-}" ] && [ -f "${ZDM_HOME}/bin/zdmcli" ]; then
        log_info "Using pre-set ZDM_HOME=$ZDM_HOME"
        return 0
    fi

    local zdm_user="$ZDM_USER"

    # Method 1: Get ZDM_HOME from zdmuser's login shell environment
    if id "$zdm_user" &>/dev/null; then
        local zdm_home_from_user
        zdm_home_from_user=$(sudo -u "$zdm_user" -i bash -c 'echo $ZDM_HOME' 2>/dev/null)
        if [ -n "$zdm_home_from_user" ] && sudo test -d "$zdm_home_from_user" 2>/dev/null && \
           sudo test -f "$zdm_home_from_user/bin/zdmcli" 2>/dev/null; then
            ZDM_HOME="$zdm_home_from_user"
            log_info "ZDM_HOME detected via zdmuser env: $ZDM_HOME"
            export ZDM_HOME
            return 0
        fi
    fi

    # Method 2: Check zdmuser's home directory for common ZDM paths
    local zdm_user_home
    zdm_user_home=$(eval echo "~$zdm_user" 2>/dev/null)
    if [ -n "$zdm_user_home" ]; then
        for subdir in zdmhome zdm app/zdmhome zdmsoftware; do
            local candidate="$zdm_user_home/$subdir"
            if sudo test -d "$candidate" 2>/dev/null && sudo test -f "$candidate/bin/zdmcli" 2>/dev/null; then
                ZDM_HOME="$candidate"
                log_info "ZDM_HOME detected via zdmuser home: $ZDM_HOME"
                export ZDM_HOME
                return 0
            fi
        done
    fi

    # Method 3: Common system-wide ZDM installation paths
    for path in /u01/app/zdmhome /u01/zdm /u01/app/zdm /opt/zdm \
                /home/zdmuser/zdmhome /home/zdmuser/zdm ~/zdmhome ~/zdm \
                "$HOME/zdmhome" "$HOME/zdm"; do
        if [ -d "$path" ] && [ -f "$path/bin/zdmcli" ]; then
            ZDM_HOME="$path"
            log_info "ZDM_HOME detected via known path: $ZDM_HOME"
            export ZDM_HOME
            return 0
        elif sudo test -d "$path" 2>/dev/null && sudo test -f "$path/bin/zdmcli" 2>/dev/null; then
            ZDM_HOME="$path"
            log_info "ZDM_HOME detected via known path (sudo): $ZDM_HOME"
            export ZDM_HOME
            return 0
        fi
    done

    # Method 4: Search for zdmcli binary
    local zdmcli_path
    zdmcli_path=$(sudo find /u01 /u02 /opt /home -name "zdmcli" -type f 2>/dev/null | head -1)
    if [ -n "$zdmcli_path" ]; then
        ZDM_HOME="$(dirname "$(dirname "$zdmcli_path")")"
        log_info "ZDM_HOME detected via binary search: $ZDM_HOME"
        export ZDM_HOME
        return 0
    fi

    # Method 5: Check for ZDM bundled JDK as indicator
    for path in /u01/app/zdmhome/jdk /u01/zdm/jdk; do
        if [ -d "$path" ]; then
            ZDM_HOME="${path%/jdk}"
            [ -f "$ZDM_HOME/bin/zdmcli" ] && { log_info "ZDM_HOME via JDK hint: $ZDM_HOME"; export ZDM_HOME; return 0; }
        fi
    done

    log_warn "ZDM_HOME could not be auto-detected. Set ZDM_REMOTE_ZDM_HOME override if needed."

    # Apply explicit override
    [ -n "${ZDM_REMOTE_ZDM_HOME:-}" ] && ZDM_HOME="$ZDM_REMOTE_ZDM_HOME" && export ZDM_HOME
}

detect_java_env() {
    if [ -n "${JAVA_HOME:-}" ] && [ -f "${JAVA_HOME}/bin/java" ]; then
        return 0
    fi

    # Method 1: ZDM bundled JDK
    if [ -n "${ZDM_HOME:-}" ] && [ -d "${ZDM_HOME}/jdk" ] && [ -f "${ZDM_HOME}/jdk/bin/java" ]; then
        JAVA_HOME="${ZDM_HOME}/jdk"
        export JAVA_HOME
        return 0
    fi

    # Method 2: java alternatives
    if command -v java >/dev/null 2>&1; then
        local java_path
        java_path=$(readlink -f "$(command -v java)" 2>/dev/null)
        if [ -n "$java_path" ]; then
            JAVA_HOME="${java_path%/bin/java}"
            export JAVA_HOME
            return 0
        fi
    fi

    # Method 3: Common paths
    for path in /usr/java/latest /usr/java/jdk* /usr/lib/jvm/java-* /opt/java/jdk*; do
        if [ -d "$path" ] && [ -f "$path/bin/java" ]; then
            JAVA_HOME="$path"
            export JAVA_HOME
            return 0
        fi
    done

    # Apply explicit override
    [ -n "${ZDM_REMOTE_JAVA_HOME:-}" ] && JAVA_HOME="$ZDM_REMOTE_JAVA_HOME" && export JAVA_HOME
}

# Run ZDM CLI command as zdmuser
run_zdm_cmd() {
    local zdm_cmd="$1"
    if [ -z "${ZDM_HOME:-}" ]; then
        echo "ERROR: ZDM_HOME not set"
        return 1
    fi
    if [ "$(whoami)" = "$ZDM_USER" ]; then
        "$ZDM_HOME/bin/$zdm_cmd" 2>&1
    else
        sudo -u "$ZDM_USER" -E env ZDM_HOME="$ZDM_HOME" "$ZDM_HOME/bin/$zdm_cmd" 2>&1
    fi
}

# =============================================================================
# JSON BUILDER
# =============================================================================
JSON_SECTIONS=()
json_add() {
    local key="$1"
    local val="$2"
    local escaped
    escaped=$(printf '%s' "$val" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\r')
    JSON_SECTIONS+=("  \"${key}\": \"${escaped}\"")
}

# =============================================================================
# DISCOVERY SECTIONS
# =============================================================================

discover_os() {
    log_section "OS INFORMATION"
    log_raw "Hostname:       $(hostname -f 2>/dev/null || hostname)"
    log_raw "Short hostname: ${HOSTNAME_SHORT}"
    log_raw "Current user:   $(whoami)"
    log_raw "OS version:"
    cat /etc/os-release 2>/dev/null | tee -a "$OUTPUT_TEXT" || true
    log_raw "Kernel: $(uname -r)"

    log_raw "--- Disk Space (all mount points) ---"
    df -h 2>/dev/null | tee -a "$OUTPUT_TEXT" || true

    # Warn on low disk space (< 50GB free is WARNING; report any < 25GB as ERROR)
    while read -r fs size used avail pct mp; do
        [[ "$fs" == "Filesystem" ]] && continue
        local avail_num="${avail//[^0-9.]/}"
        local avail_unit="${avail//[0-9.]/}"
        local avail_gb=0
        case "$avail_unit" in
            G) avail_gb=$(printf '%.0f' "$avail_num") ;;
            T) avail_gb=$(awk "BEGIN{printf \"%.0f\", $avail_num * 1024}") ;;
            M) avail_gb=0 ;;
        esac
        if [ "$avail_gb" -lt 25 ] 2>/dev/null; then
            log_error "LOW DISK: $mp has only ${avail} free (< 25GB threshold)"
        elif [ "$avail_gb" -lt 50 ] 2>/dev/null; then
            log_warn "DISK WARNING: $mp has ${avail} free (< 50GB recommended for ZDM)"
        fi
    done < <(df -h 2>/dev/null)

    json_add "hostname" "$(hostname -f 2>/dev/null || hostname)"
    json_add "os_version" "$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2)"
}

discover_zdm() {
    log_section "ZDM INSTALLATION"
    log_raw "ZDM_HOME:  ${ZDM_HOME:-NOT DETECTED}"
    log_raw "ZDM_USER:  $ZDM_USER"

    if [ -z "${ZDM_HOME:-}" ]; then
        log_error "ZDM_HOME could not be detected. ZDM may not be installed or accessible."
        json_add "zdm_installed" "UNKNOWN"
        return
    fi

    # Verify zdmcli exists and is executable
    if sudo test -x "${ZDM_HOME}/bin/zdmcli" 2>/dev/null; then
        log_info "zdmcli found and executable at: ${ZDM_HOME}/bin/zdmcli"
        json_add "zdm_installed" "YES"
    else
        log_error "zdmcli NOT found or NOT executable at: ${ZDM_HOME}/bin/zdmcli"
        json_add "zdm_installed" "NO"
    fi

    # ZDM installation verification (run zdmcli without args to show usage)
    log_raw "--- ZDM CLI Verification (usage output) ---"
    if [ "$(whoami)" = "$ZDM_USER" ]; then
        timeout 10 "$ZDM_HOME/bin/zdmcli" 2>&1 | head -20 | tee -a "$OUTPUT_TEXT" || true
    else
        sudo -u "$ZDM_USER" -E env ZDM_HOME="$ZDM_HOME" timeout 10 "$ZDM_HOME/bin/zdmcli" 2>&1 | head -20 | tee -a "$OUTPUT_TEXT" || true
    fi

    # ZDM service status
    log_raw "--- ZDM Service Status ---"
    if [ "$(whoami)" = "$ZDM_USER" ]; then
        "$ZDM_HOME/bin/zdmservice" status 2>&1 | tee -a "$OUTPUT_TEXT" || log_warn "zdmservice status failed"
    else
        sudo -u "$ZDM_USER" -E env ZDM_HOME="$ZDM_HOME" "$ZDM_HOME/bin/zdmservice" status 2>&1 | tee -a "$OUTPUT_TEXT" || log_warn "zdmservice status failed"
    fi

    # Active migration jobs
    log_raw "--- Active Migration Jobs ---"
    run_zdm_cmd "zdmcli query job" 2>&1 | tee -a "$OUTPUT_TEXT" || log_warn "Could not query ZDM jobs"

    # Check for response file templates
    log_raw "--- ZDM Response File Templates ---"
    if sudo test -d "${ZDM_HOME}/rhp/zdm/template" 2>/dev/null; then
        sudo ls "${ZDM_HOME}/rhp/zdm/template/"* 2>/dev/null | tee -a "$OUTPUT_TEXT" || true
    else
        log_warn "ZDM template directory not found at ${ZDM_HOME}/rhp/zdm/template"
    fi

    json_add "zdm_home" "${ZDM_HOME:-}"
    json_add "zdm_user" "$ZDM_USER"
}

discover_java() {
    log_section "JAVA CONFIGURATION"
    log_raw "JAVA_HOME: ${JAVA_HOME:-NOT SET}"
    if command -v java &>/dev/null; then
        java -version 2>&1 | tee -a "$OUTPUT_TEXT" || true
    elif [ -n "${JAVA_HOME:-}" ] && [ -f "${JAVA_HOME}/bin/java" ]; then
        "${JAVA_HOME}/bin/java" -version 2>&1 | tee -a "$OUTPUT_TEXT" || true
    else
        log_warn "Java not found in PATH or JAVA_HOME"
    fi
    json_add "java_home" "${JAVA_HOME:-}"
}

discover_oci_cli() {
    log_section "OCI CLI CONFIGURATION"
    log_raw "--- OCI CLI Version ---"
    oci --version 2>&1 | tee -a "$OUTPUT_TEXT" || log_warn "OCI CLI not found"

    log_raw "--- OCI Config (sensitive data masked) ---"
    local oci_conf="${OCI_CONFIG_PATH:-~/.oci/config}"
    oci_conf="${oci_conf/#\~/$HOME}"
    if [ -f "$oci_conf" ]; then
        sed 's/\(key_file\s*=\s*\).*/\1<masked>/; s/\(fingerprint\s*=\s*\).*/\1<masked>/;
             s/\(tenancy\s*=\s*\)ocid.*/\1<masked>/; s/\(user\s*=\s*\)ocid.*/\1<masked>/' \
             "$oci_conf" | tee -a "$OUTPUT_TEXT"
        log_raw "OCI config profiles:"
        grep '^\[' "$oci_conf" | tee -a "$OUTPUT_TEXT"
    else
        log_warn "OCI config not found at $oci_conf"
    fi

    local oci_key="${OCI_PRIVATE_KEY_PATH:-~/.oci/oci_api_key.pem}"
    oci_key="${oci_key/#\~/$HOME}"
    if [ -f "$oci_key" ]; then
        log_info "OCI API key file exists: $oci_key"
    else
        log_warn "OCI API key NOT found: $oci_key"
    fi

    log_raw "--- OCI Connectivity Test ---"
    if command -v oci &>/dev/null && [ -f "$oci_conf" ]; then
        oci iam region list 2>&1 | head -5 | tee -a "$OUTPUT_TEXT" || log_warn "OCI connectivity test failed"
    fi

    json_add "oci_cli_available" "$(command -v oci &>/dev/null && echo YES || echo NO)"
    json_add "oci_config_path" "${oci_conf}"
}

discover_ssh() {
    log_section "SSH CONFIGURATION"
    log_raw "--- SSH keys in ~/.ssh ---"
    ls -la ~/.ssh/ 2>/dev/null | tee -a "$OUTPUT_TEXT" || log_warn "No ~/.ssh directory found for $(whoami)"

    log_raw "--- zdmuser SSH keys ---"
    if id "$ZDM_USER" &>/dev/null; then
        sudo -u "$ZDM_USER" bash -c 'ls -la ~/.ssh/ 2>/dev/null' 2>&1 | tee -a "$OUTPUT_TEXT" || log_warn "Cannot list $ZDM_USER SSH directory"
    fi

    log_raw "--- SSH key fingerprints (public keys) ---"
    for pub_key in ~/.ssh/*.pub; do
        [ -f "$pub_key" ] && ssh-keygen -l -f "$pub_key" 2>/dev/null | tee -a "$OUTPUT_TEXT" || true
    done
}

discover_credentials() {
    log_section "CREDENTIAL / PASSWORD FILES"
    log_raw "Searching for credential files (passwords, wallets, keystores)..."
    sudo find /home /u01 /opt /etc -maxdepth 6 \
        \( -name "*.password" -o -name "*.pwd" -o -name "*.wallet" \
        -o -name "cwallet.sso" -o -name "ewallet.p12" -o -name ".credentials" \
        -o -name "*credential*" \) 2>/dev/null | head -20 | tee -a "$OUTPUT_TEXT" || true
}

discover_network_config() {
    log_section "NETWORK CONFIGURATION"
    log_raw "--- IP Addresses ---"
    ip addr show 2>/dev/null | grep 'inet ' | awk '{print "  " $2}' | tee -a "$OUTPUT_TEXT" || true

    log_raw "--- Routing Table ---"
    ip route show 2>/dev/null | tee -a "$OUTPUT_TEXT" || route -n 2>/dev/null | tee -a "$OUTPUT_TEXT" || true

    log_raw "--- DNS Configuration ---"
    cat /etc/resolv.conf 2>/dev/null | tee -a "$OUTPUT_TEXT" || true
}

test_connectivity() {
    log_section "NETWORK CONNECTIVITY TESTS"

    test_host() {
        local label="$1"
        local host="$2"
        if [ -z "$host" ]; then
            log_info "$label: HOST NOT PROVIDED - skipping"
            return
        fi
        log_raw "--- Testing connectivity to $label: $host ---"

        # Ping test with latency (10 packets)
        local ping_output
        ping_output=$(ping -c 10 "$host" 2>&1) || true
        if echo "$ping_output" | grep -q 'min/avg/max\|rtt'; then
            echo "$ping_output" | tail -3 | tee -a "$OUTPUT_TEXT"
            local avg_rtt
            avg_rtt=$(echo "$ping_output" | grep -oP '(?<=\/)\d+\.\d+(?=\/)' | head -2 | tail -1)
            if [ -n "$avg_rtt" ]; then
                local avg_int
                avg_int=$(printf '%.0f' "$avg_rtt")
                if [ "$avg_int" -gt 10 ] 2>/dev/null; then
                    log_warn "HIGH LATENCY to $label: avg RTT ${avg_rtt}ms (> 10ms threshold - may impact ZDM online migration)"
                else
                    log_info "Latency to $label: avg RTT ${avg_rtt}ms (OK)"
                fi
            fi
        else
            log_error "PING FAILED to $label ($host)"
            echo "$ping_output" | tail -3 | tee -a "$OUTPUT_TEXT"
        fi

        # Port tests: SSH (22) and Oracle (1521)
        for port in 22 1521; do
            if timeout 5 bash -c "echo >/dev/tcp/${host}/${port}" 2>/dev/null; then
                log_info "$label port $port: OPEN"
            else
                log_warn "$label port $port: BLOCKED or unreachable"
            fi
        done
    }

    test_host "SOURCE DB" "${SOURCE_HOST:-}"
    test_host "TARGET DB" "${TARGET_HOST:-}"

    json_add "source_host_tested" "${SOURCE_HOST:-SKIPPED}"
    json_add "target_host_tested" "${TARGET_HOST:-SKIPPED}"
}

discover_zdm_logs() {
    log_section "ZDM LOG FILES"
    if [ -n "${ZDM_HOME:-}" ]; then
        local log_dirs=( "${ZDM_HOME}/log" "${ZDM_HOME}/zdm/log" "/var/log/zdm" )
        for log_dir in "${log_dirs[@]}"; do
            if sudo test -d "$log_dir" 2>/dev/null; then
                log_raw "Log directory: $log_dir"
                sudo ls -lt "$log_dir"/*.log "$log_dir"/*.out 2>/dev/null | head -10 | tee -a "$OUTPUT_TEXT" || true
                break
            fi
        done
    else
        log_warn "ZDM_HOME not set - cannot locate log directory"
    fi
}

# =============================================================================
# GENERATE JSON SUMMARY
# =============================================================================
write_json() {
    {
        echo "{"
        local first=true
        for entry in "${JSON_SECTIONS[@]}"; do
            [ "$first" = true ] && first=false || echo ","
            printf '%s' "$entry"
        done
        echo ""
        echo "}"
    } > "$OUTPUT_JSON"
    log_info "JSON summary written to: $OUTPUT_JSON"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    > "$OUTPUT_TEXT"

    log_section "ZDM SERVER DISCOVERY"
    log_info "Start time: $(date)"
    log_info "Running as user: $(whoami)"
    log_info "ZDM_USER: $ZDM_USER"
    log_info "SOURCE_HOST: ${SOURCE_HOST:-NOT SET}"
    log_info "TARGET_HOST: ${TARGET_HOST:-NOT SET}"

    detect_zdm_env
    detect_java_env

    discover_os
    discover_zdm           || log_warn "ZDM section failed"
    discover_java          || log_warn "Java section failed"
    discover_oci_cli       || log_warn "OCI CLI section failed"
    discover_ssh           || log_warn "SSH section failed"
    discover_credentials   || log_warn "Credentials section failed"
    discover_network_config || log_warn "Network config section failed"
    test_connectivity      || log_warn "Connectivity tests failed"
    discover_zdm_logs      || log_warn "ZDM logs section failed"

    json_add "discovery_timestamp" "$TIMESTAMP"
    json_add "discovery_host" "$HOSTNAME_SHORT"
    write_json

    log_section "DISCOVERY COMPLETE"
    log_info "End time: $(date)"
    log_info "Text report: $OUTPUT_TEXT"
    log_info "JSON summary: $OUTPUT_JSON"
}

main "$@"
