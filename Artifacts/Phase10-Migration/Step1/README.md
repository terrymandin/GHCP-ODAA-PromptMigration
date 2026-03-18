# Step 1 - SSH Connectivity Test

This step generates and runs a pre-discovery SSH connectivity validation between the jumpbox/ZDM server and both database endpoints.

## Generated Files

- `Artifacts/Phase10-Migration/Step1/Scripts/zdm_test_ssh_connectivity.sh`
- `Artifacts/Phase10-Migration/Step1/README.md`

## Run Later on the Jumpbox/ZDM Server

Run as `zdmuser` from a clone of this repository:

```bash
bash Artifacts/Phase10-Migration/Step1/Scripts/zdm_test_ssh_connectivity.sh
```

## Runtime Output Location

When executed, the script writes reports under:

- `Artifacts/Phase10-Migration/Step1/Validation/`

Files created at runtime:

- `ssh-connectivity-report-<timestamp>.md`
- `ssh-connectivity-report-<timestamp>.json`

## What Success and Failure Look Like

- Success: both source and target SSH `hostname` probes pass, all required key checks pass, script exits `0`.
- Failure: any key validation or SSH probe fails, script prints `[FAIL]` summary and exits non-zero.

## View the Latest Reports

From the repository root on the jumpbox/ZDM server:

```bash
latest_md=$(ls -1t Artifacts/Phase10-Migration/Step1/Validation/ssh-connectivity-report-*.md | head -n 1)
latest_json=$(ls -1t Artifacts/Phase10-Migration/Step1/Validation/ssh-connectivity-report-*.json | head -n 1)

echo "Latest markdown report: $latest_md"
cat "$latest_md"

echo "Latest JSON report: $latest_json"
cat "$latest_json"
```

## Next Step

After both endpoint checks pass, continue with Step 2:

- `@Phase10-ZDM-Step2-Generate-Discovery-Scripts`
