# Step5 System Requirements - Remediation Script Implementation

## Scope

This file defines script-level coding constraints for remediation and verification artifacts generated in Step5.

## S5-03: Runtime user model

1. Generated scripts run as `zdmuser` on ZDM server.
2. Scripts must include a user guard that exits when not running as `zdmuser`.

## S5-04: Quoting and SQL execution safety

1. For SSH-based SQL helpers, use base64-wrapped SQL block execution to avoid shell quoting breakage.
2. Normalize optional SSH keys and conditionally include `-i` only when key is set and non-placeholder.

## S5-05: Verification output

1. `verify_fixes.sh` tracks per-issue PASS/FAIL/WARN status.
2. Verification writes structured markdown results to `Verification-Results.md` for Step6 consumption.

## S5-09: Script creation only '€” no execution during prompt

1. Remediation scripts and the verification script are **generated and saved to disk only**.
2. The prompt must **not execute** any remediation or verification script as part of its run.
3. Execution is the operator's responsibility, performed manually outside the prompt after reviewing the generated artifacts.

## S5-08: Verification-Results generated items

`Verification-Results.md` should include:

1. Per-issue status table (PASS/FAIL/WARN).
2. Evidence detail per issue (what was checked and observed values).
3. Overall blocker resolution result indicating Step6 readiness.
4. Remaining warnings/recommendations that are not hard blockers.
