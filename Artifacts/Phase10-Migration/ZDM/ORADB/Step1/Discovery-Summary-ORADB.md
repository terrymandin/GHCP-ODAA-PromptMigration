# Discovery Summary: ORADB Migration

## Generated
- **Date:** 2026-03-02
- **Source Files Analyzed:**
  - `zdm_source_discovery_tm-oracle-iaas_20260302_212023.txt`
  - `zdm_target_discovery_tmodaauks-rqahk1_20260302_212027.txt`
  - `zdm_server_discovery_tm-vm-odaa-oracle-jumpbox_20260302_162029.txt`

---

## Executive Summary

| Component | Status | Key Findings |
|-----------|--------|--------------|
| Source Database | ⚠️ | Oracle 12.2.0.1.0 CDB; ARCHIVELOG ✅; Force Logging ✅; PDB1 MOUNTED (not open) ⚠️; Minimal supplemental logging only ⚠️ |
| Target Environment | ✅ | Oracle 19.29.0.0.0 on ODAA 2-node RAC; ASM storage healthy; CRS online |
| ZDM Server | ⚠️ | ZDM 21.5.0 running; OCI config missing for azureuser; disk space < 50GB |
| Network | ✅ | Azure ↔ OCI cross-cloud connectivity verified (prior jobs succeeded) |

---

## Migration Method Recommendation

**Recommended:** `ONLINE_PHYSICAL`

**Justification:**
- Source database is in ARCHIVELOG mode ✅
- Force Logging is enabled ✅
- ZDM physical migration supports cross-version upgrades (12.2 → 19c) ✅
- Database is small (2.08 GB) — low risk, fast transfer ✅
- This is an Azure IaaS → ODAA (Oracle Database@Azure) migration — cross-cloud connectivity is confirmed working via prior ZDM eval jobs ✅
- Online physical migration minimises downtime using Data Guard re-synchronisation before switchover

**Pre-condition:** Supplemental logging must be fully enabled and PDB1 must be opened before starting the migration.

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
| ORACLE_HOME | /u01/app/oracle/product/12.2.0/dbhome_1 |
| Container Type | CDB |
| PDB Name | PDB1 |
| PDB Status | MOUNTED ⚠️ (must be OPEN before migration) |
| Created | 23-FEB-26 |

### OS Environment

| Property | Value |
|----------|-------|
| Hostname | tm-oracle-iaas |
| IP Address | 10.1.0.11/24 |
| OS | Oracle Linux Server 7.4 |
| Kernel | 4.1.12-124.14.1.el7uek.x86_64 |
| Architecture | x86_64 |
| Root Disk Free | 6.3 GB (78% used) ⚠️ |
| Admin User | azureuser |
| SSH Key | ~/.ssh/odaa.pem |

### Configuration Status

| Requirement | Current State | Required State | Status |
|-------------|---------------|----------------|--------|
| ARCHIVELOG Mode | YES | YES | ✅ |
| Force Logging | YES | YES | ✅ |
| Supplemental Logging (Minimal) | YES | YES | ✅ |
| Supplemental Logging (All Columns) | NO | YES (for online) | ⚠️ Action Required |
| PDB1 Open Mode | MOUNTED | READ WRITE | ⚠️ Action Required |
| TDE Enabled | NOT_AVAILABLE | N/A | ✅ (no TDE complexity) |
| Password File | Exists | YES | ✅ |
| Database Role | PRIMARY | PRIMARY | ✅ |
| Open Mode | READ WRITE | READ WRITE | ✅ |
| Protection Mode | MAXIMUM PERFORMANCE | N/A | ✅ |
| DG Broker | FALSE | N/A (ZDM manages DG) | ✅ |

### Database Sizing

| Component | Size |
|-----------|------|
| Total Data Files | 2.08 GB |
| Temp Files | 0.03 GB |
| SYSAUX Tablespace | 0.986 GB (32 GB max) |
| SYSTEM Tablespace | 0.811 GB (32 GB max) |
| UNDOTBS1 Tablespace | 0.283 GB (32 GB max) |
| USERS Tablespace | 0.005 GB (32 GB max) |

> All tablespaces use autoextend. No user data tablespaces > 100 MB were found (only system schemas).

### Character Sets

