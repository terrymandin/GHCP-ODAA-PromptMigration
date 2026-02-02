#!/bin/bash
#===============================================================================
# ZDM Server Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# ZDM Server: zdm-jumpbox.corp.example.com
#
# This script discovers ZDM server configuration for ZDM migration.
# It is executed via SSH as an admin user (azureuser), with ZDM CLI
# commands running as the zdmuser via sudo.
#
# Usage: ./zdm_server_discovery.sh
# Output: zdm_server_discovery_<hostname>_<timestamp>.txt
#         zdm_server_discovery_<hostname>_<timestamp>.json
#
# Environment Variables (passed by orchestration script):
#   SOURCE_HOST - Source database hostname for connectivity tests
#   TARGET_HOST - Target database hostname for connectivity tests
#   ZDM_USER    - ZDM software owner (default: zdmuser)
#===============================================================================

#-------------------------------------------------------------------------------
# Color Output Functions
#-------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "\n${CYAN}=== $1 ===${NC}"; }

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
HOSTNAME=$(hostname -s 2>/dev/null || hostname)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="./zdm_server_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_server_discovery_${HOSTNAME}_${TIMESTAMP}.json"

# User configuration
ZDM_USER="${ZDM_USER:-zdmuser}"

# Connectivity test targets (passed from orchestration script)
SOURCE_HOST="${SOURCE_HOST:-}"
TARGET_HOST="${TARGET_HOST:-}"

#-------------------------------------------------------------------------------
# Auto-detect ZDM Environment
#-------------------------------------------------------------------------------
detect_zdm_env() {
    log_info "Auto-detecting ZDM environment..."
    
    # If already set, use existing values
    if [ -n "${ZDM_HOME:-}" ] && [ -n "${JAVA_HOME:-}" ]; then
        log_info "Using pre-configured ZDM_HOME=$ZDM_HOME, JAVA_HOME=$JAVA_HOME"
        return 0
    fi
    
    # Detect ZDM_HOME using multiple methods
    if [ -z "${ZDM_HOME:-}" ]; then
        # Method 1: Get ZDM_HOME from zdmuser's environment
        if id "$ZDM_USER" &>/dev/null; then
            local zdm_home_from_user
            zdm_home_from_user=$(sudo -u "$ZDM_USER" -i bash -c 'echo $ZDM_HOME' 2>/dev/null)
            if [ -n "$zdm_home_from_user" ] && [ -d "$zdm_home_from_user" ] && [ -f "$zdm_home_from_user/bin/zdmcli" ]; then
                export ZDM_HOME="$zdm_home_from_user"
                log_info "Detected ZDM_HOME from $ZDM_USER user: $ZDM_HOME"
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
                        log_info "Detected ZDM_HOME from $ZDM_USER home directory: $ZDM_HOME"
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
                # zdmcli is in $ZDM_HOME/bin/zdmcli, so go up two levels
                export ZDM_HOME="$(dirname "$(dirname "$zdmcli_path")")"
                log_info "Detected ZDM_HOME by finding zdmcli: $ZDM_HOME"
            fi
        fi
    fi
    
    # Detect JAVA_HOME - check ZDM's bundled JDK first
    if [ -z "${JAVA_HOME:-}" ]; then
        # Method 1: Check ZDM's bundled JDK (ZDM often includes its own JDK)
        if [ -n "${ZDM_HOME:-}" ] && [ -d "${ZDM_HOME}/jdk" ]; then
            export JAVA_HOME="${ZDM_HOME}/jdk"
            log_info "Detected JAVA_HOME from ZDM bundled JDK: $JAVA_HOME"
        fi
        
        # Method 2: Get from zdmuser's environment
        if [ -z "${JAVA_HOME:-}" ] && id "$ZDM_USER" &>/dev/null; then
            local java_home_from_user
            java_home_from_user=$(sudo -u "$ZDM_USER" -i bash -c 'echo $JAVA_HOME' 2>/dev/null)
            if [ -n "$java_home_from_user" ] && [ -d "$java_home_from_user" ]; then
                export JAVA_HOME="$java_home_from_user"
                log_info "Detected JAVA_HOME from $ZDM_USER user: $JAVA_HOME"
            fi
        fi
        
        # Method 3: Check alternatives
        if [ -z "${JAVA_HOME:-}" ] && command -v java >/dev/null 2>&1; then
            local java_path
            java_path=$(readlink -f "$(command -v java)" 2>/dev/null)
            if [ -n "$java_path" ]; then
                export JAVA_HOME="${java_path%/bin/java}"
                log_info "Detected JAVA_HOME from alternatives: $JAVA_HOME"
            fi
        fi
        
        # Method 4: Search common Java paths
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
    
    # Apply explicit overrides if provided (highest priority)
    [ -n "${ZDM_HOME_OVERRIDE:-}" ] && export ZDM_HOME="$ZDM_HOME_OVERRIDE"
    [ -n "${JAVA_HOME_OVERRIDE:-}" ] && export JAVA_HOME="$JAVA_HOME_OVERRIDE"
}

