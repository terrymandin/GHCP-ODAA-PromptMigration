# Issue Resolution Log: ORADB

| Field | Value |
|---|---|
| **Project** | ORADB |
| **Document** | Issue Resolution Log |
| **Generated** | 2026-02-27 |
| **Based On** | Discovery Summary — ORADB (2026-02-27 21:36 UTC run) |
| **Migration Target** | Oracle Database@Azure (Exadata X11M, UK South / uk-london-1) |

---

## Summary

| # | Issue | Category | Priority | Status | Date Resolved | Verified By |
|---|-------|----------|----------|--------|---------------|-------------|
| 01 | Enable ARCHIVELOG mode on source | ❌ Blocker | CRITICAL | 🔲 Pending | | |
| 02 | Enable Force Logging on source | ❌ Blocker | CRITICAL | 🔲 Pending | | |
| 03 | Enable Supplemental Logging on source | ❌ Blocker | CRITICAL | 🔲 Pending | | |
| 04 | Configure TDE Master Key on target | ❌ Blocker | CRITICAL | 🔲 Pending | | |
| 05 | Discover OCI Object Storage Namespace | ❌ Blocker | HIGH | 🔲 Pending | | |
| 06 | Create OCI Object Storage Bucket | ❌ Blocker | HIGH | 🔲 Pending | | |
| 07 | Initialize ZDM Credential Store | ❌ Blocker | HIGH | 🔲 Pending | | |
| 08 | Configure archive log destination (source disk tight) | ⚠️ Required | MEDIUM | 🔲 Pending | | |
| 09 | Configure RMAN on source | ⚠️ Required | MEDIUM | 🔲 Pending | | |
| 10 | Verify SSH key access for zdmuser | ⚠️ Required | MEDIUM | 🔲 Pending | | |
| 11 | Update zdm-env.md with OCI OSS values | ⚠️ Required | MEDIUM | 🔲 Pending | | |
| 12 | Evaluate removal of offline DBs on target /u02 | ⚡ Recommended | LOW | 🔲 Pending | | |
| 13 | OCI config for azureuser on ZDM server | ⚡ Recommended | LOW | 🔲 Pending | | |

---

## Issue Details

---

### Issue 01: Enable ARCHIVELOG Mode on Source

**Category:** ❌ Blocker  
**Priority:** CRITICAL  
**Status:** 🔲 Pending  
**Risk Reference:** R-01  
**Script:** [Scripts/fix_01_source_archivelog_forcelogging_supplemental.sh](Scripts/fix_01_source_archivelog_forcelogging_supplemental.sh)

**Problem:**  
Source database `ORADB1` (DB_UNIQUE_NAME: `oradb1`, SID: `oradb`) on host `10.1.0.11` is in `NOARCHIVELOG` mode. ZDM `ONLINE_PHYSICAL` migration uses Oracle Data Guard for replication, which requires ARCHIVELOG mode to be enabled on the source. Without it, ZDM cannot apply redo logs to the standby (target) instance and real-time replication will not function.

**Impact:** ZDM ONLINE_PHYSICAL migration will fail at initialization.

**Remediation:**  
Run `fix_01_source_archivelog_forcelogging_supplemental.sh` on the ZDM server. This script SSHes to the source and executes the required SQL via the `oracle` user. A brief source DB restart is required.

```bash
# On ZDM server as azureuser
cd /path/to/scripts
chmod +x fix_01_source_archivelog_forcelogging_supplemental.sh
./fix_01_source_archivelog_forcelogging_supplemental.sh
```

**Verification:**
```sql
-- Connect as SYSDBA on source
SELECT LOG_MODE FROM V$DATABASE;
-- Expected: ARCHIVELOG
```

**Rollback:**
```sql
-- Only perform if absolutely necessary; disabling archivelog stops archiving
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE NOARCHIVELOG;
ALTER DATABASE OPEN;
```

**Resolution Notes:**  
`[Date] [By Whom] — [Notes]`

---

### Issue 02: Enable Force Logging on Source

**Category:** ❌ Blocker  
**Priority:** CRITICAL  
**Status:** 🔲 Pending  
**Risk Reference:** R-01  
**Script:** [Scripts/fix_01_source_archivelog_forcelogging_supplemental.sh](Scripts/fix_01_source_archivelog_forcelogging_supplemental.sh) *(combined with Issue 01 and 03)*

**Problem:**  
Force Logging is disabled on the source database. Without Force Logging, direct-path writes (e.g. `INSERT /*+ APPEND */`, SQL*Loader direct path) bypass the redo log and will not be captured in the Data Guard standby redo stream. This can cause data divergence between source and target during migration.

**Impact:** Silent data loss risk during ONLINE_PHYSICAL migration if any nologging writes occur.

