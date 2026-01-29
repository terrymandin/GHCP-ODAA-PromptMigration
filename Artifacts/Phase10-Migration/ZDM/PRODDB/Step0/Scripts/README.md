# ZDM Discovery Scripts

**Project:** PRODDB Migration to Oracle Database@Azure  
**Generated:** 2026-01-29

## Overview

This directory contains the discovery scripts for gathering information from all servers involved in the ZDM migration.

## Scripts

| Script | Description | Run As | Target Server |
|--------|-------------|--------|---------------|
| `zdm_source_discovery.sh` | Discovers source database configuration | oracle | proddb01.corp.example.com |
| `zdm_target_discovery.sh` | Discovers target Oracle Database@Azure configuration | opc/oracle | proddb-oda.eastus.azure.example.com |
| `zdm_server_discovery.sh` | Discovers ZDM server configuration | zdmuser | zdm-jumpbox.corp.example.com |
| `zdm_orchestrate_discovery.sh` | Orchestrates discovery across all servers | any | Local machine |

## Quick Start

### Option 1: Run Orchestration Script (Recommended)

Run the orchestration script from a machine with SSH access to all servers:

```bash
# Make scripts executable
chmod +x *.sh

# Test connectivity first
./zdm_orchestrate_discovery.sh --test

# Run full discovery
./zdm_orchestrate_discovery.sh

# Or run discovery for specific servers
./zdm_orchestrate_discovery.sh --source   # Source only
./zdm_orchestrate_discovery.sh --target   # Target only
./zdm_orchestrate_discovery.sh --zdm      # ZDM server only
```

### Option 2: Run Scripts Individually

Copy and run each script on its respective server:

#### Source Database
```bash
scp -i ~/.ssh/source_db_key zdm_source_discovery.sh oracle@proddb01.corp.example.com:/tmp/
ssh -i ~/.ssh/source_db_key oracle@proddb01.corp.example.com "chmod +x /tmp/zdm_source_discovery.sh && /tmp/zdm_source_discovery.sh"
```

#### Target Database (Oracle Database@Azure)
```bash
scp -i ~/.ssh/oda_azure_key zdm_target_discovery.sh opc@proddb-oda.eastus.azure.example.com:/tmp/
ssh -i ~/.ssh/oda_azure_key opc@proddb-oda.eastus.azure.example.com "chmod +x /tmp/zdm_target_discovery.sh && /tmp/zdm_target_discovery.sh"
```

#### ZDM Server
```bash
scp -i ~/.ssh/zdm_jumpbox_key zdm_server_discovery.sh zdmuser@zdm-jumpbox.corp.example.com:/tmp/
ssh -i ~/.ssh/zdm_jumpbox_key zdmuser@zdm-jumpbox.corp.example.com "chmod +x /tmp/zdm_server_discovery.sh && /tmp/zdm_server_discovery.sh"
```

## SSH Key Configuration

The scripts are configured to use separate SSH keys for each security domain:

| Server | SSH Key |
|--------|---------|
| Source Database | `~/.ssh/source_db_key` |
| Target Database | `~/.ssh/oda_azure_key` |
| ZDM Server | `~/.ssh/zdm_jumpbox_key` |

Update the key paths in `zdm_orchestrate_discovery.sh` if your keys are located elsewhere.

## Output Files

Each discovery script generates two output files:

- **Text Report**: `/tmp/zdm_<type>_discovery_<hostname>_<timestamp>.txt`
- **JSON Summary**: `/tmp/zdm_<type>_discovery_<hostname>_<timestamp>.json`

After running discovery, collect the output files to:
```
../Discovery/
├── zdm_source_discovery_*.txt
├── zdm_source_discovery_*.json
├── zdm_target_discovery_*.txt
├── zdm_target_discovery_*.json
├── zdm_server_discovery_*.txt
└── zdm_server_discovery_*.json
```

## Custom Discovery Items

The following custom discovery items were added per project requirements:

### Source Database
- Tablespace autoextend settings
- Current backup schedule and retention (RMAN configuration)
- Database links
- Materialized view refresh schedules
- Scheduler jobs

### Target Database (Oracle Database@Azure)
- Available Exadata storage capacity
- Pre-configured PDBs
- Network security group rules (local firewall rules)

### ZDM Server
- Available disk space (minimum 50GB verification)
- Network latency tests (ping to source and target)

## Troubleshooting

### SSH Connection Issues
```bash
# Test SSH connectivity
ssh -v -i ~/.ssh/source_db_key oracle@proddb01.corp.example.com

# Check key permissions
chmod 600 ~/.ssh/source_db_key
```

### Script Permission Denied
```bash
# Ensure scripts are executable
chmod +x *.sh
```

### Oracle Environment Not Set
Ensure the oracle user's `.bash_profile` or `.bashrc` sets `ORACLE_HOME`, `ORACLE_SID`, and `ORACLE_BASE`.

## Next Steps

After running discovery:

1. Review the discovery output files
2. Copy outputs to `../Discovery/`
3. Proceed to **Step 1: Discovery Questionnaire**
4. Use the discovery data to complete the questionnaire
