#!/bin/bash
# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration

set -u
set -o pipefail

ORACLE_USER="${ORACLE_USER:-oracle}"
TARGET_REMOTE_ORACLE_HOME_DEFAULT="/u02/app/oracle/product/19.0.0.0/dbhome_1"
TARGET_ORACLE_SID_DEFAULT="POKAKV1"
TARGET_DATABASE_UNIQUE_NAME_DEFAULT="POCAKV_ODAA"

HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_TXT="./zdm_target_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
REPORT_JSON="./zdm_target_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

WARNINGS=()
FAILED_SECTIONS=()

log_header() {
  local title="$1"
  {
    echo
    echo "============================================================"
    echo "$title"
    echo "============================================================"
  } >> "$REPORT_TXT"
}

log_raw() {
  printf '%s\n' "$1" >> "$REPORT_TXT"
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\r//g; :a;N;$!ba;s/\n/\\n/g'
}

add_warning() {
  WARNINGS+=("$1")
  log_raw "[WARN] $1"
}

add_failure() {
  FAILED_SECTIONS+=("$1")
  log_raw "[ERROR] Section failed: $1"
}

run_cmd_section() {
  local section="$1"
  local cmd="$2"
  log_header "$section"
  bash -lc "$cmd" >> "$REPORT_TXT" 2>&1
  local rc=$?
  if [ $rc -ne 0 ]; then
    add_failure "$section"
  fi
}

resolve_oracle_sid() {
  if [ -n "${ORACLE_SID:-}" ]; then
    printf '%s\n' "$ORACLE_SID"
    return
  fi

  if [ -n "${TARGET_ORACLE_SID:-}" ]; then
    printf '%s\n' "$TARGET_ORACLE_SID"
    return
  fi

  if [ -n "$TARGET_ORACLE_SID_DEFAULT" ]; then
    printf '%s\n' "$TARGET_ORACLE_SID_DEFAULT"
    return
  fi

  local sid
  sid="$(awk -F: '$1 !~ /^#/ && NF >= 2 && $1 != "" && $2 != "" {print $1; exit}' /etc/oratab 2>/dev/null)"
  if [ -n "$sid" ]; then
    printf '%s\n' "$sid"
    return
  fi

  sid="$(ps -ef | grep ora_pmon_ | grep -v grep | head -n1 | sed 's/.*ora_pmon_//')"
  printf '%s\n' "$sid"
}

