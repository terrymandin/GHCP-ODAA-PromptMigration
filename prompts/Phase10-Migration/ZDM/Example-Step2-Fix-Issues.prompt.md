# Example: Fix Issues for <DATABASE_NAME> (Step 2)

> **Note:** Replace `<DATABASE_NAME>` with your project name (for example: `PRODDB`).

This example is intentionally lightweight and shows how to call Step 2.

## Example Prompt

```text
@Step2-Fix-Issues.prompt.md

## Project Configuration
#file:prompts/Phase10-Migration/ZDM/zdm-env.md

Resolve blockers and required issues found in Step 1 outputs.

## Step1 Inputs
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step1/

## Step0 Discovery (Reference)
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step0/Discovery/source/
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step0/Discovery/target/
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step0/Discovery/server/

## Output Directory
Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step2/
```

---

## Expected Output

Step 2 typically generates:
- `Issue-Resolution-Log-<DATABASE_NAME>.md`
- Optional issue-fix scripts and companion READMEs (if needed for unresolved blockers)

The output should clearly track issue status (`Pending`, `In Progress`, `Resolved`) and verification notes.

For complete remediation behavior, use:
- `Step2-Fix-Issues.prompt.md`

## Next Step

When all blockers are resolved, continue with:
- `Example-Step3-Generate-Migration-Artifacts.prompt.md`
