# ZDM Migration Runbook: ORADB
## Migration: Azure IaaS Oracle 12.2 → Oracle Database@Azure (ExaDB-D) 19c

### Document Information

| Field | Value |
|-------|-------|
| Source Database | ORADB1 · Oracle 12.2.0.1 CDB · `tm-oracle-iaas` (10.1.0.11) |
| Target Database | oradb01 / oradb011 · Oracle 19c ExaDB-D · `tmodaauks-rqahk1` (10.0.1.160) |
| ZDM Server | `tm-vm-odaa-oracle-jumpbox` (10.1.0.8) · ZDM Home: `/u01/app/zdmhome` |
| Migration Type | ONLINE_PHYSICAL — Data Guard replication |
| Backup Staging | Azure Blob Storage — account `tmmigrate` / container `zdm` |
| DG Protection Mode | MAXIMUM_PERFORMANCE / ASYNC |
| Pause Point | ZDM_CONFIGURE_DG_SRC (manual validation before replication) |
| Auto Switchover | No — manual switchover |
| Oracle Home (Source) | `/u01/app/oracle/product/12.2.0/dbhome_1` |
| Oracle Home (Target) | `/u02/app/oracle/product/19.0.0.0/dbhome_1` |
| Created Date | 2026-03-05 |

---

## Phase 1: Pre-Migration Verification

### 1.1 Source Database Checks

Run as `azureuser` on ZDM server, via SSH to source:

```bash
ssh -i ~/.ssh/odaa.pem azureuser@10.1.0.11 "sudo -u oracle bash -c '
  export ORACLE_HOME=/u01/app/oracle/product/12.2.0/dbhome_1
  export ORACLE_SID=oradb
  export PATH=\$ORACLE_HOME/bin:\$PATH
  sqlplus -S / as sysdba <<EOF
SET LINESIZE 120 PAGES 50
SELECT NAME, DB_UNIQUE_NAME, LOG_MODE, FORCE_LOGGING, CDB FROM V\\\$DATABASE;
SELECT STATUS FROM V\\\$INSTANCE;
SELECT VALUE FROM V\\\$PARAMETER WHERE NAME='"'"'db_recovery_file_dest'"'"';
SELECT * FROM V\\\$RECOVERY_FILE_DEST;
SELECT PERCENT_SPACE_USED, PERCENT_SPACE_RECLAIMABLE, NUMBER_OF_FILES FROM V\\\$FLASH_RECOVERY_AREA_USAGE;
EXIT;
EOF
'"
```

**Expected results:**
- `LOG_MODE = ARCHIVELOG` ✅ (confirmed in discovery)
- `FORCE_LOGGING = YES` ✅ (confirmed in discovery)
- `CDB = YES` ✅ (confirmed in discovery)
- STATUS = OPEN
- FRA space < 70% used

Check supplemental logging:
```bash
ssh -i ~/.ssh/odaa.pem azureuser@10.1.0.11 "sudo -u oracle bash -c '
  export ORACLE_HOME=/u01/app/oracle/product/12.2.0/dbhome_1
  export ORACLE_SID=oradb
  export PATH=\$ORACLE_HOME/bin:\$PATH
  sqlplus -S / as sysdba <<EOF
SELECT LOG_MODE, SUPPLEMENTAL_LOG_DATA_MIN FROM V\\\$DATABASE;
EXIT;
EOF
'"
```

Check password file exists:
```bash
ssh -i ~/.ssh/odaa.pem azureuser@10.1.0.11 \
  "sudo -u oracle ls -la /u01/app/oracle/product/12.2.0/dbhome_1/dbs/orapworadb"
# Expected: file exists with owner oracle, permissions 640
```

Check disk space on source:
```bash
ssh -i ~/.ssh/odaa.pem azureuser@10.1.0.11 "df -h && df -h /u01"
# Expected: ≥ 10 GB free on root and /u01
# Note: Step2 Issue 7 — source root was 81% used (5.6 GB free). Verify before migration.
```

