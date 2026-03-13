# Example: Discovery Analysis and Migration Planning for <DATABASE_NAME> (Step 1)

> **Note:** Replace `<DATABASE_NAME>` with your project name (for example: `PRODDB`).

This example is intentionally lightweight and shows how to call Step 1.

## Example Prompt

```text
@Step1-Discovery-Questionnaire.prompt.md

## Project Configuration
#file:prompts/Phase10-Migration/ZDM/zdm-env.md

Analyze Step 0 discovery outputs and generate:
1) Discovery summary
2) Migration planning questionnaire

## Step0 Discovery Inputs
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step0/Discovery/source/
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step0/Discovery/target/
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step0/Discovery/server/

## Output Directory
Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step1/
```

---

## Expected Output

Step 1 produces:
- `Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step0/Discovery/Discovery-Summary-<DATABASE_NAME>.md`
- `Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step1/Migration-Questionnaire-<DATABASE_NAME>.md`

The questionnaire should highlight manual decisions (for example OCIDs, migration options, and scheduling).

For full behavior and generation rules, use:
- `Step1-Discovery-Questionnaire.prompt.md`

## Next Step

After completing the questionnaire, continue with:
- `Example-Step2-Fix-Issues.prompt.md`
