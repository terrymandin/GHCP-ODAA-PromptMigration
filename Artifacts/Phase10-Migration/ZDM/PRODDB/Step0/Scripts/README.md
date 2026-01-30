# ZDM Discovery Scripts - PRODDB Migration

## Project Details

| Property | Value |
|----------|-------|
| **Project Name** | PRODDB Migration to Oracle Database@Azure |
| **Source Database** | proddb01.corp.example.com |
| **Target Database** | proddb-oda.eastus.azure.example.com |
| **ZDM Server** | zdm-jumpbox.corp.example.com |

## User Configuration

| Server | Admin User | SSH Key |
|--------|------------|---------|
| Source | oracle | ~/.ssh/onprem_oracle_key |
| Target | opc | ~/.ssh/oci_opc_key |
| ZDM | azureuser | ~/.ssh/azure_key |

| Role | User |
|------|------|
| Oracle DB Software Owner | oracle |
| ZDM Software Owner | zdmuser |

## Scripts Overview

| Script | Purpose | Runs On |
|--------|---------|---------|
| `zdm_source_discovery.sh` | Discovers source database configuration | Source DB Server |
| `zdm_target_discovery.sh` | Discovers target Oracle Database@Azure configuration | Target DB Server |
| `zdm_server_discovery.sh` | Discovers ZDM jumpbox configuration | ZDM Server |
| `zdm_orchestrate_discovery.sh` | Orchestrates all discoveries via SSH | Any machine with SSH access |

## Quick Start

### Option 1: Run Orchestration Script (Recommended)

Run the orchestration script from any machine with SSH access to all three servers:

```bash
# Make scripts executable
chmod +x *.sh

# Test SSH connectivity first
./zdm_orchestrate_discovery.sh --test

# Run full discovery
./zdm_orchestrate_discovery.sh
```

### Option 2: Run Scripts Individually

If you prefer to run scripts manually on each server:

**On Source Database Server (as oracle):**
```bash
scp zdm_source_discovery.sh oracle@proddb01.corp.example.com:~/
ssh oracle@proddb01.corp.example.com 'chmod +x ~/zdm_source_discovery.sh && ~/zdm_source_discovery.sh'
```

**On Target Database Server (as opc):**
```bash
scp zdm_target_discovery.sh opc@proddb-oda.eastus.azure.example.com:~/
ssh opc@proddb-oda.eastus.azure.example.com 'chmod +x ~/zdm_target_discovery.sh && ~/zdm_target_discovery.sh'
```

**On ZDM Server (as azureuser):**
```bash
scp zdm_server_discovery.sh azureuser@zdm-jumpbox.corp.example.com:~/
ssh azureuser@zdm-jumpbox.corp.example.com 'chmod +x ~/zdm_server_discovery.sh && SOURCE_HOST=proddb01.corp.example.com TARGET_HOST=proddb-oda.eastus.azure.example.com ~/zdm_server_discovery.sh'
```

## Environment Variable Overrides

If auto-detection fails, set these environment variables before running:

```bash
# Server hostnames
export SOURCE_HOST="proddb01.corp.example.com"
export TARGET_HOST="proddb-oda.eastus.azure.example.com"
export ZDM_HOST="zdm-jumpbox.corp.example.com"

# SSH users
export SOURCE_ADMIN_USER="oracle"
export TARGET_ADMIN_USER="opc"
export ZDM_ADMIN_USER="azureuser"

# SSH key paths
export SOURCE_SSH_KEY="$HOME/.ssh/onprem_oracle_key"
export TARGET_SSH_KEY="$HOME/.ssh/oci_opc_key"
export ZDM_SSH_KEY="$HOME/.ssh/azure_key"

# Application users
export ORACLE_USER=oracle
export ZDM_SOFTWARE_USER=zdmuser

# Oracle path overrides (only if auto-detection fails)
export SOURCE_REMOTE_ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1
export SOURCE_REMOTE_ORACLE_SID=PRODDB

# Run orchestration
./zdm_orchestrate_discovery.sh
```

## Discovery Output

After running the orchestration script, discovery results will be saved to:

```
../Discovery/
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

## Additional Discovery Items

These scripts include additional discovery beyond standard ZDM requirements:

### Source Database
- ✅ Tablespace autoextend settings
- ✅ Current backup schedule and retention (RMAN configuration)
- ✅ Database links configured
- ✅ Materialized view refresh schedules
- ✅ Scheduler jobs that may need reconfiguration

### Target Database (Oracle Database@Azure)
- ✅ Available Exadata storage capacity
- ✅ Pre-configured PDBs
- ✅ Network security group rules (via Azure IMDS or local firewall)

### ZDM Server
- ✅ Available disk space for ZDM operations (minimum 50GB check)
- ✅ Network latency to source and target (ping tests with latency measurement)
- ✅ Port connectivity tests (SSH port 22, Oracle port 1521)

## Next Steps

After discovery is complete:

1. Review the discovery output files in `../Discovery/`
2. Proceed to **Step 1: Discovery Questionnaire** to complete the full questionnaire
3. Use the discovery data to answer technical questions in the questionnaire

## Troubleshooting

### SSH Connection Failed
- Verify SSH keys are correctly configured
- Check that the admin user has SSH access to the server
- Ensure network connectivity and firewall rules allow SSH (port 22)

### Oracle Environment Not Detected
- Set `ORACLE_HOME_OVERRIDE` and `ORACLE_SID_OVERRIDE` environment variables
- Ensure `/etc/oratab` exists and is readable
- Check if Oracle pmon process is running

### ZDM Not Detected
- Set `ZDM_HOME_OVERRIDE` environment variable
- Verify ZDM is installed under the zdmuser account
- Check if zdmcli exists at `$ZDM_HOME/bin/zdmcli`

### OCI CLI Connectivity Failed
- Verify `~/.oci/config` exists and is correctly configured
- Check that the API key file exists at the path specified in the config
- Ensure network connectivity to OCI endpoints
