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
| New Session | Restore context in a new VS Code window | `@NewSession` |
| Phase 0 | ODAA Readiness Assessment | `@Phase0-ODAA-Readiness` |
| Phase 5 | CIDR Range Planning | `@Phase5-CIDR-Planning` |
| Phase 6 | Infrastructure as Code (Terraform) | `@Phase6-IaC` |
| Phase 10 — Step 1 | Test SSH Connectivity (ZDM) | `@Phase10-ZDM-Step1-Test-SSH-Connectivity` |
| Phase 10 — Step 2 | Generate Discovery Scripts (ZDM) | `@Phase10-ZDM-Step2-Generate-Discovery-Scripts` |
| Phase 10 — Step 3 | Discovery Questionnaire (ZDM) | `@Phase10-ZDM-Step3-Discovery-Questionnaire` |
| Phase 10 — Step 4 | Fix Issues (ZDM) | `@Phase10-ZDM-Step4-Fix-Issues` |
| Phase 10 — Step 5 | Generate Migration Artifacts (ZDM) | `@Phase10-ZDM-Step5-Generate-Migration-Artifacts` |

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
3. `zdm-env.md` is git-ignored — your values will never be committed

## New VS Code Session or Remote SSH?

> **Note**: GitHub Copilot chat history is stored per VS Code instance and is **not shared** across windows.
> If you just opened this repo in a new VS Code window (e.g., via Remote SSH to a jumpbox), run `@GetStatus` first
> to restore migration context from `reports/Report-Status.md`.

## Where Are You in the Migration?

Tell me your current situation and I will direct you to the right prompt. Common starting points:

- **New session / different VS Code window** → Run `@NewSession` to restore context from the status file
- **Just starting** → Run `@Phase0-ODAA-Readiness` to assess your source databases
- **Assessment complete, need networking** → Run `@Phase5-CIDR-Planning`
- **CIDR defined, need infrastructure code** → Run `@Phase6-IaC` with `#file:Artifacts/Phase5-CIDR/CIDR-Definition.md`
- **Infrastructure deployed, ready to migrate** → Run `@Phase10-ZDM-Step1-Test-SSH-Connectivity` with `#file:zdm-env.md`
- **SSH working, need discovery** → Run `@Phase10-ZDM-Step2-Generate-Discovery-Scripts` with `#file:zdm-env.md`
- **Discovery done, need to plan** → Run `@Phase10-ZDM-Step3-Discovery-Questionnaire` (attach your Step 2 discovery output files)
- **Blockers to fix** → Run `@Phase10-ZDM-Step4-Fix-Issues` (attach Step 3 output files)
- **Ready to migrate** → Run `@Phase10-ZDM-Step5-Generate-Migration-Artifacts` (attach Step 3 and Step 4 output files)

## ZDM Workflow Overview

For Phase 10 (ZDM migration), the workflow alternates between VS Code (prompt generation) and the ZDM server (script execution):

```
VS Code                           ZDM Server
â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€    â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
@ZDM-Step1 → generates scripts → copy to ZDM → run → commit results
@ZDM-Step2 → generates scripts → copy to ZDM → run → commit results
@ZDM-Step3 → analyzes output  → complete questionnaire manually
@ZDM-Step4 → fix scripts      → run on ZDM → iterate until clean
@ZDM-Step5 → generates RSP    → copy to ZDM → run migration
```

See [.github/prompts/Phase10-ZDM-Migration-Guide.md](.github/prompts/Phase10-ZDM-Migration-Guide.md) for the full swimlane diagram and prerequisites.
