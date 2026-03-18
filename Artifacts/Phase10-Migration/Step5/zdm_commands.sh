#!/usr/bin/env bash
set -euo pipefail

# ===========================================
# ZDM CLI Commands Wrapper
# Generated: 2026-03-18
# ===========================================
#
# IMPORTANT: Login and Setup Instructions
# 1) SSH to ZDM server as ZDM_ADMIN_USER (for example: azureuser, opc)
# 2) Switch to zdmuser: sudo su - zdmuser
# 3) Navigate to this directory in your repo clone
# 4) First-time setup: ./zdm_commands.sh init
# 5) Populate and source OCI env file: source ~/zdm_oci_env.sh
# 6) Run command: ./zdm_commands.sh <init|create-creds|cleanup-creds|eval|migrate|monitor|resume|abort>
#

ZDM_HOME="/mnt/app/zdmhome"
SOURCE_DB_UNIQUE_NAME="POCAKV"
SOURCE_DB_SID="POCAKV"
SOURCE_HOST="10.200.1.12"
SOURCE_PORT="1521"
TARGET_DB_UNIQUE_NAME="POCAKV_ODAA"
TARGET_DB_SID="POCAKV1"
TARGET_HOST="10.200.0.250"
TARGET_PORT="1521"
RSP_TEMPLATE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/zdm_migrate.rsp"
RSP_GENERATED="${HOME}/creds/zdm_migrate.generated.rsp"
CREDS_DIR="${HOME}/creds"
OCI_ENV_FILE="${HOME}/zdm_oci_env.sh"

usage() {
  cat <<'USAGE'
Usage: ./zdm_commands.sh <command> [args]

Commands:
  init                     Create creds dir and OCI env template
  create-creds             Create password files from env vars
  cleanup-creds            Remove credential files and generated RSP
  eval                     Run ZDM pre-migration evaluation
  migrate                  Start migration job
  monitor <job_id>         Query migration job details
  resume <job_id>          Resume a paused job
  abort <job_id>           Abort a running job
USAGE
}

ensure_zdm() {
  if [[ ! -x "${ZDM_HOME}/bin/zdmcli" ]]; then
    echo "ERROR: zdmcli not found at ${ZDM_HOME}/bin/zdmcli"
    exit 1
  fi
}

init() {
  mkdir -p "${CREDS_DIR}"
  chmod 700 "${CREDS_DIR}"

  if [[ ! -f "${OCI_ENV_FILE}" ]]; then
    cat > "${OCI_ENV_FILE}" <<'EOF'
#!/usr/bin/env bash
# OCI target identifiers (required)
export TARGET_TENANCY_OCID=""
export TARGET_USER_OCID=""
export TARGET_FINGERPRINT=""
export TARGET_COMPARTMENT_OCID=""
export TARGET_DATABASE_OCID=""

# Path to OCI API private key file used by ZDM API key auth
export OCI_API_PRIVATE_KEY_FILE="${HOME}/.oci/oci_api_key.pem"

# Optional for OFFLINE_PHYSICAL or Object Storage staging
# export TARGET_OBJECT_STORAGE_NAMESPACE=""

# Optional source OCI context (if applicable)
# export SOURCE_TENANCY_OCID=""
# export SOURCE_COMPARTMENT_OCID=""
# export SOURCE_DATABASE_OCID=""
EOF
    chmod 600 "${OCI_ENV_FILE}"
    echo "Created OCI env template: ${OCI_ENV_FILE}"
  else
    echo "OCI env template already exists: ${OCI_ENV_FILE}"
  fi

  echo "Initialization complete."
  echo "Next steps:"
  echo "  1) Edit ${OCI_ENV_FILE} with real OCI values"
  echo "  2) source ${OCI_ENV_FILE}"
  echo "  3) Export password vars and run ./zdm_commands.sh create-creds"
}

validate_oci_environment() {
  local missing=()
  local required=(
    TARGET_TENANCY_OCID
    TARGET_USER_OCID
    TARGET_FINGERPRINT
    TARGET_COMPARTMENT_OCID
    TARGET_DATABASE_OCID
    OCI_API_PRIVATE_KEY_FILE
  )

  for v in "${required[@]}"; do
    if [[ -z "${!v:-}" ]]; then
      missing+=("${v}")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Missing required OCI environment variables:"
    printf '  - %s\n' "${missing[@]}"
    echo "Populate and source ${OCI_ENV_FILE}, then retry."
    return 1
  fi

  if [[ ! -f "${OCI_API_PRIVATE_KEY_FILE}" ]]; then
    echo "ERROR: OCI_API_PRIVATE_KEY_FILE does not exist: ${OCI_API_PRIVATE_KEY_FILE}"
    return 1
  fi

  return 0
}

