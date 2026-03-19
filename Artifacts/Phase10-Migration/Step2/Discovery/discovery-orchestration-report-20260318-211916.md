# ZDM Step2 Discovery Orchestration Report

Timestamp: 2026-03-18T21:19:20Z
Runtime User: zdmuser
Runtime Host: zdmhost

## Effective Runtime Configuration
SOURCE_HOST=10.200.1.12
TARGET_HOST=10.200.0.250
SOURCE_ADMIN_USER=azureuser
TARGET_ADMIN_USER=opc
ORACLE_USER=oracle
ZDM_USER=zdmuser
SOURCE_SSH_KEY=<unset>
TARGET_SSH_KEY=<unset>

## Script Execution Status
source: FAIL
source_log: /home/zdmuser/GHCP-ODAA-PromptMigration/Artifacts/Phase10-Migration/Step2/Discovery/logs/source-discovery-20260318-211916.log
target: FAIL
target_log: /home/zdmuser/GHCP-ODAA-PromptMigration/Artifacts/Phase10-Migration/Step2/Discovery/logs/target-discovery-20260318-211916.log
server: PASS
server_log: /home/zdmuser/GHCP-ODAA-PromptMigration/Artifacts/Phase10-Migration/Step2/Discovery/logs/server-discovery-20260318-211916.log

## Output References
source_txt: <missing>
source_json: <missing>
target_txt: <missing>
target_json: <missing>
server_txt: /home/zdmuser/GHCP-ODAA-PromptMigration/Artifacts/Phase10-Migration/Step2/Discovery/server/zdm_server_discovery_zdmhost_20260318-211916.txt
server_json: /home/zdmuser/GHCP-ODAA-PromptMigration/Artifacts/Phase10-Migration/Step2/Discovery/server/zdm_server_discovery_zdmhost_20260318-211916.json

## Overall
overall_status: FAIL
warnings_count: 2

### Warnings
- source discovery failed during remote execution
- target discovery failed during remote execution
