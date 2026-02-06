# Issue Resolution Log: PRODDB Migration

## Summary

| # | Issue | Category | Status | Date Resolved | Verified By |
|---|-------|----------|--------|---------------|-------------|
| 1 | OCI Configuration Missing for zdmuser | 🔴 Critical | 🔲 Pending | | |
| 2 | Verify Target Database Name Conflict | 🔴 Critical | 🔲 Pending | | |
| 3 | Disk Space Below 50GB Threshold | 🟡 Recommended | 🔲 Pending | | |
| 4 | Database Link SYS_HUB Review | 🟡 Recommended | 🔲 Pending | | |
| 5 | tnsnames.ora Not Found | 🟡 Recommended | 🔲 Pending | | |

**Legend:**
- 🔴 Critical (Must Fix)
- 🟡 Recommended (Should Fix)
- 🔲 Pending
- 🔄 In Progress
- ✅ Resolved
- ⏭️ Deferred

---

## Issue Details

---

### Issue 1: OCI Configuration Missing for zdmuser

**Category:** 🔴 Critical  
**Status:** 🔲 Pending  
**Server:** ZDM Server (tm-vm-odaa-oracle-jumpbox)

#### Problem

The OCI CLI is installed (version 3.73.1) but the configuration for `zdmuser` or `azureuser` is incomplete:
- OCI config file not found at `/home/azureuser/.oci/config`
- API key file not found at `/home/azureuser/.oci/oci_api_key.pem`

Discovery found that `zdmuser` has some OCI key files:
- `/home/zdmuser/.oci/odaa.pem`

However, a complete OCI configuration is required for ZDM to communicate with OCI services.

#### Remediation

**Option A: Configure OCI for zdmuser (Recommended)**

```bash
# SSH to ZDM server as azureuser
ssh azureuser@tm-vm-odaa-oracle-jumpbox

# Switch to zdmuser
sudo su - zdmuser

# Check if config exists
cat ~/.oci/config

# If config doesn't exist, create it:
mkdir -p ~/.oci
chmod 700 ~/.oci

# Create OCI config file
cat > ~/.oci/config << 'EOF'
[DEFAULT]
user=<YOUR_OCI_USER_OCID>
fingerprint=<YOUR_API_KEY_FINGERPRINT>
tenancy=<YOUR_OCI_TENANCY_OCID>
region=<YOUR_OCI_REGION>
key_file=/home/zdmuser/.oci/odaa.pem
EOF

# Set proper permissions
chmod 600 ~/.oci/config

# Verify the API key file exists and has correct permissions
ls -la ~/.oci/odaa.pem
chmod 600 ~/.oci/odaa.pem
```

**Option B: Use existing keys with proper config**

If `/home/zdmuser/.oci/odaa.pem` is the correct API key:

```bash
# As zdmuser, verify the key matches what's registered in OCI Console
openssl rsa -in ~/.oci/odaa.pem -pubout -outform DER 2>/dev/null | openssl md5 -c | awk '{print $2}'

# This fingerprint should match the one in OCI Console > User Settings > API Keys
```

#### Remediation Script

Run the script `fix_oci_config.sh` from the Scripts folder:

```bash
# On ZDM server
cd /path/to/Step2/Scripts
chmod +x fix_oci_config.sh
./fix_oci_config.sh
```

#### Verification

```bash
# As zdmuser, verify OCI connectivity
sudo su - zdmuser
oci os ns get

# Expected output: Shows your Object Storage namespace
# Example: {"data": "your_namespace"}

# Verify OCI config is complete
oci setup repair-file-permissions --file ~/.oci/config
oci iam region list --output table | head -5
```

#### Resolution Notes

| Field | Value |
|-------|-------|
| Date Resolved | |
| Resolved By | |
| Verification Result | |
| Notes | |

---

### Issue 2: Verify Target Database Name Conflict

**Category:** 🔴 Critical  
**Status:** 🔲 Pending  
**Server:** Target (tmodaauks-rqahk1)

#### Problem

Discovery found an existing database `ora.oradb01m.db` on the target cluster that may be from a previous migration attempt. This could cause naming conflicts if using the same `db_unique_name`.

Existing databases on target:
- `ora.oradb01m.db` (OFFLINE) - **Potential conflict**
- `ora.migdb.db` (OFFLINE)
- `ora.mydb.db` (OFFLINE)
- `ora.testdb_stbytm.db` (INTERMEDIATE)

