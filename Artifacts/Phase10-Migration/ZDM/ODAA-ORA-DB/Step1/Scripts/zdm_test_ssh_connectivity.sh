#!/bin/bash
# ==============================================================================
# ZDM Step 1 — SSH Connectivity Test
# Project  : ODAA-ORA-DB
# Generated: 2026-03-16
# Run as   : zdmuser on ZDM server (10.200.1.13)
#
# Usage:
#   bash zdm_test_ssh_connectivity.sh
#
# What it does:
#   1. Checks that the zdmuser ~/.ssh directory and default identity exist
#   2. Validates SSH connectivity to SOURCE (azureuser@10.200.1.12)
#   3. Validates SSH connectivity to TARGET (opc@10.200.0.250)
#   4. Writes a Markdown + JSON report to ../Validation/
#
# Note: No -i key-file flag is used for the source/target SSH connections.
#       Public keys are already in authorized_keys on those hosts.
#       The zdmuser default identity (~/.ssh/id_rsa) provides the client key.
# ==============================================================================

set -uo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
SOURCE_HOST="10.200.1.12"
SOURCE_SSH_USER="azureuser"

TARGET_HOST="10.200.0.250"
TARGET_SSH_USER="opc"

# SSH options — non-interactive, no password, accept new host keys on first connect
SSH_OPTS=(
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=10
  -o PasswordAuthentication=no
)

# ── Output paths ───────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATION_DIR="$(dirname "$SCRIPT_DIR")/Validation"
mkdir -p "$VALIDATION_DIR"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_MD="${VALIDATION_DIR}/ssh-connectivity-report-${TIMESTAMP}.md"
REPORT_JSON="${VALIDATION_DIR}/ssh-connectivity-report-${TIMESTAMP}.json"

# ── Tracking ───────────────────────────────────────────────────────────────────
OVERALL=0

ZDM_SSH_DIR_STATUS="PASS"
ZDM_SSH_DIR_DETAIL="${HOME}/.ssh exists"

ZDM_KEY_STATUS="PASS"
ZDM_KEY_DETAIL=""

SOURCE_STATUS="FAIL"
SOURCE_DETAIL=""
SOURCE_HOSTNAME=""

TARGET_STATUS="FAIL"
TARGET_DETAIL=""
TARGET_HOSTNAME=""

# ── Banner ─────────────────────────────────────────────────────────────────────
echo "======================================================================"
echo " ZDM Step 1 — SSH Connectivity Test              ${TIMESTAMP}"
echo " Project: ODAA-ORA-DB"
echo "======================================================================"
echo ""

# ── 1. Validate ~/.ssh directory ───────────────────────────────────────────────
echo "▶ Checking ZDM server SSH setup ..."
ZDM_SSH_DIR="${HOME}/.ssh"

if [[ -d "$ZDM_SSH_DIR" ]]; then
  echo "  [OK]   ~/.ssh directory found: ${ZDM_SSH_DIR}"
  ZDM_SSH_DIR_STATUS="PASS"
  ZDM_SSH_DIR_DETAIL="${ZDM_SSH_DIR} exists"
else
  echo "  [FAIL] ~/.ssh directory not found: ${ZDM_SSH_DIR}"
  ZDM_SSH_DIR_STATUS="FAIL"
  ZDM_SSH_DIR_DETAIL="${ZDM_SSH_DIR} does not exist"
  OVERALL=1
fi

# ── 2. Validate ZDM default identity key ──────────────────────────────────────
ZDM_KEY="${HOME}/.ssh/id_rsa"

if [[ -f "$ZDM_KEY" ]]; then
  if command -v stat &>/dev/null; then
    PERMS=$(stat -c "%a" "$ZDM_KEY" 2>/dev/null || stat -f "%OLp" "$ZDM_KEY" 2>/dev/null || echo "unknown")
  else
    PERMS="unknown"
  fi

  ZDM_KEY_DETAIL="${ZDM_KEY}  permissions: ${PERMS}"

  if [[ "$PERMS" == "600" || "$PERMS" == "400" || "$PERMS" == "unknown" ]]; then
    echo "  [OK]   ZDM key: ${ZDM_KEY}  (permissions: ${PERMS})"
    ZDM_KEY_STATUS="PASS"
  else
    echo "  [WARN] ZDM key permissions are ${PERMS} — expected 600. SSH may refuse the key."
    ZDM_KEY_STATUS="WARN"
  fi
else
  echo "  [WARN] Default ZDM key not found at ${ZDM_KEY}."
  echo "         Connectivity may still succeed if an SSH agent is active."
  ZDM_KEY_STATUS="WARN"
  ZDM_KEY_DETAIL="${ZDM_KEY} not found — SSH agent or alternative key may be configured"
fi

echo ""

# ── 3. Test SSH connectivity to SOURCE ────────────────────────────────────────
echo "▶ Testing SSH to SOURCE: ${SOURCE_SSH_USER}@${SOURCE_HOST} ..."

if SOURCE_OUTPUT=$(ssh "${SSH_OPTS[@]}" "${SOURCE_SSH_USER}@${SOURCE_HOST}" hostname 2>&1); then
  SOURCE_HOSTNAME="${SOURCE_OUTPUT}"
  SOURCE_STATUS="PASS"
  SOURCE_DETAIL="hostname: ${SOURCE_HOSTNAME}"
  echo "  [PASS] Connected successfully — remote hostname: ${SOURCE_HOSTNAME}"
else
  SOURCE_STATUS="FAIL"
  SOURCE_DETAIL="${SOURCE_OUTPUT}"
  echo "  [FAIL] ${SOURCE_OUTPUT}"
  OVERALL=1
fi

echo ""

