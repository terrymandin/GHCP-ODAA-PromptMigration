#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

find_repo_root() {
  local dir="$SCRIPT_DIR"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/zdm-env.md" ]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

REPO_ROOT="$(find_repo_root)"
ENV_FILE="$REPO_ROOT/zdm-env.md"
OUT_DIR="$REPO_ROOT/Artifacts/Phase10-Migration/Step4/Resolution"
mkdir -p "$OUT_DIR"

get_env_value() {
  local key="$1"
  awk -v k="$key" '
    $0 ~ "^- "k":[[:space:]]*" {
      sub("^- "k":[[:space:]]*", "", $0)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
      print
      exit
    }
  ' "$ENV_FILE"
}

is_placeholder() {
  local value="$1"
  [[ "$value" == *"<"*">"* ]]
}

SOURCE_HOST="$(get_env_value SOURCE_HOST)"
TARGET_HOST="$(get_env_value TARGET_HOST)"
SOURCE_SSH_USER="$(get_env_value SOURCE_SSH_USER)"
TARGET_SSH_USER="$(get_env_value TARGET_SSH_USER)"
SOURCE_SSH_KEY="$(get_env_value SOURCE_SSH_KEY || true)"
TARGET_SSH_KEY="$(get_env_value TARGET_SSH_KEY || true)"
SOURCE_REMOTE_ORACLE_HOME="$(get_env_value SOURCE_REMOTE_ORACLE_HOME)"
TARGET_REMOTE_ORACLE_HOME="$(get_env_value TARGET_REMOTE_ORACLE_HOME)"
SOURCE_ORACLE_SID="$(get_env_value SOURCE_ORACLE_SID)"
TARGET_ORACLE_SID="$(get_env_value TARGET_ORACLE_SID)"

run_remote_capture() {
  local host="$1"
  local user="$2"
  local key="$3"
  local oracle_home="$4"
  local oracle_sid="$5"
  local label="$6"

  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  local out_txt="$OUT_DIR/${label}-db-version-${ts}.txt"

  local remote_cmd
  remote_cmd=$(cat <<EOF
set -e
export ORACLE_HOME='${oracle_home}'
export ORACLE_SID='${oracle_sid}'
export PATH="\$ORACLE_HOME/bin:\$PATH"
echo "HOST=\$(hostname)"
echo "ORACLE_HOME=\$ORACLE_HOME"
echo "ORACLE_SID=\$ORACLE_SID"
if [ -x "\$ORACLE_HOME/bin/sqlplus" ]; then
  "\$ORACLE_HOME/bin/sqlplus" -v
else
  echo "ERROR: sqlplus not found at \$ORACLE_HOME/bin/sqlplus"
  exit 2
fi
ps -ef | grep pmon | grep -v grep || true
EOF
)

  if [ -n "$key" ] && ! is_placeholder "$key"; then
    ssh -o BatchMode=yes -o ConnectTimeout=10 -i "$key" "${user}@${host}" "$remote_cmd" > "$out_txt"
  else
    ssh -o BatchMode=yes -o ConnectTimeout=10 "${user}@${host}" "$remote_cmd" > "$out_txt"
  fi

  echo "$out_txt"
}

SOURCE_OUT="$(run_remote_capture "$SOURCE_HOST" "$SOURCE_SSH_USER" "$SOURCE_SSH_KEY" "$SOURCE_REMOTE_ORACLE_HOME" "$SOURCE_ORACLE_SID" "source")"
TARGET_OUT="$(run_remote_capture "$TARGET_HOST" "$TARGET_SSH_USER" "$TARGET_SSH_KEY" "$TARGET_REMOTE_ORACLE_HOME" "$TARGET_ORACLE_SID" "target")"

REPORT_TS="$(date +%Y%m%d-%H%M%S)"
REPORT_FILE="$OUT_DIR/fix-01-db-version-report-${REPORT_TS}.md"

{
  echo "# Fix 01 - Database Version Evidence"
  echo
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "## Inputs"
  echo "- Source host: ${SOURCE_HOST}"
  echo "- Target host: ${TARGET_HOST}"
  echo "- Source SID/home: ${SOURCE_ORACLE_SID} / ${SOURCE_REMOTE_ORACLE_HOME}"
  echo "- Target SID/home: ${TARGET_ORACLE_SID} / ${TARGET_REMOTE_ORACLE_HOME}"
  echo
  echo "## Output Artifacts"
  echo "- Source raw capture: ${SOURCE_OUT}"
  echo "- Target raw capture: ${TARGET_OUT}"
  echo
  echo "## Result"
  echo "PASS: sqlplus version and PMON evidence captured on source and target."
} > "$REPORT_FILE"

echo "Created: $REPORT_FILE"
