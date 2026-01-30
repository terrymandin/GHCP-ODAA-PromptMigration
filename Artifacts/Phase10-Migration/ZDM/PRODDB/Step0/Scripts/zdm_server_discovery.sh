#!/bin/bash
# =============================================================================
# ZDM Server Discovery Script
# =============================================================================
# Project: PRODDB Migration to Oracle Database@Azure
# ZDM Server: zdm-jumpbox.corp.example.com
# Generated: 2026-01-30
#
# Purpose:
#   Gather comprehensive discovery information from the ZDM jumpbox server
#   to support ZDM migration planning and execution.
#
# Execution:
#   This script is executed via SSH as the admin user (azureuser), with ZDM 
#   CLI commands running as zdmuser via sudo if needed.
#
# Output:
#   - Text report: ./zdm_server_discovery_<hostname>_<timestamp>.txt
#   - JSON summary: ./zdm_server_discovery_<hostname>_<timestamp>.json
# =============================================================================

# NO set -e - We want to continue even if some checks fail
SECTION_ERRORS=0

# =============================================================================
# COLOR CONFIGURATION
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# =============================================================================
# USER CONFIGURATION
# =============================================================================
# ZDM software owner (for running ZDM CLI commands)
ZDM_USER="${ZDM_USER:-zdmuser}"

# Source and Target hosts for network tests
SOURCE_HOST="${SOURCE_HOST:-proddb01.corp.example.com}"
TARGET_HOST="${TARGET_HOST:-proddb-oda.eastus.azure.example.com}"

# =============================================================================
# ENVIRONMENT VARIABLE DISCOVERY
# =============================================================================

# CRITICAL: Handle environment variables in non-interactive SSH sessions
# .bashrc often has guards like '[ -z "$PS1" ] && return' that skip non-interactive shells

# Method 1: Accept explicit overrides (passed from orchestration script - highest priority)
[ -n "${ZDM_HOME_OVERRIDE:-}" ] && export ZDM_HOME="$ZDM_HOME_OVERRIDE"
[ -n "${JAVA_HOME_OVERRIDE:-}" ] && export JAVA_HOME="$JAVA_HOME_OVERRIDE"

# Method 2: Extract export statements from profiles (bypasses interactive guards)
for profile in /etc/profile ~/.bash_profile ~/.bashrc; do
    if [ -f "$profile" ]; then
        eval "$(grep -E '^export\s+(ZDM_HOME|JAVA_HOME|PATH)=' "$profile" 2>/dev/null)" || true
    fi
done

# Method 3: Also check zdmuser's profiles
for profile in /home/$ZDM_USER/.bash_profile /home/$ZDM_USER/.bashrc; do
    if [ -f "$profile" ]; then
        eval "$(grep -E '^export\s+(ZDM_HOME|JAVA_HOME|PATH)=' "$profile" 2>/dev/null)" || true
    fi
done

