#!/bin/bash
# Standalone quota management utility
# File: scripts/set_quota.sh
#
# Provides a unified interface to manage disk quotas across
# different filesystem types (XFS, EXT4, EXT3, Btrfs, ZFS)

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source utility functions
if [[ -f "$SCRIPT_DIR/utils.sh" ]]; then
    source "$SCRIPT_DIR/utils.sh"
else
    echo "[ERROR] Cannot find utils.sh in $SCRIPT_DIR" >&2
    exit 1
fi

# Source configuration if available
if [[ -f "$SCRIPT_DIR/config.sh" ]]; then
    source "$SCRIPT_DIR/config.sh"
fi

# ============================================================================
# Constants and Defaults
# ============================================================================

VERSION="1.0.0"
DEFAULT_HARD_MULTIPLIER="${DEFAULT_QUOTA_HARD_MULTIPLIER:-1.25}"

# ============================================================================
# Usage and Help
# ============================================================================

usage() {
    cat << EOF
Usage: $(basename "$0") <command> [options] <username> [quota]

Standalone quota management utility for storage provisioning.
Supports XFS, EXT4, EXT3, Btrfs, and ZFS filesystems.

Commands:
    set <username> <quota>    Set quota for a user (e.g., 10G, 500M)
    show <username>           Display current quota for a user
    remove <username>         Remove quota restrictions for a user
    report                    Show quota report for all users
    check                     Check filesystem quota support

Options:
    -s, --soft QUOTA          Set soft limit (default: same as quota)
    -h, --hard QUOTA          Set hard limit (default: quota * ${DEFAULT_HARD_MULTIPLIER})
    -m, --mount MOUNT         Specify mount point (default: auto-detect)
    -f, --force               Skip confirmation prompts
    -v, --verbose             Enable verbose output
    --help                    Show this help message
    --version                 Show version information

Quota Format:
    <number>[M|G|T]           Examples: 500M, 10G, 1T
                              M = Megabytes, G = Gigabytes, T = Terabytes
                              If no unit specified, defaults to Gigabytes

Examples:
    $(basename "$0") set alice 10G
    $(basename "$0") set bob 5G --hard 6G
    $(basename "$0") show alice
    $(basename "$0") remove charlie
    $(basename "$0") report
    $(basename "$0") check

EOF
}

version() {
    echo "set_quota.sh version $VERSION"
    echo "Part of Automated Storage Provisioning Tool"
}

# ============================================================================
# Helper Functions
# ============================================================================

# Calculate hard quota as a multiplier of soft quota
calculate_hard_quota() {
    local soft="$1"
    local num="${soft%[MGT]}"
    local unit="${soft: -1}"

    if [[ "$unit" =~ [MGT] ]]; then
        # Has unit suffix
        local hard_num
        hard_num=$(awk "BEGIN {printf \"%.0f\", $num * $DEFAULT_HARD_MULTIPLIER}")
        echo "${hard_num}${unit}"
    else
        # No unit, assume it's in GB
        local hard_num
        hard_num=$(awk "BEGIN {printf \"%.0f\", $soft * $DEFAULT_HARD_MULTIPLIER}")
        echo "$hard_num"
    fi
}

# Convert quota to kilobytes for ext4/ext3
convert_to_kb() {
    local quota="$1"
    local num="${quota%[MGT]}"
    local unit="${quota: -1}"

    case "$unit" in
        M) echo $((num * 1024)) ;;
        G) echo $((num * 1024 * 1024)) ;;
        T) echo $((num * 1024 * 1024 * 1024)) ;;
        *)
            # No unit, assume GB
            echo $((quota * 1024 * 1024))
            ;;
    esac
}

# Convert quota to bytes for btrfs
convert_to_bytes() {
    local quota="$1"
    local num="${quota%[MGT]}"
    local unit="${quota: -1}"

    case "$unit" in
        M) echo $((num * 1024 * 1024)) ;;
        G) echo $((num * 1024 * 1024 * 1024)) ;;
        T) echo $((num * 1024 * 1024 * 1024 * 1024)) ;;
        *)
            # No unit, assume GB
            echo $((quota * 1024 * 1024 * 1024))
            ;;
    esac
}

# ============================================================================
# Quota Operations
# ============================================================================

