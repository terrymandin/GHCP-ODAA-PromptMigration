# Issue Resolution Log: ORADB

## Generated
- **Date:** 2026-03-02
- **Based On:** Discovery-Summary-ORADB.md (Step 1 output)
- **Migration Method:** ONLINE_PHYSICAL (Azure IaaS → ODAA)

---

## Summary

| # | Issue | Category | Priority | Status | Date Resolved | Verified By |
|---|-------|----------|----------|--------|---------------|-------------|
| 1 | Open PDB1 on source | ❌ Blocker | Critical | 🔲 Pending | | |
| 2 | Enable ALL COLUMNS supplemental logging | ❌ Blocker | Critical | 🔲 Pending | | |
| 3 | Configure OCI config for zdmuser | ❌ Blocker | Critical | 🔲 Pending | | |
| 4 | Monitor source root disk space | ⚡ Recommended | Medium | 🔲 Pending | | |
| 5 | Expand ZDM server root filesystem | ⚡ Recommended | Medium | 🔲 Pending | | |

---

## Issue Details

---

### Issue 1: Open PDB1 on Source

**Category:** ❌ Blocker  
**Status:** 🔲 Pending

**Problem:**  
PDB1 on the source database `ORADB1` (SID: `oradb`) is in `MOUNTED` state. ZDM physical online migration requires the source PDB to be in `READ WRITE` (open) mode before migration can begin. The PDB state must also be persisted so that it survives an instance restart.

**Remediation Script:** `Scripts/fix_open_pdb1.sh`

```bash
# Run as zdmuser on ZDM server (10.1.0.8)
cd ~/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts
chmod +x fix_open_pdb1.sh
./fix_open_pdb1.sh
```

**Verification:**

```bash
# Expected: PDB1 shows OPEN_MODE = READ WRITE and RESTRICTED = NO
# The script outputs a verification query after applying the fix.
# To manually verify, re-run the source discovery or check:
#   SELECT NAME, OPEN_MODE, RESTRICTED FROM V$PDBS WHERE NAME = 'PDB1';
```

**Expected Verification Output:**

```
NAME   OPEN_MODE  RESTRICTED
------ ---------- ----------
PDB1   READ WRITE NO
```

**Rollback / Undo:**

```sql
-- To close PDB1 again (if needed for rollback):
ALTER PLUGGABLE DATABASE PDB1 CLOSE IMMEDIATE;
ALTER PLUGGABLE DATABASE PDB1 DISCARD STATE;
```

**Resolution Notes:**  
_[Update with date, who resolved, and any notes]_

---

### Issue 2: Enable ALL COLUMNS Supplemental Logging

**Category:** ❌ Blocker  
**Status:** 🔲 Pending

**Problem:**  
The source database has only minimal supplemental logging enabled (`LOG_DATA_MIN = YES`). ZDM ONLINE_PHYSICAL migration requires ALL COLUMNS supplemental logging (`LOG_DATA_ALL = YES`) to correctly apply redo at the target during the Data Guard synchronisation phase. Without this, the migration EVAL will fail or redo apply will generate errors.

**Discovery State:**

| Type | Current | Required |
|------|---------|----------|
| Minimal (LOG_DATA_MIN) | YES ✅ | YES |
| All Columns | NO ⚠️ | **YES** |
| Primary Key | NO ⚠️ | YES |
| Unique | NO | Optional |
| Foreign Key | YES ✅ | YES |

**Remediation Script:** `Scripts/fix_supplemental_logging.sh`

```bash
# Run as zdmuser on ZDM server (10.1.0.8)
cd ~/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts
chmod +x fix_supplemental_logging.sh
./fix_supplemental_logging.sh
```

**Verification:**

```sql
-- Expected: LOG_DATA_ALL = YES, LOG_DATA_PK = YES
SELECT
  SUPPLEMENTAL_LOG_DATA_MIN  AS MIN_LOGGING,
  SUPPLEMENTAL_LOG_DATA_PK   AS PK_LOGGING,
  SUPPLEMENTAL_LOG_DATA_UI   AS UI_LOGGING,
  SUPPLEMENTAL_LOG_DATA_FK   AS FK_LOGGING,
  SUPPLEMENTAL_LOG_DATA_ALL  AS ALL_LOGGING
FROM V$DATABASE;
```

