# Issue Resolution Log: ORADB

> **Generated:** 2026-03-03
> **Source:** Discovery Summary `Discovery-Summary-ORADB.md` (Step1)
> **Target Output Directory:** `Artifacts/Phase10-Migration/ZDM/ORADB/Step2/`

---

## Summary

| # | Issue | Category | Priority | Status | Date Resolved | Verified By |
|---|-------|----------|----------|--------|---------------|-------------|
| 1 | OCI CLI config missing on ZDM server | ❌ Blocker | HIGH | 🔲 Pending | | |
| 2 | Password file missing on ODAA target | ❌ Blocker | HIGH | 🔲 Pending | | |
| 3 | Target database not open during discovery | ❌ Blocker | HIGH | 🔲 Pending | | |
| 4 | TDE wallet has no master encryption key on target | ⚠️ Required | HIGH | 🔲 Pending | | |
| 5 | SSH key mismatch — source key `iaas.pem` vs `odaa.pem` in zdm-env.md | ⚠️ Required | HIGH | 🔲 Pending | | |
| 6 | OCI Object Storage bucket not configured | ⚠️ Required | HIGH | 🔲 Pending | | |
| 7 | Source root filesystem 81% full (5.6 GB free) | ⚡ Recommendation | MEDIUM | 🔲 Pending | | |
| 8 | Target Oracle Home path unconfirmed (dbhome_1 vs dbhome_2) | ⚠️ Required | HIGH | 🔲 Pending | | |

---

## Issue Details

### Issue 1: OCI CLI config missing on ZDM server

**Category:** ❌ Blocker
**Status:** 🔲 Pending
**Script:** `Scripts/fix_oci_cli_config.sh`

**Problem:**
The OCI CLI is installed on the ZDM server (version 3.73.1), but the config file does not exist at the required path for the `zdmuser` account: `/home/zdmuser/.oci/config`. Without a valid OCI config, ZDM cannot authenticate to OCI Object Storage for the backup/transfer phase of `ONLINE_PHYSICAL` migration. The config was found missing at `/home/azureuser/.oci/config` (wrong user context — must be under `zdmuser`).

**What the script does:**
- Creates `/home/zdmuser/.oci/` directory with correct permissions
- Writes `/home/zdmuser/.oci/config` with `[DEFAULT]` profile using OCIDs from `zdm-env.md`
- Sets file permissions to `600`
- Verifies OCI connectivity by running `oci os ns get`

**Prerequisites before running:**
- The OCI API private key (`oci_api_key.pem`) must already be uploaded to `/home/zdmuser/.oci/oci_api_key.pem` on the ZDM server
- The `oci` CLI binary must be on the `zdmuser` PATH

**Remediation:**
```bash
# Run as zdmuser on ZDM server
sudo su - zdmuser
cd ~/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts
bash fix_oci_cli_config.sh
```

**Verification:**
```bash
# Run as zdmuser on ZDM server
oci os ns get --config-file /home/zdmuser/.oci/config
# Expected: JSON output with "data": "<namespace>"
```

**Resolution Notes:**
_Update when resolved — date, by whom, OCI namespace returned._

---

### Issue 2: Password file missing on ODAA target

**Category:** ❌ Blocker
**Status:** 🔲 Pending
**Script:** `Scripts/fix_target_password_file.sh`

**Problem:**
The target ODAA node (`tmodaauks-rqahk1`, 10.0.1.160) has no Oracle password file for the `oradb011` / `oradb01` database. ZDM requires a password file on the target to authenticate as SYS during the `ONLINE_PHYSICAL` migration (Data Guard setup requires SYS password authentication). Discovery output confirmed: `Password File: NOT FOUND`.

**What the script does:**
- Connects via SSH to the ODAA target node as `opc`
- Runs `orapwd` as the `oracle` user to create `orapworadb01` in the Oracle DB Home `dbs/` directory
- Verifies the file was created and has correct permissions

