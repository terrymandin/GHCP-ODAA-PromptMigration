#!/bin/bash
# =============================================================================
# zdm_server_discovery.sh
# Phase 10 — ZDM Migration · Step 2: ZDM Server Discovery
#
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration
#
# Gathers ZDM installation details, OCI CLI configuration, SSH credentials,
# network settings, and connectivity from the ZDM server itself.
# Runs locally on the ZDM box as zdmuser (called by zdm_orchestrate_discovery.sh,
# which passes SOURCE_HOST and TARGET_HOST as environment variables).
#
# Output (current working directory):
#   zdm_server_discovery_<hostname>_<timestamp>.txt   — human-readable report
#   zdm_server_discovery_<hostname>_<timestamp>.json  — machine-parseable summary
#
# Usage (standalone / manual):
#   sudo su - zdmuser
#   SOURCE_HOST=10.1.0.11 TARGET_HOST=10.0.1.160 bash zdm_server_discovery.sh
# =============================================================================

# ---------------------------------------------------------------------------
# User guard — must run as zdmuser
# ---------------------------------------------------------------------------
CURRENT_USER="$(whoami)"
if [ "$CURRENT_USER" != "${ZDM_USER:-zdmuser}" ]; then
    echo "[ERROR] This script must run as '${ZDM_USER:-zdmuser}'. Currently running as '${CURRENT_USER}'."
    echo "        Switch to the correct user first: sudo su - ${ZDM_USER:-zdmuser}"
    exit 1
fi

HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_TXT="./zdm_server_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
REPORT_JSON="./zdm_server_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

# Environment variables — passed by orchestrator
ZDM_USER="${ZDM_USER:-zdmuser}"
SOURCE_HOST="${SOURCE_HOST:-}"
TARGET_HOST="${TARGET_HOST:-}"

# Tracked warnings for JSON summary
WARNINGS=()

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log_section() { printf '\n## %s\n\n' "$1" | tee -a "$REPORT_TXT"; }
log_info()    { printf '  %s\n' "$*"    | tee -a "$REPORT_TXT"; }
log_raw()     { printf '%s\n'   "$*"   >> "$REPORT_TXT"; }
add_warning() { WARNINGS+=("$*"); log_info "WARNING: $*"; }

# ---------------------------------------------------------------------------
# Initialize report header
# ---------------------------------------------------------------------------
{
    printf '# ZDM Server Discovery Report\n\n'
    printf '| Field | Value |\n'
    printf '|-------|-------|\n'
    printf '| Generated | %s |\n' "$(date)"
    printf '| Hostname  | %s |\n' "${HOSTNAME_SHORT}"
    printf '| Run by    | %s |\n' "${CURRENT_USER}"
    printf '\n'
} > "$REPORT_TXT"

# ---------------------------------------------------------------------------
# Section 1: OS Information
# ---------------------------------------------------------------------------
log_section "OS Information"
log_info "Hostname (FQDN): $(hostname -f 2>/dev/null || hostname)"
log_info "Hostname (short): ${HOSTNAME_SHORT}"
log_info "Current user: $(whoami)"
log_info "Home directory: ${HOME}"
log_info ""
log_info "OS Release:"
{ cat /etc/os-release 2>/dev/null || cat /etc/redhat-release 2>/dev/null || uname -a; } \
    | tee -a "$REPORT_TXT"
log_info ""
log_info "Kernel: $(uname -r)"

log_info ""
log_info "Disk Space (df -h) — warn if any filesystem < 50 GB free:"
df -h 2>/dev/null | tee -a "$REPORT_TXT"

