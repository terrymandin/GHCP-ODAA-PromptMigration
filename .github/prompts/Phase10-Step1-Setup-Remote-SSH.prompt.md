---
mode: agent
description: ZDM Step 1 - Setup Remote-SSH connection to the ZDM jumpbox (runs in local VS Code session)
---
# ZDM Migration Step 1: Setup Remote-SSH Connection

## Purpose

Ensure the ZDM Azure VM exists (creating it if needed), then configure the Remote-SSH extension, SSH key, and jumpbox host entry so that subsequent steps (Step 4 onward) can run in the correct Remote-SSH terminal context as `zdmuser`.

---

## IMPORTANT: Execution Context

**This step runs entirely in the LOCAL VS Code session — NOT via Remote-SSH.**

- The terminal executing these commands is your **local PowerShell terminal** (Windows primary).
- The Remote-SSH extension must be installed and the connection configured before any Remote-SSH session can begin.
- Copilot **cannot trigger the Remote-SSH connection** — the final connection step requires user interaction via the VS Code Command Palette.
- Do not run jumpbox commands. Do not read, modify, or create files on the remote jumpbox during this step.
- Do not use `sudo`, `bash`, or Unix-native commands. Use PowerShell equivalents throughout.
- **Environment scope (CR-13):** This prompt step is intended for **development and non-production environments only**. Do not run Copilot agent steps directly against production systems.

---

## Prerequisites

- VS Code is open in the **local** session (not connected to any remote host).
- An OpenSSH client is available locally (`ssh` and `ssh-keygen` ship with Windows 10+).
- No Remote-SSH connection is active yet — this step establishes the connection configuration.

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

Before doing anything else, check whether Step 1 has already been completed:

```powershell
Test-Path "Artifacts/Phase10-Migration/Step1/remote-ssh-setup-report.md"
```

If the file exists, read it and check whether the `## Status` section shows `READY`.

