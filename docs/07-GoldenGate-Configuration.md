# Oracle GoldenGate Configuration Runbook

## Overview
Oracle GoldenGate enables near-zero downtime migration through continuous real-time replication. Ideal for mission-critical databases requiring minimal downtime.

## Prerequisites Checklist
- [ ] GoldenGate 19c or later software
- [ ] Source database in ARCHIVELOG mode
- [ ] Supplemental logging enabled
- [ ] Network connectivity with low latency (< 50ms)
- [ ] Sufficient disk space for trail files (3x daily change rate)
- [ ] Database compatibility (11.2+)

## When to Use GoldenGate
- Downtime requirement: < 5 minutes
- Database size: Any (especially > 10 TB)
- 24/7 production systems
- Continuous replication needed
- Heterogeneous migrations

## Architecture
```
Source DB → Extract Process → Trail Files → Data Pump → 
→ Trail Files → Replicat Process → Target DB
```

## Phase 1: GoldenGate Installation (1-2 hours)

### Step 1.1: Install GoldenGate on Source
```bash
# Download GoldenGate 19c for Oracle
unzip OGG_<version>_Oracle_<platform>.zip

# Create GoldenGate directories
mkdir -p /u01/app/oracle/product/gg
cd /u01/app/oracle/product/gg

# Run installer
./runInstaller

# Create subdirectories
cd /u01/app/oracle/product/gg
./ggsci
GGSCI> CREATE SUBDIRS
```

### Step 1.2: Install GoldenGate on Target
```bash
# Repeat installation on Azure Exadata target
# Same version as source
unzip OGG_<version>_Oracle_<platform>.zip
mkdir -p /u01/app/oracle/product/gg
cd /u01/app/oracle/product/gg
./ggsci
GGSCI> CREATE SUBDIRS
```

### Step 1.3: Configure Manager Process
```bash
# On both source and target
cd /u01/app/oracle/product/gg
./ggsci

GGSCI> EDIT PARAMS MGR

# Add configuration:
PORT 7809
DYNAMICPORTLIST 7810-7820
AUTORESTART EXTRACT *, RETRIES 5, WAITMINUTES 3
PURGEOLDEXTRACTS ./dirdat/*, USECHECKPOINTS, MINKEEPDAYS 7
LAGREPORTHOURS 1
LAGINFOMINUTES 30
LAGCRITICALMINUTES 45

# Start Manager
GGSCI> START MGR
GGSCI> INFO MGR
```

## Phase 2: Database Preparation (1-2 hours)

### Step 2.1: Enable Supplemental Logging on Source
```sql
-- Connect as SYSDBA
sqlplus / as sysdba

-- Enable minimal supplemental logging (database level)
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;

-- Enable schema-level supplemental logging
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (PRIMARY KEY, UNIQUE KEY) COLUMNS;

-- Enable table-level supplemental logging
-- For each replicated table
ALTER TABLE schema.table_name ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;

-- Verify supplemental logging
SELECT supplemental_log_data_min, 
       supplemental_log_data_pk,
       supplemental_log_data_ui
FROM v$database;

SELECT owner, table_name, log_group_name, log_group_type
FROM dba_log_groups
WHERE owner = 'APP_SCHEMA';
```

### Step 2.2: Create GoldenGate Users
```sql
-- On source database
CREATE USER ggadmin IDENTIFIED BY "GGPassword123!";
GRANT CONNECT, RESOURCE TO ggadmin;
GRANT SELECT ANY DICTIONARY TO ggadmin;
GRANT FLASHBACK ANY TABLE TO ggadmin;
GRANT SELECT ANY TABLE TO ggadmin;
GRANT INSERT ANY TABLE TO ggadmin;  -- For initial load
GRANT UPDATE ANY TABLE TO ggadmin;
GRANT DELETE ANY TABLE TO ggadmin;
GRANT LOCK ANY TABLE TO ggadmin;

-- Enable GoldenGate replication
EXEC DBMS_GOLDENGATE_AUTH.GRANT_ADMIN_PRIVILEGE('GGADMIN');

-- On target database
CREATE USER ggadmin IDENTIFIED BY "GGPassword123!";
GRANT CONNECT, RESOURCE TO ggadmin;
GRANT SELECT ANY DICTIONARY TO ggadmin;
GRANT SELECT ANY TABLE TO ggadmin;
GRANT INSERT ANY TABLE TO ggadmin;
GRANT UPDATE ANY TABLE TO ggadmin;
GRANT DELETE ANY TABLE TO ggadmin;
GRANT UNLIMITED TABLESPACE TO ggadmin;

EXEC DBMS_GOLDENGATE_AUTH.GRANT_ADMIN_PRIVILEGE('GGADMIN');
```

