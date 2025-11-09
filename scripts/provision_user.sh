#!/bin/bash
# Enhanced user provisioning script

set -euo pipefail

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Configuration
STORAGE_BASE="${STORAGE_BASE:-/home/storage_users}"

# Ensure storage base exists
if [ ! -d "$STORAGE_BASE" ]; then
    sudo mkdir -p "$STORAGE_BASE"
    sudo chmod 755 "$STORAGE_BASE"
    log "INFO" "Created storage base directory: $STORAGE_BASE"
fi
DEFAULT_QUOTA="${DEFAULT_QUOTA:-10G}"
DEFAULT_GROUP="${DEFAULT_GROUP:-storage_users}"
SSH_DENY_CONFIG="/etc/ssh/sshd_config.d/storage_users.conf"

# ============================================================================
# Usage Information
# ============================================================================

show_usage() {
    cat << EOF
Usage: $0 <username> [options]

Provision a new storage user with quota and directory structure.

Arguments:
    username            Username for the new storage user (required)

Options:
    -q, --quota SIZE    Disk quota (default: $DEFAULT_QUOTA)
                        Examples: 5G, 500M, 1T
    -g, --group NAME    Primary group (default: $DEFAULT_GROUP)
    --allow-ssh         Allow SSH access (default: deny)
    --no-subdirs        Skip creating default subdirectories
    -h, --help          Show this help message

Examples:
    $0 john_doe
    $0 jane_smith -q 50G
    $0 admin_user -q 100G --allow-ssh

EOF
}

# ============================================================================
# Parse Arguments
# ============================================================================

USERNAME=""
QUOTA="$DEFAULT_QUOTA"
GROUP="$DEFAULT_GROUP"
ALLOW_SSH=false
CREATE_SUBDIRS=true

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -q|--quota)
            QUOTA="$2"
            shift 2
            ;;
        -g|--group)
            GROUP="$2"
            shift 2
            ;;
        --allow-ssh)
            ALLOW_SSH=true
            shift
            ;;
        --no-subdirs)
            CREATE_SUBDIRS=false
            shift
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

# Pre-flight checks
log "INFO" "Running pre-flight checks..."

check_sudo || exit 1
validate_username "$USERNAME" || exit 1
validate_quota "$QUOTA" || exit 1
validate_storage_base || exit 1
validate_quota_support || exit 1

# Check if user already exists
if user_exists "$USERNAME"; then
    log "ERROR" "User $USERNAME already exists"
    exit 1
fi

# ============================================================================
# Setup Cleanup Handler
# ============================================================================

PROVISIONING_STARTED=false

cleanup_on_error() {
    local exit_code=$?
    if [ $exit_code -ne 0 ] && [ "$PROVISIONING_STARTED" = true ]; then
        log "ERROR" "Provisioning failed with exit code $exit_code"
        emergency_cleanup "$USERNAME"
    fi
}

trap cleanup_on_error EXIT

# ============================================================================
# Main Provisioning
# ============================================================================

log "INFO" "========================================="
log "INFO" "Starting provisioning for user: $USERNAME"
log "INFO" "Quota: $QUOTA"
log "INFO" "Group: $GROUP"
log "INFO" "SSH Access: $ALLOW_SSH"
log "INFO" "========================================="

PROVISIONING_STARTED=true

# Step 1: Create group if it doesn't exist
if ! group_exists "$GROUP"; then
    log "INFO" "Creating group: $GROUP"
    if ! sudo groupadd "$GROUP"; then
        log "ERROR" "Failed to create group $GROUP"
        exit 1
    fi
    log "INFO" "Group $GROUP created successfully"
else
    log "INFO" "Group $GROUP already exists"
fi

# Step 2: Create user
log "INFO" "Creating user $USERNAME..."
USER_HOME="$STORAGE_BASE/$USERNAME"

if ! sudo useradd -m -d "$USER_HOME" -g "$GROUP" -s /bin/bash "$USERNAME"; then
    log "ERROR" "Failed to create user $USERNAME"
    exit 1
fi
log "INFO" "User $USERNAME created successfully"

# Step 3: Generate and set secure password
log "INFO" "Generating secure temporary password..."
TEMP_PASSWORD=$(generate_secure_password 16)

if [ -z "$TEMP_PASSWORD" ]; then
    log "ERROR" "Failed to generate secure password"
    exit 1
fi

if ! echo "$USERNAME:$TEMP_PASSWORD" | sudo chpasswd; then
    log "ERROR" "Failed to set password for $USERNAME"
    exit 1
fi

# Force password change on first login
if ! sudo chage -d 0 "$USERNAME"; then
    log "WARN" "Failed to force password change on first login"
