# ZDM Discovery Scripts - PRODDB Migration

## Project Information

| Field | Value |
|-------|-------|
| **Project Name** | PRODDB Migration to Oracle Database@Azure |
| **Source Database** | proddb01.corp.example.com |
| **Target Database** | proddb-oda.eastus.azure.example.com |
| **ZDM Server** | zdm-jumpbox.corp.example.com |
| **Generated** | 2026-01-29 |

---

## Scripts Overview

| Script | Purpose | Run As | Run On |
|--------|---------|--------|--------|
| `zdm_source_discovery.sh` | Discover source database configuration | `oracle` | Source DB Server |
| `zdm_target_discovery.sh` | Discover target Oracle Database@Azure | `opc` or `oracle` | Target DB Server |
| `zdm_server_discovery.sh` | Discover ZDM jumpbox configuration | `zdmuser` | ZDM Server |
| `zdm_orchestrate_discovery.sh` | Orchestrate all discoveries remotely | Any user with SSH access | Any machine |

---

## Quick Start

### Option 1: Use the Orchestration Script (Recommended)

The orchestration script can run all discoveries remotely from a single machine with SSH access:

```bash
# Edit the configuration section in the script first
vi zdm_orchestrate_discovery.sh

# Test connectivity
./zdm_orchestrate_discovery.sh --test

# Run full discovery on all servers
./zdm_orchestrate_discovery.sh

# Run discovery on specific server only
./zdm_orchestrate_discovery.sh --source   # Source DB only
./zdm_orchestrate_discovery.sh --target   # Target DB only
./zdm_orchestrate_discovery.sh --zdm      # ZDM server only
```

### Option 2: Run Scripts Individually

1. **Copy scripts to each server:**
   ```bash
   scp zdm_source_discovery.sh oracle@proddb01.corp.example.com:/tmp/
   scp zdm_target_discovery.sh opc@proddb-oda.eastus.azure.example.com:/tmp/
   scp zdm_server_discovery.sh zdmuser@zdm-jumpbox.corp.example.com:/tmp/
   ```

2. **Run on Source Database Server:**
   ```bash
   ssh oracle@proddb01.corp.example.com
   chmod +x /tmp/zdm_source_discovery.sh
   /tmp/zdm_source_discovery.sh
   ```

3. **Run on Target Database Server:**
   ```bash
   ssh opc@proddb-oda.eastus.azure.example.com
   chmod +x /tmp/zdm_target_discovery.sh
   /tmp/zdm_target_discovery.sh
   ```

4. **Run on ZDM Server:**
   ```bash
   ssh zdmuser@zdm-jumpbox.corp.example.com
   chmod +x /tmp/zdm_server_discovery.sh
   /tmp/zdm_server_discovery.sh
   ```

5. **Collect output files to the Discovery directory:**
   ```bash
   scp oracle@proddb01.corp.example.com:/tmp/zdm_source_discovery_*.txt ../Discovery/
   scp oracle@proddb01.corp.example.com:/tmp/zdm_source_discovery_*.json ../Discovery/
   scp opc@proddb-oda.eastus.azure.example.com:/tmp/zdm_target_discovery_*.txt ../Discovery/
   scp opc@proddb-oda.eastus.azure.example.com:/tmp/zdm_target_discovery_*.json ../Discovery/
   scp zdmuser@zdm-jumpbox.corp.example.com:/tmp/zdm_server_discovery_*.txt ../Discovery/
   scp zdmuser@zdm-jumpbox.corp.example.com:/tmp/zdm_server_discovery_*.json ../Discovery/
   ```

---

## Output Files

Each discovery script generates two output files:

| File Type | Format | Purpose |
|-----------|--------|---------|
| `zdm_*_discovery_<hostname>_<timestamp>.txt` | Human-readable text | Detailed discovery report for review |
| `zdm_*_discovery_<hostname>_<timestamp>.json` | JSON | Machine-parseable summary for automation |

Output files are created in `/tmp/` on each server and should be collected to the `Step0/Discovery/` directory.

---

## Discovery Details

### Source Database Discovery

Standard discovery items:
- OS information (hostname, IP, OS version, disk space)
- Oracle environment (ORACLE_HOME, ORACLE_SID, version)
- Database configuration (name, DBID, role, log mode, size)
- Container database status (CDB, PDBs)
- TDE configuration (wallet status, encrypted tablespaces)
- Supplemental logging status
- Redo and archive log configuration
- Network configuration (listener, tnsnames, sqlnet)
- Authentication (password file, SSH keys)
- Data Guard parameters
- Schema information (sizes, invalid objects)

