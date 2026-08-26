---
name: validate-source
description: "Validate Oracle source database compatibility for ZDM migrations, including platform, version, patch level, size, and deployment model."
---

# Validate Source

## Procedure

1. Read the source fields from the migration profile.
2. Verify that platform, database version, patch level, size, and the database service
	ZDM will use are present.
3. Compare the values with the selected migration pattern and target prerequisites.
4. Require observed success from password-based SYSDBA authentication through that
	service. A local operating-system-authenticated `sqlplus / as sysdba` session does
	not prove this requirement. Do not request or persist the password.
5. Return `pass`, `fail`, or `needs-review` with evidence and remediation. Return
	`needs-review` when authentication has not been tested and `fail` when the test
	returns an authentication error.

## SYS Authentication Check

When the customer asks for help, ask them to run this on the source database host as
the Oracle software owner, replacing `<source-service>` with the profile's known
service name:

```sh
sqlplus -L "sys@<source-service> as sysdba"
```

SQL*Plus must prompt for the password interactively. Never place it in the command.
After connecting, the customer may run `SELECT 'SYS_AUTH_PASS' FROM dual;` and return
only `SYS_AUTH_PASS`, or return only the `ORA-` error number on failure. Do not ask for
the password, connect descriptor, or raw session transcript.

## Missing patch-level evidence

If the source patch level is unknown, offer these customer-run, read-only checks.
Ask for only the latest successful Database Release Update description and patch ID.

Run this in SQL*Plus or SQLcl as an account permitted to query
`DBA_REGISTRY_SQLPATCH`:

```sql
SELECT patch_id, patch_type, action, status, description, action_time
FROM dba_registry_sqlpatch
WHERE status = 'SUCCESS'
ORDER BY action_time DESC;
```

If the view is unavailable or does not reflect the Oracle home inventory, run this on
the source database host as the Oracle software owner:

```sh
$ORACLE_HOME/OPatch/opatch lspatches
```

Explain that the customer should paste only the database RU/RUR line or patch ID and
may redact hostnames, paths, and other environment identifiers. Do not infer that an
installed patch is valid for the selected migration pattern until it is compared with
the target prerequisites.

Do not collect credentials or expose connection secrets in validation output.
