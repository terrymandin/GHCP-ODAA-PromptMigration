# Migration Planning Questionnaire: PRODDB

## Instructions

Please complete the following questions. Recommended defaults are provided based on discovery analysis.
After completing, save this file and proceed to Step 2.

> **Discovery Date:** 2026-02-03  
> **Source Database:** ORADB01 (oradb01) - Oracle 19c on temandin-oravm-vm01  
> **Target Environment:** Oracle Database@Azure Exadata (2-node RAC)

---

## Section A: Migration Strategy

### A.1 Migration Method

**Recommended:** ONLINE_PHYSICAL ✓

| Option | Description | Downtime |
|--------|-------------|----------|
| [X] ONLINE_PHYSICAL | Minimal downtime using Data Guard replication | Minutes |
| [ ] OFFLINE_PHYSICAL | Extended downtime, simpler setup | Hours |

**Your Selection:** `ONLINE_PHYSICAL`

**Why we recommend ONLINE_PHYSICAL:**
- ✅ Source database is in ARCHIVELOG mode
- ✅ Force Logging is already enabled
- ✅ Supplemental Logging is configured (PK + minimal)
- ✅ Small database size (1.92 GB) enables fast initial sync
- ✅ Network connectivity confirmed between all components
- ✅ TDE wallet is configured and open

---

### A.2 Migration Timeline

| Field | Your Value |
|-------|------------|
| Planned Migration Date | _______________ |
| Maintenance Window Start | _______________ |
| Maintenance Window End | _______________ |
| Maximum Acceptable Downtime | `15 minutes` (Recommended for online migration) |

---

### A.3 Target Database Configuration

**Question:** What is the target database name?

Based on discovery, the following databases exist on target:
- `migdb` - Currently ONLINE (in use)
- `mydb` - Currently OFFLINE
- `oradb01m` - Currently OFFLINE (appears to be from previous migration attempt)

| Field | Recommended | Your Value |
|-------|-------------|------------|
| Target DB Unique Name | oradb01_target | _______________ |
| Target PDB Name (if CDB) | oradb01_pdb | _______________ |
| Use Existing Database? | [ ] YES - Specify: _______ | [ ] NO - Create new |

> **Note:** Source is Non-CDB. Target may be CDB or Non-CDB depending on your requirements.

---

## Section B: OCI/Azure Identifiers (Required)

These values must be obtained from the OCI Console or Azure Portal.

> **⚠️ Important:** These identifiers are required for ZDM to interact with OCI resources.

### B.1 OCI Tenancy Information

| Field | Value | Where to Find |
|-------|-------|---------------|
| OCI Tenancy OCID | `ocid1.tenancy.oc1..____________________` | OCI Console > Profile > Tenancy Details |
| OCI User OCID | `ocid1.user.oc1..____________________` | OCI Console > Profile > User Settings |
| OCI Fingerprint | ________________________________ | OCI Console > Profile > API Keys |
| OCI Region | `uk-london-1` (Recommended based on target FQDN) | OCI Console > Region selector |

### B.2 Compartment Information

| Field | Value | Where to Find |
|-------|-------|---------------|
| OCI Compartment OCID | `ocid1.compartment.oc1..____________________` | OCI Console > Identity > Compartments |

### B.3 Target Database OCIDs

| Field | Value | Where to Find |
|-------|-------|---------------|
| Target DB System OCID | `ocid1.exadatadbsystem.oc1..____________________` | OCI Console > Databases > Exadata DB Systems |
| Target Database OCID | `ocid1.database.oc1..____________________` | OCI Console > Databases > Databases |

---

## Section C: Object Storage Configuration

ZDM uses OCI Object Storage for backup transfer during migration.

**Recommended Bucket Name:** `zdm-migration-proddb-20260203`

| Field | Recommended | Your Value |
|-------|-------------|------------|
| Object Storage Namespace | ________________________________ | _______________ |
| Bucket Name | `zdm-migration-proddb` | _______________ |
| Bucket Region | `uk-london-1` (same as target) | _______________ |
| Create New Bucket? | [X] YES | [ ] YES [ ] NO |

> **How to find Object Storage Namespace:**
> OCI Console > Object Storage > Buckets > Click on any bucket or create new

---

## Section D: Migration Options

### D.1 Data Guard Configuration (Online Migration Only)

**Recommended:** MAXIMUM_PERFORMANCE with ASYNC

| Option | Recommended | Your Selection |
|--------|-------------|----------------|
| Protection Mode | `MAXIMUM_PERFORMANCE` | [ ] MAX_PERFORMANCE [ ] MAX_AVAILABILITY |
| Transport Type | `ASYNC` | [ ] ASYNC [ ] SYNC |

**Why we recommend MAXIMUM_PERFORMANCE + ASYNC:**
- Lower network bandwidth requirements
- Minimal impact on source database performance
- Acceptable for most migrations (sync can be enabled for final switchover)
- Source and target are in different networks (Azure to OCI connectivity)

---

### D.2 Post-Migration Options

| Option | Recommended | Your Selection | Notes |
|--------|-------------|----------------|-------|
| Auto Switchover | `NO` | [ ] YES [X] NO | Manual control for validation |
| Delete Backup After Migration | `NO` | [ ] YES [X] NO | Keep for rollback capability |
| Include Performance Data | `YES` | [X] YES [ ] NO | Preserves AWR/baseline data |
| Evaluate Datapump | `YES` | [X] YES [ ] NO | ZDM evaluates import feasibility |

---

### D.3 Pause Points

Pause points allow validation between migration phases.

**Recommended:** Pause before switchover for final validation

