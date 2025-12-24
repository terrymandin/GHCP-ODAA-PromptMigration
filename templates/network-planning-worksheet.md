# Network Planning Worksheet for Oracle Database @ Azure Exadata

## Project Information
- **Project Name:** ___________________________
- **Date:** ___________________________
- **Network Engineer:** ___________________________

## Azure Virtual Network Configuration

### VNet Details
- **VNet Name:** ___________________________
- **VNet CIDR Block:** ___________________________ (Recommended: /16)
- **Azure Region:** ___________________________
- **Resource Group:** ___________________________

### Subnet Planning

#### Client Subnet
- **Name:** ___________________________
- **CIDR:** ___________________________ (Recommended: /24)
- **Gateway:** ___________________________
- **Usable Range:** ___________________________
- **Purpose:** Application servers, database clients

#### Exadata Infrastructure Subnet
- **Name:** ___________________________
- **CIDR:** ___________________________ (Recommended: /24 or /23)
- **Gateway:** ___________________________
- **Usable Range:** ___________________________
- **Purpose:** Exadata nodes, VIPs, SCAN IPs

#### Backup Subnet
- **Name:** ___________________________
- **CIDR:** ___________________________ (Recommended: /26)
- **Gateway:** ___________________________
- **Usable Range:** ___________________________
- **Purpose:** Backup operations, OCI connectivity

#### Management Subnet
- **Name:** ___________________________
- **CIDR:** ___________________________ (Recommended: /27)
- **Gateway:** ___________________________
- **Usable Range:** ___________________________
- **Purpose:** Bastion hosts, jump boxes

## DNS Configuration

### Private DNS Zone
- **Zone Name:** ___________________________ (e.g., exadata.internal)
- **Linked to VNet:** Yes / No

### SCAN Configuration
- **SCAN Name:** ___________________________ (e.g., exadb-scan.exadata.internal)
- **SCAN IP 1:** ___________________________
- **SCAN IP 2:** ___________________________
- **SCAN IP 3:** ___________________________

### Database VIPs
- **Node 1 VIP:** ___________________________
- **Node 2 VIP:** ___________________________
- **Cluster VIP:** ___________________________

## Network Security Groups (NSGs)

### Client Subnet NSG Rules
- [ ] Allow Oracle TNS (1521-1526) from VirtualNetwork
- [ ] Allow HTTPS (443) from VirtualNetwork
- [ ] Allow SSH (22) from Management Subnet
- [ ] Deny all other inbound traffic

### Exadata Subnet NSG Rules
- [ ] Allow Oracle TNS from Client Subnet
- [ ] Allow SSH from Management Subnet
- [ ] Allow all traffic within Exadata Subnet
- [ ] Deny all other inbound traffic

## Connectivity

### Option Selected
- [ ] ExpressRoute
- [ ] VPN Gateway
- [ ] Both (Hybrid)

### ExpressRoute Configuration (if applicable)
- **Circuit Name:** ___________________________
- **Bandwidth:** ___________________________ (e.g., 1 Gbps, 10 Gbps)
- **Peering Location:** ___________________________
- **Service Provider:** ___________________________
- **Primary Subnet:** ___________________________ (e.g., 10.200.1.0/30)
- **Secondary Subnet:** ___________________________ (e.g., 10.200.1.4/30)
- **Peer ASN:** ___________________________

### VPN Gateway Configuration (if applicable)
- **Gateway Name:** ___________________________
- **SKU:** ___________________________ (e.g., VpnGw2)
- **Gateway Subnet:** ___________________________ (Must be /27 or larger)
- **Gateway Public IP:** ___________________________
- **Local Network Gateway Name:** ___________________________
- **On-Premises Public IP:** ___________________________
- **On-Premises Address Space:** ___________________________

## IP Conflict Check

### Existing Networks to Avoid
- **Corporate Network:** ___________________________
- **Remote Sites:** ___________________________
- **Other Cloud Networks:** ___________________________
- **VPN Ranges:** ___________________________

### Verification
- [ ] No conflicts with existing networks
- [ ] DNS resolution tested
- [ ] Routing tables updated
- [ ] Firewall rules configured

## Validation Checklist
- [ ] VNet created with correct CIDR
- [ ] All subnets created and properly sized
- [ ] NSGs configured and associated
- [ ] DNS zone created and linked
- [ ] Connectivity method configured and tested
- [ ] No IP conflicts
- [ ] Network diagram created
- [ ] Security team approval obtained
- [ ] Network team approval obtained

## Approval

### Reviewed By
- **Network Architect:** ___________________________ Date: _______________
- **Security Team:** ___________________________ Date: _______________
- **Cloud Architect:** ___________________________ Date: _______________

### Notes
```
_________________________________________________________________
_________________________________________________________________
_________________________________________________________________
```
