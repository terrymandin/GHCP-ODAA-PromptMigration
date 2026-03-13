# SSH Connectivity Report — Phase 10 Step 1

| Field | Value |
|-------|-------|
| **Generated** | Fri Mar 13 04:32:33 PM EDT 2026 |
| **Run by** | zdmuser@tm-vm-odaa-oracle-jumpbox |
| **Overall result** | **PASS** |

---

## Source Host

| Property | Value |
|----------|-------|
| Host | `10.1.0.11` |
| SSH User | `azureuser` |
| SSH Key | `/home/zdmuser/.ssh/odaa.pem` |
| Result | **✅ PASS** |
| Remote Hostname | `tm-oracle-iaas` |

## Target Host

| Property | Value |
|----------|-------|
| Host | `10.0.1.160` |
| SSH User | `opc` |
| SSH Key | `/home/zdmuser/.ssh/odaa.pem` |
| Result | **✅ PASS** |
| Remote Hostname | `tmodaauks-rqahk1` |

---

## Remediation Steps (if any check failed)

1. **Key not found** — Verify the key file exists at the path above under the `zdmuser` home on the ZDM server.
2. **Bad permissions** — Run: `chmod 600 ~/.ssh/odaa.pem`
3. **Connection refused / timeout** — Confirm the host's security group / firewall allows TCP/22 inbound from the ZDM server IP.
4. **Host key verification** — If `known_hosts` is causing issues, run:
   ```bash
   ssh-keyscan -H 10.1.0.11 >> ~/.ssh/known_hosts
   ssh-keyscan -H 10.0.1.160 >> ~/.ssh/known_hosts
   ```
5. **Permission denied** — Confirm the correct user (`azureuser` / `opc`) is appended to `~/.ssh/authorized_keys` on each host.

---

## Next Step

SSH connectivity is confirmed for both hosts. Proceed to:

> `@Phase10-ZDM-Step2-Generate-Discovery-Scripts`
