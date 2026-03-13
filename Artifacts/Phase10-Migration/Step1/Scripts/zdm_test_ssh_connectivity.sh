#!/usr/bin/env bash
# =============================================================================
# zdm_test_ssh_connectivity.sh
# Phase 10 — ZDM Migration · Step 1: Test SSH Connectivity
#
# Validates SSH access from the ZDM server (running as zdmuser) to:
#   • SOURCE host  (10.1.0.11  / azureuser / ~/.ssh/odaa.pem)
#   • TARGET host  (10.0.1.160 / opc        / ~/.ssh/odaa.pem)
#
# Outputs:
#   Artifacts/Phase10-Migration/Step1/Validation/
#     ssh-connectivity-report-<TIMESTAMP>.md
#     ssh-connectivity-report-<TIMESTAMP>.json
#
# Usage:
#   chmod +x zdm_test_ssh_connectivity.sh
#   ./zdm_test_ssh_connectivity.sh
#
# Run as: zdmuser on the ZDM server
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration  (from zdm-env.md)
# ---------------------------------------------------------------------------
SOURCE_HOST="10.1.0.11"
SOURCE_SSH_USER="azureuser"
SOURCE_SSH_KEY="${HOME}/.ssh/odaa.pem"

TARGET_HOST="10.0.1.160"
TARGET_SSH_USER="opc"
TARGET_SSH_KEY="${HOME}/.ssh/odaa.pem"

# ---------------------------------------------------------------------------
# Output paths
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATION_DIR="${SCRIPT_DIR}/../Validation"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_MD="${VALIDATION_DIR}/ssh-connectivity-report-${TIMESTAMP}.md"
REPORT_JSON="${VALIDATION_DIR}/ssh-connectivity-report-${TIMESTAMP}.json"

mkdir -p "${VALIDATION_DIR}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
PASS="PASS"
FAIL="FAIL"

check_key_permissions() {
    local key_path="$1"
    if [[ ! -f "${key_path}" ]]; then
        echo "NOT_FOUND"
        return
    fi
    local perms
    perms="$(stat -c '%a' "${key_path}" 2>/dev/null || stat -f '%A' "${key_path}" 2>/dev/null)"
    if [[ "${perms}" == "600" ]]; then
        echo "600_OK"
    else
        echo "BAD_PERMS:${perms}"
    fi
}

test_ssh() {
    local label="$1"
    local host="$2"
    local user="$3"
    local key="$4"

    echo ""
    echo "─────────────────────────────────────────────"
    echo "  Testing SSH: ${label}"
    echo "  Host : ${host}"
    echo "  User : ${user}"
    echo "  Key  : ${key}"
    echo "─────────────────────────────────────────────"

    # 1. Check key file & permissions
    local key_status
    key_status="$(check_key_permissions "${key}")"
    if [[ "${key_status}" == "NOT_FOUND" ]]; then
        echo "  [FAIL] SSH key not found: ${key}"
        echo "${FAIL}"
        return
    fi
    if [[ "${key_status}" != "600_OK" ]]; then
        echo "  [WARN] SSH key permissions are ${key_status#BAD_PERMS:} (expected 600). Attempting anyway."
    fi

    # 2. Test connectivity: run 'hostname' on the remote host
    local remote_hostname=""
    local ssh_exit=0
    remote_hostname="$(
        ssh -o StrictHostKeyChecking=no \
            -o BatchMode=yes \
            -o ConnectTimeout=10 \
            -i "${key}" \
            "${user}@${host}" \
            "hostname" 2>&1
    )" || ssh_exit=$?

    if [[ ${ssh_exit} -eq 0 ]]; then
        echo "  [PASS] SSH connection successful. Remote hostname: ${remote_hostname}"
        echo "${PASS}:${remote_hostname}:${key_status}"
    else
        echo "  [FAIL] SSH connection failed (exit ${ssh_exit}): ${remote_hostname}"
        echo "${FAIL}:exit_${ssh_exit}:${key_status}"
    fi
}

# ---------------------------------------------------------------------------
# Run checks
# ---------------------------------------------------------------------------
echo "============================================================"
echo "  ZDM Step 1 — SSH Connectivity Test"
echo "  Started : $(date)"
echo "  Run as  : $(whoami)@$(hostname)"
echo "============================================================"

SOURCE_RESULT="$(test_ssh "SOURCE" "${SOURCE_HOST}" "${SOURCE_SSH_USER}" "${SOURCE_SSH_KEY}")"
TARGET_RESULT="$(test_ssh "TARGET" "${TARGET_HOST}" "${TARGET_SSH_USER}" "${TARGET_SSH_KEY}")"

# Parse last line of each result block as the status token
SOURCE_STATUS="$(echo "${SOURCE_RESULT}" | tail -1)"
TARGET_STATUS="$(echo "${TARGET_RESULT}" | tail -1)"

SOURCE_PASS="false"; [[ "${SOURCE_STATUS}" == PASS* ]] && SOURCE_PASS="true"
TARGET_PASS="false"; [[ "${TARGET_STATUS}" == PASS* ]] && TARGET_PASS="true"

