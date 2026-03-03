# README: purge_source_archivelogs.sh

## Purpose
Purges obsolete archivelogs from the source database (`ORADB`, 10.1.0.11) using RMAN to reclaim disk space on the root filesystem, which is currently at 80% utilization.

## Target Server
**ZDM server** — `tm-vm-odaa-oracle-jumpbox` (10.1.0.8)  
**Run as:** `zdmuser`  
**Action Performed On:** Source database server `tm-oracle-iaas` (10.1.0.11) — via SSH + `sudo -u oracle`

## Prerequisites
- [ ] Run as `zdmuser` on ZDM server (`sudo su - zdmuser`)
- [ ] SSH key `~/.ssh/odaa.pem` (under zdmuser home) has permission `600`
- [ ] Source server `10.1.0.11` is reachable via SSH on port 22
- [ ] Source database (`oradb`) is **open** — RMAN requires the database to be mounted or open
- [ ] **Do NOT run while an active ZDM migration job is in progress** — archivelog deletion during replication can cause Data Guard sync failure

## Environment Variables
| Variable | Description | Value |
|----------|-------------|-------|
| `DATABASE_NAME` | Database identifier for log paths | `ORADB` |
| `SOURCE_HOST` | Source server IP | `10.1.0.11` |
| `SOURCE_SSH_USER` | Admin SSH user on source | `azureuser` |
| `SOURCE_SSH_KEY` | SSH private key path (under zdmuser home) | `~/.ssh/odaa.pem` |
| `ORACLE_USER` | Oracle software owner | `oracle` |
| `ORACLE_HOME` | Oracle Home on source | `/u01/app/oracle/product/12.2.0/dbhome_1` |
| `ORACLE_SID` | Oracle SID on source | `oradb` |
| `DISK_WARN_PCT` | Threshold for disk space warning | `80` |
| `DISK_TARGET_PCT` | Target disk usage percentage | `75` |

## What It Does
1. Verifies SSH connectivity to the source server
2. Checks current disk utilization on source `/` filesystem (baseline)
3. Queries archivelog mode and FRA status via SQL over SSH (base64-encoded)
4. Lists archivelogs eligible for deletion: backed up ≥ 1 time AND completed before SYSDATE-1
5. Runs RMAN commands:
   - `CROSSCHECK ARCHIVELOG ALL` — syncs RMAN catalog with actual files on disk
   - `DELETE NOPROMPT ARCHIVELOG ALL BACKED UP 1 TIMES COMPLETED BEFORE 'SYSDATE-1'` — deletes eligible logs
6. Re-checks disk utilization after purge and reports space freed
7. Provides additional guidance if disk is still above threshold

## How to Run
```bash
# Switch to zdmuser on ZDM server
sudo su - zdmuser

cd ~/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts
chmod +x purge_source_archivelogs.sh
./purge_source_archivelogs.sh
```

> **Note:** The script includes a 5-second countdown before execution — press **Ctrl+C** to cancel.

## Expected Output
```
==============================================================
  ZDM Step 2: Purge Source Archivelogs
  Database  : ORADB (oradb)
  Source    : azureuser@10.1.0.11
  ...
  ✅ PASS: SSH connectivity to source confirmed
  ℹ️  INFO: Disk before purge: /dev/sda1  30G   23G  5.8G  80% /
  ...
  ✅ PASS: RMAN purge completed without errors
  ✅ PASS: Freed approximately 5% disk space (80% → 75%)
  ✅ PASS: Source root disk is at 75% — within safe threshold (< 80%)
==============================================================
  Source disk before : 80%
  Source disk after  : 75%
  Status             : ✅ Disk within safe threshold
```

## Rollback / Undo
**Archivelog deletion is irreversible.** The script only deletes logs that have been:
1. Backed up at least once (via RMAN), AND
2. Completed more than 1 day ago

This means:
- Logs needed for active RMAN backups are NOT deleted
- Logs from the last 24 hours are NOT deleted  
- The source database can still function normally after purge

If you need to recover archivelogs that were deleted, you would need to restore them from a backup (they are "BACKED UP 1 TIMES" before deletion).

**Preventive note for migration:** 
After starting ZDM ONLINE_PHYSICAL migration, ZDM generates archivelogs continuously on the source. Monitor source disk space regularly:
```bash
ssh -i ~/.ssh/odaa.pem azureuser@10.1.0.11 "df -h / && sudo -u oracle bash -c 'export ORACLE_HOME=/u01/app/oracle/product/12.2.0/dbhome_1; export PATH=\$ORACLE_HOME/bin:\$PATH; export ORACLE_SID=oradb; rman target / <<< \"REPORT NEED BACKUP;\"'"
```
