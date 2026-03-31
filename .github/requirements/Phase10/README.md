# Phase 10 Prompt Requirements

This directory stores source-of-truth requirements used to (re)generate and maintain the Phase 10 prompts.

## Layout

- `Shared/COMMON-REQUIREMENTS.md`: requirements that apply to Step1-Step6.
- `StepX/USER-REQUIREMENTS.md`: step-specific user-facing requirements.
- `StepX/SYSTEM-REQUIREMENTS.md`: step-specific implementation/script-level requirements.
- `PROMPT-UPDATE-PROCESS.md`: standard workflow for updating requirements and regenerating prompts.

## Operating Rule

When prompt behavior changes, update the relevant step requirements first, then regenerate or revise the prompt text.
