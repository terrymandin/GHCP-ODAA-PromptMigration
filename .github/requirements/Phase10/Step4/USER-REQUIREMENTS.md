# Step4 User Requirements - Discovery Questionnaire

## Objective

Analyze Step3 discovery outputs and produce planning artifacts for manual migration decisions.

## S4-01: Output contract

Required generated files:

- `Artifacts/Phase10-Migration/Step4/Discovery-Summary.md`
- `Artifacts/Phase10-Migration/Step4/Migration-Decisions.md`

## S4-02: Input model

Primary inputs:

- Source discovery files (txt/json)
- Target discovery files (txt/json)
- ZDM server discovery files (txt/json)

Optional companion inputs for configured intent/baseline comparison (see CR-12):

- `Artifacts/Phase10-Migration/Step2/ssh-config.md` — SSH connectivity configuration written by Step2.
- `Artifacts/Phase10-Migration/Step3/db-config.md` — database and ZDM configuration written by Step3.
- `zdm-env.md` — legacy override, used when step config artifacts are absent.

## S4-03: Mismatch handling

1. Treat discovery files as observed runtime evidence.
2. Treat step config artifacts (`ssh-config.md`, `db-config.md`) or `zdm-env.md` as configured intent.
3. If they differ, explicitly report mismatches and remediation guidance.

## S4-04: Required analysis sections

Discovery Summary must include:

1. Environment overview.
2. ZDM compatibility gate results (see S4-05) — must appear before readiness assessment.
3. Readiness assessment with met requirements, required actions, and blockers.
4. Discovered configuration reference.
5. Migration method recommendation and rationale.

## S4-05: ZDM compatibility gate

Before conducting the migration planning interview or writing any questionnaire output, evaluate the following compatibility checks using Step3 discovery evidence. Present results in a structured table in the Discovery Summary.

### Compatibility checks

| Check | Rule | Severity if failed |
|-------|------|--------------------|
| DB release (source vs target) | Oracle Database release (major.minor, e.g. 12.2, 19c) must be identical for physical migration. Patch level (RU/PSU) may differ — target patch level must be ≥ source; ZDM runs `datapatch` automatically when target patch is higher. | BLOCKER if release differs; WARNING if patch level differs |
| Character set | Source `NLS_CHARACTERSET` must equal target | BLOCKER |
| `COMPATIBLE` parameter | Must be the same value on source and target | BLOCKER |
| `ARCHIVELOG` mode | Source must be in `ARCHIVELOG` mode (required for online migration) | BLOCKER (online) / WARNING (offline) |
| `SPFILE` in use | Source must run from SPFILE (required for online migration) | BLOCKER (online) / WARNING (offline) |
| TDE wallet status | Source wallet must be OPEN (mandatory for cloud targets, DB 12.2+) | BLOCKER |
| Hostname | Source and target hostnames must differ | BLOCKER |
| `/tmp` execute permission | `/tmp` must be mounted with `execute` on both source and target | BLOCKER |
| Timezone file version | Target timezone version must be ≥ source | WARNING |
| `SQLNET.ORA` encryption algorithm | Must match between source and target | WARNING |

### Gate output format

Produce a gate result block in the Discovery Summary:

```
ZDM Compatibility Gate
======================
[PASS/FAIL/WARN]  <check name>:  source=<value>  target=<value>  [note if applicable]
```

### Gate behavior

1. If **any BLOCKER** is found:
   - Halt the migration planning interview.
   - Do not write `Migration-Decisions.md`.
   - Mark the Discovery Summary with `[BLOCKED — compatibility gate failed]`.
   - Surface each blocker explicitly with the remediation path from S4-06.

2. If only WARNINGs are found:
   - Continue with the interview.
   - Include warnings in the Discovery Summary required-actions section.
   - Note in `Migration-Decisions.md` that the warnings were acknowledged.

3. If all checks PASS:
   - Proceed directly to the migration planning interview.

