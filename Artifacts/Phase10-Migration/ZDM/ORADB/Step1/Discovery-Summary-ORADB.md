# Discovery Summary — ORADB Migration to Oracle Database@Azure

| Field | Value |
|---|---|
| **Project** | ORADB |
| **Document** | Discovery Summary |
| **Generated** | 2026-02-27 |
| **Discovery Run** | 2026-02-27 21:36 UTC |
| **Migration Tool** | Oracle Zero Downtime Migration (ZDM) |
| **Migration Target** | Oracle Database@Azure (Exadata X11M, UK South / uk-london-1) |

---

## 1. Executive Summary

### 1.1 Source Database

| Property | Value |
|---|---|
| **Hostname** | tm-oracle-iaas |
| **IP Address** | 10.1.0.11 |
| **OS** | Oracle Linux 7.4 |
| **Oracle Version** | 12.2.0.1.0 |
| **DB Name** | ORADB1 |
| **DB Unique Name** | oradb1 |
| **Oracle SID** | oradb |
| **Container DB (CDB)** | YES |
| **PDBs** | PDB$SEED (READ ONLY), PDB1 (READ WRITE) |
| **Character Set** | AL32UTF8 / AL16UTF16 (NCHAR) |
| **Database Role** | PRIMARY |
| **Protection Mode** | MAXIMUM PERFORMANCE / UNPROTECTED |
| **Total Data Size** | ~1.9 GB (data files) |
| **Temp Space** | ~0.03 GB |
| **Archive Log Mode** | ❌ NOARCHIVELOG |
| **Force Logging** | ❌ NO |
| **Supplemental Logging** | ❌ NONE |
| **TDE Status** | NOT_AVAILABLE (no encryption) |
| **RMAN Configured** | NO |
| **Data Guard** | NOT CONFIGURED (dg_broker_start=FALSE) |
| **ORACLE_HOME** | /u01/app/oracle/product/12.2.0/dbhome_1 |
| **Source Disk Free** | ~8.6 GB free on root (/ at 70% — TIGHT) |

### 1.2 Target Environment

| Property | Value |
|---|---|
| **Hostname (Node 1)** | tmodaauks-rqahk1 |
| **Hostname (Node 2)** | tmodaauks-rqahk2 |
| **IP (Node 1)** | 10.0.1.160 |
| **IP (Node 2)** | 10.0.1.114 |
| **VIP (Node 1)** | 10.0.1.155 |
| **VIP (Node 2)** | 10.0.1.142 |
| **OS** | Oracle Linux 8.10 |
| **Oracle Version** | 19.0.0.0.0 (Grid Infrastructure) |
| **ORACLE_HOME (DB)** | /u02/app/oracle/product/19.0.0.0/dbhome_1 |
| **Grid Home** | /u01/app/19.0.0.0/grid |
| **Cluster Type** | 2-Node RAC (Exadata X11M) |
| **Availability Domain** | uk-london-1-ad-2 |
| **Fault Domain** | FAULT-DOMAIN-2 |
| **ASM Disk Group (Data)** | DATAC3 (HIGH) — 4,896 GB total, **4,128 GB free** |
| **ASM Disk Group (Reco)** | RECOC3 (HIGH) — 1,224 GB total, **1,048 GB free** |
| **ACFS Mount** | /acfs01 (100 GB total, 88 GB free) |
| **TDE Wallet Status** | ⚠️ OPEN_NO_MASTER_KEY |
| **OCI CLI on Target** | ❌ NOT INSTALLED |
| **Existing DBs (state)** | migdb (OFFLINE), mydb (OFFLINE), oradb01m (OFFLINE) |
| **Listener Ports** | TCP:1521, TCPS:2484 on 10.0.1.160 / 10.0.1.155 |
| **OCI Region** | uk-london-1 |
| **TARGET_DATABASE_OCID** | ocid1.database.oc1.uk-london-1.anwgiljss56liuaatz45cjnpbvpgku7gkorvxg6lytoj5lxxruk2eqxzkzma |

