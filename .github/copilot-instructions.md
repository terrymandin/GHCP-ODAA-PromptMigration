# GitHub Copilot Instructions — Oracle-to-ODAA Migration Toolkit

## What This Repo Does

This repository provides AI-assisted Copilot prompt files for migrating Oracle databases to Oracle Database@Azure (ODAA) using Zero Downtime Migration (ZDM). Each prompt guides one phase of the migration, generates artifacts, and hands off to the next step.

## Key Conventions

- **Artifact outputs** are written to `Artifacts/` which is git-ignored. Never commit generated artifacts.
- **Execution model**: Steps 2–6 run inside a VS Code Remote-SSH session connected to the ZDM jumpbox as `zdmuser`. Step 1 is the exception — it runs in the local VS Code PowerShell terminal to set up that connection.
- **Config artifacts** — `Artifacts/Phase10-Migration/Step2/ssh-config.md` and `Step3/db-config.md` — are the runtime source of truth for SSH and database variables. Generated scripts must not read or parse these files at runtime.
- **Prompts are generated from requirements.** Do not edit `.prompt.md` files directly without first updating the requirement files in `.github/requirements/Phase10/`. Use `@Phase10-Generate-Step-Prompts-From-Requirements` to regenerate.

## Entry Points

| Prompt | Purpose |
|--------|---------|
| `@00-Start-Here` | Onboarding and phase navigation |
| `@Phase10-ZDM-Orchestrator` | Auto-detects migration step and runs it |
| `@GetStatus` | Current migration progress summary |
| `@Phase10-Generate-Step-Prompts-From-Requirements` | Regenerate step prompts from requirements |

## Requirements Layout

```
.github/requirements/Phase10/
  Shared/COMMON-REQUIREMENTS.md   — applies to all steps
  StepX/USER-REQUIREMENTS.md      — user-facing intent
  StepX/SYSTEM-REQUIREMENTS.md    — script/implementation constraints
  PROMPT-UPDATE-PROCESS.md        — workflow for updating requirements and prompts
```

## Variable Naming

- SSH variables (hosts, users, key paths) live in `Step2/ssh-config.md`.
- DB and ZDM variables (`SOURCE_REMOTE_ORACLE_HOME`, `SOURCE_ORACLE_SID`, `TARGET_REMOTE_ORACLE_HOME`, `TARGET_ORACLE_SID`, `SOURCE_DATABASE_UNIQUE_NAME`, `TARGET_DATABASE_UNIQUE_NAME`, `ZDM_HOME`) live in `Step3/db-config.md`.
- OCI CLI is not required for migration execution.
