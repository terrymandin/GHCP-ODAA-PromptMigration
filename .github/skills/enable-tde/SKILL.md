---
name: enable-tde
description: "Guide customer-run Oracle TDE enablement when a migration profile reports TDE is disabled; provide staged scripts, require disruptive-operation approval, and validate sanitized pasted evidence without collecting secrets."
---

# Enable TDE

Use this skill only for customer-mediated TDE remediation. The customer runs every
database and operating-system command. Never connect to Oracle or execute a bundled
script on the customer's behalf.

## Supported Scope

- Oracle Database 19c, 21c, and 23ai.
- CDB and non-CDB databases on all source platforms in the questionnaire. For RAC,
  the responsible DBA must provide the approved shared-wallet placement and
  cluster-aware restart procedure before configuration artifacts are rendered.
- File-based keystores and customer-selected permanent user tablespaces.

Return `needs-review` without presenting enablement commands for Oracle 11g or 12c,
external key managers, or configurations outside this scope.

## Procedure

1. Read the migration profile. If `tde_enabled` is `true`, return `pass` with
   `action: none` and do not offer scripts.
2. When TDE is disabled, require `database_architecture`, `oracle_sid`,
   `wallet_root`, and `selected_tablespaces`. Require `pdb_names` for a CDB.
3. Validate Oracle identifiers before substitution. Accept only letters, digits,
   `_`, `$`, and `#`, beginning with a letter. Require an absolute wallet path and
   reject control characters, shell metacharacters, and parent traversal.
4. Create customer-specific copies of the bundled scripts and runbook in the
   task-specific output directory. Never modify the bundled assets.
   For `onprem_rac`, do not render the generic wallet-directory or configuration
   stages until the DBA has replaced single-host directory and SQL*Plus restart
   operations with the site's approved shared-storage and cluster-aware procedure.
5. Present the stages in order: precheck, wallet directory creation, TDE
   configuration, selected tablespace encryption, and verification.
6. Interpret precheck before rendering later stages. If a keystore, wallet files,
   `WALLET_ROOT`, `TDE_CONFIGURATION`, or master keys already exist but the profile
   still reports TDE disabled, stop with `needs-review`; do not present keystore
   creation commands over an existing or partially configured setup.
7. Before presenting a stage that restarts the database or takes a tablespace
   offline, explain the downtime impact and obtain explicit customer confirmation.
8. Pause after each requested stage. Ask the customer to paste only the marked
   evidence section and remind them not to paste passwords, wallet contents, keys,
   or connection strings.
9. Treat `ORA-`, `SP2-`, `LRM-`, or a nonzero shell result as `fail`. Treat a
   closed wallet, missing master key, or an unencrypted selected tablespace as
   `fail` or `needs-review`; script completion alone is not proof.
10. Persist only allowlisted evidence: database version, architecture, container
   names, wallet status/type, keystore mode, key count, selected tablespace names,
   encryption status/algorithm, stage marker, and result marker. Replace other
   values with `[REDACTED]` and never persist raw pasted output.
11. Return `pass`, `fail`, or `needs-review` in `tde_enablement`, including the
    sanitized evidence and remediation guidance. Continue to `validate-tde` only
    after `pass`.

## Secret Rules

- Never request, receive, generate, store, echo, or report a wallet password.
- A wallet password must be entered locally by the customer with hidden input.
- Never place a password in a script, command argument, substitution variable,
  generated artifact, log, report, or chat response.
- Never persist private keys, wallet files, key identifiers, or complete command
  output.

## Result Contract

Return `tde_enablement` with:

- `status`: `pass`, `fail`, or `needs-review`.
- `action`: `none`, `customer-execution-required`, or `dba-review-required`.
- `evidence`: sanitized, allowlisted facts only.
- `findings`: errors, missing proof, and operational warnings.
- `remediation`: the next customer-owned action.
