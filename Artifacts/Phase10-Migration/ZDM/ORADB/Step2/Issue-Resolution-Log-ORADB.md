# Issue Resolution Log: ORADB

## Generated
- **Date:** 2026-03-03
- **Based On:** Discovery-Summary-ORADB.md (Step 1 output)
- **Migration Method:** ONLINE_PHYSICAL (recommended)

---

## Summary

| # | Issue | Category | Priority | Status | Date Resolved | Verified By |
|---|-------|----------|----------|--------|---------------|-------------|
| 1 | OCI Object Storage namespace + bucket not configured | ⚠️ Required | HIGH | 🔲 Pending | | |
| 2 | OCI CLI config for `zdmuser` on ZDM server not verified | ⚠️ Required | HIGH | 🔲 Pending | | |
| 3 | Target `DB_UNIQUE_NAME` not confirmed | ⚠️ Required | HIGH | 🔲 Pending | | |
| 4 | Source `/` filesystem at 80% — archivelog risk | ⚡ Recommended | MEDIUM | 🔲 Pending | | |
| 5 | PDB name mapping for `PDB1` on target not decided | ⚡ Recommended | MEDIUM | 🔲 Pending | | |
| 6 | `SYS.SYS_HUB` DB link target reachability from OCI | ⚡ Recommended | LOW | 🔲 Pending | | |

> **Status Key:** 🔲 Pending · 🔄 In Progress · ✅ Resolved · N/A Not Applicable

---

## Issue Details

---

### Issue 1: OCI Object Storage Namespace and Bucket Not Configured

**Category:** ⚠️ Required Action  
**Priority:** HIGH  
**Status:** 🔲 Pending  
**Affects:** ONLINE_PHYSICAL migration only (ZDM uses Object Storage for initial RMAN transfer)

**Problem:**  
The `OCI_OSS_NAMESPACE` and `OCI_OSS_BUCKET_NAME` fields in `zdm-env.md` are empty (`<NEEDS_TO_BE_SET>`). ZDM physical online migration requires an OCI Object Storage bucket to stage the initial RMAN backup before applying it to the ODAA target.

**Discovery Evidence:**
```
OCI_OSS_NAMESPACE=<NEEDS_TO_BE_SET>
OCI_OSS_BUCKET_NAME=<NEEDS_TO_BE_SET>
```

**Remediation Script:** `Scripts/create_oci_bucket.sh`

```bash
# Run as zdmuser on ZDM server (10.1.0.8)
sudo su - zdmuser
cd ~/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts
chmod +x create_oci_bucket.sh
./create_oci_bucket.sh
```

The script will:
1. Retrieve the Object Storage namespace via `oci os ns get`
2. Create bucket `zdm-migration-oradb-YYYYMMDD` in region `uk-london-1`
3. Print the namespace and bucket name values to add to `zdm-env.md`

**Manual Step After Script:**  
Update `prompts/Phase10-Migration/ZDM/zdm-env.md`:
```
OCI_OSS_NAMESPACE: <value printed by script>
OCI_OSS_BUCKET_NAME: zdm-migration-oradb-20260303
```

**Verification:**
```bash
# Confirm bucket exists (run as zdmuser)
oci os bucket get --name zdm-migration-oradb-20260303 --namespace <namespace>
```

**Rollback:**
```bash
# Delete bucket if created in error (must be empty)
oci os bucket delete --name zdm-migration-oradb-20260303 --namespace <namespace> --force
```

**Resolution Notes:**  
_[Fill in: date resolved, namespace value, bucket name, verified by]_

---

### Issue 2: OCI CLI Configuration for `zdmuser` on ZDM Server Not Verified

**Category:** ⚠️ Required Action  
**Priority:** HIGH  
**Status:** 🔲 Pending

**Problem:**  
The Step 0 server discovery ran as `azureuser`, so the OCI CLI config check reported "Not found at `/home/azureuser/.oci/config`". ZDM itself runs as `zdmuser`, so the OCI config must be present and working under `~zdmuser/.oci/config` (`/home/zdmuser/.oci/config`).

**Discovery Evidence:**
```
OCI CLI Config Status: ⚠️ Not found at /home/azureuser/.oci/config (script ran as azureuser)
```

**Remediation Script:** `Scripts/verify_oci_cli_zdmuser.sh`

```bash
# Run as zdmuser on ZDM server (10.1.0.8)
sudo su - zdmuser
cd ~/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts
chmod +x verify_oci_cli_zdmuser.sh
./verify_oci_cli_zdmuser.sh
```