fi

log "INFO" "Temporary password set successfully"

# Step 4: Set directory permissions
log "INFO" "Setting directory permissions..."
if ! sudo chmod 700 "$USER_HOME"; then
    log "ERROR" "Failed to set permissions on $USER_HOME"
    exit 1
fi

if ! sudo chown "$USERNAME:$GROUP" "$USER_HOME"; then
    log "ERROR" "Failed to set ownership on $USER_HOME"
    exit 1
fi

log "INFO" "Directory permissions set successfully"

# Step 5: Set quota
log "INFO" "Setting disk quota..."
if ! set_user_quota "$USERNAME" "$QUOTA"; then
    log "ERROR" "Failed to set quota for $USERNAME"
    exit 1
fi
log "INFO" "Quota set successfully"

# Step 6: Create subdirectories
if [ "$CREATE_SUBDIRS" = true ]; then
    log "INFO" "Creating subdirectories..."
    
    SUBDIRS=("data" "backups" "temp" "logs")
    for subdir in "${SUBDIRS[@]}"; do
        if ! sudo -u "$USERNAME" mkdir -p "$USER_HOME/$subdir"; then
            log "WARN" "Failed to create subdirectory: $subdir"
        else
            log "INFO" "Created subdirectory: $subdir"
        fi
    done
    
    # Create a README file
    README_CONTENT="Storage User: $USERNAME
Created: $(date)
Quota: $QUOTA

Directory Structure:
- data/    : Primary data storage
- backups/ : Backup files
- temp/    : Temporary files (cleaned periodically)
- logs/    : Application logs

For support, contact your system administrator.
"
    echo "$README_CONTENT" | sudo -u "$USERNAME" tee "$USER_HOME/README.txt" > /dev/null
    log "INFO" "Created README.txt"
fi

# Step 7: Configure SSH access
if [ "$ALLOW_SSH" = false ]; then
    log "INFO" "Denying SSH access..."
    sudo mkdir -p "$(dirname "$SSH_DENY_CONFIG")"
    
    if ! grep -q "DenyUsers.*$USERNAME" "$SSH_DENY_CONFIG" 2>/dev/null; then
        echo "DenyUsers $USERNAME" | sudo tee -a "$SSH_DENY_CONFIG" > /dev/null
        log "INFO" "SSH access denied for $USERNAME"
        
        # Reload SSH config
        if sudo systemctl reload sshd 2>/dev/null || sudo systemctl reload ssh 2>/dev/null; then
            log "INFO" "SSH configuration reloaded"
        else
            log "WARN" "Could not reload SSH service automatically"
        fi
    fi
else
    log "INFO" "SSH access allowed for $USERNAME"
fi

# Step 8: Set SELinux context (if applicable)
if command -v restorecon &>/dev/null && [ -f /etc/selinux/config ]; then
    log "INFO" "Setting SELinux context..."
    sudo restorecon -R "$USER_HOME" 2>/dev/null || log "WARN" "Could not set SELinux context"
fi

# Step 9: Add audit rules (if auditd is available)
if command -v auditctl &>/dev/null; then
    log "INFO" "Adding audit rule for user directory..."
    AUDIT_RULE="-w $USER_HOME -p wa -k storage_access_$USERNAME"
    echo "$AUDIT_RULE" | sudo tee -a /etc/audit/rules.d/storage_users.rules > /dev/null 2>&1 || true
fi

# ============================================================================
# Success Output
# ============================================================================

PROVISIONING_STARTED=false  # Disable cleanup on normal exit

log "INFO" "========================================="
log "INFO" "User $USERNAME provisioned successfully!"
log "INFO" "========================================="

cat << EOF

┌─────────────────────────────────────────────────────────┐
│  USER PROVISIONING SUCCESSFUL                        │
└─────────────────────────────────────────────────────────┘

User Information:
  Username:     $USERNAME
  Group:        $GROUP
  Home:         $USER_HOME
  Quota:        $QUOTA
  SSH Access:   $ALLOW_SSH

IMPORTANT - SAVE THIS INFORMATION!
  
  Temporary Password: $TEMP_PASSWORD
  
  This password will not be shown again!
  User must change password on first login.

Next Steps:
  1. Share credentials securely with user
  2. Instruct user to change password on first login
  3. Configure any additional access controls as needed

To check quota usage:
  sudo xfs_quota -x -c "report -h" $(get_quota_mount "$STORAGE_BASE")

To deprovision user:
  $SCRIPT_DIR/deprovision_user.sh $USERNAME

EOF

log "INFO" "Provisioning completed at $(date)"

exit 0