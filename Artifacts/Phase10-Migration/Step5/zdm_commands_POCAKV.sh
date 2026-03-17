#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# ZDM Command Helper - POCAKV
# Generated: 2026-03-17
# ============================================================
# Usage flow on jumpbox/ZDM host:
# 1) SSH as ZDM_ADMIN_USER (for example azureuser/opc)
# 2) sudo su - zdmuser
# 3) cd <repo>/Artifacts/Phase10-Migration/Step5
# 4) ./zdm_commands_POCAKV.sh init
# 5) Populate and source ~/zdm_oci_env.sh
# 6) Export password variables and run create-creds
# 7) Run eval, then migrate

ZDM_HOME="/mnt/app/zdmhome"
SOURCE_DB_UNIQUE_NAME="POCAKV"
TARGET_DB_UNIQUE_NAME="POCAKV_ODAA"
SOURCE_HOST="10.200.1.12"
TARGET_HOST="10.200.0.250"
SOURCE_ORACLE_HOME="/u01/app/oracle/product/19.0.0/dbhome_1"
TARGET_ORACLE_HOME="/u02/app/oracle/product/19.0.0.0/dbhome_1"
SOURCE_ORACLE_SID="POCAKV"
TARGET_ORACLE_SID="POCAKV1"

STEP5_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RSP_TEMPLATE="${STEP5_DIR}/zdm_migrate_POCAKV.rsp"
RSP_RUNTIME="${STEP5_DIR}/zdm_migrate_POCAKV.runtime.rsp"
CREDS_DIR="${HOME}/creds"
OCI_ENV_FILE="${HOME}/zdm_oci_env.sh"

required_oci_vars=(
  TARGET_TENANCY_OCID
  TARGET_USER_OCID
  TARGET_FINGERPRINT
  TARGET_COMPARTMENT_OCID
  TARGET_DATABASE_OCID
)

validate_oci_environment() {
  local missing=()
  local var
  for var in "${required_oci_vars[@]}"; do
    if [ -z "${!var:-}" ]; then
      missing+=("${var}")
    fi
  done

  if [ "${MIGRATION_METHOD:-ONLINE_PHYSICAL}" = "OFFLINE_PHYSICAL" ] && [ -z "${TARGET_OBJECT_STORAGE_NAMESPACE:-}" ]; then
    missing+=("TARGET_OBJECT_STORAGE_NAMESPACE")
  fi

  if [ "${#missing[@]}" -gt 0 ]; then
    echo "ERROR: Missing OCI environment variables: ${missing[*]}" >&2
    echo "Populate and source ${OCI_ENV_FILE} before running migration." >&2
    return 1
  fi
}

validate_password_environment() {
  local missing=()
  [ -z "${SOURCE_SYS_PASSWORD:-}" ] && missing+=("SOURCE_SYS_PASSWORD")
  [ -z "${TARGET_SYS_PASSWORD:-}" ] && missing+=("TARGET_SYS_PASSWORD")

  if [ "${TDE_ENABLED:-false}" = "true" ] && [ -z "${SOURCE_TDE_WALLET_PASSWORD:-}" ]; then
    missing+=("SOURCE_TDE_WALLET_PASSWORD")
  fi

  if [ "${#missing[@]}" -gt 0 ]; then
    echo "ERROR: Missing password environment variables: ${missing[*]}" >&2
    return 1
  fi
}

validate_prereqs() {
  [ -x "${ZDM_HOME}/bin/zdmcli" ] || { echo "ERROR: zdmcli not found at ${ZDM_HOME}/bin/zdmcli" >&2; return 1; }
  [ -f "${RSP_TEMPLATE}" ] || { echo "ERROR: RSP template missing: ${RSP_TEMPLATE}" >&2; return 1; }
  command -v envsubst >/dev/null 2>&1 || { echo "ERROR: envsubst is required (gettext package)." >&2; return 1; }
}

render_rsp() {
  validate_oci_environment
  envsubst < "${RSP_TEMPLATE}" > "${RSP_RUNTIME}"
  chmod 600 "${RSP_RUNTIME}"
  echo "Rendered runtime RSP: ${RSP_RUNTIME}"
}

