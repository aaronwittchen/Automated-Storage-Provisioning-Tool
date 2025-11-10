
---

## **Phase 2: Project Structure Setup**

### **Step 5: Create Project Directory on Host**

```bash
# Create main project folder
mkdir -p ~/projects/storage-provisioning
cd ~/projects/storage-provisioning

# Create subdirectories
mkdir -p {manifests,scripts,docs,tests,logs}

# Create initial files
touch README.md
touch docs/architecture.md
touch docs/usage.md
```

**Directory structure:**
```
storage-provisioning/
├── manifests/          # Puppet manifests
│   ├── init.pp
│   ├── user.pp
│   └── cleanup.pp
├── scripts/            # Bash scripts
│   ├── provision_user.sh
│   ├── set_quota.sh
│   ├── deprovision_user.sh
│   └── utils.sh
├── docs/               # Documentation
│   ├── architecture.md
│   ├── usage.md
│   └── testing.md
├── tests/              # Test cases
│   └── test_provisioning.sh
├── logs/               # Local logs (for reference)
└── README.md
```

---

### **Step 6: Initialize Git Repository**

```bash
cd ~/projects/storage-provisioning

# Initialize Git
git init

# Create .gitignore
cat > .gitignore << 'EOF'
# Logs
logs/
*.log

# Temporary files
*.tmp
*.swp
*~

# Sensitive data
*.key
*.pem
secrets/

# OS files
.DS_Store
Thumbs.db
EOF

# Initial commit
git add .
git commit -m "Initial project structure"

# Optional: Create GitHub repo and push
# git remote add origin <your-repo-url>
# git push -u origin main
```

---

## **Phase 3: Development Workflow**

### **Step 7: Set Up File Transfer Method**

**Option B: Use rsync (Better, syncs only changes)**

```bash
# Install rsync on both host and VM
# On VM:
ssh storage-vm 'sudo dnf install -y rsync'

# Create sync script on host
cat > sync.sh << 'EOF'
#!/bin/bash
rsync -avz --exclude '.git' --exclude 'logs' \
  ~/projects/storage-provisioning/ \
  storage-vm:/home/admin/storage-provisioning/
EOF

chmod +x sync.sh

# Use it
./sync.sh
```

1. Open WSL

Press Win + R, type wsl, and press Enter

Or open Ubuntu/your WSL distro from the Start menu

2. Navigate to your project folder

Your Windows files are mounted under /mnt/c/, so your Desktop folder is:

cd /mnt/c/Users/theon/Desktop/Automated\ Storage\ Provisioning\ Tool


Note the backslash \ before the space in the folder name.

3. Make sure sync.sh is executable
chmod +x sync.sh

4. Run the script
./sync.sh

---

### **Step 8: Create Core Scripts**

**A. Utility Functions (`scripts/utils.sh`):**

```bash
#!/bin/bash

# Logging function
LOG_DIR="/var/log/storage-provisioning"
LOG_FILE="$LOG_DIR/provisioning.log"

log() {
    local level=$1
    shift
    local message="$@"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $message" | sudo tee -a "$LOG_FILE"
}

# Validation functions
validate_username() {
    local username=$1
    if [[ ! "$username" =~ ^[a-z][a-z0-9_-]{2,15}$ ]]; then
        log "ERROR" "Invalid username: $username"
        return 1
    fi
    return 0
}

validate_quota() {
    local quota=$1
    if [[ ! "$quota" =~ ^[0-9]+[MGT]?$ ]]; then
        log "ERROR" "Invalid quota format: $quota"
        return 1
    fi
    return 0
}

# Check if user exists
user_exists() {
    local username=$1
    id "$username" &>/dev/null
}
```

**B. User Provisioning Script (`scripts/provision_user.sh`):**

