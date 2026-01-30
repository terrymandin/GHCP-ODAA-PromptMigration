#!/bin/bash
# ===========================================
# ZDM Server Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# ZDM Server: zdm-jumpbox.corp.example.com
# Generated: 2026-01-30
# ===========================================
#
# This script discovers ZDM server configuration for migration.
# Run as: azureuser (or admin user with sudo to zdmuser)
#
# Usage:
#   ./zdm_server_discovery.sh
#
# Output:
#   - zdm_server_discovery_<hostname>_<timestamp>.txt (human-readable)
#   - zdm_server_discovery_<hostname>_<timestamp>.json (machine-parseable)
# ===========================================

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# User configuration
ZDM_USER="${ZDM_USER:-zdmuser}"

# Timestamp and hostname for output files
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME_SHORT=$(hostname -s)
OUTPUT_TXT="./zdm_server_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
OUTPUT_JSON="./zdm_server_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

# ===========================================
# HELPER FUNCTIONS
# ===========================================

log_section() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
    echo -e "\n=== $1 ===" >> "$OUTPUT_TXT"
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
    echo "[INFO] $1" >> "$OUTPUT_TXT"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    echo "[WARN] $1" >> "$OUTPUT_TXT"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[ERROR] $1" >> "$OUTPUT_TXT"
}

