---
mode: agent
description: Phase 10 ZDM Step 1 example - test SSH connectivity for a sample environment
---
# Example: Test SSH Connectivity (Step 1)

## Example Prompt

```text
@Phase10-ZDM-Step1-Test-SSH-Connectivity

## Project Configuration
#file:zdm-env.md

Validate SSH connectivity using the configured source/target hosts, users, and keys.
```

## Expected Output

```
Artifacts/Phase10-Migration/Step1/
├── Scripts/zdm_test_ssh_connectivity.sh
└── Validation/ (produced at runtime)
    ├── ssh-connectivity-report-<timestamp>.md
    └── ssh-connectivity-report-<timestamp>.json
```

## Next Step
If both SSH checks pass, continue with: `@Phase10-ZDM-Step2-Generate-Discovery-Scripts`
