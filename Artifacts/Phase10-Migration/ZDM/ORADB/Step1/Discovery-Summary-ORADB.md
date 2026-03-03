# Discovery Summary: ORADB Migration

## Generated
- **Date:** 2026-03-03
- **Source Files Analyzed:**
  - `zdm_source_discovery_tm-oracle-iaas_20260303_224041.txt`
  - `zdm_target_discovery_tmodaauks-rqahk1_20260303_224046.txt`
  - `zdm_server_discovery_tm-vm-odaa-oracle-jumpbox_20260303_174048.txt`

---

## Executive Summary

| Component | Status | Key Findings |
|-----------|--------|--------------|
| Source Database | ✅ | Oracle 12.2.0.1.0 CDB+PDB1, ARCHIVELOG, Force Logging ON, Supp. Logging ON, No TDE, 2.14 GB |
| Target Environment | ✅ | Oracle 19.29.0.0.0 ODAA 2-node RAC, ASM available, 4.1 TB free on DATAC3 |
| ZDM Server | ✅ | ZDM 21.5.0 (Jul 2025), service running, OCI CLI 3.73.1 installed |
| Network | ⚠️ | Cross-network (Azure 10.1.x.x → OCI 10.0.x.x); verify ExpressRoute/VPN latency is acceptable |
| OCI Object Storage | ⚠️ | Namespace and bucket name not yet configured in zdm-env.md — required for ONLINE migration |

---

## Migration Method Recommendation

**Recommended:** `ONLINE_PHYSICAL`

**Justification:**
- Source database is in ARCHIVELOG mode (required for online migration)
- Force Logging is enabled (required for Data Guard replication accuracy)
- Supplemental logging is already enabled at the database level
- No TDE on source — no keystore migration complexity
- Database is only 2.14 GB; initial backup will transfer quickly
- Version upgrade from 12.2 → 19c is natively supported by ZDM physical online
- Online migration minimizes downtime to just the switchover window (typically < 5 minutes for this DB size)

---

## Source Database Details

**Host:** `tm-oracle-iaas` (10.1.0.11)
**OS:** Oracle Linux 7.4, kernel 4.1.12-124.14.1.el7uek.x86_64, x86_64

### Database Identification

| Property | Value |
|----------|-------|
| Database Name (global) | ORADB1 |
| DB Unique Name | oradb1 |
| Instance Name (ORACLE_SID) | oradb |
| DBID | 2571197414 |
| Oracle Version | 12.2.0.1.0 |
| Oracle Home | /u01/app/oracle/product/12.2.0/dbhome_1 |
| Created | 23-FEB-2026 |
| Database Role | PRIMARY |
| Open Mode | READ WRITE |
| Protection Mode | MAXIMUM PERFORMANCE |
| Container Database (CDB) | YES |
| Pluggable Databases | PDB$SEED (READ ONLY), PDB1 (READ WRITE) |
| NLS Character Set | AL32UTF8 |
| NLS NChar Character Set | AL16UTF16 |

### Size

| Item | Value |
|------|-------|
| Total Data File Size | 2.14 GB |
| Temp File Size | 0.03 GB |
| SYSAUX | 1.045 GB (autoextend, max 32 GB) |
| SYSTEM | 0.811 GB (autoextend, max 32 GB) |
| UNDOTBS1 | 0.283 GB (autoextend, max 32 GB) |
| USERS | 0.005 GB (autoextend, max 32 GB) |

### Configuration Status

| Requirement | Current State | Required State | Status |
|-------------|---------------|----------------|--------|
| ARCHIVELOG Mode | YES | YES | ✅ |
| Force Logging | YES | YES | ✅ |
| Supplemental Logging (DB level) | YES (minimal) | YES | ✅ |
| Supplemental Logging (Primary Key) | YES | Recommended | ✅ |
| Supplemental Logging (All Columns) | NO | Not required | ✅ |
| TDE Enabled | NO (NOT_AVAILABLE) | N/A | ✅ |
| Password File | Present | YES | ✅ |
| DG Broker | FALSE | N/A (ZDM manages DG) | ✅ |
| Oracle Version ≥ 11.2.0.4 | 12.2.0.1.0 | YES | ✅ |

### Redo Log Configuration

