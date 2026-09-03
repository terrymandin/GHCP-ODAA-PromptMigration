# Artifacts Directory

This directory is intentionally empty in the repository.

## Purpose

Prompts and custom agents write generated artifacts here. Runtime contents are git-ignored.

## Directory Structure (After Running Prompts)

The `Phase 10 ZDM Migration` custom agent creates files under its dedicated `Phase10/` directory as its registered skills run. Depending on the selected route and progress, the directory can contain:

```
Artifacts/
└── Phase10/
	├── migration-profile.yaml
	├── test-answers.yaml             # Optional local test prefill; never a customer record
	├── zdm-response-file.rsp
	├── zdm-eval-command.sh
	├── network-validation.yaml
	├── ssh-validation.yaml
	├── nfs-validation.yaml
	└── readiness-report.md
```

## Getting Started

1. Clone this repository and open it in VS Code.
2. Run the Phase 10 workflow by selecting the `Phase 10 ZDM Migration` custom agent in Copilot Chat.
3. Start with a representative non-production environment whenever possible, answer the questionnaire, and provide only sanitized customer-run evidence.
4. Review generated artifacts before executing any command.

The current workflow stops after customer-run ZDM `-eval` validation. A passing eval is
not evidence of migration success, cutover readiness, fallback or rollback readiness,
or production readiness. No non-eval migration command is generated.

## Note

Do not commit generated artifacts. Never place passwords, wallet contents, keys, tokens,
connection strings, or raw customer output here. Private IP addresses may appear only
in local Phase 10 operational artifacts when required for migration connectivity; they
must be redacted from evidence and readiness reports and must never be committed.
