# ZDM Migration Prompts

This directory contains prompts for Zero Downtime Migration (ZDM) from on-premise Oracle databases to Oracle Database@Azure.

## Migration Workflow

The ZDM migration process is divided into six steps, each with its own prompt:

```
Step 1: Setup Remote-SSH Connection (local VS Code session)
         ↓
         ├── Check Remote-SSH extension is installed
         ├── Configure ~/.ssh/config for jumpbox
         └── Verify SSH key and test connectivity
         ↓
Step 2: Configure SSH Connectivity (Remote-SSH session begins)
         ↓
         ├── Collect SSH host, user, key values interactively
         ├── Validate SSH connectivity to source/target
         └── Write ssh-config.md artifact
         ↓
Step 3: Generate Discovery + Run to Get Context
         ↓
         ├── Collect Oracle home, SID, unique names interactively
         ├── Run discovery commands inline on all servers
         └── Write discovery reports and db-config.md
         ↓
Step 4: Get Manual Configuration Context
         ↓
         ├── Analyze discovery results
         ├── Generate Discovery Summary
         └── Complete Migration Questionnaire (manual decisions)
         ↓
Step 5: Fix Issues (Iteration may be required)
         ↓
         ├── Address critical actions from Discovery Summary
         ├── Re-run discovery to verify fixes
         └── Repeat until all blockers resolved
         ↓
Step 6: Generate Migration Artifacts & Run Migration
         ↓
         ├── Generate RSP file
         ├── Generate ZDM CLI commands
         ├── Generate Migration Runbook
         └── Execute migration
```

### What Gets Captured Where?

| Information Type | Captured In Step | Examples |
|-----------------|------------------|----------|
| **Remote-SSH Setup** | Step 1 - SSH Setup (local) | Extension check, ssh-config entry, key generation |
| **SSH Connectivity Readiness** | Step 2 - SSH Connectivity (auto) | Reachability, key validation, SSH auth precheck |
| **Technical Configuration** | Step 3 - Discovery (auto) | DB version, character set, TDE status, storage |
| **Business Decisions** | Step 4 - Migration Questionnaire (manual) | Online vs Offline, timeline, downtime tolerance |
| **OCI/Azure IDs** | Step 4 - Migration Questionnaire (manual) | OCIDs, subscription IDs |
| **Issue Resolution** | Step 5 - Fix Issues (iterative) | Enable supplemental logging, configure network |
| **Migration Config** | Step 6 - RSP/CLI generation (auto) | Response file, commands, runbook |

## Prompt Files

| Step | File | Purpose |
|------|------|---------|
| 1 | [Phase10-Step1-Setup-Remote-SSH.prompt.md](Phase10-Step1-Setup-Remote-SSH.prompt.md) | Configure Remote-SSH extension, SSH key, and jumpbox host entry |
| 2 | [Phase10-Step2-Configure-SSH-Connectivity.prompt.md](Phase10-Step2-Configure-SSH-Connectivity.prompt.md) | Collect SSH inputs interactively and validate connectivity |
| 3 | [Phase10-Step3-Generate-Discovery-Scripts.prompt.md](Phase10-Step3-Generate-Discovery-Scripts.prompt.md) | Collect DB inputs and run discovery commands inline |
| 4 | [Phase10-Step4-Discovery-Questionnaire.prompt.md](Phase10-Step4-Discovery-Questionnaire.prompt.md) | Analyze discovery, complete questionnaire |
| 5 | [Phase10-Step5-Fix-Issues.prompt.md](Phase10-Step5-Fix-Issues.prompt.md) | Address blockers, iterate until resolved |
| 6 | [Phase10-Step6-Generate-Migration-Artifacts.prompt.md](Phase10-Step6-Generate-Migration-Artifacts.prompt.md) | Generate RSP file, CLI commands, runbook |

## Example Files

> Note: Example prompt files have been removed. Use `@Phase10-ZDM-Orchestrator` to auto-detect your current step and execute it.

## Detailed Workflow

### Step 1: Setup Remote-SSH Connection

**Purpose**: Configure the Remote-SSH extension, SSH key, and jumpbox host entry so subsequent steps (Step 2 onward) can run in the correct Remote-SSH context as `zdmuser`.

