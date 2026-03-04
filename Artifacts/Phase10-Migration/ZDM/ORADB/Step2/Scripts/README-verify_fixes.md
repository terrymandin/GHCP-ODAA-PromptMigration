# README: verify_fixes.sh

## Purpose
Verifies that all Step 2 blockers for the ORADB migration have been resolved. Runs automated checks for each critical issue, writes a structured Markdown results file (`Verification-Results-ORADB.md`) to the `Step2/` directory for commit to the repo, and prints a `git commit` command to record progress. Must be run and all blockers must show ✅ PASS before proceeding to Step 3.

## Target Server
**ZDM server** — `tm-vm-odaa-oracle-jumpbox` (10.1.0.8)
Run as **`zdmuser`**.

## Prerequisites
The following issues should be fixed before running this script:
1. **fix_oci_cli_config.sh** complete (Issue 1 + Issue 6)
2. **fix_target_password_file.sh** complete (Issue 2)
3. **fix_open_target_db.sh** complete (Issue 3)
4. SSH key `~/.ssh/iaas.pem` in place for source connectivity
5. SSH key `~/.ssh/odaa.pem` in place for target connectivity

## Environment Variables
All values are hardcoded from `zdm-env.md`:

| Variable | Description | Value |
|----------|-------------|-------|
| `SOURCE_HOST` | Source DB server IP | `10.1.0.11` |
| `SOURCE_SSH_USER` | SSH user for source | `azureuser` |
| `SOURCE_SSH_KEY` | SSH key for source | `~/.ssh/iaas.pem` |
| `TARGET_HOST` | ODAA target IP | `10.0.1.160` |
| `TARGET_SSH_USER` | SSH user for target | `opc` |
| `TARGET_SSH_KEY` | SSH key for target | `~/.ssh/odaa.pem` |
| `ORACLE_USER` | Oracle OS user | `oracle` |
| `TARGET_DB_UNIQUE_NAME` | Target DB unique name | `oradb01` |
| `OCI_CONFIG_FILE` | OCI config path | `~/.oci/config` |
| `SOURCE_FREE_GB_THRESHOLD` | Minimum expected free GB on source | `10` |
| `ZDM_FREE_GB_THRESHOLD` | Minimum expected free GB on ZDM | `10` |

## What It Does

The script performs the following checks in sequence:

**Pre-check:** Prompts for Oracle Home suffix (1 or 2) to determine password file path.

**BLOCKER 1 — Target password file:**
- SSH to `opc@10.0.1.160`
- Check if `orapworadb01` exists in `${ORACLE_HOME}/dbs/`
- PASS = file found; FAIL = missing (run `fix_target_password_file.sh`)

**BLOCKER 2 — OCI CLI config:**
- Check `~/.oci/config` exists on ZDM server as `zdmuser`
- Run `oci os ns get` to test connectivity
- PASS = config valid and namespace returned; FAIL = config missing or connectivity fails

**BLOCKER 3 — Source SSH key:**
- SSH to `azureuser@10.1.0.11` using `~/.ssh/iaas.pem`
- Run `sudo -u oracle whoami` — must return `oracle`
- On failure, falls back to `odaa.pem` (with warning to update `zdm-env.md`)
- PASS = `iaas.pem` grants oracle access; FAIL = neither key works

**RECOMMENDATION 4 — Source disk space:**
- SSH to source, run `df -BG /` to get free GB on root
- WARN if below 10 GB threshold

**RECOMMENDATION 5 — ZDM server disk space:**
- Run `df -BG /` locally on ZDM server
- WARN if below 10 GB threshold

**Results file:** Writes `Verification-Results-ORADB.md` to `Step2/` with per-issue status table.

## How to Run
```bash
# 1. SSH to ZDM server and switch to zdmuser
ssh -i ~/.ssh/zdm.pem azureuser@10.1.0.8
sudo su - zdmuser

# 2. Run the script
cd ~/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts
bash verify_fixes.sh

# 3. Review output — all 3 blockers must show ✅ PASS

# 4. Commit results file (git command printed at end of script)
cd ~/Artifacts
git add Phase10-Migration/ZDM/ORADB/Step2/Verification-Results-ORADB.md
git commit -m "Step2 verification passed: all blockers resolved for ORADB"
git push
```

## Expected Output (all blockers resolved)
```
================================================================
SUMMARY
================================================================

  Blockers resolved:    3/3
  Total PASS:           3
  Total WARN:           0
  Total FAIL:           0

  BLOCKER 1 — Target password file:    PASS
  BLOCKER 2 — OCI CLI config:          PASS
  BLOCKER 3 — Source SSH key:          PASS
  RECOMMEND 4 — Source disk space:     WARN
  RECOMMEND 5 — ZDM disk space:        PASS

verify_fixes.sh completed.

  📄 Verification results written to: .../Step2/Verification-Results-ORADB.md

  Commit to repo when ready to proceed to Step 3:
    git add Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Verification-Results-ORADB.md
    git commit -m "Step2 verification passed: all blockers resolved for ORADB"

  ✅ All blockers resolved. Proceed to Step 3.
```

## Expected Output (with remaining failures)
Script exits with code `1` and prints which blockers still need remediation:
```
  ❌ 1 blocker(s) still unresolved. Fix issues and re-run verify_fixes.sh.
```

## Rollback / Undo
This script is read-only for all checks except writing `Verification-Results-ORADB.md` (safe to re-run). The results file is overwritten on each run.

---

## Proceeding to Step 3

Once `verify_fixes.sh` shows all 3 blockers as PASS and `Verification-Results-ORADB.md` is committed, run Step 3 with the following files attached:

| File | Path |
|------|------|
| Discovery Summary (Step 1) | `Artifacts/Phase10-Migration/ZDM/ORADB/Step1/Discovery-Summary-ORADB.md` |
| Migration Questionnaire (Step 1) | `Artifacts/Phase10-Migration/ZDM/ORADB/Step1/Migration-Questionnaire-ORADB.md` |
| Issue Resolution Log (Step 2) | `Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Issue-Resolution-Log-ORADB.md` |
| Verification Results (Step 2) | `Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Verification-Results-ORADB.md` |
| ZDM Environment Config | `prompts/Phase10-Migration/ZDM/zdm-env.md` |
