# Fix 04 - Validate ZDM Root Disk Headroom

## Purpose
Addresses Step 3 open item: root filesystem free space needed confirmation before migration runtime.

## Script
- `fix_04_check_zdm_disk_headroom.sh`

## What It Does
- Checks free space on `/` using `df -Pk /`.
- Uses threshold:
  - default: `2097152 KB` (2 GiB)
  - override with environment variable: `STEP4_MIN_ROOT_FREE_KB`
- Writes report to `Artifacts/Phase10-Migration/Step4/Resolution/`.

## Usage
From repository root on the ZDM host:

```bash
bash Artifacts/Phase10-Migration/Step4/fix-04-zdm-disk-headroom/fix_04_check_zdm_disk_headroom.sh
```

Optional stricter threshold:

```bash
STEP4_MIN_ROOT_FREE_KB=4194304 bash Artifacts/Phase10-Migration/Step4/fix-04-zdm-disk-headroom/fix_04_check_zdm_disk_headroom.sh
```

## Expected Result
- PASS when observed free space is greater than or equal to threshold.
