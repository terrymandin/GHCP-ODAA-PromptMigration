# Data Pump Configuration Runbook

## Overview
Oracle Data Pump provides a fast, simple method for migrating Oracle databases to Azure Exadata. Best for databases under 10TB with acceptable downtime windows of several hours.

## Prerequisites Checklist
- [ ] Source database accessible
- [ ] Target Azure Exadata provisioned
- [ ] Sufficient disk space (1.5x database size) on source
- [ ] Network connectivity or shared storage
- [ ] DBA privileges on both databases
- [ ] Matching character sets and versions

## When to Use Data Pump
- Database size < 10 TB
- Acceptable downtime: 2-48 hours
- Need to reorganize or filter data
- Cross-platform migration
- Schema-level migration required

## Architecture
```
Source Database → Export Directory → Transfer → Import Directory → Target Database
```

## Phase 1: Pre-Migration Preparation (1 hour)

### Step 1.1: Assess Database Size
```sql
-- Check database size
SELECT 
  SUM(bytes)/1024/1024/1024 AS size_gb,
  COUNT(DISTINCT tablespace_name) AS tablespaces
FROM dba_segments;

-- Check largest objects
SELECT owner, segment_name, segment_type, 
       ROUND(bytes/1024/1024/1024,2) AS size_gb
FROM dba_segments
WHERE owner NOT IN ('SYS','SYSTEM')
ORDER BY bytes DESC
FETCH FIRST 20 ROWS ONLY;

-- Estimate export size
SELECT 
  SUM(num_rows * avg_row_len) / 1024/1024/1024 AS estimated_gb
FROM dba_tables
WHERE owner NOT IN ('SYS','SYSTEM');
```

### Step 1.2: Create Directory Objects
```sql
-- On source database
CREATE DIRECTORY dp_export_dir AS '/backup/datapump/export';
GRANT READ, WRITE ON DIRECTORY dp_export_dir TO datapump_user;

-- On target database
CREATE DIRECTORY dp_import_dir AS '/backup/datapump/import';
GRANT READ, WRITE ON DIRECTORY dp_import_dir TO datapump_user;

-- Verify
SELECT * FROM dba_directories WHERE directory_name LIKE 'DP_%';
```

### Step 1.3: Create Data Pump User
```sql
-- On both source and target
CREATE USER datapump_user IDENTIFIED BY "SecurePassword123!";
GRANT DATAPUMP_EXP_FULL_DATABASE TO datapump_user;
GRANT DATAPUMP_IMP_FULL_DATABASE TO datapump_user;
GRANT DBA TO datapump_user;  -- For import
```

### Step 1.4: Test Space Requirements
```sql
-- Check available space
SELECT 
  tablespace_name,
  ROUND(SUM(bytes)/1024/1024/1024,2) AS used_gb,
  ROUND((SUM(bytes)/max_bytes)*100,2) AS pct_used
FROM dba_data_files
CROSS JOIN (SELECT SUM(bytes) AS max_bytes FROM dba_data_files)
GROUP BY tablespace_name;
```

## Phase 2: Perform Export (Varies by Size)

### Step 2.1: Full Database Export
```bash
# Create export parameter file: full_export.par
cat > full_export.par << 'EOF'
DIRECTORY=dp_export_dir
DUMPFILE=fulldb_%U.dmp
LOGFILE=fulldb_export.log
PARALLEL=8
COMPRESSION=ALL
FULL=Y
EXCLUDE=STATISTICS
REUSE_DUMPFILES=YES
EOF

# Execute export
expdp datapump_user/password PARFILE=full_export.par

# Monitor progress (in another session)
sqlplus datapump_user/password << SQL
SELECT 
  sid, serial#, sofar, totalwork,
  ROUND(sofar/totalwork*100,2) AS pct_complete
FROM v\$session_longops
WHERE opname LIKE 'EXP%'
AND totalwork != 0;
SQL
```

