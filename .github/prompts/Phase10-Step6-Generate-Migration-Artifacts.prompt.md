---
mode: agent
description: ZDM Step 6 - Generate final migration artifacts and iterate on zdm -eval until it succeeds or is explicitly skipped
---
# ZDM Migration Step 6: Generate Migration Artifacts

## Purpose

This step generates final migration artifacts for execution on the ZDM jumpbox. It derives content from Step 4 and Step 5 outputs and Step 3 discovery evidence, then runs `zdm -eval` iteratively until it succeeds or the user explicitly skips.

Generated artifacts under `Artifacts/Phase10-Migration/Step6/` (S6-01):
- `README.md`
- `ZDM-Migration-Runbook.md`
- `zdm_migrate.rsp`
- `zdm_commands.sh`

Conditional artifact:
- `Issue-Resolution-Log.md`  created only when the user explicitly skips `zdm -eval`; logs the skip decision and all outstanding eval errors.

---

## Execution Model

This step runs under the **Remote-SSH execution model** (CR-03): VS Code is connected to the ZDM jumpbox as `zdmuser`, and Copilot generates all artifacts using file tools and iterates `zdm -eval` in the terminal until it passes.

- All outputs are written to `Artifacts/Phase10-Migration/Step6/` (git-ignored). No generated files are committed or create PRs.
- OCI CLI is not required for migration execution (CR-06).
- Generated scripts and artifacts must not read, source, or parse config artifacts or `zdm-env.md` at runtime (CR-02).
- Admin login flow: connect as `ZDM_ADMIN_USER`, then `sudo su - zdmuser` to reach the `zdmuser` context (S6-03).
- **Environment scope (CR-13):** This prompt step is intended for **development and non-production environments only**. Do not run Copilot agent steps directly against production systems. Generated scripts (`zdm_commands.sh`, `zdm_migrate.rsp`) are safe to copy to production once reviewed and tested in development — run them manually on production; do not re-run this prompt on production.

Input precedence rules (CR-01):
1. `Artifacts/Phase10-Migration/Step4/Migration-Decisions.md`  confirmed RSP parameter decisions from Step 4.
2. `Artifacts/Phase10-Migration/Step5/Issue-Resolution-Log.md`  blocker resolution state from Step 5.
3. `Artifacts/Phase10-Migration/Step5/Verification-Results.md`  verification outcomes (when available).
4. `Artifacts/Phase10-Migration/Step3/db-config.md`  DB and ZDM variables.
5. `Artifacts/Phase10-Migration/Step2/ssh-config.md`  SSH connectivity variables.
6. Step 3 discovery outputs  observed runtime state from discovery scripts.
7. `zdm-env.md` (when explicitly attached)  legacy override with higher precedence than step artifacts.
8. If configured intent conflicts with discovery evidence, keep both: generate artifacts aligned to the configured intent and explicitly document the mismatch.
9. Placeholder values containing `<...>` are treated as unset.

---

## First Action: Display Environment Safety Banner (CR-13.3)

Before doing anything else, display the following banner in the chat:

```
⚠ ENVIRONMENT SAFETY: This prompt is for development/non-production use only.
Do not run against production. Generated scripts may be copied to production
once reviewed and tested — run them manually there.
```

---

## Prerequisites

Before running this prompt:
1.  Complete `@Phase10-Step1-Setup-Remote-SSH`  VS Code is connected via Remote-SSH as `zdmuser`
2.  Complete `@Phase10-Step2-Configure-SSH-Connectivity`  `Artifacts/Phase10-Migration/Step2/ssh-config.md` exists
3.  Complete `@Phase10-Step3-Generate-Discovery-Scripts`  discovery reports exist in `Artifacts/Phase10-Migration/Step3/Discovery/`
4.  Complete `@Phase10-Step4-Discovery-Questionnaire`  `Artifacts/Phase10-Migration/Step4/Migration-Decisions.md` exists
5.  Complete `@Phase10-Step5-Fix-Issues`  `Artifacts/Phase10-Migration/Step5/Verification-Results.md` shows all-PASS

---

## How to Use This Prompt

Attach the Step 4 and Step 5 artifacts and run this prompt:

```
@Phase10-Step6-Generate-Migration-Artifacts

Generate final migration artifacts from Step 4 and Step 5 outputs.

## Configuration Artifacts (read-only)
#file:Artifacts/Phase10-Migration/Step2/ssh-config.md
#file:Artifacts/Phase10-Migration/Step3/db-config.md

## Step 4 Input
#file:Artifacts/Phase10-Migration/Step4/Migration-Decisions.md

## Step 5 Inputs
#file:Artifacts/Phase10-Migration/Step5/Issue-Resolution-Log.md
#file:Artifacts/Phase10-Migration/Step5/Verification-Results.md

## Step 3 Discovery Inputs (attach most recent versions)
#file:Artifacts/Phase10-Migration/Step3/Discovery/source/source-discovery-<timestamp>.json
#file:Artifacts/Phase10-Migration/Step3/Discovery/target/target-discovery-<timestamp>.json
#file:Artifacts/Phase10-Migration/Step3/Discovery/server/server-discovery-<timestamp>.json

## Optional: Legacy override
#file:zdm-env.md
```

---

## Execution Phases

This prompt has two distinct phases:

```

  Step 6: Generate Migration Artifacts                   

  Phase 1  Generation                                   
    1. Read Step 4 decisions and Step 5 resolution log   
    2. Generate zdm_migrate.rsp from parameter set       
    3. Generate zdm_commands.sh with eval/migrate flow   
    4. Generate ZDM-Migration-Runbook.md                 
    5. Generate README.md                                
    6. Run quality gate (bash -n, shellcheck)            
                                                        
  Phase 2  Evaluation Loop                             
    7. Run zdm -eval and capture output                  
    8. Eval passes?  Proceed to completion              
    9. Eval fails?  Remediate + re-run zdm -eval        
   10. User skips?  Log skip + outstanding errors       
                Proceed to completion                   

```

---

## Part 1: Generate `zdm_migrate.rsp`

Write `Artifacts/Phase10-Migration/Step6/zdm_migrate.rsp` with a complete migration parameter set (S6-08):

1. All parameters aligned to `Migration-Decisions.md` answers from Step 4.
2. Use environment variables for sensitive and tenant-specific values (S6-04):
   ```
   SOURCEDATABASESERVICENAME=${SOURCE_DATABASE_SERVICE_NAME}
   TARGETDATABASESERVICENAME=${TARGET_DATABASE_SERVICE_NAME}
   OCIAUTHENTICATIONDETAILS_TENANCYOCID=${OCI_TENANCY_OCID}
   OCIAUTHENTICATIONDETAILS_USERID=${OCI_USER_OCID}
   ```
3. Settings conditioned on migration type (online / offline) and discovered database posture.
4. Include validation notes for each required parameter indicating which env var or config artifact to populate before execution.

---

## Part 2: Generate `zdm_commands.sh`

Write `Artifacts/Phase10-Migration/Step6/zdm_commands.sh` with the ordered command flow (S6-09):

1. **Configuration section**  declare all required environment variables with empty defaults and validation:
   ```bash
   #!/bin/bash
   # ZDM Migration Command Script
   # Run as zdmuser on the ZDM server
   set -euo pipefail

   #  Required Environment Variables 
   # Populate these before running. Empty values will cause validation to fail.
   : "${ZDM_HOME:?ZDM_HOME must be set}"
   : "${SOURCE_DATABASE_SERVICE_NAME:?SOURCE_DATABASE_SERVICE_NAME must be set}"
   : "${TARGET_DATABASE_SERVICE_NAME:?TARGET_DATABASE_SERVICE_NAME must be set}"
   ```

2. **Ordered command flow**:
   - Prerequisite checks (ZDM home exists, response file present, env vars set)
   - Version readiness gate: verify ZDM version; include upgrade check if version is outdated or undetermined (S6-05)
   - `zdm -eval` phase
   - `zdmcli migrate database` phase  guarded behind confirmation prompt
   - Monitoring phase (`zdmcli query jobid`)
   - Post-migration validation steps
   - Switchover guidance (for online migrations)

3. **Guardrails before destructive phases** (S6-09): require explicit user confirmation before triggering `zdmcli migrate database`:
   ```bash
   echo "  About to start migration. Type YES to proceed:"
   read -r CONFIRM
   [[ "${CONFIRM}" != "YES" ]] && { echo "Aborted."; exit 0; }
   ```

4. **Standalone `zdmcli migrate database` call**  include a clearly-commented standalone example outside all function wrappers for direct troubleshooting (S6-09):
   ```bash
   #  STANDALONE EXAMPLE (run directly for troubleshooting) 
   # Substitute all <placeholder> values before running.
   # zdmcli migrate database \
   #   -sourcedb <SOURCE_DB_UNIQUE_NAME> \
   #   -sourcenode <ZDM_SERVER_HOST> \
   #   -srcauth zdmauth \
   #   -srcarg1 user:<SOURCE_SSH_USER> \
   #   -srcarg2 identity_file:<~/.ssh/source.pem> \
   #   -srcarg3 sudo_location:/usr/bin/sudo \
   #   -targetnode <TARGET_HOST> \
   #   -tgtauth zdmauth \
   #   -tgtarg1 user:<TARGET_SSH_USER> \
   #   -tgtarg2 identity_file:<~/.ssh/target.pem> \
   #   -tgtarg3 sudo_location:/usr/bin/sudo \
   #   -rsp "${ZDM_HOME}/rhp/zdm_migrate.rsp" \
   #   -eval
   ```