**Expected Verification Output:**

```
MIN_LOGGING PK_LOGGING UI_LOGGING FK_LOGGING ALL_LOGGING
----------- ---------- ---------- ---------- -----------
YES         YES        NO         YES        YES
```

**Rollback / Undo:**

```sql
-- To remove ALL COLUMNS supplemental logging (if needed for rollback):
ALTER DATABASE DROP SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
-- Note: Minimal and FK supplemental logging will remain.
-- Do NOT remove until migration is fully complete and verified.
```

**Resolution Notes:**  
_[Update with date, who resolved, and any notes]_

---

### Issue 3: Configure OCI Config for zdmuser on ZDM Server

**Category:** ❌ Blocker  
**Status:** 🔲 Pending

**Problem:**  
The OCI CLI (`oci`) is installed on the ZDM server (version 3.73.1) but the OCI configuration file (`~/.oci/config`) has **not been verified** for `zdmuser`. The `azureuser` home directory has no OCI config at all. ZDM requires OCI API access to interact with Oracle Cloud Infrastructure — specifically to verify the target database OCID, access OCI Object Storage as a backup staging area, and validate the migration environment.

**Required Configuration Values (from zdm-env.md):**

| Parameter | Value |
|-----------|-------|
| Tenancy OCID | `ocid1.tenancy.oc1..aaaaaaaarvyhjcn7wkkxxx5g3o7lgqks23bmsjtsticz3gtg5xs5qyrwkftq` |
| User OCID | `ocid1.user.oc1..aaaaaaaakfe5cirdq7vkkrhogjrgcrgftvwb7mdoehujgchefpqv54vhsnoa` |
| Region | `uk-london-1` |
| API Key Fingerprint | `7f:05:c1:f2:5c:3a:46:ec:9f:95:44:c8:77:a4:50:f9` |
| Private Key Path | `~/.oci/oci_api_key.pem` |

> **⚠️ Pre-requisite:** The OCI API private key file `/home/zdmuser/.oci/oci_api_key.pem` must already exist on the ZDM server. If it does not, upload it before running the script. The corresponding public key must be uploaded to OCI Console → Identity → Users → API Keys.

**Remediation Script:** `Scripts/fix_oci_config.sh`

```bash
# Run as zdmuser on ZDM server (10.1.0.8)
cd ~/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts
chmod +x fix_oci_config.sh
./fix_oci_config.sh
```

**Verification:**

```bash
# Test OCI CLI with the new config
oci os ns get
# Expected: Returns the OCI Object Storage namespace as a JSON string
# e.g.: { "data": "axxxxxxxxxxx" }

# Also test target DB lookup
oci db database get \
  --database-id ocid1.database.oc1.uk-london-1.anwgiljss56liuaatz45cjnpbvpgku7gkorvxg6lytoj5lxxruk2eqxzkzma
```

**Rollback / Undo:**

```bash
# To remove the OCI config (if created incorrectly):
rm -f ~/.oci/config
# Re-run fix_oci_config.sh with corrected values
```

**Resolution Notes:**  
_[Update with date, who resolved, and any notes — including the Object Storage namespace retrieved by `oci os ns get`. That value is needed for Section C of the Migration Questionnaire.]_

---

### Issue 4: Monitor Source Root Disk Space

**Category:** ⚡ Recommended  
**Status:** 🔲 Pending

**Problem:**  
The source server (`tm-oracle-iaas`) root filesystem (`/`) is at **78% utilisation** with only **6.3 GB free**. During ONLINE_PHYSICAL migration, ZDM uses RMAN to create an initial backup. Archive logs accumulate in `/u01/app/oracle/fast_recovery_area` (on the root filesystem) during the Data Guard synchronisation phase. If the filesystem fills up, the migration will fail.

**Recommended Actions:**

1. Before starting migration, check current free space:
   ```bash
   ssh -i ~/.ssh/iaas.pem azureuser@10.1.0.11 \
     "df -h / /u01/app/oracle/fast_recovery_area 2>/dev/null || df -h /"
   ```

