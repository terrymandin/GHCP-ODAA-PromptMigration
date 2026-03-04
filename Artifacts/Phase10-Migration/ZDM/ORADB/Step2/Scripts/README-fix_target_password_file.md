# README: fix_target_password_file.sh

## Purpose
Creates the Oracle password file (`orapworadb01`) on the ODAA target node (`tmodaauks-rqahk1`, 10.0.1.160) using `orapwd`, enabling ZDM to authenticate as SYS during the `ONLINE_PHYSICAL` migration. Resolves **Issue 2** from the Issue Resolution Log.

## Target Server
**ZDM server** — runs the script locally as `zdmuser`, then SSH-executes `orapwd` on the ODAA target as `oracle` user.
Run as **`zdmuser`** on the ZDM server.

## Prerequisites
1. Issue 8 must be resolved first — correct target Oracle Home path (`dbhome_1` or `dbhome_2`) must be known
2. SSH key `~/.ssh/odaa.pem` must grant access to `opc@10.0.1.160`
3. `opc` user must have `sudo` to `oracle` on the ODAA target
4. SYS password to set for the target database (agreed with DBA team, stored securely in vault)

## Environment Variables
All values are hardcoded from `zdm-env.md`. Key configuration:

| Variable | Description | Value |
|----------|-------------|-------|
| `TARGET_HOST` | ODAA target IP | `10.0.1.160` |
| `TARGET_SSH_USER` | SSH admin user for ODAA | `opc` |
| `TARGET_SSH_KEY` | SSH key for ODAA | `~/.ssh/odaa.pem` |
| `ORACLE_USER` | Oracle OS user | `oracle` |
| `TARGET_ORACLE_HOME_BASE` | Oracle Home base path | `/u02/app/oracle/product/19.0.0.0` |
| `TARGET_DB_UNIQUE_NAME` | Target DB unique name | `oradb01` |
| `TARGET_INSTANCE_NAME` | Target instance name | `oradb011` |

## What It Does
1. Prompts interactively for Oracle Home suffix (`1` or `2`)
2. Tests SSH connectivity to ODAA target: `opc@10.0.1.160` → `sudo -u oracle`
3. Checks if password file already exists (prompts before overwrite)
4. Prompts securely (non-echoed) for SYS password (twice for confirmation)
5. Uses **base64 encoding** to pass the password safely through SSH/sudo shell quoting layers
6. Runs `orapwd file=<path> password=<pw> entries=20 force=y` as `oracle` on the target
7. Verifies the file was created with `ls -la`

## How to Run
```bash
# 1. SSH to ZDM server and switch to zdmuser
ssh -i ~/.ssh/zdm.pem azureuser@10.1.0.8
sudo su - zdmuser

# 2. Run the script
cd ~/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts
bash fix_target_password_file.sh
# Interactive prompts:
#   > Enter Oracle Home suffix [1 or 2]:
#   > Enter the SYS password for the target database:
#   > Confirm SYS password:
```

## Expected Output
```
[HH:MM:SS] ℹ️  INFO  Using Oracle Home: /u02/app/oracle/product/19.0.0.0/dbhome_1
[HH:MM:SS] ✅ PASS  SSH connectivity to target confirmed — oracle user accessible.
[HH:MM:SS] ✅ PASS  Password file created successfully at /u02/app/oracle/product/19.0.0.0/dbhome_1/dbs/orapworadb01
[HH:MM:SS] ✅ PASS  Password file verified: -rw-r----- 1 oracle oinstall ... orapworadb01
[HH:MM:SS] ✅ PASS  Issue 2 RESOLVED: Password file created at ...
```

After running, record the Oracle Home path confirmed in `zdm-env.md`:
```
TARGET_REMOTE_ORACLE_HOME: /u02/app/oracle/product/19.0.0.0/dbhome_1
```

## Rollback / Undo
To remove the password file (revert to no auth file):
```bash
ssh -i ~/.ssh/odaa.pem opc@10.0.1.160 \
  "sudo -u oracle rm /u02/app/oracle/product/19.0.0.0/dbhome_1/dbs/orapworadb01"
```
Note: Removing the password file will prevent remote SYS connections. Only revert if needed.
