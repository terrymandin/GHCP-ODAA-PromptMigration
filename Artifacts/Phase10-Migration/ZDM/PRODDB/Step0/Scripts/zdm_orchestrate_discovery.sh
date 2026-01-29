#!/bin/bash
#===============================================================================
# ZDM Orchestrate Discovery Script
# Project: PRODDB Migration to Oracle Database@Azure
# Generated: 2026-01-29
#
# This script orchestrates discovery across all servers:
# - Source: proddb01.corp.example.com
# - Target: proddb-oda.eastus.azure.example.com
# - ZDM:    zdm-jumpbox.corp.example.com
#===============================================================================

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

#===============================================================================
# Configuration - Update these values for your environment
#===============================================================================

# Server hostnames
SOURCE_HOST="10.1.0.10"
TARGET_HOST="10.0.1.160"
ZDM_HOST="10.1.0.8"

# SSH users
SOURCE_USER="temandin"
TARGET_USER="opc"
ZDM_USER="azureuser"

# SSH key paths (separate keys for each security domain)
SOURCE_SSH_KEY="~/.ssh/iaas.pem"
TARGET_SSH_KEY="~/.ssh/odaa.pem"
ZDM_SSH_KEY="~/.ssh/zdm.pem"

# SSH options
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"

# Local output directory
OUTPUT_DIR="./discovery_results_$(date +%Y%m%d_%H%M%S)"

# Script directory (where discovery scripts are located)
SCRIPT_DIR="$(dirname "$0")"

#===============================================================================
# Functions
#===============================================================================

print_header() {
    echo -e "\n${BLUE}===============================================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${BLUE}===============================================================================${NC}"
}

print_section() {
    echo -e "\n${GREEN}>>> $1${NC}"
}

print_info() {
    echo -e "${YELLOW}$1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ ERROR: $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ WARNING: $1${NC}"
}

#===============================================================================
# Usage
#===============================================================================

usage() {
    echo -e "${CYAN}ZDM Orchestrate Discovery Script${NC}"
    echo -e "${CYAN}Project: PRODDB Migration to Oracle Database@Azure${NC}"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help       Show this help message"
    echo "  -c, --config     Display current configuration"
    echo "  -t, --test       Test SSH connectivity only (do not run discovery)"
    echo "  -s, --source     Run discovery on source only"
    echo "  -T, --target     Run discovery on target only"
    echo "  -z, --zdm        Run discovery on ZDM server only"
    echo "  -o, --output DIR Specify output directory (default: ./discovery_results_<timestamp>)"
    echo ""
    echo "Examples:"
    echo "  $0                    # Run full discovery on all servers"
    echo "  $0 -t                 # Test connectivity only"
    echo "  $0 -s                 # Run source discovery only"
    echo "  $0 -o /tmp/discovery  # Specify custom output directory"
    echo ""
    echo "Configuration:"
    echo "  Edit the configuration section at the top of this script to update:"
    echo "  - Server hostnames (SOURCE_HOST, TARGET_HOST, ZDM_HOST)"
    echo "  - SSH users (SOURCE_USER, TARGET_USER, ZDM_USER)"
    echo "  - SSH keys (SOURCE_SSH_KEY, TARGET_SSH_KEY, ZDM_SSH_KEY)"
    exit 0
}

show_config() {
    print_header "Current Configuration"
    echo ""
    echo -e "${MAGENTA}Source Database:${NC}"
    echo "  Host:     $SOURCE_HOST"
    echo "  User:     $SOURCE_USER"
    echo "  SSH Key:  $SOURCE_SSH_KEY"
    echo ""
    echo -e "${MAGENTA}Target Database (Oracle Database@Azure):${NC}"
    echo "  Host:     $TARGET_HOST"
    echo "  User:     $TARGET_USER"
    echo "  SSH Key:  $TARGET_SSH_KEY"
    echo ""
    echo -e "${MAGENTA}ZDM Server:${NC}"
    echo "  Host:     $ZDM_HOST"
    echo "  User:     $ZDM_USER"
    echo "  SSH Key:  $ZDM_SSH_KEY"
    echo ""
    echo -e "${MAGENTA}Output Directory:${NC}"
    echo "  $OUTPUT_DIR"
    echo ""
    exit 0
}

