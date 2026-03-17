---
agent: agent
description: ZDM Step 1 - Test SSH connectivity before discovery
---
# ZDM Migration Step 1: Test SSH Connectivity

## Purpose
Generate the Step 1 SSH validation script only. The script is committed to GitHub, pulled on the jumpbox/ZDM server, and executed there by the user.

## Execution Boundary (Critical)

This prompt is generation-only.
- Generate `Artifacts/Phase10-Migration/Step1/Scripts/zdm_test_ssh_connectivity.sh`
- Do not execute SSH checks from VS Code
- Do not run terminal commands or ask to run terminal commands during prompt execution
- Do not create `ssh-connectivity-report-*.md` or `ssh-connectivity-report-*.json` during prompt execution
- Report files are created only when the generated script is run on the jumpbox/ZDM server

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
9. Exit non-zero if any check fails, and clearly list failures.
10. Do not emit any runtime logic that reads `zdm-env.md`; all needed values must be rendered into the generated script at generation time.

---

## Expected Output Structure

```text
Artifacts/Phase10-Migration/Step1/
├── Scripts/
│   └── zdm_test_ssh_connectivity.sh
└── Validation/
    ├── ssh-connectivity-report-<timestamp>.md
    └── ssh-connectivity-report-<timestamp>.json
```

---

## Output Location

Save the Step 1 script to: `Artifacts/Phase10-Migration/Step1/`

Do not generate validation report files in VS Code during this prompt.

**IMPORTANT:** Step 1 should ONLY create files in the `Step1/` directory. Do NOT create Step2/, Step3/, or Step4/ folders — those will be created by their respective prompts.

The Step 1 directory structure to create:
```
Artifacts/Phase10-Migration/
└── Step1/                                    # Step 1: SSH Connectivity Test (CREATE THIS ONLY)
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
└── Step4/    # Created by Step4 prompt — Migration artifacts
```

After generating the SSH test script:
1. Commit `Artifacts/Phase10-Migration/Step1/Scripts/zdm_test_ssh_connectivity.sh` to GitHub and push
2. On the jumpbox/ZDM server, clone or pull the repository and run the script as `zdmuser`
3. Review the generated report files in `Artifacts/Phase10-Migration/Step1/Validation/` in the repo clone
4. If both checks pass, proceed to **Step 2: Generate Discovery Scripts**

Do not perform steps 2-3 from this prompt session. They are operator-run actions on the jumpbox/ZDM server after script generation.

---

## Next Step

If Step1 passes for both source and target, continue with:
- `@Phase10-ZDM-Step2-Generate-Discovery-Scripts`
