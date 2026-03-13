#!/usr/bin/env bash
# =============================================================================
# zdm_server_discovery.sh
# Phase 10 — ZDM Migration · Step 2: ZDM Server Discovery
#
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration
#
# Runs locally on the ZDM server as zdmuser (or a user with sudo).
# Discovers: OS, ZDM installation & version, Java, OCI CLI, SSH config,
# credential files, network (including connectivity tests to source/target),
# and ZDM logs.
#
# Outputs (written to current working directory):
#   zdm_server_discovery_<hostname>_<timestamp>.txt
#   zdm_server_discovery_<hostname>_<timestamp>.json
#
# Usage (typically invoked by zdm_orchestrate_discovery.sh):
#   SOURCE_HOST=<src> TARGET_HOST=<tgt> bash zdm_server_discovery.sh
#
# Overrides (optional environment variables):
#   ZDM_HOME         - Override auto-detected ZDM home
#   JAVA_HOME        - Override auto-detected Java home
#   ZDM_USER         - ZDM software owner (default: zdmuser)
#   SOURCE_HOST      - Source hostname for connectivity tests
#   TARGET_HOST      - Target hostname for connectivity tests
# =============================================================================

# DO NOT use set -e globally — allows individual section failures without aborting
set -uo pipefail

# ---------------------------------------------------------------------------
# Configuration defaults
# ---------------------------------------------------------------------------
ZDM_USER="${ZDM_USER:-zdmuser}"
SOURCE_HOST="${SOURCE_HOST:-}"
TARGET_HOST="${TARGET_HOST:-}"

HOSTNAME_VAL="$(hostname -s 2>/dev/null || hostname)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_TXT="./zdm_server_discovery_${HOSTNAME_VAL}_${TIMESTAMP}.txt"
REPORT_JSON="./zdm_server_discovery_${HOSTNAME_VAL}_${TIMESTAMP}.json"

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log_raw() {
    local msg="$1"
    echo "$msg" | tee -a "${REPORT_TXT}"
}

log_section() {
    local title="$1"
    local line="============================================================"
    echo "" | tee -a "${REPORT_TXT}"
    echo "${line}" | tee -a "${REPORT_TXT}"
    echo "  ${title}" | tee -a "${REPORT_TXT}"
    echo "${line}" | tee -a "${REPORT_TXT}"
}

log_info() {
    log_raw "  [INFO]  $*"
}

log_warn() {
    log_raw "  [WARN]  $*"
}

log_error() {
    log_raw "  [ERROR] $*"
}

