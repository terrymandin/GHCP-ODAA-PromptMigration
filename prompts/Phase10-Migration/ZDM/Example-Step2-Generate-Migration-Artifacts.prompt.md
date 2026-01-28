# Example: Generate Migration Artifacts for PRODDB

This example demonstrates how to use Step 2 to generate all migration artifacts (RSP file, CLI commands, and runbook) from a completed questionnaire.

## Prerequisites

Before using this example:
- Complete `Step1-Discovery-Questionnaire.prompt.md` with all required information
- Have discovery output files available
- Determine output directory for generated artifacts

---

## Example Prompt

Copy and use this prompt to generate migration artifacts:

```
@Step2-Generate-Migration-Artifacts.prompt.md

Generate all migration artifacts for the PRODDB migration to Oracle Database@Azure.

## Completed Questionnaire
#file:C:\Migrations\PRODDB\Questionnaire\Step1-Completed-PRODDB.md

## Discovery Files
#file:C:\Migrations\PRODDB\Discovery\zdm_source_discovery_proddb01_20260128_140532.json
#file:C:\Migrations\PRODDB\Discovery\zdm_target_discovery_proddb-oda_20260128_141022.json
#file:C:\Migrations\PRODDB\Discovery\zdm_server_discovery_zdm-jumpbox_20260128_141545.json

## Output Directory
Save all generated artifacts to: C:\Migrations\PRODDB\Artifacts\

## Key Parameters from Questionnaire

### Migration Type
- Online Physical Migration (Data Guard)
- Maximum 15 minutes downtime during switchover

### Source Database
- Database Name: PRODDB
- Unique Name: PRODDB_PRIMARY
- Host: proddb01.corp.example.com
- Port: 1521
- Service: PRODDB.corp.example.com
- Oracle Home: /u01/app/oracle/product/19.21.0/dbhome_1
- OS User: oracle
- TDE Enabled: Yes
- TDE Wallet: /u01/app/oracle/admin/PRODDB/wallet/tde

### Target Database (Oracle Database@Azure)
- Database Name: PRODDB
- Unique Name: PRODDB_AZURE
- Database OCID: ocid1.database.oc1.iad..aaaaaaaaproddbazure67890
- Host: proddb-oda.eastus.azure.example.com
- Port: 1521
- Service: PRODDB_AZURE.eastus.azure.example.com
- Oracle Home: /u02/app/oracle/product/19.0.0.0/dbhome_1
- OS User: oracle

### ZDM Server
- ZDM Home: /opt/oracle/zdm21c
- Host: zdm-jumpbox.corp.example.com
- OS User: zdmuser
- SSH Key: /home/zdmuser/.ssh/zdm_migration_key

### OCI Configuration
- Tenancy OCID: ocid1.tenancy.oc1..aaaaaaaabcdefghijklmnopqrstuvwxyz123456789
- User OCID: ocid1.user.oc1..aaaaaaaaxyz987654321abcdefghijklmnopqrstuv
- Region: us-ashburn-1
- API Key Path: /home/zdmuser/.oci/oci_api_key.pem
- Fingerprint: aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99

### Object Storage
- Namespace: examplecorp
- Bucket: zdm-proddb-migration
- Region: us-ashburn-1

### Migration Options
- Protection Mode: MAXIMUM_PERFORMANCE
- Transport Type: ASYNC
- RMAN Channels: 8
- Compression: MEDIUM
- Encryption: AES256
- Pause After: ZDM_CONFIGURE_DG_SRC
- Auto Switchover: No

### Credential Files (to be created)
- Source SYS Password: /home/zdmuser/creds/source_sys_password.txt
- Target SYS Password: /home/zdmuser/creds/target_sys_password.txt
- TDE Wallet Password: /home/zdmuser/creds/tde_password.txt
```

---

## Expected Generated Artifacts

### 1. RSP File: `zdm_migrate_PRODDB.rsp`

