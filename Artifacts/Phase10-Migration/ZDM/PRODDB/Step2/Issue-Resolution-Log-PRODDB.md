# Issue Resolution Log: PRODDB

## Generated
- **Date:** 2026-01-30
- **Database:** PRODDB (ORADB01)
- **Source:** temandin-oravm-vm01 (10.1.0.10)
- **Target:** tmodaauks-rqahk1 (10.0.1.160)
- **ZDM Server:** tm-vm-odaa-oracle-jumpbox (10.1.0.8)

---

## Summary

| # | Issue | Category | Priority | Status | Date Resolved | Verified By |
|---|-------|----------|----------|--------|---------------|-------------|
| 1 | Enable Supplemental Logging | 🔴 Critical | Critical | 🔲 Pending | | |
| 2 | Install OCI CLI on ZDM Server | 🔴 Critical | Critical | 🔲 Pending | | |
| 3 | Configure OCI CLI on ZDM Server | 🔴 Critical | Critical | 🔲 Pending | | |
| 4 | Create SSH Keys for Oracle User on Source | 🟡 Required | High | 🔲 Pending | | |
| 5 | Configure SSH Keys for Oracle User on Target | 🟡 Required | High | 🔲 Pending | | |
| 6 | Confirm Target Database Selection | 🟡 Required | High | 🔲 Pending | | |
| 7 | Review ZDM Server Disk Space | 🔵 Advisory | Medium | 🔲 Pending | | |
| 8 | Plan Database Link Reconfiguration | 🔵 Advisory | Low | 🔲 Pending | | |
| 9 | Review Scheduler Jobs | 🔵 Advisory | Low | 🔲 Pending | | |

---

## Issue Details

---

### Issue 1: Enable Supplemental Logging on Source Database

**Category:** 🔴 Critical Blocker  
**Status:** 🔲 Pending  
**Server:** Source Database (temandin-oravm-vm01)  
**Required For:** ONLINE_PHYSICAL migration with Data Guard

#### Problem

Supplemental logging is **not enabled** on the source database. This is **mandatory** for online physical migration as it ensures that redo logs contain sufficient information for the target database to apply changes during synchronization.

**Current State:**
| Setting | Current | Required |
|---------|---------|----------|
| SUPPLEMENTAL_LOG_DATA_MIN | NO | YES |
| SUPPLEMENTAL_LOG_DATA_PK | NO | Recommended |

#### Remediation Steps

**Step 1:** Connect to source database as SYSDBA

```bash
# SSH to source server as oracle user
ssh oracle@10.1.0.10

# Connect to database
sqlplus / as sysdba
```

**Step 2:** Enable supplemental logging

```sql
-- Enable minimal supplemental logging (REQUIRED)
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;

-- Enable primary key supplemental logging (RECOMMENDED for online migration)
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (PRIMARY KEY) COLUMNS;

-- Force a log switch to ensure changes are captured
ALTER SYSTEM SWITCH LOGFILE;
```

**Step 3:** Verify the changes

```sql
-- Verify supplemental logging is enabled
SELECT 
    SUPPLEMENTAL_LOG_DATA_MIN AS "Min Logging",
    SUPPLEMENTAL_LOG_DATA_PK AS "PK Logging",
    SUPPLEMENTAL_LOG_DATA_UI AS "UI Logging",
    SUPPLEMENTAL_LOG_DATA_FK AS "FK Logging",
    SUPPLEMENTAL_LOG_DATA_ALL AS "All Logging"
FROM V$DATABASE;
```

**Expected Output:**
```
Min Logging  PK Logging  UI Logging  FK Logging  All Logging
-----------  ----------  ----------  ----------  -----------
YES          YES         NO          NO          NO
```

#### Rollback (if needed)

```sql
-- Remove supplemental logging (if rollback required)
ALTER DATABASE DROP SUPPLEMENTAL LOG DATA (PRIMARY KEY) COLUMNS;
ALTER DATABASE DROP SUPPLEMENTAL LOG DATA;

-- Verify removal
SELECT SUPPLEMENTAL_LOG_DATA_MIN, SUPPLEMENTAL_LOG_DATA_PK FROM V$DATABASE;
```

#### Resolution Notes

*[To be completed after resolution]*

| Field | Value |
|-------|-------|
| Date Resolved | |
| Resolved By | |
| Verification Output | |
| Notes | |

---