# Set quota for a user
do_set_quota() {
    local username="$1"
    local soft_quota="$2"
    local hard_quota="${3:-$(calculate_hard_quota "$soft_quota")}"
    local mount_point="${4:-$(get_quota_mount "$STORAGE_BASE")}"
    local fs_type

    fs_type=$(get_filesystem_type "$mount_point")

    log "INFO" "Setting quota for $username: soft=$soft_quota, hard=$hard_quota on $mount_point ($fs_type)"

    case "$fs_type" in
        xfs)
            if ! sudo xfs_quota -x -c "limit bsoft=${soft_quota} bhard=${hard_quota} $username" "$mount_point"; then
                log "ERROR" "Failed to set XFS quota for $username"
                return 1
            fi
            ;;
        ext4|ext3)
            local soft_kb hard_kb
            soft_kb=$(convert_to_kb "$soft_quota")
            hard_kb=$(convert_to_kb "$hard_quota")

            if ! sudo setquota -u "$username" "$soft_kb" "$hard_kb" 0 0 "$mount_point"; then
                log "ERROR" "Failed to set EXT quota for $username"
                return 1
            fi
            ;;
        btrfs)
            local user_home="$STORAGE_BASE/$username"
            if btrfs subvolume show "$user_home" &>/dev/null 2>&1; then
                local quota_bytes
                quota_bytes=$(convert_to_bytes "$hard_quota")
                local qgroupid
                qgroupid=$(btrfs subvolume show "$user_home" 2>/dev/null | awk '/Subvolume ID/ {print "0/"$3}')
                if [[ -n "$qgroupid" ]]; then
                    if ! sudo btrfs qgroup limit "$quota_bytes" "$qgroupid" "$mount_point"; then
                        log "ERROR" "Failed to set Btrfs quota for $username"
                        return 1
                    fi
                else
                    log "ERROR" "Could not determine qgroup ID for $user_home"
                    return 1
                fi
            else
                log "WARN" "Btrfs quotas require user home to be a subvolume"
                log "WARN" "Create with: btrfs subvolume create $user_home"
                return 1
            fi
            ;;
        zfs)
            # Get the ZFS dataset for the storage base
            local dataset
            dataset=$(zfs list -H -o name "$STORAGE_BASE" 2>/dev/null | head -1)
            if [[ -n "$dataset" ]]; then
                if ! sudo zfs set quota="$hard_quota" "$dataset/$username" 2>/dev/null; then
                    log "ERROR" "Failed to set ZFS quota for $username"
                    log "WARN" "Ensure ZFS dataset exists: zfs create $dataset/$username"
                    return 1
                fi
            else
                log "ERROR" "Could not determine ZFS dataset for $STORAGE_BASE"
                return 1
            fi
            ;;
        *)
            log "ERROR" "Unsupported filesystem type: $fs_type"
            return 1
            ;;
    esac

    log "INFO" "Successfully set quota for $username"
    return 0
}

# Show quota for a user
do_show_quota() {
    local username="$1"
    local mount_point="${2:-$(get_quota_mount "$STORAGE_BASE")}"
    local fs_type

    fs_type=$(get_filesystem_type "$mount_point")

    echo "=== Quota Information for $username ==="
    echo "Mount point: $mount_point"
    echo "Filesystem:  $fs_type"
    echo ""

    case "$fs_type" in
        xfs)
            echo "XFS Quota:"
            sudo xfs_quota -x -c "quota -h -u $username" "$mount_point" 2>/dev/null || echo "No quota set or quotas not enabled"
            ;;
        ext4|ext3)
            echo "EXT Quota:"
            sudo quota -u "$username" 2>/dev/null || echo "No quota set or quotas not enabled"
            ;;
        btrfs)
            echo "Btrfs Quota:"
            local user_home="$STORAGE_BASE/$username"
            if btrfs subvolume show "$user_home" &>/dev/null 2>&1; then
                sudo btrfs qgroup show -r "$mount_point" 2>/dev/null | head -5
            else
                echo "User home is not a Btrfs subvolume"
            fi
            ;;
        zfs)
            echo "ZFS Quota:"
            local dataset
            dataset=$(zfs list -H -o name "$STORAGE_BASE" 2>/dev/null | head -1)
            if [[ -n "$dataset" ]]; then
                sudo zfs get quota,used,available "$dataset/$username" 2>/dev/null || echo "No ZFS dataset for user"
            else
                echo "Could not determine ZFS dataset"
            fi
            ;;
        *)
            echo "Unsupported filesystem type: $fs_type"
            return 1
            ;;
    esac

    # Also show disk usage
    echo ""
    echo "Current Usage:"
    local user_home="$STORAGE_BASE/$username"
    if [[ -d "$user_home" ]]; then
        du -sh "$user_home" 2>/dev/null || echo "Cannot determine usage"
    else
        echo "User directory does not exist"
    fi
}