SOURCE_HOSTNAME=""; TARGET_HOSTNAME=""
if [[ "${SOURCE_PASS}" == "true" ]]; then
    SOURCE_HOSTNAME="$(echo "${SOURCE_STATUS}" | cut -d: -f2)"
fi
if [[ "${TARGET_PASS}" == "true" ]]; then
    TARGET_HOSTNAME="$(echo "${TARGET_STATUS}" | cut -d: -f2)"
fi

OVERALL="PASS"
if [[ "${SOURCE_PASS}" != "true" || "${TARGET_PASS}" != "true" ]]; then
    OVERALL="FAIL"
fi

# ---------------------------------------------------------------------------
# Write Markdown report
# ---------------------------------------------------------------------------
cat > "${REPORT_MD}" <<EOF
# SSH Connectivity Report — Phase 10 Step 1

| Field | Value |
|-------|-------|
| **Generated** | $(date) |
| **Run by** | $(whoami)@$(hostname) |
| **Overall result** | **${OVERALL}** |

---

## Source Host

| Property | Value |
|----------|-------|
| Host | \`${SOURCE_HOST}\` |
| SSH User | \`${SOURCE_SSH_USER}\` |
| SSH Key | \`${SOURCE_SSH_KEY}\` |
| Result | **$([ "${SOURCE_PASS}" == "true" ] && echo "✅ PASS" || echo "❌ FAIL")** |
| Remote Hostname | \`${SOURCE_HOSTNAME:-N/A}\` |

## Target Host

| Property | Value |
|----------|-------|
| Host | \`${TARGET_HOST}\` |
| SSH User | \`${TARGET_SSH_USER}\` |
| SSH Key | \`${TARGET_SSH_KEY}\` |
| Result | **$([ "${TARGET_PASS}" == "true" ] && echo "✅ PASS" || echo "❌ FAIL")** |
| Remote Hostname | \`${TARGET_HOSTNAME:-N/A}\` |

---

## Remediation Steps (if any check failed)

1. **Key not found** — Verify the key file exists at the path above under the \`zdmuser\` home on the ZDM server.
2. **Bad permissions** — Run: \`chmod 600 ~/.ssh/odaa.pem\`
3. **Connection refused / timeout** — Confirm the host's security group / firewall allows TCP/22 inbound from the ZDM server IP.
4. **Host key verification** — If \`known_hosts\` is causing issues, run:
   \`\`\`bash
   ssh-keyscan -H ${SOURCE_HOST} >> ~/.ssh/known_hosts
   ssh-keyscan -H ${TARGET_HOST} >> ~/.ssh/known_hosts
   \`\`\`
5. **Permission denied** — Confirm the correct user (\`${SOURCE_SSH_USER}\` / \`${TARGET_SSH_USER}\`) is appended to \`~/.ssh/authorized_keys\` on each host.

---

## Next Step

$(if [[ "${OVERALL}" == "PASS" ]]; then
  echo "SSH connectivity is confirmed for both hosts. Proceed to:"
  echo ""
  echo "> \`@Phase10-ZDM-Step2-Generate-Discovery-Scripts\`"
else
  echo "One or more SSH checks **failed**. Resolve the issues above before proceeding to Step 2."
fi)
EOF

# ---------------------------------------------------------------------------
# Write JSON report
# ---------------------------------------------------------------------------
cat > "${REPORT_JSON}" <<EOF
{
  "report": "ssh-connectivity",
  "phase": "Phase10-ZDM-Step1",
  "generated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "run_by": "$(whoami)",
  "host": "$(hostname)",
  "overall": "${OVERALL}",
  "source": {
    "host": "${SOURCE_HOST}",
    "ssh_user": "${SOURCE_SSH_USER}",
    "ssh_key": "${SOURCE_SSH_KEY}",
    "result": "$([ "${SOURCE_PASS}" == "true" ] && echo "PASS" || echo "FAIL")",
    "remote_hostname": "${SOURCE_HOSTNAME:-null}"
  },
  "target": {
    "host": "${TARGET_HOST}",
    "ssh_user": "${TARGET_SSH_USER}",
    "ssh_key": "${TARGET_SSH_KEY}",
    "result": "$([ "${TARGET_PASS}" == "true" ] && echo "PASS" || echo "FAIL")",
    "remote_hostname": "${TARGET_HOSTNAME:-null}"
  }
}
EOF

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "  Results"
echo "  Source (${SOURCE_HOST}) : $([ "${SOURCE_PASS}" == "true" ] && echo "PASS" || echo "FAIL")"
echo "  Target (${TARGET_HOST}) : $([ "${TARGET_PASS}" == "true" ] && echo "PASS" || echo "FAIL")"
echo "  Overall             : ${OVERALL}"
echo "============================================================"
echo "  Reports written to:"
echo "    ${REPORT_MD}"
echo "    ${REPORT_JSON}"
echo "============================================================"

if [[ "${OVERALL}" == "PASS" ]]; then
    echo ""
    echo "  Both SSH checks passed. Ready for Step 2."
    exit 0
else
    echo ""
    echo "  One or more SSH checks FAILED. See report for remediation."
    exit 1
fi
