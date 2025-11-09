#!/bin/bash
# Enhanced user deprovisioning script
# File: scripts/deprovision_user.sh

set -euo pipefail

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/var/backups/deprovisioned_users}"
SSH_DENY_CONFIG="/etc/ssh/sshd_config.d/storage_users.conf"
AUDIT_RULES="/etc/audit/rules.d/storage_users.rules"

# ============================================================================
# Usage Information
# ============================================================================

show_usage() {
    cat << EOF
Usage: $0 <username> [options]

Deprovision a storage user and optionally backup their data.

Arguments:
    username            Username to deprovision (required)

Options:
    -b, --backup        Create backup before deletion
    -f, --force         Skip confirmation prompt
    --keep-backup DAYS  Keep backup for specified days (default: 30)
    -h, --help          Show this help message

Examples:
    $0 john_doe
    $0 jane_smith --backup
    $0 old_user --force --backup --keep-backup 90

EOF
}

# ============================================================================
# Parse Arguments
# ============================================================================

USERNAME=""
CREATE_BACKUP=false
FORCE=false
BACKUP_RETENTION_DAYS=30

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -b|--backup)
            CREATE_BACKUP=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        --keep-backup)
            BACKUP_RETENTION_DAYS="$2"
            shift 2
            ;;
        -*)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
        *)
            if [ -z "$USERNAME" ]; then
                USERNAME="$1"
            else
                echo "Error: Multiple usernames provided"
                show_usage
                exit 1
            fi
            shift
            ;;
    esac
done

# ============================================================================
# Validation
# ============================================================================

if [ -z "$USERNAME" ]; then
    echo "Error: Username is required"
    show_usage
    exit 1
fi

log "INFO" "Running pre-flight checks..."

check_sudo || exit 1
validate_username "$USERNAME" || exit 1

# Check if user exists
if ! user_exists "$USERNAME"; then
    log "ERROR" "User $USERNAME does not exist"
    exit 1
fi

# Get user home directory
USER_HOME=$(get_user_home "$USERNAME")

if [ -z "$USER_HOME" ] || [ "$USER_HOME" = "/" ]; then
    log "ERROR" "Invalid home directory for user $USERNAME"
    exit 1
fi

# ============================================================================
# Confirmation
# ============================================================================

if [ "$FORCE" = false ]; then
    log "WARN" "========================================="
    log "WARN" "DEPROVISIONING USER: $USERNAME"
    log "WARN" "========================================="
    echo ""
    echo "This action will:"
    echo "  - Kill all processes owned by $USERNAME"
    echo "  - Remove disk quota"
    echo "  - Delete user account"
    echo "  - Delete home directory: $USER_HOME"
    
    if [ "$CREATE_BACKUP" = true ]; then
        echo "  - Create backup before deletion"
    else
        echo "  - NO BACKUP will be created"
    fi
    
    echo ""
    echo "⚠️  This action CANNOT be undone!"
    echo ""
    
    read -p "Type 'yes' to confirm deletion: " CONFIRM
    
    if [ "$CONFIRM" != "yes" ]; then
        log "INFO" "Deprovisioning cancelled by user"
        echo "Aborted"
        exit 0
    fi
fi

# ============================================================================
# Get User Information
# ============================================================================

log "INFO" "Gathering user information..."

USER_ID=$(id -u "$USERNAME")
USER_GID=$(id -g "$USERNAME")
USER_GROUPS=$(id -Gn "$USERNAME")

log "INFO" "User Details:"
log "INFO" "  Username: $USERNAME"
log "INFO" "  UID: $USER_ID"
log "INFO" "  GID: $USER_GID"
log "INFO" "  Groups: $USER_GROUPS"
log "INFO" "  Home: $USER_HOME"

# Get disk usage before deletion
if [ -d "$USER_HOME" ]; then
    DISK_USAGE=$(sudo du -sh "$USER_HOME" 2>/dev/null | awk '{print $1}')
    log "INFO" "  Disk Usage: $DISK_USAGE"
