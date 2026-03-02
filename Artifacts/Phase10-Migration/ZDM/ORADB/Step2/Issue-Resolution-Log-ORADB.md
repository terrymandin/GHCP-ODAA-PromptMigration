# Issue Resolution Log: ORADB

## Generated
- **Date:** 2026-03-02
- **Based On:** `Discovery-Summary-ORADB.md` (Step 1)
- **Migration:** ORADB (Azure IaaS → ODAA) using ZDM ONLINE_PHYSICAL

---

## Summary

| # | Issue | Category | Status | Script | Date Resolved | Verified By |
|---|-------|----------|--------|--------|---------------|-------------|
| 1 | PDB1 not open (MOUNTED state) | ❌ Blocker | 🔲 Pending | `fix_pdb1_open.sh` | | |
| 2 | ALL COLUMNS supplemental logging not enabled | ❌ Blocker | 🔲 Pending | `fix_supplemental_logging.sh` | | |
| 3 | OCI config missing for zdmuser on ZDM server | ❌ Blocker | 🔲 Pending | `fix_oci_config_zdmuser.sh` | | |
| 4 | Source root disk space low (6.3 GB free, 78% used) | ⚡ Recommended | 🔲 Pending | *(manual)* | | |
| 5 | ZDM server root filesystem < 50 GB (24 GB free) | ⚡ Recommended | 🔲 Pending | *(manual)* | | |
| 6 | Confirm target db_unique_name for ZDM -sourcedb | ⚠️ Required | 🔲 Pending | *(manual)* | | |

> **Key:** ❌ Blocker = must fix before migration  •  ⚠️ Required = must fix for best results  •  ⚡ Recommended = fix when possible

---

## Issue Details

---

### Issue 1: PDB1 Not Open (MOUNTED State)

**Category:** ❌ Blocker  
**Status:** 🔲 Pending  
**Script:** `Scripts/fix_pdb1_open.sh`

**Problem:**  
PDB1 on the source CDB (ORADB1, SID: oradb) is in `MOUNTED` mode rather than `READ WRITE`. ZDM ONLINE_PHYSICAL migration requires the source PDB to be fully open in READ WRITE state before migration can begin. If PDB1 remains MOUNTED, ZDM prechecks (EVAL) will fail at the source database validation phase.

**Discovery Evidence:**
```
PDB Name: PDB1 | PDB Status: MOUNTED ⚠️ (must be OPEN before migration)
```

**Remediation:**  
Run `Scripts/fix_pdb1_open.sh` from the ZDM server as `zdmuser`:
```bash
cd /home/zdmuser
chmod +x fix_pdb1_open.sh
./fix_pdb1_open.sh
```

**Manual SQL (if running directly on source):**
```sql
-- Connect as SYS on source (oradb)
ALTER PLUGGABLE DATABASE PDB1 OPEN;
ALTER PLUGGABLE DATABASE PDB1 SAVE STATE;

-- Verify
SELECT name, open_mode FROM v$pdbs WHERE name = 'PDB1';
-- Expected: PDB1 | READ WRITE
```

**Verification:**
```bash
# Run verify_fixes.sh and check Issue 1 output
./verify_fixes.sh
# Expected: PDB1 open_mode = READ WRITE
```

**Rollback:**
```sql
-- Close PDB1 back to MOUNTED if needed
ALTER PLUGGABLE DATABASE PDB1 CLOSE IMMEDIATE;
```

**Resolution Notes:**  
*(To be completed after fix is applied — record date, who ran the script, actual output)*

---

### Issue 2: ALL COLUMNS Supplemental Logging Not Enabled

**Category:** ❌ Blocker  
**Status:** 🔲 Pending  
**Script:** `Scripts/fix_supplemental_logging.sh`

**Problem:**  
ZDM ONLINE_PHYSICAL migration uses Oracle Data Guard redo apply to synchronise source changes to the target during the active replication phase. For the redo stream to carry all column values needed for row-level resynchronisation, `SUPPLEMENTAL LOG DATA (ALL) COLUMNS` must be enabled at the database level. Currently only minimal supplemental logging (`LOG_DATA_MIN = YES`) is active. Specifically:

| Type | Current | Required |
|------|---------|----------|
| Minimal | YES ✅ | YES |
| All Columns | NO ❌ | YES |
| Primary Key | NO ❌ | YES |
| Unique | NO | YES |

ZDM EVAL prechecks (jobs 22–34) have been failing partly due to this gap.

**Discovery Evidence:**
```
SUPPLEMENTAL_LOG_DATA_MIN: YES
SUPPLEMENTAL_LOG_DATA_ALL: NO  ⚠️
```

**Remediation:**  
Run `Scripts/fix_supplemental_logging.sh` from the ZDM server as `zdmuser`:
```bash
cd /home/zdmuser
chmod +x fix_supplemental_logging.sh
./fix_supplemental_logging.sh
```

**Manual SQL (if running directly on source):**
```sql
-- Connect as SYS on source (oradb)
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER SYSTEM SWITCH LOGFILE;

-- Verify
SELECT supplemental_log_data_min  AS log_min,
       supplemental_log_data_pk   AS log_pk,
       supplemental_log_data_ui   AS log_ui,
       supplemental_log_data_fk   AS log_fk,
       supplemental_log_data_all  AS log_all
FROM v$database;
-- Expected: log_all = YES
```

**Verification:**
```bash
# Run verify_fixes.sh and check Issue 2 output
./verify_fixes.sh
# Expected: supplemental_log_data_all = YES
```

**Rollback:**
```sql
-- Remove ALL supplemental logging (restore to minimal only)
ALTER DATABASE DROP SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER SYSTEM SWITCH LOGFILE;
```

**Performance Note:**  
ALL COLUMNS supplemental logging increases redo volume by including all column values for every DML change. For a small database (2.08 GB total) this overhead is negligible. Monitor archive log generation rate during the pre-migration period and ensure `LOCATION=/u01/app/oracle/fast_recovery_area` has sufficient headroom (see Issue 4 re: disk space).

**Resolution Notes:**  
*(To be completed after fix is applied — record date, who ran the script, actual output)*

---

### Issue 3: OCI Config Missing for zdmuser on ZDM Server

**Category:** ❌ Blocker  
**Status:** 🔲 Pending  
**Script:** `Scripts/fix_oci_config_zdmuser.sh`

**Problem:**  
ZDM requires OCI CLI access to interact with OCI Object Storage (backup staging bucket) and to validate the target database OCID during migration. The `~/.oci/config` file for `zdmuser` on the ZDM server (`tm-vm-odaa-oracle-jumpbox`) was not found. The OCI CLI (`oci`) is already installed (v3.73.1 confirmed), but it needs a valid config file and API private key.

**Discovery Evidence:**
```
OCI CLI:            3.73.1 installed ✅
OCI config (zdmuser): Not verified ⚠️
OCI config (azureuser): Not found at ~/.oci/config ⚠️
```

**Prerequisites Before Running the Script:**
1. **OCI API Key must be available** — The private key (`oci_api_key.pem`) generated against the OCI user OCID and fingerprint in `zdm-env.md` must be uploaded to the ZDM server.
2. **Upload the key:**
   ```bash
   # From your local workstation:
   scp -i ~/.ssh/zdm.pem /path/to/oci_api_key.pem azureuser@10.1.0.8:/tmp/oci_api_key.pem

   # On ZDM server as azureuser:
   sudo mkdir -p /home/zdmuser/.oci
   sudo mv /tmp/oci_api_key.pem /home/zdmuser/.oci/oci_api_key.pem
   sudo chown zdmuser:zdmuser /home/zdmuser/.oci/oci_api_key.pem
   sudo chmod 600 /home/zdmuser/.oci/oci_api_key.pem
   ```

**Remediation:**  
Run `Scripts/fix_oci_config_zdmuser.sh` on the ZDM server as `zdmuser`:
```bash
# SSH to ZDM server
ssh -i ~/.ssh/zdm.pem azureuser@10.1.0.8

# Switch to zdmuser
sudo su - zdmuser

# Copy script and run
chmod +x fix_oci_config_zdmuser.sh
./fix_oci_config_zdmuser.sh
```

**OCI config values used (from zdm-env.md):**