> **Execution context**: Step 1 runs in a **local** VS Code session (NOT via Remote-SSH). Use the local PowerShell terminal.

**Output** (git-ignored, written during prompt execution):
- `Artifacts/Phase10-Migration/Step1/remote-ssh-setup-report.md` — setup report with READY or ACTION REQUIRED status

**Usage**:
1. Open VS Code locally (not via Remote-SSH)
2. Run the Step 1 prompt — it will check the Remote-SSH extension, configure `~/.ssh/config`, and test SSH key connectivity
3. Follow the prompted instructions to connect via Remote-SSH: `Ctrl+Shift+P` → Remote-SSH: Connect to Host → select the jumpbox alias
4. Once connected, proceed to Step 2 in the Remote-SSH session

### Step 2: Configure SSH Connectivity

**Purpose**: Confirm SSH connectivity to source, target, and ZDM servers from the jumpbox and capture SSH configuration.

> **Prerequisite**: VS Code must be connected to the ZDM jumpbox via the **Remote-SSH** extension as `zdmuser`. Step 2 runs the SSH tests directly from the jumpbox terminal.

**Output** (git-ignored, written during prompt execution):
- `Artifacts/Phase10-Migration/Step2/ssh-config.md` — SSH connectivity config (pre-populate this file to skip interactive collection)
- Validation report saved to `Artifacts/Phase10-Migration/Step2/Validation/`
  - `ssh-connectivity-report-<timestamp>.md`
  - `ssh-connectivity-report-<timestamp>.json`
- `Scripts/zdm_test_ssh_connectivity.sh` — only generated if direct terminal commands are insufficient; left in place for debugging if created.

**Usage**:
1. In the Remote-SSH VS Code session (as `zdmuser`), run the Step 2 prompt
2. It will interactively collect SSH host, user, and key values, confirm them, then test connectivity directly from the jumpbox terminal, iterating up to 3 times on failure
3. Resolve any SSH failures before proceeding to Step 3
4. Resolve any SSH failures before proceeding to Step 2

### Step 3: Generate Discovery + Run to Get Context

**Purpose**: Collect Oracle home paths, SIDs, and database unique names interactively, then run discovery commands inline on all servers.

**Output**: 
- `Artifacts/Phase10-Migration/Step3/db-config.md` — database and ZDM config (pre-populate to skip interactive collection)
- Discovery reports saved to `Artifacts/Phase10-Migration/Step3/Discovery/`
  - Source, target, and server discovery results (.md and .json)
- Optional debug scripts under `Artifacts/Phase10-Migration/Step3/Scripts/`

**Usage**:
1. Run the Step 3 prompt in the Remote-SSH session (as `zdmuser`)
2. It will collect Oracle home, SID, and unique name values interactively if not pre-populated
3. Discovery commands run inline — no scripts need to be manually copied or executed
4. Discovery outputs are written automatically after each discovery stage completes

### Step 4: Get Manual Configuration Context

**Purpose**: Analyze discovery results and collect manual configuration decisions via questionnaire.

**Inputs**:
- Discovery output files (from Step 3)

**Output Location**: `Artifacts/Phase10-Migration/Step4/`
- `Discovery-Summary.md` - Auto-populated findings from discovery
- `Migration-Decisions.md` - Completed Decisions Record from migration planning interview

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
1. Attach discovery output files from `Step3/Discovery/`
2. Review generated Discovery Summary
3. Complete the Migration Questionnaire with business decisions
4. Note critical actions that need to be addressed in Step 5

### Step 5: Fix Issues (Iteration May Be Required)

**Purpose**: Address blockers and critical actions identified in the Discovery Summary before proceeding.

**Inputs**:
- Discovery Summary (from Step 4)
- Migration Questionnaire (from Step 4)

**Output Location**: `Artifacts/Phase10-Migration/Step5/`
- `Issue-Resolution-Log.md` - Tracking of issues and resolutions
- Updated discovery outputs (after re-running discovery to verify fixes)

**Common Issues to Address:**
- Enable supplemental logging on source database
- Configure OCI authentication files for zdmuser on ZDM server
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
6. Proceed to Step 6 only when all blockers are cleared

### Step 6: Generate Migration Artifacts & Run Migration

**Purpose**: Generate all artifacts needed to execute the migration.

