# ZDM Discovery Scripts — PRODDB Migration

**Project:** PRODDB Migration to Oracle Database@Azure  
**Step:** Step 0 — Discovery Scripts  
**Generated:** 2026-02-26

---

## Server Configuration

| Role | Hostname | SSH Admin User | SSH Key |
|------|----------|----------------|---------|
| Source Database | `proddb01.corp.example.com` | `oracle` | `~/.ssh/onprem_oracle_key` |
| Target (ODA@Azure) | `proddb-oda.eastus.azure.example.com` | `opc` | `~/.ssh/oci_opc_key` |
| ZDM Jumpbox | `zdm-jumpbox.corp.example.com` | `azureuser` | `~/.ssh/azure_key` |

| Application User | Value |
|-----------------|-------|
| Oracle software owner | `oracle` |
| ZDM software owner | `zdmuser` |

---

## Scripts

| Script | Purpose |
|--------|---------|
| `zdm_orchestrate_discovery.sh` | **Run this first.** Orchestrates all discovery across all servers. |
| `zdm_source_discovery.sh` | Source database discovery (run on `proddb01.corp.example.com`) |
| `zdm_target_discovery.sh` | Target discovery for Oracle Database@Azure (run on `proddb-oda.eastus.azure.example.com`) |
| `zdm_server_discovery.sh` | ZDM server discovery (run on `zdm-jumpbox.corp.example.com`) |

---

## Quick Start

### Option 1: Run Orchestration Script (Recommended)

```bash
cd Artifacts/Phase10-Migration/ZDM/PRODDB/Step0/Scripts

# Make scripts executable
chmod +x *.sh

# Verify SSH connectivity first
./zdm_orchestrate_discovery.sh --test

# Run all discoveries
./zdm_orchestrate_discovery.sh
```

Results are saved to `../Discovery/` (i.e., `Step0/Discovery/`).

### Option 2: Run Individual Scripts Manually

```bash
# Source database
scp -i ~/.ssh/onprem_oracle_key zdm_source_discovery.sh \
    oracle@proddb01.corp.example.com:/tmp/zdm_discovery/
ssh -i ~/.ssh/onprem_oracle_key oracle@proddb01.corp.example.com \
    "cd /tmp/zdm_discovery && chmod +x zdm_source_discovery.sh && ./zdm_source_discovery.sh"

# Target database  
scp -i ~/.ssh/oci_opc_key zdm_target_discovery.sh \
    opc@proddb-oda.eastus.azure.example.com:/tmp/zdm_discovery/
ssh -i ~/.ssh/oci_opc_key opc@proddb-oda.eastus.azure.example.com \
    "cd /tmp/zdm_discovery && chmod +x zdm_target_discovery.sh && ./zdm_target_discovery.sh"

# ZDM server (pass source/target hosts for connectivity tests)
scp -i ~/.ssh/azure_key zdm_server_discovery.sh \
    azureuser@zdm-jumpbox.corp.example.com:/tmp/zdm_discovery/
ssh -i ~/.ssh/azure_key azureuser@zdm-jumpbox.corp.example.com \
    "cd /tmp/zdm_discovery && chmod +x zdm_server_discovery.sh && \
     SOURCE_HOST=proddb01.corp.example.com \
     TARGET_HOST=proddb-oda.eastus.azure.example.com \
     ./zdm_server_discovery.sh"

# Collect results
mkdir -p ../Discovery/source ../Discovery/target ../Discovery/server
scp -i ~/.ssh/onprem_oracle_key \
    "oracle@proddb01.corp.example.com:/tmp/zdm_discovery/zdm_source_discovery_*" \
    ../Discovery/source/
scp -i ~/.ssh/oci_opc_key \
    "opc@proddb-oda.eastus.azure.example.com:/tmp/zdm_discovery/zdm_target_discovery_*" \
    ../Discovery/target/
scp -i ~/.ssh/azure_key \
    "azureuser@zdm-jumpbox.corp.example.com:/tmp/zdm_discovery/zdm_server_discovery_*" \
    ../Discovery/server/
```

---

## Source Discovery Covers

**Standard:**
- OS info, Oracle environment, Oracle version
- Database config: name, DBID, role, log mode, force logging, size, charset
- CDB/PDB status, TDE wallet, supplemental logging
- Redo logs, archive destinations
- Listener, tnsnames.ora, sqlnet.ora
- Password file, SSH directory
- Data Guard configuration
- Schema sizes, invalid objects

**Additional (PRODDB-specific):**
- Tablespace autoextend settings
- RMAN backup schedule & retention
- Database links (all owners)
- Materialized view refresh schedules & logs
- Scheduler jobs, programs, and run history

---

## Target Discovery Covers

