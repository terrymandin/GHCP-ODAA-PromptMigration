# ZDM Discovery Scripts - PRODDB Migration

## Project Information

- **Project Name**: PRODDB Migration to Oracle Database@Azure
- **Source Database**: proddb01.corp.example.com
- **Target Database**: proddb-oda.eastus.azure.example.com
- **ZDM Server**: zdm-jumpbox.corp.example.com

## Scripts Overview

| Script | Purpose | Target Server |
|--------|---------|---------------|
| `zdm_orchestrate_discovery.sh` | Master orchestration script | Run from any machine with SSH access |
| `zdm_source_discovery.sh` | Discover source database configuration | Source database server |
| `zdm_target_discovery.sh` | Discover target Oracle Database@Azure | Target ODA server |
| `zdm_server_discovery.sh` | Discover ZDM jumpbox configuration | ZDM server |

## User Configuration

| Server | SSH User | SSH Key | Application User |
|--------|----------|---------|------------------|
| Source | oracle | `~/.ssh/onprem_oracle_key` | oracle |
| Target | opc | `~/.ssh/oci_opc_key` | oracle |
| ZDM | azureuser | `~/.ssh/azure_key` | zdmuser |

## Quick Start

### Option 1: Run Orchestration Script (Recommended)

From any machine with SSH access to all servers:

```bash
# Navigate to the scripts directory
cd Artifacts/Phase10-Migration/ZDM/PRODDB/Step0/Scripts

# Make scripts executable
chmod +x *.sh

# Test connectivity first
./zdm_orchestrate_discovery.sh -t

# Run full discovery
./zdm_orchestrate_discovery.sh
```

### Option 2: Run Individual Scripts Manually

If the orchestration script doesn't work, you can run each discovery script manually:

```bash
# Source database
scp zdm_source_discovery.sh oracle@proddb01.corp.example.com:~/
ssh oracle@proddb01.corp.example.com "chmod +x ~/zdm_source_discovery.sh && ~/zdm_source_discovery.sh"

# Target database
scp zdm_target_discovery.sh opc@proddb-oda.eastus.azure.example.com:~/
ssh opc@proddb-oda.eastus.azure.example.com "chmod +x ~/zdm_target_discovery.sh && ~/zdm_target_discovery.sh"

# ZDM server
scp zdm_server_discovery.sh azureuser@zdm-jumpbox.corp.example.com:~/
ssh azureuser@zdm-jumpbox.corp.example.com "chmod +x ~/zdm_server_discovery.sh && SOURCE_HOST='proddb01.corp.example.com' TARGET_HOST='proddb-oda.eastus.azure.example.com' ~/zdm_server_discovery.sh"
```

## Environment Variables

You can customize the discovery by setting environment variables before running:

```bash
# Server hostnames
export SOURCE_HOST="proddb01.corp.example.com"
export TARGET_HOST="proddb-oda.eastus.azure.example.com"
export ZDM_HOST="zdm-jumpbox.corp.example.com"

# SSH users
export SOURCE_ADMIN_USER="oracle"
export TARGET_ADMIN_USER="opc"
export ZDM_ADMIN_USER="azureuser"

# SSH keys
export SOURCE_SSH_KEY="$HOME/.ssh/onprem_oracle_key"
export TARGET_SSH_KEY="$HOME/.ssh/oci_opc_key"
export ZDM_SSH_KEY="$HOME/.ssh/azure_key"

# Application users
export ORACLE_USER="oracle"
export ZDM_USER="zdmuser"

./zdm_orchestrate_discovery.sh
```

## Line Ending Warning

⚠️ **IMPORTANT**: These scripts must use Unix-style line endings (LF only).

If you encounter errors like:
```
bash: line 359: ssh_port_22:: command not found
bash: line 360: syntax error near unexpected token `}'
```

Convert the scripts to Unix line endings:
```bash
# On Linux/Mac
sed -i 's/\r$//' *.sh

# Or using dos2unix
dos2unix *.sh

# On Windows PowerShell (before copying to Linux)
(Get-Content script.sh -Raw) -replace "`r`n", "`n" | Set-Content -NoNewline script.sh
```

## Output Files

After running discovery, output files are saved to:

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

## Additional Discovery Items

These scripts include project-specific discovery beyond standard ZDM requirements:

### Source Database
- Tablespace autoextend settings
- Backup schedule and retention (RMAN configuration)
- Database links
- Materialized view refresh schedules
- Scheduler jobs that may need reconfiguration

### Target Database
- Exadata storage capacity
- Pre-configured PDBs
- Network security group rules

### ZDM Server
- Disk space verification (minimum 50GB recommended)
- Network latency tests to source and target
- Port connectivity tests (SSH:22, Oracle:1521)

## Next Steps

After completing discovery:

1. **Review output files** in the Discovery/ directory
2. **Address any issues** identified (e.g., missing TDE wallet, ARCHIVELOG mode)
3. **Proceed to Step 1**: Discovery Questionnaire to gather additional manual configuration details
4. **Complete Step 2**: Fix any issues identified
5. **Generate Step 3**: Migration artifacts and run the migration

## Troubleshooting

### SSH Connection Failures
- Verify SSH keys exist and have correct permissions (600)
- Check that the user can SSH to the server manually
- Verify firewall rules allow SSH (port 22)

### Oracle Environment Not Detected
- Check that /etc/oratab exists and has entries
- Verify ORACLE_HOME and ORACLE_SID in the oracle user's environment
- Try setting environment overrides before running

### ZDM Not Detected
- Verify ZDM is installed and the zdmuser exists
- Check ZDM_HOME in zdmuser's environment
- Look for zdmcli in common paths (/u01/app/zdmhome, /home/zdmuser/zdmhome)

---

*Generated for PRODDB Migration to Oracle Database@Azure*
*Date: Generated by ZDM Discovery Script Generator*
