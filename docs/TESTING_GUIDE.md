# Testing Guide - Rocky Linux VM on Proxmox

A hands-on guide to testing the Automated Storage Provisioning Tool on your Rocky Linux VM.

## Table of Contents

- [Initial Setup](#initial-setup)
- [Syncing Files to VM](#syncing-files-to-vm)
- [Testing Bash Scripts](#testing-bash-scripts)
- [Testing Puppet Manifests](#testing-puppet-manifests)
- [Testing set_quota.sh](#testing-set_quotash)
- [Testing File Transfers](#testing-file-transfers)
- [Testing Configuration](#testing-configuration)
- [Filesystem & Quota Commands](#filesystem--quota-commands)
- [Cleanup Commands](#cleanup-commands)
- [Troubleshooting](#troubleshooting)

---

## Initial Setup

### 1. Connect to Your VM

```bash
# SSH into your Rocky VM (replace with your IP)
ssh rocky-vm@192.168.68.105

# Or use Proxmox console directly
```

### 2. Verify Prerequisites

```bash
# Check OS version
cat /etc/os-release

# Check if running as root or have sudo
sudo whoami

# Check required packages
rpm -qa | grep -E "puppet|quota|xfsprogs"

# Install if missing
sudo dnf install -y puppet-agent quota xfsprogs git rsync
```

### 3. Verify Quota Support

```bash
# Check current filesystem type
df -T /

# Check mount options (look for usrquota/uquota)
mount | grep ' / '

# If quotas not enabled, check fstab
cat /etc/fstab

# Should have usrquota,grpquota like:
# /dev/mapper/rl-root  /  xfs  defaults,usrquota,grpquota  0 0
```

### 4. Enable Quotas (if not already)

```bash
# Edit fstab to add quota options
sudo vim /etc/fstab

# Add usrquota,grpquota to your root filesystem mount options
# Example: defaults,usrquota,grpquota

# Remount filesystem
sudo mount -o remount /

# Verify quotas are enabled
mount | grep ' / ' | grep -E 'usrquota|uquota'

# For XFS, quotas are enabled immediately after remount
# For EXT4, you also need:
# sudo quotacheck -cum /
# sudo quotaon /
```

---

## Syncing Files to VM

### Option A: Using sync_vm.sh (Recommended)

```bash
# On your LOCAL machine (Windows/WSL)
cd /path/to/Automated-Storage-Provisioning-Tool

# Setup config
./sync_vm.sh --setup-config

# Edit the config with your VM details
vim ~/.sync_vm.conf

# Push files to VM
./sync_vm.sh push
```

### Option B: Using rsync directly

```bash
# From local machine
rsync -avz --progress \
  --exclude='.git' \
  --exclude='logs' \
  --exclude='*.tmp' \
  ./ rocky-vm@192.168.68.105:/home/rocky-vm/storage-provisioning/
```

### Option C: Using scp

```bash
# Copy entire directory
scp -r ./* rocky-vm@192.168.68.105:/home/rocky-vm/storage-provisioning/
```

### Option D: Git clone on VM

```bash
# On the VM
cd ~
git clone https://github.com/yourusername/Automated-Storage-Provisioning-Tool.git
cd Automated-Storage-Provisioning-Tool
```

---

## Testing Bash Scripts

### 1. Make Scripts Executable

```bash
# On the VM
cd ~/storage-provisioning  # or wherever you synced

# Make all scripts executable
chmod +x scripts/*.sh

# Verify
ls -la scripts/
```

### 2. Test Utility Functions

```bash
# Source utils and check system info
source scripts/utils.sh
get_system_info

# Test validation functions
validate_username "testuser"    # Should succeed
validate_username "root"        # Should fail (reserved)
validate_username "123bad"      # Should fail (starts with number)

# Test quota validation
validate_quota "10G"    # Should succeed
validate_quota "500M"   # Should succeed
validate_quota "abc"    # Should fail

# Check quota support
validate_quota_support

# Get filesystem info
get_quota_mount "/home/storage_users"
get_filesystem_type "/"
```

### 3. Test User Provisioning

```bash
# Create a test user
sudo ./scripts/provision_user.sh testuser1

# With custom quota
sudo ./scripts/provision_user.sh testuser2 --quota 5G

# With SSH access allowed
sudo ./scripts/provision_user.sh testuser3 --quota 2G --allow-ssh

# Without subdirectories
sudo ./scripts/provision_user.sh testuser4 --no-subdirs
```

### 4. Verify Provisioning Worked

```bash
# Check user exists
id testuser1
getent passwd testuser1

# Check home directory
ls -la /home/storage_users/testuser1/

# Check subdirectories
ls -la /home/storage_users/testuser1/data/
ls -la /home/storage_users/testuser1/backups/

# Check permissions (should be 700)
stat /home/storage_users/testuser1/

# Check quota
sudo xfs_quota -x -c "quota -u testuser1" /

# Check all quotas
sudo xfs_quota -x -c "report -h" /
```

### 5. Test User Deprovisioning

```bash
# Deprovision with backup (interactive)
sudo ./scripts/deprovision_user.sh testuser1

# Deprovision with force (no confirmation)
sudo ./scripts/deprovision_user.sh testuser2 --force

# Deprovision with custom backup retention
sudo ./scripts/deprovision_user.sh testuser3 --force --keep-backup 60
```

### 6. Verify Deprovisioning

```bash
# User should not exist
id testuser1  # Should fail

# Home directory should be gone
ls /home/storage_users/testuser1  # Should fail

# Check backups were created
ls -la /var/backups/deprovisioned_users/

# View backup metadata
cat /var/backups/deprovisioned_users/testuser1_*.meta
```

---

## Testing Puppet Manifests

### 1. Validate Puppet Syntax

```bash
# Check syntax of all manifests
sudo /opt/puppetlabs/bin/puppet parser validate manifests/*.pp

# Or individually
sudo /opt/puppetlabs/bin/puppet parser validate manifests/init.pp
sudo /opt/puppetlabs/bin/puppet parser validate manifests/user.pp
sudo /opt/puppetlabs/bin/puppet parser validate manifests/decommission.pp
```

### 2. Apply Main Manifest (Dry Run)

```bash
# Dry run - see what would change
sudo /opt/puppetlabs/bin/puppet apply --noop manifests/init.pp

# With debug output
sudo /opt/puppetlabs/bin/puppet apply --noop --debug manifests/init.pp
```

### 3. Apply Main Manifest (For Real)

```bash
# Apply the init manifest
sudo /opt/puppetlabs/bin/puppet apply manifests/init.pp

# Verify directories created
ls -la /var/log/storage-provisioning/
ls -la /var/backups/deprovisioned_users/
ls -la /home/storage_users/
```

### 4. Provision User via Puppet

```bash
# Create a test manifest
cat << 'EOF' | sudo tee /tmp/test_user.pp
include storage_provisioning

storage_provisioning::user { 'puppetuser1':
  quota     => '5G',
  allow_ssh => false,
}
EOF

# Apply it (dry run first)
sudo /opt/puppetlabs/bin/puppet apply --noop /tmp/test_user.pp

# Apply for real
sudo /opt/puppetlabs/bin/puppet apply /tmp/test_user.pp

# Verify
id puppetuser1
ls -la /home/storage_users/puppetuser1/
```

### 5. Deprovision User via Puppet

```bash
# Create decommission manifest
cat << 'EOF' | sudo tee /tmp/decom_user.pp
include storage_provisioning

storage_provisioning::decommission { 'puppetuser1':
  create_backup  => true,
  retention_days => 30,
}
EOF

# Apply
sudo /opt/puppetlabs/bin/puppet apply /tmp/decom_user.pp
```

---

## Testing set_quota.sh

### 1. Check Quota Support

```bash
# Run the check command
sudo ./scripts/set_quota.sh check
```

### 2. Show User Quota

```bash
# First create a test user if needed
sudo ./scripts/provision_user.sh quotatest

# Show their quota
sudo ./scripts/set_quota.sh show quotatest
```

### 3. Set Quota

```bash
# Set basic quota
sudo ./scripts/set_quota.sh set quotatest 10G

# Set with custom soft/hard limits
sudo ./scripts/set_quota.sh set quotatest 5G --hard 6G

# Verify
sudo ./scripts/set_quota.sh show quotatest
```

### 4. Generate Quota Report

```bash
# Show all quotas
sudo ./scripts/set_quota.sh report
```

### 5. Remove Quota

```bash
# Remove quota (with confirmation)
sudo ./scripts/set_quota.sh remove quotatest

# Remove quota (forced)
sudo ./scripts/set_quota.sh remove quotatest --force
```

### 6. Test Quota Enforcement

```bash
# Set a small quota for testing
sudo ./scripts/set_quota.sh set quotatest 50M

# Switch to test user
sudo su - quotatest

# Try to create a file larger than quota
dd if=/dev/zero of=~/data/bigfile bs=1M count=100

# Should fail or warn when hitting quota limit
# Check quota status
exit  # back to your user

sudo ./scripts/set_quota.sh show quotatest
```

---

## Testing File Transfers

The `transfer.sh` script provides easy file transfer to/from user storage directories.

### 1. Basic Setup

```bash
# Make transfer script executable
chmod +x scripts/transfer.sh

# Create a test user for file transfer testing
sudo ./scripts/provision_user.sh transfertest --quota 5G --allow-ssh
```

### 2. Upload Files (Local - On the Server)

```bash
# Create a test file
echo "Hello World" > /tmp/testfile.txt
zip /tmp/testarchive.zip /tmp/testfile.txt

# Upload to user's data directory (default)
sudo ./scripts/transfer.sh upload transfertest /tmp/testfile.txt

# Upload to specific subdirectory
sudo ./scripts/transfer.sh upload transfertest /tmp/testarchive.zip backups/

# Verify upload
sudo ./scripts/transfer.sh list transfertest data/
sudo ./scripts/transfer.sh list transfertest backups/
```

### 3. Download Files (Local - On the Server)

```bash
# Download from user's storage to current directory
sudo ./scripts/transfer.sh download transfertest data/testfile.txt ./

# Download to specific directory
mkdir -p /tmp/downloads
sudo ./scripts/transfer.sh download transfertest backups/testarchive.zip /tmp/downloads/

# Verify download
ls -la /tmp/downloads/
```

### 4. Remote Transfers (From Your PC to Server)

```bash
# From your LOCAL machine (Windows/Mac/Linux)
# Replace 192.168.68.105 with your VM's IP

# Upload a file from your PC to server
./scripts/transfer.sh upload transfertest ./myreport.pdf -r rocky-vm@192.168.68.105

# Download a file from server to your PC
./scripts/transfer.sh download transfertest data/report.pdf ./ -r rocky-vm@192.168.68.105

# With SSH key authentication
./scripts/transfer.sh upload transfertest ./data.zip -r rocky-vm@192.168.68.105 -k ~/.ssh/id_rsa
```

### 5. Sync Directories

```bash
# Create a test directory with files
mkdir -p /tmp/project
echo "File 1" > /tmp/project/file1.txt
echo "File 2" > /tmp/project/file2.txt
echo "File 3" > /tmp/project/file3.txt

# Sync local directory TO user's storage (upload)
sudo ./scripts/transfer.sh sync-up transfertest /tmp/project/ data/project/

# Verify
sudo ./scripts/transfer.sh list transfertest data/project/

# Modify files and sync again (only changes transfer)
echo "Updated" >> /tmp/project/file1.txt
sudo ./scripts/transfer.sh sync-up transfertest /tmp/project/ data/project/

# Sync FROM user's storage to local (download)
mkdir -p /tmp/downloaded-project
sudo ./scripts/transfer.sh sync-down transfertest data/project/ /tmp/downloaded-project/

# Verify
ls -la /tmp/downloaded-project/
```

### 6. Check Disk Usage

```bash
# Show usage breakdown for user
sudo ./scripts/transfer.sh usage transfertest

# Expected output shows:
# - Per-subdirectory usage
# - Total usage
# - Quota information (if available)
```

### 7. Dry Run Mode

```bash
# Preview what would be transferred (without actually doing it)
sudo ./scripts/transfer.sh upload transfertest /tmp/bigfile.zip --dry-run

# Preview sync operations
sudo ./scripts/transfer.sh sync-up transfertest /tmp/project/ --dry-run
```

### 8. Remote Transfer from Your PC (Complete Example)

```bash
# On your LOCAL machine (not the VM)

# Step 1: Make sure you have SSH access
ssh rocky-vm@192.168.68.105 "echo 'SSH works!'"

# Step 2: Copy the transfer.sh script to your local machine
scp rocky-vm@192.168.68.105:~/storage-provisioning/scripts/transfer.sh ./

# Step 3: Upload files to a user's storage
./transfer.sh upload alice ./quarterly-report.pdf -r rocky-vm@192.168.68.105
./transfer.sh upload alice ./project-backup.zip backups/ -r rocky-vm@192.168.68.105

# Step 4: Download files from user's storage
./transfer.sh download alice data/results.csv ./ -r rocky-vm@192.168.68.105

# Step 5: Sync entire project folder
./transfer.sh sync-up alice ./my-project/ data/project/ -r rocky-vm@192.168.68.105 --compress

# Step 6: List remote files
./transfer.sh list alice data/ -r rocky-vm@192.168.68.105
```

### 9. Cleanup Transfer Test

```bash
# Remove test user when done
sudo ./scripts/deprovision_user.sh transfertest --force

# Clean up temp files
rm -rf /tmp/testfile.txt /tmp/testarchive.zip /tmp/project /tmp/downloads /tmp/downloaded-project
```

---

## Testing Configuration

### 1. View Current Configuration

```bash
# Source and print config
source scripts/config.sh
print_config
```

### 2. Test Configuration Override

```bash
# Override via environment variable
export DEFAULT_QUOTA="20G"
export STORAGE_BASE="/data/users"
source scripts/config.sh
print_config

# Reset
unset DEFAULT_QUOTA STORAGE_BASE
```

### 3. Create System Config File

```bash
# Create config directory
sudo mkdir -p /etc/storage-provisioning

# Create config file
sudo tee /etc/storage-provisioning/config.conf << 'EOF'
# System-wide storage provisioning configuration
STORAGE_BASE="/home/storage_users"
DEFAULT_QUOTA="15G"
BACKUP_RETENTION_DAYS=60
ENABLE_AUDIT=true
EOF

# Test it loads
source scripts/config.sh
print_config
```

### 4. Validate Configuration

```bash
source scripts/config.sh
validate_config
echo "Exit code: $?"
```

---

## Filesystem & Quota Commands

### XFS Quota Commands

```bash
# Report all user quotas
sudo xfs_quota -x -c "report -h" /

# Show specific user quota
sudo xfs_quota -x -c "quota -u testuser1" /

# Set quota (soft and hard)
sudo xfs_quota -x -c "limit bsoft=5G bhard=6G testuser1" /

# Remove quota
sudo xfs_quota -x -c "limit bsoft=0 bhard=0 testuser1" /

# Show free space
sudo xfs_quota -x -c "df -h" /

# Show project quotas (if used)
sudo xfs_quota -x -c "report -p" /
```

### EXT4 Quota Commands (if using EXT4)

```bash
# Check quota status
sudo quotaon -p /

# Report all quotas
sudo repquota -a

# Show user quota
sudo quota -u testuser1

# Set quota (in KB)
sudo setquota -u testuser1 5242880 6291456 0 0 /

# Remove quota
sudo setquota -u testuser1 0 0 0 0 /
```

### General Disk Commands

```bash
# Check filesystem type
df -T /

# Check disk usage by directory
du -sh /home/storage_users/*

# Check inode usage
df -i /

# Find large files
find /home/storage_users -size +100M -exec ls -lh {} \;
```

---

## Cleanup Commands

### Remove Test Users

```bash
# List storage users
ls /home/storage_users/

# Remove all test users (careful!)
for user in testuser1 testuser2 testuser3 testuser4 quotatest puppetuser1; do
    sudo ./scripts/deprovision_user.sh "$user" --force 2>/dev/null || true
done
```

### Clean Logs

```bash
# View logs
sudo tail -50 /var/log/storage-provisioning/provisioning.log

# Clear logs (if needed)
sudo truncate -s 0 /var/log/storage-provisioning/provisioning.log
```

### Clean Backups

```bash
# List backups
ls -la /var/backups/deprovisioned_users/

# Remove old backups (older than 7 days for testing)
sudo find /var/backups/deprovisioned_users/ -name "*.tar.gz" -mtime +7 -delete
```

### Reset Everything

```bash
# WARNING: This removes all provisioned users and data!
# Stop if storage_users group has real users

# Remove all users in storage_users group
for user in $(getent group storage_users | cut -d: -f4 | tr ',' ' '); do
    sudo ./scripts/deprovision_user.sh "$user" --force
done

# Clean directories
sudo rm -rf /home/storage_users/*
sudo rm -rf /var/backups/deprovisioned_users/*
sudo truncate -s 0 /var/log/storage-provisioning/*.log
```

---

## Troubleshooting

### Common Issues

#### "Quotas not enabled"

```bash
# Check current mount options
mount | grep ' / '

# If missing usrquota, edit fstab
sudo vim /etc/fstab
# Add: usrquota,grpquota to options

# Remount
sudo mount -o remount /

# Verify
mount | grep ' / ' | grep quota
```

#### "Permission denied" running scripts

```bash
# Make executable
chmod +x scripts/*.sh

# Run with sudo
sudo ./scripts/provision_user.sh username
```

#### "User already exists"

```bash
# Check if user exists
id username

# Remove if needed (without our script)
sudo userdel -r username
```

#### Puppet "Could not find class"

```bash
# Check module path
sudo /opt/puppetlabs/bin/puppet config print modulepath

# Copy manifests to proper location
sudo mkdir -p /etc/puppetlabs/code/environments/production/modules/storage_provisioning/manifests
sudo cp manifests/*.pp /etc/puppetlabs/code/environments/production/modules/storage_provisioning/manifests/

# Copy templates
sudo mkdir -p /etc/puppetlabs/code/environments/production/modules/storage_provisioning/templates
sudo cp templates/*.epp /etc/puppetlabs/code/environments/production/modules/storage_provisioning/templates/
```

#### SSH connection issues (for sync)

```bash
# Test SSH connection
ssh -v rocky-vm@192.168.68.105

# Check SSH key
ls -la ~/.ssh/

# Copy SSH key to VM
ssh-copy-id rocky-vm@192.168.68.105

# Test passwordless login
ssh rocky-vm@192.168.68.105 "echo 'SSH works!'"
```

### Useful Debug Commands

```bash
# Watch provisioning log in real-time
sudo tail -f /var/log/storage-provisioning/provisioning.log

# Check system logs for errors
sudo journalctl -xe | grep -i quota

# Check audit logs (if enabled)
sudo ausearch -k storage_access

# Puppet debug mode
sudo /opt/puppetlabs/bin/puppet apply --debug --trace manifests/init.pp
```

---

## Quick Test Sequence

Run this sequence to quickly verify everything works:

```bash
#!/bin/bash
# Quick test script - run on VM

echo "=== Testing Storage Provisioning ==="

# 1. Setup
cd ~/storage-provisioning
chmod +x scripts/*.sh

# 2. Check quota support
echo -e "\n>>> Checking quota support..."
sudo ./scripts/set_quota.sh check

# 3. Provision test user
echo -e "\n>>> Provisioning test user..."
sudo ./scripts/provision_user.sh quicktest --quota 1G

# 4. Verify user
echo -e "\n>>> Verifying user..."
id quicktest
ls -la /home/storage_users/quicktest/

# 5. Check quota
echo -e "\n>>> Checking quota..."
sudo ./scripts/set_quota.sh show quicktest

# 6. Modify quota
echo -e "\n>>> Modifying quota..."
sudo ./scripts/set_quota.sh set quicktest 2G
sudo ./scripts/set_quota.sh show quicktest

# 7. Cleanup
echo -e "\n>>> Cleaning up..."
sudo ./scripts/deprovision_user.sh quicktest --force

# 8. Verify cleanup
echo -e "\n>>> Verifying cleanup..."
id quicktest 2>&1 || echo "User removed successfully"
ls /home/storage_users/quicktest 2>&1 || echo "Directory removed successfully"

echo -e "\n=== All tests completed ==="
```

Save as `quick_test.sh` and run:

```bash
chmod +x quick_test.sh
./quick_test.sh
```

---

## Next Steps

After testing, consider:

1. **Set up cron monitoring**: Check `/etc/cron.d/` for quota alerts
2. **Configure log rotation**: Verify `/etc/logrotate.d/storage-provisioning`
3. **Test batch provisioning**: Create multiple users from a file
4. **Set up Puppet agent**: For automated provisioning across nodes
5. **Integrate with your workflow**: Connect to LDAP, add API, etc.
