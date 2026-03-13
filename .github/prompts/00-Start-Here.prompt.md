---
mode: agent
description: Start here - Oracle Database@Azure migration onboarding and navigation guide
---

# Oracle Database@Azure Migration â€” Start Here

You are assisting a database architect with migrating Oracle databases to Oracle Database@Azure (ODAA) running on Azure Exadata infrastructure.

## What This Toolkit Does

This repository provides AI-assisted Copilot prompts for each phase of the Oracle-to-ODAA migration journey. Each prompt guides you through one phase, generates artifacts, and tells you the next step.

| Phase | Purpose | Invoke With |
|-------|---------|-------------|
| Phase 0 | ODAA Readiness Assessment | `@Phase0-ODAA-Readiness` |
| Phase 5 | CIDR Range Planning | `@Phase5-CIDR-Planning` |
| Phase 6 | Infrastructure as Code (Terraform) | `@Phase6-IaC` |
| Phase 10 â€” Step 1 | Test SSH Connectivity (ZDM) | `@Phase10-ZDM-Step1-Test-SSH-Connectivity` |
| Phase 10 â€” Step 2 | Generate Discovery Scripts (ZDM) | `@Phase10-ZDM-Step2-Generate-Discovery-Scripts` |
| Phase 10 â€” Step 3 | Discovery Questionnaire (ZDM) | `@Phase10-ZDM-Step3-Discovery-Questionnaire` |
| Phase 10 â€” Step 4 | Fix Issues (ZDM) | `@Phase10-ZDM-Step4-Fix-Issues` |
| Phase 10 â€” Step 5 | Generate Migration Artifacts (ZDM) | `@Phase10-ZDM-Step5-Generate-Migration-Artifacts` |

Run `@GetStatus` at any time to see the current migration progress.

## Prerequisites

Before starting, ensure you have:
- GitHub Copilot with Claude Sonnet 4.5+ model
- Azure MCP Server Extension installed in VS Code
- GitHub Copilot for Azure Extension installed
- VS Code 1.101+, AZ CLI, and Terraform CLI

## First-Time Setup

1. Copy `zdm-env.example.md` to `zdm-env.md` in the repo root
2. Fill in your environment values (source host, target host, SSH keys, OCI identifiers)
3. `zdm-env.md` is git-ignored â€” your values will never be committed

## Where Are You in the Migration?

Tell me your current situation and I will direct you to the right prompt. Common starting points:

- **Just starting** â†’ Run `@Phase0-ODAA-Readiness` to assess your source databases
- **Assessment complete, need networking** â†’ Run `@Phase5-CIDR-Planning`
- **CIDR defined, need infrastructure code** â†’ Run `@Phase6-IaC` with `#file:Artifacts/Phase5-CIDR/CIDR-Definition.md`
- **Infrastructure deployed, ready to migrate** â†’ Run `@Phase10-ZDM-Step1-Test-SSH-Connectivity` with `#file:zdm-env.md`
- **SSH working, need discovery** â†’ Run `@Phase10-ZDM-Step2-Generate-Discovery-Scripts` with `#file:zdm-env.md`
- **Discovery done, need to plan** â†’ Run `@Phase10-ZDM-Step3-Discovery-Questionnaire` (attach your Step 2 discovery output files)
- **Blockers to fix** â†’ Run `@Phase10-ZDM-Step4-Fix-Issues` (attach Step 3 output files)
- **Ready to migrate** â†’ Run `@Phase10-ZDM-Step5-Generate-Migration-Artifacts` (attach Step 3 and Step 4 output files)

## ZDM Workflow Overview

For Phase 10 (ZDM migration), the workflow alternates between VS Code (prompt generation) and the ZDM server (script execution):

```
VS Code                           ZDM Server
â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€    â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
@ZDM-Step1 â†’ generates scripts â†’ copy to ZDM â†’ run â†’ commit results
@ZDM-Step2 â†’ generates scripts â†’ copy to ZDM â†’ run â†’ commit results
@ZDM-Step3 â†’ analyzes output  â†’ complete questionnaire manually
@ZDM-Step4 â†’ fix scripts      â†’ run on ZDM â†’ iterate until clean
@ZDM-Step5 â†’ generates RSP    â†’ copy to ZDM â†’ run migration
```

See [.github/prompts/Phase10-ZDM-Migration-Guide.md](.github/prompts/Phase10-ZDM-Migration-Guide.md) for the full swimlane diagram and prerequisites.