validate_config() {
    print_section "Validating Configuration"
    
    local errors=0
    
    # Check if SSH keys exist
    for key_path in "$SOURCE_SSH_KEY" "$TARGET_SSH_KEY" "$ZDM_SSH_KEY"; do
        expanded_path=$(eval echo "$key_path")
        if [ ! -f "$expanded_path" ]; then
            print_error "SSH key not found: $key_path"
            errors=$((errors + 1))
        else
            print_success "SSH key exists: $key_path"
        fi
    done
    
    # Check if discovery scripts exist
    for script in "zdm_source_discovery.sh" "zdm_target_discovery.sh" "zdm_server_discovery.sh"; do
        if [ ! -f "$SCRIPT_DIR/$script" ]; then
            print_error "Discovery script not found: $SCRIPT_DIR/$script"
            errors=$((errors + 1))
        else
            print_success "Script exists: $script"
        fi
    done
    
    if [ $errors -gt 0 ]; then
        print_error "Configuration validation failed with $errors error(s)"
        return 1
    fi
    
    print_success "Configuration validation passed"
    return 0
}

test_connectivity() {
    print_section "Testing SSH Connectivity"
    
    local all_passed=true
    
    # Test source
    echo -e "\n${MAGENTA}Testing Source ($SOURCE_HOST)...${NC}"
    if ssh $SSH_OPTS -i "$(eval echo $SOURCE_SSH_KEY)" "$SOURCE_USER@$SOURCE_HOST" "echo 'Connection successful'" 2>/dev/null; then
        print_success "Source connection successful"
    else
        print_error "Cannot connect to source: $SOURCE_USER@$SOURCE_HOST"
        all_passed=false
    fi
    
    # Test target
    echo -e "\n${MAGENTA}Testing Target ($TARGET_HOST)...${NC}"
    if ssh $SSH_OPTS -i "$(eval echo $TARGET_SSH_KEY)" "$TARGET_USER@$TARGET_HOST" "echo 'Connection successful'" 2>/dev/null; then
        print_success "Target connection successful"
    else
        print_error "Cannot connect to target: $TARGET_USER@$TARGET_HOST"
        all_passed=false
    fi
    
    # Test ZDM
    echo -e "\n${MAGENTA}Testing ZDM ($ZDM_HOST)...${NC}"
    if ssh $SSH_OPTS -i "$(eval echo $ZDM_SSH_KEY)" "$ZDM_USER@$ZDM_HOST" "echo 'Connection successful'" 2>/dev/null; then
        print_success "ZDM connection successful"
    else
        print_error "Cannot connect to ZDM: $ZDM_USER@$ZDM_HOST"
        all_passed=false
    fi
    
    if [ "$all_passed" = true ]; then
        print_success "All connectivity tests passed"
        return 0
    else
        print_error "Some connectivity tests failed"
        return 1
    fi
}

run_discovery() {
    local host=$1
    local user=$2
    local ssh_key=$3
    local script=$4
    local script_name=$(basename "$script")
    local target_type=$5
    
    print_section "Running Discovery on $target_type ($host)"
    
    # Expand SSH key path
    local expanded_key=$(eval echo "$ssh_key")
    
    # Create temp directory on remote host
    echo "Creating temporary directory..."
    ssh $SSH_OPTS -i "$expanded_key" "$user@$host" "mkdir -p /tmp/zdm_discovery" 2>/dev/null
    
    # Copy script to remote host
    echo "Copying discovery script..."
    scp $SSH_OPTS -i "$expanded_key" "$script" "$user@$host:/tmp/zdm_discovery/" 2>/dev/null
    if [ $? -ne 0 ]; then
        print_error "Failed to copy script to $host"
        return 1
    fi
    
    # Execute script on remote host
    echo "Executing discovery script..."
    ssh $SSH_OPTS -i "$expanded_key" "$user@$host" "chmod +x /tmp/zdm_discovery/$script_name && /tmp/zdm_discovery/$script_name" 2>/dev/null
    if [ $? -ne 0 ]; then
        print_error "Failed to execute script on $host"
        return 1
    fi
    
    # Collect results
    echo "Collecting results..."
    mkdir -p "$OUTPUT_DIR/$target_type"
    
    # Find and copy the discovery output files
    ssh $SSH_OPTS -i "$expanded_key" "$user@$host" "ls -t /tmp/zdm_${target_type}_discovery_*.txt 2>/dev/null | head -1" | while read file; do
        if [ -n "$file" ]; then
            scp $SSH_OPTS -i "$expanded_key" "$user@$host:$file" "$OUTPUT_DIR/$target_type/" 2>/dev/null
            print_success "Collected: $(basename $file)"
        fi
    done
    
    ssh $SSH_OPTS -i "$expanded_key" "$user@$host" "ls -t /tmp/zdm_${target_type}_discovery_*.json 2>/dev/null | head -1" | while read file; do
        if [ -n "$file" ]; then
            scp $SSH_OPTS -i "$expanded_key" "$user@$host:$file" "$OUTPUT_DIR/$target_type/" 2>/dev/null
            print_success "Collected: $(basename $file)"
        fi
    done
    
    print_success "Discovery complete for $target_type"
    return 0
}

