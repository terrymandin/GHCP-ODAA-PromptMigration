# README: verify_oci_cli_zdmuser.sh

## Purpose
Verifies that the OCI CLI is installed, correctly configured, and functional under the `zdmuser` account on the ZDM server. Provides step-by-step remediation guidance for any check that fails.

## Target Server
**ZDM server** — `tm-vm-odaa-oracle-jumpbox` (10.1.0.8)  
**Run as:** `zdmuser`

## Prerequisites
- [ ] Running as `zdmuser` (use `sudo su - zdmuser` to switch)
- [ ] Network access from ZDM server to OCI Identity API endpoint: `https://identity.uk-london-1.oraclecloud.com`

## Environment Variables
| Variable | Description | Value |
|----------|-------------|-------|
| `DATABASE_NAME` | Database identifier for log path | `ORADB` |
| `OCI_CONFIG_PATH` | Expected OCI CLI config location | `~/.oci/config` |
| `OCI_PRIVATE_KEY_PATH` | Expected OCI API private key location | `~/.oci/oci_api_key.pem` |
| `OCI_REGION` | Target OCI region | `uk-london-1` |
| `KNOWN_USER_OCID` | OCI User OCID (from zdm-env.md) | `ocid1.user.oc1..aaaaaaaakfe5cird...` |
| `KNOWN_TENANCY_OCID` | OCI Tenancy OCID (from zdm-env.md) | `ocid1.tenancy.oc1..aaaaaaaarvyhjcn7...` |
| `KNOWN_FINGERPRINT` | API key fingerprint (from zdm-env.md) | `7f:05:c1:f2:5c:3a:46:ec:9f:95:44:c8:77:a4:50:f9` |

## What It Does
1. **Check 1:** Verifies `oci` binary exists in `zdmuser`'s PATH
2. **Check 2:** Verifies `~/.oci/config` exists — prints setup commands if missing
3. **Check 3:** Verifies `~/.oci/oci_api_key.pem` exists with `600` permissions
4. **Check 4:** Verifies the `key_file` path in `~/.oci/config` resolves to an actual file
5. **Check 5:** Verifies `~/.oci` directory has `700` permissions
6. **Check 6:** Runs `oci iam region list` to confirm OCI API connectivity and authentication

## How to Run
```bash
# Switch to zdmuser on ZDM server
sudo su - zdmuser

cd ~/Artifacts/Phase10-Migration/ZDM/ORADB/Step2/Scripts
chmod +x verify_oci_cli_zdmuser.sh
./verify_oci_cli_zdmuser.sh
```

## Expected Output (all passing)
```
==============================================================
  ZDM Step 2: Verify OCI CLI Config for zdmuser
  ...
  ✅ PASS: OCI CLI found: 3.73.1
  ✅ PASS: OCI config file exists at /home/zdmuser/.oci/config
  ✅ PASS: Private key exists with correct permissions (600)
  ✅ PASS: Config key_file '/home/zdmuser/.oci/oci_api_key.pem' resolves to an existing file
  ✅ PASS: ~/.oci directory permissions correct (700)
  ✅ PASS: OCI CLI authenticated and can reach OCI API (region 'uk-london-1' confirmed)
==============================================================
  ✅ All OCI CLI checks PASSED — Issue 2 is resolved
  OCI CLI is correctly configured for zdmuser.
  You may now run create_oci_bucket.sh
```

## If Checks Fail: Setup Instructions

### Option A — Copy OCI config from `azureuser`
```bash
sudo su - zdmuser
sudo cp -r /home/azureuser/.oci /home/zdmuser/.oci
sudo chown -R zdmuser:zdmuser /home/zdmuser/.oci
chmod 700 /home/zdmuser/.oci
chmod 600 /home/zdmuser/.oci/config /home/zdmuser/.oci/oci_api_key.pem
```

### Option B — Interactive setup from scratch
```bash
sudo su - zdmuser
oci setup config
# Use these values when prompted:
#   Location for config:     ~/.oci/config
#   User OCID:               ocid1.user.oc1..aaaaaaaakfe5cirdq7vkkrhogjrgcrgftvwb7mdoehujgchefpqv54vhsnoa
#   Tenancy OCID:            ocid1.tenancy.oc1..aaaaaaaarvyhjcn7wkkxxx5g3o7lgqks23bmsjtsticz3gtg5xs5qyrwkftq
#   Region:                  uk-london-1
#   Use existing key pair:   YES (or generate new and upload public key to OCI Console)
#   Private key path:        /home/zdmuser/.oci/oci_api_key.pem
#   Fingerprint:             7f:05:c1:f2:5c:3a:46:ec:9f:95:44:c8:77:a4:50:f9
```

## Rollback / Undo
This script only performs read-only checks and prints guidance — it makes no changes. No rollback is required.
