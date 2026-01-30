# ZDM Migration Step 0: Generate Discovery Scripts

## Purpose
This prompt generates the discovery scripts that will be used to gather information from the source database server, target Oracle Database@Azure server, and ZDM jumpbox server.

---

## Instructions

Run this prompt to generate fresh discovery scripts. These scripts should be generated at the start of each migration project to ensure they contain the latest discovery logic.

---

## Generate Discovery Scripts

Please generate the following discovery scripts for a ZDM migration from on-premise Oracle to Oracle Database@Azure:

### 1. Source Database Discovery Script (`zdm_source_discovery.sh`)

Generate a bash script to run on the **source database server** (executed via SSH as ADMIN_USER, with SQL commands running as oracle user via sudo) that discovers:

**OS Information:**
- Hostname, IP addresses
- Operating system version
- Disk space

**Oracle Environment:**
- ORACLE_HOME, ORACLE_SID, ORACLE_BASE
- Oracle version

**Database Configuration:**
- Database name, unique name, DBID
- Database role, open mode
- Log mode (ARCHIVELOG/NOARCHIVELOG)
- Force logging status
- Database size (data files, temp files)
- Character set and national character set

**Container Database:**
- CDB status
- PDB names and status (if CDB)

**TDE Configuration:**
- TDE enabled status
- Wallet type and location
- Encrypted tablespaces

**Supplemental Logging:**
- Supplemental log data min, PK, UI, FK, ALL

**Redo/Archive Configuration:**
- Redo log groups, sizes, members
- Archive log destinations

**Network Configuration:**
- Listener status and configuration
- tnsnames.ora contents
- sqlnet.ora contents

**Authentication:**
- Password file location
- SSH directory contents

**Data Guard:**
- Current DG configuration parameters

**Schema Information:**
- Schema sizes (non-system schemas > 100MB)
- Invalid objects count by owner/type

**Output Format:**
- Text report: `./zdm_source_discovery_<hostname>_<timestamp>.txt` (in current working directory)
- JSON summary: `./zdm_source_discovery_<hostname>_<timestamp>.json` (in current working directory)
- The orchestration script will collect these to the Artifacts directory

---

### 2. Target Database Discovery Script (`zdm_target_discovery.sh`)

Generate a bash script to run on the **target database server** (Oracle Database@Azure, executed via SSH as ADMIN_USER, with SQL commands running as oracle user via sudo) that discovers:

**OS Information:**
- Hostname, IP addresses
- Operating system version

**Oracle Environment:**
- ORACLE_HOME, ORACLE_SID, ORACLE_BASE
- Oracle version

**Database Configuration:**
- Database name, unique name
- Database role, open mode
- Available storage (tablespaces, ASM if applicable)
- Character set

**Container Database:**
- CDB status
- PDB names and status

**TDE Configuration:**
- TDE/wallet status

**Network Configuration:**
- Listener status
- SCAN listener (if RAC)
- tnsnames.ora contents

**OCI/Azure Integration:**
- OCI CLI version and configuration
- OCI connectivity test
- Instance metadata (OCI and Azure)

**Grid Infrastructure (if RAC):**
- CRS status

**Authentication:**
- SSH directory contents

**Output Format:**
- Text report: `./zdm_target_discovery_<hostname>_<timestamp>.txt` (in current working directory)
- JSON summary: `./zdm_target_discovery_<hostname>_<timestamp>.json` (in current working directory)
- The orchestration script will collect these to the Artifacts directory

---

### 3. ZDM Server Discovery Script (`zdm_server_discovery.sh`)

Generate a bash script to run on the **ZDM jumpbox server** (executed via SSH as ADMIN_USER for OS-level discovery, with ZDM CLI commands running as ZDM_USER via sudo) that discovers:

**OS Information:**
- Hostname, current user
- Operating system version

**ZDM Installation:**
- ZDM_HOME location
- ZDM version
- ZDM service status
- Active migration jobs

**Java Configuration:**
- Java version
- JAVA_HOME

**OCI CLI Configuration:**
- OCI CLI version
- OCI config file location and contents (masked sensitive data)
- Configured profiles and regions
- API key file existence
- OCI connectivity test

**SSH Configuration:**
- Available SSH keys (public and private)
- SSH directory contents

**Credential Files:**
- Search for password/credential files

**Network Configuration:**
- IP addresses
- Routing table
- DNS configuration

**ZDM Logs:**
- Log directory location
- Recent log files

**Output Format:**
- Text report: `./zdm_server_discovery_<hostname>_<timestamp>.txt` (in current working directory)
- JSON summary: `./zdm_server_discovery_<hostname>_<timestamp>.json` (in current working directory)
- The orchestration script will collect these to the Artifacts directory

