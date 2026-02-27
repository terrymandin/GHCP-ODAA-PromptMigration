#!/usr/bin/env bash
# =============================================================================
# fix_05_discover_oci_namespace.sh
#
# Purpose : Discover the OCI Object Storage namespace for the configured
#           tenancy and output the value so it can be recorded in zdm-env.md.
#
# Target  : ZDM server (10.1.0.8) — run locally as zdmuser.
#           OCI CLI must be configured for zdmuser (~/oci/config present).
#
# Run as  : zdmuser on ZDM server (10.1.0.8)
# Usage   : bash fix_05_discover_oci_namespace.sh
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — sourced from zdm-env.md values
# ---------------------------------------------------------------------------
OCI_CONFIG_PATH="${OCI_CONFIG_PATH:-${HOME}/.oci/config}"
OCI_TENANCY_OCID="${OCI_TENANCY_OCID:-ocid1.tenancy.oc1..aaaaaaaarvyhjcn7wkkxxx5g3o7lgqks23bmsjtsticz3gtg5xs5qyrwkftq}"

LOG_FILE="fix_05_$(date +%Y%m%d_%H%M%S).log"

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"; }
info() { log "INFO  $*"; }
fail() { log "ERROR $*"; exit 1; }
sep()  { log "----------------------------------------------------------------------"; }

# ---------------------------------------------------------------------------
# Step 0: Preflight checks
# ---------------------------------------------------------------------------
sep
info "Starting fix_05: Discover OCI Object Storage Namespace"
info "OCI config  : ${OCI_CONFIG_PATH}"
info "Tenancy     : ${OCI_TENANCY_OCID}"
info "Log file    : ${LOG_FILE}"
sep

info "Step 0: Checking OCI CLI availability..."
command -v oci >/dev/null 2>&1 || fail "OCI CLI not found. Install it or run as zdmuser (which has OCI CLI configured)."

info "Step 0: Checking OCI config exists..."
[ -f "${OCI_CONFIG_PATH}" ] || fail "OCI config not found at ${OCI_CONFIG_PATH}. Run as zdmuser or create config file."
info "OCI config found: OK"

# ---------------------------------------------------------------------------
# Step 1: Discover namespace
# ---------------------------------------------------------------------------
sep
info "Step 1: Retrieving OCI Object Storage namespace..."

NAMESPACE_JSON=$(oci os ns get --config-file "${OCI_CONFIG_PATH}" 2>&1) || \
  fail "Failed to retrieve OCI namespace. Check OCI config, API key, and network connectivity to OCI."

NAMESPACE=$(echo "${NAMESPACE_JSON}" | python3 -c "import sys,json; print(json.load(sys.stdin)['data'])" 2>/dev/null) || \
  NAMESPACE=$(echo "${NAMESPACE_JSON}" | grep -oP '"data"\s*:\s*"\K[^"]+' 2>/dev/null) || \
  fail "Could not parse namespace from OCI CLI output: ${NAMESPACE_JSON}"

info "Raw OCI output: ${NAMESPACE_JSON}"
sep
echo ""
echo "============================================================"
echo "  OCI Object Storage Namespace: ${NAMESPACE}"
echo "============================================================"
echo ""
echo "  ACTION REQUIRED: Update zdm-env.md with this value:"
echo "  - OCI_OSS_NAMESPACE: ${NAMESPACE}"
echo ""
echo "  File: prompts/Phase10-Migration/ZDM/zdm-env.md"
echo "============================================================"
echo ""

info "Namespace discovered: ${NAMESPACE}"
info "✅ Fix 05 complete. Update zdm-env.md with OCI_OSS_NAMESPACE = ${NAMESPACE}"
sep
info "Log saved to: ${LOG_FILE}"