**If OCI CLI config is missing, set it up:**
```bash
# As zdmuser on ZDM server:
sudo su - zdmuser

# Option A: Copy config from azureuser (if already configured there)
sudo cp -r /home/azureuser/.oci /home/zdmuser/.oci
sudo chown -R zdmuser:zdmuser /home/zdmuser/.oci
chmod 700 /home/zdmuser/.oci
chmod 600 /home/zdmuser/.oci/config /home/zdmuser/.oci/oci_api_key.pem

# Option B: Run OCI setup interactively
oci setup config
# Enter:
#   User OCID:        ocid1.user.oc1..aaaaaaaakfe5cirdq7vkkrhogjrgcrgftvwb7mdoehujgchefpqv54vhsnoa
#   Tenancy OCID:     ocid1.tenancy.oc1..aaaaaaaarvyhjcn7wkkxxx5g3o7lgqks23bmsjtsticz3gtg5xs5qyrwkftq
#   Region:           uk-london-1
#   Fingerprint:      7f:05:c1:f2:5c:3a:46:ec:9f:95:44:c8:77:a4:50:f9
#   Private key path: /home/zdmuser/.oci/oci_api_key.pem
```

**Verification:**
```bash
# As zdmuser — should return region list without errors
sudo -u zdmuser oci iam region list --config-file /home/zdmuser/.oci/config
```

**Rollback:**  
N/A — this is a configuration verification step only.

**Resolution Notes:**  
_[Fill in: date verified, method used (copy vs. setup), tested with region list]_

---

### Issue 3: Target `DB_UNIQUE_NAME` Not Yet Confirmed

**Category:** ⚠️ Required Action  
**Priority:** HIGH  
**Status:** 🔲 Pending

**Problem:**  
The target ODAA system already hosts an existing database (`oradb01m`, instance `oradb011`). The migrated ORADB must be assigned a `DB_UNIQUE_NAME` that does not conflict. This is a planning decision that must be made before generating ZDM response files in Step 3.

**Discovery Evidence:**
```
Existing databases on target ODAA (tmodaauks-rqahk1):
  - oradb01m (instance oradb011) — active, shown in listener
Source DB_UNIQUE_NAME: oradb1
```

**Options:**

| Candidate `DB_UNIQUE_NAME` | Notes |
|---------------------------|-------|
| `oradb1` | Same as source — simplest, acceptable if no conflict found |
| `oradb1t` | `t` suffix = "target" — distinguishes from source during DG replication |
| `oradb1_lon` | Site-suffix naming convention |
| `oradb1_oci` | Indicates OCI landing |

**Required Action (manual):**  
1. Confirm no existing database on ODAA uses `DB_UNIQUE_NAME = oradb1`  
2. Check the existing `oradb01m` DB_UNIQUE_NAME on the target:
```bash
# SSH to target as opc and check srvctl:
ssh -i ~/.ssh/odaa.pem opc@10.0.1.160 "sudo su - oracle -c 'srvctl config database'"
```
3. Record your chosen `DB_UNIQUE_NAME` and PDB name in the questionnaire (Step 1: Migration-Questionnaire-ORADB.md) before running Step 3.

**Verification:**
```bash
# After confirming, verify the chosen name is not already registered:
ssh -i ~/.ssh/odaa.pem opc@10.0.1.160 \
  "sudo su - oracle -c 'srvctl config database | grep -i oradb'"
```

**Resolution Notes:**  
_[Fill in: chosen DB_UNIQUE_NAME, PDB name, confirmed no conflict, date, verified by]_

---

### Issue 4: Source Root Filesystem at 80% — Archivelog Accumulation Risk

**Category:** ⚡ Recommended  
**Priority:** MEDIUM  
**Status:** 🔲 Pending

**Problem:**  
The source server (`tm-oracle-iaas`, 10.1.0.11) root filesystem is at 80% capacity (23 GB used of 30 GB). During ONLINE_PHYSICAL migration, ZDM keeps the source generating archivelogs continuously until switchover. If the FRA fills up on `/`, the source database halts.

**Discovery Evidence:**
```
/ (root): 30 GB total, 23 GB used, 5.8 GB free (80%)
Archive Log Location: /u01/app/oracle/fast_recovery_area  (on root filesystem)
```

**Options:**
1. **Purge obsolete archivelogs** (recommended) using the provided RMAN script — frees space without impacting running migration prerequisites.
2. **Increase disk size** — expand the Azure VM disk (requires brief OS resize operation).
3. **Monitor only** — acceptable if migration will complete within the available 5.8 GB headroom.

**Remediation Script:** `Scripts/purge_source_archivelogs.sh`

```bash
# Run as zdmuser on ZDM server (10.1.0.8)
sudo su - zdmuser
cd ~/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts
chmod +x purge_source_archivelogs.sh
./purge_source_archivelogs.sh
```

**Verification:**
```bash
# Check source disk space after purge
ssh -i ~/.ssh/odaa.pem azureuser@10.1.0.11 "df -h /"
```

Expected: free space increases from ~5.8 GB.

**Rollback:**  
RMAN archivelog deletion is irreversible for deleted logs. Ensure FRA retention policy is respected — the script only deletes logs already backed up or beyond the retention window (`DELETE ARCHIVELOG ALL COMPLETED BEFORE 'SYSDATE-1'`).

**Resolution Notes:**  
_[Fill in: space freed, current usage percentage, date, verified by]_

---

### Issue 5: PDB Name Mapping for `PDB1` on Target Not Decided

