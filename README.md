# GitHub Oracle Database@Azure Copilot Migration & Modernization

This repository showcases how GitHub Copilot using custom prompts and chat mode can be leveraged to migrate Oracle databases to Oracle Database@Azure in Azure. The current focus is on Oracle Exadata, demonstrating end-to-end migration journeys. 

## Overview

The GitHub Copilot Migration & Modernization for Oracle Database@Azure provides a structured approach to:

1. Size Oracle Database@Azure using AWR reports
1. Assign CIDR Ranges
1. Generate Infrastructure as Code (IaC)
1. Determine the appropriate migration tool
1. Configure the migration tool

Through a guided, AI-assisted workflow, architects can efficiently migrate on-premise databases into a managed Oracle Database@Azure Exadata instance.

## Phase Completion Status

| Phase | Name | Status |
|-------|------|--------|
| Phase 1 | Planning & Assessment | ✅ Complete |
| Phase 2 | Sizing | Planned |
| Phase 3 | Obtaining the Marketplace Offering | Planned |
| Phase 4 | Architecture Validation | Planned |
| Phase 5 | CIDR Range Evaluation | ✅ Complete |
| Phase 6 | Infrastructure Generation | ✅ Complete |
| Phase 7 | Deployment to Azure | Planned |
| Phase 8 | CI/CD Pipeline Setup | Planned |
| Phase 9 | Determine Migration Tool | Planned |
| Phase 10 | Migrate Databases to Azure (ZDM) | ✅ Complete |

## Requirements

- GitHub Copilot License
- Model Claude Sonnet 4.5+ (Included in GitHub Copilot)
- Azure MCP Server Extension
- GitHub Copilot for Azure Extension
- GitHub Copilot Extension 1.35+
- GitHub Copilot Chat Extension 0.30+
- Visual Studio code 1.101+
- AZ CLI
- Terraform CLI

## Avoiding Hallucinations

To reduce hallucinations during the migration, use `@GetStatus` to maintain a `reports/Report-Status.md` file that tracks the current state of your migration. Prompts read from and write to this file to preserve context between sessions.

During each phase, read the AI's response summary carefully to understand what will be delivered and what inputs are needed.

- **Phase 10 workflow**: Run the `Phase 10 ZDM Migration` custom agent. Start with a representative non-production environment whenever possible. It collects normalized inputs, selects a supported route, and invokes registered skills in phase order.
- **Pro tip**: Phase 10 runtime state and generated files are written under `Artifacts/Phase10/` and are not committed.
- **Pro tip**: Use `@GetStatus` at the start of each session to re-establish context.
- **Pro tip**: Don't assume anything — always verify ZDM requirements and OCI identifiers with the documentation.

## Repository Structure

- **`.github/prompts/`**: Copilot prompt files for supported migration phases — invoke with `@PromptName` in Copilot Chat. Phase 10 uses a custom agent instead.
  - `00-Start-Here.prompt.md` — onboarding guide and navigation
  - `GetStatus.prompt.md` — check current migration progress
  - `Phase0-ODAA-Readiness.prompt.md` — readiness assessment
  - `Phase5-CIDR-Planning.prompt.md` — CIDR range planning
  - `Phase6-IaC.prompt.md` — Terraform infrastructure generation
- **`.github/agents/`**: Custom-agent entry points
  - `zdm-migration.agent.md` - `Phase 10 ZDM Migration` workflow entry point and coordinator
- **`.github/config/`**: Phase 10 questionnaire, supported routes, execution plans, skill catalog, and provenance
- **`.github/skills/`**: Composable validation, remediation, generation, and review skills
- **`Artifacts/`**: Generated runtime state and output by phase (git-ignored content); Phase 10 uses `Artifacts/Phase10/`

## Migration & Modernization Process

The repository implements a structured 10-phase approach to application migration:

### Phase 1: Planning & Assessment ✅

Plan your migration by gathering requirements (hosting platform, IaC preferences, database needs) and generate a comprehensive assessment report analyzing the current application structure, dependencies, architecture, risk analysis, and effort estimation.

