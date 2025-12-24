# Oracle to Azure Exadata Sizing Worksheet

## Project Information
- **Project Name:** ___________________________
- **Date:** ___________________________
- **Prepared By:** ___________________________
- **Review Date:** ___________________________

## Source Environment

### Database Details
- **Database Version:** ___________________________
- **Database Name:** ___________________________
- **Database Size (TB):** ___________________________
- **Number of Databases:** ___________________________
- **RAC Configuration:** Yes / No
- **Number of Nodes:** ___________________________

### Current Exadata Configuration
- **Model:** ___________________________
- **Rack Size:** Quarter / Half / Full
- **Number of Compute Nodes:** ___________________________
- **Number of Storage Servers:** ___________________________
- **Total OCPU:** ___________________________
- **Total Memory (GB):** ___________________________
- **Total Storage (TB):** ___________________________

## AWR Analysis Results

### CPU Metrics
- **Average CPU Utilization (%):** ___________________________
- **Peak CPU Utilization (%):** ___________________________
- **Number of CPUs Used:** ___________________________
- **CPU Wait Time:** ___________________________

### Memory Metrics
- **SGA Size (GB):** ___________________________
- **PGA Size (GB):** ___________________________
- **Buffer Cache Hit Ratio (%):** ___________________________
- **Shared Pool Size (GB):** ___________________________

### Storage Metrics
- **Current Database Size (TB):** ___________________________
- **Daily Growth Rate (GB/day):** ___________________________
- **Average IOPS (Read):** ___________________________
- **Average IOPS (Write):** ___________________________
- **Peak IOPS (Total):** ___________________________
- **Average Throughput (MB/s):** ___________________________
- **Peak Throughput (MB/s):** ___________________________

### Workload Characteristics
- **Transactions Per Second (Avg):** ___________________________
- **Transactions Per Second (Peak):** ___________________________
- **Average Sessions:** ___________________________
- **Peak Sessions:** ___________________________
- **Connection Rate:** ___________________________

## Growth Projections
- **Growth Period (months):** ___________________________
- **Expected Growth Rate (%):** ___________________________
- **Projected Size After Growth (TB):** ___________________________

## Azure Exadata Sizing Calculations

### Compute Sizing
```
Source Peak CPU Cores: ___________________________
Peak CPU Utilization: ___________________________
Target Utilization (70%): ___________________________
Growth Factor (15%): ___________________________

Recommended OCPUs = (Source_Cores × Peak_Util / 70) × 1.15
Calculated OCPUs: ___________________________
```

### Memory Sizing
```
Source SGA (GB): ___________________________
Source PGA (GB): ___________________________
Additional Buffer (15%): ___________________________

Recommended Memory = (SGA + PGA) × 1.15
Calculated Memory (GB): ___________________________
```

### Storage Sizing
```
Current Database Size (TB): ___________________________
Daily Growth (GB): ___________________________
Retention Period (days): ___________________________
Backup Space (100%): ___________________________

Recommended Storage = DB_Size + (Daily_Growth × Days × 365/12) + Backup_Space
Calculated Storage (TB): ___________________________
```

## Recommended Azure Exadata Configuration

### Selected Configuration
- **Shape:** Exadata.X8M / X9M . Quarter / Half / Full
- **Compute Nodes:** ___________________________
- **Total OCPU:** ___________________________
- **Total Memory (GB):** ___________________________
- **Total Storage (TB):** ___________________________

### Validation Against Requirements
- [ ] CPU: Target 60-70% average, 90% max peak
- [ ] Memory: Buffer cache hit ratio > 95%
- [ ] Storage: IOPS capacity > 2x current peak
- [ ] Network: Bandwidth > 1.5x current peak throughput

## Cost Estimate
- **Monthly Compute Cost:** $ ___________________________
- **Monthly Storage Cost:** $ ___________________________
- **Network Egress (if applicable):** $ ___________________________
- **Total Monthly Cost:** $ ___________________________
- **Annual Cost:** $ ___________________________

## Approval

### Reviewed By
- **Technical Lead:** ___________________________ Date: _______________
- **DBA Lead:** ___________________________ Date: _______________
- **Cloud Architect:** ___________________________ Date: _______________
- **Finance Approver:** ___________________________ Date: _______________

### Notes
```
_________________________________________________________________
_________________________________________________________________
_________________________________________________________________
_________________________________________________________________
```
