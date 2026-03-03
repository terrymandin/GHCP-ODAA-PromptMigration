# Migration Planning Questionnaire: ORADB

## Instructions
Please complete the following questions. Recommended defaults are provided based on discovery analysis.
After completing, save this file and proceed to Step 2 to resolve any outstanding issues before running Step 3.

> **Important:** Fields marked 🔐 are sensitive identifiers that must be sourced from the OCI Console or Azure Portal.
> Fields marked ⚠️ were identified in the Discovery Summary as requiring action before migration can proceed.

---

## Section A: Migration Strategy

### A.1 Migration Method

**Recommended:** `ONLINE_PHYSICAL` ✓

```
[ ] ONLINE_PHYSICAL   — Minimal downtime using Data Guard replication (RECOMMENDED)
[ ] OFFLINE_PHYSICAL  — Extended downtime (database offline during RMAN restore); simpler setup
```

**Your Selection:** _______________

**Why ONLINE_PHYSICAL is recommended:**
- Source is in ARCHIVELOG mode with Force Logging enabled
- Supplemental logging (minimal + PK) is already active — no prerequisite work needed
- No TDE on source — avoids keystore migration complexity
- Database is only 2.14 GB — initial RMAN backup will complete very quickly
- ZDM uses Data Guard to keep the target in sync, limiting switchover window to minutes

> **Note for OFFLINE_PHYSICAL:** With 2.14 GB, an offline restore would complete in ~5–15 minutes depending on network bandwidth. If a brief downtime window is acceptable, this is also a viable option and avoids OCI Object Storage requirements.

---

### A.2 Migration Timeline

| Field | Recommended / Notes | Your Value |
|-------|---------------------|------------|
| Planned Migration Date | Schedule during low-usage period | _______________ |
| Maintenance Window Start | — | _______________ |
| Maintenance Window End | — | _______________ |
| Maximum Acceptable Downtime | 15–30 min (online) / 30–60 min (offline) | _______________ |

---

### A.3 Source PDB Name Mapping

The source database has **one PDB: `PDB1`**.

| Source PDB | Target PDB Name | Notes |
|------------|-----------------|-------|
| PDB1 | _______________ | ⚠️ Must not conflict with PDBs on existing `oradb01m` |

**Recommended:** Keep as `PDB1` unless a naming convention requires otherwise.

**Your Selection:** _______________

---

### A.4 Target Database Unique Name

| Field | Recommended | Your Value |
|-------|-------------|------------|
| Target `DB_UNIQUE_NAME` | `ORADB1` (or `oradb1t` to distinguish from source) | _______________ |
| Target `DB_NAME` | `ORADB1` (must match source) | _______________ |

> ⚠️ The existing database on this ODAA system uses instance name `oradb011`. Confirm the new target DB unique name does not conflict. Use `oradb01a` or a site-specific naming convention if needed.

---

## Section B: OCI / Azure Identifiers (🔐 Required)

> **Source of truth:** OCI Console at https://cloud.oracle.com

Most values are already configured in `zdm-env.md`. The items below require verification or completion.

### B.1 Pre-configured Values (verify these are correct)

| Field | Value from zdm-env.md | Verified? |
|-------|----------------------|-----------|
| OCI Tenancy OCID | `ocid1.tenancy.oc1..aaaaaaaarvyhjcn7wk...` | [ ] YES [ ] NO |
| OCI User OCID | `ocid1.user.oc1..aaaaaaaakfe5cird...` | [ ] YES [ ] NO |
| OCI Compartment OCID | `ocid1.compartment.oc1..aaaaaaaas4upnqj7...` | [ ] YES [ ] NO |
| Target Database OCID | `ocid1.database.oc1.uk-london-1.anwgi...` | [ ] YES [ ] NO |
| OCI API Key Fingerprint | `7f:05:c1:f2:5c:3a:46:ec:9f:95:44:c8:77:a4:50:f9` | [ ] YES [ ] NO |
| OCI Region | `uk-london-1` (inferred from Target DB OCID) | [ ] YES [ ] NO |

---

### B.2 Target DB System OCID (🔐)

The Target DB System OCID (parent of the database, i.e., the ODAA VM Cluster or DB System) is **distinct** from the Target Database OCID.