### Step 2.3: Configure GLOBALS File
```bash
# On both source and target
cd /u01/app/oracle/product/gg
./ggsci

GGSCI> EDIT PARAMS ./GLOBALS

# Add:
GGSCHEMA ggadmin
CHECKPOINTTABLE ggadmin.ggcheckpoint
```

### Step 2.4: Create Checkpoint Table
```bash
# On target only
cd /u01/app/oracle/product/gg
./ggsci

GGSCI> DBLOGIN USERID ggadmin, PASSWORD GGPassword123!
GGSCI> ADD CHECKPOINTTABLE ggadmin.ggcheckpoint

# Verify
GGSCI> INFO CHECKPOINTTABLE ggadmin.ggcheckpoint
```

## Phase 3: Initial Load (Varies by Size)

### Step 3.1: Create Initial Load Extract
```bash
# On source
./ggsci
GGSCI> DBLOGIN USERID ggadmin, PASSWORD GGPassword123!

# Create special extract for initial load
GGSCI> ADD EXTRACT INITLOAD, SOURCEISTABLE

GGSCI> EDIT PARAMS INITLOAD

# Add configuration:
EXTRACT INITLOAD
USERID ggadmin, PASSWORD GGPassword123!
RMTHOST azureexadata01, MGRPORT 7809
RMTTASK REPLICAT, GROUP INITLOAD
TABLE HR.*;
TABLE SALES.*;
TABLE FINANCE.*;
```

### Step 3.2: Create Initial Load Replicat
```bash
# On target
./ggsci
GGSCI> DBLOGIN USERID ggadmin, PASSWORD GGPassword123!

GGSCI> ADD REPLICAT INITLOAD, SPECIALRUN

GGSCI> EDIT PARAMS INITLOAD

# Add configuration:
REPLICAT INITLOAD
USERID ggadmin, PASSWORD GGPassword123!
ASSUMETARGETDEFS
DISCARDFILE ./dirrpt/initload.dsc, PURGE
MAP HR.*, TARGET HR.*;
MAP SALES.*, TARGET SALES.*;
MAP FINANCE.*, TARGET FINANCE.*;
```

### Step 3.3: Execute Initial Load
```bash
# On source
./ggsci
GGSCI> START EXTRACT INITLOAD

# Monitor progress
GGSCI> INFO EXTRACT INITLOAD, DETAIL
GGSCI> STATS EXTRACT INITLOAD

# Check logs
GGSCI> VIEW REPORT INITLOAD
```

## Phase 4: Configure Change Data Capture (30 minutes)

### Step 4.1: Create Change Data Extract
```bash
# On source
./ggsci
GGSCI> DBLOGIN USERID ggadmin, PASSWORD GGPassword123!

# Add extract group
GGSCI> ADD EXTRACT EXTHR, INTEGRATED TRANLOG, BEGIN NOW
GGSCI> ADD EXTTRAIL ./dirdat/hr, EXTRACT EXTHR, MEGABYTES 500

GGSCI> EDIT PARAMS EXTHR

# Add configuration:
EXTRACT EXTHR
USERID ggadmin, PASSWORD GGPassword123!
EXTTRAIL ./dirdat/hr
TABLE HR.*;
TABLE SALES.*;
TABLE FINANCE.*;

# Register extract with database
GGSCI> REGISTER EXTRACT EXTHR DATABASE

# Start extract
GGSCI> START EXTRACT EXTHR
GGSCI> INFO EXTRACT EXTHR, DETAIL
```

