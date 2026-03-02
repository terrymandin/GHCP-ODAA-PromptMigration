# README: verify_fixes.sh

## Purpose
Consolidated verification script that checks all three critical blockers from the ORADB Discovery Summary have been resolved, plus additional recommended sanity checks. Saves results to `Step2/Verification/` as a timestamped log for Step 3 reference.

---

## Target Server
**ZDM Server** — run as `zdmuser` on `tm-vm-odaa-oracle-jumpbox` (10.1.0.8).  
The script connects to the **source server** for database checks and runs OCI CLI checks locally on the ZDM server.

---

## Prerequisites

| Requirement | Detail |
|-------------|--------|
| Run as | `zdmuser` on the ZDM server |
| Issues 1–3 resolved | Run all three fix scripts before this script |
| SSH key (source) | `~/.ssh/iaas.pem` must exist with permissions `600` |
| OCI config | `~/.oci/config` must exist (created by `fix_oci_config.sh`) |

---

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `SOURCE_HOST` | Source DB server IP | `10.1.0.11` |
| `SOURCE_SSH_USER` | Admin SSH user on source | `azureuser` |
| `SOURCE_SSH_KEY` | SSH key path (zdmuser) | `~/.ssh/iaas.pem` |
| `ORACLE_USER` | Oracle software OS user | `oracle` |
| `ORACLE_SID` | Oracle SID on source | `oradb` |
| `ORACLE_HOME` | Oracle Home on source | `/u01/app/oracle/product/12.2.0/dbhome_1` |
| `PDB_NAME` | PDB name to verify | `PDB1` |
| `ZDM_HOME` | ZDM installation home | `/u01/app/zdmhome` |
| `TARGET_DATABASE_OCID` | Target DB OCID for OCI validation | *(from zdm-env.md)* |

---

## What It Does

Runs 8 checks and reports PASS / FAIL / WARN for each:

| # | Check | Related Issue |
|---|-------|---------------|
| 1 | SSH connectivity to source | Pre-requisite |
| 2 | PDB1 is OPEN (READ WRITE) | ❌ Issue 1 |
| 3 | ALL COLUMNS + PK supplemental logging enabled | ❌ Issue 2 |
| 4 | OCI CLI configured and `oci os ns get` succeeds | ❌ Issue 3 |
| 5 | Source database is in ARCHIVELOG mode | Sanity re-check |
| 6 | Source root filesystem free space | ⚡ Issue 4 |
| 7 | ZDM server root filesystem free space | ⚡ Issue 5 |
| 8 | ZDM service is running | Pre-requisite |

All output is tee'd to `Step2/Verification/verify_fixes_<TIMESTAMP>.log`.  
The script exits with code `1` if any FAIL check is detected.

---

## How to Run

```bash
# Switch to zdmuser on the ZDM server
sudo su - zdmuser

# Navigate to scripts directory
cd ~/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts

# Make executable and run
chmod +x verify_fixes.sh
./verify_fixes.sh
```

---

## Expected Output (all passing)

```
============================================================
  verify_fixes.sh — ORADB Step 2 Verification
============================================================

  Timestamp : 2026-03-02 22:30:00 UTC
  Running as: zdmuser on tm-vm-odaa-oracle-jumpbox
  Log file  : /home/zdmuser/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Verification/verify_fixes_20260302_223000.log

--- Check 1 of 8: SSH connectivity to source (10.1.0.11) ---
  ✅ PASS: SSH to azureuser@10.1.0.11 using ~/.ssh/iaas.pem

--- Check 2 of 8: PDB1 open state (Issue 1) ---
  PDB PDB1 OPEN_MODE: 'READ WRITE'
  ✅ PASS: PDB1 is OPEN (READ WRITE) — Issue 1 resolved

--- Check 3 of 8: Supplemental logging (Issue 2) ---
  SUPPLEMENTAL_LOG_DATA_ALL: 'YES'
  ✅ PASS: ALL COLUMNS supplemental logging is enabled — Issue 2 resolved
  SUPPLEMENTAL_LOG_DATA_PK:  'YES'
  ✅ PASS: PRIMARY KEY supplemental logging is enabled

--- Check 4 of 8: OCI CLI config and connectivity (Issue 3) ---
  ✅ PASS: ~/.oci/config exists
  ✅ PASS: OCI CLI connectivity confirmed — Object Storage namespace: axxxxxxxxxxx
  ⚠️  ACTION: Record namespace 'axxxxxxxxxxx' in Migration Questionnaire Section C.

--- Check 5 of 8: Source ARCHIVELOG mode (sanity) ---
  ✅ PASS: Source database is in ARCHIVELOG mode ✅

--- Check 6 of 8: Source root disk free space ---
  Source root free space: 6 GB
  ⚠️  WARN: Source root filesystem has only 6 GB free — monitor archive log growth during migration

--- Check 7 of 8: ZDM server root disk free space ---
  ZDM root free space: 24 GB
  ⚠️  WARN: ZDM root filesystem has only 24 GB free — ZDM recommends 50+ GB

--- Check 8 of 8: ZDM service status ---
  ✅ PASS: ZDM service is responding (zdmcli query job succeeded)

============================================================
  Verification Summary
============================================================

  ✅ Passed   : 8
  ❌ Failed   : 0
  ⚠️  Warnings: 2

  🎉 All critical checks PASSED.
     All three blockers are resolved. You may proceed to Step 3.

  Next step: Step3-Generate-Migration-Artifacts.prompt.md

  Verification log saved to:
  /home/zdmuser/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Verification/verify_fixes_20260302_223000.log
```

---

## Interpretation

| Result | Meaning |
|--------|---------|
| All ✅ PASS, no ❌ FAIL | Ready to proceed to Step 3 |
| Any ❌ FAIL | Fix the failing issue and re-run this script |
| ⚠️ WARN only | Proceed with caution; warnings are non-blocking but should be noted |

---

## Rollback / Undo

This script is read-only (verification only). It makes no changes to the source database, ZDM configuration, or OCI settings. It is safe to run multiple times.

---

*Consolidated verification — ORADB Step 2 remediation*  
*Run after all three fix scripts: fix_open_pdb1.sh, fix_supplemental_logging.sh, fix_oci_config.sh*
