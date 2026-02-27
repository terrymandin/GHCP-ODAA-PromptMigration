# Example: Step 2 - Fix Issues for <DATABASE_NAME>

> **Note:** Replace `<DATABASE_NAME>` with your database name (e.g., PRODDB, HRDB, etc.). The value you specify in Example-Step0-Generate-Discovery-Scripts.prompt.md will be used throughout all steps.

## Example Prompt

```
@Step2-Fix-Issues.prompt.md

## Project Configuration
#file:prompts/Phase10-Migration/ZDM/zdm-env.md

Please help me resolve the issues identified in the Discovery Summary for our <DATABASE_NAME> migration.

## Attached Files

### Step1 Outputs
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step1/

### Discovery Files (from Step0 - for reference)
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step0/Discovery/source/
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step0/Discovery/target/
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step0/Discovery/server/

## Output Directory
Save all generated artifacts to: Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step2/
```

> **Note:** Replace `<DATABASE_NAME>` with the `PROJECT_NAME` value from [zdm-env.md](zdm-env.md).
> When referencing directories, GitHub Copilot will read all files in those directories.

---

## Example Output

### Issue Analysis

Based on the Discovery Summary for PRODDB, the following issues require resolution:

| Issue | Category | Priority | Status |
|-------|----------|----------|--------|
| Supplemental logging not enabled | ⚠️ Required | High | 🔲 Pending |
| OCI CLI not installed on ZDM server | ⚠️ Required | High | 🔲 Pending |
| Network connectivity blocked (ZDM → Source/Target) | ❌ Blocker | Critical | 🔲 Pending |
| Low disk space on ZDM server (25GB available) | ⚠️ Required | Medium | 🔲 Pending |
| Database link SYS_HUB will need recreation | ⚡ Recommendation | Low | 📝 Noted |

---

### Issue Resolution Log Generated

**File:** `Artifacts/Phase10-Migration/ZDM/PRODDB/Step2/Issue-Resolution-Log-PRODDB.md`

```markdown
# Issue Resolution Log: PRODDB

## Summary

| Issue | Status | Date Resolved | Verified By |
|-------|--------|---------------|-------------|
| Enable supplemental logging | 🔲 Pending | | |
| Install OCI CLI | 🔲 Pending | | |
| Configure network connectivity | 🔲 Pending | | |
| Increase ZDM disk space | 🔲 Pending | | |

---

## Issue 1: Supplemental Logging Not Enabled

**Category:** ⚠️ Required Action
**Status:** 🔲 Pending
**Server:** Source Database (temandin-oravm-vm01)

**Problem:**
Discovery shows supplemental logging is not enabled on the source database ORADB01.
This is required for online physical migration using Data Guard.

**Current State (from Discovery):**
- SUPPLEMENTAL_LOG_DATA_MIN: NO
- SUPPLEMENTAL_LOG_DATA_PK: NO

**Remediation:**
```sql
-- Connect to source database as SYS
sqlplus sys@oradb01 as sysdba

-- Enable supplemental logging
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (PRIMARY KEY) COLUMNS;

-- Force log switch to ensure changes take effect
ALTER SYSTEM SWITCH LOGFILE;
```

**Verification:**
```sql
-- Verify supplemental logging is enabled
SELECT SUPPLEMENTAL_LOG_DATA_MIN, SUPPLEMENTAL_LOG_DATA_PK 
FROM V$DATABASE;

-- Expected output:
-- SUPPLEMENTAL_LOG_DATA_MIN: YES
-- SUPPLEMENTAL_LOG_DATA_PK: YES
```

**Resolution Notes:**
[To be filled after resolution]

---

## Issue 2: OCI CLI Not Installed

**Category:** ⚠️ Required Action
**Status:** 🔲 Pending
**Server:** ZDM Server (tm-vm-odaa-oracle-jumpbox)

**Problem:**
Discovery shows OCI CLI is not installed on the ZDM server.
OCI CLI is required for ZDM to communicate with OCI Object Storage during migration.

**Remediation:**
```bash
# Connect to ZDM server
ssh azureuser@tm-vm-odaa-oracle-jumpbox