```properties
# ===========================================
# ZDM Response File
# Database: PRODDB
# Migration Type: ONLINE_PHYSICAL
# Generated: 2026-01-28
# ===========================================

# Migration Type
MIGRATION_METHOD=ONLINE_PHYSICAL

# ===========================================
# SOURCE DATABASE CONFIGURATION
# ===========================================
SOURCEDATABASE_CONNECTIONDETAILS_HOST=proddb01.corp.example.com
SOURCEDATABASE_CONNECTIONDETAILS_PORT=1521
SOURCEDATABASE_CONNECTIONDETAILS_SERVICENAME=PRODDB.corp.example.com
SOURCEDATABASE_ADMINPASSWORDFILE=/home/zdmuser/creds/source_sys_password.txt
SOURCEDATABASE_SABORACLEUSER=oracle

# ===========================================
# TARGET DATABASE CONFIGURATION
# Oracle Database@Azure
# ===========================================
TARGETDATABASE_OCID=ocid1.database.oc1.iad..aaaaaaaaproddbazure67890
TARGETDATABASE_CONNECTIONDETAILS_HOST=proddb-oda.eastus.azure.example.com
TARGETDATABASE_CONNECTIONDETAILS_PORT=1521
TARGETDATABASE_CONNECTIONDETAILS_SERVICENAME=PRODDB_AZURE.eastus.azure.example.com
TARGETDATABASE_ADMINPASSWORDFILE=/home/zdmuser/creds/target_sys_password.txt

# ===========================================
# OCI AUTHENTICATION
# ===========================================
OCIAUTHENTICATION_TYPE=API_KEY
OCIAUTHENTICATION_USERPRINCIPAL_TENANTID=ocid1.tenancy.oc1..aaaaaaaabcdefghijklmnopqrstuvwxyz123456789
OCIAUTHENTICATION_USERPRINCIPAL_USERID=ocid1.user.oc1..aaaaaaaaxyz987654321abcdefghijklmnopqrstuv
OCIAUTHENTICATION_USERPRINCIPAL_FINGERPRINT=aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99
OCIAUTHENTICATION_USERPRINCIPAL_PRIVATEKEYFILE=/home/zdmuser/.oci/oci_api_key.pem

# ===========================================
# DATA GUARD CONFIGURATION
# ===========================================
DATAGUARDCONFIGURATION_CREATESTANDBY=TRUE
DATAGUARDCONFIGURATION_PROTECTIONMODE=MAXIMUM_PERFORMANCE
DATAGUARDCONFIGURATION_TRANSPORTTYPE=ASYNC

# ===========================================
# BACKUP / OBJECT STORAGE CONFIGURATION
# ===========================================
BACKUPOBJECTSTORESETTINGS_OBJECTSTORAGENAMESPACE=examplecorp
BACKUPOBJECTSTORESETTINGS_BUCKETNAME=zdm-proddb-migration
BACKUPOBJECTSTORESETTINGS_REGION=us-ashburn-1

# ===========================================
# RMAN CONFIGURATION
# ===========================================
RMANSETTINGS_CHANNELS=8
RMANSETTINGS_COMPRESSION=MEDIUM
RMANSETTINGS_ENCRYPTIONALGORITHM=AES256

# ===========================================
# TDE CONFIGURATION
# ===========================================
TDESETTINGS_SOURCEWALLET=/u01/app/oracle/admin/PRODDB/wallet/tde
TDESETTINGS_TDEPASSWORDFILE=/home/zdmuser/creds/tde_password.txt

# ===========================================
# ADVISOR SETTINGS
# ===========================================
ADVISORSETTINGS_INCLUDEPERFORMANCEDATA=TRUE

# ===========================================
# POST-MIGRATION ACTIONS
# ===========================================
POSTMIGRATIONACTIONS_SWITCHOVER=FALSE
POSTMIGRATIONACTIONS_DELETEBACKUP=FALSE
```

---

### 2. CLI Commands Script: `zdm_commands_PRODDB.sh`

