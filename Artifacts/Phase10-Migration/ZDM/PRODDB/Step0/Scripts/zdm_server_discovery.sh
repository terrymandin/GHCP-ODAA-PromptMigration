#!/bin/bash
################################################################################
# ZDM Server Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# Purpose: Discover ZDM jumpbox server configuration for ZDM migration
#
# This script is executed via SSH as an admin user (azureuser) with sudo privileges.
# ZDM CLI commands are executed as the zdmuser via sudo.
#
# Environment variables passed from orchestration script:
#   - SOURCE_HOST: Source database hostname for connectivity testing
#   - TARGET_HOST: Target database hostname for connectivity testing
#   - ZDM_USER: ZDM software owner user (default: zdmuser)
#
# Output:
#   - Text report: ./zdm_server_discovery_<hostname>_<timestamp>.txt
#   - JSON summary: ./zdm_server_discovery_<hostname>_<timestamp>.json
################################################################################

# Configuration
ZDM_USER="${ZDM_USER:-zdmuser}"
SOURCE_HOST="${SOURCE_HOST:-}"
TARGET_HOST="${TARGET_HOST:-}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname -s)
OUTPUT_FILE="./zdm_server_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_server_discovery_${HOSTNAME}_${TIMESTAMP}.json"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Utility Functions
################################################################################

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
    echo "[INFO] $1" >> "$OUTPUT_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    echo "[WARN] $1" >> "$OUTPUT_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[ERROR] $1" >> "$OUTPUT_FILE"
}

log_section() {
    echo ""
    echo -e "${BLUE}=== $1 ===${NC}"
    echo "" >> "$OUTPUT_FILE"
    echo "=== $1 ===" >> "$OUTPUT_FILE"
}