# Install OCI CLI
bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"

# Answer prompts:
#   - Install directory: /home/azureuser/lib/oracle-cli
#   - Script location: /home/azureuser/bin
#   - Config location: /home/azureuser/.oci

# Configure OCI CLI with API key
oci setup config

# Provide:
#   - User OCID (from OCI Console)
#   - Tenancy OCID (from OCI Console)
#   - Region (e.g., uk-london-1)
#   - Generate new API key: Yes
#   - Key file location: /home/azureuser/.oci/oci_api_key.pem

# Upload public key to OCI Console:
# Profile → User Settings → API Keys → Add API Key
```

**Verification:**
```bash
# Test OCI CLI connectivity
oci os ns get

# Expected: Returns namespace string
# Example: { "data": "axxxxxxxxxxx" }
```

**Resolution Notes:**
[To be filled after resolution]

---

## Issue 3: Network Connectivity Blocked

**Category:** ❌ Blocker
**Status:** 🔲 Pending
**Server:** All (ZDM, Source, Target)

**Problem:**
Discovery shows network connectivity is blocked between:
- ZDM Server → Source Database (SSH:22, Oracle:1521)
- ZDM Server → Target Database (SSH:22, Oracle:1521)

**Current State (from Discovery):**
```
ZDM → Source SSH (10.1.0.10:22): FAILED
ZDM → Source Oracle (10.1.0.10:1521): FAILED
ZDM → Target SSH (10.0.1.155:22): FAILED
ZDM → Target Oracle (10.0.1.155:1521): FAILED
```

**Remediation:**

1. **Azure NSG Rules (Source Network)**
   - Navigate to Azure Portal → Network Security Groups
   - Find NSG for source VM (temandin-oravm-vm01)
   - Add inbound rules:
     | Priority | Name | Port | Protocol | Source | Action |
     |----------|------|------|----------|--------|--------|
     | 100 | Allow-ZDM-SSH | 22 | TCP | 10.0.0.0/16 | Allow |
     | 110 | Allow-ZDM-Oracle | 1521 | TCP | 10.0.0.0/16 | Allow |

2. **OCI Security Lists (Target Network)**
   - Navigate to OCI Console → Networking → Virtual Cloud Networks
   - Find VCN for target system
   - Update Security List:
     | Stateless | Source | Protocol | Dest Port | Description |
     |-----------|--------|----------|-----------|-------------|
     | No | 10.0.0.0/16 | TCP | 22 | ZDM SSH access |
     | No | 10.0.0.0/16 | TCP | 1521 | ZDM Oracle access |

3. **Host-level Firewall (if applicable)**
   ```bash
   # On source server
   sudo firewall-cmd --permanent --add-port=1521/tcp
   sudo firewall-cmd --reload
   ```

**Verification:**
```bash
# From ZDM server
nc -zv 10.1.0.10 22     # Source SSH
nc -zv 10.1.0.10 1521   # Source Oracle
nc -zv 10.0.1.155 22    # Target SSH
nc -zv 10.0.1.155 1521  # Target Oracle

# SSH test
ssh -i /home/azureuser/key.pem oracle@10.1.0.10 "echo 'Source OK'"
ssh -i /home/azureuser/key.pem opc@10.0.1.155 "echo 'Target OK'"

# Oracle test
sqlplus sys@'10.1.0.10:1521/oradb01' as sysdba
```

**Resolution Notes:**
[To be filled after resolution]

---

## Issue 4: Low Disk Space on ZDM Server

**Category:** ⚠️ Required Action
**Status:** 🔲 Pending
**Server:** ZDM Server (tm-vm-odaa-oracle-jumpbox)

**Problem:**
Only 25GB disk space available on ZDM server. ZDM requires space for:
- ZDM working files
- Temporary backup staging (if local staging is used)
- Log files

**Remediation Options:**

Option A: Clean up disk space
```bash
# Check current usage
df -h

# Clean package cache
sudo yum clean all

