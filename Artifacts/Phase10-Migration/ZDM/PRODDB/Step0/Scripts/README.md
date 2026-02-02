# ZDM Discovery Scripts - PRODDB Migration

This directory contains discovery scripts for the **PRODDB Migration to Oracle Database@Azure** project.

## Purpose

These scripts gather technical context from:
- **Source Database Server** (`proddb01.corp.example.com`)
- **Target Oracle Database@Azure** (`proddb-oda.eastus.azure.example.com`)
- **ZDM Jumpbox Server** (`zdm-jumpbox.corp.example.com`)

The discovery outputs form the foundation for all subsequent migration steps.

## Scripts

| Script | Purpose | Executed On |
|--------|---------|-------------|
| `zdm_source_discovery.sh` | Discovers source database configuration | Source Server |
| `zdm_target_discovery.sh` | Discovers target Oracle Database@Azure | Target Server |
| `zdm_server_discovery.sh` | Discovers ZDM installation and connectivity | ZDM Server |
| `zdm_orchestrate_discovery.sh` | Orchestrates discovery across all servers | Any machine with SSH access |

## Quick Start

### Option 1: Run Orchestration Script (Recommended)

Run from any machine with SSH access to all three servers:

```bash
cd Artifacts/Phase10-Migration/ZDM/PRODDB/Step0/Scripts/

# Show configuration
./zdm_orchestrate_discovery.sh -c

# Test SSH connectivity
./zdm_orchestrate_discovery.sh -t

# Run full discovery
./zdm_orchestrate_discovery.sh
```

### Option 2: Run Individual Scripts

Copy and execute scripts on each server manually:

```bash
# On source server (as oracle user)
./zdm_source_discovery.sh

# On target server (as opc user)
./zdm_target_discovery.sh

# On ZDM server (as azureuser)
SOURCE_HOST=proddb01.corp.example.com TARGET_HOST=proddb-oda.eastus.azure.example.com ./zdm_server_discovery.sh
```

## Configuration

### Server Configuration

| Setting | Value |
|---------|-------|
| Source Host | `proddb01.corp.example.com` |
| Target Host | `proddb-oda.eastus.azure.example.com` |
| ZDM Host | `zdm-jumpbox.corp.example.com` |

### User Configuration

| Server | SSH Admin User | Purpose |
|--------|---------------|---------|
| Source | `oracle` | On-premise server uses oracle user for SSH |
| Target | `opc` | OCI/ODA uses opc user for SSH |
| ZDM | `azureuser` | Azure VM uses azureuser for SSH |

| Application User | Purpose |
|-----------------|---------|
| `oracle` | Oracle database software owner |
| `zdmuser` | ZDM software owner |

### SSH Key Configuration

| Key | Path |
|-----|------|
| Source SSH Key | `~/.ssh/onprem_oracle_key` |
| Target SSH Key | `~/.ssh/oci_opc_key` |
| ZDM SSH Key | `~/.ssh/azure_key` |

## Environment Variable Overrides

You can override any configuration using environment variables:

```bash
# Server hostnames
export SOURCE_HOST="proddb01.corp.example.com"
export TARGET_HOST="proddb-oda.eastus.azure.example.com"
export ZDM_HOST="zdm-jumpbox.corp.example.com"

# SSH users
export SOURCE_ADMIN_USER="oracle"
export TARGET_ADMIN_USER="opc"
export ZDM_ADMIN_USER="azureuser"

# Application users
export ORACLE_USER=oracle
export ZDM_USER=zdmuser

# SSH keys
export SOURCE_SSH_KEY="$HOME/.ssh/onprem_oracle_key"
export TARGET_SSH_KEY="$HOME/.ssh/oci_opc_key"
export ZDM_SSH_KEY="$HOME/.ssh/azure_key"

# Run orchestration
./zdm_orchestrate_discovery.sh
```

## Output

Discovery results are saved to:

```
Artifacts/Phase10-Migration/ZDM/PRODDB/Step0/Discovery/
├── source/          # Source database discovery results
│   ├── zdm_source_discovery_<hostname>_<timestamp>.txt
│   └── zdm_source_discovery_<hostname>_<timestamp>.json
├── target/          # Target database discovery results
│   ├── zdm_target_discovery_<hostname>_<timestamp>.txt
│   └── zdm_target_discovery_<hostname>_<timestamp>.json
└── server/          # ZDM server discovery results
    ├── zdm_server_discovery_<hostname>_<timestamp>.txt
    └── zdm_server_discovery_<hostname>_<timestamp>.json
```

## Additional Discovery Items

### Source Database
In addition to standard discovery, these scripts also gather:
- All tablespace autoextend settings
- Current backup schedule and retention
- Database links configured
- Materialized view refresh schedules
- Scheduler jobs that may need reconfiguration

### Target Database (Oracle Database@Azure)
In addition to standard discovery, these scripts also gather:
- Available Exadata storage capacity
- Pre-configured PDBs
- Network security group rules

### ZDM Server
In addition to standard discovery, these scripts also verify:
- Available disk space for ZDM operations (minimum 50GB recommended)
- Network latency to source and target (ping tests)
- Port connectivity tests (SSH port 22, Oracle port 1521)

## SSH Authentication Pattern

These scripts use a secure admin-user-with-sudo pattern:

```
ZDM Server (zdmuser)
     │
     ├──► SSH as SOURCE_ADMIN_USER ──► sudo -u oracle (for SQL)
     │         (oracle)
     │
     └──► SSH as TARGET_ADMIN_USER ──► sudo -u oracle (for SQL)
               (opc)
```

- We do NOT SSH directly as 'oracle' on systems where direct oracle login is disabled
- SQL commands run as the oracle user via sudo
- ZDM CLI commands run as the zdmuser via sudo

## Next Steps

After running discovery:

1. Review discovery output files in `../Discovery/`
2. Proceed to **Step 1: Discovery Questionnaire**
   - Use `@Step1-Discovery-Questionnaire.prompt.md` to complete the full questionnaire
3. Address any issues identified in **Step 2: Fix Issues**
4. Generate migration artifacts in **Step 3**

## Troubleshooting

### SSH Connection Failed

1. Verify SSH keys are in the correct location
2. Check key permissions: `chmod 600 ~/.ssh/<keyfile>`
3. Test manually: `ssh -i ~/.ssh/<keyfile> user@host`

### Oracle Environment Not Detected

The scripts auto-detect Oracle using:
1. `/etc/oratab` entries
2. Running `pmon` processes
3. Common installation paths

If auto-detection fails, set environment variables before running:
```bash
export SOURCE_REMOTE_ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1
export SOURCE_REMOTE_ORACLE_SID=PRODDB
```

### ZDM Not Detected

The scripts detect ZDM using multiple methods. If auto-detection fails:
```bash
export ZDM_REMOTE_ZDM_HOME=/home/zdmuser/zdmhome
```

## Security Notes

⚠️ **NEVER commit passwords to source control.**

Password environment variables (`SOURCE_SYS_PASSWORD`, `TARGET_SYS_PASSWORD`, `SOURCE_TDE_WALLET_PASSWORD`) should be set at runtime on the ZDM server before running migration scripts in Step 3.

```bash
# Secure password entry (on ZDM server)
read -sp "Enter SOURCE_SYS_PASSWORD: " SOURCE_SYS_PASSWORD; echo; export SOURCE_SYS_PASSWORD
```
