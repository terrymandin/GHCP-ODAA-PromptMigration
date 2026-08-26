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
| Phase 10 | ZDM readiness and artifact generation | Select the `ZDM Migration` custom agent |

Run `@GetStatus` at any time to see the current migration progress.

## Prerequisites

Before starting, ensure you have:
- GitHub Copilot with Claude Sonnet 4.5+ model
- Azure MCP Server Extension installed in VS Code
- Oracle Developer Extension installed in VS Code
- GitHub Copilot for Azure Extension installed
- VS Code 1.101+, AZ CLI, and Terraform CLI

## Phase 10 Setup

1. Clone this repo and open it in VS Code.
2. Select the `ZDM Migration` custom agent in Copilot Chat.
3. Describe the source database and target environment, then answer the guided questionnaire.
4. Run customer-side discovery, remediation, validation, and ZDM commands only when the agent presents them, returning sanitized output without secrets.
5. The agent stores normalized state and generated outputs under `Artifacts/`.

## Where Are You in the Migration?

Tell me your current situation and I will direct you to the right prompt. Common starting points:

- **Just starting** → Run `@Phase0-ODAA-Readiness` to assess your source databases
- **Assessment complete, need networking** → Run `@Phase5-CIDR-Planning`
- **CIDR defined, need infrastructure code** → Run `@Phase6-IaC` with `#file:Artifacts/Phase5-CIDR/CIDR-Definition.md`
- **Infrastructure deployed, ready to migrate** -> Select the `ZDM Migration` custom agent
- **Already part-way through migration** -> Select the `ZDM Migration` custom agent; it resumes from the canonical profile in `Artifacts/`

## ZDM Workflow Overview

The custom agent selects an explicitly enabled route, runs registered skills in phase order, and stops at failed safety or validation gates. The customer executes all database, operating-system, and Azure commands. A generated eval command means `ready for evaluation`; migration readiness requires observed passing eval evidence.
