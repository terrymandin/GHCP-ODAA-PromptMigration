#!/bin/bash
#
# ZDM Server Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# ZDM Server: zdm-jumpbox.corp.example.com
#
# Purpose: Gather comprehensive discovery information from the ZDM jumpbox server
#          for Zero Downtime Migration (ZDM) planning
#
# Usage: bash zdm_server_discovery.sh
#
# Environment Variables (passed from orchestration script):
#   SOURCE_HOST - Source database hostname (for connectivity tests)
#   TARGET_HOST - Target database hostname (for connectivity tests)
#   ZDM_USER    - ZDM software owner (default: zdmuser)
#
# Output: 
#   - zdm_server_discovery_<hostname>_<timestamp>.txt (human-readable report)
#   - zdm_server_discovery_<hostname>_<timestamp>.json (machine-parseable JSON)
#

# ===========================================
# CONFIGURATION
# ===========================================

# Default ZDM user if not set
ZDM_USER="${ZDM_USER:-zdmuser}"

# Minimum recommended disk space for ZDM operations (in GB)
MIN_DISK_SPACE_GB=50

# Timestamp for output files
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname -s 2>/dev/null || hostname)

# Output files (in current working directory)
TEXT_OUTPUT="./zdm_server_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_OUTPUT="./zdm_server_discovery_${HOSTNAME}_${TIMESTAMP}.json"

# ===========================================
# COLOR OUTPUT FUNCTIONS
# ===========================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "\n${BLUE}========================================${NC}"; echo -e "${BLUE}$1${NC}"; echo -e "${BLUE}========================================${NC}"; }

# ===========================================
# OUTPUT FUNCTIONS
# ===========================================

init_output() {
    echo "ZDM Server Discovery Report" > "$TEXT_OUTPUT"
    echo "Generated: $(date)" >> "$TEXT_OUTPUT"
    echo "Hostname: $HOSTNAME" >> "$TEXT_OUTPUT"
    echo "Project: PRODDB Migration to Oracle Database@Azure" >> "$TEXT_OUTPUT"
    echo "========================================" >> "$TEXT_OUTPUT"
    
    # Initialize JSON
    echo "{" > "$JSON_OUTPUT"
    echo "  \"report_type\": \"zdm_server_discovery\"," >> "$JSON_OUTPUT"
    echo "  \"generated\": \"$(date -Iseconds 2>/dev/null || date)\"," >> "$JSON_OUTPUT"
    echo "  \"hostname\": \"$HOSTNAME\"," >> "$JSON_OUTPUT"
    echo "  \"project\": \"PRODDB Migration to Oracle Database@Azure\"," >> "$JSON_OUTPUT"
}

write_section() {
    local section_name="$1"
    echo "" >> "$TEXT_OUTPUT"
    echo "========================================" >> "$TEXT_OUTPUT"
    echo "$section_name" >> "$TEXT_OUTPUT"
    echo "========================================" >> "$TEXT_OUTPUT"
}

write_text() {
    echo "$1" >> "$TEXT_OUTPUT"
}

