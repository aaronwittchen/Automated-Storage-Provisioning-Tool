# User Deprovisioning Script Guide

## Overview

The `deprovision_user.sh` script safely removes storage users and their associated resources. It can optionally create backups before deletion, ensuring data recovery is possible if needed. The script handles process termination, quota removal, SSH configuration cleanup, and audit rule removal.

## Features

- **Safe user removal** with confirmation prompts
- **Optional backup creation** with metadata tracking
- **Graceful process termination** (SIGTERM then SIGKILL if needed)
- **Comprehensive cleanup** including cron jobs, quotas, SSH rules, and audit logs
- **Backup retention** with expiration dates and restore instructions
- **Detailed logging** of each deprovisioning step
- **Error handling** with manual cleanup fallbacks
- **Mail spool cleanup** and SELinux context handling

## Prerequisites

Before running the deprovisioning script:

- SSH access to the VM with sudo privileges
- `utils.sh` in the same directory as `deprovision_user.sh`
- User must exist on the system
- Sufficient disk space for backup (if using `--backup`)

## Basic Usage

### Remove a User (No Backup)

```bash
sudo ./deprovision_user.sh testuser01
```

This will prompt for confirmation before deletion.

### Remove a User with Backup

```bash
sudo ./deprovision_user.sh testuser01 --backup
```

Creates a backup before deletion. The backup is compressed and stored with metadata.

### Force Deletion (Skip Confirmation)

```bash
sudo ./deprovision_user.sh testuser01 --force
```

Deletes immediately without prompting. Use with caution.

### Backup with Custom Retention

```bash
sudo ./deprovision_user.sh testuser01 --backup --keep-backup 90
```

Creates a backup and sets retention to 90 days. Default is 30 days.

### Display Help

```bash
sudo ./deprovision_user.sh --help
```

## Complete Workflow Example

### Step 1: Create a Test User

```bash
sudo ./provision_user.sh testuser01 -q 5G
```

Expected output:

```
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
```

### Step 2: Add Test Data

Add some data to the user's directory:

```bash
sudo -u testuser01 bash -c 'echo "test data" > /home/storage_users/testuser01/data/test.txt'
```

### Step 3: Deprovision with Backup

Run the deprovisioning script with backup:

```bash
sudo ./deprovision_user.sh testuser01 --backup
```

Expected output:

```
[rocky-vm@storage-server scripts]$ sudo ./deprovision_user.sh testuser01 --backup
[sudo] password for rocky-vm:
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
```

### Step 4: Verify Backup Was Created

Check that the backup files exist:

```bash
sudo ls -lh /var/backups/deprovisioned_users/
```

Expected output:

```
[rocky-vm@storage-server scripts]$ sudo ls -lh /var/backups/deprovisioned_users/
total 108K
-rw-r--r--. 1 root root 101K Nov  5 22:18 testuser01_20251105_221839.tar.gz
-rw-------. 1 root root  250 Nov  5 22:18 testuser01_20251105_221839.tar.gz.meta
```

View backup contents:

```bash
sudo tree /var/backups/deprovisioned_users/
```

Expected output:

```
/var/backups/deprovisioned_users/
├── testuser01_20251105_221839.tar.gz
└── testuser01_20251105_221839.tar.gz.meta

0 directories, 2 files
```

### Step 5: Check Backup Metadata

View the backup metadata file:

```bash
sudo cat /var/backups/deprovisioned_users/testuser01_*.meta
```

Expected output:

```
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
```

The metadata includes the expiration date for backup management.

### Step 6: Verify User Is Gone

Confirm the user account was deleted:

```bash
id testuser01
```

Expected output:

```
id: 'testuser01': no such user
```

Verify the home directory no longer exists:

```bash
ls /home/storage_users/testuser01
```

Expected output:

```
ls: cannot access '/home/storage_users/testuser01': No such file or directory
```

## Command-Line Options

| Option | Description | Example |
|--------|-------------|---------|
| `<username>` | Username to remove (required) | `testuser01` |
| `-b, --backup` | Create backup before deletion | `--backup` |
| `-f, --force` | Skip confirmation prompt | `--force` |
| `--keep-backup DAYS` | Backup retention in days (default: 30) | `--keep-backup 90` |
| `-h, --help` | Show help message | `-h` |

## What the Script Does

### Pre-flight Checks

Validates sudo privileges, username format, and user existence.

### User Information Gathering

Collects UID, GID, group membership, home directory, and disk usage.

