---
agent: agent
description: ZDM Step 5 - generate final migration artifacts and run zdm -eval on the jumpbox
---
# ZDM Migration Step 5: Generate Migration Artifacts

## Purpose
Generate final migration artifacts for execution on the jumpbox and ZDM server by deriving content from Step3 and Step4 outputs and relevant Step2 discovery evidence. After generating artifacts, execute `zdm -eval` on the jumpbox and iterate until it succeeds or the user explicitly skips.

Generate exactly these files under `Artifacts/Phase10-Migration/Step5/`:
1. `README.md`
2. `ZDM-Migration-Runbook.md`
3. `zdm_migrate.rsp`
4. `zdm_commands.sh`

## Remote-SSH Execution Prerequisites
This prompt uses the **Remote-SSH execution** model:
- VS Code must be connected to the ZDM jumpbox via the Remote-SSH extension.
- All terminal commands run directly on the jumpbox as `zdmuser`.
- Copilot iterates and fixes errors automatically; maximum retry attempts per failed command: **5**.
- All generated outputs are written to `Artifacts/` (git-ignored) using file tools. Do not commit generated artifacts.
- `zdm-env.md` is generation-time input only. Generated scripts and artifacts must not read, source, or parse `zdm-env.md` at runtime.

## Execution Boundary (Generation + Evaluation)
This prompt has two phases:
1. **Generation phase**: Create or update the four required artifacts in `Artifacts/Phase10-Migration/Step5/`.
2. **Evaluation phase**: After generation, run `zdm -eval` on the jumpbox and iterate remediation until evaluation passes or the user explicitly skips.

Rules:
- Do not run full migration execution (beyond `zdm -eval`), SQL, or SSH-based discovery commands from VS Code.
- Use `zdm-env.md` only as generation-time input when attached.
- Do not make generated artifacts read, source, or parse `zdm-env.md` at runtime.

## Inputs and Precedence Rules
Required inputs:
1. `Artifacts/Phase10-Migration/Step3/Migration-Decisions.md`
2. `Artifacts/Phase10-Migration/Step4/Issue-Resolution-Log.md`
3. `Artifacts/Phase10-Migration/Step4/Verification-Results.md` (when available)
4. Relevant Step2 discovery outputs

Precedence and conflict handling:
1. If attached, treat `zdm-env.md` as authoritative generation input.
2. Prefer `zdm-env.md` values over template defaults/examples.
3. If `zdm-env.md` conflicts with discovery evidence or prior-step artifacts, explicitly report the mismatch in generated documentation (do not silently override).

Shared variable scope across Step1-Step5:
- `SOURCE_REMOTE_ORACLE_HOME`
- `SOURCE_ORACLE_SID`
- `TARGET_REMOTE_ORACLE_HOME`
- `TARGET_ORACLE_SID`
- `SOURCE_DATABASE_UNIQUE_NAME`
- `TARGET_DATABASE_UNIQUE_NAME`
- `ZDM_HOME`

## Required Outputs
Generate exactly these artifacts in `Artifacts/Phase10-Migration/Step5/`:
1. `README.md`
2. `ZDM-Migration-Runbook.md`
3. `zdm_migrate.rsp`
4. `zdm_commands.sh`

Conditional output:
- `Artifacts/Phase10-Migration/Step5/Issue-Resolution-Log.md` — created when the user explicitly skips `zdm -eval`. Log the skip decision and all outstanding eval errors before proceeding.

Portability constraints:
1. Generated artifacts must be runtime-portable and must not depend on `zdm-env.md`.
2. Document login flow as `ZDM_ADMIN_USER`, then `sudo su - zdmuser`.
3. State that OCI CLI is not required for this migration execution flow.

Environment variable model:
1. Use environment variables for OCI identifiers and sensitive values.
2. RSP and command artifacts must reference environment variables and include validation guidance for required values before execution.

Version readiness gate:
1. Include a pre-migration gate to verify ZDM latest stable readiness.
2. If ZDM version is outdated or undetermined, include a mandatory upgrade-verification phase before migration execution.

## Generated Items and Content Catalogs
For each artifact, generate at least the following content.