# ---------------------------------------------------------------------------
# ZDM / Java environment auto-detection
# ---------------------------------------------------------------------------
detect_zdm_env() {
    if [ -n "${ZDM_HOME:-}" ] && [ -n "${JAVA_HOME:-}" ]; then
        return 0
    fi

    # Detect ZDM_HOME
    if [ -z "${ZDM_HOME:-}" ]; then
        # Method 1: Get ZDM_HOME from zdmuser's login shell
        if id "$ZDM_USER" &>/dev/null 2>&1; then
            local zdm_home_from_user
            zdm_home_from_user=$(sudo -u "$ZDM_USER" -i bash -c 'echo $ZDM_HOME' 2>/dev/null || true)
            if [ -n "${zdm_home_from_user:-}" ] && [ -d "${zdm_home_from_user}" ] && \
               [ -f "${zdm_home_from_user}/bin/zdmcli" ]; then
                export ZDM_HOME="$zdm_home_from_user"
            fi
        fi

        # Method 2: Check zdmuser's home directory
        if [ -z "${ZDM_HOME:-}" ]; then
            local zdm_user_home
            zdm_user_home=$(eval echo "~${ZDM_USER}" 2>/dev/null || echo "/home/${ZDM_USER}")
            for subdir in zdmhome zdm app/zdmhome; do
                local candidate="${zdm_user_home}/${subdir}"
                if sudo test -d "$candidate" 2>/dev/null && sudo test -f "$candidate/bin/zdmcli" 2>/dev/null; then
                    export ZDM_HOME="$candidate"
                    break
                fi
            done
        fi

        # Method 3: Check common system paths
        if [ -z "${ZDM_HOME:-}" ]; then
            for path in /u01/app/zdmhome /u01/zdm /u01/app/zdm /opt/zdm \
                        /home/zdmuser/zdmhome /home/zdmuser/zdm ~/zdmhome ~/zdm "$HOME/zdmhome"; do
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
            zdmcli_path=$(sudo find /u01 /opt /home -name "zdmcli" -type f 2>/dev/null | head -1 || true)
            if [ -n "${zdmcli_path:-}" ]; then
                export ZDM_HOME="$(dirname "$(dirname "$zdmcli_path")")"
            fi
        fi
    fi

    # Detect JAVA_HOME
    if [ -z "${JAVA_HOME:-}" ]; then
        # Method 1: ZDM's bundled JDK
        if [ -n "${ZDM_HOME:-}" ] && [ -d "${ZDM_HOME}/jdk" ]; then
            export JAVA_HOME="${ZDM_HOME}/jdk"
        fi

        # Method 2: java alternatives
        if [ -z "${JAVA_HOME:-}" ] && command -v java >/dev/null 2>&1; then
            local java_path
            java_path=$(readlink -f "$(command -v java)" 2>/dev/null || true)
            if [ -n "${java_path:-}" ]; then
                export JAVA_HOME="${java_path%/bin/java}"
            fi
        fi

        # Method 3: Common Java paths
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

# ---------------------------------------------------------------------------
# ZDM version detection
# ---------------------------------------------------------------------------
detect_zdm_version() {
    local ZDM_VERSION=""
    local ZDM_OPATCH=""

    if [ -z "${ZDM_HOME:-}" ]; then
        echo "UNDETERMINED — ZDM_HOME not set"
        return
    fi

    # Method 1: Oracle Inventory XML
    if sudo test -f "${ZDM_HOME}/inventory/ContentsXML/comps.xml" 2>/dev/null; then
        ZDM_VERSION=$(sudo grep -oP '(?<=VER=")[0-9.]+' "${ZDM_HOME}/inventory/ContentsXML/comps.xml" 2>/dev/null | head -1 || true)
    fi

    # Method 2: OPatch
    if [ -z "${ZDM_VERSION:-}" ] && sudo test -x "${ZDM_HOME}/OPatch/opatch" 2>/dev/null; then
        ZDM_OPATCH=$(sudo -u "${ZDM_USER}" "${ZDM_HOME}/OPatch/opatch" lspatches 2>/dev/null | head -20 || true)
    fi

    # Method 3: version.txt / VERSION files
    if [ -z "${ZDM_VERSION:-}" ]; then
        for vfile in "${ZDM_HOME}/version.txt" "${ZDM_HOME}/VERSION" "${ZDM_HOME}/rhp/version.txt"; do
            if sudo test -f "$vfile" 2>/dev/null; then
                ZDM_VERSION=$(sudo cat "$vfile" 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9.]+' | head -1 || true)
                [ -n "${ZDM_VERSION:-}" ] && break
            fi
        done
    fi

    # Method 4: zdmbase log/build files
    if [ -z "${ZDM_VERSION:-}" ]; then
        for bfile in "${ZDM_HOME}/../../zdmbase/rhp/version.txt" "${ZDM_HOME}/../zdmbase/rhp/version.txt"; do
            if sudo test -f "$bfile" 2>/dev/null; then
                ZDM_VERSION=$(sudo cat "$bfile" 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9.]+' | head -1 || true)
                [ -n "${ZDM_VERSION:-}" ] && break
            fi
        done
    fi

    # Method 5: Derive from ZDM_HOME path
    if [ -z "${ZDM_VERSION:-}" ]; then
        ZDM_VERSION=$(echo "${ZDM_HOME}" | grep -oP '[0-9]+' | tail -1 || true)
        [ -n "${ZDM_VERSION:-}" ] && ZDM_VERSION="(path-derived: ${ZDM_VERSION})"
    fi

    ZDM_DETECTED_VERSION="${ZDM_VERSION:-UNDETERMINED}"
    ZDM_DETECTED_OPATCH="${ZDM_OPATCH:-N/A}"
}

# ---------------------------------------------------------------------------
# Section: OS Information
# ---------------------------------------------------------------------------
section_os() {
    log_section "OS INFORMATION"
    log_info "Hostname:          $(hostname)"
    log_info "Current User:      $(whoami)"
    log_info "OS Release:        $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"' || uname -a)"
    log_info "Kernel:            $(uname -r)"
    log_info "Date/Time:         $(date)"
    log_info "Uptime:            $(uptime)"

    log_info ""
    log_info "-- Disk Space (all mount points) --"
    df -h 2>/dev/null | tee -a "${REPORT_TXT}" || log_warn "df command failed"

    log_info ""
    log_info "-- Disk Space Warnings (< 50GB free) --"
    df -h 2>/dev/null | awk 'NR>1 {
        avail=$4
        unit=substr(avail,length(avail),1)
        val=substr(avail,1,length(avail)-1)+0
        gb=val
        if(unit=="M") gb=val/1024
        if(unit=="K") gb=val/1048576
        if(unit=="T") gb=val*1024
        if(gb < 50) printf "  [WARN]  Low disk space: %s has %s free\n", $6, avail
    }' | tee -a "${REPORT_TXT}" || true
}

