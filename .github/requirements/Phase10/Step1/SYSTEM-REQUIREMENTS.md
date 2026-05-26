# Step1 System Requirements - Create VM + Remote-SSH Setup Implementation

## Scope

This file defines implementation-level constraints for the Step 1 setup step. Step1 runs in the LOCAL VS Code terminal (PowerShell on Windows). Azure VM creation and SSH configuration both run locally. No Remote-SSH session is active during this step.

## S1-09A-0: Jumpbox admin auth mode

All jumpbox admin SSH interactions in Step1 must support both modes:

- `JUMPBOX_AUTH_MODE=ssh-key`:
   - `ssh -o BatchMode=yes -p 22 -i "<JUMPBOX_SSH_KEY>" <SSH_USERNAME>@<JUMPBOX_HOST> "<cmd>"`
- `JUMPBOX_AUTH_MODE=password`:
   - `ssh -p 22 <SSH_USERNAME>@<JUMPBOX_HOST> "<cmd>"`

For password mode, omit `-i` and omit `BatchMode=yes` so the terminal can prompt for password interactively.

Execution consistency requirement:
- Resolve `JUMPBOX_AUTH_MODE` once per Step1 run and lock that choice for all subsequent jumpbox admin SSH commands.
- Render and run only the selected mode's command variant in that run.
- Do not present or execute mixed key/password variants in the same run.
- When `JUMPBOX_AUTH_MODE=password`, do not run `authorized_keys` installation steps; instead, require interactive `zdmuser` password setup before the Phase 5 connectivity test.

## S1-09A: Azure VM Creation Implementation

This section applies only when the user confirms they want a new VM created (S1-00-B).

### S1-09A-1: Parameter Validation

Before running any `az` command, validate:
- Resource group name: not empty, no spaces
- VM name: alphanumeric, hyphens allowed, 1–15 chars for compatibility
- Region: non-empty string
- OS disk size: integer ≥ 30
- Authentication type: `ssh` or `password`; if `ssh`, public key must be non-empty

### S1-09A-2: VNet/Subnet Pre-check

If the user specifies a new VNet/subnet, run these first in the local PowerShell terminal:

```powershell
az network vnet create `
  --resource-group "<RESOURCE_GROUP>" `
  --name "<VNET_NAME>" `
  --location "<REGION>" `
  --address-prefix "10.0.0.0/16"

az network vnet subnet create `
  --resource-group "<RESOURCE_GROUP>" `
  --vnet-name "<VNET_NAME>" `
  --name "<SUBNET_NAME>" `
  --address-prefix "10.0.0.0/24"
```

### S1-09A-3: VM Creation Command

Use a **two-step confirmation flow**:

**Step 1 — Parameter confirmation:** Display a summary of all collected parameter values and ask the user to confirm they are correct. Do not generate or display the `az vm create` command at this stage.

**Step 2 — Command display and execution confirmation:** After the user confirms the parameters, build the full `az vm create` command and display it in a fenced code block. Then ask:

> "Shall I run this command now? (Yes / No)"

Run the command in the local PowerShell terminal **only** after the user replies Yes. If the user replies No, ask what they would like to change.

**Command template (SSH public key auth):**

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
  --output json
