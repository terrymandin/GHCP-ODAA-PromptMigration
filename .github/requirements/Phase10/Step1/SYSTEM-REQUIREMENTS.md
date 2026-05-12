# Step1 System Requirements - Create VM + Remote-SSH Setup Implementation

## Scope

This file defines implementation-level constraints for the Step 1 setup step. Step1 runs in the LOCAL VS Code terminal (PowerShell on Windows). Azure VM creation and SSH configuration both run locally. No Remote-SSH session is active during this step.

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

Run this command in the local PowerShell terminal, substituting the admin username and private key path that were used for VM creation:

```powershell
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes -p 22 -i "<JUMPBOX_SSH_KEY>" <SSH_USERNAME>@<JUMPBOX_HOST> "sudo dnf install -y tar"
```

- Capture `$LASTEXITCODE`. If non-zero, surface the SSH error and do not proceed until resolved.
- Confirm output contains `Complete!` before continuing.
- Do **not** skip this step even if the user believes `tar` may already be installed — Oracle Linux 10 minimal images omit `tar` by default.

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

The connectivity verification test (S1-06 point 5) uses these options to avoid interactive prompts:

```powershell
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes `
    -p <JUMPBOX_PORT> -i "<JUMPBOX_SSH_KEY>" `
    <JUMPBOX_USER>@<JUMPBOX_HOST> hostname
```

- `BatchMode=yes` prevents password prompts and makes key-auth failures explicit.
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

## Status
READY / ACTION REQUIRED

## Remaining Actions (when ACTION REQUIRED)
- <list any steps user must complete manually>

## Next Step
Run Step4 (Configure SSH Connectivity) in the Remote-SSH VS Code session connected to <JUMPBOX_ALIAS> as zdmuser.
```

## S1-16: Local execution constraints

1. All commands run in the LOCAL PowerShell terminal — do not use any Remote-SSH or jumpbox commands.
2. Do not use `sudo`, `bash`, or Unix shell commands natively on Windows. Use PowerShell equivalents.
3. File path separators use `\` on Windows. When passing paths to `ssh` or `ssh-keygen` (which are OpenSSH tools), use forward slashes (`/`) in `-i` argument values or quote paths with backslashes.
4. Step1 must not read, modify, or create any files on the remote jumpbox.
5. Step1 must not produce any artifacts in `Artifacts/Phase10-Migration/Step6/` or later directories — only `Step1/`.