# ---------------------------------------------------------------------------
# Section: ZDM Installation
# ---------------------------------------------------------------------------
section_zdm() {
    log_section "ZDM INSTALLATION"
    log_info "ZDM_HOME:          ${ZDM_HOME:-NOT DETECTED}"
    log_info "ZDM_USER:          ${ZDM_USER}"

    # Detect version
    detect_zdm_version
    log_info "ZDM Version:       ${ZDM_DETECTED_VERSION}"

    if [ -n "${ZDM_DETECTED_OPATCH:-}" ] && [ "${ZDM_DETECTED_OPATCH}" != "N/A" ]; then
        log_info ""
        log_info "-- OPatch Installed Patches --"
        echo "${ZDM_DETECTED_OPATCH}" | tee -a "${REPORT_TXT}"
    fi

    log_info ""
    log_info "-- zdmcli Functional Check --"
    if [ -n "${ZDM_HOME:-}" ] && sudo test -x "${ZDM_HOME}/bin/zdmcli" 2>/dev/null; then
        log_info "zdmcli found at: ${ZDM_HOME}/bin/zdmcli"
        ZDM_CLI_FUNCTIONAL="true"
        # Run zdmcli without args — displays help/usage if installed correctly
        if [ "$(whoami)" = "$ZDM_USER" ]; then
            "${ZDM_HOME}/bin/zdmcli" 2>&1 | head -10 | tee -a "${REPORT_TXT}" || true
        else
            sudo -u "$ZDM_USER" -E ZDM_HOME="$ZDM_HOME" "${ZDM_HOME}/bin/zdmcli" 2>&1 | \
                head -10 | tee -a "${REPORT_TXT}" || true
        fi
    else
        log_warn "zdmcli not found or not executable at ${ZDM_HOME:-UNKNOWN}/bin/zdmcli"
        ZDM_CLI_FUNCTIONAL="false"
    fi

    log_info ""
    log_info "-- ZDM Service Status --"
    if [ -n "${ZDM_HOME:-}" ] && sudo test -x "${ZDM_HOME}/bin/zdmservice" 2>/dev/null; then
        if [ "$(whoami)" = "$ZDM_USER" ]; then
            "${ZDM_HOME}/bin/zdmservice" status 2>&1 | tee -a "${REPORT_TXT}" || log_warn "zdmservice status failed"
        else
            sudo -u "$ZDM_USER" -E ZDM_HOME="$ZDM_HOME" "${ZDM_HOME}/bin/zdmservice" status 2>&1 | \
                tee -a "${REPORT_TXT}" || log_warn "zdmservice status failed"
        fi
    else
        log_warn "zdmservice not found at ${ZDM_HOME:-UNKNOWN}/bin/zdmservice"
    fi

    ZDM_SERVICE_RUNNING="false"
    if grep -q "running" "${REPORT_TXT}" 2>/dev/null; then
        ZDM_SERVICE_RUNNING="true"
    fi

    log_info ""
    log_info "-- Active Migration Jobs --"
    if [ -n "${ZDM_HOME:-}" ] && [ "${ZDM_CLI_FUNCTIONAL:-false}" = "true" ]; then
        if [ "$(whoami)" = "$ZDM_USER" ]; then
            "${ZDM_HOME}/bin/zdmcli" query job 2>&1 | tee -a "${REPORT_TXT}" || log_warn "zdmcli query job failed"
        else
            sudo -u "$ZDM_USER" -E ZDM_HOME="$ZDM_HOME" "${ZDM_HOME}/bin/zdmcli" query job 2>&1 | \
                tee -a "${REPORT_TXT}" || log_warn "zdmcli query job failed"
        fi
    else
        log_info "zdmcli not available — skipping active jobs query"
    fi

    log_info ""
    log_info "-- ZDM Response File Templates --"
    if [ -n "${ZDM_HOME:-}" ]; then
        sudo ls "${ZDM_HOME}/rhp/zdm/template/" 2>/dev/null | tee -a "${REPORT_TXT}" || \
            log_warn "Template directory not found at ${ZDM_HOME}/rhp/zdm/template/"
    fi
}

