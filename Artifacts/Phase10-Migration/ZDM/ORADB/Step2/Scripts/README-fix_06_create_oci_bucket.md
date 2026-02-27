# README: fix_06_create_oci_bucket.sh

## Purpose
Creates the OCI Object Storage bucket (`zdm-oradb-migration`) in the `uk-london-1` region that ZDM will use as the data transfer medium to copy RMAN backup sets from the source Oracle database to the target ODAA system.

## Target Server
**ZDM server** (`10.1.0.8`) — run locally as `zdmuser`.

## Prerequisites
- `fix_05_discover_oci_namespace.sh` has been run and `OCI_OSS_NAMESPACE` is known
- OCI CLI is installed and configured for `zdmuser` (`~/.oci/config` present)
- The OCI user (`OCI_USER_OCID`) has the `OBJECT-STORAGE-NAMESPACE-READ` and `BUCKET-CREATE` permissions in the compartment
- `OCI_COMPARTMENT_OCID` is correct (from `zdm-env.md`)
- Bucket name `zdm-oradb-migration` is not already in use in the tenancy/namespace

## Environment Variables

| Variable | Description | Default / Example |
|---|---|---|
| `OCI_CONFIG_PATH` | OCI CLI config file path | `~/.oci/config` |
| `OCI_COMPARTMENT_OCID` | Target compartment OCID | From zdm-env.md |
| `OCI_OSS_NAMESPACE` | Object Storage namespace | Auto-detected if blank (calls `oci os ns get`) |
| `OCI_REGION` | OCI region for the bucket | `uk-london-1` |
| `OCI_OSS_BUCKET_NAME` | Bucket name to create | `zdm-oradb-migration` |

## What It Does
1. **Preflight**: Verifies OCI CLI and config are present.
2. **Auto-detects** `OCI_OSS_NAMESPACE` if not set (calls `oci os ns get`).
3. **Step 1**: Checks whether the bucket already exists — skips creation if it does.
4. **Step 2**: Creates the bucket with versioning disabled (not needed for ZDM staging).
5. **Step 3**: Verifies the bucket is accessible with `oci os bucket get`.
6. **Outputs** the bucket name and namespace for recording in `zdm-env.md`.

## How to Run
```bash
# On ZDM server (10.1.0.8) as zdmuser
su - zdmuser
chmod +x fix_06_create_oci_bucket.sh

# With namespace already known:
OCI_OSS_NAMESPACE=<namespace> ./fix_06_create_oci_bucket.sh

# Or let the script auto-detect namespace:
./fix_06_create_oci_bucket.sh
```

## Expected Output
```
============================================================
  OCI Object Storage Bucket Ready
  Bucket Name : zdm-oradb-migration
  Namespace   : <namespace_string>
  Region      : uk-london-1

  ACTION REQUIRED: Update zdm-env.md with these values:
  - OCI_OSS_NAMESPACE:   <namespace_string>
  - OCI_OSS_BUCKET_NAME: zdm-oradb-migration
============================================================
```

## After Running
Update `zdm-env.md`:
```markdown
- OCI_OSS_NAMESPACE: <namespace_string>
- OCI_OSS_BUCKET_NAME: zdm-oradb-migration
```

## Rollback / Undo
To remove the bucket (only if no objects have been uploaded):
```bash
oci os bucket delete --bucket-name zdm-oradb-migration --namespace <namespace> --force
```
If objects are present, empty the bucket first:
```bash
oci os object bulk-delete --bucket-name zdm-oradb-migration --namespace <namespace> --force
oci os bucket delete --bucket-name zdm-oradb-migration --namespace <namespace> --force
```
