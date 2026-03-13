---
mode: agent
description: Phase 10 ZDM Step 2 example - generate discovery scripts for a sample environment
---
# Example: Generate Discovery Scripts (Step 2)

## Example Prompt

```text
@Phase10-ZDM-Step2-Generate-Discovery-Scripts

## Project Configuration
#file:zdm-env.md

Generate Step 2 discovery scripts.
```

> After generation, copy the scripts to the ZDM server and run them to collect discovery output.

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

## Next Step
After collecting discovery outputs and committing them, continue with: `@Phase10-ZDM-Step3-Discovery-Questionnaire`
