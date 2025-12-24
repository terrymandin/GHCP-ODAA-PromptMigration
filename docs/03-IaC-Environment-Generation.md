# IaC Environment Generation for Oracle Database @ Azure Exadata

## Overview

This guide provides Infrastructure as Code (IaC) templates and procedures for deploying Oracle Database @ Azure Exadata infrastructure using Terraform and Azure Resource Manager (ARM) templates.

## Prerequisites

- Completed AWR-based sizing
- Completed CIDR planning
- Azure subscription with Owner or Contributor role
- Terraform installed (version 1.5.0 or later)
- Azure CLI installed and configured
- Git for version control

## Step 1: IaC Tool Selection

### 1.1 Terraform (Recommended)

**Advantages:**
- Multi-cloud support
- Strong community and module ecosystem
- State management
- Plan and preview changes before apply

**Use when:**
- Managing infrastructure across Azure and OCI
- Need version control and GitOps workflows
- Require modular, reusable infrastructure code

### 1.2 ARM Templates

**Advantages:**
- Native Azure support
- Integrated with Azure DevOps
- No external dependencies

**Use when:**
- Azure-only deployment
- Existing ARM template infrastructure
- Integration with Azure Policy

## Step 2: Project Structure

### 2.1 Recommended Directory Layout

```
exadata-azure-iac/
├── README.md
├── .gitignore
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── providers.tf
│   ├── terraform.tfvars.example
│   ├── modules/
│   │   ├── networking/
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── exadata/
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   └── security/
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       └── outputs.tf
│   └── environments/
│       ├── dev/
│       │   └── terraform.tfvars
│       ├── staging/
│       │   └── terraform.tfvars
│       └── production/
│           └── terraform.tfvars
├── arm-templates/
│   ├── azuredeploy.json
│   ├── azuredeploy.parameters.json
│   └── nested/
│       ├── networking.json
│       ├── exadata.json
│       └── security.json
└── scripts/
    ├── deploy.sh
    ├── destroy.sh
    └── validate.sh
```

## Step 3: Terraform Configuration

### 3.1 Provider Configuration (providers.tf)

```hcl
terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
  
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "tfstatestorage"
    container_name       = "tfstate"
    key                  = "exadata.terraform.tfstate"
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
  
  subscription_id = var.subscription_id
}
```

### 3.2 Variables Configuration (variables.tf)

```hcl
# General Settings
variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "eastus"
}

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be dev, staging, or production."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

# Networking Variables
variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.100.0.0/16"]
}

variable "client_subnet_prefix" {
  description = "Address prefix for client subnet"
  type        = string
  default     = "10.100.1.0/24"
}

variable "exadata_subnet_prefix" {
  description = "Address prefix for Exadata infrastructure subnet"
  type        = string
  default     = "10.100.10.0/24"
}

variable "backup_subnet_prefix" {
  description = "Address prefix for backup subnet"
  type        = string
  default     = "10.100.20.0/26"
}

variable "management_subnet_prefix" {
  description = "Address prefix for management subnet"
  type        = string
  default     = "10.100.30.0/27"
}

# Exadata Configuration
variable "exadata_infrastructure_name" {
  description = "Name of the Exadata infrastructure"
  type        = string
}

variable "exadata_shape" {
  description = "Shape of the Exadata infrastructure"
  type        = string
  validation {
    condition     = can(regex("^Exadata\\.(X8M|X9M)\\.(Quarter|Half|Full)$", var.exadata_shape))
    error_message = "Shape must be in format: Exadata.X8M.Quarter, Exadata.X8M.Half, etc."
  }
}

variable "exadata_storage_size_tb" {
  description = "Storage size in TB"
  type        = number
}

variable "compute_count" {
  description = "Number of compute nodes"
  type        = number
}

# Tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    ManagedBy = "Terraform"
    Project   = "Exadata-Migration"
  }
}
```

### 3.3 Main Configuration (main.tf)

