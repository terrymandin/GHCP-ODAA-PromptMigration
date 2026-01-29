#!/bin/bash
#===============================================================================
# ZDM Server Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# Target: zdm-jumpbox.corp.example.com
# Generated: 2026-01-29
#===============================================================================
# Usage: ./zdm_server_discovery.sh
# Run as: zdmuser
# Output: Text report and JSON summary in /tmp/
#===============================================================================

# Exit on error
set -e

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname -s)
OUTPUT_FILE="/tmp/zdm_server_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_FILE="/tmp/zdm_server_discovery_${HOSTNAME}_${TIMESTAMP}.json"

# Source and Target hosts for connectivity tests
SOURCE_HOST="proddb01.corp.example.com"
TARGET_HOST="proddb-oda.eastus.azure.example.com"

# Minimum disk space recommended for ZDM operations (in GB)
MIN_DISK_SPACE_GB=50

#-------------------------------------------------------------------------------
# Color Codes
#-------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#-------------------------------------------------------------------------------
# Utility Functions
#-------------------------------------------------------------------------------
log_header() {
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BLUE}= $1${NC}"
    echo -e "${BLUE}================================================================${NC}"
    echo ""
}

log_section() {
    echo -e "\n${GREEN}--- $1 ---${NC}"
    echo "=== $1 ===" >> "$OUTPUT_FILE"
}

log_info() {
    echo -e "${NC}$1${NC}"
    echo "$1" >> "$OUTPUT_FILE"
}

log_warn() {
    echo -e "${YELLOW}WARNING: $1${NC}"
    echo "WARNING: $1" >> "$OUTPUT_FILE"
}

log_error() {
    echo -e "${RED}ERROR: $1${NC}"
    echo "ERROR: $1" >> "$OUTPUT_FILE"
}

log_success() {
    echo -e "${GREEN}✓ $1${NC}"
    echo "PASS: $1" >> "$OUTPUT_FILE"
}

log_fail() {
    echo -e "${RED}✗ $1${NC}"
    echo "FAIL: $1" >> "$OUTPUT_FILE"
}

#-------------------------------------------------------------------------------
# Initialize Output Files
#-------------------------------------------------------------------------------
log_header "ZDM Server Discovery"
echo "================================================================" > "$OUTPUT_FILE"
echo "= ZDM Server Discovery Report" >> "$OUTPUT_FILE"
echo "= Project: PRODDB Migration to Oracle Database@Azure" >> "$OUTPUT_FILE"
echo "= Host: $HOSTNAME" >> "$OUTPUT_FILE"
echo "= Date: $(date)" >> "$OUTPUT_FILE"
echo "================================================================" >> "$OUTPUT_FILE"

# Initialize JSON
echo "{" > "$JSON_FILE"
echo "  \"discovery_type\": \"zdm_server\"," >> "$JSON_FILE"
echo "  \"project\": \"PRODDB Migration to Oracle Database@Azure\"," >> "$JSON_FILE"
echo "  \"hostname\": \"$HOSTNAME\"," >> "$JSON_FILE"
echo "  \"timestamp\": \"$(date -Iseconds)\"," >> "$JSON_FILE"

#-------------------------------------------------------------------------------
# OS Information
#-------------------------------------------------------------------------------
log_section "OS INFORMATION"
echo "" >> "$OUTPUT_FILE"

echo "Hostname: $(hostname)" >> "$OUTPUT_FILE"
echo "Current User: $(whoami)" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Operating System:" >> "$OUTPUT_FILE"
cat /etc/os-release 2>/dev/null | head -5 >> "$OUTPUT_FILE" || uname -a >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Kernel Version:" >> "$OUTPUT_FILE"
uname -r >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# JSON: OS Info
echo "  \"os\": {" >> "$JSON_FILE"
echo "    \"hostname\": \"$(hostname)\"," >> "$JSON_FILE"
echo "    \"user\": \"$(whoami)\"," >> "$JSON_FILE"
echo "    \"kernel\": \"$(uname -r)\"" >> "$JSON_FILE"
echo "  }," >> "$JSON_FILE"

