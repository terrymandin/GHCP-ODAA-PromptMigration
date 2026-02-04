# Example: Generate Migration Artifacts for PRODDB (Step 3)

This example demonstrates how to use Step 3 to generate all migration artifacts (RSP file, CLI commands, and runbook) from a completed questionnaire after all issues have been resolved in Step 2.

## Prerequisites

Before using this example:
- ✅ Complete `Step0-Generate-Discovery-Scripts.prompt.md` and run discovery
- ✅ Complete `Step1-Discovery-Questionnaire.prompt.md` with all required information
- ✅ Complete `Step2-Fix-Issues.prompt.md` - all blockers must be resolved
- Have discovery output files and Issue Resolution Log available

---

## Example Prompt

Copy and use this prompt to generate migration artifacts:

```
@Step3-Generate-Migration-Artifacts.prompt.md

Generate all migration artifacts for the <DATABASE> migration to Oracle Database@Azure.

## Step1 Outputs (Questionnaire and Summary)
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE>/Step1/

## Step2 Outputs (Issue Resolution Log)
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE>/Step2/

## Discovery Files (from Step0)
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE>/Step0/Discovery/source/
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE>/Step0/Discovery/target/
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE>/Step0/Discovery/server/

## Output Directory
Save all generated artifacts to: Artifacts/Phase10-Migration/ZDM/<DATABASE>/Step3/

> **Note:** Replace `<DATABASE>` with your database name (e.g., PRODDB, HRDB, etc.).
> When referencing directories, GitHub Copilot will read all files in those directories.

## Additional Parameters (Optional Overrides)

> **Note:** Most parameters should be extracted from the attached questionnaire and discovery files.
> Only include parameters here if they need to override or supplement the discovered values.

### Migration Options (from Questionnaire Section D)
- Protection Mode: MAXIMUM_PERFORMANCE
- Transport Type: ASYNC
- Pause After: ZDM_CONFIGURE_DG_SRC
- Auto Switchover: No

### Credential Files (created at runtime from environment variables)

> ⚠️ **SECURITY**: ZDM requires password file paths in the response file (.rsp) - it cannot read 
> passwords directly from environment variables. The secure workflow is:
> 1. Set passwords as environment variables on the ZDM server (never committed to git)
> 2. Create temporary password files from environment variables just before migration
> 3. ZDM reads from these files during migration
> 4. Delete the files immediately after migration completes
>
> This approach ensures passwords are never stored in the repository while meeting ZDM's requirements.

**Required Password Environment Variables (set on ZDM server before running):**
- `SOURCE_SYS_PASSWORD` - Source Oracle SYS password
- `TARGET_SYS_PASSWORD` - Target Oracle SYS password  
- `SOURCE_TDE_WALLET_PASSWORD` - TDE wallet password (if TDE is enabled on source)

**Temporary password files (created at runtime, deleted after migration):**
- Source SYS Password: ~/creds/source_sys_password.txt
- Target SYS Password: ~/creds/target_sys_password.txt
- TDE Wallet Password: ~/creds/tde_password.txt (if TDE enabled)
```

---

## Expected Generated Artifacts

> **Note:** The values shown below are examples. The generated artifacts will use values 
> extracted from the discovery JSON files and questionnaire for your specific migration.

### 1. README: `README.md`

