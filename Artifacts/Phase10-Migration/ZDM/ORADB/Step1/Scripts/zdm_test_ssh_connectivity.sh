#!/usr/bin/env bash
# =============================================================================
# zdm_test_ssh_connectivity.sh
# ZDM Migration — Step 1: Test SSH Connectivity
# Project   : ORADB
# Run as    : zdmuser on the ZDM server
# =============================================================================
# Validates SSH key files and end-to-end SSH connectivity to the source and
# target database hosts before running the longer Step 2 discovery flow.
#
# Usage:
#   chmod +x zdm_test_ssh_connectivity.sh
#   ./zdm_test_ssh_connectivity.sh
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration (sourced from zdm-env.md)
# ---------------------------------------------------------------------------
PROJECT_NAME="ORADB"

SOURCE_HOST="10.1.0.11"
TARGET_HOST="10.0.1.160"

SOURCE_SSH_USER="azureuser"
TARGET_SSH_USER="opc"

SOURCE_SSH_KEY="${HOME}/.ssh/odaa.pem"
TARGET_SSH_KEY="${HOME}/.ssh/odaa.pem"

# ---------------------------------------------------------------------------
# Output paths
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Resolve the project root relative to Scripts/ → Step1/ → ORADB/ → ZDM/ → Phase10-Migration/ → Artifacts/ → root
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../../../.." && pwd)"

VALIDATION_DIR="${PROJECT_ROOT}/Artifacts/Phase10-Migration/ZDM/${PROJECT_NAME}/Step1/Validation"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_MD="${VALIDATION_DIR}/ssh-connectivity-report-${TIMESTAMP}.md"
REPORT_JSON="${VALIDATION_DIR}/ssh-connectivity-report-${TIMESTAMP}.json"

# ---------------------------------------------------------------------------
# SSH options
# ---------------------------------------------------------------------------
SSH_OPTS=(
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=10
  -o PasswordAuthentication=no
  -i
)

# ---------------------------------------------------------------------------
# Tracking
# ---------------------------------------------------------------------------
FAILURES=()
declare -A RESULTS   # key → "PASS" | "FAIL: <reason>"

# ---------------------------------------------------------------------------
# Helper: log to stdout
# ---------------------------------------------------------------------------
log() { echo "[$(date +%H:%M:%S)] $*"; }

# ---------------------------------------------------------------------------
# Helper: check key file
# ---------------------------------------------------------------------------
check_key() {
  local label="$1"
  local keyfile="$2"

  log "Checking key: ${label} → ${keyfile}"

  # Expand ~ manually in case the script is sourced non-interactively
  keyfile="${keyfile/#\~/${HOME}}"

  # Existence + readability
  if [[ ! -f "${keyfile}" ]]; then
    RESULTS["${label}_key_exists"]="FAIL: file not found: ${keyfile}"
    FAILURES+=("${label} key not found: ${keyfile}")
    return 1
  fi
  RESULTS["${label}_key_exists"]="PASS"

  if [[ ! -r "${keyfile}" ]]; then
    RESULTS["${label}_key_readable"]="FAIL: file not readable: ${keyfile}"
    FAILURES+=("${label} key not readable: ${keyfile}")
    return 1
  fi
  RESULTS["${label}_key_readable"]="PASS"

  # Permissions: must be 600 or stricter (400, 000)
  local perms
  perms="$(stat -c "%a" "${keyfile}" 2>/dev/null || stat -f "%OLp" "${keyfile}" 2>/dev/null)"
  if [[ "${perms}" =~ ^[0-9]+$ ]]; then
    # Group and other bits must be 0 (last two digits 00)
    local go_bits="${perms: -2}"
    if [[ "${go_bits}" != "00" ]]; then
      RESULTS["${label}_key_perms"]="FAIL: permissions ${perms} (expected 600 or stricter)"
      FAILURES+=("${label} key has insecure permissions ${perms}: ${keyfile}")
      return 1
    fi
    RESULTS["${label}_key_perms"]="PASS (${perms})"
  else
    RESULTS["${label}_key_perms"]="WARN: could not determine permissions"
  fi

  return 0
}

