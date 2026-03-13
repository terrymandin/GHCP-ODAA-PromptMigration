# ZDM Step 2: Discovery Scripts

Phase 10 Migration — Step 2 discovery scripts for read-only environment collection.

## Overview

These scripts gather technical context from all three environments required for a ZDM migration:

| Script | Runs On | Purpose |
|--------|---------|---------|
| `zdm_orchestrate_discovery.sh` | ZDM Server | Orchestrates all discovery — **start here** |
| `zdm_source_discovery.sh` | Source DB Server | Oracle source database & OS discovery |
| `zdm_target_discovery.sh` | Target DB Server | Oracle Database@Azure / ODAA discovery |
| `zdm_server_discovery.sh` | ZDM Server | ZDM installation, OCI CLI, network connectivity |

> **READ-ONLY**: All scripts are strictly read-only. They make no changes to any server, database, or OS configuration.

---

## Quick Start

Run the orchestration script from the ZDM server as `zdmuser`:

```bash
# 1. Upload scripts to ZDM server
scp -i ~/.ssh/odaa.pem Scripts/*.sh azureuser@<zdm-server-ip>:/tmp/zdm_step2/

# 2. SSH to ZDM server and switch to zdmuser
ssh -i ~/.ssh/odaa.pem azureuser@<zdm-server-ip>
sudo su - zdmuser

# 3. Copy scripts to zdmuser home, make executable
cp /tmp/zdm_step2/*.sh ~/zdm_discovery/
chmod +x ~/zdm_discovery/*.sh

# 4. Run orchestrated discovery (all 3 servers in sequence)
cd ~/zdm_discovery/
./zdm_orchestrate_discovery.sh
```

Discovery output files are automatically collected to:
```
Artifacts/Phase10-Migration/Step2/Discovery/
├── source/   ← source database discovery output
├── target/   ← target database discovery output
└── server/   ← ZDM server discovery output
```

---

## Configuration

The orchestration script reads values from `zdm-env.md`. The key variables are pre-populated from your environment file:

| Variable | Value | Description |
|----------|-------|-------------|
| `SOURCE_HOST` | `10.1.0.11` | Source database server IP |
| `SOURCE_ADMIN_USER` | `azureuser` | Admin SSH user for source |
| `SOURCE_SSH_KEY` | `~/.ssh/odaa.pem` | SSH key for source |
| `TARGET_HOST` | `10.0.1.160` | Target database server IP |
| `TARGET_ADMIN_USER` | `opc` | Admin SSH user for target |
| `TARGET_SSH_KEY` | `~/.ssh/odaa.pem` | SSH key for target |
| `ORACLE_USER` | `oracle` | Oracle software owner |
| `ZDM_USER` | `zdmuser` | ZDM software owner |

Override any variable at runtime:

```bash
SOURCE_HOST=10.1.0.20 ./zdm_orchestrate_discovery.sh
```

---

## SSH Authentication Model

Scripts SSH as the admin user with `sudo -u oracle` for database commands — not directly as `oracle`:

```
ZDM Server (zdmuser)
    │
    ├──► SSH as SOURCE_ADMIN_USER (azureuser) ──► sudo -u oracle (SQL)
    │
    └──► SSH as TARGET_ADMIN_USER (opc) ──► sudo -u oracle (SQL)
```

---

## CLI Options

```bash
./zdm_orchestrate_discovery.sh          # Full discovery (all 3 servers)
./zdm_orchestrate_discovery.sh -t       # Test SSH connectivity only
./zdm_orchestrate_discovery.sh -c       # Display configuration and exit
./zdm_orchestrate_discovery.sh -v       # Verbose SSH/SCP output
./zdm_orchestrate_discovery.sh -h       # Show help
```

---

## Oracle Environment Overrides

If auto-detection fails (common with ODAA/Exadata RAC where `/etc/oratab` returns `db_name` instead of instance SID), set overrides before running:

```bash
# Source overrides
export SOURCE_ORACLE_SID="oradb011"           # RAC Node 1 instance SID
export SOURCE_REMOTE_ORACLE_HOME="/u01/app/oracle/product/19.0.0.0/dbhome_1"

# Target overrides
export TARGET_ORACLE_SID="oradb011"           # Use instance SID (e.g. dbname + "1")
export TARGET_REMOTE_ORACLE_HOME="/u01/app/oracle/product/19.0.0.0/dbhome_1"
```

> **Exadata RAC tip:** Run `ps -ef | grep pmon` on the target node to find the running instance SID.

---

## Output Format

Each discovery script produces two files:

| File | Format | Contents |
|------|--------|----------|
| `zdm_*_discovery_<hostname>_<timestamp>.txt` | Human-readable | Full discovery report with all sections |
| `zdm_*_discovery_<hostname>_<timestamp>.json` | JSON | Structured summary for programmatic use |

---

## Line Endings

Scripts use Unix LF line endings. If transferred from Windows and you see errors like:
```
bash: syntax error near unexpected token `}'
```

Convert line endings on the ZDM server:
```bash
sed -i 's/\r$//' *.sh
```

---

## Next Step

After collecting discovery outputs and committing them to the repository:

```
@Phase10-ZDM-Step3-Discovery-Questionnaire
```
