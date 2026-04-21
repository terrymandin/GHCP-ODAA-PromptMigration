---
mode: agent
description: ZDM Step 5 - Resolve blockers identified in Step 4 discovery analysis and produce a verified Issue Resolution Log before migration artifact generation
---
# ZDM Migration Step 5: Fix Issues

## Purpose

This step generates remediation and verification artifacts for all blockers and required actions identified in the Step 4 Discovery Summary. **Iteration may be required** until all blockers are resolved.

Generated artifacts:
- `Issue-Resolution-Log.md` — issue register with status, evidence, remediation plans, and iteration history
- `Scripts/fix_<issue-id>_<short-name>.sh` — one remediation script per remediable issue
- `Scripts/fix_orchestrator.sh` — orchestrator that invokes individual fix scripts in dependency order
- `Scripts/README-fix_<issue-id>_<short-name>.md` — companion README per fix script
- `Scripts/README-fix_orchestrator.md` — companion README for the orchestrator
- `Scripts/verify_fixes.sh` — generates `Verification-Results.md` for Step 6 consumption
- `README.md` — step summary and review checklist

**Scripts are generated and saved to disk by default** (S5-09). Execution is the operator's responsibility after reviewing the generated artifacts. Conditional inline execution is available after the script inventory and risk banner are presented — see Part 5.

---

## Execution Model

This step runs under the **Remote-SSH execution model** (CR-03): VS Code is connected to the ZDM jumpbox as `zdmuser`, and Copilot generates all artifacts using file tools — **no scripts are executed during this prompt**.

- All outputs are written to `Artifacts/Phase10-Migration/Step5/` (git-ignored). No generated files are committed or create PRs.
- OCI CLI is not required for this step or any Phase10 migration execution step (CR-06).
- Generated scripts must not read, source, or parse config artifacts at runtime (CR-02).
- **Environment scope (CR-13):** This prompt step is intended for **development and non-production environments only**. Do not run Copilot agent steps directly against production systems. Generated scripts are safe to copy to production once reviewed and tested in development — see the risk banner in Part 5 for the script promotion path.

Input precedence rules (CR-01):
1. `Artifacts/Phase10-Migration/Step4/Discovery-Summary.md` — primary evidence input (observed runtime state).
2. `Artifacts/Phase10-Migration/Step4/Migration-Decisions.md` — confirmed RSP parameter decisions from Step 4.
3. `Artifacts/Phase10-Migration/Step3/db-config.md` — DB and ZDM variable source for script generation.
4. `Artifacts/Phase10-Migration/Step2/ssh-config.md` — SSH connectivity variables for script generation.
5. `zdm-env.md` (when explicitly attached) — legacy override with higher precedence than step artifacts.
6. If configured intent conflicts with discovery evidence, keep both: generate fixes aligned to the configured intent and explicitly document the mismatch and required verification step.
7. Placeholder values containing `<...>` are treated as unset.

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
1. ✅ Complete `@Phase10-Step1-Setup-Remote-SSH` — VS Code is connected via Remote-SSH as `zdmuser`
2. ✅ Complete `@Phase10-Step2-Configure-SSH-Connectivity` — `Artifacts/Phase10-Migration/Step2/ssh-config.md` exists
3. ✅ Complete `@Phase10-Step3-Generate-Discovery-Scripts` — discovery reports exist in `Artifacts/Phase10-Migration/Step3/Discovery/`
4. ✅ Complete `@Phase10-Step4-Discovery-Questionnaire` — `Artifacts/Phase10-Migration/Step4/Discovery-Summary.md` and `Migration-Decisions.md` exist
5. ✅ Review Discovery Summary for critical blockers and required actions

---

## How to Use This Prompt

Attach the Step 4 artifacts and run this prompt:

```
@Phase10-Step5-Fix-Issues

Please generate remediation scripts and the Issue Resolution Log for all blockers and required actions.

## Attached Configuration (read-only)
#file:Artifacts/Phase10-Migration/Step2/ssh-config.md
#file:Artifacts/Phase10-Migration/Step3/db-config.md

## Step 4 Analysis Artifacts
#file:Artifacts/Phase10-Migration/Step4/Discovery-Summary.md
#file:Artifacts/Phase10-Migration/Step4/Migration-Decisions.md

## Optional: Legacy override
#file:zdm-env.md
```

---

## Iterative Operation Model (S5-02)

