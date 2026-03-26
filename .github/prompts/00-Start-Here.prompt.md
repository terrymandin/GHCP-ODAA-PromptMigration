---
mode: agent
description: Start here - Oracle Database@Azure migration onboarding and navigation guide
---

# Oracle Database@Azure Migration — Start Here

You are assisting a database architect with migrating Oracle databases to Oracle Database@Azure (ODAA) running on Azure Exadata infrastructure.

## What This Toolkit Does

This repository provides AI-assisted Copilot prompts for each phase of the Oracle-to-ODAA migration journey. Each prompt guides you through one phase, generates artifacts, and tells you the next step.

| Phase | Purpose | Invoke With |
|-------|---------|-------------|
| Phase 0 | ODAA Readiness Assessment | `@Phase0-ODAA-Readiness` |
| Phase 5 | CIDR Range Planning | `@Phase5-CIDR-Planning` |
| Phase 6 | Infrastructure as Code (Terraform) | `@Phase6-IaC` |
| Phase 10 | ZDM Migration (guided, all steps) | `@Phase10-ZDM-Orchestrator` |

Run `@GetStatus` at any time to see the current migration progress.

## Prerequisites

Before starting, ensure you have:
- GitHub Copilot with Claude Sonnet 4.5+ model
- Azure MCP Server Extension installed in VS Code
- Oracle Developer Extension installed in VS Code
- GitHub Copilot for Azure Extension installed
- VS Code 1.101+, AZ CLI, and Terraform CLI

## First-Time Setup

1. Copy `zdm-env.example.md` to `zdm-env.md` in the repo root
2. Fill in your environment values (source host, target host, SSH keys, OCI identifiers)
3. `zdm-env.md` is git-ignored — your values will never be committed
4. `zdm-env.md` is for prompt-time generation only; generated scripts/artifacts should not read it at runtime on the jumpbox/ZDM server

## Where Are You in the Migration?

Tell me your current situation and I will direct you to the right prompt. Common starting points:

- **Just starting** → Run `@Phase0-ODAA-Readiness` to assess your source databases
- **Assessment complete, need networking** → Run `@Phase5-CIDR-Planning`
- **CIDR defined, need infrastructure code** → Run `@Phase6-IaC` with `#file:Artifacts/Phase5-CIDR/CIDR-Definition.md`
- **Infrastructure deployed, ready to migrate** → Run `@Phase10-ZDM-Orchestrator` with `#file:zdm-env.md`
- **Already part-way through migration** → Run `@Phase10-ZDM-Orchestrator` with `#file:zdm-env.md` — it will detect your current step automatically

## ZDM Workflow Overview

For Phase 10 (ZDM migration), the workflow alternates between VS Code (prompt generation) and the ZDM server (script execution):

```
VS Code                           ZDM Server
------------------------------    ------------------------------
@ZDM-Step1 -> tests SSH inline  -> writes connectivity report
@ZDM-Step2 -> runs discovery    -> writes discovery reports
@ZDM-Step3 -> analyzes output   -> complete questionnaire manually
@ZDM-Step4 -> fix scripts       -> run on ZDM -> iterate until clean
@ZDM-Step5 -> generates RSP     -> copy to ZDM -> run migration
```

See [.github/prompts/Phase10-ZDM-Migration-Guide.md](.github/prompts/Phase10-ZDM-Migration-Guide.md) for the full swimlane diagram and prerequisites.
