# Oracle Exadata to Azure Exadata Migration Framework

A comprehensive prompt-based framework for Cloud Solution Architects (CSAs) migrating Oracle Exadata workloads from on-premises to Oracle Database @ Azure Exadata.

## Overview

This framework provides end-to-end guidance for migrating Oracle Exadata databases to Azure, including:

- **AWR-based Sizing**: Methodology for right-sizing Azure Exadata infrastructure
- **CIDR Planning**: Network design and IP address planning
- **Infrastructure as Code**: Terraform templates for automated provisioning
- **Migration Tool Selection**: Decision tree and comparison of migration approaches
- **Runbooks**: Step-by-step configuration guides for each migration tool

## Migration Tools Covered

| Tool | Downtime | Complexity | Best For |
|------|----------|------------|----------|
| **Zero Downtime Migration (ZDM)** | 5-30 minutes | Medium | Most migrations, minimal downtime required |
| **Data Pump** | 2-48 hours | Low | Simple migrations, databases < 10 TB |
| **Oracle GoldenGate** | < 5 minutes | High | 24/7 systems, near-zero downtime required |
| **Transportable Tablespaces (TTS)** | 2-12 hours | Medium | Very large databases > 5 TB |

## Quick Start

### Step 1: Assessment and Sizing
Start with AWR-based sizing to determine your Azure Exadata requirements:

📖 **[AWR-Based Sizing Guide](docs/01-AWR-Sizing-Guide.md)**

- Generate AWR reports from source database
- Analyze CPU, memory, storage, and I/O metrics
- Calculate Azure Exadata shape requirements
- Document sizing recommendations

### Step 2: Network Planning
Design your Azure network infrastructure:

📖 **[CIDR Planning Guide](docs/02-CIDR-Planning-Guide.md)**

- Plan VNet and subnet CIDR blocks
- Configure Network Security Groups (NSGs)
- Set up DNS and connectivity options
- Avoid IP conflicts

### Step 3: Infrastructure Provisioning
Deploy Azure infrastructure using IaC:

📖 **[IaC Environment Generation](docs/03-IaC-Environment-Generation.md)**

- Terraform configurations for Azure resources
- Module structure for networking, security, and Exadata
- Environment-specific configurations (dev, staging, prod)
- CI/CD pipeline integration

### Step 4: Choose Migration Tool
Select the appropriate migration tool:

📖 **[Migration Tool Selection Guide](docs/04-Migration-Tool-Selection.md)**

Use the decision tree to select:
- **ZDM** - Recommended for most migrations
- **Data Pump** - Simple, full database exports
- **GoldenGate** - Minimal downtime required
- **TTS** - Large databases, cross-platform

### Step 5: Execute Migration
Follow the detailed runbook for your chosen tool:

📖 **Migration Runbooks:**
- **[Zero Downtime Migration (ZDM)](docs/05-ZDM-Configuration.md)** - Automated migration with minimal downtime
- **[Data Pump](docs/06-DataPump-Configuration.md)** - Traditional export/import approach  
- **[Oracle GoldenGate](docs/07-GoldenGate-Configuration.md)** - Real-time replication
- **[Transportable Tablespaces (TTS)](docs/08-TTS-Configuration.md)** - Physical datafile transport

## Repository Structure

```
GHCP-ODAA-PromptMigration/
├── README.md                          # This file
├── docs/
│   ├── 01-AWR-Sizing-Guide.md        # Database sizing methodology
│   ├── 02-CIDR-Planning-Guide.md     # Network design and planning
│   ├── 03-IaC-Environment-Generation.md  # Terraform templates
│   ├── 04-Migration-Tool-Selection.md    # Tool comparison and selection
│   ├── 05-ZDM-Configuration.md       # ZDM runbook
│   ├── 06-DataPump-Configuration.md  # Data Pump runbook
│   ├── 07-GoldenGate-Configuration.md    # GoldenGate runbook
│   └── 08-TTS-Configuration.md       # TTS runbook
├── templates/                         # Configuration templates
└── scripts/                          # Automation scripts

```

