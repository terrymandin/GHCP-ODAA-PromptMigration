# Step 0: Discovery Scripts - PRODDB Migration

## Overview

This directory contains the discovery scripts and outputs for **Step 0** of the ZDM migration process for the PRODDB Migration to Oracle Database@Azure project.

**Generated:** 2026-01-29

## Directory Structure

```
Step0/
├── Scripts/                              # Discovery scripts
│   ├── zdm_source_discovery.sh           # Source database discovery
│   ├── zdm_target_discovery.sh           # Target Oracle Database@Azure discovery
│   ├── zdm_server_discovery.sh           # ZDM jumpbox discovery
│   ├── zdm_orchestrate_discovery.sh      # Orchestration script
│   └── README.md                         # Script usage instructions
├── Discovery/                            # Discovery outputs (after execution)
│   ├── source/                           # Source server results
│   ├── target/                           # Target server results
│   └── server/                           # ZDM server results
└── README.md                             # This file
```

## Migration Project Details

| Property | Value |
|----------|-------|
| Project Name | PRODDB Migration to Oracle Database@Azure |
| Source Database | proddb01.corp.example.com |
| Target Database | proddb-oda.eastus.azure.example.com |
| ZDM Server | zdm-jumpbox.corp.example.com |

## How to Execute Discovery

### Quick Start

```bash
# Navigate to the Scripts directory
cd Artifacts/Phase10-Migration/ZDM/PRODDB/Step0/Scripts

# Test SSH connectivity first
./zdm_orchestrate_discovery.sh --test

# Run full discovery
./zdm_orchestrate_discovery.sh
```

### Detailed Instructions

See [Scripts/README.md](Scripts/README.md) for detailed usage instructions.

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

## Script Features

All scripts include these resilience features:

1. **Continue on failure** - Scripts don't stop if individual checks fail
2. **Environment auto-detection** - Automatically finds ORACLE_HOME, ZDM_HOME, etc.
3. **Non-interactive SSH support** - Works correctly over SSH without login shell
4. **Both text and JSON output** - Human-readable and machine-parseable formats
5. **Color-coded output** - Easy to identify warnings and errors

## Next Steps

After executing discovery scripts:

1. **Review output files** in `Discovery/` subdirectories
2. **Proceed to Step 1**: Discovery Questionnaire
   - Reference: `prompts/Phase10-Migration/ZDM/Step1-Discovery-Questionnaire.prompt.md`
   - Attach the discovery output files
   - Complete all sections including business decisions (migration type, timeline, OCI identifiers)
3. **Save completed questionnaire** to `../Step1/Completed-Questionnaire-PRODDB.md`
4. **Proceed to Step 2**: Generate Migration Artifacts
   - Generate RSP file, CLI commands, and runbook
   - Save to `../Step2/`

## Troubleshooting

### Common Issues

1. **SSH key not found**: Ensure SSH keys exist and have correct permissions (600)
2. **Environment variables not detected**: Use explicit overrides (see Scripts/README.md)
3. **Permission denied**: Ensure the user account has access to Oracle/ZDM installations

### Getting Help

If discovery fails, the scripts provide detailed error messages. Check:
- The text output file for specific section failures
- The JSON summary for a quick overview of what succeeded/failed
- The "Sections with errors" count at the end of each discovery run
