#!/bin/bash
################################################################################
# ZDM Server Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# ZDM Server: zdm-jumpbox.corp.example.com
#
# Purpose: Discover ZDM server configuration and environment details
# Execution: Run via SSH as ADMIN_USER (azureuser) with sudo privileges
################################################################################

# Configuration - User defaults
ZDM_USER="${ZDM_USER:-zdmuser}"

# Connectivity test configuration (passed from orchestration script)
SOURCE_HOST="${SOURCE_HOST:-}"
TARGET_HOST="${TARGET_HOST:-}"

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Timestamp for output files
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname -f 2>/dev/null || hostname)

# Output files in current working directory
OUTPUT_TXT="./zdm_server_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
OUTPUT_JSON="./zdm_server_discovery_${HOSTNAME}_${TIMESTAMP}.json"

# Initialize JSON output
json_data="{}"

################################################################################
# Utility Functions
################################################################################

log_section() {
    local title="$1"
    echo "" | tee -a "$OUTPUT_TXT"
    echo "========================================" | tee -a "$OUTPUT_TXT"
    echo "$title" | tee -a "$OUTPUT_TXT"
    echo "========================================" | tee -a "$OUTPUT_TXT"
    echo -e "${BLUE}▶ $title${NC}"
}

log_info() {
    echo "$1" | tee -a "$OUTPUT_TXT"
    echo -e "${GREEN}  $1${NC}"
}

log_warn() {
    echo "WARNING: $1" | tee -a "$OUTPUT_TXT"
    echo -e "${YELLOW}  ⚠ WARNING: $1${NC}"
}

log_error() {
    echo "ERROR: $1" | tee -a "$OUTPUT_TXT"
    echo -e "${RED}  ✗ ERROR: $1${NC}"
}

add_json_field() {
    local key="$1"
    local value="$2"
    # Escape quotes in value
    value="${value//\"/\\\"}"
    json_data=$(echo "$json_data" | jq --arg k "$key" --arg v "$value" '. + {($k): $v}')
}

################################################################################
# ZDM Environment Auto-Detection
################################################################################

