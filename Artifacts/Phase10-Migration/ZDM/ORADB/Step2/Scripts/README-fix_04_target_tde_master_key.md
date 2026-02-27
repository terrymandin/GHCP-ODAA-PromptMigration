# README: fix_04_target_tde_master_key.sh

## Purpose
Creates a TDE (Transparent Data Encryption) master key in the target ODAA CDB wallet, resolving the `OPEN_NO_MASTER_KEY` wallet status that would block ZDM from provisioning the migrated PDB.

## Target Server
**Target database server** (`10.0.1.160`, Node 1) — script runs **on the ZDM server** (`10.1.0.8`) and connects to the target via SSH.

## Prerequisites
- SSH access from ZDM server to target confirmed (verify `opc@10.0.1.160` is reachable with `~/.ssh/odaa.pem`)
- `opc` has passwordless sudo to `oracle` on the target (standard ODAA configuration)
- Target CDB wallet exists at the wallet location (already open in `OPEN_NO_MASTER_KEY` state per discovery)
- You have the TDE wallet password for the target CDB (set during ODAA provisioning, available in OCI Console)
- Target ORACLE_SID must be known — confirm from `/etc/oratab` on the target or from the OCI Console

## Environment Variables

| Variable | Description | Default / Example |
|---|---|---|
| `TARGET_HOST` | Target node 1 IP address | `10.0.1.160` |
| `TARGET_SSH_USER` | SSH admin user on target | `opc` |
| `TARGET_SSH_KEY` | Path to SSH private key | `~/.ssh/odaa.pem` |
| `ORACLE_USER` | Oracle OS user on target | `oracle` |
| `TARGET_ORACLE_HOME` | ORACLE_HOME on target | `/u02/app/oracle/product/19.0.0.0/dbhome_1` |
| `TARGET_ORACLE_SID` | CDB SID on target | Auto-detected from `/etc/oratab` if blank |
| `TDE_WALLET_PASSWORD` | TDE wallet password | Prompted interactively if not set |

## What It Does
1. **Prompts** for `TDE_WALLET_PASSWORD` if not provided as an environment variable (password is never logged).
2. **Preflight**: Tests SSH connectivity to target.
3. **Auto-detects** `ORACLE_SID` from `/etc/oratab` on the target if `TARGET_ORACLE_SID` is not set.
4. **Step 1**: Queries `V$ENCRYPTION_WALLET` to show current wallet status.
5. **Step 2**: Executes `ADMINISTER KEY MANAGEMENT SET KEY FORCE KEYSTORE IDENTIFIED BY "<password>" WITH BACKUP` — creates the TDE master key in the existing wallet.
6. **Step 3**: Re-queries `V$ENCRYPTION_WALLET` to confirm `STATUS = OPEN` (not `OPEN_NO_MASTER_KEY`).

SQL is transmitted via base64 encoding to avoid shell quoting conflicts.

## How to Run
```bash
# On ZDM server (10.1.0.8) as azureuser or zdmuser
cd Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts
chmod +x fix_04_target_tde_master_key.sh

# Interactive (prompts for password):
./fix_04_target_tde_master_key.sh

# Or pass password via environment variable (use with caution):
TDE_WALLET_PASSWORD='<wallet_password>' ./fix_04_target_tde_master_key.sh
```

## Expected Output
```
[...] INFO  Step 1: Checking current TDE wallet status...
WRL_PARAMETER                  STATUS              WALLET_TYPE
------------------------------ ------------------- --------------------
/opt/oracle/dcs/commonstore/..  OPEN_NO_MASTER_KEY  PASSWORD

[...] INFO  Step 2: Creating TDE master key...
keystore altered.

[...] INFO  Step 3: Verifying wallet status...
WRL_PARAMETER                  STATUS              WALLET_TYPE
------------------------------ ------------------- --------------------
/opt/oracle/dcs/commonstore/..  OPEN                PASSWORD

[...] INFO  ✅ TDE wallet is OPEN with a master key. Target CDB is ready for ZDM migration.
```

## Rollback / Undo
TDE master key creation cannot be simply reversed. The key is stored in the wallet with a backup (the `WITH BACKUP` clause creates a dated backup of the wallet).

- If the wallet password was entered incorrectly: re-run the script with the correct password.
- If the wallet is corrupted: restore from the backup file created by `WITH BACKUP` (located alongside the wallet, with a timestamp in the filename).
- Contact Oracle Support if wallet recovery is needed.
