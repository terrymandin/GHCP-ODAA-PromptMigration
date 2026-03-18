# Phase10 Migration - Step2 Discovery Scripts

## Purpose
Step2 generates read-only discovery scripts for source, target, and ZDM server assessment.

This step is generation-only in VS Code. Discovery runtime outputs are produced later when scripts are executed on the jumpbox/ZDM server.

## Generated Files
- `Scripts/zdm_source_discovery.sh`
- `Scripts/zdm_target_discovery.sh`
- `Scripts/zdm_server_discovery.sh`
- `Scripts/zdm_orchestrate_discovery.sh`
- `Scripts/README.md`

## Generated Directories
- `Discovery/source/`
- `Discovery/target/`
- `Discovery/server/`

## Required Runtime User
Run orchestrated discovery as `zdmuser` on the jumpbox/ZDM server.

## How To Run Later On Jumpbox/ZDM Server
From repository root:

```bash
bash Artifacts/Phase10-Migration/Step2/Scripts/zdm_orchestrate_discovery.sh
```

Optional scope execution:

```bash
bash Artifacts/Phase10-Migration/Step2/Scripts/zdm_orchestrate_discovery.sh -t source
bash Artifacts/Phase10-Migration/Step2/Scripts/zdm_orchestrate_discovery.sh -t target
bash Artifacts/Phase10-Migration/Step2/Scripts/zdm_orchestrate_discovery.sh -t server
```

## Runtime Output Locations
- Source discovery files: `Artifacts/Phase10-Migration/Step2/Discovery/source/`
- Target discovery files: `Artifacts/Phase10-Migration/Step2/Discovery/target/`
- Server discovery files: `Artifacts/Phase10-Migration/Step2/Discovery/server/`
- Orchestration markdown summary: `Artifacts/Phase10-Migration/Step2/Discovery/discovery-summary-<timestamp>.md`
- Orchestration JSON summary: `Artifacts/Phase10-Migration/Step2/Discovery/discovery-summary-<timestamp>.json`
- Runtime logs: `Artifacts/Phase10-Migration/Step2/Discovery/discovery-run-<timestamp>.log` plus per-target logs under each discovery subdirectory

## Success / Failure Signals
- Success: orchestrator exits `0`, per-script status shows `PASS`, and summary JSON contains `"status": "success"`.
- Partial/Failure: non-zero orchestrator exit, one or more script statuses are `FAIL`, or summary JSON contains `"status": "partial"` with warnings.

## Next Step
After runtime discovery outputs are collected, continue with Step3: `@Phase10-ZDM-Step3-Discovery-Questionnaire`.
