# Step2 Scripts README

## Files In This Directory
- `zdm_source_discovery.sh` - remote source database and host read-only discovery
- `zdm_target_discovery.sh` - remote target database and host read-only discovery
- `zdm_server_discovery.sh` - local ZDM server read-only discovery (enforces `zdmuser`)
- `zdm_orchestrate_discovery.sh` - orchestrates source, target, and server discovery execution and artifact collection

## What To Run Later On Jumpbox/ZDM Server
Primary command:

```bash
bash zdm_orchestrate_discovery.sh
```

CLI options:
- `-h` show usage and exit
- `-c` show effective runtime configuration and exit
- `-t all|source|target|server` choose which discovery scripts to run
- `-v` verbose mode

## Runtime Output, Logs, And Reports
All runtime outputs are written under Step2 `Discovery/`:

- `../Discovery/source/` - source discovery txt/json outputs
- `../Discovery/target/` - target discovery txt/json outputs
- `../Discovery/server/` - server discovery txt/json outputs
- `../Discovery/logs/` - orchestrator execution logs per script
- `../Discovery/discovery-orchestration-report-<timestamp>.md`
- `../Discovery/discovery-orchestration-report-<timestamp>.json`

Per-script output naming pattern:
- `zdm_<type>_discovery_<hostname>_<timestamp>.txt`
- `zdm_<type>_discovery_<hostname>_<timestamp>.json`

## Success / Failure Signals
- Success: exit code `0`, report shows overall PASS/success, selected script statuses are `PASS`, and txt/json artifacts are present.
- Failure: non-zero exit code, report has warnings and partial/fail status, and one or more per-script statuses are `FAIL`.

## Notes
- Scripts are read-only and do not perform remediation actions.
- SQL statements are SELECT-only and run as `oracle` via `sudo -u oracle` on remote source/target hosts.
- SSH `-i` is used only when normalized key paths are non-empty.
