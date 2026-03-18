#!/bin/bash
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration
#
# zdm_server_discovery.sh
# ZDM Step 2 — ZDM Server Local Discovery
#
# Purpose  : Collect read-only diagnostics from the local ZDM server.
# Auth     : Must run as zdmuser (enforced by user guard below).
# Outputs  : zdm_server_discovery_<hostname>_<ts>.txt
#            zdm_server_discovery_<hostname>_<ts>.json
# Run on   : ZDM server directly as zdmuser.
#
# Usage:
#   sudo su - zdmuser
#   ./zdm_server_discovery.sh

set -u

# ---------------------------------------------------------------------------
# User guard — must run as zdmuser
# ---------------------------------------------------------------------------
CURRENT_USER="$(whoami)"
if [ "$CURRENT_USER" != "${ZDM_USER:-zdmuser}" ]; then
  echo "[ERROR] This script must run as '${ZDM_USER:-zdmuser}'. Currently running as '${CURRENT_USER}'."
  echo "        Switch to the correct user first: sudo su - ${ZDM_USER:-zdmuser}"
  exit 1
fi

# ---------------------------------------------------------------------------
# Configuration — override with environment variables when running standalone
# ---------------------------------------------------------------------------
ZDM_HOME="${ZDM_HOME:-/mnt/app/zdmhome}"
ZDM_USER="${ZDM_USER:-zdmuser}"
SOURCE_HOST="${SOURCE_HOST:-10.200.1.12}"
TARGET_HOST="${TARGET_HOST:-10.200.0.250}"

# ---------------------------------------------------------------------------
# Timing and output setup
# ---------------------------------------------------------------------------
ts="$(date +%Y%m%d-%H%M%S)"
run_host="$(hostname 2>/dev/null || echo unknown)"
run_user="$(id -un 2>/dev/null || echo unknown)"
output_dir="${OUTPUT_DIR:-$PWD}"
txt_report="${output_dir}/zdm_server_discovery_${run_host}_${ts}.txt"
json_report="${output_dir}/zdm_server_discovery_${run_host}_${ts}.json"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
escape_json() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\r'/}"; s="${s//$'\t'/\\t}"
  printf -- '%s' "${s}"
}

section() { printf -- '\n=== %s ===\n' "$1" | tee -a "${txt_report}"; }
emit()    { printf -- '%s\n' "$1" | tee -a "${txt_report}"; }

warnings=()
warn() { warnings+=("$1"); emit "[WARN] $1"; }

# ---------------------------------------------------------------------------
# Initialize report
# ---------------------------------------------------------------------------
mkdir -p "${output_dir}"
printf -- '# ZDM Step 2 — ZDM Server Discovery Report\n' > "${txt_report}"
printf -- 'Generated: %s\nHost: %s\nUser: %s\n' "${ts}" "${run_host}" "${run_user}" >> "${txt_report}"

# ---------------------------------------------------------------------------
# Section 1: Local system details
# ---------------------------------------------------------------------------
section "1. Local System Details"
emit "Hostname  : $(hostname -f 2>/dev/null || hostname)"
emit "OS        : $(uname -a)"
if [[ -f /etc/os-release ]]; then
  emit "OS Release:"
  cat /etc/os-release | tee -a "${txt_report}" || true
fi
emit "Kernel    : $(uname -r)"
emit "Uptime    : $(uptime 2>/dev/null || echo 'unavailable')"
emit "Current user : ${run_user}"
emit "Home directory : ${HOME}"

# ---------------------------------------------------------------------------
# Section 2: ZDM installation details
# ---------------------------------------------------------------------------
section "2. ZDM Installation Details"
emit "ZDM_HOME configured : ${ZDM_HOME}"

if [[ -d "${ZDM_HOME}" ]]; then
  emit "ZDM_HOME exists     : yes"
  ls -la "${ZDM_HOME}" 2>&1 | head -30 | tee -a "${txt_report}" || emit "(ls ZDM_HOME failed)"
else
  warn "ZDM_HOME not found at ${ZDM_HOME}"
fi

emit "--- zdmcli location and version ---"
zdmcli_path=""
for candidate in "${ZDM_HOME}/bin/zdmcli" "/opt/zdm/bin/zdmcli" "/home/${ZDM_USER}/zdmhome/bin/zdmcli"; do
  if [[ -x "${candidate}" ]]; then
    zdmcli_path="${candidate}"
    break
  fi
done

if [[ -n "${zdmcli_path}" ]]; then
  emit "zdmcli found: ${zdmcli_path}"
  "${zdmcli_path}" -version 2>&1 | tee -a "${txt_report}" || emit "(zdmcli -version failed)"
else
  warn "zdmcli not found in expected locations; check ZDM_HOME or PATH."
  which zdmcli 2>/dev/null && emit "zdmcli in PATH: $(which zdmcli)" || emit "(zdmcli not in PATH)"
