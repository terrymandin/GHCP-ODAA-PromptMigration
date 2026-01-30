# ZDM Migration Step 0: Discovery

## Project: PRODDB Migration to Oracle Database@Azure

This directory contains the Step 0 artifacts for the PRODDB migration project.

## Directory Structure

```
Step0/
├── README.md              # This file
├── Scripts/               # Discovery scripts
│   ├── zdm_source_discovery.sh
│   ├── zdm_target_discovery.sh
│   ├── zdm_server_discovery.sh
│   ├── zdm_orchestrate_discovery.sh
│   └── README.md
└── Discovery/             # Discovery output (after execution)
    ├── source/
    ├── target/
    └── server/
```

## Migration Configuration

| Parameter | Value |
|-----------|-------|
| Project Name | PRODDB Migration to Oracle Database@Azure |
| Source Database | proddb01.corp.example.com |
| Target Database | proddb-oda.eastus.azure.example.com |
| ZDM Server | zdm-jumpbox.corp.example.com |

### User Configuration

| Server | SSH Admin User | Purpose |
|--------|---------------|---------|
| Source | oracle | On-premise server SSH access |
| Target | opc | OCI/ODA SSH access |
| ZDM | azureuser | Azure VM SSH access |

| User | Purpose |
|------|---------|
| oracle | Oracle database software owner |
| zdmuser | ZDM software owner |

### SSH Key Configuration

| Server | SSH Key Path |
|--------|--------------|
| Source | ~/.ssh/onprem_oracle_key |
| Target | ~/.ssh/oci_opc_key |
| ZDM | ~/.ssh/azure_key |

## Quick Start

1. Navigate to the Scripts directory:
   ```bash
   cd Scripts/
   ```

2. Make scripts executable:
   ```bash
   chmod +x *.sh
   ```

3. Test connectivity:
   ```bash
   ./zdm_orchestrate_discovery.sh -t
   ```

4. Run discovery:
   ```bash
   ./zdm_orchestrate_discovery.sh
   ```

5. Review results in `Discovery/` directory

## Additional Discovery Items

This discovery includes extra checks specific to this migration:

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
- Available disk space for ZDM operations (minimum 50GB recommended)
- Network latency tests to source and target

## Next Steps

After completing Step 0:

1. **Review Discovery Reports** - Examine the text and JSON reports
2. **Proceed to Step 1** - Complete the Discovery Questionnaire using the gathered information
3. **Proceed to Step 2** - Generate migration artifacts based on questionnaire answers

## File Locations

| Artifact | Location |
|----------|----------|
| Discovery Scripts | `Scripts/` |
| Discovery Output | `Discovery/` |
| Step 1 Questionnaire | `../Step1/` |
| Step 2 Migration Artifacts | `../Step2/` |

---
Generated for PRODDB Migration Project
