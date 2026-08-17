# Phase 10 Prompt Requirements

This directory stores source-of-truth requirements used to (re)generate and maintain the Phase 10 prompts.

## Layout

- `Shared/COMMON-REQUIREMENTS.md`: requirements that apply to Steps 0–6.
- `Step3/USER-REQUIREMENTS.md`: Azure VM creation and ZDM installation — user-facing requirements.
- `Step3/SYSTEM-REQUIREMENTS.md`: Azure VM creation and ZDM installation — implementation constraints.
- `StepX/USER-REQUIREMENTS.md`: step-specific user-facing requirements (Steps 1–6).
- `StepX/SYSTEM-REQUIREMENTS.md`: step-specific implementation/script-level requirements (Steps 1–6).
- `ZDM-Prerequisites/`: pre-loaded ZDM prerequisite check catalogs by ZDM version.
- `Rules/`: deterministic rule and error knowledgebase catalogs used by Steps 5–7.
- `PROMPT-UPDATE-PROCESS.md`: standard workflow for updating requirements and regenerating prompts.

## Operating Rule

When prompt behavior changes, update the relevant step requirements first, then regenerate or revise the prompt text.
