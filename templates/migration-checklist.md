# Oracle Exadata to Azure Migration Checklist

## Pre-Migration Phase

### Assessment
- [ ] Source database version documented
- [ ] Database size measured
- [ ] AWR reports generated (7+ days)
- [ ] Peak and average workloads identified
- [ ] Application dependencies mapped
- [ ] Migration tool selected
- [ ] Risk assessment completed
- [ ] Rollback plan documented

### Sizing
- [ ] CPU requirements calculated
- [ ] Memory requirements calculated
- [ ] Storage requirements calculated
- [ ] Network bandwidth requirements determined
- [ ] Azure Exadata shape selected
- [ ] Cost estimate prepared and approved

### Network Planning
- [ ] VNet CIDR planned
- [ ] Subnet CIDRs allocated
- [ ] No IP conflicts verified
- [ ] NSG rules defined
- [ ] DNS configuration planned
- [ ] Connectivity method selected (ExpressRoute/VPN)
- [ ] Network diagram created
- [ ] Network change requests submitted

### Azure Subscription
- [ ] Azure subscription identified
- [ ] Resource group created
- [ ] RBAC permissions configured
- [ ] Azure policies reviewed
- [ ] Budget alerts configured
- [ ] Tagging strategy defined

### IaC Preparation
- [ ] Terraform installed and configured
- [ ] Azure CLI installed
- [ ] Service principal created
- [ ] Terraform state backend configured
- [ ] IaC code reviewed
- [ ] Test deployment successful

## Infrastructure Deployment Phase

### Azure Infrastructure
- [ ] Virtual Network created
- [ ] Subnets created
- [ ] NSGs created and associated
- [ ] Private DNS zone created
- [ ] ExpressRoute/VPN configured
- [ ] Azure Bastion deployed (if using)
- [ ] Monitoring configured

### Exadata Deployment
- [ ] Oracle Database @ Azure Exadata provisioned
- [ ] Database instances created
- [ ] RAC configuration completed (if applicable)
- [ ] TNS configuration completed
- [ ] Listener configuration verified
- [ ] Database parameters tuned
- [ ] Backup configuration completed

## Migration Tool Setup

### ZDM (if applicable)
- [ ] ZDM service host provisioned
- [ ] ZDM software installed
- [ ] SSH keys configured
- [ ] Network connectivity tested
- [ ] ZDM users created on source and target
- [ ] Response file created
- [ ] Test migration successful

### Data Pump (if applicable)
- [ ] Export directory created on source
- [ ] Import directory created on target
- [ ] Sufficient disk space verified
- [ ] Data Pump users created
- [ ] Parameter files created
- [ ] Test export successful
- [ ] Transfer method determined

### GoldenGate (if applicable)
- [ ] GoldenGate software installed on source
- [ ] GoldenGate software installed on target
- [ ] Manager process configured
- [ ] Supplemental logging enabled
- [ ] GoldenGate users created
- [ ] Extract process configured
- [ ] Replicat process configured
- [ ] Trail files location configured
- [ ] Test replication successful

### TTS (if applicable)
- [ ] Tablespaces identified for transport
- [ ] Self-containment verified
- [ ] Platform compatibility checked
- [ ] Export directory created
- [ ] Sufficient storage for datafiles verified
- [ ] Test transport successful

## Test Migration Phase

### Test Execution
- [ ] Test database created
- [ ] Test migration executed
- [ ] Migration duration measured
- [ ] Issues documented
- [ ] Runbook updated based on test
- [ ] Performance validated

### Application Testing
- [ ] Application connection strings updated (test)
- [ ] Application functionality tested
- [ ] Performance testing completed
- [ ] Load testing completed (if applicable)
- [ ] User acceptance testing completed
- [ ] Known issues documented

### Rollback Testing
- [ ] Rollback procedure documented
- [ ] Rollback test successful
- [ ] Rollback duration measured
- [ ] Recovery point objectives verified

## Production Migration Phase

### Pre-Migration
- [ ] Change request approved
- [ ] Stakeholders notified
- [ ] Maintenance window scheduled
- [ ] Application teams coordinated
- [ ] Full backup of source completed
- [ ] Backup verification successful
- [ ] Go/no-go meeting held
- [ ] Final migration plan reviewed

### Migration Execution (Day of)
- [ ] Pre-migration checklist completed
- [ ] Application connections quiesced
- [ ] Source database status verified
- [ ] Migration started
- [ ] Progress monitored continuously
- [ ] Issues logged and addressed
- [ ] Migration completed successfully

### Post-Migration Validation
- [ ] Target database open in READ WRITE mode
- [ ] All tablespaces online
- [ ] All objects valid
- [ ] Row counts verified
- [ ] Constraint verification completed
- [ ] Index verification completed
- [ ] Trigger verification completed
- [ ] Statistics gathered
- [ ] AWR snapshot taken
- [ ] No errors in alert log

### Application Cutover
- [ ] Connection strings updated
- [ ] DNS updated (if applicable)
- [ ] Applications restarted
- [ ] Application connectivity verified
- [ ] Smoke tests completed
- [ ] User access verified
- [ ] Batch jobs updated
- [ ] Monitoring alerts configured

## Post-Migration Phase

### Validation
- [ ] Full application testing completed
- [ ] Performance compared to baseline
- [ ] No data loss verified
- [ ] All integrations working
- [ ] Backup and recovery tested
- [ ] High availability tested (if applicable)
- [ ] Disaster recovery tested (if applicable)

### Optimization
- [ ] AWR reports reviewed
- [ ] Performance tuning completed
- [ ] Indexes optimized
- [ ] Statistics refreshed
- [ ] SQL plans validated
- [ ] Resource usage optimized

### Documentation
- [ ] Migration summary documented
- [ ] As-built documentation created
- [ ] Runbook updated with lessons learned
- [ ] Known issues documented
- [ ] Operational procedures documented
- [ ] Troubleshooting guide updated
- [ ] Architecture diagram updated

### Decommissioning (After Validation Period)
- [ ] Source database backed up
- [ ] Source database archived
- [ ] Migration tools decommissioned
- [ ] Temporary resources removed
- [ ] Costs optimized
- [ ] Project closed

## Sign-Off

### Technical Sign-Off
- **Database Administrator:** ___________________________ Date: _______________
- **Application Owner:** ___________________________ Date: _______________
- **Cloud Architect:** ___________________________ Date: _______________
- **Network Engineer:** ___________________________ Date: _______________
- **Security Engineer:** ___________________________ Date: _______________

### Business Sign-Off
- **Business Owner:** ___________________________ Date: _______________
- **Project Manager:** ___________________________ Date: _______________

## Lessons Learned
```
_________________________________________________________________
_________________________________________________________________
_________________________________________________________________
_________________________________________________________________
_________________________________________________________________
```