### Issue 2: Install OCI CLI on ZDM Server

**Category:** 🔴 Critical Blocker  
**Status:** 🔲 Pending  
**Server:** ZDM Server (tm-vm-odaa-oracle-jumpbox)  
**Required For:** ZDM to interact with OCI Object Storage and manage migration jobs

#### Problem

The OCI CLI is **not installed** on the ZDM server. ZDM requires the OCI CLI to:
- Upload/download backups to OCI Object Storage
- Query OCI resource information
- Manage migration workflows

**Current State:**
| Check | Status |
|-------|--------|
| OCI CLI Installed | ❌ NO |
| OCI Config File | ❌ NOT FOUND |

#### Remediation Steps

**Step 1:** SSH to ZDM server

```bash
# Connect as azureuser (admin user)
ssh azureuser@10.1.0.8
```

**Step 2:** Install OCI CLI

```bash
# Run the official OCI CLI installer
# When prompted, accept defaults or customize installation path

bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"
```

**Interactive Prompts (suggested responses):**
```
Install location: [/home/azureuser/lib/oracle-cli] - Press Enter for default
Script location: [/home/azureuser/bin/oci] - Press Enter for default
Add to PATH: [Y] - Yes
```

**Step 3:** Add OCI CLI to PATH (if not automatic)

```bash
# Add to .bashrc if not done by installer
echo 'export PATH=$PATH:$HOME/bin' >> ~/.bashrc
source ~/.bashrc
```

**Step 4:** Verify installation

```bash
# Check OCI CLI version
oci --version
```

**Expected Output:**
```
3.x.x (or current version)
```

#### Rollback (if needed)

```bash
# Remove OCI CLI installation
rm -rf ~/lib/oracle-cli
rm -f ~/bin/oci
# Remove PATH entry from .bashrc if added manually
```

#### Resolution Notes

*[To be completed after resolution]*

| Field | Value |
|-------|-------|
| Date Resolved | |
| Resolved By | |
| OCI CLI Version | |
| Notes | |

---

### Issue 3: Configure OCI CLI on ZDM Server

**Category:** 🔴 Critical Blocker  
**Status:** 🔲 Pending  
**Server:** ZDM Server (tm-vm-odaa-oracle-jumpbox)  
**Required For:** Authentication to OCI services  
**Depends On:** Issue 2 (OCI CLI Installation)

#### Problem

OCI CLI configuration is required to authenticate ZDM with OCI services. This includes:
- User OCID
- Tenancy OCID
- Region
- API Key

#### Prerequisites

Before configuring OCI CLI, you need to obtain the following from OCI Console:

| Value | Where to Find | Status |
|-------|---------------|--------|
| OCI User OCID | OCI Console → Identity & Security → Users → Your User | 🔲 Obtain |
| OCI Tenancy OCID | OCI Console → Governance → Tenancy Details | ✅ Discovered: `ocid1.tenancy.oc1..aaaaaaaaax76pwvum5vhn2p3v264osde3ykrudasfzjktipw3ibpvtndhtkq` |
| OCI Region | uk-london-1 | ✅ Confirmed |
| API Key | Generate via OCI Console or locally | 🔲 Generate |

#### Remediation Steps

**Step 1:** SSH to ZDM server as zdmuser

```bash
# Connect as zdmuser (ZDM operational user)
ssh zdmuser@10.1.0.8

# Or switch from azureuser
sudo su - zdmuser
```

**Step 2:** Generate API Key (if not existing)

```bash
# Create .oci directory
mkdir -p ~/.oci
chmod 700 ~/.oci

# Generate API key pair
openssl genrsa -out ~/.oci/oci_api_key.pem 2048
chmod 600 ~/.oci/oci_api_key.pem

# Generate public key
openssl rsa -pubout -in ~/.oci/oci_api_key.pem -out ~/.oci/oci_api_key_public.pem
```

**Step 3:** Upload public key to OCI Console

1. Go to OCI Console → Identity & Security → Users → Your User
2. Click "API Keys" in the left menu
3. Click "Add API Key"
4. Select "Paste a public key"
5. Paste the contents of `~/.oci/oci_api_key_public.pem`
6. Click "Add"
7. **Copy the fingerprint** shown in the confirmation dialog

**Step 4:** Run OCI CLI setup

```bash
oci setup config
```

