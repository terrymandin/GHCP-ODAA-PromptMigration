# Migration Questionnaire — ORADB

| Field | Value |
|---|---|
| **Project** | ORADB |
| **Document** | Migration Questionnaire |
| **Status** | ⚠️ INCOMPLETE — items marked ❓ require stakeholder input |
| **Related Summary** | [Discovery-Summary-ORADB.md](Discovery-Summary-ORADB.md) |
| **Instructions** | Review each section. Pre-populated values come from zdm-env.md or discovery. Replace all `❓ [REQUIRED]` and `❓ [DECISION]` entries before proceeding to Step 2 (Fix Issues) or Step 3 (Generate Migration Artifacts). |

---

## Section A: Migration Method & Timing

### A.1 Migration Method Selection

> **Context**: Source database is currently in NOARCHIVELOG mode.
> - `ONLINE_PHYSICAL` requires ARCHIVELOG + Force Logging to be enabled first (see Discovery Summary ACTION-01, ACTION-02).
> - `OFFLINE_PHYSICAL` can proceed immediately but requires scheduled downtime.
> - `ONLINE_LOGICAL` (GoldenGate) is not recommended for this workload.
>
> **Recommendation**: `ONLINE_PHYSICAL` after completing prerequisite enabling of ARCHIVELOG.

| Question | Answer |
|---|---|
| **Selected migration method** | ❓ [DECISION] `ONLINE_PHYSICAL` (recommended) or `OFFLINE_PHYSICAL` |
| **Rationale / notes** | ❓ [OPTIONAL] e.g. "Maintenance window available Sat 02:00–06:00, prefer online" |

### A.2 Migration Schedule

| Question | Answer |
|---|---|
| **Target migration start date** | ❓ [REQUIRED] e.g. `2026-03-15` |
| **Maintenance window (for switchover / cutover)** | ❓ [REQUIRED] e.g. `Saturday 02:00–05:00 UTC` |
| **Maximum acceptable downtime (minutes)** | ❓ [REQUIRED] e.g. `30` |
| **Business freeze/blackout window start** | ❓ [REQUIRED] e.g. `2026-03-15 01:45 UTC` |
| **Application team contact for cutover** | ❓ [REQUIRED] Name / email / Slack handle |
| **DBA contact (source)** | ❓ [REQUIRED] Name / contact |
| **DBA contact (target / ODAA)** | ❓ [REQUIRED] Name / contact |
| **Rollback decision time (minutes after switchover)** | ❓ [DECISION] e.g. `60` — if issues found within this window, roll back to source |

### A.3 ZDM Migration Type Parameters (Physical)

| Parameter | Value |
|---|---|
| **ZDM_MIGRATION_METHOD** | ❓ [DECISION] `ONLINE_PHYSICAL` or `OFFLINE_PHYSICAL` |
| **ZDM_SRC_DB_ENV** | `ON_PREM` |
| **ZDM_TGT_DB_ENV** | `ORACLE_DATABASE_AT_AZURE` (ODAA Exadata) |
| **Transfer medium** | `OSS` (OCI Object Storage) |

---

## Section B: OCI & Identity Configuration

> These values are pre-populated from `zdm-env.md`. Verify each is correct and active.

### B.1 OCI Identity

| Parameter | Value | Status |
|---|---|---|
| **OCI Tenancy OCID** | `ocid1.tenancy.oc1..aaaaaaaarvyhjcn7wkkxxx5g3o7lgqks23bmsjtsticz3gtg5xs5qyrwkftq` | ✅ From zdm-env.md |
| **OCI User OCID** | `ocid1.user.oc1..aaaaaaaakfe5cirdq7vkkrhogjrgcrgftvwb7mdoehujgchefpqv54vhsnoa` | ✅ From zdm-env.md |
| **OCI Compartment OCID** | `ocid1.compartment.oc1..aaaaaaaas4upnqj72dfiivgwvn3uui5gkxo7ng6leeoifucbjiy326urbhmq` | ✅ From zdm-env.md |
| **OCI Region** | `uk-london-1` | ✅ From ZDM OCI config |
| **OCI API Key Fingerprint** | `7f:05:c1:f2:5c:3a:46:ec:9f:95:44:c8:77:a4:50:f9` | ✅ From zdm-env.md |
| **OCI Config File Path (zdmuser)** | `/home/zdmuser/.oci/config` | ✅ Discovered on ZDM server |
| **OCI Private Key Path (zdmuser)** | ❓ [VERIFY] Path in zdmuser OCI config — confirm key file is at path listed | ⚠️ Masked in discovery |

