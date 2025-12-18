#!/bin/bash
# Centralized configuration for storage provisioning
# File: scripts/config.sh
#
# This file defines all configurable parameters used across
# the storage provisioning scripts. Override values by:
#   1. Setting environment variables before sourcing
#   2. Creating /etc/storage-provisioning/config.conf
#   3. Creating ~/.storage-provisioning.conf (user-specific)

# ============================================================================
# Configuration Loading Order
# ============================================================================
# 1. Default values (defined below)
# 2. System config: /etc/storage-provisioning/config.conf
# 3. User config: ~/.storage-provisioning.conf
# 4. Environment variables (highest priority)

# Load system configuration if exists
SYSTEM_CONFIG="/etc/storage-provisioning/config.conf"
if [[ -f "$SYSTEM_CONFIG" ]]; then
    # shellcheck source=/dev/null
    source "$SYSTEM_CONFIG"
fi

# Load user configuration if exists
USER_CONFIG="${HOME}/.storage-provisioning.conf"
if [[ -f "$USER_CONFIG" ]]; then
    # shellcheck source=/dev/null
    source "$USER_CONFIG"
fi

# ============================================================================
# Storage Paths
# ============================================================================

# Base directory for user storage
export STORAGE_BASE="${STORAGE_BASE:-/home/storage_users}"

# Log directory for provisioning operations
export LOG_DIR="${LOG_DIR:-/var/log/storage-provisioning}"

# Directory for deprovisioned user backups
export BACKUP_DIR="${BACKUP_DIR:-/var/backups/deprovisioned_users}"

# ============================================================================
# User Defaults
# ============================================================================

# Default group for storage users
export DEFAULT_GROUP="${DEFAULT_GROUP:-storage_users}"

# Default quota for new users (format: number + M/G/T)
export DEFAULT_QUOTA="${DEFAULT_QUOTA:-10G}"

# Hard quota multiplier (hard = soft * multiplier)
export DEFAULT_QUOTA_HARD_MULTIPLIER="${DEFAULT_QUOTA_HARD_MULTIPLIER:-1.25}"

# Default shell for new users
export DEFAULT_SHELL="${DEFAULT_SHELL:-/bin/bash}"

# Default subdirectories to create for each user (comma-separated)
export DEFAULT_SUBDIRS="${DEFAULT_SUBDIRS:-data,backups,temp,logs}"

# ============================================================================
# SSH Configuration
# ============================================================================

# Directory for SSH configuration snippets
export SSH_CONFIG_DIR="${SSH_CONFIG_DIR:-/etc/ssh/sshd_config.d}"

# SSH configuration file for storage users
export SSH_STORAGE_CONF="${SSH_STORAGE_CONF:-storage_users.conf}"

# Full path to SSH storage users config
export SSH_STORAGE_CONF_PATH="${SSH_CONFIG_DIR}/${SSH_STORAGE_CONF}"

# Whether to allow SSH by default for new users (true/false)
export ALLOW_SSH_DEFAULT="${ALLOW_SSH_DEFAULT:-false}"

# ============================================================================
# Audit Configuration
# ============================================================================

# Directory for audit rules
export AUDIT_RULES_DIR="${AUDIT_RULES_DIR:-/etc/audit/rules.d}"

# Audit rules file for storage users
export AUDIT_RULES_FILE="${AUDIT_RULES_FILE:-storage_users.rules}"

# Full path to audit rules file
export AUDIT_RULES_PATH="${AUDIT_RULES_DIR}/${AUDIT_RULES_FILE}"

# Whether to enable audit logging (true/false)
export ENABLE_AUDIT="${ENABLE_AUDIT:-true}"

# ============================================================================
# Retention Policies
# ============================================================================

# Days to keep deprovisioned user backups
export BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"

# Days to keep log files
export LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-90}"

# Days to keep old backup archives before cleanup
export BACKUP_CLEANUP_DAYS="${BACKUP_CLEANUP_DAYS:-90}"

# ============================================================================
# Password Policy
# ============================================================================

# Length of generated temporary passwords
export PASSWORD_LENGTH="${PASSWORD_LENGTH:-16}"

# Force password change on first login (true/false)
export FORCE_PASSWORD_CHANGE="${FORCE_PASSWORD_CHANGE:-true}"

# Characters allowed in generated passwords
export PASSWORD_CHARS="${PASSWORD_CHARS:-A-Za-z0-9}"

# ============================================================================
# Feature Flags
# ============================================================================

# Enable SELinux context restoration (true/false)
export ENABLE_SELINUX="${ENABLE_SELINUX:-true}"

# Enable verbose logging (true/false)
export VERBOSE="${VERBOSE:-false}"

# Dry run mode - don't make changes (true/false)
export DRY_RUN="${DRY_RUN:-false}"

# ============================================================================
# Quota Configuration
# ============================================================================

# Minimum allowed quota (prevents misconfiguration)
export QUOTA_MIN="${QUOTA_MIN:-100M}"

# Maximum allowed quota
export QUOTA_MAX="${QUOTA_MAX:-10T}"

# Warning threshold percentage (warn when usage exceeds this)
export QUOTA_WARN_PERCENT="${QUOTA_WARN_PERCENT:-90}"

# Critical threshold percentage
export QUOTA_CRITICAL_PERCENT="${QUOTA_CRITICAL_PERCENT:-95}"

# ============================================================================
# Network/Sync Configuration (for sync_vm.sh)
# ============================================================================

# Default remote target for VM sync
export DEFAULT_REMOTE_TARGET="${DEFAULT_REMOTE_TARGET:-}"

# Default SSH key path
export DEFAULT_SSH_KEY="${DEFAULT_SSH_KEY:-${HOME}/.ssh/id_rsa}"

