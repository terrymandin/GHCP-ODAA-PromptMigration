# README: verify_fixes.sh

## Purpose
Runs a quick automated check of all three Step 2 blockers after the remediation scripts have been applied:
- **Issue 1** — PDB1 is `READ WRITE` on the source database
- **Issue 2** — `ALL COLUMNS` supplemental logging is enabled on the source database
- **Issue 3** — OCI CLI authenticates successfully as `zdmuser` on the ZDM server

Prints a pass/fail summary and indicates which fix scripts to re-run if any check fails.

---

## Target Server
**ZDM server** — run directly on `tm-vm-odaa-oracle-jumpbox` as `zdmuser`. The script uses SSH to reach the source server for the Oracle checks.

| Field | Value |
|-------|-------|
| Executed on | ZDM server: `tm-vm-odaa-oracle-jumpbox` (10.1.0.8) |
| Run as user | `zdmuser` |
| SSH to source | `azureuser@10.1.0.11` via `/home/zdmuser/iaas.pem` |

---

## Prerequisites

| Requirement | Detail |
|-------------|--------|
| All three `fix_*.sh` scripts attempted | Run `fix_pdb1_open.sh`, `fix_supplemental_logging.sh`, and `fix_oci_config_zdmuser.sh` first |
| ZDM server SSH connectivity to source | `ssh -i /home/zdmuser/iaas.pem azureuser@10.1.0.11` must work |
| OCI API private key uploaded | `/home/zdmuser/.oci/oci_api_key.pem` must exist (for Check 3) |

---

## Environment Variables

| Variable | Default Value | Description |
|----------|---------------|-------------|
| `SOURCE_HOST` | `10.1.0.11` | IP address of the source Oracle database server |
| `SOURCE_SSH_USER` | `azureuser` | Admin SSH user on the source server |
| `SOURCE_SSH_KEY` | `/home/zdmuser/iaas.pem` | Path to SSH private key for the source server |
| `ORACLE_USER` | `oracle` | OS user that owns the Oracle installation |
| `ORACLE_HOME` | `/u01/app/oracle/product/12.2.0/dbhome_1` | Oracle Home on the source server |
| `ORACLE_SID` | `oradb` | Oracle SID of the source CDB |

---

## What It Does

1. **Check 1** — SSHes to the source server and queries `V$PDBS.open_mode` for PDB1. Passes if value is `READ WRITE`.
2. **Check 2** — SSHes to the source server and queries `V$DATABASE.supplemental_log_data_all`. Passes if value is `YES`.
3. **Check 3** — Runs `oci os ns get` locally (as the current user on ZDM server). Passes if the command returns a valid namespace JSON response.
4. **Summary** — Prints `PASS/FAIL` count and, if all pass, confirms readiness to proceed to Step 3.

---

## How to Run

```bash
# On ZDM server as zdmuser:
cd /home/zdmuser
chmod +x verify_fixes.sh
./verify_fixes.sh
```

---

## Expected Output (all checks passing)

```
================================================================
 verify_fixes.sh — Step 2 Blocker Verification
 Source: 10.1.0.11  SID: oradb
 Date:   2026-03-02 22:00:00 UTC
================================================================

---- Check 1: PDB1 Open Mode -----------------------------------
   PDB1 open_mode: READWRITE
   ✅ PASS — PDB1 is READ WRITE

---- Check 2: ALL COLUMNS Supplemental Logging -----------------
   supplemental_log_data_all: YES
   ✅ PASS — ALL COLUMNS supplemental logging is enabled

---- Check 3: OCI CLI Connectivity (as zdmuser) ----------------
   ✅ PASS — OCI CLI connectivity confirmed
   Object Storage Namespace: <your-namespace>

================================================================
 Summary
================================================================
   Passed: 3/3
   Failed: 0/3

   🎉 ALL BLOCKERS RESOLVED — ready to proceed to Step 3

   Next steps:
   1. Update Issue-Resolution-Log-ORADB.md with resolution notes
   2. Re-run source discovery and save to Step2/Verification/
   3. Run Step3-Generate-Migration-Artifacts.prompt.md
================================================================
```

---

## Expected Output (with failures)

```
   Failed: 2/3

   ❌ 2 blocker(s) remain — fix before proceeding to Step 3:
      • Issue 1: PDB1 open_mode = MOUNTED (expected READ WRITE)
      • Issue 3: OCI CLI connectivity failed
```

---

## Rollback / Undo

This script is read-only — it makes no changes and has no rollback requirement.

---

## Related Files

- `Issue-Resolution-Log-ORADB.md` — Update issue statuses based on this script's output
- `fix_pdb1_open.sh` + `README-fix_pdb1_open.md` — Fix for Check 1
- `fix_supplemental_logging.sh` + `README-fix_supplemental_logging.md` — Fix for Check 2
- `fix_oci_config_zdmuser.sh` + `README-fix_oci_config_zdmuser.md` — Fix for Check 3
