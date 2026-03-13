#!/bin/bash
# =============================================================================
# zdm_server_discovery.sh
# Phase 10 â€” ZDM Migration Â· Step 2: ZDM Server Discovery
#
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration
#
# Discovers ZDM installation, Java, OCI CLI, SSH keys, network connectivity
# to source and target hosts, and related server environment on the ZDM server.
#
# Run locally on the ZDM server as zdmuser (or any user with sudo).
#
# The orchestration script MUST export SOURCE_HOST and TARGET_HOST before
# calling this script so network connectivity tests are performed.
#
# Outputs (written to current working directory):
#   zdm_server_discovery_<hostname>_<timestamp>.txt
#   zdm_server_discovery_<hostname>_<timestamp>.json
#
# Usage:
#   chmod +x zdm_server_discovery.sh
#   SOURCE_HOST=10.1.0.11 TARGET_HOST=10.0.1.160 ./zdm_server_discovery.sh
# =============================================================================

# Do NOT use set -e globally â€” individual sections handle their own errors
set -uo pipefail

# ---------------------------------------------------------------------------
# Configuration (set by orchestration script or environment)
# ---------------------------------------------------------------------------
ZDM_USER="${ZDM_USER:-zdmuser}"
ZDM_HOME="${ZDM_HOME:-}"
JAVA_HOME="${JAVA_HOME:-}"
SOURCE_HOST="${SOURCE_HOST:-}"
TARGET_HOST="${TARGET_HOST:-}"
OCI_CONFIG_PATH="${OCI_CONFIG_PATH:-~/.oci/config}"

# Accept explicit overrides
[ -n "${ZDM_REMOTE_ZDM_HOME:-}"  ] && ZDM_HOME="$ZDM_REMOTE_ZDM_HOME"
[ -n "${ZDM_REMOTE_JAVA_HOME:-}" ] && JAVA_HOME="$ZDM_REMOTE_JAVA_HOME"

# ---------------------------------------------------------------------------
# Output paths (write to current working directory)
# ---------------------------------------------------------------------------
HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_TXT="./zdm_server_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
REPORT_JSON="./zdm_server_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log_raw() { echo "$1" | tee -a "$REPORT_TXT"; }
log_info() { echo "[INFO]  $1" | tee -a "$REPORT_TXT"; }
log_warn() { echo "[WARN]  $1" | tee -a "$REPORT_TXT"; }
log_error() { echo "[ERROR] $1" | tee -a "$REPORT_TXT"; }
log_section() {
    log_raw ""
    log_raw "============================================================"
    log_raw "  $1"
    log_raw "============================================================"
}

