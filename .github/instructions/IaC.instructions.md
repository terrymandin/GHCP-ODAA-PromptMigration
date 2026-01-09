---
applyTo: '**'
---
## Creating Infrastructure Using Azure Verified Modules (AVM)

When creating infrastructure on Azure using Terraform or Bicep, leverage Azure Verified Modules (AVM) from the Terraform Registry or Bicep Registry. These modules follow Microsoft best practices and are officially maintained.

### Azure Verified Modules Best Practices

1. **Fetch AVM Guidance First**: Before creating any infrastructure code using Azure Verified Modules, use `fetch_webpage` to retrieve the official Terraform AVM guidance for LLMs:
   - **Primary Source**: `https://azure.github.io/Azure-Verified-Modules/llms.txt`
   - This provides up-to-date specifications, standards, and best practices for AVM
   - Follow naming conventions and patterns from AVM guidance


2. **Use Official Module Sources**: Always reference Azure Verified Module Terraform modules from official sources:
   - Terraform: `source = "Azure/avm-<resource-type>/azurerm"`
   - Include version constraints for production deployments

3. **Complete Configuration Files**: Create comprehensive Terraform configurations including:
   - Provider configuration with required versions
   - Main resource definitions using AVM modules
   - Variable definitions with validation and descriptions
   - Output definitions for resource IDs and important attributes
   - Example `.tfvars` or parameter files
   - README documentation with prerequisites and usage

4. **Validate Iteratively**: Always run validation commands until successful:
   - Terraform: `terraform init`, `terraform validate`, `terraform plan`
   - Fix any errors and re-run until all validations pass

5. **Follow Module Requirements**: Pay attention to:
   - Required vs optional variables
   - Provider version requirements
   - Resource dependencies (e.g., infrastructure before cluster)
   - Azure regional availability
   - Proper resource ID formatting
   - AVM interface specifications from the guidance document

6. **Include Supporting Resources**: Create necessary Azure resources:
   - Resource Groups
   - Virtual Networks with appropriate delegations
   - Subnets with proper CIDR ranges
   - Identity and security configurations

7. **Document Thoroughly**: Provide clear documentation including:
   - Module sources and versions used
   - Prerequisites and requirements
   - Configuration examples
   - Known issues or limitations
   - Next steps for deployment

### Key AVM Resources

- **LLM Guidance**: https://azure.github.io/Azure-Verified-Modules/llms.txt (fetch before starting)
- **Terraform Registry**: https://registry.terraform.io/namespaces/Azure
- **AVM Specifications**: https://azure.github.io/Azure-Verified-Modules
- Next steps for deployment