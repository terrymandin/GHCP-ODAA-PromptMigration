# README: fix_supplemental_logging.sh

## Purpose
Enables `ALL COLUMNS` supplemental logging on the source Oracle 12.2 CDB (`ORADB1`, SID: `oradb`). This is required for ZDM `ONLINE_PHYSICAL` migration so that the Oracle Data Guard redo stream carries full before/after column values for every DML change. This resolves **Issue 2** (blocker) from `Issue-Resolution-Log-ORADB.md`.

---

## Target Server
**Source database server** — accessed remotely via SSH from the ZDM server.

| Field | Value |
|-------|-------|
| Executed on | ZDM server: `tm-vm-odaa-oracle-jumpbox` (10.1.0.8) |
| SSH target | Source: `azureuser@10.1.0.11` |
| Oracle action | Runs as `oracle` user via `sudo` |
| SSH key | `/home/zdmuser/iaas.pem` |

---

## Prerequisites

| Requirement | Detail |
|-------------|--------|
| ZDM server SSH connectivity to source | Must be able to `ssh -i /home/zdmuser/iaas.pem azureuser@10.1.0.11` |
| `azureuser` has `sudo` rights | Required to `sudo -u oracle` on source |
| Oracle CDB is OPEN | Database must be running in READ WRITE mode |
| Source disk space | Archive log destination (`/u01/app/oracle/fast_recovery_area`) should have adequate free space — enabling ALL supplemental logging increases redo/archive log volume. See Issue 4 in `Issue-Resolution-Log-ORADB.md`. |

---

## Environment Variables

| Variable | Default Value | Description |
|----------|---------------|-------------|
| `SOURCE_HOST` | `10.1.0.11` | IP address of the source Oracle database server |
| `SOURCE_SSH_USER` | `azureuser` | Admin SSH user on the source server |
| `SOURCE_SSH_KEY` | `/home/zdmuser/iaas.pem` | Path to SSH private key for the source server (on ZDM server) |
| `ORACLE_USER` | `oracle` | OS user that owns the Oracle installation |
| `ORACLE_HOME` | `/u01/app/oracle/product/12.2.0/dbhome_1` | Oracle Home directory on the source server |
| `ORACLE_SID` | `oradb` | Oracle SID of the source CDB |

---

## What It Does

1. **Step 1** — Queries `V$DATABASE` to show the current supplemental logging state (MIN, PK, UI, FK, ALL columns) before the fix.
2. **Step 2** — Executes `ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS` to enable full supplemental logging. Then `ALTER SYSTEM SWITCH LOGFILE` to ensure the change is reflected in new redo logs immediately.
3. **Step 3** — Re-queries `V$DATABASE` to confirm `supplemental_log_data_all = YES`.

All SQL is delivered over SSH via base64 encoding to avoid shell-quoting conflicts.

---

## How to Run

```bash
# On ZDM server as zdmuser:
cd /home/zdmuser
chmod +x fix_supplemental_logging.sh
./fix_supplemental_logging.sh
```

To override any default values:
```bash
SOURCE_HOST=10.1.0.11 ORACLE_SID=oradb ./fix_supplemental_logging.sh
```

---

## Expected Output

```
================================================================
 fix_supplemental_logging.sh — Enable ALL COLUMNS suplog
 Source: 10.1.0.11  SID: oradb
================================================================

---- Step 1: Current supplemental logging status ---------------
LOG_MODE   LOG_MIN LOG_PK LOG_UI LOG_FK LOG_ALL
---------- ------- ------ ------ ------ -------
ARCHIVELOG YES     NO     NO     YES    NO

---- Step 2: Enable ALL COLUMNS supplemental logging -----------
Database altered.
System altered.

---- Step 3: Verify supplemental logging -----------------------
LOG_MIN LOG_PK LOG_UI LOG_FK LOG_ALL
------- ------ ------ ------ -------
YES     YES    YES    YES    YES

================================================================
 Done.
 Expected result: log_all = YES
...
================================================================
```

---

## Performance Impact

Enabling `ALL COLUMNS` supplemental logging causes Oracle to write the values of all columns for every row changed by DML operations into the redo stream. For the ORADB source database (2.08 GB total data, no significant user tables observed in discovery), this overhead is minimal. However:

- **Monitor** archive log growth rate after enabling: `du -sh /u01/app/oracle/fast_recovery_area/`
- **Consider** redirecting archive logs to `/mnt` if root disk space becomes constrained (see Issue 4)

---

## Rollback / Undo

To remove ALL COLUMNS supplemental logging (restore to minimal-only state):

```sql
-- Connect as SYS on source (oradb)
ALTER DATABASE DROP SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER SYSTEM SWITCH LOGFILE;

-- Verify (log_all should return to NO)
SELECT supplemental_log_data_all AS log_all FROM v$database;
```

> **Note:** Do NOT disable supplemental logging once ZDM migration is in progress — this will break redo apply at the target.

---

## Related Files

- `Issue-Resolution-Log-ORADB.md` — Update **Issue 2** status to ✅ Resolved after confirming output
- `verify_fixes.sh` — Runs a quick re-check of all three blockers
- `Issue-Resolution-Log-ORADB.md` Issue 4 — Disk space guidance for archive log area