**Inputs**:
- Completed questionnaire (from Step 4)
- Issue Resolution Log (from Step 5 - confirming all blockers resolved)
- Discovery output files (from Step 3)

**Output Location**: `Artifacts/Phase10-Migration/Step6/`
- `README.md` - Quick-start guide and checklist
- `zdm_migrate.rsp` - ZDM response file
- `zdm_commands.sh` - CLI commands script
- `ZDM-Migration-Runbook.md` - Step-by-step runbook

**Usage**:
1. Ensure all issues from Step 5 are resolved
2. Provide completed questionnaire from `Step4/`
3. Artifacts are saved to `Step6/`
4. Review generated artifacts
5. Follow the runbook to execute migration

---

## End-to-End Workflow

The complete workflow alternates between your local VS Code environment and the ZDM server. This swimlane diagram shows where each action occurs:

```
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                              ZDM MIGRATION WORKFLOW                                          │
├────────────────────────────────────┬────────────────────────────────────────────────────────┤
│    💻 VS CODE (Local / Remote-SSH)  │              🖥️ ZDM SERVER                             │
├────────────────────────────────────┼────────────────────────────────────────────────────────┤
│                                    │                                                        │
│  ┌──────────────────────────────┐  │                                                        │
│  │ 1. Fork & Clone Repo         │  │                                                        │
│  └──────────────┬───────────────┘  │                                                        │
│                 ▼                  │                                                        │
│  ┌──────────────────────────────┐  │                                                        │
│  │ 2. Connect via Remote-SSH    │  │                                                        │
│  │    Run Step1 Prompt          │  │                                                        │
│  │    → Test SSH connectivity   │  │                                                        │
│  │      (runs on jumpbox)       │  │                                                        │
│  └──────────────┬───────────────┘  │                                                        │
│                 ▼                  │                                                        │
│  ┌──────────────────────────────┐  │                                                        │
│  │ 3. Run Step2 Prompt          │  │                                                        │
│  │    → Generate discovery      │  │                                                        │
│  │      scripts                 │  │                                                        │
│  └──────────────┬───────────────┘  │                                                        │
│                 ▼                  │                                                        │
│  ┌──────────────────────────────┐  │                                                        │
│  │ 4. git commit & push         │──┼───────────────────┐                                    │
│  └──────────────────────────────┘  │                   ▼                                    │
│                                    │  ┌────────────────────────────────────────────────┐    │
│                                    │  │ 5. SSH as admin user (azureuser/opc)           │    │
│                                    │  │    sudo su - zdmuser                           │    │
│                                    │  └──────────────────────┬─────────────────────────┘    │
│                                    │                         ▼                              │
│                                    │  ┌────────────────────────────────────────────────┐    │
│                                    │  │ 6. git clone <fork-url>                        │    │
│                                    │  └──────────────────────┬─────────────────────────┘    │
│                                    │                         ▼                              │
│                                    │  ┌────────────────────────────────────────────────┐    │
│                                    │  │ 7. Run discovery scripts                       │    │
│                                    │  │    (source, target, ZDM servers)               │    │
│                                    │  └──────────────────────┬─────────────────────────┘    │
│                                    │                         ▼                              │
│                   ┌────────────────┼──│ 8. git commit & push artifacts                 │    │
│                   ▼                │  └────────────────────────────────────────────────┘    │
│  ┌──────────────────────────────┐  │                                                        │
│  │ 9. git pull                  │  │                                                        │
│  └──────────────┬───────────────┘  │                                                        │
│                 ▼                  │                                                        │
│  ┌──────────────────────────────┐  │                                                        │
│  │ 10. Run Step3 Prompt         │  │                                                        │
│  │     → Analyze discovery      │  │                                                        │
│  │     → Generate questionnaire │  │                                                        │
│  └──────────────┬───────────────┘  │                                                        │
│                 ▼                  │                                                        │
│  ┌──────────────────────────────┐  │                                                        │
│  │ 11. Complete questionnaire   │  │                                                        │
│  │     (manual decisions)       │  │                                                        │
│  └──────────────┬───────────────┘  │                                                        │
│                 ▼                  │                                                        │
│  ┌──────────────────────────────┐  │                                                        │
│  │ 12. Run Step4 Prompt         │  │                                                        │
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
│  │ 13. Run Step5 Prompt         │  │                                                        │
│  │     → Generate RSP, CLI,     │  │                                                        │
│  │       Runbook                │  │                                                        │
│  └──────────────┬───────────────┘  │                                                        │
│                 ▼                  │                                                        │
│  ┌──────────────────────────────┐  │                                                        │
│  │ 14. git commit & push        │──┼───────────────────┐                                    │
│  └──────────────────────────────┘  │                   ▼                                    │
│                                    │  ┌────────────────────────────────────────────────┐    │
│                                    │  │ 15. git pull                                   │    │
│                                    │  └──────────────────────┬─────────────────────────┘    │
│                                    │                         ▼                              │
│                                    │  ┌────────────────────────────────────────────────┐    │
│                                    │  │ 16. ./zdm_commands.sh init                     │    │
│                                    │  │     → Creates ~/creds, ~/zdm_oci_env.sh        │    │
│                                    │  └──────────────────────┬─────────────────────────┘    │
│                                    │                         ▼                              │
│                                    │  ┌────────────────────────────────────────────────┐    │
│                                    │  │ 17. Edit ~/zdm_oci_env.sh with OCIDs           │    │
│                                    │  │     source ~/zdm_oci_env.sh                    │    │
│                                    │  └──────────────────────┬─────────────────────────┘    │
│                                    │                         ▼                              │
│                                    │  ┌────────────────────────────────────────────────┐    │
│                                    │  │ 18. Set passwords & create-creds               │    │
│                                    │  └──────────────────────┬─────────────────────────┘    │
│                                    │                         ▼                              │
│                                    │  ┌────────────────────────────────────────────────┐    │
│                                    │  │ 19. Follow Runbook                             │    │
│                                    │  │     → eval → migrate → resume → cleanup        │    │
│                                    │  └────────────────────────────────────────────────┘    │
│                                    │                                                        │
└────────────────────────────────────┴────────────────────────────────────────────────────────┘
```

