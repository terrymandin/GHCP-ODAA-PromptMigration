---
mode: agent
description: ZDM Step 2 - Verify or install ZDM 26.1 on the ZDM jumpbox (runs in Remote-SSH session as zdmuser)
---
# ZDM Migration Step 2: ZDM Installation Verification and Setup

## Purpose

Verify that Zero Downtime Migration (ZDM) version 26.1 is installed and running on the jumpbox. If ZDM is not installed, create the `zdmuser` OS user, guide the user through the download and installation, and ensure `ZDM_HOME` and the ZDM `bin` path are set in `zdmuser`'s `.bashrc`.

> **Note:** The ZDM Azure VM is created during Step 1 (Remote-SSH Setup). By the time this step runs, the VM already exists and the Remote-SSH connection is established.

---

## IMPORTANT: Execution Context

This step runs entirely in the **Remote-SSH VS Code session** on the ZDM jumpbox, logged in as **`zdmuser`**.

- `zdmuser` and `/home/zdmuser` are created and ownership is transferred during Step 1. The Remote-SSH connection is configured in Step 1 to connect as `zdmuser`.
- Use `sudo` for commands that require `root` privileges (e.g., installing packages, creating directories under `/u01/`).
- Do **not** use `sudo -u zdmuser` to impersonate `zdmuser` — the session is already `zdmuser`.
- Do not run ZDM installation commands locally. Do not use PowerShell or Windows-native commands on the jumpbox.
- **Environment scope (CR-13):** This prompt step is intended for **development and non-production environments only**. Do not run Copilot agent steps directly against production systems.

---

## First Action: Display Environment Safety Banner (CR-13.3)

Before doing anything else, display the following banner in the chat:

```
⚠ ENVIRONMENT SAFETY: This prompt is for development/non-production use only.
Do not run against production. Generated scripts may be copied to production
once reviewed and tested — run them manually there.
```

---

## Pre-populated Bypass Check

Before doing anything else, check whether Step 2 has already been completed:

Read the file `Artifacts/Phase10-Migration/Step5/zdm-install-report.md` using file tools.

