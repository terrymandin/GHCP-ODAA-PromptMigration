---
agent: agent
description: ZDM Step 3 - Analyze discovery output and conduct migration planning interview to produce a completed Decisions Record
---
# ZDM Migration Step 3: Discovery Analysis & Migration Planning Interview

## Purpose
This prompt analyzes Step 2 discovery output and guides the operator through a structured interview to produce three artifacts:
1. **Discovery Summary** — Auto-populated findings from the discovery scripts
2. **Migration-Decisions.md (Decisions Record)** — Completed RSP parameter decisions captured through an interactive interview; no blank fields
3. **Step3 README** — Summary of generated files, what to review, and next steps

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
1. ✅ Complete `@Phase10-ZDM-Step1-Test-SSH-Connectivity` — confirm all SSH connectivity checks pass
2. ✅ Complete `@Phase10-ZDM-Step2-Generate-Discovery-Scripts` — confirm discovery reports were generated for source, target, and ZDM server components
3. ✅ Confirm discovery output files exist in `Artifacts/Phase10-Migration/Step2/Discovery/` subdirectories
4. ✅ Be prepared to answer migration planning questions in the chat during this session — the interview requires interactive responses before `Migration-Decisions.md` is written

---

## Execution Model

This step runs under the **Remote-SSH** execution model:
- VS Code is connected to the ZDM jumpbox via the **Remote-SSH** extension, with the terminal session running as **`zdmuser`**.
- Copilot reads discovery files attached as inputs and writes output artifacts using file tools — no terminal commands are executed in this step.
- All outputs are written to `Artifacts/Phase10-Migration/Step3/` (git-ignored). No generated files are committed or create PRs.
- OCI CLI is not required for this step or any Phase10 migration execution step.

Input precedence rules (mandatory):
- Treat discovery files as **observed runtime evidence**.
- Treat `zdm-env.md` as **configured intent** when attached.
- If they disagree, do not silently override; explicitly report the mismatch and recommend corrective action.
- Treat placeholder values containing `<...>` in `zdm-env.md` as unset.
- `zdm-env.md` is input to this prompt only. Generated outputs must not read or source it.

Evidence selection when multiple discovery files exist per component:
- Use the most recent file set by timestamp (highest timestamp = most recent).
- Keep source, target, and server evidence references explicit in generated outputs.

DB-specific value scope (Step1–Step5):
- `SOURCE_REMOTE_ORACLE_HOME`
- `SOURCE_ORACLE_SID`
- `TARGET_REMOTE_ORACLE_HOME`
- `TARGET_ORACLE_SID`
- `SOURCE_DATABASE_UNIQUE_NAME`
- `TARGET_DATABASE_UNIQUE_NAME`

ZDM-specific value scope (Step1–Step5):
- `ZDM_HOME`

---

## How to Use This Prompt

Attach the discovery files from Step2 and run this prompt. Copilot will:
1. Analyze discovery files and write the Discovery Summary.
2. Conduct a structured interactive interview — Phase A (migration method), Phase B (method-specific parameters), Phase C (OCI/storage identifiers).
3. Write `Migration-Decisions.md` as a completed Decisions Record only after all interview phases are answered.
4. Write the Step3 README.

```
@Phase10-ZDM-Step3-Discovery-Questionnaire

Please analyze the discovery results, conduct the migration planning interview, and generate all Step3 artifacts.

## Attached Discovery Files

### Project Configuration (optional)
#file:zdm-env.md

### Source Database Discovery (from Step2)
#file:Artifacts/Phase10-Migration/Step2/Discovery/source/zdm_source_discovery_<hostname>_<timestamp>.md
#file:Artifacts/Phase10-Migration/Step2/Discovery/source/zdm_source_discovery_<hostname>_<timestamp>.json

### Target Database Discovery (from Step2)
#file:Artifacts/Phase10-Migration/Step2/Discovery/target/zdm_target_discovery_<hostname>_<timestamp>.md
#file:Artifacts/Phase10-Migration/Step2/Discovery/target/zdm_target_discovery_<hostname>_<timestamp>.json

### ZDM Server Discovery (from Step2)
#file:Artifacts/Phase10-Migration/Step2/Discovery/server/zdm_server_discovery_<hostname>_<timestamp>.md
#file:Artifacts/Phase10-Migration/Step2/Discovery/server/zdm_server_discovery_<hostname>_<timestamp>.json

**Note:** Replace `<hostname>` and `<timestamp>` with actual values.
Use the most recent discovery files if multiple exist per component (highest timestamp).
```

