# Example: Discovery Analysis and Migration Planning for <DATABASE_NAME> (Step 3)

> **Note:** Replace `<DATABASE_NAME>` with your project name (for example: `PRODDB`).

This example is intentionally lightweight and shows how to call Step 3.

## Example Prompt

```text
@Step3-Discovery-Questionnaire.prompt.md

## Project Configuration
#file:prompts/Phase10-Migration/ZDM/zdm-env.md

Analyze Step 2 discovery outputs and generate:
1) Discovery summary
2) Migration planning questionnaire

## Step2 Discovery Inputs
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step2/Discovery/source/
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step2/Discovery/target/
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step2/Discovery/server/

## Output Directory
Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step3/
```

---

## Expected Output

Step 3 produces:
- `Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step3/Discovery-Summary-<DATABASE_NAME>.md`
- `Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step3/Migration-Questionnaire-<DATABASE_NAME>.md`

The questionnaire should highlight manual decisions (for example OCIDs, migration options, and scheduling).

For full behavior and generation rules, use:
- `Step3-Discovery-Questionnaire.prompt.md`

## Next Step

After completing the questionnaire, continue with:
- `Example-Step4-Fix-Issues.prompt.md`
