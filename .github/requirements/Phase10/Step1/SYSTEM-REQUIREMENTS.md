# Step1 System Requirements - Remote-SSH Setup Implementation

## Scope

This file defines implementation-level constraints for the Remote-SSH setup step. Step1 runs in the LOCAL VS Code terminal (PowerShell on Windows). No Remote-SSH session is active during this step.

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
Run Step2 (Configure SSH Connectivity) in the Remote-SSH VS Code session connected to <JUMPBOX_ALIAS> as zdmuser.
```

## S1-16: Local execution constraints

1. All commands run in the LOCAL PowerShell terminal — do not use any Remote-SSH or jumpbox commands.
2. Do not use `sudo`, `bash`, or Unix shell commands natively on Windows. Use PowerShell equivalents.
3. File path separators use `\` on Windows. When passing paths to `ssh` or `ssh-keygen` (which are OpenSSH tools), use forward slashes (`/`) in `-i` argument values or quote paths with backslashes.
4. Step1 must not read, modify, or create any files on the remote jumpbox.
5. Step1 must not produce any artifacts in `Artifacts/Phase10-Migration/Step2/` or later directories — only `Step1/`.
