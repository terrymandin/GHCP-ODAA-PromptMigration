---
name: validate-target
description: "Validate Oracle ZDM target database prerequisites, including Oracle-home patch parity with the source."
---

# Validate Target

## Procedure

1. Read the target platform, Oracle home, database version, patch level, and selected
   route from the canonical migration profile.
2. Require a target-service administrator to verify ZDM-compatible patch parity
   between the source and target Oracle homes. A newer target RU alone is not proof:
   source one-offs or overlay fixes may still be absent from the target.
3. Accept only a sanitized result: `PATCH_PARITY_PASS`, or `PATCH_PARITY_FAIL` plus
   source-only patch identifiers approved for disclosure. Never persist raw OPatch
   inventory, hostnames, Oracle-home paths, or the complete ZDM patch discrepancy.
4. Return `needs-review` when parity has not been assessed, `fail` when source-required
   fixes are missing, and `pass` only after observed parity approval.
5. On failure, direct the customer to the supported Oracle Database@Azure patching
   process or Oracle Support. Do not advise blindly applying a ZDM-generated list and
   do not add `-ignore` or other bypass flags.

## Result Contract

Return `target_validation` with:

- `status`: `pass`, `fail`, or `needs-review`;
- `evidence`: target version and sanitized patch-parity result only;
- `findings`: missing or unverified target prerequisites;
- `remediation`: customer-owned supported patching or support action.