```bash
#!/bin/bash

# Source utility functions
source "$(dirname "$0")/utils.sh"

# Configuration
STORAGE_BASE="/home/storage_users"
DEFAULT_QUOTA="10G"
DEFAULT_GROUP="storage_users"

# Parse arguments
USERNAME=$1
QUOTA=${2:-$DEFAULT_QUOTA}

# Validation
if [ -z "$USERNAME" ]; then
    echo "Usage: $0 <username> [quota]"
    exit 1
fi

validate_username "$USERNAME" || exit 1
validate_quota "$QUOTA" || exit 1

# Check if user already exists
if user_exists "$USERNAME"; then
    log "ERROR" "User $USERNAME already exists"
    exit 1
fi

log "INFO" "Starting provisioning for user: $USERNAME"

# Create group if it doesn't exist
if ! getent group "$DEFAULT_GROUP" > /dev/null; then
    sudo groupadd "$DEFAULT_GROUP"
    log "INFO" "Created group: $DEFAULT_GROUP"
fi

# Create user
sudo useradd -m -d "$STORAGE_BASE/$USERNAME" -g "$DEFAULT_GROUP" -s /bin/bash "$USERNAME"
log "INFO" "Created user: $USERNAME"

# Set initial password (user should change)
echo "$USERNAME:ChangeMe123!" | sudo chpasswd
sudo chage -d 0 "$USERNAME"  # Force password change on first login
log "INFO" "Set temporary password for $USERNAME"

# Set directory permissions
sudo chmod 700 "$STORAGE_BASE/$USERNAME"
log "INFO" "Set permissions for $STORAGE_BASE/$USERNAME"

# Set quota
sudo xfs_quota -x -c "limit bsoft=${QUOTA} bhard=${QUOTA} $USERNAME" /
log "INFO" "Set quota $QUOTA for $USERNAME"

# Create subdirectories
sudo -u "$USERNAME" mkdir -p "$STORAGE_BASE/$USERNAME"/{data,backups,temp}
log "INFO" "Created subdirectories for $USERNAME"

echo "User $USERNAME provisioned successfully"
echo "   Directory: $STORAGE_BASE/$USERNAME"
echo "   Quota: $QUOTA"
echo "   Temporary password: ChangeMe123!"
```

**C. Deprovisioning Script (`scripts/deprovision_user.sh`):**

```bash
#!/bin/bash

source "$(dirname "$0")/utils.sh"

USERNAME=$1

if [ -z "$USERNAME" ]; then
    echo "Usage: $0 <username>"
    exit 1
fi

if ! user_exists "$USERNAME"; then
    log "ERROR" "User $USERNAME does not exist"
    exit 1
fi

read -p "Are you sure you want to delete user $USERNAME and all data? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted"
    exit 0
fi

log "INFO" "Starting deprovisioning for user: $USERNAME"

# Remove quota
sudo xfs_quota -x -c "limit bsoft=0 bhard=0 $USERNAME" / 2>/dev/null
log "INFO" "Removed quota for $USERNAME"

# Kill user processes
sudo pkill -u "$USERNAME"
log "INFO" "Killed processes for $USERNAME"

# Delete user and home directory
sudo userdel -r "$USERNAME"
log "INFO" "Deleted user $USERNAME and home directory"

echo "User $USERNAME deprovisioned successfully"
```

Perfect! Here's your complete testing workflow:

## 🚀 Step-by-Step Testing Guide

### **1. Sync Files to VM**
```bash
# On your host machine
cd ~/projects/storage-provisioning
chmod +x sync.sh
./sync.sh
```

### **2. SSH into VM and Setup**
```bash
# SSH into VM
ssh storage-vm

# Navigate to synced files
cd ~/storage-provisioning/scripts

# Make scripts executable
chmod +x provision_user.sh deprovision_user.sh
chmod 644 utils.sh

# Create log directory
sudo mkdir -p /var/log/storage-provisioning
sudo chmod 755 /var/log/storage-provisioning
```

### **3. Pre-flight Check (IMPORTANT!)**
```bash
# Check if quotas are enabled on your filesystem
mount | grep ' / '

# If you DON'T see "usrquota" or "uquota" in the output:
# You need to enable quotas first (this is critical!)
```

