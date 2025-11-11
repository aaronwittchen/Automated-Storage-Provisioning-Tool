#!/bin/bash
# Storage Provisioning Test Suite
# File: tests/test_provisioning.sh

set -euo pipefail

# Get the directory of this script
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(dirname "$TEST_DIR")"

# Load environment variables
if [ -f "$PROJECT_ROOT/.env" ]; then
    # Read and export variables while handling paths with spaces
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        
        # Handle each line as a key=value pair
        key="${line%%=*}"
        value="${line#*=}"
        
        # Remove any surrounding quotes
        value="${value%\"}"
        value="${value#\"}"
        value="${value%\'}"
        value="${value#\'}"
        
        # Export the variable
        export "$key"="$value"
    done < "$PROJECT_ROOT/.env"
else
    echo "ERROR: .env file not found in $PROJECT_ROOT"
    exit 1
fi

# Configuration (with .env defaults)
TEST_USER="testuser_$(date +%s)"
TEST_QUOTA="5G"
VM_HOST="${VM_HOST:-rocky-vm@192.168.68.105}"
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_ed25519}"
# Use project root as base if SCRIPT_DIR is not set
SCRIPT_DIR="${SCRIPT_DIR:-$PROJECT_ROOT/scripts}"

# Resolve paths (handle ~ and relative paths)
SSH_KEY_PATH="$(realpath -m "$SSH_KEY_PATH" 2>/dev/null || echo "$SSH_KEY_PATH")"
PASS_COUNT=0
FAIL_COUNT=0

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ============================================================================
# Test Helper Functions
# ============================================================================

test_pass() {
    local test_name=$1
    echo -e "${GREEN}✓ PASS${NC}: $test_name"
    ((PASS_COUNT++))
}

test_fail() {
    local test_name=$1
    local error_msg=${2:-"Unknown error"}
    echo -e "${RED}✗ FAIL${NC}: $test_name - $error_msg"
    ((FAIL_COUNT++))
}

test_skip() {
    local test_name=$1
    echo -e "${YELLOW}⊘ SKIP${NC}: $test_name"
}

run_remote_cmd() {
    local cmd=$1
    ssh -i "$SSH_KEY_PATH" "$VM_HOST" "$cmd"
}

# ============================================================================
# Pre-flight Checks
# ============================================================================

echo -e "${YELLOW}=== Storage Provisioning Test Suite ===${NC}"
# Debug output
echo "Environment Variables:"
echo "- VM_HOST: $VM_HOST"
echo "- SSH_KEY_PATH: $SSH_KEY_PATH"
echo "- SCRIPT_DIR: $SCRIPT_DIR"
echo "- Current directory: $(pwd)"
echo "- Home directory: $HOME"

# Check if we're running in WSL
echo -e "\n=== System Information ==="
if grep -q microsoft /proc/version 2>/dev/null; then
    echo "Running in WSL"
    echo "Windows username: $(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r')"
else
    echo "Not running in WSL"
fi
echo "Test User: $TEST_USER"
echo "Test Quota: $TEST_QUOTA"
echo ""

echo "Running pre-flight checks..."

# Check if SSH key exists
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo -e "${RED}ERROR: SSH key not found at $SSH_KEY_PATH${NC}"
    exit 1
fi

# Check key permissions
if [ "$(stat -c "%a" "$SSH_KEY_PATH" 2>/dev/null || stat -f "%Lp" "$SSH_KEY_PATH" 2>/dev/null)" -gt 600 ]; then
    echo -e "${YELLOW}WARNING: SSH key permissions are too open. Run: chmod 600 $SSH_KEY_PATH${NC}"
fi

# Check SSH connectivity
echo -e "\n=== Testing SSH Connection ==="

# Set up SSH options for automatic login
SSH_OPTS=(
    -i "$SSH_KEY_PATH"
    -o ConnectTimeout=5
    -o BatchMode=yes
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
)

# Build the full command for display
SSH_CMD=(
    ssh
    -v
    -i "$SSH_KEY_PATH"
    -o ConnectTimeout=5
    -o BatchMode=yes
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
    "$VM_HOST"
    true
)

echo "Command: ${SSH_CMD[*]}"

echo -e "\n${YELLOW}=== Debug Information ===${NC}"
echo "Current user: $(whoami)"
echo "SSH key path: $SSH_KEY_PATH"
echo "SSH key permissions: $(stat -c "%a %n" "$SSH_KEY_PATH" 2>/dev/null || stat -f "%Lp %N" "$SSH_KEY_PATH" 2>/dev/null)"
echo "SSH key content (first line): $(head -n 1 "$SSH_KEY_PATH")"