| Field | Where to Find | Your Value |
|-------|---------------|------------|
| Target DB System OCID | OCI Console → Oracle Database → Exadata Database Service on Dedicated Infrastructure → VM Clusters → select your cluster | _______________ |

---

### B.3 OCI Config on ZDM Server

The OCI CLI must be configured under the `zdmuser` account on the ZDM server. Verify:

```bash
# Run on ZDM server as azureuser:
sudo -u zdmuser oci iam region list --config-file ~/.oci/config
```

| Field | Value (zdmuser account) | Status |
|-------|------------------------|--------|
| OCI Config Path | `~/.oci/config` (under zdmuser home) | [ ] Verified working [ ] Needs setup |
| OCI Private Key Path | `~/.oci/oci_api_key.pem` (under zdmuser home) | [ ] Verified [ ] Needs copy |

---

## Section C: OCI Object Storage (⚠️ Required for ONLINE_PHYSICAL)

> Object Storage is used by ZDM to transfer the initial RMAN backup from source to target.
> **Not required if you choose OFFLINE_PHYSICAL.**

### C.1 Bucket Configuration

| Field | Recommended | Your Value |
|-------|-------------|------------|
| ⚠️ OCI OSS Namespace | Retrieve with: `oci os ns get` | _______________ |
| ⚠️ Bucket Name | `zdm-migration-oradb-20260303` | _______________ |
| Bucket Region | `uk-london-1` (same as TARGET_DATABASE_OCID) | _______________ |
| Create New Bucket? | YES | [ ] YES — I will create it [ ] NO — using existing |
| Bucket Compartment OCID | Same as OCI_COMPARTMENT_OCID | _______________ if different |

**To create the bucket (run on ZDM server as zdmuser):**
```bash
# Get namespace:
oci os ns get

# Create bucket:
oci os bucket create \
  --compartment-id ocid1.compartment.oc1..aaaaaaaas4upnqj72dfiivgwvn3uui5gkxo7ng6leeoifucbjiy326urbhmq \
  --name zdm-migration-oradb-20260303 \
  --region uk-london-1
```

After creation, update `zdm-env.md`:
- `OCI_OSS_NAMESPACE: <your-namespace>`
- `OCI_OSS_BUCKET_NAME: zdm-migration-oradb-20260303`

---

## Section D: Migration Options

### D.1 Data Guard Configuration (ONLINE_PHYSICAL only)

**Recommended:** MAXIMUM_PERFORMANCE with ASYNC transport for cross-network (Azure → OCI) migration.

| Option | Recommended | Your Selection |
|--------|-------------|----------------|
| Protection Mode | `MAXIMUM_PERFORMANCE` | [ ] MAX_PERFORMANCE [ ] MAX_AVAILABILITY |
| Redo Transport | `ASYNC` | [ ] ASYNC [ ] SYNC |

> **Justification:** ASYNC avoids source database performance impact during cross-network replication. MAXIMUM_PERFORMANCE allows the primary to continue without waiting for standby acknowledgement. Switch to MAXIMUM_AVAILABILITY only if you require zero data loss.

---

### D.2 Auto Switchover

| Option | Recommended | Your Selection |
|--------|-------------|----------------|
| Auto Switchover | `NO` (manual control) | [ ] YES — ZDM switches over automatically [ ] NO — I will trigger switchover manually |

> **Recommended NO:** Pause at `ZDM_SWITCHOVER_SRC` and manually validate the standby before triggering switchover. This gives you control over the exact cutover moment and allows application-level validation.

---

### D.3 Pause Points

ZDM can pause at key steps to allow manual validation.

| Pause Point | Recommended | Your Selection |
|-------------|-------------|----------------|
| `ZDM_CONFIGURE_DG_SRC` | Optional | [ ] Pause [ ] Skip |
| `ZDM_SWITCHOVER_SRC` | **YES — Recommended** | [X] Pause [ ] Skip |
| No pauses (run to completion) | Not recommended | [ ] |

> **Recommended:** Pause at `ZDM_SWITCHOVER_SRC`. Before switchover, verify:
> - Target database is synchronized (apply lag ≈ 0)
> - Application connectivity to target is confirmed
> - Stakeholders are available for validation

---

### D.4 Post-Migration Cleanup

