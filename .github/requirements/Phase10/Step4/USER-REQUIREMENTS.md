# Step4 User Requirements - Fix Issues

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
