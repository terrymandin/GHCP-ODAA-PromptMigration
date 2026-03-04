# Migration Planning Questionnaire: ORADB
## Items Requiring Manual Input

> **Instructions:** Review each question, confirm or update the recommended default, and enter the actual value in the `Answer` field.
> Completed answers will be used to populate the ZDM response file in Step 3.
>
> **Discovery Date:** 2026-03-03
> **Source:** tm-oracle-iaas (10.1.0.11) → Oracle 12.2.0.1 CDB (ORADB1)
> **Target:** tmodaauks-rqahk1 / ODAA (10.0.1.160) → Oracle 19c ExaDB-D

---

## Section A: Migration Strategy Decisions

### A1 — Migration Method

| | |
|---|---|
| **Question** | Should this migration use Online (zero-downtime) or Offline (maintenance window) Physical migration? |
| **Recommended Default** | **ONLINE_PHYSICAL** |
| **Justification** | Source is in ARCHIVELOG mode with Force Logging enabled. Data size is small (2.15 GB). Online physical migration via Data Guard minimizes downtime to the switchover window only (typically minutes). No blocking TDE or supplemental logging issues for physical method. |
| **Answer** | ☐ `ONLINE_PHYSICAL` &nbsp;&nbsp; ☐ `OFFLINE_PHYSICAL` |

---

### A2 — Planned Migration Date / Maintenance Window

| | |
|---|---|
| **Question** | What is the target migration date and switchover maintenance window? |
| **Recommended Default** | Schedule during off-peak hours; allow a 2–4 hour maintenance window for switchover and validation |
| **Answer** | **Date:** _______________ &nbsp;&nbsp; **Window Start:** _______________ &nbsp;&nbsp; **Window End:** _______________ |

---

### A3 — Maximum Acceptable Downtime

| | |
|---|---|
| **Question** | What is the maximum application downtime acceptable during switchover? |
| **Recommended Default** | `< 30 minutes` (online physical switchover is typically 5–15 minutes for this database size) |
| **Answer** | _______________ minutes |

---

### A4 — Target Oracle Home Path

| | |
|---|---|
| **Question** | What is the Oracle Database Home path on the ODAA target node to use for the migration? |
| **Recommended Default** | `/u02/app/oracle/product/19.0.0.0/dbhome_1` |
| **Justification** | Based on prior successful EVAL jobs (Jobs 16–17) which used `dbhome_1`. Recent ORADB-specific jobs (27–34) used `dbhome_2` and still failed at `ZDM_VALIDATE_TGT` for TDE reasons (not home path). Confirm which home contains the `oradb011` instance. |
| **Answer** | `/u02/app/oracle/product/19.0.0.0/dbhome_` ___ (`1` or `2`) |
| **ZDM Parameter** | `-targethome` |

---

### A5 — Target ZDM Node (sourcenode/targetnode)

| | |
|---|---|
| **Question** | Which ODAA node should ZDM connect to as the target node? |
| **Recommended Default** | `10.0.1.160` (tmodaauks-rqahk1, Node 1 — matches `TARGET_HOST` in `zdm-env.md`) |
| **Justification** | The ZDM server `/etc/hosts` shows a 2-node ODAA cluster (rqahk1 and rqahk2). ZDM typically connects to the first node (or the node where the DB is currently running). Confirm which node hosts the active `oradb011` instance. |
| **Answer** | ☐ `10.0.1.160` (rqahk1 / Node 1) &nbsp;&nbsp; ☐ `10.0.1.114` (rqahk2 / Node 2) |
| **ZDM Parameter** | `-targetnode` |

---

## Section B: OCI/Azure Identifiers 🔐

> Items marked ✅ are already populated in `zdm-env.md`. Items marked ⚠️ require manual entry.

### B1 — OCI Tenancy OCID

| | |
|---|---|
| **Status** | ✅ Configured in `zdm-env.md` |
| **Current Value** | `ocid1.tenancy.oc1..aaaaaaaarvyhjcn7wkkxxx5g3o7lgqks23bmsjtsticz3gtg5xs5qyrwkftq` |
| **Confirm Value** | ☐ Confirmed &nbsp;&nbsp; ☐ Update to: _______________ |

---

### B2 — OCI User OCID