```markdown
# <DB_NAME> Migration to Oracle Database@Azure

## Migration Overview

> Values extracted from discovery files and questionnaire

| Field | Value | Source |
|-------|-------|--------|
| **Source Database** | `<DB_NAME>` on `<SOURCE_HOST>` | Discovery: db_name, hostname |
| **Target Environment** | Oracle Database@Azure (`<TARGET_HOST>`) | Discovery: target hostname |
| **Migration Method** | ONLINE_PHYSICAL (Minimal Downtime) | Questionnaire: Section A.1 |
| **Expected Downtime** | ~15 minutes (switchover only) | Questionnaire: Section A.2 |
| **ZDM Server** | `<ZDM_SERVER>` | Discovery: zdm hostname |

---

## Prerequisites Checklist

| # | Task | Status |
|---|------|--------|
| 1 | All Critical issues from Step 2 resolved | 🔲 |
| 2 | All OCI OCIDs populated in ~/zdm_oci_env.sh | 🔲 |
| 3 | OCI CLI configured for zdmuser | 🔲 |
| 4 | TDE wallet password available (if TDE enabled) | 🔲 |
| 5 | SSH connectivity verified | 🔲 |

---

## Generated Artifacts

| File | Description |
|------|-------------|
| README.md | This file - task checklist and quick-start guide |
| ZDM-Migration-Runbook-`<DB_NAME>`.md | Comprehensive step-by-step migration guide |
| zdm_migrate_`<DB_NAME>`.rsp | ZDM response file with migration parameters |
| zdm_commands_`<DB_NAME>`.sh | Shell script with all ZDM CLI commands |

---

## Quick Start Guide

### Step 1: Log into ZDM Server
```bash
# SSH as your admin user (extracted from discovery)
ssh <ADMIN_USER>@<ZDM_SERVER>

# Switch to zdmuser
sudo su - zdmuser
```

### Step 2: First-Time Setup (run once)
```bash
# Navigate to your cloned fork's artifacts directory
cd ~/GHCP-ODAA-PromptMigration/Artifacts/Phase10-Migration/ZDM/<DATABASE>/Step3

# Initialize environment (creates ~/creds directory and ~/zdm_oci_env.sh template)
./zdm_commands_<DB_NAME>.sh init
```

### Step 3: Configure OCI Environment
```bash
# Edit the generated OCI environment file with actual values
vi ~/zdm_oci_env.sh

# Source the OCI environment variables
source ~/zdm_oci_env.sh
```

### Step 4: Set Up Passwords
```bash
./zdm_commands_<DB_NAME>.sh create-creds
```

### Step 5: Run Evaluation (Dry Run)
```bash
./zdm_commands_<DB_NAME>.sh eval
./zdm_commands_<DB_NAME>.sh status <JOB_ID>
```

### Step 6: Execute Migration
```bash
./zdm_commands_<DB_NAME>.sh migrate
./zdm_commands_<DB_NAME>.sh status <JOB_ID>
```

### Step 7: Resume After Validation
```bash
./zdm_commands_<DB_NAME>.sh resume <JOB_ID>
```

### Step 8: Cleanup
```bash
./zdm_commands_<DB_NAME>.sh cleanup-creds
```

---

## Command Reference

| Command | Description |
|---------|-------------|
| `./zdm_commands_<DB_NAME>.sh setup` | Interactive password setup |
| `./zdm_commands_<DB_NAME>.sh preflight` | Run pre-flight checks |
| `./zdm_commands_<DB_NAME>.sh eval` | Run evaluation (dry run) |
| `./zdm_commands_<DB_NAME>.sh migrate` | Start actual migration |
| `./zdm_commands_<DB_NAME>.sh query <ID>` | Query job status |
| `./zdm_commands_<DB_NAME>.sh resume <ID>` | Resume paused job |
| `./zdm_commands_<DB_NAME>.sh cleanup` | Remove password files |

---

*Generated by ZDM Migration Planning - Step 3*
```

---

### 2. RSP File: `zdm_migrate_<DB_NAME>.rsp`

> **Note:** Values are extracted from discovery files. OCI identifiers use environment variable 
> placeholders (e.g., `${TARGET_TENANCY_OCID}`) that must be substituted before use.

