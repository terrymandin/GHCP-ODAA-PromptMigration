---
agent: agent
description: Phase 10 ZDM Step 2 example - generate discovery scripts for a sample environment
---
# Example: Generate Discovery Scripts (Step 2)

## Example Prompt

```text
@Phase10-ZDM-Step2-Generate-Discovery-Scripts

## Project Configuration
#file:zdm-env.md

Generate Step 2 discovery scripts.
```

`zdm-env.md` is generation input only. Generated scripts should be checked into GitHub, retrieved from the repo clone on the jumpbox/ZDM server, and run there without any runtime dependency on `zdm-env.md`.
When generating artifacts, treat `zdm-env.md` values as authoritative and prefer them over template defaults; map `SOURCE_SSH_USER`/`TARGET_SSH_USER` to generated admin-user variables when needed.

Step 2 prompt behavior is generation-only: create scripts and placeholder directories only. Do not execute discovery commands or generate discovery output files during prompt execution.
Any "run" wording in generated README/scripts refers to later manual execution on the jumpbox/ZDM server by the user.

> After generation, commit and push the Step2 scripts. On the jumpbox/ZDM server, pull the repo and run the scripts to collect discovery output.

## Expected Output

```
Artifacts/Phase10-Migration/Step2/
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

## Discovery Items Generated (when scripts are run on jumpbox/ZDM server)

### Source Discovery
- Connectivity and auth context: source host, SSH user, SSH key mode.
- Remote system details: hostname, OS, kernel, uptime.
- Oracle environment details:
    - `/etc/oratab` entries.
    - PMON SIDs detected.
    - Oracle home in use.
    - Oracle SID in use.
    - Database unique name (config value).
    - `sqlplus` version.

### Target Discovery
- Connectivity and auth context: target host, SSH user, SSH key mode.
- Remote system details: hostname, OS, kernel, uptime.
- Oracle environment details:
    - `/etc/oratab` entries.
    - PMON SIDs detected.
    - Oracle home in use.
    - Oracle SID in use.
    - Database unique name (config value).
    - `sqlplus` version.

### ZDM Server Discovery
- Local system details: hostname, OS, kernel, uptime, current user.
- ZDM installation details: `ZDM_HOME`, existence, permissions, `zdmcli` path, `zdmcli` version.
- Capacity snapshot: root disk usage, memory summary.
- Endpoint traceability: source and target endpoint values used during discovery.

### Orchestration Summary
- Effective runtime configuration used for source/target values.
- Per-script execution status (`PASS`/`FAIL`) and log file paths.
- Overall Step 2 discovery status.
- Output formats produced by each script run: raw text, markdown report, and JSON report.

## Next Step
After collecting discovery outputs and committing them, continue with: `@Phase10-ZDM-Step3-Discovery-Questionnaire`