# Test basic SSH connectivity first
echo -e "\n${YELLOW}=== Testing Basic Connectivity ===${NC}"
if ! ping -c 2 "${VM_HOST#*@}" &>/dev/null; then
    echo -e "${RED}ERROR: Cannot ping ${VM_HOST#*@}. Check if the VM is running and accessible.${NC}"
    exit 1
else
    echo "✓ Host ${VM_HOST#*@} is reachable via ping"
fi

# Test SSH connection with minimal options
echo -e "\n${YELLOW}=== Testing SSH Connection (Minimal) ===${NC}"
SSH_SIMPLE_CMD=(
    ssh
    -v
    -i "$SSH_KEY_PATH"
    -o ConnectTimeout=5
    -o BatchMode=yes
    -o StrictHostKeyChecking=no
    "$VM_HOST"
    "echo 'SSH connection successful!'; exit 0"
)

echo "Running: ${SSH_SIMPLE_CMD[*]}"
"${SSH_SIMPLE_CMD[@]}"
SSH_EXIT=$?

if [ $SSH_EXIT -eq 0 ]; then
    echo -e "${GREEN}✓ SSH connection successful!${NC}"
else
    echo -e "${RED}✗ SSH connection failed with code $SSH_EXIT${NC}"
    exit 1
fi

# If we get here, the simple SSH worked, so we can proceed with the full test
SSH_OUTPUT=$("${SSH_CMD[@]}" 2>&1)
SSH_EXIT=$?

if [ $SSH_EXIT -eq 124 ]; then
    echo -e "${RED}ERROR: SSH connection timed out. Check if the VM is running and accessible.${NC}"
elif [ $SSH_EXIT -ne 0 ]; then
    echo -e "${RED}ERROR: Cannot connect to $VM_HOST (Exit code: $SSH_EXIT)${NC}"
    echo -e "${YELLOW}SSH Output:${NC}"
    echo "$SSH_OUTPUT" | grep -i -E 'error|fail|denied|authenticat|permission|refused|timeout|debug1'
    
    # Additional diagnostics
    echo -e "\n${YELLOW}=== Additional Diagnostics ===${NC}"
    echo "Checking if VM is reachable (ping):"
    ping -c 2 "${VM_HOST#*@}" 2>/dev/null || echo "Ping failed"
    
    echo -e "\nChecking SSH key permissions:"
    ls -la "$SSH_KEY_PATH"
    
    echo -e "\nTrying to connect with verbose output (first 10 lines):"
    ssh -v "${SSH_OPTS[@]}" "$VM_HOST" exit 2>&1 | head -n 10
    
    exit 1
fi
test_pass "SSH connectivity to $VM_HOST"

# Check if provision script exists
if ! run_remote_cmd "[ -f $SCRIPT_DIR/provision_user.sh ]"; then
    echo -e "${RED}ERROR: provision_user.sh not found on VM${NC}"
    exit 1
fi
test_pass "provision_user.sh exists"

# Check if deprovision script exists
if ! run_remote_cmd "[ -f $SCRIPT_DIR/deprovision_user.sh ]"; then
    echo -e "${RED}ERROR: deprovision_user.sh not found on VM${NC}"
    exit 1
fi
test_pass "deprovision_user.sh exists"

# Check sudo access
if ! run_remote_cmd "sudo true" &>/dev/null; then
    echo -e "${RED}ERROR: No sudo access on VM${NC}"
    exit 1
fi
test_pass "sudo access available"

echo ""

# ============================================================================
# Test Suite
# ============================================================================

echo -e "${YELLOW}=== Running Tests ===${NC}"
echo ""

# Test 1: Create user with provision script
echo "Test 1: Creating test user with provision script..."
if run_remote_cmd "sudo $SCRIPT_DIR/provision_user.sh $TEST_USER -q $TEST_QUOTA" &>/dev/null; then
    test_pass "User creation ($TEST_USER)"
else
    test_fail "User creation ($TEST_USER)" "provision_user.sh failed"
    exit 1
fi

# Test 2: Verify user exists
echo "Test 2: Verifying user exists..."
if run_remote_cmd "id $TEST_USER" &>/dev/null; then
    UID=$(run_remote_cmd "id -u $TEST_USER")
    test_pass "User exists (UID: $UID)"
else
    test_fail "User exists" "id $TEST_USER returned error"