```properties
# ===========================================
# ZDM Response File
# Database: <DB_NAME> (from discovery: db_name)
# Migration Type: ONLINE_PHYSICAL (from questionnaire)
# Generated: <DATE>
# ===========================================
#
# Values extracted from:
# - Source Discovery: <source discovery JSON file>
# - Target Discovery: <target discovery JSON file>
# - ZDM Server Discovery: <server discovery JSON file>
# - Migration Questionnaire: <questionnaire file>
#
# ===========================================

# Migration Type (from Questionnaire Section A.1)
MIGRATION_METHOD=ONLINE_PHYSICAL

# ===========================================
# SOURCE DATABASE CONFIGURATION
# Values from: source discovery JSON
# ===========================================
SOURCEDATABASE_CONNECTIONDETAILS_HOST=<SOURCE_HOST>
SOURCEDATABASE_CONNECTIONDETAILS_PORT=1521
SOURCEDATABASE_CONNECTIONDETAILS_SERVICENAME=<db_name_lower>
SOURCEDATABASE_ADMINPASSWORDFILE=/home/zdmuser/creds/source_sys_password.txt
SOURCEDATABASE_ORACLEHOME=<SOURCE_ORACLE_HOME>

# ===========================================
# TARGET DATABASE CONFIGURATION
# Values from: target discovery JSON
# ===========================================
TARGETDATABASE_OCID=${TARGET_DATABASE_OCID}
TARGETDATABASE_CONNECTIONDETAILS_HOST=<TARGET_HOST>
TARGETDATABASE_CONNECTIONDETAILS_PORT=1521
TARGETDATABASE_ADMINPASSWORDFILE=/home/zdmuser/creds/target_sys_password.txt
TARGETDATABASE_ORACLEHOME=<TARGET_ORACLE_HOME>

# ===========================================
# OCI AUTHENTICATION
# Values from environment variables (set in ~/zdm_oci_env.sh)
# ===========================================
OCIAUTHENTICATION_TYPE=API_KEY
OCIAUTHENTICATION_USERPRINCIPAL_TENANTID=${TARGET_TENANCY_OCID}
OCIAUTHENTICATION_USERPRINCIPAL_USERID=${TARGET_USER_OCID}
OCIAUTHENTICATION_USERPRINCIPAL_FINGERPRINT=${TARGET_FINGERPRINT}
OCIAUTHENTICATION_USERPRINCIPAL_PRIVATEKEYFILE=/home/zdmuser/.oci/oci_api_key.pem

# ===========================================
# DATA GUARD CONFIGURATION
# Values from Questionnaire Section D.1
# ===========================================
DATAGUARDCONFIGURATION_CREATESTANDBY=TRUE
DATAGUARDCONFIGURATION_PROTECTIONMODE=MAXIMUM_PERFORMANCE
DATAGUARDCONFIGURATION_TRANSPORTTYPE=ASYNC

# ===========================================
# TDE CONFIGURATION
# Values from: source discovery (if TDE wallet detected)
# ===========================================
TDE_ENABLED=TRUE
TDESETTINGS_SOURCEWALLET=<TDE_WALLET_LOCATION>
TDESETTINGS_TDEPASSWORDFILE=/home/zdmuser/creds/tde_password.txt

# ===========================================
# PAUSE CONFIGURATION
# Value from Questionnaire Section D.3
# ===========================================
PAUSEAFTER=ZDM_CONFIGURE_DG_SRC

# ===========================================
# POST-MIGRATION ACTIONS
# Values from Questionnaire Section D.2
# ===========================================
POSTMIGRATIONACTIONS_SWITCHOVER=FALSE
POSTMIGRATIONACTIONS_DELETEBACKUP=FALSE
```

---

### 3. CLI Commands Script: `zdm_commands_<DB_NAME>.sh`

> **Note:** All configuration values are extracted from discovery files and questionnaire.
> Variable names use `ZDM_MIG_` prefix to avoid conflicts with user environment variables.