#===============================================================================
# Parse Arguments
#===============================================================================

RUN_SOURCE=true
RUN_TARGET=true
RUN_ZDM=true
TEST_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -c|--config)
            show_config
            ;;
        -t|--test)
            TEST_ONLY=true
            shift
            ;;
        -s|--source)
            RUN_SOURCE=true
            RUN_TARGET=false
            RUN_ZDM=false
            shift
            ;;
        -T|--target)
            RUN_SOURCE=false
            RUN_TARGET=true
            RUN_ZDM=false
            shift
            ;;
        -z|--zdm)
            RUN_SOURCE=false
            RUN_TARGET=false
            RUN_ZDM=true
            shift
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            ;;
    esac
done

#===============================================================================
# Main Script
#===============================================================================

print_header "ZDM Orchestrate Discovery"
print_info "Project: PRODDB Migration to Oracle Database@Azure"
print_info "Started: $(date)"

# Validate configuration
validate_config
if [ $? -ne 0 ]; then
    exit 1
fi

# Test connectivity
test_connectivity
if [ $? -ne 0 ]; then
    print_error "Connectivity tests failed. Please resolve before continuing."
    exit 1
fi

# If test only mode, exit here
if [ "$TEST_ONLY" = true ]; then
    print_header "Test Mode Complete"
    exit 0
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"
print_info "Output directory: $OUTPUT_DIR"

# Run discovery on each server
ERRORS=0

if [ "$RUN_SOURCE" = true ]; then
    run_discovery "$SOURCE_HOST" "$SOURCE_USER" "$SOURCE_SSH_KEY" "$SCRIPT_DIR/zdm_source_discovery.sh" "source"
    [ $? -ne 0 ] && ERRORS=$((ERRORS + 1))
fi

if [ "$RUN_TARGET" = true ]; then
    run_discovery "$TARGET_HOST" "$TARGET_USER" "$TARGET_SSH_KEY" "$SCRIPT_DIR/zdm_target_discovery.sh" "target"
    [ $? -ne 0 ] && ERRORS=$((ERRORS + 1))
fi

if [ "$RUN_ZDM" = true ]; then
    run_discovery "$ZDM_HOST" "$ZDM_USER" "$ZDM_SSH_KEY" "$SCRIPT_DIR/zdm_server_discovery.sh" "server"
    [ $? -ne 0 ] && ERRORS=$((ERRORS + 1))
fi

#===============================================================================
# Summary
#===============================================================================

print_header "Discovery Summary"

echo ""
echo -e "${MAGENTA}Output Directory:${NC} $OUTPUT_DIR"
echo ""

echo -e "${MAGENTA}Collected Files:${NC}"
find "$OUTPUT_DIR" -type f -name "*.txt" -o -name "*.json" 2>/dev/null | while read file; do
    echo "  - $file"
done

echo ""
if [ $ERRORS -eq 0 ]; then
    print_success "All discovery tasks completed successfully"
    echo ""
    echo -e "${CYAN}Next Steps:${NC}"
    echo "  1. Review discovery reports in: $OUTPUT_DIR"
    echo "  2. Copy outputs to: Artifacts/Phase10-Migration/ZDM/PRODDB/Step0/Discovery/"
    echo "  3. Proceed to Step 1: Complete the Discovery Questionnaire"
else
    print_error "$ERRORS discovery task(s) failed"
    echo "Review the errors above and retry failed discoveries."
fi

print_info "Completed: $(date)"

exit $ERRORS
