#!/bin/bash
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration

set -u
set -o pipefail

DISCOVERY_TYPE="target"
HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_TXT="./zdm_${DISCOVERY_TYPE}_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
REPORT_JSON="./zdm_${DISCOVERY_TYPE}_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"
ORACLE_USER="${ORACLE_USER:-oracle}"

TARGET_REMOTE_ORACLE_HOME="${TARGET_REMOTE_ORACLE_HOME:-}"
TARGET_ORACLE_SID="${TARGET_ORACLE_SID:-}"
TARGET_DATABASE_UNIQUE_NAME="${TARGET_DATABASE_UNIQUE_NAME:-}"

WARNINGS=()
ERRORS=()

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\r//g; :a;N;$!ba;s/\n/\\n/g'
}

append_report() {
  printf '%s\n' "$1" >> "$REPORT_TXT"
}

warn() {
  WARNINGS+=("$1")
  append_report "[WARN] $1"
}

section() {
  append_report ""
  append_report "==================== $1 ===================="
}

run_cmd() {
  local title="$1"
  local cmd="$2"
  section "$title"
  local out
  out="$(bash -lc "$cmd" 2>&1)"
  if [ $? -ne 0 ]; then
    warn "$title command failed"
  fi
  append_report "$out"
}

find_home_from_oratab() {
  awk -F: '!/^#/ && NF>=2 && $2 !~ /^$/ {print $2; exit}' /etc/oratab 2>/dev/null
}

find_sid_from_oratab() {
  awk -F: '!/^#/ && NF>=2 && $1 !~ /^$/ {print $1; exit}' /etc/oratab 2>/dev/null
}

find_sid_from_pmon() {
  ps -ef 2>/dev/null | grep ora_pmon_ | grep -v grep | head -n 1 | sed 's/.*ora_pmon_//'
}

