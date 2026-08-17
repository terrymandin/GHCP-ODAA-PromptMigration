# Step7 System Requirements - Migration Artifact Implementation

## Scope

This file defines implementation-level constraints for generated Step7 runtime artifacts.

## S7-06: Runtime portability constraints

1. Generated artifacts must not require `zdm-env.md` at runtime.
2. Document admin login flow (`ZDM_ADMIN_USER` then `sudo su - zdmuser`).

## S7-07: Environment variable model

1. Use environment variables for OCI identifiers and sensitive values.
2. Generated RSP and command artifacts must reference env vars and include validation guidance.

## S7-08: Version readiness gate

1. Include ZDM latest-stable verification as a pre-migration gate.
2. If ZDM version is outdated/undetermined, include a mandatory upgrade verification phase before migration execution.

## S7-09: RSP generated items

`zdm_migrate.rsp` should include:

1. Complete migration parameter set aligned to questionnaire decisions.
2. Environment-variable based references for sensitive and tenant-specific values.
3. Settings conditioned by migration type (online/offline) and discovered posture.

## S7-10: Command script generated items

`zdm_commands.sh` should include:

1. Ordered command flow for precheck/evaluation/migration/monitoring.
2. Guardrails and prerequisites checks before destructive phases.
3. Clear placeholders or env var references for required runtime values.
4. A standalone sample `zdmcli migrate database` call that can be executed directly (outside the wrapper script) for troubleshooting or manual execution.
5. When Step6 flagged the PATCH_CHECK gate as WARNING (target RU > source RU with individually-named source patches), include `-ignore PATCH_CHECK` in both the `zdmcli migrate database -eval` and `zdmcli migrate database` commands. Precede each command with a comment block that explains: (a) why the flag is present, (b) that the source one-off patches are subsumed by the higher target Release Update and are not individually required, and (c) that this is the expected and documented approach when the target is at a higher RU than the source. This prevents operators from needing to diagnose repeated PRGT-1017 eval failures before discovering the flag.

## S7-11: -sourcenode value must be the source database host

1. The `-sourcenode` parameter in `zdmcli migrate database` must always be set to `$SOURCE_HOST` (the source database hostname captured in `ssh-config.md`).
2. Never set `-sourcenode` to the ZDM jumpbox hostname. ZDM's `-sourcenode` identifies the host running the source Oracle instance, not the host running ZDM. Using the ZDM host causes PRGZ-3928 because ZDM cannot find the source instance there.
3. Add an inline comment in `zdm_commands.sh` adjacent to `-sourcenode` that states: `# -sourcenode must be the source DB host, not the ZDM jumpbox host`.

## S7-12: -sourcesid vs -sourcedb selection based on SOURCE_GI_TYPE

1. Read `SOURCE_GI_TYPE` from `Artifacts/Phase10-Migration/Step7/db-config.md` (set by Step5 source discovery).
2. If `SOURCE_GI_TYPE=grid`: use `-sourcedb $SOURCE_DATABASE_UNIQUE_NAME` in `zdmcli migrate database`. This is required when the source database is registered with Grid Infrastructure/srvctl.
3. If `SOURCE_GI_TYPE=standalone` or blank: use `-sourcesid $SOURCE_ORACLE_SID` in `zdmcli migrate database`.
4. Using the wrong flag for the source configuration causes PRGZ-3928. Add an inline comment in `zdm_commands.sh` that documents which flag was chosen and why.

## S7-13: RSP parameter name validation against ZDM 26.1

1. All RSP parameter names written to `zdm_migrate.rsp` must match the names published in the ZDM 26.1 documentation and the Layer 0 table in the loaded prerequisite catalog (`.github/requirements/Phase10/ZDM-Prerequisites/<version>/<method>.md`).
2. Do not use pre-26.x parameter names or aliases. Legacy parameter names are silently ignored by ZDM 26.1, causing PRGZ-3127 (unrecognized or ignored parameter) without error messages that identify the cause.
3. Before finalizing `zdm_migrate.rsp`, cross-check each parameter name against the Layer 0 RSP mappings in the loaded catalog file. Flag any parameter not found in the catalog as `[UNVERIFIED — confirm against ZDM 26.1 docs]` in a comment above the parameter.
4. Known parameter name changes to enforce:
   - Use `TGT_REDODG` (not any legacy disk group alias).
   - Use `TGT_RECODG` (not any legacy recovery disk group alias).
   - Use `PLATFORM_TYPE` values `EXACS`, `EXACC`, `VMDB`, `NON_CLOUD` exactly as documented.

