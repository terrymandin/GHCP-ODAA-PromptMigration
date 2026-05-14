# Step3 System Requirements — ZDM Installation Implementation

## Scope

Implementation-level constraints for Step3. The step runs entirely in the Remote-SSH terminal on the jumpbox as the SSH user (e.g., `azureuser`). Commands scoped to `zdmuser` use `sudo -u zdmuser`.

> **Note:** Azure VM creation is handled in Step 1. S3-09 (VM creation implementation) has been moved to Step 1 system requirements.

---

## S3-10: Version Detection Implementation

1. Probe for an installed ZDM binary in this order — stop at the first match:

   ```bash
   # Check 1: ZDM_HOME environment variable
   if [ -n "$ZDM_HOME" ] && [ -x "$ZDM_HOME/bin/zdmcli" ]; then
       DETECTED_ZDM_HOME="$ZDM_HOME"
   # Check 2: Common install paths
   elif [ -x "/u01/app/zdmhome/bin/zdmcli" ]; then
       DETECTED_ZDM_HOME="/u01/app/zdmhome"
   elif [ -x "/home/zdmuser/zdmhome/bin/zdmcli" ]; then
       DETECTED_ZDM_HOME="/home/zdmuser/zdmhome"
   elif [ -x "/home/zdmuser/zdm/home/bin/zdmcli" ]; then
       DETECTED_ZDM_HOME="/home/zdmuser/zdm/home"
   # Check 3: PATH
   elif command -v zdmcli >/dev/null 2>&1; then
       DETECTED_ZDM_HOME="$(dirname $(dirname $(command -v zdmcli)))"
   else
       DETECTED_ZDM_HOME=""
   fi
   ```

2. If `DETECTED_ZDM_HOME` is empty, set version result to `NOT INSTALLED`.

3. If `DETECTED_ZDM_HOME` is set, run:
   ```bash
   "$DETECTED_ZDM_HOME/bin/zdmcli" -build 2>&1
   ```
   Extract the `full version:` line. Confirm it contains `26.1`. If it does not contain `26.1`, report the detected version and proceed to the installation branch.

4. Also run `zdmservice status` to confirm the service is running. Because the current session is the SSH user, use `sudo -u zdmuser`:
   ```bash
   sudo -u zdmuser "$DETECTED_ZDM_HOME/bin/zdmservice" status 2>&1
   ```
   Parse the `Running:` field. If `Running: false`, start the service:
   ```bash
   sudo -u zdmuser "$DETECTED_ZDM_HOME/bin/zdmservice" start
   ```

---

## S3-11: Download Step Implementation

1. When the user pastes a `wget` command and token, validate that the command:
   - Contains `wget` (or `curl`)
   - Points to an Oracle host (e.g., `edelivery.oracle.com`, `oss.oracle.com`, or similar Oracle domain)
   - Includes a download token or SSO cookie argument

2. If the wget command appears complete, execute it on the jumpbox. Capture output to confirm download success (check for `200 OK` or non-zero exit code).

3. After download, identify the downloaded filename:
   ```bash
   ls -1t /u01/app/zdm_download/*.zip | head -1
   ```
   This is the ZDM kit zip file. Store the path as `ZDM_KIT_ZIP`.

4. Identify the inner `zdm_home.zip` or equivalent after unzipping:
   ```bash
   unzip -l "$ZDM_KIT_ZIP" | grep -i 'zdm_home\.zip'
   ```

---

## S3-12: Pre-Installation Package Check Implementation

Before running the installer, verify each required package is present. These packages should have been installed by Step 1 (as the admin user). Report any that are missing, but **do not attempt to install them from the `zdmuser` session** — `zdmuser` does not have `sudo`. If packages are missing, surface the install command for the user to run as `azureuser` (or root) before continuing.

Check for missing packages:
```bash
for pkg in expect glibc-devel libnsl ncurses-compat-libs libaio unzip perl wget; do
    rpm -q "$pkg" > /dev/null 2>&1 && echo "$pkg: OK" || echo "$pkg: MISSING"
done
```

If any are `MISSING`, display the appropriate install command for the user to run as `azureuser` **from a local PowerShell terminal** (not in the Remote-SSH session):

**Oracle Linux 8 / RHEL 8:**
```powershell
ssh -o BatchMode=yes -p 22 -i "<JUMPBOX_SSH_KEY>" azureuser@<JUMPBOX_HOST> "sudo dnf install -y expect glibc-devel libnsl ncurses-compat-libs libaio unzip perl"
```

**Oracle Linux 9/10 / RHEL 9:**
```powershell
ssh -o BatchMode=yes -p 22 -i "<JUMPBOX_SSH_KEY>" azureuser@<JUMPBOX_HOST> "sudo dnf install -y expect glibc-devel libnsl ncurses-compat-libs libaio unzip perl wget"
```

Do not continue until all packages report `OK`.

Detect the OS version to confirm the correct package list:
```bash
grep -E '^(NAME|VERSION_ID)=' /etc/os-release
```

---

## S3-13: Installation Directory Verification and ZDM Setup