# Auto-detect ZDM environment
detect_zdm_env() {
    # If already set, use existing values
    if [ -n "${ZDM_HOME:-}" ] && [ -n "${JAVA_HOME:-}" ]; then
        return 0
    fi
    
    # Detect ZDM_HOME using multiple methods
    if [ -z "${ZDM_HOME:-}" ]; then
        # Method 1: Get ZDM_HOME from zdmuser's environment
        if id "$ZDM_USER" &>/dev/null; then
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
            for path in /u01/app/zdmhome /u01/zdm /u01/app/zdm /opt/zdm /home/zdmuser/zdmhome; do
                if sudo test -d "$path" 2>/dev/null && sudo test -f "$path/bin/zdmcli" 2>/dev/null; then
                    export ZDM_HOME="$path"
                    break
                elif [ -d "$path" ] && [ -f "$path/bin/zdmcli" ]; then
                    export ZDM_HOME="$path"
                    break
                fi
            done
        fi
        
        # Method 4: Search for zdmcli binary
        if [ -z "${ZDM_HOME:-}" ]; then
            local zdmcli_path
            zdmcli_path=$(sudo find /u01 /opt /home -name "zdmcli" -type f 2>/dev/null | head -1)
            if [ -n "$zdmcli_path" ]; then
                export ZDM_HOME="$(dirname "$(dirname "$zdmcli_path")")"
            fi
        fi
    fi
    
    # Detect JAVA_HOME - check ZDM's bundled JDK first
    if [ -z "${JAVA_HOME:-}" ]; then
        # Method 1: Check ZDM's bundled JDK
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

# Run ZDM command as zdmuser
run_zdm_cmd() {
    local zdm_cmd="$1"
    if [ -n "${ZDM_HOME:-}" ]; then
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

# ===========================================
# MAIN DISCOVERY
# ===========================================

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  ZDM Server Discovery${NC}"
echo -e "${BLUE}  Project: PRODDB Migration${NC}"
echo -e "${BLUE}=========================================${NC}"

# Initialize output file
echo "ZDM Server Discovery Report" > "$OUTPUT_TXT"
echo "Project: PRODDB Migration to Oracle Database@Azure" >> "$OUTPUT_TXT"
echo "Generated: $(date)" >> "$OUTPUT_TXT"
echo "Hostname: $(hostname)" >> "$OUTPUT_TXT"
echo "Current User: $(whoami)" >> "$OUTPUT_TXT"
echo "==========================================" >> "$OUTPUT_TXT"

# Detect ZDM environment
detect_zdm_env

# -------------------------------------------
# OS INFORMATION
# -------------------------------------------
log_section "OS Information"

HOSTNAME_FULL=$(hostname -f 2>/dev/null || hostname)
IP_ADDRESSES=$(hostname -I 2>/dev/null || ip addr show | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | tr '\n' ' ')
OS_VERSION=$(cat /etc/os-release 2>/dev/null | grep "PRETTY_NAME" | cut -d'"' -f2)
KERNEL_VERSION=$(uname -r)
CURRENT_USER=$(whoami)

log_info "Hostname: $HOSTNAME_FULL"
log_info "IP Addresses: $IP_ADDRESSES"
log_info "OS Version: $OS_VERSION"
log_info "Kernel: $KERNEL_VERSION"
log_info "Current User: $CURRENT_USER"
log_info "ZDM User: $ZDM_USER"

# -------------------------------------------
# DISK SPACE (CUSTOM REQUIREMENT - Minimum 50GB)
# -------------------------------------------
log_section "Disk Space Analysis"

echo "" >> "$OUTPUT_TXT"
echo "Disk Usage:" >> "$OUTPUT_TXT"
df -h >> "$OUTPUT_TXT" 2>/dev/null

# Check available space on key partitions
ROOT_AVAIL=$(df -BG / 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')
HOME_AVAIL=$(df -BG /home 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')
ZDM_AVAIL="N/A"

if [ -n "${ZDM_HOME:-}" ] && [ -d "${ZDM_HOME}" ]; then
    ZDM_AVAIL=$(df -BG "${ZDM_HOME}" 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')
fi

log_info "Root (/) available: ${ROOT_AVAIL:-N/A} GB"
log_info "Home (/home) available: ${HOME_AVAIL:-N/A} GB"
log_info "ZDM_HOME partition available: ${ZDM_AVAIL} GB"

# Minimum 50GB check
MIN_SPACE=50
SPACE_OK="false"
if [ -n "$ROOT_AVAIL" ] && [ "$ROOT_AVAIL" -ge "$MIN_SPACE" ] 2>/dev/null; then
    SPACE_OK="true"
    log_info "Disk space check: ${GREEN}PASS${NC} (>= ${MIN_SPACE}GB available)"
elif [ -n "$HOME_AVAIL" ] && [ "$HOME_AVAIL" -ge "$MIN_SPACE" ] 2>/dev/null; then
    SPACE_OK="true"
    log_info "Disk space check: ${GREEN}PASS${NC} (>= ${MIN_SPACE}GB available on /home)"
else
    log_warn "Disk space check: FAIL (< ${MIN_SPACE}GB available) - recommend expanding disk"
fi

# -------------------------------------------
# ZDM INSTALLATION
# -------------------------------------------
log_section "ZDM Installation"

log_info "ZDM_HOME: ${ZDM_HOME:-NOT FOUND}"

ZDM_INSTALLED="false"
ZDM_SERVICE_STATUS="NOT RUNNING"

if [ -n "${ZDM_HOME:-}" ]; then
    if [ -f "${ZDM_HOME}/bin/zdmcli" ]; then
        ZDM_INSTALLED="true"
        log_info "ZDM CLI: Found at ${ZDM_HOME}/bin/zdmcli"
        
        # Check if executable
        if [ -x "${ZDM_HOME}/bin/zdmcli" ] || sudo test -x "${ZDM_HOME}/bin/zdmcli" 2>/dev/null; then
            log_info "ZDM CLI: Executable"
        else
            log_warn "ZDM CLI: Not executable"
        fi
        
        # Check for response file templates
        if sudo ls "${ZDM_HOME}/rhp/zdm/template/"*.rsp &>/dev/null 2>&1; then
            log_info "ZDM Templates: Found"
        else
            log_warn "ZDM Templates: Not found"
        fi
    else
        log_error "ZDM CLI not found at ${ZDM_HOME}/bin/zdmcli"
    fi
    
    # ZDM Service Status
    echo "" >> "$OUTPUT_TXT"
    echo "ZDM Service Status:" >> "$OUTPUT_TXT"
    if sudo -u "$ZDM_USER" ZDM_HOME="$ZDM_HOME" $ZDM_HOME/bin/zdmservice status >> "$OUTPUT_TXT" 2>&1; then
        ZDM_SERVICE_STATUS="RUNNING"
        log_info "ZDM Service: RUNNING"
    else
        log_warn "ZDM Service: NOT RUNNING or error querying status"
    fi
    
    # Active migration jobs
    echo "" >> "$OUTPUT_TXT"
    echo "Active Migration Jobs:" >> "$OUTPUT_TXT"
    run_zdm_cmd "zdmcli query job" >> "$OUTPUT_TXT" 2>&1 || echo "No active jobs or could not query" >> "$OUTPUT_TXT"
else
    log_error "ZDM_HOME not detected - ZDM may not be installed"
fi

# -------------------------------------------
# JAVA CONFIGURATION
# -------------------------------------------
log_section "Java Configuration"

log_info "JAVA_HOME: ${JAVA_HOME:-NOT SET}"

if [ -n "${JAVA_HOME:-}" ] && [ -f "${JAVA_HOME}/bin/java" ]; then
    JAVA_VERSION=$("${JAVA_HOME}/bin/java" -version 2>&1 | head -1)
    log_info "Java Version: $JAVA_VERSION"
elif command -v java &>/dev/null; then
    JAVA_VERSION=$(java -version 2>&1 | head -1)
    log_info "Java Version (system): $JAVA_VERSION"
else
    log_warn "Java not found"
    JAVA_VERSION="NOT FOUND"
fi

# -------------------------------------------
# OCI CLI CONFIGURATION
# -------------------------------------------
log_section "OCI CLI Configuration"

OCI_INSTALLED="false"
OCI_CONFIGURED="false"
OCI_CONNECTIVITY="FAILED"

if command -v oci &>/dev/null; then
    OCI_INSTALLED="true"
    OCI_VERSION=$(oci --version 2>&1)
    log_info "OCI CLI Version: $OCI_VERSION"
    
    # Check OCI config
    OCI_CONFIG_FILE="${HOME}/.oci/config"
    if [ -f "$OCI_CONFIG_FILE" ]; then
        OCI_CONFIGURED="true"
        log_info "OCI Config: Found at $OCI_CONFIG_FILE"
        
        echo "" >> "$OUTPUT_TXT"
        echo "OCI Config (sensitive data masked):" >> "$OUTPUT_TXT"
        grep -v "key\|pass\|secret" "$OCI_CONFIG_FILE" >> "$OUTPUT_TXT" 2>/dev/null
        
        # Check profiles
        PROFILES=$(grep "^\[" "$OCI_CONFIG_FILE" 2>/dev/null | tr -d '[]')
        log_info "OCI Profiles: $PROFILES"
        
        # Check for API key
        KEY_FILE=$(grep "key_file" "$OCI_CONFIG_FILE" 2>/dev/null | head -1 | cut -d= -f2 | tr -d ' ')
        if [ -n "$KEY_FILE" ] && [ -f "$(eval echo $KEY_FILE)" ]; then
            log_info "OCI API Key: Found"
        else
            log_warn "OCI API Key: Not found or path invalid"
        fi
    else
        log_warn "OCI Config: Not found at $OCI_CONFIG_FILE"
    fi
    
    # Test OCI connectivity
    echo "" >> "$OUTPUT_TXT"
    echo "OCI Connectivity Test:" >> "$OUTPUT_TXT"
    if oci os ns get >> "$OUTPUT_TXT" 2>&1; then
        OCI_CONNECTIVITY="SUCCESS"
        log_info "OCI Connectivity: ${GREEN}SUCCESS${NC}"
    else
        log_error "OCI Connectivity: FAILED"
    fi
else
    log_warn "OCI CLI: Not installed"
    OCI_VERSION="NOT INSTALLED"
fi

# -------------------------------------------
# SSH CONFIGURATION
# -------------------------------------------
log_section "SSH Configuration"

echo "" >> "$OUTPUT_TXT"
echo "SSH Keys (${CURRENT_USER}):" >> "$OUTPUT_TXT"
ls -la ~/.ssh/ >> "$OUTPUT_TXT" 2>/dev/null || echo "SSH directory not found" >> "$OUTPUT_TXT"

# Check for required SSH keys
SOURCE_KEY="~/.ssh/onprem_oracle_key"
TARGET_KEY="~/.ssh/oci_opc_key"
AZURE_KEY="~/.ssh/azure_key"

for key_var in "SOURCE_KEY:$SOURCE_KEY" "TARGET_KEY:$TARGET_KEY" "AZURE_KEY:$AZURE_KEY"; do
    key_name="${key_var%%:*}"
    key_path="${key_var#*:}"
    expanded_path=$(eval echo "$key_path")
    if [ -f "$expanded_path" ]; then
        log_info "$key_name ($key_path): Found"
    else
        log_warn "$key_name ($key_path): Not found"
    fi
done

# Check ZDM user's SSH keys
echo "" >> "$OUTPUT_TXT"
echo "SSH Keys (${ZDM_USER}):" >> "$OUTPUT_TXT"
sudo ls -la ~${ZDM_USER}/.ssh/ >> "$OUTPUT_TXT" 2>/dev/null || echo "ZDM user SSH directory not found" >> "$OUTPUT_TXT"

# -------------------------------------------
# NETWORK CONNECTIVITY (CUSTOM REQUIREMENT)
# -------------------------------------------
log_section "Network Connectivity"

# SOURCE_HOST and TARGET_HOST should be passed as environment variables from orchestration script
# If not provided, connectivity tests will be skipped
SOURCE_HOST="${SOURCE_HOST:-}"
TARGET_HOST="${TARGET_HOST:-}"

# Ping tests for latency
echo "" >> "$OUTPUT_TXT"
echo "Network Latency Tests:" >> "$OUTPUT_TXT"

SOURCE_PING="SKIPPED"
TARGET_PING="SKIPPED"
SOURCE_LATENCY="N/A"
TARGET_LATENCY="N/A"

# Test source connectivity (only if SOURCE_HOST is provided)
if [ -n "$SOURCE_HOST" ]; then
    echo "Ping to Source ($SOURCE_HOST):" >> "$OUTPUT_TXT"
    if ping -c 3 "$SOURCE_HOST" >> "$OUTPUT_TXT" 2>&1; then
        SOURCE_PING="SUCCESS"
        SOURCE_LATENCY=$(ping -c 3 "$SOURCE_HOST" 2>/dev/null | tail -1 | awk -F'/' '{print $5}')
        log_info "Source ping: SUCCESS (avg ${SOURCE_LATENCY:-N/A}ms)"
    else
        SOURCE_PING="FAILED"
        log_warn "Source ping: FAILED - check DNS and network connectivity"
    fi
else
    log_info "SOURCE_HOST not provided - skipping source connectivity tests"
    echo "SOURCE_HOST not provided - skipping source connectivity tests" >> "$OUTPUT_TXT"
fi

# Test target connectivity (only if TARGET_HOST is provided)
if [ -n "$TARGET_HOST" ]; then
    echo "" >> "$OUTPUT_TXT"
    echo "Ping to Target ($TARGET_HOST):" >> "$OUTPUT_TXT"
    if ping -c 3 "$TARGET_HOST" >> "$OUTPUT_TXT" 2>&1; then
        TARGET_PING="SUCCESS"
        TARGET_LATENCY=$(ping -c 3 "$TARGET_HOST" 2>/dev/null | tail -1 | awk -F'/' '{print $5}')
        log_info "Target ping: SUCCESS (avg ${TARGET_LATENCY:-N/A}ms)"
    else
        TARGET_PING="FAILED"
        log_warn "Target ping: FAILED - check DNS and network connectivity"
    fi
else
    log_info "TARGET_HOST not provided - skipping target connectivity tests"
    echo "TARGET_HOST not provided - skipping target connectivity tests" >> "$OUTPUT_TXT"
fi

# Port connectivity tests
echo "" >> "$OUTPUT_TXT"
echo "Port Connectivity Tests:" >> "$OUTPUT_TXT"

# Source ports (only if SOURCE_HOST is provided)
if [ -n "$SOURCE_HOST" ]; then
    for port in 22 1521; do
        if timeout 5 bash -c "echo >/dev/tcp/$SOURCE_HOST/$port" 2>/dev/null; then
            log_info "Source port $port: OPEN"
            echo "  Source:$port - OPEN" >> "$OUTPUT_TXT"
        else
            log_warn "Source port $port: BLOCKED or unreachable"
            echo "  Source:$port - BLOCKED" >> "$OUTPUT_TXT"
        fi
    done
fi

# Target ports (only if TARGET_HOST is provided)
if [ -n "$TARGET_HOST" ]; then
    for port in 22 1521; do
        if timeout 5 bash -c "echo >/dev/tcp/$TARGET_HOST/$port" 2>/dev/null; then
            log_info "Target port $port: OPEN"
            echo "  Target:$port - OPEN" >> "$OUTPUT_TXT"
        else
            log_warn "Target port $port: BLOCKED or unreachable"
            echo "  Target:$port - BLOCKED" >> "$OUTPUT_TXT"
        fi
    done
fi

# -------------------------------------------
# NETWORK CONFIGURATION
# -------------------------------------------
log_section "Network Configuration"

echo "" >> "$OUTPUT_TXT"
echo "IP Addresses:" >> "$OUTPUT_TXT"
ip addr show >> "$OUTPUT_TXT" 2>/dev/null || ifconfig >> "$OUTPUT_TXT" 2>/dev/null

echo "" >> "$OUTPUT_TXT"
echo "Routing Table:" >> "$OUTPUT_TXT"
ip route >> "$OUTPUT_TXT" 2>/dev/null || netstat -rn >> "$OUTPUT_TXT" 2>/dev/null

echo "" >> "$OUTPUT_TXT"
echo "DNS Configuration:" >> "$OUTPUT_TXT"
cat /etc/resolv.conf >> "$OUTPUT_TXT" 2>/dev/null

# -------------------------------------------
# CREDENTIAL FILES
# -------------------------------------------
log_section "Credential Files"

echo "" >> "$OUTPUT_TXT"
echo "Searching for credential files..." >> "$OUTPUT_TXT"

# Search for potential credential files (DO NOT print contents)
CRED_FILES=$(find ~/creds ~/.credentials /tmp -name "*password*" -o -name "*credential*" -o -name "*wallet*" 2>/dev/null | head -10)
if [ -n "$CRED_FILES" ]; then
    log_warn "Potential credential files found (review for security):"
    echo "$CRED_FILES" >> "$OUTPUT_TXT"
else
    log_info "No credential files found in common locations"
fi

# -------------------------------------------
# ZDM LOGS
# -------------------------------------------
log_section "ZDM Logs"

if [ -n "${ZDM_HOME:-}" ]; then
    ZDM_LOG_DIR="${ZDM_HOME}/log"
    if [ -d "$ZDM_LOG_DIR" ] || sudo test -d "$ZDM_LOG_DIR" 2>/dev/null; then
        log_info "ZDM Log Directory: $ZDM_LOG_DIR"
        echo "" >> "$OUTPUT_TXT"
        echo "Recent ZDM Log Files:" >> "$OUTPUT_TXT"
        sudo ls -lt "$ZDM_LOG_DIR" 2>/dev/null | head -10 >> "$OUTPUT_TXT"
    else
        log_warn "ZDM Log Directory not found"
    fi
fi

# -------------------------------------------
# GENERATE JSON OUTPUT
# -------------------------------------------
log_section "Generating JSON Output"

cat > "$OUTPUT_JSON" << EOJSON
{
  "discovery_type": "zdm_server",
  "project": "PRODDB Migration to Oracle Database@Azure",
  "timestamp": "$(date -Iseconds)",
  "hostname": "$HOSTNAME_FULL",
  "ip_addresses": "$IP_ADDRESSES",
  "current_user": "$CURRENT_USER",
  "os": {
    "version": "$OS_VERSION",
    "kernel": "$KERNEL_VERSION"
  },
  "disk_space": {
    "root_available_gb": "${ROOT_AVAIL:-0}",
    "home_available_gb": "${HOME_AVAIL:-0}",
    "zdm_available_gb": "${ZDM_AVAIL:-0}",
    "minimum_required_gb": 50,
    "sufficient": $SPACE_OK
  },
  "zdm": {
    "home": "${ZDM_HOME:-NOT FOUND}",
    "installed": $ZDM_INSTALLED,
    "service_status": "$ZDM_SERVICE_STATUS",
    "user": "$ZDM_USER"
  },
  "java": {
    "home": "${JAVA_HOME:-NOT SET}",
    "version": "${JAVA_VERSION:-NOT FOUND}"
  },
  "oci_cli": {
    "installed": $OCI_INSTALLED,
    "configured": $OCI_CONFIGURED,
    "version": "${OCI_VERSION:-NOT INSTALLED}",
    "connectivity": "$OCI_CONNECTIVITY"
  },
  "network": {
    "source_host": "${SOURCE_HOST:-NOT PROVIDED}",
    "target_host": "${TARGET_HOST:-NOT PROVIDED}",
    "source_ping": "$SOURCE_PING",
    "target_ping": "$TARGET_PING",
    "source_latency_ms": "${SOURCE_LATENCY:-N/A}",
    "target_latency_ms": "${TARGET_LATENCY:-N/A}"
  },
  "readiness": {
    "zdm_installed": $ZDM_INSTALLED,
    "zdm_running": $([ "$ZDM_SERVICE_STATUS" = "RUNNING" ] && echo "true" || echo "false"),
    "oci_configured": $OCI_CONFIGURED,
    "oci_connected": $([ "$OCI_CONNECTIVITY" = "SUCCESS" ] && echo "true" || echo "false"),
    "disk_space_ok": $SPACE_OK,
    "source_reachable": $(if [ "$SOURCE_PING" = "SUCCESS" ]; then echo "true"; elif [ "$SOURCE_PING" = "SKIPPED" ]; then echo "\"skipped\""; else echo "false"; fi),
    "target_reachable": $(if [ "$TARGET_PING" = "SUCCESS" ]; then echo "true"; elif [ "$TARGET_PING" = "SKIPPED" ]; then echo "\"skipped\""; else echo "false"; fi)
  }
}
EOJSON

log_info "JSON output saved to: $OUTPUT_JSON"

# -------------------------------------------
# SUMMARY
# -------------------------------------------
log_section "Discovery Summary"

echo ""
echo -e "${GREEN}ZDM Server discovery completed!${NC}"
echo ""
echo "Output files:"
echo "  - Text report: $OUTPUT_TXT"
echo "  - JSON summary: $OUTPUT_JSON"
echo ""
echo "ZDM Server Readiness:"
echo "  - ZDM Installed: $([ "$ZDM_INSTALLED" = "true" ] && echo -e "${GREEN}YES${NC}" || echo -e "${RED}NO${NC}")"
echo "  - ZDM Service: $([ "$ZDM_SERVICE_STATUS" = "RUNNING" ] && echo -e "${GREEN}RUNNING${NC}" || echo -e "${RED}NOT RUNNING${NC}")"
echo "  - OCI CLI Configured: $([ "$OCI_CONFIGURED" = "true" ] && echo -e "${GREEN}YES${NC}" || echo -e "${RED}NO${NC}")"
echo "  - OCI Connectivity: $([ "$OCI_CONNECTIVITY" = "SUCCESS" ] && echo -e "${GREEN}OK${NC}" || echo -e "${RED}FAILED${NC}")"
echo "  - Disk Space (>=50GB): $([ "$SPACE_OK" = "true" ] && echo -e "${GREEN}OK${NC}" || echo -e "${YELLOW}LOW${NC}")"

# Source/Target reachability - handle SKIPPED case
if [ "$SOURCE_PING" = "SKIPPED" ]; then
    echo -e "  - Source Reachable: ${YELLOW}SKIPPED${NC} (SOURCE_HOST not provided)"
elif [ "$SOURCE_PING" = "SUCCESS" ]; then
    echo -e "  - Source Reachable: ${GREEN}YES${NC}"
else
    echo -e "  - Source Reachable: ${RED}NO${NC}"
fi

if [ "$TARGET_PING" = "SKIPPED" ]; then
    echo -e "  - Target Reachable: ${YELLOW}SKIPPED${NC} (TARGET_HOST not provided)"
elif [ "$TARGET_PING" = "SUCCESS" ]; then
    echo -e "  - Target Reachable: ${GREEN}YES${NC}"
else
    echo -e "  - Target Reachable: ${RED}NO${NC}"
fi

if [ -z "$SOURCE_HOST" ] || [ -z "$TARGET_HOST" ]; then
    echo ""
    echo -e "${YELLOW}NOTE:${NC} To test connectivity, run the orchestration script which passes SOURCE_HOST and TARGET_HOST,"
    echo "      or set these environment variables before running this script:"
    echo "        export SOURCE_HOST='your-source-hostname'"
    echo "        export TARGET_HOST='your-target-hostname'"
fi
echo ""
