# Example: CIDR Planning for Oracle Database@Azure

This example demonstrates how to use the Phase 5 CIDR Planning prompt to calculate and allocate appropriate CIDR ranges for Oracle Database@Azure deployments.

## Full CIDR Planning Prompt Example

Copy and use this prompt to generate CIDR allocations based on Microsoft best practices:

```
@CIDR-Planning-Prompt.md

Plan CIDR ranges for Oracle Database@Azure deployment:

## Configuration Details

### Virtual Machine Cluster Configuration
- Number of VM Clusters: 2
- VMs per Cluster: 3
- Expected Growth: 1 additional cluster in next 12 months
- High Availability: Multi-zone deployment in single region

### Network Context
- Existing VNet CIDR: 10.0.0.0/16
- Reserved IP Ranges: 10.0.0.0/24 (management subnet), 10.0.1.0/24 (gateway subnet)
- Cross-Region Connectivity: Yes, peering to East US 2 (10.1.0.0/16)
- Autonomous Database: No

### Deployment Type
- Exadata Version: Oracle Exadata X9M
- Deployment Region: East US

## Requirements
- Follow Microsoft best practices from the documentation
- Include 75% growth buffer for future expansion
- Ensure no overlap with existing network ranges
- Avoid reserved ranges for X9M (100.106.0.0/16, 100.107.0.0/16)
- Allocate /25 or larger for client subnet (not minimum /27)
- Document all calculations and assumptions

Generate the CIDR Definition document in Artifacts/CIDR Definition.md with complete details.
```

---

## What This Prompt Will Generate

Using this prompt, the AI will create a comprehensive CIDR allocation document with:

### 1. **Calculated IP Requirements**

**Current Deployment:**
- Client Subnet: (2 clusters × ((3 VMs × 4 IPs) + 3 SCANs)) + 13 = 43 IPs
- Backup Subnet: (2 clusters × (3 VMs × 3 IPs)) + 3 = 21 IPs

**With Growth Buffer (75%):**
- Client Subnet: 43 IPs × 1.75 = ~76 IPs (Recommended: /25 = 125 usable IPs)
- Backup Subnet: 21 IPs × 1.75 = ~37 IPs (Recommended: /26 = 61 usable IPs)

### 2. **CIDR Range Allocations**

```markdown
| Subnet Type       | CIDR Range      | Usable IPs | Purpose                      |
|-------------------|-----------------|------------|------------------------------|
| Client Subnet     | 10.0.10.0/25    | 125        | VM cluster client connectivity|
| Backup Subnet     | 10.0.11.0/26    | 61         | Backup network traffic       |
```

### 3. **Reserved IP Documentation**

**Client Subnet (10.0.10.0/25):**
- First 4 IPs: 10.0.10.0 - 10.0.10.3
- 9th to 16th IPs: 10.0.10.8 - 10.0.10.15
- Last IP: 10.0.10.127

**Backup Subnet (10.0.11.0/26):**
- Networking Services: 3 IPs reserved

### 4. **Validation Checklist**

```markdown
- [ ] CIDR ranges reviewed by network team
- [ ] No conflicts with existing Azure resources
- [ ] Growth capacity sufficient for 12-24 months
- [ ] High availability requirements met
- [ ] Cross-region connectivity verified (no overlap with 10.1.0.0/16)
- [ ] Avoided X9M reserved ranges (100.106.0.0/16, 100.107.0.0/16)
- [ ] Security team approval obtained
- [ ] CSA architecture review completed
```

---

## Scenario Comparisons

### Scenario 1: Small Deployment (Minimum Configuration)
```
Configuration:
- 1 VM cluster with 2 VMs
- No growth planned
- No cross-region connectivity

IP Requirements:
- Client: (1 × ((2 × 4) + 3)) + 13 = 24 IPs → /27 (30 usable)
- Backup: (1 × (2 × 3)) + 3 = 9 IPs → /28 (13 usable)

Recommended (with buffer):
- Client: /26 (61 usable IPs) - 154% buffer
- Backup: /27 (29 usable IPs) - 222% buffer
```

### Scenario 2: Medium Deployment (Example Above)
```
Configuration:
- 2 VM clusters with 3 VMs each
- 1 additional cluster planned (12 months)
- Cross-region peering

IP Requirements:
- Client: 43 IPs → Minimum /26 (61 usable)
- Backup: 21 IPs → Minimum /27 (29 usable)

Recommended (with 75% buffer):
- Client: /25 (125 usable IPs) - 191% buffer
- Backup: /26 (61 usable IPs) - 190% buffer
```

### Scenario 3: Large Deployment (Enterprise Scale)
```
Configuration:
- 4 VM clusters with 4 VMs each
- 2 additional clusters planned (24 months)
- Multi-region with Autonomous Database

IP Requirements:
- Client: (4 × ((4 × 4) + 3)) + 13 = 89 IPs
- Backup: (4 × (4 × 3)) + 3 = 51 IPs
- Autonomous DB: Minimum 30 IPs

Recommended (with 100% buffer):
- Client: /24 (253 usable IPs) - 184% buffer
- Backup: /25 (125 usable IPs) - 145% buffer
- Autonomous DB: /27 (29 usable IPs)
```

