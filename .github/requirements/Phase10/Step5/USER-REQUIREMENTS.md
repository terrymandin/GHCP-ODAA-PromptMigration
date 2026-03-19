# Step5 User Requirements - Generate Migration Artifacts

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
