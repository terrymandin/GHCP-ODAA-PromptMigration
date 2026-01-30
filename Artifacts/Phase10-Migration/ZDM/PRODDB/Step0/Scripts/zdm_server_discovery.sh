#!/bin/bash
#===============================================================================
# ZDM Server Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# ZDM Server: zdm-jumpbox.corp.example.com
#
# Purpose: Gather comprehensive information from the ZDM jumpbox server
#          to support ZDM migration planning.
#
# Execution: Run as ADMIN_USER (azureuser) via SSH. ZDM commands execute as ZDM_USER.
#
# Output:
#   - Text report: ./zdm_server_discovery_<hostname>_<timestamp>.txt
#   - JSON summary: ./zdm_server_discovery_<hostname>_<timestamp>.json
#===============================================================================

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script variables
SCRIPT_NAME="zdm_server_discovery.sh"
HOSTNAME=$(hostname -s 2>/dev/null || hostname)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="./zdm_server_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_server_discovery_${HOSTNAME}_${TIMESTAMP}.json"

# User configuration - can be overridden via environment
ZDM_USER="${ZDM_USER:-zdmuser}"

# Error tracking
declare -a FAILED_SECTIONS=()
declare -a SUCCESS_SECTIONS=()

#===============================================================================
# FUNCTIONS
#===============================================================================

print_header() {
    local title="$1"
    echo -e "\n${BLUE}=================================================================================${NC}"
    echo -e "${CYAN}  $title${NC}"
    echo -e "${BLUE}=================================================================================${NC}"
}