---

## AI Instructions

When this prompt is run with discovery files attached, perform the following:

### Part 1: Generate Discovery Summary

Create `Artifacts/Phase10-Migration/Step3/Discovery-Summary.md` including:

1. **Generation Metadata**
   - Date/time of analysis
   - List of source discovery files analyzed

2. **Executive Summary** (table by component: Source Database, Target Environment, ZDM Server, Network)
   - Status (✅/⚠️/❌) and key findings per component

3. **Migration Method Recommendation**
   - Recommended method: ONLINE_PHYSICAL or OFFLINE_PHYSICAL
   - Explicit justification based on discovered evidence

4. **Source Database Details**
   - Database identification (name, version, size, character set)
   - Readiness checks: ARCHIVELOG mode, Force Logging, Supplemental Logging, TDE
   - Configuration status table (Current State / Required State / Status)

5. **Target Environment Details**
   - Platform, version, and readiness indicators relevant to migration

6. **ZDM Server Details**
   - Discovered version from `zdm_installation.zdm_version` in server discovery JSON
   - Service posture (running/stopped, active jobs)
   - ZDM version status assessment

7. **Required Actions Before Migration**
   - Critical (must fix before continuing)
   - Recommended (should fix before go-live)

8. **Discovered Values Reference**
   - Complete list of all discovered values for reuse in Step4/Step5

9. **Mismatch Section** (include only when `zdm-env.md` intent differs from discovery evidence)
   - Table: Field | Configured Intent | Discovered Value | Recommended Action

**Classification guardrails:**
- If Step2 discovery completed successfully, do not classify "oracle SSH directory not found" as a blocker by itself. ZDM uses admin users (`SOURCE_ADMIN_USER`, `TARGET_ADMIN_USER`) with `sudo -u oracle`; discovery success already confirms SSH connectivity.
- Always evaluate ZDM version evidence from `zdm_installation.zdm_version` in server discovery output.
- If ZDM version is UNDETERMINED or known to be outdated, generate a Required Action: *Verify ZDM is the latest stable release; upgrade if necessary (see My Oracle Support — "Zero Downtime Migration").*

### Part 2: Conduct Migration Planning Interview

**Do not write `Migration-Decisions.md` until all interview phases below are fully answered.**

Run the interview in three sequential phases. For each question, present the discovered or `zdm-env.md`-sourced recommended default inline and ask the operator to confirm or override. If `zdm-env.md` is attached and provides a non-placeholder value, present it as the pre-filled default; ask for confirmation, not an open question.

---

#### Phase A — Migration Method (gates all subsequent questions)

Ask:
> **[A1] Migration Method** (`MIGRATION_METHOD`)
> Based on discovery analysis, the recommended method is **[insert recommendation with one-line justification]**.
> Confirm ONLINE_PHYSICAL, choose OFFLINE_PHYSICAL, or provide a reason to change:

Do not proceed to Phase B until A1 is answered.

---

#### Phase B — Migration-type-specific questions

Ask **only** the questions for the method confirmed in Phase A.

**If ONLINE_PHYSICAL:**

| ID | Question | RSP Parameter | Recommended Default |
|----|---|---|---|
| B1 | Log switch interval (minutes) | `LOG_SWITCH_INTERVAL` | 20 |
| B2 | Data Guard protection mode | `DATAGUARD_PROTECTION_MODE` | MAX_PERFORMANCE |
| B3 | Data transfer medium | `DATA_TRANSFER_MEDIUM` | OSS |
| B4 | Insert pause point before switchover? (YES/NO) | `PAUSE_BEFORE_SWITCHOVER` | YES |
| B5 | Enable auto-switchover? (YES/NO) | `AUTO_SWITCHOVER` | NO |

