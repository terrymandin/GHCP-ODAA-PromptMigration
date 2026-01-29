# ZDM Migration Step 0: Generate Discovery Scripts

## Purpose
This prompt generates the discovery scripts that will be used to gather information from the source database server, target Oracle Database@Azure server, and ZDM jumpbox server.

---

## Instructions

Run this prompt to generate fresh discovery scripts. These scripts should be generated at the start of each migration project to ensure they contain the latest discovery logic.

---

## Generate Discovery Scripts

Please generate the following discovery scripts for a ZDM migration from on-premise Oracle to Oracle Database@Azure:

### 1. Source Database Discovery Script (`zdm_source_discovery.sh`)

Generate a bash script to run on the **source database server** (as oracle user) that discovers:

**OS Information:**
- Hostname, IP addresses
- Operating system version
- Disk space

**Oracle Environment:**
- ORACLE_HOME, ORACLE_SID, ORACLE_BASE
- Oracle version

**Database Configuration:**
- Database name, unique name, DBID
- Database role, open mode
- Log mode (ARCHIVELOG/NOARCHIVELOG)
- Force logging status
- Database size (data files, temp files)
- Character set and national character set

**Container Database:**
- CDB status
- PDB names and status (if CDB)

**TDE Configuration:**
- TDE enabled status
- Wallet type and location
- Encrypted tablespaces

**Supplemental Logging:**
- Supplemental log data min, PK, UI, FK, ALL

**Redo/Archive Configuration:**
- Redo log groups, sizes, members
- Archive log destinations

**Network Configuration:**
- Listener status and configuration
- tnsnames.ora contents
- sqlnet.ora contents

**Authentication:**
- Password file location
- SSH directory contents

**Data Guard:**
- Current DG configuration parameters

**Schema Information:**
- Schema sizes (non-system schemas > 100MB)
- Invalid objects count by owner/type

**Output Format:**
- Text report: `./zdm_source_discovery_<hostname>_<timestamp>.txt` (in current working directory)
- JSON summary: `./zdm_source_discovery_<hostname>_<timestamp>.json` (in current working directory)
- The orchestration script will collect these to the Artifacts directory

---

### 2. Target Database Discovery Script (`zdm_target_discovery.sh`)

Generate a bash script to run on the **target database server** (Oracle Database@Azure, as opc or oracle user) that discovers:

**OS Information:**
- Hostname, IP addresses
- Operating system version

**Oracle Environment:**
- ORACLE_HOME, ORACLE_SID, ORACLE_BASE
- Oracle version

**Database Configuration:**
- Database name, unique name
- Database role, open mode
- Available storage (tablespaces, ASM if applicable)
- Character set

**Container Database:**
- CDB status
- PDB names and status

**TDE Configuration:**
- TDE/wallet status

**Network Configuration:**
- Listener status
- SCAN listener (if RAC)
- tnsnames.ora contents

**OCI/Azure Integration:**
- OCI CLI version and configuration
- OCI connectivity test
- Instance metadata (OCI and Azure)

**Grid Infrastructure (if RAC):**
- CRS status

**Authentication:**
- SSH directory contents

**Output Format:**
- Text report: `./zdm_target_discovery_<hostname>_<timestamp>.txt` (in current working directory)
- JSON summary: `./zdm_target_discovery_<hostname>_<timestamp>.json` (in current working directory)
- The orchestration script will collect these to the Artifacts directory

---

### 3. ZDM Server Discovery Script (`zdm_server_discovery.sh`)

Generate a bash script to run on the **ZDM jumpbox server** (as zdmuser) that discovers:

**OS Information:**
- Hostname, current user
- Operating system version

**ZDM Installation:**
- ZDM_HOME location
- ZDM version
- ZDM service status
- Active migration jobs

**Java Configuration:**
- Java version
- JAVA_HOME

**OCI CLI Configuration:**
- OCI CLI version
- OCI config file location and contents (masked sensitive data)
- Configured profiles and regions
- API key file existence
- OCI connectivity test

**SSH Configuration:**
- Available SSH keys (public and private)
- SSH directory contents

**Credential Files:**
- Search for password/credential files

**Network Configuration:**
- IP addresses
- Routing table
- DNS configuration

**ZDM Logs:**
- Log directory location
- Recent log files

**Output Format:**
- Text report: `./zdm_server_discovery_<hostname>_<timestamp>.txt` (in current working directory)
- JSON summary: `./zdm_server_discovery_<hostname>_<timestamp>.json` (in current working directory)
- The orchestration script will collect these to the Artifacts directory

