# Issue Resolution Log: PRODDB

## Generated
- **Date:** 2026-02-03
- **Discovery Summary Referenced:** Discovery-Summary-PRODDB.md
- **Migration Questionnaire Referenced:** Migration-Questionnaire-PRODDB.md

---

## Summary

| # | Issue | Category | Status | Date Resolved | Verified By |
|---|-------|----------|--------|---------------|-------------|
| 1 | OCI CLI not configured for azureuser | 🔴 Critical | 🔲 Pending | | |
| 2 | Verify OCI Configuration for zdmuser | 🔴 Critical | 🔲 Pending | | |
| 3 | Disk space below threshold (24GB vs 50GB recommended) | ⚠️ Recommended | 🔲 Pending | | |
| 4 | Confirm target database for migration | ⚠️ Recommended | 🔲 Pending | | |
| 5 | Review SYS_HUB database link | ⚡ Informational | 🔲 Pending | | |

---

## Issue Analysis

### Overall Migration Readiness

| Component | Status | Notes |
|-----------|--------|-------|
| Source Database | ✅ Ready | All prerequisites met (ARCHIVELOG, Force Logging, Supplemental Logging) |
| Target Environment | ✅ Ready | RAC cluster online, ASM available, listeners running |
| ZDM Server | ⚠️ Actions Required | OCI config needs verification, disk space warning |
| Network | ✅ Ready | SSH and Oracle ports open to source and target |

**Good News:** The source database is fully configured for ONLINE_PHYSICAL migration. No database-level changes are required.

---

## Issue Details

---

### Issue 1: OCI CLI Not Configured for azureuser

**Category:** 🔴 Critical  
**Status:** 🔲 Pending  
**Affects:** ZDM Server (tm-vm-odaa-oracle-jumpbox)

#### Problem

The OCI CLI configuration file and API key are not found for the `azureuser` account:
- `/home/azureuser/.oci/config` - **Not Found**
- OCI API Key - **Not Found**

However, SSH keys exist for `zdmuser` at `/home/zdmuser/.oci/odaa.pem`, suggesting ZDM operations should run as `zdmuser`.

#### Remediation Option A: Use zdmuser for ZDM Operations (Recommended)

Since `zdmuser` appears to already have OCI configuration, verify and use this account:

```bash
# Connect to ZDM server
ssh azureuser@tm-vm-odaa-oracle-jumpbox

# Check if zdmuser has OCI config
sudo -u zdmuser cat /home/zdmuser/.oci/config

# Test OCI connectivity as zdmuser
sudo -u zdmuser oci os ns get
```

**If zdmuser OCI config exists and works:** 
- Use `zdmuser` for all ZDM operations
- Update Issue 1 status to ✅ Resolved
- Proceed with ZDM migration using zdmuser

#### Remediation Option B: Configure OCI CLI for azureuser

If you need to configure OCI CLI for `azureuser`:

```bash
# Connect to ZDM server as azureuser
ssh azureuser@tm-vm-odaa-oracle-jumpbox

# Create .oci directory
mkdir -p ~/.oci
chmod 700 ~/.oci

# Option 1: Copy existing config from zdmuser (if accessible)
sudo cp /home/zdmuser/.oci/config ~/.oci/config
sudo cp /home/zdmuser/.oci/odaa.pem ~/.oci/odaa.pem
sudo chown azureuser:azureuser ~/.oci/*
chmod 600 ~/.oci/*

# Option 2: Create new OCI configuration
oci setup config
# Follow prompts to enter:
# - User OCID (from OCI Console > Profile > User Settings)
# - Tenancy OCID (from OCI Console > Profile > Tenancy Details)
# - Region (uk-london-1 based on target FQDN)
# - Path for API key
```

#### Manual OCI Config File Creation

If using Option 2, create the config file manually:

