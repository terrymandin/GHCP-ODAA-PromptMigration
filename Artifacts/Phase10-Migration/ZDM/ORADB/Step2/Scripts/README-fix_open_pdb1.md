# README: fix_open_pdb1.sh

## Purpose
Opens PDB1 on the source Oracle 12.2 database (`ORADB1`) in `READ WRITE` mode and persists the state so it survives future instance restarts — resolving **Issue 1 (Blocker)** from the ORADB Discovery Summary.

---

## Target Server
**ZDM Server** — run as `zdmuser` on `tm-vm-odaa-oracle-jumpbox` (10.1.0.8).  
The script connects to the **source server** (`tm-oracle-iaas`, 10.1.0.11) via SSH and executes SQL as `oracle` using `sudo`.

---

## Prerequisites

| Requirement | Detail |
|-------------|--------|
| Run as | `zdmuser` on the ZDM server |
| SSH key | `~/.ssh/iaas.pem` must exist and have permissions `600` |
| Source reachable | Port 22 open from ZDM server (10.1.0.8) to source (10.1.0.11) |
| Source DB running | `oradb` instance must be `READ WRITE` at the CDB level |
| Prior step | Step 0 discovery completed; Step 1 Discovery Summary reviewed |

---

## Environment Variables

All variables have hard-coded defaults matching the discovered environment. Override by exporting before running if your environment differs.

| Variable | Description | Default / Example |
|----------|-------------|-------------------|
| `SOURCE_HOST` | IP or hostname of source DB server | `10.1.0.11` |
| `SOURCE_SSH_USER` | Admin SSH user on source server | `azureuser` |
| `SOURCE_SSH_KEY` | Path to SSH private key (as zdmuser) | `~/.ssh/iaas.pem` |
| `ORACLE_USER` | OS user owning the Oracle software | `oracle` |
| `ORACLE_SID` | Oracle SID on source | `oradb` |
| `ORACLE_HOME` | Oracle Home path on source | `/u01/app/oracle/product/12.2.0/dbhome_1` |
| `PDB_NAME` | Name of the PDB to open | `PDB1` |

---

## What It Does

1. **User guard** — Exits immediately if not running as `zdmuser`.
2. **SSH connectivity test** — Verifies the ZDM server can reach the source server over SSH.
3. **Check current PDB state** — Queries `V$PDBS` to show the current `OPEN_MODE` and `RESTRICTED` status of `PDB1`.
4. **Open PDB** — Runs `ALTER PLUGGABLE DATABASE PDB1 OPEN;` as `sysdba`.
5. **Save state** — Runs `ALTER PLUGGABLE DATABASE PDB1 SAVE STATE;` so PDB1 automatically opens after any future CDB restart.
6. **Verify** — Re-queries `V$PDBS` and confirms `OPEN_MODE = READ WRITE`. Exits with code `1` if verification fails.

> SQL is passed to the remote session via base64 encoding to prevent shell quoting conflicts with single-quoted SQL values.

---

## How to Run

```bash
# Switch to zdmuser on the ZDM server
sudo su - zdmuser

# Navigate to scripts directory
cd ~/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts

# Make executable and run
chmod +x fix_open_pdb1.sh
./fix_open_pdb1.sh
```

To override a variable:

```bash
ORACLE_SID=oradb ./fix_open_pdb1.sh
```

---

## Expected Output

```
============================================================
  fix_open_pdb1.sh — Issue 1: Open PDB1 on source
============================================================

[2026-03-02 22:00:00 UTC] Verifying SSH connectivity to 10.1.0.11 ...
SSH OK: connected as azureuser on tm-oracle-iaas

[2026-03-02 22:00:01 UTC] Checking current PDB state ...

NAME            OPEN_MODE    RESTRICTED
--------------- ------------ ----------
PDB1            MOUNTED

[2026-03-02 22:00:02 UTC] Opening PDB1 and saving state ...
Pluggable database altered.
Pluggable database altered.

[2026-03-02 22:00:05 UTC] Verifying PDB state after fix ...

NAME            OPEN_MODE    RESTRICTED
--------------- ------------ ----------
PDB1            READ WRITE   NO

✅ SUCCESS: PDB1 is now OPEN (READ WRITE)

Next step: Run fix_supplemental_logging.sh to resolve Issue 2.
[2026-03-02 22:00:05 UTC] fix_open_pdb1.sh completed.
```

---

## Rollback / Undo

To revert PDB1 to MOUNTED state (e.g., if needed for troubleshooting):

```sql
-- As sysdba on source (run via SSH or direct console):
ALTER PLUGGABLE DATABASE PDB1 CLOSE IMMEDIATE;
ALTER PLUGGABLE DATABASE PDB1 DISCARD STATE;
```

> **Warning:** Do not close PDB1 once the ZDM migration job has started. Closing the PDB during an active migration will cause the migration job to fail.

---

*Issue 1 of 3 critical blockers — ORADB Step 2 remediation*
