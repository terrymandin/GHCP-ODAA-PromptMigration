---
agent: agent
description: ZDM Step 1 - Test SSH connectivity before discovery
---
# ZDM Migration Step 1: Test SSH Connectivity

## Purpose
Generate Step 1 artifacts for pre-discovery SSH validation. This step produces files only in the repository; runtime SSH checks happen later on the jumpbox/ZDM server.

## Execution Boundary (Critical)

This prompt is generation-only.
- Generate only Step1 files:
   - `Artifacts/Phase10-Migration/Step1/Scripts/zdm_test_ssh_connectivity.sh`
   - `Artifacts/Phase10-Migration/Step1/README.md`
- Do not execute SSH checks from VS Code
- Do not run terminal commands or ask to run terminal commands during prompt execution
- Do not create `ssh-connectivity-report-*.md` or `ssh-connectivity-report-*.json` during prompt execution
- Report files are created only when the generated script is run on the jumpbox/ZDM server
- Do not run migration, SSH, SQL, discovery, or remediation commands in VS Code

Agent action guardrail:
- This step authorizes file generation only.
- Do not call any execution tools for SSH validation in this step.
- If asked to "validate" in this step, interpret it as "generate a validation script".

---

## Inputs

Attach your project configuration:

```text
#file:zdm-env.md
```

Required values in `zdm-env.md`:
- `SOURCE_HOST`
- `TARGET_HOST`
- `SOURCE_SSH_USER`
- `TARGET_SSH_USER`

Optional values in `zdm-env.md`:
- `SOURCE_SSH_KEY`
- `TARGET_SSH_KEY`

Configuration precedence for artifact generation (mandatory):
- Treat attached `zdm-env.md` values as authoritative generation input.
- Render `SOURCE_HOST`, `TARGET_HOST`, `SOURCE_SSH_USER`, `TARGET_SSH_USER`, `SOURCE_SSH_KEY`, and `TARGET_SSH_KEY` directly from `zdm-env.md` when creating the script.
- If a value from `zdm-env.md` conflicts with any template default/example value, prefer `zdm-env.md`.
- If values conflict with discovery evidence, do not silently override; explicitly report the mismatch in prompt output notes.
- Only fall back to defaults when a `zdm-env.md` field is missing/blank or still a placeholder containing `<...>`.

`zdm-env.md` is a generation-time input only. The generated script must be self-contained and must not read, source, parse, or depend on `zdm-env.md` (or any repo-local config file) at runtime.

Placeholder values containing `<...>` (for example `~/.ssh/<source_key>.pem`) must be treated as unset.

DB-specific value scope for Step 1-5 prompts:
- `SOURCE_REMOTE_ORACLE_HOME`
- `SOURCE_ORACLE_SID`
- `TARGET_REMOTE_ORACLE_HOME`
- `TARGET_ORACLE_SID`
- `SOURCE_DATABASE_UNIQUE_NAME`
- `TARGET_DATABASE_UNIQUE_NAME`

ZDM-specific value scope for Step 1-5 prompts:
- `ZDM_HOME`

Operational prerequisite note:
- OCI CLI is not required.

---

## Instructions

Generate a single bash script named `zdm_test_ssh_connectivity.sh` in:

`Artifacts/Phase10-Migration/Step1/Scripts/`

The script must:
1. Run on the ZDM server as `zdmuser`.
2. If `SOURCE_SSH_KEY` / `TARGET_SSH_KEY` are set, validate each key file exists and is readable.
3. If key variables are set, validate key file permissions are `600` (or stricter).
4. Validate SSH connectivity to:
   - `SOURCE_SSH_USER@SOURCE_HOST`
   - `TARGET_SSH_USER@TARGET_HOST`
   Use `-i <key>` only when the corresponding key variable is non-empty and does not contain a placeholder value (for example `<...>`).
5. Use non-interactive SSH options:
   - `-o BatchMode=yes`
   - `-o StrictHostKeyChecking=accept-new`
   - `-o ConnectTimeout=10`
   - `-o PasswordAuthentication=no`
