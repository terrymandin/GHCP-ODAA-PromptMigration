---
mode: agent
description: ZDM Step 4 - Analyze Step 3 discovery output and conduct migration planning interview to produce a completed Decisions Record
---
# ZDM Migration Step 4: Discovery Analysis & Migration Planning Interview

## Purpose

This step analyzes Step 3 discovery output and guides the operator through a structured interview to produce three artifacts:
1. **Discovery Summary** — Auto-populated analysis of Step 3 discovery evidence
2. **Migration-Decisions.md** — Completed Decisions Record capturing all RSP parameter decisions; no blank or placeholder values
3. **Step 4 README** — Summary of generated files, review checklist, and next steps

This step **reads** discovery evidence from Step 3 and config artifacts from Steps 2–3. It does not run terminal commands.

---

## Execution Model

This step runs under the **Remote-SSH execution model** (CR-03): VS Code is connected to the ZDM jumpbox as `zdmuser`. Copilot reads discovery files and writes output artifacts using file tools — **no terminal commands are executed in this step**.

- All outputs are written to `Artifacts/Phase10-Migration/Step4/` (git-ignored). No generated files are committed or create PRs.
- OCI CLI is not required for this step or any Phase10 migration execution step (CR-06).
- Input config artifacts are read-only. Generated outputs must not read, source, or parse config artifacts at runtime (CR-02).

Input precedence rules (CR-01):
1. Step 3 discovery files are the primary evidence source (observed runtime state).
2. `Artifacts/Phase10-Migration/Step3/db-config.md` is the primary DB/ZDM variable source.
3. `Artifacts/Phase10-Migration/Step2/ssh-config.md` is the primary SSH variable source.
4. `zdm-env.md` (when explicitly attached) is a legacy override with higher precedence than step artifacts.
5. If configured intent (`zdm-env.md` or step artifacts) conflicts with discovery evidence, do not silently override — explicitly report the mismatch and recommend corrective action (S4-03).
6. Placeholder values containing `<...>` are treated as unset.

Evidence selection when multiple discovery files exist per component (S4-08):
- Use the most recent file set by timestamp (highest timestamp = most recent).
- Keep source, target, and server evidence references explicit in generated outputs.

---

## Prerequisites

Before running this prompt:
1. ✅ Complete `@Phase10-Step1-Setup-Remote-SSH` — VS Code is connected via Remote-SSH as `zdmuser`
2. ✅ Complete `@Phase10-Step2-Configure-SSH-Connectivity` — SSH connectivity verified; `Artifacts/Phase10-Migration/Step2/ssh-config.md` exists
3. ✅ Complete `@Phase10-Step3-Generate-Discovery-Scripts` — discovery runs complete; discovery reports exist in `Artifacts/Phase10-Migration/Step3/Discovery/`
4. ✅ Be prepared to answer migration planning questions interactively — the interview requires responses before `Migration-Decisions.md` is written

---

## How to Use This Prompt

Attach the Step 3 discovery files and run this prompt:

```
@Phase10-Step4-Discovery-Questionnaire

Please analyze the discovery results, conduct the migration planning interview, and generate all Step 4 artifacts.

## Attached Configuration (read-only)
#file:Artifacts/Phase10-Migration/Step2/ssh-config.md
#file:Artifacts/Phase10-Migration/Step3/db-config.md

## Optional: Legacy override
#file:zdm-env.md

## Source Database Discovery (from Step 3)
#file:Artifacts/Phase10-Migration/Step3/Discovery/source/zdm_source_discovery_<hostname>_<timestamp>.md
#file:Artifacts/Phase10-Migration/Step3/Discovery/source/zdm_source_discovery_<hostname>_<timestamp>.json

## Target Database Discovery (from Step 3)
#file:Artifacts/Phase10-Migration/Step3/Discovery/target/zdm_target_discovery_<hostname>_<timestamp>.md
#file:Artifacts/Phase10-Migration/Step3/Discovery/target/zdm_target_discovery_<hostname>_<timestamp>.json

## ZDM Server Discovery (from Step 3)
#file:Artifacts/Phase10-Migration/Step3/Discovery/server/zdm_server_discovery_<hostname>_<timestamp>.md
#file:Artifacts/Phase10-Migration/Step3/Discovery/server/zdm_server_discovery_<hostname>_<timestamp>.json

**Note:** Replace `<hostname>` and `<timestamp>` with actual filename values.
Use the most recent discovery files if multiple exist per component (highest timestamp = most recent).
```

---

## Part 1: Generate Discovery Summary

Write `Artifacts/Phase10-Migration/Step4/Discovery-Summary.md` with the following sections (S4-06):

