# ZDM Prerequisites — Online Physical Migration

- ZDM Version: 26.1
- Migration Method: ONLINE_PHYSICAL
- Source URL: https://docs.oracle.com/en/database/oracle/zero-downtime-migration/26.1/zdmug/preparing-for-database-migration.html
- Extracted: 2026-04-21
- Note: Oracle 26.x family shares a single doc set; content sourced from 26.1 publication.

---

## Layer 0 — Questionnaire (no commands needed)

Checks answered by asking the user; they directly set RSP params or `zdmcli` flags.

| Parameter | Allowed values | RSP / CLI mapping | Doc section |
|-----------|---------------|-------------------|-------------|
| `PLATFORM_TYPE` | `VMDB` (OCI VM/BM), `EXACS` (ExaDB-D or ExaDB-D on Exascale), `EXACC` (ExaDB-C@C or ExaDB-C@C on Exascale), `NON_CLOUD` (on-prem Exadata) | RSP: `PLATFORM_TYPE` | 4.7 Setting Physical Migration Parameters |
| `MIGRATION_METHOD` | `ONLINE_PHYSICAL` (Data Guard online) | RSP: `MIGRATION_METHOD` | 4.7 Setting Physical Migration Parameters |
| `DATA_TRANSFER_MEDIUM` | `OSS` (OCI Object Storage), `ZDLRA`, `NFS`, `DIRECT` (RMAN restore from service / active duplicate), `EXTBACKUP` | RSP: `DATA_TRANSFER_MEDIUM` | 4.7 Setting Physical Migration Parameters |
| Source storage type | `-sourcesid` (single instance) vs `-sourcedb` (RAC / Grid) | `zdmcli` flag | 4.3 Source Database Prerequisites |
| TDE wallet type | `AUTOLOGIN` (preferred) or `PASSWORD` | `zdmcli -tdekeystorepasswd` or `-tdekeystorewallet` | 4.5 Setting Up TDE Keystore |
| Automatic application switchover required? | `YES` / `NO` | Application-side TNS config | 4.11 Preparing for Automatic Application Switchover |
| Data Guard Broker role switchover? | `TRUE` / `FALSE` | RSP: `ZDM_USE_DG_BROKER` | 4.12 Using Oracle Data Guard Broker Role Switchover |
| Use existing RMAN backup? | `TRUE` / `FALSE` | RSP: `ZDM_USE_EXISTING_BACKUP` | 4.8 Using an Existing RMAN Backup |
| Use existing standby for instantiation? | `TRUE` / `FALSE` | RSP: `ZDM_USE_EXISTING_STANDBY` | 4.10 Using an Existing Standby |
| Cloud-native DR strategy required? | `YES` / `NO` | RSP: `TGT_STBY_NODE` | 4.16 Creating Cloud-Native DR Strategy |
| Non-CDB to PDB conversion? | `TRUE` / `FALSE` | RSP: `NONCDBTOPDB_CONVERSION` | 4.14 Converting Non-CDB to CDB |

---

## Layer 1 — Infrastructure (no DB credentials)

Checks performable with SSH and OS commands only (no `sqlplus`).

