---
agent: agent
description: ZDM Step 1 - Test SSH connectivity before discovery
---
# ZDM Migration Step 1: Test SSH Connectivity

## Purpose
Generate Step1 SSH precheck artifacts for pre-discovery validation. This step creates files only in the repository; runtime SSH checks and report generation happen later on the jumpbox/ZDM server.

## Execution Boundary

This prompt is generation-only.
- Generate files under `Artifacts/Phase10-Migration/Step1/` only.
- Do not execute migration, SSH, SQL, discovery, or remediation commands from VS Code.
- Do not run terminal commands during prompt execution.
- Do not generate runtime validation report files during prompt execution.
- Runtime reports are created only when the generated script is executed later on the jumpbox/ZDM server.

## Inputs And Precedence Rules

Attach `zdm-env.md` when available and treat it as authoritative generation input.

Required values from `zdm-env.md`:
- `SOURCE_HOST`
- `TARGET_HOST`
- `SOURCE_SSH_USER`
- `TARGET_SSH_USER`

Optional values from `zdm-env.md`:
- `SOURCE_SSH_KEY`
- `TARGET_SSH_KEY`

Input precedence and handling requirements:
- Prefer `zdm-env.md` values over prompt defaults/examples.
- If `zdm-env.md` values conflict with discovery evidence, do not silently override; report the mismatch explicitly.
- `zdm-env.md` is generation-time input only; generated script/runtime artifacts must not read, source, or parse `zdm-env.md`.
- Treat placeholder values containing `<...>` as unset.

DB-specific value scope (Step1-Step5):
- `SOURCE_REMOTE_ORACLE_HOME`
- `SOURCE_ORACLE_SID`
- `TARGET_REMOTE_ORACLE_HOME`
- `TARGET_ORACLE_SID`
- `SOURCE_DATABASE_UNIQUE_NAME`
- `TARGET_DATABASE_UNIQUE_NAME`

ZDM-specific value scope (Step1-Step5):
- `ZDM_HOME`

OCI CLI requirement:
- OCI CLI is not required for migration execution.

## Required Outputs

Generate exactly these files:
- `Artifacts/Phase10-Migration/Step1/Scripts/zdm_test_ssh_connectivity.sh`
- `Artifacts/Phase10-Migration/Step1/README.md`

Do not generate these runtime report files during prompt execution:
- `Artifacts/Phase10-Migration/Step1/Validation/ssh-connectivity-report-<timestamp>.md`
- `Artifacts/Phase10-Migration/Step1/Validation/ssh-connectivity-report-<timestamp>.json`

When the generated script is run later on jumpbox/ZDM server, it must create the `Validation/` reports above.

`Artifacts/Phase10-Migration/Step1/README.md` must summarize:
- generated files for Step1,
- what the user should run later on jumpbox/ZDM server,
- where runtime outputs/logs/reports are written,
- success/failure signals to check,
- required runtime user (`zdmuser`),
- example commands to display the latest markdown and JSON reports from `Artifacts/Phase10-Migration/Step1/Validation/`.

## Generated Items And Runtime Content Catalog

### Script: `zdm_test_ssh_connectivity.sh`

Generated script behavior requirements:
1. Intended runtime user is `zdmuser` on the jumpbox/ZDM server.
2. Validate source and target SSH connectivity:
   - `SOURCE_SSH_USER@SOURCE_HOST`
   - `TARGET_SSH_USER@TARGET_HOST`
3. Use `-i <key>` only when the corresponding key path is non-empty after placeholder normalization.
4. When keys are provided, validate key existence, readability, and permissions (`600` or stricter).
5. Use these non-interactive SSH options:
   - `-o BatchMode=yes`
   - `-o StrictHostKeyChecking=accept-new`
   - `-o ConnectTimeout=10`
   - `-o PasswordAuthentication=no`
6. Run `hostname` as the remote probe command for both endpoints.
7. Runtime reports must include at least:
   - execution metadata: timestamp, runtime host, effective user,
   - effective SSH model per endpoint: user, host, key mode (explicit key vs default/agent),
   - key checks when keys are provided: existence, readability, permission result,
   - source connectivity (`hostname`) pass/fail,
   - target connectivity (`hostname`) pass/fail,
   - final summary status and non-zero behavior when any check fails.
8. Runtime console output must include:
   - per-check pass/fail status for major checks (minimum: source probe and target probe),
   - final overall pass/fail summary.
9. Exit code contract:
   - `0` when all checks pass,
   - non-zero when any check fails.
10. Include single-line manual SSH test commands for both endpoints in script output/help comments:
    - default key/agent mode: `ssh user@host ...`
    - explicit key mode: `ssh -i <key> user@host ...`
    Commands must use the same non-interactive options and `hostname` probe behavior as script execution.

### Generated directory structure for this step

Only create Step1 artifacts during prompt execution:

```text
Artifacts/Phase10-Migration/
└── Step1/
    ├── README.md
    └── Scripts/
        └── zdm_test_ssh_connectivity.sh
```

Runtime-only outputs produced later when the script is executed:

```text
Artifacts/Phase10-Migration/Step1/Validation/
├── ssh-connectivity-report-<timestamp>.md
└── ssh-connectivity-report-<timestamp>.json
```

Do not create Step2-Step5 directories in this prompt.

## Next Step

After Step1 connectivity checks pass for both source and target, continue with `@Phase10-ZDM-Step2-Generate-Discovery-Scripts`.
