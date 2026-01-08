# Reusable Terraform Prompt for Oracle Database@Azure (ODAA)

## Quick Start - Using @ Mentions (Recommended)

**In GitHub Copilot Chat**, you can reference this file directly without copy/pasting:

```
@PROMPT_TEMPLATE.md

Deploy to westus2 with Exadata.X11M shape and 4 compute nodes.
```

The `@` symbol lets Copilot read the file content automatically. You can:
- `@PROMPT_TEMPLATE.md` - Reference this entire file
- `@workspace` - Include workspace context
- Combine with your custom requirements

---

## Prompt Template

### Core Prompt

```
Create an Oracle Database@Azure (ODAA) Infrastructure and Cluster instance using Terraform Azure Verified Modules (AVM).

Use ONLY Azure Verified Modules for ALL resources - do not use raw azurerm resources:

ODAA Resources:
- ODAA Infrastructure AVM: https://registry.terraform.io/modules/Azure/avm-res-oracledatabase-cloudexadatainfrastructure/azurerm/latest
- ODAA Cluster AVM: https://registry.terraform.io/modules/Azure/avm-res-oracledatabase-cloudvmcluster/azurerm/latest

Supporting Infrastructure AVMs:
- Resource Group AVM: https://registry.terraform.io/modules/Azure/avm-res-resources-resourcegroup/azurerm/latest
- Virtual Network AVM: https://registry.terraform.io/modules/Azure/avm-res-network-virtualnetwork/azurerm/latest
- Log Analytics Workspace AVM: https://registry.terraform.io/modules/Azure/avm-res-operationalinsights-workspace/azurerm/latest

Iterate with "terraform init", "terraform validate" and "terraform plan" until there are no errors.

Place Terraform in the IaC directory
```

---

## Usage Methods

### Method 1: @ Mention (Best for VS Code Copilot)
Type in Copilot Chat:
```
@PROMPT_TEMPLATE.md

Additional requirements:
- Deploy to eastus region
- Use 32 CPU cores
```

### Method 2: Copy & Paste
1. Copy the "Core Prompt" above
2. Paste into any AI chat
3. Add custom requirements

### Method 3: Reference with Context
```
Using the prompt in @PROMPT_TEMPLATE.md, create ODAA infrastructure with:
- Exadata.X11M shape
- Custom maintenance window for Sundays
- Private endpoints enabled
```

---

## Why Use Azure Verified Modules (AVM) for Everything?

Using AVM modules for all infrastructure components provides several benefits:

1. **Consistency**: All resources follow the same patterns and standards
2. **Best Practices**: AVM modules implement Azure best practices by default
3. **Security**: Built-in support for private endpoints, diagnostics, locks, and RBAC
4. **Maintainability**: Microsoft-maintained with regular updates
5. **Extensibility**: Comprehensive interfaces for role assignments, monitoring, and more
6. **Validation**: Pre-tested and validated configurations

### Available AVM Modules

