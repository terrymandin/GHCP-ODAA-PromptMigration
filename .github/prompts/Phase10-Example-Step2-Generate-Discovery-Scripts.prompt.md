---
agent: agent
description: Phase 10 ZDM Step 2 example - generate discovery scripts for a sample environment
---
# Example: Generate Discovery Scripts (Step 2)

## Example Prompt

```text
@Phase10-ZDM-Step2-Generate-Discovery-Scripts

Project Configuration:
#file:zdm-env.md

Generate Step 2 discovery scripts.
```

## Expected Output

```
Artifacts/Phase10-Migration/Step2/
├── README.md
├── Scripts/
│   ├── zdm_source_discovery.sh
│   ├── zdm_target_discovery.sh
│   ├── zdm_server_discovery.sh
│   ├── zdm_orchestrate_discovery.sh
│   └── README.md
└── Discovery/
    ├── source/
    ├── target/
    └── server/
```

## Requirements Summary

- Generation-only step: create files and placeholder directories only; do not run SSH/SQL/discovery in VS Code.
- If `zdm-env.md` is attached, treat it as authoritative input, prefer it over defaults, and report conflicts with evidence instead of silently overriding.
- Generated scripts are runtime-independent from `zdm-env.md`; runtime outputs are created later on jumpbox/ZDM server.
- Output contract: four scripts plus `Artifacts/Phase10-Migration/Step2/README.md` and `Artifacts/Phase10-Migration/Step2/Scripts/README.md`, and placeholder directories under `Artifacts/Phase10-Migration/Step2/Discovery/{source,target,server}`.
- Scripts are strictly read-only (`SELECT`-only SQL, no mutation commands) and include a read-only banner comment.
- Auth model: source/target SSH as admin user then SQL as `oracle` via `sudo -u oracle`; ZDM server script runs locally as `zdmuser` with a user guard.
- SSH key normalization is required: empty/placeholder key values are treated as unset, and `-i` is included only when the normalized key path is non-empty.
- Step prompt preserves required implementation examples/patterns for user guards, key normalization, login-shell remote execution, SQL via stdin (SP2-0310 prevention), and runtime status/warnings output schema.
- OCI CLI is not required for migration execution.

## Next Steps

After running discovery scripts and collecting outputs, continue with @Phase10-ZDM-Step3-Discovery-Questionnaire.
