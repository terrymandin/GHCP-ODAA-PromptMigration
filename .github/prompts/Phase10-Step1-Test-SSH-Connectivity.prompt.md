---
mode: agent
description: ZDM Step 1 - Test SSH connectivity before discovery
---
# ZDM Migration Step 1: Test SSH Connectivity

## Purpose
Run a fast precheck before Step2 to validate SSH host/IP reachability and SSH key usability, so you can catch bad connectivity inputs before generating and running the longer discovery flow.

---

## Requirements

### VS Code Remote SSH (Recommended)
Connect to the jumpbox/ZDM server directly using VS Code Remote SSH:
1. In VS Code, open the Remote Explorer (`Ctrl+Shift+P` → **Remote-SSH: Connect to Host**)
2. Connect to your jumpbox (e.g. `zdmuser@<jumpbox-ip>`)
3. Open this repository folder on the remote host
4. The VS Code integrated terminal is now a shell **on the ZDM server** — scripts you generate are already there, no copying needed

**Requirements for Remote SSH workflow:**
- VS Code with the **Remote - SSH** extension installed locally
- SSH access to the jumpbox/ZDM server from your PC
- This repository cloned on the jumpbox (e.g. `~/GHCP-ODAA-PromptMigration/`)
- `zdm-env.md` filled in and saved on the jumpbox (copy from `zdm-env.example.md`)
- SSH keys for source/target hosts stored in `~/.ssh/` on the jumpbox with permissions `600`

### Traditional Workflow (PC → Copy → Run)
If not using VS Code Remote SSH, generate the script on your PC and copy it to the ZDM server manually.

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

---

## Running the Script

### Option A: VS Code Remote SSH (Recommended)
You are already connected to the ZDM server — no copying required.

1. Open the VS Code integrated terminal (`Ctrl+`` ` or **Terminal → New Terminal**)
2. If not already `zdmuser`, switch: `sudo su - zdmuser`
3. Navigate to the script:
   ```bash
   cd ~/GHCP-ODAA-PromptMigration/Artifacts/Phase10-Migration/Step1/Scripts
   ```
4. Make it executable and run:
   ```bash
   chmod 755 zdm_test_ssh_connectivity.sh
   bash zdm_test_ssh_connectivity.sh
   ```
5. Review the report files written to `Step1/Validation/`

### Option B: Traditional Workflow (PC → Copy → Run)
1. Copy `zdm_test_ssh_connectivity.sh` to the ZDM server:
   ```bash
   scp Artifacts/Phase10-Migration/Step1/Scripts/zdm_test_ssh_connectivity.sh zdmuser@<zdm-server>:~/
   ```
2. SSH into the ZDM server and run as `zdmuser`:
   ```bash
   ssh zdmuser@<zdm-server>
   bash ~/zdm_test_ssh_connectivity.sh
   ```
3. Copy the report files back to your PC or commit them from the ZDM server

---

## Next Step

If Step1 passes for both source and target, continue with:
- `@Phase10-ZDM-Step2-Generate-Discovery-Scripts`
