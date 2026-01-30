# ZDM Discovery Scripts - PRODDB Migration

## Overview

This directory contains discovery scripts generated for the **PRODDB Migration to Oracle Database@Azure** project.

**Generated:** 2026-01-30

## Server Configuration

| Server | Hostname | Admin User | SSH Key |
|--------|----------|------------|---------|
| Source Database | proddb01.corp.example.com | oracle | ~/.ssh/onprem_oracle_key |
| Target Database (ODA@Azure) | proddb-oda.eastus.azure.example.com | opc | ~/.ssh/oci_opc_key |
| ZDM Jumpbox | zdm-jumpbox.corp.example.com | azureuser | ~/.ssh/azure_key |

## Application Users

| User Type | Username | Purpose |
|-----------|----------|---------|
| Oracle User | oracle | Database software owner, runs SQL commands |
| ZDM User | zdmuser | ZDM software owner, runs ZDM CLI commands |

## Scripts

| Script | Purpose | Target Server |
|--------|---------|---------------|
| `zdm_source_discovery.sh` | Gather source database information | Source (proddb01) |
| `zdm_target_discovery.sh` | Gather target ODA@Azure information | Target (proddb-oda) |
| `zdm_server_discovery.sh` | Gather ZDM jumpbox information | ZDM Server |
| `zdm_orchestrate_discovery.sh` | Orchestrate all discoveries | Run from any machine |

## Quick Start

### Option 1: Use Orchestration Script (Recommended)

```bash
# Make scripts executable
chmod +x *.sh

# Run orchestration (uses pre-configured settings)
./zdm_orchestrate_discovery.sh

# Test connectivity first
./zdm_orchestrate_discovery.sh --test

# Show configuration
./zdm_orchestrate_discovery.sh --config
```

### Option 2: Run Scripts Individually

```bash
# 1. Source Database Discovery
scp -i ~/.ssh/onprem_oracle_key zdm_source_discovery.sh oracle@proddb01.corp.example.com:/tmp/
ssh -i ~/.ssh/onprem_oracle_key oracle@proddb01.corp.example.com "cd /tmp && chmod +x zdm_source_discovery.sh && ./zdm_source_discovery.sh"

# 2. Target Database Discovery  
scp -i ~/.ssh/oci_opc_key zdm_target_discovery.sh opc@proddb-oda.eastus.azure.example.com:/tmp/
ssh -i ~/.ssh/oci_opc_key opc@proddb-oda.eastus.azure.example.com "cd /tmp && chmod +x zdm_target_discovery.sh && ./zdm_target_discovery.sh"

# 3. ZDM Server Discovery
scp -i ~/.ssh/azure_key zdm_server_discovery.sh azureuser@zdm-jumpbox.corp.example.com:/tmp/
ssh -i ~/.ssh/azure_key azureuser@zdm-jumpbox.corp.example.com "cd /tmp && chmod +x zdm_server_discovery.sh && ./zdm_server_discovery.sh"

# 4. Collect results to Discovery folder
mkdir -p ../Discovery/source ../Discovery/target ../Discovery/server
scp -i ~/.ssh/onprem_oracle_key oracle@proddb01.corp.example.com:/tmp/zdm_source_discovery_*.{txt,json} ../Discovery/source/
scp -i ~/.ssh/oci_opc_key opc@proddb-oda.eastus.azure.example.com:/tmp/zdm_target_discovery_*.{txt,json} ../Discovery/target/
scp -i ~/.ssh/azure_key azureuser@zdm-jumpbox.corp.example.com:/tmp/zdm_server_discovery_*.{txt,json} ../Discovery/server/
```

## Environment Variable Overrides

If auto-detection fails on remote servers, set these before running the orchestration script:

```bash
# Source server overrides
export SOURCE_REMOTE_ORACLE_HOME=/u01/app/oracle/product/19.0.0.0/dbhome_1
export SOURCE_REMOTE_ORACLE_SID=PRODDB

# Target server overrides
export TARGET_REMOTE_ORACLE_HOME=/u01/app/oracle/product/19.0.0.0/dbhome_1
export TARGET_REMOTE_ORACLE_SID=PRODDB

# ZDM server overrides
export ZDM_REMOTE_ZDM_HOME=/home/zdmuser/zdmhome
export ZDM_REMOTE_JAVA_HOME=/usr/java/jdk1.8.0

# Then run
./zdm_orchestrate_discovery.sh
```