#### Remediation

**Step 1: Verify the status of existing oradb01m database**

```bash
# SSH to target as opc
ssh opc@tmodaauks-rqahk1

# Check database status with srvctl
sudo su - oracle
srvctl status database -d oradb01m

# Check if database has any resources
srvctl config database -d oradb01m

# Check CRS status
crsctl status resource ora.oradb01m.db -t
```

**Step 2: Decision tree**

| Scenario | Action |
|----------|--------|
| `oradb01m` is a failed previous migration, not needed | Remove database and reuse name |
| `oradb01m` is valid and must be kept | Use different db_unique_name like `oradb01_oda` |
| Unsure | Contact DBA team for guidance |

**Option A: Remove existing database (if confirmed not needed)**

```bash
# As oracle user on target
# First, ensure database is completely stopped
srvctl stop database -d oradb01m -f

# Remove from CRS
srvctl remove database -d oradb01m -f

# Optionally, clean up datafiles from ASM
# WARNING: This permanently deletes data!
# asmcmd rm -rf +DATAC3/ORADB01M
```

**Option B: Use different db_unique_name**

Update the Migration Questionnaire with:
- Target DB Unique Name: `oradb01_oda` (instead of `oradb01m`)

#### Verification

```bash
# Verify no conflicting database exists
srvctl config database -d <chosen_db_unique_name>
# Expected: "Database <name> does not exist"

# Verify ASM has no conflicting directories
asmcmd ls +DATAC3/ | grep -i oradb01
```

#### Resolution Notes

| Field | Value |
|-------|-------|
| Decision Made | [ ] Remove oradb01m  [ ] Use oradb01_oda  [ ] Other: _______ |
| Date Resolved | |
| Resolved By | |
| Verification Result | |
| Notes | |

---

### Issue 3: Disk Space Below 50GB Threshold

**Category:** 🟡 Recommended  
**Status:** 🔲 Pending  
**Server:** ZDM Server (tm-vm-odaa-oracle-jumpbox)

#### Problem

The ZDM server has only 24GB available on the `/u01` partition, which is below the recommended 50GB minimum.

```
Filesystem                  Size  Used Avail Use%
/dev/mapper/rootvg-rootlv    39G   15G   24G  39%
```

#### Impact Assessment

| Database Size | 24GB Available | Recommendation |
|---------------|----------------|----------------|
| ORADB01 (2.6GB) | ✅ Sufficient | Proceed with monitoring |
| Larger databases | ❌ Insufficient | Must expand storage |

For this 2.6GB database, 24GB should be sufficient but close monitoring is recommended.

#### Remediation Options

**Option A: Proceed with current space (for small databases)**

```bash
# Monitor disk space during migration
watch -n 30 "df -h /u01"

# Clean up any unnecessary files
sudo find /u01 -type f -name "*.log" -mtime +30 -delete
sudo find /tmp -type f -mtime +7 -delete
```

**Option B: Expand disk space (recommended for production)**

```bash
# On Azure - expand the managed disk via Azure Portal first

# Then extend LVM on the server
sudo lvextend -l +100%FREE /dev/mapper/rootvg-rootlv
sudo xfs_growfs /

# Verify
df -h /u01
```

**Option C: Use alternate storage location**

```bash
# Create migration workspace on /mnt (16GB available)
sudo mkdir -p /mnt/zdm_workspace
sudo chown zdmuser:zdm /mnt/zdm_workspace
```

#### Verification

```bash
df -h /u01
# Expected: At least 24GB available (or more if expanded)
```

#### Resolution Notes

| Field | Value |
|-------|-------|
| Option Selected | [ ] Proceed as-is  [ ] Expand disk  [ ] Use alternate storage |
| Date Resolved | |
| Resolved By | |
| Notes | |

---

### Issue 4: Database Link SYS_HUB Review

**Category:** 🟡 Recommended  
**Status:** 🔲 Pending  
**Server:** Source (temandin-oravm-vm01)

#### Problem

A database link `SYS_HUB` exists on the source database pointing to `SEEDDATA`. After migration, this link may need to be:
1. Removed if no longer needed
2. Updated with new connection details
3. Recreated pointing to the correct post-migration target

#### Current Configuration

| Property | Value |
|----------|-------|
| Owner | SYS |
| DB Link Name | SYS_HUB |
| Connect To | SEEDDATA |
| Created | 17-APR-19 |

