# Common Requirements for Phase 10 (Step1-Step7)

## Scope

These requirements apply to all Phase10 ZDM prompts unless a step explicitly overrides them.

## Canonical Phase10 Contract

1. Step sequence is fixed:
   - Step1: Setup Remote-SSH (local VS Code session)
   - Step2: Install/Verify ZDM (Remote-SSH jumpbox)
   - Step3: Configure SSH connectivity
   - Step4: Run discovery
   - Step5: Discovery questionnaire
   - Step6: Fix issues
   - Step7: Generate migration artifacts
2. Config artifacts are fixed:
   - `Artifacts/Phase10-Migration/Step3/ssh-config.md`
   - `Artifacts/Phase10-Migration/Step4/db-config.md`
3. Any prompt, requirement, or doc that conflicts with this contract is non-canonical and must be updated to match this file.

## CR-01: Source of truth precedence

1. Treat step configuration artifacts as the primary authoritative generation input (see CR-12):
   - `Artifacts/Phase10-Migration/Step3/ssh-config.md` for SSH connectivity variables.
   - `Artifacts/Phase10-Migration/Step4/db-config.md` for database and ZDM variables.
2. When `zdm-env.md` is explicitly attached, treat it as a legacy override with higher precedence than the step artifacts.
3. Prefer artifact or `zdm-env.md` values over template defaults and examples.
4. If values conflict with discovery evidence, do not silently override. Explicitly report the mismatch.

## CR-02: Generation-time vs runtime boundary

1. `zdm-env.md` is generation-time input only.
2. Generated scripts and artifacts must not read, source, or parse `zdm-env.md` at runtime.

## CR-03: Execution model

All Phase10 prompts use the **Remote-SSH execution** model **except Step1**:

1. VS Code is connected to the ZDM jumpbox via the Remote-SSH extension, with the terminal session running as `zdmuser`.
2. Copilot runs commands directly in the jumpbox terminal, iterating and fixing errors automatically.
3. All outputs are written to `Artifacts/` (git-ignored) using file tools. No outputs are committed to git.
4. Prompts must not perform irreversible or destructive actions without explicit user confirmation.
5. `zdm-env.md` is input to the prompt only. Generated scripts and artifacts must not read, source, or parse `zdm-env.md` at runtime.

**Step1 exception**: Step1 (Remote-SSH Setup) runs in the LOCAL VS Code session before any Remote-SSH connection is established. It uses the local PowerShell terminal (Windows primary). Step1 must not issue jumpbox commands.

## CR-04: Requirements-to-prompt traceability

1. Prompt changes are derived from shared and step-specific requirements.
2. Requirements should remain specific enough to regenerate prompts deterministically.

## CR-05: Variable scope for Phase10

DB-specific values used across Step4-Step7:

- `SOURCE_REMOTE_ORACLE_HOME`
- `SOURCE_ORACLE_SID`
- `TARGET_REMOTE_ORACLE_HOME`
- `TARGET_ORACLE_SID`
- `SOURCE_DATABASE_UNIQUE_NAME`
- `TARGET_DATABASE_UNIQUE_NAME`
- `SOURCE_GI_TYPE` (auto-detected in Step5 source discovery: `standalone` or `grid`; controls `-sourcesid` vs `-sourcedb` CLI flag in Step7)
- `TGT_REDODG` (target ASM redo disk group name; required RSP parameter for EXACS/EXACC platform types)
- `TGT_RECODG` (target ASM recovery/FRA disk group name; required RSP parameter for EXACS/EXACC platform types)

ZDM-specific value used across Step4-Step7:

- `ZDM_HOME`

Variable-to-artifact mapping:

- SSH variables (`SOURCE_HOST`, `TARGET_HOST`, `SOURCE_SSH_USER`, `TARGET_SSH_USER`, `SOURCE_SSH_KEY`, `TARGET_SSH_KEY`, `ORACLE_USER`, `ZDM_SOFTWARE_USER`) are captured in `Artifacts/Phase10-Migration/Step3/ssh-config.md`.
- DB and ZDM variables (`SOURCE_REMOTE_ORACLE_HOME`, `SOURCE_ORACLE_SID`, `TARGET_REMOTE_ORACLE_HOME`, `TARGET_ORACLE_SID`, `SOURCE_DATABASE_UNIQUE_NAME`, `TARGET_DATABASE_UNIQUE_NAME`, `ZDM_HOME`, `SOURCE_GI_TYPE`, `TGT_REDODG`, `TGT_RECODG`) are captured in `Artifacts/Phase10-Migration/Step4/db-config.md`.

## CR-06: OCI CLI requirement

1. OCI CLI is not required for migration execution.

## CR-07: Per-step output README requirement

1. Each StepX output directory must include a `README.md` file in that step directory.
2. The step README must summarize:
	- generated files for that step,
	- what the user should run later on the jumpbox/ZDM server,
	- where runtime outputs/logs/reports are written,
	- the success/failure signals to check.
3. Step-specific requirements may add extra README expectations, but may not remove this baseline requirement.

## CR-08: Two-layer step requirements model

1. Each Phase10 step should separate user-facing intent requirements from script/implementation coding requirements.
2. User-facing requirements should focus on:
	- objective,
	- output contract,
	- execution boundary,
	- user-visible behavior and success criteria.
3. Implementation requirements should focus on:
	- coding patterns
	- shell/sql implementation constraints,
	- required snippets/examples,
	- schema/format details for machine-readable outputs.
4. User-facing requirements are intended to be easier for non-implementation contributors to edit.
5. Implementation requirements must remain explicit enough to preserve deterministic prompt and script generation.

Recommended step-level file names:

- `USER-REQUIREMENTS.md` for user-facing requirements.
- `SYSTEM-REQUIREMENTS.md` for implementation/script-level requirements.

Naming rule:

- Use only `USER-REQUIREMENTS.md` and `SYSTEM-REQUIREMENTS.md` for every Phase10 step.

## CR-09: Regeneration inputs when requirements are split

1. Prompt regeneration must include both step files plus shared common requirements.
2. Shared/common requirements remain the global baseline and do not move into step-level files.
3. If user-facing and implementation requirements conflict, treat implementation requirements as controlling for generated script behavior, and document the conflict for user review.

## CR-10: Legacy file policy

1. `REQUIREMENTS.md` is no longer a canonical step requirement file for Phase10.
2. Step requirements must be authored and maintained only in `USER-REQUIREMENTS.md` and `SYSTEM-REQUIREMENTS.md`.
3. Avoid duplicating the same requirement text in both files; place each requirement in exactly one layer.

## CR-11: Generation quality gate and evidence

1. Before finalizing generated artifacts, run local non-invasive validation checks allowed by the execution boundary.
2. Validation must include syntax checks for generated shell scripts (for example `bash -n` on each script).
3. If optional linters are available in the environment (for example `shellcheck`), run them and resolve actionable findings.
4. Any failed validation check is a stop-ship condition for generation output; fix and re-run checks until all required checks pass.
5. Final output must include a concise validation evidence summary listing checks performed and pass/fail status.
6. This quality gate applies to all Phase10 steps that generate executable scripts or machine-readable artifacts.

## CR-12: Configuration artifact contract

1. Step3 writes `Artifacts/Phase10-Migration/Step3/ssh-config.md` containing SSH connectivity variables.
2. Step4 writes `Artifacts/Phase10-Migration/Step4/db-config.md` containing database and ZDM variables.
3. Both artifact files use the same key-value markdown format as `zdm-env.md`:
   - One variable per line: `- KEY: value`
   - Blank value means unset: `- KEY: `
   - Placeholder values containing `<...>` are treated as unset.
4. Steps 4–7 consume `ssh-config.md` as a read-only input for SSH connectivity context.
5. Steps 5–7 consume `db-config.md` as a read-only input for database context.
6. **Pre-populated file bypass**: If the artifact file already exists at the expected path when the step starts, use it directly and skip interactive collection. This enables testing acceleration — users may pre-populate either artifact file to bypass the collection phase.
7. Generated scripts and runtime artifacts must not read, source, or parse either config artifact at runtime (CR-02 applies).

