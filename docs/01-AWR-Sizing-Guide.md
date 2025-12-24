# AWR-Based Sizing Guide for Oracle Database @ Azure Exadata

## Overview

This guide provides a systematic approach to sizing Oracle Database @ Azure Exadata infrastructure based on Automatic Workload Repository (AWR) reports from your source Oracle Exadata system.

## Prerequisites

- Access to source Oracle Exadata database
- DBA privileges to generate AWR reports
- At least 7 days of representative workload data
- Peak and average load periods identified

## Step 1: Generate AWR Reports

### 1.1 Identify Snapshot Range

```sql
-- Check available snapshots
SELECT snap_id, begin_interval_time, end_interval_time
FROM dba_hist_snapshot
ORDER BY snap_id DESC
FETCH FIRST 30 ROWS ONLY;

-- Identify peak hour snapshots over the last 7 days
SELECT snap_id, begin_interval_time, end_interval_time
FROM dba_hist_snapshot
WHERE begin_interval_time >= SYSDATE - 7
ORDER BY snap_id;
```

### 1.2 Generate AWR Report

```sql
-- Generate AWR report for specific snapshot range
@$ORACLE_HOME/rdbms/admin/awrrpt.sql

-- For RAC, generate RAC AWR report
@$ORACLE_HOME/rdbms/admin/awrgrpt.sql
```

## Step 2: Analyze Key Metrics

### 2.1 CPU and Compute Resources

Extract the following from AWR reports:

**CPU Metrics:**
- Average CPU utilization (%)
- Peak CPU utilization (%)
- CPU wait time
- Number of CPUs used

**Formula for CPU cores needed:**
```
Required_Cores = (Peak_CPU_Usage × Current_Cores) / Target_Utilization
Target_Utilization = 70-80% for production systems
```

### 2.2 Memory Requirements

**Memory Metrics:**
- SGA size (System Global Area)
- PGA size (Program Global Area)
- Buffer cache hit ratio
- Shared pool statistics

**Key queries:**

```sql
-- Current SGA and PGA settings
SELECT name, value/1024/1024/1024 AS value_gb
FROM v$parameter
WHERE name IN ('sga_target', 'sga_max_size', 'pga_aggregate_target');

-- Buffer pool advisor
SELECT size_for_estimate, size_factor, estd_physical_read_factor
FROM v$db_cache_advice
WHERE name = 'DEFAULT' AND block_size = 8192
ORDER BY size_for_estimate;
```

### 2.3 Storage and I/O Analysis

**Storage Metrics:**
- Total database size
- Daily growth rate
- IOPS (Read/Write)
- Throughput (MB/s)

**Key queries:**

```sql
-- Database size
SELECT SUM(bytes)/1024/1024/1024 AS size_gb
FROM dba_segments;

-- Tablespace usage
SELECT tablespace_name,
       ROUND(SUM(bytes)/1024/1024/1024, 2) AS size_gb
FROM dba_segments
GROUP BY tablespace_name
ORDER BY size_gb DESC;

-- I/O statistics from AWR
SELECT *
FROM dba_hist_sysstat
WHERE stat_name IN ('physical read total IO requests',
                    'physical write total IO requests',
                    'physical read total bytes',
                    'physical write total bytes')
ORDER BY snap_id DESC;
```

### 2.4 Workload Characteristics

**Workload Metrics:**
- Transactions per second (TPS)
- Sessions (average and peak)
- Connection rate
- Query complexity (parse/execute ratio)

**Key queries:**

```sql
-- User sessions over time
SELECT snap_id, instance_number, 
       MAX(current_utilization) AS max_sessions
FROM dba_hist_resource_limit
WHERE resource_name = 'sessions'
GROUP BY snap_id, instance_number
ORDER BY snap_id DESC;

-- Transaction rate
SELECT end_interval_time,
       ROUND(value/60, 2) AS transactions_per_second
FROM dba_hist_sysstat s, dba_hist_snapshot sn
WHERE s.snap_id = sn.snap_id
AND stat_name = 'user commits'
ORDER BY end_interval_time DESC;
```

## Step 3: Azure Exadata Sizing Recommendation

### 3.1 Shape Selection Matrix

| Source Exadata Model | Compute (OCPU) | Memory (GB) | Storage (TB) | Recommended Azure Shape |
|---------------------|----------------|-------------|--------------|-------------------------|
| X8M - Quarter Rack  | 50-100         | 360-720     | 42-84        | Azure Exadata X8M (Quarter) |
| X8M - Half Rack     | 100-200        | 720-1440    | 84-168       | Azure Exadata X8M (Half) |
| X8M - Full Rack     | 200-400        | 1440-2880   | 168-336      | Azure Exadata X8M (Full) |
| X9M - Quarter Rack  | 64-128         | 512-1024    | 61-122       | Azure Exadata X9M (Quarter) |
| X9M - Half Rack     | 128-256        | 1024-2048   | 122-244      | Azure Exadata X9M (Half) |
| X9M - Full Rack     | 256-512        | 2048-4096   | 244-488      | Azure Exadata X9M (Full) |

### 3.2 Sizing Calculation Worksheet

```
=== COMPUTE SIZING ===
Source Peak CPU Cores: ____________
Source Average CPU Utilization: ____________%
Growth Factor (next 12-24 months): ____________%

Recommended Azure OCPUs = Source_Cores × (Peak_Util/70) × (1 + Growth_Factor)

=== MEMORY SIZING ===
Source SGA (GB): ____________
Source PGA (GB): ____________
Additional memory for caching (10-20%): ____________

Recommended Memory (GB) = (SGA + PGA) × 1.15

=== STORAGE SIZING ===
Current Database Size (TB): ____________
Daily Growth Rate (GB): ____________
Retention Period (months): ____________
Backup Space (50-100% of DB size): ____________

Recommended Storage (TB) = DB_Size + (Daily_Growth × Days × Retention) + Backup_Space
```

### 3.3 Performance Validation

After sizing, validate against these thresholds:

- **CPU:** Target 60-70% average, 90% max peak
- **Memory:** Buffer cache hit ratio > 95%
- **Storage:** IOPS capacity > 2x current peak
- **Network:** Bandwidth > 1.5x current peak throughput

## Step 4: Document Sizing Results

Create a sizing summary document with:

1. **Executive Summary**
   - Source environment overview
   - Recommended Azure configuration
   - Cost estimate

2. **Detailed Analysis**
   - AWR report period and coverage
   - Key metrics and trends
   - Sizing calculations and assumptions

3. **Recommendations**
   - Initial configuration
   - Scaling strategy
   - Performance testing plan

## Best Practices

1. **Multiple AWR Reports:** Collect reports from different time periods (weekday, weekend, month-end)
2. **Peak Analysis:** Always size for peak with headroom, not average
3. **Growth Planning:** Include 12-24 months growth projections
4. **RAC Considerations:** For RAC, analyze each node and aggregate requirements
5. **Special Workloads:** Consider batch jobs, maintenance windows separately

## Next Steps

After completing sizing:
1. Proceed to [CIDR Planning Guide](02-CIDR-Planning-Guide.md)
2. Review cost estimates with Azure pricing calculator
3. Validate sizing with Oracle and Azure support teams
4. Begin [IaC Environment Generation](03-IaC-Environment-Generation.md)

## Additional Resources

- [Oracle AWR Report Analysis Guide](https://docs.oracle.com/en/database/)
- [Azure Exadata Infrastructure Specifications](https://docs.microsoft.com/en-us/azure/)
- [Oracle Database @ Azure Pricing](https://azure.microsoft.com/pricing/)
