# ZDM Migration Runbook: PRODDB
## Migration: On-Premise to Oracle Database@Azure

---

### Document Information

| Field | Value |
|-------|-------|
| **Source Database** | PRODDB (PRODDB_PRIMARY) |
| **Source Host** | proddb01.corp.example.com |
| **Target Database** | PRODDB (PRODDB_AZURE) |
| **Target Host** | proddb-oda.eastus.azure.example.com |
| **Migration Type** | ONLINE_PHYSICAL (Data Guard) |
| **Maximum Downtime** | 15 minutes |
| **Created Date** | 2026-02-04 |
| **ZDM Version** | 21c |

---

## Table of Contents

1. [Pre-Migration Verification](#phase-1-pre-migration-verification)
2. [Source Database Configuration](#phase-2-source-database-configuration)
3. [Target Database Configuration](#phase-3-target-database-configuration)
4. [ZDM Server Configuration](#phase-4-zdm-server-configuration)
5. [Migration Execution](#phase-5-migration-execution)
6. [Post-Migration Validation](#phase-6-post-migration-validation)
7. [Rollback Procedures](#phase-7-rollback-procedures)
8. [Troubleshooting](#appendix-a-troubleshooting)

---

## Phase 1: Pre-Migration Verification

### 1.1 Source Database Checks

Execute these commands on the **source database server** as `oracle` user.

#### 1.1.1 Verify Database Status

```bash
# SSH to source
ssh oracle@proddb01.corp.example.com

# Set environment
export ORACLE_HOME=/u01/app/oracle/product/19.21.0/dbhome_1
export ORACLE_SID=PRODDB
export PATH=$ORACLE_HOME/bin:$PATH
```

```sql
-- Connect to database
sqlplus / as sysdba

-- Verify database is open
SELECT NAME, OPEN_MODE, DATABASE_ROLE, LOG_MODE FROM V$DATABASE;
-- Expected: PRODDB, READ WRITE, PRIMARY, ARCHIVELOG

-- Verify Force Logging
SELECT FORCE_LOGGING FROM V$DATABASE;
-- Expected: YES

-- Verify Supplemental Logging
SELECT SUPPLEMENTAL_LOG_DATA_MIN, SUPPLEMENTAL_LOG_DATA_PK FROM V$DATABASE;
-- Expected: YES, YES

-- Check database size
SELECT ROUND(SUM(BYTES)/1024/1024/1024, 2) AS SIZE_GB FROM DBA_DATA_FILES;

-- Verify password file exists
SELECT * FROM V$PWFILE_USERS;
```

#### 1.1.2 Verify TDE Configuration

```sql
-- Check TDE wallet status
SELECT WRL_PARAMETER, STATUS, WALLET_TYPE FROM V$ENCRYPTION_WALLET;
-- Expected: /u01/app/oracle/admin/PRODDB/wallet/tde, OPEN, AUTOLOGIN

-- Check for encrypted tablespaces
SELECT TABLESPACE_NAME, ENCRYPTED FROM DBA_TABLESPACES WHERE ENCRYPTED = 'YES';
```

#### 1.1.3 Verify Network Connectivity from Source

```bash
# Test connectivity to ZDM server
ping -c 3 zdm-jumpbox.corp.example.com

# Test connectivity to target
ping -c 3 proddb-oda.eastus.azure.example.com

# Test Oracle listener on target
tnsping PRODDB_AZURE
```

### 1.2 Target Database Checks

Execute these commands on the **target database server** as `oracle` user.

```bash
# SSH to target
ssh oracle@proddb-oda.eastus.azure.example.com

# Set environment
export ORACLE_HOME=/u02/app/oracle/product/19.0.0.0/dbhome_1
export ORACLE_SID=PRODDB
export PATH=$ORACLE_HOME/bin:$PATH
```

```sql
-- Connect to database
sqlplus / as sysdba

-- Verify target is accessible
SELECT INSTANCE_NAME, STATUS FROM V$INSTANCE;

-- Verify ASM diskgroups (for Exadata)
SELECT NAME, STATE, TOTAL_MB, FREE_MB FROM V$ASM_DISKGROUP;

-- Verify listener is running
lsnrctl status
```

#### 1.2.2 Verify Target Storage

```bash
# Check ASM diskgroup space
asmcmd lsdg

# Expected output should show DATA and RECO diskgroups with sufficient space
```

### 1.3 ZDM Server Checks

Execute these commands on the **ZDM server**.

```bash
# SSH to ZDM server as your admin user (azureuser in this example)
ssh azureuser@zdm-jumpbox.corp.example.com

# Switch to zdmuser
sudo su - zdmuser

# Set ZDM environment
export ZDM_HOME=/opt/oracle/zdm21c
export PATH=$ZDM_HOME/bin:$PATH
```

#### 1.3.1 Verify ZDM Installation

```bash
# Check ZDM version
$ZDM_HOME/bin/zdmcli -version

# Verify ZDM service is running
$ZDM_HOME/bin/zdmcli query job -jobid 0 2>&1 | head -5
# This may show an error about job not found, but confirms ZDM is responding
```

#### 1.3.2 First-Time Setup (run once)

```bash
# Navigate to Step3 artifacts in your cloned fork
cd /path/to/GHCP-ODAA-PromptMigration/Artifacts/Phase10-Migration/ZDM/PRODDB/Step3

# Make script executable
chmod +x zdm_commands_PRODDB.sh

# Initialize environment (creates ~/creds directory and ~/zdm_oci_env.sh template)
./zdm_commands_PRODDB.sh init
```

#### 1.3.3 Configure OCI Environment

```bash
# Edit the generated OCI environment file with actual OCID values
vi ~/zdm_oci_env.sh

# Then source the environment variables
source ~/zdm_oci_env.sh

# Verify OCI CLI version
oci --version

# Test OCI connectivity
oci os ns get
# Expected: Returns namespace

# Verify target database is accessible
oci db database get --database-id ${TARGET_DATABASE_OCID} --query 'data.{name:"db-name",state:"lifecycle-state"}'
```

#### 1.3.4 Verify SSH Connectivity

```bash
# Test SSH to source
ssh -i /home/zdmuser/.ssh/zdm_migration_key oracle@proddb01.corp.example.com "hostname"

# Test SSH to target
ssh -i /home/zdmuser/.ssh/zdm_migration_key oracle@proddb-oda.eastus.azure.example.com "hostname"
```

#### 1.3.5 Verify Disk Space

```bash
# Check ZDM home disk space
df -h /opt/oracle/zdm21c
# Recommended: At least 20GB free

# Check credentials directory exists (created by init command)
ls -la ~/creds/
```

### 1.4 Network Connectivity Checks

```bash
# From ZDM server, verify all network paths
# Source Oracle port
nc -zv proddb01.corp.example.com 1521

# Target Oracle port
nc -zv proddb-oda.eastus.azure.example.com 1521

# Source SSH port
nc -zv proddb01.corp.example.com 22

# Target SSH port
nc -zv proddb-oda.eastus.azure.example.com 22
```

---

## Phase 2: Source Database Configuration

### 2.1 Enable Archive Log Mode

> **Note:** Skip this section if already in ARCHIVELOG mode (verified in 1.1.1).

```sql
-- If not in ARCHIVELOG mode (requires downtime)
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;

-- Verify
SELECT LOG_MODE FROM V$DATABASE;
```

### 2.2 Enable Force Logging

```sql
-- If not already enabled
ALTER DATABASE FORCE LOGGING;

-- Verify
SELECT FORCE_LOGGING FROM V$DATABASE;
-- Expected: YES
```

### 2.3 Enable Supplemental Logging

```sql
-- Enable minimal supplemental logging
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;

-- Enable primary key supplemental logging
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (PRIMARY KEY) COLUMNS;

-- Verify
SELECT SUPPLEMENTAL_LOG_DATA_MIN, SUPPLEMENTAL_LOG_DATA_PK FROM V$DATABASE;
-- Expected: YES, YES
```

### 2.4 Configure TNS Entries

Add entry for target database on source server:

```bash
# On source server, add to $ORACLE_HOME/network/admin/tnsnames.ora
cat >> $ORACLE_HOME/network/admin/tnsnames.ora << 'EOF'

PRODDB_AZURE =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = proddb-oda.eastus.azure.example.com)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = PRODDB_AZURE.eastus.azure.example.com)
    )
  )
EOF
```

### 2.5 Configure SSH Key Authentication

```bash
# On source server as oracle user
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Add ZDM server's public key to authorized_keys
cat >> ~/.ssh/authorized_keys << 'EOF'
<ZDM_PUBLIC_KEY_CONTENT>
EOF

chmod 600 ~/.ssh/authorized_keys
```

### 2.6 Create/Verify Password File

```bash
# Verify password file exists
ls -la $ORACLE_HOME/dbs/orapwPRODDB

# If not exists, create it
orapwd file=$ORACLE_HOME/dbs/orapwPRODDB password=<SYS_PASSWORD> entries=10 format=12.2
```

---

## Phase 3: Target Database Configuration

### 3.1 Configure TNS Entries

Add entry for source database on target server:

```bash
# On target server, add to $ORACLE_HOME/network/admin/tnsnames.ora
cat >> $ORACLE_HOME/network/admin/tnsnames.ora << 'EOF'

PRODDB_PRIMARY =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = proddb01.corp.example.com)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = PRODDB.corp.example.com)
    )
  )
EOF
```

### 3.2 Configure SSH Key Authentication

```bash
# On target server as oracle user
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Add ZDM server's public key to authorized_keys
cat >> ~/.ssh/authorized_keys << 'EOF'
<ZDM_PUBLIC_KEY_CONTENT>
EOF

chmod 600 ~/.ssh/authorized_keys
```

### 3.3 Verify OCI Connectivity

```bash
# On target server, verify OCI metadata
curl -H "Authorization: Bearer Oracle" http://169.254.169.254/opc/v2/instance/

# Verify database OCID is accessible
oci db database get --database-id ${TARGET_DATABASE_OCID}
```

### 3.4 Prepare for Data Guard

```sql
-- On target, verify standby file management
SHOW PARAMETER STANDBY_FILE_MANAGEMENT;
-- Recommended: AUTO

-- Verify DB_FILE_NAME_CONVERT and LOG_FILE_NAME_CONVERT if paths differ
SHOW PARAMETER DB_FILE_NAME_CONVERT;
SHOW PARAMETER LOG_FILE_NAME_CONVERT;
```

---

## Phase 4: ZDM Server Configuration

### 4.1 Verify ZDM Installation

```bash
# As zdmuser on ZDM server
export ZDM_HOME=/opt/oracle/zdm21c
export PATH=$ZDM_HOME/bin:$PATH

# Check ZDM version
$ZDM_HOME/bin/zdmcli -version

# Check ZDM service status
$ZDM_HOME/bin/zdmservice status
```

### 4.2 Configure OCI CLI

```bash
# Create OCI config directory
mkdir -p ~/.oci
chmod 700 ~/.oci

# Create/update OCI configuration file
cat > ~/.oci/config << 'EOF'
[DEFAULT]
user=ocid1.user.oc1..aaaaaaaaxyz987654321abcdefghijklmnopqrstuv
fingerprint=aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99
tenancy=ocid1.tenancy.oc1..aaaaaaaabcdefghijklmnopqrstuvwxyz123456789
region=us-ashburn-1
key_file=/home/zdmuser/.oci/oci_api_key.pem
EOF

chmod 600 ~/.oci/config

# Test OCI connectivity
oci os ns get
```

### 4.3 Configure SSH Keys

```bash
# Verify SSH key exists and has correct permissions
ls -la /home/zdmuser/.ssh/zdm_migration_key
# Should show -rw------- (600)

# Test connectivity to source
ssh -i /home/zdmuser/.ssh/zdm_migration_key oracle@proddb01.corp.example.com "echo 'Source connection OK'"

# Test connectivity to target
ssh -i /home/zdmuser/.ssh/zdm_migration_key oracle@proddb-oda.eastus.azure.example.com "echo 'Target connection OK'"
```

### 4.4 Create Credential Files at Runtime

> ⚠️ **SECURITY**: Run these commands immediately before migration. Clean up after completion.

```bash
# Set password environment variables (securely)
read -sp "Enter Source SYS Password: " SOURCE_SYS_PASSWORD; echo; export SOURCE_SYS_PASSWORD
read -sp "Enter Target SYS Password: " TARGET_SYS_PASSWORD; echo; export TARGET_SYS_PASSWORD
read -sp "Enter TDE Wallet Password: " SOURCE_TDE_WALLET_PASSWORD; echo; export SOURCE_TDE_WALLET_PASSWORD

# Create credentials directory
mkdir -p /home/zdmuser/creds
chmod 700 /home/zdmuser/creds

# Create password files
echo "$SOURCE_SYS_PASSWORD" > /home/zdmuser/creds/source_sys_password.txt
echo "$TARGET_SYS_PASSWORD" > /home/zdmuser/creds/target_sys_password.txt
echo "$SOURCE_TDE_WALLET_PASSWORD" > /home/zdmuser/creds/tde_password.txt

# Secure password files
chmod 600 /home/zdmuser/creds/*.txt

# Verify files exist
ls -la /home/zdmuser/creds/
```

### 4.5 Set OCI Environment Variables

```bash
# Create environment file (do not include passwords!)
cat > /home/zdmuser/zdm_oci_env.sh << 'EOF'
# OCI Environment Variables for PRODDB Migration
export TARGET_TENANCY_OCID="ocid1.tenancy.oc1..aaaaaaaabcdefghijklmnopqrstuvwxyz123456789"
export TARGET_USER_OCID="ocid1.user.oc1..aaaaaaaaxyz987654321abcdefghijklmnopqrstuv"
export TARGET_FINGERPRINT="aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99"
export TARGET_COMPARTMENT_OCID="<Your Compartment OCID>"
export TARGET_DATABASE_OCID="ocid1.database.oc1.iad..aaaaaaaaproddbazure67890"

# Object Storage (OPTIONAL for ONLINE_PHYSICAL)
# export TARGET_OBJECT_STORAGE_NAMESPACE="examplecorp"
EOF

chmod 600 /home/zdmuser/zdm_oci_env.sh

# Source the environment
source /home/zdmuser/zdm_oci_env.sh
```

### 4.6 Test Connectivity

```bash
# Verify ZDM can reach OCI
oci db database get --database-id ${TARGET_DATABASE_OCID} --query 'data.{name:"db-name",state:"lifecycle-state"}'

# Verify network connectivity
nc -zv proddb01.corp.example.com 1521
nc -zv proddb-oda.eastus.azure.example.com 1521
```

---

## Phase 5: Migration Execution

### 5.1 Run Evaluation (Dry Run)

Always run evaluation first to identify potential issues.

```bash
# Navigate to Step3 directory
cd /path/to/Artifacts/Phase10-Migration/ZDM/PRODDB/Step3

# Source environment
source /home/zdmuser/zdm_oci_env.sh

# Run evaluation
./zdm_commands_PRODDB.sh eval

# Or run directly with ZDM CLI:
$ZDM_HOME/bin/zdmcli migrate database \
  -sourcesid PRODDB \
  -sourcenode proddb01.corp.example.com \
  -srcauth zdmauth \
  -srcarg1 user:oracle \
  -srcarg2 identity_file:/home/zdmuser/.ssh/zdm_migration_key \
  -srcarg3 sudo_location:/usr/bin/sudo \
  -targetnode proddb-oda.eastus.azure.example.com \
  -tgtauth zdmauth \
  -tgtarg1 user:oracle \
  -tgtarg2 identity_file:/home/zdmuser/.ssh/zdm_migration_key \
  -tgtarg3 sudo_location:/usr/bin/sudo \
  -rsp /path/to/zdm_migrate_PRODDB.rsp \
  -eval
```

**Review Evaluation Output:**
- Check for errors or warnings
- Review estimated migration time
- Verify all prerequisites pass

### 5.2 Execute Migration

After successful evaluation, execute the actual migration:

```bash
# Source environment and set passwords
source /home/zdmuser/zdm_oci_env.sh

# Set password environment variables
read -sp "Enter Source SYS Password: " SOURCE_SYS_PASSWORD; echo; export SOURCE_SYS_PASSWORD
read -sp "Enter Target SYS Password: " TARGET_SYS_PASSWORD; echo; export TARGET_SYS_PASSWORD
read -sp "Enter TDE Wallet Password: " SOURCE_TDE_WALLET_PASSWORD; echo; export SOURCE_TDE_WALLET_PASSWORD

# Create password files
./zdm_commands_PRODDB.sh create-creds

# Execute migration
./zdm_commands_PRODDB.sh migrate
```

**Expected Output:**
- Job ID will be returned (save this!)
- Initial phases will begin execution

### 5.3 Monitor Progress

Open a separate terminal to monitor migration progress:

```bash
# Query job status (replace <JOB_ID> with actual job ID)
$ZDM_HOME/bin/zdmcli query job -jobid <JOB_ID>

# Watch progress in real-time
watch -n 30 "$ZDM_HOME/bin/zdmcli query job -jobid <JOB_ID>"

# Check ZDM logs for detailed progress
tail -f $ZDM_HOME/zdm/zdm_<JOB_ID>/log/zdm.log
```

**Migration Phases for ONLINE_PHYSICAL:**

| Phase | Description | Duration (Estimated) |
|-------|-------------|---------------------|
| ZDM_VALIDATE_SRC | Validate source database | 5-10 min |
| ZDM_VALIDATE_TGT | Validate target database | 5-10 min |
| ZDM_SETUP_SRC | Configure source for Data Guard | 10-15 min |
| ZDM_SETUP_TGT | Configure target for Data Guard | 10-15 min |
| ZDM_CONFIGURE_DG_SRC | Set up Data Guard on source | 15-30 min |
| ZDM_TRANSFER_DATA | Initial data transfer | Varies (size dependent) |
| ZDM_SYNC_DATA | Synchronize redo data | Continuous |
| **PAUSE POINT** | **ZDM_CONFIGURE_DG_SRC** | **Manual resume required** |
| ZDM_SWITCHOVER_SRC | Perform switchover | 10-15 min |
| ZDM_SWITCHOVER_TGT | Complete switchover on target | 5-10 min |
| ZDM_POST_MIGRATION | Post-migration cleanup | 5-10 min |

### 5.4 Resume After Pause Point

The migration is configured to pause at `ZDM_CONFIGURE_DG_SRC` for validation.

**Before resuming:**
1. Verify Data Guard is configured correctly
2. Check redo apply lag
3. Confirm application downtime window is approved

```bash
# Check current sync status
ssh oracle@proddb-oda.eastus.azure.example.com "sqlplus -s / as sysdba <<EOF
SELECT SEQUENCE#, FIRST_TIME, NEXT_TIME, APPLIED FROM V\\\$ARCHIVED_LOG ORDER BY SEQUENCE# DESC FETCH FIRST 10 ROWS ONLY;
EOF"

# Check Data Guard status
ssh oracle@proddb-oda.eastus.azure.example.com "sqlplus -s / as sysdba <<EOF
SELECT DATABASE_ROLE, PROTECTION_MODE, OPEN_MODE FROM V\\\$DATABASE;
SELECT DEST_ID, STATUS, ERROR FROM V\\\$ARCHIVE_DEST_STATUS WHERE DEST_ID <= 2;
EOF"
```

**Resume migration:**

```bash
# Resume from pause point
./zdm_commands_PRODDB.sh resume <JOB_ID>

# Or directly:
$ZDM_HOME/bin/zdmcli resume job -jobid <JOB_ID>
```

### 5.5 Switchover Execution

The switchover will occur automatically after resume. Monitor closely:

```bash
# Watch job progress during switchover
watch -n 10 "$ZDM_HOME/bin/zdmcli query job -jobid <JOB_ID>"

# Monitor target database role change
ssh oracle@proddb-oda.eastus.azure.example.com "sqlplus -s / as sysdba <<EOF
SELECT NAME, DATABASE_ROLE, OPEN_MODE FROM V\\\$DATABASE;
EOF"
```

**Switchover Completed When:**
- Target database role changes to PRIMARY
- Source database role changes to PHYSICAL STANDBY (or DISABLED)
- Job status shows SUCCEEDED

---

## Phase 6: Post-Migration Validation

### 6.1 Verify Database Status

```sql
-- On target database
sqlplus / as sysdba

-- Verify database is PRIMARY and READ WRITE
SELECT NAME, DATABASE_ROLE, OPEN_MODE FROM V$DATABASE;
-- Expected: PRODDB, PRIMARY, READ WRITE

-- Verify all datafiles are online
SELECT FILE#, STATUS, NAME FROM V$DATAFILE;
-- All should show ONLINE

-- Check instance status
SELECT INSTANCE_NAME, STATUS, HOST_NAME FROM V$INSTANCE;
```

### 6.2 Data Verification

```sql
-- Compare row counts for key tables (use application-specific tables)
SELECT COUNT(*) FROM <SCHEMA>.<TABLE>;

-- Verify data checksums (if documented before migration)
SELECT ORA_HASH(column_value) FROM <TABLE>;

-- Check for invalid objects
SELECT OWNER, OBJECT_TYPE, OBJECT_NAME, STATUS 
FROM DBA_OBJECTS 
WHERE STATUS = 'INVALID';
```

### 6.3 Application Connectivity Tests

```bash
# Test connection using new connection string
sqlplus app_user/password@proddb-oda.eastus.azure.example.com:1521/PRODDB_AZURE.eastus.azure.example.com

# Test JDBC connection (example)
java -jar connectivity_test.jar "jdbc:oracle:thin:@proddb-oda.eastus.azure.example.com:1521/PRODDB_AZURE.eastus.azure.example.com"
```

### 6.4 Performance Validation

```sql
-- Collect AWR snapshot for baseline comparison
EXEC DBMS_WORKLOAD_REPOSITORY.CREATE_SNAPSHOT;

-- Check current performance metrics
SELECT METRIC_NAME, VALUE FROM V$SYSMETRIC WHERE METRIC_NAME LIKE '%Response Time%';

-- Verify temp tablespace
SELECT TABLESPACE_NAME, BYTES/1024/1024 MB_ALLOCATED FROM DBA_TEMP_FILES;
```

### 6.5 TDE Wallet Validation

```sql
-- Verify TDE wallet is open
SELECT WRL_PARAMETER, STATUS, WALLET_TYPE FROM V$ENCRYPTION_WALLET;
-- Expected: OPEN, AUTOLOGIN

-- Verify encrypted tablespaces are accessible
SELECT TABLESPACE_NAME, ENCRYPTED FROM DBA_TABLESPACES;
```

### 6.6 Clean Up Credentials

> ⚠️ **SECURITY**: Always clean up password files after successful migration.

```bash
# On ZDM server
rm -f /home/zdmuser/creds/source_sys_password.txt
rm -f /home/zdmuser/creds/target_sys_password.txt
rm -f /home/zdmuser/creds/tde_password.txt

# Verify cleanup
ls -la /home/zdmuser/creds/
```

---

## Phase 7: Rollback Procedures

### 7.1 Before Switchover (Data Guard Still Configured)

If issues occur before switchover, the source remains PRIMARY:

```bash
# Abort ZDM job
$ZDM_HOME/bin/zdmcli abort job -jobid <JOB_ID>

# On source, remove Data Guard configuration
sqlplus / as sysdba <<EOF
ALTER SYSTEM SET LOG_ARCHIVE_DEST_2='' SCOPE=BOTH;
ALTER SYSTEM SET FAL_SERVER='' SCOPE=BOTH;
EOF

# Remove standby database from target (if needed)
# This can be done from OCI Console or using DBCA
```

### 7.2 After Switchover

After switchover completes, rollback requires failback procedure:

```bash
# Step 1: Stop applications on new primary (target)

# Step 2: On target, convert to standby
# This requires Data Guard Broker or manual commands
# Contact DBA team for assistance

# Step 3: On source, convert back to primary
# Reinstate old primary

# Step 4: Perform switchover back to source
```

> **Note:** Post-switchover rollback is complex and may require Oracle Support assistance. Always test switchover in non-production first.

### 7.3 Emergency Contacts

| Role | Contact | Notes |
|------|---------|-------|
| DBA Lead | dba-lead@example.com | Primary escalation |
| Oracle Support | My Oracle Support | SR for critical issues |
| Network Team | network-team@example.com | Connectivity issues |
| Application Team | app-team@example.com | Application restart |

---

## Appendix A: Troubleshooting

### A.1 Common Issues and Solutions

#### Issue: SSH Authentication Failed

**Symptom:** ZDM cannot connect to source or target via SSH.

**Solution:**
```bash
# Verify SSH key permissions
chmod 600 /home/zdmuser/.ssh/zdm_migration_key

# Test SSH manually with verbose output
ssh -vv -i /home/zdmuser/.ssh/zdm_migration_key oracle@<host>

# Check target's authorized_keys
ssh oracle@<host> "cat ~/.ssh/authorized_keys"
```

#### Issue: OCI Authentication Failed

**Symptom:** OCI CLI commands fail with authentication error.

**Solution:**
```bash
# Verify OCI config exists
cat ~/.oci/config

# Check fingerprint matches
oci setup repair-file-permissions

# Test with explicit config
oci os ns get --config-file ~/.oci/config --profile DEFAULT
```

#### Issue: Data Guard Sync Lag

**Symptom:** Large apply lag on standby.

**Solution:**
```sql
-- Check apply lag
SELECT NAME, VALUE FROM V$DATAGUARD_STATS WHERE NAME = 'apply lag';

-- Check for gaps
SELECT * FROM V$ARCHIVE_GAP;

-- Increase parallel recovery
ALTER SYSTEM SET RECOVERY_PARALLELISM=8;
```

#### Issue: TDE Wallet Not Opening on Target

**Symptom:** Encrypted data inaccessible after migration.

**Solution:**
```sql
-- Check wallet status
SELECT * FROM V$ENCRYPTION_WALLET;

-- Open wallet manually
ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN IDENTIFIED BY "<password>";

-- Set up auto-login if needed
ADMINISTER KEY MANAGEMENT CREATE AUTO_LOGIN KEYSTORE FROM KEYSTORE '<wallet_path>' IDENTIFIED BY "<password>";
```

#### Issue: Migration Job Stuck

**Symptom:** Job appears to hang at a phase.

**Solution:**
```bash
# Check job status
$ZDM_HOME/bin/zdmcli query job -jobid <JOB_ID>

# Check ZDM logs
tail -100 $ZDM_HOME/zdm/zdm_<JOB_ID>/log/zdm.log

# If truly stuck, abort and retry
$ZDM_HOME/bin/zdmcli abort job -jobid <JOB_ID>
```

### A.2 Log File Locations

| Component | Log Location |
|-----------|-------------|
| ZDM Job Logs | `$ZDM_HOME/zdm/zdm_<JOB_ID>/log/` |
| ZDM Service Logs | `$ZDM_HOME/logs/` |
| Source Alert Log | `$ORACLE_BASE/diag/rdbms/proddb/PRODDB/trace/alert_PRODDB.log` |
| Target Alert Log | `$ORACLE_BASE/diag/rdbms/proddb/PRODDB/trace/alert_PRODDB.log` |
| Data Guard Broker | `$ORACLE_BASE/diag/rdbms/*/drc*.log` |

### A.3 Useful Commands Reference

```bash
# ZDM Commands
$ZDM_HOME/bin/zdmcli query job -jobid <JOB_ID>        # Query job status
$ZDM_HOME/bin/zdmcli resume job -jobid <JOB_ID>       # Resume paused job
$ZDM_HOME/bin/zdmcli abort job -jobid <JOB_ID>        # Abort job
$ZDM_HOME/bin/zdmcli query jobs                        # List all jobs

# Data Guard Commands (on target)
dgmgrl sys/<password>@PRODDB_AZURE
DGMGRL> show configuration;
DGMGRL> show database PRODDB_AZURE;

# OCI Commands
oci db database get --database-id <OCID>
oci db database list --compartment-id <OCID>
```

---

## Appendix B: Migration Timeline

| Phase | Estimated Duration | Notes |
|-------|-------------------|-------|
| Phase 1: Pre-Migration Verification | 1-2 hours | Run day before migration |
| Phase 2-4: Configuration | 2-4 hours | Run day before migration |
| Phase 5.1: Evaluation | 30 minutes | Day of migration |
| Phase 5.2: Migration Start | 1-2 hours | Initial sync |
| Phase 5.3: Data Transfer | Varies | Depends on database size |
| Phase 5.4: Switchover | 15-30 minutes | Planned downtime window |
| Phase 6: Validation | 1-2 hours | Post-switchover |

**Total Estimated Time:** 6-12 hours (excluding data transfer time)
**Downtime Window:** ≤ 15 minutes (during switchover only)

---

*Generated by ZDM Migration Planning - Step 3*
*Date: 2026-02-04*