# ---------------------------------------------------------------------------
# Auto-detect ZDM environment
# ---------------------------------------------------------------------------
detect_zdm_env() {
    if [ -n "${ZDM_HOME:-}" ] && [ -n "${JAVA_HOME:-}" ]; then
        return 0
    fi

    if [ -z "${ZDM_HOME:-}" ]; then
        local zdm_user="${ZDM_USER:-zdmuser}"

        # Method 1: Get ZDM_HOME from zdmuser's login shell
        if id "$zdm_user" >/dev/null 2>&1; then
            local zdm_home_from_user
            zdm_home_from_user=$(sudo su - "$zdm_user" -c 'echo $ZDM_HOME' 2>/dev/null)
            if [ -n "$zdm_home_from_user" ] && sudo test -f "$zdm_home_from_user/bin/zdmcli" 2>/dev/null; then
                ZDM_HOME="$zdm_home_from_user"
            fi
        fi

        # Method 2: Check zdmuser's home directory
        if [ -z "${ZDM_HOME:-}" ]; then
            local zdm_user_home
            zdm_user_home=$(eval echo "~$zdm_user" 2>/dev/null)
            if [ -n "$zdm_user_home" ]; then
                for subdir in zdmhome zdm app/zdmhome; do
                    local candidate="$zdm_user_home/$subdir"
                    if sudo test -d "$candidate" 2>/dev/null && sudo test -f "$candidate/bin/zdmcli" 2>/dev/null; then
                        ZDM_HOME="$candidate"
                        break
                    fi
                done
            fi
        fi

        # Method 3: Common system paths
        if [ -z "${ZDM_HOME:-}" ]; then
            for path in /u01/app/zdmhome /u01/zdm /u01/app/zdm /opt/zdm /home/zdmuser/zdmhome \
                        "/home/${ZDM_USER:-zdmuser}/zdmhome" "$HOME/zdmhome"; do
                if sudo test -d "$path" 2>/dev/null && sudo test -f "$path/bin/zdmcli" 2>/dev/null; then
                    ZDM_HOME="$path"
                    break
                fi
            done
        fi

        # Method 4: Find zdmcli binary
        if [ -z "${ZDM_HOME:-}" ]; then
            local zdmcli_path
            zdmcli_path=$(sudo find /u01 /opt /home -name "zdmcli" -type f 2>/dev/null | head -1)
            if [ -n "$zdmcli_path" ]; then
                ZDM_HOME="$(dirname "$(dirname "$zdmcli_path")")"
            fi
        fi
    fi

    # Detect JAVA_HOME â€” ZDM's bundled JDK first
    if [ -z "${JAVA_HOME:-}" ]; then
        if [ -n "${ZDM_HOME:-}" ] && [ -d "${ZDM_HOME}/jdk" ]; then
            JAVA_HOME="${ZDM_HOME}/jdk"
        elif command -v java >/dev/null 2>&1; then
            local java_path
            java_path=$(readlink -f "$(command -v java)" 2>/dev/null)
            [ -n "$java_path" ] && JAVA_HOME="${java_path%/bin/java}"
        else
            for path in /usr/java/latest /usr/java/jdk* /usr/lib/jvm/java-* /opt/java/jdk*; do
                if [ -d "$path" ] && [ -f "$path/bin/java" ]; then
                    JAVA_HOME="$path"
                    break
                fi
            done
        fi
    fi
}

# ---------------------------------------------------------------------------
# ZDM version detection
# ---------------------------------------------------------------------------
detect_zdm_version() {
    local ZDM_VERSION=""
    local ZDM_OPATCH=""

    if [ -z "${ZDM_HOME:-}" ]; then
        echo "UNDETERMINED"
        return
    fi

    # Method 1: Oracle Inventory XML
    if sudo test -f "${ZDM_HOME}/inventory/ContentsXML/comps.xml" 2>/dev/null; then
        ZDM_VERSION=$(sudo grep -oP '(?<=VER=")[0-9.]+' "${ZDM_HOME}/inventory/ContentsXML/comps.xml" 2>/dev/null | head -1)
    fi

    # Method 2: OPatch
    if [ -z "${ZDM_VERSION:-}" ] && sudo test -x "${ZDM_HOME}/OPatch/opatch" 2>/dev/null; then
        ZDM_OPATCH=$(sudo su - "${ZDM_USER:-zdmuser}" -c "${ZDM_HOME}/OPatch/opatch lspatches" 2>/dev/null | head -20)
    fi

    # Method 3: version.txt files
    if [ -z "${ZDM_VERSION:-}" ]; then
        for vfile in "${ZDM_HOME}/version.txt" "${ZDM_HOME}/VERSION" "${ZDM_HOME}/rhp/version.txt"; do
            if sudo test -f "$vfile" 2>/dev/null; then
                ZDM_VERSION=$(sudo cat "$vfile" 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9.]+' | head -1)
                break
            fi
        done
    fi

    # Method 4: zdmbase log/build files
    if [ -z "${ZDM_VERSION:-}" ]; then
        for bfile in "${ZDM_HOME}/../../zdmbase/rhp/version.txt" "${ZDM_HOME}/../zdmbase/rhp/version.txt"; do
            if sudo test -f "$bfile" 2>/dev/null; then
                ZDM_VERSION=$(sudo cat "$bfile" 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9.]+' | head -1)
                break
            fi
        done
    fi

    # Method 5: Derive major version from ZDM_HOME path
    if [ -z "${ZDM_VERSION:-}" ]; then
        ZDM_VERSION=$(echo "${ZDM_HOME}" | grep -oP '[0-9]+' | tail -1)
        [ -n "${ZDM_VERSION:-}" ] && ZDM_VERSION="(derived from path: ${ZDM_VERSION})"
    fi

    echo "${ZDM_VERSION:-UNDETERMINED}"
}

