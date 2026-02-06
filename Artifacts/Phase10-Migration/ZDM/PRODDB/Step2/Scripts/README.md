# Step 2 Scripts - PRODDB Migration

## Overview

This directory contains remediation scripts for issues identified in the Discovery Summary.

## Scripts

| Script | Purpose | Run On |
|--------|---------|--------|
| `fix_oci_config.sh` | Configure OCI CLI for zdmuser | ZDM Server |
| `verify_target_db_name.sh` | Check for database name conflicts | Target Server |
| `check_db_link.sh` | Analyze SYS_HUB database link | Source Server |

## Usage

### 1. Fix OCI Configuration (ZDM Server)

**Priority:** 🔴 Critical

```bash
# SSH to ZDM server
ssh azureuser@tm-vm-odaa-oracle-jumpbox

# Copy script to server (or run directly via SSH)
# Run with sudo
sudo ./fix_oci_config.sh
```

**Required Information:**
- OCI User OCID
- OCI Tenancy OCID
- OCI Region (e.g., uk-london-1)
- API Key Fingerprint
- API Key File Path (default: /home/zdmuser/.oci/odaa.pem)

### 2. Verify Target Database Name (Target Server)

**Priority:** 🔴 Critical

```bash
# SSH to target server
ssh opc@tmodaauks-rqahk1

# Run script
./verify_target_db_name.sh oradb01

# Or check alternative names
./verify_target_db_name.sh oradb01_oda
```

**Expected Output:**
- If conflict: Script exits with code 1 and shows removal/rename options
- If no conflict: Script exits with code 0, safe to proceed

### 3. Check Database Link (Source Server)

**Priority:** 🟡 Recommended

```bash
# SSH to source server
ssh oracle@temandin-oravm-vm01

# Or as admin user with sudo
ssh temandin@temandin-oravm-vm01
sudo -u oracle ./check_db_link.sh
```

**Expected Output:**
- Database link details
- Connectivity test result
- List of dependencies (if any)
- Recommended post-migration action

## Verification

After running remediation scripts, verify the fixes:

```bash
# Verify OCI configuration
ssh azureuser@tm-vm-odaa-oracle-jumpbox "sudo -u zdmuser oci os ns get"

# Verify target database name is available
ssh opc@tmodaauks-rqahk1 "sudo -u oracle srvctl config database -d oradb01_oda"
# Should return: "Database oradb01_oda does not exist"
```

## Issue Resolution Workflow

```
1. Run remediation script
         ↓
2. Verify fix was successful
         ↓
3. Update Issue-Resolution-Log-PRODDB.md
         ↓
4. Re-run discovery if needed
         ↓
5. Save verification output to Step2/Verification/
         ↓
6. Proceed to Step 3 when all critical issues resolved
```

---

*Generated for PRODDB Migration to Oracle Database@Azure*
