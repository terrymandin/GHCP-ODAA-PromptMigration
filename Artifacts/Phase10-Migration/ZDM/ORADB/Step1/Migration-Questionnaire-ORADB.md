# Migration Planning Questionnaire: ORADB

## Instructions
Please complete the following questions. Recommended defaults are provided based on discovery analysis.
After completing this questionnaire, save the file and proceed to Step 2 to resolve the identified issues,
then Step 3 to generate migration artifacts.

> **Pre-requisite:** Before running the migration, ensure all Critical actions in `Discovery-Summary-ORADB.md` have been completed:
> 1. PDB1 must be open (`ALTER PLUGGABLE DATABASE PDB1 OPEN`)
> 2. Full supplemental logging must be enabled (`ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS`)
> 3. OCI config must be configured for zdmuser on the ZDM server

---

## Section A: Migration Strategy

### A.1 Migration Method
**Recommended:** ONLINE_PHYSICAL ✓

```
[ ] ONLINE_PHYSICAL  - Minimal downtime using Data Guard replication (recommended)
[ ] OFFLINE_PHYSICAL - Extended downtime, no Data Guard; simpler but longer outage
```

**Your Selection:** _______________

**Why we recommend ONLINE_PHYSICAL:**
- Source database is in ARCHIVELOG mode ✅
- Force Logging is enabled ✅
- Cross-version upgrade (12.2 → 19c) is fully supported by ZDM physical migration
- Database is small (2.08 GB) — initial copy will complete quickly
- ZDM EVAL jobs have previously passed all prechecks on this infrastructure (Jobs 16 & 17)
- Only supplemental logging and PDB open state need to be resolved before proceeding

---

### A.2 Migration Timeline

| Field | Recommended | Your Value |
|-------|-------------|------------|
| Planned Migration Date | _______________ | _______________ |
| Maintenance Window Start | _______________ | _______________ |
| Maintenance Window End | Recommended: 2-hour window | _______________ |
| Maximum Acceptable Downtime | Recommended: 15–30 minutes (online) | _______________ |

**Notes:**
- For ONLINE_PHYSICAL, actual switchover downtime is typically 5–15 minutes
- Schedule during off-peak hours to minimise application impact
- Ensure DBAs from both source (Azure) and target (OCI) teams are available

---

### A.3 Migration Scope

| Field | Discovered Value | Confirm |
|-------|-----------------|---------|
| Source DB | ORADB1 (oradb1 unique name) | [ ] Confirmed |
| Source PDB | PDB1 | [ ] Confirmed |
| Target CDB | oradb01m | [ ] Confirmed |
| Target PDB (will be created) | _______________ (recommend: ORADB1) | _______________ |
| Version Upgrade | 12.2.0.1.0 → 19.29.0.0.0 | [ ] Confirmed |

---

## Section B: OCI / Azure Identifiers

> These values are collected from `zdm-env.md`. Verify they are correct before proceeding.

| Field | Value from zdm-env.md | Status |
|-------|----------------------|--------|
| OCI Tenancy OCID | `ocid1.tenancy.oc1..aaaaaaaarvyhjcn7wkkxxx5g3o7lgqks23bmsjtsticz3gtg5xs5qyrwkftq` | [ ] Verified |
| OCI User OCID | `ocid1.user.oc1..aaaaaaaakfe5cirdq7vkkrhogjrgcrgftvwb7mdoehujgchefpqv54vhsnoa` | [ ] Verified |
| OCI Compartment OCID | `ocid1.compartment.oc1..aaaaaaaas4upnqj72dfiivgwvn3uui5gkxo7ng6leeoifucbjiy326urbhmq` | [ ] Verified |
| OCI Region | `uk-london-1` (derived from TARGET_DATABASE_OCID) | [ ] Verified |
| Target Database OCID | `ocid1.database.oc1.uk-london-1.anwgiljss56liuaatz45cjnpbvpgku7gkorvxg6lytoj5lxxruk2eqxzkzma` | [ ] Verified |
| OCI API Key Fingerprint | `7f:05:c1:f2:5c:3a:46:ec:9f:95:44:c8:77:a4:50:f9` | [ ] Verified |
| OCI Private Key Path | `~/.oci/oci_api_key.pem` (on ZDM server as zdmuser) | [ ] Verified |

