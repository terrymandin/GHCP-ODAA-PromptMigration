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

<!--
TODO: Determine if Note below is required:

> Note: If your workload have many repositories, consider using the Phase0-Multi-repo-assessment.prompt.md to assess multiple repositories in a single workflow.
> Start by creating a file named `codebase-repos.md` in the root folder, listing all the repositories to assess.
> Then, use the command `/phase0-multirepoassessment` to start the multi-repo assessment process.
>
-->

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

To reduce hallucinations during the migration, the guided prompts use two files in the repository's `reports/` folder:

- `reports/Report-Status.md` — overall migration status dashboard
- `reports/Application-Assessment-Report.md` — application assessment summary

You can update these files at any phase to fit your requirements.

During each phase, read the summary carefully to understand what will be delivered by the model and what inputs are needed.

- Pro tip: for the rewrite migration process, some unnecessary files may be created (Class1.cs); clean them up before your final check-in.
- Pro tip 2: use the @terminal command to ask the agent to solve issues during your tests.
- Pro tip 3: Don't assume anything, always verify with the documentation.

## Repository Structure

- **`.github/`**: Contains custom prompts and chat modes that enable GitHub Copilot to assist with migration
  - **`chatmodes/`**: Defines specialized chat experiences for migration scenarios
  - **`prompts/`**: Structured prompts for each phase of the migration process

- **`Use-cases/`**: Example applications representing different migration scenarios
  - **`01-MultiZoneSilver/`**: Oracle Silver MAA Architecture
  - **`02-MultiRegionGold/`**: Oracle Gold MAA Architecture

## Migration & Modernization Process

The repository implements a structured 10-phase approach to application migration:

### Phase 1: Planning & Assessment

Plan your migration by gathering requirements (hosting platform, IaC preferences, database needs) and generate a comprehensive assessment report analyzing the current application structure, dependencies, architecture, risk analysis, and effort estimation.

### Phase 2: Sizing

Use Oracle AWR or statspack reports to size the Oracle Database@Azure deployment.  
>
> QUESTION: Our [current guidance](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/scenarios/oracle-on-azure/oracle-landing-zone-plan#plan-your-oracle-on-azure-estate) is to consult with Oracle for sizing of Oracle Database@Azure.  Could this be replaced or augmented with AI?

### Phase 3: Obtaining the Oracle Database@Azure Marketplace offering

Work with Oracle to obtain an Oracle Database@Azure marketplace offering.

### Phase 4: CIDR Range Evaluation

Determine the CIDR Ranges to be used by the Oracle Database@Azure deployments

### Phase 5: Infrastructure Generation

Create infrastructure as code (IaC) files (Bicep or Terraform) using [Azure Verified Modules](https://aka.ms/avm) for deploying to Azure, incorporating best practices and security configurations.

### Phase 6: Deployment to Azure

Deploy the validated Oracle Database@Azure architecture to Azure with comprehensive deployment monitoring and validation.

### Phase 7: CI/CD Pipeline Setup

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

1. Clone this repository
2. Install [GitHub Copilot](https://copilot.github.com/) in your Visual Studio Code
3. Open one of the use case projects in VS Code
4. Start a chat with GitHub Copilot using the prompt:  "`/phase1-planandassess` under the folder #file:02-NetFramework30-ASPNET-WEB" to begin the migration planning and assessment
5. Use `/getstatus` at any time to check the current migration status
6. Follow the guided prompts to complete each phase of the migration process

## Use Cases

This repository contains example applications that can be used to test prompts and understand how GitHub Copilot works in the context of migration and modernization:

- **Simple Database**: Migration path for legacy ASP applications

## Improved Prompt Structure

The custom prompts have been significantly enhanced with:

### Enhanced Structured Workflow

- **Planning Phase**: Added a dedicated planning phase to gather requirements before starting the assessment
- **Status Command**: New `/getstatus` command to check migration progress at any time
- **Report Generation**: Automatic creation of assessment, validation, and status reports
- **Incremental Validation**: Step-by-step validation checks throughout the migration process
- **Context Preservation**: Better context retention between phases of the migration

### Technical Improvements

- GitHub Copilot Migration \& Modernization for Azure
  - Overview
  - Requirements
  - Avoiding Hallucinations
  - Repository Structure
  - Migration \& Modernization Process
    - Phase 1: Planning \& Assessment
    - Phase 2: Code Migration
    - Phase 3: Infrastructure Generation
    - Phase 4: Deployment to Azure
    - Phase 5: CI/CD Pipeline Setup
  - Key Features
  - Migration Status Tracking
  - Getting Started
  - Target Azure Hosting Platforms
  - Authentication \& Authorization
  - Use Cases
  - Improved Prompt Structure
    - Enhanced Structured Workflow
    - Technical Improvements
    - Documentation and Reporting
  - Contributing
  - License

### Documentation and Reporting

- **Detailed Reports**: More comprehensive reports with actionable recommendations
- **Visual Progress**: Visual progress tracking with completion percentages
- **Risk Management**: Enhanced risk identification and mitigation guidance
- **Architecture Diagrams**: Support for generating before/after architecture diagrams
- **Performance Metrics**: Added performance baseline recommendations and validation

## Contributing

Contributions to improve the prompts, chat modes, or add new use cases are welcome. Please feel free to submit pull requests or open issues to discuss potential improvements.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.