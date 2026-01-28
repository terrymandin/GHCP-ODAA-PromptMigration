# ZDM Migration Prompts

This directory contains prompts for Zero Downtime Migration (ZDM) from on-premise Oracle databases to Oracle Database@Azure.

## Migration Workflow

The ZDM migration process is divided into three steps, each with its own prompt:

```
Step 0: Generate Discovery Scripts
         ↓
Step 1: Discovery and Questionnaire
         ↓
Step 2: Generate Migration Artifacts
         ↓
     Execute Migration
```

## Prompt Files

| Step | File | Example | Purpose |
|------|------|---------|---------|
| 0 | [Step0-Generate-Discovery-Scripts.prompt.md](Step0-Generate-Discovery-Scripts.prompt.md) | [Example](Example-Step0-Generate-Discovery-Scripts.prompt.md) | Generate fresh discovery scripts |
| 1 | [Step1-Discovery-Questionnaire.prompt.md](Step1-Discovery-Questionnaire.prompt.md) | [Example](Example-Step1-Discovery-Questionnaire.prompt.md) | Complete questionnaire with discovered info |
| 2 | [Step2-Generate-Migration-Artifacts.prompt.md](Step2-Generate-Migration-Artifacts.prompt.md) | [Example](Example-Step2-Generate-Migration-Artifacts.prompt.md) | Generate RSP file, CLI commands, runbook |

## Example Files

Each step has a corresponding example file showing a completed prompt for a fictional "PRODDB" migration:

| Example | Description |
|---------|-------------|
| [Example-Step0](Example-Step0-Generate-Discovery-Scripts.prompt.md) | Shows how to request discovery scripts with custom requirements |
| [Example-Step1](Example-Step1-Discovery-Questionnaire.prompt.md) | Shows a fully completed questionnaire for online physical migration |
| [Example-Step2](Example-Step2-Generate-Migration-Artifacts.prompt.md) | Shows expected RSP file, CLI script, and runbook output |

## Detailed Workflow

### Step 0: Generate Discovery Scripts

**Purpose**: Create fresh discovery scripts that gather configuration from all servers involved in the migration.

**Output**: Four bash scripts saved to `Artifacts/Phase10-Migration/ZDM/<DB_NAME>/Scripts/`
- `zdm_source_discovery.sh` - Run on source database server
- `zdm_target_discovery.sh` - Run on target Oracle Database@Azure server
- `zdm_server_discovery.sh` - Run on ZDM jumpbox server
- `zdm_orchestrate_discovery.sh` - Master script to run all discoveries remotely

**Usage**:
1. Run the Step 0 prompt
2. Scripts are saved to `Artifacts/Phase10-Migration/ZDM/<DB_NAME>/Scripts/`
3. Copy scripts to respective servers and execute
4. Collect output files to `Artifacts/Phase10-Migration/ZDM/<DB_NAME>/Discovery/`

### Step 1: Discovery and Questionnaire

**Purpose**: Complete a comprehensive questionnaire with all information needed for migration.

**Inputs**:
- Discovery output files (from Step 0 scripts)
- Manual information (credentials, OCIDs, etc.)

**Output**: Completed questionnaire document

**Usage**:
1. Attach discovery output files from `Artifacts/Phase10-Migration/ZDM/<DB_NAME>/Discovery/`
2. Fill in auto-populated fields (🔍) from discovery outputs
3. Complete manual fields (🔐) with credentials and OCIDs
4. Verify all information is correct

### Step 2: Generate Migration Artifacts

**Purpose**: Generate all artifacts needed to execute the migration.

**Inputs**:
- Completed questionnaire (from Step 1)
- Discovery output files

**Outputs** (saved to `Artifacts/Phase10-Migration/ZDM/<DB_NAME>/`):
- `zdm_migrate_<DB_NAME>.rsp` - ZDM response file
- `zdm_commands_<DB_NAME>.sh` - CLI commands script
- `ZDM-Migration-Runbook-<DB_NAME>.md` - Step-by-step runbook