### 1.2 Target Database Checks

```bash
ssh -i ~/.ssh/odaa.pem opc@10.0.1.160 "sudo -u oracle bash -c '
  export ORACLE_HOME=/u02/app/oracle/product/19.0.0.0/dbhome_1
  export ORACLE_SID=oradb011
  export PATH=\$ORACLE_HOME/bin:\$PATH
  sqlplus -S / as sysdba <<EOF
SELECT OPEN_MODE, DB_UNIQUE_NAME, DATABASE_ROLE FROM V\\\$DATABASE;
SELECT NAME, OPEN_MODE FROM V\\\$PDBS;
EXIT;
EOF
'"
# Expected: OPEN_MODE = READ WRITE
```

Verify password file on target (confirmed by verify_fixes.sh):
```bash
ssh -i ~/.ssh/odaa.pem opc@10.0.1.160 \
  "sudo -u oracle ls -la /u02/app/oracle/product/19.0.0.0/dbhome_1/dbs/orapworadb01"
# Expected: file exists, owner oracle, permissions 640
```

Verify TNS listener on target:
```bash
ssh -i ~/.ssh/odaa.pem opc@10.0.1.160 "sudo -u oracle bash -c '
  export ORACLE_HOME=/u02/app/oracle/product/19.0.0.0/dbhome_1
  export PATH=\$ORACLE_HOME/bin:\$PATH
  lsnrctl status'"
# Expected: listener running; services oradb01, oradb011, oradb01XDB visible
```

### 1.3 ZDM Server Checks

```bash
# Switch to zdmuser
sudo su - zdmuser

# Verify ZDM is installed and running
/u01/app/zdmhome/bin/zdmcli -version

# Check ZDM service status
/u01/app/zdmhome/bin/zdmservice status

# Verify SSH connectivity to source
ssh -i ~/.ssh/odaa.pem azureuser@10.1.0.11 "echo 'Source SSH OK'"

# Verify SSH connectivity to target
ssh -i ~/.ssh/odaa.pem opc@10.0.1.160 "echo 'Target SSH OK'"

# Verify Azure Blob credentials
cat ~/.azure/zdm_blob_creds
# Expected: contains AZURE_STORAGE_ACCOUNT and AZURE_STORAGE_KEY (or SAS token)

# Check disk space on ZDM server
df -h
# Expected: ≥ 10 GB free (confirmed 23 GB free in Step2)
```

### 1.4 Network Connectivity Checks

Ports confirmed OPEN from ZDM server to both source and target (verified in Step 2):

| Connection | Protocol | Port | Status |
|-----------|----------|------|--------|
| ZDM → Source (10.1.0.11) | SSH | 22 | ✅ OPEN |
| ZDM → Source (10.1.0.11) | Oracle | 1521 | ✅ OPEN |
| ZDM → Target (10.0.1.160) | SSH | 22 | ✅ OPEN |
| ZDM → Target (10.0.1.160) | Oracle | 1521 | ✅ OPEN |

> Note: ICMP (ping) to target ODAA 10.0.1.160 shows PING_FAILED — this is expected. ZDM uses TCP port 22/1521, not ICMP.

---

## Phase 2: Source Database Configuration

> Most source configuration was confirmed ready in Step 1 and Step 2. Run these only if pre-migration checks show issues.

### 2.1 Archive Log Mode (Already Enabled)

```sql
-- Already ARCHIVELOG as confirmed in discovery. No action needed.
-- If re-verification fails:
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;
ARCHIVE LOG LIST;
```

### 2.2 Force Logging (Already Enabled)

```sql
-- Confirmed YES in discovery. No action needed.
-- If re-verification shows NO:
ALTER DATABASE FORCE LOGGING;
SELECT FORCE_LOGGING FROM V$DATABASE;  -- Expected: YES
```

### 2.3 Supplemental Logging (Already Enabled)

