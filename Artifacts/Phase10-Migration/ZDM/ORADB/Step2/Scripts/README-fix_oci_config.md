# README: fix_oci_config.sh

## Purpose
Creates and validates the OCI CLI configuration file (`~/.oci/config`) for `zdmuser` on the ZDM server, and confirms OCI API connectivity — resolving **Issue 3 (Blocker)** from the ORADB Discovery Summary. ZDM requires OCI API access to interact with OCI Object Storage (backup staging) and to validate the target database configuration.

---

## Target Server
**ZDM Server only** — run as `zdmuser` directly on `tm-vm-odaa-oracle-jumpbox` (10.1.0.8).  
No SSH to source or target is required. This script operates entirely on the ZDM server.

---

## Prerequisites

| Requirement | Detail |
|-------------|--------|
| Run as | `zdmuser` on the ZDM server |
| OCI CLI | Already installed (version 3.73.1 confirmed in discovery ✅) |
| OCI API private key | `/home/zdmuser/.oci/oci_api_key.pem` must exist on the ZDM server before running |
| OCI API public key uploaded | Corresponding public key must be registered in OCI Console → Identity → Users → API Keys |
| Issues 1 & 2 | Recommended to resolve Issues 1 and 2 first, but this script can run independently |

### How to upload the OCI API private key to the ZDM server

If the key file is not yet on the ZDM server, transfer it from your workstation:

```bash
# From your workstation (with access to ZDM server via its admin user):
scp -i ~/.ssh/zdm.pem /path/to/oci_api_key.pem azureuser@10.1.0.8:/tmp/oci_api_key.pem

# Then on the ZDM server as zdmuser:
sudo su - zdmuser
mkdir -p ~/.oci
mv /tmp/oci_api_key.pem ~/.oci/oci_api_key.pem
chmod 600 ~/.oci/oci_api_key.pem
```

---

## Environment Variables

All variables have hard-coded defaults from `zdm-env.md`. Override by exporting before running if values differ.

| Variable | Description | Default / Value |
|----------|-------------|-----------------|
| `OCI_TENANCY_OCID` | OCI Tenancy OCID | `ocid1.tenancy.oc1..aaaaaaaarvyh...` |
| `OCI_USER_OCID` | OCI User OCID | `ocid1.user.oc1..aaaaaaaakfe5...` |
| `OCI_REGION` | OCI home region (must match target DB region) | `uk-london-1` |
| `OCI_FINGERPRINT` | API key fingerprint | `7f:05:c1:f2:5c:3a:46:ec:9f:95:44:c8:77:a4:50:f9` |
| `OCI_PRIVATE_KEY_PATH` | Path to OCI API private key on ZDM server | `~/.oci/oci_api_key.pem` |
| `TARGET_DATABASE_OCID` | Target Oracle DB OCID for access validation | `ocid1.database.oc1.uk-london-1.anwg...` |

---

## What It Does

1. **User guard** — Exits immediately if not running as `zdmuser`.
2. **OCI CLI check** — Confirms `oci` binary is in PATH and prints its version.
3. **Private key check** — Verifies `~/.oci/oci_api_key.pem` exists. If missing, prints detailed instructions on how to transfer it. Also ensures file permissions are `600`.
4. **Backup existing config** — If `~/.oci/config` already exists, creates a timestamped backup before overwriting.
5. **Write config** — Creates `~/.oci/config` with the `[DEFAULT]` profile populated from `zdm-env.md` values.
6. **Connectivity test** — Runs `oci os ns get` to confirm OCI API authentication is working and retrieves the Object Storage namespace.
7. **Target DB validation** — Attempts `oci db database get` for the target database OCID to confirm IAM permissions. Warns (does not fail) if this check fails, as the namespace test is the primary validator.
8. **Summary** — Prints the retrieved namespace and next steps, including how to create the Object Storage bucket.

---

## How to Run

```bash
# Switch to zdmuser on the ZDM server
sudo su - zdmuser

# Navigate to scripts directory
cd ~/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts

# Make executable and run
chmod +x fix_oci_config.sh
./fix_oci_config.sh
```

---

## Expected Output

```
============================================================
  fix_oci_config.sh — Issue 3: Configure OCI CLI for zdmuser
============================================================

[2026-03-02 22:10:00 UTC] Running as: zdmuser on tm-vm-odaa-oracle-jumpbox

[2026-03-02 22:10:00 UTC] Checking OCI CLI installation ...
✅ OCI CLI found: 3.73.1

[2026-03-02 22:10:01 UTC] Checking OCI API private key at: /home/zdmuser/.oci/oci_api_key.pem ...
✅ OCI API private key found and permissions OK

[2026-03-02 22:10:01 UTC] Creating OCI config at: /home/zdmuser/.oci/config ...
   Existing config backed up to: /home/zdmuser/.oci/config.bak.20260302221001
✅ ~/.oci/config written successfully.

--- Config summary ---
[DEFAULT]
  user        = ocid1.user.oc1..aaaaaaaakfe5...
  fingerprint = 7f:05:c1:f2:5c:3a:46:ec:9f:95:44:c8:77:a4:50:f9
  tenancy     = ocid1.tenancy.oc1..aaaaaaaarvy...
  region      = uk-london-1
  key_file    = /home/zdmuser/.oci/oci_api_key.pem

[2026-03-02 22:10:02 UTC] Testing OCI CLI connectivity (oci os ns get) ...
✅ OCI CLI connectivity confirmed.
   Object Storage Namespace: axxxxxxxxxxx

   ⚠️  ACTION REQUIRED: Record this namespace in the Migration Questionnaire
   (Section C — Object Storage Configuration, OCI_OSS_NAMESPACE field).
   Namespace value: axxxxxxxxxxx

[2026-03-02 22:10:05 UTC] Verifying target database OCID access ...
✅ Target database accessible via OCI API. Lifecycle state: AVAILABLE

============================================================
  fix_oci_config.sh — Summary
============================================================

✅ OCI config created at /home/zdmuser/.oci/config
✅ OCI CLI can authenticate and reach OCI Object Storage

Object Storage Namespace: axxxxxxxxxxx

Next steps:
  1. Update Migration Questionnaire Section C with:
     OCI_OSS_NAMESPACE  = axxxxxxxxxxx
     OCI_OSS_BUCKET_NAME = zdm-migration-oradb
  2. Create the Object Storage bucket if it does not exist: ...
  3. Run verify_fixes.sh to confirm all three blockers are resolved.

[2026-03-02 22:10:05 UTC] fix_oci_config.sh completed.
```

---

## Post-Run Action Required

After running this script, **record the Object Storage namespace** in the Migration Questionnaire ([Migration-Questionnaire-ORADB.md](../../Migration-Questionnaire-ORADB.md)):

- Section C → **Object Storage Namespace** field

Then create the Object Storage bucket if it does not already exist:

```bash
# As zdmuser on ZDM server, using the namespace from the script output:
oci os bucket create \
  --compartment-id <OCI_COMPARTMENT_OCID> \
  --name zdm-migration-oradb \
  --namespace-name <OCI_OSS_NAMESPACE>
```

---

## Rollback / Undo

```bash
# To remove the created OCI config and restore the backup (if applicable):
rm -f ~/.oci/config

# Restore from backup if one was created:
# ls ~/.oci/config.bak.*
# cp ~/.oci/config.bak.<timestamp> ~/.oci/config
```

---

*Issue 3 of 3 critical blockers — ORADB Step 2 remediation*