Step 5 supports repeated cycles until all blockers are resolved:

```
┌─────────────────────────────────────────────────────────┐
│  Step 5: Fix Issues - Iterative Process                 │
├─────────────────────────────────────────────────────────┤
│  1. Review blockers from Discovery Summary              │
│           ↓                                             │
│  2. Generate remediation scripts (this prompt)          │
│           ↓                                             │
│  3. Operator executes scripts from jumpbox terminal     │
│           ↓                                             │
│  4. Operator runs verify_fixes.sh to check results      │
│           ↓                                             │
│  5. Re-run Step 3 discovery if evidence refresh needed  │
│           ↓                                             │
│  6. Update Issue Resolution Log (re-run this prompt)    │
│           ↓                                             │
│  ┌──────────────────────────────────────────┐           │
│  │ All blockers resolved?                   │           │
│  │   NO  → Return to step 2                 │           │
│  │   YES → Proceed to Step 6                │           │
│  └──────────────────────────────────────────┘           │
└─────────────────────────────────────────────────────────┘
```

Each iteration updates `Issue-Resolution-Log.md` with iteration history and verification outcomes.

---

## Part 1: Issue Analysis

Analyze the Discovery Summary and categorize all issues:

| Category | Priority | Examples |
|----------|----------|----------|
| ❌ **Blockers** | Critical | Database not in ARCHIVELOG mode, version incompatibility |
| ⚠️ **Required Actions** | High | Supplemental logging not enabled, OCI config missing for zdmuser |
| ⚡ **Recommendations** | Medium | Performance optimizations, disk space warnings |

---

## Part 1b: Generate Layer 1 Infrastructure Pre-flight Script (S5-08, CR-14-A)

Before generating database-level fix scripts, generate the Layer 1 infrastructure pre-flight check script from the CR-14 prerequisite catalog.

### Prerequisite catalog access

Apply the CR-14-A version lookup protocol to read the catalog file before generating this script:

1. Determine the ZDM version from `db-config.md` or the most recent ZDM server discovery report.
2. Determine the migration method from `Migration-Decisions.md`; default to `ONLINE_PHYSICAL` if not yet confirmed.
3. Select the catalog file path:
   - `ONLINE_PHYSICAL` → `.github/requirements/Phase10/ZDM-Prerequisites/<version>/online-physical.md`
   - `OFFLINE_PHYSICAL` → `.github/requirements/Phase10/ZDM-Prerequisites/<version>/offline-physical.md`
4. Use `read_file` to load the catalog file. If the version directory does not exist, substitute `26.1` and log a warning.

Do NOT use `fetch_webpage` for ZDM documentation. Do NOT read or write `Artifacts/Phase10-Migration/ZDM-Doc-Checks/`.

### Generated artifacts

Write the following files using file tools:

- `Artifacts/Phase10-Migration/Step5/Scripts/preflight_l1_infrastructure.sh`
- `Artifacts/Phase10-Migration/Step5/Scripts/README-preflight_l1_infrastructure.md`

### Script generation rules

1. Read the **"Layer 1 — Infrastructure"** section of the CR-14 catalog file (loaded per CR-14-A above).
2. For each row in that section, generate a corresponding shell check using the `Verification command` column from the catalog row.
3. Label each check in the script output with `L1_CHECK:<check-name>:<status>` and the doc section from the catalog row so a human can trace it back to ZDM documentation.
4. Each check must report `[PASS]`, `[FAIL]`, or `[SKIP]` with a one-line explanation.
5. Script must **not** abort on first failure — run all checks and summarize at the end.
6. Exit code 0 if all checks pass; non-zero if any check fails.
7. All failures must include the exact command that failed and the output received.
8. Include a comment block at the top listing the cache file path and the date the script was generated from it.

```bash
# LAYER 1 PRE-FLIGHT CHECK SCRIPT
# Generated from: .github/requirements/Phase10/ZDM-Prerequisites/<version>/<method>.md
# Generated on:   <YYYY-MM-DD HH:MM UTC>
# ZDM Version:    <zdm-version>
#
# Usage: Run as zdmuser on the ZDM jumpbox.
#        bash Scripts/preflight_l1_infrastructure.sh

[ "$(id -un)" = "zdmuser" ] || { echo "ERROR: must run as zdmuser"; exit 1; }

# Results are prefixed: L1_CHECK:<check-name>:<PASS|FAIL|SKIP>
```

