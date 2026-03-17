#!/usr/bin/env bash

set -u
set -o pipefail

# Rendered from zdm-env.md at generation time. Runtime does not depend on zdm-env.md.
SOURCE_HOST_DEFAULT="10.200.1.12"
TARGET_HOST_DEFAULT="10.200.0.250"
SOURCE_SSH_USER_DEFAULT="azureuser"
TARGET_SSH_USER_DEFAULT="opc"
SOURCE_REMOTE_ORACLE_HOME_DEFAULT="/u01/app/oracle/product/19.0.0/dbhome_1"
TARGET_REMOTE_ORACLE_HOME_DEFAULT="/u02/app/oracle/product/19.0.0.0/dbhome_1"
SOURCE_ORACLE_SID_DEFAULT="POCAKV"
TARGET_ORACLE_SID_DEFAULT="POCAKV1"
SOURCE_DATABASE_UNIQUE_NAME_DEFAULT="POCAKV"
TARGET_DATABASE_UNIQUE_NAME_DEFAULT="POCAKV_ODAA"
REQUIRED_RUN_USER_DEFAULT="zdmuser"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEP2_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DISCOVERY_BASE="$STEP2_DIR/Discovery"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
SUMMARY_MD="$DISCOVERY_BASE/discovery-summary-$TIMESTAMP.md"
SUMMARY_JSON="$DISCOVERY_BASE/discovery-summary-$TIMESTAMP.json"

SOURCE_SCRIPT="$SCRIPT_DIR/zdm_source_discovery.sh"
TARGET_SCRIPT="$SCRIPT_DIR/zdm_target_discovery.sh"
SERVER_SCRIPT="$SCRIPT_DIR/zdm_server_discovery.sh"

mkdir -p "$DISCOVERY_BASE/source" "$DISCOVERY_BASE/target" "$DISCOVERY_BASE/server"

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\r//g; :a;N;$!ba;s/\n/\\n/g'
}

run_step() {
  local name="$1"
  local cmd="$2"

  echo "Running $name discovery..."
  local output rc
  output="$(bash -c "$cmd" 2>&1)"
  rc=$?

  printf '%s\n' "$output"
  return $rc
}

SOURCE_HOST="${SOURCE_HOST:-$SOURCE_HOST_DEFAULT}"
TARGET_HOST="${TARGET_HOST:-$TARGET_HOST_DEFAULT}"
SOURCE_SSH_USER="${SOURCE_SSH_USER:-$SOURCE_SSH_USER_DEFAULT}"
TARGET_SSH_USER="${TARGET_SSH_USER:-$TARGET_SSH_USER_DEFAULT}"
SOURCE_ADMIN_USER="${SOURCE_ADMIN_USER:-$SOURCE_SSH_USER}"
TARGET_ADMIN_USER="${TARGET_ADMIN_USER:-$TARGET_SSH_USER}"
SOURCE_REMOTE_ORACLE_HOME="${SOURCE_REMOTE_ORACLE_HOME:-$SOURCE_REMOTE_ORACLE_HOME_DEFAULT}"
TARGET_REMOTE_ORACLE_HOME="${TARGET_REMOTE_ORACLE_HOME:-$TARGET_REMOTE_ORACLE_HOME_DEFAULT}"
SOURCE_ORACLE_SID="${SOURCE_ORACLE_SID:-$SOURCE_ORACLE_SID_DEFAULT}"
TARGET_ORACLE_SID="${TARGET_ORACLE_SID:-$TARGET_ORACLE_SID_DEFAULT}"
SOURCE_DATABASE_UNIQUE_NAME="${SOURCE_DATABASE_UNIQUE_NAME:-$SOURCE_DATABASE_UNIQUE_NAME_DEFAULT}"
TARGET_DATABASE_UNIQUE_NAME="${TARGET_DATABASE_UNIQUE_NAME:-$TARGET_DATABASE_UNIQUE_NAME_DEFAULT}"
REQUIRED_RUN_USER="${REQUIRED_RUN_USER:-$REQUIRED_RUN_USER_DEFAULT}"

SOURCE_STATUS="PASS"
TARGET_STATUS="PASS"
SERVER_STATUS="PASS"

SOURCE_LOG="$DISCOVERY_BASE/source/source-orchestrator-$TIMESTAMP.log"
TARGET_LOG="$DISCOVERY_BASE/target/target-orchestrator-$TIMESTAMP.log"
SERVER_LOG="$DISCOVERY_BASE/server/server-orchestrator-$TIMESTAMP.log"

if [[ ! -x "$SOURCE_SCRIPT" ]]; then
  SOURCE_STATUS="FAIL"
  echo "Missing or non-executable: $SOURCE_SCRIPT" > "$SOURCE_LOG"
else
  if SOURCE_SSH_USER="$SOURCE_ADMIN_USER" SOURCE_HOST="$SOURCE_HOST" SOURCE_REMOTE_ORACLE_HOME="$SOURCE_REMOTE_ORACLE_HOME" SOURCE_ORACLE_SID="$SOURCE_ORACLE_SID" SOURCE_DATABASE_UNIQUE_NAME="$SOURCE_DATABASE_UNIQUE_NAME" REQUIRED_RUN_USER="$REQUIRED_RUN_USER" "$SOURCE_SCRIPT" > "$SOURCE_LOG" 2>&1; then
    SOURCE_STATUS="PASS"
  else
    SOURCE_STATUS="FAIL"
  fi
fi