```bash
cat > ~/.oci/config << 'EOF'
[DEFAULT]
user=ocid1.user.oc1..YOUR_USER_OCID
fingerprint=XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX
tenancy=ocid1.tenancy.oc1..YOUR_TENANCY_OCID
region=uk-london-1
key_file=/home/azureuser/.oci/api_private_key.pem
EOF

chmod 600 ~/.oci/config
```

#### Verification

```bash
# Test OCI connectivity
oci os ns get

# Expected output:
# {
#   "data": "your-namespace-name"
# }

# Test listing buckets (should work if proper permissions)
oci os bucket list --compartment-id <compartment-ocid>
```

#### Resolution Notes
_[To be filled when resolved]_

---

### Issue 2: Verify OCI Configuration for zdmuser

**Category:** 🔴 Critical  
**Status:** 🔲 Pending  
**Affects:** ZDM Server (tm-vm-odaa-oracle-jumpbox)

#### Problem

Discovery found OCI key file at `/home/zdmuser/.oci/odaa.pem`, but the OCI configuration was not fully verified during discovery.

#### Remediation

Run these commands on the ZDM server to verify zdmuser's OCI configuration:

```bash
# Connect to ZDM server
ssh azureuser@tm-vm-odaa-oracle-jumpbox

# Check if zdmuser OCI config exists
sudo -u zdmuser cat /home/zdmuser/.oci/config

# Test OCI connectivity as zdmuser
sudo -u zdmuser oci os ns get

# Verify the Object Storage namespace (needed for migration)
sudo -u zdmuser oci os ns get --query 'data' --raw-output
```

#### If OCI Config is Missing for zdmuser

```bash
# Switch to zdmuser
sudo su - zdmuser

# Create OCI configuration
mkdir -p ~/.oci
chmod 700 ~/.oci

# Configure OCI CLI interactively
oci setup config

# Or create config manually
cat > ~/.oci/config << 'EOF'
[DEFAULT]
user=ocid1.user.oc1..YOUR_USER_OCID
fingerprint=XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX
tenancy=ocid1.tenancy.oc1..YOUR_TENANCY_OCID
region=uk-london-1
key_file=/home/zdmuser/.oci/odaa.pem
EOF

chmod 600 ~/.oci/config
```

#### Verification

```bash
# As zdmuser, verify connectivity to OCI
sudo -u zdmuser oci os ns get

# Test access to compartment (optional but recommended)
sudo -u zdmuser oci iam compartment list --query "data[].name"
```

#### Resolution Notes
_[To be filled when resolved]_

---

### Issue 3: Disk Space Below Threshold

**Category:** ⚠️ Recommended  
**Status:** 🔲 Pending  
**Affects:** ZDM Server (tm-vm-odaa-oracle-jumpbox)

#### Problem

| Mount Point | Available | Recommended | Gap |
|-------------|-----------|-------------|-----|
| /u01/app/zdmhome | 24 GB | 50 GB | -26 GB |

#### Risk Assessment

For this migration:
- **Source database size:** 1.92 GB data files
- **Available space:** 24 GB
- **Risk Level:** LOW

The 24 GB available space is **likely sufficient** for this small database migration. ZDM primarily needs space for:
- Response files and logs (~100 MB)
- Temporary backup files if not using direct Object Storage path

#### Remediation Options

**Option A: Accept Current Space (Recommended for this migration)**

Given the small database size (1.92 GB), the available 24 GB should be sufficient.

```bash
# Monitor disk space during migration
df -h /u01/app/zdmhome

# Set up monitoring (optional)
watch -n 60 'df -h /u01/app/zdmhome'
```

**Option B: Expand Storage (If concerned)**

```bash
# Check current disk configuration
sudo lsblk
sudo lvdisplay

# If using LVM, expand logical volume
# Example (adjust device names):
sudo lvextend -L +30G /dev/mapper/vg_zdm-lv_zdm
sudo xfs_growfs /u01/app/zdmhome  # For XFS
# OR
sudo resize2fs /dev/mapper/vg_zdm-lv_zdm  # For ext4
```

