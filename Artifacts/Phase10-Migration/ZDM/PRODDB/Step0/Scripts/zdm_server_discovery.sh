#!/bin/bash
###############################################################################
# ZDM Server Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# ZDM Server: zdm-jumpbox.corp.example.com
# 
# Purpose: Discover ZDM jumpbox configuration for ZDM migration
# Run as: zdmuser on ZDM jumpbox server
#
# Generated: 2026-01-29
###############################################################################

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Get hostname and timestamp for output files
HOSTNAME=$(hostname -s 2>/dev/null || hostname)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="./zdm_server_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_server_discovery_${HOSTNAME}_${TIMESTAMP}.json"

# Initialize JSON structure
declare -A JSON_DATA

# Source and Target hosts for connectivity tests
SOURCE_HOST="${SOURCE_HOST:-proddb01.corp.example.com}"
TARGET_HOST="${TARGET_HOST:-proddb-oda.eastus.azure.example.com}"

###############################################################################
# Environment Variable Sourcing with Fallback
###############################################################################
source_environment() {
    echo -e "${BLUE}=== Sourcing ZDM Environment ===${NC}"
    
    # Method 1: Use explicit overrides if provided (passed via environment)
    if [ -n "${ZDM_HOME_OVERRIDE:-}" ]; then
        export ZDM_HOME="$ZDM_HOME_OVERRIDE"
        echo -e "${GREEN}Using explicit ZDM_HOME override: $ZDM_HOME${NC}"
    fi
    if [ -n "${JAVA_HOME_OVERRIDE:-}" ]; then
        export JAVA_HOME="$JAVA_HOME_OVERRIDE"
        echo -e "${GREEN}Using explicit JAVA_HOME override: $JAVA_HOME${NC}"
    fi
    
    # Method 2: Source profiles - extract export statements
    for profile in /etc/profile ~/.bash_profile ~/.bashrc ~/.profile; do
        if [ -f "$profile" ]; then
            eval "$(grep -E '^export\s+' "$profile" 2>/dev/null)" || true
        fi
    done
    
    # Method 3: Search common ZDM installation locations
    if [ -z "${ZDM_HOME:-}" ]; then
        for zh in /home/zdmuser/zdmhome /opt/zdm/zdmhome /u01/zdm/zdmhome ~/zdmhome; do
            if [ -d "$zh" ]; then
                export ZDM_HOME="$zh"
                echo -e "${YELLOW}Auto-detected ZDM_HOME: $ZDM_HOME${NC}"
                break
            fi
        done
    fi
    
    # Method 4: Search common Java installation locations
    if [ -z "${JAVA_HOME:-}" ]; then
        for jh in /usr/java/jdk* /usr/lib/jvm/java-* /opt/java/jdk*; do
            if [ -d "$jh" ]; then
                export JAVA_HOME="$jh"
                echo -e "${YELLOW}Auto-detected JAVA_HOME: $JAVA_HOME${NC}"
                break
            fi
        done
    fi
    
    # Set PATH
    if [ -n "${ZDM_HOME:-}" ]; then
        export PATH=$ZDM_HOME/bin:$PATH
    fi
    if [ -n "${JAVA_HOME:-}" ]; then
        export PATH=$JAVA_HOME/bin:$PATH
    fi
    
    echo "ZDM_HOME: ${ZDM_HOME:-NOT SET}"
    echo "JAVA_HOME: ${JAVA_HOME:-NOT SET}"
}

###############################################################################
# Helper Functions
###############################################################################
print_header() {
    local title="$1"
    echo ""
    echo -e "${CYAN}===============================================================================${NC}"
    echo -e "${CYAN}  $title${NC}"
    echo -e "${CYAN}===============================================================================${NC}"
    echo ""
}

print_section() {
    local title="$1"
    echo ""
    echo -e "${YELLOW}--- $title ---${NC}"
}

mask_sensitive() {
    # Mask sensitive information like keys, passwords, fingerprints
    sed -E 's/(key_file\s*=\s*).*/\1***MASKED***/' |
    sed -E 's/(fingerprint\s*=\s*).*/\1***MASKED***/' |
    sed -E 's/(pass_phrase\s*=\s*).*/\1***MASKED***/'
}

###############################################################################
# Discovery Functions
###############################################################################

discover_os_info() {
    print_header "OS INFORMATION"
    
    print_section "Hostname and Current User"
    echo "Hostname: $(hostname)"
    echo "Current User: $(whoami)"
    echo "User ID: $(id)"
    
    print_section "Operating System Version"
    if [ -f /etc/os-release ]; then
        cat /etc/os-release
    elif [ -f /etc/redhat-release ]; then
        cat /etc/redhat-release
    else
        uname -a
    fi
    
    JSON_DATA["hostname"]=$(hostname)
    JSON_DATA["user"]=$(whoami)
    JSON_DATA["os_version"]=$(cat /etc/redhat-release 2>/dev/null || uname -r)
}

