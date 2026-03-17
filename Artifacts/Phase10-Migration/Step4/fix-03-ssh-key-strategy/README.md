# Fix 03 - Resolve SSH Authentication Strategy

## Purpose
Addresses Step 3 open item: SSH key strategy was ambiguous (placeholders vs agent/default mode).

## Script
- `fix_03_validate_ssh_strategy.sh`

## What It Does
- Reads source/target SSH host, user, and key values from `zdm-env.md`.
- Detects effective mode:
  - `explicit-key` when concrete key path(s) are configured
  - `agent/default` when placeholders or empty key values are used
- Validates key files and permissions (`600`) in explicit mode.
- Checks agent identity availability in agent/default mode.
- Verifies SSH connectivity to source and target in batch mode.
- Writes report and probe output to `Artifacts/Phase10-Migration/Step4/Resolution/`.

## Usage
From repository root on the ZDM/jump host:

```bash
bash Artifacts/Phase10-Migration/Step4/fix-03-ssh-key-strategy/fix_03_validate_ssh_strategy.sh
```

## Expected Result
- PASS when mode is valid and both source/target SSH probes succeed.
