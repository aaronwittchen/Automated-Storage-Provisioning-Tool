#!/bin/bash
# Enhanced utility functions for storage provisioning
# File: scripts/utils.sh

set -euo pipefail

# Get the directory where this script is located
UTILS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source centralized configuration if available
if [[ -f "$UTILS_SCRIPT_DIR/config.sh" ]]; then
    # shellcheck source=./config.sh
    source "$UTILS_SCRIPT_DIR/config.sh"
fi

# Configuration (with fallbacks if config.sh not loaded)
LOG_DIR="${LOG_DIR:-/var/log/storage-provisioning}"
LOG_FILE="$LOG_DIR/provisioning.log"
STORAGE_BASE="${STORAGE_BASE:-/home/storage_users}"
DEFAULT_GROUP="${DEFAULT_GROUP:-storage_users}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ============================================================================
# Logging Functions
# ============================================================================

ensure_log_dir() {
    if [ ! -d "$LOG_DIR" ]; then
        sudo mkdir -p "$LOG_DIR"
        sudo chmod 755 "$LOG_DIR"
    fi
    
    # Ensure log file exists and is writable
    if [ ! -f "$LOG_FILE" ]; then
        sudo touch "$LOG_FILE"
        sudo chmod 644 "$LOG_FILE"
    fi
}

log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    
    ensure_log_dir
    
    # Log to file
    echo "[$timestamp] [$level] $message" | sudo tee -a "$LOG_FILE" > /dev/null
    
    # Also output to console with colors
    case "$level" in
        ERROR)
            echo -e "${RED}[ERROR]${NC} $message" >&2
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
        INFO)
            echo -e "${GREEN}[INFO]${NC} $message"
            ;;
        *)
            echo "[$level] $message"
            ;;
    esac
}

# ============================================================================
# Validation Functions
# ============================================================================

validate_username() {
    local username=$1
    
    # Check format: lowercase letters, numbers, underscores, hyphens (3-16 chars)
    if [[ ! "$username" =~ ^[a-z][a-z0-9_-]{2,15}$ ]]; then
        log "ERROR" "Invalid username: $username (must be 3-16 chars, start with letter, lowercase only)"
        return 1
    fi
    
    # Check against reserved names
    local reserved_names=("root" "admin" "administrator" "system" "daemon" "bin" "sys")
    for reserved in "${reserved_names[@]}"; do
        if [ "$username" = "$reserved" ]; then
            log "ERROR" "Username $username is reserved"
            return 1
        fi
    done
    
    return 0
}

validate_quota() {
    local quota=$1
    
    # Check format: number followed by optional unit (M, G, T)
    if [[ ! "$quota" =~ ^[0-9]+[MGT]?$ ]]; then
        log "ERROR" "Invalid quota format: $quota (use format like 10G, 500M, 1T)"
        return 1
    fi
    
    # Extract numeric value and unit
    local value="${quota//[^0-9]/}"
    local unit="${quota//[0-9]/}"
    
    # Default to G if no unit specified
    unit="${unit:-G}"
    
    # Convert to MB for range checking
    local mb_value
    case "$unit" in
        M) mb_value=$value ;;
        G) mb_value=$((value * 1024)) ;;
        T) mb_value=$((value * 1024 * 1024)) ;;
    esac
    
    # Check reasonable limits (1MB to 10TB)
    if [ "$mb_value" -lt 1 ] || [ "$mb_value" -gt 10485760 ]; then
        log "ERROR" "Quota $quota is outside reasonable limits (1M - 10T)"
        return 1
    fi
    
    return 0
}

validate_storage_base() {
    if [ ! -d "$STORAGE_BASE" ]; then
        log "ERROR" "Storage base directory $STORAGE_BASE does not exist"
        return 1
    fi
    
    if [ ! -w "$STORAGE_BASE" ] && [ "$EUID" -ne 0 ]; then
        log "ERROR" "Storage base directory $STORAGE_BASE is not writable"
        return 1
    fi
    
    return 0
}

check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        if ! sudo -n true 2>/dev/null; then
            log "ERROR" "This script requires sudo privileges"
            echo "Please run with sudo or ensure your user has passwordless sudo access"
            return 1
        fi
    fi
    return 0
}

# ============================================================================
# Quota Functions
# ============================================================================

get_quota_mount() {
    local path=$1
    df -P "$path" 2>/dev/null | tail -1 | awk '{print $6}'
}

get_filesystem_type() {
    local mount_point=$1
    df -T "$mount_point" 2>/dev/null | tail -1 | awk '{print $2}'
}