### Handling missing discovery data

If a required compatibility value was not collected in Step3 (e.g., `COMPATIBLE` parameter or timezone version not present in discovery files), flag it as `[DATA MISSING]` in the gate output and treat it as a BLOCKER requiring re-run of Step3 with the updated discovery scope before proceeding.

## S4-06: Compatibility gate remediation paths

For each BLOCKER type, provide the following guidance:

**DB release mismatch (source release ≠ target release, physical migration):**
Physical migration (ONLINE_PHYSICAL / OFFLINE_PHYSICAL) requires source and target to be at the same Oracle Database release (major.minor — e.g., both 12.2, or both 19c). A patch-level difference (RU/PSU) is acceptable as long as the target patch level is ≥ source; ZDM handles this automatically via `datapatch` — flag as WARNING only. Three remediation options for a release mismatch:
1. Reprovision the target database at the same version as the source, then re-run Step3.
2. Use ZDM migrate+upgrade workflow: provision the target at the same version as source, then supply `ZDM_UPGRADE_TARGET_HOME` pointing to a higher-version Oracle Home already provisioned on the target — ZDM will migrate then upgrade. Supported for 12.2+ source to 19c target CDB (requires `ZDM_UPGRADE_TARGET_HOME` and optionally `ZDM_PRE_UPGRADE_TARGET_HOME` for non-CDB to PDB conversion).
3. Switch to logical migration (ZDM logical, DataPump, or GoldenGate) which supports cross-version and cross-platform migrations.

**Character set mismatch:**
Character set must match. Remediation: provision a new target database with the same character set as the source, or perform a character set migration on the source (requires extensive testing). Cross-character-set migration requires the logical migration path.

**`COMPATIBLE` parameter mismatch:**
Set `COMPATIBLE` to the same value on both source and target: `ALTER SYSTEM SET COMPATIBLE='<value>' SCOPE=SPFILE;` then restart. Note: lowering `COMPATIBLE` is not supported — the target must be at `≥` source value; set source value on target if target is higher.

**`ARCHIVELOG` mode:**
Enable archivelog mode on source: `SHUTDOWN IMMEDIATE; STARTUP MOUNT; ALTER DATABASE ARCHIVELOG; ALTER DATABASE OPEN;`

**SPFILE not in use:**
Create SPFILE from PFILE: `CREATE SPFILE FROM PFILE; SHUTDOWN IMMEDIATE; STARTUP;`

**TDE wallet not OPEN:**
Open the TDE wallet: `ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN IDENTIFIED BY <password>;` (non-CDB) or with `CONTAINER=ALL` for CDB. Verify with `SELECT * FROM v$encryption_wallet;`.

**Hostname collision:**
Source and target must be on different hosts. This is a provisioning error — provision the target on a different host.

**`/tmp` missing execute permission:**
Remount `/tmp` with execute: `mount -o remount,exec /tmp`. To make permanent, update `/etc/fstab` to remove the `noexec` option for `/tmp`.

**Timezone version (target < source):**
Upgrade target timezone file before migration: apply the appropriate DST patch to the Oracle home on the target and run `DBMS_DST` procedures. Refer to Oracle Doc ID 1509653.1 for the upgrade procedure.

## S4-07: Discovery Summary generated items

`Discovery-Summary.md` should include at least:

1. Generation metadata: date/time and source discovery files analyzed.
2. **ZDM compatibility gate results** (from S4-05) — structured pass/fail/warn table; must appear before executive summary.
3. Executive summary by component (source/target/ZDM/network) with status.
4. Migration method recommendation with explicit justification.
5. Source database details and readiness checks (archivelog/force/supplemental/TDE and related prechecks).
6. Target environment details relevant to migration readiness.
7. ZDM server details including discovered version evidence and service posture.
8. Required actions split by severity (critical vs recommended) — compatibility gate blockers appear first.
9. Discovered values reference section for Step5/Step6 reuse.
10. Mismatch section when `zdm-env.md` intent differs from discovery evidence.

