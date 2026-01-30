#!/bin/bash
################################################################################
# ZDM Server Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# 
# Purpose: Discover ZDM jumpbox server configuration for ZDM migration
# 
# Usage: Run on ZDM jumpbox server as admin user (azureuser)
#        This script will execute ZDM CLI commands as zdmuser
#
# Environment Variables (passed by orchestration script):
#   - SOURCE_HOST: Source database hostname (for connectivity testing)
#   - TARGET_HOST: Target database hostname (for connectivity testing)
#   - ZDM_USER: ZDM software owner user (default: zdmuser)
#
# Output: 
#   - Text report: ./zdm_server_discovery_<hostname>_<timestamp>.txt
#   - JSON summary: ./zdm_server_discovery_<hostname>_<timestamp>.json
################################################################################

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Timestamp for output files
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME_SHORT=$(hostname -s 2>/dev/null || hostname)

# Output files (in current working directory)
TEXT_OUTPUT="./zdm_server_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
JSON_OUTPUT="./zdm_server_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

# User configuration
ZDM_USER="${ZDM_USER:-zdmuser}"

# Environment variables for connectivity testing (passed from orchestration script)
SOURCE_HOST="${SOURCE_HOST:-}"
TARGET_HOST="${TARGET_HOST:-}"

################################################################################
# Helper Functions
################################################################################

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
    echo "[INFO] $1" >> "$TEXT_OUTPUT"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    echo "[WARN] $1" >> "$TEXT_OUTPUT"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[ERROR] $1" >> "$TEXT_OUTPUT"
}

log_section() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo "" >> "$TEXT_OUTPUT"
    echo "========================================" >> "$TEXT_OUTPUT"
    echo "$1" >> "$TEXT_OUTPUT"
    echo "========================================" >> "$TEXT_OUTPUT"
}

# Auto-detect ZDM environment
detect_zdm_env() {
    # If already set, use existing values
    if [ -n "${ZDM_HOME:-}" ]; then
        return 0
    fi
    
    # Method 1: Get ZDM_HOME from zdmuser's environment
    if id "$ZDM_USER" &>/dev/null; then
        local zdm_home_from_user
        zdm_home_from_user=$(sudo -u "$ZDM_USER" -i bash -c 'echo $ZDM_HOME' 2>/dev/null)
        if [ -n "$zdm_home_from_user" ] && [ -d "$zdm_home_from_user" ] && [ -f "$zdm_home_from_user/bin/zdmcli" ]; then
            export ZDM_HOME="$zdm_home_from_user"
            return 0
        fi
    fi
    
    # Method 2: Check zdmuser's home directory for common ZDM paths
    local zdm_user_home
    zdm_user_home=$(eval echo ~$ZDM_USER 2>/dev/null)
    if [ -n "$zdm_user_home" ]; then
        for subdir in zdmhome zdm app/zdmhome; do
            local candidate="$zdm_user_home/$subdir"
            if sudo test -d "$candidate" 2>/dev/null && sudo test -f "$candidate/bin/zdmcli" 2>/dev/null; then
                export ZDM_HOME="$candidate"
                return 0
            fi
        done
    fi
    
    # Method 3: Check common ZDM installation locations system-wide
    for path in /u01/app/zdmhome /u01/zdm /u01/app/zdm /opt/zdm /home/zdmuser/zdmhome; do
        if sudo test -d "$path" 2>/dev/null && sudo test -f "$path/bin/zdmcli" 2>/dev/null; then
            export ZDM_HOME="$path"
            return 0
        fi
    done
    
    # Method 4: Search for zdmcli binary and derive ZDM_HOME
    local zdmcli_path
    zdmcli_path=$(sudo find /u01 /opt /home -name "zdmcli" -type f 2>/dev/null | head -1)
    if [ -n "$zdmcli_path" ]; then
        # zdmcli is in $ZDM_HOME/bin/zdmcli, so go up two levels
        export ZDM_HOME="$(dirname "$(dirname "$zdmcli_path")")"
        return 0
    fi
}

