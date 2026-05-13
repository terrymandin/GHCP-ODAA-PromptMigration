# Step1 User Requirements - Create VM + Setup Remote-SSH Connection

## Objective

Ensure the ZDM Azure VM exists (creating it if needed), then configure a Remote-SSH connection from the local VS Code session to the jumpbox so that subsequent steps (Step4 onward) run in the correct Remote-SSH terminal context as `zdmuser`.

**Execution model exception**: Step1 runs entirely in the LOCAL VS Code session (local terminal), not via Remote-SSH. Azure VM creation (`az vm create`) and SSH setup both run locally. The Remote-SSH extension must be installed and the connection must be set up before any Remote-SSH session can begin.

## S1-01: Output contract

Step1 writes one artifact using file tools after setup completes:

- `Artifacts/Phase10-Migration/Step1/remote-ssh-setup-report.md`

The report must contain:

1. Extension check result (installed / not installed, with version when available).
2. SSH key location and mode (existing key used vs. new key generated).
3. The host alias added or confirmed in `~/.ssh/config`.
4. Connection command the user can run to manually verify: `ssh zdmuser@<jumpbox-alias>`.
5. Final status: READY or ACTION REQUIRED, with remaining manual actions listed.

## S1-00: ZDM VM Readiness Check

Before any SSH or extension setup, confirm the ZDM jumpbox VM exists.

### S1-00-A: Initial Question

Ask the user:

> **Is the Azure VM for the ZDM jumpbox already created and running?**

- If **yes** — ask for the VM's IP address or FQDN and record it as `JUMPBOX_HOST`. Proceed to S1-02.
- If **no** — ask if they would like assistance creating the VM (S1-00-B).

### S1-00-B: VM Creation Offer

If the VM does not exist, offer to create it:

> **Would you like help creating the Azure VM for ZDM?**

- If **no** — display the recommended configuration (see S1-00-C defaults), wait for the user to confirm the VM is ready, then continue to S1-02.
- If **yes** — collect VM parameters interactively (S1-00-C) and create the VM.

### S1-00-C: VM Parameter Collection

Collect the following parameters **one at a time**, presenting the recommended default for each. Ask each question separately and wait for the user's answer before proceeding to the next.

| Parameter | Question to Ask | Recommended Default |
|-----------|-----------------|---------------------|
| VM Name | "What name would you like for the ZDM jumpbox VM?" | `zdm-jumpbox` |
| Resource Group | "Which Azure resource group should the VM be placed in? Enter an existing name or a new name to create." | *(ask user)* |
| Azure Region | "Which Azure region should the VM be deployed to? (e.g., `eastus`, `westus2`)" | *(ask user)* |
| Image | "Which OS image? Press Enter to accept the recommended Oracle Linux 10 image." | `Oracle:Oracle-Linux:ol10-lvm-gen2:latest` |
| VM Size | "Which VM size? Press Enter to accept the recommended size." | `Standard_D2s_v3` |
| OS Disk Size (GB) | "What size (in GB) should the OS disk be? Press Enter to accept the recommended size." | `256` |
| VNet / Subnet | "Which VNet and subnet should the VM use? Enter existing names or new names to create them." | *(ask user)* |
| Authentication Type | "Would you like to authenticate with an SSH public key (recommended) or a password?" | SSH public key |
| SSH Public Key / Password | "Please paste your SSH public key (or enter a password if you chose password auth above)." | *(ask user)* |
| SSH Username | "What admin username should be used for SSH login on the VM?" | `azureuser` |

Display a full summary of all collected values and require explicit user confirmation before creating the VM.

### S1-00-D: VM Creation

Use a **two-step confirmation flow** — parameter review first, then command execution:

**Step 1 — Confirm parameters:** Display a summary of all collected parameter values and ask the user to confirm they are correct ("Are these parameters correct? Yes / No"). Do not build or show the command yet.

**Step 2 — Show command and ask to run:** After the user confirms the parameters, build the full `az vm create` command and **display it in a fenced code block**. Ask the user explicitly: "Shall I run this command now? (Yes / No)". Run the command in the local PowerShell terminal **only** after the user replies Yes. If the user replies No, ask what they would like to change and return to Step 1.