# Check for filesystems with < 50 GB free
while IFS= read -r line; do
    avail_col="$(echo "${line}" | awk '{print $4}')"
    mount_col="$(echo "${line}" | awk '{print $6}')"
    # Convert to GB for comparison (handles G, M, T suffixes)
    avail_num="$(echo "${avail_col}" | grep -oP '\d+\.?\d*')"
    avail_unit="$(echo "${avail_col}" | grep -oP '[GMTK]' || echo 'B')"
    if [[ -n "${avail_num}" ]]; then
        avail_gb=0
        case "${avail_unit}" in
            T) avail_gb="$(echo "${avail_num} * 1024" | bc 2>/dev/null || echo 9999)" ;;
            G) avail_gb="${avail_num%.*}" ;;
            M) avail_gb=0 ;;
            K) avail_gb=0 ;;
        esac
        if [[ "${avail_gb}" -lt 50 ]] 2>/dev/null; then
            add_warning "Filesystem ${mount_col} has only ${avail_col} free (< 50 GB threshold)"
        fi
    fi
done < <(df -h 2>/dev/null | tail -n +2)

# ---------------------------------------------------------------------------
# Section 2: ZDM Installation
# ---------------------------------------------------------------------------
log_section "ZDM Installation"

# Detect ZDM_HOME
ZDM_HOME="${ZDM_HOME:-}"
if [[ -z "${ZDM_HOME}" ]]; then
    # 1. Login environment
    ZDM_HOME="$(env | grep -i '^zdm_home=' | cut -d= -f2 | head -1)"
fi
if [[ -z "${ZDM_HOME}" ]]; then
    # 2. Common home paths
    for p in \
        /u01/app/zdmhome /opt/zdm/zdmhome /home/zdmuser/zdmhome \
        /u01/app/oracle/zdm /opt/oracle/zdm; do
        [[ -d "${p}" && -f "${p}/bin/zdmcli" ]] && { ZDM_HOME="${p}"; break; }
    done
fi
if [[ -z "${ZDM_HOME}" ]]; then
    # 3. Common system paths
    for p in /etc/zdm /var/zdm; do
        [[ -d "${p}" ]] && { ZDM_HOME="${p}"; break; }
    done
fi
if [[ -z "${ZDM_HOME}" ]]; then
    # 4. find (limited depth)
    ZDM_HOME="$(find /u01 /opt /home 2>/dev/null -maxdepth 6 -name 'zdmcli' -type f \
        | head -1 | xargs -I{} dirname {} | xargs -I{} dirname {} 2>/dev/null)"
fi

export ZDM_HOME
log_info "ZDM_HOME: ${ZDM_HOME:-NOT DETECTED}"

if [[ -z "${ZDM_HOME}" ]]; then
    add_warning "ZDM_HOME could not be detected. ZDM installation checks skipped."