```bash
#!/bin/bash
# ===========================================
# ZDM CLI Commands for PRODDB Migration
# Migration Type: Online Physical
# Generated: 2026-01-28
# ===========================================

# ===========================================
# ENVIRONMENT CONFIGURATION
# ===========================================

export ZDM_HOME="/opt/oracle/zdm21c"
export PATH=$ZDM_HOME/bin:$PATH

# Source Database
export SOURCE_DB="PRODDB_PRIMARY"
export SOURCE_HOST="proddb01.corp.example.com"
export SOURCE_USER="oracle"

# Target Database (Oracle Database@Azure)
export TARGET_HOST="proddb-oda.eastus.azure.example.com"
export TARGET_USER="oracle"
export TARGET_HOME="/u02/app/oracle/product/19.0.0.0/dbhome_1"

# Authentication
export SSH_KEY="/home/zdmuser/.ssh/zdm_migration_key"
export RSP_FILE="/home/zdmuser/migrations/PRODDB/zdm_migrate_PRODDB.rsp"

# OCI
export OCI_BACKUP_USER="ocid1.user.oc1..aaaaaaaaxyz987654321abcdefghijklmnopqrstuv"

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
    log "Starting ZDM Migration Evaluation for PRODDB..."
    
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
    log "Starting Online Physical Migration for PRODDB..."
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
        echo "=== ZDM Job Monitor: PRODDB Migration ==="
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

PRODDB Migration Commands
=========================

Step 1: Source the script
  source zdm_commands_PRODDB.sh

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
    log "PRODDB migration commands loaded. Type 'show_usage' for help."
else
    show_usage
fi
```

---

### 3. Migration Runbook: `ZDM-Migration-Runbook-PRODDB.md`

The runbook will be a comprehensive document including:

```markdown
# ZDM Migration Runbook: PRODDB
## Migration: On-Premise to Oracle Database@Azure

### Document Information
| Field | Value |
|-------|-------|
| Source Database | PRODDB_PRIMARY (proddb01.corp.example.com) |
| Target Database | PRODDB_AZURE (proddb-oda.eastus.azure.example.com) |
| Migration Type | Online Physical (Data Guard) |
| Database Size | 2,450 GB |
| Created Date | 2026-01-28 |
| Created By | Generated via ZDM Step 2 Prompt |

---

## Phase 1: Pre-Migration Verification

### 1.1 Source Database Verification

# Connect as SYSDBA
sqlplus / as sysdba

-- Verify database identification
SELECT name, db_unique_name, database_role, open_mode FROM v$database;
-- Expected: PRODDB, PRODDB_PRIMARY, PRIMARY, READ WRITE

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
nc -zv proddb01.corp.example.com 22
nc -zv proddb01.corp.example.com 1521
nc -zv proddb-oda.eastus.azure.example.com 22
nc -zv proddb-oda.eastus.azure.example.com 1521
nc -zv objectstorage.us-ashburn-1.oraclecloud.com 443

[... continues with all phases ...]
```

---

## Post-Generation Checklist

After artifacts are generated:

### 1. Create Password Files
```bash
# On ZDM server as zdmuser
mkdir -p /home/zdmuser/creds
chmod 700 /home/zdmuser/creds

# Create password files (replace with actual passwords)
echo '<SOURCE_SYS_PASSWORD>' > /home/zdmuser/creds/source_sys_password.txt
echo '<TARGET_SYS_PASSWORD>' > /home/zdmuser/creds/target_sys_password.txt
echo '<TDE_WALLET_PASSWORD>' > /home/zdmuser/creds/tde_password.txt

# Secure the files
chmod 600 /home/zdmuser/creds/*.txt
```

### 2. Copy Artifacts to ZDM Server
```bash
scp C:\Migrations\PRODDB\Artifacts\* zdmuser@zdm-jumpbox.corp.example.com:/home/zdmuser/migrations/PRODDB/
```

### 3. Quick Start Commands
```bash
# On ZDM server
cd /home/zdmuser/migrations/PRODDB
source zdm_commands_PRODDB.sh
check_zdm_service
run_evaluation
```

### 4. Estimated Timeline
| Phase | Duration |
|-------|----------|
| Initial Backup & Transfer | 6-8 hours (2.45TB @ 1Gbps) |
| Restore on Target | 3-4 hours |
| Data Guard Sync | 30-60 minutes (catch-up) |
| Switchover | 10-15 minutes |
| **Total** | **~12-14 hours** |

---

## Tips

1. **Review all artifacts** before copying to ZDM server
2. **Test RSP file syntax** with a dry-run evaluation first
3. **Create password files** on ZDM server, not on Windows
4. **Follow the runbook** step by step - don't skip verification steps
5. **Monitor the job** continuously during migration
