#!/bin/bash
#===============================================================================
# ZDM Server Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
#
# Purpose: Discover ZDM jumpbox server configuration for migration planning.
#          Executed via SSH as admin user, ZDM CLI commands run as zdmuser.
#
# Usage: ./zdm_server_discovery.sh
#
# Output:
#   - zdm_server_discovery_<hostname>_<timestamp>.txt (human-readable report)
#   - zdm_server_discovery_<hostname>_<timestamp>.json (machine-parseable)
#===============================================================================

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

# Output files (current working directory)
TEXT_REPORT="./zdm_server_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
JSON_REPORT="./zdm_server_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

# Default ZDM user if not set
ZDM_USER="${ZDM_USER:-zdmuser}"

#===============================================================================
# ENVIRONMENT DETECTION
#===============================================================================

detect_zdm_env() {
    # If already set, use existing values
    if [ -n "${ZDM_HOME:-}" ] && [ -n "${JAVA_HOME:-}" ]; then
        return 0
    fi
    
    # Detect ZDM_HOME
    if [ -z "${ZDM_HOME:-}" ]; then
        # Check common ZDM installation locations
        for path in ~/zdmhome ~/zdm /opt/zdm /u01/zdm "$HOME/zdmhome" /home/zdmuser/zdmhome /home/*/zdmhome; do
            if [ -d "$path" ] && [ -f "$path/bin/zdmcli" ]; then
                export ZDM_HOME="$path"
                break
            fi
        done
        
        # Check if zdmuser has ZDM_HOME set
        if [ -z "${ZDM_HOME:-}" ]; then
            local zdm_user_home=$(eval echo ~$ZDM_USER 2>/dev/null)
            if [ -d "$zdm_user_home/zdmhome" ]; then
                export ZDM_HOME="$zdm_user_home/zdmhome"
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
            fi
        fi
        
        # Method 2: Search common Java paths
        if [ -z "${JAVA_HOME:-}" ]; then
            for path in /usr/java/latest /usr/java/jdk* /usr/lib/jvm/java-* /opt/java/jdk* /usr/lib/jvm/jre-*; do
                if [ -d "$path" ] && [ -f "$path/bin/java" ]; then
                    export JAVA_HOME="$path"
                    break
                fi
            done
        fi
    fi
}

# Apply explicit overrides if provided
[ -n "${ZDM_HOME_OVERRIDE:-}" ] && export ZDM_HOME="$ZDM_HOME_OVERRIDE"
[ -n "${JAVA_HOME_OVERRIDE:-}" ] && export JAVA_HOME="$JAVA_HOME_OVERRIDE"

# Detect ZDM environment
detect_zdm_env

#===============================================================================
# ZDM EXECUTION FUNCTIONS
#===============================================================================

run_zdm_cmd() {
    local zdm_cmd="$1"
    if [ -n "${ZDM_HOME:-}" ]; then
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
# OUTPUT FUNCTIONS
#===============================================================================

print_header() {
    local title="$1"
    echo "" >> "$TEXT_REPORT"
    echo "===============================================================================" >> "$TEXT_REPORT"
    echo "  $title" >> "$TEXT_REPORT"
    echo "===============================================================================" >> "$TEXT_REPORT"
    echo -e "${BLUE}=== $title ===${NC}"
}

print_section() {
    local title="$1"
    echo "" >> "$TEXT_REPORT"
    echo "--- $title ---" >> "$TEXT_REPORT"
    echo -e "${GREEN}--- $title ---${NC}"
}

print_info() {
    local label="$1"
    local value="$2"
    printf "%-30s: %s\n" "$label" "$value" >> "$TEXT_REPORT"
    printf "${CYAN}%-30s${NC}: %s\n" "$label" "$value"
}

print_output() {
    local output="$1"
    echo "$output" >> "$TEXT_REPORT"
    echo "$output"
}

#===============================================================================
# JSON BUILDER
#===============================================================================

declare -A JSON_DATA

add_json() {
    local key="$1"
    local value="$2"
    JSON_DATA["$key"]="$value"
}

write_json() {
    echo "{" > "$JSON_REPORT"
    local first=true
    for key in "${!JSON_DATA[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> "$JSON_REPORT"
        fi
        local value="${JSON_DATA[$key]}"
        if [[ "$value" =~ ^\[.*\]$ ]] || [[ "$value" =~ ^\{.*\}$ ]]; then
            printf '  "%s": %s' "$key" "$value" >> "$JSON_REPORT"
        else
            printf '  "%s": "%s"' "$key" "$value" >> "$JSON_REPORT"
        fi
    done
    echo "" >> "$JSON_REPORT"
    echo "}" >> "$JSON_REPORT"
}

#===============================================================================
# DISCOVERY FUNCTIONS
#===============================================================================

discover_os_info() {
    print_header "OS INFORMATION"
    
    local hostname_full=$(hostname -f 2>/dev/null || hostname)
    local hostname_short=$(hostname -s)
    local current_user=$(whoami)
    local os_version=$(cat /etc/os-release 2>/dev/null | grep "PRETTY_NAME" | cut -d'"' -f2 || uname -a)
    local kernel_version=$(uname -r)
    local ip_addresses=$(hostname -I 2>/dev/null || ip addr show | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | tr '\n' ' ')
    
    print_info "Hostname (Full)" "$hostname_full"
    print_info "Hostname (Short)" "$hostname_short"
    print_info "Current User" "$current_user"
    print_info "OS Version" "$os_version"
    print_info "Kernel Version" "$kernel_version"
    print_info "IP Addresses" "$ip_addresses"
    
    add_json "hostname_full" "$hostname_full"
    add_json "hostname_short" "$hostname_short"
    add_json "current_user" "$current_user"
    add_json "os_version" "$os_version"
    add_json "kernel_version" "$kernel_version"
    add_json "ip_addresses" "$ip_addresses"
}

discover_zdm_installation() {
    print_header "ZDM INSTALLATION"
    
    print_info "ZDM_HOME" "${ZDM_HOME:-NOT FOUND}"
    add_json "zdm_home" "${ZDM_HOME:-NOT FOUND}"
    
    if [ -n "${ZDM_HOME:-}" ] && [ -d "${ZDM_HOME}" ]; then
        print_section "ZDM Version"
        local zdm_version=$(run_zdm_cmd "zdmcli -version" 2>/dev/null | head -5)
        print_output "$zdm_version"
        add_json "zdm_version" "$(echo "$zdm_version" | head -1)"
        
        print_section "ZDM Service Status"
        local zdm_status=$(run_zdm_cmd "zdmservice status" 2>/dev/null)
        print_output "$zdm_status"
        
        if echo "$zdm_status" | grep -q "running"; then
            add_json "zdm_service_status" "running"
        else
            add_json "zdm_service_status" "not running"
        fi
        
        print_section "Active Migration Jobs"
        local active_jobs=$(run_zdm_cmd "zdmcli query job -jobtype MIGRATE_DATABASE" 2>/dev/null | head -20)
        print_output "$active_jobs"
        
        local job_count=$(echo "$active_jobs" | grep -c "JOBID" || echo "0")
        add_json "active_migration_jobs" "$job_count"
    else
        print_info "ZDM Status" "ZDM_HOME not found or not accessible"
        add_json "zdm_service_status" "not installed"
    fi
}

discover_java_config() {
    print_header "JAVA CONFIGURATION"
    
    print_info "JAVA_HOME" "${JAVA_HOME:-NOT SET}"
    add_json "java_home" "${JAVA_HOME:-NOT SET}"
    
    if command -v java >/dev/null 2>&1; then
        local java_version=$(java -version 2>&1 | head -3)
        print_section "Java Version"
        print_output "$java_version"
        add_json "java_version" "$(echo "$java_version" | head -1)"
    else
        print_info "Java" "NOT FOUND"
        add_json "java_version" "NOT FOUND"
    fi
}

discover_oci_config() {
    print_header "OCI CLI CONFIGURATION"
    
    if command -v oci >/dev/null 2>&1; then
        local oci_version=$(oci --version 2>&1)
        print_info "OCI CLI Version" "$oci_version"
        add_json "oci_cli_version" "$oci_version"
        add_json "oci_cli_installed" "true"
        
        print_section "OCI Config File"
        local oci_config="$HOME/.oci/config"
        if [ -f "$oci_config" ]; then
            print_info "Config Location" "$oci_config"
            add_json "oci_config_path" "$oci_config"
            
            # Show config with sensitive data masked
            print_output "Config Contents (sensitive data masked):"
            sed 's/fingerprint=.*/fingerprint=***MASKED***/g' "$oci_config" 2>/dev/null | \
            sed 's/pass_phrase=.*/pass_phrase=***MASKED***/g' >> "$TEXT_REPORT"
            
            # List profiles
            local profiles=$(grep '^\[' "$oci_config" 2>/dev/null | tr -d '[]')
            print_section "Configured Profiles"
            print_output "$profiles"
            
            # List regions
            local regions=$(grep 'region=' "$oci_config" 2>/dev/null | cut -d= -f2 | sort -u)
            print_section "Configured Regions"
            print_output "$regions"
        else
            print_info "OCI Config" "NOT FOUND at $oci_config"
            add_json "oci_config_exists" "false"
        fi
        
        print_section "API Key File"
        local key_file=$(grep 'key_file=' "$oci_config" 2>/dev/null | head -1 | cut -d= -f2)
        if [ -n "$key_file" ]; then
            # Expand ~ to home directory
            key_file="${key_file/#\~/$HOME}"
            if [ -f "$key_file" ]; then
                print_info "API Key File" "EXISTS: $key_file"
                add_json "oci_api_key_exists" "true"
            else
                print_info "API Key File" "NOT FOUND: $key_file"
                add_json "oci_api_key_exists" "false"
            fi
        fi
        
        print_section "OCI Connectivity Test"
        if oci iam region list --output table 2>&1 | head -10 >> "$TEXT_REPORT"; then
            print_info "OCI Connectivity" "SUCCESS"
            add_json "oci_connectivity" "success"
        else
            print_info "OCI Connectivity" "FAILED"
            add_json "oci_connectivity" "failed"
        fi
    else
        print_info "OCI CLI" "NOT INSTALLED"
        add_json "oci_cli_installed" "false"
    fi
}

