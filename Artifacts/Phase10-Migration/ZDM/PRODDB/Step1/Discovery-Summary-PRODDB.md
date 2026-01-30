# Discovery Summary: PRODDB Migration

## Generated
- **Date:** 2026-01-30
- **Source Files Analyzed:**
  - `zdm_source_discovery_temandin-oravm-vm01_20260130_220738.txt`
  - `zdm_target_discovery_tmodaauks-rqahk1_20260130_220814.txt`
  - `zdm_server_discovery_tm-vm-odaa-oracle-jumpbox_20260130_170816.txt`

---

## Executive Summary

| Component | Status | Key Findings |
|-----------|--------|--------------|
| Source Database | ✅ Ready | Oracle 19c, ARCHIVELOG mode, Force Logging enabled, TDE configured |
| Target Environment | ⚠️ Action Required | Exadata RAC (2-node), Multiple databases running, **Target PDB needs to be identified** |
| ZDM Server | ⚠️ Action Required | ZDM installed and running, **OCI CLI not installed**, disk space below recommended |
| Network | ✅ Ready | Connectivity verified to both source and target, ports 22 and 1521 open |

---

## Migration Method Recommendation

**Recommended:** `ONLINE_PHYSICAL`

**Justification:**
- ✅ Source database is in **ARCHIVELOG** mode (required for online migration)
- ✅ **Force Logging** is enabled
- ✅ **TDE** is configured with AUTOLOGIN wallet (simplifies migration)
- ✅ Database size is small (~1.88 GB) - fast initial sync
- ✅ Network connectivity is good (1.24ms latency to source)
- ⚠️ Supplemental logging needs to be enabled for online migration

**Alternative:** `OFFLINE_PHYSICAL` - Use if extended downtime is acceptable and simpler setup is preferred.

---

## Source Database Details

### Database Identification

| Property | Value |
|----------|-------|
| Hostname | temandin-oravm-vm01 |
| IP Address | 10.1.0.10 |
| Operating System | Oracle Linux Server 7.9 |
| Database Name | ORADB01 |
| DB Unique Name | oradb01 |
| DBID | 1593802201 |
| Oracle Version | 19.0.0.0.0 |
| ORACLE_HOME | /u01/app/oracle/product/19.0.0/dbhome_1 |
| ORACLE_SID | oradb01 |

### Database Configuration

| Property | Value |
|----------|-------|
| Database Role | PRIMARY |
| Open Mode | READ WRITE |
| Database Size (Data) | 1.88 GB |
| Database Size (Temp) | 0.03 GB |
| Character Set | AL32UTF8 |
| National Character Set | AL16UTF16 |
| CDB Status | NO (Non-CDB) |

### Configuration Status

| Requirement | Current State | Required State | Status |
|-------------|---------------|----------------|--------|
| ARCHIVELOG Mode | YES | YES | ✅ |
| Force Logging | YES | YES | ✅ |
| Supplemental Logging MIN | **NO** | YES (for online) | ⚠️ **Action Required** |
| Supplemental Logging PK | NO | Recommended | ⚠️ |
| TDE Enabled | YES (AUTOLOGIN) | Optional | ✅ |
| Password File | EXISTS | Required | ✅ |

### TDE Configuration

| Property | Value |
|----------|-------|
| Wallet Type | AUTOLOGIN |
| Wallet Status | OPEN |
| Wallet Location | /u01/app/oracle/admin/oradb01/wallet/tde/ |
| Master Key Created By | SYS (2026-01-28) |

### Redo Log Configuration

| Group | Size (MB) | Members | Status |
|-------|-----------|---------|--------|
| 1 | 200 | 1 | INACTIVE |
| 2 | 200 | 1 | CURRENT |
| 3 | 200 | 1 | INACTIVE |

### Archive Log Configuration

| Property | Value |
|----------|-------|
| Log Mode | ARCHIVELOG |
| Archive Destination | /u01/app/oracle/product/19.0.0/dbhome_1/dbs/arch |

