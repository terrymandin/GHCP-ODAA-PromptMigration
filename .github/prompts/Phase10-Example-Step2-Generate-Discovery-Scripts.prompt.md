---
agent: agent
description: Phase 10 ZDM Step 2 example - generate discovery scripts for a sample environment
---
# Example: Generate Discovery Scripts (Step 2)

## Example Prompt

```text
@Phase10-ZDM-Step2-Generate-Discovery-Scripts

Project Configuration:
#file:zdm-env.md

Generate Step 2 discovery scripts.
```

## Expected Output

```
Artifacts/Phase10-Migration/Step2/
├── Scripts/
│   ├── zdm_source_discovery.sh
│   ├── zdm_target_discovery.sh
│   ├── zdm_server_discovery.sh
│   ├── zdm_orchestrate_discovery.sh
│   └── README.md
└── Discovery/
    ├── source/
    ├── target/
    └── server/
```

## Requirements Summary

- Generation-only step: create discovery scripts and directories only; do not run discovery in VS Code.
- If `zdm-env.md` is attached, treat it as authoritative generation input and prefer it over defaults.
- Generated scripts must not read or source `zdm-env.md` at runtime.
- Step 2 output contract includes four scripts, script README, and discovery output folders; discovery files are produced later when scripts run on jumpbox/ZDM server.

## Next Steps

After running discovery scripts and collecting outputs, continue with @Phase10-ZDM-Step3-Discovery-Questionnaire.