# Remove old logs
sudo find /var/log -type f -name "*.gz" -delete
sudo journalctl --vacuum-time=7d
```

Option B: Expand disk (Azure)
```bash
# 1. Stop VM in Azure Portal
# 2. Go to Disks → Select OS disk → Size + Performance
# 3. Increase size (e.g., to 128GB)
# 4. Start VM
# 5. Extend partition

sudo growpart /dev/sda 2
sudo xfs_growfs /
```

**Verification:**
```bash
df -h
# Ensure at least 50GB free space available
```

**Resolution Notes:**
[To be filled after resolution]
```

---

---

### Script README Files Generated

A `README-<scriptname>.md` is saved alongside each script in `Artifacts/Phase10-Migration/ZDM/PRODDB/Step2/Scripts/`.

**Example — `README-fix_source_PRODDB.md`:**

```markdown
# README: fix_source_PRODDB.sh

## Purpose
Enables supplemental logging on the source Oracle database (ORADB01) to satisfy ZDM online physical migration prerequisites.

## Target Server
**Source Database Server** — `temandin-oravm-vm01` (run via SSH from the ZDM jumpbox)

## Prerequisites
- SSH access to the source server as `temandin` (admin user with sudo)
- Oracle database `ORADB01` must be open and in ARCHIVELOG mode
- Environment variables sourced from `zdm-env.md`:
  - `SOURCE_HOST` — hostname or IP of the source server
  - `SOURCE_SSH_KEY` — path to the SSH private key
  - `SOURCE_SSH_USER` — admin SSH user (e.g., `temandin`)
  - `ORACLE_USER` — OS Oracle user (e.g., `oracle`)
  - `ORACLE_HOME` — Oracle home path (e.g., `/u01/app/oracle/product/19.0.0/dbhome_1`)
  - `ORACLE_SID` — Oracle SID (e.g., `ORADB01`)

## What It Does
1. SSH into the source server as `SOURCE_SSH_USER`
2. Switches to `ORACLE_USER` via `sudo -u oracle bash -c '...'`
3. Connects to the database as SYSDBA using `sqlplus / as sysdba`
4. Runs `ALTER DATABASE ADD SUPPLEMENTAL LOG DATA`
5. Runs `ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (PRIMARY KEY) COLUMNS`
6. Runs `ALTER SYSTEM SWITCH LOGFILE` to flush redo
7. Queries `V$DATABASE` to verify `SUPPLEMENTAL_LOG_DATA_MIN = YES` and `SUPPLEMENTAL_LOG_DATA_PK = YES`
8. Prints PASS or FAIL based on the verification result and exits with the appropriate code

## How to Run
```bash
# From the ZDM server, ensure environment variables are set, then:
bash Artifacts/Phase10-Migration/ZDM/PRODDB/Step2/Scripts/fix_source_PRODDB.sh
```

## Expected Output
```
[INFO] Connecting to source: temandin-oravm-vm01
[INFO] Enabling supplemental logging on ORADB01...
[INFO] ALTER DATABASE ADD SUPPLEMENTAL LOG DATA ... done
[INFO] ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (PRIMARY KEY) COLUMNS ... done
[INFO] Switching logfile...
[INFO] Verifying supplemental logging...
[PASS] SUPPLEMENTAL_LOG_DATA_MIN = YES
[PASS] SUPPLEMENTAL_LOG_DATA_PK  = YES
[INFO] fix_source_PRODDB.sh completed successfully.
```

## Rollback / Undo
To disable supplemental logging (only if required — disabling during migration causes data loss):
```sql
-- Connect as SYSDBA on source
ALTER DATABASE DROP SUPPLEMENTAL LOG DATA;
```
> **Warning:** Do not disable supplemental logging while ZDM migration is in progress.
```

---

### Iteration Required

After resolving the above issues:

1. ✅ Re-run discovery to verify fixes:
   ```bash
   ./zdm_orchestrate_discovery.sh
   ```

2. ✅ Save updated discovery files to:
   `Artifacts/Phase10-Migration/ZDM/PRODDB/Step2/Verification/`

3. ✅ Update Issue Resolution Log with resolution notes

4. 🔲 If new issues found, repeat Step 2

5. 🔲 When all issues resolved, proceed to Step 3

---

*This is an example output. Actual results will vary based on your discovery findings.*
