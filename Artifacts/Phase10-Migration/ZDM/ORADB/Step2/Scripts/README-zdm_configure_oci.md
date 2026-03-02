# README: zdm_configure_oci.sh

## Purpose
Creates and validates the OCI CLI configuration (`~/.oci/config`) for `zdmuser` on the ZDM server, verifies end-to-end OCI API connectivity, and provides guided steps to create the Object Storage bucket required for ZDM migration staging — resolving Issues 3 and 4 from `Issue-Resolution-Log-ORADB.md`.

---

## Target Server
**ZDM Server** — `tm-vm-odaa-oracle-jumpbox` (`10.1.0.8`)
All commands run **as `zdmuser`** on the ZDM server.

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| Run as user | `zdmuser` on the ZDM server |
| OCI private key in place | `/home/zdmuser/.oci/oci_api_key.pem` must exist **before** running the script (see below) |
| OCI CLI installed | Confirmed as `3.73.1` in Step 0 discovery; script validates this |
| HTTPS outbound from ZDM server | Port 443 to `objectstorage.uk-london-1.oraclecloud.com` must not be blocked |
| API key registered in OCI Console | Fingerprint `7f:05:c1:f2:5c:3a:46:ec:9f:95:44:c8:77:a4:50:f9` must match the key uploaded in OCI → Identity → Users → API Keys |

### Copying the Private Key to the ZDM Server

If the OCI API private key is not yet on the ZDM server, copy it first:

```bash
# From your LOCAL machine:
scp -i ~/.ssh/zdm.pem \
    /local/path/oci_api_key.pem \
    azureuser@10.1.0.8:/tmp/oci_api_key.pem

# Then on the ZDM server (as azureuser or an admin user):
sudo mkdir -p /home/zdmuser/.oci
sudo cp /tmp/oci_api_key.pem /home/zdmuser/.oci/oci_api_key.pem
sudo chown zdmuser:zdmuser /home/zdmuser/.oci/oci_api_key.pem
sudo chmod 600 /home/zdmuser/.oci/oci_api_key.pem
rm /tmp/oci_api_key.pem    # clean up temp copy
```

---

## Environment Variables

All values are hardcoded in the script from `zdm-env.md`. No exports are required before running.

| Variable | Value | Description |
|----------|-------|-------------|
| `OCI_CONFIG_PATH` | `~/.oci/config` | OCI CLI config file path (relative to `zdmuser`) |
| `OCI_PRIVATE_KEY_PATH` | `~/.oci/oci_api_key.pem` | OCI API private key path |
| `OCI_TENANCY_OCID` | `ocid1.tenancy.oc1..aaaaaa...` | OCI tenancy OCID from `zdm-env.md` |
| `OCI_USER_OCID` | `ocid1.user.oc1..aaaaaa...` | OCI user OCID from `zdm-env.md` |
| `OCI_API_KEY_FINGERPRINT` | `7f:05:c1:f2:5c:3a:46:ec:9f:95:44:c8:77:a4:50:f9` | API key fingerprint from `zdm-env.md` |
| `OCI_REGION` | `uk-london-1` | OCI region (derived from `TARGET_DATABASE_OCID`) |
| `OCI_COMPARTMENT_OCID` | `ocid1.compartment.oc1..aaaaaa...` | Compartment OCID for bucket creation |
| `OCI_OSS_NAMESPACE` | *(unset — set before running bucket creation)* | Object Storage namespace |
| `OCI_OSS_BUCKET_NAME` | *(unset — set before running bucket creation)* | Recommended: `zdm-migration-oradb` |

---

## What It Does

1. **User guard** — exits immediately if not running as `zdmuser`
2. **Creates `~/.oci/` directory** with permissions `700`
3. **Writes `~/.oci/config`** with tenancy, user OCID, fingerprint, region, and key path; backs up any existing config with a timestamp suffix
4. **Checks private key** — exits with actionable instructions if `~/.oci/oci_api_key.pem` is missing
5. **Validates OCI CLI is in PATH** — checks `oci --version`
6. **Tests connectivity** — runs `oci os ns get` to retrieve the Object Storage namespace; prints the namespace value (required for `zdm-env.md` update and bucket creation)
7. **Confirms IAM auth** — runs `oci iam region list` to verify authentication end-to-end
8. **Guides bucket creation** — prints all three options (script, CLI, OCI Console) for creating the `zdm-migration-oradb` staging bucket; includes an opt-in commented block in the script that can be uncommented to automate this

