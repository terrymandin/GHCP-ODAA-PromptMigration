# Example: Test SSH Connectivity for <DATABASE_NAME> (Step 1)

> **Note:** Replace `<DATABASE_NAME>` with your project name (for example: `PRODDB`).

This example is intentionally lightweight and shows how to run the Step1 SSH precheck before Step2.

## Example Prompt

```text
@Step1-Test-SSH-Connectivity.prompt.md

## Project Configuration
#file:prompts/Phase10-Migration/ZDM/zdm-env.md

Validate SSH connectivity for <DATABASE_NAME> using configured source/target hosts, users, and keys.
```

---

## Expected Output

Step 1 generates:

```text
Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step1/
├── Scripts/
│   └── zdm_test_ssh_connectivity.sh
└── Validation/
    ├── ssh-connectivity-report-<timestamp>.md
    └── ssh-connectivity-report-<timestamp>.json
```

## Next Step

If both SSH checks pass, continue with:
- `Example-Step2-Generate-Discovery-Scripts.prompt.md`
