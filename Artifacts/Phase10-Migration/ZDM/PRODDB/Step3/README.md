# PRODDB Migration to Oracle Database@Azure

## Migration Overview

| Field | Value |
|-------|-------|
| **Source Database** | ORADB01 (oradb01) on temandin-oravm-vm01 |
| **Source Version** | Oracle 19c Enterprise Edition |
| **Target Environment** | Oracle Database@Azure Exadata (2-node RAC) |
| **Target Hosts** | tmodaauks-rqahk1, tmodaauks-rqahk2 |
| **Migration Method** | ONLINE_PHYSICAL (Data Guard-based) |
| **Expected Downtime** | Minutes (during switchover only) |
| **Database Size** | 1.92 GB |
| **Generated Date** | 2026-02-03 |

---

## Prerequisites Checklist

Complete these items before starting the migration:

### ⬜ OCI Configuration (Critical)

| Item | Status | Action Required |
|------|--------|-----------------|
| OCI Tenancy OCID | ⬜ | Obtain from OCI Console > Profile > Tenancy Details |
| OCI User OCID | ⬜ | Obtain from OCI Console > Profile > User Settings |
| OCI API Fingerprint | ⬜ | Obtain from OCI Console > Profile > API Keys |
| OCI Compartment OCID | ⬜ | Obtain from OCI Console > Identity > Compartments |
| Target DB System OCID | ⬜ | Obtain from OCI Console > Databases > Exadata DB Systems |
| Target Database OCID | ⬜ | Obtain from OCI Console > Databases > Databases |
| Object Storage Namespace | ⬜ | Obtain from OCI Console > Object Storage |

### ⬜ Password Requirements

| Password | Where to Set |
|----------|--------------|
| SOURCE_SYS_PASSWORD | Source database SYS password |
| TARGET_SYS_PASSWORD | Target database SYS password |
| SOURCE_TDE_WALLET_PASSWORD | TDE wallet password (required for migration) |

**Important:** Never hardcode passwords. Use environment variables as shown in the CLI commands script.

### ⬜ Issue Resolution (from Step2)

| Issue | Status | Required Action |
|-------|--------|-----------------|
| OCI CLI Configuration | ⬜ | Verify zdmuser OCI config or configure for azureuser |
| Disk Space (24 GB available) | ⬜ | Acceptable for 1.92 GB database - monitor during migration |
| Target Database Selection | ⬜ | Confirm target database unique name |
| SYS_HUB Database Link | ⬜ | Document decision for post-migration handling |

---

## Generated Artifacts

| File | Description | Usage |
|------|-------------|-------|
| [README.md](README.md) | This file - Quick start guide and overview | Reference |
| [ZDM-Migration-Runbook-PRODDB.md](ZDM-Migration-Runbook-PRODDB.md) | Step-by-step installation and configuration guide | Follow during migration |
| [zdm_migrate_PRODDB.rsp](zdm_migrate_PRODDB.rsp) | ZDM response file with all parameters | Used by ZDM CLI commands |
| [zdm_commands_PRODDB.sh](zdm_commands_PRODDB.sh) | Ready-to-execute migration commands | Execute for migration |

---

## Quick Start Guide

### Step 1: Set Environment Variables

```bash
# SSH to ZDM server as zdmuser (recommended)
ssh azureuser@tm-vm-odaa-oracle-jumpbox
sudo su - zdmuser

# Set required passwords (never hardcode these!)
read -sp "Enter Source SYS Password: " SOURCE_SYS_PASSWORD; echo
export SOURCE_SYS_PASSWORD

read -sp "Enter Target SYS Password: " TARGET_SYS_PASSWORD; echo
export TARGET_SYS_PASSWORD

read -sp "Enter TDE Wallet Password: " SOURCE_TDE_WALLET_PASSWORD; echo
export SOURCE_TDE_WALLET_PASSWORD
```

### Step 2: Update RSP File with OCI Details

Edit `zdm_migrate_PRODDB.rsp` and replace all placeholder values:
- `<YOUR_TENANCY_OCID>` → Your actual tenancy OCID
- `<YOUR_USER_OCID>` → Your actual user OCID
- `<YOUR_FINGERPRINT>` → Your API key fingerprint
- `<YOUR_COMPARTMENT_OCID>` → Your compartment OCID
- `<TARGET_DATABASE_OCID>` → Target database OCID
- `<OBJECT_STORAGE_NAMESPACE>` → Your OCI namespace

### Step 3: Run Evaluation

```bash
# Make script executable
chmod +x zdm_commands_PRODDB.sh

# Run evaluation (dry run)
./zdm_commands_PRODDB.sh eval
```

### Step 4: Execute Migration

```bash
# Start migration
./zdm_commands_PRODDB.sh migrate

# Monitor progress (note the job ID from output)
./zdm_commands_PRODDB.sh status <JOB_ID>
```

### Step 5: Complete Switchover

```bash
# When paused at ZDM_SWITCHOVER_SRC
# Perform final validations, then:
./zdm_commands_PRODDB.sh resume <JOB_ID>
```

### Step 6: Post-Migration Validation

Follow the validation steps in the Runbook:
- Verify data integrity
- Test application connectivity
- Confirm performance baselines

---

## Important Notes

### Security Considerations

⚠️ **Password Security:**
- All password files are created at runtime from environment variables
- Password files are automatically cleaned up after migration
- Never commit passwords to version control
- Never share password files

### Rollback Information

If migration fails or needs to be reversed:

1. **Before Switchover:** Simply abort the ZDM job
   ```bash
   ./zdm_commands_PRODDB.sh abort <JOB_ID>
   ```

2. **After Switchover:** Follow rollback procedures in the Runbook (Phase 7)

3. **Source Database:** Remains unchanged until explicit decommission

### Network Architecture

```
┌─────────────────────┐      ┌─────────────────────┐
│   Source Database   │      │  Target (ODAA RAC)  │
│   temandin-oravm-vm01│      │  tmodaauks-rqahk1/2 │
│   10.1.0.10         │◀────▶│  10.0.1.160         │
│   Oracle 19c        │      │  Oracle 19c Exadata │
└─────────────────────┘      └─────────────────────┘
          ▲                           ▲
          │                           │
          │    ┌─────────────────┐    │
          │    │   ZDM Server    │    │
          └────│ tm-vm-odaa-...  │────┘
               │   10.1.0.8      │
               │  ZDM + OCI CLI  │
               └─────────────────┘
```

### Support Contacts

| Role | Contact |
|------|---------|
| DBA Team | _______________ |
| Network Team | _______________ |
| Application Team | _______________ |
| Oracle Support | MOS SR # _______________ |

---

## Estimated Timeline

| Phase | Duration | Notes |
|-------|----------|-------|
| Pre-migration setup | 1-2 hours | OCI config, verification |
| Initial sync | 15-30 minutes | 1.92 GB database |
| Redo apply (catch-up) | 5-10 minutes | Depends on transaction rate |
| Switchover | 2-5 minutes | Minimal downtime |
| Post-validation | 30-60 minutes | Application testing |
| **Total Migration Window** | **~3 hours** | Including buffer |

---

## Change Log

| Date | Author | Change |
|------|--------|--------|
| 2026-02-03 | ZDM Migration Planning | Initial generation |

---

*Generated by ZDM Migration Planning - Step 3*
*Date: 2026-02-03*
