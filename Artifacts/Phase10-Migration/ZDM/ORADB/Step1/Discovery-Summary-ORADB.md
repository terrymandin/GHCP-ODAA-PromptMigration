# Discovery Summary: ORADB Migration

## Generated
- **Date:** 2026-03-03
- **Source Files Analyzed:**
  - `zdm_source_discovery_tm-oracle-iaas_20260303_232709.txt`
  - `zdm_target_discovery_tmodaauks-rqahk1_20260303_232714.txt`
  - `zdm_server_discovery_tm-vm-odaa-oracle-jumpbox_20260303_182716.txt`

---

## Executive Summary

| Component | Status | Key Findings |
|-----------|--------|--------------|
| Source Database | ✅ Ready | Oracle 12.2.0.1 CDB, ARCHIVELOG, Force Logging enabled, 2.15 GB data |
| Target Environment | ⚠️ Action Required | ODAA 19c Exadata, ASM configured, DB was not open during discovery, TDE master key missing, password file missing |
| ZDM Server | ⚠️ Action Required | ZDM 21.5.0 running, SSH keys present, OCI CLI installed but config missing |
| Network | ⚠️ Action Required | SSH/listener ports open to both nodes; ICMP to target blocked (expected); OCI config required for Object Storage |

---

## Migration Method Recommendation

**Recommended:** `ONLINE_PHYSICAL`

**Justification:**
- Source is in ARCHIVELOG mode with Force Logging enabled — all prerequisites met for Data Guard-based online migration
- Database is small (2.15 GB data files) — minimal initial backup time
- Physical migration (RMAN + Data Guard) is the lowest-risk path for CDB-to-CDB migration between Oracle 12.2 and 19c
- Online method minimizes downtime by maintaining a synchronized standby until switchover
- ZDM 21.5.0 is the current installed version and fully supports `ONLINE_PHYSICAL` to ODAA/ExaDB-D

---

## Source Database Details

### Database Identification

| Property | Value |
|----------|-------|
| Database Name | ORADB1 |
| DB Unique Name | oradb1 |
| DBID | 2571197414 |
| Oracle SID | oradb |
| Oracle Version | 12.2.0.1.0 |
| Oracle Home | `/u01/app/oracle/product/12.2.0/dbhome_1` |
| Database Role | PRIMARY |
| Open Mode | READ WRITE |
| CDB | YES |
| PDBs | PDB$SEED (READ ONLY), PDB1 (READ WRITE) |
| Character Set | AL32UTF8 |
| NLS National Charset | AL16UTF16 |

### Operating System

| Property | Value |
|----------|-------|
| Hostname | tm-oracle-iaas |
| FQDN | tm-oracle-iaas.s15cwnltpnyuher1lvdjg5qxtd.zx.internal.cloudapp.net |
| IP Address | 10.1.0.11 |
| OS Version | Oracle Linux Server 7.4 |
| Kernel | 4.1.12-124.14.1.el7uek.x86_64 |
| Architecture | x86_64 |

### Disk Space

| Filesystem | Size | Used | Available | Use% | Mount |
|------------|------|------|-----------|------|-------|
| /dev/sda2 | 30G | 23G | 5.6G | 81% | / |
| /dev/sda1 | 497M | 117M | 381M | 24% | /boot |
| /dev/sdb1 | 16G | 2.1G | 13G | 14% | /mnt/resource |

> ⚠️ **Root filesystem is 81% full (5.6 GB free).** Ensure adequate space for ZDM staging files and RMAN backup pieces during migration. Consider moving the FRA to the ephemeral disk or verifying the FRA size limit.

### Database Storage

| Property | Value |
|----------|-------|
| Data Files Size | 2.15 GB |
| Temp Files Size | 0.03 GB |
| FRA Location | `/u01/app/oracle/fast_recovery_area` |
| Redo Log Groups | 3 groups × 200 MB |
| Archive Rate (24h) | ~0.17 GB/hour (1 archive per period) |

### Configuration Status