2. Consider redirecting archive logs to the `/mnt/resource` partition (16 GB, 15 GB free):
   ```sql
   -- As sysdba on source:
   ALTER SYSTEM SET LOG_ARCHIVE_DEST_1='LOCATION=/mnt/oracle/archive' SCOPE=BOTH;
   -- Ensure /mnt/oracle/archive exists and is owned by oracle
   ```

3. Set an RMAN archive log deletion policy to prevent accumulation:
   ```
   RMAN> CONFIGURE ARCHIVELOG DELETION POLICY TO APPLIED ON ALL STANDBY;
   ```

**No dedicated remediation script is generated** for this item as the action depends on your storage allocation decisions. Monitor and take action as needed before starting the migration.

**Resolution Notes:**  
_[Update with confirmed free space at migration start time]_

---

### Issue 5: Expand ZDM Server Root Filesystem

**Category:** ⚡ Recommended  
**Status:** 🔲 Pending

**Problem:**  
The ZDM server (`tm-vm-odaa-oracle-jumpbox`) root filesystem has only **24 GB free** (total: 39 GB). ZDM documentation recommends a minimum of **50 GB** of free space for staging migration logs, temporary files, and RMAN output.

**Impact Assessment:**  
For this specific migration (2.08 GB database), the risk is relatively low — the staging data should fit within available space. However, if multiple migrations are run or ZDM logs accumulate, disk pressure may cause issues.

**Recommended Actions:**

1. Check current ZDM log and base directory sizes:
   ```bash
   du -sh /u01/app/zdmbase/chkbase/* 2>/dev/null | sort -rh | head -20
   du -sh /u01/app/zdmhome/logs/* 2>/dev/null | sort -rh | head -10
   ```

2. Clean up failed job logs (can be done safely after confirmed failures):
   ```bash
   # As zdmuser
   ls /u01/app/zdmbase/chkbase/
   # Old failed jobs can be purged via zdmcli after confirming they are not needed
   ```

3. If expansion is needed, resize the Azure VM OS disk or attach a data disk via Azure portal.

**No dedicated remediation script is generated** for this item. Escalate to the Azure infrastructure team if disk expansion is required.

**Resolution Notes:**  
_[Update with confirmed free space at migration start time]_

---

## Re-Verification Instructions

After resolving Issues 1–3, re-run the relevant portions of source discovery to confirm the fixes:

```bash
# As zdmuser on ZDM server
sudo su - zdmuser

# Re-run source discovery to verify PDB1 open state and supplemental logging
cd ~/Artifacts/Phase10-Migration/ZDM/ORADB/Step0/Scripts
./zdm_orchestrate_discovery.sh source
# Save updated outputs to:
# Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Verification/
```

Or run the consolidated verification script:

```bash
cd ~/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts
chmod +x verify_fixes.sh
./verify_fixes.sh
```

---

## Completion Checklist

Before proceeding to Step 3, confirm all items are ✅:

```
[ ] Issue 1 RESOLVED  — PDB1 is OPEN (READ WRITE) and state is SAVED
[ ] Issue 2 RESOLVED  — ALL COLUMNS supplemental logging is YES in V$DATABASE
[ ] Issue 3 RESOLVED  — OCI CLI returns namespace via `oci os ns get` as zdmuser
[ ] Issue 4 REVIEWED  — Source disk space is adequate for migration
[ ] Issue 5 REVIEWED  — ZDM server disk space is adequate for migration
[ ] verify_fixes.sh has been run and all checks passed
[ ] Verification discovery outputs saved to Step2/Verification/
[ ] Migration Questionnaire (Step1) updated with OCI Object Storage namespace (Section C)

Completed By: _______________
Date: _______________
Reviewed By: _______________
```

---

## Next Steps

Once all blockers are resolved:

1. ✅ This log is updated and all items marked resolved
2. ✅ `verify_fixes.sh` output saved to `Step2/Verification/`
3. 🔲 Run `Step3-Generate-Migration-Artifacts.prompt.md` with:
   - `Migration-Questionnaire-ORADB.md` (completed)
   - `Discovery-Summary-ORADB.md`
   - This `Issue-Resolution-Log-ORADB.md`
   - Latest discovery files from `Step2/Verification/`

---

*Generated by ZDM Migration Planning - Step 2*  
*Source: Discovery-Summary-ORADB.md | Migration-Questionnaire-ORADB.md*