**If quotas are NOT enabled, do this once:**
```bash
# Edit fstab
sudo nano /etc/fstab

# Find the line for / (root filesystem), change from:
# UUID=xxx / xfs defaults 0 0
# To:
# UUID=xxx / xfs defaults,usrquota,grpquota 0 0

# Remount
sudo mount -o remount /

# Verify
mount | grep ' / '
# Should now show: rw,usrquota,grpquota
```

### **4. Test Provision Script**
```bash
# Test with help
sudo ./provision_user.sh --help

# Create a test user with 5GB quota
sudo ./provision_user.sh testuser01 -q 5G

# You should see:
# - Green [INFO] messages
# - A temporary password (SAVE IT!)
# - Success message with user details
```

### **5. Verify User Creation**
```bash
# Check user exists
id testuser01

# Check home directory
ls -la /home/storage_users/testuser01

# Check quota
sudo xfs_quota -x -c "report -h" /
# Should show testuser01 with 5G limit

# Check subdirectories
ls -la /home/storage_users/testuser01/
# Should see: data, backups, temp, logs, README.txt
```

### **6. Test User Login (Optional)**
```bash
# Try switching to the user
sudo su - testuser01

# You'll be forced to change password
# Enter the temporary password shown during provisioning
# Set a new password

# Check you're in the right place
pwd  # Should be /home/storage_users/testuser01
ls   # Should see data, backups, temp, logs

Exactly — now you’ve switched into `testuser01` with `sudo su - testuser01`. This is the **proper way to test the user environment** and quotas because the user owns the home directory.

From here you can:

1. Check the current directory:

```bash
pwd
ls -la
```

2. Create some files to see quota usage:

```bash
dd if=/dev/zero of=testfile bs=1M count=100
```

3. Check your quota for `testuser01`:

```bash
xfs_quota -x -c "report -h" /
```
sudo -u testuser01 quota -s
This will show how much of the 5G quota is used.

4. Exit back to `rocky-vm`:

```bash
exit
```

This confirms the quota enforcement and proper permissions for the user.

Do you want me to give a **quick script to automate testing multiple users and their quotas**?

# Exit back to admin
exit
```

### **7. Test Deprovision with Backup**
```bash
# Create some test data first
sudo -u testuser01 bash -c 'echo "test data" > /home/storage_users/testuser01/data/test.txt'

# Deprovision with backup
sudo ./deprovision_user.sh testuser01 --backup

# Type 'yes' when prompted

# Verify backup was created
ls -lh /var/backups/deprovisioned_users/
# Should see testuser01_TIMESTAMP.tar.gz
[rocky-vm@storage-server scripts]$ ls -ld /var/backups/deprovisioned_users
drwx------. 2 root root 93 Nov  5 22:18 /var/backups/deprovisioned_users
[rocky-vm@storage-server scripts]$ sudo ls -lh /var/backups/deprovisioned_users/
total 108K
-rw-r--r--. 1 root root 101K Nov  5 22:18 testuser01_20251105_221839.tar.gz
-rw-------. 1 root root  250 Nov  5 22:18 testuser01_20251105_221839.tar.gz.meta
[rocky-vm@storage-server scripts]$ sudo ls -lh /var/backups/deprovisioned_users/
total 108K
-rw-r--r--. 1 root root 101K Nov  5 22:18 testuser01_20251105_221839.tar.gz
-rw-------. 1 root root  250 Nov  5 22:18 testuser01_20251105_221839.tar.gz.meta
[rocky-vm@storage-server scripts]$ sudo tree /var/backups/deprovisioned_users/
/var/backups/deprovisioned_users/
├── testuser01_20251105_221839.tar.gz
└── testuser01_20251105_221839.tar.gz.meta

0 directories, 2 files
# Check backup metadata
cat /var/backups/deprovisioned_users/testuser01_*.meta

# Verify user is gone
id testuser01  # Should fail with "no such user"
ls /home/storage_users/testuser01  # Should not exist
[rocky-vm@storage-server scripts]$ sudo cat /var/backups/deprovisioned_users/testuser01_20251105_221839.tar.gz.meta
Username: testuser01
UID: 1002
GID: 1002
Groups: storage_users
Home Directory: /home/storage_users/testuser01
Disk Usage: 101M
Backup Date: Wed Nov  5 10:18:40 PM CET 2025
Backup Size: 101K
Retention: 30 days
Expires: Fri Dec  5 10:18:40 PM CET 2025
[rocky-vm@storage-server scripts]$
```
[rocky-vm@storage-server scripts]$ sudo ./deprovision_user.sh testuser01 --backup
[INFO] Running pre-flight checks...
[WARN] =========================================
[WARN] DEPROVISIONING USER: testuser01
[WARN] =========================================