| Field | Value |
|-------|-------|
| User OCID | `ocid1.user.oc1..aaaaaaaakfe5cirdq7vkkrhogjrgcrgftvwb7mdoehujgchefpqv54vhsnoa` |
| Tenancy OCID | `ocid1.tenancy.oc1..aaaaaaaarvyhjcn7wkkxxx5g3o7lgqks23bmsjtsticz3gtg5xs5qyrwkftq` |
| Region | `uk-london-1` |
| Fingerprint | `7f:05:c1:f2:5c:3a:46:ec:9f:95:44:c8:77:a4:50:f9` |
| Private Key Path | `~/.oci/oci_api_key.pem` |

**Verification:**
```bash
# As zdmuser on ZDM server:
oci os ns get
# Expected: {"data": "<your-namespace-string>"}

# Also test tenancy access
oci iam compartment list --compartment-id ocid1.tenancy.oc1..aaaaaaaarvyhjcn7wkkxxx5g3o7lgqks23bmsjtsticz3gtg5xs5qyrwkftq --all --query 'data[].name'
```

**Rollback:**
```bash
# Remove the config (restores to pre-fix state)
rm -f /home/zdmuser/.oci/config
```

**Post-Fix Action — Record the OCI Namespace:**  
Once `oci os ns get` succeeds, record the namespace value and update `zdm-env.md`:
```
OCI_OSS_NAMESPACE: <value from oci os ns get>
```

**Resolution Notes:**  
*(To be completed after fix is applied — record date, who ran the script, OCI namespace retrieved)*

---

### Issue 4: Source Root Disk Space Low

**Category:** ⚡ Recommended  
**Status:** 🔲 Pending  
**Script:** *(manual steps — no script generated)*

**Problem:**  
Source server root filesystem (`/`) is 78% used with only 6.3 GB free. During ONLINE_PHYSICAL migration, ZDM will trigger RMAN backups and the archive log destination (`/u01/app/oracle/fast_recovery_area`) is on the same filesystem. With ALL COLUMNS supplemental logging now enabled (Issue 2), redo / archive log generation will increase. Running out of archive log space during migration would cause the migration to stall or fail.

**Assessment:**
```
Root Disk Free:        6.3 GB (78% used) ⚠️
Archive Log Dest:      /u01/app/oracle/fast_recovery_area  (on same root FS)
/mnt partition:        16 GB free (available as overflow)
```

**Recommended Actions:**

1. **Redirect archive logs to /mnt** (preferred — more free space):
   ```sql
   -- Connect as SYS on source
   ALTER SYSTEM SET log_archive_dest_1 = 'LOCATION=/mnt/oracle/fast_recovery_area' SCOPE=BOTH;
   ALTER SYSTEM SWITCH LOGFILE;

   -- Verify
   ARCHIVE LOG LIST;
   ```

2. **Monitor archive log generation** before migration:
   ```bash
   # Watch disk usage
   df -h /u01 /mnt
   # Monitor archive log count growth
   ls -lht /u01/app/oracle/fast_recovery_area/ | head -20
   ```

3. **Clean up existing archive logs** that are already backed up:
   ```bash
   # As oracle via sudo on source
   rman target /
   # RMAN> CROSSCHECK ARCHIVELOG ALL;
   # RMAN> DELETE EXPIRED ARCHIVELOG ALL;
   # RMAN> DELETE ARCHIVELOG ALL COMPLETED BEFORE 'SYSDATE-1';
   ```

**Rollback:**
```sql
-- Restore original archive dest
ALTER SYSTEM SET log_archive_dest_1 = 'LOCATION=/u01/app/oracle/fast_recovery_area' SCOPE=BOTH;
```

**Resolution Notes:**  
*(To be completed — document chosen approach and space freed)*

---

### Issue 5: ZDM Server Root Filesystem < 50 GB

**Category:** ⚡ Recommended  
**Status:** 🔲 Pending  
**Script:** *(manual steps — infrastructure change)*

**Problem:**  
ZDM documentation recommends a minimum of 50 GB free on the root filesystem for staging migration artefacts, ZDM job logs, and temporary files. The ZDM server has:
- `/` (rootvg-rootlv): 39 GB total, 24 GB free — below the 50 GB recommendation
- `/mnt` (temp): 16 GB free — usable but ephemeral