## CR-13: Environment safety and scope disclaimer (applies to all steps)

1. **Copilot agent prompts** are intended to run in **development and non-production environments only**. Do not run Copilot agent prompts directly against production systems.
2. **Generated scripts** are designed to be portable and are safe to use in both development and production environments, once reviewed and tested. The recommended workflow is: run the prompt in development → review and test generated scripts → copy scripts to production → execute manually.
3. Every prompt step must display a concise risk banner **at the start of execution**, before any other action, using this format:
   ```
   ⚠ ENVIRONMENT SAFETY: This prompt is for development/non-production use only.
   Do not run against production. Generated scripts may be copied to production
   once reviewed and tested — run them manually there.
   ```
4. Any prompt step that can modify system state (e.g., Steps 3, 5, and 6) must additionally display a full risk banner **before presenting execution options or running any commands**. The full banner must include:
   - The development-only restriction for running Copilot prompts.
   - The script promotion path for production use.
   - Any scripts that operate at Oracle Home or OS scope (affecting all databases on the server), listed explicitly.
   - A `CONFIRM` acknowledgment gate: do not proceed to execution until the user types `CONFIRM`.
5. Prompts must never imply that running Copilot agent steps directly on a production system is a supported or recommended workflow.

## CR-14: Three-layer pre-validation model (ZDM prerequisites as spec)

All Phase10 migration steps must validate prerequisites in the order below before submitting any job to `zdm -eval`. The goal is to surface any issue that is findable from documentation *before* touching the database or calling ZDM.

**The prerequisite check catalog is pre-loaded in the repository.** Do not use `fetch_webpage` to retrieve ZDM documentation at runtime. Read the check catalog directly from the versioned requirements files using `read_file`.

### CR-14-A: Pre-loaded prerequisite catalog files

The catalog files are located in the repository at:

```
.github/requirements/Phase10/ZDM-Prerequisites/
  README.md
  26.1/
    online-physical.md    ← ONLINE_PHYSICAL checks (Layer 0, 1, 2)
    offline-physical.md   ← OFFLINE_PHYSICAL checks (Layer 0, 1, 2)
```

**Default version**: `26.1`. If the ZDM version discovered from `$ZDM_HOME/bin/zdmcli -version` has no matching subdirectory, use the `26.1/` catalog and log a warning that the catalog version may not exactly match the installed version.

**Version lookup protocol** — run at the start of any step that needs the check catalog (Steps 3–6):

1. Obtain the ZDM version string from discovery (e.g., `26.1`). If not yet discovered, use `26.1` as default.
2. Determine the migration method (`ONLINE_PHYSICAL` or `OFFLINE_PHYSICAL`) from `db-config.md` or Step 6 answers. Default to `ONLINE_PHYSICAL` if not yet confirmed.
3. Select the matching catalog file:
   - `ONLINE_PHYSICAL` → `.github/requirements/Phase10/ZDM-Prerequisites/<version>/online-physical.md`
   - `OFFLINE_PHYSICAL` → `.github/requirements/Phase10/ZDM-Prerequisites/<version>/offline-physical.md`
4. Read the catalog file using `read_file`. This is the authoritative check list for the current step.

Show inline status: `Prerequisite catalog — loaded (<version>, <method>)` or `Prerequisite catalog — WARNING: version <discovered> not found, using 26.1`.

**Never call `fetch_webpage` for ZDM documentation** during a migration session. If the user says `refresh docs`, direct them to run the `@Phase10-Update-ZDM-Prerequisites` prompt instead.

### CR-14-B: Catalog file format

Each catalog file uses the following structured markdown format. Steps consume it by reading the tables for each layer.

