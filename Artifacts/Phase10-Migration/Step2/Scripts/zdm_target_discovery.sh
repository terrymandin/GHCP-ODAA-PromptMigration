#!/bin/bash
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration

set -u

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
HOSTNAME_SAFE="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)"
RAW_OUT="./zdm_target_discovery_${HOSTNAME_SAFE}_${TIMESTAMP}.txt"
JSON_OUT="./zdm_target_discovery_${HOSTNAME_SAFE}_${TIMESTAMP}.json"

TARGET_HOST="${TARGET_HOST:-}"
TARGET_ADMIN_USER="${TARGET_ADMIN_USER:-${TARGET_SSH_USER:-opc}}"
TARGET_SSH_KEY="${TARGET_SSH_KEY:-}"
ORACLE_USER="${ORACLE_USER:-oracle}"
TARGET_REMOTE_ORACLE_HOME="${TARGET_REMOTE_ORACLE_HOME:-/u02/app/oracle/product/19.0.0.0/dbhome_1}"
TARGET_ORACLE_SID="${TARGET_ORACLE_SID:-POCAKV1}"
TARGET_DATABASE_UNIQUE_NAME="${TARGET_DATABASE_UNIQUE_NAME:-POCAKV_ODAA}"

WARNINGS=()
SECTION_FAILS=0

is_placeholder() { [[ "$1" == *"<"*">"* ]]; }
[ -n "$TARGET_SSH_KEY" ] && is_placeholder "$TARGET_SSH_KEY" && TARGET_SSH_KEY=""

log() { printf '%s\n' "$*" | tee -a "$RAW_OUT"; }
warn() {
  WARNINGS+=("$*")
  printf '[WARN] %s\n' "$*" | tee -a "$RAW_OUT"
}
section() { log ""; log "==== $* ===="; }

run_cmd() {
  local label="$1"
  shift
  log "[CMD] $label"
  if "$@" >>"$RAW_OUT" 2>&1; then
    return 0
  fi
  warn "Command failed: $label"
  SECTION_FAILS=$((SECTION_FAILS + 1))
  return 1
}

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/ }"
  printf '%s' "$s"
}

find_oracle_sid() {
  if [ -n "${ORACLE_SID:-}" ]; then
    printf '%s' "$ORACLE_SID"
    return 0
  fi
  if [ -n "$TARGET_ORACLE_SID" ] && ! is_placeholder "$TARGET_ORACLE_SID"; then
    printf '%s' "$TARGET_ORACLE_SID"
    return 0
  fi

  local sid
  sid="$(awk -F: '$1 !~ /^#/ && $1 != "" { print $1; exit }' /etc/oratab 2>/dev/null)"
  if [ -n "$sid" ]; then
    printf '%s' "$sid"
    return 0
  fi

  sid="$(ps -ef 2>/dev/null | awk '/ora_pmon_/ && !/awk/ { sub(/^.*ora_pmon_/, "", $NF); print $NF; exit }')"
  printf '%s' "$sid"
}

