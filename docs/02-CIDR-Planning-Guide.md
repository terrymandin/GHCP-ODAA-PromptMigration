# CIDR Planning Guide for Oracle Database @ Azure Exadata

## Overview

This guide provides comprehensive CIDR (Classless Inter-Domain Routing) planning for Oracle Database @ Azure Exadata deployments, ensuring proper network isolation, security, and connectivity.

## Prerequisites

- Completed AWR-based sizing
- Azure subscription with appropriate permissions
- Network architecture diagram of current environment
- Understanding of existing IP address schemes
- Security and compliance requirements documented

## Step 1: Understanding Network Requirements

### 1.1 Oracle Database @ Azure Network Architecture

Oracle Database @ Azure Exadata requires several network components:

- **Client Subnet:** For database client connections
- **Backup Subnet:** For backup and recovery operations  
- **Exadata Infrastructure Subnet:** For Exadata infrastructure communication
- **Management Subnet:** For administrative access (optional)
- **Azure Services Subnet:** For integration with other Azure services

### 1.2 Connectivity Requirements

```
┌─────────────────────────────────────────────────────────────┐
│                     Azure Virtual Network                    │
│                                                               │
│  ┌────────────────┐  ┌────────────────┐  ┌───────────────┐ │
│  │ Client Subnet  │  │ Backup Subnet  │  │  Management   │ │
│  │ /24            │  │ /26            │  │  Subnet /28   │ │
│  └────────┬───────┘  └────────┬───────┘  └───────┬───────┘ │
│           │                   │                   │          │
│  ┌────────┴───────────────────┴───────────────────┴───────┐ │
│  │         Exadata Infrastructure Subnet                   │ │
│  │                    /24 or /23                            │ │
│  └──────────────────────────────────────────────────────────┘ │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

## Step 2: CIDR Block Sizing

### 2.1 Minimum Subnet Sizes

| Subnet Type | Minimum Size | Recommended Size | Hosts Available | Purpose |
|-------------|--------------|------------------|-----------------|---------|
| Client Subnet | /26 (64 IPs) | /24 (256 IPs) | 251 | Application servers, clients |
| Backup Subnet | /28 (16 IPs) | /26 (64 IPs) | 59 | Backup operations, OCI connectivity |
| Exadata Infrastructure | /24 (256 IPs) | /23 (512 IPs) | 507 | Exadata nodes, VIPs, SCAN IPs |
| Management | /28 (16 IPs) | /27 (32 IPs) | 27 | Bastion, jump boxes |

**Note:** Azure reserves 5 IP addresses in each subnet (.0, .1, .2, .3, and last address)

### 2.2 Exadata Infrastructure Subnet Calculation

**Required IPs per Exadata:**
```
For Quarter Rack:
- Database VM nodes: 2-4 VMs × 3 IPs (node, VIP, SCAN) = 6-12 IPs
- Storage servers: 3 × 1 IP = 3 IPs
- SCAN listeners: 3 IPs
- Cluster VIP: 1 IP
- Additional overhead: 10-20 IPs
Total: ~30-50 IPs

For Half Rack:
- Database VM nodes: 4-8 VMs × 3 IPs = 12-24 IPs
- Storage servers: 6 × 1 IP = 6 IPs
- SCAN listeners: 3 IPs
- Cluster VIP: 1 IP
- Additional overhead: 20-30 IPs
Total: ~50-70 IPs

For Full Rack:
- Database VM nodes: 8-16 VMs × 3 IPs = 24-48 IPs
- Storage servers: 12 × 1 IP = 12 IPs
- SCAN listeners: 3 IPs
- Cluster VIP: 1 IP
- Additional overhead: 30-50 IPs
Total: ~80-120 IPs
```

**Recommendation:** Use /24 for single Exadata, /23 for multiple or future expansion

## Step 3: IP Address Planning Worksheet

### 3.1 Azure VNet Planning

```
=== AZURE VIRTUAL NETWORK ===
VNet Name: ____________________________
VNet CIDR Block: ______________________ (Recommended: /16 for flexibility)
Azure Region: __________________________
Resource Group: ________________________

Example: 10.100.0.0/16 provides 65,536 IP addresses
```

### 3.2 Subnet Allocation

```
=== SUBNET ALLOCATION ===

Client Subnet:
  Name: ____________________________
  CIDR: ____________________________ (e.g., 10.100.1.0/24)
  Gateway: _________________________ (e.g., 10.100.1.1)
  Usable Range: ____________________ (e.g., 10.100.1.4 - 10.100.1.254)

