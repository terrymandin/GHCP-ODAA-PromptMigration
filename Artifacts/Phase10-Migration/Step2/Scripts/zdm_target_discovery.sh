#!/bin/bash

set -u

# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration

TARGET_HOST="${TARGET_HOST:-10.200.0.250}"
TARGET_ADMIN_USER="${TARGET_ADMIN_USER:-opc}"
ORACLE_USER="${ORACLE_USER:-oracle}"
TARGET_SSH_KEY="${TARGET_SSH_KEY:-}"

TARGET_REMOTE_ORACLE_HOME="${TARGET_REMOTE_ORACLE_HOME:-/u02/app/oracle/product/19.0.0.0/dbhome_1}"
TARGET_ORACLE_SID="${TARGET_ORACLE_SID:-POCAKV1}"
TARGET_DATABASE_UNIQUE_NAME="${TARGET_DATABASE_UNIQUE_NAME:-POCAKV_ODAA}"

WARNINGS_NL=""
warning_count=0

add_warning() {
  local message="$1"
  warning_count=$((warning_count + 1))
  WARNINGS_NL+="$message"$'\n'
  echo "[WARN] $message" >&2
}

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

is_placeholder() {
  [[ "$1" == *"<"*">"* ]]
}

normalize_optional_key() {
  local raw="${1:-}"
  if [ -z "$raw" ]; then
    echo ""
    return 0
  fi
  if is_placeholder "$raw"; then
    echo ""
    return 0
  fi
  if [[ "$raw" == ~/* ]]; then
    echo "${HOME}/${raw#~/}"
    return 0
  fi
  echo "$raw"
}

detected_oracle_home=""
detected_oracle_sid=""

detect_oracle_env() {
  # 1) Existing environment variables
  detected_oracle_home="${ORACLE_HOME:-}"
  detected_oracle_sid="${ORACLE_SID:-}"

  # 2) /etc/oratab
  if [ -z "$detected_oracle_sid" ] && [ -r /etc/oratab ]; then
    detected_oracle_sid="$(awk -F: '!/^#/ && NF>=2 && $1 != "" && $1 != "*" {print $1; exit}' /etc/oratab)"
  fi
  if [ -z "$detected_oracle_home" ] && [ -n "$detected_oracle_sid" ] && [ -r /etc/oratab ]; then
    detected_oracle_home="$(awk -F: -v sid="$detected_oracle_sid" '!/^#/ && $1==sid {print $2; exit}' /etc/oratab)"
  fi

  # 3) PMON process detection (ora_pmon_*)
  if [ -z "$detected_oracle_sid" ]; then
    detected_oracle_sid="$(ps -ef 2>/dev/null | awk -F'ora_pmon_' '/ora_pmon_/ {print $2; exit}' | awk '{print $1}')"
  fi

  # 4) Common Oracle home paths
  if [ -z "$detected_oracle_home" ]; then
    for candidate in \
      /u01/app/oracle/product/*/dbhome_* \
      /u02/app/oracle/product/*/dbhome_* \
      /opt/oracle/product/*/dbhome_*; do
      if [ -d "$candidate" ]; then
        detected_oracle_home="$candidate"
        break
      fi
    done
  fi

  # 5) oraenv/coraenv
  if [ -z "$detected_oracle_home" ] && [ -n "$detected_oracle_sid" ]; then
    local env_home
    env_home="$(ORACLE_SID="$detected_oracle_sid" ORAENV_ASK=NO bash -lc '. oraenv >/dev/null 2>&1; echo "$ORACLE_HOME"' 2>/dev/null | tail -n1)"
    if [ -n "$env_home" ]; then
      detected_oracle_home="$env_home"
    fi
  fi

  if [ -z "$detected_oracle_home" ] && [ -n "$TARGET_REMOTE_ORACLE_HOME" ]; then
    detected_oracle_home="$TARGET_REMOTE_ORACLE_HOME"
    add_warning "Could not auto-detect ORACLE_HOME; using configured TARGET_REMOTE_ORACLE_HOME."
  fi

  if [ -z "$detected_oracle_sid" ] && [ -n "$TARGET_ORACLE_SID" ]; then
    detected_oracle_sid="$TARGET_ORACLE_SID"
    add_warning "Could not auto-detect ORACLE_SID; using configured TARGET_ORACLE_SID."
  fi
}

run_sql_block() {
  local sql_input="$1"

  if [ -z "$detected_oracle_home" ] || [ -z "$detected_oracle_sid" ]; then
    add_warning "Skipping SQL checks because ORACLE_HOME or ORACLE_SID is unset."
    return 1
  fi

  printf '%s\n' "$sql_input" | sudo -u "$ORACLE_USER" bash -lc "export ORACLE_HOME='$detected_oracle_home'; export ORACLE_SID='$detected_oracle_sid'; export PATH=\"\$ORACLE_HOME/bin:\$PATH\"; sqlplus -s '/ as sysdba'" 2>&1
}

render_warning_array_json() {
  if [ "$warning_count" -eq 0 ]; then
    echo "[]"
    return 0
  fi

  local first=1
  local out="["
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    if [ $first -eq 0 ]; then
      out+=","
    fi
    out+="\"$(json_escape "$line")\""
    first=0
  done <<< "$WARNINGS_NL"
  out+="]"
  echo "$out"
}

hostname_short="$(hostname 2>/dev/null || echo unknown)"
timestamp="$(date +%Y%m%d-%H%M%S)"
iso_timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

raw_out="./zdm_target_discovery_${hostname_short}_${timestamp}.txt"
json_out="./zdm_target_discovery_${hostname_short}_${timestamp}.json"

target_ssh_key_norm="$(normalize_optional_key "$TARGET_SSH_KEY")"
target_key_mode="default_or_agent"
if [ -n "$target_ssh_key_norm" ]; then
  target_key_mode="explicit_key"
  if [ ! -f "$target_ssh_key_norm" ]; then
    add_warning "TARGET_SSH_KEY was provided but file does not exist on this host: $target_ssh_key_norm"
  fi
fi

detect_oracle_env

system_hostname="$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo unknown)"
os_release="$(grep -E '^(PRETTY_NAME)=' /etc/os-release 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '"' || uname -s)"
kernel_info="$(uname -r 2>/dev/null || echo unknown)"
uptime_info="$(uptime -p 2>/dev/null || uptime 2>/dev/null || echo unknown)"
current_user="$(whoami 2>/dev/null || id -un 2>/dev/null || echo unknown)"

oratab_entries="$(grep -Ev '^#|^$' /etc/oratab 2>/dev/null || true)"
pmon_sids="$(ps -ef 2>/dev/null | awk -F'ora_pmon_' '/ora_pmon_/ {print $2}' | awk '{print $1}' | paste -sd ',' - || true)"
sqlplus_version="$(sudo -u "$ORACLE_USER" bash -lc "export ORACLE_HOME='$detected_oracle_home'; export PATH=\"\$ORACLE_HOME/bin:\$PATH\"; sqlplus -v" 2>/dev/null || true)"
listener_status="$(sudo -u "$ORACLE_USER" bash -lc "export ORACLE_HOME='$detected_oracle_home'; export PATH=\"\$ORACLE_HOME/bin:\$PATH\"; lsnrctl status" 2>&1 || true)"
scan_status="$(srvctl status scan 2>&1 || true)"
grid_status="$(crsctl stat res -t 2>&1 || true)"
asm_diskgroup="$(sudo -u "$ORACLE_USER" bash -lc "export ORACLE_HOME='$detected_oracle_home'; export ORACLE_SID='+ASM'; export PATH=\"\$ORACLE_HOME/bin:\$PATH\"; sqlplus -s '/ as sysasm' <<'EOSQL'
set pages 100 lines 200 feedback off
select name, state, round(total_mb/1024) total_gb, round(free_mb/1024) free_gb from v\$asm_diskgroup;
EOSQL" 2>&1 || true)"

