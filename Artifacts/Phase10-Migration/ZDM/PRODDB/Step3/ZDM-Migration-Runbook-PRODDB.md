# ZDM Migration Runbook: PRODDB
## Migration: On-Premise to Oracle Database@Azure

### Document Information

| Field | Value |
|-------|-------|
| Source Database | ORADB01 (oradb01) on temandin-oravm-vm01 |
| Target Database | Oracle Database@Azure Exadata (tmodaauks-rqahk1/rqahk2) |
| Migration Type | ONLINE_PHYSICAL |
| Migration Method | Data Guard Physical Standby |
| ZDM Server | tm-vm-odaa-oracle-jumpbox (10.1.0.8) |
| Created Date | 2026-02-03 |
| Database Size | 1.92 GB |

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

**Connect to source database server:**
```bash
ssh azureuser@temandin-oravm-vm01
sudo su - oracle
```

**Set environment:**
```bash
export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1
export ORACLE_SID=oradb01
export PATH=$ORACLE_HOME/bin:$PATH
```

**Verify database status:**
```sql
sqlplus / as sysdba << 'EOF'
-- Basic database info
SELECT NAME, DB_UNIQUE_NAME, DBID, DATABASE_ROLE, OPEN_MODE, LOG_MODE
FROM V$DATABASE;

-- Verify ARCHIVELOG mode
SELECT LOG_MODE FROM V$DATABASE;

-- Verify Force Logging
SELECT FORCE_LOGGING FROM V$DATABASE;

-- Verify Supplemental Logging
SELECT SUPPLEMENTAL_LOG_DATA_MIN, SUPPLEMENTAL_LOG_DATA_PK FROM V$DATABASE;

-- Check database size
SELECT ROUND(SUM(BYTES)/1024/1024/1024, 2) AS SIZE_GB FROM DBA_DATA_FILES;

-- Verify password file exists
SELECT * FROM V$PWFILE_USERS;

-- Check TDE wallet status
SELECT * FROM V$ENCRYPTION_WALLET;

-- Check for invalid objects
SELECT COUNT(*) AS INVALID_OBJECTS FROM DBA_OBJECTS WHERE STATUS = 'INVALID';

-- Check database links
SELECT OWNER, DB_LINK, USERNAME, HOST FROM DBA_DB_LINKS;
EOF
```

**Expected Results:**

| Check | Expected Value | Actual | Status |
|-------|----------------|--------|--------|
| LOG_MODE | ARCHIVELOG | | ⬜ |
| FORCE_LOGGING | YES | | ⬜ |
| SUPPLEMENTAL_LOG_DATA_MIN | YES | | ⬜ |
| SUPPLEMENTAL_LOG_DATA_PK | YES | | ⬜ |
| Password File Users | ≥1 (SYS) | | ⬜ |
| Wallet Status | OPEN | | ⬜ |
| Invalid Objects | 0 | | ⬜ |

---

### 1.2 Target Database Checks

**Connect to target node 1:**
```bash
ssh opc@tmodaauks-rqahk1
sudo su - oracle
```

**Set environment:**
```bash
export ORACLE_HOME=/u02/app/oracle/product/19.0.0.0/dbhome_1
export GRID_HOME=/u01/app/19.0.0.0/grid
export PATH=$ORACLE_HOME/bin:$GRID_HOME/bin:$PATH
```

**Verify cluster status:**
```bash
# Check CRS status
crsctl check crs

# Check cluster nodes
olsnodes -n

# Check all resources
crsctl stat res -t
```

**Verify ASM disk groups:**
```sql
sqlplus / as sysasm << 'EOF'
SET LINESIZE 200
SELECT NAME, STATE, TYPE, TOTAL_MB, FREE_MB, 
       ROUND(FREE_MB/TOTAL_MB*100,1) AS PCT_FREE 
FROM V$ASM_DISKGROUP;
EOF
```

**Expected ASM Configuration:**

| Disk Group | Expected State | Purpose |
|------------|----------------|---------|
| DATAC3 | MOUNTED | Data storage |
| RECOC3 | MOUNTED | Recovery area |

**Verify listener status:**
```bash
lsnrctl status LISTENER
lsnrctl status LISTENER_SCAN1
```

