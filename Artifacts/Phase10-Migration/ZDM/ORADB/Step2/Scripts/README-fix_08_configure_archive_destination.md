# README: fix_08_configure_archive_destination.sh

## Purpose
Configures the Oracle archive log destination on the source database to point to a path with adequate free space, preventing the source filesystem from filling during migration. The source server currently has only ~8.6 GB free on `/` and the default archive destination is under `$ORACLE_HOME/dbs/arch`.

## Target Server
**Source database server** (`10.1.0.11`) — script runs **on the ZDM server** (`10.1.0.8`) and connects via SSH.

## Prerequisites
- `fix_01_source_archivelog_forcelogging_supplemental.sh` completed first — ARCHIVELOG mode must be enabled before this step makes sense
- `azureuser` has passwordless sudo to `oracle` on source
- Sufficient free disk space exists at the chosen destination path on the source (recommend ≥ 10 GB)
- Disk usage on source reviewed: `df -h` on source to identify suitable mount points

## Environment Variables

| Variable | Description | Default / Example |
|---|---|---|
| `SOURCE_HOST` | Source DB host IP | `10.1.0.11` |
| `SOURCE_SSH_USER` | SSH admin user on source | `azureuser` |
| `SOURCE_SSH_KEY` | Path to SSH private key | `~/.ssh/odaa.pem` |
| `ORACLE_USER` | Oracle OS user | `oracle` |
| `SOURCE_ORACLE_HOME` | Oracle software home | `/u01/app/oracle/product/12.2.0/dbhome_1` |
| `SOURCE_ORACLE_SID` | Oracle SID | `oradb` |
| `ARCHIVE_DEST` | Archive log destination path on source | `/u01/app/oracle/archive` |

## What It Does
1. **Preflight**: Tests SSH connectivity; prints current disk usage.
2. **Step 1**: Prints disk space on source to help select a destination.
3. **Step 2**: Creates the archive destination directory on the source as `oracle:oinstall`.
4. **Step 3**: Sets `LOG_ARCHIVE_DEST_1='LOCATION=<path>'` using `ALTER SYSTEM ... SCOPE=BOTH` and switches the logfile to confirm archiving works.
5. **Step 4**: Verifies the parameter is set and disk space after the logfile switch.

SQL is transmitted via base64 encoding to avoid single-quote conflicts with `LOCATION=` values.

## How to Run
```bash
# On ZDM server (10.1.0.8) as azureuser
chmod +x fix_08_configure_archive_destination.sh

# Default destination (/u01/app/oracle/archive):
./fix_08_configure_archive_destination.sh

# Override destination:
ARCHIVE_DEST=/u01/app/oracle/archive ./fix_08_configure_archive_destination.sh
```

## Expected Output
```
[...] INFO  Step 3: Setting LOG_ARCHIVE_DEST_1 to '/u01/app/oracle/archive'...
System altered.
System altered.
System altered.

NAME                  TYPE        VALUE
--------------------- ----------- -------------------------------------------
log_archive_dest_1    string      LOCATION=/u01/app/oracle/archive

[...] INFO  ✅ Fix 08 complete.
Archive log destination: /u01/app/oracle/archive
```

## Post-Run Monitoring
During migration, archive logs will accumulate. Monitor with:
```bash
# On source as oracle
df -h /u01/app/oracle/archive
# In RMAN:
LIST ARCHIVELOG ALL;
DELETE ARCHIVELOG UNTIL TIME 'SYSDATE - 2';
```

## Rollback / Undo
To revert to the default (or previous) archive destination:
```sql
-- Connect as SYSDBA on source
ALTER SYSTEM SET LOG_ARCHIVE_DEST_1='' SCOPE=BOTH;
-- Oracle will use the default FRA or dbs/arch
```