---

### 4. Master Orchestration Script (`zdm_orchestrate_discovery.sh`)

Generate a bash script that can be run from any machine with SSH access to orchestrate discovery across all servers:

**Configuration:**
- Environment variables for SOURCE_HOST, TARGET_HOST, ZDM_HOST
- Environment variables for SSH/admin users (each server can have a different admin user):
  - SOURCE_ADMIN_USER: Linux admin user for source database server (default: "azureuser")
  - TARGET_ADMIN_USER: Linux admin user for target Oracle Database@Azure server (default: "azureuser")
  - ZDM_ADMIN_USER: Linux admin user for ZDM jumpbox server (default: "azureuser")
- Environment variables for application users:
  - ORACLE_USER: Oracle database software owner (default: "oracle")
  - ZDM_USER: ZDM software owner user for ZDM CLI commands (default: "zdmuser")
- Separate SSH key paths for each environment:
  - SOURCE_SSH_KEY: SSH key for source database server
  - TARGET_SSH_KEY: SSH key for target Oracle Database@Azure server
  - ZDM_SSH_KEY: SSH key for ZDM jumpbox server
  (Note: These are typically different keys due to separate security domains)

**User Execution Model:**
- Each server can have a different admin user for SSH connections:
  - Source server: SOURCE_ADMIN_USER (default: "azureuser")
  - Target server: TARGET_ADMIN_USER (default: "azureuser")
  - ZDM server: ZDM_ADMIN_USER (default: "azureuser")
- OS-level discovery commands run as the respective admin user
- Oracle SQL commands run as ORACLE_USER (default: "oracle") via `sudo -u oracle`
- ZDM CLI commands run as ZDM_USER (default: "zdmuser") via `sudo -u zdmuser`

**Environment Variable Defaults in Orchestration Script:**
```bash
# ===========================================
# USER CONFIGURATION
# ===========================================

# SSH/Admin users for each server (can be different for each environment)
# These are Linux admin users with sudo privileges
SOURCE_ADMIN_USER="${SOURCE_ADMIN_USER:-azureuser}"
TARGET_ADMIN_USER="${TARGET_ADMIN_USER:-azureuser}"
ZDM_ADMIN_USER="${ZDM_ADMIN_USER:-azureuser}"

# Oracle database software owner (for running SQL commands)
ORACLE_USER="${ORACLE_USER:-oracle}"

# ZDM software owner (for running ZDM CLI commands)
ZDM_USER="${ZDM_USER:-zdmuser}"
```

**Functions:**
- Configuration validation
- SSH connectivity testing
- Copy and execute discovery scripts remotely
- Collect results to local Artifacts directory

**Output Directory:**
- Default output should be the Artifacts directory: `Artifacts/Phase10-Migration/ZDM/<DB_NAME>/Step0/Discovery/`
- Configurable via command-line option or environment variable
- Create subdirectories for each server type (source/, target/, server/)

**Resilience Requirements:**
- **Continue on failure** - If one server discovery fails, continue with the remaining servers
- **Login shell for remote execution** - SSH commands run non-interactively, which means `.bashrc` is typically NOT sourced (it often has guards like `[ -z "$PS1" ] && return` at the top). To ensure environment variables like ZDM_HOME, ORACLE_HOME, JAVA_HOME are available:
  - Use `bash -l -c 'command'` to force a login shell when executing remote scripts
  - This ensures `.bash_profile` and `.bashrc` are properly sourced
- **Auto-detection as primary method** - The remote discovery scripts should auto-detect Oracle and ZDM environments by:
  - Parsing /etc/oratab for Oracle homes and SIDs
  - Checking running pmon processes
  - Searching common installation paths
  - Using Java alternatives or common Java paths
- **Optional explicit overrides** - Allow explicit configuration of environment variables as fallback when auto-detection fails. These can be:
  - Set as environment variables before running the orchestration script
  - Or specified in `zdm-env.md` and referenced in the prompt with `@zdm-env.md`
  - Available overrides:
    - ZDM_REMOTE_ZDM_HOME: Path to ZDM home directory on ZDM server
    - ZDM_REMOTE_JAVA_HOME: Path to Java home on ZDM server
    - SOURCE_REMOTE_ORACLE_HOME: Path to Oracle home on source server
    - SOURCE_REMOTE_ORACLE_SID: Oracle SID on source server
    - TARGET_REMOTE_ORACLE_HOME: Path to Oracle home on target server
    - TARGET_REMOTE_ORACLE_SID: Oracle SID on target server
- **Error tracking** - Track which servers succeeded/failed and report at the end
- **Partial success** - A discovery run with 2 out of 3 servers successful should still save and report the successful results

