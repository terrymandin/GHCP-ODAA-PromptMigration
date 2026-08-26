# Artifacts Directory

This directory is intentionally empty in the repository.

## Purpose

Prompts and custom agents write generated artifacts here. Runtime contents are git-ignored.

## Directory Structure (After Running Prompts)

The Phase 10 custom agent creates files as its registered skills run. Depending on the selected route and progress, the directory can contain:

```
Artifacts/
├── migration-profile.yaml
├── test-answers.yaml                 # Optional local test prefill; never a customer record
├── zdm-response-file.rsp
├── zdm-eval-command.sh
├── network-validation.yaml
├── ssh-validation.yaml
├── nfs-validation.yaml
└── readiness-report.md
```

## Getting Started

1. Clone this repository and open it in VS Code.
2. Select the `ZDM Migration` custom agent in Copilot Chat.
3. Answer its questionnaire and provide only sanitized customer-run evidence.
4. Review generated artifacts before executing any command.

## Note

Do not commit generated artifacts. Never place passwords, wallet contents, keys, tokens, connection strings, private IPs, or raw customer output here.