### 1.3 ZDM Server

| Property | Value |
|---|---|
| **Hostname** | tm-vm-odaa-oracle-jumpbox |
| **IP Address** | 10.1.0.8 |
| **OS** | Oracle Linux 9.5 |
| **ZDM_HOME** | /u01/app/zdmhome |
| **ZDM Service Status** | ✅ Running (RMI:8897, HTTP:8898) |
| **ZDM CLI** | ✅ Found: /u01/app/zdmhome/bin/zdmcli |
| **Java** | ✅ Bundled JDK at /u01/app/zdmhome/jdk |
| **OCI CLI Version** | ✅ 3.73.1 |
| **OCI Config (azureuser)** | ❌ NOT FOUND at ~/.oci/config |
| **OCI Config (zdmuser)** | ✅ Found at /home/zdmuser/.oci/config (region: uk-london-1) |
| **OCI API Key (azureuser)** | ❌ NOT FOUND at ~/.oci/oci_api_key.pem |
| **ZDM Credential Store** | ❌ NOT FOUND at /u01/app/zdmhome/zdm/cred |
| **zdmuser SSH Keys** | ✅ iaas.pem, odaa.pem, zdm.pem, id_ed25519, id_rsa |
| **Source Ping (10.1.0.11)** | ✅ SUCCESS (0% loss, avg 1.576ms) |
| **Target Ping (10.0.1.160)** | ⚠️ ICMP BLOCKED (100% loss) — TCP ports 22 & 1521 OPEN |
| **Disk Free (/)** | 24 GB free of 39 GB (ZDM warnings are threshold false positives) |
| **Response File Templates** | zdm_logical_template.rsp, zdm_template.rsp, zdm_xtts_template.rsp |

---

## 2. Migration Assessment

### 2.1 Recommended Migration Method

| Method | Feasibility | Reason |
|---|---|---|
| **ONLINE_PHYSICAL** (Data Guard) | ⚠️ Requires pre-work | Source must be in ARCHIVELOG + Force Logging enabled first |
| **OFFLINE_PHYSICAL** (RMAN restore) | ✅ Immediately feasible | No ARCHIVELOG requirement; requires planned downtime |
| **ONLINE_LOGICAL** (GoldenGate) | ❌ Not recommended | Requires supplemental logging + GoldenGate license; overkill for 1.9 GB DB |

**Primary Recommendation: ONLINE_PHYSICAL** after enabling ARCHIVELOG and Force Logging on the source.

> This is the ZDM flagship method for Oracle-to-ODAA migrations. It uses Oracle Data Guard to replicate and then switches over with minimal downtime. Given the small database size (1.9 GB) and existing Exadata target, this is the optimal path. The pre-requisite work (ARCHIVELOG, Force Logging) must be completed before executing ZDM.

**Alternative: OFFLINE_PHYSICAL** if a scheduled maintenance window is acceptable.

> Requires taking the source database offline, performing an RMAN backup/restore to the target via OCI Object Storage or direct copy. Simpler configuration but causes downtime proportional to database size and network speed.

### 2.2 Version Upgrade Consideration

The migration involves an **implicit version upgrade from 12.2.0.1 → 19c**. ZDM physical migration handles this automatically via the Data Guard redo apply mechanism. No manual upgrade steps are required when using ONLINE_PHYSICAL or OFFLINE_PHYSICAL with ZDM.

### 2.3 CDB → CDB Migration

Source is a CDB with one user PDB (PDB1). The target Exadata also uses CDB architecture. ZDM will migrate PDB1 into a new CDB on the target. The target database OCID (`ocid1.database.oc1.uk-london-1.anwg...`) refers to the pre-provisioned target CDB container.

---

## 3. Configuration Status Checklist

