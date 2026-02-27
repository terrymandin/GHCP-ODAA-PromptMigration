# README: fix_09_configure_rman.sh

## Purpose
Configures RMAN on the source Oracle database and takes a full pre-migration database backup (plus archive logs). This provides a recovery point before initiating ZDM migration and is required if using `OFFLINE_PHYSICAL` method.

## Target Server
**Source database server** (`10.1.0.11`) — script runs **on the ZDM server** (`10.1.0.8`) and connects via SSH.

## Prerequisites
- `fix_01_source_archivelog_forcelogging_supplemental.sh` completed — ARCHIVELOG mode must be enabled for a consistent backup
- `fix_08_configure_archive_destination.sh` completed — archive destination must have adequate space
- `azureuser` has passwordless sudo to `oracle` on source
- Sufficient free disk space on source for the backup (source DB is ~1.9 GB; backup with compression will be smaller, but allow at least 3–4 GB headroom at the backup destination)
- SSH timeout set for long-running RMAN operations (script uses `ConnectTimeout=300`)

## Environment Variables

| Variable | Description | Default / Example |
|---|---|---|
| `SOURCE_HOST` | Source DB host IP | `10.1.0.11` |
| `SOURCE_SSH_USER` | SSH admin user on source | `azureuser` |
| `SOURCE_SSH_KEY` | Path to SSH private key | `~/.ssh/odaa.pem` |
| `ORACLE_USER` | Oracle OS user | `oracle` |
| `SOURCE_ORACLE_HOME` | Oracle software home | `/u01/app/oracle/product/12.2.0/dbhome_1` |
| `SOURCE_ORACLE_SID` | Oracle SID | `oradb` |
| `RMAN_BACKUP_DIR` | RMAN backup destination path | `/u01/app/oracle/fast_recovery_area` |

## What It Does
1. **Preflight**: Tests SSH; shows disk space on source.
2. **Step 1**: Creates the RMAN backup/recovery area directory on source.
3. **Step 2**: Configures RMAN settings:
   - Retention: 7-day recovery window
   - Control file autobackup: ON
   - Default device: DISK
   - Backup optimization: ON
   - Compression: BASIC
4. **Step 3**: Takes a full compressed backup: `BACKUP AS COMPRESSED BACKUPSET DATABASE PLUS ARCHIVELOG`, then deletes obsolete backups.
5. **Step 4**: Runs `VALIDATE DATABASE` and `LIST BACKUP SUMMARY` to confirm backup integrity; shows disk usage.

## How to Run
```bash
# On ZDM server (10.1.0.8) as azureuser
chmod +x fix_09_configure_rman.sh
./fix_09_configure_rman.sh

# Custom backup destination:
RMAN_BACKUP_DIR=/u01/app/oracle/rman_backup ./fix_09_configure_rman.sh
```

## Expected Output
```
[...] INFO  Step 2: Configuring RMAN...
RMAN configuration parameters are successfully changed.
...
[...] INFO  Step 3: Taking full RMAN backup...
Starting backup at ...
...
Finished backup at ...
[...] INFO  Step 4: Verifying backup completeness...
List of Backups
===============
Key     TY LV S Device Type ...
------- -- -- - ----------- ...
1       B  F  A DISK        ...

[...] INFO  ✅ Fix 09 complete.
```

## Rollback / Undo
The RMAN configuration changes can be reset:
```bash
rman TARGET /
CONFIGURE RETENTION POLICY CLEAR;
CONFIGURE CONTROLFILE AUTOBACKUP CLEAR;
CONFIGURE DEFAULT DEVICE TYPE CLEAR;
CONFIGURE COMPRESSION ALGORITHM CLEAR;
```

Backup sets on disk can be removed:
```bash
rman TARGET /
DELETE ALL BACKUP;
```
