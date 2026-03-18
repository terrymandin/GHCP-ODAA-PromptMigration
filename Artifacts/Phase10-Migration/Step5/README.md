# Step 5 Migration Artifacts

Generated: 2026-03-18  
Scope: Source `POCAKV` on `10.200.1.12` to Target `POCAKV_ODAA` on `10.200.0.250` using ZDM from `zdmhost`

## 1. Migration Overview

- Source host/database: `factvmhost` (`10.200.1.12`) / `POCAKV`
- Target host/database: `vmclusterpoc-ytlat1` (`10.200.0.250`) / `POCAKV_ODAA`
- Pinned source Oracle home/SID: `/u01/app/oracle/product/19.0.0/dbhome_1` / `POCAKV`
- Pinned target Oracle home/SID: `/u02/app/oracle/product/19.0.0.0/dbhome_1` / `POCAKV1`
- ZDM host/home: `zdmhost` / `/mnt/app/zdmhome`
- Planned migration method: `ONLINE_PHYSICAL` (default; adjust if your approved method differs)
- Expected downtime: `[TBD from migration questionnaire]`
- Cutover window: `[TBD from change plan]`
- Key contacts: `[TBD DBA lead / Infra lead / App owner]`

## 2. Prerequisites Checklist

### Core Migration Prerequisites

- [ ] Confirm migration objective and final method are signed off (questionnaire section 1)
- [ ] Confirm downtime, RPO, and go/no-go owner are signed off
- [ ] Confirm source and target patch levels captured in evidence
- [ ] Confirm ARCHIVELOG and FORCE LOGGING state on source database
- [ ] Confirm target instance pinning is `POCAKV1` for all scripts and commands
- [ ] Confirm rollback runbook and authority path are approved
- [ ] Confirm application smoke test and validation checklist are prepared
- [ ] Confirm `~/zdm_oci_env.sh` is populated on ZDM host before running eval/migrate
- [ ] Confirm password environment variables are set in session (do not hardcode)

### OCI Identifiers Required

- [ ] `TARGET_TENANCY_OCID`
- [ ] `TARGET_USER_OCID`
- [ ] `TARGET_FINGERPRINT`
- [ ] `TARGET_COMPARTMENT_OCID`
- [ ] `TARGET_DATABASE_OCID`
- [ ] `TARGET_OBJECT_STORAGE_NAMESPACE` (only for `OFFLINE_PHYSICAL` or object storage staging)

OCI CLI is optional and not required for Step 5 artifact usage.

### Password Inputs Required At Runtime

- [ ] `SRC_SYS_PASSWORD`
- [ ] `TGT_SYS_PASSWORD`
- [ ] `TGT_TDE_PASSWORD` (if TDE wallet password differs or required by policy)

### Step 4 Blockers Checklist

Verification file was not found at `Artifacts/Phase10-Migration/Step4/Verification/Verification-Results.md`, so blockers remain unchecked by design.

- [ ] Blocker 1: source/target SQL*Plus version evidence captured
- [ ] Blocker 2: ZDM version/build evidence captured
- [ ] Blocker 3: SSH auth strategy validated and documented

Blocker note: OCI config is needed for ZDM to authenticate to OCI; ZDM uses its own OCI SDK with credentials from the RSP file.

### Recommended (Issues 4-5) Follow-up

- ⚠️ Revalidate ZDM host disk headroom for migration runtime logs/temp
- ⚠️ Confirm target SID pinning (`POCAKV1`) in all migration-time commands

## 3. Generated Artifacts

- `README.md`: this checklist and quick-start guide
- `ZDM-Migration-Runbook.md`: end-to-end operational runbook
- `zdm_migrate.rsp`: ZDM response file template using environment variable placeholders
- `zdm_commands.sh`: helper CLI wrapper (`init`, `create-creds`, `cleanup-creds`, `eval`, `migrate`, `monitor`, `resume`, `abort`)

## 4. Quick Start Guide

Run all commands from a repository clone on the ZDM server.

```bash
# 1) SSH to ZDM server as admin user, then switch to zdmuser
ssh <ZDM_ADMIN_USER>@<zdm-server>
sudo su - zdmuser

# 2) Go to Step5 artifacts directory
cd /path/to/repo/Artifacts/Phase10-Migration/Step5

# 3) First-time setup
chmod +x zdm_commands.sh
./zdm_commands.sh init

# 4) Populate OCI values and source environment
vi ~/zdm_oci_env.sh
source ~/zdm_oci_env.sh

# 5) Set passwords in current shell (not in files)
export SRC_SYS_PASSWORD='***'
export TGT_SYS_PASSWORD='***'
export TGT_TDE_PASSWORD='***'   # if required

# 6) Create credential files
./zdm_commands.sh create-creds

# 7) Run evaluation
./zdm_commands.sh eval

# 8) Execute migration
./zdm_commands.sh migrate

# 9) Monitor / resume / abort
./zdm_commands.sh monitor <job_id>
./zdm_commands.sh resume <job_id>
./zdm_commands.sh abort <job_id>

# 10) Cleanup credentials after completion
./zdm_commands.sh cleanup-creds
```

## 5. Important Notes

- Security:
  - Do not commit OCI OCIDs, private key paths, or passwords to git.
  - Keep `~/creds` permission at `700` and password files at `600`.
  - Prefer ephemeral environment variables for secrets.
- Rollback:
  - Follow rollback section in `ZDM-Migration-Runbook.md`.
  - Keep source write-stop and cutover checkpoints clearly recorded.
- ZDM Version:
  - Discovery flagged version as undetermined (`PRCG-1027` for `-version`), so run Phase 0 in runbook before migration.
- Support:
  - Oracle ZDM docs: <https://docs.oracle.com/en/database/oracle/zero-downtime-migration/index.html>
  - My Oracle Support: search "Zero Downtime Migration"
