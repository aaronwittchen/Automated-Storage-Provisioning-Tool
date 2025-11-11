#!/bin/bash
set -x  # Enable debug output

# Load environment variables
if [ -f .env ]; then
    source .env
else
    echo "ERROR: .env file not found"
    exit 1
fi

# Set defaults if not set in .env
VM_HOST="${VM_HOST:-rocky-vm@192.168.68.105}"
SSH_KEY_PATH="${SSH_KEY_PATH:-~/.ssh/id_ed25519}"

# Resolve tilde in path
SSH_KEY_PATH="${SSH_KEY_PATH/#\~/$HOME}"

echo "Testing SSH connection to $VM_HOST with key $SSH_KEY_PATH"

# Check if key exists
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "ERROR: SSH key not found at $SSH_KEY_PATH"
    echo "Trying to list .ssh directory..."
    ls -la ~/.ssh/ || echo "Could not list .ssh directory"
    exit 1
fi

# Test SSH connection with verbose output
echo "=== Testing SSH connection with verbose output ==="
ssh -v -i "$SSH_KEY_PATH" -o ConnectTimeout=5 "$VM_HOST" 'echo "SSH connection successful!"' 2>&1 | grep -i -E 'error|fail|denied|authenticat|permission|refused|timeout'

# If the above fails, try with password authentication disabled
echo -e "\n=== Testing SSH connection with password authentication disabled ==="
ssh -v -o PreferredAuthentications=publickey -o PasswordAuthentication=no -i "$SSH_KEY_PATH" -o ConnectTimeout=5 "$VM_HOST" 'echo "SSH connection successful!"' 2>&1 | grep -i -E 'error|fail|denied|authenticat|permission|refused|timeout'
