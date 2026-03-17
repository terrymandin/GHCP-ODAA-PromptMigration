---
agent: agent
description: ZDM Step 3 - Analyze discovery output and create migration plan
---
# ZDM Migration Step 3: Get Manual Configuration Context

## Purpose
This prompt analyzes the discovery output from Step 2 and generates:
1. **Discovery Summary** - Auto-populated findings from the discovery scripts
2. **Migration Planning Questionnaire** - Questions requiring manual input with recommended defaults

---

## Migration Flow Overview

```
Step 2: Run Scripts to Get Context
         ↓
Step 3: Get Manual Configuration Context    ← YOU ARE HERE
         ↓
Step 4: Fix Issues (Iteration may be required)
         ↓
Step 5: Generate Migration Artifacts & Run Migration
```

---

## Prerequisites

Before running this prompt:
1. ✅ Complete `@Phase10-ZDM-Step1-Test-SSH-Connectivity` and confirm connectivity checks pass
2. ✅ Run `@Phase10-ZDM-Step2-Generate-Discovery-Scripts` to generate discovery scripts
3. ✅ Commit/push Step2 scripts, then execute them from the repository clone on the jumpbox/ZDM server
4. ✅ Check discovery output files into the repository

---

## How to Use This Prompt

Attach the discovery files from Step2 and run this prompt:

Configuration precedence for artifact generation (mandatory):
- If `zdm-env.md` is attached, treat it as authoritative for configured intent values used in Step3 artifacts.
- Use discovery output as observed runtime evidence, and use `zdm-env.md` as the configured baseline when generating consistency checks and recommendations.
- If discovery and `zdm-env.md` disagree, do not silently replace values; explicitly call out the mismatch and recommend corrective action.

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
@Phase10-ZDM-Step3-Discovery-Questionnaire

Please analyze the discovery results and generate:
1. A summary of discovered configurations
2. A questionnaire for manual decisions with recommended defaults

## Attached Discovery Files

### Source Database Discovery (from Step2)
#file:Artifacts/Phase10-Migration/Step2/Discovery/source/zdm_source_discovery_<hostname>_<timestamp>.txt
#file:Artifacts/Phase10-Migration/Step2/Discovery/source/zdm_source_discovery_<hostname>_<timestamp>.json

### Target Database Discovery (from Step2)
#file:Artifacts/Phase10-Migration/Step2/Discovery/target/zdm_target_discovery_<hostname>_<timestamp>.txt
#file:Artifacts/Phase10-Migration/Step2/Discovery/target/zdm_target_discovery_<hostname>_<timestamp>.json

### ZDM Server Discovery (from Step2)
#file:Artifacts/Phase10-Migration/Step2/Discovery/server/zdm_server_discovery_<hostname>_<timestamp>.txt
#file:Artifacts/Phase10-Migration/Step2/Discovery/server/zdm_server_discovery_<hostname>_<timestamp>.json

**Note:** Replace `<hostname>` and `<timestamp>` with actual values.
Use the most recent discovery files if multiple exist (highest timestamp).
```

---

## AI Instructions

When this prompt is run with discovery files attached, perform the following:

### Part 1: Generate Discovery Summary

Create a file `Discovery-Summary.md` in `Artifacts/Phase10-Migration/Step3/` that includes:

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

   > **IMPORTANT: ZDM Version Check**
   > Always check `zdm_installation.zdm_version` from the server discovery JSON.
   > If the version is UNDETERMINED or known to be outdated, add a **Required Action** item:
   > `Verify ZDM is the latest stable release; upgrade if necessary (see My Oracle Support — 'Zero Downtime Migration').

3. **Discovered Configurations**
   - All auto-populated values from discovery scripts
   - Organized by source/target/ZDM server

4. **Recommendations**
   - Suggested migration method based on findings
   - Identified risks or concerns

### Part 2: Generate Migration Planning Questionnaire

Create a file `Migration-Questionnaire.md` in `Artifacts/Phase10-Migration/Step3/` containing ONLY the items requiring manual input:

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

Step 3 creates the following outputs:

```
Artifacts/Phase10-Migration/
├── Step2/
│   └── Discovery/
│       ├── source/
│       ├── target/
│       └── server/
└── Step3/                                      # NEW: Created by this step
    ├── Discovery-Summary.md                         # NEW: Generated summary
    └── Migration-Questionnaire.md                   # NEW: Manual items only
```

---

## Discovery Summary Template

The Discovery Summary should follow this structure:

```markdown
# Discovery Summary

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

| Property | Value |
|----------|-------|
| ZDM Version | <from discovery — zdm_installation.zdm_version> |
| ZDM Home | <from discovery> |
| ZDM Service Status | Running / Stopped |
| Active Jobs | <count> |

### ZDM Version Status

| Check | Current State | Required State | Status |
|-------|---------------|----------------|--------|
| ZDM Version Installed | <discovered version> | Latest stable | ✅/⚠️/❌ |
| ZDM Service Running | YES/NO | YES | ✅/❌ |
| ZDM Binary Functional | YES/NO | YES | ✅/❌ |

> **ZDM Version Guidance:**
> Oracle ZDM is updated regularly. Check [Oracle ZDM Release Notes](https://docs.oracle.com/en/database/oracle/zero-downtime-migration/index.html) to confirm the installed version is the latest stable release.
> - If the discovered version is **not the latest stable release**, flag this as a ⚠️ **Required Action** in the Required Actions section.
> - If the version is **undetermined**, flag this as a ⚠️ **Required Action** requiring manual inspection and upgrade verification before proceeding.
> - ZDM patch bundles and release updates are available on [My Oracle Support](https://support.oracle.com) — search for "Zero Downtime Migration" to find the latest available version.

## Required Actions Before Migration

### Critical (Must Fix)
1. [Action item with command if applicable]

### Recommended
1. [Action item]

## Discovered Values Reference

[Complete list of all discovered values for reference in Step 4]
```

---

## Migration Questionnaire Template

The Questionnaire should follow this structure:

```markdown
# Migration Planning Questionnaire

## Instructions
Please complete the following questions. Recommended defaults are provided based on discovery analysis.
After completing, save this file and proceed to Step 4.

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

**Recommended Bucket Name:** zdm-migration-<date>

| Field | Recommended | Your Value |
|-------|-------------|------------|
| Object Storage Namespace | [from discovery or manual] | _______________ |
| Bucket Name | zdm-migration | _______________ |
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
3. Run `@Phase10-ZDM-Step4-Fix-Issues` to address any blockers
4. After all issues resolved, run `@Phase10-ZDM-Step5-Generate-Migration-Artifacts` with:
   - This completed questionnaire
   - The Discovery Summary
   - The Issue Resolution Log
```

---

## Next Steps

After Step 3 generates the outputs:

1. **Review Discovery Summary** - Check for any required actions or blockers
2. **Complete the Questionnaire** - Fill in manual items
3. **Run Step 4**: `@Phase10-ZDM-Step4-Fix-Issues`
   - Address all blockers and required actions
   - Iterate until all issues are resolved
4. **Run Step 5**: `@Phase10-ZDM-Step5-Generate-Migration-Artifacts`
   - Attach the completed questionnaire
   - Attach the Issue Resolution Log
   - This generates the RSP file, ZDM commands, and runbook
