# ZDM Migration Step 2: Generate Migration Artifacts

## Purpose
This prompt takes completed questionnaire responses from Step 1 and generates all required migration artifacts:
- **Runbook**: Step-by-step installation and configuration guide
- **RSP File**: ZDM response file with all parameters
- **ZDM CLI Commands**: Ready-to-execute migration commands

---

## Instructions

### Prerequisites
1. Complete `Step1-Discovery-Questionnaire.prompt.md` with all required information
2. Attach the completed questionnaire to this prompt
3. Attach all discovery script outputs from Step0

### Input Required
Provide the completed questionnaire by either:
- Attaching the saved questionnaire from `Artifacts/Phase10-Migration/ZDM/<DB_NAME>/Step1/Completed-Questionnaire-<DB_NAME>.md`
- Pasting the completed sections below

### How to Use This Prompt

```
@Step2-Generate-Migration-Artifacts.prompt.md

Generate all migration artifacts for the <DATABASE> migration to Oracle Database@Azure.

## Completed Questionnaire
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE>/Step1/Completed-Questionnaire-<DATABASE>.md

## Discovery Files (from Step0)
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE>/Step0/Discovery/source/zdm_source_discovery_<hostname>_<timestamp>.json
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE>/Step0/Discovery/target/zdm_target_discovery_<hostname>_<timestamp>.json
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE>/Step0/Discovery/server/zdm_server_discovery_<hostname>_<timestamp>.json

## Output Directory
Save all generated artifacts to: Artifacts/Phase10-Migration/ZDM/<DATABASE>/Step2/
```

**Note:** Replace `<DATABASE>`, `<hostname>`, and `<timestamp>` with actual values from your environment.

---

## Artifact Generation Request

Based on the attached/provided questionnaire responses, generate the following artifacts:

### Artifact 1: Installation Runbook
**Output Location:** `Artifacts/Phase10-Migration/ZDM/<DB_NAME>/Step2/`
**Filename:** `ZDM-Migration-Runbook-<DB_NAME>.md`

Generate a comprehensive runbook that includes:

1. **Pre-Migration Checklist**
   - All verification steps with specific values from questionnaire
   - Commands to run on each server

2. **Source Database Configuration**
   - Enable ARCHIVELOG mode (if not enabled)
   - Enable Force Logging
   - Enable Supplemental Logging
   - Configure TNS entries
   - Set up SSH keys
   - Create/verify password file

3. **Target Database Configuration**
   - Configure TNS entries
   - Set up SSH keys
   - Verify OCI connectivity
   - Prepare for Data Guard (online migration)

4. **ZDM Server Configuration**
   - Verify ZDM installation
   - Configure OCI CLI
   - Set up SSH keys
   - Create credential files
   - Test connectivity

5. **Migration Execution Steps**
   - Pre-migration evaluation
   - Migration execution
   - Monitoring commands
   - Pause/Resume procedures
   - Switchover steps

6. **Post-Migration Validation**
   - Data verification queries
   - Application connectivity tests
   - Performance validation

7. **Rollback Procedures**
   - Steps to revert if issues occur

---

### Artifact 2: RSP File
**Output Location:** User-specified migration working directory
**Filename:** `zdm_migrate_<DB_NAME>.rsp`

Generate a complete RSP file with:
- All placeholder values replaced with actual questionnaire responses
- Appropriate settings based on migration type (online/offline)
- TDE configuration (if applicable)
- Data Guard settings (for online migration)
- Backup and RMAN settings

**Output Location:** `Artifacts/Phase10-Migration/ZDM/<DB_NAME>/Step2/`
**Filename:** `zdm_migrate_<DB_NAME>.rsp`

---

### Artifact 3: ZDM CLI Commands
**Output Location:** `Artifacts/Phase10-Migration/ZDM/<DB_NAME>/Step2/`
**Filename:** `zdm_commands_<DB_NAME>.sh`

Generate a shell script containing:
- Environment variable definitions
- Evaluation command
- Migration command (with all parameters)
- Job monitoring commands
- Resume commands
- Abort command (for emergency use)

---

## Template Structures

### Runbook Template Structure

```markdown
# ZDM Migration Runbook: [DATABASE_NAME]
## Migration: On-Premise to Oracle Database@Azure

### Document Information
| Field | Value |
|-------|-------|
| Source Database | [value] |
| Target Database | [value] |
| Migration Type | [ONLINE/OFFLINE] |
| Created Date | [date] |

---

## Phase 1: Pre-Migration Verification
### 1.1 Source Database Checks
[Commands and verification steps]

### 1.2 Target Database Checks
[Commands and verification steps]

### 1.3 ZDM Server Checks
[Commands and verification steps]

### 1.4 Network Connectivity Checks
[Commands and verification steps]

---

## Phase 2: Source Database Configuration
### 2.1 Enable Archive Log Mode
[Specific commands if needed]

### 2.2 Enable Force Logging
[Commands]

### 2.3 Enable Supplemental Logging
[Commands]

### 2.4 Configure Network
[TNS entries]

### 2.5 Configure SSH
[Key setup commands]

---

## Phase 3: Target Database Configuration
[Similar structure]

---

## Phase 4: ZDM Server Configuration
[Similar structure]

---

## Phase 5: Migration Execution
### 5.1 Run Evaluation
[Command]

### 5.2 Execute Migration
[Command]

### 5.3 Monitor Progress
[Commands]

---

## Phase 6: Post-Migration
### 6.1 Validation Steps
[Verification commands and queries]

### 6.2 Switchover (Online Only)
[Commands]

---

## Phase 7: Rollback Procedures
[Emergency rollback steps]

---

## Appendix A: Troubleshooting
[Common issues and solutions]
```

