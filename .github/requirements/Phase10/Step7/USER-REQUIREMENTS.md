# Step7 User Requirements - Generate Migration Artifacts

## Objective

Generate final migration artifacts from Step6/Step7 outputs for execution on the jumpbox/ZDM server.

## S7-01: Output contract

Required generated files under `Artifacts/Phase10-Migration/Step7/`:

- `README.md`
- `ZDM-Migration-Runbook.md`
- `zdm_migrate.rsp`
- `zdm_commands.sh`
- `Rule-Validation-Report.md`

## S7-02: Required input artifacts

1. `Artifacts/Phase10-Migration/Step7/Migration-Decisions.md`
2. `Artifacts/Phase10-Migration/Step7/Issue-Resolution-Log.md`
3. `Artifacts/Phase10-Migration/Step7/Verification-Results.md` (when available)
4. Relevant Step5 discovery outputs

## S7-03: README generated items

`README.md` should include at least:

1. Migration overview and assumptions.
2. Prerequisites checklist (including Step7 blocker resolution state when available).
3. Generated artifact index and how each file is used.
4. Quick-start execution flow from evaluation to migration and validation.
5. Security and credential handling notes.

## S7-04: Runbook generated items

`ZDM-Migration-Runbook.md` should include at least:

1. Pre-migration checklist and validation commands.
2. Source configuration tasks.
3. Target configuration tasks.
4. ZDM server preparation tasks (including admin-user to zdmuser flow).
5. Migration execution, monitoring, pause/resume, and switchover guidance.
6. Post-migration validation and rollback procedures.
7. Datapatch failure recovery section (required when `PLATFORM_TYPE` is `EXACS` or `EXACC`): include a clearly labeled section titled "Datapatch Failure Recovery (ZDM_DATAPATCH_TGT)" that covers:
   - How to identify a `ZDM_DATAPATCH_TGT FAILED` status using `zdmcli query jobid <jobid>`.
   - Manual datapatch execution steps: SSH to each target node, set Oracle environment, run `sudo -u oracle $ORACLE_HOME/OPatch/datapatch -verbose` as oracle, and capture the log.
   - Common failure causes: missing prerequisite patches on target home, `sqlpatch.pm` incompatibility (MOS 1609718.1), stale datapatch registry entries.
   - Remediation for the `sqlpatch.pm` / `Unsupported named object type` error: apply the MOS 1609718.1 patch to the target Oracle home before re-running datapatch.
   - How to resume the ZDM job after manual datapatch completes: `zdmcli resume jobid <jobid>`.
   - Note that skipping datapatch leaves the target database in an inconsistent patch state and is not supported for production use.

## S7-05: Iterate until `zdm -eval` succeeds or user skips

`zdm -eval` is **Layer 3** in the CR-14 three-layer pre-validation model. It must only be submitted after Layer 1 (infrastructure) and Layer 2 (database prerequisite queries) have both passed. It is the final and authoritative gatekeeper for ZDM-internal checks that cannot be externally reproduced.

After running `zdm -eval`, the agent must not proceed to migration execution until the evaluation phase passes. The expected behavior is:

1. Confirm Layer 1 (`preflight_l1_infrastructure.sh`) and Layer 2 (compatibility gate in Step6 + `verify_fixes.sh` from Step7) have both passed before submitting. If either layer has outstanding failures, surface them and stop.
2. Run the `zdm -eval` command and capture its output.
3. If the evaluation **succeeds** (all phases show `PRECHECK_PASSED`), continue to the next step.
4. If the evaluation **fails**, triage the failure against the CR-14 prerequisite catalog file (`.github/requirements/Phase10/ZDM-Prerequisites/<version>/<method>.md`, loaded per CR-14-A):
   - If the failure maps to a **Layer 1 check** in the catalog: fix at Layer 1 (regenerate `preflight_l1_infrastructure.sh` or apply the fix directly), re-run Layer 1, then re-run `zdm -eval`.
   - If the failure maps to a **Layer 2 check** in the catalog: generate or update the relevant fix script from Step7 conventions, apply the fix, re-run `verify_fixes.sh`, then re-run `zdm -eval`.
   - If the failure is **not in the catalog**: add it to the catalog file under the appropriate layer, noting it as `[zdm-eval-feedback <date>]` per CR-14-D. Then apply the fix and re-run `zdm -eval`. This keeps the catalog growing with real-world failures so future runs catch the issue earlier.
5. Repeat the fix-and-retry loop until either:
   - The `zdm -eval` exits successfully, **or**
   - The user explicitly instructs the agent to **skip** the evaluation.
6. If the user skips, log the skip decision and the outstanding eval errors in `Artifacts/Phase10-Migration/Step7/Issue-Resolution-Log.md` before continuing.

## S7-06: Rule validation and continuation policy

1. Step7 must evaluate the deterministic rule catalog before final artifact completion and write results to `Rule-Validation-Report.md`.
2. If any BLOCKER rule fails, Step7 must halt and direct the user back to Step6 remediation before continuing.
3. Final chat summary must include:
   - rule catalog version used,
   - count of PASS/FAIL/WARN rules,
   - whether artifact generation continued or halted due to blocking rules.
