# Step 0: Discovery Scripts — ORADB

## Project Configuration

| Setting | Value |
|---------|-------|
| **Project Name** | ORADB |
| **Source Host** | 10.1.0.11 |
| **Target Host** | 10.0.1.160 |
| **ZDM Host** | 10.1.0.8 |
| **Source SSH User** | azureuser |
| **Target SSH User** | opc |
| **ZDM SSH User** | azureuser |
| **Source SSH Key** | `~/.ssh/odaa.pem` |
| **Target SSH Key** | `~/.ssh/odaa.pem` |
| **ZDM SSH Key** | `~/.ssh/zdm.pem` |
| **Oracle User** | oracle |
| **ZDM User** | zdmuser |

---

## Scripts

| Script | Purpose |
|--------|---------|
| `zdm_source_discovery.sh` | Read-only discovery on the **source** Oracle database server |
| `zdm_target_discovery.sh` | Read-only discovery on the **target** Oracle Database@Azure server |
| `zdm_server_discovery.sh` | Read-only discovery on the **ZDM jumpbox** server |
| `zdm_orchestrate_discovery.sh` | **Master orchestration** — copies and executes all three scripts via SSH |

---

## Quick Start

### Prerequisites

1. SSH keys deployed to `~/.ssh/` on the machine running this script (recommended: zdmuser on ZDM server):
   - `~/.ssh/odaa.pem` (for source and target)
   - `~/.ssh/zdm.pem` (for ZDM server)
2. Keys must have permissions `600`
3. Admin users (`azureuser`, `opc`) must be able to `sudo` on their respective servers

### Run Discovery

```bash
cd Artifacts/Phase10-Migration/ZDM/ORADB/Step0/Scripts/

# Make scripts executable
chmod +x *.sh

# Test SSH connectivity only
./zdm_orchestrate_discovery.sh --test

# View configuration
./zdm_orchestrate_discovery.sh --config

# Run full discovery
./zdm_orchestrate_discovery.sh

# Run with verbose SSH output (useful for debugging)
./zdm_orchestrate_discovery.sh --verbose
```

### Override Configuration

Environment variables override defaults from `zdm-env.md`:

```bash
# Override source host
SOURCE_HOST=10.1.0.11 ./zdm_orchestrate_discovery.sh

# Override SSH keys
SOURCE_SSH_KEY=~/.ssh/my_custom_key.pem ./zdm_orchestrate_discovery.sh

# Override output directory
OUTPUT_DIR=/tmp/my_discovery ./zdm_orchestrate_discovery.sh
```

### Set Required Passwords (Before Running Migration)

> ⚠️ **Never commit passwords to source control.**

Set these environment variables at runtime before executing ZDM migration scripts (Steps 2–3):

```bash
read -sp "SOURCE_SYS_PASSWORD: "         SOURCE_SYS_PASSWORD; echo; export SOURCE_SYS_PASSWORD
read -sp "SOURCE_TDE_WALLET_PASSWORD: "   SOURCE_TDE_WALLET_PASSWORD; echo; export SOURCE_TDE_WALLET_PASSWORD
read -sp "TARGET_SYS_PASSWORD: "         TARGET_SYS_PASSWORD; echo; export TARGET_SYS_PASSWORD
```

---

## Output Structure

After running the orchestration script, discovery results are saved to:

```
Artifacts/Phase10-Migration/ZDM/ORADB/Step0/Discovery/
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

## Migration Flow

```
Step 0: Generate & Run Discovery Scripts   ← YOU ARE HERE
         ↓
Step 1: Discovery Questionnaire
         (prompts/Phase10-Migration/ZDM/Step1-Discovery-Questionnaire.prompt.md)
         ↓
Step 2: Fix Issues
         ↓
Step 3: Generate Migration Artifacts & Run Migration
```

---

## Security Notes

- All discovery scripts are **strictly read-only** — no DDL, DML, or configuration changes
- SQL queries use `SELECT` only (no `ALTER`, `CREATE`, `DROP`, `INSERT`, `UPDATE`, `DELETE`)
- OS commands use read-only utilities (`cat`, `grep`, `ls`, `df`, `ps`, etc.)
- Output files are written only to the designated output directory
- SSH keys should reside in `~/.ssh/` with permissions `600`
- The orchestration script should run as `zdmuser` for proper key resolution

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `Permission denied (publickey)` | SSH key not found or wrong permissions | Check key at `~/.ssh/odaa.pem`, ensure perms `600` |
| `sudo: oracle: command not found` | sudo not configured for oracle user SQL | Ensure sudoers allows `azureuser` to run commands as `oracle` |
| `ORACLE_HOME not detected` | Oracle not installed or /etc/oratab missing | Set `ORACLE_HOME` and `ORACLE_SID` override env vars |
| `ZDM_HOME not detected` | ZDM installed under different path | Set `ZDM_HOME` override env var |
| Script fails with syntax errors | Windows CRLF line endings | Run `sed -i 's/\r$//' *.sh` or `dos2unix *.sh` on the Linux server |