**Provide the following values:**
```
Location for config: ~/.oci/config (Press Enter)
User OCID: <your-user-ocid>
Tenancy OCID: ocid1.tenancy.oc1..aaaaaaaaax76pwvum5vhn2p3v264osde3ykrudasfzjktipw3ibpvtndhtkq
Region: uk-london-1
Generate a new key: n
Key file location: ~/.oci/oci_api_key.pem
Fingerprint: <paste-fingerprint-from-console>
```

**Step 5:** Verify OCI CLI configuration

```bash
# Test connection - get namespace (proves authentication works)
oci os ns get

# List buckets in Object Storage
oci os bucket list --compartment-id ocid1.tenancy.oc1..aaaaaaaaax76pwvum5vhn2p3v264osde3ykrudasfzjktipw3ibpvtndhtkq
```

**Expected Output:**
```json
{
  "data": "your-namespace-name"
}
```

#### Rollback (if needed)

```bash
# Remove OCI configuration
rm -rf ~/.oci/config
# Keep the API keys if they might be reused
```

#### Resolution Notes

*[To be completed after resolution]*

| Field | Value |
|-------|-------|
| Date Resolved | |
| Resolved By | |
| User OCID Used | |
| Fingerprint | |
| Namespace Retrieved | |
| Notes | |

---

### Issue 4: Create SSH Keys for Oracle User on Source

**Category:** 🟡 Required Action  
**Status:** 🔲 Pending  
**Server:** Source Database (temandin-oravm-vm01)  
**Required For:** ZDM passwordless SSH access to source database

#### Problem

ZDM requires passwordless SSH access from the zdmuser on ZDM server to the oracle user on the source database server. SSH keys need to be properly configured.

#### Remediation Steps

**Step 1:** On ZDM server - Prepare the public key

```bash
# As zdmuser on ZDM server
ssh zdmuser@10.1.0.8

# Check existing keys
ls -la ~/.ssh/

# The discovery shows these keys exist:
# - iaas.pem, id_ed25519, id_rsa, odaa.pem, zdm.pem
# We'll use the existing id_ed25519 or id_rsa key

# Display public key to copy
cat ~/.ssh/id_ed25519.pub
# Or if using RSA:
cat ~/.ssh/id_rsa.pub
```

**Step 2:** On Source server - Configure oracle user's authorized_keys

```bash
# SSH to source as a user with sudo access (e.g., opc or azureuser)
ssh azureuser@10.1.0.10

# Switch to oracle user
sudo su - oracle

# Create .ssh directory if it doesn't exist
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Add ZDM server's public key
echo "ssh-ed25519 AAAA... zdmuser@tm-vm-odaa-oracle-jumpbox" >> ~/.ssh/authorized_keys

# Or use ssh-copy-id from ZDM server (alternative approach):
# From ZDM server: ssh-copy-id -i ~/.ssh/id_ed25519.pub oracle@10.1.0.10

# Set proper permissions
chmod 600 ~/.ssh/authorized_keys
```

**Step 3:** Test SSH connectivity from ZDM server

```bash
# As zdmuser on ZDM server
ssh -i ~/.ssh/id_ed25519 oracle@10.1.0.10 "echo 'SSH to source OK'; hostname; whoami"
```

**Expected Output:**
```
SSH to source OK
temandin-oravm-vm01
oracle
```

**Step 4:** Verify Oracle environment access

```bash
# Test that oracle environment is accessible
ssh -i ~/.ssh/id_ed25519 oracle@10.1.0.10 "source ~/.bash_profile; echo \$ORACLE_HOME; sqlplus -v"
```

#### Rollback (if needed)

```bash
# On source server, remove the specific key from authorized_keys
# Edit ~/.ssh/authorized_keys and remove the line with zdmuser@tm-vm-odaa-oracle-jumpbox
```

#### Resolution Notes

*[To be completed after resolution]*

| Field | Value |
|-------|-------|
| Date Resolved | |
| Resolved By | |
| Key Type Used | |
| SSH Test Result | |
| Notes | |

---

### Issue 5: Configure SSH Keys for Oracle User on Target

**Category:** 🟡 Required Action  
**Status:** 🔲 Pending  
**Server:** Target Exadata (tmodaauks-rqahk1, tmodaauks-rqahk2)  
**Required For:** ZDM passwordless SSH access to target Exadata nodes

#### Problem

ZDM requires passwordless SSH access from zdmuser on ZDM server to the oracle user on both target Exadata nodes.