discover_zdm_installation() {
    print_header "ZDM INSTALLATION"
    
    print_section "ZDM Home Location"
    echo "ZDM_HOME: ${ZDM_HOME:-NOT SET}"
    
    if [ -d "${ZDM_HOME:-}" ]; then
        echo ""
        echo "Contents of ZDM_HOME:"
        ls -la "$ZDM_HOME" 2>/dev/null || echo "Unable to list ZDM_HOME contents"
    fi
    
    print_section "ZDM Version"
    if [ -n "${ZDM_HOME:-}" ] && [ -x "${ZDM_HOME}/bin/zdmcli" ]; then
        ${ZDM_HOME}/bin/zdmcli -version 2>/dev/null || echo "Unable to get ZDM version"
        JSON_DATA["zdm_version"]=$("${ZDM_HOME}/bin/zdmcli" -version 2>/dev/null | head -1 || echo "unknown")
    else
        echo "ZDM CLI not found"
        JSON_DATA["zdm_version"]="not_found"
    fi
    
    print_section "ZDM Service Status"
    if [ -n "${ZDM_HOME:-}" ] && [ -x "${ZDM_HOME}/bin/zdmservice" ]; then
        ${ZDM_HOME}/bin/zdmservice status 2>/dev/null || echo "Unable to get ZDM service status"
    else
        echo "ZDM service script not found"
    fi
    
    print_section "Active Migration Jobs"
    if [ -n "${ZDM_HOME:-}" ] && [ -x "${ZDM_HOME}/bin/zdmcli" ]; then
        ${ZDM_HOME}/bin/zdmcli query job -all 2>/dev/null || echo "Unable to query migration jobs"
    else
        echo "ZDM CLI not available"
    fi
    
    JSON_DATA["zdm_home"]="${ZDM_HOME:-}"
}

discover_java_config() {
    print_header "JAVA CONFIGURATION"
    
    print_section "Java Version"
    java -version 2>&1 || echo "Java not found in PATH"
    
    print_section "JAVA_HOME"
    echo "JAVA_HOME: ${JAVA_HOME:-NOT SET}"
    
    if [ -d "${JAVA_HOME:-}" ]; then
        echo ""
        echo "Java installation directory contents:"
        ls -la "$JAVA_HOME" 2>/dev/null | head -10
    fi
    
    JSON_DATA["java_home"]="${JAVA_HOME:-}"
}