This action will:
  - Kill all processes owned by testuser01
  - Remove disk quota
  - Delete user account
  - Delete home directory: /home/storage_users/testuser01
  - Create backup before deletion

⚠️  This action CANNOT be undone!

Type 'yes' to confirm deletion: yes
[INFO] Gathering user information...
[INFO] User Details:
[INFO]   Username: testuser01
[INFO]   UID: 1002
[INFO]   GID: 1002
[INFO]   Groups: storage_users
[INFO]   Home: /home/storage_users/testuser01
[INFO]   Disk Usage: 101M
[INFO] Creating backup...
[INFO] Backup file: /var/backups/deprovisioned_users/testuser01_20251105_221839.tar.gz
[INFO] Archiving /home/storage_users/testuser01 (this may take a while)...
[INFO] Backup created successfully: /var/backups/deprovisioned_users/testuser01_20251105_221839.tar.gz (101K)
[INFO] Backup metadata saved: /var/backups/deprovisioned_users/testuser01_20251105_221839.tar.gz.meta
[INFO] =========================================
[INFO] Starting deprovisioning process...
[INFO] =========================================
[INFO] Step 1: Disabling user account...
[INFO] User account locked
[INFO] Step 2: Terminating user processes...
[INFO] No running processes found for testuser01
[INFO] Step 3: Removing cron jobs...
[INFO] No cron jobs found for testuser01
[INFO] Step 4: Removing disk quota...
[INFO] Quota removed
[INFO] Step 5: Cleaning up SSH configuration...
[INFO] SSH configuration updated and reloaded
[INFO] Step 6: Removing audit rules...
[INFO] Audit rules updated
[INFO] Step 7: Removing mail spool...
[INFO] Mail spool removed
[INFO] Step 8: Deleting user account and home directory...
userdel: testuser01 mail spool (/var/spool/mail/testuser01) not found
[INFO] User testuser01 deleted successfully
[INFO] =========================================
[INFO] User testuser01 deprovisioned successfully!
[INFO] =========================================

┌─────────────────────────────────────────────────────────┐
│  USER DEPROVISIONING COMPLETE                        │
└─────────────────────────────────────────────────────────┘

User Information:
  Username:     testuser01
  UID:          1002
  Home:         /home/storage_users/testuser01 (deleted)
  Disk Usage:   101M

Backup Information:
  File:         /var/backups/deprovisioned_users/testuser01_20251105_221839.tar.gz
  Size:         101K
  Retention:    30 days
  Metadata:     /var/backups/deprovisioned_users/testuser01_20251105_221839.tar.gz.meta

To restore from backup:
  sudo tar -xzf /var/backups/deprovisioned_users/testuser01_20251105_221839.tar.gz -C /

[INFO] Deprovisioning completed at Wed Nov  5 10:18:41 PM CET 2025
[rocky-vm@storage-server scripts]$


### **8. Test Force Deprovision (No Prompt)**
```bash
# Create another test user
sudo ./provision_user.sh testuser02 -q 3G

# Force delete without confirmation
sudo ./deprovision_user.sh testuser02 --force

# Should delete immediately without asking
```