Present each question individually and wait for the operator to respond before moving to the next.

**If OFFLINE_PHYSICAL:**

| ID | Question | RSP Parameter | Recommended Default |
|----|---|---|---|
| B1 | Backup/transfer medium | `DATA_TRANSFER_MEDIUM` | OSS |
| B2 | Maximum acceptable downtime window (hours) | *(runbook planning)* | 4 |

Do not proceed to Phase C until all Phase B questions are answered.

---

#### Phase C — Common questions (both migration methods)

Present each question in order. Mark OCI identifiers as **🔐 Manual Entry Required** when `zdm-env.md` does not supply a non-placeholder value.

| ID | Question | RSP / CLI Mapping | Source Priority |
|----|---|---|---|
| C1 | OCI Tenancy OCID | `OCID_TENANCY` / `zdmcli -ocitenancy` | zdm-env.md → manual |
| C2 | OCI User OCID | `OCID_USER` | zdm-env.md → manual |
| C3 | OCI Compartment OCID | `OCID_COMPARTMENT` | zdm-env.md → manual |
| C4 | Target Database OCID | `OCID_TARGET_DATABASE` | zdm-env.md → manual |
| C5 | OCI Object Storage namespace | `OSS_BUCKET_NAMESPACE` | zdm-env.md → manual |
| C6 | OCI Object Storage bucket name | `OSS_BUCKET_NAME` | zdm-env.md → manual |
| C7 | OCI Object Storage bucket region | `OSS_BUCKET_REGION` | zdm-env.md → discovered |
| C8 | Wallet/TLS migration required? (YES/NO — ask only if TDE is enabled) | `WALLET_MIGRATION` | discovered |

---

### Part 2b: Write Migration Decisions Record

After all interview phases (A, B, C) are fully answered, create `Artifacts/Phase10-Migration/Step3/Migration-Decisions.md` as a completed **Decisions Record**. This file is the primary input for Step5 RSP generation.

Required sections:

1. **Generation Metadata**
   - Date/time of interview
   - Confirmed migration method

2. **Decisions Table** — one row per answered question, no blank or placeholder values:

```markdown
| Parameter | RSP / CLI Mapping | Value | Source |
|---|---|---|---|
| MIGRATION_METHOD | `MIGRATION_METHOD` | ONLINE_PHYSICAL | confirmed by operator |
| LOG_SWITCH_INTERVAL | `LOG_SWITCH_INTERVAL` | 20 | confirmed by operator |
...
```

Source column values: `discovered`, `from zdm-env.md`, or `manual`.

3. **Runbook Planning Notes** — free-form section for any non-RSP answers (e.g., downtime window, maintenance schedule).

**Integrity rule:** If any required question was not answered, record the parameter as `BLOCKED — <reason>` and surface it as a Critical blocker in the Step3 README. Do not write placeholder values.



### Part 3: Generate Step3 README

Create `Artifacts/Phase10-Migration/Step3/README.md` summarizing:
- Generated files for this step and their purpose
- What the operator should review before proceeding to Step4
- Where runtime outputs and reports are written (all in `Artifacts/Phase10-Migration/Step3/`)
- Success signals: all three files created, interview fully completed, no unresolved critical blockers, Decisions Record contains no blank/placeholder/BLOCKED values
- Failure signals: missing discovery inputs, unresolvable blockers, interview questions left unanswered (BLOCKED rows in Decisions Record)

### Validation Evidence

After writing all output files, confirm creation and provide a concise summary:
- List each output file path written
- Confirm each was created successfully
- Note any sections that could not be populated due to missing discovery evidence

---

## Output Files

Step 3 creates the following outputs (all git-ignored):

```
Artifacts/Phase10-Migration/
└── Step3/
    ├── README.md                    # Step summary, review checklist, next steps
    ├── Discovery-Summary.md         # Auto-populated analysis of discovery evidence
    └── Migration-Decisions.md       # Completed Decisions Record (no blank values)
```

---