| Pause Point | Recommended | Your Selection | Description |
|-------------|-------------|----------------|-------------|
| ZDM_VALIDATE_SRC | [ ] | [ ] | Pause after source validation |
| ZDM_VALIDATE_TGT | [ ] | [ ] | Pause after target validation |
| ZDM_CONFIGURE_DG_SRC | [ ] | [ ] | Pause after Data Guard setup on source |
| ZDM_SWITCHOVER_SRC | [X] | [X] | Pause before switchover (Recommended) |
| None | [ ] | [ ] | Run to completion |

**Your Additional Pause Points:** _______________

---

## Section E: Credential Management

### E.1 SSH Key Configuration

Based on discovery, the following SSH keys are available on ZDM server:

| Key | Location | Recommended Use |
|-----|----------|-----------------|
| zdm.pem | /home/zdmuser/.ssh/zdm.pem | Source connectivity |
| odaa.pem | /home/zdmuser/.ssh/odaa.pem | Target connectivity (ODAA) |
| iaas.pem | /home/zdmuser/.ssh/iaas.pem | Alternative target key |

| Field | Recommended | Your Value |
|-------|-------------|------------|
| Source SSH Key Path | `/home/zdmuser/.ssh/zdm.pem` | _______________ |
| Target SSH Key Path | `/home/zdmuser/.ssh/odaa.pem` | _______________ |

### E.2 Admin User Configuration

| Field | Discovered/Recommended | Your Value |
|-------|------------------------|------------|
| Source Admin User | `azureuser` | _______________ |
| Target Admin User | `opc` | _______________ |

> **Note:** Admin users should have sudo access to oracle user on respective hosts.

---

## Section F: TDE Wallet Migration

Source database has TDE wallet configured:
- **Wallet Location:** `/u01/app/oracle/admin/oradb01/wallet/tde/`
- **Wallet Type:** AUTOLOGIN
- **Status:** OPEN

| Field | Recommended | Your Value |
|-------|-------------|------------|
| Migrate TDE Wallet? | [X] YES | [ ] YES [ ] NO |
| Wallet Password | ________________________________ | (Required for migration) |

> **Important:** TDE wallet password is required even for AUTOLOGIN wallets during migration.

---

## Section G: Database Link Handling

Discovery found the following database link(s) on source:

| Owner | DB Link Name | Remote User | Host |
|-------|--------------|-------------|------|
| SYS | SYS_HUB | SEEDDATA | (not specified) |

| Action | Your Selection |
|--------|----------------|
| Recreate links post-migration | [ ] YES [ ] NO |
| Document for manual recreation | [ ] YES [ ] NO |
| Links no longer needed | [ ] YES [ ] NO |

**Notes:** _______________________________________________

---

## Section H: Network Configuration Verification

### H.1 Connectivity Summary (from Discovery)

| Path | SSH (22) | Oracle (1521) | Status |
|------|----------|---------------|--------|
| ZDM → Source | ✅ OPEN | ✅ OPEN | Ready |
| ZDM → Target | ✅ OPEN | ✅ OPEN | Ready |

### H.2 Additional Network Considerations

| Question | Your Response |
|----------|---------------|
| Is ExpressRoute/VPN in use? | [ ] YES [ ] NO |
| Estimated network bandwidth | _______________ Mbps |
| Network change freeze periods? | _______________ |

---

## Section I: Rollback Planning

| Question | Your Response |
|----------|---------------|
| Maximum rollback window needed | _______________ hours |
| Keep source database running post-migration? | [ ] YES [ ] NO |
| Source retention period after successful migration | _______________ days |

---

## Section J: Confirmation

| Checklist Item | Confirmed |
|----------------|-----------|
| I have reviewed the Discovery Summary | [ ] |
| I have completed all required fields above | [ ] |
| I have obtained all OCI OCIDs | [ ] |
| I understand the recommended defaults and their justifications | [ ] |
| I have the TDE wallet password available | [ ] |
| I have verified network connectivity requirements | [ ] |

**Completed By:** _______________  
**Role/Title:** _______________  
**Date:** _______________

---

## Summary of Discovered Values (Pre-populated)

These values were auto-discovered and will be used in migration artifacts:

```yaml
# Source Database
source_db_unique_name: oradb01
source_database_name: ORADB01
source_dbid: 1593802201
source_oracle_home: /u01/app/oracle/product/19.0.0/dbhome_1
source_db_host: temandin-oravm-vm01
source_db_ip: 10.1.0.10
source_listener_port: 1521
source_character_set: AL32UTF8
source_is_cdb: NO
source_data_size_gb: 1.92
tde_wallet_location: /u01/app/oracle/admin/oradb01/wallet/tde/

# Target Environment
target_db_host: tmodaauks-rqahk1
target_db_ip: 10.0.1.160
target_listener_port: 1521
target_oracle_home: /u02/app/oracle/product/19.0.0.0/dbhome_1
target_grid_home: /u01/app/19.0.0.0/grid
target_data_diskgroup: +DATAC3
target_reco_diskgroup: +RECOC3

# ZDM Server
zdm_host: tm-vm-odaa-oracle-jumpbox
zdm_ip: 10.1.0.8
zdm_home: /u01/app/zdmhome
zdm_user: zdmuser
```

---

## Next Steps

After completing this questionnaire:

1. ✅ Save this file with your responses
2. 🔍 Review [Discovery-Summary-PRODDB.md](Discovery-Summary-PRODDB.md) for any critical actions
3. 🔧 Run **Step 2**: `Step2-Fix-Issues.prompt.md` to address any blockers
4. 🚀 After all issues resolved, run **Step 3**: `Step3-Generate-Migration-Artifacts.prompt.md` with:
   - This completed questionnaire
   - The Discovery Summary
   - The Issue Resolution Log from Step 2