**Features:**
- Help message (-h, --help)
- Config display (-c, --config)
- Connectivity test only (-t, --test)
- Color-coded terminal output
- Resilient error handling (continue despite individual failures)

---

## Script Requirements

All scripts should include:
- Shebang (`#!/bin/bash`)
- **Resilient error handling** - Do NOT use `set -e` globally; instead use individual error trapping so scripts continue running even when some checks fail
- **Environment variable discovery with auto-detection** - Use a priority-based approach:
  1. **Environment variable** - If already set in the environment (e.g., `export ORACLE_HOME=...`), use it
  2. **Auto-detection** - If not set, attempt to discover automatically using the methods below
  3. **Fallback override** - Accept explicit overrides passed from orchestration script as last resort

- **Auto-detection methods** - Scripts should include functions to auto-detect Oracle and ZDM environments:
  ```bash
  # Auto-detect ORACLE_HOME and ORACLE_SID
  detect_oracle_env() {
      # If already set, use existing values
      if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
          return 0
      fi
      
      # Method 1: Parse /etc/oratab (most reliable)
      if [ -f /etc/oratab ]; then
          # Get first non-comment entry, or match specific SID if provided
          local oratab_entry
          if [ -n "${ORACLE_SID:-}" ]; then
              oratab_entry=$(grep "^${ORACLE_SID}:" /etc/oratab 2>/dev/null | head -1)
          else
              oratab_entry=$(grep -v '^#' /etc/oratab | grep -v '^$' | head -1)
          fi
          if [ -n "$oratab_entry" ]; then
              export ORACLE_SID="${ORACLE_SID:-$(echo "$oratab_entry" | cut -d: -f1)}"
              export ORACLE_HOME="${ORACLE_HOME:-$(echo "$oratab_entry" | cut -d: -f2)}"
          fi
      fi
      
      # Method 2: Check running pmon process
      if [ -z "${ORACLE_SID:-}" ]; then
          local pmon_sid
          pmon_sid=$(ps -ef | grep 'ora_pmon_' | grep -v grep | head -1 | sed 's/.*ora_pmon_//')
          [ -n "$pmon_sid" ] && export ORACLE_SID="$pmon_sid"
      fi
      
      # Method 3: Search common Oracle installation paths
      if [ -z "${ORACLE_HOME:-}" ]; then
          for path in /u01/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1 /oracle/product/*/dbhome_1; do
              if [ -d "$path" ] && [ -f "$path/bin/sqlplus" ]; then
                  export ORACLE_HOME="$path"
                  break
              fi
          done
      fi
      
      # Method 4: Check oraenv/coraenv
      if [ -z "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
          [ -f /usr/local/bin/oraenv ] && . /usr/local/bin/oraenv <<< "$ORACLE_SID" 2>/dev/null
      fi
  }
  
  # Auto-detect ZDM_HOME and JAVA_HOME (for ZDM server script)
  detect_zdm_env() {
      # If already set, use existing values
      if [ -n "${ZDM_HOME:-}" ] && [ -n "${JAVA_HOME:-}" ]; then
          return 0
      fi
      
      # Detect ZDM_HOME
      if [ -z "${ZDM_HOME:-}" ]; then
          # Check common ZDM installation locations
          for path in ~/zdmhome ~/zdm /opt/zdm /u01/zdm "$HOME/zdmhome"; do
              if [ -d "$path" ] && [ -f "$path/bin/zdmcli" ]; then
                  export ZDM_HOME="$path"
                  break
              fi
          done
      fi
      
      # Detect JAVA_HOME
      if [ -z "${JAVA_HOME:-}" ]; then
          # Method 1: Check alternatives
          if command -v java >/dev/null 2>&1; then
              local java_path
              java_path=$(readlink -f "$(command -v java)" 2>/dev/null)
              if [ -n "$java_path" ]; then
                  export JAVA_HOME="${java_path%/bin/java}"
              fi
          fi
          
          # Method 2: Search common Java paths
          if [ -z "${JAVA_HOME:-}" ]; then
              for path in /usr/java/latest /usr/java/jdk* /usr/lib/jvm/java-* /opt/java/jdk*; do
                  if [ -d "$path" ] && [ -f "$path/bin/java" ]; then
                      export JAVA_HOME="$path"
                      break
                  fi
              done
          fi
      fi
  }
  ```

