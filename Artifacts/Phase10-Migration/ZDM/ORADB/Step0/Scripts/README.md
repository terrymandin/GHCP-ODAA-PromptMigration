# Step 0: ZDM Discovery Scripts — Project ORADB

Generated discovery scripts for Oracle ZDM migration from on-premise Oracle to Oracle Database@Azure.

---

## Project Configuration

| Variable | Value |
|---|---|
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

## Scripts

| Script | Purpose |
|---|---|
| `zdm_orchestrate_discovery.sh` | **Run this one.** Orchestrates all three discovery scripts remotely. |
| `zdm_source_discovery.sh` | Discovers source Oracle database configuration. |
| `zdm_target_discovery.sh` | Discovers target Oracle Database@Azure configuration. |
| `zdm_server_discovery.sh` | Discovers ZDM jumpbox server configuration. |

---

## Quick Start

### 1. Make scripts executable

```bash
chmod +x Artifacts/Phase10-Migration/ZDM/ORADB/Step0/Scripts/*.sh
```

### 2. Verify configuration (optional)

```bash
./zdm_orchestrate_discovery.sh -c
```

### 3. Test SSH connectivity

```bash
./zdm_orchestrate_discovery.sh -t
```

### 4. Run full discovery

```bash
./zdm_orchestrate_discovery.sh
```

Output files are saved to `Artifacts/Phase10-Migration/ZDM/ORADB/Step0/Discovery/`.

---

## SSH Authentication Pattern

These scripts use a **secure admin-user-with-sudo** pattern:

```
Orchestrator (local)
    │
    ├──► SSH as azureuser  ──► SOURCE (10.1.0.11)  ──► sudo -u oracle (SQL)
    │
    ├──► SSH as opc        ──► TARGET (10.0.1.160) ──► sudo -u oracle (SQL)
    │
    └──► SSH as azureuser  ──► ZDM    (10.1.0.8)   ──► sudo -u zdmuser (ZDM CLI)
```

---

## Environment Variable Overrides

Override any default via shell environment before running:

```bash
# Example: different source SSH key
export SOURCE_SSH_KEY=~/.ssh/prod_key.pem
./zdm_orchestrate_discovery.sh

# Example: force Oracle home (if auto-detection fails)
export SOURCE_REMOTE_ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1
export SOURCE_REMOTE_ORACLE_SID=PRODDB
./zdm_orchestrate_discovery.sh
```

---

## Security: Password Variables

> **NEVER commit passwords to source control.**

Password variables are required for Step 2 migration scripts. Set them securely at runtime:

```bash
read -sp "Enter SOURCE_SYS_PASSWORD: " SOURCE_SYS_PASSWORD; echo; export SOURCE_SYS_PASSWORD
read -sp "Enter SOURCE_TDE_WALLET_PASSWORD: " SOURCE_TDE_WALLET_PASSWORD; echo; export SOURCE_TDE_WALLET_PASSWORD
read -sp "Enter TARGET_SYS_PASSWORD: " TARGET_SYS_PASSWORD; echo; export TARGET_SYS_PASSWORD
```

---

## Output Structure

```
Artifacts/Phase10-Migration/ZDM/ORADB/Step0/
├── Scripts/
│   ├── zdm_orchestrate_discovery.sh       ← Run this
│   ├── zdm_source_discovery.sh
│   ├── zdm_target_discovery.sh
│   ├── zdm_server_discovery.sh
│   └── README.md
└── Discovery/                             ← Populated after running orchestrator
    ├── source/
    │   ├── zdm_source_discovery_<hostname>_<ts>.txt
    │   └── zdm_source_discovery_<hostname>_<ts>.json
    ├── target/
    │   ├── zdm_target_discovery_<hostname>_<ts>.txt
    │   └── zdm_target_discovery_<hostname>_<ts>.json
    └── server/
        ├── zdm_server_discovery_<hostname>_<ts>.txt
        └── zdm_server_discovery_<hostname>_<ts>.json
```

---

## Troubleshooting

### CRLF line ending errors

If you see errors like `bash: line NNN: xxx:: command not found`, convert to Unix line endings:

```bash
sed -i 's/\r$//' *.sh
```

### SSH key not found

The orchestrator logs a full SSH key diagnostic at startup. If a key is reported as MISSING, override the path:

```bash
export SOURCE_SSH_KEY=/correct/path/to/key.pem
```

### Oracle environment not detected

Set overrides before running:

```bash
export SOURCE_REMOTE_ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1
export SOURCE_REMOTE_ORACLE_SID=ORADB
```

---

## Next Step

After collecting discovery output files, proceed to:  
**Step 1: Discovery Questionnaire** — `prompts/Phase10-Migration/ZDM/Step1-Discovery-Questionnaire.prompt.md`