| Check | Status | Impact | Action Required |
|---|---|---|---|
| **Source ARCHIVELOG mode** | ❌ NOARCHIVELOG | **BLOCKER** for ONLINE migration | `ALTER DATABASE ARCHIVELOG;` (requires restart) |
| **Source Force Logging** | ❌ DISABLED | BLOCKER for ONLINE migration | `ALTER DATABASE FORCE LOGGING;` |
| **Supplemental Logging** | ❌ NONE | Required for online replication | `ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;` |
| **Source TDE** | ✅ NONE | No action — target TDE applied after migration | No action on source |
| **Target TDE Master Key** | ⚠️ OPEN_NO_MASTER_KEY | ZDM requires TDE master key on target | Create TDE master key in target CDB |
| **Source Password File** | ✅ EXCLUSIVE mode | Required for DG — OK | None |
| **Source listener on 1521** | ✅ OPEN | Required for ZDM | None |
| **Target listener on 1521** | ✅ OPEN | Required for ZDM | None |
| **ZDM → Source TCP:22** | ✅ OPEN | SSH access required | None |
| **ZDM → Source TCP:1521** | ✅ OPEN | DB access required | None |
| **ZDM → Target TCP:22** | ✅ OPEN | SSH access required | None |
| **ZDM → Target TCP:1521** | ✅ OPEN | DB access required | None |
| **ZDM → Target ICMP** | ⚠️ BLOCKED | Not required for ZDM operations | No action — normal for ODAA (NSG blocks ICMP) |
| **OCI CLI on ZDM server** | ✅ v3.73.1 | Required for OCI Object Storage | None |
| **OCI Config for zdmuser** | ✅ Present | ZDM runs as zdmuser | None |
| **OCI Config for azureuser** | ❌ MISSING | Not directly needed by ZDM but needed for manual OCI operations | Copy/create OCI config for azureuser if needed |
| **OCI Object Storage Namespace** | ❌ NOT SET | Required for ZDM data transfer | Discover with `oci os ns get` |
| **OCI OSS Bucket** | ❌ NOT SET | Required for ZDM data transfer | Create bucket in uk-london-1 / compartment |
| **ZDM Credential Store** | ❌ NOT FOUND | Required before running zdmcli migrate | Initialize with `zdmcli -cred` |
| **Source disk space** | ⚠️ TIGHT (8.6 GB free) | May be insufficient for archive log growth | Monitor disk; consider archive destination on separate mount |
| **Source RMAN configured** | ❌ NOT configured | Required for OFFLINE_PHYSICAL | Configure RMAN if using offline method |
| **Data Guard** | ❌ Not configured | Configured automatically by ZDM for ONLINE_PHYSICAL | No pre-action needed |
| **Source DB Links** | ⚠️ SYS.SYS_HUB present | System DB link — monitor post-migration | Review after migration |
| **SCAN listener (target)** | ✅ 3 SCAN VIPs configured | RAC SCAN access — operational | None |

---

## 4. Required Actions

### 4.1 CRITICAL — Must Complete Before ONLINE_PHYSICAL Migration

These actions are **blocking** for ZDM ONLINE_PHYSICAL. Coordinate with source DBA for each.

#### ACTION-01: Enable ARCHIVELOG Mode on Source

⚠️ **Requires database restart (brief downtime on source)**

```sql
-- Connect as SYSDBA to source
CONNECT / AS SYSDBA
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;

-- Verify
SELECT LOG_MODE FROM V$DATABASE;
-- Expected: ARCHIVELOG
```

#### ACTION-02: Enable Force Logging on Source

```sql
-- After database is open
ALTER DATABASE FORCE LOGGING;

-- Verify
SELECT FORCE_LOGGING FROM V$DATABASE;
-- Expected: YES
```

#### ACTION-03: Enable Minimum Supplemental Logging on Source

```sql
-- Enable ALL supplemental logging (required for online migration)
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;

-- Verify
SELECT SUPPLEMENTAL_LOG_DATA_MIN, SUPPLEMENTAL_LOG_DATA_ALL
FROM V$DATABASE;
-- Expected: YES, YES
```

#### ACTION-04: Configure TDE Master Key on Target

The target wallet is `OPEN_NO_MASTER_KEY`. ZDM requires a TDE master key to exist.

