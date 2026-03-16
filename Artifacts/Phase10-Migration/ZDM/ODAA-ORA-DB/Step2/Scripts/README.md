# ZDM Step 2 — Discovery Scripts

## Overview

These scripts gather read-only technical discovery data from the source database server,
target Oracle Database@Azure server, and ZDM server before migration begins.

**Project:** ODAA-ORA-DB  
**Step:** 2 of 5 — Discovery

---

## Prerequisites

Before running, ensure the following are in place on the **ZDM server** as `zdmuser`:

| Requirement | Detail |
|-------------|--------|
| ZDM server SSH access | You can SSH to the ZDM box as `zdmuser` |
| Source SSH access | `zdmuser` can SSH to `azureuser@10.200.1.12` without a password |
| Target SSH access | `zdmuser` can SSH to `opc@10.200.0.250` without a password |
| Public keys pre-authorised | No `-i` key flag needed — `authorized_keys` already configured |
| OCI CLI configured | `~/.oci/config` exists and `oci iam region list` works |
| Python 3 | Required for OCI metadata JSON parsing on target |

> **SSH key note:** `SOURCE_SSH_KEY` and `TARGET_SSH_KEY` default to empty, meaning the
> orchestrator relies on the SSH agent or `~/.ssh/id_rsa`. Set these variables only if you
> need to use a specific key file.

---

## Environment Variables

These variables can be set before running `zdm_orchestrate_discovery.sh` to override defaults:

```bash
# Required server configuration (defaults shown match zdm-env.md)
export SOURCE_HOST="10.200.1.12"
export TARGET_HOST="10.200.0.250"
export SOURCE_ADMIN_USER="azureuser"
export TARGET_ADMIN_USER="opc"
export ORACLE_USER="oracle"
export ZDM_USER="zdmuser"

# Optional SSH key overrides (leave empty to use SSH agent / default key)
export SOURCE_SSH_KEY=""
export TARGET_SSH_KEY=""

# Optional Oracle environment overrides (leave empty for auto-detection)
# Required for Exadata RAC: set TARGET_ORACLE_SID to instance SID on Node 1 (e.g. oradb011)
export SOURCE_REMOTE_ORACLE_HOME=""
export SOURCE_ORACLE_SID=""
export TARGET_REMOTE_ORACLE_HOME=""
export TARGET_ORACLE_SID=""
```

---

## How to Run

### 1. Copy scripts to the ZDM server

```bash
scp Scripts/zdm_*_discovery.sh azureuser@10.200.1.13:/home/zdmuser/step2/
```

### 2. SSH to the ZDM server and switch to zdmuser

```bash
ssh azureuser@10.200.1.13
sudo su - zdmuser
cd /home/zdmuser/step2
```

### 3. Run the orchestration script

```bash
# Full discovery (all three servers)
bash zdm_orchestrate_discovery.sh

# Connectivity test only (faster pre-check)
bash zdm_orchestrate_discovery.sh -t

# Show current configuration
bash zdm_orchestrate_discovery.sh -c

# Verbose output
bash zdm_orchestrate_discovery.sh -v
```

### 4. Retrieve output files

```bash
# From your local machine
scp -r azureuser@10.200.1.13:/home/zdmuser/step2/Discovery/ \
    Artifacts/Phase10-Migration/ZDM/ODAA-ORA-DB/Step2/Discovery/
```

---

## Output Files

All discovery output is written to the `Discovery/` subdirectory:

```
Step2/
├── Scripts/
│   ├── zdm_source_discovery.sh          # SOURCE server discovery
│   ├── zdm_target_discovery.sh          # TARGET server discovery
│   ├── zdm_server_discovery.sh          # ZDM server discovery (local)
│   ├── zdm_orchestrate_discovery.sh     # Master orchestration script
│   └── README.md                        # This file
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

Each script writes two files:
- **`.txt`** — Human-readable sections for each discovery area
- **`.json`** — Machine-readable summary with `status` (`success`/`partial`) and `warnings` array

---

## Troubleshooting

| Symptom | Resolution |
|---------|------------|
| `syntax error near unexpected token` | Script has CRLF line endings. Run: `sed -i 's/\r$//' script.sh` |
| `Permission denied (publickey)` | Ensure `authorized_keys` is configured on source/target for zdmuser |
| SQL sections show `ORA-01034` | Set `TARGET_ORACLE_SID` to Node 1 instance SID (e.g. `oradb011`). See zdm-env.md note |
| Script exits with RC=1 | One or more sections failed — review the `.txt` report for `[WARN]`/`[ERROR]` lines |
| `zdmcli not found` | Verify `ZDM_HOME` is set in zdmuser's `.bash_profile`; re-source with `. ~/.bash_profile` |

---

## Next Step

After all three discovery scripts complete successfully:

→ Proceed to **Step 3**: `@Phase10-ZDM-Step3-Discovery-Questionnaire`
