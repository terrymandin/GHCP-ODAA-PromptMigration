# Step 2 Discovery Scripts — README

## Generated Files

| Script | Purpose | Run As |
|--------|---------|--------|
| `zdm_source_discovery.sh` | Read-only diagnostics on source Oracle DB server (via SSH) | `zdmuser` (orchestrated) |
| `zdm_target_discovery.sh` | Read-only diagnostics on target Oracle DB server (via SSH) | `zdmuser` (orchestrated) |
| `zdm_server_discovery.sh` | Read-only diagnostics on local ZDM server | `zdmuser` (local) |
| `zdm_orchestrate_discovery.sh` | Orchestrates all three scripts; produces combined status report | `zdmuser` |

All scripts are **read-only** (`SELECT`-only SQL, no OS/DB mutation). Each script includes a
read-only banner comment confirming this constraint.

---

## Prerequisites

- Run on the ZDM server as `zdmuser`.
- SSH access to source (`10.200.1.12` as `azureuser`) and target (`10.200.0.250` as `opc`) must be
  working. Validate connectivity with Step 1 before running Step 2.
- Oracle environment (`ORACLE_HOME`, `ORACLE_SID`) is auto-detected; explicit values override detection.

---

## Usage

### Run the Orchestrator (Recommended)

```bash
sudo su - zdmuser
cd ~/zdm-step2-scripts
./zdm_orchestrate_discovery.sh           # standard run
./zdm_orchestrate_discovery.sh -v        # verbose output
./zdm_orchestrate_discovery.sh -c        # show effective config and exit
./zdm_orchestrate_discovery.sh -h        # show help and exit
```

The orchestrator:
1. Prints startup diagnostics (user, home, SSH key inventory).
2. Copies and executes `zdm_source_discovery.sh` on the source server.
3. Copies and executes `zdm_target_discovery.sh` on the target server.
4. Executes `zdm_server_discovery.sh` locally.
5. Retrieves remote output files via SCP.
6. Produces a Markdown summary report and overall status.

### Run Individual Scripts (Advanced)

```bash
# Source discovery (run from ZDM server, SSH to source)
./zdm_source_discovery.sh

# Target discovery (run from ZDM server, SSH to target)
./zdm_target_discovery.sh

# ZDM server discovery (run locally as zdmuser)
./zdm_server_discovery.sh
```

---

## Runtime Output Naming

Scripts produce two output files per run:

```
zdm_<type>_discovery_<hostname>_<YYYYMMDD-HHMMSS>.txt    # human-readable text report
zdm_<type>_discovery_<hostname>_<YYYYMMDD-HHMMSS>.json   # structured JSON summary
```

Where `<type>` is one of: `source`, `target`, `server`.

The orchestrator writes its run log and combined report under:

```
$HOME/zdm-step2-orch-<YYYYMMDD-HHMMSS>/
├── zdm_orchestrate_run_<ts>.log
└── zdm_orchestrate_report_<ts>.md
```

---

## Retrieving Outputs for Review

After runtime, copy output files back to VS Code workspace:

```bash
# From your local machine or jumpbox:
scp "zdmuser@<zdm-server>:$HOME/zdm-step2-source-*/zdm_source_*" \
    Artifacts/Phase10-Migration/Step2/Discovery/source/

scp "zdmuser@<zdm-server>:$HOME/zdm-step2-target-*/zdm_target_*" \
    Artifacts/Phase10-Migration/Step2/Discovery/target/

scp "zdmuser@<zdm-server>:$HOME/zdm-step2-server-*/zdm_server_*" \
    Artifacts/Phase10-Migration/Step2/Discovery/server/
```

---

## Success and Failure Signals

| Signal | Meaning |
|--------|---------|
| `[PASS] source discovery completed` | Source script succeeded |
| `[PASS] target discovery completed` | Target script succeeded |
| `[PASS] server discovery completed` | Server script succeeded |
| `Overall Step2 Discovery Status: PASS` | All three scripts passed |
| `Overall Step2 Discovery Status: PARTIAL` | One or more scripts failed |
| `[FAIL]` in log | Review per-script failure context in orchestrator log |
| `status: "partial"` in JSON | At least one section had warnings or errors |

---

## Next Step

After collecting and reviewing runtime outputs, continue with:

```
@Phase10-ZDM-Step3-Discovery-Questionnaire
```
