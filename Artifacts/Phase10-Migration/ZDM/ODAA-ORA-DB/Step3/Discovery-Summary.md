# Discovery Summary

## Generated

- **Date:** 2026-03-17
- **Project:** ODAA-ORA-DB
- **Source Files Analyzed:**
  - `Step2/Discovery/source/zdm_source_discovery_factvmhost_20260316-141303.txt` / `.json`
  - `Step2/Discovery/target/zdm_target_discovery_vmclusterpoc-ytlat1_20260316-141306.txt` / `.json`
  - `Step2/Discovery/server/zdm_server_discovery_zdmhost_20260316-141320.txt` / `.json`

---

## Executive Summary

| Component | Status | Key Findings |
|-----------|--------|--------------|
| Source Database | ⚠️ | Oracle 19c on Oracle Linux 7.9 — **sqlplus path mismatch** prevented SQL collection; ARCHIVELOG and supplemental logging status unknown; Data Guard destination detected |
| Target Environment | ⚠️ | Oracle 19c EXAdata VM Cluster on Oracle Linux 8.10 — Listener verified READY; **ORA-01034** on SQL (ORACLE_SID mismatch: oratab shows `CDBAKV_STANDBY`, running instance is `CDBAKV21`); OCI CLI not installed |
| ZDM Server | ❌ | **ZDM_HOME not detected** — `zdmcli`, `zdmservice`, and ZDM version cannot be verified; **Java not found**; **OCI CLI not installed**; **No .pem/.key files** in `~/.ssh/`; must be resolved before migration |
| Network | ✅ | SOURCE and TARGET both reachable from ZDM (SSH port 22 and Oracle port 1521 OPEN); avg RTT < 2 ms — excellent |

---

## Migration Method Recommendation

**Recommended:** `ONLINE_PHYSICAL` *(pending confirmation of ARCHIVELOG mode on source)*

**Justification:**
- Network connectivity from ZDM → SOURCE and ZDM → TARGET is confirmed healthy (RTT < 2 ms, zero packet loss)
- Target is Exadata VM Cluster — purpose-built for Data Guard physical standby workloads
- Oracle 19c on both ends — same major version avoids upgrade complexity
- NFS shares already mounted on both source and target (`/nfstest`, `/mount/saadb12feb2026/`) — suitable for backup staging
- **Condition:** Source must be in ARCHIVELOG mode. This must be verified and enabled in Step 4 if not already set (the sqlplus path issue prevented reading it from discovery)

> ⚠️ **If ARCHIVELOG cannot be enabled** (due to application or business constraints), fall back to `OFFLINE_PHYSICAL`.

---

## Source Database Details

### Database Identification

| Property | Value | Source |
|----------|-------|--------|
| Hostname (short) | `factvmhost` | Discovered |
| FQDN | `factvmhost.x4hxgv13rquehhrpcjkae2yqea.zx.internal.cloudapp.net` | Discovered |
| IP Address | `10.200.1.12` | Discovered |
| OS | Oracle Linux Server 7.9 | Discovered |
| Kernel | 5.4.17-2036.101.2.el7uek.x86_64 | Discovered |
| ORACLE_HOME | `/u02/app/oracle/product/19.0.0.0/dbhome_1` | Discovered |
| ORACLE_SID | `MCKESS` | Discovered via `/etc/oratab` |
| Database Name | `MCKESS` (inferred from SID) | Inferred — **confirm manually** |
| Oracle Version | 19c (path-inferred) | Path-inferred — **SQL failed** |
| SSH Admin User | `azureuser` | `zdm-env.md` |
| SSH Keys in `~/.ssh/` | Multiple keys present including `ssh-key-10.200.0.250.key`, `id_rsa` | Discovered |

> ⚠️ **Source sqlplus issue:** The discovery script found `ORACLE_HOME=/u02/app/oracle/product/19.0.0.0/dbhome_1` but `sqlplus` was not executable at that path. All SQL sections returned `No such file or directory`. This must be fixed in Step 4 before database-level discovery can be completed.

### Data Guard on Source

