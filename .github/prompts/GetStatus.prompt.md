---
mode: agent
description: Get the current Oracle Database@Azure migration status
---

# Oracle Database@Azure Migration Status

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
- [ ] Phase 10: ZDM profile and route selected
- [ ] Phase 10: Required remediation and validation passed
- [ ] Phase 10: Response file and eval command generated
- [ ] Phase 10: Customer-run ZDM eval passed

## Next Step
Run `@Phase0-ODAA-Readiness` to begin the migration readiness assessment.
```

### If `Artifacts/Report-Status.md` exists
Read its content, summarize the current state, and ensure it contains:

1. **Executive Summary** - source database, target ODAA environment, overall completion %
2. **Phase completion checklist** - `[x]` for completed phases with timestamps, `[ ]` for pending
3. **Database configuration** - source and target roles, database name, and selected migration route; do not persist private endpoints
4. **ZDM readiness** - remediation, validation, artifact generation, and observed eval status
	- Record the assessment environment as `non_production` or `production`.
	- Treat an observed eval pass as an eval milestone only, not migration, cutover, fallback, rollback, or production readiness.
5. **Blockers and issues** - severity and current resolution state
6. **Next recommended step** - a prompt invocation for an earlier phase or an instruction to run the `Phase 10 ZDM Migration` custom agent for Phase 10

## Status File Format Rules

- Use `[x]` for completed phases, `[ ]` for pending
- Include timestamps for completed phases: `[x] Phase 0 - Completed 2026-03-01`
- Format blockers with text severity labels: `Critical`, `High`, or `Resolved`
- Keep the file human-readable markdown
- Always end with a **Next Steps** section containing a prompt invocation for an earlier phase or an instruction to run the `Phase 10 ZDM Migration` custom agent for Phase 10