### B.2 OCI Target Database

| Parameter | Value | Status |
|---|---|---|
| **Target Database OCID** | `ocid1.database.oc1.uk-london-1.anwgiljss56liuaatz45cjnpbvpgku7gkorvxg6lytoj5lxxruk2eqxzkzma` | ✅ From zdm-env.md |
| **Target DB Name (ODAA)** | ❓ [VERIFY] Confirm target CDB name on ODAA console | Existing offline DBs found: `migdb`, `mydb`, `oradb01m` |
| **Target PDB Name** | ❓ [DECISION] Name for migrated PDB on target e.g. `ORADB1PDB` | ZDM auto-creates PDB within target CDB |

### B.3 OCI Object Storage

| Parameter | Value | Status |
|---|---|---|
| **OCI Object Storage Namespace** | ❓ [REQUIRED] Run: `oci os ns get` as zdmuser on ZDM server | ❌ BLANK in zdm-env.md |
| **OCI OSS Bucket Name** | ❓ [REQUIRED] Create bucket, then record name here (suggested: `zdm-oradb-migration`) | ❌ BLANK in zdm-env.md |
| **Bucket Region** | `uk-london-1` | Must match OCI region |
| **Bucket Compartment** | Same as OCI_COMPARTMENT_OCID above | ✅ |
| **Bucket Retention / Cleanup** | ❓ [DECISION] Auto-delete migration artifacts after how many days? e.g. `30` | |

---

## Section C: Infrastructure Configuration

### C.1 Source Database Server

| Parameter | Value | Status |
|---|---|---|
| **Source Host / IP** | `10.1.0.11` | ✅ From zdm-env.md |
| **Source SSH User** | `azureuser` | ✅ From zdm-env.md |
| **Source SSH Key** | `~/.ssh/odaa.pem` (zdmuser) | ✅ Key confirmed in zdmuser ~/.ssh/ |
| **Source Oracle SID** | `oradb` | ✅ Discovered |
| **Source DB Unique Name** | `oradb1` | ✅ Discovered |
| **Source ORACLE_HOME** | `/u01/app/oracle/product/12.2.0/dbhome_1` | ✅ Discovered |
| **Source ORACLE_BASE** | `/u01/app/oracle` | ✅ Derived |
| **Source DB admin user** | `SYS` | Standard |
| **Source DB admin password** | ❓ [REQUIRED] SYS password for source ORADB — store in ZDM credential file | Sensitive — do not put in plain text |
| **Source admin SSH sudo required?** | ❓ [VERIFY] Does `azureuser` have passwordless sudo to `oracle` on source? | Required for file operations |

### C.2 Target Database Server

| Parameter | Value | Status |
|---|---|---|
| **Target Host / IP** | `10.0.1.160` (node 1) | ✅ From zdm-env.md |
| **Target SSH User** | `opc` | ✅ From zdm-env.md |
| **Target SSH Key** | `~/.ssh/odaa.pem` (zdmuser) | ✅ Key confirmed in zdmuser ~/.ssh/ |
| **Target ORACLE_HOME** | `/u02/app/oracle/product/19.0.0.0/dbhome_1` | ✅ From /etc/oratab |
| **Target Grid Home** | `/u01/app/19.0.0.0/grid` | ✅ Discovered |
| **Target ASM Disk Group (Data)** | `+DATAC3` | ✅ Discovered (4.1 TB free) |
| **Target ASM Disk Group (Reco)** | `+RECOC3` | ✅ Discovered (1.0 TB free) |
| **Target DB admin user** | `SYS` | Standard |
| **Target DB admin password** | ❓ [REQUIRED] SYS password for target CDB — store in ZDM credential file | Sensitive |
| **Target DB TDE wallet password** | ❓ [REQUIRED] Wallet password for target — needed to create TDE master key | Sensitive |
| **Target admin SSH sudo required?** | ❓ [VERIFY] Does `opc` have passwordless sudo to `oracle` on target? | |

### C.3 ZDM Server

