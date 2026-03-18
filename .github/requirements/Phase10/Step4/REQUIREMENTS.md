# Step4 Requirements - Fix Issues

## Objective

Generate remediation and verification artifacts for blockers and required actions identified in Step3.

## S4-01: Output contract

Required generated artifacts under `Artifacts/Phase10-Migration/Step4/`:

- `Issue-Resolution-Log.md`
- `verify_fixes.sh`
- Remediation scripts under `Scripts/`
- One `README-<scriptname>.md` companion per remediation script

## S4-02: Iterative operation model

1. Step4 supports repeated cycles until blockers are resolved.
2. Each iteration updates issue tracking and verification outcomes.

## S4-03: Runtime user model

1. Generated scripts run as `zdmuser` on ZDM server.
2. Scripts must include a user guard that exits when not running as `zdmuser`.

## S4-04: Quoting and SQL execution safety

1. For SSH-based SQL helpers, use base64-wrapped SQL block execution to avoid shell quoting breakage.
2. Normalize optional SSH keys and conditionally include `-i` only when key is set and non-placeholder.

## S4-05: Verification output

1. `verify_fixes.sh` tracks per-issue PASS/FAIL/WARN status.
2. Verification writes structured markdown results to `Verification-Results.md` for Step5 consumption.

## S4-06: Issue-Resolution-Log generated items

`Issue-Resolution-Log.md` should include at least:

1. Issue register with IDs, severity, owner, status, and last-updated timestamp.
2. For each issue: evidence, remediation plan, verification method, and rollback notes.
3. Iteration history showing what changed between remediation cycles.
4. Explicit unresolved items and blockers preventing Step5 progression.

## S4-07: Remediation package generated items

For each remediation script in `Scripts/`, generate a companion `README-<scriptname>.md` containing:

1. Purpose and target server.
2. Prerequisites and required environment variables.
3. Step-by-step behavior summary.
4. Exact execution command and required runtime user (`zdmuser`).
5. Expected output or success indicators.
6. Rollback/undo guidance when applicable.

## S4-08: Verification-Results generated items

`Verification-Results.md` should include:

1. Per-issue status table (PASS/FAIL/WARN).
2. Evidence detail per issue (what was checked and observed values).
3. Overall blocker resolution result indicating Step5 readiness.
4. Remaining warnings/recommendations that are not hard blockers.