Exadata Infrastructure Subnet:
  Name: ____________________________
  CIDR: ____________________________ (e.g., 10.100.10.0/24)
  Gateway: _________________________ (e.g., 10.100.10.1)
  Usable Range: ____________________ (e.g., 10.100.10.4 - 10.100.10.254)

Backup Subnet:
  Name: ____________________________
  CIDR: ____________________________ (e.g., 10.100.20.0/26)
  Gateway: _________________________ (e.g., 10.100.20.1)
  Usable Range: ____________________ (e.g., 10.100.20.4 - 10.100.20.62)

Management Subnet:
  Name: ____________________________
  CIDR: ____________________________ (e.g., 10.100.30.0/27)
  Gateway: _________________________ (e.g., 10.100.30.1)
  Usable Range: ____________________ (e.g., 10.100.30.4 - 10.100.30.30)
```

## Step 4: Network Design Patterns

### 4.1 Pattern 1: Single Region Deployment

```
VNet: 10.100.0.0/16
├── Client Subnet: 10.100.1.0/24
├── Exadata Infrastructure: 10.100.10.0/24
├── Backup Subnet: 10.100.20.0/26
└── Management Subnet: 10.100.30.0/27

Total Used: ~600 IPs
Available for Growth: ~64,900 IPs
```

### 4.2 Pattern 2: Multi-Region with DR

```
Primary Region - VNet: 10.100.0.0/16
├── Client Subnet: 10.100.1.0/24
├── Exadata Infrastructure: 10.100.10.0/24
├── Backup Subnet: 10.100.20.0/26
└── Management Subnet: 10.100.30.0/27

DR Region - VNet: 10.101.0.0/16
├── Client Subnet: 10.101.1.0/24
├── Exadata Infrastructure: 10.101.10.0/24
├── Backup Subnet: 10.101.20.0/26
└── Management Subnet: 10.101.30.0/27

VNet Peering: Primary <-> DR
```

### 4.3 Pattern 3: Hub and Spoke Architecture

```
Hub VNet: 10.0.0.0/16 (Shared Services)
├── Firewall Subnet: 10.0.1.0/24
├── VPN Gateway Subnet: 10.0.2.0/27
└── Azure Bastion Subnet: 10.0.3.0/26

Spoke VNet (Exadata): 10.100.0.0/16
├── Client Subnet: 10.100.1.0/24
├── Exadata Infrastructure: 10.100.10.0/24
├── Backup Subnet: 10.100.20.0/26
└── Management Subnet: 10.100.30.0/27
```

## Step 5: Avoiding IP Conflicts

### 5.1 Check Existing IP Allocations

```bash
# List all VNets and their CIDR blocks
az network vnet list --query "[].{Name:name, CIDR:addressSpace.addressPrefixes}" -o table

# Check on-premises network ranges
# Document all existing ranges:
# - Corporate network: _________________
# - Remote sites: _____________________
# - VPN ranges: _______________________
# - Cloud provider networks: __________
```

### 5.2 Reserved IP Ranges to Avoid

**Do not use these ranges if they conflict:**
- 10.0.0.0/8 (Private - often used by enterprises)
- 172.16.0.0/12 (Private - common in cloud)
- 192.168.0.0/16 (Private - common in small networks)
- Azure reserved ranges in your subscription

**Recommended ranges for new deployments:**
- 10.100.0.0/16 through 10.150.0.0/16 (less commonly used)
- 172.20.0.0/16 through 172.25.0.0/16 (less commonly used)

## Step 6: Network Security Groups (NSG)

### 6.1 Client Subnet NSG Rules

```json
{
  "securityRules": [
    {
      "name": "Allow-Oracle-TNS",
      "priority": 100,
      "direction": "Inbound",
      "access": "Allow",
      "protocol": "TCP",
      "sourceAddressPrefix": "VirtualNetwork",
      "sourcePortRange": "*",
      "destinationAddressPrefix": "10.100.10.0/24",
      "destinationPortRange": "1521-1526"
    },
    {
      "name": "Allow-HTTPS",
      "priority": 110,
      "direction": "Inbound",
      "access": "Allow",
      "protocol": "TCP",
      "sourceAddressPrefix": "VirtualNetwork",
      "sourcePortRange": "*",
      "destinationAddressPrefix": "*",
      "destinationPortRange": "443"
    }
  ]
}
```

### 6.2 Exadata Infrastructure Subnet NSG Rules

```json
{
  "securityRules": [
    {
      "name": "Allow-Oracle-TNS-From-Client",
      "priority": 100,
      "direction": "Inbound",
      "access": "Allow",
      "protocol": "TCP",
      "sourceAddressPrefix": "10.100.1.0/24",
      "sourcePortRange": "*",
      "destinationAddressPrefix": "*",
      "destinationPortRange": "1521-1526"
    },
    {
      "name": "Allow-SSH-From-Management",
      "priority": 110,
      "direction": "Inbound",
      "access": "Allow",
      "protocol": "TCP",
      "sourceAddressPrefix": "10.100.30.0/27",
      "sourcePortRange": "*",
      "destinationAddressPrefix": "*",
      "destinationPortRange": "22"
    },
    {
      "name": "Allow-Exadata-Internal",
      "priority": 120,
      "direction": "Inbound",
      "access": "Allow",
      "protocol": "*",
      "sourceAddressPrefix": "10.100.10.0/24",
      "sourcePortRange": "*",
      "destinationAddressPrefix": "10.100.10.0/24",
      "destinationPortRange": "*"
    }
  ]
}
```

## Step 7: DNS Configuration

### 7.1 DNS Requirements

- **Private DNS Zone:** For internal name resolution
- **DNS Forwarding:** For hybrid connectivity
- **SCAN Names:** Three SCAN IP addresses required

### 7.2 DNS Planning Worksheet

```
=== DNS CONFIGURATION ===

