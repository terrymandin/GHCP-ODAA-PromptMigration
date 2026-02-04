# ZDM Migration Runbook: PRODDB
## Migration: On-Premise to Oracle Database@Azure

---

### Document Information

| Field | Value |
|-------|-------|
| **Source Database** | PRODDB (PRODDB_PRIMARY) on proddb01.corp.example.com |
| **Target Database** | PRODDB_AZURE on proddb-oda.eastus.azure.example.com |
| **Migration Type** | ONLINE_PHYSICAL (Data Guard) |
| **Maximum Downtime** | 15 minutes |
| **Created Date** | 2026-02-04 |
| **ZDM Home** | /opt/oracle/zdm21c |
| **ZDM Server** | zdm-jumpbox.corp.example.com |

---

## Table of Contents

1. [Phase 1: Pre-Migration Verification](#phase-1-pre-migration-verification)
2. [Phase 2: Source Database Configuration](#phase-2-source-database-configuration)
3. [Phase 3: Target Database Configuration](#phase-3-target-database-configuration)
4. [Phase 4: ZDM Server Configuration](#phase-4-zdm-server-configuration)
5. [Phase 5: Migration Execution](#phase-5-migration-execution)
6. [Phase 6: Post-Migration Validation](#phase-6-post-migration-validation)
7. [Phase 7: Rollback Procedures](#phase-7-rollback-procedures)
8. [Appendix A: Troubleshooting](#appendix-a-troubleshooting)

---

## Phase 1: Pre-Migration Verification

### 1.1 Source Database Checks

Connect to the source database server and verify the prerequisites:

```bash
# SSH to source server
ssh oracle@proddb01.corp.example.com
```

#### 1.1.1 Verify Database Status

```sql
-- Connect as SYS
sqlplus / as sysdba

-- Check database status
SELECT NAME, OPEN_MODE, LOG_MODE, FORCE_LOGGING, DATABASE_ROLE 
FROM V$DATABASE;

-- Expected output:
-- NAME     OPEN_MODE            LOG_MODE     FORCE_LOGGING  DATABASE_ROLE
-- -------- -------------------- ------------ -------------- ---------------
-- PRODDB   READ WRITE           ARCHIVELOG   YES            PRIMARY
```

#### 1.1.2 Verify Supplemental Logging

```sql
-- Check supplemental logging
SELECT SUPPLEMENTAL_LOG_DATA_MIN, SUPPLEMENTAL_LOG_DATA_PK 
FROM V$DATABASE;

-- Expected: Both should be YES
```

#### 1.1.3 Verify TDE Configuration

```sql
-- Check TDE wallet status
SELECT WRL_TYPE, STATUS, WALLET_TYPE 
FROM V$ENCRYPTION_WALLET;

-- Expected: STATUS = OPEN

-- Check TDE wallet location
SELECT * FROM V$ENCRYPTION_WALLET;
```

#### 1.1.4 Verify Password File

```bash
# Check password file exists
ls -la /u01/app/oracle/product/19.21.0/dbhome_1/dbs/orapwPRODDB

# Verify content
orapwd describe file=/u01/app/oracle/product/19.21.0/dbhome_1/dbs/orapwPRODDB
```

#### 1.1.5 Verify Database Size

```sql
-- Check database size for estimation
SELECT SUM(BYTES)/1024/1024/1024 AS SIZE_GB FROM DBA_DATA_FILES;
SELECT SUM(BYTES)/1024/1024/1024 AS SIZE_GB FROM DBA_TEMP_FILES;
```

### 1.2 Target Database Checks

Connect to the target Oracle Database@Azure environment:

```bash
# SSH to target server
ssh oracle@proddb-oda.eastus.azure.example.com
```

#### 1.2.1 Verify Oracle Home

```bash
# Set environment
export ORACLE_HOME=/u02/app/oracle/product/19.0.0.0/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH

# Verify Oracle version
sqlplus -version
```

#### 1.2.2 Verify Listener

```bash
# Check listener status
lsnrctl status

# Verify port 1521 is listening
netstat -tlnp | grep 1521
```

#### 1.2.3 Verify ASM Storage

```bash
# Check ASM disk groups (if applicable)
export ORACLE_SID=+ASM1
asmcmd lsdg

# Expected disk groups:
# +DATAC3 - for data files
# +RECOC3 - for recovery files
```

### 1.3 ZDM Server Checks

Connect to the ZDM server:

```bash
# SSH as admin user
ssh azureuser@zdm-jumpbox.corp.example.com

# Switch to zdmuser
sudo su - zdmuser
```

#### 1.3.1 Verify ZDM Installation

```bash
# Set ZDM environment
export ZDM_HOME=/opt/oracle/zdm21c
export PATH=$ZDM_HOME/bin:$PATH

# Check ZDM version
$ZDM_HOME/bin/zdmcli -version

# Verify ZDM service is running
$ZDM_HOME/bin/zdmservice status
```

#### 1.3.2 Verify OCI CLI

```bash
# Check OCI CLI version
oci --version

# Test OCI connectivity
oci os ns get
```

#### 1.3.3 Verify SSH Keys

```bash
# Check SSH key exists
ls -la /home/zdmuser/.ssh/zdm_migration_key

# Test SSH to source
ssh -i /home/zdmuser/.ssh/zdm_migration_key oracle@proddb01.corp.example.com "hostname"

# Test SSH to target
ssh -i /home/zdmuser/.ssh/zdm_migration_key oracle@proddb-oda.eastus.azure.example.com "hostname"
```

### 1.4 Network Connectivity Checks

```bash
# From ZDM server, test connectivity

# Test Oracle port to source
nc -zv proddb01.corp.example.com 1521

# Test Oracle port to target
nc -zv proddb-oda.eastus.azure.example.com 1521

# Test SSH to source
nc -zv proddb01.corp.example.com 22

# Test SSH to target
nc -zv proddb-oda.eastus.azure.example.com 22
```

---

## Phase 2: Source Database Configuration

### 2.1 Enable Archive Log Mode (If Not Already Enabled)

> **Note:** Based on discovery, ARCHIVELOG mode is already enabled. Skip this section if already configured.

```sql
-- Only if not already in ARCHIVELOG mode
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;

-- Verify
SELECT LOG_MODE FROM V$DATABASE;
```

### 2.2 Enable Force Logging

> **Note:** Based on discovery, Force Logging is already enabled.

```sql
-- Only if not already enabled
ALTER DATABASE FORCE LOGGING;

-- Verify
SELECT FORCE_LOGGING FROM V$DATABASE;
```

### 2.3 Enable Supplemental Logging

> **Note:** Based on discovery, Supplemental Logging is already configured.

```sql
-- Enable minimal supplemental logging (if not enabled)
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;

-- Enable primary key supplemental logging (if not enabled)
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (PRIMARY KEY) COLUMNS;

-- Verify
SELECT SUPPLEMENTAL_LOG_DATA_MIN, SUPPLEMENTAL_LOG_DATA_PK, SUPPLEMENTAL_LOG_DATA_UI 
FROM V$DATABASE;
```

### 2.4 Configure TNS Entries

Add target database entry to tnsnames.ora on source:

```bash
# Edit tnsnames.ora on source
vi $ORACLE_HOME/network/admin/tnsnames.ora

# Add target entry:
```

```
PRODDB_AZURE =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = proddb-oda.eastus.azure.example.com)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = PRODDB_AZURE.eastus.azure.example.com)
    )
  )
```

### 2.5 Configure SSH Keys for ZDM Access

```bash
# On source server as oracle user
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Add ZDM server's public key to authorized_keys
# Get the public key from ZDM server (/home/zdmuser/.ssh/zdm_migration_key.pub)
echo "ssh-rsa AAAAB3... zdmuser@zdm-jumpbox" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

### 2.6 Verify Password File

```bash
# Ensure password file exists and is valid
ls -la $ORACLE_HOME/dbs/orapwPRODDB

# Recreate if needed
orapwd file=$ORACLE_HOME/dbs/orapwPRODDB password=<sys_password> entries=10 force=y
```

---

## Phase 3: Target Database Configuration

### 3.1 Configure TNS Entries

Add source database entry to tnsnames.ora on target:

```bash
# Edit tnsnames.ora on target
vi $ORACLE_HOME/network/admin/tnsnames.ora

# Add source entry:
```

```
PRODDB_PRIMARY =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = proddb01.corp.example.com)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = PRODDB.corp.example.com)
    )
  )
```

### 3.2 Configure SSH Keys for ZDM Access

```bash
# On target server as oracle user
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Add ZDM server's public key to authorized_keys
echo "ssh-rsa AAAAB3... zdmuser@zdm-jumpbox" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

### 3.3 Verify OCI Connectivity (From Target)

```bash
# Test OCI CLI if installed
oci os ns get
```

### 3.4 Prepare for Data Guard Reception

```bash
# Ensure archive log destination is configured for standby
# This will be configured by ZDM, but verify space is available

# Check available space on ASM
asmcmd lsdg
```

---

## Phase 4: ZDM Server Configuration

### 4.1 Login to ZDM Server

```bash
# SSH as the admin user (azureuser)
ssh azureuser@zdm-jumpbox.corp.example.com

# Switch to zdmuser
sudo su - zdmuser
```

### 4.2 Clone Repository and Navigate to Artifacts

```bash
# Clone the repository (if not already done)
cd ~
git clone https://github.com/terrymandin/GHCP-ODAA-PromptMigration.git

# Navigate to Step3 artifacts
cd ~/GHCP-ODAA-PromptMigration/Artifacts/Phase10-Migration/ZDM/PRODDB/Step3

# Make CLI script executable
chmod +x zdm_commands_PRODDB.sh
```

### 4.3 Create Credentials Directory

```bash
# Create the credentials directory
mkdir -p ~/creds
chmod 700 ~/creds
```

### 4.4 Create OCI Environment File

Run the init command to create the OCI environment file template:

```bash
./zdm_commands_PRODDB.sh init
```

Then edit the file with your actual OCI values:

```bash
vi ~/zdm_oci_env.sh
```

Set the following values:

```bash
# Target OCI Configuration (REQUIRED)
export TARGET_TENANCY_OCID="ocid1.tenancy.oc1..aaaaaaaabcdefghijklmnopqrstuvwxyz123456789"
export TARGET_USER_OCID="ocid1.user.oc1..aaaaaaaaxyz987654321abcdefghijklmnopqrstuv"
export TARGET_FINGERPRINT="aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99"
export TARGET_COMPARTMENT_OCID="<your-compartment-ocid>"
export TARGET_DATABASE_OCID="ocid1.database.oc1.iad..aaaaaaaaproddbazure67890"

# Object Storage Configuration (OPTIONAL for ONLINE_PHYSICAL)
# export TARGET_OBJECT_STORAGE_NAMESPACE="examplecorp"
```

### 4.5 Source OCI Environment Variables

```bash
# Source the OCI environment file
source ~/zdm_oci_env.sh

# Verify variables are set
echo $TARGET_TENANCY_OCID
echo $TARGET_DATABASE_OCID
```

### 4.6 Set Password Environment Variables

```bash
# Set passwords securely (will not echo to screen)
read -sp "Enter SOURCE SYS password: " SOURCE_SYS_PASSWORD; echo; export SOURCE_SYS_PASSWORD
read -sp "Enter TARGET SYS password: " TARGET_SYS_PASSWORD; echo; export TARGET_SYS_PASSWORD
read -sp "Enter TDE wallet password: " SOURCE_TDE_WALLET_PASSWORD; echo; export SOURCE_TDE_WALLET_PASSWORD
```

### 4.7 Create Password Files

```bash
# Create password files from environment variables
./zdm_commands_PRODDB.sh create-creds
```

### 4.8 Verify ZDM Installation

```bash
# Verify ZDM is working
export ZDM_HOME=/opt/oracle/zdm21c
$ZDM_HOME/bin/zdmcli -version

# Check ZDM service status
$ZDM_HOME/bin/zdmservice status
```

### 4.9 Test Connectivity

```bash
# Test SSH to source
ssh -i /home/zdmuser/.ssh/zdm_migration_key oracle@proddb01.corp.example.com "hostname"

# Test SSH to target
ssh -i /home/zdmuser/.ssh/zdm_migration_key oracle@proddb-oda.eastus.azure.example.com "hostname"
```

---

## Phase 5: Migration Execution

### 5.1 Pre-Migration Evaluation

Run the evaluation first to validate all settings without making changes:

```bash
# Source environment
source ~/zdm_oci_env.sh

# Run evaluation
./zdm_commands_PRODDB.sh eval
```

Review the evaluation output carefully:
- Check for any warnings or errors
- Verify all prerequisites are met
- Note the estimated migration time

### 5.2 Execute Migration

```bash
# Start the actual migration
./zdm_commands_PRODDB.sh migrate
```

The command will output a job ID. Save this for monitoring:
```
Job ID: <JOB_ID>
```

### 5.3 Monitor Progress

```bash
# Query job status
./zdm_commands_PRODDB.sh status <JOB_ID>

# Alternative: Direct ZDM command
$ZDM_HOME/bin/zdmcli query job -jobid <JOB_ID>

# View detailed phase status
$ZDM_HOME/bin/zdmcli query job -jobid <JOB_ID> -output long
```

### 5.4 Migration Phases

The online physical migration will proceed through these phases:

| Phase | Description | Expected Duration |
|-------|-------------|-------------------|
| ZDM_VALIDATE_SRC | Validate source database | 5-10 minutes |
| ZDM_VALIDATE_TGT | Validate target environment | 5-10 minutes |
| ZDM_CONFIGURE_DG_SRC | Configure Data Guard on source | 10-15 minutes |
| **PAUSE** | Migration pauses here for validation | Manual |
| ZDM_SWITCHOVER_SRC | Perform switchover (downtime) | 5-15 minutes |
| ZDM_POST_ACTIONS | Post-migration cleanup | 5-10 minutes |

### 5.5 Pause at Validation Point

The migration will pause at `ZDM_CONFIGURE_DG_SRC` as configured. At this point:

1. Verify Data Guard is syncing properly
2. Check standby database status
3. Validate application connectivity (read-only if available)
4. Confirm switchover window is available

```sql
-- On source database, check Data Guard status
SELECT DEST_ID, STATUS, DESTINATION, ERROR FROM V$ARCHIVE_DEST WHERE DEST_ID=2;

-- Check gap status
SELECT * FROM V$ARCHIVE_GAP;
```

### 5.6 Resume for Switchover

When ready to perform the switchover:

```bash
# Resume the migration job
./zdm_commands_PRODDB.sh resume <JOB_ID>
```

> ⚠️ **Warning:** The switchover phase will cause a brief outage (estimated 15 minutes or less).

---

## Phase 6: Post-Migration Validation

### 6.1 Verify Database Status

```sql
-- Connect to new primary (target)
sqlplus sys/<password>@PRODDB_AZURE as sysdba

-- Verify database role
SELECT NAME, OPEN_MODE, DATABASE_ROLE FROM V$DATABASE;
-- Expected: DATABASE_ROLE = PRIMARY

-- Verify database is open
SELECT STATUS FROM V$INSTANCE;
```

### 6.2 Data Verification Queries

```sql
-- Check tablespace status
SELECT TABLESPACE_NAME, STATUS FROM DBA_TABLESPACES;

-- Check datafile status
SELECT FILE#, STATUS, NAME FROM V$DATAFILE;

-- Verify user objects count (compare with source)
SELECT OWNER, OBJECT_TYPE, COUNT(*) 
FROM DBA_OBJECTS 
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP')
GROUP BY OWNER, OBJECT_TYPE
ORDER BY OWNER, OBJECT_TYPE;

-- Check for invalid objects
SELECT OWNER, OBJECT_TYPE, OBJECT_NAME, STATUS
FROM DBA_OBJECTS
WHERE STATUS = 'INVALID';
```

### 6.3 Application Connectivity Tests

```sql
-- Test connecting with application user
sqlplus appuser/<password>@PRODDB_AZURE

-- Run sample application queries
SELECT COUNT(*) FROM critical_table;
```

### 6.4 Performance Validation

```sql
-- Check AWR/performance data was migrated
SELECT SNAP_ID, BEGIN_INTERVAL_TIME 
FROM DBA_HIST_SNAPSHOT 
ORDER BY SNAP_ID DESC 
FETCH FIRST 5 ROWS ONLY;

-- Compare query execution times with baseline
```

### 6.5 TDE Verification

```sql
-- Verify TDE wallet is open
SELECT WRL_TYPE, STATUS, WALLET_TYPE FROM V$ENCRYPTION_WALLET;

-- Verify encrypted tablespaces
SELECT TABLESPACE_NAME, ENCRYPTED FROM DBA_TABLESPACES;
```

---

## Phase 7: Rollback Procedures

### 7.1 Emergency Rollback (Before Switchover)

If issues are discovered before switchover, the migration can be aborted:

```bash
# Abort the migration job
./zdm_commands_PRODDB.sh abort <JOB_ID>

# Or directly via ZDM
$ZDM_HOME/bin/zdmcli abort job -jobid <JOB_ID>
```

After abort:
1. Source database remains operational
2. Data Guard configuration is removed
3. Target standby is cleaned up

### 7.2 Post-Switchover Rollback

> ⚠️ **Warning:** Post-switchover rollback is complex and may result in data loss.

If critical issues are found after switchover:

1. **Evaluate the severity** - Can issues be fixed on the new primary?
2. **Check for data changes** - Any new transactions since switchover?

```sql
-- On new primary (target), check for any new transactions
SELECT SCN, TIMESTAMP FROM V$DATABASE;
```

3. **If rollback is required:**

```bash
# This is a manual process requiring careful execution
# Contact Oracle Support if needed

# High-level steps:
# 1. Stop applications
# 2. Reinstate old primary as the primary database
# 3. Discard target database or convert to standby
```

### 7.3 Cleanup After Successful Migration

```bash
# After validation is complete and migration is confirmed successful:

# 1. Clean up password files
./zdm_commands_PRODDB.sh cleanup-creds

# 2. Archive migration logs
mkdir -p ~/migration_archive/PRODDB
cp -r $ZDM_HOME/zdm/log/* ~/migration_archive/PRODDB/

# 3. Update DNS/connection strings for applications
# 4. Decommission source database (after retention period)
```

---

## Appendix A: Troubleshooting

### A.1 Common Issues and Solutions

#### OCI Authentication Errors

```
Error: Authorization failed or requested resource not found
```

**Solution:**
```bash
# Verify OCI configuration
cat ~/.oci/config

# Test OCI connectivity
oci os ns get

# Regenerate API key if needed
oci setup keys --output-dir ~/.oci
```

#### SSH Connectivity Issues

```
Error: Permission denied (publickey)
```

**Solution:**
```bash
# Check SSH key permissions
chmod 600 /home/zdmuser/.ssh/zdm_migration_key

# Verify key is in authorized_keys on target
ssh -vvv -i /home/zdmuser/.ssh/zdm_migration_key oracle@proddb-oda.eastus.azure.example.com
```

#### Data Guard Gap Issues

```
Error: Archive log gap detected
```

**Solution:**
```sql
-- On source, check for gaps
SELECT * FROM V$ARCHIVE_GAP;

-- Force log switch
ALTER SYSTEM SWITCH LOGFILE;

-- Check again
SELECT DEST_ID, STATUS, ERROR FROM V$ARCHIVE_DEST WHERE DEST_ID=2;
```

#### TDE Wallet Errors

```
Error: Cannot open TDE wallet
```

**Solution:**
```sql
-- Check wallet status
SELECT WRL_TYPE, STATUS FROM V$ENCRYPTION_WALLET;

-- Open wallet manually if needed
ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN IDENTIFIED BY "<password>";
```

### A.2 ZDM Log Locations

```bash
# Main ZDM logs
ls -la $ZDM_HOME/zdm/log/

# Job-specific logs
ls -la $ZDM_HOME/zdm/log/zdm_job_<JOB_ID>/

# Migration advisor output
cat $ZDM_HOME/zdm/log/zdm_job_<JOB_ID>/migration_advisor_report.html
```

### A.3 Useful Monitoring Commands

```bash
# Continuous job monitoring
watch -n 30 "$ZDM_HOME/bin/zdmcli query job -jobid <JOB_ID>"

# Check all active jobs
$ZDM_HOME/bin/zdmcli query job -all

# Get detailed phase information
$ZDM_HOME/bin/zdmcli query job -jobid <JOB_ID> -output long
```

---

*Generated: 2026-02-04*
*ZDM Migration Planning - Step 3*