- If status is **READY**: Display a summary of the existing configuration (alias, host, key path) and jump directly to [Phase 7: User Handoff Instructions](#phase-7-user-handoff-instructions). Do not re-run setup.
- If status is **ACTION REQUIRED** or the file does not exist: Continue with Phase 1 below.

---

## Phase 0: ZDM VM Readiness Check

Before configuring SSH, confirm the target VM exists and is reachable. Ask the user:

> **Is the Azure VM for the ZDM jumpbox already created and running?**
> - Yes — it already exists and is running
> - No — I need to create one

### If the VM already exists

Ask for the VM's IP address or FQDN and note it as `JUMPBOX_HOST`. Proceed to [Phase 1: Extension Check](#phase-1-extension-check-s1-03-s1-10).

### If the VM does not yet exist — Azure VM Creation

Ask the user if they would like assistance creating the ZDM Azure VM:

> **Would you like help creating the Azure VM for ZDM?**
> - Yes — help me create it now
> - No — I will create it myself and come back

**If the user declines**, provide a reminder of the recommended VM configuration (shown below) and wait for them to confirm the VM is ready before proceeding to Phase 1.

**If the user accepts**, collect the following parameters one prompt at a time, showing the recommended default for each:

| Parameter | Question to ask | Recommended default |
|-----------|-----------------|---------------------|
| **VM Name** | What name would you like for the ZDM VM? | `zdm-jumpbox` |
| **Resource Group** | Which Azure resource group should the VM be placed in? (Existing or new?) | *(ask user)* |
| **Region** | Which Azure region? | *(ask user)* |
| **Image** | Which OS image? | `Oracle:Oracle-Linux:ol10-lvm-gen2:latest` |
| **VM Size** | Which VM size? | `Standard_D2s_v3` |
| **OS Disk Size** | OS disk size in GB? | `256` |
| **VNet / Subnet** | Which VNet and subnet? (Existing or new?) | *(ask user)* |
| **Authentication** | SSH public key or password? | SSH public key (recommended) |
| **SSH Key / Password** | Paste your SSH public key (or choose password and provide it) | *(ask user)* |
| **SSH Username** | What username should be used for SSH login? | `azureuser` |

Once all parameters are collected, display a parameter summary and ask the user to confirm the values are correct before building the command.

> **Review your VM configuration:**
> - Name: `<name>`
> - Resource Group: `<rg>`
> - Region: `<region>`
> - Image: `<image>`
> - Size: `<size>`
> - OS Disk: `<disk_size_gb>` GB
> - VNet/Subnet: `<vnet>/<subnet>`
> - Auth: `<SSH key | password>`
> - SSH Username: `<username>`
>
> **Are these parameters correct? (Yes / No)**

After the user confirms the parameters, build the full `az vm create` command from the collected values and display it in a fenced code block for review. **Do not run the command yet.**

> If the VNet/subnet does not yet exist, also display the `az network vnet create` and `az network vnet subnet create` commands that will be run first.

```powershell
az vm create `
  --resource-group "<RESOURCE_GROUP>" `
  --name "<VM_NAME>" `
  --location "<REGION>" `
  --image "Oracle:Oracle-Linux:ol10-lvm-gen2:latest" `
  --size "Standard_D2s_v3" `
  --os-disk-size-gb 256 `
  --vnet-name "<VNET_NAME>" `
  --subnet "<SUBNET_NAME>" `
  --admin-username "<SSH_USERNAME>" `
  --ssh-key-values "<SSH_PUBLIC_KEY>" `
  --public-ip-sku Standard `
  --output table
```

> If the user chose password authentication, replace `--ssh-key-values` with `--admin-password "<PASSWORD>"` and add `--authentication-type password`.

After displaying the command, ask:

> **Shall I run this command now? (Yes / No)**

Run the command in the **local PowerShell terminal** only after the user replies **Yes**. If the user replies No, ask what they would like to change.

After the VM is created, display the public IP address returned by `az vm create` — record it as `JUMPBOX_HOST`.

> **VM created successfully.**
> Public IP: `<public_ip>`
>
> This IP address will be used in Phase 2 to configure the Remote-SSH connection.

### Post-Creation: Install VS Code Server Prerequisites

Before configuring Remote-SSH, install `tar` on the new VM. Oracle Linux 10 minimal images do not include `tar` by default, and VS Code Server **cannot install without it** — the connection will fail with "Failed to install the VS Code Server" if this step is skipped.

Run the following in the **local PowerShell terminal**:

```powershell
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes -p 22 `
    -i "<JUMPBOX_SSH_KEY>" <SSH_USERNAME>@<JUMPBOX_HOST> `
    "sudo dnf install -y tar"
```

- **PASS** (`$LASTEXITCODE -eq 0` and output contains `Complete!`): Confirm `tar` installed and continue.
- **FAIL**: Display the error and stop. Do not proceed until `tar` is successfully installed.

### Post-Creation: Clone Migration Repo onto the Jumpbox

Immediately after `tar` is confirmed, clone the migration repo into `/home/zdmuser` on the jumpbox via SSH from the **local PowerShell terminal**. This ensures the repo is present the moment Step 2 opens in the Remote-SSH window.

**Run each command separately and verify exit code 0 before proceeding:**

```powershell
# 1. Install git
ssh -o BatchMode=yes -p 22 -i "<JUMPBOX_SSH_KEY>" <SSH_USERNAME>@<JUMPBOX_HOST> "sudo dnf install -y git"
```

```powershell
# 2. Create /home/zdmuser
ssh -o BatchMode=yes -p 22 -i "<JUMPBOX_SSH_KEY>" <SSH_USERNAME>@<JUMPBOX_HOST> "sudo mkdir -p /home/zdmuser"
```

```powershell
# 3. Clone the repo
ssh -o BatchMode=yes -p 22 -i "<JUMPBOX_SSH_KEY>" <SSH_USERNAME>@<JUMPBOX_HOST> "sudo git clone https://github.com/terrymandin/GHCP-ODAA-PromptMigration.git /home/zdmuser/GHCP-ODAA-PromptMigration"
```

```powershell
# 4. Verify
ssh -o BatchMode=yes -p 22 -i "<JUMPBOX_SSH_KEY>" <SSH_USERNAME>@<JUMPBOX_HOST> "ls /home/zdmuser/GHCP-ODAA-PromptMigration/.github"
```

- **PASS**: `.github` directory contents listed — confirm and continue.
- **FAIL**: Surface the error and stop. Do not proceed to Phase 1 until the clone is verified.

### Post-Creation: Create `zdmuser` and Transfer Ownership

Immediately after the clone is verified, create `zdmuser` and transfer ownership of `/home/zdmuser` via SSH from the **local PowerShell terminal**. This must happen in Step 1 so the Remote-SSH connection (configured next) can connect directly as `zdmuser` and open the repo it owns.

**Run each command separately and verify exit code 0 before proceeding:**

```powershell
# 1. Create the zdm group (idempotent)
ssh -o BatchMode=yes -p 22 -i "<JUMPBOX_SSH_KEY>" <SSH_USERNAME>@<JUMPBOX_HOST> "getent group zdm > /dev/null 2>&1 || sudo groupadd zdm"
```

```powershell
# 2. Create zdmuser account (idempotent; -M skips home dir creation since it already exists)
ssh -o BatchMode=yes -p 22 -i "<JUMPBOX_SSH_KEY>" <SSH_USERNAME>@<JUMPBOX_HOST> "getent passwd zdmuser > /dev/null 2>&1 || sudo useradd -g zdm -d /home/zdmuser -M zdmuser"
```

```powershell
# 3. Transfer ownership of /home/zdmuser to zdmuser
ssh -o BatchMode=yes -p 22 -i "<JUMPBOX_SSH_KEY>" <SSH_USERNAME>@<JUMPBOX_HOST> "sudo chown -R zdmuser:zdmuser /home/zdmuser"
```

```powershell
# 4. Create zdmuser's .ssh directory with correct permissions
ssh -o BatchMode=yes -p 22 -i "<JUMPBOX_SSH_KEY>" <SSH_USERNAME>@<JUMPBOX_HOST> "sudo mkdir -p /home/zdmuser/.ssh && sudo chmod 700 /home/zdmuser/.ssh && sudo chown zdmuser:zdmuser /home/zdmuser/.ssh"
```

```powershell
# 5. Install the SSH public key into zdmuser's authorized_keys
$pubKey = (Get-Content "<JUMPBOX_SSH_KEY>.pub" -Raw).Trim()
$sshCmd = "echo '$pubKey' | sudo tee /home/zdmuser/.ssh/authorized_keys > /dev/null && sudo chmod 600 /home/zdmuser/.ssh/authorized_keys && sudo chown zdmuser:zdmuser /home/zdmuser/.ssh/authorized_keys"
ssh -o BatchMode=yes -p 22 -i "<JUMPBOX_SSH_KEY>" <SSH_USERNAME>@<JUMPBOX_HOST> $sshCmd
```

```powershell
# 6. Verify: confirm ownership and that zdmuser can read the repo
ssh -o BatchMode=yes -p 22 -i "<JUMPBOX_SSH_KEY>" <SSH_USERNAME>@<JUMPBOX_HOST> "stat -c '%U %G' /home/zdmuser"
ssh -o BatchMode=yes -p 22 -i "<JUMPBOX_SSH_KEY>" <SSH_USERNAME>@<JUMPBOX_HOST> "sudo -u zdmuser ls /home/zdmuser/GHCP-ODAA-PromptMigration/.github"
```

- **PASS**: `stat` shows `zdmuser` as owner; `ls` lists the `.github` directory contents — confirm and continue.
- **FAIL**: Surface the error and stop. Do not proceed to Phase 1 until `zdmuser` exists, owns `/home/zdmuser`, and the SSH key is in place.

Proceed to Phase 1.

---

## Phase 1: Extension Check (S1-03, S1-10)

Check whether the Remote-SSH extension is installed by inspecting the VS Code extensions directory on disk. Do **not** invoke `code` or `code.cmd` as a subprocess — doing so opens unwanted VS Code windows in the background:

```powershell
$extInstalled = Test-Path "$env:USERPROFILE\.vscode\extensions\ms-vscode-remote.remote-ssh*"
```

**If `$extInstalled` is `$true`:** Confirm the extension is installed and continue to Phase 2.

**If `$extInstalled` is `$false` (extension not installed):** Stop and ask the user to install it using one of these methods:

- **Method A (UI):** Open the VS Code Extensions panel (`Ctrl+Shift+X`) → Search for **"Remote - SSH"** → Click **Install**.
- **Method B (command, run outside of Copilot agent execution):**
  ```powershell
  code --install-extension ms-vscode-remote.remote-ssh
  ```

Do not continue to Phase 2 until the user confirms the extension is installed.

---

## Phase 2: Collect Jumpbox Connection Variables

Collect or confirm the following values from the user before writing any configuration:

| Variable | Description | Default / Example |
|----------|-------------|-------------------|
| `JUMPBOX_HOST` | IP address or FQDN of the ZDM jumpbox | `10.0.0.5` or `zdm-jumpbox.example.com` |
| `JUMPBOX_PORT` | SSH port | `22` |
| `JUMPBOX_USER` | SSH login user (**must be `zdmuser`**) | `zdmuser` |
| `JUMPBOX_SSH_KEY` | Local path to the private key file | `$env:USERPROFILE\.ssh\zdm_jumpbox_key` |
| `JUMPBOX_ALIAS` | Host alias in `~/.ssh/config` | `zdm-jumpbox` |

**Validation rules:**
- `JUMPBOX_USER` **must** be `zdmuser`. If the user provides a different value, flag this and ask them to confirm — all subsequent steps depend on this user.
- Treat any value containing `<...>` as unset and prompt for it.
- Confirm all values with the user before proceeding.

---

## Phase 3: SSH Key Setup

### 3a. Check for existing key

Check whether the key file at `JUMPBOX_SSH_KEY` already exists:

```powershell
Test-Path "<JUMPBOX_SSH_KEY>"
```

- **If the file exists:** Confirm it is present, note the path, and continue to Phase 4. Do not regenerate.
- **If the file does not exist:** Offer to generate a new key pair (see 3b). Do not overwrite any existing file without explicit user confirmation.

> **Bootstrap guardrail:** Do not enter a bootstrap or key-copy workflow based on the user describing an alternative login path (e.g., _"I SSH as `azureuser` then `sudo su - zdmuser`"_). That describes the user's normal manual access pattern — it does not indicate that `zdmuser` lacks key-based SSH auth. If `JUMPBOX_SSH_KEY` is provided and the file exists, proceed directly to Phase 4 and then the connectivity test. Only offer bootstrap instructions (copy the public key to `zdmuser`'s `authorized_keys` via `azureuser`) if the connectivity test in Phase 5 fails with a key authentication error (e.g., `Permission denied (publickey)`).