# Detect Java environment
detect_java_env() {
    # If already set, use existing values
    if [ -n "${JAVA_HOME:-}" ]; then
        return 0
    fi
    
    # Method 1: Check ZDM's bundled JDK (ZDM often includes its own JDK)
    if [ -n "${ZDM_HOME:-}" ] && [ -d "${ZDM_HOME}/jdk" ]; then
        export JAVA_HOME="${ZDM_HOME}/jdk"
        return 0
    fi
    
    # Method 2: Check alternatives
    if command -v java >/dev/null 2>&1; then
        local java_path
        java_path=$(readlink -f "$(command -v java)" 2>/dev/null)
        if [ -n "$java_path" ]; then
            export JAVA_HOME="${java_path%/bin/java}"
            return 0
        fi
    fi
    
    # Method 3: Search common Java paths
    for path in /usr/java/latest /usr/java/jdk* /usr/lib/jvm/java-* /opt/java/jdk*; do
        if [ -d "$path" ] && [ -f "$path/bin/java" ]; then
            export JAVA_HOME="$path"
            return 0
        fi
    done
}

# Apply explicit overrides if provided
apply_overrides() {
    [ -n "${ZDM_HOME_OVERRIDE:-}" ] && export ZDM_HOME="$ZDM_HOME_OVERRIDE"
    [ -n "${JAVA_HOME_OVERRIDE:-}" ] && export JAVA_HOME="$JAVA_HOME_OVERRIDE"
}

# Run ZDM command as zdmuser
run_zdm_cmd() {
    local zdm_cmd="$1"
    if [ -n "${ZDM_HOME:-}" ]; then
        if [ "$(whoami)" = "$ZDM_USER" ]; then
            ZDM_HOME="$ZDM_HOME" "$ZDM_HOME/bin/$zdm_cmd"
        else
            sudo -u "$ZDM_USER" ZDM_HOME="$ZDM_HOME" "$ZDM_HOME/bin/$zdm_cmd"
        fi
    else
        echo "ERROR: ZDM_HOME not set"
        return 1
    fi
}

################################################################################
# Initialize
################################################################################

# Initialize output file
echo "ZDM Server Discovery Report" > "$TEXT_OUTPUT"
echo "Generated: $(date)" >> "$TEXT_OUTPUT"
echo "Hostname: $(hostname)" >> "$TEXT_OUTPUT"
echo "Current User: $(whoami)" >> "$TEXT_OUTPUT"
echo "" >> "$TEXT_OUTPUT"

# Detect environments
detect_zdm_env
detect_java_env
apply_overrides

