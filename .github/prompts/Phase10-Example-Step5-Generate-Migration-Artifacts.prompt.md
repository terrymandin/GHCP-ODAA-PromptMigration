---
mode: agent
description: Phase 10 ZDM Step 5 example - generate migration artifacts ready to execute
---
# Example: Generate Migration Artifacts (Step 5)

## Example Prompt

```text
@Phase10-ZDM-Step5-Generate-Migration-Artifacts

## Project Configuration
#file:zdm-env.md

Generate migration artifacts.

## Step 3 Inputs
#file:Artifacts/Phase10-Migration/Step3/Discovery-Summary.md
#file:Artifacts/Phase10-Migration/Step3/Migration-Questionnaire.md

## Step 4 Inputs
#file:Artifacts/Phase10-Migration/Step4/Issue-Resolution-Log.md
#file:Artifacts/Phase10-Migration/Step4/Verification/Verification-Results.md

## Step 2 Discovery Inputs
#file:Artifacts/Phase10-Migration/Step2/Discovery/source/<source-hostname>-<timestamp>.json
#file:Artifacts/Phase10-Migration/Step2/Discovery/target/<target-hostname>-<timestamp>.json
#file:Artifacts/Phase10-Migration/Step2/Discovery/server/<zdm-hostname>-<timestamp>.json

## Output Directory
Artifacts/Phase10-Migration/Step5/
```

> Replace `<hostname>` and `<timestamp>` with the actual filenames from Step 2.

## Expected Output
- `Artifacts/Phase10-Migration/Step5/README.md` — prerequisites checklist and quick-start guide
- `Artifacts/Phase10-Migration/Step5/zdm_migrate_<DB_NAME>.rsp` — ZDM response file
- `Artifacts/Phase10-Migration/Step5/zdm_commands_<DB_NAME>.sh` — init, create-creds, eval, migrate, monitor commands
- `Artifacts/Phase10-Migration/Step5/ZDM-Migration-Runbook-<DB_NAME>.md` — step-by-step runbook

Derived from Step 2 discovery facts + Step 3 decisions + Step 4 verified resolutions.
