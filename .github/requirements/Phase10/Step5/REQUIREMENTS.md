# Step5 Requirements - Generate Migration Artifacts

## Objective

Generate final migration artifacts from Step3/Step4 outputs for execution on the jumpbox/ZDM server.

## S5-01: Output contract

Required generated files under `Artifacts/Phase10-Migration/Step5/`:

- `README.md`
- `ZDM-Migration-Runbook.md`
- `zdm_migrate.rsp`
- `zdm_commands.sh`

## S5-02: Required input artifacts

1. `Artifacts/Phase10-Migration/Step3/Migration-Questionnaire.md`
2. `Artifacts/Phase10-Migration/Step4/Issue-Resolution-Log.md`
3. `Artifacts/Phase10-Migration/Step4/Verification-Results.md` (when available)
4. Relevant Step2 discovery outputs

## S5-03: Runtime portability constraints

1. Generated artifacts must not require `zdm-env.md` at runtime.
2. Document admin login flow (`ZDM_ADMIN_USER` then `sudo su - zdmuser`).

## S5-04: Environment variable model

1. Use environment variables for OCI identifiers and sensitive values.
2. Generated RSP and command artifacts must reference env vars and include validation guidance.

## S5-05: Version readiness gate

1. Include ZDM latest-stable verification as a pre-migration gate.
2. If ZDM version is outdated/undetermined, include a mandatory upgrade verification phase before migration execution.

## S5-06: README generated items

`README.md` should include at least:

1. Migration overview and assumptions.
2. Prerequisites checklist (including Step4 blocker resolution state when available).
3. Generated artifact index and how each file is used.
4. Quick-start execution flow from evaluation to migration and validation.
5. Security and credential handling notes.

## S5-07: Runbook generated items

`ZDM-Migration-Runbook.md` should include at least:

1. Pre-migration checklist and validation commands.
2. Source configuration tasks.
3. Target configuration tasks.
4. ZDM server preparation tasks (including admin-user to zdmuser flow).
5. Migration execution, monitoring, pause/resume, and switchover guidance.
6. Post-migration validation and rollback procedures.

## S5-08: RSP generated items

`zdm_migrate.rsp` should include:

1. Complete migration parameter set aligned to questionnaire decisions.
2. Environment-variable based references for sensitive and tenant-specific values.
3. Settings conditioned by migration type (online/offline) and discovered posture.

## S5-09: Command script generated items

`zdm_commands.sh` should include:

1. Ordered command flow for precheck/evaluation/migration/monitoring.
2. Guardrails and prerequisites checks before destructive phases.
3. Clear placeholders or env var references for required runtime values.
4. A standalone sample `zdmcli migrate database` call that can be executed directly (outside the wrapper script) for troubleshooting or manual execution.
