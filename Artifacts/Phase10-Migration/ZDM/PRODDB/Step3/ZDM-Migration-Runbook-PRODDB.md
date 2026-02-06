# ZDM Migration Runbook: PRODDB
## Migration: On-Premises Oracle to Oracle Database@Azure

---

## Document Information

| Field | Value |
|-------|-------|
| Source Database | ORADB01 (oradb01) @ temandin-oravm-vm01 |
| Target Database | ORADB01 (oradb01_oda) @ tmodaauks-rqahk1 |
| Migration Type | ONLINE_PHYSICAL (Minimal Downtime) |
| Expected Downtime | 15-30 minutes |
| Database Size | ~2.6 GB |
| Created Date | February 5, 2026 |
| ZDM Server | tm-vm-odaa-oracle-jumpbox |

---

## Phase 1: Pre-Migration Verification

### 1.1 Source Database Checks

**Server:** temandin-oravm-vm01 (10.1.0.10)  
**Login:** SSH as oracle (or admin user with sudo to oracle)

```bash
# SSH to source
ssh oracle@10.1.0.10

# Or using admin user
ssh temandin@10.1.0.10
sudo su - oracle
```

#### Verify Database Status

```sql
-- Connect to database
sqlplus / as sysdba

-- Check database status
SELECT name, open_mode, database_role, log_mode FROM v$database;
-- Expected: ORADB01, READ WRITE, PRIMARY, ARCHIVELOG

-- Verify Force Logging
SELECT force_logging FROM v$database;
-- Expected: YES

-- Check Supplemental Logging
SELECT supplemental_log_data_min, supplemental_log_data_pk FROM v$database;
-- Expected: YES, YES

-- Verify TDE Wallet
SELECT wrl_type, status, wallet_type FROM v$encryption_wallet;
-- Expected: FILE, OPEN, AUTOLOGIN

-- Check database size
SELECT 
    ROUND(SUM(CASE WHEN file_type = 'Data' THEN bytes END)/1024/1024/1024, 2) AS data_gb,
    ROUND(SUM(CASE WHEN file_type = 'Temp' THEN bytes END)/1024/1024/1024, 2) AS temp_gb
FROM (
    SELECT 'Data' AS file_type, bytes FROM dba_data_files
    UNION ALL
    SELECT 'Temp', bytes FROM dba_temp_files
);

EXIT;
```

#### Verify Network Configuration

```bash
# Check listener status
lsnrctl status

# Verify password file exists
ls -la $ORACLE_HOME/dbs/orapw*
```

---

### 1.2 Target Database Checks

**Server:** tmodaauks-rqahk1 (10.0.1.160)  
**Login:** SSH as opc, sudo to oracle

```bash
# SSH to target
ssh opc@10.0.1.160

# Switch to oracle user
sudo su - oracle
```

#### Verify Cluster Status

```bash
# Check CRS status
crsctl check crs

# List registered databases
srvctl config database

# Verify no conflicting database exists
srvctl config database -d oradb01_oda
# Expected: "Database oradb01_oda does not exist"

# Check ASM disk groups
asmcmd lsdg
```

#### Verify Network Configuration

```bash
# Check listener
lsnrctl status

# Check SCAN listeners
srvctl status scan_listener
```

---

### 1.3 ZDM Server Checks

**Server:** tm-vm-odaa-oracle-jumpbox (10.1.0.8)  
**Login:** SSH as azureuser, sudo to zdmuser

```bash
# SSH to ZDM server
ssh azureuser@tm-vm-odaa-oracle-jumpbox

# Switch to zdmuser
sudo su - zdmuser
```

#### Verify ZDM Installation

```bash
# Check ZDM_HOME
echo $ZDM_HOME
# Expected: /u01/app/zdmhome

# Verify ZDM service status
$ZDM_HOME/bin/zdmservice status
# Expected: Running: true

# Check ZDM CLI
$ZDM_HOME/bin/zdmcli
# Should display usage information

# Check disk space (minimum 50GB recommended)
df -h /u01
# Available: 24GB (sufficient for this 2.6GB database)
```

