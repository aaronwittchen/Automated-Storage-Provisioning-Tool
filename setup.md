# VM Setup and Configuration

## SSH Configuration

Configure SSH access to your storage VM by editing your SSH config file:

```bash
# C:\Users\user\.ssh\config
Host storage-vm
    HostName 192.168.68.105  # Update this IP if needed
    User rocky-vm            # Your VM username
    IdentityFile ~/.ssh/id_ed25519  # Path to your private key
```

Connect to the VM:

```bash
ssh storage-vm
```

Expected output:

```
Activate the web console with: systemctl enable --now cockpit.socket

Last login: Mon Nov 10 16:26:39 2025
[rocky-vm@storage-unit ~]$
```

---

## Set Up File Transfer Method

The `sync_vm.sh` script automates bidirectional file synchronization between your host machine and the VM using `rsync` over SSH. This is essential for development and testing workflows.

### Prerequisites

Ensure you have:
- `rsync` installed on both your host and VM
- SSH key-based authentication configured (see Step 3)
- The `sync_vm.sh` script in your project directory

### Initial Configuration

Generate a personal config file (one-time setup):

```bash
./sync_vm.sh --setup-config
```

This creates `~/.sync_vm.conf` with default paths. Edit it to match your setup:

```bash
nano ~/.sync_vm.conf
```

The config file contains:

```
# Default local project directory
LOCAL_DIR="$(pwd)"

# Default remote VM target (user@host:/path)
REMOTE_TARGET="rocky-vm@192.168.68.105:/home/rocky-vm/storage-provisioning/"
```

Update these paths if your local project or remote target directories differ.

### Basic Usage

#### Push Local Files to VM

Synchronize your local project to the VM:

```bash
./sync_vm.sh push
```

This uses defaults from `~/.sync_vm.conf`. For a one-time override:

```bash
./sync_vm.sh push /path/to/local rocky-vm@192.168.68.105:/remote/path
```

#### Pull Files from VM to Local

Synchronize files from the VM back to your local machine:

```bash
./sync_vm.sh pull
```

Or with custom paths:

```bash
./sync_vm.sh pull /path/to/local rocky-vm@192.168.68.105:/remote/path
```

### Excluded Files and Directories

The script automatically excludes the following from sync to avoid syncing unnecessary files:

- `.git` — Version control directory
- `logs` — Log files
- `*.tmp` — Temporary files
- `*.bak` — Backup files
- `__pycache__` — Python cache directory

To modify excluded items, edit the `EXCLUDES` array in `sync_vm.sh`.

### How It Works

The script uses `rsync` with the following features:

- **Two-way sync**: Push changes to VM or pull changes back to your host
- **Incremental**: Only transfers changed files
- **Delete flag**: `--delete` removes files on destination that don't exist on source
- **Logging**: All sync operations are logged to `sync.log`
- **Color output**: Status messages use color for readability

Before each sync, the script displays a summary and asks for confirmation:

```
-------------------------------------------
 Automated Storage Provisioning Tool Sync
-------------------------------------------
Mode  : push
Local : /path/to/project
Remote: rocky-vm@192.168.68.105:/home/rocky-vm/storage-provisioning/
Config: /home/user/.sync_vm.conf

Proceed with sync? (y/n):
```

Type `y` to confirm or `n` to abort.

### Troubleshooting

**"rsync not found"**: Install rsync on your host and VM:

```bash
# Host (Linux/macOS)
brew install rsync  # macOS
sudo apt-get install rsync  # Ubuntu/Debian

# VM
sudo dnf install rsync
```

**Permission denied**: Ensure SSH key-based authentication is working and the remote path exists on the VM.

**Nothing syncing**: Check that files have actually changed. The script only transfers modified files.

---

## Initial Setup

### Create the VM

Use VirtualBox, VMware, or KVM with the following specifications:

- 2 CPUs
- 4GB RAM
- 40GB disk
- Network: Bridged Adapter

For details on network configuration options, see [vm-network-configuration.md](./vm-network-configuration.md).

### Initial VM Configuration

Update the system and verify networking:

```bash
# Update system
sudo dnf update -y

# Check networking
ip addr show
ping -c 4 google.com
```