### Tablespace Configuration

| Tablespace | Size (MB) | Autoextend | Max Size (MB) |
|------------|-----------|------------|---------------|
| SYSTEM | 910 | YES | 32,768 |
| SYSAUX | 670 | YES | 32,768 |
| UNDOTBS1 | 340 | YES | 32,768 |
| USERS | 5 | YES | 32,768 |

### Database Links

| Owner | DB Link Name | Username | Host |
|-------|--------------|----------|------|
| SYS | SYS_HUB | - | SEEDDATA |

> ⚠️ **Note:** Database link `SYS_HUB` will need to be reconfigured after migration.

### Scheduler Jobs (Enabled)

| Owner | Job Name | Schedule |
|-------|----------|----------|
| ORACLE_OCM | MGMT_CONFIG_JOB | Daily at 01:01 |
| ORACLE_OCM | MGMT_STATS_CONFIG_JOB | Monthly on 1st |
| SYS | BSLN_MAINTAIN_STATS_JOB | Weekly |
| SYS | CLEANUP_NON_EXIST_OBJ | Every 12 hours |
| SYS | ORA$AUTOTASK_CLEAN | Daily at 03:00 |
| SYS | PURGE_LOG | Daily at 03:00 |

> ⚠️ **Note:** Review scheduler jobs after migration to ensure they're appropriate for the target environment.

### Disk Space (Source)

| Mount Point | Size | Used | Available | Use% |
|-------------|------|------|-----------|------|
| / (root) | 30G | 20G | 8.2G | 71% |
| /u02 (Oracle Data) | 4.0T | 33M | 4.0T | 1% |

---

## Target Environment Details

### Target Identification

| Property | Value |
|----------|-------|
| Hostname | tmodaauks-rqahk1 (Node 1 of 2) |
| IP Address | 10.0.1.160 |
| Operating System | Oracle Linux Server 8.10 |
| Platform | Oracle Database@Azure (Exadata) |
| OCI Region | uk-london-1 |
| Availability Domain | uk-london-1-ad-2 |
| Shape | Exadata.X11M |

### RAC Configuration

| Property | Value |
|----------|-------|
| Cluster Type | RAC (2-node) |
| Node 1 | tmodaauks-rqahk1 |
| Node 2 | tmodaauks-rqahk2 |
| SCAN Listeners | 3 (LISTENER_SCAN1, LISTENER_SCAN2, LISTENER_SCAN3) |
| Grid Infrastructure | /u01/app/19.0.0.0/grid |
| Database Home | /u02/app/oracle/product/19.0.0.0/dbhome_1 |

### Existing Databases on Target

| Database | Status | Nodes | Notes |
|----------|--------|-------|-------|
| **MIGDB** | Open | 1, 2 | Previous migration database |
| **MYDB** | Open | 1, 2 | Test database |
| **ORADB01M** | Open | 1, 2 | ⚠️ **Possible target for this migration** |

> ⚠️ **Important:** Target database/PDB must be identified. `ORADB01M` appears to be provisioned for this migration based on naming convention.

### ASM Storage (Exadata)

| Diskgroup | Type | Total (GB) | Free (GB) | % Free | Status |
|-----------|------|------------|-----------|--------|--------|
| DATAC3 | HIGH | 4,896 | 4,128.86 | 84.33% | ✅ Sufficient |
| RECOC3 | HIGH | 1,224 | 1,053.05 | 86.03% | ✅ Sufficient |

### OCI Instance Metadata

| Property | Value |
|----------|-------|
| Instance ID | ocid1.instance.oc1.uk-london-1.anwgiljsgr62dgic4cub6udfash7igvt2ojxiboiibndwizljtwbm2gzjpiq |
| Compartment ID | ocid1.tenancy.oc1..aaaaaaaaax76pwvum5vhn2p3v264osde3ykrudasfzjktipw3ibpvtndhtkq |
| Fault Domain | FAULT-DOMAIN-2 |
| Cloud Provider | Azure |
| Cloud Provider Region | UK South |