---

### 4. Master Orchestration Script (`zdm_orchestrate_discovery.sh`)

Generate a bash script that can be run from any machine with SSH access to orchestrate discovery across all servers:

**Configuration:**
- Environment variables for SOURCE_HOST, TARGET_HOST, ZDM_HOST
- Environment variables for users (SOURCE_USER, TARGET_USER, ZDM_USER)
- Separate SSH key paths for each environment:
  - SOURCE_SSH_KEY: SSH key for source database server
  - TARGET_SSH_KEY: SSH key for target Oracle Database@Azure server
  - ZDM_SSH_KEY: SSH key for ZDM jumpbox server
  (Note: These are typically different keys due to separate security domains)

**Functions:**
- Configuration validation
- SSH connectivity testing
- Copy and execute discovery scripts remotely
- Collect results to local Artifacts directory

**Output Directory:**
- Default output should be the Artifacts directory: `Artifacts/Phase10-Migration/ZDM/<DB_NAME>/Step0/Discovery/`
- Configurable via command-line option or environment variable
- Create subdirectories for each server type (source/, target/, server/)

**Resilience Requirements:**
- **Continue on failure** - If one server discovery fails, continue with the remaining servers
- **Source environment on remote hosts** - Before running discovery scripts, source common shell profile files to load environment variables:
  - For interactive bash: `source ~/.bashrc` (must handle non-interactive sourcing)
  - For login shells: `source ~/.bash_profile` or `source ~/.profile`
  - For system-wide settings: `source /etc/profile`
- **Error tracking** - Track which servers succeeded/failed and report at the end
- **Partial success** - A discovery run with 2 out of 3 servers successful should still save and report the successful results

**Features:**
- Help message (-h, --help)
- Config display (-c, --config)
- Connectivity test only (-t, --test)
- Color-coded terminal output
- Resilient error handling (continue despite individual failures)

---

## Script Requirements

All scripts should include:
- Shebang (`#!/bin/bash`)
- **Resilient error handling** - Do NOT use `set -e` globally; instead use individual error trapping so scripts continue running even when some checks fail
- **Environment variable sourcing** - Source common profile files (`~/.bashrc`, `~/.bash_profile`, `/etc/profile.d/*.sh`) to ensure environment variables like `ZDM_HOME`, `ORACLE_HOME`, `JAVA_HOME` are available
- Color-coded terminal output
- Clear section headers in output
- Both human-readable text and machine-parseable JSON output
- Usage instructions
- Timestamps in filenames
- **Continue on failure** - Each discovery section should be wrapped in error handling that logs failures but continues to the next section
- **Output to current directory** - Write output files to the current working directory (not /tmp) so the orchestration script can easily collect them

---

## Output Location

Save all Step 0 outputs to: `Artifacts/Phase10-Migration/ZDM/<DB_NAME>/Step0/`

The directory structure for each migration should be:
```
Artifacts/Phase10-Migration/ZDM/<DB_NAME>/
├── Step0/                                    # Step 0: Discovery Scripts
│   ├── Scripts/                              # Discovery scripts
│   │   ├── zdm_source_discovery.sh
│   │   ├── zdm_target_discovery.sh
│   │   ├── zdm_server_discovery.sh
│   │   ├── zdm_orchestrate_discovery.sh
│   │   └── README.md
│   ├── README.md                             # Step 0 instructions
│   └── Discovery/                            # Discovery output files (after execution)
│       ├── zdm_source_discovery_*.txt
│       ├── zdm_source_discovery_*.json
│       ├── zdm_target_discovery_*.txt
│       ├── zdm_target_discovery_*.json
│       ├── zdm_server_discovery_*.txt
│       └── zdm_server_discovery_*.json
├── Step1/                                    # Step 1: Completed Questionnaire
│   └── Completed-Questionnaire-<DB_NAME>.md
└── Step2/                                    # Step 2: Migration Artifacts
    ├── zdm_migrate_<DB_NAME>.rsp
    ├── zdm_commands_<DB_NAME>.sh
    └── ZDM-Migration-Runbook-<DB_NAME>.md
```

---

## Next Steps

After generating discovery scripts:
1. Copy discovery scripts to respective servers
2. Execute scripts to gather discovery information
3. Collect output files to `Step0/Discovery/`
4. Proceed to **Step 1: Discovery Questionnaire** to complete the full questionnaire with discovery data and business decisions