find_oracle_home() {
  local sid="$1"

  if [ -n "${ORACLE_HOME:-}" ] && [ -x "${ORACLE_HOME}/bin/sqlplus" ]; then
    printf '%s' "$ORACLE_HOME"
    return 0
  fi

  local from_oratab
  from_oratab="$(awk -F: -v sid="$sid" 'sid=="" || $1==sid { if ($2!="" && $2!="*") { print $2; exit } }' /etc/oratab 2>/dev/null)"
  if [ -n "$from_oratab" ] && [ -x "$from_oratab/bin/sqlplus" ]; then
    printf '%s' "$from_oratab"
    return 0
  fi

  local pmon_sid
  pmon_sid="$(ps -ef 2>/dev/null | awk '/ora_pmon_/ && !/awk/ { sub(/^.*ora_pmon_/, "", $NF); print $NF; exit }')"
  if [ -n "$pmon_sid" ]; then
    from_oratab="$(awk -F: -v sid="$pmon_sid" '$1==sid { if ($2!="" && $2!="*") { print $2; exit } }' /etc/oratab 2>/dev/null)"
    if [ -n "$from_oratab" ] && [ -x "$from_oratab/bin/sqlplus" ]; then
      printf '%s' "$from_oratab"
      return 0
    fi
  fi

  for p in \
    "$TARGET_REMOTE_ORACLE_HOME" \
    /u02/app/oracle/product/19.0.0.0/dbhome_1 \
    /u01/app/oracle/product/19.0.0/dbhome_1 \
    /u01/app/oracle/product/21.0.0/dbhome_1 \
    /opt/oracle/product/19c/dbhome_1
  do
    if [ -n "$p" ] && [ -x "$p/bin/sqlplus" ]; then
      printf '%s' "$p"
      return 0
    fi
  done

  if command -v oraenv >/dev/null 2>&1; then
    printf '%s' "$(ORAENV_ASK=NO ORACLE_SID="$sid" . oraenv >/dev/null 2>&1; printf '%s' "${ORACLE_HOME:-}")"
    return 0
  fi
  if command -v coraenv >/dev/null 2>&1; then
    printf '%s' "$(ORAENV_ASK=NO ORACLE_SID="$sid" . coraenv >/dev/null 2>&1; printf '%s' "${ORACLE_HOME:-}")"
    return 0
  fi

  printf ''
}

run_sql() {
  local label="$1"
  local sql_text="$2"
  local oh="$3"
  local sid="$4"

  log "[SQL] $label"
  if [ -z "$oh" ] || [ -z "$sid" ] || [ ! -x "$oh/bin/sqlplus" ]; then
    warn "Skipping SQL section '$label' (ORACLE_HOME/ORACLE_SID/sqlplus unresolved)"
    SECTION_FAILS=$((SECTION_FAILS + 1))
    return 1
  fi

  if ! printf '%s\n' "$sql_text" | sudo -u "$ORACLE_USER" env ORACLE_HOME="$oh" ORACLE_SID="$sid" PATH="$oh/bin:$PATH" bash -lc '
set -u
cat | "$ORACLE_HOME/bin/sqlplus" -s / as sysdba
' >>"$RAW_OUT" 2>&1; then
    warn "SQL section failed: $label"
    SECTION_FAILS=$((SECTION_FAILS + 1))
    return 1
  fi

  return 0
}

