# Step2 Scripts - Discovery Execution Guide

## Script Inventory
- `zdm_source_discovery.sh`: read-only source database/server discovery (runs on source host via orchestrator SSH)
- `zdm_target_discovery.sh`: read-only target database/server discovery (runs on target host via orchestrator SSH)
- `zdm_server_discovery.sh`: read-only ZDM server discovery (runs locally as `zdmuser`)
- `zdm_orchestrate_discovery.sh`: coordinates source/target/server script execution and summary reporting

## Runtime Guardrails
- Scripts are read-only. SQL blocks use `SELECT` only.
- Source/target SQL execution runs under `oracle` via `sudo -u oracle`.
- Server discovery enforces a `zdmuser` runtime guard.
- SSH key paths support normalization; placeholder values like `<...>` are treated as unset.

## How To Run Later
From repository root:

```bash
bash Artifacts/Phase10-Migration/Step2/Scripts/zdm_orchestrate_discovery.sh
```

Common flags:

```bash
bash Artifacts/Phase10-Migration/Step2/Scripts/zdm_orchestrate_discovery.sh -c    # show effective config
bash Artifacts/Phase10-Migration/Step2/Scripts/zdm_orchestrate_discovery.sh -t all
bash Artifacts/Phase10-Migration/Step2/Scripts/zdm_orchestrate_discovery.sh -t source
bash Artifacts/Phase10-Migration/Step2/Scripts/zdm_orchestrate_discovery.sh -t target
bash Artifacts/Phase10-Migration/Step2/Scripts/zdm_orchestrate_discovery.sh -t server
```

## Runtime Outputs
- Raw text + JSON per endpoint:
  - `Artifacts/Phase10-Migration/Step2/Discovery/source/zdm_source_discovery_<hostname>_<timestamp>.txt`
  - `Artifacts/Phase10-Migration/Step2/Discovery/source/zdm_source_discovery_<hostname>_<timestamp>.json`
  - `Artifacts/Phase10-Migration/Step2/Discovery/target/zdm_target_discovery_<hostname>_<timestamp>.txt`
  - `Artifacts/Phase10-Migration/Step2/Discovery/target/zdm_target_discovery_<hostname>_<timestamp>.json`
  - `Artifacts/Phase10-Migration/Step2/Discovery/server/zdm_server_discovery_<hostname>_<timestamp>.txt`
  - `Artifacts/Phase10-Migration/Step2/Discovery/server/zdm_server_discovery_<hostname>_<timestamp>.json`
- Orchestrator summary files:
  - `Artifacts/Phase10-Migration/Step2/Discovery/discovery-summary-<timestamp>.md`
  - `Artifacts/Phase10-Migration/Step2/Discovery/discovery-summary-<timestamp>.json`
- Orchestrator logs:
  - `Artifacts/Phase10-Migration/Step2/Discovery/discovery-run-<timestamp>.log`
  - endpoint-specific orchestrator logs in endpoint output directories

## Success / Failure Signals
- Success: endpoint statuses are `PASS`, orchestrator exits with `0`, summary JSON status is `success`.
- Failure/partial: one or more endpoint statuses are `FAIL`, orchestrator exits non-zero, summary JSON status is `partial` and warnings are populated.