**Check existing databases:**
```bash
cat /etc/oratab | grep -v '^#'
srvctl status database -d migdb
srvctl status database -d oradb01m 2>/dev/null || echo "oradb01m not registered"
```

---

### 1.3 ZDM Server Checks

**Connect to ZDM server:**
```bash
ssh azureuser@tm-vm-odaa-oracle-jumpbox
```

**Switch to zdmuser (recommended for ZDM operations):**
```bash
sudo su - zdmuser
```

**Set ZDM environment:**
```bash
export ZDM_HOME=/u01/app/zdmhome
export PATH=$ZDM_HOME/bin:$PATH
```

**Verify ZDM installation:**
```bash
# Check ZDM version
$ZDM_HOME/bin/zdmcli -build

# Check ZDM service status
$ZDM_HOME/bin/zdmservice status

# List existing jobs (if any)
$ZDM_HOME/bin/zdmcli query job -listall
```

**Verify OCI CLI configuration:**
```bash
# Check OCI config exists
cat ~/.oci/config

# Test OCI connectivity
oci os ns get

# Get Object Storage namespace
oci os ns get --query 'data' --raw-output
```

**Verify SSH keys:**
```bash
# List available SSH keys
ls -la ~/.ssh/*.pem

# Expected keys:
# /home/zdmuser/.ssh/zdm.pem - Source connectivity
# /home/zdmuser/.ssh/odaa.pem - Target connectivity
```

**Check disk space:**
```bash
df -h /u01/app/zdmhome
# Expected: At least 20 GB free
```

---

### 1.4 Network Connectivity Checks

**From ZDM server, verify connectivity to source:**
```bash
# SSH connectivity
ssh -i ~/.ssh/zdm.pem azureuser@10.1.0.10 "hostname; echo 'SSH OK'"

# Oracle port connectivity
nc -zv 10.1.0.10 1521

# TNS ping
tnsping temandin-oravm-vm01:1521/oradb01
```

**From ZDM server, verify connectivity to target:**
```bash
# SSH connectivity
ssh -i ~/.ssh/odaa.pem opc@10.0.1.160 "hostname; echo 'SSH OK'"

# Oracle port connectivity
nc -zv 10.0.1.160 1521

# TNS ping (scan address)
tnsping tmodaauks-rqahk1:1521
```

**Network Connectivity Summary:**

| Path | SSH (22) | Oracle (1521) | Status |
|------|----------|---------------|--------|
| ZDM → Source (10.1.0.10) | ✅ | ✅ | ⬜ Verified |
| ZDM → Target (10.0.1.160) | ✅ | ✅ | ⬜ Verified |

---

## Phase 2: Source Database Configuration

> **Note:** Based on discovery, the source database is already configured for online migration. The following steps verify the existing configuration.

### 2.1 Verify Archive Log Mode

**Already enabled - verification only:**
```sql
sqlplus / as sysdba << 'EOF'
SELECT LOG_MODE FROM V$DATABASE;
-- Expected: ARCHIVELOG
EOF
```

If NOT in ARCHIVELOG mode (not expected):
```sql
-- Only if needed - requires database restart
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;
```

---

### 2.2 Verify Force Logging

**Already enabled - verification only:**
```sql
sqlplus / as sysdba << 'EOF'
SELECT FORCE_LOGGING FROM V$DATABASE;
-- Expected: YES
EOF
```

If NOT enabled (not expected):
```sql
ALTER DATABASE FORCE LOGGING;
```

---

### 2.3 Verify Supplemental Logging

**Already enabled - verification only:**
```sql
sqlplus / as sysdba << 'EOF'
SELECT SUPPLEMENTAL_LOG_DATA_MIN, SUPPLEMENTAL_LOG_DATA_PK, 
       SUPPLEMENTAL_LOG_DATA_UI, SUPPLEMENTAL_LOG_DATA_ALL
FROM V$DATABASE;
-- Expected: MIN=YES, PK=YES
EOF
```

If NOT enabled (not expected):
```sql
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (PRIMARY KEY) COLUMNS;
```

---

### 2.4 Configure TNS Entries

