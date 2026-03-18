#!/bin/bash

# READ-ONLY DISCOVERY SCRIPT - Makes no changes to the database or OS configuration

set -u

DISCOVERY_TYPE="target"
ORACLE_USER="${ORACLE_USER:-oracle}"
TARGET_DATABASE_UNIQUE_NAME="${TARGET_DATABASE_UNIQUE_NAME:-POCAKV_ODAA}"
TARGET_REMOTE_ORACLE_HOME="${TARGET_REMOTE_ORACLE_HOME:-/u02/app/oracle/product/19.0.0.0/dbhome_1}"
TARGET_ORACLE_SID="${TARGET_ORACLE_SID:-POCAKV1}"
TARGET_SSH_KEY="${TARGET_SSH_KEY:-}"

HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OUT_TXT="./zdm_${DISCOVERY_TYPE}_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"
OUT_JSON="./zdm_${DISCOVERY_TYPE}_discovery_${HOSTNAME_SHORT}_${TIMESTAMP}.json"

STATUS="success"
WARNINGS=()

escape_json() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

add_warning() {
  WARNINGS+=("$1")
  STATUS="partial"
}

log_section() {
  local title="$1"
  {
    echo ""
    echo "===== ${title} ====="
  } >> "$OUT_TXT"
}

run_cmd() {
  local title="$1"
  shift
  log_section "$title"
  {
    echo "$ $*"
    "$@"
  } >> "$OUT_TXT" 2>&1 || add_warning "Command failed: ${title}"
}

normalize_key_mode() {
  local key="$1"
  if [[ -z "$key" || "$key" == *"<"*">"* ]]; then
    printf '%s\n' "default_or_agent"
  else
    printf '%s\n' "explicit_key"
  fi
}

CURRENT_ORACLE_HOME=""
CURRENT_ORACLE_SID=""
DETECTION_SOURCE=""

detect_oracle_env() {
  if [[ -n "${ORACLE_HOME:-}" && -n "${ORACLE_SID:-}" ]]; then
    CURRENT_ORACLE_HOME="$ORACLE_HOME"
    CURRENT_ORACLE_SID="$ORACLE_SID"
    DETECTION_SOURCE="environment"
    return 0
  fi

  local oratab_sid=""
  local oratab_home=""
  if [[ -f /etc/oratab ]]; then
    oratab_sid="$(awk -F: '($1 !~ /^#/ && $1 != "" && $1 !~ /^\+/){print $1; exit}' /etc/oratab 2>/dev/null || true)"
    oratab_home="$(awk -F: '($1 !~ /^#/ && $1 != "" && $1 !~ /^\+/){print $2; exit}' /etc/oratab 2>/dev/null || true)"
  fi

  if [[ -n "$oratab_sid" && -n "$oratab_home" ]]; then
    CURRENT_ORACLE_SID="$oratab_sid"
    CURRENT_ORACLE_HOME="$oratab_home"
    DETECTION_SOURCE="oratab"
    return 0
  fi

  local pmon_sid
  pmon_sid="$(ps -ef 2>/dev/null | awk '/ora_pmon_/ {sub(/^.*ora_pmon_/, "", $0); print $0; exit}' || true)"
  if [[ -n "$pmon_sid" ]]; then
    CURRENT_ORACLE_SID="$pmon_sid"
    DETECTION_SOURCE="pmon"
  fi

  local homes=(
    "${TARGET_REMOTE_ORACLE_HOME}"
    "/u02/app/oracle/product/19.0.0.0/dbhome_1"
    "/u01/app/oracle/product/19.0.0/dbhome_1"
    "/opt/oracle/product/19c/dbhome_1"
  )
  local h
  for h in "${homes[@]}"; do
    if [[ -n "$h" && -x "$h/bin/sqlplus" ]]; then
      CURRENT_ORACLE_HOME="$h"
      if [[ -z "$CURRENT_ORACLE_SID" ]]; then
        CURRENT_ORACLE_SID="${TARGET_ORACLE_SID}"
      fi
      DETECTION_SOURCE="common_paths"
      break
    fi
  done

  if [[ -z "$CURRENT_ORACLE_HOME" && -n "$CURRENT_ORACLE_SID" ]]; then
    local oraenv_path=""
    oraenv_path="$(command -v oraenv 2>/dev/null || command -v coraenv 2>/dev/null || true)"
    if [[ -n "$oraenv_path" ]]; then
      CURRENT_ORACLE_HOME="$(sudo -u "$ORACLE_USER" env ORACLE_SID="$CURRENT_ORACLE_SID" ORAENV_ASK=NO bash -lc '. "$0" >/dev/null 2>&1; printf "%s" "$ORACLE_HOME"' "$oraenv_path" 2>/dev/null || true)"
      if [[ -n "$CURRENT_ORACLE_HOME" ]]; then
        DETECTION_SOURCE="oraenv"
      fi
    fi
  fi

  if [[ -z "$CURRENT_ORACLE_SID" ]]; then
    CURRENT_ORACLE_SID="$TARGET_ORACLE_SID"
  fi
  if [[ -z "$CURRENT_ORACLE_HOME" ]]; then
    CURRENT_ORACLE_HOME="$TARGET_REMOTE_ORACLE_HOME"
  fi

  if [[ ! -x "$CURRENT_ORACLE_HOME/bin/sqlplus" ]]; then
    add_warning "Unable to verify sqlplus executable at ${CURRENT_ORACLE_HOME}/bin/sqlplus"
    return 1
  fi

  return 0
}

