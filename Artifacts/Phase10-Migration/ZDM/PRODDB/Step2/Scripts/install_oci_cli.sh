#!/bin/bash
# =============================================================================
# Script: install_oci_cli.sh
# Purpose: Install and configure OCI CLI on ZDM server
# Server: tm-vm-odaa-oracle-jumpbox (10.1.0.8)
# 
# Usage:
#   1. SSH to ZDM server: ssh azureuser@10.1.0.8
#   2. Run this script: bash install_oci_cli.sh
# =============================================================================

set -e

echo "================================================================"
echo "OCI CLI Installation Script for ZDM Server"
echo "Date: $(date)"
echo "Hostname: $(hostname)"
echo "User: $(whoami)"
echo "================================================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print status
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Check if OCI CLI is already installed
echo ""
echo "================================================================"
echo "Step 1: Checking if OCI CLI is already installed"
echo "================================================================"

if command -v oci &> /dev/null; then
    OCI_VERSION=$(oci --version 2>/dev/null || echo "unknown")
    print_warning "OCI CLI is already installed (version: $OCI_VERSION)"
    echo ""
    read -p "Do you want to reinstall/update? (y/N): " REINSTALL
    if [[ ! "$REINSTALL" =~ ^[Yy]$ ]]; then
        echo "Skipping installation. Proceeding to configuration check..."
    fi
else
    echo ""
    echo "================================================================"
    echo "Step 2: Installing OCI CLI"
    echo "================================================================"
    
    # Install dependencies
    print_status "Installing required packages..."
    if command -v yum &> /dev/null; then
        sudo yum install -y python3 python3-pip curl
    elif command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y python3 python3-pip curl
    fi
    
    # Download and run OCI CLI installer
    print_status "Downloading OCI CLI installer..."
    
    # Create a response file for non-interactive installation
    INSTALL_DIR="$HOME/lib/oracle-cli"
    EXEC_DIR="$HOME/bin"
    
    echo "Installing to: $INSTALL_DIR"
    echo "Executable in: $EXEC_DIR"
    
    # Run installer with automatic responses
    bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)" -- \
        --install-dir "$INSTALL_DIR" \
        --exec-dir "$EXEC_DIR" \
        --accept-all-defaults
    
    # Add to PATH if not already there
    if ! grep -q "$EXEC_DIR" ~/.bashrc; then
        echo "export PATH=\$PATH:$EXEC_DIR" >> ~/.bashrc
        print_status "Added $EXEC_DIR to PATH in ~/.bashrc"
    fi
    
    # Source bashrc to get new PATH
    export PATH=$PATH:$EXEC_DIR
fi

# Verify installation
echo ""
echo "================================================================"
echo "Step 3: Verifying OCI CLI installation"
echo "================================================================"

if command -v oci &> /dev/null; then
    OCI_VERSION=$(oci --version)
    print_status "OCI CLI installed successfully!"
    echo "Version: $OCI_VERSION"
else
    # Try with explicit path
    if [ -f "$HOME/bin/oci" ]; then
        OCI_VERSION=$($HOME/bin/oci --version)
        print_status "OCI CLI installed at $HOME/bin/oci"
        echo "Version: $OCI_VERSION"
        echo ""
        print_warning "Please run: source ~/.bashrc"
        print_warning "Or log out and log back in to update your PATH"
    else
        print_error "OCI CLI installation failed!"
        exit 1
    fi
fi

# Check for existing configuration
echo ""
echo "================================================================"
echo "Step 4: Checking OCI CLI configuration"
echo "================================================================"

if [ -f ~/.oci/config ]; then
    print_status "OCI config file exists: ~/.oci/config"
    echo ""
    echo "Current profiles:"
    grep '^\[' ~/.oci/config
else
    print_warning "OCI config file not found"
    echo ""
    echo "To configure OCI CLI, you will need:"
    echo "  1. OCI User OCID (from OCI Console → Identity → Users)"
    echo "  2. OCI Tenancy OCID: ocid1.tenancy.oc1..aaaaaaaaax76pwvum5vhn2p3v264osde3ykrudasfzjktipw3ibpvtndhtkq"
    echo "  3. OCI Region: uk-london-1"
    echo "  4. API Key (generate or use existing)"
    echo ""
    read -p "Do you want to configure OCI CLI now? (y/N): " CONFIGURE
    if [[ "$CONFIGURE" =~ ^[Yy]$ ]]; then
        echo ""
        echo "Running 'oci setup config'..."
        echo ""
        oci setup config
    else
        echo ""
        echo "You can configure later by running: oci setup config"
    fi
fi

echo ""
echo "================================================================"
echo "Installation Complete"
echo "================================================================"
echo ""
echo "Next steps:"
echo "  1. If PATH was updated, run: source ~/.bashrc"
echo "  2. Configure OCI CLI (if not done): oci setup config"
echo "  3. Test connection: oci os ns get"
echo ""
echo "For zdmuser, you may need to repeat this installation as zdmuser:"
echo "  sudo su - zdmuser"
echo "  bash install_oci_cli.sh"
echo ""
