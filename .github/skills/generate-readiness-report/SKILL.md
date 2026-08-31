---
name: generate-readiness-report
description: "Generate an Oracle ZDM migration readiness report from questionnaire answers and validation results."
---

# Generate Readiness Report

## Procedure

1. Summarize the assessment environment, source, target, migration method, and downtime
    requirement. If the environment is `production` or unspecified, add a warning that a
    representative non-production assessment is strongly recommended first.
2. List each remediation and validation status with sanitized evidence only.
3. For TDE remediation, report the selected non-secret scope, approval warnings,
   wallet status/type, key counts, and tablespace encryption status. Never include
   raw pasted output, wallet paths, key identifiers, passwords, or key material.
4. When the selected transfer medium is NFS, report the `nfs_storage` status and only
    its allowlisted categorical evidence: provider model, NFS version, private endpoint
    and DNS readiness, same-path mount, source/target access, marker visibility,
    capacity, persistence, and approvals. Never include subscription or tenant IDs,
    private IPs, host names, connection strings, mount output, or filesystem contents.
5. Separate blockers, warnings, and informational findings.
6. Derive the assessment decision deterministically:
     - `not ready` when any required remediation, validation, generation, or observed
         eval result is `fail`;
     - `ready for evaluation` when validations and generation pass but eval evidence is
         absent or `needs-review`;
     - `ready with warnings` when eval passes and unresolved non-blocking warnings exist;
    - `ready` only when eval passes and no blockers or warnings remain.
    Job creation or a generated command is not an eval pass. These labels describe
    readiness or results for this eval assessment only; they are not migration or
    production-readiness decisions.
7. Include the selected route ID, ZDM release, route provenance status, and eval job ID
     when observed. Do not include identity-file paths or other operationally sensitive
     metadata in the report.
8. Render the report with a template from `./templates/` when available.
9. Include a Scope and Limitations section stating that the workflow stops after
    customer-run `-eval` validation. A passing eval does not prove migration success,
    cutover readiness, fallback or rollback readiness, workload behavior, performance,
    recoverability, or production readiness.