> **Note:** For Oracle Database@Azure (Exadata), SSH access typically goes through the opc user first, then to oracle.

#### Remediation Steps

**Step 1:** Determine SSH access pattern for target

```bash
# From ZDM server, check if direct oracle access is possible
ssh -i ~/.ssh/odaa.pem oracle@10.0.1.160 "whoami"

# If that fails, try opc user
ssh -i ~/.ssh/odaa.pem opc@10.0.1.160 "whoami"
```

**Step 2A:** If using opc user (typical for Exadata)

```bash
# SSH to target as opc
ssh -i ~/.ssh/odaa.pem opc@10.0.1.160

# Switch to oracle user
sudo su - oracle

# Create .ssh directory
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Add ZDM server's public key
# Get the public key from ZDM server first
echo "<public-key-content>" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# Repeat for Node 2
ssh -i ~/.ssh/odaa.pem opc@10.0.1.161  # Assuming Node 2 IP
sudo su - oracle
mkdir -p ~/.ssh
chmod 700 ~/.ssh
echo "<public-key-content>" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

**Step 2B:** If using grid user for ASM operations

```bash
# ZDM may also need access to grid user for ASM operations
ssh -i ~/.ssh/odaa.pem opc@10.0.1.160

# Switch to grid user
sudo su - grid

# Create .ssh directory
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Add ZDM server's public key
echo "<public-key-content>" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

**Step 3:** Test SSH connectivity from ZDM server

```bash
# As zdmuser on ZDM server

# Test Node 1
ssh -i ~/.ssh/odaa.pem oracle@10.0.1.160 "echo 'SSH to target node 1 OK'; hostname; whoami"

# Test Node 2 (if applicable)
ssh -i ~/.ssh/odaa.pem oracle@10.0.1.161 "echo 'SSH to target node 2 OK'; hostname; whoami"
```

**Expected Output:**
```
SSH to target node 1 OK
tmodaauks-rqahk1
oracle
```

**Step 4:** Verify Oracle environment access on target

```bash
# Test Oracle environment
ssh -i ~/.ssh/odaa.pem oracle@10.0.1.160 "source ~/.bash_profile; echo \$ORACLE_HOME"
```

**Expected Output:**
```
/u02/app/oracle/product/19.0.0.0/dbhome_1
```

#### Resolution Notes

*[To be completed after resolution]*

| Field | Value |
|-------|-------|
| Date Resolved | |
| Resolved By | |
| Key Used | |
| Node 1 Access | |
| Node 2 Access | |
| Notes | |

---

### Issue 6: Confirm Target Database Selection

**Category:** 🟡 Required Action  
**Status:** 🔲 Pending  
**Server:** Target Exadata (tmodaauks-rqahk1)  
**Required For:** Migration target identification

#### Problem

Multiple databases exist on the target Exadata cluster. The target database/PDB for this migration needs to be confirmed.

**Discovered Databases on Target:**
| Database | Status | Best Candidate? |
|----------|--------|-----------------|
| **ORADB01M** | Open (2-node RAC) | ✅ Likely - naming matches source |
| MIGDB | Open (2-node RAC) | ❌ Appears to be previous migration |
| MYDB | Open (2-node RAC) | ❌ Appears to be test database |

#### Action Required

**Step 1:** Verify ORADB01M is the intended target

```bash
# SSH to target and check ORADB01M details
ssh -i ~/.ssh/odaa.pem oracle@10.0.1.160

# Set environment for ORADB01M
export ORACLE_SID=ORADB01M1  # Node 1 instance

# Connect and check database details
sqlplus / as sysdba <<EOF
SET LINESIZE 200
SELECT name, db_unique_name, database_role, open_mode FROM v\$database;
SHOW PDBS;
SELECT tablespace_name, status FROM dba_tablespaces;
EOF
```

**Step 2:** Confirm database is ready for migration

Check the following:
- [ ] Database is in OPEN mode
- [ ] Wallet status is ready to receive TDE keys
- [ ] Sufficient storage available in ASM diskgroups
- [ ] Database is empty or has the expected schema structure

**Step 3:** Record target database identifiers

After confirmation, obtain these OCIDs from OCI Console:

| Identifier | OCID |
|------------|------|
| Target DB System OCID | |
| Target Database OCID | |
| Target Database Home OCID | |

