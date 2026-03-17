# Fix 01 - Capture Source/Target DB Version Evidence

## Purpose
Addresses Step 3 open item: SQL*Plus/database version evidence was not captured in discovery output.

## Script
- `fix_01_capture_db_version.sh`

## What It Does
- Loads host, user, key, Oracle home, and SID values from `zdm-env.md`.
- Connects to source and target hosts via SSH.
- Runs `sqlplus -v` with explicit Oracle environment pinning.
- Captures PMON process evidence.
- Writes raw outputs and a summary report to `Artifacts/Phase10-Migration/Step4/Resolution/`.

## Usage
From repository root on the ZDM/jump host:

```bash
bash Artifacts/Phase10-Migration/Step4/fix-01-capture-db-version/fix_01_capture_db_version.sh
```

## Expected Result
- Report file: `fix-01-db-version-report-<timestamp>.md`
- Raw source file: `source-db-version-<timestamp>.txt`
- Raw target file: `target-db-version-<timestamp>.txt`