## Discovery Summary Template

The Discovery Summary must follow this structure:

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
> If the installed version is not the latest stable release, or is undetermined, flag as a ⚠️ Required Action.
> ZDM patch bundles and release updates are available on My Oracle Support — search "Zero Downtime Migration".

## Required Actions Before Migration

### Critical (Must Fix)
1. [Action item with command if applicable]

### Recommended
1. [Action item]

## Discovered Values Reference

[Complete list of all discovered values for reuse in Step 4 and Step 5]

## Mismatch Report (include only when zdm-env.md is attached and conflicts exist)

| Field | Configured Intent (zdm-env.md) | Discovered Value | Recommended Action |
|-------|-------------------------------|------------------|--------------------|
| [field] | [value] | [value] | [action] |
```

---

## Decisions Record Template

`Migration-Decisions.md` is written only after all interview phases are complete. It must follow this structure — no blank or placeholder values are permitted:

```markdown
# Migration Decisions Record

## Generated
- Date: <timestamp>
- Confirmed Migration Method: ONLINE_PHYSICAL / OFFLINE_PHYSICAL

## Decisions Table

| Parameter | RSP / CLI Mapping | Value | Source |
|---|---|---|---|
| MIGRATION_METHOD | `MIGRATION_METHOD` | ONLINE_PHYSICAL | confirmed by operator |
| LOG_SWITCH_INTERVAL | `LOG_SWITCH_INTERVAL` | 20 | confirmed by operator |
| DATAGUARD_PROTECTION_MODE | `DATAGUARD_PROTECTION_MODE` | MAX_PERFORMANCE | confirmed by operator |
| DATA_TRANSFER_MEDIUM | `DATA_TRANSFER_MEDIUM` | OSS | confirmed by operator |
| PAUSE_BEFORE_SWITCHOVER | `PAUSE_BEFORE_SWITCHOVER` | YES | confirmed by operator |
| AUTO_SWITCHOVER | `AUTO_SWITCHOVER` | NO | confirmed by operator |
| OCID_TENANCY | `OCID_TENANCY` / `zdmcli -ocitenancy` | ocid1.tenancy.oc1.. | from zdm-env.md |
| OCID_USER | `OCID_USER` | ocid1.user.oc1.. | manual |
| OCID_COMPARTMENT | `OCID_COMPARTMENT` | ocid1.compartment.oc1.. | manual |
| OCID_TARGET_DATABASE | `OCID_TARGET_DATABASE` | ocid1.database.oc1.. | manual |
| OSS_BUCKET_NAMESPACE | `OSS_BUCKET_NAMESPACE` | <namespace> | from zdm-env.md |
| OSS_BUCKET_NAME | `OSS_BUCKET_NAME` | zdm-migration | from zdm-env.md |
| OSS_BUCKET_REGION | `OSS_BUCKET_REGION` | uk-london-1 | discovered |
| WALLET_MIGRATION | `WALLET_MIGRATION` | YES | discovered |

Source values: `discovered` · `from zdm-env.md` · `confirmed by operator` · `manual`

## Runbook Planning Notes

- Maximum acceptable downtime window: <operator answer>
- [Other non-RSP planning notes]

## Blocked Parameters (Critical — must resolve before Step 5)

| Parameter | Reason |
|---|---|
| [none / list any BLOCKED items] | [reason operator could not answer] |
```

---

## Next Steps

After Step 3 completes:

1. **Review Discovery Summary** — Check for any Required Actions or Critical blockers
2. **Confirm Decisions Record** — Verify `Migration-Decisions.md` has no BLOCKED rows
3. **Run Step 4**: `@Phase10-ZDM-Step4-Fix-Issues`
   - Address all critical blockers and required actions
   - Iterate until all issues are resolved
4. **Run Step 5**: `@Phase10-ZDM-Step5-Generate-Migration-Artifacts`
   - Attach the completed Decisions Record (`Migration-Decisions.md`)
   - Attach the Discovery Summary
   - Attach the Issue Resolution Log from Step 4
   - Step 5 generates the RSP file, ZDM commands, and full runbook
