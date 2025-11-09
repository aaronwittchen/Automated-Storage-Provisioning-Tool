## **Phase 1: Environment Setup**

### **Step 1: Install and Configure Rocky Linux VM**

1. **Create the VM:**
   - Use VirtualBox, VMware, or KVM
   - Allocate: 2 CPUs, 4GB RAM, 40GB disk
   - Network: NAT (simplest) or Bridged (if you want VM accessible from other devices)

2. **Install Rocky Linux:**
   - Download Rocky Linux 9 ISO
   - Minimal or Server with GUI (your choice)
   - During installation: create a user account (e.g., `admin`)
   - Set a strong password or use SSH keys later

3. **Initial VM Configuration:**
   ```bash
   # Update system
   sudo dnf update -y
   
   # Check networking
   ip addr show
   ping -c 4 google.com
   output:

[yeah@localhost ~]$ ip addr show
1: lo: <LOOPBACK, UP, LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group defaul t qlen 1000
link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
inet 127.0.0.1/8 scope host lo
valid_lft forever preferred_lft forever
inet6:1/128 scope host
valid_lft forever preferred_lft forever
2: enp0s3: <BROADCAST, MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP gr oup default qlen 1000
link/ether 08:00:27:ed: 5f:47 brd ff:ff:ff:ff:ff:ff
inet 10.0.2.15/24 brd 10.0.2.255 scope global dynamic noprefixroute enp0s3 valid_lft 84565sec preferred_lft 84565sec
inet6 fe80::a00:27ff: feed: 5f47/64 scope link noprefixroute
valid_lft forever preferred_lft forever
[yeah@localhost ~]$ ping -c 4 google.com
PING google.com (142.250.185.110) 56(84) bytes of data.
64 bytes from fra16s49-in-f14.1e100.net (142.250.185.110): icmp_seq=1 ttl=117 ti me=14.8 ms
64 bytes from fra16s49-in-f14.1e100.net (142.250.185.110): icmp_seq=2 ttl=117 ti me=14.5 ms
64 bytes from fra16s49-in-f14.1e100.net (142.250.185.110): icmp_seq=3 ttl=117 ti me=14.1 ms
64 bytes from fra16s49-in-f14.1e100.net (142.250.185.110): icmp_seq=4 ttl=117 ti me=57.9 ms
google.com ping statistics
4 packets transmitted, 4 received, 0% packet loss, time 3004ms rtt min/avg/max/mdev = 14.091/25.324/57.930/18.826 ms [yeah@localhost ~]$ |


   # Set hostname (optional but professional)
   sudo hostnamectl set-hostname storage-server
   
   # Check filesystem type (important for quotas)
   df -T /

   output:
   
[yeah@localhost ~]$ df -T / Filesystem
/dev/mapper/rl-root xfs
Type 1K-blocks
Used Available Use% Mounted on 17756160 6540412 11215748 37% /
   ```

4. **Take a VM Snapshot:**
   - Name it: "Fresh Install - Before Configuration"
   - This is your safety net

---

### **Step 2: Install Required Packages**

```bash
# Essential tools
sudo dnf install -y \
  vim \
  git \
  wget \
  curl \
  openssh-server \
  quota \
  policycoreutils-python-utils

# For Puppet
sudo dnf install -y https://yum.puppet.com/puppet7-release-el-9.noarch.rpm
sudo dnf install -y coreutils
sudo dnf install -y puppet-agent

sudo dnf install -y epel-release
sudo dnf install -y tree htop net-tools

# Enable and start SSH
sudo systemctl enable sshd --now
sudo systemctl status sshd
```

---

### **Step 3: Configure Disk Quotas**

1. **Check your filesystem:**
   ```bash
   df -T /
   # If it's XFS (Rocky Linux default):
   # Output will show "xfs" in Type column
   ```