discover_ssh_config() {
    print_header "SSH CONFIGURATION"
    
    print_section "SSH Directory Contents"
    if [ -d ~/.ssh ]; then
        ls -la ~/.ssh 2>/dev/null >> "$TEXT_REPORT"
        
        print_section "Available SSH Keys"
        for key in ~/.ssh/*.pub; do
            if [ -f "$key" ]; then
                local key_name=$(basename "$key")
                local private_key="${key%.pub}"
                if [ -f "$private_key" ]; then
                    print_info "$key_name" "Private key exists"
                else
                    print_info "$key_name" "Public key only"
                fi
            fi
        done
    else
        print_output "SSH directory not found"
    fi
    
    # Check zdmuser's SSH keys
    print_section "ZDM User SSH Keys"
    local zdm_user_home=$(eval echo ~$ZDM_USER 2>/dev/null)
    if [ -d "$zdm_user_home/.ssh" ]; then
        sudo ls -la "$zdm_user_home/.ssh" 2>/dev/null >> "$TEXT_REPORT" || \
        print_output "Cannot access $ZDM_USER SSH directory"
    else
        print_output "$ZDM_USER SSH directory not found"
    fi
}

discover_credential_files() {
    print_header "CREDENTIAL FILES"
    
    print_section "Searching for Credential Files"
    
    # Search common locations for credential files
    local search_paths="/home /opt /u01 /var"
    local cred_patterns="*password* *credential* *wallet* *.pem *.key"
    
    for pattern in $cred_patterns; do
        local found=$(find $search_paths -name "$pattern" -type f 2>/dev/null | head -10)
        if [ -n "$found" ]; then
            print_output "Files matching '$pattern':"
            echo "$found" >> "$TEXT_REPORT"
        fi
    done
    
    print_section "ZDM Response Files"
    if [ -n "${ZDM_HOME:-}" ]; then
        local rsp_files=$(find "${ZDM_HOME}" -name "*.rsp" -type f 2>/dev/null)
        if [ -n "$rsp_files" ]; then
            print_output "Response files found:"
            echo "$rsp_files" >> "$TEXT_REPORT"
        else
            print_output "No response files found in ZDM_HOME"
        fi
    fi
}

discover_network_config() {
    print_header "NETWORK CONFIGURATION"
    
    print_section "IP Addresses"
    ip addr show 2>/dev/null | grep 'inet ' >> "$TEXT_REPORT" || \
    ifconfig 2>/dev/null | grep 'inet ' >> "$TEXT_REPORT"
    
    print_section "Routing Table"
    ip route 2>/dev/null | head -20 >> "$TEXT_REPORT" || \
    route -n 2>/dev/null | head -20 >> "$TEXT_REPORT"
    
    print_section "DNS Configuration"
    cat /etc/resolv.conf 2>/dev/null >> "$TEXT_REPORT"
}

discover_zdm_logs() {
    print_header "ZDM LOGS"
    
    if [ -n "${ZDM_HOME:-}" ]; then
        local log_dir="${ZDM_HOME}/log"
        if [ -d "$log_dir" ]; then
            print_info "Log Directory" "$log_dir"
            add_json "zdm_log_dir" "$log_dir"
            
            print_section "Recent Log Files"
            ls -lt "$log_dir"/*.log 2>/dev/null | head -10 >> "$TEXT_REPORT" || \
            print_output "No log files found"
            
            print_section "Log Directory Size"
            du -sh "$log_dir" 2>/dev/null >> "$TEXT_REPORT"
        else
            print_output "Log directory not found: $log_dir"
        fi
    else
        print_output "ZDM_HOME not set - cannot locate logs"
    fi
}

discover_disk_space() {
    print_header "DISK SPACE FOR ZDM OPERATIONS"
    
    print_section "Disk Usage"
    df -h 2>/dev/null >> "$TEXT_REPORT"
    
    # Check ZDM_HOME partition specifically
    if [ -n "${ZDM_HOME:-}" ]; then
        print_section "ZDM_HOME Partition"
        local zdm_partition=$(df -h "${ZDM_HOME}" 2>/dev/null | tail -1)
        print_output "$zdm_partition"
        
        local available_gb=$(df -BG "${ZDM_HOME}" 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')
        print_info "Available Space (GB)" "$available_gb"
        add_json "zdm_available_space_gb" "$available_gb"
        
        # Check if minimum 50GB recommended
        if [ -n "$available_gb" ] && [ "$available_gb" -lt 50 ] 2>/dev/null; then
            print_output ""
            echo -e "${YELLOW}⚠ WARNING: Less than 50GB available. Recommended minimum is 50GB for ZDM operations.${NC}"
            echo "WARNING: Less than 50GB available. Recommended minimum is 50GB for ZDM operations." >> "$TEXT_REPORT"
            add_json "zdm_space_warning" "true"
        else
            add_json "zdm_space_warning" "false"
        fi
    fi
    
    print_section "/tmp Space"
    df -h /tmp 2>/dev/null >> "$TEXT_REPORT"
}

discover_network_latency() {
    print_header "NETWORK LATENCY TESTS"
    
    # Source server connectivity (placeholder - actual host would be passed or configured)
    local source_host="${SOURCE_HOST:-proddb01.corp.example.com}"
    local target_host="${TARGET_HOST:-proddb-oda.eastus.azure.example.com}"
    
    print_section "Ping Test to Source ($source_host)"
    if ping -c 5 "$source_host" 2>&1 >> "$TEXT_REPORT"; then
        local source_latency=$(ping -c 5 "$source_host" 2>/dev/null | tail -1 | awk -F'/' '{print $5}')
        print_info "Average Latency to Source" "${source_latency}ms"
        add_json "source_latency_ms" "$source_latency"
    else
        print_output "Unable to ping source host"
        add_json "source_latency_ms" "unreachable"
    fi
    
    print_section "Ping Test to Target ($target_host)"
    if ping -c 5 "$target_host" 2>&1 >> "$TEXT_REPORT"; then
        local target_latency=$(ping -c 5 "$target_host" 2>/dev/null | tail -1 | awk -F'/' '{print $5}')
        print_info "Average Latency to Target" "${target_latency}ms"
        add_json "target_latency_ms" "$target_latency"
    else
        print_output "Unable to ping target host"
        add_json "target_latency_ms" "unreachable"
    fi
    
    print_section "SSH Port Connectivity"
    # Test SSH port connectivity
    for host in "$source_host" "$target_host"; do
        if timeout 5 bash -c "echo >/dev/tcp/$host/22" 2>/dev/null; then
            print_info "SSH to $host" "Port 22 OPEN"
        else
            print_info "SSH to $host" "Port 22 CLOSED or filtered"
        fi
    done
    
    print_section "Oracle Port Connectivity"
    # Test Oracle listener port
    for host in "$source_host" "$target_host"; do
        if timeout 5 bash -c "echo >/dev/tcp/$host/1521" 2>/dev/null; then
            print_info "Oracle to $host" "Port 1521 OPEN"
        else
            print_info "Oracle to $host" "Port 1521 CLOSED or filtered"
        fi
    done
}

#===============================================================================
# MAIN EXECUTION
#===============================================================================

main() {
    echo "ZDM Server Discovery Script" > "$TEXT_REPORT"
    echo "Generated: $(date)" >> "$TEXT_REPORT"
    echo "Hostname: $(hostname)" >> "$TEXT_REPORT"
    echo "User: $(whoami)" >> "$TEXT_REPORT"
    
    add_json "discovery_type" "zdm_server"
    add_json "discovery_timestamp" "$(date -Iseconds)"
    add_json "discovered_by" "$(whoami)"
    
    echo -e "${CYAN}Starting ZDM Server Discovery...${NC}"
    echo -e "${CYAN}Output files will be created in current directory${NC}"
    
    # Run all discovery functions (continue on error)
    discover_os_info || echo "Warning: OS info discovery had errors"
    discover_zdm_installation || echo "Warning: ZDM installation discovery had errors"
    discover_java_config || echo "Warning: Java config discovery had errors"
    discover_oci_config || echo "Warning: OCI config discovery had errors"
    discover_ssh_config || echo "Warning: SSH config discovery had errors"
    discover_credential_files || echo "Warning: Credential file discovery had errors"
    discover_network_config || echo "Warning: Network config discovery had errors"
    discover_zdm_logs || echo "Warning: ZDM logs discovery had errors"
    
    # Additional discovery requirements
    discover_disk_space || echo "Warning: Disk space discovery had errors"
    discover_network_latency || echo "Warning: Network latency discovery had errors"
    
    # Write JSON report
    write_json
    
    echo ""
    echo -e "${GREEN}===============================================================================${NC}"
    echo -e "${GREEN}Discovery Complete${NC}"
    echo -e "${GREEN}===============================================================================${NC}"
    echo -e "Text Report: ${CYAN}$TEXT_REPORT${NC}"
    echo -e "JSON Report: ${CYAN}$JSON_REPORT${NC}"
}

# Run main function
main "$@"
