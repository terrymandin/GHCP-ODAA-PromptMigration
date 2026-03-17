# Step 2 Discovery Scripts

This folder contains read-only discovery scripts for ZDM migration planning.

## Scripts

- `zdm_source_discovery.sh`: Runs on the source DB server (via SSH), collects source DB and OS details.
- `zdm_target_discovery.sh`: Runs on the target DB server (via SSH), collects target DB and OS details.
- `zdm_server_discovery.sh`: Runs locally on the ZDM server as `zdmuser`.
- `zdm_orchestrate_discovery.sh`: Master script that copies/runs discovery scripts and gathers outputs.

## Prerequisites

- Run as `zdmuser` on the ZDM server.
- SSH access from ZDM server to source and target hosts.
- Private keys available in `~/.ssh` and permissions set to `600`.
- `sudo -u oracle` available on source/target host for SQL execution.
- OCI config available for zdmuser if your environment requires it (`~/.oci/config`).

## Environment Variables

Set these before running the orchestrator (or export in your shell profile):

- `SOURCE_HOST` (required)
- `TARGET_HOST` (required)
- `SOURCE_ADMIN_USER` (optional; default: `SOURCE_SSH_USER` then `azureuser`)
- `TARGET_ADMIN_USER` (optional; default: `TARGET_SSH_USER` then `azureuser`)
- `ORACLE_USER` (optional; default: `oracle`)
- `ZDM_USER` (optional; default: `zdmuser`)
- `SOURCE_SSH_KEY` (optional; if empty, SSH agent/default key is used)
- `TARGET_SSH_KEY` (optional; if empty, SSH agent/default key is used)

Optional DB overrides used by source/target scripts:

- `SOURCE_REMOTE_ORACLE_HOME`
- `SOURCE_ORACLE_SID`
- `TARGET_REMOTE_ORACLE_HOME`
- `TARGET_ORACLE_SID`
- `SOURCE_DATABASE_UNIQUE_NAME`
- `TARGET_DATABASE_UNIQUE_NAME`
- `ZDM_HOME`

## Run

From this `Scripts` folder:

```bash
bash zdm_orchestrate_discovery.sh
```

Useful options:

```bash
bash zdm_orchestrate_discovery.sh -h   # help
bash zdm_orchestrate_discovery.sh -c   # show resolved config
bash zdm_orchestrate_discovery.sh -t   # connectivity test only
bash zdm_orchestrate_discovery.sh -v   # verbose mode
```

## Output Locations

- Source outputs: `Artifacts/Phase10-Migration/Step2/Discovery/source/`
- Target outputs: `Artifacts/Phase10-Migration/Step2/Discovery/target/`
- ZDM server outputs: `Artifacts/Phase10-Migration/Step2/Discovery/server/`

Each script writes:

- `zdm_<type>_discovery_<hostname>_<timestamp>.txt`
- `zdm_<type>_discovery_<hostname>_<timestamp>.json`

JSON includes top-level `status` and a `warnings` array.

## Next Step

After collecting discovery outputs, continue with Step 3:

- `@Phase10-ZDM-Step3-Discovery-Questionnaire`