```markdown
# ZDM Prerequisites — <Method>

- ZDM Version: <version>
- Migration Method: <ONLINE_PHYSICAL | OFFLINE_PHYSICAL>
- Source URL: <oracle doc url>
- Extracted: <date>

## Layer 0 — Questionnaire (no commands needed)
| Parameter | Allowed values | RSP / CLI mapping | Doc section |
|-----------|---------------|-------------------|-------------|

## Layer 1 — Infrastructure (no DB credentials)
| Check name | Verification command | Pass condition | Severity | Doc section |
|------------|---------------------|----------------|----------|-------------|

## Layer 2 — Source DB prerequisites (requires DB connection)
| Check name | SQL or command | Pass condition | Severity | Doc section |
|------------|---------------|----------------|----------|-------------|

## Layer 2 — Target DB prerequisites (requires DB connection)
| Check name | SQL or command | Pass condition | Severity | Doc section |
|------------|---------------|----------------|----------|-------------|

## Layer 2 — Additional checks for this migration method
| Check name | SQL or command | Pass condition | Severity | Doc section |
|------------|---------------|----------------|----------|-------------|
```

### CR-14-C: Layer execution rules

1. **Layer 0** is answered during the Step6 migration planning interview. Its answers propagate directly to RSP and `zdmcli` flags — no runtime verification needed.
2. **Layer 1** checks are executed by `preflight_l1_infrastructure.sh` (generated in Step7, S7-08). All L1 checks must pass before L2 checks run.
3. **Layer 2** checks are evaluated as the Step6 compatibility gate (S6-05). For customers who do not permit automated DB connections, each L2 query is surfaced as a copy-paste block for the DBA to run manually and return results.
4. **Layer 3** (`zdm -eval`) is submitted only after L0 + L1 + L2 all pass. Any eval failure is triaged against the catalog: if it maps to an L1 or L2 check, fix at that layer. If it is not in the catalog, add it to the catalog file under the appropriate layer with a note `[new — added <date>, source: zdm-eval-feedback]` and commit the change.

### CR-14-D: Catalog lifecycle

| Trigger | Action |
|---------|--------|
| Steps 3–6 start | Read catalog from `.github/requirements/Phase10/ZDM-Prerequisites/<version>/` using `read_file` |
| ZDM version not found in directory | Use `26.1/` catalog; log version mismatch warning |
| User says `refresh docs` | Direct user to run `@Phase10-Update-ZDM-Prerequisites` prompt; do not fetch at runtime |
| ZDM upgraded to a new version | Operator runs `@Phase10-Update-ZDM-Prerequisites`, which creates a new versioned directory and commits it |
| `zdm -eval` surfaces uncovered failure | Add new check to the matching catalog file under the appropriate layer; commit the update |

## CR-15: Interactive variable collection — learn-more option

Applies to all Phase10 steps that prompt the user to supply a variable value interactively (e.g., Step4 SSH connectivity collection, Step5 database variable collection, Step6 migration planning interview).

### CR-15-A: Learn-more offer

1. When prompting the user for any variable value, always append a learn-more hint on the line immediately following the prompt. Use this format:

   ```
   SOURCE_ORACLE_SID: ___
   (Type a value, or type ? to learn more about this variable before answering.)
   ```

2. The learn-more trigger is `?` typed as the answer to any variable prompt. Copilot must recognize `?`, `??`, or `help` as a learn-more intent for any prompt in an interactive collection block.

3. After displaying learn-more content, re-present the original prompt so the user can answer without restarting the collection sequence.

### CR-15-B: Learn-more content requirements

When the user requests learn-more for a variable, Copilot must explain:

1. **Purpose** — what ZDM uses this value for (RSP parameter, `zdmcli` flag, or discovery control).
2. **How to find it** — one or more concrete commands the user can run on the relevant host (jumpbox, source, or target) to discover the correct value. Prefer commands executable without a DB connection where possible.
3. **Constraints and pitfalls** — allowed values, format rules, and known failure modes if the wrong value is supplied (e.g., which ZDM error code results).
4. **Example value** — a representative example (not a placeholder) so the user understands the expected format.

### CR-15-C: Variable glossary used by learn-more

The learn-more content for each variable must be derived from CR-05 definitions, step-level requirements, and the loaded prerequisite catalog. Steps must not fabricate values or reference external URLs at runtime. The table below is the authoritative per-variable content source:

| Variable | Purpose | How to find | Constraints / pitfalls | Example |
|----------|---------|-------------|------------------------|---------|
| `SOURCE_REMOTE_ORACLE_HOME` | Path to Oracle software home on the source host | `cat /etc/oratab` on source; look for lines matching the target SID | Must be the ORACLE_HOME directory, not `$ORACLE_BASE`; verify it exists: `ssh ... test -d <path>` | `/u01/app/oracle/product/19.0.0/dbhome_1` |
| `SOURCE_ORACLE_SID` | Oracle instance name (ORACLE_SID) of the source database | `ps -ef | grep ora_pmon` on source; or `/etc/oratab` | Case-sensitive; must match exactly what the instance uses | `ORCL` |
| `SOURCE_GI_TYPE` | Whether the source uses standalone or Grid Infrastructure | `crsctl query crs activeversion` on source — if it returns a version, GI is active | Wrong value → PRGZ-3928; use `grid` when srvctl manages the DB, `standalone` otherwise | `standalone` |
| `TARGET_REMOTE_ORACLE_HOME` | Path to Oracle software home on the target host | `cat /etc/oratab` on target | Same rules as `SOURCE_REMOTE_ORACLE_HOME` | `/u02/app/oracle/product/19.0.0/dbhome_1` |
| `TARGET_ORACLE_SID` | Oracle instance name on the target (Node 1 instance for RAC) | `cat /etc/oratab` on target; for RAC use instance name ending in `1` | For ExaCS/EXACC RAC the SID is `<db_name>1`; wrong SID → ZDM cannot connect to target instance | `ORCL1` |
| `SOURCE_DATABASE_UNIQUE_NAME` | `DB_UNIQUE_NAME` of the source database | `SELECT db_unique_name FROM v$database;` on source; or `srvctl config database -d <name>` | Must match the value in the source controlfile; used in `-sourcedb` or as DG primary name | `ORCL_PHX` |
| `TARGET_DATABASE_UNIQUE_NAME` | `DB_UNIQUE_NAME` of the target database | `SELECT db_unique_name FROM v$database;` on target | Must differ from source `DB_UNIQUE_NAME`; used as DG standby name | `ORCL_IAD` |
| `ZDM_HOME` | Installation directory of ZDM on the jumpbox | `which zdmcli` then strip `/bin/zdmcli`; or check common paths like `/mnt/app/zdmhome` | Leave blank for auto-detection; if set incorrectly, all `zdmcli` invocations will fail | `/mnt/app/zdmhome` |
| `TGT_REDODG` | ASM disk group used for redo logs on the target | `asmcmd lsdg` on target as grid user; look for group mounted as `REDO` or similar; or `SELECT name FROM v$asm_diskgroup WHERE name LIKE '%REDO%'` | Required RSP param for EXACS/EXACC; omitting it causes PRCG-1054 | `DATA` or `REDO` (varies by provisioning) |
| `TGT_RECODG` | ASM disk group used for recovery/FRA on the target | Same as `TGT_REDODG` but look for `RECO`, `FRA`, or `RECOC1` | Required RSP param for EXACS/EXACC; omitting it causes PRCG-1054 | `RECO` |

## CR-16: Grouped interactive question collection

Applies to all Phase10 steps that collect multiple variable values interactively from the user.

### CR-16-A: Present questions as a numbered list in a single chat message

