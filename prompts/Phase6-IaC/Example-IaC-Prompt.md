# Example: Using Azure Verified Modules for All ODAA Resources

This example demonstrates how to request infrastructure using Azure Verified Modules (AVM) for **all** resources.

## Prerequisites

**IMPORTANT**: Before using this example, ensure you have completed Phase 5 CIDR Planning. The `Artifacts/Phase5-CIDR/CIDR-Definition.md` file must exist with approved network configuration. This example shows how to reference that file so the AI pulls the correct CIDR ranges.

## Full AVM-Based Prompt Example

Copy and use this prompt to generate ODAA infrastructure with AVM modules for everything:

```
@IaC-Prompt.md #file:Artifacts/Phase5-CIDR/CIDR-Definition.md

Create Oracle Database@Azure (ODAA) infrastructure using Azure Verified Modules (AVM) for ALL resources:

## Infrastructure Requirements

### Foundation (Use Resource Group AVM Module)
- Resource Group: eastus location
- Enable resource locks (CanNotDelete)
- Configure role assignments for Database team

### Core ODAA Resources (Use AVM Modules)
- Exadata Infrastructure: X11M shape with 4 compute nodes and 6 storage nodes
- VM Cluster: 32 CPU cores, 120 GB memory, 4 TB storage
- Deploy to eastus region in availability zone 1
- License model: BringYourOwnLicense
- Time zone: America/Los_Angeles
- GI version: 19.0.0.0

### Network Resources (Use VNet AVM Module)
- Read network configuration from the CIDR-Definition.md file:
  - Use the approved VNet CIDR range
  - Use the approved Client Subnet CIDR range with delegation to Oracle.Database/networkAttachments
  - Use the approved Backup Subnet CIDR range
- Include Network Security Group via AVM module
- Configure subnet delegation properly for Oracle

### Monitoring (Use Log Analytics AVM Module)
- Log Analytics Workspace with 30-day retention
- Enable diagnostic settings on all resources
- Configure workspace for centralized logging

### Advanced Features (Use AVM Interfaces)
- Add role assignments for Database Contributors
- Enable resource locks (CanNotDelete) on production resources
- Configure diagnostic settings for all resources
- Use private endpoints where applicable
- Consistent tagging strategy across all resources

### Tags
Environment: Production
ManagedBy: Terraform
Project: Oracle Database @ Azure
CostCenter: IT-Database
Owner: Database Team

## Required Outputs
- All resource IDs
- VM Cluster OCID
- Connection information
- Configuration summary

Iterate with "terraform init", "terraform validate", and "terraform plan" until there are no errors.
```

---

## What This Prompt Will Generate

Using this enhanced prompt, the AI will create:

### 1. **Resource Group** (AVM)
   ```hcl
   module "resource_group" {
     source  = "Azure/avm-res-resources-resourcegroup/azurerm"
     version = "~> 0.1"
     
     # Includes:
     # - Resource group creation
     # - Role assignments
     # - Resource locks
     # - Tags
   }
   ```

### 2. **Virtual Network** (AVM)
   ```hcl
   module "virtual_network" {
     source  = "Azure/avm-res-network-virtualnetwork/azurerm"
     version = "~> 0.7"
     
     # Includes:
     # - Subnets with delegations
     # - Role assignments
     # - Diagnostic settings
     # - Resource locks
     # - Tags
   }
   ```

### 3. **Log Analytics Workspace** (AVM)
   ```hcl
   module "log_analytics" {
     source  = "Azure/avm-res-operationalinsights-workspace/azurerm"
     version = "~> 0.4"
     
     # Includes:
     # - Retention configuration
     # - Diagnostic settings
     # - Role assignments
     # - Resource locks
     # - Tags
   }
   ```

### 4. **Exadata Infrastructure** (AVM)
   ```hcl
   module "exadata_infrastructure" {
     source  = "Azure/avm-res-oracledatabase-cloudexadatainfrastructure/azurerm"
     version = "0.2.0"
     
     # Fully configured with:
     # - Compute and storage nodes
     # - Maintenance windows
     # - Customer contacts
     # - Role assignments
     # - Tags
   }
   ```