print_section() {
    local title="$1"
    echo -e "\n${GREEN}--- $title ---${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

log_section_result() {
    local section="$1"
    local status="$2"
    if [ "$status" = "success" ]; then
        SUCCESS_SECTIONS+=("$section")
    else
        FAILED_SECTIONS+=("$section")
    fi
}

# Auto-detect ZDM environment
detect_zdm_env() {
    # If already set, use existing values
    if [ -n "${ZDM_HOME:-}" ] && [ -n "${JAVA_HOME:-}" ]; then
        print_success "Using pre-configured ZDM_HOME=$ZDM_HOME, JAVA_HOME=$JAVA_HOME"
        return 0
    fi
    
    print_section "Auto-detecting ZDM Environment"
    
    # Detect ZDM_HOME
    if [ -z "${ZDM_HOME:-}" ]; then
        # Check common ZDM installation locations
        for path in ~/zdmhome ~/zdm /opt/zdm /u01/zdm "$HOME/zdmhome" /home/zdmuser/zdmhome; do
            if [ -d "$path" ] && [ -f "$path/bin/zdmcli" ]; then
                export ZDM_HOME="$path"
                print_success "Detected ZDM_HOME: $ZDM_HOME"
                break
            fi
        done
        
        # Also check zdmuser's home directory
        if [ -z "${ZDM_HOME:-}" ]; then
            local zdmuser_home
            zdmuser_home=$(getent passwd "$ZDM_USER" 2>/dev/null | cut -d: -f6)
            if [ -n "$zdmuser_home" ] && [ -f "$zdmuser_home/zdmhome/bin/zdmcli" ]; then
                export ZDM_HOME="$zdmuser_home/zdmhome"
                print_success "Detected ZDM_HOME from zdmuser home: $ZDM_HOME"
            fi
        fi
    fi
    
    # Detect JAVA_HOME
    if [ -z "${JAVA_HOME:-}" ]; then
        # Method 1: Check alternatives
        if command -v java >/dev/null 2>&1; then
            local java_path
            java_path=$(readlink -f "$(command -v java)" 2>/dev/null)
            if [ -n "$java_path" ]; then
                export JAVA_HOME="${java_path%/bin/java}"
                print_success "Detected JAVA_HOME from alternatives: $JAVA_HOME"
            fi
        fi
        
        # Method 2: Search common Java paths
        if [ -z "${JAVA_HOME:-}" ]; then
            for path in /usr/java/latest /usr/java/jdk* /usr/lib/jvm/java-* /opt/java/jdk* /usr/lib/jvm/jre*; do
                if [ -d "$path" ] && [ -f "$path/bin/java" ]; then
                    export JAVA_HOME="$path"
                    print_success "Detected JAVA_HOME from common path: $JAVA_HOME"
                    break
                fi
            done
        fi
    fi
    
    # Apply explicit overrides if provided (highest priority)
    [ -n "${ZDM_HOME_OVERRIDE:-}" ] && export ZDM_HOME="$ZDM_HOME_OVERRIDE"
    [ -n "${JAVA_HOME_OVERRIDE:-}" ] && export JAVA_HOME="$JAVA_HOME_OVERRIDE"
    
    # Validate ZDM_HOME
    if [ -z "${ZDM_HOME:-}" ]; then
        print_warning "ZDM_HOME not detected - ZDM-specific checks will be skipped"
    fi
    
    return 0
}

# Execute ZDM CLI command as zdmuser
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

#===============================================================================
# DISCOVERY SECTIONS
#===============================================================================

discover_os_info() {
    print_section "OS Information"
    {
        echo "=== OS INFORMATION ==="
        echo "Hostname: $(hostname -f 2>/dev/null || hostname)"
        echo "Short Hostname: $(hostname -s 2>/dev/null || hostname)"
        echo "Current User: $(whoami)"
        echo ""
        echo "Operating System:"
        cat /etc/os-release 2>/dev/null || cat /etc/redhat-release 2>/dev/null || uname -a
        echo ""
        echo "Kernel Version: $(uname -r)"
        echo "Architecture: $(uname -m)"
        echo ""
        log_section_result "OS Information" "success"
    } 2>&1 || log_section_result "OS Information" "failed"
}

discover_zdm_installation() {
    print_section "ZDM Installation"
    {
        echo "=== ZDM INSTALLATION ==="
        echo "ZDM_HOME: ${ZDM_HOME:-NOT SET}"
        echo ""
        
        if [ -n "${ZDM_HOME:-}" ] && [ -d "$ZDM_HOME" ]; then
            echo "ZDM Directory Contents:"
            ls -la "$ZDM_HOME" 2>/dev/null
            echo ""
            
            echo "=== ZDM VERSION ==="
            if [ -f "$ZDM_HOME/bin/zdmcli" ]; then
                run_zdm_cmd "zdmcli -version" || echo "  Unable to get ZDM version"
            fi
            echo ""
            
            echo "=== ZDM SERVICE STATUS ==="
            run_zdm_cmd "zdmcli query zdmserver" || echo "  Unable to query ZDM service"
            echo ""
            
            echo "=== ACTIVE MIGRATION JOBS ==="
            run_zdm_cmd "zdmcli query job" || echo "  No jobs found or unable to query"
            echo ""
        else
            echo "  ZDM_HOME not set or directory not found"
        fi
        log_section_result "ZDM Installation" "success"
    } 2>&1 || log_section_result "ZDM Installation" "failed"
}

discover_java_config() {
    print_section "Java Configuration"
    {
        echo "=== JAVA CONFIGURATION ==="
        echo "JAVA_HOME: ${JAVA_HOME:-NOT SET}"
        echo ""
        
        echo "Java Version:"
        if [ -n "${JAVA_HOME:-}" ] && [ -f "$JAVA_HOME/bin/java" ]; then
            $JAVA_HOME/bin/java -version 2>&1
        elif command -v java >/dev/null 2>&1; then
            java -version 2>&1
        else
            echo "  Java not found"
        fi
        echo ""
        log_section_result "Java Configuration" "success"
    } 2>&1 || log_section_result "Java Configuration" "failed"
}

discover_oci_config() {
    print_section "OCI CLI Configuration"
    {
        echo "=== OCI CLI VERSION ==="
        oci --version 2>&1 || echo "  OCI CLI not installed"
        echo ""
        
        echo "=== OCI CONFIG FILE ==="
        local oci_config="${OCI_CONFIG_PATH:-$HOME/.oci/config}"
        echo "Config Path: $oci_config"
        
        if [ -f "$oci_config" ]; then
            echo ""
            echo "Configured Profiles:"
            grep '^\[' "$oci_config" 2>/dev/null
            echo ""
            echo "Configured Regions:"
            grep 'region' "$oci_config" 2>/dev/null
            echo ""
            echo "Config Contents (sensitive data masked):"
            cat "$oci_config" 2>/dev/null | \
                sed 's/key_file=.*/key_file=***MASKED***/g' | \
                sed 's/fingerprint=.*/fingerprint=***MASKED***/g' | \
                sed 's/pass_phrase=.*/pass_phrase=***MASKED***/g'
        else
            echo "  OCI config file not found"
        fi
        echo ""
        
        echo "=== API KEY FILE ==="
        local api_key_dir="${OCI_CONFIG_PATH:-$HOME/.oci}"
        api_key_dir=$(dirname "$api_key_dir")
        if [ -d "$api_key_dir" ]; then
            echo "Files in $api_key_dir:"
            ls -la "$api_key_dir" 2>/dev/null | grep -v '^total'
        else
            echo "  OCI directory not found"
        fi
        echo ""
        
        echo "=== OCI CONNECTIVITY TEST ==="
        if command -v oci >/dev/null 2>&1; then
            echo "Testing OCI connectivity..."
            timeout 15 oci iam region list --output table 2>&1 | head -20 || echo "  OCI connectivity test failed or timed out"
        else
            echo "  OCI CLI not available"
        fi
        echo ""
        log_section_result "OCI Configuration" "success"
    } 2>&1 || log_section_result "OCI Configuration" "failed"
}

discover_ssh_config() {
    print_section "SSH Configuration"
    {
        echo "=== SSH DIRECTORY (Current User) ==="
        echo "User: $(whoami)"
        if [ -d ~/.ssh ]; then
            echo "SSH directory contents:"
            ls -la ~/.ssh/ 2>/dev/null
            echo ""
            echo "Public Keys:"
            for pubkey in ~/.ssh/*.pub; do
                if [ -f "$pubkey" ]; then
                    echo "  $pubkey:"
                    cat "$pubkey"
                fi
            done
        else
            echo "  No .ssh directory found"
        fi
        echo ""
        
        echo "=== SSH DIRECTORY (zdmuser) ==="
        local zdmuser_home
        zdmuser_home=$(getent passwd "$ZDM_USER" 2>/dev/null | cut -d: -f6)
        if [ -n "$zdmuser_home" ] && [ -d "$zdmuser_home/.ssh" ]; then
            echo "User: $ZDM_USER"
            echo "SSH directory contents:"
            sudo -u "$ZDM_USER" ls -la "$zdmuser_home/.ssh/" 2>/dev/null || ls -la "$zdmuser_home/.ssh/" 2>/dev/null
        else
            echo "  zdmuser SSH directory not found or not accessible"
        fi
        echo ""
        log_section_result "SSH Configuration" "success"
    } 2>&1 || log_section_result "SSH Configuration" "failed"
}

discover_credentials() {
    print_section "Credential Files Search"
    {
        echo "=== SEARCHING FOR CREDENTIAL/PASSWORD FILES ==="
        echo "Note: This search looks for files that might contain credentials"
        echo ""
        
        # Search in common locations
        echo "Files containing 'password' or 'credential' in name:"
        find /home -type f \( -name "*password*" -o -name "*credential*" -o -name "*secret*" \) 2>/dev/null | head -20 || echo "  None found"
        echo ""
        
        echo "Wallet files:"
        find /home -type f -name "*.p12" -o -name "*wallet*" 2>/dev/null | head -20 || echo "  None found"
        echo ""
        
        echo "Response files (.rsp):"
        find /home -type f -name "*.rsp" 2>/dev/null | head -20 || echo "  None found"
        echo ""
        log_section_result "Credential Files" "success"
    } 2>&1 || log_section_result "Credential Files" "failed"
}

discover_network_config() {
    print_section "Network Configuration"
    {
        echo "=== IP ADDRESSES ==="
        ip addr show 2>/dev/null | grep 'inet ' | awk '{print "  " $2}' || ifconfig 2>/dev/null | grep 'inet ' | awk '{print "  " $2}'
        echo ""
        
        echo "=== ROUTING TABLE ==="
        ip route show 2>/dev/null || netstat -rn 2>/dev/null || route -n 2>/dev/null
        echo ""
        
        echo "=== DNS CONFIGURATION ==="
        echo "Nameservers:"
        cat /etc/resolv.conf 2>/dev/null | grep -v '^#' | grep -v '^$'
        echo ""
        
        echo "=== HOSTNAMES ==="
        echo "/etc/hosts (relevant entries):"
        cat /etc/hosts 2>/dev/null | grep -v '^#' | grep -v '^$' | head -20
        echo ""
        log_section_result "Network Configuration" "success"
    } 2>&1 || log_section_result "Network Configuration" "failed"
}

discover_zdm_logs() {
    print_section "ZDM Logs"
    {
        echo "=== ZDM LOG DIRECTORY ==="
        if [ -n "${ZDM_HOME:-}" ]; then
            local log_dir="$ZDM_HOME/log"
            if [ -d "$log_dir" ]; then
                echo "Log directory: $log_dir"
                echo "Contents:"
                ls -la "$log_dir" 2>/dev/null | head -30
                echo ""
                echo "Most recent log files:"
                ls -lt "$log_dir"/*.log 2>/dev/null | head -10
            else
                echo "  Log directory not found at $log_dir"
            fi
        else
            echo "  ZDM_HOME not set"
        fi
        echo ""
        log_section_result "ZDM Logs" "success"
    } 2>&1 || log_section_result "ZDM Logs" "failed"
}

#===============================================================================
# ADDITIONAL DISCOVERY (Project-specific requirements)
#===============================================================================

discover_disk_space() {
    print_section "Disk Space for ZDM Operations"
    {
        echo "=== DISK SPACE ANALYSIS ==="
        echo "Minimum recommended: 50GB for ZDM operations"
        echo ""
        df -h
        echo ""
        
        echo "=== ZDM HOME DISK SPACE ==="
        if [ -n "${ZDM_HOME:-}" ]; then
            local zdm_mount
            zdm_mount=$(df "$ZDM_HOME" 2>/dev/null | tail -1)
            echo "$zdm_mount"
            
            local avail_gb
            avail_gb=$(df -BG "$ZDM_HOME" 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')
            echo ""
            if [ -n "$avail_gb" ]; then
                if [ "$avail_gb" -ge 50 ]; then
                    echo "✓ Available space ($avail_gb GB) meets minimum requirement (50GB)"
                else
                    echo "⚠ WARNING: Available space ($avail_gb GB) is below minimum (50GB)"
                fi
            fi
        else
            echo "  ZDM_HOME not set - checking /home directory"
            df -BG /home 2>/dev/null | tail -1
        fi
        echo ""
        
        echo "=== TMP DIRECTORY SPACE ==="
        df -h /tmp 2>/dev/null
        echo ""
        log_section_result "Disk Space" "success"
    } 2>&1 || log_section_result "Disk Space" "failed"
}

discover_network_latency() {
    print_section "Network Latency Tests"
    {
        local source_host="proddb01.corp.example.com"
        local target_host="proddb-oda.eastus.azure.example.com"
        
        echo "=== PING TEST TO SOURCE DATABASE ==="
        echo "Host: $source_host"
        ping -c 5 "$source_host" 2>&1 || echo "  Unable to ping source host"
        echo ""
        
        echo "=== PING TEST TO TARGET DATABASE ==="
        echo "Host: $target_host"
        ping -c 5 "$target_host" 2>&1 || echo "  Unable to ping target host"
        echo ""
        
        echo "=== DNS RESOLUTION TEST ==="
        echo "Source: $(nslookup "$source_host" 2>&1 | grep 'Address' | tail -1 || echo 'Resolution failed')"
        echo "Target: $(nslookup "$target_host" 2>&1 | grep 'Address' | tail -1 || echo 'Resolution failed')"
        echo ""
        
        echo "=== TRACEROUTE TO TARGET (first 15 hops) ==="
        traceroute -m 15 "$target_host" 2>&1 | head -20 || echo "  Traceroute not available or failed"
        echo ""
        log_section_result "Network Latency" "success"
    } 2>&1 || log_section_result "Network Latency" "failed"
}

#===============================================================================
# JSON OUTPUT GENERATION
#===============================================================================

generate_json_summary() {
    print_section "Generating JSON Summary"
    
    local zdm_version java_version oci_version
    local disk_avail_gb
    
    if [ -n "${ZDM_HOME:-}" ] && [ -f "$ZDM_HOME/bin/zdmcli" ]; then
        zdm_version=$(run_zdm_cmd "zdmcli -version" 2>/dev/null | head -1 || echo "unknown")
    else
        zdm_version="not_installed"
    fi
    
    if command -v java >/dev/null 2>&1; then
        java_version=$(java -version 2>&1 | head -1 || echo "unknown")
    else
        java_version="not_installed"
    fi
    
    if command -v oci >/dev/null 2>&1; then
        oci_version=$(oci --version 2>&1 || echo "unknown")
    else
        oci_version="not_installed"
    fi
    
    if [ -n "${ZDM_HOME:-}" ]; then
        disk_avail_gb=$(df -BG "$ZDM_HOME" 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G' || echo "0")
    else
        disk_avail_gb=$(df -BG /home 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G' || echo "0")
    fi
    
    cat > "$JSON_FILE" << EOJSON
{
    "discovery_type": "zdm_server",
    "discovery_timestamp": "$(date -Iseconds)",
    "hostname": "$HOSTNAME",
    "current_user": "$(whoami)",
    "zdm": {
        "zdm_home": "${ZDM_HOME:-not_set}",
        "version": "$zdm_version"
    },
    "java": {
        "java_home": "${JAVA_HOME:-not_set}",
        "version": "$java_version"
    },
    "oci_cli": {
        "version": "$oci_version"
    },
    "storage": {
        "available_gb": ${disk_avail_gb:-0},
        "meets_minimum": $([ "${disk_avail_gb:-0}" -ge 50 ] && echo "true" || echo "false")
    },
    "discovery_status": {
        "successful_sections": [$(printf '"%s",' "${SUCCESS_SECTIONS[@]}" | sed 's/,$//')]
        "failed_sections": [$(printf '"%s",' "${FAILED_SECTIONS[@]}" | sed 's/,$//')]
    }
}
EOJSON
    
    print_success "JSON summary written to: $JSON_FILE"
}

#===============================================================================
# MAIN EXECUTION
#===============================================================================

main() {
    print_header "ZDM Server Discovery"
    echo "Project: PRODDB Migration to Oracle Database@Azure"
    echo "Timestamp: $(date)"
    echo "Output File: $OUTPUT_FILE"
    echo ""
    
    # Detect ZDM environment
    detect_zdm_env
    
    # Run all discovery sections and capture to output file
    {
        echo "==============================================================================="
        echo "ZDM SERVER DISCOVERY REPORT"
        echo "==============================================================================="
        echo "Project: PRODDB Migration to Oracle Database@Azure"
        echo "Hostname: $HOSTNAME"
        echo "Current User: $(whoami)"
        echo "Timestamp: $(date)"
        echo "ZDM_HOME: ${ZDM_HOME:-NOT SET}"
        echo "JAVA_HOME: ${JAVA_HOME:-NOT SET}"
        echo "==============================================================================="
        echo ""
        
        # Standard discovery sections
        discover_os_info
        discover_zdm_installation
        discover_java_config
        discover_oci_config
        discover_ssh_config
        discover_credentials
        discover_network_config
        discover_zdm_logs
        
        # Additional discovery (project-specific)
        discover_disk_space
        discover_network_latency
        
        echo ""
        echo "==============================================================================="
        echo "DISCOVERY SUMMARY"
        echo "==============================================================================="
        echo "Successful Sections: ${#SUCCESS_SECTIONS[@]}"
        echo "Failed Sections: ${#FAILED_SECTIONS[@]}"
        if [ ${#FAILED_SECTIONS[@]} -gt 0 ]; then
            echo "Failed: ${FAILED_SECTIONS[*]}"
        fi
        echo "==============================================================================="
        
    } 2>&1 | tee "$OUTPUT_FILE"
    
    # Generate JSON summary
    generate_json_summary
    
    print_header "Discovery Complete"
    echo "Text Report: $OUTPUT_FILE"
    echo "JSON Summary: $JSON_FILE"
    echo ""
    
    if [ ${#FAILED_SECTIONS[@]} -gt 0 ]; then
        print_warning "Some sections failed. Check the output for details."
        exit 1
    else
        print_success "All discovery sections completed successfully"
        exit 0
    fi
}

# Run main function
main "$@"
