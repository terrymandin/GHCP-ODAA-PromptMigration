
# Example: Generate Discovery Scripts for a Migration Project

This example demonstrates how to use Step 0 to generate fresh discovery scripts for a production Oracle database migration to Oracle Database@Azure.

## Prerequisites

Before using this example:
- Identify the source database server hostname and access credentials
- Identify the target Oracle Database@Azure hostname and access credentials
- Identify the ZDM jumpbox server hostname and access credentials
- Ensure SSH access is available between servers

---

**Note:** Only the "Project Name" is required. All other fields (such as source/target hostnames, database name, etc.) are auto-detected or optional. You may leave them blank unless you need to override the defaults.


## Example Prompt

Copy and use this prompt to generate discovery scripts:

```
@Step0-Generate-Discovery-Scripts.prompt.md

## Project Configuration
#file:prompts/Phase10-Migration/ZDM/zdm-env.md

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

> 🔑 **Before running this prompt:** Update `PROJECT_NAME` and all connection details in [zdm-env.md](zdm-env.md). The `PROJECT_NAME` value becomes the artifact directory name used in every subsequent step.

---

## Running the Scripts on the Server

After Copilot generates the scripts, run them on the ZDM server. Set the same variables from [zdm-env.md](zdm-env.md) as environment variables before executing the orchestrator:

```bash
# Source your project config (copy values from zdm-env.md)
export SOURCE_HOST="proddb01.corp.example.com"
export TARGET_HOST="proddb-oda.eastus.azure.example.com"
export ZDM_HOST="zdm-jumpbox.corp.example.com"
export SOURCE_USER="oracle"
export TARGET_USER="opc"
export ZDM_USER="azureuser"
export SOURCE_SSH_KEY="$HOME/.ssh/onprem_oracle_key"
export TARGET_SSH_KEY="$HOME/.ssh/oci_opc_key"
export ZDM_SSH_KEY="$HOME/.ssh/azure_key"
export ORACLE_USER=oracle
export ZDM_SOFTWARE_USER=zdmuser

./zdm_orchestrate_discovery.sh
```

> ⚠️ **SECURITY NOTE**: Password environment variables (`SOURCE_SYS_PASSWORD`, `TARGET_SYS_PASSWORD`, `SOURCE_TDE_WALLET_PASSWORD`) should be set at **migration runtime** on the ZDM server, NOT saved to any files in the repository. See the section below for secure password handling.

---

## Password Environment Variables (Set at Migration Runtime)

> **NEVER commit passwords to GitHub or any source control system.**

Password environment variables are required for Step 2 migration scripts, but should be set securely at runtime on the ZDM server:

### Secure Password Entry (on ZDM server before running migration)

```bash
# Prompt for passwords securely (passwords not visible while typing)
read -sp "Enter SOURCE_SYS_PASSWORD: " SOURCE_SYS_PASSWORD; echo; export SOURCE_SYS_PASSWORD
read -sp "Enter SOURCE_TDE_WALLET_PASSWORD: " SOURCE_TDE_WALLET_PASSWORD; echo; export SOURCE_TDE_WALLET_PASSWORD
read -sp "Enter TARGET_SYS_PASSWORD: " TARGET_SYS_PASSWORD; echo; export TARGET_SYS_PASSWORD
```

### Required Password Variables

| Variable | Description | Required For |
|----------|-------------|--------------|
| `SOURCE_SYS_PASSWORD` | Source Oracle SYS password | All migrations |
| `SOURCE_TDE_WALLET_PASSWORD` | Source TDE wallet password | TDE-enabled databases only |
| `TARGET_SYS_PASSWORD` | Target Oracle SYS password | All migrations |

### Generated Scripts Validate Passwords

All scripts generated in Step 2 will check that required password environment variables are set before executing any migration operations. If passwords are not set, the script will exit with an error message explaining which variables need to be set.

---

## Expected Output

The prompt will generate all Step 0 artifacts in `Artifacts/Phase10-Migration/ZDM/PRODDB/Step0/`:

**IMPORTANT:** Step 0 ONLY creates files in the `Step0/` directory. Step1/ and Step2/ folders are NOT created by this prompt.

```
Artifacts/Phase10-Migration/ZDM/PRODDB/
└── Step0/                   # ONLY this folder is created by Step 0
    ├── Scripts/
    │   ├── zdm_source_discovery.sh
    │   ├── zdm_target_discovery.sh
    │   ├── zdm_server_discovery.sh
    │   ├── zdm_orchestrate_discovery.sh
    │   └── README.md
    └── Discovery/           # Outputs collected after script execution
        ├── source/          # Source server discovery results
        ├── target/          # Target server discovery results  
        └── server/          # ZDM server discovery results
