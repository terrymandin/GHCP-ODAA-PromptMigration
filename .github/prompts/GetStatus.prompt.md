---
mode: agent
description: Get the current Oracle Database@Azure migration status
---

# Oracle Database@Azure Migration - Status

## Instructions

Retrieve and display the current status of the Oracle Database@Azure migration.

### If `Artifacts/Report-Status.md` does not exist
Create it with the following initial content, then display it:

```markdown
# Oracle Database@Azure Migration Status

**Status**: Not Started
**Last Updated**: <today's date>

## Phase Completion
- [ ] Phase 0: ODAA Readiness Assessment
- [ ] Phase 5: CIDR Range Planning
- [ ] Phase 6: Infrastructure as Code (Terraform)
- [ ] Phase 10 - Step 1: Setup Remote-SSH
- [ ] Phase 10 - Step 2: Install ZDM
- [ ] Phase 10 - Step 3: Configure SSH Connectivity
- [ ] Phase 10 - Step 4: Run Discovery
- [ ] Phase 10 - Step 5: Discovery Questionnaire
- [ ] Phase 10 - Step 6: Fix Issues
- [ ] Phase 10 - Step 7: Generate Migration Artifacts

## Next Step
Run `@Phase0-ODAA-Readiness` to begin the migration readiness assessment.
```

### If `Artifacts/Report-Status.md` exists
Read its content, summarize the current state, and ensure it contains:

1. **Executive Summary** - source database, target ODAA environment, overall completion %
2. **Phase completion checklist** - `[x]` for completed phases with timestamps, `[ ]` for pending
	- Include all current steps: Phase 0, Phase 5, Phase 6, and Phase 10 Steps 1-7
3. **Database configuration** - source host, target host, database name, migration method (ZDM/DataGuard/RMAN/DataPump/GoldenGate)
4. **ZDM readiness** (if applicable) - Step 2 install status, Step 3 SSH status, Step 4 discovery status, blockers resolved Y/N
5. **Blockers and issues** - severity (Critical / High / Medium), current resolution state
6. **Next recommended step** - specific `@PromptName` command to run next

When deriving the next recommended step, use this mapping:

- Step 1 -> `@Phase10-Step1-Setup-Remote-SSH`
- Step 2 -> `@Phase10-Step2-Install-ZDM`
- Step 3 -> `@Phase10-Step3-Configure-SSH-Connectivity`
- Step 4 -> `@Phase10-Step4-Generate-Discovery-Scripts`
- Step 5 -> `@Phase10-Step5-Discovery-Questionnaire`
- Step 6 -> `@Phase10-Step6-Fix-Issues`
- Step 7 -> `@Phase10-Step7-Generate-Migration-Artifacts`

## Status File Format Rules

- Use `[x]` for completed phases, `[ ]` for pending
- Include timestamps for completed phases: `[x] Phase 0 - Completed 2026-03-01`
- Format blockers with severity: `Critical`, `High`, `Medium`, `Resolved`
- Keep the file human-readable markdown
- Always end with a **Next Steps** section containing a specific `@PromptName` invocation
