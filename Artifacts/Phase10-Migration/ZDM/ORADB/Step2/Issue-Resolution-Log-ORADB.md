# Issue Resolution Log: ORADB

## Generated
- **Date:** 2026-03-02
- **Based On:** `Discovery-Summary-ORADB.md` (Step 1)
- **Migration:** ORADB (Azure IaaS `tm-oracle-iaas`) → ODAA (`tmodaauks-rqahk1`)

---

## Summary

| # | Issue | Category | Status | Script | Date Resolved | Verified By |
|---|-------|----------|--------|--------|---------------|-------------|
| 1 | PDB1 is MOUNTED — must be OPEN READ WRITE | ❌ Blocker | 🔲 Pending | `zdm_fix_source_db.sh` | | |
| 2 | ALL COLUMNS supplemental logging not enabled | ❌ Blocker | 🔲 Pending | `zdm_fix_source_db.sh` | | |
| 3 | OCI config not configured for `zdmuser` on ZDM server | ❌ Blocker | 🔲 Pending | `zdm_configure_oci.sh` | | |
| 4 | `OCI_OSS_NAMESPACE` and `OCI_OSS_BUCKET_NAME` not set in `zdm-env.md` | ⚠️ Required | 🔲 Pending | Manual + `zdm_configure_oci.sh` | | |
| 5 | Source root filesystem at 78% used (6.3 GB free) | ⚡ Recommended | 🔲 Pending | Manual steps below | | |
| 6 | ZDM server root filesystem below 50 GB recommended (24 GB free) | ⚡ Recommended | 🔲 Pending | Manual steps below | | |

---

## Issue Details

---

### Issue 1: PDB1 is MOUNTED — must be OPEN READ WRITE

**Category:** ❌ Blocker
**Status:** 🔲 Pending

**Problem:**
The source PDB1 was discovered in `MOUNTED` open mode. ZDM online physical migration requires the source PDB to be in `READ WRITE` mode before migration begins. Additionally, `SAVE STATE` is required so that PDB1 automatically reopens if the source database is restarted during the migration window.

**Discovery Evidence:**
```
PDB Name:    PDB1
PDB Status:  MOUNTED  ⚠️ (must be OPEN before migration)
```

**Remediation:**
Run the fix script as `zdmuser` on the ZDM server (`tm-vm-odaa-oracle-jumpbox`):
```bash
sudo su - zdmuser
chmod +x ~/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts/zdm_fix_source_db.sh
~/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts/zdm_fix_source_db.sh
```

The script executes the following SQL on the source database:
```sql
ALTER PLUGGABLE DATABASE PDB1 OPEN READ WRITE;
ALTER PLUGGABLE DATABASE PDB1 SAVE STATE;
```

**Verification:**
After running the script, verify:
```sql
SELECT name, open_mode, restricted
FROM   v$pdbs
WHERE  name = 'PDB1';
-- Expected: open_mode = READ WRITE, restricted = NO
```

Or re-run source discovery and confirm `PDB Status: OPEN READ WRITE ✅`.

**Rollback:**
To revert PDB1 to MOUNTED state (e.g., if deliberately kept closed):
```sql
ALTER PLUGGABLE DATABASE PDB1 CLOSE IMMEDIATE;
```

**Resolution Notes:**
_Date:_ _______________  |  _Resolved By:_ _______________  |  _Notes:_ _______________

---

### Issue 2: ALL COLUMNS Supplemental Logging Not Enabled

**Category:** ❌ Blocker
**Status:** 🔲 Pending

**Problem:**
`ONLINE_PHYSICAL` migration uses Data Guard redo application at the target. Full supplemental logging (`ALL COLUMNS`) is required so that all column values are captured in the redo stream, enabling accurate row-level changes during the active migration phase. Current state shows only minimal supplemental logging (FOREIGN KEY only).

**Discovery Evidence:**
```
Supplemental Logging (Minimal) : YES  ✅
Supplemental Logging (All Cols): NO   ⚠️  ← Must be YES
Supplemental Logging (Primary Key): NO  ⚠️
```

**Remediation:**
Run the fix script as `zdmuser` on the ZDM server (same script as Issue 1 — covers both):
```bash
~/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts/zdm_fix_source_db.sh
```

The script executes the following SQL on the source database:
```sql
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER SYSTEM SWITCH LOGFILE;
```

**Verification:**
After running the script, verify:
```sql
SELECT supplemental_log_data_min  AS supp_min,
       supplemental_log_data_pk   AS supp_pk,
       supplemental_log_data_all  AS supp_all
FROM   v$database;
-- Expected: SUPP_ALL = YES
```

**Rollback:**
To revert supplemental logging (only do this after migration completes or is abandoned):
```sql
ALTER DATABASE DROP SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
```

**Resolution Notes:**
_Date:_ _______________  |  _Resolved By:_ _______________  |  _Notes:_ _______________

---

### Issue 3: OCI Config Not Configured for zdmuser on ZDM Server

**Category:** ❌ Blocker
**Status:** 🔲 Pending

