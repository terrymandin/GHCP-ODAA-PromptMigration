# Step 0: Discovery Scripts - PRODDB Migration

This directory contains the discovery phase artifacts for the PRODDB migration to Oracle Database@Azure using Zero Downtime Migration (ZDM).

## Project Details

| Parameter | Value |
|-----------|-------|
| **Project Name** | PRODDB Migration to Oracle Database@Azure |
| **Source Database** | proddb01.corp.example.com |
| **Target Database** | proddb-oda.eastus.azure.example.com |
| **ZDM Server** | zdm-jumpbox.corp.example.com |
| **Generated** | 2026-01-30 |

## Directory Structure

```
Step0/
├── README.md                  # This file
├── Scripts/                   # Discovery scripts
│   ├── zdm_source_discovery.sh
│   ├── zdm_target_discovery.sh
│   ├── zdm_server_discovery.sh
│   ├── zdm_orchestrate_discovery.sh
│   └── README.md
└── Discovery/                 # Output files (after execution)
    ├── source/
    ├── target/
    └── server/
```

## Quick Start

1. **Navigate to Scripts directory:**
   ```bash
   cd Scripts/
   ```

2. **Make scripts executable:**
   ```bash
   chmod +x *.sh
   ```

3. **Test SSH connectivity:**
   ```bash
   ./zdm_orchestrate_discovery.sh --test
   ```

4. **Run discovery:**
   ```bash
   ./zdm_orchestrate_discovery.sh
   ```

5. **Review results in Discovery/ directory**

## SSH Keys Required

Ensure the following SSH keys are available:

| Server | User | SSH Key |
|--------|------|---------|
| proddb01.corp.example.com | oracle | `~/.ssh/source_db_key` |
| proddb-oda.eastus.azure.example.com | opc | `~/.ssh/oda_azure_key` |
| zdm-jumpbox.corp.example.com | zdmuser | `~/.ssh/zdm_jumpbox_key` |

## Additional Discovery (PRODDB-Specific)

These scripts include additional discovery beyond the standard ZDM requirements:

### Source Database
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
- Available disk space (minimum 50GB recommended)
- Network latency to source and target (ping tests)

## Next Steps

After completing discovery:

1. ✅ **Step 0 Complete** - Discovery scripts executed
2. ➡️ **Step 1** - Complete the Discovery Questionnaire using collected data
3. ⏳ **Step 2** - Generate migration artifacts based on questionnaire responses

## Troubleshooting

### SSH Connection Issues
```bash
# Test individual connections
ssh -i ~/.ssh/source_db_key -v oracle@proddb01.corp.example.com
ssh -i ~/.ssh/oda_azure_key -v opc@proddb-oda.eastus.azure.example.com
ssh -i ~/.ssh/zdm_jumpbox_key -v zdmuser@zdm-jumpbox.corp.example.com
```

### Environment Detection Issues
If auto-detection fails, set environment overrides:
```bash
export SOURCE_REMOTE_ORACLE_HOME=/u01/app/oracle/product/19.0.0.0/dbhome_1
export SOURCE_REMOTE_ORACLE_SID=PRODDB
./zdm_orchestrate_discovery.sh
```

### Running Discovery on Individual Servers
```bash
./zdm_orchestrate_discovery.sh --source-only
./zdm_orchestrate_discovery.sh --target-only
./zdm_orchestrate_discovery.sh --zdm-only
```
