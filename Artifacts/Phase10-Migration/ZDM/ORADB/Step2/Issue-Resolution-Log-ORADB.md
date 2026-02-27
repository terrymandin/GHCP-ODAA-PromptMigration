# Issue Resolution Log: ORADB

| Field | Value |
|---|---|
| **Project** | ORADB |
| **Document** | Issue Resolution Log (Step 2) |
| **Generated** | 2026-02-27 |
| **Based on Discovery** | 2026-02-27 21:36 UTC |
| **Migration Target** | Oracle Database@Azure — Exadata X11M, uk-london-1 |

---

## Summary

| # | Issue | Category | Status | Date Resolved | Verified By |
|---|-------|----------|--------|---------------|-------------|
| ACTION-01 | Enable ARCHIVELOG mode on source | ❌ Blocker | 🔲 Pending | | |
| ACTION-02 | Enable Force Logging on source | ❌ Blocker | 🔲 Pending | | |
| ACTION-03 | Enable Supplemental Logging on source | ❌ Blocker | 🔲 Pending | | |
| ACTION-04 | Configure TDE Master Key on target CDB | ❌ Blocker | 🔲 Pending | | |
| ACTION-05 | Discover OCI Object Storage Namespace | ❌ Blocker | 🔲 Pending | | |
| ACTION-06 | Create OCI Object Storage Bucket | ❌ Blocker | 🔲 Pending | | |
| ACTION-07 | Initialize ZDM Credential Store | ❌ Blocker | 🔲 Pending | | |
| ACTION-08 | Configure Archive Log destination (disk) | ⚠️ Required | 🔲 Pending | | |
| ACTION-09 | Configure RMAN on source (pre-migration backup) | ⚠️ Required | 🔲 Pending | | |
| ACTION-10 | Verify zdmuser SSH key access to source + target | ⚠️ Required | 🔲 Pending | | |
| ACTION-11 | Verify oracle sudo access via admin SSH user | ⚠️ Required | 🔲 Pending | | |
| ACTION-12 | Update zdm-env.md with OSS namespace + bucket | ⚠️ Required | 🔲 Pending | | |
| R-07 | Review/remove offline DBs on target /u02 | ⚠️ Required | 🔲 Pending | | |

**Status key:** 🔲 Pending | 🔄 In Progress | ✅ Resolved | ❌ Failed / Blocked

---

## Remediation Scripts

The following scripts were generated for this step:

| Script | Server | Resolves |
|--------|--------|---------|
| [Scripts/fix_source_ORADB.sh](Scripts/fix_source_ORADB.sh) | Source (10.1.0.11) — run from ZDM server | ACTION-01, 02, 03, 08, 09 |
| [Scripts/fix_target_ORADB.sh](Scripts/fix_target_ORADB.sh) | Target (10.0.1.160) — run from ZDM server | ACTION-04 |
| [Scripts/fix_zdm_server_ORADB.sh](Scripts/fix_zdm_server_ORADB.sh) | ZDM server (10.1.0.8) — run locally | ACTION-05, 06, 07, 10, 11 |

---

## Issue Details

---

### ACTION-01: Enable ARCHIVELOG Mode on Source

**Category:** ❌ Blocker  
**Risk:** R-01 (Critical)  
**Status:** 🔲 Pending  
**Server:** Source (tm-oracle-iaas / 10.1.0.11)

**Problem:**  
The source database ORADB1 is in NOARCHIVELOG mode. ZDM ONLINE_PHYSICAL requires ARCHIVELOG mode to establish a Data Guard standby relationship and apply redo to the target.

**Discovery Evidence:**  
`SELECT LOG_MODE FROM V$DATABASE;` → `NOARCHIVELOG`

**Remediation:**  
Run `Scripts/fix_source_ORADB.sh`. The script performs the following steps automatically:

```sql
-- Run as SYSDBA on source
ALTER SYSTEM SET log_archive_dest_1='LOCATION=/u01/app/oracle/fast_recovery_area' SCOPE=SPFILE;
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;
ALTER SYSTEM SWITCH LOGFILE;
```

> ⚠️ **Requires brief source database downtime.** Coordinate with stakeholders.

**Verification:**  
```sql
SELECT LOG_MODE FROM V$DATABASE;
-- Expected: ARCHIVELOG
```

**Rollback:**  
```sql
-- If ARCHIVELOG must be disabled (reversing this decision):
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE NOARCHIVELOG;
ALTER DATABASE OPEN;
```