```hcl
# Resource Group
resource "azurerm_resource_group" "exadata_rg" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Networking Module
module "networking" {
  source = "./modules/networking"
  
  resource_group_name      = azurerm_resource_group.exadata_rg.name
  location                 = azurerm_resource_group.exadata_rg.location
  vnet_name                = "${var.environment}-exadata-vnet"
  vnet_address_space       = var.vnet_address_space
  client_subnet_prefix     = var.client_subnet_prefix
  exadata_subnet_prefix    = var.exadata_subnet_prefix
  backup_subnet_prefix     = var.backup_subnet_prefix
  management_subnet_prefix = var.management_subnet_prefix
  tags                     = var.tags
}

# Security Module
module "security" {
  source = "./modules/security"
  
  resource_group_name = azurerm_resource_group.exadata_rg.name
  location            = azurerm_resource_group.exadata_rg.location
  vnet_id             = module.networking.vnet_id
  client_subnet_id    = module.networking.client_subnet_id
  exadata_subnet_id   = module.networking.exadata_subnet_id
  tags                = var.tags
}

# Exadata Module
module "exadata" {
  source = "./modules/exadata"
  
  resource_group_name         = azurerm_resource_group.exadata_rg.name
  location                    = azurerm_resource_group.exadata_rg.location
  exadata_infrastructure_name = var.exadata_infrastructure_name
  exadata_shape               = var.exadata_shape
  exadata_subnet_id           = module.networking.exadata_subnet_id
  storage_size_tb             = var.exadata_storage_size_tb
  compute_count               = var.compute_count
  tags                        = var.tags
  
  depends_on = [
    module.networking,
    module.security
  ]
}
```

### 3.4 Networking Module (modules/networking/main.tf)

```hcl
# Virtual Network
resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.vnet_address_space
  tags                = var.tags
}

# Client Subnet
resource "azurerm_subnet" "client" {
  name                 = "client-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.client_subnet_prefix]
}

# Exadata Infrastructure Subnet
resource "azurerm_subnet" "exadata" {
  name                 = "exadata-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.exadata_subnet_prefix]
  
  delegation {
    name = "exadata-delegation"
    
    service_delegation {
      name = "Oracle.Database/networkAttachments"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action"
      ]
    }
  }
}

# Backup Subnet
resource "azurerm_subnet" "backup" {
  name                 = "backup-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.backup_subnet_prefix]
}

# Management Subnet
resource "azurerm_subnet" "management" {
  name                 = "management-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.management_subnet_prefix]
}

# Private DNS Zone
resource "azurerm_private_dns_zone" "exadata" {
  name                = "exadata.internal"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Link DNS Zone to VNet
resource "azurerm_private_dns_zone_virtual_network_link" "exadata" {
  name                  = "exadata-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.exadata.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  registration_enabled  = true
}
```

### 3.5 Security Module (modules/security/main.tf)

```hcl
# Network Security Group for Client Subnet
resource "azurerm_network_security_group" "client_nsg" {
  name                = "client-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
  
  security_rule {
    name                       = "Allow-Oracle-TNS"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "1521-1526"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
  
  security_rule {
    name                       = "Allow-HTTPS"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
}

# Network Security Group for Exadata Subnet
resource "azurerm_network_security_group" "exadata_nsg" {
  name                = "exadata-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
  
  security_rule {
    name                       = "Allow-Oracle-TNS-From-Client"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "1521-1526"
    source_address_prefix      = var.client_subnet_id
    destination_address_prefix = "*"
  }
  
  security_rule {
    name                       = "Allow-SSH"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
  
  security_rule {
    name                       = "Allow-Exadata-Internal"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.exadata_subnet_id
    destination_address_prefix = var.exadata_subnet_id
  }
}

# Associate NSG with Client Subnet
resource "azurerm_subnet_network_security_group_association" "client" {
  subnet_id                 = var.client_subnet_id
  network_security_group_id = azurerm_network_security_group.client_nsg.id
}

# Associate NSG with Exadata Subnet
resource "azurerm_subnet_network_security_group_association" "exadata" {
  subnet_id                 = var.exadata_subnet_id
  network_security_group_id = azurerm_network_security_group.exadata_nsg.id
}
```