**Usage**:
1. Provide completed questionnaire
2. Artifacts are saved to `Artifacts/Phase10-Migration/ZDM/<DB_NAME>/`
3. Review generated artifacts
4. Create password files as instructed
5. Follow the runbook to execute migration

## Artifacts Directory Structure

Each migration creates a dedicated folder under `Artifacts/Phase10-Migration/ZDM/`:

```
Artifacts/Phase10-Migration/ZDM/
└── <DB_NAME>/                          # e.g., PRODDB
    ├── Scripts/                        # Discovery scripts (Step 0)
    │   ├── zdm_source_discovery.sh
    │   ├── zdm_target_discovery.sh
    │   ├── zdm_server_discovery.sh
    │   └── zdm_orchestrate_discovery.sh
    ├── Discovery/                      # Discovery outputs
    │   ├── zdm_source_discovery_*.txt
    │   ├── zdm_source_discovery_*.json
    │   ├── zdm_target_discovery_*.txt
    │   ├── zdm_target_discovery_*.json
    │   ├── zdm_server_discovery_*.txt
    │   └── zdm_server_discovery_*.json
    ├── Questionnaire/                  # Completed questionnaires
    │   └── Step1-Completed-<DB_NAME>.md
    ├── zdm_migrate_<DB_NAME>.rsp       # Generated RSP file (Step 2)
    ├── zdm_commands_<DB_NAME>.sh       # Generated CLI script (Step 2)
    └── ZDM-Migration-Runbook-<DB_NAME>.md  # Generated runbook (Step 2)
```

## Migration Types

### Online Physical Migration
- **Downtime**: Minutes (during switchover only)
- **Method**: Uses Oracle Data Guard for real-time replication
- **Best for**: Production databases requiring minimal downtime
- **Requirements**: Network connectivity between source and target for Data Guard

### Offline Physical Migration
- **Downtime**: Hours (depends on database size and network speed)
- **Method**: RMAN backup and restore via Object Storage
- **Best for**: Non-production databases or when Data Guard is not feasible
- **Requirements**: Object Storage bucket for backup transfer

## Prerequisites

### ZDM Server
- ZDM 21c or later installed
- OCI CLI configured with API key authentication
- SSH key access to source and target servers
- Java 8+ installed

### Source Database
- Oracle 11.2.0.4 or later
- For online migration: ARCHIVELOG mode, Force Logging, Supplemental Logging
- SSH access from ZDM server
- Password file configured

### Target (Oracle Database@Azure)
- Database system provisioned in OCI/Azure
- Network connectivity established (ExpressRoute/VPN)
- SSH access from ZDM server
- Object Storage bucket for backup transfer

## Network Requirements

| From | To | Port | Purpose |
|------|-----|------|---------|
| ZDM | Source | 22 | SSH for remote execution |
| ZDM | Source | 1521 | Database connectivity |
| ZDM | Target | 22 | SSH for remote execution |
| ZDM | Target | 1521 | Database connectivity |
| ZDM | OCI OSS | 443 | Backup transfer |
| Source | Target | 1521 | Data Guard (online only) |

## Best Practices

1. **Always run Step 0 first** - Ensures scripts contain latest discovery logic
2. **Verify all questionnaire fields** - Incorrect values cause migration failures
3. **Test connectivity before migration** - Use the connectivity matrix in questionnaire
4. **Create password files securely** - Never embed passwords in scripts
5. **Review generated runbook** - Understand each step before execution
6. **Plan for rollback** - Know the rollback procedures before starting

## Support Resources

- [Oracle ZDM Documentation](https://docs.oracle.com/en/database/oracle/zero-downtime-migration/)
- [Oracle Database@Azure Documentation](https://docs.oracle.com/en-us/iaas/Content/multicloud/oaa.htm)
- [OCI CLI Documentation](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/cliconcepts.htm)
