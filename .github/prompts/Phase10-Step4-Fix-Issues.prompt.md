---
agent: agent
description: ZDM Step 4 - Resolve blockers identified in discovery
---
# ZDM Migration Step 4: Fix Issues

## Purpose
This prompt helps address blockers and critical actions identified in the Discovery Summary before proceeding to migration artifact generation. **Iteration may be required** until all issues are resolved.

## Execution Boundary (Critical)

This prompt is generation-only.
- Generate remediation scripts, verification scripts, and markdown artifacts under `Artifacts/Phase10-Migration/Step4/`
- Do not execute remediation commands, SQL, SSH, or verification checks from VS Code
- Script execution happens after commit/push, from the repository clone on the jumpbox/ZDM server

---

## Prerequisites

Before running this prompt:
1. ✅ Complete `@Phase10-ZDM-Step1-Test-SSH-Connectivity` and confirm connectivity checks pass
2. ✅ Complete `@Phase10-ZDM-Step2-Generate-Discovery-Scripts` and run discovery scripts
3. ✅ Complete `@Phase10-ZDM-Step3-Discovery-Questionnaire` to generate Discovery Summary
4. ✅ Review Discovery Summary for critical actions and blockers

---

## How to Use This Prompt

Attach the Discovery Summary and run this prompt to get remediation guidance:

Configuration precedence for artifact generation (mandatory):
- If `zdm-env.md` is attached, treat it as authoritative generation input for environment-specific values in scripts and documentation.
- Prefer `zdm-env.md` over template defaults/examples when generating hostnames, users, key paths, Oracle homes, SIDs, unique names, and ZDM paths.
- If `zdm-env.md` conflicts with prior discovery evidence, keep both: generate fixes aligned to `zdm-env.md` intent and explicitly document the mismatch and verification step.

DB-specific value scope for Step 1-5 prompts:
- `SOURCE_REMOTE_ORACLE_HOME`
- `SOURCE_ORACLE_SID`
- `TARGET_REMOTE_ORACLE_HOME`
- `TARGET_ORACLE_SID`
- `SOURCE_DATABASE_UNIQUE_NAME`
- `TARGET_DATABASE_UNIQUE_NAME`

ZDM-specific value scope for Step 1-5 prompts:
- `ZDM_HOME`

```
@Phase10-ZDM-Step4-Fix-Issues

Please help me resolve the issues identified in the Discovery Summary.

## Attached Files

### Discovery Summary (from Step3)
#file:Artifacts/Phase10-Migration/Step3/Discovery-Summary.md

### Migration Questionnaire (from Step3)
#file:Artifacts/Phase10-Migration/Step3/Migration-Questionnaire.md
```

---

## Iterative Process

This step is designed to be repeated until all blockers are resolved:

```
┌─────────────────────────────────────────────────────────┐
│  Step 4: Fix Issues - Iterative Process                 │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  1. Review blockers from Discovery Summary              │
│           ↓                                             │
│  2. Generate remediation scripts/commands               │
│           ↓                                             │
│  3. Commit/push scripts and execute on jumpbox          │
│           ↓                                             │
│  4. Re-run relevant discovery scripts                   │
│           ↓                                             │
│  5. Update Issue Resolution Log                         │
│           ↓                                             │
│  ┌──────────────────────────────────────────┐           │
│  │ All blockers resolved?                   │           │
│  │   NO  → Return to step 1                 │           │
│  │   YES → Proceed to Step 5                │           │
│  └──────────────────────────────────────────┘           │
└─────────────────────────────────────────────────────────┘
```

---

## AI Instructions

When this prompt is run with the Discovery Summary attached, perform the following:

### Part 1: Issue Analysis

Analyze the Discovery Summary and categorize issues:

| Category | Priority | Examples |
|----------|----------|----------|
| ❌ **Blockers** | Critical | Database not in ARCHIVELOG mode, version incompatibility |
| ⚠️ **Required Actions** | High | Supplemental logging not enabled, OCI config missing for zdmuser |
| ⚡ **Recommendations** | Medium | Performance optimizations, security improvements |

### Part 2: Generate Remediation Scripts

For each issue, generate:

1. **Remediation Script/Commands**
   - Exact commands to fix the issue
   - Which server to run on (source, target, or ZDM)
   - **Which user to run as** — all scripts must be run as `zdmuser` on the ZDM server. Include a user guard at the top of every generated script:
     ```bash
     if [[ "$(whoami)" != "zdmuser" ]]; then
       echo "ERROR: This script must be run as zdmuser. Current user: $(whoami)"
       echo "       Switch with: sudo su - zdmuser"
       exit 1
     fi
     ```
   - SSH keys are in `/home/zdmuser/.ssh/` — generated scripts must use `~/.ssh/<keyname>.pem` paths (which expand correctly when running as `zdmuser`)
   - Runtime independence: generated scripts must not read, source, or parse `zdm-env.md`; values from `zdm-env.md` are generation-time input only

2. **Verification Commands**
   - How to verify the fix was successful
   - Expected output

3. **Rollback Commands** (if applicable)
   - How to undo the change if needed

4. **Script README File**
   - For every script file saved to `Artifacts/Phase10-Migration/Step4/Scripts/`, create a corresponding `README-<scriptname>.md` in the same directory
   - Each README must include:
     - **Purpose**: One-sentence summary of what the script does
     - **Target Server**: Which server to run on (source, target, or ZDM)
     - **Prerequisites**: Required tools, credentials, environment variables, and prior steps
     - **Environment Variables**: List every variable the script reads, with description and example value
     - **What It Does**: Numbered step-by-step walkthrough of the script logic
     - **How to Run**: Exact command(s) to execute the script, including which user to run as (e.g. "Run as `zdmuser` on the ZDM server")
     - **Expected Output**: Description of successful output and any key indicators
     - **Rollback / Undo**: How to reverse the changes if needed

#### ⚠️ SSH Shell Quoting — Mandatory Pattern for `run_sql_on_source`

When generating bash scripts that run SQL over SSH via `sudo -u oracle bash -c '...'`, SQL statements containing single-quoted string values (e.g. `'LOCATION=/path'`, `'SOME_VALUE'`) will break the outer shell quoting and cause `ORA-00922` or similar parse errors.

**Always generate the `run_sql_on_source` helper using base64 encoding:**