---

## Part 3: Generate `ZDM-Migration-Runbook.md`

Write `Artifacts/Phase10-Migration/Step6/ZDM-Migration-Runbook.md` (S6-07):

1. **Pre-migration checklist and validation commands**  confirm all Step 5 blockers resolved, discovery refreshed, configuration artifacts in place.
2. **Source configuration tasks**  supplemental logging, ARCHIVELOG mode, force logging, source backup location.
3. **Target configuration tasks**  wallet/credential setup, TNS/connectivity, target pre-validation.
4. **ZDM server preparation tasks**  admin user  `sudo su - zdmuser` flow (S6-03), ZDM home verification, OCI config check, SSH key locations under `/home/zdmuser/.ssh/`.
5. **Migration execution**  `zdm -eval`  `zdmcli migrate database`  monitoring with `zdmcli query jobid`.
6. **Pause/resume operations**  `zdmcli pause jobid` / `zdmcli resume jobid` usage.
7. **Switchover guidance**  applicable for online migration; confirm data guard setup and trigger switchover.
8. **Post-migration validation**  confirm data integrity, application connectivity, and operational state.
9. **Rollback procedures**  pre-requisites for rollback, conditions, steps, verification.

---

## Part 4: Generate `README.md`

Write `Artifacts/Phase10-Migration/Step6/README.md` (CR-07, S6-06):

1. **Migration overview and assumptions**  source/target summary from Step 4 decisions, migration type (online/offline).
2. **Prerequisites checklist**  all Steps 15 completed; Step 5 blocker resolution state from `Verification-Results.md` when available.
3. **Generated artifact index**  each file, its purpose, and how it is used:
   - `zdm_migrate.rsp`  ZDM response file (pass with `-rsp` flag)
   - `zdm_commands.sh`  Ordered execution guide; run as `zdmuser` on ZDM server
   - `ZDM-Migration-Runbook.md`  Full operator runbook (pre/execute/validate/rollback)
4. **Quick-start execution flow**  from evaluation to migration to post-migration validation.
5. **Security and credential handling**  no secrets in files; use env vars; key file paths under `/home/zdmuser/.ssh/`; admin user  `sudo su - zdmuser` login flow.
6. **Where runtime outputs are written**  all artifacts under `Artifacts/Phase10-Migration/Step6/`; ZDM job logs under `$ZDM_HOME/log/`.
7. **Success signals**: `zdm -eval` exits 0; `zdmcli migrate database` job completes; post-migration validation passes.
8. **Failure signals**: eval blocking errors; migration job FAILED state; post-migration validation failures.

---

## Part 5: Generation Quality Gate (CR-11)

After all artifacts are written to disk, run bash syntax validation in the jumpbox terminal:

1. **Mandatory  bash syntax check**:
   ```bash
   bash -n ~/Artifacts/Phase10-Migration/Step6/zdm_commands.sh && echo "OK" || echo "FAIL"
   ```

2. **Optional  shellcheck** (run if available):
   ```bash
   if command -v shellcheck &>/dev/null; then
     shellcheck ~/Artifacts/Phase10-Migration/Step6/zdm_commands.sh
   fi
   ```

3. Any syntax error is a **stop-ship condition**: fix and re-run until all checks pass.

4. Include a concise validation evidence block in the final chat output listing the script checked and PASS/FAIL status.

---

## Pre-Execution Risk Banner (CR-13.3)

Before beginning the `zdm -eval` iteration loop, always display the following banner. It is mandatory — do not skip or abbreviate it.

```
⚠ ENVIRONMENT SAFETY WARNING

This Copilot agent prompt is intended to run in development/non-production
environments only. Do not run this prompt directly against a production system.

Generated scripts (zdm_commands.sh, zdm_migrate.rsp) are safe to copy to
production once reviewed and tested in development. For production use:
review scripts, copy them to the production host, and run manually —
do not re-run this prompt on production.

The following artifacts operate at Oracle Home / OS scope and will affect
  ALL databases sharing that Oracle Home or host — not just the migration target:
    - zdm_commands.sh  →  OS/Oracle-Home scope
      (ZDM migration engine reconfigures redo apply, Data Guard, and network
       parameters that apply at the Oracle Home or OS level on source and target)

Type CONFIRM to proceed to zdm -eval, or press Enter to stop here and
review generated artifacts manually before running anything.
```

