# Migration Planning Questionnaire: PRODDB

## Instructions

Please complete the following questions. **Recommended defaults** are provided based on discovery analysis of your PRODDB migration environment.

After completing this questionnaire:
1. Save this file
2. Run `Step2-Generate-Migration-Artifacts.prompt.md` to generate the RSP file and ZDM commands

---

## Pre-Questionnaire Checklist

Before completing this questionnaire, ensure the following critical actions from the Discovery Summary have been addressed:

- [ ] Supplemental logging enabled on source database
- [ ] OCI CLI installed and configured on ZDM server
- [ ] Network connectivity verified (ZDM → Source, ZDM → Target)
- [ ] SSH key authentication configured for ZDM migrations

---

## Section A: Migration Strategy

### A.1 Migration Method

**Recommended:** `ONLINE_PHYSICAL` ✓

Based on discovery analysis:
- ✅ Source database is in ARCHIVELOG mode
- ✅ Force Logging is enabled  
- ✅ TDE is configured with AUTOLOGIN wallet
- ✅ Small database size (1.88 GB) = fast synchronization
- ✅ Oracle 19c to Oracle 19c (version compatible)
- ✅ Target is ODAA Exadata (supports physical migration)

| Option | Description | Your Selection |
|--------|-------------|----------------|
| ONLINE_PHYSICAL | Minimal downtime using Data Guard replication | ✓ **Recommended** |
| OFFLINE_PHYSICAL | Extended downtime, simpler setup, RMAN restore only | |

**Your Selection:** `ONLINE_PHYSICAL` *(change if needed)*

---

### A.2 Migration Timeline

| Field | Recommended | Your Value |
|-------|-------------|------------|
| Planned Migration Date | _______________ | _______________ |
| Maintenance Window Start | _______________ (e.g., 02:00 UTC) | _______________ |
| Maintenance Window End | _______________ (e.g., 06:00 UTC) | _______________ |
| Maximum Acceptable Downtime | **15-30 minutes** (recommended for online) | _______________ |

**Notes:**
- For ONLINE_PHYSICAL, actual downtime is typically switchover time only (5-15 minutes)
- Schedule during low-activity period based on your application requirements

---

## Section B: OCI/Azure Identifiers (🔐 Required)

These values **must** be obtained from the OCI Console or Azure Portal for Oracle Database@Azure.

### B.1 OCI Tenancy Information

| Field | Value | Where to Find |
|-------|-------|---------------|
| OCI Tenancy OCID | ocid1.tenancy.oc1.._____ | OCI Console → Profile → Tenancy → OCID |
| OCI User OCID | ocid1.user.oc1.._____ | OCI Console → Profile → User Settings → OCID |
| OCI Compartment OCID | ocid1.compartment.oc1.._____ | OCI Console → Identity → Compartments |
| OCI Region | _____ (e.g., `uk-london-1`) | OCI Console → Region dropdown |

### B.2 Target Database System

| Field | Value | Where to Find |
|-------|-------|---------------|
| Target DB System OCID | ocid1.exadatainfrastructure.oc1.._____ | OCI Console → Bare Metal, VM, and Exadata → DB Systems |
| Target VM Cluster OCID | ocid1.cloudvmcluster.oc1.._____ | OCI Console → VM Clusters |
| Target Database Home OCID | ocid1.dbhome.oc1.._____ | OCI Console → Database Homes |
| Target Database OCID | *(leave blank for new DB)* | Will be created during migration |

### B.3 Azure Information (for ODAA)

| Field | Discovered Value | Your Value (if different) |
|-------|------------------|---------------------------|
| Azure Subscription ID | _______________ | _______________ |
| Azure Resource Group | _______________ | _______________ |
| ODAA Exadata System Name | `tmodaauks-rqahk1` | _______________ |

---

## Section C: Object Storage Configuration

ZDM requires OCI Object Storage for backup transfer during migration.

**Recommended Bucket Name:** `zdm-migration-proddb-20260130`

| Field | Recommended | Your Value |
|-------|-------------|------------|
| Object Storage Namespace | *(obtain from OCI Console)* | _______________ |
| Bucket Name | `zdm-migration-proddb` | _______________ |
| Bucket Region | *(same as target region)* | _______________ |
| Create New Bucket? | **YES** (clean migration) | [ ] YES  [ ] NO |

**Where to find namespace:**
OCI Console → Object Storage → Buckets → Look at top of page for "Namespace:"

---

## Section D: Migration Options

### D.1 Data Guard Configuration (Online Migration)

**Recommended:** MAXIMUM_PERFORMANCE with ASYNC transport

| Option | Recommended | Your Selection | Notes |
|--------|-------------|----------------|-------|
| Protection Mode | `MAXIMUM_PERFORMANCE` | [ ] MAX_PERFORMANCE [ ] MAX_AVAILABILITY | MAX_PERF for remote/WAN |
| Transport Type | `ASYNC` | [ ] ASYNC [ ] SYNC | ASYNC for cross-region |
| Redo Transport Compression | `ENABLE` | [ ] ENABLE [ ] DISABLE | Saves bandwidth |

**Why MAXIMUM_PERFORMANCE + ASYNC:**
- Source and target are in different networks (Azure → ODAA)
- Latency-tolerant for WAN connections
- No impact on source database performance

---

### D.2 TDE Wallet Migration

| Option | Discovered Value | Your Selection |
|--------|------------------|----------------|
| Source Wallet Location | `/u01/app/oracle/admin/oradb01/wallet/tde/` | *(auto-detected)* |
| Source Wallet Type | AUTOLOGIN | *(auto-detected)* |
| Migrate Encryption Keys | **YES** | [ ] YES [ ] NO |