```bash
normalize_optional_key() {
  local raw="$1"
  [[ -z "$raw" || "$raw" == *"<"*">"* ]] && { echo ""; return; }
  echo "$raw"
}

SOURCE_SSH_KEY_NORM="$(normalize_optional_key "${SOURCE_SSH_KEY:-}")"
TARGET_SSH_KEY_NORM="$(normalize_optional_key "${TARGET_SSH_KEY:-}")"

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

The same pattern applies to any analogous `run_sql_on_target` helper. Base64 output contains only `A–Z a–z 0–9 + / =` characters and therefore can never conflict with shell quoting delimiters.

If `SOURCE_SSH_KEY` / `TARGET_SSH_KEY` are empty or placeholder values containing `<...>` in `zdm-env.md`, generated scripts must not include `-i` for that host.

### Part 3: Create Issue Resolution Log

Create the following artifacts in `Artifacts/Phase10-Migration/Step4/`:

- `Issue-Resolution-Log.md` — tracking table and per-issue details (see template below)
- `Scripts/` directory containing each remediation script **and** a `README-<scriptname>.md` alongside it

---

### Part 4: Generate Verification Script

Generate `Scripts/verify_fixes.sh` that confirms all three blockers are resolved and writes a structured Markdown results file to the repo.

#### Required capabilities

1. **Per-issue status tracking** — declare these variables in the Configuration section with safe defaults:
   ```bash
   # Per-issue status for Verification-Results output (values: PASS | FAIL | WARN)
   ISSUE1_STATUS="FAIL"; ISSUE1_DETAIL="Not checked"
   ISSUE2_STATUS="FAIL"; ISSUE2_DETAIL="Not checked"
   ISSUE3_STATUS="FAIL"; ISSUE3_DETAIL="Not checked"
   ISSUE4_STATUS="WARN"; ISSUE4_DETAIL="Not checked"
   ISSUE5_STATUS="WARN"; ISSUE5_DETAIL="Not checked"
   ```

2. **Set status inline** — after the pass/fail/warn call inside each blocker and recommended check, assign the matching `ISSUE*_STATUS` and `ISSUE*_DETAIL` variable, e.g.:
   ```bash
   if [[ "${PDB_OPEN_MODE}" == "READ WRITE" ]]; then
     pass "PDB1 is OPEN (READ WRITE) — Issue 1 resolved"
     ISSUE1_STATUS="PASS"; ISSUE1_DETAIL="OPEN_MODE = READ WRITE"
   else
     fail "PDB1 open mode is '${PDB_OPEN_MODE}' — run fix_open_pdb1.sh"
     ISSUE1_STATUS="FAIL"; ISSUE1_DETAIL="OPEN_MODE = '${PDB_OPEN_MODE}' — run fix_open_pdb1.sh"
   fi
   ```
   Apply the same pattern to:
   - Issue 2 (supplemental logging check) → `ISSUE2_STATUS` / `ISSUE2_DETAIL`
   - Issue 3 (OCI config / connectivity check) → `ISSUE3_STATUS` / `ISSUE3_DETAIL`
   - Issue 4 (source disk space check) → `ISSUE4_STATUS` / `ISSUE4_DETAIL`
   - Issue 5 (ZDM disk space check) → `ISSUE5_STATUS` / `ISSUE5_DETAIL`

3. **Write `Verification-Results.md`** — after the summary output block and the `verify_fixes.sh completed` echo, append a section that writes a Markdown results file to the Step4 directory (parent of `Verification/`) so it can be committed to the repo:

   ```bash
   # =============================================================================
   # Write structured Markdown results file (commit to repo for Step 5)
   # =============================================================================
   DB_NAME_UPPER="${ORACLE_SID^^}"
   RESULTS_FILE="$(dirname "${VERIFY_DIR}")/Verification-Results.md"

   _icon() { case "$1" in PASS) echo "✅ PASS";; FAIL) echo "❌ FAIL";; WARN) echo "⚠️  WARN";; *) echo "❓ UNKNOWN";; esac; }
   ISSUE1_ICON=$(_icon "${ISSUE1_STATUS}")
   ISSUE2_ICON=$(_icon "${ISSUE2_STATUS}")
   ISSUE3_ICON=$(_icon "${ISSUE3_STATUS}")
   ISSUE4_ICON=$(_icon "${ISSUE4_STATUS}")
   ISSUE5_ICON=$(_icon "${ISSUE5_STATUS}")

   BLOCKERS_PASSED=0
   [[ "${ISSUE1_STATUS}" == "PASS" ]] && BLOCKERS_PASSED=$((BLOCKERS_PASSED + 1))
   [[ "${ISSUE2_STATUS}" == "PASS" ]] && BLOCKERS_PASSED=$((BLOCKERS_PASSED + 1))
   [[ "${ISSUE3_STATUS}" == "PASS" ]] && BLOCKERS_PASSED=$((BLOCKERS_PASSED + 1))

   if [[ "${FAIL_COUNT}" -eq 0 ]]; then
     PROCEED_LINE="✅ YES — all 3 blockers resolved"
     COMMIT_MSG_BODY="Step4 verification passed: all blockers resolved for ${DB_NAME_UPPER}"
   else
     PROCEED_LINE="❌ NO — ${FAIL_COUNT} blocker(s) still pending"
     COMMIT_MSG_BODY="Step4 verification: ${BLOCKERS_PASSED}/3 blockers resolved for ${DB_NAME_UPPER}"
   fi

   cat > "${RESULTS_FILE}" << RESULTS_EOF
   # Step 4 Verification Results

   **Verified:** $(date -u '+%Y-%m-%d %H:%M:%S UTC')
   **Verified By:** $(whoami) on $(hostname)
   **Log:** \`$(basename "${LOG_FILE}")\` (in \`Step4/Verification/\`)

   ---

   ## Blocker Status (Must Be Resolved Before Step 5)

   | # | Issue | Status | Detail |
   |---|-------|--------|--------|
   | 1 | PDB1 is OPEN (READ WRITE) on source | ${ISSUE1_ICON} | ${ISSUE1_DETAIL} |
   | 2 | ALL COLUMNS supplemental logging on source | ${ISSUE2_ICON} | ${ISSUE2_DETAIL} |
   | 3 | OCI config (~/.oci/config) for zdmuser on ZDM server | ${ISSUE3_ICON} | ${ISSUE3_DETAIL} |

   ## Recommended Items

   | # | Item | Status | Detail |
   |---|------|--------|--------|
   | 4 | Source root disk space | ${ISSUE4_ICON} | ${ISSUE4_DETAIL} |
   | 5 | ZDM server root disk space | ${ISSUE5_ICON} | ${ISSUE5_DETAIL} |

   ---

   ## Summary

   - **Blockers Resolved:** ${BLOCKERS_PASSED}/3
   - **Proceed to Step 5:** ${PROCEED_LINE}
   RESULTS_EOF

   echo ""
   echo "  📄 Verification results written to:"
   echo "  ${RESULTS_FILE}"
   echo ""
   echo "  Commit to repo when ready to proceed to Step 5:"
   echo "    git add Artifacts/Phase10-Migration/Step4/Verification-Results.md"
   echo "    git commit -m \"${COMMIT_MSG_BODY}\""
   ```