**Prerequisites before running:**
- Confirm the correct Oracle Home path (`dbhome_1` or `dbhome_2`) — see Issue 8
- Obtain the SYS password for the new target database (ZDM will use this during migration)
- SSH key `~/.ssh/odaa.pem` must grant access to `opc@10.0.1.160`

**Remediation:**
```bash
# Run as zdmuser on ZDM server
sudo su - zdmuser
cd ~/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts
bash fix_target_password_file.sh
# You will be prompted for:
#   1. Oracle Home path (dbhome_1 or dbhome_2)
#   2. SYS password to set in the password file
```

**Verification:**
```bash
# Run as zdmuser on ZDM server
ssh -i ~/.ssh/odaa.pem opc@10.0.1.160 \
  "sudo -u oracle ls -la /u02/app/oracle/product/19.0.0.0/dbhome_1/dbs/orapw*"
# Expected: file listed with owner oracle, permissions 640 or 600
```

**Resolution Notes:**
_Update when resolved — date, by whom, Oracle Home confirmed, password file path._

---

### Issue 3: Target database not open during discovery

**Category:** ❌ Blocker
**Status:** 🔲 Pending
**Script:** `Scripts/fix_open_target_db.sh`

**Problem:**
During Step 0 discovery, the target ODAA database was in MOUNT state and queries against `v$database` returned `ORA-01219`. The database was not fully open. This means ZDM cannot run `ZDM_VALIDATE_TGT` successfully until the target database is open and accessible. Additionally, several configuration parameters (DB name, character set, open mode) could not be verified.

**What the script does:**
- Connects via SSH to the ODAA target node
- Checks the current open mode of the target database
- If the database is in MOUNT state, issues `ALTER DATABASE OPEN` (as DBA decision — script prompts before executing)
- Verifies the database is `READ WRITE` after open

**Prerequisites before running:**
- Confirm the correct Oracle Home path and SID for the target (`oradb011` / `oradb01`)
- Ensure DBA approval to open the database

**Remediation:**
```bash
# Run as zdmuser on ZDM server
sudo su - zdmuser
cd ~/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts
bash fix_open_target_db.sh
```

**Verification:**
```bash
# Verify target DB is open after fix
ssh -i ~/.ssh/odaa.pem opc@10.0.1.160 \
  "sudo -u oracle bash -c 'export ORACLE_HOME=/u02/app/oracle/product/19.0.0.0/dbhome_1; export ORACLE_SID=oradb011; export PATH=\${ORACLE_HOME}/bin:\${PATH}; sqlplus -S / as sysdba <<EOF
SELECT OPEN_MODE FROM V\\\$DATABASE;
EXIT;
EOF'"
# Expected: READ WRITE
```

**Resolution Notes:**
_Update when resolved — date, open mode confirmed._

---

### Issue 4: TDE wallet has no master encryption key on target (Manual DBA Action Required)

**Category:** ⚠️ Required
**Status:** 🔲 Pending
**Script:** N/A — DBA decision required

**Problem:**
The ODAA target database wallet status is `OPEN_NO_MASTER_KEY`. ZDM physical migration to ODAA/ExaDB-D environments typically requires TDE to be configured when the target is Exadata. The source database (`ORADB1` on Oracle Linux) does NOT have TDE enabled (`TDE_CONFIGURATION: NOT_AVAILABLE`). This mismatch is the likely cause of prior `ZDM_VALIDATE_TGT` failures (Jobs 18–34).

**Options:**

| Option | Description | Recommendation |
|--------|-------------|----------------|
| **Option A** | Enable TDE on SOURCE before migration using `zdm-env.md` parameters; ZDM passes `-tdekeystorepasswd` | Recommended for ODAA targets — encrypts data at rest on Exadata |
| **Option B** | Explicitly disable TDE enforcement in ZDM RSP: set `TGT_SKIP_DATAPATCH=FALSE` and confirm ODAA doesn't mandate TDE | Check with Oracle ODAA support — ODAA normally mandates TDE |
| **Option C** | Configure TDE master key on TARGET only; ZDM will handle the rest for physical migration | May be sufficient if ZDM allows enabling TDE on target during migration |