### **9. Check Logs**
```bash
# View provisioning logs
sudo tail -f /var/log/storage-provisioning/provisioning.log

# Or view entire log
sudo less /var/log/storage-provisioning/provisioning.log
```

## 🔍 Common Issues & Solutions

### **Issue: "Quotas not enabled"**
```bash
# Solution: Edit /etc/fstab and add usrquota,grpquota
# See step 3 above
```

### **Issue: "Permission denied"**
```bash
# Make sure you're using sudo
sudo ./provision_user.sh username
```

### **Issue: "utils.sh not found"**
```bash
# Run from the scripts directory
cd ~/storage-provisioning/scripts
sudo ./provision_user.sh testuser
```

### **Issue: Scripts have Windows line endings**
```bash
# If you edited on Windows, convert line endings
sudo dnf install dos2unix
dos2unix *.sh
```

## 📋 Quick Test Checklist

```bash
# Complete test sequence
cd ~/storage-provisioning/scripts

# 1. Provision
sudo ./provision_user.sh alice -q 10G
# Note the password

# 2. Verify
id alice
ls -la /home/storage_users/alice
sudo xfs_quota -x -c "report -h" /

# 3. Create test data
sudo -u alice bash -c 'echo "Hello" > /home/storage_users/alice/data/file.txt'

# 4. Deprovision with backup
sudo ./deprovision_user.sh alice --backup
# Type 'yes'

# 5. Verify cleanup
id alice  # Should fail
ls /var/backups/deprovisioned_users/  # Should see backup
```

## 🎯 What to Look For

**Success indicators:**
- Green `[INFO]` messages
- No red `[ERROR]` messages
- User created successfully
- Quota shows up in `xfs_quota` report
- Subdirectories created
- Backup file created during deprovision
- User completely removed after deprovision

**❌ Failure indicators:**
- Red `[ERROR]` messages
- "Quotas not enabled" error → Fix fstab
- "Permission denied" → Use sudo
- Scripts not executable → Run chmod +x

Try these steps and let me know what happens! Which step should I help you with first - the quota setup or running the provision test?



[rocky-vm@storage-server scripts]$ sudo ./provision_user.sh testuser01 -q 5G
[INFO] Running pre-flight checks...
[INFO] Checking quota support on / (filesystem: xfs)
[INFO] =========================================
[INFO] Starting provisioning for user: testuser01
[INFO] Quota: 5G
[INFO] Group: storage_users
[INFO] SSH Access: false
[INFO] =========================================
[INFO] Creating group: storage_users
[INFO] Group storage_users created successfully
[INFO] Creating user testuser01...
[INFO] User testuser01 created successfully
[INFO] Generating secure temporary password...
[INFO] Temporary password set successfully
[INFO] Setting directory permissions...
[INFO] Directory permissions set successfully
[INFO] Setting disk quota...
[INFO] Setting quota 5G for testuser01 on / (xfs)
[INFO] Quota set successfully
[INFO] Creating subdirectories...
[INFO] Created subdirectory: data
[INFO] Created subdirectory: backups
[INFO] Created subdirectory: temp
[INFO] Created subdirectory: logs
[INFO] Created README.txt
[INFO] Denying SSH access...
[INFO] SSH access denied for testuser01
[INFO] SSH configuration reloaded
[INFO] Setting SELinux context...
[INFO] Adding audit rule for user directory...
[INFO] =========================================
[INFO] User testuser01 provisioned successfully!
[INFO] =========================================

┌─────────────────────────────────────────────────────────┐
│  USER PROVISIONING SUCCESSFUL                        │
└─────────────────────────────────────────────────────────┘

User Information:
  Username:     testuser01
  Group:        storage_users
  Home:         /home/storage_users/testuser01
  Quota:        5G
  SSH Access:   false

IMPORTANT - SAVE THIS INFORMATION!

  Temporary Password: akhiVQ8q5aT2iZPQ

  This password will not be shown again!
  User must change password on first login.