# Method 4: Auto-detect ZDM environment
detect_zdm_env() {
    # If already set, use existing values
    if [ -n "${ZDM_HOME:-}" ] && [ -n "${JAVA_HOME:-}" ]; then
        return 0
    fi
    
    # Detect ZDM_HOME
    if [ -z "${ZDM_HOME:-}" ]; then
        # Check common ZDM installation locations
        for path in /home/$ZDM_USER/zdmhome /home/*/zdmhome ~/zdmhome ~/zdm /opt/zdm* /u01/app/zdm* /u01/zdm*; do
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
            for path in /usr/java/latest /usr/java/jdk* /usr/lib/jvm/java-* /opt/java/jdk* /usr/lib/jvm/jre*; do
                if [ -d "$path" ] && [ -f "$path/bin/java" ]; then
                    export JAVA_HOME="$path"
                    break
                fi
            done
        fi
    fi
}

detect_zdm_env

# =============================================================================
# OUTPUT CONFIGURATION
# =============================================================================
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname)
OUTPUT_FILE="./zdm_server_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_server_discovery_${HOSTNAME}_${TIMESTAMP}.json"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

log_section() {
    local section_name="$1"
    echo "" | tee -a "$OUTPUT_FILE"
    echo "=============================================================================" | tee -a "$OUTPUT_FILE"
    echo " $section_name" | tee -a "$OUTPUT_FILE"
    echo "=============================================================================" | tee -a "$OUTPUT_FILE"
    echo -e "${CYAN}[SECTION]${NC} $section_name"
}

log_info() {
    echo "$1" | tee -a "$OUTPUT_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    echo "[SUCCESS] $1" >> "$OUTPUT_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "[WARNING] $1" >> "$OUTPUT_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[ERROR] $1" >> "$OUTPUT_FILE"
}

run_zdm_cmd() {
    local zdm_cmd="$1"
    if [ -n "${ZDM_HOME:-}" ]; then
        # Execute as zdmuser - use sudo if current user is not zdmuser
        if [ "$(whoami)" = "$ZDM_USER" ]; then
            $ZDM_HOME/bin/$zdm_cmd 2>&1
        else
            sudo -u "$ZDM_USER" -E ZDM_HOME="$ZDM_HOME" $ZDM_HOME/bin/$zdm_cmd 2>&1
        fi
    else
        echo "ERROR: ZDM_HOME not set"
        return 1
    fi
}

# =============================================================================
# INITIALIZE JSON OUTPUT
# =============================================================================
init_json() {
    cat > "$JSON_FILE" <<EOF
{
  "discovery_type": "zdm_server",
  "timestamp": "$(date -Iseconds)",
  "hostname": "$HOSTNAME",
  "project": "PRODDB Migration to Oracle Database@Azure",
  "zdm_server": "zdm-jumpbox.corp.example.com",
EOF
}

append_json() {
    local key="$1"
    local value="$2"
    echo "  \"$key\": \"$value\"," >> "$JSON_FILE"
}

append_json_object() {
    local key="$1"
    local value="$2"
    echo "  \"$key\": $value," >> "$JSON_FILE"
}

finalize_json() {
    echo "  \"discovery_complete\": true" >> "$JSON_FILE"
    echo "}" >> "$JSON_FILE"
}

# =============================================================================
# DISCOVERY FUNCTIONS
# =============================================================================

discover_os_info() {
    log_section "OPERATING SYSTEM INFORMATION"
    
    log_info "Hostname: $(hostname)"
    log_info "Current User: $(whoami)"
    log_info ""
    
    log_info "Operating System:"
    cat /etc/os-release 2>/dev/null | head -5 | tee -a "$OUTPUT_FILE" || \
        cat /etc/redhat-release 2>/dev/null | tee -a "$OUTPUT_FILE" || \
        uname -a | tee -a "$OUTPUT_FILE"
    log_info ""
    
    log_info "Kernel Version: $(uname -r)"
    log_info ""
    
    log_info "Memory:"
    free -h 2>/dev/null | tee -a "$OUTPUT_FILE" || cat /proc/meminfo | head -3 | tee -a "$OUTPUT_FILE"
    
    append_json "hostname" "$HOSTNAME"
    append_json "os_version" "$(cat /etc/os-release 2>/dev/null | grep '^VERSION=' | cut -d= -f2 | tr -d '\"')"
}

discover_zdm_installation() {
    log_section "ZDM INSTALLATION"
    
    log_info "ZDM_HOME: ${ZDM_HOME:-NOT SET}"
    
    if [ -n "${ZDM_HOME:-}" ] && [ -d "$ZDM_HOME" ]; then
        log_info ""
        log_info "ZDM Version:"
        run_zdm_cmd "zdmcli -version" | tee -a "$OUTPUT_FILE" || log_warning "Could not get ZDM version"
        
        log_info ""
        log_info "ZDM Service Status:"
        run_zdm_cmd "zdmservice status" | tee -a "$OUTPUT_FILE" || log_warning "Could not get ZDM service status"
        
        log_info ""
        log_info "Active Migration Jobs:"
        run_zdm_cmd "zdmcli query job -all" | tee -a "$OUTPUT_FILE" || log_info "No active jobs or could not query jobs"
        
        append_json "zdm_home" "$ZDM_HOME"
    else
        log_warning "ZDM_HOME not found or not set"
        log_info ""
        log_info "Searching for ZDM installation..."
        find /home /opt /u01 -name "zdmcli" -type f 2>/dev/null | head -5 | tee -a "$OUTPUT_FILE" || log_info "No ZDM installation found"
    fi
}

discover_java_config() {
    log_section "JAVA CONFIGURATION"
    
    log_info "JAVA_HOME: ${JAVA_HOME:-NOT SET}"
    log_info ""
    
    log_info "Java Version:"
    if [ -n "${JAVA_HOME:-}" ] && [ -f "$JAVA_HOME/bin/java" ]; then
        $JAVA_HOME/bin/java -version 2>&1 | tee -a "$OUTPUT_FILE"
        append_json "java_home" "$JAVA_HOME"
    elif command -v java >/dev/null 2>&1; then
        java -version 2>&1 | tee -a "$OUTPUT_FILE"
        append_json "java_home" "system"
    else
        log_warning "Java not found"
    fi
    
    log_info ""
    log_info "Java Alternatives (if available):"
    alternatives --display java 2>/dev/null | head -10 | tee -a "$OUTPUT_FILE" || \
        update-alternatives --display java 2>/dev/null | head -10 | tee -a "$OUTPUT_FILE" || \
        log_info "Java alternatives not configured"
}

discover_oci_cli() {
    log_section "OCI CLI CONFIGURATION"
    
    log_info "OCI CLI Version:"
    oci --version 2>&1 | tee -a "$OUTPUT_FILE" || log_warning "OCI CLI not installed or not in PATH"
    
    log_info ""
    log_info "OCI Config Location:"
    for config_path in ~/.oci/config /home/$ZDM_USER/.oci/config; do
        if [ -f "$config_path" ]; then
            log_info "Found: $config_path"
            
            log_info ""
            log_info "Configured Profiles:"
            grep '^\[' "$config_path" 2>/dev/null | tee -a "$OUTPUT_FILE"
            
            log_info ""
            log_info "Configured Regions:"
            grep '^region' "$config_path" 2>/dev/null | tee -a "$OUTPUT_FILE"
            
            log_info ""
            log_info "Config Contents (sensitive data masked):"
            sed 's/key=.*/key=***MASKED***/g; s/fingerprint=.*/fingerprint=***MASKED***/g; s/pass_phrase=.*/pass_phrase=***MASKED***/g' "$config_path" 2>/dev/null | tee -a "$OUTPUT_FILE"
        fi
    done
    
    log_info ""
    log_info "API Key Files:"
    for key_dir in ~/.oci /home/$ZDM_USER/.oci; do
        if [ -d "$key_dir" ]; then
            ls -la "$key_dir"/*.pem 2>/dev/null | tee -a "$OUTPUT_FILE" || log_info "No .pem files in $key_dir"
        fi
    done
    
    log_info ""
    log_info "OCI Connectivity Test:"
    timeout 15 oci iam region list --query "data[0:3].name" 2>&1 | tee -a "$OUTPUT_FILE" || \
        log_warning "OCI connectivity test failed or timed out"
}

discover_ssh_config() {
    log_section "SSH CONFIGURATION"
    
    log_info "SSH Directory (~/.ssh):"
    ls -la ~/.ssh/ 2>/dev/null | tee -a "$OUTPUT_FILE" || log_warning "SSH directory not found or not accessible"
    
    log_info ""
    log_info "Available SSH Keys (private):"
    for key_file in ~/.ssh/id_* ~/.ssh/*_key ~/.ssh/*.pem; do
        if [ -f "$key_file" ] && [[ ! "$key_file" == *.pub ]]; then
            log_info "  $key_file ($(stat -c %a "$key_file" 2>/dev/null || stat -f %Mp%Lp "$key_file" 2>/dev/null) permissions)"
        fi
    done 2>/dev/null | tee -a "$OUTPUT_FILE"
    
    log_info ""
    log_info "Available SSH Keys (public):"
    ls -la ~/.ssh/*.pub 2>/dev/null | tee -a "$OUTPUT_FILE" || log_info "No public keys found"
    
    log_info ""
    log_info "SSH Config File:"
    if [ -f ~/.ssh/config ]; then
        cat ~/.ssh/config 2>/dev/null | tee -a "$OUTPUT_FILE"
    else
        log_info "No SSH config file found"
    fi
    
    log_info ""
    log_info "ZDM User SSH Keys (/home/$ZDM_USER/.ssh):"
    sudo ls -la /home/$ZDM_USER/.ssh/ 2>/dev/null | tee -a "$OUTPUT_FILE" || \
        ls -la /home/$ZDM_USER/.ssh/ 2>/dev/null | tee -a "$OUTPUT_FILE" || \
        log_info "Could not access $ZDM_USER SSH directory"
}

discover_credential_files() {
    log_section "CREDENTIAL FILES"
    
    log_info "Searching for password/credential files..."
    log_info ""
    
    log_info "ZDM Response Files:"
    find /home /opt /tmp -name "*.rsp" -type f 2>/dev/null | head -20 | tee -a "$OUTPUT_FILE" || log_info "No .rsp files found"
    
    log_info ""
    log_info "Wallet Directories:"
    find /home /opt -type d -name "*wallet*" 2>/dev/null | head -10 | tee -a "$OUTPUT_FILE" || log_info "No wallet directories found"
    
    log_info ""
    log_info "Potential Credential Files (names only):"
    find /home /opt -type f \( -name "*password*" -o -name "*credential*" -o -name "*secret*" \) 2>/dev/null | head -10 | tee -a "$OUTPUT_FILE" || log_info "No credential files found"
}

discover_network_config() {
    log_section "NETWORK CONFIGURATION"
    
    log_info "IP Addresses:"
    ip addr show 2>/dev/null | grep "inet " | awk '{print $2}' | tee -a "$OUTPUT_FILE" || \
        ifconfig 2>/dev/null | grep "inet " | awk '{print $2}' | tee -a "$OUTPUT_FILE" || \
        hostname -I 2>/dev/null | tee -a "$OUTPUT_FILE"
    log_info ""
    
    log_info "Default Gateway:"
    ip route | grep default | tee -a "$OUTPUT_FILE" || route -n | grep UG | tee -a "$OUTPUT_FILE"
    log_info ""
    
    log_info "DNS Configuration:"
    cat /etc/resolv.conf 2>/dev/null | grep -v '^#' | tee -a "$OUTPUT_FILE"
    log_info ""
    
    log_info "Hosts File Entries (non-default):"
    cat /etc/hosts 2>/dev/null | grep -v '^#' | grep -v '^$' | grep -v 'localhost' | tee -a "$OUTPUT_FILE" || log_info "No custom hosts entries"
}

discover_zdm_logs() {
    log_section "ZDM LOGS"
    
    if [ -n "${ZDM_HOME:-}" ]; then
        log_info "ZDM Log Directory:"
        local log_dir="$ZDM_HOME/logs"
        if [ -d "$log_dir" ]; then
            log_info "$log_dir"
            log_info ""
            log_info "Recent Log Files (last 10):"
            ls -lt "$log_dir"/*.log 2>/dev/null | head -10 | tee -a "$OUTPUT_FILE" || log_info "No log files found"
            
            log_info ""
            log_info "Log Directory Size:"
            du -sh "$log_dir" 2>/dev/null | tee -a "$OUTPUT_FILE"
        else
            log_info "ZDM log directory not found at $log_dir"
        fi
        
        log_info ""
        log_info "ZDM Job Logs Directory:"
        local job_log_dir="$ZDM_HOME/rhp"
        if [ -d "$job_log_dir" ]; then
            log_info "$job_log_dir"
            log_info ""
            log_info "Recent Job Directories:"
            ls -lt "$job_log_dir" 2>/dev/null | head -10 | tee -a "$OUTPUT_FILE"
        else
            log_info "ZDM job log directory not found at $job_log_dir"
        fi
    else
        log_warning "ZDM_HOME not set - cannot locate log directories"
    fi
}

# =============================================================================
# ADDITIONAL CUSTOM DISCOVERY (per user requirements)
# =============================================================================

discover_disk_space() {
    log_section "DISK SPACE FOR ZDM OPERATIONS"
    
    log_info "Disk Space Overview:"
    df -h 2>/dev/null | tee -a "$OUTPUT_FILE"
    
    log_info ""
    log_info "ZDM Minimum Requirement: 50GB recommended"
    log_info ""
    
    # Check specific paths
    for path in "/" "/home" "/opt" "/tmp" "${ZDM_HOME:-/nonexistent}"; do
        if [ -d "$path" ]; then
            local available=$(df -BG "$path" 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')
            if [ -n "$available" ]; then
                if [ "$available" -ge 50 ]; then
                    log_success "$path has ${available}GB available (sufficient)"
                else
                    log_warning "$path has ${available}GB available (below 50GB recommended)"
                fi
            fi
        fi
    done
    
    log_info ""
    log_info "Largest Directories in ZDM_HOME (if set):"
    if [ -n "${ZDM_HOME:-}" ] && [ -d "$ZDM_HOME" ]; then
        du -sh "$ZDM_HOME"/* 2>/dev/null | sort -rh | head -10 | tee -a "$OUTPUT_FILE"
    fi
    
    log_info ""
    log_info "Inode Usage:"
    df -i 2>/dev/null | tee -a "$OUTPUT_FILE"
}

discover_network_latency() {
    log_section "NETWORK LATENCY TESTS"
    
    log_info "Testing connectivity and latency to source and target databases..."
    log_info ""
    
    log_info "Ping to Source Database ($SOURCE_HOST):"
    if ping -c 1 "$SOURCE_HOST" >/dev/null 2>&1; then
        ping -c 5 "$SOURCE_HOST" 2>&1 | tail -6 | tee -a "$OUTPUT_FILE"
        log_success "Source host is reachable"
    else
        log_warning "Source host ($SOURCE_HOST) is not reachable via ping"
        log_info "Attempting DNS resolution..."
        host "$SOURCE_HOST" 2>&1 | head -3 | tee -a "$OUTPUT_FILE" || nslookup "$SOURCE_HOST" 2>&1 | head -5 | tee -a "$OUTPUT_FILE"
    fi
    
    log_info ""
    log_info "Ping to Target Database ($TARGET_HOST):"
    if ping -c 1 "$TARGET_HOST" >/dev/null 2>&1; then
        ping -c 5 "$TARGET_HOST" 2>&1 | tail -6 | tee -a "$OUTPUT_FILE"
        log_success "Target host is reachable"
    else
        log_warning "Target host ($TARGET_HOST) is not reachable via ping"
        log_info "Attempting DNS resolution..."
        host "$TARGET_HOST" 2>&1 | head -3 | tee -a "$OUTPUT_FILE" || nslookup "$TARGET_HOST" 2>&1 | head -5 | tee -a "$OUTPUT_FILE"
    fi
    
    log_info ""
    log_info "Port Connectivity Tests:"
    
    # Test SSH ports
    log_info "Testing SSH port (22) to source..."
    timeout 5 bash -c "echo >/dev/tcp/$SOURCE_HOST/22" 2>/dev/null && \
        log_success "SSH port 22 on $SOURCE_HOST is open" || \
        log_warning "SSH port 22 on $SOURCE_HOST is not accessible"
    
    log_info "Testing SSH port (22) to target..."
    timeout 5 bash -c "echo >/dev/tcp/$TARGET_HOST/22" 2>/dev/null && \
        log_success "SSH port 22 on $TARGET_HOST is open" || \
        log_warning "SSH port 22 on $TARGET_HOST is not accessible"
    
    # Test Oracle listener ports
    log_info ""
    log_info "Testing Oracle listener port (1521)..."
    
    timeout 5 bash -c "echo >/dev/tcp/$SOURCE_HOST/1521" 2>/dev/null && \
        log_success "Oracle port 1521 on $SOURCE_HOST is open" || \
        log_warning "Oracle port 1521 on $SOURCE_HOST is not accessible"
    
    timeout 5 bash -c "echo >/dev/tcp/$TARGET_HOST/1521" 2>/dev/null && \
        log_success "Oracle port 1521 on $TARGET_HOST is open" || \
        log_warning "Oracle port 1521 on $TARGET_HOST is not accessible"
    
    log_info ""
    log_info "Traceroute to Source (first 10 hops):"
    traceroute -m 10 "$SOURCE_HOST" 2>&1 | head -12 | tee -a "$OUTPUT_FILE" || \
        log_info "Traceroute not available or host unreachable"
    
    log_info ""
    log_info "Traceroute to Target (first 10 hops):"
    traceroute -m 10 "$TARGET_HOST" 2>&1 | head -12 | tee -a "$OUTPUT_FILE" || \
        log_info "Traceroute not available or host unreachable"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    echo "============================================================================="
    echo " ZDM Server Discovery"
    echo " Project: PRODDB Migration to Oracle Database@Azure"
    echo " Server: zdm-jumpbox.corp.example.com"
    echo " Timestamp: $(date)"
    echo "============================================================================="
    
    # Initialize output files
    echo "ZDM Server Discovery Report" > "$OUTPUT_FILE"
    echo "Generated: $(date)" >> "$OUTPUT_FILE"
    echo "Hostname: $HOSTNAME" >> "$OUTPUT_FILE"
    echo "Project: PRODDB Migration to Oracle Database@Azure" >> "$OUTPUT_FILE"
    
    init_json
    
    # Run discovery sections - continue even if some fail
    discover_os_info || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_zdm_installation || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_java_config || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_oci_cli || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_ssh_config || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_credential_files || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_network_config || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_zdm_logs || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    
    # Additional custom discovery per user requirements
    discover_disk_space || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_network_latency || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    
    # Finalize
    finalize_json
    
    echo ""
    echo "============================================================================="
    if [ $SECTION_ERRORS -gt 0 ]; then
        echo -e "${YELLOW}Discovery completed with $SECTION_ERRORS section(s) having warnings/errors${NC}"
    else
        echo -e "${GREEN}Discovery completed successfully${NC}"
    fi
    echo "Output files:"
    echo "  Text report: $OUTPUT_FILE"
    echo "  JSON summary: $JSON_FILE"
    echo "============================================================================="
    
    # Always exit 0 so orchestrator knows script completed
    exit 0
}

# Run main
main "$@"
