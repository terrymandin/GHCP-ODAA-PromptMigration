# README: fix_05_discover_oci_namespace.sh

## Purpose
Retrieves the OCI Object Storage namespace for the configured tenancy and outputs the value to populate the `OCI_OSS_NAMESPACE` field in `zdm-env.md` — required before the ZDM response file can be fully configured.

## Target Server
**ZDM server** (`10.1.0.8`) — run locally as `zdmuser` (OCI CLI is already installed and configured for zdmuser).

## Prerequisites
- OCI CLI is installed on the ZDM server (`oci --version` should return `3.73.1` or newer)
- `~/.oci/config` is present for `zdmuser` with a valid API key (confirmed in Step 0 discovery)
- Network connectivity from the ZDM server to OCI API endpoints (`objectstorage.uk-london-1.oraclecloud.com`)
- Run fix_05 **before** fix_06 (namespace is needed for bucket creation)

## Environment Variables

| Variable | Description | Default / Example |
|---|---|---|
| `OCI_CONFIG_PATH` | Path to OCI CLI config file | `~/.oci/config` |
| `OCI_TENANCY_OCID` | OCI Tenancy OCID (for reference / logging only) | From zdm-env.md |

## What It Does
1. **Preflight**: Verifies OCI CLI is installed and `~/.oci/config` exists.
2. **Step 1**: Runs `oci os ns get` to retrieve the Object Storage namespace for the tenancy.
3. **Parses** the JSON response to extract the namespace string.
4. **Displays** the namespace clearly with instructions to update `zdm-env.md`.

## How to Run
```bash
# On ZDM server (10.1.0.8) as zdmuser
su - zdmuser
cd /path/to/scripts
chmod +x fix_05_discover_oci_namespace.sh
./fix_05_discover_oci_namespace.sh
```

## Expected Output
```
============================================================
  OCI Object Storage Namespace: <namespace_string>
============================================================

  ACTION REQUIRED: Update zdm-env.md with this value:
  - OCI_OSS_NAMESPACE: <namespace_string>

  File: prompts/Phase10-Migration/ZDM/zdm-env.md
============================================================
```

## After Running
Update `zdm-env.md`:
```markdown
- OCI_OSS_NAMESPACE: <namespace_string>
```

Then proceed to `fix_06_create_oci_bucket.sh`.

## Rollback / Undo
This script is read-only. No changes are made to any system. Re-run at any time.
