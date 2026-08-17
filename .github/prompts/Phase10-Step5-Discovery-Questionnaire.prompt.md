---
mode: agent
description: ZDM Step 5 - Analyze Step 4 discovery output and conduct migration planning interview to produce a completed Decisions Record
---
# ZDM Migration Step 5: Discovery Analysis & Migration Planning Interview

## Purpose

This step analyzes Step 4 discovery output and guides the operator through a structured interview to produce three artifacts:
1. **Discovery Summary** — Auto-populated analysis of Step 4 discovery evidence
2. **Migration-Decisions.md** — Completed Decisions Record capturing all RSP parameter decisions; no blank or placeholder values
3. **Step 5 README** — Summary of generated files, review checklist, and next steps

This step **reads** discovery evidence from Step 4 and config artifacts from Steps 2–3. It does not run terminal commands.

---

## Execution Model

This step runs under the **Remote-SSH execution model** (CR-03): VS Code is connected to the ZDM jumpbox as `zdmuser`. Copilot reads discovery files and writes output artifacts using file tools — **no terminal commands are executed in this step**.

- All outputs are written to `Artifacts/Phase10-Migration/Step5/` (git-ignored). No generated files are committed or create PRs.
- OCI CLI is not required for this step or any Phase10 migration execution step (CR-06).
- Input config artifacts are read-only. Generated outputs must not read, source, or parse config artifacts at runtime (CR-02).
- **Environment scope (CR-13):** This prompt step is intended for **development and non-production environments only**. Do not run Copilot agent steps directly against production systems.

Input precedence rules (CR-01):
1. Step 4 discovery files are the primary evidence source (observed runtime state).
2. `Artifacts/Phase10-Migration/Step4/db-config.md` is the primary DB/ZDM variable source.
3. `Artifacts/Phase10-Migration/Step3/ssh-config.md` is the primary SSH variable source.
4. `zdm-env.md` (when explicitly attached) is a legacy override with higher precedence than step artifacts.
5. If configured intent (`zdm-env.md` or step artifacts) conflicts with discovery evidence, do not silently override — explicitly report the mismatch and recommend corrective action (S5-03).
6. Placeholder values containing `<...>` are treated as unset.

Evidence selection when multiple discovery files exist per component (S5-08):
- Use the most recent file set by timestamp (highest timestamp = most recent).
- Keep source, target, and server evidence references explicit in generated outputs.

Deterministic validation model (CR-17):
- Load `.github/requirements/Phase10/Rules/<version>/zdm-<version>-rules.yaml` (fallback `26.1`).
- Load `.github/requirements/Phase10/Rules/zdm-errors.yaml`.
- Use rule ids and `ERR-*` mappings in blocker output; do not rely on freeform-only classifications.

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
2. ✅ Complete `@Phase10-Step3-Configure-SSH-Connectivity` — SSH connectivity verified; `Artifacts/Phase10-Migration/Step3/ssh-config.md` exists
3. ✅ Complete `@Phase10-Step4-Generate-Discovery-Scripts` — discovery runs complete; discovery reports exist in `Artifacts/Phase10-Migration/Step4/Discovery/`
4. ✅ Be prepared to answer migration planning questions interactively — the interview requires responses before `Migration-Decisions.md` is written

---

## How to Use This Prompt

Attach the Step 4 discovery files and run this prompt:

```
@Phase10-Step5-Discovery-Questionnaire

Please analyze the discovery results, conduct the migration planning interview, and generate all Step 5 artifacts.

## Attached Configuration (read-only)
#file:Artifacts/Phase10-Migration/Step3/ssh-config.md
#file:Artifacts/Phase10-Migration/Step4/db-config.md

## Optional: Legacy override
#file:zdm-env.md

## Source Database Discovery (from Step 4)
#file:Artifacts/Phase10-Migration/Step4/Discovery/source/zdm_source_discovery_<hostname>_<timestamp>.md
#file:Artifacts/Phase10-Migration/Step4/Discovery/source/zdm_source_discovery_<hostname>_<timestamp>.json

## Target Database Discovery (from Step 4)
#file:Artifacts/Phase10-Migration/Step4/Discovery/target/zdm_target_discovery_<hostname>_<timestamp>.md
#file:Artifacts/Phase10-Migration/Step4/Discovery/target/zdm_target_discovery_<hostname>_<timestamp>.json

## ZDM Server Discovery (from Step 4)
#file:Artifacts/Phase10-Migration/Step4/Discovery/server/zdm_server_discovery_<hostname>_<timestamp>.md
#file:Artifacts/Phase10-Migration/Step4/Discovery/server/zdm_server_discovery_<hostname>_<timestamp>.json

**Note:** Replace `<hostname>` and `<timestamp>` with actual filename values.
Use the most recent discovery files if multiple exist per component (highest timestamp = most recent).
```

---

## Preliminary Question: Confirm Migration Method

Before running the compatibility gate or writing any artifacts, ask the operator to confirm the migration method. Two of the gate checks (`ARCHIVELOG` mode and `SPFILE` in use) are BLOCKER for `ONLINE_PHYSICAL` but only WARNING for `OFFLINE_PHYSICAL` — the gate cannot classify them correctly without this answer.

> **Migration Method** (`MIGRATION_METHOD`)
> Based on Step 4 discovery evidence, the recommended method is **[insert recommendation with one-line justification from: archivelog mode, force logging, TDE status, supplemental logging, downtime window]**.
> Confirm `ONLINE_PHYSICAL`, choose `OFFLINE_PHYSICAL`, or provide a reason to change:

Wait for the operator's answer before proceeding. Record the confirmed method — it is used immediately in the compatibility gate (Part 1) and carried forward into the full planning interview (Part 2, Phase A already answered).

---

## Part 1: Generate Discovery Summary

Write `Artifacts/Phase10-Migration/Step5/Discovery-Summary.md` with the following sections (S5-06):

### 1. Generation Metadata
- Date/time of analysis
- List of discovery files analyzed (filenames with timestamps)

### 2. ZDM Compatibility Gate (S5-05)

Evaluate the following compatibility checks using Step 4 discovery evidence **before the interview and before any questionnaire output is written**. Present results using this exact gate result block format in the Discovery Summary:

```
ZDM Compatibility Gate
======================
[PASS/FAIL/WARN]  <check name>:  source=<value>  target=<value>  [note if applicable]
```

| Check | Rule | Severity if failed |
|-------|------|-----------------|
| DB release (source vs target) | Oracle Database release (major.minor, e.g. 12.2, 19c) must be identical for physical migration. Patch level (RU/PSU) may differ — target ≥ source; ZDM runs `datapatch` automatically when target patch is higher. | BLOCKER if release differs; WARNING if patch level differs |
| Character set | Source `NLS_CHARACTERSET` must equal target | BLOCKER |
| `COMPATIBLE` parameter | Must be the same value on source and target | BLOCKER |
| `ARCHIVELOG` mode | Source must be in `ARCHIVELOG` mode (required for online migration) | BLOCKER if confirmed method is `ONLINE_PHYSICAL` / WARNING if `OFFLINE_PHYSICAL` |
| `SPFILE` in use | Source must run from SPFILE (required for online migration) | BLOCKER if confirmed method is `ONLINE_PHYSICAL` / WARNING if `OFFLINE_PHYSICAL` |
| TDE wallet status | Source wallet must be OPEN (mandatory for cloud targets, DB 12.2+) | BLOCKER |
| Hostname | Source and target hostnames must differ | BLOCKER |
| `/tmp` execute permission | `/tmp` must be mounted with `execute` on both source and target | BLOCKER |
| Timezone file version | Target timezone version must be ≥ source | WARNING |
| `SQLNET.ORA` encryption algorithm | Must match between source and target | WARNING |
| ZDM host resolves target RAC node hostnames | `getent hosts <tgt-node1> [<tgt-node2> ...]` from ZDM host (if target is RAC) — all nodes must resolve to an IP | BLOCKER (if RAC) |
| Source oracle user sudo (ZDM `zdmauth` pattern) | `ssh <src-user>@<src-host> "sudo -u oracle id"` must return oracle UID without error | BLOCKER |
| Source one-off patches vs target RU (PATCH_CHECK) | Compare `opatch lspatches` on source and target. If target RU ≥ source RU and source has individually-named patches subsumed by the target RU, flag PATCH_CHECK risk. See remediation below. | WARNING — pre-populate `-ignore PATCH_CHECK` in Step 7 when flagged |
| Target datapatch compatibility | `datapatch -prereqs` exits cleanly on all target nodes without `Unsupported named object type` error at `sqlpatch.pm` | WARNING |