---

## Calculation Reference

### Client Subnet Formula
```
Total IPs = (Number of Clusters × ((VMs per Cluster × 4) + 3)) + 13

Components:
- 4 IPs per VM
- 3 IPs for SCANs per cluster
- 13 IPs reserved for networking services
```

### Backup Subnet Formula
```
Total IPs = (Number of Clusters × (VMs per Cluster × 3)) + 3

Components:
- 3 IPs per VM
- 3 IPs reserved for networking services
```

### CIDR Capacity Table

| CIDR | Total IPs | Client Usable* | Backup Usable** | Max 2-VM Clusters | Max 3-VM Clusters | Max 4-VM Clusters |
|------|-----------|----------------|-----------------|-------------------|-------------------|-------------------|
| /28  | 16        | 0              | 13              | 0                 | 0                 | 0                 |
| /27  | 32        | 15             | 29              | 1                 | 0                 | 0                 |
| /26  | 64        | 47             | 61              | 4                 | 3                 | 2                 |
| /25  | 128       | 111            | 125             | 10                | 7                 | 5                 |
| /24  | 256       | 239            | 253             | 21                | 15                | 12                |

\* After removing 13 IPs for networking services  
\** After removing 3 IPs for networking services

---

## Best Practices Applied

### 1. **Oversizing for Future Growth**
✅ Allocate /25 instead of minimum /27 for client subnet  
✅ Include 50-100% buffer beyond current requirements  
✅ Account for planned expansion (12-24 months)  

**Why?** Reduces relative impact of reserved IPs and avoids subnet reallocation

### 2. **Avoid Network Conflicts**
✅ Check existing VNet and subnet allocations  
✅ Verify cross-region peering address spaces  
✅ Document reserved ranges (X9M: 100.106.0.0/16, 100.107.0.0/16)  

**Why?** Prevents routing issues and connectivity problems

### 3. **Document Reserved IPs**
✅ First 4 IPs in client subnet  
✅ IPs 9-16 in client subnet  
✅ Last IP in subnet  

**Why?** Ensures awareness of Azure networking service requirements

### 4. **Plan for High Availability**
✅ Consider multi-zone deployments  
✅ Account for disaster recovery scenarios  
✅ Document cross-region connectivity  

**Why?** Ensures sufficient capacity for HA/DR architectures

---

## Common Pitfalls to Avoid

### ❌ Don't: Use Minimum CIDR Sizes
```
Client: /27 (only 15 usable IPs after reserved)
Result: Limited to 1 small cluster, no growth capacity
```

### ✅ Do: Allocate Larger Subnets
```
Client: /25 (111 usable IPs after reserved)
Result: Room for 10 two-VM clusters or significant growth
```

---

### ❌ Don't: Forget Reserved Ranges
```
CIDR: 100.106.10.0/24 (conflicts with X9M interconnect)
Result: Deployment failure or routing issues
```

### ✅ Do: Use Proper Address Space
```
CIDR: 10.0.10.0/25 (within VNet range, no conflicts)
Result: Successful deployment and connectivity
```

---

### ❌ Don't: Ignore Growth Planning
```
Plan: Exact fit for current 2 clusters
Result: Need to reallocate subnets in 6 months
```

### ✅ Do: Include Growth Buffer
```
Plan: 75-100% buffer beyond current needs
Result: Accommodate growth without network changes
```

---

### ❌ Don't: Overlook Cross-Region Routing
```
Region 1: 10.0.0.0/16
Region 2: 10.0.0.0/16 (duplicate!)
Result: Routing conflicts, connectivity issues
```

### ✅ Do: Coordinate Address Spaces
```
Region 1: 10.0.0.0/16
Region 2: 10.1.0.0/16 (unique)
Result: Clean routing, no conflicts
```

---

## Generated File Structure

The prompt will create this file in your workspace:

```
Artifacts/
└── CIDR Definition.md
```

### Contents Include:
1. **Configuration Summary** - Deployment parameters and requirements
2. **Calculated IP Requirements** - Detailed breakdown by subnet type
3. **Assigned CIDR Ranges** - Table with allocations and capacity
4. **Reserved IP Addresses** - Specific IPs reserved by Azure
5. **Network Constraints** - Validation of no-overlap requirements
6. **Validation Checklist** - Team review and approval tracking
7. **Reference Documentation** - Links to Microsoft Learn resources
8. **Next Steps** - Actions to proceed with infrastructure generation

---

## Integration with Other Phases

### Prerequisites (Must Complete First)
- ✅ **Phase 2: Sizing** - Determines VM cluster size and count
- ✅ **Phase 3: Marketplace Offering** - Confirms deployment model
- ✅ **Phase 4: Architecture Validation** - Validates network topology

### Following Phases (Depend on CIDR Planning)
- **Phase 6: Infrastructure as Code** - Uses CIDR ranges in Terraform/Bicep
- **Phase 7: Deployment** - Applies network configuration to Azure
- **Phase 8: CI/CD Pipeline** - References CIDR in pipeline variables

---

## Example Output: Artifacts/CIDR Definition.md

