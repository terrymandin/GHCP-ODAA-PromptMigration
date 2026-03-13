---
mode: agent
description: Get the current Oracle Database@Azure migration status
---

# Oracle Database@Azure Migration â€” Status

## Instructions

Retrieve and display the current status of the Oracle Database@Azure migration.

### If `reports/Report-Status.md` does not exist
Create it with the following initial content, then display it:

```markdown
# Oracle Database@Azure Migration Status

**Status**: Not Started
**Last Updated**: <today's date>

## Phase Completion
- [ ] Phase 0: ODAA Readiness Assessment
- [ ] Phase 5: CIDR Range Planning
- [ ] Phase 6: Infrastructure as Code (Terraform)
- [ ] Phase 10 â€” Step 1: ZDM SSH Connectivity
- [ ] Phase 10 â€” Step 2: ZDM Discovery Scripts
- [ ] Phase 10 â€” Step 3: ZDM Migration Planning
- [ ] Phase 10 â€” Step 4: ZDM Issue Resolution
- [ ] Phase 10 â€” Step 5: ZDM Migration Artifacts

## Next Step
Run `@Phase0-ODAA-Readiness` to begin the migration readiness assessment.
```

### If `reports/Report-Status.md` exists
Read its content, summarize the current state, and ensure it contains:

1. **Executive Summary** â€” source database, target ODAA environment, overall completion %
2. **Phase completion checklist** â€” `[x]` for completed phases with timestamps, `[ ]` for pending
3. **Database configuration** â€” source host, target host, database name, migration method (ZDM/DataGuard/RMAN/DataPump/GoldenGate)
4. **ZDM readiness** (if applicable) â€” SSH connectivity status, discovery status, blockers resolved Y/N
5. **Blockers and issues** â€” severity (Critical / High / Medium), current resolution state
6. **Next recommended step** â€” specific `@PromptName` command to run next

## Status File Format Rules

- Use `[x]` for completed phases, `[ ]` for pending
- Include timestamps for completed phases: `[x] Phase 0 â€” Completed 2026-03-01`
- Format blockers with severity: `âŒ Critical`, `âš ï¸ High`, `âœ… Resolved`
- Keep the file human-readable markdown
- Always end with a **Next Steps** section containing a specific `@PromptName` invocation