## Step 4: Environment-Specific Configuration

### 4.1 Development Environment (environments/dev/terraform.tfvars)

```hcl
subscription_id             = "your-subscription-id"
environment                 = "dev"
location                    = "eastus"
resource_group_name         = "exadata-dev-rg"

# Networking
vnet_address_space          = ["10.100.0.0/16"]
client_subnet_prefix        = "10.100.1.0/24"
exadata_subnet_prefix       = "10.100.10.0/24"
backup_subnet_prefix        = "10.100.20.0/26"
management_subnet_prefix    = "10.100.30.0/27"

# Exadata Configuration (smaller for dev)
exadata_infrastructure_name = "exadata-dev"
exadata_shape               = "Exadata.X8M.Quarter"
exadata_storage_size_tb     = 42
compute_count               = 2

tags = {
  Environment = "Development"
  ManagedBy   = "Terraform"
  Project     = "Exadata-Migration"
  CostCenter  = "IT-Dev"
}
```

### 4.2 Production Environment (environments/production/terraform.tfvars)

```hcl
subscription_id             = "your-subscription-id"
environment                 = "production"
location                    = "eastus"
resource_group_name         = "exadata-prod-rg"

# Networking
vnet_address_space          = ["10.100.0.0/16"]
client_subnet_prefix        = "10.100.1.0/24"
exadata_subnet_prefix       = "10.100.10.0/23"
backup_subnet_prefix        = "10.100.20.0/26"
management_subnet_prefix    = "10.100.30.0/27"

# Exadata Configuration (full production)
exadata_infrastructure_name = "exadata-prod"
exadata_shape               = "Exadata.X9M.Half"
exadata_storage_size_tb     = 244
compute_count               = 8

tags = {
  Environment       = "Production"
  ManagedBy         = "Terraform"
  Project           = "Exadata-Migration"
  CostCenter        = "IT-Prod"
  BusinessCritical  = "Yes"
}
```

## Step 5: Deployment Scripts

### 5.1 Deployment Script (scripts/deploy.sh)

```bash
#!/bin/bash
set -e

ENVIRONMENT=${1:-dev}
TERRAFORM_DIR="../terraform"

echo "Deploying Exadata infrastructure for environment: $ENVIRONMENT"

cd "$TERRAFORM_DIR"

# Initialize Terraform
echo "Initializing Terraform..."
terraform init

# Select workspace
echo "Selecting workspace: $ENVIRONMENT"
terraform workspace select "$ENVIRONMENT" || terraform workspace new "$ENVIRONMENT"

# Validate configuration
echo "Validating Terraform configuration..."
terraform validate

# Plan deployment
echo "Planning deployment..."
terraform plan \
  -var-file="environments/$ENVIRONMENT/terraform.tfvars" \
  -out="$ENVIRONMENT.tfplan"

# Apply deployment
echo "Applying deployment..."
read -p "Do you want to proceed with deployment? (yes/no): " CONFIRM
if [ "$CONFIRM" == "yes" ]; then
  terraform apply "$ENVIRONMENT.tfplan"
  echo "Deployment completed successfully!"
else
  echo "Deployment cancelled."
  exit 1
fi
```

### 5.2 Validation Script (scripts/validate.sh)

```bash
#!/bin/bash
set -e

ENVIRONMENT=${1:-dev}

echo "Validating deployment for environment: $ENVIRONMENT"

# Check if resource group exists
RG_NAME="exadata-$ENVIRONMENT-rg"
echo "Checking resource group: $RG_NAME"
az group show --name "$RG_NAME" --output table

# Check VNet
echo "Checking virtual network..."
az network vnet list --resource-group "$RG_NAME" --output table

# Check subnets
echo "Checking subnets..."
az network vnet subnet list --resource-group "$RG_NAME" --vnet-name "$ENVIRONMENT-exadata-vnet" --output table

# Check NSGs
echo "Checking network security groups..."
az network nsg list --resource-group "$RG_NAME" --output table

echo "Validation completed!"
```

## Step 6: Best Practices

### 6.1 State Management