# ── 4. Test SSH connectivity to TARGET ────────────────────────────────────────
echo "▶ Testing SSH to TARGET: ${TARGET_SSH_USER}@${TARGET_HOST} ..."

if TARGET_OUTPUT=$(ssh "${SSH_OPTS[@]}" "${TARGET_SSH_USER}@${TARGET_HOST}" hostname 2>&1); then
  TARGET_HOSTNAME="${TARGET_OUTPUT}"
  TARGET_STATUS="PASS"
  TARGET_DETAIL="hostname: ${TARGET_HOSTNAME}"
  echo "  [PASS] Connected successfully — remote hostname: ${TARGET_HOSTNAME}"
else
  TARGET_STATUS="FAIL"
  TARGET_DETAIL="${TARGET_OUTPUT}"
  echo "  [FAIL] ${TARGET_OUTPUT}"
  OVERALL=1
fi

echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
echo "======================================================================"
if [[ $OVERALL -eq 0 ]]; then
  echo " RESULT: ALL CHECKS PASSED ✓"
  echo " Proceed to Step 2: @Phase10-ZDM-Step2-Generate-Discovery-Scripts"
else
  echo " RESULT: ONE OR MORE CHECKS FAILED ✗"
  echo " Resolve the failures above before continuing."
fi
echo "======================================================================"
echo ""

# ── Write Markdown report ─────────────────────────────────────────────────────
OVERALL_LABEL="ALL CHECKS PASSED"
NEXT_STEP="Proceed to **Step 2**: run \`@Phase10-ZDM-Step2-Generate-Discovery-Scripts\`."
[[ $OVERALL -ne 0 ]] && OVERALL_LABEL="ONE OR MORE CHECKS FAILED"
[[ $OVERALL -ne 0 ]] && NEXT_STEP="Resolve the failing checks above, then re-run this script."

cat > "$REPORT_MD" <<MDEOF
# SSH Connectivity Report — Step 1

| | |
|---|---|
| **Project** | ODAA-ORA-DB |
| **Timestamp** | ${TIMESTAMP} |
| **Run by** | $(whoami)@$(hostname) |
| **ZDM Server** | 10.200.1.13 |
| **Overall Result** | ${OVERALL_LABEL} |

---

## Check Results

| Check | Status | Detail |
|-------|--------|--------|
| ZDM \`~/.ssh\` directory | ${ZDM_SSH_DIR_STATUS} | ${ZDM_SSH_DIR_DETAIL} |
| ZDM identity key (\`~/.ssh/id_rsa\`) | ${ZDM_KEY_STATUS} | ${ZDM_KEY_DETAIL} |
| SOURCE SSH (\`${SOURCE_SSH_USER}@${SOURCE_HOST}\`) | ${SOURCE_STATUS} | ${SOURCE_DETAIL} |
| TARGET SSH (\`${TARGET_SSH_USER}@${TARGET_HOST}\`) | ${TARGET_STATUS} | ${TARGET_DETAIL} |

---

## SSH Options Used

\`\`\`
-o BatchMode=yes
-o StrictHostKeyChecking=accept-new
-o ConnectTimeout=10
-o PasswordAuthentication=no
\`\`\`

> **Note:** No \`-i\` key-file argument is passed to SSH for source/target connections.
> Public keys are pre-authorised in \`~/.ssh/authorized_keys\` on both hosts.

---

## Next Step

${NEXT_STEP}
MDEOF

# ── Write JSON report ─────────────────────────────────────────────────────────
OVERALL_JSON_STATUS="PASS"
[[ $OVERALL -ne 0 ]] && OVERALL_JSON_STATUS="FAIL"

# Escape any double-quotes in detail strings for valid JSON
_esc() { printf '%s' "$1" | sed 's/"/\\"/g'; }

cat > "$REPORT_JSON" <<JSONEOF
{
  "report": "ssh-connectivity-report",
  "project": "ODAA-ORA-DB",
  "timestamp": "${TIMESTAMP}",
  "run_by": "$(whoami)@$(hostname)",
  "zdm_server": "10.200.1.13",
  "overall_status": "${OVERALL_JSON_STATUS}",
  "checks": {
    "zdm_ssh_dir": {
      "path": "${HOME}/.ssh",
      "status": "${ZDM_SSH_DIR_STATUS}",
      "detail": "$(_esc "${ZDM_SSH_DIR_DETAIL}")"
    },
    "zdm_key": {
      "path": "${HOME}/.ssh/id_rsa",
      "status": "${ZDM_KEY_STATUS}",
      "detail": "$(_esc "${ZDM_KEY_DETAIL}")"
    },
    "source_ssh": {
      "host": "${SOURCE_HOST}",
      "user": "${SOURCE_SSH_USER}",
      "status": "${SOURCE_STATUS}",
      "remote_hostname": "$(_esc "${SOURCE_HOSTNAME}")",
      "detail": "$(_esc "${SOURCE_DETAIL}")"
    },
    "target_ssh": {
      "host": "${TARGET_HOST}",
      "user": "${TARGET_SSH_USER}",
      "status": "${TARGET_STATUS}",
      "remote_hostname": "$(_esc "${TARGET_HOSTNAME}")",
      "detail": "$(_esc "${TARGET_DETAIL}")"
    }
  },
  "ssh_options": {
    "BatchMode": "yes",
    "StrictHostKeyChecking": "accept-new",
    "ConnectTimeout": "10",
    "PasswordAuthentication": "no",
    "key_file": "none — public keys pre-authorised on source and target"
  }
}
JSONEOF

echo "Reports written:"
echo "  Markdown : ${REPORT_MD}"
echo "  JSON     : ${REPORT_JSON}"
echo ""

exit $OVERALL