**Add target database entry to tnsnames.ora:**
```bash
# On source server as oracle user
cat >> $ORACLE_HOME/network/admin/tnsnames.ora << 'EOF'

# Target ODAA Database - for ZDM migration
ORADB01_TGT =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = tmodaauks-rqahk1)(PORT = 1521))
    (ADDRESS = (PROTOCOL = TCP)(HOST = tmodaauks-rqahk2)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = oradb01_tgt)
    )
  )
EOF
```

**Verify TNS entry:**
```bash
tnsping ORADB01_TGT
```

---

### 2.5 Configure SSH Key Authentication

**On source server, authorize ZDM server's key:**
```bash
# As oracle user on source
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Add ZDM server's public key (get from zdmuser@zdm-server)
# The zdm.pem private key's corresponding public key should be added
cat >> ~/.ssh/authorized_keys << 'EOF'
# ZDM Server Key for migration
<INSERT PUBLIC KEY HERE>
EOF

chmod 600 ~/.ssh/authorized_keys
```

**Test from ZDM server:**
```bash
# From ZDM server as zdmuser
ssh -i ~/.ssh/zdm.pem oracle@10.1.0.10 "echo 'SSH OK'"
```

---

### 2.6 Verify Password File

```sql
sqlplus / as sysdba << 'EOF'
-- Check password file users
SELECT * FROM V$PWFILE_USERS;

-- Verify password file location
!ls -la $ORACLE_HOME/dbs/orapw$ORACLE_SID
EOF
```

Expected location: `/u01/app/oracle/product/19.0.0/dbhome_1/dbs/orapworadb01`

---

### 2.7 Verify TDE Wallet

```sql
sqlplus / as sysdba << 'EOF'
-- Check wallet status
SELECT * FROM V$ENCRYPTION_WALLET;

-- Check wallet location
SELECT * FROM V$ENCRYPTION_KEYS WHERE ROWNUM = 1;
EOF
```

**Wallet Details:**
- Location: `/u01/app/oracle/admin/oradb01/wallet/tde/`
- Type: AUTOLOGIN
- Status: OPEN

> **Important:** TDE wallet password is required during migration even for AUTOLOGIN wallets.

---

## Phase 3: Target Database Configuration

### 3.1 Configure TNS Entries

**On target nodes as oracle user:**
```bash
# On tmodaauks-rqahk1 (and rqahk2)
cat >> $ORACLE_HOME/network/admin/tnsnames.ora << 'EOF'

# Source Database - for ZDM migration
ORADB01_SRC =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = temandin-oravm-vm01)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = oradb01)
    )
  )
EOF
```

---

### 3.2 Configure SSH Key Authentication

**On target nodes, authorize ZDM server's key:**
```bash
# As opc user, then switch to oracle
sudo su - oracle
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Add ZDM server's public key
cat >> ~/.ssh/authorized_keys << 'EOF'
# ZDM Server Key for migration
<INSERT PUBLIC KEY HERE>
EOF

chmod 600 ~/.ssh/authorized_keys
```

**Test from ZDM server:**
```bash
# From ZDM server as zdmuser
ssh -i ~/.ssh/odaa.pem oracle@10.0.1.160 "echo 'SSH OK'"
```

---

### 3.3 Verify ASM Storage Availability

```sql
-- On target as oracle user, connect to ASM
export ORACLE_SID=+ASM1
sqlplus / as sysasm << 'EOF'
SET LINESIZE 200
SELECT NAME, TYPE, STATE, TOTAL_MB, FREE_MB,
       ROUND(FREE_MB/TOTAL_MB*100,1) AS PCT_FREE
FROM V$ASM_DISKGROUP
WHERE NAME IN ('DATAC3','RECOC3');
EOF
```

**Required free space:**
- DATAC3: At least 5 GB free (for 1.92 GB source)
- RECOC3: At least 5 GB free (for recovery area)

---

### 3.4 Prepare Target Database

**Decision required:** Use existing database or create new?

**Option A: If using existing oradb01m:**
```bash
# Check if oradb01m exists and is suitable
srvctl status database -d oradb01m

# If it contains data from previous attempt, remove it
srvctl stop database -d oradb01m -force
srvctl remove database -d oradb01m
```

**Option B: ZDM will create target database**