| Group | Members | Size | Status |
|-------|---------|------|--------|
| 1 | 1 | 200 MB | CURRENT |
| 2 | 1 | 200 MB | INACTIVE |
| 3 | 1 | 200 MB | INACTIVE |

**Archive Log Location:** `/u01/app/oracle/fast_recovery_area`

### Listener

| Property | Value |
|----------|-------|
| Listener Alias | LISTENER |
| Version | 12.2.0.1.0 |
| Host | tm-oracle-iaas.s15cwnltpnyuher1lvdjg5qxtd.zx.internal.cloudapp.net |
| Port | 1521 (TCP) |
| Uptime | 8+ days (started 23-FEB-2026) |

### Scheduler Jobs (Active)

The following SYS-owned scheduler jobs are enabled and will continue post-migration:
- `ORACLE_OCM.MGMT_CONFIG_JOB` (daily statistics collection)
- `ORACLE_OCM.MGMT_STATS_CONFIG_JOB` (monthly stats)
- `SYS.BSLN_MAINTAIN_STATS_JOB`, `CLEANUP_*` family, `PURGE_LOG`, etc.

### Database Links

| Owner | DB Link | Username | Host |
|-------|---------|----------|------|
| SYS | SYS_HUB | SEEDDATA | (see discovery) |

> ⚠️ **Note:** The `SYS_HUB` database link targets `SEEDDATA`. Verify this link is still needed post-migration; if so, ensure the target endpoint is reachable from OCI.

### RMAN Backup Configuration

| Setting | Value |
|---------|-------|
| Controlfile Autobackup | ON |
| Default Device Type | DISK |
| Backup Optimization | ON |
| Retention Policy | REDUNDANCY 1 |
| Backup Location | /u01/app/oracle/fast_recovery_area |

### Source Disk Space

| Filesystem | Size | Used | Free | Use% | Notes |
|------------|------|------|------|------|-------|
| / (root) | 30 GB | 23 GB | 5.8 GB | 80% | ⚠️ Monitor — keep archive logs from filling this |
| /mnt/resource | 16 GB | 2.1 GB | 13 GB | 14% | |

> ⚠️ **Warning:** Root filesystem is at 80% capacity. Monitor archive log accumulation during migration to avoid running out of space.

---

## Target Environment Details

**Host:** `tmodaauks-rqahk1` (10.0.1.160) — Node 1 of 2-node RAC
**OS:** Oracle Linux 8.10, kernel 5.15.0-308.179.6.16.el8uek.x86_64
**Platform:** Oracle Database at Azure (ODAA) — ExaDB infrastructure

### Oracle Environment

| Property | Value |
|----------|-------|
| Oracle Version | 19.29.0.0.0 |
| Grid Infrastructure Home | /u01/app/19.0.0.0/grid |
| Database Home | /u02/app/oracle/product/19.0.0.0/dbhome_1 |
| ASM Instance | +ASM1 |
| RAC Nodes | tmodaauks-rqahk1 (node 1), tmodaauks-rqahk2 (node 2) |

### Cluster Status

| Service | Status |
|---------|--------|
| Oracle High Availability Services | Online (CRS-4638) |
| Cluster Ready Services | Online (CRS-4537) |
| Cluster Synchronization Services | Online (CRS-4529) |
| Event Manager | Online (CRS-4533) |

### ASM Storage

| Disk Group | Type | Total (GB) | Free (GB) | Used % |
|------------|------|-----------|----------|--------|
| DATAC3 | HIGH | 4,896 | 4,128.86 | 15.7% |
| RECOC3 | HIGH | 1,224 | 1,048.89 | 14.3% |

> ✅ Ample storage available on both DATAC3 and RECOC3 for the 2.14 GB source database.

### Listener / Network

| Protocol | Host | Port | Notes |
|----------|------|------|-------|
| TCP | 10.0.1.160 | 1521 | Primary private IP |
| TCP | 10.0.1.155 | 1521 | VIP |
| TCPS | 10.0.1.155 | 2484 | SSL listener |
| IPC | LISTENER | — | Local |

### TDE / Wallet

| Property | Value |
|----------|-------|
| Wallet Type | FILE |
| Wallet Location | /var/opt/oracle/dbaas_acfs/grid/tcps_wallets/ |
| Status | OPEN_NO_MASTER_KEY |

