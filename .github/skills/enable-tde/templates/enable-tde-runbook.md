# Customer TDE Enablement Runbook

## Scope

- Database: `{{ORACLE_SID}}`
- Architecture: `{{DATABASE_ARCHITECTURE}}`
- PDBs: `{{PDB_NAMES}}`
- Wallet root: `{{WALLET_ROOT}}`
- Selected tablespaces: `{{SELECTED_TABLESPACES}}`

These files are generated for this task from repository templates. Review them with
the responsible Oracle DBA before execution. The customer owns backups, rollback,
change approval, and command execution.

## Safety Rules

- Run SQL files as an authorized DBA using SQL*Plus with SYSDBA privileges.
- Run the shell stage as the Oracle software owner or another approved account.
- Never paste a wallet password, wallet contents, key material, or connection string
  into chat or an artifact.
- Confirm that database and wallet backups satisfy local recovery policy.
- Stop on any `ORA-`, `SP2-`, `LRM-`, shell error, or unexpected environment value.
- For RAC, do not use the generic directory or SQL*Plus restart stages. The Oracle
   DBA must supply approved shared-wallet placement and cluster-aware restart steps.

## Stages

1. Run `01-tde-precheck.sql`. Paste output only from `TDE_STAGE=PRECHECK` through
   `TDE_RESULT=PRECHECK_COMPLETE`.
   Stop before later stages if the precheck finds an existing or partially
   configured keystore; the responsible DBA must review that state.
2. Run `02-create-wallet-directory.sh`. Paste only its `TDE_` result lines.
3. Review and approve the planned database restart. Then run
   `03-configure-tde.sql`. Enter the wallet password only at its hidden local prompt.
4. Review and approve the planned offline interval for every selected tablespace.
   Then run `04-encrypt-tablespaces.sql`.
5. Run `05-tde-verify.sql`. Paste output only from `TDE_STAGE=VERIFY` through
   `TDE_RESULT=VERIFY_COMPLETE`.

The migration workflow resumes only when verification shows an open wallet, at
least one master key for each required container, and encryption for every selected
tablespace. Script completion markers alone do not establish success.