#### Resolution Notes

*[To be completed after resolution]*

| Field | Value |
|-------|-------|
| Confirmed Target Database | |
| DB_UNIQUE_NAME | |
| Open Mode | |
| Confirmed By | |
| Date | |

---

### Issue 7: Review ZDM Server Disk Space

**Category:** 🔵 Advisory  
**Status:** 🔲 Pending  
**Server:** ZDM Server (tm-vm-odaa-oracle-jumpbox)  
**Impact:** May affect migration performance or cause failures during backup phase

#### Problem

Available disk space on the ZDM server (25GB) is below the recommended 50GB minimum for ZDM operations.

**Current State:**
| Mount Point | Available | Recommended | Status |
|-------------|-----------|-------------|--------|
| / (root) | 25GB | 50GB | ⚠️ Below recommended |

#### Impact Assessment

For PRODDB migration:
- Source database size: **1.88 GB** (small)
- Backup files will be stored temporarily: ~2-4 GB expected
- ZDM logs and working files: ~1-2 GB
- **Available: 25 GB** - Should be sufficient for this migration

#### Recommended Actions

**Option A:** Accept current disk space (Low Risk for this migration)

Given the small database size (1.88 GB), 25 GB should be sufficient. However, monitor disk usage during migration:

```bash
# Monitor disk space during migration
watch -n 60 'df -h / | tail -1'

# Set up alert if space drops below 5GB
# Add to crontab:
*/5 * * * * [ $(df / | tail -1 | awk '{print $4}' | sed 's/G//') -lt 5 ] && echo "Low disk space on ZDM server" | mail -s "ZDM Disk Alert" admin@example.com
```

**Option B:** Increase disk space (Recommended for future migrations)

```bash
# If using Azure VM, extend the OS disk via Azure Portal or CLI
# Then extend the filesystem:
sudo growpart /dev/sda 1
sudo xfs_growfs /
```

**Option C:** Clean up unnecessary files

```bash
# Check disk usage by directory
du -sh /* 2>/dev/null | sort -h

# Clean old logs if present
find /var/log -name "*.log" -mtime +30 -delete

# Clean package manager cache
sudo yum clean all  # For RHEL/OL
```

#### Resolution Notes

*[To be completed after resolution]*

| Field | Value |
|-------|-------|
| Decision | Accept / Increase / Clean |
| Current Available | |
| Post-Action Available | |
| Notes | |

---

### Issue 8: Plan Database Link Reconfiguration

**Category:** 🔵 Advisory (Post-Migration)  
**Status:** 🔲 Pending  
**Server:** Target Database  
**When:** After successful migration

#### Problem

The source database has a database link `SYS_HUB` that connects to `SEEDDATA`. After migration, this link will need to be reconfigured for the target environment.

**Discovered Database Link:**
| Owner | DB Link Name | Host |
|-------|--------------|------|
| SYS | SYS_HUB | SEEDDATA |

#### Action Required (Post-Migration)

**Step 1:** Understand the database link purpose

```sql
-- Before migration, document the link details
SELECT owner, db_link, username, host FROM dba_db_links WHERE db_link = 'SYS_HUB';

-- Check if link is actively used
SELECT * FROM dba_dependencies WHERE referenced_link_name = 'SYS_HUB';
```

**Step 2:** Plan for post-migration

| Question | Answer |
|----------|--------|
| Is this link still needed? | |
| What does SEEDDATA resolve to? | |
| Will the target host change? | |
| New TNS entry required? | |

**Step 3:** Post-migration reconfiguration

```sql
-- Drop old link if no longer needed
DROP DATABASE LINK SYS_HUB;

-- Or recreate with new target
CREATE DATABASE LINK SYS_HUB
CONNECT TO username IDENTIFIED BY "password"
USING 'new_tns_entry';
```

#### Resolution Notes

*[To be completed after migration]*

| Field | Value |
|-------|-------|
| Link Still Needed | Yes / No |
| New Target | |
| Reconfigured Date | |
| Tested By | |

---

### Issue 9: Review Scheduler Jobs

**Category:** 🔵 Advisory (Post-Migration)  
**Status:** 🔲 Pending  
**Server:** Target Database  
**When:** After successful migration

#### Problem

The source database has several scheduler jobs that will be migrated. These should be reviewed for appropriateness in the target environment.

