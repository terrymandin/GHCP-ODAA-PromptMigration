# Process: Update Requirements and Rebuild Prompts

## Purpose

Use this process whenever you need to change behavior in any Phase10 prompt.

## Workflow

1. Identify affected step(s).
2. Update the step requirement file first:
   - ` .github/requirements/Phase10/StepX/REQUIREMENTS.md`
3. If shared behavior changed, update:
   - ` .github/requirements/Phase10/Shared/COMMON-REQUIREMENTS.md`
4. Regenerate prompt files from requirements by running this command:

   ```text
   @Phase10-Generate-Step-Prompts-From-Requirements

   Regenerate the step prompts based on new requirements.

   #file:.github/requirements/Phase10/Shared/COMMON-REQUIREMENTS.md
   #file:.github/requirements/Phase10/StepX/REQUIREMENTS.md
   ```

   Replace `X` only once in the Step requirements path. The meta prompt infers target prompt files from that Step.

5. Validate prompt text against requirements with the checklist below.
6. Commit both requirement and prompt updates in the same PR.

## Prompt Regeneration Checklist

For each updated step prompt, verify:

1. Execution boundary is explicit (generation-only vs runtime).
2. Input precedence rules match requirements.
3. Output files and directories exactly match the step output contract.
4. Security/read-only/user guardrails are preserved.
5. Variable names and scope are consistent with common requirements.
6. "Next Step" handoff remains correct.

## Suggested PR Structure

1. Commit 1: Requirements change only.
2. Commit 2: Prompt regeneration/update.
3. Commit 3 (optional): Artifact/template adjustments if required.

## Review Questions

Before merging, confirm:

1. Can someone regenerate the prompt from requirements without tribal knowledge?
2. Are runtime actions clearly separated from generation actions?
3. Are conflicts between `zdm-env.md` and discovery evidence handled explicitly?
4. Are all affected Step and Example prompts updated together?
