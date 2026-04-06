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

1. Clone this repo locally and open it in VS Code
2. Run `@Phase10-Step1-Setup-Remote-SSH` (in a **local** VS Code session) — it will check the Remote-SSH extension, configure `~/.ssh/config`, test SSH connectivity, and write `Artifacts/Phase10-Migration/Step1/remote-ssh-setup-report.md`
3. Connect VS Code to the ZDM jumpbox via the **Remote-SSH** extension (as `zdmuser`) and re-open the repo
4. Run `@Phase10-Step2-Configure-SSH-Connectivity` — it will interactively collect source host, target host, SSH users, SSH key paths, and application user names, then test connectivity and write `Artifacts/Phase10-Migration/Step2/ssh-config.md`
5. Run `@Phase10-Step3-Generate-Discovery-Scripts` — it will interactively collect Oracle home paths, SIDs, unique names, and ZDM home, then run discovery and write `Artifacts/Phase10-Migration/Step3/db-config.md`
6. To speed up re-runs or testing, pre-populate either config artifact file and the interactive collection phase will be skipped automatically

## Where Are You in the Migration?

Tell me your current situation and I will direct you to the right prompt. Common starting points:

- **Just starting** → Run `@Phase0-ODAA-Readiness` to assess your source databases
- **Assessment complete, need networking** → Run `@Phase5-CIDR-Planning`
- **CIDR defined, need infrastructure code** → Run `@Phase6-IaC` with `#file:Artifacts/Phase5-CIDR/CIDR-Definition.md`
- **Infrastructure deployed, ready to migrate** → Run `@Phase10-ZDM-Orchestrator`
- **Already part-way through migration** → Run `@Phase10-ZDM-Orchestrator` — it will detect your current step automatically

## ZDM Workflow Overview

For Phase 10 (ZDM migration), the workflow alternates between VS Code (prompt generation) and the ZDM server (script execution):

```
Local VS Code                     ZDM Jumpbox (Remote-SSH)
------------------------------    ------------------------------
@ZDM-Step1 -> SSH setup (local)  -> writes remote-ssh-setup-report
@ZDM-Step2 -> tests SSH inline   -> writes connectivity report
@ZDM-Step3 -> runs discovery     -> writes discovery reports
@ZDM-Step4 -> analyzes output    -> complete questionnaire manually
@ZDM-Step5 -> fix scripts        -> run on ZDM -> iterate until clean
@ZDM-Step6 -> generates RSP      -> copy to ZDM -> run migration
```

See [.github/prompts/Phase10-ZDM-Migration-Guide.md](.github/prompts/Phase10-ZDM-Migration-Guide.md) for the full swimlane diagram and prerequisites.
