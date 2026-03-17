---
agent: agent
description: ZDM Step 2 - Generate read-only database discovery scripts
---
# ZDM Migration Step 2: Generate Discovery Scripts

## Purpose

Generate four bash scripts that gather technical context from the source database server, target
Oracle Database@Azure server, and ZDM server. These outputs form the foundation for all subsequent
migration steps.

## Execution Boundary (Critical)

This prompt is generation-only.
- Generate Step2 scripts and placeholder output directories under `Artifacts/Phase10-Migration/Step2/`
- Do not execute SSH, SCP, SQL, or discovery commands from VS Code
- Do not generate discovery output `.txt`/`.json` files during prompt execution
- Discovery output files are created only when the generated scripts are run on the jumpbox/ZDM server
- Any wording below that says a script "runs", "copies", or "executes" describes runtime behavior of the generated script after handoff, not actions to perform during prompt execution

Attach `zdm-env.md` to this prompt to supply hostnames, SSH users, key paths, and optional
overrides for your specific environment.

`zdm-env.md` is used only while generating artifacts in VS Code. Generated scripts must be standalone and must not read, source, parse, or otherwise depend on `zdm-env.md` (or any repo-local config file) at runtime on the jumpbox/ZDM server.

DB-specific value scope for Step 1-5 prompts:
- `SOURCE_REMOTE_ORACLE_HOME`
- `SOURCE_ORACLE_SID`
- `TARGET_REMOTE_ORACLE_HOME`
- `TARGET_ORACLE_SID`
- `SOURCE_DATABASE_UNIQUE_NAME`
- `TARGET_DATABASE_UNIQUE_NAME`

ZDM-specific value scope for Step 1-5 prompts:
- `ZDM_HOME`

---

## Read-Only Constraint

All generated scripts **must be strictly read-only**. They must never modify the source database,
target database, ZDM server, or any OS configuration.

- SQL: `SELECT` statements only; connect as `/ as sysdba`; no DDL, DML, or `ALTER SYSTEM/DATABASE`
- OS: `cat`, `ls`, `grep`, `ps`, status commands only; no `chmod`, `chown`, `sed -i`, package installs
- Services: `lsnrctl status`, `zdmservice status` (read-only); no start/stop
- Output: write discovery report files only to the designated output directory

Add this comment at the top of each generated script:
```
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration
```

---

## SSH Authentication Model

Scripts SSH as an admin user (not `oracle` directly), then run SQL via `sudo -u oracle`:

- Source server: SSH as `SOURCE_ADMIN_USER`  `sudo -u oracle` for SQL
- Target server: SSH as `TARGET_ADMIN_USER`  `sudo -u oracle` for SQL
- ZDM server: runs locally as `zdmuser`  no SSH needed

---

## Scripts to Generate

### 1. `zdm_source_discovery.sh`  Source Database Server

Generated script runtime behavior (when user runs orchestrator on jumpbox/ZDM server):
- Execute via SSH as `SOURCE_ADMIN_USER`; SQL runs as `oracle` user via `sudo -u oracle`
- Collect:

**OS**
- Hostname, IP addresses, OS version, disk space

**Oracle Environment**
- ORACLE_HOME, ORACLE_SID, ORACLE_BASE, Oracle version

**Database Configuration**
- Database name, unique name, DBID, role, open mode, character set / national character set
- Log mode (ARCHIVELOG/NOARCHIVELOG), force logging, supplemental logging (min, PK, UI, FK, ALL)

**Container Database**
- CDB status; PDB names and open mode (if CDB)

**TDE**
- TDE enabled status, wallet type and location, encrypted tablespaces

**Tablespaces**
- Autoextend settings (ON/OFF, MAXSIZE, increment size) for all data files; current vs max size

**Redo / Archive**
- Redo log groups, sizes, members; archive log destinations

**Network**
- Listener status, `tnsnames.ora`, `sqlnet.ora` contents

**Authentication**
- Password file location; SSH directory contents

**Schema Information**
- Schema sizes (non-system schemas > 100 MB); invalid object counts by owner/type

**Backup Configuration**
- RMAN schedule (crontab + DBMS_SCHEDULER backup jobs), retention policy, archivelog deletion policy
- Last successful backup timestamp and location (disk / tape / OSS)

**Database Links**
- All public and private database links (owner, name, host, username)

**Materialized Views**
- Names, owner, refresh type/mode, next refresh time; materialized view logs present

**Scheduler Jobs**
- All DBMS_SCHEDULER jobs (owner, name, type, schedule, enabled, last/next run)
- Flag jobs referencing external hostnames, file paths, or credentials that may need post-migration changes

**Data Guard**
- Current DG configuration parameters (if applicable)

---

### 2. `zdm_target_discovery.sh`  Target Oracle Database@Azure

Generated script runtime behavior (when user runs orchestrator on jumpbox/ZDM server):
- Execute via SSH as `TARGET_ADMIN_USER`; SQL runs as `oracle` user via `sudo -u oracle`
- Collect:

**OS**
- Hostname, IP addresses, OS version

**Oracle Environment**
- ORACLE_HOME, ORACLE_SID, Oracle version

**Database Configuration**
- Database name, unique name, role, open mode, character set

**Container Database**
- CDB status; all PDB names and open mode; any PDB pre-created for this migration

**TDE**
- Wallet status and type

**Storage**
- ASM disk groups: name, total size, free space, redundancy type
- Cell disk and grid disk free space (if Exadata, via `asmcmd` or `cellcli`)

**Network**
- Listener status, SCAN listener (if RAC), `tnsnames.ora` contents

**OCI/Azure Integration**
- OCI config file location and profile metadata (masked/sanitized)
- Instance metadata (OCI and Azure)

**Grid Infrastructure**
- CRS status (if RAC/Exadata)

**Network Security**
- `iptables` / `firewalld` rules affecting Oracle listener ports (22, 1521, 2484)
- OCI/Azure NSG references if metadata is available from host context

---

### 3. `zdm_server_discovery.sh`  ZDM Server

Generated script runtime behavior (when user runs orchestrator on jumpbox/ZDM server):
- Runs **locally on the ZDM box** as `zdmuser`
- Called by the orchestration script, which runs as `zdmuser`, so it always executes as `zdmuser`

**User guard  add near the top and exit immediately if check fails:**
```bash
CURRENT_USER="$(whoami)"
if [ "$CURRENT_USER" != "${ZDM_USER:-zdmuser}" ]; then
    echo "[ERROR] This script must run as '${ZDM_USER:-zdmuser}'. Currently running as '${CURRENT_USER}'."
    echo "        Switch to the correct user first: sudo su - ${ZDM_USER:-zdmuser}"
    exit 1
fi
```

Because the script always runs as `zdmuser`, call all ZDM commands and access all ZDM files
**directly  never use `sudo`** for ZDM paths.

Collect:

**OS**
- Hostname, current user, OS version
- Disk space on all mount points  warn if any filesystem has < 50 GB free

**ZDM Installation**
- ZDM_HOME location (detect from login environment, common home paths, common system paths, or `find`)
- ZDM version  try in order: Oracle Inventory XML, OPatch lspatches, version.txt files,
  zdmbase build files, derive major version from ZDM_HOME path
- `zdmcli` existence and executability (do NOT use `zdmcli -version`  it is invalid)
- ZDM service status (`zdmservice status`)
- Active migration jobs (`zdmcli query job`)
- Response file templates in `$ZDM_HOME/rhp/zdm/template/`

**Java**
- Java version and JAVA_HOME (check ZDM bundled JDK at `$ZDM_HOME/jdk` first)

**OCI Authentication Configuration**
- Config file location and masked contents, configured profiles/regions
- API key file existence and file permissions

**SSH / Credentials**
- SSH keys in `~/.ssh/`; credential/password files in zdmuser's home

**Network**
- IP addresses, routing table, DNS configuration

**Connectivity Tests** (only if env vars are provided)
- `SOURCE_HOST` and `TARGET_HOST` are **passed by the orchestration script** as environment variables
- Ping each host with `ping -c 10`; report min/avg/max RTT  warn if avg RTT > 10 ms
- Port tests for 22 and 1521 on each host using `/dev/tcp`
- Skip gracefully if the env vars are not set

---

### 4. `zdm_orchestrate_discovery.sh`  Master Orchestration Script

Generated script runtime behavior (when user runs it manually on the ZDM box as `zdmuser`):
- Copies and executes the three discovery scripts
- Collects results into the output directory

**Environment Variables (with defaults):**
```bash
SOURCE_HOST="${SOURCE_HOST:-}"
TARGET_HOST="${TARGET_HOST:-}"
SOURCE_ADMIN_USER="${SOURCE_ADMIN_USER:-azureuser}"
TARGET_ADMIN_USER="${TARGET_ADMIN_USER:-azureuser}"
ORACLE_USER="${ORACLE_USER:-oracle}"
ZDM_USER="${ZDM_USER:-zdmuser}"
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-}"   # empty or <...> placeholder = use SSH agent / default key
TARGET_SSH_KEY="${TARGET_SSH_KEY:-}"   # empty or <...> placeholder = use SSH agent / default key

is_placeholder() { [[ "$1" == *"<"*">"* ]]; }
[ -n "$SOURCE_SSH_KEY" ] && is_placeholder "$SOURCE_SSH_KEY" && SOURCE_SSH_KEY=""
[ -n "$TARGET_SSH_KEY" ] && is_placeholder "$TARGET_SSH_KEY" && TARGET_SSH_KEY=""
```