read -r -d '' sql_payload <<'SQLBLOCK' || true
set pages 500 lines 250 trimspool on feedback off verify off heading on
prompt === DATABASE_CONFIGURATION ===
select name, db_unique_name, database_role, open_mode, cdb from v$database;
select parameter, value from nls_database_parameters where parameter in ('NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET');
prompt === CDB_PDB_POSTURE ===
select name, open_mode from v$pdbs order by name;
prompt === TDE_STATUS ===
select wallet_type, wallet_order, status, wrl_type, wrl_parameter from v$encryption_wallet;
prompt === TARGET_STORAGE_AND_NETWORK ===
select name, value from v$parameter where name in ('db_create_file_dest','log_archive_dest_1','local_listener','remote_listener');
SQLBLOCK

sql_output="$(run_sql_block "$sql_payload" || true)"

if [ -z "$sql_output" ]; then
  add_warning "SQL output is empty. Verify oracle user access and target database state."
fi

{
  echo "ZDM Step2 Target Discovery"
  echo "Timestamp: $iso_timestamp"
  echo "Host: $system_hostname"
  echo "Current User: $current_user"
  echo "Target Host (configured): $TARGET_HOST"
  echo "Target Admin User (configured): $TARGET_ADMIN_USER"
  echo "SSH Key Mode: $target_key_mode"
  echo "Detected ORACLE_HOME: ${detected_oracle_home:-<unset>}"
  echo "Detected ORACLE_SID: ${detected_oracle_sid:-<unset>}"
  echo "Configured TARGET_DATABASE_UNIQUE_NAME: $TARGET_DATABASE_UNIQUE_NAME"
  echo "OS: $os_release"
  echo "Kernel: $kernel_info"
  echo "Uptime: $uptime_info"
  echo
  echo "=== /etc/oratab entries ==="
  echo "${oratab_entries:-<none>}"
  echo
  echo "=== PMON SIDs ==="
  echo "${pmon_sids:-<none>}"
  echo
  echo "=== sqlplus version ==="
  echo "${sqlplus_version:-<unavailable>}"
  echo
  echo "=== listener status ==="
  echo "${listener_status:-<unavailable>}"
  echo
  echo "=== SCAN status (if RAC/Exadata) ==="
  echo "${scan_status:-<unavailable>}"
  echo
  echo "=== Grid status (if RAC/Exadata) ==="
  echo "${grid_status:-<unavailable>}"
  echo
  echo "=== ASM disk groups (if available) ==="
  echo "${asm_diskgroup:-<unavailable>}"
  echo
  echo "=== OCI/Azure metadata files (sanitized listing only) ==="
  ls -la ~/.oci 2>/dev/null || echo "~/.oci not present"
  ls -la ~/.azure 2>/dev/null || echo "~/.azure not present"
  echo
  echo "=== Network security checks ==="
  (command -v ss >/dev/null 2>&1 && ss -lntp) || (command -v netstat >/dev/null 2>&1 && netstat -lntp) || echo "No ss/netstat available"
  echo
  echo "=== SQL Discovery Output ==="
  echo "$sql_output"
  echo
  echo "=== Warnings ==="
  if [ "$warning_count" -eq 0 ]; then
    echo "none"
  else
    printf '%s' "$WARNINGS_NL"
  fi
} > "$raw_out"