#-------------------------------------------------------------------------------
# Disk Space Check (ZDM Specific)
#-------------------------------------------------------------------------------
log_section "DISK SPACE CHECK"
echo "" >> "$OUTPUT_FILE"

echo "Disk Space Usage:" >> "$OUTPUT_FILE"
df -h >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Check ZDM_HOME disk space
if [ -n "$ZDM_HOME" ]; then
    ZDM_DISK=$(df -BG "$ZDM_HOME" 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')
    echo "ZDM_HOME ($ZDM_HOME) available space: ${ZDM_DISK}GB" >> "$OUTPUT_FILE"
    
    if [ "$ZDM_DISK" -ge "$MIN_DISK_SPACE_GB" ]; then
        log_success "ZDM disk space: ${ZDM_DISK}GB available (minimum ${MIN_DISK_SPACE_GB}GB recommended)"
    else
        log_fail "ZDM disk space: ${ZDM_DISK}GB available - BELOW minimum ${MIN_DISK_SPACE_GB}GB recommended"
    fi
else
    # Check /home disk if ZDM_HOME not set
    HOME_DISK=$(df -BG /home 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')
    echo "/home available space: ${HOME_DISK}GB" >> "$OUTPUT_FILE"
    
    if [ "$HOME_DISK" -ge "$MIN_DISK_SPACE_GB" ]; then
        log_success "Home disk space: ${HOME_DISK}GB available (minimum ${MIN_DISK_SPACE_GB}GB recommended)"
    else
        log_warn "Home disk space: ${HOME_DISK}GB available - BELOW minimum ${MIN_DISK_SPACE_GB}GB recommended"
    fi
fi
echo "" >> "$OUTPUT_FILE"

# Check /tmp disk space
TMP_DISK=$(df -BG /tmp 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')
echo "/tmp available space: ${TMP_DISK}GB" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# ZDM Installation
#-------------------------------------------------------------------------------
log_section "ZDM INSTALLATION"
echo "" >> "$OUTPUT_FILE"

echo "ZDM_HOME: ${ZDM_HOME:-NOT SET}" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

if [ -n "$ZDM_HOME" ] && [ -d "$ZDM_HOME" ]; then
    echo "ZDM Directory Contents:" >> "$OUTPUT_FILE"
    ls -la "$ZDM_HOME" >> "$OUTPUT_FILE" 2>&1
    echo "" >> "$OUTPUT_FILE"
    
    echo "ZDM Version:" >> "$OUTPUT_FILE"
    if [ -f "$ZDM_HOME/bin/zdmcli" ]; then
        "$ZDM_HOME/bin/zdmcli" -version 2>&1 >> "$OUTPUT_FILE" || echo "Unable to get ZDM version" >> "$OUTPUT_FILE"
    else
        echo "zdmcli not found" >> "$OUTPUT_FILE"
    fi
    echo "" >> "$OUTPUT_FILE"
    
    echo "ZDM Service Status:" >> "$OUTPUT_FILE"
    "$ZDM_HOME/bin/zdmservice" status 2>&1 >> "$OUTPUT_FILE" || echo "Unable to get ZDM service status" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    echo "Active ZDM Migration Jobs:" >> "$OUTPUT_FILE"
    "$ZDM_HOME/bin/zdmcli" query job -status RUNNING 2>&1 >> "$OUTPUT_FILE" || echo "No running jobs or unable to query" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    echo "Recent ZDM Migration Jobs (All):" >> "$OUTPUT_FILE"
    "$ZDM_HOME/bin/zdmcli" query job 2>&1 | head -20 >> "$OUTPUT_FILE" || echo "No jobs found or unable to query" >> "$OUTPUT_FILE"
else
    echo "ZDM_HOME not set or directory does not exist" >> "$OUTPUT_FILE"
    log_warn "ZDM_HOME not configured. Please set ZDM_HOME environment variable."
fi
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Java Configuration
#-------------------------------------------------------------------------------
log_section "JAVA CONFIGURATION"
echo "" >> "$OUTPUT_FILE"

echo "JAVA_HOME: ${JAVA_HOME:-NOT SET}" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Java Version:" >> "$OUTPUT_FILE"
java -version 2>&1 >> "$OUTPUT_FILE" || echo "Java not found in PATH" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Java Location:" >> "$OUTPUT_FILE"
which java 2>&1 >> "$OUTPUT_FILE" || echo "Java not found" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# OCI CLI Configuration
#-------------------------------------------------------------------------------
log_section "OCI CLI CONFIGURATION"
echo "" >> "$OUTPUT_FILE"

echo "OCI CLI Version:" >> "$OUTPUT_FILE"
oci --version 2>&1 >> "$OUTPUT_FILE" || echo "OCI CLI not installed or not in PATH" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "OCI Config File:" >> "$OUTPUT_FILE"
if [ -f ~/.oci/config ]; then
    echo "Found: ~/.oci/config" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    echo "Configured Profiles:" >> "$OUTPUT_FILE"
    grep "^\[" ~/.oci/config >> "$OUTPUT_FILE" 2>/dev/null
    echo "" >> "$OUTPUT_FILE"
    
    echo "Configured Regions:" >> "$OUTPUT_FILE"
    grep "^region" ~/.oci/config >> "$OUTPUT_FILE" 2>/dev/null
    echo "" >> "$OUTPUT_FILE"
    
    echo "API Key Files:" >> "$OUTPUT_FILE"
    grep "^key_file" ~/.oci/config | while read line; do
        KEY_FILE=$(echo "$line" | cut -d= -f2 | tr -d ' ')
        if [ -f "$KEY_FILE" ]; then
            echo "  ✓ $KEY_FILE exists" >> "$OUTPUT_FILE"
        else
            echo "  ✗ $KEY_FILE NOT FOUND" >> "$OUTPUT_FILE"
        fi
    done
else
    echo "OCI config file not found at ~/.oci/config" >> "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

echo "OCI Connectivity Test:" >> "$OUTPUT_FILE"
oci iam region list --query "data[0].name" --raw-output 2>&1 >> "$OUTPUT_FILE" && log_success "OCI API connectivity verified" || log_fail "OCI connectivity test failed"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# SSH Configuration
#-------------------------------------------------------------------------------
log_section "SSH CONFIGURATION"
echo "" >> "$OUTPUT_FILE"

echo "SSH Directory Contents:" >> "$OUTPUT_FILE"
ls -la ~/.ssh/ 2>/dev/null >> "$OUTPUT_FILE" || echo "No .ssh directory found" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Available SSH Keys:" >> "$OUTPUT_FILE"
echo "Public Keys:" >> "$OUTPUT_FILE"
ls -la ~/.ssh/*.pub 2>/dev/null >> "$OUTPUT_FILE" || echo "  No public keys found" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Private Keys:" >> "$OUTPUT_FILE"
ls -la ~/.ssh/id_* 2>/dev/null | grep -v ".pub" >> "$OUTPUT_FILE" || echo "  No private keys found (id_*)" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "SSH Config:" >> "$OUTPUT_FILE"
if [ -f ~/.ssh/config ]; then
    cat ~/.ssh/config >> "$OUTPUT_FILE"
else
    echo "No SSH config file found" >> "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Credential Files
#-------------------------------------------------------------------------------
log_section "CREDENTIAL FILES"
echo "" >> "$OUTPUT_FILE"

echo "Searching for common credential file patterns..." >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Search in ZDM_HOME if set
if [ -n "$ZDM_HOME" ]; then
    echo "Files in ZDM_HOME containing 'password', 'cred', or 'wallet':" >> "$OUTPUT_FILE"
    find "$ZDM_HOME" -type f \( -name "*password*" -o -name "*cred*" -o -name "*wallet*" \) 2>/dev/null >> "$OUTPUT_FILE" || echo "  None found" >> "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

echo "Wallet directories:" >> "$OUTPUT_FILE"
find /home -type d -name "*wallet*" 2>/dev/null >> "$OUTPUT_FILE" || echo "  None found in /home" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Network Configuration
#-------------------------------------------------------------------------------
log_section "NETWORK CONFIGURATION"
echo "" >> "$OUTPUT_FILE"

echo "IP Addresses:" >> "$OUTPUT_FILE"
ip addr show 2>/dev/null | grep "inet " | awk '{print "  " $2}' >> "$OUTPUT_FILE" || hostname -I >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Routing Table:" >> "$OUTPUT_FILE"
ip route show 2>/dev/null >> "$OUTPUT_FILE" || route -n >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "DNS Configuration (/etc/resolv.conf):" >> "$OUTPUT_FILE"
cat /etc/resolv.conf >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Hosts File (/etc/hosts):" >> "$OUTPUT_FILE"
cat /etc/hosts >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Network Latency Tests
#-------------------------------------------------------------------------------
log_section "NETWORK LATENCY TESTS"
echo "" >> "$OUTPUT_FILE"

echo "Testing connectivity to Source Database: $SOURCE_HOST" >> "$OUTPUT_FILE"
echo "Ping test (5 packets):" >> "$OUTPUT_FILE"
ping -c 5 "$SOURCE_HOST" 2>&1 >> "$OUTPUT_FILE" && log_success "Source host reachable" || log_fail "Source host unreachable"
echo "" >> "$OUTPUT_FILE"

echo "Testing connectivity to Target Database: $TARGET_HOST" >> "$OUTPUT_FILE"
echo "Ping test (5 packets):" >> "$OUTPUT_FILE"
ping -c 5 "$TARGET_HOST" 2>&1 >> "$OUTPUT_FILE" && log_success "Target host reachable" || log_fail "Target host unreachable"
echo "" >> "$OUTPUT_FILE"

# SSH connectivity tests
echo "SSH Port Tests:" >> "$OUTPUT_FILE"
echo "Testing SSH port (22) to Source ($SOURCE_HOST):" >> "$OUTPUT_FILE"
timeout 5 bash -c "echo >/dev/tcp/$SOURCE_HOST/22" 2>&1 && log_success "SSH port 22 open on source" || log_fail "SSH port 22 closed/unreachable on source"
echo "" >> "$OUTPUT_FILE"

echo "Testing SSH port (22) to Target ($TARGET_HOST):" >> "$OUTPUT_FILE"
timeout 5 bash -c "echo >/dev/tcp/$TARGET_HOST/22" 2>&1 && log_success "SSH port 22 open on target" || log_fail "SSH port 22 closed/unreachable on target"
echo "" >> "$OUTPUT_FILE"

# Oracle listener port test (1521)
echo "Oracle Listener Port Tests:" >> "$OUTPUT_FILE"
echo "Testing port 1521 to Source ($SOURCE_HOST):" >> "$OUTPUT_FILE"
timeout 5 bash -c "echo >/dev/tcp/$SOURCE_HOST/1521" 2>&1 && log_success "Port 1521 open on source" || log_fail "Port 1521 closed/unreachable on source"
echo "" >> "$OUTPUT_FILE"

echo "Testing port 1521 to Target ($TARGET_HOST):" >> "$OUTPUT_FILE"
timeout 5 bash -c "echo >/dev/tcp/$TARGET_HOST/1521" 2>&1 && log_success "Port 1521 open on target" || log_fail "Port 1521 closed/unreachable on target"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# ZDM Logs
#-------------------------------------------------------------------------------
log_section "ZDM LOGS"
echo "" >> "$OUTPUT_FILE"

if [ -n "$ZDM_HOME" ]; then
    ZDM_LOG_DIR="$ZDM_HOME/chkbase"
    echo "ZDM Log Directory: $ZDM_LOG_DIR" >> "$OUTPUT_FILE"
    
    if [ -d "$ZDM_LOG_DIR" ]; then
        echo "Recent Log Files (last 10):" >> "$OUTPUT_FILE"
        ls -lt "$ZDM_LOG_DIR" 2>/dev/null | head -10 >> "$OUTPUT_FILE"
    else
        echo "Log directory not found" >> "$OUTPUT_FILE"
    fi
    
    # Also check scheduled directory
    ZDM_SCHED_DIR="$ZDM_HOME/rhp/zdm/zdm_*"
    echo "" >> "$OUTPUT_FILE"
    echo "ZDM Scheduled Migration Directories:" >> "$OUTPUT_FILE"
    ls -d $ZDM_SCHED_DIR 2>/dev/null | head -5 >> "$OUTPUT_FILE" || echo "No scheduled migration directories found" >> "$OUTPUT_FILE"
else
    echo "ZDM_HOME not set - unable to locate log directory" >> "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Environment Summary
#-------------------------------------------------------------------------------
log_section "ENVIRONMENT VARIABLES"
echo "" >> "$OUTPUT_FILE"

echo "Relevant Environment Variables:" >> "$OUTPUT_FILE"
echo "ZDM_HOME=$ZDM_HOME" >> "$OUTPUT_FILE"
echo "JAVA_HOME=$JAVA_HOME" >> "$OUTPUT_FILE"
echo "ORACLE_HOME=$ORACLE_HOME" >> "$OUTPUT_FILE"
echo "PATH=$PATH" >> "$OUTPUT_FILE"
echo "OCI_CLI_CONFIG_FILE=${OCI_CLI_CONFIG_FILE:-~/.oci/config}" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# Finalize JSON Output
#-------------------------------------------------------------------------------
echo "  \"zdm_home\": \"${ZDM_HOME:-NOT SET}\"," >> "$JSON_FILE"
echo "  \"java_home\": \"${JAVA_HOME:-NOT SET}\"," >> "$JSON_FILE"
echo "  \"connectivity\": {" >> "$JSON_FILE"
echo "    \"source_host\": \"$SOURCE_HOST\"," >> "$JSON_FILE"
echo "    \"target_host\": \"$TARGET_HOST\"" >> "$JSON_FILE"
echo "  }," >> "$JSON_FILE"
echo "  \"discovery_complete\": true" >> "$JSON_FILE"
echo "}" >> "$JSON_FILE"

#-------------------------------------------------------------------------------
# Summary
#-------------------------------------------------------------------------------
log_section "DISCOVERY COMPLETE"
echo "" >> "$OUTPUT_FILE"
echo "Output Files:" >> "$OUTPUT_FILE"
echo "  Text Report: $OUTPUT_FILE" >> "$OUTPUT_FILE"
echo "  JSON Summary: $JSON_FILE" >> "$OUTPUT_FILE"

echo ""
echo -e "${GREEN}================================================================${NC}"
echo -e "${GREEN}= ZDM Server Discovery Complete${NC}"
echo -e "${GREEN}================================================================${NC}"
echo -e "Text Report: ${BLUE}$OUTPUT_FILE${NC}"
echo -e "JSON Summary: ${BLUE}$JSON_FILE${NC}"
echo ""
echo -e "${YELLOW}Connectivity Summary:${NC}"
echo -e "  Source Host: $SOURCE_HOST"
echo -e "  Target Host: $TARGET_HOST"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Review the discovery report for any failures"
echo "2. Address connectivity issues if any"
echo "3. Collect all discovery outputs to Step0/Discovery/"
echo "4. Proceed to Step 1: Discovery Questionnaire"
echo ""