ZDM can create the target database during migration. Ensure:
- Target DB Unique Name is specified in RSP file
- ASM disk groups have sufficient space

---

## Phase 4: ZDM Server Configuration

### 4.1 Verify ZDM Installation

```bash
# As zdmuser on ZDM server
export ZDM_HOME=/u01/app/zdmhome
export PATH=$ZDM_HOME/bin:$PATH

# Check ZDM version
$ZDM_HOME/bin/zdmcli -build

# Expected output:
# ZDM BUILD INFO
# BUILD VERSION: 21.x.x.x.x
```

---

### 4.2 Configure OCI CLI

**If OCI CLI not configured:**
```bash
# Create OCI config directory
mkdir -p ~/.oci
chmod 700 ~/.oci

# Create config file
cat > ~/.oci/config << 'EOF'
[DEFAULT]
user=<YOUR_USER_OCID>
fingerprint=<YOUR_FINGERPRINT>
tenancy=<YOUR_TENANCY_OCID>
region=uk-london-1
key_file=/home/zdmuser/.oci/odaa.pem
EOF

chmod 600 ~/.oci/config
```

**Test OCI connectivity:**
```bash
oci os ns get
# Expected: Returns your Object Storage namespace
```

---

### 4.3 Set Up SSH Keys

**Verify key permissions:**
```bash
chmod 600 ~/.ssh/zdm.pem
chmod 600 ~/.ssh/odaa.pem

# Test source connectivity
ssh -i ~/.ssh/zdm.pem oracle@10.1.0.10 "hostname"

# Test target connectivity (as oracle, not opc)
ssh -i ~/.ssh/odaa.pem oracle@10.0.1.160 "hostname"
```

---

### 4.4 Create Password Files (At Migration Time)

> ⚠️ **SECURITY:** Create password files only when ready to migrate. Clean up after completion.

```bash
# Create credentials directory
mkdir -p ~/creds
chmod 700 ~/creds

# Set passwords as environment variables (interactive, secure)
read -sp "Enter Source SYS Password: " SOURCE_SYS_PASSWORD; echo
export SOURCE_SYS_PASSWORD

read -sp "Enter Target SYS Password: " TARGET_SYS_PASSWORD; echo
export TARGET_SYS_PASSWORD

read -sp "Enter TDE Wallet Password: " SOURCE_TDE_WALLET_PASSWORD; echo
export SOURCE_TDE_WALLET_PASSWORD

# Create password files
echo "$SOURCE_SYS_PASSWORD" > ~/creds/source_sys_password.txt
echo "$TARGET_SYS_PASSWORD" > ~/creds/target_sys_password.txt
echo "$SOURCE_TDE_WALLET_PASSWORD" > ~/creds/tde_password.txt

chmod 600 ~/creds/*.txt
```

---

### 4.5 Test ZDM Connectivity

```bash
# Verify ZDM can reach source
$ZDM_HOME/bin/zdmcli query networkconfig \
  -srcnode 10.1.0.10 \
  -srcauth zdmauth \
  -srcsshkeypath /home/zdmuser/.ssh/zdm.pem

# Verify ZDM can reach target  
$ZDM_HOME/bin/zdmcli query networkconfig \
  -tgtnode 10.0.1.160 \
  -tgtauth zdmauth \
  -tgtsshkeypath /home/zdmuser/.ssh/odaa.pem
```

---

## Phase 5: Migration Execution

### 5.1 Run Pre-Migration Evaluation

**Execute evaluation (dry run):**
```bash
# Ensure RSP file is updated with OCI details
cd ~/step3  # or wherever artifacts are located

# Run evaluation
$ZDM_HOME/bin/zdmcli migrate database \
  -rsp zdm_migrate_PRODDB.rsp \
  -sourcedb oradb01 \
  -sourcenode temandin-oravm-vm01 \
  -srcauth zdmauth \
  -srcarg1 user:azureuser \
  -srcarg2 identity_file:/home/zdmuser/.ssh/zdm.pem \
  -srcarg3 sudo_location:/usr/bin/sudo \
  -targetnode tmodaauks-rqahk1 \
  -tgtauth zdmauth \
  -tgtarg1 user:opc \
  -tgtarg2 identity_file:/home/zdmuser/.ssh/odaa.pem \
  -tgtarg3 sudo_location:/usr/bin/sudo \
  -tdekeyloc /u01/app/oracle/admin/oradb01/wallet/tde/ \
  -taboraliasname tde_password \
  -sourcesyswallet /home/zdmuser/creds/source_sys_password.txt \
  -eval
```

