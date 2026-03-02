# ZDM Migration — Step 0: Discovery Scripts
## Project: ORADB

This directory contains the read-only discovery scripts generated for the **ORADB** ZDM migration project.

---

## Scripts

| Script | Purpose | Target Server |
|--------|---------|---------------|
| `zdm_source_discovery.sh` | Collects Oracle DB config, TDE, schemas, backups, etc. from the **source** server | Source DB (`10.1.0.11`) |
| `zdm_target_discovery.sh` | Collects Oracle DB config, ASM storage, NSG rules, OCI connectivity from the **target** server | Target DB@Azure (`10.0.1.160`) |
| `zdm_server_discovery.sh` | Collects ZDM installation, OCI CLI config, SSH keys, and network connectivity from the **ZDM jumpbox** | ZDM Server (`10.1.0.8`) |
| `zdm_orchestrate_discovery.sh` | Orchestrates all three discovery scripts via SSH; collects output into `Step0/Discovery/` | Runs locally |

---

## Quick Start

### 1. Review configuration

```bash
bash zdm_orchestrate_discovery.sh --config
```

### 2. Test SSH connectivity

```bash
bash zdm_orchestrate_discovery.sh --test
```

### 3. Run full discovery

```bash
bash zdm_orchestrate_discovery.sh
```

With verbose SSH output:

```bash
bash zdm_orchestrate_discovery.sh --verbose
```

---

## Configuration

Default values come from [zdm-env.md](../../../../../prompts/Phase10-Migration/ZDM/zdm-env.md). Override any setting via environment variable before running the orchestration script:

```bash
# Override SSH admin users
export SOURCE_ADMIN_USER="azureuser"
export TARGET_ADMIN_USER="opc"
export ZDM_ADMIN_USER="azureuser"

# Override SSH key paths
export SOURCE_SSH_KEY="~/.ssh/odaa.pem"
export TARGET_SSH_KEY="~/.ssh/odaa.pem"
export ZDM_SSH_KEY="~/.ssh/zdm.pem"

# Force Oracle paths (leave blank for auto-detection)
export SOURCE_REMOTE_ORACLE_HOME=""
export SOURCE_ORACLE_SID=""
```

### Default Values (from zdm-env.md)

| Variable | Value |
|----------|-------|
| `SOURCE_HOST` | `10.1.0.11` |
| `TARGET_HOST` | `10.0.1.160` |
| `ZDM_HOST` | `10.1.0.8` |
| `SOURCE_ADMIN_USER` | `azureuser` |
| `TARGET_ADMIN_USER` | `opc` |
| `ZDM_ADMIN_USER` | `azureuser` |
| `SOURCE_SSH_KEY` | `~/.ssh/odaa.pem` |
| `TARGET_SSH_KEY` | `~/.ssh/odaa.pem` |
| `ZDM_SSH_KEY` | `~/.ssh/zdm.pem` |
| `ORACLE_USER` | `oracle` |
| `ZDM_USER` | `zdmuser` |

---

## SSH Authentication Model

Discovery scripts use the **admin-user-with-sudo** pattern. Direct SSH as `oracle` or `zdmuser` is not required.

```
Orchestration machine
      │
      ├──► SSH as SOURCE_ADMIN_USER (azureuser) → sudo -u oracle  (source SQL)
      ├──► SSH as TARGET_ADMIN_USER (opc)        → sudo -u oracle  (target SQL)
      └──► SSH as ZDM_ADMIN_USER   (azureuser)   → sudo -u zdmuser (ZDM CLI)
```

---

## Read-Only Constraint

> **CRITICAL:** All discovery scripts are strictly read-only. They perform no DDL, DML, or OS configuration changes. Only `SELECT` queries and OS read commands are used.

---

## Output Structure

After running the orchestration script, discovery output is collected to:

```
Artifacts/Phase10-Migration/ZDM/ORADB/Step0/
└── Discovery/
    ├── source/
    │   ├── zdm_source_discovery_<hostname>_<timestamp>.txt
    │   └── zdm_source_discovery_<hostname>_<timestamp>.json
    ├── target/
    │   ├── zdm_target_discovery_<hostname>_<timestamp>.txt
    │   └── zdm_target_discovery_<hostname>_<timestamp>.json
    └── server/
        ├── zdm_server_discovery_<hostname>_<timestamp>.txt
        └── zdm_server_discovery_<hostname>_<timestamp>.json
```

---

## Troubleshooting

### SSH key not found
The orchestration script runs an upfront SSH key diagnostic. If a key is missing, it logs:
```
[WARN]  SOURCE_SSH_KEY: /home/azureuser/.ssh/odaa.pem  [MISSING]
```
Set the correct path: `export SOURCE_SSH_KEY="/path/to/correct.pem"`

### Script syntax errors with `::` in error messages
This indicates Windows CRLF line endings. Convert before running:
```bash
sed -i 's/\r$//' zdm_orchestrate_discovery.sh zdm_source_discovery.sh \
    zdm_target_discovery.sh zdm_server_discovery.sh
```

### ZDM CLI not found
The ZDM server discovery script will auto-detect `ZDM_HOME` using multiple methods. If it fails, set an override:
```bash
export ZDM_REMOTE_ZDM_HOME="/u01/app/zdmhome"
bash zdm_orchestrate_discovery.sh
```

---

## Next Step

After collecting discovery output, proceed to:

**Step 1 — Discovery Questionnaire** (`../../../prompts/Phase10-Migration/ZDM/Step1-Discovery-Questionnaire.prompt.md`)

Use the discovery output files from `Step0/Discovery/` as input context for the Step 1 questionnaire.