| Requirement | Current State | Required State | Status |
|-------------|---------------|----------------|--------|
| ARCHIVELOG Mode | YES | YES | ✅ |
| Force Logging | YES | YES | ✅ |
| Supplemental Logging (Minimal) | YES | YES | ✅ |
| CDB Architecture | YES | YES (ODAA target is CDB) | ✅ |
| TDE Configured | NOT_AVAILABLE | Not required for physical migration | ✅ |
| Password File | Present (`orapworadb`) | YES | ✅ |
| Data Guard Configured | NO | Required for online physical migration | ⚠️ ZDM will configure |
| Available Disk Space (root) | 5.6 GB free | Recommend ≥ 10 GB | ⚠️ |

### Supplemental Logging Detail

| Logging Type | Enabled |
|-------------|---------|
| Minimal (ALL) | YES |
| Primary Key | NO |
| Unique Index | NO |
| Foreign Key | YES |
| All Columns | NO |

> Note: Minimal supplemental logging is sufficient for `ONLINE_PHYSICAL` migration. All columns logging is only required for logical migrations.

### Network / Listener

| Property | Value |
|----------|-------|
| Listener Port | 1521 |
| Listener Host | tm-oracle-iaas (TCP, PORT 1521) |
| Active Services | oradb1, oradb (CDB), oradbXDB, pdb1 |
| sqlnet.ora | Not found (default configuration) |

### Data Guard (Source)

| Parameter | Value |
|-----------|-------|
| db_unique_name | oradb1 |
| dg_broker_start | FALSE |
| log_archive_dest_2 | (empty) |
| log_archive_config | (empty) |
| standby_file_management | MANUAL |

> ZDM will configure `log_archive_dest_2` and Data Guard parameters automatically during `ONLINE_PHYSICAL` migration. No pre-configuration required.

### Database Links

| Owner | Link Name | Username | Host | Created |
|-------|-----------|----------|------|---------|
| SYS | SYS_HUB | SEEDDATA | — | 2017-01-26 |

> This is a system-generated CDB seed link. No action required.

### RMAN Configuration

| Setting | Value |
|---------|-------|
| Backup Optimization | ON |
| Controlfile Autobackup | ON |
| Autobackup Format | `/u01/app/oracle/fast_recovery_area/%F` |
| Default Device Type | DISK |
| Retention Policy | TO REDUNDANCY 1 |

---

## Target Environment Details

### Database Identification

| Property | Value |
|----------|-------|
| Hostname | tmodaauks-rqahk1 (Node 1) |
| FQDN | tmodaauks-rqahk1.ocioracle.ocitmvnetuks.oraclevcn.com |
| Oracle Instance | oradb011 (from listener services) |
| DB Unique Name | oradb01 (inferred from listener service names) |
| Grid Oracle Home | `/u01/app/19.0.0.0/grid` |
| Database Oracle Home | `/u02/app/oracle/product/19.0.0.0/dbhome_1` or `dbhome_2` (**confirm**) |
| Grid Version | 19.0.0.0.0 |
| Platform | ODAA (ExaDB-D on Azure) |

> ⚠️ **Target database was NOT OPEN during discovery.** Queries against `v$database` returned `ORA-01219`. Database configuration details (DB name, character set, open mode) could not be fully captured. The database was mounted but not open at discovery time.

### Operating System

| Property | Value |
|----------|-------|
| OS Version | Oracle Linux Server 8.10 |
| Kernel | 5.15.0-308.179.6.16.el8uek.x86_64 |
| Architecture | x86_64 |

### Network Interfaces

| Interface | IP Address | Type |
|-----------|-----------|------|
| bondeth0 | 10.0.1.160/24 | Primary |
| bondeth0:1 | 10.0.1.155/24 | VIP (Node 1) |
| bondeth0:3 | 10.0.1.200/24 | Secondary |
| bondeth0:4 | 10.0.1.159/24 | Secondary |
| bondeth1 | 192.168.255.151/22 | Private interconnect |
| stre0/stre1 | 100.106.64.130-131 | RDMA Storage |
| clre0/clre1 | 100.107.0.192-193 | Cluster interconnect |

