## What This Repo Does

This repository provides GitHub Copilot prompts and custom agents for planning and assessing Oracle database migrations to Oracle Database@Azure (ODAA).

## Key Conventions

- **Artifact outputs** are written to phase-specific directories under `Artifacts/`, which is git-ignored. Phase 10 uses `Artifacts/Phase10/`. Never commit generated artifacts.
- Follow path-scoped instruction files under `.github/instructions/` for phase-specific maintenance rules.
- Never commit customer secrets, credentials, private infrastructure details, or raw command output.
- Do not claim that a customer-side command or validation ran unless its output was observed.

## Entry Points

| Entry point | Purpose |
|--------|---------|
| `@00-Start-Here` | Onboarding and phase navigation |
| `Phase 10 ZDM Migration` custom agent | Run the Phase 10 questionnaire, validation, and ZDM artifact-generation workflow |
| `@GetStatus` | Current migration progress summary |
