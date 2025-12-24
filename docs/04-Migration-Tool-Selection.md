# Migration Tool Selection Guide

## Overview

This guide helps you select the appropriate migration tool for moving Oracle databases from on-premises Exadata to Oracle Database @ Azure Exadata. Each tool has specific use cases, requirements, and trade-offs.

## Migration Tools Comparison

| Tool | Downtime | Complexity | Data Size | RAC Support | Use Case |
|------|----------|------------|-----------|-------------|----------|
| **Zero Downtime Migration (ZDM)** | Minutes | Medium | Any | Yes | Recommended for most migrations |
| **Data Pump** | Hours-Days | Low | < 10 TB | Yes | Simple, full database exports |
| **Oracle GoldenGate** | Near-zero | High | Any | Yes | Minimal downtime required |
| **Transportable Tablespaces (TTS)** | Hours | Medium | > 1 TB | Yes | Large databases, cross-platform |

## Decision Tree

```
Start: Do you require near-zero downtime (<5 minutes)?
│
├─ Yes → Is the database > 10 TB?
│   │
│   ├─ Yes → Use Oracle GoldenGate
│   │         (See: 07-GoldenGate-Configuration.md)
│   │
│   └─ No → Use Zero Downtime Migration (ZDM)
│            (See: 05-ZDM-Configuration.md)
│
└─ No → What is your acceptable downtime window?
    │
    ├─ Hours (< 8 hours) → Is the database homogeneous (same platform)?
    │   │
    │   ├─ Yes → Database size?
    │   │   │
    │   │   ├─ < 5 TB → Use Data Pump
    │   │   │            (See: 06-DataPump-Configuration.md)
    │   │   │
    │   │   └─ > 5 TB → Use Transportable Tablespaces
    │   │                (See: 08-TTS-Configuration.md)
    │   │
    │   └─ No → Use Data Pump with cross-platform conversion
    │            (See: 06-DataPump-Configuration.md)
    │
    └─ Days → Use Data Pump
              (See: 06-DataPump-Configuration.md)
```

## Tool-Specific Considerations

### Zero Downtime Migration (ZDM)

**When to Use:**
- Production databases requiring minimal downtime
- Oracle Database 11g Release 2 (11.2.0.4) and later
- Moving from on-premises to Oracle Database @ Azure
- Need automated, orchestrated migration

**Advantages:**
- Automated process with minimal manual intervention
- Built-in validation and fallback capabilities
- Supports physical and logical migration
- Integrated with Oracle Maximum Availability Architecture (MAA)

**Limitations:**
- Requires Oracle support license
- Network bandwidth requirements can be significant
- Initial setup complexity

**Technical Requirements:**
- ZDM service host (separate server)
- Network connectivity between source and target
- Compatible Oracle Database versions
- Sufficient storage for backups and temporary files

**Estimated Downtime:**
- Database < 1 TB: 5-15 minutes
- Database 1-10 TB: 15-30 minutes
- Database > 10 TB: 30-60 minutes

### Data Pump

**When to Use:**
- Straightforward database migrations
- Small to medium databases (< 10 TB)
- Acceptable downtime window of several hours
- Need to reorganize or consolidate data

**Advantages:**
- Simple and well-understood technology
- Built into Oracle Database
- Excellent for data subsetting and filtering
- Good for cross-platform migrations

**Limitations:**
- Requires significant downtime
- Network bandwidth dependent
- Export/import times increase with database size

**Technical Requirements:**
- Sufficient disk space on source and target (1.5x database size)
- Network connectivity or shared storage
- Database compatibility mode matching

**Estimated Downtime:**
- 1 TB database: 2-4 hours
- 5 TB database: 10-20 hours
- 10 TB database: 20-40 hours

**Performance Factors:**
- Parallelism settings (PARALLEL parameter)
- Network bandwidth
- Compression (COMPRESSION=ALL)
- Encryption requirements

### Oracle GoldenGate