## Custom Discovery Items

The following additional discovery items were included per project requirements:

### Source Database
- Tablespace autoextend settings
- Backup schedule and retention (RMAN configuration)
- Database links
- Materialized view refresh schedules
- Scheduler jobs (DBMS_SCHEDULER and legacy DBMS_JOB)

### Target Database (Oracle Database@Azure)
- Exadata storage capacity (if applicable)
- Pre-configured PDBs
- Network security information

### ZDM Server
- Disk space validation (minimum 50GB recommended)
- Network latency tests (ping to source and target)
- Port connectivity tests (SSH and Oracle listener ports)

## Output Files

Discovery scripts produce two output files each:

| File Type | Description |
|-----------|-------------|
| `zdm_*_discovery_<hostname>_<timestamp>.txt` | Human-readable text report |
| `zdm_*_discovery_<hostname>_<timestamp>.json` | Machine-parseable JSON summary |

## Output Directory Structure

After running discovery:

```
PRODDB/
├── Step0/
│   ├── Scripts/           # Discovery scripts (this folder)
│   │   ├── zdm_source_discovery.sh
│   │   ├── zdm_target_discovery.sh
│   │   ├── zdm_server_discovery.sh
│   │   ├── zdm_orchestrate_discovery.sh
│   │   └── README.md
│   ├── Discovery/         # Discovery output (created after execution)
│   │   ├── source/
│   │   │   ├── zdm_source_discovery_proddb01_*.txt
│   │   │   └── zdm_source_discovery_proddb01_*.json
│   │   ├── target/
│   │   │   ├── zdm_target_discovery_proddb-oda_*.txt
│   │   │   └── zdm_target_discovery_proddb-oda_*.json
│   │   └── server/
│   │       ├── zdm_server_discovery_zdm-jumpbox_*.txt
│   │       └── zdm_server_discovery_zdm-jumpbox_*.json
│   └── README.md
├── Step1/                 # Questionnaire (after Step 1)
└── Step2/                 # Migration artifacts (after Step 2)
```

## Resilience Features

All scripts include:

1. **Continue on Failure** - Scripts continue running even if individual sections fail
2. **Auto-Detection** - Oracle and ZDM environments are auto-detected from:
   - /etc/oratab
   - Running processes
   - Common installation paths
3. **Environment Override Support** - Explicit overrides available when auto-detection fails
4. **Color-Coded Output** - Easy identification of success, warnings, and errors
5. **Partial Success Handling** - Orchestration continues even if some servers fail

## Troubleshooting

### SSH Connection Fails

```bash
# Test SSH manually
ssh -v -i ~/.ssh/onprem_oracle_key oracle@proddb01.corp.example.com

# Check SSH key permissions (should be 600)
chmod 600 ~/.ssh/onprem_oracle_key
```

### Environment Variables Not Set

If ORACLE_HOME or ZDM_HOME not detected:

1. Check if environment is set interactively:
   ```bash
   ssh -i <key> user@host "echo \$ORACLE_HOME"
   ```

2. If empty, use environment overrides (see above)

3. For persistent fix, add exports to `/etc/profile.d/` on remote servers

### Discovery Script Errors

- Scripts are designed to continue on errors
- Check the text report for `[WARNING]` and `[ERROR]` markers
- Individual section failures don't stop the overall discovery

## Next Steps

After completing discovery:

1. **Review Discovery Output** - Check all text and JSON files in `../Discovery/`
2. **Proceed to Step 1** - Use `Step1-Discovery-Questionnaire.prompt.md` with discovery files attached
3. **Complete Questionnaire** - Answer all questions including business decisions
4. **Proceed to Step 2** - Generate migration artifacts

## Support

For issues with these scripts, consult:
- ZDM Documentation: Oracle Zero Downtime Migration Guide
- Oracle Database@Azure Documentation
- Project migration runbook
