# Step3 User Requirements - Discovery Questionnaire

## Objective

Analyze Step2 discovery outputs and produce planning artifacts for manual migration decisions.

## S3-01: Output contract

Required generated files:

- `Artifacts/Phase10-Migration/Step3/Discovery-Summary.md`
- `Artifacts/Phase10-Migration/Step3/Migration-Questionnaire.md`

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

## S3-07: Migration Questionnaire generated items

`Migration-Questionnaire.md` should include manual-input sections with recommendation and rationale:

1. Migration strategy decisions (online/offline, downtime window, cutover approach).
2. OCI/Azure identifiers requiring operator entry.
3. Object storage/staging selections when applicable.
4. Migration options (Data Guard posture, pause points, switchover preferences).
5. Network configuration questions when discovery does not fully establish required paths.