### 5. **VM Cluster** (AVM)
   ```hcl
   module "vm_cluster" {
     source  = "Azure/avm-res-oracledatabase-cloudvmcluster/azurerm"
     version = "0.2.0"
     
     # Includes:
     # - Diagnostic settings
     # - Network configuration
     # - Storage configuration
     # - Role assignments
     # - Tags
   }
   ```

---

## Benefits of This Approach

### 1. **Consistency**
All resources follow the same AVM patterns:
- Standardized variable naming
- Common interfaces for diagnostic settings
- Consistent role assignment patterns
- Uniform tagging approach

### 2. **Built-in Best Practices**
- Resource Group AVM includes integrated locks and RBAC
- Virtual Network AVM includes NSG support
- Log Analytics AVM includes data retention policies
- All modules support resource locks
- Private endpoint support where applicable

### 3. **Enhanced Security**
- Role assignments on all resources
- Diagnostic settings enabled by default
- Support for customer-managed keys
- Private endpoint integration

### 4. **Operational Excellence**
- Resource locks prevent accidental deletion
- Comprehensive diagnostic logging
- Centralized monitoring configuration
- Consistent tagging for cost management

### 5. **Maintainability**
- Microsoft-maintained modules
- Regular security updates
- Breaking change notifications
- Comprehensive documentation

---

## Key Differences from Raw Resources

| Aspect | Raw azurerm Resources | AVM Modules |
|--------|----------------------|-------------|
| **Configuration Complexity** | Manual configuration of all settings | Pre-configured best practices |
| **Diagnostic Settings** | Manual resource blocks | Built-in interface |
| **Role Assignments** | Separate resources | Integrated interface |
| **Resource Locks** | Separate management lock resources | Built-in lock configuration |
| **Private Endpoints** | Manual setup | Standardized interface |
| **NSG Integration** | Separate resources and associations | Integrated configuration |
| **Maintenance** | Manual updates needed | Microsoft-maintained |
| **Best Practices** | Must implement manually | Included by default |

---

## Expected File Structure

```
terraform/
├── providers.tf              # Provider configurations
├── main.tf                   # All AVM module declarations
├── variables.tf              # Variable definitions with validation
├── outputs.tf                # Output values
├── terraform.tfvars          # Example values (customize!)
└── README.md                 # Deployment documentation
```

---

## Code Size Comparison

### Raw Resources Approach
- Resource Group: ~5 lines
- Separate locks: ~6 lines each
- Separate RBAC: ~5 lines each  
- VNet: ~15 lines
- Subnet: ~20 lines
- Separate diagnostics: ~15 lines each
- Log Analytics: ~8 lines
- ODAA modules: ~150 lines (using AVM)

**Total**: ~300-350 lines (without full security features)

### Full AVM Approach
- Resource Group AVM: ~20 lines (with locks & RBAC)
- VNet AVM: ~50 lines (includes subnets, diagnostics, locks)
- Log Analytics AVM: ~30 lines (includes diagnostics, locks)
- ODAA modules: ~150 lines (using AVM)

**Total**: ~250-280 lines (with full security features built-in)

**Result**: ~20% less code, with MORE features! 🎉

---

## Module Usage Details

### Resource Group Module
```hcl
module "resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "~> 0.1"

  name     = "rg-odaa-prod-eastus"
  location = "eastus"
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Project     = "Oracle Database @ Azure"
  }
  
  lock = {
    kind = "CanNotDelete"
    name = "rg-lock"
  }
  
  role_assignments = {
    db_contributor = {
      role_definition_name = "Contributor"
      principal_id         = var.database_team_principal_id
    }
  }
}
```

### Virtual Network Module
```hcl
module "virtual_network" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "~> 0.7"

  name                = "vnet-odaa-prod-eastus"
  location            = "eastus"
  resource_group_name = module.resource_group.name
  
  address_space = ["172.16.0.0/24"]
  
  subnets = {
    oracle = {
      name             = "snet-oracle"
      address_prefixes = ["172.16.0.0/25"]
      
      delegation = [{
        name = "Oracle.Database.networkAttachments"
        service_delegation = {
          name = "Oracle.Database/networkAttachments"
          actions = [
            "Microsoft.Network/networkinterfaces/*",
            "Microsoft.Network/virtualNetworks/subnets/join/action",
          ]
        }
      }]
    }
  }

  diagnostic_settings = {
    default = {
      workspace_resource_id = module.log_analytics.resource_id
      log_categories        = ["allLogs"]
      metric_categories     = ["AllMetrics"]
    }
  }

  lock = {
    kind = "CanNotDelete"
    name = "vnet-lock"
  }
  
  tags = var.tags
}
```

