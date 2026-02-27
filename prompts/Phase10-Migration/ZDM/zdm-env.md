# ZDM Migration Project Configuration

> **Instructions:** Update the values below for your migration project before running any Example prompts.
> All Example prompts attach this file with `#file:prompts/Phase10-Migration/ZDM/zdm-env.md` so
> GitHub Copilot will use these values automatically when generating scripts and artifacts.

---

## Project Identification

- PROJECT_NAME: PRODDB

> `PROJECT_NAME` is used for all artifact directory paths:
> `Artifacts/Phase10-Migration/ZDM/PRODDB/Step0/Scripts/`, `Step1/`, `Step2/`, `Step3/`

---

## Server Hostnames

- SOURCE_HOST: proddb01.corp.example.com
- TARGET_HOST: proddb-oda.eastus.azure.example.com
- ZDM_HOST: zdm-jumpbox.corp.example.com

---

## SSH Users (admin user for each server)

- SOURCE_SSH_USER: oracle
- TARGET_SSH_USER: opc
- ZDM_SSH_USER: azureuser

---

## SSH Key Paths (separate keys per security domain)

- SOURCE_SSH_KEY: ~/.ssh/onprem_oracle_key
- TARGET_SSH_KEY: ~/.ssh/oci_opc_key
- ZDM_SSH_KEY: ~/.ssh/azure_key

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

- OCI_TENANCY_OCID: ocid1.tenancy.oc1..example
- OCI_USER_OCID: ocid1.user.oc1..example
- OCI_COMPARTMENT_OCID: ocid1.compartment.oc1..example
- OCI_API_KEY_FINGERPRINT: aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99
- OCI_CONFIG_PATH: ~/.oci/config
- OCI_PRIVATE_KEY_PATH: ~/.oci/oci_api_key.pem

### OCI Object Storage

- OCI_OSS_NAMESPACE: example_namespace
- OCI_OSS_BUCKET_NAME: zdm-migration-bucket