| Resource | Module Name | Registry URL |
|----------|-------------|--------------|
| **Resource Group** | `avm-res-resources-resourcegroup` | [Link](https://registry.terraform.io/modules/Azure/avm-res-resources-resourcegroup/azurerm/latest) |
| **Virtual Network** | `avm-res-network-virtualnetwork` | [Link](https://registry.terraform.io/modules/Azure/avm-res-network-virtualnetwork/azurerm/latest) |
| **Log Analytics Workspace** | `avm-res-operationalinsights-workspace` | [Link](https://registry.terraform.io/modules/Azure/avm-res-operationalinsights-workspace/azurerm/latest) |
| **ODAA Exadata Infrastructure** | `avm-res-oracledatabase-cloudexadatainfrastructure` | [Link](https://registry.terraform.io/modules/Azure/avm-res-oracledatabase-cloudexadatainfrastructure/azurerm/latest) |
| **ODAA VM Cluster** | `avm-res-oracledatabase-cloudvmcluster` | [Link](https://registry.terraform.io/modules/Azure/avm-res-oracledatabase-cloudvmcluster/azurerm/latest) |

---

## Tips for Getting Better Results

1. **Be Specific About AVM**: Always mention "using Azure Verified Modules for ALL resources"
2. **Specify Regions**: Include target Azure region (e.g., "eastus", "westus2")
3. **Network Details**: Provide VNet CIDR ranges and subnet requirements
4. **ODAA Configuration**: Specify Exadata shape, node counts, CPU cores, memory, storage
5. **License Model**: State if using "BringYourOwnLicense" or "LicenseIncluded"
6. **Advanced Features**: Request specific AVM features:
   - Role assignments: "Add Database Contributor role assignments"
   - Resource locks: "Enable CanNotDelete locks on all resources"
   - Diagnostic settings: "Configure diagnostic logging to Log Analytics"
   - Private endpoints: "Enable private endpoints for secure connectivity"
7. **Validation**: Always end with "Iterate with terraform init, validate, and plan until no errors"
8. **Tags**: Specify tagging requirements for governance and cost management

---

## Example Prompts

### Basic ODAA Deployment
```
@PROMPT_TEMPLATE.md

Create ODAA infrastructure using Azure Verified Modules for ALL resources:
- Deploy to eastus region in availability zone 1
- Use Exadata.X11M shape with 4 compute nodes and 6 storage nodes
- Configure cluster with 32 CPU cores, 120 GB memory, and 4 TB storage
- VNet address space: 172.16.0.0/24
- Backup subnet CIDR: 172.16.1.0/24
- License model: BringYourOwnLicense
- Time zone: America/Los_Angeles
```

### Production-Ready Deployment with Advanced Features
```
@PROMPT_TEMPLATE.md

Create production-grade ODAA infrastructure using Azure Verified Modules for ALL resources:
- Deploy to westus2 region with availability zone redundancy
- Exadata.X11M: 8 compute nodes, 12 storage nodes
- VM Cluster: 64 CPU cores, 240 GB memory, 8 TB storage
- Use Resource Group AVM with CanNotDelete lock
- Use VNet AVM with 10.0.0.0/16 address space
- Configure NSG via AVM module
- Use Log Analytics AVM with 90-day retention
- Enable diagnostic settings on all resources
- Add role assignments for Database team (Database Contributor)
- Configure private endpoints for secure connectivity
- Set up custom maintenance window for Sundays 2-6 AM UTC
- License: BringYourOwnLicense
- Time zone: America/New_York
- Tags: Environment=Production, ManagedBy=Terraform, CostCenter=IT
```

### Development Environment
```
@PROMPT_TEMPLATE.md

Create ODAA development environment using Azure Verified Modules:
- Deploy to eastus2 region
- Exadata.X9M shape (cost-optimized)
- 2 compute nodes, 3 storage nodes
- VM Cluster: 16 CPU cores, 60 GB memory, 2 TB storage
- Simple networking: 192.168.0.0/24
- Use all AVM modules (Resource Group, VNet, Log Analytics, ODAA)
- Enable basic diagnostic logging
- License: BringYourOwnLicense
- Tags: Environment=Development, AutoShutdown=Enabled
```

### Migration Scenario
```
@PROMPT_TEMPLATE.md

Create ODAA infrastructure for Oracle database migration using AVM for everything:
- Target region: centralus (zone 2)
- Exadata.X11M with high capacity: 6 compute, 9 storage nodes
- Large VM Cluster: 48 cores, 180 GB RAM, 6 TB storage
- Isolated VNet: 10.100.0.0/16 with dedicated subnet
- Use Resource Group AVM with resource locks
- Use VNet AVM with NSG and route tables
- Use Log Analytics AVM with 120-day retention for compliance
- Enable all diagnostic settings
- Add role assignments for Migration team and DBA team
- Configure private endpoints
- Set maintenance window to minimize impact
- License: BringYourOwnLicense
- Time zone: America/Chicago
- Tags: Project=OracleMigration, CostCenter=DataEngineering, Compliance=Required
```

---

## What You'll Get

When you use this prompt, the AI will generate:

### 1. Terraform Configuration Files
- `providers.tf` - Provider configurations (azurerm, azapi, random)
- `main.tf` - All resources using AVM modules
- `variables.tf` - Variable definitions with validation
- `outputs.tf` - Output values for resource IDs and configurations
- `terraform.tfvars` - Example values (customize before use)

### 2. Documentation
- `README.md` - Comprehensive deployment guide
- Prerequisites and requirements
- Step-by-step instructions
- Troubleshooting tips

### 3. AVM Module Usage
All infrastructure using Azure Verified Modules:
```hcl
# Resource Group with AVM
module "resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "~> 0.1"
  # ... with locks and RBAC
}

# VNet with AVM
module "virtual_network" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "~> 0.7"
  # ... with subnets, delegation, diagnostics, locks
}

# Log Analytics with AVM
module "log_analytics" {
  source  = "Azure/avm-res-operationalinsights-workspace/azurerm"
  version = "~> 0.4"
  # ... with retention, diagnostics, locks
}

# ODAA Infrastructure with AVM
module "exadata_infrastructure" {
  source  = "Azure/avm-res-oracledatabase-cloudexadatainfrastructure/azurerm"
  version = "0.2.0"
  # ... fully configured
}

# ODAA VM Cluster with AVM
module "vm_cluster" {
  source  = "Azure/avm-res-oracledatabase-cloudvmcluster/azurerm"
  version = "0.2.0"
  # ... fully configured
}
```

---

## Validation Workflow

After generation, the AI will automatically run:

1. `terraform init` - Initialize providers and modules
2. `terraform validate` - Check syntax and configuration
3. `terraform plan` - Preview changes

If errors occur, the AI will:
- Identify the issue
- Fix the configuration
- Re-run validation
- Repeat until successful

---

## Common Customizations

### Change Region
```
Deploy to westus2 instead of eastus
```

### Adjust Resources
```
Change to 6 compute nodes and 8 storage nodes
Increase to 48 CPU cores and 180 GB memory
```

### Modify Network
```
Use VNet address space 10.0.0.0/16
Change Oracle subnet to 10.0.1.0/24
```

### Add Security Features
```
Add Database Contributor role for service principal <ID>
Enable CanNotDelete locks on all production resources
Configure private endpoints for VM Cluster
```

### Change Maintenance Window
```
Set maintenance window to Saturdays 3-7 AM UTC
Disable automatic maintenance
```

---

## Best Practices

1. **Always Use Latest AVM Versions**: Use `~> X.Y` version constraints for supporting infrastructure
2. **Pin ODAA Module Versions**: Use exact versions like `0.2.0` for ODAA modules until stable
3. **Validate Early**: Run terraform plan before deploying
4. **Use Resource Locks**: Enable CanNotDelete locks on production resources
5. **Enable Diagnostics**: Configure diagnostic settings for monitoring and troubleshooting
6. **Tag Everything**: Use consistent tagging for cost management and governance
7. **Secure Credentials**: Never commit SSH keys or secrets to version control
8. **Review Plans**: Always review terraform plan output before applying
9. **Use Remote State**: Configure remote state storage for team collaboration
10. **Document Changes**: Keep README.md updated with any customizations

---

## Troubleshooting

### Common Issues

**Issue**: Module not found
```
Error: Module not installed
```
**Solution**: Run `terraform init` to download modules

**Issue**: Invalid CIDR ranges
```
Error: Invalid CIDR block
```
**Solution**: Ensure VNet and subnet CIDRs don't overlap and are properly sized

**Issue**: Zone not available
```
Error: Availability zone not supported
```
**Solution**: Check Azure region supports specified availability zones for ODAA

**Issue**: Insufficient capacity
```
Error: Shape not available
```
**Solution**: Check Exadata shape availability in target region

---

## Additional Resources

- **Azure Verified Modules**: https://aka.ms/avm
- **AVM Registry**: https://registry.terraform.io/namespaces/Azure
- **ODAA Documentation**: https://learn.microsoft.com/azure/oracle/oracle-db/
- **Terraform AzureRM Provider**: https://registry.terraform.io/providers/hashicorp/azurerm/latest
- **AVM Best Practices**: https://azure.github.io/Azure-Verified-Modules/

---

## Support

For issues or questions:
1. Check the generated README.md for specific guidance
2. Review Terraform plan output for detailed errors
3. Consult Azure Verified Modules documentation
4. Check ODAA module GitHub repositories for known issues

---

**Ready to deploy?** Copy the Core Prompt above, add your specific requirements, and let the AI generate your infrastructure!