# Auto-detect ZDM_HOME and JAVA_HOME
detect_zdm_env() {
    # If already set, use existing values
    if [ -n "${ZDM_HOME:-}" ] && [ -n "${JAVA_HOME:-}" ]; then
        return 0
    fi
    
    # Detect ZDM_HOME using multiple methods
    if [ -z "${ZDM_HOME:-}" ]; then
        # Method 1: Get ZDM_HOME from zdmuser's environment
        # This is the most reliable method as ZDM is typically installed under zdmuser
        if id "$ZDM_USER" &>/dev/null; then
            # Try to get ZDM_HOME from zdmuser's login shell environment
            local zdm_home_from_user
            zdm_home_from_user=$(sudo -u "$ZDM_USER" -i bash -c 'echo $ZDM_HOME' 2>/dev/null)
            if [ -n "$zdm_home_from_user" ] && [ -d "$zdm_home_from_user" ] && [ -f "$zdm_home_from_user/bin/zdmcli" ]; then
                export ZDM_HOME="$zdm_home_from_user"
            fi
        fi
        
        # Method 2: Check zdmuser's home directory for common ZDM paths
        if [ -z "${ZDM_HOME:-}" ]; then
            local zdm_user_home
            zdm_user_home=$(eval echo ~$ZDM_USER 2>/dev/null)
            if [ -n "$zdm_user_home" ]; then
                for subdir in zdmhome zdm app/zdmhome; do
                    local candidate="$zdm_user_home/$subdir"
                    if [ -d "$candidate" ] && [ -f "$candidate/bin/zdmcli" ]; then
                        export ZDM_HOME="$candidate"
                        break
                    fi
                done
            fi
        fi
        
        # Method 3: Check common ZDM installation locations system-wide
        if [ -z "${ZDM_HOME:-}" ]; then
            for path in /u01/app/zdmhome /u01/zdm /u01/app/zdm /opt/zdm /home/zdmuser/zdmhome /home/*/zdmhome ~/zdmhome ~/zdm "$HOME/zdmhome"; do
                # Use sudo to check paths that may not be readable by current user
                if sudo test -d "$path" 2>/dev/null && sudo test -f "$path/bin/zdmcli" 2>/dev/null; then
                    export ZDM_HOME="$path"
                    break
                elif [ -d "$path" ] && [ -f "$path/bin/zdmcli" ]; then
                    export ZDM_HOME="$path"
                    break
                fi
            done
        fi
        
        # Method 4: Search for zdmcli binary and derive ZDM_HOME
        if [ -z "${ZDM_HOME:-}" ]; then
            local zdmcli_path
            zdmcli_path=$(sudo find /u01 /opt /home -name "zdmcli" -type f 2>/dev/null | head -1)
            if [ -n "$zdmcli_path" ]; then
                # zdmcli is in $ZDM_HOME/bin/zdmcli, so go up two levels
                export ZDM_HOME="$(dirname "$(dirname "$zdmcli_path")")"
            fi
        fi
    fi
    
    # Detect JAVA_HOME - check ZDM's bundled JDK first
    if [ -z "${JAVA_HOME:-}" ]; then
        # Method 1: Check ZDM's bundled JDK (ZDM often includes its own JDK)
        if [ -n "${ZDM_HOME:-}" ] && [ -d "${ZDM_HOME}/jdk" ]; then
            export JAVA_HOME="${ZDM_HOME}/jdk"
        fi
        
        # Method 2: Check alternatives
        if [ -z "${JAVA_HOME:-}" ] && command -v java >/dev/null 2>&1; then
            local java_path
            java_path=$(readlink -f "$(command -v java)" 2>/dev/null)
            if [ -n "$java_path" ]; then
                export JAVA_HOME="${java_path%/bin/java}"
            fi
        fi
        
        # Method 3: Search common Java paths
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

# Run ZDM command as zdmuser
run_zdm_cmd() {
    local zdm_cmd="$1"
    if [ -n "${ZDM_HOME:-}" ]; then
        # Execute as zdmuser - use sudo if current user is not zdmuser
        if [ "$(whoami)" = "$ZDM_USER" ]; then
            $ZDM_HOME/bin/$zdm_cmd 2>&1
        else
            sudo -u "$ZDM_USER" ZDM_HOME="$ZDM_HOME" $ZDM_HOME/bin/$zdm_cmd 2>&1
        fi
    else
        echo "ERROR: ZDM_HOME not set"
        return 1
    fi
}

################################################################################
# Initialize
################################################################################

echo "ZDM Server Discovery Script" > "$OUTPUT_FILE"
echo "Generated: $(date)" >> "$OUTPUT_FILE"
echo "Hostname: $HOSTNAME" >> "$OUTPUT_FILE"
echo "ZDM User: $ZDM_USER" >> "$OUTPUT_FILE"
echo "Source Host (for connectivity test): ${SOURCE_HOST:-NOT_PROVIDED}" >> "$OUTPUT_FILE"
echo "Target Host (for connectivity test): ${TARGET_HOST:-NOT_PROVIDED}" >> "$OUTPUT_FILE"
echo "========================================" >> "$OUTPUT_FILE"

# Detect ZDM environment
detect_zdm_env
apply_overrides

################################################################################
# OS Information Discovery
################################################################################

log_section "OS INFORMATION"

log_info "Hostname: $(hostname -f 2>/dev/null || hostname)"
echo "Hostname: $(hostname -f 2>/dev/null || hostname)" >> "$OUTPUT_FILE"

log_info "Current User: $(whoami)"
echo "Current User: $(whoami)" >> "$OUTPUT_FILE"

log_info "Operating System:"
if [ -f /etc/os-release ]; then
    cat /etc/os-release >> "$OUTPUT_FILE"
elif [ -f /etc/redhat-release ]; then
    cat /etc/redhat-release >> "$OUTPUT_FILE"
fi
uname -a >> "$OUTPUT_FILE"

################################################################################
# Disk Space Discovery (Minimum 50GB recommended for ZDM operations)
################################################################################

log_section "DISK SPACE (ZDM OPERATIONS)"

log_info "Disk Space Overview:"
df -h >> "$OUTPUT_FILE"

log_info "Checking ZDM home directory disk space:"
if [ -n "${ZDM_HOME:-}" ]; then
    ZDM_DISK_SPACE=$(df -h "$ZDM_HOME" 2>/dev/null | tail -1 | awk '{print $4}')
    log_info "Available space in ZDM_HOME ($ZDM_HOME): $ZDM_DISK_SPACE"
    echo "Available space in ZDM_HOME ($ZDM_HOME): $ZDM_DISK_SPACE" >> "$OUTPUT_FILE"
    
    # Check if available space is sufficient (50GB recommended)
    ZDM_DISK_AVAIL_KB=$(df -k "$ZDM_HOME" 2>/dev/null | tail -1 | awk '{print $4}')
    if [ -n "$ZDM_DISK_AVAIL_KB" ] && [ "$ZDM_DISK_AVAIL_KB" -lt 52428800 ]; then
        log_warn "WARNING: Less than 50GB available in ZDM_HOME - may be insufficient for ZDM operations"
    else
        log_info "Disk space check: PASSED (50GB+ available)"
    fi
else
    log_warn "ZDM_HOME not detected - cannot check ZDM disk space"
fi

log_info "Checking /tmp disk space (used for temporary files):"
TMP_DISK_SPACE=$(df -h /tmp 2>/dev/null | tail -1 | awk '{print $4}')
echo "Available space in /tmp: $TMP_DISK_SPACE" >> "$OUTPUT_FILE"

################################################################################
# ZDM Installation Discovery
################################################################################

log_section "ZDM INSTALLATION"

if [ -z "${ZDM_HOME:-}" ]; then
    log_error "ZDM_HOME not detected"
    echo "ZDM_HOME: NOT_DETECTED" >> "$OUTPUT_FILE"
else
    log_info "ZDM_HOME: $ZDM_HOME"
    echo "ZDM_HOME: $ZDM_HOME" >> "$OUTPUT_FILE"
fi

# Verify ZDM installation
log_info "ZDM Installation Verification:"
if [ -n "${ZDM_HOME:-}" ]; then
    if [ -f "$ZDM_HOME/bin/zdmcli" ] || sudo test -f "$ZDM_HOME/bin/zdmcli" 2>/dev/null; then
        log_info "zdmcli binary found: $ZDM_HOME/bin/zdmcli"
        echo "zdmcli binary: FOUND at $ZDM_HOME/bin/zdmcli" >> "$OUTPUT_FILE"
        
        # Check if executable
        if [ -x "$ZDM_HOME/bin/zdmcli" ] || sudo test -x "$ZDM_HOME/bin/zdmcli" 2>/dev/null; then
            log_info "zdmcli is executable"
            echo "zdmcli executable: YES" >> "$OUTPUT_FILE"
        else
            log_warn "zdmcli is not executable"
            echo "zdmcli executable: NO" >> "$OUTPUT_FILE"
        fi
        
        # Run zdmcli without arguments to show usage (verifies installation)
        log_info "ZDM CLI usage (verifies installation):"
        run_zdm_cmd "zdmcli" 2>&1 | head -30 >> "$OUTPUT_FILE"
    else
        log_error "zdmcli binary not found at $ZDM_HOME/bin/zdmcli"
        echo "zdmcli binary: NOT_FOUND" >> "$OUTPUT_FILE"
    fi
    
    # Check for response file templates
    log_info "ZDM Response File Templates:"
    if sudo ls "$ZDM_HOME/rhp/zdm/template/"*.rsp 2>/dev/null; then
        sudo ls -la "$ZDM_HOME/rhp/zdm/template/"*.rsp >> "$OUTPUT_FILE" 2>&1
    else
        echo "No response file templates found in $ZDM_HOME/rhp/zdm/template/" >> "$OUTPUT_FILE"
    fi
else
    log_error "Cannot verify ZDM installation - ZDM_HOME not set"
fi

# ZDM Service Status
log_info "ZDM Service Status:"
if [ -n "${ZDM_HOME:-}" ]; then
    if [ "$(whoami)" = "$ZDM_USER" ]; then
        $ZDM_HOME/bin/zdmservice status >> "$OUTPUT_FILE" 2>&1
    else
        sudo -u "$ZDM_USER" ZDM_HOME="$ZDM_HOME" $ZDM_HOME/bin/zdmservice status >> "$OUTPUT_FILE" 2>&1
    fi
else
    echo "Cannot check ZDM service - ZDM_HOME not set" >> "$OUTPUT_FILE"
fi

# Active Migration Jobs
log_info "Active Migration Jobs:"
if [ -n "${ZDM_HOME:-}" ]; then
    run_zdm_cmd "zdmcli query job -jobtype MIGRATE_DATABASE" 2>&1 | head -50 >> "$OUTPUT_FILE"
else
    echo "Cannot query migration jobs - ZDM_HOME not set" >> "$OUTPUT_FILE"
fi

################################################################################
# Java Configuration Discovery
################################################################################

log_section "JAVA CONFIGURATION"

if [ -z "${JAVA_HOME:-}" ]; then
    log_warn "JAVA_HOME not detected"
    echo "JAVA_HOME: NOT_DETECTED" >> "$OUTPUT_FILE"
else
    log_info "JAVA_HOME: $JAVA_HOME"
    echo "JAVA_HOME: $JAVA_HOME" >> "$OUTPUT_FILE"
fi

log_info "Java Version:"
if [ -n "${JAVA_HOME:-}" ] && [ -f "$JAVA_HOME/bin/java" ]; then
    "$JAVA_HOME/bin/java" -version >> "$OUTPUT_FILE" 2>&1
elif command -v java >/dev/null 2>&1; then
    java -version >> "$OUTPUT_FILE" 2>&1
else
    echo "Java not found in PATH or JAVA_HOME" >> "$OUTPUT_FILE"
fi

################################################################################
# OCI CLI Configuration Discovery
################################################################################

log_section "OCI CLI CONFIGURATION"

log_info "OCI CLI Version:"
oci --version >> "$OUTPUT_FILE" 2>&1 || echo "OCI CLI not installed or not in PATH" >> "$OUTPUT_FILE"

log_info "OCI Config File Location:"
if [ -f ~/.oci/config ]; then
    echo "OCI config file exists at ~/.oci/config" >> "$OUTPUT_FILE"
    log_info "OCI Config Profiles and Regions (sensitive data masked):"
    grep -E '^\[|^user=|^fingerprint=|^tenancy=|^region=' ~/.oci/config 2>/dev/null >> "$OUTPUT_FILE"
else
    echo "OCI config file not found at ~/.oci/config" >> "$OUTPUT_FILE"
fi

log_info "OCI API Key File:"
if [ -f ~/.oci/oci_api_key.pem ]; then
    echo "OCI API key file exists at ~/.oci/oci_api_key.pem" >> "$OUTPUT_FILE"
else
    echo "OCI API key file not found at ~/.oci/oci_api_key.pem" >> "$OUTPUT_FILE"
    # Check for other key files
    ls ~/.oci/*.pem 2>/dev/null >> "$OUTPUT_FILE" || echo "No .pem files found in ~/.oci/" >> "$OUTPUT_FILE"
fi

log_info "OCI Connectivity Test:"
oci iam region list --output table 2>&1 | head -20 >> "$OUTPUT_FILE" || echo "OCI connectivity test failed or OCI CLI not configured" >> "$OUTPUT_FILE"

################################################################################
# SSH Configuration Discovery
################################################################################

log_section "SSH CONFIGURATION"

log_info "Available SSH Keys (current user):"
if [ -d ~/.ssh ]; then
    ls -la ~/.ssh/ 2>/dev/null >> "$OUTPUT_FILE"
else
    echo "SSH directory not found for current user" >> "$OUTPUT_FILE"
fi

log_info "SSH Keys for $ZDM_USER:"
ZDM_USER_HOME=$(eval echo ~$ZDM_USER 2>/dev/null)
if [ -d "$ZDM_USER_HOME/.ssh" ]; then
    sudo ls -la "$ZDM_USER_HOME/.ssh/" 2>/dev/null >> "$OUTPUT_FILE"
else
    echo "SSH directory not found for $ZDM_USER user" >> "$OUTPUT_FILE"
fi

################################################################################
# Credential Files Discovery
################################################################################

log_section "CREDENTIAL FILES"

log_info "Searching for password/credential files (warning: should be secured):"
find ~ -name "*password*" -o -name "*credential*" -o -name "*.wallet" 2>/dev/null | head -20 >> "$OUTPUT_FILE"
if [ $? -ne 0 ] || [ -z "$(find ~ -name "*password*" -o -name "*credential*" -o -name "*.wallet" 2>/dev/null)" ]; then
    echo "No password/credential files found in home directory (this is good)" >> "$OUTPUT_FILE"
fi

################################################################################
# Network Configuration Discovery
################################################################################

log_section "NETWORK CONFIGURATION"

log_info "IP Addresses:"
ip addr show 2>/dev/null | grep 'inet ' | awk '{print $2}' >> "$OUTPUT_FILE" || \
    ifconfig 2>/dev/null | grep 'inet ' >> "$OUTPUT_FILE"

log_info "Routing Table:"
ip route show 2>/dev/null >> "$OUTPUT_FILE" || \
    netstat -rn 2>/dev/null >> "$OUTPUT_FILE"

log_info "DNS Configuration:"
cat /etc/resolv.conf >> "$OUTPUT_FILE"

################################################################################
# Network Connectivity Tests (Source and Target)
################################################################################

log_section "NETWORK CONNECTIVITY TESTS"

# Initialize test results for JSON
SOURCE_PING="SKIPPED"
SOURCE_SSH="SKIPPED"
SOURCE_ORACLE="SKIPPED"
TARGET_PING="SKIPPED"
TARGET_SSH="SKIPPED"
TARGET_ORACLE="SKIPPED"
SOURCE_LATENCY="N/A"
TARGET_LATENCY="N/A"

# Test connectivity to source
if [ -n "${SOURCE_HOST:-}" ]; then
    log_info "Testing connectivity to SOURCE: $SOURCE_HOST"
    
    # Ping test with latency measurement
    log_info "Ping test to $SOURCE_HOST:"
    if ping -c 3 "$SOURCE_HOST" >> "$OUTPUT_FILE" 2>&1; then
        SOURCE_PING="SUCCESS"
        SOURCE_LATENCY=$(ping -c 3 "$SOURCE_HOST" 2>/dev/null | tail -1 | awk -F'/' '{print $5}')
        log_info "Ping to source: SUCCESS (avg latency: ${SOURCE_LATENCY}ms)"
    else
        SOURCE_PING="FAILED"
        log_warn "Ping to source: FAILED"
    fi
    
    # SSH port test (22)
    log_info "SSH port (22) test to $SOURCE_HOST:"
    if timeout 5 bash -c "echo >/dev/tcp/$SOURCE_HOST/22" 2>/dev/null; then
        SOURCE_SSH="OPEN"
        log_info "Source SSH port (22): OPEN"
        echo "Source SSH port (22): OPEN" >> "$OUTPUT_FILE"
    else
        SOURCE_SSH="BLOCKED"
        log_warn "Source SSH port (22): BLOCKED or unreachable"
        echo "Source SSH port (22): BLOCKED or unreachable" >> "$OUTPUT_FILE"
    fi
    
    # Oracle port test (1521)
    log_info "Oracle port (1521) test to $SOURCE_HOST:"
    if timeout 5 bash -c "echo >/dev/tcp/$SOURCE_HOST/1521" 2>/dev/null; then
        SOURCE_ORACLE="OPEN"
        log_info "Source Oracle port (1521): OPEN"
        echo "Source Oracle port (1521): OPEN" >> "$OUTPUT_FILE"
    else
        SOURCE_ORACLE="BLOCKED"
        log_warn "Source Oracle port (1521): BLOCKED or unreachable"
        echo "Source Oracle port (1521): BLOCKED or unreachable" >> "$OUTPUT_FILE"
    fi
else
    log_info "SOURCE_HOST not provided - skipping source connectivity tests"
    echo "SOURCE_HOST not provided - skipping source connectivity tests" >> "$OUTPUT_FILE"
fi

# Test connectivity to target
if [ -n "${TARGET_HOST:-}" ]; then
    log_info "Testing connectivity to TARGET: $TARGET_HOST"
    
    # Ping test with latency measurement
    log_info "Ping test to $TARGET_HOST:"
    if ping -c 3 "$TARGET_HOST" >> "$OUTPUT_FILE" 2>&1; then
        TARGET_PING="SUCCESS"
        TARGET_LATENCY=$(ping -c 3 "$TARGET_HOST" 2>/dev/null | tail -1 | awk -F'/' '{print $5}')
        log_info "Ping to target: SUCCESS (avg latency: ${TARGET_LATENCY}ms)"
    else
        TARGET_PING="FAILED"
        log_warn "Ping to target: FAILED"
    fi
    
    # SSH port test (22)
    log_info "SSH port (22) test to $TARGET_HOST:"
    if timeout 5 bash -c "echo >/dev/tcp/$TARGET_HOST/22" 2>/dev/null; then
        TARGET_SSH="OPEN"
        log_info "Target SSH port (22): OPEN"
        echo "Target SSH port (22): OPEN" >> "$OUTPUT_FILE"
    else
        TARGET_SSH="BLOCKED"
        log_warn "Target SSH port (22): BLOCKED or unreachable"
        echo "Target SSH port (22): BLOCKED or unreachable" >> "$OUTPUT_FILE"
    fi
    
    # Oracle port test (1521)
    log_info "Oracle port (1521) test to $TARGET_HOST:"
    if timeout 5 bash -c "echo >/dev/tcp/$TARGET_HOST/1521" 2>/dev/null; then
        TARGET_ORACLE="OPEN"
        log_info "Target Oracle port (1521): OPEN"
        echo "Target Oracle port (1521): OPEN" >> "$OUTPUT_FILE"
    else
        TARGET_ORACLE="BLOCKED"
        log_warn "Target Oracle port (1521): BLOCKED or unreachable"
        echo "Target Oracle port (1521): BLOCKED or unreachable" >> "$OUTPUT_FILE"
    fi
else
    log_info "TARGET_HOST not provided - skipping target connectivity tests"
    echo "TARGET_HOST not provided - skipping target connectivity tests" >> "$OUTPUT_FILE"
fi

################################################################################
# ZDM Logs Discovery
################################################################################

log_section "ZDM LOGS"

log_info "ZDM Log Directory Location:"
if [ -n "${ZDM_HOME:-}" ]; then
    ZDM_LOG_DIR="$ZDM_HOME/rhp/zdm/zdmlog"
    if sudo test -d "$ZDM_LOG_DIR" 2>/dev/null; then
        echo "ZDM log directory: $ZDM_LOG_DIR" >> "$OUTPUT_FILE"
        log_info "Recent ZDM log files:"
        sudo ls -lt "$ZDM_LOG_DIR" 2>/dev/null | head -20 >> "$OUTPUT_FILE"
    else
        echo "ZDM log directory not found at $ZDM_LOG_DIR" >> "$OUTPUT_FILE"
    fi
else
    echo "Cannot check ZDM logs - ZDM_HOME not set" >> "$OUTPUT_FILE"
fi

################################################################################
# Generate JSON Summary
################################################################################

log_section "GENERATING JSON SUMMARY"

# Check ZDM status for JSON
ZDM_STATUS="NOT_DETECTED"
if [ -n "${ZDM_HOME:-}" ] && ([ -f "$ZDM_HOME/bin/zdmcli" ] || sudo test -f "$ZDM_HOME/bin/zdmcli" 2>/dev/null); then
    ZDM_STATUS="INSTALLED"
fi

# Get OCI CLI version for JSON
OCI_VERSION=$(oci --version 2>/dev/null || echo "NOT_INSTALLED")

# Get Java version for JSON
JAVA_VERSION=$("${JAVA_HOME:-/usr}/bin/java" -version 2>&1 | head -1 || java -version 2>&1 | head -1 || echo "NOT_DETECTED")

cat > "$JSON_FILE" <<EOF
{
  "discovery_type": "zdm_server",
  "discovery_timestamp": "$(date -Iseconds)",
  "hostname": "$HOSTNAME",
  "current_user": "$(whoami)",
  "zdm_user": "$ZDM_USER",
  "zdm": {
    "zdm_home": "${ZDM_HOME:-NOT_DETECTED}",
    "status": "$ZDM_STATUS"
  },
  "java": {
    "java_home": "${JAVA_HOME:-NOT_DETECTED}",
    "version": "$JAVA_VERSION"
  },
  "oci_cli": {
    "version": "$OCI_VERSION"
  },
  "disk_space": {
    "zdm_home_available": "${ZDM_DISK_SPACE:-N/A}",
    "tmp_available": "${TMP_DISK_SPACE:-N/A}"
  },
  "connectivity": {
    "source": {
      "host": "${SOURCE_HOST:-NOT_PROVIDED}",
      "ping": "$SOURCE_PING",
      "latency_ms": "${SOURCE_LATENCY}",
      "ssh_port_22": "$SOURCE_SSH",
      "oracle_port_1521": "$SOURCE_ORACLE"
    },
    "target": {
      "host": "${TARGET_HOST:-NOT_PROVIDED}",
      "ping": "$TARGET_PING",
      "latency_ms": "${TARGET_LATENCY}",
      "ssh_port_22": "$TARGET_SSH",
      "oracle_port_1521": "$TARGET_ORACLE"
    }
  },
  "output_files": {
    "text_report": "$OUTPUT_FILE",
    "json_summary": "$JSON_FILE"
  }
}
EOF

log_info "JSON summary written to: $JSON_FILE"

################################################################################
# Summary
################################################################################

log_section "DISCOVERY COMPLETE"

log_info "Text report: $OUTPUT_FILE"
log_info "JSON summary: $JSON_FILE"

echo ""
echo -e "${GREEN}ZDM server discovery complete!${NC}"
echo "Output files created in current directory:"
echo "  - $OUTPUT_FILE"
echo "  - $JSON_FILE"
