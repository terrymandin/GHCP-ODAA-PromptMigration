# ZDM Migration Step 2: Fix Issues

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

Please help me resolve the issues identified in the Discovery Summary for our <DATABASE> migration.

## Attached Files

### Discovery Summary (from Step1)
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE>/Step1/Discovery-Summary-<DATABASE>.md

### Migration Questionnaire (from Step1)
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE>/Step1/Migration-Questionnaire-<DATABASE>.md
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

### Part 3: Create Issue Resolution Log

Create a file `Issue-Resolution-Log-<DATABASE>.md` in `Artifacts/Phase10-Migration/ZDM/<DATABASE>/Step2/` tracking:

```markdown
# Issue Resolution Log: <DATABASE>

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
```bash
# Generate SSH key if needed
ssh-keygen -t rsa -b 4096 -f ~/.ssh/zdm_key

# Copy to source/target
ssh-copy-id -i ~/.ssh/zdm_key.pub oracle@<source_host>
ssh-copy-id -i ~/.ssh/zdm_key.pub opc@<target_host>

# Test
ssh -i ~/.ssh/zdm_key oracle@<source_host> "echo 'Source OK'"
ssh -i ~/.ssh/zdm_key opc@<target_host> "echo 'Target OK'"
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

After fixing issues, re-run the relevant discovery script:

```bash
# From ZDM server, re-run source discovery
./zdm_orchestrate_discovery.sh source

# Or run individual scripts
ssh oracle@<source_host> 'bash -s' < zdm_source_discovery.sh
```

Save updated discovery outputs to:
`Artifacts/Phase10-Migration/ZDM/<DATABASE>/Step2/Verification/`

---

## Completion Checklist

Before proceeding to Step 3, ensure:

- [ ] All ❌ Blockers are resolved
- [ ] All ⚠️ Required Actions are completed
- [ ] Issue Resolution Log is updated with all resolutions
- [ ] Verification discovery has been re-run
- [ ] No new blockers identified in verification

---

## Next Steps

Once all issues are resolved:

1. ✅ Save Issue Resolution Log
2. ✅ Ensure verification discovery files are saved
3. 🔲 Run `Step3-Generate-Migration-Artifacts.prompt.md` with:
   - Completed questionnaire from Step 1
   - Issue Resolution Log from Step 2
   - Latest discovery files

---

*Generated by ZDM Migration Planning - Step 2*
