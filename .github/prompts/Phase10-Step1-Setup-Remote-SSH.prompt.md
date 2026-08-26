---
mode: agent
description: ZDM Step 1 - Set up Remote-SSH through the committed local PowerShell runner
---
# ZDM Migration Step 1: Setup Remote-SSH Connection

## Purpose

Configure a development/non-production ZDM jumpbox and a local Remote-SSH host entry using `scripts/Phase10/Step01/Initialize-Step01Jumpbox.ps1`. This prompt owns user interaction, safety checks, approvals, and handoff. The script owns deterministic execution.

## Execution Boundary

Run this step from the local VS Code session in Windows PowerShell. Do not open a Remote-SSH session during setup. The script may use SSH from local PowerShell only for a newly created jumpbox.

Display before any other action:

```
⚠ ENVIRONMENT SAFETY: This prompt is for development/non-production use only.
Do not run against production. Generated scripts may be copied to production
once reviewed and tested — run them manually there.
```

Use SSH public-key authentication only. Never collect, display, pass, or persist a VM admin password.

## Existing Setup Bypass

Check `Artifacts/Phase10-Migration/Step1/remote-ssh-setup-report.md`. If its `## Status` is `READY`, summarize its alias, host, and key path, then continue to **Remote-SSH Handoff** without rerunning setup.

## Inputs And Approval

Ask whether the ZDM jumpbox already exists and is running.

For an existing VM, collect these values in one numbered chat message. Do not use `vscode_askQuestions`:

1. `JUMPBOX_HOST` - IP address or FQDN
2. `JUMPBOX_PORT` (default: `22`)
3. `JUMPBOX_USER` (must be `zdmuser`)
4. `JUMPBOX_SSH_KEY` - local private key path
5. `JUMPBOX_ALIAS` (default: `zdm-jumpbox`)

Treat `<...>` values as unset. Confirm all values before running the script.

For a new VM, first ask whether the user wants setup help. If yes, collect Groups 1-4 in one numbered chat message:

**Group 1 - VM Identity**
1. VM name (default: `zdm-jumpbox`)
2. Resource group
3. Azure region

**Group 2 - VM Configuration**
4. OS image (default: `Oracle:Oracle-Linux:ol10-lvm-gen2:latest`)
5. VM size (default: `Standard_D2s_v3`)
6. OS disk size in GB (default: `256`)

**Group 3 - Networking**
7. VNet name
8. Subnet name
9. Are the VNet and subnet new? (Yes/No)

**Group 4 - Authentication**
10. Admin SSH username (default: `azureuser`)
11. Local public SSH key path
12. Local private SSH key path

Display all collected values together and require explicit confirmation. If the private key does not exist, offer script-managed `ed25519` key generation with `-GenerateSshKey`; for an existing VM, remind the user to add its public key to `zdmuser`'s `authorized_keys`.

## Script Execution

Build the exact reviewed command using confirmed non-secret values:

```powershell
.\scripts\Phase10\Step01\Initialize-Step01Jumpbox.ps1 -Mode Plan ...
```

Run or display `-Mode Plan` first. Use `-VmMode ExistingVm` for an existing jumpbox; use `-VmMode CreateVm` with the approved VM, network, admin-user, and public-key values for a new jumpbox. Read the JSON result and show its status, failed checks, and remaining actions.

After a successful plan and explicit approval, offer two equivalent choices:

1. Run the same command in `-Mode Apply` through this local Copilot session.
2. Copy the exact reviewed `-Mode Apply` command and run it manually in a local PowerShell terminal.

Never recreate the script's Azure, SSH, file, or report commands inline. Do not include passwords, tokens, or private-key contents in any command, JSON result, or report.

## Required Outputs

Apply mode writes these git-ignored outputs:

- `Artifacts/Phase10-Migration/Step1/remote-ssh-setup-report.md`
- `Artifacts/Phase10-Migration/Step1/README.md`

`READY` requires the Remote-SSH extension, the named SSH host entry, successful key-based connectivity, and successful bootstrap when a new VM was created. Otherwise report `ACTION REQUIRED` and its remaining actions.

## Remote-SSH Handoff

Copilot cannot establish the Remote-SSH connection automatically. When the report is `READY`, tell the user to:

1. Open the Command Palette with `Ctrl+Shift+P`.
2. Select `Remote-SSH: Connect to Host`.
3. Select `JUMPBOX_ALIAS`.
4. Open `/home/zdmuser/GHCP-ODAA-PromptMigration` in the new window.
5. Start a new Copilot Chat and run `@Phase10-ZDM-Orchestrator`.

Ask the user to confirm that the new terminal prompt shows `zdmuser@<hostname>`. Do not declare Step 1 complete or recommend the next step until they provide that confirmation. If they cannot connect, remain in Step 1 and troubleshoot from the runner result and SSH configuration.

## Next Step

After confirmation, run `@Phase10-Step2-Install-ZDM` in the Remote-SSH VS Code window.