## Migration Decision Tree

```
Do you require near-zero downtime (< 5 minutes)?
│
├─ Yes → Database > 10 TB?
│   ├─ Yes → Use GoldenGate
│   └─ No  → Use ZDM
│
└─ No → Acceptable downtime?
    ├─ Hours (< 8) → Database size?
    │   ├─ < 5 TB  → Use Data Pump
    │   └─ > 5 TB  → Use TTS
    └─ Days → Use Data Pump
```

## Migration Phases

Every migration follows these phases:

### 1. Assessment (1-2 weeks)
- Database sizing and analysis
- Tool selection
- Risk assessment
- Timeline development

### 2. Preparation (2-4 weeks)
- Infrastructure provisioning
- Tool installation and configuration
- Test migration (non-production)
- Runbook development

### 3. Testing (2-4 weeks)
- Full test migration
- Performance validation
- Application testing
- Rollback testing

### 4. Production Migration (1 week)
- Final pre-migration checks
- Execute migration
- Validation
- Cutover

### 5. Post-Migration (2-4 weeks)
- Performance monitoring
- Issue resolution
- Optimization
- Documentation

## Key Features

### Comprehensive Sizing
- AWR report analysis methodology
- CPU, memory, storage, and I/O calculations
- Shape selection matrices
- Growth planning considerations

### Network Design
- VNet and subnet planning
- CIDR block calculations
- NSG rule templates
- DNS and connectivity patterns

### Infrastructure as Code
- Terraform modules for Azure resources
- Environment-specific configurations
- CI/CD pipeline integration
- Best practices and security

### Multiple Migration Paths
- Four migration tools covered
- Decision tree for tool selection
- Detailed step-by-step runbooks
- Troubleshooting guides

## Prerequisites

### General Requirements
- Oracle Exadata source database (11.2.0.4+)
- Azure subscription with appropriate permissions
- Network connectivity (ExpressRoute or VPN recommended)
- DBA expertise with Oracle databases

### Tool-Specific Requirements

**For ZDM:**
- Oracle support license
- ZDM service host (Linux, 16GB RAM, 500GB disk)
- SSH connectivity between source, target, and ZDM host

**For Data Pump:**
- Sufficient disk space (1.5x database size)
- Data Pump privileges
- Network or shared storage

**For GoldenGate:**
- GoldenGate licenses
- Supplemental logging enabled
- Archive log mode enabled
- Low-latency network (< 50ms recommended)

**For TTS:**
- Self-contained tablespaces
- Platform compatibility
- Sufficient staging storage

## Best Practices

### Planning
1. **Always test first** - Perform test migration before production
2. **Size appropriately** - Include growth projections (12-24 months)
3. **Plan for rollback** - Have documented rollback procedures
4. **Communication** - Keep stakeholders informed throughout

### Execution
1. **Monitor continuously** - Track progress and performance
2. **Validate thoroughly** - Check row counts, object counts, and performance
3. **Document everything** - Maintain detailed logs and notes
4. **Test applications** - Verify application functionality before cutover

### Post-Migration
1. **Gather statistics** - Run DBMS_STATS after migration
2. **Monitor performance** - Compare AWR reports to baseline
3. **Optimize as needed** - Tune based on Azure Exadata characteristics
4. **Maintain backups** - Keep source backups until fully validated

## Validation Checklist

After any migration, verify:

- [ ] Target database open in READ WRITE mode
- [ ] All objects migrated and valid
- [ ] Row counts match source database
- [ ] Application connectivity verified
- [ ] Performance metrics acceptable
- [ ] No errors in alert logs
- [ ] Backup and recovery tested
- [ ] Monitoring configured
- [ ] Documentation updated
- [ ] Rollback plan tested

## Support and Troubleshooting

