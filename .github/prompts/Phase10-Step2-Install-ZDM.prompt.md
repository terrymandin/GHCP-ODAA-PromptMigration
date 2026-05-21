---
mode: agent
description: ZDM Step 2 - Verify or install ZDM 26.1 on the ZDM jumpbox (runs in Remote-SSH session as zdmuser)
---
# ZDM Migration Step 2: ZDM Installation Verification and Setup

## Purpose

Verify that Zero Downtime Migration (ZDM) version 26.1 is installed and running on the jumpbox. If ZDM is not installed, verify prerequisites, guide the user through the Oracle download, and run the installer. Ensure `ZDM_HOME` and the ZDM `bin` directory are configured in `zdmuser`'s `.bashrc`.

> **Note:** The ZDM Azure VM is created during Step 1 (VM Create + Remote-SSH Setup). By the time this step runs, the VM already exists and the Remote-SSH connection is established.

---

## Execution Context

This step runs entirely in the **Remote-SSH VS Code session** on the ZDM jumpbox, logged in as **`zdmuser`**.

- `zdmuser`, `/home/zdmuser`, the ZDM prerequisite packages, and the `/u01/app/zdm*` directories are all set up during Step 1. This step verifies they exist before proceeding.
- `zdmuser` does **not** have `sudo` access by default. Do not use `sudo -u zdmuser` or `sudo su zdmuser` — the session already is `zdmuser`. Any command requiring root is handled via the escalation method collected in Phase 0.
- **Environment scope (CR-13):** This prompt is for **development and non-production environments only**. Do not run Copilot agent steps directly against production systems.

---

## First Action: Display Environment Safety Banner (CR-13.3)

Before doing anything else, display:

```
⚠ ENVIRONMENT SAFETY: This prompt is for development/non-production use only.
Do not run against production. Generated scripts may be copied to production
once reviewed and tested — run them manually there.
```

---

## Pre-populated Bypass Check (S3-01)

Read `Artifacts/Phase10-Migration/Step2/zdm-install-report.md` using file tools.