### 1. Generation Metadata
- Date/time of analysis
- List of discovery files analyzed (filenames with timestamps)

### 2. Executive Summary

Table by component — Source Database, Target Environment, ZDM Server, Network:

| Component | Status | Key Findings |
|-----------|--------|--------------|
| Source Database | ✅/⚠️/❌ | Brief status |
| Target Environment | ✅/⚠️/❌ | Brief status |
| ZDM Server | ✅/⚠️/❌ | Brief status |
| Network | ✅/⚠️/❌ | Brief status |

### 3. Migration Method Recommendation
- Recommended method: `ONLINE_PHYSICAL` or `OFFLINE_PHYSICAL`
- Explicit justification based on discovered evidence (archivelog mode, force logging, TDE, supplemental logging, downtime window requirements)

### 4. Source Database Details
- Database identification: name, unique name, version, size, character set
- ARCHIVELOG mode, Force Logging, Supplemental Logging, TDE — current state vs. required state with status

Configuration status table:

| Requirement | Current State | Required State | Status |
|-------------|---------------|----------------|--------|
| ARCHIVELOG Mode | YES/NO | YES | ✅/❌ |
| Force Logging | YES/NO | YES | ✅/❌ |
| Supplemental Logging | YES/NO | YES (online) | ✅/⚠️ |
| TDE Enabled | YES/NO | N/A | ✅ |

### 5. Target Environment Details
- Platform, Oracle version, and readiness indicators relevant to migration

### 6. ZDM Server Details

- ZDM version discovered from `zdm_installation.zdm_version` in server discovery JSON
- ZDM service posture (running/stopped, active jobs)
- ZDM version assessment status

| Property | Value |
|----------|-------|
| ZDM Version | <from discovery — zdm_installation.zdm_version> |
| ZDM Home | <from discovery> |
| ZDM Service Status | Running / Stopped |
| Active Jobs | <count> |

**Classification guardrails (S4-09):**
- If Step 3 discovery completed successfully, do not classify "oracle SSH directory not found" as a blocker by itself. ZDM uses admin users with `sudo -u oracle`; discovery success already confirms SSH connectivity.
- Always evaluate ZDM version evidence from `zdm_installation.zdm_version` in server discovery output.
- If ZDM version is UNDETERMINED or outdated, generate a Required Action: *Verify ZDM is the latest stable release; upgrade if necessary (see My Oracle Support — "Zero Downtime Migration").*

### 7. Required Actions Before Migration

Split by severity:
- **Critical (must fix before continuing)** — blockers that prevent migration
- **Recommended (should fix before go-live)** — advisory items

### 8. Discovered Values Reference

Complete list of all discovered values for reuse in Steps 5–6 (including ORACLE_HOME, SID, unique names, DB versions, ZDM home, region evidence).

### 9. Mismatch Report *(include only when configured intent differs from discovery evidence)*

| Field | Configured Intent | Discovered Value | Recommended Action |
|-------|-------------------|------------------|--------------------|
| [field] | [value from ssh-config.md / db-config.md / zdm-env.md] | [observed value] | [action] |

---

## Part 2: Migration Planning Interview

**Do not write `Migration-Decisions.md` until all interview phases below are fully answered (S4-10, S4-05).**

Run the interview in three sequential phases. For each question:
- Present the discovered or config-artifact-sourced recommended default inline.
- If `zdm-env.md` is attached and provides a non-placeholder value, present it as the pre-filled default and ask for confirmation — not an open question (S4-10).
- Wait for the operator to respond before moving to the next question (S4-05).
- Do not ask questions whose answers cannot influence an RSP parameter, a `zdmcli` argument, or runbook content (S4-05).

---

### Phase A — Migration Method (gates all subsequent questions)

Ask:
> **[A1] Migration Method** (`MIGRATION_METHOD`)
> Based on discovery analysis, the recommended method is **[insert recommendation with one-line justification]**.
> Confirm `ONLINE_PHYSICAL`, choose `OFFLINE_PHYSICAL`, or provide a reason to change:

Do not proceed to Phase B until A1 is answered.

---

### Phase B — Migration-type-specific questions

Ask **only** the questions for the method confirmed in Phase A.

**If ONLINE_PHYSICAL:**

| ID | Question | RSP Parameter | Recommended Default |
|----|----------|---------------|---------------------|
| B1 | Log switch interval (minutes) | `LOG_SWITCH_INTERVAL` | 20 |
| B2 | Data Guard protection mode | `DATAGUARD_PROTECTION_MODE` | MAX_PERFORMANCE |
| B3 | Data transfer medium | `DATA_TRANSFER_MEDIUM` | OSS |
| B4 | Insert pause point before switchover? (YES/NO) | `PAUSE_BEFORE_SWITCHOVER` | YES |
| B5 | Enable auto-switchover? (YES/NO) | `AUTO_SWITCHOVER` | NO |

