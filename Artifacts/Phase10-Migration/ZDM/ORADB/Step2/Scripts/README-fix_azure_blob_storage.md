# README: fix_azure_blob_storage.sh

## Purpose
Configures an **Azure Blob Storage container** as the ZDM staging location for `ONLINE_PHYSICAL` migration and confirms connectivity from the ZDM server. Resolves **Issue 1** and **Issue 6** from the Issue Resolution Log.

**Replaces** `fix_oci_cli_config.sh` — OCI Object Storage is not available because the OCI user is a federated IDCSApp user with API keys disabled and no OCI IAM access.

## Target Server
**ZDM server** — `tm-vm-odaa-oracle-jumpbox` (10.1.0.8)
Run as **`zdmuser`**.

## Prerequisites

1. ZDM server SSH access: `ssh -i ~/.ssh/zdm.pem azureuser@10.1.0.8` then `sudo su - zdmuser`
2. An **Azure Storage Account** with a container (or permission to create one):
   - Same Azure region as the ZDM server, or a region accessible over the network
   - Obtain either an **access key** (full access) or a **SAS token** (scoped access)
3. If using a SAS token, ensure it has the following permissions on the container:
   - `Read`, `Write`, `Delete`, `List`, `Create`
   - Expiry set beyond the expected migration duration

### Optional: Install Azure CLI (recommended)

The script works best with the Azure CLI installed on the ZDM server:

```bash
# On the ZDM server as azureuser (or zdmuser with sudo)
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
sudo dnf install -y https://packages.microsoft.com/config/rhel/8/packages-microsoft-prod.rpm
sudo dnf install -y azure-cli

# Verify
az --version
```

If Azure CLI is not installed, the script requires a SAS token and uses `curl` for connectivity verification and container creation.

## Authentication Methods

| Method | How to Obtain | Permissions Needed |
|--------|--------------|-------------------|
| **Access key** | Azure Portal → Storage Account → Security + networking → Access keys | Full storage account access |
| **SAS token** | Azure Portal → Storage Account → Security + networking → Shared access signature | Read, Write, Delete, List, Create on the container |

> **Security note:** Prefer SAS tokens — they are scoped and have an expiry. Do not store access keys in the repository.

## How to Run

```bash
# 1. SSH to ZDM server and switch to zdmuser
ssh -i ~/.ssh/zdm.pem azureuser@10.1.0.8
sudo su - zdmuser

# 2. Run the script (interactive prompts)
cd ~/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts
bash fix_azure_blob_storage.sh
```

### Non-interactive (via environment variables)

```bash
export AZURE_STORAGE_ACCOUNT="mystorageaccount"
export AZURE_STORAGE_CONTAINER="zdm-oradb-migration"
export AZURE_STORAGE_KEY="<access-key>"          # OR
# export AZURE_STORAGE_SAS="sv=2023-...&sig=..."  # use one or the other

bash fix_azure_blob_storage.sh
```

## What It Does

1. Detects whether **Azure CLI** (`az`) is available; falls back to `curl` with SAS token
2. Prompts for storage account name, container name, and credentials (if not set via env)
3. Tests connectivity — checks whether the container already exists
4. Creates the container with **private access** if it does not exist
5. Writes credentials to `~/.azure/zdm_blob_creds` (permissions `600`)
6. Prints the `zdm-env.md` values and ZDM response file parameters to record

## Credentials File

The script writes to `~/.azure/zdm_blob_creds`:

```
AZURE_STORAGE_ACCOUNT=<account>
AZURE_STORAGE_CONTAINER=zdm-oradb-migration
AZURE_STORAGE_AUTH_TYPE=key|sas
AZURE_STORAGE_AUTH_VALUE=<key or SAS token>
AZURE_BLOB_ENDPOINT=https://<account>.blob.core.windows.net
```

This file is read by `verify_fixes.sh` (BLOCKER 2) and referenced when building the ZDM response file in Step 3. **Do not commit this file to the repository.**

## Expected Output (success)

```
[HH:MM:SS] ✅ PASS  Azure CLI found: 2.xx.x
[HH:MM:SS] ℹ️  INFO  Storage account: mystorageaccount
[HH:MM:SS] ℹ️  INFO  Container: zdm-oradb-migration
[HH:MM:SS] ℹ️  INFO  Auth method: storage account access key
[HH:MM:SS] ✅ PASS  Container 'zdm-oradb-migration' created successfully (private access).
[HH:MM:SS] ✅ PASS  Credentials written to /home/zdmuser/.azure/zdm_blob_creds (permissions 600).
[HH:MM:SS] ✅ PASS  Issue 1 RESOLVED: Azure Blob Storage credentials configured at ...
[HH:MM:SS] ✅ PASS  Issue 6 RESOLVED: Azure Blob container 'zdm-oradb-migration' is ready at ...
```

After running, record the following in `zdm-env.md`:
```
AZURE_STORAGE_ACCOUNT_NAME: <account>
AZURE_STORAGE_CONTAINER_NAME: zdm-oradb-migration
AZURE_BLOB_ENDPOINT: https://<account>.blob.core.windows.net
AZURE_STORAGE_AUTH_TYPE: key|sas
```

## ZDM Response File Parameters (Step 3)

The following parameters are needed in the ZDM RSP file for Step 3. Confirm exact names against ZDM 21.5 documentation (`zdmcli migrate database --help`):

```properties
# Azure Blob Storage staging (ZDM 21.5 — verify parameter names)
COMMON_BACKUP_AZURE_ACCOUNT_NAME=<storage_account_name>
COMMON_BACKUP_AZURE_CONTAINER_NAME=zdm-oradb-migration
COMMON_BACKUP_AZURE_ENDPOINT=https://<account>.blob.core.windows.net
COMMON_BACKUP_AZURE_ACCOUNT_KEY=<key>          # if using access key
# COMMON_BACKUP_AZURE_SAS_TOKEN=<token>         # if using SAS token
```

## Rollback / Undo

To delete credentials file:
```bash
rm ~/.azure/zdm_blob_creds
```

To delete the container (only if empty — **irreversible**):
```bash
# az CLI
az storage container delete \
  --name zdm-oradb-migration \
  --account-name <account> \
  --account-key <key>

# OR curl (SAS)
curl -s -o /dev/null -w "%{http_code}" -X DELETE \
  "https://<account>.blob.core.windows.net/zdm-oradb-migration?restype=container&<sas>"
```
