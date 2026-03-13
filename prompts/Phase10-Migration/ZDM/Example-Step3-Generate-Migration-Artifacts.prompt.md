# Example: Generate Migration Artifacts for <DATABASE_NAME> (Step 3)

> **Note:** Replace `<DATABASE_NAME>` with your project name (for example: `PRODDB`).

This example is intentionally lightweight and shows how to call Step 3.

## Example Prompt

```text
@Step3-Generate-Migration-Artifacts.prompt.md

## Project Configuration
#file:prompts/Phase10-Migration/ZDM/zdm-env.md

Generate migration artifacts for <DATABASE_NAME>.

## Step1 Inputs
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step1/

## Step2 Inputs
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step2/

## Step0 Discovery Inputs
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step0/Discovery/source/
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step0/Discovery/target/
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step0/Discovery/server/

## Output Directory
Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step3/
```

---

## Expected Output

Step 3 generates a migration artifact set, usually including:
- `README.md`
- `zdm_migrate_<DATABASE_NAME>.rsp`
- `zdm_commands_<DATABASE_NAME>.sh`
- `ZDM-Migration-Runbook-<DATABASE_NAME>.md`

These files should be derived from Step0 discovery plus Step1/Step2 decisions and resolutions.

For full generation rules and operational guidance, use:
- `Step3-Generate-Migration-Artifacts.prompt.md`
