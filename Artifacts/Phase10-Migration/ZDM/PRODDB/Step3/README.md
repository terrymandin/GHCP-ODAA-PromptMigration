# PRODDB Migration to Oracle Database@Azure

## Overview

This directory contains all migration artifacts for the PRODDB database migration from on-premises Oracle to Oracle Database@Azure using Zero Downtime Migration (ZDM).

| Property | Value |
|----------|-------|
| **Source Database** | ORADB01 (oradb01) |
| **Source Host** | temandin-oravm-vm01 (10.1.0.10) |
| **Target Platform** | Oracle Database@Azure (Exadata 2-node RAC) |
| **Target Host** | tmodaauks-rqahk1 (10.0.1.160) |
| **Migration Type** | ONLINE_PHYSICAL (Minimal Downtime) |
| **Expected Downtime** | 15-30 minutes (switchover only) |
| **Database Size** | ~2.6 GB |

---

## Generated Artifacts

| File | Description |
|------|-------------|
| [README.md](README.md) | This file - overview and quick start |
| [ZDM-Migration-Runbook-PRODDB.md](ZDM-Migration-Runbook-PRODDB.md) | Step-by-step installation and configuration guide |
| [zdm_migrate_PRODDB.rsp](zdm_migrate_PRODDB.rsp) | ZDM response file with all parameters |
| [zdm_commands_PRODDB.sh](zdm_commands_PRODDB.sh) | Ready-to-execute migration commands |

---

## Prerequisites Checklist

Before starting the migration, ensure the following are complete:

### OCI Configuration (Required)

- [ ] **OCI Tenancy OCID** - Obtain from OCI Console → Tenancy Details
- [ ] **OCI User OCID** - Obtain from OCI Console → User Settings
- [ ] **OCI API Key Fingerprint** - Obtain from OCI Console → API Keys
- [ ] **OCI Compartment OCID** - Obtain from OCI Console → Identity → Compartments
- [ ] **Target Database OCID** - Obtain from OCI Console → Databases → DB Details
- [ ] **OCI CLI configured for zdmuser** - Run `oci os ns get` to verify

### Passwords (Set at Runtime - Never Store)

- [ ] **SOURCE_SYS_PASSWORD** - Source Oracle SYS password
- [ ] **TARGET_SYS_PASSWORD** - Target Oracle SYS password
- [ ] **SOURCE_TDE_WALLET_PASSWORD** - TDE wallet password (source has TDE enabled)

### Access Verification

- [ ] SSH access to ZDM server as `azureuser`
- [ ] SSH from ZDM to source (10.1.0.10) - Port 22 ✅
- [ ] SSH from ZDM to target (10.0.1.160) - Port 22 ✅
- [ ] Oracle listener connectivity to source - Port 1521 ✅
- [ ] Oracle listener connectivity to target - Port 1521 ✅

### Source Database Status

- [x] ARCHIVELOG mode enabled
- [x] Force Logging enabled
- [x] Supplemental Logging enabled (MIN + PK)
- [x] TDE wallet configured (AUTOLOGIN)
- [x] Password file exists

---

## Quick Start Guide

### Step 1: Login to ZDM Server

```bash
# SSH as admin user
ssh azureuser@tm-vm-odaa-oracle-jumpbox

# Switch to zdmuser
sudo su - zdmuser
```

### Step 2: Clone Repository and Navigate to Artifacts

```bash
# Clone your fork (if not already done)
git clone https://github.com/<your-fork>/GHCP-ODAA-PromptMigration.git
cd GHCP-ODAA-PromptMigration/Artifacts/Phase10-Migration/ZDM/PRODDB/Step3

# Or if already cloned, pull latest
cd ~/GHCP-ODAA-PromptMigration
git pull
cd Artifacts/Phase10-Migration/ZDM/PRODDB/Step3
```

### Step 3: Initialize Environment (First Time Only)

```bash
# Make script executable
chmod +x zdm_commands_PRODDB.sh

# Run initialization
./zdm_commands_PRODDB.sh init
```

This creates:
- `~/creds/` directory for temporary password files
- `~/zdm_oci_env.sh` template for OCI environment variables

### Step 4: Configure OCI Environment Variables

Edit the OCI environment file with your actual OCIDs:

```bash
vi ~/zdm_oci_env.sh
```

Set the following values:
```bash
export TARGET_TENANCY_OCID="ocid1.tenancy.oc1..your-tenancy"
export TARGET_USER_OCID="ocid1.user.oc1..your-user"
export TARGET_FINGERPRINT="aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99"
export TARGET_COMPARTMENT_OCID="ocid1.compartment.oc1..your-compartment"
export TARGET_DATABASE_OCID="ocid1.database.oc1..your-database"
```

