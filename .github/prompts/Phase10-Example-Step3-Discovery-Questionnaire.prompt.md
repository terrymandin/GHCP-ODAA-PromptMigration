---
agent: agent
description: Phase 10 ZDM Step 3 example - analyze discovery output and generate migration plan
---
# Example: Discovery Analysis and Migration Planning (Step 3)

## Example Prompt

```text
@Phase10-ZDM-Step3-Discovery-Questionnaire

Project Configuration:
#file:zdm-env.md

Analyze Step 2 discovery outputs and generate:
1) Discovery Summary
2) Migration Planning Questionnaire
3) Step3 README

Step 2 Discovery Inputs:
Search the following directories for discovery output files and read the most recent ones:
- `Artifacts/Phase10-Migration/Step2/Discovery/source/` — source database discovery (`.md` and `.json`)
- `Artifacts/Phase10-Migration/Step2/Discovery/target/` — target database discovery (`.md` and `.json`)
- `Artifacts/Phase10-Migration/Step2/Discovery/server/` — ZDM server discovery (`.md` and `.json`)

If multiple timestamped files exist in a directory, use the one with the highest (most recent) timestamp.

Output Directory:
Artifacts/Phase10-Migration/Step3/
```

## Expected Output
- `Artifacts/Phase10-Migration/Step3/README.md`
- `Artifacts/Phase10-Migration/Step3/Discovery-Summary.md`
- `Artifacts/Phase10-Migration/Step3/Migration-Questionnaire.md`

## Requirements Summary

- Step 3 analyzes Step2 discovery outputs and produces three Step3 artifacts: README, Discovery Summary, and Migration Questionnaire.
- If `zdm-env.md` is attached, treat it as configured baseline; explicitly report mismatches against discovery evidence using a Field / Configured Intent / Discovered Value / Recommended Action table.
- When multiple discovery files exist per component, use the most recent by timestamp.
- Discovery Summary must include: generation metadata, executive summary by component, migration method recommendation with justification, source/target/ZDM details with readiness checks, required actions by severity (critical vs recommended), discovered values reference, and mismatch section when applicable.
- Do not classify "oracle SSH directory not found" as a blocker when Step2 discovery succeeded; always evaluate ZDM version from server discovery and flag UNDETERMINED or outdated versions as required actions.
- Migration Questionnaire must capture only manual decisions (including migration strategy, cutover approach, OCI/Azure identifiers, object storage, migration options, and network configuration) with recommended defaults and justifications.
- After writing all output files, provide a validation evidence summary confirming each file was created.
- All outputs are written to `Artifacts/Phase10-Migration/Step3/` (git-ignored).

## Next Steps

After reviewing Discovery Summary and completing the questionnaire, continue with @Phase10-ZDM-Step4-Fix-Issues.