- If the file exists and the `## Status` section shows `VERIFIED`: Display a confirmation summary (ZDM version, ZDM_HOME, service running status) and jump directly to [Phase 5: Write Artifacts](#phase-5-write-artifacts). Do not re-run installation.

- If the file does not exist or shows `ACTION REQUIRED`: Continue with Phase 1 below.

---

## Phase 1: Detect Installed ZDM Version (S3-03, S3-10)

Run the following detection sequence in the jumpbox terminal to find an existing ZDM installation:

```bash
# Probe for zdmcli in environment variable and common paths
if [ -n "$ZDM_HOME" ] && [ -x "$ZDM_HOME/bin/zdmcli" ]; then
    DETECTED_ZDM_HOME="$ZDM_HOME"
elif [ -x "/u01/app/zdmhome/bin/zdmcli" ]; then
    DETECTED_ZDM_HOME="/u01/app/zdmhome"
elif [ -x "/home/zdmuser/zdmhome/bin/zdmcli" ]; then
    DETECTED_ZDM_HOME="/home/zdmuser/zdmhome"
elif [ -x "/home/zdmuser/zdm/home/bin/zdmcli" ]; then
    DETECTED_ZDM_HOME="/home/zdmuser/zdm/home"
elif command -v zdmcli >/dev/null 2>&1; then
    DETECTED_ZDM_HOME="$(dirname $(dirname $(command -v zdmcli)))"
else
    DETECTED_ZDM_HOME=""
fi
echo "DETECTED_ZDM_HOME=${DETECTED_ZDM_HOME}"
```

**If `DETECTED_ZDM_HOME` is set:**

Run the version check:
```bash
"$DETECTED_ZDM_HOME/bin/zdmcli" -build 2>&1
```

Check that the output contains `26.1`. For example:
```
full version: "26.1.0"
```

- **Version matches 26.1** → Record `ZDM_HOME` and proceed to [Phase 3: Service Status Check](#phase-3-service-status-check).
- **Version does not match 26.1** → Report the discovered version and proceed to [Phase 2: ZDM Installation](#phase-2-zdm-installation).

**If `DETECTED_ZDM_HOME` is empty:** → Proceed to [Phase 2: ZDM Installation](#phase-2-zdm-installation).

---

## Phase 2: ZDM Installation (S3-04, S3-11, S3-12, S3-13)

### 2a. Verify `zdmuser` OS User

`zdmuser` is created during Step 1. Confirm the account exists and owns its home directory before proceeding:

```bash
id zdmuser
stat -c '%U %G' /home/zdmuser
```

Expected: `zdmuser` is present and owns `/home/zdmuser`. If the account is missing (Step 1 was skipped or failed), create it using `sudo` before continuing:

```bash
getent group zdm  > /dev/null 2>&1 || sudo groupadd zdm
getent passwd zdmuser > /dev/null 2>&1 || sudo useradd -g zdm -d /home/zdmuser -M zdmuser
sudo chown -R zdmuser:zdmuser /home/zdmuser
```

If `sudo` is unavailable, surface the commands to the user and ask them to run as `root` before continuing.

### 2b. Pre-Installation Package Check

Before downloading, verify required packages are present:

```bash
for pkg in expect glibc-devel libnsl ncurses-compat-libs libaio unzip perl; do
    rpm -q "$pkg" > /dev/null 2>&1 && echo "$pkg: OK" || echo "$pkg: MISSING"
done
```

Also detect the OS version:
```bash
cat /etc/os-release | grep -E '^(NAME|VERSION_ID)='
```

If any packages are `MISSING`, run the appropriate install command using `sudo` (the SSH user typically has sudo on Azure VMs):

**Oracle Linux 8 / RHEL 8:**
```bash
sudo yum install -y expect glibc-devel libnsl ncurses-compat-libs libaio unzip perl
```

**Oracle Linux 9 / RHEL 9:**
```bash
sudo yum install -y expect glibc-devel libnsl ncurses-compat-libs libaio unzip perl wget
```

If `sudo` is not available, surface the command to the user and ask them to run it as `root` before continuing.

### 2c. Download the ZDM Kit

Display the following prompt to the user:

> **Action Required — ZDM Download**
>
> ZDM 26.1 is not installed. You need to download the ZDM software kit from Oracle.
>
> 1. Navigate to the [Zero Downtime Migration Download](https://www.oracle.com/database/technologies/rac/zdm-downloads.html) page.
> 2. Select **ZDM 26.1** and click **Download**.
> 3. The Oracle download page will provide a `wget` command with an authentication token.
> 4. **Copy the full `wget` command (including token) and paste it here.**
>
> Once you paste the command, I will execute the download directly on the jumpbox.

Wait for the user to paste the `wget` command. Do not proceed to 2d until the command is provided.

### 2d. Execute the Download

Once the user provides the `wget` command:

1. Validate the command contains `wget` (or `curl`) and references an Oracle download host.
2. Create a working download directory and set ownership to `zdmuser`:
   ```bash
   sudo mkdir -p /u01/app/zdm_download
   sudo chown zdmuser:zdm /u01/app/zdm_download
   cd /u01/app/zdm_download
   ```
3. Execute the provided download command. Capture output and confirm a non-zero file was downloaded.
4. Identify the downloaded zip file:
   ```bash
   ls -1t /u01/app/zdm_download/*.zip | head -1
   ```
   Store this as `ZDM_KIT_ZIP`.

### 2e. Create Installation Directories and Set Ownership

Create the ZDM home and base directories and assign them to `zdmuser`:
```bash
sudo mkdir -p /u01/app/zdmhome
sudo mkdir -p /u01/app/zdmbase
sudo chown -R zdmuser:zdm /u01/app/zdmhome /u01/app/zdmbase
```

### 2f. Unzip and Run the Installer

The session is already `zdmuser`, so run the installer directly:

```bash
cd /u01/app/zdm_download
unzip "$ZDM_KIT_ZIP"

# Locate installer and inner zip
INSTALL_SCRIPT=$(find /u01/app/zdm_download -name "zdminstall.sh" | head -1)
ZDM_HOME_ZIP=$(find /u01/app/zdm_download -name "zdm_home.zip" | head -1)

echo "Installer: $INSTALL_SCRIPT"
echo "ZDM home zip: $ZDM_HOME_ZIP"

"$INSTALL_SCRIPT" setup \
    oraclehome=/u01/app/zdmhome \
    oraclebase=/u01/app/zdmbase \
    ziploc="$ZDM_HOME_ZIP"
```

> **Note:** After installation, the installer will display a message asking you to run `orainstRoot.sh` and `root.sh`. **Ignore these messages** — they are not required for ZDM.

If the installer exits non-zero, display the last 30 lines of output to the user and stop. Do not proceed to the service start.

Set `DETECTED_ZDM_HOME=/u01/app/zdmhome` after a successful install.

---

## Phase 3: Service Status Check (S3-10)

The session is `zdmuser`, so run the service commands directly:

```bash
"$DETECTED_ZDM_HOME/bin/zdmservice" status 2>&1
```

If the output shows `Running: false` or the service is not yet started, start it:

```bash
"$DETECTED_ZDM_HOME/bin/zdmservice" start
```

Then re-check status:
```bash
"$DETECTED_ZDM_HOME/bin/zdmservice" status 2>&1
```

Confirm the output shows `Running: true`. Capture the full status output for the report.

---

## Phase 4: .bashrc Environment Setup (S3-05, S3-14)

The session is `zdmuser` and the session owns `/home/zdmuser`. Read and write `.bashrc` directly — no `sudo` required.

Check for existing `ZDM_HOME` and PATH entries:

```bash
grep -n 'ZDM_HOME\|zdmhome' ~/.bashrc
```

**If `ZDM_HOME` is already set to the correct path and `$ZDM_HOME/bin` is already on the PATH:**
- Mark `.bashrc` status as `ALREADY SET`. Skip the update.

**If missing or set to an incorrect path:**

Append the following block to `/home/zdmuser/.bashrc` (substitute the actual detected `ZDM_HOME` path):

```bash
tee -a ~/.bashrc << 'BASHRC_EOF'

# ZDM Environment
export ZDM_HOME=/u01/app/zdmhome
export PATH=$ZDM_HOME/bin:$PATH
BASHRC_EOF
```

> Use the actual confirmed `DETECTED_ZDM_HOME` path in the `export ZDM_HOME=` line — not the hardcoded example if it differs.

Source `.bashrc` to verify the settings apply correctly:
```bash
bash -c 'source ~/.bashrc && which zdmcli && zdmcli -build | grep "full version"'
```

---

## Phase 5: Write Artifacts (S3-01, S3-15, S3-16)

Using file tools, write the following two files:

### `Artifacts/Phase10-Migration/Step5/zdm-install-report.md`

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

### `Artifacts/Phase10-Migration/Step5/README.md`

```markdown
# Step 2 — ZDM Installation

## Files Generated
- `zdm-install-report.md` — ZDM version verification and installation summary

## Manual Actions Required (if any)
<List any root-level commands the user must run, or "None" if all actions were completed automatically>

## Success Signals
- `zdmservice status` shows `Running: true`
- `zdmcli -build` shows `full version: "26.1.0"`
- `ZDM_HOME` is set in `~/.bashrc`

## Next Step
Proceed to Step 4 (SSH Connectivity) in the Remote-SSH VS Code session.
```

---

## Phase 6: User Handoff

After writing both artifacts, display a summary:

```
Step 2 — ZDM Installation
--------------------------
ZDM Version:     26.1.0  ✓
ZDM_HOME:        /u01/app/zdmhome
Service:         Running: true  ✓
.bashrc:         ZDM_HOME and PATH configured  ✓

Status: VERIFIED

-> Next: Step 3 - Configure SSH Connectivity

Run @Phase10-ZDM-Orchestrator or say "continue" to proceed.
```

If status is `ACTION REQUIRED`, list the remaining actions and do not suggest proceeding until they are resolved.