### Log Analytics Module
```hcl
module "log_analytics" {
  source  = "Azure/avm-res-operationalinsights-workspace/azurerm"
  version = "~> 0.4"

  name                = "law-odaa-prod-eastus"
  location            = "eastus"
  resource_group_name = module.resource_group.name
  
  log_analytics_workspace_sku          = "PerGB2018"
  log_analytics_workspace_retention_in_days = 30
  
  log_analytics_workspace_daily_quota_gb = 10

  lock = {
    kind = "CanNotDelete"
    name = "law-lock"
  }
  
  tags = var.tags
}
```

---

## Comparison Table: Module Features

| Module | Lines of Code | Features Included |
|--------|---------------|-------------------|
| Resource Group | ~15 | Name, location, tags, locks, RBAC |
| Virtual Network | ~40 | VNet, subnets, delegation, diagnostics, RBAC, locks |
| Log Analytics | ~30 | Workspace, retention, quotas, diagnostics, RBAC, locks |
| Exadata Infrastructure | ~80 | Full ODAA config, maintenance, contacts, telemetry |
| VM Cluster | ~80 | Full cluster config, diagnostics, network, storage |

**Total AVM Code**: ~245 lines with enterprise features  
**Raw Resources Equivalent**: ~350+ lines for same features

---

## Migration Path

If you have existing infrastructure with raw resources:

### Option 1: Fresh Deployment (Recommended for Dev/Test)
1. Use this full AVM prompt
2. Deploy to new resource group
3. Migrate data
4. Decommission old resources

### Option 2: Gradual Migration (Production)
1. Start with AVM for new resources
2. Import existing resources into Terraform state
3. Gradually replace raw resources with AVM modules
4. Use `terraform import` for existing resources

### Option 3: Hybrid Approach
1. Keep existing infrastructure as-is
2. Use full AVM for new environments
3. Document differences between approaches
4. Plan future migration during maintenance windows

---

## Quick Reference: AVM Module URLs

| Resource | Module URL |
|----------|-----------|
| Resource Group | https://registry.terraform.io/modules/Azure/avm-res-resources-resourcegroup/azurerm/latest |
| Virtual Network | https://registry.terraform.io/modules/Azure/avm-res-network-virtualnetwork/azurerm/latest |
| Log Analytics | https://registry.terraform.io/modules/Azure/avm-res-operationalinsights-workspace/azurerm/latest |
| ODAA Infrastructure | https://registry.terraform.io/modules/Azure/avm-res-oracledatabase-cloudexadatainfrastructure/azurerm/latest |
| ODAA VM Cluster | https://registry.terraform.io/modules/Azure/avm-res-oracledatabase-cloudvmcluster/azurerm/latest |

---

## Pro Tips

1. **Always specify "ALL resources"** in your prompt to ensure complete AVM usage
2. **Use module outputs** like `module.resource_group.name` for dependencies
3. **Leverage built-in features** instead of creating separate resources
4. **Pin ODAA versions** to `0.2.0` for stability
5. **Use version constraints** like `~> 0.7` for supporting modules
6. **Request features explicitly**: "Add role assignments", "Enable locks", "Configure diagnostics"
7. **Test in dev first** before deploying to production
8. **Review terraform plan** carefully before applying

---

## Next Steps

1. ✅ Copy the prompt example above
2. ✅ Customize with your specific requirements
3. ✅ Paste into GitHub Copilot or AI chat
4. ✅ Review the generated code
5. ✅ Update `terraform.tfvars` with your values
6. ✅ Run `terraform init`
7. ✅ Run `terraform validate`
8. ✅ Run `terraform plan` and review
9. ✅ Run `terraform apply` when ready

---

**Ready to deploy with full AVM?** Use the prompt example at the top of this file! 🚀
