---
agent: agent
description: Phase 10 ZDM Step 1 example - test SSH connectivity for a sample environment
---
# Example: Test SSH Connectivity (Step 1)

## Example Prompt

```text
@Phase10-ZDM-Step1-Test-SSH-Connectivity

Project Configuration:
#file:zdm-env.md

Generate a script to validate SSH connectivity later on the jumpbox/ZDM server.
```

## Expected Output

```
Artifacts/Phase10-Migration/Step1/
├── README.md
├── Scripts/zdm_test_ssh_connectivity.sh
└── Validation/ (produced when script is run on jumpbox/ZDM server)
    ├── ssh-connectivity-report-<timestamp>.md
    └── ssh-connectivity-report-<timestamp>.json
```

## Requirements Summary

- Generation-only step: create files only, no SSH execution in VS Code.
- If `zdm-env.md` is attached, treat it as authoritative generation input and prefer it over defaults.
- If `zdm-env.md` values conflict with discovery evidence, report mismatch explicitly instead of silently overriding.
- Generated script must not read or source `zdm-env.md` at runtime, and placeholder key values containing `<...>` are treated as unset.
- Generate `Artifacts/Phase10-Migration/Step1/README.md` and `Artifacts/Phase10-Migration/Step1/Scripts/zdm_test_ssh_connectivity.sh` only.
- Runtime report content includes execution metadata, effective SSH mode per endpoint, key checks (when keys are provided), source/target hostname probe results, and final summary with non-zero failure behavior.
- Runtime report generation must enforce completeness/parity gates: both markdown/json outputs exist and are non-empty, markdown contains populated value lines for required sections, and markdown/json summary values match for overall status and failure count.
- If report rendering or write verification fails, runtime behavior must print a clear actionable failure reason and exit non-zero.
- Runtime console output must show per-check pass/fail status plus a final overall pass/fail summary, and the script must use non-interactive SSH options (`BatchMode`, `StrictHostKeyChecking=accept-new`, `ConnectTimeout`, `PasswordAuthentication=no`).
- Shell-rendered report output must be safe for leading-dash literals (no `printf` option-parsing noise) and remain consistent on bash in Oracle Linux/RHEL-family jumpbox environments.
- Step1 runtime user is `zdmuser`, and output should include manual single-line SSH test commands for source and target in both default key/agent mode and explicit key mode.
- OCI CLI is not required for this step.

## Next Steps

After SSH connectivity passes on both source and target, continue with @Phase10-ZDM-Step2-Generate-Discovery-Scripts.
