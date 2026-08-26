---
name: validate-tde
description: "Validate Oracle Transparent Data Encryption prerequisites for physical ZDM migrations."
---

# Validate TDE

## Procedure

1. Confirm whether TDE is enabled on the source database.
2. If `enable-tde` ran, require a successful `tde_enablement` result and use only
	its sanitized evidence. Do not treat script completion markers as proof.
3. Verify that every required container has an open wallet or keystore and a master
	encryption key without collecting secrets or persisting key identifiers.
4. Verify that every customer-selected tablespace is encrypted with the expected
	algorithm and that target requirements are compatible.
5. Return `pass`, `fail`, or `needs-review` with evidence and remediation guidance.
