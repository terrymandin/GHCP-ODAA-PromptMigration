# Step 2: Discovery Scripts

Phase 10 ZDM Migration — Run scripts to collect technical context from all servers.

## Environment

| Variable | Value |
|----------|-------|
| Source Host | `10.1.0.11` |
| Target Host | `10.0.1.160` |
| Source SSH User | `azureuser` |
| Target SSH User | `opc` |
| SSH Key | `~/.ssh/odaa.pem` |

## Scripts

| Script | Purpose | Runs On |
|--------|---------|---------|
| `zdm_orchestrate_discovery.sh` | Master orchestrator — copy and execute the other three scripts | ZDM server (local) |
| `zdm_source_discovery.sh` | Discover source Oracle DB environment | Source DB server (via SSH) |
| `zdm_target_discovery.sh` | Discover Oracle Database@Azure environment | Target DB server (via SSH) |
| `zdm_server_discovery.sh` | Discover ZDM server installation and connectivity | ZDM server (local) |

## Usage

### Option A — Orchestrated (recommended)

Copy all scripts to the ZDM server and run the orchestrator as `zdmuser`:

```bash
# Copy scripts to ZDM server
scp -i ~/.ssh/odaa.pem Artifacts/Phase10-Migration/Step2/Scripts/*.sh azureuser@<ZDM_HOST>:~/

# SSH to ZDM server
ssh -i ~/.ssh/odaa.pem azureuser@<ZDM_HOST>

# Switch to zdmuser
sudo su - zdmuser

# Place scripts and run
mkdir -p ~/zdm_scripts && cp ~/*.sh ~/zdm_scripts/
chmod +x ~/zdm_scripts/*.sh
cd ~/zdm_scripts
./zdm_orchestrate_discovery.sh
```

Output is saved to `Artifacts/Phase10-Migration/Step2/Discovery/` relative to the repo root.

### Option B — Individual scripts

Run each discovery script individually on its respective server:

```bash
# Source server
scp -i ~/.ssh/odaa.pem zdm_source_discovery.sh azureuser@10.1.0.11:~/
ssh -i ~/.ssh/odaa.pem azureuser@10.1.0.11 "chmod +x ~/zdm_source_discovery.sh && ~/zdm_source_discovery.sh"

# Target server
scp -i ~/.ssh/odaa.pem zdm_target_discovery.sh opc@10.0.1.160:~/
ssh -i ~/.ssh/odaa.pem opc@10.0.1.160 "chmod +x ~/zdm_target_discovery.sh && ~/zdm_target_discovery.sh"

# ZDM server (local, as zdmuser)
chmod +x zdm_server_discovery.sh
SOURCE_HOST=10.1.0.11 TARGET_HOST=10.0.1.160 ./zdm_server_discovery.sh
```

## CLI Options (orchestrator)

```
./zdm_orchestrate_discovery.sh [-h] [-c] [-t] [-v]

  -h, --help     Show help
  -c, --config   Show configuration and exit
  -t, --test     Test SSH connectivity only
  -v, --verbose  Enable verbose SSH/SCP output
```

## Setting Required Password Variables

> ⚠️ **SECURITY**: Never commit passwords to source control.

Set these before running migration scripts (Step 4):

```bash
# On the ZDM server terminal
read -sp "SOURCE_SYS_PASSWORD: "        SOURCE_SYS_PASSWORD; echo; export SOURCE_SYS_PASSWORD
read -sp "SOURCE_TDE_WALLET_PASSWORD: " SOURCE_TDE_WALLET_PASSWORD; echo; export SOURCE_TDE_WALLET_PASSWORD
read -sp "TARGET_SYS_PASSWORD: "        TARGET_SYS_PASSWORD; echo; export TARGET_SYS_PASSWORD
```

## Environment Overrides

If Oracle or ZDM auto-detection fails, set these before running the orchestrator:

```bash
export SOURCE_REMOTE_ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1
export SOURCE_REMOTE_ORACLE_SID=oradb011       # For Exadata RAC: use instance SID (not db_name)
export TARGET_REMOTE_ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1
export TARGET_REMOTE_ORACLE_SID=oradb011
export ZDM_REMOTE_ZDM_HOME=/u01/app/zdmhome
```

> **ODAA / Exadata RAC note:** `/etc/oratab` returns `db_name` (e.g. `oradb01`), not the running
> RAC instance SID (e.g. `oradb011`). Set `TARGET_REMOTE_ORACLE_SID` to the Node 1 instance SID.
> Confirm with: `ps -ef | grep pmon` on the target node.

## Expected Output

After running, discovery files are committed to:

```
Artifacts/Phase10-Migration/Step2/
└── Discovery/
    ├── source/
    │   ├── zdm_source_discovery_<host>_<timestamp>.txt
    │   └── zdm_source_discovery_<host>_<timestamp>.json
    ├── target/
    │   ├── zdm_target_discovery_<host>_<timestamp>.txt
    │   └── zdm_target_discovery_<host>_<timestamp>.json
    └── server/
        ├── zdm_server_discovery_<host>_<timestamp>.txt
        └── zdm_server_discovery_<host>_<timestamp>.json
```

## Next Step

After collecting and committing discovery output:

```
@Phase10-ZDM-Step3-Discovery-Questionnaire
```
