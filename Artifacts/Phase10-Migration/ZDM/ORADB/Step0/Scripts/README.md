# ZDM Discovery Scripts — ORADB

**Project:** ORADB Migration to Oracle Database@Azure  
**Step:** 0 — Run Scripts to Get Context  
**Generated:** 2026-02-26

---

## Overview

These scripts gather technical discovery data from all three servers involved in the ZDM migration. The orchestration script coordinates the collection automatically, or each script can be run manually.

## Server Roles

| Server | Hostname | SSH User | Application User |
|--------|----------|----------|-----------------|
| Source Database | `proddb01.corp.example.com` | `oracle` | `oracle` |
| Target Oracle DB@Azure | `proddb-oda.eastus.azure.example.com` | `opc` | `oracle` |
| ZDM Jumpbox | `zdm-jumpbox.corp.example.com` | `azureuser` | `zdmuser` |

## SSH Key Configuration

| Server | Key Variable | Default Path |
|--------|-------------|--------------|
| Source | `SOURCE_SSH_KEY` | `~/.ssh/onprem_oracle_key` |
| Target | `TARGET_SSH_KEY` | `~/.ssh/oci_opc_key` |
| ZDM    | `ZDM_SSH_KEY`    | `~/.ssh/azure_key` |

---

## Quick Start

```bash
cd Artifacts/Phase10-Migration/ZDM/ORADB/Step0/Scripts

# Make scripts executable (if not already)
chmod +x *.sh

# Test connectivity first
./zdm_orchestrate_discovery.sh --test

# Run full discovery
./zdm_orchestrate_discovery.sh
```

Results are collected to `../Discovery/source/`, `../Discovery/target/`, and `../Discovery/server/`.

---

## Script Descriptions

### `zdm_orchestrate_discovery.sh`
**Run this one.** Copies each discovery script to its respective server via SCP, executes it in a login shell, and collects the output files back to the `Discovery/` directory. Continues even if one or two servers fail.

**Options:**
```
-h, --help      Show help
-c, --config    Show current configuration and exit
-t, --test      SSH connectivity test only (no discovery)
```

### `zdm_source_discovery.sh`
Runs on `proddb01.corp.example.com`. Discovers Oracle version, database configuration, character set, TDE status, supplemental logging, redo/archive config, network config, schemas, tablespace autoextend settings, backup schedule, database links, materialized view refresh schedules, and scheduler jobs.

### `zdm_target_discovery.sh`
Runs on `proddb-oda.eastus.azure.example.com`. Discovers Oracle/Grid version, CDB/PDB configuration, Exadata/ASM storage capacity, pre-configured PDBs, TDE status, RAC/CRS status, OCI/Azure integration, and network security group rules.

### `zdm_server_discovery.sh`
Runs on `zdm-jumpbox.corp.example.com`. Discovers ZDM installation and service status, Java configuration, OCI CLI setup, disk space (minimum 50GB check), SSH keys, and network latency/port-level connectivity to the source and target servers.

---

## Environment Variable Overrides

Set these before running if auto-detection fails:

```bash
# If Oracle homes are in non-standard locations
export SOURCE_REMOTE_ORACLE_HOME=/u01/app/oracle/product/19c/dbhome_1
export SOURCE_REMOTE_ORACLE_SID=ORADB
export TARGET_REMOTE_ORACLE_HOME=/u02/app/oracle/product/19c/dbhome_1
export TARGET_REMOTE_ORACLE_SID=ORADB

# If ZDM is in a non-standard location
export ZDM_REMOTE_ZDM_HOME=/home/zdmuser/zdmhome
export ZDM_REMOTE_JAVA_HOME=/usr/java/latest

# Then run
./zdm_orchestrate_discovery.sh
```

---

## Output Files

After successful execution:

```
Discovery/
├── source/
│   ├── zdm_source_discovery_<hostname>_<timestamp>.txt   ← human-readable report
│   ├── zdm_source_discovery_<hostname>_<timestamp>.json  ← machine-readable summary
│   └── zdm_source_discovery_sh_console.log               ← SSH execution log
├── target/
│   ├── zdm_target_discovery_<hostname>_<timestamp>.txt
│   ├── zdm_target_discovery_<hostname>_<timestamp>.json
│   └── zdm_target_discovery_sh_console.log
└── server/
    ├── zdm_server_discovery_<hostname>_<timestamp>.txt
    ├── zdm_server_discovery_<hostname>_<timestamp>.json
    └── zdm_server_discovery_sh_console.log
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Script exits after banner with no output | Invalid SSH key path | Run `--config` to check key paths; run `--test` to validate connectivity |
| `ORACLE_HOME not detected` | Profile not sourced in non-interactive SSH | Set `SOURCE_REMOTE_ORACLE_HOME` override |
| `ZDM_HOME not detected` | ZDM installed under non-standard path | Set `ZDM_REMOTE_ZDM_HOME` override |
| SQL returns `ERROR: ORACLE_HOME or ORACLE_SID not set` | Auto-detection failed | Set `SOURCE_REMOTE_ORACLE_SID` override |
| `Permission denied` on SQL | oracle user sudo not configured | Ensure `ADMIN_USER` has passwordless sudo to oracle |

### Line Ending Issues (Windows → Linux)

If scripts were edited on Windows, convert line endings before running:

```bash
sed -i 's/\r$//' *.sh
# or
dos2unix *.sh
```

---

## Next Step

After collecting discovery files, proceed to **Step 1: Discovery Questionnaire**:

```
prompts/Phase10-Migration/ZDM/Step1-Discovery-Questionnaire.prompt.md
```

Attach the `.txt` and `.json` files from `Discovery/` to the prompt.