### Layer 1 pre-flight relationship to database fix scripts

Layer 1 failures are **blocking** for the database-level fix menu (S5-07). This script will be executed in Part 5 (Step 5b) after the operator confirms the CONFIRM banner. All Layer 1 checks must PASS before the database fix script inventory (Step 5c) is presented.

---

## Part 2: Generate Remediation Scripts

For each blocker and required action, generate a remediation script under `Artifacts/Phase10-Migration/Step5/Scripts/`. Use this naming convention (S5-07):

```
Scripts/fix_<issue-id>_<short-name>.sh
```

Examples: `fix_B01_enable_archivelog.sh`, `fix_B02_create_spfile.sh`, `fix_W01_upgrade_timezone.sh`.
`<issue-id>` uses the Issue-Resolution-Log ID. `<short-name>` is a 2–4 word snake_case description.

### Target-first remediation preference (S5-10)

When a compatibility fix can be applied to either source or target, **generate the script for the target database**. Source-side scripts are generated only when the fix is source-only by nature:

| Fix type | Target for script |
|----------|------------------|
| `ARCHIVELOG` mode | Source (source-only) |
| SPFILE creation | Source (source-only) |
| RMAN configuration | Source (source-only) |
| Source TDE wallet creation/key management | Source (source-only) |
| `COMPATIBLE` parameter alignment | **Target** — set source value on target (lowering source not supported) |
| Timezone file upgrade | **Target** — upgrade target to ≥ source |
| `/tmp` execute permission | **Target** (and source if also failing) |
| `SQLNET.ORA` encryption alignment | **Target** — update target to match source |
| TDE wallet OPEN status | **Target** — open/configure on target |

Each companion README must state which server the script targets and **why** (source-only by nature, or target-preferred per this policy).

### Scope classification (S5-12)

Each fix script must declare its **scope** based on the broadest system component it modifies:

| Scope | Meaning | Examples |
|-------|---------|----------|
| `DATABASE` | Affects only the named database instance | `COMPATIBLE`, ARCHIVELOG, SPFILE, TDE wallet, RMAN config |
| `ORACLE-HOME` | Affects all databases sharing this Oracle Home | `SQLNET.ORA` encryption settings, timezone file upgrade |
| `OS` | Affects all processes on the host | `/tmp` mount flags |

Scope must be declared in:
1. The script header block (add `# SCOPE: DATABASE | ORACLE-HOME | OS` after `# TARGET:`).
2. The companion `README-fix_<issue-id>_<short-name>.md` as a **Scope** field with a plain-English explanation of what else on the server could be affected.
3. The script inventory table in Part 5 as a **Scope** column.

**Script requirements (S5-03, S5-04):**

1. All scripts run as `zdmuser` on the ZDM server. Include a user guard at the top of every script:
   ```bash
   if [[ "$(whoami)" != "zdmuser" ]]; then
     echo "ERROR: This script must be run as zdmuser. Current user: $(whoami)"
     echo "       Switch with: sudo su - zdmuser"
     exit 1
   fi
   ```

2. SSH keys are in `/home/zdmuser/.ssh/`. Generated scripts must use `~/.ssh/<keyname>` paths (expand correctly when running as `zdmuser`).

3. All scripts must include the `normalize_optional_key` helper and use it for SSH key handling. Include `-i` only when the key is set and non-placeholder:
   ```bash
   normalize_optional_key() {
     local raw="$1"
     [[ -z "$raw" || "$raw" == *"<"*">"* ]] && { echo ""; return; }
     echo "$raw"
   }
   SOURCE_SSH_KEY_NORM="$(normalize_optional_key "${SOURCE_SSH_KEY:-}")"
   TARGET_SSH_KEY_NORM="$(normalize_optional_key "${TARGET_SSH_KEY:-}")"
   ```

4. **SSH-based SQL helpers must use base64-wrapped execution** (S5-04) to avoid shell quoting breakage when SQL contains single-quoted strings:
   ```bash
   run_sql_on_source() {
     local sql_block="$1"
     local encoded_sql
     encoded_sql=$(printf '%s\n' "${sql_block}" | base64 -w 0)
     ssh ${SOURCE_SSH_KEY_NORM:+-i "${SOURCE_SSH_KEY_NORM}"} \
         -o StrictHostKeyChecking=no \
         -o ConnectTimeout=10 \
         "${SOURCE_SSH_USER}@${SOURCE_HOST}" \
         "sudo -u ${ORACLE_USER} bash -c '
           export ORACLE_HOME=${ORACLE_HOME}
           export ORACLE_SID=${ORACLE_SID}
           export PATH=\${ORACLE_HOME}/bin:\${PATH}
           echo \"${encoded_sql}\" | base64 -d | sqlplus -S / as sysdba
         '"
   }
   ```
   Apply the same pattern to `run_sql_on_target`. Base64 output (`A–Z a–z 0–9 + / =`) never conflicts with shell quoting delimiters.