For a 2.08 GB database, the actual migration staging footprint will be small and 24 GB is likely sufficient. However, ensure ZDM logs and wallet directories are not filling the disk between now and migration.

**Recommended Actions:**

1. **Check current ZDM disk usage:**
   ```bash
   # SSH to ZDM server as zdmuser or azureuser
   df -h /
   du -sh /u01/app/zdmbase/rhp/zdm/log/*
   du -sh /u01/app/zdmhome/*
   ```

2. **Archive / remove old ZDM job logs** (jobs that have already failed/completed):
   ```bash
   # List old job logs
   ls -lht /u01/app/zdmbase/rhp/zdm/log/
   # Compress or remove logs for completed/aborted jobs (18–34)
   ```

3. **Resize the VM / disk in Azure** if more headroom is genuinely needed:
   - Azure Portal → VM → Disks → Resize OS disk
   - Then: `sudo growpart /dev/sda 1 && sudo xfs_growfs /`

**Resolution Notes:**  
*(To be completed — document disk size after any extension)*

---

### Issue 6: Confirm Target DB Unique Name for ZDM

**Category:** ⚠️ Required  
**Status:** 🔲 Pending  
**Script:** *(manual verification)*

**Problem:**  
The ZDM `-srcdbname` and `-targetsysdbaconnstr` / target DB registration require the exact `db_unique_name` as registered in the Oracle Clusterware. Discovery found the target instance as `oradb011` and the CDB listener service as `oradb01m`. The exact `db_unique_name` used in the ZDM response file must match what SRVCTL / LSNRCTL report.

**Verification Steps (run on ZDM server):**
```bash
# SSH to target node 1 as opc
ssh -i /home/zdmuser/odaa.pem opc@10.0.1.160

# Check db_unique_name via SRVCTL
sudo -u oracle /u02/app/oracle/product/19.0.0.0/dbhome_1/bin/srvctl config database -v

# Check LSNRCTL services
sudo -u oracle /u01/app/19.0.0.0/grid/bin/lsnrctl status

# Or query if the DB is open
sudo -u oracle bash -c '
  export ORACLE_HOME=/u02/app/oracle/product/19.0.0.0/dbhome_1
  export ORACLE_SID=oradb011
  export PATH=${ORACLE_HOME}/bin:${PATH}
  sqlplus -S / as sysdba <<SQL
    SELECT db_unique_name FROM v\$database;
    EXIT;
SQL
'
```

**Expected:** The `db_unique_name` is likely `oradb01m` (the CDB name derived from the listener service). Confirm this value and update the ZDM response file (`/home/zdmuser/iaas_to_odaa.rsp`) if needed.

**Resolution Notes:**  
*(To be completed — record confirmed db_unique_name value)*

---

## Verification After All Fixes

Once all blockers are resolved, re-run source discovery and a ZDM EVAL job to confirm:

```bash
# 1. Re-run source discovery
cd /home/zdmuser
./zdm_orchestrate_discovery.sh source

# 2. Save updated discovery output to Step2/Verification/
# Copy output files to: Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Verification/

# 3. Run ZDM EVAL job (after Step 3 artifacts are generated)
# zdmcli migrate database -sourcedb <src> -sourcenode <src_host> ... -eval
```

Save re-run discovery outputs to: `Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Verification/`

---

## Completion Checklist

Before proceeding to Step 3:

```
[ ] Issue 1 — PDB1 is READ WRITE (verified via fix_pdb1_open.sh output or verify_fixes.sh)
[ ] Issue 2 — supplemental_log_data_all = YES (verified via fix_supplemental_logging.sh or verify_fixes.sh)
[ ] Issue 3 — oci os ns get succeeds as zdmuser; OCI_OSS_NAMESPACE recorded in zdm-env.md
[ ] Issue 4 — Archive log dest has adequate free space for migration duration
[ ] Issue 5 — ZDM server disk reviewed; acceptable headroom confirmed
[ ] Issue 6 — Target db_unique_name confirmed and recorded
[ ] Issue Resolution Log updated with resolution notes for each completed item
[ ] Re-run source discovery completed and saved to Step2/Verification/
[ ] No new blockers identified in verification discovery output
```

---

*Generated by ZDM Migration Planning — Step 2 | 2026-03-02*