> ℹ️ Target wallet is open but has no master key — this is the expected state for a fresh ODAA system ready to receive a migrated database. ZDM will configure TDE as part of the migration process (`ZDM_SETUP_TDE_TGT`).

### Existing Databases on Target

The following databases already exist on this ODAA system:
- `oradb01m` (instance `oradb011`) — active, shown in listener

> ⚠️ **Note:** Ensure the new database name (`ORADB1` migrated as target unique name) does not conflict with existing databases on the target system.

---

## ZDM Server Details

**Host:** `tm-vm-odaa-oracle-jumpbox` (10.1.0.8)
**OS:** Oracle Linux 9.5, kernel 5.15.0-307.178.5.el9uek.x86_64

### ZDM Installation

| Property | Value |
|----------|-------|
| ZDM Home | /u01/app/zdmhome |
| ZDM User | zdmuser |
| ZDM Version | 21.5.0 (Build: Jul 24 2025) |
| Java Version | 1.8.0_451 (via $JAVA_HOME) |
| ZDM Service | ✅ Running |
| RMI Port | 8897 |
| HTTP Port | 8898 |
| MySQL Port | 8899 |
| Wallet Path | /u01/app/zdmbase/crsdata/tm-vm-odaa-oracle-jumpbox/security |

### Response File Templates Available

| Template | Purpose |
|----------|---------|
| zdm_template.rsp | Physical migration (ONLINE/OFFLINE) |
| zdm_logical_template.rsp | Logical migration |
| zdm_xtts_template.rsp | Cross-platform tablespace migration |

### OCI CLI

| Property | Value |
|----------|-------|
| OCI CLI Version | 3.73.1 |
| Config Status | ⚠️ Not found at `/home/azureuser/.oci/config` (script ran as azureuser) |

> ℹ️ The OCI CLI config check failed because the discovery script runs as `azureuser`. The OCI config must be present under the `zdmuser` account at `~zdmuser/.oci/config`. Verify: `sudo -u zdmuser oci iam region list`

### Disk Space on ZDM Server

| Filesystem | Free | Warning |
|------------|------|---------|
| / (root) | 24 GB | ⚠️ < 50 GB (soft recommendation only) |

> ℹ️ The 50 GB disk warning is a conservative recommendation for large databases. With a 2.14 GB source database, 24 GB free on `/` is sufficient.

### Previous ZDM Job History (Summary)

| Last Successful Job | Job IDs 16 & 17 | EVAL | All prechecks PASSED (Jan 26, 2026) |
| Last Migration Attempt | Job ID 19 | MIGRATE | ABORTED at ZDM_VALIDATE_TGT |

> ℹ️ Jobs 16 and 17 were EVAL runs against a different database pair (`mydb`). The ORADB migration has not yet been run. Historical job failures are from earlier testing with different source/target parameters.

---

## Migration Readiness Assessment

### Requirements Met ✅

| Item | Evidence |
|------|----------|
| ARCHIVELOG mode enabled | `LOG_MODE = ARCHIVELOG` |
| Force Logging enabled | `FORCE_LOGGING = YES` (ZDM physical requires this) |
| Supplemental logging enabled | Minimal + primary key supplemental logging active |
| Password file present | `/u01/app/oracle/product/12.2.0/dbhome_1/dbs/orapworadb` |
| Target storage available | DATAC3: 4.1 TB free; RECOC3: 1.0 TB free |
| ZDM service running | `Running: true` on port 8898 |
| OCI CLI installed | v3.73.1 on ZDM server |
| SSH connectivity | Discovery scripts executed successfully on all hosts |

### Actions Required ⚠️