### ASM Storage

| Disk Group | Type | Total (TB) | Free (TB) | Used % |
|------------|------|-----------|----------|--------|
| DATAC3 | HIGH | 4.90 | 4.13 | 15.7% |
| RECOC3 | HIGH | 1.22 | 1.05 | 14.3% |

> ✅ Ample storage available for the 2.15 GB source database.

### TDE / Wallet Configuration

| Property | Value |
|----------|-------|
| Wallet Status | OPEN_NO_MASTER_KEY |
| Wallet Type | UNKNOWN |
| Wallet Location | `/var/opt/oracle/dbaas_acfs/grid/tcps_wallets/` |

> ⚠️ **TDE wallet is open but has no master encryption key.** ZDM physical migration to ODAA requires TDE to be enabled on the source before migration, or TDE can be configured by ZDM as part of the migration process. If TDE is not enabled on the source, the `-tdekeystorepasswd` flag should **not** be used. Confirm the TDE strategy with the DBA team.

### Target Authentication

| Property | Value |
|----------|-------|
| Password File | NOT FOUND |
| Oracle user SSH | `.ssh/` directory present, `authorized_keys` configured |

> ⚠️ **Password file not found on target.** ZDM requires the target to have a password file for SYS authentication. One must be created: `orapwd file=/u02/app/oracle/product/19.0.0.0/dbhome_X/dbs/orapworadb01 password=<SYS_PASSWORD> entries=10`.

### Listener

| Property | Value |
|----------|-------|
| TCP Port 1521 | OPEN (10.0.1.160, 10.0.1.155, 10.0.1.200, 10.0.1.159) |
| TCPS Port 2484 | OPEN (10.0.1.155, 10.0.1.159, 10.0.1.200) |
| Active Services | +ASM, +APX, oradb011 (database instance), oradb01pdb |

---

## ZDM Server Details

### Installation

| Property | Value |
|----------|-------|
| Hostname | tm-vm-odaa-oracle-jumpbox |
| IP Address | 10.1.0.8 |
| OS Version | Oracle Linux Server 9.5 |
| ZDM Version | 21.5.0 (Build: Jul 24 2025) |
| ZDM Home | `/u01/app/zdmhome` |
| ZDM Base | `/u01/app/zdmbase` |
| ZDM Service | RUNNING ✅ |
| HTTP Port | 8898 |
| RMI Port | 8897 |
| Java Version | 1.8.0_451 |

### SSH Keys (zdmuser)

| Key File | Path | Purpose |
|----------|------|---------|
| iaas.pem | `/home/zdmuser/.ssh/iaas.pem` | Source database server |
| odaa.pem | `/home/zdmuser/.ssh/odaa.pem` | Target ODAA server |
| zdm.pem | `/home/zdmuser/.ssh/zdm.pem` | ZDM server self-access |
| id_rsa | `/home/zdmuser/.ssh/id_rsa` | General |
| id_ed25519 | `/home/zdmuser/.ssh/id_ed25519` | General |

> ⚠️ **Note: `zdm-env.md` lists `SOURCE_SSH_KEY: ~/.ssh/odaa.pem` for the source, but the ZDM server holds `iaas.pem` as the source key.** Based on prior successful ZDM EVAL jobs (Jobs 25–34), `iaas.pem` was used for the source (`-srcarg2 identity_file:/home/zdmuser/iaas.pem`). Confirm which key is correct for source SSH access.

### OCI CLI

| Property | Value |
|----------|-------|
| OCI CLI Version | 3.73.1 |
| OCI Config | NOT FOUND at `/home/azureuser/.oci/config` |

> ⚠️ **OCI CLI config is not set up on the ZDM server.** If using OCI Object Storage for backup/restore, the OCI config profile must be created at `/home/zdmuser/.oci/config` (the zdmuser context). The zdm-env.md has OCI credentials defined — these need to be written to the config file.

### Network Connectivity Tests