Expected output:

```
[rocky-vm@storage-unit ~]$ ping -c 4 google.com
PING google.com (142.250.185.174) 56(84) bytes of data.
64 bytes from fra16s51-in-f14.1e100.net (142.250.185.174): icmp_seq=1 ttl=118 time=15.3 ms
64 bytes from fra16s51-in-f14.1e100.net (142.250.185.174): icmp_seq=2 ttl=118 time=15.0 ms
64 bytes from fra16s51-in-f14.1e100.net (142.250.185.174): icmp_seq=3 ttl=118 time=14.2 ms
64 bytes from fra16s51-in-f14.1e100.net (142.250.185.174): icmp_seq=4 ttl=118 time=14.2 ms

--- google.com ping statistics ---
4 packets transmitted, 4 received, 0% packet loss, time 3010ms
rtt min/avg/max/mdev = 14.160/14.646/15.253/0.483 ms
```

Set hostname:

```bash
sudo hostnamectl set-hostname storage-server
```

Check filesystem type:

```bash
df -T /
```

Expected output:

```
Filesystem          Type 1K-blocks    Used Available Use% Mounted on
/dev/mapper/rl-root xfs   17756160 6484468  11271692  37% /
```

### Take a VM Snapshot

Create a snapshot named "Fresh Install - Before Configuration" as a safety net before proceeding with configuration.

---

## Step 1: Install Required Packages

Install essential tools and services:

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

# Additional utilities
sudo dnf install -y epel-release
sudo dnf install -y tree htop net-tools

# Enable and start SSH
sudo systemctl enable sshd --now
sudo systemctl status sshd
```

Expected output for SSH status:

```
● sshd.service - OpenSSH server daemon
     Loaded: loaded (/usr/lib/systemd/system/sshd.service; enabled; preset: enabled)
     Active: active (running) since Mon 2025-11-10 16:20:19 CET; 20min ago
       Docs: man:sshd(8)
             man:sshd_config(5)
   Main PID: 907 (sshd)
      Tasks: 1 (limit: 22987)
     Memory: 5.3M
        CPU: 525ms
     CGroup: /system.slice/sshd.service
             └─907 "sshd: /usr/sbin/sshd -D [listener] 0 of 10-100 startups"
```

---

## Step 2: Configure Disk Quotas

Verify your filesystem type (XFS is the Rocky Linux default):

```bash
df -T /
```

Expected output:

```
Filesystem          Type 1K-blocks    Used Available Use% Mounted on
/dev/mapper/rl-root xfs   17756160 6484448  11271712  37% /
```

### For XFS Filesystem

Check current mount options:

```bash
mount | grep ' / '
```

Edit `/etc/fstab` to enable quotas on the root filesystem:

```bash
sudo vim /etc/fstab
```

Find the line for `/dev/mapper/rl-root` and add quota options. The line should look like:

```
/dev/mapper/rl-root / xfs defaults,usrquota,grpquota 0 0
```

Do not add quotas to `/boot` or other non-XFS partitions. Save and exit with `:wq`.

Add quota flags to the kernel command line via GRUB:

```bash
sudo vim /etc/default/grub
```

Find the `GRUB_CMDLINE_LINUX` line and append `rootflags=usrquota,grpquota`:

```
GRUB_CMDLINE_LINUX="crashkernel=auto resume=/dev/mapper/rl-swap rd.lvm.lv=rl/root rd.lvm.lv=rl/swap rhgb quiet rootflags=usrquota,grpquota"
```

Save and exit.

Regenerate GRUB configuration and reboot:

```bash
sudo grub2-mkconfig -o /boot/grub2/grub.cfg
sudo grubby --args="rootflags=usrquota,grpquota" --update-kernel=ALL
sudo reboot
```

Verify quotas are enabled after reboot:

```bash
mount | grep ' / '
```

You should see `usrquota,grpquota` in the mount options without `noquota`.

### For ext4 Filesystem (if applicable)

Edit `/etc/fstab` and add quota options:

```bash
sudo vim /etc/fstab
# Add: usrquota,grpquota to options

