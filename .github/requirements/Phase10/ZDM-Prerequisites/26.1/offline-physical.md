# ZDM Prerequisites — Offline Physical Migration

- ZDM Version: 26.1
- Migration Method: OFFLINE_PHYSICAL
- Source URL: https://docs.oracle.com/en/database/oracle/zero-downtime-migration/26.1/zdmug/preparing-for-database-migration.html
- Extracted: 2026-04-21
- Note: Oracle 26.x family shares a single doc set; content sourced from 26.1 publication.

---

## Layer 0 — Questionnaire (no commands needed)

Checks answered by asking the user; they directly set RSP params or `zdmcli` flags.

| Parameter | Allowed values | RSP / CLI mapping | Doc section |
|-----------|---------------|-------------------|-------------|
| `PLATFORM_TYPE` | `VMDB` (OCI VM/BM), `EXACS` (ExaDB-D or ExaDB-D on Exascale), `EXACC` (ExaDB-C@C or ExaDB-C@C on Exascale), `NON_CLOUD` (on-prem Exadata) | RSP: `PLATFORM_TYPE` | 4.7 Setting Physical Migration Parameters |
| `MIGRATION_METHOD` | `OFFLINE_PHYSICAL` (RMAN backup and restore; only method for SE2) | RSP: `MIGRATION_METHOD` | 4.7 Setting Physical Migration Parameters |
| `DATA_TRANSFER_MEDIUM` | `OSS` (OCI Object Storage), `ZDLRA`, `NFS`, `EXTBACKUP` | RSP: `DATA_TRANSFER_MEDIUM` | 4.7 Setting Physical Migration Parameters |
| Source storage type | `-sourcesid` (single instance) vs `-sourcedb` (RAC / Grid) | `zdmcli` flag | 4.3 Source Database Prerequisites |
| TDE wallet type | `AUTOLOGIN` (preferred) or `PASSWORD` | `zdmcli -tdekeystorepasswd` or `-tdekeystorewallet` | 4.5 Setting Up TDE Keystore |
| Use existing RMAN backup? | `TRUE` / `FALSE` | RSP: `ZDM_USE_EXISTING_BACKUP` | 4.8 Using an Existing RMAN Backup |
| Non-CDB to PDB conversion? | `TRUE` / `FALSE` | RSP: `NONCDBTOPDB_CONVERSION` | 4.14 Converting Non-CDB to CDB |
| PDB clone method (if PDB source) | `COLD`, `HOT` | RSP: `ZDM_PDB_CLONE_METHOD`; `DATA_TRANSFER_MEDIUM=DBLINK` | 4.20 Migration Using PDB Clone |
| TDE mandatory override (NON_CLOUD only) | `TRUE` / `FALSE` | RSP: `ZDM_TDE_MANDATORY` | 4.15 On-Premises to On-Premises Migration |

---

## Layer 1 — Infrastructure (no DB credentials)

Checks performable with SSH and OS commands only (no `sqlplus`).