4. **Write the results file into the repo clone** — use `BASH_SOURCE[0]` to locate the script, then `git rev-parse --show-toplevel` from that directory to find the repo root. Write `Verification-Results.md` there so the user can commit it without any extra copy step. Fall back to the local `~/Artifacts/...` path only if not running inside a git repo:

   ```bash
   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   REPO_ROOT=$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel 2>/dev/null || echo "")

   if [[ -n "${REPO_ROOT}" ]]; then
     RESULTS_BASE="${REPO_ROOT}/Artifacts/Phase10-Migration/Step4"
   else
     RESULTS_BASE="$(dirname "${VERIFY_DIR}")"
   fi
   mkdir -p "${RESULTS_BASE}"
   RESULTS_FILE="${RESULTS_BASE}/Verification-Results.md"
   ```

5. **Place the results file write + git instructions** after the `verify_fixes.sh completed` echo line and before the final `exit 1` guard — so the file is always written regardless of pass/fail, enabling partial progress to be committed. After writing the file, echo the manual git commands for the user to run — do **not** run git commands automatically:

   ```bash
   echo ""
   echo "  📄 Verification results written to:"
   echo "  ${RESULTS_FILE}"
   echo ""
   echo "  Commit and push to repo before running Step 5:"
   echo "    cd \"${REPO_ROOT:-<repo-root>}\""
   echo "    git add Artifacts/Phase10-Migration/Step4/Verification-Results.md"
   echo "    git commit -m \"${COMMIT_MSG_BODY}\""
   echo "    git push"
   ```

6. **`VERIFY_DIR` path** — point the log output subdirectory at `${HOME}/Artifacts/Phase10-Migration/Step4/Verification`. Logs stay local; only the results file goes into the repo clone.

**Issue Resolution Log template:**

```markdown
# Issue Resolution Log

## Summary
| Issue | Status | Date Resolved | Verified By |
|-------|--------|---------------|-------------|
| Enable supplemental logging | 🔲 Pending | | |
| Configure OCI authentication for zdmuser | 🔲 Pending | | |
| Configure network connectivity | 🔲 Pending | | |

## Issue Details

### Issue 1: [Issue Name]
**Category:** ❌ Blocker / ⚠️ Required / ⚡ Recommended
**Status:** 🔲 Pending / 🔄 In Progress / ✅ Resolved

**Problem:**
[Description of the issue]

**Remediation:**
```bash
# Commands to fix the issue
```

**Verification:**
```bash
# Commands to verify the fix
```

**Resolution Notes:**
[Notes about how this was resolved, date, by whom]

---
```

---

## Common Issues and Remediation

### Source Database Issues

#### 1. Supplemental Logging Not Enabled
```sql
-- Connect as SYS
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (PRIMARY KEY) COLUMNS;
ALTER SYSTEM SWITCH LOGFILE;

-- Verify
SELECT SUPPLEMENTAL_LOG_DATA_MIN, SUPPLEMENTAL_LOG_DATA_PK FROM V$DATABASE;
```

#### 2. ARCHIVELOG Mode Not Enabled
```sql
-- Requires database restart
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;

-- Verify
ARCHIVE LOG LIST;
```

#### 3. Force Logging Not Enabled
```sql
ALTER DATABASE FORCE LOGGING;

-- Verify
SELECT FORCE_LOGGING FROM V$DATABASE;
```

### ZDM Server Issues

#### 4. OCI Authentication Config Missing or Invalid
```bash
# Check OCI config for zdmuser on ZDM server
ls -l ~/.oci/config ~/.oci/oci_api_key.pem

# Validate expected key settings exist
grep -E '^(user|fingerprint|tenancy|region|key_file)=' ~/.oci/config

# Verify key file permissions
stat -c '%a %n' ~/.oci/oci_api_key.pem
```

