# Fix 02 - Capture ZDM Version/Build Evidence

## Purpose
Addresses Step 3 open item: ZDM version command used in discovery was invalid.

## Script
- `fix_02_capture_zdm_version.sh`

## What It Does
- Loads `ZDM_HOME` from `zdm-env.md`.
- Checks `zdmcli` exists at `${ZDM_HOME}/bin/zdmcli`.
- Tries supported command sequence until one succeeds:
  - `zdmcli -build`
  - `zdmcli -v`
  - `zdmcli -version`
  - `zdmcli help`
- Writes raw output and a summary report to `Artifacts/Phase10-Migration/Step4/Resolution/`.

## Usage
From repository root on the ZDM host:

```bash
bash Artifacts/Phase10-Migration/Step4/fix-02-capture-zdm-version/fix_02_capture_zdm_version.sh
```

## Expected Result
- PASS report if any command succeeds.
- FAIL report if all commands fail, including list of attempted commands.
