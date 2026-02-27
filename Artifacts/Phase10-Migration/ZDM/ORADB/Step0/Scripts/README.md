# ZDM Discovery Scripts - ORADB

**Step 0: Discovery Scripts** for the ORADB migration project.

> Generated from: `prompts/Phase10-Migration/ZDM/Step0-Generate-Discovery-Scripts.prompt.md`  
> Configuration: `prompts/Phase10-Migration/ZDM/zdm-env.md`

---

## Project Configuration

| Variable | Value |
|---|---|
| PROJECT_NAME | ORADB |
| SOURCE_HOST | 10.1.0.11 |
| TARGET_HOST | 10.0.1.160 |
| ZDM_HOST | 10.1.0.8 |
| SOURCE_ADMIN_USER | azureuser |
| TARGET_ADMIN_USER | opc |
| ZDM_ADMIN_USER | azureuser |
| SOURCE_SSH_KEY | ~/.ssh/odaa.pem |
| TARGET_SSH_KEY | ~/.ssh/odaa.pem |
| ZDM_SSH_KEY | ~/.ssh/zdm.pem |
| ORACLE_USER | oracle |
| ZDM_USER | zdmuser |

---

## Scripts

| Script | Purpose |
|---|---|
| `zdm_orchestrate_discovery.sh` | **Master script** — orchestrates all discovery with one command |
| `zdm_source_discovery.sh` | Discovers source Oracle database server |
| `zdm_target_discovery.sh` | Discovers target Oracle Database@Azure server |
| `zdm_server_discovery.sh` | Discovers ZDM jumpbox server |

---

## Quick Start

### Step 1 — Set required passwords (do not save to repo)

```bash
export SOURCE_SYS_PASSWORD="..."
export TARGET_SYS_PASSWORD="..."
# export SOURCE_TDE_WALLET_PASSWORD="..."  # only if TDE enabled
```

### Step 2 — Run orchestration from this directory

```bash
cd Artifacts/Phase10-Migration/ZDM/ORADB/Step0/Scripts

# Option A: Run all discoveries
bash zdm_orchestrate_discovery.sh

# Option B: Test SSH connectivity first
bash zdm_orchestrate_discovery.sh --test

# Option C: Show configuration
bash zdm_orchestrate_discovery.sh --config

# Option D: Verbose mode
bash zdm_orchestrate_discovery.sh --verbose
```

### Step 3 — Review output

Discovery reports are collected to:
```
Artifacts/Phase10-Migration/ZDM/ORADB/Step0/Discovery/
  source/   zdm_source_discovery_<host>_<timestamp>.txt
            zdm_source_discovery_<host>_<timestamp>.json
  target/   zdm_target_discovery_<host>_<timestamp>.txt
            zdm_target_discovery_<host>_<timestamp>.json
  server/   zdm_server_discovery_<host>_<timestamp>.json
            zdm_server_discovery_<host>_<timestamp>.json
```

---

## SSH Authentication Pattern

Scripts connect as admin users and use `sudo -u oracle` (or `sudo -u zdmuser`) for privileged commands. Direct SSH as `oracle` is not used.

```
Orchestration Script (local machine)
    │
    ├── SSH as azureuser  →  source (10.1.0.11)   →  sudo -u oracle for SQL
    ├── SSH as opc        →  target (10.0.1.160)  →  sudo -u oracle for SQL
    └── SSH as azureuser  →  ZDM    (10.1.0.8)    →  sudo -u zdmuser for ZDM CLI
```

---

## Environment Variable Overrides

Override any default by setting environment variables before running:

```bash
# Server addresses
export SOURCE_HOST="10.1.0.11"
export TARGET_HOST="10.0.1.160"
export ZDM_HOST="10.1.0.8"

# SSH keys
export SOURCE_SSH_KEY="~/.ssh/odaa.pem"
export TARGET_SSH_KEY="~/.ssh/odaa.pem"
export ZDM_SSH_KEY="~/.ssh/zdm.pem"

# Remote path overrides (when auto-detection fails)
export SOURCE_REMOTE_ORACLE_HOME="/u01/app/oracle/product/19.0.0/dbhome_1"
export SOURCE_REMOTE_ORACLE_SID="ORCL"
export ZDM_REMOTE_ZDM_HOME="/u01/app/zdmhome"

# Custom output directory
export OUTPUT_DIR="/path/to/output"
```

---

## Troubleshooting

| Error | Resolution |
|---|---|
| `SSH key MISSING` in diagnostic | Verify key path with `ls -la ~/.ssh/` and set the correct `*_SSH_KEY` variable |
| `SSH connection FAILED` | Check host reachability, security group rules (port 22), and user access |
| `No output files found` | Run individual discovery script manually on the server to see errors |
| `bash: command not found` (with `::`) | Script has CRLF line endings — run `dos2unix` on the script file |
| `lsnrctl failed` | Oracle listener not running or ORACLE_HOME not auto-detected |
| `ZDM_HOME not detected` | Set `ZDM_REMOTE_ZDM_HOME` override variable |

---

## Next Step

After collecting discovery outputs, proceed to:  
**Step 1: Discovery Questionnaire** → `prompts/Phase10-Migration/ZDM/Step1-Discovery-Questionnaire.prompt.md`
