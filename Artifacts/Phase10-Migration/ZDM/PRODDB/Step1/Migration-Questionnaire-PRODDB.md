# Migration Planning Questionnaire: PRODDB

## Instructions
Please complete the following questions. Recommended defaults are provided based on discovery analysis.
After completing, save this file and proceed to Step 2.

**Project:** PRODDB Migration to Oracle Database@Azure  
**Source:** ORADB01 on temandin-oravm-vm01 (10.1.0.10)  
**Target:** Exadata RAC on tmodaauks-rqahk1 (10.0.1.160)  
**ZDM Server:** tm-vm-odaa-oracle-jumpbox (10.1.0.8)

---

## Section A: Migration Strategy

### A.1 Migration Method

**Recommended:** `ONLINE_PHYSICAL` ✓

| Option | Description | Select |
|--------|-------------|--------|
| ONLINE_PHYSICAL | Minimal downtime using Data Guard synchronization | ✓ Recommended |
| OFFLINE_PHYSICAL | Extended downtime, simpler setup | |

**Your Selection:** `ONLINE_PHYSICAL`

**Why we recommend ONLINE_PHYSICAL:**
- ✅ Source database is in ARCHIVELOG mode (verified)
- ✅ Force Logging is enabled (verified)
- ✅ TDE is configured with AUTOLOGIN wallet (simplifies key transfer)
- ✅ Small database size (1.88 GB) enables fast initial sync
- ✅ Network latency is excellent (1.24ms to source)
- ✅ All TCP ports accessible (22, 1521)

---

### A.2 Migration Timeline

| Field | Your Value |
|-------|------------|
| Planned Migration Date | _______________ |
| Maintenance Window Start | _______________ |
| Maintenance Window End | _______________ |
| Maximum Acceptable Downtime | _______________ |

**Recommended Downtime:** 15-30 minutes for ONLINE_PHYSICAL migration

---

### A.3 Source Database to Migrate

**Discovered Source Database:**

| Property | Value |
|----------|-------|
| Database Name | ORADB01 |
| DB Unique Name | oradb01 |
| ORACLE_SID | oradb01 |
| Size | 1.88 GB |
| CDB/PDB | Non-CDB |

**Confirm:** [ ] Yes, this is the correct source database

---

### A.4 Target Database Selection

**Existing Databases on Target Exadata:**

| Database | Current Status | Select as Target |
|----------|----------------|------------------|
| ORADB01M | Open (2-node RAC) | [ ] ← Likely target based on naming |
| MIGDB | Open (2-node RAC) | [ ] |
| MYDB | Open (2-node RAC) | [ ] |
| **Create New** | N/A | [ ] |

**Your Selection:** _______________

> ⚠️ **Important:** If creating a new database, it must be provisioned via OCI Console before running ZDM.

---

## Section B: OCI/Azure Identifiers (Required)

These values must be obtained from the OCI Console. They are required for ZDM to interact with OCI services.

### B.1 OCI Identity

| Field | Value | Where to Find |
|-------|-------|---------------|
| OCI Tenancy OCID | _______________ | OCI Console → Governance → Tenancy Details |
| OCI User OCID | _______________ | OCI Console → Identity → Users → Your User |
| OCI API Key Fingerprint | _______________ | OCI Console → User → API Keys |

**Discovered Tenancy (from target metadata):**
```
ocid1.tenancy.oc1..aaaaaaaaax76pwvum5vhn2p3v264osde3ykrudasfzjktipw3ibpvtndhtkq
```
**Confirm this is correct:** [ ] Yes [ ] No, use different tenancy: _______________

---

### B.2 OCI Compartment and Region

| Field | Discovered Value | Confirm/Override |
|-------|-----------------|------------------|
| OCI Region | uk-london-1 | [ ] Confirmed / Override: _______________ |
| OCI Compartment OCID | (same as tenancy discovered) | Override if different: _______________ |

---

### B.3 Target Database Identifiers

