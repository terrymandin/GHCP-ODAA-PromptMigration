# Discovery Summary: PRODDB Migration

## Generated
- **Date:** 2026-01-30
- **Source Files Analyzed:**
  - `zdm_source_discovery_temandin-oravm-vm01_20260130_204604.json`
  - `zdm_source_discovery_temandin-oravm-vm01_20260130_204604.txt`
  - `zdm_target_discovery_tmodaauks-rqahk1_20260130_204655.json`
  - `zdm_target_discovery_tmodaauks-rqahk1_20260130_204655.txt`
  - `zdm_server_discovery_tm-vm-odaa-oracle-jumpbox_20260130_154712.json`
  - `zdm_server_discovery_tm-vm-odaa-oracle-jumpbox_20260130_154712.txt`

---

## Executive Summary

| Component | Status | Key Findings |
|-----------|--------|--------------|
| Source Database | ✅ Ready | ARCHIVELOG enabled, Force Logging ON, TDE enabled with AUTOLOGIN wallet |
| Target Environment | ⚠️ Needs Attention | Exadata target identified, but database not yet created/running (ORA-01034 errors expected) |
| ZDM Server | ⚠️ Action Required | Service running, but OCI CLI not installed, low disk space (25GB), network connectivity issues |
| Network | ❌ Requires Action | Cannot reach source/target from ZDM server, firewall/NSG rules needed |

---

## Migration Method Recommendation

**Recommended:** `ONLINE_PHYSICAL` ✓

**Justification:**
- Source database is in **ARCHIVELOG** mode (required for online migration)
- **Force Logging** is enabled (required for Data Guard synchronization)
- **TDE** is enabled with **AUTOLOGIN** wallet (simplifies migration)
- Source is a **non-CDB** database (simpler migration path)
- Database size is small (**1.88 GB**) - minimal synchronization time
- Source is on **Oracle 19c**, target is **Oracle 19c** (version compatible)

**Considerations:**
- Supplemental logging is **NOT** enabled - **must be enabled before migration**
- Target database is on **Oracle Database@Azure (Exadata)** - uses RMAN-based migration
- Database link `SYS_HUB` exists and may need to be recreated post-migration

---

## Source Database Details

### Database Identification

| Property | Value |
|----------|-------|
| Database Name | ORADB01 |
| DB Unique Name | oradb01 |
| DBID | 1593802201 |
| Oracle SID | oradb01 |
| Database Role | PRIMARY |
| Open Mode | READWRITE |
| Platform | Linux x86 64-bit |

### Version and Environment

| Property | Value |
|----------|-------|
| Oracle Version | 19.0.0.0.0 |
| ORACLE_HOME | /u01/app/oracle/product/19.0.0/dbhome_1 |
| ORACLE_BASE | /u01/app/oracle/product |
| Hostname | temandin-oravm-vm01.s15cwnltpnyuher1lvdjg5qxtd.zx.internal.cloudapp.net |
| IP Address | 10.1.0.10 |
| OS Version | Oracle Linux Server 7.9 |
| Kernel | 4.14.35-1902.10.7.el7uek.x86_64 |

### Container Database Status

| Property | Value |
|----------|-------|
| CDB Status | NO (Non-CDB) |
| PDBs | N/A |

### Database Size

| Type | Size (GB) |
|------|-----------|
| Data Files | 1.88 |
| Temp Files | 0.03 |
| Redo Logs | 0.59 |
| **Total** | **~2.5 GB** |

### Character Set

| Property | Value |
|----------|-------|
| Character Set | AL32UTF8 |
| National Character Set | AL16UTF16 |

### Configuration Status (Migration Readiness)

| Requirement | Current State | Required State | Status |
|-------------|---------------|----------------|--------|
| ARCHIVELOG Mode | YES | YES | ✅ |
| Force Logging | YES | YES | ✅ |
| TDE Enabled | YES | YES | ✅ |
| TDE Wallet Type | AUTOLOGIN | AUTOLOGIN | ✅ |
| Supplemental Logging (Minimal) | NO | YES (for online) | ⚠️ **Action Required** |
| Supplemental Logging (PK) | NO | Recommended | ⚠️ |
| Supplemental Logging (UI) | NO | Recommended | ⚠️ |