If a new VNet/subnet is required, display the `az network vnet create` and `az network vnet subnet create` commands alongside the VM creation command (in the Step 2 display), and run them first — each with its own "Shall I run this?" confirmation.

After successful creation, extract and display the public IP address from the command output and record it as `JUMPBOX_HOST`.

### S1-00-E: Post-Creation Prerequisites

Immediately after VM creation succeeds, install the packages required for VS Code Server to function on the jumpbox. Run the following over SSH using the VM's admin user (`azureuser`) and the provided private key:

```powershell
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes -p 22 -i "<JUMPBOX_SSH_KEY>" <SSH_USERNAME>@<JUMPBOX_HOST> "sudo dnf install -y tar"
```

Confirm the command exits with code 0 and reports `Complete!`. If it fails, surface the error and do not proceed until `tar` is installed — VS Code Server cannot extract its installation package without it.

After confirming `tar` is installed, continue to S1-00-F.

### S1-00-F: Clone Migration Repo onto the Jumpbox

Immediately after the `tar` installation succeeds, clone the migration repo into the jumpbox's `/home/zdmuser` directory over SSH. This must be done before the user opens the Remote-SSH VS Code window so the repo is available the moment Step 2 begins.

**Steps to execute (all run via SSH from the local terminal):**

1. Install `git` if not already present:
   ```powershell
   ssh ... "sudo dnf install -y git"
   ```
2. Create the `/home/zdmuser` directory:
   ```powershell
   ssh ... "sudo mkdir -p /home/zdmuser"
   ```
3. Clone the repo into it:
   ```powershell
   ssh ... "sudo git clone https://github.com/terrymandin/GHCP-ODAA-PromptMigration.git /home/zdmuser/GHCP-ODAA-PromptMigration"
   ```
4. Confirm the clone succeeded by checking that the directory exists:
   ```powershell
   ssh ... "ls /home/zdmuser/GHCP-ODAA-PromptMigration/.github"
   ```

If the clone fails (e.g. `git` not found, network error), surface the error and do not proceed until it is resolved.

After confirming the clone is present, continue to S1-00-G.

### S1-00-G: Create `zdmuser` and Transfer Ownership

Immediately after the clone is verified, create the `zdmuser` OS account and transfer ownership of `/home/zdmuser` — all via SSH from the local PowerShell terminal. This must happen in Step 1 so that the VS Code Remote-SSH connection (configured below) can connect directly as `zdmuser` and open the repo.

**Steps to execute (run via SSH from the local terminal, each separately with exit-code check):**

1. Create the `zdm` group and `zdmuser` account:
   ```powershell
   ssh -o BatchMode=yes -p 22 -i "<JUMPBOX_SSH_KEY>" <SSH_USERNAME>@<JUMPBOX_HOST> "getent group zdm > /dev/null 2>&1 || sudo groupadd zdm"
   ssh -o BatchMode=yes -p 22 -i "<JUMPBOX_SSH_KEY>" <SSH_USERNAME>@<JUMPBOX_HOST> "getent passwd zdmuser > /dev/null 2>&1 || sudo useradd -g zdm -d /home/zdmuser -M zdmuser"
   ```

2. Transfer ownership of `/home/zdmuser` to `zdmuser`:
   ```powershell
   ssh -o BatchMode=yes -p 22 -i "<JUMPBOX_SSH_KEY>" <SSH_USERNAME>@<JUMPBOX_HOST> "sudo chown -R zdmuser:zdmuser /home/zdmuser"
   ```