### 3b. Generate new SSH key pair (if needed)

If generating a new key, first ensure the `.ssh\` directory exists and has correct permissions:

```powershell
if (-not (Test-Path "$env:USERPROFILE\.ssh")) {
    New-Item -ItemType Directory -Path "$env:USERPROFILE\.ssh" | Out-Null
}
icacls "$env:USERPROFILE\.ssh" /inheritance:r /grant:r "$env:USERNAME:(F)" | Out-Null
```

Then generate the key pair:

```powershell
ssh-keygen -t ed25519 -f "$env:USERPROFILE\.ssh\zdm_jumpbox_key" -C "zdmuser@zdm-jumpbox"
```

When prompted for a passphrase:
- For interactive use, a passphrase is recommended.
- For automation/non-interactive use, an empty passphrase is acceptable — confirm with the user.

After generation:
1. Confirm both files exist: `zdm_jumpbox_key` (private) and `zdm_jumpbox_key.pub` (public).
2. Set private key permissions:
   ```powershell
   icacls "$env:USERPROFILE\.ssh\zdm_jumpbox_key" /inheritance:r /grant:r "$env:USERNAME:(F)" | Out-Null
   ```
3. Display the public key content so the user can copy it to the jumpbox:
   ```powershell
   Get-Content "$env:USERPROFILE\.ssh\zdm_jumpbox_key.pub"
   ```

**User action required:** The user must manually copy the public key content to `~/.ssh/authorized_keys` on the jumpbox before the connectivity test in Phase 5 will succeed.

---

## Phase 4: SSH Config Entry

### 4a. Ensure `.ssh\` directory and config file exist

```powershell
if (-not (Test-Path "$env:USERPROFILE\.ssh")) {
    New-Item -ItemType Directory -Path "$env:USERPROFILE\.ssh" | Out-Null
    icacls "$env:USERPROFILE\.ssh" /inheritance:r /grant:r "$env:USERNAME:(F)" | Out-Null
}
if (-not (Test-Path "$env:USERPROFILE\.ssh\config")) {
    New-Item -ItemType File -Path "$env:USERPROFILE\.ssh\config" | Out-Null
}
```

### 4b. Check for existing host entry (idempotent)

Read the current config and search for the `Host <JUMPBOX_ALIAS>` block:

```powershell
$configContent = Get-Content "$env:USERPROFILE\.ssh\config" -Raw -ErrorAction SilentlyContinue
$configContent | Select-String -Pattern "Host\s+<JUMPBOX_ALIAS>"
```

Evaluate the result:

- **Entry absent:** Append the host block (see 4c). Do not modify any existing unrelated host blocks.
- **Entry present and matches collected values:** Confirm and do not modify.
- **Entry present but differs:** Show a field-by-field comparison of the existing vs. collected values and ask the user to confirm whether to update. Only modify when the user explicitly confirms.

### 4c. Write the SSH config host block

Append (or update) the following host block using file tools, substituting the collected values. Only the named `Host <JUMPBOX_ALIAS>` block is written or updated — never delete unrelated host entries:

```
Host <JUMPBOX_ALIAS>
    HostName <JUMPBOX_HOST>
    Port <JUMPBOX_PORT>
    User <JUMPBOX_USER>
    IdentityFile <JUMPBOX_SSH_KEY>
    ServerAliveInterval 60
    ServerAliveCountMax 10
