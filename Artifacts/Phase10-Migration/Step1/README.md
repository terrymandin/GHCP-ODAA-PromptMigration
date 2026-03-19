# Phase10 Migration - Step1 SSH Connectivity Validation

## Purpose
Step1 validates SSH connectivity from the jumpbox/ZDM server to both source and target database hosts before running discovery scripts.

## Generated Files
- `Scripts/zdm_test_ssh_connectivity.sh`

The following runtime files are generated when the script is executed later on the jumpbox/ZDM server:
- `Validation/ssh-connectivity-report-<timestamp>.md`
- `Validation/ssh-connectivity-report-<timestamp>.json`
- `Validation/ssh-connectivity-run-<timestamp>.log`

## Required Runtime User
Run the script as `zdmuser` on the jumpbox/ZDM server.

## How To Run Later On Jumpbox/ZDM Server
From the repository root:

```bash
bash Artifacts/Phase10-Migration/Step1/Scripts/zdm_test_ssh_connectivity.sh
```

Or from inside Step1:

```bash
cd Artifacts/Phase10-Migration/Step1
bash Scripts/zdm_test_ssh_connectivity.sh
```

## Runtime Output Locations
- Markdown report: `Artifacts/Phase10-Migration/Step1/Validation/ssh-connectivity-report-<timestamp>.md`
- JSON report: `Artifacts/Phase10-Migration/Step1/Validation/ssh-connectivity-report-<timestamp>.json`
- Execution log: `Artifacts/Phase10-Migration/Step1/Validation/ssh-connectivity-run-<timestamp>.log`

## Success / Failure Signals
- Success: exit code `0`, console shows `Final Summary: PASS`, both source/target hostname probes are `PASS`, and report verification passes.
- Failure: non-zero exit code, console shows one or more `[FAIL]` checks and `Final Summary: FAIL`.

## View Latest Reports
Display latest markdown report:

```bash
ls -1t Artifacts/Phase10-Migration/Step1/Validation/ssh-connectivity-report-*.md | head -n1 | xargs cat
```

Display latest JSON report:

```bash
ls -1t Artifacts/Phase10-Migration/Step1/Validation/ssh-connectivity-report-*.json | head -n1 | xargs cat
```
