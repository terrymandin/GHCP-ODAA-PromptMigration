---
mode: agent
description: ZDM Step 5 - Resolve blockers identified in Step 4 discovery analysis and produce a verified Issue Resolution Log before migration artifact generation
---
# ZDM Migration Step 5: Fix Issues

## Purpose

This step generates remediation and verification artifacts for all blockers and required actions identified in the Step 4 Discovery Summary. **Iteration may be required** until all blockers are resolved.

Generated artifacts:
- `Issue-Resolution-Log.md` — issue register with status, evidence, remediation plans, and iteration history
- `Scripts/` — remediation scripts, each with a `README-<scriptname>.md` companion
- `verify_fixes.sh` — generates `Verification-Results.md` for Step 6 consumption
- `README.md` — step summary and review checklist

**Scripts are generated and saved to disk only. No scripts are executed during this prompt** (S5-09). Execution is the operator's responsibility after reviewing the generated artifacts.

---

## Execution Model

This step runs under the **Remote-SSH execution model** (CR-03): VS Code is connected to the ZDM jumpbox as `zdmuser`, and Copilot generates all artifacts using file tools — **no scripts are executed during this prompt**.

- All outputs are written to `Artifacts/Phase10-Migration/Step5/` (git-ignored). No generated files are committed or create PRs.
- OCI CLI is not required for this step or any Phase10 migration execution step (CR-06).
- Generated scripts must not read, source, or parse config artifacts at runtime (CR-02).

Input precedence rules (CR-01):
1. `Artifacts/Phase10-Migration/Step4/Discovery-Summary.md` — primary evidence input (observed runtime state).
2. `Artifacts/Phase10-Migration/Step4/Migration-Decisions.md` — confirmed RSP parameter decisions from Step 4.
3. `Artifacts/Phase10-Migration/Step3/db-config.md` — DB and ZDM variable source for script generation.
4. `Artifacts/Phase10-Migration/Step2/ssh-config.md` — SSH connectivity variables for script generation.
5. `zdm-env.md` (when explicitly attached) — legacy override with higher precedence than step artifacts.
6. If configured intent conflicts with discovery evidence, keep both: generate fixes aligned to the configured intent and explicitly document the mismatch and required verification step.
7. Placeholder values containing `<...>` are treated as unset.

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

## Part 2: Generate Remediation Scripts

For each blocker and required action, generate a remediation script under `Artifacts/Phase10-Migration/Step5/Scripts/`.

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

5. **No script is executed during this prompt** (S5-09). All scripts are written to disk only. Values from config artifacts and `zdm-env.md` are generation-time input; generated scripts must not read, source, or parse them at runtime.

**Per-script README (S5-07):**

For every script in `Scripts/`, create a companion `README-<scriptname>.md` in the same directory containing:
- **Purpose**: one-sentence summary
- **Target Server**: which server to run on (source / target / ZDM)
- **Prerequisites**: required tools, credentials, prior steps
- **Environment Variables**: list every variable the script reads, with description and example value
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

## Part 5: Generate Step 5 README

Write `Artifacts/Phase10-Migration/Step5/README.md` (CR-08) summarizing:
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

## Part 6: Generation Quality Gate (CR-12)

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
    ├── README.md                        # Step summary, operator checklist, next steps
    ├── Issue-Resolution-Log.md          # Issue register, evidence, iteration history
    ├── Verification-Results.md          # Written by operator running verify_fixes.sh
    └── Scripts/
        ├── verify_fixes.sh              # Verification script — writes Verification-Results.md
        ├── fix_<issue>.sh               # Per-issue remediation script(s)
        └── README-<scriptname>.md       # Companion README per script
```

All files are git-ignored. No outputs are committed or create PRs.

---

## Completion Checklist

Before proceeding to Step 6, confirm:

- [ ] All ❌ Blockers resolved in `Issue-Resolution-Log.md`
- [ ] All ⚠️ Required Actions completed
- [ ] Each remediation script has a `README-<scriptname>.md` alongside it
- [ ] `verify_fixes.sh` has been run by the operator — all blocker checks PASS
- [ ] `Verification-Results.md` is present in `Artifacts/Phase10-Migration/Step5/`
- [ ] No new blockers introduced by remediation

---

## Next Step

After all blockers are resolved and `Verification-Results.md` shows all-PASS:

> Run **`@Phase10-Step6-Generate-Migration-Artifacts`** in this Remote-SSH VS Code session connected to the ZDM jumpbox as **`zdmuser`**.

