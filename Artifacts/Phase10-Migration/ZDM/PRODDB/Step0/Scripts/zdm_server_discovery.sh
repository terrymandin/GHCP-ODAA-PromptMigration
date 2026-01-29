#!/bin/bash
#===============================================================================
# ZDM Server Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# Target Server: zdm-jumpbox.corp.example.com
# Generated: 2026-01-29
#===============================================================================

set -e

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script variables
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname)
OUTPUT_FILE="/tmp/zdm_server_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_FILE="/tmp/zdm_server_discovery_${HOSTNAME}_${TIMESTAMP}.json"

#===============================================================================
# Functions
#===============================================================================

print_header() {
    echo -e "${BLUE}===============================================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${BLUE}===============================================================================${NC}"
}

print_section() {
    echo -e "\n${GREEN}>>> $1${NC}"
    echo "===============================================================================" >> "$OUTPUT_FILE"
    echo "$1" >> "$OUTPUT_FILE"
    echo "===============================================================================" >> "$OUTPUT_FILE"
}

print_info() {
    echo -e "${YELLOW}$1${NC}"
}

print_error() {
    echo -e "${RED}ERROR: $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

#===============================================================================
# Usage
#===============================================================================

usage() {
    echo "Usage: $0 [-h|--help]"
    echo ""
    echo "ZDM Server Discovery Script"
    echo "Run this script as the zdmuser on the ZDM jumpbox server."
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help message"
    echo ""
    echo "Output files:"
    echo "  Text report: /tmp/zdm_server_discovery_<hostname>_<timestamp>.txt"
    echo "  JSON summary: /tmp/zdm_server_discovery_<hostname>_<timestamp>.json"
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
    shift
done

#===============================================================================
# Main Script
#===============================================================================

print_header "ZDM Server Discovery Script"
print_info "Project: PRODDB Migration to Oracle Database@Azure"
print_info "Started: $(date)"
print_info "Output: $OUTPUT_FILE"

# Initialize output file
echo "ZDM Server Discovery Report" > "$OUTPUT_FILE"
echo "Generated: $(date)" >> "$OUTPUT_FILE"
echo "Hostname: $HOSTNAME" >> "$OUTPUT_FILE"
echo "Current User: $(whoami)" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Initialize JSON
echo "{" > "$JSON_FILE"
echo '  "discovery_type": "zdm_server",' >> "$JSON_FILE"
echo "  \"hostname\": \"$HOSTNAME\"," >> "$JSON_FILE"
echo "  \"current_user\": \"$(whoami)\"," >> "$JSON_FILE"
echo "  \"timestamp\": \"$(date -Iseconds)\"," >> "$JSON_FILE"

#-------------------------------------------------------------------------------
# OS Information
#-------------------------------------------------------------------------------
print_section "OS Information"

echo "Hostname: $(hostname)" | tee -a "$OUTPUT_FILE"
echo "Current User: $(whoami)" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Operating System:" | tee -a "$OUTPUT_FILE"
cat /etc/os-release 2>/dev/null | grep -E "^NAME=|^VERSION=" | tee -a "$OUTPUT_FILE"
uname -a | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Disk Space (Custom Request - Verify minimum 50GB)
#-------------------------------------------------------------------------------
print_section "Disk Space (Custom Discovery - Minimum 50GB Required)"

echo "Disk Space Overview:" | tee -a "$OUTPUT_FILE"
df -h | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "ZDM Operations Disk Space Check:" | tee -a "$OUTPUT_FILE"
# Check common ZDM working directories
for dir in "/home/zdmuser" "/u01" "/tmp" "/var"; do
    if [ -d "$dir" ]; then
        AVAIL_GB=$(df -BG "$dir" 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')
        if [ -n "$AVAIL_GB" ]; then
            if [ "$AVAIL_GB" -ge 50 ]; then
                echo -e "  ${GREEN}✓ $dir: ${AVAIL_GB}GB available (meets 50GB minimum)${NC}" | tee -a "$OUTPUT_FILE"
            else
                echo -e "  ${RED}✗ $dir: ${AVAIL_GB}GB available (BELOW 50GB minimum)${NC}" | tee -a "$OUTPUT_FILE"
            fi
        fi
    fi
done
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# ZDM Installation
#-------------------------------------------------------------------------------
print_section "ZDM Installation"

echo "ZDM_HOME: ${ZDM_HOME:-NOT SET}" | tee -a "$OUTPUT_FILE"

if [ -n "$ZDM_HOME" ] && [ -d "$ZDM_HOME" ]; then
    echo "" >> "$OUTPUT_FILE"
    echo "ZDM Version:" | tee -a "$OUTPUT_FILE"
    $ZDM_HOME/bin/zdmcli -version 2>/dev/null | tee -a "$OUTPUT_FILE" || echo "Unable to get ZDM version" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    echo "ZDM Service Status:" | tee -a "$OUTPUT_FILE"
    $ZDM_HOME/bin/zdmservice status 2>/dev/null | tee -a "$OUTPUT_FILE" || echo "Unable to get ZDM service status" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    echo "Active Migration Jobs:" | tee -a "$OUTPUT_FILE"
    $ZDM_HOME/bin/zdmcli query job -all 2>/dev/null | tee -a "$OUTPUT_FILE" || echo "No active jobs or unable to query jobs" >> "$OUTPUT_FILE"
else
    echo "ZDM_HOME not set or directory does not exist" | tee -a "$OUTPUT_FILE"
    
    # Try to find ZDM installation
    echo "" >> "$OUTPUT_FILE"
    echo "Searching for ZDM installation..." | tee -a "$OUTPUT_FILE"
    find /u01 /opt /home -name "zdmcli" -type f 2>/dev/null | head -5 | tee -a "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Java Configuration
#-------------------------------------------------------------------------------
print_section "Java Configuration"

echo "JAVA_HOME: ${JAVA_HOME:-NOT SET}" | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Java Version:" | tee -a "$OUTPUT_FILE"
java -version 2>&1 | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Java Location:" | tee -a "$OUTPUT_FILE"
which java 2>/dev/null | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# OCI CLI Configuration
#-------------------------------------------------------------------------------
print_section "OCI CLI Configuration"

echo "OCI CLI Version:" | tee -a "$OUTPUT_FILE"
oci --version 2>/dev/null | tee -a "$OUTPUT_FILE" || echo "OCI CLI not installed" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "OCI Config File:" | tee -a "$OUTPUT_FILE"
OCI_CONFIG_FILE="${OCI_CLI_CONFIG_FILE:-$HOME/.oci/config}"
if [ -f "$OCI_CONFIG_FILE" ]; then
    echo "Config file location: $OCI_CONFIG_FILE" | tee -a "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    echo "Configured Profiles:" | tee -a "$OUTPUT_FILE"
    grep "^\[" "$OCI_CONFIG_FILE" 2>/dev/null | tee -a "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    echo "Configured Regions:" | tee -a "$OUTPUT_FILE"
    grep "^region" "$OCI_CONFIG_FILE" 2>/dev/null | tee -a "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    echo "Config Details (masked):" | tee -a "$OUTPUT_FILE"
    grep -E "^\[|^region|^tenancy|^user|^fingerprint|^key_file" "$OCI_CONFIG_FILE" 2>/dev/null | \
        sed 's/\(tenancy=\).*/\1***MASKED***/' | \
        sed 's/\(user=\).*/\1***MASKED***/' | \
        sed 's/\(fingerprint=\).*/\1***MASKED***/' | tee -a "$OUTPUT_FILE"
else
    echo "OCI config file not found at $OCI_CONFIG_FILE" | tee -a "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

echo "API Key Files:" | tee -a "$OUTPUT_FILE"
if [ -d ~/.oci ]; then
    ls -la ~/.oci/*.pem 2>/dev/null | tee -a "$OUTPUT_FILE" || echo "No .pem files found in ~/.oci" >> "$OUTPUT_FILE"
else
    echo "~/.oci directory does not exist" | tee -a "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

echo "OCI Connectivity Test:" | tee -a "$OUTPUT_FILE"
oci os ns get 2>&1 | tee -a "$OUTPUT_FILE" || echo "OCI connectivity test failed" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# SSH Configuration
#-------------------------------------------------------------------------------
print_section "SSH Configuration"

echo "SSH Directory Contents:" | tee -a "$OUTPUT_FILE"
ls -la ~/.ssh/ 2>/dev/null | tee -a "$OUTPUT_FILE" || echo "~/.ssh directory not found" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Available SSH Keys:" | tee -a "$OUTPUT_FILE"
for keyfile in ~/.ssh/id_* ~/.ssh/*.pem ~/.ssh/*_key; do
    if [ -f "$keyfile" ]; then
        echo "  Found: $keyfile" | tee -a "$OUTPUT_FILE"
        # Check if public key exists
        if [ -f "${keyfile}.pub" ]; then
            echo "    Public key: ${keyfile}.pub" | tee -a "$OUTPUT_FILE"
        fi
    fi
done 2>/dev/null
echo "" >> "$OUTPUT_FILE"

echo "SSH Config File:" | tee -a "$OUTPUT_FILE"
if [ -f ~/.ssh/config ]; then
    echo "SSH config file exists:" | tee -a "$OUTPUT_FILE"
    cat ~/.ssh/config | tee -a "$OUTPUT_FILE"
else
    echo "No SSH config file found at ~/.ssh/config" | tee -a "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Credential Files
#-------------------------------------------------------------------------------
print_section "Credential Files"

echo "Searching for password/credential files..." | tee -a "$OUTPUT_FILE"
find ~ -name "*password*" -o -name "*credential*" -o -name "*wallet*" 2>/dev/null | head -20 | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "ZDM Credential Store:" | tee -a "$OUTPUT_FILE"
if [ -n "$ZDM_HOME" ]; then
    ls -la "$ZDM_HOME/crsdata/$(hostname)/security" 2>/dev/null | tee -a "$OUTPUT_FILE" || echo "ZDM credential store not found" >> "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Network Configuration
#-------------------------------------------------------------------------------
print_section "Network Configuration"

echo "IP Addresses:" | tee -a "$OUTPUT_FILE"
ip addr show 2>/dev/null | grep "inet " | awk '{print "  " $2}' | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Routing Table:" | tee -a "$OUTPUT_FILE"
ip route show | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "DNS Configuration:" | tee -a "$OUTPUT_FILE"
cat /etc/resolv.conf 2>/dev/null | tee -a "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Network Latency Tests (Custom Request)
#-------------------------------------------------------------------------------
print_section "Network Latency Tests (Custom Discovery)"

# Source database
SOURCE_HOST="proddb01.corp.example.com"
echo "Ping Test to Source Database ($SOURCE_HOST):" | tee -a "$OUTPUT_FILE"
ping -c 5 "$SOURCE_HOST" 2>&1 | tee -a "$OUTPUT_FILE" || echo "Unable to ping $SOURCE_HOST" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Target database
TARGET_HOST="proddb-oda.eastus.azure.example.com"
echo "Ping Test to Target Database ($TARGET_HOST):" | tee -a "$OUTPUT_FILE"
ping -c 5 "$TARGET_HOST" 2>&1 | tee -a "$OUTPUT_FILE" || echo "Unable to ping $TARGET_HOST" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Traceroute to Source (first 10 hops):" | tee -a "$OUTPUT_FILE"
traceroute -m 10 "$SOURCE_HOST" 2>&1 | tee -a "$OUTPUT_FILE" || echo "Unable to traceroute to $SOURCE_HOST" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Traceroute to Target (first 10 hops):" | tee -a "$OUTPUT_FILE"
traceroute -m 10 "$TARGET_HOST" 2>&1 | tee -a "$OUTPUT_FILE" || echo "Unable to traceroute to $TARGET_HOST" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# ZDM Logs
#-------------------------------------------------------------------------------
print_section "ZDM Logs"

if [ -n "$ZDM_HOME" ]; then
    ZDM_LOG_DIR="$ZDM_HOME/log"
    echo "ZDM Log Directory: $ZDM_LOG_DIR" | tee -a "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    if [ -d "$ZDM_LOG_DIR" ]; then
        echo "Recent Log Files (last 10):" | tee -a "$OUTPUT_FILE"
        ls -lt "$ZDM_LOG_DIR"/*.log 2>/dev/null | head -10 | tee -a "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        
        echo "Log Directory Size:" | tee -a "$OUTPUT_FILE"
        du -sh "$ZDM_LOG_DIR" 2>/dev/null | tee -a "$OUTPUT_FILE"
    else
        echo "ZDM log directory not found" | tee -a "$OUTPUT_FILE"
    fi
else
    echo "ZDM_HOME not set, unable to locate log directory" | tee -a "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Generate JSON Summary
#-------------------------------------------------------------------------------
print_section "Generating JSON Summary"

# Get key values for JSON
ZDM_VERSION=$($ZDM_HOME/bin/zdmcli -version 2>/dev/null | head -1 || echo "Unknown")
JAVA_VERSION=$(java -version 2>&1 | head -1)
OCI_VERSION=$(oci --version 2>/dev/null || echo "Not installed")
TOTAL_DISK_GB=$(df -BG / | tail -1 | awk '{print $2}' | tr -d 'G')
AVAIL_DISK_GB=$(df -BG / | tail -1 | awk '{print $4}' | tr -d 'G')

# Continue JSON file
cat >> "$JSON_FILE" <<EOF
  "os": {
    "hostname": "$HOSTNAME",
    "os_version": "$(cat /etc/os-release 2>/dev/null | grep '^VERSION=' | cut -d= -f2 | tr -d '"')"
  },
  "zdm": {
    "zdm_home": "${ZDM_HOME:-NOT SET}",
    "version": "$ZDM_VERSION"
  },
  "java": {
    "java_home": "${JAVA_HOME:-NOT SET}",
    "version": "$JAVA_VERSION"
  },
  "oci": {
    "version": "$OCI_VERSION",
    "config_file": "$OCI_CONFIG_FILE"
  },
  "disk_space": {
    "total_gb": "$TOTAL_DISK_GB",
    "available_gb": "$AVAIL_DISK_GB",
    "meets_minimum_50gb": $([ "$AVAIL_DISK_GB" -ge 50 ] && echo "true" || echo "false")
  },
  "connectivity": {
    "source_host": "$SOURCE_HOST",
    "target_host": "$TARGET_HOST"
  },
  "output_files": {
    "text_report": "$OUTPUT_FILE",
    "json_summary": "$JSON_FILE"
  }
}
EOF

#-------------------------------------------------------------------------------
# Complete
#-------------------------------------------------------------------------------
print_header "Discovery Complete"
print_info "Text Report: $OUTPUT_FILE"
print_info "JSON Summary: $JSON_FILE"
print_info "Completed: $(date)"

echo ""
echo "===============================================================================" >> "$OUTPUT_FILE"
echo "Discovery completed at $(date)" >> "$OUTPUT_FILE"
echo "===============================================================================" >> "$OUTPUT_FILE"

exit 0