| Check name | Verification command | Pass condition | Severity | Doc section |
|------------|---------------------|----------------|----------|-------------|
| ZDM service running | `$ZDM_HOME/bin/zdmcli query jobid 0 2>&1 \| head -5` or `systemctl status zdm` | ZDM service responsive / no hard error | BLOCKER | 4.1 Prerequisites for Online Physical Migration |
| Hostnames differ between source and target | `hostname` on SOURCE and TARGET; compare | Hostnames are NOT identical | BLOCKER | 4 Preparing for a Physical Database Migration (Note) |
| SSH port 22 open: ZDM host → source | `nc -zv $SOURCE_HOST 22` from ZDM host | Connection succeeds | BLOCKER | 4.3 Source Database Prerequisites |
| SSH port 22 open: ZDM host → target | `nc -zv $TARGET_HOST 22` from ZDM host | Connection succeeds | BLOCKER | 4.4 Target Database Prerequisites |
| SCAN listener port open: source → target | `tnsping $TARGET_SCAN_ADDR` from source host (`TARGET_SCAN_ADDR` must be the value explicitly captured from Step 3 target listener/network discovery — do not rely on ZDM auto-detection, which may return `null:null` if SCAN is not in DNS) | TNS OK | BLOCKER | 4.3 Source Database Prerequisites |
| SCAN listener port open: target → source | `tnsping $SOURCE_SCAN_ADDR` from target host | TNS OK | BLOCKER | 4.3 Source Database Prerequisites |
| Port 1521 open: ZDM host → target | `nc -zv $TARGET_HOST 1521` from ZDM host | Connection succeeds | BLOCKER | 4.4 Target Database Prerequisites |
| `/tmp` exec permission on source | `ssh ... "mount \| grep ' /tmp '"` | Mounted without `noexec` | BLOCKER | 4.2 Preparing the Source and Target Databases |
| `/tmp` exec permission on target | `ssh ... "mount \| grep ' /tmp '"` | Mounted without `noexec` | BLOCKER | 4.2 Preparing the Source and Target Databases |
| SSH key file exists and is `600` | `ls -la ~/.ssh/<key_file>; stat -c '%a' ~/.ssh/<key_file>` | File present, permissions `600` | BLOCKER | S3-11 (SYSTEM-REQUIREMENTS) |
| Oracle UID matches on source and target | `id oracle` on source; `id oracle` on target | UID values match | WARNING | 4.2 Preparing the Source and Target Databases |
| NTP / system time within 6 min of OCI | `ntpq -p` or `chronyc tracking` | Offset < 6 minutes | BLOCKER | 4.2 Preparing the Source and Target Databases |
| OS and DB version match source ↔ target | `uname -a` on source and target; `$ORACLE_HOME/OPatch/opatch lspatches` | Same OS family; same or higher patch on target | BLOCKER | 4.2 Preparing the Source and Target Databases |
| Grid Infrastructure present on target | `crsctl stat res -t 2>/dev/null \| head -5` | GI resources visible | BLOCKER | 4.4 Target Database Prerequisites |
| ASM disk group size adequate on target | `asmcmd lsdg` | Free space ≥ source DB size | WARNING | 4.4 Target Database Prerequisites |
| OCI Object Storage accessible from ZDM host (if `DATA_TRANSFER_MEDIUM=OSS`) | `curl -s -o /dev/null -w '%{http_code}' https://objectstorage.<region>.oraclecloud.com` | HTTP 200 or 401 (reachable) | BLOCKER | 4.6 Using Supported Data Transfer Media |
| NFS mount accessible from source AND target (if `DATA_TRANSFER_MEDIUM=NFS`) | `ls -la $BACKUP_PATH` on both source and target | Directory readable; `rwx` for oracle on source | BLOCKER | 4.6 Using Supported Data Transfer Media |
| Source database registered with SRVCTL (if Grid Infrastructure) | `srvctl status database -d $SOURCE_ORACLE_SID` | Database listed | WARNING | 4.3 Source Database Prerequisites |
| RAC: SNAPSHOT CONTROLFILE on shared storage (if RAC source) | `rman target / <<< "show snapshot controlfile name;"` | Path is on ASM (`+`) or shared ACFS | BLOCKER | 4.3 Source Database Prerequisites |
| RAC: SSH passwordless between nodes for oracle (if RAC target) | `ssh oracle@<node2> echo ok` from node1 | `ok` returned without passphrase | BLOCKER | 4.4 Target Database Prerequisites |
| Oracle-user sudo on source (ZDM `zdmauth` pattern) | `ssh <src-user>@<src-host> "sudo -u oracle id"` | Returns oracle UID (e.g., `uid=54321(oracle)`) without passphrase prompt or sudo error | BLOCKER | 4.3 Source Database Prerequisites / ZDM Installation Guide (sudoers setup) |
| ZDM host resolves target RAC node hostnames | `getent hosts <tgt-node1> [<tgt-node2> ...]` from ZDM host (if target is RAC) | All node hostnames resolve to an IP address | BLOCKER | 4.4 Target Database Prerequisites |