---

## How to Run

```bash
# 1. Switch to zdmuser on the ZDM server
sudo su - zdmuser

# 2. Ensure private key is in place (see Prerequisites above)
ls -la ~/.oci/oci_api_key.pem   # should exist before continuing

# 3. Make executable (first run only)
chmod +x ~/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts/zdm_configure_oci.sh

# 4. Run
~/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts/zdm_configure_oci.sh
```

Total runtime: approximately 20–45 seconds (depending on OCI API latency).

---

## Expected Output

A successful run produces output like the following (abbreviated):

```
[2026-03-02 22:05:01] STEP 1: Creating OCI config directory /home/zdmuser/.oci...
  ✅ Directory /home/zdmuser/.oci ready (mode 700)
[2026-03-02 22:05:01] STEP 2: Writing OCI config to /home/zdmuser/.oci/config...
  ✅ OCI config written and secured (mode 600)
[2026-03-02 22:05:01] STEP 3: Checking OCI private key...
  ✅ OCI private key found. Permissions set to 600.
[2026-03-02 22:05:02] STEP 4: Verifying OCI CLI installation...
  ✅ OCI CLI found: 3.73.1
[2026-03-02 22:05:04] STEP 5: Testing OCI CLI connectivity...
  ✅ OCI CLI connectivity OK
  Object Storage namespace: abcde1fghij2k

  *** ACTION REQUIRED: Update zdm-env.md ***
  Set OCI_OSS_NAMESPACE = abcde1fghij2k

[2026-03-02 22:05:07] STEP 6: Confirming OCI region list (auth end-to-end check)...
+-------------------+
| REGION-NAME       |
+-------------------+
| uk-london-1       |
...
  ✅ OCI IAM API reachable. Region uk-london-1 should appear above.
```

**Key indicators of success:**
- Step 5: `OCI CLI connectivity OK` — namespace printed
- Step 6: `uk-london-1` appears in the region list

---

## After Running

1. **Note the namespace** printed in Step 5.
2. **Create the bucket** using one of the three options shown in Step 7 output.
3. **Update `zdm-env.md`:**
   ```
   OCI_OSS_NAMESPACE:   <namespace from Step 5>
   OCI_OSS_BUCKET_NAME: zdm-migration-oradb
   ```
4. **Verify the bucket:**
   ```bash
   oci os bucket get \
     --namespace-name "<namespace>" \
     --bucket-name "zdm-migration-oradb"
   ```
5. **Update `Issue-Resolution-Log-ORADB.md`:**
   - Issue 3 (OCI config) → ✅ Resolved
   - Issue 4 (OSS namespace/bucket) → ✅ Resolved (once namespace and bucket are confirmed)

---

## Rollback / Undo

| Action | Command |
|--------|---------|
| Remove OCI config | `rm ~/.oci/config` (backup was saved as `~/.oci/config.bak.<timestamp>`) |
| Restore previous config | `cp ~/.oci/config.bak.<timestamp> ~/.oci/config` |
| Delete the staging bucket | `oci os bucket delete --namespace-name "<ns>" --bucket-name "zdm-migration-oradb" --force` |

> **Note:** Do not delete the bucket during an active ZDM migration — this would cause the job to fail during backup/restore phases.

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `ServiceError: 401 - NotAuthenticated` | Key fingerprint mismatch or wrong user OCID | Verify API key in OCI Console → Identity → Users → API Keys |
| `ServiceError: 404 - NotFound` | User OCID or tenancy OCID incorrect | Re-check values in `zdm-env.md` against OCI Console |
| `Cannot connect / connection refused` | HTTPS outbound blocked from ZDM server | Check Azure NSG outbound rules — allow port 443 to OCI endpoints |
| `oci: command not found` | OCI CLI not in PATH for zdmuser | Add `~/.local/bin` to PATH in `~/.bashrc` for zdmuser and re-source |
| `key_file does not exist` | Private key not at `OCI_PRIVATE_KEY_PATH` | Copy key (see Prerequisites above) |

---

## Resolves

| Issue | Resolution Log Reference |
|-------|--------------------------|
| Issue 3: OCI config missing for `zdmuser` | `Issue-Resolution-Log-ORADB.md` — Issue 3 |
| Issue 4: OCI OSS namespace and bucket not configured | `Issue-Resolution-Log-ORADB.md` — Issue 4 |
