---
agent: agent
description: Phase 10 ZDM Step 4 example - resolve blockers identified in discovery
---
# Example: Fix Issues (Step 4)

## Example Prompt

```text
@Phase10-ZDM-Step4-Fix-Issues

Project Configuration:
#file:zdm-env.md

Resolve blockers and required actions found in Step 3 outputs.

Step 3 Inputs:
#file:Artifacts/Phase10-Migration/Step3/Discovery-Summary.md
#file:Artifacts/Phase10-Migration/Step3/Migration-Questionnaire.md

Step 2 Discovery (Reference):
#file:Artifacts/Phase10-Migration/Step2/Discovery/source/<source-hostname>-<timestamp>.json
#file:Artifacts/Phase10-Migration/Step2/Discovery/target/<target-hostname>-<timestamp>.json
#file:Artifacts/Phase10-Migration/Step2/Discovery/server/<zdm-hostname>-<timestamp>.json

Output Directory:
Artifacts/Phase10-Migration/Step4/
```

## Expected Output
- `Artifacts/Phase10-Migration/Step4/README.md`
- `Artifacts/Phase10-Migration/Step4/Issue-Resolution-Log.md`
- Remediation scripts in `Artifacts/Phase10-Migration/Step4/Scripts/` (one per blocker, each with a companion `README-<scriptname>.md`)
- `Artifacts/Phase10-Migration/Step4/Scripts/verify_fixes.sh` (writes `Verification-Results.md` when run)
- `Artifacts/Phase10-Migration/Step4/Verification-Results.md` (written by `verify_fixes.sh` at runtime)

## Requirements Summary

- Step 4 runs under the Remote-SSH execution model: VS Code is connected to the ZDM jumpbox as `zdmuser`; Copilot generates artifacts using file tools; remediation scripts requiring database changes need explicit user confirmation before execution.
- All outputs are written to `Artifacts/Phase10-Migration/Step4/` (git-ignored). No commit or push is required.
- If `zdm-env.md` is attached, treat it as authoritative generation-time input; document mismatches with discovery evidence and include verification steps.
- Step 4 supports iterative remediation cycles (S4-02): each cycle updates the Issue-Resolution-Log with iteration history and new verification outcomes.
- Issue-Resolution-Log must include: issue register with IDs/severity/status, per-issue evidence/remediation/verification/rollback, iteration history, and explicit unresolved blockers (S4-06).
- Every remediation script must have a companion `README-<scriptname>.md` covering purpose, target server, prerequisites, environment variables, step-by-step behavior, execution command, expected output, and rollback guidance (S4-07).
- `verify_fixes.sh` tracks per-issue PASS/FAIL/WARN status and writes `Verification-Results.md` to `Artifacts/Phase10-Migration/Step4/` at runtime (S4-05, S4-08).
- `Verification-Results.md` includes: per-issue status table, evidence detail per issue, overall blocker resolution result, and remaining warnings (S4-08).
- All generated scripts must include a `zdmuser` guard, use base64-wrapped SQL for SSH-based SQL helpers, and normalize optional SSH keys (S4-03, S4-04).
- Step4 README summarizes generated files, review steps, success/failure signals (CR-08).

## Next Steps

After blockers are resolved and verification indicates readiness, continue with @Phase10-ZDM-Step5-Generate-Migration-Artifacts.