**Option C: Clean up existing files**

```bash
# Check for old ZDM jobs that can be cleaned
ls -la /u01/app/zdmhome/zdm/zdm_*

# Remove completed job directories (after confirming they're no longer needed)
# zdmcli query job -jobid <old_job_id>
# zdmcli abort job -jobid <old_job_id>  # If stuck

# Clear old logs
find /u01/app/zdmhome/zdm/log -type f -mtime +30 -delete
```

#### Verification

```bash
# Check current space
df -h /u01/app/zdmhome

# Expected: At least 20 GB free (10x database size as safety margin)
```

#### Resolution Notes
_[To be filled when resolved - Note if space was expanded or if current space is accepted]_

---

### Issue 4: Confirm Target Database for Migration

**Category:** ⚠️ Recommended  
**Status:** 🔲 Pending  
**Affects:** Target Environment (tmodaauks-rqahk1/rqahk2)

#### Problem

Discovery found three existing databases on target, but no clear empty database designated for the PRODDB migration:

| Database | Status | Notes |
|----------|--------|-------|
| migdb | ONLINE | Currently in use with PDB migdbpdb |
| mydb | OFFLINE | Unknown purpose |
| oradb01m | OFFLINE | Appears to be previous migration attempt |

#### Decision Required

**Question:** Which approach will you use for the target database?

| Option | Action Required |
|--------|-----------------|
| A. Use existing `oradb01m` | Verify it's empty or can be overwritten |
| B. Create new database | Specify new database unique name |
| C. ZDM will create target | Provide target DB unique name for ZDM to create |

#### Remediation Option A: Verify oradb01m

```bash
# SSH to target as opc
ssh opc@tmodaauks-rqahk1

# Switch to oracle user
sudo su - oracle

# Check oradb01m status and contents
export ORACLE_SID=oradb01m1
export ORACLE_HOME=/u02/app/oracle/product/19.0.0.0/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH

# Try to start and check
sqlplus / as sysdba << EOF
STARTUP;
SELECT NAME, OPEN_MODE FROM V\$DATABASE;
SELECT TABLESPACE_NAME, BYTES/1024/1024 MB FROM DBA_DATA_FILES;
SHUTDOWN IMMEDIATE;
EOF
```

#### Remediation Option B: Remove oradb01m and Let ZDM Create Fresh

```bash
# If oradb01m should be removed (run as oracle on target)
# WARNING: This destroys the database!

# Stop database if running
srvctl stop database -d oradb01m -force

# Remove database from cluster
srvctl remove database -d oradb01m

# Clean up files (if needed)
# asmcmd rm -rf +DATAC3/ORADB01M/
# asmcmd rm -rf +RECOC3/ORADB01M/
```

#### Recommended Approach for ZDM

For ONLINE_PHYSICAL migration, ZDM typically:
1. Uses an existing empty CDB (to create PDB into) OR
2. Creates a new database on the target

**Recommended target configuration for questionnaire:**

```yaml
target_db_unique_name: oradb01_tgt  # Or your preferred name
target_database_name: ORADB01
# Note: If source is Non-CDB and target should be Non-CDB, 
# ZDM will handle the setup
```

#### Verification

Once target database approach is decided, update the Migration Questionnaire Section A.3 with:
- Target DB Unique Name
- Whether using existing database or creating new

#### Resolution Notes
_[To be filled with final decision on target database approach]_

---

### Issue 5: Review SYS_HUB Database Link

**Category:** ⚡ Informational  
**Status:** 🔲 Pending  
**Affects:** Source Database (oradb01)

#### Problem

A database link exists that won't automatically work post-migration:

| Owner | Link Name | Remote User | Purpose |
|-------|-----------|-------------|---------|
| SYS | SYS_HUB | SEEDDATA | Unknown - needs review |

#### Assessment Questions

1. Is this database link still needed?
2. What does it connect to?
3. Will the remote database be accessible from the new target network?