# Rsync options
export RSYNC_OPTIONS="${RSYNC_OPTIONS:--avz --progress}"

# Files/directories to exclude from sync (comma-separated)
export SYNC_EXCLUDES="${SYNC_EXCLUDES:-.git,logs,*.tmp,*.bak,__pycache__,.env}"

# ============================================================================
# Validation Functions
# ============================================================================

# Validate configuration values
validate_config() {
    local errors=0

    # Check storage base is an absolute path
    if [[ ! "$STORAGE_BASE" =~ ^/ ]]; then
        echo "[CONFIG ERROR] STORAGE_BASE must be an absolute path: $STORAGE_BASE" >&2
        ((errors++))
    fi

    # Check quota format
    if [[ ! "$DEFAULT_QUOTA" =~ ^[0-9]+[MGT]?$ ]]; then
        echo "[CONFIG ERROR] Invalid DEFAULT_QUOTA format: $DEFAULT_QUOTA" >&2
        ((errors++))
    fi

    # Check multiplier is a valid number
    if ! [[ "$DEFAULT_QUOTA_HARD_MULTIPLIER" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        echo "[CONFIG ERROR] Invalid DEFAULT_QUOTA_HARD_MULTIPLIER: $DEFAULT_QUOTA_HARD_MULTIPLIER" >&2
        ((errors++))
    fi

    # Check retention days are positive integers
    if ! [[ "$BACKUP_RETENTION_DAYS" =~ ^[0-9]+$ ]] || [[ "$BACKUP_RETENTION_DAYS" -lt 1 ]]; then
        echo "[CONFIG ERROR] BACKUP_RETENTION_DAYS must be a positive integer: $BACKUP_RETENTION_DAYS" >&2
        ((errors++))
    fi

    # Check password length
    if ! [[ "$PASSWORD_LENGTH" =~ ^[0-9]+$ ]] || [[ "$PASSWORD_LENGTH" -lt 8 ]]; then
        echo "[CONFIG ERROR] PASSWORD_LENGTH must be at least 8: $PASSWORD_LENGTH" >&2
        ((errors++))
    fi

    return $errors
}

# Print current configuration (for debugging)
print_config() {
    cat << EOF
=== Storage Provisioning Configuration ===

Storage Paths:
  STORAGE_BASE:              $STORAGE_BASE
  LOG_DIR:                   $LOG_DIR
  BACKUP_DIR:                $BACKUP_DIR

User Defaults:
  DEFAULT_GROUP:             $DEFAULT_GROUP
  DEFAULT_QUOTA:             $DEFAULT_QUOTA
  DEFAULT_QUOTA_HARD_MULT:   $DEFAULT_QUOTA_HARD_MULTIPLIER
  DEFAULT_SHELL:             $DEFAULT_SHELL
  DEFAULT_SUBDIRS:           $DEFAULT_SUBDIRS

SSH Configuration:
  SSH_CONFIG_DIR:            $SSH_CONFIG_DIR
  SSH_STORAGE_CONF:          $SSH_STORAGE_CONF
  ALLOW_SSH_DEFAULT:         $ALLOW_SSH_DEFAULT

Audit Configuration:
  AUDIT_RULES_DIR:           $AUDIT_RULES_DIR
  AUDIT_RULES_FILE:          $AUDIT_RULES_FILE
  ENABLE_AUDIT:              $ENABLE_AUDIT

Retention Policies:
  BACKUP_RETENTION_DAYS:     $BACKUP_RETENTION_DAYS
  LOG_RETENTION_DAYS:        $LOG_RETENTION_DAYS
  BACKUP_CLEANUP_DAYS:       $BACKUP_CLEANUP_DAYS

Password Policy:
  PASSWORD_LENGTH:           $PASSWORD_LENGTH
  FORCE_PASSWORD_CHANGE:     $FORCE_PASSWORD_CHANGE

Feature Flags:
  ENABLE_SELINUX:            $ENABLE_SELINUX
  VERBOSE:                   $VERBOSE
  DRY_RUN:                   $DRY_RUN

Quota Configuration:
  QUOTA_MIN:                 $QUOTA_MIN
  QUOTA_MAX:                 $QUOTA_MAX
  QUOTA_WARN_PERCENT:        $QUOTA_WARN_PERCENT
  QUOTA_CRITICAL_PERCENT:    $QUOTA_CRITICAL_PERCENT

Configuration Sources:
  System config:             $SYSTEM_CONFIG $([ -f "$SYSTEM_CONFIG" ] && echo "(loaded)" || echo "(not found)")
  User config:               $USER_CONFIG $([ -f "$USER_CONFIG" ] && echo "(loaded)" || echo "(not found)")

EOF
}

# ============================================================================
# Helper Functions
# ============================================================================

# Parse subdirs string into array
get_subdirs_array() {
    local IFS=','
    read -ra SUBDIRS_ARRAY <<< "$DEFAULT_SUBDIRS"
    echo "${SUBDIRS_ARRAY[@]}"
}

# Get config value with fallback
get_config() {
    local key="$1"
    local default="${2:-}"
    local value

    value="${!key:-$default}"
    echo "$value"
}

# Check if running in dry run mode
is_dry_run() {
    [[ "$DRY_RUN" == "true" ]]
}

# Check if verbose mode is enabled
is_verbose() {
    [[ "$VERBOSE" == "true" ]]
}

# ============================================================================
# Export Functions
# ============================================================================

export -f validate_config
export -f print_config
export -f get_subdirs_array
export -f get_config
export -f is_dry_run
export -f is_verbose

# ============================================================================
# Auto-validation (optional, uncomment to enable)
# ============================================================================

# Uncomment the following line to validate config on source
# validate_config || echo "[WARNING] Configuration validation failed" >&2