create_oci_env_template() {
  cat > "${OCI_ENV_FILE}" <<'EOF'
#!/usr/bin/env bash
# Fill with real OCI values, then source this file.
export TARGET_TENANCY_OCID=""
export TARGET_USER_OCID=""
export TARGET_FINGERPRINT=""
export TARGET_COMPARTMENT_OCID=""
export TARGET_DATABASE_OCID=""
# Optional for ONLINE_PHYSICAL, required for OFFLINE_PHYSICAL:
export TARGET_OBJECT_STORAGE_NAMESPACE=""

# Optional source-side OCI identifiers if applicable:
# export SOURCE_TENANCY_OCID=""
# export SOURCE_COMPARTMENT_OCID=""
# export SOURCE_DATABASE_OCID=""
EOF
  chmod 600 "${OCI_ENV_FILE}"
  echo "Created OCI env template: ${OCI_ENV_FILE}"
}

create_creds() {
  validate_password_environment
  mkdir -p "${CREDS_DIR}"
  chmod 700 "${CREDS_DIR}"

  printf '%s' "${SOURCE_SYS_PASSWORD}" > "${CREDS_DIR}/source_sys_password.txt"
  printf '%s' "${TARGET_SYS_PASSWORD}" > "${CREDS_DIR}/target_sys_password.txt"

  if [ "${TDE_ENABLED:-false}" = "true" ]; then
    printf '%s' "${SOURCE_TDE_WALLET_PASSWORD}" > "${CREDS_DIR}/tde_password.txt"
  fi

  chmod 600 "${CREDS_DIR}"/*.txt
  echo "Credential files created in ${CREDS_DIR}"
}

cleanup_creds() {
  if [ -d "${CREDS_DIR}" ]; then
    rm -f "${CREDS_DIR}"/*.txt
    echo "Credential files removed from ${CREDS_DIR}"
  fi
}

run_eval() {
  validate_prereqs
  render_rsp
  echo "Running evaluation..."
  "${ZDM_HOME}/bin/zdmcli" migrate database -rsp "${RSP_RUNTIME}" -eval
}

run_migrate() {
  validate_prereqs
  render_rsp
  echo "Starting migration..."
  "${ZDM_HOME}/bin/zdmcli" migrate database -rsp "${RSP_RUNTIME}"
}

show_monitor_commands() {
  cat <<'EOF'
Use one of the following with your real job id:
  /mnt/app/zdmhome/bin/zdmcli query job -jobid <JOB_ID>
  /mnt/app/zdmhome/bin/zdmcli query job -list all
EOF
}

resume_job() {
  local job_id="${1:-}"
  [ -n "${job_id}" ] || { echo "Usage: $0 resume <JOB_ID>" >&2; return 1; }
  "${ZDM_HOME}/bin/zdmcli" resume job -jobid "${job_id}"
}

abort_job() {
  local job_id="${1:-}"
  [ -n "${job_id}" ] || { echo "Usage: $0 abort <JOB_ID>" >&2; return 1; }
  "${ZDM_HOME}/bin/zdmcli" abort job -jobid "${job_id}"
}

init() {
  validate_prereqs
  mkdir -p "${CREDS_DIR}"
  chmod 700 "${CREDS_DIR}"
  if [ ! -f "${OCI_ENV_FILE}" ]; then
    create_oci_env_template
  else
    echo "OCI env file already exists: ${OCI_ENV_FILE}"
  fi
  echo "Init complete. Next: source ${OCI_ENV_FILE}, export passwords, run create-creds."
}

usage() {
  cat <<'EOF'
Usage: ./zdm_commands_POCAKV.sh <command> [args]

Commands:
  init               Prepare ~/creds and OCI env template
  create-creds       Create password files from environment variables
  cleanup-creds      Remove password files
  eval               Run zdmcli evaluation (-eval)
  migrate            Run zdmcli migration
  monitor            Print monitoring commands
  resume <JOB_ID>    Resume paused job
  abort <JOB_ID>     Abort a job
EOF
}

cmd="${1:-}"
case "${cmd}" in
  init) init ;;
  create-creds) create_creds ;;
  cleanup-creds) cleanup_creds ;;
  eval) run_eval ;;
  migrate) run_migrate ;;
  monitor) show_monitor_commands ;;
  resume) shift; resume_job "${1:-}" ;;
  abort) shift; abort_job "${1:-}" ;;
  *) usage; exit 1 ;;
esac