---

### RSP File Template Structure

```properties
# ===========================================
# ZDM Response File
# Database: [DATABASE_NAME]
# Migration Type: [ONLINE_PHYSICAL/OFFLINE_PHYSICAL]
# Generated: [DATE]
# ===========================================

# Migration Method
MIGRATION_METHOD=[ONLINE_PHYSICAL|OFFLINE_PHYSICAL]

# Source Database Configuration
SOURCEDATABASE_CONNECTIONDETAILS_HOST=[value]
SOURCEDATABASE_CONNECTIONDETAILS_PORT=[value]
SOURCEDATABASE_CONNECTIONDETAILS_SERVICENAME=[value]
SOURCEDATABASE_ADMINPASSWORDFILE=[value]

# Target Database Configuration
TARGETDATABASE_OCID=[value]
TARGETDATABASE_CONNECTIONDETAILS_HOST=[value]
TARGETDATABASE_CONNECTIONDETAILS_PORT=[value]
TARGETDATABASE_CONNECTIONDETAILS_SERVICENAME=[value]

# OCI Authentication
OCIAUTHENTICATION_TYPE=API_KEY
OCIAUTHENTICATION_USERPRINCIPAL_TENANTID=[value]
OCIAUTHENTICATION_USERPRINCIPAL_USERID=[value]
OCIAUTHENTICATION_USERPRINCIPAL_FINGERPRINT=[value]
OCIAUTHENTICATION_USERPRINCIPAL_PRIVATEKEYFILE=[value]

# [Additional sections based on migration type]
```

---

### CLI Commands Template Structure

```bash
#!/bin/bash
# ===========================================
# ZDM CLI Commands
# Database: [DATABASE_NAME]
# Generated: [DATE]
# ===========================================

# Environment Variables
export ZDM_HOME="[value]"
export SOURCE_DB="[value]"
export SOURCE_HOST="[value]"
export TARGET_HOST="[value]"
export RSP_FILE="[path]"
export SSH_KEY="[path]"

# Evaluation Command
echo "Running ZDM Evaluation..."
$ZDM_HOME/bin/zdmcli migrate database \
  -sourcedb $SOURCE_DB \
  [additional parameters] \
  -eval

# Migration Command
echo "Starting Migration..."
$ZDM_HOME/bin/zdmcli migrate database \
  -sourcedb $SOURCE_DB \
  [all parameters]

# Monitoring Commands
# $ZDM_HOME/bin/zdmcli query job -jobid <JOB_ID>

# Resume Command (if paused)
# $ZDM_HOME/bin/zdmcli resume job -jobid <JOB_ID>
```

---

## Generation Checklist

When generating artifacts, ensure:

- [ ] All placeholder values are replaced with actual questionnaire responses
- [ ] Commands use absolute paths from questionnaire
- [ ] **Password environment variable validation is included** - Scripts must check that `SOURCE_SYS_PASSWORD`, `TARGET_SYS_PASSWORD`, and `SOURCE_TDE_WALLET_PASSWORD` (if TDE enabled) are set before executing
- [ ] Passwords are NEVER embedded in scripts or files - only referenced via environment variables
- [ ] RSP file references password files that will be created from environment variables at runtime
- [ ] RSP file matches migration type (online vs offline)
- [ ] Runbook includes rollback procedures
- [ ] CLI script has proper error handling
- [ ] All OCIDs are properly formatted
- [ ] Network ports match questionnaire values
- [ ] TDE settings included if TDE is enabled
- [ ] Data Guard settings included for online migration

---

## Password Security Requirements

> ⚠️ **SECURITY**: Generated scripts must validate password environment variables and must NEVER contain hardcoded passwords.

### Required Password Validation in Generated Scripts

All generated CLI command scripts (`zdm_commands_<DB_NAME>.sh`) must include a password validation function that runs before any migration operation:

```bash
# ===========================================
# PASSWORD ENVIRONMENT VARIABLE VALIDATION
# ===========================================

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
    # TDE_ENABLED should be set to "true" or "false" based on questionnaire
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
        printf '  export %s="<value>"\n' "${missing_vars[@]}"
        echo ""
        echo "For secure password entry, use:"
        echo '  read -sp "Enter PASSWORD: " VAR_NAME; echo; export VAR_NAME'
        echo ""
        echo "See Step0-Generate-Discovery-Scripts.prompt.md for password configuration details."
        return 1
    fi
    
    echo ""
    echo "✓ All required password environment variables are set"
    return 0
}

# Call validation before any operation
validate_password_environment || exit 1
```

### Password File Creation at Runtime

The runbook and CLI scripts should include instructions to create temporary password files from environment variables at migration runtime:

```bash
# Create password files from environment variables (run on ZDM server)
create_password_files() {
    local creds_dir="${HOME}/creds"
    
    # Validate environment variables first
    validate_password_environment || return 1
    
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
    
    echo "Password files created in $creds_dir"
}

# Clean up password files after migration
cleanup_password_files() {
    local creds_dir="${HOME}/creds"
    
    if [ -d "$creds_dir" ]; then
        rm -f "$creds_dir"/*.txt
        echo "Password files cleaned up"
    fi
}
```

---

## Output Confirmation

After generation, confirm all files are saved to the user-specified migration working directory:

1. **Runbook**: `ZDM-Migration-Runbook-<DB_NAME>.md`
2. **RSP file**: `zdm_migrate_<DB_NAME>.rsp`
3. **CLI commands**: `zdm_commands_<DB_NAME>.sh`

Review all generated artifacts before execution.