### Step 2.2: Schema-Level Export (Alternative)
```bash
# For specific schemas only
cat > schema_export.par << 'EOF'
DIRECTORY=dp_export_dir
DUMPFILE=schemas_%U.dmp
LOGFILE=schema_export.log
PARALLEL=8
COMPRESSION=ALL
SCHEMAS=HR,SALES,FINANCE
EXCLUDE=STATISTICS
EOF

expdp datapump_user/password PARFILE=schema_export.par
```

### Step 2.3: Table-Level Export (For Specific Tables)
```bash
cat > table_export.par << 'EOF'
DIRECTORY=dp_export_dir
DUMPFILE=tables_%U.dmp
LOGFILE=table_export.log
PARALLEL=4
COMPRESSION=ALL
TABLES=HR.EMPLOYEES,SALES.ORDERS
EOF

expdp datapump_user/password PARFILE=table_export.par
```

### Step 2.4: Export with Filtering
```bash
# Export with data filtering
cat > filtered_export.par << 'EOF'
DIRECTORY=dp_export_dir
DUMPFILE=filtered_%U.dmp
LOGFILE=filtered_export.log
SCHEMAS=SALES
QUERY=SALES.ORDERS:"WHERE order_date >= TO_DATE('2023-01-01','YYYY-MM-DD')"
COMPRESSION=ALL
EOF

expdp datapump_user/password PARFILE=filtered_export.par
```

## Phase 3: Transfer Dump Files (Varies)

### Option A: Direct Network Copy
```bash
# Using scp with compression
for file in /backup/datapump/export/*.dmp; do
  scp -C "$file" oracle@targethost:/backup/datapump/import/
done

# Using rsync (resume-capable)
rsync -avz --progress --partial   /backup/datapump/export/*.dmp   oracle@targethost:/backup/datapump/import/
```

### Option B: Azure Blob Storage Transfer
```bash
# Upload to Azure Blob Storage
az storage blob upload-batch   --account-name mystorageaccount   --destination datapump-container   --source /backup/datapump/export/   --pattern "*.dmp"

# Download on target
az storage blob download-batch   --account-name mystorageaccount   --source datapump-container   --destination /backup/datapump/import/
```

### Option C: Shared Storage (Fastest)
```bash
# If using shared NFS/Azure Files
# Mount same storage on both source and target
mount -t nfs nfsserver:/datapump /backup/datapump
# No copy needed!
```

## Phase 4: Perform Import (Varies by Size)

### Step 4.1: Pre-Import Checks on Target
```sql
-- Verify target is ready
SELECT * FROM v$version;
SELECT name, open_mode FROM v$database;

-- Check tablespace availability
SELECT tablespace_name, status FROM dba_tablespaces;

-- Verify dump file accessibility
SELECT * FROM dba_directories WHERE directory_name = 'DP_IMPORT_DIR';
```

### Step 4.2: Test Import (Dry Run)
```bash
# Test import without actually importing
cat > test_import.par << 'EOF'
DIRECTORY=dp_import_dir
DUMPFILE=fulldb_%U.dmp
LOGFILE=test_import.log
SQLFILE=import_ddl.sql
FULL=Y
EOF

impdp datapump_user/password PARFILE=test_import.par

# Review import_ddl.sql for any issues
less /backup/datapump/import/import_ddl.sql
```

### Step 4.3: Full Database Import
```bash
cat > full_import.par << 'EOF'
DIRECTORY=dp_import_dir
DUMPFILE=fulldb_%U.dmp
LOGFILE=fulldb_import.log
PARALLEL=8
FULL=Y
TABLE_EXISTS_ACTION=REPLACE
TRANSFORM=SEGMENT_ATTRIBUTES:N  -- Don't import storage clauses
EXCLUDE=STATISTICS
EOF

# Execute import
impdp datapump_user/password PARFILE=full_import.par

# Monitor progress
sqlplus datapump_user/password << SQL
SELECT 
  sid, serial#, sofar, totalwork,
  ROUND(sofar/totalwork*100,2) AS pct_complete,
  time_remaining
FROM v\$session_longops
WHERE opname LIKE 'IMP%'
AND totalwork != 0;
SQL
```