```sql
-- Confirmed SUPPLEMENTAL_LOG_DATA_MIN = YES in discovery.
-- For physical migration, minimal supplemental logging is sufficient.
-- No action needed unless ZDM eval reports otherwise.
```

### 2.4 TDE Configuration (⚠️ DBA Decision Required — See Issue 4)

**Only perform this section after TDE strategy is confirmed with Oracle ODAA support.**

If TDE is required (Option A — Enable on source):

```sql
-- Run on source as SYS (ORADB1 CDB root)
export ORACLE_HOME=/u01/app/oracle/product/12.2.0/dbhome_1
export ORACLE_SID=oradb

-- Create and open software keystore
ADMINISTER KEY MANAGEMENT
  CREATE KEYSTORE '/u01/app/oracle/product/12.2.0/dbhome_1/admin/oradb/wallet'
  IDENTIFIED BY "<TDE_WALLET_PASSWORD>";

ADMINISTER KEY MANAGEMENT
  SET KEYSTORE OPEN
  IDENTIFIED BY "<TDE_WALLET_PASSWORD>";

ADMINISTER KEY MANAGEMENT
  SET KEY IDENTIFIED BY "<TDE_WALLET_PASSWORD>" WITH BACKUP;

-- Verify CDB root
SELECT * FROM V$ENCRYPTION_WALLET;
-- Expected: STATUS = OPEN, WALLET_TYPE = PASSWORD

-- For each PDB in the CDB:
ALTER SESSION SET CONTAINER = PDB1;
ADMINISTER KEY MANAGEMENT
  SET KEY IDENTIFIED BY "<TDE_WALLET_PASSWORD>" WITH BACKUP CONTAINER = CURRENT;
```

After enabling TDE, set `TDE_ENABLED=true` in `zdm_commands_ORADB.sh` and set the environment variable:
```bash
read -sp "TDE wallet password: " SOURCE_TDE_WALLET_PASSWORD; echo; export SOURCE_TDE_WALLET_PASSWORD
```

### 2.5 Verify Source Password File

```bash
ssh -i ~/.ssh/odaa.pem azureuser@10.1.0.11 \
  "sudo -u oracle ls -la /u01/app/oracle/product/12.2.0/dbhome_1/dbs/orapworadb"
```

### 2.6 Verify Source TNS Configuration

```bash
ssh -i ~/.ssh/odaa.pem azureuser@10.1.0.11 "sudo -u oracle bash -c '
  export ORACLE_HOME=/u01/app/oracle/product/12.2.0/dbhome_1
  export PATH=\$ORACLE_HOME/bin:\$PATH
  tnsping ORADB1'"
```

---

## Phase 3: Target Database Configuration

### 3.1 Verify Target Database is Open (READ WRITE)

```bash
ssh -i ~/.ssh/odaa.pem opc@10.0.1.160 "sudo -u oracle bash -c '
  export ORACLE_HOME=/u02/app/oracle/product/19.0.0.0/dbhome_1
  export ORACLE_SID=oradb011
  export PATH=\$ORACLE_HOME/bin:\$PATH
  sqlplus -S / as sysdba <<EOF
SELECT OPEN_MODE FROM V\\\$DATABASE;
EXIT;
EOF
'"
# Expected: READ WRITE
# If MOUNT: ALTER DATABASE OPEN;  (see fix_open_target_db.sh from Step2)
```

### 3.2 Verify Target Password File (Confirmed by verify_fixes.sh)

```bash
ssh -i ~/.ssh/odaa.pem opc@10.0.1.160 \
  "sudo -u oracle ls -la /u02/app/oracle/product/19.0.0.0/dbhome_1/dbs/orapworadb01"
# Expected: -rw-r----- 1 oracle oinstall ... orapworadb01
```

### 3.3 Set TDE Master Key on Target (If TDE Strategy Requires It)