fi

# ============================================================================
# Create Backup
# ============================================================================

BACKUP_FILE=""

if [ "$CREATE_BACKUP" = true ]; then
    log "INFO" "Creating backup..."
    
    # Create backup directory
    sudo mkdir -p "$BACKUP_DIR"
    sudo chmod 700 "$BACKUP_DIR"
    
    # Generate backup filename with timestamp
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="$BACKUP_DIR/${USERNAME}_${TIMESTAMP}.tar.gz"
    
    log "INFO" "Backup file: $BACKUP_FILE"
    
    # Create backup with progress
    if [ -d "$USER_HOME" ]; then
        log "INFO" "Archiving $USER_HOME (this may take a while)..."
        
        if sudo tar -czf "$BACKUP_FILE" -C "$(dirname "$USER_HOME")" "$(basename "$USER_HOME")" 2>&1 | tee -a "$LOG_FILE"; then
            BACKUP_SIZE=$(ls -lh "$BACKUP_FILE" | awk '{print $5}')
            log "INFO" "Backup created successfully: $BACKUP_FILE ($BACKUP_SIZE)"
            
            # Create metadata file
            METADATA_FILE="${BACKUP_FILE}.meta"
            cat > "$METADATA_FILE" << EOF
Username: $USERNAME
UID: $USER_ID
GID: $USER_GID
Groups: $USER_GROUPS
Home Directory: $USER_HOME
Disk Usage: $DISK_USAGE
Backup Date: $(date)
Backup Size: $BACKUP_SIZE
Retention: $BACKUP_RETENTION_DAYS days
Expires: $(date -d "+$BACKUP_RETENTION_DAYS days" 2>/dev/null || date -v+${BACKUP_RETENTION_DAYS}d 2>/dev/null || echo "Unknown")
EOF
            sudo chmod 600 "$METADATA_FILE"
            log "INFO" "Backup metadata saved: $METADATA_FILE"
        else
            log "ERROR" "Backup creation failed"
            read -p "Continue with deletion anyway? (yes/no): " CONTINUE
            if [ "$CONTINUE" != "yes" ]; then
                log "INFO" "Deprovisioning cancelled"
                exit 1
            fi
        fi
    else
        log "WARN" "User home directory does not exist, skipping backup"
    fi
fi

# ============================================================================
# Deprovisioning Steps
# ============================================================================

log "INFO" "========================================="
log "INFO" "Starting deprovisioning process..."
log "INFO" "========================================="

# Step 1: Disable user account (prevent new logins)
log "INFO" "Step 1: Disabling user account..."
if sudo usermod -L "$USERNAME" 2>&1 | tee -a "$LOG_FILE"; then
    log "INFO" "User account locked"
else
    log "WARN" "Could not lock user account"
fi

# Step 2: Kill all user processes
log "INFO" "Step 2: Terminating user processes..."

USER_PIDS=$(pgrep -u "$USERNAME" 2>/dev/null || true)
if [ -n "$USER_PIDS" ]; then
    log "INFO" "Found $(echo "$USER_PIDS" | wc -l) process(es) for $USERNAME"
    
    # Send SIGTERM first (graceful)
    sudo pkill -TERM -u "$USERNAME" 2>/dev/null || true
    sleep 2
    
    # Check if any processes remain
    REMAINING_PIDS=$(pgrep -u "$USERNAME" 2>/dev/null || true)
    if [ -n "$REMAINING_PIDS" ]; then
        log "WARN" "Some processes remain, sending SIGKILL..."
        sudo pkill -KILL -u "$USERNAME" 2>/dev/null || true
        sleep 1
    fi
    
    # Final check
    if pgrep -u "$USERNAME" > /dev/null 2>&1; then
        log "WARN" "Some processes may still be running"
    else
        log "INFO" "All processes terminated"
    fi
