---
mode: agent
description: Phase 5 - CIDR range planning for Oracle Database@Azure
---

# Phase 5: CIDR Range Planning for Oracle Database@Azure

## Objective
Generate appropriate CIDR ranges for Oracle Database@Azure deployment subnets (client and backup) based on the planned virtual machine cluster configuration and Azure networking best practices.

## Prerequisites
Before running this prompt, ensure you have:
- Completed sizing assessment (Phase 2)
- Architecture design session with CSA completed
- Network topology design approved
- Existing Azure Virtual Network information (if applicable)

## Required Parameters

You will need to provide the following information:

### Virtual Machine Cluster Configuration
1. **Number of VM Clusters**: How many VM clusters will be deployed? (minimum: 1)
2. **VMs per Cluster**: How many virtual machines in each cluster? (minimum: 2, typical: 2-4)
3. **Growth Planning**: Expected number of additional clusters in the next 12-24 months?
4. **High Availability Requirements**: Multi-zone or multi-region deployment?

### Network Context
5. **Existing VNet CIDR**: What is the existing Azure Virtual Network CIDR range? (e.g., 10.0.0.0/16)
6. **Reserved IP Ranges**: Are there any IP ranges already in use or reserved?
7. **Cross-Region Connectivity**: Will this connect to other Azure regions or on-premises networks?
8. **Autonomous Database**: Will Oracle Autonomous Database be deployed? (yes/no)

### Deployment Type
9. **Exadata Version**: Oracle Exadata X9M or other version?
10. **Deployment Region**: Which Azure region(s) for deployment?

## Instructions

### Step 1: Gather Information
Start by gathering the required parameters from the user through a series of questions. Validate that:
- Number of VM clusters is at least 1
- VMs per cluster is at least 2
- CIDR ranges don't overlap with existing networks
- For Oracle Exadata X9M, account for reserved ranges: 100.106.0.0/16 and 100.107.0.0/16

