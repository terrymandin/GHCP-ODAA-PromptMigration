# Issue Resolution Log: ORADB

| Field | Value |
|---|---|
| **Project** | ORADB |
| **Document** | Issue Resolution Log |
| **Generated** | 2026-02-27 |
| **Based On** | Discovery Summary dated 2026-02-27 |
| **Migration Method** | ONLINE_PHYSICAL (recommended) — pending ARCHIVELOG enablement |

---

## Summary

| # | Issue | Category | Priority | Status | Date Resolved | Verified By |
|---|-------|----------|----------|--------|---------------|-------------|
| ACTION-01 | Enable ARCHIVELOG Mode on Source | ❌ Blocker | CRITICAL | 🔲 Pending | | |
| ACTION-02 | Enable Force Logging on Source | ❌ Blocker | CRITICAL | 🔲 Pending | | |
| ACTION-03 | Enable Supplemental Logging on Source | ❌ Blocker | CRITICAL | 🔲 Pending | | |
| ACTION-04 | Configure TDE Master Key on Target | ⚠️ Required | HIGH | 🔲 Pending | | |
| ACTION-05 | Discover OCI Object Storage Namespace | ⚠️ Required | HIGH | 🔲 Pending | | |
| ACTION-06 | Create OCI Object Storage Bucket | ⚠️ Required | HIGH | 🔲 Pending | | |
| ACTION-07 | Initialize ZDM Credential Store | ⚠️ Required | HIGH | 🔲 Pending | | |
| ACTION-08 | Configure Archive Log Destination | ⚡ Recommended | MEDIUM | 🔲 Pending | | |
| ACTION-09 | Configure RMAN on Source | ⚡ Recommended | MEDIUM | 🔲 Pending | | |
| ACTION-10 | Verify SSH Key Access (zdmuser → source/target) | ⚡ Recommended | MEDIUM | 🔲 Pending | | |
| ACTION-11 | Verify Oracle User SSH Access from ZDM | ⚡ Recommended | MEDIUM | 🔲 Pending | | |
| ACTION-12 | Update zdm-env.md with Missing Values | ⚠️ Required | MEDIUM | 🔲 Pending | | |

> **Completion Rule:** All CRITICAL and HIGH items must be ✅ Resolved before proceeding to Step 3.

---

## Remediation Scripts (Quick Reference)

| Script | Purpose | Run As | Run Where |
|--------|---------|--------|-----------|
| `Scripts/fix_01_source_archivelog.sh` | Enable ARCHIVELOG + Force Logging + Supplemental Logging | azureuser (sudo to oracle) | ZDM Server → SSH to Source |
| `Scripts/fix_02_target_tde_master_key.sh` | Create TDE Master Key on target CDB | opc (sudo to oracle) | ZDM Server → SSH to Target |
| `Scripts/fix_03_oci_oss_setup.sh` | Discover OSS namespace + create migration bucket | zdmuser | ZDM Server |
| `Scripts/fix_04_zdm_cred_store.sh` | Initialize ZDM credential store | zdmuser | ZDM Server |
| `Scripts/fix_05_rman_archive_config.sh` | Configure RMAN + archive destination on source | azureuser (sudo to oracle) | ZDM Server → SSH to Source |
| `Scripts/fix_06_verify_ssh.sh` | Verify all SSH connections required by ZDM | zdmuser | ZDM Server |

---

## Issue Details

---

### ACTION-01: Enable ARCHIVELOG Mode on Source

**Category:** ❌ Blocker
**Status:** 🔲 Pending
**Priority:** CRITICAL
**Server:** Source Database (`10.1.0.11` / `tm-oracle-iaas`)
**Run As:** `azureuser` → `sudo -u oracle` → `sqlplus / as sysdba`

**Problem:**
The source database `oradb1` (SID: `oradb`) is in `NOARCHIVELOG` mode. ZDM's ONLINE_PHYSICAL migration method requires the source to be in ARCHIVELOG mode so that redo log archives can be applied to the standby (target) during replication. Without archive logging, ZDM cannot keep the target in sync with the source.

