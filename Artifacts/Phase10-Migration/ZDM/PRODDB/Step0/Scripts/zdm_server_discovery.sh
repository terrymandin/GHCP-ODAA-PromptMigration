#!/bin/bash
#
# ZDM Server Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# ZDM Server: zdm-jumpbox.corp.example.com
#
# This script gathers comprehensive information about the ZDM jumpbox server
# for ZDM migration planning. It should be executed via SSH as the admin user (azureuser)
# with sudo privileges to run ZDM commands as the zdmuser.
#
# Usage: bash zdm_server_discovery.sh
#
# Environment Variables (set by orchestration script):
#   SOURCE_HOST - Source database hostname for connectivity tests
#   TARGET_HOST - Target database hostname for connectivity tests
#   ZDM_USER    - ZDM software owner (default: zdmuser)
#
# Output: 
#   - zdm_server_discovery_<hostname>_<timestamp>.txt (human-readable)
#   - zdm_server_discovery_<hostname>_<timestamp>.json (machine-parseable)
#

# =============================================================================
# CONFIGURATION
# =============================================================================

# ZDM user configuration
ZDM_USER="${ZDM_USER:-zdmuser}"

# Source and target hosts for connectivity tests (set by orchestration script)
SOURCE_HOST="${SOURCE_HOST:-}"
TARGET_HOST="${TARGET_HOST:-}"

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Timestamp for output files
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME_SHORT=$(hostname -s)
OUTPUT_FILE="./zdm_server_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_server_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

