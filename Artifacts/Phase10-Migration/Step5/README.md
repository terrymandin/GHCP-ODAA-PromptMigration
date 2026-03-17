# Step 5 Migration Artifacts - POCAKV to POCAKV_ODAA

Generated: 2026-03-17

This folder contains generated Step 5 migration artifacts for Oracle Zero Downtime Migration (ZDM).

## Migration Overview

- Source host: `10.200.1.12` (`factvmhost`)
- Target host: `10.200.0.250` (`vmclusterpoc-ytlat1`)
- ZDM host: `zdmhost`
- Source database unique name: `POCAKV`
- Target database unique name: `POCAKV_ODAA`
- Source SID / home: `POCAKV` / `/u01/app/oracle/product/19.0.0/dbhome_1`
- Target SID / home: `POCAKV1` / `/u02/app/oracle/product/19.0.0.0/dbhome_1`
- Planned migration method default: `ONLINE_PHYSICAL`
- Expected downtime: `[TBD in cutover plan]`

## Prerequisites Checklist

- [ ] Step 4 verification summary available and reviewed (`Artifacts/Phase10-Migration/Step4/Verification/Verification-Results.md` or `Verification-Results.md`)
- [ ] OCI identifiers collected and exported on ZDM host (`TARGET_TENANCY_OCID`, `TARGET_USER_OCID`, `TARGET_FINGERPRINT`, `TARGET_COMPARTMENT_OCID`, `TARGET_DATABASE_OCID`)
- [ ] Optional Object Storage namespace collected (required for `OFFLINE_PHYSICAL`)
- [ ] Password environment variables set at runtime (`SOURCE_SYS_PASSWORD`, `TARGET_SYS_PASSWORD`, optional `SOURCE_TDE_WALLET_PASSWORD`)
- [ ] SSH from ZDM host to source/target validated with selected auth strategy
- [ ] Network/listener/connectivity checks completed

Step 4 blockers checklist (verification file not provided at generation time):

- [ ] Issue 1: source/target SQL*Plus version evidence captured
- [ ] Issue 2: ZDM version/build evidence captured
- [ ] Issue 3: SSH auth strategy validated

Recommended items:

- [ ] Issue 4: ZDM disk headroom validated for migration runtime
- [ ] Issue 5: target SID pinning (`POCAKV1`) validated end-to-end

Blocker note:

- OCI config is needed for ZDM to authenticate to OCI; ZDM uses its own OCI SDK with credentials from the RSP file.

## Generated Artifacts

- `zdm_migrate_POCAKV.rsp`: ZDM response file template using environment-variable placeholders for OCI values
- `zdm_commands_POCAKV.sh`: executable helper script (`init`, `create-creds`, `cleanup-creds`, `eval`, `migrate`, `monitor`, `resume`, `abort`)
- `ZDM-Migration-Runbook-POCAKV.md`: detailed migration runbook

## Quick Start

Run from the repository clone on the jumpbox/ZDM server.

```bash
# 1) Login and switch user
ssh <ZDM_ADMIN_USER>@<zdm-host>
sudo su - zdmuser

# 2) Go to Step5 artifacts
cd <repo-root>/Artifacts/Phase10-Migration/Step5

# 3) First-time setup
chmod +x zdm_commands_POCAKV.sh
./zdm_commands_POCAKV.sh init

# 4) Populate OCI env file and load it
vi ~/zdm_oci_env.sh
source ~/zdm_oci_env.sh

# 5) Set passwords securely
read -sp "Enter SOURCE SYS password: " SOURCE_SYS_PASSWORD; echo; export SOURCE_SYS_PASSWORD
read -sp "Enter TARGET SYS password: " TARGET_SYS_PASSWORD; echo; export TARGET_SYS_PASSWORD

# 6) Create password files
./zdm_commands_POCAKV.sh create-creds

# 7) Evaluation run
./zdm_commands_POCAKV.sh eval

# 8) Migration run
./zdm_commands_POCAKV.sh migrate

# 9) Monitor jobs
./zdm_commands_POCAKV.sh monitor

# 10) Cleanup credentials when done
./zdm_commands_POCAKV.sh cleanup-creds
```

## Important Notes

- Generated artifacts are runtime-portable and do not require reading `zdm-env.md` on the jumpbox.
- No passwords are stored in scripts or in `.rsp` files.
- Keep `~/creds` permission at `700` and password files at `600`.
- Phase 0 update of ZDM is strongly recommended because Step 2 discovery did not capture a valid version command (`PRCG-1027` for `-version`).

## Conflict and Input Notes

- No value conflict was detected between Step 2/3/4 and `zdm-env.md` for host/SID/home/DB unique names.
- The requested Step 4 verification file was not present in the repo at generation time; checklist items remain unchecked pending execution of `verify_fixes.sh`.
