# Phase 10 Prompt Requirements

This directory stores source-of-truth requirements used to (re)generate and maintain the Phase 10 prompts.

## Layout

- `Shared/COMMON-REQUIREMENTS.md`: requirements that apply to Steps 1–7.
- `StepX/USER-REQUIREMENTS.md`: step-specific user-facing requirements (Steps 1–7).
- `StepX/SYSTEM-REQUIREMENTS.md`: step-specific implementation/script-level requirements (Steps 1–7).
- `ZDM-Prerequisites/`: pre-loaded ZDM prerequisite check catalogs by ZDM version.
- `PROMPT-UPDATE-PROCESS.md`: standard workflow for updating requirements and regenerating prompts.

## Operating Rule

When prompt behavior changes, update the relevant step requirements first, then regenerate or revise the prompt text.