**Current State (from Discovery):**
```
Archive Log Mode: NOARCHIVELOG
Force Logging:    NO
Redo groups:      3 × 200 MB (all INACTIVE / CURRENT, none archived)
Archive dest:     /u01/app/oracle/product/12.2.0/dbhome_1/dbs/arch (inactive)
```

**⚠️ Prerequisite — Disk Space Check:**
Source has ~8.6 GB free on `/`. Archive logs will accumulate under the configured destination.
Before enabling ARCHIVELOG, configure a dedicated archive log destination (see ACTION-08).

**⚠️ Impact — Source Restart Required:**
Enabling ARCHIVELOG requires a database shutdown and restart (MOUNT mode). Plan a brief
maintenance window with the source DBA. Typical duration: 10–15 minutes.

**Remediation:**
```bash
# Run fix_01_source_archivelog.sh from the ZDM server (or copy/paste the SQL block below)
# File: Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts/fix_01_source_archivelog.sh
ssh -i ~/.ssh/odaa.pem azureuser@10.1.0.11 "sudo -u oracle bash -s" << 'EOF_OUTER'
export ORACLE_HOME=/u01/app/oracle/product/12.2.0/dbhome_1
export ORACLE_SID=oradb
export PATH=$ORACLE_HOME/bin:$PATH

sqlplus -S / as sysdba << 'EOF_SQL'
-- Step 1: Set archive log destination BEFORE enabling (avoid using default dbs/arch path)
ALTER SYSTEM SET log_archive_dest_1='LOCATION=/u01/app/oracle/archive' SCOPE=SPFILE;

-- Step 2: Shutdown and restart in MOUNT mode
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;

-- Step 3: Enable ARCHIVELOG
ALTER DATABASE ARCHIVELOG;

-- Step 4: Open the database
ALTER DATABASE OPEN;

-- Step 5: Enable Force Logging (required for ZDM Data Guard replication)
ALTER DATABASE FORCE LOGGING;

-- Step 6: Switch log to confirm archive is working
ALTER SYSTEM SWITCH LOGFILE;
ALTER SYSTEM SWITCH LOGFILE;

-- Step 7: Verify
SELECT LOG_MODE FROM V$DATABASE;
SELECT FORCE_LOGGING FROM V$DATABASE;
SELECT STATUS FROM V$ARCHIVE_DEST WHERE DEST_ID=1;
ARCHIVE LOG LIST;
SELECT GROUP#, STATUS, ARCHIVED FROM V$LOG;
EXIT;
EOF_SQL
EOF_OUTER
```

**Verification:**
```sql
-- Connect to source and confirm (expected outputs shown)
SELECT LOG_MODE FROM V$DATABASE;
-- Expected: ARCHIVELOG

SELECT FORCE_LOGGING FROM V$DATABASE;
-- Expected: YES

ARCHIVE LOG LIST;
-- Expected: Database log mode       Archive Mode
--           Automatic archival      Enabled
--           Archive destination     /u01/app/oracle/archive

SELECT COUNT(*) FROM V$ARCHIVED_LOG WHERE COMPLETION_TIME > SYSDATE - 1/24;
-- Expected: > 0 (at least 2 from the manual log switches above)
```

**Rollback:**
```sql
-- If ARCHIVELOG must be reversed (emergency only — will break ONLINE_PHYSICAL)
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE NOARCHIVELOG;
ALTER DATABASE OPEN;
```

**Resolution Notes:**
```
Date:
Performed by:
Verification output:
Notes:
```

---

### ACTION-02: Enable Force Logging on Source

> **Note:** This action is included in `fix_01_source_archivelog.sh` as Step 5, immediately after enabling ARCHIVELOG. No separate script is needed if running ACTION-01 and ACTION-02 together.

**Category:** ❌ Blocker
**Status:** 🔲 Pending
**Priority:** CRITICAL
**Server:** Source Database (`10.1.0.11`)

**Problem:**
Force Logging ensures that all data changes generate redo, even for operations that would normally suppress redo (e.g., `NOLOGGING` DML). ZDM's Data Guard replication depends on complete redo streams — any gaps will cause data loss.

