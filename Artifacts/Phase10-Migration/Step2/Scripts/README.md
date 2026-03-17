# Step 2 Discovery Scripts

These scripts are generated for ZDM migration Step 2 and are designed to run on the jumpbox/ZDM server.

## Prerequisites

- Run as `zdmuser` on the ZDM server
- SSH access from ZDM server to source and target DB servers
- SSH keys available in `~/.ssh/` when key-based auth is used
- Oracle and ZDM utilities available on their respective hosts
- OCI configuration available on the ZDM host if required for your environment

## Runtime Configuration

Set environment variables before running if your runtime values differ from the rendered defaults:

```bash
export SOURCE_HOST="10.200.1.12"
export TARGET_HOST="10.200.0.250"

# Admin SSH users used for remote access
export SOURCE_ADMIN_USER="azureuser"
export TARGET_ADMIN_USER="opc"

# Optional SSH keys. Leave empty to use SSH agent/default key.
# Placeholder values (<...>) are treated as empty.
export SOURCE_SSH_KEY=""
export TARGET_SSH_KEY=""

# Optional Oracle and ZDM user overrides
export ORACLE_USER="oracle"
export ZDM_USER="zdmuser"
```

You can display the effective runtime settings with:

```bash
bash zdm_orchestrate_discovery.sh -c
```

## Run Discovery

```bash
cd Artifacts/Phase10-Migration/Step2/Scripts
bash zdm_orchestrate_discovery.sh
```

Optional modes:

```bash
bash zdm_orchestrate_discovery.sh -t   # connectivity checks only
bash zdm_orchestrate_discovery.sh -v   # verbose
bash zdm_orchestrate_discovery.sh -h   # help
```

## Output Files

The orchestrator collects outputs into:

- `Artifacts/Phase10-Migration/Step2/Discovery/source/`
- `Artifacts/Phase10-Migration/Step2/Discovery/target/`
- `Artifacts/Phase10-Migration/Step2/Discovery/server/`

Each script writes:

- `zdm_<type>_discovery_<hostname>_<timestamp>.txt`
- `zdm_<type>_discovery_<hostname>_<timestamp>.json`

## Important Notes

- Scripts are read-only and gather discovery details only
- `zdm-env.md` is generation-time input only; these scripts do not read it at runtime
- If any discovery report has `"status": "partial"`, review warnings before continuing

## Next Step

After collecting discovery outputs, continue with:

- `@Phase10-ZDM-Step3-Discovery-Questionnaire`