Next Steps:
  1. Share credentials securely with user
  2. Instruct user to change password on first login
  3. Configure any additional access controls as needed

To check quota usage:
  sudo xfs_quota -x -c "report -h" /

To deprovision user:
  /home/rocky-vm/storage-provisioning/scripts/deprovision_user.sh testuser01

[INFO] Provisioning completed at Wed Nov  5 10:10:49 PM CET 2025
[rocky-vm@storage-server scripts]$





---

### **Step 9: Create Puppet Manifests**

**`manifests/user.pp`:**

```puppet
# Define a user provisioning class
class storage_provisioning::user (
  String $username,
  String $quota = '10G',
  String $storage_base = '/home/storage_users',
  String $user_group = 'storage_users',
) {
  
  # Ensure storage group exists
  group { $user_group:
    ensure => present,
  }

  # Create user
  user { $username:
    ensure     => present,
    gid        => $user_group,
    home       => "${storage_base}/${username}",
    managehome => true,
    shell      => '/bin/bash',
    require    => Group[$user_group],
  }

  # Set home directory permissions
  file { "${storage_base}/${username}":
    ensure  => directory,
    owner   => $username,
    group   => $user_group,
    mode    => '0700',
    require => User[$username],
  }

  # Create subdirectories
  file { ["${storage_base}/${username}/data",
          "${storage_base}/${username}/backups",
          "${storage_base}/${username}/temp"]:
    ensure  => directory,
    owner   => $username,
    group   => $user_group,
    mode    => '0755',
    require => File["${storage_base}/${username}"],
  }

  # Set quota (using exec, as Puppet doesn't have native XFS quota support)
  exec { "set_quota_${username}":
    command => "/usr/sbin/xfs_quota -x -c 'limit bsoft=${quota} bhard=${quota} ${username}' /",
    unless  => "/usr/sbin/xfs_quota -x -c 'report -h' / | grep -q ${username}",
    require => User[$username],
  }
}
```

**`manifests/init.pp`:**

```puppet
# Example usage
storage_provisioning::user { 'testuser1':
  username => 'testuser1',
  quota    => '5G',
}

storage_provisioning::user { 'testuser2':
  username => 'testuser2',
  quota    => '15G',
}
```

---

### **Step 10: Testing Workflow**

**Create test script (`tests/test_provisioning.sh`):**

```bash
#!/bin/bash

echo "=== Storage Provisioning Test Suite ==="

# Test 1: Create user
echo "Test 1: Creating test user..."
ssh storage-vm 'bash ~/storage-provisioning/scripts/provision_user.sh testuser001 5G'

# Test 2: Verify user exists
echo "Test 2: Verifying user..."
ssh storage-vm 'id testuser001'

# Test 3: Check directory
echo "Test 3: Checking directory..."
ssh storage-vm 'ls -la /home/storage_users/testuser001'

# Test 4: Check quota
echo "Test 4: Checking quota..."
ssh storage-vm 'sudo xfs_quota -x -c "report -h" / | grep testuser001'

# Test 5: Test SFTP access
echo "Test 5: Testing SFTP access..."
# (Would need to set up keys for this)

# Test 6: Deprovision
echo "Test 6: Deprovisioning user..."
ssh storage-vm 'echo "yes" | bash ~/storage-provisioning/scripts/deprovision_user.sh testuser001'

# Test 7: Verify removal
echo "Test 7: Verifying removal..."
ssh storage-vm 'id testuser001' && echo "FAIL: User still exists" || echo "PASS: User removed"

echo "=== Tests Complete ==="
```

Make it executable:
```bash
chmod +x tests/test_provisioning.sh
```

---

## **Phase 4: Development Cycle**

### **Step 11: Iterative Development Loop**

1. **Write/modify scripts or manifests on host**
   ```bash
   vim scripts/provision_user.sh
   ```

