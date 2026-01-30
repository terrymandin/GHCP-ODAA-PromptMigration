# ZDM Migration Prompts

This directory contains prompts for Zero Downtime Migration (ZDM) from on-premise Oracle databases to Oracle Database@Azure.

## Migration Workflow

The ZDM migration process is divided into four steps, each with its own prompt:

```
Step 0: Generate Discovery Scripts + Run to Get Context
         ↓
         ├── Generate discovery scripts
         ├── Run discovery scripts on servers
         └── Collect discovery outputs
         ↓
Step 1: Get Manual Configuration Context
         ↓
         ├── Analyze discovery results
         ├── Generate Discovery Summary
         └── Complete Migration Questionnaire (manual decisions)
         ↓
Step 2: Fix Issues (Iteration may be required)
         ↓
         ├── Address critical actions from Discovery Summary
         ├── Re-run discovery to verify fixes
         └── Repeat until all blockers resolved
         ↓
Step 3: Generate Migration Artifacts & Run Migration
         ↓
         ├── Generate RSP file
         ├── Generate ZDM CLI commands
         ├── Generate Migration Runbook
         └── Execute migration
```

### What Gets Captured Where?

| Information Type | Captured In Step | Examples |
|-----------------|------------------|----------|
| **Technical Configuration** | Step 0 - Discovery Scripts (auto) | DB version, character set, TDE status, storage |
| **Business Decisions** | Step 1 - Migration Questionnaire (manual) | Online vs Offline, timeline, downtime tolerance |
| **OCI/Azure IDs** | Step 1 - Migration Questionnaire (manual) | OCIDs, subscription IDs |
| **Issue Resolution** | Step 2 - Fix Issues (iterative) | Enable supplemental logging, configure network |
| **Migration Config** | Step 3 - RSP/CLI generation (auto) | Response file, commands, runbook |

## Prompt Files

| Step | File | Example | Purpose |
|------|------|---------|---------|
| 0 | [Step0-Generate-Discovery-Scripts.prompt.md](Step0-Generate-Discovery-Scripts.prompt.md) | [Example](Example-Step0-Generate-Discovery-Scripts.prompt.md) | Generate and run discovery scripts |
| 1 | [Step1-Discovery-Questionnaire.prompt.md](Step1-Discovery-Questionnaire.prompt.md) | [Example](Example-Step1-Discovery-Questionnaire.prompt.md) | Analyze discovery, complete questionnaire |
| 2 | [Step2-Fix-Issues.prompt.md](Step2-Fix-Issues.prompt.md) | [Example](Example-Step2-Fix-Issues.prompt.md) | Address blockers, iterate until resolved |
| 3 | [Step3-Generate-Migration-Artifacts.prompt.md](Step3-Generate-Migration-Artifacts.prompt.md) | [Example](Example-Step3-Generate-Migration-Artifacts.prompt.md) | Generate RSP file, CLI commands, runbook |

## Example Files

Each step has a corresponding example file showing a completed prompt for a fictional "PRODDB" migration:

| Example | Description |
|---------|-------------|
| [Example-Step0](Example-Step0-Generate-Discovery-Scripts.prompt.md) | Shows how to request discovery scripts with custom requirements |
| [Example-Step1](Example-Step1-Discovery-Questionnaire.prompt.md) | Shows a fully completed questionnaire for online physical migration |
| [Example-Step2](Example-Step2-Fix-Issues.prompt.md) | Shows iterative issue resolution and verification |
| [Example-Step3](Example-Step3-Generate-Migration-Artifacts.prompt.md) | Shows expected RSP file, CLI script, and runbook output |
| [Example-Step2](Example-Step2-Fix-Issues.prompt.md) | Shows iterative issue resolution and verification |
| [Example-Step3](Example-Step3-Generate-Migration-Artifacts.prompt.md) | Shows expected RSP file, CLI script, and runbook output |

## Detailed Workflow

### Step 0: Generate Discovery Scripts + Run to Get Context

**Purpose**: Generate and execute discovery scripts to gather technical context from all servers.

**Output**: 
- Four bash scripts saved to `Artifacts/Phase10-Migration/ZDM/<DB_NAME>/Step0/Scripts/`
  - `zdm_source_discovery.sh` - Run on source database server
  - `zdm_target_discovery.sh` - Run on target Oracle Database@Azure server
  - `zdm_server_discovery.sh` - Run on ZDM jumpbox server
  - `zdm_orchestrate_discovery.sh` - Master script to run all discoveries remotely
- Discovery outputs saved to `Artifacts/Phase10-Migration/ZDM/<DB_NAME>/Step0/Discovery/`
  - Source, target, and server discovery results (TXT and JSON)

**Usage**:
1. Run the Step 0 prompt to generate discovery scripts
2. Copy discovery scripts to respective servers and execute
3. Collect output files to `Artifacts/Phase10-Migration/ZDM/<DB_NAME>/Step0/Discovery/`