#### Remediation

**Step 1: Investigate the database link purpose**

```sql
-- Connect to source database as SYSDBA
sqlplus / as sysdba

-- Check database link details
SELECT owner, db_link, username, host, created
FROM dba_db_links
WHERE db_link = 'SYS_HUB';

-- Test if the link is working
SELECT * FROM dual@SYS_HUB;

-- Check if any objects depend on this link
SELECT owner, name, type, referenced_link_name
FROM dba_dependencies
WHERE referenced_link_name = 'SYS_HUB';
```

**Step 2: Decision tree**

| Usage | Action |
|-------|--------|
| Link is not used by any objects | Consider dropping post-migration |
| Link is used but target is same | Keep as-is |
| Link is used but target changes | Update post-migration |

**Step 3: Document for post-migration**

Add to post-migration checklist:
- [ ] Verify SYS_HUB database link connectivity
- [ ] Update connection string if target changed
- [ ] Test dependent objects

#### Verification

```sql
-- After migration, verify link status
SELECT * FROM dual@SYS_HUB;
```

#### Resolution Notes

| Field | Value |
|-------|-------|
| Link Purpose | |
| Dependencies Found | [ ] Yes  [ ] No |
| Post-Migration Action | [ ] Keep  [ ] Drop  [ ] Update |
| Date Reviewed | |
| Reviewed By | |

---

### Issue 5: tnsnames.ora Not Found

**Category:** 🟡 Recommended  
**Status:** 🔲 Pending  
**Server:** Source (temandin-oravm-vm01)

#### Problem

The `tnsnames.ora` and `sqlnet.ora` files were not found in the default location:
- Expected: `/u01/app/oracle/product/19.0.0/dbhome_1/network/admin/`

This is not a blocker for migration but can make connectivity testing more difficult.

#### Remediation

**Create tnsnames.ora on source (optional)**

```bash
# SSH to source as oracle user
ssh oracle@temandin-oravm-vm01

# Or as admin user and sudo
ssh temandin@temandin-oravm-vm01
sudo su - oracle

# Create network admin directory if needed
mkdir -p $ORACLE_HOME/network/admin

# Create tnsnames.ora
cat > $ORACLE_HOME/network/admin/tnsnames.ora << 'EOF'
ORADB01 =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = temandin-oravm-vm01)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = oradb01)
    )
  )

# Target connection (for testing after migration)
ORADB01_ODA =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = tmodaauks-rqahk1)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = oradb01)
    )
  )
EOF

# Verify
tnsping ORADB01
```

#### Verification

```bash
tnsping ORADB01
# Expected: OK (XX msec)
```

#### Resolution Notes

| Field | Value |
|-------|-------|
| Action Taken | [ ] Created tnsnames.ora  [ ] Deferred  [ ] Not needed |
| Date Resolved | |
| Notes | |

---

## Completion Checklist

Before proceeding to Step 3, ensure all critical issues are resolved:

### 🔴 Critical Issues
- [ ] Issue 1: OCI Configuration - Status: _______
- [ ] Issue 2: Target Database Name - Status: _______

### 🟡 Recommended Issues
- [ ] Issue 3: Disk Space - Status: _______
- [ ] Issue 4: Database Link Review - Status: _______
- [ ] Issue 5: tnsnames.ora - Status: _______

### Final Verification
- [ ] All critical issues resolved
- [ ] Verification discovery re-run (if changes made)
- [ ] Verification files saved to `Step2/Verification/`

---

## Re-Run Discovery After Fixes

After resolving issues, re-run discovery to verify:

```bash
# From ZDM server
cd /path/to/Step0/Scripts

# Re-run full orchestration
./zdm_orchestrate_discovery.sh

# Or run individual scripts
ssh azureuser@tm-vm-odaa-oracle-jumpbox 'ZDM_USER=zdmuser bash -s' < zdm_server_discovery.sh

# Save outputs to Step2/Verification/
```

---

## Next Steps

Once all critical issues are resolved:

1. ✅ Update this Issue Resolution Log with resolution details
2. ✅ Save verification discovery files to `Step2/Verification/`
3. 🔲 Run `Step3-Generate-Migration-Artifacts.prompt.md` with:
   - Completed questionnaire from Step 1
   - This Issue Resolution Log
   - Latest discovery files

---

*Generated by ZDM Migration Planning - Step 2*  
*Date: February 5, 2026*
