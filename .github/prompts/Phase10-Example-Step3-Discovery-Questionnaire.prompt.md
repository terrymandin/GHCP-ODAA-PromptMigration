---
mode: agent
description: Phase 10 ZDM Step 3 example - analyze discovery output and generate migration plan
---
# Example: Discovery Analysis and Migration Planning (Step 3)

## Example Prompt

```text
@Phase10-ZDM-Step3-Discovery-Questionnaire

## Project Configuration
#file:zdm-env.md

Analyze Step 2 discovery outputs and generate:
1) Discovery Summary
2) Migration Planning Questionnaire

## Step 2 Discovery Inputs
#file:Artifacts/Phase10-Migration/Step2/Discovery/source/<source-hostname>-<timestamp>.txt
#file:Artifacts/Phase10-Migration/Step2/Discovery/source/<source-hostname>-<timestamp>.json
#file:Artifacts/Phase10-Migration/Step2/Discovery/target/<target-hostname>-<timestamp>.txt
#file:Artifacts/Phase10-Migration/Step2/Discovery/target/<target-hostname>-<timestamp>.json
#file:Artifacts/Phase10-Migration/Step2/Discovery/server/<zdm-hostname>-<timestamp>.txt
#file:Artifacts/Phase10-Migration/Step2/Discovery/server/<zdm-hostname>-<timestamp>.json

## Output Directory
Artifacts/Phase10-Migration/Step3/
```

> Replace `<hostname>` and `<timestamp>` with the actual filenames produced by Step 2.
> Use the most recent files if multiple runs exist.

## Expected Output
- `Artifacts/Phase10-Migration/Step3/Discovery-Summary.md`
- `Artifacts/Phase10-Migration/Step3/Migration-Questionnaire.md`

## Next Step
After completing the questionnaire, continue with: `@Phase10-ZDM-Step4-Fix-Issues`