Do **not** begin the `zdm -eval` loop until the user types `CONFIRM`. If the user does not type `CONFIRM`, stop at this banner — all artifacts remain on disk for manual review and execution.

---

## Part 6: zdm -eval Iteration Loop (S6-08)

After the quality gate passes, begin the evaluation loop:

1. **Before running `zdm -eval`**, confirm both prerequisite layers have passed:
   - **Layer 1**: `Scripts/preflight_l1_infrastructure.sh` results in `Artifacts/Phase10-Migration/Step5/Verification-Results.md` show all-PASS under `### Layer 1 Infrastructure Pre-flight`. If any Layer 1 check is FAIL, surface the failures and stop — do not submit `zdm -eval`.
   - **Layer 2**: `Artifacts/Phase10-Migration/Step5/Verification-Results.md` from `verify_fixes.sh` shows all blocker checks PASS. If any Layer 2 blocker is outstanding, surface them and stop.

   Once both layers are confirmed PASS, run `zdm -eval` using the generated response file and capture the full output.
2. If evaluation **succeeds** (exit code 0 / no blocking errors), surface the success output and proceed to the Completion Checklist.
3. If evaluation **fails**, surface the error output and triage the failure against the CR-14 prerequisite cache (`Artifacts/Phase10-Migration/ZDM-Doc-Checks/prerequisites-<zdm-version>.md`):
   - If the failure **matches a cache entry**: apply the remediation guidance from that cache row (re-run the relevant fix script from Step 5 or adjust `zdm_migrate.rsp`), then re-run `zdm -eval`.
   - If the failure is **NOT in the cache**: add it to the cache file under the appropriate layer section, noting it as `[zdm-eval-feedback <date>]` per CR-14-F. Then attempt remediation (adjust `zdm_migrate.rsp` or create a new fix script) and re-run `zdm -eval`.
4. Repeat the fix-and-retry loop until either:
   - `zdm -eval` exits successfully, **or**
   - The user explicitly instructs the agent to **skip** evaluation (for example: responds with "skip eval" or confirms they want to proceed despite failures).
5. If the user **skips**: create `Artifacts/Phase10-Migration/Step6/Issue-Resolution-Log.md` logging the skip decision and all outstanding eval errors before continuing.
6. Do not proceed to full migration execution (`zdmcli migrate database`) from this prompt. That is an operator-driven step using `zdm_commands.sh`.

---

## Output Files

```
Artifacts/Phase10-Migration/
 Step6/
     README.md                        # Migration overview, prereqs, artifact index, quick-start
     ZDM-Migration-Runbook.md         # Full operator runbook (pre/execute/validate/rollback)
     zdm_migrate.rsp                  # ZDM response file with migration parameters
     zdm_commands.sh                  # Ordered command script for migration execution
     Issue-Resolution-Log.md          # Created only if user skips zdm -eval
```

All files are git-ignored. No outputs are committed or create PRs.

---

## Completion Checklist

Before handing off artifacts to the operator:

- [ ] All four required files generated: `README.md`, `ZDM-Migration-Runbook.md`, `zdm_migrate.rsp`, `zdm_commands.sh`
- [ ] `zdm_commands.sh` passes `bash -n` syntax check
- [ ] `zdm -eval` exits 0 (or skip is explicitly logged in `Issue-Resolution-Log.md`)
- [ ] All Step 5 blockers confirmed resolved in `Verification-Results.md`
- [ ] Security and credential notes included in `README.md`
- [ ] Standalone `zdmcli migrate database` example present in `zdm_commands.sh`

---

## Final Handoff

After all artifacts are generated, validated, and `zdm -eval` succeeds (or is explicitly skipped):

> **ZDM Migration Artifacts are complete.** Use the generated artifacts in `Artifacts/Phase10-Migration/Step6/` to execute the migration from the jumpbox terminal:
>
> 1. Review `ZDM-Migration-Runbook.md` for the full execution sequence.
> 2. Set required environment variables documented in `zdm_commands.sh`.
> 3. Run `zdm_commands.sh` as `zdmuser` on the ZDM server for guided execution.
> 4. Or use the standalone `zdmcli migrate database` example in `zdm_commands.sh` for manual execution.
>
> All runtime logs are written to `$ZDM_HOME/log/`. All generated artifacts remain under `Artifacts/Phase10-Migration/Step6/` (git-ignored).