5. **Scripts are written to disk by default** (S5-09). Values from config artifacts and `zdm-env.md` are generation-time input; generated scripts must not read, source, or parse them at runtime. Inline execution requires explicit user request after the Part 5 risk banner and inventory are presented.

### Orchestrator script (S5-07)

Generate `Artifacts/Phase10-Migration/Step5/Scripts/fix_orchestrator.sh` that:
1. Lists all fix scripts it will invoke, in dependency order, at the top as comments.
2. Invokes each fix script individually (not sources them) so failures are isolated.
3. Logs pass/fail status per script to stdout.
4. Stops on first BLOCKER-category failure unless the `--continue-on-error` flag is passed.
5. Accepts a `--dry-run` flag that prints what would be executed without running anything.

Generate `Artifacts/Phase10-Migration/Step5/Scripts/README-fix_orchestrator.md` documenting all of the above.

**Per-script companion README (S5-07):**

For every `fix_<issue-id>_<short-name>.sh`, create `Scripts/README-fix_<issue-id>_<short-name>.md` containing:
- **Purpose**: one-sentence summary
- **Target Server**: which server (`source-db`, `target-db`, or `zdm-server`) and why (source-only by nature or target-preferred per S5-10)
- **Scope**: `DATABASE`, `ORACLE-HOME`, or `OS` — with plain-English explanation of what else could be affected
- **Prerequisites**: required tools, credentials, prior steps
- **Environment Variables**: every variable the script reads, with description and example value
- **What It Does**: numbered step-by-step walkthrough
- **How to Run**: exact command including runtime user (`zdmuser` on ZDM server)
- **Expected Output**: description of successful output and key indicators
- **Rollback / Undo**: how to reverse the changes; "N/A" if not applicable

---

## Part 3: Create Issue Resolution Log

Write `Artifacts/Phase10-Migration/Step5/Issue-Resolution-Log.md` (S5-06) using this structure:

```markdown
# Issue Resolution Log

**Last Updated:** [YYYY-MM-DD HH:MM UTC]

## Summary

| Issue ID | Issue | Severity | Owner | Status | Last Updated |
|----------|-------|----------|-------|--------|--------------|
| I-01 | [Issue name] | ❌ Blocker | | 🔲 Pending | |
| I-02 | [Issue name] | ⚠️ Required | | 🔲 Pending | |

## Issue Details

### Issue I-01: [Issue Name]
**Category:** ❌ Blocker / ⚠️ Required / ⚡ Recommended
**Status:** 🔲 Pending / 🔄 In Progress / ✅ Resolved
**Last Updated:** [timestamp]

**Evidence:**
[Observed values, query results, or error messages from discovery]

**Remediation Plan:**
[Step-by-step plan — which server, which user, which script to run]

**Verification Method:**
[How to confirm the fix — expected output]

**Rollback Notes:**
[How to undo the change; "N/A" if not applicable]

---

## Iteration History

### Cycle 1 — [YYYY-MM-DD]
[Summary of what was attempted, what changed, and verification outcome]

---

## Unresolved Items and Blockers (Step 6 Prerequisites)

| Issue ID | Issue | Current Status | Blocking Reason |
|----------|-------|----------------|-----------------|
| [I-XX] | [Issue name] | 🔄 In Progress | [Why it prevents Step 6 progression] |

> ⚠️ **Step 6 must not proceed until all ❌ Blocker items are listed as ✅ Resolved.**
```

---

## Part 4: Generate Verification Script

Write `Artifacts/Phase10-Migration/Step5/Scripts/verify_fixes.sh` that checks all blockers and writes `Verification-Results.md` to `Artifacts/Phase10-Migration/Step5/`.

**Required capabilities (S5-05, S5-08):**