1. When a step needs to collect multiple variables interactively, **present all questions as a numbered list in a single chat message**, rather than asking one question, waiting for an answer, then asking the next. Do **not** use `vscode_askQuestions` for this — questions must appear in the chat as plain numbered markdown, not as a VS Code dialog.
2. Each group must be clearly labelled with a heading (e.g., `**Hosts**`, `**SSH Users**`, `**SSH Keys**`, `**Application Users**`). Number questions sequentially across all groups (e.g., 1, 2, 3 … not restarting at 1 per group) so the user can reply by number.
3. The user may reply with all answers at once in any format — numbered (`1: 10.0.0.11`), bullet, or prose — and Copilot must parse the response and map answers back to the correct variables by number.
4. Do not hold up the conversation waiting for individual answers — only send a second message when a later group's questions depend on the answer to an earlier group (e.g., authentication type determines which key/password question to show).
5. **Example format Copilot must use:**
   ```
   **Hosts**
   1. SOURCE_HOST — IP address or FQDN of the source database server (e.g. `10.0.0.10`)
   2. TARGET_HOST — IP address or FQDN of the target database server (e.g. `10.0.0.20`)

   **SSH Users**
   3. SOURCE_SSH_USER — SSH admin user for the source host (e.g. `opc`)
   4. TARGET_SSH_USER — SSH admin user for the target host (e.g. `opc`)

   Reply with answers by number, e.g.:
   1: 10.1.0.11
   2: 10.1.0.12
   3: opc
   4: opc
   ```

### CR-16-B: Standard groupings per step

Use these canonical group layouts when collecting variables. Steps may add extra groups or merge groups where the variable count is small, but must not split a group across separate messages.

**Step 1 — VM Parameter Collection:**
- Group 1 — VM Identity: VM name, resource group, Azure region
- Group 2 — VM Configuration: image (show default), VM size (show default), OS disk size (show default)
- Group 3 — Networking: VNet name, subnet name
- Group 4 — Authentication: auth type (SSH key / password), SSH username (show default)
- Group 5 — SSH Key or Password: SSH public key path or password (dependent on Group 4 answer)

**Step 3 — SSH Connectivity Collection (S4-08):**
- Group 1 — Hosts: source host IP/FQDN, target host IP/FQDN
- Group 2 — SSH Users: SSH admin user for source, SSH admin user for target
- Group 3 — SSH Keys: source SSH key path (blank = agent/default), target SSH key path
- Group 4 — Application Users: Oracle software owner (default: `oracle`), ZDM software user (default: `zdmuser`)

**Step 4 — Discovery Variable Collection:**
- Group 1 — Database Homes: `SOURCE_REMOTE_ORACLE_HOME`, `TARGET_REMOTE_ORACLE_HOME`
- Group 2 — Instance Names: `SOURCE_ORACLE_SID`, `TARGET_ORACLE_SID`
- Group 3 — Unique Names: `SOURCE_DATABASE_UNIQUE_NAME`, `TARGET_DATABASE_UNIQUE_NAME`
- Group 4 — ZDM Server: `ZDM_HOME` (blank = auto-detect)

**Step 5 — Migration Planning Interview (S6-08):**
- Group A — Migration Type & Platform (present together): migration method (ONLINE_PHYSICAL / OFFLINE_PHYSICAL), target platform type, source storage type.
- Group B-Online — Online-specific settings (present together, only if ONLINE_PHYSICAL confirmed): log switch interval, Data Guard protection mode, data transfer medium, pause before switchover, auto-switchover.
- Group B-Offline — Offline-specific settings (present together, only if OFFLINE_PHYSICAL confirmed): backup/transfer medium, maximum downtime window.
- Group C — Object Storage (present together, only if OSS transfer medium): namespace, bucket name, bucket region. Note: OCI identity parameters (Tenancy OCID, User OCID, Compartment OCID, Target Database OCID) are **not required** for physical migrations — ZDM uses the OCI config file on the ZDM host, set up during Step 2 installation. Do not ask for them.
- Group D — TDE/Wallet (present together, only if TDE enabled): wallet transfer medium (`WALLET_MIGRATION`).

  Pre-filled values from `zdm-env.md` or `db-config.md` must be shown as defaults in the group prompt. Only ask groups whose questions are applicable given prior answers (e.g., skip Group B-Online if method is OFFLINE_PHYSICAL). Each group is still subject to the inter-group dependency rule in CR-16-A: a later group may depend on a confirmed answer from an earlier group.

### CR-16-C: Confirmation summary before action

After collecting all groups, display a single consolidated summary of all collected values and require the user to confirm before writing any artifact or running any command. This confirmation is separate from the group collection and must show all values together.
