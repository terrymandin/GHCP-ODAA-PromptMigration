#!/bin/bash
# =============================================================================
# ZDM Server Discovery Script
# =============================================================================
# Project: PRODDB Migration to Oracle Database@Azure
# Target Server: zdm-jumpbox.corp.example.com
# Generated: 2026-01-29
# =============================================================================
# This script discovers the ZDM jumpbox configuration for ZDM migration.
# It gathers ZDM installation, OCI CLI, SSH, and network information.
# =============================================================================

# NO set -e - We want to continue even if some checks fail
SECTION_ERRORS=0

# =============================================================================
# Color Output
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Environment Variable Discovery
# =============================================================================
# CRITICAL: Handle environment variables in non-interactive SSH sessions
# .bashrc often has guards like '[ -z "$PS1" ] && return' that skip non-interactive shells

# Method 1: Accept explicit overrides (passed from orchestration script)
[ -n "${ZDM_HOME_OVERRIDE:-}" ] && export ZDM_HOME="$ZDM_HOME_OVERRIDE"
[ -n "${JAVA_HOME_OVERRIDE:-}" ] && export JAVA_HOME="$JAVA_HOME_OVERRIDE"

# Method 2: Extract export statements from profiles (bypasses interactive guards)
for profile in /etc/profile ~/.bash_profile ~/.bashrc; do
    if [ -f "$profile" ]; then
        eval "$(grep -E '^export\s+(ZDM_HOME|JAVA_HOME|PATH)=' "$profile" 2>/dev/null)" || true
    fi
done

# Method 3: Auto-detect ZDM and Java environments
detect_zdm_env() {
    # If already set, use existing values
    if [ -n "${ZDM_HOME:-}" ]; then
        return 0
    fi
    
    # Search common ZDM installation paths
    for zdm_path in ~/zdmhome ~/zdm /home/*/zdmhome /opt/zdm* /u01/app/zdm* "$HOME/zdmhome"; do
        if [ -d "$zdm_path" ] && [ -f "$zdm_path/bin/zdmcli" ]; then
            export ZDM_HOME="$zdm_path"
            break
        fi
    done
}

detect_java_env() {
    # If already set, use existing value
    if [ -n "${JAVA_HOME:-}" ]; then
        return 0
    fi
    
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
}

detect_zdm_env
detect_java_env

# Update PATH
[ -n "$ZDM_HOME" ] && export PATH="$ZDM_HOME/bin:$PATH"
[ -n "$JAVA_HOME" ] && export PATH="$JAVA_HOME/bin:$PATH"

# =============================================================================
# Output Configuration
# =============================================================================
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname)
OUTPUT_FILE="./zdm_server_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_server_discovery_${HOSTNAME}_${TIMESTAMP}.json"

# Project-specific configuration for network tests
SOURCE_HOST="proddb01.corp.example.com"
TARGET_HOST="proddb-oda.eastus.azure.example.com"

# =============================================================================
# Helper Functions
# =============================================================================
log_section() {
    local section_name="$1"
    echo ""
    echo "================================================================================"
    echo " $section_name"
    echo "================================================================================"
    echo ""
}

log_subsection() {
    local subsection_name="$1"
    echo ""
    echo "--- $subsection_name ---"
    echo ""
}

# =============================================================================
# Discovery Functions
# =============================================================================

discover_os_info() {
    log_section "OS INFORMATION"
    
    echo "Hostname: $(hostname)"
    echo "FQDN: $(hostname -f 2>/dev/null || hostname)"
    echo "Current User: $(whoami)"
    echo ""
    
    log_subsection "IP Addresses"
    ip addr show 2>/dev/null | grep "inet " || ifconfig 2>/dev/null | grep "inet " || echo "Could not determine IP addresses"
    
    log_subsection "Operating System"
    if [ -f /etc/os-release ]; then
        cat /etc/os-release
    elif [ -f /etc/redhat-release ]; then
        cat /etc/redhat-release
    else
        uname -a
    fi
    
    log_subsection "Kernel"
    uname -r
    
    log_subsection "Uptime"
    uptime
}

discover_disk_space() {
    log_section "DISK SPACE FOR ZDM OPERATIONS"
    
    echo "Minimum 50GB recommended for ZDM operations"
    echo ""
    
    log_subsection "Filesystem Usage"
    df -h
    
    log_subsection "ZDM Home Disk Space"
    if [ -n "${ZDM_HOME:-}" ] && [ -d "$ZDM_HOME" ]; then
        df -h "$ZDM_HOME"
        echo ""
        echo "ZDM Home directory size:"
        du -sh "$ZDM_HOME" 2>/dev/null || echo "Could not determine ZDM_HOME size"
    else
        echo "ZDM_HOME not set or directory not found"
    fi
    
    log_subsection "Available Space Check"
    local root_avail=$(df -BG / 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//')
    local home_avail=$(df -BG ~ 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//')
    
    echo "Root (/) available: ${root_avail:-Unknown}GB"
    echo "Home (~) available: ${home_avail:-Unknown}GB"
    
    if [ "${home_avail:-0}" -lt 50 ] 2>/dev/null; then
        echo ""
        echo "WARNING: Less than 50GB available in home directory!"
    else
        echo ""
        echo "OK: Sufficient disk space available"
    fi
}

discover_zdm_installation() {
    log_section "ZDM INSTALLATION"
    
    echo "ZDM_HOME: ${ZDM_HOME:-NOT SET}"
    echo ""
    
    if [ -z "${ZDM_HOME:-}" ]; then
        echo "ZDM_HOME is not set. Searching for ZDM installation..."
        for zdm_path in ~/zdmhome ~/zdm /home/*/zdmhome /opt/zdm* /u01/app/zdm*; do
            if [ -d "$zdm_path" ] && [ -f "$zdm_path/bin/zdmcli" ]; then
                echo "Found ZDM installation at: $zdm_path"
                export ZDM_HOME="$zdm_path"
                break
            fi
        done
    fi
    
    if [ -n "${ZDM_HOME:-}" ] && [ -d "$ZDM_HOME" ]; then
        log_subsection "ZDM Version"
        if [ -f "$ZDM_HOME/bin/zdmcli" ]; then
            "$ZDM_HOME/bin/zdmcli" -version 2>&1 || echo "Could not determine ZDM version"
        else
            echo "zdmcli not found in $ZDM_HOME/bin/"
        fi
        
        log_subsection "ZDM Service Status"
        "$ZDM_HOME/bin/zdmservice" status 2>&1 || echo "Could not get ZDM service status"
        
        log_subsection "Active Migration Jobs"
        "$ZDM_HOME/bin/zdmcli" query job -jobtype MIGRATE 2>&1 || echo "Could not query migration jobs"
        
        log_subsection "ZDM Directory Contents"
        ls -la "$ZDM_HOME/" 2>/dev/null || echo "Could not list ZDM_HOME contents"
    else
        echo "ZDM installation not found"
    fi
}

