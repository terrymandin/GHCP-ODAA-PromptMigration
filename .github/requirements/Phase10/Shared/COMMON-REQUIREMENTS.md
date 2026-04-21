# Common Requirements for Phase 10 (Step1-Step6)

## Scope

These requirements apply to all Phase10 ZDM prompts unless a step explicitly overrides them.

## CR-01: Source of truth precedence

1. Treat step configuration artifacts as the primary authoritative generation input (see CR-12):
   - `Artifacts/Phase10-Migration/Step2/ssh-config.md` for SSH connectivity variables.
   - `Artifacts/Phase10-Migration/Step3/db-config.md` for database and ZDM variables.
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

DB-specific values used across Step2-Step6:

- `SOURCE_REMOTE_ORACLE_HOME`
- `SOURCE_ORACLE_SID`
- `TARGET_REMOTE_ORACLE_HOME`
- `TARGET_ORACLE_SID`
- `SOURCE_DATABASE_UNIQUE_NAME`
- `TARGET_DATABASE_UNIQUE_NAME`

ZDM-specific value used across Step2-Step6:

- `ZDM_HOME`

Variable-to-artifact mapping:

- SSH variables (`SOURCE_HOST`, `TARGET_HOST`, `SOURCE_SSH_USER`, `TARGET_SSH_USER`, `SOURCE_SSH_KEY`, `TARGET_SSH_KEY`, `ORACLE_USER`, `ZDM_SOFTWARE_USER`) are captured in `Artifacts/Phase10-Migration/Step2/ssh-config.md`.
- DB and ZDM variables (`SOURCE_REMOTE_ORACLE_HOME`, `SOURCE_ORACLE_SID`, `TARGET_REMOTE_ORACLE_HOME`, `TARGET_ORACLE_SID`, `SOURCE_DATABASE_UNIQUE_NAME`, `TARGET_DATABASE_UNIQUE_NAME`, `ZDM_HOME`) are captured in `Artifacts/Phase10-Migration/Step3/db-config.md`.

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

1. Step2 writes `Artifacts/Phase10-Migration/Step2/ssh-config.md` containing SSH connectivity variables.
2. Step3 writes `Artifacts/Phase10-Migration/Step3/db-config.md` containing database and ZDM variables.
3. Both artifact files use the same key-value markdown format as `zdm-env.md`:
   - One variable per line: `- KEY: value`
   - Blank value means unset: `- KEY: `
   - Placeholder values containing `<...>` are treated as unset.
4. Steps 3–6 consume `ssh-config.md` as a read-only input for SSH connectivity context.
5. Steps 4–6 consume `db-config.md` as a read-only input for database context.
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
2. Determine the migration method (`ONLINE_PHYSICAL` or `OFFLINE_PHYSICAL`) from `db-config.md` or Step 4 answers. Default to `ONLINE_PHYSICAL` if not yet confirmed.
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

1. **Layer 0** is answered during the Step4 migration planning interview. Its answers propagate directly to RSP and `zdmcli` flags — no runtime verification needed.
2. **Layer 1** checks are executed by `preflight_l1_infrastructure.sh` (generated in Step5, S5-08). All L1 checks must pass before L2 checks run.
3. **Layer 2** checks are evaluated as the Step4 compatibility gate (S4-05). For customers who do not permit automated DB connections, each L2 query is surfaced as a copy-paste block for the DBA to run manually and return results.
4. **Layer 3** (`zdm -eval`) is submitted only after L0 + L1 + L2 all pass. Any eval failure is triaged against the catalog: if it maps to an L1 or L2 check, fix at that layer. If it is not in the catalog, add it to the catalog file under the appropriate layer with a note `[new — added <date>, source: zdm-eval-feedback]` and commit the change.

### CR-14-D: Catalog lifecycle

| Trigger | Action |
|---------|--------|
| Steps 3–6 start | Read catalog from `.github/requirements/Phase10/ZDM-Prerequisites/<version>/` using `read_file` |
| ZDM version not found in directory | Use `26.1/` catalog; log version mismatch warning |
| User says `refresh docs` | Direct user to run `@Phase10-Update-ZDM-Prerequisites` prompt; do not fetch at runtime |
| ZDM upgraded to a new version | Operator runs `@Phase10-Update-ZDM-Prerequisites`, which creates a new versioned directory and commits it |
| `zdm -eval` surfaces uncovered failure | Add new check to the matching catalog file under the appropriate layer; commit the update |
