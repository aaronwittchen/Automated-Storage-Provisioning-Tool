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

### Using WSL

Set up personal configuration (one-time):

```bash
./sync_vm.sh --setup-config  # Creates ~/.sync_vm.conf
./sync_vm.sh push
./sync_vm.sh pull
./sync_vm.sh push /custom/local rocky-vm@192.168.68.105:/custom/path
```

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