**Review evaluation results:**
```bash
# Note the JOB_ID from output
$ZDM_HOME/bin/zdmcli query job -jobid <EVAL_JOB_ID>
```

---

### 5.2 Execute Migration

**Start the migration:**
```bash
$ZDM_HOME/bin/zdmcli migrate database \
  -rsp zdm_migrate_PRODDB.rsp \
  -sourcedb oradb01 \
  -sourcenode temandin-oravm-vm01 \
  -srcauth zdmauth \
  -srcarg1 user:azureuser \
  -srcarg2 identity_file:/home/zdmuser/.ssh/zdm.pem \
  -srcarg3 sudo_location:/usr/bin/sudo \
  -targetnode tmodaauks-rqahk1 \
  -tgtauth zdmauth \
  -tgtarg1 user:opc \
  -tgtarg2 identity_file:/home/zdmuser/.ssh/odaa.pem \
  -tgtarg3 sudo_location:/usr/bin/sudo \
  -tdekeyloc /u01/app/oracle/admin/oradb01/wallet/tde/ \
  -taboraliasname tde_password \
  -sourcesyswallet /home/zdmuser/creds/source_sys_password.txt \
  -targetsyswallet /home/zdmuser/creds/target_sys_password.txt \
  -tdepassword /home/zdmuser/creds/tde_password.txt \
  -pauseafter ZDM_SWITCHOVER_SRC
```

**Record the Job ID:** _______________

---

### 5.3 Monitor Migration Progress

**Check job status:**
```bash
# Replace <JOB_ID> with actual job ID
$ZDM_HOME/bin/zdmcli query job -jobid <JOB_ID>
```

**Monitor Data Guard lag (during redo apply):**
```sql
-- On target database
SELECT NAME, VALUE, UNIT FROM V$DATAGUARD_STATS;
SELECT THREAD#, SEQUENCE#, APPLIED FROM V$ARCHIVED_LOG 
WHERE APPLIED='YES' ORDER BY SEQUENCE# DESC FETCH FIRST 5 ROWS ONLY;
```

**Check migration phases:**

| Phase | Description | Expected Duration |
|-------|-------------|-------------------|
| ZDM_VALIDATE_SRC | Source validation | 2-5 min |
| ZDM_VALIDATE_TGT | Target validation | 2-5 min |
| ZDM_SETUP_SRC | Source configuration | 5-10 min |
| ZDM_SETUP_TGT | Target configuration | 5-10 min |
| ZDM_BACKUP_SRC | Database backup | 10-20 min (for 1.92 GB) |
| ZDM_RESTORE_TGT | Restore on target | 10-20 min |
| ZDM_CONFIGURE_DG_SRC | Data Guard setup | 5-10 min |
| ZDM_SWITCHOVER_SRC | **PAUSED** | Waiting for resume |

---

### 5.4 Pause/Resume Procedures

**When migration pauses at ZDM_SWITCHOVER_SRC:**

1. **Verify redo lag is minimal:**
   ```sql
   -- On target
   SELECT ARCHIVED_SEQ#, APPLIED_SEQ# FROM V$ARCHIVE_DEST_STATUS 
   WHERE DEST_ID=1;
   ```

2. **Notify stakeholders** - switchover is about to happen

3. **Stop applications** connecting to source database

4. **Resume migration:**
   ```bash
   $ZDM_HOME/bin/zdmcli resume job -jobid <JOB_ID>
   ```

---

### 5.5 Switchover Process

ZDM performs switchover automatically when resumed:

1. Final redo log apply
2. Role transition (Primary → Standby on source)
3. Role transition (Standby → Primary on target)
4. Database open on target

**Verify switchover completed:**
```sql
-- On target database
SELECT DATABASE_ROLE, OPEN_MODE FROM V$DATABASE;
-- Expected: PRIMARY, READ WRITE
```

---

## Phase 6: Post-Migration Validation