| Check name | Verification command | Pass condition | Severity | Doc section |
|------------|---------------------|----------------|----------|-------------|
| ZDM service running | `$ZDM_HOME/bin/zdmcli query jobid 0 2>&1 \| head -5` | ZDM service responsive | BLOCKER | General |
| Hostnames differ between source and target | `hostname` on SOURCE and TARGET; compare | Hostnames are NOT identical | BLOCKER | 4 Preparing for a Physical Database Migration (Note) |
| SSH port 22 open: ZDM host → source | `nc -zv $SOURCE_HOST 22` from ZDM host | Connection succeeds | BLOCKER | 4.3 Source Database Prerequisites |
| SSH port 22 open: ZDM host → target | `nc -zv $TARGET_HOST 22` from ZDM host | Connection succeeds | BLOCKER | 4.4 Target Database Prerequisites |
| Port 1521 open: ZDM host → target (if needed for RMAN restore) | `nc -zv $TARGET_HOST 1521` | Connection succeeds | WARNING | 4.4 Target Database Prerequisites |
| `/tmp` exec permission on source | `ssh ... "mount \| grep ' /tmp '"` | Mounted without `noexec` | BLOCKER | 4.2 Preparing the Source and Target Databases |
| `/tmp` exec permission on target | `ssh ... "mount \| grep ' /tmp '"` | Mounted without `noexec` | BLOCKER | 4.2 Preparing the Source and Target Databases |
| SSH key file exists and is `600` | `ls -la ~/.ssh/<key_file>; stat -c '%a' ~/.ssh/<key_file>` | File present, permissions `600` | BLOCKER | S3-11 (SYSTEM-REQUIREMENTS) |
| Oracle UID matches on source and target | `id oracle` on source and target | UID values match | WARNING | 4.2 Preparing the Source and Target Databases |
| NTP / system time within 6 min of OCI | `ntpq -p` or `chronyc tracking` | Offset < 6 minutes | BLOCKER | 4.2 Preparing the Source and Target Databases |
| OS and DB version match source ↔ target | `uname -a`; `$ORACLE_HOME/OPatch/opatch lspatches` | Same OS family; same or higher patch on target | BLOCKER | 4.2 Preparing the Source and Target Databases |
| Grid Infrastructure present on target | `crsctl stat res -t 2>/dev/null \| head -5` | GI resources visible | BLOCKER | 4.4 Target Database Prerequisites |
| ASM disk group size adequate on target | `asmcmd lsdg` | Free space ≥ source DB size | WARNING | 4.4 Target Database Prerequisites |
| OCI Object Storage accessible from ZDM host (if `DATA_TRANSFER_MEDIUM=OSS`) | `curl -s -o /dev/null -w '%{http_code}' https://objectstorage.<region>.oraclecloud.com` | HTTP 200 or 401 (reachable) | BLOCKER | 4.6 Using Supported Data Transfer Media |
| NFS mount accessible from source AND target (if `DATA_TRANSFER_MEDIUM=NFS`) | `ls -la $BACKUP_PATH` on both source and target | Directory readable; `rwx` for oracle on source, at least `r` for oracle on target | BLOCKER | 4.6 Using Supported Data Transfer Media |
| NFS paths match source and target (single-mount scenario) | `echo $BACKUP_PATH` on source and target | Same path string | BLOCKER | 4.6 Using Supported Data Transfer Media |
| ZDLRA backup valid (if `DATA_TRANSFER_MEDIUM=ZDLRA`) | ZDLRA console / `rman target / catalog rman/<pw>@<zdlra_scan>` — list backups | Valid level 0 backup exists | BLOCKER | 4.6 Using Supported Data Transfer Media |
| All RAC instances up before backup (if ZDLRA) | `srvctl status database -d $SOURCE_ORACLE_SID` | All instances are `running` | BLOCKER | 4.6 Using Supported Data Transfer Media |
| Source database registered with SRVCTL (if Grid Infrastructure) | `srvctl status database -d $SOURCE_ORACLE_SID` | Database listed | WARNING | 4.3 Source Database Prerequisites |
| RAC: SNAPSHOT CONTROLFILE on shared storage (if RAC source) | `rman target / <<< "show snapshot controlfile name;"` | Path is on ASM (`+`) or shared ACFS | BLOCKER | 4.3 Source Database Prerequisites |
| RAC: SSH passwordless between nodes for oracle (if RAC target) | `ssh oracle@<node2> echo ok` from node1 | `ok` returned without passphrase | BLOCKER | 4.4 Target Database Prerequisites |
| No incoming transactions before backup phase | Manual confirmation or application quiesce check | Application/source writes stopped | BLOCKER | 4.3 Source Database Prerequisites — Offline migrations note |

---

## Layer 2 — Source DB prerequisites (requires DB connection)

Run via `sqlplus / as sysdba` over SSH using `sudo -u oracle`.

| Check name | SQL or command | Pass condition | Severity | Doc section |
|------------|---------------|----------------|----------|-------------|
| SPFILE in use | `SELECT value FROM v$parameter WHERE name='spfile';` | Non-null, non-empty path (Note: offline migration supports non-SPFILE sources, but SPFILE strongly recommended) | WARNING | 4.2 Preparing the Source and Target Databases |
| COMPATIBLE parameter value | `SELECT value FROM v$parameter WHERE name='compatible';` | Record value — must match target | BLOCKER | 4.2 Preparing the Source and Target Databases |
| DB_NAME | `SELECT name FROM v$database;` | Record value — must match target `DB_NAME` (ExaDB-D/C@C) or can differ (OCI) | BLOCKER | 4.4 Target Database Prerequisites |
| DB_UNIQUE_NAME | `SELECT db_unique_name FROM v$database;` | Record value — target must be unique | BLOCKER | 4.4 Target Database Prerequisites |
| Character set | `SELECT value FROM nls_database_parameters WHERE parameter='NLS_CHARACTERSET';` | Must match target | BLOCKER | 4.2 Preparing the Source and Target Databases |
| TDE wallet status (DB 12.2+) | `SELECT status, wallet_type FROM v$encryption_wallet;` | `STATUS=OPEN`, `WALLET_TYPE` is `AUTOLOGIN` or `PASSWORD` | BLOCKER | 4.3 Source Database Prerequisites / 4.5 TDE Keystore |
| TDE wallet open on all PDBs (if CDB, DB 12.2+) | `SELECT con_id, status, wallet_type FROM v$encryption_wallet;` | All PDBs show `STATUS=OPEN` | BLOCKER | 4.3 Source Database Prerequisites |
| TDE not required check (if `PLATFORM_TYPE=NON_CLOUD` and `ZDM_TDE_MANDATORY=FALSE`) | `SELECT status FROM v$encryption_wallet;` | If source has no TDE and `ZDM_TDE_MANDATORY=FALSE` set, target TDE is not enforced | WARNING | 4.15 On-Premises Migration |
| SQLNET encryption algorithm | `SELECT name, value FROM v$parameter WHERE name LIKE '%sqlnet%encrypt%';` | Record value — must match target | WARNING | 4.2 Preparing the Source and Target Databases |
| Time zone file version | `SELECT * FROM v$timezone_file;` | Record value — target must be same or higher | WARNING | 4.4 Target Database Prerequisites |
| RMAN CONTROLFILE AUTOBACKUP | `RMAN> show controlfile autobackup;` | `ON` or set to `ON` before migration | BLOCKER | 4.3 Source Database Prerequisites |
| RMAN configuration (baseline capture) | `RMAN> show all;` | Capture output for post-migration comparison | WARNING | 4.4 Target Database Prerequisites |
| Existing level 0 backup valid (if `ZDM_USE_EXISTING_BACKUP=TRUE`) | `RMAN> list backup tag='<tag>' summary;` | Backup exists with `incremental_level=0` | BLOCKER | 4.8 Using an Existing RMAN Backup |
| Standby control file backup (if using existing backup) | `RMAN> list backup of controlfile for standby;` | Backup exists at `$BACKUP_PATH/lower_case_dbname/standby_ctl_*` | BLOCKER | 4.8 Using an Existing RMAN Backup |
| DB_nK_CACHE_SIZE handling | `SELECT name, value FROM v$parameter WHERE name LIKE 'db%cache_size';` | Record non-default block size cache values for ZDM automation | WARNING | 4.3 Source Database Prerequisites |

