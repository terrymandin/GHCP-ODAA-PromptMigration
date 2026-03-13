# Step 2 — Discovery Scripts

## Purpose

These scripts collect read-only technical context from the source database server,
Oracle Database@Azure (ODAA/Exadata) target server, and the ZDM server itself.
The collected outputs form the foundation for the Step 3 discovery questionnaire
and all subsequent migration steps.

---

## Prerequisites

Before running these scripts, confirm:

1. **ZDM server account** — You must be logged in (or `sudo su -`) as `zdmuser` on the ZDM box.
2. **SSH keys in place** — The key files referenced below must exist under `~/.ssh/` with permissions `600`:
   ```
   chmod 600 ~/.ssh/odaa.pem
   ```
3. **SSH connectivity verified** — Step 1 (`zdm_test_ssh_connectivity.sh`) must have passed for both SOURCE and TARGET hosts.
4. **OCI CLI configured** — `~/.oci/config` must exist and have a valid API key for OCI operations.

---

## Environment Configuration

The orchestrator reads configuration from environment variables. The defaults
below match the values in `zdm-env.md` for this project:

| Variable | Default | Description |
|----------|---------|-------------|
| `SOURCE_HOST` | `10.1.0.11` | Source database server IP/hostname |
| `TARGET_HOST` | `10.0.1.160` | ODAA target server IP/hostname |
| `SOURCE_ADMIN_USER` | `azureuser` | SSH admin user on source |
| `TARGET_ADMIN_USER` | `opc` | SSH admin user on target |
| `SOURCE_SSH_KEY` | `~/.ssh/odaa.pem` | SSH private key for source (empty = SSH agent) |
| `TARGET_SSH_KEY` | `~/.ssh/odaa.pem` | SSH private key for target (empty = SSH agent) |
| `ORACLE_USER` | `oracle` | OS user that owns Oracle processes |
| `ZDM_USER` | `zdmuser` | ZDM software user |
| `SOURCE_REMOTE_ORACLE_HOME` | *(auto-detect)* | Override if auto-detection fails |
| `SOURCE_ORACLE_SID` | *(auto-detect)* | Override if auto-detection fails |
| `TARGET_REMOTE_ORACLE_HOME` | *(auto-detect)* | Override if auto-detection fails |
| `TARGET_ORACLE_SID` | *(auto-detect)* | Override if auto-detection fails |

> **ODAA / Exadata RAC note:** On the target, `/etc/oratab` returns the `db_name`
> (e.g. `oradb01`) rather than the running RAC instance SID (e.g. `oradb011`).
> If the target SQL sections fail, set `TARGET_ORACLE_SID` to the Node 1 instance
> SID (confirm with `ps -ef | grep pmon` on the target).

---

## How to Run

### Option 1: Full Discovery (recommended)

```bash
sudo su - zdmuser
cd /path/to/Artifacts/Phase10-Migration/Step2/Scripts
bash zdm_orchestrate_discovery.sh
```

### Option 2: Connectivity pre-check only

```bash
bash zdm_orchestrate_discovery.sh -t
```

### Option 3: Show resolved configuration

```bash
bash zdm_orchestrate_discovery.sh -c
```

### Option 4: Verbose SSH output (debugging)

```bash
bash zdm_orchestrate_discovery.sh -v
```

### Overriding environment variables

```bash
TARGET_ORACLE_SID=oradb011 \
SOURCE_SSH_KEY="" \
TARGET_SSH_KEY="" \
bash zdm_orchestrate_discovery.sh
```

---

## Running Individual Scripts

Each discovery script can also be run standalone on its respective server:

```bash
# Source — SSH in as azureuser, then:
bash zdm_source_discovery.sh

# Target — SSH in as opc, then:
TARGET_ORACLE_SID=oradb011 bash zdm_target_discovery.sh

# ZDM server — run locally as zdmuser:
SOURCE_HOST=10.1.0.11 TARGET_HOST=10.0.1.160 bash zdm_server_discovery.sh
```

---

## Output Files

After a successful run, discovery output is collected into:

```
Artifacts/Phase10-Migration/Step2/Discovery/
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

Each JSON summary includes:
- `status`: `"success"` or `"partial"`
- `warnings`: array of conditions requiring attention before migration

---

## Troubleshooting

| Symptom | Likely Cause | Resolution |
|---------|-------------|------------|
| `syntax error near unexpected token` | CRLF line endings | `sed -i 's/\r$//' *.sh` |
| `ORA-01034: ORACLE not available` on target | RAC SID mismatch | Set `TARGET_ORACLE_SID=<db_name>1` |
| `Permission denied (publickey)` | Key not found or wrong permissions | `chmod 600 ~/.ssh/odaa.pem`; verify key path |
| `SQL*Plus connectivity test failed` | Wrong SID or ORACLE_HOME | Set `SOURCE_ORACLE_SID` / `TARGET_ORACLE_SID` explicitly |
| `zdmservice status` fails | ZDM service not started | `${ZDM_HOME}/bin/zdmservice start` (outside discovery scope) |

---

## Next Step

After collecting discovery outputs and committing them:

> Continue with: `@Phase10-ZDM-Step3-Discovery-Questionnaire`