### Step 1: Get Manual Configuration Context

**Purpose**: Analyze discovery results and collect manual configuration decisions via questionnaire.

**Inputs**:
- Discovery output files (from Step 0)

**Output Location**: `Artifacts/Phase10-Migration/ZDM/<DB_NAME>/Step1/`
- `Discovery-Summary-<DB_NAME>.md` - Auto-populated findings from discovery
- `Migration-Questionnaire-<DB_NAME>.md` - Manual decisions with recommended defaults

**The Questionnaire captures:**
- Migration type (Online Physical vs Offline Physical)
- Migration timeline and downtime tolerance
- OCI/Azure identifiers (OCIDs, subscription IDs)
- Credential storage references (NOT actual passwords)
- Network and backup configuration choices
- Data Guard settings (for online migration)
- Execution options (auto-switchover, pause points)
- Rollback plans and risk mitigation

**Usage**:
1. Attach discovery output files from `Step0/Discovery/`
2. Review generated Discovery Summary
3. Complete the Migration Questionnaire with business decisions
4. Note critical actions that need to be addressed in Step 2

### Step 2: Fix Issues (Iteration May Be Required)

**Purpose**: Address blockers and critical actions identified in the Discovery Summary before proceeding.

**Inputs**:
- Discovery Summary (from Step 1)
- Migration Questionnaire (from Step 1)

**Output Location**: `Artifacts/Phase10-Migration/ZDM/<DB_NAME>/Step2/`
- `Issue-Resolution-Log-<DB_NAME>.md` - Tracking of issues and resolutions
- Updated discovery outputs (after re-running discovery to verify fixes)

**Common Issues to Address:**
- Enable supplemental logging on source database
- Install and configure OCI CLI on ZDM server
- Configure network connectivity (NSG/firewall rules)
- Set up SSH key authentication
- Verify TDE wallet configuration
- Resolve storage or capacity issues

**Iterative Process:**
1. Review blockers from Discovery Summary
2. Execute remediation steps
3. Re-run relevant discovery scripts to verify fixes
4. Update Issue Resolution Log
5. Repeat until all critical actions are resolved
6. Proceed to Step 3 only when all blockers are cleared

### Step 3: Generate Migration Artifacts & Run Migration

**Purpose**: Generate all artifacts needed to execute the migration.

**Inputs**:
- Completed questionnaire (from Step 1)
- Issue Resolution Log (from Step 2 - confirming all blockers resolved)
- Discovery output files (from Step 0)

**Output Location**: `Artifacts/Phase10-Migration/ZDM/<DB_NAME>/Step3/`
- `zdm_migrate_<DB_NAME>.rsp` - ZDM response file
- `zdm_commands_<DB_NAME>.sh` - CLI commands script
- `ZDM-Migration-Runbook-<DB_NAME>.md` - Step-by-step runbook

**Usage**:
1. Ensure all issues from Step 2 are resolved
2. Provide completed questionnaire from `Step1/`
3. Artifacts are saved to `Step3/`
4. Review generated artifacts
5. Create password files as instructed
6. Follow the runbook to execute migration

## Artifacts Directory Structure

Each migration creates a dedicated folder under `Artifacts/Phase10-Migration/ZDM/`:

```
Artifacts/Phase10-Migration/ZDM/
└── <DB_NAME>/                              # e.g., PRODDB
    ├── Step0/                              # Step 0: Run Scripts to Get Context
    │   ├── Scripts/                        # Discovery scripts
    │   │   ├── zdm_source_discovery.sh
    │   │   ├── zdm_target_discovery.sh
    │   │   ├── zdm_server_discovery.sh
    │   │   ├── zdm_orchestrate_discovery.sh
    │   │   └── README.md
    │   └── Discovery/                      # Discovery outputs
    │       ├── source/
    │       │   ├── zdm_source_discovery_*.txt
    │       │   └── zdm_source_discovery_*.json
    │       ├── target/
    │       │   ├── zdm_target_discovery_*.txt
    │       │   └── zdm_target_discovery_*.json
    │       └── server/
    │           ├── zdm_server_discovery_*.txt
    │           └── zdm_server_discovery_*.json
    ├── Step1/                              # Step 1: Get Manual Configuration Context
    │   ├── Discovery-Summary-<DB_NAME>.md
    │   └── Migration-Questionnaire-<DB_NAME>.md
    ├── Step2/                              # Step 2: Fix Issues (Iterative)
    │   ├── Issue-Resolution-Log-<DB_NAME>.md
    │   └── Verification/                   # Re-run discovery outputs
    │       └── (updated discovery files)
    └── Step3/                              # Step 3: Migration Artifacts & Execution
        ├── zdm_migrate_<DB_NAME>.rsp
        ├── zdm_commands_<DB_NAME>.sh
        └── ZDM-Migration-Runbook-<DB_NAME>.md
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