1. **Per-issue status tracking** — declare variables with safe defaults for each issue:
   ```bash
   # Per-issue status (values: PASS | FAIL | WARN)
   ISSUE1_STATUS="FAIL"; ISSUE1_DETAIL="Not checked"
   ISSUE2_STATUS="FAIL"; ISSUE2_DETAIL="Not checked"
   ISSUE3_STATUS="WARN"; ISSUE3_DETAIL="Not checked"
   ```

2. **Set status inline** after each check:
   ```bash
   if [[ "${ARCHIVELOG_MODE}" == "ARCHIVELOG" ]]; then
     ISSUE1_STATUS="PASS"; ISSUE1_DETAIL="ARCHIVELOG mode confirmed"
   else
     ISSUE1_STATUS="FAIL"; ISSUE1_DETAIL="Mode = '${ARCHIVELOG_MODE}' — run fix script"
   fi
   ```

3. **Write `Verification-Results.md`** (S5-08) after all checks complete — structured markdown visible in VS Code:
   ```bash
   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   STEP5_ARTIFACTS_DIR="$(dirname "${SCRIPT_DIR}")"
   RESULTS_FILE="${STEP5_ARTIFACTS_DIR}/Verification-Results.md"

   _icon() { case "$1" in PASS) echo "✅ PASS";; FAIL) echo "❌ FAIL";; WARN) echo "⚠️  WARN";; *) echo "❓ UNKNOWN";; esac; }

   cat > "${RESULTS_FILE}" << RESULTS_EOF
   # Step 5 Verification Results

   **Verified:** $(date -u '+%Y-%m-%d %H:%M:%S UTC')
   **Verified By:** $(whoami) on $(hostname)

   ## Blocker Status (Must Be Resolved Before Step 6)

   | # | Issue | Status | Detail |
   |---|-------|--------|---------|
   | 1 | [Blocker 1 description] | $(_icon "${ISSUE1_STATUS}") | ${ISSUE1_DETAIL} |
   | 2 | [Blocker 2 description] | $(_icon "${ISSUE2_STATUS}") | ${ISSUE2_DETAIL} |

   ## Recommended Items

   | # | Item | Status | Detail |
   |---|------|--------|---------|
   | 3 | [Recommended item] | $(_icon "${ISSUE3_STATUS}") | ${ISSUE3_DETAIL} |

   ## Summary

   - **Proceed to Step 6:** [YES — all blockers resolved / NO — N blocker(s) still pending]
   RESULTS_EOF

   echo "Verification results written to: ${RESULTS_FILE}"
   echo "Attach this file when running @Phase10-Step6-Generate-Migration-Artifacts"
   ```

4. Log output directory: `${STEP5_ARTIFACTS_DIR}/Verification/`

---

## Part 5: Present Script Inventory, Risk Banner, and Execution Options

After all scripts and companions are written to disk and the quality gate (Part 6) passes, execute this sequence.

### Step 5a: Pre-execution risk banner (S5-13, CR-13)

Always display the following banner. It is mandatory — do not skip or abbreviate it.

```
⚠ ENVIRONMENT SAFETY WARNING

These Copilot agent prompts are intended to run in development/non-production
environments only. Do not run this prompt directly against a production system.

Generated scripts are safe to copy to production once reviewed and tested in
development. For production use: review scripts, copy them to the production
host, and run manually — do not re-run this prompt on production.

[Include the following paragraph only when ORACLE-HOME or OS scope scripts exist:]
  The following scripts affect Oracle Home or OS-level settings and will impact
  ALL databases sharing that Oracle Home or host — not just the migration target:
    - <script_name>  →  <ORACLE-HOME | OS> scope  (<what it changes>)

Type CONFIRM to proceed to the execution menu, or press Enter to review scripts
manually (Option A — no execution).
```

If no `ORACLE-HOME` or `OS` scope scripts are present, omit the blast-radius paragraph but keep the rest of the banner.

Do **not** display the execution menu until the user types `CONFIRM`. If the user does not type `CONFIRM`, default to Option A (review only — no execution).

### Step 5b: Run Layer 1 Infrastructure Pre-flight (S5-08)

After `CONFIRM` is received, execute the Layer 1 pre-flight check script inline before presenting the database fix inventory:

```bash
bash ~/Artifacts/Phase10-Migration/Step5/Scripts/preflight_l1_infrastructure.sh
```

Display the full output of the pre-flight run inline in the chat.