2. **For XFS filesystem:**
   ```bash
   # Check current mount options
   mount | grep ' / '

   Example output:
/dev/mapper/rl-root on / type xfs (rw,relatime,seclabel,attr2,inode64,noquota)
Notice at the end it says noquota — quotas are not enabled yet.
   
   # Edit /etc/fstab to add quota options
   sudo vim /etc/fstab
   # Find the line for / (root) and add: usrquota,grpquota
   # Example:
   # /dev/mapper/rl-root / xfs defaults,usrquota,grpquota 0 0
   Put your cursor on /dev/mapper/rl-root and press i to enter insert mode.

Reformat it as a single line, like this:

/dev/mapper/rl-root / xfs defaults,usrquota,grpquota 0 0


Leave /boot line as-is (don’t add quotas there).

Press Esc, then type :wq to save and exit.

# /etc/fstab
# Created by anaconda on Wed Nov 5 14:50:43 2025
#
# Accessible filesystems, by reference, are maintained under '/dev/disk/'.
# See man pages fstab(5), findfs(8), mount(8) and/or blkid(8) for more info.
#
# After editing this file, run 'systemctl daemon-reload' to update systemd
# units generated from this file.

# Root filesystem with quotas enabled
/dev/mapper/rl-root / xfs defaults,usrquota,grpquota 0 0

# Boot partition
UUID=ae29afbf-e555-4e4f-8f72-9d203dc1b74c /boot xfs defaults 0 0

cat /etc/fstab
sudo systemctl daemon-reload
sudo reboot
mount | grep ' / '
Press Esc, then type :wq to save and exit.


   # Remount to apply
   sudo mount -o remount /
   
   # Verify quota is enabled
   mount | grep ' / '
   # Should show: usrquota,grpquota
   ```

   sudo xfs_quota -x -c 'report -h' /

3. **For ext4 filesystem (if applicable):**
   ```bash
   sudo vim /etc/fstab
   # Add: usrquota,grpquota to options
   
   sudo mount -o remount /
   sudo quotacheck -cug /
   sudo quotaon -v /
   ```

4. **Test quota system:**
   ```bash
   sudo xfs_quota -x -c 'report -h' /
   # Should run without errors
   ```

5. **Take another snapshot:** "Quotas Configured"

Verify your current setup (to confirm XFS and no quotas enabled yet):
textdf -T /
mount | grep ' / '

Expect xfs in the type column and noquota in the mount options.


Install quota tools if not already present (provides additional utilities like repquota, though not strictly required for XFS):
textsudo dnf install quota -y