if [[ ! -x "$TARGET_SCRIPT" ]]; then
  TARGET_STATUS="FAIL"
  echo "Missing or non-executable: $TARGET_SCRIPT" > "$TARGET_LOG"
else
  if TARGET_SSH_USER="$TARGET_ADMIN_USER" TARGET_HOST="$TARGET_HOST" TARGET_REMOTE_ORACLE_HOME="$TARGET_REMOTE_ORACLE_HOME" TARGET_ORACLE_SID="$TARGET_ORACLE_SID" TARGET_DATABASE_UNIQUE_NAME="$TARGET_DATABASE_UNIQUE_NAME" REQUIRED_RUN_USER="$REQUIRED_RUN_USER" "$TARGET_SCRIPT" > "$TARGET_LOG" 2>&1; then
    TARGET_STATUS="PASS"
  else
    TARGET_STATUS="FAIL"
  fi
fi

if [[ ! -x "$SERVER_SCRIPT" ]]; then
  SERVER_STATUS="FAIL"
  echo "Missing or non-executable: $SERVER_SCRIPT" > "$SERVER_LOG"
else
  if SOURCE_HOST="$SOURCE_HOST" TARGET_HOST="$TARGET_HOST" SOURCE_SSH_USER="$SOURCE_ADMIN_USER" TARGET_SSH_USER="$TARGET_ADMIN_USER" REQUIRED_RUN_USER="$REQUIRED_RUN_USER" "$SERVER_SCRIPT" > "$SERVER_LOG" 2>&1; then
    SERVER_STATUS="PASS"
  else
    SERVER_STATUS="FAIL"
  fi
fi

OVERALL_STATUS="PASS"
if [[ "$SOURCE_STATUS" != "PASS" || "$TARGET_STATUS" != "PASS" || "$SERVER_STATUS" != "PASS" ]]; then
  OVERALL_STATUS="FAIL"
fi

{
  echo "# Step 2 Discovery Orchestration Summary"
  echo
  echo "- Timestamp: $TIMESTAMP"
  echo "- Overall status: $OVERALL_STATUS"
  echo
  echo "## Effective Runtime Configuration"
  echo
  echo "| Variable | Value |"
  echo "|---|---|"
  echo "| SOURCE_HOST | $SOURCE_HOST |"
  echo "| TARGET_HOST | $TARGET_HOST |"
  echo "| SOURCE_ADMIN_USER | $SOURCE_ADMIN_USER |"
  echo "| TARGET_ADMIN_USER | $TARGET_ADMIN_USER |"
  echo "| SOURCE_REMOTE_ORACLE_HOME | $SOURCE_REMOTE_ORACLE_HOME |"
  echo "| TARGET_REMOTE_ORACLE_HOME | $TARGET_REMOTE_ORACLE_HOME |"
  echo "| SOURCE_ORACLE_SID | $SOURCE_ORACLE_SID |"
  echo "| TARGET_ORACLE_SID | $TARGET_ORACLE_SID |"
  echo
  echo "## Script Execution Status"
  echo
  echo "| Script | Status | Log |"
  echo "|---|---|---|"
  echo "| zdm_source_discovery.sh | $SOURCE_STATUS | $SOURCE_LOG |"
  echo "| zdm_target_discovery.sh | $TARGET_STATUS | $TARGET_LOG |"
  echo "| zdm_server_discovery.sh | $SERVER_STATUS | $SERVER_LOG |"
} > "$SUMMARY_MD"

{
  echo "{"
  echo "  \"timestamp\": \"$(json_escape "$TIMESTAMP")\"," 
  echo "  \"overall_status\": \"$(json_escape "$OVERALL_STATUS")\"," 
  echo "  \"effective_config\": {"
  echo "    \"source_host\": \"$(json_escape "$SOURCE_HOST")\"," 
  echo "    \"target_host\": \"$(json_escape "$TARGET_HOST")\"," 
  echo "    \"source_admin_user\": \"$(json_escape "$SOURCE_ADMIN_USER")\"," 
  echo "    \"target_admin_user\": \"$(json_escape "$TARGET_ADMIN_USER")\"," 
  echo "    \"source_remote_oracle_home\": \"$(json_escape "$SOURCE_REMOTE_ORACLE_HOME")\"," 
  echo "    \"target_remote_oracle_home\": \"$(json_escape "$TARGET_REMOTE_ORACLE_HOME")\"," 
  echo "    \"source_oracle_sid\": \"$(json_escape "$SOURCE_ORACLE_SID")\"," 
  echo "    \"target_oracle_sid\": \"$(json_escape "$TARGET_ORACLE_SID")\""
  echo "  },"
  echo "  \"scripts\": {"
  echo "    \"source\": { \"status\": \"$(json_escape "$SOURCE_STATUS")\", \"log\": \"$(json_escape "$SOURCE_LOG")\" },"
  echo "    \"target\": { \"status\": \"$(json_escape "$TARGET_STATUS")\", \"log\": \"$(json_escape "$TARGET_LOG")\" },"
  echo "    \"server\": { \"status\": \"$(json_escape "$SERVER_STATUS")\", \"log\": \"$(json_escape "$SERVER_LOG")\" }"
  echo "  }"
  echo "}"
} > "$SUMMARY_JSON"

echo "Summary markdown report: $SUMMARY_MD"
echo "Summary json report: $SUMMARY_JSON"

if [[ "$OVERALL_STATUS" == "FAIL" ]]; then
  exit 1
fi

exit 0
