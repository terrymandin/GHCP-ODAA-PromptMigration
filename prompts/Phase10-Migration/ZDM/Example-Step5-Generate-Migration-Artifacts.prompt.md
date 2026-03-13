# Example: Generate Migration Artifacts for <DATABASE_NAME> (Step 5)

> **Note:** Replace `<DATABASE_NAME>` with your project name (for example: `PRODDB`).

This example is intentionally lightweight and shows how to call Step 5.

## Example Prompt

```text
@Step5-Generate-Migration-Artifacts.prompt.md

## Project Configuration
#file:prompts/Phase10-Migration/ZDM/zdm-env.md

Generate migration artifacts for <DATABASE_NAME>.

## Step3 Inputs
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step3/

## Step4 Inputs
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step4/

## Step2 Discovery Inputs
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step2/Discovery/source/
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step2/Discovery/target/
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step2/Discovery/server/

## Output Directory
Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step5/
```

---

## Expected Output

Step 5 generates a migration artifact set, usually including:
- `README.md`
- `zdm_migrate_<DATABASE_NAME>.rsp`
- `zdm_commands_<DATABASE_NAME>.sh`
- `ZDM-Migration-Runbook-<DATABASE_NAME>.md`

These files should be derived from Step2 discovery plus Step3/Step4 decisions and resolutions.

For full generation rules and operational guidance, use:
- `Step5-Generate-Migration-Artifacts.prompt.md`