#### Verify OCI Configuration

```bash
# Test OCI connectivity
oci os ns get
# Expected: {"data": "your_namespace"}

# Verify OCI config
cat ~/.oci/config
```

---

### 1.4 Network Connectivity Checks

**From ZDM Server:**

```bash
# Test SSH to source
ssh -o ConnectTimeout=10 -i /home/zdmuser/.ssh/zdm.pem oracle@10.1.0.10 "echo 'SSH OK'"

# Test SSH to target
ssh -o ConnectTimeout=10 -i /home/zdmuser/.ssh/odaa.pem opc@10.0.1.160 "echo 'SSH OK'"

# Test Oracle port to source
nc -zv 10.1.0.10 1521

# Test Oracle port to target
nc -zv 10.0.1.160 1521
```

---

## Phase 2: Source Database Configuration

> **Note:** Based on discovery, source database is already configured correctly. These steps are for verification/reference.

### 2.1 Enable Archive Log Mode (Already Enabled ✅)

```sql
-- Verify (should already be enabled)
sqlplus / as sysdba
ARCHIVE LOG LIST;
-- Expected: Database log mode: Archive Mode

-- If NOT enabled (skip if already enabled):
-- SHUTDOWN IMMEDIATE;
-- STARTUP MOUNT;
-- ALTER DATABASE ARCHIVELOG;
-- ALTER DATABASE OPEN;
```

### 2.2 Enable Force Logging (Already Enabled ✅)

```sql
-- Verify (should already be enabled)
SELECT force_logging FROM v$database;
-- Expected: YES

-- If NOT enabled:
-- ALTER DATABASE FORCE LOGGING;
```

### 2.3 Enable Supplemental Logging (Already Enabled ✅)

```sql
-- Verify current state
SELECT 
    supplemental_log_data_min AS min,
    supplemental_log_data_pk AS pk,
    supplemental_log_data_ui AS ui,
    supplemental_log_data_fk AS fk,
    supplemental_log_data_all AS all_cols
FROM v$database;
-- Expected: YES, YES, (others optional)

-- If NOT enabled:
-- ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
-- ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (PRIMARY KEY) COLUMNS;
-- ALTER SYSTEM SWITCH LOGFILE;
```

### 2.4 Verify TDE Wallet (Already Configured ✅)

```sql
-- Check wallet status
SELECT wrl_type, wrl_parameter, status, wallet_type FROM v$encryption_wallet;
-- Expected: FILE, /u01/app/oracle/admin/oradb01/wallet/tde/, OPEN, AUTOLOGIN

-- Verify wallet location (from sqlnet.ora)
-- /u01/app/oracle/admin/oradb01/wallet/tde/
```

### 2.5 Configure TNS Entries (Optional)

Create tnsnames.ora if not exists:

```bash
# As oracle user on source
cat >> $ORACLE_HOME/network/admin/tnsnames.ora << 'EOF'

ORADB01 =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = temandin-oravm-vm01)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = oradb01)
    )
  )

ORADB01_ODA =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = tmodaauks-rqahk1)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = oradb01_oda)
    )
  )
EOF
```

---

## Phase 3: Target Database Configuration

> **Note:** Target is Oracle Database@Azure with Exadata. Most configuration is handled by ZDM.

### 3.1 Verify Target Environment

```bash
# As opc on target
ssh opc@10.0.1.160

# Check available Oracle homes
cat /etc/oratab

# Check Grid Infrastructure
crsctl check crs

# Verify ASM disk groups have sufficient space
asmcmd lsdg
# DATAC3 and RECOC3 should have sufficient free space
```

### 3.2 Verify SSH Key Access