# ---------------------------------------------------------------------------
# Helper: test SSH connectivity
# ---------------------------------------------------------------------------
check_ssh() {
  local label="$1"
  local user="$2"
  local host="$3"
  local keyfile="$4"

  keyfile="${keyfile/#\~/${HOME}}"

  log "Testing SSH: ${user}@${host} using ${keyfile}"

  local ssh_out
  if ssh_out="$(ssh "${SSH_OPTS[@]}" "${keyfile}" "${user}@${host}" hostname 2>&1)"; then
    RESULTS["${label}_ssh"]="PASS (hostname: ${ssh_out})"
    log "  OK — remote hostname: ${ssh_out}"
  else
    RESULTS["${label}_ssh"]="FAIL: ${ssh_out}"
    FAILURES+=("${label} SSH failed to ${user}@${host}: ${ssh_out}")
    log "  FAIL — ${ssh_out}"
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  log "=================================================="
  log " ZDM Step 1 — SSH Connectivity Test"
  log " Project : ${PROJECT_NAME}"
  log " Run as  : $(whoami)"
  log " Date    : $(date)"
  log "=================================================="

  mkdir -p "${VALIDATION_DIR}"

  # --- Key file checks -------------------------------------------------------
  log ""
  log "--- Key File Validation ---"
  check_key "source" "${SOURCE_SSH_KEY}" || true
  check_key "target" "${TARGET_SSH_KEY}" || true

  # --- SSH connectivity checks -----------------------------------------------
  log ""
  log "--- SSH Connectivity Validation ---"

  # Only test SSH if key checks passed (key must exist + be readable)
  if [[ "${RESULTS[source_key_exists]:-}" == "PASS" && "${RESULTS[source_key_readable]:-}" == "PASS" ]]; then
    check_ssh "source" "${SOURCE_SSH_USER}" "${SOURCE_HOST}" "${SOURCE_SSH_KEY}"
  else
    RESULTS["source_ssh"]="SKIP: key unavailable"
    FAILURES+=("source SSH skipped — key not available")
  fi

  if [[ "${RESULTS[target_key_exists]:-}" == "PASS" && "${RESULTS[target_key_readable]:-}" == "PASS" ]]; then
    check_ssh "target" "${TARGET_SSH_USER}" "${TARGET_HOST}" "${TARGET_SSH_KEY}"
  else
    RESULTS["target_ssh"]="SKIP: key unavailable"
    FAILURES+=("target SSH skipped — key not available")
  fi

  # --- Write reports ---------------------------------------------------------
  write_markdown_report
  write_json_report

  log ""
  log "Reports written to: ${VALIDATION_DIR}"
  log "  MD  : ${REPORT_MD}"
  log "  JSON: ${REPORT_JSON}"

  # --- Summary ---------------------------------------------------------------
  log ""
  if [[ ${#FAILURES[@]} -eq 0 ]]; then
    log "=================================================="
    log " RESULT: ALL CHECKS PASSED"
    log "=================================================="
    exit 0
  else
    log "=================================================="
    log " RESULT: ${#FAILURES[@]} CHECK(S) FAILED"
    for f in "${FAILURES[@]}"; do
      log "  [FAIL] ${f}"
    done
    log "=================================================="
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Write Markdown report
# ---------------------------------------------------------------------------
write_markdown_report() {
  local overall="PASS"
  [[ ${#FAILURES[@]} -gt 0 ]] && overall="FAIL"

  cat > "${REPORT_MD}" <<EOF
# SSH Connectivity Report — ${PROJECT_NAME}

| Field        | Value                        |
|--------------|------------------------------|
| Project      | ${PROJECT_NAME}              |
| Generated    | $(date)                      |
| Run by       | $(whoami)@$(hostname)        |
| Overall      | **${overall}**               |

---

## Source Host

| Check              | Result                                          |
|--------------------|-------------------------------------------------|
| Host               | ${SOURCE_HOST}                                  |
| User               | ${SOURCE_SSH_USER}                              |
| Key file           | ${SOURCE_SSH_KEY}                               |
| Key exists         | ${RESULTS[source_key_exists]:-N/A}              |
| Key readable       | ${RESULTS[source_key_readable]:-N/A}            |
| Key permissions    | ${RESULTS[source_key_perms]:-N/A}               |
| SSH connectivity   | ${RESULTS[source_ssh]:-N/A}                     |

---

## Target Host

| Check              | Result                                          |
|--------------------|-------------------------------------------------|
| Host               | ${TARGET_HOST}                                  |
| User               | ${TARGET_SSH_USER}                              |
| Key file           | ${TARGET_SSH_KEY}                               |
| Key exists         | ${RESULTS[target_key_exists]:-N/A}              |
| Key readable       | ${RESULTS[target_key_readable]:-N/A}            |
| Key permissions    | ${RESULTS[target_key_perms]:-N/A}               |
| SSH connectivity   | ${RESULTS[target_ssh]:-N/A}                     |

---

## Failures

EOF

  if [[ ${#FAILURES[@]} -eq 0 ]]; then
    echo "None — all checks passed." >> "${REPORT_MD}"
  else
    for f in "${FAILURES[@]}"; do
      echo "- ${f}" >> "${REPORT_MD}"
    done
  fi

  cat >> "${REPORT_MD}" <<EOF

---
*Generated by zdm_test_ssh_connectivity.sh*
EOF
}

# ---------------------------------------------------------------------------
# Write JSON report
# ---------------------------------------------------------------------------
write_json_report() {
  local overall="PASS"
  [[ ${#FAILURES[@]} -gt 0 ]] && overall="FAIL"

  # Escape a string for JSON
  json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

  # Build failures array
  local failures_json="[]"
  if [[ ${#FAILURES[@]} -gt 0 ]]; then
    failures_json="["
    local first=true
    for f in "${FAILURES[@]}"; do
      [[ "${first}" == "true" ]] && first=false || failures_json+=","
      failures_json+="\"$(json_escape "${f}")\""
    done
    failures_json+="]"
  fi

  cat > "${REPORT_JSON}" <<EOF
{
  "project": "$(json_escape "${PROJECT_NAME}")",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "run_by": "$(json_escape "$(whoami)@$(hostname)")",
  "overall": "$(json_escape "${overall}")",
  "source": {
    "host": "$(json_escape "${SOURCE_HOST}")",
    "user": "$(json_escape "${SOURCE_SSH_USER}")",
    "key_file": "$(json_escape "${SOURCE_SSH_KEY}")",
    "key_exists": "$(json_escape "${RESULTS[source_key_exists]:-N/A}")",
    "key_readable": "$(json_escape "${RESULTS[source_key_readable]:-N/A}")",
    "key_perms": "$(json_escape "${RESULTS[source_key_perms]:-N/A}")",
    "ssh_connectivity": "$(json_escape "${RESULTS[source_ssh]:-N/A}")"
  },
  "target": {
    "host": "$(json_escape "${TARGET_HOST}")",
    "user": "$(json_escape "${TARGET_SSH_USER}")",
    "key_file": "$(json_escape "${TARGET_SSH_KEY}")",
    "key_exists": "$(json_escape "${RESULTS[target_key_exists]:-N/A}")",
    "key_readable": "$(json_escape "${RESULTS[target_key_readable]:-N/A}")",
    "key_perms": "$(json_escape "${RESULTS[target_key_perms]:-N/A}")",
    "ssh_connectivity": "$(json_escape "${RESULTS[target_ssh]:-N/A}")"
  },
  "failures": ${failures_json}
}
EOF
}

main "$@"
