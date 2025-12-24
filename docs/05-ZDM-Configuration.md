# Zero Downtime Migration (ZDM) Configuration Runbook

## Overview
This runbook provides step-by-step instructions for Oracle Zero Downtime Migration from on-premises Exadata to Oracle Database @ Azure Exadata with minimal downtime.

## Prerequisites Checklist
- [ ] Source Exadata database (Oracle 11.2.0.4+)
- [ ] Target Azure Exadata provisioned
- [ ] ZDM service host (Linux server, 16GB RAM, 500GB disk)
- [ ] Network connectivity between source, target, ZDM host
- [ ] Oracle Database 19c+ and ZDM 21.x software
- [ ] SSH keys configured for passwordless authentication
- [ ] RMAN backup location with sufficient space

## Architecture
```
Source Exadata ←SSH/RMAN→ ZDM Service Host ←SSH/RMAN→ Target Azure Exadata
```

## Phase 1: ZDM Service Host Setup (30 minutes)

### Step 1.1: Install ZDM Software
```bash
# Download ZDM from Oracle Support (Patch 32484308)
unzip p32484308_210000_Linux-x86-64.zip
cd zdm21
./zdminstall.sh setup oraclehome=/u01/app/oracle/product/21.0.0/zdm

# Verify installation
/u01/app/oracle/product/21.0.0/zdm/bin/zdmcli -version
```

### Step 1.2: Start ZDM Service
```bash
export ZDM_HOME=/u01/app/oracle/product/21.0.0/zdm
$ZDM_HOME/bin/zdmservice start
$ZDM_HOME/bin/zdmservice status
```

### Step 1.3: Configure SSH Connectivity
```bash
# Generate SSH keys
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa_zdm

# Copy to all source and target nodes
for node in exadata01 exadata02 azureexadata01 azureexadata02; do
  ssh-copy-id -i ~/.ssh/id_rsa_zdm.pub oracle@$node
  ssh oracle@$node "hostname; date"  # Test connection
done
```

## Phase 2: Database Preparation (1-2 hours)

### Step 2.1: Prepare Source Database
```sql
-- Enable archive log mode if needed
ALTER DATABASE ARCHIVELOG;

-- Create ZDM user
CREATE USER zdmuser IDENTIFIED BY "ComplexPassword123!";
GRANT SYSDBA TO zdmuser;
GRANT SELECT ANY DICTIONARY TO zdmuser;

-- Verify database health
SELECT * FROM v$database;
SELECT COUNT(*) FROM dba_objects WHERE status != 'VALID';
```

### Step 2.2: Backup Source Database
```bash
rman target / << EOF
BACKUP AS COMPRESSED BACKUPSET 
  DATABASE PLUS ARCHIVELOG
  FORMAT '/backup/zdm/%U' 
  TAG 'PRE_ZDM_BACKUP';
EOF
```

### Step 2.3: Configure Target Database
```sql
-- On Azure Exadata
CREATE USER zdmuser IDENTIFIED BY "ComplexPassword123!";
GRANT SYSDBA TO zdmuser;
GRANT UNLIMITED TABLESPACE TO zdmuser;
```

### Step 2.4: Configure TNS Entries
```bash
# Edit tnsnames.ora on ZDM host
cat >> $ORACLE_HOME/network/admin/tnsnames.ora << 'EOF'
SOURCEDB =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = source-scan)(PORT = 1521))
    (CONNECT_DATA = (SERVICE_NAME = sourcedb))
  )

TARGETDB =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = target-scan)(PORT = 1521))
    (CONNECT_DATA = (SERVICE_NAME = targetdb))
  )
EOF

# Test connectivity
tnsping SOURCEDB && tnsping TARGETDB
```

## Phase 3: Create Migration Response File (15 minutes)

Create `/home/oracle/zdm_migration.rsp`:

```properties
# Source Configuration
SOURCEDB=SOURCEDB
SOURCENODE=exadata01
SOURCEHOME=/u01/app/oracle/product/19.0.0/dbhome_1
SRCAUTH=zdmauth
SRCARG1=user:zdmuser
SRCARG2=identity_file:/home/oracle/.ssh/id_rsa_zdm

# Target Configuration
TARGETDB=TARGETDB
TARGETNODE=azureexadata01
TARGETHOME=/u01/app/oracle/product/19.0.0/dbhome_1
TGTAUTH=zdmauth
TGTARG1=user:zdmuser
TGTARG2=identity_file:/home/oracle/.ssh/id_rsa_zdm

# Migration Settings
MIGRATION_METHOD=PHYSICAL_ONLINE
PLATFORM_TYPE=EXADATA
BACKUPPATH=/backup/zdm
DATAPUMPSETTINGS_DATAFILEPARALLEL=8
ZLIBCOMPRESS=TRUE
LOG_LEVEL=INFO
```