| Parameter | Value |
|-----------|-------|
| NLS_CHARACTERSET | AL32UTF8 |
| NLS_NCHAR_CHARACTERSET | AL16UTF16 |

### Network / Connectivity

| Component | Value |
|-----------|-------|
| Listener Status | RUNNING ✅ |
| Listener Port | 1521 (TCP) |
| Listener Host | tm-oracle-iaas.s15cwnltpnyuher1lvdjg5qxtd.zx.internal.cloudapp.net |
| Services | ORADB1, oradbXDB, pdb1, 4b85b38ae4551c7fe0630b00010aad3c |
| tnsnames.ora | oradb → (TCP 10.1.0.11:1521, SERVICE_NAME=oradb) |
| Archive Log Dest 1 | LOCATION=/u01/app/oracle/fast_recovery_area |

### RMAN / Backup

| Property | Value |
|----------|-------|
| Controlfile Autobackup | ON ✅ |
| Default Device Type | DISK |
| Backup Optimisation | ON |
| Retention Policy | TO REDUNDANCY 1 |

### Supplemental Logging Detail

| Type | Status |
|------|--------|
| Minimal (LOG_DATA_MIN) | YES ✅ |
| All Columns | NO ⚠️ |
| Primary Key | NO ⚠️ |
| Unique | NO |
| Foreign Key | YES |

### Discovery Errors / Warnings

| Severity | Message | Impact |
|----------|---------|--------|
| ERROR | TDE section failed | Non-critical — no TDE configured, section query failed |
| ERROR | Network configuration section failed (sqlnet.ora) | Non-critical — listener is working |
| WARN | Oracle user .ssh directory not found | Not a blocker — ZDM uses azureuser with sudo |

---

## Target Environment Details

### Environment Identification

| Property | Value |
|----------|-------|
| Hostname | tmodaauks-rqahk1 (Node 1), tmodaauks-rqahk2 (Node 2) |
| IP Address | 10.0.1.160/24 (primary), 10.0.1.155/24 (TCPS), additional VIPs |
| OS | Oracle Linux Server 8.10 |
| Kernel | 5.15.0-308.179.6.16.el8uek.x86_64 |
| Oracle Version | 19.0.0.0.0 (19.29.0.0.0) |
| ORACLE_HOME | /u02/app/oracle/product/19.0.0.0/dbhome_1 |
| Grid Home | /u01/app/19.0.0.0/grid |
| ASM SID | +ASM1 |
| Cluster Type | 2-node RAC (ODAA) |
| Admin User | opc |
| SSH Key | ~/.ssh/odaa.pem (on ZDM server: /home/zdmuser/odaa.pem) |

### Target Database Info

| Property | Value |
|----------|-------|
| CDB Name | oradb01m (from listener service: `oradb01m.ocioracle...`) |
| PDB Name | oradb01pdb (from listener service: `oradb01pdb.ocioracle...`) |
| Instance Name | oradb011 |
| DB State During Discovery | NOT MOUNTED (expected — pre-migration state) |

### ASM Storage

| Disk Group | Total | Free | Used % | Status |
|------------|-------|------|--------|--------|
| DATAC3 | 4,896 GB | 4,128 GB | 15.7% | MOUNTED ✅ |
| RECOC3 | 1,224 GB | 1,048 GB | 14.3% | MOUNTED ✅ |

> Ample storage for 2.08 GB source database + Data Guard logs.

### Target Connectivity

| Component | Value |
|-----------|-------|
| Listener TCP | 10.0.1.160:1521 ✅ |
| Listener TCPS | 10.0.1.155:2484 ✅ |
| CRS Status | ONLINE ✅ |
| Grid Infrastructure | CRS, CRS, CSA, EVM all online ✅ |
| TDE Wallet | OPEN_NO_MASTER_KEY (normal for pre-migration target) |

### Discovery Results

| Metric | Value |
|--------|-------|
| Errors | 0 ✅ |
| Warnings | 0 ✅ |
| Completed | Mon Mar 2 21:20:28 UTC 2026 |

> Note: SQL query failures (ORA-01507, ORA-01219) for database-level queries are expected because the target database was not mounted during discovery — this is normal pre-migration state.

---

## ZDM Server Details

### Server Identification