Private DNS Zone: ________________________ (e.g., exadata.internal)

SCAN Name: ______________________________ (e.g., exadb-scan.exadata.internal)
SCAN IP 1: ______________________________ (e.g., 10.100.10.10)
SCAN IP 2: ______________________________ (e.g., 10.100.10.11)
SCAN IP 3: ______________________________ (e.g., 10.100.10.12)

Database VIPs:
Node 1 VIP: _____________________________ (e.g., 10.100.10.20)
Node 2 VIP: _____________________________ (e.g., 10.100.10.21)

Cluster VIP: ____________________________ (e.g., 10.100.10.15)
```

## Step 8: Connectivity Options

### 8.1 ExpressRoute

```
=== EXPRESSROUTE CONFIGURATION ===

Circuit Name: ___________________________
Bandwidth: ______________________________ (e.g., 1 Gbps, 10 Gbps)
Peering Location: _______________________
Service Provider: _______________________

BGP Peering:
  Primary Subnet: _______________________ (e.g., 10.200.1.0/30)
  Secondary Subnet: _____________________ (e.g., 10.200.1.4/30)
  Peer ASN: _____________________________ (e.g., 65000)
```

### 8.2 VPN Gateway

```
=== VPN GATEWAY CONFIGURATION ===

Gateway Name: ___________________________
SKU: ___________________________________ (e.g., VpnGw2)
Gateway Subnet: _________________________ (Must be named "GatewaySubnet")
Gateway IP: _____________________________ (Public IP for VPN)

Local Network Gateway:
  On-Premises IP: _______________________
  Address Space: ________________________ (On-premises CIDR)
```

## Step 9: Validation Checklist

- [ ] No IP conflicts with existing networks
- [ ] Sufficient IP addresses for current and future needs
- [ ] Subnets properly sized for Exadata requirements
- [ ] NSG rules allow necessary traffic
- [ ] DNS configuration planned
- [ ] Connectivity method selected (ExpressRoute/VPN)
- [ ] Network diagram created and reviewed
- [ ] Security team approval obtained
- [ ] Network team approval obtained

## Step 10: Documentation Template

Create a network design document including:

```markdown
# Network Design Document - Oracle Database @ Azure Exadata

## Network Topology
[Insert network diagram]

## IP Address Allocation
[Complete subnet table]

## Security Configuration
[NSG rules and firewall policies]

## DNS Configuration
[DNS zones and records]

## Connectivity
[ExpressRoute/VPN details]

## Monitoring and Management
[Network monitoring setup]

## Change Management
[Process for network changes]
```

## Best Practices

1. **IP Planning:** Always allocate larger address spaces than initially needed
2. **Segmentation:** Use separate subnets for different functions
3. **Documentation:** Keep IP allocation spreadsheet updated
4. **Security:** Follow principle of least privilege in NSG rules
5. **Naming Convention:** Use consistent naming scheme for all resources
6. **High Availability:** Plan for multiple availability zones if required

## Next Steps

After completing CIDR planning:
1. Proceed to [IaC Environment Generation](03-IaC-Environment-Generation.md)
2. Review network design with Azure network team
3. Submit network change requests if needed
4. Begin infrastructure provisioning

## Additional Resources

- [Azure Virtual Network Documentation](https://docs.microsoft.com/azure/virtual-network/)
- [Oracle Database @ Azure Networking Requirements](https://docs.oracle.com/en-us/iaas/Content/Database/Concepts/exaoverview.htm)
- [Azure Network Security Best Practices](https://docs.microsoft.com/azure/security/)
