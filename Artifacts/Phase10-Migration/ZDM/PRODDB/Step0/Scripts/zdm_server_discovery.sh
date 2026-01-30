#!/bin/bash
# ZDM Server Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# Target: zdm-jumpbox.corp.example.com
# Generated: 2026-01-30

# NO set -e - We want to continue even if some checks fail
SECTION_ERRORS=0

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# ENVIRONMENT DETECTION AND SETUP
# =============================================================================

# Auto-detect ZDM and Java environments
detect_zdm_env() {
    # If already set, use existing values
    if [ -n "${ZDM_HOME:-}" ] && [ -n "${JAVA_HOME:-}" ]; then
        return 0
    fi
    
    # Detect ZDM_HOME
    if [ -z "${ZDM_HOME:-}" ]; then
        # Check common ZDM installation locations
        for path in ~/zdmhome ~/zdm /opt/zdm /u01/zdm "$HOME/zdmhome" /home/zdmuser/zdmhome; do
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
[ -n "${ZDM_HOME_OVERRIDE:-}" ] && export ZDM_HOME="$ZDM_HOME_OVERRIDE"
[ -n "${JAVA_HOME_OVERRIDE:-}" ] && export JAVA_HOME="$JAVA_HOME_OVERRIDE"

# Extract export statements from profiles (bypasses interactive guards)
for profile in /etc/profile ~/.bash_profile ~/.bashrc; do
    if [ -f "$profile" ]; then
        eval "$(grep -E '^export\s+(ZDM_HOME|JAVA_HOME|PATH)=' "$profile" 2>/dev/null)" || true
    fi
done

# Run auto-detection
detect_zdm_env

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname)
OUTPUT_FILE="./zdm_server_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_server_discovery_${HOSTNAME}_${TIMESTAMP}.json"

# Configuration for ping tests (PRODDB-specific)
SOURCE_HOST="proddb01.corp.example.com"
TARGET_HOST="proddb-oda.eastus.azure.example.com"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

