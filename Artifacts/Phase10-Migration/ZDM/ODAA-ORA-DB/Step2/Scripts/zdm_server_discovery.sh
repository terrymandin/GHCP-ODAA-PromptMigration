#!/bin/bash
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration
# ==============================================================================
# ZDM Step 2 — ZDM Server Discovery
# Project  : ODAA-ORA-DB
# Generated: 2026-03-16
#
# Runs LOCALLY on the ZDM server (10.200.1.13) as zdmuser.
# Never uses sudo — all ZDM commands are accessed directly as zdmuser.
#
# Environment variables (passed by orchestrator when called via it):
#   SOURCE_HOST  — source server IP for connectivity test
#   TARGET_HOST  — target server IP for connectivity test
#   ZDM_USER     — expected user (default: zdmuser)
#
# Outputs (written to CWD — orchestrator reads them in-place):
#   zdm_server_discovery_<hostname>_<timestamp>.txt
#   zdm_server_discovery_<hostname>_<timestamp>.json
# ==============================================================================

# ── User guard ────────────────────────────────────────────────────────────────
CURRENT_USER="$(whoami)"
if [ "$CURRENT_USER" != "${ZDM_USER:-zdmuser}" ]; then
    echo "[ERROR] This script must run as '${ZDM_USER:-zdmuser}'. Currently running as '${CURRENT_USER}'."
    echo "        Switch to the correct user first: sudo su - ${ZDM_USER:-zdmuser}"
    exit 1
fi

SOURCE_HOST="${SOURCE_HOST:-}"
TARGET_HOST="${TARGET_HOST:-}"
ZDM_USER="${ZDM_USER:-zdmuser}"

HOSTNAME_LOCAL="$(hostname)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OUTPUT_DIR="$(pwd)"
REPORT_TXT="${OUTPUT_DIR}/zdm_server_discovery_${HOSTNAME_LOCAL}_${TIMESTAMP}.txt"
REPORT_JSON="${OUTPUT_DIR}/zdm_server_discovery_${HOSTNAME_LOCAL}_${TIMESTAMP}.json"

WARNINGS=()
SECTION_STATUSES=()

# ── Logging ───────────────────────────────────────────────────────────────────
log_info()  { echo "[INFO]  $*" | tee -a "$REPORT_TXT"; }
log_warn()  { echo "[WARN]  $*" | tee -a "$REPORT_TXT"; WARNINGS+=("$*"); }
log_error() { echo "[ERROR] $*" | tee -a "$REPORT_TXT"; }
log_raw()   { echo "$*"         | tee -a "$REPORT_TXT"; }
section()   { log_raw ""; log_raw "$(printf '=%.0s' {1..70})"; log_raw "  $*"; log_raw "$(printf '=%.0s' {1..70})"; }

# ── Header ────────────────────────────────────────────────────────────────────
> "$REPORT_TXT"
log_raw "ZDM SERVER DISCOVERY REPORT"
log_raw "Project  : ODAA-ORA-DB"
log_raw "Host     : ${HOSTNAME_LOCAL}"
log_raw "Timestamp: ${TIMESTAMP}"
log_raw "Run by   : ${CURRENT_USER}"
log_raw "$(printf '=%.0s' {1..70})"

# ══════════════════════════════════════════════════════════════════════════════
section "1. OS INFORMATION"
# ══════════════════════════════════════════════════════════════════════════════
log_info "Hostname     : $(hostname -f 2>/dev/null || hostname)"
log_info "Current user : ${CURRENT_USER}"
log_info "Home dir     : ${HOME}"
log_raw  "IP Addresses :"
ip addr show 2>/dev/null | grep 'inet ' | awk '{print "  " $2}' | tee -a "$REPORT_TXT"
log_raw  "OS Version   :"
cat /etc/os-release 2>/dev/null | tee -a "$REPORT_TXT" || uname -a | tee -a "$REPORT_TXT"
log_raw  "Kernel       : $(uname -r)"

log_raw ""
log_raw "Disk space (warn if any filesystem < 50 GB free):"
df -h --output=source,fstype,size,avail,pcent,target 2>/dev/null | tee -a "$REPORT_TXT" || \
    df -h 2>/dev/null | tee -a "$REPORT_TXT"