```

**For password authentication:** replace `--ssh-key-values "<SSH_PUBLIC_KEY>"` with `--admin-password "<PASSWORD>"` and add `--authentication-type password`.

**Defaults to substitute when the user accepts the recommendation:**
- `--image`: `Oracle:Oracle-Linux:ol10-lvm-gen2:latest`
- `--size`: `Standard_D2s_v3`
- `--os-disk-size-gb`: `256`
- `--admin-username`: `azureuser`
- `--public-ip-sku`: `Standard` (always include)

### S1-09A-4: Output Capture

Extract from the JSON output:
- `publicIpAddress` — record as `JUMPBOX_HOST` for use in S1-04 (variable collection)
- `powerState` — must be `VM running` before proceeding

### S1-09A-5: Post-Creation Package Installation

Immediately after extracting `JUMPBOX_HOST`, install `tar` on the new VM over SSH. VS Code Server requires `tar` to extract its installation archive — without it, the Remote-SSH connection will fail with "Failed to install the VS Code Server."

Build one admin SSH command prefix for the selected `JUMPBOX_AUTH_MODE` and use only that variant for this Step1 run:

- key mode: `JUMPBOX_ADMIN_SSH_CMD = ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes -p 22 -i "<JUMPBOX_SSH_KEY>" <SSH_USERNAME>@<JUMPBOX_HOST>`
- password mode: `JUMPBOX_ADMIN_SSH_CMD = ssh -o StrictHostKeyChecking=accept-new -p 22 <SSH_USERNAME>@<JUMPBOX_HOST>`

Run this command in the local PowerShell terminal:

```powershell
<JUMPBOX_ADMIN_SSH_CMD> "sudo dnf install -y tar"
```

- Capture `$LASTEXITCODE`. If non-zero, surface the SSH error and do not proceed until resolved.
- Confirm output contains `Complete!` before continuing.
- Do **not** skip this step even if the user believes `tar` may already be installed — Oracle Linux 10 minimal images omit `tar` by default.

### S1-09A-6: Clone Migration Repo onto the Jumpbox

Immediately after `tar` is confirmed installed, clone the migration repo into `/home/zdmuser` on the jumpbox via SSH from the local PowerShell terminal. Run each command separately and check `$LASTEXITCODE` after each.

**Step 1 — Install git:**
```powershell
<JUMPBOX_ADMIN_SSH_CMD> "sudo dnf install -y git"
```
Check exit code 0. `git` may already be present on some images — a `Nothing to do. Complete!` response is also acceptable.

**Step 2 — Create /home/zdmuser directory:**
```powershell
<JUMPBOX_ADMIN_SSH_CMD> "sudo mkdir -p /home/zdmuser"
```

**Step 3 — Clone the repo:**
```powershell
<JUMPBOX_ADMIN_SSH_CMD> "sudo git clone https://github.com/terrymandin/GHCP-ODAA-PromptMigration.git /home/zdmuser/GHCP-ODAA-PromptMigration"
```
If the directory already exists and is non-empty, skip the clone and confirm existing contents.

**Step 4 — Verify clone:**
```powershell
<JUMPBOX_ADMIN_SSH_CMD> "ls /home/zdmuser/GHCP-ODAA-PromptMigration/.github"
```
Expect output listing the `.github` directory contents. Non-zero exit or empty output = failure.

**Ownership:** The cloned directory will be owned by `root`. Proceed immediately to S1-09A-7 to create `zdmuser` and transfer ownership before proceeding to any SSH configuration steps.

### S1-09A-7: Create `zdmuser` and Transfer Ownership

Immediately after the repo clone is verified, perform the following steps via SSH from the local PowerShell terminal. Each command must exit with code 0 before proceeding to the next.

**Step 1 — Create `zdm` group (idempotent):**
```powershell
<JUMPBOX_ADMIN_SSH_CMD> "getent group zdm > /dev/null 2>&1 || sudo groupadd zdm"
```

**Step 2 — Create `zdmuser` account (idempotent, using existing `/home/zdmuser` dir):**
```powershell
<JUMPBOX_ADMIN_SSH_CMD> "getent passwd zdmuser > /dev/null 2>&1 || sudo useradd -g zdm -d /home/zdmuser -M zdmuser"
```
The `-M` flag prevents `useradd` from attempting to create the home directory (it already exists).

**Step 3 — Transfer ownership of `/home/zdmuser` to `zdmuser`:**
```powershell
<JUMPBOX_ADMIN_SSH_CMD> "sudo chown -R zdmuser:zdm /home/zdmuser"
```

**Step 4 — Set up `zdmuser` credentials based on mode:**

If key mode:
```powershell
<JUMPBOX_ADMIN_SSH_CMD> "sudo mkdir -p /home/zdmuser/.ssh && sudo chmod 700 /home/zdmuser/.ssh && sudo chown zdmuser:zdm /home/zdmuser/.ssh"
```

**Step 5 — Install the SSH public key for `zdmuser` (key mode):**

Read the public key locally and write it to `authorized_keys` on the jumpbox. The key file is `<JUMPBOX_SSH_KEY>.pub` (the `.pub` counterpart of the private key used in this step).

```powershell
$pubKey = (Get-Content "<JUMPBOX_SSH_KEY>.pub" -Raw).Trim()
$sshCmd = "echo '$pubKey' | sudo tee /home/zdmuser/.ssh/authorized_keys > /dev/null && sudo chmod 600 /home/zdmuser/.ssh/authorized_keys && sudo chown zdmuser:zdm /home/zdmuser/.ssh/authorized_keys"
<JUMPBOX_ADMIN_SSH_CMD> $sshCmd
```

If password mode:
```powershell
<JUMPBOX_ADMIN_SSH_CMD> "sudo passwd zdmuser"
```
Complete the interactive prompt and confirm password update succeeded.

**Step 6 — Verify ownership and access:**
```powershell
# Confirm ownership
<JUMPBOX_ADMIN_SSH_CMD> "stat -c '%U %G' /home/zdmuser"
# Confirm zdmuser can read the repo
<JUMPBOX_ADMIN_SSH_CMD> "sudo -u zdmuser ls /home/zdmuser/GHCP-ODAA-PromptMigration/.github"
```
Expected outputs:
- `stat`: `zdmuser zdm`
- `ls`: lists `.github` directory contents

If any step exits non-zero, surface the error and stop. Do not proceed to S1-09A-8 until `zdmuser` exists, owns `/home/zdmuser`, and the selected credential bootstrap is complete.

### S1-09A-8: Install ZDM Prerequisites and Create `/u01` Directory Structure

While still connected as the admin SSH user (e.g., `azureuser`), install the ZDM prerequisite packages and create the ZDM installation directories. Doing this now (as admin with `sudo`) means `zdmuser` will never need `sudo` in the Remote-SSH session — it already owns the directories it needs.

**Step 1 — Install prerequisite packages:**
```powershell
<JUMPBOX_ADMIN_SSH_CMD> "sudo dnf install -y expect glibc-devel libnsl ncurses-compat-libs libaio unzip perl wget"
```
Confirm exit code 0 and that output contains `Complete!` or `Nothing to do.` (packages already installed). If any package fails, surface the error and do not continue.

**Step 2 — Create ZDM installation directories:**
```powershell
<JUMPBOX_ADMIN_SSH_CMD> "sudo mkdir -p /u01/app/zdmhome /u01/app/zdmbase /u01/app/zdm_download"
```

**Step 3 — Set ownership so `zdmuser` owns the directories:**
```powershell
<JUMPBOX_ADMIN_SSH_CMD> "sudo chown -R zdmuser:zdm /u01/app/zdmhome /u01/app/zdmbase /u01/app/zdm_download"
```

**Step 4 — Verify:**
```powershell
<JUMPBOX_ADMIN_SSH_CMD> "stat -c '%U %G %n' /u01/app/zdmhome /u01/app/zdmbase /u01/app/zdm_download"
```
Expected: each line shows `zdmuser zdm <path>`.

## S1-09B: MCP-backed Azure control plane implementation

When MCP servers are available in the execution environment, implement Azure control-plane actions in this order:

Implementation runtime reference: Microsoft Azure MCP Server (`@azure/mcp`) started with `npx -y @azure/mcp@latest server start`.
For reduced tool count and faster startup in this scenario, prefer namespace scoping: `--mode namespace --namespace compute --namespace network --namespace monitor`.

1. Resolve subscription context using `mcp_azure_mcp_subscription_list` before any VM lookup/create call.
2. Query existing VM resources with `mcp_azure_mcp_compute` to avoid duplicate `az vm create` calls.
3. Execute VM creation with `mcp_azure_mcp_compute` after the user confirms parameters per S1-09A-3.
4. Use MCP query/read responses to extract public IP and running state (`JUMPBOX_HOST`, power state).
5. If MCP calls fail or do not support a required field, continue with the existing `az` command templates from S1-09A-2 and S1-09A-3.

MCP or CLI path must produce the same downstream variables and report fields.

---

## S1-10: Extension check implementation

1. Check for the Remote-SSH extension by testing for its directory in the VS Code extensions folder using `Test-Path`. Do **not** invoke `code` or `code.cmd` as a subprocess — doing so opens unwanted VS Code windows in the background:

   ```powershell
   $extInstalled = Test-Path "$env:USERPROFILE\.vscode\extensions\ms-vscode-remote.remote-ssh*"
   ```

2. If `$extInstalled` is `$true`, log the result as installed and continue.
3. If `$false`, surface the install instructions from S1-03. Do not continue the setup workflow until the user confirms the extension is installed and re-runs or continues.

## S1-11: SSH config file path (Windows)

1. The SSH config file path on Windows is: `$env:USERPROFILE\.ssh\config`
2. The `.ssh\` directory may not exist. If absent, create it before writing the config:

   ```powershell
   if (-not (Test-Path "$env:USERPROFILE\.ssh")) {
       New-Item -ItemType Directory -Path "$env:USERPROFILE\.ssh" | Out-Null
   }
   ```

3. Set directory permissions so only the current user has access:

   ```powershell
   icacls "$env:USERPROFILE\.ssh" /inheritance:r /grant:r "$env:USERNAME:(F)" | Out-Null
   ```

4. On macOS/Linux: use `~/.ssh/config` with `chmod 600 ~/.ssh/config` and `chmod 700 ~/.ssh/`.

## S1-12: Idempotent host entry detection

1. Read the existing `~/.ssh/config` file using `Get-Content` if it exists.
2. Search for a `Host <JUMPBOX_ALIAS>` block using a pattern match.
3. If found, parse the existing block and compare field-by-field with the collected values.
4. Report whether the existing entry matches, partially matches, or is absent.
5. Only modify the file when the user explicitly confirms an update.
6. Never delete existing unrelated host blocks — append new entries or update only the named block.

## S1-13: SSH key generation command

When generating a new key pair (S1-05), use the following command:

```powershell
ssh-keygen -t ed25519 -f "$env:USERPROFILE\.ssh\zdm_jumpbox_key" -C "zdmuser@zdm-jumpbox"
```

After generation:

1. Confirm both `zdm_jumpbox_key` (private) and `zdm_jumpbox_key.pub` (public) exist.
2. Set private key permissions (Windows):

   ```powershell
   icacls "$env:USERPROFILE\.ssh\zdm_jumpbox_key" /inheritance:r /grant:r "$env:USERNAME:(F)" | Out-Null
   ```

3. Display the public key content using `Get-Content "$env:USERPROFILE\.ssh\zdm_jumpbox_key.pub"` so the user can copy it to the jumpbox.

## S1-14: SSH connectivity test

The connectivity verification test (S1-06 point 5) must match `JUMPBOX_AUTH_MODE`:

```powershell
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes `
    -p <JUMPBOX_PORT> -i "<JUMPBOX_SSH_KEY>" `
    <JUMPBOX_USER>@<JUMPBOX_HOST> hostname