else
    log "INFO" "No running processes found for $USERNAME"
fi

# Step 3: Remove from cron jobs
log "INFO" "Step 3: Removing cron jobs..."
if sudo crontab -u "$USERNAME" -l > /dev/null 2>&1; then
    sudo crontab -u "$USERNAME" -r 2>/dev/null || true
    log "INFO" "Removed cron jobs for $USERNAME"
else
    log "INFO" "No cron jobs found for $USERNAME"
fi

# Step 4: Remove disk quota
log "INFO" "Step 4: Removing disk quota..."
remove_user_quota "$USERNAME"
log "INFO" "Quota removed"

# Step 5: Remove SSH deny rule
log "INFO" "Step 5: Cleaning up SSH configuration..."
if [ -f "$SSH_DENY_CONFIG" ]; then
    sudo sed -i "/DenyUsers.*$USERNAME/d" "$SSH_DENY_CONFIG" 2>/dev/null || true
    
    # Reload SSH config
    if sudo systemctl reload sshd 2>/dev/null || sudo systemctl reload ssh 2>/dev/null; then
        log "INFO" "SSH configuration updated and reloaded"
    else
        log "WARN" "Could not reload SSH service"
    fi
fi

# Step 6: Remove audit rules
log "INFO" "Step 6: Removing audit rules..."
if [ -f "$AUDIT_RULES" ]; then
    sudo sed -i "/storage_access_$USERNAME/d" "$AUDIT_RULES" 2>/dev/null || true
    
    if command -v auditctl &>/dev/null; then
        sudo auditctl -R "$AUDIT_RULES" 2>/dev/null || true
        log "INFO" "Audit rules updated"
    fi
fi

# Step 7: Remove user mail spool
log "INFO" "Step 7: Removing mail spool..."
MAIL_SPOOL="/var/mail/$USERNAME"
if [ -f "$MAIL_SPOOL" ]; then
    sudo rm -f "$MAIL_SPOOL"
    log "INFO" "Mail spool removed"
fi

# Step 8: Delete user account and home directory
log "INFO" "Step 8: Deleting user account and home directory..."
if sudo userdel -r "$USERNAME" 2>&1 | tee -a "$LOG_FILE"; then
    log "INFO" "User $USERNAME deleted successfully"
else
    log "ERROR" "Failed to delete user $USERNAME"
    
    # Try to manually remove home directory if userdel failed
    if [ -d "$USER_HOME" ]; then
        log "WARN" "Attempting manual cleanup of home directory..."
        sudo rm -rf "$USER_HOME" 2>&1 | tee -a "$LOG_FILE" || log "ERROR" "Could not remove home directory"
    fi
fi

# ============================================================================
# Success Output
# ============================================================================

log "INFO" "========================================="
log "INFO" "User $USERNAME deprovisioned successfully!"
log "INFO" "========================================="

cat << EOF

┌─────────────────────────────────────────────────────────┐
│  USER DEPROVISIONING COMPLETE                        │
└─────────────────────────────────────────────────────────┘

User Information:
  Username:     $USERNAME
  UID:          $USER_ID
  Home:         $USER_HOME (deleted)
  Disk Usage:   ${DISK_USAGE:-Unknown}

EOF

if [ -n "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ]; then
    BACKUP_SIZE=$(ls -lh "$BACKUP_FILE" | awk '{print $5}')
    cat << EOF
Backup Information:
  File:         $BACKUP_FILE
  Size:         $BACKUP_SIZE
  Retention:    $BACKUP_RETENTION_DAYS days
  Metadata:     ${BACKUP_FILE}.meta

To restore from backup:
  sudo tar -xzf $BACKUP_FILE -C /

EOF
else
    echo "WARNING: No backup was created"
    echo ""
fi

log "INFO" "Deprovisioning completed at $(date)"

exit 0