# ZDM Discovery Scripts

## Project: PRODDB Migration to Oracle Database@Azure

This directory contains the discovery scripts generated for the PRODDB migration project.

## Scripts

| Script | Description | Target Server |
|--------|-------------|---------------|
| `zdm_source_discovery.sh` | Discovers source database configuration | proddb01.corp.example.com |
| `zdm_target_discovery.sh` | Discovers target Oracle Database@Azure | proddb-oda.eastus.azure.example.com |
| `zdm_server_discovery.sh` | Discovers ZDM jumpbox configuration | zdm-jumpbox.corp.example.com |
| `zdm_orchestrate_discovery.sh` | Orchestrates discovery across all servers | Local machine |

## Configuration

### Server Hostnames
- **Source Database:** proddb01.corp.example.com
- **Target Database:** proddb-oda.eastus.azure.example.com
- **ZDM Server:** zdm-jumpbox.corp.example.com

### User Configuration
| Server | SSH Admin User | Purpose |
|--------|---------------|---------|
| Source | oracle | On-premise server uses oracle user for SSH |
| Target | opc | OCI/ODA uses opc user for SSH |
| ZDM | azureuser | Azure VM uses azureuser for SSH |

### Application Users
- **Oracle User:** oracle (database software owner)
- **ZDM User:** zdmuser (ZDM software owner)

### SSH Keys
- **Source SSH Key:** ~/.ssh/onprem_oracle_key
- **Target SSH Key:** ~/.ssh/oci_opc_key
- **ZDM SSH Key:** ~/.ssh/azure_key

## Usage

### Option 1: Run Orchestration Script (Recommended)

The orchestration script handles everything automatically:

```bash
# Make scripts executable
chmod +x *.sh

# Show configuration
./zdm_orchestrate_discovery.sh -c

# Test SSH connectivity first
./zdm_orchestrate_discovery.sh -t

# Run full discovery
./zdm_orchestrate_discovery.sh
```

### Option 2: Run Individual Scripts Manually

If you prefer to run scripts manually on each server:

#### Source Database
```bash
# Copy to source server
scp -i ~/.ssh/onprem_oracle_key zdm_source_discovery.sh oracle@proddb01.corp.example.com:/tmp/

# SSH and run
ssh -i ~/.ssh/onprem_oracle_key oracle@proddb01.corp.example.com
cd /tmp
chmod +x zdm_source_discovery.sh
./zdm_source_discovery.sh
```

#### Target Database
```bash
# Copy to target server
scp -i ~/.ssh/oci_opc_key zdm_target_discovery.sh opc@proddb-oda.eastus.azure.example.com:/tmp/

# SSH and run
ssh -i ~/.ssh/oci_opc_key opc@proddb-oda.eastus.azure.example.com
cd /tmp
chmod +x zdm_target_discovery.sh
./zdm_target_discovery.sh
```

#### ZDM Server
```bash
# Copy to ZDM server
scp -i ~/.ssh/azure_key zdm_server_discovery.sh azureuser@zdm-jumpbox.corp.example.com:/tmp/

# SSH and run
ssh -i ~/.ssh/azure_key azureuser@zdm-jumpbox.corp.example.com
cd /tmp
chmod +x zdm_server_discovery.sh
./zdm_server_discovery.sh
```

## Output Files

Each discovery script generates:
- **Text Report:** `zdm_<type>_discovery_<hostname>_<timestamp>.txt`
- **JSON Summary:** `zdm_<type>_discovery_<hostname>_<timestamp>.json`

The orchestration script collects these to:
```
../Discovery/
├── source/
│   ├── zdm_source_discovery_*.txt
│   └── zdm_source_discovery_*.json
├── target/
│   ├── zdm_target_discovery_*.txt
│   └── zdm_target_discovery_*.json
└── server/
    ├── zdm_server_discovery_*.txt
    └── zdm_server_discovery_*.json
```

## Additional Discovery Items

### Source Database (per project requirements)
- Tablespace autoextend settings
- Current backup schedule and retention
- Database links configured
- Materialized view refresh schedules
- Scheduler jobs that may need reconfiguration

### Target Database (Oracle Database@Azure)
- Available Exadata storage capacity
- Pre-configured PDBs
- Network security group rules

### ZDM Server
- Available disk space for ZDM operations (minimum 50GB)
- Network latency to source and target (ping tests)

## Environment Variables

Set these environment variables to override default configuration:

```bash
# Server hostnames
export SOURCE_HOST="proddb01.corp.example.com"
export TARGET_HOST="proddb-oda.eastus.azure.example.com"
export ZDM_HOST="zdm-jumpbox.corp.example.com"

# SSH users (admin user for each server)
export SOURCE_ADMIN_USER="oracle"
export TARGET_ADMIN_USER="opc"
export ZDM_ADMIN_USER="azureuser"

# SSH key paths
export SOURCE_SSH_KEY="$HOME/.ssh/onprem_oracle_key"
export TARGET_SSH_KEY="$HOME/.ssh/oci_opc_key"
export ZDM_SSH_KEY="$HOME/.ssh/azure_key"

# Application users
export ORACLE_USER=oracle
export ZDM_USER=zdmuser
```

### Path Overrides (if auto-detection fails)

```bash
# Source Oracle paths
export SOURCE_REMOTE_ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1
export SOURCE_REMOTE_ORACLE_SID=PRODDB

# Target Oracle paths
export TARGET_REMOTE_ORACLE_HOME=/u02/app/oracle/product/19.0.0.0/dbhome_1
export TARGET_REMOTE_ORACLE_SID=

# ZDM paths
export ZDM_REMOTE_ZDM_HOME=/home/zdmuser/zdmhome
export ZDM_REMOTE_JAVA_HOME=/usr/java/latest
```

## Troubleshooting

### SSH Connection Failed
1. Verify the SSH key exists and has correct permissions (600)
2. Verify the hostname is resolvable
3. Verify firewall rules allow SSH (port 22)
4. Try manual SSH: `ssh -i <key> -v <user>@<host>`

### Oracle Environment Not Detected
1. Check if /etc/oratab exists and has entries
2. Check if pmon process is running
3. Set explicit overrides via environment variables

### ZDM Not Found
1. Verify ZDM is installed
2. Check common paths: ~/zdmhome, /opt/zdm
3. Set ZDM_REMOTE_ZDM_HOME explicitly

### Permission Denied
1. Verify the admin user has sudo privileges
2. Check that the oracle/zdmuser exists
3. Verify sudoers configuration allows password-less sudo

## Next Steps

After completing discovery:
1. Review the generated reports in `../Discovery/`
2. Proceed to **Step 1: Discovery Questionnaire**
3. Use discovery data to complete the questionnaire

---
Generated: $(date)
