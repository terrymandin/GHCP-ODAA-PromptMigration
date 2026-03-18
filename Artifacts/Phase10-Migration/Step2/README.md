# Step 2 - Discovery Script Generation

This directory contains generated, read-only discovery tooling for ZDM migration preparation.

## Generated files

- `Scripts/zdm_source_discovery.sh`
- `Scripts/zdm_target_discovery.sh`
- `Scripts/zdm_server_discovery.sh`
- `Scripts/zdm_orchestrate_discovery.sh`
- `Scripts/README.md`
- `Discovery/source/` (placeholder output directory)
- `Discovery/target/` (placeholder output directory)
- `Discovery/server/` (placeholder output directory)

## What to run later on jumpbox/ZDM server

1. Copy this full `Step2` directory to the jumpbox or ZDM server.
2. Ensure scripts are executable:
   - `chmod +x Scripts/*.sh`
3. Run orchestrator from `Scripts/`:
   - `./zdm_orchestrate_discovery.sh -v`

## Runtime outputs and logs

At runtime, outputs are written under `Discovery/`:

- Source artifacts: `Discovery/source/`
- Target artifacts: `Discovery/target/`
- Server artifacts: `Discovery/server/`
- Orchestrator log/report files: `Discovery/discovery_orchestrator_<timestamp>.{log,md,json}`

Per discovery script naming pattern:

- `zdm_<type>_discovery_<hostname>_<timestamp>.txt`
- `zdm_<type>_discovery_<hostname>_<timestamp>.json`

## Success and failure signals

- Success: orchestrator exits `0`, markdown/json report status is `success`, and each target shows `PASS`.
- Partial/failure: orchestrator exits non-zero, report status is `partial`, and `FAIL` entries explain which target/script failed.