**Standard:**
- OS info, Oracle environment, Oracle version
- Database config, CDB/PDB status, TDE
- Listener, SCAN listener (RAC), tnsnames.ora
- OCI CLI config & connectivity
- Azure IMDS metadata
- Grid Infrastructure (CRS/ASM) status
- SSH/sudo config

**Additional (PRODDB-specific):**
- Exadata/ASM disk group capacity & free space
- Pre-configured PDBs (names, status, tablespaces)
- Azure NSG / OCI Security List rules (via CLI)
- Host-level firewall rules

---

## ZDM Server Discovery Covers

**Standard:**
- OS info
- ZDM installation verification (multi-method auto-detection)
- ZDM service status, active jobs
- Java version & JAVA_HOME
- OCI CLI config & connectivity
- SSH keys & credentials
- Network config, routing, DNS
- ZDM logs

**Additional (PRODDB-specific):**
- Disk space check (minimum 50 GB required) with per-filesystem breakdown
- Network latency: ICMP ping + port tests (SSH/1521) to source and target
- Traceroute to source and target
- OCI/Azure endpoint reachability test

---

## Environment Override Variables

If auto-detection fails, set these before running the orchestration script:

```bash
# Oracle path overrides
export SOURCE_REMOTE_ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1
export SOURCE_REMOTE_ORACLE_SID=PRODDB
export TARGET_REMOTE_ORACLE_HOME=/u01/app/oracle/product/19.0.0.0/dbhome_1

# ZDM path overrides
export ZDM_REMOTE_ZDM_HOME=/home/zdmuser/zdmhome
export ZDM_REMOTE_JAVA_HOME=/usr/java/jdk1.8.0_291

./zdm_orchestrate_discovery.sh
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `ssh_port_22:: command not found` | Scripts have Windows CRLF endings. Run: `sed -i 's/\r$//' *.sh` |
| SSH connection refused | Verify SSH key path, check security groups/NSG allow port 22 |
| ORACLE_HOME not found | Set `SOURCE_REMOTE_ORACLE_HOME` / `TARGET_REMOTE_ORACLE_HOME` overrides |
| ZDM_HOME not found | Set `ZDM_REMOTE_ZDM_HOME` override |
| SQL errors (ORA-01034) | Database may not be running — check with `ps -ef | grep pmon` |
| Partial discovery | Scripts are resilient; partial results are still valuable for Step 1 |

### Convert CRLF → LF (if needed)

```bash
# Linux/Mac
sed -i 's/\r$//' *.sh

# PowerShell (before copying to Linux)
Get-ChildItem *.sh | ForEach-Object {
    (Get-Content $_.FullName -Raw) -replace "`r`n", "`n" | 
    Set-Content -NoNewline $_.FullName
}
```

---

## Password Variables (Set at Runtime — Never Commit)

> ⚠️ **NEVER** commit passwords to source control.

Set these on the ZDM server before Step 2 migration:

```bash
read -sp "SOURCE_SYS_PASSWORD: " SOURCE_SYS_PASSWORD; echo; export SOURCE_SYS_PASSWORD
read -sp "SOURCE_TDE_WALLET_PASSWORD: " SOURCE_TDE_WALLET_PASSWORD; echo; export SOURCE_TDE_WALLET_PASSWORD
read -sp "TARGET_SYS_PASSWORD: " TARGET_SYS_PASSWORD; echo; export TARGET_SYS_PASSWORD
```

---

## Expected Output Structure

```
Step0/
├── Scripts/          ← You are here
│   ├── zdm_orchestrate_discovery.sh
│   ├── zdm_source_discovery.sh
│   ├── zdm_target_discovery.sh
│   ├── zdm_server_discovery.sh
│   └── README.md
└── Discovery/        ← Populated after script execution
    ├── source/
    │   ├── zdm_source_discovery_proddb01_NNNNNN_TTTTTT.txt
    │   └── zdm_source_discovery_proddb01_NNNNNN_TTTTTT.json
    ├── target/
    │   ├── zdm_target_discovery_proddb-oda_NNNNNN_TTTTTT.txt
    │   └── zdm_target_discovery_proddb-oda_NNNNNN_TTTTTT.json
    └── server/
        ├── zdm_server_discovery_zdm-jumpbox_NNNNNN_TTTTTT.txt
        └── zdm_server_discovery_zdm-jumpbox_NNNNNN_TTTTTT.json
```

---

## Next Step

After collecting discovery outputs:

1. Review files in `Step0/Discovery/`
2. Proceed to **Step 1: Discovery Questionnaire**
   ```
   prompts/Phase10-Migration/ZDM/Step1-Discovery-Questionnaire.prompt.md
   ```
   Attach the `.txt` output files to provide context to the questionnaire.