| Finding | Detail |
|---------|--------|
| Data Guard detected | `log_archive_dest_2` is set (from discovery warning) |
| DG parameter values | **Not collected** — SQL failed |

> ⚠️ If source is a primary database in a Data Guard configuration, the migration plan must account for the existing standby. ZDM can co-exist with an existing DG configuration; confirm with Oracle Support if needed.

### Storage on Source

| Mount | Size | Used | Avail | Notes |
|-------|------|------|-------|-------|
| `/` (rootvg-rootlv) | 117G | 98G | 19G | ⚠️ **84% full — low space** |
| `/mnt` (sda1) | 32G | 17G | 14G | Reasonable |
| `/nfstest1` (Azure Blob NFS) | 5.0 PB | 0 | 5.0 PB | Available for backup staging |
| `/nfstest` (Azure Files NFS) | 1.0 TB | 3.2G | 1021G | Available for staging |

> ⚠️ The root filesystem `/` is 84% full (19 GB free). Archive log generation during online migration may fill this. Ensure archive logs are directed to an NFS mount or the target ASM.

### Configuration Status

| Requirement | Current State | Required State | Status |
|-------------|---------------|----------------|--------|
| ARCHIVELOG Mode | **UNKNOWN — sqlplus failed** | YES | ⚠️ |
| Force Logging | **UNKNOWN — sqlplus failed** | YES (online) | ⚠️ |
| Supplemental Logging (MIN) | **UNKNOWN — sqlplus failed** | YES (online) | ⚠️ |
| TDE Status | **UNKNOWN — sqlplus failed** | Check | ⚠️ |
| Data Guard destination | SET (log_archive_dest_2 not empty) | Review | ⚠️ |
| sqlplus executable at ORACLE_HOME | NOT FOUND | Required | ❌ |
| Root filesystem space | 19 GB free (84% full) | > 50 GB recommended | ⚠️ |

---

## Target Environment Details

### Database Identification

| Property | Value | Source |
|----------|-------|--------|
| Hostname (short) | `vmclusterpoc-ytlat1` | Discovered |
| FQDN | `vmclusterpoc-ytlat1.ociexadatasubn.ocivmoraexa19c.oraclevcn.com` | Discovered |
| IP Address (listener) | `10.200.0.250` | Discovered |
| Additional IPs | `10.200.0.241`, `10.200.0.30`, `10.200.0.101`, `10.200.2.50` | Discovered |
| OS | Oracle Linux Server 8.10 | Discovered |
| Kernel | 5.15.0-308.179.6.16.el8uek.x86_64 | Discovered |
| Platform | Exadata VM Cluster (EXAdata volume groups, ACFS) | Inferred from disk layout |
| ORACLE_HOME | `/u02/app/oracle/product/19.0.0.0/dbhome_1` | Discovered |
| ORACLE_SID (oratab) | `CDBAKV_STANDBY` | Discovered via `/etc/oratab` |
| **Running instance SID** | `CDBAKV21` | From listener — **use this as TARGET_ORACLE_SID** |
| SSH Admin User | `opc` | `zdm-env.md` |

> ❌ **ORA-01034 Root Cause Confirmed:** `/etc/oratab` contains `CDBAKV_STANDBY` as the SID, but the running RAC instance is `CDBAKV21` (visible in listener services). This mismatch causes `ORA-01034: ORACLE not available` for all SQL executed against `CDBAKV_STANDBY`. **Fix:** Set `TARGET_ORACLE_SID=CDBAKV21` in `zdm-env.md` and re-run Step 2 target discovery.

### Listener / Services Discovered

The target listener (TCP 10.200.0.250:1521 and 10.200.0.241:1521, TCPS 10.200.0.241:2484) is **RUNNING** with the following relevant services:

| Service | Instance | Status |
|---------|----------|--------|
| `CDBAKV_STANDBY` | CDBAKV21 | READY |
| `CDBAKV2XDB` | CDBAKV21 | READY |
| `CDBAKV_CFG` | CDBAKV21 | READY |
| `TESTDB_PRI` | TESTDB1 | READY |
| `DB0225` | DB02251 | READY |
| `pdb1` | DB02251, TESTDB1 | READY |

