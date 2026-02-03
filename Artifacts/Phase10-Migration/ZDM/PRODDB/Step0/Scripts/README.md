# ZDM Discovery Scripts - PRODDB Migration

This directory contains discovery scripts for the **PRODDB Migration to Oracle Database@Azure** project.

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
| Oracle DB Owner | oracle |
| ZDM Software Owner | zdmuser |

## Scripts

| Script | Purpose |
|--------|---------|
| `zdm_source_discovery.sh` | Discovers source database configuration, including additional checks for tablespace autoextend, backup schedules, database links, materialized views, and scheduler jobs |
| `zdm_target_discovery.sh` | Discovers target Oracle Database@Azure configuration, including Exadata storage capacity, pre-configured PDBs, and network security information |
| `zdm_server_discovery.sh` | Discovers ZDM server configuration, including disk space verification (50GB minimum) and network latency tests to source/target |
| `zdm_orchestrate_discovery.sh` | Master orchestration script to run all discoveries |

## Quick Start

### Option 1: Run Orchestration Script (Recommended)

The orchestration script handles everything automatically:

```bash
# Make scripts executable
chmod +x *.sh

# Run full discovery
./zdm_orchestrate_discovery.sh

# Or test connectivity first
./zdm_orchestrate_discovery.sh --test

# View current configuration
./zdm_orchestrate_discovery.sh --config
```

### Option 2: Run Individual Scripts

If you need to run discovery on a specific server:

```bash
# Source database
ssh -i ~/.ssh/onprem_oracle_key oracle@proddb01.corp.example.com "bash -l" < zdm_source_discovery.sh

# Target database
ssh -i ~/.ssh/oci_opc_key opc@proddb-oda.eastus.azure.example.com "bash -l" < zdm_target_discovery.sh

# ZDM server
ssh -i ~/.ssh/azure_key azureuser@zdm-jumpbox.corp.example.com "bash -l" < zdm_server_discovery.sh
```

## Environment Variable Overrides

If auto-detection fails, you can set environment variables before running the orchestration:

```bash
# Optional: Override Oracle paths on source
export SOURCE_REMOTE_ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1
export SOURCE_REMOTE_ORACLE_SID=PRODDB

# Optional: Override Oracle paths on target
export TARGET_REMOTE_ORACLE_HOME=/u02/app/oracle/product/19.0.0.0/dbhome_1

# Optional: Override ZDM paths
export ZDM_REMOTE_ZDM_HOME=/home/zdmuser/zdmhome

# Run discovery
./zdm_orchestrate_discovery.sh
```

## Output Files

Discovery results are saved to `../Discovery/`:

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

## Additional Discovery Included

### Source Database (PRODDB-Specific)
- ✅ Tablespace autoextend settings
- ✅ Current backup schedule and retention
- ✅ Database links configured
- ✅ Materialized view refresh schedules
- ✅ Scheduler jobs that may need reconfiguration

### Target Database (Oracle Database@Azure)
- ✅ Available Exadata storage capacity
- ✅ Pre-configured PDBs
- ✅ Network security group rules

### ZDM Server
- ✅ Available disk space (50GB minimum recommended)
- ✅ Network latency to source and target (ping tests)
- ✅ Port connectivity tests (SSH 22, Oracle 1521)

## Troubleshooting

### Windows Line Endings

If scripts fail with errors like `ssh_port_22:: command not found`, convert line endings:

```bash
# On Linux/Mac
sed -i 's/\r$//' *.sh

# Or use dos2unix
dos2unix *.sh
```

### SSH Connection Failures

1. Verify SSH key permissions: `chmod 600 ~/.ssh/*_key`
2. Test connection manually: `ssh -v -i <key> <user>@<host>`
3. Check firewall rules on target servers

### Oracle Environment Not Detected

If auto-detection fails, set explicit environment variables (see above).

## Next Steps

After running discovery:

1. Review the generated reports in `../Discovery/`
2. Proceed to **Step 1: Discovery Questionnaire** to complete the full questionnaire
3. Reference: `@Step1-Discovery-Questionnaire.prompt.md`

## Security Notes

⚠️ **Never commit passwords to source control!**

Password environment variables (`SOURCE_SYS_PASSWORD`, `TARGET_SYS_PASSWORD`, `SOURCE_TDE_WALLET_PASSWORD`) should be set at migration runtime on the ZDM server:

```bash
# Securely prompt for passwords
read -sp "Enter SOURCE_SYS_PASSWORD: " SOURCE_SYS_PASSWORD; echo; export SOURCE_SYS_PASSWORD
read -sp "Enter TARGET_SYS_PASSWORD: " TARGET_SYS_PASSWORD; echo; export TARGET_SYS_PASSWORD
```
