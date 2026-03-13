# Discovery Output: ZDM Server

Discovery output files from the ZDM server are collected here by `zdm_orchestrate_discovery.sh`
after running `zdm_server_discovery.sh` locally.

## Expected Files

| File | Description |
|------|-------------|
| `zdm_server_discovery_<hostname>_<timestamp>.txt` | Full human-readable discovery report |
| `zdm_server_discovery_<hostname>_<timestamp>.json` | Machine-parseable JSON summary |

## Contents Covered

- OS information and disk space (with warnings for < 50GB free)
- ZDM installation (ZDM_HOME, version, zdmcli status, service status, active jobs)
- ZDM version detection via Oracle Inventory, OPatch, version files, and path inference
- Java configuration (ZDM bundled JDK or system Java)
- OCI CLI version and configuration (masked)
- SSH key presence and permissions
- Network connectivity to source (`10.1.0.11`) and target (`10.0.1.160`)
  - Ping latency (10 pings, warning if avg RTT > 10ms)
  - Port tests: SSH (22) and Oracle listener (1521)
- Server network configuration (IPs, routing, DNS)
- ZDM log directory and recent logs
- Credential file search
