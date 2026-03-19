# Phase 10 Migration — Step 2: Discovery Scripts

## Overview

Step 2 generates read-only discovery tooling for the source database server, target database server,
and ZDM server. All scripts are read-only and make no changes to database or OS configuration.

This step is **generation-only** in VS Code. Scripts are executed later on the jumpbox/ZDM server
by the user. Runtime outputs are written to the ZDM server working directories under `zdmuser`'s home.

---

## Generated Files

| File | Purpose |
|------|---------|
| `Scripts/zdm_source_discovery.sh` | Collects source DB server diagnostics via SSH |
| `Scripts/zdm_target_discovery.sh` | Collects target DB server diagnostics via SSH |
| `Scripts/zdm_server_discovery.sh` | Collects local ZDM server diagnostics |
| `Scripts/zdm_orchestrate_discovery.sh` | Orchestrates all three discovery scripts end-to-end |
| `Scripts/README.md` | Script usage and runtime instructions |
| `Discovery/source/` | Placeholder directory — receives runtime source discovery outputs |
| `Discovery/target/` | Placeholder directory — receives runtime target discovery outputs |
| `Discovery/server/` | Placeholder directory — receives runtime server discovery outputs |

---

## Environment Configuration Used

Values resolved from `zdm-env.md` at generation time:

| Variable | Value |
|----------|-------|
| `SOURCE_HOST` | `10.200.1.12` |
| `TARGET_HOST` | `10.200.0.250` |
| `SOURCE_ADMIN_USER` | `azureuser` (mapped from `SOURCE_SSH_USER`) |
| `TARGET_ADMIN_USER` | `opc` (mapped from `TARGET_SSH_USER`) |
| `SOURCE_SSH_KEY` | Not set (placeholder value treated as unset) |
| `TARGET_SSH_KEY` | Not set (placeholder value treated as unset) |
| `ORACLE_USER` | `oracle` |
| `ZDM_USER` | `zdmuser` |
| `SOURCE_REMOTE_ORACLE_HOME` | `/u01/app/oracle/product/19.0.0/dbhome_1` |
| `SOURCE_ORACLE_SID` | `POCAKV` |
| `TARGET_REMOTE_ORACLE_HOME` | `/u02/app/oracle/product/19.0.0.0/dbhome_1` |
| `TARGET_ORACLE_SID` | `POCAKV1` |
| `SOURCE_DATABASE_UNIQUE_NAME` | `POCAKV` |
| `TARGET_DATABASE_UNIQUE_NAME` | `POCAKV_ODAA` |
| `ZDM_HOME` | `/mnt/app/zdmhome` |

> **SSH key note:** Both `SOURCE_SSH_KEY` and `TARGET_SSH_KEY` contain placeholder values
> (`<source_key>.pem` / `<target_key>.pem`). These are treated as unset. Scripts will use
> SSH agent or default key authentication (no `-i` flag). Supply real key paths in `zdm-env.md`
> and regenerate if you require explicit key paths.

---

## What to Run on the Jumpbox / ZDM Server

1. Copy the contents of `Scripts/` to the ZDM server (as `zdmuser`):

   ```bash
   scp Scripts/zdm_*_discovery.sh zdmuser@<zdm-server>:~/zdm-step2-scripts/
   scp Scripts/zdm_orchestrate_discovery.sh zdmuser@<zdm-server>:~/zdm-step2-scripts/
   chmod +x ~/zdm-step2-scripts/*.sh
   ```

2. Log in to the ZDM server as `zdmuser` and run the orchestrator:

   ```bash
   sudo su - zdmuser
   cd ~/zdm-step2-scripts
   ./zdm_orchestrate_discovery.sh
   ```

   For verbose output:
   ```bash
   ./zdm_orchestrate_discovery.sh -v
   ```

3. Review the runtime outputs written under `$HOME/zdm-step2-*-<timestamp>/` on the ZDM server.

4. Copy runtime outputs back to `Artifacts/Phase10-Migration/Step2/Discovery/{source,target,server}/`
   for review in VS Code before proceeding to Step 3.

---

## Runtime Output Locations

| Output | Path on ZDM server |
|--------|-------------------|
| Source discovery text | `$HOME/zdm-step2-source-<ts>/zdm_source_discovery_<hostname>_<ts>.txt` |
| Source discovery JSON | `$HOME/zdm-step2-source-<ts>/zdm_source_discovery_<hostname>_<ts>.json` |
| Target discovery text | `$HOME/zdm-step2-target-<ts>/zdm_target_discovery_<hostname>_<ts>.txt` |
| Target discovery JSON | `$HOME/zdm-step2-target-<ts>/zdm_target_discovery_<hostname>_<ts>.json` |
| Server discovery text | `$HOME/zdm-step2-server-<ts>/zdm_server_discovery_<hostname>_<ts>.txt` |
| Server discovery JSON | `$HOME/zdm-step2-server-<ts>/zdm_server_discovery_<hostname>_<ts>.json` |
| Orchestrator log | `$HOME/zdm-step2-orch-<ts>/zdm_orchestrate_run_<ts>.log` |
| Orchestrator report | `$HOME/zdm-step2-orch-<ts>/zdm_orchestrate_report_<ts>.md` |

---

## Success and Failure Signals

- **Overall PASS:** All three discovery scripts complete and produce both `.txt` and `.json` output files.
- **Partial:** One or more scripts fail; orchestrator produces `status: "partial"` in the JSON summary.
- **FAIL:** Orchestrator exits non-zero; check the orchestrator log for per-script failure context.

Check for these patterns in orchestrator output:

```
[PASS] source discovery completed
[PASS] target discovery completed
[PASS] server discovery completed
Overall Step2 Discovery Status: PASS
```

Any `[FAIL]` or `[WARN]` lines indicate issues that require review before proceeding to Step 3.

---

## Next Step

After runtime discovery outputs are collected and reviewed, continue with:

```
@Phase10-ZDM-Step3-Discovery-Questionnaire
```