| Parameter | Value | Status |
|---|---|---|
| **ZDM Host / IP** | `10.1.0.8` | ✅ From zdm-env.md |
| **ZDM SSH User** | `azureuser` | ✅ From zdm-env.md |
| **ZDM SSH Key** | `~/.ssh/zdm.pem` | ✅ From zdm-env.md |
| **ZDM_HOME** | `/u01/app/zdmhome` | ✅ Discovered |
| **ZDM service URL** | `jdbc:mysql://localhost:8899/` | ✅ Discovered |
| **ZDM run user** | `zdmuser` | ✅ Discovered |

---

## Section D: Database Configuration Decisions

### D.1 Archive Log Mode (Pre-Migration)

| Question | Answer |
|---|---|
| **Will ARCHIVELOG be enabled before migration?** | ❓ [DECISION] `YES` (required for ONLINE_PHYSICAL) or `NO` (use OFFLINE_PHYSICAL) |
| **Archive log destination path** | ❓ [REQUIRED if YES] e.g. `/u01/app/oracle/archive` — ensure sufficient disk space first |
| **Who will perform the ARCHIVELOG change?** | ❓ [REQUIRED] Source DBA name |
| **Estimated time to enable (including restart)** | ❓ [ESTIMATE] e.g. `30 minutes` |
| **Notification required before source restart?** | ❓ [DECISION] `YES` / `NO` — list teams to notify |

### D.2 Data Guard / Replication Settings (ONLINE_PHYSICAL only)

| Question | Answer |
|---|---|
| **Target DB Unique Name (for DG)** | ❓ [DECISION] e.g. `oradb1_odaa` — must be unique globally |
| **Desired Data Guard protection mode** | ❓ [DECISION] `MAXIMUM_PERFORMANCE` (recommended, async) or `MAXIMUM_AVAILABILITY` (sync, adds latency) |
| **Redo log transport mode** | `ASYNC` (for MAXIMUM_PERFORMANCE) — auto-set by ZDM |
| **FAL server (for log gap resolution)** | ❓ [OPTIONAL] If needed, specify source DB service name |
| **Standby member VIP (target SCAN)** | ❓ [VERIFY] SCAN hostname for target — confirm from OCI console or DNS |

### D.3 Character Set Compatibility

| Source | Target | Compatible? |
|---|---|---|
| AL32UTF8 | ❓ [VERIFY] Confirm target CDB character set via ODAA console | Must match or be a superset |
| AL16UTF16 (NCHAR) | ❓ [VERIFY] Confirm target NCHAR character set | Must match |

> If character sets do not match, ZDM will report an error during the migration setup phase.

### D.4 Parallel Degree for Migration

| Question | Answer |
|---|---|
| **RMAN backup parallelism** | ❓ [DECISION] e.g. `4` — based on source CPU count and I/O capacity |
| **OSS upload parallel streams** | ❓ [DECISION] e.g. `4` |
| **Target RMAN restore parallelism** | ❓ [DECISION] e.g. `4` |

### D.5 Existing Databases on Target

> **Noted**: Three existing databases (migdb, mydb, oradb01m) are OFFLINE on target. `/u02` filesystem is 75% full (14 GB free).

| Question | Answer |
|---|---|
| **Should existing offline DBs be removed before migration?** | ❓ [DECISION] `YES` (recommended to free /u02 space) / `NO` (keep for reference) |
| **Which DBs to remove?** | ❓ [DECISION] e.g. `migdb`, `mydb`, `oradb01m` — confirm with ODAA team |

### D.6 Source Backup Prior to Migration

| Question | Answer |
|---|---|
| **Will a full RMAN backup be taken before starting ZDM?** | ❓ [DECISION] `YES` (strongly recommended) / `NO` |
| **Backup destination** | ❓ [REQUIRED if YES] e.g. `/u01/app/oracle/fast_recovery_area` or OCI Object Storage |
| **Backup retention period** | ❓ [DECISION] e.g. `7 days` |

---

## Section E: Post-Migration & Validation

### E.1 Application Connectivity