discover_java() {
    log_section "JAVA CONFIGURATION"
    
    echo "JAVA_HOME: ${JAVA_HOME:-NOT SET}"
    echo ""
    
    log_subsection "Java Version"
    if command -v java >/dev/null 2>&1; then
        java -version 2>&1
    else
        echo "Java not found in PATH"
    fi
    
    log_subsection "Java Location"
    which java 2>/dev/null || echo "java not in PATH"
    
    if [ -n "${JAVA_HOME:-}" ]; then
        echo ""
        echo "JAVA_HOME contents:"
        ls -la "$JAVA_HOME/" 2>/dev/null | head -10 || echo "Could not list JAVA_HOME contents"
    fi
}

discover_oci_cli() {
    log_section "OCI CLI CONFIGURATION"
    
    log_subsection "OCI CLI Version"
    if command -v oci >/dev/null 2>&1; then
        oci --version 2>&1 || echo "Could not determine OCI CLI version"
    else
        echo "OCI CLI not installed"
        return 0
    fi
    
    log_subsection "OCI CLI Location"
    which oci 2>/dev/null
    
    log_subsection "OCI Config File"
    if [ -f ~/.oci/config ]; then
        echo "OCI config file found at ~/.oci/config"
        echo ""
        echo "Profiles configured:"
        grep "^\[" ~/.oci/config 2>/dev/null
        echo ""
        echo "Regions configured:"
        grep "^region" ~/.oci/config 2>/dev/null | sort -u
        echo ""
        echo "Config contents (sensitive data masked):"
        cat ~/.oci/config 2>/dev/null | sed 's/\(key_file=\).*/\1***MASKED***/' | sed 's/\(fingerprint=\).*/\1***MASKED***/' | sed 's/\(pass_phrase=\).*/\1***MASKED***/'
    else
        echo "OCI config file not found at ~/.oci/config"
    fi
    
    log_subsection "OCI API Key Files"
    if [ -d ~/.oci ]; then
        echo "Contents of ~/.oci/:"
        ls -la ~/.oci/ 2>/dev/null
        
        # Check for key files
        echo ""
        echo "Key files found:"
        find ~/.oci -name "*.pem" 2>/dev/null || echo "No .pem files found"
    else
        echo "~/.oci directory not found"
    fi
    
    log_subsection "OCI Connectivity Test"
    if command -v oci >/dev/null 2>&1; then
        echo "Testing OCI API connectivity..."
        oci iam region list --output table 2>&1 | head -15 || echo "OCI connectivity test failed"
    else
        echo "OCI CLI not available for connectivity test"
    fi
}