3. Create `zdmuser`'s `.ssh` directory and `authorized_keys` file with the SSH public key used in this step, then lock down permissions:
   ```powershell
   ssh -o BatchMode=yes -p 22 -i "<JUMPBOX_SSH_KEY>" <SSH_USERNAME>@<JUMPBOX_HOST> "sudo mkdir -p /home/zdmuser/.ssh && sudo chmod 700 /home/zdmuser/.ssh && sudo chown zdmuser:zdmuser /home/zdmuser/.ssh"
   # Read the public key content locally, then write it to authorized_keys on the jumpbox
   $pubKey = Get-Content "<JUMPBOX_SSH_KEY>.pub" -Raw
   ssh -o BatchMode=yes -p 22 -i "<JUMPBOX_SSH_KEY>" <SSH_USERNAME>@<JUMPBOX_HOST> "echo '$pubKey' | sudo tee /home/zdmuser/.ssh/authorized_keys > /dev/null && sudo chmod 600 /home/zdmuser/.ssh/authorized_keys && sudo chown zdmuser:zdmuser /home/zdmuser/.ssh/authorized_keys"
   ```

4. Verify `zdmuser` can be impersonated and owns the repo:
   ```powershell
   ssh -o BatchMode=yes -p 22 -i "<JUMPBOX_SSH_KEY>" <SSH_USERNAME>@<JUMPBOX_HOST> "sudo -u zdmuser ls /home/zdmuser/GHCP-ODAA-PromptMigration/.github"
   ssh -o BatchMode=yes -p 22 -i "<JUMPBOX_SSH_KEY>" <SSH_USERNAME>@<JUMPBOX_HOST> "stat -c '%U %G' /home/zdmuser"
   ```
   Expected: owner is `zdmuser`, group is `zdmuser` or `zdm`.

If any step fails, surface the error and do not proceed until it is resolved.

After confirming `zdmuser` exists and owns `/home/zdmuser`, proceed to S1-02 (Execution Context / SSH setup). Do not route back to Step 3 — VM creation is complete.

---

## S1-02: Execution context

1. Step1 runs in the LOCAL VS Code terminal (not via Remote-SSH).
2. The primary platform is Windows. All PowerShell paths use `$env:USERPROFILE` for the home directory. Mention macOS/Linux equivalents (`~/.ssh/`) only as parenthetical notes.
3. Do not assume the Remote-SSH extension is installed. Always check first.
4. Copilot must not attempt to establish the Remote-SSH connection itself — the final connection step requires user interaction via the Command Palette. Provide clear instructions for this action.

## S1-03: Extension check

1. Check whether the Remote-SSH extension (`ms-vscode-remote.remote-ssh`) is installed by inspecting the VS Code extensions directory on disk — do **not** invoke `code` or `code.cmd` as a subprocess, as doing so opens unwanted VS Code windows:

   ```powershell
   $extInstalled = Test-Path "$env:USERPROFILE\.vscode\extensions\ms-vscode-remote.remote-ssh*"
   ```

2. If `$extInstalled` is `$true`, confirm and continue.
3. If `$false`, instruct the user to install it:
   - Method A (UI): Open VS Code Extensions panel (`Ctrl+Shift+X`) → search "Remote - SSH" → click Install.
   - Method B (command): Run `code --install-extension ms-vscode-remote.remote-ssh` in a terminal outside of Copilot agent execution.
4. Do not proceed to SSH key setup until the extension is confirmed installed.

## S1-04: Jumpbox connection variable collection

Collect or confirm these values interactively before writing the SSH config entry:

| Variable | Description | Example |
|----------|-------------|---------|
| `JUMPBOX_HOST` | IP address or FQDN of the ZDM jumpbox | `10.0.0.5` or `zdm-jumpbox.example.com` |
| `JUMPBOX_PORT` | SSH port (default: 22) | `22` |
| `JUMPBOX_USER` | SSH login user (must be `zdmuser`) | `zdmuser` |
| `JUMPBOX_SSH_KEY` | Local path to the private key file | `$env:USERPROFILE\.ssh\zdm_jumpbox_key` |
| `JUMPBOX_ALIAS` | Host alias for `~/.ssh/config` (default: `zdm-jumpbox`) | `zdm-jumpbox` |

**Pre-populated bypass (CR-12)**: If `Artifacts/Phase10-Migration/Step1/remote-ssh-setup-report.md` already exists and shows status READY, skip interactive collection and display a confirmation that setup is already complete.

## S1-05: SSH key handling

