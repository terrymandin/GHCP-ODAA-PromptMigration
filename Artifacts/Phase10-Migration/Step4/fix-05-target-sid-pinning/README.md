# Fix 05 - Validate Target SID Pinning

## Purpose
Addresses Step 3 open item: ensure all runbooks pin target instance to `TARGET_ORACLE_SID=POCAKV1` and avoid auto-detection drift.

## Script
- `fix_05_validate_target_sid_pinning.sh`

## What It Does
- Loads target host, SSH user/key, Oracle SID, Oracle home, and DB unique name from `zdm-env.md`.
- Fails if `TARGET_ORACLE_SID` is empty or placeholder.
- Connects to target host and captures PMON process list.
- Verifies configured `TARGET_ORACLE_SID` appears in PMON evidence.
- Writes summary and raw capture under `Artifacts/Phase10-Migration/Step4/Resolution/`.

## Usage
From repository root on the ZDM/jump host:

```bash
bash Artifacts/Phase10-Migration/Step4/fix-05-target-sid-pinning/fix_05_validate_target_sid_pinning.sh
```

## Expected Result
- PASS when configured SID is non-placeholder and present in PMON output.
