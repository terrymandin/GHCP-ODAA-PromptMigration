#!/bin/bash
#===============================================================================
# ZDM Server Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# ZDM Server: zdm-jumpbox.corp.example.com
#
# Purpose: Gather discovery information from the ZDM jumpbox server
#
# Usage: ./zdm_server_discovery.sh
#
# Output:
#   - zdm_server_discovery_<hostname>_<timestamp>.txt (human-readable report)
#   - zdm_server_discovery_<hostname>_<timestamp>.json (machine-parseable JSON)
#===============================================================================

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script variables
SCRIPT_VERSION="1.0.0"
HOSTNAME=$(hostname -s 2>/dev/null || hostname)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="./zdm_server_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_server_discovery_${HOSTNAME}_${TIMESTAMP}.json"

# User configuration - can be overridden via environment
ZDM_USER="${ZDM_USER:-zdmuser}"

# Error tracking
SECTION_ERRORS=0
TOTAL_ERRORS=0

#===============================================================================
# Functions
#===============================================================================

print_header() {
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}============================================================${NC}"
}

print_section() {
    echo -e "\n${BLUE}------------------------------------------------------------${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}------------------------------------------------------------${NC}"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info() {
    echo -e "${NC}$1${NC}"
}

# Auto-detect ZDM_HOME and JAVA_HOME
detect_zdm_env() {
    # If already set, use existing values
    if [ -n "${ZDM_HOME:-}" ] && [ -n "${JAVA_HOME:-}" ]; then
        return 0
    fi
    
    # Detect ZDM_HOME
    if [ -z "${ZDM_HOME:-}" ]; then
        # Check common ZDM installation locations
        for path in ~/zdmhome ~/zdm /opt/zdm /u01/zdm "$HOME/zdmhome" /home/*/zdmhome /home/zdmuser/zdmhome; do
            if [ -d "$path" ] && [ -f "$path/bin/zdmcli" ]; then
                export ZDM_HOME="$path"
                break
            fi
        done
    fi
    
    # Detect JAVA_HOME
    if [ -z "${JAVA_HOME:-}" ]; then
        # Method 1: Check alternatives
        if command -v java >/dev/null 2>&1; then
            local java_path
            java_path=$(readlink -f "$(command -v java)" 2>/dev/null)
            if [ -n "$java_path" ]; then
                export JAVA_HOME="${java_path%/bin/java}"
            fi
        fi
        
        # Method 2: Search common Java paths
        if [ -z "${JAVA_HOME:-}" ]; then
            for path in /usr/java/latest /usr/java/jdk* /usr/lib/jvm/java-* /opt/java/jdk*; do
                if [ -d "$path" ] && [ -f "$path/bin/java" ]; then
                    export JAVA_HOME="$path"
                    break
                fi
            done
        fi
    fi
}

# Apply explicit overrides if provided (highest priority)
apply_overrides() {
    [ -n "${ZDM_HOME_OVERRIDE:-}" ] && export ZDM_HOME="$ZDM_HOME_OVERRIDE"
    [ -n "${JAVA_HOME_OVERRIDE:-}" ] && export JAVA_HOME="$JAVA_HOME_OVERRIDE"
}

# Run ZDM CLI command
run_zdm_cmd() {
    local zdm_cmd="$1"
    if [ -n "${ZDM_HOME:-}" ]; then
        # Execute as zdmuser - use sudo if current user is not zdmuser
        if [ "$(whoami)" = "$ZDM_USER" ]; then
            $ZDM_HOME/bin/$zdm_cmd 2>/dev/null
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
    cat > "$JSON_FILE" <<EOF
{
  "discovery_type": "zdm_server",
  "hostname": "$HOSTNAME",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "script_version": "$SCRIPT_VERSION",
EOF
}

# Close JSON output
close_json() {
    # Remove trailing comma and close JSON
    sed -i '$ s/,$//' "$JSON_FILE" 2>/dev/null || true
    echo "}" >> "$JSON_FILE"
}

# Add JSON section
add_json() {
    local key="$1"
    local value="$2"
    local is_object="${3:-false}"
    
    if [ "$is_object" = "true" ]; then
        echo "  \"$key\": $value," >> "$JSON_FILE"
    else
        # Escape special characters in value
        value=$(echo "$value" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' | tr '\n' ' ')
        echo "  \"$key\": \"$value\"," >> "$JSON_FILE"
    fi
}

#===============================================================================
# Discovery Sections
#===============================================================================

discover_os_info() {
    print_section "OS INFORMATION"
    
    echo "Hostname: $HOSTNAME"
    echo "Current User: $(whoami)"
    
    echo ""
    echo "IP Addresses:"
    ip addr show 2>/dev/null | grep 'inet ' | awk '{print "  " $2}' || hostname -I 2>/dev/null | tr ' ' '\n' | sed 's/^/  /'
    
    echo ""
    echo "Operating System:"
    if [ -f /etc/os-release ]; then
        cat /etc/os-release | grep -E "^(NAME|VERSION|ID)=" | sed 's/^/  /'
    elif [ -f /etc/redhat-release ]; then
        echo "  $(cat /etc/redhat-release)"
    fi
    
    echo ""
    echo "Kernel Version: $(uname -r)"
    
    # Add to JSON
    add_json "hostname" "$HOSTNAME"
    add_json "current_user" "$(whoami)"
    add_json "os_version" "$(cat /etc/os-release 2>/dev/null | grep '^VERSION=' | cut -d= -f2 | tr -d '\"')"
}

discover_zdm_installation() {
    print_section "ZDM INSTALLATION"
    
    echo "ZDM_HOME: ${ZDM_HOME:-NOT SET}"
    
    if [ -n "${ZDM_HOME:-}" ] && [ -d "${ZDM_HOME}" ]; then
        echo ""
        echo "ZDM Version:"
        run_zdm_cmd "zdmcli -version" || echo "  Unable to get ZDM version"
        
        echo ""
        echo "ZDM Service Status:"
        run_zdm_cmd "zdmservice status" || echo "  ZDM service status check failed"
        
        echo ""
        echo "Active Migration Jobs:"
        run_zdm_cmd "zdmcli query job -jobtype migration" || echo "  No active jobs or query failed"
        
        add_json "zdm_home" "${ZDM_HOME}"
        add_json "zdm_installed" "true"
    else
        echo "  ZDM not found"
        add_json "zdm_installed" "false"
    fi
}

discover_java() {
    print_section "JAVA CONFIGURATION"
    
    echo "JAVA_HOME: ${JAVA_HOME:-NOT SET}"
    
    echo ""
    echo "Java Version:"
    if [ -n "${JAVA_HOME:-}" ] && [ -f "$JAVA_HOME/bin/java" ]; then
        $JAVA_HOME/bin/java -version 2>&1 | head -3
    elif command -v java >/dev/null 2>&1; then
        java -version 2>&1 | head -3
    else
        echo "  Java not found"
    fi
    
    add_json "java_home" "${JAVA_HOME:-}"
}

discover_oci_cli() {
    print_section "OCI CLI CONFIGURATION"
    
    echo "OCI CLI Version:"
    oci --version 2>/dev/null || echo "  OCI CLI not installed"
    
    echo ""
    echo "OCI Config Location:"
    local oci_config="${OCI_CONFIG_FILE:-$HOME/.oci/config}"
    if [ -f "$oci_config" ]; then
        echo "  Config file: $oci_config"
        echo ""
        echo "  Profiles:"
        grep '^\[' "$oci_config" 2>/dev/null | sed 's/^/    /'
        
        echo ""
        echo "  Regions configured:"
        grep 'region=' "$oci_config" 2>/dev/null | sed 's/^/    /'
        
        echo ""
        echo "  Config contents (sensitive data masked):"
        cat "$oci_config" 2>/dev/null | sed 's/\(key_file\|fingerprint\|tenancy\|user\)=.*/\1=***MASKED***/' | sed 's/^/    /'
    else
        echo "  OCI config not found at $oci_config"
    fi
    
    echo ""
    echo "OCI API Key Files:"
    if [ -d ~/.oci ]; then
        ls -la ~/.oci/*.pem 2>/dev/null | sed 's/^/  /' || echo "  No PEM files found in ~/.oci/"
    fi
    
    echo ""
    echo "OCI Connectivity Test:"
    oci iam region list --query 'data[0].name' --raw-output 2>/dev/null && echo "  OCI connectivity: OK" || echo "  OCI connectivity: FAILED or not configured"
    
    add_json "oci_cli_installed" "$(command -v oci >/dev/null 2>&1 && echo 'true' || echo 'false')"
}

discover_ssh() {
    print_section "SSH CONFIGURATION"
    
    echo "SSH Directory Contents:"
    if [ -d ~/.ssh ]; then
        ls -la ~/.ssh/ 2>/dev/null | head -20
    else
        echo "  ~/.ssh not found for current user"
    fi
    
    echo ""
    echo "Available SSH Keys:"
    for key in ~/.ssh/*.pub; do
        if [ -f "$key" ]; then
            local private_key="${key%.pub}"
            echo "  Public: $key"
            if [ -f "$private_key" ]; then
                echo "    Private: $private_key (exists)"
            else
                echo "    Private: NOT FOUND"
            fi
        fi
    done
    
    echo ""
    echo "SSH Config (~/.ssh/config):"
    if [ -f ~/.ssh/config ]; then
        cat ~/.ssh/config 2>/dev/null | head -30 | sed 's/^/  /'
    else
        echo "  ~/.ssh/config not found"
    fi
}

discover_credentials() {
    print_section "CREDENTIAL FILES SEARCH"
    
    echo "Searching for potential credential files..."
    echo ""
    
    echo "Files containing 'password' in name (in home directory):"
    find ~ -maxdepth 3 -name "*password*" -o -name "*passwd*" -o -name "*credential*" -o -name "*.wallet" 2>/dev/null | head -20 | sed 's/^/  /'
    
    echo ""
    echo "ZDM Credential Store:"
    if [ -n "${ZDM_HOME:-}" ] && [ -d "$ZDM_HOME/crsdata" ]; then
        find "$ZDM_HOME/crsdata" -name "*wallet*" -o -name "*credential*" 2>/dev/null | head -10 | sed 's/^/  /'
    else
        echo "  ZDM credential store not found"
    fi
}

discover_network() {
    print_section "NETWORK CONFIGURATION"
    
    echo "IP Addresses:"
    ip addr show 2>/dev/null | grep 'inet ' | awk '{print "  " $2}'
    
    echo ""
    echo "Routing Table:"
    ip route 2>/dev/null | head -10 | sed 's/^/  /' || route -n 2>/dev/null | head -10 | sed 's/^/  /'
    
    echo ""
    echo "DNS Configuration:"
    if [ -f /etc/resolv.conf ]; then
        grep -v '^#' /etc/resolv.conf | grep -v '^$' | sed 's/^/  /'
    fi
}

discover_zdm_logs() {
    print_section "ZDM LOGS"
    
    if [ -n "${ZDM_HOME:-}" ]; then
        local log_dir="$ZDM_HOME/logs"
        if [ -d "$log_dir" ]; then
            echo "Log Directory: $log_dir"
            echo ""
            echo "Recent Log Files:"
            ls -lt "$log_dir"/*.log 2>/dev/null | head -10 | sed 's/^/  /'
        else
            echo "  Log directory not found at $log_dir"
        fi
        
        # Check for job-specific logs
        local job_log_dir="$ZDM_HOME/chkbase"
        if [ -d "$job_log_dir" ]; then
            echo ""
            echo "Job Directories:"
            ls -lt "$job_log_dir" 2>/dev/null | head -10 | sed 's/^/  /'
        fi
    else
        echo "  ZDM_HOME not set - cannot locate logs"
    fi
}

# Additional discovery for PRODDB migration project
discover_disk_space() {
    print_section "DISK SPACE FOR ZDM OPERATIONS"
    
    echo "Disk Space Usage:"
    df -h | grep -v tmpfs
    
    echo ""
    echo "ZDM Home Disk Space:"
    if [ -n "${ZDM_HOME:-}" ]; then
        local zdm_mount
        zdm_mount=$(df "$ZDM_HOME" 2>/dev/null | tail -1)
        echo "  ZDM_HOME: $ZDM_HOME"
        echo "  Mount Info: $zdm_mount"
        
        local available_gb
        available_gb=$(df -BG "$ZDM_HOME" 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')
        echo "  Available: ${available_gb}GB"
        
        if [ -n "$available_gb" ] && [ "$available_gb" -ge 50 ]; then
            print_success "Sufficient disk space (>= 50GB recommended)"
        else
            print_warning "Low disk space - 50GB recommended for ZDM operations"
        fi
    else
        echo "  ZDM_HOME not set"
    fi
    
    echo ""
    echo "Home Directory Space:"
    du -sh ~ 2>/dev/null || echo "  Unable to determine home directory usage"
}

discover_network_latency() {
    print_section "NETWORK LATENCY TESTS"
    
    # Source server ping test
    local source_host="proddb01.corp.example.com"
    echo "Ping to Source Database Server ($source_host):"
    ping -c 3 "$source_host" 2>/dev/null | tail -4 || echo "  Ping to $source_host failed"
    
    echo ""
    
    # Target server ping test
    local target_host="proddb-oda.eastus.azure.example.com"
    echo "Ping to Target Database Server ($target_host):"
    ping -c 3 "$target_host" 2>/dev/null | tail -4 || echo "  Ping to $target_host failed"
    
    echo ""
    echo "SSH Connectivity Tests:"
    echo "  Source: Testing SSH port 22 to $source_host..."
    timeout 5 bash -c "echo >/dev/tcp/$source_host/22" 2>/dev/null && echo "    Port 22: OPEN" || echo "    Port 22: CLOSED or timeout"
    
    echo "  Target: Testing SSH port 22 to $target_host..."
    timeout 5 bash -c "echo >/dev/tcp/$target_host/22" 2>/dev/null && echo "    Port 22: OPEN" || echo "    Port 22: CLOSED or timeout"
    
    echo ""
    echo "Database Port Tests (1521):"
    echo "  Source: Testing port 1521 to $source_host..."
    timeout 5 bash -c "echo >/dev/tcp/$source_host/1521" 2>/dev/null && echo "    Port 1521: OPEN" || echo "    Port 1521: CLOSED or timeout"
    
    echo "  Target: Testing port 1521 to $target_host..."
    timeout 5 bash -c "echo >/dev/tcp/$target_host/1521" 2>/dev/null && echo "    Port 1521: OPEN" || echo "    Port 1521: CLOSED or timeout"
}

#===============================================================================
# Main Execution
#===============================================================================

main() {
    # Initialize environment
    detect_zdm_env
    apply_overrides
    
    # Start output file
    print_header "ZDM Server Discovery Report" | tee "$OUTPUT_FILE"
    echo "Generated: $(date)" | tee -a "$OUTPUT_FILE"
    echo "Hostname: $HOSTNAME" | tee -a "$OUTPUT_FILE"
    echo "Script Version: $SCRIPT_VERSION" | tee -a "$OUTPUT_FILE"
    echo "" | tee -a "$OUTPUT_FILE"
    
    # Initialize JSON
    init_json
    
    # Run discovery sections (continue on failure)
    {
        discover_os_info || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_zdm_installation || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_java || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_oci_cli || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_ssh || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_credentials || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_network || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_zdm_logs || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        
        # Additional discovery for PRODDB project
        discover_disk_space || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_network_latency || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    } 2>&1 | tee -a "$OUTPUT_FILE"
    
    # Add errors to JSON and close
    add_json "section_errors" "$SECTION_ERRORS"
    close_json
    
    # Summary
    echo "" | tee -a "$OUTPUT_FILE"
    print_header "DISCOVERY COMPLETE" | tee -a "$OUTPUT_FILE"
    echo "Text Report: $OUTPUT_FILE" | tee -a "$OUTPUT_FILE"
    echo "JSON Summary: $JSON_FILE" | tee -a "$OUTPUT_FILE"
    
    if [ $SECTION_ERRORS -gt 0 ]; then
        print_warning "$SECTION_ERRORS section(s) had errors" | tee -a "$OUTPUT_FILE"
    else
        print_success "All sections completed successfully" | tee -a "$OUTPUT_FILE"
    fi
}

# Run main function
main "$@"
