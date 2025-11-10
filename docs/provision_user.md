# User Provisioning Script Guide

## Overview

The `provision_user.sh` script automates the creation of storage users with disk quotas, directory structures, and security controls. It handles all necessary configurations including group creation, password management, SSH access control, and audit logging.

## Features

- **Automated user creation** with custom quotas and groups
- **Secure password generation** with forced password change on first login
- **Quota enforcement** using XFS quotas
- **Directory structure** with sensible defaults (data, backups, temp, logs)
- **SSH access control** with built-in deny rules
- **SELinux support** when available
- **Audit logging** for security and compliance
- **Error handling** with automatic cleanup on failure
- **Comprehensive logging** at each step

## Prerequisites

Before running the provisioning script:

- SSH access to the VM with sudo privileges
- Disk quotas enabled on the filesystem (see main setup guide Step 2)
- XFS filesystem (Rocky Linux default)
- `utils.sh` in the same directory as `provision_user.sh`
- Python 3 (for secure password generation in utils.sh)

## Basic Usage

### Create a User with Default Quota (10GB)

```bash
sudo ./provision_user.sh john_doe
```

### Create a User with Custom Quota

```bash
sudo ./provision_user.sh jane_smith -q 50G
```

Supported quota sizes: `5G`, `500M`, `1T`, etc.

### Create a User with SSH Access

By default, users cannot SSH into the system. To allow SSH access:

```bash
sudo ./provision_user.sh admin_user -q 100G --allow-ssh
```

### Create a User Without Subdirectories

Skip automatic subdirectory creation:

```bash
sudo ./provision_user.sh minimal_user --no-subdirs
```

### Create a User in a Custom Group

```bash
sudo ./provision_user.sh new_user -g developers -q 20G
```

### Display Help

```bash
sudo ./provision_user.sh --help
```

## Script Output

When you run the script, it displays comprehensive output showing each step of the provisioning process. Here's the complete output from a successful provisioning run:

```bash
[rocky-vm@storage-server scripts]$ sudo ./provision_user.sh testuser01 -q 5G
[INFO] Running pre-flight checks...
[INFO] Checking quota support on / (filesystem: xfs)
[INFO] =========================================
[INFO] Starting provisioning for user: testuser01
[INFO] Quota: 5G
[INFO] Group: storage_users
[INFO] SSH Access: false
[INFO] =========================================
[INFO] Group storage_users already exists
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

  Temporary Password: Y8t50mZQOwyaLx3g

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

[INFO] Provisioning completed at Mon Nov 10 05:19:53 PM CET 2025
```

**Output Breakdown:**

1. **Pre-flight checks** — Validates quota support and system requirements
2. **Configuration summary** — Shows username, quota, group, and SSH settings
3. **Provisioning steps** — Each action is logged as it completes
4. **Success confirmation** — Visual separator and success message
5. **User information** — Summary of the created account
6. **Temporary password** — One-time credential for first login
7. **Next steps** — Instructions for completing user setup
8. **Helpful commands** — Quick reference for quota checking and deprovisioning
9. **Completion timestamp** — When the provisioning finished

## What the Script Does

### Step 1: Group Creation

The script ensures the specified group exists. If it doesn't, the group is created automatically. By default, all users are added to the `storage_users` group.

### Step 2: User Account Creation

A new user account is created with:
- Home directory: `/home/storage_users/<username>`
- Shell: `/bin/bash`
- Group: `storage_users` (or custom group)

### Step 3: Secure Password Generation

A cryptographically secure temporary password (16 characters) is generated and set. The user is forced to change it on first login for security.

### Step 4: Directory Permissions

Home directory permissions are set to `700` (read-write-execute for owner only), ensuring privacy from other users.

### Step 5: Disk Quota

The disk quota is applied to the user's home directory. This enforces storage limits and prevents users from consuming all available space.

### Step 6: Directory Structure

The following subdirectories are created by default:

| Directory | Purpose |
|-----------|---------|
| `data/` | Primary data storage |
| `backups/` | Backup files |
| `temp/` | Temporary files (cleaned periodically) |
| `logs/` | Application logs |

A `README.txt` file is created with directory descriptions and support information.

### Step 7: SSH Access Control

By default, users are denied SSH access for security. SSH access can be explicitly allowed with `--allow-ssh`.

The script adds the user to `/etc/ssh/sshd_config.d/storage_users.conf`:

```
DenyUsers testuser01
```

