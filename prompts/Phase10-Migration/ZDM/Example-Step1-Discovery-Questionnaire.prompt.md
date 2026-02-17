# Example: Discovery Analysis and Migration Planning for PRODDB

This example demonstrates Step 1 for a production Oracle database migration to Oracle Database@Azure.

## What Step 1 Does

Step 1 takes the discovery output from Step 0 and generates:
1. **Discovery Summary** - Auto-populated analysis of all discovered configurations
2. **Migration Planning Questionnaire** - Only the items requiring manual input, with recommended defaults

---

## Prerequisites

Before running Step 1:
- ✅ Run `Step0-Generate-Discovery-Scripts.prompt.md` to generate discovery scripts
- ✅ Execute scripts on all servers and collect outputs to `Step0/Discovery/`
- ✅ Have OCI/Azure console access for OCIDs (needed to complete the questionnaire)

---

## Example Prompt

Copy and use this prompt with your discovery files:

```
@Step1-Discovery-Questionnaire.prompt.md

Please analyze the discovery results for our <DATABASE> migration and generate:
1. A summary of discovered configurations
2. A questionnaire for manual decisions with recommended defaults

## Attached Discovery Files

### Source Database Discovery (from Step0)
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE>/Step0/Discovery/source/

### Target Database Discovery (from Step0)
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE>/Step0/Discovery/target/

### ZDM Server Discovery (from Step0)
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE>/Step0/Discovery/server/

## Output Directory
Save all generated artifacts to: Artifacts/Phase10-Migration/ZDM/<DATABASE>/Step1/
```

> **Note:** Replace `<DATABASE>` with your database name (e.g., PRODDB, HRDB, etc.).
> When referencing directories, GitHub Copilot will read all files in those directories.

---

## Example Output: Discovery Summary

This is an example of what Step 1 generates in `Artifacts/Phase10-Migration/ZDM/PRODDB/Step0/Discovery/Discovery-Summary-PRODDB.md`:

```markdown
# Discovery Summary: PRODDB Migration

## Generated
- Date: 2026-01-30
- Source Files Analyzed:
  - zdm_source_discovery_proddb01_20260130_140532.json
  - zdm_target_discovery_odadb-node1_20260130_141022.json
  - zdm_server_discovery_zdm-jumpbox_20260130_141545.json

---

## Executive Summary

| Component | Status | Key Findings |
|-----------|--------|--------------|
| Source Database | ✅ Ready | ORADB01, 19c, 1.88GB, ARCHIVELOG, TDE enabled |
| Target Environment | ✅ Ready | ODAA Exadata, 19c, sufficient capacity |
| ZDM Server | ✅ Ready | ZDM 21.4 installed, service running |
| Network | ⚠️ Verify | Connectivity tests needed |

---

## Migration Method Recommendation

**Recommended:** ONLINE_PHYSICAL ✓

**Justification:**
- Source database is in ARCHIVELOG mode ✅
- Force Logging is enabled ✅
- TDE is configured with AUTOLOGIN wallet ✅
- Database size (1.88 GB) is small - migration will be quick
- Minimal downtime is typically preferred for production databases

**Alternative Consideration:**
Given the small database size (1.88 GB), OFFLINE_PHYSICAL could also work well if a maintenance window of 1-2 hours is acceptable. However, ONLINE_PHYSICAL is recommended for production readiness and minimal risk.

---

## Source Database Details

### Database Identification
| Property | Value |
|----------|-------|
| Database Name | ORADB01 |
| Database Unique Name | oradb01 |
| Database SID | oradb01 |
| DBID | 1593802201 |
| Version | 19.0.0.0.0 |
| Role | PRIMARY |
| Platform | Linux x86 64-bit |

### Database Size and Configuration
| Property | Value |
|----------|-------|
| Total Size | 1.88 GB |
| Character Set | AL32UTF8 |
| National Character Set | AL16UTF16 |
| Open Mode | READ WRITE |
| CDB | NO (Non-CDB) |

### Migration Readiness
| Requirement | Current State | Required | Status |
|-------------|---------------|----------|--------|
| ARCHIVELOG Mode | YES | YES | ✅ |
| Force Logging | YES | YES | ✅ |
| Supplemental Logging (MIN) | NO | YES (Online) | ⚠️ Action Required |
| Supplemental Logging (PK) | NO | YES (Online) | ⚠️ Action Required |
| Supplemental Logging (UI) | NO | YES (Online) | ⚠️ Action Required |
| TDE Enabled | YES | Optional | ✅ |
| TDE Wallet Type | AUTOLOGIN | Supported | ✅ |

### Source Host
| Property | Value |
|----------|-------|
| Hostname | temandin-oravm-vm01 |
| IP Address | 10.1.0.10 |
| OS | Oracle Linux Server 7.9 |
| Oracle Home | /u01/app/oracle/product/19.0.0/dbhome_1 |
| Listener Port | 1521 |

---

## Target Environment Details

### Target Host
| Property | Value |
|----------|-------|
| Hostname | tmodaauks-rqahk1 |
| IP Address | 10.0.1.160 |
| Platform | Oracle Database@Azure (Exadata) |
| OS | Oracle Linux Server 8.10 |
| Oracle Home | /u02/app/oracle/product/19.0.0.0/dbhome_1 |
| Version | 19.0.0.0.0 |

### Target Readiness
| Requirement | Status | Notes |
|-------------|--------|-------|
| Oracle Version Match | ✅ | Both 19c |
| Platform Compatible | ✅ | Linux x86-64 |
| Exadata Storage | ✅ | Available |

---

## ZDM Server Details

### Server Information
| Property | Value |
|----------|-------|
| Hostname | tm-vm-odaa-oracle-jumpbox |
| IP Address | 10.1.0.8 |
| OS | Oracle Linux Server 9.5 |

### ZDM Installation
| Property | Value |
|----------|-------|
| ZDM Home | /u01/app/zdmhome |
| ZDM Base | /u01/app/zdmbase |
| ZDM User | zdmuser |
| Service Status | ✅ Running |

### OCI CLI Status
| Property | Value |
|----------|-------|
| Installed | ❌ NOT INSTALLED |

---

## Required Actions Before Migration

### Critical (Must Fix Before Migration)

| # | Action | Command/Steps | Priority |
|---|--------|---------------|----------|
| 1 | Enable Supplemental Logging | See SQL below | HIGH |
| 2 | Install OCI CLI on ZDM Server | `dnf install python3-oci-cli` | HIGH |
| 3 | Verify Network Connectivity | Test SSH/Oracle ports | HIGH |

**Enable Supplemental Logging (run on source):**
```sql
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (PRIMARY KEY) COLUMNS;
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (UNIQUE INDEX) COLUMNS;
```

### Recommended

| # | Action | Notes |
|---|--------|-------|
| 1 | Create OCI Object Storage bucket | For migration backups |
| 2 | Test OCI API connectivity | After OCI CLI install |
| 3 | Configure SSH key authentication | Between all servers |

---

## Discovered Values Reference

These values are auto-populated and will be used in Step 2:

### Source Database
- DB_NAME: ORADB01
- DB_UNIQUE_NAME: oradb01
- DBID: 1593802201
- ORACLE_HOME: /u01/app/oracle/product/19.0.0/dbhome_1
- TDE_WALLET_LOCATION: /u01/app/oracle/admin/oradb01/wallet/tde/

### Target Environment  
- TARGET_HOST: 10.0.1.160
- TARGET_ORACLE_HOME: /u02/app/oracle/product/19.0.0.0/dbhome_1

### ZDM Server
- ZDM_HOST: 10.1.0.8
- ZDM_HOME: /u01/app/zdmhome
```

---

## Example Output: Migration Planning Questionnaire

This is an example of what Step 1 generates in `Artifacts/Phase10-Migration/ZDM/PRODDB/Step1/Migration-Questionnaire-PRODDB.md`:

```markdown
# Migration Planning Questionnaire: PRODDB

## Instructions

Please complete the following questions. Recommended defaults are provided based on
the discovery analysis. After completing, save this file and proceed to Step 2.

**Discovery Summary:** See `Step0/Discovery/Discovery-Summary-PRODDB.md` for full details.

---

## Section A: Migration Strategy

### A.1 Migration Method

**Recommended:** ONLINE_PHYSICAL ✓

Based on discovery analysis:
- Source is in ARCHIVELOG mode with Force Logging enabled
- TDE is configured properly
- Database size (1.88 GB) allows for quick synchronization
- Online migration provides minimal downtime

| Option | Description | Your Selection |
|--------|-------------|----------------|
| ONLINE_PHYSICAL | Minimal downtime (~15 min), uses Data Guard | [X] Recommended |
| OFFLINE_PHYSICAL | Longer downtime, simpler setup | [ ] |

**Your Selection:** _________________ (default: ONLINE_PHYSICAL)

### A.2 Migration Timeline

| Field | Recommended | Your Value |
|-------|-------------|------------|
| Planned Migration Date | _________________ | _________________ |
| Maintenance Window Start | _________________ | _________________ |
| Maintenance Window End | _________________ | _________________ |
| Maximum Acceptable Downtime | 15-30 minutes | _________________ |

---

## Section B: OCI/Azure Identifiers (Required)

These values must be obtained from the OCI Console. They are NOT discoverable automatically.

| Field | Where to Find | Your Value |
|-------|---------------|------------|
| OCI Tenancy OCID | OCI Console > Profile > Tenancy | _________________________ |
| OCI User OCID | OCI Console > Profile > User Settings | _________________________ |
| OCI Compartment OCID | OCI Console > Identity > Compartments | _________________________ |
| OCI Region | e.g., uk-london-1, us-ashburn-1 | _________________________ |
| Target DB System OCID | OCI Console > Oracle Database > Exadata | _________________________ |
| Target Database OCID | OCI Console > Oracle Database > Databases | _________________________ |

---

## Section C: Object Storage Configuration

| Field | Recommended | Your Value |
|-------|-------------|------------|
| Object Storage Namespace | (from OCI Console) | _________________________ |
| Bucket Name | zdm-migration-proddb | _________________________ |
| Bucket Region | (same as target) | _________________________ |
| Create New Bucket? | YES | [ ] YES [ ] NO |

---

## Section D: Migration Options

### D.1 Data Guard Configuration (for Online Migration)

**Recommended:** MAXIMUM_PERFORMANCE with ASYNC

| Option | Recommended | Your Selection |
|--------|-------------|----------------|
| Protection Mode | MAXIMUM_PERFORMANCE | [ ] MAX_PERF [ ] MAX_AVAIL |
| Transport Type | ASYNC | [ ] ASYNC [ ] SYNC |

**Why MAX_PERF + ASYNC?** Best performance with acceptable RPO for most migrations.

### D.2 Post-Migration Options

| Option | Recommended | Reason | Your Selection |
|--------|-------------|--------|----------------|
| Auto Switchover | NO | Manual control for production | [ ] YES [ ] NO |
| Delete Backup After | NO | Keep for rollback option | [ ] YES [ ] NO |
| Include Perf Data | YES | Helps optimize target | [ ] YES [ ] NO |

### D.3 Pause Points

**Recommended:** Pause before switchover (ZDM_SWITCHOVER_SRC)

[ ] ZDM_CONFIGURE_DG_SRC - Pause after Data Guard setup
[X] ZDM_SWITCHOVER_SRC - Pause before switchover (Recommended for production)
[ ] None - Run to completion

**Why pause before switchover?** Allows validation and coordination with application team.

---

## Section E: RMAN Backup Settings

| Setting | Recommended | Your Value |
|---------|-------------|------------|
| Parallel Channels | 4 (small database) | _________________ |
| Compression | MEDIUM | [ ] LOW [X] MEDIUM [ ] HIGH |
| Encryption | AES256 | [ ] AES128 [ ] AES192 [X] AES256 |

---

## Section F: Confirmation

Before proceeding to Step 2, please confirm:

[ ] I have reviewed the Discovery Summary
[ ] I have completed all OCI/Azure identifiers in Section B  
[ ] I have verified network connectivity between all servers
[ ] I understand the supplemental logging must be enabled before migration

**Completed By:** _________________________
**Date:** _________________________

---

## Next Steps

After completing this questionnaire:

1. **Save this file** to `Artifacts/Phase10-Migration/ZDM/PRODDB/Step1/`
2. **Complete required actions** from the Discovery Summary
3. **Run Step 2 prompt**: `Step2-Generate-Migration-Artifacts.prompt.md`
```

---

## Summary: What Gets Created

When you run Step 1 with discovery files attached:

| Output File | Location | Purpose |
|-------------|----------|---------|
| Discovery-Summary-PRODDB.md | `Step0/Discovery/` | Auto-populated analysis of all discoveries |
| Migration-Questionnaire-PRODDB.md | `Step1/` | Manual items only, with recommendations |

---

## Tips

1. **Let the AI do the work** - Discovery summary is fully auto-populated
2. **Focus on manual items** - The questionnaire only asks what can't be discovered
3. **Use the recommendations** - They're based on analysis of your specific environment
4. **Complete Section B** - OCI OCIDs are required and can only come from the console
5. **Review the required actions** - Complete them before running Step 2