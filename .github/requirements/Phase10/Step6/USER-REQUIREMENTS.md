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

## S6-03: README generated items

`README.md` should include at least:

1. Migration overview and assumptions.
2. Prerequisites checklist (including Step5 blocker resolution state when available).
3. Generated artifact index and how each file is used.
4. Quick-start execution flow from evaluation to migration and validation.
5. Security and credential handling notes.

## S6-04: Runbook generated items

`ZDM-Migration-Runbook.md` should include at least:

1. Pre-migration checklist and validation commands.
2. Source configuration tasks.
3. Target configuration tasks.
4. ZDM server preparation tasks (including admin-user to zdmuser flow).
5. Migration execution, monitoring, pause/resume, and switchover guidance.
6. Post-migration validation and rollback procedures.

## S6-05: Iterate until `zdm -eval` succeeds or user skips

`zdm -eval` is **Layer 3** in the CR-14 three-layer pre-validation model. It must only be submitted after Layer 1 (infrastructure) and Layer 2 (database prerequisite queries) have both passed. It is the final and authoritative gatekeeper for ZDM-internal checks that cannot be externally reproduced.

After running `zdm -eval`, the agent must not proceed to migration execution until the evaluation phase passes. The expected behavior is:

1. Confirm Layer 1 (`preflight_l1_infrastructure.sh`) and Layer 2 (compatibility gate in Step4 + `verify_fixes.sh` from Step5) have both passed before submitting. If either layer has outstanding failures, surface them and stop.
2. Run the `zdm -eval` command and capture its output.
3. If the evaluation **succeeds** (all phases show `PRECHECK_PASSED`), continue to the next step.
4. If the evaluation **fails**, triage the failure against the CR-14 prerequisite cache (`Artifacts/Phase10-Migration/ZDM-Doc-Checks/prerequisites-<zdm-version>.md`):
   - If the failure maps to a **Layer 1 check** in the cache: fix at Layer 1 (regenerate `preflight_l1_infrastructure.sh` or apply the fix directly), re-run Layer 1, then re-run `zdm -eval`.
   - If the failure maps to a **Layer 2 check** in the cache: generate or update the relevant fix script from Step5 conventions, apply the fix, re-run `verify_fixes.sh`, then re-run `zdm -eval`.
   - If the failure is **not in the cache**: add it to the cache under the appropriate layer, noting it as `[zdm-eval-feedback <date>]` per CR-14-F. Then apply the fix and re-run `zdm -eval`. This keeps the cache growing with real-world failures so future runs catch the issue earlier.
5. Repeat the fix-and-retry loop until either:
   - The `zdm -eval` exits successfully, **or**
   - The user explicitly instructs the agent to **skip** the evaluation.
6. If the user skips, log the skip decision and the outstanding eval errors in `Artifacts/Phase10-Migration/Step6/Issue-Resolution-Log.md` before continuing.
