# Rule Validation Golden Fixtures

This directory contains golden fixtures for deterministic validation of:

- `.github/requirements/Phase10/Rules/26.1/zdm-26.1-rules.yaml`
- `.github/requirements/Phase10/Rules/zdm-errors.yaml`

## Purpose

Use these fixtures to regression-check rule behavior after any update to:

- rule catalog content,
- error mapping content,
- Step5 to Step7 prompt logic that interprets rules.

## Fixture format

Each fixture file is a JSON document with:

- `case_id`: stable identifier
- `migration_method`: `ONLINE_PHYSICAL` or `OFFLINE_PHYSICAL`
- `input`: normalized facts used for rule evaluation
- `expected.rule_status`: expected result by rule id (`PASS`, `FAIL`, `WARN`)
- `expected.error_mappings`: expected `ERR-*` mappings for failed rules

## Execution model

No runtime script is required in this repository. Fixtures are intended for:

1. manual validation during prompt updates, and
2. future automation (a rule-evaluator script can consume these JSON files directly).

## Current coverage

The `26.1` fixture set covers the initial high-impact rules (`RULE-001` to `RULE-010`) and key warning behavior (`RULE-011` to `RULE-015`) across four cases.