### Step 2: Leverage Best Practices
Use the MCP server to fetch and apply best practices from:
- [Plan IP address space for Oracle Database@Azure](https://learn.microsoft.com/en-us/azure/oracle/oracle-db/oracle-database-plan-ip)

Calculate IP requirements based on Microsoft documentation:

**Client Subnet Requirements:**
- 4 IP addresses per VM
- 3 IP addresses for SCANs per VM cluster
- 13 IP addresses reserved for networking services

**Backup Subnet Requirements:**
- 3 IP addresses per VM
- 3 IP addresses reserved for networking services

**Autonomous Database (if applicable):**
- Minimum CIDR size: /27

### Step 3: Calculate CIDR Ranges
Based on the requirements, calculate:

1. **Total IP Requirements**:
   - Client subnet: (Number of clusters Ã— ((VMs per cluster Ã— 4) + 3)) + 13
   - Backup subnet: (Number of clusters Ã— (VMs per cluster Ã— 3)) + 3

2. **Recommended CIDR Size** (with growth buffer):
   - Add 50-100% buffer for future growth
   - Follow Microsoft recommendation: Allocate at least /25 instead of /27 to reduce relative effect of reserved IPs
   - Consider table from documentation showing CIDR capacity

3. **Subnet Allocation**:
   - Client subnet CIDR
   - Backup subnet CIDR
   - Autonomous Database subnet CIDR (if applicable)

### Step 4: Validate Against Constraints
Ensure the calculated ranges:
- âœ“ Don't overlap with existing VNet CIDRs
- âœ“ Don't use reserved ranges (100.106.0.0/16, 100.107.0.0/16 for X9M)
- âœ“ Provide sufficient capacity for current and future needs
- âœ“ Meet minimum CIDR size requirements
- âœ“ Account for cross-region routing requirements

### Step 5: Generate CIDR Definition Document
Create or update the file `Artifacts/Phase5-CIDR/CIDR-Definition.md` with the following structure:

```markdown
# CIDR Range Definition for Oracle Database@Azure

**Generated Date**: [Current Date]
**Deployment Region**: [Region]
**Exadata Version**: [Version]

## Configuration Summary

- **Number of VM Clusters**: [X]
- **VMs per Cluster**: [X]
- **Autonomous Database**: [Yes/No]
- **Growth Buffer**: [X]%

## Calculated IP Requirements

### Client Subnet
- VMs: [X clusters] Ã— [X VMs] Ã— 4 IPs = [X] IPs
- SCANs: [X clusters] Ã— 3 IPs = [X] IPs
- Networking Services: 13 IPs
- **Total Required**: [X] IPs
- **Recommended CIDR Size**: /[X] ([X] usable IPs)

### Backup Subnet
- VMs: [X clusters] Ã— [X VMs] Ã— 3 IPs = [X] IPs
- Networking Services: 3 IPs
- **Total Required**: [X] IPs
- **Recommended CIDR Size**: /[X] ([X] usable IPs)

### Autonomous Database Subnet (if applicable)
- **Minimum CIDR Size**: /27

## Assigned CIDR Ranges

| Subnet Type | CIDR Range | Usable IPs | Purpose |
|-------------|------------|------------|---------|
| Client Subnet | [e.g., 10.0.1.0/25] | [X] | VM cluster client connectivity |
| Backup Subnet | [e.g., 10.0.2.0/26] | [X] | Backup network traffic |
| Autonomous DB Subnet | [e.g., 10.0.3.0/27] | [X] | Autonomous Database (if applicable) |

## Reserved IP Addresses

### Client Subnet Reserved IPs
For subnet [CIDR]:
- [First 4 IPs]: 10.0.1.0 - 10.0.1.3
- [9th to 16th IPs]: 10.0.1.8 - 10.0.1.15
- [Last IP]: 10.0.1.255

### Backup Subnet Reserved IPs
For subnet [CIDR]:
- [First IP]: [x.x.x.0]
- [Second IP]: [x.x.x.1]
- [Last IP]: [x.x.x.255]

## Network Constraints

- âœ“ No overlap with existing VNet CIDR: [VNet CIDR]
- âœ“ Reserved ranges avoided: 100.106.0.0/16, 100.107.0.0/16 (X9M)
- âœ“ Cross-region routing accounted for: [Yes/No]
- âœ“ Future growth capacity: [X]% buffer included

## Validation Checklist

- [ ] CIDR ranges reviewed by network team
- [ ] No conflicts with existing Azure resources
- [ ] Growth capacity sufficient for 12-24 months
- [ ] High availability requirements met
- [ ] Cross-region connectivity verified
- [ ] Security team approval obtained
- [ ] CSA architecture review completed

## Reference Documentation

- [Plan IP address space for Oracle Database@Azure](https://learn.microsoft.com/en-us/azure/oracle/oracle-db/oracle-database-plan-ip)
- [Network planning for Oracle Database@Azure](https://learn.microsoft.com/en-us/azure/oracle/oracle-db/oracle-database-network-plan)
- [Design an IP addressing schema for Azure](https://learn.microsoft.com/en-us/training/modules/design-ip-addressing-for-azure/)

## Next Steps

1. Review and validate CIDR assignments with network team
2. Update Azure Virtual Network configuration
3. Proceed to Phase 6: Infrastructure as Code generation
4. Configure NSGs and route tables for the defined subnets

---

**Notes**: 
- Maintain buffer capacity for future expansion
- Consider multi-region disaster recovery requirements
- Document any deviations from recommendations with justification
```

## Example Usage

```
/phase5-cidr

Please provide the following information for CIDR planning:

1. How many VM clusters will be deployed? 2
2. How many VMs per cluster? 3
3. Expected additional clusters in next 12-24 months? 1
4. Existing Azure VNet CIDR? 10.0.0.0/16
5. Any reserved IP ranges? 10.0.0.0/24 (management)
6. Cross-region connectivity needed? Yes, to East US 2
7. Deploy Oracle Autonomous Database? No
8. Exadata version? X9M
9. Deployment region? East US
```

## Success Criteria

âœ“ CIDR ranges calculated based on VM cluster requirements
âœ“ Growth buffer (50-100%) included in calculations
âœ“ No overlap with existing network ranges
âœ“ Reserved IP ranges properly documented
âœ“ Meets minimum CIDR size requirements from Microsoft documentation
âœ“ `Artifacts/Phase5-CIDR/CIDR Definition.md` file created with complete specifications
âœ“ Validation checklist included for team review
âœ“ References to official Microsoft documentation included

## Notes

- Always allocate more space than the minimum requirement (e.g., /25 instead of /27)
- Account for Azure networking service reserved IPs
- Consider future expansion and multi-region scenarios
- Validate against Oracle Database@Azure interconnect reserved ranges for X9M
- Document assumptions and constraints clearly

## Related Phases

- **Previous**: Phase 4 - Architecture Validation
- **Next**: Phase 6 - Infrastructure as Code Generation
- **Reference**: Phase 2 - Sizing (for VM cluster requirements)
