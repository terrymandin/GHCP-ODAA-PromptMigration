# README: fix_01_source_archivelog_forcelogging_supplemental.sh

## Purpose
Enables ARCHIVELOG mode, Force Logging, and Supplemental Logging on the source Oracle database (`ORADB1`, SID: `oradb`) — three CRITICAL blockers for ZDM ONLINE_PHYSICAL migration.

## Target Server
**Source database server** (`10.1.0.11`) — script runs **on the ZDM server** (`10.1.0.8`) and connects to the source via SSH.

## Prerequisites
- Issues 01, 02, 03 in the Issue Resolution Log are open (Pending)
- SSH access from ZDM server to source confirmed (run `fix_10_verify_ssh_access.sh` first to validate, or confirm Step 0 discovery worked)
- `azureuser` has passwordless sudo to `oracle` on the source server
- Source database is running and reachable on TCP 1521
- **Maintenance window scheduled** — the ARCHIVELOG enable step requires a brief database restart (typically < 5 minutes for a ~1.9 GB DB)
- `fix_08_configure_archive_destination.sh` should be run after this script (or at least a destination with adequate free space reviewed before enabling ARCHIVELOG)

## Environment Variables

| Variable | Description | Default / Example |
|---|---|---|
| `SOURCE_HOST` | Source database server IP | `10.1.0.11` |
| `SOURCE_SSH_USER` | SSH admin user on source | `azureuser` |
| `SOURCE_SSH_KEY` | Path to SSH private key | `~/.ssh/odaa.pem` |
| `ORACLE_USER` | Oracle OS user on source | `oracle` |
| `SOURCE_ORACLE_HOME` | ORACLE_HOME on source | `/u01/app/oracle/product/12.2.0/dbhome_1` |
| `SOURCE_ORACLE_SID` | Oracle SID on source | `oradb` |

## What It Does
1. **Preflight**: Tests SSH connectivity to source.
2. **Step 1**: Checks current `LOG_MODE`, `FORCE_LOGGING`, and supplemental logging status.
3. **Step 2** _(if needed)_: `SHUTDOWN IMMEDIATE`, `STARTUP MOUNT`, `ALTER DATABASE ARCHIVELOG`, `ALTER DATABASE OPEN` — enables ARCHIVELOG mode with a brief restart.
4. **Step 3**: `ALTER DATABASE FORCE LOGGING` — ensures direct-path writes are captured in redo.
5. **Step 4**: `ALTER DATABASE ADD SUPPLEMENTAL LOG DATA` and `ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS`, followed by a `SWITCH LOGFILE`.
6. **Step 5**: Queries `V$DATABASE` and runs `ARCHIVE LOG LIST` to confirm all three settings are active.

SQL is transmitted via base64 encoding to avoid shell quoting conflicts.

## How to Run
```bash
# On ZDM server (10.1.0.8) as azureuser
cd Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts
chmod +x fix_01_source_archivelog_forcelogging_supplemental.sh
./fix_01_source_archivelog_forcelogging_supplemental.sh
```

Optionally override defaults with environment variables:
```bash
SOURCE_HOST=10.1.0.11 SOURCE_SSH_KEY=~/.ssh/odaa.pem \
  ./fix_01_source_archivelog_forcelogging_supplemental.sh
```

## Expected Output
```
[...] INFO  Step 5: Verification...
LOG_MODE       FORCE_LOGGING SUPPLEMENTAL_LOG_DATA_MIN SUPPLEMENTAL_LOG_DATA_ALL
-------------- ------------- ------------------------- -------------------------
ARCHIVELOG     YES           YES                      YES

Archive Mode  : Archive Mode
Automatic archival: Enabled
Archive destination: /u01/app/oracle/archive  (or configured path)

[...] INFO  ✅ All checks passed. Source database is ready for ZDM ONLINE_PHYSICAL migration.
```

## Rollback / Undo
```sql
-- Disable supplemental logging
ALTER DATABASE DROP SUPPLEMENTAL LOG DATA;

-- Disable Force Logging
ALTER DATABASE NO FORCE LOGGING;

-- Disable ARCHIVELOG (⚠️ requires restart — only do this if migration is abandoned)
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE NOARCHIVELOG;
ALTER DATABASE OPEN;
```

> ⚠️ Disabling ARCHIVELOG while Data Guard is active (post-ZDM start) will break replication. Only roll back if the migration has not yet started with ZDM.