> ✅ Multiple databases are running on the target cluster. The migration target is `CDBAKV21` (instance of the CDB `CDBAKV`). The pre-created destination PDB for this migration must be confirmed.

### Storage on Target

| Mount | Size | Used | Avail | Notes |
|-------|------|------|-------|-------|
| `/u01/app/19.0.0.0/grid` | 50G | 13G | 38G | Grid Infrastructure |
| `/u02` | 57G | 30G | 25G | Oracle homes |
| `/acfs01` (ASM ACFS) | 100G | 13G | 88G | ACFS volume |
| Azure Files NFS | 1.0 TB | 3.2G | 1021G | Shared with source — staging candidate |

> ⚠️ ASM disk group sizes and free space could **not** be collected (ORA-01034). Must be verified after SID fix.

### Configuration Status

| Requirement | Current State | Required State | Status |
|-------------|---------------|----------------|--------|
| Oracle version (target) | 19c | Same or higher than source | ✅ |
| Listener running | YES — TCP 1521, TCPS 2484 | YES | ✅ |
| Database SQL access | FAILED — ORA-01034 (SID mismatch) | Fix required | ❌ |
| OCI CLI installed | NOT INSTALLED (`oci` not in PATH) | Required for ZDM | ❌ |
| ASM disk group space | UNKNOWN (ORA-01034) | Must verify | ⚠️ |
| firewalld | Inactive | OK (NSG/VCN controls access) | ✅ |
| Grid Infrastructure | Not detected via common paths | Verify manually | ⚠️ |

---

## ZDM Server Details

| Property | Value |
|----------|-------|
| Hostname | `zdmhost` |
| FQDN | `zdmhost.x4hxgv13rquehhrpcjkae2yqea.zx.internal.cloudapp.net` |
| IP Address | `10.200.1.13` |
| OS | Red Hat Enterprise Linux 8.9 (Ootpa) |
| Current user | `zdmuser` ✅ |
| ZDM Home | **NOT DETECTED** |
| ZDM Version | **UNKNOWN** |
| Java | **NOT FOUND** |
| OCI CLI | **NOT INSTALLED** |
| `~/.ssh/id_rsa` | Present (600 permissions) ✅ |
| `.pem`/`.key` files | **NONE** in `~/.ssh/` |
| `~/.oci/config` | **NOT FOUND** |

### ZDM Version Status

| Check | Current State | Required State | Status |
|-------|---------------|----------------|--------|
| ZDM_HOME detected | NOT DETECTED | Must be set | ❌ |
| ZDM Version | UNDETERMINED | Latest stable | ⚠️ |
| zdmcli executable | UNKNOWN (ZDM_HOME missing) | Required | ❌ |
| zdmservice running | UNKNOWN | Required | ❌ |
| Java executable | NOT FOUND | Required | ❌ |
| OCI CLI installed | NOT INSTALLED | Required | ❌ |
| ~/.oci/config | NOT FOUND | Required | ❌ |