| | |
|---|---|
| **Status** | ✅ Configured in `zdm-env.md` |
| **Current Value** | `ocid1.user.oc1..aaaaaaaakfe5cirdq7vkkrhogjrgcrgftvwb7mdoehujgchefpqv54vhsnoa` |
| **Confirm Value** | ☐ Confirmed &nbsp;&nbsp; ☐ Update to: _______________ |

---

### B3 — OCI Compartment OCID

| | |
|---|---|
| **Status** | ✅ Configured in `zdm-env.md` |
| **Current Value** | `ocid1.compartment.oc1..aaaaaaaas4upnqj72dfiivgwvn3uui5gkxo7ng6leeoifucbjiy326urbhmq` |
| **Confirm Value** | ☐ Confirmed &nbsp;&nbsp; ☐ Update to: _______________ |

---

### B4 — OCI Region

| | |
|---|---|
| **Status** | ⚠️ Not explicitly set in `zdm-env.md` |
| **Recommended Default** | `uk-london-1` (inferred from `TARGET_DATABASE_OCID` which contains `oc1.uk-london-1`) |
| **Answer** | _______________ |
| **ZDM RSP Parameter** | `COMMON_BACKUP_OSS_REGION` |

---

### B5 — Target DB System OCID

| | |
|---|---|
| **Status** | ⚠️ Not separately listed in `zdm-env.md` |
| **Note** | The `TARGET_DATABASE_OCID` is for the database (not the DB system). Identify the DB System OCID if needed for OCI operations. |
| **Answer** | `ocid1.dbsystem.oc1...` _______________ |

---

### B6 — Target Database OCID

| | |
|---|---|
| **Status** | ✅ Configured in `zdm-env.md` |
| **Current Value** | `ocid1.database.oc1.uk-london-1.anwgiljss56liuaatz45cjnpbvpgku7gkorvxg6lytoj5lxxruk2eqxzkzma` |
| **Confirm Value** | ☐ Confirmed &nbsp;&nbsp; ☐ Update to: _______________ |
| **ZDM RSP Parameter** | `MIGRATION_METHOD` + target DB identifier |

---

### B7 — Target DB Unique Name

| | |
|---|---|
| **Status** | ⚠️ Not in `zdm-env.md` — inferred from discovery |
| **Recommended Default** | `oradb01` (inferred from listener services: `oradb01m`, `oradb01pdb`, `oradb01XDB`) |
| **Answer** | _______________ |
| **ZDM Parameter** | `-targetdb` or `TGT_DB_UNIQUE_NAME` in RSP |

---

### B8 — OCI API Key Fingerprint

| | |
|---|---|
| **Status** | ✅ Configured in `zdm-env.md` |
| **Current Value** | `7f:05:c1:f2:5c:3a:46:ec:9f:95:44:c8:77:a4:50:f9` |
| **Confirm Value** | ☐ Confirmed &nbsp;&nbsp; ☐ Update to: _______________ |

---

### B9 — OCI API Private Key Location (zdmuser context)

| | |
|---|---|
| **Status** | ⚠️ Needs verification — OCI config not yet created on ZDM server |
| **Recommended Default** | `/home/zdmuser/.oci/oci_api_key.pem` |
| **Justification** | ZDM operations run as `zdmuser`. The private key must be accessible to zdmuser. `zdm-env.md` references `~/.oci/oci_api_key.pem`; confirm the key has been placed in zdmuser's home. |
| **Answer** | _______________ |

---

## Section C: Object Storage Configuration

### C1 — OCI Object Storage Namespace

| | |
|---|---|
| **Status** | ⚠️ NOT configured in `zdm-env.md` (blank) |
| **How to Find** | Run: `oci os ns get --config-file /home/zdmuser/.oci/config` on ZDM server (after OCI CLI configured) |
| **Answer** | _______________ |
| **ZDM RSP Parameter** | `COMMON_BACKUP_OSS_NAMESPACE` |

---

### C2 — OCI Object Storage Bucket Name

| | |
|---|---|
| **Status** | ⚠️ NOT configured in `zdm-env.md` (blank) |
| **Recommended Default** | `zdm-oradb-migration` (create new dedicated bucket) |
| **Justification** | A dedicated bucket simplifies cleanup and access management. Bucket should be in the same tenancy and region as the ODAA target. |
| **Answer** | _______________ |
| **ZDM RSP Parameter** | `COMMON_BACKUP_OSS_BUCKET` |