status="success"
if [ "$warning_count" -gt 0 ]; then
  status="partial"
fi

{
  echo "{"
  echo "  \"status\": \"$status\"," 
  echo "  \"warnings\": $(render_warning_array_json),"
  echo "  \"timestamp\": \"$(json_escape "$iso_timestamp")\"," 
  echo "  \"host\": \"$(json_escape "$system_hostname")\"," 
  echo "  \"discovery_type\": \"target\"," 
  echo "  \"target_host\": \"$(json_escape "$TARGET_HOST")\"," 
  echo "  \"target_admin_user\": \"$(json_escape "$TARGET_ADMIN_USER")\"," 
  echo "  \"ssh_key_mode\": \"$(json_escape "$target_key_mode")\"," 
  echo "  \"oracle_user\": \"$(json_escape "$ORACLE_USER")\"," 
  echo "  \"oracle_home\": \"$(json_escape "${detected_oracle_home:-}")\"," 
  echo "  \"oracle_sid\": \"$(json_escape "${detected_oracle_sid:-}")\"," 
  echo "  \"configured_db_unique_name\": \"$(json_escape "$TARGET_DATABASE_UNIQUE_NAME")\"," 
  echo "  \"raw_output_file\": \"$(json_escape "$raw_out")\""
  echo "}"
} > "$json_out"

echo "[INFO] Target discovery raw output: $raw_out"
echo "[INFO] Target discovery JSON summary: $json_out"