```markdown
# CIDR Range Definition for Oracle Database@Azure

**Generated Date**: 2026-01-09
**Deployment Region**: East US
**Exadata Version**: Oracle Exadata X9M

## Configuration Summary

- **Number of VM Clusters**: 2 (current) + 1 (planned) = 3 total capacity
- **VMs per Cluster**: 3
- **Autonomous Database**: No
- **Growth Buffer**: 75%

## Calculated IP Requirements

### Client Subnet
- VMs: 2 clusters × 3 VMs × 4 IPs = 24 IPs
- SCANs: 2 clusters × 3 IPs = 6 IPs
- Networking Services: 13 IPs
- **Total Required**: 43 IPs
- **With 75% Buffer**: 76 IPs
- **Recommended CIDR Size**: /25 (111 usable IPs after reserved)

### Backup Subnet
- VMs: 2 clusters × 3 VMs × 3 IPs = 18 IPs
- Networking Services: 3 IPs
- **Total Required**: 21 IPs
- **With 75% Buffer**: 37 IPs
- **Recommended CIDR Size**: /26 (61 usable IPs after reserved)

## Assigned CIDR Ranges

| Subnet Type   | CIDR Range    | Usable IPs | Purpose                        |
|---------------|---------------|------------|--------------------------------|
| Client Subnet | 10.0.10.0/25  | 125 total (111 after reserved) | VM cluster client connectivity |
| Backup Subnet | 10.0.11.0/26  | 64 total (61 after reserved)   | Backup network traffic         |

## Network Constraints

- ✅ No overlap with existing VNet CIDR: 10.0.0.0/16
- ✅ No conflict with management subnet: 10.0.0.0/24
- ✅ No conflict with gateway subnet: 10.0.1.0/24
- ✅ No conflict with East US 2 peered VNet: 10.1.0.0/16
- ✅ Reserved ranges avoided: 100.106.0.0/16, 100.107.0.0/16 (X9M interconnect)
- ✅ Future growth capacity: 75% buffer included (capacity for 3 total clusters)

## Validation Checklist

- [ ] CIDR ranges reviewed by network team
- [ ] No conflicts with existing Azure resources confirmed
- [ ] Growth capacity sufficient for 12-24 months verified
- [ ] Multi-zone deployment requirements validated
- [ ] Cross-region connectivity to East US 2 verified (10.1.0.0/16)
- [ ] X9M reserved ranges verified as not in use
- [ ] Security team approval obtained
- [ ] CSA architecture review completed

## Next Steps

1. Review and validate CIDR assignments with network team
2. Update Azure Virtual Network documentation
3. Proceed to Phase 6: Infrastructure as Code generation
4. Configure NSGs and route tables for the defined subnets
5. Update network diagrams with allocated CIDR ranges
```

---

## Pro Tips

1. **Always include growth buffer** - 50-100% is recommended
2. **Use /25 or larger** for client subnets (not minimum /27)
3. **Document everything** - Future teams will thank you
4. **Validate cross-region** - Check all peered VNets for conflicts
5. **Consider Autonomous DB** - Reserve space even if not immediate need
6. **Check X9M ranges** - Always avoid 100.106.0.0/16 and 100.107.0.0/16
7. **Review with network team** - Get approval before IaC generation
8. **Update regularly** - Revisit CIDR plan as requirements change

---

## Troubleshooting Common Issues

### Issue: "Not enough IPs in subnet"
**Cause**: CIDR size too small or reserved IPs not accounted for  
**Solution**: Use the calculated recommendations, allocate /25 for client, /26 for backup

### Issue: "Routing conflicts with peered network"
**Cause**: Overlapping CIDR ranges between regions  
**Solution**: Coordinate address spaces, use different /16 ranges per region

### Issue: "Can't use 100.106.x.x range"
**Cause**: Reserved for Oracle Exadata X9M interconnect  
**Solution**: Use private address space from 10.0.0.0/8, 172.16.0.0/12, or 192.168.0.0/16

### Issue: "Subnet too small for growth"
**Cause**: Minimum CIDR size selected without buffer  
**Solution**: Follow Microsoft guidance, allocate /25 instead of /27 for client subnet

---

## Quick Reference: CIDR Sizes

| Notation | IPs    | Example Use Case |
|----------|--------|------------------|
| /28      | 16     | Too small for ODAA |
| /27      | 32     | Minimum (not recommended) |
| /26      | 64     | Good for small deployments |
| /25      | 128    | **Recommended for client subnet** |
| /24      | 256    | Large deployments, multi-cluster |
| /23      | 512    | Enterprise scale |

---

## Next Steps

1. ✅ Copy the prompt example at the top
2. ✅ Customize with your specific VM cluster configuration
3. ✅ Paste into GitHub Copilot or AI chat with @CIDR-Planning-Prompt.md
4. ✅ Review the generated CIDR Definition.md file
5. ✅ Validate with network team
6. ✅ Obtain necessary approvals
7. ✅ Proceed to Phase 6: Infrastructure as Code generation

---

**Ready to plan your CIDR ranges?** Use the prompt example at the top of this file! 🎯