```bash
# From ZDM server, test SSH as opc
ssh -i /home/zdmuser/.ssh/odaa.pem opc@10.0.1.160 "whoami"
# Expected: opc

# Test sudo to oracle
ssh -i /home/zdmuser/.ssh/odaa.pem opc@10.0.1.160 "sudo -u oracle whoami"
# Expected: oracle
```

---

## Phase 4: ZDM Server Configuration

### 4.1 Login to ZDM Server

```bash
# SSH as admin user
ssh azureuser@tm-vm-odaa-oracle-jumpbox

# Switch to zdmuser (REQUIRED for ZDM commands)
sudo su - zdmuser

# Verify you are zdmuser
whoami
# Expected: zdmuser
```

### 4.2 Clone Repository and Navigate to Artifacts

```bash
# Clone the repository (if not already done)
cd ~
git clone https://github.com/<your-fork>/GHCP-ODAA-PromptMigration.git

# Navigate to Step3 artifacts
cd ~/GHCP-ODAA-PromptMigration/Artifacts/Phase10-Migration/ZDM/PRODDB/Step3

# Make scripts executable
chmod +x zdm_commands_PRODDB.sh
```

### 4.3 Initialize Environment (First Time Only)

```bash
# Run initialization
./zdm_commands_PRODDB.sh init
```

This creates:
- `~/creds/` directory with proper permissions (700)
- `~/zdm_oci_env.sh` template file for OCI environment variables

### 4.4 Create OCI Environment File

Edit the OCI environment file:

```bash
vi ~/zdm_oci_env.sh
```

Add your OCI identifiers:

```bash
#!/bin/bash
# OCI Environment Variables for PRODDB Migration
# Edit this file with your actual OCI OCIDs

export TARGET_TENANCY_OCID="ocid1.tenancy.oc1..your-tenancy-ocid"
export TARGET_USER_OCID="ocid1.user.oc1..your-user-ocid"
export TARGET_FINGERPRINT="aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99"
export TARGET_COMPARTMENT_OCID="ocid1.compartment.oc1..your-compartment-ocid"
export TARGET_DATABASE_OCID="ocid1.database.oc1..your-database-ocid"

# Optional: Object Storage (not required for ONLINE_PHYSICAL to ODA)
# export TARGET_OBJECT_STORAGE_NAMESPACE="your_namespace"
```

Source the file:

```bash
source ~/zdm_oci_env.sh
```

### 4.5 Set Password Environment Variables

> ⚠️ **SECURITY:** Enter passwords interactively - never save to files

```bash
# Secure password entry (passwords not visible)
read -sp "Enter SOURCE_SYS_PASSWORD: " SOURCE_SYS_PASSWORD; echo; export SOURCE_SYS_PASSWORD
read -sp "Enter TARGET_SYS_PASSWORD: " TARGET_SYS_PASSWORD; echo; export TARGET_SYS_PASSWORD
read -sp "Enter SOURCE_TDE_WALLET_PASSWORD: " SOURCE_TDE_WALLET_PASSWORD; echo; export SOURCE_TDE_WALLET_PASSWORD

# Verify variables are set (shows "set" not the actual password)
[ -n "$SOURCE_SYS_PASSWORD" ] && echo "SOURCE_SYS_PASSWORD: set" || echo "SOURCE_SYS_PASSWORD: NOT SET"
[ -n "$TARGET_SYS_PASSWORD" ] && echo "TARGET_SYS_PASSWORD: set" || echo "TARGET_SYS_PASSWORD: NOT SET"
[ -n "$SOURCE_TDE_WALLET_PASSWORD" ] && echo "SOURCE_TDE_WALLET_PASSWORD: set" || echo "SOURCE_TDE_WALLET_PASSWORD: NOT SET"
```

### 4.6 Create Password Files

```bash
./zdm_commands_PRODDB.sh create-creds
```

This creates:
- `~/creds/source_sys_password.txt`
- `~/creds/target_sys_password.txt`
- `~/creds/tde_password.txt`