**Resolution Notes:**  
_[To be completed after execution]_

---

### ACTION-02: Enable Force Logging on Source

**Category:** ❌ Blocker  
**Risk:** R-01 (Critical)  
**Status:** 🔲 Pending  
**Server:** Source (tm-oracle-iaas / 10.1.0.11)

**Problem:**  
Force Logging is disabled on the source. Without it, certain DDL operations using NOLOGGING bypass redo generation, causing Data Guard applier on the target to silently lose data blocks.

**Discovery Evidence:**  
`SELECT FORCE_LOGGING FROM V$DATABASE;` → `NO`

**Remediation:**  
Included in `Scripts/fix_source_ORADB.sh`:

```sql
ALTER DATABASE FORCE LOGGING;
```

**Verification:**  
```sql
SELECT FORCE_LOGGING FROM V$DATABASE;
-- Expected: YES
```

**Rollback:**  
```sql
ALTER DATABASE NO FORCE LOGGING;
```

**Resolution Notes:**  
_[To be completed after execution]_

---

### ACTION-03: Enable Supplemental Logging on Source

**Category:** ❌ Blocker  
**Risk:** R-02 (High)  
**Status:** 🔲 Pending  
**Server:** Source (tm-oracle-iaas / 10.1.0.11)

**Problem:**  
Supplemental logging is not enabled on the source. ZDM ONLINE_PHYSICAL (Data Guard) requires minimum supplemental logging to correctly reconstruct redo on the target.

**Discovery Evidence:**  
`SELECT SUPPLEMENTAL_LOG_DATA_MIN FROM V$DATABASE;` → `NO`

**Remediation:**  
Included in `Scripts/fix_source_ORADB.sh`:

```sql
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER SYSTEM SWITCH LOGFILE;
```

**Verification:**  
```sql
SELECT SUPPLEMENTAL_LOG_DATA_MIN, SUPPLEMENTAL_LOG_DATA_ALL FROM V$DATABASE;
-- Expected: YES, YES
```

**Rollback:**  
```sql
ALTER DATABASE DROP SUPPLEMENTAL LOG DATA;
```

**Resolution Notes:**  
_[To be completed after execution]_

---

### ACTION-04: Configure TDE Master Key on Target CDB

**Category:** ❌ Blocker  
**Risk:** R-03 (High)  
**Status:** 🔲 Pending  
**Server:** Target Node 1 (tmodaauks-rqahk1 / 10.0.1.160)

**Problem:**  
The target CDB TDE wallet is in state `OPEN_NO_MASTER_KEY`. ZDM requires a TDE master key to exist on the target to complete the physical migration. Without it, ZDM may fail at the point of applying encrypted redo or performing the final standby conversion.

**Discovery Evidence:**  
`SELECT STATUS, WALLET_TYPE FROM V$ENCRYPTION_WALLET;` → `OPEN_NO_MASTER_KEY`

**Remediation:**  
Run `Scripts/fix_target_ORADB.sh`. The script prompts for the TDE wallet password and runs:

```sql
ADMINISTER KEY MANAGEMENT SET KEY FORCE KEYSTORE 
  IDENTIFIED BY "<wallet_password>" WITH BACKUP;
```

> ⚠️ The wallet password is prompted interactively and never stored in the script.  
> ⚠️ This must be run as SYSDBA on the **target CDB root**, not inside a PDB.

**Verification:**  
```sql
SELECT STATUS, WALLET_TYPE FROM V$ENCRYPTION_WALLET;
-- Expected: OPEN, PASSWORD  (or AUTOLOGIN if auto-login wallet is configured)
-- Must NOT show OPEN_NO_MASTER_KEY
```

**Rollback:**  
Not applicable — adding a master key does not change the wallet state adversely.  
If performed on the wrong CDB, the DBA should coordinate with Oracle Support.

**Resolution Notes:**  
_[To be completed after execution — include target CDB SID and node used]_

---

### ACTION-05: Discover OCI Object Storage Namespace

**Category:** ❌ Blocker  
**Risk:** R-04 (High)  
**Status:** 🔲 Pending  
**Server:** ZDM Server (tm-vm-odaa-oracle-jumpbox / 10.1.0.8)

**Problem:**  
The OCI Object Storage namespace is not configured in zdm-env.md. ZDM uses OCI Object Storage to stage backup files during migration. The namespace is required for all OCI OS operations.