**Problem:**
ZDM requires the `zdmuser` account on the ZDM server to have a valid OCI CLI configuration (`~/.oci/config`) and API key (`~/.oci/oci_api_key.pem`) in order to:
- Authenticate to OCI and interact with Object Storage (backup staging)
- Verify and resolve the target DB OCID
- Manage ZDM job state stored in OCI

Discovery found:
```
OCI config (zdmuser):   Not verified  ⚠️
OCI config (azureuser): Not found at ~/.oci/config  ⚠️
```

**Prerequisites before running the fix script:**
1. Ensure the OCI API private key (`oci_api_key.pem`) file is copied to the ZDM server at `/home/zdmuser/.oci/oci_api_key.pem`.
   From your local machine:
   ```bash
   scp -i ~/.ssh/zdm.pem \
       /path/to/oci_api_key.pem \
       azureuser@10.1.0.8:/tmp/oci_api_key.pem

   # Then on ZDM server:
   sudo cp /tmp/oci_api_key.pem /home/zdmuser/.oci/oci_api_key.pem
   sudo chown zdmuser:zdmuser /home/zdmuser/.oci/oci_api_key.pem
   sudo chmod 600 /home/zdmuser/.oci/oci_api_key.pem
   ```
2. Confirm the API key fingerprint in OCI Console matches:
   `7f:05:c1:f2:5c:3a:46:ec:9f:95:44:c8:77:a4:50:f9`

**Remediation:**
Run the OCI configuration script as `zdmuser`:
```bash
sudo su - zdmuser
chmod +x ~/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts/zdm_configure_oci.sh
~/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts/zdm_configure_oci.sh
```

The script creates `~/.oci/config` with the following values (from `zdm-env.md`):
```ini
[DEFAULT]
user=ocid1.user.oc1..aaaaaaaakfe5cirdq7vkkrhogjrgcrgftvwb7mdoehujgchefpqv54vhsnoa
fingerprint=7f:05:c1:f2:5c:3a:46:ec:9f:95:44:c8:77:a4:50:f9
tenancy=ocid1.tenancy.oc1..aaaaaaaarvyhjcn7wkkxxx5g3o7lgqks23bmsjtsticz3gtg5xs5qyrwkftq
region=uk-london-1
key_file=/home/zdmuser/.oci/oci_api_key.pem
```

**Verification:**
```bash
# As zdmuser on ZDM server:
oci os ns get
# Expected: {"data": "<your-namespace>"}  (non-empty string)

oci iam region list --output table
# Expected: list of OCI regions including uk-london-1
```

**Rollback:**
```bash
# Remove OCI config (a backup is created automatically by the script):
rm ~/.oci/config
# Restore backup:
cp ~/.oci/config.bak.<timestamp> ~/.oci/config
```

**Resolution Notes:**
_Date:_ _______________  |  _Resolved By:_ _______________  |  _Notes:_ _______________

---

### Issue 4: OCI Object Storage Namespace and Bucket Name Not Configured

**Category:** ⚠️ Required
**Status:** 🔲 Pending

**Problem:**
`OCI_OSS_NAMESPACE` and `OCI_OSS_BUCKET_NAME` were not set in `zdm-env.md`. ZDM physical migration requires an OCI Object Storage bucket as the backup staging location. These values must be determined and set before generating the ZDM response file in Step 3.

**Steps to Resolve:**

1. **Get the Object Storage namespace** (run as `zdmuser` after OCI config is set up — Issue 3 must be resolved first):
   ```bash
   oci os ns get
   # Output: {"data": "abc123xyz"}
   # Note the value — this is your OCI_OSS_NAMESPACE
   ```

2. **Decide on a bucket name** — recommended: `zdm-migration-oradb`

3. **Create the bucket** (uncomment and adjust the bucket creation block in `zdm_configure_oci.sh`, or use OCI Console):
   ```bash
   oci os bucket create \
     --namespace-name "<your-namespace>" \
     --name "zdm-migration-oradb" \
     --compartment-id "ocid1.compartment.oc1..aaaaaaaas4upnqj72dfiivgwvn3uui5gkxo7ng6leeoifucbjiy326urbhmq" \
     --public-access-type "NoPublicAccess"
   ```
   Or: OCI Console → Storage → Object Storage & Archive Storage → Buckets → Create Bucket.

4. **Update `zdm-env.md`** with both values:
   ```
   OCI_OSS_NAMESPACE: <your-namespace>
   OCI_OSS_BUCKET_NAME: zdm-migration-oradb
   ```

**Verification:**
```bash
oci os bucket get \
  --namespace-name "<your-namespace>" \
  --bucket-name "zdm-migration-oradb"
# Expected: JSON with bucket details, no error
```

**Resolution Notes:**
_Date:_ _______________  |  _Resolved By:_ _______________  |  _Namespace:_ _______________  |  _Bucket:_ _______________

---

### Issue 5: Source Root Filesystem at 78% Used (6.3 GB Free)

**Category:** ⚡ Recommended
**Status:** 🔲 Pending

**Problem:**
The source database server (`tm-oracle-iaas`) root filesystem is at 78% utilisation with only 6.3 GB free. During `ONLINE_PHYSICAL` migration, archive logs accumulate in the FRA (`/u01/app/oracle/fast_recovery_area`) as redo is generated. If the FRA fills up, the source database will hang.