**Missing data handling:** If a required compatibility value was not collected in Step 4, flag it as `[DATA MISSING]` in the gate output and treat it as a BLOCKER — re-run Step 4 with the updated discovery scope before proceeding.

### 2b. Rule Evaluation (CR-17)

After the compatibility gate table, include a `Rule Evaluation` section with one line per evaluated rule:

```
RULE:<id>:<PASS|FAIL|WARN>:<remediation_ref-or-none>
```

For mapped failures, include the matching `ERR-*` id from `.github/requirements/Phase10/Rules/zdm-errors.yaml`.

### 3. Executive Summary

Table by component — Source Database, Target Environment, ZDM Server, Network:

| Component | Status | Key Findings |
|-----------|--------|--------------|
| Source Database | ✅/⚠️/❌ | Brief status |
| Target Environment | ✅/⚠️/❌ | Brief status |
| ZDM Server | ✅/⚠️/❌ | Brief status |
| Network | ✅/⚠️/❌ | Brief status |

### 4. Migration Method Recommendation
- Recommended method: `ONLINE_PHYSICAL` or `OFFLINE_PHYSICAL`
- Explicit justification based on discovered evidence (archivelog mode, force logging, TDE, supplemental logging, downtime window requirements)

### 5. Source Database Details
- Database identification: name, unique name, version, size, character set
- ARCHIVELOG mode, Force Logging, Supplemental Logging, TDE — current state vs. required state with status

Configuration status table:

| Requirement | Current State | Required State | Status |
|-------------|---------------|----------------|--------|
| ARCHIVELOG Mode | YES/NO | YES | ✅/❌ |
| Force Logging | YES/NO | YES | ✅/❌ |
| Supplemental Logging | YES/NO | YES (online) | ✅/⚠️ |
| TDE Enabled | YES/NO | N/A | ✅ |

### 6. Target Environment Details
- Platform, Oracle version, and readiness indicators relevant to migration

### 7. ZDM Server Details

- ZDM version discovered from `zdm_installation.zdm_version` in server discovery JSON
- ZDM service posture (running/stopped, active jobs)
- ZDM version assessment status

| Property | Value |
|----------|-------|
| ZDM Version | <from discovery — zdm_installation.zdm_version> |
| ZDM Home | <from discovery> |
| ZDM Service Status | Running / Stopped |
| Active Jobs | <count> |

**Classification guardrails (S5-09):**
- If Step 4 discovery completed successfully, do not classify "oracle SSH directory not found" as a blocker by itself. ZDM uses admin users with `sudo -u oracle`; discovery success already confirms SSH connectivity.
- Always evaluate ZDM version evidence from `zdm_installation.zdm_version` in server discovery output.
- If ZDM version is UNDETERMINED or outdated, generate a Required Action: *Verify ZDM is the latest stable release; upgrade if necessary (see My Oracle Support — "Zero Downtime Migration").*

### 8. Required Actions Before Migration