---

## Layer 2 — Target DB prerequisites (requires DB connection)

| Check name | SQL or command | Pass condition | Severity | Doc section |
|------------|---------------|----------------|----------|-------------|
| Placeholder DB exists | `SELECT name FROM v$database;` | Returns a valid DB_NAME | BLOCKER | 4.4 Target Database Prerequisites |
| DB_NAME matches source (ExaDB-D/C@C) or is unique (OCI) | `SELECT name FROM v$database;` | Matches rule for platform type; same letter case as source | BLOCKER | 4.4 Target Database Prerequisites |
| DB_UNIQUE_NAME is unique | `SELECT db_unique_name FROM v$database;` | Does not equal source `DB_UNIQUE_NAME` | BLOCKER | 4.4 Target Database Prerequisites |
| SYS password matches source | `echo "SELECT 1 FROM dual;" \| sqlplus sys/<password>@$TARGET_SCAN as sysdba` | Login succeeds | BLOCKER | 4.4 Target Database Prerequisites |
| Automatic backups disabled | OCI console + `SELECT dest_name, status FROM v$archive_dest;` | No active cloud backup policy | BLOCKER | 4.4 Target Database Prerequisites |
| Patch level same as or higher than source | `$ORACLE_HOME/OPatch/opatch lspatches` | Target patch ≥ source patch | WARNING | 4.4 Target Database Prerequisites |
| Time zone file version same or higher | `SELECT * FROM v$timezone_file;` | Target TZ version ≥ source TZ version | WARNING | 4.4 Target Database Prerequisites |
| TDE wallet folder exists and open (DB 12.2+, cloud targets) | `SELECT status, wallet_type FROM v$encryption_wallet;` | `STATUS=OPEN`, `WALLET_TYPE` is `AUTOLOGIN` or `PASSWORD` | BLOCKER | 4.4 Target Database Prerequisites |
| TDE wallet open on all PDBs (if CDB) | `SELECT con_id, status, wallet_type FROM v$encryption_wallet;` | All PDBs show `STATUS=OPEN` | BLOCKER | 4.4 Target Database Prerequisites |
| COMPATIBLE matches source | `SELECT value FROM v$parameter WHERE name='compatible';` | Same value as source | BLOCKER | 4.2 Preparing the Source and Target Databases |
| Character set matches source | `SELECT value FROM nls_database_parameters WHERE parameter='NLS_CHARACTERSET';` | Same as source | BLOCKER | 4.2 Preparing the Source and Target Databases |
| SQLNET encryption algorithm matches source | `SELECT name, value FROM v$parameter WHERE name LIKE '%sqlnet%encrypt%';` | Same algorithm as source | WARNING | 4.2 Preparing the Source and Target Databases |

---

## Layer 2 — Additional checks for OFFLINE_PHYSICAL

| Check name | SQL or command | Pass condition | Severity | Doc section |
|------------|---------------|----------------|----------|-------------|
| No SQL*Net connectivity required between source and target (OSS path) | Confirm with user — no tnsping required for `DATA_TRANSFER_MEDIUM=OSS` offline | N/A (not needed) | WARNING | 4.6 Using Supported Data Transfer Media — OSS offline note |
| Source database Standard Edition 2 (SE2 check) | `SELECT edition FROM v$instance;` | `OFFLINE_PHYSICAL` is the **only** supported method for SE2 — confirm `MIGRATION_METHOD=OFFLINE_PHYSICAL` | BLOCKER | 4.7 Setting Physical Migration Parameters — MIGRATION_METHOD note |
| RMAN backup not running simultaneously | `ps -ef \| grep rman` on source | No overlapping RMAN job at migration start | WARNING | 4.3 Source Database Prerequisites |
| Archive logs retained (not deleted while needed) | `SELECT sequence#, deleted FROM v$archived_log ORDER BY 1 DESC FETCH FIRST 10 ROWS ONLY;` [constructed] | Recent archive logs not deleted before ZDM uses them | WARNING | 4.3 Source Database Prerequisites |