# Check for < 50 GB free on any filesystem
while IFS= read -r line; do
    AVAIL_NUM=$(echo "$line" | awk '{print $4}' | sed 's/G//')
    FS_MOUNT=$(echo "$line" | awk '{print $6}')
    if [[ "$AVAIL_NUM" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        if (( $(echo "$AVAIL_NUM < 50" | bc -l 2>/dev/null || echo 0) )); then
            log_warn "Low disk space on ${FS_MOUNT}: ${AVAIL_NUM} GB free (< 50 GB threshold)"
        fi
    fi
done < <(df -h --output=avail,target 2>/dev/null | tail -n +2 | grep 'G$\|T$')

SECTION_STATUSES+=("os:success")

# ══════════════════════════════════════════════════════════════════════════════
section "2. ZDM INSTALLATION"
# ══════════════════════════════════════════════════════════════════════════════

# -- Detect ZDM_HOME --
ZDM_HOME="${ZDM_HOME:-}"

if [[ -z "$ZDM_HOME" ]]; then
    # 1. Login environment
    ZDM_HOME_LOGIN=$(bash -l -c 'echo $ZDM_HOME' 2>/dev/null)
    [[ -n "$ZDM_HOME_LOGIN" && -d "$ZDM_HOME_LOGIN" ]] && ZDM_HOME="$ZDM_HOME_LOGIN"
fi

if [[ -z "$ZDM_HOME" ]]; then
    # 2. Common home paths
    for p in /u01/app/zdmhome /u01/zdm/zdmhome /opt/zdm/zdmhome \
              /home/zdmuser/zdmhome "$HOME/zdmhome"; do
        if [[ -d "$p/bin" && -x "$p/bin/zdmcli" ]]; then
            ZDM_HOME="$p"; break
        fi
    done
fi

if [[ -z "$ZDM_HOME" ]]; then
    # 3. Common system paths
    for p in /zdm /opt/zdm /u01/app/oracle/zdmhome; do
        if [[ -d "$p/bin" && -x "$p/bin/zdmcli" ]]; then
            ZDM_HOME="$p"; break
        fi
    done
fi

if [[ -z "$ZDM_HOME" ]]; then
    # 4. find (slower, bounded)
    FOUND=$(find /u01 /opt /home/$ZDM_USER "$HOME" -maxdepth 6 -name zdmcli -type f 2>/dev/null | head -1)
    if [[ -n "$FOUND" ]]; then
        ZDM_HOME="$(dirname "$(dirname "$FOUND")")"
    fi
fi

if [[ -n "$ZDM_HOME" ]]; then
    log_info "ZDM_HOME     : $ZDM_HOME"
else
    log_warn "ZDM_HOME could not be detected — zdmcli checks will be skipped"
    ZDM_HOME=""
fi

# -- Detect ZDM version --
ZDM_VERSION="unknown"

if [[ -n "$ZDM_HOME" ]]; then
    # Priority 1: Oracle Inventory XML
    INV_XML=$(find /etc/oraInst.loc /u01 /opt -name inventory.xml -maxdepth 6 2>/dev/null | \
              xargs grep -l 'zdm\|ZDM' 2>/dev/null | head -1)
    if [[ -n "$INV_XML" ]]; then
        ZDM_VERSION_INV=$(grep -i 'zdm' "$INV_XML" 2>/dev/null | \
                          grep -o 'VERSION="[^"]*"' | head -1 | sed 's/VERSION="//;s/"//')
        [[ -n "$ZDM_VERSION_INV" ]] && ZDM_VERSION="$ZDM_VERSION_INV"
    fi

    # Priority 2: OPatch lspatches
    if [[ "$ZDM_VERSION" == "unknown" && -x "$ZDM_HOME/OPatch/opatch" ]]; then
        ZDM_VERSION_OP=$("$ZDM_HOME/OPatch/opatch" lspatches 2>/dev/null | \
                         grep -i 'zdm\|Zero Downtime' | head -1 | awk '{print $1}')
        [[ -n "$ZDM_VERSION_OP" ]] && ZDM_VERSION="opatch:$ZDM_VERSION_OP"
    fi

    # Priority 3: version.txt files
    if [[ "$ZDM_VERSION" == "unknown" ]]; then
        for vf in "$ZDM_HOME/version.txt" "$ZDM_HOME/zdm.ver" \
                  "$ZDM_HOME/rhp/zdm/lib/zdm.ver"; do
            if [[ -f "$vf" ]]; then
                ZDM_VERSION=$(head -1 "$vf" 2>/dev/null | tr -d '\n')
                break
            fi
        done
    fi

    # Priority 4: zdmbase build files
    if [[ "$ZDM_VERSION" == "unknown" ]]; then
        for bf in "$ZDM_HOME/zdmbase/version.txt" \
                  "$ZDM_HOME/zdmbase/zdm.ver"; do
            if [[ -f "$bf" ]]; then
                ZDM_VERSION=$(head -1 "$bf" 2>/dev/null | tr -d '\n')
                break
            fi
        done
    fi

    # Priority 5: derive from path
    if [[ "$ZDM_VERSION" == "unknown" ]]; then
        ZDM_VERSION_PATH=$(echo "$ZDM_HOME" | grep -o '[0-9]\{2\}[.][0-9]' | head -1)
        [[ -n "$ZDM_VERSION_PATH" ]] && ZDM_VERSION="path-derived:${ZDM_VERSION_PATH}"
    fi

    log_info "ZDM Version  : ${ZDM_VERSION}"

    # -- zdmcli existence and executability --
    log_raw ""
    log_raw "zdmcli check:"
    if [[ -x "$ZDM_HOME/bin/zdmcli" ]]; then
        log_info "zdmcli found and executable: $ZDM_HOME/bin/zdmcli"
        ls -la "$ZDM_HOME/bin/zdmcli" 2>/dev/null | tee -a "$REPORT_TXT"
    else
        log_warn "zdmcli not found or not executable at $ZDM_HOME/bin/zdmcli"
    fi

    # -- ZDM service status --
    log_raw ""
    log_raw "ZDM service status:"
    if [[ -x "$ZDM_HOME/bin/zdmservice" ]]; then
        "$ZDM_HOME/bin/zdmservice" status 2>&1 | tee -a "$REPORT_TXT"
    elif [[ -x "$ZDM_HOME/zdmbase/bin/zdmservice" ]]; then
        "$ZDM_HOME/zdmbase/bin/zdmservice" status 2>&1 | tee -a "$REPORT_TXT"
    else
        log_warn "zdmservice not found at $ZDM_HOME/bin/zdmservice — service status unavailable"
    fi

    # -- Active migration jobs --
    log_raw ""
    log_raw "Active migration jobs:"
    if [[ -x "$ZDM_HOME/bin/zdmcli" ]]; then
        "$ZDM_HOME/bin/zdmcli" query job 2>&1 | tee -a "$REPORT_TXT"
    else
        log_info "(zdmcli not available — skipping job query)"
    fi

    # -- Response file templates --
    log_raw ""
    log_raw "Response file templates:"
    TEMPLATE_DIR="$ZDM_HOME/rhp/zdm/template"
    if [[ -d "$TEMPLATE_DIR" ]]; then
        ls -la "$TEMPLATE_DIR" 2>/dev/null | tee -a "$REPORT_TXT"
    else
        log_info "(template directory not found at $TEMPLATE_DIR)"
        TEMPLATE_DIR=$(find "$ZDM_HOME" -name "*.rsp" -maxdepth 8 2>/dev/null | head -5 | \
                       xargs -I{} dirname {} | sort -u | head -1)
        if [[ -n "$TEMPLATE_DIR" ]]; then
            log_info "Templates found at: $TEMPLATE_DIR"
            ls -la "$TEMPLATE_DIR"/*.rsp 2>/dev/null | tee -a "$REPORT_TXT"
        fi
    fi

    SECTION_STATUSES+=("zdm_install:success")
else
    log_warn "Skipping ZDM installation details — ZDM_HOME not detected"
    SECTION_STATUSES+=("zdm_install:partial")
fi

# ══════════════════════════════════════════════════════════════════════════════
section "3. JAVA"
# ══════════════════════════════════════════════════════════════════════════════
log_raw "Java check:"

# Check ZDM bundled JDK first
JAVA_BIN=""
if [[ -n "$ZDM_HOME" && -x "$ZDM_HOME/jdk/bin/java" ]]; then
    JAVA_BIN="$ZDM_HOME/jdk/bin/java"
    log_info "ZDM bundled JDK: $JAVA_BIN"
elif command -v java &>/dev/null; then
    JAVA_BIN="$(command -v java)"
    log_info "System java: $JAVA_BIN"
fi

if [[ -n "$JAVA_BIN" ]]; then
    "$JAVA_BIN" -version 2>&1 | tee -a "$REPORT_TXT"
    log_info "JAVA_HOME: ${JAVA_HOME:-not set}"
else
    log_warn "No Java executable found — ZDM requires Java"
fi
SECTION_STATUSES+=("java:success")

# ══════════════════════════════════════════════════════════════════════════════
section "4. OCI CLI"
# ══════════════════════════════════════════════════════════════════════════════
log_raw "OCI CLI version:"
oci --version 2>&1 | tee -a "$REPORT_TXT" || log_warn "OCI CLI not found in PATH"

log_raw ""
log_raw "OCI config (~/.oci/config) — API key path masked:"
if [[ -f ~/.oci/config ]]; then
    while IFS= read -r line; do
        if [[ "$line" =~ ^key_file || "$line" =~ ^fingerprint ]]; then
            KEY="${line%%=*}"
            log_raw "  ${KEY} = ***MASKED***"
        else
            log_raw "  $line"
        fi
    done < ~/.oci/config
else
    log_warn "(~/.oci/config not found)"
fi

log_raw ""
log_raw "OCI API key file existence:"
OCI_KEY_PATH=$(grep 'key_file' ~/.oci/config 2>/dev/null | head -1 | awk -F= '{print $2}' | tr -d ' ')
OCI_KEY_EXPANDED="${OCI_KEY_PATH/#\~/$HOME}"
if [[ -n "$OCI_KEY_EXPANDED" ]]; then
    if [[ -f "$OCI_KEY_EXPANDED" ]]; then
        ls -la "$OCI_KEY_EXPANDED" 2>/dev/null | tee -a "$REPORT_TXT"
    else
        log_warn "OCI API key file not found: $OCI_KEY_EXPANDED"
    fi
fi

log_raw ""
log_raw "OCI connectivity test (region list):"
oci iam region list --output table 2>&1 | head -15 | tee -a "$REPORT_TXT" || \
    log_warn "OCI connectivity test failed"
SECTION_STATUSES+=("oci_cli:success")

# ══════════════════════════════════════════════════════════════════════════════
section "5. SSH KEYS AND CREDENTIALS"
# ══════════════════════════════════════════════════════════════════════════════
log_raw "~/.ssh contents:"
if [[ -d ~/.ssh ]]; then
    ls -la ~/.ssh/ 2>/dev/null | tee -a "$REPORT_TXT"
    log_raw ""
    log_raw ".pem and .key files:"
    PEM_COUNT=$(ls ~/.ssh/*.pem ~/.ssh/*.key 2>/dev/null | wc -l)
    ls -la ~/.ssh/*.pem ~/.ssh/*.key 2>/dev/null | tee -a "$REPORT_TXT" || \
        log_info "(no .pem or .key files in ~/.ssh/)"
    if [[ "${PEM_COUNT:-0}" -eq 0 ]]; then
        log_warn "No .pem or .key files found in ~/.ssh/ — ZDM migration may require SSH keys for source/target"
    fi
else
    log_warn "~/.ssh directory not found"
fi

log_raw ""
log_raw "Credential/password files in home:"
find "$HOME" -maxdepth 2 \( -name "*.pwd" -o -name "*.cred" -o -name "password*" \
    -o -name "*credentials*" \) 2>/dev/null | tee -a "$REPORT_TXT" || \
    log_info "(none found)"
SECTION_STATUSES+=("ssh_creds:success")

# ══════════════════════════════════════════════════════════════════════════════
section "6. NETWORK"
# ══════════════════════════════════════════════════════════════════════════════
log_raw "Network interfaces:"
ip addr show 2>/dev/null | tee -a "$REPORT_TXT"

log_raw ""
log_raw "Routing table:"
ip route show 2>/dev/null | tee -a "$REPORT_TXT"

log_raw ""
log_raw "DNS configuration (/etc/resolv.conf):"
cat /etc/resolv.conf 2>/dev/null | tee -a "$REPORT_TXT" || log_info "(/etc/resolv.conf not found)"
SECTION_STATUSES+=("network:success")

# ══════════════════════════════════════════════════════════════════════════════
section "7. CONNECTIVITY TESTS"
# ══════════════════════════════════════════════════════════════════════════════
run_port_test() {
    local host="$1" port="$2"
    if (echo >/dev/tcp/"$host"/"$port") 2>/dev/null; then
        log_info "  Port $port on $host: OPEN"
        return 0
    else
        log_warn "  Port $port on $host: CLOSED or UNREACHABLE"
        return 1
    fi
}

if [[ -z "$SOURCE_HOST" && -z "$TARGET_HOST" ]]; then
    log_info "SOURCE_HOST and TARGET_HOST not provided — skipping connectivity tests"
    log_info "Run with: SOURCE_HOST=<ip> TARGET_HOST=<ip> bash $0"
    SECTION_STATUSES+=("connectivity:skipped")
else
    for HOST_VAR in SOURCE TARGET; do
        HOST_IP="${SOURCE_HOST}"
        [[ "$HOST_VAR" == "TARGET" ]] && HOST_IP="${TARGET_HOST}"

        if [[ -z "$HOST_IP" ]]; then
            log_info "${HOST_VAR}_HOST not set — skipping"
            continue
        fi

        log_raw ""
        log_raw "--- ${HOST_VAR} HOST: ${HOST_IP} ---"

        # Ping test (10 packets, report min/avg/max)
        log_raw "  Ping test (10 packets):"
        PING_OUT=$(ping -c 10 -W 2 "$HOST_IP" 2>&1)
        echo "$PING_OUT" | tail -4 | tee -a "$REPORT_TXT"
        AVG_RTT=$(echo "$PING_OUT" | grep 'min/avg/max\|rtt' | \
                  grep -o '[0-9]*\.[0-9]*/[0-9]*\.[0-9]*' | awk -F/ '{print $2}' | head -1)
        if [[ -n "$AVG_RTT" ]]; then
            RTT_CHECK=$(echo "$AVG_RTT > 10" | bc -l 2>/dev/null || echo 0)
            if [[ "$RTT_CHECK" == "1" ]]; then
                log_warn "${HOST_VAR} avg RTT ${AVG_RTT} ms exceeds 10 ms threshold"
            else
                log_info "${HOST_VAR} avg RTT: ${AVG_RTT} ms (OK)"
            fi
        fi
        if ! echo "$PING_OUT" | grep -q '0% packet loss\|0 packets lost'; then
            log_warn "${HOST_VAR} ping shows packet loss — check network path"
        fi

        log_raw "  Port tests:"
        run_port_test "$HOST_IP" 22
        run_port_test "$HOST_IP" 1521
    done
    SECTION_STATUSES+=("connectivity:success")
fi

# ══════════════════════════════════════════════════════════════════════════════
section "SUMMARY"
# ══════════════════════════════════════════════════════════════════════════════
OVERALL_STATUS="success"
if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    OVERALL_STATUS="partial"
    log_raw ""
    log_raw "WARNINGS requiring attention:"
    for w in "${WARNINGS[@]}"; do
        log_raw "  [!] $w"
    done
fi
log_raw ""
log_raw "Section statuses: ${SECTION_STATUSES[*]}"
log_raw "Report: $REPORT_TXT"
log_raw "JSON  : $REPORT_JSON"

# ── JSON output ───────────────────────────────────────────────────────────────
_esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g'; }
_arr() { local out; for v in "$@"; do out+="\"$(_esc "$v")\","; done; echo "[${out%,}]"; }
WARN_JSON=$(_arr "${WARNINGS[@]+"${WARNINGS[@]}"}")

cat > "$REPORT_JSON" <<JSONEOF
{
  "report": "zdm_server_discovery",
  "project": "ODAA-ORA-DB",
  "timestamp": "${TIMESTAMP}",
  "hostname": "$(_esc "$HOSTNAME_LOCAL")",
  "run_by": "${CURRENT_USER}",
  "overall_status": "${OVERALL_STATUS}",
  "zdm": {
    "zdm_home": "$(_esc "${ZDM_HOME:-}")",
    "zdm_version": "$(_esc "${ZDM_VERSION:-unknown}")"
  },
  "connectivity": {
    "source_host": "$(_esc "${SOURCE_HOST:-}")",
    "target_host": "$(_esc "${TARGET_HOST:-}")"
  },
  "sections": $(printf '['; printf '"%s",' "${SECTION_STATUSES[@]}"; printf ']' | sed 's/,]$/]/'),
  "warnings": ${WARN_JSON},
  "report_txt": "$(_esc "$REPORT_TXT")"
}
JSONEOF

echo ""
echo "======================================================================"
echo " ZDM SERVER DISCOVERY COMPLETE — ${OVERALL_STATUS^^}"
echo " Reports: ${OUTPUT_DIR}"
echo "======================================================================"
