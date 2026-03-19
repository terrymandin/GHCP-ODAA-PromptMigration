---
agent: agent
description: Phase 10 ZDM Step 5 example - generate final migration artifacts from requirements
---
# Example: Generate Migration Artifacts (Step 5)

## Example Prompt

```text
@Phase10-ZDM-Step5-Generate-Migration-Artifacts

Generate final migration artifacts.

Optional Generation Input:
#file:zdm-env.md

Step3 Input:
#file:Artifacts/Phase10-Migration/Step3/Migration-Questionnaire.md

Step4 Inputs:
#file:Artifacts/Phase10-Migration/Step4/Issue-Resolution-Log.md
#file:Artifacts/Phase10-Migration/Step4/Verification-Results.md

Relevant Step2 Discovery Inputs:
#file:Artifacts/Phase10-Migration/Step2/Discovery/source/source-discovery-<timestamp>.json
#file:Artifacts/Phase10-Migration/Step2/Discovery/target/target-discovery-<timestamp>.json
#file:Artifacts/Phase10-Migration/Step2/Discovery/server/server-discovery-<timestamp>.json

Output Directory:
Artifacts/Phase10-Migration/Step5/
```

## Expected Output

- `Artifacts/Phase10-Migration/Step5/README.md`
- `Artifacts/Phase10-Migration/Step5/ZDM-Migration-Runbook.md`
- `Artifacts/Phase10-Migration/Step5/zdm_migrate.rsp`
- `Artifacts/Phase10-Migration/Step5/zdm_commands.sh`

## Requirements Summary

- Generation-only step: create Step5 artifacts only; do not execute migration operations in VS Code.
- If `zdm-env.md` is attached, treat it as authoritative generation input and explicitly flag mismatches with discovery or prior artifacts.
- Generated artifacts must be runtime-portable and must not read or source `zdm-env.md`.
- Step 5 artifacts must include environment-variable based configuration, admin-to-zdmuser flow, and ZDM version readiness gating.

## Next Steps

Commit Step5 artifacts, then execute runtime migration operations on the jumpbox or ZDM server using the generated runbook and command script.
