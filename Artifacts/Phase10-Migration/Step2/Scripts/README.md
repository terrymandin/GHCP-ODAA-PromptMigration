# Phase 10 - Step 2 Discovery Scripts

This folder contains generated, runtime-independent Step 2 discovery scripts for ZDM migration planning.

`zdm-env.md` was used as generation input only. These scripts do not read or depend on `zdm-env.md` at runtime.

## Prerequisites

- Run on the jumpbox/ZDM server as `zdmuser`.
- SSH connectivity from ZDM host to source and target DB hosts.
- Required SSH keys are available in `/home/zdmuser/.ssh` with `600` permissions (or SSH agent configured).
- `sudo -u oracle` is allowed on source/target hosts for SQL discovery.
- ZDM software installed and accessible for local ZDM server discovery.
- OCI config available under `~/.oci/config` when applicable.

## Generated Scripts

- `zdm_source_discovery.sh`
- `zdm_target_discovery.sh`
- `zdm_server_discovery.sh`
- `zdm_orchestrate_discovery.sh`

All scripts are read-only and only collect metadata/report output.

## Environment Variables

Set these before running orchestrator (examples shown with generated defaults):

```bash
export SOURCE_HOST="10.200.1.12"
export TARGET_HOST="10.200.0.250"
export SOURCE_ADMIN_USER="azureuser"
export TARGET_ADMIN_USER="opc"
export ORACLE_USER="oracle"
export ZDM_USER="zdmuser"

# Optional: leave empty to use SSH agent/default key
export SOURCE_SSH_KEY=""
export TARGET_SSH_KEY=""

# Optional ORACLE_HOME / SID overrides passed to remote discovery scripts
export SOURCE_REMOTE_ORACLE_HOME="/u01/app/oracle/product/19.0.0/dbhome_1"
export SOURCE_ORACLE_SID="POCAKV"
export TARGET_REMOTE_ORACLE_HOME="/u02/app/oracle/product/19.0.0.0/dbhome_1"
export TARGET_ORACLE_SID="POKAKV1"
```

## Run

From this directory:

```bash
bash zdm_orchestrate_discovery.sh
```

Useful options:

```bash
bash zdm_orchestrate_discovery.sh -h   # help
bash zdm_orchestrate_discovery.sh -c   # show effective config
bash zdm_orchestrate_discovery.sh -t   # connectivity test only
bash zdm_orchestrate_discovery.sh -v   # verbose mode
```

## Output Files

Outputs are collected under:

- `Artifacts/Phase10-Migration/Step2/Discovery/source/`
- `Artifacts/Phase10-Migration/Step2/Discovery/target/`
- `Artifacts/Phase10-Migration/Step2/Discovery/server/`

Each script generates:

- `zdm_<type>_discovery_<hostname>_<timestamp>.txt`
- `zdm_<type>_discovery_<hostname>_<timestamp>.json`

JSON includes top-level `status` (`success` or `partial`) and `warnings`.

## Next Step

After discovery outputs are reviewed and committed, continue with Step 3:

`@Phase10-ZDM-Step3-Discovery-Questionnaire`
