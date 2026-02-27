# README: fix_10_verify_ssh_access.sh

## Purpose
Verifies all SSH paths required by ZDM from the ZDM server to the source and target database servers — including admin user SSH, sudo-to-oracle capability, Oracle binary access, ZDM service status, and OCI CLI functionality. Run this before initiating `zdmcli migrate database` to confirm the environment is ready.

## Target Server
**ZDM server** (`10.1.0.8`) — run locally as `zdmuser`. The script performs outbound SSH from the ZDM server to source and target.

## Prerequisites
- SSH keys for both source (`~/.ssh/odaa.pem`) and target (`~/.ssh/odaa.pem`) are present in `zdmuser`'s `~/.ssh/`
- `azureuser` has passwordless sudo on source (`azureuser ALL=(oracle) NOPASSWD: ALL` in sudoers)
- `opc` has passwordless sudo on target (standard ODAA pre-configuration)
- ZDM service is running (`zdmcli status`)
- OCI CLI is configured for `zdmuser` (`~/.oci/config` present)
- Network connectivity from ZDM server to source (TCP 22, 1521) and target (TCP 22, 1521)

## Environment Variables

| Variable | Description | Default / Example |
|---|---|---|
| `SOURCE_HOST` | Source DB host IP | `10.1.0.11` |
| `SOURCE_SSH_USER` | SSH admin user on source | `azureuser` |
| `SOURCE_SSH_KEY` | Path to source SSH private key | `~/.ssh/odaa.pem` |
| `TARGET_HOST` | Target node 1 IP | `10.0.1.160` |
| `TARGET_SSH_USER` | SSH admin user on target | `opc` |
| `TARGET_SSH_KEY` | Path to target SSH private key | `~/.ssh/odaa.pem` |
| `ORACLE_USER` | Oracle OS user | `oracle` |
| `ZDM_HOME` | ZDM installation home | `/u01/app/zdmhome` |
| `OCI_CONFIG_PATH` | OCI CLI config path | `~/.oci/config` |
| `SOURCE_ORACLE_HOME` | Source Oracle Home | `/u01/app/oracle/product/12.2.0/dbhome_1` |
| `SOURCE_ORACLE_SID` | Source Oracle SID | `oradb` |
| `TARGET_ORACLE_HOME` | Target Oracle Home | `/u02/app/oracle/product/19.0.0.0/dbhome_1` |

## What It Does
Runs 8 tests and reports PASS / FAIL for each:

| Test | Description |
|---|---|
| T01 | SSH to source as `azureuser` (hostname check) |
| T02 | SSH to source → `sudo -u oracle whoami` |
| T03 | SSH to source → oracle `sqlplus -S / as sysdba` query against `DUAL` |
| T04 | SSH to target as `opc` (hostname check) |
| T05 | SSH to target → `sudo -u oracle whoami` |
| T06 | SSH to target → oracle `sqlplus` binary exists and is executable |
| T07 | ZDM service is Running (`zdmcli status`) |
| T08 | OCI CLI functional (`oci os ns get` returns namespace) |

## How to Run
```bash
# On ZDM server (10.1.0.8) as zdmuser
su - zdmuser
chmod +x fix_10_verify_ssh_access.sh
./fix_10_verify_ssh_access.sh
```

## Expected Output
```
  ✅ [PASS] T01: Source SSH as azureuser — tm-oracle-iaas
  ✅ [PASS] T02: Source sudo to oracle — oracle
  ✅ [PASS] T03: Source sqlplus connection — 1
  ✅ [PASS] T04: Target SSH as opc — tmodaauks-rqahk1
  ✅ [PASS] T05: Target sudo to oracle — oracle
  ✅ [PASS] T06: Target Oracle binaries accessible — sqlplus found
  ✅ [PASS] T07: ZDM service status — Service RUNNING
  ✅ [PASS] T08: OCI CLI functional — Namespace reachable

Test results: 8/8 passed, 0 failed.
✅ All SSH access tests passed. ZDM environment is ready for migration.
```

## Common Failure Resolutions

| Failing Test | Likely Cause | Resolution |
|---|---|---|
| T01 / T04 | Wrong key path or key not authorized | Verify key in `~/.ssh/authorized_keys` on the respective host |
| T02 / T05 | sudo not configured for oracle | Add `azureuser ALL=(oracle) NOPASSWD: ALL` to `/etc/sudoers.d/oracle` on source; ODAA target normally pre-configured |
| T03 | ARCHIVELOG restart needed / DB not running | Confirm source DB is up; complete fix_01 |
| T06 | Wrong `TARGET_ORACLE_HOME` | Verify from `/etc/oratab` on target |
| T07 | ZDM service stopped | Run: `/u01/app/zdmhome/bin/zdmservice start` |
| T08 | OCI API key mismatch / network | Verify `~/.oci/config` fingerprint matches uploaded API key in OCI Console |

## Rollback / Undo
This script is read-only — it makes no changes. Re-run at any time.