log_section() {
    local title="$1"
    echo ""
    echo -e "${BLUE}=============================================================================${NC}"
    echo -e "${BLUE}  $title${NC}"
    echo -e "${BLUE}=============================================================================${NC}"
    echo ""
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_subsection() {
    echo ""
    echo -e "${CYAN}--- $1 ---${NC}"
    echo ""
}

# Auto-detect ZDM environment
detect_zdm_env() {
    # If already set, use existing values
    if [ -n "${ZDM_HOME:-}" ]; then
        if [ -f "${ZDM_HOME}/bin/zdmcli" ]; then
            log_info "Using pre-configured ZDM_HOME=$ZDM_HOME"
            return 0
        fi
    fi
    
    log_info "Auto-detecting ZDM environment..."
    
    # Method 1: Get ZDM_HOME from zdmuser's environment
    if [ -z "${ZDM_HOME:-}" ]; then
        if id "$ZDM_USER" &>/dev/null; then
            local zdm_home_from_user
            zdm_home_from_user=$(sudo -u "$ZDM_USER" -i bash -c 'echo $ZDM_HOME' 2>/dev/null)
            if [ -n "$zdm_home_from_user" ] && [ -d "$zdm_home_from_user" ]; then
                if sudo test -f "$zdm_home_from_user/bin/zdmcli" 2>/dev/null || [ -f "$zdm_home_from_user/bin/zdmcli" ]; then
                    export ZDM_HOME="$zdm_home_from_user"
                    log_info "Detected ZDM_HOME from $ZDM_USER environment: $ZDM_HOME"
                fi
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
                if sudo test -d "$candidate" 2>/dev/null && sudo test -f "$candidate/bin/zdmcli" 2>/dev/null; then
                    export ZDM_HOME="$candidate"
                    log_info "Detected ZDM_HOME from $ZDM_USER home directory: $ZDM_HOME"
                    break
                fi
            done
        fi
    fi
    
    # Method 3: Check common ZDM installation locations system-wide
    if [ -z "${ZDM_HOME:-}" ]; then
        for path in /u01/app/zdmhome /u01/zdm /u01/app/zdm /opt/zdm /home/zdmuser/zdmhome; do
            if sudo test -d "$path" 2>/dev/null && sudo test -f "$path/bin/zdmcli" 2>/dev/null; then
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
            log_info "Detected ZDM_HOME from zdmcli search: $ZDM_HOME"
        fi
    fi
    
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
            for path in /usr/java/latest /usr/java/jdk* /usr/lib/jvm/java-*; do
                if [ -d "$path" ] && [ -f "$path/bin/java" ]; then
                    export JAVA_HOME="$path"
                    log_info "Detected JAVA_HOME from path search: $JAVA_HOME"
                    break
                fi
            done
        fi
    fi
    
    # Apply explicit overrides if provided (highest priority)
    [ -n "${ZDM_HOME_OVERRIDE:-}" ] && export ZDM_HOME="$ZDM_HOME_OVERRIDE"
    [ -n "${JAVA_HOME_OVERRIDE:-}" ] && export JAVA_HOME="$JAVA_HOME_OVERRIDE"
}

# Run ZDM command as zdmuser
run_zdm_cmd() {
    local zdm_cmd="$1"
    if [ -n "${ZDM_HOME:-}" ]; then
        if [ "$(whoami)" = "$ZDM_USER" ]; then
            ZDM_HOME="$ZDM_HOME" $ZDM_HOME/bin/$zdm_cmd 2>/dev/null
        else
            sudo -u "$ZDM_USER" ZDM_HOME="$ZDM_HOME" $ZDM_HOME/bin/$zdm_cmd 2>/dev/null
        fi
    else
        echo "ERROR: ZDM_HOME not set"
        return 1
    fi
}

# Initialize JSON output
init_json() {
    echo "{" > "$JSON_FILE"
    echo '  "discovery_type": "zdm_server",' >> "$JSON_FILE"
    echo "  \"hostname\": \"$HOSTNAME_SHORT\"," >> "$JSON_FILE"
    echo "  \"timestamp\": \"$TIMESTAMP\"," >> "$JSON_FILE"
    echo '  "project": "PRODDB Migration to Oracle Database@Azure",' >> "$JSON_FILE"
}

# Add JSON key-value pair
add_json() {
    local key="$1"
    local value="$2"
    local is_last="${3:-false}"
    # Escape special characters in value
    value=$(echo "$value" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g')
    if [ "$is_last" = "true" ]; then
        echo "  \"$key\": \"$value\"" >> "$JSON_FILE"
    else
        echo "  \"$key\": \"$value\"," >> "$JSON_FILE"
    fi
}

# Finalize JSON output
finalize_json() {
    echo "}" >> "$JSON_FILE"
}

# =============================================================================
# DISCOVERY FUNCTIONS
# =============================================================================

discover_os_info() {
    log_section "OS INFORMATION"
    
    log_subsection "Hostname and Current User"
    echo "Hostname: $(hostname)"
    echo "Short hostname: $(hostname -s)"
    echo "Current user: $(whoami)"
    echo "ZDM user: $ZDM_USER"
    
    log_subsection "IP Addresses"
    ip addr show 2>/dev/null | grep 'inet ' | awk '{print "  " $2}' || hostname -I 2>/dev/null || echo "  Unable to determine"
    
    log_subsection "Operating System Version"
    if [ -f /etc/os-release ]; then
        cat /etc/os-release
    elif [ -f /etc/redhat-release ]; then
        cat /etc/redhat-release
    else
        uname -a
    fi
    
    log_subsection "Kernel Information"
    uname -r
}

discover_zdm_installation() {
    log_section "ZDM INSTALLATION"
    
    log_subsection "ZDM Environment"
    echo "ZDM_HOME: ${ZDM_HOME:-NOT SET}"
    echo "ZDM_USER: $ZDM_USER"
    
    log_subsection "ZDM Installation Verification"
    if [ -n "${ZDM_HOME:-}" ]; then
        if sudo test -f "$ZDM_HOME/bin/zdmcli" 2>/dev/null || [ -f "$ZDM_HOME/bin/zdmcli" ]; then
            log_success "zdmcli found at: $ZDM_HOME/bin/zdmcli"
            
            # Check if executable
            if sudo test -x "$ZDM_HOME/bin/zdmcli" 2>/dev/null; then
                log_success "zdmcli is executable"
            else
                log_warn "zdmcli exists but may not be executable"
            fi
            
            # Display zdmcli usage to verify it works (NOT -version as that's invalid)
            echo ""
            echo "ZDM CLI Help (first 20 lines):"
            if [ "$(whoami)" = "$ZDM_USER" ]; then
                ZDM_HOME="$ZDM_HOME" $ZDM_HOME/bin/zdmcli 2>&1 | head -20
            else
                sudo -u "$ZDM_USER" ZDM_HOME="$ZDM_HOME" $ZDM_HOME/bin/zdmcli 2>&1 | head -20
            fi
        else
            log_error "zdmcli NOT found at: $ZDM_HOME/bin/zdmcli"
        fi
        
        # Check for response file templates
        log_subsection "ZDM Response File Templates"
        local template_dir="$ZDM_HOME/rhp/zdm/template"
        if sudo test -d "$template_dir" 2>/dev/null; then
            echo "Templates found at: $template_dir"
            sudo ls -la "$template_dir"/*.rsp 2>/dev/null || echo "No .rsp template files found"
        else
            echo "Template directory not found at: $template_dir"
        fi
    else
        log_error "ZDM_HOME not set - ZDM installation not detected"
    fi
    
    log_subsection "ZDM Service Status"
    if [ -n "${ZDM_HOME:-}" ]; then
        echo "Running: zdmservice status"
        if [ "$(whoami)" = "$ZDM_USER" ]; then
            ZDM_HOME="$ZDM_HOME" $ZDM_HOME/bin/zdmservice status 2>&1 || echo "Unable to get ZDM service status"
        else
            sudo -u "$ZDM_USER" ZDM_HOME="$ZDM_HOME" $ZDM_HOME/bin/zdmservice status 2>&1 || echo "Unable to get ZDM service status"
        fi
    else
        echo "ZDM_HOME not set - cannot check service status"
    fi
    
    log_subsection "Active Migration Jobs"
    if [ -n "${ZDM_HOME:-}" ]; then
        echo "Running: zdmcli query job -jobid all"
        if [ "$(whoami)" = "$ZDM_USER" ]; then
            ZDM_HOME="$ZDM_HOME" $ZDM_HOME/bin/zdmcli query job -jobid all 2>&1 | head -50 || echo "No active migration jobs or unable to query"
        else
            sudo -u "$ZDM_USER" ZDM_HOME="$ZDM_HOME" $ZDM_HOME/bin/zdmcli query job -jobid all 2>&1 | head -50 || echo "No active migration jobs or unable to query"
        fi
    fi
}

discover_java_config() {
    log_section "JAVA CONFIGURATION"
    
    log_subsection "JAVA_HOME"
    echo "JAVA_HOME: ${JAVA_HOME:-NOT SET}"
    
    log_subsection "Java Version"
    if [ -n "${JAVA_HOME:-}" ] && [ -f "$JAVA_HOME/bin/java" ]; then
        "$JAVA_HOME/bin/java" -version 2>&1
    elif command -v java &>/dev/null; then
        java -version 2>&1
    else
        echo "Java not found"
    fi
    
    log_subsection "ZDM Bundled JDK"
    if [ -n "${ZDM_HOME:-}" ] && [ -d "${ZDM_HOME}/jdk" ]; then
        echo "ZDM bundled JDK found at: ${ZDM_HOME}/jdk"
        if [ -f "${ZDM_HOME}/jdk/bin/java" ]; then
            "${ZDM_HOME}/jdk/bin/java" -version 2>&1
        fi
    else
        echo "ZDM bundled JDK not found"
    fi
}

discover_oci_cli() {
    log_section "OCI CLI CONFIGURATION"
    
    log_subsection "OCI CLI Version"
    if command -v oci &>/dev/null; then
        oci --version 2>/dev/null || echo "Unable to get OCI CLI version"
    else
        echo "OCI CLI not installed"
    fi
    
    log_subsection "OCI Config File"
    local oci_config=~/.oci/config
    if [ -f "$oci_config" ]; then
        echo "OCI config file exists at: $oci_config"
        echo ""
        echo "Configured profiles:"
        grep '^\[' "$oci_config" 2>/dev/null
        echo ""
        echo "Configured regions:"
        grep 'region' "$oci_config" 2>/dev/null | head -5
    else
        echo "OCI config file not found at: $oci_config"
    fi
    
    # Check zdmuser's OCI config as well
    local zdm_user_home
    zdm_user_home=$(eval echo ~$ZDM_USER 2>/dev/null)
    if [ -n "$zdm_user_home" ] && [ -f "$zdm_user_home/.oci/config" ]; then
        echo ""
        echo "ZDM user ($ZDM_USER) OCI config exists at: $zdm_user_home/.oci/config"
    fi
    
    log_subsection "OCI API Key File"
    if [ -f ~/.oci/oci_api_key.pem ]; then
        echo "API key file exists at: ~/.oci/oci_api_key.pem"
    else
        echo "Default API key file not found at: ~/.oci/oci_api_key.pem"
        ls -la ~/.oci/*.pem 2>/dev/null || echo "No .pem files found in ~/.oci/"
    fi
    
    log_subsection "OCI Connectivity Test"
    if command -v oci &>/dev/null; then
        echo "Testing OCI connectivity..."
        oci iam region list --output table 2>/dev/null | head -15 || echo "Unable to connect to OCI or not authenticated"
    fi
}

discover_ssh_config() {
    log_section "SSH CONFIGURATION"
    
    log_subsection "Current User SSH Keys"
    if [ -d ~/.ssh ]; then
        echo "Contents of ~/.ssh:"
        ls -la ~/.ssh/ 2>/dev/null
    else
        echo "SSH directory not found for current user"
    fi
    
    log_subsection "ZDM User SSH Keys"
    local zdm_user_home
    zdm_user_home=$(eval echo ~$ZDM_USER 2>/dev/null)
    if [ -n "$zdm_user_home" ] && [ -d "$zdm_user_home/.ssh" ]; then
        echo "Contents of $zdm_user_home/.ssh:"
        sudo ls -la "$zdm_user_home/.ssh/" 2>/dev/null || echo "Unable to list ZDM user SSH directory"
    else
        echo "SSH directory not found for $ZDM_USER user"
    fi
}

discover_credential_files() {
    log_section "CREDENTIAL FILES"
    
    log_subsection "Searching for Password/Credential Files"
    echo "Searching in home directories for credential files..."
    sudo find /home -name "*password*" -o -name "*credential*" -o -name "*secret*" 2>/dev/null | head -20 || echo "No credential files found or search not permitted"
    
    log_subsection "ZDM Wallet Files"
    if [ -n "${ZDM_HOME:-}" ]; then
        local wallet_dir="$ZDM_HOME/crsdata"
        if sudo test -d "$wallet_dir" 2>/dev/null; then
            echo "ZDM credential storage found at: $wallet_dir"
            sudo ls -la "$wallet_dir" 2>/dev/null | head -20
        fi
    fi
}

discover_network_config() {
    log_section "NETWORK CONFIGURATION"
    
    log_subsection "IP Addresses"
    ip addr show 2>/dev/null | grep 'inet '
    
    log_subsection "Routing Table"
    ip route show 2>/dev/null | head -20 || route -n 2>/dev/null | head -20
    
    log_subsection "DNS Configuration"
    if [ -f /etc/resolv.conf ]; then
        cat /etc/resolv.conf
    else
        echo "/etc/resolv.conf not found"
    fi
    
    log_subsection "Hosts File"
    cat /etc/hosts
}

discover_disk_space() {
    log_section "DISK SPACE (Minimum 50GB Recommended)"
    
    log_subsection "Filesystem Usage"
    df -h 2>/dev/null || df 2>/dev/null
    
    log_subsection "ZDM Home Disk Space"
    if [ -n "${ZDM_HOME:-}" ]; then
        local zdm_disk
        zdm_disk=$(df -h "$ZDM_HOME" 2>/dev/null | tail -1)
        echo "Disk containing ZDM_HOME ($ZDM_HOME):"
        echo "$zdm_disk"
        
        # Check if available space is at least 50GB
        local available_gb
        available_gb=$(df -BG "$ZDM_HOME" 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//')
        if [ -n "$available_gb" ]; then
            if [ "$available_gb" -ge 50 ]; then
                log_success "Available space: ${available_gb}GB (meets 50GB minimum)"
            else
                log_warn "Available space: ${available_gb}GB (BELOW 50GB minimum recommended)"
            fi
        fi
    fi
    
    log_subsection "Temporary Directory Space"
    df -h /tmp 2>/dev/null || echo "Unable to check /tmp disk space"
}

discover_connectivity() {
    log_section "NETWORK CONNECTIVITY TO SOURCE AND TARGET"
    
    if [ -z "${SOURCE_HOST:-}" ] && [ -z "${TARGET_HOST:-}" ]; then
        log_warn "SOURCE_HOST and TARGET_HOST not provided - skipping connectivity tests"
        echo "To run connectivity tests, set these environment variables before running the script."
        return
    fi
    
    log_subsection "Source Database Connectivity ($SOURCE_HOST)"
    if [ -n "${SOURCE_HOST:-}" ]; then
        # Ping test
        echo "Ping test to $SOURCE_HOST:"
        if ping -c 3 -W 5 "$SOURCE_HOST" 2>/dev/null; then
            log_success "Ping to $SOURCE_HOST: SUCCESS"
            # Get latency
            local latency
            latency=$(ping -c 3 -W 5 "$SOURCE_HOST" 2>/dev/null | tail -1 | awk -F'/' '{print $5}')
            [ -n "$latency" ] && echo "Average latency: ${latency}ms"
        else
            log_warn "Ping to $SOURCE_HOST: FAILED (ICMP may be blocked)"
        fi
        
        # Port tests
        echo ""
        echo "Port connectivity tests:"
        for port in 22 1521; do
            if timeout 5 bash -c "echo >/dev/tcp/$SOURCE_HOST/$port" 2>/dev/null; then
                log_success "Source port $port: OPEN"
            else
                log_warn "Source port $port: BLOCKED or unreachable"
            fi
        done
    else
        log_info "SOURCE_HOST not provided - skipping source connectivity tests"
    fi
    
    log_subsection "Target Database Connectivity ($TARGET_HOST)"
    if [ -n "${TARGET_HOST:-}" ]; then
        # Ping test
        echo "Ping test to $TARGET_HOST:"
        if ping -c 3 -W 5 "$TARGET_HOST" 2>/dev/null; then
            log_success "Ping to $TARGET_HOST: SUCCESS"
            # Get latency
            local latency
            latency=$(ping -c 3 -W 5 "$TARGET_HOST" 2>/dev/null | tail -1 | awk -F'/' '{print $5}')
            [ -n "$latency" ] && echo "Average latency: ${latency}ms"
        else
            log_warn "Ping to $TARGET_HOST: FAILED (ICMP may be blocked)"
        fi
        
        # Port tests
        echo ""
        echo "Port connectivity tests:"
        for port in 22 1521; do
            if timeout 5 bash -c "echo >/dev/tcp/$TARGET_HOST/$port" 2>/dev/null; then
                log_success "Target port $port: OPEN"
            else
                log_warn "Target port $port: BLOCKED or unreachable"
            fi
        done
    else
        log_info "TARGET_HOST not provided - skipping target connectivity tests"
    fi
}

discover_zdm_logs() {
    log_section "ZDM LOGS"
    
    log_subsection "ZDM Log Directory"
    if [ -n "${ZDM_HOME:-}" ]; then
        local log_dir="$ZDM_HOME/logs"
        if sudo test -d "$log_dir" 2>/dev/null; then
            echo "Log directory: $log_dir"
            echo ""
            echo "Recent log files:"
            sudo ls -lt "$log_dir"/*.log 2>/dev/null | head -10 || echo "No .log files found"
        else
            echo "Log directory not found at: $log_dir"
        fi
        
        # Check for job logs
        local job_log_dir="$ZDM_HOME/chkbase"
        if sudo test -d "$job_log_dir" 2>/dev/null; then
            echo ""
            echo "Job checkpoint directory: $job_log_dir"
            sudo ls -lt "$job_log_dir" 2>/dev/null | head -10
        fi
    else
        echo "ZDM_HOME not set - cannot check log directory"
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          ZDM SERVER DISCOVERY - PRODDB MIGRATION                          ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Timestamp: $(date)"
    echo "Output File: $OUTPUT_FILE"
    echo "JSON File: $JSON_FILE"
    echo ""
    
    # Display connectivity test targets
    echo "Connectivity test targets:"
    echo "  SOURCE_HOST: ${SOURCE_HOST:-NOT SET}"
    echo "  TARGET_HOST: ${TARGET_HOST:-NOT SET}"
    echo ""
    
    # Detect ZDM environment
    detect_zdm_env
    
    if [ -z "${ZDM_HOME:-}" ]; then
        log_warn "ZDM_HOME not detected. Some discovery steps may be limited."
    else
        log_info "Using ZDM_HOME: $ZDM_HOME"
    fi
    
    log_info "ZDM commands will run as user: $ZDM_USER"
    echo ""
    
    # Initialize JSON output
    init_json
    add_json "zdm_home" "${ZDM_HOME:-NOT_SET}"
    add_json "zdm_user" "$ZDM_USER"
    add_json "java_home" "${JAVA_HOME:-NOT_SET}"
    
    # Run discovery (all output tee'd to both console and file)
    {
        echo "ZDM SERVER DISCOVERY"
        echo "Project: PRODDB Migration to Oracle Database@Azure"
        echo "ZDM Server: zdm-jumpbox.corp.example.com"
        echo "Timestamp: $(date)"
        echo "ZDM_HOME: ${ZDM_HOME:-NOT SET}"
        echo "ZDM_USER: $ZDM_USER"
        echo "SOURCE_HOST: ${SOURCE_HOST:-NOT SET}"
        echo "TARGET_HOST: ${TARGET_HOST:-NOT SET}"
        
        # Standard discovery
        discover_os_info
        discover_zdm_installation
        discover_java_config
        discover_oci_cli
        discover_ssh_config
        discover_credential_files
        discover_network_config
        
        # Additional project-specific discovery
        discover_disk_space
        discover_connectivity
        discover_zdm_logs
        
        echo ""
        log_section "DISCOVERY COMPLETE"
        echo "Output saved to: $OUTPUT_FILE"
        echo "JSON saved to: $JSON_FILE"
        
    } 2>&1 | tee "$OUTPUT_FILE"
    
    # Add connectivity results to JSON
    local source_ping="SKIPPED"
    local target_ping="SKIPPED"
    
    if [ -n "${SOURCE_HOST:-}" ]; then
        if ping -c 1 -W 3 "$SOURCE_HOST" &>/dev/null; then
            source_ping="SUCCESS"
        else
            source_ping="FAILED"
        fi
    fi
    
    if [ -n "${TARGET_HOST:-}" ]; then
        if ping -c 1 -W 3 "$TARGET_HOST" &>/dev/null; then
            target_ping="SUCCESS"
        else
            target_ping="FAILED"
        fi
    fi
    
    add_json "source_host" "${SOURCE_HOST:-NOT_SET}"
    add_json "target_host" "${TARGET_HOST:-NOT_SET}"
    add_json "source_ping" "$source_ping"
    add_json "target_ping" "$target_ping"
    add_json "discovery_status" "COMPLETED" "true"
    finalize_json
    
    echo ""
    log_info "Discovery completed successfully!"
    echo ""
}

# Run main function
main "$@"