**Current State:** `FORCE_LOGGING = NO` (from V$DATABASE)

**Remediation (if not already done via ACTION-01):**
```bash
ssh -i ~/.ssh/odaa.pem azureuser@10.1.0.11 "sudo -u oracle bash -s" << 'EOF'
export ORACLE_HOME=/u01/app/oracle/product/12.2.0/dbhome_1
export ORACLE_SID=oradb
export PATH=$ORACLE_HOME/bin:$PATH
sqlplus -S / as sysdba << 'ENDSQL'
ALTER DATABASE FORCE LOGGING;
SELECT FORCE_LOGGING FROM V\$DATABASE;
EXIT;
ENDSQL
EOF
```

**Verification:**
```
FORCE_LOGGING
-------------
YES
```

**Resolution Notes:**
```
Date:
Performed by:
Verification output:
Notes:
```

---

### ACTION-03: Enable Supplemental Logging on Source

> **Note:** Supplemental logging is best enabled after ARCHIVELOG mode is active (ACTION-01/02).
> It is included as the final step in `fix_01_source_archivelog.sh`.

**Category:** ❌ Blocker
**Status:** 🔲 Pending
**Priority:** CRITICAL
**Server:** Source Database (`10.1.0.11`)

**Problem:**
Supplemental logging is required for ZDM's online physical migration to capture all necessary redo information for Data Guard replication and for proper handling of primary key tracking. Discovery shows no supplemental logging is configured.

**Current State (from Discovery):**
```
SUPPLEMENTAL_LOG_DATA_MIN: NO
SUPPLEMENTAL_LOG_DATA_PK:  NO
SUPPLEMENTAL_LOG_DATA_UI:  NO
SUPPLEMENTAL_LOG_DATA_FK:  NO
SUPPLEMENTAL_LOG_DATA_ALL: NO
```

**Remediation:**
```bash
ssh -i ~/.ssh/odaa.pem azureuser@10.1.0.11 "sudo -u oracle bash -s" << 'EOF'
export ORACLE_HOME=/u01/app/oracle/product/12.2.0/dbhome_1
export ORACLE_SID=oradb
export PATH=$ORACLE_HOME/bin:$PATH
sqlplus -S / as sysdba << 'ENDSQL'
-- Minimum supplemental logging (required)
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
-- ALL columns supplemental logging (recommended for ZDM ONLINE_PHYSICAL)
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER SYSTEM SWITCH LOGFILE;

SELECT SUPPLEMENTAL_LOG_DATA_MIN, SUPPLEMENTAL_LOG_DATA_ALL FROM V\$DATABASE;
EXIT;
ENDSQL
EOF
```

**Verification:**
```
SUPPLEMENTAL_LOG_DATA_MIN  SUPPLEMENTAL_LOG_DATA_ALL
-------------------------  -------------------------
YES                        YES
```

**Resolution Notes:**
```
Date:
Performed by:
Verification output:
Notes:
```

---

### ACTION-04: Configure TDE Master Key on Target

**Category:** ⚠️ Required
**Status:** 🔲 Pending
**Priority:** HIGH
**Server:** Target Database Node 1 (`10.0.1.160` / `tmodaauks-rqahk1`)
**Run As:** `opc` → `sudo -u oracle` → `sqlplus / as sysdba`

**Problem:**
The target CDB on ODAA shows TDE wallet status `OPEN_NO_MASTER_KEY`. ZDM requires a TDE master key to exist in the target wallet before migration begins. Without it, ZDM will fail during the database creation/restore phase.

**Current State (from Discovery):**
```
Target TDE Wallet Status: OPEN_NO_MASTER_KEY
```

**⚠️ Prerequisite:**
You must know the TDE wallet password for the target CDB. This was set when the Exadata
Database Service was provisioned on ODAA. Retrieve it from your password vault / ODAA admin.

