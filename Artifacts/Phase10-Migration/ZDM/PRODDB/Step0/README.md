# ZDM Migration Step 0: Discovery - PRODDB

## Project Information

| Field | Value |
|-------|-------|
| **Project Name** | PRODDB Migration to Oracle Database@Azure |
| **Source Database** | proddb01.corp.example.com |
| **Target Database** | proddb-oda.eastus.azure.example.com |
| **ZDM Server** | zdm-jumpbox.corp.example.com |
| **Generated** | 2026-01-29 |

---

## Overview

Step 0 generates and runs discovery scripts to gather information about the source database, target Oracle Database@Azure, and ZDM jumpbox server. This information will be used in Step 1 to complete the migration questionnaire.

---

## Directory Contents

```
Step0/
├── Scripts/                              # Discovery scripts
│   ├── zdm_source_discovery.sh           # Source database discovery
│   ├── zdm_target_discovery.sh           # Target database discovery  
│   ├── zdm_server_discovery.sh           # ZDM server discovery
│   ├── zdm_orchestrate_discovery.sh      # Orchestration script
│   └── README.md                         # Script documentation
├── Discovery/                            # Discovery output files (after execution)
│   └── (output files will be placed here)
└── README.md                             # This file
```

---

## Instructions

### 1. Review the Discovery Scripts

Navigate to the `Scripts/` directory and review the generated scripts:
- [zdm_source_discovery.sh](Scripts/zdm_source_discovery.sh) - Runs on source database server
- [zdm_target_discovery.sh](Scripts/zdm_target_discovery.sh) - Runs on target Oracle Database@Azure
- [zdm_server_discovery.sh](Scripts/zdm_server_discovery.sh) - Runs on ZDM jumpbox
- [zdm_orchestrate_discovery.sh](Scripts/zdm_orchestrate_discovery.sh) - Orchestrates all discoveries

### 2. Configure the Orchestration Script

Edit `Scripts/zdm_orchestrate_discovery.sh` to update the configuration:

```bash
SOURCE_HOST="proddb01.corp.example.com"
SOURCE_USER="oracle"

TARGET_HOST="proddb-oda.eastus.azure.example.com"
TARGET_USER="opc"

ZDM_HOST="zdm-jumpbox.corp.example.com"
ZDM_USER="zdmuser"

SSH_KEY="~/.ssh/id_rsa"
```

### 3. Test Connectivity

```bash
cd Scripts/
./zdm_orchestrate_discovery.sh --test
```

### 4. Run Discovery

**Option A: Run all discoveries (recommended):**
```bash
./zdm_orchestrate_discovery.sh
```

**Option B: Run individual discoveries:**
```bash
./zdm_orchestrate_discovery.sh --source   # Source only
./zdm_orchestrate_discovery.sh --target   # Target only
./zdm_orchestrate_discovery.sh --zdm      # ZDM server only
```

### 5. Review Discovery Results

After discovery completes, review the output files in `Discovery/`:
- Text reports (`.txt`) - Human-readable detailed discovery
- JSON summaries (`.json`) - Machine-parseable data

---

## Custom Discovery Items for PRODDB

In addition to standard discovery, these project-specific items are gathered:

### Source Database
- ✓ Tablespace autoextend settings
- ✓ Current backup schedule and retention (RMAN)
- ✓ Database links configured
- ✓ Materialized view refresh schedules
- ✓ Scheduler jobs that may need reconfiguration

### Target Database (Oracle Database@Azure)
- ✓ Available Exadata storage capacity
- ✓ Pre-configured PDBs
- ✓ Network security group rules (local firewall)

### ZDM Server
- ✓ Available disk space for ZDM operations (minimum 50GB)
- ✓ Network latency to source and target (ping tests)
- ✓ Port connectivity tests (SSH and Oracle listener)

---

## Expected Output

After running discovery, you should have:

| File | Description |
|------|-------------|
| `zdm_source_discovery_<hostname>_<timestamp>.txt` | Detailed source discovery report |
| `zdm_source_discovery_<hostname>_<timestamp>.json` | Source discovery JSON summary |
| `zdm_target_discovery_<hostname>_<timestamp>.txt` | Detailed target discovery report |
| `zdm_target_discovery_<hostname>_<timestamp>.json` | Target discovery JSON summary |
| `zdm_server_discovery_<hostname>_<timestamp>.txt` | Detailed ZDM server discovery report |
| `zdm_server_discovery_<hostname>_<timestamp>.json` | ZDM server discovery JSON summary |

---

## Next Steps

1. ✅ **Step 0 Complete:** Discovery scripts generated and executed
2. ➡️ **Step 1:** Complete the Discovery Questionnaire using the collected data
3. ⏳ **Step 2:** Generate ZDM migration artifacts

To proceed to Step 1, use the prompt:
```
@Step1-Discovery-Questionnaire.prompt.md
```

---

## Troubleshooting

### Discovery Script Failed

1. Check SSH connectivity:
   ```bash
   ./zdm_orchestrate_discovery.sh --test
   ```

2. Verify user permissions:
   - Source: `oracle` user must have SYSDBA access
   - Target: `opc` or `oracle` user must have SYSDBA access
   - ZDM: `zdmuser` must have access to ZDM_HOME

3. Check Oracle environment is set:
   ```bash
   echo $ORACLE_HOME
   echo $ORACLE_SID
   ```

### Missing Information

If discovery is incomplete:
1. Review the discovery script output for errors
2. Run specific sections manually via sqlplus
3. Document any manual discoveries in the Step 1 questionnaire
