# Step1 User Requirements - Setup Remote-SSH Connection

## Objective

Configure a Remote-SSH connection from the local VS Code session to the ZDM jumpbox so that subsequent steps (Step2 onward) run in the correct Remote-SSH terminal context as `zdmuser`.

**Execution model exception**: Step1 runs entirely in the LOCAL VS Code session (local terminal), not via Remote-SSH. The Remote-SSH extension must be installed and the connection must be set up before any Remote-SSH session can begin.

## S1-01: Output contract

Step1 writes one artifact using file tools after setup completes:

- `Artifacts/Phase10-Migration/Step1/remote-ssh-setup-report.md`

The report must contain:

1. Extension check result (installed / not installed, with version when available).
2. SSH key location and mode (existing key used vs. new key generated).
3. The host alias added or confirmed in `~/.ssh/config`.
4. Connection command the user can run to manually verify: `ssh zdmuser@<jumpbox-alias>`.
5. Final status: READY or ACTION REQUIRED, with remaining manual actions listed.

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

After Step1, all subsequent steps (Step2 through Step6) must run in the Remote-SSH VS Code session connected to the ZDM jumpbox as `zdmuser`.

1. After delivering the Phase 7 handoff instructions, **explicitly ask the user to confirm** that they have successfully opened the Remote-SSH VS Code session and that their terminal prompt shows `zdmuser@<hostname>`.
2. Do not declare Step 1 complete or suggest running Step 2 until the user provides that confirmation.
3. If the user cannot connect, remain in Step 1 and help troubleshoot before proceeding.

## S1-09: Success criteria

Step1 is complete when **all** of the following are true:

1. The Remote-SSH extension is confirmed installed.
2. The SSH host entry is present in `~/.ssh/config`.
3. The SSH connectivity test passes (or the user acknowledges a known failure and opts to proceed manually).
4. `Artifacts/Phase10-Migration/Step1/remote-ssh-setup-report.md` is written with status READY or ACTION REQUIRED.
5. The user has been given clear step-by-step instructions to open a Remote-SSH session via the VS Code Command Palette.
6. **The user has explicitly confirmed** that they have successfully opened a Remote-SSH VS Code window connected to `<JUMPBOX_ALIAS>` and that their integrated terminal prompt shows `zdmuser@<hostname>`.