```sql
-- Connect to target CDB as SYSDBA
ADMINISTER KEY MANAGEMENT SET KEY FORCE KEYSTORE IDENTIFIED BY "<wallet_password>" WITH BACKUP;

-- Verify
SELECT STATUS, WALLET_TYPE FROM V$ENCRYPTION_WALLET;
-- Expected: OPEN, PASSWORD or AUTOLOGIN
```

#### ACTION-05: Discover OCI Object Storage Namespace

Run on ZDM server as zdmuser (OCI config already in place):

```bash
su - zdmuser
oci os ns get
# Note the namespace value and update zdm-env.md OCI_OSS_NAMESPACE
```

#### ACTION-06: Create OCI Object Storage Bucket

```bash
# As zdmuser on ZDM server
oci os bucket create \
  --compartment-id ocid1.compartment.oc1..aaaaaaaas4upnqj72dfiivgwvn3uui5gkxo7ng6leeoifucbjiy326urbhmq \
  --name <BUCKET_NAME> \
  --namespace <OSS_NAMESPACE>

# Suggested bucket name: zdm-oradb-migration
# Update zdm-env.md OCI_OSS_BUCKET_NAME after creation
```

#### ACTION-07: Initialize ZDM Credential Store

The ZDM credential store (`/u01/app/zdmhome/zdm/cred`) does not exist.
ZDM requires source and target DB credentials to be stored before running `zdmcli migrate`.

```bash
su - zdmuser
zdmcli migrate database -help
# Follow credential initialization procedure per ZDM documentation
# Typically: zdmcli -credstore init or populate response file with passwords
```

### 4.2 RECOMMENDED — Should Complete Before Migration

#### ACTION-08: Configure Archive Log Destination (if enabling ARCHIVELOG)

Source disk is tight (~8.6 GB free). Ensure archive logs are directed to a path with sufficient space, or add a mount point.

```bash
# Check available space and configure archive destination
df -h /u01/app/oracle
# Set log_archive_dest_1 to a path with adequate free space
```

#### ACTION-09: Configure RMAN on Source (for Offline/Backup-Based Migration)

If using OFFLINE_PHYSICAL method or as a backup strategy:

```bash
rman TARGET /
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '/u01/app/oracle/fast_recovery_area/%F';
CONFIGURE DEFAULT DEVICE TYPE TO DISK;
```

#### ACTION-10: Verify SSH Key Access for zdmuser

Confirm zdmuser can SSH to both source and target without password prompts:

```bash
# On ZDM server as zdmuser
ssh -i ~/.ssh/odaa.pem azureuser@10.1.0.11 "hostname"
# Expected: tm-oracle-iaas

ssh -i ~/.ssh/odaa.pem opc@10.0.1.160 "hostname"
# Expected: tmodaauks-rqahk1
```

#### ACTION-11: Verify Oracle User SSH Access from ZDM Server

ZDM requires password-less SSH to the `oracle` user on source and target for file operations:

```bash
# Z DM server → source oracle user
ssh -i ~/.ssh/odaa.pem oracle@10.1.0.11 "echo OK"

# ZDM server → target oracle user
ssh -i ~/.ssh/odaa.pem oracle@10.0.1.160 "echo OK"
```

If SSH as `oracle` is not permitted, ZDM can use the admin user with sudo — confirm ZDM response file settings accordingly.

#### ACTION-12: Update zdm-env.md with Missing Values

The following fields in [zdm-env.md](../../../../prompts/Phase10-Migration/ZDM/zdm-env.md) are currently blank and must be populated:

| Field | Status | Notes |
|---|---|---|
| `OCI_OSS_NAMESPACE` | ❌ BLANK | Run `oci os ns get` as zdmuser |
| `OCI_OSS_BUCKET_NAME` | ❌ BLANK | Create bucket, then record name |

---

## 5. Source Database — Detailed Findings

### 5.1 PDB Inventory

