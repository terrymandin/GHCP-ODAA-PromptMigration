# Step 2 Discovery Scripts (ZDM)

These scripts are generated from your local `zdm-env.md` values, but they are runtime-independent and do not read `zdm-env.md` when executed on the jumpbox/ZDM server.

## Files

- `zdm_source_discovery.sh`: Read-only source database server discovery (runs remotely over SSH)
- `zdm_target_discovery.sh`: Read-only target Oracle Database@Azure server discovery (runs remotely over SSH)
- `zdm_server_discovery.sh`: Read-only local ZDM server discovery (must run as `zdmuser`)
- `zdm_orchestrate_discovery.sh`: Master script to execute all three discoveries and collect outputs

## Prerequisites

- Run from the repo clone on the jumpbox/ZDM server
- Run orchestration as `zdmuser`
- SSH connectivity from ZDM server to source and target servers is already validated
- SSH keys are present in `~/.ssh` for the runtime user (`zdmuser`) when key-based auth is required
- If OCI integration checks are needed, OCI config should exist on ZDM server (typically `~/.oci/config`)

## Required/Optional Environment Variables

Set these before running if defaults are not correct for your environment:

```bash
export SOURCE_HOST="10.200.1.12"
export TARGET_HOST="10.200.0.250"
export SOURCE_ADMIN_USER="azureuser"
export TARGET_ADMIN_USER="opc"
export ORACLE_USER="oracle"
export ZDM_USER="zdmuser"

# Optional keys. Empty or <...> placeholder means SSH agent/default key is used.
export SOURCE_SSH_KEY="~/.ssh/source_key.pem"
export TARGET_SSH_KEY="~/.ssh/target_key.pem"
```

## Run

```bash
cd Artifacts/Phase10-Migration/Step2/Scripts
bash zdm_orchestrate_discovery.sh
```

Helpful options:

```bash
bash zdm_orchestrate_discovery.sh -h   # help
bash zdm_orchestrate_discovery.sh -c   # show effective config
bash zdm_orchestrate_discovery.sh -t   # connectivity tests only
bash zdm_orchestrate_discovery.sh -v   # verbose mode
```

## Output Locations

- Source outputs: `Artifacts/Phase10-Migration/Step2/Discovery/source/`
- Target outputs: `Artifacts/Phase10-Migration/Step2/Discovery/target/`
- ZDM server outputs: `Artifacts/Phase10-Migration/Step2/Discovery/server/`

Each discovery script writes:

- `zdm_<type>_discovery_<hostname>_<timestamp>.txt`
- `zdm_<type>_discovery_<hostname>_<timestamp>.json`

## Next Step

After running and collecting outputs, continue with:

`@Phase10-ZDM-Step3-Discovery-Questionnaire`
