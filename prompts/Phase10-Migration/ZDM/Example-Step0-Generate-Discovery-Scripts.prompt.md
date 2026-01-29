# Example: Generate Discovery Scripts for PRODDB Migration

This example demonstrates how to use Step 0 to generate fresh discovery scripts for a production Oracle database migration to Oracle Database@Azure.

## Prerequisites

Before using this example:
- Identify the source database server hostname and access credentials
- Identify the target Oracle Database@Azure hostname and access credentials
- Identify the ZDM jumpbox server hostname and access credentials
- Ensure SSH access is available between servers

---

## Example Prompt

Copy and use this prompt to generate discovery scripts:

```
@Step0-Generate-Discovery-Scripts.prompt.md

Generate discovery scripts for our PRODDB migration project.

## Migration Project Details
- Project Name: PRODDB Migration to Oracle Database@Azure
- Source Database: proddb01.corp.example.com
- Target Database: proddb-oda.eastus.azure.example.com  
- ZDM Server: zdm-jumpbox.corp.example.com

## Script Output Location
Save all generated scripts to: Artifacts/Phase10-Migration/ZDM/PRODDB/Scripts/

## Additional Discovery Requirements

### Source Database
In addition to the standard discovery, also gather:
- All tablespace autoextend settings
- Current backup schedule and retention
- Any database links configured
- Materialized view refresh schedules
- Scheduler jobs that may need reconfiguration

### Target Database (Oracle Database@Azure)
In addition to the standard discovery, also gather:
- Available Exadata storage capacity
- Pre-configured PDBs
- Network security group rules

### ZDM Server
In addition to the standard discovery, also verify:
- Available disk space for ZDM operations (minimum 50GB recommended)
- Network latency to source and target (ping tests)
```

---

## Expected Output

The prompt will generate all Step 0 artifacts in `Artifacts/Phase10-Migration/ZDM/PRODDB/Step0/`:

```
Artifacts/Phase10-Migration/ZDM/PRODDB/
├── Step0/
│   ├── Scripts/
│   │   ├── zdm_source_discovery.sh
│   │   ├── zdm_target_discovery.sh
│   │   ├── zdm_server_discovery.sh
│   │   ├── zdm_orchestrate_discovery.sh
│   │   └── README.md
│   ├── Discovery/           # Outputs collected after execution
│   └── README.md
├── Step1/                   # Completed questionnaire (after Step 1)
└── Step2/                   # Migration artifacts (after Step 2)
```

---

### 1. zdm_source_discovery.sh
```bash
#!/bin/bash
# ZDM Source Database Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# Target: proddb01.corp.example.com
# Generated: 2026-01-28

set -e

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname)
OUTPUT_FILE="/tmp/zdm_source_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_FILE="/tmp/zdm_source_discovery_${HOSTNAME}_${TIMESTAMP}.json"

# ... comprehensive discovery logic ...

# Additional custom discovery for tablespace autoextend
log_section "TABLESPACE AUTOEXTEND SETTINGS"
run_sql "
SELECT tablespace_name, file_name, autoextensible, 
       maxbytes/1024/1024/1024 as max_gb
FROM dba_data_files ORDER BY tablespace_name;
"

# Additional custom discovery for database links
log_section "DATABASE LINKS"
run_sql "SELECT owner, db_link, host FROM dba_db_links;"

# ... rest of script ...
```

### 2. zdm_target_discovery.sh
```bash
#!/bin/bash
# ZDM Target Database Discovery Script
# Oracle Database@Azure
# Target: proddb-oda.eastus.azure.example.com
# Generated: 2026-01-28

# ... comprehensive discovery logic for ODA@Azure ...
```