### Common Issues

**Network Connectivity**
- Verify firewall rules and NSG configurations
- Test connectivity with telnet/tnsping
- Check bandwidth and latency

**Performance Issues**
- Gather AWR reports and compare to baseline
- Check for missing indexes or statistics
- Review initialization parameters

**Application Errors**
- Verify connection strings updated
- Check for invalid objects
- Review application logs

### Getting Help

- Oracle Support: [https://support.oracle.com/](https://support.oracle.com/)
- Azure Support: [https://portal.azure.com/](https://portal.azure.com/)
- Oracle Database @ Azure Documentation: [https://docs.oracle.com/](https://docs.oracle.com/)
- Azure Documentation: [https://docs.microsoft.com/azure/](https://docs.microsoft.com/azure/)

## Contributing

This framework is designed to be adapted to your specific migration needs. Feel free to:

- Customize the Terraform templates for your environment
- Modify runbooks based on your procedures
- Add organization-specific checklists and requirements
- Incorporate lessons learned from your migrations

## Timeline Estimates

| Database Size | Tool | Preparation | Migration Window | Total Duration |
|--------------|------|-------------|------------------|----------------|
| < 1 TB | Data Pump | 1 week | 2-4 hours | 2-3 weeks |
| < 1 TB | ZDM | 2 weeks | 5-15 minutes | 3-4 weeks |
| 1-10 TB | Data Pump | 2 weeks | 12-24 hours | 4-6 weeks |
| 1-10 TB | ZDM | 2 weeks | 15-30 minutes | 4-6 weeks |
| 10-50 TB | TTS | 3 weeks | 4-12 hours | 6-8 weeks |
| 10-50 TB | GoldenGate | 4 weeks | < 5 minutes | 8-12 weeks |
| > 50 TB | GoldenGate | 6 weeks | < 5 minutes | 12-16 weeks |

*Times include assessment, preparation, testing, and production migration*

## Security Considerations

- **Encryption**: Enable TDE (Transparent Data Encryption) on both source and target
- **Network Security**: Use NSGs, private endpoints, and Azure Firewall
- **Access Control**: Implement RBAC and database roles
- **Auditing**: Enable database and Azure audit logging
- **Compliance**: Follow industry-specific compliance requirements
- **Secrets Management**: Use Azure Key Vault for credentials

## Cost Optimization

- Right-size based on actual AWR metrics, not assumptions
- Use Azure Reserved Instances for predictable workloads
- Implement auto-scaling where appropriate
- Monitor and optimize storage usage
- Review Azure Advisor recommendations regularly

## Success Stories

This framework has been designed based on best practices from numerous successful Oracle Exadata to Azure migrations, incorporating lessons learned and proven patterns.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Oracle Database @ Azure product team
- Azure Architecture Center
- Oracle migration specialists and DBAs
- Cloud Solution Architects community

---

## Quick Reference Card

### Migration Tool Selection

| Your Requirement | Recommended Tool |
|-----------------|------------------|
| Minimum downtime | GoldenGate or ZDM |
| Simple migration | Data Pump |
| Large database (> 10 TB) | TTS or GoldenGate |
| Complex schema | ZDM or GoldenGate |
| Budget-conscious | Data Pump or TTS |
| Heterogeneous platforms | Data Pump or GoldenGate |

### Phase Durations

| Phase | Duration |
|-------|----------|
| AWR Sizing | 1-3 days |
| CIDR Planning | 2-5 days |
| IaC Provisioning | 1-2 weeks |
| Tool Setup | 3-7 days |
| Test Migration | 1-2 weeks |
| Production Migration | 1-7 days |

### Key Contacts

During your migration, maintain contact with:
- Oracle Support
- Azure Support
- Network team
- Security team
- Application teams
- Business stakeholders

---

**Ready to start your migration?** Begin with the [AWR-Based Sizing Guide](docs/01-AWR-Sizing-Guide.md)!