### TDE Configuration

| Property | Value |
|----------|-------|
| TDE Enabled | YES |
| Wallet Type | AUTOLOGIN |
| Wallet Location | /u01/app/oracle/admin/oradb01/wallet/tde/ |
| Wallet Status | OPEN |
| Encrypted Tablespaces | (Default encryption) |

### Redo Log Configuration

| Property | Value |
|----------|-------|
| Number of Redo Groups | 3 |
| Redo Log Size | 200 MB per group |
| Total Redo Size | 600 MB |
| Archive Destination | /u01/app/oracle/product/19.0.0/dbhome_1/dbs/arch |

### Authentication

| Property | Value |
|----------|-------|
| Password File | /u01/app/oracle/product/19.0.0/dbhome_1/dbs/orapworadb01 |
| Password File Exists | YES |

### Database Links

| Owner | DB Link Name | Username | Status |
|-------|--------------|----------|--------|
| SYS | SYS_HUB | CURRENT_USER → SEEDDATA | ⚠️ Review post-migration |

### Tablespace Configuration

| Tablespace | Used (GB) | Max (GB) | % Used | AutoExtend |
|------------|-----------|----------|--------|------------|
| SYSAUX | 0.65 | 32 | 2.04% | YES |
| SYSTEM | 0.89 | 32 | 2.78% | YES |
| UNDOTBS1 | 0.33 | 32 | 1.04% | YES |
| USERS | 0.00 | 32 | 0.02% | YES |

### Backup Configuration

| Property | Value |
|----------|-------|
| CONTROLFILE AUTOBACKUP | ON |

### Network Configuration (Source)

| Property | Value |
|----------|-------|
| Listener Status | Running on port 1521 |
| Service Names | oradb01, oradb01XDB |
| tnsnames.ora | Not configured |
| sqlnet.ora | Not configured |

---

## Target Environment Details

### Environment Identification

| Property | Value |
|----------|-------|
| Hostname | tmodaauks-rqahk1.ocioracle.ocitmvnetuks.oraclevcn.com |
| Short Hostname | tmodaauks-rqahk1 |
| Cloud Provider | Azure (Oracle Database@Azure) |
| Platform Type | Exadata |
| RAC Status | Single Instance (RAC disabled) |

### Version and Environment

| Property | Value |
|----------|-------|
| Oracle Version | 19.0.0.0.0 |
| ORACLE_HOME | /u02/app/oracle/product/19.0.0.0/dbhome_1 |
| ORACLE_BASE | /u02/app/oracle/product |
| OS Version | Oracle Linux Server 8.10 |
| Kernel | 5.15.0-308.179.6.16.el8uek.x86_64 |
| Current ORACLE_SID | +ASM1 (ASM instance - target DB not yet created) |

### IP Addresses

| Type | Address |
|------|---------|
| Primary IPs | 10.0.1.160, 10.0.1.159, 10.0.1.155, 10.0.1.200 |
| Internal/Cluster IPs | 192.168.255.151, 169.254.200.2 |
| OCI Backend IPs | 100.106.64.130, 100.106.64.131, 100.107.0.192, 100.107.0.193 |

### Database Status

| Property | Status |
|----------|--------|
| Database Instance | ⚠️ ORA-01034 - Database not started/created |
| Explanation | This is expected for a fresh target - database will be created during ZDM migration |

### TDE Configuration (Target)

| Property | Value |
|----------|-------|
| TDE Enabled | NOT ENABLED |
| Note | TDE will be configured during migration |

### Existing Databases on Target (from Listener)

| Database | Instance | Status |
|----------|----------|--------|
| migdb | migdb1 | READY |
| mydb | mydb1 | READY |
| oradb01 | oradb011 | READY (previous migration?) |

⚠️ **Note:** There appears to be an existing `oradb01` database on the target from a previous migration attempt.

### Listener Configuration

| Property | Value |
|----------|-------|
| Listener Status | Running |
| Ports | 1521 (TCP), 2484 (TCPS) |
| Grid Listener | /u01/app/19.0.0.0/grid/network/admin/listener.ora |

