---
agent: agent
description: Phase 10 ZDM Step 4 example - resolve blockers identified in discovery
---
# Example: Fix Issues (Step 4)

## Example Prompt

```text
@Phase10-ZDM-Step4-Fix-Issues

## Project Configuration
#file:zdm-env.md

Resolve blockers and required actions found in Step 3 outputs.

## Step 3 Inputs
#file:Artifacts/Phase10-Migration/Step3/Discovery-Summary.md
#file:Artifacts/Phase10-Migration/Step3/Migration-Questionnaire.md

## Step 2 Discovery (Reference)
#file:Artifacts/Phase10-Migration/Step2/Discovery/source/<source-hostname>-<timestamp>.json
#file:Artifacts/Phase10-Migration/Step2/Discovery/target/<target-hostname>-<timestamp>.json
#file:Artifacts/Phase10-Migration/Step2/Discovery/server/<zdm-hostname>-<timestamp>.json

## Output Directory
Artifacts/Phase10-Migration/Step4/
```

## Expected Output
- `Artifacts/Phase10-Migration/Step4/Issue-Resolution-Log.md`
- Remediation scripts (one per blocker) each with a companion `README.md`
- `verify_fixes.sh` to confirm all blockers are resolved

Step 4 prompt behavior is generation-only: do not execute remediation or verification commands during prompt execution in VS Code.

## Next Step
When all blockers are resolved and `verify_fixes.sh` reports PASS (run from the repository clone on the jumpbox/ZDM server), continue with: `@Phase10-ZDM-Step5-Generate-Migration-Artifacts`
