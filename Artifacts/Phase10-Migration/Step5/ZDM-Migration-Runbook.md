# ZDM Migration Runbook

## Migration: On-Premise to Oracle Database@Azure

### Document Information

| Field | Value |
|---|---|
| Source Database | `POCAKV` |
| Target Database | `POCAKV_ODAA` |
| Source Host | `factvmhost (10.200.1.12)` |
| Target Host | `vmclusterpoc-ytlat1 (10.200.0.250)` |
| Migration Type | `ONLINE_PHYSICAL` (default) |
| Source Oracle Home/SID | `/u01/app/oracle/product/19.0.0/dbhome_1` / `POCAKV` |
| Target Oracle Home/SID | `/u02/app/oracle/product/19.0.0.0/dbhome_1` / `POCAKV1` |
| ZDM Home | `/mnt/app/zdmhome` |
| Created Date | `2026-03-18` |

---

## Phase 0: ZDM Version Pre-Migration Gate (Required)

Discovery captured `PRCG-1027 : Invalid command specified: -version`, so version state is undetermined.

1. Confirm currently installed ZDM build with a supported command in your installed release.
2. If not latest stable, upgrade ZDM before running evaluation/migration.
3. Validate ZDM service health before proceeding.

Reference sources:
- Oracle ZDM documentation: <https://docs.oracle.com/en/database/oracle/zero-downtime-migration/index.html>
- My Oracle Support: search `Zero Downtime Migration`

Pre-migration checklist item (mandatory):
- [ ] Confirm ZDM latest stable version is installed (`zdmcli query jobid -all` to confirm service, OPatch/inventory for version)

---

## Phase 1: Pre-Migration Verification

### 1.1 Source Database Checks

Run on source host as oracle user context:

```bash
export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1
export ORACLE_SID=POCAKV
$ORACLE_HOME/bin/sqlplus -v
$ORACLE_HOME/bin/sqlplus / as sysdba <<'SQL'
set pages 200 lines 200
select name, db_unique_name, open_mode, log_mode, force_logging from v$database;
select instance_name, host_name from v$instance;
select supplemental_log_data_min, supplemental_log_data_pk, supplemental_log_data_ui from v$database;
SQL
```

### 1.2 Target Database Checks

Run on target host with explicit SID pinning:

```bash
export ORACLE_HOME=/u02/app/oracle/product/19.0.0.0/dbhome_1
export ORACLE_SID=POCAKV1
$ORACLE_HOME/bin/sqlplus -v
$ORACLE_HOME/bin/sqlplus / as sysdba <<'SQL'
set pages 200 lines 200
select name, db_unique_name, open_mode from v$database;
select instance_name, host_name from v$instance;
SQL
```

### 1.3 ZDM Server Checks

Run as `zdmuser`:

```bash
export ZDM_HOME=/mnt/app/zdmhome
$ZDM_HOME/bin/zdmcli query job -all
df -h /
free -h
```

### 1.4 Network Connectivity Checks

From ZDM host:

```bash
ping -c 4 10.200.1.12
ping -c 4 10.200.0.250
# Add tnsping or listener checks as required by your network policy.
```

---

## Phase 2: Source Database Configuration

### 2.1 Enable ARCHIVELOG Mode (if not enabled)

```sql
-- Run as SYSDBA on source
shutdown immediate;
startup mount;
alter database archivelog;
alter database open;
archive log list;
```

### 2.2 Enable Force Logging

```sql
alter database force logging;
select force_logging from v$database;
```

### 2.3 Enable Supplemental Logging

```sql
alter database add supplemental log data;
select supplemental_log_data_min from v$database;
```

### 2.4 Configure TNS Entries

Ensure `tnsnames.ora` and listener connectivity include source/target services used by ZDM.

### 2.5 Configure SSH

- Use either agent/default authentication or explicit key paths.
- Ensure key permissions are `600` and owner is correct.

### 2.6 Create/Verify Password File

Ensure source password file exists and SYS password is validated for migration operations.

