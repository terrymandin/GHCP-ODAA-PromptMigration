---
mode: agent
description: ZDM Step 1 - Setup Remote-SSH connection to the ZDM jumpbox (runs in local VS Code session)
---
# ZDM Migration Step 1: Setup Remote-SSH Connection

## Purpose

Configure the Remote-SSH extension, SSH key, and jumpbox host entry so that subsequent steps (Step 2 onward) can run in the correct Remote-SSH terminal context as `zdmuser`.

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

## Status
READY / ACTION REQUIRED

## Remaining Actions (when ACTION REQUIRED)
- <list any steps the user must complete manually>

## Next Step
Run Step 2 (Configure SSH Connectivity) in the Remote-SSH VS Code session connected to <JUMPBOX_ALIAS> as zdmuser.
```

Set `Status` to:
- **READY** — extension installed, SSH config entry present, and connectivity test passed.
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

When status is READY, open a Remote-SSH session to the configured jumpbox and run `@Phase10-Step2-Configure-SSH-Connectivity`.
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

> _"Please confirm you have successfully opened the Remote-SSH VS Code window and that your integrated terminal prompt shows `zdmuser@<hostname>`. Reply with the hostname shown when you are ready to proceed to Step 2."_

- Do **not** declare Step 1 complete or suggest running Step 2 until the user provides this confirmation.
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

> Run **`@Phase10-Step2-Configure-SSH-Connectivity`** in the Remote-SSH VS Code session connected to **`<JUMPBOX_ALIAS>`** as **`zdmuser`**.
