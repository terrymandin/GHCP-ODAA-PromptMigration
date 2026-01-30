#!/bin/bash
# =============================================================================
# Script: verify_fixes.sh
# Purpose: Verify all fixes from Step 2 have been applied correctly
# Server: Run from ZDM server (tm-vm-odaa-oracle-jumpbox)
# 
# Usage:
#   ssh zdmuser@10.1.0.8
#   bash verify_fixes.sh
# =============================================================================

echo "================================================================"
echo "ZDM Migration Pre-Flight Verification"
echo "Database: PRODDB"
echo "Date: $(date)"
echo "================================================================"
echo ""

# Configuration
SOURCE_HOST="10.1.0.10"
SOURCE_USER="oracle"
TARGET_HOST="10.0.1.160"
TARGET_USER="oracle"
ZDM_HOME="/u01/app/zdmhome"

# Keys (adjust as needed)
SOURCE_KEY="${SOURCE_KEY:-$HOME/.ssh/id_ed25519}"
TARGET_KEY="${TARGET_KEY:-$HOME/.ssh/odaa.pem}"

# Counters
PASS=0
FAIL=0
WARN=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() { echo -e "\n${BLUE}━━━ $1 ━━━${NC}"; }
print_pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
print_fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)); }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; ((WARN++)); }
print_info() { echo -e "       $1"; }

# =============================================================================
print_header "1. Source Database Checks"
# =============================================================================

echo "Connecting to source ($SOURCE_HOST)..."

# Check SSH connectivity
if ssh -i "$SOURCE_KEY" -o BatchMode=yes -o ConnectTimeout=10 "$SOURCE_USER@$SOURCE_HOST" "echo OK" &>/dev/null; then
    print_pass "SSH connection to source"
else
    print_fail "SSH connection to source"
    print_info "Cannot verify source database settings without SSH access"
fi

