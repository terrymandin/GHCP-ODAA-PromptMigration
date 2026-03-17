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

SOURCE_HOST="$(get_env_value SOURCE_HOST)"
TARGET_HOST="$(get_env_value TARGET_HOST)"
SOURCE_SSH_USER="$(get_env_value SOURCE_SSH_USER)"
TARGET_SSH_USER="$(get_env_value TARGET_SSH_USER)"
SOURCE_SSH_KEY="$(get_env_value SOURCE_SSH_KEY || true)"
TARGET_SSH_KEY="$(get_env_value TARGET_SSH_KEY || true)"

TS="$(date +%Y%m%d-%H%M%S)"
REPORT_FILE="$OUT_DIR/fix-03-ssh-strategy-report-${TS}.md"
RAW_FILE="$OUT_DIR/fix-03-ssh-strategy-raw-${TS}.txt"

FAIL_COUNT=0
MODE="agent/default"

if [ -n "$SOURCE_SSH_KEY" ] && ! is_placeholder "$SOURCE_SSH_KEY"; then
  MODE="explicit-key"
fi
if [ -n "$TARGET_SSH_KEY" ] && ! is_placeholder "$TARGET_SSH_KEY"; then
  MODE="explicit-key"
fi

{
  echo "# Fix 03 - SSH Authentication Strategy Validation"
  echo
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "## Effective Mode"
  echo "- ${MODE}"
  echo
  echo "## Inputs"
  echo "- Source host/user: ${SOURCE_HOST} / ${SOURCE_SSH_USER}"
  echo "- Target host/user: ${TARGET_HOST} / ${TARGET_SSH_USER}"
  echo "- Source key: ${SOURCE_SSH_KEY:-<empty>}"
  echo "- Target key: ${TARGET_SSH_KEY:-<empty>}"
  echo
} > "$REPORT_FILE"

run_ssh_probe() {
  local host="$1"
  local user="$2"
  local key="$3"

  if [ -n "$key" ] && ! is_placeholder "$key"; then
    ssh -o BatchMode=yes -o ConnectTimeout=10 -i "$key" "${user}@${host}" "hostname"
  else
    ssh -o BatchMode=yes -o ConnectTimeout=10 "${user}@${host}" "hostname"
  fi
}

if [ "$MODE" = "explicit-key" ]; then
  echo "## Explicit Key Checks" >> "$REPORT_FILE"

  for key_path in "$SOURCE_SSH_KEY" "$TARGET_SSH_KEY"; do
    if [ -z "$key_path" ] || is_placeholder "$key_path"; then
      echo "- FAIL: explicit key mode selected but key value is missing or placeholder." >> "$REPORT_FILE"
      FAIL_COUNT=$((FAIL_COUNT + 1))
      continue
    fi

    if [ ! -f "$key_path" ]; then
      echo "- FAIL: key file not found: ${key_path}" >> "$REPORT_FILE"
      FAIL_COUNT=$((FAIL_COUNT + 1))
      continue
    fi

    perm="$(stat -c '%a' "$key_path")"
    if [ "$perm" != "600" ]; then
      echo "- FAIL: key file permissions are ${perm}, expected 600: ${key_path}" >> "$REPORT_FILE"
      FAIL_COUNT=$((FAIL_COUNT + 1))
    else
      echo "- PASS: key file exists with 600 permissions: ${key_path}" >> "$REPORT_FILE"
    fi
  done
else
  echo "## Agent/Default Checks" >> "$REPORT_FILE"
  if ssh-add -l > "$RAW_FILE" 2>&1; then
    echo "- PASS: ssh-agent identities are loaded." >> "$REPORT_FILE"
  else
    echo "- WARN: ssh-agent identity list not available; relying on default key files." >> "$REPORT_FILE"
    cat "$RAW_FILE" >> "$REPORT_FILE"
  fi
fi

echo >> "$REPORT_FILE"
echo "## Connectivity Probes" >> "$REPORT_FILE"

if run_ssh_probe "$SOURCE_HOST" "$SOURCE_SSH_USER" "$SOURCE_SSH_KEY" > "$RAW_FILE" 2>&1; then
  echo "- PASS: source SSH connectivity confirmed." >> "$REPORT_FILE"
else
  echo "- FAIL: source SSH connectivity failed." >> "$REPORT_FILE"
  cat "$RAW_FILE" >> "$REPORT_FILE"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

if run_ssh_probe "$TARGET_HOST" "$TARGET_SSH_USER" "$TARGET_SSH_KEY" > "$RAW_FILE" 2>&1; then
  echo "- PASS: target SSH connectivity confirmed." >> "$REPORT_FILE"
else
  echo "- FAIL: target SSH connectivity failed." >> "$REPORT_FILE"
  cat "$RAW_FILE" >> "$REPORT_FILE"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

if [ "$FAIL_COUNT" -eq 0 ]; then
  echo >> "$REPORT_FILE"
  echo "## Result" >> "$REPORT_FILE"
  echo "PASS: SSH strategy and connectivity checks passed." >> "$REPORT_FILE"
  echo "Created: $REPORT_FILE"
  exit 0
fi

echo >> "$REPORT_FILE"
echo "## Result" >> "$REPORT_FILE"
echo "FAIL: ${FAIL_COUNT} SSH strategy issue(s) detected." >> "$REPORT_FILE"
echo "Created: $REPORT_FILE"
exit 1
