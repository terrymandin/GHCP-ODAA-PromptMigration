# ZDM Discovery Scripts - PRODDB Migration

## Overview

This directory contains discovery scripts for the **PRODDB Migration to Oracle Database@Azure** project.

**Generated:** 2026-01-29

## Migration Details

| Property | Value |
|----------|-------|
| Project Name | PRODDB Migration to Oracle Database@Azure |
| Source Database | proddb01.corp.example.com |
| Target Database | proddb-oda.eastus.azure.example.com |
| ZDM Server | zdm-jumpbox.corp.example.com |

## SSH Key Configuration

| Server | SSH Key |
|--------|---------|
| Source | ~/.ssh/source_db_key |
| Target | ~/.ssh/oda_azure_key |
| ZDM | ~/.ssh/zdm_jumpbox_key |

## Scripts

| Script | Purpose | Run As |
|--------|---------|--------|
| `zdm_source_discovery.sh` | Discover source database configuration | oracle@source |
| `zdm_target_discovery.sh` | Discover target Oracle Database@Azure configuration | opc@target |
| `zdm_server_discovery.sh` | Discover ZDM jumpbox configuration | zdmuser@zdm |
| `zdm_orchestrate_discovery.sh` | Orchestrate all discoveries from a central location | local |

## Quick Start

### Option 1: Run Orchestration Script (Recommended)

```bash
# From this Scripts directory
cd Artifacts/Phase10-Migration/ZDM/PRODDB/Step0/Scripts

# Test connectivity first
./zdm_orchestrate_discovery.sh --test

# Run full discovery
./zdm_orchestrate_discovery.sh

# Results will be in ../Discovery/
```

### Option 2: Run Scripts Individually

```bash
# Source database discovery
scp -i ~/.ssh/source_db_key zdm_source_discovery.sh oracle@proddb01.corp.example.com:/tmp/
ssh -i ~/.ssh/source_db_key oracle@proddb01.corp.example.com "cd /tmp && chmod +x zdm_source_discovery.sh && ./zdm_source_discovery.sh"

# Target database discovery
scp -i ~/.ssh/oda_azure_key zdm_target_discovery.sh opc@proddb-oda.eastus.azure.example.com:/tmp/
ssh -i ~/.ssh/oda_azure_key opc@proddb-oda.eastus.azure.example.com "cd /tmp && chmod +x zdm_target_discovery.sh && ./zdm_target_discovery.sh"

# ZDM server discovery
scp -i ~/.ssh/zdm_jumpbox_key zdm_server_discovery.sh zdmuser@zdm-jumpbox.corp.example.com:/tmp/
ssh -i ~/.ssh/zdm_jumpbox_key zdmuser@zdm-jumpbox.corp.example.com "cd /tmp && chmod +x zdm_server_discovery.sh && ./zdm_server_discovery.sh"
```

## Custom Discovery Items

These scripts include additional discovery beyond the standard template:

### Source Database
- Tablespace autoextend settings
- Current backup schedule and retention
- Database links configured
- Materialized view refresh schedules
- Scheduler jobs that may need reconfiguration

### Target Database (Oracle Database@Azure)
- Available Exadata storage capacity
- Pre-configured PDBs
- Network security group rules

### ZDM Server
- Available disk space for ZDM operations (minimum 50GB recommended)
- Network latency to source and target (ping tests)

## Output Files

After running discovery, output files will be saved to:

```
../Discovery/
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

## Environment Variable Overrides

If auto-detection fails (e.g., non-standard installation paths), set these environment variables before running the orchestration script:

```bash
# Source database overrides
export SOURCE_REMOTE_ORACLE_HOME=/custom/path/to/oracle/home
export SOURCE_REMOTE_ORACLE_SID=PRODDB

# Target database overrides
export TARGET_REMOTE_ORACLE_HOME=/custom/path/to/oracle/home
export TARGET_REMOTE_ORACLE_SID=PRODDB

# ZDM server overrides
export ZDM_REMOTE_ZDM_HOME=/home/zdmuser/zdmhome
export ZDM_REMOTE_JAVA_HOME=/usr/java/jdk1.8.0

# Run orchestration
./zdm_orchestrate_discovery.sh
```

## Troubleshooting

### SSH Connection Issues

1. Verify SSH key permissions:
   ```bash
   chmod 600 ~/.ssh/source_db_key ~/.ssh/oda_azure_key ~/.ssh/zdm_jumpbox_key
   ```

2. Test connectivity manually:
   ```bash
   ssh -i ~/.ssh/source_db_key oracle@proddb01.corp.example.com "echo OK"
   ssh -i ~/.ssh/oda_azure_key opc@proddb-oda.eastus.azure.example.com "echo OK"
   ssh -i ~/.ssh/zdm_jumpbox_key zdmuser@zdm-jumpbox.corp.example.com "echo OK"
   ```

### Environment Variables Not Found

The scripts use multiple methods to detect environment variables:
1. Explicit overrides (highest priority)
2. Profile extraction (parses .bashrc/.bash_profile)
3. Auto-detection (searches common paths)

If auto-detection fails, use the environment variable overrides described above.

### Partial Failures

The scripts are designed to be resilient:
- Each discovery section continues even if previous sections fail
- The orchestration script continues even if one server fails
- Check the "Sections with errors" count in the output

## Next Steps

After running discovery:

1. **Review output files** in `../Discovery/`
2. **Proceed to Step 1** - Discovery Questionnaire
   - Use `prompts/Phase10-Migration/ZDM/Step1-Discovery-Questionnaire.prompt.md`
   - Attach discovery output files
   - Complete all sections including business decisions
3. **Save questionnaire** to `Artifacts/Phase10-Migration/ZDM/PRODDB/Step1/`
4. **Proceed to Step 2** - Generate Migration Artifacts