# ============================================================================
# MAIN
# ============================================================================
: > "$REPORT_TXT"

log_raw "============================================================"
log_raw "  ZDM Step 2 â€” ZDM Server Discovery"
log_raw "  Generated : $(date)"
log_raw "  Run by    : $(whoami)@$(hostname)"
log_raw "============================================================"

# ============================================================================
# 1. OS INFORMATION
# ============================================================================
log_section "1. OS INFORMATION"

OS_HOSTNAME="$(hostname -f 2>/dev/null || hostname)"
CURRENT_USER="$(whoami)"
log_info "Hostname    : $OS_HOSTNAME"
log_info "Current User: $CURRENT_USER"

if [ "$CURRENT_USER" != "$ZDM_USER" ]; then
    log_warn "Script is running as '$CURRENT_USER', not '$ZDM_USER'. Some ZDM paths may require sudo."
fi

OS_VERSION="$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"' || uname -r)"
log_info "OS Version  : $OS_VERSION"

log_raw ""
log_info "--- Disk Space (all mount points) ---"
log_info "NOTE: ZDM operations require >= 25GB free; >= 50GB preferred on ZDM_HOME and /tmp"
df -h 2>/dev/null | tee -a "$REPORT_TXT"

# Warn on filesystems with < 50GB free
log_raw ""
log_info "--- Low Disk Space Warnings (< 50GB free) ---"
df -BG 2>/dev/null | awk 'NR>1 {
    avail = $4
    gsub(/G/, "", avail)
    if (avail+0 < 50) print "[WARN]  Low disk: " $0 " â€” only " avail "GB free (50GB+ preferred)"
}' | tee -a "$REPORT_TXT" || true

# ============================================================================
# 2. ZDM INSTALLATION
# ============================================================================
log_section "2. ZDM INSTALLATION"

detect_zdm_env

ZDM_HOME_STATUS="NOT FOUND"
ZDM_CLI_STATUS="NOT FOUND"
ZDM_VERSION="UNDETERMINED"
ZDM_SERVICE_STATUS="UNKNOWN"
ZDM_OPATCH_PATCHES="N/A"

if [ -n "${ZDM_HOME:-}" ]; then
    ZDM_HOME_STATUS="$ZDM_HOME"
    log_info "ZDM_HOME: $ZDM_HOME"

    # Check zdmcli exists and is executable
    if sudo test -x "${ZDM_HOME}/bin/zdmcli" 2>/dev/null; then
        ZDM_CLI_STATUS="FOUND and EXECUTABLE"
        log_info "zdmcli: ${ZDM_HOME}/bin/zdmcli â€” $ZDM_CLI_STATUS"

        # Run zdmcli without args to verify it responds (do NOT use -version)
        log_raw ""
        log_info "--- zdmcli usage output (no args) ---"
        sudo su - "${ZDM_USER}" -c "${ZDM_HOME}/bin/zdmcli" 2>&1 | head -20 | tee -a "$REPORT_TXT" || \
            log_warn "zdmcli invocation produced no output or error"
    else
        log_warn "zdmcli not found or not executable at ${ZDM_HOME}/bin/zdmcli"
    fi

    # ZDM Version
    ZDM_VERSION="$(detect_zdm_version)"
    if [ "$ZDM_VERSION" = "UNDETERMINED" ]; then
        log_warn "ZDM Version: UNDETERMINED â€” manual inspection required"
    else
        log_info "ZDM Version: $ZDM_VERSION"
    fi

    # OPatch patches
    if sudo test -x "${ZDM_HOME}/OPatch/opatch" 2>/dev/null; then
        log_raw ""
        log_info "--- Installed OPatch Patches ---"
        ZDM_OPATCH_PATCHES="$(sudo su - "${ZDM_USER}" -c "${ZDM_HOME}/OPatch/opatch lspatches" 2>/dev/null | head -20 | tee -a "$REPORT_TXT")"
    fi

    # Response file templates
    log_raw ""
    log_info "--- ZDM Response File Templates ---"
    sudo ls "${ZDM_HOME}/rhp/zdm/template/"*.rsp 2>/dev/null | tee -a "$REPORT_TXT" || \
        log_info "No .rsp templates found at ${ZDM_HOME}/rhp/zdm/template/"

    # Check ZDM service
    log_raw ""
    log_info "--- ZDM Service Status ---"
    ZDM_SERVICE_OUTPUT="$(sudo su - "${ZDM_USER}" -c "zdmservice status" 2>&1 || true)"
    echo "$ZDM_SERVICE_OUTPUT" | tee -a "$REPORT_TXT"
    if echo "$ZDM_SERVICE_OUTPUT" | grep -qi "running"; then
        ZDM_SERVICE_STATUS="RUNNING"
    else
        ZDM_SERVICE_STATUS="NOT RUNNING"
        log_warn "ZDM service does not appear to be running"
    fi

    # Active migration jobs
    log_raw ""
    log_info "--- Active Migration Jobs ---"
    sudo su - "${ZDM_USER}" -c "${ZDM_HOME}/bin/zdmcli query job" 2>&1 | tee -a "$REPORT_TXT" || \
        log_warn "Could not query ZDM jobs"