| Target | Ping | Port 22 (SSH) | Port 1521 (Oracle) |
|--------|------|---------------|-------------------|
| Source (10.1.0.11) | ✅ SUCCESS (avg RTT 1ms) | ✅ OPEN | ✅ OPEN |
| Target (10.0.1.160) | ❌ FAILED (ICMP blocked) | ✅ OPEN | ✅ OPEN |

> ✅ ICMP blocked to the ODAA target is **expected and normal**. ZDM uses SSH/TCP only — SSH and Oracle Listener ports are confirmed open.

### /etc/hosts (ZDM Server)

| IP | Hostname |
|----|---------|
| 10.0.1.160 | dbServer-1, tmodaauks-rqahk1 |
| 10.0.1.114 | dbServer-2, tmodaauks-rqahk2 |
| 10.0.1.155 | tmodaauks-rqahk1-vip |
| 10.0.1.142 | tmodaauks-rqahk2-vip |

> ℹ️ The ODAA environment appears to be a **2-node system** (rqahk1 / rqahk2). The ZDM env targets node 1 (10.0.1.160). Confirm which node ZDM should use as the `-targetnode`.

### Prior ZDM Job History Summary

| Jobs | Status | Notes |
|------|--------|-------|
| 1–15 | FAILED | Connectivity/configuration errors (placeholder RSP, wrong hostnames, wrong SIDs) |
| 16–17 | SUCCEEDED (EVAL) | Full precheck passed — different source/target nodes |
| 18–21 | FAILED (MIGRATE) | `ZDM_SETUP_TGT` and `ZDM_VALIDATE_TGT` failures — TDE and target configuration issues |
| 22–34 | FAILED (EVAL) | Multiple iterations for current ORADB project; recent failures at `ZDM_VALIDATE_TGT` suggesting TDE master key or DB unique name mismatch |

---

## Pre-Migration Actions Required

| # | Action | Owner | Priority |
|---|--------|-------|----------|
| 1 | Confirm target Oracle Home path (`dbhome_1` vs `dbhome_2`) | DBA/OCI | HIGH |
| 2 | Create password file on target ODAA node | DBA | HIGH |
| 3 | Resolve TDE strategy: configure TDE on source OR confirm no-TDE physical migration | DBA | HIGH |
| 4 | Configure OCI CLI on ZDM server (`/home/zdmuser/.oci/config`) with API key | ZDM Admin | HIGH |
| 5 | Confirm correct SSH key for source: `iaas.pem` vs `odaa.pem` | ZDM Admin | HIGH |
| 6 | Create OCI Object Storage bucket and note namespace/bucket name | OCI Admin | HIGH |
| 7 | Verify available disk space on source FRA for RMAN backup (currently 5.6 GB free on root) | DBA | MEDIUM |
| 8 | Confirm target DB unique name (`oradb01` assumed from listener services) | DBA | MEDIUM |
| 9 | Confirm which ODAA node to use as ZDM target node (rqahk1 or rqahk2) | OCI/DBA | MEDIUM |
| 10 | Verify source `SOURCE_SSH_USER` — zdm-env.md lists `azureuser`; confirm this user can `sudo -u oracle` on source | DBA | MEDIUM |

---

## Risks and Concerns

| Risk | Severity | Mitigation |
|------|----------|-----------|
| Target DB was not open during discovery — full target config unverified | HIGH | Open DB and re-run target discovery section manually or proceed with known values |
| TDE not configured on source; ODAA wallet has no master key | HIGH | Clarify TDE requirement with Oracle ODAA support; configure TDE if required before migration |
| Source root filesystem 81% full | MEDIUM | Monitor space during RMAN backup; extend root volume or relocate FRA if needed |
| No OCI Object Storage configured | MEDIUM | Required if using backup/restore method; configure before running ZDM |
| Version upgrade 12.2 → 19c | LOW | Supported path; ZDM runs `DATAPATCH` automatically post-migration |
| `dg_broker_start=FALSE` on source | LOW | ZDM ONLINE_PHYSICAL will configure Data Guard; DG Broker not required |
| Prior ZDM job failures at `ZDM_VALIDATE_TGT` | MEDIUM | Likely TDE-related; resolving TDE strategy should clear this |
