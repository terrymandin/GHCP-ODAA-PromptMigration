# PRODDB Migration - Step 0: Discovery

## Overview

This directory contains the discovery scripts and outputs for the PRODDB migration to Oracle Database@Azure using Zero Downtime Migration (ZDM).

## Project Details

| Property | Value |
|----------|-------|
| Project Name | PRODDB Migration to Oracle Database@Azure |
| Source Database | proddb01.corp.example.com |
| Target Database | proddb-oda.eastus.azure.example.com |
| ZDM Server | zdm-jumpbox.corp.example.com |

## Directory Structure

```
Step0/
├── README.md                    # This file
├── Scripts/                     # Discovery scripts
│   ├── zdm_source_discovery.sh
│   ├── zdm_target_discovery.sh
│   ├── zdm_server_discovery.sh
│   ├── zdm_orchestrate_discovery.sh
│   └── README.md
└── Discovery/                   # Discovery output (after execution)
    ├── source/                  # Source server results
    ├── target/                  # Target server results
    └── server/                  # ZDM server results
```

## Quick Start

```bash
# Navigate to Scripts directory
cd Scripts

# Make executable
chmod +x *.sh

# Test connectivity
./zdm_orchestrate_discovery.sh -t

# Run full discovery
./zdm_orchestrate_discovery.sh
```

## User Configuration

| Server | SSH User | SSH Key |
|--------|----------|---------|
| Source (proddb01.corp.example.com) | oracle | ~/.ssh/onprem_oracle_key |
| Target (proddb-oda.eastus.azure.example.com) | opc | ~/.ssh/oci_opc_key |
| ZDM (zdm-jumpbox.corp.example.com) | azureuser | ~/.ssh/azure_key |

## What Gets Discovered

### Source Database
- OS and Oracle environment
- Database configuration (name, DBID, log mode, force logging)
- CDB/PDB configuration
- TDE/wallet status
- Supplemental logging settings
- Redo and archive log configuration
- Network configuration (listener, tnsnames, sqlnet)
- Authentication (password files, SSH)
- Data Guard parameters
- Schema sizes and invalid objects
- **Additional for PRODDB:**
  - Tablespace autoextend settings
  - Backup schedule and retention
  - Database links
  - Materialized view refresh schedules
  - Scheduler jobs

### Target Database (Oracle Database@Azure)
- OS and Oracle environment
- Database configuration
- Storage (tablespaces, ASM)
- CDB/PDB configuration
- TDE/wallet status
- Network configuration
- OCI/Azure integration
- Grid infrastructure (if RAC)
- **Additional for PRODDB:**
  - Exadata storage capacity
  - Pre-configured PDBs
  - Network security group rules

### ZDM Server
- OS information
- ZDM installation and version
- Java configuration
- OCI CLI configuration and connectivity
- SSH keys
- Credential files
- Network configuration
- ZDM logs
- **Additional for PRODDB:**
  - Disk space (50GB minimum recommended)
  - Network latency to source and target

## Next Steps

After running discovery:

1. **Review Discovery Reports**
   - Check for any errors or warnings
   - Verify all required information was collected

2. **Proceed to Step 1: Discovery Questionnaire**
   - Complete the questionnaire with discovery data
   - Make business decisions (migration window, method, etc.)

3. **Proceed to Step 2: Generate Migration Artifacts**
   - Generate ZDM response file
   - Generate migration commands
   - Generate runbook

## Troubleshooting

See [Scripts/README.md](Scripts/README.md) for detailed troubleshooting steps.

## Generated

- **Date:** January 30, 2026
- **Script Version:** 1.0.0