sudo mount -o remount /
sudo quotacheck -cug /
sudo quotaon -v /
```

### Test the Quota System

Test XFS quotas:

```bash
sudo xfs_quota -x -c 'report -h' /
```

For a full report including blocks and inodes:

```bash
sudo xfs_quota -x -c 'report -ubih' /
```

Use `-g` instead of `-u` for group-specific reports.

### Take Another Snapshot

Create a snapshot named "Quotas Configured" after successful quota setup.

---

## Step 3: Configure SSH for Key-Based Authentication

### Get Your VM's IP Address

On your VM, run:

```bash
ip addr show
```

Look for the IP address under `enp0s3` (or similar):

```
2: enp0s3: <BROADCAST,MULTICAST,UP,LOWER_UP> ...
    inet 192.168.68.105/24 ...
```

Write down your VM IP—you'll need it multiple times.

### Generate SSH Key on Host Machine

On your host machine, generate an SSH key:

```bash
ssh-keygen -t ed25519 -C "storage-provisioning-project"
```

When prompted:

```
Enter file in which to save the key (/home/yourname/.ssh/id_ed25519):
```

Press Enter to accept the default location.

```
Enter passphrase (empty for no passphrase):
```

Choose one of:
- Press Enter twice for no passphrase (simpler, less secure)
- Type a passphrase and press Enter twice (more secure, recommended)

Expected output:

```
Your identification has been saved in /home/yourname/.ssh/id_ed25519
Your public key has been saved in /home/yourname/.ssh/id_ed25519.pub
The key fingerprint is:
SHA256:... storage-provisioning-project
```

### Copy Your Key to the VM

#### For Linux/macOS Host

```bash
ssh-copy-id rocky-vm@192.168.68.105
```

When prompted, type your VM user's password. You should see:

```
Number of key(s) added: 1
```

#### For Windows Host

Since `ssh-copy-id` isn't available on Windows by default, copy the key manually.

Open your public key file in Notepad:

```
notepad C:\Users\yourusername\.ssh\id_ed25519.pub
```

Copy the entire contents (starts with `ssh-ed25519 AAAA...`). Make sure you copy the full value.

SSH into the VM with your password (one time only):

```bash
ssh rocky-vm@192.168.68.105
```

On the VM, create the `.ssh` directory:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
```

Open the `authorized_keys` file:

```bash
nano ~/.ssh/authorized_keys
```

Paste your public key and save. Exit with `Ctrl+X`, then `Y`, then `Enter`.

Set correct permissions:

```bash
chmod 600 ~/.ssh/authorized_keys
```

### Test Passwordless Login

Exit the VM:

```bash
exit
```

SSH again from your host:

```bash
ssh rocky-vm@192.168.68.105
```

You should log in immediately without a password prompt. If you set a passphrase, it will ask for the passphrase (not the VM password).

### Configure SSH Config for Easy Access

#### For Linux/macOS Host

Open or create your SSH config file:

```bash
nano ~/.ssh/config
```

Add:

```
Host storage-vm
    HostName 192.168.68.105
    User rocky-vm
    IdentityFile ~/.ssh/id_ed25519
```

Replace the IP and username if needed. Save and exit with `Ctrl+X`, then `Y`, then `Enter`.

Set correct permissions:

```bash
chmod 600 ~/.ssh/config
```

#### For Windows Host

Create the `.ssh` folder if it doesn't exist:

```
mkdir C:\Users\yourusername\.ssh
```

Open the config file in Notepad:

```
notepad C:\Users\yourusername\.ssh\config
```

If prompted "Cannot find the file. Do you want to create a new file?", click Yes.

Add:

```
Host storage-vm
    HostName 192.168.68.105
    User rocky-vm
    IdentityFile C:\Users\yourusername\.ssh\id_ed25519
```

Replace the username path and VM credentials as needed. Save and close.

Optionally, secure the config file (Windows command prompt):

```
icacls C:\Users\yourusername\.ssh\config /inheritance:r /grant yourusername:R
```

### Test the Easy Connection

From your host:

```bash
ssh storage-vm
```

You should be logged into the VM immediately without a password prompt.

Expected output:

```
[rocky-vm@storage-server ~]$
```

