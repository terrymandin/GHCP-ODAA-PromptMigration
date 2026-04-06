# Step6 User Requirements - Generate Migration Artifacts

## Objective

Generate final migration artifacts from Step4/Step5 outputs for execution on the jumpbox/ZDM server.

## S6-01: Output contract

Required generated files under `Artifacts/Phase10-Migration/Step6/`:

- `README.md`
- `ZDM-Migration-Runbook.md`
- `zdm_migrate.rsp`
- `zdm_commands.sh`

## S6-02: Required input artifacts

1. `Artifacts/Phase10-Migration/Step4/Migration-Decisions.md`
2. `Artifacts/Phase10-Migration/Step5/Issue-Resolution-Log.md`
3. `Artifacts/Phase10-Migration/Step5/Verification-Results.md` (when available)
4. Relevant Step3 discovery outputs

## S6-06: README generated items

`README.md` should include at least:

1. Migration overview and assumptions.
2. Prerequisites checklist (including Step5 blocker resolution state when available).
3. Generated artifact index and how each file is used.
4. Quick-start execution flow from evaluation to migration and validation.
5. Security and credential handling notes.

## S6-07: Runbook generated items

`ZDM-Migration-Runbook.md` should include at least:

1. Pre-migration checklist and validation commands.
2. Source configuration tasks.
3. Target configuration tasks.
4. ZDM server preparation tasks (including admin-user to zdmuser flow).
5. Migration execution, monitoring, pause/resume, and switchover guidance.
6. Post-migration validation and rollback procedures.

## S6-08: Iterate until `zdm -eval` succeeds or user skips

After running `zdm -eval`, the agent must not proceed to migration execution until the evaluation phase passes. The expected behavior is:

1. Run the `zdm -eval` command and capture its output.
2. If the evaluation **succeeds** (exit code 0 / no blocking errors), continue to the next step.
3. If the evaluation **fails**, surface the errors from the output, attempt remediation (e.g., re-running relevant fix scripts from Step5, adjusting the response file), and re-run `zdm -eval`.
4. Repeat the fix-and-retry loop until either:
   - The `zdm -eval` exits successfully, **or**
   - The user explicitly instructs the agent to **skip** the evaluation (e.g., responds with "skip eval" or confirms they want to proceed despite failures).
5. If the user skips, log the skip decision and the outstanding eval errors in `Artifacts/Phase10-Migration/Step6/Issue-Resolution-Log.md` before continuing.