```bash
#!/bin/bash
# ===========================================
# ZDM CLI Commands for <DB_NAME> Migration
# Migration Type: Online Physical
# Generated: <DATE>
# ===========================================
#
# Configuration values extracted from:
# - Source: <source discovery JSON>
# - Target: <target discovery JSON>
# - ZDM Server: <server discovery JSON>
# - Questionnaire: <questionnaire file>
#
# ===========================================

# -------------------------------------------
# MIGRATION CONFIGURATION VARIABLES
# NOTE: These use ZDM_MIG_ prefix to avoid conflicts with
# user environment variables from Step 0 discovery scripts
# -------------------------------------------
export ZDM_HOME="<ZDM_HOME>"  # From ZDM server discovery

# Source Database Configuration (from source discovery)
export ZDM_MIG_SOURCE_DB="<DB_NAME>"
export ZDM_MIG_SOURCE_DB_UNIQUE_NAME="<db_unique_name>"
export ZDM_MIG_SOURCE_HOST="<SOURCE_HOST>"
export ZDM_MIG_SOURCE_PORT="1521"
export ZDM_MIG_SOURCE_ORACLE_HOME="<SOURCE_ORACLE_HOME>"
export ZDM_MIG_SOURCE_SSH_USER="oracle"

# Target Database Configuration (from target discovery)
export ZDM_MIG_TARGET_HOST="<TARGET_HOST>"
export ZDM_MIG_TARGET_PORT="1521"
export ZDM_MIG_TARGET_ORACLE_HOME="<TARGET_ORACLE_HOME>"
export ZDM_MIG_TARGET_SSH_USER="opc"  # From questionnaire

# TDE Configuration (from source discovery - if TDE wallet detected)
export TDE_ENABLED="true"
export TDE_WALLET_LOCATION="<TDE_WALLET_LOCATION>"

# ===========================================
# PASSWORD ENVIRONMENT VARIABLE VALIDATION
# ===========================================
# This script requires password environment variables to be set.
# NEVER hardcode passwords in this script.

validate_password_environment() {
    local missing_vars=()
    local errors=0
    
    echo "Validating required password environment variables..."
    
    # Check SOURCE_SYS_PASSWORD
    if [ -z "${SOURCE_SYS_PASSWORD:-}" ]; then
        missing_vars+=("SOURCE_SYS_PASSWORD")
        ((errors++))
    else
        echo "  ✓ SOURCE_SYS_PASSWORD is set"
    fi
    
    # Check TARGET_SYS_PASSWORD
    if [ -z "${TARGET_SYS_PASSWORD:-}" ]; then
        missing_vars+=("TARGET_SYS_PASSWORD")
        ((errors++))
    else
        echo "  ✓ TARGET_SYS_PASSWORD is set"
    fi
    
    # Check SOURCE_TDE_WALLET_PASSWORD (only if TDE is enabled)
    if [ "${TDE_ENABLED:-false}" = "true" ]; then
        if [ -z "${SOURCE_TDE_WALLET_PASSWORD:-}" ]; then
            missing_vars+=("SOURCE_TDE_WALLET_PASSWORD")
            ((errors++))
        else
            echo "  ✓ SOURCE_TDE_WALLET_PASSWORD is set"
        fi
    fi
    
    if [ $errors -gt 0 ]; then
        echo ""
        echo "ERROR: The following required password environment variables are not set:"
        printf '  - %s\n' "${missing_vars[@]}"
        echo ""
        echo "Please set these variables before running the migration script:"
        echo ""
        echo "  # Secure password entry (passwords not visible while typing):"
        printf '  read -sp "Enter %s: " %s; echo; export %s\n' "${missing_vars[@]}" "${missing_vars[@]}" "${missing_vars[@]}"
        echo ""
        echo "See Step0-Generate-Discovery-Scripts.prompt.md for password configuration details."
        return 1
    fi
    
    echo ""
    echo "✓ All required password environment variables are set"
    return 0
}

# Create password files from environment variables
create_password_files() {
    local creds_dir="${HOME}/creds"
    
    echo "Creating password files from environment variables..."
    
    # Create credentials directory
    mkdir -p "$creds_dir"
    chmod 700 "$creds_dir"
    
    # Create password files from environment variables
    echo "$SOURCE_SYS_PASSWORD" > "$creds_dir/source_sys_password.txt"
    echo "$TARGET_SYS_PASSWORD" > "$creds_dir/target_sys_password.txt"
    
    if [ "${TDE_ENABLED:-false}" = "true" ]; then
        echo "$SOURCE_TDE_WALLET_PASSWORD" > "$creds_dir/tde_password.txt"
    fi
    
    # Secure the files
    chmod 600 "$creds_dir"/*.txt
    
    echo "  ✓ Password files created in $creds_dir"
}

# Clean up password files after migration
cleanup_password_files() {
    local creds_dir="${HOME}/creds"
    
    if [ -d "$creds_dir" ]; then
        rm -f "$creds_dir"/*.txt
        echo "  ✓ Password files cleaned up"
    fi
}

# ===========================================
# ENVIRONMENT CONFIGURATION
# ===========================================

export ZDM_HOME="<ZDM_HOME>"
export PATH=$ZDM_HOME/bin:$PATH

# Source Database (from source discovery)
export SOURCE_DB="<DB_NAME>_PRIMARY"
export SOURCE_HOST="<SOURCE_HOST>"
export SOURCE_USER="oracle"

# Target Database (Oracle Database@Azure)
export TARGET_HOST="<TARGET_HOST>"
export TARGET_USER="oracle"
export TARGET_HOME="<TARGET_ORACLE_HOME>"

# Authentication
export SSH_KEY="/home/zdmuser/.ssh/zdm_migration_key"
export RSP_FILE="/home/zdmuser/migrations/<DATABASE>/zdm_migrate_<DB_NAME>.rsp"

# OCI (from environment variables in ~/zdm_oci_env.sh)
export OCI_BACKUP_USER="${TARGET_USER_OCID}"

# ===========================================
# HELPER FUNCTIONS
# ===========================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

check_zdm_service() {
    log "Checking ZDM service status..."
    $ZDM_HOME/bin/zdmservice status
    if [ $? -ne 0 ]; then
        log "ERROR: ZDM service is not running"
        log "Start with: $ZDM_HOME/bin/zdmservice start"
        return 1
    fi
    log "ZDM service is running"
    return 0
}

# ===========================================
# 1. PRE-MIGRATION EVALUATION
# ===========================================

run_evaluation() {
    log "Starting ZDM Migration Evaluation for <DB_NAME>..."
    
    $ZDM_HOME/bin/zdmcli migrate database \
        -sourcedb $SOURCE_DB \
        -sourcenode $SOURCE_HOST \
        -srcauth zdmauth \
        -srcarg1 user:$SOURCE_USER \
        -srcarg2 identity_file:$SSH_KEY \
        -srcarg3 sudo_location:/usr/bin/sudo \
        -targetnode $TARGET_HOST \
        -tgtauth zdmauth \
        -tgtarg1 user:$TARGET_USER \
        -tgtarg2 identity_file:$SSH_KEY \
        -tgtarg3 sudo_location:/usr/bin/sudo \
        -rsp $RSP_FILE \
        -eval
    
    if [ $? -eq 0 ]; then
        log "Evaluation completed successfully"
    else
        log "ERROR: Evaluation failed - review output above"
        return 1
    fi
}

# ===========================================
# 2. EXECUTE ONLINE PHYSICAL MIGRATION
# ===========================================

run_migration() {
    log "Starting Online Physical Migration for <DB_NAME>..."
    log "This will configure Data Guard between source and target"
    log "Migration will PAUSE after ZDM_CONFIGURE_DG_SRC phase"
    
    $ZDM_HOME/bin/zdmcli migrate database \
        -sourcedb $SOURCE_DB \
        -sourcenode $SOURCE_HOST \
        -srcauth zdmauth \
        -srcarg1 user:$SOURCE_USER \
        -srcarg2 identity_file:$SSH_KEY \
        -srcarg3 sudo_location:/usr/bin/sudo \
        -targetnode $TARGET_HOST \
        -targethome $TARGET_HOME \
        -tgtauth zdmauth \
        -tgtarg1 user:$TARGET_USER \
        -tgtarg2 identity_file:$SSH_KEY \
        -tgtarg3 sudo_location:/usr/bin/sudo \
        -backupuser $OCI_BACKUP_USER \
        -rsp $RSP_FILE \
        -pauseafter ZDM_CONFIGURE_DG_SRC
    
    log "Migration job submitted. Use query_job to check status."
}

# ===========================================
# 3. JOB MANAGEMENT
# ===========================================

query_job() {
    local JOB_ID=$1
    if [ -z "$JOB_ID" ]; then
        log "Usage: query_job <JOB_ID>"
        log "To list all jobs: list_all_jobs"
        return 1
    fi
    $ZDM_HOME/bin/zdmcli query job -jobid $JOB_ID
}

query_job_details() {
    local JOB_ID=$1
    if [ -z "$JOB_ID" ]; then
        log "Usage: query_job_details <JOB_ID>"
        return 1
    fi
    $ZDM_HOME/bin/zdmcli query job -jobid $JOB_ID -details
}

list_all_jobs() {
    log "Listing all ZDM migration jobs..."
    $ZDM_HOME/bin/zdmcli query job -all
}

resume_job() {
    local JOB_ID=$1
    if [ -z "$JOB_ID" ]; then
        log "Usage: resume_job <JOB_ID>"
        return 1
    fi
    log "Resuming migration job $JOB_ID..."
    $ZDM_HOME/bin/zdmcli resume job -jobid $JOB_ID
}

abort_job() {
    local JOB_ID=$1
    if [ -z "$JOB_ID" ]; then
        log "Usage: abort_job <JOB_ID>"
        return 1
    fi
    log "WARNING: About to abort job $JOB_ID"
    read -p "Type 'yes' to confirm: " confirm
    if [ "$confirm" == "yes" ]; then
        $ZDM_HOME/bin/zdmcli abort job -jobid $JOB_ID
        log "Job $JOB_ID aborted"
    else
        log "Abort cancelled"
    fi
}

watch_job() {
    local JOB_ID=$1
    if [ -z "$JOB_ID" ]; then
        log "Usage: watch_job <JOB_ID>"
        return 1
    fi
    log "Monitoring job $JOB_ID (Ctrl+C to stop)..."
    while true; do
        clear
        echo "=== ZDM Job Monitor: <DB_NAME> Migration ==="
        echo "Job ID: $JOB_ID"
        echo "Time: $(date)"
        echo ""
        $ZDM_HOME/bin/zdmcli query job -jobid $JOB_ID
        echo ""
        echo "Refreshing in 30 seconds... (Ctrl+C to exit)"
        sleep 30
    done
}

# ===========================================
# USAGE
# ===========================================

show_usage() {
    cat << EOF

<DB_NAME> Migration Commands
=========================

Step 1: Source the script
  source zdm_commands_<DB_NAME>.sh

Step 2: Verify ZDM service
  check_zdm_service

Step 3: Run evaluation
  run_evaluation

Step 4: Execute migration
  run_migration

Step 5: Monitor and manage
  list_all_jobs
  query_job <JOB_ID>
  query_job_details <JOB_ID>
  watch_job <JOB_ID>
  resume_job <JOB_ID>
  abort_job <JOB_ID>

EOF
}

# Display usage when sourced
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
    log "<DB_NAME> migration commands loaded. Type 'show_usage' for help."
else
    show_usage
fi
```

