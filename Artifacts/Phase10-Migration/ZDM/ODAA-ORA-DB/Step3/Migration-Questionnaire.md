# Migration Planning Questionnaire

## Instructions

Please complete the following questions. Recommended defaults are provided based on discovery analysis.  
After completing, save this file and proceed to **Step 4: Fix Issues**.

> **Pre-condition:** Review the [Discovery-Summary.md](./Discovery-Summary.md) first.  
> All **Critical** actions in the Discovery Summary must be resolved before Step 5 (artifact generation).

---

## Section A: Migration Strategy

### A.1 Migration Method

**Recommended:** `ONLINE_PHYSICAL` ✓

```
[ ] ONLINE_PHYSICAL   - Minimal downtime (~15-30 min) using ZDM + Data Guard physical standby
[ ] OFFLINE_PHYSICAL  - Extended downtime, simpler — use only if ARCHIVELOG cannot be enabled
```

**Your Selection:** _______________

**Why ONLINE_PHYSICAL is recommended:**
- SOURCE (`factvmhost`) and TARGET (`vmclusterpoc-ytlat1`) are both Oracle 19c — same major version, no upgrade needed
- Network RTT ZDM → SOURCE/TARGET is < 2 ms with zero packet loss — ideal for Data Guard redo shipping
- TARGET is an Exadata VM Cluster — purpose-built for Data Guard workloads
- Azure NFS shares (`/nfstest1`, `/nfstest`, `/mount/saadb12feb2026/adbshare01`) are mounted on both hosts and usable for RMAN backup staging