| Property | Value |
|----------|-------|
| Hostname | tm-vm-odaa-oracle-jumpbox |
| IP Address | 10.1.0.8/24 |
| OS | Oracle Linux Server 9.5 |
| Kernel | 5.15.0-307.178.5.el9uek.x86_64 |
| Admin User | azureuser |
| ZDM User | zdmuser |
| ZDM Home | /u01/app/zdmhome |
| ZDM Version | 21.5.0 (Build: Jul 24 2025) |
| ZDM Service | RUNNING ✅ |

### ZDM Service Ports

| Port | Purpose |
|------|---------|
| 8897 | RMI |
| 8898 | HTTP |
| 8899 | MySQL (internal) |

### ZDM Resources

| Resource | Status |
|----------|--------|
| zdmcli binary | /u01/app/zdmhome/bin/zdmcli ✅ |
| Physical template | /u01/app/zdmhome/rhp/zdm/template/zdm_template.rsp ✅ |
| Physical XTTS template | /u01/app/zdmhome/rhp/zdm/template/zdm_xtts_template.rsp ✅ |
| Logical template | /u01/app/zdmhome/rhp/zdm/template/zdm_logical_template.rsp ✅ |
| Response file (current) | /home/zdmuser/iaas_to_odaa.rsp ✅ |
| Source SSH key | /home/zdmuser/iaas.pem ✅ |
| Target SSH key | /home/zdmuser/odaa.pem ✅ |
| Java | 1.8.0_451 at /u01/app/zdmhome/jdk ✅ |
| OCI CLI | 3.73.1 installed ✅ |
| OCI config (zdmuser) | **Not verified** ⚠️ |
| OCI config (azureuser) | Not found at ~/.oci/config ⚠️ |

### ZDM Server Disk Space

| Filesystem | Size | Free | Status |
|------------|------|------|--------|
| / (rootvg-rootlv) | 39 GB | 24 GB | ⚠️ Below 50 GB recommended |
| /mnt (temp) | 16 GB | 15 GB | ⚠️ Below 50 GB recommended |

### ZDM Job History

| Job ID | Type | Status | Notes |
|--------|------|--------|-------|
| 16 | EVAL | SUCCEEDED | All prechecks passed |
| 17 | EVAL | SUCCEEDED | All prechecks passed |
| 18–21 | MIGRATE | FAILED/ABORTED | ZDM_SETUP_TGT / ZDM_VALIDATE_TGT issues |
| 22–34 | EVAL | FAILED | Working on iaas_to_odaa.rsp (incremental tuning) |

> Jobs 16 and 17 confirmed that EVAL prechecks can fully pass for a similar migration configuration. The remaining EVAL failures (jobs 22–34) indicate ongoing tuning of source/target DB identification and supplemental logging configuration — exactly the items flagged in this discovery.

---

## Required Actions Before Migration

### Critical (Must Fix Before Starting Migration)

| # | Action | Command / Steps | Reason |
|---|--------|-----------------|--------|
| 1 | **Open PDB1** | `sqlplus / as sysdba` → `ALTER PLUGGABLE DATABASE PDB1 OPEN;` → `ALTER PLUGGABLE DATABASE PDB1 SAVE STATE;` | PDB1 is currently MOUNTED — ZDM physical migration requires the source PDB to be in READ WRITE state |
| 2 | **Enable ALL COLUMNS supplemental logging** | `sqlplus / as sysdba` → `ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;` | Online physical migration requires full supplemental logging to apply redo at target |
| 3 | **Configure OCI config for zdmuser on ZDM server** | As zdmuser: create `~/.oci/config` with tenancy, user, fingerprint, key, and region values | Required for ZDM to interact with OCI Object Storage and verify target DB details |

### Recommended (Fix Before Migration for Best Results)

| # | Action | Details |
|---|--------|---------|
| 4 | **Monitor source disk space** | Root filesystem at 78% used (6.3 GB free). Ensure archive log destination has sufficient space during migration. Consider increasing or redirecting archive logs to /mnt/resource (16 GB partition). |
| 5 | **Expand ZDM server root filesystem** | Only 24 GB free on /; ZDM recommends 50+ GB for staging. |
| 6 | **Verify zdmuser OCI config** | Ensure `~/.oci/config` for zdmuser points to the correct API key and region (uk-london-1). The OCI config for azureuser (`/home/azureuser/.oci/config`) was not found. |
| 7 | **Confirm target DB name for ZDM** | The target CDB instance is `oradb011` (from listener). Confirm the exact target `-sourcedb` name matches the db_unique_name registered on the target. |