>
> VBD: [Architecture Design and Review Session for Migrating Oracle Workloads to Oracle Exadata Database@Azure](https://eng.ms/docs/microsoft-customer-partner-solutions-mcaps/customer-experience-and-support/asd-management/og-management/ppe-resource-center-repos/azure-engagement-resource-center/sp01/oracle/adr/deliveryguide_exadata_v2)

>QUESTIONNAIRE: [Questionnaire Exadata Migration.xlsx](https://microsoft.sharepoint.com/:x:/r/teams/ASDIPRelease/IP%20Release/Secure%20Infrastructure/VBD/Migrating%20Oracle%20Workloads%20to%20Azure/Architecture%20Design%20and%20Review%20Session%20for%20Migrating%20Oracle%20Workloads%20to%20Azure/OracleDB@Azure/Questionnaire%20Exadata%20Migration.xlsx?d=wc882448f3dcc4217aa6d73298c267117&csf=1&web=1&e=msZa93)

### Phase 2: Sizing *(Planned)*

Use Oracle AWR or statspack reports to size the Oracle Database@Azure deployment.  
>
> QUESTION: Our [current guidance](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/scenarios/oracle-on-azure/oracle-landing-zone-plan#plan-your-oracle-on-azure-estate) is to consult with Oracle for sizing of Oracle Database@Azure.  Could this be replaced or augmented with AI?

### Phase 3: Obtaining the Oracle Database@Azure Marketplace offering *(Planned)*

Work with Oracle to obtain an Oracle Database@Azure marketplace offering.

### Phase 4: Architecture Validation *(Planned)*

Before generating IaC, the architecture is validated against [Cloud Adoption Framework](https://aka.ms/caf) best practices, Oracle Database@Azure networking requirements, security and compliance requirements, high availability and disaster recovery configurations, and Azure Policy compliance and governance standards.

### Phase 5: CIDR Range Evaluation ✅

Determine the CIDR Ranges to be used by the Oracle Database@Azure deployments

### Phase 6: Infrastructure Generation ✅

Create infrastructure as code (IaC) files (Bicep or Terraform) using [Azure Verified Modules](https://aka.ms/avm) for deploying to Azure, incorporating best practices and security configurations.

### Phase 7: Deployment to Azure *(Planned)*

Deploy the validated Oracle Database@Azure architecture to Azure with comprehensive deployment monitoring and validation.

### Phase 8: CI/CD Pipeline Setup *(Planned)*

Configure automated deployment pipelines for continuous integration and delivery, with environment-specific configurations and security gates.

### Phase 9: Determine the best tool to migrate on-prem databases to Azure *(Planned)*

Determine the best tool for migrating databases to Azure such as Zero Migration Downtime (ZDM), Oracle Data Guard, Oracle Recovery Manager (RMAN), Oracle Data Pump, and Oracle GoldenGate.

### Phase 10: Migrate databases from on-premise to Azure ✅

Run the `Phase 10 ZDM Migration` custom agent to execute the Phase 10 workflow, preferably against a representative non-production environment first. It assesses readiness for customer-run ZDM `-eval` and writes artifacts under `Artifacts/Phase10/`. The currently enabled route is Oracle IaaS to ODAA using ZDM 26.1 offline physical migration; unverified routes remain disabled.

## Key Features

- **Comprehensive Assessment**: Analyze existing on-premise Exadata deployments
- **Infrastructure as Code**: Generate Azure Verified Module Terraform files for Azure resources
- **CI/CD Integration**: Set up GitHub Actions or Azure DevOps pipelines for automated deployment
- **Structured Migration Planning**: Guided approach to planning migration with targeted questions and requirements gathering
- **Deployment Monitoring**: Real-time validation and monitoring during application deployment
- **Incremental Validation**: Step-by-step validation throughout the migration process

## Migration Status Tracking

The project now includes comprehensive migration status tracking through the `/getstatus` command:

- **Progress Monitoring**: Track overall migration progress with completion percentages and phase status
- **Quality Metrics**: View quality scores for each completed phase
- **Timeline Tracking**: Timestamps for completed phases to monitor project timeline
- **Risk Management**: Identification and tracking of potential issues with severity levels
- **Next Steps Guidance**: Clear recommendations for the next steps in the migration process
- **Resource Links**: Quick access to relevant documentation and resources
- **Executive Summary**: At-a-glance view of key migration metrics and status

Status reports are stored in the `reports/Report-Status.md` file, providing a central location for tracking migration progress across all phases.

## Getting Started

1. Clone this repository and open it in VS Code
2. Install [GitHub Copilot](https://copilot.github.com/) with Claude Sonnet 4.5+ model
3. Install the **Azure MCP Server**, **GitHub Copilot for Azure** and **Oracle Developer** extensions
4. Open GitHub Copilot Chat and type `@00-Start-Here` for phase navigation
5. To run Phase 10, select the `Phase 10 ZDM Migration` custom agent and submit its sample question or describe the source and target
6. Use `@GetStatus` at any time to check the current migration progress

## Phase 10 ZDM Migration Quick Reference

The `Phase 10 ZDM Migration` custom agent runs the registered execution plan and pauses whenever customer-run evidence or approval is required:

| Phase | Purpose |
|-------|---------|
| Questionnaire and routing | Normalize inputs and select an explicitly supported route |
| Discovery and remediation | Present safe customer-run checks and gated remediation |
| Validation | Require observed SSH, network, database, target, and NFS evidence as applicable |
| Generation | Produce the ZDM response file and eval command only after all gates pass |
| Evaluation and review | Parse sanitized customer-run eval evidence and report readiness |

This release stops after observed customer-run `-eval` validation. A passing eval does
not prove migration success, cutover readiness, fallback or rollback readiness, or
production readiness. It does not generate non-eval migration or cutover commands.

## Contributing

Contributions to improve the prompts, chat modes, or add new use cases are welcome. Please feel free to submit pull requests or open issues to discuss potential improvements.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.