fi

# Test 3: Verify home directory
echo "Test 3: Verifying home directory..."
HOME_DIR="/home/storage_users/$TEST_USER"
if run_remote_cmd "[ -d $HOME_DIR ]"; then
    PERMS=$(run_remote_cmd "stat -c '%a' $HOME_DIR")
    test_pass "Home directory exists (permissions: $PERMS)"
else
    test_fail "Home directory" "Directory not found at $HOME_DIR"
fi

# Test 4: Verify subdirectories
echo "Test 4: Verifying subdirectories..."
SUBDIRS=("data" "backups" "temp" "logs")
ALL_SUBDIRS_OK=true
for subdir in "${SUBDIRS[@]}"; do
    if run_remote_cmd "[ -d $HOME_DIR/$subdir ]"; then
        echo "  ✓ $subdir/"
    else
        echo "  ✗ $subdir/ - NOT FOUND"
        ALL_SUBDIRS_OK=false
    fi
done
if [ "$ALL_SUBDIRS_OK" = true ]; then
    test_pass "All subdirectories created"
else
    test_fail "Subdirectories" "Some subdirectories missing"
fi

# Test 5: Verify README file
echo "Test 5: Verifying README file..."
if run_remote_cmd "[ -f $HOME_DIR/README.txt ]"; then
    test_pass "README.txt created"
else
    test_fail "README.txt" "File not found"
fi

# Test 6: Verify quota was set
echo "Test 6: Verifying quota..."
if run_remote_cmd "sudo xfs_quota -x -c 'report -h' / | grep -q $TEST_USER"; then
    QUOTA_INFO=$(run_remote_cmd "sudo xfs_quota -x -c 'report -h' / | grep $TEST_USER")
    test_pass "Quota set: $QUOTA_INFO"
else
    test_fail "Quota" "User quota not found"
fi

# Test 7: Verify ownership
echo "Test 7: Verifying ownership..."
OWNER=$(run_remote_cmd "stat -c '%U:%G' $HOME_DIR")
if [ "$OWNER" = "$TEST_USER:storage_users" ]; then
    test_pass "Ownership correct ($OWNER)"
else
    test_fail "Ownership" "Expected $TEST_USER:storage_users, got $OWNER"
fi

# Test 8: Test file creation (quota enforcement)
echo "Test 8: Testing file creation in user directory..."
TEST_FILE="$HOME_DIR/data/test_file.txt"
if run_remote_cmd "sudo -u $TEST_USER bash -c 'echo \"test data\" > $TEST_FILE'" &>/dev/null; then
    if run_remote_cmd "[ -f $TEST_FILE ]"; then
        test_pass "File creation in user directory"
    else
        test_fail "File creation" "File not created"
    fi
else
    test_fail "File creation" "Permission denied"
fi

# Test 9: Verify SSH access is denied
echo "Test 9: Verifying SSH access is denied..."
if run_remote_cmd "sudo sshd -T | grep -i denyusers | grep -q $TEST_USER"; then
    test_pass "SSH access denied for user"
else
    test_fail "SSH deny rule" "User not in DenyUsers"
fi

# Test 10: Deprovision user without backup
echo "Test 10: Deprovisioning user (without backup)..."
if echo "yes" | run_remote_cmd "sudo $SCRIPT_DIR/deprovision_user.sh $TEST_USER --force" &>/dev/null; then
    test_pass "User deprovisioning"
else
    test_fail "User deprovisioning" "deprovision_user.sh failed"
fi

# Test 11: Verify user removal
echo "Test 11: Verifying user removal..."
if ! run_remote_cmd "id $TEST_USER" &>/dev/null; then
    test_pass "User successfully removed"
else
    test_fail "User removal" "User still exists"
fi

# Test 12: Verify home directory removal
echo "Test 12: Verifying home directory removal..."
if ! run_remote_cmd "[ -d $HOME_DIR ]"; then
    test_pass "Home directory removed"
else
    test_fail "Home directory removal" "Directory still exists at $HOME_DIR"
fi

# ============================================================================
# Test Summary
# ============================================================================

echo ""
echo -e "${YELLOW}=== Test Summary ===${NC}"
echo -e "Passed: ${GREEN}$PASS_COUNT${NC}"
echo -e "Failed: ${RED}$FAIL_COUNT${NC}"
echo "Total:  $((PASS_COUNT + FAIL_COUNT))"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}$FAIL_COUNT test(s) failed${NC}"
    exit 1
fi