**When to Use:**
- Mission-critical systems requiring near-zero downtime
- Continuous data replication needed
- Heterogeneous database migrations
- Complex multi-step migrations

**Advantages:**
- Near-zero downtime migrations
- Continuous replication
- Supports heterogeneous platforms
- Bi-directional replication possible

**Limitations:**
- Most complex to set up and manage
- Requires supplemental logging (performance impact)
- Licensing costs
- Requires specialized expertise

**Technical Requirements:**
- GoldenGate software on source and target
- Supplemental logging enabled
- Archive log mode enabled
- Network connectivity with low latency
- Sufficient disk space for trail files

**Estimated Downtime:**
- Switchover window: < 5 minutes
- Setup time: Days to weeks
- Total migration duration: Weeks (for initial sync + validation)

**Use Cases:**
- 24/7 production systems
- Large databases (> 50 TB)
- Phased migrations
- Disaster recovery setup

### Transportable Tablespaces (TTS)

**When to Use:**
- Very large databases (> 5 TB)
- Same database version and platform (or compatible)
- Self-contained tablespaces
- Need to migrate subset of database

**Advantages:**
- Very fast for large databases (copies files, not data)
- Minimal downtime for data migration
- Efficient for large datasets
- Can migrate portions of database

**Limitations:**
- Requires tablespaces to be self-contained
- Platform/endian compatibility required (or conversion needed)
- Complex for cross-platform migrations
- Metadata export/import still required

**Technical Requirements:**
- Tablespaces must be self-contained
- Compatible Oracle versions
- Sufficient storage for datafile copies
- Same or convertible endian format

**Estimated Downtime:**
- 5 TB database: 2-4 hours (mainly for metadata)
- 50 TB database: 4-8 hours (mainly for metadata)
- Actual data copying can be done while database is online

**Self-Contained Check:**
```sql
EXECUTE DBMS_TTS.TRANSPORT_SET_CHECK('TABLESPACE_NAME', TRUE);
SELECT * FROM TRANSPORT_SET_VIOLATIONS;
```

## Migration Assessment Questionnaire

Answer these questions to determine the best tool:

### 1. Database Characteristics
```
Database Size: _________________ TB
Number of Schemas: _____________
Number of Tablespaces: _________
Database Version: ______________
RAC Configuration: Yes / No
Platform: ______________________
```

### 2. Business Requirements
```
Maximum Acceptable Downtime: _________ hours
Migration Window: Start ________ End ________
Business Impact of Extended Downtime: High / Medium / Low
Rollback Required: Yes / No
Validation Time Required: _________ hours
```

### 3. Technical Constraints
```
Network Bandwidth (source to Azure): _________ Gbps
Available Shared Storage: Yes / No
DBA Expertise Level: Beginner / Intermediate / Expert
Budget for Tools/Licensing: $ _________
Timeline for Migration: _________ weeks
```

### 4. Special Considerations
```
Encryption Required: Yes / No
Compliance Requirements: _________________
Data Masking Needed: Yes / No
Schema Consolidation: Yes / No
Platform Change: Yes / No
```

## Recommended Tool Matrix

Based on your answers:

| Scenario | Recommended Tool | Alternative |
|----------|------------------|-------------|
| < 5 TB, 4-8 hour window | Data Pump | TTS |
| < 5 TB, < 1 hour window | ZDM | GoldenGate |
| 5-20 TB, 4-12 hour window | TTS | Data Pump |
| 5-20 TB, < 1 hour window | ZDM | GoldenGate |
| > 20 TB, any window | GoldenGate + TTS | ZDM |
| 24/7 operation | GoldenGate | ZDM |
| Cross-platform | Data Pump | TTS + Conversion |

## Hybrid Approaches

For complex migrations, consider combining tools:

### Approach 1: TTS + Data Pump
```
1. Use TTS for large user tablespaces
2. Use Data Pump for:
   - SYSTEM/SYSAUX metadata
   - Small tablespaces
   - Objects that couldn't be transported
```