**SSH key rule**  only include `-i` when the normalized key variable is non-empty (placeholders like `<...>` must be treated as empty):
```bash
ssh $SSH_OPTS ${SOURCE_SSH_KEY:+-i "$SOURCE_SSH_KEY"} "${SOURCE_ADMIN_USER}@${SOURCE_HOST}" ...
scp $SCP_OPTS ${SOURCE_SSH_KEY:+-i "$SOURCE_SSH_KEY"} "$script" "${SOURCE_ADMIN_USER}@${SOURCE_HOST}:$remote_dir/"
```

**Remote execution**  use a login shell so `.bash_profile` is sourced (ensuring ORACLE_HOME,
ZDM_HOME, etc. are available). Prepend `cd` to the script content so the working directory is
correct after profile sourcing (which may contain `cd` commands that change cwd):
```bash
ssh $SSH_OPTS ${key_path:+-i "$key_path"} "${admin_user}@${host}" \
    "mkdir -p $remote_dir && bash -l -s" \
    < <(echo "cd '$remote_dir'" ; cat "$script_path")
```

Apply this pattern to all three discovery scripts (source, target, server).

**Pass hostnames to ZDM server discovery** so connectivity tests work:
```bash
SOURCE_HOST="$SOURCE_HOST" TARGET_HOST="$TARGET_HOST" ZDM_USER="$ZDM_USER" bash "$script_path"
```

**Startup diagnostic**  before attempting any connections, log:
1. Current user and home directory (warn if not `zdmuser`)
2. `.pem` and `.key` files found in `~/.ssh/` (warn if none found)
3. For each SSH key variable: if empty or placeholder (`<...>`), note that SSH agent/default key will be used;
  if non-empty after placeholder normalization, resolve the path and report whether the file exists or is missing

**Resilience requirements:**
- Continue if one server fails  track which servers succeeded/failed and report at the end
- Never suppress SSH/SCP errors (`2>/dev/null`); capture stderr and log it on failure
- After the remote script finishes, SSH back and list the temp directory contents before SCP
  to confirm output files were created
- Do NOT define or call `log_raw` in the orchestration script  it is only defined inside the
  individual discovery scripts; use `log_info` for all orchestrator output
- Functions like `show_help` and `show_config` must end with `exit` and must only be called
  from the argument-parsing block  never from the main body

**CLI options:** `-h` help, `-c` config display, `-t` connectivity test only, `-v` verbose

---

## Implementation Requirements (All Scripts)

- Shebang `#!/bin/bash`; **Unix LF line endings only**  CRLF causes `syntax error near unexpected token`
  on Linux. If scripts fail with `::` in error messages, run `sed -i 's/\r$//' script.sh`.
- **No `set -e`**  wrap each section individually so one failure does not abort the rest of the script
- **Auto-detect ORACLE_HOME and ORACLE_SID** using in priority order:
  1. Already-set environment variable
  2. Parse `/etc/oratab`
  3. Running `pmon` process (`ps -ef | grep ora_pmon_`)
  4. Common paths (`/u01/app/oracle/product/*/dbhome_1`, etc.)
  5. `oraenv` / `coraenv`
  Accept explicit environment variable overrides as highest-priority fallback
- **SQL execution**  run as `oracle` user; use `sudo -u oracle -E ORACLE_HOME=... ORACLE_SID=...`
  if `$(whoami)`  `$ORACLE_USER`
- **Output files**  write to current working directory:
  - `./zdm_<type>_discovery_<hostname>_<timestamp>.txt`  human-readable report
  - `./zdm_<type>_discovery_<hostname>_<timestamp>.json`  machine-parseable summary
- Each JSON summary must include a top-level `status` field (`"success"` or `"partial"`) and a
  `warnings` array listing any conditions that need attention before migration
- Runtime independence: scripts must not read `zdm-env.md`; all required values must come from rendered constants and/or explicit environment variables exported before execution

---

## Output Location

Save generated scripts to: `Artifacts/Phase10-Migration/Step2/Scripts/`

Create placeholder directories for discovery output:
```
Artifacts/Phase10-Migration/Step2/Discovery/source/
Artifacts/Phase10-Migration/Step2/Discovery/target/
Artifacts/Phase10-Migration/Step2/Discovery/server/
```

Also create `Artifacts/Phase10-Migration/Step2/Scripts/README.md` explaining:
- Prerequisites (zdmuser account, SSH keys in place, OCI config available for ZDM if required)
- How to set required environment variables (`SOURCE_HOST`, `TARGET_HOST`, SSH users, SSH keys)
- How to run: `bash zdm_orchestrate_discovery.sh`
- Where to find output files and what to do next (Step 3)
- That `zdm-env.md` is generation input only and is not required on the ZDM server at runtime

After generation, stop. Do not run scripts from VS Code or the local workspace. Commit and push Step2 artifacts to GitHub, then clone/pull the repository on the jumpbox/ZDM server and run from that repo clone when ready.

> **Note:** Only create files under `Step2/`. Directories for Step3 and Step4 are created by
> their respective prompts.