else
    # ZDM version detection
    log_info ""
    log_info "ZDM Version:"
    ZDM_VERSION=""

    # 1. Oracle Inventory XML
    if [[ -z "${ZDM_VERSION}" ]] && [[ -f /etc/oraInst.loc ]]; then
        inv_loc="$(grep -i 'inventory_loc' /etc/oraInst.loc | cut -d= -f2 | tr -d ' ')"
        if [[ -n "${inv_loc}" && -f "${inv_loc}/ContentsXML/inventory.xml" ]]; then
            ZDM_VERSION="$(grep -i 'zdm\|zero.*data' "${inv_loc}/ContentsXML/inventory.xml" 2>/dev/null \
                | grep -oP 'VER="[^"]+"' | head -1)"
            [[ -n "${ZDM_VERSION}" ]] && log_info "  (from Oracle Inventory): ${ZDM_VERSION}"
        fi
    fi

    # 2. OPatch lspatches
    if [[ -z "${ZDM_VERSION}" ]] && [[ -f "${ZDM_HOME}/OPatch/opatch" ]]; then
        ZDM_VERSION="$("${ZDM_HOME}/OPatch/opatch" lspatches 2>/dev/null | head -5)"
        [[ -n "${ZDM_VERSION}" ]] && log_info "  (from OPatch): ${ZDM_VERSION}"
    fi

    # 3. version.txt / build files
    if [[ -z "${ZDM_VERSION}" ]]; then
        for vfile in \
            "${ZDM_HOME}/zdm/version.txt" \
            "${ZDM_HOME}/lib/version.txt" \
            "${ZDM_HOME}/VERSION.txt"; do
            if [[ -f "${vfile}" ]]; then
                ZDM_VERSION="$(cat "${vfile}" 2>/dev/null | head -3)"
                log_info "  (from ${vfile}): ${ZDM_VERSION}"
                break
            fi
        done
    fi

    # 4. zdmbase build files
    if [[ -z "${ZDM_VERSION}" ]]; then
        for bfile in "${ZDM_HOME}"/zdmbase/build*.txt "${ZDM_HOME}"/zdmbase/*.version 2>/dev/null; do
            [[ -f "${bfile}" ]] && {
                ZDM_VERSION="$(cat "${bfile}" | head -3)"
                log_info "  (from ${bfile}): ${ZDM_VERSION}"
                break
            }
        done
    fi

    # 5. Derive from path
    if [[ -z "${ZDM_VERSION}" ]]; then
        ZDM_VERSION="$(echo "${ZDM_HOME}" | grep -oP '\d+\.\d+[\.\d]*' | head -1)"
        [[ -n "${ZDM_VERSION}" ]] && log_info "  (derived from path): ${ZDM_VERSION}"
    fi

    [[ -z "${ZDM_VERSION}" ]] && add_warning "Could not determine ZDM version."

    # zdmcli existence
    log_info ""
    log_info "zdmcli existence and executability:"
    if [[ -f "${ZDM_HOME}/bin/zdmcli" ]]; then
        ls -la "${ZDM_HOME}/bin/zdmcli" | tee -a "$REPORT_TXT"
    else
        add_warning "zdmcli not found at ${ZDM_HOME}/bin/zdmcli"
        log_info "(zdmcli not found at ${ZDM_HOME}/bin/zdmcli)"
    fi

    # ZDM service status
    log_info ""
    log_info "ZDM Service Status:"
    "${ZDM_HOME}/bin/zdmservice" status 2>&1 | tee -a "$REPORT_TXT" \
        || log_info "(zdmservice status failed)"

    # Active migration jobs
    log_info ""
    log_info "Active Migration Jobs (zdmcli query job):"
    "${ZDM_HOME}/bin/zdmcli" query job 2>&1 | tee -a "$REPORT_TXT" \
        || log_info "(zdmcli query job unavailable or no jobs)"

    # Response file templates
    log_info ""
    log_info "Response File Templates:"
    TEMPLATE_DIR="${ZDM_HOME}/rhp/zdm/template"
    if [[ -d "${TEMPLATE_DIR}" ]]; then
        ls -la "${TEMPLATE_DIR}/" 2>/dev/null | tee -a "$REPORT_TXT"
    else
        log_info "(Template directory not found: ${TEMPLATE_DIR})"
    fi
fi

# ---------------------------------------------------------------------------
# Section 3: Java
# ---------------------------------------------------------------------------
log_section "Java"
JAVA_CMD=""
# Check ZDM bundled JDK first
if [[ -n "${ZDM_HOME}" && -f "${ZDM_HOME}/jdk/bin/java" ]]; then
    JAVA_CMD="${ZDM_HOME}/jdk/bin/java"
    log_info "Found ZDM bundled JDK: ${JAVA_CMD}"
elif command -v java &>/dev/null; then
    JAVA_CMD="java"
fi

if [[ -n "${JAVA_CMD}" ]]; then
    "${JAVA_CMD}" -version 2>&1 | tee -a "$REPORT_TXT"
    log_info "JAVA_HOME: ${JAVA_HOME:-not set}"
else
    add_warning "Java not found in ZDM JDK or PATH."
    log_info "(Java not found)"
fi

# ---------------------------------------------------------------------------
# Section 4: OCI CLI
# ---------------------------------------------------------------------------
log_section "OCI CLI"
if command -v oci &>/dev/null; then
    oci --version 2>&1 | tee -a "$REPORT_TXT"
    log_info ""
    log_info "OCI config location and masked contents:"
    OCI_CONFIG="${OCI_CLI_CONFIG_FILE:-${HOME}/.oci/config}"
    if [[ -f "${OCI_CONFIG}" ]]; then
        log_info "Config file: ${OCI_CONFIG}"
        grep -E '^\[|^fingerprint|^region|^tenancy|^user' "${OCI_CONFIG}" 2>/dev/null \
            | tee -a "$REPORT_TXT"
    else
        add_warning "OCI config file not found: ${OCI_CONFIG}"
        log_info "(OCI config not found at ${OCI_CONFIG})"
    fi

    log_info ""
    log_info "OCI API key file:"
    OCI_KEY_PATH="$(grep '^key_file' "${OCI_CONFIG:-/dev/null}" 2>/dev/null \
        | head -1 | cut -d= -f2 | tr -d ' ')"
    if [[ -n "${OCI_KEY_PATH}" && -f "${OCI_KEY_PATH}" ]]; then
        ls -la "${OCI_KEY_PATH}" | tee -a "$REPORT_TXT"
    else
        add_warning "OCI API key file not found (key_file=${OCI_KEY_PATH:-not configured})"
        log_info "(OCI API key not found: ${OCI_KEY_PATH:-not configured})"
    fi

    log_info ""
    log_info "OCI configured profiles and regions:"
    grep -E '^\[|^region' "${OCI_CONFIG:-/dev/null}" 2>/dev/null | tee -a "$REPORT_TXT"

    log_info ""
    log_info "OCI connectivity test (region list — timeout 30s):"
    timeout 30 oci iam region list --output table 2>&1 | head -20 | tee -a "$REPORT_TXT" \
        || add_warning "OCI CLI connectivity test failed"
else
    add_warning "OCI CLI (oci) not found in PATH."
    log_info "(OCI CLI not installed or not on PATH)"
fi

# ---------------------------------------------------------------------------
# Section 5: SSH Keys and Credentials
# ---------------------------------------------------------------------------
log_section "SSH Keys and Credentials"
log_info "Files in ~/.ssh/:"
ls -la "${HOME}/.ssh/" 2>/dev/null | tee -a "$REPORT_TXT" \
    || log_info "(~/.ssh/ not found or inaccessible)"

PEM_COUNT="$(find "${HOME}/.ssh/" -name '*.pem' -o -name '*.key' 2>/dev/null | wc -l)"
log_info ""
log_info "PEM/key files found in ~/.ssh/: ${PEM_COUNT}"
if [[ "${PEM_COUNT}" -eq 0 ]]; then
    add_warning "No .pem or .key files found in ~/.ssh/ — SSH keys may not be in place for source/target connectivity."
fi

log_info ""
log_info "Credential/password files in home directory:"
find "${HOME}" -maxdepth 3 \( -name '*.pwd' -o -name '*cred*' -o -name '*password*' \) 2>/dev/null \
    | tee -a "$REPORT_TXT" || log_info "(none found)"

# ---------------------------------------------------------------------------
# Section 6: Network
# ---------------------------------------------------------------------------
log_section "Network"
log_info "IP Addresses:"
ip addr show 2>/dev/null | grep 'inet ' | awk '{printf "    %s\n",$2}' | tee -a "$REPORT_TXT" \
    || ifconfig 2>/dev/null | grep 'inet ' | awk '{printf "    %s\n",$2}' | tee -a "$REPORT_TXT"

log_info ""
log_info "Routing Table:"
ip route 2>/dev/null | tee -a "$REPORT_TXT" || route -n 2>/dev/null | tee -a "$REPORT_TXT"

log_info ""
log_info "DNS Configuration (/etc/resolv.conf):"
cat /etc/resolv.conf 2>/dev/null | tee -a "$REPORT_TXT" || log_info "(not found)"

# ---------------------------------------------------------------------------
# Section 7: Connectivity Tests (SOURCE and TARGET)
# ---------------------------------------------------------------------------
log_section "Connectivity Tests"

if [[ -z "${SOURCE_HOST}" && -z "${TARGET_HOST}" ]]; then
    log_info "(SOURCE_HOST and TARGET_HOST not set — connectivity tests skipped)"
    log_info "  To run manually: SOURCE_HOST=<ip> TARGET_HOST=<ip> bash zdm_server_discovery.sh"
fi

run_connectivity_test() {
    local label="$1"
    local host="$2"

    if [[ -z "${host}" ]]; then
        log_info "  ${label}: (host not set — skipped)"
        return
    fi

    log_info ""
    log_info "--- ${label} (${host}) ---"

    # Ping test
    log_info "  Ping (10 packets):"
    ping_output="$(ping -c 10 "${host}" 2>&1)"
    ping_exit=$?
    echo "${ping_output}" | tee -a "$REPORT_TXT"

    if [[ ${ping_exit} -ne 0 ]]; then
        add_warning "Ping to ${label} (${host}) failed"
    else
        avg_rtt="$(echo "${ping_output}" | grep -oP 'min/avg/max.*?= \S+' | grep -oP '\d+\.\d+' | sed -n '2p')"
        if [[ -n "${avg_rtt}" ]]; then
            avg_int="${avg_rtt%.*}"
            if [[ "${avg_int}" -gt 10 ]] 2>/dev/null; then
                add_warning "Ping to ${label} (${host}): avg RTT ${avg_rtt} ms exceeds 10 ms threshold"
            else
                log_info "  Avg RTT: ${avg_rtt} ms (within 10 ms threshold)"
            fi
        fi
    fi

    # Port tests via /dev/tcp
    for port in 22 1521; do
        port_result="$(timeout 5 bash -c "echo >/dev/tcp/${host}/${port}" 2>&1)"
        port_exit=$?
        if [[ ${port_exit} -eq 0 ]]; then
            log_info "  Port ${port}: OPEN"
        else
            log_info "  Port ${port}: CLOSED or FILTERED"
            add_warning "Port ${port} on ${label} (${host}) is not reachable"
        fi
    done
}

run_connectivity_test "SOURCE" "${SOURCE_HOST}"
run_connectivity_test "TARGET" "${TARGET_HOST}"

# ---------------------------------------------------------------------------
# Build JSON summary
# ---------------------------------------------------------------------------
WARNINGS_JSON="["
for i in "${!WARNINGS[@]}"; do
    [[ $i -gt 0 ]] && WARNINGS_JSON+=","
    escaped="${WARNINGS[$i]//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    WARNINGS_JSON+="\"${escaped}\""
done
WARNINGS_JSON+="]"

STATUS="success"
[[ ${#WARNINGS[@]} -gt 0 ]] && STATUS="partial"

cat > "${REPORT_JSON}" << JSONEOF
{
  "report":       "server-discovery",
  "phase":        "Phase10-ZDM-Step2",
  "generated":    "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "run_by":       "${CURRENT_USER}",
  "hostname":     "${HOSTNAME_SHORT}",
  "status":       "${STATUS}",
  "zdm_home":     "${ZDM_HOME:-}",
  "zdm_version":  "${ZDM_VERSION:-}",
  "source_host":  "${SOURCE_HOST:-}",
  "target_host":  "${TARGET_HOST:-}",
  "warnings":     ${WARNINGS_JSON},
  "report_txt":   "${REPORT_TXT}"
}
JSONEOF

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "  ZDM Server Discovery — Complete"
echo "  Hostname : ${HOSTNAME_SHORT}"
echo "  Status   : ${STATUS}"
echo "  Warnings : ${#WARNINGS[@]}"
echo "  Reports  :"
echo "    ${REPORT_TXT}"
echo "    ${REPORT_JSON}"
echo "============================================================"