---

## Phase 3: Target Database Configuration

### 3.1 Configure TNS Entries

Add target service endpoints required for Data Guard and migration validation.

### 3.2 Configure SSH

Validate `zdmuser` connectivity path to target host and oracle account.

### 3.3 Verify OCI Identifiers for RSP

Before evaluation/migration, confirm:

- `TARGET_TENANCY_OCID`
- `TARGET_USER_OCID`
- `TARGET_FINGERPRINT`
- `TARGET_COMPARTMENT_OCID`
- `TARGET_DATABASE_OCID`

OCI CLI is optional and not required.

### 3.4 Prepare Data Guard Path (Online Migration)

Confirm network and listener readiness for `ONLINE_PHYSICAL` migration path.

---

## Phase 4: ZDM Server Configuration

### 4.1 Login Procedure

1. SSH as admin user (for example, `azureuser` or `opc`) to the ZDM host.
2. Switch to ZDM software user:

```bash
sudo su - zdmuser
```

### 4.2 Clone Repository and Navigate to Artifacts

```bash
git clone <your-fork-or-repo-url>
cd <repo>/Artifacts/Phase10-Migration/Step5
```

### 4.3 Create Credentials Directory

```bash
mkdir -p ~/creds
chmod 700 ~/creds
```

### 4.4 Create OCI Environment File

Use `./zdm_commands.sh init` to scaffold `~/zdm_oci_env.sh`, then fill real OCIDs.

### 4.5 Set Password Environment Variables Securely

```bash
export SRC_SYS_PASSWORD='***'
export TGT_SYS_PASSWORD='***'
export TGT_TDE_PASSWORD='***'  # if needed
```

### 4.6 Verify ZDM Installation

```bash
export ZDM_HOME=/mnt/app/zdmhome
$ZDM_HOME/bin/zdmcli help
```

---

## Phase 5: Migration Execution

### 5.1 Initialize Environment

```bash
chmod +x zdm_commands.sh
./zdm_commands.sh init
source ~/zdm_oci_env.sh
```

### 5.2 Create Credential Files

```bash
./zdm_commands.sh create-creds
```

### 5.3 Pre-Migration Evaluation

```bash
./zdm_commands.sh eval
```

### 5.4 Execute Migration

```bash
./zdm_commands.sh migrate
```

### 5.5 Monitor Jobs

```bash
./zdm_commands.sh monitor <job_id>
```

### 5.6 Pause/Resume/Abort

```bash
./zdm_commands.sh resume <job_id>
./zdm_commands.sh abort <job_id>
```

---

## Phase 6: Post-Migration Validation

### 6.1 Data Verification Queries

```sql
-- Run where appropriate after cutover
select name, db_unique_name, open_mode from v$database;
select count(*) from <critical_table>;   -- replace with app-specific checks
```

### 6.2 Application Connectivity Tests

- Run application smoke tests from agreed checklist.
- Confirm connection strings/service endpoints moved to target.

### 6.3 Performance Validation

- Compare baseline metrics (AWR/ASH/app SLA) against acceptance criteria.
- Record results in change ticket evidence.

### 6.4 Switchover (Online Migration)

Follow ZDM-directed switchover step in active job workflow and validate application write readiness before go-live.

---

## Phase 7: Rollback Procedures

1. Define rollback go/no-go criteria before cutover.
2. If rollback is triggered, halt cutover completion and keep source as primary endpoint.
3. Restore application connections to source service endpoints.
4. Validate source database health and data consistency.
5. Document incident timeline and evidence for post-mortem.

---

## Appendix A: Troubleshooting

- `PRCG-1027` on `zdmcli -version`: use supported command set for your release; perform Phase 0 upgrade if needed.
- Target SID confusion in multi-instance environment: always export `TARGET_ORACLE_SID=POCAKV1`.
- Missing OCI variables: source `~/zdm_oci_env.sh` and rerun.
- Credential file permission failures: ensure `~/creds` is `700` and files are `600`.
