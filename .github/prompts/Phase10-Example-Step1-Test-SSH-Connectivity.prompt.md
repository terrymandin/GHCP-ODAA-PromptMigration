---
agent: agent
description: Phase 10 ZDM Step 1 example - test SSH connectivity for a sample environment
---
# Example: Test SSH Connectivity (Step 1)

## Prerequisites

VS Code must be connected to the ZDM jumpbox via the **Remote-SSH** extension before running this step. The terminal and all file operations execute on the jumpbox.

## Example Prompt

```text
@Phase10-ZDM-Step1-Test-SSH-Connectivity

Project Configuration:
#file:zdm-env.md

Test SSH connectivity from the jumpbox to the source and target database servers.
```

## Expected Output

```
Artifacts/Phase10-Migration/Step1/
└── Validation/                         (git-ignored — written during prompt execution)
    ├── ssh-connectivity-report-<timestamp>.md
    └── ssh-connectivity-report-<timestamp>.json
```

`Scripts/zdm_test_ssh_connectivity.sh` is only generated if direct terminal commands are insufficient (e.g. multi-step key diagnostics). If generated, it is left in place for debugging.

## Requirements Summary

- Runs via terminal on the ZDM jumpbox (VS Code Remote-SSH). No script transfer or manual execution required.
- If `zdm-env.md` is attached, treat it as authoritative input and prefer its values over defaults.
- SSH tests run as `zdmuser` using `sudo su - zdmuser -c "ssh ..."` so key paths resolve correctly relative to `/home/zdmuser`.
- Use non-interactive SSH options: `BatchMode=yes`, `StrictHostKeyChecking=accept-new`, `ConnectTimeout=10`, `PasswordAuthentication=no`.
- Use `-i <key>` only when `SOURCE_SSH_KEY` / `TARGET_SSH_KEY` are non-empty after placeholder normalization.
- Before SSH tests: confirm `zdmuser` exists; if keys are specified, confirm key files exist with permissions `600`; attempt `chmod 600` automatically if permissions are wrong.
- Iterate on failures: diagnose error, apply fix, retry. Maximum **3 total attempts** per endpoint.
- After 3 failures: stop, report exactly what was tried and the last error, and state what the user should check manually.
- Write validation report (markdown + JSON) using file tools. Reports are git-ignored in `Artifacts/`.
- Report summary inline in chat: per-endpoint PASS/FAIL (remote hostname or error), and overall status.

## Next Steps

After SSH connectivity passes on both source and target, continue with @Phase10-ZDM-Step2-Generate-Discovery-Scripts.