resolve_oracle_home() {
  if [ -n "${ORACLE_HOME:-}" ]; then
    printf '%s\n' "$ORACLE_HOME"
    return
  fi

  if [ -n "${TARGET_REMOTE_ORACLE_HOME:-}" ]; then
    printf '%s\n' "$TARGET_REMOTE_ORACLE_HOME"
    return
  fi

  if [ -n "$TARGET_REMOTE_ORACLE_HOME_DEFAULT" ]; then
    printf '%s\n' "$TARGET_REMOTE_ORACLE_HOME_DEFAULT"
    return
  fi

  local sid="${1:-}"
  local home
  if [ -n "$sid" ]; then
    home="$(awk -F: -v sid="$sid" '$1 == sid {print $2; exit}' /etc/oratab 2>/dev/null)"
    if [ -n "$home" ]; then
      printf '%s\n' "$home"
      return
    fi
  fi

  for p in /u01/app/oracle/product/*/dbhome_1 /u02/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1; do
    if [ -d "$p" ]; then
      printf '%s\n' "$p"
      return
    fi
  done

  if [ -f /usr/local/bin/oraenv ] || [ -f /usr/bin/oraenv ]; then
    home="$(ORAENV_ASK=NO ORACLE_SID="${sid:-}" . oraenv >/dev/null 2>&1; printf '%s' "${ORACLE_HOME:-}")"
    if [ -n "$home" ]; then
      printf '%s\n' "$home"
      return
    fi
  fi

  printf '%s\n' ""
}

run_sql_section() {
  local section="$1"
  local sql_text="$2"

  log_header "$section"

  if [ -z "$EFFECTIVE_ORACLE_HOME" ] || [ -z "$EFFECTIVE_ORACLE_SID" ]; then
    add_failure "$section"
    add_warning "Skipped SQL for '$section' because ORACLE_HOME/ORACLE_SID could not be resolved"
    return
  fi

  if [ ! -x "$EFFECTIVE_ORACLE_HOME/bin/sqlplus" ]; then
    add_failure "$section"
    add_warning "sqlplus not executable at $EFFECTIVE_ORACLE_HOME/bin/sqlplus"
    return
  fi

  if [ "$(whoami)" != "$ORACLE_USER" ]; then
    printf '%s\n' "$sql_text" | sudo -u "$ORACLE_USER" -E env ORACLE_HOME="$EFFECTIVE_ORACLE_HOME" ORACLE_SID="$EFFECTIVE_ORACLE_SID" PATH="$EFFECTIVE_ORACLE_HOME/bin:$PATH" "$EFFECTIVE_ORACLE_HOME/bin/sqlplus" -s / as sysdba >> "$REPORT_TXT" 2>&1
  else
    printf '%s\n' "$sql_text" | env ORACLE_HOME="$EFFECTIVE_ORACLE_HOME" ORACLE_SID="$EFFECTIVE_ORACLE_SID" PATH="$EFFECTIVE_ORACLE_HOME/bin:$PATH" "$EFFECTIVE_ORACLE_HOME/bin/sqlplus" -s / as sysdba >> "$REPORT_TXT" 2>&1
  fi

  local rc=$?
  if [ $rc -ne 0 ]; then
    add_failure "$section"
  fi
}

EFFECTIVE_ORACLE_SID="$(resolve_oracle_sid)"
EFFECTIVE_ORACLE_HOME="$(resolve_oracle_home "$EFFECTIVE_ORACLE_SID")"

{
  echo "# ZDM Target Discovery Report"
  echo "# Host: $HOSTNAME_SHORT"
  echo "# Timestamp: $TIMESTAMP"
  echo "# Oracle user: $ORACLE_USER"
  echo "# Resolved ORACLE_SID: ${EFFECTIVE_ORACLE_SID:-<unset>}"
  echo "# Resolved ORACLE_HOME: ${EFFECTIVE_ORACLE_HOME:-<unset>}"
  echo "# Target DB Unique Name (rendered): $TARGET_DATABASE_UNIQUE_NAME_DEFAULT"
} > "$REPORT_TXT"

if [ -z "$EFFECTIVE_ORACLE_SID" ]; then
  add_warning "ORACLE_SID could not be resolved"
fi
if [ -z "$EFFECTIVE_ORACLE_HOME" ]; then
  add_warning "ORACLE_HOME could not be resolved"
fi

run_cmd_section "OS - Host, IP, OS version" "hostname -f; ip -o -4 addr show; cat /etc/os-release"
run_cmd_section "Oracle Environment" "echo ORACLE_HOME=${EFFECTIVE_ORACLE_HOME:-}; echo ORACLE_SID=${EFFECTIVE_ORACLE_SID:-}; if [ -n '$EFFECTIVE_ORACLE_HOME' ]; then '$EFFECTIVE_ORACLE_HOME/bin/sqlplus' -v 2>/dev/null; fi"
run_cmd_section "Network files and listeners" "if [ -n '$EFFECTIVE_ORACLE_HOME' ]; then lsnrctl status; srvctl status scan_listener 2>/dev/null; cat '$EFFECTIVE_ORACLE_HOME/network/admin/tnsnames.ora' 2>/dev/null; fi"
run_cmd_section "Storage - ASM and Exadata indicators" "asmcmd lsdg 2>/dev/null; cellcli -e list griddisk attributes name,asmmodestatus,size,freespace 2>/dev/null; cellcli -e list celldisk attributes name,size,freespace 2>/dev/null"
run_cmd_section "Integration metadata" "[ -f ~/.oci/config ] && sed -E 's#(key_file|fingerprint|tenancy|user|pass_phrase) *=.*#\\1 = ***MASKED***#g' ~/.oci/config || true; curl -s --max-time 2 -H Metadata:true 'http://169.254.169.254/metadata/instance?api-version=2021-02-01' || true"
run_cmd_section "Grid infrastructure and firewall" "crsctl check crs 2>/dev/null; crsctl stat res -t 2>/dev/null; iptables -S 2>/dev/null; firewall-cmd --list-all 2>/dev/null"

run_sql_section "Database configuration" "set pages 200 lines 300
col name format a20
col db_unique_name format a30
select name, db_unique_name, database_role, open_mode, cdb from v\$database;
select parameter, value from nls_database_parameters where parameter in ('NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET');
exit"

run_sql_section "Container database details" "set pages 200 lines 300
select name, open_mode from v\$pdbs;
exit"

run_sql_section "TDE wallet status" "set pages 200 lines 300
select wallet_type, status, wallet_order, con_id from v\$encryption_wallet;
exit"

STATUS="success"
if [ ${#FAILED_SECTIONS[@]} -gt 0 ] || [ ${#WARNINGS[@]} -gt 0 ]; then
  STATUS="partial"
fi

{
  echo "{"
  echo "  \"status\": \"$(json_escape "$STATUS")\"," 
  echo "  \"host\": \"$(json_escape "$HOSTNAME_SHORT")\"," 
  echo "  \"timestamp\": \"$(json_escape "$TIMESTAMP")\"," 
  echo "  \"oracle_sid\": \"$(json_escape "$EFFECTIVE_ORACLE_SID")\"," 
  echo "  \"oracle_home\": \"$(json_escape "$EFFECTIVE_ORACLE_HOME")\"," 
  echo "  \"warnings\": ["
  if [ ${#WARNINGS[@]} -gt 0 ]; then
    for i in "${!WARNINGS[@]}"; do
      comma=","
      if [ "$i" -eq "$(( ${#WARNINGS[@]} - 1 ))" ]; then
        comma=""
      fi
      echo "    \"$(json_escape "${WARNINGS[$i]}")\"$comma"
    done
  fi
  echo "  ],"
  echo "  \"failed_sections\": ["
  if [ ${#FAILED_SECTIONS[@]} -gt 0 ]; then
    for i in "${!FAILED_SECTIONS[@]}"; do
      comma=","
      if [ "$i" -eq "$(( ${#FAILED_SECTIONS[@]} - 1 ))" ]; then
        comma=""
      fi
      echo "    \"$(json_escape "${FAILED_SECTIONS[$i]}")\"$comma"
    done
  fi
  echo "  ]"
  echo "}"
} > "$REPORT_JSON"

echo "Text report: $REPORT_TXT"
echo "JSON report: $REPORT_JSON"

exit 0
