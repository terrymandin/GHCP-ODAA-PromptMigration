# ZDM Migration Prompts

This directory contains prompts for Zero Downtime Migration (ZDM) from on-premise Oracle databases to Oracle Database@Azure.

## Migration Workflow

The ZDM migration process is divided into five steps, each with its own prompt:

```
Step 1: Test SSH Connectivity (fail-fast precheck)
         ↓
         ├── Validate source/target SSH hosts
         ├── Validate SSH key files + permissions
         └── Confirm non-interactive SSH works
         ↓
Step 2: Generate Discovery Scripts + Run to Get Context
         ↓
         ├── Generate discovery scripts
         ├── Run discovery scripts on servers
         └── Collect discovery outputs
         ↓
Step 3: Get Manual Configuration Context
         ↓
         ├── Analyze discovery results
         ├── Generate Discovery Summary
         └── Complete Migration Questionnaire (manual decisions)
         ↓
Step 4: Fix Issues (Iteration may be required)
         ↓
         ├── Address critical actions from Discovery Summary
         ├── Re-run discovery to verify fixes
         └── Repeat until all blockers resolved
         ↓
Step 5: Generate Migration Artifacts & Run Migration
         ↓
         ├── Generate RSP file
         ├── Generate ZDM CLI commands
         ├── Generate Migration Runbook
         └── Execute migration
```

### What Gets Captured Where?

| Information Type | Captured In Step | Examples |
|-----------------|------------------|----------|
| **SSH Connectivity Readiness** | Step 1 - SSH Connectivity Test (auto) | Reachability, key file validation, SSH auth precheck |
| **Technical Configuration** | Step 2 - Discovery Scripts (auto) | DB version, character set, TDE status, storage |
| **Business Decisions** | Step 3 - Migration Questionnaire (manual) | Online vs Offline, timeline, downtime tolerance |
| **OCI/Azure IDs** | Step 3 - Migration Questionnaire (manual) | OCIDs, subscription IDs |
| **Issue Resolution** | Step 4 - Fix Issues (iterative) | Enable supplemental logging, configure network |
| **Migration Config** | Step 5 - RSP/CLI generation (auto) | Response file, commands, runbook |

## Prompt Files

| Step | File | Example | Purpose |
|------|------|---------|---------|
| 1 | [Phase10-ZDM-Step1-Test-SSH-Connectivity.prompt.md](Phase10-ZDM-Step1-Test-SSH-Connectivity.prompt.md) | [Example](Phase10-ZDM-Example-Step1-Test-SSH-Connectivity.prompt.md) | Validate SSH hosts and keys before discovery |
| 2 | [Phase10-ZDM-Step2-Generate-Discovery-Scripts.prompt.md](Phase10-ZDM-Step2-Generate-Discovery-Scripts.prompt.md) | [Example](Phase10-ZDM-Example-Step2-Generate-Discovery-Scripts.prompt.md) | Generate and run discovery scripts |
| 3 | [Phase10-ZDM-Step3-Discovery-Questionnaire.prompt.md](Phase10-ZDM-Step3-Discovery-Questionnaire.prompt.md) | [Example](Phase10-ZDM-Example-Step3-Discovery-Questionnaire.prompt.md) | Analyze discovery, complete questionnaire |
| 4 | [Phase10-ZDM-Step4-Fix-Issues.prompt.md](Phase10-ZDM-Step4-Fix-Issues.prompt.md) | [Example](Phase10-ZDM-Example-Step4-Fix-Issues.prompt.md) | Address blockers, iterate until resolved |
| 5 | [Phase10-ZDM-Step5-Generate-Migration-Artifacts.prompt.md](Phase10-ZDM-Step5-Generate-Migration-Artifacts.prompt.md) | [Example](Phase10-ZDM-Example-Step5-Generate-Migration-Artifacts.prompt.md) | Generate RSP file, CLI commands, runbook |

## Example Files

Each step has a corresponding example file showing a completed prompt for a fictional "PRODDB" migration:

