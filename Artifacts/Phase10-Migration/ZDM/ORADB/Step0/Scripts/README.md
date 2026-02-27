# ZDM Discovery Scripts — Project ORADB

Generated: 2026-02-27

## Overview

This directory contains discovery scripts for the ZDM migration project **ORADB**. These scripts gather technical context from the source database, target Oracle Database@Azure, and ZDM server. The discovery outputs feed into Step 1 (Discovery Questionnaire) and all subsequent migration steps.

## Scripts

| Script | Purpose | Target Server |
|--------|---------|---------------|
| `zdm_source_discovery.sh` | Discovers source DB configuration | Source: `10.1.0.11` |
| `zdm_target_discovery.sh` | Discovers target DB configuration | Target: `10.0.1.160` |
| `zdm_server_discovery.sh` | Discovers ZDM server configuration | ZDM: `10.1.0.8` |
| `zdm_orchestrate_discovery.sh` | Orchestrates all three discoveries | Run locally |

## Additional Discovery Coverage

These scripts include **additional discovery** beyond the standard ZDM discovery requirements:

### Source Database (`zdm_source_discovery.sh`)
| Section | Additional Discovery |
|---------|---------------------|
| 12 | Tablespace autoextend settings (all data files and temp files) |
| 13 | Backup schedule and retention (RMAN config, job history, FRA settings) |
| 14 | Database links (all DBLinks with endpoints and owners) |
| 15 | Materialized view refresh schedules (refresh mode, next run, logs) |
| 16 | Scheduler jobs (non-system jobs, run history, programs, chains) |

### Target Database (`zdm_target_discovery.sh`)
| Section | Additional Discovery |
|---------|---------------------|
| 10 | Exadata/ASM storage capacity (disk groups, cell configuration, cellcli) |
| 11 | Pre-configured PDBs — detailed inventory (status, services, app containers) |
| 12 | Network Security Group (NSG) rules via OCI CLI |

### ZDM Server (`zdm_server_discovery.sh`)
| Section | Additional Discovery |
|---------|---------------------|
| 9 | Disk space for ZDM operations (minimum **25GB** recommended, per-path assessment) |
| 10 | Network latency to source and target (detailed ping stats, traceroute, port tests) |

## Quick Start

### Option 1: Orchestrated (Recommended)

Run all discoveries from your local machine:

```bash
cd Artifacts/Phase10-Migration/ZDM/ORADB/Step0/Scripts

# Test SSH connectivity first
./zdm_orchestrate_discovery.sh --test

# Run full discovery
./zdm_orchestrate_discovery.sh
```

### Option 2: Manual (Run each script individually)

```bash
# Source discovery
ssh -i ~/.ssh/odaa.pem azureuser@10.1.0.11 'bash -l -s' < zdm_source_discovery.sh

# Target discovery
ssh -i ~/.ssh/odaa.pem opc@10.0.1.160 'bash -l -s' < zdm_target_discovery.sh

# ZDM Server discovery (pass source and target hosts for connectivity tests)
ssh -i ~/.ssh/zdm.pem azureuser@10.1.0.8 \
    'SOURCE_HOST="10.1.0.11" TARGET_HOST="10.0.1.160" bash -l -s' \
    < zdm_server_discovery.sh
```

## Configuration (from `zdm-env.md`)

| Parameter | Value |
|-----------|-------|
| `PROJECT_NAME` | ORADB |
| `SOURCE_HOST` | 10.1.0.11 |
| `TARGET_HOST` | 10.0.1.160 |
| `ZDM_HOST` | 10.1.0.8 |
| `SOURCE_SSH_USER` | azureuser |
| `TARGET_SSH_USER` | opc |
| `ZDM_SSH_USER` | azureuser |
| `SOURCE_SSH_KEY` | `~/.ssh/odaa.pem` |
| `TARGET_SSH_KEY` | `~/.ssh/odaa.pem` |
| `ZDM_SSH_KEY` | `~/.ssh/zdm.pem` |
| `ORACLE_USER` | oracle |
| `ZDM_SOFTWARE_USER` | zdmuser |

## Environment Overrides

Override any default before running:

```bash
# Override SSH keys
export SOURCE_SSH_KEY="/path/to/source.pem"
export TARGET_SSH_KEY="/path/to/target.pem"
export ZDM_SSH_KEY="/path/to/zdm.pem"

# Override Oracle paths if auto-detection fails
export SOURCE_REMOTE_ORACLE_HOME="/u01/app/oracle/product/19.0.0.0/dbhome_1"
export SOURCE_REMOTE_ORACLE_SID="PRODDB"

# OCI configuration for NSG and storage queries
export OCI_COMPARTMENT_OCID="ocid1.compartment.oc1..aaaaaaaas4upnqj72dfiivgwvn3uui5gkxo7ng6leeoifucbjiy326urbhmq"

./zdm_orchestrate_discovery.sh
```

## Output Location

Discovery results are collected to:
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

## Troubleshooting

### SSH Connection Fails
```bash
# Test manually
ssh -i ~/.ssh/odaa.pem -o ConnectTimeout=10 azureuser@10.1.0.11 "hostname"
# If this fails, check:
# 1. Key permissions: chmod 600 ~/.ssh/odaa.pem
# 2. Network connectivity / firewall rules
# 3. Correct username for the server
```

### Oracle Auto-Detection Fails
```bash
# Set explicit overrides
export SOURCE_REMOTE_ORACLE_HOME="/u01/app/oracle/product/19.0.0.0/dbhome_1"
export SOURCE_REMOTE_ORACLE_SID="YOURDBNAME"
./zdm_orchestrate_discovery.sh
```

### Script Fails with CRLF Errors
```bash
# Convert line endings on the target server
dos2unix zdm_source_discovery.sh
# Or:
sed -i 's/\r$//' zdm_source_discovery.sh
```

### ZDM Discovery Cannot Find ZDM_HOME
The ZDM discovery script searches for ZDM_HOME using multiple methods. If all fail:
```bash
# Pass the ZDM_HOME override explicitly
ssh -i ~/.ssh/zdm.pem azureuser@10.1.0.8 \
    'ZDM_HOME_OVERRIDE="/u01/app/zdmhome" SOURCE_HOST="10.1.0.11" TARGET_HOST="10.0.1.160" bash -l -s' \
    < zdm_server_discovery.sh
```

## Next Steps

After collecting discovery output:
1. Review all `.txt` files in `Step0/Discovery/`
2. Proceed to **Step 1**: `prompts/Phase10-Migration/ZDM/Step1-Discovery-Questionnaire.prompt.md`
