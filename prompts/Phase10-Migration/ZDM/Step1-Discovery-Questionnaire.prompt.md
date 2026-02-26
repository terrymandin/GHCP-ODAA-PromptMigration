# ZDM Migration Step 1: Get Manual Configuration Context

> **Note:** Replace `<DATABASE_NAME>` with your database name (e.g., PRODDB, HRDB, etc.). The value you specify in Example-Step0-Generate-Discovery-Scripts.prompt.md will be used throughout all steps.

## Purpose
This prompt analyzes the discovery output from Step 0 and generates:
1. **Discovery Summary** - Auto-populated findings from the discovery scripts
2. **Migration Planning Questionnaire** - Questions requiring manual input with recommended defaults

---

## Migration Flow Overview

```
Step 0: Run Scripts to Get Context
         ↓
Step 1: Get Manual Configuration Context    ← YOU ARE HERE
         ↓
Step 2: Fix Issues (Iteration may be required)
         ↓
Step 3: Generate Migration Artifacts & Run Migration
```

---

## Prerequisites

Before running this prompt:
1. ✅ Run `Step0-Generate-Discovery-Scripts.prompt.md` to generate discovery scripts
2. ✅ Execute the discovery scripts on all servers
3. ✅ Check discovery output files into the repository

---

## How to Use This Prompt

Attach the discovery files from Step0 and run this prompt:

```
@Step1-Discovery-Questionnaire.prompt.md

Please analyze the discovery results for our <DATABASE_NAME> migration and generate:
1. A summary of discovered configurations
2. A questionnaire for manual decisions with recommended defaults

## Attached Discovery Files

### Source Database Discovery (from Step0)
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step0/Discovery/source/zdm_source_discovery_<hostname>_<timestamp>.txt
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step0/Discovery/source/zdm_source_discovery_<hostname>_<timestamp>.json

### Target Database Discovery (from Step0)
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step0/Discovery/target/zdm_target_discovery_<hostname>_<timestamp>.txt
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step0/Discovery/target/zdm_target_discovery_<hostname>_<timestamp>.json

### ZDM Server Discovery (from Step0)
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step0/Discovery/server/zdm_server_discovery_<hostname>_<timestamp>.txt
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step0/Discovery/server/zdm_server_discovery_<hostname>_<timestamp>.json

**Note:** Replace `<DATABASE_NAME>`, `<hostname>`, and `<timestamp>` with actual values.
Use the most recent discovery files if multiple exist (highest timestamp).
```

---

## AI Instructions

When this prompt is run with discovery files attached, perform the following:

### Part 1: Generate Discovery Summary

Create a file `Discovery-Summary-<DATABASE_NAME>.md` in `Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step1/` that includes:

1. **Environment Overview**
   - Source database summary (name, version, size, character set)
   - Target environment summary (version, platform)
   - ZDM server summary (version, status)

2. **Migration Readiness Assessment**
   - ✅ Requirements met (e.g., ARCHIVELOG mode, Force Logging)
   - ⚠️ Actions required (e.g., enable supplemental logging)
   - ❌ Blockers (if any)
   
   > **IMPORTANT: SSH Authentication**
   > Do NOT flag "SSH directory not found for oracle user" as a blocker.
   > ZDM uses admin users (SOURCE_ADMIN_USER, TARGET_ADMIN_USER) with `sudo -u oracle`.
   > If discovery succeeded, SSH connectivity is already working.

3. **Discovered Configurations**
   - All auto-populated values from discovery scripts
   - Organized by source/target/ZDM server

4. **Recommendations**
   - Suggested migration method based on findings
   - Identified risks or concerns

### Part 2: Generate Migration Planning Questionnaire

Create a file `Migration-Questionnaire-<DATABASE_NAME>.md` in `Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step1/` containing ONLY the items requiring manual input:

**Section A: Migration Strategy Decisions**
- Online vs Offline migration (with recommendation based on discovery)
- Migration timeline and maintenance window
- Maximum acceptable downtime

**Section B: OCI/Azure Identifiers** (🔐 Manual Entry Required)
- OCI Tenancy OCID
- OCI User OCID
- OCI Compartment OCID
- OCI Region
- Target DB System OCID
- Target Database OCID

**Section C: Object Storage Configuration**
- Bucket namespace and name
- Bucket region

**Section D: Migration Options**
- Data Guard protection mode (with recommendation)
- Auto switchover preference
- Pause points for validation

**Section E: Network Configuration** (if not fully discovered)
- ExpressRoute/VPN details
- Bandwidth estimates

Each question should include:
- The question/field
- A **recommended default** based on discovery analysis
- Brief justification for the recommendation

---

## Output Files

Step 1 creates the following outputs:

```
Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/
├── Step0/
│   └── Discovery/
│       ├── source/
│       ├── target/
│       └── server/
└── Step1/                                      # NEW: Created by this step
    ├── Discovery-Summary-<DATABASE_NAME>.md         # NEW: Generated summary
    └── Migration-Questionnaire-<DATABASE_NAME>.md   # NEW: Manual items only
```

---

## Discovery Summary Template

The Discovery Summary should follow this structure:

```markdown
# Discovery Summary: <DATABASE_NAME> Migration

## Generated
- Date: <timestamp>
- Source Files: <list of discovery files analyzed>

## Executive Summary

| Component | Status | Key Findings |
|-----------|--------|--------------|
| Source Database | ✅/⚠️/❌ | Brief status |
| Target Environment | ✅/⚠️/❌ | Brief status |
| ZDM Server | ✅/⚠️/❌ | Brief status |
| Network | ✅/⚠️/❌ | Brief status |

## Migration Method Recommendation

**Recommended:** [ONLINE_PHYSICAL / OFFLINE_PHYSICAL]

**Justification:**
- [Reason 1 based on discovery]
- [Reason 2 based on discovery]

## Source Database Details

### Database Identification
| Property | Value |
|----------|-------|
| Database Name | <from discovery> |
| ... | ... |

### Configuration Status
| Requirement | Current State | Required State | Status |
|-------------|---------------|----------------|--------|
| ARCHIVELOG Mode | YES/NO | YES | ✅/❌ |
| Force Logging | YES/NO | YES | ✅/❌ |
| Supplemental Logging | YES/NO | YES (for online) | ✅/⚠️ |
| TDE Enabled | YES/NO | N/A | ✅ |

## Target Environment Details
[Similar structure]

## ZDM Server Details
[Similar structure]

## Required Actions Before Migration

### Critical (Must Fix)
1. [Action item with command if applicable]

### Recommended
1. [Action item]

## Discovered Values Reference

[Complete list of all discovered values for reference in Step 2]
```

---

## Migration Questionnaire Template

The Questionnaire should follow this structure:

```markdown
# Migration Planning Questionnaire: <DATABASE_NAME>

## Instructions
Please complete the following questions. Recommended defaults are provided based on discovery analysis.
After completing, save this file and proceed to Step 2.

---

## Section A: Migration Strategy

### A.1 Migration Method
**Recommended:** ONLINE_PHYSICAL ✓

[ ] ONLINE_PHYSICAL - Minimal downtime using Data Guard
[ ] OFFLINE_PHYSICAL - Extended downtime, simpler setup

**Your Selection:** _______________

**Why we recommend ONLINE_PHYSICAL:**
- Source database is in ARCHIVELOG mode
- Force Logging is enabled
- [Other reasons from discovery]

### A.2 Migration Timeline

| Field | Your Value |
|-------|------------|
| Planned Migration Date | _______________ |
| Maintenance Window Start | _______________ |
| Maintenance Window End | _______________ |
| Maximum Acceptable Downtime | _______________ (Recommended: 15-30 minutes for online) |

---

## Section B: OCI/Azure Identifiers (Required)

These values must be obtained from the OCI Console or Azure Portal.

| Field | Value | Where to Find |
|-------|-------|---------------|
| OCI Tenancy OCID | _______________ | OCI Console > Tenancy Details |
| OCI User OCID | _______________ | OCI Console > User Settings |
| OCI Compartment OCID | _______________ | OCI Console > Compartments |
| OCI Region | _______________ | e.g., uk-london-1 |
| Target DB System OCID | _______________ | OCI Console > DB Systems |
| Target Database OCID | _______________ | OCI Console > Databases |

---

## Section C: Object Storage

**Recommended Bucket Name:** zdm-migration-<DATABASE_NAME>-<date>

| Field | Recommended | Your Value |
|-------|-------------|------------|
| Object Storage Namespace | [from discovery or manual] | _______________ |
| Bucket Name | zdm-migration-<DATABASE_NAME> | _______________ |
| Bucket Region | [same as target] | _______________ |
| Create New Bucket? | YES | [ ] YES [ ] NO |

---

## Section D: Migration Options

### D.1 Data Guard Configuration (Online Migration)
**Recommended:** MAXIMUM_PERFORMANCE with ASYNC

| Option | Recommended | Your Selection |
|--------|-------------|----------------|
| Protection Mode | MAXIMUM_PERFORMANCE | [ ] MAX_PERF [ ] MAX_AVAIL |
| Transport Type | ASYNC | [ ] ASYNC [ ] SYNC |

### D.2 Post-Migration Options

| Option | Recommended | Your Selection |
|--------|-------------|----------------|
| Auto Switchover | NO (manual control) | [ ] YES [ ] NO |
| Delete Backup After Migration | NO (keep for rollback) | [ ] YES [ ] NO |
| Include Performance Data | YES | [ ] YES [ ] NO |

### D.3 Pause Points
**Recommended:** Pause before switchover for validation

[ ] ZDM_CONFIGURE_DG_SRC - Pause after Data Guard setup
[X] ZDM_SWITCHOVER_SRC - Pause before switchover (Recommended)
[ ] None - Run to completion

---

## Section E: Confirmation

[ ] I have reviewed the Discovery Summary
[ ] I have completed all required fields above
[ ] I understand the recommended defaults and their justifications

**Completed By:** _______________
**Date:** _______________

---

## Next Steps

After completing this questionnaire:
1. Save this file
2. Review the Discovery Summary for any critical actions
3. Run `Step2-Fix-Issues.prompt.md` to address any blockers
4. After all issues resolved, run `Step3-Generate-Migration-Artifacts.prompt.md` with:
   - This completed questionnaire
   - The Discovery Summary
   - The Issue Resolution Log
```

---

## Next Steps

After Step 1 generates the outputs:

1. **Review Discovery Summary** - Check for any required actions or blockers
2. **Complete the Questionnaire** - Fill in manual items
3. **Run Step 2**: `Step2-Fix-Issues.prompt.md`
   - Address all blockers and required actions
   - Iterate until all issues are resolved
4. **Run Step 3**: `Step3-Generate-Migration-Artifacts.prompt.md`
   - Attach the completed questionnaire
   - Attach the Issue Resolution Log
   - This generates the RSP file, ZDM commands, and runbook