**If all L1 checks PASS:**
- Append the pre-flight results to `Verification-Results.md` under a `### Layer 1 Infrastructure Pre-flight` section.
- Proceed to Step 5c (database fix inventory).

**If any L1 check FAILS:**
- Append the failing check results to `Verification-Results.md` under `### Layer 1 Infrastructure Pre-flight`.
- Surface each failing check name and the remediation guidance from the `[ZDM doc section]` column in the CR-14 catalog file (per CR-14-C).
- **Do not present the Step 5c database fix script inventory until all Layer 1 checks pass.**
- Instruct the operator to resolve Layer 1 failures manually using the ZDM documentation referenced in each failing check row, then re-run this prompt to retry.

### Step 5c: Script inventory table (S5-11)

After `CONFIRM` is received, present the script inventory table:

```
Generated fix scripts
---------------------
| Script                        | Target     | Severity | Scope        | Summary                            |
|-------------------------------|------------|----------|--------------|------------------------------------|  
| fix_B01_enable_archivelog.sh  | source-db  | BLOCKER  | DATABASE     | Enable ARCHIVELOG mode on source   |
| fix_B02_compatible_param.sh   | target-db  | BLOCKER  | DATABASE     | Set COMPATIBLE=12.2.0 on target    |
| fix_W01_upgrade_timezone.sh   | target-db  | WARNING  | ORACLE-HOME  | Upgrade DST timezone file          |
| fix_orchestrator.sh           | all        | —        | —            | Run all fixes in dependency order  |

Options:
  A (default) — Review scripts individually and run selectively outside this prompt.
  B — Say "run all" to execute all scripts via the orchestrator (fix_orchestrator.sh).
  C — Say "run fix_<id>" (e.g., "run fix_B01") to execute a specific script inline.
```

Do not execute any script unless the user explicitly says `run all` or `run fix_<id>` after seeing this menu (S5-09).

### Step 5d: Conditional inline execution (S5-09)

When the user triggers execution:
- **`run all`** — invoke `fix_orchestrator.sh` inline via the terminal.
- **`run fix_<id>`** — invoke the matching `fix_<issue-id>_*.sh` script inline.

For each execution:
1. Display the exact command being run before executing it.
2. Capture stdout and stderr and display them in the chat.
3. Record the exit code and execution timestamp in `Issue-Resolution-Log.md`.
4. After execution, run `Scripts/verify_fixes.sh` automatically for the affected issue(s) and report PASS/FAIL.

---

## Part 6: Generate Step 5 README

Write `Artifacts/Phase10-Migration/Step5/README.md` (CR-07) summarizing:
- **Generated files** and their purpose:
  - `Issue-Resolution-Log.md` — issue register with evidence, remediation plans, iteration history
  - `Scripts/` — remediation scripts + `README-<scriptname>.md` companions
  - `Scripts/verify_fixes.sh` — generates `Verification-Results.md`
  - `Verification-Results.md` — written by running `verify_fixes.sh` (not generated by this prompt)
- **What the operator must do** before proceeding to Step 6:
  - Review `Issue-Resolution-Log.md` for all blockers and required actions
  - Run each remediation script from the jumpbox terminal as `zdmuser`
  - Run `verify_fixes.sh` and confirm all blockers PASS
  - Check `Verification-Results.md` shows all blockers resolved
- **Success signals**: all ❌ Blocker items ✅ Resolved; `verify_fixes.sh` all-PASS; `Verification-Results.md` present in `Step5/`
- **Failure signals**: any FAIL in `Verification-Results.md`; unresolved blockers in `Issue-Resolution-Log.md`

---

## Part 7: Generation Quality Gate (CR-11)

After all scripts are written to disk, run syntax validation in the jumpbox terminal:

1. **Mandatory — bash syntax check** for every `.sh` file:
   ```bash
   for f in ~/Artifacts/Phase10-Migration/Step5/Scripts/*.sh; do
     bash -n "$f" && echo "OK: $f" || echo "FAIL: $f"
   done
   ```

2. **Optional — shellcheck** (run if available):
   ```bash
   if command -v shellcheck &>/dev/null; then
     shellcheck ~/Artifacts/Phase10-Migration/Step5/Scripts/*.sh
   fi
   ```

3. Any syntax error is a **stop-ship condition**: fix and re-run until all pass.

4. Include a concise validation evidence block in the final chat output listing each script checked and PASS/FAIL status.

---

## Common Issues and Remediation Reference

### Source Database Issues

