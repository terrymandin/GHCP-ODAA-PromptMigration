# Step5 User Requirements - Fix Issues

## Objective

Generate remediation and verification artifacts for blockers and required actions identified in Step4.

## S5-01: Output contract

Required generated artifacts under `Artifacts/Phase10-Migration/Step5/`:

- `Issue-Resolution-Log.md`
- `Scripts/fix_<issue-id>_<short-name>.sh` — one script per remediable issue (see S5-07 for naming)
- `Scripts/fix_orchestrator.sh` — orchestrator that invokes individual fix scripts in dependency order
- `Scripts/README-fix_<issue-id>_<short-name>.md` — one companion README per fix script
- `Scripts/README-fix_orchestrator.md` — companion README for the orchestrator
- `verify_fixes.sh` — verification script (run after fixes are applied)
- `README.md` — step summary and review checklist

Non-remediable issues (e.g., provisioning changes requiring console action) must be documented in `Issue-Resolution-Log.md` with manual steps only — no script is generated for them.

## S5-02: Iterative operation model

1. Step5 supports repeated cycles until blockers are resolved.
2. Each iteration updates issue tracking and verification outcomes.

## S5-06: Issue-Resolution-Log generated items

`Issue-Resolution-Log.md` should include at least:

1. Issue register with IDs, severity, owner, status, and last-updated timestamp.
2. For each issue: evidence, remediation plan, verification method, and rollback notes.
3. Iteration history showing what changed between remediation cycles.
4. Explicit unresolved items and blockers preventing Step6 progression.

## S5-07: Remediation package generated items

### Per-issue fix script naming

Each remediable issue gets exactly one script:

```
Scripts/fix_<issue-id>_<short-name>.sh
```

Examples:
- `fix_B01_enable_archivelog.sh`
- `fix_B02_create_spfile.sh`
- `fix_W01_upgrade_timezone.sh`

`<issue-id>` uses the Issue-Resolution-Log ID. `<short-name>` is a 2–4 word snake_case description.

### Orchestrator script

`fix_orchestrator.sh` must:
1. List all fix scripts it will invoke, in dependency order, at the top as comments.
2. Invoke each fix script individually (not source them) so failures are isolated.
3. Log pass/fail status per script to stdout.
4. Stop on first BLOCKER-category failure unless `--continue-on-error` flag is passed.
5. Accept an optional `--dry-run` flag that prints what would be executed without running anything.

### Companion README per fix script

For each `fix_<issue-id>_<short-name>.sh`, generate `README-fix_<issue-id>_<short-name>.md` containing:

1. Issue ID and severity (BLOCKER / WARNING).
2. Target server (`zdm-server`, `source-db`, or `target-db`) and rationale (see S5-10).
3. Prerequisites and required environment variables.
4. Step-by-step behavior summary.
5. Exact execution command and required runtime user.
6. Expected output or success indicators.
7. Rollback/undo guidance when applicable.

## S5-10: Target-first remediation preference

When a compatibility fix can be applied to either the source or the target database, **generate the script for the target database**. Do not generate source-side scripts unless the fix is source-only by nature.

Source-only fixes (always generate against source):
- Enabling `ARCHIVELOG` mode
- Creating/switching to SPFILE
- RMAN configuration (`CONTROLFILE AUTOBACKUP`, snapshot controlfile location)
- Source TDE wallet creation or key management (when target TDE is not yet applicable)

Target-preferred fixes (generate against target even if source could also be changed):
- `COMPATIBLE` parameter alignment — set source value on target (lowering source is not supported)
- Timezone file upgrade — upgrade target to match or exceed source
- `/tmp` execute permission — remediate on target (and source if also failing)
- `SQLNET.ORA` encryption algorithm alignment — update target to match source
- TDE wallet status — open/configure on target

Each companion README must explicitly state which server the script targets and why (source-only by nature, or target-preferred per this policy).

## S5-12: Scope classification and blast-radius awareness

Each fix script must be assigned a **scope** based on the broadest system component it modifies:

| Scope | Meaning | Examples |
|-------|---------|----------|
| `DATABASE` | Affects only the named database instance | `COMPATIBLE` parameter, ARCHIVELOG mode, SPFILE creation, TDE wallet, RMAN config |
| `ORACLE-HOME` | Affects all databases sharing this Oracle Home | `SQLNET.ORA` encryption settings, timezone file upgrade |
| `OS` | Affects all processes on the host | `/tmp` mount flags |

Scope must be declared in:
1. The `# TARGET:` header block of the fix script (add `# SCOPE: DATABASE | ORACLE-HOME | OS`).
2. The companion `README-fix_<issue-id>_<short-name>.md` as a **Scope** field (with a plain-English explanation of what else on the server could be affected).
3. The S5-11 script inventory table as a **Scope** column.

When any `ORACLE-HOME` or `OS` scope scripts are present, they must be explicitly listed in the S5-13 risk banner before execution options are presented.

## S5-11: Execution model and user choice

After all scripts are generated and written to disk, present the user with a **script inventory table** and an explicit choice:

```
Generated fix scripts
---------------------
| Script | Target | Severity | Summary |
|--------|--------|----------|---------|
| fix_B01_enable_archivelog.sh | source-db | BLOCKER | Enable ARCHIVELOG mode on source |
| fix_B02_compatible_param.sh  | target-db | BLOCKER | Set COMPATIBLE=12.2.0 on target  |
| fix_W01_upgrade_timezone.sh  | target-db | WARNING | Upgrade DST timezone file        |
| fix_orchestrator.sh          | all       | —        | Run all fixes in order           |

Options:
  A (default) — Review scripts individually and run selectively outside this prompt.
  B — Say "run all" to execute all scripts via the orchestrator.
  C — Say "run fix_<id>" (e.g., "run fix_B01") to execute a specific script inline.
```

Do not execute any script unless the user explicitly says `run all` or `run fix_<id>` after seeing this menu. See S5-09 for execution constraints.