---

## Layer 2 — Source DB prerequisites (requires DB connection)

Run via `sqlplus / as sysdba` over SSH using `sudo -u oracle`.

| Check name | SQL or command | Pass condition | Severity | Doc section |
|------------|---------------|----------------|----------|-------------|
| ARCHIVELOG mode enabled | `SELECT log_mode FROM v$database;` | `ARCHIVELOG` | BLOCKER | 4.3 Source Database Prerequisites |
| SPFILE in use | `SELECT value FROM v$parameter WHERE name='spfile';` | Non-null, non-empty path | BLOCKER | 4.2 Preparing the Source and Target Databases |
| COMPATIBLE parameter value | `SELECT value FROM v$parameter WHERE name='compatible';` | Record value — must match target | BLOCKER | 4.2 Preparing the Source and Target Databases |
| DB_NAME | `SELECT name FROM v$database;` | Record value — must match target `DB_NAME` (ExaDB-D/C@C) or can differ (OCI) | BLOCKER | 4.4 Target Database Prerequisites |
| DB_UNIQUE_NAME | `SELECT db_unique_name FROM v$database;` | Record value — target must be unique | BLOCKER | 4.4 Target Database Prerequisites |
| Character set | `SELECT value FROM nls_database_parameters WHERE parameter='NLS_CHARACTERSET';` | Must match target | BLOCKER | 4.2 Preparing the Source and Target Databases |
| TDE wallet status (DB 12.2+) | `SELECT status, wallet_type FROM v$encryption_wallet;` | `STATUS=OPEN`, `WALLET_TYPE` is `AUTOLOGIN` or `PASSWORD` | BLOCKER | 4.3 Source Database Prerequisites / 4.5 TDE Keystore |
| TDE wallet open on all PDBs (if CDB, DB 12.2+) | `SELECT con_id, status, wallet_type FROM v$encryption_wallet;` | All PDBs show `STATUS=OPEN` | BLOCKER | 4.3 Source Database Prerequisites |
| SQLNET encryption algorithm | `SELECT name, value FROM v$parameter WHERE name LIKE '%sqlnet%encrypt%';` | Record value — must match target | WARNING | 4.2 Preparing the Source and Target Databases |
| Time zone file version | `SELECT * FROM v$timezone_file;` | Record value — target must be same or higher | WARNING | 4.4 Target Database Prerequisites |
| RMAN CONTROLFILE AUTOBACKUP | `RMAN> show controlfile autobackup;` | `ON` or set to `ON` before migration | BLOCKER | 4.3 Source Database Prerequisites |
| RMAN configuration (baseline capture) | `RMAN> show all;` | Capture output for post-migration comparison | WARNING | 4.4 Target Database Prerequisites |
| Source is non-standard edition (SE2 check) | `SELECT edition FROM v$instance;` | `ENTERPRISE` for ONLINE_PHYSICAL (SE2 requires OFFLINE_PHYSICAL) | BLOCKER | 4.7 Setting Physical Migration Parameters — MIGRATION_METHOD note |

---

## Layer 2 — Target DB prerequisites (requires DB connection)