**Remediation:**  
Handled within `fix_01_source_archivelog_forcelogging_supplemental.sh`. Runs after ARCHIVELOG is enabled:
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
`[Date] [By Whom] — [Notes]`

---

### Issue 03: Enable Supplemental Logging on Source

**Category:** ❌ Blocker  
**Priority:** CRITICAL  
**Status:** 🔲 Pending  
**Risk Reference:** R-02  
**Script:** [Scripts/fix_01_source_archivelog_forcelogging_supplemental.sh](Scripts/fix_01_source_archivelog_forcelogging_supplemental.sh) *(combined with Issues 01 and 02)*

**Problem:**  
Supplemental logging is `NONE` on the source. While ZDM ONLINE_PHYSICAL primarily relies on redo shipping (not LogMiner), enabling minimum supplemental logging is required by ZDM to ensure that Data Guard redo is complete and consistent.

**Impact:** ZDM pre-check will flag this as a missing prerequisite and may refuse to start.

**Remediation:**  
Handled within `fix_01_source_archivelog_forcelogging_supplemental.sh`:
```sql
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
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
`[Date] [By Whom] — [Notes]`

---

### Issue 04: Configure TDE Master Key on Target

**Category:** ❌ Blocker  
**Priority:** CRITICAL  
**Status:** 🔲 Pending  
**Risk Reference:** R-03  
**Script:** [Scripts/fix_04_target_tde_master_key.sh](Scripts/fix_04_target_tde_master_key.sh)

**Problem:**  
The target ODAA CDB wallet status is `OPEN_NO_MASTER_KEY`. ZDM requires an active TDE master key in the target CDB before it can provision the migrated PDB. Without a master key, Oracle will not open an encrypted tablespace, and ZDM will fail during the database registration step.

**Impact:** ZDM will abort with a TDE/wallet error when attempting to open or register the PDB on the target.

**Remediation:**  
Run `fix_04_target_tde_master_key.sh` on the ZDM server. The script SSHes to the target node and creates a new TDE master key in the existing wallet. You will be prompted for the wallet password.

```bash
# On ZDM server — will prompt for TARGET_TDE_WALLET_PASSWORD
./Scripts/fix_04_target_tde_master_key.sh
```

**Verification:**
```sql
SELECT STATUS, WALLET_TYPE FROM V$ENCRYPTION_WALLET;
-- Expected: OPEN (not OPEN_NO_MASTER_KEY), WALLET_TYPE = PASSWORD or AUTOLOGIN
```

**Rollback:**  
TDE master key creation cannot be simply undone. If incorrect wallet password was used, re-run with correct password. Contact Oracle Support if wallet is corrupted.

**Resolution Notes:**  
`[Date] [By Whom] — [Notes]`

---

### Issue 05: Discover OCI Object Storage Namespace

**Category:** ❌ Blocker  
**Priority:** HIGH  
**Status:** 🔲 Pending  
**Risk Reference:** R-04  
**Script:** [Scripts/fix_05_discover_oci_namespace.sh](Scripts/fix_05_discover_oci_namespace.sh)

**Problem:**  
The `OCI_OSS_NAMESPACE` field in `zdm-env.md` is blank. ZDM uses OCI Object Storage as the data transfer medium (`OSS`) to copy RMAN backup sets from source to target. Without the namespace, the ZDM response file cannot be correctly configured.

**Impact:** ZDM response file generation will be incomplete; ZDM migrate command will fail on OSS configuration.

**Remediation:**  
Run `fix_05_discover_oci_namespace.sh` on the ZDM server as `zdmuser` (OCI CLI is already configured for zdmuser):

```bash
# On ZDM server as zdmuser
./Scripts/fix_05_discover_oci_namespace.sh
# Note the namespace output and update zdm-env.md OCI_OSS_NAMESPACE
```

**Verification:**
```bash
# Should return a JSON object with "data" key containing the namespace string
oci os ns get
```

**Resolution Notes:**  
`[Date] [By Whom] — OCI_OSS_NAMESPACE = ______________`

---

### Issue 06: Create OCI Object Storage Bucket

**Category:** ❌ Blocker  
**Priority:** HIGH  
**Status:** 🔲 Pending  
**Risk Reference:** R-04  
**Script:** [Scripts/fix_06_create_oci_bucket.sh](Scripts/fix_06_create_oci_bucket.sh)

**Problem:**  
No OCI Object Storage bucket exists for the migration data transfer. ZDM requires a pre-existing bucket in the same OCI region (`uk-london-1`) and compartment to stage RMAN backup sets.

**Impact:** ZDM migrate command will fail when attempting to write backup pieces to OCI Object Storage.

**Remediation:**  
Run `fix_06_create_oci_bucket.sh` on the ZDM server as `zdmuser`. The script creates bucket `zdm-oradb-migration` in the configured compartment and region:

```bash
# On ZDM server as zdmuser — requires OCI_OSS_NAMESPACE from Issue 05
./Scripts/fix_06_create_oci_bucket.sh
```

**Verification:**
```bash
oci os bucket get --bucket-name zdm-oradb-migration --namespace <namespace>
# Should return bucket metadata without error
```

**Resolution Notes:**  
`[Date] [By Whom] — Bucket Name = zdm-oradb-migration`

---

### Issue 07: Initialize ZDM Credential Store

**Category:** ❌ Blocker  
**Priority:** HIGH  
**Status:** 🔲 Pending  
**Risk Reference:** R-05  
**Script:** [Scripts/fix_07_init_zdm_credential_store.sh](Scripts/fix_07_init_zdm_credential_store.sh)

**Problem:**  
The ZDM credential store directory (`/u01/app/zdmhome/zdm/cred`) does not exist. ZDM `zdmcli migrate database` requires Oracle Wallet entries containing the source and target SYS database passwords. Without the credential store, ZDM cannot authenticate to the source and target databases.

**Impact:** `zdmcli migrate database` will fail with a credential/authentication error at startup.

**Remediation:**  
Run `fix_07_init_zdm_credential_store.sh` on the ZDM server as `zdmuser`. The script initializes the Oracle Wallet and adds credentials for source and target SYS accounts. You will be prompted for passwords — do not store them in plain text.

```bash
# On ZDM server as zdmuser
./Scripts/fix_07_init_zdm_credential_store.sh
```

**Verification:**
```bash
# List wallet contents
mkstore -wrl /u01/app/zdmhome/zdm/cred -listCredential
```

**Resolution Notes:**  
`[Date] [By Whom] — Credential store initialized with source/target SYS credentials`

---

### Issue 08: Configure Archive Log Destination (Source Disk Tight)

**Category:** ⚠️ Required  
**Priority:** MEDIUM  
**Status:** 🔲 Pending  
**Risk Reference:** R-06  
**Script:** [Scripts/fix_08_configure_archive_destination.sh](Scripts/fix_08_configure_archive_destination.sh)

**Problem:**  
Source disk has only ~8.6 GB free on `/` (filesystem at 70%). Once ARCHIVELOG mode is enabled (Issue 01), archive logs will accumulate under the default destination (`/u01/app/oracle/product/12.2.0/dbhome_1/dbs/arch`). During an active migration with Data Guard shipping redo, archive log accumulation could fill the disk and freeze the source database.

**Impact:** If archive log destination fills, Oracle will hang all DML on the source — causing an unplanned outage during migration.

**Remediation:**  
Run `fix_08_configure_archive_destination.sh` to redirect archive logs to a dedicated path with sufficient space (e.g., `/u01/app/oracle/archive`) or assess if an additional mount point is required:

```bash
./Scripts/fix_08_configure_archive_destination.sh
```

**Verification:**
```sql
SHOW PARAMETER log_archive_dest_1;
-- Should show the new path
ARCHIVE LOG LIST;
-- Should confirm archive destination
```

**Resolution Notes:**  
`[Date] [By Whom] — Archive destination set to: ______________`

---

### Issue 09: Configure RMAN on Source

**Category:** ⚠️ Required  
**Priority:** MEDIUM  
**Status:** 🔲 Pending  
**Risk Reference:** R-08  
**Script:** [Scripts/fix_09_configure_rman.sh](Scripts/fix_09_configure_rman.sh)

**Problem:**  
RMAN is not configured on the source database. No backup policies or recent backups exist. It is strongly recommended to take an RMAN backup of the source before initiating ZDM migration. Additionally, for `OFFLINE_PHYSICAL` method, RMAN is required.

**Impact:** No pre-migration backup; risk of data loss if migration fails and source database is damaged.

**Remediation:**  
Run `fix_09_configure_rman.sh` to configure RMAN and optionally take an initial backup:

```bash
./Scripts/fix_09_configure_rman.sh
```

**Verification:**
```bash
# On source as oracle
rman TARGET /
LIST BACKUP SUMMARY;
```

**Resolution Notes:**  
`[Date] [By Whom] — RMAN configured; initial backup completed`

---

### Issue 10: Verify SSH Key Access for zdmuser

**Category:** ⚠️ Required  
**Priority:** MEDIUM  
**Status:** 🔲 Pending  
**Risk Reference:** R-07  
**Script:** [Scripts/fix_10_verify_ssh_access.sh](Scripts/fix_10_verify_ssh_access.sh)

**Problem:**  
Although Step 0 discovery succeeded (confirming `azureuser` can SSH to both source and target), the `oracle` user's SSH home directory is not accessible from the discovery user. ZDM requires passwordless SSH from the ZDM server to the `oracle` user (or admin user with sudo to oracle) on both source and target.

**Impact:** ZDM zdmcli will fail on file operations if SSH as `oracle` is blocked and sudo is not configured for the admin user.

**Remediation:**  
Run `fix_10_verify_ssh_access.sh` to verify all required SSH paths from the ZDM server:

```bash
./Scripts/fix_10_verify_ssh_access.sh
```

**Verification:**  
All tests in the script should output `OK`.

**Resolution Notes:**  
`[Date] [By Whom] — SSH access verified for all paths`

---

### Issue 11: Update zdm-env.md with OCI OSS Values

**Category:** ⚠️ Required  
**Priority:** MEDIUM  
**Status:** 🔲 Pending

**Problem:**  
`zdm-env.md` has two blank required fields:
- `OCI_OSS_NAMESPACE` — must be populated after running `fix_05_discover_oci_namespace.sh`
- `OCI_OSS_BUCKET_NAME` — must be populated after running `fix_06_create_oci_bucket.sh`

**Remediation:**  
After completing Issues 05 and 06, manually update `zdm-env.md`:
```markdown
- OCI_OSS_NAMESPACE: <value from oci os ns get>
- OCI_OSS_BUCKET_NAME: zdm-oradb-migration
```

**Resolution Notes:**  
`[Date] [By Whom] — zdm-env.md updated`

---

### Issue 12: Evaluate Removal of Offline DBs on Target /u02

**Category:** ⚡ Recommended  
**Priority:** LOW  
**Status:** 🔲 Pending

**Problem:**  
Three offline databases (`migdb`, `mydb`, `oradb01m`) exist on the target and consume space on `/u02` (57 GB total, only 14 GB free). The new ORADB database home and files will also be placed under `/u02`. Although the database data files land on ASM (`+DATAC3`), the `/u02` Oracle Home files could be impacted.

**Remediation:**  
Coordinate with ODAA administrators to deregister/remove stale offline databases. Use OCI Console or:
```bash
# As oracle on target — verify these DBs are truly unused before removing
srvctl status database -db migdb
srvctl remove database -db migdb
```

**Resolution Notes:**  
`[Date] [By Whom] — Stale databases removed / confirmed unused`

---

### Issue 13: OCI Config for azureuser on ZDM Server

**Category:** ⚡ Recommended  
**Priority:** LOW  
**Status:** 🔲 Pending

**Problem:**  
The OCI CLI config (`~/.oci/config`) is missing for `azureuser` on the ZDM server. ZDM itself runs as `zdmuser` (whose config is present), so this is not a ZDM blocker. However, manual OCI operations (monitoring, bucket inspection) run as `azureuser` will fail without OCI config.

**Remediation:**  
Copy or link from zdmuser's config:
```bash
# As azureuser on ZDM server
mkdir -p ~/.oci
cp /home/zdmuser/.oci/config ~/.oci/config
cp /home/zdmuser/.oci/oci_api_key.pem ~/.oci/oci_api_key.pem
chmod 600 ~/.oci/config ~/.oci/oci_api_key.pem
# Verify
oci os ns get
```

**Resolution Notes:**  
`[Date] [By Whom] — OCI config copied for azureuser`

---

## Completion Checklist

Before proceeding to Step 3 (Generate Migration Artifacts), confirm:

- [ ] Issue 01: ARCHIVELOG enabled on source — verified with `SELECT LOG_MODE FROM V$DATABASE`
- [ ] Issue 02: Force Logging enabled on source — verified with `SELECT FORCE_LOGGING FROM V$DATABASE`
- [ ] Issue 03: Supplemental Logging enabled on source — verified with `SELECT SUPPLEMENTAL_LOG_DATA_MIN, SUPPLEMENTAL_LOG_DATA_ALL FROM V$DATABASE`
- [ ] Issue 04: TDE Master Key created on target — verified with `SELECT STATUS FROM V$ENCRYPTION_WALLET`
- [ ] Issue 05: OCI OSS Namespace discovered and recorded
- [ ] Issue 06: OCI OSS Bucket created (`zdm-oradb-migration`)
- [ ] Issue 07: ZDM Credential Store initialized with source/target SYS credentials
- [ ] Issue 08: Archive log destination verified — sufficient disk space confirmed
- [ ] Issue 09: RMAN configured; pre-migration backup taken
- [ ] Issue 10: SSH access verified for all ZDM paths
- [ ] Issue 11: `zdm-env.md` updated with `OCI_OSS_NAMESPACE` and `OCI_OSS_BUCKET_NAME`
- [ ] Migration Questionnaire (`Migration-Questionnaire-ORADB.md`) — all `❓ [REQUIRED]` and `❓ [DECISION]` items completed

---

*Generated by GitHub Copilot — ODAA Migration Accelerator — Step 2: Fix Issues*  
*Based on: Discovery-Summary-ORADB.md (2026-02-27 21:36 UTC)*