# ---------------------------------------------------------------------------
# Section: Java Configuration
# ---------------------------------------------------------------------------
section_java() {
    log_section "JAVA CONFIGURATION"
    log_info "JAVA_HOME:         ${JAVA_HOME:-NOT DETECTED}"
    if command -v java >/dev/null 2>&1; then
        log_info "java version:"
        java -version 2>&1 | tee -a "${REPORT_TXT}" || true
    elif [ -n "${JAVA_HOME:-}" ] && [ -f "${JAVA_HOME}/bin/java" ]; then
        log_info "java version (from JAVA_HOME):"
        "${JAVA_HOME}/bin/java" -version 2>&1 | tee -a "${REPORT_TXT}" || true
    else
        log_warn "java not found in PATH or JAVA_HOME"
    fi
}

# ---------------------------------------------------------------------------
# Section: OCI CLI Configuration
# ---------------------------------------------------------------------------
section_oci() {
    log_section "OCI CLI CONFIGURATION"
    log_info "-- OCI CLI Version --"
    oci --version 2>&1 | tee -a "${REPORT_TXT}" || log_warn "OCI CLI not found or not in PATH"

    log_info ""
    log_info "-- OCI Config File --"
    local oci_config="${OCI_CONFIG_PATH:-${HOME}/.oci/config}"
    if [ -f "${oci_config}" ]; then
        log_info "OCI config found at: ${oci_config}"
        # Mask private key content and fingerprint
        sed 's/\(key_file\s*=\s*\).*/\1[MASKED]/' "${oci_config}" | \
            sed 's/\(fingerprint\s*=\s*\).*/\1[MASKED]/' | \
            tee -a "${REPORT_TXT}"
    else
        log_warn "OCI config not found at ${oci_config}"
    fi

    log_info ""
    log_info "-- OCI API Key Existence --"
    local oci_key="${OCI_PRIVATE_KEY_PATH:-${HOME}/.oci/oci_api_key.pem}"
    if [ -f "${oci_key}" ]; then
        log_info "OCI private key found at: ${oci_key}"
        ls -lh "${oci_key}" 2>/dev/null | tee -a "${REPORT_TXT}" || true
    else
        log_warn "OCI private key not found at ${oci_key}"
    fi

    log_info ""
    log_info "-- OCI Connectivity Test --"
    if command -v oci >/dev/null 2>&1; then
        oci iam region list --output table 2>&1 | head -10 | tee -a "${REPORT_TXT}" || \
            log_warn "OCI connectivity test failed"
    fi
}