`README.md` must include:
1. Migration overview and assumptions.
2. Prerequisites checklist, including Step4 blocker-resolution state when available.
3. Artifact index and usage for each generated file.
4. Quick-start flow from evaluation to migration and validation.
5. Security and credential-handling notes.
6. Where runtime outputs, logs, and reports are written.
7. Success and failure signals to check.

`ZDM-Migration-Runbook.md` must include:
1. Pre-migration checklist and validation commands.
2. Source configuration tasks.
3. Target configuration tasks.
4. ZDM server preparation tasks, including admin-user to zdmuser flow.
5. Migration execution, monitoring, pause and resume, and switchover guidance.
6. Post-migration validation and rollback procedures.

`zdm_migrate.rsp` must include:
1. Complete migration parameter set aligned to questionnaire decisions.
2. Environment-variable references for sensitive and tenant-specific values.
3. Settings conditioned by migration type (online or offline) and discovered posture.

`zdm_commands.sh` must include:
1. Ordered command flow for precheck, evaluation, migration, and monitoring.
2. Guardrails and prerequisite checks before destructive phases.
3. Clear placeholders or environment variable references for required runtime values.
4. One standalone sample `zdmcli migrate database` command executable directly outside wrapper functions for troubleshooting or manual execution.

Traceability requirement:
1. Keep all generated Step5 artifacts explicitly aligned to shared Phase10 requirements and Step5 requirements.

## Generation Quality Gate
After generating `zdm_commands.sh`:
1. Run `bash -n zdm_commands.sh` to validate shell syntax.
2. If `shellcheck` is available, run it and resolve all actionable findings.
3. Any failed validation check is a stop-ship condition; fix and re-run until all required checks pass.
4. Include a concise validation evidence summary in chat listing checks run and pass/fail status.

## zdm -eval Iteration Loop
After all artifacts are generated and the quality gate passes:
1. Run the `zdm -eval` command using the generated response file and capture its full output.
2. If evaluation **succeeds** (exit code 0 / no blocking errors), surface the success output and proceed to the Next-Step Handoff.
3. If evaluation **fails**, surface the error output, attempt remediation (re-run relevant fix scripts from Step4, adjust `zdm_migrate.rsp`), and re-run `zdm -eval`.
4. Repeat the fix-and-retry loop until either:
   - `zdm -eval` exits successfully, **or**
   - The user explicitly instructs the agent to **skip** evaluation (for example, by responding with "skip eval" or confirming they want to proceed despite failures).
5. If the user skips, log the skip decision and all outstanding eval errors in `Artifacts/Phase10-Migration/Step5/Issue-Resolution-Log.md` before continuing.
6. Do not proceed to full migration execution from this prompt.

## Next-Step Handoff
After artifacts are generated, validated, and `zdm -eval` succeeds (or is explicitly skipped):
1. Step5 artifacts are git-ignored and remain in `Artifacts/Phase10-Migration/Step5/` only. Do not commit them.
2. Execute runtime migration commands on the jumpbox or ZDM server using the generated artifacts.
3. Use `Artifacts/Phase10-Migration/Step5/ZDM-Migration-Runbook.md` and `Artifacts/Phase10-Migration/Step5/zdm_commands.sh` as the runtime execution guide.

## Usage Command
```text
@Phase10-ZDM-Step5-Generate-Migration-Artifacts

Generate final migration artifacts from Step3 and Step4 outputs.

## Optional Generation Input
#file:zdm-env.md

## Step3 Input
#file:Artifacts/Phase10-Migration/Step3/Migration-Decisions.md

## Step4 Inputs
#file:Artifacts/Phase10-Migration/Step4/Issue-Resolution-Log.md
#file:Artifacts/Phase10-Migration/Step4/Verification-Results.md

## Relevant Step2 Discovery Inputs
#file:Artifacts/Phase10-Migration/Step2/Discovery/source/source-discovery-<timestamp>.json
#file:Artifacts/Phase10-Migration/Step2/Discovery/target/target-discovery-<timestamp>.json
#file:Artifacts/Phase10-Migration/Step2/Discovery/server/server-discovery-<timestamp>.json

## Output Directory
Artifacts/Phase10-Migration/Step5/
```