Edit /etc/fstab to add quota options (you've already done this, but double-check):
textsudo vim /etc/fstab

Find the line for your root filesystem (e.g., /dev/mapper/rl-root) and add usrquota,grpquota after defaults:
text/dev/mapper/rl-root / xfs defaults,usrquota,grpquota 0 0

Do not add quotas to /boot or other non-XFS partitions.
Save and exit (:wq).
Reload systemd (though not always necessary):
textsudo systemctl daemon-reload



Add quota flags to the kernel command line via GRUB (this is the key missing step for root filesystem):
textsudo vim /etc/default/grub

Find the GRUB_CMDLINE_LINUX line and append rootflags=usrquota,grpquota (or rootflags=uquota,gquota—either works). Example:
textGRUB_CMDLINE_LINUX="crashkernel=auto resume=/dev/mapper/rl-swap rd.lvm.lv=rl/root rd.lvm.lv=rl/swap rhgb quiet rootflags=usrquota,grpquota"

Save and exit.


Regenerate GRUB config:
textsudo grub2-mkconfig -o /boot/grub2/grub.cfg

Update all kernels with the new flags:
textsudo grubby --args="rootflags=usrquota,grpquota" --update-kernel=ALL

Reboot the system:
textsudo reboot

Verify quotas are enabled after reboot:
textmount | grep ' / '

You should now see usrquota,grpquota (or uquota,gquota) in the options, without noquota.


Test the quota system:
textsudo xfs_quota -x -c 'report -h' /

This should output a report of current usage (e.g., for users and groups) without errors. If it still fails, check the exact error message and share it for further troubleshooting.
For a full report including blocks and inodes:
textsudo xfs_quota -x -c 'report -ubih' /
(Use -g instead of -u for group-specific report.)

---

VM > Settings > Network > Adapter 1 Bridged adapter

### **Step 4: Configure SSH for Key-Based Authentication**

**On your host machine:**

1. **Generate SSH key (if you don't have one):**
   ```bash
   ssh-keygen -t ed25519 -C "storage-provisioning-project"
   # Press Enter to use default location
   # Set a passphrase (optional but recommended)
   ```

2. **Copy key to VM:**
   ```bash
   ssh-copy-id admin@<VM-IP>
   # Replace <VM-IP> with your VM's IP (from ip addr show)
   # Example: ssh-copy-id admin@10.0.2.15
   ```

3. **Test passwordless login:**
   ```bash
   ssh admin@<VM-IP>
   # Should log in without asking for password
   ```

4. **Configure SSH config file for easier access:**
   ```bash
   vim ~/.ssh/config
   ```
   Add:
   ```
   Host storage-vm
       HostName <VM-IP>
       User admin
       IdentityFile ~/.ssh/id_ed25519
   ```
   
   Now you can simply: `ssh storage-vm`
ssh yeah@192.168.68.105

Here's a **detailed step-by-step guide** for setting up SSH key-based authentication:

---

## **Step 4: Configure SSH for Key-Based Authentication**

### **Part 1: Get Your VM's IP Address**

**On your VM (Rocky Linux):**

```bash
ip addr show
```

**Look for the IP address** in the output. It will be under `enp0s3` (or similar):

```
2: enp0s3: <BROADCAST,MULTICAST,UP,LOWER_UP> ...
    inet 10.0.2.15/24 ...
```

**Your VM IP is:** `10.0.2.15` (in this example)

**Write this down** — you'll need it multiple times.

---

### **Part 2: Generate SSH Key on Host Machine**

**On your host machine (your main computer, NOT the VM):**

Open a terminal and run:

```bash
ssh-keygen -t ed25519 -C "storage-provisioning-project"
```

**You'll see prompts like this:**

```
Generating public/private ed25519 key pair.
Enter file in which to save the key (/home/yourname/.ssh/id_ed25519):
```

**Press Enter** to accept the default location.

```
Enter passphrase (empty for no passphrase):
```

**Two options:**
- **Press Enter twice** for no passphrase (simpler, less secure)
- **Type a passphrase** and press Enter, then type it again (more secure, recommended)

**You'll see:**
```
Your identification has been saved in /home/yourname/.ssh/id_ed25519
Your public key has been saved in /home/yourname/.ssh/id_ed25519.pub
The key fingerprint is:
SHA256:... storage-provisioning-project
```

✅ **Key generated successfully!**

---

### **Part 3: Copy Your Key to the VM**

**Still on your host machine:**

```bash
ssh-copy-id yeah@10.0.2.15
```

**Replace:**
- `yeah` with your VM username (the one you created during Rocky Linux installation)
- `10.0.2.15` with your actual VM IP from Part 1

**You'll see:**
```
/usr/bin/ssh-copy-id: INFO: attempting to log in with the new key(s)...
The authenticity of host '10.0.2.15 (10.0.2.15)' can't be established.
ED25519 key fingerprint is SHA256:...
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

**Type:** `yes` and press Enter

```
yeah@10.0.2.15's password:
```

**Type your VM user's password** and press Enter

**You should see:**
```
Number of key(s) added: 1

Now try logging into the machine, with:   "ssh 'yeah@10.0.2.15'"
and check to make sure that only the key(s) you wanted were added.
```

✅ **Key copied successfully!**

---

### **Part 4: Test Passwordless Login**

**On your host machine:**

```bash
ssh yeah@10.0.2.15
```

**What should happen:**
- If you set a passphrase: It will ask for the **passphrase** (NOT the VM password)
- If you didn't set a passphrase: You should be logged in **immediately** without any password prompt

**You should see:**
```
[yeah@localhost ~]$
```

✅ **You're now logged into the VM without typing the VM password!**

**To exit the VM and return to your host:**
```bash
exit
```

Step 1: Copy your public key to the VM

Since ssh-copy-id isn’t available on Windows by default, you can do it manually.

On your Windows host, open your public key file:

notepad C:\Users\theon\.ssh\id_ed25519.pub


Copy the entire contents (it starts with ssh-ed25519 AAAA…).

Step 2: Add the key to the VM

SSH into the VM with your password (just this once):

ssh yeah@192.168.68.105


On the VM, create the .ssh folder in your home directory:

mkdir -p ~/.ssh
chmod 700 ~/.ssh


Open (or create) authorized_keys:

nano ~/.ssh/authorized_keys


Paste the public key you copied from Windows.

Save and exit (Ctrl+O, Enter, Ctrl+X in nano).

Set correct permissions:

chmod 600 ~/.ssh/authorized_keys

Step 3: Test passwordless SSH

Exit the VM:

exit


From your Windows host, SSH again:

ssh yeah@192.168.68.105


You should log in immediately, no password prompt.

If you gave your key a passphrase, it will ask for the passphrase, not the VM password.

✅ Success: You now have passwordless SSH login.

make sure its the full value
ssh-ed25519 AAAAC3N... storage-provisioning-project

---

### **Part 5: Create SSH Config for Easy Access**

This lets you type `ssh storage-vm` instead of `ssh yeah@10.0.2.15` every time.

**On your host machine:**

1. **Open (or create) the SSH config file:**

```bash
nano ~/.ssh/config
```

(If `nano` isn't installed, use `vim` or any text editor)

2. **Add these lines:**

```
Host storage-vm
    HostName 10.0.2.15
    User yeah
    IdentityFile ~/.ssh/id_ed25519
```

**Replace:**
- `10.0.2.15` with your VM's actual IP
- `yeah` with your VM username

3. **Save and exit:**
   - In nano: Press `Ctrl+X`, then `Y`, then `Enter`
   - In vim: Press `Esc`, type `:wq`, press `Enter`

4. **Set correct permissions:**

```bash
chmod 600 ~/.ssh/config
```

---

### **Part 6: Test the Easy Connection**

**On your host machine:**

```bash
ssh storage-vm
```

**You should be logged into the VM immediately!**

```
[yeah@localhost ~]$
```

✅ **SSH is now fully configured!**

### Adapting SSH Config for Windows Host

The provided steps are for a Linux/macOS host (using `~` for home and commands like `nano`/`chmod`), but since your host is Windows (based on paths like `C:\Users\theon\.ssh`), we'll adjust them accordingly. Windows OpenSSH uses a similar config file at `C:\Users\yourusername\.ssh\config` (no file extension). You can edit it with Notepad or any text editor. No `chmod` is strictly needed on Windows, as file permissions are handled differently, but we'll ensure it's secure.

**Prerequisites**: 
- Your pubkey auth is working (from previous fixes—no password prompt when using `ssh -i C:\Users\theon\.ssh\id_ed25519 yeah@192.168.68.105`).
- Use the current VM IP: From context, it's now 192.168.68.105 (not 10.0.2.15, which was the old NAT IP). If it's changed, confirm with `ip addr show` in the VM.

#### Step 1: Create/Edit the SSH Config File on Windows Host
1. Open Command Prompt or PowerShell as your user (theon).
2. Create the .ssh folder if it doesn't exist:
   ```
   mkdir C:\Users\theon\.ssh
   ```
3. Open the config file in Notepad (creates it if missing):
   ```
   notepad C:\Users\theon\.ssh\config
   ```
   - If prompted "Cannot find the file. Do you want to create a new file?", click Yes.

#### Step 2: Add the Configuration Lines
In Notepad, paste this exact content (replace IP/user/key path if needed):

```
Host storage-vm
    HostName 192.168.68.105
    User yeah
    IdentityFile C:\Users\theon\.ssh\id_ed25519
```

- **Explanations/Replacements**:
  - `Host storage-vm`: Alias—you can now use `ssh storage-vm` instead of the full command.
  - `HostName 192.168.68.105`: Your VM's IP (use 10.0.2.15 only if back on NAT; confirm with VM's `ip addr show`).
  - `User yeah`: Your VM username.
  - `IdentityFile C:\Users\theon\.ssh\id_ed25519`: Path to your private key (no .pub). Use forward slashes (/) or double backslashes (\\) if needed, but this should work.

Save the file (File > Save) and close Notepad.

#### Step 3: Secure the Config File (Optional but Recommended)
Windows doesn't have `chmod`, but to restrict access:
```
icacls C:\Users\theon\.ssh\config.txt /inheritance:r /grant %USERNAME%:R
```
- This sets read-only for your user. If errors, skip—Windows SSH is lenient.

#### Step 4: Test the Easy Connection
From Command Prompt/PowerShell:
```
ssh storage-vm
```
- It should connect directly to the VM without password (or ask for key passphrase if set).
- Expected: Logs you in, showing something like `[yeah@storage-server ~]$`.

If it prompts for password: 
- Check config syntax (no extra spaces/tabs; indent with 4 spaces under Host).
- Verbose test: `ssh -v storage-vm`—look for "Offering public key" and acceptance.
- If "Bad configuration option": Fix indents or path in config.

✅ Once working, you can use `ssh storage-vm` for quick access—great for scripting or frequent logins! If IP changes (e.g., DHCP), update the config.
 Automated Storage Provisioning Tool  ren C:\Users\theon\.ssh\config.txt config
 Automated Storage Provisioning Tool  icacls C:\Users\theon\.ssh\config /inheritance:r /grant theon:R
processed file: C:\Users\theon\.ssh\config
Successfully processed 1 files; Failed processing 0 files
 Automated Storage Provisioning Tool  ssh storage-vm
Activate the web console with: systemctl enable --now cockpit.socket

Last login: Wed Nov  5 20:28:26 2025 from 192.168.68.101
[yeah@storage-server ~]$ 

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

echo "✅ User $USERNAME provisioned successfully"
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

echo "✅ User $USERNAME deprovisioned successfully"
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

4. Exit back to `yeah`:

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
[yeah@storage-server scripts]$ ls -ld /var/backups/deprovisioned_users
drwx------. 2 root root 93 Nov  5 22:18 /var/backups/deprovisioned_users
[yeah@storage-server scripts]$ sudo ls -lh /var/backups/deprovisioned_users/
total 108K
-rw-r--r--. 1 root root 101K Nov  5 22:18 testuser01_20251105_221839.tar.gz
-rw-------. 1 root root  250 Nov  5 22:18 testuser01_20251105_221839.tar.gz.meta
[yeah@storage-server scripts]$ sudo ls -lh /var/backups/deprovisioned_users/
total 108K
-rw-r--r--. 1 root root 101K Nov  5 22:18 testuser01_20251105_221839.tar.gz
-rw-------. 1 root root  250 Nov  5 22:18 testuser01_20251105_221839.tar.gz.meta
[yeah@storage-server scripts]$ sudo tree /var/backups/deprovisioned_users/
/var/backups/deprovisioned_users/
├── testuser01_20251105_221839.tar.gz
└── testuser01_20251105_221839.tar.gz.meta

0 directories, 2 files
# Check backup metadata
cat /var/backups/deprovisioned_users/testuser01_*.meta

# Verify user is gone
id testuser01  # Should fail with "no such user"
ls /home/storage_users/testuser01  # Should not exist
[yeah@storage-server scripts]$ sudo cat /var/backups/deprovisioned_users/testuser01_20251105_221839.tar.gz.meta
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
[yeah@storage-server scripts]$
```
[yeah@storage-server scripts]$ sudo ./deprovision_user.sh testuser01 --backup
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
[yeah@storage-server scripts]$


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
# ✅ Note the password

# 2. Verify
id alice
ls -la /home/storage_users/alice
sudo xfs_quota -x -c "report -h" /

# 3. Create test data
sudo -u alice bash -c 'echo "Hello" > /home/storage_users/alice/data/file.txt'

# 4. Deprovision with backup
sudo ./deprovision_user.sh alice --backup
# ✅ Type 'yes'

# 5. Verify cleanup
id alice  # Should fail
ls /var/backups/deprovisioned_users/  # Should see backup
```

## 🎯 What to Look For

**✅ Success indicators:**
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



[yeah@storage-server scripts]$ sudo ./provision_user.sh testuser01 -q 5G
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
  /home/yeah/storage-provisioning/scripts/deprovision_user.sh testuser01

[INFO] Provisioning completed at Wed Nov  5 10:10:49 PM CET 2025
[yeah@storage-server scripts]$





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