> **Where to find these values:**
> - Tenancy OCID: OCI Console → Administration → Tenancy Details
> - User OCID: OCI Console → Identity → Users → (your user)
> - Compartment OCID: OCI Console → Identity → Compartments
> - Target Database OCID: OCI Console → Oracle Database → Exadata Database Service (ExaDB) → (your DB)

### B.1 Target DB System OCID

> The Target DB System OCID (Exadata Infrastructure OCID) is separate from the Database OCID.

| Field | Value | Where to Find |
|-------|-------|---------------|
| Target DB System OCID | _______________ | OCI Console → Exadata DB → DB Systems → (your system) → OCID |

---

## Section C: Object Storage Configuration

> OCI Object Storage is used as the backup staging area for ZDM physical migration.
> **Note:** `OCI_OSS_NAMESPACE` and `OCI_OSS_BUCKET_NAME` are not set in `zdm-env.md` — these must be provided.

**Recommended Bucket Name:** `zdm-migration-oradb`

| Field | Recommended | Your Value |
|-------|-------------|------------|
| Object Storage Namespace | *(retrieve via: `oci os ns get`)* | _______________ |
| Bucket Name | `zdm-migration-oradb` | _______________ |
| Bucket Region | `uk-london-1` (same as target) | _______________ |
| Create New Bucket? | YES (if bucket does not already exist) | [ ] YES  [ ] NO |

> **How to get the namespace:**
> Run on ZDM server as zdmuser (after OCI config is set up):
> ```bash
> oci os ns get
> ```
> Or check OCI Console → Object Storage → Buckets → Namespace shown in the header.

> **Bucket requirements:**
> - Bucket must be in the same tenancy and region as the target database
> - ZDM needs access via the OCI API Key configured for zdmuser
> - Bucket must not be public; private bucket with IAM policy for the migration user is preferred

---

## Section D: Migration Options

### D.1 Data Guard Configuration (Online Migration)

**Recommended:** MAXIMUM_PERFORMANCE with ASYNC transport

| Option | Recommended | Your Selection |
|--------|-------------|----------------|
| Protection Mode | `MAXIMUM_PERFORMANCE` | [ ] MAX_PERFORMANCE  [ ] MAX_AVAILABILITY |
| Redo Transport | `ASYNC` | [ ] ASYNC  [ ] SYNC |

**Justification for MAXIMUM_PERFORMANCE / ASYNC:**
- Minimises performance impact on source during migration active replication phase
- Source is on Azure IaaS; network latency to OCI may make SYNC transport impractical
- For a 2.08 GB database, lag will be minimal even with ASYNC

---

### D.2 TDE (Transparent Data Encryption)

| Field | Discovered | Action |
|-------|-----------|--------|
| Source TDE Status | NOT_AVAILABLE (no encryption) | No TDE password required for source |
| Target TDE Wallet | OPEN_NO_MASTER_KEY | ZDM will configure TDE on target as part of migration |
| TDE Keystore Password | N/A (source not encrypted) | _______________ (set a new password for target keystore) |

> **Recommendation:** Even though source is not TDE-encrypted, ODAA (Oracle Database@Azure) may require TDE to be enabled on the target. Confirm with your ODAA team whether TDE is mandatory.
> If required, ZDM will migrate to a TDE-enabled target using `-tdekeystorepasswd`.

---

### D.3 Post-Migration Options

| Option | Recommended | Your Selection |
|--------|-------------|----------------|
| Auto Switchover | `NO` — manual control recommended | [ ] YES  [ ] NO |
| Delete Backup After Migration | `NO` — retain for rollback period | [ ] YES  [ ] NO |
| Pause Before Switchover | `YES` — pause at ZDM_SWITCHOVER_SRC | [ ] YES  [ ] NO |
| Include Performance Data | `YES` | [ ] YES  [ ] NO |

---

### D.4 Pause Points
**Recommended:** Pause before switchover to allow manual validation.

```
[ ] ZDM_CONFIGURE_DG_SRC    — Pause after Data Guard is configured (to verify replication lag)
[X] ZDM_SWITCHOVER_SRC      — RECOMMENDED: Pause before switchover for final application checks
[ ] None                    — Run to completion without pause
```

**Your Selection:** _______________

---

### D.5 Target DB Parameters

