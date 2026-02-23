# ZDM Discovery Scripts

## Overview

This directory contains the discovery scripts for the **PRODDB Migration to Oracle Database@Azure** project. These scripts gather technical context from the source database, target Oracle Database@Azure, and ZDM jumpbox server.

## Project Configuration

### Server Details
- **Source Database**: proddb01.corp.example.com
- **Target Database**: proddb-oda.eastus.azure.example.com (Oracle Database@Azure)
- **ZDM Server**: zdm-jumpbox.corp.example.com

### User Configuration
Different admin users are configured for each server environment:

| Server | Admin User | SSH Key | Description |
|--------|-----------|---------|-------------|
| Source | oracle | ~/.ssh/onprem_oracle_key | On-premise server admin |
| Target | opc | ~/.ssh/oci_opc_key | OCI/ODA default admin user |
| ZDM | azureuser | ~/.ssh/azure_key | Azure VM admin user |

### Application Users
- **ORACLE_USER**: oracle (database software owner)
- **ZDM_USER**: zdmuser (ZDM software owner)

## Scripts

### 1. zdm_source_discovery.sh
Discovers configuration and environment details from the source database server.

**Collects:**
- OS information and disk space
- Oracle environment and database configuration
- Database size and tablespace information
- TDE configuration
- Supplemental logging status
- Redo/archive configuration
- Network configuration (listener, tnsnames, sqlnet)
- Schema information and invalid objects
- **Tablespace autoextend settings** (custom requirement)
- **Backup schedule and retention** (custom requirement)
- **Database links** (custom requirement)
- **Materialized view refresh schedules** (custom requirement)
- **Scheduler jobs** (custom requirement)

### 2. zdm_target_discovery.sh
Discovers configuration and environment details from the target Oracle Database@Azure server.

**Collects:**
- OS information
- Oracle environment and database configuration
- Available storage (tablespaces, ASM)
- **Exadata storage capacity** (custom requirement)
- **Pre-configured PDBs** (custom requirement)
- TDE configuration
- Network configuration (listener, SCAN listener if RAC)
- **Network security group rules** (custom requirement)
- OCI/Azure integration (metadata, OCI CLI)
- Grid Infrastructure status (if RAC)

### 3. zdm_server_discovery.sh
Discovers configuration and environment details from the ZDM jumpbox server.

**Collects:**
- OS information
- **Disk space verification (minimum 50GB for ZDM operations)** (custom requirement)
- ZDM installation and version
- ZDM service status
- Active migration jobs
- Java configuration
- OCI CLI configuration
- SSH key configuration
- Network configuration
- **Network latency tests to source and target** (custom requirement)
- ZDM logs location

### 4. zdm_orchestrate_discovery.sh (Master Script)
Orchestrates the execution of all discovery scripts across all servers.

**Features:**
- Manages SSH connections to all servers with server-specific credentials
- Executes discovery scripts remotely using login shells
- Collects output files to centralized location
- Resilient error handling (continues on failure)
- Color-coded terminal output
- Connectivity testing
- Configuration display

## Quick Start

### Prerequisites

1. **SSH Access**: Ensure you have SSH access to all three servers
2. **SSH Keys**: Verify SSH keys are in place and have correct permissions:
   ```bash
   chmod 600 ~/.ssh/onprem_oracle_key
   chmod 600 ~/.ssh/oci_opc_key
   chmod 600 ~/.ssh/azure_key
   ```
3. **Sudo Privileges**: Admin users must have sudo privileges on their respective servers
4. **jq Installed**: The scripts use `jq` for JSON processing (required on remote servers)

### Running Discovery

**Option 1: Use the orchestration script (recommended)**
```bash
cd Artifacts/Phase10-Migration/ZDM/PRODDB/Step0/Scripts/

# Display configuration
./zdm_orchestrate_discovery.sh --config

# Test connectivity first
./zdm_orchestrate_discovery.sh --test

# Run full discovery
./zdm_orchestrate_discovery.sh
```

**Option 2: Run scripts manually**

If you prefer to run scripts individually or need to debug:

```bash
# On source database server (as oracle user)
ssh -i ~/.ssh/onprem_oracle_key oracle@proddb01.corp.example.com < zdm_source_discovery.sh

# On target database server (as opc user)
ssh -i ~/.ssh/oci_opc_key opc@proddb-oda.eastus.azure.example.com < zdm_target_discovery.sh

# On ZDM server (as azureuser)
ssh -i ~/.ssh/azure_key azureuser@zdm-jumpbox.corp.example.com < zdm_server_discovery.sh
```