| Example | Description |
|---------|-------------|
| [Example-Step1](Phase10-ZDM-Example-Step1-Test-SSH-Connectivity.prompt.md) | Shows SSH host/key connectivity validation before discovery |
| [Example-Step2](Phase10-ZDM-Example-Step2-Generate-Discovery-Scripts.prompt.md) | Shows how to request discovery scripts with custom requirements |
| [Example-Step3](Phase10-ZDM-Example-Step3-Discovery-Questionnaire.prompt.md) | Shows a fully completed questionnaire for online physical migration |
| [Example-Step4](Phase10-ZDM-Example-Step4-Fix-Issues.prompt.md) | Shows iterative issue resolution and verification |
| [Example-Step5](Phase10-ZDM-Example-Step5-Generate-Migration-Artifacts.prompt.md) | Shows expected RSP file, CLI script, and runbook output |

## Detailed Workflow

### Step 1: Test SSH Connectivity (Precheck)

**Purpose**: Fail fast on bad SSH IP/hostname, user, key, or key permission inputs before running the longer discovery step.

**Output**:
- SSH precheck script saved to `Artifacts/Phase10-Migration/Step1/Scripts/`
  - `zdm_test_ssh_connectivity.sh`
- Validation outputs saved to `Artifacts/Phase10-Migration/Step1/Validation/`
  - `ssh-connectivity-report-<timestamp>.md`
  - `ssh-connectivity-report-<timestamp>.json`

**Usage**:
1. Fill SSH host/user/key values in `zdm-env.md`
2. Run the Step 1 prompt to generate the precheck script
3. Execute the script on the ZDM server as `zdmuser`
4. Resolve any SSH failures before proceeding to Step 2

### Step 2: Generate Discovery Scripts + Run to Get Context

**Purpose**: Generate discovery scripts to gather technical context from all servers.

**Output**: 
- Four bash scripts saved to `Artifacts/Phase10-Migration/Step2/Scripts/`
  - `zdm_source_discovery.sh` - Run on source database server
  - `zdm_target_discovery.sh` - Run on target Oracle Database@Azure server
  - `zdm_server_discovery.sh` - Run on ZDM jumpbox server
  - `zdm_orchestrate_discovery.sh` - Master script to run all discoveries remotely
- Discovery outputs saved to `Artifacts/Phase10-Migration/Step2/Discovery/`
  - Source, target, and server discovery results (TXT and JSON)

**Usage**:
1. Run the Step 2 prompt to generate discovery scripts
2. Copy discovery scripts to respective servers and execute
3. Collect output files to `Artifacts/Phase10-Migration/Step2/Discovery/`

### Step 3: Get Manual Configuration Context

**Purpose**: Analyze discovery results and collect manual configuration decisions via questionnaire.

**Inputs**:
- Discovery output files (from Step 2)

**Output Location**: `Artifacts/Phase10-Migration/Step3/`
- `Discovery-Summary.md` - Auto-populated findings from discovery
- `Migration-Questionnaire.md` - Manual decisions with recommended defaults

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
1. Attach discovery output files from `Step2/Discovery/`
2. Review generated Discovery Summary
3. Complete the Migration Questionnaire with business decisions
4. Note critical actions that need to be addressed in Step 4

### Step 4: Fix Issues (Iteration May Be Required)

**Purpose**: Address blockers and critical actions identified in the Discovery Summary before proceeding.

**Inputs**:
- Discovery Summary (from Step 3)
- Migration Questionnaire (from Step 3)

**Output Location**: `Artifacts/Phase10-Migration/Step4/`
- `Issue-Resolution-Log.md` - Tracking of issues and resolutions
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
6. Proceed to Step 5 only when all blockers are cleared

### Step 5: Generate Migration Artifacts & Run Migration

**Purpose**: Generate all artifacts needed to execute the migration.

**Inputs**:
- Completed questionnaire (from Step 3)
- Issue Resolution Log (from Step 4 - confirming all blockers resolved)
- Discovery output files (from Step 2)

**Output Location**: `Artifacts/Phase10-Migration/Step5/`
- `README.md` - Quick-start guide and checklist
- `zdm_migrate.rsp` - ZDM response file
- `zdm_commands.sh` - CLI commands script with `init`, `create-creds`, and migration commands
- `ZDM-Migration-Runbook.md` - Step-by-step runbook

**Usage**:
1. Ensure all issues from Step 4 are resolved
2. Provide completed questionnaire from `Step3/`
3. Artifacts are saved to `Step5/`
4. Review generated artifacts
5. Commit and push to GitHub
6. Pull changes on ZDM jumpbox
7. Follow the runbook to execute migration

---

## End-to-End Workflow