else
    log_warn "ZDM_HOME not found. Check ZDM installation."
    log_warn "Set ZDM_REMOTE_ZDM_HOME env var to specify the path explicitly."
fi

# ============================================================================
# 3. JAVA CONFIGURATION
# ============================================================================
log_section "3. JAVA CONFIGURATION"

{
    log_info "JAVA_HOME: ${JAVA_HOME:-NOT DETECTED}"
    if [ -n "${JAVA_HOME:-}" ] && [ -f "${JAVA_HOME}/bin/java" ]; then
        JAVA_VERSION="$("${JAVA_HOME}/bin/java" -version 2>&1 | head -1)"
        log_info "Java Version: $JAVA_VERSION"
    else
        JAVA_VERSION="$(java -version 2>&1 | head -1 || echo "NOT FOUND")"
        log_info "Java Version (system): $JAVA_VERSION"
    fi
} || log_warn "Java discovery failed"

# ============================================================================
# 4. OCI CLI CONFIGURATION
# ============================================================================
log_section "4. OCI CLI CONFIGURATION"

{
    log_info "--- OCI CLI Version ---"
    OCI_VERSION="$(oci --version 2>&1 || echo "NOT INSTALLED")"
    log_info "OCI CLI: $OCI_VERSION"

    OCI_CONFIG_EXP="${OCI_CONFIG_PATH/#\~/$HOME}"
    log_raw ""
    log_info "--- OCI Config File (masked): $OCI_CONFIG_EXP ---"
    if [ -f "$OCI_CONFIG_EXP" ]; then
        sed 's/\(key_file\s*=\s*\).*/\1<MASKED>/' "$OCI_CONFIG_EXP" | tee -a "$REPORT_TXT"

        log_raw ""
        log_info "--- OCI API Key File Check ---"
        OCI_KEY_PATH="$(grep 'key_file' "$OCI_CONFIG_EXP" 2>/dev/null | head -1 | sed 's/.*=\s*//' | tr -d ' ')"
        OCI_KEY_EXP="${OCI_KEY_PATH/#\~/$HOME}"
        if [ -f "$OCI_KEY_EXP" ]; then
            log_info "OCI API key exists: $OCI_KEY_EXP"
        else
            log_warn "OCI API key NOT FOUND: $OCI_KEY_EXP"
        fi
    else
        log_warn "OCI config not found at: $OCI_CONFIG_EXP"
    fi
} || log_warn "OCI CLI discovery failed"

# ============================================================================
# 5. SSH CONFIGURATION
# ============================================================================
log_section "5. SSH CONFIGURATION"

{
    log_info "--- SSH keys in ~/.ssh/ ---"
    SSH_DIR="$HOME/.ssh"
    if [ -d "$SSH_DIR" ]; then
        ls -la "$SSH_DIR/" 2>/dev/null | tee -a "$REPORT_TXT"
    else
        log_warn "SSH directory $SSH_DIR does not exist"
    fi

    log_raw ""
    log_info "--- Checking for .pem and .key files ---"
    PEM_FILES="$(find "$SSH_DIR" -name '*.pem' -o -name '*.key' 2>/dev/null | tr '\n' ' ')"
    if [ -n "$PEM_FILES" ]; then
        log_info "Found SSH key files: $PEM_FILES"
    else
        log_warn "No .pem or .key files found in $SSH_DIR"
    fi
} || log_warn "SSH discovery failed"

