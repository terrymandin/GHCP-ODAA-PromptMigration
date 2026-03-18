# Common Requirements for Phase 10 (Step1-Step5)

## Scope

These requirements apply to all Phase10 ZDM prompts unless a step explicitly overrides them.

## CR-01: Source of truth precedence

1. Treat attached `zdm-env.md` as authoritative generation input when present.
2. Prefer `zdm-env.md` values over template defaults and examples.
3. If values conflict with discovery evidence, do not silently override. Explicitly report the mismatch.

## CR-02: Generation-time vs runtime boundary

1. `zdm-env.md` is generation-time input only.
2. Generated scripts and artifacts must not read, source, or parse `zdm-env.md` at runtime.

## CR-03: Execution guardrail

1. Prompts generate files only.
2. Prompts must not run migration, SSH, SQL, discovery, or remediation commands in VS Code.
3. Runtime actions are performed later by the user on the jumpbox/ZDM server.

## CR-04: Requirements-to-prompt traceability

1. Prompt changes are derived from shared and step-specific requirements.
2. Requirements should remain specific enough to regenerate prompts deterministically.

## CR-05: Variable scope for Phase10

DB-specific values used across Step1-Step5:

- `SOURCE_REMOTE_ORACLE_HOME`
- `SOURCE_ORACLE_SID`
- `TARGET_REMOTE_ORACLE_HOME`
- `TARGET_ORACLE_SID`
- `SOURCE_DATABASE_UNIQUE_NAME`
- `TARGET_DATABASE_UNIQUE_NAME`

ZDM-specific value used across Step1-Step5:

- `ZDM_HOME`

## CR-06: OCI CLI requirement

1. OCI CLI is not required for migration execution.

## CR-07: Step Prompt vs Example Prompt content boundary

1. Step prompt files (`Phase10-StepX-*.prompt.md`) are the canonical location for all operational instructions, guardrails, prerequisites, execution boundaries, and handoff details.
2. Example prompt files (`Phase10-Example-StepX-*.prompt.md`) are simplified invocation references and must contain exactly these four sections:
	- `Example Prompt`
	- `Expected Output`
	- `Requirements Summary`
	- `Next Steps`
3. Example prompt files must not add extra sections such as Prerequisites, Execution Boundary, or detailed implementation catalogs.
4. `Requirements Summary` in each example file must provide a concise overview derived from shared and step-specific requirements.
5. `Next Steps` should contain a concise handoff to the following Phase10 step.
6. If content is needed beyond those four sections, place it in the corresponding Step prompt file.

## CR-08: Per-step output README requirement

1. Each StepX output directory must include a `README.md` file in that step directory.
2. The step README must summarize:
	- generated files for that step,
	- what the user should run later on the jumpbox/ZDM server,
	- where runtime outputs/logs/reports are written,
	- the success/failure signals to check.
3. Step-specific requirements may add extra README expectations, but may not remove this baseline requirement.

## CR-09: Two-layer step requirements model

1. Each Phase10 step should separate user-facing intent requirements from script/implementation coding requirements.
2. User-facing requirements should focus on:
	- objective,
	- output contract,
	- execution boundary,
	- user-visible behavior and success criteria.
3. Implementation requirements should focus on:
	- coding patterns,
	- shell/sql implementation constraints,
	- required snippets/examples,
	- schema/format details for machine-readable outputs.
4. User-facing requirements are intended to be easier for non-implementation contributors to edit.
5. Implementation requirements must remain explicit enough to preserve deterministic prompt and script generation.

Recommended step-level file names:

- `USER-REQUIREMENTS.md` for user-facing requirements.
- `SYSTEM-REQUIREMENTS.md` for implementation/script-level requirements.

Naming rule:

- Use only `USER-REQUIREMENTS.md` and `SYSTEM-REQUIREMENTS.md` for every Phase10 step.

## CR-10: Regeneration inputs when requirements are split

1. Prompt regeneration must include both step files plus shared common requirements.
2. Shared/common requirements remain the global baseline and do not move into step-level files.
3. If user-facing and implementation requirements conflict, treat implementation requirements as controlling for generated script behavior, and document the conflict for user review.
4. Example prompts should continue to summarize combined requirements concisely, while detailed implementation constraints remain in the Step prompt.

## CR-11: Legacy file policy

1. `REQUIREMENTS.md` is no longer a canonical step requirement file for Phase10.
2. Step requirements must be authored and maintained only in `USER-REQUIREMENTS.md` and `SYSTEM-REQUIREMENTS.md`.
3. Avoid duplicating the same requirement text in both files; place each requirement in exactly one layer.