**Action Required:**
1. Contact Oracle ODAA support / DBA team to confirm TDE requirements for this ODAA instance
2. If TDE on source is required: enable TDE wallet on source and set master key before running ZDM
3. Update `zdm-env.md` with `TDE_KEYSTORE_PASSWD` once strategy is confirmed
4. Update Issue Resolution Log with decision

**TDE Enablement on Source (if Option A chosen):**
```sql
-- Connect as SYS on source (ORADB1)
-- Create and open the software keystore for the CDB
ADMINISTER KEY MANAGEMENT CREATE KEYSTORE '/u01/app/oracle/product/12.2.0/dbhome_1/admin/oradb/wallet' IDENTIFIED BY "<walletPassword>";
ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN IDENTIFIED BY "<walletPassword>";
ADMINISTER KEY MANAGEMENT SET KEY IDENTIFIED BY "<walletPassword>" WITH BACKUP;
-- Verify
SELECT * FROM v$encryption_wallet;
-- Then for each PDB:
ALTER SESSION SET CONTAINER = PDB1;
ADMINISTER KEY MANAGEMENT SET KEY IDENTIFIED BY "<walletPassword>" WITH BACKUP CONTAINER = CURRENT;
```

**Resolution Notes:**
_Update with DBA/Oracle support decision — date, chosen option, confirmed configuration._

---

### Issue 5: SSH key mismatch — source key `iaas.pem` vs `odaa.pem`

**Category:** ⚠️ Required
**Status:** 🔲 Pending
**Script:** `Scripts/verify_fixes.sh` (includes SSH connectivity test)

**Problem:**
`zdm-env.md` lists `SOURCE_SSH_KEY: ~/.ssh/odaa.pem` for the source database server, but the ZDM server holds `iaas.pem` as the SSH key specifically for the source database. Prior successful ZDM EVAL jobs used `-srcarg2 identity_file:/home/zdmuser/iaas.pem`, confirming `iaas.pem` is the correct source key. Using the wrong key will cause ZDM job failure at `ZDM_VALIDATE_SRC`.

**Recommended Action:**
Update `zdm-env.md` to set `SOURCE_SSH_KEY: ~/.ssh/iaas.pem` to match the actual working key, OR confirm that `odaa.pem` also grants access to the source server.

**Verification Commands:**
```bash
# Run as zdmuser on ZDM server — test which key grants access to source
ssh -i ~/.ssh/iaas.pem azureuser@10.1.0.11 "sudo -u oracle whoami"
# Expected: oracle

ssh -i ~/.ssh/odaa.pem azureuser@10.1.0.11 "sudo -u oracle whoami"
# If this ALSO returns "oracle", both keys work
# If this fails, iaas.pem is the correct key — update zdm-env.md
```

**Resolution Notes:**
_Update zdm-env.md once confirmed — which key is the correct source key._

---

### Issue 6: OCI Object Storage bucket not configured

**Category:** ⚠️ Required
**Status:** 🔲 Pending
**Script:** `Scripts/fix_oci_cli_config.sh` (includes bucket creation)

**Problem:**
`zdm-env.md` has `OCI_OSS_NAMESPACE` and `OCI_OSS_BUCKET_NAME` both blank. ZDM `ONLINE_PHYSICAL` migration using OCI Object Storage requires a valid bucket in the target OCI region. Without this, the ZDM response file cannot be fully populated for Step 3.

**Recommended Action:**
After OCI CLI is configured (Issue 1), run:
```bash
# Get namespace
oci os ns get --config-file /home/zdmuser/.oci/config

# Create bucket (replace <NAMESPACE> and confirm region)
oci os bucket create \
  --config-file /home/zdmuser/.oci/config \
  --compartment-id ocid1.compartment.oc1..aaaaaaaas4upnqj72dfiivgwvn3uui5gkxo7ng6leeoifucbjiy326urbhmq \
  --name zdm-oradb-migration \
  --region uk-london-1

# Update zdm-env.md with:
# OCI_OSS_NAMESPACE: <value from ns get>
# OCI_OSS_BUCKET_NAME: zdm-oradb-migration
```