The complete workflow alternates between your local VS Code environment and the ZDM server. This swimlane diagram shows where each action occurs:

```
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                              ZDM MIGRATION WORKFLOW                                          │
├────────────────────────────────────┬────────────────────────────────────────────────────────┤
│         💻 VS CODE (Local)         │              🖥️ ZDM SERVER                             │
├────────────────────────────────────┼────────────────────────────────────────────────────────┤
│                                    │                                                        │
│  ┌──────────────────────────────┐  │                                                        │
│  │ 1. Fork & Clone Repo         │  │                                                        │
│  └──────────────┬───────────────┘  │                                                        │
│                 ▼                  │                                                        │
│  ┌──────────────────────────────┐  │                                                        │
│  │ 2. Run Step2 Prompt          │  │                                                        │
│  │    → Generate discovery      │  │                                                        │
│  │      scripts                 │  │                                                        │
│  └──────────────┬───────────────┘  │                                                        │
│                 ▼                  │                                                        │
│  ┌──────────────────────────────┐  │                                                        │
│  │ 3. git commit & push         │──┼───────────────────┐                                    │
│  └──────────────────────────────┘  │                   ▼                                    │
│                                    │  ┌────────────────────────────────────────────────┐    │
│                                    │  │ 4. SSH as admin user (azureuser/opc)           │    │
│                                    │  │    sudo su - zdmuser                           │    │
│                                    │  └──────────────────────┬─────────────────────────┘    │
│                                    │                         ▼                              │
│                                    │  ┌────────────────────────────────────────────────┐    │
│                                    │  │ 5. git clone <fork-url>                        │    │
│                                    │  └──────────────────────┬─────────────────────────┘    │
│                                    │                         ▼                              │
│                                    │  ┌────────────────────────────────────────────────┐    │
│                                    │  │ 6. Run discovery scripts                       │    │
│                                    │  │    (source, target, ZDM servers)               │    │
│                                    │  └──────────────────────┬─────────────────────────┘    │
│                                    │                         ▼                              │
│                   ┌────────────────┼──│ 7. git commit & push artifacts                 │    │
│                   ▼                │  └────────────────────────────────────────────────┘    │
│  ┌──────────────────────────────┐  │                                                        │
│  │ 8. git pull                  │  │                                                        │
│  └──────────────┬───────────────┘  │                                                        │
│                 ▼                  │                                                        │
│  ┌──────────────────────────────┐  │                                                        │
│  │ 9. Run Step3 Prompt          │  │                                                        │
│  │    → Analyze discovery       │  │                                                        │
│  │    → Generate questionnaire  │  │                                                        │
│  └──────────────┬───────────────┘  │                                                        │
│                 ▼                  │                                                        │
│  ┌──────────────────────────────┐  │                                                        │
│  │ 10. Complete questionnaire   │  │                                                        │
│  │     (manual decisions)       │  │                                                        │
│  └──────────────┬───────────────┘  │                                                        │
│                 ▼                  │                                                        │
│  ┌──────────────────────────────┐  │                                                        │
│  │ 11. Run Step4 Prompt         │  │                                                        │
│  │     → Identify issues        │  │                                                        │
│  └──────────────┬───────────────┘  │                                                        │
│                 │                  │                                                        │
│     ┌───────────┴───────────┐      │                                                        │
│     │  ITERATE UNTIL FIXED  │◄─────┼──────────────────────────────────────────┐             │
│     │  ┌─────────────────┐  │      │                                          │             │
│     │  │ Fix issues      │──┼──────┼───► Re-run discovery on servers ─────────┤             │
│     │  │ Re-run Step3/4  │◄─┼──────┼──── git commit/push artifacts ◄──────────┘             │
│     │  └─────────────────┘  │      │                                                        │
│     └───────────┬───────────┘      │                                                        │
│                 ▼                  │                                                        │
│  ┌──────────────────────────────┐  │                                                        │
│  │ 12. Run Step5 Prompt         │  │                                                        │
│  │     → Generate RSP, CLI,     │  │                                                        │
│  │       Runbook                │  │                                                        │
│  └──────────────┬───────────────┘  │                                                        │
│                 ▼                  │                                                        │
│  ┌──────────────────────────────┐  │                                                        │
│  │ 13. git commit & push        │──┼───────────────────┐                                    │
│  └──────────────────────────────┘  │                   ▼                                    │
│                                    │  ┌────────────────────────────────────────────────┐    │
│                                    │  │ 14. git pull                                   │    │
│                                    │  └──────────────────────┬─────────────────────────┘    │
│                                    │                         ▼                              │
│                                    │  ┌────────────────────────────────────────────────┐    │
│                                    │  │ 15. ./zdm_commands.sh init                     │    │
│                                    │  │     → Creates ~/creds, ~/zdm_oci_env.sh        │    │
│                                    │  └──────────────────────┬─────────────────────────┘    │
│                                    │                         ▼                              │
│                                    │  ┌────────────────────────────────────────────────┐    │
│                                    │  │ 16. Edit ~/zdm_oci_env.sh with OCIDs           │    │
│                                    │  │     source ~/zdm_oci_env.sh                    │    │
│                                    │  └──────────────────────┬─────────────────────────┘    │
│                                    │                         ▼                              │
│                                    │  ┌────────────────────────────────────────────────┐    │
│                                    │  │ 17. Set passwords & create-creds               │    │
│                                    │  └──────────────────────┬─────────────────────────┘    │
│                                    │                         ▼                              │
│                                    │  ┌────────────────────────────────────────────────┐    │
│                                    │  │ 18. Follow Runbook                             │    │
│                                    │  │     → eval → migrate → resume → cleanup        │    │
│                                    │  └────────────────────────────────────────────────┘    │
│                                    │                                                        │
└────────────────────────────────────┴────────────────────────────────────────────────────────┘
```

