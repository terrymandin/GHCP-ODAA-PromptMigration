# ZDM Migration Project Configuration — Example / Template
> **Setup:** Copy this file to `zdm-env.md` in the same directory and fill in your real values.
> `zdm-env.md` is git-ignored so your environment-specific values are never committed.
>
> All Example prompts attach `zdm-env.md` with `#file:prompts/Phase10-Migration/ZDM/zdm-env.md` so
> GitHub Copilot will use these values automatically when generating scripts and artifacts.
---
## Project Identification
- PROJECT_NAME: <YOUR_PROJECT_NAME>
> `PROJECT_NAME` is used for all artifact directory paths:
> `Artifacts/Phase10-Migration/ZDM/<YOUR_PROJECT_NAME>/Step0/Scripts/`, `Step1/`, `Step2/`, `Step3/`
---
## Server Hostnames
- SOURCE_HOST: <SOURCE_HOST_IP_OR_FQDN>
- TARGET_HOST: <TARGET_HOST_IP_OR_FQDN>
- ZDM_HOST: <ZDM_HOST_IP_OR_FQDN>
---
## SSH Users (admin user for each server)
- SOURCE_SSH_USER: <SOURCE_SSH_USER>
- TARGET_SSH_USER: <TARGET_SSH_USER>
- ZDM_SSH_USER: <ZDM_SSH_USER>
---
## SSH Key Paths (separate keys per security domain)
- SOURCE_SSH_KEY: ~/.ssh/<source_key>.pem
- TARGET_SSH_KEY: ~/.ssh/<target_key>.pem
- ZDM_SSH_KEY: ~/.ssh/<zdm_key>.pem
---
## Application User Configuration
- ORACLE_USER: oracle
- ZDM_SOFTWARE_USER: zdmuser
---
## Oracle Path Overrides
Leave blank to allow auto-detection via `/etc/oratab` and common paths. Set only if auto-detection fails.
- SOURCE_REMOTE_ORACLE_HOME: 
- SOURCE_REMOTE_ORACLE_SID: 
- TARGET_REMOTE_ORACLE_HOME: 
- TARGET_REMOTE_ORACLE_SID:
---
## OCI/Azure Configuration (non-sensitive identifiers)
- OCI_TENANCY_OCID: ocid1.tenancy.oc1..<YOUR_TENANCY_OCID>
- OCI_USER_OCID: ocid1.user.oc1..<YOUR_USER_OCID>
- OCI_COMPARTMENT_OCID: ocid1.compartment.oc1..<YOUR_COMPARTMENT_OCID>
- TARGET_DATABASE_OCID: ocid1.database.oc1.<region>.<YOUR_DATABASE_OCID>
- OCI_API_KEY_FINGERPRINT: <xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx>
- OCI_CONFIG_PATH: ~/.oci/config
- OCI_PRIVATE_KEY_PATH: ~/.oci/oci_api_key.pem
### OCI Object Storage
- OCI_OSS_NAMESPACE: 
- OCI_OSS_BUCKET_NAME: 