**Discovered Scheduler Jobs:**
| Owner | Job Name | Schedule |
|-------|----------|----------|
| ORACLE_OCM | MGMT_CONFIG_JOB | Daily at 01:01 |
| ORACLE_OCM | MGMT_STATS_CONFIG_JOB | Monthly on 1st |
| SYS | BSLN_MAINTAIN_STATS_JOB | Weekly |
| SYS | CLEANUP_NON_EXIST_OBJ | Every 12 hours |
| SYS | ORA$AUTOTASK_CLEAN | Daily at 03:00 |
| SYS | PURGE_LOG | Daily at 03:00 |

#### Action Required (Post-Migration)

**Step 1:** Review jobs after migration

```sql
-- List all enabled jobs
SELECT owner, job_name, enabled, state, last_start_date, next_run_date
FROM dba_scheduler_jobs
WHERE enabled = 'TRUE'
ORDER BY owner, job_name;
```

**Step 2:** Consider the following

| Job Category | Review Action |
|--------------|---------------|
| OCM Jobs | May not be needed in cloud environment |
| Maintenance Jobs | Usually should remain enabled |
| Custom Jobs | Review for environment-specific changes |

**Step 3:** Disable unnecessary jobs

```sql
-- Example: Disable a job
BEGIN
  DBMS_SCHEDULER.DISABLE('ORACLE_OCM.MGMT_CONFIG_JOB');
END;
/
```

#### Resolution Notes

*[To be completed after migration]*

| Field | Value |
|-------|-------|
| Jobs Reviewed | |
| Jobs Disabled | |
| Jobs Modified | |
| Reviewed By | |
| Date | |

---

## Re-Running Discovery (Verification)

After fixing critical issues, re-run discovery to verify fixes:

### Option 1: Run Orchestrated Discovery

```bash
# From ZDM server as zdmuser
cd /path/to/scripts
./zdm_orchestrate_discovery.sh all
```

### Option 2: Run Individual Discovery Scripts

```bash
# Re-run source discovery to verify supplemental logging
ssh oracle@10.1.0.10 'bash -s' < zdm_source_discovery.sh > verification_source_$(date +%Y%m%d_%H%M%S).txt

# Re-run ZDM server discovery to verify OCI CLI
./zdm_server_discovery.sh > verification_server_$(date +%Y%m%d_%H%M%S).txt
```

### Save Verification Files

Save updated discovery outputs to:
```
Artifacts/Phase10-Migration/ZDM/PRODDB/Step2/Verification/
```

---

## Completion Checklist

Before proceeding to Step 3 (Generate Migration Artifacts):

### Critical Issues (Must Complete)
- [ ] ✅ Issue 1: Supplemental Logging Enabled
- [ ] ✅ Issue 2: OCI CLI Installed
- [ ] ✅ Issue 3: OCI CLI Configured

### Required Actions (Should Complete)
- [ ] ✅ Issue 4: SSH Keys for Source Configured
- [ ] ✅ Issue 5: SSH Keys for Target Configured
- [ ] ✅ Issue 6: Target Database Confirmed

### Advisory Items (Track for Post-Migration)
- [ ] 📝 Issue 7: Disk Space Noted
- [ ] 📝 Issue 8: DB Link Reconfiguration Planned
- [ ] 📝 Issue 9: Scheduler Jobs Noted

### Verification
- [ ] Verification discovery scripts re-run
- [ ] No new blockers identified
- [ ] All team members aware of post-migration items

---

## Remediation Scripts

Pre-built scripts for common fixes are available in:
```
Artifacts/Phase10-Migration/ZDM/PRODDB/Step2/Scripts/
```

- `fix_supplemental_logging.sql` - Enable supplemental logging on source
- `install_oci_cli.sh` - Install OCI CLI on ZDM server
- `configure_ssh_keys.sh` - Configure SSH key authentication
- `verify_fixes.sh` - Verify all fixes applied

---

## Next Steps

Once all critical and required issues are resolved:

1. ✅ Save this Issue Resolution Log
2. ✅ Save verification discovery files
3. 🔲 Complete the Migration Questionnaire (if not done)
4. 🔲 Run `Step3-Generate-Migration-Artifacts.prompt.md` with:
   - Completed questionnaire from Step 1
   - This Issue Resolution Log from Step 2
   - Latest discovery/verification files

---

*Generated by ZDM Migration Planning - Step 2*
*Date: 2026-01-30*