### Step 4.4: Schema-Only Import (Metadata First)
```bash
# Import structure only, data later
cat > metadata_import.par << 'EOF'
DIRECTORY=dp_import_dir
DUMPFILE=fulldb_%U.dmp
LOGFILE=metadata_import.log
SCHEMAS=HR,SALES,FINANCE
CONTENT=METADATA_ONLY
TRANSFORM=SEGMENT_ATTRIBUTES:N
EOF

impdp datapump_user/password PARFILE=metadata_import.par

# Then import data
cat > data_import.par << 'EOF'
DIRECTORY=dp_import_dir
DUMPFILE=fulldb_%U.dmp
LOGFILE=data_import.log
SCHEMAS=HR,SALES,FINANCE
CONTENT=DATA_ONLY
PARALLEL=8
EOF

impdp datapump_user/password PARFILE=data_import.par
```

## Phase 5: Post-Import Validation (1-2 hours)

### Step 5.1: Verify Object Counts
```sql
-- Compare object counts
SELECT object_type, COUNT(*) 
FROM dba_objects 
WHERE owner IN ('HR','SALES','FINANCE')
GROUP BY object_type
ORDER BY object_type;

-- Check for invalid objects
SELECT owner, object_name, object_type, status
FROM dba_objects
WHERE status != 'VALID'
AND owner IN ('HR','SALES','FINANCE');

-- Compile invalid objects
BEGIN
  DBMS_UTILITY.COMPILE_SCHEMA('HR');
  DBMS_UTILITY.COMPILE_SCHEMA('SALES');
  DBMS_UTILITY.COMPILE_SCHEMA('FINANCE');
END;
/
```

### Step 5.2: Verify Row Counts
```sql
-- Generate row count script
SELECT 'SELECT '''||table_name||''' AS table_name, COUNT(*) FROM '||owner||'.'||table_name||';'
FROM dba_tables
WHERE owner IN ('HR','SALES','FINANCE')
ORDER BY owner, table_name;

-- Compare with source counts
```

### Step 5.3: Validate Constraints and Indexes
```sql
-- Check constraints
SELECT constraint_name, constraint_type, status
FROM dba_constraints
WHERE owner IN ('HR','SALES','FINANCE')
AND status != 'ENABLED'
ORDER BY owner, table_name;

-- Check indexes
SELECT owner, index_name, status, tablespace_name
FROM dba_indexes
WHERE owner IN ('HR','SALES','FINANCE')
AND status != 'VALID'
ORDER BY owner, index_name;
```

### Step 5.4: Gather Statistics
```sql
-- Gather statistics for imported schemas
EXEC DBMS_STATS.GATHER_SCHEMA_STATS('HR', CASCADE=>TRUE);
EXEC DBMS_STATS.GATHER_SCHEMA_STATS('SALES', CASCADE=>TRUE);
EXEC DBMS_STATS.GATHER_SCHEMA_STATS('FINANCE', CASCADE=>TRUE);

-- Verify statistics gathered
SELECT owner, table_name, num_rows, last_analyzed
FROM dba_tables
WHERE owner IN ('HR','SALES','FINANCE')
ORDER BY owner, table_name;
```

## Phase 6: Application Cutover

### Step 6.1: Update Connection Strings
```bash
# Update tnsnames.ora or application config
# Change from: source-db:1521/SOURCEDB
# Change to: azure-exadata:1521/TARGETDB
```

### Step 6.2: Test Application Connectivity
```bash
# Test database connections
sqlplus appuser/password@TARGETDB << EOF
SELECT 'Connection successful' AS status FROM dual;
SELECT COUNT(*) FROM app_schema.main_table;
EOF
```

