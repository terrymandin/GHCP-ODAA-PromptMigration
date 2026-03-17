#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
STEP4_DIR="$REPO_ROOT/Artifacts/Phase10-Migration/Step4"
VERIFY_DIR="$STEP4_DIR/Verification"
mkdir -p "$VERIFY_DIR"

TS="$(date +%Y%m%d-%H%M%S)"
SUMMARY_FILE="$VERIFY_DIR/Verification-Results-${TS}.md"

checks=(
  "fix-01-capture-db-version/fix_01_capture_db_version.sh"
  "fix-02-capture-zdm-version/fix_02_capture_zdm_version.sh"
  "fix-03-ssh-key-strategy/fix_03_validate_ssh_strategy.sh"
  "fix-04-zdm-disk-headroom/fix_04_check_zdm_disk_headroom.sh"
  "fix-05-target-sid-pinning/fix_05_validate_target_sid_pinning.sh"
)

pass_count=0
fail_count=0

{
  echo "# Step 4 Verification Results"
  echo
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "## Execution Summary"
} > "$SUMMARY_FILE"

for check in "${checks[@]}"; do
  script_path="$STEP4_DIR/$check"
  if bash "$script_path" > "$VERIFY_DIR/$(basename "$check" .sh)-${TS}.log" 2>&1; then
    echo "- PASS: ${check}" >> "$SUMMARY_FILE"
    pass_count=$((pass_count + 1))
  else
    echo "- FAIL: ${check}" >> "$SUMMARY_FILE"
    fail_count=$((fail_count + 1))
  fi
done

{
  echo
  echo "## Totals"
  echo "- Passed: ${pass_count}"
  echo "- Failed: ${fail_count}"
  echo
  if [ "$fail_count" -eq 0 ]; then
    echo "Overall Result: PASS"
  else
    echo "Overall Result: FAIL"
  fi
  echo
  echo "## Log Directory"
  echo "- ${VERIFY_DIR}"
} >> "$SUMMARY_FILE"

echo "Created: $SUMMARY_FILE"

if [ "$fail_count" -ne 0 ]; then
  exit 1
fi
