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

## CR-14: Three-layer pre-validation model (ZDM documentation as spec)

All Phase10 migration steps must validate prerequisites in the order below before submitting any job to `zdm -eval`. The goal is to surface any issue that is findable from documentation *before* touching the database or calling ZDM.

**The prerequisite check catalog is derived at runtime from the ZDM product documentation — it is not hardcoded in these requirements.** This ensures checks stay current as ZDM documentation is updated without any change to these requirement files.

### CR-14-A: Authoritative doc URLs (versioned)

| Migration method | Doc URL |
|-----------------|---------|
| Physical Online to ODAA | `https://docs.oracle.com/en/database/oracle/zero-downtime-migration/<version>/zdmpn/` |
| Physical Offline to ODAA | `https://docs.oracle.com/en/database/oracle/zero-downtime-migration/<version>/zdmpa/` |
| Logical Offline to ODAA | `https://docs.oracle.com/en/database/oracle/zero-downtime-migration/<version>/zdmpl/` |

`<version>` is the ZDM version string (e.g., `21.5`) discovered from `$ZDM_HOME/bin/zdmcli -version` during Step3 ZDM server discovery. Substitute the actual discovered version into the URL before fetching.

### CR-14-B: Doc-fetch-and-cache protocol

The prerequisite check catalog must be built by fetching the ZDM documentation and extracting checks from it. A cache file avoids redundant fetches across steps.

**Cache file path:**
```
Artifacts/Phase10-Migration/ZDM-Doc-Checks/prerequisites-<zdm-version>.md
```

**Protocol — run at the start of any step that needs the check catalog (Steps 3–6):**

1. **Check for cache**: Does `Artifacts/Phase10-Migration/ZDM-Doc-Checks/prerequisites-<zdm-version>.md` exist?
   - YES and the user has not said `refresh docs` → use the cache file. Skip to step 4.
   - NO, or user said `refresh docs` → proceed to step 2.

2. **Fetch docs**: Use `fetch_webpage` to retrieve the applicable URL(s) for the confirmed migration method. If the migration method is not yet confirmed (e.g., early in Step 3), fetch the Physical Online URL as the default; fetch additional method URLs once the method is confirmed.

3. **Extract and write cache**: Parse the fetched content and extract all prerequisite checks. Write the extracted catalog to the cache file using the format defined in CR-14-C. Confirm the file is non-empty after writing.

4. **Use cache**: Read the cache file to obtain the check catalog for the current step's use.

**If `fetch_webpage` fails** (network unavailable, site unreachable):
- If a cache file exists for any version, use it and log a warning that the cache may be stale.
- If no cache exists at all, surface the failure and provide the doc URLs so the user can manually supply the prerequisite list.
- Do not silently fall back to hardcoded defaults.

### CR-14-C: Cache file format

The cache file is a structured markdown document. When extracting checks from ZDM docs, populate the following sections. Each check must include the doc section title where it was found so a human can verify the source.

```markdown
# ZDM Prerequisites — Extracted from Documentation
- ZDM Version: <version>
- Migration Method: <ONLINE_PHYSICAL | OFFLINE_PHYSICAL | OFFLINE_LOGICAL>
- Source URL: <url fetched>
- Extracted: <date/time>

## Layer 0 — Questionnaire (no commands needed)
<!-- Checks answered by asking the user; they directly set RSP params or zdmcli flags -->
| Parameter | Allowed values | RSP / CLI mapping | Doc section |
|-----------|---------------|-------------------|-------------|
| ... | ... | ... | ... |

## Layer 1 — Infrastructure (no DB credentials)
<!-- Checks performable with SSH + OS commands only -->
| Check name | Verification command | Pass condition | Severity | Doc section |
|------------|---------------------|----------------|----------|-------------|
| ... | ... | ... | BLOCKER/WARNING | ... |

## Layer 2 — Source DB prerequisites (requires DB connection)
| Check name | SQL or command | Pass condition | Severity | Doc section |
|------------|---------------|----------------|----------|-------------|
| ... | ... | ... | BLOCKER/WARNING | ... |

## Layer 2 — Target DB prerequisites (requires DB connection)
| Check name | SQL or command | Pass condition | Severity | Doc section |
|------------|---------------|----------------|----------|-------------|
| ... | ... | ... | BLOCKER/WARNING | ... |

## Layer 2 — Additional checks for this migration method
<!-- Logical migration: Data Pump roles, streams_pool_size, etc. -->
| Check name | SQL or command | Pass condition | Severity | Doc section |
|------------|---------------|----------------|----------|-------------|
| ... | ... | ... | BLOCKER/WARNING | ... |
```

