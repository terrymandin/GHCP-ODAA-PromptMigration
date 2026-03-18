# SSH Connectivity Validation Report

- Timestamp (UTC): 20260318T193244Z
- Runtime Host: zdmhost
- Runtime User: zdmuser
- Script Path: /home/zdmuser/GHCP-ODAA-PromptMigration/Artifacts/Phase10-Migration/Step1/Scripts

## Effective SSH Model

### Source Endpoint
- User: azureuser
- Host: 10.200.1.12
- Mode: default_or_agent
- Key Path: N/A
- Key Check: not_applicable
- Key Detail: key not provided; using default/agent mode

### Target Endpoint
- User: opc
- Host: 10.200.0.250
- Mode: default_or_agent
- Key Path: N/A
- Key Check: not_applicable
- Key Detail: key not provided; using default/agent mode

## Connectivity Probes

- Source Probe Status: pass
- Source Probe Output: factvmhost
- Target Probe Status: pass
- Target Probe Output: vmclusterpoc-ytlat1

## Manual Single-Line SSH Tests

Default key/agent mode:
- ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o PasswordAuthentication=no azureuser@10.200.1.12 hostname
- ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o PasswordAuthentication=no opc@10.200.0.250 hostname

Explicit key mode:
- ssh -i ~/.ssh/<source_key>.pem -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o PasswordAuthentication=no azureuser@10.200.1.12 hostname
- ssh -i ~/.ssh/<target_key>.pem -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o PasswordAuthentication=no opc@10.200.0.250 hostname

## Final Summary

- Failures: 0
- Overall Status: PASS