| Check name | SQL or command | Pass condition | Severity | Doc section |
|------------|---------------|----------------|----------|-------------|
| Placeholder DB exists | `SELECT name FROM v$database;` | Returns a valid DB_NAME (target provisioned) | BLOCKER | 4.4 Target Database Prerequisites |
| DB_NAME matches source (ExaDB-D/C@C) or is unique (OCI) | `SELECT name FROM v$database;` | Matches rule for platform type; same letter case as source | BLOCKER | 4.4 Target Database Prerequisites |
| DB_UNIQUE_NAME is unique | `SELECT db_unique_name FROM v$database;` | Does not equal source `DB_UNIQUE_NAME` | BLOCKER | 4.4 Target Database Prerequisites |
| SYS password matches source | `zdmcli` will test implicitly; pre-check: `echo "SELECT 1 FROM dual;" \| sqlplus sys/<password>@$TARGET_SCAN as sysdba` | Login succeeds | BLOCKER | 4.4 Target Database Prerequisites |
| Automatic backups disabled | `SELECT dest_id, status FROM v$archive_dest WHERE dest_id=1;` + OCI console check | No cloud backup policy active | BLOCKER | 4.4 Target Database Prerequisites |
| Patch level same as or higher than source | `$ORACLE_HOME/OPatch/opatch lspatches` | Target patch ≥ source patch | WARNING | 4.4 Target Database Prerequisites |
| Time zone file version same or higher | `SELECT * FROM v$timezone_file;` | Target TZ version ≥ source TZ version | WARNING | 4.4 Target Database Prerequisites |
| TDE wallet folder exists and open | `SELECT status, wallet_type FROM v$encryption_wallet;` | `STATUS=OPEN`, `WALLET_TYPE` is `AUTOLOGIN` or `PASSWORD` | BLOCKER | 4.4 Target Database Prerequisites / 4.5 TDE Keystore |
| TDE wallet open on all PDBs (if CDB) | `SELECT con_id, status, wallet_type FROM v$encryption_wallet;` | All PDBs show `STATUS=OPEN` | BLOCKER | 4.4 Target Database Prerequisites |
| COMPATIBLE matches source | `SELECT value FROM v$parameter WHERE name='compatible';` | Same value as source | BLOCKER | 4.2 Preparing the Source and Target Databases |
| Character set matches source | `SELECT value FROM nls_database_parameters WHERE parameter='NLS_CHARACTERSET';` | Same as source | BLOCKER | 4.2 Preparing the Source and Target Databases |
| SQLNET encryption algorithm matches source | `SELECT name, value FROM v$parameter WHERE name LIKE '%sqlnet%encrypt%';` | Same algorithm as source | WARNING | 4.2 Preparing the Source and Target Databases |
| Datapatch compatibility pre-flight | `sudo -u oracle $ORACLE_HOME/OPatch/datapatch -prereqs 2>&1 \| head -30` on all target nodes | Exits without `Unsupported named object type` error at `sqlpatch.pm`; no missing prerequisite patches reported | WARNING | MOS 1609718.1 |

---

## Layer 2 — Additional checks for ONLINE_PHYSICAL

| Check name | SQL or command | Pass condition | Severity | Doc section |
|------------|---------------|----------------|----------|-------------|
| Data Guard prerequisites: SQL*Net two-way connectivity | `tnsping $SOURCE_DB_SERVICE` from target; `tnsping $TARGET_DB_SERVICE` from source | Both TNS pings succeed | BLOCKER | 4.1 Prerequisites for Online Physical Migration |
| SSH tunnel configured if SCAN not reachable | Manual check or `nc -zv $TARGET_SCAN $SCAN_PORT` from source | SCAN reachable OR SSH tunnel set up + `TGT_SSH_TUNNEL_PORT` in RSP | BLOCKER | 4.1 Prerequisites for Online Physical Migration |
| Broker not blocking (if existing non-broker standby) | `SELECT database_role FROM v$database;` + DGMGRL check | No unmanaged standby when `ZDM_USE_DG_BROKER=TRUE` | WARNING | 4.12 Using Oracle Data Guard Broker Role Switchover |
| RMAN backup not running simultaneously | Check OS processes: `ps -ef \| grep rman` | No overlapping RMAN job at migration start | WARNING | 4.3 Source Database Prerequisites |
| Archive logs retained (not deleted while needed) | `SELECT sequence#, deleted FROM v$archived_log ORDER BY 1 DESC LIMIT 10;` [constructed] | Recent archive logs not deleted | WARNING | 4.3 Source Database Prerequisites |