**Remediation:**  
Included in `Scripts/fix_zdm_server_ORADB.sh`. Executed as zdmuser:

```bash
oci os ns get --config-file /home/zdmuser/.oci/config --query 'data' --raw-output
```

**Verification:**  
Output is a short string (e.g., `axyz1234abcd`). No error message.

**Post-Action:**  
Update `zdm-env.md`:
```
- OCI_OSS_NAMESPACE: <value from command output>
```

**Resolution Notes:**  
Namespace value: _[To be completed]_

---

### ACTION-06: Create OCI Object Storage Bucket

**Category:** ❌ Blocker  
**Risk:** R-04 (High)  
**Status:** 🔲 Pending  
**Server:** ZDM Server (tm-vm-odaa-oracle-jumpbox / 10.1.0.8)

**Problem:**  
No OCI Object Storage bucket exists for ZDM data transfer. ZDM requires a bucket in the same region as the target (uk-london-1) within the project compartment.

**Remediation:**  
Included in `Scripts/fix_zdm_server_ORADB.sh`. Executed as zdmuser:

```bash
oci os bucket create \
  --compartment-id ocid1.compartment.oc1..aaaaaaaas4upnqj72dfiivgwvn3uui5gkxo7ng6leeoifucbjiy326urbhmq \
  --namespace <OCI_OSS_NAMESPACE> \
  --name zdm-oradb-migration \
  --storage-tier Standard
```

**Bucket Details:**
| Field | Value |
|---|---|
| Suggested Name | `zdm-oradb-migration` |
| Region | uk-london-1 |
| Compartment | ocid1.compartment.oc1..aaaaaaaas4upnqj72dfiivgwvn3uui5gkxo7ng6leeoifucbjiy326urbhmq |
| Storage Tier | Standard |

**Post-Action:**  
Update `zdm-env.md`:
```
- OCI_OSS_BUCKET_NAME: zdm-oradb-migration
```

**Resolution Notes:**  
Bucket name used: _[To be completed]_

---

### ACTION-07: Initialize ZDM Credential Store

**Category:** ❌ Blocker  
**Risk:** R-05 (High)  
**Status:** 🔲 Pending  
**Server:** ZDM Server (tm-vm-odaa-oracle-jumpbox / 10.1.0.8)

**Problem:**  
The ZDM credential store at `/u01/app/zdmhome/zdm/cred` does not exist. ZDM requires source and target SYS passwords to be stored before initiating a migration job.

**Remediation:**  
The credential store is initialized automatically when `zdmcli migrate database` is first invoked with password arguments. Run as zdmuser:

```bash
# Option 1: Pass credentials on the command line (they are stored in the cred store)
/u01/app/zdmhome/bin/zdmcli migrate database \
  -sourcedb oradb1 \
  -sourcenode 10.1.0.11 \
  -srcauth zdmauth \
  -srcarg1 user:azureuser \
  -srcarg2 identity_file:/home/zdmuser/.ssh/odaa.pem \
  -srcarg3 sudo_location:/usr/bin/sudo \
  -targetnode 10.0.1.160 \
  -tgtauth zdmauth \
  -tgtarg1 user:opc \
  -tgtarg2 identity_file:/home/zdmuser/.ssh/odaa.pem \
  -tgtarg3 sudo_location:/usr/bin/sudo \
  -rsp /u01/app/zdmhome/rhp/zdm/template/zdm_template.rsp \
  -eval    # -eval flag does a dry-run only; remove for actual migration
```

> The full migration command will be generated in Step 3.  
> `-eval` performs a pre-flight checks only run without executing the migration.

**Verification:**  
```bash
ls -la /u01/app/zdmhome/zdm/cred/
# Directory should exist with wallet files after first zdmcli run
```

**Resolution Notes:**  
_[To be completed — record when first zdmcli eval or migrate run is executed]_

---

### ACTION-08: Configure Archive Log Destination on Source

**Category:** ⚠️ Required  
**Risk:** R-06 (Medium)  
**Status:** 🔲 Pending  
**Server:** Source (tm-oracle-iaas / 10.1.0.11)

**Problem:**  
Source disk is tight at ~8.6 GB free on root (`/`). Enabling ARCHIVELOG will cause archive logs to accumulate. The default archive destination (`ORACLE_HOME/dbs/arch`) is on the already-tight root filesystem.