| Parameter | Discovered Default | Recommended / Your Value |
|-----------|-------------------|--------------------------|
| Target DB Unique Name | oradb011 *(instance)* | _______________ |
| Target Oracle Home | `/u02/app/oracle/product/19.0.0.0/dbhome_1` | [ ] Confirmed |
| Target ASM DATA Diskgroup | `+DATAC3` | _______________ |
| Target ASM REDO Diskgroup | `+RECOC3` | _______________ |

---

## Section E: Network Configuration

### E.1 Cross-Cloud Connectivity

| Component | Status | Notes |
|-----------|--------|-------|
| Azure ↔ OCI ExpressRoute/Interconnect | ✅ Confirmed working | ZDM eval jobs 16 & 17 passed all prechecks across the network |
| Source → ZDM Server (SSH port 22) | ✅ Confirmed | ZDM server at 10.1.0.8, source at 10.1.0.11 (same subnet) |
| ZDM Server → Target (SSH port 22) | ✅ Confirmed | Target at 10.0.1.160 (OCI VCN) reachable from ZDM server |
| ZDM Server → OCI Object Storage | ⚠️ Verify HTTPS | OCI CLI connectivity should be tested after OCI config is set up on ZDM server |

### E.2 Firewall / NSG Ports Required

| Port | Protocol | Direction | Purpose |
|------|----------|-----------|---------|
| 22 | TCP | ZDM → Source | SSH (zdmauth) |
| 22 | TCP | ZDM → Target | SSH (zdmauth) |
| 1521 | TCP | ZDM → Source | Oracle listener (validation) |
| 1521 | TCP | ZDM → Target | Oracle listener (DG setup) |
| 443 | HTTPS | ZDM → OCI | Object Storage access |

| Field | Value | Your Confirmation |
|-------|-------|-------------------|
| ExpressRoute / Interconnect Bandwidth | _______________ Mbps | _______________ |
| Estimated Transfer Time (2 GB) | < 5 minutes at 100 Mbps | [ ] Acceptable |
| Backup Route Available? | _______________ | _______________ |

---

## Section F: Rollback Plan

| Field | Recommended | Your Selection |
|-------|-------------|----------------|
| Rollback Method | Revert switchover; source DB remains primary until confirmed | _______________ |
| Rollback Window | 24–48 hours after migration | _______________ |
| When to Delete Source | After application validation complete | _______________ |
| Source DB Retention Post-Migration | ≥ 7 days (keep archive logs) | _______________ |

---

## Section G: Application Impact

| Field | Your Value |
|-------|------------|
| Applications Connecting to Source DB | _______________ |
| Application Team Contact | _______________ |
| Connection String Change Required? | [ ] YES  [ ] NO |
| Estimated Application Validation Time | _______________ |
| Notify Users Before Switchover? | [ ] YES  [ ] NO |

---

## Section H: Confirmation Checklist

Before proceeding to Step 2 and Step 3, confirm:

```
[ ] PDB1 has been opened on source (ALTER PLUGGABLE DATABASE PDB1 OPEN)
[ ] ALL COLUMNS supplemental logging enabled on source (ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS)
[ ] OCI config configured for zdmuser on ZDM server (~/.oci/config)
[ ] OCI Object Storage bucket name and namespace determined (Section C)
[ ] Target DB System OCID obtained (Section B.1)
[ ] Migration method selected (Section A.1)
[ ] Maintenance window scheduled (Section A.2)
[ ] Target PDB name decided (Section A.3)
[ ] TDE keystore password decided (Section D.2)
[ ] Application team notified (Section G)
[ ] Rollback plan agreed (Section F)

Completed By: _______________
Date: _______________
Reviewed By: _______________
```

---

## Next Steps

After completing this questionnaire:

1. **Fix Issues** — Run `Step2-Fix-Issues.prompt.md` with:
   - This questionnaire
   - `Discovery-Summary-ORADB.md`
   - Focus on Critical items: PDB1 open, supplemental logging, OCI config

2. **Generate Artifacts** — Run `Step3-Generate-Migration-Artifacts.prompt.md` with:
   - This completed questionnaire
   - `Discovery-Summary-ORADB.md`
   - The Issue Resolution Log from Step 2

3. **Run Migration** — Execute the generated ZDM command from Step 3
