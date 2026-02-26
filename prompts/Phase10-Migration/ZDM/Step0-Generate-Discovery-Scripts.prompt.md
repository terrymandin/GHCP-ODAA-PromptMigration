# ZDM Migration Step 0: Run Scripts to Get Context

## Purpose
This prompt generates the discovery scripts that will be used to gather technical context from the source database server, target Oracle Database@Azure server, and ZDM jumpbox server. The discovery outputs form the foundation for all subsequent migration steps.

---

## Migration Flow Overview

```
Step 0: Run Scripts to Get Context    ← YOU ARE HERE
         ↓
Step 1: Get Manual Configuration Context
         ↓
Step 2: Fix Issues (Iteration may be required)
         ↓
Step 3: Generate Migration Artifacts & Run Migration
```

---

## SSH Authentication Pattern

> **IMPORTANT:** The discovery scripts use a secure admin-user-with-sudo pattern, NOT direct SSH as oracle.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  SSH Authentication Model                                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ZDM Server (zdmuser)                                                        │
│       │                                                                      │
│       ├──► SSH as SOURCE_ADMIN_USER ──► sudo -u oracle (for SQL)            │
│       │         (e.g., temandin)                                             │
│       │                                                                      │
│       └──► SSH as TARGET_ADMIN_USER ──► sudo -u oracle (for SQL)            │
│                 (e.g., opc)                                                  │
│                                                                              │
│  We do NOT SSH directly as 'oracle' - this follows enterprise security      │
│  patterns where direct oracle login is disabled.                             │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Environment Variables:**
- `SOURCE_ADMIN_USER` - Admin user for SSH to source (default: oracle, but often a named admin like temandin)
- `TARGET_ADMIN_USER` - Admin user for SSH to target (default: opc for Exadata/ODA)
- `ORACLE_USER` - Database software owner for sudo (default: oracle)

**Discovery scripts automatically:**
1. SSH as the admin user (SOURCE_ADMIN_USER or TARGET_ADMIN_USER)
2. Detect if running as oracle; if not, use `sudo -u oracle` for SQL commands
3. This means "SSH directory not found for oracle user" is NOT a blocker

---

## Instructions

### Step 1: Specify Database Name

Before generating discovery scripts, specify the database name that will be used throughout all migration steps:

**DATABASE Name:** `<YOUR_DATABASE_NAME>`

> **Important:** This database name will be used to:
> - Organize all artifacts: `Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/`
> - Name output files in Steps 1-3
> - Track this specific migration project
>
> **Replace `<DATABASE_NAME>` with your actual database name** (e.g., PRODDB, FINANCEDB, SALESDB)

---

### Step 2: Generate Discovery Scripts

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
- ZDM_HOME location (must detect even when running as different user than zdmuser)
- ZDM installation verification (check if `$ZDM_HOME/bin/zdmcli` exists and is executable)
- ZDM service status (via `zdmservice status`)
- Active migration jobs

**IMPORTANT: ZDM Version Detection:**
ZDM does NOT support a `-version` flag. To verify ZDM is installed:
1. Check if `$ZDM_HOME/bin/zdmcli` exists and is executable
2. Run `$ZDM_HOME/bin/zdmcli` without arguments - it will display usage information if installed correctly
3. Check for ZDM response file templates at `$ZDM_HOME/rhp/zdm/template/*.rsp`
4. Use `zdmservice status` to check if the ZDM service is running
Do NOT use `zdmcli -version` as this is an invalid command.

**IMPORTANT: ZDM Detection Requirements:**
The script may be executed as a different user (e.g., azureuser) than the ZDM software owner (zdmuser). The script MUST detect ZDM using these methods in priority order:
1. **Get ZDM_HOME from zdmuser's environment** - Use `sudo -u zdmuser -i bash -c 'echo $ZDM_HOME'` to get the environment variable from the zdmuser's login shell
2. **Check zdmuser's home directory** - Look for common paths like `~zdmuser/zdmhome`, `~zdmuser/app/zdmhome`
3. **Search common system paths** - Check `/u01/app/zdmhome`, `/u01/zdm`, `/opt/zdm`, etc.
4. **Find zdmcli binary** - Use `sudo find` to locate the zdmcli binary and derive ZDM_HOME from it
5. **Check for ZDM's bundled JDK** - ZDM often includes its own JDK at `$ZDM_HOME/jdk`

