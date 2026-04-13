# Step5 System Requirements - Remediation Script Implementation

## Scope

This file defines script-level coding constraints for remediation and verification artifacts generated in Step5.

## S5-08: Runtime user model

1. All scripts run from the ZDM jumpbox as `zdmuser`.
2. Each script must include a user guard at the top that exits non-zero when not running as `zdmuser`:
   ```bash
   [ "$(id -un)" = "zdmuser" ] || { echo "ERROR: must run as zdmuser"; exit 1; }
   ```
3. Each script header must declare its target with a comment on the first non-shebang line:
   ```bash
   # TARGET: zdm-server | source-db | target-db
   ```
4. Scripts targeting `source-db` or `target-db` execute their payload via SSH from the jumpbox, using the SSH connectivity variables from `Artifacts/Phase10-Migration/Step2/ssh-config.md` (same pattern as Step3 discovery). They must not assume a direct local connection to those hosts.
5. Scripts targeting `zdm-server` execute locally on the jumpbox.

## S5-09: Quoting and SQL execution safety

1. For SSH-based SQL helpers, use base64-wrapped SQL block execution to avoid shell quoting breakage.
2. Normalize optional SSH keys and conditionally include `-i` only when key is set and non-placeholder.

## S5-10: Verification output

1. `verify_fixes.sh` tracks per-issue PASS/FAIL/WARN status.
2. Verification writes structured markdown results to `Verification-Results.md` for Step6 consumption.

## S5-11: Pre-execution risk banner and acknowledgment gate

Before displaying the S5-07 execution menu, the prompt must always display the following risk banner. The banner is mandatory — it must not be skipped or abbreviated.

```
⚠ ENVIRONMENT SAFETY WARNING

These Copilot agent prompts are intended to run in development/non-production
environments only. Do not run this prompt directly against a production system.

Generated scripts are safe to copy to production once reviewed and tested in
development. For production use: review scripts, copy them to the production
host, and run manually — do not re-run this prompt on production.

[If any ORACLE-HOME or OS scope scripts exist, list them here:]
  The following scripts affect Oracle Home or OS level settings and will impact
  ALL databases sharing that Oracle Home or host — not just the migration target:
    - <script_name>  →  <ORACLE-HOME | OS> scope  (<what it changes>)

Type CONFIRM to proceed to the execution menu, or press Enter to review scripts
manually (Option A — no execution).
```

Behavior rules:
1. Always show the banner before the S5-07 menu, even on subsequent iterations of Step5.
2. If no `ORACLE-HOME` or `OS` scope scripts are present, omit the blast-radius paragraph but keep the rest of the banner.
3. Do not display the S5-07 execution options until the user types `CONFIRM`.
4. If the user does not type `CONFIRM` (presses Enter or provides any other input), default to Option A (review only — no execution).

## S5-12: Default no-execution — conditional execution on explicit user request

1. Remediation scripts and the verification script are **generated and saved to disk only** by default.
2. The prompt must **not execute** any remediation or verification script unless the user explicitly requests execution after seeing the S5-07 script inventory and choice menu.
3. Explicit execution triggers:
   - `run all` — invoke `fix_orchestrator.sh` inline via the terminal.
   - `run fix_<id>` (e.g., `run fix_B01`) — invoke the matching `fix_<issue-id>_*.sh` script inline.
4. When executing a script inline:
   - Display the exact command being run before executing it.
   - Capture stdout and stderr and display them in the chat.
   - Record the exit code and execution timestamp in `Issue-Resolution-Log.md`.
   - After execution, run `verify_fixes.sh` automatically for the affected issue(s) and report PASS/FAIL.
5. Never execute a script silently or without prior display of the S5-07 menu.

## S5-13: Verification-Results generated items

`Verification-Results.md` should include:

1. Per-issue status table (PASS/FAIL/WARN).
2. Evidence detail per issue (what was checked and observed values).
3. Overall blocker resolution result indicating Step6 readiness.
4. Remaining warnings/recommendations that are not hard blockers.