```bash
ssh -i ~/.ssh/odaa.pem opc@10.0.1.160 "sudo -u oracle bash -c '
  export ORACLE_HOME=/u02/app/oracle/product/19.0.0.0/dbhome_1
  export ORACLE_SID=oradb011
  export PATH=\$ORACLE_HOME/bin:\$PATH
  sqlplus -S / as sysdba <<EOF
-- Check current wallet status
SELECT WRL_TYPE, STATUS, WALLET_TYPE FROM V\\\$ENCRYPTION_WALLET;
EXIT;
EOF
'"
# Expected after TDE setup: STATUS = OPEN
```

### 3.4 Verify Target Listener and TNS

```bash
ssh -i ~/.ssh/odaa.pem opc@10.0.1.160 "sudo -u oracle bash -c '
  export ORACLE_HOME=/u02/app/oracle/product/19.0.0.0/dbhome_1
  export PATH=\$ORACLE_HOME/bin:\$PATH
  lsnrctl status | grep -E \"Service|Status\"'"
```

---

## Phase 4: ZDM Server Configuration

### 4.1 Login to ZDM Server

```bash
# From your workstation:
ssh -i ~/.ssh/zdm.pem azureuser@10.1.0.8

# Switch to zdmuser:
sudo su - zdmuser

# Verify you are zdmuser:
whoami          # expected: zdmuser
echo $HOME      # expected: /home/zdmuser
```

### 4.2 Clone Repository and Navigate to Artifacts

```bash
# If not already cloned:
cd ~
git clone <your-migration-repo-fork-url>
cd ~/GHCP-ODAA-PromptMigration

# If already cloned — pull latest:
cd ~/GHCP-ODAA-PromptMigration
git pull

# Navigate to Step3 artifacts:
cd Artifacts/Phase10-Migration/ZDM/ORADB/Step3
ls -la
```

### 4.3 Run Init Script (First Time Only)

```bash
bash zdm_commands_ORADB.sh init
```

This creates:
- `~/creds/` directory (chmod 700)
- `~/zdm_oci_env.sh` — template file for OCI environment variables

### 4.4 Populate OCI Environment File

```bash
# Edit ~/zdm_oci_env.sh and fill in the OCI OCID values:
vi ~/zdm_oci_env.sh

# The file should contain:
# export TARGET_TENANCY_OCID="ocid1.tenancy.oc1..aaaaaaaarvyhjcn7wkkxxx5g3o7lgqks23bmsjtsticz3gtg5xs5qyrwkftq"
# export TARGET_USER_OCID="ocid1.user.oc1..aaaaaaaakfe5cirdq7vkkrhogjrgcrgftvwb7mdoehujgchefpqv54vhsnoa"
# export TARGET_COMPARTMENT_OCID="ocid1.compartment.oc1..aaaaaaaas4upnqj72dfiivgwvn3uui5gkxo7ng6leeoifucbjiy326urbhmq"
# export TARGET_DATABASE_OCID="ocid1.database.oc1.uk-london-1.anwgiljss56liuaatz45cjnpbvpgku7gkorvxg6lytoj5lxxruk2eqxzkzma"
# export TARGET_FINGERPRINT="<OCI_API_KEY_FINGERPRINT>"
# ⚠️ NOTE: The current OCI user is a federated IDCSApp user with API keys disabled.
#    If ZDM requires OCI API authentication, an OCI admin must provision a service account
#    or enable API keys for a dedicated migration user. Contact OCI admin if eval fails with OCI auth error.
```

### 4.5 Set Password Environment Variables (Runtime — Do Not Save to File)

```bash
# Set securely at the terminal — values are in memory only, never written to disk
read -sp "Source SYS password: " SOURCE_SYS_PASSWORD; echo; export SOURCE_SYS_PASSWORD
read -sp "Target SYS password: " TARGET_SYS_PASSWORD; echo; export TARGET_SYS_PASSWORD

# Only if TDE is enabled (after DBA confirms TDE strategy):
# read -sp "TDE wallet password: " SOURCE_TDE_WALLET_PASSWORD; echo; export SOURCE_TDE_WALLET_PASSWORD
```