- **Apply overrides after auto-detection** - If orchestration script passes explicit overrides, apply them last:
  ```bash
  # Apply explicit overrides if provided (highest priority)
  [ -n "${ORACLE_HOME_OVERRIDE:-}" ] && export ORACLE_HOME="$ORACLE_HOME_OVERRIDE"
  [ -n "${ORACLE_SID_OVERRIDE:-}" ] && export ORACLE_SID="$ORACLE_SID_OVERRIDE"
  [ -n "${ZDM_HOME_OVERRIDE:-}" ] && export ZDM_HOME="$ZDM_HOME_OVERRIDE"
  [ -n "${JAVA_HOME_OVERRIDE:-}" ] && export JAVA_HOME="$JAVA_HOME_OVERRIDE"
  
  # User defaults - can be overridden via environment
  ORACLE_USER="${ORACLE_USER:-oracle}"
  ZDM_USER="${ZDM_USER:-zdmuser}"
  ```
- **Execute SQL as oracle user** - All `run_sql` and `run_sql_value` functions must ensure SQL commands are executed as the ORACLE_USER (default: oracle):
  ```bash
  # Default oracle user if not set
  ORACLE_USER="${ORACLE_USER:-oracle}"
  
  run_sql() {
      local sql_query="$1"
      if [ -n "${ORACLE_HOME:-}" ] && [ -n "${ORACLE_SID:-}" ]; then
          local sqlplus_cmd="$ORACLE_HOME/bin/sqlplus -s / as sysdba"
          local sql_script=$(cat <<EOSQL
  SET PAGESIZE 1000
  SET LINESIZE 200
  SET FEEDBACK OFF
  SET HEADING ON
  SET ECHO OFF
  $sql_query
  EOSQL
  )
          # Execute as oracle user - use sudo if current user is not oracle
          if [ "$(whoami)" = "$ORACLE_USER" ]; then
              echo "$sql_script" | $sqlplus_cmd
          else
              echo "$sql_script" | sudo -u "$ORACLE_USER" -E ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd
          fi
      else
          echo "ERROR: ORACLE_HOME or ORACLE_SID not set"
          return 1
      fi
  }
  ```
- **Execute ZDM CLI as zdmuser** - All ZDM CLI commands must be executed as the ZDM_USER (default: zdmuser):
  ```bash
  # Default ZDM user if not set
  ZDM_USER="${ZDM_USER:-zdmuser}"
  
  run_zdm_cmd() {
      local zdm_cmd="$1"
      if [ -n "${ZDM_HOME:-}" ]; then
          # Execute as zdmuser - use sudo if current user is not zdmuser
          if [ "$(whoami)" = "$ZDM_USER" ]; then
              $ZDM_HOME/bin/$zdm_cmd
          else
              sudo -u "$ZDM_USER" -E ZDM_HOME="$ZDM_HOME" $ZDM_HOME/bin/$zdm_cmd
          fi
      else
          echo "ERROR: ZDM_HOME not set"
          return 1
      fi
  }
  ```
- Color-coded terminal output
- Clear section headers in output
- Both human-readable text and machine-parseable JSON output
- Usage instructions
- Timestamps in filenames
- **Continue on failure** - Each discovery section should be wrapped in error handling that logs failures but continues to the next section
- **Output to current directory** - Write output files to the current working directory (not /tmp) so the orchestration script can easily collect them

---

## Output Location

Save all Step 0 outputs to: `Artifacts/Phase10-Migration/ZDM/<DB_NAME>/Step0/`

The directory structure for each migration should be:
```
Artifacts/Phase10-Migration/ZDM/<DB_NAME>/
├── Step0/                                    # Step 0: Discovery Scripts
│   ├── Scripts/                              # Discovery scripts
│   │   ├── zdm_source_discovery.sh
│   │   ├── zdm_target_discovery.sh
│   │   ├── zdm_server_discovery.sh
│   │   ├── zdm_orchestrate_discovery.sh
│   │   └── README.md
│   ├── README.md                             # Step 0 instructions
│   └── Discovery/                            # Discovery output files (after execution)
│       ├── zdm_source_discovery_*.txt
│       ├── zdm_source_discovery_*.json
│       ├── zdm_target_discovery_*.txt
│       ├── zdm_target_discovery_*.json
│       ├── zdm_server_discovery_*.txt
│       └── zdm_server_discovery_*.json
├── Step1/                                    # Step 1: Completed Questionnaire
│   └── Completed-Questionnaire-<DB_NAME>.md
└── Step2/                                    # Step 2: Migration Artifacts
    ├── zdm_migrate_<DB_NAME>.rsp
    ├── zdm_commands_<DB_NAME>.sh
    └── ZDM-Migration-Runbook-<DB_NAME>.md
```

---

## Next Steps

After generating discovery scripts:
1. Copy discovery scripts to respective servers
2. Execute scripts to gather discovery information
3. Collect output files to `Step0/Discovery/`
4. Proceed to **Step 1: Discovery Questionnaire** to complete the full questionnaire with discovery data and business decisions
