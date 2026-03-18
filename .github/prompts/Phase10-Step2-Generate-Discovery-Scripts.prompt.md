---
agent: agent
description: ZDM Step 2 - Generate read-only database discovery scripts
---
# ZDM Migration Step 2: Generate Discovery Scripts

## Purpose

Generate read-only discovery tooling for source, target, and ZDM server assessment. This step creates
scripts and placeholder directories only; runtime discovery outputs are produced later on the jumpbox/ZDM
server when the generated scripts are executed by the user.

## Execution Boundary

This prompt is generation-only.
- Generate files under `Artifacts/Phase10-Migration/Step2/` only.
- Do not execute migration, SSH, SCP, SQL, discovery, or remediation commands from VS Code.
- Do not generate discovery runtime output files during prompt execution.
- Runtime outputs are created only when scripts run later on the jumpbox/ZDM server.

## Inputs And Precedence Rules

Attach `zdm-env.md` when available and treat it as authoritative generation input.

Input precedence and handling requirements:
- Prefer `zdm-env.md` values over prompt defaults/examples.
- If `zdm-env.md` values conflict with discovery evidence, do not silently override; report the mismatch explicitly.
- If step user-facing and implementation requirements conflict, treat implementation requirements as controlling for script behavior and document the conflict for user review.
- `zdm-env.md` is generation-time input only; generated scripts must not read, source, or parse `zdm-env.md` at runtime.
- Map `SOURCE_SSH_USER` and `TARGET_SSH_USER` to generated `SOURCE_ADMIN_USER` and `TARGET_ADMIN_USER`.
- Normalize SSH key values: empty or placeholder values (for example `<...>`) are treated as unset.
- Include SSH `-i` only when the normalized key path is non-empty.

DB-specific value scope (Step1-Step5):
- `SOURCE_REMOTE_ORACLE_HOME`
- `SOURCE_ORACLE_SID`
- `TARGET_REMOTE_ORACLE_HOME`
- `TARGET_ORACLE_SID`
- `SOURCE_DATABASE_UNIQUE_NAME`
- `TARGET_DATABASE_UNIQUE_NAME`

ZDM-specific value scope (Step1-Step5):
- `ZDM_HOME`

OCI CLI requirement:
- OCI CLI is not required for migration execution.

## Required Outputs

Generate exactly these files:
- `Artifacts/Phase10-Migration/Step2/Scripts/zdm_source_discovery.sh`
- `Artifacts/Phase10-Migration/Step2/Scripts/zdm_target_discovery.sh`
- `Artifacts/Phase10-Migration/Step2/Scripts/zdm_server_discovery.sh`
- `Artifacts/Phase10-Migration/Step2/Scripts/zdm_orchestrate_discovery.sh`
- `Artifacts/Phase10-Migration/Step2/README.md`
- `Artifacts/Phase10-Migration/Step2/Scripts/README.md`

Create placeholder directories:
- `Artifacts/Phase10-Migration/Step2/Discovery/source/`
- `Artifacts/Phase10-Migration/Step2/Discovery/target/`
- `Artifacts/Phase10-Migration/Step2/Discovery/server/`

`Artifacts/Phase10-Migration/Step2/Scripts/README.md` must summarize:
- generated files for Step2,
- what the user should run later on jumpbox/ZDM server,
- where runtime outputs/logs/reports are written,
- success/failure signals to check.

`Artifacts/Phase10-Migration/Step2/README.md` must summarize:
- generated files and directories for Step2,
- what the user should run later on jumpbox/ZDM server,
- where runtime outputs/logs/reports are written,
- success/failure signals to check.

## Generated Items And Runtime Content Catalog

Treat this section as the prompt-level source-of-truth catalog for Step2 discovery coverage. Add or change discovery items in requirements first, then regenerate this prompt and scripts.

### Read-only enforcement (all generated scripts)

All generated scripts must be strictly read-only.
- SQL is `SELECT`-only; no DDL/DML.
- No OS/service mutation commands.
- Include this banner comment near the top of each discovery script:

```bash
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration
```

### Auth and user model

- Source and target scripts SSH as admin users, then run SQL as `oracle` via `sudo -u oracle`.
- ZDM server discovery runs locally as `zdmuser` and enforces a user guard.
- Preserve the generated variable mapping: `SOURCE_SSH_USER`/`TARGET_SSH_USER` -> `SOURCE_ADMIN_USER`/`TARGET_ADMIN_USER`.

### Script: `zdm_source_discovery.sh`