#### Supplemental Logging Not Enabled
```sql
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (PRIMARY KEY) COLUMNS;
ALTER SYSTEM SWITCH LOGFILE;
-- Verify
SELECT SUPPLEMENTAL_LOG_DATA_MIN, SUPPLEMENTAL_LOG_DATA_PK FROM V$DATABASE;
```

#### ARCHIVELOG Mode Not Enabled
```sql
-- Requires database restart
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;
-- Verify
ARCHIVE LOG LIST;
```

#### Force Logging Not Enabled
```sql
ALTER DATABASE FORCE LOGGING;
-- Verify
SELECT FORCE_LOGGING FROM V$DATABASE;
```

### ZDM Server Issues

#### OCI Authentication Config Missing
```bash
# Check OCI config for zdmuser on ZDM server
ls -l ~/.oci/config ~/.oci/oci_api_key.pem
grep -E '^(user|fingerprint|tenancy|region|key_file)=' ~/.oci/config
stat -c '%a %n' ~/.oci/oci_api_key.pem
```

#### SSH Key Authentication Issues

> **Note:** ZDM uses admin users with `sudo -u oracle`, not direct SSH as oracle.
> If Step 3 discovery completed successfully, SSH is already working.
> All remediation scripts run as `zdmuser` on the ZDM server; SSH keys must be in `/home/zdmuser/.ssh/`.

```bash
# SSH pattern: zdmuser on ZDM server → SSH as admin user → sudo -u oracle
ssh ${SOURCE_SSH_KEY_NORM:+-i "$SOURCE_SSH_KEY_NORM"} ${SOURCE_SSH_USER}@${SOURCE_HOST} \
    "sudo -u oracle whoami"  # Should print: oracle
```

### Network Issues

#### Connectivity Between Servers
```bash
# From ZDM server, test connectivity
nc -zv ${SOURCE_HOST} 22
nc -zv ${SOURCE_HOST} 1521
nc -zv ${TARGET_HOST} 22
nc -zv ${TARGET_HOST} 1521
```

---

## Re-Running Discovery

After fixing issues, refresh evidence by re-running `@Phase10-Step3-Generate-Discovery-Scripts`. New discovery reports will be written to `Artifacts/Phase10-Migration/Step3/Discovery/` (timestamped) and can be re-attached for a follow-up Step 4 + Step 5 cycle.

---

## Output Files

```
Artifacts/Phase10-Migration/
└── Step5/
    ├── README.md                               # Step summary, operator checklist, next steps
    ├── Issue-Resolution-Log.md                 # Issue register, evidence, iteration history
    ├── Verification-Results.md                 # Written by operator running verify_fixes.sh
    ├── Verification/                           # Verification script log output directory
    └── Scripts/
        ├── preflight_l1_infrastructure.sh      # Layer 1 infrastructure pre-flight checks (S5-08)
        ├── README-preflight_l1_infrastructure.md  # Companion README for Layer 1 pre-flight
        ├── verify_fixes.sh                     # Verification script — writes Verification-Results.md
        ├── fix_<issue-id>_<short-name>.sh      # Per-issue remediation script(s)
        ├── README-fix_<issue-id>_<short-name>.md  # Companion README per fix script
        ├── fix_orchestrator.sh                 # Orchestrator — runs all fix scripts in order
        └── README-fix_orchestrator.md          # Companion README for the orchestrator
```

All files are git-ignored. No outputs are committed or create PRs.

---

## Completion Checklist

Before proceeding to Step 6, confirm:

- [ ] All ❌ Blockers resolved in `Issue-Resolution-Log.md`
- [ ] All ⚠️ Required Actions completed
- [ ] `preflight_l1_infrastructure.sh` generated and all Layer 1 checks PASS (visible in `Verification-Results.md` under `### Layer 1 Infrastructure Pre-flight`)
- [ ] Each remediation script has a `README-<scriptname>.md` alongside it
- [ ] `verify_fixes.sh` has been run by the operator — all blocker checks PASS
- [ ] `Verification-Results.md` is present in `Artifacts/Phase10-Migration/Step5/`
- [ ] No new blockers introduced by remediation

---

## Next Step

After all blockers are resolved and `Verification-Results.md` shows all-PASS:

> Run **`@Phase10-Step6-Generate-Migration-Artifacts`** in this Remote-SSH VS Code session connected to the ZDM jumpbox as **`zdmuser`**.