### Quick Reference: Where Does Each Step Run?

| Phase | Location | Actions |
|-------|----------|---------|
| **Setup** | VS Code | Fork repo, clone, run Step1 prompt (SSH precheck), then run Step2 prompt |
| **Discovery** | ZDM Server | Clone fork, run discovery scripts, commit artifacts |
| **Analysis** | VS Code | Pull, run Step3/4 prompts, complete questionnaire |
| **Iteration** | Both | Fix issues on servers, re-run discovery, update Step3/4 |
| **Generation** | VS Code | Run Step5 prompt, commit artifacts |
| **Migration** | ZDM Server | Pull, init, configure, execute migration |

### Important: ZDM Server Login

When working on the ZDM server, you must:
1. **SSH as your admin user** (e.g., `azureuser`, `opc`) - NOT directly as `zdmuser`
2. **Switch to zdmuser**: `sudo su - zdmuser`
3. **First-time setup**: Run `./zdm_commands.sh init` to create required directories and files

---

## Artifacts Directory Structure

Each migration creates its artifacts directly under `Artifacts/Phase10-Migration/`:

```
Artifacts/Phase10-Migration/
├── Step1/                              # Step 1: Test SSH Connectivity
│   ├── Scripts/
│   │   └── zdm_test_ssh_connectivity.sh
│   └── Validation/
│       ├── ssh-connectivity-report-*.md
│       └── ssh-connectivity-report-*.json
├── Step2/                              # Step 2: Run Scripts to Get Context
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
├── Step3/                              # Step 3: Get Manual Configuration Context
│   ├── Discovery-Summary.md
│   └── Migration-Questionnaire.md
├── Step4/                              # Step 4: Fix Issues (Iterative)
│   ├── Issue-Resolution-Log.md
│   └── Verification/                   # Re-run discovery outputs
│       └── (updated discovery files)
└── Step5/                              # Step 5: Migration Artifacts & Execution
    ├── zdm_migrate.rsp
    ├── zdm_commands.sh
    └── ZDM-Migration-Runbook.md
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

1. **Always run Step 1 first** - Catch bad SSH host/key inputs before long-running discovery
2. **Run Step 2 next** - Ensures scripts contain latest discovery logic
3. **Verify all questionnaire fields** - Incorrect values cause migration failures
4. **Test connectivity before migration** - Use the connectivity matrix in questionnaire
5. **Create password files securely** - Never embed passwords in scripts
6. **Review generated runbook** - Understand each step before execution
7. **Plan for rollback** - Know the rollback procedures before starting

## Support Resources

- [Oracle ZDM Documentation](https://docs.oracle.com/en/database/oracle/zero-downtime-migration/)
- [Oracle Database@Azure Documentation](https://docs.oracle.com/en-us/iaas/Content/multicloud/oaa.htm)
- [OCI CLI Documentation](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/cliconcepts.htm)