detect_zdm_env() {
    log_section "ZDM Environment Detection"
    
    # If already set, use existing values
    if [ -n "${ZDM_HOME:-}" ] && [ -n "${JAVA_HOME:-}" ]; then
        log_info "Using existing ZDM_HOME: $ZDM_HOME"
        log_info "Using existing JAVA_HOME: $JAVA_HOME"
        return 0
    fi
    
    # Detect ZDM_HOME using multiple methods
    if [ -z "${ZDM_HOME:-}" ]; then
        # Method 1: Get ZDM_HOME from zdmuser's environment
        log_info "Checking zdmuser environment..."
        if id "$ZDM_USER" &>/dev/null; then
            local zdm_home_from_user
            zdm_home_from_user=$(sudo -u "$ZDM_USER" -i bash -c 'echo $ZDM_HOME' 2>/dev/null)
            if [ -n "$zdm_home_from_user" ] && [ -d "$zdm_home_from_user" ] && sudo test -f "$zdm_home_from_user/bin/zdmcli" 2>/dev/null; then
                export ZDM_HOME="$zdm_home_from_user"
                log_info "Found ZDM_HOME from zdmuser environment: $ZDM_HOME"
            fi
        fi
        
        # Method 2: Check zdmuser's home directory
        if [ -z "${ZDM_HOME:-}" ]; then
            log_info "Checking zdmuser home directory..."
            local zdm_user_home
            zdm_user_home=$(eval echo ~$ZDM_USER 2>/dev/null)
            if [ -n "$zdm_user_home" ]; then
                for subdir in zdmhome zdm app/zdmhome; do
                    local candidate="$zdm_user_home/$subdir"
                    if sudo test -d "$candidate" 2>/dev/null && sudo test -f "$candidate/bin/zdmcli" 2>/dev/null; then
                        export ZDM_HOME="$candidate"
                        log_info "Found ZDM_HOME in zdmuser home: $ZDM_HOME"
                        break
                    fi
                done
            fi
        fi
        
        # Method 3: Check common ZDM installation locations
        if [ -z "${ZDM_HOME:-}" ]; then
            log_info "Searching common ZDM installation paths..."
            for path in /u01/app/zdmhome /u01/zdm /u01/app/zdm /opt/zdm /home/zdmuser/zdmhome /home/*/zdmhome; do
                if sudo test -d "$path" 2>/dev/null && sudo test -f "$path/bin/zdmcli" 2>/dev/null; then
                    export ZDM_HOME="$path"
                    log_info "Found ZDM_HOME: $ZDM_HOME"
                    break
                fi
            done
        fi
        
        # Method 4: Search for zdmcli binary
        if [ -z "${ZDM_HOME:-}" ]; then
            log_info "Searching for zdmcli binary..."
            local zdmcli_path
            zdmcli_path=$(sudo find /u01 /opt /home -name "zdmcli" -type f 2>/dev/null | head -1)
            if [ -n "$zdmcli_path" ]; then
                export ZDM_HOME="$(dirname "$(dirname "$zdmcli_path")")"
                log_info "Found ZDM_HOME from zdmcli location: $ZDM_HOME"
            fi
        fi
    fi
    
    # Detect JAVA_HOME - check ZDM's bundled JDK first
    if [ -z "${JAVA_HOME:-}" ]; then
        # Method 1: Check ZDM's bundled JDK
        if [ -n "${ZDM_HOME:-}" ] && sudo test -d "${ZDM_HOME}/jdk" 2>/dev/null; then
            export JAVA_HOME="${ZDM_HOME}/jdk"
            log_info "Found JAVA_HOME from ZDM's bundled JDK: $JAVA_HOME"
        fi
        
        # Method 2: Check alternatives
        if [ -z "${JAVA_HOME:-}" ] && command -v java >/dev/null 2>&1; then
            local java_path
            java_path=$(readlink -f "$(command -v java)" 2>/dev/null)
            if [ -n "$java_path" ]; then
                export JAVA_HOME="${java_path%/bin/java}"
                log_info "Found JAVA_HOME from alternatives: $JAVA_HOME"
            fi
        fi
        
        # Method 3: Search common Java paths
        if [ -z "${JAVA_HOME:-}" ]; then
            for path in /usr/java/latest /usr/java/jdk* /usr/lib/jvm/java-* /opt/java/jdk*; do
                if [ -d "$path" ] && [ -f "$path/bin/java" ]; then
                    export JAVA_HOME="$path"
                    log_info "Found JAVA_HOME from common paths: $JAVA_HOME"
                    break
                fi
            done
        fi
    fi
    
    # Apply explicit overrides if provided (highest priority)
    [ -n "${ZDM_HOME_OVERRIDE:-}" ] && export ZDM_HOME="$ZDM_HOME_OVERRIDE"
    [ -n "${JAVA_HOME_OVERRIDE:-}" ] && export JAVA_HOME="$JAVA_HOME_OVERRIDE"
    
    # Verify detection
    if [ -z "${ZDM_HOME:-}" ]; then
        log_error "Failed to detect ZDM_HOME"
        return 1
    fi
    
    if [ -z "${JAVA_HOME:-}" ]; then
        log_warn "Failed to detect JAVA_HOME (may affect ZDM operations)"
    fi
    
    log_info "✓ ZDM environment detected successfully"
    log_info "  ZDM_HOME: $ZDM_HOME"
    log_info "  JAVA_HOME: ${JAVA_HOME:-not set}"
    log_info "  ZDM_USER: $ZDM_USER"
    
    return 0
}

################################################################################
# ZDM Command Execution Function
################################################################################

run_zdm_cmd() {
    local zdm_cmd="$1"
    if [ -n "${ZDM_HOME:-}" ]; then
        # Execute as zdmuser - use sudo if current user is not zdmuser
        if [ "$(whoami)" = "$ZDM_USER" ]; then
            $ZDM_HOME/bin/$zdm_cmd 2>&1
        else
            sudo -u "$ZDM_USER" -E ZDM_HOME="$ZDM_HOME" JAVA_HOME="${JAVA_HOME:-}" $ZDM_HOME/bin/$zdm_cmd 2>&1
        fi
    else
        echo "ERROR: ZDM_HOME not set"
        return 1
    fi
}

################################################################################
# Main Discovery Functions
################################################################################

gather_os_info() {
    log_section "Operating System Information"
    
    log_info "Hostname: $(hostname -f 2>/dev/null || hostname)"
    add_json_field "hostname" "$(hostname -f 2>/dev/null || hostname)"
    
    log_info "Current User: $(whoami)"
    add_json_field "current_user" "$(whoami)"
    
    log_info "IP Addresses:"
    ip addr show | grep 'inet ' | awk '{print "  " $2}' | tee -a "$OUTPUT_TXT"
    
    log_info "OS Version:"
    if [ -f /etc/os-release ]; then
        cat /etc/os-release | tee -a "$OUTPUT_TXT"
        os_version=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
        add_json_field "os_version" "$os_version"
    elif [ -f /etc/redhat-release ]; then
        cat /etc/redhat-release | tee -a "$OUTPUT_TXT"
        add_json_field "os_version" "$(cat /etc/redhat-release)"
    fi
    
    log_info "Disk Space:"
    df -h | tee -a "$OUTPUT_TXT"
    
    log_info "Memory:"
    free -h | tee -a "$OUTPUT_TXT"
}

gather_disk_space_check() {
    log_section "Disk Space Verification"
    
    log_info "Checking for minimum 50GB available disk space for ZDM operations..."
    
    # Check root filesystem
    local root_avail_gb=$(df -BG / | tail -1 | awk '{print $4}' | sed 's/G//')
    log_info "Root filesystem available: ${root_avail_gb}GB"
    
    if [ "$root_avail_gb" -ge 50 ]; then
        log_info "✓ Root filesystem has sufficient space (${root_avail_gb}GB >= 50GB)"
        add_json_field "disk_space_sufficient" "true"
    else
        log_warn "Root filesystem has insufficient space (${root_avail_gb}GB < 50GB recommended)"
        add_json_field "disk_space_sufficient" "false"
    fi
    
    # Check /tmp if it's a separate mount
    if mountpoint -q /tmp 2>/dev/null; then
        local tmp_avail_gb=$(df -BG /tmp | tail -1 | awk '{print $4}' | sed 's/G//')
        log_info "/tmp filesystem available: ${tmp_avail_gb}GB"
        
        if [ "$tmp_avail_gb" -lt 10 ]; then
            log_warn "/tmp filesystem has limited space (${tmp_avail_gb}GB)"
        fi
    fi
    
    # Check ZDM_HOME filesystem if detected
    if [ -n "${ZDM_HOME:-}" ] && [ -d "$ZDM_HOME" ]; then
        local zdm_avail_gb=$(df -BG "$ZDM_HOME" | tail -1 | awk '{print $4}' | sed 's/G//')
        log_info "ZDM_HOME filesystem available: ${zdm_avail_gb}GB"
    fi
}

gather_zdm_installation() {
    log_section "ZDM Installation"
    
    log_info "ZDM_HOME: ${ZDM_HOME:-not set}"
    add_json_field "zdm_home" "${ZDM_HOME:-}"
    
    if [ -n "${ZDM_HOME:-}" ]; then
        # Check if zdmcli exists and is executable
        if sudo test -f "$ZDM_HOME/bin/zdmcli" 2>/dev/null && sudo test -x "$ZDM_HOME/bin/zdmcli" 2>/dev/null; then
            log_info "✓ ZDM CLI found and executable"
            add_json_field "zdm_cli_found" "true"
            
            # Display ZDM CLI usage (no -version flag available)
            log_info "ZDM CLI Usage:"
            run_zdm_cmd "zdmcli" | head -20 | tee -a "$OUTPUT_TXT"
        else
            log_error "ZDM CLI not found or not executable"
            add_json_field "zdm_cli_found" "false"
        fi
        
        # Check for ZDM response file templates
        log_info "ZDM Response File Templates:"
        if sudo test -d "$ZDM_HOME/rhp/zdm/template" 2>/dev/null; then
            sudo ls -l "$ZDM_HOME/rhp/zdm/template"/*.rsp 2>&1 | tee -a "$OUTPUT_TXT"
        else
            log_warn "Response file templates directory not found"
        fi
    else
        log_error "ZDM_HOME not detected"
        add_json_field "zdm_cli_found" "false"
    fi
}

gather_zdm_service_status() {
    log_section "ZDM Service Status"
    
    if [ -n "${ZDM_HOME:-}" ] && sudo test -x "$ZDM_HOME/bin/zdmservice" 2>/dev/null; then
        log_info "ZDM Service Status:"
        run_zdm_cmd "zdmservice status" | tee -a "$OUTPUT_TXT"
        
        # Check if service is running
        if run_zdm_cmd "zdmservice status" | grep -q "is running"; then
            log_info "✓ ZDM service is running"
            add_json_field "zdm_service_running" "true"
        else
            log_warn "ZDM service is not running"
            add_json_field "zdm_service_running" "false"
        fi
    else
        log_warn "ZDM service command not found"
        add_json_field "zdm_service_running" "unknown"
    fi
}

gather_zdm_jobs() {
    log_section "Active ZDM Migration Jobs"
    
    if [ -n "${ZDM_HOME:-}" ]; then
        log_info "Querying active migration jobs..."
        run_zdm_cmd "zdmcli query job" | tee -a "$OUTPUT_TXT" || log_info "No active jobs or query failed"
    fi
}

gather_java_config() {
    log_section "Java Configuration"
    
    log_info "JAVA_HOME: ${JAVA_HOME:-not set}"
    add_json_field "java_home" "${JAVA_HOME:-}"
    
    if command -v java &> /dev/null; then
        log_info "Java Version:"
        java -version 2>&1 | tee -a "$OUTPUT_TXT"
        
        java_version=$(java -version 2>&1 | head -1)
        add_json_field "java_version" "$java_version"
    else
        log_warn "Java not found in PATH"
    fi
    
    # Check ZDM's bundled JDK
    if [ -n "${ZDM_HOME:-}" ] && sudo test -d "$ZDM_HOME/jdk" 2>/dev/null; then
        log_info "ZDM Bundled JDK:"
        sudo $ZDM_HOME/jdk/bin/java -version 2>&1 | tee -a "$OUTPUT_TXT"
    fi
}

gather_oci_config() {
    log_section "OCI CLI Configuration"
    
    if command -v oci &> /dev/null; then
        log_info "OCI CLI Version:"
        oci --version 2>&1 | tee -a "$OUTPUT_TXT"
        add_json_field "oci_cli_installed" "true"
        
        # Check for OCI config file
        log_info "OCI Configuration:"
        if [ -f ~/.oci/config ]; then
            log_info "OCI config file exists for current user"
            grep -E "^\[|^user|^tenancy|^region" ~/.oci/config 2>&1 | tee -a "$OUTPUT_TXT"
        else
            log_warn "OCI config file not found for current user"
        fi
        
        # Check OCI config for zdmuser
        local zdm_user_home=$(eval echo ~$ZDM_USER 2>/dev/null)
        if [ -n "$zdm_user_home" ] && sudo test -f "$zdm_user_home/.oci/config" 2>/dev/null; then
            log_info "OCI config file exists for $ZDM_USER"
            sudo -u "$ZDM_USER" grep -E "^\[|^user|^tenancy|^region" "$zdm_user_home/.oci/config" 2>&1 | tee -a "$OUTPUT_TXT"
        else
            log_warn "OCI config file not found for $ZDM_USER"
        fi
        
        # Test OCI connectivity
        log_info "OCI Connectivity Test:"
        oci iam region list 2>&1 | head -10 | tee -a "$OUTPUT_TXT" || log_warn "OCI connectivity test failed"
    else
        log_warn "OCI CLI not installed"
        add_json_field "oci_cli_installed" "false"
    fi
}

gather_ssh_config() {
    log_section "SSH Configuration"
    
    log_info "SSH Keys (current user):"
    if [ -d ~/.ssh ]; then
        ls -l ~/.ssh/*.pub ~/.ssh/id_* 2>&1 | tee -a "$OUTPUT_TXT"
    else
        log_warn "SSH directory not found for current user"
    fi
    
    log_info "SSH Keys ($ZDM_USER):"
    local zdm_user_home=$(eval echo ~$ZDM_USER 2>/dev/null)
    if [ -n "$zdm_user_home" ] && sudo test -d "$zdm_user_home/.ssh" 2>/dev/null; then
        sudo -u "$ZDM_USER" ls -l "$zdm_user_home/.ssh"/*.pub "$zdm_user_home/.ssh"/id_* 2>&1 | tee -a "$OUTPUT_TXT"
    else
        log_warn "SSH directory not found for $ZDM_USER"
    fi
}

gather_network_config() {
    log_section "Network Configuration"
    
    log_info "IP Addresses:"
    ip addr show | tee -a "$OUTPUT_TXT"
    
    log_info "Routing Table:"
    ip route | tee -a "$OUTPUT_TXT"
    
    log_info "DNS Configuration:"
    cat /etc/resolv.conf | tee -a "$OUTPUT_TXT"
}

gather_network_connectivity() {
    log_section "Network Connectivity Tests"
    
    # Only run connectivity tests if SOURCE_HOST and TARGET_HOST are provided
    if [ -z "${SOURCE_HOST:-}" ] && [ -z "${TARGET_HOST:-}" ]; then
        log_info "SOURCE_HOST and TARGET_HOST not provided - skipping connectivity tests"
        log_info "These variables should be set by the orchestration script"
        return 0
    fi
    
    # Test connectivity to source
    if [ -n "${SOURCE_HOST:-}" ]; then
        log_info "Testing connectivity to source: $SOURCE_HOST"
        
        # Ping test
        log_info "Ping test to $SOURCE_HOST:"
        if ping -c 3 "$SOURCE_HOST" &>/dev/null; then
            local latency=$(ping -c 3 "$SOURCE_HOST" 2>&1 | grep 'avg' | awk -F'/' '{print $5}')
            log_info "✓ SUCCESS - Average latency: ${latency}ms"
            add_json_field "source_ping" "SUCCESS"
            add_json_field "source_latency_ms" "$latency"
        else
            log_warn "✗ FAILED - Cannot ping $SOURCE_HOST"
            add_json_field "source_ping" "FAILED"
        fi
        
        # Port tests
        log_info "Port connectivity tests to $SOURCE_HOST:"
        for port in 22 1521; do
            if timeout 5 bash -c "echo >/dev/tcp/$SOURCE_HOST/$port" 2>/dev/null; then
                log_info "  Port $port: ✓ OPEN"
            else
                log_warn "  Port $port: ✗ BLOCKED or unreachable"
            fi
        done
    else
        log_info "SOURCE_HOST not provided - skipping source connectivity tests"
        add_json_field "source_ping" "SKIPPED"
    fi
    
    # Test connectivity to target
    if [ -n "${TARGET_HOST:-}" ]; then
        log_info "Testing connectivity to target: $TARGET_HOST"
        
        # Ping test
        log_info "Ping test to $TARGET_HOST:"
        if ping -c 3 "$TARGET_HOST" &>/dev/null; then
            local latency=$(ping -c 3 "$TARGET_HOST" 2>&1 | grep 'avg' | awk -F'/' '{print $5}')
            log_info "✓ SUCCESS - Average latency: ${latency}ms"
            add_json_field "target_ping" "SUCCESS"
            add_json_field "target_latency_ms" "$latency"
        else
            log_warn "✗ FAILED - Cannot ping $TARGET_HOST"
            add_json_field "target_ping" "FAILED"
        fi
        
        # Port tests
        log_info "Port connectivity tests to $TARGET_HOST:"
        for port in 22 1521; do
            if timeout 5 bash -c "echo >/dev/tcp/$TARGET_HOST/$port" 2>/dev/null; then
                log_info "  Port $port: ✓ OPEN"
            else
                log_warn "  Port $port: ✗ BLOCKED or unreachable"
            fi
        done
    else
        log_info "TARGET_HOST not provided - skipping target connectivity tests"
        add_json_field "target_ping" "SKIPPED"
    fi
}

gather_zdm_logs() {
    log_section "ZDM Logs"
    
    if [ -n "${ZDM_HOME:-}" ]; then
        # Check for ZDM log directory
        local log_dirs=(
            "$ZDM_HOME/zdm/log"
            "$ZDM_HOME/log"
            "/var/log/zdm"
        )
        
        for log_dir in "${log_dirs[@]}"; do
            if sudo test -d "$log_dir" 2>/dev/null; then
                log_info "Log Directory: $log_dir"
                sudo ls -lht "$log_dir" 2>&1 | head -20 | tee -a "$OUTPUT_TXT"
                add_json_field "zdm_log_dir" "$log_dir"
                break
            fi
        done
    fi
}

################################################################################
# Main Execution
################################################################################

main() {
    echo "========================================" | tee "$OUTPUT_TXT"
    echo "ZDM Server Discovery" | tee -a "$OUTPUT_TXT"
    echo "Project: PRODDB Migration to Oracle Database@Azure" | tee -a "$OUTPUT_TXT"
    echo "ZDM Server: zdm-jumpbox.corp.example.com" | tee -a "$OUTPUT_TXT"
    echo "Timestamp: $(date)" | tee -a "$OUTPUT_TXT"
    echo "========================================" | tee -a "$OUTPUT_TXT"
    
    # Initialize JSON
    json_data=$(jq -n '{}')
    add_json_field "discovery_type" "zdm_server"
    add_json_field "timestamp" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    add_json_field "project" "PRODDB Migration to Oracle Database@Azure"
    add_json_field "zdm_server" "zdm-jumpbox.corp.example.com"
    
    # Detect ZDM environment first
    if ! detect_zdm_env; then
        log_warn "Failed to detect ZDM environment. Continuing with limited discovery..."
    fi
    
    # Run all discovery functions with error handling
    gather_os_info || log_error "Failed to gather OS info"
    gather_disk_space_check || log_error "Failed to check disk space"
    gather_zdm_installation || log_error "Failed to gather ZDM installation info"
    gather_zdm_service_status || log_error "Failed to gather ZDM service status"
    gather_zdm_jobs || log_error "Failed to gather ZDM jobs"
    gather_java_config || log_error "Failed to gather Java config"
    gather_oci_config || log_error "Failed to gather OCI config"
    gather_ssh_config || log_error "Failed to gather SSH config"
    gather_network_config || log_error "Failed to gather network config"
    gather_network_connectivity || log_error "Failed to test network connectivity"
    gather_zdm_logs || log_error "Failed to gather ZDM logs"
    
    # Write JSON output
    echo "$json_data" | jq '.' > "$OUTPUT_JSON"
    
    log_section "Discovery Complete"
    log_info "Text report: $OUTPUT_TXT"
    log_info "JSON summary: $OUTPUT_JSON"
    
    echo -e "\n${GREEN}✓ ZDM server discovery completed successfully${NC}"
}

# Run main function
main