---

### 4. Migration Runbook: `ZDM-Migration-Runbook-<DB_NAME>.md`

The runbook will be a comprehensive document including:

```markdown
# ZDM Migration Runbook: <DB_NAME>
## Migration: On-Premise to Oracle Database@Azure

### Document Information
| Field | Value |
|-------|-------|
| Source Database | `<DB_NAME>` (`<SOURCE_HOST>`) |
| Target Database | `<DB_NAME>_AZURE` (`<TARGET_HOST>`) |
| Migration Type | Online Physical (Data Guard) |
| Database Size | (from discovery) |
| Created Date | (generated) |
| Created By | Generated via ZDM Step 3 Prompt |

---

## Phase 1: Pre-Migration Verification

### 1.1 Source Database Verification

# Connect as SYSDBA
sqlplus / as sysdba

-- Verify database identification
SELECT name, db_unique_name, database_role, open_mode FROM v$database;
-- Expected: <DB_NAME>, <DB_UNIQUE_NAME>, PRIMARY, READ WRITE

-- Verify archive log mode
SELECT log_mode FROM v$database;
-- Expected: ARCHIVELOG

-- Verify force logging
SELECT force_logging FROM v$database;
-- Expected: YES

-- Verify supplemental logging
SELECT supplemental_log_data_min, supplemental_log_data_pk, 
       supplemental_log_data_ui FROM v$database;
-- Expected: YES, YES, YES

### 1.2 Network Connectivity Verification

# From ZDM server, test all connections
nc -zv <SOURCE_HOST> 22
nc -zv <SOURCE_HOST> 1521
nc -zv <TARGET_HOST> 22
nc -zv <TARGET_HOST> 1521
nc -zv objectstorage.<region>.oraclecloud.com 443

[... continues with all phases ...]
```