```

---

## Phase 5: Connectivity Test

After the SSH config entry is written, run a connectivity test to verify the configuration. Capture stdout (remote hostname) and stderr (error text) separately using a temporary file so each can be reported independently (S1-14):

```powershell
$errFile = [System.IO.Path]::GetTempFileName()
$remoteHostname = & ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes `
    -p <JUMPBOX_PORT> -i "<JUMPBOX_SSH_KEY>" `
    <JUMPBOX_USER>@<JUMPBOX_HOST> hostname 2>$errFile
$exitCode = $LASTEXITCODE
$errText = if (Test-Path $errFile) { (Get-Content $errFile -Raw).Trim() } else { '' }
Remove-Item $errFile -ErrorAction SilentlyContinue
```

- **PASS** (`$exitCode -eq 0`): `$remoteHostname` contains the remote hostname. Record both the command and the returned hostname.
- **FAIL** (`$exitCode -ne 0`): `$errText` contains the error output. Common causes:
  - Public key not yet added to jumpbox `authorized_keys` — user must complete the authorized_keys step first.
  - Incorrect host, port, or key path — verify values and retry.
  - Host unreachable — check network/VPN connectivity.

**Display the connectivity test result inline** (PASS or FAIL with detail) before writing the report.

If the test fails, the user may choose to:
1. Fix the issue and re-run this step.
2. Proceed and have the report written with status `ACTION REQUIRED`.

---

## Phase 6: Write Setup Report

### 6a. Write the setup report

Write `Artifacts/Phase10-Migration/Step1/remote-ssh-setup-report.md` using file tools. Create the directory if absent.

Use this exact format, substituting actual values:

```markdown
# Remote-SSH Setup Report
Generated: <ISO-8601 timestamp>

