# ZDM Discovery Scripts - PRODDB Migration

This directory contains the discovery scripts for the PRODDB Migration to Oracle Database@Azure project.

## Project Details

| Property | Value |
|----------|-------|
| Project Name | PRODDB Migration to Oracle Database@Azure |
| Source Database | proddb01.corp.example.com |
| Target Database | proddb-oda.eastus.azure.example.com |
| ZDM Server | zdm-jumpbox.corp.example.com |

## User Configuration

| Server | SSH Admin User | SSH Key |
|--------|----------------|---------|
| Source | oracle | ~/.ssh/onprem_oracle_key |
| Target | opc | ~/.ssh/oci_opc_key |
| ZDM Server | azureuser | ~/.ssh/azure_key |

| Role | User |
|------|------|
| Oracle Software Owner | oracle |
| ZDM Software Owner | zdmuser |

## Scripts

| Script | Description |
|--------|-------------|
| `zdm_source_discovery.sh` | Discovers source database configuration |
| `zdm_target_discovery.sh` | Discovers target Oracle Database@Azure configuration |
| `zdm_server_discovery.sh` | Discovers ZDM jumpbox server configuration |
| `zdm_orchestrate_discovery.sh` | Master script to run all discoveries remotely |

## Quick Start

### 1. Make Scripts Executable (if running on Linux/macOS)

```bash
chmod +x *.sh
```

### 2. Test Connectivity

```bash
./zdm_orchestrate_discovery.sh --test
```

### 3. Run Full Discovery

```bash
./zdm_orchestrate_discovery.sh
```

### 4. View Configuration

```bash
./zdm_orchestrate_discovery.sh --config
```

## Environment Variables

You can customize the discovery by setting environment variables before running:

```bash
# Override hostnames
export SOURCE_HOST="proddb01.corp.example.com"
export TARGET_HOST="proddb-oda.eastus.azure.example.com"
export ZDM_HOST="zdm-jumpbox.corp.example.com"

# Override SSH users
export SOURCE_ADMIN_USER="oracle"
export TARGET_ADMIN_USER="opc"
export ZDM_ADMIN_USER="azureuser"

# Override SSH keys
export SOURCE_SSH_KEY="$HOME/.ssh/onprem_oracle_key"
export TARGET_SSH_KEY="$HOME/.ssh/oci_opc_key"
export ZDM_SSH_KEY="$HOME/.ssh/azure_key"

# Run discovery
./zdm_orchestrate_discovery.sh
```

### Optional Path Overrides

If auto-detection fails, you can provide explicit paths:

```bash
# Oracle path overrides
export SOURCE_REMOTE_ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1
export SOURCE_REMOTE_ORACLE_SID=PRODDB
export TARGET_REMOTE_ORACLE_HOME=/u02/app/oracle/product/19.0.0.0/dbhome_1

# ZDM path overrides
export ZDM_REMOTE_ZDM_HOME=/home/zdmuser/zdmhome
export ZDM_REMOTE_JAVA_HOME=/home/zdmuser/zdmhome/jdk
```

## Output Location

Discovery outputs are saved to:

```
Artifacts/Phase10-Migration/ZDM/PRODDB/Step0/Discovery/
├── source/              # Source database discovery results
│   ├── zdm_source_discovery_<hostname>_<timestamp>.txt
│   ├── zdm_source_discovery_<hostname>_<timestamp>.json
│   └── discovery_output.log
├── target/              # Target database discovery results
│   ├── zdm_target_discovery_<hostname>_<timestamp>.txt
│   ├── zdm_target_discovery_<hostname>_<timestamp>.json
│   └── discovery_output.log
└── server/              # ZDM server discovery results
    ├── zdm_server_discovery_<hostname>_<timestamp>.txt
    ├── zdm_server_discovery_<hostname>_<timestamp>.json
    └── discovery_output.log
```

## Discovery Coverage

### Source Database Discovery
- OS information (hostname, IP, disk space)
- Oracle environment (ORACLE_HOME, ORACLE_SID, version)
- Database configuration (name, DBID, role, log mode)
- Container database (CDB/PDB status)
- TDE configuration
- Supplemental logging
- Redo/Archive configuration
- Network configuration (listener, tnsnames, sqlnet)
- Authentication (password files, SSH)
- Data Guard configuration
- Schema information

**Additional (Custom Requirements):**
- Tablespace autoextend settings
- Backup schedule and retention
- Database links
- Materialized view refresh schedules
- Scheduler jobs

### Target Database Discovery
- OS information
- Oracle environment
- Database configuration
- Storage (tablespaces, ASM disk groups)
- CDB/PDB configuration
- TDE/Wallet status
- Network configuration
- OCI/Azure integration
- Grid Infrastructure (if RAC)
- SSH configuration

**Additional (Custom Requirements):**
- Exadata storage capacity
- Pre-configured PDBs
- Network security group rules

### ZDM Server Discovery
- OS information
- ZDM installation verification
- ZDM service status
- Active migration jobs
- Java configuration
- OCI CLI configuration
- SSH configuration
- Network configuration
- ZDM logs

**Additional (Custom Requirements):**
- Disk space for ZDM operations (minimum 50GB recommended)
- Network latency to source and target (ping tests)

## SSH Authentication Model

The scripts use a secure admin-user-with-sudo pattern:

```
ZDM Server (azureuser)
    │
    ├──► SSH as oracle (source) ──► sudo -u oracle (for SQL)
    │
    ├──► SSH as opc (target) ──► sudo -u oracle (for SQL)
    │
    └──► Local execution ──► sudo -u zdmuser (for ZDM CLI)
```

## Troubleshooting

### SSH Connection Fails
1. Verify SSH key exists: `ls -la ~/.ssh/`
2. Check SSH key permissions: `chmod 600 ~/.ssh/*_key`
3. Test manual SSH: `ssh -i ~/.ssh/key_file user@host`

### Oracle Environment Not Detected
1. Check /etc/oratab exists on target server
2. Verify pmon process is running: `ps -ef | grep pmon`
3. Set explicit overrides: `SOURCE_REMOTE_ORACLE_HOME=/path/to/oracle`

### ZDM Not Detected
1. Verify zdmuser exists: `id zdmuser`
2. Check ZDM installation: `ls -la /home/zdmuser/zdmhome/bin/zdmcli`
3. Set explicit override: `ZDM_REMOTE_ZDM_HOME=/path/to/zdmhome`

## Next Steps

After running discovery:

1. Review the discovery reports in the Discovery directory
2. Proceed to **Step 1: Discovery Questionnaire** using:
   ```
   @Step1-Discovery-Questionnaire.prompt.md
   ```
3. Complete the questionnaire with discovery data and business decisions

## Security Notes

⚠️ **IMPORTANT**: Password environment variables should be set at **migration runtime** on the ZDM server, NOT saved to any files:

```bash
# Set passwords securely at runtime (on ZDM server)
read -sp "Enter SOURCE_SYS_PASSWORD: " SOURCE_SYS_PASSWORD; echo; export SOURCE_SYS_PASSWORD
read -sp "Enter TARGET_SYS_PASSWORD: " TARGET_SYS_PASSWORD; echo; export TARGET_SYS_PASSWORD
```

Never commit passwords to version control.

---

*Generated by ZDM Migration Discovery - Step 0*
*Project: PRODDB Migration to Oracle Database@Azure*