run_sql_select() {
  local title="$1"
  local sql_body="$2"

  log_section "$title"

  if [[ -z "$CURRENT_ORACLE_HOME" || -z "$CURRENT_ORACLE_SID" ]]; then
    echo "Oracle environment not detected; skipping SQL section." >> "$OUT_TXT"
    add_warning "Skipped SQL section due to missing Oracle environment: ${title}"
    return 1
  fi

  {
    printf 'set pages 1000 lines 300 trimspool on feedback off verify off heading on\n'
    printf '%s\n' "$sql_body"
    printf 'exit\n'
  } | sudo -u "$ORACLE_USER" env ORACLE_HOME="$CURRENT_ORACLE_HOME" ORACLE_SID="$CURRENT_ORACLE_SID" PATH="$CURRENT_ORACLE_HOME/bin:$PATH" bash -lc 'sqlplus -s / as sysdba' >> "$OUT_TXT" 2>&1 || {
    add_warning "SQL section failed: ${title}"
    return 1
  }

  return 0
}

{
  echo "ZDM Step2 Target Discovery"
  echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Discovery Type: ${DISCOVERY_TYPE}"
  echo "Host: ${HOSTNAME_SHORT}"
} > "$OUT_TXT"

TARGET_KEY_MODE="$(normalize_key_mode "$TARGET_SSH_KEY")"

log_section "Connectivity and Authentication Context"
{
  echo "TARGET_HOST=${TARGET_HOST:-<unset>}"
  echo "TARGET_ADMIN_USER=${TARGET_ADMIN_USER:-<unset>}"
  echo "TARGET_SSH_KEY_MODE=${TARGET_KEY_MODE}"
} >> "$OUT_TXT"

run_cmd "Remote System Details" uname -a
run_cmd "Operating System Release" bash -lc 'cat /etc/os-release 2>/dev/null || true'
run_cmd "Uptime" uptime
run_cmd "/etc/oratab Entries" bash -lc 'cat /etc/oratab 2>/dev/null || echo /etc/oratab-not-found'
run_cmd "PMON SIDs" bash -lc 'ps -ef | grep pmon | grep -v grep || true'

if ! detect_oracle_env; then
  add_warning "Oracle environment detection completed with issues"
fi

log_section "Oracle Environment Details"
{
  echo "ORACLE_HOME=${CURRENT_ORACLE_HOME:-<unset>}"
  echo "ORACLE_SID=${CURRENT_ORACLE_SID:-<unset>}"
  echo "DETECTION_SOURCE=${DETECTION_SOURCE:-fallback}"
  echo "TARGET_DATABASE_UNIQUE_NAME=${TARGET_DATABASE_UNIQUE_NAME}"
} >> "$OUT_TXT"

