# ZDM Migration Step 1: Test SSH Connectivity

> **Note:** Replace `<DATABASE_NAME>` with your database name (for example: `PRODDB`).

## Purpose
Run a fast precheck before Step2 to validate SSH host/IP reachability and SSH key usability, so you can catch bad connectivity inputs before generating and running the longer discovery flow.

---

## Inputs

Attach your project configuration:

```text
#file:prompts/Phase10-Migration/ZDM/zdm-env.md
```

Required values in `zdm-env.md`:
- `PROJECT_NAME`
- `SOURCE_HOST`
- `TARGET_HOST`
- `SOURCE_SSH_USER`
- `TARGET_SSH_USER`
- `SOURCE_SSH_KEY`
- `TARGET_SSH_KEY`

---

## Instructions

Generate a single bash script named `zdm_test_ssh_connectivity.sh` in:

`Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step1/Scripts/`

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
   - `Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step1/Validation/`
8. Write:
   - `ssh-connectivity-report-<timestamp>.md` (human-readable summary)
   - `ssh-connectivity-report-<timestamp>.json` (machine-readable status)
9. Exit non-zero if any check fails, and clearly list failures.

---

## Expected Output Structure

```text
Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step1/
├── Scripts/
│   └── zdm_test_ssh_connectivity.sh
└── Validation/
    ├── ssh-connectivity-report-<timestamp>.md
    └── ssh-connectivity-report-<timestamp>.json
```

## Next Step

If Step1 passes for both source and target, continue with:
- `Step2-Generate-Discovery-Scripts.prompt.md`
