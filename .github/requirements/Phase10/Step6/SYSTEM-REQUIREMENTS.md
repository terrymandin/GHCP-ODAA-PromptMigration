# Step6 System Requirements - Migration Artifact Implementation

## Scope

This file defines implementation-level constraints for generated Step5 runtime artifacts.

## S6-06: Runtime portability constraints

1. Generated artifacts must not require `zdm-env.md` at runtime.
2. Document admin login flow (`ZDM_ADMIN_USER` then `sudo su - zdmuser`).

## S6-07: Environment variable model

1. Use environment variables for OCI identifiers and sensitive values.
2. Generated RSP and command artifacts must reference env vars and include validation guidance.

## S6-08: Version readiness gate

1. Include ZDM latest-stable verification as a pre-migration gate.
2. If ZDM version is outdated/undetermined, include a mandatory upgrade verification phase before migration execution.

## S6-09: RSP generated items

`zdm_migrate.rsp` should include:

1. Complete migration parameter set aligned to questionnaire decisions.
2. Environment-variable based references for sensitive and tenant-specific values.
3. Settings conditioned by migration type (online/offline) and discovered posture.

## S6-10: Command script generated items

`zdm_commands.sh` should include:

1. Ordered command flow for precheck/evaluation/migration/monitoring.
2. Guardrails and prerequisites checks before destructive phases.
3. Clear placeholders or env var references for required runtime values.
4. A standalone sample `zdmcli migrate database` call that can be executed directly (outside the wrapper script) for troubleshooting or manual execution.