### 4.6 Source OCI Environment Variables

```bash
source ~/zdm_oci_env.sh

# Verify variables are set:
echo "Tenancy: $TARGET_TENANCY_OCID"
echo "Database: $TARGET_DATABASE_OCID"
```

### 4.7 Create Temporary Password Files

```bash
bash zdm_commands_ORADB.sh create-creds
# Creates: ~/creds/source_sys_password.txt (chmod 600)
#          ~/creds/target_sys_password.txt (chmod 600)
#          ~/creds/tde_password.txt (only if TDE_ENABLED=true)
```

### 4.8 Verify ZDM Installation

```bash
/u01/app/zdmhome/bin/zdmcli -version
/u01/app/zdmhome/bin/zdmservice status
# Expected: service running
```

### 4.9 Verify Azure Blob Storage Credentials

```bash
# Verify credentials file is present:
ls -la ~/.azure/zdm_blob_creds
# Expected: -rw------- (chmod 600)

# Source credentials (if not already in environment):
source ~/.azure/zdm_blob_creds
echo "Azure account: $AZURE_STORAGE_ACCOUNT"
```

---

## Phase 5: Migration Execution

### 5.1 Run Evaluation (Dry Run — No Changes Made)

```bash
# Ensure you are in the Step3 directory as zdmuser:
cd ~/GHCP-ODAA-PromptMigration/Artifacts/Phase10-Migration/ZDM/ORADB/Step3

bash zdm_commands_ORADB.sh eval
```

**Review evaluation output carefully:**
- All check items should show `✓` or `PASS`
- Pay attention to ZDM_VALIDATE_TGT — this is where prior jobs (18–34) failed due to TDE mismatch
- If TDE-related failures occur: see Issue 4 in `Issue-Resolution-Log-ORADB.md`
- Note the evaluation JOB_ID for reference

### 5.2 Review Evaluation Job Output

```bash
# Replace <EVAL_JOB_ID> with the ID from the eval command output:
bash zdm_commands_ORADB.sh status <EVAL_JOB_ID>

# For detailed log:
/u01/app/zdmhome/bin/zdmcli query job -jobid <EVAL_JOB_ID>

# View ZDM log for this job:
cat /u01/app/zdmhome/log/zdmhost/zdm_<EVAL_JOB_ID>*/zdm*.log 2>/dev/null | tail -100
```

### 5.3 Execute Migration

> ⚠️ Only proceed after successful evaluation with no blocking issues.

```bash
bash zdm_commands_ORADB.sh migrate
# Output: ZDM JOB_ID printed — record this number
# Example: "Job ID: 42"
```

**The job will progress through these phases:**

| Phase | Description |
|-------|-------------|
| ZDM_VALIDATE_SRC | SSH + Oracle connectivity to source |
| ZDM_VALIDATE_TGT | SSH + Oracle connectivity to target |
| ZDM_SETUP_SRC | Install ZDM agent on source |
| ZDM_SETUP_TGT | Install ZDM agent on target |
| ZDM_BACKUP_FULL_SRC | RMAN full backup to Azure Blob |
| ZDM_RESTORE_TGT | Restore backup to target via RMAN |
| ZDM_SETUP_TDE_TGT | Configure TDE on target (if TDE enabled) |
| ZDM_CONFIGURE_DG_SRC | Configure Data Guard — **⚠️ JOB PAUSES HERE** |
| _(manual resume required below)_ | |
| ZDM_MONITOR_REDO | Monitor redo lag |
| ZDM_SWITCHOVER_SRC | Initiate switchover |
| ZDM_SWITCHOVER_TGT | Complete switchover |
| ZDM_POST_MIGRATION | Post-migration cleanup |

### 5.4 Monitor Migration Progress

```bash
# Poll job status (run every few minutes):
bash zdm_commands_ORADB.sh status <JOB_ID>

# Or run continuous monitoring (Ctrl+C to stop):
watch -n 30 "/u01/app/zdmhome/bin/zdmcli query job -jobid <JOB_ID>"
```

