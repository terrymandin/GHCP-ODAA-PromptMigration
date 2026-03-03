# README: verify_fixes.sh

## Purpose
Verifies all required actions from the ORADB Discovery Summary are resolved before proceeding to Step 3 (Generate Migration Artifacts). Runs automated checks and writes a structured `Verification-Results-ORADB.md` file for committing to the repository.

## Target Server
**ZDM server** — `tm-vm-odaa-oracle-jumpbox` (10.1.0.8)  
**Run as:** `zdmuser`

## Prerequisites
- [ ] `create_oci_bucket.sh` has been run (Issue 1)
- [ ] `zdm-env.md` updated with `OCI_OSS_NAMESPACE` and `OCI_OSS_BUCKET_NAME`
- [ ] `verify_oci_cli_zdmuser.sh` has been run (Issue 2)
- [ ] `purge_source_archivelogs.sh` has been run if source disk was at ≥80% (Issue 3)
- [ ] SSH key `~/.ssh/odaa.pem` exists with permissions `600` (for SSH to source and target)
- [ ] SSH key `~/.ssh/zdm.pem` exists with permissions `600` (not used by this script directly)

## Environment Variables
| Variable | Description | Value |
|----------|-------------|-------|
| `DATABASE_NAME` | Database identifier | `ORADB` |
| `ORACLE_SID` | Oracle SID for log naming | `oradb` |
| `SOURCE_HOST` | Source server IP | `10.1.0.11` |
| `SOURCE_SSH_USER` | SSH user for source | `azureuser` |
| `SOURCE_SSH_KEY` | SSH key for source and target | `~/.ssh/odaa.pem` |
| `TARGET_HOST` | Target ODAA node 1 IP | `10.0.1.160` |
| `TARGET_SSH_USER` | SSH user for target | `opc` |
| `OCI_CONFIG_PATH` | OCI CLI config | `~/.oci/config` |
| `OCI_REGION` | OCI region | `uk-london-1` |
| `SOURCE_DISK_WARN_PCT` | Source disk warning threshold | `85` |
| `ZDM_DISK_WARN_PCT` | ZDM disk warning threshold | `90` |

## What It Does

Runs 5 automated checks and produces a results file:

| # | Check | Type | Passes When |
|---|-------|------|-------------|
| 1 | OCI Object Storage bucket configured and accessible | Required | `oci os bucket list` returns a bucket matching `zdm-migration-oradb*` |
| 2 | OCI CLI authenticated for `zdmuser` | Required | `oci iam region list` returns `uk-london-1` without error |
| 3 | Source root filesystem disk usage | Recommended | Source `/` is below 85% utilization |
| 4 | ZDM root filesystem disk usage | Recommended | ZDM `/` is below 90% utilization |
| 5 | ZDM → Target SSH connectivity | Recommended | `ssh opc@10.0.1.160 echo ok` returns `ok` (cross-network requires ExpressRoute) |

After all checks, writes:
- `Step2/Verification-Results-ORADB.md` — structured Markdown results table for repo commit
- `Step2/Verification/verify_fixes_<timestamp>.log` — full execution log (retained on ZDM server)

## How to Run
```bash
# Switch to zdmuser on ZDM server
sudo su - zdmuser

cd ~/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts
chmod +x verify_fixes.sh
./verify_fixes.sh
```

## Expected Output (all passing)
```
==============================================================
  ZDM Step 2: Final Verification — ORADB
  ...
══════════════════════════════════════════════════════════════
  VERIFICATION SUMMARY — ORADB
══════════════════════════════════════════════════════════════

  Required Actions (must be PASS before Step 3):
  ────────────────────────────────────────────────
  Issue 1 — OCI OSS bucket configured      : ✅ PASS
            Bucket 'zdm-migration-oradb-20260303' exists in uk-london-1
  Issue 2 — OCI CLI auth for zdmuser        : ✅ PASS
            oci iam region list succeeded for region 'uk-london-1'

  Recommended Items:
  ────────────────────────────────────────────────
  Issue 3 — Source disk space               : ✅ PASS
            Root disk at 75%; free: 8G
  Issue 4 — ZDM disk space                  : ✅ PASS
            ZDM root disk at 45%; free: 24G
  Issue 5 — ZDM → Target SSH connectivity   : ✅ PASS
            SSH to 10.0.1.160 as opc succeeded

  ────────────────────────────────────────────────
  Required Pass : 2/2
  Failures      : 0
  Warnings      : 0
  Proceed to Step 3: ✅ YES — all 2 required actions resolved
══════════════════════════════════════════════════════════════

  📄 Verification results written to:
  /home/zdmuser/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Verification-Results-ORADB.md
```

## After Running — Commit Results to Repo

The script prints the exact commands. From your developer workstation:

```bash
# 1. Copy results file from ZDM server to repo
scp -i <zdm-admin-key> \
  azureuser@10.1.0.8:/home/zdmuser/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Verification-Results-ORADB.md \
  Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Verification-Results-ORADB.md

# 2. Commit to repo
git add Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Verification-Results-ORADB.md
git commit -m "Step2 verification passed: all required actions resolved for ORADB"
```

## Exit Codes
| Code | Meaning |
|------|---------|
| `0` | All required actions (Issues 1 & 2) are PASS — safe to proceed to Step 3 |
| `1` | One or more required actions FAILED — resolve and re-run |

> **Note:** Warnings (e.g., source disk at 75–84%, target SSH delay) do not cause a non-zero exit. Address warnings before starting migration, but they do not block Step 3 artifact generation.

## Manual Decision Items (not script-checkable)

These must be confirmed in the Migration Questionnaire before running Step 3:

| Item | Where to Record |
|------|----------------|
| Target `DB_UNIQUE_NAME` confirmed (no conflict with `oradb01m`) | Migration-Questionnaire-ORADB.md Section A.4 |
| Target PDB name for `PDB1` decided | Migration-Questionnaire-ORADB.md Section A.3 |
| `SYS.SYS_HUB` DB link reviewed (keep/drop decision) | Issue-Resolution-Log-ORADB.md Issue 6 |

## Rollback / Undo
This script is read-only (no changes made to any database or Oracle configuration). No rollback is required.