**Resolution Notes:**
_Update zdm-env.md with namespace and bucket name once created._

---

### Issue 7: Source root filesystem 81% full

**Category:** ⚡ Recommendation
**Status:** 🔲 Pending

**Problem:**
Source server root filesystem (`/dev/sda2`) is 81% used with only 5.6 GB free. ZDM stages RMAN backup pieces and archive logs during `ONLINE_PHYSICAL` migration. The FRA is on root at `/u01/app/oracle/fast_recovery_area`. If the FRA fills during migration, the job will fail.

**Recommended Actions:**
1. Check current FRA usage and configured limit:
   ```sql
   -- Run on source as SYS
   SELECT * FROM V$RECOVERY_FILE_DEST;
   SELECT * FROM V$FLASH_RECOVERY_AREA_USAGE;
   ```
2. Consider relocating FRA to ephemeral disk (`/mnt/resource`, 13 GB free):
   ```sql
   -- Requires DBA approval — ephemeral disk is lost on VM restart
   ALTER SYSTEM SET db_recovery_file_dest='/mnt/resource/fra' SCOPE=BOTH;
   ALTER SYSTEM SET db_recovery_file_dest_size=10G SCOPE=BOTH;
   ```
3. Or purge obsolete RMAN backups:
   ```bash
   rman target /
   DELETE NOPROMPT OBSOLETE;
   CROSSCHECK BACKUP;
   DELETE NOPROMPT EXPIRED BACKUP;
   ```

**Resolution Notes:**
_Update with action taken — FRA relocated, purge completed, or accepted as low risk._

---

### Issue 8: Target Oracle Home path unconfirmed (dbhome_1 vs dbhome_2)

**Category:** ⚠️ Required
**Status:** 🔲 Pending

**Problem:**
Discovery found two potential Oracle DB homes on the ODAA target:
- `/u02/app/oracle/product/19.0.0.0/dbhome_1`
- `/u02/app/oracle/product/19.0.0.0/dbhome_2`

The active `oradb011` instance must be identified by running this check as `oracle` on the ODAA node:

```bash
ssh -i ~/.ssh/odaa.pem opc@10.0.1.160 \
  "sudo -u oracle bash -c 'cat /etc/oratab | grep oradb'"
# Also check:
ssh -i ~/.ssh/odaa.pem opc@10.0.1.160 \
  "sudo -u oracle bash -c 'ps -ef | grep pmon | grep oradb'"
```

**Resolution Notes:**
_Update with confirmed dbhome path — required for Issue 2 (password file creation) and Step 3 ZDM RSP._

---

## Blocker Checklist

Before proceeding to Step 3, all items below must be ✅:

- [ ] **Issue 1**: OCI CLI config created at `/home/zdmuser/.oci/config`; `oci os ns get` returns namespace
- [ ] **Issue 2**: Password file `orapworadb01` exists on ODAA target under correct `dbs/` path
- [ ] **Issue 3**: Target database `oradb011` is in `READ WRITE` open mode
- [ ] **Issue 4**: TDE strategy confirmed and implemented (DBA decision documented)
- [ ] **Issue 5**: Source SSH key confirmed (`iaas.pem`); `zdm-env.md` updated if needed
- [ ] **Issue 6**: OCI Object Storage bucket created; `zdm-env.md` updated with namespace + bucket
- [ ] **Issue 7**: Source disk space reviewed; risk accepted or FRA relocated
- [ ] **Issue 8**: Target Oracle Home path confirmed; `zdm-env.md` or questionnaire updated
- [ ] **All Scripts Run**: `verify_fixes.sh` executed; all 3 blocker checks show PASS
- [ ] **Results Committed**: `Verification-Results-ORADB.md` committed to repo

---

*Generated by ZDM Migration Planning — Step 2 | 2026-03-03*