discover_oci_config() {
    print_header "OCI CLI CONFIGURATION"
    
    print_section "OCI CLI Version"
    oci --version 2>/dev/null || echo "OCI CLI not installed or not in PATH"
    
    print_section "OCI Config File Location and Contents"
    if [ -f ~/.oci/config ]; then
        echo "OCI config file: ~/.oci/config"
        echo ""
        echo "Contents (sensitive data masked):"
        cat ~/.oci/config 2>/dev/null | mask_sensitive
    else
        echo "OCI config file not found at ~/.oci/config"
    fi
    
    print_section "Configured Profiles and Regions"
    if [ -f ~/.oci/config ]; then
        echo "Profiles:"
        grep '^\[' ~/.oci/config 2>/dev/null
        echo ""
        echo "Regions configured:"
        grep 'region' ~/.oci/config 2>/dev/null
    fi
    
    print_section "API Key Files"
    echo "Checking for OCI API key files in ~/.oci/:"
    ls -la ~/.oci/*.pem 2>/dev/null || echo "No .pem files found in ~/.oci/"
    
    print_section "OCI Connectivity Test"
    echo "Testing OCI API connectivity..."
    oci iam region list --output table 2>/dev/null | head -20 || echo "Unable to connect to OCI API"
}

discover_ssh_config() {
    print_header "SSH CONFIGURATION"
    
    print_section "SSH Directory Contents"
    ls -la ~/.ssh/ 2>/dev/null || echo "No .ssh directory found"
    
    print_section "Available SSH Keys (public)"
    for key in ~/.ssh/*.pub; do
        if [ -f "$key" ]; then
            echo ""
            echo "Key: $key"
            echo "Fingerprint: $(ssh-keygen -lf "$key" 2>/dev/null || echo 'Unable to get fingerprint')"
        fi
    done
    
    print_section "SSH Config File"
    if [ -f ~/.ssh/config ]; then
        echo "Contents of ~/.ssh/config:"
        cat ~/.ssh/config 2>/dev/null
    else
        echo "No SSH config file found"
    fi
}

discover_credential_files() {
    print_header "CREDENTIAL FILES"
    
    print_section "Searching for Password/Credential Files"
    echo "Looking in common locations..."
    
    # Search in home directory
    find ~ -maxdepth 3 -type f \( -name "*password*" -o -name "*credential*" -o -name "*secret*" -o -name "*.wallet" \) 2>/dev/null | head -20
    
    # Check ZDM credential store
    if [ -d "${ZDM_HOME:-}/crsdata" ]; then
        echo ""
        echo "ZDM credential store found:"
        ls -la "${ZDM_HOME}/crsdata" 2>/dev/null | head -10
    fi
}

discover_network_config() {
    print_header "NETWORK CONFIGURATION"
    
    print_section "IP Addresses"
    ip addr show 2>/dev/null | grep 'inet ' | awk '{print "  " $2}' || ifconfig 2>/dev/null | grep 'inet ' | awk '{print "  " $2}'
    
    print_section "Routing Table"
    ip route show 2>/dev/null || route -n 2>/dev/null || echo "Unable to get routing table"
    
    print_section "DNS Configuration"
    if [ -f /etc/resolv.conf ]; then
        cat /etc/resolv.conf
    else
        echo "resolv.conf not found"
    fi
}

discover_zdm_logs() {
    print_header "ZDM LOGS"
    
    print_section "Log Directory Location"
    if [ -d "${ZDM_HOME:-}/log" ]; then
        echo "Log directory: ${ZDM_HOME}/log"
        
        print_section "Recent Log Files"
        ls -lt "${ZDM_HOME}/log" 2>/dev/null | head -20
        
        print_section "Log Directory Size"
        du -sh "${ZDM_HOME}/log" 2>/dev/null || echo "Unable to determine size"
    else
        echo "ZDM log directory not found"
    fi
}

###############################################################################
# ADDITIONAL DISCOVERY - Custom for PRODDB Migration
###############################################################################

discover_disk_space() {
    print_header "DISK SPACE FOR ZDM OPERATIONS"
    
    print_section "Disk Space Overview"
    df -h
    
    print_section "ZDM Home Directory Space"
    if [ -d "${ZDM_HOME:-}" ]; then
        echo "Space used by ZDM_HOME:"
        du -sh "$ZDM_HOME" 2>/dev/null || echo "Unable to determine"
        
        echo ""
        echo "Breakdown by subdirectory:"
        du -sh "$ZDM_HOME"/* 2>/dev/null | sort -rh | head -10
    fi
    
    print_section "Available Space Check (50GB Minimum Recommended)"
    local zdm_mount=$(df -P "${ZDM_HOME:-/home}" 2>/dev/null | tail -1 | awk '{print $4}')
    local zdm_mount_gb=$((zdm_mount / 1024 / 1024))
    
    echo "Available space on ZDM home partition: ${zdm_mount_gb}GB"
    
    if [ "$zdm_mount_gb" -lt 50 ]; then
        echo -e "${RED}WARNING: Less than 50GB available! ZDM operations may fail.${NC}"
        JSON_DATA["disk_space_warning"]="true"
    else
        echo -e "${GREEN}OK: Sufficient disk space available.${NC}"
        JSON_DATA["disk_space_warning"]="false"
    fi
    
    JSON_DATA["available_disk_gb"]="$zdm_mount_gb"
    
    print_section "Temp Directory Space"
    df -h /tmp 2>/dev/null
    echo ""
    echo "TMPDIR: ${TMPDIR:-/tmp}"
}

discover_network_latency() {
    print_header "NETWORK LATENCY TESTS"
    
    print_section "Ping Test to Source Database (${SOURCE_HOST})"
    echo "Testing connectivity to: ${SOURCE_HOST}"
    ping -c 5 "${SOURCE_HOST}" 2>&1 || echo "Ping to source failed - may be blocked by firewall"
    
    print_section "Ping Test to Target Database (${TARGET_HOST})"
    echo "Testing connectivity to: ${TARGET_HOST}"
    ping -c 5 "${TARGET_HOST}" 2>&1 || echo "Ping to target failed - may be blocked by firewall"
    
    print_section "SSH Connectivity Test to Source"
    echo "Testing SSH port connectivity to ${SOURCE_HOST}:22"
    timeout 5 bash -c "echo >/dev/tcp/${SOURCE_HOST}/22" 2>/dev/null && echo "SSH port 22: OPEN" || echo "SSH port 22: CLOSED or FILTERED"
    
    print_section "SSH Connectivity Test to Target"
    echo "Testing SSH port connectivity to ${TARGET_HOST}:22"
    timeout 5 bash -c "echo >/dev/tcp/${TARGET_HOST}/22" 2>/dev/null && echo "SSH port 22: OPEN" || echo "SSH port 22: CLOSED or FILTERED"
    
    print_section "Oracle Listener Connectivity Test to Source (1521)"
    timeout 5 bash -c "echo >/dev/tcp/${SOURCE_HOST}/1521" 2>/dev/null && echo "Oracle port 1521: OPEN" || echo "Oracle port 1521: CLOSED or FILTERED"
    
    print_section "Oracle Listener Connectivity Test to Target (1521)"
    timeout 5 bash -c "echo >/dev/tcp/${TARGET_HOST}/1521" 2>/dev/null && echo "Oracle port 1521: OPEN" || echo "Oracle port 1521: CLOSED or FILTERED"
    
    print_section "Network Path to Source (traceroute)"
    traceroute -m 15 "${SOURCE_HOST}" 2>&1 | head -20 || echo "Traceroute not available or blocked"
    
    print_section "Network Path to Target (traceroute)"
    traceroute -m 15 "${TARGET_HOST}" 2>&1 | head -20 || echo "Traceroute not available or blocked"
}

###############################################################################
# Generate JSON Output
###############################################################################
generate_json() {
    cat > "$JSON_FILE" <<EOF
{
    "discovery_type": "zdm_server",
    "project": "PRODDB Migration to Oracle Database@Azure",
    "timestamp": "$(date -Iseconds)",
    "hostname": "${JSON_DATA["hostname"]:-}",
    "user": "${JSON_DATA["user"]:-}",
    "os_version": "${JSON_DATA["os_version"]:-}",
    "zdm": {
        "home": "${JSON_DATA["zdm_home"]:-}",
        "version": "${JSON_DATA["zdm_version"]:-}"
    },
    "java": {
        "home": "${JSON_DATA["java_home"]:-}"
    },
    "disk_space": {
        "available_gb": "${JSON_DATA["available_disk_gb"]:-}",
        "warning": ${JSON_DATA["disk_space_warning"]:-false}
    },
    "discovery_complete": true
}
EOF
}

###############################################################################
# Main Execution
###############################################################################
main() {
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     ZDM Server Discovery Script                                          ║${NC}"
    echo -e "${GREEN}║     Project: PRODDB Migration to Oracle Database@Azure                  ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Discovery started at: $(date)"
    echo "Output files will be saved to current directory:"
    echo "  Text Report: $OUTPUT_FILE"
    echo "  JSON Summary: $JSON_FILE"
    echo ""
    
    # Source ZDM environment
    source_environment
    
    # Redirect all output to both terminal and file
    {
        echo "=================================================================="
        echo "ZDM Server Discovery Report"
        echo "Project: PRODDB Migration to Oracle Database@Azure"
        echo "Generated: $(date)"
        echo "Hostname: $(hostname)"
        echo "Current User: $(whoami)"
        echo "=================================================================="
        
        # Run all discovery functions with error trapping
        discover_os_info || echo -e "${RED}WARNING: OS info discovery failed${NC}"
        discover_zdm_installation || echo -e "${RED}WARNING: ZDM installation discovery failed${NC}"
        discover_java_config || echo -e "${RED}WARNING: Java config discovery failed${NC}"
        discover_oci_config || echo -e "${RED}WARNING: OCI config discovery failed${NC}"
        discover_ssh_config || echo -e "${RED}WARNING: SSH config discovery failed${NC}"
        discover_credential_files || echo -e "${RED}WARNING: Credential files discovery failed${NC}"
        discover_network_config || echo -e "${RED}WARNING: Network config discovery failed${NC}"
        discover_zdm_logs || echo -e "${RED}WARNING: ZDM logs discovery failed${NC}"
        
        # Additional discovery for PRODDB migration
        discover_disk_space || echo -e "${RED}WARNING: Disk space discovery failed${NC}"
        discover_network_latency || echo -e "${RED}WARNING: Network latency tests failed${NC}"
        
        echo ""
        echo "=================================================================="
        echo "Discovery completed at: $(date)"
        echo "=================================================================="
        
    } 2>&1 | tee "$OUTPUT_FILE"
    
    # Generate JSON output
    generate_json
    
    echo ""
    echo -e "${GREEN}Discovery complete!${NC}"
    echo "Text Report: $OUTPUT_FILE"
    echo "JSON Summary: $JSON_FILE"
}

# Run main function
main "$@"
