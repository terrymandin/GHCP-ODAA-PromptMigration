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
OUT_DIR="$REPO_ROOT/Artifacts/Phase10-Migration/Step4/Resolution"
mkdir -p "$OUT_DIR"

MIN_FREE_KB="${STEP4_MIN_ROOT_FREE_KB:-2097152}"
TS="$(date +%Y%m%d-%H%M%S)"
REPORT_FILE="$OUT_DIR/fix-04-zdm-disk-report-${TS}.md"

ROOT_LINE="$(df -Pk / | awk 'NR==2 {print $0}')"
ROOT_AVAIL_KB="$(df -Pk / | awk 'NR==2 {print $4}')"
ROOT_USE_PCT="$(df -Pk / | awk 'NR==2 {print $5}')"
ROOT_AVAIL_GIB="$(awk -v kb="$ROOT_AVAIL_KB" 'BEGIN {printf "%.2f", kb/1048576}')"
MIN_FREE_GIB="$(awk -v kb="$MIN_FREE_KB" 'BEGIN {printf "%.2f", kb/1048576}')"

STATUS="PASS"
if [ "$ROOT_AVAIL_KB" -lt "$MIN_FREE_KB" ]; then
  STATUS="FAIL"
fi

{
  echo "# Fix 04 - ZDM Root Disk Headroom"
  echo
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "## Check Inputs"
  echo "- Minimum required free space (KB): ${MIN_FREE_KB}"
  echo "- Minimum required free space (GiB): ${MIN_FREE_GIB}"
  echo
  echo "## Observed"
  echo "- df row: ${ROOT_LINE}"
  echo "- Available (KB): ${ROOT_AVAIL_KB}"
  echo "- Available (GiB): ${ROOT_AVAIL_GIB}"
  echo "- Use percent: ${ROOT_USE_PCT}"
  echo
  echo "## Result"
  if [ "$STATUS" = "PASS" ]; then
    echo "PASS: root filesystem free space meets threshold."
  else
    echo "FAIL: root filesystem free space is below threshold."
  fi
} > "$REPORT_FILE"

echo "Created: $REPORT_FILE"
[ "$STATUS" = "PASS" ]