write_json_summary() {
  local status="success"
  if [ "$SECTION_FAILS" -gt 0 ]; then
    status="partial"
  fi

  {
    printf '{\n'
    printf '  "status": "%s",\n' "$status"
    printf '  "type": "target",\n'
    printf '  "host": "%s",\n' "$(json_escape "$HOSTNAME_SAFE")"
    printf '  "timestamp": "%s",\n' "$TIMESTAMP"
    printf '  "raw_output": "%s",\n' "$(json_escape "$RAW_OUT")"
    printf '  "warnings": ['
    if [ "${#WARNINGS[@]}" -gt 0 ]; then
      printf '\n'
      local i
      for i in "${!WARNINGS[@]}"; do
        printf '    "%s"' "$(json_escape "${WARNINGS[$i]}")"
        if [ "$i" -lt $(( ${#WARNINGS[@]} - 1 )) ]; then
          printf ','
        fi
        printf '\n'
      done
      printf '  '
    fi
    printf ']\n'
    printf '}\n'
  } >"$JSON_OUT"
}

main() {
  : >"$RAW_OUT"

  section "Connectivity and auth context"
  log "target_host=${TARGET_HOST:-unset}"
  log "target_admin_user=$TARGET_ADMIN_USER"
  log "target_ssh_key_mode=$([ -n "$TARGET_SSH_KEY" ] && echo explicit || echo default-agent)"

  section "Remote system details"
  run_cmd "hostname" hostname
  run_cmd "uname" uname -a
  run_cmd "uptime" uptime
  run_cmd "os-release" bash -lc 'if [ -f /etc/os-release ]; then cat /etc/os-release; else echo /etc/os-release not found; fi'

  local sid
  local oh
  sid="$(find_oracle_sid)"
  oh="$(find_oracle_home "$sid")"

  section "Oracle environment details"
  log "oracle_sid=$sid"
  log "oracle_home=$oh"
  log "database_unique_name_config=$TARGET_DATABASE_UNIQUE_NAME"
  run_cmd "/etc/oratab" bash -lc 'if [ -f /etc/oratab ]; then grep -v "^#" /etc/oratab; else echo /etc/oratab not found; fi'
  run_cmd "PMON" bash -lc 'ps -ef | awk "/ora_pmon_/ && !/awk/ {print \$NF}"'
  run_cmd "sqlplus version" bash -lc 'if [ -x "'"$oh"'"/bin/sqlplus" ]; then "'"$oh"'"/bin/sqlplus -v; else echo sqlplus-not-found; fi'

  section "Database core configuration"
  run_sql "db identity and mode" "set pages 200 lines 300 trimspool on feedback on
select name, db_unique_name, database_role, open_mode from v\$database;
select parameter, value from nls_database_parameters where parameter in ('NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET');
" "$oh" "$sid"

  section "CDB and PDB posture"
  run_sql "cdb pdb status" "set pages 200 lines 300 trimspool on feedback on
select cdb from v\$database;
select name, open_mode from v\$pdbs;
" "$oh" "$sid"

  section "TDE wallet status"
  run_sql "wallet status" "set pages 200 lines 300 trimspool on feedback on
select wallet_type, status, wallet_order from v\$encryption_wallet;
" "$oh" "$sid"

  section "Storage posture"
  run_sql "asm diskgroups" "set pages 200 lines 300 trimspool on feedback on
select name, state, type, total_mb, free_mb from v\$asm_diskgroup order by name;
" "$oh" "$sid"
  run_cmd "cell/grid disk details" bash -lc 'if command -v cellcli >/dev/null 2>&1; then cellcli -e "list celldisk attributes name,size,status"; else echo cellcli-not-found; fi'

  section "Network posture"
  run_cmd "listener status" bash -lc 'if command -v lsnrctl >/dev/null 2>&1; then lsnrctl status; else echo lsnrctl-not-found; fi'
  run_cmd "scan listeners" bash -lc 'if command -v srvctl >/dev/null 2>&1; then srvctl config scan_listener; else echo srvctl-not-found; fi'
  run_cmd "tnsnames.ora" bash -lc 'if [ -n "'"$oh"'" ] && [ -f "'"$oh"'"/network/admin/tnsnames.ora ]; then cat "'"$oh"'"/network/admin/tnsnames.ora; else echo tnsnames.ora-not-found; fi'

  section "Cloud integration metadata"
  run_cmd "oci config metadata" bash -lc 'if [ -f ~/.oci/config ]; then sed -E "s#(key_file\s*=\s*).*#\1***#g" ~/.oci/config; else echo ~/.oci/config-not-found; fi'
  run_cmd "azure metadata" bash -lc 'if command -v az >/dev/null 2>&1; then az account show --output table; else echo az-cli-not-found; fi'

  section "Grid and security checks"
  run_cmd "grid infrastructure" bash -lc 'if command -v crsctl >/dev/null 2>&1; then crsctl check cluster; crsctl stat res -t; else echo crsctl-not-found; fi'
  run_cmd "ssh/listener ports" bash -lc 'if command -v ss >/dev/null 2>&1; then ss -tulpen | grep -E ":22|:1521|:1522" || true; else netstat -tulpen 2>/dev/null | grep -E ":22|:1521|:1522" || true; fi'

  write_json_summary
  log ""
  log "Discovery complete"
  log "raw_output=$RAW_OUT"
  log "json_output=$JSON_OUT"
}

main "$@"