### Quick Reference: Where Does Each Step Run?

| Phase | Location | Actions |
|-------|----------|---------|
| **Step 1: Remote-SSH Setup** | VS Code (Local) | Check extension, configure ssh-config, test key connectivity |
| **Step 2: SSH Connectivity** | VS Code via Remote-SSH (on jumpbox) | Collect SSH vars interactively, test connectivity, write ssh-config.md |
| **Step 3: Discovery** | VS Code via Remote-SSH (on jumpbox) | Collect DB vars, run discovery inline, write db-config.md |
| **Analysis** | VS Code via Remote-SSH | Run Step 4 prompt, complete questionnaire |
| **Iteration** | VS Code via Remote-SSH | Fix issues with Step 5, re-run discovery, iterate until clean |
| **Generation** | VS Code via Remote-SSH | Run Step 6 prompt, write migration artifacts |
| **Migration** | ZDM Server | Follow runbook, execute migration |

### VS Code Remote-SSH Setup (Step 1)

Step 1 runs locally in VS Code **before** connecting to the jumpbox:
1. Install the [Remote - SSH](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh) extension in VS Code
2. Run the Step 1 prompt in the local VS Code terminal — it will check the extension, configure `~/.ssh/config`, and test connectivity
3. Follow the prompt instructions to connect: **Remote-SSH: Connect to Host...** → select the jumpbox alias
4. Once connected as `zdmuser`, proceed to Step 2 in the Remote-SSH session

### Important: ZDM Server Login (Steps 2–6)

For Steps 2–6, VS Code must be connected to the ZDM jumpbox via Remote-SSH as `zdmuser`. All Copilot commands run directly in the jumpbox terminal — no manual script transfer is required.

---

## Artifacts Directory Structure

Each migration creates its artifacts directly under `Artifacts/Phase10-Migration/`:

```
Artifacts/Phase10-Migration/
├── Step1/                              # Step 1: Test SSH Connectivity (all git-ignored)
│   ├── Scripts/                        # Only created if direct terminal commands are insufficient
│   │   └── zdm_test_ssh_connectivity.sh
│   └── Validation/                     # Written by Copilot during Step 1 prompt execution
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
│   └── Migration-Decisions.md
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
- OCI authentication files configured with API key authentication for zdmuser
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
- [OCI API Signing Key and Config Documentation](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm)