## Phase 4: Execute Migration (Varies)

### Step 4.1: Validate Configuration
```bash
# Test migration configuration
$ZDM_HOME/bin/zdmcli migrate database   -rsp /home/oracle/zdm_migration.rsp   -eval

# Review output for any errors
```

### Step 4.2: Start Migration Job
```bash
# Execute migration
$ZDM_HOME/bin/zdmcli migrate database   -rsp /home/oracle/zdm_migration.rsp   -sourcedb SOURCEDB   -targetdb TARGETDB

# Save the returned JOB_ID
export ZDM_JOB_ID=<returned-job-id>
```

### Step 4.3: Monitor Progress
```bash
# Continuous monitoring
watch -n 30 "$ZDM_HOME/bin/zdmcli query job -jobid $ZDM_JOB_ID"

# Check logs
tail -f $ZDM_HOME/zdm/log/zdm_${ZDM_JOB_ID}.log
```

## Phase 5: Switchover (5-15 minutes)

### Step 5.1: Pre-Switchover Checks
```bash
# Verify replication lag is minimal
$ZDM_HOME/bin/zdmcli query job -jobid $ZDM_JOB_ID | grep "Lag"
# Should be < 5 minutes

# Stop applications
systemctl stop application-service
```

### Step 5.2: Execute Switchover
```bash
$ZDM_HOME/bin/zdmcli switchover database -jobid $ZDM_JOB_ID

# Monitor switchover
watch -n 10 "$ZDM_HOME/bin/zdmcli query job -jobid $ZDM_JOB_ID"
```

### Step 5.3: Validate Migration
```sql
-- On target database
SELECT name, open_mode, database_role FROM v$database;
-- Expected: OPEN, READ WRITE, PRIMARY

SELECT COUNT(*) FROM dba_objects WHERE status = 'VALID';
SELECT tablespace_name, status FROM dba_tablespaces;
```

## Phase 6: Application Cutover (30 minutes)

### Step 6.1: Update Connection Strings
```bash
# Update application configuration
# Old: sourcedb.domain.com:1521/SOURCEDB
# New: targetdb.azure.com:1521/TARGETDB
```

### Step 6.2: Restart Applications
```bash
systemctl start application-service

# Test connectivity
sqlplus appuser/password@TARGETDB << EOF
SELECT 'Success' FROM dual;
EOF
```

## Phase 7: Post-Migration Tasks (1-2 hours)

### Step 7.1: Gather Statistics
```sql
EXEC DBMS_STATS.GATHER_DICTIONARY_STATS;
EXEC DBMS_STATS.GATHER_SCHEMA_STATS('APP_SCHEMA', CASCADE=>TRUE);
```

### Step 7.2: Configure Monitoring
```sql
EXEC DBMS_WORKLOAD_REPOSITORY.MODIFY_SNAPSHOT_SETTINGS(
  interval => 30, retention => 14
);
```

## Troubleshooting Guide

### Issue: SSH Connection Failure
```bash
ssh -vvv -i ~/.ssh/id_rsa_zdm oracle@targethost
# Check permissions: chmod 600 ~/.ssh/id_rsa_zdm
```

### Issue: Insufficient Disk Space
```bash
df -h /backup/zdm
# Clean old backups or expand storage
```

### Issue: Archive Log Lag
```bash
# Check network bandwidth
iperf3 -c targethost

# Increase parallelism in response file
DATAPUMPSETTINGS_DATAFILEPARALLEL=16
```

## Rollback Procedure

If issues arise:
```bash
$ZDM_HOME/bin/zdmcli rollback database -jobid $ZDM_JOB_ID
# This reopens source database and restores original configuration
```

## Success Criteria
- [ ] Target database in READ WRITE mode
- [ ] All objects valid
- [ ] Application connectivity verified
- [ ] Row counts match source
- [ ] Performance metrics acceptable
- [ ] No errors in alert log

## Timeline
- Setup: 2-3 hours
- Initial sync: 4-24 hours (depends on size)
- Switchover: 5-15 minutes
- Validation: 1-2 hours
- **Total downtime: 5-30 minutes**

## Additional Resources
- [Oracle ZDM Documentation](https://docs.oracle.com/en/database/oracle/zero-downtime-migration/)
- [ZDM Best Practices (MOS Doc ID 2694762.1)](https://support.oracle.com/)