**If OFFLINE_PHYSICAL:**

| ID | Question | RSP Parameter | Recommended Default |
|----|----------|---------------|---------------------|
| B1 | Backup/transfer medium | `DATA_TRANSFER_MEDIUM` | OSS |
| B2 | Maximum acceptable downtime window (hours) | *(runbook planning)* | 4 |

Present each question individually and wait for the operator to respond before moving to the next.

Do not proceed to Phase C until all Phase B questions are answered (S4-10).

---

### Phase C — Common questions (both migration methods)

Present each question in order. Mark OCI identifiers as **🔐 Manual Entry Required** when no non-placeholder value is available from `zdm-env.md` or step config artifacts.

| ID | Question | RSP / CLI Mapping | Source Priority |
|----|----------|-------------------|-----------------|
| C1 | OCI Tenancy OCID | `OCID_TENANCY` / `zdmcli -ocitenancy` | db-config.md → zdm-env.md → manual |
| C2 | OCI User OCID | `OCID_USER` | db-config.md → zdm-env.md → manual |
| C3 | OCI Compartment OCID | `OCID_COMPARTMENT` | db-config.md → zdm-env.md → manual |
| C4 | Target Database OCID | `OCID_TARGET_DATABASE` | db-config.md → zdm-env.md → manual |
| C5 | OCI Object Storage namespace | `OSS_BUCKET_NAMESPACE` | db-config.md → zdm-env.md → manual |
| C6 | OCI Object Storage bucket name | `OSS_BUCKET_NAME` | db-config.md → zdm-env.md → manual |
| C7 | OCI Object Storage bucket region | `OSS_BUCKET_REGION` | discovered → db-config.md |
| C8 | Wallet/TLS migration required? (YES/NO — ask only if TDE is enabled) | `WALLET_MIGRATION` | discovered |

---

## Part 2b: Write Migration Decisions Record

After all interview phases (A, B, C) are fully answered, write `Artifacts/Phase10-Migration/Step4/Migration-Decisions.md` as a completed **Decisions Record** (S4-11, S4-12).

This file is the primary RSP parameter input for Step 5. It must contain **no blank, placeholder, or unanswered values**.

Required sections:

### 1. Generation Metadata
- Date/time of interview completion
- Confirmed migration method

### 2. Decisions Table

One row per answered question. No blank or placeholder values permitted (S4-12):

| Parameter | RSP / CLI Mapping | Value | Source |
|-----------|-------------------|-------|--------|
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

Source column values: `discovered` · `from zdm-env.md` · `confirmed by operator` · `manual`

### 3. Runbook Planning Notes

Free-form section for non-RSP answers (e.g., downtime window, maintenance schedule, escalation contacts).

**Blocked Parameters** (write only if any question was unanswerable):

| Parameter | Reason |
|-----------|--------|
| [parameter] | [reason operator could not answer] |

If any required question was not answered, record the parameter as `BLOCKED — <reason>` and surface it as a Critical blocker in the Step 4 README (S4-12).

---

## Part 3: Generate Step 4 README

Write `Artifacts/Phase10-Migration/Step4/README.md` (CR-08) summarizing:
- **Generated files** for this step and their purpose
- **Review checklist** — what the operator must verify before proceeding to Step 5
- **Output location** — all files in `Artifacts/Phase10-Migration/Step4/`
- **Success signals**: all three files created; interview fully completed; Decisions Record contains no blank/placeholder/BLOCKED values; no unresolved critical blockers
- **Failure signals**: missing Step 3 discovery inputs; unresolvable blockers; BLOCKED rows in Decisions Record

---

## Validation Evidence

After writing all output files, confirm creation and provide a concise summary (CR-12):
- List each output file path written
- Confirm each file was created successfully (non-empty)
- Note any sections that could not be populated due to missing discovery evidence

---

## Output Files

```
Artifacts/Phase10-Migration/
└── Step4/
    ├── README.md                    # Step summary, review checklist, next steps
    ├── Discovery-Summary.md         # Auto-populated analysis of Step 3 discovery evidence
    └── Migration-Decisions.md       # Completed Decisions Record (no blank/placeholder values)
```

All files are git-ignored. No outputs are committed or create PRs.

---

## Next Step

After Step 4 completes with no unresolved Critical blockers, and `Migration-Decisions.md` contains no BLOCKED rows:

> Run **`@Phase10-Step5-Fix-Issues`** in this Remote-SSH VS Code session connected to the ZDM jumpbox as **`zdmuser`**.