fi

emit "--- ZDM home permissions ---"
if [[ -d "${ZDM_HOME}" ]]; then
  stat "${ZDM_HOME}" 2>&1 | tee -a "${txt_report}" || emit "(stat failed)"
fi

# ---------------------------------------------------------------------------
# Section 3: Capacity snapshot
# ---------------------------------------------------------------------------
section "3. Capacity Snapshot"
emit "--- Disk summary ---"
df -h 2>/dev/null | tee -a "${txt_report}" || emit "(df failed)"

emit "--- Memory summary ---"
free -h 2>/dev/null | tee -a "${txt_report}" || emit "(free failed)"

emit "--- /mnt directory (ZDM mount check) ---"
df -h /mnt 2>/dev/null | tee -a "${txt_report}" || emit "(/mnt not a separate mount)"

# ---------------------------------------------------------------------------
# Section 4: Java details
# ---------------------------------------------------------------------------
section "4. Java Details"
emit "--- Bundled JDK check (in ZDM_HOME) ---"
bundled_java=""
for jpath in "${ZDM_HOME}/jdk/bin/java" "${ZDM_HOME}/java/bin/java"; do
  if [[ -x "${jpath}" ]]; then
    bundled_java="${jpath}"
    break
  fi
done

if [[ -n "${bundled_java}" ]]; then
  emit "Bundled JDK: ${bundled_java}"
  "${bundled_java}" -version 2>&1 | tee -a "${txt_report}" || emit "(java -version failed)"
else
  emit "(Bundled JDK not found in ZDM_HOME; checking JAVA_HOME/PATH)"
fi

emit "--- JAVA_HOME ---"
emit "JAVA_HOME : ${JAVA_HOME:-<not set>}"
if [[ -n "${JAVA_HOME:-}" && -x "${JAVA_HOME}/bin/java" ]]; then
  "${JAVA_HOME}/bin/java" -version 2>&1 | tee -a "${txt_report}" || emit "(JAVA_HOME java failed)"
fi

emit "--- java in PATH ---"
java -version 2>&1 | tee -a "${txt_report}" || emit "(java not in PATH)"

# ---------------------------------------------------------------------------
# Section 5: OCI authentication configuration
# ---------------------------------------------------------------------------
section "5. OCI Authentication Configuration"
emit "(Note: OCI CLI is not required for ZDM migration execution)"

if command -v oci &>/dev/null; then
  emit "--- OCI CLI version ---"
  oci --version 2>&1 | tee -a "${txt_report}" || emit "(oci --version failed)"
  emit "--- OCI config location and profiles (masked) ---"
  if [[ -f "${HOME}/.oci/config" ]]; then
    emit "OCI config found: ${HOME}/.oci/config"
    grep -E '^\[|^region|^tenancy' "${HOME}/.oci/config" | tee -a "${txt_report}" || true
    emit "--- OCI API key presence and permissions ---"
    if grep -q 'key_file' "${HOME}/.oci/config" 2>/dev/null; then
      local key_file
      key_file=$(grep 'key_file' "${HOME}/.oci/config" | head -1 | awk -F= '{print $2}' | tr -d ' ')
      if [[ -f "${key_file}" ]]; then
        ls -lh "${key_file}" | tee -a "${txt_report}" || emit "(ls key_file failed)"
        stat -c '%a' "${key_file}" 2>/dev/null | xargs -I{} echo "Permissions: {}" | tee -a "${txt_report}" || true
      else
        warn "OCI API key file not found: ${key_file}"
      fi
    fi
  else
    emit "(~/.oci/config not found)"
  fi
else
  emit "(OCI CLI not installed)"
fi

# ---------------------------------------------------------------------------
# Section 6: SSH / credential inventory
# ---------------------------------------------------------------------------
section "6. SSH / Credential Inventory (zdmuser context)"
emit "--- ~/.ssh directory contents ---"
if [[ -d "${HOME}/.ssh" ]]; then
  ls -la "${HOME}/.ssh" 2>/dev/null | tee -a "${txt_report}" || emit "(ls .ssh failed)"
  emit "--- .pem / .key file inventory ---"
  find "${HOME}/.ssh" -name '*.pem' -o -name '*.key' 2>/dev/null | while read -r kf; do
    ls -lh "${kf}" 2>/dev/null
    local perms
    perms=$(stat -c '%a' "${kf}" 2>/dev/null || echo "?")
    emit "  ${kf}  perms=${perms}"
  done | tee -a "${txt_report}" || emit "(no .pem/.key files found)"
  emit "--- authorized_keys ---"
  if [[ -f "${HOME}/.ssh/authorized_keys" ]]; then
    wc -l "${HOME}/.ssh/authorized_keys" | tee -a "${txt_report}" || true
  else
    emit "(authorized_keys not found)"
  fi
else
  warn "${HOME}/.ssh directory not found for ${ZDM_USER}."