### Step 6.3: Restart Applications
```bash
systemctl restart application-service
# Monitor logs for any connection issues
tail -f /var/log/application/app.log
```

## Troubleshooting Guide

### Issue: Export Runs Out of Space
```bash
# Check space
df -h /backup/datapump/export

# Solutions:
# 1. Increase compression
# 2. Export schemas separately
# 3. Exclude large tables and handle separately
EXCLUDE=TABLE:"IN ('LARGE_TABLE1','LARGE_TABLE2')"
```

### Issue: Import Fails with ORA-39151
```sql
-- Table already exists
-- Solutions:
# 1. Use TABLE_EXISTS_ACTION parameter
TABLE_EXISTS_ACTION=REPLACE  -- Drop and recreate
TABLE_EXISTS_ACTION=APPEND   -- Keep existing, add new rows
TABLE_EXISTS_ACTION=TRUNCATE -- Keep structure, replace data
TABLE_EXISTS_ACTION=SKIP     -- Skip if exists
```

### Issue: Invalid Objects After Import
```sql
-- Recompile schema
BEGIN
  DBMS_UTILITY.COMPILE_SCHEMA(schema_name => 'HR');
END;
/

-- Check remaining invalids
SELECT object_name, object_type 
FROM dba_objects 
WHERE status='INVALID' AND owner='HR';
```

### Issue: Slow Performance
```bash
# Increase parallelism
PARALLEL=16  # In parameter file

# Disable redo logging (CAUTION)
TRANSFORM=DISABLE_ARCHIVE_LOGGING:Y

# Use direct path
ACCESS_METHOD=DIRECT_PATH
```

## Performance Tuning

### Optimize Export
```bash
# Maximize export performance
PARALLEL=16              # Match CPU cores
COMPRESSION=ALL          # Reduce file size
EXCLUDE=STATISTICS       # Skip stats export
FILESIZE=10G            # Split into multiple files
```

### Optimize Import
```bash
# Maximize import performance
PARALLEL=16
TABLE_EXISTS_ACTION=TRUNCATE
TRANSFORM=DISABLE_ARCHIVE_LOGGING:Y
ACCESS_METHOD=DIRECT_PATH
METRICS=Y               # Show import metrics
```

## Downtime Estimation

| Database Size | Export Time | Transfer Time | Import Time | Total Downtime |
|--------------|-------------|---------------|-------------|----------------|
| 100 GB       | 30-60 min   | 15-30 min     | 45-90 min   | 2-3 hours      |
| 500 GB       | 2-4 hours   | 1-2 hours     | 3-6 hours   | 6-12 hours     |
| 1 TB         | 4-8 hours   | 2-4 hours     | 6-12 hours  | 12-24 hours    |
| 5 TB         | 20-40 hours | 10-20 hours   | 30-60 hours | 3-5 days       |

*Times vary based on hardware, network, and data characteristics*

## Best Practices

1. **Test First**: Always perform test migration
2. **Parallelism**: Use parallel degree matching CPU cores
3. **Compression**: Enable ALL compression to reduce I/O
4. **Multiple Files**: Split dumps across multiple files
5. **Statistics**: Exclude during export/import, gather after
6. **Validation**: Always validate row counts and objects
7. **Monitoring**: Monitor v$session_longops during operations
8. **Network**: Use compression for remote transfers

## Success Criteria
- [ ] All objects imported successfully
- [ ] Row counts match source
- [ ] All constraints enabled
- [ ] All indexes valid
- [ ] Statistics gathered
- [ ] Application connectivity verified
- [ ] Performance acceptable

## Additional Resources
- [Oracle Data Pump Guide](https://docs.oracle.com/en/database/oracle/oracle-database/19/sutil/)
- [Data Pump Best Practices (MOS Doc ID 403207.1)](https://support.oracle.com/)
- [Data Pump Parameters Reference](https://docs.oracle.com/en/database/oracle/oracle-database/19/sutil/oracle-data-pump-overview.html)