1. If `JUMPBOX_SSH_KEY` points to an existing file, confirm it exists and note its path. Do not regenerate. Proceed directly to S1-06 (SSH config entry and connectivity test).
2. If the key file does not exist or the user states they have no key yet, offer to generate one:
   - Generate an `ed25519` key pair in `$env:USERPROFILE\.ssh\` with a descriptive filename (e.g. `zdm_jumpbox_key`).
   - Prompt the user for a passphrase or offer to skip (empty passphrase for automation use).
   - After generation, remind the user to copy `zdm_jumpbox_key.pub` to the jumpbox's `~/.ssh/authorized_keys` before connecting.
3. Set correct permissions on the private key file: `icacls "$keyPath" /inheritance:r /grant:r "$env:USERNAME:(F)"` (Windows).
4. Do not overwrite an existing key without explicit user confirmation.
5. **Do not enter a bootstrap or key-copy workflow based on the user describing an alternative login path** (e.g. "I SSH as `azureuser` then `sudo su - zdmuser`"). That describes the user's normal manual access pattern — it does not indicate that `zdmuser` lacks key-based SSH auth. If `JUMPBOX_SSH_KEY` is provided and the file exists, proceed directly to the connectivity test. Only offer bootstrap instructions (copy public key to `zdmuser`'s `authorized_keys` via `azureuser`) if the connectivity test fails with a key authentication error (e.g. `Permission denied (publickey)`).

## S1-06: SSH config entry

1. Check whether `$env:USERPROFILE\.ssh\config` already contains an entry for `JUMPBOX_ALIAS`.
2. If the entry exists and matches the collected values, confirm and do not modify.
3. If the entry exists but differs, show the difference and ask the user to confirm the update.
4. If no entry exists, append the following host block to `~/.ssh/config` (create the file if absent):

```
Host <JUMPBOX_ALIAS>
    HostName <JUMPBOX_HOST>
    Port <JUMPBOX_PORT>
    User <JUMPBOX_USER>
    IdentityFile <JUMPBOX_SSH_KEY>
    ServerAliveInterval 60
    ServerAliveCountMax 10
```

5. After writing the entry, run `ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes -p <JUMPBOX_PORT> -i "<JUMPBOX_SSH_KEY>" <JUMPBOX_USER>@<JUMPBOX_HOST> hostname` to verify connectivity. Report PASS (with returned hostname) or FAIL (with error text).

## S1-07: User handoff to Remote-SSH connect

After SSH config and connectivity check complete, guide the user to open a Remote-SSH session:

1. Open VS Code Command Palette: `Ctrl+Shift+P` (Windows) / `Cmd+Shift+P` (macOS).
2. Type: `Remote-SSH: Connect to Host`
3. Select: `<JUMPBOX_ALIAS>` from the list.
4. VS Code will open a new window connected to the jumpbox. The terminal in that window will run as `zdmuser`.

Copilot cannot trigger this action automatically — it requires user interaction.

## S1-08: Prerequisite for subsequent steps

After Step1, all subsequent steps (Step4 through Step7) must run in the Remote-SSH VS Code session connected to the ZDM jumpbox as `zdmuser`.

1. After delivering the Phase 7 handoff instructions, **explicitly ask the user to confirm** that they have successfully opened the Remote-SSH VS Code session and that their terminal prompt shows `zdmuser@<hostname>`.
2. Do not declare Step 1 complete or suggest running Step 4 until the user provides that confirmation.
3. If the user cannot connect, remain in Step 1 and help troubleshoot before proceeding.

## S1-09: Success criteria

Step1 is complete when **all** of the following are true:

1. The Remote-SSH extension is confirmed installed.
2. The SSH host entry is present in `~/.ssh/config`.
3. The SSH connectivity test passes (or the user acknowledges a known failure and opts to proceed manually).
4. `Artifacts/Phase10-Migration/Step1/remote-ssh-setup-report.md` is written with status READY or ACTION REQUIRED.
5. The user has been given clear step-by-step instructions to open a Remote-SSH session via the VS Code Command Palette.
6. **The user has explicitly confirmed** that they have successfully opened a Remote-SSH VS Code window connected to `<JUMPBOX_ALIAS>` and that their integrated terminal prompt shows `zdmuser@<hostname>`.