1. Verify the ZDM installation directories exist and are owned by `zdmuser` (they should have been created by Step 1):
   ```bash
   stat -c '%U %G %n' /u01/app/zdmhome /u01/app/zdmbase /u01/app/zdm_download
   ```
   Expected: each line shows `zdmuser zdm <path>`. If any directory is missing or not owned by `zdmuser`, surface the following command for the user to run as `azureuser` from a local terminal:
   ```powershell
   ssh -o BatchMode=yes -p 22 -i "<JUMPBOX_SSH_KEY>" azureuser@<JUMPBOX_HOST> "sudo mkdir -p /u01/app/zdmhome /u01/app/zdmbase /u01/app/zdm_download && sudo chown -R zdmuser:zdm /u01/app/zdmhome /u01/app/zdmbase /u01/app/zdm_download"
   ```

2. Unzip the ZDM kit, then locate and run the installer as `zdmuser` (the current session):
   ```bash
   cd /u01/app/zdm_download
   unzip "$ZDM_KIT_ZIP"
   # Locate the install script
   INSTALL_SCRIPT=$(find /u01/app/zdm_download -name "zdminstall.sh" | head -1)
   # Locate the inner zdm_home.zip
   ZDM_HOME_ZIP=$(find /u01/app/zdm_download -name "zdm_home.zip" | head -1)
   "$INSTALL_SCRIPT" setup \
       oraclehome=/u01/app/zdmhome \
       oraclebase=/u01/app/zdmbase \
       ziploc="$ZDM_HOME_ZIP"
   ```
   **Do not prefix with `sudo` or `sudo -u zdmuser`** — the current session already is `zdmuser` and owns the installation directories.

4. Capture the full installer output. On success, the installer exits 0 and does not print an unrecoverable error.

5. Ignore the post-install root script messages. Do **not** run `orainstRoot.sh` or `root.sh`.

---

## S3-14: .bashrc Update Implementation

The target file is `zdmuser`'s `/home/zdmuser/.bashrc`. Since the current session is the SSH user, all read/write operations use `sudo`.

1. Read the current `/home/zdmuser/.bashrc` contents:
   ```bash
   sudo cat /home/zdmuser/.bashrc
   ```

2. Check if `ZDM_HOME` is already exported with the correct path using a precise match:
   ```bash
   sudo grep -c "export ZDM_HOME=${DETECTED_ZDM_HOME}" /home/zdmuser/.bashrc
   ```

3. Check if `$ZDM_HOME/bin` is already on the PATH in `.bashrc`:
   ```bash
   sudo grep -c 'ZDM_HOME.*bin.*PATH\|PATH.*ZDM_HOME.*bin' /home/zdmuser/.bashrc
   ```

4. Only append if either check returns 0. Use `sudo tee -a` to append:
   ```bash
   sudo tee -a /home/zdmuser/.bashrc << 'EOF'

   # ZDM Environment
   export ZDM_HOME=/u01/app/zdmhome
   export PATH=$ZDM_HOME/bin:$PATH
   EOF
   ```
   Replace `/u01/app/zdmhome` with the actual `DETECTED_ZDM_HOME` value.

5. Validate PATH update as `zdmuser`:
   ```bash
   sudo -u zdmuser bash -c 'source ~/.bashrc && which zdmcli && zdmcli -build | grep "full version"'
   ```

---

## S3-15: Artifact Report Format

Write `Artifacts/Phase10-Migration/Step5/zdm-install-report.md` using file tools. The report format is:

```markdown
# ZDM Installation Report
Generated: <ISO timestamp>

## Version
- Detected ZDM Version: <version string or NOT INSTALLED>
- Required Version: 26.1
- Version Match: YES | NO

## Installation
- ZDM_HOME: <path>
- Action Taken: SKIPPED (already installed) | INSTALLED
- zdmservice Running: true | false

## Environment
- .bashrc ZDM_HOME: ALREADY SET | UPDATED
- .bashrc PATH: ALREADY SET | UPDATED

## zdmservice Status
<paste of zdmservice status output>

## zdmcli Build Info
<paste of zdmcli -build output>

## Status
VERIFIED | ACTION REQUIRED

### Remaining Actions (if ACTION REQUIRED)
- <list any outstanding manual steps>
```

---

## S3-16: Step3 README Requirement (CR-07)

Write `Artifacts/Phase10-Migration/Step5/README.md` alongside the install report. It must include:

1. **Files generated**: `zdm-install-report.md`
2. **Manual actions**: Any `root`-level commands the user must run (if packages were missing or `sudo` was unavailable).
3. **Success signals**: `Running: true` in `zdmservice status`, `26.1` in `zdmcli -build`.
4. **Next step**: Step1 (Remote-SSH Setup) → Step4 (SSH Connectivity).

---

## S3-17: Error Handling

- If the installer exits non-zero, capture the last 30 lines of output and display them. Do not write a `VERIFIED` report. Set status to `ACTION REQUIRED` and list what failed.
- If the ZDM service fails to start after installation, surface the `zdmservice start` output and suggest checking system logs: `journalctl -u zdm` or `$ZDM_BASE/crsdata/<hostname>/rhp/rhpserver.log`.
- If package dependencies are missing and the user cannot install them, write the report with `ACTION REQUIRED` and list the missing packages.