| CON_ID | Name | Open Mode | GUID |
|---|---|---|---|
| 2 | PDB$SEED | READ ONLY | 4B858081EF781282E0630B00010A1DAD |
| 3 | PDB1 | READ WRITE | 4B85B38AE4551C7FE0630B00010AAD3C |

> **Migration scope**: PDB1 is the user PDB and will be migrated. PDB$SEED is a seed template and is not migrated by ZDM.

### 5.2 Tablespace Summary

| Tablespace | Current (GB) | Max (GB) | Type | Autoextend | Status |
|---|---|---|---|---|---|
| SYSAUX | 0.81 | 32 | PERMANENT | YES | ONLINE |
| SYSTEM | 0.80 | 32 | PERMANENT | YES | ONLINE |
| TEMP | 0.03 | 32 | TEMPORARY | YES | ONLINE |
| UNDOTBS1 | 0.28 | 32 | UNDO | YES | ONLINE |
| USERS | 0.005 | 32 | PERMANENT | YES | ONLINE |

> All data files are on local filesystem under `/u01/app/oracle/oradata/oradb1/`.
> No user-created tablespaces detected. Database is essentially empty of user data.

### 5.3 Network / Listener

- Listener running on: `tm-oracle-iaas.s15cwnltpnyuher1lvdjg5qxtd.zx.internal.cloudapp.net:1521`
- tnsnames.ora: entry for `oradb` exists (HOST=10.1.0.11, PORT=1521)
- sqlnet.ora: **NOT FOUND** — no wallet/encryption config on source network layer
- listener.ora: **NOT FOUND** — listener auto-registered (standard for 12c+)
- Services registered: oradb1, oradbXDB, pdb1, service alias GUID for PDB1

### 5.4 Redo Log Configuration

| Group | Size | Status | Archived |
|---|---|---|---|
| 1 | 200 MB | INACTIVE | NO |
| 2 | 200 MB | CURRENT | NO |
| 3 | 200 MB | INACTIVE | NO |

> 3 groups × 200 MB each (standard). All in NOARCHIVELOG state (logs overwrite without archiving).
> Archive destination configured to `/u01/app/oracle/product/12.2.0/dbhome_1/dbs/arch` but inactive.

### 5.5 Data Guard Parameters (Current State)

| Parameter | Value |
|---|---|
| db_unique_name | oradb1 |
| dg_broker_start | FALSE |
| fal_client | (empty) |
| fal_server | (empty) |
| log_archive_config | (empty) |
| log_archive_dest_1 | (empty) |
| log_archive_dest_2 | (empty) |
| standby_file_management | MANUAL |
| protection_mode | MAXIMUM PERFORMANCE |
| protection_level | UNPROTECTED |

> Data Guard is not currently configured. ZDM will configure a temporary standby relationship to the target database when using ONLINE_PHYSICAL method. Parameters such as `log_archive_dest_2`, `fal_client`, `fal_server`, and `dg_broker_start` will be set by ZDM automatically.

### 5.6 Database Links

| Owner | DB Link | Username | Host | Created |
|---|---|---|---|---|
| SYS | SYS_HUB | SEEDDATA | (system) | 2017-01-26 |

> This is a system-managed DB link (ORA_SEEDDATA link). It is not user data and does not impact migration. Monitor post-migration connectivity, but no action is required before migration.

### 5.7 Authentication

- Password file: EXCLUSIVE mode (`/u01/app/oracle/product/12.2.0/dbhome_1/dbs/orapworadb`) ✅
- `REMOTE_LOGIN_PASSWORDFILE = EXCLUSIVE` ✅ (required for Data Guard / ZDM ONLINE_PHYSICAL)
- OS auth prefix: `ops$`
- Oracle user `~/.ssh`: **NOT ACCESSIBLE** from discovery user — zdmuser SSH key setup should be verified separately (see ACTION-10)

### 5.8 Backup / Scheduler

- RMAN: **NOT CONFIGURED** — no backup policies, no recent backups
- Oracle crontab: none
- Scheduler jobs: ORA$PREPLUGIN_BACKUP_JOB (DISABLED — auto-created by Grid/ASM, not running)
- No active backup regime detected — **establish backup prior to migration**