validate_quota_support() {
    local mount_point=$(get_quota_mount "$STORAGE_BASE")
    local fs_type=$(get_filesystem_type "$mount_point")
    
    log "INFO" "Checking quota support on $mount_point (filesystem: $fs_type)"
    
    # Check if filesystem supports quotas
    case "$fs_type" in
        xfs)
            if ! mount | grep " $mount_point " | grep -qE 'usrquota|uquota|prjquota'; then
                log "ERROR" "XFS quotas not enabled on $mount_point"
                log "ERROR" "Add 'usrquota,grpquota' to mount options in /etc/fstab and remount"
                return 1
            fi
            ;;
        ext4|ext3)
            if ! mount | grep " $mount_point " | grep -qE 'usrquota|grpquota'; then
                log "ERROR" "EXT quotas not enabled on $mount_point"
                log "ERROR" "Add 'usrquota,grpquota' to mount options in /etc/fstab and remount"
                return 1
            fi
            ;;
        *)
            log "WARN" "Filesystem type $fs_type may not support quotas"
            ;;
    esac
    
    # Check if quota commands are available
    if ! command -v xfs_quota &>/dev/null && ! command -v setquota &>/dev/null; then
        log "ERROR" "No quota management tools found (xfs_quota or quota-tools)"
        return 1
    fi
    
    return 0
}

set_user_quota() {
    local username=$1
    local quota=$2
    local mount_point=$(get_quota_mount "$STORAGE_BASE")
    local fs_type=$(get_filesystem_type "$mount_point")
    
    log "INFO" "Setting quota $quota for $username on $mount_point ($fs_type)"
    
    case "$fs_type" in
        xfs)
            if ! sudo xfs_quota -x -c "limit bsoft=${quota} bhard=${quota} $username" "$mount_point" 2>&1 | tee -a "$LOG_FILE"; then
                log "ERROR" "Failed to set XFS quota for $username"
                return 1
            fi
            ;;
        ext4|ext3)
            # Convert quota format for setquota (expects KB)
            local value="${quota//[^0-9]/}"
            local unit="${quota//[0-9]/}"
            unit="${unit:-G}"
            
            local kb_value
            case "$unit" in
                M) kb_value=$((value * 1024)) ;;
                G) kb_value=$((value * 1024 * 1024)) ;;
                T) kb_value=$((value * 1024 * 1024 * 1024)) ;;
            esac
            
            if ! sudo setquota -u "$username" "$kb_value" "$kb_value" 0 0 "$mount_point" 2>&1 | tee -a "$LOG_FILE"; then
                log "ERROR" "Failed to set EXT quota for $username"
                return 1
            fi
            ;;
        *)
            log "WARN" "Cannot set quota on unsupported filesystem: $fs_type"
            return 1
            ;;
    esac
    
    return 0
}

remove_user_quota() {
    local username=$1
    local mount_point=$(get_quota_mount "$STORAGE_BASE")
    local fs_type=$(get_filesystem_type "$mount_point")
    
    case "$fs_type" in
        xfs)
            sudo xfs_quota -x -c "limit bsoft=0 bhard=0 $username" "$mount_point" 2>/dev/null || true
            ;;
        ext4|ext3)
            sudo setquota -u "$username" 0 0 0 0 "$mount_point" 2>/dev/null || true
            ;;
    esac
}

# ============================================================================
# User Management Functions
# ============================================================================

user_exists() {
    local username=$1
    id "$username" &>/dev/null
}

group_exists() {
    local groupname=$1
    getent group "$groupname" > /dev/null
}

get_user_home() {
    local username=$1
    getent passwd "$username" | cut -d: -f6
}

# ============================================================================
# Security Functions
# ============================================================================

generate_secure_password() {
    local length=${1:-16}
    
    # Use multiple methods as fallback
    if command -v openssl &>/dev/null; then
        openssl rand -base64 "$length" | tr -d "=+/" | cut -c1-"$length"
    elif [ -c /dev/urandom ]; then
        tr -dc 'A-Za-z0-9!@#$%^&*' < /dev/urandom | head -c "$length"
    else
        log "ERROR" "No secure random source available"
        return 1
    fi
}

# ============================================================================
# System Information
# ============================================================================

get_system_info() {
    echo "System Information:"
    echo "  OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    echo "  Kernel: $(uname -r)"
    echo "  Storage Base: $STORAGE_BASE"
    echo "  Quota Mount: $(get_quota_mount "$STORAGE_BASE")"
    echo "  Filesystem: $(get_filesystem_type "$(get_quota_mount "$STORAGE_BASE")")"
}

# ============================================================================
# Cleanup and Error Handling
# ============================================================================

emergency_cleanup() {
    local username=$1
    log "WARN" "Performing emergency cleanup for $username"
    
    # Kill user processes
    sudo pkill -u "$username" 2>/dev/null || true
    
    # Remove quota
    remove_user_quota "$username"
    
    # Remove user
    sudo userdel -r "$username" 2>/dev/null || true
    
    log "INFO" "Emergency cleanup completed for $username"
}

# ============================================================================
# Initialization
# ============================================================================

# Ensure log directory exists when script is sourced
ensure_log_dir

# Export functions for use in other scripts
export -f log
export -f validate_username
export -f validate_quota
export -f validate_storage_base
export -f check_sudo
export -f validate_quota_support
export -f set_user_quota
export -f remove_user_quota
export -f user_exists
export -f group_exists
export -f generate_secure_password
export -f emergency_cleanup
export -f get_quota_mount
export -f get_filesystem_type