---

## Phase 5: Migration Execution

### 5.1 Run Evaluation (Recommended)

Run an evaluation first to validate configuration without making changes:

```bash
# Navigate to artifacts directory
cd ~/GHCP-ODAA-PromptMigration/Artifacts/Phase10-Migration/ZDM/PRODDB/Step3

# Source OCI environment
source ~/zdm_oci_env.sh

# Run evaluation
./zdm_commands_PRODDB.sh eval
```

**Expected Output:**
- ZDM checks source and target connectivity
- Validates configuration parameters
- Reports any issues that would prevent migration

**Review evaluation results before proceeding!**

### 5.2 Execute Migration

Once evaluation passes, start the migration:

```bash
./zdm_commands_PRODDB.sh migrate
```

**Note the Job ID** from the output - you'll need it for monitoring.

Example output:
```
Job ID: 12345
Starting migration...
```

### 5.3 Monitor Progress

```bash
# Monitor job status
./zdm_commands_PRODDB.sh status <JOB_ID>

# Example:
./zdm_commands_PRODDB.sh status 12345

# Or use zdmcli directly for more details
$ZDM_HOME/bin/zdmcli query job -jobid <JOB_ID>
```

### 5.4 Migration Phases

The ONLINE_PHYSICAL migration proceeds through these phases:

| Phase | Description | Duration |
|-------|-------------|----------|
| ZDM_SETUP_SRC | Initial source setup | ~5 min |
| ZDM_PREPARE_SRC | Prepare source for migration | ~5 min |
| ZDM_CLONE_TGT | Clone target environment | ~10 min |
| ZDM_DISCOVER_SRC | Discover source configuration | ~5 min |
| ZDM_CONFIGURE_DG_SRC | Configure Data Guard | ~15 min |
| ZDM_SWITCHOVER_SRC | **PAUSE POINT** - Ready for switchover | Manual |
| ZDM_POST_SWITCHOVER | Post-switchover cleanup | ~5 min |

### 5.5 Handling Pause at ZDM_SWITCHOVER_SRC

Migration will pause at `ZDM_SWITCHOVER_SRC` for validation.

**At this point:**
1. Data Guard is synchronized
2. Source is still primary
3. Target is standby (mounted, receiving redo)

**Validation Steps Before Resuming:**

```bash
# On source - check Data Guard status
sqlplus / as sysdba
SELECT database_role, open_mode, switchover_status FROM v$database;
-- Expected: PRIMARY, READ WRITE, TO STANDBY

# On target - verify standby is synchronized
sqlplus / as sysdba
SELECT database_role, open_mode FROM v$database;
-- Expected: PHYSICAL STANDBY, MOUNTED

# Check redo apply lag
SELECT name, value FROM v$dataguard_stats WHERE name = 'apply lag';
-- Expected: minimal lag (e.g., +00 00:00:00)

EXIT;
```

### 5.6 Resume Migration (Perform Switchover)

Once validation is complete and you're ready for switchover:

```bash
./zdm_commands_PRODDB.sh resume <JOB_ID>
```

> ⚠️ **WARNING:** This initiates the switchover. Applications will experience downtime (15-30 min).

---

## Phase 6: Post-Migration Validation

### 6.1 Verify Target Database

```bash
# SSH to target
ssh opc@10.0.1.160
sudo su - oracle

sqlplus / as sysdba
```

```sql
-- Verify database role changed to PRIMARY
SELECT name, database_role, open_mode FROM v$database;
-- Expected: ORADB01, PRIMARY, READ WRITE

-- Check database status
SELECT status FROM v$instance;
-- Expected: OPEN

-- Verify data integrity - count key tables
SELECT COUNT(*) FROM <your_table>;

-- Check for invalid objects
SELECT owner, object_type, COUNT(*) 
FROM dba_objects 
WHERE status = 'INVALID' 
GROUP BY owner, object_type;

EXIT;
```

