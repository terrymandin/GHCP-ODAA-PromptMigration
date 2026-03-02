# README: zdm_fix_source_db.sh

## Purpose
Opens `PDB1` on the source database (`READ WRITE`) and enables `ALL COLUMNS` supplemental logging — resolving the two critical blockers identified in `Discovery-Summary-ORADB.md` before ZDM online physical migration can proceed.

---

## Target Server
**ZDM Server** — `tm-vm-odaa-oracle-jumpbox` (`10.1.0.8`)
All commands execute **as `zdmuser`** on the ZDM server and reach the source database over SSH.

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| Run as user | `zdmuser` on the ZDM server |
| SSH key in place | `/home/zdmuser/.ssh/iaas.pem` (key to source) — confirmed present by Step 0 discovery |
| `azureuser` SSH access | `azureuser@10.1.0.11` must be accessible and sudoable to `oracle` |
| Source CDB running | Container database `oradb` must be open READ WRITE (CDB was confirmed open in discovery) |
| Step 1 complete | `Discovery-Summary-ORADB.md` reviewed and issues identified |

---

## Environment Variables

All values are hardcoded in the script from `zdm-env.md` and `Discovery-Summary-ORADB.md`. No exports required before running.

| Variable | Value | Description |
|----------|-------|-------------|
| `SOURCE_HOST` | `10.1.0.11` | IP of source Oracle database server |
| `SOURCE_SSH_USER` | `azureuser` | Admin SSH user on source server |
| `SOURCE_SSH_KEY` | `~/.ssh/iaas.pem` | SSH key for source (relative to `zdmuser`) |
| `ORACLE_USER` | `oracle` | OS user running the Oracle database (reached via sudo) |
| `ORACLE_HOME` | `/u01/app/oracle/product/12.2.0/dbhome_1` | Oracle home discovered in Step 0 |
| `ORACLE_SID` | `oradb` | Oracle SID of the source CDB |
| `PDB_NAME` | `PDB1` | Name of the pluggable database to open |

---

## What It Does

1. **User guard** — exits immediately if not running as `zdmuser`
2. **SSH connectivity check** — SSHes to source as `azureuser`, runs `sudo -u oracle whoami` to confirm oracle is reachable
3. **Pre-fix state check** — queries `v$pdbs` to show current PDB1 open mode
4. **Open PDB1** — runs `ALTER PLUGGABLE DATABASE PDB1 OPEN READ WRITE` then `SAVE STATE` (so it persists across restarts)
5. **Enable supplemental logging** — runs `ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS`
6. **Switch logfile** — runs `ALTER SYSTEM SWITCH LOGFILE` to activate supplemental logging in the next redo group
7. **Verify PDB1 state** — re-queries `v$pdbs` and confirms `open_mode = READ WRITE`
8. **Verify supplemental logging** — queries `v$database` and displays all supplemental log columns; `supp_all` should show `YES`
9. **FRA advisory check** — queries `v$recovery_file_dest` to show current FRA usage as a disk space warning

SQL statements are delivered via base64 encoding to prevent shell quoting conflicts when single-quoted SQL values are present.

---

## How to Run

```bash
# 1. Switch to zdmuser on the ZDM server
sudo su - zdmuser

# 2. Make executable (first run only)
chmod +x ~/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts/zdm_fix_source_db.sh

# 3. Run
~/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts/zdm_fix_source_db.sh
```

Total runtime: approximately 30–60 seconds.

---

## Expected Output

A successful run produces output like the following (abbreviated):

```
[2026-03-02 22:00:01] STEP 1: Verifying SSH connectivity...
  ✅ SSH connectivity OK — reached oracle via sudo
[2026-03-02 22:00:03] STEP 2: Checking current PDB1 open mode...
NAME       OPEN_MODE       RESTRICTED
---------- --------------- ----------
PDB1       MOUNTED

[2026-03-02 22:00:05] STEP 3: Opening PDB1 READ WRITE and saving state...
  ✅ ALTER PLUGGABLE DATABASE PDB1 OPEN READ WRITE → issued
  ✅ ALTER PLUGGABLE DATABASE PDB1 SAVE STATE → issued
[2026-03-02 22:00:07] STEP 4: Enabling ALL COLUMNS supplemental logging...
  ✅ ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS → issued
[2026-03-02 22:00:08] STEP 5: Switching logfile...
  ✅ ALTER SYSTEM SWITCH LOGFILE → issued
[2026-03-02 22:00:09] STEP 6: Verifying PDB1 open mode...
  ✅ PDB1 open_mode = READ WRITE ✅
[2026-03-02 22:00:10] STEP 7: Verifying supplemental logging status...
LOG_MODE   SUPP_MIN SUPP_PK  SUPP_UI  SUPP_FK  SUPP_ALL
---------- -------- -------- -------- -------- --------
ARCHIVELOG YES      YES      YES      YES      YES
```

**Key indicators of success:**
- Step 6: `PDB1 open_mode = READ WRITE ✅`
- Step 7: `SUPP_ALL = YES`
- No `ORA-` errors in the output

---

## Rollback / Undo

| Action | Command |
|--------|---------|
| Close PDB1 again | `ALTER PLUGGABLE DATABASE PDB1 CLOSE IMMEDIATE;` |
| Remove ALL COLUMNS supplemental logging | `ALTER DATABASE DROP SUPPLEMENTAL LOG DATA (ALL) COLUMNS;` |
| Remove PDB1 save state (revert auto-open) | `ALTER PLUGGABLE DATABASE PDB1 NO SAVE STATE;` |

> **Note:** Only roll back supplemental logging after the migration is complete or has been fully abandoned. Removing it mid-migration will cause Data Guard synchronisation to break.

---

## Resolves

| Issue | Resolution Log Reference |
|-------|--------------------------|
| Issue 1: PDB1 MOUNTED | `Issue-Resolution-Log-ORADB.md` — Issue 1 |
| Issue 2: ALL COLUMNS supplemental logging missing | `Issue-Resolution-Log-ORADB.md` — Issue 2 |
