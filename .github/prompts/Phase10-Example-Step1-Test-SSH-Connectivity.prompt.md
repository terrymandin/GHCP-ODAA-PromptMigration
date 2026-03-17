---
agent: agent
description: Phase 10 ZDM Step 1 example - test SSH connectivity for a sample environment
---
# Example: Test SSH Connectivity (Step 1)

## Example Prompt

```text
@Phase10-ZDM-Step1-Test-SSH-Connectivity

## Project Configuration
#file:zdm-env.md

Generate a script to validate SSH connectivity later on the jumpbox/ZDM server.
```

`zdm-env.md` is attached only to populate generated script values. The generated script must run without reading `zdm-env.md` at runtime.

Step 1 prompt behavior is generation-only: create the script in `Artifacts/Phase10-Migration/Step1/Scripts/` and do not run SSH checks or create report files during prompt execution.

Agent action guardrail:
- Do not run terminal commands for SSH checks in this step.
- Only generate the script file in the Step1 `Scripts/` directory.

## Expected Output

```
Artifacts/Phase10-Migration/Step1/
├── Scripts/zdm_test_ssh_connectivity.sh
└── Validation/ (produced at runtime)
    ├── ssh-connectivity-report-<timestamp>.md
    └── ssh-connectivity-report-<timestamp>.json
```

## Next Step
After generating the script, commit and push it to GitHub. Run it from the repo clone on the jumpbox/ZDM server as `zdmuser`, and if both SSH checks pass, continue with: `@Phase10-ZDM-Step2-Generate-Discovery-Scripts`
