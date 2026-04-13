---
mode: agent
description: Generate or update Phase10 StepX prompt files from requirements
---
# Generate Phase10 Step Prompt Files From Requirements

## Purpose

Use this meta prompt to generate or update the StepX prompt files directly from the requirements source of truth.

## How To Use

Use this exact command pattern. Replace `X` in the Step requirements paths with `1` through `6`:

```text
@Phase10-Generate-Step-Prompts-From-Requirements

Regenerate the step prompts based on new requirements.

## Required Inputs
#file:.github/requirements/Phase10/Shared/COMMON-REQUIREMENTS.md
#file:.github/requirements/Phase10/StepX/USER-REQUIREMENTS.md
#file:.github/requirements/Phase10/StepX/SYSTEM-REQUIREMENTS.md
```

Accepted natural-language trigger variants:

- `Regenerate the step prompts based on new requirements.`
- `Regenerate prompt files from requirements.`
- `Update step prompt files from requirements.`

The selected Step is inferred from the attached `StepX/USER-REQUIREMENTS.md` or `StepX/SYSTEM-REQUIREMENTS.md` path.

## Step-to-File Mapping

When `X` is provided, update this file:

1. Step 1 — `.github/prompts/Phase10-Step1-Setup-Remote-SSH.prompt.md`
2. Step 2 — `.github/prompts/Phase10-Step2-Configure-SSH-Connectivity.prompt.md`
3. Step 3 — `.github/prompts/Phase10-Step3-Generate-Discovery-Scripts.prompt.md`
4. Step 4 — `.github/prompts/Phase10-Step4-Discovery-Questionnaire.prompt.md`
5. Step 5 — `.github/prompts/Phase10-Step5-Fix-Issues.prompt.md`
6. Step 6 — `.github/prompts/Phase10-Step6-Generate-Migration-Artifacts.prompt.md`

## Generation Rules

1. Treat requirements as authoritative.
   - Apply shared requirements first, then step-specific user and system requirements.
2. Keep this prompt section order in every generated prompt:
   1. Purpose
   2. Execution boundary (generation-only vs runtime)
   3. Inputs and precedence rules
   4. Required outputs
   5. Generated items/content catalogs
   6. Next-step handoff
3. Preserve deterministic behavior.
   - Convert each must/shall requirement into explicit imperative prompt text.
4. Preserve or create valid YAML frontmatter:
   - `agent: agent`
   - Step-appropriate `description`

## Coverage Check (Required)

Before finishing, verify:

1. Every requirement section in `StepX/USER-REQUIREMENTS.md` and `StepX/SYSTEM-REQUIREMENTS.md` is represented in the generated prompt text.
2. Shared constraints are present unless explicitly narrowed by StepX requirements.
3. Output paths, filenames, and variable names match requirements exactly.
4. Next-step handoff points to the correct next Phase10 prompt.

## Output Expectations

1. Update the StepX prompt file in place.
2. Do not modify prompts for other steps.
3. Provide a concise summary of what changed and which requirement sections drove the changes.
