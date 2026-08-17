# Phase10 Rule and Error Catalogs

This directory contains deterministic migration intelligence for Phase10:

- Versioned rule catalogs (`<version>/zdm-<version>-rules.yaml`)
- Error knowledgebase mappings (`zdm-errors.yaml`)

## Operating model

1. Prompts orchestrate data collection and artifact generation.
2. Rule catalogs define pass/fail validation behavior.
3. Error catalogs define deterministic remediation mapping.
4. New recurring failures are added here as requirements updates.

## Version fallback

When a discovered ZDM version has no matching rule directory, use `26.1` and log a warning.

## Change control

When adding or modifying rules:

1. Add or update a unique `id`.
2. Mark `severity` as `BLOCKER` or `WARNING`.
3. Include `applies_to` migration methods.
4. Provide deterministic `condition` text and a `remediation_ref`.
5. Update prompts by regenerating from requirements after catalog updates.

## Golden fixtures

A small regression fixture set is available at:

- `.github/requirements/Phase10/Rules/fixtures/README.md`
- `.github/requirements/Phase10/Rules/fixtures/26.1/`

Use these cases during prompt and catalog updates to confirm deterministic behavior for high-frequency rules and error mappings.