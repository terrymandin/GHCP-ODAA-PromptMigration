# ZDM Migration Artifacts: PRODDB

## Migration Overview

| Field | Value |
|-------|-------|
| **Source Database** | PRODDB (PRODDB_PRIMARY) on proddb01.corp.example.com |
| **Target Database** | PRODDB (PRODDB_AZURE) on Oracle Database@Azure |
| **Migration Method** | ONLINE_PHYSICAL (Data Guard) |
| **Expected Downtime** | ≤ 15 minutes during switchover |
| **Generated Date** | 2026-02-04 |

---

## Prerequisites Checklist

Complete these items before starting migration:

### OCI Configuration (Required)

| Item | Status | Notes |
|------|--------|-------|
| OCI CLI installed on ZDM server | 🔲 | Required for ZDM to interact with OCI |
| OCI API key configured | 🔲 | Private key at /home/zdmuser/.oci/oci_api_key.pem |
| OCI environment variables set | 🔲 | See [Environment Variables](#environment-variables) |

### Network Connectivity (Verified in Discovery)

| Path | SSH (22) | Oracle (1521) | Status |
|------|----------|---------------|--------|
| ZDM → Source | ✅ | ✅ | Ready |
| ZDM → Target | ✅ | ✅ | Ready |

### Credentials

| Item | Status | Notes |
|------|--------|-------|
| Password environment variables | 🔲 | Set at runtime (see [Password Configuration](#password-configuration)) |
| SSH keys configured | 🔲 | zdm_migration_key for source/target access |
| TDE wallet password available | 🔲 | Required since TDE is enabled |

---

## Generated Artifacts

| File | Description | Usage |
|------|-------------|-------|
| [README.md](README.md) | This file - quick start guide | Reference during migration |
| [ZDM-Migration-Runbook-PRODDB.md](ZDM-Migration-Runbook-PRODDB.md) | Step-by-step migration runbook | Follow during migration execution |
| [zdm_migrate_PRODDB.rsp](zdm_migrate_PRODDB.rsp) | ZDM response file | Configuration for ZDM CLI |
| [zdm_commands_PRODDB.sh](zdm_commands_PRODDB.sh) | ZDM CLI commands script | Execute migration commands |

---

## Environment Variables

### OCI Environment Variables (Required)

Set these on the ZDM server before running migration:

```bash
# Target OCI Configuration (REQUIRED)
export TARGET_TENANCY_OCID="ocid1.tenancy.oc1..aaaaaaaabcdefghijklmnopqrstuvwxyz123456789"
export TARGET_USER_OCID="ocid1.user.oc1..aaaaaaaaxyz987654321abcdefghijklmnopqrstuv"
export TARGET_FINGERPRINT="aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99"
export TARGET_COMPARTMENT_OCID="<Your Compartment OCID>"
export TARGET_DATABASE_OCID="ocid1.database.oc1.iad..aaaaaaaaproddbazure67890"

# Object Storage (OPTIONAL for ONLINE_PHYSICAL to Oracle Database@Azure)
# Only required for OFFLINE_PHYSICAL migrations
# export TARGET_OBJECT_STORAGE_NAMESPACE="examplecorp"
```

### Password Configuration

> ⚠️ **SECURITY**: Passwords are NEVER stored in files or scripts. Set these environment variables at runtime.

```bash
# Required password environment variables (set before running migration)
export SOURCE_SYS_PASSWORD="<source SYS password>"
export TARGET_SYS_PASSWORD="<target SYS password>"
export SOURCE_TDE_WALLET_PASSWORD="<TDE wallet password>"
```

For secure password entry:
```bash
read -sp "Enter Source SYS Password: " SOURCE_SYS_PASSWORD; echo; export SOURCE_SYS_PASSWORD
read -sp "Enter Target SYS Password: " TARGET_SYS_PASSWORD; echo; export TARGET_SYS_PASSWORD
read -sp "Enter TDE Wallet Password: " SOURCE_TDE_WALLET_PASSWORD; echo; export SOURCE_TDE_WALLET_PASSWORD
```

---

## Quick Start Guide

### Step 1: Log into ZDM Server

```bash
# SSH as your admin user (azureuser in this example - NOT directly as zdmuser)
ssh azureuser@zdm-jumpbox.corp.example.com

# Switch to zdmuser
sudo su - zdmuser
```

### Step 2: First-Time Setup (run once)

```bash
# Navigate to Step3 artifacts in your cloned fork
cd /path/to/GHCP-ODAA-PromptMigration/Artifacts/Phase10-Migration/ZDM/PRODDB/Step3

# Make script executable
chmod +x zdm_commands_PRODDB.sh

# Initialize environment (creates ~/creds directory and ~/zdm_oci_env.sh template)
./zdm_commands_PRODDB.sh init
```

### Step 3: Configure OCI Environment

```bash
# Edit the generated OCI environment file with actual OCID values
vi ~/zdm_oci_env.sh

# Source the OCI environment variables
source ~/zdm_oci_env.sh
```

### Step 4: Set Password Environment Variables

```bash
# Set password environment variables (securely)
read -sp "Enter Source SYS Password: " SOURCE_SYS_PASSWORD; echo; export SOURCE_SYS_PASSWORD
read -sp "Enter Target SYS Password: " TARGET_SYS_PASSWORD; echo; export TARGET_SYS_PASSWORD
read -sp "Enter TDE Wallet Password: " SOURCE_TDE_WALLET_PASSWORD; echo; export SOURCE_TDE_WALLET_PASSWORD

# Create password files from environment variables
./zdm_commands_PRODDB.sh create-creds
```

### Step 5: Run Evaluation (Dry Run)

```bash
# Run preflight checks
./zdm_commands_PRODDB.sh preflight

# Run evaluation
./zdm_commands_PRODDB.sh eval
```

Review evaluation results before proceeding.

### Step 6: Execute Migration

```bash
# Start migration
./zdm_commands_PRODDB.sh migrate

# Monitor progress (in separate terminal)
./zdm_commands_PRODDB.sh status <JOB_ID>
```

### Step 7: Post-Migration Validation

Follow the validation steps in the runbook:
- Verify Data Guard configuration
- Check database connectivity
- Validate application connections
- Run data verification queries

### Step 8: Switchover (When Ready)

```bash
# Resume migration after pause point for switchover
./zdm_commands_PRODDB.sh resume <JOB_ID>
```

### Step 9: Cleanup

```bash
# Clean up password files after migration
./zdm_commands_PRODDB.sh cleanup-creds
```

---

## Important Notes

### Security Considerations

- **Password files** are created at runtime and should be cleaned up after migration
- **SSH keys** should have restricted permissions (600)
- **OCI API keys** should be rotated after migration is complete
- **Never commit** passwords or OCI identifiers to source control

### Rollback Information

The migration uses Data Guard which provides built-in rollback capability:
- Before switchover: Simply terminate the Data Guard configuration
- After switchover: Failback to original source (requires additional configuration)

Rollback window: Keep source database operational for at least 7 days post-migration.

### Support Contacts

| Role | Contact |
|------|---------|
| DBA Team | dba-team@example.com |
| Network Team | network-team@example.com |
| Application Team | app-team@example.com |
| Oracle Support | Submit SR via My Oracle Support |

---

## Key Parameters Summary

### Source Database

| Parameter | Value |
|-----------|-------|
| Database Name | PRODDB |
| Unique Name | PRODDB_PRIMARY |
| Host | proddb01.corp.example.com |
| Port | 1521 |
| Service | PRODDB.corp.example.com |
| Oracle Home | /u01/app/oracle/product/19.21.0/dbhome_1 |
| TDE Enabled | Yes |
| TDE Wallet | /u01/app/oracle/admin/PRODDB/wallet/tde |

### Target Database

| Parameter | Value |
|-----------|-------|
| Database Name | PRODDB |
| Unique Name | PRODDB_AZURE |
| Host | proddb-oda.eastus.azure.example.com |
| Port | 1521 |
| Service | PRODDB_AZURE.eastus.azure.example.com |
| Oracle Home | /u02/app/oracle/product/19.0.0.0/dbhome_1 |

### ZDM Server

| Parameter | Value |
|-----------|-------|
| ZDM Home | /opt/oracle/zdm21c |
| Host | zdm-jumpbox.corp.example.com |
| User | zdmuser |
| SSH Key | /home/zdmuser/.ssh/zdm_migration_key |

---

## Next Steps After Migration

1. ✅ Verify all applications connect to target database
2. ✅ Run performance baseline tests
3. ✅ Update DNS/connection strings (if applicable)
4. ✅ Clean up password files: `rm -f /home/zdmuser/creds/*.txt`
5. ✅ Decommission source database (after retention period)
6. ✅ Document lessons learned

---

*Generated by ZDM Migration Planning - Step 3*
*Date: 2026-02-04*