discover_ssh_config() {
    log_section "SSH CONFIGURATION"
    
    log_subsection "SSH Directory Contents"
    if [ -d ~/.ssh ]; then
        ls -la ~/.ssh/ 2>/dev/null
    else
        echo "~/.ssh directory not found"
    fi
    
    log_subsection "Available SSH Keys (Private)"
    find ~/.ssh -type f ! -name "*.pub" ! -name "known_hosts" ! -name "authorized_keys" ! -name "config" 2>/dev/null | while read key; do
        if [ -f "$key" ]; then
            echo "$key"
            # Check if it's a valid private key
            head -1 "$key" 2>/dev/null | grep -q "PRIVATE KEY" && echo "  -> Valid private key format" || echo "  -> Unknown format"
        fi
    done
    
    log_subsection "Available SSH Keys (Public)"
    ls -la ~/.ssh/*.pub 2>/dev/null || echo "No public key files found"
    
    log_subsection "SSH Config"
    if [ -f ~/.ssh/config ]; then
        echo "SSH config file found:"
        cat ~/.ssh/config 2>/dev/null
    else
        echo "No ~/.ssh/config file found"
    fi
    
    log_subsection "SSH Agent Status"
    ssh-add -l 2>&1 || echo "SSH agent not running or no keys loaded"
}

discover_credentials() {
    log_section "CREDENTIAL FILES"
    
    log_subsection "Searching for credential files"
    echo "Note: This search looks for files that might contain credentials."
    echo "Review these files to ensure they are properly secured."
    echo ""
    
    # Search for common credential file patterns
    find ~ -maxdepth 3 \( -name "*password*" -o -name "*credential*" -o -name "*secret*" -o -name "*.wallet" \) -type f 2>/dev/null | head -20
    
    log_subsection "ZDM Credential Store"
    if [ -n "${ZDM_HOME:-}" ] && [ -d "$ZDM_HOME" ]; then
        find "$ZDM_HOME" -name "*wallet*" -o -name "*credential*" 2>/dev/null | head -10
    fi
}

discover_network_config() {
    log_section "NETWORK CONFIGURATION"
    
    log_subsection "IP Addresses"
    ip addr show 2>/dev/null | grep "inet " || ifconfig 2>/dev/null | grep "inet "
    
    log_subsection "Routing Table"
    ip route show 2>/dev/null || route -n 2>/dev/null || echo "Could not get routing table"
    
    log_subsection "DNS Configuration"
    cat /etc/resolv.conf 2>/dev/null || echo "Could not read /etc/resolv.conf"
    
    log_subsection "Hosts File"
    cat /etc/hosts 2>/dev/null | grep -v "^#" | grep -v "^$" || echo "Could not read /etc/hosts"
}

discover_network_latency() {
    log_section "NETWORK LATENCY TESTS"
    
    log_subsection "Ping to Source Database"
    echo "Testing connectivity to: $SOURCE_HOST"
    if ping -c 5 "$SOURCE_HOST" 2>&1; then
        echo ""
        echo "Latency summary:"
        ping -c 5 "$SOURCE_HOST" 2>&1 | tail -2
    else
        echo "WARNING: Ping to source ($SOURCE_HOST) failed"
        echo "This may be due to firewall rules blocking ICMP"
    fi
    
    echo ""
    
    log_subsection "Ping to Target Database"
    echo "Testing connectivity to: $TARGET_HOST"
    if ping -c 5 "$TARGET_HOST" 2>&1; then
        echo ""
        echo "Latency summary:"
        ping -c 5 "$TARGET_HOST" 2>&1 | tail -2
    else
        echo "WARNING: Ping to target ($TARGET_HOST) failed"
        echo "This may be due to firewall rules blocking ICMP"
    fi
    
    log_subsection "SSH Connectivity Test"
    echo "Testing SSH port connectivity..."
    
    echo -n "Source ($SOURCE_HOST:22): "
    timeout 5 bash -c "cat < /dev/null > /dev/tcp/$SOURCE_HOST/22" 2>/dev/null && echo "OPEN" || echo "CLOSED/FILTERED"
    
    echo -n "Target ($TARGET_HOST:22): "
    timeout 5 bash -c "cat < /dev/null > /dev/tcp/$TARGET_HOST/22" 2>/dev/null && echo "OPEN" || echo "CLOSED/FILTERED"
    
    log_subsection "Oracle Listener Connectivity Test"
    echo "Testing Oracle listener port connectivity..."
    
    echo -n "Source ($SOURCE_HOST:1521): "
    timeout 5 bash -c "cat < /dev/null > /dev/tcp/$SOURCE_HOST/1521" 2>/dev/null && echo "OPEN" || echo "CLOSED/FILTERED"
    
    echo -n "Target ($TARGET_HOST:1521): "
    timeout 5 bash -c "cat < /dev/null > /dev/tcp/$TARGET_HOST/1521" 2>/dev/null && echo "OPEN" || echo "CLOSED/FILTERED"
}

discover_zdm_logs() {
    log_section "ZDM LOGS"
    
    if [ -z "${ZDM_HOME:-}" ]; then
        echo "ZDM_HOME not set, cannot check logs"
        return 0
    fi
    
    log_subsection "Log Directory"
    local log_dir="$ZDM_HOME/rhp_logs"
    if [ -d "$log_dir" ]; then
        echo "Log directory: $log_dir"
        echo ""
        echo "Recent log files:"
        ls -lt "$log_dir"/*.log 2>/dev/null | head -10 || echo "No log files found"
        
        echo ""
        echo "Log directory size:"
        du -sh "$log_dir" 2>/dev/null
    else
        echo "Log directory not found at $log_dir"
    fi
    
    log_subsection "Service Log"
    local service_log="$ZDM_HOME/rhp_logs/zdmservice.log"
    if [ -f "$service_log" ]; then
        echo "Last 20 lines of zdmservice.log:"
        tail -20 "$service_log"
    else
        echo "zdmservice.log not found"
    fi
}

# =============================================================================
# JSON Summary Generation
# =============================================================================
generate_json_summary() {
    local zdm_version="UNKNOWN"
    if [ -n "${ZDM_HOME:-}" ] && [ -f "$ZDM_HOME/bin/zdmcli" ]; then
        zdm_version=$("$ZDM_HOME/bin/zdmcli" -version 2>/dev/null | head -1 || echo "UNKNOWN")
    fi
    
    local java_version="UNKNOWN"
    if command -v java >/dev/null 2>&1; then
        java_version=$(java -version 2>&1 | head -1 || echo "UNKNOWN")
    fi
    
    local oci_version="NOT INSTALLED"
    if command -v oci >/dev/null 2>&1; then
        oci_version=$(oci --version 2>&1 || echo "UNKNOWN")
    fi
    
    local disk_available=$(df -BG ~ 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//')
    
    cat > "$JSON_FILE" <<EOF
{
  "discovery_type": "zdm_server",
  "timestamp": "$TIMESTAMP",
  "hostname": "$HOSTNAME",
  "project": "PRODDB Migration to Oracle Database@Azure",
  "current_user": "$(whoami)",
  "zdm": {
    "zdm_home": "${ZDM_HOME:-NOT SET}",
    "version": "${zdm_version}"
  },
  "java": {
    "java_home": "${JAVA_HOME:-NOT SET}",
    "version": "${java_version}"
  },
  "oci_cli": {
    "version": "${oci_version}"
  },
  "disk_space": {
    "home_available_gb": "${disk_available:-UNKNOWN}"
  },
  "network_test_targets": {
    "source": "$SOURCE_HOST",
    "target": "$TARGET_HOST"
  },
  "section_errors": $SECTION_ERRORS
}
EOF
    echo "JSON summary saved to: $JSON_FILE"
}

# =============================================================================
# Main Execution
# =============================================================================
main() {
    echo "================================================================================"
    echo " ZDM Server Discovery"
    echo " Project: PRODDB Migration to Oracle Database@Azure"
    echo " Server: zdm-jumpbox.corp.example.com"
    echo " Timestamp: $(date)"
    echo "================================================================================"
    
    # Run all discovery sections with error handling
    {
        discover_os_info || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_disk_space || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_zdm_installation || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_java || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_oci_cli || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_ssh_config || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_credentials || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_network_config || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_network_latency || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        discover_zdm_logs || SECTION_ERRORS=$((SECTION_ERRORS + 1))
        
    } 2>&1 | tee "$OUTPUT_FILE"
    
    # Generate JSON summary
    generate_json_summary
    
    echo ""
    echo "================================================================================"
    echo " DISCOVERY COMPLETE"
    echo "================================================================================"
    echo " Text report: $OUTPUT_FILE"
    echo " JSON summary: $JSON_FILE"
    echo " Sections with errors: $SECTION_ERRORS"
    echo "================================================================================"
}

# Run main
main

# Always exit 0 so orchestrator knows script completed
exit 0
