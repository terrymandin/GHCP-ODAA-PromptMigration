#!/bin/bash
#
# Fix OCI Configuration for ZDM User
# Project: PRODDB Migration to Oracle Database@Azure
#
# This script helps configure OCI CLI for zdmuser on the ZDM server.
# Run this script as azureuser (with sudo access) on the ZDM server.
#
# Usage: ./fix_oci_config.sh
#

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "\n${BLUE}=== $1 ===${NC}\n"; }

ZDM_USER="${ZDM_USER:-zdmuser}"

log_section "OCI Configuration Fix Script for ZDM"

echo "This script will help configure OCI CLI for the ZDM user ($ZDM_USER)."
echo "You will need the following information from OCI Console:"
echo "  - User OCID"
echo "  - Tenancy OCID"
echo "  - Region (e.g., uk-london-1)"
echo "  - API Key Fingerprint"
echo "  - Path to API private key"
echo ""

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
    log_warn "This script should be run with sudo or as root."
    log_info "Attempting to continue, but some operations may fail..."
fi

log_section "Step 1: Checking existing OCI configuration"

ZDM_USER_HOME=$(eval echo ~$ZDM_USER)
OCI_DIR="$ZDM_USER_HOME/.oci"

log_info "ZDM user home: $ZDM_USER_HOME"
log_info "OCI config directory: $OCI_DIR"

# Check for existing config
if [ -f "$OCI_DIR/config" ]; then
    log_info "Existing OCI config found:"
    sudo cat "$OCI_DIR/config" | grep -v "key_file" | head -20
    echo ""
    read -p "Do you want to overwrite the existing config? (y/n): " OVERWRITE
    if [ "$OVERWRITE" != "y" ]; then
        log_info "Keeping existing configuration."
        log_section "Testing existing OCI connectivity"
        sudo -u "$ZDM_USER" oci os ns get && log_info "OCI connectivity: SUCCESS" || log_error "OCI connectivity: FAILED"
        exit 0
    fi
fi

log_section "Step 2: Checking for existing API key files"

echo "Available .pem files for $ZDM_USER:"
sudo find "$ZDM_USER_HOME" -name "*.pem" 2>/dev/null | while read f; do
    echo "  - $f"
done

echo ""

# Default key path based on discovery
DEFAULT_KEY_PATH="$ZDM_USER_HOME/.oci/odaa.pem"
if sudo test -f "$DEFAULT_KEY_PATH"; then
    log_info "Found default API key: $DEFAULT_KEY_PATH"
fi

log_section "Step 3: Gathering OCI configuration details"

# Prompt for OCI details
read -p "Enter OCI User OCID (ocid1.user.oc1...): " OCI_USER_OCID
read -p "Enter OCI Tenancy OCID (ocid1.tenancy.oc1...): " OCI_TENANCY_OCID
read -p "Enter OCI Region (e.g., uk-london-1): " OCI_REGION
read -p "Enter API Key Fingerprint (xx:xx:xx...): " OCI_FINGERPRINT
read -p "Enter API Key File Path [$DEFAULT_KEY_PATH]: " OCI_KEY_FILE
OCI_KEY_FILE="${OCI_KEY_FILE:-$DEFAULT_KEY_PATH}"

# Validate inputs
if [ -z "$OCI_USER_OCID" ] || [ -z "$OCI_TENANCY_OCID" ] || [ -z "$OCI_REGION" ] || [ -z "$OCI_FINGERPRINT" ]; then
    log_error "All fields are required. Please run the script again with all values."
    exit 1
fi

# Check if key file exists
if ! sudo test -f "$OCI_KEY_FILE"; then
    log_error "API key file not found: $OCI_KEY_FILE"
    exit 1
fi

log_section "Step 4: Creating OCI configuration"

# Create .oci directory if needed
sudo mkdir -p "$OCI_DIR"
sudo chown "$ZDM_USER:$(id -gn $ZDM_USER 2>/dev/null || echo $ZDM_USER)" "$OCI_DIR"
sudo chmod 700 "$OCI_DIR"

# Create config file
sudo tee "$OCI_DIR/config" > /dev/null << EOF
[DEFAULT]
user=$OCI_USER_OCID
fingerprint=$OCI_FINGERPRINT
tenancy=$OCI_TENANCY_OCID
region=$OCI_REGION
key_file=$OCI_KEY_FILE
EOF

# Set permissions
sudo chown "$ZDM_USER:$(id -gn $ZDM_USER 2>/dev/null || echo $ZDM_USER)" "$OCI_DIR/config"
sudo chmod 600 "$OCI_DIR/config"
sudo chmod 600 "$OCI_KEY_FILE"

log_info "OCI configuration created at: $OCI_DIR/config"

log_section "Step 5: Verifying fingerprint matches"

log_info "Calculating fingerprint from private key..."
CALCULATED_FP=$(sudo openssl rsa -in "$OCI_KEY_FILE" -pubout -outform DER 2>/dev/null | openssl md5 -c | awk '{print $2}')

if [ "$CALCULATED_FP" = "$OCI_FINGERPRINT" ]; then
    log_info "Fingerprint MATCHES: $CALCULATED_FP"
else
    log_warn "Fingerprint MISMATCH!"
    log_warn "  Provided:   $OCI_FINGERPRINT"
    log_warn "  Calculated: $CALCULATED_FP"
    log_warn "Verify the correct API key is being used."
fi

log_section "Step 6: Testing OCI connectivity"

log_info "Testing OCI CLI as $ZDM_USER..."

if sudo -u "$ZDM_USER" oci os ns get 2>/dev/null; then
    echo ""
    log_info "OCI connectivity: SUCCESS"
    
    echo ""
    log_info "Testing region list..."
    sudo -u "$ZDM_USER" oci iam region list --output table | head -10
    
    log_section "Configuration Complete"
    echo -e "${GREEN}OCI CLI is now configured for $ZDM_USER${NC}"
    echo ""
    echo "Configuration file: $OCI_DIR/config"
    echo "API key file: $OCI_KEY_FILE"
    echo ""
else
    echo ""
    log_error "OCI connectivity: FAILED"
    echo ""
    echo "Troubleshooting steps:"
    echo "1. Verify the API key is uploaded to OCI Console (User Settings > API Keys)"
    echo "2. Check that the fingerprint matches"
    echo "3. Verify the User OCID and Tenancy OCID are correct"
    echo "4. Check network connectivity to OCI endpoints"
    echo ""
    exit 1
fi
