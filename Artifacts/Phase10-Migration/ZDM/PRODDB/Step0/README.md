# Step 0: Discovery Scripts

**Project:** PRODDB Migration to Oracle Database@Azure  
**Generated:** 2026-01-29

## Overview

Step 0 is the first phase of the ZDM migration process. This step generates and executes discovery scripts to gather comprehensive information from all servers involved in the migration.

## Migration Details

| Item | Value |
|------|-------|
| **Project Name** | PRODDB Migration to Oracle Database@Azure |
| **Source Database** | proddb01.corp.example.com |
| **Target Database** | proddb-oda.eastus.azure.example.com |
| **ZDM Server** | zdm-jumpbox.corp.example.com |

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
└── Discovery/                   # Discovery output files (after execution)
    ├── zdm_source_discovery_*.txt
    ├── zdm_source_discovery_*.json
    ├── zdm_target_discovery_*.txt
    ├── zdm_target_discovery_*.json
    ├── zdm_server_discovery_*.txt
    └── zdm_server_discovery_*.json
```

## Prerequisites

Before running discovery:

1. **SSH Access**: Ensure SSH access is available to all servers
2. **SSH Keys**: Configure SSH keys as specified:
   - Source: `~/.ssh/source_db_key`
   - Target: `~/.ssh/oda_azure_key`
   - ZDM: `~/.ssh/zdm_jumpbox_key`
3. **User Permissions**: 
   - Source: `oracle` user with SYSDBA access
   - Target: `opc` or `oracle` user with SYSDBA access
   - ZDM: `zdmuser` with ZDM installation access

## How to Run Discovery

### Quick Start

```bash
cd Scripts/

# Make scripts executable
chmod +x *.sh

# Test connectivity
./zdm_orchestrate_discovery.sh --test

# Run full discovery
./zdm_orchestrate_discovery.sh
```

### Detailed Instructions

See [Scripts/README.md](Scripts/README.md) for detailed instructions on running discovery scripts.

## What Gets Discovered

### Source Database
- OS information (hostname, IP, disk space)
- Oracle environment (ORACLE_HOME, version)
- Database configuration (name, DBID, role, log mode)
- TDE/encryption status
- Supplemental logging
- Redo/archive configuration
- Network configuration (listener, tnsnames.ora)
- Schema information
- **Custom:** Tablespace autoextend settings
- **Custom:** Backup schedule and retention
- **Custom:** Database links
- **Custom:** Materialized view refresh schedules
- **Custom:** Scheduler jobs

### Target Database (Oracle Database@Azure)
- OS information
- Oracle environment
- Database configuration
- CDB/PDB configuration
- TDE status
- Network configuration
- OCI/Azure integration
- Grid Infrastructure (if RAC)
- **Custom:** Available Exadata storage capacity
- **Custom:** Pre-configured PDBs
- **Custom:** Network security group rules

### ZDM Server
- OS information
- ZDM installation and version
- Java configuration
- OCI CLI configuration
- SSH configuration
- Credential files
- Network configuration
- ZDM logs
- **Custom:** Available disk space (50GB minimum check)
- **Custom:** Network latency to source and target

## Output Files

After running discovery, collect the following files to the `Discovery/` directory:

| File | Description |
|------|-------------|
| `zdm_source_discovery_*.txt` | Source database text report |
| `zdm_source_discovery_*.json` | Source database JSON summary |
| `zdm_target_discovery_*.txt` | Target database text report |
| `zdm_target_discovery_*.json` | Target database JSON summary |
| `zdm_server_discovery_*.txt` | ZDM server text report |
| `zdm_server_discovery_*.json` | ZDM server JSON summary |

## Next Steps

After completing Step 0:

1. ✅ Review all discovery output files
2. ✅ Copy outputs to `Discovery/` directory
3. ➡️ Proceed to **Step 1: Discovery Questionnaire**
   - Use discovery data to answer technical questions
   - Make business decisions (migration window, strategy, etc.)
4. ➡️ Then proceed to **Step 2: Generate Migration Artifacts**
   - Generate ZDM response file
   - Generate migration commands
   - Generate runbook

## Troubleshooting

### Common Issues

1. **SSH Connection Failed**
   - Verify SSH key permissions: `chmod 600 ~/.ssh/<key>`
   - Test connectivity manually: `ssh -v -i <key> user@host`

2. **Oracle Commands Not Found**
   - Ensure `ORACLE_HOME` is set in user's profile
   - Run: `source ~/.bash_profile` before executing script

3. **Permission Denied on Script**
   - Make script executable: `chmod +x *.sh`

4. **SQL*Plus Errors**
   - Verify ORACLE_SID is set
   - Verify database is running
   - Check SYSDBA permissions

## Support

For issues with discovery scripts, review the error messages in the script output. Common resolutions:

- Check network connectivity between servers
- Verify SSH key configuration
- Ensure Oracle environment variables are set
- Confirm database is accessible
