# Step3 User Requirements — ZDM Installation Verification

## Objective

Verify that Zero Downtime Migration (ZDM) version 26.1 is installed and running on the jumpbox. If ZDM is not installed, create the `zdmuser` OS user and guide the user through the download and installation process. Ensure `ZDM_HOME` and the ZDM `bin` directory are configured in `zdmuser`'s `.bashrc`.

> **Note:** The ZDM Azure VM is created during Step 1 (VM Create + Remote-SSH Setup). By the time Step3 runs, the VM already exists and the Remote-SSH connection is established.

**Execution model**: Step3 runs entirely in the Remote-SSH VS Code session on the jumpbox, logged in as the SSH user (typically `azureuser` on Azure VMs). The `zdmuser` OS account does not exist yet at the start — it is created as part of the installation. All `zdmuser`-scoped commands run via `sudo -u zdmuser`. Step3 must not run any commands locally.

---

## S3-01: Output Contract

Step3 writes one artifact using file tools after verification or installation completes:

- `Artifacts/Phase10-Migration/Step5/zdm-install-report.md`

The report must contain:

1. ZDM version detected, or `NOT INSTALLED` if absent.
2. Installation action taken: `SKIPPED` (already installed) or `INSTALLED` (new installation performed).
3. `ZDM_HOME` path confirmed or set.
4. `.bashrc` update status: `ALREADY SET` or `UPDATED`.
5. `zdmservice status` output snippet (Running: true/false).
6. Final status: `VERIFIED` or `ACTION REQUIRED`, with any remaining actions listed.

**Pre-populated bypass**: If `Artifacts/Phase10-Migration/Step5/zdm-install-report.md` already exists and shows status `VERIFIED`, display a confirmation summary and skip all steps.

---

## S3-02: Execution Context

1. Step3 runs in the Remote-SSH terminal on the ZDM jumpbox, logged in as the SSH user (e.g., `azureuser`). This user typically has `sudo` access on Azure VMs.
2. `zdmuser` does not exist at the start of Step3. It is created during the installation process (see S3-04 Step A).
3. Commands that must run as `zdmuser` use `sudo -u zdmuser <command>` or `sudo -u zdmuser bash -c '<command>'`.
4. Commands that require `root` and cannot be done via `sudo` must be surfaced to the user as explicit instructions. Provide the exact command and wait for the user to confirm completion before proceeding.
5. Do not assume `zdmuser` can log in interactively via SSH — use `sudo -u zdmuser` from the SSH user's session.

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

### Step A — Create `zdmuser` OS User

Create the `zdm` group and `zdmuser` account if they do not already exist. This step requires `sudo`:

```bash
getent group zdm  > /dev/null 2>&1 || sudo groupadd zdm
getent passwd zdmuser > /dev/null 2>&1 || sudo useradd -g zdm zdmuser
```

If `sudo` is unavailable, surface the commands to the user and ask them to run as `root`.

### Step B — Download

1. Instruct the user to navigate to the [Zero Downtime Migration Download](https://www.oracle.com/database/technologies/rac/zdm-downloads.html) page.
2. Display the following prompt to the user:

   > **Action Required:** Please copy the download token and `wget` command from the Oracle ZDM Downloads page and paste them into this chat. The download page provides a `wget` command with an authentication token that allows the file to be downloaded directly to the jumpbox.

3. Wait for the user to paste the `wget` command (and token if separate) before proceeding.
4. Execute the provided `wget` command on the jumpbox (running as the SSH user is acceptable for the download).

### Step C — Pre-Installation Package Check

Before running the installer, check for required packages and report their status. Install any missing packages using `sudo` (the SSH user typically has `sudo` on Azure VMs).

For **Oracle Linux 8 / RHEL 8**:
```bash
sudo yum install -y expect glibc-devel libnsl ncurses-compat-libs libaio unzip perl
```

For **Oracle Linux 9 / RHEL 9**:
```bash
sudo yum install -y expect glibc-devel libnsl ncurses-compat-libs libaio unzip perl wget
```

If `sudo` is not available, surface the command to the user and ask them to run it as `root` before continuing.

### Step D — Create Installation Directories and Set Ownership

Create the ZDM home and base directories and assign them to `zdmuser`:
```bash
sudo mkdir -p /u01/app/zdmhome
sudo mkdir -p /u01/app/zdmbase
sudo chown -R zdmuser:zdm /u01/app/zdmhome /u01/app/zdmbase
```

### Step E — Unzip and Install as `zdmuser`

The installer must run as `zdmuser`. Use `sudo -u zdmuser` to execute it:

```bash
cd <zdm_download_directory>
unzip zdm*.zip
sudo -u zdmuser ./zdminstall.sh setup \
    oraclehome=/u01/app/zdmhome \
    oraclebase=/u01/app/zdmbase \
    ziploc=<path_to_zdm_home.zip>
```

> **Note:** Ignore the post-install message instructing you to run `orainstRoot.sh` and `root.sh`. These scripts are not required for ZDM.

### Step F — Start and Verify the ZDM Service

Start and verify the service as `zdmuser` using `sudo -u zdmuser`:

```bash
sudo -u zdmuser /u01/app/zdmhome/bin/zdmservice start
sudo -u zdmuser /u01/app/zdmhome/bin/zdmservice status
sudo -u zdmuser /u01/app/zdmhome/bin/zdmcli -build
```

Expected `zdmservice status` output includes `Running: true`. Expected `zdmcli -build` output includes `full version: "26.1.0"`.

**Reference**: [ZDM 26.1 Installation Guide](https://docs.oracle.com/en/database/oracle/zero-downtime-migration/26.1/zdmug/installing-zero-downtime-migration-software.html#GUID-A55FEDBA-236A-4006-91A5-6F28D100C5B2)

---

## S3-05: .bashrc Environment Setup

After `ZDM_HOME` is confirmed or set, ensure it is persisted in `zdmuser`'s `.bashrc` (`/home/zdmuser/.bashrc`). Since the current session is the SSH user, use `sudo` to read and write this file.

1. Check for existing entries:
   ```bash
   sudo grep -n 'ZDM_HOME\|zdmhome' /home/zdmuser/.bashrc
   ```

2. If `ZDM_HOME` is already set to the correct path and `$ZDM_HOME/bin` is already on the PATH, mark as `ALREADY SET` and skip the update.

3. If missing or set to an incorrect path, append the following block to `/home/zdmuser/.bashrc`:
   ```bash
   sudo tee -a /home/zdmuser/.bashrc << 'BASHRC_EOF'

   # ZDM Environment
   export ZDM_HOME=/u01/app/zdmhome
   export PATH=$ZDM_HOME/bin:$PATH
   BASHRC_EOF
   ```
   Use the actual confirmed `ZDM_HOME` path, not a hardcoded default, if it differs.

4. Verify settings as `zdmuser`:
   ```bash
   sudo -u zdmuser bash -c 'source ~/.bashrc && which zdmcli && zdmcli -build'
   ```

---

## S3-06: Success Criteria

Step3 is complete when all of the following are true:

1. `zdmcli -build` returns a version string containing `26.1`.
2. `zdmservice status` shows `Running: true`.
3. `ZDM_HOME` is set in `zdmuser`'s `/home/zdmuser/.bashrc` with `$ZDM_HOME/bin` on the PATH.
4. `Artifacts/Phase10-Migration/Step5/zdm-install-report.md` is written with final status `VERIFIED`.
