# PRODDB Migration Discovery Scripts

## Project Information
- **Project Name:** PRODDB Migration to Oracle Database@Azure
- **Source Database:** proddb01.corp.example.com
- **Target Database:** proddb-oda.eastus.azure.example.com
- **ZDM Server:** zdm-jumpbox.corp.example.com
- **Generated:** 2026-01-29

## Scripts Overview

| Script | Purpose | Run On | Run As |
|--------|---------|--------|--------|
| `zdm_source_discovery.sh` | Discover source database configuration | Source DB Server | oracle |
| `zdm_target_discovery.sh` | Discover target Oracle Database@Azure configuration | Target Server | opc/oracle |
| `zdm_server_discovery.sh` | Discover ZDM jumpbox configuration | ZDM Server | zdmuser |
| `zdm_orchestrate_discovery.sh` | Orchestrate discovery across all servers | Any machine with SSH access | Any user |

## Quick Start

### Option 1: Orchestrated Discovery (Recommended)

Run the orchestration script from a machine with SSH access to all three servers:

```bash
# Set environment variables (optional - defaults are configured)
export SOURCE_SSH_KEY=~/.ssh/source_db_key
export TARGET_SSH_KEY=~/.ssh/oda_azure_key
export ZDM_SSH_KEY=~/.ssh/zdm_jumpbox_key

# Test connectivity first
./zdm_orchestrate_discovery.sh --test

# Run full discovery
./zdm_orchestrate_discovery.sh
```

### Option 2: Manual Discovery

Run each script individually on the respective servers:

```bash
# On source database server (as oracle user)
./zdm_source_discovery.sh

# On target Oracle Database@Azure server (as opc or oracle user)
./zdm_target_discovery.sh

# On ZDM jumpbox server (as zdmuser)
./zdm_server_discovery.sh
```

## Configuration

### SSH Keys

The following SSH keys are configured for this migration:

| Server | SSH Key Path |
|--------|--------------|
| Source Database | `~/.ssh/source_db_key` |
| Target Database | `~/.ssh/oda_azure_key` |
| ZDM Server | `~/.ssh/zdm_jumpbox_key` |

### Environment Variable Overrides

If remote servers have non-interactive shell guards in `.bashrc` that prevent environment variable sourcing, use these explicit overrides:

```bash
# Source server
export SOURCE_REMOTE_ORACLE_HOME=/u01/app/oracle/product/19.0.0.0/dbhome_1
export SOURCE_REMOTE_ORACLE_SID=PRODDB

# Target server
export TARGET_REMOTE_ORACLE_HOME=/u01/app/oracle/product/19.0.0.0/dbhome_1
export TARGET_REMOTE_ORACLE_SID=PRODDB

# ZDM server
export ZDM_REMOTE_ZDM_HOME=/home/zdmuser/zdmhome
export ZDM_REMOTE_JAVA_HOME=/usr/java/jdk1.8.0_391
```

## Additional Discovery Items (PRODDB-Specific)

### Source Database Discovery
In addition to standard discovery, the source script gathers:
- All tablespace autoextend settings
- Current backup schedule and retention
- Any database links configured
- Materialized view refresh schedules
- Scheduler jobs that may need reconfiguration

### Target Database Discovery (Oracle Database@Azure)
In addition to standard discovery, the target script gathers:
- Available Exadata storage capacity
- Pre-configured PDBs
- Network security group rules

### ZDM Server Discovery
In addition to standard discovery, the ZDM script verifies:
- Available disk space for ZDM operations (minimum 50GB recommended)
- Network latency to source and target (ping tests)

## Output Files

After running discovery, output files will be saved to:

```
../Discovery/
├── source/
│   ├── zdm_source_discovery_<hostname>_<timestamp>.txt
│   └── zdm_source_discovery_<hostname>_<timestamp>.json
├── target/
│   ├── zdm_target_discovery_<hostname>_<timestamp>.txt
│   └── zdm_target_discovery_<hostname>_<timestamp>.json
└── server/
    ├── zdm_server_discovery_<hostname>_<timestamp>.txt
    └── zdm_server_discovery_<hostname>_<timestamp>.json
```

## Orchestration Script Options

```
Usage: zdm_orchestrate_discovery.sh [options]

Options:
    -h, --help          Show help message
    -c, --config        Display current configuration
    -t, --test          Test SSH connectivity only
    -s, --source-only   Run discovery on source server only
    -T, --target-only   Run discovery on target server only
    -z, --zdm-only      Run discovery on ZDM server only
    -o, --output DIR    Override output directory
    -v, --verbose       Enable verbose output
```

## Resilience Features

The discovery scripts include the following resilience features:

1. **Continue on Failure** - If one server discovery fails, the orchestration continues with remaining servers
2. **Login Shell Execution** - Uses `bash -l` to ensure environment variables are properly sourced
3. **Environment Override Support** - Explicit environment variables can be passed when profile sourcing fails
4. **Error Tracking** - Failed and successful discoveries are tracked and reported
5. **Partial Success Handling** - Results from successful discoveries are preserved even when others fail

## Next Steps

After running discovery:

1. Review the discovery output files in the `Discovery/` directory
2. Proceed to **Step 1: Discovery Questionnaire** 
   - Use the discovery data to complete the migration questionnaire
3. Generate migration artifacts in **Step 2**

## Troubleshooting

### SSH Connection Issues
```bash
# Test SSH connectivity
ssh -i ~/.ssh/source_db_key -o BatchMode=yes oracle@proddb01.corp.example.com "hostname"

# Check key permissions
chmod 600 ~/.ssh/source_db_key
```

### Environment Variables Not Sourced
If Oracle/ZDM environment variables are not being sourced on remote servers, use the explicit override environment variables documented above.

### Discovery Script Failures
Each discovery section is wrapped in error handling. Check the output files for specific sections that failed. Common issues:
- Oracle database not running
- Insufficient privileges
- Network connectivity issues

## Support

For issues with these discovery scripts, contact the migration team or refer to the ZDM documentation.