## Extension
- Status: Installed
- Extension ID: ms-vscode-remote.remote-ssh

## SSH Key
- Key path: <JUMPBOX_SSH_KEY>
- Mode: existing / generated
- Public key location: <JUMPBOX_SSH_KEY>.pub

## SSH Config Entry
- Config file: $env:USERPROFILE\.ssh\config
- Host alias: <JUMPBOX_ALIAS>
- HostName: <JUMPBOX_HOST>
- Port: <JUMPBOX_PORT>
- User: <JUMPBOX_USER>
- IdentityFile: <JUMPBOX_SSH_KEY>

## Connectivity Test
- Command: ssh -o BatchMode=yes -p <JUMPBOX_PORT> -i "<JUMPBOX_SSH_KEY>" <JUMPBOX_USER>@<JUMPBOX_HOST> hostname
- Result: PASS / FAIL
- Remote hostname: <hostname returned> (on PASS)
- Error: <error text> (on FAIL)

## Repo Clone
- Location: /home/zdmuser/GHCP-ODAA-PromptMigration
- Result: CLONED / SKIPPED (already present) / FAILED
- Verified: .github directory present (YES / NO)

## zdmuser Setup
- Group (zdm): CREATED / ALREADY EXISTS
- Account (zdmuser): CREATED / ALREADY EXISTS
- /home/zdmuser owner: zdmuser (CONFIRMED / FAILED)
- .ssh/authorized_keys: INSTALLED / FAILED

## Status
READY / ACTION REQUIRED

## Remaining Actions (when ACTION REQUIRED)
- <list any steps the user must complete manually>

## Next Step
Run Step 2 (Install ZDM) in the Remote-SSH VS Code session connected to <JUMPBOX_ALIAS> as zdmuser.
```

Set `Status` to:
- **READY** — extension installed, SSH config entry present, connectivity test passed, and repo cloned.
- **ACTION REQUIRED** — any required item is incomplete; list each outstanding item under "Remaining Actions".

### 6b. Write the Step 1 output directory README

Also write `Artifacts/Phase10-Migration/Step1/README.md` using file tools:

```markdown
# Step 1 — Remote-SSH Setup Outputs

This directory contains artifacts generated by Step 1 of the ZDM Phase 10 migration workflow.

## Files

| File | Description |
|------|-------------|
| `remote-ssh-setup-report.md` | Remote-SSH setup status report (extension, SSH key, config entry, connectivity test result) |
| `README.md` | This file |