#### 5. SSH Key Authentication Issues

> **IMPORTANT:** ZDM uses admin users with sudo, NOT direct SSH as oracle.
> If Step 2 discovery completed successfully, SSH is already working.
> All fix scripts run **as zdmuser** on the ZDM server; SSH keys must be in `/home/zdmuser/.ssh/`.

```bash
# Normalize keys first: empty or <...> placeholder means "no -i"
SOURCE_SSH_KEY_NORM="$(normalize_optional_key "${SOURCE_SSH_KEY:-}")"
TARGET_SSH_KEY_NORM="$(normalize_optional_key "${TARGET_SSH_KEY:-}")"

# SSH Pattern: zdmuser on ZDM server → SSH as admin user → sudo to oracle
# Source: ssh ${SOURCE_SSH_KEY_NORM:+-i "$SOURCE_SSH_KEY_NORM"} SOURCE_SSH_USER@host → sudo -u oracle
# Target: ssh ${TARGET_SSH_KEY_NORM:+-i "$TARGET_SSH_KEY_NORM"} TARGET_SSH_USER@host → sudo -u oracle

# Test SSH connectivity (run as zdmuser on ZDM server)
ssh ${SOURCE_SSH_KEY_NORM:+-i "$SOURCE_SSH_KEY_NORM"} ${SOURCE_SSH_USER}@<source_host> "sudo -u oracle whoami"  # Should print: oracle
ssh ${TARGET_SSH_KEY_NORM:+-i "$TARGET_SSH_KEY_NORM"} ${TARGET_SSH_USER}@<target_host> "sudo -u oracle whoami"  # Should print: oracle
```

### Network Issues

#### 6. Connectivity Between Servers
```bash
# From ZDM server, test connectivity
nc -zv <source_ip> 22
nc -zv <source_ip> 1521
nc -zv <target_ip> 22
nc -zv <target_ip> 1521

# If blocked, configure NSG/firewall rules in Azure/OCI console
```

---

## Re-Running Discovery

After fixing issues, re-run the relevant discovery script as `zdmuser` on the ZDM server:

```bash
# Switch to zdmuser if not already
sudo su - zdmuser

# Re-run source discovery
cd ~/Artifacts/Phase10-Migration/Step2/Scripts
./zdm_orchestrate_discovery.sh source

# Or run individual scripts directly
SOURCE_SSH_KEY_NORM="$(normalize_optional_key "${SOURCE_SSH_KEY:-}")"
ssh ${SOURCE_SSH_KEY_NORM:+-i "$SOURCE_SSH_KEY_NORM"} ${SOURCE_SSH_USER}@${SOURCE_HOST} 'ORACLE_USER=oracle bash -s' < zdm_source_discovery.sh
```

Save updated discovery outputs to:
`Artifacts/Phase10-Migration/Step4/Verification/`

---

## Completion Checklist

Before proceeding to Step 5, ensure:

- [ ] All ❌ Blockers are resolved
- [ ] All ⚠️ Required Actions are completed
- [ ] Issue Resolution Log is updated with all resolutions
- [ ] Each remediation script has a corresponding `README-<scriptname>.md` saved alongside it
- [ ] Verification discovery has been re-run
- [ ] No new blockers identified in verification
- [ ] `verify_fixes.sh` has been run and all critical checks PASSED
- [ ] `Verification-Results.md` committed and pushed to repo (run the git commands printed by the script)

---

## Next Steps

Once all issues are resolved:

1. ✅ Save Issue Resolution Log
2. ✅ Ensure each remediation script has a `README-<scriptname>.md` saved alongside it
3. ✅ Run `verify_fixes.sh` — confirm all checks PASS
4. ✅ Run the git commands printed by the script to commit and push `Verification-Results.md`
5. ✅ Ensure verification discovery files are saved
6. 🔲 Run `@Phase10-ZDM-Step5-Generate-Migration-Artifacts` with:
   - Completed questionnaire from Step 3
   - Issue Resolution Log from Step 4
   - `Verification-Results.md` from Step 4
   - Latest discovery files

---

*Generated by ZDM Migration Planning - Step 4*