---

### C3 — OCI Object Storage Bucket Region

| | |
|---|---|
| **Status** | ⚠️ Confirm with namespace |
| **Recommended Default** | `uk-london-1` (inferred from TARGET_DATABASE_OCID region) |
| **Answer** | _______________ |
| **ZDM RSP Parameter** | `COMMON_BACKUP_OSS_REGION` |

---

## Section D: Migration Options

### D1 — Data Guard Protection Mode

| | |
|---|---|
| **Question** | What Data Guard protection mode should be configured during the migration replication phase? |
| **Recommended Default** | `MAX_PERFORMANCE` |
| **Justification** | Source and target are connected over ExpressRoute/VPN with cross-cloud network. `MAX_PERFORMANCE` provides the best throughput with asynchronous redo shipping, reducing the chance of source performance impact. `MAX_AVAILABILITY` can be considered if data loss policy requires synchronous apply. |
| **Answer** | ☐ `MAX_PERFORMANCE` &nbsp;&nbsp; ☐ `MAX_AVAILABILITY` &nbsp;&nbsp; ☐ `MAX_PROTECTION` |
| **ZDM RSP Parameter** | `ONLINE_STANDBY_DG_PROTECTION_MODE` |

---

### D2 — Auto Switchover

| | |
|---|---|
| **Question** | Should ZDM automatically perform switchover after replication lag is minimized, or pause for manual confirmation? |
| **Recommended Default** | **Pause for manual confirmation** (set pause point at `ZDM_SWITCHOVER_SRC`) |
| **Justification** | For a first migration of this environment, it is advisable to pause before switchover to allow the DBA/application team to verify the standby database is synchronized and applications are ready to redirect. |
| **Answer** | ☐ Auto switchover &nbsp;&nbsp; ☐ Pause at `ZDM_SWITCHOVER_SRC` for manual confirmation |
| **ZDM RSP Parameter** | `PAUSEAFTER` |

---

### D3 — Pause Points

| | |
|---|---|
| **Question** | At which ZDM migration phases should the job pause for manual validation? |
| **Recommended Default** | Pause after `ZDM_VALIDATE_TGT` and `ZDM_SWITCHOVER_SRC` |
| **Justification** | Pausing after target validation allows DBAs to inspect the standby database before data transfer begins. Pausing before switchover allows application owners to confirm. |
| **Answer (select all desired)** | ☐ After `ZDM_VALIDATE_TGT` &nbsp;&nbsp; ☐ After `ZDM_CONFIGURE_DG_SRC` &nbsp;&nbsp; ☐ After `ZDM_SWITCHOVER_SRC` &nbsp;&nbsp; ☐ None |
| **ZDM RSP Parameter** | `PAUSEAFTER` (comma-separated list) |

---

### D4 — TDE Strategy

| | |
|---|---|
| **Question** | How should TDE be handled? The source has no TDE configured; the target ODAA wallet has no master key. |
| **Recommended Default** | **Enable TDE on source before migration (recommended for ODAA)** |
| **Justification** | ODAA (ExaDB-D) requires TDE to be enabled. ZDM can configure TDE on the source as part of the migration, or it can be pre-configured by the DBA. If `-tdekeystorepasswd` is used in ZDM CLI, a TDE wallet password must be set. Prior job attempts with TDE failed at `ZDM_VALIDATE_TGT` — confirm if this was due to missing TDE or other reasons. |
| **Options** | ☐ Pre-configure TDE on source (DBA action before Step 3) &nbsp;&nbsp; ☐ Let ZDM configure TDE &nbsp;&nbsp; ☐ Confirm TDE not required and omit flag |
| **Answer** | _______________ |
| **ZDM Parameter** | `-tdekeystorepasswd` (if TDE in use) |

---

### D5 — Source SSH User / Key Confirmation

| | |
|---|---|
| **Question** | Which SSH user and key should ZDM use to connect to the source database server? |
| **Current zdm-env.md Setting** | `SOURCE_SSH_USER: azureuser`, `SOURCE_SSH_KEY: ~/.ssh/odaa.pem` |
| **Observed in ZDM Job History** | Recent ORADB jobs used `user:temandin` with `iaas.pem` for source |
| **Recommended Default** | `user: azureuser`, key: `/home/zdmuser/.ssh/iaas.pem` |
| **Justification** | The ZDM server holds `iaas.pem` as the source key (separate from `odaa.pem` for target). `zdm-env.md` should be updated to reference `iaas.pem` for `SOURCE_SSH_KEY`. |
| **Answer** | **User:** _______________ &nbsp;&nbsp; **Key:** `/home/zdmuser/.ssh/` _______________ (iaas.pem / odaa.pem) |
| **ZDM Parameter** | `-srcarg1 user:<user>` `-srcarg2 identity_file:<key>` |