write_json_field() {
    local field_name="$1"
    local field_value="$2"
    local is_last="${3:-false}"
    
    # Escape special characters in JSON
    field_value=$(echo "$field_value" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' ' ')
    
    if [ "$is_last" = "true" ]; then
        echo "  \"$field_name\": \"$field_value\"" >> "$JSON_OUTPUT"
    else
        echo "  \"$field_name\": \"$field_value\"," >> "$JSON_OUTPUT"
    fi
}

finalize_json() {
    echo "}" >> "$JSON_OUTPUT"
}

# ===========================================
# ZDM ENVIRONMENT DETECTION
# ===========================================

detect_zdm_env() {
    log_info "Detecting ZDM environment..."
    
    # If already set, use existing values
    if [ -n "${ZDM_HOME:-}" ] && [ -f "${ZDM_HOME}/bin/zdmcli" ]; then
        log_info "Using pre-set ZDM_HOME=$ZDM_HOME"
        return 0
    fi
    
    # Method 1: Get ZDM_HOME from zdmuser's environment
    if [ -z "${ZDM_HOME:-}" ]; then
        if id "$ZDM_USER" &>/dev/null; then
            local zdm_home_from_user
            zdm_home_from_user=$(sudo -u "$ZDM_USER" -i bash -c 'echo $ZDM_HOME' 2>/dev/null)
            if [ -n "$zdm_home_from_user" ] && [ -d "$zdm_home_from_user" ] && [ -f "$zdm_home_from_user/bin/zdmcli" ]; then
                export ZDM_HOME="$zdm_home_from_user"
                log_info "Detected ZDM_HOME from $ZDM_USER environment: $ZDM_HOME"
            fi
        fi
    fi
    
    # Method 2: Check zdmuser's home directory for common ZDM paths
    if [ -z "${ZDM_HOME:-}" ]; then
        local zdm_user_home
        zdm_user_home=$(eval echo ~$ZDM_USER 2>/dev/null)
        if [ -n "$zdm_user_home" ]; then
            for subdir in zdmhome zdm app/zdmhome; do
                local candidate="$zdm_user_home/$subdir"
                if [ -d "$candidate" ] && [ -f "$candidate/bin/zdmcli" ]; then
                    export ZDM_HOME="$candidate"
                    log_info "Detected ZDM_HOME from $ZDM_USER home: $ZDM_HOME"
                    break
                fi
            done
        fi
    fi
    
    # Method 3: Check common ZDM installation locations system-wide
    if [ -z "${ZDM_HOME:-}" ]; then
        for path in /u01/app/zdmhome /u01/zdm /u01/app/zdm /opt/zdm /home/zdmuser/zdmhome /home/*/zdmhome; do
            if sudo test -d "$path" 2>/dev/null && sudo test -f "$path/bin/zdmcli" 2>/dev/null; then
                export ZDM_HOME="$path"
                log_info "Detected ZDM_HOME from common path: $ZDM_HOME"
                break
            elif [ -d "$path" ] && [ -f "$path/bin/zdmcli" ]; then
                export ZDM_HOME="$path"
                log_info "Detected ZDM_HOME from common path: $ZDM_HOME"
                break
            fi
        done
    fi
    
    # Method 4: Search for zdmcli binary and derive ZDM_HOME
    if [ -z "${ZDM_HOME:-}" ]; then
        local zdmcli_path
        zdmcli_path=$(sudo find /u01 /opt /home -name "zdmcli" -type f 2>/dev/null | head -1)
        if [ -n "$zdmcli_path" ]; then
            export ZDM_HOME="$(dirname "$(dirname "$zdmcli_path")")"
            log_info "Detected ZDM_HOME from zdmcli binary: $ZDM_HOME"
        fi
    fi
    
    # Apply overrides if provided
    [ -n "${ZDM_HOME_OVERRIDE:-}" ] && export ZDM_HOME="$ZDM_HOME_OVERRIDE"
    
    # Detect JAVA_HOME - check ZDM's bundled JDK first
    if [ -z "${JAVA_HOME:-}" ]; then
        # Method 1: Check ZDM's bundled JDK
        if [ -n "${ZDM_HOME:-}" ] && [ -d "${ZDM_HOME}/jdk" ]; then
            export JAVA_HOME="${ZDM_HOME}/jdk"
            log_info "Detected JAVA_HOME from ZDM bundled JDK: $JAVA_HOME"
        fi
        
        # Method 2: Check alternatives
        if [ -z "${JAVA_HOME:-}" ] && command -v java >/dev/null 2>&1; then
            local java_path
            java_path=$(readlink -f "$(command -v java)" 2>/dev/null)
            if [ -n "$java_path" ]; then
                export JAVA_HOME="${java_path%/bin/java}"
                log_info "Detected JAVA_HOME from alternatives: $JAVA_HOME"
            fi
        fi
        
        # Method 3: Search common Java paths
        if [ -z "${JAVA_HOME:-}" ]; then
            for path in /usr/java/latest /usr/java/jdk* /usr/lib/jvm/java-* /opt/java/jdk*; do
                if [ -d "$path" ] && [ -f "$path/bin/java" ]; then
                    export JAVA_HOME="$path"
                    log_info "Detected JAVA_HOME from common path: $JAVA_HOME"
                    break
                fi
            done
        fi
    fi
    
    # Apply JAVA_HOME override if provided
    [ -n "${JAVA_HOME_OVERRIDE:-}" ] && export JAVA_HOME="$JAVA_HOME_OVERRIDE"
}

# ===========================================
# ZDM CLI EXECUTION FUNCTION
# ===========================================

run_zdm_cmd() {
    local zdm_cmd="$1"
    if [ -n "${ZDM_HOME:-}" ]; then
        if [ "$(whoami)" = "$ZDM_USER" ]; then
            $ZDM_HOME/bin/$zdm_cmd
        else
            sudo -u "$ZDM_USER" ZDM_HOME="$ZDM_HOME" $ZDM_HOME/bin/$zdm_cmd
        fi
    else
        echo "ERROR: ZDM_HOME not set"
        return 1
    fi
}

# ===========================================
# DISCOVERY FUNCTIONS
# ===========================================

discover_os_info() {
    log_section "OS Information"
    write_section "OS Information"
    
    # Hostname
    local hostname_full=$(hostname -f 2>/dev/null || hostname)
    write_text "Hostname: $hostname_full"
    write_json_field "hostname_full" "$hostname_full"
    
    # Current user
    write_text "Current User: $(whoami)"
    write_json_field "current_user" "$(whoami)"
    
    # OS Version
    local os_version=""
    if [ -f /etc/os-release ]; then
        os_version=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
    elif [ -f /etc/redhat-release ]; then
        os_version=$(cat /etc/redhat-release)
    else
        os_version=$(uname -a)
    fi
    write_text "OS Version: $os_version"
    write_json_field "os_version" "$os_version"
    
    log_info "OS information collected"
}

discover_zdm_installation() {
    log_section "ZDM Installation"
    write_section "ZDM Installation"
    
    write_text "ZDM_HOME: ${ZDM_HOME:-NOT FOUND}"
    write_json_field "zdm_home" "${ZDM_HOME:-NOT FOUND}"
    
    if [ -n "${ZDM_HOME:-}" ]; then
        # Check if zdmcli exists and is executable
        if [ -f "$ZDM_HOME/bin/zdmcli" ]; then
            write_text "ZDM CLI: $ZDM_HOME/bin/zdmcli (EXISTS)"
            if [ -x "$ZDM_HOME/bin/zdmcli" ]; then
                write_text "ZDM CLI Executable: YES"
                write_json_field "zdmcli_status" "INSTALLED_AND_EXECUTABLE"
            else
                write_text "ZDM CLI Executable: NO (check permissions)"
                write_json_field "zdmcli_status" "NOT_EXECUTABLE"
            fi
        else
            write_text "ZDM CLI: NOT FOUND at $ZDM_HOME/bin/zdmcli"
            write_json_field "zdmcli_status" "NOT_FOUND"
        fi
        
        # Check for ZDM response file templates
        write_text ""
        write_text "ZDM Response File Templates:"
        if [ -d "$ZDM_HOME/rhp/zdm/template" ]; then
            ls -la "$ZDM_HOME/rhp/zdm/template/"*.rsp 2>/dev/null >> "$TEXT_OUTPUT" || write_text "No .rsp files found"
        else
            write_text "Template directory not found: $ZDM_HOME/rhp/zdm/template"
        fi
        
        # ZDM Service Status (NOTE: zdmcli does NOT have -version flag)
        write_text ""
        write_text "ZDM Service Status:"
        if [ "$(whoami)" = "$ZDM_USER" ]; then
            $ZDM_HOME/bin/zdmservice status 2>&1 >> "$TEXT_OUTPUT" || write_text "Unable to get ZDM service status"
        else
            sudo -u "$ZDM_USER" ZDM_HOME="$ZDM_HOME" $ZDM_HOME/bin/zdmservice status 2>&1 >> "$TEXT_OUTPUT" || write_text "Unable to get ZDM service status"
        fi
        
        # Active migration jobs
        write_text ""
        write_text "Active Migration Jobs:"
        if [ "$(whoami)" = "$ZDM_USER" ]; then
            $ZDM_HOME/bin/zdmcli query job -all 2>&1 | head -50 >> "$TEXT_OUTPUT" || write_text "No active jobs or unable to query"
        else
            sudo -u "$ZDM_USER" ZDM_HOME="$ZDM_HOME" $ZDM_HOME/bin/zdmcli query job -all 2>&1 | head -50 >> "$TEXT_OUTPUT" || write_text "No active jobs or unable to query"
        fi
    else
        write_text "ZDM_HOME not detected - ZDM may not be installed"
        write_json_field "zdmcli_status" "ZDM_NOT_INSTALLED"
    fi
    
    log_info "ZDM installation collected"
}

discover_java_config() {
    log_section "Java Configuration"
    write_section "Java Configuration"
    
    write_text "JAVA_HOME: ${JAVA_HOME:-NOT SET}"
    write_json_field "java_home" "${JAVA_HOME:-NOT SET}"
    
    # Java version
    if [ -n "${JAVA_HOME:-}" ] && [ -f "$JAVA_HOME/bin/java" ]; then
        write_text ""
        write_text "Java Version:"
        $JAVA_HOME/bin/java -version 2>&1 >> "$TEXT_OUTPUT"
        local java_version=$($JAVA_HOME/bin/java -version 2>&1 | head -1)
        write_json_field "java_version" "$java_version"
    elif command -v java &>/dev/null; then
        write_text ""
        write_text "Java Version (from PATH):"
        java -version 2>&1 >> "$TEXT_OUTPUT"
        local java_version=$(java -version 2>&1 | head -1)
        write_json_field "java_version" "$java_version"
    else
        write_text "Java not found"
        write_json_field "java_version" "NOT_FOUND"
    fi
    
    log_info "Java configuration collected"
}

discover_oci_cli_config() {
    log_section "OCI CLI Configuration"
    write_section "OCI CLI Configuration"
    
    # OCI CLI version
    write_text "OCI CLI Version:"
    if command -v oci &>/dev/null; then
        oci --version 2>&1 >> "$TEXT_OUTPUT"
        local oci_version=$(oci --version 2>&1)
        write_json_field "oci_cli_version" "$oci_version"
    else
        write_text "OCI CLI not installed"
        write_json_field "oci_cli_version" "NOT_INSTALLED"
    fi
    
    # OCI config file
    write_text ""
    write_text "OCI Config File:"
    local oci_config="${OCI_CONFIG_PATH:-~/.oci/config}"
    oci_config=$(eval echo "$oci_config")
    if [ -f "$oci_config" ]; then
        write_text "Config file exists: $oci_config"
        write_text ""
        write_text "OCI Profiles (sensitive data masked):"
        grep -E '^\[|^region|^tenancy' "$oci_config" 2>/dev/null >> "$TEXT_OUTPUT" || write_text "Unable to read OCI config"
        write_json_field "oci_config_exists" "true"
    else
        write_text "OCI config file not found: $oci_config"
        write_json_field "oci_config_exists" "false"
    fi
    
    # OCI API key file
    write_text ""
    write_text "OCI API Key File:"
    local oci_key="${OCI_PRIVATE_KEY_PATH:-~/.oci/oci_api_key.pem}"
    oci_key=$(eval echo "$oci_key")
    if [ -f "$oci_key" ]; then
        write_text "API key file exists: $oci_key"
        write_json_field "oci_api_key_exists" "true"
    else
        write_text "API key file not found: $oci_key"
        write_json_field "oci_api_key_exists" "false"
    fi
    
    # OCI connectivity test
    write_text ""
    write_text "OCI Connectivity Test:"
    if command -v oci &>/dev/null && [ -f "$oci_config" ]; then
        if oci iam region list --output table 2>/dev/null | head -10 >> "$TEXT_OUTPUT"; then
            write_text "OCI connectivity: SUCCESS"
            write_json_field "oci_connectivity" "SUCCESS"
        else
            write_text "OCI connectivity: FAILED"
            write_json_field "oci_connectivity" "FAILED"
        fi
    else
        write_text "OCI connectivity test skipped (CLI not installed or config missing)"
        write_json_field "oci_connectivity" "SKIPPED"
    fi
    
    log_info "OCI CLI configuration collected"
}

discover_ssh_config() {
    log_section "SSH Configuration"
    write_section "SSH Configuration"
    
    # SSH keys for current user
    write_text "SSH Keys (current user: $(whoami)):"
    if [ -d ~/.ssh ]; then
        ls -la ~/.ssh 2>/dev/null >> "$TEXT_OUTPUT"
    else
        write_text "SSH directory not found for current user"
    fi
    
    # SSH keys for zdmuser
    write_text ""
    write_text "SSH Keys ($ZDM_USER):"
    local zdm_user_home=$(eval echo ~$ZDM_USER 2>/dev/null)
    if [ -d "$zdm_user_home/.ssh" ]; then
        sudo ls -la "$zdm_user_home/.ssh" 2>/dev/null >> "$TEXT_OUTPUT" || write_text "Unable to list $ZDM_USER SSH directory"
    else
        write_text "SSH directory not found for $ZDM_USER"
    fi
    
    log_info "SSH configuration collected"
}

discover_credential_files() {
    log_section "Credential Files Search"
    write_section "Credential Files Search"
    
    write_text "Searching for potential credential files..."
    write_text "(This helps identify files that may need secure handling during migration)"
    write_text ""
    
    # Search for common credential file patterns
    for pattern in "*.wallet" "*password*" "*credential*" "*.pem" "*.key" "*secret*"; do
        local found=$(sudo find /home /root /u01 -name "$pattern" -type f 2>/dev/null | head -10)
        if [ -n "$found" ]; then
            write_text "Pattern: $pattern"
            echo "$found" >> "$TEXT_OUTPUT"
            write_text ""
        fi
    done
    
    log_info "Credential files search completed"
}

discover_network_config() {
    log_section "Network Configuration"
    write_section "Network Configuration"
    
    # IP addresses
    write_text "IP Addresses:"
    ip addr show 2>/dev/null | grep 'inet ' >> "$TEXT_OUTPUT" || \
    ifconfig 2>/dev/null | grep 'inet ' >> "$TEXT_OUTPUT" || \
    write_text "Unable to get IP addresses"
    
    # Routing table
    write_text ""
    write_text "Routing Table:"
    ip route show 2>/dev/null >> "$TEXT_OUTPUT" || \
    netstat -rn 2>/dev/null >> "$TEXT_OUTPUT" || \
    write_text "Unable to get routing table"
    
    # DNS configuration
    write_text ""
    write_text "DNS Configuration:"
    if [ -f /etc/resolv.conf ]; then
        cat /etc/resolv.conf >> "$TEXT_OUTPUT"
    else
        write_text "/etc/resolv.conf not found"
    fi
    
    log_info "Network configuration collected"
}

discover_zdm_logs() {
    log_section "ZDM Logs"
    write_section "ZDM Logs"
    
    if [ -n "${ZDM_HOME:-}" ]; then
        local log_dir="$ZDM_HOME/zdm/log"
        write_text "Log Directory: $log_dir"
        
        if [ -d "$log_dir" ]; then
            write_text ""
            write_text "Recent Log Files:"
            sudo ls -lt "$log_dir" 2>/dev/null | head -20 >> "$TEXT_OUTPUT" || write_text "Unable to list log directory"
        else
            write_text "Log directory not found"
        fi
    else
        write_text "ZDM_HOME not set - cannot locate log directory"
    fi
    
    log_info "ZDM logs collected"
}

# ===========================================
# ADDITIONAL DISCOVERY (PRODDB Specific)
# ===========================================

discover_disk_space() {
    log_section "Disk Space for ZDM Operations"
    write_section "Disk Space for ZDM Operations"
    
    write_text "Minimum Recommended: ${MIN_DISK_SPACE_GB}GB"
    write_text ""
    write_text "Disk Space Summary:"
    df -h 2>/dev/null >> "$TEXT_OUTPUT"
    
    # Check available space on key directories
    write_text ""
    write_text "Key Directory Space Analysis:"
    
    local zdm_dir="${ZDM_HOME:-/u01}"
    local home_dir="$HOME"
    local tmp_dir="/tmp"
    
    for dir in "$zdm_dir" "$home_dir" "$tmp_dir" "/u01" "/opt"; do
        if [ -d "$dir" ]; then
            local available_gb=$(df -BG "$dir" 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')
            if [ -n "$available_gb" ]; then
                if [ "$available_gb" -ge "$MIN_DISK_SPACE_GB" ]; then
                    write_text "  $dir: ${available_gb}GB available - SUFFICIENT"
                else
                    write_text "  $dir: ${available_gb}GB available - WARNING: Below ${MIN_DISK_SPACE_GB}GB threshold"
                fi
            fi
        fi
    done
    
    # Get total available on ZDM home partition
    local zdm_available_gb=""
    if [ -n "${ZDM_HOME:-}" ] && [ -d "${ZDM_HOME:-}" ]; then
        zdm_available_gb=$(df -BG "$ZDM_HOME" 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')
    fi
    write_json_field "zdm_partition_available_gb" "${zdm_available_gb:-UNKNOWN}"
    
    if [ -n "$zdm_available_gb" ] && [ "$zdm_available_gb" -lt "$MIN_DISK_SPACE_GB" ]; then
        write_json_field "disk_space_sufficient" "false"
        write_text ""
        write_text "⚠️  WARNING: Insufficient disk space on ZDM partition!"
        write_text "    Available: ${zdm_available_gb}GB"
        write_text "    Required: ${MIN_DISK_SPACE_GB}GB minimum"
    else
        write_json_field "disk_space_sufficient" "true"
    fi
    
    log_info "Disk space analysis completed"
}

discover_network_latency() {
    log_section "Network Latency Tests"
    write_section "Network Latency Tests"
    
    write_text "Testing network connectivity and latency to source and target..."
    write_text ""
    
    # ===========================================
    # SOURCE HOST CONNECTIVITY
    # ===========================================
    if [ -n "${SOURCE_HOST:-}" ]; then
        write_text "Source Host: $SOURCE_HOST"
        write_text "----------------------------------------"
        
        # Ping test
        write_text "Ping Test (3 packets):"
        if ping -c 3 "$SOURCE_HOST" 2>&1 >> "$TEXT_OUTPUT"; then
            local source_latency=$(ping -c 3 "$SOURCE_HOST" 2>/dev/null | tail -1 | awk -F'/' '{print $5}')
            write_text "Ping Result: SUCCESS (avg latency: ${source_latency}ms)"
            write_json_field "source_ping_status" "SUCCESS"
            write_json_field "source_ping_latency_ms" "${source_latency:-UNKNOWN}"
        else
            write_text "Ping Result: FAILED (host may block ICMP or be unreachable)"
            write_json_field "source_ping_status" "FAILED"
        fi
        
        # Port tests
        write_text ""
        write_text "Port Connectivity Tests:"
        for port in 22 1521; do
            if timeout 5 bash -c "echo >/dev/tcp/$SOURCE_HOST/$port" 2>/dev/null; then
                write_text "  Port $port: OPEN"
                write_json_field "source_port_${port}" "OPEN"
            else
                write_text "  Port $port: BLOCKED or unreachable"
                write_json_field "source_port_${port}" "BLOCKED"
            fi
        done
        write_text ""
    else
        write_text "SOURCE_HOST not provided - skipping source connectivity tests"
        write_json_field "source_ping_status" "SKIPPED"
        write_text ""
    fi
    
    # ===========================================
    # TARGET HOST CONNECTIVITY
    # ===========================================
    if [ -n "${TARGET_HOST:-}" ]; then
        write_text "Target Host: $TARGET_HOST"
        write_text "----------------------------------------"
        
        # Ping test
        write_text "Ping Test (3 packets):"
        if ping -c 3 "$TARGET_HOST" 2>&1 >> "$TEXT_OUTPUT"; then
            local target_latency=$(ping -c 3 "$TARGET_HOST" 2>/dev/null | tail -1 | awk -F'/' '{print $5}')
            write_text "Ping Result: SUCCESS (avg latency: ${target_latency}ms)"
            write_json_field "target_ping_status" "SUCCESS"
            write_json_field "target_ping_latency_ms" "${target_latency:-UNKNOWN}"
        else
            write_text "Ping Result: FAILED (host may block ICMP or be unreachable)"
            write_json_field "target_ping_status" "FAILED"
        fi
        
        # Port tests
        write_text ""
        write_text "Port Connectivity Tests:"
        for port in 22 1521; do
            if timeout 5 bash -c "echo >/dev/tcp/$TARGET_HOST/$port" 2>/dev/null; then
                write_text "  Port $port: OPEN"
                write_json_field "target_port_${port}" "OPEN"
            else
                write_text "  Port $port: BLOCKED or unreachable"
                write_json_field "target_port_${port}" "BLOCKED"
            fi
        done
        write_text ""
    else
        write_text "TARGET_HOST not provided - skipping target connectivity tests"
        write_json_field "target_ping_status" "SKIPPED"
        write_text ""
    fi
    
    # ===========================================
    # CONNECTIVITY SUMMARY
    # ===========================================
    write_text "Connectivity Summary"
    write_text "----------------------------------------"
    if [ -n "${SOURCE_HOST:-}" ] || [ -n "${TARGET_HOST:-}" ]; then
        write_text "Review the port test results above."
        write_text "Required ports:"
        write_text "  - SSH (22): Required for ZDM orchestration"
        write_text "  - Oracle (1521): Required for database connectivity"
        write_text ""
        write_text "If ports are blocked, work with your network team to open firewall rules."
    else
        write_text "No connectivity tests performed (SOURCE_HOST and TARGET_HOST not provided)"
        write_text "Run the orchestration script to automatically pass these values."
    fi
    
    log_info "Network latency tests completed"
}

# ===========================================
# MAIN EXECUTION
# ===========================================

main() {
    log_info "Starting ZDM Server Discovery"
    log_info "Output will be saved to:"
    log_info "  Text: $TEXT_OUTPUT"
    log_info "  JSON: $JSON_OUTPUT"
    
    # Initialize output files
    init_output
    
    # Detect ZDM environment
    detect_zdm_env
    
    # Standard discovery sections
    discover_os_info || log_warn "OS information discovery failed - continuing"
    discover_zdm_installation || log_warn "ZDM installation discovery failed - continuing"
    discover_java_config || log_warn "Java configuration discovery failed - continuing"
    discover_oci_cli_config || log_warn "OCI CLI configuration discovery failed - continuing"
    discover_ssh_config || log_warn "SSH configuration discovery failed - continuing"
    discover_credential_files || log_warn "Credential files search failed - continuing"
    discover_network_config || log_warn "Network configuration discovery failed - continuing"
    discover_zdm_logs || log_warn "ZDM logs discovery failed - continuing"
    
    # Additional PRODDB-specific discovery
    discover_disk_space || log_warn "Disk space discovery failed - continuing"
    discover_network_latency || log_warn "Network latency tests failed - continuing"
    
    # Finalize JSON output
    write_json_field "discovery_completed" "$(date -Iseconds 2>/dev/null || date)" "true"
    finalize_json
    
    log_info ""
    log_info "=========================================="
    log_info "Discovery Complete!"
    log_info "=========================================="
    log_info "Text Report: $TEXT_OUTPUT"
    log_info "JSON Summary: $JSON_OUTPUT"
}

# Run main function
main "$@"