# ---------------------------------------------------------------------------
# Section: SSH Configuration
# ---------------------------------------------------------------------------
section_ssh() {
    log_section "SSH CONFIGURATION"
    log_info "-- SSH Directory (~/.ssh) --"
    if [ -d "${HOME}/.ssh" ]; then
        ls -la "${HOME}/.ssh/" 2>/dev/null | tee -a "${REPORT_TXT}" || true

        log_info ""
        log_info "-- SSH Key Files --"
        find "${HOME}/.ssh" -name "*.pem" -o -name "*.key" -o -name "id_rsa" -o -name "id_ed25519" 2>/dev/null | \
            while read -r kf; do
                local perms
                perms=$(stat -c '%a' "$kf" 2>/dev/null || stat -f '%A' "$kf" 2>/dev/null || echo "unknown")
                log_info "  Key: ${kf}  Permissions: ${perms}"
            done | tee -a "${REPORT_TXT}" || true
    else
        log_warn "~/.ssh directory not found for $(whoami)"
    fi
}

# ---------------------------------------------------------------------------
# Section: Credential Files
# ---------------------------------------------------------------------------
section_credentials() {
    log_section "CREDENTIAL FILES"
    log_info "-- Searching for credential/password files --"
    find "${HOME}" -maxdepth 4 \
        \( -name "*.wallet" -o -name "cwallet.sso" -o -name "ewallet.p12" \
           -o -name "*.sso" -o -name "*.p12" \) 2>/dev/null | \
        tee -a "${REPORT_TXT}" || true
}