```

```powershell
ssh -o StrictHostKeyChecking=accept-new `
   -p <JUMPBOX_PORT> `
   <JUMPBOX_USER>@<JUMPBOX_HOST> hostname
```

- In key mode, `BatchMode=yes` prevents password prompts and makes key-auth failures explicit.
- In password mode, do not use `BatchMode=yes`; allow interactive password entry.
- `StrictHostKeyChecking=accept-new` adds the host to `known_hosts` on first connection without prompting, but will fail if the key changes.
- Capture the exit code: `$LASTEXITCODE`. Non-zero = FAIL.
- Capture stdout (remote hostname) and stderr (error message) separately using redirection.

## S1-15: Report write specification

Write `Artifacts/Phase10-Migration/Step1/remote-ssh-setup-report.md` using file tools after the connectivity test completes. File format:

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

## Jumpbox Auth
- Mode: ssh-key / password
- Credential handling: key path / interactive password

## SSH Config Entry
- Config file: <config path>
- Host alias: <JUMPBOX_ALIAS>
- HostName: <JUMPBOX_HOST>
- Port: <JUMPBOX_PORT>
- User: <JUMPBOX_USER>
- IdentityFile: <JUMPBOX_SSH_KEY>

## Connectivity Test
- Command: ssh -o BatchMode=yes -p <PORT> -i "<KEY>" <USER>@<HOST> hostname
- Result: PASS / FAIL
- Remote hostname: <hostname returned> (on PASS)
- Error: <error text> (on FAIL)

## Repo Clone
- Location: /home/zdmuser/GHCP-ODAA-PromptMigration
- Result: CLONED / SKIPPED (already present) / FAILED
- Verified: .github directory present (YES / NO)

## Status
READY / ACTION REQUIRED

## Remaining Actions (when ACTION REQUIRED)
- <list any steps user must complete manually>

## Remaining Actions for Step 2
- Run: sudo chown -R zdmuser:zdmuser /home/zdmuser  (after zdmuser account is created)

## Next Step
Run Step 2 (Install ZDM) in the Remote-SSH VS Code session connected to <JUMPBOX_ALIAS> as <SSH_USERNAME>.
```

## S1-16: Local execution constraints

1. All commands run in the LOCAL PowerShell terminal — do not use any Remote-SSH or jumpbox commands.
2. Do not use `sudo`, `bash`, or Unix shell commands natively on Windows. Use PowerShell equivalents.
3. File path separators use `\` on Windows. When passing paths to `ssh` or `ssh-keygen` (which are OpenSSH tools), use forward slashes (`/`) in `-i` argument values or quote paths with backslashes.
4. Step1 runs commands on the remote jumpbox only via `ssh` from the local terminal (package installation and repo clone). It does not open a Remote-SSH session or modify jumpbox files via VS Code file tools.
5. Step1 must not produce any artifacts in `Artifacts/Phase10-Migration/Step6/` or later directories — only `Step1/`.