### Step 4.2: Create Data Pump
```bash
# On source (pumps data to target)
./ggsci

GGSCI> ADD EXTRACT PUMPHR, EXTTRAILSOURCE ./dirdat/hr
GGSCI> ADD RMTTRAIL ./dirdat/hr, EXTRACT PUMPHR, MEGABYTES 500

GGSCI> EDIT PARAMS PUMPHR

# Add configuration:
EXTRACT PUMPHR
USERID ggadmin, PASSWORD GGPassword123!
RMTHOST azureexadata01, MGRPORT 7809
RMTTRAIL ./dirdat/hr
PASSTHRU
TABLE HR.*;
TABLE SALES.*;
TABLE FINANCE.*;

# Start pump
GGSCI> START EXTRACT PUMPHR
GGSCI> INFO EXTRACT PUMPHR, DETAIL
```

### Step 4.3: Create Replicat
```bash
# On target
./ggsci
GGSCI> DBLOGIN USERID ggadmin, PASSWORD GGPassword123!

GGSCI> ADD REPLICAT REPHR, INTEGRATED, EXTTRAIL ./dirdat/hr, CHECKPOINTTABLE ggadmin.ggcheckpoint

GGSCI> EDIT PARAMS REPHR

# Add configuration:
REPLICAT REPHR
USERID ggadmin, PASSWORD GGPassword123!
ASSUMETARGETDEFS
DISCARDFILE ./dirrpt/rephr.dsc, PURGE, MEGABYTES 500
MAP HR.*, TARGET HR.*;
MAP SALES.*, TARGET SALES.*;
MAP FINANCE.*, TARGET FINANCE.*;

# Start replicat
GGSCI> START REPLICAT REPHR
GGSCI> INFO REPLICAT REPHR, DETAIL
```

## Phase 5: Monitor Replication (Ongoing)

### Step 5.1: Check Replication Status
```bash
./ggsci

# Check all processes
GGSCI> INFO ALL

# Check replication lag
GGSCI> LAG EXTRACT EXTHR
GGSCI> LAG REPLICAT REPHR

# Detailed statistics
GGSCI> STATS EXTRACT EXTHR
GGSCI> STATS REPLICAT REPHR
```

### Step 5.2: Monitor with SQL
```sql
-- On source: Check extract status
SELECT component_name, component_type, status
FROM dba_goldengate_inbound;

-- On target: Check apply lag
SELECT apply_name, 
       ROUND(apply_lag/60,2) AS lag_minutes,
       ROUND(apply_time,2) AS apply_time_sec
FROM gv$goldengate_capture;
```

### Step 5.3: Verify Data Synchronization
```sql
-- Compare row counts (run on both source and target)
SELECT 'HR.EMPLOYEES' AS table_name, COUNT(*) FROM HR.EMPLOYEES
UNION ALL
SELECT 'SALES.ORDERS', COUNT(*) FROM SALES.ORDERS
UNION ALL
SELECT 'FINANCE.TRANSACTIONS', COUNT(*) FROM FINANCE.TRANSACTIONS;

-- Check for replication errors
SELECT * FROM ggadmin.ggcheckpoint ORDER BY checkpoint_time DESC;
```

## Phase 6: Switchover (< 5 minutes)

### Step 6.1: Pre-Switchover Validation
```bash
./ggsci

# Verify lag is minimal
GGSCI> LAG EXTRACT EXTHR
# Should be < 1 minute

GGSCI> LAG REPLICAT REPHR
# Should be < 1 minute

# Check for errors
GGSCI> VIEW REPORT EXTHR
GGSCI> VIEW REPORT REPHR
```

### Step 6.2: Quiesce Source Database
```sql
-- Stop application connections
ALTER SYSTEM ENABLE RESTRICTED SESSION;

-- Wait for active transactions to complete
SELECT COUNT(*) FROM v$transaction;

-- Verify no pending changes
SELECT COUNT(*) FROM dba_pending_transactions;
```

### Step 6.3: Final Synchronization
```bash
# Wait for extract to catch up
./ggsci
GGSCI> INFO EXTRACT EXTHR, DETAIL

# Wait for replicat to apply all changes
GGSCI> INFO REPLICAT REPHR, DETAIL

# Verify zero lag
GGSCI> LAG EXTRACT EXTHR
GGSCI> LAG REPLICAT REPHR
# Both should show: "At EOF, no more records to process"
```

### Step 6.4: Stop Replication
```bash
# Stop in order
GGSCI> STOP EXTRACT EXTHR
GGSCI> STOP EXTRACT PUMPHR
GGSCI> STOP REPLICAT REPHR

# Verify all stopped
GGSCI> INFO ALL
```