---

## Discovered Values Reference

These values are auto-populated from discovery for use in Step 2 and Step 3:

```
# Source Database
SOURCE_HOST:           tm-oracle-iaas (10.1.0.11)
SOURCE_SSH_USER:       azureuser
SOURCE_SSH_KEY:        /home/zdmuser/iaas.pem
SOURCE_ORACLE_SID:     oradb
SOURCE_DB_NAME:        ORADB1
SOURCE_DB_UNIQUE_NAME: oradb1
SOURCE_DBID:           2571197414
SOURCE_VERSION:        12.2.0.1.0
SOURCE_ORACLE_HOME:    /u01/app/oracle/product/12.2.0/dbhome_1
SOURCE_ORACLE_BASE:    /u01/app/oracle
SOURCE_CDB:            YES
SOURCE_PDB_NAME:       PDB1
SOURCE_CHAR_SET:       AL32UTF8
SOURCE_NCHAR_SET:      AL16UTF16
SOURCE_ARCHIVELOG:     YES
SOURCE_FORCE_LOGGING:  YES
SOURCE_ARCHIVE_DEST:   /u01/app/oracle/fast_recovery_area
SOURCE_LISTENER_PORT:  1521

# Target Database
TARGET_HOST:           tmodaauks-rqahk1 (10.0.1.160)
TARGET_SSH_USER:       opc
TARGET_SSH_KEY:        /home/zdmuser/odaa.pem
TARGET_ORACLE_HOME:    /u02/app/oracle/product/19.0.0.0/dbhome_1
TARGET_GRID_HOME:      /u01/app/19.0.0.0/grid
TARGET_VERSION:        19.0.0.0.0 (19.29)
TARGET_INSTANCE:       oradb011
TARGET_CDB:            YES (ODAA managed CDB)
TARGET_PDB:            oradb01pdb
TARGET_LISTENER_PORT:  1521
TARGET_CLUSTER:        2-node RAC (tmodaauks-rqahk1, tmodaauks-rqahk2)
TARGET_ASM_DATA_DG:    DATAC3 (4128 GB free)
TARGET_ASM_RECO_DG:    RECOC3 (1048 GB free)

# ZDM Server
ZDM_HOST:              tm-vm-odaa-oracle-jumpbox (10.1.0.8)
ZDM_HOME:              /u01/app/zdmhome
ZDM_BASE:              /u01/app/zdmbase
ZDM_USER:              zdmuser
ZDM_VERSION:           21.5.0
ZDM_RSP_FILE:          /home/zdmuser/iaas_to_odaa.rsp

# OCI Configuration (from zdm-env.md)
OCI_TENANCY_OCID:      ocid1.tenancy.oc1..aaaaaaaarvyhjcn7wkkxxx5g3o7lgqks23bmsjtsticz3gtg5xs5qyrwkftq
OCI_USER_OCID:         ocid1.user.oc1..aaaaaaaakfe5cirdq7vkkrhogjrgcrgftvwb7mdoehujgchefpqv54vhsnoa
OCI_COMPARTMENT_OCID:  ocid1.compartment.oc1..aaaaaaaas4upnqj72dfiivgwvn3uui5gkxo7ng6leeoifucbjiy326urbhmq
TARGET_DATABASE_OCID:  ocid1.database.oc1.uk-london-1.anwgiljss56liuaatz45cjnpbvpgku7gkorvxg6lytoj5lxxruk2eqxzkzma
OCI_FINGERPRINT:       7f:05:c1:f2:5c:3a:46:ec:9f:95:44:c8:77:a4:50:f9
OCI_REGION:            uk-london-1
OCI_CONFIG_PATH:       ~/.oci/config (zdmuser)
OCI_PRIVATE_KEY_PATH:  ~/.oci/oci_api_key.pem
OCI_OSS_NAMESPACE:     *** NOT SET — manual entry required ***
OCI_OSS_BUCKET_NAME:   *** NOT SET — manual entry required ***
```
