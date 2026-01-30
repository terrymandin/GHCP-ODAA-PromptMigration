# ZDM Discovery Scripts - PRODDB Migration

This directory contains the discovery scripts for the PRODDB migration to Oracle Database@Azure.

## Project Details

| Parameter | Value |
|-----------|-------|
| **Project Name** | PRODDB Migration to Oracle Database@Azure |
| **Source Database** | proddb01.corp.example.com |
| **Target Database** | proddb-oda.eastus.azure.example.com |
| **ZDM Server** | zdm-jumpbox.corp.example.com |
| **Generated** | 2026-01-30 |

## Scripts Overview

| Script | Purpose | Target Server |
|--------|---------|---------------|
| `zdm_source_discovery.sh` | Discovers source database configuration | proddb01.corp.example.com |
| `zdm_target_discovery.sh` | Discovers target Oracle Database@Azure configuration | proddb-oda.eastus.azure.example.com |
| `zdm_server_discovery.sh` | Discovers ZDM jumpbox configuration | zdm-jumpbox.corp.example.com |
| `zdm_orchestrate_discovery.sh` | Orchestrates discovery across all servers | Run from local machine |

## SSH Key Configuration

The scripts are configured to use the following SSH keys:

| Server | SSH Key Path |
|--------|--------------|
| Source | `~/.ssh/source_db_key` |
| Target | `~/.ssh/oda_azure_key` |
| ZDM | `~/.ssh/zdm_jumpbox_key` |

## Quick Start

### Option 1: Run Orchestration Script (Recommended)

The orchestration script handles copying scripts to servers, executing them, and collecting results:

```bash
# Make scripts executable
chmod +x *.sh

# Test connectivity first
./zdm_orchestrate_discovery.sh --test

# View current configuration
./zdm_orchestrate_discovery.sh --config

# Run full discovery
./zdm_orchestrate_discovery.sh
```

### Option 2: Run Individual Scripts Manually

If you prefer to run scripts manually on each server:

```bash
# Copy and run on source server
scp -i ~/.ssh/source_db_key zdm_source_discovery.sh oracle@proddb01.corp.example.com:/tmp/
ssh -i ~/.ssh/source_db_key oracle@proddb01.corp.example.com "chmod +x /tmp/zdm_source_discovery.sh && cd /tmp && ./zdm_source_discovery.sh"

# Copy and run on target server
scp -i ~/.ssh/oda_azure_key zdm_target_discovery.sh opc@proddb-oda.eastus.azure.example.com:/tmp/
ssh -i ~/.ssh/oda_azure_key opc@proddb-oda.eastus.azure.example.com "chmod +x /tmp/zdm_target_discovery.sh && cd /tmp && ./zdm_target_discovery.sh"

# Copy and run on ZDM server
scp -i ~/.ssh/zdm_jumpbox_key zdm_server_discovery.sh zdmuser@zdm-jumpbox.corp.example.com:/tmp/
ssh -i ~/.ssh/zdm_jumpbox_key zdmuser@zdm-jumpbox.corp.example.com "chmod +x /tmp/zdm_server_discovery.sh && cd /tmp && ./zdm_server_discovery.sh"
```

## Environment Overrides

If auto-detection fails (e.g., non-standard installation paths), you can provide explicit overrides:

```bash
# Set overrides before running orchestration
export SOURCE_REMOTE_ORACLE_HOME=/custom/path/oracle/product/19.0.0.0/dbhome_1
export SOURCE_REMOTE_ORACLE_SID=PRODDB
./zdm_orchestrate_discovery.sh
```

Available override variables:
- `SOURCE_REMOTE_ORACLE_HOME` - Oracle home on source server
- `SOURCE_REMOTE_ORACLE_SID` - Oracle SID on source server
- `TARGET_REMOTE_ORACLE_HOME` - Oracle home on target server
- `TARGET_REMOTE_ORACLE_SID` - Oracle SID on target server
- `ZDM_REMOTE_ZDM_HOME` - ZDM home on ZDM server
- `ZDM_REMOTE_JAVA_HOME` - Java home on ZDM server

## Output Location

Discovery results are saved to:

```
../Discovery/
├── source/                           # Source server results
│   ├── zdm_source_discovery_*.txt   # Human-readable report
│   └── zdm_source_discovery_*.json  # Machine-parseable summary
├── target/                           # Target server results
│   ├── zdm_target_discovery_*.txt
│   └── zdm_target_discovery_*.json
└── server/                           # ZDM server results
    ├── zdm_server_discovery_*.txt
    └── zdm_server_discovery_*.json
```

## Discovery Coverage

### Source Database Discovery
- OS Information (hostname, IP, disk space)
- Oracle Environment (ORACLE_HOME, ORACLE_SID, version)
- Database Configuration (name, DBID, role, mode, size, character set)
- Container Database / PDB information
- TDE Configuration (wallet status, encrypted tablespaces)
- Supplemental Logging settings
- Redo and Archive configuration
- Network Configuration (listener, tnsnames.ora, sqlnet.ora)
- Authentication (password file, SSH keys)
- Data Guard configuration
- Schema information (sizes, invalid objects)
- **PRODDB-specific:**
  - Tablespace autoextend settings
  - Backup schedule and retention
  - Database links
  - Materialized view refresh schedules
  - Scheduler jobs

### Target Database Discovery (Oracle Database@Azure)
- OS Information
- Oracle Environment (including Grid Infrastructure)
- Database Configuration
- Storage (tablespaces, ASM disk groups)
- Container Database / PDB information
- TDE Configuration
- Network Configuration (listener, SCAN listener)
- OCI/Azure Integration (CLI, metadata)
- Grid Infrastructure (RAC) status
- **PRODDB-specific:**
  - Exadata storage capacity
  - Pre-configured PDBs
  - Network security group rules

### ZDM Server Discovery
- OS Information
- ZDM Installation (version, service status, active jobs)
- Java Configuration
- OCI CLI Configuration (version, profiles, connectivity)
- SSH Configuration (available keys)
- Credential files
- Network Configuration (IP, routing, DNS)
- ZDM Logs
- **PRODDB-specific:**
  - Disk space (minimum 50GB check)
  - Network latency to source and target (ping tests)

## Resilience Features

All scripts include:

1. **Continue on Failure** - Scripts continue running even if individual sections fail
2. **Auto-detection with Fallbacks** - Multiple methods to detect Oracle/ZDM environments
3. **Non-interactive SSH Support** - Works correctly in non-interactive SSH sessions
4. **Error Tracking** - Reports which sections had errors

## Next Steps

After running discovery:

1. Review the discovery reports in `../Discovery/`
2. Proceed to **Step 1: Discovery Questionnaire**
3. Use the discovery data to complete the questionnaire with business decisions