### 6.1 Database Validation

**On target database:**
```sql
sqlplus / as sysdba << 'EOF'
-- Verify database role
SELECT DATABASE_ROLE, OPEN_MODE, LOG_MODE FROM V$DATABASE;

-- Check database size matches source
SELECT ROUND(SUM(BYTES)/1024/1024/1024, 2) AS SIZE_GB FROM DBA_DATA_FILES;

-- Verify no invalid objects
SELECT COUNT(*) FROM DBA_OBJECTS WHERE STATUS = 'INVALID';

-- Check tablespaces
SELECT TABLESPACE_NAME, STATUS FROM DBA_TABLESPACES;

-- Verify user accounts
SELECT USERNAME, ACCOUNT_STATUS FROM DBA_USERS 
WHERE ORACLE_MAINTAINED = 'N';
EOF
```

---

### 6.2 Data Verification

**Run data validation queries:**
```sql
-- Compare row counts of key tables (customize for your schema)
SELECT 'TABLE_NAME' AS TABLE_NAME, COUNT(*) AS ROW_COUNT 
FROM SCHEMA.TABLE_NAME
UNION ALL
SELECT 'TABLE_NAME2', COUNT(*) FROM SCHEMA.TABLE_NAME2;

-- Verify recent data
SELECT MAX(LAST_UPDATE_DATE) FROM KEY_TRANSACTION_TABLE;
```

---

### 6.3 Application Connectivity Tests

**Update application connection strings:**
```
# New connection string for ODAA
jdbc:oracle:thin:@//tmodaauks-rqahk1:1521/oradb01_tgt
```

**Test connectivity from application servers:**
```bash
# From app server
sqlplus user/password@tmodaauks-rqahk1:1521/oradb01_tgt
```

---

### 6.4 Performance Validation

**Compare performance baselines:**
```sql
-- Check AWR data was migrated (if INCLUDE_AWR=YES)
SELECT SNAP_ID, BEGIN_INTERVAL_TIME 
FROM DBA_HIST_SNAPSHOT 
ORDER BY SNAP_ID DESC 
FETCH FIRST 10 ROWS ONLY;

-- Run a quick performance check
SELECT VALUE FROM V$SYSSTAT WHERE NAME = 'db block gets';
```

---

### 6.5 Post-Migration Cleanup

**Clean up password files:**
```bash
# On ZDM server
rm -f ~/creds/*.txt
rmdir ~/creds
```

**Clean up Data Guard configuration (if no longer needed):**
```bash
# After successful migration and validation period
# Remove Data Guard from source
dgmgrl sys/password@oradb01
DGMGRL> REMOVE DATABASE oradb01;
```

---

### 6.6 Database Link Recreation

**If SYS_HUB database link is needed:**
```sql
-- On target database
CREATE DATABASE LINK SYS_HUB
CONNECT TO SEEDDATA IDENTIFIED BY "<password>"
USING 'tns_alias_for_remote_db';

-- Test the link
SELECT * FROM DUAL@SYS_HUB;
```

---

## Phase 7: Rollback Procedures

### 7.1 Before Switchover

If issues occur before switchover, abort the job:
```bash
$ZDM_HOME/bin/zdmcli abort job -jobid <JOB_ID>
```

The source database remains unchanged and applications continue normally.

---

### 7.2 After Switchover

If rollback is required after switchover:

**Step 1: Stop applications on new target**

**Step 2: Failback to original source**
```bash
# On target (now primary), initiate failover
dgmgrl sys/password@oradb01_tgt
DGMGRL> FAILOVER TO oradb01;
```

**Step 3: Restart applications on original source**

**Step 4: Remove failed target configuration**
```sql
-- Clean up on original source
ALTER DATABASE DROP STANDBY LOGFILE GROUP n;
```

---

### 7.3 Emergency Contacts

| Situation | Contact | Phone |
|-----------|---------|-------|
| Database Emergency | DBA On-call | _______________ |
| Network Issues | Network Team | _______________ |
| Oracle Support | MOS SR | _______________ |
| Application Issues | App Team | _______________ |

---

## Appendix A: Troubleshooting

### Common Issues and Solutions

#### Issue: OCI Authentication Failed