Split by severity:
- **Critical (must fix before continuing)** — blockers that prevent migration
- **Recommended (should fix before go-live)** — advisory items

### 9. Discovered Values Reference

Complete list of all discovered values for reuse in Steps 5–6 (including ORACLE_HOME, SID, unique names, DB versions, ZDM home, region evidence).

### 10. Mismatch Report *(include only when configured intent differs from discovery evidence)*

| Field | Configured Intent | Discovered Value | Recommended Action |
|-------|-------------------|------------------|--------------------|
| [field] | [value from ssh-config.md / db-config.md / zdm-env.md] | [observed value] | [action] |

---

## Compatibility Gate Decision (S5-05)

After writing the Discovery Summary (Part 1), apply the gate outcome before proceeding to any interview or questionnaire output:

**If any BLOCKER is found:**
- Write `Discovery-Summary.md` marked with `[BLOCKED — compatibility gate failed]` in the document header.
- In the **Required Actions (Critical)** section of the Discovery Summary, include each blocker with its full remediation context from the remediation paths section below — Step 6 reads this section to generate the correct fix scripts.
- Do not write `Migration-Decisions.md`.
- Halt the migration planning interview.
- In the **chat**, display only a concise table of blockers:

  | # | Blocker | One-line description |
  |---|---------|---------------------|
  | 1 | `<check name>` | `<brief reason>` |

  Do **not** paste manual Oracle commands or detailed remediation steps into the chat — that detail is in the Discovery Summary for Step 6 to consume.
- Tell the user:

  > **Blockers found — Step 5 paused.** Run `@Phase10-Step6-Fix-Issues` to generate automated remediation scripts for the issues above. After applying and verifying the fixes, re-run `@Phase10-Step4-Generate-Discovery-Scripts` if structural changes were made, then re-run this prompt.

**If only WARNINGs are found:**
- Continue with the interview.
- Include warnings in the Discovery Summary required-actions section.
- Note in `Migration-Decisions.md` that the warnings were acknowledged.

**If all checks PASS:**
- Proceed directly to Part 2 (Migration Planning Interview).

### Remediation Paths for Blockers (S5-12)

**DB release mismatch (source release ≠ target release, physical migration):**
Physical migration requires both databases at the same Oracle release (major.minor — e.g., both 12.2 or both 19c). Patch-level differences (RU/PSU) are acceptable if target ≥ source — flag as WARNING only; ZDM handles this via `datapatch`. Three options for a release mismatch:
1. Reprovision the target at the same version as source and re-run Step 4.
2. ZDM migrate+upgrade: provision target at the same version as source and supply `ZDM_UPGRADE_TARGET_HOME` pointing to a higher-version Oracle Home already on the target. Supported for 12.2+ source to 19c target CDB (optionally `ZDM_PRE_UPGRADE_TARGET_HOME` for non-CDB to PDB conversion).
3. Switch to logical migration (ZDM logical, DataPump, or GoldenGate) — supports cross-version and cross-platform migrations.

**Character set mismatch:**
Provision a new target with the same character set as source, or perform character set migration on source (requires extensive testing). Cross-character-set migration requires the logical migration path.

**`COMPATIBLE` parameter mismatch:**
`ALTER SYSTEM SET COMPATIBLE='<value>' SCOPE=SPFILE;` on the mismatched host, then restart. Note: lowering `COMPATIBLE` is not supported — if the target value is higher, set the source value on the target.

**`ARCHIVELOG` mode:**
`SHUTDOWN IMMEDIATE; STARTUP MOUNT; ALTER DATABASE ARCHIVELOG; ALTER DATABASE OPEN;`

**SPFILE not in use:**
`CREATE SPFILE FROM PFILE; SHUTDOWN IMMEDIATE; STARTUP;`

**TDE wallet not OPEN:**
`ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN IDENTIFIED BY <password>;` (non-CDB) or with `CONTAINER=ALL` for CDB. Verify with `SELECT * FROM v$encryption_wallet;`.