### 6.2 Verify Application Connectivity

```bash
# Test tnsping from application server
tnsping ORADB01_ODA

# Test sqlplus connection
sqlplus system/<password>@ORADB01_ODA

# Verify application-specific queries
SELECT * FROM <application_table> WHERE ROWNUM < 5;
```

### 6.3 Verify Data Guard Configuration

```sql
-- On new primary (target)
SELECT database_role, protection_mode FROM v$database;

-- Check Data Guard broker configuration
SHOW CONFIGURATION;
```

---

## Phase 7: Rollback Procedures

### 7.1 Before Switchover (Easy Rollback)

If migration is paused at `ZDM_SWITCHOVER_SRC`:

```bash
# Abort the migration job
./zdm_commands_PRODDB.sh abort <JOB_ID>

# Source database remains primary
# Target standby will be removed
```

### 7.2 After Switchover (Switchback)

If switchover has completed but you need to revert:

```sql
-- On current primary (target)
sqlplus / as sysdba

-- Verify switchback status
SELECT switchover_status FROM v$database;
-- Must show: TO STANDBY or SESSIONS ACTIVE

-- Initiate switchback (if needed)
ALTER DATABASE SWITCHOVER TO oradb01;

-- On original source, open database
ALTER DATABASE OPEN;
```

### 7.3 Emergency Procedures

If critical issues occur:

1. **Stop application traffic immediately**
2. **Document the issue**
3. **Contact Oracle Support** if needed
4. **Do NOT make additional changes** until root cause is understood

---

## Appendix A: Troubleshooting

### A.1 Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| OCI authentication failed | Invalid API key or fingerprint | Verify OCI config, regenerate API key |
| SSH connection refused | Key not authorized | Add key to authorized_keys |
| ZDM service not running | Service crashed | `zdmservice start` |
| Data Guard sync failing | Network issues | Check firewall, verify port 1521 |
| Insufficient disk space | Not enough space on ZDM | Clean up or expand storage |

### A.2 Log Locations

| Log Type | Location |
|----------|----------|
| ZDM Service Logs | `$ZDM_HOME/logs/` |
| Migration Job Logs | `$ZDM_BASE/chkbase/<job_id>/` |
| Source Alert Log | `/u01/app/oracle/diag/rdbms/oradb01/oradb01/trace/alert_oradb01.log` |
| Target Alert Log | `/u02/app/oracle/diag/rdbms/oradb01/oradb01/trace/alert_oradb01.log` |

### A.3 Useful Commands

```bash
# View ZDM job logs
$ZDM_HOME/bin/zdmcli query job -jobid <JOB_ID> -phase <PHASE>

# List all jobs
$ZDM_HOME/bin/zdmcli query job -jobid all

# Abort a job
$ZDM_HOME/bin/zdmcli abort job -jobid <JOB_ID>

# Restart ZDM service
$ZDM_HOME/bin/zdmservice stop
$ZDM_HOME/bin/zdmservice start
```

---

## Appendix B: Post-Migration Checklist

- [ ] Verify all applications can connect
- [ ] Update connection strings in application configs
- [ ] Reconfigure database links (SYS_HUB if needed)
- [ ] Set up backup schedules on target
- [ ] Configure monitoring and alerting
- [ ] Update documentation with new connection details
- [ ] Notify stakeholders of successful migration
- [ ] Schedule decommissioning of source (after validation period)
- [ ] Clean up temporary credentials: `./zdm_commands_PRODDB.sh cleanup-creds`

---

## Appendix C: Contact Information

| Role | Name | Contact |
|------|------|---------|
| DBA Lead | _______________ | _______________ |
| Network Team | _______________ | _______________ |
| Application Owner | _______________ | _______________ |
| Oracle Support | - | My Oracle Support (MOS) |

---

*Generated: February 5, 2026*  
*ZDM Migration Planning - Step 3*