---

## Post-Generation Checklist

After artifacts are generated:

### 1. Commit Artifacts to GitHub
```bash
# From VS Code terminal
git add Artifacts/Phase10-Migration/ZDM/<DATABASE>/Step3/
git commit -m "Add Step3 migration artifacts for <DB_NAME>"
git push
```

### 2. Log into ZDM Server and Pull Changes
```bash
# SSH as admin user (from discovery)
ssh <ADMIN_USER>@<ZDM_SERVER>

# Switch to zdmuser
sudo su - zdmuser

# Navigate to your fork clone and pull changes
cd /home/zdmuser/GHCP-ODAA-PromptMigration
git pull
```

### 3. Run First-Time Setup
```bash
# Navigate to Step3 artifacts
cd Artifacts/Phase10-Migration/ZDM/<DATABASE>/Step3

# Make script executable
chmod +x zdm_commands_<DB_NAME>.sh

# Initialize environment (creates ~/creds directory and ~/zdm_oci_env.sh template)
./zdm_commands_<DB_NAME>.sh init
```

### 4. Configure OCI Environment Variables
```bash
# Edit the generated OCI environment file with actual OCID values
vi ~/zdm_oci_env.sh

# The file will look like:
# export TARGET_TENANCY_OCID="ocid1.tenancy.oc1..____________________"
# export TARGET_USER_OCID="ocid1.user.oc1..____________________"
# ... etc.

# Source the OCI environment variables
source ~/zdm_oci_env.sh
```

