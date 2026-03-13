# Example: Generate Discovery Scripts for <DATABASE_NAME> (Step 0)

> **Note:** Replace `<DATABASE_NAME>` with your project name (for example: `PRODDB`).

This example is intentionally lightweight and shows how to call Step 0.

## Example Prompt

```text
@Step0-Generate-Discovery-Scripts.prompt.md

## Project Configuration
#file:prompts/Phase10-Migration/ZDM/zdm-env.md

Generate Step 0 discovery scripts for the <DATABASE_NAME> migration.
```

> Update `PROJECT_NAME` in [zdm-env.md](zdm-env.md) before running.

---

## Expected Output

Step 0 generates script artifacts in:

```text
Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step0/
├── Scripts/
│   ├── zdm_source_discovery.sh
│   ├── zdm_target_discovery.sh
│   ├── zdm_server_discovery.sh
│   ├── zdm_orchestrate_discovery.sh
│   └── README.md
└── Discovery/
    ├── source/
    ├── target/
    └── server/
```

For script execution guidance and operational details, use:
- `Step0-Generate-Discovery-Scripts.prompt.md`

## Next Step

After collecting discovery outputs, continue with:
- `Example-Step1-Discovery-Questionnaire.prompt.md`
