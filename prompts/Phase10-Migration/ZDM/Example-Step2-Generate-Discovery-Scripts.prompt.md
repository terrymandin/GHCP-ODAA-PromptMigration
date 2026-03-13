# Example: Generate Discovery Scripts (Step 2)

This example is intentionally lightweight and shows how to call Step 2.
Run Step 2 scripts from the ZDM box; no SSH into the ZDM box is required for Step 2.

## Example Prompt

```text
@Step2-Generate-Discovery-Scripts.prompt.md

## Project Configuration
#file:prompts/Phase10-Migration/ZDM/zdm-env.md

Generate Step 2 discovery scripts.
```

> Run the generated scripts on the ZDM box.

---

## Expected Output

Step 2 generates script artifacts in:

```text
Artifacts/Phase10-Migration/Step2/
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
- `Step2-Generate-Discovery-Scripts.prompt.md`

## Next Step

After collecting discovery outputs, continue with:
- `Example-Step3-Discovery-Questionnaire.prompt.md`