**Hostname collision:**
Source and target must be on different hosts — reprovision the target on a different host.

**`/tmp` missing execute permission:**
`mount -o remount,exec /tmp`. Make permanent by removing `noexec` from the `/tmp` entry in `/etc/fstab`.

**Timezone file version (target < source):**
Apply the appropriate DST patch to the Oracle home on the target and run `DBMS_DST` procedures. Reference: Oracle Doc ID 1509653.1.

**PATCH_CHECK (PRGT-1017) with higher target RU:**
When target is at a higher Release Update (RU) than source and source has individually-named one-off patches (e.g., 19.3 one-offs migrating to a 19.29 target), ZDM's PATCH_CHECK phase flags each source patch not individually present in the target home, even though those patches are subsumed by the target's higher RU. This is documented ZDM behavior, not a configuration error. The safe resolution is to add `-ignore PATCH_CHECK` to both `zdmcli migrate database -eval` and `zdmcli migrate database` commands. This flag suppresses the individual patch-number comparison and relies on the target RU for supersession. Confirm that target RU ≥ source RU before using this flag. When Step 5 flags PATCH_CHECK as WARNING, Step 7 must pre-populate `-ignore PATCH_CHECK` in `zdm_commands.sh` with an explanatory comment.

**ZDM host cannot resolve target RAC node hostnames:**
Add the missing RAC node hostname-to-IP entries to `/etc/hosts` on the ZDM jumpbox (not the source or target). Run `getent hosts <node>` to verify after editing. Step 6 generates `fix_W04_zdm_host_hosts_resolution.sh` for this.

**Source oracle user sudo not configured:**
Configure sudoers on the source host to allow the ZDM admin user to run commands as `oracle` without a password. Add a line to `/etc/sudoers.d/zdmauth` (or equivalent): `<zdm-admin-user> ALL=(oracle) NOPASSWD: ALL`. Verify with `ssh <src-user>@<src-host> "sudo -u oracle id"`. This is a ZDM-specific requirement from the ZDM Installation Guide, separate from standard Oracle DB setup docs. Step 6 generates `fix_W05_source_oracle_sudo.sh` for this.

---

## Part 2: Migration Planning Interview

**Do not write `Migration-Decisions.md` until all interview phases below are fully answered (S5-10, S5-05).**

Run the interview in three sequential phases. For each question:
- Present the discovered or config-artifact-sourced recommended default inline.
- If `zdm-env.md` is attached and provides a non-placeholder value, present it as the pre-filled default and ask for confirmation — not an open question (S5-10).
- Wait for the operator to respond before moving to the next question (S5-05).
- Do not ask questions whose answers cannot influence an RSP parameter, a `zdmcli` argument, or runbook content (S5-05).

---

### Phase A — Platform and Storage (A1 already confirmed above)

The migration method (`MIGRATION_METHOD`) was confirmed in the Preliminary Question before the compatibility gate. Present questions A2 and A3 together as a **numbered list in a single chat message** (CR-16-A). Do NOT use `vscode_askQuestions` — questions must appear in the chat as plain numbered markdown, not as a VS Code dialog.

Read the **Layer 0** rows from the CR-14 prerequisite catalog file (`.github/requirements/Phase10/ZDM-Prerequisites/<version>/<method>.md`, loaded per CR-14-A) before posting the question block, to populate the allowed values for both questions.

Post this question block:

---

**Migration Planning — Platform & Storage (please answer by number):**

1. **Target Platform Type** (`PLATFORM_TYPE` RSP parameter) — [list allowed values and their RSP mappings from the Layer 0 catalog exactly as listed; do not hardcode values here]. Based on Step 4 discovery, recommended: **[inferred from target environment type]**
2. **Source Storage Type** (determines `zdmcli` identifier flag) — [list allowed values and their CLI flag mappings from the Layer 0 catalog exactly as listed]. Based on Step 4 discovery, recommended: **[inferred from `db_create_file_dest` parameter or ASM PMON evidence]**