fi

# ---------------------------------------------------------------------------
# Section 7: Network context
# ---------------------------------------------------------------------------
section "7. Network Context"
emit "--- IP addresses ---"
ip addr 2>/dev/null | tee -a "${txt_report}" || ifconfig 2>/dev/null | tee -a "${txt_report}" || emit "(ip/ifconfig unavailable)"

emit "--- Default routing ---"
ip route 2>/dev/null | tee -a "${txt_report}" || route -n 2>/dev/null | tee -a "${txt_report}" || emit "(route unavailable)"

emit "--- DNS resolvers ---"
cat /etc/resolv.conf 2>/dev/null | tee -a "${txt_report}" || emit "(/etc/resolv.conf not found)"

# ---------------------------------------------------------------------------
# Section 8: Optional connectivity tests (ping / port)
# ---------------------------------------------------------------------------
section "8. Optional Connectivity Tests (ping / port checks)"
emit "Endpoint traceability — values used during discovery:"
emit "  SOURCE_HOST : ${SOURCE_HOST}"
emit "  TARGET_HOST : ${TARGET_HOST}"

if [[ -n "${SOURCE_HOST}" ]]; then
  emit "--- Ping source host (${SOURCE_HOST}) ---"
  ping -c 3 -W 2 "${SOURCE_HOST}" 2>&1 | tee -a "${txt_report}" || warn "Ping to SOURCE_HOST (${SOURCE_HOST}) failed."

  emit "--- Port 22 check source host ---"
  if command -v nc &>/dev/null; then
    nc -zv -w 5 "${SOURCE_HOST}" 22 2>&1 | tee -a "${txt_report}" || warn "Port 22 unreachable on SOURCE_HOST (${SOURCE_HOST})."
  elif command -v timeout &>/dev/null; then
    timeout 5 bash -c "echo >/dev/tcp/${SOURCE_HOST}/22" 2>&1 && emit "Port 22 open" || warn "Port 22 unreachable on SOURCE_HOST (${SOURCE_HOST})."
  else
    emit "(nc/timeout not available for port check)"
  fi
fi

if [[ -n "${TARGET_HOST}" ]]; then
  emit "--- Ping target host (${TARGET_HOST}) ---"
  ping -c 3 -W 2 "${TARGET_HOST}" 2>&1 | tee -a "${txt_report}" || warn "Ping to TARGET_HOST (${TARGET_HOST}) failed."

  emit "--- Port 22 check target host ---"
  if command -v nc &>/dev/null; then
    nc -zv -w 5 "${TARGET_HOST}" 22 2>&1 | tee -a "${txt_report}" || warn "Port 22 unreachable on TARGET_HOST (${TARGET_HOST})."
  elif command -v timeout &>/dev/null; then
    timeout 5 bash -c "echo >/dev/tcp/${TARGET_HOST}/22" 2>&1 && emit "Port 22 open" || warn "Port 22 unreachable on TARGET_HOST (${TARGET_HOST})."
  else
    emit "(nc/timeout not available for port check)"
  fi
fi

# ---------------------------------------------------------------------------
# Section 9: Endpoint traceability summary
# ---------------------------------------------------------------------------
section "9. Endpoint Traceability"
emit "SOURCE_HOST : ${SOURCE_HOST}"
emit "TARGET_HOST : ${TARGET_HOST}"
emit "ZDM_HOME    : ${ZDM_HOME}"
emit "ZDM_USER    : ${ZDM_USER}"

# ---------------------------------------------------------------------------
# JSON summary
# ---------------------------------------------------------------------------
overall_status="success"
[[ ${#warnings[@]} -gt 0 ]] && overall_status="partial"

warnings_json=""
for w in "${warnings[@]}"; do
  warnings_json+="\"$(escape_json "${w}")\","
done
warnings_json="${warnings_json%,}"

cat > "${json_report}" <<JSON
{
  "step": "Step2-Server-Discovery",
  "status": "${overall_status}",
  "timestamp": "${ts}",
  "host": "$(escape_json "${run_host}")",
  "run_user": "$(escape_json "${run_user}")",
  "zdm_home": "$(escape_json "${ZDM_HOME}")",
  "zdm_user": "$(escape_json "${ZDM_USER}")",
  "source_host": "$(escape_json "${SOURCE_HOST}")",
  "target_host": "$(escape_json "${TARGET_HOST}")",
  "txt_report": "$(escape_json "${txt_report}")",
  "warnings_count": ${#warnings[@]},
  "warnings": [${warnings_json}]
}
JSON

emit ""
emit "=== Discovery Complete ==="
emit "Status  : ${overall_status}"
emit "Report  : ${txt_report}"
emit "JSON    : ${json_report}"
[[ ${#warnings[@]} -gt 0 ]] && emit "Warnings: ${#warnings[@]} — review above [WARN] entries."

exit 0
