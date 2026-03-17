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

ZDM_HOME="$(get_env_value ZDM_HOME)"
ZDMCLI="$ZDM_HOME/bin/zdmcli"

if [ ! -x "$ZDMCLI" ]; then
  echo "ERROR: zdmcli not executable at $ZDMCLI"
  exit 2
fi

TS="$(date +%Y%m%d-%H%M%S)"
RAW_FILE="$OUT_DIR/zdm-version-${TS}.txt"
REPORT_FILE="$OUT_DIR/fix-02-zdm-version-report-${TS}.md"

commands=(
  "$ZDMCLI -build"
  "$ZDMCLI -v"
  "$ZDMCLI -version"
  "$ZDMCLI help"
)

SUCCESS_CMD=""

for cmd in "${commands[@]}"; do
  if bash -c "$cmd" > "$RAW_FILE" 2>&1; then
    SUCCESS_CMD="$cmd"
    break
  fi
done

if [ -z "$SUCCESS_CMD" ]; then
  {
    echo "# Fix 02 - ZDM Version Evidence"
    echo
    echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo "## Result"
    echo "FAIL: Unable to capture ZDM version/build with tested commands."
    echo
    echo "## Commands Attempted"
    for cmd in "${commands[@]}"; do
      echo "- $cmd"
    done
    echo
    echo "## Raw Output"
    echo "- ${RAW_FILE}"
  } > "$REPORT_FILE"
  echo "Created: $REPORT_FILE"
  exit 1
fi

{
  echo "# Fix 02 - ZDM Version Evidence"
  echo
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "## Result"
  echo "PASS: ZDM command succeeded and output captured."
  echo
  echo "## Successful Command"
  echo "- ${SUCCESS_CMD}"
  echo
  echo "## Raw Output"
  echo "- ${RAW_FILE}"
} > "$REPORT_FILE"

echo "Created: $REPORT_FILE"