# ============================================================================
# 6. NETWORK CONNECTIVITY TO SOURCE AND TARGET
# ============================================================================
log_section "6. NETWORK CONNECTIVITY TESTS"

SOURCE_PING="SKIPPED"
TARGET_PING="SKIPPED"
SOURCE_PORT22="SKIPPED"
SOURCE_PORT1521="SKIPPED"
TARGET_PORT22="SKIPPED"
TARGET_PORT1521="SKIPPED"

run_connectivity_tests() {
    local host="$1"
    local label="$2"
    local ping_var="$3"
    local port22_var="$4"
    local port1521_var="$5"

    log_raw ""
    log_info "--- Testing: $label ($host) ---"

    # Ping test (10 pings, capture latency)
    local ping_result
    ping_result="$(ping -c 10 "$host" 2>&1)"
    if echo "$ping_result" | grep -q 'rtt\|round-trip'; then
        local rtt_line
        rtt_line="$(echo "$ping_result" | grep 'rtt\|round-trip')"
        local avg_rtt
        avg_rtt="$(echo "$rtt_line" | grep -oP '[0-9]+\.[0-9]+' | sed -n '2p')"
        eval "$ping_var='SUCCESS (avg ${avg_rtt}ms)'"
        log_info "Ping $label: SUCCESS â€” RTT stats: $rtt_line"
        if awk "BEGIN { exit (${avg_rtt:-0} <= 10) }"; then
            log_warn "Average RTT ${avg_rtt}ms > 10ms â€” high latency may impact ZDM online migration"
        fi
    else
        eval "$ping_var='FAILED'"
        log_warn "Ping $label: FAILED"
        log_raw "$ping_result"
    fi

    # Port tests
    for port in 22 1521; do
        local port_result="FAILED"
        if timeout 5 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
            port_result="OPEN"
            log_info "Port $port ($label): OPEN"
        else
            log_warn "Port $port ($label): BLOCKED or unreachable"
        fi
        if [ "$port" = "22" ]; then
            eval "$port22_var='$port_result'"
        else
            eval "$port1521_var='$port_result'"
        fi
    done
}

if [ -n "${SOURCE_HOST:-}" ]; then
    run_connectivity_tests "$SOURCE_HOST" "SOURCE" "SOURCE_PING" "SOURCE_PORT22" "SOURCE_PORT1521" || \
        log_warn "Source connectivity tests encountered errors"
else
    log_info "SOURCE_HOST not provided â€” skipping source connectivity tests"
fi

if [ -n "${TARGET_HOST:-}" ]; then
    run_connectivity_tests "$TARGET_HOST" "TARGET" "TARGET_PING" "TARGET_PORT22" "TARGET_PORT1521" || \
        log_warn "Target connectivity tests encountered errors"
else
    log_info "TARGET_HOST not provided â€” skipping target connectivity tests"
fi

# ============================================================================
# 7. NETWORK CONFIGURATION
# ============================================================================
log_section "7. NETWORK CONFIGURATION"

{
    log_info "--- IP Addresses ---"
    ip addr show 2>/dev/null | grep 'inet ' | tee -a "$REPORT_TXT"

    log_raw ""
    log_info "--- Routing Table ---"
    ip route 2>/dev/null | tee -a "$REPORT_TXT" || route -n 2>/dev/null | tee -a "$REPORT_TXT" || true

    log_raw ""
    log_info "--- DNS Configuration (/etc/resolv.conf) ---"
    cat /etc/resolv.conf 2>/dev/null | tee -a "$REPORT_TXT" || log_warn "Could not read /etc/resolv.conf"
} || log_warn "Network configuration discovery failed"

# ============================================================================
# 8. ZDM LOGS
# ============================================================================
log_section "8. ZDM LOGS"