## Output

Discovery outputs are collected to:
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

## Customization

### Overriding Configuration

You can override the default configuration using environment variables:

```bash
# Override server hostnames
export SOURCE_HOST="mydb.example.com"
export TARGET_HOST="mytarget.example.com"
export ZDM_HOST="myzdm.example.com"

# Override admin users
export SOURCE_ADMIN_USER="myuser"
export TARGET_ADMIN_USER="opc"
export ZDM_ADMIN_USER="azureuser"

# Override SSH keys
export SOURCE_SSH_KEY="~/.ssh/my_source_key"
export TARGET_SSH_KEY="~/.ssh/my_target_key"
export ZDM_SSH_KEY="~/.ssh/my_zdm_key"

# Override application users
export ORACLE_USER="oracle"
export ZDM_USER="zdmuser"

# Run with custom configuration
./zdm_orchestrate_discovery.sh
```

### Changing Output Directory

```bash
export ZDM_OUTPUT_DIR="/path/to/custom/output"
./zdm_orchestrate_discovery.sh
```

## Troubleshooting

### SSH Connection Issues

**Problem**: Cannot connect to server
```
✗ Failed to connect to Source Database
```

**Solutions**:
1. Verify SSH key permissions: `chmod 600 ~/.ssh/onprem_oracle_key`
2. Test manual SSH connection: `ssh -i ~/.ssh/onprem_oracle_key oracle@proddb01.corp.example.com`
3. Check if SSH key is correct for the server
4. Verify network connectivity: `ping proddb01.corp.example.com`

### Oracle Environment Not Detected

**Problem**: Script fails to detect ORACLE_HOME or ORACLE_SID

**Solutions**:
1. Check /etc/oratab file exists and has entries
2. Verify Oracle processes are running: `ps -ef | grep pmon`
3. Manually set environment variables before running script:
   ```bash
   export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1
   export ORACLE_SID=PRODDB
   ```

### ZDM_HOME Not Detected

**Problem**: Script fails to detect ZDM installation

**Solutions**:
1. Verify ZDM is installed: `sudo find /u01 /opt /home -name zdmcli`
2. Check zdmuser exists: `id zdmuser`
3. Manually set ZDM_HOME:
   ```bash
   export ZDM_HOME=/u01/app/zdmhome
   ```

### Permission Denied Errors

**Problem**: `sudo` commands fail or permission denied errors

**Solutions**:
1. Verify admin user has sudo privileges: `sudo -l`
2. Check sudoers configuration allows sudo without password (or provide password when prompted)
3. Ensure oracle/zdmuser users exist on the system

### Line Ending Issues

**Problem**: Script fails with syntax errors like `command not found` or unexpected tokens

**Cause**: Windows CRLF line endings instead of Unix LF

**Solution**: Convert line endings on the remote server:
```bash
# Using sed
sed -i 's/\r$//' zdm_source_discovery.sh

# Or using dos2unix
dos2unix zdm_source_discovery.sh
```

## Security Notes

⚠️ **Important Security Considerations**:

1. **SSH Keys**: Keep SSH private keys secure with proper permissions (600)
2. **Passwords**: Never commit passwords or credentials to Git
3. **Output Files**: Discovery outputs may contain sensitive information - handle appropriately
4. **sudoers**: Configure sudoers to limit sudo access to specific commands if possible

## Next Steps

After successful discovery:

1. **Review Discovery Outputs**: Examine the text and JSON files in the Discovery directory
2. **Verify Completeness**: Ensure all expected data was collected
3. **Proceed to Step 1**: Run the Discovery Questionnaire prompt to complete the full assessment

## Custom Discovery Requirements

This project includes additional discovery requirements beyond the standard ZDM discovery:

### Source Database
- ✅ Tablespace autoextend settings
- ✅ Backup schedule and retention policies
- ✅ Database links configuration
- ✅ Materialized view refresh schedules
- ✅ Scheduler jobs that may need reconfiguration

### Target Database (Oracle Database@Azure)
- ✅ Exadata storage capacity
- ✅ Pre-configured PDBs
- ✅ Network security group rules

### ZDM Server
- ✅ Disk space verification (minimum 50GB)
- ✅ Network latency tests to source and target

## Support

For issues or questions:
1. Review the troubleshooting section above
2. Check the ZDM documentation
3. Consult the project team

## Version Information

- **Project**: PRODDB Migration to Oracle Database@Azure
- **Migration Type**: Zero Downtime Migration (ZDM)
- **Generated**: $(date)
- **Step**: Step 0 - Discovery Scripts
