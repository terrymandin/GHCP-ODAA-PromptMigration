# ZDM Discovery Scripts - PRODDB Migration

## Project Details

| Property | Value |
|----------|-------|
| Project Name | PRODDB Migration to Oracle Database@Azure |
| Source Database | proddb01.corp.example.com |
| Target Database | proddb-oda.eastus.azure.example.com |
| ZDM Server | zdm-jumpbox.corp.example.com |

## User Configuration

| Server | Admin User | SSH Key |
|--------|------------|---------|
| Source | oracle | ~/.ssh/onprem_oracle_key |
| Target | opc | ~/.ssh/oci_opc_key |
| ZDM | azureuser | ~/.ssh/azure_key |

| Role | User |
|------|------|
| Oracle Software Owner | oracle |
| ZDM Software Owner | zdmuser |

## Scripts

| Script | Purpose |
|--------|---------|
| `zdm_source_discovery.sh` | Discover source database configuration, TDE, logging, schemas, etc. |
| `zdm_target_discovery.sh` | Discover target Oracle Database@Azure configuration |
| `zdm_server_discovery.sh` | Discover ZDM jumpbox configuration, OCI CLI, connectivity |
| `zdm_orchestrate_discovery.sh` | Master script to run all discoveries remotely |

## Quick Start

### Option 1: Run Orchestrated Discovery (Recommended)

From your local machine with SSH access to all servers:

```bash
# Navigate to scripts directory
cd Artifacts/Phase10-Migration/ZDM/PRODDB/Step0/Scripts

# Make scripts executable
chmod +x *.sh

# Test connectivity first
./zdm_orchestrate_discovery.sh -t

# Run full discovery
./zdm_orchestrate_discovery.sh
```

### Option 2: Run Individual Scripts Manually

Copy and run each script on its respective server:

```bash
# On source server (as oracle user)
scp -i ~/.ssh/onprem_oracle_key zdm_source_discovery.sh oracle@proddb01.corp.example.com:/tmp/
ssh -i ~/.ssh/onprem_oracle_key oracle@proddb01.corp.example.com
cd /tmp && chmod +x zdm_source_discovery.sh && ./zdm_source_discovery.sh

# On target server (as opc user)
scp -i ~/.ssh/oci_opc_key zdm_target_discovery.sh opc@proddb-oda.eastus.azure.example.com:/tmp/
ssh -i ~/.ssh/oci_opc_key opc@proddb-oda.eastus.azure.example.com
cd /tmp && chmod +x zdm_target_discovery.sh && ./zdm_target_discovery.sh

# On ZDM server (as azureuser)
scp -i ~/.ssh/azure_key zdm_server_discovery.sh azureuser@zdm-jumpbox.corp.example.com:/tmp/
ssh -i ~/.ssh/azure_key azureuser@zdm-jumpbox.corp.example.com
cd /tmp && chmod +x zdm_server_discovery.sh && ./zdm_server_discovery.sh
```

## Orchestration Script Options

```bash
# Show help
./zdm_orchestrate_discovery.sh -h

# Show current configuration
./zdm_orchestrate_discovery.sh -c

# Test SSH connectivity only
./zdm_orchestrate_discovery.sh -t

# Run discovery on specific server only
./zdm_orchestrate_discovery.sh -s    # Source only
./zdm_orchestrate_discovery.sh -g    # Target only
./zdm_orchestrate_discovery.sh -z    # ZDM only
```

## Environment Variables

You can override defaults by setting environment variables:

```bash
# Override server hostnames
export SOURCE_HOST="custom-source.example.com"
export TARGET_HOST="custom-target.example.com"
export ZDM_HOST="custom-zdm.example.com"

# Override SSH users
export SOURCE_ADMIN_USER="custom_user"
export TARGET_ADMIN_USER="custom_user"
export ZDM_ADMIN_USER="custom_user"

# Override SSH keys
export SOURCE_SSH_KEY="~/.ssh/custom_key"
export TARGET_SSH_KEY="~/.ssh/custom_key"
export ZDM_SSH_KEY="~/.ssh/custom_key"

# Override output directory
export OUTPUT_DIR="/custom/path/to/output"

# Override Oracle/ZDM paths if auto-detection fails
export SOURCE_REMOTE_ORACLE_HOME="/u01/app/oracle/product/19.0.0/dbhome_1"
export SOURCE_REMOTE_ORACLE_SID="PRODDB"
export TARGET_REMOTE_ORACLE_HOME="/u02/app/oracle/product/19.0.0/dbhome_1"
export ZDM_REMOTE_ZDM_HOME="/home/zdmuser/zdmhome"

./zdm_orchestrate_discovery.sh
```

## Output

Discovery results are collected to: `../Discovery/`

```
Discovery/
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

## Additional Discovery Items (PRODDB Project)

### Source Database
- Tablespace autoextend settings
- Backup schedule and retention (RMAN)
- Database links
- Materialized view refresh schedules
- Scheduler jobs (DBMS_SCHEDULER and DBMS_JOB)

### Target Database
- Exadata storage capacity
- Pre-configured PDBs
- Network security group rules

### ZDM Server
- Disk space (minimum 50GB recommended)
- Network latency to source and target (ping tests)
- Port connectivity tests (SSH and Oracle listener)

## Troubleshooting

### SSH Connection Fails
1. Verify the SSH key file exists and has correct permissions (`chmod 600`)
2. Verify the username is correct for each server
3. Test manual SSH connection: `ssh -i <key> <user>@<host>`

### Oracle Environment Not Detected
1. Check that `/etc/oratab` exists and contains the database entry
2. Verify Oracle processes are running: `ps -ef | grep pmon`
3. Set explicit overrides: `SOURCE_REMOTE_ORACLE_HOME` and `SOURCE_REMOTE_ORACLE_SID`

### ZDM Not Detected
1. Verify ZDM is installed in a common location
2. Set explicit override: `ZDM_REMOTE_ZDM_HOME`

### Partial Results
- The scripts are designed to continue on failure
- Check the output files for sections that completed vs failed
- Re-run individual server discovery with `-s`, `-g`, or `-z` flags

## Next Steps

After discovery is complete:
1. Review the discovery reports for any issues
2. Proceed to **Step 1: Discovery Questionnaire** to complete the migration questionnaire
3. Use the questionnaire output for **Step 2: Generate Migration Artifacts**