### OCI/Azure Integration

| Property | Value |
|----------|-------|
| OCI CLI Installed | NO |
| Azure Metadata Available | No (404 response) |

---

## ZDM Server Details

### Server Identification

| Property | Value |
|----------|-------|
| Hostname | tm-vm-odaa-oracle-jumpbox.s15cwnltpnyuher1lvdjg5qxtd.zx.internal.cloudapp.net |
| Short Hostname | tm-vm-odaa-oracle-jumpbox |
| IP Address | 10.1.0.8 |
| Current User | azureuser |

### OS Environment

| Property | Value |
|----------|-------|
| OS Version | Oracle Linux Server 9.5 |
| Kernel | 5.15.0-307.178.5.el9uek.x86_64 |

### ZDM Installation

| Property | Value |
|----------|-------|
| ZDM_HOME | /u01/app/zdmhome |
| JAVA_HOME | /u01/app/zdmhome/jdk |
| ZDM Log Directory | /u01/app/zdmhome/log |
| ZDM Wallet Path | /u01/app/zdmbase/crsdata/tm-vm-odaa-oracle-jumpbox/security |

### ZDM Service Status

| Property | Value |
|----------|-------|
| Service Running | YES |
| RMI Port | 8897 |
| HTTP Port | 8898 |
| MySQL Conn String | jdbc:mysql://localhost:8899/ |
| Active Migration Jobs | 0 |

### Disk Space

| Filesystem | Size | Used | Available | Use% | Mounted On |
|------------|------|------|-----------|------|------------|
| /dev/mapper/rootvg-rootlv | 39G | 14G | 25G | 36% | / (ZDM_HOME) |
| /dev/sdb1 | 16G | 28K | 15G | 1% | /mnt |
| /dev/sda2 | 736M | 387M | 350M | 53% | /boot |

| Warning | Details |
|---------|---------|
| ⚠️ LOW DISK SPACE | Only **25 GB** available. Recommended minimum is **50 GB** for ZDM operations. |

### OCI/Azure CLI

| Tool | Status |
|------|--------|
| OCI CLI | ❌ NOT INSTALLED |

### Credential Files Found

| File | Path |
|------|------|
| SSH Private Key | /home/azureuser/key.pem |

### ZDM Response File Templates

| Template | Path |
|----------|------|
| Physical Migration | /u01/app/zdmhome/rhp/zdm/template/zdm_template.rsp |
| Logical Migration | /u01/app/zdmhome/rhp/zdm/template/zdm_logical_template.rsp |
| XTTS Migration | /u01/app/zdmhome/rhp/zdm/template/zdm_xtts_template.rsp |

### Network Connectivity

| Test | Result |
|------|--------|
| Ping to Source | ❌ UNREACHABLE |
| Ping to Target | ❌ UNREACHABLE |
| SSH to Source (Port 22) | ❌ CLOSED/FILTERED |
| SSH to Target (Port 22) | ❌ CLOSED/FILTERED |
| Oracle to Source (Port 1521) | ❌ CLOSED/FILTERED |
| Oracle to Target (Port 1521) | ❌ CLOSED/FILTERED |

---

## Required Actions Before Migration

### ❌ Critical (Must Fix)

1. **Enable Supplemental Logging on Source Database**
   ```sql
   -- Connect to source database as SYS
   ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
   ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (PRIMARY KEY) COLUMNS;
   ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (UNIQUE INDEX) COLUMNS;
   
   -- Verify
   SELECT supplemental_log_data_min, supplemental_log_data_pk, supplemental_log_data_ui
   FROM v$database;
   ```

2. **Install OCI CLI on ZDM Server**
   ```bash
   # As azureuser on ZDM server
   sudo dnf install python3-oci-cli -y
   # OR
   bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"
   
   # Configure OCI CLI
   oci setup config
   ```

