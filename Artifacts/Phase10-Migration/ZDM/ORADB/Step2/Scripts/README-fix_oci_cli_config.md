# README: fix_oci_cli_config.sh

> ## ⚠️ SUPERSEDED — 2026-03-04
> This script is **no longer used** for this migration.
> **Replaced by: [`fix_azure_blob_storage.sh`](fix_azure_blob_storage.sh)** — see [`README-fix_azure_blob_storage.md`](README-fix_azure_blob_storage.md)
>
> **Reason:** The OCI user (`temandin@microsoft.com`) is a federated IDCSApp user with API keys disabled.
> No OCI IAM, Instance Principal, or service account access is available.
> Azure Blob Storage is used instead.

---

## Original Purpose (Reference Only)
Would have created the OCI CLI configuration file for `zdmuser` on the ZDM server and created the OCI Object Storage bucket required for ZDM `ONLINE_PHYSICAL` migration. Would have resolved **Issue 1** and **Issue 6** from the Issue Resolution Log.

## Target Server
**ZDM server** — `tm-vm-odaa-oracle-jumpbox` (10.1.0.8)
Run as **`zdmuser`**.

## Prerequisites
1. ZDM server SSH access to the jumpbox as `azureuser` (then `sudo su - zdmuser`)
2. OCI CLI must be installed (`oci --version` must succeed as `zdmuser`)
3. OCI API private key (`oci_api_key.pem`) must be uploaded **before** running this script:
   ```bash
   # From your local machine or a host with the key:
   scp -i ~/.ssh/zdm.pem /path/to/oci_api_key.pem azureuser@10.1.0.8:/tmp/oci_api_key.pem

   # On the ZDM server as azureuser:
   sudo mkdir -p /home/zdmuser/.oci
   sudo mv /tmp/oci_api_key.pem /home/zdmuser/.oci/oci_api_key.pem
   sudo chown zdmuser:zdmuser /home/zdmuser/.oci/oci_api_key.pem
   sudo chmod 600 /home/zdmuser/.oci/oci_api_key.pem
   ```
4. OCI credentials in `zdm-env.md` must be current (user OCID, tenancy OCID, fingerprint)

## Environment Variables
All values are hardcoded from `zdm-env.md`. The following are used:

| Variable | Description | Value |
|----------|-------------|-------|
| `OCI_USER_OCID` | OCI user OCID | `ocid1.user.oc1..aaaaaaaakfe5...` |
| `OCI_TENANCY_OCID` | OCI tenancy OCID | `ocid1.tenancy.oc1..aaaaaaaarvy...` |
| `OCI_FINGERPRINT` | API key fingerprint | `7f:05:c1:f2:5c:3a:46:ec:...` |
| `OCI_REGION` | OCI region | `uk-london-1` |
| `OCI_PRIVATE_KEY_PATH` | Path to private key (zdmuser context) | `~/.oci/oci_api_key.pem` |
| `OCI_COMPARTMENT_OCID` | Compartment for bucket creation | `ocid1.compartment.oc1...` |
| `OCI_BUCKET_NAME` | Object Storage bucket name | `zdm-oradb-migration` |

## What It Does
1. Verifies the OCI CLI binary is in PATH
2. Checks the private key exists at `~/.oci/oci_api_key.pem` and has `600` permissions
3. Creates `~/.oci/` directory (if absent)
4. Writes `~/.oci/config` with `[DEFAULT]` profile and all required fields
5. Sets `~/.oci/config` permissions to `600`
6. Tests OCI connectivity via `oci os ns get` to retrieve the Object Storage namespace
7. Checks if bucket `zdm-oradb-migration` already exists; creates it if not

## How to Run
```bash
# 1. SSH to ZDM server and switch to zdmuser
ssh -i ~/.ssh/zdm.pem azureuser@10.1.0.8
sudo su - zdmuser

# 2. Run the script
cd ~/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts
bash fix_oci_cli_config.sh
```

## Expected Output
```
[HH:MM:SS] ✅ PASS  OCI CLI found: 3.73.1
[HH:MM:SS] ✅ PASS  Private key found at /home/zdmuser/.oci/oci_api_key.pem with permissions 600.
[HH:MM:SS] ✅ PASS  OCI config written to /home/zdmuser/.oci/config with permissions 600.
[HH:MM:SS] ✅ PASS  OCI connectivity verified. Object Storage namespace: <namespace>
[HH:MM:SS] ✅ PASS  Bucket 'zdm-oradb-migration' created successfully.
[HH:MM:SS] ✅ PASS  Issue 1 RESOLVED: OCI CLI config created at /home/zdmuser/.oci/config
[HH:MM:SS] ✅ PASS  Issue 6 RESOLVED: OCI Object Storage bucket 'zdm-oradb-migration' is ready
```
After running, the namespace value must be recorded in `zdm-env.md`:
```
OCI_OSS_NAMESPACE: <value returned>
OCI_OSS_BUCKET_NAME: zdm-oradb-migration
```

## Rollback / Undo
The script backs up any existing config as `~/.oci/config.bak` before overwriting.
To restore:
```bash
cp ~/.oci/config.bak ~/.oci/config
```
To delete the created bucket (only if empty):
```bash
oci os bucket delete \
  --config-file ~/.oci/config \
  --namespace <namespace> \
  --bucket-name zdm-oradb-migration \
  --force
```
