# Step 2 Discovery Scripts

These scripts are generated from values in `zdm-env.md` at generation time, then committed to source control.
They do not require `zdm-env.md` at runtime.

## Files

- `zdm_source_discovery.sh`: Connects to the source server, collects host/Oracle discovery data, and writes reports under `../Discovery/source`.
- `zdm_target_discovery.sh`: Connects to the target server, collects host/Oracle discovery data, and writes reports under `../Discovery/target`.
- `zdm_server_discovery.sh`: Collects local ZDM jumpbox/server discovery data and writes reports under `../Discovery/server`.
- `zdm_orchestrate_discovery.sh`: Runs all three scripts and writes a summary under `../Discovery`.

## Generated Output Directories

- `../Discovery/source/`
- `../Discovery/target/`
- `../Discovery/server/`

## Prerequisites

- Run from the ZDM jumpbox/server clone as user `zdmuser`.
- SSH from jumpbox to source/target must already be working.
- If private keys are used, place them in `~/.ssh/` for `zdmuser` and use `chmod 600`.
- If key values were placeholders (for example `<source_key>.pem`), scripts use SSH agent/default key auth.

## Run

```bash
cd Artifacts/Phase10-Migration/Step2/Scripts
chmod +x zdm_*.sh
./zdm_orchestrate_discovery.sh
```

## Optional Runtime Overrides

You can override values without editing scripts:

```bash
SOURCE_ADMIN_USER=azureuser \
TARGET_ADMIN_USER=opc \
TARGET_ORACLE_SID=POCAKV1 \
./zdm_orchestrate_discovery.sh
```

Compatibility mapping in the orchestrator:

- `SOURCE_ADMIN_USER` defaults to `SOURCE_SSH_USER`
- `TARGET_ADMIN_USER` defaults to `TARGET_SSH_USER`

## Next Step

After discovery files are collected, proceed with Step 3 prompt:

`@Phase10-ZDM-Step3-Discovery-Questionnaire`
