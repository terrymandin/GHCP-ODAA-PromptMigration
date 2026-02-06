# Migration Planning Questionnaire: PRODDB

## Instructions

Please complete the following questions. **Recommended defaults** are provided based on discovery analysis.
After completing, save this file and proceed to Step 2.

> **Discovery Summary:** Review `Discovery-Summary-PRODDB.md` before completing this questionnaire.

---

## Section A: Migration Strategy

### A.1 Migration Method

**Recommended:** ONLINE_PHYSICAL ✓

- [X] **ONLINE_PHYSICAL** - Minimal downtime using Data Guard (Recommended)
- [ ] OFFLINE_PHYSICAL - Extended downtime, simpler setup

**Your Selection:** `ONLINE_PHYSICAL`

**Why we recommend ONLINE_PHYSICAL:**
- ✅ Source database is in ARCHIVELOG mode
- ✅ Force Logging is enabled
- ✅ Supplemental Logging (MIN + PK) is already configured
- ✅ TDE wallet is AUTOLOGIN type (no password prompts during sync)
- ✅ Network connectivity verified between all servers
- ✅ Small database size (2.6GB) means fast initial sync
- ✅ Target is a 2-node RAC providing high availability

---

### A.2 Migration Timeline

| Field | Recommended | Your Value |
|-------|-------------|------------|
| Planned Migration Date | _______________ | `________________` |
| Maintenance Window Start (UTC) | _______________ | `________________` |
| Maintenance Window End (UTC) | _______________ | `________________` |
| Maximum Acceptable Downtime | 15-30 minutes | `________________` |

> **Note:** For ONLINE_PHYSICAL migration, only the final switchover requires downtime.

---

### A.3 Target Database Naming

**Current Source Values:**
- DB Name: `ORADB01`
- DB Unique Name: `oradb01`

**Recommended Target Values:**

| Field | Recommended | Your Value |
|-------|-------------|------------|
| Target DB Name | ORADB01 (same as source) | `________________` |
| Target DB Unique Name | oradb01_oda | `________________` |

> **⚠️ Important:** Discovery found an existing database `oradb01m` on the target cluster. 
> Confirm this does not conflict with your migration.
> 
> - [ ] I have verified the existing `oradb01m` database status

---

## Section B: OCI/Azure Identifiers (Required)

These values must be obtained from the OCI Console.

> **🔐 Security Note:** These are non-sensitive identifiers. Never include passwords in this file.

| Field | Value | Where to Find |
|-------|-------|---------------|
| OCI Tenancy OCID | `________________` | OCI Console → Tenancy Details |
| OCI User OCID | `________________` | OCI Console → User Settings → OCID |
| OCI Compartment OCID | `________________` | OCI Console → Identity → Compartments |
| OCI Region | `________________` | e.g., `uk-london-1`, `us-ashburn-1` |
| Target DB System OCID | `________________` | OCI Console → Bare Metal, VM, and Exadata → DB Systems |
| Target Database OCID | `________________` | OCI Console → DB Systems → Database Details |
| OCI API Key Fingerprint | `________________` | OCI Console → User Settings → API Keys |

### OCI API Key Configuration

| Field | Recommended | Your Value |
|-------|-------------|------------|
| OCI Config Path | /home/zdmuser/.oci/config | `________________` |
| OCI Private Key Path | /home/zdmuser/.oci/odaa.pem | `________________` |

> **Discovery Finding:** Found existing key files in `/home/zdmuser/.oci/`:
> - `odaa.pem` - Verify this is the correct API key for migration

---

## Section C: Object Storage Configuration

Object Storage is used to transfer backup files during migration.

**Recommended Bucket Name:** `zdm-migration-oradb01-2026`

| Field | Recommended | Your Value |
|-------|-------------|------------|
| Object Storage Namespace | `________________` | `________________` |
| Bucket Name | zdm-migration-oradb01 | `________________` |
| Bucket Region | (same as target) | `________________` |
| Create New Bucket? | YES | [ ] YES  [ ] NO |

> **How to find Object Storage Namespace:**
> OCI Console → Object Storage → Buckets → Look at "Namespace" column

---

## Section D: Migration Options

### D.1 Data Guard Configuration (Online Migration)

**Recommended:** MAXIMUM_PERFORMANCE with ASYNC

| Option | Recommended | Your Selection |
|--------|-------------|----------------|
| Protection Mode | MAXIMUM_PERFORMANCE | [X] MAX_PERF  [ ] MAX_AVAIL |
| Transport Type | ASYNC | [X] ASYNC  [ ] SYNC |

**Justification:**
- ASYNC provides best performance over WAN links
- For small databases like ORADB01 (2.6GB), sync performance impact is minimal
- MAX_PERFORMANCE allows primary to continue if standby is temporarily unavailable

---

### D.2 Post-Migration Options

| Option | Recommended | Your Selection |
|--------|-------------|----------------|
| Auto Switchover | NO (manual control) | [ ] YES  [X] NO |
| Delete Backup After Migration | NO (keep for rollback) | [ ] YES  [X] NO |
| Include Performance Data | YES | [X] YES  [ ] NO |
| Skip Fallback | NO | [ ] YES  [X] NO |

**Justification for Manual Switchover:**
- Allows validation of Data Guard sync before cutover
- Provides controlled migration window
- Enables rollback if issues are discovered

---

### D.3 Pause Points

Select pause points where ZDM should stop for validation:

**Recommended:** Pause before switchover (ZDM_SWITCHOVER_SRC)