#-------------------------------------------------------------------------------
# ZDM Command Execution Functions
#-------------------------------------------------------------------------------
run_zdm_cmd() {
    local zdm_cmd="$1"
    if [ -n "${ZDM_HOME:-}" ]; then
        # Execute as zdmuser - use sudo if current user is not zdmuser
        if [ "$(whoami)" = "$ZDM_USER" ]; then
            ZDM_HOME="$ZDM_HOME" $ZDM_HOME/bin/$zdm_cmd 2>&1
        else
            sudo -u "$ZDM_USER" ZDM_HOME="$ZDM_HOME" $ZDM_HOME/bin/$zdm_cmd 2>&1
        fi
    else
        echo "ERROR: ZDM_HOME not set"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# Discovery Functions
#-------------------------------------------------------------------------------

discover_os_info() {
    log_section "OS Information"
    echo "Hostname: $(hostname)"
    echo "FQDN: $(hostname -f 2>/dev/null || echo 'N/A')"
    echo "Current User: $(whoami)"
    echo ""
    echo "IP Addresses:"
    ip addr show 2>/dev/null | grep 'inet ' | awk '{print "  " $2}' || hostname -I 2>/dev/null | tr ' ' '\n' | sed 's/^/  /'
    echo ""
    echo "Operating System:"
    cat /etc/os-release 2>/dev/null | grep -E '^(NAME|VERSION)=' || cat /etc/redhat-release 2>/dev/null
    echo ""
    echo "Kernel: $(uname -r)"
}

discover_zdm_installation() {
    log_section "ZDM Installation"
    
    echo "ZDM_HOME: ${ZDM_HOME:-NOT SET}"
    echo "ZDM_USER: $ZDM_USER"
    
    if [ -n "${ZDM_HOME:-}" ]; then
        echo ""
        echo "ZDM Installation Verification:"
        if [ -f "$ZDM_HOME/bin/zdmcli" ]; then
            echo "  zdmcli: EXISTS at $ZDM_HOME/bin/zdmcli"
            if [ -x "$ZDM_HOME/bin/zdmcli" ]; then
                echo "  zdmcli: EXECUTABLE"
            else
                echo "  zdmcli: NOT EXECUTABLE (permission issue)"
            fi
        else
            echo "  zdmcli: NOT FOUND at $ZDM_HOME/bin/zdmcli"
        fi
        
        echo ""
        echo "ZDM Response File Templates:"
        if [ -d "$ZDM_HOME/rhp/zdm/template" ]; then
            ls -la "$ZDM_HOME/rhp/zdm/template/"*.rsp 2>/dev/null || echo "  No .rsp files found"
        else
            echo "  Template directory not found"
        fi
        
        echo ""
        echo "ZDM CLI Usage (verification that zdmcli is functional):"
        # Run zdmcli without arguments to show usage - this verifies it's installed correctly
        run_zdm_cmd "zdmcli" 2>&1 | head -20
    else
        echo ""
        log_warn "ZDM_HOME not detected. Please set ZDM_HOME environment variable or ZDM_HOME_OVERRIDE."
    fi
}

discover_zdm_service() {
    log_section "ZDM Service Status"
    
    if [ -n "${ZDM_HOME:-}" ]; then
        echo "ZDM Service Status:"
        run_zdm_cmd "zdmservice status" 2>&1 || echo "zdmservice status command failed"
        
        echo ""
        echo "Active Migration Jobs:"
        run_zdm_cmd "zdmcli query job -jobid all" 2>&1 | head -30 || echo "No active jobs or query failed"
    else
        log_warn "ZDM_HOME not set - skipping ZDM service status"
    fi
}

discover_java_config() {
    log_section "Java Configuration"
    
    echo "JAVA_HOME: ${JAVA_HOME:-NOT SET}"
    
    if [ -n "${JAVA_HOME:-}" ] && [ -f "${JAVA_HOME}/bin/java" ]; then
        echo ""
        echo "Java Version:"
        "$JAVA_HOME/bin/java" -version 2>&1
    elif command -v java &>/dev/null; then
        echo ""
        echo "System Java Version:"
        java -version 2>&1
    else
        echo "Java not found"
    fi
}

discover_oci_cli() {
    log_section "OCI CLI Configuration"
    
    echo "OCI CLI Version:"
    oci --version 2>/dev/null || echo "OCI CLI not installed or not in PATH"
    
    echo ""
    echo "OCI Configuration:"
    if [ -f ~/.oci/config ]; then
        echo "OCI config file found at ~/.oci/config"
        echo ""
        echo "Configured profiles:"
        grep '^\[' ~/.oci/config 2>/dev/null | tr -d '[]'
        echo ""
        echo "Configuration (sensitive data masked):"
        cat ~/.oci/config 2>/dev/null | sed 's/\(key_file\|fingerprint\|key_content\)=.*/\1=***MASKED***/g'
    else
        echo "OCI config file not found at ~/.oci/config"
    fi
    
    echo ""
    echo "API Key File Existence:"
    if [ -f ~/.oci/oci_api_key.pem ]; then
        echo "  ~/.oci/oci_api_key.pem: EXISTS"
    else
        echo "  ~/.oci/oci_api_key.pem: NOT FOUND"
    fi
    
    echo ""
    echo "OCI Connectivity Test:"
    if command -v oci &>/dev/null; then
        if oci iam region list --query 'data[0].name' --raw-output 2>/dev/null; then
            echo "OCI connectivity: SUCCESS"
        else
            echo "OCI connectivity: FAILED"
        fi
    else
        echo "OCI CLI not available for connectivity test"
    fi
}

discover_ssh_config() {
    log_section "SSH Configuration"
    
    echo "SSH Directory Contents (current user: $(whoami)):"
    if [ -d ~/.ssh ]; then
        ls -la ~/.ssh/ 2>/dev/null
    else
        echo "SSH directory not found for current user"
    fi
    
    echo ""
    echo "SSH Directory Contents ($ZDM_USER):"
    local zdm_user_home
    zdm_user_home=$(eval echo ~$ZDM_USER 2>/dev/null)
    if [ -d "$zdm_user_home/.ssh" ]; then
        sudo ls -la "$zdm_user_home/.ssh/" 2>/dev/null || echo "Unable to list $ZDM_USER SSH directory"
    else
        echo "SSH directory not found for $ZDM_USER"
    fi
}

discover_credential_files() {
    log_section "Credential Files Search"
    
    echo "Searching for potential credential/password files..."
    echo "(This helps identify files that may need to be secured or migrated)"
    echo ""
    
    # Search in zdmuser home
    local zdm_user_home
    zdm_user_home=$(eval echo ~$ZDM_USER 2>/dev/null)
    
    echo "Files containing 'password' or 'credential' in name:"
    sudo find "$zdm_user_home" /tmp -maxdepth 3 -type f \( -name "*password*" -o -name "*credential*" -o -name "*wallet*" -o -name "*.rsp" \) 2>/dev/null | head -20
    
    echo ""
    echo "Note: Review these files before migration to ensure credentials are properly secured."
}

discover_network_config() {
    log_section "Network Configuration"
    
    echo "IP Addresses:"
    ip addr show 2>/dev/null | grep 'inet ' | awk '{print "  " $2}'
    
    echo ""
    echo "Routing Table:"
    ip route show 2>/dev/null | head -10 || netstat -rn 2>/dev/null | head -10
    
    echo ""
    echo "DNS Configuration:"
    cat /etc/resolv.conf 2>/dev/null
}

discover_disk_space() {
    log_section "Disk Space for ZDM Operations"
    
    echo "Disk Usage:"
    df -h 2>/dev/null | grep -E '^Filesystem|^/'
    
    echo ""
    echo "ZDM Working Directory Space:"
    if [ -n "${ZDM_HOME:-}" ]; then
        local zdm_partition
        zdm_partition=$(df "$ZDM_HOME" 2>/dev/null | tail -1)
        echo "ZDM_HOME partition: $zdm_partition"
        
        local zdm_user_home
        zdm_user_home=$(eval echo ~$ZDM_USER 2>/dev/null)
        local zdm_home_partition
        zdm_home_partition=$(df "$zdm_user_home" 2>/dev/null | tail -1)
        echo "$ZDM_USER home partition: $zdm_home_partition"
    fi
    
    echo ""
    echo "Disk Space Assessment (minimum 50GB recommended for ZDM):"
    local available_gb
    available_gb=$(df -BG / 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')
    if [ -n "$available_gb" ]; then
        if [ "$available_gb" -ge 50 ]; then
            echo "  Root partition: ${available_gb}GB available - SUFFICIENT"
        else
            echo "  Root partition: ${available_gb}GB available - WARNING: Below recommended 50GB"
        fi
    fi
}

discover_connectivity() {
    log_section "Network Connectivity Tests"
    
    # Test connectivity to SOURCE_HOST
    if [ -n "${SOURCE_HOST:-}" ]; then
        echo "Source Database Connectivity (${SOURCE_HOST}):"
        echo ""
        
        # Ping test
        echo "  Ping test:"
        if ping -c 3 -W 5 "$SOURCE_HOST" &>/dev/null; then
            local ping_time
            ping_time=$(ping -c 3 "$SOURCE_HOST" 2>/dev/null | tail -1 | awk -F'/' '{print $5}')
            echo "    Status: SUCCESS (avg latency: ${ping_time}ms)"
        else
            echo "    Status: FAILED (host unreachable or ICMP blocked)"
        fi
        
        # Port tests
        echo ""
        echo "  Port connectivity:"
        for port in 22 1521; do
            if timeout 5 bash -c "echo >/dev/tcp/$SOURCE_HOST/$port" 2>/dev/null; then
                echo "    Port $port: OPEN"
            else
                echo "    Port $port: BLOCKED or unreachable"
            fi
        done
    else
        echo "SOURCE_HOST not provided - skipping source connectivity tests"
    fi
    
    echo ""
    
    # Test connectivity to TARGET_HOST
    if [ -n "${TARGET_HOST:-}" ]; then
        echo "Target Database Connectivity (${TARGET_HOST}):"
        echo ""
        
        # Ping test
        echo "  Ping test:"
        if ping -c 3 -W 5 "$TARGET_HOST" &>/dev/null; then
            local ping_time
            ping_time=$(ping -c 3 "$TARGET_HOST" 2>/dev/null | tail -1 | awk -F'/' '{print $5}')
            echo "    Status: SUCCESS (avg latency: ${ping_time}ms)"
        else
            echo "    Status: FAILED (host unreachable or ICMP blocked)"
        fi
        
        # Port tests
        echo ""
        echo "  Port connectivity:"
        for port in 22 1521; do
            if timeout 5 bash -c "echo >/dev/tcp/$TARGET_HOST/$port" 2>/dev/null; then
                echo "    Port $port: OPEN"
            else
                echo "    Port $port: BLOCKED or unreachable"
            fi
        done
    else
        echo "TARGET_HOST not provided - skipping target connectivity tests"
    fi
}

discover_zdm_logs() {
    log_section "ZDM Logs"
    
    if [ -n "${ZDM_HOME:-}" ]; then
        local log_dir="$ZDM_HOME/log"
        
        echo "Log Directory: $log_dir"
        
        if [ -d "$log_dir" ]; then
            echo ""
            echo "Recent Log Files:"
            sudo ls -lht "$log_dir"/*.log 2>/dev/null | head -10 || echo "No log files found"
            
            echo ""
            echo "Log Directory Size:"
            sudo du -sh "$log_dir" 2>/dev/null || echo "Unable to determine log directory size"
        else
            echo "Log directory not found at $log_dir"
        fi
        
        # Check zdmuser home for additional logs
        local zdm_user_home
        zdm_user_home=$(eval echo ~$ZDM_USER 2>/dev/null)
        if [ -d "$zdm_user_home/zdm_logs" ]; then
            echo ""
            echo "Additional logs in $zdm_user_home/zdm_logs:"
            sudo ls -lht "$zdm_user_home/zdm_logs" 2>/dev/null | head -5
        fi
    else
        log_warn "ZDM_HOME not set - skipping log discovery"
    fi
}

#-------------------------------------------------------------------------------
# JSON Output Generation
#-------------------------------------------------------------------------------
generate_json_summary() {
    local zdm_installed="false"
    local zdm_service_status="unknown"
    local source_ping="skipped"
    local target_ping="skipped"
    
    if [ -n "${ZDM_HOME:-}" ] && [ -f "$ZDM_HOME/bin/zdmcli" ]; then
        zdm_installed="true"
        zdm_service_status=$(run_zdm_cmd "zdmservice status" 2>&1 | grep -i 'running\|stopped' | head -1 || echo "unknown")
    fi
    
    if [ -n "${SOURCE_HOST:-}" ]; then
        if ping -c 1 -W 3 "$SOURCE_HOST" &>/dev/null; then
            source_ping="success"
        else
            source_ping="failed"
        fi
    fi
    
    if [ -n "${TARGET_HOST:-}" ]; then
        if ping -c 1 -W 3 "$TARGET_HOST" &>/dev/null; then
            target_ping="success"
        else
            target_ping="failed"
        fi
    fi
    
    local available_gb
    available_gb=$(df -BG / 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')
    
    cat > "$JSON_FILE" <<EOF
{
  "discovery_type": "zdm_server",
  "discovery_timestamp": "$(date -Iseconds)",
  "hostname": "$HOSTNAME",
  "zdm_home": "${ZDM_HOME:-}",
  "java_home": "${JAVA_HOME:-}",
  "zdm_user": "$ZDM_USER",
  "zdm": {
    "installed": $zdm_installed,
    "service_status": "$zdm_service_status"
  },
  "connectivity": {
    "source_host": "${SOURCE_HOST:-}",
    "source_ping": "$source_ping",
    "target_host": "${TARGET_HOST:-}",
    "target_ping": "$target_ping"
  },
  "disk_space": {
    "root_available_gb": "${available_gb:-unknown}"
  },
  "output_files": {
    "text_report": "$OUTPUT_FILE",
    "json_summary": "$JSON_FILE"
  }
}
EOF
    
    log_info "JSON summary written to: $JSON_FILE"
}

#-------------------------------------------------------------------------------
# Main Execution
#-------------------------------------------------------------------------------
main() {
    log_info "Starting ZDM Server Discovery on $HOSTNAME"
    log_info "Timestamp: $TIMESTAMP"
    log_info "Running as user: $(whoami)"
    log_info "ZDM user for CLI commands: $ZDM_USER"
    [ -n "$SOURCE_HOST" ] && log_info "Source host for connectivity: $SOURCE_HOST"
    [ -n "$TARGET_HOST" ] && log_info "Target host for connectivity: $TARGET_HOST"
    
    # Detect ZDM environment
    detect_zdm_env
    
    # Run all discovery sections with error handling
    {
        echo "==============================================================================="
        echo "ZDM Server Discovery Report"
        echo "Project: PRODDB Migration to Oracle Database@Azure"
        echo "ZDM Server: zdm-jumpbox.corp.example.com"
        echo "Generated: $(date)"
        echo "Hostname: $HOSTNAME"
        echo "==============================================================================="
        
        # Standard discovery
        discover_os_info || log_warn "OS info discovery had errors"
        discover_zdm_installation || log_warn "ZDM installation discovery had errors"
        discover_zdm_service || log_warn "ZDM service discovery had errors"
        discover_java_config || log_warn "Java config discovery had errors"
        discover_oci_cli || log_warn "OCI CLI discovery had errors"
        discover_ssh_config || log_warn "SSH config discovery had errors"
        discover_credential_files || log_warn "Credential files discovery had errors"
        discover_network_config || log_warn "Network config discovery had errors"
        discover_zdm_logs || log_warn "ZDM logs discovery had errors"
        
        # Additional custom discovery requirements
        discover_disk_space || log_warn "Disk space discovery had errors"
        discover_connectivity || log_warn "Connectivity tests had errors"
        
        echo ""
        echo "==============================================================================="
        echo "End of Discovery Report"
        echo "==============================================================================="
    } 2>&1 | tee "$OUTPUT_FILE"
    
    # Generate JSON summary
    generate_json_summary
    
    log_info "Discovery complete!"
    log_info "Text report: $OUTPUT_FILE"
    log_info "JSON summary: $JSON_FILE"
}

# Execute main function
main "$@"