# Remove quota for a user
do_remove_quota() {
    local username="$1"
    local mount_point="${2:-$(get_quota_mount "$STORAGE_BASE")}"
    local fs_type

    fs_type=$(get_filesystem_type "$mount_point")

    log "INFO" "Removing quota for $username on $mount_point ($fs_type)"

    case "$fs_type" in
        xfs)
            sudo xfs_quota -x -c "limit bsoft=0 bhard=0 $username" "$mount_point" 2>/dev/null || true
            ;;
        ext4|ext3)
            sudo setquota -u "$username" 0 0 0 0 "$mount_point" 2>/dev/null || true
            ;;
        btrfs)
            local user_home="$STORAGE_BASE/$username"
            if btrfs subvolume show "$user_home" &>/dev/null 2>&1; then
                local qgroupid
                qgroupid=$(btrfs subvolume show "$user_home" 2>/dev/null | awk '/Subvolume ID/ {print "0/"$3}')
                if [[ -n "$qgroupid" ]]; then
                    sudo btrfs qgroup limit none "$qgroupid" "$mount_point" 2>/dev/null || true
                fi
            fi
            ;;
        zfs)
            local dataset
            dataset=$(zfs list -H -o name "$STORAGE_BASE" 2>/dev/null | head -1)
            if [[ -n "$dataset" ]]; then
                sudo zfs set quota=none "$dataset/$username" 2>/dev/null || true
            fi
            ;;
        *)
            log "WARN" "Cannot remove quota on unsupported filesystem: $fs_type"
            ;;
    esac

    log "INFO" "Quota removed for $username"
}

# Show quota report for all users
do_report() {
    local mount_point="${1:-$(get_quota_mount "$STORAGE_BASE")}"
    local fs_type

    fs_type=$(get_filesystem_type "$mount_point")

    echo "=== Quota Report ==="
    echo "Mount point: $mount_point"
    echo "Filesystem:  $fs_type"
    echo "Generated:   $(date)"
    echo ""

    case "$fs_type" in
        xfs)
            echo "XFS Quota Report:"
            sudo xfs_quota -x -c "report -h" "$mount_point" 2>/dev/null || echo "Quotas not enabled"
            ;;
        ext4|ext3)
            echo "EXT Quota Report:"
            sudo repquota -u "$mount_point" 2>/dev/null || echo "Quotas not enabled"
            ;;
        btrfs)
            echo "Btrfs Qgroup Report:"
            sudo btrfs qgroup show -r "$mount_point" 2>/dev/null || echo "Quotas not enabled"
            ;;
        zfs)
            echo "ZFS Quota Report:"
            local dataset
            dataset=$(zfs list -H -o name "$STORAGE_BASE" 2>/dev/null | head -1)
            if [[ -n "$dataset" ]]; then
                sudo zfs list -o name,quota,used,available -r "$dataset" 2>/dev/null
            else
                echo "Could not determine ZFS dataset"
            fi
            ;;
        *)
            echo "Unsupported filesystem type: $fs_type"
            return 1
            ;;
    esac
}