# ---------------------------------------------------------------------------
# Section: Network Configuration
# ---------------------------------------------------------------------------
section_network() {
    log_section "NETWORK CONFIGURATION"
    log_info "-- IP Addresses --"
    ip addr show 2>/dev/null | grep 'inet ' | awk '{print "  " $2 " dev " $NF}' | \
        tee -a "${REPORT_TXT}" || \
        ifconfig 2>/dev/null | grep 'inet ' | tee -a "${REPORT_TXT}" || \
        log_warn "Could not retrieve IP addresses"

    log_info ""
    log_info "-- Default Route --"
    ip route show default 2>/dev/null | tee -a "${REPORT_TXT}" || \
        route -n 2>/dev/null | head -5 | tee -a "${REPORT_TXT}" || \
        log_warn "Could not retrieve routing table"

    log_info ""
    log_info "-- DNS Configuration --"
    cat /etc/resolv.conf 2>/dev/null | tee -a "${REPORT_TXT}" || log_warn "/etc/resolv.conf not found"

    # ---------------------------------------------------------------------------
    # Connectivity tests to source and target (only when hosts are provided)
    # ---------------------------------------------------------------------------
    log_info ""
    log_section "NETWORK CONNECTIVITY TESTS"

    if [ -n "${SOURCE_HOST:-}" ]; then
        log_info "-- Source Host: ${SOURCE_HOST} --"
        # Ping test (10 packets for latency measurement)
        local ping_result
        ping_result=$(ping -c 10 "$SOURCE_HOST" 2>&1 || true)
        echo "${ping_result}" | tee -a "${REPORT_TXT}" || true
        local avg_rtt
        avg_rtt=$(echo "${ping_result}" | grep -oP 'avg.*?(\d+\.\d+)/\K\d+\.\d+' 2>/dev/null | head -1 || \
                  echo "${ping_result}" | grep 'rtt\|round-trip' | grep -oP '\d+\.\d+' | awk -F'/' 'NR==1{print $2}' || \
                  echo "N/A")
        if echo "${ping_result}" | grep -q "0% packet loss" 2>/dev/null || \
           echo "${ping_result}" | grep -q "0 packets lost" 2>/dev/null; then
            log_info "Source ping: SUCCESS (avg RTT: ${avg_rtt} ms)"
            SOURCE_PING_STATUS="SUCCESS"
            SOURCE_AVG_RTT="${avg_rtt}"
            # Warn on high latency
            if [ "${avg_rtt}" != "N/A" ]; then
                local rtt_int
                rtt_int=$(echo "${avg_rtt}" | cut -d. -f1)
                [ "${rtt_int}" -gt 10 ] 2>/dev/null && \
                    log_warn "Source avg RTT ${avg_rtt}ms > 10ms — high latency may impact ZDM online migration performance"
            fi
        else
            log_warn "Source ping: FAILED or partial packet loss"
            SOURCE_PING_STATUS="FAILED"
            SOURCE_AVG_RTT="N/A"
        fi

        # Port tests
        for port in 22 1521; do
            if timeout 5 bash -c "echo >/dev/tcp/${SOURCE_HOST}/${port}" 2>/dev/null; then
                log_info "Source port ${port}: OPEN"
            else
                log_warn "Source port ${port}: BLOCKED or unreachable (timeout 5s)"
            fi
        done
    else
        log_info "SOURCE_HOST not provided — skipping source connectivity tests"
        SOURCE_PING_STATUS="SKIPPED"
        SOURCE_AVG_RTT="N/A"
    fi

    log_info ""
    if [ -n "${TARGET_HOST:-}" ]; then
        log_info "-- Target Host: ${TARGET_HOST} --"
        local ping_result_t
        ping_result_t=$(ping -c 10 "$TARGET_HOST" 2>&1 || true)
        echo "${ping_result_t}" | tee -a "${REPORT_TXT}" || true
        local avg_rtt_t
        avg_rtt_t=$(echo "${ping_result_t}" | grep 'rtt\|round-trip' | grep -oP '\d+\.\d+' | awk -F'/' 'NR==1{print $2}' || echo "N/A")
        if echo "${ping_result_t}" | grep -q "0% packet loss" 2>/dev/null || \
           echo "${ping_result_t}" | grep -q "0 packets lost" 2>/dev/null; then
            log_info "Target ping: SUCCESS (avg RTT: ${avg_rtt_t} ms)"
            TARGET_PING_STATUS="SUCCESS"
            TARGET_AVG_RTT="${avg_rtt_t}"
            if [ "${avg_rtt_t}" != "N/A" ]; then
                local rtt_int_t
                rtt_int_t=$(echo "${avg_rtt_t}" | cut -d. -f1)
                [ "${rtt_int_t}" -gt 10 ] 2>/dev/null && \
                    log_warn "Target avg RTT ${avg_rtt_t}ms > 10ms — high latency may impact ZDM online migration performance"
            fi
        else
            log_warn "Target ping: FAILED or partial packet loss"
            TARGET_PING_STATUS="FAILED"
            TARGET_AVG_RTT="N/A"
        fi

        for port in 22 1521; do
            if timeout 5 bash -c "echo >/dev/tcp/${TARGET_HOST}/${port}" 2>/dev/null; then
                log_info "Target port ${port}: OPEN"
            else
                log_warn "Target port ${port}: BLOCKED or unreachable (timeout 5s)"
            fi
        done
    else
        log_info "TARGET_HOST not provided — skipping target connectivity tests"
        TARGET_PING_STATUS="SKIPPED"
        TARGET_AVG_RTT="N/A"
    fi
}

# ---------------------------------------------------------------------------
# Section: ZDM Logs
# ---------------------------------------------------------------------------
section_zdm_logs() {
    log_section "ZDM LOGS"
    if [ -n "${ZDM_HOME:-}" ]; then
        local zdm_base
        zdm_base=$(dirname "$(dirname "${ZDM_HOME}")" 2>/dev/null || echo "")
        local log_dirs=("${ZDM_HOME}/log" "${zdm_base}/zdmbase/crsdata" "/u01/app/zdmbase/crsdata")

        for log_dir in "${log_dirs[@]}"; do
            if sudo test -d "$log_dir" 2>/dev/null; then
                log_info "Log directory found: ${log_dir}"
                sudo ls -lt "$log_dir" 2>/dev/null | head -10 | tee -a "${REPORT_TXT}" || true
            fi
        done
    else
        log_warn "ZDM_HOME not set — cannot locate ZDM log directory"
    fi
}