**Remediation:**
```bash
# Run from ZDM server as zdmuser (or use fix_02_target_tde_master_key.sh)
ssh -i ~/.ssh/odaa.pem opc@10.0.1.160 "sudo -u oracle bash -s" << 'EOF'
export ORACLE_HOME=/u02/app/oracle/product/19.0.0.0/dbhome_1
# Find active CDB SID
ORACLE_SID=$(cat /etc/oratab | grep -v '^#' | grep -i "dbhome_1" | head -1 | cut -d: -f1)
export ORACLE_SID
export PATH=$ORACLE_HOME/bin:$PATH

echo "Connecting to CDB: $ORACLE_SID"
sqlplus -S / as sysdba << 'ENDSQL'
-- Check current wallet status
SELECT STATUS, WALLET_TYPE FROM V$ENCRYPTION_WALLET;

-- Create TDE master key (replace <WALLET_PASSWORD> with the actual wallet password)
-- IMPORTANT: Run this command interactively — do NOT store the password in scripts
-- ADMINISTER KEY MANAGEMENT SET KEY FORCE KEYSTORE IDENTIFIED BY "<WALLET_PASSWORD>" WITH BACKUP;

-- Verify after executing
SELECT STATUS, WALLET_TYPE FROM V$ENCRYPTION_WALLET;
EXIT;
ENDSQL
EOF
```

**Manual SQL (run interactively with password):**
```sql
-- Connect to target as SYSDBA
sqlplus / as sysdba

-- Create TDE master key (interactive — supply wallet password at prompt)
ADMINISTER KEY MANAGEMENT SET KEY FORCE KEYSTORE
  IDENTIFIED BY "<TDE_WALLET_PASSWORD>"
  WITH BACKUP;

-- Verify
SELECT STATUS, WALLET_TYPE FROM V$ENCRYPTION_WALLET;
-- Expected: OPEN  PASSWORD  (or AUTOLOGIN if auto-login wallet configured)
```

**Verification:**
```sql
SELECT STATUS, WALLET_TYPE FROM V$ENCRYPTION_WALLET;
-- STATUS must NOT be OPEN_NO_MASTER_KEY after this step
-- Expected: OPEN + (PASSWORD or AUTOLOGIN)
```

**Resolution Notes:**
```
Date:
Performed by:
Wallet password source:
Verification output:
Notes:
```

---

### ACTION-05: Discover OCI Object Storage Namespace

**Category:** ⚠️ Required
**Status:** 🔲 Pending
**Priority:** HIGH
**Server:** ZDM Server (`10.1.0.8` / `tm-vm-odaa-oracle-jumpbox`)
**Run As:** `zdmuser`

**Problem:**
The OCI Object Storage namespace is required for ZDM to create buckets and transfer migration data. It is blank in `zdm-env.md`. The zdmuser OCI config is already configured (region: uk-london-1), so this is a simple query.

**Remediation:**
```bash
# On ZDM server, run as zdmuser
ssh -i ~/.ssh/zdm.pem azureuser@10.1.0.8 "sudo -u zdmuser bash -c 'oci os ns get'"

# Alternative: log in to ZDM server directly
su - zdmuser
oci os ns get --config-file ~/.oci/config
```

**Expected Output:**
```json
{
  "data": "<YOUR_NAMESPACE_STRING>"
}
```

**Post-Action:**
Record the namespace value in `zdm-env.md`:
```
- OCI_OSS_NAMESPACE: <namespace_value>
```

**Resolution Notes:**
```
Date:
Namespace value discovered:
zdm-env.md updated: YES / NO
Notes:
```

---

### ACTION-06: Create OCI Object Storage Bucket

**Category:** ⚠️ Required
**Status:** 🔲 Pending
**Priority:** HIGH
**Server:** ZDM Server (`10.1.0.8`)
**Run As:** `zdmuser`
**Prerequisite:** ACTION-05 (namespace must be known)

**Problem:**
ZDM requires an OCI Object Storage bucket in the same region as the target database (uk-london-1) to stage RMAN backup sets during migration. No bucket exists yet.

