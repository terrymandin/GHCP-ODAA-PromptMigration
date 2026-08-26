---
name: Phase 10 ZDM Maintenance
description: "Use when: editing the Phase 10 ZDM agent, route configuration, skills, templates, examples, or contract tests."
applyTo: '.github/agents/zdm-migration.agent.md,.github/config/**,.github/skills/**,.github/templates/**,.github/examples/**,tests/Test-ZdmContracts.ps1,tests/Test-AzureFilesNfsSkill.ps1,tests/fixtures/**'
---
# Phase 10 maintenance rules

- Treat `.github/config/` as the only runtime configuration source. Do not create or consume mirrored questionnaire, pattern, plan, or skill-catalog files elsewhere.
- Treat `.github/config/questionnaire.yaml` as the input contract and `.github/templates/migration-profile.yaml` as the structural profile template.
- Select only a route explicitly enabled by `.github/config/migration-patterns.yaml`; never infer a method or mode from downtime.
- Use only plans and skills registered in `.github/config/execution-plans.yaml` and `.github/config/skill-catalog.yaml`.
- Keep the agent, configuration, skill metadata, templates, examples, and contract tests synchronized when changing a workflow contract.
- Write runtime output under `Artifacts/`; do not overwrite source templates or commit generated customer artifacts.
- Never include passwords, private keys, wallet contents, credentials, tokens, connection strings, subscription or tenant IDs, private IPs, or raw customer output in generated files, reports, examples, or tests.
- Treat customer-pasted output as transient and persist only sanitized, allowlisted evidence.
- Never execute customer database or operating-system mutations.
- Never execute customer Azure mutations. Require explicit approval before presenting Azure resource-creation commands and separate approval before package installation, mounting, or persistent host changes.
- Never overwrite or delete an existing Azure resource, and never enable unrestricted public access for an NFS share.
- Stop and report missing required inputs or failed validation before generating a ZDM response file.
- Keep database listener or SCAN endpoints separate from SSH execution nodes.
- A generated eval command means only `ready for evaluation`; migration readiness requires passing sanitized customer-run ZDM eval evidence.
- Keep `tests/fixtures/` sanitized and environment-independent so contract tests run from a clean clone.