---

## 6. Target Environment — Detailed Findings

### 6.1 Cluster Configuration

| Property | Value |
|---|---|
| Cluster Name (derived) | tmodaauks (2-node RAC) |
| Node 1 | tmodaauks-rqahk1 (10.0.1.160, VIP: 10.0.1.155) |
| Node 2 | tmodaauks-rqahk2 (10.0.1.114, VIP: 10.0.1.142) |
| SCAN Listeners | 3 SCAN VIPs — SCAN1 on node 2, SCAN2+3 on node 1 |
| Grid Infrastructure | Oracle 19c, version 19.0.0.0.0 |
| ASM Status | Running on both nodes |

> All CRS resources are STABLE. The ACFS volume (acfs01) is mounted on both nodes with 88 GB free.

### 6.2 ASM Disk Groups

| Disk Group | Redundancy | Total (GB) | Free (GB) | Used (GB) |
|---|---|---|---|---|
| DATAC3 | HIGH | 4,896 | 4,128 | 767 |
| RECOC3 | HIGH | 1,224 | 1,048 | 175 |

> **Data storage capacity is more than sufficient.** Source DB is ~1.9 GB; target has over 4 TB free on DATAC3.

### 6.3 Existing Databases on Target

| DB Name | Status | Notes |
|---|---|---|
| migdb | OFFLINE (all instances) | Existing test/previous migration DB |
| mydb | OFFLINE (all instances) | Existing test DB |
| oradb01m | OFFLINE (all instances) | Appears to be a previous ORADB migration attempt |

> These offline DBs occupy space on /u02 (57 GB total, only 14 GB free). **Coordinate whether these DBs should be removed** before the ORADB migration to free /u02 space for the new database home files.

### 6.4 OCI Instance Metadata

| Field | Value |
|---|---|
| Region | uk-london-1 |
| Availability Domain | uk-london-1-ad-2 |
| Fault Domain | FAULT-DOMAIN-2 |
| Shape | ExadataVMInstance (X11M) |
| Cloud Provider | Azure (Oracle Database@Azure) |
| Cloud Region | UK South |

---

## 7. ZDM Server — Detailed Findings

### 7.1 Network Routing Analysis

ZDM server (10.1.0.8) is in subnet 10.1.0.0/24 (same subnet as source 10.1.0.11).
The target (10.0.1.160) is in subnet 10.0.1.0/24 (ODAA VNet).

| Connection | Result | Detail |
|---|---|---|
| ZDM → Source (10.1.0.11) ICMP | ✅ SUCCESS | 0% loss, avg 1.576ms, well within 10ms |
| ZDM → Source (10.1.0.11) TCP:22 | ✅ OPEN | SSH access confirmed |
| ZDM → Source (10.1.0.11) TCP:1521 | ✅ OPEN | Oracle listener access confirmed |
| ZDM → Target (10.0.1.160) ICMP | ⚠️ BLOCKED | 100% ICMP loss — NSG on ODAA blocks ICMP (expected) |
| ZDM → Target (10.0.1.160) TCP:22 | ✅ OPEN | SSH access confirmed |
| ZDM → Target (10.0.1.160) TCP:1521 | ✅ OPEN | Oracle listener access confirmed |

> **Assessment: Network connectivity is sufficient for ZDM operations.** ICMP (ping) failure to target is an expected ODAA NSG behavior and does **not** indicate a routing problem. ZDM uses TCP for all real communications (SSH:22, Oracle:1521, ZDM transfer port). No firewall remediation is required.

The hosts file on the ZDM server already has entries for all target nodes, VIPs, and SCAN names.

### 7.2 OCI Configuration

| Config Item | azureuser | zdmuser |
|---|---|---|
| ~/.oci/config | ❌ NOT FOUND | ✅ PRESENT (region: uk-london-1) |
| OCI API key | ❌ NOT FOUND | ✅ (masked in discovery) |
| OCI CLI usable | ❌ | ✅ |