**Remediation:**
```bash
# On ZDM server as zdmuser
su - zdmuser

OSS_NAMESPACE="<NAMESPACE_FROM_ACTION_05>"
COMPARTMENT_OCID="ocid1.compartment.oc1..aaaaaaaas4upnqj72dfiivgwvn3uui5gkxo7ng6leeoifucbjiy326urbhmq"
BUCKET_NAME="zdm-oradb-migration"
REGION="uk-london-1"

oci os bucket create \
  --namespace "${OSS_NAMESPACE}" \
  --compartment-id "${COMPARTMENT_OCID}" \
  --name "${BUCKET_NAME}" \
  --region "${REGION}" \
  --versioning Disabled \
  --public-access-type NoPublicAccess

# Verify bucket creation
oci os bucket get \
  --namespace "${OSS_NAMESPACE}" \
  --bucket-name "${BUCKET_NAME}"
```

**Verification:**
```bash
oci os bucket list \
  --namespace "${OSS_NAMESPACE}" \
  --compartment-id "${COMPARTMENT_OCID}" \
  --query "data[?name=='zdm-oradb-migration']"
# Expected: Returns bucket object with "name": "zdm-oradb-migration"
```

**Post-Action:**
Record the bucket name in `zdm-env.md`:
```
- OCI_OSS_BUCKET_NAME: zdm-oradb-migration
```

**Resolution Notes:**
```
Date:
Bucket name:
Bucket OCID:
zdm-env.md updated: YES / NO
Notes:
```

---

### ACTION-07: Initialize ZDM Credential Store

**Category:** ⚠️ Required
**Status:** 🔲 Pending
**Priority:** HIGH
**Server:** ZDM Server (`10.1.0.8`)
**Run As:** `zdmuser`
**Prerequisites:** ACTION-04 (TDE wallet), ACTION-05/06 (OSS), source and target SYS passwords

**Problem:**
The ZDM credential store (`/u01/app/zdmhome/zdm/cred`) does not exist. ZDM requires source and target database SYS credentials to be stored in its credential store before executing `zdmcli migrate database`.

**Remediation:**
```bash
# Step 1: Log in to ZDM server as zdmuser
su - zdmuser

# Step 2: Verify ZDM service is running
/u01/app/zdmhome/bin/zdmcli query jobid -jobid 1 2>/dev/null || echo "ZDM service is running (no jobs yet)"

# Step 3: Create the ZDM credential store directory (if not present)
# ZDM auto-creates this on first credential add — no manual mkdir needed

# Step 4: Add source database SYS password to ZDM wallet
# (ZDM will prompt for password — do NOT put plaintext in scripts)
/u01/app/zdmhome/bin/zdmcli migrate database \
  -sourcedb oradb1 \
  -sourcenode 10.1.0.11 \
  -srcauth zdmauth \
  -srcarg1 user:azureuser \
  -srcarg2 identity_file:/home/zdmuser/.ssh/odaa.pem \
  -srcarg3 sudo_location:/usr/bin/sudo \
  -targetdb <TARGET_DB_UNIQUE_NAME> \
  -targetnode 10.0.1.160 \
  -tgtauth zdmauth \
  -tgtarg1 user:opc \
  -tgtarg2 identity_file:/home/zdmuser/.ssh/odaa.pem \
  -tgtarg3 sudo_location:/usr/bin/sudo \
  -rsp /u01/app/zdmhome/rhp/zdm/template/zdm_template.rsp \
  -pauseafter ZDM_VALIDATE_SRC \
  2>&1 | head -50
# Note: Running with -pauseafter ZDM_VALIDATE_SRC allows you to test credential
# setup only; cancel migration after validation passes.
```

**Alternative — Response File Method:**
The ZDM response file (Step 3) can include encrypted passwords via the `TGT_DB_UNIQUE_NAME`
and related parameters. Consult the ZDM admin guide for `zdmcli -cred` wallet operations:
```bash
# Check ZDM documentation
/u01/app/zdmhome/bin/zdmcli migrate database -help 2>&1 | grep -i cred
```

**Verification:**
```bash
# Verify credential store directory was created after first zdmcli invocation
ls -la /u01/app/zdmhome/zdm/cred/
# Expected: cwallet.sso and related files
```

