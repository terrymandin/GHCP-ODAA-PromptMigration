#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

find_repo_root() {
  local dir="$SCRIPT_DIR"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/zdm-env.md" ]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

REPO_ROOT="$(find_repo_root)"
ENV_FILE="$REPO_ROOT/zdm-env.md"
OUT_DIR="$REPO_ROOT/Artifacts/Phase10-Migration/Step4/Resolution"
mkdir -p "$OUT_DIR"

get_env_value() {
  local key="$1"
  awk -v k="$key" '
    $0 ~ "^- "k":[[:space:]]*" {
      sub("^- "k":[[:space:]]*", "", $0)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
      print
      exit
    }
  ' "$ENV_FILE"
}

is_placeholder() {
  local value="$1"
  [[ "$value" == *"<"*">"* ]]
}

TARGET_HOST="$(get_env_value TARGET_HOST)"
TARGET_SSH_USER="$(get_env_value TARGET_SSH_USER)"
TARGET_SSH_KEY="$(get_env_value TARGET_SSH_KEY || true)"
TARGET_ORACLE_SID="$(get_env_value TARGET_ORACLE_SID || true)"
TARGET_REMOTE_ORACLE_HOME="$(get_env_value TARGET_REMOTE_ORACLE_HOME || true)"
TARGET_DATABASE_UNIQUE_NAME="$(get_env_value TARGET_DATABASE_UNIQUE_NAME || true)"

TS="$(date +%Y%m%d-%H%M%S)"
REPORT_FILE="$OUT_DIR/fix-05-target-sid-pinning-report-${TS}.md"
RAW_FILE="$OUT_DIR/fix-05-target-sid-pinning-raw-${TS}.txt"

FAIL_COUNT=0

{
  echo "# Fix 05 - Target SID Pinning Validation"
  echo
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "## Inputs"
  echo "- Target host/user: ${TARGET_HOST} / ${TARGET_SSH_USER}"
  echo "- TARGET_ORACLE_SID: ${TARGET_ORACLE_SID:-<empty>}"
  echo "- TARGET_REMOTE_ORACLE_HOME: ${TARGET_REMOTE_ORACLE_HOME:-<empty>}"
  echo "- TARGET_DATABASE_UNIQUE_NAME: ${TARGET_DATABASE_UNIQUE_NAME:-<empty>}"
  echo
} > "$REPORT_FILE"

if [ -z "$TARGET_ORACLE_SID" ] || is_placeholder "$TARGET_ORACLE_SID"; then
  echo "- FAIL: TARGET_ORACLE_SID is empty or placeholder in zdm-env.md." >> "$REPORT_FILE"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

REMOTE_CHECK_CMD="ps -ef | grep pmon | grep -v grep"
if [ -n "$TARGET_SSH_KEY" ] && ! is_placeholder "$TARGET_SSH_KEY"; then
  ssh -o BatchMode=yes -o ConnectTimeout=10 -i "$TARGET_SSH_KEY" "${TARGET_SSH_USER}@${TARGET_HOST}" "$REMOTE_CHECK_CMD" > "$RAW_FILE" 2>&1 || true
else
  ssh -o BatchMode=yes -o ConnectTimeout=10 "${TARGET_SSH_USER}@${TARGET_HOST}" "$REMOTE_CHECK_CMD" > "$RAW_FILE" 2>&1 || true
fi

echo "## PMON Evidence" >> "$REPORT_FILE"
if grep -q "$TARGET_ORACLE_SID" "$RAW_FILE"; then
  echo "- PASS: TARGET_ORACLE_SID found in PMON list." >> "$REPORT_FILE"
else
  echo "- FAIL: TARGET_ORACLE_SID not found in PMON list." >> "$REPORT_FILE"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

echo "- Raw output: ${RAW_FILE}" >> "$REPORT_FILE"

if [ "$FAIL_COUNT" -eq 0 ]; then
  echo >> "$REPORT_FILE"
  echo "## Result" >> "$REPORT_FILE"
  echo "PASS: target SID pinning validated." >> "$REPORT_FILE"
  echo "Created: $REPORT_FILE"
  exit 0
fi

echo >> "$REPORT_FILE"
echo "## Result" >> "$REPORT_FILE"
echo "FAIL: ${FAIL_COUNT} target SID pinning issue(s) detected." >> "$REPORT_FILE"
echo "Created: $REPORT_FILE"
exit 1