> ZDM service runs as `zdmuser`. OCI CLI is configured under zdmuser and should function for ZDM operations (Object Storage upload/download). The OCI config for `azureuser` is absent — only required if running OCI commands directly as azureuser.

### 7.3 ZDM Installation Status

| Item | Status |
|---|---|
| ZDM_HOME | /u01/app/zdmhome |
| zdmcli | ✅ Found and executable |
| ZDM Service | ✅ Running |
| Response file templates | ✅ zdm_template.rsp (physical), zdm_logical_template.rsp, zdm_xtts_template.rsp |
| ZDM Credential Store | ❌ NOT INITIALIZED |
| Active Migration Jobs | None |
| ZDM Logs | Empty (no prior migration runs) |

### 7.4 Disk Space on ZDM Server

| Filesystem | Total | Used | Free | Mount |
|---|---|---|---|---|
| / (rootvg-rootlv) | 39 GB | 15 GB | 24 GB | / |
| /dev/shm | 3.8 GB | 0 | 3.8 GB | tmpfs |
| /mnt | 16 GB | <1 MB | 15 GB | data disk |

> ZDM emits low-disk warnings against a 50 GB threshold, but these are advisory. For a 1.9 GB source database, 24 GB free on `/` is adequate for ZDM working files and staging. The `/mnt` disk (15 GB free) could also be used for temporary staging if needed.

---

## 8. Risk Register

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R-01 | Source in NOARCHIVELOG — online migration not possible until enabled | **CRITICAL** | Enable ARCHIVELOG + Force Logging (ACTION-01, ACTION-02) |
| R-02 | No supplemental logging — online replication will not capture all changes | **HIGH** | Enable supplemental logging (ACTION-03) |
| R-03 | Target TDE wallet has no master key — ZDM may fail at encryption step | **HIGH** | Create TDE master key on target (ACTION-04) |
| R-04 | OCI Object Storage not configured — ZDM cannot transfer data | **HIGH** | Discover OSS namespace and create bucket (ACTION-05, ACTION-06) |
| R-05 | ZDM credential store not initialized | **HIGH** | Initialize credential store before running zdmcli (ACTION-07) |
| R-06 | Source disk space is tight (8.6 GB free) | **MEDIUM** | Monitor archive log accumulation; add disk or redirect archive destination |
| R-07 | /u02 on target is 75% full (14 GB free) with 3 offline DBs | **MEDIUM** | Evaluate removing migdb/mydb/oradb01m from target to free space |
| R-08 | No RMAN backup of source prior to migration | **MEDIUM** | Take RMAN backup before initiating ZDM (ACTION-09) |
| R-09 | OCI config missing for azureuser on ZDM server | **LOW** | Copy or recreate OCI config under azureuser if needed for manual steps |
| R-10 | System DB link SYS_HUB present on source | **LOW** | System-managed link; verify post-migration if any application references it |
| R-11 | Source ZDM version and target Grid version compatibility | **LOW** | Verify ZDM version supports 12.2 → 19c CDB migration in release notes |
| R-12 | 12.2 → 19c upgrade compatibility of PDB1 workload | **LOW** | Run OPatch/pre-upgrade checks after enabling ARCHIVELOG |

---

## 9. Next Steps

1. **Complete ACTION-01 through ACTION-07** (Critical actions) — estimated 2–4 hours with source DBA access
2. **Complete ACTION-08 through ACTION-12** (Recommended actions)
3. **Fill in the Migration Questionnaire** ([Migration-Questionnaire-ORADB.md](Migration-Questionnaire-ORADB.md)) — gather remaining decisions from stakeholders
4. **Proceed to Step 2** — Fix Issues prompt to resolve blockers and validate configuration
5. **Proceed to Step 3** — Generate ZDM migration artifacts (response file, migration command)

---

*Generated by GitHub Copilot — ODAA Migration Accelerator*
*Based on discovery run: 2026-02-27 21:36 UTC*
