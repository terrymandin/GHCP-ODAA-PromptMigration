# ZDM Migration Runbook

## Migration: POCAKV -> POCAKV_ODAA

### Document Information

| Field | Value |
|-------|-------|
| Source Database | POCAKV |
| Target Database | POCAKV_ODAA |
| Source Host | 10.200.1.12 (factvmhost) |
| Target Host | 10.200.0.250 (vmclusterpoc-ytlat1) |
| Migration Type | ONLINE_PHYSICAL (default) |
| ZDM Home | /mnt/app/zdmhome |
| Created Date | 2026-03-17 |

## Phase 0: Pre-Migration ZDM Version Gate

Step 2 captured `PRCG-1027` for `zdmcli -version`, so version evidence is incomplete.

1. Confirm installed ZDM build with supported commands from Oracle docs/MOS.
2. Upgrade to latest stable release if outdated/undetermined.
3. Re-run Step 4 verification and archive evidence in `Artifacts/Phase10-Migration/Step4/Verification/`.
4. Ensure item is complete before cutover: `[ ] Confirm ZDM latest stable version is installed`.

## Phase 1: Pre-Migration Verification

### 1.1 Source Database Checks

```bash
ssh azureuser@10.200.1.12
sudo su - oracle
export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1
export ORACLE_SID=POCAKV
$ORACLE_HOME/bin/sqlplus -v
ps -ef | grep pmon
```

### 1.2 Target Database Checks

```bash
ssh opc@10.200.0.250
sudo su - oracle
export ORACLE_HOME=/u02/app/oracle/product/19.0.0.0/dbhome_1
export ORACLE_SID=POCAKV1
$ORACLE_HOME/bin/sqlplus -v
ps -ef | grep pmon
```

### 1.3 ZDM Server Checks

```bash
ssh <ZDM_ADMIN_USER>@<zdm-host>
sudo su - zdmuser
/mnt/app/zdmhome/bin/zdmcli -help
mkdir -p ~/creds
chmod 700 ~/creds
df -h /
```

### 1.4 OCI and Password Variables

Create `~/zdm_oci_env.sh` with OCI values and source it:

```bash
cat > ~/zdm_oci_env.sh <<'EOF'
export TARGET_TENANCY_OCID="ocid1.tenancy.oc1..xxxx"
export TARGET_USER_OCID="ocid1.user.oc1..xxxx"
export TARGET_FINGERPRINT="aa:bb:cc:dd:..."
export TARGET_COMPARTMENT_OCID="ocid1.compartment.oc1..xxxx"
export TARGET_DATABASE_OCID="ocid1.database.oc1..xxxx"
# Required for OFFLINE_PHYSICAL only:
export TARGET_OBJECT_STORAGE_NAMESPACE=""
EOF
chmod 600 ~/zdm_oci_env.sh
source ~/zdm_oci_env.sh

read -sp "Enter SOURCE SYS password: " SOURCE_SYS_PASSWORD; echo; export SOURCE_SYS_PASSWORD
read -sp "Enter TARGET SYS password: " TARGET_SYS_PASSWORD; echo; export TARGET_SYS_PASSWORD
```

## Phase 2: Source Database Configuration

Execute as source `oracle` user and DBA team:

```sql
-- SQL*Plus as SYSDBA
archive log list;
alter database force logging;
alter database add supplemental log data;
```

Confirm listener/service reachability and TNS aliases from ZDM host.

## Phase 3: Target Database Configuration

1. Confirm target SID pinning remains `POCAKV1`.
2. Validate listener and service registration for target DB unique name `POCAKV_ODAA`.
3. Confirm SSH access path from ZDM host with selected key/agent strategy.
4. Ensure target SYS credentials are valid for migration window.

## Phase 4: ZDM Artifact Setup

On jumpbox/ZDM server (from repo clone):

```bash
cd <repo-root>/Artifacts/Phase10-Migration/Step5
chmod +x zdm_commands_POCAKV.sh
./zdm_commands_POCAKV.sh init
source ~/zdm_oci_env.sh
./zdm_commands_POCAKV.sh create-creds
```

## Phase 5: Migration Execution

### 5.1 Evaluation

```bash
./zdm_commands_POCAKV.sh eval
```

Capture the eval output and remediate any reported issues before production run.

### 5.2 Migration

```bash
./zdm_commands_POCAKV.sh migrate
```

### 5.3 Monitoring and Control

```bash
./zdm_commands_POCAKV.sh monitor
# then run listed query commands with real JOB_ID

./zdm_commands_POCAKV.sh resume <JOB_ID>
./zdm_commands_POCAKV.sh abort <JOB_ID>
```

## Phase 6: Post-Migration Validation

1. Validate application connectivity against target.
2. Execute data consistency checks agreed by DBA/app teams.
3. Validate performance baseline after cutover.
4. Update operational runbooks and monitoring targets.

## Phase 7: Rollback Procedure (High-Level)

1. Trigger rollback decision based on predefined go/no-go criteria.
2. Stop application writes to target if required.
3. Use approved ZDM rollback/fallback method for migration type.
4. Redirect application connectivity back to source.
5. Document incident timeline and corrective actions.

## Security and Cleanup

After migration completion:

```bash
cd <repo-root>/Artifacts/Phase10-Migration/Step5
./zdm_commands_POCAKV.sh cleanup-creds
unset SOURCE_SYS_PASSWORD TARGET_SYS_PASSWORD SOURCE_TDE_WALLET_PASSWORD
```

## Evidence to Archive

- Eval and migrate command outputs
- Job status snapshots
- Post-migration validation results
- Final Step 4 verification summary file