2. **Validate syntax locally (before pushing)**
   ```bash
   # For bash scripts
   bash -n scripts/provision_user.sh
   shellcheck scripts/provision_user.sh  # if you have shellcheck installed
   
   # For Puppet
   puppet parser validate manifests/user.pp
   ```

3. **Sync to VM**
   ```bash
   ./sync.sh
   # or
   sync-vm
   ```

4. **SSH into VM and test**
   ```bash
   ssh storage-vm
   cd ~/storage-provisioning
   
   # Test scripts
   bash scripts/provision_user.sh testuser001 5G
   
   # Or test Puppet with --noop (dry-run)
   sudo puppet apply --noop manifests/init.pp
   
   # Then apply for real
   sudo puppet apply manifests/init.pp
   ```

5. **Verify results**
   ```bash
   # Check user
   id testuser001
   
   # Check directory
   ls -la /home/storage_users/testuser001
   
   # Check quota
   sudo xfs_quota -x -c 'report -h' / | grep testuser001
   ```

6. **Document findings**
   ```bash
   # On host machine
   vim docs/testing.md
   # Record what worked, what didn't, any errors
   ```

7. **Commit changes**
   ```bash
   git add .
   git commit -m "feat: add user provisioning with quota support"
   ```

8. **If something breaks: restore VM snapshot**
   ```bash
   # In VirtualBox/VMware: Restore to previous snapshot
   # Then retry with fixes
   ```

---

## **Phase 5: Enhancements & Documentation**

### **Step 12: Add Logging System**

Create log directory on VM:
```bash
ssh storage-vm 'sudo mkdir -p /var/log/storage-provisioning && sudo chmod 755 /var/log/storage-provisioning'
```

Update all scripts to use logging (already included in utils.sh above)

---

### **Step 13: Create Comprehensive Documentation**

**`README.md`:**
```markdown
# Automated Storage Provisioning Tool

Enterprise-grade storage user provisioning system for Rocky Linux.

## Features
- Automated user creation with quotas
- Directory structure management
- SFTP access configuration
- Safe deprovisioning with confirmations
- Comprehensive logging

## Quick Start
[Installation and usage instructions]

## Architecture
[Link to architecture.md]

## Testing
[Link to testing.md]
```

**`docs/architecture.md`:** Draw system diagram, explain components

**`docs/usage.md`:** Step-by-step usage examples

**`docs/testing.md`:** Test cases and results

---

### **Step 14: Optional Enhancements**

1. **Add monitoring:**
   ```bash
   # Script to check disk usage
   scripts/monitor_usage.sh
   ```

2. **Email notifications:**
   - When quota is 80% full
   - When provisioning succeeds/fails

3. **Web interface:**
   - Simple Flask/Django app to provision users
   - Deployed on the VM

4. **Multi-server support:**
   - Extend to provision across multiple VMs

---

## **Final Workflow Summary**

```
┌─────────────┐
│ Host Machine│
│             │
│ 1. Write    │
│ 2. Validate │
│ 3. Sync     │──────SSH/SCP/rsync────┐
│ 4. Commit   │                       │
└─────────────┘                       │
                                      ▼
                            ┌──────────────────┐
                            │   Rocky Linux VM │
                            │                  │
                            │ 5. Apply scripts │
                            │ 6. Test          │
                            │ 7. Verify        │
                            │                  │
                            │ ├─Users created  │
                            │ ├─Dirs created   │
                            │ ├─Quotas set     │
                            │ └─Logs written   │
                            └──────────────────┘
```

---

## **Quick Reference Commands**

```bash
# On host
cd ~/projects/storage-provisioning
./sync.sh
ssh storage-vm

# On VM
cd ~/storage-provisioning
bash scripts/provision_user.sh alice 10G
sudo puppet apply manifests/init.pp
sudo xfs_quota -x -c 'report -h' /
bash scripts/deprovision_user.sh alice
```

---

This plan is **production-ready** and gives you everything you need to build, test, and document your project. Would you like me to create any of these scripts or manifests as artifacts you can immediately use?