**Remediation:**  
Included in `Scripts/fix_source_ORADB.sh`. Sets FRA to `/u01/app/oracle/fast_recovery_area` (same mount as ORACLE_BASE but using fast recovery area standard path):

```sql
ALTER SYSTEM SET log_archive_dest_1='LOCATION=/u01/app/oracle/fast_recovery_area' SCOPE=SPFILE;
ALTER SYSTEM SET db_recovery_file_dest='/u01/app/oracle/fast_recovery_area' SCOPE=BOTH;
ALTER SYSTEM SET db_recovery_file_dest_size=5G SCOPE=BOTH;
```

> Monitor archive log accumulation after enabling ARCHIVELOG. For a 1.9 GB database with 200 MB redo groups, each log switch generates ~200 MB. At steady state, expect 1–3 GB/hour of archive log generation during active migration.

**Verification:**  
```bash
df -h /u01/app/oracle
# Confirm space is adequate (>5 GB free recommended during migration)
```

**Resolution Notes:**  
_[Record disk free space before and after steps]_

---

### ACTION-09: Configure RMAN on Source

**Category:** ⚠️ Required  
**Risk:** R-08 (Medium)  
**Status:** 🔲 Pending  
**Server:** Source (tm-oracle-iaas / 10.1.0.11)

**Problem:**  
No RMAN backup exists for the source database. Before initiating migration, a baseline backup should be taken as a safety net. Additionally, RMAN is required if OFFLINE_PHYSICAL is selected as the migration method.

**Remediation:**  
Includes in `Scripts/fix_source_ORADB.sh`. Configures RMAN with FRA:

```bash
rman TARGET /
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '/u01/app/oracle/fast_recovery_area/%F';
CONFIGURE DEFAULT DEVICE TYPE TO DISK;
CONFIGURE BACKUP OPTIMIZATION ON;
CONFIGURE RETENTION POLICY TO REDUNDANCY 1;
```

After script execution, manually take a full pre-migration backup:

```bash
# Run on source as oracle user
rman TARGET /
BACKUP DATABASE PLUS ARCHIVELOG;
```

**Verification:**  
```bash
rman TARGET /
LIST BACKUP SUMMARY;
```

**Resolution Notes:**  
_[Record date of backup and location]_

---

### ACTION-10: Verify zdmuser SSH Key Access

**Category:** ⚠️ Required  
**Risk:** R-05 (Medium)  
**Status:** 🔲 Pending  
**Server:** ZDM Server (10.1.0.8)

**Problem:**  
Discovery confirmed zdmuser has SSH keys (`odaa.pem`, `iaas.pem`, `zdm.pem`) but did not explicitly verify they work for source and target connections. ZDM executes all SSH as zdmuser.

**Remediation:**  
Included in `Scripts/fix_zdm_server_ORADB.sh`:

```bash
# As zdmuser
ssh -i ~/.ssh/odaa.pem azureuser@10.1.0.11 "hostname"   # Expected: tm-oracle-iaas
ssh -i ~/.ssh/odaa.pem opc@10.0.1.160 "hostname"        # Expected: tmodaauks-rqahk1
```

**Verification:**  
Both commands return the server hostname without errors.

**Resolution Notes:**  
_[Record test results and key in use]_

---

### ACTION-11: Verify Oracle Sudo Access via Admin SSH User

**Category:** ⚠️ Required  
**Risk:** R-05 (Medium)  
**Status:** 🔲 Pending  
**Server:** ZDM Server (10.1.0.8)

**Problem:**  
ZDM uses the admin SSH user (azureuser / opc) with `sudo -u oracle` to execute Oracle commands on source and target. This must be confirmed working before migration.

**Remediation:**  
Included in `Scripts/fix_zdm_server_ORADB.sh`:

```bash
# As zdmuser on ZDM server
ssh -i ~/.ssh/odaa.pem azureuser@10.1.0.11 "sudo -u oracle id"
# Expected: uid=... (oracle) ...

ssh -i ~/.ssh/odaa.pem opc@10.0.1.160 "sudo -u oracle id"
# Expected: uid=... (oracle) ...
```

If not working, add to `/etc/sudoers` on source/target:
```
azureuser ALL=(oracle) NOPASSWD: ALL
opc       ALL=(oracle) NOPASSWD: ALL
```

**Resolution Notes:**  
_[Record outcome of sudo test]_

---

### ACTION-12: Update zdm-env.md with Missing Values

