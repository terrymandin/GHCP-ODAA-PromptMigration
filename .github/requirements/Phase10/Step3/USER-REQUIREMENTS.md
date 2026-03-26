# Step3 User Requirements - Discovery Questionnaire

## Objective

Analyze Step2 discovery outputs and produce planning artifacts for manual migration decisions.

## S3-01: Output contract

Required generated files:

- `Artifacts/Phase10-Migration/Step3/Discovery-Summary.md`
- `Artifacts/Phase10-Migration/Step3/Migration-Decisions.md`

## S3-02: Input model

Primary inputs:

- Source discovery files (txt/json)
- Target discovery files (txt/json)
- ZDM server discovery files (txt/json)

Optional companion input:

- `zdm-env.md` for configured intent/baseline comparison

## S3-03: Mismatch handling

1. Treat discovery files as observed runtime evidence.
2. Treat `zdm-env.md` as configured intent.
3. If they differ, explicitly report mismatches and remediation guidance.

## S3-04: Required analysis sections

Discovery Summary must include:

1. Environment overview.
2. Readiness assessment with met requirements, required actions, and blockers.
3. Discovered configuration reference.
4. Migration method recommendation and rationale.

## S3-06: Discovery Summary generated items

`Discovery-Summary.md` should include at least:

1. Generation metadata: date/time and source discovery files analyzed.
2. Executive summary by component (source/target/ZDM/network) with status.
3. Migration method recommendation with explicit justification.
4. Source database details and readiness checks (archivelog/force/supplemental/TDE and related prechecks).
5. Target environment details relevant to migration readiness.
6. ZDM server details including discovered version evidence and service posture.
7. Required actions split by severity (critical vs recommended).
8. Discovered values reference section for Step4/Step5 reuse.
9. Mismatch section when `zdm-env.md` intent differs from discovery evidence.

## S3-07: Migration Planning Interview

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

## S3-10: Interview preconditions

1. Do not begin the interview until Part 1 (Discovery Summary) analysis is complete.
2. If `zdm-env.md` is attached and contains a non-placeholder value for a question field, present that value as the pre-filled default and ask for confirmation — do not ask an open question.
3. Do not ask questions whose answers cannot influence an RSP parameter, a `zdmcli` argument, or runbook content.
4. Do not ask Phase B (ONLINE_PHYSICAL) questions when the confirmed method is OFFLINE_PHYSICAL, and vice versa.
5. Do not proceed to Phase C until Phase B is fully answered.

## S3-11: Decisions Record output

After the interview is complete, write `Migration-Decisions.md` as a **Decisions Record** — not a form to fill in.

The file must contain:

1. **Generation metadata** (date/time, migration method confirmed).
2. **Decisions table** with one row per answered question:

| Parameter | RSP / CLI Mapping | Value | Source |
|---|---|---|---|
| MIGRATION_METHOD | `MIGRATION_METHOD` | ONLINE_PHYSICAL | confirmed by operator |
| ... | ... | ... | discovered / confirmed / manual |

Source values: `discovered` (from Step2 evidence), `from zdm-env.md` (pre-filled and confirmed), `manual` (operator entered directly).

3. **Runbook planning notes** — any non-RSP answers (e.g., downtime window) recorded as free-form notes for the runbook author.

No blank or placeholder values are permitted in this file. All rows must be answered before the file is written.