### 5.5 Resume at Pause Point (ZDM_CONFIGURE_DG_SRC)

When the job pauses at `ZDM_CONFIGURE_DG_SRC`, perform these manual validations before resuming:

**Validate Data Guard is configured on target:**

```bash
ssh -i ~/.ssh/odaa.pem opc@10.0.1.160 "sudo -u oracle bash -c '
  export ORACLE_HOME=/u02/app/oracle/product/19.0.0.0/dbhome_1
  export ORACLE_SID=oradb011
  export PATH=\$ORACLE_HOME/bin:\$PATH
  sqlplus -S / as sysdba <<EOF
SELECT DATABASE_ROLE, PROTECTION_MODE, PROTECTION_LEVEL FROM V\\\$DATABASE;
SELECT THREAD#, SEQUENCE#, APPLIED FROM V\\\$ARCHIVED_LOG ORDER BY SEQUENCE# DESC FETCH FIRST 5 ROWS ONLY;
EXIT;
EOF
'"
# Expected: DATABASE_ROLE = PHYSICAL STANDBY
```

**Check redo transport lag on source:**

```bash
ssh -i ~/.ssh/odaa.pem azureuser@10.1.0.11 "sudo -u oracle bash -c '
  export ORACLE_HOME=/u01/app/oracle/product/12.2.0/dbhome_1
  export ORACLE_SID=oradb
  export PATH=\$ORACLE_HOME/bin:\$PATH
  sqlplus -S / as sysdba <<EOF
SELECT NAME, VALUE FROM V\\\$DATAGUARD_STATS WHERE NAME LIKE '"'"'transport lag'"'"';
SELECT NAME, VALUE FROM V\\\$DATAGUARD_STATS WHERE NAME LIKE '"'"'apply lag'"'"';
EXIT;
EOF
'"
# Expected: transport lag and apply lag are 0 or near 0
```

**Resume the job after DBA validation:**

```bash
bash zdm_commands_ORADB.sh resume <JOB_ID>
```

### 5.6 Switchover

> ⚠️ The switchover converts the source ORADB1 to a standby and promotes oradb01 to primary. Coordinate with application owners before this step.

**Pre-switchover checklist:**
- [ ] Application connections quiesced or pointed to maintenance page
- [ ] Redo lag confirmed at 0 (or acceptable minimum)
- [ ] DBA team notified and ready
- [ ] Rollback plan reviewed (see Phase 7)

ZDM performs the switchover automatically after resume if no additional pause is set. Monitor with:

```bash
bash zdm_commands_ORADB.sh status <JOB_ID>
```

**Post-switchover — verify new primary:**

```bash
ssh -i ~/.ssh/odaa.pem opc@10.0.1.160 "sudo -u oracle bash -c '
  export ORACLE_HOME=/u02/app/oracle/product/19.0.0.0/dbhome_1
  export ORACLE_SID=oradb011
  export PATH=\$ORACLE_HOME/bin:\$PATH
  sqlplus -S / as sysdba <<EOF
SELECT DATABASE_ROLE, OPEN_MODE, DB_UNIQUE_NAME FROM V\\\$DATABASE;
EXIT;
EOF
'"
# Expected: DATABASE_ROLE = PRIMARY, OPEN_MODE = READ WRITE
```

---

## Phase 6: Post-Migration Validation

### 6.1 Data Integrity Checks on Target