Then source the file:
```bash
source ~/zdm_oci_env.sh
```

### Step 5: Set Password Environment Variables

```bash
# Securely enter passwords (not visible while typing)
read -sp "Enter SOURCE_SYS_PASSWORD: " SOURCE_SYS_PASSWORD; echo; export SOURCE_SYS_PASSWORD
read -sp "Enter TARGET_SYS_PASSWORD: " TARGET_SYS_PASSWORD; echo; export TARGET_SYS_PASSWORD
read -sp "Enter SOURCE_TDE_WALLET_PASSWORD: " SOURCE_TDE_WALLET_PASSWORD; echo; export SOURCE_TDE_WALLET_PASSWORD
```

### Step 6: Create Password Files

```bash
./zdm_commands_PRODDB.sh create-creds
```

### Step 7: Run Evaluation (Recommended First)

```bash
./zdm_commands_PRODDB.sh eval
```

Review the evaluation output before proceeding.

### Step 8: Execute Migration

```bash
./zdm_commands_PRODDB.sh migrate
```

### Step 9: Monitor Progress

```bash
# Get the job ID from the migrate output, then monitor:
./zdm_commands_PRODDB.sh status <JOB_ID>
```

### Step 10: Complete Switchover (After Pause)

Migration will pause at `ZDM_SWITCHOVER_SRC` for validation. When ready:

```bash
./zdm_commands_PRODDB.sh resume <JOB_ID>
```

### Step 11: Post-Migration Cleanup

```bash
# Clean up password files
./zdm_commands_PRODDB.sh cleanup-creds
```

---

## Migration Workflow Summary

```
┌─────────────────────────────────────────────────────────────┐
│                    PRODDB Migration Workflow                 │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Login: ssh azureuser@ZDM_HOST → sudo su - zdmuser       │
│                          ↓                                   │
│  2. Initialize: ./zdm_commands_PRODDB.sh init                │
│                          ↓                                   │
│  3. Configure: Edit ~/zdm_oci_env.sh with OCIDs             │
│                          ↓                                   │
│  4. Source: source ~/zdm_oci_env.sh                         │
│                          ↓                                   │
│  5. Set Passwords: read -sp ... (secure entry)              │
│                          ↓                                   │
│  6. Create Creds: ./zdm_commands_PRODDB.sh create-creds     │
│                          ↓                                   │
│  7. Evaluate: ./zdm_commands_PRODDB.sh eval                 │
│                          ↓                                   │
│  8. Migrate: ./zdm_commands_PRODDB.sh migrate               │
│                          ↓                                   │
│  9. [PAUSE at ZDM_SWITCHOVER_SRC - Validate Data Guard]     │
│                          ↓                                   │
│  10. Resume: ./zdm_commands_PRODDB.sh resume <JOB_ID>       │
│                          ↓                                   │
│  11. Validate: Run post-migration checks                     │
│                          ↓                                   │
│  12. Cleanup: ./zdm_commands_PRODDB.sh cleanup-creds        │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Important Notes

### Security Considerations

- ⚠️ **Never commit passwords** to the repository
- ⚠️ Password files in `~/creds/` are temporary - delete after migration
- ⚠️ OCI API keys should have minimal required permissions
- ⚠️ Use `read -sp` for password entry (passwords not echoed)

### Rollback Information

The migration creates a Data Guard standby on the target. If issues occur:

1. **Before Switchover:** Simply abort the migration; source remains primary
2. **After Switchover:** Switchback to source is possible via Data Guard

See the Runbook for detailed rollback procedures.

### Support Contacts

| Role | Contact |
|------|---------|
| DBA Team | _______________ |
| Network Team | _______________ |
| Oracle Support | My Oracle Support (MOS) |

---

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| OCI authentication fails | Verify fingerprint matches, check API key permissions |
| SSH connection refused | Verify SSH keys, check firewall/NSG rules |
| ZDM service not running | Run `zdmservice status` and restart if needed |
| Password validation fails | Ensure environment variables are exported |

### Log Locations

| Log Type | Location |
|----------|----------|
| ZDM Logs | `$ZDM_HOME/logs/` |
| Job Logs | `$ZDM_BASE/chkbase/<job_id>/` |
| Source Alert Log | `/u01/app/oracle/diag/rdbms/oradb01/oradb01/trace/alert_oradb01.log` |

---

## Next Steps After Migration

1. ✅ Verify application connectivity to new database
2. ✅ Update connection strings in applications
3. ✅ Review and reconfigure database links (SYS_HUB)
4. ✅ Configure backup schedules on target
5. ✅ Update monitoring and alerting
6. ✅ Document DNS/network changes
7. ✅ Decommission source database (after validation period)

---

*Generated: February 5, 2026*  
*ZDM Migration Planning - Step 3*
