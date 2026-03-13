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

- **Pro tip**: Use `#file:zdm-env.md` to automatically attach your environment config to ZDM prompts.
- **Pro tip**: Use `@GetStatus` at the start of each session to re-establish context.
- **Pro tip**: Don't assume anything â€” always verify ZDM requirements and OCI identifiers with the documentation.

## Repository Structure

- **`.github/prompts/`**: Copilot prompt files for each migration phase â€” invoke with `@PromptName` in Copilot Chat
  - `00-Start-Here.prompt.md` â€” onboarding guide and navigation
  - `GetStatus.prompt.md` â€” check current migration progress
  - `Phase0-ODAA-Readiness.prompt.md` â€” readiness assessment
  - `Phase5-CIDR-Planning.prompt.md` â€” CIDR range planning
  - `Phase6-IaC.prompt.md` â€” Terraform infrastructure generation
  - `ZDM-Step1` through `ZDM-Step5` â€” ZDM migration workflow
  - `Phase10-ZDM-Migration-Guide.md` â€” ZDM reference documentation

- **`Artifacts/`**: Generated output from running prompts (git-ignored content)

- **`zdm-env.example.md`**: Template for ZDM environment configuration â€” copy to `zdm-env.md` and fill in your values

## Migration & Modernization Process

The repository implements a structured 10-phase approach to application migration:

### Phase 1: Planning & Assessment

Plan your migration by gathering requirements (hosting platform, IaC preferences, database needs) and generate a comprehensive assessment report analyzing the current application structure, dependencies, architecture, risk analysis, and effort estimation.

>
> VBD: [Architecture Design and Review Session for Migrating Oracle Workloads to Oracle Exadata Database@Azure](https://eng.ms/docs/microsoft-customer-partner-solutions-mcaps/customer-experience-and-support/asd-management/og-management/ppe-resource-center-repos/azure-engagement-resource-center/sp01/oracle/adr/deliveryguide_exadata_v2)

>QUESTIONNAIRE: [Questionnaire Exadata Migration.xlsx](https://microsoft.sharepoint.com/:x:/r/teams/ASDIPRelease/IP%20Release/Secure%20Infrastructure/VBD/Migrating%20Oracle%20Workloads%20to%20Azure/Architecture%20Design%20and%20Review%20Session%20for%20Migrating%20Oracle%20Workloads%20to%20Azure/OracleDB@Azure/Questionnaire%20Exadata%20Migration.xlsx?d=wc882448f3dcc4217aa6d73298c267117&csf=1&web=1&e=msZa93)

### Phase 2: Sizing

Use Oracle AWR or statspack reports to size the Oracle Database@Azure deployment.  
>
> QUESTION: Our [current guidance](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/scenarios/oracle-on-azure/oracle-landing-zone-plan#plan-your-oracle-on-azure-estate) is to consult with Oracle for sizing of Oracle Database@Azure.  Could this be replaced or augmented with AI?

### Phase 3: Obtaining the Oracle Database@Azure Marketplace offering

Work with Oracle to obtain an Oracle Database@Azure marketplace offering.

### Phase 4: Architecture Validation

Before generating IaC, the architecture is validated against [Cloud Adoption Framework](https://aka.ms/caf) best practices, Oracle Database@Azure networking requirements, security and compliance requirements, high availability and disaster recovery configurations, and Azure Policy compliance and governance standards.

### Phase 5: CIDR Range Evaluation

Determine the CIDR Ranges to be used by the Oracle Database@Azure deployments

### Phase 6: Infrastructure Generation

Create infrastructure as code (IaC) files (Bicep or Terraform) using [Azure Verified Modules](https://aka.ms/avm) for deploying to Azure, incorporating best practices and security configurations.

### Phase 7: Deployment to Azure

Deploy the validated Oracle Database@Azure architecture to Azure with comprehensive deployment monitoring and validation.

### Phase 8: CI/CD Pipeline Setup

Configure automated deployment pipelines for continuous integration and delivery, with environment-specific configurations and security gates.

### Phase 9: Determine the best tool to migrate on-prem databases to Azure

Determine the best tool for migrating databases to Azure such as Zero Migration Downtime (ZDM), Oracle Data Guard, Oracle Recovery Manager (RMAN), Oracle Data Pump, and Oracle GoldenGate. 

### Phase 10: Migrate databases from on-premise to Azure

Use the migration tool to migrate to Azure.

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
3. Install the **Azure MCP Server** and **GitHub Copilot for Azure** extensions
4. Copy `zdm-env.example.md` â†’ `zdm-env.md` and fill in your environment values
5. Open GitHub Copilot Chat and type `@00-Start-Here` to begin
6. Use `@GetStatus` at any time to check the current migration progress

## ZDM Migration Quick Reference

The Phase 10 ZDM migration uses a 5-step workflow that alternates between VS Code (generating scripts) and the ZDM server (running them):

| Step | Run In | Purpose |
|------|--------|---------|
| `@Phase10-ZDM-Step1-Test-SSH-Connectivity` | VS Code | Generate SSH precheck script |
| `@Phase10-ZDM-Step2-Generate-Discovery-Scripts` | VS Code | Generate database discovery scripts |
| Run discovery scripts | ZDM Server | Collect source/target/ZDM facts |
| `@Phase10-ZDM-Step3-Discovery-Questionnaire` | VS Code | Analyze results, create migration plan |
| `@Phase10-ZDM-Step4-Fix-Issues` | VS Code + ZDM | Resolve blockers iteratively |
| `@Phase10-ZDM-Step5-Generate-Migration-Artifacts` | VS Code | Generate RSP, runbook, and migration commands |

## Contributing

Contributions to improve the prompts, chat modes, or add new use cases are welcome. Please feel free to submit pull requests or open issues to discuss potential improvements.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.