```

### Key Resilience Features

All generated scripts include:

1. **Unix Line Endings (LF only)** - Scripts use Unix-style line endings (`\n`) to ensure proper execution on Linux:
   
   > **⚠️ IMPORTANT:** If scripts fail with errors like `ssh_port_22:: command not found` or `syntax error near unexpected token`, the scripts have Windows CRLF line endings. Convert them before running:
   > ```bash
   > # Convert all scripts to Unix line endings
   > sed -i 's/\r$//' *.sh
   > # Or on Windows PowerShell before copying:
   > (Get-Content script.sh -Raw) -replace "`r`n", "`n" | Set-Content -NoNewline script.sh
   > ```

2. **Environment Variable Sourcing with Fallbacks** - Scripts use multiple approaches to ensure ZDM_HOME, ORACLE_HOME, JAVA_HOME, etc. are available even in non-interactive SSH sessions:
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

3. **Continue on Failure** - Each discovery section is wrapped in error handling:
   ```bash
   # Section runs even if previous sections failed
   discover_section "ZDM Installation" || SECTION_ERRORS=$((SECTION_ERRORS + 1))
   ```

4. **Never call `exit`-containing functions from the main body** - `show_help` and `show_config` must call `exit` so they work as CLI options, but this means they will silently terminate the entire script if called anywhere outside the argument-parsing block — even when output is suppressed with `> /dev/null 2>&1`. The script will print its startup banner and stop without error, appearing to do nothing.
   ```bash
   # WRONG — show_config contains 'exit 0', so this kills the script
   # before validate_prerequisites ever runs:
   show_config > /dev/null 2>&1
   validate_prerequisites  # never reached

   # RIGHT — only call show_config/show_help inside argument parsing:
   for arg in "$@"; do
       case "$arg" in
           -h|--help)   show_help ;;    # exits
           -c|--config) show_config ;;  # exits
           -t|--test)   TEST_ONLY=true ;;
       esac
   done
   validate_prerequisites  # reached correctly
   ```

5. **Resilient Orchestration** - The orchestration script continues even when individual server discoveries fail

5. **Artifacts Directory Output** - Results are collected to the Artifacts directory by default, not /tmp

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

# Helper function to run SQL - executes as oracle user via sudo if needed
run_sql() {
    local sql_query="$1"
    if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
        local sqlplus_cmd="$ORACLE_HOME/bin/sqlplus -s / as sysdba"
        local sql_script=$(cat <<EOSQL
SET PAGESIZE 1000
SET LINESIZE 200
SET FEEDBACK OFF
SET HEADING ON
SET ECHO OFF
$sql_query
EOSQL
)
        # Execute as oracle user - use sudo if current user is not oracle
        if [ "$(whoami)" = "oracle" ]; then
            echo "$sql_script" | $sqlplus_cmd
        else
            echo "$sql_script" | sudo -u oracle -E ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd
        fi
    else
        echo "ERROR: ORACLE_HOME or ORACLE_SID not set"
        return 1
    fi
}

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

# Script directory (where this script is located)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Calculate repository root from script location
# Script is at: Artifacts/Phase10-Migration/ZDM/PRODDB/Step0/Scripts/ (6 levels deep)
# Navigate up 6 levels: Scripts -> Step0 -> PRODDB -> ZDM -> Phase10-Migration -> Artifacts -> RepoRoot
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../../.." && pwd)"

# Output directory - absolute path based on repository root
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/Artifacts/Phase10-Migration/ZDM/PRODDB/Step0/Discovery}"

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