*Reply with answers by number, e.g.:*
```
1: <value from catalog>
2: <value from catalog>
```

---

Parse the user's reply and map answers back by number. Do not proceed to Phase B until both questions are answered.

---

### Phase B — Migration-type-specific questions

Ask **only** the questions for the method confirmed in Phase A. Present as a **numbered list in a single chat message** (CR-16-A). Do NOT use `vscode_askQuestions`. Continue numbering sequentially from Phase A (Phase A ended at question 2).

**If ONLINE_PHYSICAL:** post this question block:

---

**Migration Planning — Online Physical Settings (please answer by number):**

3. **Log switch interval (minutes)** (`LOG_SWITCH_INTERVAL`) *(default: `20`)*
4. **Data Guard protection mode** (`DATAGUARD_PROTECTION_MODE`) *(default: `MAX_PERFORMANCE`)*
5. **Data transfer medium** (`DATA_TRANSFER_MEDIUM`) *(default: `OSS`)*
6. **Insert pause point before switchover?** (`PAUSE_BEFORE_SWITCHOVER`, YES/NO) *(default: `YES`)*
7. **Enable auto-switchover?** (`AUTO_SWITCHOVER`, YES/NO) *(default: `NO`)*

*Reply with answers by number, e.g.:*
```
3: 20
4: MAX_PERFORMANCE
5: OSS
6: YES
7: NO
```

---

**If OFFLINE_PHYSICAL:** post this question block:

---

**Migration Planning — Offline Physical Settings (please answer by number):**

3. **Backup/transfer medium** (`DATA_TRANSFER_MEDIUM`) *(default: `OSS`)*
4. **Maximum acceptable downtime window (hours)** *(for runbook planning, default: `4`)*

*Reply with answers by number, e.g.:*
```
3: OSS
4: 4
```

---

Parse the user's reply and map answers back by number. Do not proceed to Phase C until all Phase B questions are answered.

---

### Phase C — Object Storage *(present only if OSS transfer medium was selected in Phase B)*

> **Note (CR-16-B):** OCI identity parameters (Tenancy OCID, User OCID, Compartment OCID, Target Database OCID) are **not required** for physical migrations — ZDM uses the OCI config file on the ZDM host, set up during Step 2 installation. Do not ask for them.

Present questions as a **numbered list in a single chat message** (CR-16-A). Do NOT use `vscode_askQuestions`. Continue numbering sequentially from Phase B (ONLINE: Phase B ended at 7, so start at 8; OFFLINE: Phase B ended at 4, so start at 5).

Post this question block *(adjusting the leading number to continue from Phase B)*:

---

**Migration Planning — Object Storage (please answer by number):**

*(N+0).* **OCI Object Storage namespace** (`OSS_BUCKET_NAMESPACE`) — pre-fill from `db-config.md` or `zdm-env.md` if available
*(N+1).* **OCI Object Storage bucket name** (`OSS_BUCKET_NAME`) — pre-fill from `db-config.md` or `zdm-env.md` if available
*(N+2).* **OCI Object Storage bucket region** (`OSS_BUCKET_REGION`) — inferred from target discovery if available, otherwise ask

*Reply with answers by number.*

---

*(If the transfer medium is not OSS, skip Phase C entirely.)*

---

### Phase D — TDE/Wallet *(present only if TDE is enabled on the source database)*

Present as a **numbered list in a single chat message** (CR-16-A). Continue numbering sequentially from the last answered phase.

Post this question block *(adjusting the leading number to continue from Phase C or Phase B)*:

---

**Migration Planning — TDE/Wallet (please answer by number):**

*(N).* **Wallet/TLS migration required?** (`WALLET_MIGRATION`, YES/NO) — based on TDE wallet status discovered in Step 4 *(default: `YES` if TDE is enabled)*