**Resolution Notes:**
```
Date:
Performed by:
Source SYS password stored: YES / NO
Target SYS password stored: YES / NO
TDE wallet password stored: YES / NO
Verification output:
Notes:
```

---

### ACTION-08: Configure Archive Log Destination on Source

**Category:** ⚡ Recommended
**Status:** 🔲 Pending
**Priority:** MEDIUM
**Server:** Source Database (`10.1.0.11`)
**Prerequisite:** Confirm disk/mount point for archive logs before enabling ARCHIVELOG

**Problem:**
Source disk has only ~8.6 GB free on `/`. Archive logs will accumulate at the configured
destination. The default archive path (`$ORACLE_HOME/dbs/arch`) is on the already-tight
root filesystem. A dedicated mount or path with more headroom should be configured.

**Remediation (already included in ACTION-01 fix script):**
```bash
# On source server as oracle, before or during ARCHIVELOG enablement
# Option A: Use the existing archive destination default path with monitoring
mkdir -p /u01/app/oracle/archive
chown oracle:oinstall /u01/app/oracle/archive

# Check /u01 disk space
df -h /u01
# If /u01 has more space, configure log_archive_dest_1 to /u01/app/oracle/archive

# Option B: If a separate mount exists with more space (e.g. /mnt/archive)
# Set SPFILE parameter:
# ALTER SYSTEM SET log_archive_dest_1='LOCATION=/mnt/archive' SCOPE=SPFILE;
```

**RMAN Archive Deletion Policy:**
```rman
-- Set deletion policy to avoid unbounded log accumulation
CONFIGURE ARCHIVELOG DELETION POLICY TO APPLIED ON ALL STANDBY;
-- Or for simple cleanup during migration window:
CONFIGURE ARCHIVELOG DELETION POLICY TO NONE;
```

**Ongoing Monitoring:**
```bash
# Monitor archive log space on source (run periodically during migration)
ssh -i ~/.ssh/odaa.pem azureuser@10.1.0.11 "sudo -u oracle bash -c '
export ORACLE_HOME=/u01/app/oracle/product/12.2.0/dbhome_1
export ORACLE_SID=oradb
export PATH=\$ORACLE_HOME/bin:\$PATH
df -h /u01/app/oracle/archive 2>/dev/null || df -h /u01
sqlplus -S / as sysdba <<SQL
SELECT DEST_NAME, STATUS, TARGET, ARCHIVER, DESTINATION FROM V\\\$ARCHIVE_DEST WHERE STATUS=\\'VALID\\';
SQL
'"
```

**Resolution Notes:**
```
Date:
Archive destination configured:
Available space at destination:
Monitoring plan:
Notes:
```

---

### ACTION-09: Configure RMAN on Source

**Category:** ⚡ Recommended
**Status:** 🔲 Pending
**Priority:** MEDIUM
**Server:** Source Database (`10.1.0.11`)

**Problem:**
RMAN is not configured on the source database. While ZDM manages its own RMAN backup/restore
internally, it is strongly recommended to:
1. Configure RMAN so a pre-migration backup can be taken as a safety net
2. Set up Fast Recovery Area (FRA) for archive log and backup management during the migration window

**Remediation:**
```bash
# Run fix_05_rman_archive_config.sh — or manually:
ssh -i ~/.ssh/odaa.pem azureuser@10.1.0.11 "sudo -u oracle bash -s" << 'EOF'
export ORACLE_HOME=/u01/app/oracle/product/12.2.0/dbhome_1
export ORACLE_SID=oradb
export PATH=$ORACLE_HOME/bin:$PATH
mkdir -p /u01/app/oracle/fast_recovery_area

rman target / << 'ENDRMAN'
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '/u01/app/oracle/fast_recovery_area/%F';
CONFIGURE DEFAULT DEVICE TYPE TO DISK;
CONFIGURE BACKUP OPTIMIZATION ON;
CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 3 DAYS;

-- Take pre-migration backup
BACKUP DATABASE PLUS ARCHIVELOG;

SHOW ALL;
EXIT;
ENDRMAN
EOF
```