### Approach 2: GoldenGate + Data Pump
```
1. Initial load with Data Pump (offline)
2. Setup GoldenGate for incremental changes
3. Sync and switchover with GoldenGate
```

### Approach 3: ZDM + Pre-staging
```
1. Pre-stage large datafiles to Azure (offline)
2. Use ZDM for final synchronization
3. Minimize final migration window
```

## Migration Phases

Regardless of tool selected, follow these phases:

### Phase 1: Assessment (1-2 weeks)
- Database sizing and analysis
- Tool selection
- Risk assessment
- Timeline development

### Phase 2: Preparation (2-4 weeks)
- Infrastructure provisioning
- Tool installation and configuration
- Test migration (non-production)
- Runbook development

### Phase 3: Testing (2-4 weeks)
- Full test migration
- Performance validation
- Application testing
- Rollback testing

### Phase 4: Production Migration (1 week)
- Final pre-migration checks
- Execute migration
- Validation
- Cutover

### Phase 5: Post-Migration (2-4 weeks)
- Performance monitoring
- Issue resolution
- Optimization
- Documentation

## Validation Steps (All Tools)

After migration, perform these validations:

### 1. Data Validation
```sql
-- Row counts
SELECT table_name, num_rows 
FROM dba_tables 
WHERE owner = 'SCHEMA_NAME';

-- Data checksum (sample)
SELECT /*+ PARALLEL(8) */ 
  SUM(ORA_HASH(column1||column2||column3)) as checksum
FROM schema.large_table;
```

### 2. Object Validation
```sql
-- Object counts
SELECT object_type, COUNT(*) 
FROM dba_objects 
WHERE owner = 'SCHEMA_NAME'
GROUP BY object_type;

-- Invalid objects
SELECT object_name, object_type, status
FROM dba_objects
WHERE status != 'VALID'
AND owner = 'SCHEMA_NAME';
```

### 3. Performance Validation
```sql
-- Generate AWR report for first 24 hours
@$ORACLE_HOME/rdbms/admin/awrrpt.sql

-- Compare key metrics to baseline
SELECT metric_name, value
FROM v$sysmetric
WHERE metric_name IN (
  'Database CPU Time Ratio',
  'Database Wait Time Ratio',
  'Executions Per Sec',
  'Physical Reads Per Sec'
);
```

## Risk Mitigation

### Common Risks and Mitigation:

1. **Data Loss**
   - Mitigation: Multiple backups, validation scripts, rollback plan

2. **Extended Downtime**
   - Mitigation: Test migrations, proper sizing, fallback procedures

3. **Performance Issues**
   - Mitigation: AWR analysis, proper indexing, statistics gathering

4. **Application Compatibility**
   - Mitigation: Application testing, connection string updates, TNS configuration

5. **Network Issues**
   - Mitigation: Bandwidth testing, compression, multi-path networking

## Next Steps

After selecting your migration tool:

1. **For ZDM:** Proceed to [ZDM Configuration Runbook](05-ZDM-Configuration.md)
2. **For Data Pump:** Proceed to [Data Pump Configuration Runbook](06-DataPump-Configuration.md)
3. **For GoldenGate:** Proceed to [GoldenGate Configuration Runbook](07-GoldenGate-Configuration.md)
4. **For TTS:** Proceed to [TTS Configuration Runbook](08-TTS-Configuration.md)

## Additional Resources

- [Oracle Zero Downtime Migration Documentation](https://docs.oracle.com/en/database/oracle/zero-downtime-migration/)
- [Oracle Data Pump Guide](https://docs.oracle.com/en/database/oracle/oracle-database/19/sutil/)
- [Oracle GoldenGate Documentation](https://docs.oracle.com/en/middleware/goldengate/)
- [Transportable Tablespaces Guide](https://docs.oracle.com/en/database/oracle/oracle-database/19/admin/)
