---
name: validate-target
description: "Validate Oracle ZDM target database prerequisites, including Oracle-home patch parity with the source."
---

# Validate Target

## Procedure

1. Read the target platform, Oracle home, database version, patch level, and selected
   route from the canonical migration profile. Read the normalized source RU/RUR
   description and patch ID produced by `validate-source`; do not ask the customer to
   repeat known source values.
2. Collect observed target patch evidence using the customer-run checks below. Treat a
   supplied target patch level as profile data, not observed evidence.
3. Require a target-service administrator to compare the normalized source and target
   RU/RUR evidence and verify ZDM-compatible Oracle-home patch parity. A newer target RU
   alone is not proof: source one-offs or overlay fixes may still be absent from the
   target.
4. Derive `migration.target.patch_parity_verified`; never accept an unsupported yes/no
   questionnaire answer. Accept only a sanitized comparison result containing the
   source and target RU/RUR patch IDs plus `PATCH_PARITY_PASS`, or
   `PATCH_PARITY_FAIL` plus source-only patch identifiers approved for disclosure.
5. Never persist raw SQL or OPatch output, hostnames, Oracle-home paths, or the complete
   ZDM patch discrepancy. Persist only normalized source and target RU/RUR descriptions
   and patch IDs, the sanitized comparison result, and the derived Boolean.
6. Return `needs-review` when target evidence or parity assessment is missing, `fail`
   when source-required fixes are missing, and `pass` only after observed parity
   approval. A successful ZDM eval remains the final compatibility gate.
7. On failure, direct the customer to the supported Oracle Database@Azure patching
   process or Oracle Support. Do not advise blindly applying a ZDM-generated list and
   do not add `-ignore` or other bypass flags.

## Target patch-level evidence

Ask the customer to run this read-only query against the target database in SQL*Plus
or SQLcl as an account permitted to query `DBA_REGISTRY_SQLPATCH`:

```sql
SELECT patch_id, patch_type, action, status, description, action_time
FROM dba_registry_sqlpatch
WHERE status = 'SUCCESS'
ORDER BY action_time DESC;
```

Ask for only the latest successful database RU/RUR description and patch ID. This view
shows SQL patch application and is not sufficient by itself to prove Oracle-home binary
patch parity.

When the view is unavailable, does not reflect the target Oracle-home inventory, or
one-off and overlay comparison is required, ask the customer or target-service
administrator to run this as the target Oracle software owner when that access is
supported:

```sh
$ORACLE_HOME/OPatch/opatch lspatches
```

If Oracle Database@Azure service controls prevent the customer from collecting the
Oracle-home evidence, return `needs-review` and direct them to the supported service
patching process or Oracle Support. Ask for only the RU/RUR line and patch identifiers
approved for disclosure, not the complete inventory.

## Result Contract

Return `target_validation` with:

- `status`: `pass`, `fail`, or `needs-review`;
- `evidence`: normalized source and target RU/RUR descriptions and patch IDs, target
   version, sanitized patch-parity result, and derived parity Boolean only;
- `findings`: missing or unverified target prerequisites;
- `remediation`: customer-owned supported patching or support action.