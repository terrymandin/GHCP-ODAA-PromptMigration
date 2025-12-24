# Transportable Tablespaces (TTS) Configuration Runbook

## Overview
Transportable Tablespaces (TTS) provides the fastest method for migrating large databases by physically copying datafiles. Ideal for very large databases (> 5 TB) with acceptable downtime windows of several hours.

## Prerequisites
- Self-contained tablespaces
- Same or compatible database versions  
- Compatible endian formats
- Sufficient storage for datafile copies
- DBA privileges on both databases

## When to Use TTS
- Database size > 5 TB
- Acceptable downtime: 2-12 hours
- Same platform or compatible endian
- Self-contained tablespaces
- Fastest migration method needed

## Phase 1: Pre-Migration (30 min)

### Check Self-Containment
```sql
EXEC DBMS_TTS.TRANSPORT_SET_CHECK('HR_DATA,SALES_DATA', TRUE);
SELECT * FROM TRANSPORT_SET_VIOLATIONS;
-- Fix any violations
```

### Verify Compatibility
```sql
SELECT platform_name, endian_format FROM v\;
```

## Phase 2: Prepare Source (30 min)

### Set Read-Only
```sql
ALTER TABLESPACE HR_DATA READ ONLY;
ALTER TABLESPACE SALES_DATA READ ONLY;
```

### Export Metadata
```bash
expdp system/password   DIRECTORY=tts_export_dir   DUMPFILE=tts_metadata.dmp   TRANSPORT_TABLESPACES=HR_DATA,SALES_DATA   TRANSPORT_FULL_CHECK=Y
```

## Phase 3: Copy Datafiles

### Option A: Direct Copy
```bash
rsync -avz --progress /u01/app/oracle/oradata/sourcedb/*.dbf   oracle@targethost:/u01/app/oracle/oradata/targetdb/
```

### Option B: RMAN Conversion (Different Endian)
```bash
rman target /
CONVERT TABLESPACE 'HR_DATA','SALES_DATA'
TO PLATFORM 'Linux x86 64-bit'
FORMAT '/backup/tts/converted/%U'
PARALLELISM 4;
```

## Phase 4: Import on Target (30-60 min)

### Import Metadata
```bash
impdp system/password   DIRECTORY=tts_import_dir   DUMPFILE=tts_metadata.dmp   TRANSPORT_DATAFILES='/path/to/datafile1.dbf','/path/to/datafile2.dbf'
```

### Set Read-Write
```sql
ALTER TABLESPACE HR_DATA READ WRITE;
ALTER TABLESPACE SALES_DATA READ WRITE;
```

## Phase 5: Validation (30 min)

### Verify Objects
```sql
SELECT tablespace_name, status FROM dba_tablespaces
WHERE tablespace_name IN ('HR_DATA','SALES_DATA');

SELECT COUNT(*) FROM dba_objects
WHERE status != 'VALID'
AND owner IN (SELECT DISTINCT owner FROM dba_segments 
              WHERE tablespace_name IN ('HR_DATA','SALES_DATA'));
```

### Gather Statistics
```sql
EXEC DBMS_STATS.GATHER_SCHEMA_STATS('HR', CASCADE=>TRUE);
EXEC DBMS_STATS.GATHER_SCHEMA_STATS('SALES', CASCADE=>TRUE);
```

## Troubleshooting

### Not Self-Contained
```sql
-- View violations
SELECT * FROM TRANSPORT_SET_VIOLATIONS;
-- Move dependent objects or include more tablespaces
```

### Platform Incompatibility
- Use RMAN CONVERT for different endian formats
- Verify with: SELECT platform_name FROM v
### Insufficient Space
```bash
df -h /u01/app/oracle/oradata/targetdb
-- Ensure 1.5x datafile size available
```

## Downtime Estimation

| DB Size | Metadata Export | Datafile Copy | Import | Total |
|---------|----------------|---------------|---------|--------|
| 5 TB    | 15 min         | 1-2 hours     | 15 min  | 2-3 hours |
| 10 TB   | 20 min         | 2-4 hours     | 20 min  | 3-5 hours |
| 50 TB   | 30 min         | 10-20 hours   | 30 min  | 11-21 hours |

## Best Practices
1. Test on non-production first
2. Verify self-containment thoroughly
3. Use parallel operations
4. Maintain backups until validated
5. Document all datafile mappings

## Success Criteria
- [ ] All tablespaces transported
- [ ] Tablespaces READ WRITE on target
- [ ] All objects valid
- [ ] Row counts match
- [ ] Application tested

## Additional Resources
- [Oracle TTS Guide](https://docs.oracle.com/en/database/oracle/oracle-database/19/admin/)
- [MOS Doc ID 371556.1](https://support.oracle.com/)