**Symptoms:**
```
Error: OCI API authentication failed
```

**Solution:**
```bash
# Verify OCI config
cat ~/.oci/config

# Test OCI connectivity
oci os ns get

# Check API key fingerprint matches
oci iam user api-key list --user-id <user-ocid>
```

---

#### Issue: SSH Connection Failed

**Symptoms:**
```
Error: Cannot connect to source/target node
```

**Solution:**
```bash
# Test SSH manually
ssh -v -i ~/.ssh/zdm.pem oracle@10.1.0.10

# Check key permissions
ls -la ~/.ssh/*.pem
# Should be: -rw------- (600)

# Verify authorized_keys on remote host
cat /home/oracle/.ssh/authorized_keys
```

---

#### Issue: TNS Connection Failed

**Symptoms:**
```
ORA-12541: TNS:no listener
ORA-12545: Connect failed because target host or object does not exist
```

**Solution:**
```bash
# Test port connectivity
nc -zv 10.1.0.10 1521

# Check listener status on source/target
lsnrctl status

# Verify tnsnames.ora
cat $ORACLE_HOME/network/admin/tnsnames.ora
```

---

#### Issue: Insufficient Disk Space

**Symptoms:**
```
Error: Insufficient space in /u01/app/zdmhome
```

**Solution:**
```bash
# Check current usage
df -h /u01/app/zdmhome

# Clean old ZDM jobs
$ZDM_HOME/bin/zdmcli query job -listall
# Identify old completed jobs and remove their directories

# Expand storage if LVM
sudo lvextend -L +20G /dev/mapper/vg_zdm-lv_zdm
sudo xfs_growfs /u01/app/zdmhome
```

---

#### Issue: Data Guard Lag Too High

**Symptoms:**
```
Redo apply lag > 60 seconds
```

**Solution:**
```sql
-- Check archive log status
SELECT THREAD#, SEQUENCE#, APPLIED FROM V$ARCHIVED_LOG 
WHERE APPLIED='NO' ORDER BY SEQUENCE#;

-- Check Data Guard stats
SELECT NAME, VALUE FROM V$DATAGUARD_STATS;

-- Verify network throughput between source and target
```

---

#### Issue: Job Stuck in Phase

**Symptoms:**
```
Job status shows same phase for extended period
```

**Solution:**
```bash
# Check detailed job phase
$ZDM_HOME/bin/zdmcli query job -jobid <JOB_ID>

# Check ZDM logs
tail -100 $ZDM_HOME/zdm/log/zdm.log

# If safe to retry
$ZDM_HOME/bin/zdmcli resume job -jobid <JOB_ID>
```

---

## Appendix B: Command Reference

### ZDM CLI Commands

| Command | Purpose |
|---------|---------|
| `zdmcli migrate database -eval` | Evaluate migration (dry run) |
| `zdmcli migrate database` | Execute migration |
| `zdmcli query job -jobid <ID>` | Check job status |
| `zdmcli query job -listall` | List all jobs |
| `zdmcli resume job -jobid <ID>` | Resume paused job |
| `zdmcli abort job -jobid <ID>` | Abort running job |
| `zdmcli suspend job -jobid <ID>` | Suspend running job |

---

## Appendix C: File Locations Reference

| File | Location |
|------|----------|
| ZDM Home | /u01/app/zdmhome |
| ZDM CLI | /u01/app/zdmhome/bin/zdmcli |
| ZDM Logs | /u01/app/zdmhome/zdm/log/ |
| OCI Config | /home/zdmuser/.oci/config |
| SSH Keys | /home/zdmuser/.ssh/ |
| RSP File | ~/step3/zdm_migrate_PRODDB.rsp |
| Source Oracle Home | /u01/app/oracle/product/19.0.0/dbhome_1 |
| Target Oracle Home | /u02/app/oracle/product/19.0.0.0/dbhome_1 |
| Target Grid Home | /u01/app/19.0.0.0/grid |
| Source TDE Wallet | /u01/app/oracle/admin/oradb01/wallet/tde/ |
| Source Password File | /u01/app/oracle/product/19.0.0/dbhome_1/dbs/orapworadb01 |

---

*Generated by ZDM Migration Planning - Step 3*
*Date: 2026-02-03*