| Field | Value | Where to Find |
|-------|-------|---------------|
| Target DB System OCID | _______________ | OCI Console → Bare Metal, VM, and Exadata → DB Systems |
| Target Database OCID | _______________ | OCI Console → Databases (within DB System) |
| Target Database Home OCID | _______________ | OCI Console → Database Homes (within DB System) |
| Target PDB Name | _______________ | e.g., ORADB01PDB (if migrating to CDB) |

**Discovered from CRS Status:**
```
Target databases visible on cluster:
- ora.oradb01m.db (likely target)
- ora.migdb.db
- ora.mydb.db
```

---

## Section C: Object Storage Configuration

ZDM uses OCI Object Storage to transfer backup files during migration.

### C.1 Object Storage Settings

| Field | Recommended | Your Value |
|-------|-------------|------------|
| Object Storage Namespace | _______________ | _______________ |
| Bucket Name | zdm-migration-proddb | _______________ |
| Bucket Region | uk-london-1 (same as target) | _______________ |

**Bucket Options:**

| Option | Select |
|--------|--------|
| Create new bucket for this migration | [ ] Recommended |
| Use existing bucket | [ ] Bucket name: _______________ |

> **Finding Your Namespace:** OCI Console → Object Storage → Buckets → Any bucket → View namespace

---

### C.2 Object Storage Credentials

| Field | Value |
|-------|-------|
| Auth Token (for Swift access) | *Will be prompted at runtime* |

> ⚠️ **Security:** Auth tokens should be entered at runtime, not stored in files.

---

## Section D: Migration Options

### D.1 Data Guard Configuration (Online Migration Only)

**Recommended:** MAXIMUM_PERFORMANCE with ASYNC transport

| Option | Recommended | Your Selection |
|--------|-------------|----------------|
| Protection Mode | MAXIMUM_PERFORMANCE | [ ] MAX_PERFORMANCE [ ] MAX_AVAILABILITY |
| Transport Type | ASYNC | [ ] ASYNC [ ] SYNC |

**Why MAXIMUM_PERFORMANCE:**
- Lower network requirements
- No impact on source database commit times
- Suitable for cross-region/cross-cloud migrations
- RPO: potential data loss of uncommitted transactions (typically seconds)

---

### D.2 TDE Wallet Configuration

**Discovered TDE Status:**

| Source | Target |
|--------|--------|
| TDE Enabled: YES | Wallet Status: OPEN_NO_MASTER_KEY |
| Wallet Type: AUTOLOGIN | (Ready to receive keys) |
| Wallet Location: /u01/app/oracle/admin/oradb01/wallet/tde/ | /var/opt/oracle/dbaas_acfs/grid/tcps_wallets/ |

**TDE Migration Options:**

| Option | Description | Select |
|--------|-------------|--------|
| AUTO_TDE_DOWNLOAD | ZDM automatically transfers TDE keys | [ ] Recommended |
| MANUAL_TDE | Manually copy and import TDE wallet | [ ] |

**Your Selection:** _______________

**TDE Wallet Password:** *Will be prompted at runtime*

---

### D.3 Post-Migration Options

| Option | Recommended | Your Selection |
|--------|-------------|----------------|
| Auto Switchover | NO (manual control for validation) | [ ] YES [ ] NO |
| Delete Backup After Migration | NO (keep for rollback period) | [ ] YES [ ] NO |
| Keep Source as Standby | NO (clean switchover) | [ ] YES [ ] NO |
| Include Performance Data (AWR) | YES | [ ] YES [ ] NO |

---

### D.4 Pause Points for Validation

ZDM can pause at specific phases to allow validation before proceeding.

**Recommended:** Pause before switchover (`ZDM_SWITCHOVER_SRC`)