run_cmd "sqlplus Version" bash -lc '"'"${CURRENT_ORACLE_HOME}"'"/bin/sqlplus -v 2>/dev/null || echo sqlplus-unavailable'

run_sql_select "Database Configuration" "
SELECT name, db_unique_name, database_role, open_mode, cdb FROM v\\$database;
SELECT parameter, value FROM nls_database_parameters WHERE parameter IN ('NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET') ORDER BY parameter;
"

run_sql_select "CDB and PDB Posture" "
SELECT cdb FROM v\\$database;
SELECT name, open_mode FROM v\\$pdbs ORDER BY name;
"

run_sql_select "TDE Wallet Status" "
SELECT wallet_type, wallet_order, status, wrl_type, wrl_parameter FROM v\\$encryption_wallet;
"

run_cmd "Storage Posture (ASM + Exadata When Available)" bash -lc '
  if command -v asmcmd >/dev/null 2>&1; then
    asmcmd lsdg || true
  else
    echo asmcmd-not-available
  fi
  if command -v cellcli >/dev/null 2>&1; then
    cellcli -e "LIST CELL DETAIL" || true
    cellcli -e "LIST GRIDDISK" || true
  else
    echo cellcli-not-available
  fi
'

run_cmd "Network Posture" bash -lc '
  lsnrctl status 2>/dev/null || echo lsnrctl-unavailable
  srvctl status scan 2>/dev/null || echo srvctl-scan-not-available
  find "${CURRENT_ORACLE_HOME:-/tmp}" -maxdepth 4 -name tnsnames.ora -type f 2>/dev/null | head -n 5 | xargs -r -I{} sh -c "echo --- {}; sed -n 1,120p {}"
'

run_cmd "OCI and Azure Metadata (Sanitized)" bash -lc '
  [ -f ~/.oci/config ] && awk -F= '/\[|fingerprint|region|tenancy|user|key_file/ {print $1"="$2}' ~/.oci/config | sed -E "s/(fingerprint|tenancy|user)=.*/\1=<masked>/" || echo oci-config-not-found
  [ -f /var/lib/waagent/ovf-env.xml ] && head -n 40 /var/lib/waagent/ovf-env.xml || echo azure-metadata-not-found
'

run_cmd "Grid Infrastructure Status" bash -lc '
  crsctl check crs 2>/dev/null || echo crsctl-not-available
  crsctl stat res -t 2>/dev/null || true
'

run_cmd "Network Security Checks" bash -lc '
  ss -tulnp | grep -E "(22|1521|1522)" || true
  iptables -S 2>/dev/null || echo iptables-unavailable-or-permission-denied
  firewall-cmd --list-all 2>/dev/null || echo firewall-cmd-unavailable-or-permission-denied
'

{
  echo ""
  echo "===== Summary ====="
  echo "status=${STATUS}"
  echo "warnings_count=${#WARNINGS[@]}"
} >> "$OUT_TXT"

{
  printf '{\n'
  printf '  "discovery_type": "target",\n'
  printf '  "timestamp": "%s",\n' "$(escape_json "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
  printf '  "host": "%s",\n' "$(escape_json "$HOSTNAME_SHORT")"
  printf '  "status": "%s",\n' "$(escape_json "$STATUS")"
  printf '  "oracle_home": "%s",\n' "$(escape_json "${CURRENT_ORACLE_HOME:-}")"
  printf '  "oracle_sid": "%s",\n' "$(escape_json "${CURRENT_ORACLE_SID:-}")"
  printf '  "database_unique_name": "%s",\n' "$(escape_json "$TARGET_DATABASE_UNIQUE_NAME")"
  printf '  "warnings": ['

  i=0
  while [[ $i -lt ${#WARNINGS[@]} ]]; do
    if [[ $i -gt 0 ]]; then
      printf ', '
    fi
    printf '"%s"' "$(escape_json "${WARNINGS[$i]}")"
    i=$((i + 1))
  done

  printf ']\n'
  printf '}\n'
} > "$OUT_JSON"

echo "[INFO] Target discovery text output: ${OUT_TXT}"
echo "[INFO] Target discovery json output: ${OUT_JSON}"
