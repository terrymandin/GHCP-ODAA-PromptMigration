# ZDM Migration Artifacts: PRODDB

## Migration Overview

| Field | Value |
|-------|-------|
| **Source Database** | PRODDB on proddb01.corp.example.com (Oracle 19.21.0) |
| **Target Database** | PRODDB_AZURE on Oracle Database@Azure (Oracle 19.0.0) |
| **Migration Method** | ONLINE_PHYSICAL (Data Guard) |
| **Expected Downtime** | Maximum 15 minutes during switchover |
| **ZDM Server** | zdm-jumpbox.corp.example.com |

---

## Prerequisites Checklist

Complete these items before starting the migration:

### OCI/Azure Configuration

| # | Item | Status |
|---|------|--------|
| 1 | Obtain TARGET_TENANCY_OCID from OCI Console | 🔲 |
| 2 | Obtain TARGET_USER_OCID from OCI Console | 🔲 |
| 3 | Obtain TARGET_FINGERPRINT from OCI Console | 🔲 |
| 4 | Obtain TARGET_COMPARTMENT_OCID from OCI Console | 🔲 |
| 5 | Obtain TARGET_DATABASE_OCID from OCI Console | 🔲 |
| 6 | Configure OCI API key at /home/zdmuser/.oci/oci_api_key.pem | 🔲 |

### Password Requirements

| # | Environment Variable | Description | Status |
|---|---------------------|-------------|--------|
| 1 | SOURCE_SYS_PASSWORD | Source Oracle SYS password | 🔲 |
| 2 | TARGET_SYS_PASSWORD | Target Oracle SYS password | 🔲 |
| 3 | SOURCE_TDE_WALLET_PASSWORD | TDE wallet password | 🔲 |

> ⚠️ **SECURITY**: Never commit passwords to source control. Set these environment variables at runtime.

### Network Verification

| # | Item | Status |
|---|------|--------|
| 1 | SSH connectivity from ZDM to source (port 22) | ✅ Verified |
| 2 | SSH connectivity from ZDM to target (port 22) | ✅ Verified |
| 3 | Oracle connectivity from ZDM to source (port 1521) | ✅ Verified |
| 4 | Oracle connectivity from ZDM to target (port 1521) | ✅ Verified |

---

## Generated Artifacts

| File | Description |
|------|-------------|
| [README.md](README.md) | This file - overview and quick start guide |
| [ZDM-Migration-Runbook-PRODDB.md](ZDM-Migration-Runbook-PRODDB.md) | Step-by-step installation and configuration guide |
| [zdm_migrate_PRODDB.rsp](zdm_migrate_PRODDB.rsp) | ZDM response file with all migration parameters |
| [zdm_commands_PRODDB.sh](zdm_commands_PRODDB.sh) | Ready-to-execute CLI commands |

---

## Quick Start Guide

### Step 1: SSH to ZDM Server

```bash
# SSH as the admin user, then switch to zdmuser
ssh azureuser@zdm-jumpbox.corp.example.com
sudo su - zdmuser
```

### Step 2: Clone Repository and Navigate to Artifacts

```bash
# Clone your fork (if not already done)
cd ~
git clone https://github.com/terrymandin/GHCP-ODAA-PromptMigration.git

# Navigate to Step3 artifacts
cd ~/GHCP-ODAA-PromptMigration/Artifacts/Phase10-Migration/ZDM/PRODDB/Step3
```

### Step 3: First-Time Setup (Run Once)

```bash
# Initialize the environment (creates ~/creds and ~/zdm_oci_env.sh)
./zdm_commands_PRODDB.sh init
```

### Step 4: Configure OCI Environment Variables

```bash
# Edit the OCI environment file with your actual OCIDs
vi ~/zdm_oci_env.sh

# Source the environment file
source ~/zdm_oci_env.sh
```

### Step 5: Set Password Environment Variables

```bash
# Set passwords securely (will not echo to screen)
read -sp "Enter SOURCE SYS password: " SOURCE_SYS_PASSWORD; echo; export SOURCE_SYS_PASSWORD
read -sp "Enter TARGET SYS password: " TARGET_SYS_PASSWORD; echo; export TARGET_SYS_PASSWORD
read -sp "Enter TDE wallet password: " SOURCE_TDE_WALLET_PASSWORD; echo; export SOURCE_TDE_WALLET_PASSWORD
```

### Step 6: Create Password Files

```bash
# Create credential files from environment variables
./zdm_commands_PRODDB.sh create-creds
```

### Step 7: Run Evaluation

```bash
# Run evaluation first (dry run)
./zdm_commands_PRODDB.sh eval
```

### Step 8: Execute Migration

```bash
# Start the actual migration
./zdm_commands_PRODDB.sh migrate

# Monitor the job
./zdm_commands_PRODDB.sh status <JOB_ID>
```

### Step 9: Switchover (After Sync Complete)

```bash
# Resume from pause point to perform switchover
./zdm_commands_PRODDB.sh resume <JOB_ID>
```

### Step 10: Cleanup

```bash
# Remove password files after successful migration
./zdm_commands_PRODDB.sh cleanup-creds
```

---

## Important Notes

### Security Considerations

- Password files are created at runtime from environment variables
- Password files are stored in `~/creds/` with 600 permissions
- Always run `cleanup-creds` after successful migration
- Never commit passwords or OCIDs to source control

### Object Storage Note

> **Note:** For ONLINE_PHYSICAL migrations to Oracle Database@Azure, Object Storage is **NOT required**. ZDM uses direct Data Guard redo shipping over the network. The Object Storage parameters in the RSP file are optional and can be left empty unless you specifically need backup staging.

### Rollback Information

The migration pauses at `ZDM_CONFIGURE_DG_SRC` to allow validation before switchover:
- Source database remains operational until switchover
- Data Guard standby can be aborted if issues are found
- Use `./zdm_commands_PRODDB.sh abort <JOB_ID>` for emergency rollback

### Support Contacts

| Role | Contact | Notes |
|------|---------|-------|
| DBA Team | _______________ | Source database |
| Cloud Team | _______________ | Oracle Database@Azure |
| Network Team | _______________ | Connectivity issues |

---

## Migration Summary

| Component | Details |
|-----------|---------|
| **Source** | PRODDB (PRODDB_PRIMARY) on proddb01.corp.example.com:1521 |
| **Target** | PRODDB_AZURE on proddb-oda.eastus.azure.example.com:1521 |
| **Method** | ONLINE_PHYSICAL with Data Guard |
| **Protection Mode** | MAXIMUM_PERFORMANCE |
| **Transport Type** | ASYNC |
| **TDE Enabled** | Yes |
| **Pause Point** | ZDM_CONFIGURE_DG_SRC |
| **Auto Switchover** | No (manual validation before switchover) |

---

*Generated: 2026-02-04*
*ZDM Migration Planning - Step 3*