# Initialize JSON output
cat > "$JSON_OUTPUT" << 'EOJSON'
{
  "discovery_type": "zdm_server",
  "generated_timestamp": "TIMESTAMP_PLACEHOLDER",
  "hostname": "HOSTNAME_PLACEHOLDER",
  "current_user": "USER_PLACEHOLDER",
EOJSON
sed -i "s/TIMESTAMP_PLACEHOLDER/$(date -Iseconds)/g" "$JSON_OUTPUT" 2>/dev/null || \
    sed -i '' "s/TIMESTAMP_PLACEHOLDER/$(date -Iseconds)/g" "$JSON_OUTPUT" 2>/dev/null
sed -i "s/HOSTNAME_PLACEHOLDER/$(hostname)/g" "$JSON_OUTPUT" 2>/dev/null || \
    sed -i '' "s/HOSTNAME_PLACEHOLDER/$(hostname)/g" "$JSON_OUTPUT" 2>/dev/null
sed -i "s/USER_PLACEHOLDER/$(whoami)/g" "$JSON_OUTPUT" 2>/dev/null || \
    sed -i '' "s/USER_PLACEHOLDER/$(whoami)/g" "$JSON_OUTPUT" 2>/dev/null

################################################################################
# OS Information
################################################################################

log_section "OS INFORMATION"

log_info "Hostname: $(hostname)"
echo "Hostname: $(hostname)" >> "$TEXT_OUTPUT"

log_info "Current User: $(whoami)"
echo "Current User: $(whoami)" >> "$TEXT_OUTPUT"

log_info "Operating System:"
if [ -f /etc/os-release ]; then
    cat /etc/os-release | tee -a "$TEXT_OUTPUT"
elif [ -f /etc/redhat-release ]; then
    cat /etc/redhat-release | tee -a "$TEXT_OUTPUT"
else
    uname -a | tee -a "$TEXT_OUTPUT"
fi

################################################################################
# ADDITIONAL DISCOVERY: Available Disk Space for ZDM Operations
################################################################################

log_section "DISK SPACE FOR ZDM OPERATIONS"

log_info "Disk Space Summary:"
df -h | tee -a "$TEXT_OUTPUT"

log_info "Checking ZDM-relevant disk space (minimum 50GB recommended):"
# Check common ZDM working directories
for dir in /u01 /home/$ZDM_USER /opt /tmp; do
    if [ -d "$dir" ]; then
        AVAIL_GB=$(df -BG "$dir" 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//')
        if [ -n "$AVAIL_GB" ]; then
            if [ "$AVAIL_GB" -ge 50 ]; then
                log_info "$dir: ${AVAIL_GB}GB available - SUFFICIENT"
            else
                log_warn "$dir: ${AVAIL_GB}GB available - BELOW 50GB RECOMMENDED"
            fi
        fi
    fi
done

# Check ZDM_HOME specifically if set
if [ -n "${ZDM_HOME:-}" ]; then
    ZDM_HOME_AVAIL=$(df -BG "$ZDM_HOME" 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//')
    if [ -n "$ZDM_HOME_AVAIL" ]; then
        log_info "ZDM_HOME ($ZDM_HOME): ${ZDM_HOME_AVAIL}GB available"
        echo "ZDM_HOME available space: ${ZDM_HOME_AVAIL}GB" >> "$TEXT_OUTPUT"
    fi
fi

################################################################################
# ZDM Installation
################################################################################

log_section "ZDM INSTALLATION"

log_info "ZDM_HOME: ${ZDM_HOME:-NOT DETECTED}"
echo "ZDM_HOME: ${ZDM_HOME:-NOT DETECTED}" >> "$TEXT_OUTPUT"

if [ -n "${ZDM_HOME:-}" ]; then
    log_info "Checking ZDM installation..."
    
    # Check if zdmcli exists and is executable
    if sudo test -f "$ZDM_HOME/bin/zdmcli" 2>/dev/null; then
        log_info "zdmcli found at $ZDM_HOME/bin/zdmcli"
        echo "zdmcli: FOUND" >> "$TEXT_OUTPUT"
        
        # Get file permissions
        sudo ls -la "$ZDM_HOME/bin/zdmcli" 2>/dev/null | tee -a "$TEXT_OUTPUT"
    else
        log_warn "zdmcli not found at $ZDM_HOME/bin/zdmcli"
        echo "zdmcli: NOT FOUND" >> "$TEXT_OUTPUT"
    fi
    
    # Check for ZDM response file templates
    log_info "ZDM Response File Templates:"
    if sudo test -d "$ZDM_HOME/rhp/zdm/template" 2>/dev/null; then
        sudo ls -la "$ZDM_HOME/rhp/zdm/template/"*.rsp 2>/dev/null | tee -a "$TEXT_OUTPUT" || log_info "No .rsp files found"
    else
        log_warn "Template directory not found at $ZDM_HOME/rhp/zdm/template"
    fi
    
    # Check ZDM service status
    log_info "ZDM Service Status:"
    if [ "$(whoami)" = "$ZDM_USER" ]; then
        "$ZDM_HOME/bin/zdmservice" status 2>&1 | tee -a "$TEXT_OUTPUT" || log_warn "Could not get ZDM service status"
    else
        sudo -u "$ZDM_USER" "$ZDM_HOME/bin/zdmservice" status 2>&1 | tee -a "$TEXT_OUTPUT" || log_warn "Could not get ZDM service status"
    fi
    
    # List active migration jobs
    log_info "Active Migration Jobs:"
    if [ "$(whoami)" = "$ZDM_USER" ]; then
        "$ZDM_HOME/bin/zdmcli" query job -jobtype physical 2>&1 | head -50 | tee -a "$TEXT_OUTPUT" || log_info "No migration jobs found or ZDM not running"
    else
        sudo -u "$ZDM_USER" "$ZDM_HOME/bin/zdmcli" query job -jobtype physical 2>&1 | head -50 | tee -a "$TEXT_OUTPUT" || log_info "No migration jobs found or ZDM not running"
    fi
else
    log_warn "ZDM_HOME not detected - ZDM installation not found"
    log_info "Searching for ZDM installation..."
    
    # Try to find zdmcli
    ZDMCLI_SEARCH=$(sudo find /u01 /opt /home -name "zdmcli" -type f 2>/dev/null | head -5)
    if [ -n "$ZDMCLI_SEARCH" ]; then
        log_info "Found zdmcli at: $ZDMCLI_SEARCH"
        echo "zdmcli found at: $ZDMCLI_SEARCH" >> "$TEXT_OUTPUT"
    else
        log_warn "zdmcli not found on this system"
    fi
fi

################################################################################
# Java Configuration
################################################################################

log_section "JAVA CONFIGURATION"

log_info "JAVA_HOME: ${JAVA_HOME:-NOT SET}"
echo "JAVA_HOME: ${JAVA_HOME:-NOT SET}" >> "$TEXT_OUTPUT"

# Check ZDM's bundled JDK first
if [ -n "${ZDM_HOME:-}" ] && [ -d "${ZDM_HOME}/jdk" ]; then
    log_info "ZDM Bundled JDK found at: ${ZDM_HOME}/jdk"
    echo "ZDM Bundled JDK: ${ZDM_HOME}/jdk" >> "$TEXT_OUTPUT"
    "${ZDM_HOME}/jdk/bin/java" -version 2>&1 | tee -a "$TEXT_OUTPUT"
elif [ -n "${JAVA_HOME:-}" ] && [ -f "${JAVA_HOME}/bin/java" ]; then
    log_info "Java Version:"
    "${JAVA_HOME}/bin/java" -version 2>&1 | tee -a "$TEXT_OUTPUT"
elif command -v java >/dev/null 2>&1; then
    log_info "System Java Version:"
    java -version 2>&1 | tee -a "$TEXT_OUTPUT"
else
    log_warn "Java not found"
fi

################################################################################
# OCI CLI Configuration
################################################################################

log_section "OCI CLI CONFIGURATION"

log_info "OCI CLI Version:"
oci --version 2>&1 | tee -a "$TEXT_OUTPUT" || log_warn "OCI CLI not installed"

log_info "OCI Config File Location:"
if [ -f ~/.oci/config ]; then
    log_info "OCI config found at ~/.oci/config"
    echo "OCI Config: ~/.oci/config" >> "$TEXT_OUTPUT"
    
    # Show profiles and regions (masking sensitive data)
    log_info "Configured Profiles and Regions:"
    grep -E '^\[|^region=' ~/.oci/config 2>/dev/null | tee -a "$TEXT_OUTPUT"
    
    # Check API key file existence
    log_info "API Key Files:"
    for keyfile in ~/.oci/*.pem; do
        if [ -f "$keyfile" ]; then
            log_info "Found: $keyfile"
            echo "API Key: $keyfile" >> "$TEXT_OUTPUT"
        fi
    done
else
    log_warn "OCI config file not found at ~/.oci/config"
    
    # Check zdmuser's OCI config
    ZDM_USER_HOME=$(eval echo ~$ZDM_USER 2>/dev/null)
    if [ -n "$ZDM_USER_HOME" ] && sudo test -f "$ZDM_USER_HOME/.oci/config" 2>/dev/null; then
        log_info "OCI config found for $ZDM_USER at $ZDM_USER_HOME/.oci/config"
        sudo grep -E '^\[|^region=' "$ZDM_USER_HOME/.oci/config" 2>/dev/null | tee -a "$TEXT_OUTPUT"
    fi
fi

log_info "OCI Connectivity Test:"
oci iam region list --query 'data[0].name' --raw-output 2>&1 | tee -a "$TEXT_OUTPUT" || log_warn "OCI connectivity test failed"

################################################################################
# SSH Configuration
################################################################################

log_section "SSH CONFIGURATION"

log_info "SSH Keys (current user):"
if [ -d ~/.ssh ]; then
    ls -la ~/.ssh 2>/dev/null | tee -a "$TEXT_OUTPUT"
else
    log_warn "SSH directory not found for current user"
fi

log_info "SSH Keys ($ZDM_USER):"
ZDM_USER_HOME=$(eval echo ~$ZDM_USER 2>/dev/null)
if [ -n "$ZDM_USER_HOME" ] && sudo test -d "$ZDM_USER_HOME/.ssh" 2>/dev/null; then
    sudo ls -la "$ZDM_USER_HOME/.ssh" 2>/dev/null | tee -a "$TEXT_OUTPUT"
else
    log_warn "SSH directory not found for $ZDM_USER"
fi

################################################################################
# Credential Files
################################################################################

log_section "CREDENTIAL FILES"

log_info "Searching for password/credential files..."

# Search common locations for credential files (read-only check, no content display)
CRED_FILES=$(sudo find /home/$ZDM_USER /root /tmp -name '*password*' -o -name '*credential*' -o -name '*.wallet' 2>/dev/null | head -20)
if [ -n "$CRED_FILES" ]; then
    log_info "Found credential-related files:"
    echo "$CRED_FILES" | tee -a "$TEXT_OUTPUT"
else
    log_info "No credential files found in common locations"
fi

################################################################################
# Network Configuration
################################################################################

log_section "NETWORK CONFIGURATION"

log_info "IP Addresses:"
ip addr show 2>/dev/null | grep 'inet ' | awk '{print $2}' | tee -a "$TEXT_OUTPUT" || \
    ifconfig 2>/dev/null | grep 'inet ' | awk '{print $2}' | tee -a "$TEXT_OUTPUT"

log_info "Routing Table:"
ip route 2>/dev/null | tee -a "$TEXT_OUTPUT" || route -n 2>/dev/null | tee -a "$TEXT_OUTPUT"

log_info "DNS Configuration:"
if [ -f /etc/resolv.conf ]; then
    cat /etc/resolv.conf | tee -a "$TEXT_OUTPUT"
else
    log_warn "resolv.conf not found"
fi

################################################################################
# ADDITIONAL DISCOVERY: Network Connectivity Tests
################################################################################

log_section "NETWORK CONNECTIVITY TESTS"

# Test connectivity to source database
if [ -n "${SOURCE_HOST:-}" ]; then
    log_info "Testing connectivity to SOURCE: $SOURCE_HOST"
    echo "Source Host: $SOURCE_HOST" >> "$TEXT_OUTPUT"
    
    # Ping test with latency measurement
    log_info "Ping test to $SOURCE_HOST:"
    PING_OUTPUT=$(ping -c 5 "$SOURCE_HOST" 2>&1)
    echo "$PING_OUTPUT" | tee -a "$TEXT_OUTPUT"
    
    if echo "$PING_OUTPUT" | grep -q "0% packet loss\|0.0% packet loss"; then
        SOURCE_PING="SUCCESS"
        # Extract average latency
        SOURCE_LATENCY=$(echo "$PING_OUTPUT" | grep 'avg' | awk -F'/' '{print $5}')
        log_info "Source ping: SUCCESS (avg latency: ${SOURCE_LATENCY}ms)"
    else
        SOURCE_PING="FAILED"
        log_warn "Source ping: FAILED"
    fi
    
    # Port connectivity tests
    log_info "Port connectivity tests to $SOURCE_HOST:"
    for port in 22 1521; do
        if timeout 5 bash -c "echo >/dev/tcp/$SOURCE_HOST/$port" 2>/dev/null; then
            log_info "Port $port: OPEN"
            echo "Source port $port: OPEN" >> "$TEXT_OUTPUT"
        else
            log_warn "Port $port: BLOCKED or unreachable"
            echo "Source port $port: BLOCKED" >> "$TEXT_OUTPUT"
        fi
    done
else
    log_info "SOURCE_HOST not provided - skipping source connectivity tests"
    SOURCE_PING="SKIPPED"
fi

# Test connectivity to target database
if [ -n "${TARGET_HOST:-}" ]; then
    log_info "Testing connectivity to TARGET: $TARGET_HOST"
    echo "Target Host: $TARGET_HOST" >> "$TEXT_OUTPUT"
    
    # Ping test with latency measurement
    log_info "Ping test to $TARGET_HOST:"
    PING_OUTPUT=$(ping -c 5 "$TARGET_HOST" 2>&1)
    echo "$PING_OUTPUT" | tee -a "$TEXT_OUTPUT"
    
    if echo "$PING_OUTPUT" | grep -q "0% packet loss\|0.0% packet loss"; then
        TARGET_PING="SUCCESS"
        # Extract average latency
        TARGET_LATENCY=$(echo "$PING_OUTPUT" | grep 'avg' | awk -F'/' '{print $5}')
        log_info "Target ping: SUCCESS (avg latency: ${TARGET_LATENCY}ms)"
    else
        TARGET_PING="FAILED"
        log_warn "Target ping: FAILED"
    fi
    
    # Port connectivity tests
    log_info "Port connectivity tests to $TARGET_HOST:"
    for port in 22 1521; do
        if timeout 5 bash -c "echo >/dev/tcp/$TARGET_HOST/$port" 2>/dev/null; then
            log_info "Port $port: OPEN"
            echo "Target port $port: OPEN" >> "$TEXT_OUTPUT"
        else
            log_warn "Port $port: BLOCKED or unreachable"
            echo "Target port $port: BLOCKED" >> "$TEXT_OUTPUT"
        fi
    done
else
    log_info "TARGET_HOST not provided - skipping target connectivity tests"
    TARGET_PING="SKIPPED"
fi

################################################################################
# ZDM Logs
################################################################################

log_section "ZDM LOGS"

if [ -n "${ZDM_HOME:-}" ]; then
    ZDM_LOG_DIR="$ZDM_HOME/rhp/log"
    
    if sudo test -d "$ZDM_LOG_DIR" 2>/dev/null; then
        log_info "ZDM Log Directory: $ZDM_LOG_DIR"
        echo "ZDM Log Directory: $ZDM_LOG_DIR" >> "$TEXT_OUTPUT"
        
        log_info "Recent Log Files (last 10):"
        sudo ls -lt "$ZDM_LOG_DIR" 2>/dev/null | head -10 | tee -a "$TEXT_OUTPUT"
    else
        log_warn "ZDM log directory not found at $ZDM_LOG_DIR"
    fi
else
    log_warn "Cannot check ZDM logs - ZDM_HOME not set"
fi

################################################################################
# Finalize JSON Output
################################################################################

log_section "FINALIZING DISCOVERY"

# Calculate disk space
DISK_AVAILABLE=$(df -BG /u01 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//' || echo "UNKNOWN")

# Complete JSON output
cat >> "$JSON_OUTPUT" << EOJSON
  "zdm_configuration": {
    "zdm_home": "${ZDM_HOME:-NOT DETECTED}",
    "java_home": "${JAVA_HOME:-NOT SET}",
    "zdm_user": "${ZDM_USER}"
  },
  "disk_space": {
    "available_gb": "${DISK_AVAILABLE}"
  },
  "connectivity": {
    "source_host": "${SOURCE_HOST:-NOT PROVIDED}",
    "source_ping": "${SOURCE_PING:-SKIPPED}",
    "source_latency_ms": "${SOURCE_LATENCY:-N/A}",
    "target_host": "${TARGET_HOST:-NOT PROVIDED}",
    "target_ping": "${TARGET_PING:-SKIPPED}",
    "target_latency_ms": "${TARGET_LATENCY:-N/A}"
  },
  "discovery_status": "COMPLETED"
}
EOJSON

log_info "Discovery completed successfully"
log_info "Text report: $TEXT_OUTPUT"
log_info "JSON summary: $JSON_OUTPUT"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Discovery Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo "Text report: $TEXT_OUTPUT"
echo "JSON summary: $JSON_OUTPUT"