**Verification:**
```bash
ssh -i ~/.ssh/odaa.pem azureuser@10.1.0.11 "sudo -u oracle bash -c '
export ORACLE_HOME=/u01/app/oracle/product/12.2.0/dbhome_1
export ORACLE_SID=oradb
export PATH=\$ORACLE_HOME/bin:\$PATH
rman target / <<SQL
LIST BACKUP SUMMARY;
EXIT;
SQL
'"
```

**Resolution Notes:**
```
Date:
FRA location:
Pre-migration backup taken: YES / NO
Backup size:
Notes:
```

---

### ACTION-10: Verify SSH Key Access (zdmuser → Source and Target)

**Category:** ⚡ Recommended
**Status:** 🔲 Pending
**Priority:** MEDIUM
**Server:** ZDM Server (`10.1.0.8`)
**Run As:** `zdmuser`

**Problem:**
ZDM executes remote commands on source and target via SSH as zdmuser using the keys found in
`/home/zdmuser/.ssh/`. Connectivity was confirmed as `azureuser` during Step 0 discovery, but
ZDM itself will use the `zdmuser` identity. Verify that zdmuser's keys work for both hosts.

**Remediation / Verification:**
```bash
# On ZDM server as zdmuser
su - zdmuser

# Test SSH to source (azureuser admin, then sudo to oracle)
echo "=== Testing zdmuser SSH to SOURCE ==="
ssh -i ~/.ssh/odaa.pem -o StrictHostKeyChecking=no azureuser@10.1.0.11 \
  "sudo -u oracle whoami && hostname"
# Expected: oracle  \n  tm-oracle-iaas

# Test SSH to target (opc admin, then sudo to oracle)
echo "=== Testing zdmuser SSH to TARGET ==="
ssh -i ~/.ssh/odaa.pem -o StrictHostKeyChecking=no opc@10.0.1.160 \
  "sudo -u oracle whoami && hostname"
# Expected: oracle  \n  tmodaauks-rqahk1
```

Alternatively, use `fix_06_verify_ssh.sh`.

**Resolution Notes:**
```
Date:
zdmuser → source SSH result:
zdmuser → target SSH result:
Notes:
```

---

### ACTION-11: Verify Oracle User Direct SSH Access (if required by ZDM configuration)

**Category:** ⚡ Recommended
**Status:** 🔲 Pending
**Priority:** MEDIUM
**Server:** ZDM Server (`10.1.0.8`)

**Problem:**
Some ZDM response file configurations require direct SSH as the `oracle` OS user rather than
using admin+sudo. Verify if direct oracle SSH is permitted; if not, confirm the ZDM response
file will use the admin+sudo pattern (`-srcauth zdmauth`/`-tgtauth zdmauth`).

**Context:**
Discovery shows zdmuser's `~/.ssh/` contains: `iaas.pem`, `odaa.pem`, `zdm.pem`, `id_ed25519`, `id_rsa`.
The `oracle` user SSH directory was not accessible during Step 0 discovery.

**Remediation / Verification:**
```bash
su - zdmuser

# Test direct SSH as oracle (may fail — expected if PermitRootLogin-like restrictions apply)
echo "=== Testing direct oracle SSH to SOURCE ==="
ssh -i ~/.ssh/odaa.pem oracle@10.1.0.11 "hostname" 2>&1
# If this fails: use -srcauth zdmauth in zdmcli command (admin user + sudo)

echo "=== Testing direct oracle SSH to TARGET ==="
ssh -i ~/.ssh/odaa.pem oracle@10.0.1.160 "hostname" 2>&1
# If this fails: use -tgtauth zdmauth in zdmcli command
```

**Decision:**
| Result | ZDM Config Implication |
|--------|----------------------|
| Direct `oracle` SSH works | Can use `-srcauth osSudoRoot` in response file |
| Direct `oracle` SSH blocked | Must use `-srcauth zdmauth` with admin user + sudo (standard ODAA pattern) |

**Resolution Notes:**
```
Date:
Direct oracle SSH to source: WORKS / BLOCKED
Direct oracle SSH to target: WORKS / BLOCKED
ZDM auth method confirmed:
Notes:
```