6. Run a trivial remote command (`hostname`) to confirm end-to-end success.
7. At runtime on the jumpbox/ZDM server, create output files in:
   - `Artifacts/Phase10-Migration/Step1/Validation/`
8. At runtime on the jumpbox/ZDM server, write:
   - `ssh-connectivity-report-<timestamp>.md` (human-readable summary)
   - `ssh-connectivity-report-<timestamp>.json` (machine-readable status)
9. Include runtime report content covering at least:
   - execution metadata: timestamp, runtime host, effective user
   - effective SSH model per endpoint: user, host, key mode (explicit key vs default/agent)
   - key checks when keys are provided: existence, readability, permission result
   - source connectivity (`hostname`) pass/fail
   - target connectivity (`hostname`) pass/fail
   - final summary status and non-zero exit behavior when any check fails
10. Print per-check runtime status to console (minimum: source probe, target probe) with pass/fail outcomes.
11. Print a final overall pass/fail summary to console.
12. Exit code must be `0` only when all checks pass; otherwise exit non-zero.
13. Include in script output/help comments single-line manual SSH test commands for both endpoints:
    - default key/agent mode: `ssh user@host ...`
    - explicit key mode: `ssh -i <key> user@host ...`
    Use the same non-interactive options and `hostname` probe behavior as the script.
14. Do not emit any runtime logic that reads `zdm-env.md`; all needed values must be rendered into the generated script at generation time.

Generate `Artifacts/Phase10-Migration/Step1/README.md` with:
1. Generated files for Step1.
2. What to run later on jumpbox/ZDM server.
3. Where runtime outputs/logs/reports are written.
4. Success/failure signals to check.
5. Example commands to display the latest markdown and JSON reports under `Artifacts/Phase10-Migration/Step1/Validation` after runtime execution.

---

## Expected Output Structure

```text
Artifacts/Phase10-Migration/Step1/
├── README.md
├── Scripts/
│   └── zdm_test_ssh_connectivity.sh
└── Validation/
    ├── ssh-connectivity-report-<timestamp>.md
    └── ssh-connectivity-report-<timestamp>.json
```

---

## Output Location

Save Step 1 files to: `Artifacts/Phase10-Migration/Step1/`

Do not generate validation report files in VS Code during this prompt.

**IMPORTANT:** Step 1 should ONLY create files in the `Step1/` directory. Do NOT create Step2/, Step3/, or Step4/ folders — those will be created by their respective prompts.

The Step 1 directory structure to create:
```
Artifacts/Phase10-Migration/
└── Step1/                                    # Step 1: SSH Connectivity Test (CREATE THIS ONLY)
   ├── README.md                              # Step 1 run and output guidance
    └── Scripts/                              # SSH test script
        └── zdm_test_ssh_connectivity.sh
```

> **Note:** The `Validation/` subdirectory and its report files are produced at runtime when `zdm_test_ssh_connectivity.sh` is executed on the ZDM server — they are not created by this prompt.

For reference, the complete migration folder structure (created across all steps) is:
```
Artifacts/Phase10-Migration/
├── Step1/    # Created by Step1 prompt (this prompt) — SSH connectivity test script
├── Step2/    # Created by Step2 prompt — Discovery scripts
├── Step3/    # Created by Step3 prompt — Discovery questionnaire
├── Step4/    # Created by Step4 prompt — Fix issues
└── Step5/    # Created by Step5 prompt — Migration artifacts
```

After generating Step1 files:
1. Commit `Artifacts/Phase10-Migration/Step1/README.md` and `Artifacts/Phase10-Migration/Step1/Scripts/zdm_test_ssh_connectivity.sh` to GitHub and push
2. On the jumpbox/ZDM server, clone or pull the repository and run the script as `zdmuser`
3. Review the generated report files in `Artifacts/Phase10-Migration/Step1/Validation/` in the repo clone
4. If both checks pass, proceed to **Step 2: Generate Discovery Scripts**

Do not perform steps 2-3 from this prompt session. They are operator-run actions on the jumpbox/ZDM server after script generation.

---

## Next Step

If Step1 passes for both source and target, continue with:
- `@Phase10-ZDM-Step2-Generate-Discovery-Scripts`