```bash
ssh -i ~/.ssh/odaa.pem opc@10.0.1.160 "sudo -u oracle bash -c '
  export ORACLE_HOME=/u02/app/oracle/product/19.0.0.0/dbhome_1
  export ORACLE_SID=oradb011
  export PATH=\$ORACLE_HOME/bin:\$PATH
  sqlplus -S / as sysdba <<EOF
-- Check database status
SELECT NAME, DB_UNIQUE_NAME, OPEN_MODE, DATABASE_ROLE, LOG_MODE FROM V\\\$DATABASE;

-- Check CDB and PDB status
SELECT CON_ID, NAME, OPEN_MODE FROM V\\\$PDBS;

-- Check character set
SELECT VALUE FROM NLS_DATABASE_PARAMETERS WHERE PARAMETER='"'"'NLS_CHARACTERSET'"'"';

-- Quick row count spot check of key tables (example)
SELECT COUNT(*) FROM DBA_TABLES;
SELECT COUNT(*) FROM DBA_OBJECTS;
EXIT;
EOF
'"
```

Expected values:
- DB_UNIQUE_NAME = `oradb01`
- OPEN_MODE = `READ WRITE`
- DATABASE_ROLE = `PRIMARY`
- NLS_CHARACTERSET = `AL32UTF8` (matches source)

### 6.2 Application Connectivity Test

Test that applications can connect to the target database service:

```bash
# From ZDM server (represents network path):
ssh -i ~/.ssh/odaa.pem opc@10.0.1.160 "sudo -u oracle bash -c '
  export ORACLE_HOME=/u02/app/oracle/product/19.0.0.0/dbhome_1
  export PATH=\$ORACLE_HOME/bin:\$PATH
  tnsping oradb01'"
```

### 6.3 Performance Baseline Validation

```bash
ssh -i ~/.ssh/odaa.pem opc@10.0.1.160 "sudo -u oracle bash -c '
  export ORACLE_HOME=/u02/app/oracle/product/19.0.0.0/dbhome_1
  export ORACLE_SID=oradb011
  export PATH=\$ORACLE_HOME/bin:\$PATH
  sqlplus -S / as sysdba <<EOF
-- Check top wait events  
SELECT EVENT, TOTAL_WAITS, TIME_WAITED FROM V\\\$SYSTEM_EVENT
  WHERE WAIT_CLASS != '"'"'Idle'"'"' ORDER BY TIME_WAITED DESC FETCH FIRST 10 ROWS ONLY;
EXIT;
EOF
'"
```

### 6.4 Cleanup Credentials Files

```bash
bash zdm_commands_ORADB.sh cleanup-creds
# Removes ~/creds/*.txt securely
```

---

## Phase 7: Rollback Procedures

### 7.1 Abort Migration Before Switchover

If issues are found before switchover begins (before ZDM_SWITCHOVER_SRC), abort the job:

```bash
bash zdm_commands_ORADB.sh abort <JOB_ID>
# Source database is unaffected — it remains PRIMARY throughout
```

Then check source database is healthy:

```bash
ssh -i ~/.ssh/odaa.pem azureuser@10.1.0.11 "sudo -u oracle bash -c '
  export ORACLE_HOME=/u01/app/oracle/product/12.2.0/dbhome_1
  export ORACLE_SID=oradb
  export PATH=\$ORACLE_HOME/bin:\$PATH
  sqlplus -S / as sysdba <<EOF
SELECT DATABASE_ROLE, OPEN_MODE FROM V\\\$DATABASE;
EXIT;
EOF
'"
# Expected: PRIMARY / READ WRITE
```

Clean up ZDM agents installed on source/target during the job:

```bash
# Run as zdmuser on ZDM server
/u01/app/zdmhome/bin/zdmcli cleanup job -jobid <JOB_ID>
```

### 7.2 Rollback After Switchover (Emergency)

If switchover has begun or completed and issues arise:

1. **If switchover in progress (ZDM_SWITCHOVER_SRC/TGT phase):**
   - Do NOT abort — let ZDM complete to a clean state
   - Oracle Data Guard switchover is a two-step process; interrupting midway can cause both databases to be in limbo