**Note:** TDE wallet password will be required during migration. Ensure you have the wallet password available.

| Field | Value |
|-------|-------|
| TDE Wallet Password | *(enter securely during migration, not here)* |

---

### D.3 Database Naming on Target

| Field | Discovered Source | Recommended Target | Your Value |
|-------|-------------------|-------------------|------------|
| Database Name (DB_NAME) | ORADB01 | `ORADB01` | _______________ |
| DB Unique Name | oradb01 | `oradb01_oda` | _______________ |
| PDB Name (if converting to CDB) | N/A (non-CDB) | `ORADB01PDB` | _______________ |
| Convert to CDB? | N/A | **Recommended: YES** | [ ] YES [ ] NO |

**Note:** Oracle Database@Azure typically uses CDB architecture. Converting from non-CDB to CDB/PDB is recommended.

---

### D.4 Post-Migration Options

| Option | Recommended | Your Selection | Justification |
|--------|-------------|----------------|---------------|
| Auto Switchover | **NO** | [ ] YES [ ] NO | Manual control for validation |
| Delete Backup After Migration | **NO** | [ ] YES [ ] NO | Keep for rollback capability |
| Include Performance Data | **YES** | [ ] YES [ ] NO | Preserve optimizer statistics |
| Preserve Passwords | **YES** | [ ] YES [ ] NO | Maintain user credentials |

---

### D.5 Pause Points for Validation

**Recommended:** Pause before switchover to validate data and application connectivity

| Pause Point | Description | Select |
|-------------|-------------|--------|
| `ZDM_SETUP_SRC` | After source setup, before backup | [ ] |
| `ZDM_BACKUP_FULL_SRC` | After full backup created | [ ] |
| `ZDM_CLONE_TGT` | After database cloned to target | [ ] |
| `ZDM_CONFIGURE_DG_SRC` | After Data Guard setup | [ ] |
| `ZDM_SWITCHOVER_SRC` | **Before switchover** | [X] **Recommended** |
| None | Run to completion | [ ] |

**Your Selected Pause Point:** `ZDM_SWITCHOVER_SRC`

---

## Section E: Network and Connectivity

### E.1 SSH Configuration

| Field | Discovered Value | Your Value |
|-------|------------------|------------|
| ZDM SSH User | azureuser | _______________ |
| ZDM SSH Key File | /home/azureuser/key.pem | _______________ |
| Source SSH User | oracle *(or SSH user on source)* | _______________ |
| Target SSH User | oracle *(or opc on ODAA)* | _______________ |

### E.2 Source Database Credentials

| Field | Value |
|-------|-------|
| SYS Password | *(enter securely during migration)* |
| SYSTEM Password | *(enter securely during migration)* |

### E.3 Network Verification Status

| Test | Current Status | Action Required |
|------|----------------|-----------------|
| ZDM → Source (SSH) | ❌ BLOCKED | Configure NSG/firewall |
| ZDM → Source (Oracle) | ❌ BLOCKED | Configure NSG/firewall |
| ZDM → Target (SSH) | ❌ BLOCKED | Configure NSG/firewall |
| ZDM → Target (Oracle) | ❌ BLOCKED | Configure NSG/firewall |

**After fixing network, verify with:**
```bash
# From ZDM server
ssh -i /home/azureuser/key.pem oracle@10.1.0.10 "echo 'Source SSH OK'"
ssh -i /home/azureuser/key.pem opc@10.0.1.155 "echo 'Target SSH OK'"
sqlplus sys@'10.1.0.10:1521/oradb01' as sysdba
```

---

## Section F: Rollback Planning

| Field | Recommended | Your Value |
|-------|-------------|------------|
| Keep Source Available Post-Migration | **YES** (for 7 days) | [ ] YES [ ] NO |
| Source Retention Period | 7 days | _______________ days |
| Backup Retention | **Keep until validation complete** | _______________ |

---

## Section G: Validation Checklist (Post-Switchover)

**Validation tasks to perform at the pause point before final switchover:**

- [ ] Application connectivity test
- [ ] Critical query performance validation
- [ ] Data integrity checks (row counts, checksums)
- [ ] Database link functionality (SYS_HUB needs recreation)
- [ ] Scheduled job verification
- [ ] Alert log review for errors

---

## Section H: Confirmation

| Confirmation | Check |
|--------------|-------|
| I have reviewed the Discovery Summary | [ ] |
| I have completed all required fields above | [ ] |
| I have addressed critical actions from Discovery Summary | [ ] |
| I understand the recommended defaults and their justifications | [ ] |
| I have the TDE wallet password available | [ ] |
| I have database SYS/SYSTEM passwords available | [ ] |

**Completed By:** _______________

**Date:** _______________

**Email/Contact:** _______________

---

## Summary of Your Selections

*Fill this section after completing the questionnaire for quick reference:*

| Parameter | Your Value |
|-----------|------------|
| Migration Method | ONLINE_PHYSICAL |
| Target DB Unique Name | _______________ |
| Pause Point | ZDM_SWITCHOVER_SRC |
| Object Storage Bucket | _______________ |
| Planned Migration Date | _______________ |
| Maximum Downtime | _______________ |

---

## Next Steps

After completing this questionnaire:

1. ✅ Save this file
2. 🔲 Ensure all critical actions are completed (supplemental logging, OCI CLI, network)
3. 🔲 Run `Step2-Generate-Migration-Artifacts.prompt.md` with:
   - This completed questionnaire
   - The Discovery Summary
4. 🔲 Review generated RSP file and migration commands
5. 🔲 Execute migration runbook

---

*Generated by ZDM Migration Planning - Step 1*
*Based on discovery performed: 2026-01-30*