## S4-08: Migration Planning Interview

After generating the Discovery Summary, conduct a structured interactive interview in decision-tree order before writing any questionnaire output file.

Interview phases — must be completed in sequence:

**Phase A — Migration Type (gates all subsequent questions)**
1. Confirm (or override) the recommended migration method: ONLINE_PHYSICAL or OFFLINE_PHYSICAL.

**Phase B — Migration-type-specific questions**

For ONLINE_PHYSICAL only:
- Log switch interval preference (RSP: `LOG_SWITCH_INTERVAL`).
- Data Guard protection mode: MAX_PERFORMANCE / MAX_AVAILABILITY / MAX_PROTECTION (RSP: `DATAGUARD_PROTECTION_MODE`).
- Data transfer medium: DIRECT or OSS (RSP: `DATA_TRANSFER_MEDIUM`).
- Insert pause point before switchover? (RSP: `PAUSE_BEFORE_SWITCHOVER`).
- Enable auto-switchover? (RSP: `AUTO_SWITCHOVER`).

For OFFLINE_PHYSICAL only:
- Backup/transfer medium: OSS, NFS, or COPY (RSP: `DATA_TRANSFER_MEDIUM`).
- Maximum acceptable downtime window (runbook planning input).

**Phase C — Common questions (both paths)**
- OCI Tenancy OCID (RSP: `OCID_TENANCY` / `zdmcli -ocitenancy`). Mark as manual-entry required if not in `zdm-env.md`.
- OCI User OCID (RSP: `OCID_USER`). Mark as manual-entry required if not in `zdm-env.md`.
- OCI Compartment OCID (RSP: `OCID_COMPARTMENT`). Mark as manual-entry required if not in `zdm-env.md`.
- Target Database OCID (RSP: `OCID_TARGET_DATABASE`). Mark as manual-entry required if not in `zdm-env.md`.
- OCI Object Storage namespace, bucket name, and bucket region (RSP: `OSS_BUCKET_NAMESPACE`, `OSS_BUCKET_NAME`, `OSS_BUCKET_REGION`).
- TLS/wallet transfer medium if TDE is enabled (RSP: `WALLET_MIGRATION`).

Each question must present the discovered or `zdm-env.md`-sourced recommended default and ask the user to confirm or provide a value.

## S4-09: Interview preconditions

1. Do not begin the interview until Part 1 (Discovery Summary) analysis is complete.
2. If `zdm-env.md` is attached and contains a non-placeholder value for a question field, present that value as the pre-filled default and ask for confirmation — do not ask an open question.
3. Do not ask questions whose answers cannot influence an RSP parameter, a `zdmcli` argument, or runbook content.
4. Do not ask Phase B (ONLINE_PHYSICAL) questions when the confirmed method is OFFLINE_PHYSICAL, and vice versa.
5. Do not proceed to Phase C until Phase B is fully answered.

## S4-10: Decisions Record output

After the interview is complete, write `Migration-Decisions.md` as a **Decisions Record** '€” not a form to fill in.

The file must contain:

1. **Generation metadata** (date/time, migration method confirmed).
2. **Decisions table** with one row per answered question:

| Parameter | RSP / CLI Mapping | Value | Source |
|---|---|---|---|
| MIGRATION_METHOD | `MIGRATION_METHOD` | ONLINE_PHYSICAL | confirmed by operator |
| ... | ... | ... | discovered / confirmed / manual |

Source values: `discovered` (from Step3 evidence), `from zdm-env.md` (pre-filled and confirmed), `manual` (operator entered directly).

3. **Runbook planning notes** '€” any non-RSP answers (e.g., downtime window) recorded as free-form notes for the runbook author.

No blank or placeholder values are permitted in this file. All rows must be answered before the file is written.