**Discovery Evidence:**
```
Root Disk Free:      6.3 GB (78% used)  ⚠️
Archive Log Dest 1:  LOCATION=/u01/app/oracle/fast_recovery_area
/mnt (temp partition): 16 GB free (available for redirect)
```

**Recommended Steps:**

1. **Monitor FRA usage before and during migration:**
   ```sql
   -- Run on source as oracle
   SELECT name,
          round(space_limit/1073741824, 2)    AS limit_gb,
          round(space_used/1073741824, 2)     AS used_gb,
          round(space_reclaimable/1073741824, 2) AS reclaimable_gb,
          number_of_files
   FROM   v$recovery_file_dest;
   ```

2. **Optional — redirect archive logs to /mnt partition** (larger, 16 GB free):
   ```sql
   ALTER SYSTEM SET log_archive_dest_1 = 'LOCATION=/mnt/resource/archivelog' SCOPE=BOTH;
   ```
   Ensure `/mnt/resource/archivelog` exists and is owned by oracle:
   ```bash
   sudo mkdir -p /mnt/resource/archivelog
   sudo chown oracle:oinstall /mnt/resource/archivelog
   ```

3. **Delete obsolete RMAN backups** if backup retention allows:
   ```bash
   rman target /
   # In RMAN:
   DELETE OBSOLETE;
   ```

**Resolution Notes:**
_Date:_ _______________  |  _Resolved By:_ _______________  |  _Action Taken:_ _______________

---

### Issue 6: ZDM Server Root Filesystem Below 50 GB Recommended

**Category:** ⚡ Recommended
**Status:** 🔲 Pending

**Problem:**
The ZDM server (`tm-vm-odaa-oracle-jumpbox`) root filesystem has only 24 GB free on a 39 GB volume. Oracle recommends 50+ GB for ZDM staging operations (log capture, temporary files). Low disk space may cause ZDM jobs to fail mid-flight.

**Discovery Evidence:**
```
/ (rootvg-rootlv): 39 GB total, 24 GB free  ⚠️ (below 50 GB recommended)
/mnt (temp):       16 GB total, 15 GB free
```

**Recommended Steps:**

1. **Check ZDM base/log usage** as `zdmuser`:
   ```bash
   du -sh /u01/app/zdmbase/
   du -sh /u01/app/zdmhome/
   find /u01/app/zdmbase/crsdata -name "*.log" -mtime +30 | xargs ls -lh | tail -20
   ```

2. **Option A — Expand the root VM disk in Azure:**
   - Azure Portal → VM `tm-vm-odaa-oracle-jumpbox` → Disks → Resize OS disk
   - Then expand the LVM volume group and logical volume:
     ```bash
     sudo pvresize /dev/sda
     sudo lvextend -l +100%FREE /dev/rootvg/rootlv
     sudo xfs_growfs /
     ```

3. **Option B — Redirect ZDM staging to /mnt** (temporary disk, larger):
   - Set `ZDM_BASE` to point to a path on `/mnt` before job start (consult ZDM documentation for `zdm.base` parameter)
   - Note: `/mnt` is ephemeral on Azure VMs — not suitable for long-lived staging

4. **Purge old ZDM job logs:**
   ```bash
   # ZDM job logs are stored in:
   ls /u01/app/zdmbase/crsdata/*/rhp/zdm/log/
   # Archive or delete logs from completed/failed jobs older than migration window
   ```

**Resolution Notes:**
_Date:_ _______________  |  _Resolved By:_ _______________  |  _Action Taken:_ _______________

---

## Completion Checklist

Before proceeding to Step 3 (Generate Migration Artifacts), verify ALL of the following:

- [ ] **Issue 1:** PDB1 open mode verified as `READ WRITE` (query `v$pdbs`)
- [ ] **Issue 2:** `supplemental_log_data_all = YES` verified in `v$database`
- [ ] **Issue 3:** `oci os ns get` succeeds as `zdmuser` on ZDM server
- [ ] **Issue 4:** `OCI_OSS_NAMESPACE` and `OCI_OSS_BUCKET_NAME` updated in `zdm-env.md` and bucket exists in OCI
- [ ] **Issue 5:** FRA usage monitored; archive log redirect in place if needed
- [ ] **Issue 6:** ZDM server disk space confirmed adequate for migration staging
- [ ] ZDM EVAL prechecks pass with latest `iaas_to_odaa.rsp` (re-run `zdmcli migrate database ... -eval`)

---

## Remediation Scripts

| Script | Location | Purpose | Run On |
|--------|----------|---------|--------|
| `zdm_fix_source_db.sh` | `Step2/Scripts/` | Open PDB1 + enable ALL supplemental logging | ZDM server as `zdmuser` |
| `zdm_configure_oci.sh` | `Step2/Scripts/` | Configure OCI CLI for `zdmuser` + verify connectivity | ZDM server as `zdmuser` |

---

*Generated by ZDM Migration Planning - Step 2 | 2026-03-02*