# Check supplemental logging
echo "Checking supplemental logging..."
SUPLOG=$(ssh -i "$SOURCE_KEY" "$SOURCE_USER@$SOURCE_HOST" "
    export ORACLE_SID=oradb01
    export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1
    \$ORACLE_HOME/bin/sqlplus -s / as sysdba <<EOF
SET HEADING OFF FEEDBACK OFF
SELECT SUPPLEMENTAL_LOG_DATA_MIN || ',' || SUPPLEMENTAL_LOG_DATA_PK FROM V\\\$DATABASE;
EOF
" 2>/dev/null | tr -d '[:space:]')

if [ "$SUPLOG" == "YES,YES" ]; then
    print_pass "Supplemental logging (MIN=YES, PK=YES)"
elif [[ "$SUPLOG" == YES* ]]; then
    print_warn "Supplemental logging partial (MIN=YES, PK may be missing)"
    print_info "Value: $SUPLOG"
else
    print_fail "Supplemental logging not enabled"
    print_info "Value: $SUPLOG"
fi

# Check ARCHIVELOG mode
echo "Checking ARCHIVELOG mode..."
LOGMODE=$(ssh -i "$SOURCE_KEY" "$SOURCE_USER@$SOURCE_HOST" "
    export ORACLE_SID=oradb01
    export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1
    \$ORACLE_HOME/bin/sqlplus -s / as sysdba <<EOF
SET HEADING OFF FEEDBACK OFF
SELECT LOG_MODE FROM V\\\$DATABASE;
EOF
" 2>/dev/null | tr -d '[:space:]')

if [ "$LOGMODE" == "ARCHIVELOG" ]; then
    print_pass "Database in ARCHIVELOG mode"
else
    print_fail "Database not in ARCHIVELOG mode"
    print_info "Value: $LOGMODE"
fi

# Check Force Logging
echo "Checking Force Logging..."
FORCELOG=$(ssh -i "$SOURCE_KEY" "$SOURCE_USER@$SOURCE_HOST" "
    export ORACLE_SID=oradb01
    export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1
    \$ORACLE_HOME/bin/sqlplus -s / as sysdba <<EOF
SET HEADING OFF FEEDBACK OFF
SELECT FORCE_LOGGING FROM V\\\$DATABASE;
EOF
" 2>/dev/null | tr -d '[:space:]')

if [ "$FORCELOG" == "YES" ]; then
    print_pass "Force Logging enabled"
else
    print_fail "Force Logging not enabled"
    print_info "Value: $FORCELOG"
fi

# =============================================================================
print_header "2. Target Environment Checks"
# =============================================================================

echo "Connecting to target ($TARGET_HOST)..."

# Check SSH connectivity
if ssh -i "$TARGET_KEY" -o BatchMode=yes -o ConnectTimeout=10 "$TARGET_USER@$TARGET_HOST" "echo OK" &>/dev/null; then
    print_pass "SSH connection to target (oracle user)"
elif ssh -i "$TARGET_KEY" -o BatchMode=yes -o ConnectTimeout=10 "opc@$TARGET_HOST" "echo OK" &>/dev/null; then
    print_warn "SSH connection to target (opc user only, oracle may need configuration)"
else
    print_fail "SSH connection to target"
fi

# Check target port connectivity
echo "Checking target ports..."
if nc -z -w5 "$TARGET_HOST" 1521 &>/dev/null; then
    print_pass "Port 1521 (Oracle) accessible on target"
else
    print_warn "Port 1521 not accessible (may be blocked by firewall)"
fi

if nc -z -w5 "$TARGET_HOST" 22 &>/dev/null; then
    print_pass "Port 22 (SSH) accessible on target"
else
    print_fail "Port 22 not accessible on target"
fi

# =============================================================================
print_header "3. ZDM Server Checks"
# =============================================================================

# Check OCI CLI
echo "Checking OCI CLI installation..."
if command -v oci &>/dev/null; then
    OCI_VER=$(oci --version 2>/dev/null)
    print_pass "OCI CLI installed (version: $OCI_VER)"
else
    print_fail "OCI CLI not installed"
fi

# Check OCI CLI configuration
echo "Checking OCI CLI configuration..."
if [ -f ~/.oci/config ]; then
    print_pass "OCI config file exists"
    
    # Test OCI connection
    echo "Testing OCI connection..."
    if oci os ns get &>/dev/null; then
        NS=$(oci os ns get --query 'data' --raw-output 2>/dev/null)
        print_pass "OCI CLI configured and working (namespace: $NS)"
    else
        print_fail "OCI CLI configured but connection failed"
        print_info "Run 'oci os ns get' to see the error"
    fi
else
    print_fail "OCI config file not found"
fi

# Check ZDM service
echo "Checking ZDM service..."
if [ -d "$ZDM_HOME" ]; then
    print_pass "ZDM_HOME exists: $ZDM_HOME"
    
    if $ZDM_HOME/bin/zdmservice status &>/dev/null; then
        print_pass "ZDM service is running"
    else
        print_warn "ZDM service may not be running"
    fi
else
    print_fail "ZDM_HOME not found: $ZDM_HOME"
fi

# Check disk space
echo "Checking disk space..."
AVAIL=$(df -BG / | tail -1 | awk '{print $4}' | sed 's/G//')
if [ "$AVAIL" -ge 50 ]; then
    print_pass "Disk space: ${AVAIL}GB available (≥50GB recommended)"
elif [ "$AVAIL" -ge 25 ]; then
    print_warn "Disk space: ${AVAIL}GB available (50GB recommended, should be OK for small DBs)"
else
    print_fail "Disk space: ${AVAIL}GB available (critically low)"
fi

# Check Java
echo "Checking Java..."
if [ -n "$JAVA_HOME" ] && [ -d "$JAVA_HOME" ]; then
    JAVA_VER=$($JAVA_HOME/bin/java -version 2>&1 | head -1)
    print_pass "JAVA_HOME configured: $JAVA_HOME"
    print_info "$JAVA_VER"
elif [ -d "$ZDM_HOME/jdk" ]; then
    print_pass "Java bundled with ZDM: $ZDM_HOME/jdk"
else
    print_warn "JAVA_HOME not set (ZDM may use bundled Java)"
fi

# =============================================================================
print_header "4. Network Connectivity"
# =============================================================================

echo "Testing connectivity to source..."
if ping -c 1 -W 2 "$SOURCE_HOST" &>/dev/null; then
    LATENCY=$(ping -c 3 "$SOURCE_HOST" 2>/dev/null | tail -1 | awk -F'/' '{print $5}')
    print_pass "Ping to source: ${LATENCY}ms average"
else
    print_warn "ICMP blocked to source (TCP may still work)"
fi

if nc -z -w5 "$SOURCE_HOST" 1521 &>/dev/null; then
    print_pass "Port 1521 accessible on source"
else
    print_fail "Port 1521 not accessible on source"
fi

echo "Testing connectivity to target..."
if ping -c 1 -W 2 "$TARGET_HOST" &>/dev/null; then
    print_pass "Ping to target successful"
else
    print_warn "ICMP blocked to target (expected for Exadata)"
fi

# =============================================================================
print_header "Verification Summary"
# =============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  ${GREEN}PASSED:${NC} $PASS"
echo -e "  ${RED}FAILED:${NC} $FAIL"
echo -e "  ${YELLOW}WARNINGS:${NC} $WARN"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $FAIL -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ All critical checks passed!${NC}"
    echo "  You can proceed to Step 3: Generate Migration Artifacts"
    echo ""
    exit 0
else
    echo ""
    echo -e "${RED}✗ Some critical checks failed.${NC}"
    echo "  Please resolve the failed items before proceeding."
    echo ""
    exit 1
fi
