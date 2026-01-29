# ZDM Discovery Scripts - PRODDB Migration

This directory contains the discovery scripts generated for the **PRODDB Migration to Oracle Database@Azure** project.

## Scripts Overview

| Script | Purpose | Target Server | User |
|--------|---------|---------------|------|
| `zdm_source_discovery.sh` | Discovers source Oracle database configuration | proddb01.corp.example.com | oracle |
| `zdm_target_discovery.sh` | Discovers target Oracle Database@Azure environment | proddb-oda.eastus.azure.example.com | opc |
| `zdm_server_discovery.sh` | Discovers ZDM jumpbox configuration | zdm-jumpbox.corp.example.com | zdmuser |
| `zdm_orchestrate_discovery.sh` | Orchestrates discovery across all servers | Local machine | - |

## Quick Start

### Option 1: Run Orchestration Script (Recommended)

The orchestration script handles copying, executing, and collecting results from all servers:

```bash
# Set SSH keys for each environment
export SOURCE_SSH_KEY=~/.ssh/source_db_key
export TARGET_SSH_KEY=~/.ssh/oda_azure_key
export ZDM_SSH_KEY=~/.ssh/zdm_jumpbox_key

# Run orchestration
./zdm_orchestrate_discovery.sh

# Results will be collected to ../Discovery/
```

### Option 2: Run Scripts Individually

```bash
# 1. Copy and run on source database server
scp -i ~/.ssh/source_db_key zdm_source_discovery.sh oracle@proddb01.corp.example.com:/tmp/
ssh -i ~/.ssh/source_db_key oracle@proddb01.corp.example.com "cd /tmp && chmod +x zdm_source_discovery.sh && ./zdm_source_discovery.sh"

# 2. Copy and run on target Oracle Database@Azure server
scp -i ~/.ssh/oda_azure_key zdm_target_discovery.sh opc@proddb-oda.eastus.azure.example.com:/tmp/
ssh -i ~/.ssh/oda_azure_key opc@proddb-oda.eastus.azure.example.com "cd /tmp && chmod +x zdm_target_discovery.sh && ./zdm_target_discovery.sh"

# 3. Copy and run on ZDM jumpbox server
scp -i ~/.ssh/zdm_jumpbox_key zdm_server_discovery.sh zdmuser@zdm-jumpbox.corp.example.com:/tmp/
ssh -i ~/.ssh/zdm_jumpbox_key zdmuser@zdm-jumpbox.corp.example.com "cd /tmp && chmod +x zdm_server_discovery.sh && ./zdm_server_discovery.sh"

# 4. Collect results
scp -i ~/.ssh/source_db_key oracle@proddb01.corp.example.com:/tmp/zdm_source_discovery_*.* ../Discovery/source/
scp -i ~/.ssh/oda_azure_key opc@proddb-oda.eastus.azure.example.com:/tmp/zdm_target_discovery_*.* ../Discovery/target/
scp -i ~/.ssh/zdm_jumpbox_key zdmuser@zdm-jumpbox.corp.example.com:/tmp/zdm_server_discovery_*.* ../Discovery/server/
```

## Orchestration Script Options

```bash
# Show help
./zdm_orchestrate_discovery.sh --help

# Display current configuration
./zdm_orchestrate_discovery.sh --config

# Test connectivity only (no discovery)
./zdm_orchestrate_discovery.sh --test

# Specify custom output directory
./zdm_orchestrate_discovery.sh --output /path/to/output
```

## SSH Keys Configuration

This migration uses separate SSH keys for each environment:

| Environment | SSH Key Path | Description |
|-------------|--------------|-------------|
| Source Database | `~/.ssh/source_db_key` | Key for proddb01.corp.example.com |
| Target ODA@Azure | `~/.ssh/oda_azure_key` | Key for proddb-oda.eastus.azure.example.com |
| ZDM Server | `~/.ssh/zdm_jumpbox_key` | Key for zdm-jumpbox.corp.example.com |

## Discovery Output

Each script produces two output files in the current working directory:

- **Text Report**: `zdm_<type>_discovery_<hostname>_<timestamp>.txt` - Human-readable detailed report
- **JSON Summary**: `zdm_<type>_discovery_<hostname>_<timestamp>.json` - Machine-parseable summary

## What Each Script Discovers

### Source Database Discovery (`zdm_source_discovery.sh`)

**Standard Discovery:**
- OS information (hostname, IP, disk space)
- Oracle environment (ORACLE_HOME, version)
- Database configuration (name, DBID, log mode)
- Container database (CDB/PDB status)
- TDE configuration (wallet, encrypted tablespaces)
- Supplemental logging settings
- Redo/archive configuration
- Network configuration (listener, tnsnames.ora)
- Authentication (password file, SSH)
- Data Guard configuration
- Schema information

**Additional PRODDB Requirements:**
- Tablespace autoextend settings
- Current backup schedule and retention
- Database links configured
- Materialized view refresh schedules
- Scheduler jobs that may need reconfiguration

### Target Database Discovery (`zdm_target_discovery.sh`)

**Standard Discovery:**
- OS information
- Oracle environment
- Database configuration
- Storage (tablespaces, ASM disk groups)
- Container database (CDB/PDB)
- TDE/wallet status
- Network configuration (listener, SCAN)
- OCI/Azure integration (CLI, metadata)
- Grid infrastructure (if RAC)
- Authentication

**Additional PRODDB Requirements:**
- Available Exadata storage capacity
- Pre-configured PDBs
- Network security group rules

### ZDM Server Discovery (`zdm_server_discovery.sh`)

**Standard Discovery:**
- OS information
- ZDM installation (ZDM_HOME, version, service status)
- Java configuration
- OCI CLI configuration and connectivity
- SSH configuration and keys
- Credential files
- Network configuration
- ZDM logs

**Additional PRODDB Requirements:**
- Available disk space for ZDM operations (50GB minimum)
- Network latency to source and target (ping tests)
- Port connectivity tests (SSH, Oracle listener)

## Resilience Features

All scripts are designed to be resilient:

1. **No `set -e`** - Scripts continue running even when individual checks fail
2. **Environment sourcing** - Scripts source `.bashrc`, `.bash_profile`, etc. to ensure environment variables are available
3. **Error tracking** - Each section tracks errors independently
4. **Continue on failure** - Orchestrator continues with remaining servers even if one fails
5. **Partial success** - Reports are saved even with partial discovery

## Next Steps

After running discovery:

1. **Review Output** - Check the discovery files in `../Discovery/`
2. **Proceed to Step 1** - Use `Step1-Discovery-Questionnaire.prompt.md` to complete the full questionnaire
3. **Prepare for Step 2** - Generate migration artifacts (RSP file, commands, runbook)

## Troubleshooting

### SSH Connection Issues
```bash
# Test connectivity
./zdm_orchestrate_discovery.sh --test

# Check SSH key permissions (should be 600)
chmod 600 ~/.ssh/source_db_key
chmod 600 ~/.ssh/oda_azure_key
chmod 600 ~/.ssh/zdm_jumpbox_key
```

### Environment Variables Not Found
Scripts automatically source common profile files. If variables are still missing:
```bash
# On the remote server, check:
echo $ORACLE_HOME
echo $ZDM_HOME
echo $JAVA_HOME

# Add to appropriate profile file if missing
```

### Partial Discovery Results
If some sections fail, the script continues. Check the output file for `WARNING` or `ERROR` messages to identify issues.

---

*Generated: 2026-01-29*
*Project: PRODDB Migration to Oracle Database@Azure*
