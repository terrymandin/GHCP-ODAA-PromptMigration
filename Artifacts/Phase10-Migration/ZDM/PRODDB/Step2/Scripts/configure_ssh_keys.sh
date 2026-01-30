#!/bin/bash
# =============================================================================
# Script: configure_ssh_keys.sh
# Purpose: Configure SSH key authentication between ZDM server and source/target
# 
# Run this script on the ZDM server (tm-vm-odaa-oracle-jumpbox)
# 
# Usage:
#   1. SSH to ZDM server as zdmuser: ssh zdmuser@10.1.0.8
#   2. Run this script: bash configure_ssh_keys.sh
# =============================================================================

set -e

echo "================================================================"
echo "SSH Key Configuration Script for ZDM Migration"
echo "Date: $(date)"
echo "Hostname: $(hostname)"
echo "User: $(whoami)"
echo "================================================================"

# Configuration - Update these values as needed
SOURCE_HOST="10.1.0.10"
SOURCE_USER="oracle"
TARGET_HOST="10.0.1.160"
TARGET_USER="oracle"  # or "opc" depending on access pattern

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }

# Check if running as correct user
echo ""
echo "================================================================"
echo "Step 1: Checking current user and SSH keys"
echo "================================================================"

if [ "$(whoami)" != "zdmuser" ]; then
    print_warning "Current user is $(whoami), recommended to run as zdmuser"
    echo "You can switch with: sudo su - zdmuser"
fi