## S7-14: Auto-include -tdekeystorepasswd when wallet type is PASSWORD

1. Read the TDE wallet type from Step5 discovery evidence (the `WALLET_TYPE` column from `v$encryption_wallet`).
2. If `WALLET_TYPE=PASSWORD` on the source database: add `-tdekeystorepasswd` to the `zdmcli migrate database` (and `-eval`) command with a placeholder for the wallet password (e.g., `$TDE_KEYSTORE_PASSWORD`). Do not embed the password literally.
3. If `WALLET_TYPE=AUTOLOGIN`: omit `-tdekeystorepasswd`.
4. Omitting `-tdekeystorepasswd` when the wallet type is PASSWORD causes PRGZ-3111 (keystore password required). Add an inline comment in `zdm_commands.sh` that states which wallet type was detected and why the flag is or is not present.

## S7-15: DB_NAME_CHECK ignore for ODAA when DB names differ

1. Compare source `DB_NAME` (from Step5 source discovery, `SELECT name FROM v$database`) against target `DB_NAME` (from Step5 target discovery).
2. If `PLATFORM_TYPE` is `EXACS` or `EXACC` AND source `DB_NAME` ≠ target `DB_NAME`: add `-ignore DB_NAME_CHECK` to both the `zdmcli migrate database -eval` and `zdmcli migrate database` commands.
3. Precede the command with a comment block explaining: (a) that ODAA/ExaCS targets are sometimes provisioned with a DB_NAME that differs from the source (e.g., different case or provisioning default), (b) that this flag suppresses the DB_NAME equality check, (c) that the operator must confirm the DB_NAME difference is intentional before proceeding.
4. Do not add `-ignore DB_NAME_CHECK` when `PLATFORM_TYPE=VMDB` or when DB names already match — it is not needed and may mask a real provisioning error.

## S7-16: TGT_SSH_TUNNEL_PORT — omit when direct SQL*Net connectivity works

1. Before including `TGT_SSH_TUNNEL_PORT` in `zdm_migrate.rsp`, verify whether Layer 1 infrastructure checks confirmed that direct SQL*Net connectivity from source to target SCAN port 1521 succeeded (check `nc -zv $TARGET_SCAN_ADDR 1521` result from Step5/Step7 discovery or Layer 1 check output).
2. If direct SQL*Net connectivity was confirmed: do NOT include `TGT_SSH_TUNNEL_PORT` in the RSP. Adding this parameter when direct connectivity works causes `localhost:<port>` precheck failures because ZDM routes traffic through a local tunnel that was never established.
3. If direct SQL*Net connectivity failed and an SSH tunnel was set up: include `TGT_SSH_TUNNEL_PORT` with the configured local port.
4. Add an inline comment in `zdm_migrate.rsp` adjacent to where `TGT_SSH_TUNNEL_PORT` would appear, documenting the decision (present or absent) and the connectivity check result that drove it.

## S7-17: Rule-validation gate before artifact finalization

1. Before finalizing Step7 artifacts, load and evaluate `.github/requirements/Phase10/Rules/<version>/zdm-<version>-rules.yaml` (fallback version `26.1`).
2. Write `Artifacts/Phase10-Migration/Step7/Rule-Validation-Report.md` containing:
   - catalog version and migration method,
   - evaluated rule ids and pass/fail/warn status,
   - blocking failures with remediation references,
   - warning-only findings.
3. If any BLOCKER rule fails, stop before finalizing `zdm_migrate.rsp` and `zdm_commands.sh`.

## S7-18: Deterministic eval-failure mapping

1. During `zdm -eval` retries, map known PRGZ/PRGT/PRCG failures using `.github/requirements/Phase10/Rules/zdm-errors.yaml`.
2. For mapped failures, use the mapped remediation text and include the `ERR-*` id in `Issue-Resolution-Log.md`.
3. For unmapped failures, log `UNMAPPED_ERROR` and include a requirement to update `zdm-errors.yaml` in the next requirements iteration.