### Step 6.5: Activate Target Database
```sql
-- On target database
-- Enable application access
ALTER SYSTEM DISABLE RESTRICTED SESSION;

-- Gather statistics
EXEC DBMS_STATS.GATHER_DATABASE_STATS;

-- Verify database status
SELECT name, open_mode FROM v$database;
```

## Phase 7: Application Cutover

### Step 7.1: Update Connection Strings
```bash
# Update applications to point to target
# Update DNS or modify connection strings
# Test connectivity before full cutover
```

### Step 7.2: Restart Applications
```bash
systemctl restart application-service

# Monitor for errors
tail -f /var/log/application.log
```

## Phase 8: Post-Migration Cleanup

### Step 8.1: Remove GoldenGate Configuration (Optional)
```bash
# On source and target
./ggsci

# Delete extract/replicat
GGSCI> DELETE EXTRACT EXTHR
GGSCI> DELETE EXTRACT PUMPHR
GGSCI> DELETE REPLICAT REPHR

# Clean trail files
GGSCI> PURGE EXTTRAIL ./dirdat/*
GGSCI> PURGE RMTTRAIL ./dirdat/*
```

### Step 8.2: Disable Supplemental Logging (Source)
```sql
-- If no longer needed
ALTER DATABASE DROP SUPPLEMENTAL LOG DATA;

-- Remove table-level logging
SELECT 'ALTER TABLE '||owner||'.'||table_name||' DROP SUPPLEMENTAL LOG DATA (ALL) COLUMNS;'
FROM dba_log_groups
WHERE owner IN ('HR','SALES','FINANCE');
```

## Troubleshooting Guide

### Issue: Extract Abends
```bash
# Check extract report
GGSCI> VIEW REPORT EXTHR

# Common causes:
# - Missing supplemental logging
# - Insufficient disk space
# - Database connectivity issues

# Restart extract
GGSCI> START EXTRACT EXTHR
```

### Issue: High Replication Lag
```bash
# Check network bandwidth
iperf3 -c targethost

# Increase replicat parallelism
GGSCI> EDIT PARAMS REPHR
# Add: PARALLELREPLICAT 4

# Restart replicat
GGSCI> STOP REPLICAT REPHR
GGSCI> START REPLICAT REPHR
```

### Issue: Missing Trail Files
```bash
# Check trail file location and permissions
ls -la ./dirdat/

# Verify extract is writing
GGSCI> INFO EXTRACT EXTHR, SHOWCH

# Increase trail file retention
GGSCI> EDIT PARAMS MGR
# Modify: PURGEOLDEXTRACTS ./dirdat/*, USECHECKPOINTS, MINKEEPDAYS 14
```

### Issue: Replicat Errors
```sql
-- Check for conflicts
SELECT * FROM ggadmin.ggcheckpoint 
WHERE checkpoint_time > SYSDATE - 1
ORDER BY checkpoint_time DESC;

# View discard file
./ggsci
GGSCI> VIEW GGSEVT
```

## Performance Tuning

### Optimize Extract
```
EXTRACT EXTHR
TRANLOGOPTIONS INTEGRATEDPARAMS (max_sga_size 1024)
THREADOPTIONS MAXCOMMITPROPAGATIONDELAY 60000
```

### Optimize Replicat
```
REPLICAT REPHR
BATCHSQL
MAP schema.large_table, TARGET schema.large_table, BULK, BUFSIZE 1024000;
```

## Downtime Estimation

| Phase | Duration |
|-------|----------|
| Initial Load | 4-48 hours (depends on size) |
| Replication Setup | 1-2 hours |
| Synchronization | Ongoing (hours to days) |
| **Final Switchover** | **< 5 minutes** |

## Success Criteria
- [ ] All tables synchronized
- [ ] Replication lag < 1 minute before switchover
- [ ] Zero data loss verified
- [ ] Applications connected to target
- [ ] No replication errors
- [ ] Performance acceptable

## Additional Resources
- [Oracle GoldenGate Documentation](https://docs.oracle.com/en/middleware/goldengate/)
- [GoldenGate Best Practices (MOS Doc ID 1308324.1)](https://support.oracle.com/)
- [GoldenGate Performance Tuning](https://www.oracle.com/a/tech/docs/gg-performance-best-practices.pdf)