**Category:** ⚡ Recommended  
**Priority:** MEDIUM  
**Status:** 🔲 Pending

**Problem:**  
The source CDB has one PDB: `PDB1`. The migration questionnaire requires a target PDB name to be confirmed. ZDM allows PDB renaming at migration time with the `ZDM_PDBNAME` response file parameter.

**Discovery Evidence:**
```
Source CDB = YES
Source PDBs = PDB$SEED (READ ONLY), PDB1 (READ WRITE)
Existing target databases: oradb01m (may already have a PDB1)
```

**Required Action (manual):**  
1. Check what PDBs exist on the target within `oradb01m`:
```bash
ssh -i ~/.ssh/odaa.pem opc@10.0.1.160 \
  "sudo -u oracle bash -c 'export ORACLE_HOME=/u02/app/oracle/product/19.0.0.0/dbhome_1; \
   export ORACLE_SID=oradb011; \
   export PATH=\$ORACLE_HOME/bin:\$PATH; \
   echo \"select pdb_name, open_mode from cdb_pdbs where con_id > 2;\" | sqlplus -S / as sysdba'"
```
2. If `PDB1` already exists in `oradb01m`, choose a different name (e.g., `ORADB_PDB1`, `PDB_ORADB`, etc.)  
3. If no conflict, keep the name as `PDB1`.
4. Record final decision in the questionnaire (Section A.3).

**Resolution Notes:**  
_[Fill in: chosen PDB name, conflict check result, date, verified by]_

---

### Issue 6: `SYS.SYS_HUB` Database Link Reachability from OCI

**Category:** ⚡ Recommended  
**Priority:** LOW  
**Status:** 🔲 Pending

**Problem:**  
The source database has a `SYS_HUB` database link owned by `SYS`, pointing to user `SEEDDATA`. After migration, the CDB will run in OCI (ODAA, UK-London). If this link's target endpoint is only reachable from the Azure VNet (`10.1.0.x`) and not from OCI, the link will fail post-migration.

**Discovery Evidence:**
```
DB Link: SYS.SYS_HUB → SEEDDATA
```

**Required Action (decision):**  
1. Determine if the `SYS_HUB` link is actively used by any application.  
2. Check the link target host from the source:
```bash
# Check link target details (run as zdmuser on ZDM server):
ssh -i ~/.ssh/odaa.pem azureuser@10.1.0.11 \
  "sudo -u oracle bash -c 'export ORACLE_HOME=/u01/app/oracle/product/12.2.0/dbhome_1; \
   export ORACLE_SID=oradb; \
   export PATH=\$ORACLE_HOME/bin:\$PATH; \
   echo \"SELECT owner, db_link, username, host FROM dba_db_links WHERE db_link='"'"'SYS_HUB'"'"';\" | sqlplus -S / as sysdba'"
```
3. If the link is not needed, drop it before or after migration.  
4. If needed and the target is an Azure-internal host, plan network routing from OCI → Azure (e.g., verify ExpressRoute allows return path).

**Resolution Notes:**  
_[Fill in: link target host, decision: keep/drop/update, date, verified by]_

---

## Completion Checklist

Before proceeding to Step 3, confirm all required actions are resolved:

| # | Item | Status |
|---|------|--------|
| 1 | `OCI_OSS_NAMESPACE` and `OCI_OSS_BUCKET_NAME` set in `zdm-env.md` | [ ] Done |
| 2 | `oci iam region list` works as `zdmuser` on ZDM server | [ ] Done |
| 3 | Target `DB_UNIQUE_NAME` confirmed and recorded in questionnaire | [ ] Done |
| 4 | Source disk space at <80% or archivelog purge scheduled | [ ] Done / [ ] N/A |
| 5 | Target PDB name confirmed (keep `PDB1` or rename) | [ ] Done |
| 6 | `SYS_HUB` link reviewed (keep/drop decision made) | [ ] Done / [ ] N/A |
| 7 | `verify_fixes.sh` run — all critical checks PASS | [ ] Done |
| 8 | `Verification-Results-ORADB.md` committed to repo | [ ] Done |

---

## Next Steps

1. ✅ Run `Scripts/create_oci_bucket.sh` → update `zdm-env.md` (Issue 1)
2. ✅ Run `Scripts/verify_oci_cli_zdmuser.sh` → set up OCI CLI for zdmuser if needed (Issue 2)
3. ✅ Confirm `DB_UNIQUE_NAME` and PDB mapping — update `Migration-Questionnaire-ORADB.md` (Issues 3 & 5)
4. ✅ Run `Scripts/purge_source_archivelogs.sh` → reclaim disk on source (Issue 4)
5. ✅ Run `Scripts/verify_fixes.sh` → confirm all checks pass, commit `Verification-Results-ORADB.md`
6. 🔲 Once all items resolved, proceed to `Step3-Generate-Migration-Artifacts.prompt.md`

---

*Generated by ZDM Migration Planning - Step 2 | ORADB | 2026-03-03*