**Java Configuration:**
- Java version (check ZDM's bundled JDK at `$ZDM_HOME/jdk` first)
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

**IMPORTANT: Network Connectivity Tests to Source and Target:**
The ZDM server discovery script MUST test network connectivity to the source and target database servers. These hostnames are NOT hardcoded in the script - they MUST be passed as environment variables by the orchestration script:

```bash
# Environment variables that MUST be set by orchestration script
SOURCE_HOST="${SOURCE_HOST:-}"   # Source database hostname (passed from orchestration)
TARGET_HOST="${TARGET_HOST:-}"   # Target database hostname (passed from orchestration)
```

The script should:
1. **Only run connectivity tests if SOURCE_HOST and TARGET_HOST are provided** - Skip tests gracefully if not set
2. **Ping tests** - Test ICMP connectivity and measure latency
3. **Port tests** - Test SSH (22) and Oracle (1521) port connectivity using `timeout` and `/dev/tcp`
4. **Report clearly** - Show SUCCESS/FAILED for each test with actionable guidance

Example connectivity test logic:
```bash
# Test connectivity only if hosts are provided
if [ -n "${SOURCE_HOST:-}" ]; then
    # Ping test
    if ping -c 3 "$SOURCE_HOST" &>/dev/null; then
        SOURCE_PING="SUCCESS"
    else
        SOURCE_PING="FAILED"
    fi
    
    # Port tests
    for port in 22 1521; do
        if timeout 5 bash -c "echo >/dev/tcp/$SOURCE_HOST/$port" 2>/dev/null; then
            log_info "Source port $port: OPEN"
        else
            log_warn "Source port $port: BLOCKED or unreachable"
        fi
    done
else
    log_info "SOURCE_HOST not provided - skipping source connectivity tests"
    SOURCE_PING="SKIPPED"
fi
```

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

---

## Required Password/Credential Environment Variables

> ⚠️ **SECURITY WARNING**: Never commit passwords or secrets to GitHub or any source control system. The environment variables below must be set at runtime on the ZDM server before executing migration scripts. Step 1 questionnaire will reference these variables rather than requesting direct password entry. Step 2 generated scripts will validate that these variables are set before executing.

The following environment variables must be set before running ZDM migration scripts. These are used in Step 2 when generating migration artifacts and executing the migration.

### Required Password Variables

| Variable | Description | Required For |
|----------|-------------|--------------|
| `SOURCE_SYS_PASSWORD` | Source Oracle SYS password | All migrations |
| `SOURCE_TDE_WALLET_PASSWORD` | Source TDE wallet password | TDE-enabled databases |
| `TARGET_SYS_PASSWORD` | Target Oracle SYS password | All migrations |

### How to Set Password Variables Securely

**On the ZDM server (Linux) - Set at runtime:**
```bash
# Set password environment variables (do NOT save to a file in the repo)
# Run this in your terminal session before executing migration scripts

export SOURCE_SYS_PASSWORD="your_source_sys_password"
export SOURCE_TDE_WALLET_PASSWORD="your_tde_wallet_password"  # Only if TDE enabled
export TARGET_SYS_PASSWORD="your_target_sys_password"
```

**Alternative: Use a secure credential store or prompt:**
```bash
# Prompt for passwords securely (passwords not visible while typing)
read -sp "Enter SOURCE_SYS_PASSWORD: " SOURCE_SYS_PASSWORD; echo; export SOURCE_SYS_PASSWORD
read -sp "Enter SOURCE_TDE_WALLET_PASSWORD: " SOURCE_TDE_WALLET_PASSWORD; echo; export SOURCE_TDE_WALLET_PASSWORD
read -sp "Enter TARGET_SYS_PASSWORD: " TARGET_SYS_PASSWORD; echo; export TARGET_SYS_PASSWORD
```

**PowerShell Equivalent (Windows):**
```powershell
# Set password environment variables
$env:SOURCE_SYS_PASSWORD = Read-Host "Enter SOURCE_SYS_PASSWORD" -AsSecureString | ConvertFrom-SecureString -AsPlainText
$env:SOURCE_TDE_WALLET_PASSWORD = Read-Host "Enter SOURCE_TDE_WALLET_PASSWORD" -AsSecureString | ConvertFrom-SecureString -AsPlainText
$env:TARGET_SYS_PASSWORD = Read-Host "Enter TARGET_SYS_PASSWORD" -AsSecureString | ConvertFrom-SecureString -AsPlainText
```

### OCI/Azure Configuration Variables

These non-sensitive identifiers can be set in environment or configuration files:

```bash
# --- OCI Authentication ---
export OCI_USER_OCID="<oci_user_ocid>"
export OCI_COMPARTMENT_OCID="<oci_compartment_ocid>"
export TARGET_DB_SYSTEM_OCID="<target_db_system_ocid>"
export TARGET_DATABASE_OCID="<target_database_ocid>"
export OCI_API_KEY_FINGERPRINT="<oci_api_key_fingerprint>"
export OCI_CONFIG_PATH="~/.oci/config"
export OCI_PRIVATE_KEY_PATH="~/.oci/oci_api_key.pem"

# --- OCI Object Storage ---
export OCI_OSS_NAMESPACE="<oci_oss_namespace>"
export OCI_OSS_BUCKET_NAME="<oci_oss_bucket_name>"
```

### Password Variable Validation

Step 2 generated scripts will include validation to check that required password environment variables are set before executing:

```bash
# Example validation included in generated scripts
check_required_passwords() {
    local missing_vars=()
    
    [ -z "${SOURCE_SYS_PASSWORD:-}" ] && missing_vars+=("SOURCE_SYS_PASSWORD")
    [ -z "${TARGET_SYS_PASSWORD:-}" ] && missing_vars+=("TARGET_SYS_PASSWORD")
    
    # Check TDE password only if TDE is enabled
    if [ "${TDE_ENABLED:-false}" = "true" ] && [ -z "${SOURCE_TDE_WALLET_PASSWORD:-}" ]; then
        missing_vars+=("SOURCE_TDE_WALLET_PASSWORD")
    fi
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        echo "ERROR: The following required password environment variables are not set:"
        printf '  - %s\n' "${missing_vars[@]}"
        echo ""
        echo "Set these variables before running the migration script:"
        printf '  export %s="<value>"\n' "${missing_vars[@]}"
        exit 1
    fi
    
    echo "✓ All required password environment variables are set"
}
```

---

**Functions:**
- Configuration validation
- SSH connectivity testing
- Copy and execute discovery scripts remotely
- Collect results to local Artifacts directory

**Output Directory:**
- Default output should be the Discovery directory **relative to the repository root**: `Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step0/Discovery/`
- The script must calculate the repository root by navigating up from `SCRIPT_DIR`. Since the script is located at `Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step0/Scripts/`, use: `REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../../.." && pwd)"` (6 levels up: Scripts → Step0 → <DATABASE_NAME> → ZDM → Phase10-Migration → Artifacts → RepoRoot)
- Use an absolute path for `OUTPUT_DIR` by combining `REPO_ROOT` with the relative path: `OUTPUT_DIR="${REPO_ROOT}/Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step0/Discovery"`
- Configurable via command-line option or environment variable (when set externally, use as-is)
- Create subdirectories for each server type (source/, target/, server/)

**Resilience Requirements:**
- **Continue on failure** - If one server discovery fails, continue with the remaining servers
- **Login shell for remote execution** - SSH commands run non-interactively, which means `.bashrc` is typically NOT sourced (it often has guards like `[ -z "$PS1" ] && return` at the top). To ensure environment variables like ZDM_HOME, ORACLE_HOME, JAVA_HOME are available:
  - Use `bash -l -c 'command'` to force a login shell when executing remote scripts
  - This ensures `.bash_profile` and `.bashrc` are properly sourced
- **Pass SOURCE_HOST and TARGET_HOST to ZDM server discovery** - The orchestration script MUST pass the source and target hostnames as environment variables when running the ZDM server discovery script, so connectivity tests work correctly:
  ```bash
  # When running server discovery, pass the hostnames for connectivity testing
  ssh $SSH_OPTS -i "$key_path" "${ZDM_ADMIN_USER}@${ZDM_HOST}" \
      "SOURCE_HOST='$SOURCE_HOST' TARGET_HOST='$TARGET_HOST' ZDM_USER='$ZDM_USER' bash -l -s" < "$script_path"
  ```
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

> **⚠️ CRITICAL: Unix Line Endings (LF only)**
> 
> All generated shell scripts **MUST** use Unix-style line endings (LF - `\n`) and NOT Windows-style (CRLF - `\r\n`).
> 
> Windows CRLF line endings will cause script execution failures on Linux with errors like:
> ```
> bash: line 359: ssh_port_22:: command not found
> bash: line 360: syntax error near unexpected token `}'
> ```
> 
> When creating files, ensure the tool or editor saves with LF endings. If scripts fail with syntax errors containing colons (`::`), convert line endings:
> ```bash
> # On Linux/Mac
> sed -i 's/\r$//' script.sh
> 
> # Or using dos2unix
> dos2unix script.sh
> ```

All scripts should include:
- Shebang (`#!/bin/bash`)
- **Unix line endings (LF only)** - Scripts will be executed on Linux; Windows CRLF endings cause parse errors
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
      
      # Detect ZDM_HOME using multiple methods
      if [ -z "${ZDM_HOME:-}" ]; then
          # Method 1: Get ZDM_HOME from zdmuser's environment
          # This is the most reliable method as ZDM is typically installed under zdmuser
          local zdm_user="${ZDM_USER:-zdmuser}"
          if id "$zdm_user" &>/dev/null; then
              # Try to get ZDM_HOME from zdmuser's login shell environment
              local zdm_home_from_user
              zdm_home_from_user=$(sudo -u "$zdm_user" -i bash -c 'echo $ZDM_HOME' 2>/dev/null)
              if [ -n "$zdm_home_from_user" ] && [ -d "$zdm_home_from_user" ] && [ -f "$zdm_home_from_user/bin/zdmcli" ]; then
                  export ZDM_HOME="$zdm_home_from_user"
              fi
          fi
          
          # Method 2: Check zdmuser's home directory for common ZDM paths
          if [ -z "${ZDM_HOME:-}" ]; then
              local zdm_user_home
              zdm_user_home=$(eval echo ~$zdm_user 2>/dev/null)
              if [ -n "$zdm_user_home" ]; then
                  for subdir in zdmhome zdm app/zdmhome; do
                      local candidate="$zdm_user_home/$subdir"
                      if [ -d "$candidate" ] && [ -f "$candidate/bin/zdmcli" ]; then
                          export ZDM_HOME="$candidate"
                          break
                      fi
                  done
              fi
          fi
          
          # Method 3: Check common ZDM installation locations system-wide
          if [ -z "${ZDM_HOME:-}" ]; then
              for path in /u01/app/zdmhome /u01/zdm /u01/app/zdm /opt/zdm /home/zdmuser/zdmhome /home/*/zdmhome ~/zdmhome ~/zdm "$HOME/zdmhome"; do
                  # Use sudo to check paths that may not be readable by current user
                  if sudo test -d "$path" 2>/dev/null && sudo test -f "$path/bin/zdmcli" 2>/dev/null; then
                      export ZDM_HOME="$path"
                      break
                  elif [ -d "$path" ] && [ -f "$path/bin/zdmcli" ]; then
                      export ZDM_HOME="$path"
                      break
                  fi
              done
          fi
          
          # Method 4: Search for zdmcli binary and derive ZDM_HOME
          if [ -z "${ZDM_HOME:-}" ]; then
              local zdmcli_path
              zdmcli_path=$(sudo find /u01 /opt /home -name "zdmcli" -type f 2>/dev/null | head -1)
              if [ -n "$zdmcli_path" ]; then
                  # zdmcli is in $ZDM_HOME/bin/zdmcli, so go up two levels
                  export ZDM_HOME="$(dirname "$(dirname "$zdmcli_path")")"
              fi
          fi
      fi
      
      # Detect JAVA_HOME - check ZDM's bundled JDK first
      if [ -z "${JAVA_HOME:-}" ]; then
          # Method 1: Check ZDM's bundled JDK (ZDM often includes its own JDK)
          if [ -n "${ZDM_HOME:-}" ] && [ -d "${ZDM_HOME}/jdk" ]; then
              export JAVA_HOME="${ZDM_HOME}/jdk"
          fi
          
          # Method 2: Check alternatives
          if [ -z "${JAVA_HOME:-}" ] && command -v java >/dev/null 2>&1; then
              local java_path
              java_path=$(readlink -f "$(command -v java)" 2>/dev/null)
              if [ -n "$java_path" ]; then
                  export JAVA_HOME="${java_path%/bin/java}"
              fi
          fi
          
          # Method 3: Search common Java paths
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

Save all Step 0 outputs to: `Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/Step0/`

**IMPORTANT:** Step 0 should ONLY create files in the `Step0/` directory. Do NOT create Step1/ or Step2/ folders - those will be created by their respective prompts.

The Step 0 directory structure should be:
```
Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/
└── Step0/                                    # Step 0: Discovery Scripts (CREATE THIS ONLY)
    ├── Scripts/                              # Discovery scripts
    │   ├── zdm_source_discovery.sh
    │   ├── zdm_target_discovery.sh
    │   ├── zdm_server_discovery.sh
    │   ├── zdm_orchestrate_discovery.sh
    │   └── README.md
    └── Discovery/                            # Discovery output files (created after script execution)
        ├── source/
        ├── target/
        └── server/
```

For reference, the complete migration folder structure (created across all steps) is:
```
Artifacts/Phase10-Migration/ZDM/<DATABASE_NAME>/
├── Step0/    # Created by Step0 prompt (this prompt)
├── Step1/    # Created by Step1 prompt (Discovery Questionnaire)
└── Step2/    # Created by Step2 prompt (Migration Artifacts)
After generating discovery scripts:
1. Copy discovery scripts to respective servers
2. Execute scripts to gather discovery information
3. Collect output files to `Step0/Discovery/`
4. Proceed to **Step 1: Discovery Questionnaire** to complete the full questionnaire with discovery data and business decisions