### TDE Status (Target)

| Property | Value |
|----------|-------|
| Wallet Type | UNKNOWN |
| Wallet Status | OPEN_NO_MASTER_KEY |
| Wallet Location | /var/opt/oracle/dbaas_acfs/grid/tcps_wallets/ |

> ⚠️ **Note:** Target wallet shows `OPEN_NO_MASTER_KEY`. This is expected for a fresh PDB that will receive migrated data.

### Network Configuration

| Property | Status |
|----------|--------|
| Listener (Local) | ✅ Running |
| SCAN Listener 1 | ✅ Running on tmodaauks-rqahk2 |
| SCAN Listener 2 | ✅ Running on tmodaauks-rqahk1 |
| SCAN Listener 3 | ✅ Running on tmodaauks-rqahk1 |
| Port 1521 | ✅ Open |
| Port 2484 (TCPS) | ✅ Open |

---

## ZDM Server Details

### ZDM Server Identification

| Property | Value |
|----------|-------|
| Hostname | tm-vm-odaa-oracle-jumpbox |
| IP Address | 10.1.0.8 |
| Operating System | Oracle Linux Server 9.5 |
| Admin User | azureuser |
| ZDM User | zdmuser |

### ZDM Installation

| Property | Value |
|----------|-------|
| ZDM_HOME | /u01/app/zdmhome |
| ZDM Service Status | ✅ Running |
| HTTP Port | 8898 |
| RMI Port | 8897 |
| Wallet Path | /u01/app/zdmbase/crsdata/tm-vm-odaa-oracle-jumpbox/security |

### Java Configuration

| Property | Value |
|----------|-------|
| JAVA_HOME | /u01/app/zdmhome/jdk (bundled) |
| Java Version | 1.8.0_451 |

### OCI CLI Status

| Property | Value | Status |
|----------|-------|--------|
| OCI CLI Installed | NO | ❌ **Action Required** |
| OCI Config File | NOT FOUND | ❌ **Action Required** |

### SSH Keys (zdmuser)

| Key Type | Status |
|----------|--------|
| iaas.pem | ✅ Present |
| id_ed25519 | ✅ Present |
| id_rsa | ✅ Present |
| odaa.pem | ✅ Present |
| zdm.pem | ✅ Present |

### Disk Space (ZDM Server)

| Mount Point | Size | Available | Status |
|-------------|------|-----------|--------|
| / (root) | 39G | 25G | ⚠️ Below 50GB recommended |
| ZDM_HOME | - | 25G | ⚠️ Below 50GB recommended |

> ⚠️ **Warning:** Available disk space (25GB) is below the recommended 50GB for ZDM operations. Monitor during migration.

### Network Connectivity (from ZDM Server)

| Target | Ping | Latency | Port 22 | Port 1521 |
|--------|------|---------|---------|-----------|
| Source (10.1.0.10) | ✅ SUCCESS | 1.24ms | ✅ OPEN | ✅ OPEN |
| Target (10.0.1.160) | ⚠️ ICMP blocked | N/A | ✅ OPEN | ✅ OPEN |

> **Note:** ICMP is blocked to target (expected for Exadata), but TCP ports are accessible.

---

## Required Actions Before Migration

### Critical (Must Fix) 🔴

1. **Enable Supplemental Logging on Source**
   ```sql
   -- Connect as SYS to source database
   ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
   ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (PRIMARY KEY) COLUMNS;
   -- Verify
   SELECT supplemental_log_data_min, supplemental_log_data_pk FROM v$database;
   ```

2. **Install OCI CLI on ZDM Server**
   ```bash
   # As azureuser on ZDM server
   sudo bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"
   ```

3. **Configure OCI CLI on ZDM Server**
   ```bash
   # As zdmuser on ZDM server
   oci setup config
   # Enter: User OCID, Tenancy OCID, Region (uk-london-1), API key path
   ```

