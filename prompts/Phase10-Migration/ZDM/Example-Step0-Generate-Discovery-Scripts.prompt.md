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

## SSH Key Configuration
- Source SSH Key: ~/.ssh/source_db_key
- Target SSH Key: ~/.ssh/oda_azure_key
- ZDM SSH Key: ~/.ssh/zdm_jumpbox_key

## Explicit Environment Variables (Optional - use if profile sourcing fails)
# These are passed to remote scripts when .bashrc has non-interactive guards
- ZDM_REMOTE_ZDM_HOME: /home/zdmuser/zdmhome
- ZDM_REMOTE_JAVA_HOME: /usr/java/jdk1.8.0_391
- SOURCE_REMOTE_ORACLE_HOME: /u01/app/oracle/product/19.0.0.0/dbhome_1
- SOURCE_REMOTE_ORACLE_SID: PRODDB
- TARGET_REMOTE_ORACLE_HOME: /u01/app/oracle/product/19.0.0.0/dbhome_1
- TARGET_REMOTE_ORACLE_SID: PRODDB

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
│   ├── Discovery/           # Outputs collected after execution (default output location)
│   │   ├── source/          # Source server discovery results
│   │   │   ├── zdm_source_discovery_*.txt
│   │   │   └── zdm_source_discovery_*.json
│   │   ├── target/          # Target server discovery results  
│   │   │   ├── zdm_target_discovery_*.txt
│   │   │   └── zdm_target_discovery_*.json
│   │   └── server/          # ZDM server discovery results
│   │       ├── zdm_server_discovery_*.txt
│   │       └── zdm_server_discovery_*.json
│   └── README.md
├── Step1/                   # Completed questionnaire (after Step 1)
└── Step2/                   # Migration artifacts (after Step 2)
```

### Key Resilience Features

All generated scripts include:

1. **Environment Variable Sourcing with Fallbacks** - Scripts use multiple approaches to ensure ZDM_HOME, ORACLE_HOME, JAVA_HOME, etc. are available even in non-interactive SSH sessions:
   ```bash
   # Method 1: Accept explicit overrides (highest priority)
   [ -n "${ZDM_HOME_OVERRIDE:-}" ] && export ZDM_HOME="$ZDM_HOME_OVERRIDE"
   
   # Method 2: Extract export statements from profiles (works in non-interactive shells)
   for profile in /etc/profile ~/.bash_profile ~/.bashrc; do
       if [ -f "$profile" ]; then
           # Extract exports without running interactive guards
           eval "$(grep -E '^export\s+' "$profile" 2>/dev/null)" || true
       fi
   done
   
   # Method 3: Search common installation paths as fallback
   if [ -z "$ZDM_HOME" ]; then
       for zdm_path in /home/*/zdmhome /opt/zdm* /u01/app/zdm*; do
           [ -d "$zdm_path" ] && export ZDM_HOME="$zdm_path" && break
       done
   fi
   ```

2. **Continue on Failure** - Each discovery section is wrapped in error handling:
   ```bash
   # Section runs even if previous sections failed
   discover_section "ZDM Installation" || SECTION_ERRORS=$((SECTION_ERRORS + 1))
   ```

3. **Resilient Orchestration** - The orchestration script continues even when individual server discoveries fail

4. **Artifacts Directory Output** - Results are collected to the Artifacts directory by default, not /tmp

---

### 1. zdm_source_discovery.sh
```bash
#!/bin/bash
# ZDM Source Database Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# Target: proddb01.corp.example.com
# Generated: 2026-01-28

# NO set -e - We want to continue even if some checks fail
SECTION_ERRORS=0

# CRITICAL: Handle environment variables in non-interactive SSH sessions
# .bashrc often has guards like '[ -z "$PS1" ] && return' that skip non-interactive shells

# Method 1: Accept explicit overrides (passed from orchestration script)
[ -n "${ORACLE_HOME_OVERRIDE:-}" ] && export ORACLE_HOME="$ORACLE_HOME_OVERRIDE"
[ -n "${ORACLE_SID_OVERRIDE:-}" ] && export ORACLE_SID="$ORACLE_SID_OVERRIDE"
[ -n "${ORACLE_BASE_OVERRIDE:-}" ] && export ORACLE_BASE="$ORACLE_BASE_OVERRIDE"

# Method 2: Extract export statements from profiles (bypasses interactive guards)
for profile in /etc/profile ~/.bash_profile ~/.bashrc; do
    if [ -f "$profile" ]; then
        eval "$(grep -E '^export\s+(ORACLE_HOME|ORACLE_SID|ORACLE_BASE|TNS_ADMIN|PATH)=' "$profile" 2>/dev/null)" || true
    fi
done

# Method 3: Try to find Oracle from oratab or common paths
if [ -z "$ORACLE_HOME" ]; then
    # Try oratab
    if [ -f /etc/oratab ]; then
        ORACLE_HOME=$(grep -v '^#' /etc/oratab | grep ':' | head -1 | cut -d: -f2)
        [ -n "$ORACLE_HOME" ] && export ORACLE_HOME
    fi
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname)
# Output to current directory (not /tmp)
OUTPUT_FILE="./zdm_source_discovery_${HOSTNAME}_${TIMESTAMP}.txt"
JSON_FILE="./zdm_source_discovery_${HOSTNAME}_${TIMESTAMP}.json"

# ... comprehensive discovery logic with resilient sections ...

# Each section wrapped in error handling
discover_tablespace_autoextend() {
    log_section "TABLESPACE AUTOEXTEND SETTINGS"
    run_sql "
    SELECT tablespace_name, file_name, autoextensible, 
           maxbytes/1024/1024/1024 as max_gb
    FROM dba_data_files ORDER BY tablespace_name;
    " || echo "WARNING: Failed to query tablespace autoextend settings"
}
discover_tablespace_autoextend || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# Additional custom discovery for database links
discover_database_links() {
    log_section "DATABASE LINKS"
    run_sql "SELECT owner, db_link, host FROM dba_db_links;" || echo "WARNING: Failed to query database links"
}
discover_database_links || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# ... rest of script ...
exit 0  # Always exit 0 so orchestrator knows script completed
```

### 2. zdm_target_discovery.sh
```bash
#!/bin/bash
# ZDM Target Database Discovery Script
# Oracle Database@Azure
# Target: proddb-oda.eastus.azure.example.com
# Generated: 2026-01-28

# NO set -e - We want to continue even if some checks fail
SECTION_ERRORS=0

# CRITICAL: Handle environment variables in non-interactive SSH sessions
# .bashrc often has guards like '[ -z "$PS1" ] && return' that skip non-interactive shells

# Method 1: Accept explicit overrides (passed from orchestration script)
[ -n "${ORACLE_HOME_OVERRIDE:-}" ] && export ORACLE_HOME="$ORACLE_HOME_OVERRIDE"
[ -n "${ORACLE_SID_OVERRIDE:-}" ] && export ORACLE_SID="$ORACLE_SID_OVERRIDE"
[ -n "${GRID_HOME_OVERRIDE:-}" ] && export GRID_HOME="$GRID_HOME_OVERRIDE"

# Method 2: Extract export statements from profiles (bypasses interactive guards)
for profile in /etc/profile ~/.bash_profile ~/.bashrc; do
    if [ -f "$profile" ]; then
        eval "$(grep -E '^export\s+(ORACLE_HOME|ORACLE_SID|ORACLE_BASE|GRID_HOME|TNS_ADMIN|PATH)=' "$profile" 2>/dev/null)" || true
    fi
done

# Method 3: For ODA@Azure, check common Grid/Oracle home locations
if [ -z "$ORACLE_HOME" ]; then
    for ora_path in /u01/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1; do
        [ -d "$ora_path" ] && export ORACLE_HOME="$ora_path" && break
    done
fi

# Output to current directory (not /tmp)
OUTPUT_FILE="./zdm_target_discovery_$(hostname)_$(date +%Y%m%d_%H%M%S).txt"
JSON_FILE="./zdm_target_discovery_$(hostname)_$(date +%Y%m%d_%H%M%S).json"

# ... comprehensive discovery logic for ODA@Azure with resilient sections ...
```

### 3. zdm_server_discovery.sh
```bash
#!/bin/bash
# ZDM Server Discovery Script
# Target: zdm-jumpbox.corp.example.com
# Generated: 2026-01-28

# NO set -e - We want to continue even if some checks fail
SECTION_ERRORS=0

# CRITICAL: Handle environment variables in non-interactive SSH sessions
# .bashrc often has guards like '[ -z "$PS1" ] && return' that skip non-interactive shells

# Method 1: Accept explicit overrides (passed from orchestration script)
[ -n "${ZDM_HOME_OVERRIDE:-}" ] && export ZDM_HOME="$ZDM_HOME_OVERRIDE"
[ -n "${JAVA_HOME_OVERRIDE:-}" ] && export JAVA_HOME="$JAVA_HOME_OVERRIDE"

# Method 2: Extract export statements from profiles (bypasses interactive guards)
for profile in /etc/profile ~/.bash_profile ~/.bashrc; do
    if [ -f "$profile" ]; then
        # Extract export statements without running interactive checks
        eval "$(grep -E '^export\s+(ZDM_HOME|JAVA_HOME|PATH)=' "$profile" 2>/dev/null)" || true
    fi
done

# Method 3: Search common ZDM installation paths as fallback
if [ -z "$ZDM_HOME" ]; then
    for zdm_path in /home/*/zdmhome /home/*/zdm /opt/zdm* /u01/app/zdm*; do
        if [ -d "$zdm_path" ] && [ -f "$zdm_path/bin/zdmcli" ]; then
            export ZDM_HOME="$zdm_path"
            break
        fi
    done
fi

# Output to current directory (not /tmp)
OUTPUT_FILE="./zdm_server_discovery_$(hostname)_$(date +%Y%m%d_%H%M%S).txt"
JSON_FILE="./zdm_server_discovery_$(hostname)_$(date +%Y%m%d_%H%M%S).json"

# ... ZDM jumpbox discovery logic ...

# Additional disk space check with resilient error handling
discover_disk_space() {
    log_section "DISK SPACE FOR ZDM OPERATIONS"
    df -h | grep -E "^/dev|Filesystem" || echo "WARNING: Failed to get disk space"
    echo "Minimum 50GB recommended for ZDM operations"
}
discover_disk_space || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# Network latency tests with resilient error handling
discover_network_latency() {
    log_section "NETWORK LATENCY TESTS"
    echo "Ping to source (proddb01.corp.example.com):"
    ping -c 5 proddb01.corp.example.com 2>&1 | tail -3 || echo "WARNING: Ping to source failed"
    echo ""
    echo "Ping to target (proddb-oda.eastus.azure.example.com):"
    ping -c 5 proddb-oda.eastus.azure.example.com 2>&1 | tail -3 || echo "WARNING: Ping to target failed"
}
discover_network_latency || SECTION_ERRORS=$((SECTION_ERRORS + 1))

# Always exit 0 so orchestrator knows script completed
exit 0
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

# SSH Keys - typically different for each server environment
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-~/.ssh/source_db_key}"
TARGET_SSH_KEY="${TARGET_SSH_KEY:-~/.ssh/oda_azure_key}"
ZDM_SSH_KEY="${ZDM_SSH_KEY:-~/.ssh/zdm_jumpbox_key}"

# Explicit environment variable overrides (optional - use when profile sourcing fails)
# These are passed to remote scripts via environment
ZDM_REMOTE_ZDM_HOME="${ZDM_REMOTE_ZDM_HOME:-}"      # e.g., /home/zdmuser/zdmhome
ZDM_REMOTE_JAVA_HOME="${ZDM_REMOTE_JAVA_HOME:-}"    # e.g., /usr/java/jdk1.8.0
SOURCE_REMOTE_ORACLE_HOME="${SOURCE_REMOTE_ORACLE_HOME:-}"  # e.g., /u01/app/oracle/product/19c
SOURCE_REMOTE_ORACLE_SID="${SOURCE_REMOTE_ORACLE_SID:-}"    # e.g., PRODDB
TARGET_REMOTE_ORACLE_HOME="${TARGET_REMOTE_ORACLE_HOME:-}"  # e.g., /u01/app/oracle/product/19c
TARGET_REMOTE_ORACLE_SID="${TARGET_REMOTE_ORACLE_SID:-}"    # e.g., PRODDB

# Output directory - default to Artifacts directory
OUTPUT_DIR="${OUTPUT_DIR:-../../../Artifacts/Phase10-Migration/ZDM/PRODDB/Step0/Discovery}"

# Error tracking for resilience
SOURCE_SUCCESS=false
TARGET_SUCCESS=false
ZDM_SUCCESS=false

# ... resilient orchestration logic ...

run_discovery() {
    local host=$1
    local user=$2
    local ssh_key=$3
    local script=$4
    local target_type=$5
    local env_overrides=$6  # Additional environment variable exports
    
    # Use bash -l -c to simulate login shell (ensures profile files are sourced)
    # This is critical because non-interactive SSH does NOT source .bashrc by default
    ssh $SSH_OPTS -i "$ssh_key" "$user@$host" "bash -l -c '
        # Pass explicit environment overrides if provided
        $env_overrides
        
        # Now run the discovery script
        cd /tmp/zdm_discovery && chmod +x $script && ./$script
    '" 2>&1
    
    # Continue even if this fails
    return 0
}

# Run all discoveries - continue even if one fails
# Pass explicit environment variable overrides for each server type
run_discovery "$SOURCE_HOST" "$SOURCE_USER" "$SOURCE_SSH_KEY" "zdm_source_discovery.sh" "source" \
    "export ORACLE_HOME_OVERRIDE='$SOURCE_REMOTE_ORACLE_HOME'; export ORACLE_SID_OVERRIDE='$SOURCE_REMOTE_ORACLE_SID'" && SOURCE_SUCCESS=true
    
run_discovery "$TARGET_HOST" "$TARGET_USER" "$TARGET_SSH_KEY" "zdm_target_discovery.sh" "target" \
    "export ORACLE_HOME_OVERRIDE='$TARGET_REMOTE_ORACLE_HOME'; export ORACLE_SID_OVERRIDE='$TARGET_REMOTE_ORACLE_SID'" && TARGET_SUCCESS=true
    
run_discovery "$ZDM_HOST" "$ZDM_USER" "$ZDM_SSH_KEY" "zdm_server_discovery.sh" "server" \
    "export ZDM_HOME_OVERRIDE='$ZDM_REMOTE_ZDM_HOME'; export JAVA_HOME_OVERRIDE='$ZDM_REMOTE_JAVA_HOME'" && ZDM_SUCCESS=true

# Report results even if some failed
echo "Results: Source=$SOURCE_SUCCESS, Target=$TARGET_SUCCESS, ZDM=$ZDM_SUCCESS"
```

---

## How to Execute Discovery

After generating the scripts:

### Option 1: Run Orchestration Script (Recommended)
```bash
# From any machine with SSH access to all servers
# Set SSH keys for each environment (typically different keys for security)
export SOURCE_SSH_KEY=~/.ssh/source_db_key
export TARGET_SSH_KEY=~/.ssh/oda_azure_key
export ZDM_SSH_KEY=~/.ssh/zdm_jumpbox_key

# Optional: Override output directory (defaults to Artifacts/Phase10-Migration/ZDM/PRODDB/Step0/Discovery/)
export OUTPUT_DIR=./my_discovery_output

cd Artifacts/Phase10-Migration/ZDM/PRODDB/Step0/Scripts
./zdm_orchestrate_discovery.sh

# Results will be collected to the Discovery/ directory
# Script continues even if some discoveries fail
```

### Option 2: Run Scripts Individually
```bash
# Define SSH keys for each environment
SOURCE_SSH_KEY=~/.ssh/source_db_key
TARGET_SSH_KEY=~/.ssh/oda_azure_key
ZDM_SSH_KEY=~/.ssh/zdm_jumpbox_key

# 1. Copy and run on source database server
# Note: Scripts source environment files automatically for ORACLE_HOME, etc.
scp -i $SOURCE_SSH_KEY zdm_source_discovery.sh oracle@proddb01.corp.example.com:/tmp/zdm_discovery/
ssh -i $SOURCE_SSH_KEY oracle@proddb01.corp.example.com "cd /tmp/zdm_discovery && chmod +x zdm_source_discovery.sh && ./zdm_source_discovery.sh"

# 2. Copy and run on target server
# Note: Scripts source environment files automatically for ORACLE_HOME, etc.
scp -i $TARGET_SSH_KEY zdm_target_discovery.sh opc@proddb-oda.eastus.azure.example.com:/tmp/zdm_discovery/
ssh -i $TARGET_SSH_KEY opc@proddb-oda.eastus.azure.example.com "cd /tmp/zdm_discovery && chmod +x zdm_target_discovery.sh && ./zdm_target_discovery.sh"

# 3. Copy and run on ZDM server
# Note: Scripts source environment files automatically for ZDM_HOME, JAVA_HOME, etc.
scp -i $ZDM_SSH_KEY zdm_server_discovery.sh zdmuser@zdm-jumpbox.corp.example.com:/tmp/zdm_discovery/
ssh -i $ZDM_SSH_KEY zdmuser@zdm-jumpbox.corp.example.com "cd /tmp/zdm_discovery && chmod +x zdm_server_discovery.sh && ./zdm_server_discovery.sh"

# 4. Collect results to Step0/Discovery/
# Note: Scripts write to current directory, not /tmp
scp -i $SOURCE_SSH_KEY oracle@proddb01.corp.example.com:/tmp/zdm_discovery/zdm_source_discovery_*.txt ../Discovery/source/
scp -i $SOURCE_SSH_KEY oracle@proddb01.corp.example.com:/tmp/zdm_discovery/zdm_source_discovery_*.json ../Discovery/source/
scp -i $TARGET_SSH_KEY opc@proddb-oda.eastus.azure.example.com:/tmp/zdm_discovery/zdm_target_discovery_*.txt ../Discovery/target/
scp -i $TARGET_SSH_KEY opc@proddb-oda.eastus.azure.example.com:/tmp/zdm_discovery/zdm_target_discovery_*.json ../Discovery/target/
scp -i $ZDM_SSH_KEY zdmuser@zdm-jumpbox.corp.example.com:/tmp/zdm_discovery/zdm_server_discovery_*.txt ../Discovery/server/
scp -i $ZDM_SSH_KEY zdmuser@zdm-jumpbox.corp.example.com:/tmp/zdm_discovery/zdm_server_discovery_*.json ../Discovery/server/
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
- **Scripts are resilient** - they continue running even when some checks fail, ensuring you get as much discovery data as possible
- **Non-interactive SSH issue** - `.bashrc` often has guards that skip sourcing for non-interactive shells. The scripts use three approaches to handle this:
  1. Explicit environment variable overrides (highest priority) - set `ZDM_REMOTE_ZDM_HOME`, `SOURCE_REMOTE_ORACLE_HOME`, etc.
  2. Login shell execution with `bash -l -c` - forces profile sourcing
  3. Extract exports from profiles - parses export statements without running interactive guards
  4. Fallback path searches - searches common installation directories
- **If ZDM/ORACLE_HOME not detected** - use the explicit override environment variables when running the orchestration script