### 5. Set Password Environment Variables (at runtime)

> ⚠️ **SECURITY**: Set passwords securely at runtime. Never save passwords to files in the repository.

```bash
# On ZDM server as zdmuser - use secure password entry
read -sp "Enter SOURCE_SYS_PASSWORD: " SOURCE_SYS_PASSWORD; echo; export SOURCE_SYS_PASSWORD
read -sp "Enter TARGET_SYS_PASSWORD: " TARGET_SYS_PASSWORD; echo; export TARGET_SYS_PASSWORD
read -sp "Enter SOURCE_TDE_WALLET_PASSWORD: " SOURCE_TDE_WALLET_PASSWORD; echo; export SOURCE_TDE_WALLET_PASSWORD
```

### 6. Create Password Files and Run Migration
```bash
# Create password files from environment variables
./zdm_commands_<DB_NAME>.sh create-creds

# Run preflight checks
./zdm_commands_<DB_NAME>.sh preflight

# Run evaluation (dry run)
./zdm_commands_<DB_NAME>.sh eval

# After migration is complete, clean up password files
./zdm_commands_<DB_NAME>.sh cleanup-creds
```

### 7. Estimated Timeline
| Phase | Duration |
|-------|----------|
| Initial Backup & Transfer | (depends on database size and network bandwidth) |
| Restore on Target | (depends on database size) |
| Data Guard Sync | (depends on lag) |
| Switchover | 10-15 minutes |
| **Total** | (estimate based on discovery) |

---

## Tips

1. **Review all artifacts** before running on ZDM server
2. **Run `./zdm_commands_<DB_NAME>.sh init`** on first use to set up the environment
3. **Edit `~/zdm_oci_env.sh`** with actual OCID values from OCI Console
4. **Source `~/zdm_oci_env.sh`** before every session
5. **Set password environment variables** on ZDM server at runtime - never save passwords in the repository
4. **Password files are created automatically** by the `create_password_files` function from environment variables
5. **Clean up password files** after migration using `cleanup_password_files`
6. **Follow the runbook** step by step - don't skip verification steps
7. **Monitor the job** continuously during migration
