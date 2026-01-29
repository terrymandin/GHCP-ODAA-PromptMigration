# ZDM Migration Step 0: Discovery Scripts

**Project:** PRODDB Migration to Oracle Database@Azure  
**Generated:** 2026-01-29

## Overview

This directory contains Step 0 artifacts for the PRODDB migration - the discovery scripts and collected discovery data.

## Directory Structure

```
Step0/
├── Scripts/                              # Discovery scripts
│   ├── zdm_source_discovery.sh          # Source database discovery
│   ├── zdm_target_discovery.sh          # Target ODA@Azure discovery
│   ├── zdm_server_discovery.sh          # ZDM jumpbox discovery
│   ├── zdm_orchestrate_discovery.sh     # Orchestration script
│   └── README.md                         # Scripts documentation
├── Discovery/                            # Discovery output (after execution)
│   ├── source/                          # Source server results
│   ├── target/                          # Target server results
│   └── server/                          # ZDM server results
└── README.md                            # This file
```

## Migration Project Details

| Item | Value |
|------|-------|
| Project Name | PRODDB Migration to Oracle Database@Azure |
| Source Database | proddb01.corp.example.com |
| Target Database | proddb-oda.eastus.azure.example.com |
| ZDM Server | zdm-jumpbox.corp.example.com |

## SSH Keys Configuration

| Environment | SSH Key |
|-------------|---------|
| Source Database | ~/.ssh/source_db_key |
| Target ODA@Azure | ~/.ssh/oda_azure_key |
| ZDM Server | ~/.ssh/zdm_jumpbox_key |

## How to Execute Discovery

### Quick Start (Orchestrated)

```bash
# Set SSH keys
export SOURCE_SSH_KEY=~/.ssh/source_db_key
export TARGET_SSH_KEY=~/.ssh/oda_azure_key
export ZDM_SSH_KEY=~/.ssh/zdm_jumpbox_key

# Run orchestration
cd Scripts
./zdm_orchestrate_discovery.sh

# Results collected to Discovery/ subdirectories
```

### Manual Execution

See `Scripts/README.md` for detailed manual execution instructions.

## Additional Discovery Requirements

The scripts include custom discovery for this project:

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
- Available disk space for ZDM operations (minimum 50GB)
- Network latency to source and target (ping tests)

## Next Steps

After completing Step 0:

1. **Execute Discovery Scripts**
   - Run the orchestration script or execute scripts manually
   - Verify output files are collected to `Discovery/` subdirectories

2. **Proceed to Step 1: Discovery Questionnaire**
   - Use `Step1-Discovery-Questionnaire.prompt.md`
   - Attach discovery output files
   - Complete all sections including business decisions
   - Save to `Step1/Completed-Questionnaire-PRODDB.md`

3. **Proceed to Step 2: Generate Migration Artifacts**
   - Generate RSP file, CLI commands, and runbook
   - Save to `Step2/` directory

## Migration Workflow

```
Step 0: Discovery Scripts (YOU ARE HERE)
    ↓
Step 1: Discovery Questionnaire
    ↓
Step 2: Migration Artifacts
    ↓
Migration Execution
```

---

*Part of the PRODDB Migration to Oracle Database@Azure project*
