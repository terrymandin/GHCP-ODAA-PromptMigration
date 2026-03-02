# README: fix_pdb1_open.sh

## Purpose
Opens PDB1 on the source Oracle 12.2 CDB (`ORADB1`, SID: `oradb`) and saves its open state so it automatically reopens after database restarts. This resolves **Issue 1** (blocker) from `Issue-Resolution-Log-ORADB.md`.

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
| Oracle database ORADB is running | CDB must be OPEN; only PDB1 is MOUNTED |
| Script run as `zdmuser` | Or any user that has the SSH key at the configured path |

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

1. **Step 1** — Queries `V$PDBS` to show the current `open_mode` and `restricted` status of PDB1 before the fix.
2. **Step 2** — Executes `ALTER PLUGGABLE DATABASE PDB1 OPEN` to open the PDB in READ WRITE mode, then `ALTER PLUGGABLE DATABASE PDB1 SAVE STATE` to persist the open state across restarts.
3. **Step 3** — Queries `V$PDBS` again to confirm PDB1 is now `READ WRITE`.

All SQL is delivered over SSH via base64 encoding to avoid shell-quoting conflicts.

---

## How to Run

```bash
# On ZDM server as zdmuser:
cd /home/zdmuser
chmod +x fix_pdb1_open.sh
./fix_pdb1_open.sh
```

To override any default values:
```bash
SOURCE_HOST=10.1.0.11 ORACLE_SID=oradb ./fix_pdb1_open.sh
```

---

## Expected Output

```
================================================================
 fix_pdb1_open.sh — Open PDB1 on 10.1.0.11
================================================================

---- Step 1: Current PDB status --------------------------------
NAME       OPEN_MODE    RESTRICTED
---------- ------------ ----------
PDB1       MOUNTED      NO

---- Step 2: Open PDB1 and save state --------------------------
Pluggable database altered.
Pluggable database altered.

---- Step 3: Verify PDB1 status --------------------------------
NAME       OPEN_MODE    RESTRICTED
---------- ------------ ----------
PDB1       READ WRITE   NO

================================================================
 Done.
 Expected result: PDB1 | open_mode=READ WRITE | restricted=NO
================================================================
```

---

## Rollback / Undo

To close PDB1 back to MOUNTED state (e.g., if testing):

```sql
-- Connect as SYS on source (oradb)
ALTER PLUGGABLE DATABASE PDB1 CLOSE IMMEDIATE;
-- Optional: clear saved state
ALTER PLUGGABLE DATABASE PDB1 SAVE STATE;   -- saves MOUNTED state
```

Or via SSH from ZDM server:
```bash
SOURCE_HOST=10.1.0.11 SOURCE_SSH_USER=azureuser SOURCE_SSH_KEY=/home/zdmuser/iaas.pem
sql_block="ALTER PLUGGABLE DATABASE PDB1 CLOSE IMMEDIATE; EXIT;"
encoded=$(printf '%s\n' "${sql_block}" | base64 -w 0)
ssh -i "${SOURCE_SSH_KEY}" azureuser@10.1.0.11 \
  "sudo -u oracle bash -c 'export ORACLE_HOME=/u01/app/oracle/product/12.2.0/dbhome_1; export ORACLE_SID=oradb; export PATH=\${ORACLE_HOME}/bin:\${PATH}; echo \"${encoded}\" | base64 -d | sqlplus -S / as sysdba'"
```

---

## Related Files

- `Issue-Resolution-Log-ORADB.md` — Update **Issue 1** status to ✅ Resolved after confirming output
- `verify_fixes.sh` — Runs a quick re-check of all three blockers