### CR-14-D: Extraction rules (applied when parsing doc pages)

When extracting checks from a fetched ZDM doc page, apply these rules:

1. **Layer assignment** — assign each extracted prerequisite to a layer:
   - **Layer 0**: answered by asking the user; no command needed. Examples: `PLATFORM_TYPE` (ExaDB-D → `EXACS`, Base DB → `VMDB`), source storage type (`-sourcesid` vs `-sourcedb`).
   - **Layer 1**: verifiable with SSH and OS commands only, no `sqlplus`. Examples: SSH key format, passwordless sudo, `/etc/hosts` entries, NFS mounts, Oracle UID match, `tnsping`, ZDM service health.
   - **Layer 2**: requires a database connection (`sqlplus / as sysdba` via SSH). Examples: `ARCHIVELOG`, `COMPATIBLE`, `DB_NAME`, TDE wallet status, RMAN config.

2. **Severity assignment**:
   - Mark a check as `BLOCKER` if the doc states the requirement as mandatory or uses language like "must", "required", "mandatory".
   - Mark a check as `WARNING` if the doc uses language like "should", "recommended", or flags it as a potential issue rather than a hard stop.

3. **SQL construction**: When the doc shows example SQL queries, copy them verbatim into the cache. When the doc states a requirement in prose without SQL, construct the minimal SQL that verifies the condition and note `[constructed]` in the Doc section column.

4. **Completeness**: Extract checks from all sections of the page, including "Prerequisites", "Source and Target Database Prerequisites", "Additional Configuration", and step-by-step preparation sections (e.g., "Step 2: Prepare the Source Database").

5. **New checks**: If a fetched page contains a prerequisite not found in any previous cache for this ZDM version, add it to the cache and note `[new — added <date>]` in the Doc section column.

### CR-14-E: Layer execution rules

1. **Layer 0** is answered during the Step4 migration planning interview. Its answers propagate directly to RSP and `zdmcli` flags — no runtime verification needed.
2. **Layer 1** checks are executed by `preflight_l1_infrastructure.sh` (generated in Step5, S5-08). All L1 checks must pass before L2 checks run.
3. **Layer 2** checks are evaluated as the Step4 compatibility gate (S4-05). For customers who do not permit automated DB connections, each L2 query is surfaced as a copy-paste block for the DBA to run manually and return results.
4. **Layer 3** (`zdm -eval`) is submitted only after L0 + L1 + L2 all pass. Any eval failure is triaged against the cache: if it maps to an L1 or L2 check, fix at that layer. If it is not in the cache, add it to the cache as a new check before retrying.

### CR-14-F: Cache lifecycle

| Trigger | Action |
|---------|--------|
| First run of any Step 3–6, no cache exists | Fetch docs, extract, write cache |
| ZDM version changes (upgrade) | New cache file created for new version; old cache retained |
| User says `refresh docs` | Re-fetch and overwrite cache for current version |
| `fetch_webpage` unavailable | Use existing cache with stale warning; fail hard if no cache exists |
| `zdm -eval` surfaces uncovered failure | Add new check to cache under appropriate layer; note source as `[zdm-eval-feedback]` |