**Additional custom discovery for PRODDB:**
- Tablespace autoextend settings
- Current backup schedule and retention (RMAN configuration)
- Database links configured
- Materialized view refresh schedules
- Scheduler jobs that may need reconfiguration

### Target Database Discovery (Oracle Database@Azure)

Standard discovery items:
- OS information (hostname, IP, OS version)
- Oracle environment (ORACLE_HOME, ORACLE_SID, version)
- Database configuration (name, role, character set)
- Storage configuration (tablespaces, ASM disk groups)
- Container database status (CDB, PDBs)
- TDE/wallet status
- Network configuration (listener, SCAN listener)
- OCI/Azure integration (CLI, metadata)
- Grid Infrastructure status (if RAC)
- SSH configuration

**Additional custom discovery for Oracle Database@Azure:**
- Available Exadata storage capacity
- Pre-configured PDBs
- Network security group rules (local firewall)

### ZDM Server Discovery

Standard discovery items:
- OS information (hostname, current user, OS version)
- ZDM installation (ZDM_HOME, version, service status)
- Active migration jobs
- Java configuration (version, JAVA_HOME)
- OCI CLI configuration (version, profiles, connectivity)
- SSH configuration (keys, config file)
- Credential files search
- Network configuration (IP, routing, DNS)
- ZDM logs

**Additional custom discovery for ZDM Server:**
- Available disk space check (minimum 50GB recommended)
- Network latency tests to source and target (ping)
- SSH port connectivity tests (port 22)
- Oracle listener port connectivity tests (port 1521)

---

## Prerequisites

### SSH Access Requirements

| From | To | User | Purpose |
|------|-----|------|---------|
| Orchestration host | Source DB | `oracle` | Run source discovery |
| Orchestration host | Target DB | `opc` or `oracle` | Run target discovery |
| Orchestration host | ZDM Server | `zdmuser` | Run ZDM discovery |

### Required Permissions

- **Source Database:** `oracle` user with SYSDBA access
- **Target Database:** `opc` or `oracle` user with SYSDBA access
- **ZDM Server:** `zdmuser` with access to ZDM_HOME

---

## Troubleshooting

### SSH Connection Failed
```bash
# Test SSH connection manually
ssh -v -i ~/.ssh/id_rsa oracle@proddb01.corp.example.com

# Check if SSH key exists
ls -la ~/.ssh/id_rsa
```

### Script Permissions Error
```bash
# Make script executable
chmod +x zdm_source_discovery.sh
```

### Oracle Environment Not Set
```bash
# Set Oracle environment before running
export ORACLE_HOME=/u01/app/oracle/product/19c/dbhome_1
export ORACLE_SID=PRODDB
export PATH=$ORACLE_HOME/bin:$PATH
```

### ZDM Environment Not Set
```bash
# Set ZDM environment before running
export ZDM_HOME=/u01/app/zdm/zdm21
export PATH=$ZDM_HOME/bin:$PATH
```

---

## Next Steps

After completing discovery:

1. **Review all discovery reports** in the `Step0/Discovery/` directory
2. **Identify any issues** such as:
   - Missing prerequisites (TDE not configured, supplemental logging not enabled)
   - Connectivity problems
   - Insufficient disk space
3. **Proceed to Step 1:** Complete the Discovery Questionnaire using the discovered information
4. **Use Step 1 output** to generate ZDM migration artifacts in Step 2

---

## Directory Structure

```
Artifacts/Phase10-Migration/ZDM/PRODDB/
├── Step0/                                    # Step 0: Discovery
│   ├── Scripts/                              # Discovery scripts (this directory)
│   │   ├── zdm_source_discovery.sh
│   │   ├── zdm_target_discovery.sh
│   │   ├── zdm_server_discovery.sh
│   │   ├── zdm_orchestrate_discovery.sh
│   │   └── README.md
│   ├── Discovery/                            # Discovery output files
│   │   ├── zdm_source_discovery_*.txt
│   │   ├── zdm_source_discovery_*.json
│   │   ├── zdm_target_discovery_*.txt
│   │   ├── zdm_target_discovery_*.json
│   │   ├── zdm_server_discovery_*.txt
│   │   └── zdm_server_discovery_*.json
│   └── README.md
├── Step1/                                    # Step 1: Completed Questionnaire
└── Step2/                                    # Step 2: Migration Artifacts
```
