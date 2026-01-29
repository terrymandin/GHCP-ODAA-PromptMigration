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
- Text report: `/tmp/zdm_source_discovery_<hostname>_<timestamp>.txt`
- JSON summary: `/tmp/zdm_source_discovery_<hostname>_<timestamp>.json`

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
- Text report: `/tmp/zdm_target_discovery_<hostname>_<timestamp>.txt`
- JSON summary: `/tmp/zdm_target_discovery_<hostname>_<timestamp>.json`

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
- Text report: `/tmp/zdm_server_discovery_<hostname>_<timestamp>.txt`
- JSON summary: `/tmp/zdm_server_discovery_<hostname>_<timestamp>.json`

---

### 4. Master Orchestration Script (`zdm_orchestrate_discovery.sh`)

Generate a bash script that can be run from any machine with SSH access to orchestrate discovery across all servers:

**Configuration:**
- Environment variables for SOURCE_HOST, TARGET_HOST, ZDM_HOST
- Environment variables for users (SOURCE_USER, TARGET_USER, ZDM_USER)
- SSH key path

**Functions:**
- Configuration validation
- SSH connectivity testing
- Copy and execute discovery scripts remotely
- Collect results to local output directory

**Features:**
- Help message (-h, --help)
- Config display (-c, --config)
- Connectivity test only (-t, --test)
- Color-coded terminal output
- Error handling

---

## Script Requirements

All scripts should include:
- Shebang (`#!/bin/bash`)
- Error handling (`set -e` where appropriate)
- Color-coded terminal output
- Clear section headers in output
- Both human-readable text and machine-parseable JSON output
- Usage instructions
- Timestamps in filenames

---

### 5. Planning Questionnaire (`Planning-Questionnaire-<DB_NAME>.md`)

Generate a markdown questionnaire to capture **business and architectural decisions** that cannot be discovered by scripts. This questionnaire should be pre-populated with project details provided by the user.

**Pre-populate from user input:**
- Project Name
- Source/Target/ZDM hostnames
- Generated date

**Sections to include:**

#### Section A: Migration Strategy (Required)
- Migration Type: `ONLINE_PHYSICAL` or `OFFLINE_PHYSICAL`
- Decision justification
- Decision factors table (downtime tolerance, complexity, network requirements)

#### Section B: Migration Timeline (Required)
- Planned Migration Date
- Maintenance Window (Start/End)
- Maximum Acceptable Downtime
- Rollback Decision Point

#### Section C: OCI/Azure Identifiers (Required for Target)
- OCI Tenancy OCID
- OCI User OCID
- OCI Compartment OCID
- OCI Region
- Target DB System OCID
- Target Database OCID

#### Section D: Credentials (Required - Store Securely)
- Source SYS Password location/reference
- Target SYS Password location/reference
- TDE Wallet Password location/reference (if TDE enabled)

#### Section E: Network and Connectivity
- ExpressRoute/VPN configuration status
- Network path description
- Estimated bandwidth (Mbps)
- Firewall rules confirmed

#### Section F: Backup and Storage Configuration
- Object Storage Namespace
- Bucket Name and Region
- Backup Method: Object Storage / NFS / Local
- RMAN Parallel Channels (default: 4)
- Compression Level: LOW / MEDIUM / HIGH

#### Section G: Data Guard Configuration (Online Migration Only)
- Protection Mode: MAXIMUM_PERFORMANCE / MAXIMUM_AVAILABILITY
- Transport Type: ASYNC / SYNC

#### Section H: Migration Execution Options
- Auto Switchover after migration: YES / NO
- Delete backup after successful migration: YES / NO
- Include performance statistics: YES / NO
- Pause Point: None / ZDM_CONFIGURE_DG_SRC / ZDM_SWITCHOVER_SRC

#### Section I: Rollback and Risk
- Rollback plan description
- Maximum time before rollback decision
- Known risks or constraints
- Special considerations

#### Section J: Approvals
- Completed By / Date
- Technical Review By / Date
- Business Approval By / Date

---

## Output Location

Save all Step 0 outputs to: `Artifacts/Phase10-Migration/ZDM/<DB_NAME>/Step0/`

The directory structure for each migration should be:
```
Artifacts/Phase10-Migration/ZDM/<DB_NAME>/
├── Step0/                                    # Step 0: Discovery Scripts & Planning
│   ├── Scripts/                              # Discovery scripts
│   │   ├── zdm_source_discovery.sh
│   │   ├── zdm_target_discovery.sh
│   │   ├── zdm_server_discovery.sh
│   │   ├── zdm_orchestrate_discovery.sh
│   │   └── README.md
│   ├── Planning-Questionnaire-<DB_NAME>.md   # Business decisions questionnaire
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

After generating scripts and questionnaire:
1. **Complete the Planning Questionnaire** (`Step0/Planning-Questionnaire-<DB_NAME>.md`)
2. Copy discovery scripts to respective servers
3. Execute scripts to gather discovery information
4. Collect output files to `Step0/Discovery/`
5. Proceed to Step 1: Discovery Questionnaire (combine planning + discovery)