### 3. zdm_server_discovery.sh
```bash
#!/bin/bash
# ZDM Server Discovery Script
# Target: zdm-jumpbox.corp.example.com
# Generated: 2026-01-28

# ... ZDM jumpbox discovery logic ...

# Additional disk space check
log_section "DISK SPACE FOR ZDM OPERATIONS"
df -h | grep -E "^/dev|Filesystem"
echo "Minimum 50GB recommended for ZDM operations"

# Network latency tests
log_section "NETWORK LATENCY TESTS"
echo "Ping to source (proddb01.corp.example.com):"
ping -c 5 proddb01.corp.example.com 2>&1 | tail -3
echo ""
echo "Ping to target (proddb-oda.eastus.azure.example.com):"
ping -c 5 proddb-oda.eastus.azure.example.com 2>&1 | tail -3
```

### 4. zdm_orchestrate_discovery.sh
```bash
#!/bin/bash
# ZDM Discovery Orchestration Script
# Project: PRODDB Migration
# Generated: 2026-01-28

# Pre-configured for this migration
SOURCE_HOST="proddb01.corp.example.com"
SOURCE_USER="oracle"
TARGET_HOST="proddb-oda.eastus.azure.example.com"
TARGET_USER="opc"
ZDM_HOST="zdm-jumpbox.corp.example.com"
ZDM_USER="zdmuser"
SSH_KEY="${SSH_KEY:-~/.ssh/zdm_migration_key}"

# ... orchestration logic ...
```

---

## How to Execute Discovery

After generating the scripts:

### Option 1: Run Orchestration Script (Recommended)
```bash
# From any machine with SSH access to all servers
export SSH_KEY=~/.ssh/zdm_migration_key
cd Artifacts/Phase10-Migration/ZDM/PRODDB/Step0/Scripts
./zdm_orchestrate_discovery.sh
```

### Option 2: Run Scripts Individually
```bash
# 1. Copy and run on source database server
scp zdm_source_discovery.sh oracle@proddb01.corp.example.com:/tmp/
ssh oracle@proddb01.corp.example.com "chmod +x /tmp/zdm_source_discovery.sh && /tmp/zdm_source_discovery.sh"

# 2. Copy and run on target server
scp zdm_target_discovery.sh opc@proddb-oda.eastus.azure.example.com:/tmp/
ssh opc@proddb-oda.eastus.azure.example.com "chmod +x /tmp/zdm_target_discovery.sh && /tmp/zdm_target_discovery.sh"

# 3. Copy and run on ZDM server
scp zdm_server_discovery.sh zdmuser@zdm-jumpbox.corp.example.com:/tmp/
ssh zdmuser@zdm-jumpbox.corp.example.com "chmod +x /tmp/zdm_server_discovery.sh && /tmp/zdm_server_discovery.sh"

# 4. Collect results to Step0/Discovery/
scp oracle@proddb01.corp.example.com:/tmp/zdm_source_discovery_*.txt ../Discovery/
scp opc@proddb-oda.eastus.azure.example.com:/tmp/zdm_target_discovery_*.txt ../Discovery/
scp zdmuser@zdm-jumpbox.corp.example.com:/tmp/zdm_server_discovery_*.txt ../Discovery/
```

---

## Next Steps

After generating and executing discovery scripts:

1. **Run Discovery Scripts** (`Step0/Scripts/`)
   - Execute scripts on all servers
   - Collect output files to `Step0/Discovery/`

2. **Proceed to Step 1**
   - Use `Step1-Discovery-Questionnaire.prompt.md`
   - Attach discovery output files from `Step0/Discovery/`
   - Complete all sections including business decisions (migration type, timeline, OCI identifiers, etc.)
   - Save output to `Step1/Completed-Questionnaire-PRODDB.md`

3. **Proceed to Step 2**
   - Generate RSP file, CLI commands, and runbook
   - Save outputs to `Step2/`

---

## Tips

- **Always regenerate scripts** for each new migration project to ensure they're current
- **Customize additional discovery** based on your specific database features
- **Test SSH connectivity** before running the orchestration script
- **Review outputs carefully** - discovery data drives all subsequent artifacts
- **Business decisions are captured in Step 1** - the questionnaire combines technical discovery with business/architectural decisions