# ---------------------------------------------------------------------------
# Build JSON summary
# ---------------------------------------------------------------------------
build_json() {
    cat > "${REPORT_JSON}" <<JSONEOF
{
  "report_type": "zdm_server_discovery",
  "hostname": "${HOSTNAME_VAL}",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "run_as_user": "$(whoami)",
  "zdm_installation": {
    "zdm_home": "${ZDM_HOME:-N/A}",
    "zdm_version": "${ZDM_DETECTED_VERSION:-UNDETERMINED}",
    "zdm_opatch_patches": "${ZDM_DETECTED_OPATCH:-N/A}",
    "zdm_service_running": ${ZDM_SERVICE_RUNNING:-false},
    "zdmcli_functional": ${ZDM_CLI_FUNCTIONAL:-false}
  },
  "java": {
    "java_home": "${JAVA_HOME:-N/A}"
  },
  "network_connectivity": {
    "source_host": "${SOURCE_HOST:-N/A}",
    "source_ping": "${SOURCE_PING_STATUS:-SKIPPED}",
    "source_avg_rtt_ms": "${SOURCE_AVG_RTT:-N/A}",
    "target_host": "${TARGET_HOST:-N/A}",
    "target_ping": "${TARGET_PING_STATUS:-SKIPPED}",
    "target_avg_rtt_ms": "${TARGET_AVG_RTT:-N/A}"
  },
  "report_files": {
    "text_report": "${REPORT_TXT}",
    "json_summary": "${REPORT_JSON}"
  }
}
JSONEOF
    log_info "JSON summary written to: ${REPORT_JSON}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    echo "# ZDM Server Discovery Report" > "${REPORT_TXT}"
    echo "# Generated: $(date)" >> "${REPORT_TXT}"
    echo "# Host: $(hostname)" >> "${REPORT_TXT}"
    echo "# Run as: $(whoami)" >> "${REPORT_TXT}"

    log_section "ZDM SERVER DISCOVERY — Phase 10 Step 2"
    log_info "Started:      $(date)"
    log_info "Run as:       $(whoami)@$(hostname)"
    log_info "ZDM User:     ${ZDM_USER}"
    log_info "Source Host:  ${SOURCE_HOST:-not provided}"
    log_info "Target Host:  ${TARGET_HOST:-not provided}"

    # Warn if not running as zdmuser
    if [ "$(whoami)" != "$ZDM_USER" ]; then
        log_warn "Running as $(whoami), not ${ZDM_USER}. Some ZDM paths may resolve differently."
        log_warn "SSH keys must be in /home/${ZDM_USER}/.ssh/ with permissions 600."
    fi

    detect_zdm_env

    # Apply explicit overrides (highest priority)
    [ -n "${ZDM_REMOTE_ZDM_HOME:-}" ]  && export ZDM_HOME="$ZDM_REMOTE_ZDM_HOME"
    [ -n "${ZDM_REMOTE_JAVA_HOME:-}" ] && export JAVA_HOME="$ZDM_REMOTE_JAVA_HOME"

    log_info "ZDM_HOME:     ${ZDM_HOME:-NOT DETECTED}"
    log_info "JAVA_HOME:    ${JAVA_HOME:-NOT DETECTED}"

    section_os          || log_warn "OS section encountered errors"
    section_zdm         || log_warn "ZDM installation section encountered errors"
    section_java        || log_warn "Java section encountered errors"
    section_oci         || log_warn "OCI CLI section encountered errors"
    section_ssh         || log_warn "SSH section encountered errors"
    section_credentials || log_warn "Credentials section encountered errors"
    section_network     || log_warn "Network section encountered errors"
    section_zdm_logs    || log_warn "ZDM logs section encountered errors"

    log_section "DISCOVERY COMPLETE"
    log_info "Finished: $(date)"
    log_info "Text report:  ${REPORT_TXT}"
    log_info "JSON summary: ${REPORT_JSON}"

    build_json
}

main "$@"