| Question | Answer |
|---|---|
| **Application connection strings** | ❓ [REQUIRED] List all applications connecting to source ORADB. Include service names and protocol (JDBC/ODBC/OCI) |
| **Connection failover mechanism** | ❓ [DECISION] `SCAN` (recommended for RAC target) / `VIP` / `single-node` |
| **Target SCAN hostname/address** | ❓ [REQUIRED] SCAN DNS name or IP from OCI / ODAA console |
| **New JDBC connect string (example)** | ❓ [REQUIRED] e.g. `jdbc:oracle:thin:@<SCAN_HOST>:1521/pdb1.<domain>` |

### E.2 Migration Switchover / Cutover

| Question | Answer |
|---|---|
| **Who has approval authority to execute switchover?** | ❓ [REQUIRED] Name / role |
| **Post-switchover application smoke test owner** | ❓ [REQUIRED] App team name / contact |
| **Smoke test checklist available?** | ❓ [DECISION] `YES` — attach or link / `NO` — create during Step 2 |
| **Expected smoke test duration (minutes)** | ❓ [ESTIMATE] e.g. `20` |

### E.3 Rollback Plan

| Question | Answer |
|---|---|
| **Rollback strategy** | ❓ [DECISION] `FLASHBACK` (ZDM configures Guaranteed Restore Point on source) or `RE-SWITCHOVER` |
| **Rollback decision window (minutes post-switchover)** | ❓ [DECISION] e.g. `60` |
| **Who initiates rollback?** | ❓ [REQUIRED] Named DBA or team |
| **Rollback communication plan** | ❓ [REQUIRED] How is rollback decision communicated to app team and stakeholders? |

### E.4 Post-Migration Validation Checks

The following checks should be executed after switchover:

| Check | Owner | Expected Result |
|---|---|---|
| Source database status | DBA | `READ ONLY WITH APPLY` (if ONLINE_PHYSICAL post-switchover) |
| Target PDB open mode | DBA | `READ WRITE` |
| Tablespace counts match | DBA | Match source tablespace inventory |
| Row counts on key tables | App DBA | ❓ [REQUIRED] Identify 5–10 critical tables for row count comparison |
| Application login test | App team | Successful login with new connection string |
| Transaction write test | App team | INSERT/UPDATE/DELETE succeeds on target |
| OCI console DB status | ODAA admin | Green / Available |

### E.5 DNS / Connection String Update

| Question | Answer |
|---|---|
| **DNS entry to update** | ❓ [REQUIRED] Hostname/alias currently pointing to source DB |
| **DNS TTL (seconds) — set low before migration** | ❓ [DECISION] e.g. `60` seconds |
| **Who manages DNS update?** | ❓ [REQUIRED] Network / infra team contact |
| **DNS update timing** | Before or after application switchover? ❓ [DECISION] |

### E.6 Monitoring & Alerting

| Question | Answer |
|---|---|
| **Monitoring tool for target DB** | ❓ [REQUIRED] e.g. OCI Ops Insights, Enterprise Manager, custom |
| **Alert recipients for migration events** | ❓ [REQUIRED] Email address(es) / PagerDuty integration |
| **Log aggregation for migration logs** | ❓ [DECISION] Log path on ZDM server: `/u01/app/zdmhome/log/tm-vm-odaa-oracle-jumpbox/` |

---

## Pre-Flight Summary

Before proceeding to Step 2 (Fix Issues), confirm the following minimum required fields are populated:

| # | Item | Status |
|---|---|---|
| 1 | Migration method selected (A.1) | ❓ |
| 2 | Migration date / maintenance window (A.2) | ❓ |
| 3 | OCI OSS Namespace (B.3) | ❓ |
| 4 | OCI OSS Bucket Name (B.3) | ❓ |
| 5 | Source SYS password available (C.1) | ❓ |
| 6 | Target SYS password available (C.2) | ❓ |
| 7 | Target TDE wallet password available (C.2) | ❓ |
| 8 | ARCHIVELOG enablement plan confirmed (D.1) | ❓ |
| 9 | Target DB Unique Name for DG decided (D.2) | ❓ |
| 10 | Target SCAN hostname confirmed (E.1) | ❓ |
| 11 | Rollback window and strategy confirmed (E.3) | ❓ |
| 12 | Application smoke test plan defined (E.2) | ❓ |

---

*Generated by GitHub Copilot — ODAA Migration Accelerator*
*Pre-populated from zdm-env.md and discovery run: 2026-02-27 21:36 UTC*