**Category:** ⚠️ Required  
**Status:** 🔲 Pending

**Problem:**  
Two fields are blank in `zdm-env.md` and block Step 3 (artifact generation):
- `OCI_OSS_NAMESPACE` — must be populated after ACTION-05
- `OCI_OSS_BUCKET_NAME` — must be populated after ACTION-06

**Remediation:**  
After completing ACTION-05 and ACTION-06, edit `prompts/Phase10-Migration/ZDM/zdm-env.md`:

```markdown
- OCI_OSS_NAMESPACE: <value from oci os ns get>
- OCI_OSS_BUCKET_NAME: zdm-oradb-migration
```

**Resolution Notes:**  
_[Record values set]_

---

### R-07: Review and Clean Up Offline Databases on Target /u02

**Category:** ⚠️ Required  
**Risk:** R-07 (Medium)  
**Status:** 🔲 Pending  
**Server:** Target (tmodaauks-rqahk1 / 10.0.1.160)

**Problem:**  
Three offline databases (`migdb`, `mydb`, `oradb01m`) occupy `/u02` on the target Exadata nodes. Current free space on `/u02` is only ~14 GB. ZDM will create a new database home and data files for ORADB on `/u02`, which may fail if space is insufficient.

**Remediation:**  
Coordinate with ODAA DBA to remove unused offline databases:

```bash
# On target node 1 as grid user or root
# 1. Confirm databases are truly unused (no active connections)
srvctl status database -db migdb
srvctl status database -db mydb  
srvctl status database -db oradb01m

# 2. Deregister from CRS and remove data files (dangerous — confirm before running)
srvctl remove database -db migdb -noprompt
srvctl remove database -db mydb -noprompt
srvctl remove database -db oradb01m -noprompt

# 3. Remove data files from ASM (if stored in ASM)
# Connect as grid/sysdba and use ASMCMD to remove
asmcmd
cd DATAC3/
ls
rm -rf <migdb_dir>
rm -rf <mydb_dir>
rm -rf <oradb01m_dir>
```

> ⚠️ **Irreversible operation.** Confirm with all stakeholders that these databases are no longer needed before deletion.

**Verification:**  
```bash
df -h /u02
# Expected: >20 GB free after cleanup
```

**Resolution Notes:**  
_[Record confirmation from stakeholders and which DBs were removed]_

---

## Verification Checklist

Before proceeding to Step 3, confirm all items below:

- [ ] ACTION-01: `SELECT LOG_MODE FROM V$DATABASE;` → `ARCHIVELOG`
- [ ] ACTION-02: `SELECT FORCE_LOGGING FROM V$DATABASE;` → `YES`
- [ ] ACTION-03: `SELECT SUPPLEMENTAL_LOG_DATA_MIN FROM V$DATABASE;` → `YES`
- [ ] ACTION-04: `SELECT STATUS FROM V$ENCRYPTION_WALLET;` → `OPEN` (not `OPEN_NO_MASTER_KEY`)
- [ ] ACTION-05: OCI namespace retrieved and recorded in zdm-env.md
- [ ] ACTION-06: OCI bucket `zdm-oradb-migration` created and recorded in zdm-env.md
- [ ] ACTION-07: ZDM credential store initialized (or will be initialized with Step 3 eval run)
- [ ] ACTION-08: Archive log destination set and disk space confirmed adequate
- [ ] ACTION-09: RMAN configured; pre-migration backup taken
- [ ] ACTION-10: zdmuser SSH access to source and target verified
- [ ] ACTION-11: sudo -u oracle works from both source and target admin users
- [ ] ACTION-12: zdm-env.md fully populated (no blank required fields)
- [ ] R-07: Target /u02 disk space confirmed adequate (>20 GB free) or offline DBs removed

---

## Re-Verification Discovery

After completing all remediation steps, re-run source and target discovery to confirm fixes:

```bash
# From ZDM server as azureuser — re-run source discovery
ssh -i ~/.ssh/zdm.pem azureuser@10.1.0.8 'bash -s' < Artifacts/Phase10-Migration/ZDM/ORADB/Step0/Scripts/zdm_orchestrate_discovery.sh source

# Save updated output to Step2/Verification/
```

Save re-verification discovery files to:  
`Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Verification/`

---

*Generated by GitHub Copilot — ODAA Migration Accelerator — Step 2: Fix Issues*  
*Based on Discovery Summary: 2026-02-27 21:36 UTC*
