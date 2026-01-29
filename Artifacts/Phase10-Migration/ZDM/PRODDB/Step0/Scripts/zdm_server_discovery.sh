#!/bin/bash
################################################################################
# ZDM Server Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# Target Server: zdm-jumpbox.corp.example.com
# Generated: 2026-01-29
#
# Purpose: Discovers comprehensive information about the ZDM jumpbox server
#          for migration planning and execution.
#
# Usage: Run as zdmuser on the ZDM jumpbox server
#        ./zdm_server_discovery.sh
#
# Output: Text report and JSON summary in current working directory
################################################################################

# NO set -e - We want to continue even if some checks fail
SECTION_ERRORS=0
SCRIPT_VERSION="1.0.0"

# Source environment for ZDM_HOME, JAVA_HOME, etc.
# This is critical - ZDM_HOME is often set in .bashrc
for profile in ~/.bash_profile ~/.bashrc /etc/profile ~/.profile /etc/profile.d/*.sh; do
    [ -f "$profile" ] && source "$profile" 2>/dev/null || true
done

# Initialize variables
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname -s 2>/dev/null || hostname)
OUTPUT_FILE="./zdm_server_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_server_discovery_${HOSTNAME}_${TIMESTAMP}.json"

# Migration project servers for connectivity tests
SOURCE_HOST="proddb01.corp.example.com"
TARGET_HOST="proddb-oda.eastus.azure.example.com"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Helper Functions
################################################################################

log_section() {
    local section_name="$1"
    echo ""
    echo "================================================================================" | tee -a "$OUTPUT_FILE"
    echo "= $section_name" | tee -a "$OUTPUT_FILE"
    echo "================================================================================" | tee -a "$OUTPUT_FILE"
    echo -e "${BLUE}[INFO]${NC} Discovering: $section_name"
}

log_subsection() {
    local subsection_name="$1"
    echo "" | tee -a "$OUTPUT_FILE"
    echo "--- $subsection_name ---" | tee -a "$OUTPUT_FILE"
}

log_info() {
    echo "$1" | tee -a "$OUTPUT_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$OUTPUT_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$OUTPUT_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

################################################################################
# Discovery Functions
################################################################################

discover_os_info() {
    log_section "OPERATING SYSTEM INFORMATION"
    
    log_subsection "Hostname and User"
    log_info "Hostname: $HOSTNAME"
    log_info "FQDN: $(hostname -f 2>/dev/null || echo 'N/A')"
    log_info "Current User: $(whoami)"
    log_info "User ID: $(id)"
    
    log_subsection "IP Addresses"
    ip addr show 2>/dev/null | grep -E "inet |inet6 " | tee -a "$OUTPUT_FILE" || \
        ifconfig 2>/dev/null | grep -E "inet |inet6 " | tee -a "$OUTPUT_FILE" || \
        log_warning "Could not retrieve IP addresses"
    
    log_subsection "Operating System Version"
    cat /etc/os-release 2>/dev/null | tee -a "$OUTPUT_FILE" || \
        cat /etc/redhat-release 2>/dev/null | tee -a "$OUTPUT_FILE" || \
        uname -a | tee -a "$OUTPUT_FILE"
    
    log_subsection "Kernel Version"
    uname -r | tee -a "$OUTPUT_FILE"
    
    log_subsection "Memory"
    free -h 2>/dev/null | tee -a "$OUTPUT_FILE" || log_warning "Could not retrieve memory info"
}

discover_zdm_installation() {
    log_section "ZDM INSTALLATION"
    
    log_subsection "ZDM_HOME"
    if [ -n "$ZDM_HOME" ]; then
        log_info "ZDM_HOME: $ZDM_HOME"
        if [ -d "$ZDM_HOME" ]; then
            log_info "ZDM_HOME directory exists"
            ls -la "$ZDM_HOME" 2>/dev/null | head -20 | tee -a "$OUTPUT_FILE"
        else
            log_error "ZDM_HOME directory does not exist"
        fi
    else
        log_warning "ZDM_HOME is not set"
        # Try to find ZDM installation
        log_info "Searching for ZDM installation..."
        find /home -name "zdmhome" -type d 2>/dev/null | head -5 | tee -a "$OUTPUT_FILE" || \
            log_info "No ZDM installation found in /home"
        find /opt -name "zdm*" -type d 2>/dev/null | head -5 | tee -a "$OUTPUT_FILE" || \
            log_info "No ZDM installation found in /opt"
    fi
    
    log_subsection "ZDM Version"
    if [ -n "$ZDM_HOME" ] && [ -f "$ZDM_HOME/bin/zdmcli" ]; then
        "$ZDM_HOME/bin/zdmcli" -version 2>&1 | tee -a "$OUTPUT_FILE" || \
            log_warning "Could not get ZDM version"
    else
        log_warning "zdmcli not found"
    fi
    
    log_subsection "ZDM Service Status"
    if [ -n "$ZDM_HOME" ] && [ -f "$ZDM_HOME/bin/zdmservice" ]; then
        "$ZDM_HOME/bin/zdmservice" status 2>&1 | tee -a "$OUTPUT_FILE" || \
            log_warning "Could not get ZDM service status"
    else
        log_warning "zdmservice not found"
    fi
    
    log_subsection "Active Migration Jobs"
    if [ -n "$ZDM_HOME" ] && [ -f "$ZDM_HOME/bin/zdmcli" ]; then
        "$ZDM_HOME/bin/zdmcli" query job -allactive 2>&1 | tee -a "$OUTPUT_FILE" || \
            log_info "No active migration jobs or could not query"
    fi
    
    log_subsection "Completed Migration Jobs (Recent)"
    if [ -n "$ZDM_HOME" ] && [ -f "$ZDM_HOME/bin/zdmcli" ]; then
        "$ZDM_HOME/bin/zdmcli" query job -completed 2>&1 | head -30 | tee -a "$OUTPUT_FILE" || \
            log_info "No completed migration jobs or could not query"
    fi
}

discover_java_config() {
    log_section "JAVA CONFIGURATION"
    
    log_subsection "JAVA_HOME"
    if [ -n "$JAVA_HOME" ]; then
        log_info "JAVA_HOME: $JAVA_HOME"
    else
        log_warning "JAVA_HOME is not set"
    fi
    
    log_subsection "Java Version"
    if command -v java &>/dev/null; then
        java -version 2>&1 | tee -a "$OUTPUT_FILE"
    else
        log_warning "Java not found in PATH"
    fi
    
    log_subsection "Java Location"
    which java 2>/dev/null | tee -a "$OUTPUT_FILE" || log_warning "java not in PATH"
}

discover_oci_cli() {
    log_section "OCI CLI CONFIGURATION"
    
    log_subsection "OCI CLI Version"
    oci --version 2>&1 | tee -a "$OUTPUT_FILE" || log_warning "OCI CLI not installed or not in PATH"
    
    log_subsection "OCI Config File"
    if [ -f ~/.oci/config ]; then
        log_info "OCI config file exists: ~/.oci/config"
        log_info ""
        log_info "Configured profiles:"
        grep "^\[" ~/.oci/config 2>/dev/null | tee -a "$OUTPUT_FILE"
        log_info ""
        log_info "Profile details (sensitive data masked):"
        while IFS= read -r line; do
            if [[ "$line" =~ ^key_file|^fingerprint|^tenancy|^user|^region ]]; then
                # Mask sensitive values
                key=$(echo "$line" | cut -d'=' -f1)
                value=$(echo "$line" | cut -d'=' -f2-)
                if [[ "$key" =~ fingerprint|tenancy|user ]]; then
                    masked_value="${value:0:8}...${value: -4}"
                    echo "${key}=${masked_value}" | tee -a "$OUTPUT_FILE"
                else
                    echo "$line" | tee -a "$OUTPUT_FILE"
                fi
            elif [[ "$line" =~ ^\[ ]]; then
                echo "$line" | tee -a "$OUTPUT_FILE"
            fi
        done < ~/.oci/config
    else
        log_warning "OCI config not found at ~/.oci/config"
    fi
    
    log_subsection "OCI API Key Files"
    if [ -d ~/.oci ]; then
        log_info "OCI directory contents:"
        ls -la ~/.oci/ 2>/dev/null | tee -a "$OUTPUT_FILE"
        
        # Check for private key files
        for keyfile in ~/.oci/*.pem; do
            if [ -f "$keyfile" ]; then
                log_info "Private key found: $keyfile"
                # Check permissions
                perms=$(stat -c %a "$keyfile" 2>/dev/null || stat -f %A "$keyfile" 2>/dev/null)
                if [ "$perms" == "600" ] || [ "$perms" == "400" ]; then
                    log_info "  Permissions OK: $perms"
                else
                    log_warning "  Permissions may be too open: $perms (should be 600 or 400)"
                fi
            fi
        done
    else
        log_warning "~/.oci directory not found"
    fi
    
    log_subsection "OCI Connectivity Test"
    oci iam region list --output table 2>&1 | head -20 | tee -a "$OUTPUT_FILE" || \
        log_warning "OCI connectivity test failed"
}

discover_ssh_config() {
    log_section "SSH CONFIGURATION"
    
    log_subsection "SSH Directory Contents"
    if [ -d ~/.ssh ]; then
        ls -la ~/.ssh/ 2>/dev/null | tee -a "$OUTPUT_FILE"
    else
        log_warning "~/.ssh directory not found"
    fi
    
    log_subsection "Available SSH Keys"
    if [ -d ~/.ssh ]; then
        log_info "Private keys:"
        for keyfile in ~/.ssh/id_* ~/.ssh/*_key ~/.ssh/*.pem; do
            if [ -f "$keyfile" ] && [[ ! "$keyfile" =~ \.pub$ ]]; then
                log_info "  Found: $keyfile"
                perms=$(stat -c %a "$keyfile" 2>/dev/null || stat -f %A "$keyfile" 2>/dev/null)
                log_info "    Permissions: $perms"
            fi
        done
        
        log_info ""
        log_info "Public keys:"
        for pubkey in ~/.ssh/*.pub; do
            if [ -f "$pubkey" ]; then
                log_info "  Found: $pubkey"
            fi
        done
    fi
    
    log_subsection "SSH Config"
    if [ -f ~/.ssh/config ]; then
        log_info "SSH config exists:"
        cat ~/.ssh/config 2>/dev/null | tee -a "$OUTPUT_FILE"
    else
        log_info "No SSH config file found"
    fi
}

discover_credential_files() {
    log_section "CREDENTIAL FILES"
    
    log_subsection "Search for Password/Credential Files"
    log_info "Searching in home directory for credential files..."
    
    # Common credential file patterns
    find ~ -maxdepth 3 -type f \( \
        -name "*.cred" -o \
        -name "*.credential*" -o \
        -name "*password*" -o \
        -name "*.wallet" -o \
        -name "*.auth" -o \
        -name "*secret*" \
    \) 2>/dev/null | grep -v ".bash_history" | tee -a "$OUTPUT_FILE" || \
        log_info "No obvious credential files found"
    
    log_subsection "ZDM Credential Store"
    if [ -n "$ZDM_HOME" ] && [ -d "$ZDM_HOME/rhp/zdm/credentials" ]; then
        log_info "ZDM credentials directory:"
        ls -la "$ZDM_HOME/rhp/zdm/credentials/" 2>/dev/null | tee -a "$OUTPUT_FILE"
    else
        log_info "ZDM credentials directory not found at standard location"
    fi
}

discover_network_config() {
    log_section "NETWORK CONFIGURATION"
    
    log_subsection "IP Addresses"
    ip addr show 2>/dev/null | tee -a "$OUTPUT_FILE" || \
        ifconfig -a 2>/dev/null | tee -a "$OUTPUT_FILE" || \
        log_warning "Could not list network interfaces"
    
    log_subsection "Routing Table"
    ip route show 2>/dev/null | tee -a "$OUTPUT_FILE" || \
        route -n 2>/dev/null | tee -a "$OUTPUT_FILE" || \
        netstat -rn 2>/dev/null | tee -a "$OUTPUT_FILE" || \
        log_warning "Could not get routing table"
    
    log_subsection "DNS Configuration"
    if [ -f /etc/resolv.conf ]; then
        cat /etc/resolv.conf | tee -a "$OUTPUT_FILE"
    else
        log_warning "/etc/resolv.conf not found"
    fi
    
    log_subsection "Hosts File"
    if [ -f /etc/hosts ]; then
        cat /etc/hosts | tee -a "$OUTPUT_FILE"
    fi
}

discover_zdm_logs() {
    log_section "ZDM LOGS"
    
    log_subsection "Log Directory Location"
    if [ -n "$ZDM_HOME" ]; then
        local log_dir="$ZDM_HOME/rhp/zdm/logs"
        if [ -d "$log_dir" ]; then
            log_info "ZDM log directory: $log_dir"
            log_info ""
            log_info "Recent log files:"
            ls -lt "$log_dir"/*.log 2>/dev/null | head -20 | tee -a "$OUTPUT_FILE" || \
                log_info "No .log files found"
        else
            log_warning "ZDM log directory not found: $log_dir"
        fi
    else
        log_warning "ZDM_HOME not set, cannot locate logs"
    fi
    
    log_subsection "ZDM Service Logs"
    if [ -n "$ZDM_HOME" ]; then
        local service_log="$ZDM_HOME/rhp/zdm/logs/zdmservice.log"
        if [ -f "$service_log" ]; then
            log_info "Last 50 lines of zdmservice.log:"
            tail -50 "$service_log" 2>/dev/null | tee -a "$OUTPUT_FILE"
        fi
    fi
}

################################################################################
# Additional Custom Discovery (PRODDB Specific - ZDM Server Requirements)
################################################################################

discover_disk_space() {
    log_section "DISK SPACE FOR ZDM OPERATIONS"
    
    log_subsection "Disk Space Summary"
    df -h | tee -a "$OUTPUT_FILE"
    
    log_subsection "ZDM Operations Space Check (50GB Recommended)"
    log_info ""
    
    # Check key directories
    for check_dir in "$ZDM_HOME" "/home/$(whoami)" "/tmp" "/var/tmp"; do
        if [ -d "$check_dir" ]; then
            available_kb=$(df -k "$check_dir" 2>/dev/null | tail -1 | awk '{print $4}')
            if [ -n "$available_kb" ]; then
                available_gb=$((available_kb / 1024 / 1024))
                mount_point=$(df "$check_dir" 2>/dev/null | tail -1 | awk '{print $6}')
                
                if [ "$available_gb" -ge 50 ]; then
                    log_info "✓ $check_dir ($mount_point): ${available_gb}GB available - SUFFICIENT"
                elif [ "$available_gb" -ge 25 ]; then
                    log_warning "⚠ $check_dir ($mount_point): ${available_gb}GB available - MAY BE LOW"
                else
                    log_error "✗ $check_dir ($mount_point): ${available_gb}GB available - INSUFFICIENT"
                fi
            fi
        fi
    done
    
    log_subsection "Large Files/Directories in ZDM_HOME"
    if [ -n "$ZDM_HOME" ] && [ -d "$ZDM_HOME" ]; then
        du -sh "$ZDM_HOME"/* 2>/dev/null | sort -rh | head -10 | tee -a "$OUTPUT_FILE"
    fi
}

discover_network_latency() {
    log_section "NETWORK LATENCY TESTS"
    
    log_subsection "Ping to Source Database Server"
    log_info "Target: $SOURCE_HOST"
    if ping -c 5 "$SOURCE_HOST" 2>&1 | tee -a "$OUTPUT_FILE"; then
        log_info ""
        log_info "Ping statistics:"
        ping -c 10 "$SOURCE_HOST" 2>/dev/null | tail -3 | tee -a "$OUTPUT_FILE"
    else
        log_warning "Ping to source failed - host may not respond to ICMP"
    fi
    
    echo "" | tee -a "$OUTPUT_FILE"
    
    log_subsection "Ping to Target Database Server"
    log_info "Target: $TARGET_HOST"
    if ping -c 5 "$TARGET_HOST" 2>&1 | tee -a "$OUTPUT_FILE"; then
        log_info ""
        log_info "Ping statistics:"
        ping -c 10 "$TARGET_HOST" 2>/dev/null | tail -3 | tee -a "$OUTPUT_FILE"
    else
        log_warning "Ping to target failed - host may not respond to ICMP"
    fi
    
    log_subsection "Port Connectivity Tests"
    log_info ""
    log_info "Testing SSH port (22) connectivity..."
    
    # Test SSH to source
    timeout 5 bash -c "</dev/tcp/$SOURCE_HOST/22" 2>/dev/null && \
        log_info "✓ SSH port open on $SOURCE_HOST" || \
        log_warning "✗ Cannot connect to SSH port on $SOURCE_HOST"
    
    # Test SSH to target
    timeout 5 bash -c "</dev/tcp/$TARGET_HOST/22" 2>/dev/null && \
        log_info "✓ SSH port open on $TARGET_HOST" || \
        log_warning "✗ Cannot connect to SSH port on $TARGET_HOST"
    
    log_info ""
    log_info "Testing Oracle listener port (1521) connectivity..."
    
    # Test listener to source
    timeout 5 bash -c "</dev/tcp/$SOURCE_HOST/1521" 2>/dev/null && \
        log_info "✓ Listener port open on $SOURCE_HOST" || \
        log_warning "✗ Cannot connect to listener port on $SOURCE_HOST"
    
    # Test listener to target
    timeout 5 bash -c "</dev/tcp/$TARGET_HOST/1521" 2>/dev/null && \
        log_info "✓ Listener port open on $TARGET_HOST" || \
        log_warning "✗ Cannot connect to listener port on $TARGET_HOST"
    
    log_subsection "Traceroute to Source"
    traceroute -m 15 "$SOURCE_HOST" 2>/dev/null | head -20 | tee -a "$OUTPUT_FILE" || \
        log_info "traceroute not available"
    
    log_subsection "Traceroute to Target"
    traceroute -m 15 "$TARGET_HOST" 2>/dev/null | head -20 | tee -a "$OUTPUT_FILE" || \
        log_info "traceroute not available"
}

discover_ssh_connectivity() {
    log_section "SSH CONNECTIVITY VERIFICATION"
    
    log_subsection "SSH Keys for This Migration"
    log_info "Expected SSH keys:"
    log_info "  Source: ~/.ssh/source_db_key"
    log_info "  Target: ~/.ssh/oda_azure_key"
    log_info "  ZDM:    ~/.ssh/zdm_jumpbox_key"
    log_info ""
    
    for keyfile in ~/.ssh/source_db_key ~/.ssh/oda_azure_key ~/.ssh/zdm_jumpbox_key; do
        if [ -f "$keyfile" ]; then
            log_info "✓ Found: $keyfile"
            perms=$(stat -c %a "$keyfile" 2>/dev/null || stat -f %A "$keyfile" 2>/dev/null)
            log_info "  Permissions: $perms"
        else
            log_warning "✗ Not found: $keyfile"
        fi
    done
}

################################################################################
# Main Execution
################################################################################

main() {
    echo "" | tee "$OUTPUT_FILE"
    echo "================================================================================" | tee -a "$OUTPUT_FILE"
    echo "= ZDM Server Discovery Report" | tee -a "$OUTPUT_FILE"
    echo "= Project: PRODDB Migration to Oracle Database@Azure" | tee -a "$OUTPUT_FILE"
    echo "= Server: zdm-jumpbox.corp.example.com" | tee -a "$OUTPUT_FILE"
    echo "= Hostname: $HOSTNAME" | tee -a "$OUTPUT_FILE"
    echo "= User: $(whoami)" | tee -a "$OUTPUT_FILE"
    echo "= Timestamp: $(date)" | tee -a "$OUTPUT_FILE"
    echo "= Script Version: $SCRIPT_VERSION" | tee -a "$OUTPUT_FILE"
    echo "================================================================================" | tee -a "$OUTPUT_FILE"
    
    # Run all discovery functions - continue even if some fail
    discover_os_info || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_zdm_installation || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_java_config || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_oci_cli || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_ssh_config || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_credential_files || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_network_config || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_zdm_logs || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    
    # Additional PRODDB-specific discovery for ZDM server
    discover_disk_space || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_network_latency || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_ssh_connectivity || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    
    # Summary
    log_section "DISCOVERY SUMMARY"
    log_info "Discovery completed at: $(date)"
    log_info "Section errors encountered: $SECTION_ERRORS"
    log_info "Text report: $OUTPUT_FILE"
    log_info "JSON summary: $JSON_FILE"
    
    # Build final JSON
    cat > "$JSON_FILE" << EOF
{
  "discovery_type": "zdm_server",
  "project": "PRODDB Migration to Oracle Database@Azure",
  "target_server": "zdm-jumpbox.corp.example.com",
  "hostname": "$HOSTNAME",
  "current_user": "$(whoami)",
  "timestamp": "$(date -Iseconds 2>/dev/null || date)",
  "script_version": "$SCRIPT_VERSION",
  "zdm_home": "${ZDM_HOME:-null}",
  "java_home": "${JAVA_HOME:-null}",
  "section_errors": $SECTION_ERRORS,
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
    
    echo ""
    log_success "Discovery complete!"
    echo ""
    echo "Output files:"
    echo "  Text Report: $OUTPUT_FILE"
    echo "  JSON Summary: $JSON_FILE"
    echo ""
    
    # Always exit 0 so orchestrator knows script completed
    exit 0
}

# Run main
main "$@"