3. **Fix Network Connectivity**
   - Configure Azure NSG rules to allow:
     - ZDM Server (10.1.0.8) → Source (10.1.0.10): Ports 22, 1521
     - ZDM Server (10.1.0.8) → Target (10.0.1.155): Ports 22, 1521
   - Verify peering/routing between VNets if source and target are in different VNets
   - Test connectivity after NSG changes:
     ```bash
     # From ZDM server
     nc -zv 10.1.0.10 22
     nc -zv 10.1.0.10 1521
     nc -zv 10.0.1.155 22
     nc -zv 10.0.1.155 1521
     ```

4. **Configure SSH Key Authentication**
   - Generate SSH keys for ZDM user (zdmuser) if not exists
   - Copy public key to source Oracle user's authorized_keys
   - Copy public key to target Oracle user's authorized_keys
   ```bash
   # As zdmuser on ZDM server
   ssh-keygen -t rsa -b 4096
   ssh-copy-id oracle@10.1.0.10
   ssh-copy-id oracle@10.0.1.155
   ```

### ⚠️ Recommended

1. **Increase ZDM Server Disk Space**
   - Current: 25 GB available
   - Recommended: 50+ GB
   - Options:
     - Extend root volume
     - Add additional volume and mount at /u01

2. **Create tnsnames.ora on Source**
   ```bash
   # Create basic tnsnames.ora
   cat > $ORACLE_HOME/network/admin/tnsnames.ora << 'EOF'
   ORADB01 =
     (DESCRIPTION =
       (ADDRESS = (PROTOCOL = TCP)(HOST = temandin-oravm-vm01)(PORT = 1521))
       (CONNECT_DATA =
         (SERVICE_NAME = oradb01)
       )
     )
   EOF
   ```

3. **Verify Java Installation on ZDM Server**
   ```bash
   # Check Java version
   $ZDM_HOME/jdk/bin/java -version
   ```

4. **Review Database Link SYS_HUB**
   - This link may need to be recreated post-migration with updated connection string

5. **Clear Any Previous Migration Artifacts**
   - Existing `oradb01` database detected on target - confirm if cleanup needed

---

## Discovered Values Reference

### Source Database Values (for RSP file)

```properties
# Source Database Configuration
SOURCEDATABASE_CONNECTIONSTRING=temandin-oravm-vm01.s15cwnltpnyuher1lvdjg5qxtd.zx.internal.cloudapp.net:1521/oradb01
SOURCEDATABASE_ADMINUSERNAME=SYS
SOURCEDATABASE_DBID=1593802201
SOURCE_HOSTNAME=temandin-oravm-vm01
SOURCE_IP=10.1.0.10
SOURCE_ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1
SOURCE_ORACLE_SID=oradb01
SOURCE_DB_NAME=ORADB01
SOURCE_DB_UNIQUE_NAME=oradb01
SOURCE_CHARACTER_SET=AL32UTF8
SOURCE_TDE_WALLET=/u01/app/oracle/admin/oradb01/wallet/tde/
```

### Target Environment Values (for RSP file)

```properties
# Target Database Configuration (ODAA Exadata)
TARGET_HOSTNAME=tmodaauks-rqahk1.ocioracle.ocitmvnetuks.oraclevcn.com
TARGET_IP=10.0.1.155
TARGET_ORACLE_HOME=/u02/app/oracle/product/19.0.0.0/dbhome_1
CLOUD_PROVIDER=Azure
PLATFORM_TYPE=Exadata
```

### ZDM Server Values

```properties
# ZDM Server Configuration
ZDM_HOME=/u01/app/zdmhome
ZDM_SERVER=tm-vm-odaa-oracle-jumpbox.s15cwnltpnyuher1lvdjg5qxtd.zx.internal.cloudapp.net
ZDM_IP=10.1.0.8
```

### Network Information

```properties
# Network Configuration
SOURCE_LISTENER_PORT=1521
TARGET_LISTENER_PORT=1521
TARGET_TCPS_PORT=2484
```

---

## Next Steps

1. ✅ Review this Discovery Summary
2. 🔲 Complete **required actions** listed above
3. 🔲 Fill out `Migration-Questionnaire-PRODDB.md` with OCI/Azure identifiers
4. 🔲 Run Step 2 to generate migration artifacts

---

*Generated by ZDM Migration Discovery Analysis - Step 1*