---

## Section E: Network Configuration

### E1 — Connectivity Type (Source Azure → Target OCI)

| | |
|---|---|
| **Question** | What network path connects the Azure source environment to the OCI ODAA target? |
| **Recommended Default** | **Azure ExpressRoute ↔ OCI FastConnect** (expected for ODAA on Azure topology) |
| **Justification** | The ZDM server is on Azure (`10.1.0.8/24`); target is on OCI (`10.0.1.x/24`). These subnets communicate over an interconnect. Confirm the interconnect type and estimated available bandwidth. |
| **Answer** | ☐ ExpressRoute ↔ FastConnect &nbsp;&nbsp; ☐ Site-to-Site VPN &nbsp;&nbsp; ☐ Other: _______________ |

---

### E2 — Estimated Available Bandwidth

| | |
|---|---|
| **Question** | What is the estimated available network bandwidth between source and target during the migration? |
| **Recommended Default** | Confirm provisioned bandwidth of the ExpressRoute/FastConnect circuit |
| **Relevance** | Source data is 2.15 GB — even at 100 Mbps, initial backup transfer would complete in ~3 minutes. Redo shipping rate is approximately 0.17 GB/hour (low). Network is not expected to be a bottleneck. |
| **Answer** | _______________ Mbps / Gbps |

---

### E3 — Firewall / NSG Rules Confirmation

| | |
|---|---|
| **Question** | Have NSG/firewall rules been confirmed for ZDM traffic between the ZDM server and both source and target? |
| **Required Ports** | Port 22 (SSH) and Port 1521 (Oracle Listener) from ZDM server (10.1.0.8) to source (10.1.0.11) and target (10.0.1.160) |
| **Discovery Finding** | Ports 22 and 1521 confirmed OPEN to both nodes from ZDM server ✅ |
| **Answer** | ☐ Confirmed open &nbsp;&nbsp; ☐ Need to verify NSG rules on OCI side |

---

## Section F: Credentials (Do Not Store — Reference Only)

> **IMPORTANT:** Do not enter actual passwords in this document. The items below are a checklist confirming passwords have been set and are available to the migration team.

| Credential | Status | Notes |
|-----------|--------|-------|
| SYS password (source ORADB1) | ☐ Available | Required by ZDM for RMAN operations |
| SYS password (target oradb01) | ☐ Available | Required by ZDM; target password file must also exist (see Action #2 in Discovery Summary) |
| TDE wallet password (source) | ☐ Available / ☐ N/A | Required only if TDE is configured; if new TDE setup, set this password before migration |
| TDE wallet password (target) | ☐ Available / ☐ N/A | Target ODAA wallet has no master key — set after TDE strategy is confirmed |
| OCI API private key | ☐ Available at `/home/zdmuser/.oci/oci_api_key.pem` | Must match registered API fingerprint `7f:05:c1:...` |

---

## Summary Checklist Before Proceeding to Step 2 (Fix Issues)

| # | Item | Status |
|---|------|--------|
| 1 | Target Oracle Home path confirmed | ☐ |
| 2 | Target DB unique name confirmed | ☐ |
| 3 | Target password file created | ☐ |
| 4 | TDE strategy decided and actioned | ☐ |
| 5 | OCI CLI configured on ZDM server (`/home/zdmuser/.oci/config`) | ☐ |
| 6 | OCI API private key installed for zdmuser | ☐ |
| 7 | OCI Object Storage bucket created | ☐ |
| 8 | Source SSH key confirmed (`iaas.pem` vs `odaa.pem`) | ☐ |
| 9 | Migration method confirmed (ONLINE_PHYSICAL) | ☐ |
| 10 | Maintenance window scheduled | ☐ |
| 11 | All OCI OCIDs and Object Storage details entered above | ☐ |
| 12 | Credentials available and shared with migration team | ☐ |
