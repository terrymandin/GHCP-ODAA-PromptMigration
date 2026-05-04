---
mode: agent
description: Generate or update Phase10 StepX prompt files from requirements
---
# Generate Phase10 Step Prompt Files From Requirements

## Purpose

Use this meta prompt to generate or update the StepX prompt files directly from the requirements source of truth.

## First Action: Determine Mode

**If no requirement files are attached**, ask the user before doing anything else:

> Which step do you want to regenerate?
>
> - **1** — Step 1: Setup Remote SSH
> - **2** — Step 2: Configure SSH Connectivity
> - **3** — Step 3: Generate Discovery Scripts
> - **4** — Step 4: Discovery Questionnaire
> - **5** — Step 5: Fix Issues
> - **6** — Step 6: Generate Migration Artifacts
> - **All** — Regenerate all steps in sequence (1 through 6)
>
> Type a number or "All".

Wait for the answer, then read the requirement files yourself using `read_file` — do not ask the user to attach them manually when running in this mode.

**If requirement files are already attached**, skip the question and proceed directly to generation using the attached files.

---

## How To Use

### Option A — Attach files yourself (single step)

Replace `X` in the Step requirements paths with `1` through `6`:

```text
@Phase10-Generate-Step-Prompts-From-Requirements

Regenerate the step prompts based on new requirements.

## Required Inputs
#file:.github/requirements/Phase10/Shared/COMMON-REQUIREMENTS.md
#file:.github/requirements/Phase10/StepX/USER-REQUIREMENTS.md
#file:.github/requirements/Phase10/StepX/SYSTEM-REQUIREMENTS.md
```

### Option B — Let the prompt ask you (single step or all steps)

Just run:

```text
@Phase10-Generate-Step-Prompts-From-Requirements
```

You will be asked which step (or "All") to regenerate. The prompt will read the requirement files itself.

Accepted natural-language trigger variants:

- `Regenerate the step prompts based on new requirements.`
- `Regenerate prompt files from requirements.`
- `Update step prompt files from requirements.`
- `Regenerate all step prompts.`

The selected Step is inferred from the attached `StepX/USER-REQUIREMENTS.md` or `StepX/SYSTEM-REQUIREMENTS.md` path, or from the user's answer to the step-selection question.

---

## Step-to-File Mapping

| Step | Prompt file | Requirements files |
|------|-------------|-------------------|
| 1 | `.github/prompts/Phase10-Step1-Setup-Remote-SSH.prompt.md` | `Step1/USER-REQUIREMENTS.md`, `Step1/SYSTEM-REQUIREMENTS.md` |
| 2 | `.github/prompts/Phase10-Step2-Configure-SSH-Connectivity.prompt.md` | `Step2/USER-REQUIREMENTS.md`, `Step2/SYSTEM-REQUIREMENTS.md` |
| 3 | `.github/prompts/Phase10-Step3-Generate-Discovery-Scripts.prompt.md` | `Step3/USER-REQUIREMENTS.md`, `Step3/SYSTEM-REQUIREMENTS.md` |
| 4 | `.github/prompts/Phase10-Step4-Discovery-Questionnaire.prompt.md` | `Step4/USER-REQUIREMENTS.md`, `Step4/SYSTEM-REQUIREMENTS.md` |
| 5 | `.github/prompts/Phase10-Step5-Fix-Issues.prompt.md` | `Step5/USER-REQUIREMENTS.md`, `Step5/SYSTEM-REQUIREMENTS.md` |
| 6 | `.github/prompts/Phase10-Step6-Generate-Migration-Artifacts.prompt.md` | `Step6/USER-REQUIREMENTS.md`, `Step6/SYSTEM-REQUIREMENTS.md` |

All requirement files live under `.github/requirements/Phase10/`. The shared file is always `.github/requirements/Phase10/Shared/COMMON-REQUIREMENTS.md`.

---

## "All Steps" Mode

When the user selects "All":

1. Read `Shared/COMMON-REQUIREMENTS.md` once.
2. Process each step in order (1 → 6), reading each step's `USER-REQUIREMENTS.md` and `SYSTEM-REQUIREMENTS.md` and regenerating its prompt file.
3. After each step, confirm the file was updated before moving to the next.
4. After all six steps, produce a single summary table showing what changed in each.

Do not ask the user for confirmation between steps — process all six sequentially and report at the end.

---

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
   - `mode: agent`
   - Step-appropriate `description`

## Coverage Check (Required)

Before finishing each step, verify:

1. Every requirement section in `StepX/USER-REQUIREMENTS.md` and `StepX/SYSTEM-REQUIREMENTS.md` is represented in the generated prompt text.
2. Shared constraints are present unless explicitly narrowed by StepX requirements.
3. Output paths, filenames, and variable names match requirements exactly.
4. Next-step handoff points to the correct next Phase10 prompt.

## Output Expectations

1. Update the StepX prompt file in place.
2. Do not modify prompts for other steps (unless "All" mode).
3. Provide a concise summary of what changed and which requirement sections drove the changes.
