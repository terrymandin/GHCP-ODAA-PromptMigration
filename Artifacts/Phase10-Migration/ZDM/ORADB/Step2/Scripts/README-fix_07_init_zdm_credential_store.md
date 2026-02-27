# README: fix_07_init_zdm_credential_store.sh

## Purpose
Initializes the ZDM credential store directory and guides setup of the Oracle Wallet (or response file) with source and target SYS database passwords required by `zdmcli migrate database`. The ZDM credential store (`/u01/app/zdmhome/zdm/cred`) does not currently exist.

## Target Server
**ZDM server** (`10.1.0.8`) — run locally as `zdmuser`.

## Prerequisites
- ZDM is installed and service is running (`zdmcli status` returns Running)
- You have the source SYS password for `ORADB` on `10.1.0.11`
- You have the target SYS password for the target CDB on `10.0.1.160`
- Fix 01 (ARCHIVELOG) has been completed — confirms source DB is accessible

## Environment Variables

| Variable | Description | Default / Example |
|---|---|---|
| `ZDM_HOME` | ZDM installation home | `/u01/app/zdmhome` |
| `SOURCE_HOST` | Source DB host | `10.1.0.11` |
| `SOURCE_ORACLE_SID` | Source Oracle SID | `oradb` |
| `TARGET_HOST` | Target DB host | `10.0.1.160` |
| `TARGET_ORACLE_SID` | Target CDB SID (confirm from OCI Console) | Prompted/set manually |

Passwords are **always prompted interactively** — they are never stored in environment variables, logs, or files.

## What It Does
1. **Prompts** interactively for ZDM wallet password, source SYS password, and target SYS password (none are echoed or logged).
2. **Step 1**: Verifies `zdmcli` is found and executable.
3. **Step 2**: Creates the credential store directory (`/u01/app/zdmhome/zdm/cred`) if it does not exist.
4. **Step 3**: Initializes an Oracle Wallet at that location using `orapki` (bundled with ZDM).
5. **Step 4**: Displays instructions for two supported credential methods:
   - **Method A** (recommended): Add `SOURCEDATABASEPASSWORD` / `TARGETDATABASEPASSWORD` directly in the ZDM response file (generated in Step 3).
   - **Method B**: Use `mkstore` to add credential aliases to the Oracle Wallet.
6. **Step 5**: Saves a `credential_notes.txt` (chmod 600) with connection details (no passwords) for reference.
7. **Step 6**: Verifies the ZDM service is running.

## How to Run
```bash
# On ZDM server (10.1.0.8) as zdmuser
su - zdmuser
chmod +x fix_07_init_zdm_credential_store.sh
./fix_07_init_zdm_credential_store.sh
# Enter passwords when prompted
```

## Expected Output
```
[...] INFO  Step 2: Creating credential store directory: /u01/app/zdmhome/zdm/cred
[...] INFO  Step 3: Initializing Oracle Wallet...
Oracle PKI Tool Release ...
Wallet created successfully.
[...] INFO  Credential notes saved to: /u01/app/zdmhome/zdm/cred/credential_notes.txt (chmod 600)
[...] INFO  ZDM service: RUNNING ✅
[...] INFO  ✅ Fix 07 complete.
```

## Rollback / Undo
To remove and reinitialize the credential store:
```bash
rm -rf /u01/app/zdmhome/zdm/cred
mkdir -p /u01/app/zdmhome/zdm/cred
# Re-run fix_07_init_zdm_credential_store.sh
```
