# Step 0: Discovery Scripts - PRODDB Migration

## Overview

This directory contains the discovery phase artifacts for the **PRODDB Migration to Oracle Database@Azure** project.

**Generated:** 2026-01-30

## Purpose

Step 0 generates and executes discovery scripts to gather comprehensive information about:
- Source database configuration and environment
- Target Oracle Database@Azure configuration
- ZDM jumpbox server setup and connectivity

This information is essential for completing the migration questionnaire (Step 1) and generating migration artifacts (Step 2).

## Directory Structure

```
Step0/
├── Scripts/                    # Discovery scripts
│   ├── zdm_source_discovery.sh
│   ├── zdm_target_discovery.sh
│   ├── zdm_server_discovery.sh
│   ├── zdm_orchestrate_discovery.sh
│   └── README.md
├── Discovery/                  # Output files (after execution)
│   ├── source/
│   ├── target/
│   └── server/
└── README.md                   # This file
```

## Migration Project Details

| Property | Value |
|----------|-------|
| Project Name | PRODDB Migration to Oracle Database@Azure |
| Source Database | proddb01.corp.example.com |
| Target Database | proddb-oda.eastus.azure.example.com |
| ZDM Server | zdm-jumpbox.corp.example.com |

## User Configuration

| Server | Admin User | SSH Key |
|--------|------------|---------|
| Source | oracle | ~/.ssh/onprem_oracle_key |
| Target | opc | ~/.ssh/oci_opc_key |
| ZDM | azureuser | ~/.ssh/azure_key |

| Role | User |
|------|------|
| Oracle Software Owner | oracle |
| ZDM Software Owner | zdmuser |

## Quick Start

```bash
cd Scripts/

# Make scripts executable
chmod +x *.sh

# Option 1: Run orchestration script (recommended)
./zdm_orchestrate_discovery.sh

# Option 2: Test connectivity first
./zdm_orchestrate_discovery.sh --test

# Option 3: View configuration
./zdm_orchestrate_discovery.sh --config
```

## Custom Discovery Items

The following additional discovery items are included per project requirements:

### Source Database
- ✅ Tablespace autoextend settings
- ✅ Backup schedule and retention (RMAN)
- ✅ Database links
- ✅ Materialized view refresh schedules
- ✅ Scheduler jobs

### Target Database (Oracle Database@Azure)
- ✅ Exadata storage capacity
- ✅ Pre-configured PDBs
- ✅ Network security information

### ZDM Server
- ✅ Disk space validation (50GB minimum)
- ✅ Network latency tests (ping)
- ✅ Port connectivity tests

## Next Steps

After completing Step 0:

1. **Review Discovery Output**
   - Check `Discovery/` subdirectories for output files
   - Review any warnings or errors in the text reports

2. **Proceed to Step 1: Discovery Questionnaire**
   ```
   @Step1-Discovery-Questionnaire.prompt.md
   
   Complete the questionnaire for PRODDB migration.
   
   [Attach discovery files from Step0/Discovery/]
   ```

3. **Proceed to Step 2: Generate Migration Artifacts**
   - RSP file
   - ZDM CLI commands
   - Migration runbook

## Troubleshooting

See `Scripts/README.md` for detailed troubleshooting guidance including:
- SSH connection issues
- Environment variable detection
- Script error handling