# Check quota support
do_check() {
    local mount_point="${1:-$(get_quota_mount "$STORAGE_BASE")}"
    local fs_type

    fs_type=$(get_filesystem_type "$mount_point")

    echo "=== Quota Support Check ==="
    echo ""
    echo "Storage Base:  $STORAGE_BASE"
    echo "Mount Point:   $mount_point"
    echo "Filesystem:    $fs_type"
    echo ""

    echo "--- Mount Options ---"
    mount | grep " $mount_point " || echo "Could not find mount info"
    echo ""

    echo "--- Quota Tools ---"
    echo -n "xfs_quota:   "
    command -v xfs_quota &>/dev/null && echo "Available" || echo "Not found"

    echo -n "setquota:    "
    command -v setquota &>/dev/null && echo "Available" || echo "Not found"

    echo -n "quota:       "
    command -v quota &>/dev/null && echo "Available" || echo "Not found"

    echo -n "repquota:    "
    command -v repquota &>/dev/null && echo "Available" || echo "Not found"

    echo -n "btrfs:       "
    command -v btrfs &>/dev/null && echo "Available" || echo "Not found"

    echo -n "zfs:         "
    command -v zfs &>/dev/null && echo "Available" || echo "Not found"
    echo ""

    echo "--- Quota Status ---"
    if validate_quota_support; then
        echo -e "${GREEN}Quota support is properly configured${NC}"
        return 0
    else
        echo -e "${RED}Quota support needs configuration${NC}"
        echo ""
        echo "To enable quotas:"
        case "$fs_type" in
            xfs)
                echo "  1. Edit /etc/fstab and add 'usrquota,grpquota' to mount options"
                echo "  2. Run: sudo mount -o remount $mount_point"
                ;;
            ext4|ext3)
                echo "  1. Edit /etc/fstab and add 'usrquota,grpquota' to mount options"
                echo "  2. Run: sudo mount -o remount $mount_point"
                echo "  3. Run: sudo quotacheck -cum $mount_point"
                echo "  4. Run: sudo quotaon $mount_point"
                ;;
            btrfs)
                echo "  1. Run: sudo btrfs quota enable $mount_point"
                ;;
            zfs)
                echo "  ZFS quotas are set per-dataset, no global enable needed"
                ;;
        esac
        return 1
    fi
}

# ============================================================================
# Main Entry Point
# ============================================================================

main() {
    local command=""
    local username=""
    local quota=""
    local soft_quota=""
    local hard_quota=""
    local mount_point=""
    local force=false
    local verbose=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            set|show|remove|report|check)
                command="$1"
                shift
                ;;
            -s|--soft)
                soft_quota="$2"
                shift 2
                ;;
            -h|--hard)
                hard_quota="$2"
                shift 2
                ;;
            -m|--mount)
                mount_point="$2"
                shift 2
                ;;
            -f|--force)
                force=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            --version)
                version
                exit 0
                ;;
            -*)
                log "ERROR" "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                # Positional arguments
                if [[ -z "$username" ]]; then
                    username="$1"
                elif [[ -z "$quota" ]]; then
                    quota="$1"
                fi
                shift
                ;;
        esac
    done

    # Check for required command
    if [[ -z "$command" ]]; then
        log "ERROR" "No command specified"
        usage
        exit 1
    fi

    # Check sudo access for commands that need it
    if [[ "$command" != "check" ]] || [[ "$command" != "show" ]]; then
        check_sudo || exit 1
    fi

    # Execute command
    case "$command" in
        set)
            # Validate inputs
            if [[ -z "$username" ]]; then
                log "ERROR" "Username required for 'set' command"
                exit 1
            fi
            if [[ -z "$quota" ]]; then
                log "ERROR" "Quota required for 'set' command"
                exit 1
            fi

            validate_username "$username" || exit 1
            validate_quota "$quota" || exit 1

            if ! user_exists "$username"; then
                log "ERROR" "User '$username' does not exist"
                exit 1
            fi

            # Set soft quota if not specified
            soft_quota="${soft_quota:-$quota}"

            # Validate soft quota
            validate_quota "$soft_quota" || exit 1

            # Validate hard quota if specified
            if [[ -n "$hard_quota" ]]; then
                validate_quota "$hard_quota" || exit 1
            fi

            do_set_quota "$username" "$soft_quota" "$hard_quota" "$mount_point"
            ;;
        show)
            if [[ -z "$username" ]]; then
                log "ERROR" "Username required for 'show' command"
                exit 1
            fi

            validate_username "$username" || exit 1

            if ! user_exists "$username"; then
                log "ERROR" "User '$username' does not exist"
                exit 1
            fi

            do_show_quota "$username" "$mount_point"
            ;;
        remove)
            if [[ -z "$username" ]]; then
                log "ERROR" "Username required for 'remove' command"
                exit 1
            fi

            validate_username "$username" || exit 1

            if ! user_exists "$username"; then
                log "ERROR" "User '$username' does not exist"
                exit 1
            fi

            # Confirm unless force flag is set
            if [[ "$force" != true ]]; then
                echo -n "Remove quota for $username? [y/N] "
                read -r confirm
                if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                    echo "Aborted."
                    exit 0
                fi
            fi

            do_remove_quota "$username" "$mount_point"
            ;;
        report)
            do_report "$mount_point"
            ;;
        check)
            do_check "$mount_point"
            ;;
        *)
            log "ERROR" "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