{
    if [ -n "${ZDM_HOME:-}" ]; then
        ZDM_LOG_DIR=""
        for logdir in "${ZDM_HOME}/../../zdmbase/chkbase/zdm" "${ZDM_HOME}/../zdmbase/chkbase/zdm" \
                      "/u01/app/zdmbase/chkbase/zdm" "/home/${ZDM_USER}/zdmbase/chkbase/zdm"; do
            if sudo test -d "$logdir" 2>/dev/null; then
                ZDM_LOG_DIR="$logdir"
                break
            fi
        done

        if [ -n "$ZDM_LOG_DIR" ]; then
            log_info "ZDM Log Directory: $ZDM_LOG_DIR"
            sudo ls -lt "$ZDM_LOG_DIR" 2>/dev/null | head -20 | tee -a "$REPORT_TXT"
        else
            log_info "ZDM log directory not found in standard locations"
        fi
    else
        log_info "ZDM_HOME not set â€” skipping log discovery"
    fi
} || log_warn "ZDM log discovery failed"

# ============================================================================
# 9. CREDENTIAL / PASSWORD FILES
# ============================================================================
log_section "9. CREDENTIAL FILE SEARCH"

{
    log_info "--- Searching for password/credential files ---"
    sudo find /home/$ZDM_USER /home/$(whoami) -maxdepth 3 \
        \( -name '*.pwd' -o -name '*.cred' -o -name 'wallet*' -o -name 'tde*' \) \
        -not -path '*/.git/*' 2>/dev/null | head -20 | tee -a "$REPORT_TXT" || true
    log_info "(NOTE: Discovery does not display file contents â€” security-sensitive)"
} || log_warn "Credential file search failed"

# ============================================================================
# WRITE JSON SUMMARY
# ============================================================================
log_section "WRITING JSON SUMMARY"

{
# Safely substitute ZDM_OPATCH_PATCHES newlines for JSON
ZDM_OPATCH_CLEAN="${ZDM_OPATCH_PATCHES//$'\n'/ | }"
ZDM_OPATCH_CLEAN="${ZDM_OPATCH_CLEAN//\"/\'}"

cat > "$REPORT_JSON" <<JSON
{
  "report_type": "server_discovery",
  "generated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "run_by": "$(whoami)",
  "hostname": "$(hostname -f 2>/dev/null || hostname)",
  "timestamp": "$TIMESTAMP",
  "zdm_installation": {
    "zdm_home": "${ZDM_HOME:-NOT FOUND}",
    "zdm_version": "${ZDM_VERSION:-UNDETERMINED}",
    "zdm_opatch_patches": "${ZDM_OPATCH_CLEAN:-N/A}",
    "zdm_service_running": $([ "$ZDM_SERVICE_STATUS" = "RUNNING" ] && echo true || echo false),
    "zdmcli_functional": $([ "$ZDM_CLI_STATUS" = "FOUND and EXECUTABLE" ] && echo true || echo false)
  },
  "java": {
    "java_home": "${JAVA_HOME:-NOT DETECTED}",
    "java_version": "${JAVA_VERSION:-NOT DETECTED}"
  },
  "oci": {
    "oci_cli_version": "${OCI_VERSION:-NOT INSTALLED}",
    "oci_config_path": "${OCI_CONFIG_EXP:-}"
  },
  "connectivity": {
    "source_host": "${SOURCE_HOST:-not_provided}",
    "source_ping": "${SOURCE_PING}",
    "source_port_22": "${SOURCE_PORT22}",
    "source_port_1521": "${SOURCE_PORT1521}",
    "target_host": "${TARGET_HOST:-not_provided}",
    "target_ping": "${TARGET_PING}",
    "target_port_22": "${TARGET_PORT22}",
    "target_port_1521": "${TARGET_PORT1521}"
  },
  "output_files": {
    "text_report": "$REPORT_TXT",
    "json_summary": "$REPORT_JSON"
  }
}
JSON
    log_info "JSON summary written to: $REPORT_JSON"
} || log_warn "Failed to write JSON summary"

# ============================================================================
# COMPLETION
# ============================================================================
log_raw ""
log_raw "============================================================"
log_raw "  ZDM Server Discovery COMPLETE"
log_raw "  Text report : $REPORT_TXT"
log_raw "  JSON summary: $REPORT_JSON"
log_raw "  Completed   : $(date)"
log_raw "============================================================"

echo ""
echo "[DONE] ZDM server discovery complete."
echo "  Text : $REPORT_TXT"
echo "  JSON : $REPORT_JSON"