> ⚠️ **Condition:** SOURCE must be confirmed in `ARCHIVELOG` mode (blocked by sqlplus path issue — see Discovery Summary Critical Action #1 and #5). If `ARCHIVELOG` cannot be enabled, select `OFFLINE_PHYSICAL`.

---

### A.2 Migration Timeline

| Field | Recommended | Your Value |
|-------|-------------|------------|
| Planned Migration Date | _______________ (schedule after all Critical actions resolved) | _______________ |
| Maintenance Window Start | _______________ | _______________ |
| Maintenance Window End | _______________ | _______________ |
| Maximum Acceptable Downtime | 30 minutes (ONLINE) / 4–8 hours (OFFLINE) | _______________ |
| Rollback Deadline | Within 2 hours of switchover | _______________ |

---

## Section B: OCI / Azure Identifiers (Required — 🔐 Manual Entry)

These values must be obtained from the OCI Console. They cannot be auto-discovered and are required for ZDM response file generation in Step 5.

| Field | Value | Where to Find |
|-------|-------|---------------|
| OCI Tenancy OCID | `ocid1.tenancy.oc1..<YOUR_TENANCY_OCID>` | OCI Console → **Governance & Administration → Tenancy Details** |
| OCI User OCID | `ocid1.user.oc1..<YOUR_USER_OCID>` | OCI Console → **Identity → Users → your user** |
| OCI Compartment OCID | `ocid1.compartment.oc1..<YOUR_COMPARTMENT_OCID>` | OCI Console → **Identity → Compartments** |
| OCI Region | _______________ | e.g., `uk-london-1`, `eu-frankfurt-1`, `us-ashburn-1` |
| Target DB System OCID | _______________ | OCI Console → **Oracle Database → Exadata → VM Clusters** → select `vmclusterpoc-ytlat1` |
| Target Database OCID | `ocid1.database.oc1.<region>.<YOUR_DATABASE_OCID>` | OCI Console → DB System → select database (CDBAKV) |
| OCI API Key Fingerprint | `<xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx>` | OCI Console → **User Settings → API Keys** |
| OCI Private Key Path | `~/.oci/oci_api_key.pem` | Path on ZDM server after `oci setup config` |

> **Note:** The values above are pre-filled placeholders from `zdm-env.md` — replace with real OCIDs before Step 5.

---

## Section C: Object Storage Configuration

**Recommended Bucket:** Use the existing Azure Files NFS share for RMAN backup staging, **or** create a dedicated OCI Object Storage bucket.

| Field | Recommended | Your Value |
|-------|-------------|------------|
| Storage Type | OCI Object Storage (for ZDM) | [ ] OCI Object Storage  [ ] NFS (see note) |
| OCI Object Storage Namespace | _______________ | _______________ |
| Bucket Name | `zdm-migration-mckess-<date>` | _______________ |
| Bucket Region | Same as target DB region | _______________ |
| Create New Bucket? | YES — dedicated migration bucket | [ ] YES  [ ] NO |
| NFS Staging Path (alternative) | `/nfstest` or `/mount/saadb12feb2026/adbshare01` (1 TB, already mounted on both hosts) | _______________ |

> **Note on NFS vs OCI Object Storage:** ZDM `ONLINE_PHYSICAL` with `DATA_TRANSFER_MEDIUM=OBJECT_STORE` uses OCI Object Storage. Alternatively, `DATA_TRANSFER_MEDIUM=DBLINK` or `NFS` can be used if OCI Object Storage is not yet configured. Given that a large Azure Files NFS share is already mounted on both hosts, `NFS` is a viable fallback while OCI CLI is being configured on the ZDM server.

---

## Section D: Migration Options

### D.1 Data Guard Configuration (Online Migration)

**Recommended:** `MAXIMUM_PERFORMANCE` with `ASYNC` transport

| Option | Recommended | Your Selection |
|--------|-------------|----------------|
| Protection Mode | `MAXIMUM_PERFORMANCE` | [ ] MAX_PERFORMANCE  [ ] MAX_AVAILABILITY |
| Transport Type | `ASYNC` | [ ] ASYNC  [ ] SYNC |
| Redo Apply Mode | `APPLY_NOW` | [ ] APPLY_NOW  [ ] DELAY=n |

> `MAXIMUM_PERFORMANCE` with `ASYNC` is appropriate for the network profile (< 2 ms RTT LAN/inter-subnet) and minimises impact on source production throughput. Use `MAXIMUM_AVAILABILITY` with `SYNC` only if RPO of 0 is a hard requirement.

---

### D.2 Post-Migration / Switchover Options

| Option | Recommended | Your Selection |
|--------|-------------|----------------|
| Auto Switchover after Sync | NO — manual control recommended | [ ] YES  [ ] NO |
| Delete Migration Backup After Completion | NO — retain for rollback window | [ ] YES  [ ] NO |
| Include Performance Diagnostics | YES | [ ] YES  [ ] NO |
| Retain Source as Standby Post-Switchover | YES (for rollback) | [ ] YES  [ ] NO |

---

### D.3 ZDM Pause Points

Pause points allow manual validation before ZDM proceeds to the next phase.

```
[ ] ZDM_CONFIGURE_DG_SRC      - Pause after Data Guard configuration (source side)
[X] ZDM_SWITCHOVER_SRC        - Pause BEFORE switchover ← RECOMMENDED
                                  Gives time to validate data sync, run app-level checks,
                                  confirm business sign-off before cutting over
[ ] ZDM_CLEANUP_SRC           - Pause before source cleanup
[ ] None                      - Run to completion without pausing
```

**Your Pause Point Selection:** _______________

---

### D.4 Existing Data Guard on Source

Discovery indicates `log_archive_dest_2` is configured on `factvmhost` — a standby database may exist.

| Question | Your Answer |
|----------|-------------|
| Does SOURCE currently have a standby database? | [ ] YES  [ ] NO  [ ] Unknown |
| If YES — is it a physical or logical standby? | _______________ |
| Can the existing standby be deregistered before migration? | [ ] YES  [ ] NO |
| Is the existing DG used for DR purposes during migration? | [ ] YES  [ ] NO |

> ZDM can work alongside an existing Data Guard configuration, but the response file must include the existing DG parameters. Confirm with Oracle Support if the source is already in a DG broker configuration.

---

## Section E: Network Configuration

| Question | Recommended / Discovered | Your Answer |
|----------|--------------------------|-------------|
| Network path ZDM → SOURCE | LAN (10.200.1.0/24 subnet), RTT 1.5 ms ✅ | Confirm |
| Network path ZDM → TARGET | Cross-subnet (10.200.1.x → 10.200.0.x), RTT 1.3 ms ✅ | Confirm |
| ExpressRoute / FastConnect in use? | Likely (Azure → OCI inter-connect given mixed platform) | [ ] YES  [ ] NO |
| Bandwidth estimate available for redo shipping? | _______________ Mbps | _______________ |
| Archive log destination on SOURCE | Confirm not writing to local `/` (84% full) | _______________ |
| Any proxy required for OCI CLI on ZDM server? | _______________ | [ ] YES  [ ] NO |

---

## Section F: Application and Business Context

| Question | Your Answer |
|----------|-------------|
| Application name(s) using `MCKESS` database | _______________ |
| Application owner / contact for migration sign-off | _______________ |
| Is a freeze period required before switchover? | [ ] YES  [ ] NO |
| Known scheduler jobs with external host/path references | Review `DBMS_SCHEDULER` exports — see Discovery Summary warning |
| Post-migration DB link updates required? | Discovery could not confirm (SQL failed) — verify after Step 4 |
| Existing DR/HA commitment SLAs during migration | _______________ |

---

## Section G: Confirmation Checklist

Before proceeding to Step 5:

```
[ ] All Critical actions from Discovery-Summary.md have been resolved
[ ] Step 2 discovery re-run after fixes — SQL sections now complete
[ ] ARCHIVELOG mode confirmed ON on SOURCE
[ ] Force Logging confirmed ON on SOURCE
[ ] Supplemental Logging (MIN) confirmed ON on SOURCE
[ ] TARGET_ORACLE_SID updated to CDBAKV21 in zdm-env.md
[ ] ZDM_HOME located and set in zdmuser .bash_profile
[ ] ZDM service confirmed running (zdmservice status)
[ ] Java confirmed available ($ZDM_HOME/jdk or system)
[ ] OCI CLI installed and configured on ZDM server
[ ] ~/.oci/config populated with real Tenancy/User/Region/Key values
[ ] All OCI/Azure Identifiers in Section B filled in above
[ ] Migration timeline and maintenance window agreed with application owner

[ ] I have reviewed the Discovery Summary
[ ] I have completed all required fields in this questionnaire
[ ] I understand the recommended defaults and their justifications
```

**Completed By:** _______________  
**Date:** _______________

---

## Next Steps

After completing this questionnaire:

1. **Address all Critical issues** — run `@Phase10-ZDM-Step4-Fix-Issues` to generate fix scripts
2. **Re-run Step 2 discovery** after fixes to confirm SQL sections succeed
3. **Fill in Section B** (OCI Identifiers) from the OCI Console
4. **Proceed to Step 5** — run `@Phase10-ZDM-Step5-Generate-Migration-Artifacts` with:
   - This completed questionnaire
   - The updated Discovery Summary
   - The Issue Resolution Log from Step 4