| # | Item | Priority | Action |
|---|------|----------|--------|
| 1 | OCI Object Storage bucket | **High** | Create OCI bucket and update `OCI_OSS_NAMESPACE` and `OCI_OSS_BUCKET_NAME` in `zdm-env.md` |
| 2 | OCI CLI config for zdmuser | **High** | Verify `~zdmuser/.oci/config` is configured and `oci iam region list` works as zdmuser |
| 3 | Source disk monitoring | **Medium** | Source `/` is at 80%. Monitor archive log growth during migration — consider increasing archive log retention or purging old archivelogs before starting |
| 4 | Database link review | **Low** | Review `SYS.SYS_HUB` database link — ensure its target endpoint is reachable from OCI post-migration |
| 5 | PDB name mapping | **Medium** | Decide target PDB name for `PDB1`: keep as `PDB1` or rename (must not conflict with existing PDBs on `oradb01m`) |
| 6 | Target DB unique name | **High** | Confirm target `DB_UNIQUE_NAME` to be assigned to the migrated ORADB — must not conflict with `oradb01m` on same ODAA system |

### Blockers ❌

**None identified.** The environment is ready to proceed to artifact generation once the ⚠️ items above are addressed.

---

## Discovered Values Reference

The following values were auto-discovered and are pre-populated for use in Step 3 artifact generation:

### Source

```
SOURCE_HOST=10.1.0.11
SOURCE_SSH_USER=azureuser
SOURCE_SSH_KEY=~/.ssh/odaa.pem
SOURCE_ORACLE_HOME=/u01/app/oracle/product/12.2.0/dbhome_1
SOURCE_ORACLE_SID=oradb
SOURCE_DB_NAME=ORADB1
SOURCE_DB_UNIQUE_NAME=oradb1
SOURCE_ORACLE_VERSION=12.2.0.1.0
SOURCE_CHARACTER_SET=AL32UTF8
SOURCE_NCHAR_CHARACTER_SET=AL16UTF16
SOURCE_IS_CDB=YES
SOURCE_PDBS=PDB1
SOURCE_ARCHIVE_LOG_DEST=/u01/app/oracle/fast_recovery_area
SOURCE_DB_SIZE_GB=2.14
```

### Target

```
TARGET_HOST=10.0.1.160
TARGET_SSH_USER=opc
TARGET_SSH_KEY=~/.ssh/odaa.pem
TARGET_ORACLE_HOME=/u02/app/oracle/product/19.0.0.0/dbhome_1
TARGET_ORACLE_VERSION=19.29.0.0.0
TARGET_IS_RAC=YES
TARGET_RAC_NODES=tmodaauks-rqahk1,tmodaauks-rqahk2
TARGET_ASM_DATA_DG=+DATAC3
TARGET_ASM_RECO_DG=+RECOC3
TARGET_LISTENER_PORT=1521
```

### ZDM Server

```
ZDM_HOST=10.1.0.8
ZDM_USER=zdmuser
ZDM_SSH_USER=azureuser
ZDM_SSH_KEY=~/.ssh/zdm.pem
ZDM_HOME=/u01/app/zdmhome
ZDM_VERSION=21.5.0
ZDM_RSP_TEMPLATE=/u01/app/zdmhome/rhp/zdm/template/zdm_template.rsp
```

### OCI (from zdm-env.md)

```
OCI_TENANCY_OCID=ocid1.tenancy.oc1..aaaaaaaarvyhjcn7wkkxxx5g3o7lgqks23bmsjtsticz3gtg5xs5qyrwkftq
OCI_USER_OCID=ocid1.user.oc1..aaaaaaaakfe5cirdq7vkkrhogjrgcrgftvwb7mdoehujgchefpqv54vhsnoa
OCI_COMPARTMENT_OCID=ocid1.compartment.oc1..aaaaaaaas4upnqj72dfiivgwvn3uui5gkxo7ng6leeoifucbjiy326urbhmq
TARGET_DATABASE_OCID=ocid1.database.oc1.uk-london-1.anwgiljss56liuaatz45cjnpbvpgku7gkorvxg6lytoj5lxxruk2eqxzkzma
OCI_API_KEY_FINGERPRINT=7f:05:c1:f2:5c:3a:46:ec:9f:95:44:c8:77:a4:50:f9
OCI_CONFIG_PATH=~/.oci/config
OCI_PRIVATE_KEY_PATH=~/.oci/oci_api_key.pem
OCI_REGION=uk-london-1 (inferred from TARGET_DATABASE_OCID)
OCI_OSS_NAMESPACE=<NEEDS_TO_BE_SET>
OCI_OSS_BUCKET_NAME=<NEEDS_TO_BE_SET>
```
