#!/bin/bash
#
# Check Database Link Dependencies
# Project: PRODDB Migration to Oracle Database@Azure
#
# This script checks the SYS_HUB database link on the source database
# to determine if it's in use and what post-migration actions are needed.
#
# Run this script on the source server as oracle user (or admin with sudo).
#
# Usage: ./check_db_link.sh
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

ORACLE_USER="${ORACLE_USER:-oracle}"

log_section "Database Link Analysis: SYS_HUB"

# Detect Oracle environment
if [ -z "${ORACLE_HOME:-}" ]; then
    if [ -f /etc/oratab ]; then
        ORACLE_SID=$(grep -v '^#' /etc/oratab | grep -v '^$' | grep -v '^+' | head -1 | cut -d: -f1)
        ORACLE_HOME=$(grep -v '^#' /etc/oratab | grep -v '^$' | grep -v '^+' | head -1 | cut -d: -f2)
    fi
fi

export ORACLE_HOME ORACLE_SID

log_info "ORACLE_HOME: ${ORACLE_HOME:-NOT SET}"
log_info "ORACLE_SID: ${ORACLE_SID:-NOT SET}"
echo ""

run_sql() {
    local sql_query="$1"
    local sqlplus_cmd="$ORACLE_HOME/bin/sqlplus -s / as sysdba"
    local sql_script=$(cat <<EOSQL
SET PAGESIZE 1000
SET LINESIZE 200
SET FEEDBACK OFF
SET HEADING ON
SET ECHO OFF
$sql_query
EOSQL
)
    if [ "$(whoami)" = "$ORACLE_USER" ]; then
        echo "$sql_script" | ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd 2>/dev/null
    else
        echo "$sql_script" | sudo -u "$ORACLE_USER" ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$ORACLE_SID" $sqlplus_cmd 2>/dev/null
    fi
}

log_section "Step 1: Database Link Details"

echo "Querying database link configuration..."
run_sql "
SELECT owner, db_link, username, host, created
FROM dba_db_links
WHERE db_link LIKE '%HUB%' OR db_link LIKE '%SYS_HUB%'
ORDER BY owner, db_link;
"

log_section "Step 2: Test Database Link Connectivity"

echo "Testing if SYS_HUB database link is functional..."
result=$(run_sql "SELECT 'CONNECTED' FROM dual@SYS_HUB;" 2>&1)
if echo "$result" | grep -q "CONNECTED"; then
    log_info "Database link SYS_HUB is FUNCTIONAL"
else
    log_warn "Database link SYS_HUB is NOT WORKING"
    echo "Error: $result"
fi

log_section "Step 3: Check Dependencies on SYS_HUB"

echo "Checking for objects that depend on SYS_HUB..."
run_sql "
SELECT owner, name, type, referenced_link_name
FROM dba_dependencies
WHERE referenced_link_name = 'SYS_HUB'
   OR referenced_link_name LIKE '%HUB%'
ORDER BY owner, type, name;
"

dep_count=$(run_sql "SELECT COUNT(*) FROM dba_dependencies WHERE referenced_link_name = 'SYS_HUB';" | grep -o '[0-9]*' | head -1)

if [ "$dep_count" -gt 0 ] 2>/dev/null; then
    log_warn "Found $dep_count object(s) dependent on SYS_HUB"
else
    log_info "No dependencies found on SYS_HUB"
fi

log_section "Step 4: Check Synonyms Using SYS_HUB"

echo "Checking for synonyms using the database link..."
run_sql "
SELECT owner, synonym_name, table_owner, table_name, db_link
FROM dba_synonyms
WHERE db_link = 'SYS_HUB'
   OR db_link LIKE '%HUB%'
ORDER BY owner, synonym_name;
"

log_section "Step 5: Check for Remote Objects Access"

echo "Checking for views that might use the link..."
run_sql "
SELECT owner, view_name
FROM dba_views
WHERE text_vc LIKE '%@SYS_HUB%'
   OR text_vc LIKE '%@\"SYS_HUB\"%';
" 2>/dev/null || echo "  (Unable to query view text)"

log_section "Summary and Recommendations"

echo "Database Link: SYS_HUB"
echo "Owner: SYS"
echo "Target: SEEDDATA"
echo ""

if [ "$dep_count" -gt 0 ] 2>/dev/null; then
    echo -e "${YELLOW}Action Required:${NC}"
    echo "  Dependencies exist on this database link."
    echo "  After migration, verify the link still points to the correct target."
    echo "  If the link target changes, update the connection string."
    echo ""
    echo "To update post-migration:"
    echo "  DROP DATABASE LINK SYS_HUB;"
    echo "  CREATE DATABASE LINK SYS_HUB CONNECT TO <user> IDENTIFIED BY <password> USING '<new_tns_alias>';"
else
    echo -e "${GREEN}No dependencies found.${NC}"
    echo "  The database link can be dropped post-migration if not needed."
    echo ""
    echo "To drop post-migration:"
    echo "  DROP DATABASE LINK SYS_HUB;"
fi

echo ""
log_info "Add this to your post-migration checklist:"
echo "  [ ] Verify SYS_HUB database link connectivity"
echo "  [ ] Update or remove link as needed"