validate_password_environment() {
  local missing=()
  local required=(SRC_SYS_PASSWORD TGT_SYS_PASSWORD)

  for v in "${required[@]}"; do
    if [[ -z "${!v:-}" ]]; then
      missing+=("${v}")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Missing required password environment variables:"
    printf '  - %s\n' "${missing[@]}"
    echo "Export them in-session and retry."
    return 1
  fi

  return 0
}

create_creds() {
  validate_password_environment
  mkdir -p "${CREDS_DIR}"
  chmod 700 "${CREDS_DIR}"

  umask 077
  printf '%s\n' "${SRC_SYS_PASSWORD}" > "${CREDS_DIR}/src_sys_password.txt"
  printf '%s\n' "${TGT_SYS_PASSWORD}" > "${CREDS_DIR}/tgt_sys_password.txt"

  if [[ -n "${TGT_TDE_PASSWORD:-}" ]]; then
    printf '%s\n' "${TGT_TDE_PASSWORD}" > "${CREDS_DIR}/tde_wallet_password.txt"
  elif [[ ! -f "${CREDS_DIR}/tde_wallet_password.txt" ]]; then
    echo "WARNING: TGT_TDE_PASSWORD not set and tde_wallet_password.txt not present."
    echo "Set TGT_TDE_PASSWORD if required for your policy/release."
  fi

  chmod 600 "${CREDS_DIR}"/*.txt || true
  echo "Credential files created under ${CREDS_DIR}"
}

generate_rsp_file() {
  validate_oci_environment
  mkdir -p "${CREDS_DIR}"
  chmod 700 "${CREDS_DIR}"

  if [[ ! -f "${RSP_TEMPLATE}" ]]; then
    echo "ERROR: RSP template not found: ${RSP_TEMPLATE}"
    exit 1
  fi

  envsubst < "${RSP_TEMPLATE}" > "${RSP_GENERATED}"
  chmod 600 "${RSP_GENERATED}"
  echo "Generated RSP: ${RSP_GENERATED}"
}

cleanup_creds() {
  local files=(
    "${CREDS_DIR}/src_sys_password.txt"
    "${CREDS_DIR}/tgt_sys_password.txt"
    "${CREDS_DIR}/tde_wallet_password.txt"
    "${RSP_GENERATED}"
  )

  for f in "${files[@]}"; do
    if [[ -f "${f}" ]]; then
      : > "${f}"
      rm -f "${f}"
      echo "Removed ${f}"
    fi
  done
}

run_eval() {
  ensure_zdm
  validate_password_environment
  generate_rsp_file

  "${ZDM_HOME}/bin/zdmcli" migrate database \
    -rsp "${RSP_GENERATED}" \
    -sourcedb "${SOURCE_DB_UNIQUE_NAME}" \
    -sourcenode "${SOURCE_HOST}" \
    -targetnode "${TARGET_HOST}" \
    -eval
}

run_migrate() {
  ensure_zdm
  validate_password_environment
  generate_rsp_file

  "${ZDM_HOME}/bin/zdmcli" migrate database \
    -rsp "${RSP_GENERATED}" \
    -sourcedb "${SOURCE_DB_UNIQUE_NAME}" \
    -sourcenode "${SOURCE_HOST}" \
    -targetnode "${TARGET_HOST}"
}

monitor_job() {
  local job_id="${1:-}"
  if [[ -z "${job_id}" ]]; then
    echo "ERROR: monitor requires <job_id>"
    exit 1
  fi
  ensure_zdm
  "${ZDM_HOME}/bin/zdmcli" query job -jobid "${job_id}"
}

resume_job() {
  local job_id="${1:-}"
  if [[ -z "${job_id}" ]]; then
    echo "ERROR: resume requires <job_id>"
    exit 1
  fi
  ensure_zdm
  "${ZDM_HOME}/bin/zdmcli" resume job -jobid "${job_id}"
}

abort_job() {
  local job_id="${1:-}"
  if [[ -z "${job_id}" ]]; then
    echo "ERROR: abort requires <job_id>"
    exit 1
  fi
  ensure_zdm
  "${ZDM_HOME}/bin/zdmcli" abort job -jobid "${job_id}"
}

main() {
  local cmd="${1:-}"
  case "${cmd}" in
    init)
      init
      ;;
    create-creds)
      create_creds
      ;;
    cleanup-creds)
      cleanup_creds
      ;;
    eval)
      run_eval
      ;;
    migrate)
      run_migrate
      ;;
    monitor)
      shift
      monitor_job "${1:-}"
      ;;
    resume)
      shift
      resume_job "${1:-}"
      ;;
    abort)
      shift
      abort_job "${1:-}"
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