---

### ACTION-12: Update zdm-env.md with Missing Values

**Category:** ⚠️ Required
**Status:** 🔲 Pending
**Priority:** MEDIUM
**File:** `prompts/Phase10-Migration/ZDM/zdm-env.md`

**Problem:**
Two required fields are blank in `zdm-env.md`. These values are needed for Step 3 migration
artifact generation (ZDM response file and migration command).

**Fields to Populate:**

| Field | How to Obtain | Status |
|-------|--------------|--------|
| `OCI_OSS_NAMESPACE` | Run `oci os ns get` as zdmuser (ACTION-05) | ❌ BLANK |
| `OCI_OSS_BUCKET_NAME` | Create bucket (ACTION-06) | ❌ BLANK |

**Post-Action:**
After completing ACTION-05 and ACTION-06, update the following lines in `zdm-env.md`:
```diff
- OCI_OSS_NAMESPACE: 
+ OCI_OSS_NAMESPACE: <value from oci os ns get>
- OCI_OSS_BUCKET_NAME: 
+ OCI_OSS_BUCKET_NAME: zdm-oradb-migration
```

**Resolution Notes:**
```
Date:
OCI_OSS_NAMESPACE value:
OCI_OSS_BUCKET_NAME value:
zdm-env.md updated: YES / NO
Notes:
```

---

## Completion Checklist

Before proceeding to Step 3 (Generate Migration Artifacts):

- [ ] ACTION-01: Source database is in ARCHIVELOG mode (`LOG_MODE = ARCHIVELOG`)
- [ ] ACTION-02: Force Logging is enabled (`FORCE_LOGGING = YES`)
- [ ] ACTION-03: Supplemental logging is enabled (`SUPPLEMENTAL_LOG_DATA_MIN = YES`)
- [ ] ACTION-04: Target TDE wallet has a master key (`STATUS != OPEN_NO_MASTER_KEY`)
- [ ] ACTION-05: OCI Object Storage namespace discovered and recorded in zdm-env.md
- [ ] ACTION-06: OCI Object Storage bucket created (`zdm-oradb-migration` in uk-london-1)
- [ ] ACTION-07: ZDM credential store initialized (`/u01/app/zdmhome/zdm/cred` exists)
- [ ] ACTION-08: Archive log destination configured with adequate space
- [ ] ACTION-09: Pre-migration RMAN backup taken
- [ ] ACTION-10: zdmuser SSH access to source and target verified
- [ ] ACTION-11: ZDM auth method (admin+sudo vs. direct oracle) confirmed
- [ ] ACTION-12: zdm-env.md updated with OSS namespace and bucket name

---

## Verification Discovery (Post-Fix)

After completing all CRITICAL and HIGH actions, re-run source and target discovery to confirm
changes took effect. Save outputs to `Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Verification/`.

```bash
# From ZDM server, re-run source discovery
ssh -i ~/.ssh/zdm.pem azureuser@10.1.0.8 "sudo -u zdmuser bash -s" \
  < Artifacts/Phase10-Migration/ZDM/ORADB/Step0/Scripts/zdm_source_discovery.sh \
  > Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Verification/zdm_source_post_fix.txt

# Re-run target discovery
ssh -i ~/.ssh/zdm.pem azureuser@10.1.0.8 "sudo -u zdmuser bash -s" \
  < Artifacts/Phase10-Migration/ZDM/ORADB/Step0/Scripts/zdm_target_discovery.sh \
  > Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Verification/zdm_target_post_fix.txt
```

---

## Next Steps

Once all items in the Completion Checklist are ✅:

1. Update this log with resolution dates and verifications
2. Ensure `zdm-env.md` is fully populated
3. Proceed to **Step 3**: Run `Step3-Generate-Migration-Artifacts.prompt.md` with:
   - This Issue Resolution Log
   - Updated Migration Questionnaire from Step 1
   - Latest discovery files from `Step2/Verification/`

---

*Generated by GitHub Copilot — ODAA Migration Accelerator*
*Based on Discovery Summary: 2026-02-27*
