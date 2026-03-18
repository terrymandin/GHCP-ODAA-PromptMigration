# Phase10 Migration - Step2 Discovery Scripts

## Purpose
Step2 generates read-only discovery scripts for source, target, and ZDM server context collection.
The scripts are generated in this repository now, but they are executed later on the jumpbox/ZDM server.

## Generated Files And Directories
Generated scripts:
- `Scripts/zdm_source_discovery.sh`
- `Scripts/zdm_target_discovery.sh`
- `Scripts/zdm_server_discovery.sh`
- `Scripts/zdm_orchestrate_discovery.sh`

Generated docs:
- `README.md`
- `Scripts/README.md`

Runtime output directories (created as placeholders now):
- `Discovery/source/`
- `Discovery/target/`
- `Discovery/server/`

Runtime logs and orchestration reports are also written under `Discovery/` when scripts run.

## Required Runtime User
Run Step2 from the jumpbox/ZDM server clone of this repository.

- `zdm_orchestrate_discovery.sh` should be run from the Step2 scripts folder.
- `zdm_server_discovery.sh` enforces running as `zdmuser`.

## What To Run Later On Jumpbox/ZDM Server
From repository root:

```bash
cd Artifacts/Phase10-Migration/Step2/Scripts
bash zdm_orchestrate_discovery.sh
```

Optional helper commands:

```bash
bash zdm_orchestrate_discovery.sh -h
bash zdm_orchestrate_discovery.sh -c
bash zdm_orchestrate_discovery.sh -t source
bash zdm_orchestrate_discovery.sh -t target
bash zdm_orchestrate_discovery.sh -t server
bash zdm_orchestrate_discovery.sh -v
```

## Runtime Outputs
When executed on jumpbox/ZDM server, expected outputs are:

- Source discovery raw text and JSON:
  - `Discovery/source/zdm_source_discovery_<hostname>_<timestamp>.txt`
  - `Discovery/source/zdm_source_discovery_<hostname>_<timestamp>.json`
- Target discovery raw text and JSON:
  - `Discovery/target/zdm_target_discovery_<hostname>_<timestamp>.txt`
  - `Discovery/target/zdm_target_discovery_<hostname>_<timestamp>.json`
- Server discovery raw text and JSON:
  - `Discovery/server/zdm_server_discovery_<hostname>_<timestamp>.txt`
  - `Discovery/server/zdm_server_discovery_<hostname>_<timestamp>.json`
- Orchestration reports:
  - `Discovery/discovery-orchestration-report-<timestamp>.md`
  - `Discovery/discovery-orchestration-report-<timestamp>.json`
- Per-run logs:
  - `Discovery/logs/source-discovery-<timestamp>.log`
  - `Discovery/logs/target-discovery-<timestamp>.log`
  - `Discovery/logs/server-discovery-<timestamp>.log`

## Success / Failure Signals
- Success signal: orchestrator exits with code `0`, per-script status shows `PASS`, and discovery `.txt` and `.json` files are present for each selected target.
- Failure signal: orchestrator exits non-zero, report status is partial/fail, and one or more warnings/errors are listed in report and logs.

## Next Step
After running Step2 and validating outputs, continue with `@Phase10-ZDM-Step3-Discovery-Questionnaire`.