*Reply with answers by number.*

---

---

## Part 2b: Write Migration Decisions Record

After all interview phases (A, B, C) are fully answered, write `Artifacts/Phase10-Migration/Step5/Migration-Decisions.md` as a completed **Decisions Record** (S5-11, S5-12).

This file is the primary RSP parameter input for Step 6. It must contain **no blank, placeholder, or unanswered values**.

Required sections:

### 1. Generation Metadata
- Date/time of interview completion
- Confirmed migration method

### 2. Decisions Table

One row per answered question. No blank or placeholder values permitted (S5-12):

| Parameter | RSP / CLI Mapping | Value | Source |
|-----------|-------------------|-------|--------|
| MIGRATION_METHOD | `MIGRATION_METHOD` | ONLINE_PHYSICAL | confirmed by operator |
| PLATFORM_TYPE | `PLATFORM_TYPE` | <from Layer 0 catalog> | confirmed by operator |
| SOURCE_STORAGE_TYPE | *(zdmcli flag)* | <from Layer 0 catalog> | confirmed by operator |
| LOG_SWITCH_INTERVAL | `LOG_SWITCH_INTERVAL` | 20 | confirmed by operator |
| DATAGUARD_PROTECTION_MODE | `DATAGUARD_PROTECTION_MODE` | MAX_PERFORMANCE | confirmed by operator |
| DATA_TRANSFER_MEDIUM | `DATA_TRANSFER_MEDIUM` | OSS | confirmed by operator |
| PAUSE_BEFORE_SWITCHOVER | `PAUSE_BEFORE_SWITCHOVER` | YES | confirmed by operator |
| AUTO_SWITCHOVER | `AUTO_SWITCHOVER` | NO | confirmed by operator |
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

If any required question was not answered, record the parameter as `BLOCKED — <reason>` and surface it as a Critical blocker in the Step 5 README (S5-12).

---

## Part 3: Generate Step 5 README

Write `Artifacts/Phase10-Migration/Step5/README.md` (CR-07) summarizing:
- **Generated files** for this step and their purpose
- **Review checklist** — what the operator must verify before proceeding to Step 6
- **Output location** — all files in `Artifacts/Phase10-Migration/Step5/`
- **Success signals**: all three files created; interview fully completed; Decisions Record contains no blank/placeholder/BLOCKED values; no unresolved critical blockers
- **Failure signals**: missing Step 4 discovery inputs; unresolvable blockers; BLOCKED rows in Decisions Record

---

## Validation Evidence

After writing all output files, confirm creation and provide a concise summary (CR-11):
- List each output file path written
- Confirm each file was created successfully (non-empty)
- Note any sections that could not be populated due to missing discovery evidence

---

## Output Files

```
Artifacts/Phase10-Migration/
└── Step4/
    ├── README.md                    # Step summary, review checklist, next steps
    ├── Discovery-Summary.md         # Auto-populated analysis of Step 4 discovery evidence
    └── Migration-Decisions.md       # Completed Decisions Record (no blank/placeholder values)
```

All files are git-ignored. No outputs are committed or create PRs.

---

## Next Step

**When Step 5 completes with no unresolved Critical blockers** and `Migration-Decisions.md` contains no BLOCKED rows:

> Run **`@Phase10-Step6-Fix-Issues`** in this Remote-SSH VS Code session connected to the ZDM jumpbox as **`zdmuser`**.

**When Step 5 halts due to compatibility gate blockers:**

> Run **`@Phase10-Step6-Fix-Issues`** to generate remediation scripts for the listed blockers. After running and verifying the fixes, re-run **`@Phase10-Step4-Generate-Discovery-Scripts`** (if structural changes were made to the environment), then re-run **`@Phase10-Step5-Discovery-Questionnaire`** to confirm all blockers are resolved.