### Recommended (Should Fix) 🟡

1. **Create tnsnames.ora on Source** (for listener configuration)
   ```bash
   # Create proper TNS entries for migration connectivity
   ```

2. **Create SSH Keys for Oracle User on Source**
   ```bash
   # As oracle on source
   mkdir -p ~/.ssh
   chmod 700 ~/.ssh
   ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
   ```

3. **Create SSH Keys for Oracle User on Target**
   ```bash
   # As oracle on target
   mkdir -p ~/.ssh
   chmod 700 ~/.ssh
   ```

4. **Increase ZDM Server Disk Space** (if possible)
   - Current: 25GB available
   - Recommended: 50GB minimum

### Informational 🔵

1. **Database Link SYS_HUB** - Will need reconfiguration after migration
2. **Scheduler Jobs** - Review after migration for target environment compatibility
3. **Target Database Selection** - Confirm ORADB01M is the intended target

---

## Discovered Values Reference

### Source Database Values
```bash
SOURCE_HOST="10.1.0.10"
SOURCE_HOSTNAME="temandin-oravm-vm01"
SOURCE_DB_NAME="ORADB01"
SOURCE_DB_UNIQUE_NAME="oradb01"
SOURCE_ORACLE_HOME="/u01/app/oracle/product/19.0.0/dbhome_1"
SOURCE_ORACLE_SID="oradb01"
SOURCE_DBID="1593802201"
SOURCE_VERSION="19.0.0.0.0"
SOURCE_CHARACTER_SET="AL32UTF8"
SOURCE_LOG_MODE="ARCHIVELOG"
SOURCE_TDE_WALLET="/u01/app/oracle/admin/oradb01/wallet/tde/"
SOURCE_TDE_STATUS="AUTOLOGIN"
SOURCE_CDB="NO"
```

### Target Database Values
```bash
TARGET_HOST="10.0.1.160"
TARGET_HOSTNAME="tmodaauks-rqahk1"
TARGET_ORACLE_HOME="/u02/app/oracle/product/19.0.0.0/dbhome_1"
TARGET_GRID_HOME="/u01/app/19.0.0.0/grid"
TARGET_DB_NAME="ORADB01M"  # Confirm this is the target
TARGET_REGION="uk-london-1"
TARGET_COMPARTMENT_OCID="ocid1.tenancy.oc1..aaaaaaaaax76pwvum5vhn2p3v264osde3ykrudasfzjktipw3ibpvtndhtkq"
TARGET_ASM_DISKGROUP="+DATAC3"
TARGET_RECO_DISKGROUP="+RECOC3"
```

### ZDM Server Values
```bash
ZDM_HOST="10.1.0.8"
ZDM_HOSTNAME="tm-vm-odaa-oracle-jumpbox"
ZDM_HOME="/u01/app/zdmhome"
ZDM_USER="zdmuser"
ZDM_ADMIN_USER="azureuser"
ZDM_JAVA_HOME="/u01/app/zdmhome/jdk"
```

### OCI Values (To Be Completed in Questionnaire)
```bash
OCI_TENANCY_OCID="<from questionnaire>"
OCI_USER_OCID="<from questionnaire>"
OCI_COMPARTMENT_OCID="<from questionnaire>"
OCI_REGION="uk-london-1"
TARGET_DB_SYSTEM_OCID="<from questionnaire>"
TARGET_DATABASE_OCID="<from questionnaire>"
OCI_OSS_NAMESPACE="<from questionnaire>"
OCI_OSS_BUCKET_NAME="zdm-migration-proddb"
```

---

## Next Steps

1. ✅ Review this Discovery Summary
2. ⬜ Complete the Migration Questionnaire (Migration-Questionnaire-PRODDB.md)
3. ⬜ Run Step 2: Fix identified issues
4. ⬜ Run Step 3: Generate migration artifacts