## Runtime Outputs

Step 1 runs entirely in the local VS Code terminal (Windows PowerShell). The only output file written is `remote-ssh-setup-report.md` in this directory. No scripts are executed on the jumpbox during this step.

## Success Signals

- `remote-ssh-setup-report.md` exists in this directory with `## Status` set to `READY`.
- The SSH connectivity test recorded in the report shows `Result: PASS`.

## Failure Signals

- Status is `ACTION REQUIRED` — review the `## Remaining Actions` section in the report for outstanding manual steps.
- Connectivity test shows `Result: FAIL` — verify host/port/key values and confirm the public key is present in `zdmuser`'s `authorized_keys` on the jumpbox.

## Next Actions

When status is READY, open a Remote-SSH session to the configured jumpbox and run `@Phase10-Step2-Install-ZDM`.
```

---

## Phase 7: User Handoff Instructions

> **Copilot cannot establish the Remote-SSH connection automatically. This step requires user interaction.**

Guide the user to open a Remote-SSH session:

1. Open the VS Code Command Palette:
   - Windows: `Ctrl+Shift+P`
   - macOS: `Cmd+Shift+P`
2. Type: **`Remote-SSH: Connect to Host`**
3. Select: **`<JUMPBOX_ALIAS>`** from the list (e.g. `zdm-jumpbox`).
4. VS Code will open a new window connected to the jumpbox. The integrated terminal in that window runs as `zdmuser`.
5. In the new window, open the repo folder on the jumpbox (clone it there first if not already done).
6. Open a new Copilot Chat panel and type `@Phase10-ZDM-Orchestrator`.

If the alias does not appear in the list, verify that the SSH config entry was written to `$env:USERPROFILE\.ssh\config` and that the Remote-SSH extension is installed.

> **Important — session continuity:** The Copilot chat session in this local VS Code window does **not** carry over to the Remote-SSH window. Each VS Code window has its own independent chat context. This is by design — the orchestrator uses artifact files on disk (not the chat session) to track migration state. However, because `Artifacts/Phase10-Migration/Step1/remote-ssh-setup-report.md` is git-ignored, it will not be present in the jumpbox repo clone. The orchestrator handles this automatically: when it detects it is running on Linux (Remote-SSH context), it infers Step 1 is complete without needing the report file. You do not need to copy or commit any files between the two sessions.

**After delivering these handoff instructions, explicitly ask the user to confirm:**

> _"Please confirm you have successfully opened the Remote-SSH VS Code window and that your integrated terminal prompt shows `zdmuser@<hostname>`. Reply with the hostname shown when you are ready to proceed to Step 4."_

- Do **not** declare Step 1 complete or suggest running Step 4 until the user provides this confirmation.
- If the user cannot connect, remain in Step 1 and help troubleshoot the connection issue before proceeding.

---

## Success Criteria

Step 1 is complete when all of the following are true:

1. The `ms-vscode-remote.remote-ssh` extension is confirmed installed in the local VS Code session.
2. The SSH host entry for `<JUMPBOX_ALIAS>` is present in `$env:USERPROFILE\.ssh\config` with the correct field values.
3. The SSH connectivity test has passed (exit code 0 and remote hostname returned), **or** the user has acknowledged a known failure and chosen to proceed with status `ACTION REQUIRED`.
4. `Artifacts/Phase10-Migration/Step1/remote-ssh-setup-report.md` is written with status `READY` or `ACTION REQUIRED`.
5. The user has been given clear instructions for connecting via Remote-SSH.
6. **The user has explicitly confirmed** that they have successfully opened a Remote-SSH VS Code window connected to `<JUMPBOX_ALIAS>` and that their integrated terminal prompt shows `zdmuser@<hostname>`.

---

## Output Files

All outputs are written to `Artifacts/Phase10-Migration/Step1/` which is git-ignored. No files are committed or create PRs.

| File | Description |
|------|-------------|
| `Artifacts/Phase10-Migration/Step1/remote-ssh-setup-report.md` | Setup status report — consumed by subsequent steps as pre-populated bypass input |
| `Artifacts/Phase10-Migration/Step1/README.md` | Step 1 output directory index |

---

## Next Step

After Step 1 completes and you have connected to the jumpbox via Remote-SSH:

> Run **`@Phase10-Step2-Install-ZDM`** in the Remote-SSH VS Code session connected to **`<JUMPBOX_ALIAS>`** as **`zdmuser`**.