| Option | Recommended | Your Selection |
|--------|-------------|----------------|
| Delete OCI backup after migration | `NO` (keep for rollback 7 days) | [ ] YES [ ] NO |
| Delete source database after switchover | `NO` (manual decommission) | [ ] YES [ ] NO |

---

## Section E: TDE Keystore Password

Even though the source database does **not** use TDE, the ODAA target requires a TDE keystore password to be set during `ZDM_SETUP_TDE_TGT`. ZDM will prompt for this if the `-tdekeystorepasswd` flag is used.

| Field | Notes | Your Value |
|-------|-------|------------|
| TDE Keystore Password | 🔐 Will be passed as `-tdekeystorepasswd` at runtime — NOT stored in RSP file | _______________ |

> **Recommendation:** Choose a strong password and store it in a secure vault (Azure Key Vault or OCI Vault). This password will be used to open the TDE wallet on the target after migration.

---

## Section F: Network Connectivity Confirmation

### F.1 ZDM → Source SSH

| Check | Expected | Result |
|-------|----------|--------|
| ZDM server (10.1.0.8) can SSH to source (10.1.0.11) as azureuser | ✅ Should work (same VNet 10.1.0.0/24) | [ ] Verified [ ] Needs testing |

```bash
# Test from ZDM server:
sudo -u zdmuser ssh -i ~/.ssh/odaa.pem azureuser@10.1.0.11 "echo ok"
```

### F.2 ZDM → Target SSH

| Check | Expected | Result |
|-------|----------|--------|
| ZDM server (10.1.0.8) can SSH to target (10.0.1.160) as opc | ⚠️ Cross-network (10.1.x.x → 10.0.x.x); requires ExpressRoute/VPN | [ ] Verified [ ] Needs testing |

```bash
# Test from ZDM server:
sudo -u zdmuser ssh -i ~/.ssh/odaa.pem opc@10.0.1.160 "echo ok"
```

### F.3 Network Bandwidth Estimate

| Field | Notes | Your Value |
|-------|-------|------------|
| Connectivity Type | ExpressRoute / VPN / Public Internet | _______________ |
| Available Bandwidth (Mbps) | Used to estimate backup transfer time | _______________ |
| Estimated Transfer Time | Source DB = 2.14 GB → at 100 Mbps ≈ 3 min | _______________ |

---

## Section G: Application Cutover Coordination

| Field | Notes | Your Value |
|-------|-------|------------|
| Application Teams to Notify | Teams with connections to ORADB1 | _______________ |
| Connection String Update Required? | YES — point apps to new OCI target after switchover | [ ] YES [ ] NO |
| Rollback Window | Time after switchover during which you can roll back | _______________ (Recommended: 24–48 hours) |

> **Note:** After ZDM online switchover, the source becomes a Data Guard standby. It can be re-promoted if rollback is needed within the rollback window (before decommissioning the source).

---

## Section H: Completion Checklist

Before proceeding to Step 3, confirm:

| # | Item | Status |
|---|------|--------|
| 1 | Section A: Migration method selected | [ ] Complete |
| 2 | Section A: Target DB unique name confirmed | [ ] Complete |
| 3 | Section A: PDB mapping confirmed | [ ] Complete |
| 4 | Section B: All OCI OCIDs verified | [ ] Complete |
| 5 | Section B: OCI CLI working under zdmuser on ZDM server | [ ] Complete |
| 6 | Section C: OCI Object Storage bucket created and namespace filled in zdm-env.md | [ ] Complete (or N/A if OFFLINE) |
| 7 | Section D: Data Guard and switchover options confirmed | [ ] Complete |
| 8 | Section E: TDE keystore password prepared | [ ] Complete |
| 9 | Section F: SSH connectivity verified (ZDM → Source, ZDM → Target) | [ ] Complete |
| 10 | Discovery Summary reviewed for ⚠️ actions | [ ] Complete |

---

**Completed By:** _______________
**Review Date:** _______________

---

## Next Steps

After completing this questionnaire:

1. ✅ Address all ⚠️ actions from the [Discovery Summary](Discovery-Summary-ORADB.md)
2. ✅ Run `Step2-Fix-Issues.prompt.md` to resolve any outstanding issues
3. Once all issues are resolved, run `Step3-Generate-Migration-Artifacts.prompt.md` with:
   - This completed questionnaire
   - The Discovery Summary
   - The Issue Resolution Log from Step 2
