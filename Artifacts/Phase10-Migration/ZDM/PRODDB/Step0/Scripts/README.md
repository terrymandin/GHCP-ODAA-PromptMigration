# ZDM Discovery Scripts - PRODDB Migration

## Overview

This directory contains discovery scripts for the **PRODDB Migration to Oracle Database@Azure** project. These scripts gather information from the source database, target Oracle Database@Azure, and ZDM jumpbox server to support migration planning.

## Scripts

| Script | Purpose | Target Server |
|--------|---------|---------------|
| `zdm_orchestrate_discovery.sh` | Master orchestration script - coordinates all discovery | Run locally |
| `zdm_source_discovery.sh` | Discovers source database configuration | Source DB Server |
| `zdm_target_discovery.sh` | Discovers target Oracle Database@Azure configuration | Target DB Server |
| `zdm_server_discovery.sh` | Discovers ZDM jumpbox configuration | ZDM Server |

## Server Configuration

| Server | Hostname | Admin User | SSH Key |
|--------|----------|------------|---------|
| Source | `proddb01.corp.example.com` | `oracle` | `~/.ssh/onprem_oracle_key` |
| Target | `proddb-oda.eastus.azure.example.com` | `opc` | `~/.ssh/oci_opc_key` |
| ZDM | `zdm-jumpbox.corp.example.com` | `azureuser` | `~/.ssh/azure_key` |

## Quick Start

### 1. Test Connectivity
```bash
./zdm_orchestrate_discovery.sh -t
```

### 2. Show Configuration
```bash
./zdm_orchestrate_discovery.sh -c
```

### 3. Run Full Discovery
```bash
./zdm_orchestrate_discovery.sh
```

### 4. Run Discovery on Specific Server
```bash
# Source only
./zdm_orchestrate_discovery.sh -s

# Target only
./zdm_orchestrate_discovery.sh -d

# ZDM server only
./zdm_orchestrate_discovery.sh -z
```

## Environment Variables

Override default configuration using environment variables:

```bash
# Server hostnames
export SOURCE_HOST="your-source-host.example.com"
export TARGET_HOST="your-target-host.example.com"
export ZDM_HOST="your-zdm-host.example.com"

# SSH admin users
export SOURCE_ADMIN_USER="oracle"
export TARGET_ADMIN_USER="opc"
export ZDM_ADMIN_USER="azureuser"

# Application users
export ORACLE_USER="oracle"
export ZDM_USER="zdmuser"

# SSH keys
export SOURCE_SSH_KEY="$HOME/.ssh/onprem_oracle_key"
export TARGET_SSH_KEY="$HOME/.ssh/oci_opc_key"
export ZDM_SSH_KEY="$HOME/.ssh/azure_key"

# Output directory (optional)
export OUTPUT_DIR="/custom/output/path"
```

## Output

Discovery results are saved to:
```
Artifacts/Phase10-Migration/ZDM/PRODDB/Step0/Discovery/
├── source/
│   ├── zdm_source_discovery_<hostname>_<timestamp>.txt
│   └── zdm_source_discovery_<hostname>_<timestamp>.json
├── target/
│   ├── zdm_target_discovery_<hostname>_<timestamp>.txt
│   └── zdm_target_discovery_<hostname>_<timestamp>.json
└── server/
    ├── zdm_server_discovery_<hostname>_<timestamp>.txt
    └── zdm_server_discovery_<hostname>_<timestamp>.json
```

## Discovery Information Gathered

### Source Database
- OS and disk information
- Oracle environment (ORACLE_HOME, ORACLE_SID, version)
- Database configuration (name, DBID, role, open mode)
- CDB/PDB configuration
- TDE wallet status and encrypted tablespaces
- Supplemental logging status
- Redo log and archive log configuration
- Network configuration (listener, tnsnames.ora, sqlnet.ora)
- Data Guard parameters
- Schema sizes and invalid objects
- **Tablespace autoextend settings**
- **Backup schedule and retention**
- **Database links**
- **Materialized view refresh schedules**
- **Scheduler jobs**

### Target Database (Oracle Database@Azure)
- OS information
- Oracle environment and version
- Database configuration
- CDB/PDB configuration
- Storage (tablespaces, ASM disk groups)
- TDE configuration
- Network configuration
- OCI/Azure integration status
- Grid Infrastructure (RAC) status
- **Exadata storage capacity**
- **Pre-configured PDBs**
- **Network security group rules**

### ZDM Server
- OS information
- ZDM installation (ZDM_HOME, version, service status)
- Active migration jobs
- Java configuration
- OCI CLI configuration and connectivity
- SSH keys
- Credential files
- Network configuration
- ZDM logs
- **Disk space availability (50GB minimum check)**
- **Network latency to source and target**

## Prerequisites

1. **SSH keys** must be configured and accessible
2. **Network connectivity** from orchestration host to all servers
3. **Sudo privileges** for:
   - Running SQL commands as `oracle` user
   - Running ZDM CLI commands as `zdmuser`

## Troubleshooting

### SSH Connection Failed
- Verify SSH key exists and has correct permissions (`chmod 600`)
- Test manual SSH: `ssh -i <key> <user>@<host>`
- Check firewall rules allow SSH (port 22)

### Oracle Environment Not Detected
- Script auto-detects from `/etc/oratab` and running processes
- Override with environment variables if needed:
  ```bash
  export SOURCE_REMOTE_ORACLE_HOME="/u01/app/oracle/product/19.0.0/dbhome_1"
  export SOURCE_REMOTE_ORACLE_SID="PRODDB"
  ```

### ZDM Not Found
- Verify ZDM is installed and `zdmcli` exists
- Override with:
  ```bash
  export ZDM_REMOTE_ZDM_HOME="/home/zdmuser/zdmhome"
  ```

## Next Steps

After running discovery:
1. Review the generated reports in `Step0/Discovery/`
2. Proceed to **Step 1: Discovery Questionnaire** (`Step1-Discovery-Questionnaire.prompt.md`)
3. Complete the questionnaire with discovery data and business decisions

## Generated

- **Date**: January 30, 2026
- **Project**: PRODDB Migration to Oracle Database@Azure
