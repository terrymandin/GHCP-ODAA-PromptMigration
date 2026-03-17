---
mode: agent
description: ZDM Step 1 - Test SSH connectivity before discovery
---
# ZDM Migration Step 1: Test SSH Connectivity

## Purpose
Run a fast precheck before Step2 to validate SSH host/IP reachability and SSH key usability, so you can catch bad connectivity inputs before generating and running the longer discovery flow.

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
- `SOURCE_SSH_KEY`
- `TARGET_SSH_KEY`

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
2. Validate both key files exist and are readable.
3. Validate key file permissions are `600` (or stricter).
4. Validate SSH connectivity to:
   - `SOURCE_SSH_USER@SOURCE_HOST` with `SOURCE_SSH_KEY`
   - `TARGET_SSH_USER@TARGET_HOST` with `TARGET_SSH_KEY`
5. Use non-interactive SSH options:
   - `-o BatchMode=yes`
   - `-o StrictHostKeyChecking=accept-new`
   - `-o ConnectTimeout=10`
   - `-o PasswordAuthentication=no`
6. Run a trivial remote command (`hostname`) to confirm end-to-end success.
7. Create output files in:
   - `Artifacts/Phase10-Migration/Step1/Validation/`
8. Write:
   - `ssh-connectivity-report-<timestamp>.md` (human-readable summary)
   - `ssh-connectivity-report-<timestamp>.json` (machine-readable status)
9. Exit non-zero if any check fails, and clearly list failures.

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
1. Copy `zdm_test_ssh_connectivity.sh` to the ZDM server
2. Run it as `zdmuser` to validate connectivity to both source and target hosts
3. Review the generated report files in `Step1/Validation/`
4. If both checks pass, proceed to **Step 2: Generate Discovery Scripts**

---

## Next Step

If Step1 passes for both source and target, continue with:
- `@Phase10-ZDM-Step2-Generate-Discovery-Scripts`