| Phase | Description | Select |
|-------|-------------|--------|
| ZDM_VALIDATE_SRC | After source validation | [ ] |
| ZDM_VALIDATE_TGT | After target validation | [ ] |
| ZDM_BACKUP_SRC | After backup completion | [ ] |
| ZDM_RESTORE_TGT | After restore on target | [ ] |
| ZDM_CONFIGURE_DG_SRC | After Data Guard setup | [ ] |
| **ZDM_SWITCHOVER_SRC** | Before switchover | [✓] Recommended |
| None | Run to completion | [ ] |

**Your Selection:** _______________

---

## Section E: Network Configuration

### E.1 Connectivity Summary (Verified)

| Path | Status | Latency |
|------|--------|---------|
| ZDM → Source (10.1.0.10) | ✅ Connected | 1.24ms |
| ZDM → Target (10.0.1.160) | ✅ Connected | N/A (ICMP blocked, TCP OK) |
| Source → Target | ❓ To be verified | _______________ |

### E.2 Network Details (If Needed)

| Field | Value |
|-------|-------|
| ExpressRoute/VPN Name | _______________ |
| Estimated Bandwidth | _______________ |
| Network Restrictions/Firewall Notes | _______________ |

---

## Section F: Rollback and Recovery Planning

### F.1 Rollback Strategy

| Option | Description | Select |
|--------|-------------|--------|
| Keep source database intact | Source remains available for rollback | [✓] Recommended |
| Flashback source after cutover | Enable flashback for point-in-time recovery | [ ] |
| Full RMAN backup before migration | Additional safety backup | [ ] |

### F.2 Post-Migration Retention

| Item | Retention Period | Your Value |
|------|-----------------|------------|
| Source Database (before decommission) | 7 days recommended | _______________ |
| Object Storage Backup Files | 30 days recommended | _______________ |

---

## Section G: Confirmation Checklist

Please confirm the following before proceeding to Step 2:

| Item | Confirmed |
|------|-----------|
| I have reviewed the Discovery Summary | [ ] |
| I have identified the correct source database (ORADB01) | [ ] |
| I have identified/confirmed the target database | [ ] |
| I have the OCI Console access to obtain OCIDs | [ ] |
| I understand the supplemental logging must be enabled | [ ] |
| I understand OCI CLI must be installed on ZDM server | [ ] |
| I have coordinated the maintenance window with stakeholders | [ ] |

---

## Summary of Values Entered

*After completing this questionnaire, summarize key values here:*

```bash
# Migration Method
MIGRATION_METHOD=

# Timeline
PLANNED_DATE=
MAINTENANCE_WINDOW_START=
MAINTENANCE_WINDOW_END=
MAX_DOWNTIME_MINUTES=

# OCI Identifiers
OCI_TENANCY_OCID=
OCI_USER_OCID=
OCI_COMPARTMENT_OCID=
OCI_REGION=uk-london-1

# Target Database
TARGET_DB_SYSTEM_OCID=
TARGET_DATABASE_OCID=
TARGET_DB_NAME=
TARGET_PDB_NAME=

# Object Storage
OCI_OSS_NAMESPACE=
OCI_OSS_BUCKET_NAME=

# Migration Options
DATAGUARD_MODE=MAXIMUM_PERFORMANCE
AUTO_SWITCHOVER=NO
TDE_TRANSFER_MODE=AUTO_TDE_DOWNLOAD
PAUSE_PHASE=ZDM_SWITCHOVER_SRC
```

---

## Completed By

| Field | Value |
|-------|-------|
| Name | _______________ |
| Date | _______________ |
| Role | _______________ |

---

## Next Steps

After completing this questionnaire:

1. ✅ Save this file
2. ⬜ Address Critical Actions from Discovery Summary:
   - Enable supplemental logging on source
   - Install and configure OCI CLI on ZDM server
3. ⬜ Run **Step 2: Fix Issues** (`Step2-Fix-Issues.prompt.md`)
4. ⬜ After all issues resolved, run **Step 3: Generate Migration Artifacts** (`Step3-Generate-Migration-Artifacts.prompt.md`)
