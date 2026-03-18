# Process: Update Requirements and Rebuild Prompts

## Purpose

Use this process whenever you need to change behavior in any Phase10 prompt.

## Workflow

1. Identify affected step(s).
2. Update step requirement input file(s) first:
  - ` .github/requirements/Phase10/StepX/USER-REQUIREMENTS.md`
  - ` .github/requirements/Phase10/StepX/SYSTEM-REQUIREMENTS.md`
3. If shared behavior changed, update:
   - ` .github/requirements/Phase10/Shared/COMMON-REQUIREMENTS.md`
4. Regenerate prompt files from requirements using this command pattern:

   ```text
   @Phase10-Generate-Step-Prompts-From-Requirements

   Regenerate the step prompts based on new requirements.

   #file:.github/requirements/Phase10/Shared/COMMON-REQUIREMENTS.md
   #file:.github/requirements/Phase10/StepX/USER-REQUIREMENTS.md
   #file:.github/requirements/Phase10/StepX/SYSTEM-REQUIREMENTS.md
   ```

  Replace `X` only in the Step requirements paths. The meta prompt infers target prompt files from the Step path.
  Include both step files so user-facing and implementation constraints are both applied.

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
7. User-facing behavior traces to `USER-REQUIREMENTS.md` and coding constraints trace to `SYSTEM-REQUIREMENTS.md`.
8. Shell-script output rendering is safe for markdown/list literals that begin with `-` (no `printf` option parsing errors during runtime writes).
9. Any runtime report contract includes explicit completeness/parity checks and non-zero exit behavior on report-write failures.

For each updated example prompt, verify:

1. It contains exactly four sections: `Example Prompt`, `Expected Output`, `Requirements Summary`, and `Next Steps`.
2. It does not include extra sections (for example: `Prerequisites`, `Execution Boundary`, or detailed catalogs).
3. `Requirements Summary` is concise and reflects shared plus step-specific requirements.
4. `Next Steps` provides the handoff to the next Phase10 prompt.
5. Any detailed operational guidance exists in the corresponding Step prompt, not in the Example prompt.

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
5. Do Example prompts remain lightweight while Step prompts retain all operational details?
