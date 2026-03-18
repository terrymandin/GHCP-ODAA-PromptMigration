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
