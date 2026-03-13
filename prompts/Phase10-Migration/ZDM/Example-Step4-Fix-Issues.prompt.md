# Example: Fix Issues (Step 4)

This example is intentionally lightweight and shows how to call Step 4.

## Example Prompt

```text
@Step4-Fix-Issues.prompt.md

## Project Configuration
#file:prompts/Phase10-Migration/ZDM/zdm-env.md

Resolve blockers and required issues found in Step 3 outputs.

## Step3 Inputs
#file:Artifacts/Phase10-Migration/Step3/

## Step2 Discovery (Reference)
#file:Artifacts/Phase10-Migration/Step2/Discovery/source/
#file:Artifacts/Phase10-Migration/Step2/Discovery/target/
#file:Artifacts/Phase10-Migration/Step2/Discovery/server/

## Output Directory
Artifacts/Phase10-Migration/Step4/
```

---

## Expected Output

Step 4 typically generates:
- `Issue-Resolution-Log.md`
- Optional issue-fix scripts and companion READMEs (if needed for unresolved blockers)

The output should clearly track issue status (`Pending`, `In Progress`, `Resolved`) and verification notes.

For complete remediation behavior, use:
- `Step4-Fix-Issues.prompt.md`

## Next Step

When all blockers are resolved, continue with:
- `Example-Step5-Generate-Migration-Artifacts.prompt.md`