- [ ] ZDM_SETUP_SRC - Pause after initial setup
- [ ] ZDM_CLONE_TGT - Pause after cloning target
- [ ] ZDM_CONFIGURE_DG_SRC - Pause after Data Guard setup
- [X] ZDM_SWITCHOVER_SRC - **Pause before switchover (Recommended)**
- [ ] None - Run to completion

> **Tip:** Pausing at ZDM_SWITCHOVER_SRC allows you to:
> - Verify Data Guard sync status
> - Test application connectivity to standby (read-only)
> - Validate data consistency
> - Perform final go/no-go decision

---

### D.4 TDE Wallet Configuration

**Discovered Configuration:**

| Property | Source Value |
|----------|--------------|
| Wallet Type | AUTOLOGIN |
| Wallet Location | /u01/app/oracle/admin/oradb01/wallet/tde/ |
| Wallet Status | OPEN |

| Field | Recommended | Your Value |
|-------|-------------|------------|
| Copy TDE Wallet to Target | YES | [X] YES  [ ] NO |
| Target Wallet Location | /u02/app/oracle/admin/oradb01/wallet/tde/ | `________________` |

> **Note:** ZDM will handle TDE wallet migration automatically. Ensure source wallet password is available at migration time.

---

## Section E: SSH Key Configuration

### E.1 Discovered SSH Keys

| Server | User | Key Location |
|--------|------|--------------|
| ZDM Server | zdmuser | /home/zdmuser/.ssh/iaas.pem, odaa.pem, zdm.pem |
| Source | oracle | Admin user with sudo |
| Target | opc | /home/opc/.ssh/id_rsa |

### E.2 Confirm SSH Key Mappings

| Connection | User | SSH Key Path |
|------------|------|--------------|
| ZDM → Source | `________________` | `________________` |
| ZDM → Target | `________________` | `________________` |

> **Discovery Note:** Source uses admin user with sudo to run oracle commands.
> Target uses `opc` user with sudo.

---

## Section F: Network Configuration

### F.1 Connectivity Verification

**Discovery Results:**

| Path | Ping | SSH (22) | Oracle (1521) |
|------|------|----------|---------------|
| ZDM → Source | ✅ 0.9ms | ✅ | ✅ |
| ZDM → Target | ❌ (ICMP blocked) | ✅ | ✅ |

- [X] I confirm network connectivity is established (SSH and Oracle ports open)

### F.2 Database Connection Details

| Field | Source | Target |
|-------|--------|--------|
| Hostname/IP | 10.1.0.10 | 10.0.1.160 |
| Port | 1521 | 1521 |
| Service Name | oradb01 | (to be created) |
| Connection Method | SYSDBA | SYSDBA |

---

## Section G: Credentials (DO NOT FILL - Set at Runtime)

> **🔒 SECURITY WARNING:** Never save passwords in this file or any repository.

The following credentials are required but should be set as **environment variables at migration runtime** on the ZDM server:

| Variable | Description | Required |
|----------|-------------|----------|
| `SOURCE_SYS_PASSWORD` | Source database SYS password | YES |
| `TARGET_SYS_PASSWORD` | Target database SYS password | YES |
| `SOURCE_TDE_WALLET_PASSWORD` | Source TDE wallet password | YES (TDE enabled) |

**To set at runtime (on ZDM server):**
```bash
read -sp "Enter SOURCE_SYS_PASSWORD: " SOURCE_SYS_PASSWORD; echo; export SOURCE_SYS_PASSWORD
read -sp "Enter TARGET_SYS_PASSWORD: " TARGET_SYS_PASSWORD; echo; export TARGET_SYS_PASSWORD
read -sp "Enter SOURCE_TDE_WALLET_PASSWORD: " SOURCE_TDE_WALLET_PASSWORD; echo; export SOURCE_TDE_WALLET_PASSWORD
```

- [ ] I understand passwords must be set at migration runtime and not saved to files

---

## Section H: Pre-Migration Checklist

Based on discovery findings, confirm the following:

### Actions Required

- [ ] Configure OCI CLI credentials for zdmuser (Critical)
- [ ] Verify target database unique name does not conflict with existing `oradb01m`
- [ ] Review SYS_HUB database link requirements post-migration
- [ ] (Optional) Expand ZDM server disk space to 50GB+

### Validations

- [ ] I have reviewed the Discovery Summary document
- [ ] I have confirmed network connectivity to source and target
- [ ] I have the required OCI OCIDs available
- [ ] I have access to database SYS passwords
- [ ] I have access to TDE wallet password

---

## Section I: Confirmation

- [ ] I have completed all required fields above
- [ ] I understand the recommended defaults and their justifications
- [ ] I am ready to proceed to Step 2 (Fix Issues)

**Completed By:** _______________

**Date:** _______________

**Role:** _______________

---

## Summary of Selections

| Setting | Value |
|---------|-------|
| Migration Method | ONLINE_PHYSICAL |
| Maximum Downtime | ___ minutes |
| Protection Mode | MAXIMUM_PERFORMANCE |
| Transport Type | ASYNC |
| Pause Point | ZDM_SWITCHOVER_SRC |
| Auto Switchover | NO |

---

## Next Steps

After completing this questionnaire:

1. ✅ **Save this file** with your responses
2. ➡️ **Run Step 2:** `Step2-Fix-Issues.prompt.md` to address any blockers
   - Configure OCI credentials
   - Resolve database link issues (if needed)
   - Verify target database naming
3. ➡️ **Run Step 3:** `Step3-Generate-Migration-Artifacts.prompt.md`
   - Attach this completed questionnaire
   - Generate ZDM response file and migration commands