If it prompts for a password, check:
- SSH config syntax (proper indentation with 4 spaces under Host)
- File path to private key is correct
- For verbose troubleshooting: `ssh -v storage-vm`

---

## Step 4: Deploy and Test Provisioning Scripts

### Pre-flight Check

Before running the provisioning scripts, verify that quotas are enabled on your filesystem:

```bash
mount | grep ' / '
```

If you see `usrquota` or `uquota` in the output, quotas are enabled and you can proceed. If not, refer back to Step 2: Configure Disk Quotas.

### Sync Scripts to VM

Use `sync_vm.sh` to copy your project files to the VM:

```bash
./sync_vm.sh push
```

Confirm the sync and wait for completion.

### Fix Line Endings

Scripts synced from Windows to Linux may have Windows line endings (CRLF). Convert all scripts in the VM:

```bash
cd ~/storage-provisioning/scripts/
for file in *.sh; do sed -i 's/\r$//' "$file"; done
```

This ensures the scripts run properly on Linux.

### Test the Provisioning Script

Verify the script is working by displaying the help information:

```bash
sudo ./provision_user.sh --help
```

Expected output:

```
Usage: ./provision_user.sh <username> [options]

Provision a new storage user with quota and directory structure.

Arguments:
    username            Username for the new storage user (required)

Options:
    -q, --quota SIZE    Disk quota (default: 10G)
                        Examples: 5G, 500M, 1T
    -g, --group NAME    Primary group (default: storage_users)
    --allow-ssh         Allow SSH access (default: deny)
    --no-subdirs        Skip creating default subdirectories
    -h, --help          Show this help message

Examples:
    ./provision_user.sh john_doe
    ./provision_user.sh jane_smith -q 50G
    ./provision_user.sh admin_user -q 100G --allow-ssh
```

### Create a Test User

Create a test user with a 5GB quota to verify the provisioning process:

```bash
sudo ./provision_user.sh testuser01 -q 5G
```

For detailed information about the provisioning script, its options, and complete output examples, see [provision_user.md](./provision_user.md).

The script will run through several steps and display a success summary with the temporary password.

### Verify User Creation

Confirm the test user was created successfully:

```bash
# Check user exists
id testuser01
```

Expected output:

```
uid=1002(testuser01) gid=1002(storage_users) groups=1002(storage_users)
```

Check the home directory and subdirectories:

```bash
ls -la /home/storage_users/testuser01/
```

Expected output should include:

```
data/
backups/
temp/
logs/
README.txt
```

Check that the quota was applied:

```bash
sudo xfs_quota -x -c "report -h" /
```

You should see `testuser01` listed with a 5G hard limit.

### Test User Login (Optional)

Switch to the test user to verify permissions and quota enforcement:

```bash
sudo su - testuser01
```

You will be prompted to change the temporary password. Enter the password displayed during provisioning, then set a new password.

Once logged in, verify the environment:

```bash
# Check current directory
pwd

# List files
ls -la

# Create a test file to verify quota
dd if=/dev/zero of=testfile bs=1M count=100

# Check quota usage
xfs_quota -x -c "report -h" /
```

Exit back to the rocky-vm user:

```bash
exit
```

### Take a Final Snapshot

Create a snapshot named "Provisioning Scripts Tested" after successful verification. This serves as a clean baseline if you need to troubleshoot later.

---

## Step 5: Deprovision Test User

Once you've verified the provisioning script works, you can test the deprovisioning process to ensure user removal is working correctly.

### Deprovision Without Backup

Remove the test user without creating a backup:

```bash
sudo ./deprovision_user.sh testuser01
```

You will be prompted to confirm the deletion. Type `yes` to proceed.

### Deprovision With Backup

For a safer approach, create a backup before deletion:

```bash
sudo ./deprovision_user.sh testuser01 --backup
```

This creates a backup archive that can be restored later if needed.

For detailed information about the deprovisioning script, its options, backup management, and complete output examples, see [deprovision_user.md](./deprovision_user.md).

### Verify User Removal

Confirm the user was successfully removed:

```bash
# User should not exist
id testuser01

# Home directory should be gone
ls /home/storage_users/testuser01
```

Both commands should return "not found" or similar errors, confirming successful removal.