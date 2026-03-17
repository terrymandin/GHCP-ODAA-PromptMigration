---
agent: agent
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
Search the following directories for discovery output files and read the most recent ones:
- `Artifacts/Phase10-Migration/Step2/Discovery/source/` — source database discovery (`.txt` and `.json`)
- `Artifacts/Phase10-Migration/Step2/Discovery/target/` — target database discovery (`.txt` and `.json`)
- `Artifacts/Phase10-Migration/Step2/Discovery/server/` — ZDM server discovery (`.txt` and `.json`)

If multiple timestamped files exist in a directory, use the one with the highest (most recent) timestamp.

## Output Directory
Artifacts/Phase10-Migration/Step3/
```

## Expected Output
- `Artifacts/Phase10-Migration/Step3/Discovery-Summary.md`
- `Artifacts/Phase10-Migration/Step3/Migration-Questionnaire.md`

If `zdm-env.md` is attached, use it as the configured baseline when creating Step3 artifacts and explicitly call out mismatches between configured values and discovered runtime values.

## Next Step
After completing the questionnaire, continue with: `@Phase10-ZDM-Step4-Fix-Issues`
