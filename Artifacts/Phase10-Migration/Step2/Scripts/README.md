# Step 2 Scripts

## Generated scripts

- `zdm_source_discovery.sh`
- `zdm_target_discovery.sh`
- `zdm_server_discovery.sh`
- `zdm_orchestrate_discovery.sh`

All scripts are read-only and collect discovery data only.

## How to run on jumpbox/ZDM server

1. `chmod +x *.sh`
2. Run full discovery:
   - `./zdm_orchestrate_discovery.sh -v`
3. Optional single target run:
   - `./zdm_orchestrate_discovery.sh -t source`
   - `./zdm_orchestrate_discovery.sh -t target`
   - `./zdm_orchestrate_discovery.sh -t server`
4. Show config/help:
   - `./zdm_orchestrate_discovery.sh -c`
   - `./zdm_orchestrate_discovery.sh -h`

## Runtime output locations

- Source: `../Discovery/source/`
- Target: `../Discovery/target/`
- Server: `../Discovery/server/`
- Orchestrator reports/logs: `../Discovery/discovery_orchestrator_<timestamp>.{log,md,json}`

## Success and failure checks

- `PASS` appears for each discovery target in orchestrator report.
- JSON report top-level `status` is `success` for full success or `partial` when warnings/failures occurred.
- Non-zero exit code indicates one or more discovery targets failed.
