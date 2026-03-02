# README: fix_oci_config_zdmuser.sh

## Purpose
Creates `~/.oci/config` for the `zdmuser` account on the ZDM server (`tm-vm-odaa-oracle-jumpbox`) and validates OCI CLI connectivity using `oci os ns get`. A working OCI configuration is required for ZDM to interact with OCI Object Storage (backup staging) and to validate target database details during migration. This resolves **Issue 3** (blocker) from `Issue-Resolution-Log-ORADB.md`.

---

## Target Server
**ZDM server** — this script is run **directly on the ZDM server** as `zdmuser` (not via SSH from another host).

| Field | Value |
|-------|-------|
| Run directly on | ZDM server: `tm-vm-odaa-oracle-jumpbox` (10.1.0.8) |
| Run as user | `zdmuser` |
| OCI CLI location | `/usr/local/bin/oci` (v3.73.1 — already installed) |

---

## Prerequisites

| Requirement | Detail |
|-------------|--------|
| OCI API private key uploaded | The `.pem` file corresponding to fingerprint `7f:05:c1:f2:5c:3a:46:ec:9f:95:44:c8:77:a4:50:f9` must be at `/home/zdmuser/.oci/oci_api_key.pem` with permissions `600` before the OCI CLI test (Step 5) can pass |
| OCI CLI installed on ZDM server | Already confirmed: OCI CLI 3.73.1 ✅ |
| Network access to OCI | ZDM server must be able to reach `https://objectstorage.uk-london-1.oraclecloud.com` (HTTPS/443). Cross-cloud connectivity was confirmed working by ZDM EVAL jobs 16 & 17. |
| `zdmuser` home exists | `/home/zdmuser` — confirmed present |

### Uploading the OCI API Private Key (one-time step)

Before running this script, upload the OCI API private key from your workstation:

```bash
# From your local workstation:
scp -i ~/.ssh/zdm.pem /path/to/oci_api_key.pem \
    azureuser@10.1.0.8:/tmp/oci_api_key.pem

# On ZDM server as azureuser:
sudo mkdir -p /home/zdmuser/.oci
sudo mv /tmp/oci_api_key.pem /home/zdmuser/.oci/oci_api_key.pem
sudo chown zdmuser:zdmuser /home/zdmuser/.oci/oci_api_key.pem
sudo chmod 600 /home/zdmuser/.oci/oci_api_key.pem
```

> **Where to get the key:** The `oci_api_key.pem` private key was generated when you added the API key to the OCI user in the OCI Console (Identity → Users → API Keys). If you do not have it, generate a new API key pair in OCI Console and update `zdm-env.md` with the new fingerprint.

---

## Environment Variables

| Variable | Default Value | Description |
|----------|---------------|-------------|
| `OCI_USER_OCID` | `ocid1.user.oc1..aaaaaaaakfe5ci...` | OCI User OCID (from zdm-env.md) |
| `OCI_TENANCY_OCID` | `ocid1.tenancy.oc1..aaaaaaaaarvyhj...` | OCI Tenancy OCID (from zdm-env.md) |
| `OCI_REGION` | `uk-london-1` | OCI region of the target database |
| `OCI_FINGERPRINT` | `7f:05:c1:f2:5c:3a:46:ec:9f:95:44:c8:77:a4:50:f9` | Fingerprint for the OCI API key |
| `OCI_PRIVATE_KEY_PATH` | `~/.oci/oci_api_key.pem` | Path to the OCI API private key (expands relative to home of the running user) |

---

## What It Does

1. **Step 1** — Verifies the script is running as `zdmuser` (warns if not).
2. **Step 2** — Creates `~/.oci/` directory with permissions `700`.
3. **Step 3** — Checks whether the API private key exists at `~/.oci/oci_api_key.pem`; prints upload instructions if missing.
4. **Step 4** — Writes `~/.oci/config` in standard OCI CLI format (`[DEFAULT]` profile). Backs up any existing config file with a timestamp suffix.
5. **Step 5** — Runs `oci os ns get` to confirm the OCI CLI can authenticate and reach OCI Object Storage. Prints the Object Storage namespace on success.

---

## How to Run

```bash
# SSH to ZDM server as azureuser
ssh -i ~/.ssh/zdm.pem azureuser@10.1.0.8

# Switch to zdmuser
sudo su - zdmuser

# Copy the script to zdmuser home (if not already there)
# Then run:
chmod +x fix_oci_config_zdmuser.sh
./fix_oci_config_zdmuser.sh
```

---

## Expected Output

```
================================================================
 fix_oci_config_zdmuser.sh — Create ~/.oci/config for zdmuser
 Running as: zdmuser  on  tm-vm-odaa-oracle-jumpbox
================================================================

---- Step 1: Verify user identity ------------------------------
   User: zdmuser
   Home: /home/zdmuser

---- Step 2: Create ~/.oci directory ---------------------------
   ✅ Directory: /home/zdmuser/.oci

---- Step 3: Check API private key -----------------------------
   ✅ Private key found: /home/zdmuser/.oci/oci_api_key.pem

---- Step 4: Write ~/.oci/config --------------------------------
   ✅ Config written: /home/zdmuser/.oci/config

---- Step 5: Verify OCI CLI connectivity -----------------------
   Running: oci os ns get

   ✅ OCI CLI connectivity confirmed
   Object Storage Namespace: <your-namespace>

================================================================
 Done.
 OCI config created at: /home/zdmuser/.oci/config
 OCI Namespace:         <your-namespace>

 Next steps:
  1. Update zdm-env.md: OCI_OSS_NAMESPACE: <your-namespace>
  2. Decide on Object Storage bucket name (recommend: zdm-migration-oradb)
  3. Create the bucket if it does not exist: ...
================================================================
```

---

## Post-Fix Actions

1. **Record the OCI Object Storage namespace** in `zdm-env.md`:
   ```
   OCI_OSS_NAMESPACE: <value from oci os ns get>
   ```

2. **Create the Object Storage bucket** (if it does not already exist):
   ```bash
   oci os bucket create \
     --compartment-id ocid1.compartment.oc1..aaaaaaaas4upnqj72dfiivgwvn3uui5gkxo7ng6leeoifucbjiy326urbhmq \
     --name zdm-migration-oradb \
     --namespace <your-namespace>
   ```

3. **Verify bucket access:**
   ```bash
   oci os bucket get --name zdm-migration-oradb --namespace <your-namespace>
   ```

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| `ServiceError: 401 Unauthorized` | Wrong fingerprint or key mismatch | Re-generate API key in OCI Console; update fingerprint in script and zdm-env.md |
| `FileNotFoundError` for key file | Private key not uploaded | Follow the key upload instructions in Prerequisites |
| `ConnectionError` / timeout | Network connectivity to OCI | Test: `curl -I https://objectstorage.uk-london-1.oraclecloud.com` from ZDM server |
| `InvalidParameter` on user/tenancy OCID | OCID has a typo | Verify OCIDs in OCI Console |

---

## Rollback / Undo

```bash
# Remove the config (restores to pre-fix state)
rm -f /home/zdmuser/.oci/config
# The backup (if present) can be restored:
# cp /home/zdmuser/.oci/config.bak.<timestamp> /home/zdmuser/.oci/config
```

---

## Related Files

- `Issue-Resolution-Log-ORADB.md` — Update **Issue 3** status to ✅ Resolved after confirming output; record the OCI namespace
- `verify_fixes.sh` — Runs a quick re-check of all three blockers including OCI CLI check
- `zdm-env.md` — Update `OCI_OSS_NAMESPACE` and `OCI_OSS_BUCKET_NAME` after this fix
