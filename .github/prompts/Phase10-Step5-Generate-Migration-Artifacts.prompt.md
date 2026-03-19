---
agent: agent
description: ZDM Step 5 - generate final migration artifacts from Step3 and Step4 outputs
---
# ZDM Migration Step 5: Generate Migration Artifacts

## Purpose
Generate final migration artifacts for execution on the jumpbox and ZDM server by deriving content from Step3 and Step4 outputs and relevant Step2 discovery evidence.

Generate exactly these files under `Artifacts/Phase10-Migration/Step5/`:
1. `README.md`
2. `ZDM-Migration-Runbook.md`
3. `zdm_migrate.rsp`
4. `zdm_commands.sh`

## Execution Boundary (Generation Only)
This prompt is generation-only.
- Create or update files only.
- Do not run migration, SSH, SQL, discovery, verification, or remediation commands from VS Code.
- Runtime execution occurs later by the user on the jumpbox and ZDM server.

`zdm-env.md` rules:
- Use `zdm-env.md` only as generation-time input when attached.
- Do not make generated artifacts read, source, or parse `zdm-env.md` at runtime.

## Inputs and Precedence Rules
Required inputs:
1. `Artifacts/Phase10-Migration/Step3/Migration-Questionnaire.md`
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

## Next-Step Handoff
After artifacts are generated and reviewed:
1. Commit Step5 artifacts to the repository.
2. Execute runtime commands on the jumpbox or ZDM server only.
3. Use `Artifacts/Phase10-Migration/Step5/ZDM-Migration-Runbook.md` and `Artifacts/Phase10-Migration/Step5/zdm_commands.sh` as the runtime execution guide.

## Usage Command
```text
@Phase10-ZDM-Step5-Generate-Migration-Artifacts

Generate final migration artifacts from Step3 and Step4 outputs.

## Optional Generation Input
#file:zdm-env.md

## Step3 Input
#file:Artifacts/Phase10-Migration/Step3/Migration-Questionnaire.md

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