### Backup Creation (Optional)

- Creates timestamped TAR.GZ archive
- Stores in `/var/backups/deprovisioned_users/`
- Generates metadata file with user info and expiration date
- Compresses data for efficient storage

### Deprovisioning Steps

1. **Disable account** — Locks the user account to prevent login
2. **Terminate processes** — Kills all running processes (SIGTERM, then SIGKILL if needed)
3. **Remove cron jobs** — Deletes scheduled tasks
4. **Remove quota** — Clears disk quota limits
5. **Clean SSH config** — Removes SSH deny rules
6. **Remove audit rules** — Deletes audit logging rules
7. **Remove mail spool** — Deletes user mail files
8. **Delete user** — Removes user account and home directory

### Success Output

Displays user information, backup details (if created), and restore instructions.

## Backup Management

### Backup Location

All backups are stored in `/var/backups/deprovisioned_users/` with naming scheme:

```
<username>_<YYYYMMDD_HHMMSS>.tar.gz
<username>_<YYYYMMDD_HHMMSS>.tar.gz.meta
```

### Restore from Backup

To restore a deleted user's data:

```bash
# List available backups
sudo ls -lh /var/backups/deprovisioned_users/

# Extract backup
sudo tar -xzf /var/backups/deprovisioned_users/testuser01_20251105_221839.tar.gz -C /

# Or restore to alternate location
sudo tar -xzf /var/backups/deprovisioned_users/testuser01_20251105_221839.tar.gz -C /tmp/recovery/
```

### Manual Cleanup

To manually remove old backups:

```bash
# Remove a specific backup
sudo rm -f /var/backups/deprovisioned_users/testuser01_20251105_221839.tar.gz*

# Remove all backups older than 30 days
sudo find /var/backups/deprovisioned_users/ -name "*.tar.gz" -mtime +30 -delete
```

## Error Handling

The script handles various error conditions gracefully:

- **User doesn't exist** — Exits with clear error message
- **Invalid home directory** — Prevents accidental deletion of system directories
- **Backup creation fails** — Allows continuing with confirmation
- **Process termination fails** — Logs warning but continues
- **userdel fails** — Attempts manual cleanup of home directory

## Troubleshooting

### "User does not exist" Error

**Problem**: Script fails saying user doesn't exist.

**Solution**: Verify the username:

```bash
id testuser01
# If user doesn't exist, use correct username
```

### "Permission denied" Error

**Problem**: Script fails with permission denied.

**Solution**: Ensure you're running with `sudo`:

```bash
sudo ./deprovision_user.sh testuser01 --backup
```

### Backup Is Very Large

**Problem**: Backup takes a long time or uses lots of disk space.

**Solution**: Exclude unnecessary files before deletion, or increase backup retention by using a separate storage location.

### Processes Still Running After Deprovisioning

**Problem**: Some processes remain after script completion.

**Solution**: Check what's still running:

```bash
pgrep -u testuser01
# If nothing returns, all processes were killed
```

## Advanced Configuration

### Change Backup Location

Edit the script and modify:

```bash
BACKUP_DIR="${BACKUP_DIR:-/var/backups/deprovisioned_users}"
```

Or set environment variable:

```bash
BACKUP_DIR=/mnt/backups sudo ./deprovision_user.sh testuser01 --backup
```

### Change Backup Retention Default

Modify in script:

```bash
BACKUP_RETENTION_DAYS=30
```

Or use `--keep-backup` option:

```bash
sudo ./deprovision_user.sh testuser01 --backup --keep-backup 90
```

## Security Considerations

- **Confirmation required** — Two-stage confirmation prevents accidental deletion
- **Force flag** — Use `--force` carefully, only in automated workflows
- **Backup permissions** — Backups are readable only by root (`600` permissions)
- **Process termination** — Graceful shutdown before forced kill
- **Audit cleanup** — All audit rules and logs related to user are removed
- **SSH cleanup** — SSH deny rules are removed to prevent lingering restrictions

## Integration with Provisioning

The provisioning and deprovisioning scripts work together:

```bash
# Provision user
sudo ./provision_user.sh sysadmin -q 100G

# ... user operates ...

# Deprovision when done
sudo ./deprovision_user.sh sysadmin --backup --keep-backup 90
```

## See Also

- User provisioning: `provision_user.md`
- File synchronization: `file-sync-guide.md`
- Quota management: See Step 2 in main setup guide
- Main setup guide: `setup.md`