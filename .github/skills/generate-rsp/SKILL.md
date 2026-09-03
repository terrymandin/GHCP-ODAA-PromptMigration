---
name: generate-rsp
description: "Generate an Oracle ZDM response file from a validated migration profile and the matching repository template."
---

# Generate RSP

## Procedure

1. Confirm all required validations passed and the selected route is explicitly
	`enabled` in `../../config/migration-patterns.yaml` for the installed ZDM release.
	Return `fail` for an unmatched or disabled route. Never use the nearest route. The
	only allowed validation exception is unverified target patch parity when
	`migration.target.patch_parity_override` is explicitly `true`; preserve that result
	as a warning and never describe target validation or parity as passed.
2. Select only the template named by that enabled route and verify its provenance
	record. A missing, empty, or comment-only template is a failure.
3. For `vmdb-to-odaa-physical-offline-zdm26.1`, require these normalized
	profile values before rendering: NFS transfer medium, absolute shared backup
	path, target database unique name, and target ASM data, redo, and recovery disk
	groups. Do not infer these values from source platform or database names.
4. Render the required ZDM properties exactly as follows:
	`MIGRATION_METHOD=OFFLINE_PHYSICAL`, `DATA_TRANSFER_MEDIUM=NFS`,
	`PLATFORM_TYPE=EXACS`, `BACKUP_PATH`, `TGT_DB_UNIQUE_NAME`, `TGT_DATADG`,
	`TGT_REDODG`, and `TGT_RECODG`. Render `SKIP_FALLBACK=TRUE` only when selected.
5. Treat `PLATFORM_TYPE` as the target ZDM platform. Never map source
	`oracle_iaas` or VM DB to `PLATFORM_TYPE=VMDB` for an ODAA Exadata target.
6. Map validated profile values to template placeholders. Uppercase ZDM enum and
	boolean values while preserving paths, database names, and ASM disk groups.
7. Write the generated response file to the task output directory.
8. Reject generation when a required property is absent, duplicated, empty, or
	still contains an unresolved `{{...}}` placeholder. Reject unknown properties
	unless they are confirmed against the installed ZDM release. Require the rendered
	property set to equal the route's `expected_rsp_properties` set.
9. Reject secret values. Never render wallet passwords, private keys, credentials,
	tokens, or connection strings into the response file.
10. Do not render `SHUTDOWN_SRC=TRUE` for eval/precheck artifacts. Add it only after
	 explicit cutover approval for a customer-executed migration.

## Result Contract

Return and persist a sanitized result with:

- `status`: `pass`, `fail`, or `needs-review`;
- `route_id`, `zdm_release`, `template`, and `provenance`;
- `output_file` and rendered property names, but no secret values;
- `findings` and `remediation`.

Use `pass` only when the route is enabled, provenance exists, all prerequisite
validations passed, and the rendered file passes every schema and security check.