- **Remote State:** Always use remote backend (Azure Storage)
- **State Locking:** Enable to prevent concurrent modifications
- **Backup:** Regular backups of Terraform state

### 6.2 Security

- **Secrets Management:** Use Azure Key Vault for sensitive data
- **Service Principal:** Use with minimum required permissions
- **Network Isolation:** Deploy via Azure DevOps agents in VNet

### 6.3 Code Organization

- **Modules:** Reusable components for networking, security, compute
- **Environments:** Separate tfvars files for each environment
- **Variables:** Use validation rules to prevent misconfigurations

### 6.4 GitOps Workflow

```
1. Developer creates feature branch
2. Make infrastructure changes
3. Run terraform plan locally
4. Create pull request
5. Automated terraform plan runs in CI
6. Peer review and approval
7. Merge to main branch
8. Automated terraform apply in CD pipeline
```

## Step 7: CI/CD Integration

### 7.1 Azure DevOps Pipeline (azure-pipelines.yml)

```yaml
trigger:
  branches:
    include:
      - main
      - develop
  paths:
    include:
      - terraform/**

pool:
  vmImage: 'ubuntu-latest'

variables:
  - group: terraform-secrets

stages:
  - stage: Validate
    jobs:
      - job: TerraformValidate
        steps:
          - task: TerraformInstaller@0
            inputs:
              terraformVersion: '1.5.0'
          
          - task: TerraformTaskV4@4
            displayName: 'Terraform Init'
            inputs:
              provider: 'azurerm'
              command: 'init'
              workingDirectory: '$(System.DefaultWorkingDirectory)/terraform'
              backendServiceArm: 'Azure-Service-Connection'
              backendAzureRmResourceGroupName: 'tfstate-rg'
              backendAzureRmStorageAccountName: 'tfstatestorage'
              backendAzureRmContainerName: 'tfstate'
              backendAzureRmKey: 'exadata.terraform.tfstate'
          
          - task: TerraformTaskV4@4
            displayName: 'Terraform Validate'
            inputs:
              provider: 'azurerm'
              command: 'validate'
              workingDirectory: '$(System.DefaultWorkingDirectory)/terraform'
  
  - stage: Plan
    dependsOn: Validate
    jobs:
      - job: TerraformPlan
        steps:
          - task: TerraformTaskV4@4
            displayName: 'Terraform Plan'
            inputs:
              provider: 'azurerm'
              command: 'plan'
              workingDirectory: '$(System.DefaultWorkingDirectory)/terraform'
              commandOptions: '-var-file=environments/$(environment)/terraform.tfvars -out=$(environment).tfplan'
              environmentServiceNameAzureRM: 'Azure-Service-Connection'
  
  - stage: Apply
    dependsOn: Plan
    condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
    jobs:
      - deployment: TerraformApply
        environment: 'production'
        strategy:
          runOnce:
            deploy:
              steps:
                - task: TerraformTaskV4@4
                  displayName: 'Terraform Apply'
                  inputs:
                    provider: 'azurerm'
                    command: 'apply'
                    workingDirectory: '$(System.DefaultWorkingDirectory)/terraform'
                    commandOptions: '$(environment).tfplan'
                    environmentServiceNameAzureRM: 'Azure-Service-Connection'
```

## Step 8: Post-Deployment Verification

After deployment, verify:

1. **Resource Group Created:** Contains all resources
2. **VNet and Subnets:** Correct CIDR blocks
3. **NSGs:** Properly associated with subnets
4. **Exadata Infrastructure:** Provisioned and accessible
5. **DNS:** Private zone configured
6. **Tags:** Applied to all resources

## Next Steps

After IaC deployment:
1. Proceed to [Migration Tool Selection](04-Migration-Tool-Selection.md)
2. Configure Exadata infrastructure
3. Set up monitoring and alerting
4. Begin database migration planning

## Additional Resources

- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Oracle Database @ Azure Terraform Examples](https://github.com/oracle/terraform-provider-oci)
- [Azure DevOps Terraform Tasks](https://marketplace.visualstudio.com/items?itemName=ms-devlabs.custom-terraform-tasks)
