# README: fix_open_target_db.sh

## Purpose
Checks the open mode of the ODAA target database (`oradb011` on `tmodaauks-rqahk1`) and, if it is in MOUNT or shutdown state, offers to open it to `READ WRITE`. This resolves **Issue 3** from the Issue Resolution Log — the target database was found in MOUNT (not OPEN) state during Step 0 discovery, preventing `ZDM_VALIDATE_TGT` from succeeding.

## Target Server
**ZDM server** — runs locally as `zdmuser`, then SSH-executes SQL on the ODAA target as `oracle`.
Run as **`zdmuser`** on the ZDM server.

## Prerequisites
1. DBA approval to open the target database — script prompts before making any changes
2. SSH key `~/.ssh/odaa.pem` must grant access to `opc@10.0.1.160`
3. Oracle Home path confirmed (Issue 8) — script prompts for `dbhome_1` or `dbhome_2`
4. Password file must exist on the target (Issue 2 must be resolved first if `startup` is needed)

## Environment Variables
All values are hardcoded from `zdm-env.md`:

| Variable | Description | Value |
|----------|-------------|-------|
| `TARGET_HOST` | ODAA target IP | `10.0.1.160` |
| `TARGET_SSH_USER` | SSH admin user | `opc` |
| `TARGET_SSH_KEY` | SSH key | `~/.ssh/odaa.pem` |
| `ORACLE_USER` | Oracle OS user | `oracle` |
| `TARGET_ORACLE_HOME_BASE` | Oracle Home base | `/u02/app/oracle/product/19.0.0.0` |
| `TARGET_INSTANCE_NAME` | Target Oracle SID | `oradb011` |

## What It Does
1. Prompts for Oracle Home suffix (`1` or `2`)
2. Tests SSH connectivity to ODAA target
3. Runs `SELECT STATUS, OPEN_MODE FROM V$INSTANCE, V$DATABASE` using **base64 encoding** to safely pass SQL through SSH layers
4. Parses output to determine current state (OPEN / READ ONLY / MOUNTED / SHUTDOWN / UNKNOWN)
5. If database is already `READ WRITE` — exits immediately with success (no changes)
6. If not open — displays planned SQL and **prompts for explicit DBA approval** before proceeding
7. Executes `ALTER DATABASE OPEN` (or `STARTUP` for shutdown state) after approval
8. Verifies `SELECT OPEN_MODE FROM V$DATABASE` returns `READ WRITE`

## How to Run
```bash
# 1. SSH to ZDM server and switch to zdmuser
ssh -i ~/.ssh/zdm.pem azureuser@10.1.0.8
sudo su - zdmuser

# 2. Run the script
cd ~/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts
bash fix_open_target_db.sh
# Interactive prompts:
#   > Enter Oracle Home suffix [1 or 2]:
#   > Do you have DBA approval to open this database? [yes/no]:
```

## Expected Output (database previously in MOUNT state)
```
[HH:MM:SS] ✅ PASS  SSH connectivity to target confirmed.
[HH:MM:SS] ⚠️  WARN  Database oradb011 is in MOUNT state. Must be opened before ZDM can validate.
  Current database state: MOUNTED
  Action: ALTER DATABASE OPEN;
  Do you have DBA approval? [yes/no]: yes
[HH:MM:SS] ✅ PASS  Database oradb011 is now READ WRITE.
[HH:MM:SS] ✅ PASS  Issue 3 RESOLVED...
```

## Expected Output (database already open)
```
[HH:MM:SS] ✅ PASS  Database oradb011 is already in READ WRITE mode.
SUMMARY: No action required. Database already open READ WRITE.
```

## Rollback / Undo
If the database needs to be returned to MOUNT state (uncommon):
```bash
ssh -i ~/.ssh/odaa.pem opc@10.0.1.160 \
  "sudo -u oracle bash -c 'export ORACLE_HOME=/u02/app/oracle/product/19.0.0.0/dbhome_1; export ORACLE_SID=oradb011; export PATH=\${ORACLE_HOME}/bin:\${PATH}; sqlplus / as sysdba <<EOF
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
EXIT;
EOF'"
```
Consult the DBA before reverting — this will disconnect all sessions.
