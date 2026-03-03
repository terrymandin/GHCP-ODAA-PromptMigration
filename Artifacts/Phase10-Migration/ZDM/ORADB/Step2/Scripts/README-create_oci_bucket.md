# README: create_oci_bucket.sh

## Purpose
Creates the OCI Object Storage bucket required for ZDM ONLINE_PHYSICAL migration, retrieves the namespace, and prints the values to update in `zdm-env.md`.

## Target Server
**ZDM server** — `tm-vm-odaa-oracle-jumpbox` (10.1.0.8)  
**Run as:** `zdmuser`

## Prerequisites
- [ ] OCI CLI installed on the ZDM server and in `zdmuser`'s PATH
- [ ] OCI CLI config present at `~/.oci/config` (under zdmuser home)
- [ ] OCI private key at `~/.oci/oci_api_key.pem` with permissions `600`
- [ ] `verify_oci_cli_zdmuser.sh` has been run and all checks passed
- [ ] zdmuser account has network access to OCI API endpoints (https://objectstorage.uk-london-1.oraclecloud.com)

## Environment Variables
All configuration is hardcoded from discovered values. No external environment variables are required.

| Variable | Description | Value |
|----------|-------------|-------|
| `DATABASE_NAME` | Database identifier used for log paths | `ORADB` |
| `OCI_COMPARTMENT_OCID` | OCI compartment where the bucket will be created | `ocid1.compartment.oc1..aaaaaaaas4upnqj7...` |
| `OCI_REGION` | OCI region for the bucket | `uk-london-1` |
| `BUCKET_NAME` | Name of the bucket to create | `zdm-migration-oradb-YYYYMMDD` |
| `OCI_CONFIG_PATH` | Path to OCI CLI config file | `~/.oci/config` |

## What It Does
1. Verifies OCI CLI is installed and config exists
2. Calls `oci os ns get` to retrieve the Object Storage namespace for the tenancy
3. Checks if the bucket already exists to avoid duplicate creation errors
4. Creates bucket `zdm-migration-oradb-YYYYMMDD` in the `uk-london-1` region under the configured compartment
5. Verifies the bucket is accessible via `oci os bucket get`
6. Prints the **namespace** and **bucket name** values to be manually entered in `zdm-env.md`

## How to Run
```bash
# Switch to zdmuser on ZDM server
sudo su - zdmuser

cd ~/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts
chmod +x create_oci_bucket.sh
./create_oci_bucket.sh
```

## Expected Output
```
==============================================================
  ZDM Step 2: Create OCI Object Storage Bucket
  ...
  ✅ PASS: OCI CLI found: 3.73.1
  ✅ PASS: OCI config found at /home/zdmuser/.oci/config
  ✅ PASS: Object Storage namespace: <your-namespace>
  ✅ PASS: Bucket 'zdm-migration-oradb-20260303' created successfully
  ✅ PASS: Bucket verified: zdm-migration-oradb-20260303
==============================================================
  ✅ SUCCESS — Bucket created and verified

  ACTION REQUIRED: Update zdm-env.md with these values
  File: prompts/Phase10-Migration/ZDM/zdm-env.md

  OCI_OSS_NAMESPACE: <your-namespace>
  OCI_OSS_BUCKET_NAME: zdm-migration-oradb-20260303
==============================================================
```

After the script completes, manually update `prompts/Phase10-Migration/ZDM/zdm-env.md`:
```markdown
- OCI_OSS_NAMESPACE: <value printed by script>
- OCI_OSS_BUCKET_NAME: zdm-migration-oradb-20260303
```

## Rollback / Undo
To delete the bucket (it must be empty):
```bash
# Get namespace if not known
oci os ns get --config-file ~/.oci/config

# Delete bucket (must be empty first)
oci os bucket delete \
  --namespace-name <namespace> \
  --bucket-name zdm-migration-oradb-20260303 \
  --config-file ~/.oci/config \
  --region uk-london-1 \
  --force
```

> **Note:** If the bucket already has objects in it (e.g., from a partial ZDM run), bulk-delete all objects first:
> ```bash
> oci os object bulk-delete \
>   --namespace-name <namespace> \
>   --bucket-name zdm-migration-oradb-20260303 \
>   --config-file ~/.oci/config \
>   --force
> ```