- If it exists and `## Status` shows `VERIFIED`: display a summary (ZDM version, ZDM_HOME, service status) and skip to [Phase 5: Write Artifacts](#phase-5-write-artifacts-s3-15-s3-16). Do not re-run installation.
- If absent or shows `ACTION REQUIRED`: continue with Phase 0.

---

## Phase 0: Collect Escalation Credentials (S3-09B)

`zdmuser` has no `sudo` access by default. First check whether root escalation is needed at all, then collect only the credentials required for the chosen method.

### 0a. Check Whether zdmuser Already Has Sudo Access

Run in the jumpbox terminal:
```bash
sudo -n true 2>/dev/null && echo "HAS_SUDO" || echo "NO_SUDO"
```

- **`HAS_SUDO`**: record `ESCALATION_METHOD=passwordless-sudo`. Skip to Phase 1.
- **`NO_SUDO`**: continue to 0b.

### 0b. Choose an Escalation Method

Ask the user the following question in chat (CR-16-A). Do NOT use `vscode_askQuestions` — post the question as plain markdown in the chat:

> **`zdmuser` does not have passwordless sudo. When root operations are needed (e.g., installing missing packages), how should I escalate?**
>
> **Option A — Local terminal** *(no changes to the VM)*: I'll show a ready-to-run PowerShell `ssh` command you run from your local terminal as `azureuser`. You run it and reply "done".
>
> **Option B — zdmuser sudo password** *(one-time setup)*: Provide a password for zdmuser and I'll configure password-based sudo. Root operations will then run in-session — no separate terminal needed after the one-time setup.
>
> Reply with **A** or **B**.

**If Option A:**
- Record `ESCALATION_METHOD=local-terminal`.
- Post the following in chat (CR-16-A — do NOT use `vscode_askQuestions`):
  > **Two values are needed to generate the escalation command (both are in your local `Artifacts/Phase10-Migration/Step1/remote-ssh-setup-report.md` on Windows):**
  > 1. **Jumpbox public IP** — `Public IP:` line in the `## VM Details` section (e.g., `51.105.43.11`)
  > 2. **azureuser SSH key path** — `Key path:` line in the `## SSH Key` section (e.g., `C:\Users\you\SSHTesting\key.pem`)
- Store as `JUMPBOX_HOST` and `JUMPBOX_SSH_KEY`. All escalation commands will use these real values — no placeholders.

**If Option B:**
- Post the following in chat (CR-16-A — do NOT use `vscode_askQuestions`):
  > **Two values are needed for the one-time sudo setup (both are in your local `Artifacts/Phase10-Migration/Step1/remote-ssh-setup-report.md` on Windows):**
  > 1. **Jumpbox public IP** — `Public IP:` line in the `## VM Details` section
  > 2. **azureuser SSH key path** — `Key path:` line in the `## SSH Key` section
  > 3. **What password do you want to set for `zdmuser`?**
- Store as `JUMPBOX_HOST`, `JUMPBOX_SSH_KEY`, and `ZDMUSER_PASS` (session variable — never written to disk or any file).
- Show the one-time setup command with real values substituted for `$JUMPBOX_SSH_KEY`, `$JUMPBOX_HOST`, and `$ZDMUSER_PASS`:
  ```powershell
  ssh -o BatchMode=yes -p 22 -i "$JUMPBOX_SSH_KEY" azureuser@$JUMPBOX_HOST `
    "echo 'zdmuser:$ZDMUSER_PASS' | sudo chpasswd && echo 'zdmuser ALL=(ALL) ALL' | sudo tee /etc/sudoers.d/zdmuser-pwd && sudo chmod 440 /etc/sudoers.d/zdmuser-pwd"
  ```
- After the user confirms it ran, verify in-session:
  ```bash
  echo "$ZDMUSER_PASS" | sudo -S true 2>/dev/null && echo "SUDO_OK" || echo "SUDO_FAIL"
  ```
  - `SUDO_OK` → record `ESCALATION_METHOD=sudo-password`. Continue to Phase 1.
  - `SUDO_FAIL` → surface the error, ask the user to retry the setup command, and re-test before continuing.

---

## Phase 1: Detect Installed ZDM Version (S3-03, S3-10)

Run the following detection sequence in the jumpbox terminal:

```bash
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

**If `DETECTED_ZDM_HOME` is set**, check the version:
```bash
"$DETECTED_ZDM_HOME/bin/zdmcli" -build 2>&1
```
- Output contains `26.1` → ZDM 26.1 confirmed. Record `DETECTED_ZDM_HOME` and skip to [Phase 3: Service Status Check](#phase-3-service-status-check-s3-10).
- Output does not contain `26.1` → report the detected version and proceed to Phase 2.

**If `DETECTED_ZDM_HOME` is empty** → proceed to Phase 2.

---

## Phase 2: ZDM Installation (S3-04, S3-11, S3-12, S3-13)

### 2a. Verify `zdmuser` OS User and Directories (S3-04 Step A)

`zdmuser` and the `/u01/app/zdm*` directories are prepared during Step 1. Confirm before proceeding:

```bash
id zdmuser
stat -c '%U %G' /home/zdmuser
stat -c '%U %G %n' /u01/app/zdmhome /u01/app/zdmbase /u01/app/zdm_download
```

Expected: `zdmuser` exists; `/home/zdmuser` owned by `zdmuser zdm`; all three `/u01/app/zdm*` dirs owned by `zdmuser zdm`.

If any directory is missing or not owned by `zdmuser`, escalate using `ESCALATION_METHOD` from Phase 0:

**`ESCALATION_METHOD=local-terminal`** — run from your local PowerShell terminal:
```powershell
ssh -o BatchMode=yes -p 22 -i "$JUMPBOX_SSH_KEY" azureuser@$JUMPBOX_HOST "sudo mkdir -p /u01/app/zdmhome /u01/app/zdmbase /u01/app/zdm_download && sudo chown -R zdmuser:zdm /u01/app/zdmhome /u01/app/zdmbase /u01/app/zdm_download"
```

**`ESCALATION_METHOD=sudo-password`** — run in the jumpbox terminal:
```bash
echo "$ZDMUSER_PASS" | sudo -S mkdir -p /u01/app/zdmhome /u01/app/zdmbase /u01/app/zdm_download
echo "$ZDMUSER_PASS" | sudo -S chown -R zdmuser:zdm /u01/app/zdmhome /u01/app/zdmbase /u01/app/zdm_download
```

Do not proceed until all directories exist and are owned by `zdmuser zdm`.

### 2b. Pre-Installation Package Check (S3-04 Step C, S3-12)

Verify required packages before downloading. First detect the OS version:
```bash
grep -E '^(NAME|VERSION_ID)=' /etc/os-release
```

Check for missing packages:
```bash
for pkg in expect glibc-devel libnsl ncurses-compat-libs libaio unzip perl wget; do
    rpm -q "$pkg" > /dev/null 2>&1 && echo "$pkg: OK" || echo "$pkg: MISSING"
done
```

If any are `MISSING`, install them using the `ESCALATION_METHOD` from Phase 0:

**`ESCALATION_METHOD=local-terminal`** — run from your local PowerShell terminal:

*Oracle Linux 8 / RHEL 8:*
```powershell
ssh -o BatchMode=yes -p 22 -i "$JUMPBOX_SSH_KEY" azureuser@$JUMPBOX_HOST "sudo dnf install -y expect glibc-devel libnsl ncurses-compat-libs libaio unzip perl"
```
*Oracle Linux 9/10 / RHEL 9:*
```powershell
ssh -o BatchMode=yes -p 22 -i "$JUMPBOX_SSH_KEY" azureuser@$JUMPBOX_HOST "sudo dnf install -y expect glibc-devel libnsl ncurses-compat-libs libaio unzip perl wget"
```

**`ESCALATION_METHOD=sudo-password`** — run in the jumpbox terminal:

*Oracle Linux 8 / RHEL 8:*
```bash
echo "$ZDMUSER_PASS" | sudo -S dnf install -y expect glibc-devel libnsl ncurses-compat-libs libaio unzip perl
```
*Oracle Linux 9/10 / RHEL 9:*
```bash
echo "$ZDMUSER_PASS" | sudo -S dnf install -y expect glibc-devel libnsl ncurses-compat-libs libaio unzip perl wget
```

After the install completes, re-run the `rpm -q` loop to confirm all packages report `OK`. Do not continue until all are confirmed.

### 2c. Download the ZDM Kit (S3-04 Step B, S3-11)

Navigate to the download directory:
```bash
cd /u01/app/zdm_download
```

Ask the user:

> **Action Required — ZDM Download**
>
> 1. Navigate to the [Zero Downtime Migration Downloads](https://www.oracle.com/database/technologies/rac/zdm-downloads.html) page.
> 2. Select **ZDM 26.1** and copy the `wget` command (including the authentication token).
> 3. **Paste the full `wget` command here.**

Wait for the user to paste the command before proceeding.

Validate the pasted command:
- Contains `wget` (or `curl`)
- Points to an Oracle host (e.g., `edelivery.oracle.com`, `oss.oracle.com`)
- Includes an authentication token or SSO cookie

If valid, execute it in the jumpbox terminal. Confirm a non-zero file was downloaded (check for `200 OK` or exit code 0). Then identify the downloaded zip:
```bash
ls -1t /u01/app/zdm_download/*.zip | head -1
```
Store the path as `ZDM_KIT_ZIP`.

### 2d. Verify Installation Directories (S3-04 Step D, S3-13)

Confirm the `/u01/app/zdm*` directories still exist and are correctly owned:
```bash
stat -c '%U %G %n' /u01/app/zdmhome /u01/app/zdmbase /u01/app/zdm_download
```
If any are missing, use the escalation commands from 2a above.

### 2e. Unzip and Run the Installer (S3-04 Step E, S3-13)

The session is already `zdmuser` — run the installer directly, with no `sudo` or `sudo -u zdmuser` prefix:

```bash
cd /u01/app/zdm_download
unzip "$ZDM_KIT_ZIP"

INSTALL_SCRIPT=$(find /u01/app/zdm_download -name "zdminstall.sh" | head -1)
ZDM_HOME_ZIP=$(find /u01/app/zdm_download -name "zdm_home.zip" | head -1)

echo "Installer: $INSTALL_SCRIPT"
echo "ZDM home zip: $ZDM_HOME_ZIP"

"$INSTALL_SCRIPT" setup \
    oraclehome=/u01/app/zdmhome \
    oraclebase=/u01/app/zdmbase \
    ziploc="$ZDM_HOME_ZIP"
```

Capture the full installer output. If the installer exits non-zero, display the last 30 lines and set status to `ACTION REQUIRED` — do not proceed to Phase 3.

> **Note:** Ignore any post-install message asking you to run `orainstRoot.sh` or `root.sh`. These are not required for ZDM.

Set `DETECTED_ZDM_HOME=/u01/app/zdmhome` after a successful install.

---

## Phase 3: Service Status Check (S3-10)

The session is `zdmuser` — run the service commands directly:

```bash
"$DETECTED_ZDM_HOME/bin/zdmservice" status 2>&1
```

If the output shows `Running: false`, start the service:
```bash
"$DETECTED_ZDM_HOME/bin/zdmservice" start
```

Then re-check:
```bash
"$DETECTED_ZDM_HOME/bin/zdmservice" status 2>&1
```

Confirm the output shows `Running: true`. Capture the full status output for the artifact report.

If the service fails to start, surface the output and suggest checking logs:
```bash
journalctl -u zdm 2>/dev/null || ls "$DETECTED_ZDM_HOME/../zdmbase/crsdata/$(hostname)/rhp/" 2>/dev/null
```

---

## Phase 4: .bashrc Environment Setup (S3-05, S3-14)

The session is `zdmuser` — read and write `~/.bashrc` directly, no `sudo` required.

Check for existing entries:
```bash
grep -n 'ZDM_HOME\|zdmhome' ~/.bashrc
```

Check specifically whether `ZDM_HOME` is already set to the correct path:
```bash
grep -c "export ZDM_HOME=${DETECTED_ZDM_HOME}" ~/.bashrc
```

Check whether `$ZDM_HOME/bin` is already on the PATH:
```bash
grep -c 'ZDM_HOME.*bin.*PATH\|PATH.*ZDM_HOME.*bin' ~/.bashrc
```

**If both checks return ≥ 1**: mark `.bashrc` status as `ALREADY SET` and skip the update.

**If either check returns 0**, append the following block (substituting the actual `DETECTED_ZDM_HOME` value):
```bash
tee -a ~/.bashrc << 'BASHRC_EOF'

# ZDM Environment
export ZDM_HOME=/u01/app/zdmhome
export PATH=$ZDM_HOME/bin:$PATH
BASHRC_EOF
```

Validate the update:
```bash
source ~/.bashrc && which zdmcli && zdmcli -build | grep "full version"
```

---

## Phase 5: Write Artifacts (S3-15, S3-16)

Write both files using file tools. Create the `Artifacts/Phase10-Migration/Step2/` directory if absent.

### `Artifacts/Phase10-Migration/Step2/zdm-install-report.md`

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

Set `Status` to:
- **VERIFIED** — ZDM 26.1 confirmed, service running, `.bashrc` configured.
- **ACTION REQUIRED** — any required item is incomplete; list each under "Remaining Actions".

### `Artifacts/Phase10-Migration/Step2/README.md`

```markdown
# Step 2 — ZDM Installation Outputs

## Files Generated
| File | Description |
|------|-------------|
| `zdm-install-report.md` | ZDM version verification and installation summary |
| `README.md` | This file |

## Manual Actions Required (if any)
<List any root-level commands the user must run, or "None" if all actions were completed automatically>

## Success Signals
- `zdmservice status` shows `Running: true`
- `zdmcli -build` shows `full version: "26.1.0"`
- `ZDM_HOME` and `$ZDM_HOME/bin` are set in `~/.bashrc`

## Failure Signals
- Installer exits non-zero → review installer output; check directory ownership
- Service fails to start → check `journalctl -u zdm` or `$ZDM_BASE/crsdata/<hostname>/rhp/rhpserver.log`
- Packages missing → re-run package install as azureuser, then re-verify

## Next Step
Proceed to Step 3 (Configure SSH Connectivity) in the Remote-SSH VS Code session.
```

---

## Phase 6: User Handoff

Display a summary:

```
Step 2 — ZDM Installation
--------------------------
ZDM Version:  26.1.0  ✓
ZDM_HOME:     /u01/app/zdmhome
Service:      Running: true  ✓
.bashrc:      ZDM_HOME and PATH configured  ✓

Status: VERIFIED

→ Next: Run @Phase10-ZDM-Orchestrator or say "continue" to proceed to Step 3.
```

If status is `ACTION REQUIRED`, list the remaining actions and do not suggest proceeding until they are resolved.

---

## Success Criteria (S3-06)

Step 2 is complete when all of the following are true:

1. `zdmcli -build` returns a version string containing `26.1`.
2. `zdmservice status` shows `Running: true`.
3. `ZDM_HOME` is set in `zdmuser`'s `~/.bashrc` with `$ZDM_HOME/bin` on the PATH.
4. `Artifacts/Phase10-Migration/Step2/zdm-install-report.md` is written with status `VERIFIED`.