echo ""
echo "Available SSH keys in ~/.ssh:"
ls -la ~/.ssh/*.pem ~/.ssh/id_* 2>/dev/null || echo "No keys found"

echo ""
echo "================================================================"
echo "Step 2: Select or generate SSH key"
echo "================================================================"

# Check for existing keys
EXISTING_KEYS=()
for key in ~/.ssh/id_ed25519 ~/.ssh/id_rsa ~/.ssh/zdm.pem ~/.ssh/odaa.pem; do
    if [ -f "$key" ]; then
        EXISTING_KEYS+=("$key")
    fi
done

if [ ${#EXISTING_KEYS[@]} -gt 0 ]; then
    echo "Found existing SSH keys:"
    for i in "${!EXISTING_KEYS[@]}"; do
        echo "  $((i+1)). ${EXISTING_KEYS[$i]}"
    done
    echo "  $((${#EXISTING_KEYS[@]}+1)). Generate new key"
    echo ""
    read -p "Select key to use (1-$((${#EXISTING_KEYS[@]}+1))): " KEY_CHOICE
    
    if [ "$KEY_CHOICE" -le "${#EXISTING_KEYS[@]}" ] 2>/dev/null; then
        SSH_KEY="${EXISTING_KEYS[$((KEY_CHOICE-1))]}"
        print_status "Using existing key: $SSH_KEY"
    else
        # Generate new key
        SSH_KEY=~/.ssh/zdm_migration_key
        echo "Generating new ED25519 key..."
        ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "zdmuser@$(hostname)-migration"
        print_status "Generated new key: $SSH_KEY"
    fi
else
    # Generate new key
    SSH_KEY=~/.ssh/zdm_migration_key
    echo "No existing keys found. Generating new ED25519 key..."
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "zdmuser@$(hostname)-migration"
    print_status "Generated new key: $SSH_KEY"
fi

# Determine public key
if [[ "$SSH_KEY" == *.pem ]]; then
    # For .pem files, public key might not exist - derive it
    if [ ! -f "${SSH_KEY}.pub" ]; then
        print_warning "Generating public key from private key..."
        ssh-keygen -y -f "$SSH_KEY" > "${SSH_KEY}.pub"
    fi
    PUBLIC_KEY="${SSH_KEY}.pub"
else
    PUBLIC_KEY="${SSH_KEY}.pub"
fi

echo ""
echo "Public key to distribute:"
echo "---"
cat "$PUBLIC_KEY"
echo "---"

echo ""
echo "================================================================"
echo "Step 3: Test/Configure SSH to Source ($SOURCE_HOST)"
echo "================================================================"

echo "Testing SSH connection to source ($SOURCE_USER@$SOURCE_HOST)..."

if ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=10 "$SOURCE_USER@$SOURCE_HOST" "echo 'Connection successful'" 2>/dev/null; then
    print_status "SSH to source already working!"
else
    print_warning "SSH to source not configured or failed"
    echo ""
    echo "To configure SSH access to source:"
    echo ""
    echo "Option A: Using ssh-copy-id (if password auth available)"
    echo "  ssh-copy-id -i $PUBLIC_KEY $SOURCE_USER@$SOURCE_HOST"
    echo ""
    echo "Option B: Manual copy"
    echo "  1. SSH to source as admin user"
    echo "  2. Switch to $SOURCE_USER: sudo su - $SOURCE_USER"
    echo "  3. Run these commands:"
    echo "     mkdir -p ~/.ssh && chmod 700 ~/.ssh"
    echo "     echo '$(cat $PUBLIC_KEY)' >> ~/.ssh/authorized_keys"
    echo "     chmod 600 ~/.ssh/authorized_keys"
    echo ""
    read -p "Try ssh-copy-id now? (y/N): " TRY_COPY
    if [[ "$TRY_COPY" =~ ^[Yy]$ ]]; then
        ssh-copy-id -i "$PUBLIC_KEY" "$SOURCE_USER@$SOURCE_HOST" || print_error "ssh-copy-id failed"
    fi
fi

echo ""
echo "================================================================"
echo "Step 4: Test/Configure SSH to Target ($TARGET_HOST)"
echo "================================================================"

# For Exadata targets, we might need to use a different key (odaa.pem)
TARGET_KEY="$SSH_KEY"
if [ -f ~/.ssh/odaa.pem ]; then
    echo "Found odaa.pem - this is typically used for Oracle Database@Azure targets"
    read -p "Use odaa.pem for target connection? (Y/n): " USE_ODAA
    if [[ ! "$USE_ODAA" =~ ^[Nn]$ ]]; then
        TARGET_KEY=~/.ssh/odaa.pem
    fi
fi

echo "Testing SSH connection to target ($TARGET_USER@$TARGET_HOST) with $TARGET_KEY..."

if ssh -i "$TARGET_KEY" -o BatchMode=yes -o ConnectTimeout=10 "$TARGET_USER@$TARGET_HOST" "echo 'Connection successful'" 2>/dev/null; then
    print_status "SSH to target already working!"
else
    # Try opc user as fallback
    if ssh -i "$TARGET_KEY" -o BatchMode=yes -o ConnectTimeout=10 "opc@$TARGET_HOST" "echo 'Connection successful'" 2>/dev/null; then
        print_status "SSH to target working via opc user"
        print_warning "Note: ZDM may need oracle user access. Configure as needed."
    else
        print_warning "SSH to target not configured or failed"
        echo ""
        echo "For Oracle Database@Azure (Exadata) targets:"
        echo "  1. SSH to target: ssh -i $TARGET_KEY opc@$TARGET_HOST"
        echo "  2. Switch to oracle: sudo su - oracle"
        echo "  3. Configure authorized_keys as shown above"
    fi
fi

echo ""
echo "================================================================"
echo "Step 5: Verify connections"
echo "================================================================"

echo ""
echo "Final connection tests:"
echo ""

# Test source
echo -n "Source ($SOURCE_USER@$SOURCE_HOST): "
if ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=10 "$SOURCE_USER@$SOURCE_HOST" "hostname" 2>/dev/null; then
    print_status "OK"
else
    print_error "FAILED"
fi

# Test target
echo -n "Target ($TARGET_USER@$TARGET_HOST): "
if ssh -i "$TARGET_KEY" -o BatchMode=yes -o ConnectTimeout=10 "$TARGET_USER@$TARGET_HOST" "hostname" 2>/dev/null; then
    print_status "OK"
else
    # Try opc
    if ssh -i "$TARGET_KEY" -o BatchMode=yes -o ConnectTimeout=10 "opc@$TARGET_HOST" "hostname" 2>/dev/null; then
        print_warning "OK (via opc user)"
    else
        print_error "FAILED"
    fi
fi

echo ""
echo "================================================================"
echo "Configuration Summary"
echo "================================================================"
echo ""
echo "SSH Key for Source: $SSH_KEY"
echo "SSH Key for Target: $TARGET_KEY"
echo ""
echo "For ZDM migration, you will specify these keys in the response file:"
echo "  SOURCESSHKEY=$SSH_KEY"
echo "  TARGETSSHKEY=$TARGET_KEY"
echo ""
