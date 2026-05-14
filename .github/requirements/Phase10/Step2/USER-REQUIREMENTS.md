# Step3 User Requirements — ZDM Installation Verification

## Objective

Verify that Zero Downtime Migration (ZDM) version 26.1 is installed and running on the jumpbox. If ZDM is not installed, create the `zdmuser` OS user and guide the user through the download and installation process. Ensure `ZDM_HOME` and the ZDM `bin` directory are configured in `zdmuser`'s `.bashrc`.

> **Note:** The ZDM Azure VM is created during Step 1 (VM Create + Remote-SSH Setup). By the time Step3 runs, the VM already exists and the Remote-SSH connection is established.

**Execution model**: Step3 runs entirely in the Remote-SSH VS Code session on the jumpbox, logged in as `zdmuser`. The `zdmuser` OS account, its home directory, the ZDM prerequisite packages, and the `/u01/app/zdm*` directories are all set up during Step 1 — this step should verify they exist before proceeding.

**`sudo` policy**: `zdmuser` does **not** have `sudo` access. Any command that requires root must be surfaced to the user to run from a local PowerShell terminal as `azureuser`. Never use `sudo su zdmuser` — the session already is `zdmuser`. Never use `sudo -u zdmuser <command>` — the session is already `zdmuser`.

---

## S3-01: Output Contract

Step3 writes one artifact using file tools after verification or installation completes:

- `Artifacts/Phase10-Migration/Step2/zdm-install-report.md`

The report must contain:

1. ZDM version detected, or `NOT INSTALLED` if absent.
2. Installation action taken: `SKIPPED` (already installed) or `INSTALLED` (new installation performed).
3. `ZDM_HOME` path confirmed or set.
4. `.bashrc` update status: `ALREADY SET` or `UPDATED`.
5. `zdmservice status` output snippet (Running: true/false).
6. Final status: `VERIFIED` or `ACTION REQUIRED`, with any remaining actions listed.

**Pre-populated bypass**: If `Artifacts/Phase10-Migration/Step2/zdm-install-report.md` already exists and shows status `VERIFIED`, display a confirmation summary and skip all steps.

---

## S3-02: Execution Context

1. Step3 runs in the Remote-SSH terminal on the ZDM jumpbox, logged in as `zdmuser`. The Remote-SSH connection is configured in Step 1 to connect as `zdmuser`.
2. `zdmuser` is created during Step 1. By the time Step 2 runs, the account exists and owns `/home/zdmuser`. Step A of S3-04 verifies this — if the account is missing, it must be created before continuing.
3. Commands that require `root` are run via `sudo`. Commands that the Remote-SSH session cannot run directly as `zdmuser` must be surfaced to the user as explicit instructions.
4. Do not use `sudo -u zdmuser` to impersonate `zdmuser` — the session IS `zdmuser`.

---

## S3-03: ZDM Version Check

Check whether ZDM 26.1 is already installed:

1. If `$ZDM_HOME` is set in the current shell, run:
   ```bash
   $ZDM_HOME/bin/zdmcli -build
   ```
   and extract the version string. Confirm it contains `26.1`.

2. If `$ZDM_HOME` is not set, probe common installation locations in order:
   - `/u01/app/zdmhome`
   - `/home/zdmuser/zdmhome`
   - `/home/zdmuser/zdm/home`

   For each location, test if `bin/zdmcli` exists:
   ```bash
   test -x /u01/app/zdmhome/bin/zdmcli && /u01/app/zdmhome/bin/zdmcli -build
   ```

3. If `zdmcli` is discoverable on the PATH, run `zdmcli -build` directly.

**Expected version string** (must contain `26.1`):
```
full version: "26.1.0"
```

4. If ZDM 26.1 is confirmed installed:
   - Record the `ZDM_HOME` path.
   - Proceed directly to S3-05 (`.bashrc` check).

5. If ZDM is absent or a different version is detected:
   - Report the discovered version (or `NOT FOUND`).
   - Proceed to S3-04 (installation guidance).

---

## S3-04: ZDM Installation Guidance

If ZDM 26.1 is not installed, guide the user through the following steps:

### Step A — Verify `zdmuser` OS User

> **Note:** `zdmuser` and the `zdm` group are created during Step 1. The prerequisite packages and `/u01/app/zdm*` directories are also prepared during Step 1. Verify they exist before proceeding:

```bash
id zdmuser
stat -c '%U %G' /home/zdmuser
stat -c '%U %G %n' /u01/app/zdmhome /u01/app/zdmbase /u01/app/zdm_download
```

Expected: `zdmuser` exists; `/home/zdmuser` owned by `zdmuser zdm`; all three `/u01/app/zdm*` dirs owned by `zdmuser zdm`.

If any directory is missing or not owned by `zdmuser`, surface the following command for the user to run **from a local PowerShell terminal as `azureuser`** — do not attempt to create them in this session:

```powershell
ssh -o BatchMode=yes -p 22 -i "<JUMPBOX_SSH_KEY>" azureuser@<JUMPBOX_HOST> "sudo mkdir -p /u01/app/zdmhome /u01/app/zdmbase /u01/app/zdm_download && sudo chown -R zdmuser:zdm /u01/app/zdmhome /u01/app/zdmbase /u01/app/zdm_download"
```

### Step B — Download

1. Instruct the user to navigate to the [Zero Downtime Migration Download](https://www.oracle.com/database/technologies/rac/zdm-downloads.html) page.
2. Display the following prompt to the user:

   > **Action Required:** Please copy the download token and `wget` command from the Oracle ZDM Downloads page and paste them into this chat. The download page provides a `wget` command with an authentication token that allows the file to be downloaded directly to the jumpbox.

3. Wait for the user to paste the `wget` command (and token if separate) before proceeding.
4. Execute the provided `wget` command on the jumpbox (running as the SSH user is acceptable for the download).

### Step C — Pre-Installation Package Check

Verify the prerequisite packages are installed. These should have been installed by Step 1; if any are missing, **do not attempt to install them from the `zdmuser` session**. Surface the install command for the user to run as `azureuser` from a local terminal.

Check:
```bash
for pkg in expect glibc-devel libnsl ncurses-compat-libs libaio unzip perl wget; do
    rpm -q "$pkg" > /dev/null 2>&1 && echo "$pkg: OK" || echo "$pkg: MISSING"
done
```

If any are `MISSING`, display:
```powershell
# Run this from a LOCAL PowerShell terminal as azureuser, not in the Remote-SSH session:
ssh -o BatchMode=yes -p 22 -i "<JUMPBOX_SSH_KEY>" azureuser@<JUMPBOX_HOST> "sudo dnf install -y expect glibc-devel libnsl ncurses-compat-libs libaio unzip perl wget"
```

### Step D — Verify Installation Directories

The `/u01/app/zdm*` directories should already exist and be owned by `zdmuser`. Verify:
```bash
stat -c '%U %G %n' /u01/app/zdmhome /u01/app/zdmbase /u01/app/zdm_download
```
Expected: each line shows `zdmuser zdm <path>`. If missing, ask the user to run the remediation command from Step A (above) before continuing.

### Step E — Unzip and Install as `zdmuser`

The installer must run as `zdmuser`. Since the Remote-SSH session already is `zdmuser`, run the installer directly — no `sudo` or `sudo -u zdmuser` prefix:

```bash
cd /u01/app/zdm_download
unzip zdm*.zip
./zdminstall.sh setup \
    oraclehome=/u01/app/zdmhome \
    oraclebase=/u01/app/zdmbase \
    ziploc=<path_to_zdm_home.zip>
```

> **Note:** Ignore the post-install message instructing you to run `orainstRoot.sh` and `root.sh`. These scripts are not required for ZDM.

### Step F — Start and Verify the ZDM Service

Start and verify the service. The session is already `zdmuser`, so run directly:

```bash
/u01/app/zdmhome/bin/zdmservice start
/u01/app/zdmhome/bin/zdmservice status
/u01/app/zdmhome/bin/zdmcli -build
```

Expected `zdmservice status` output includes `Running: true`. Expected `zdmcli -build` output includes `full version: "26.1.0"`.

**Reference**: [ZDM 26.1 Installation Guide](https://docs.oracle.com/en/database/oracle/zero-downtime-migration/26.1/zdmug/installing-zero-downtime-migration-software.html#GUID-A55FEDBA-236A-4006-91A5-6F28D100C5B2)

---

## S3-05: .bashrc Environment Setup

After `ZDM_HOME` is confirmed or set, ensure it is persisted in `zdmuser`'s `.bashrc` (`/home/zdmuser/.bashrc`). Since the current session is `zdmuser`, read and write `~/.bashrc` directly — no `sudo` required.

1. Check for existing entries:
   ```bash
   grep -n 'ZDM_HOME\|zdmhome' ~/.bashrc
   ```

2. If `ZDM_HOME` is already set to the correct path and `$ZDM_HOME/bin` is already on the PATH, mark as `ALREADY SET` and skip the update.

3. If missing or set to an incorrect path, append the following block to `~/.bashrc`:
   ```bash
   tee -a ~/.bashrc << 'BASHRC_EOF'

   # ZDM Environment
   export ZDM_HOME=/u01/app/zdmhome
   export PATH=$ZDM_HOME/bin:$PATH
   BASHRC_EOF
   ```
   Use the actual confirmed `ZDM_HOME` path, not a hardcoded default, if it differs.

4. Verify settings:
   ```bash
   source ~/.bashrc && which zdmcli && zdmcli -build
   ```

---

## S3-06: Success Criteria

Step3 is complete when all of the following are true:

1. `zdmcli -build` returns a version string containing `26.1`.
2. `zdmservice status` shows `Running: true`.
3. `ZDM_HOME` is set in `zdmuser`'s `/home/zdmuser/.bashrc` with `$ZDM_HOME/bin` on the PATH.
4. `Artifacts/Phase10-Migration/Step2/zdm-install-report.md` is written with final status `VERIFIED`.