> **ZDM Version Guidance:**
> Oracle ZDM is updated regularly. Visit the [Oracle ZDM Release Notes](https://docs.oracle.com/en/database/oracle/zero-downtime-migration/index.html) to confirm the installed version is the latest stable release.
> - The ZDM version is **UNDETERMINED** — this is a ⚠️ **Required Action**: manually verify `zdmservice status` and confirm the installed release matches the latest available on [My Oracle Support](https://support.oracle.com) (search: "Zero Downtime Migration").
> - ZDM is likely installed but `ZDM_HOME` is not set in zdmuser's `.bash_profile`. Source the profile or set `ZDM_HOME` manually and re-run Step 2 server discovery.

### Network Connectivity (ZDM → Source and Target)

| Test | Result |
|------|--------|
| Ping SOURCE (10.200.1.12), 10 pkts | 0% packet loss, avg RTT 1.518 ms ✅ |
| SSH port 22 SOURCE | OPEN ✅ |
| Oracle port 1521 SOURCE | OPEN ✅ |
| Ping TARGET (10.200.0.250), 10 pkts | 0% packet loss, avg RTT 1.307 ms ✅ |
| SSH port 22 TARGET | OPEN ✅ |
| Oracle port 1521 TARGET | OPEN ✅ |

---

## Required Actions Before Migration

### ❌ Critical (Must Fix Before Proceeding)

1. **Fix SOURCE sqlplus path**
   - `sqlplus` not found at `/u02/app/oracle/product/19.0.0.0/dbhome_1/bin/sqlplus`
   - Verify the correct `ORACLE_HOME` on `factvmhost` with:
     ```bash
     ssh azureuser@10.200.1.12 "cat /etc/oratab ; ls /u01/app/oracle/product/*/dbhome_1/bin/sqlplus 2>/dev/null"
     ```
   - Update `SOURCE_REMOTE_ORACLE_HOME` in `zdm-env.md` if the path differs, then re-run Step 2 discovery

2. **Fix TARGET ORACLE_SID mismatch**
   - `/etc/oratab` shows `CDBAKV_STANDBY`; running RAC instance is `CDBAKV21`
   - Set in `zdm-env.md`:
     ```
     TARGET_ORACLE_SID: CDBAKV21
     ```
   - Re-run Step 2 target discovery to collect database configuration, TDE status, ASM disk groups

3. **Resolve ZDM_HOME on ZDM server**
   - `ZDM_HOME` is not set in `zdmuser`'s environment — locate the ZDM installation:
     ```bash
     ssh azureuser@10.200.1.13 "sudo su - zdmuser -c 'find /u01 /opt /home -name zdmcli -type f 2>/dev/null'"
     ```
   - Add to `/home/zdmuser/.bash_profile`:
     ```bash
     export ZDM_HOME=/path/to/zdmhome
     export PATH=$ZDM_HOME/bin:$PATH
     ```
   - Re-run Step 2 server discovery to verify `zdmservice status` and job list

4. **Install or locate Java on ZDM server**
   - ZDM bundles a JDK at `$ZDM_HOME/jdk` — fixing ZDM_HOME should resolve this
   - If ZDM is not installed, install it: download from [My Oracle Support](https://support.oracle.com) (search: "Zero Downtime Migration")

5. **Verify ARCHIVELOG mode on SOURCE**
   - Cannot be confirmed until sqlplus is fixed (Critical action #1 above)
   - After fixing: `SELECT log_mode FROM v$database;` — must return `ARCHIVELOG`
   - If `NOARCHIVELOG`: plan a maintenance window to enable archive logging:
     ```sql
     SHUTDOWN IMMEDIATE;
     STARTUP MOUNT;
     ALTER DATABASE ARCHIVELOG;
     ALTER DATABASE OPEN;
     ```

### ⚠️ Recommended (Fix Before Migration)

6. **Install OCI CLI on ZDM server**
   - Required for ZDM to interact with OCI Object Storage and DB Systems
   ```bash
   sudo su - zdmuser
   bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"
   # Then configure: oci setup config
   ```

7. **Configure OCI CLI (`~/.oci/config`) on ZDM server**
   - After install, run `oci setup config` as `zdmuser` and provide:
     - Tenancy OCID, User OCID, Region, API Key (from `zdm-env.md` placeholders)

8. **Copy source/target SSH keys to ZDM server**
   - `~/.ssh/` on `zdmhost` has no `.pem` or `.key` files for reaching SOURCE/TARGET with explicit key
   - The default `~/.ssh/id_rsa` is present — confirm it has been added to `authorized_keys` on `factvmhost` and `vmclusterpoc-ytlat1`
   - If not, copy the appropriate `.pem` key from `factvmhost`'s `~/.ssh/` (e.g. `ssh-key-vmclusterpoc-ytlat1.key`) to zdmuser's `~/.ssh/` with permissions `600`

9. **Verify ZDM version is latest stable release**
   - Once ZDM_HOME is located, check on [My Oracle Support](https://support.oracle.com) that the installed version is current
   - Apply latest ZDM patch bundle if required before running migration

10. **Verify source root filesystem space**
    - `/` on `factvmhost` is 84% full (19 GB free)
    - Ensure archive logs are directed to `/nfstest1` or `/nfstest`, not local disk
    - Verify database archive log destination: `SELECT destination FROM v$archive_dest WHERE status='VALID';`

11. **Verify Force Logging and Supplemental Logging on SOURCE**
    - After sqlplus path is fixed:
      ```sql
      SELECT force_logging FROM v$database;
      SELECT supplemental_log_data_min FROM v$database;
      ```
    - Enable if not set:
      ```sql
      ALTER DATABASE FORCE LOGGING;
      ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
      ```

12. **Confirm pre-created PDB on Target for migration**
    - The target CDB `CDBAKV` is running; confirm a destination PDB is pre-created for MCKESS migration
    - Check via: `SELECT con_id, name, open_mode FROM v$pdbs;` (after SID fix)

---

## Discovered Values Reference

*(For use in Step 4 fix scripts and Step 5 migration artifact generation)*

```
# SOURCE
SOURCE_HOST             = 10.200.1.12
SOURCE_HOSTNAME         = factvmhost
SOURCE_FQDN             = factvmhost.x4hxgv13rquehhrpcjkae2yqea.zx.internal.cloudapp.net
SOURCE_SSH_USER         = azureuser
SOURCE_ORACLE_HOME      = /u02/app/oracle/product/19.0.0.0/dbhome_1  ← VERIFY (sqlplus missing)
SOURCE_ORACLE_SID       = MCKESS
SOURCE_OS               = Oracle Linux 7.9
SOURCE_NFS_MOUNTS       = /nfstest1 (Azure Blob, 5 PB), /nfstest (Azure Files, 1 TB)
SOURCE_ROOT_FREE_GB     = 19 GB (84% full — LOW)
SOURCE_DATA_GUARD       = log_archive_dest_2 configured (DG destination present)

# TARGET
TARGET_HOST             = 10.200.0.250
TARGET_HOSTNAME         = vmclusterpoc-ytlat1
TARGET_FQDN             = vmclusterpoc-ytlat1.ociexadatasubn.ocivmoraexa19c.oraclevcn.com
TARGET_SSH_USER         = opc
TARGET_ORACLE_HOME      = /u02/app/oracle/product/19.0.0.0/dbhome_1
TARGET_ORACLE_SID       = CDBAKV21  ← USE THIS (not CDBAKV_STANDBY from oratab)
TARGET_OS               = Oracle Linux 8.10
TARGET_PLATFORM         = Exadata VM Cluster
TARGET_LISTENER_PORT    = 1521 (TCP), 2484 (TCPS)
TARGET_LISTENER_IP      = 10.200.0.250, 10.200.0.241
TARGET_ASM_SID          = +ASM1
TARGET_GRID_HOME        = Not detected via common paths — locate manually
TARGET_NFS_MOUNT        = /mount/saadb12feb2026/adbshare01 (Azure Files, 1 TB)

# ZDM SERVER
ZDM_HOST                = 10.200.1.13
ZDM_HOSTNAME            = zdmhost
ZDM_SSH_USER            = azureuser (admin) / zdmuser (ZDM operations)
ZDM_OS                  = RHEL 8.9
ZDM_HOME                = NOT DETECTED — locate and set in .bash_profile
ZDM_VERSION             = UNKNOWN — must verify after ZDM_HOME resolved
ZDM_JAVA                = NOT FOUND — likely at $ZDM_HOME/jdk after ZDM_HOME resolved
ZDM_OCI_CLI             = NOT INSTALLED
ZDM_SSH_DEFAULT_KEY     = ~/.ssh/id_rsa (present, 600)
ZDM_PEM_KEY_FILES       = NONE in ~/.ssh/

# NETWORK
ZDM → SOURCE RTT         = 1.518 ms avg (excellent)
ZDM → TARGET RTT         = 1.307 ms avg (excellent)
ZDM → SOURCE Port 22     = OPEN
ZDM → SOURCE Port 1521   = OPEN
ZDM → TARGET Port 22     = OPEN
ZDM → TARGET Port 1521   = OPEN
```