log_section() {
    local title="$1"
    echo -e "\n${BLUE}=================================================================================${NC}"
    echo -e "${BLUE}  $title${NC}"
    echo -e "${BLUE}=================================================================================${NC}\n"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# =============================================================================
# DISCOVERY SECTIONS
# =============================================================================

discover_os_info() {
    log_section "OS INFORMATION"
    {
        echo "=== OS INFORMATION ==="
        echo "Hostname: $(hostname)"
        echo "Current User: $(whoami)"
        echo ""
        echo "Operating System:"
        cat /etc/os-release 2>/dev/null || cat /etc/redhat-release 2>/dev/null || uname -a
        echo ""
        echo "Kernel Version: $(uname -r)"
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "OS information collected"
}

discover_zdm_installation() {
    log_section "ZDM INSTALLATION"
    {
        echo "=== ZDM INSTALLATION ==="
        echo "ZDM_HOME: ${ZDM_HOME:-NOT SET}"
        echo ""
        if [ -n "${ZDM_HOME:-}" ] && [ -d "${ZDM_HOME}" ]; then
            echo "ZDM Version:"
            $ZDM_HOME/bin/zdmcli -version 2>/dev/null || echo "Unable to determine ZDM version"
            echo ""
            echo "ZDM Service Status:"
            $ZDM_HOME/bin/zdmservice status 2>/dev/null || echo "ZDM service status unavailable"
            echo ""
            echo "Active Migration Jobs:"
            $ZDM_HOME/bin/zdmcli query job -all 2>/dev/null || echo "No active jobs or unable to query"
            echo ""
            echo "ZDM Home Contents:"
            ls -la $ZDM_HOME 2>/dev/null || echo "Unable to list ZDM_HOME"
            echo ""
        else
            echo "WARNING: ZDM_HOME not set or directory does not exist"
            echo "Searching for ZDM installation..."
            find /home -name "zdmcli" -type f 2>/dev/null | head -5 || echo "zdmcli not found"
        fi
    } >> "$OUTPUT_FILE" 2>&1
    log_success "ZDM installation information collected"
}

discover_java() {
    log_section "JAVA CONFIGURATION"
    {
        echo "=== JAVA CONFIGURATION ==="
        echo "JAVA_HOME: ${JAVA_HOME:-NOT SET}"
        echo ""
        echo "Java Version:"
        java -version 2>&1 || echo "Java not found in PATH"
        echo ""
        if [ -n "${JAVA_HOME:-}" ]; then
            echo "Java from JAVA_HOME:"
            $JAVA_HOME/bin/java -version 2>&1 || echo "Unable to run java from JAVA_HOME"
        fi
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "Java configuration collected"
}

discover_oci_cli() {
    log_section "OCI CLI CONFIGURATION"
    {
        echo "=== OCI CLI CONFIGURATION ==="
        echo ""
        echo "OCI CLI Version:"
        oci --version 2>/dev/null || echo "OCI CLI not installed"
        echo ""
        echo "OCI Config File Location:"
        if [ -f ~/.oci/config ]; then
            echo "Found: ~/.oci/config"
            echo ""
            echo "Configured Profiles and Regions (sensitive data masked):"
            grep -E '^\[|^region=' ~/.oci/config 2>/dev/null | sed 's/key_file=.*/key_file=[MASKED]/' || echo "Unable to parse config"
            echo ""
            echo "API Key Files:"
            ls -la ~/.oci/*.pem 2>/dev/null || echo "No .pem files found in ~/.oci"
        else
            echo "OCI config file not found at ~/.oci/config"
        fi
        echo ""
        echo "OCI Connectivity Test:"
        oci iam region list --output table 2>/dev/null | head -10 || echo "OCI connectivity test failed or OCI CLI not configured"
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "OCI CLI configuration collected"
}

discover_ssh() {
    log_section "SSH CONFIGURATION"
    {
        echo "=== SSH CONFIGURATION ==="
        echo ""
        echo "SSH Directory Contents:"
        ls -la ~/.ssh/ 2>/dev/null || echo "No .ssh directory found"
        echo ""
        echo "Available SSH Keys (public):"
        ls -la ~/.ssh/*.pub 2>/dev/null || echo "No public keys found"
        echo ""
        echo "Available SSH Keys (private):"
        ls -la ~/.ssh/id_* ~/.ssh/*_key 2>/dev/null | grep -v '.pub' || echo "No private keys found"
        echo ""
        echo "SSH Config:"
        cat ~/.ssh/config 2>/dev/null || echo "No SSH config file found"
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "SSH configuration collected"
}

discover_credentials() {
    log_section "CREDENTIAL FILES"
    {
        echo "=== CREDENTIAL FILES ==="
        echo ""
        echo "Searching for password/credential files..."
        find ~ -maxdepth 3 -name "*password*" -o -name "*credential*" -o -name "*.wallet" 2>/dev/null | head -20 || echo "No credential files found"
        echo ""
        echo "ZDM Credentials Directory:"
        if [ -n "${ZDM_HOME:-}" ]; then
            ls -la ${ZDM_HOME}/crsdata/*/security 2>/dev/null || echo "No ZDM security directory found"
        fi
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "Credential files information collected"
}

discover_network() {
    log_section "NETWORK CONFIGURATION"
    {
        echo "=== NETWORK CONFIGURATION ==="
        echo ""
        echo "IP Addresses:"
        ip addr show 2>/dev/null | grep 'inet ' | awk '{print "  " $2}' || hostname -I 2>/dev/null | tr ' ' '\n' | sed 's/^/  /'
        echo ""
        echo "Routing Table:"
        ip route 2>/dev/null || route -n 2>/dev/null || echo "Unable to get routing table"
        echo ""
        echo "DNS Configuration:"
        cat /etc/resolv.conf 2>/dev/null || echo "Unable to read resolv.conf"
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "Network configuration collected"
}

discover_zdm_logs() {
    log_section "ZDM LOGS"
    {
        echo "=== ZDM LOGS ==="
        echo ""
        if [ -n "${ZDM_HOME:-}" ]; then
            echo "Log Directory Location:"
            local log_dir="${ZDM_HOME}/crsdata/$(hostname)/rhp"
            if [ -d "$log_dir" ]; then
                echo "$log_dir"
                echo ""
                echo "Recent Log Files:"
                ls -lt "$log_dir"/*.log 2>/dev/null | head -10 || echo "No log files found"
            else
                echo "ZDM log directory not found at expected location"
                echo "Searching for log files..."
                find ${ZDM_HOME} -name "*.log" -type f 2>/dev/null | head -10 || echo "No log files found"
            fi
        else
            echo "ZDM_HOME not set - unable to locate logs"
        fi
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "ZDM logs information collected"
}

# =============================================================================
# ADDITIONAL DISCOVERY REQUIREMENTS FOR PRODDB ZDM SERVER
# =============================================================================

discover_disk_space() {
    log_section "DISK SPACE FOR ZDM OPERATIONS"
    {
        echo "=== DISK SPACE FOR ZDM OPERATIONS ==="
        echo ""
        echo "Minimum Recommended: 50GB free space"
        echo ""
        echo "Disk Space Summary:"
        df -h 2>/dev/null
        echo ""
        echo "ZDM Home Partition:"
        if [ -n "${ZDM_HOME:-}" ]; then
            df -h "$ZDM_HOME" 2>/dev/null || echo "Unable to determine ZDM_HOME partition"
        fi
        echo ""
        echo "/tmp Space (used for temporary files):"
        df -h /tmp 2>/dev/null
        echo ""
        echo "Home Directory Space:"
        df -h ~ 2>/dev/null
        echo ""
        
        # Check if enough space is available
        local zdm_free_gb=0
        if [ -n "${ZDM_HOME:-}" ]; then
            zdm_free_gb=$(df -BG "$ZDM_HOME" 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')
        else
            zdm_free_gb=$(df -BG ~ 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')
        fi
        
        echo ""
        if [ "$zdm_free_gb" -ge 50 ] 2>/dev/null; then
            echo "✓ PASS: ${zdm_free_gb}GB available (≥ 50GB recommended)"
        else
            echo "✗ WARNING: ${zdm_free_gb}GB available (< 50GB recommended)"
        fi
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "Disk space information collected"
}

discover_network_latency() {
    log_section "NETWORK LATENCY TESTS"
    {
        echo "=== NETWORK LATENCY TESTS ==="
        echo ""
        echo "Source Database: $SOURCE_HOST"
        echo "Target Database: $TARGET_HOST"
        echo ""
        
        echo "Ping Test to Source ($SOURCE_HOST):"
        if ping -c 5 "$SOURCE_HOST" 2>/dev/null; then
            echo ""
            echo "Source connectivity: ✓ PASS"
        else
            echo "Source connectivity: ✗ FAIL (ping failed or host unreachable)"
        fi
        echo ""
        
        echo "Ping Test to Target ($TARGET_HOST):"
        if ping -c 5 "$TARGET_HOST" 2>/dev/null; then
            echo ""
            echo "Target connectivity: ✓ PASS"
        else
            echo "Target connectivity: ✗ FAIL (ping failed or host unreachable)"
        fi
        echo ""
        
        echo "DNS Resolution Test:"
        echo "  Source: $(host "$SOURCE_HOST" 2>/dev/null | head -1 || nslookup "$SOURCE_HOST" 2>/dev/null | grep 'Address:' | tail -1 || echo "DNS resolution failed")"
        echo "  Target: $(host "$TARGET_HOST" 2>/dev/null | head -1 || nslookup "$TARGET_HOST" 2>/dev/null | grep 'Address:' | tail -1 || echo "DNS resolution failed")"
        echo ""
        
        echo "Port Connectivity Test (SSH port 22):"
        echo -n "  Source ($SOURCE_HOST:22): "
        timeout 5 bash -c "</dev/tcp/$SOURCE_HOST/22" 2>/dev/null && echo "✓ OPEN" || echo "✗ CLOSED or unreachable"
        echo -n "  Target ($TARGET_HOST:22): "
        timeout 5 bash -c "</dev/tcp/$TARGET_HOST/22" 2>/dev/null && echo "✓ OPEN" || echo "✗ CLOSED or unreachable"
        echo ""
        
        echo "Port Connectivity Test (Oracle port 1521):"
        echo -n "  Source ($SOURCE_HOST:1521): "
        timeout 5 bash -c "</dev/tcp/$SOURCE_HOST/1521" 2>/dev/null && echo "✓ OPEN" || echo "✗ CLOSED or unreachable"
        echo -n "  Target ($TARGET_HOST:1521): "
        timeout 5 bash -c "</dev/tcp/$TARGET_HOST/1521" 2>/dev/null && echo "✓ OPEN" || echo "✗ CLOSED or unreachable"
        echo ""
    } >> "$OUTPUT_FILE" 2>&1
    log_success "Network latency tests completed"
}

# =============================================================================
# JSON OUTPUT GENERATION
# =============================================================================

generate_json_summary() {
    log_section "GENERATING JSON SUMMARY"
    
    # Collect key values for JSON
    local zdm_version="unknown"
    if [ -n "${ZDM_HOME:-}" ]; then
        zdm_version=$($ZDM_HOME/bin/zdmcli -version 2>/dev/null | head -1 || echo "unknown")
    fi
    
    local java_version=$(java -version 2>&1 | head -1 | awk -F'"' '{print $2}' || echo "unknown")
    local oci_version=$(oci --version 2>/dev/null || echo "not installed")
    
    # Check disk space
    local zdm_free_gb=0
    if [ -n "${ZDM_HOME:-}" ]; then
        zdm_free_gb=$(df -BG "$ZDM_HOME" 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')
    else
        zdm_free_gb=$(df -BG ~ 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')
    fi
    
    # Check connectivity
    local source_reachable="false"
    local target_reachable="false"
    ping -c 1 "$SOURCE_HOST" >/dev/null 2>&1 && source_reachable="true"
    ping -c 1 "$TARGET_HOST" >/dev/null 2>&1 && target_reachable="true"
    
    cat > "$JSON_FILE" <<EOF
{
  "discovery_type": "zdm_server",
  "discovery_timestamp": "$(date -Iseconds)",
  "hostname": "$HOSTNAME",
  "project": "PRODDB Migration to Oracle Database@Azure",
  "current_user": "$(whoami)",
  "zdm_installation": {
    "zdm_home": "${ZDM_HOME:-unknown}",
    "zdm_version": "${zdm_version}"
  },
  "java_configuration": {
    "java_home": "${JAVA_HOME:-unknown}",
    "java_version": "${java_version}"
  },
  "oci_cli": {
    "version": "${oci_version}",
    "config_exists": $([ -f ~/.oci/config ] && echo "true" || echo "false")
  },
  "disk_space": {
    "free_gb": ${zdm_free_gb:-0},
    "minimum_recommended_gb": 50,
    "meets_requirement": $([ "${zdm_free_gb:-0}" -ge 50 ] 2>/dev/null && echo "true" || echo "false")
  },
  "connectivity": {
    "source_host": "$SOURCE_HOST",
    "source_reachable": $source_reachable,
    "target_host": "$TARGET_HOST",
    "target_reachable": $target_reachable
  },
  "section_errors": $SECTION_ERRORS,
  "output_files": {
    "text_report": "$OUTPUT_FILE",
    "json_summary": "$JSON_FILE"
  }
}
EOF
    log_success "JSON summary generated: $JSON_FILE"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    echo -e "${GREEN}=============================================================================${NC}"
    echo -e "${GREEN}  ZDM Server Discovery Script${NC}"
    echo -e "${GREEN}  Project: PRODDB Migration to Oracle Database@Azure${NC}"
    echo -e "${GREEN}  Host: $HOSTNAME${NC}"
    echo -e "${GREEN}  Timestamp: $(date)${NC}"
    echo -e "${GREEN}=============================================================================${NC}"
    
    # Initialize output file
    echo "ZDM Server Discovery Report" > "$OUTPUT_FILE"
    echo "============================" >> "$OUTPUT_FILE"
    echo "Project: PRODDB Migration to Oracle Database@Azure" >> "$OUTPUT_FILE"
    echo "Host: $HOSTNAME" >> "$OUTPUT_FILE"
    echo "Generated: $(date)" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    # Run all discovery sections (continue on failure)
    discover_os_info || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_zdm_installation || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_java || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_oci_cli || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_ssh || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_credentials || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_network || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_zdm_logs || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    
    # Additional PRODDB ZDM server-specific discovery
    discover_disk_space || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    discover_network_latency || SECTION_ERRORS=$((SECTION_ERRORS + 1))
    
    # Generate JSON summary
    generate_json_summary
    
    echo ""
    echo -e "${GREEN}=============================================================================${NC}"
    echo -e "${GREEN}  Discovery Complete${NC}"
    echo -e "${GREEN}=============================================================================${NC}"
    echo -e "Text Report: ${BLUE}$OUTPUT_FILE${NC}"
    echo -e "JSON Summary: ${BLUE}$JSON_FILE${NC}"
    if [ $SECTION_ERRORS -gt 0 ]; then
        echo -e "${YELLOW}Warning: $SECTION_ERRORS section(s) encountered errors${NC}"
    fi
}

# Show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "ZDM Server Discovery Script"
    echo "Project: PRODDB Migration to Oracle Database@Azure"
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help message"
    echo ""
    echo "Environment Variables (optional overrides):"
    echo "  ZDM_HOME_OVERRIDE     Override auto-detected ZDM_HOME"
    echo "  JAVA_HOME_OVERRIDE    Override auto-detected JAVA_HOME"
    echo ""
    echo "Output:"
    echo "  ./zdm_server_discovery_<hostname>_<timestamp>.txt"
    echo "  ./zdm_server_discovery_<hostname>_<timestamp>.json"
}

# Parse command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    *)
        main
        ;;
esac