2. **If switchover completed but issues discovered on target (PRIMARY = oradb01):**
   - Perform a manual Data Guard switchover back to source (oradb1 becomes primary again):
     ```sql
     -- On target (now PRIMARY = oradb011) as SYS:
     ALTER DATABASE COMMIT TO SWITCHOVER TO PHYSICAL STANDBY WITH SESSION SHUTDOWN;
     STARTUP MOUNT;
     -- On source (now STANDBY = oradb) as SYS:
     ALTER DATABASE COMMIT TO SWITCHOVER TO PRIMARY WITH SESSION SHUTDOWN;
     ALTER DATABASE OPEN;
     ```
   - Contact Oracle ODAA support for assistance: this is a non-trivial operation

3. **Always document the issue and contact Oracle support before attempting manual rollback.**

---

## Appendix A: Troubleshooting

### ZDM_VALIDATE_TGT Failure (TDE-related)

- **Symptom:** Job fails at `ZDM_VALIDATE_TGT` with TDE-related message (seen in prior jobs 18–34)
- **Cause:** Target ODAA wallet has `OPEN_NO_MASTER_KEY` status; ODAA requires a master encryption key
- **Resolution:** Confirm TDE strategy (Issue 4 from Step2); enable TDE on source if required; set TDE master key on target

### OCI Authentication Failure

- **Symptom:** ZDM reports OCI API authentication failure
- **Cause:** The OCI user (`temandin@microsoft.com`) is a federated IDCSApp user; API keys are disabled
- **Resolution:** Contact OCI admin to provision a non-federated OCI service account or enable Instance Principal for the ZDM VM. Update RSP file `OCIAUTHENTICATION_*` parameters.

### Azure Blob Storage Access Failure

- **Symptom:** ZDM cannot write backup pieces to Azure Blob
- **Cause:** Credentials in `~/.azure/zdm_blob_creds` expired or incorrect
- **Resolution:** Re-run `fix_azure_blob_storage.sh` from Step2/Scripts; obtain new access key/SAS token from Azure portal

### SSH Key Authentication Failure

- **Symptom:** `ZDM_VALIDATE_SRC` or `ZDM_VALIDATE_TGT` fails with SSH auth error
- **Cause:** Wrong key or key permissions
- **Resolution:** Confirm key works: `ssh -i ~/.ssh/odaa.pem azureuser@10.1.0.11 "echo OK"`. Ensure `/.ssh/odaa.pem` is `chmod 600`, owned by `zdmuser`.

### Source Disk Space Exhaustion During Migration

- **Symptom:** RMAN backup fails or job hangs with `ORA-19504` / `ORA-27040`
- **Cause:** Source root filesystem or FRA full (Issue 7 — 81% at start; 5.6 GB free)
- **Resolution:** Purge obsolete RMAN backups: `RMAN: DELETE NOPROMPT OBSOLETE;` OR relocate FRA to `/mnt/resource` (ephemeral — caution: data lost on VM restart)

### Target Database in MOUNT State

- **Symptom:** `ZDM_VALIDATE_TGT` fails; target DB not accessible
- **Cause:** Target ODAA DB was in MOUNT state at discovery (Issue 3)
- **Resolution:** Open database: `ALTER DATABASE OPEN;` on target (see `fix_open_target_db.sh` from Step2)

---

## Appendix B: Useful ZDM Commands

```bash
# Check job status
/u01/app/zdmhome/bin/zdmcli query job -jobid <JOB_ID>

# List all jobs
/u01/app/zdmhome/bin/zdmcli query jobid -all

# Resume a paused job
/u01/app/zdmhome/bin/zdmcli resume job -jobid <JOB_ID>

# Abort a job
/u01/app/zdmhome/bin/zdmcli abort job -jobid <JOB_ID>

# Clean up job artifacts
/u01/app/zdmhome/bin/zdmcli cleanup job -jobid <JOB_ID>

# View ZDM logs
ls /u01/app/zdmhome/log/zdmhost/
tail -100 /u01/app/zdmhome/log/zdmhost/zdm_<JOB_ID>*/zdm*.log
```

---

*Generated by ZDM Migration Planning — Step 3 | 2026-03-05*