### Step 8: SELinux Context

If SELinux is enabled, the correct security context is applied to the user's home directory.

### Step 9: Audit Logging

If `auditd` is available, an audit rule is added to track access to the user's directory:

```
-w /home/storage_users/testuser01 -p wa -k storage_access_testuser01
```

## Command-Line Options

| Option | Description | Example |
|--------|-------------|---------|
| `<username>` | Username (required) | `john_doe` |
| `-q, --quota SIZE` | Disk quota limit | `-q 50G` |
| `-g, --group NAME` | Primary group | `-g developers` |
| `--allow-ssh` | Allow SSH access | `--allow-ssh` |
| `--no-subdirs` | Skip subdirectory creation | `--no-subdirs` |
| `-h, --help` | Show help message | `-h` |

## Workflow Example

Provision a developer with SSH access and 100GB quota:

```bash
sudo ./provision_user.sh dev_sysadmin -q 100G -g developers --allow-ssh
```

Then:

1. Save the temporary password shown in the output
2. Share credentials with the user securely
3. User logs in and changes password on first login
4. Check quota usage:
   ```bash
   sudo xfs_quota -x -c "report -h" /
   ```

## Error Handling

The script includes comprehensive error handling:

- **Pre-flight validation** — checks sudo privileges, quota support, storage base
- **Automatic cleanup** — removes user and home directory if provisioning fails
- **Detailed error messages** — shows exactly what went wrong
- **Exit codes** — non-zero exit on any error

If provisioning fails, the `emergency_cleanup` function (in `utils.sh`) removes the partially-created user and directory.

## Security Considerations

- **Temporary passwords** — Never reused, user forced to change on first login
- **Restrictive permissions** — Home directories have `700` permissions (owner only)
- **SSH disabled by default** — Users cannot access system remotely unless explicitly allowed
- **Audit logging** — Directory access is logged for compliance
- **SELinux support** — Proper security contexts are enforced when available
- **No default shell access** — Users cannot become root with sudo

## Verification Commands

After provisioning a user, verify the setup:

```bash
# Check user exists
id testuser01

# Check home directory
ls -la /home/storage_users/testuser01/

# Check quota
sudo xfs_quota -x -c "report -h" /

# Check SSH denial
sudo sshd -T | grep "^denyusers"

# Check audit rules
sudo auditctl -l | grep testuser01
```

## Troubleshooting

### "Permission denied" Error

**Problem**: Script fails with permission denied.

**Solution**: Ensure you're running with `sudo`:

```bash
sudo ./provision_user.sh testuser01
```

### "User already exists" Error

**Problem**: Script fails because user already exists.

**Solution**: Either use a different username or deprovision the existing user first:

```bash
sudo /path/to/deprovision_user.sh testuser01
sudo ./provision_user.sh testuser01 -q 5G
```

### "Quota not set" Error

**Problem**: Script reports quota support not available.

**Solution**: Verify quotas are enabled:

```bash
mount | grep ' / '
# Should show: usrquota,grpquota
```

If not enabled, see Step 2 in the main setup guide.

### "utils.sh: No such file or directory"

**Problem**: Script fails to source utility functions.

**Solution**: Ensure `utils.sh` is in the same directory as `provision_user.sh`:

```bash
ls -la ~/storage-provisioning/scripts/
# Should see both provision_user.sh and utils.sh
```

## Advanced Configuration

### Change Default Quota

Edit the script and modify:

```bash
DEFAULT_QUOTA="${DEFAULT_QUOTA:-10G}"
```

Or set environment variable before running:

```bash
DEFAULT_QUOTA=20G sudo ./provision_user.sh newuser
```

### Change Default Group

```bash
DEFAULT_GROUP="${DEFAULT_GROUP:-storage_users}"
```

Or use `-g` option:

```bash
sudo ./provision_user.sh newuser -g custom_group
```

### Change Storage Base Directory

```bash
STORAGE_BASE=/mnt/storage sudo ./provision_user.sh newuser
```

## Integration with Deployment Tools

The script can be integrated into deployment workflows:

```bash
# In a deployment script
for user in user1 user2 user3; do
    sudo /path/to/provision_user.sh "$user" -q 50G
done
```

Or with Puppet/Ansible for automated provisioning at scale.

## See Also

- Deprovisioning: `deprovision_user.sh`
- File synchronization: `file-sync-guide.md`
- Quota management: See Step 2 in main setup guide
- Main setup guide: `setup.md`