When run later on jumpbox/ZDM server, collect:
1. Connectivity and auth context: source host, SSH user, SSH key mode.
2. Remote system details: hostname, OS, kernel, uptime.
3. Oracle environment details:
   - `/etc/oratab` entries.
   - PMON SIDs detected.
   - Oracle home in use.
   - Oracle SID in use.
   - Database unique name (configured value).
   - `sqlplus` version.
4. Database configuration: name/unique name/role/open mode/character sets; archivelog/force/supplemental logging.
5. CDB/PDB posture: CDB status and PDB names/open modes.
6. TDE status: wallet type/location and encrypted tablespaces.
7. Tablespace/datafile posture: autoextend settings and current/max sizing.
8. Redo/archive posture: redo groups/sizes/members and archive destinations.
9. Network config: listener status, `tnsnames.ora`, `sqlnet.ora`.
10. Authentication artifacts: password file location and SSH directory contents.
11. Schema posture: non-system schema sizes and invalid object counts.
12. Backup posture: schedules/policies and most recent successful backup evidence.
13. Integration objects: database links, materialized views/logs, scheduler jobs that may require post-cutover updates.
14. Data Guard parameters/config evidence when applicable.

### Script: `zdm_target_discovery.sh`

When run later on jumpbox/ZDM server, collect:
1. Connectivity and auth context: target host, SSH user, SSH key mode.
2. Remote system details: hostname, OS, kernel, uptime.
3. Oracle environment details:
   - `/etc/oratab` entries.
   - PMON SIDs detected.
   - Oracle home in use.
   - Oracle SID in use.
   - Database unique name (configured value).
   - `sqlplus` version.
4. Database configuration: name/unique name/role/open mode/character set.
5. CDB/PDB posture: CDB status and PDB open mode(s), including pre-created migration PDB.
6. TDE wallet status/type.
7. Storage posture: ASM disk groups and free space (plus Exadata cell/grid disk details when available).
8. Network posture: listener status, SCAN status when applicable, and `tnsnames.ora`.
9. OCI/Azure integration metadata (sanitized profile/metadata only).
10. Grid infrastructure status when RAC/Exadata applies.
11. Network security checks relevant to SSH/listener ports.

### Script: `zdm_server_discovery.sh`

When run later on jumpbox/ZDM server, collect:
1. Local system details: hostname, OS, kernel, uptime, current user.
2. ZDM installation details: `ZDM_HOME`, existence/permissions, `zdmcli` path, version evidence.
3. Capacity snapshot: disk and memory summary.
4. Java details: `JAVA_HOME` and Java version (prefer bundled JDK check first).
5. OCI authentication configuration: config location, profile metadata (masked), API key presence/permissions.
6. SSH/credential inventory in `zdmuser` home context.
7. Network context: IP/routing/DNS summaries.
8. Optional connectivity tests to source/target when env vars are provided (ping/port checks).
9. Endpoint traceability: source and target endpoint values used during discovery.

Enforce local user guard so script runs as `zdmuser`.

### Script: `zdm_orchestrate_discovery.sh`

When run later on jumpbox/ZDM server, runtime summary must include:
1. Effective runtime configuration used for source and target values.
2. Per-script execution status (`PASS`/`FAIL`) and log file paths.
3. Overall Step2 discovery status.
4. Output format references produced by script runs (raw text, markdown report, JSON report).

Runtime behavior requirements:
- Apply key normalization consistently and include SSH `-i` only when normalized key path is non-empty.
- Continue when one target fails and report per-target/per-script status.
- Do not suppress SSH/SCP errors; capture and report failure context.

### Shared script implementation requirements

- Use shebang `#!/bin/bash`.
- Use Unix LF line endings.
- Keep scripts runtime-independent from `zdm-env.md`.
- Preserve read-only behavior throughout.
- Ensure SQL execution remains `SELECT`-only and follows the admin-SSH plus `sudo -u oracle` model.
- Keep runtime output generation within Step2 discovery output locations only.

### Required implementation examples

Include and preserve the following concrete examples in generated script guidance.

ZDM server user guard example:

```bash
CURRENT_USER="$(whoami)"
if [ "$CURRENT_USER" != "${ZDM_USER:-zdmuser}" ]; then
      echo "[ERROR] This script must run as '${ZDM_USER:-zdmuser}'. Currently running as '${CURRENT_USER}'."
      echo "        Switch to the correct user first: sudo su - ${ZDM_USER:-zdmuser}"
      exit 1
fi
```

Orchestrator env defaults and key placeholder normalization example:

```bash
SOURCE_HOST="${SOURCE_HOST:-}"
TARGET_HOST="${TARGET_HOST:-}"
SOURCE_ADMIN_USER="${SOURCE_ADMIN_USER:-azureuser}"
TARGET_ADMIN_USER="${TARGET_ADMIN_USER:-azureuser}"
ORACLE_USER="${ORACLE_USER:-oracle}"
ZDM_USER="${ZDM_USER:-zdmuser}"
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-}"
TARGET_SSH_KEY="${TARGET_SSH_KEY:-}"

is_placeholder() { [[ "$1" == *"<"*">"* ]]; }
[ -n "$SOURCE_SSH_KEY" ] && is_placeholder "$SOURCE_SSH_KEY" && SOURCE_SSH_KEY=""
[ -n "$TARGET_SSH_KEY" ] && is_placeholder "$TARGET_SSH_KEY" && TARGET_SSH_KEY=""
```

Conditional `-i` usage pattern example:

```bash
ssh $SSH_OPTS ${SOURCE_SSH_KEY:+-i "$SOURCE_SSH_KEY"} "${SOURCE_ADMIN_USER}@${SOURCE_HOST}" ...
scp $SCP_OPTS ${SOURCE_SSH_KEY:+-i "$SOURCE_SSH_KEY"} "$script" "${SOURCE_ADMIN_USER}@${SOURCE_HOST}:$remote_dir/"
```

Remote execution pattern with login shell and working-directory prelude:

```bash
remote_dir="$HOME/zdm-step2-${dtype}-${timestamp}"
ssh $SSH_OPTS ${key_path:+-i "$key_path"} "${admin_user}@${host}" \
   "mkdir -p $remote_dir && bash -l -s" \
   < <(printf 'cd %q\n' "$remote_dir"; cat "$script_path")
```

Pass endpoint values to ZDM server discovery example:

```bash
SOURCE_HOST="$SOURCE_HOST" TARGET_HOST="$TARGET_HOST" ZDM_USER="$ZDM_USER" bash "$script_path"
```

### Required runtime behavior details

- Startup diagnostics must log current user/home, `.pem`/`.key` inventory, and normalized key resolution/existence checks.
- Continue execution when one server fails and report per-target/per-script status.
- Never suppress SSH/SCP errors; capture and report failure context.
- Confirm remote output existence before SCP retrieval.
- Enforce shell-safe remote path handling: do not use quoted-tilde runtime paths (for example `cd '~/dir'`); use `$HOME/...` or another explicit absolute path.
- Fail fast with an explicit error when remote working-directory setup fails before artifact checks.
- Do not define/call `log_raw` in orchestrator; use orchestrator-safe logging only.
- `show_help` and `show_config` must terminate with `exit` and be called only from argument parsing.
- Support CLI options: `-h`, `-c`, `-t`, `-v`.

### Required cross-script constraints

- Do not use global `set -e`; structure script sections so one section failure does not abort all discovery sections.
- Preserve ORACLE_HOME/ORACLE_SID auto-detection order:
   1. Existing environment variables.
   2. `/etc/oratab`.
   3. PMON process detection (`ora_pmon_*`).
   4. Common Oracle home paths.
   5. `oraenv`/`coraenv`.
- Run SQL as `oracle` with explicit Oracle environment.
- Prevent SP2-0310: pass SQL to `sqlplus` via stdin (pipe/heredoc), not temporary `@/tmp/*.sql` files.
- Preserve runtime output naming patterns:
   - `./zdm_<type>_discovery_<hostname>_<timestamp>.txt`
   - `./zdm_<type>_discovery_<hostname>_<timestamp>.json`
- JSON summary must include top-level `status` (`success` or `partial`) and `warnings` array.

## Generation Quality Gate And Validation Evidence

Before finalizing generated Step2 artifacts, run local non-invasive validation checks permitted by the execution boundary.

Required checks:
- Run `bash -n` on each generated shell script:
   - `Artifacts/Phase10-Migration/Step2/Scripts/zdm_source_discovery.sh`
   - `Artifacts/Phase10-Migration/Step2/Scripts/zdm_target_discovery.sh`
   - `Artifacts/Phase10-Migration/Step2/Scripts/zdm_server_discovery.sh`
   - `Artifacts/Phase10-Migration/Step2/Scripts/zdm_orchestrate_discovery.sh`
- If `shellcheck` is available, run it and resolve actionable findings.
- Any failed required validation check is stop-ship; fix and re-run until checks pass.

Final output must include a concise validation evidence summary listing checks performed and pass/fail status.

## Next Step Handoff

After generating Step2 artifacts, stop.
- Do not run discovery scripts in VS Code.
- Runtime execution is performed later on jumpbox/ZDM server.
- After runtime discovery outputs are collected, continue with `@Phase10-ZDM-Step3-Discovery-Questionnaire`.