# ZDM Migration Step 2: Fix Issues

> **Note:** Replace `<DATABASE_NAME>` with your database name (e.g., PRODDB, HRDB, etc.). The value you specify in Example-Step0-Generate-Discovery-Scripts.prompt.md will be used throughout all steps.

## Purpose
This prompt helps address blockers and critical actions identified in the Discovery Summary before proceeding to migration artifact generation. **Iteration may be required** until all issues are resolved.

---

## Prerequisites

Before running this prompt:
1. ✅ Complete `Step0-Generate-Discovery-Scripts.prompt.md` and run discovery scripts
2. ✅ Complete `Step1-Discovery-Questionnaire.prompt.md` to generate Discovery Summary
3. ✅ Review Discovery Summary for critical actions and blockers

---

## How to Use This Prompt

Attach the Discovery Summary and run this prompt to get remediation guidance:

```
@Step2-Fix-Issues.prompt.md

Please help me resolve the issues identified in the Discovery Summary for our <DATABASE_NAME> migration.

## Attached Files

### Discovery Summary (from Step1)
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step1/Discovery-Summary-<DATABASE_NAME>.md

### Migration Questionnaire (from Step1)
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step1/Migration-Questionnaire-<DATABASE_NAME>.md
```

---

## Iterative Process

This step is designed to be repeated until all blockers are resolved:

```
┌─────────────────────────────────────────────────────────┐
│  Step 2: Fix Issues - Iterative Process                 │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  1. Review blockers from Discovery Summary              │
│           ↓                                             │
│  2. Generate remediation scripts/commands               │
│           ↓                                             │
│  3. Execute remediation steps                           │
│           ↓                                             │
│  4. Re-run relevant discovery scripts                   │
│           ↓                                             │
│  5. Update Issue Resolution Log                         │
│           ↓                                             │
│  ┌──────────────────────────────────────────┐           │
│  │ All blockers resolved?                   │           │
│  │   NO  → Return to step 1                 │           │
│  │   YES → Proceed to Step 3                │           │
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
| ⚠️ **Required Actions** | High | Supplemental logging not enabled, OCI CLI not installed |
| ⚡ **Recommendations** | Medium | Performance optimizations, security improvements |

### Part 2: Generate Remediation Scripts

For each issue, generate:

1. **Remediation Script/Commands**
   - Exact commands to fix the issue
   - Which server to run on (source, target, or ZDM)
   - Required privileges

2. **Verification Commands**
   - How to verify the fix was successful
   - Expected output

3. **Rollback Commands** (if applicable)
   - How to undo the change if needed

4. **Script README File**
   - For every script file saved to `Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step2/Scripts/`, create a corresponding `README-<scriptname>.md` in the same directory
   - Each README must include:
     - **Purpose**: One-sentence summary of what the script does
     - **Target Server**: Which server to run on (source, target, or ZDM)
     - **Prerequisites**: Required tools, credentials, environment variables, and prior steps
     - **Environment Variables**: List every variable the script reads, with description and example value
     - **What It Does**: Numbered step-by-step walkthrough of the script logic
     - **How to Run**: Exact command(s) to execute the script
     - **Expected Output**: Description of successful output and any key indicators
     - **Rollback / Undo**: How to reverse the changes if needed

#### ⚠️ SSH Shell Quoting — Mandatory Pattern for `run_sql_on_source`

When generating bash scripts that run SQL over SSH via `sudo -u oracle bash -c '...'`, SQL statements containing single-quoted string values (e.g. `'LOCATION=/path'`, `'SOME_VALUE'`) will break the outer shell quoting and cause `ORA-00922` or similar parse errors.

**Always generate the `run_sql_on_source` helper using base64 encoding:**

```bash
run_sql_on_source() {
  local sql_block="$1"
  local encoded_sql
  encoded_sql=$(printf '%s\n' "${sql_block}" | base64 -w 0)
  ssh -i "${SOURCE_SSH_KEY}" \
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

### Part 3: Create Issue Resolution Log

Create the following artifacts in `Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step2/`:

- `Issue-Resolution-Log-<DATABASE_NAME>.md` — tracking table and per-issue details (see template below)
- `Scripts/` directory containing each remediation script **and** a `README-<scriptname>.md` alongside it

**Issue Resolution Log template:**

```markdown
# Issue Resolution Log: <DATABASE_NAME>

## Summary
| Issue | Status | Date Resolved | Verified By |
|-------|--------|---------------|-------------|
| Enable supplemental logging | 🔲 Pending | | |
| Install OCI CLI | 🔲 Pending | | |
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

#### 4. OCI CLI Not Installed
```bash
# Install OCI CLI
bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"

# Configure
oci setup config

# Verify
oci os ns get
```

#### 5. SSH Key Authentication Issues

> **IMPORTANT:** ZDM uses admin users with sudo, NOT direct SSH as oracle.
> If Step 0 discovery completed successfully, SSH is already working.

```bash
# SSH Pattern: admin user + sudo to oracle
# Source: ssh SOURCE_ADMIN_USER@host → sudo -u oracle
# Target: ssh TARGET_ADMIN_USER@host → sudo -u oracle

# Test SSH (as configured admin users, not oracle)
ssh -i <key> ${SOURCE_ADMIN_USER}@<source_host> "sudo -u oracle whoami"  # Should print: oracle
ssh -i <key> ${TARGET_ADMIN_USER}@<target_host> "sudo -u oracle whoami"  # Should print: oracle

# Example with typical users:
ssh -i iaas.pem temandin@source_host "sudo -u oracle whoami"
ssh opc@target_host "sudo -u oracle whoami"
```

**Note:** "SSH directory not found for oracle user" is NOT a blocker - we don't SSH as oracle.

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

After fixing issues, re-run the relevant discovery script:

```bash
# From ZDM server, re-run source discovery (uses SOURCE_ADMIN_USER automatically)
./zdm_orchestrate_discovery.sh source

# Or run individual scripts (SSH as admin user, script will sudo to oracle)
ssh -i <key> ${SOURCE_ADMIN_USER}@<source_host> 'ORACLE_USER=oracle bash -s' < zdm_source_discovery.sh

# Example:
ssh -i iaas.pem temandin@10.1.0.10 'ORACLE_USER=oracle bash -s' < zdm_source_discovery.sh
```

Save updated discovery outputs to:
`Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step2/Verification/`

---

## Completion Checklist

Before proceeding to Step 3, ensure:

- [ ] All ❌ Blockers are resolved
- [ ] All ⚠️ Required Actions are completed
- [ ] Issue Resolution Log is updated with all resolutions
- [ ] Each remediation script has a corresponding `README-<scriptname>.md` saved alongside it
- [ ] Verification discovery has been re-run
- [ ] No new blockers identified in verification

---

## Next Steps

Once all issues are resolved:

1. ✅ Save Issue Resolution Log
2. ✅ Ensure each remediation script has a `README-<scriptname>.md` saved alongside it
3. ✅ Ensure verification discovery files are saved
4. 🔲 Run `Step3-Generate-Migration-Artifacts.prompt.md` with:
   - Completed questionnaire from Step 1
   - Issue Resolution Log from Step 2
   - Latest discovery files

---

*Generated by ZDM Migration Planning - Step 2*
