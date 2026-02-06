#!/bin/bash
#
# Verify Target Database Name Conflicts
# Project: PRODDB Migration to Oracle Database@Azure
#
# This script checks for existing databases on the target cluster
# that may conflict with the migration target name.
#
# Run this script on the target server as opc (with sudo to oracle).
#
# Usage: ./verify_target_db_name.sh [db_unique_name]
#

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "\n${BLUE}=== $1 ===${NC}\n"; }

# Target db_unique_name to check (optional parameter)
CHECK_NAME="${1:-oradb01}"

log_section "Target Database Name Conflict Check"

echo "Checking for conflicts with database name: $CHECK_NAME"
echo ""

# Get Grid Home
GRID_HOME="${GRID_HOME:-/u01/app/19.0.0.0/grid}"

log_section "Step 1: List all registered databases"

if [ -f "$GRID_HOME/bin/srvctl" ]; then
    log_info "Querying CRS for registered databases..."
    sudo -u oracle $GRID_HOME/bin/srvctl config database 2>/dev/null || echo "No databases found or srvctl error"
else
    log_warn "srvctl not found at $GRID_HOME/bin/srvctl"
fi

log_section "Step 2: Check for databases matching pattern"

echo "Searching for databases containing 'oradb01'..."
echo ""

# Check CRS resources
log_info "CRS resources matching 'oradb01':"
crsctl status resource -t 2>/dev/null | grep -i oradb01 || echo "  No matching CRS resources found"

echo ""

# List databases
log_info "Registered databases:"
for db in $(sudo -u oracle $GRID_HOME/bin/srvctl config database 2>/dev/null); do
    status=$(sudo -u oracle $GRID_HOME/bin/srvctl status database -d "$db" 2>/dev/null | head -1)
    echo "  - $db: $status"
done

log_section "Step 3: Check specific database: $CHECK_NAME"

log_info "Checking if '$CHECK_NAME' exists..."
if sudo -u oracle $GRID_HOME/bin/srvctl config database -d "$CHECK_NAME" 2>/dev/null; then
    log_warn "Database '$CHECK_NAME' EXISTS in CRS!"
    echo ""
    log_info "Database configuration:"
    sudo -u oracle $GRID_HOME/bin/srvctl config database -d "$CHECK_NAME" 2>/dev/null
    echo ""
    log_info "Database status:"
    sudo -u oracle $GRID_HOME/bin/srvctl status database -d "$CHECK_NAME" 2>/dev/null
    CONFLICT=true
else
    log_info "Database '$CHECK_NAME' does NOT exist in CRS - OK to use"
    CONFLICT=false
fi

log_section "Step 4: Check ASM for database files"

log_info "Checking ASM disk groups for '$CHECK_NAME' directories..."

# Check DATAC3 (common data disk group name)
for dg in DATAC3 DATAC1 DATA; do
    if sudo -u oracle asmcmd ls "+$dg" 2>/dev/null | grep -qi oradb01; then
        log_warn "Found oradb01 files in +$dg:"
        sudo -u oracle asmcmd ls "+$dg" 2>/dev/null | grep -i oradb01
    fi
done

log_section "Step 5: Recommendations"

if [ "$CONFLICT" = true ]; then
    echo -e "${YELLOW}Conflict detected. Options:${NC}"
    echo ""
    echo "Option A: Remove the existing database (if not needed)"
    echo "  sudo -u oracle srvctl stop database -d $CHECK_NAME -f"
    echo "  sudo -u oracle srvctl remove database -d $CHECK_NAME -f"
    echo ""
    echo "Option B: Use a different db_unique_name for migration"
    echo "  Suggested alternatives:"
    echo "    - oradb01_oda"
    echo "    - oradb01_azure"
    echo "    - oradb01_prod"
    echo ""
else
    echo -e "${GREEN}No conflicts found for '$CHECK_NAME'${NC}"
    echo "You can proceed with db_unique_name = $CHECK_NAME"
fi

log_section "Step 6: Summary"

echo "Checked database name: $CHECK_NAME"
if [ "$CONFLICT" = true ]; then
    echo -e "Status: ${RED}CONFLICT DETECTED${NC}"
    exit 1
else
    echo -e "Status: ${GREEN}NO CONFLICT${NC}"
    exit 0
fi
