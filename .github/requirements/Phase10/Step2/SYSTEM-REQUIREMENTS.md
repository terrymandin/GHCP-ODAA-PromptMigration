# Step2 System Requirements - Discovery Script Implementation

## Scope

This file defines script-level coding constraints and required implementation patterns for Step2 generation.

## S2-07: Required implementation patterns in generated script examples

These patterns must be represented explicitly in the Step2 prompt text so generated scripts remain consistent.

1. ZDM server user guard example must be present:

	```bash
	CURRENT_USER="$(whoami)"
	if [ "$CURRENT_USER" != "${ZDM_USER:-zdmuser}" ]; then
	    echo "[ERROR] This script must run as '${ZDM_USER:-zdmuser}'. Currently running as '${CURRENT_USER}'."
	    echo "        Switch to the correct user first: sudo su - ${ZDM_USER:-zdmuser}"
	    exit 1
	fi
	```

2. Orchestrator environment variable defaults and key placeholder normalization example must be present:

	```bash
	SOURCE_HOST="${SOURCE_HOST:-}"
	TARGET_HOST="${TARGET_HOST:-}"
	SOURCE_ADMIN_USER="${SOURCE_ADMIN_USER:-azureuser}"
	TARGET_ADMIN_USER="${TARGET_ADMIN_USER:-azureuser}"
	ORACLE_USER="${ORACLE_USER:-oracle}"
	ZDM_USER="${ZDM_USER:-zdmuser}"
	SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-}"
	TARGET_SSH_KEY="${TARGET_SSH_KEY:-}"

	is_placeholder() { [[ "$1" == *"<"*">"* ]]; }
	[ -n "$SOURCE_SSH_KEY" ] && is_placeholder "$SOURCE_SSH_KEY" && SOURCE_SSH_KEY=""
	[ -n "$TARGET_SSH_KEY" ] && is_placeholder "$TARGET_SSH_KEY" && TARGET_SSH_KEY=""
	```

3. Conditional `-i` SSH/SCP example must be present:

	```bash
	ssh $SSH_OPTS ${SOURCE_SSH_KEY:+-i "$SOURCE_SSH_KEY"} "${SOURCE_ADMIN_USER}@${SOURCE_HOST}" ...
	scp $SCP_OPTS ${SOURCE_SSH_KEY:+-i "$SOURCE_SSH_KEY"} "$script" "${SOURCE_ADMIN_USER}@${SOURCE_HOST}:$remote_dir/"
	```

4. Remote execution pattern must resolve the remote user's home directory via a separate SSH call before constructing `remote_dir`. The local `$HOME` must never be passed to remote SSH commands because the remote admin user (for example `azureuser`, `opc`) has a different home than the local `zdmuser`:

	```bash
	# Resolve $HOME on the remote host first — do NOT use the local $HOME here
	remote_home=$(ssh $SSH_OPTS ${key_path:+-i "$key_path"} "${admin_user}@${host}" 'echo $HOME' 2>>"$log_file")
	if [[ -z "$remote_home" ]]; then
	    log_fail "${dtype}: Could not determine remote home for ${admin_user}@${host}. Aborting."
	    printf -- 'FAIL'; return 1
	fi
	remote_dir="${remote_home}/zdm-step2-${dtype}-${timestamp}"
	ssh $SSH_OPTS ${key_path:+-i "$key_path"} "${admin_user}@${host}" \
	    "mkdir -p $remote_dir" 2>>"$log_file"
	ssh $SSH_OPTS ${key_path:+-i "$key_path"} "${admin_user}@${host}" \
	    "bash -l -s" \
	    < <(printf 'cd %q\n' "$remote_dir"; cat "$script_path")
	```

	Note: `mkdir -p` and `bash -l -s` are issued as separate SSH commands so that a `mkdir` failure is caught and reported before the script is run.

5. Orchestrator must pass endpoint values to local ZDM server discovery script:

	```bash
	SOURCE_HOST="$SOURCE_HOST" TARGET_HOST="$TARGET_HOST" ZDM_USER="$ZDM_USER" bash "$script_path"
	```

6. Orchestrator startup diagnostics must include:
	- current user and home directory,
	- `.pem`/`.key` inventory in `~/.ssh/`,
	- resolved SSH key handling mode and existence checks.

7. Orchestrator resilience and behavior requirements must include:
	- continue execution when one server fails and report per-target status,
	- never suppress SSH/SCP errors,
	- confirm remote output existence before SCP,
	- enforce shell-safe remote path handling: do not use quoted-tilde paths for runtime `cd` (for example `cd '~/dir'`), and prefer `$HOME/...` or another absolute path,
	- fail fast with explicit error if remote working-directory setup fails before artifact checks,
	- do not define/call `log_raw` in orchestrator,
	- `show_help` and `show_config` terminate with `exit` and are only called from argument parsing,
	- support CLI options `-h`, `-c`, `-t`, `-v`.

## S2-08: Required cross-script implementation constraints

1. Shebang must be `#!/bin/bash` and generated scripts must use Unix LF line endings.
2. Do not use global `set -e`; sections should fail independently so discovery continues.
3. ORACLE_HOME and ORACLE_SID auto-detection order must be documented and preserved:
	1. already-set environment variables,
	2. `/etc/oratab`,
	3. `ora_pmon_*` process detection,
	4. common Oracle home paths,
	5. `oraenv`/`coraenv`.
4. SQL execution must run as `oracle` using `sudo -u oracle` with explicit Oracle environment.
5. To prevent SP2-0310, SQL must be passed to `sqlplus` via stdin (pipe/heredoc), not temporary `@/tmp/*.sql` files.
6. Runtime output naming examples must be preserved:
	- `./zdm_<type>_discovery_<hostname>_<timestamp>.txt`
	- `./zdm_<type>_discovery_<hostname>_<timestamp>.json`
7. JSON summary output must include top-level `status` (`success` or `partial`) and `warnings` array.