find_home_common_paths() {
  ls -d /u01/app/oracle/product/*/dbhome_1 /u02/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1 2>/dev/null | head -n 1
}

detect_oracle_env() {
  ORACLE_HOME_DETECTED=""
  ORACLE_SID_DETECTED=""

  if [ -n "${TARGET_REMOTE_ORACLE_HOME}" ]; then
    ORACLE_HOME_DETECTED="$TARGET_REMOTE_ORACLE_HOME"
  elif [ -n "${ORACLE_HOME:-}" ]; then
    ORACLE_HOME_DETECTED="$ORACLE_HOME"
  else
    ORACLE_HOME_DETECTED="$(find_home_from_oratab)"
    [ -z "$ORACLE_HOME_DETECTED" ] && ORACLE_HOME_DETECTED="$(find_home_common_paths)"
  fi

  if [ -n "${TARGET_ORACLE_SID}" ]; then
    ORACLE_SID_DETECTED="$TARGET_ORACLE_SID"
  elif [ -n "${ORACLE_SID:-}" ]; then
    ORACLE_SID_DETECTED="$ORACLE_SID"
  else
    ORACLE_SID_DETECTED="$(find_sid_from_oratab)"
    [ -z "$ORACLE_SID_DETECTED" ] && ORACLE_SID_DETECTED="$(find_sid_from_pmon)"
  fi

  if [ -z "$ORACLE_HOME_DETECTED" ] || [ -z "$ORACLE_SID_DETECTED" ]; then
    local oraenv_sid
    oraenv_sid="${ORACLE_SID_DETECTED:-$(find_sid_from_oratab)}"
    if [ -n "$oraenv_sid" ]; then
      local oraenv_home
      oraenv_home="$(ORACLE_SID="$oraenv_sid" ORAENV_ASK=NO bash -lc '. oraenv >/dev/null 2>&1 || . coraenv >/dev/null 2>&1; echo ${ORACLE_HOME:-}' 2>/dev/null)"
      [ -z "$ORACLE_HOME_DETECTED" ] && ORACLE_HOME_DETECTED="$oraenv_home"
      [ -z "$ORACLE_SID_DETECTED" ] && ORACLE_SID_DETECTED="$oraenv_sid"
    fi
  fi

  [ -z "$ORACLE_HOME_DETECTED" ] && warn "Could not auto-detect ORACLE_HOME"
  [ -z "$ORACLE_SID_DETECTED" ] && warn "Could not auto-detect ORACLE_SID"
}

run_sql() {
  local title="$1"
  local sql="$2"
  section "$title"

  if [ -z "${ORACLE_HOME_DETECTED:-}" ] || [ -z "${ORACLE_SID_DETECTED:-}" ]; then
    warn "Skipping SQL section '$title' because ORACLE environment is incomplete"
    append_report "ORACLE_HOME='$ORACLE_HOME_DETECTED' ORACLE_SID='$ORACLE_SID_DETECTED'"
    return 1
  fi

  local sqlplus_cmd="\"${ORACLE_HOME_DETECTED}/bin/sqlplus\" -s / as sysdba"
  local payload
  payload="set pages 500 lines 300 long 50000 trimspool on verify off feedback off timing off; ${sql}; exit;"

  local output
  if [ "$(whoami)" != "$ORACLE_USER" ]; then
    output="$(printf '%s\n' "$payload" | sudo -u "$ORACLE_USER" -E ORACLE_HOME="$ORACLE_HOME_DETECTED" ORACLE_SID="$ORACLE_SID_DETECTED" PATH="$ORACLE_HOME_DETECTED/bin:$PATH" bash -lc "$sqlplus_cmd" 2>&1)"
  else
    output="$(printf '%s\n' "$payload" | ORACLE_HOME="$ORACLE_HOME_DETECTED" ORACLE_SID="$ORACLE_SID_DETECTED" PATH="$ORACLE_HOME_DETECTED/bin:$PATH" bash -lc "$sqlplus_cmd" 2>&1)"
  fi

  if [ $? -ne 0 ]; then
    warn "SQL section '$title' failed"
  fi
  append_report "$output"
}

write_json() {
  local status="success"
  if [ ${#WARNINGS[@]} -gt 0 ] || [ ${#ERRORS[@]} -gt 0 ]; then
    status="partial"
  fi

  {
    echo "{"
    echo "  \"status\": \"$(json_escape "$status")\"," 
    echo "  \"type\": \"$(json_escape "$DISCOVERY_TYPE")\"," 
    echo "  \"host\": \"$(json_escape "$HOSTNAME_SHORT")\"," 
    echo "  \"timestamp\": \"$(json_escape "$TIMESTAMP")\"," 
    echo "  \"oracle\": {"
    echo "    \"oracle_user\": \"$(json_escape "$ORACLE_USER")\"," 
    echo "    \"oracle_home\": \"$(json_escape "${ORACLE_HOME_DETECTED:-}")\"," 
    echo "    \"oracle_sid\": \"$(json_escape "${ORACLE_SID_DETECTED:-}")\"," 
    echo "    \"target_database_unique_name\": \"$(json_escape "${TARGET_DATABASE_UNIQUE_NAME:-}")\""
    echo "  },"
    echo "  \"warnings\": ["
    if [ ${#WARNINGS[@]} -gt 0 ]; then
      for i in "${!WARNINGS[@]}"; do
        comma=","
        [ "$i" -eq "$((${#WARNINGS[@]} - 1))" ] && comma=""
        echo "    \"$(json_escape "${WARNINGS[$i]}")\"${comma}"
      done
    fi
    echo "  ],"
    echo "  \"errors\": ["
    if [ ${#ERRORS[@]} -gt 0 ]; then
      for i in "${!ERRORS[@]}"; do
        comma=","
        [ "$i" -eq "$((${#ERRORS[@]} - 1))" ] && comma=""
        echo "    \"$(json_escape "${ERRORS[$i]}")\"${comma}"
      done
    fi
    echo "  ]"
    echo "}"
  } > "$REPORT_JSON"
}

append_report "# Target Discovery Report"
append_report "Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
append_report "Host: $HOSTNAME_SHORT"
append_report "Running User: $(whoami)"
append_report "Read-only mode: enabled"

detect_oracle_env

section "Resolved Oracle Environment"
append_report "ORACLE_USER=$ORACLE_USER"
append_report "ORACLE_HOME=$ORACLE_HOME_DETECTED"
append_report "ORACLE_SID=$ORACLE_SID_DETECTED"
append_report "TARGET_DATABASE_UNIQUE_NAME=${TARGET_DATABASE_UNIQUE_NAME:-}"

run_cmd "OS: Host, IP, OS" "hostname -f 2>/dev/null; ip -br addr 2>/dev/null || ip addr 2>/dev/null; cat /etc/os-release 2>/dev/null"
run_cmd "Oracle Version (binary)" "[ -n '$ORACLE_HOME_DETECTED' ] && '$ORACLE_HOME_DETECTED/bin/sqlplus' -v 2>/dev/null || echo 'sqlplus binary not found'"

run_sql "Database Configuration" "select name, db_unique_name, database_role, open_mode, log_mode from v\$database; select parameter, value from nls_database_parameters where parameter in ('NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET') order by parameter;"
run_sql "Container Database and PDBs" "select cdb from v\$database; select con_id, name, open_mode from v\$pdbs order by con_id;"
run_sql "TDE Wallet Status" "select wrl_type, wrl_parameter, status, wallet_type from v\$encryption_wallet;"
run_sql "ASM Diskgroups" "select name, type, total_mb, free_mb, usable_file_mb from v\$asm_diskgroup order by name;"
run_cmd "ASM / Exadata Storage Utilities" "asmcmd lsdg 2>/dev/null || true; cellcli -e list griddisk attributes name,size,freespace 2>/dev/null || true; cellcli -e list celldisk attributes name,size,freespace 2>/dev/null || true"
run_cmd "Network Files and Listener" "lsnrctl status 2>/dev/null; srvctl status scan_listener 2>/dev/null || true; [ -n '$ORACLE_HOME_DETECTED' ] && cat '$ORACLE_HOME_DETECTED/network/admin/tnsnames.ora' 2>/dev/null"
run_cmd "OCI Config and Profiles (masked)" "for f in ~/.oci/config /home/oracle/.oci/config; do if [ -f \"$f\" ]; then echo \"[CONFIG] $f\"; sed -E 's/(fingerprint|user|tenancy|region|key_file)[[:space:]]*=.*/\\1=***masked***/g' \"$f\"; fi; done"
run_cmd "Instance Metadata (OCI/Azure)" "curl -s -H 'Metadata:true' 'http://169.254.169.254/metadata/instance?api-version=2021-02-01' 2>/dev/null || true; curl -s -H 'Authorization: Bearer Oracle' 'http://169.254.169.254/opc/v2/instance/' 2>/dev/null || true"
run_cmd "Grid Infrastructure / CRS" "crsctl check cluster 2>/dev/null || crsctl stat res -t 2>/dev/null || true"
run_cmd "Network Security Rules" "iptables -S 2>/dev/null || true; firewall-cmd --list-all 2>/dev/null || true; ss -ltnp 2>/dev/null | egrep '(:22|:1521|:2484)' || true"

if [ -n "${TARGET_DATABASE_UNIQUE_NAME:-}" ]; then
  run_sql "Target Database Unique Name Check" "select name, db_unique_name from v\$database;"
fi

if [ ${#WARNINGS[@]} -gt 0 ]; then
  section "Warnings"
  for w in "${WARNINGS[@]}"; do
    append_report "- $w"
  done
fi

write_json

echo "Target discovery report: $REPORT_TXT"
echo "Target discovery summary: $REPORT_JSON"

exit 0