#### Remediation

**Step 1: Document the database link details**

```sql
-- Run on source database as SYS
SELECT 
    OWNER,
    DB_LINK,
    USERNAME,
    HOST,
    CREATED
FROM DBA_DB_LINKS 
WHERE DB_LINK = 'SYS_HUB';

-- Test if link is functional
SELECT * FROM DUAL@SYS_HUB;
```

**Step 2: Decision Matrix**

| If... | Then... |
|-------|---------|
| Link is not needed | Document as deprecated, no action needed |
| Link is needed | Document connection details for manual recreation |
| Remote host needs reconfiguration | Plan TNS/network updates post-migration |

**Step 3: If recreation needed post-migration**

```sql
-- Template for recreating on target (run after migration)
CREATE DATABASE LINK SYS_HUB
CONNECT TO SEEDDATA IDENTIFIED BY "password"
USING 'tns_alias_or_connect_string';
```

#### Verification

Update Migration Questionnaire Section G with your decision:
- [ ] Recreate links post-migration
- [ ] Document for manual recreation  
- [ ] Links no longer needed

#### Resolution Notes
_[To be filled with decision on database link handling]_

---

## Completion Checklist

Before proceeding to Step 3 (Generate Migration Artifacts):

| # | Checklist Item | Status |
|---|----------------|--------|
| 1 | Issue 1 or 2 resolved (OCI CLI working for zdmuser OR azureuser) | 🔲 |
| 2 | Disk space verified as sufficient or expanded | 🔲 |
| 3 | Target database approach confirmed and documented | 🔲 |
| 4 | Database link decision documented in questionnaire | 🔲 |
| 5 | Migration Questionnaire Section B (OCI OCIDs) completed | 🔲 |
| 6 | All 🔴 Critical issues resolved | 🔲 |

---

## Re-Running Discovery After Fixes

After resolving issues, verify the fixes by re-running relevant discovery:

### Verify OCI Configuration

```bash
# On ZDM server as the user who will run ZDM
# (zdmuser recommended)

# Test 1: OCI namespace
oci os ns get

# Test 2: List compartments (verify permissions)
oci iam compartment list --query "data[*].{name:name, id:id}" --output table

# Test 3: Verify target infrastructure access
oci db exadata-infrastructure list --compartment-id <compartment-ocid> --query "data[*].{name:\"display-name\", id:id}" --output table
```

### Re-run Full ZDM Server Discovery

```bash
# If significant changes made to ZDM server
cd /path/to/discovery/scripts
./zdm_orchestrate_discovery.sh server

# Save output to Step2/Verification/
mv zdm_server_discovery_*.json ../Step2/Verification/
mv zdm_server_discovery_*.txt ../Step2/Verification/
```

---

## Quick Resolution Commands

For convenience, here are the most likely commands needed:

```bash
# === On ZDM Server (tm-vm-odaa-oracle-jumpbox) ===

# Check zdmuser OCI config (most likely resolution)
sudo -u zdmuser cat /home/zdmuser/.oci/config
sudo -u zdmuser oci os ns get

# Check disk space
df -h /u01/app/zdmhome

# === On Target (tmodaauks-rqahk1) ===

# Check existing databases
ssh opc@tmodaauks-rqahk1 "sudo -u oracle srvctl status database -d oradb01m"

# List all databases
ssh opc@tmodaauks-rqahk1 "sudo -u oracle cat /etc/oratab | grep -v '^#'"
```

---

## Next Steps

Once all issues are resolved:

1. ✅ Update this Issue Resolution Log with resolution notes
2. ✅ Complete all sections of Migration-Questionnaire-PRODDB.md (especially Section B - OCI OCIDs)
3. ✅ Save any verification discovery outputs to `Step2/Verification/`
4. 🔲 Proceed to `Step3-Generate-Migration-Artifacts.prompt.md`

---

*Generated by ZDM Migration Planning - Step 2*
*Date: 2026-02-03*
