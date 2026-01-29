# PRODDB Migration - Step 0: Discovery

## Project Overview

| Field | Value |
|-------|-------|
| **Project Name** | PRODDB Migration to Oracle Database@Azure |
| **Source Database** | proddb01.corp.example.com |
| **Target Database** | proddb-oda.eastus.azure.example.com |
| **ZDM Server** | zdm-jumpbox.corp.example.com |
| **Generated** | 2026-01-29 |

## Purpose

Step 0 generates and executes discovery scripts to gather comprehensive information about:
- Source database configuration and environment
- Target Oracle Database@Azure configuration
- ZDM jumpbox server setup and readiness

## Directory Structure

```
Step0/
├── README.md                    # This file
├── Scripts/                     # Discovery scripts
│   ├── README.md               # Script usage documentation
│   ├── zdm_source_discovery.sh # Source database discovery
│   ├── zdm_target_discovery.sh # Target database discovery
│   ├── zdm_server_discovery.sh # ZDM server discovery
│   └── zdm_orchestrate_discovery.sh # Orchestration script
└── Discovery/                   # Discovery output (after execution)
    ├── source/                  # Source discovery results
    ├── target/                  # Target discovery results
    └── server/                  # ZDM server discovery results
```

## Quick Start

### Prerequisites

1. SSH access to all three servers with appropriate keys:
   - Source: `~/.ssh/source_db_key`
   - Target: `~/.ssh/oda_azure_key`
   - ZDM: `~/.ssh/zdm_jumpbox_key`

2. Appropriate user accounts:
   - Source: `oracle` user
   - Target: `opc` or `oracle` user
   - ZDM: `zdmuser`

### Running Discovery

```bash
cd Scripts/

# Option 1: Test connectivity first
./zdm_orchestrate_discovery.sh --test

# Option 2: Run full discovery
./zdm_orchestrate_discovery.sh

# Option 3: Run for specific server only
./zdm_orchestrate_discovery.sh --source-only
./zdm_orchestrate_discovery.sh --target-only
./zdm_orchestrate_discovery.sh --zdm-only
```

## Discovery Scope

### Standard Discovery (All Migrations)

| Category | Source | Target | ZDM |
|----------|--------|--------|-----|
| OS Information | ✓ | ✓ | ✓ |
| Oracle Environment | ✓ | ✓ | - |
| Database Configuration | ✓ | ✓ | - |
| CDB/PDB Status | ✓ | ✓ | - |
| TDE Configuration | ✓ | ✓ | - |
| Network Configuration | ✓ | ✓ | ✓ |
| ZDM Installation | - | - | ✓ |
| OCI/Azure Integration | - | ✓ | ✓ |

### PRODDB-Specific Additional Discovery

#### Source Database
- Tablespace autoextend settings
- Backup schedule and retention
- Database links
- Materialized view refresh schedules
- Scheduler jobs requiring reconfiguration

#### Target Database (Oracle Database@Azure)
- Available Exadata storage capacity
- Pre-configured PDBs
- Network security group rules

#### ZDM Server
- Available disk space (50GB minimum recommended)
- Network latency to source and target

## Environment Variable Overrides

For servers with non-interactive shell guards, the following explicit overrides are configured:

```bash
# Source
SOURCE_REMOTE_ORACLE_HOME=/u01/app/oracle/product/19.0.0.0/dbhome_1
SOURCE_REMOTE_ORACLE_SID=PRODDB

# Target
TARGET_REMOTE_ORACLE_HOME=/u01/app/oracle/product/19.0.0.0/dbhome_1
TARGET_REMOTE_ORACLE_SID=PRODDB

# ZDM
ZDM_REMOTE_ZDM_HOME=/home/zdmuser/zdmhome
ZDM_REMOTE_JAVA_HOME=/usr/java/jdk1.8.0_391
```

## Output Files

After discovery execution, the following files will be generated:

| Server | Text Report | JSON Summary |
|--------|-------------|--------------|
| Source | `zdm_source_discovery_<hostname>_<timestamp>.txt` | `zdm_source_discovery_<hostname>_<timestamp>.json` |
| Target | `zdm_target_discovery_<hostname>_<timestamp>.txt` | `zdm_target_discovery_<hostname>_<timestamp>.json` |
| ZDM | `zdm_server_discovery_<hostname>_<timestamp>.txt` | `zdm_server_discovery_<hostname>_<timestamp>.json` |

## Next Steps

After completing Step 0 discovery:

1. **Review Discovery Output**
   - Verify all sections completed successfully
   - Note any warnings or errors
   - Identify any prerequisites that need to be addressed

2. **Proceed to Step 1: Discovery Questionnaire**
   - Use the discovery data to populate the migration questionnaire
   - Make business decisions about migration approach
   - Path: `../Step1/`

3. **Generate Migration Artifacts (Step 2)**
   - After completing the questionnaire, generate:
     - ZDM response file
     - Migration commands
     - Runbook documentation
   - Path: `../Step2/`

## Troubleshooting

See `Scripts/README.md` for detailed troubleshooting information.

Common issues:
- SSH connectivity failures
- Environment variable sourcing issues
- Insufficient disk space
- Database not running

## Contact

For migration support, contact the Oracle Database@Azure migration team.
