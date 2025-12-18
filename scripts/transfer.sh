#!/bin/bash
# File transfer utility for storage provisioning
# File: scripts/transfer.sh
#
# Provides easy file transfer to/from user storage directories
# Supports upload, download, list, and sync operations

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source utilities
if [[ -f "$SCRIPT_DIR/utils.sh" ]]; then
    source "$SCRIPT_DIR/utils.sh"
fi

# Source config
if [[ -f "$SCRIPT_DIR/config.sh" ]]; then
    source "$SCRIPT_DIR/config.sh"
fi

# ============================================================================
# Constants
# ============================================================================

VERSION="1.0.0"
STORAGE_BASE="${STORAGE_BASE:-/home/storage_users}"

# ============================================================================
# Usage
# ============================================================================

usage() {
    cat << 'EOF'
Usage: transfer.sh <command> [options] <args>

File transfer utility for storage user directories.

Commands:
    upload <username> <local_file> [remote_dir]
        Upload a file to user's storage directory
        remote_dir defaults to 'data/'

    download <username> <remote_file> [local_dir]
        Download a file from user's storage directory
        local_dir defaults to current directory

    sync-up <username> <local_dir> [remote_dir]
        Sync a local directory TO user's storage (upload)
        remote_dir defaults to 'data/'

    sync-down <username> <remote_dir> [local_dir]
        Sync FROM user's storage to local directory (download)
        local_dir defaults to current directory

    list <username> [subdir]
        List files in user's storage directory

    usage <username>
        Show disk usage for a user

    share <username> <file> [expiry_hours]
        Generate a temporary download command/link
        expiry_hours defaults to 24

Options:
    -r, --remote HOST       Remote server (user@host) for remote transfers
    -p, --port PORT         SSH port (default: 22)
    -k, --key KEYFILE       SSH private key file
    -n, --dry-run           Show what would be transferred without doing it
    -v, --verbose           Enable verbose output
    -q, --quiet             Suppress non-essential output
    --compress              Enable compression for transfer
    --delete                Delete extraneous files during sync (careful!)
    --help                  Show this help message
    --version               Show version

Examples:
    # Local transfers (on the server itself)
    transfer.sh upload alice report.zip
    transfer.sh download alice report.zip ./downloads/
    transfer.sh list alice
    transfer.sh sync-up alice ./project/ data/project/

    # Remote transfers (from your PC to server)
    transfer.sh upload alice report.zip -r admin@192.168.1.100
    transfer.sh download alice data/report.zip -r admin@192.168.1.100
    transfer.sh sync-up alice ./local-folder/ -r admin@192.168.1.100

    # With SSH key
    transfer.sh upload alice file.zip -r admin@server -k ~/.ssh/id_rsa

EOF
}

version() {
    echo "transfer.sh version $VERSION"
    echo "Part of Automated Storage Provisioning Tool"
}

# ============================================================================
# Helper Functions
# ============================================================================

# Build SSH options string
build_ssh_opts() {
    local opts="-o StrictHostKeyChecking=accept-new -o BatchMode=yes"

    if [[ -n "$SSH_PORT" ]]; then
        opts="$opts -p $SSH_PORT"
    fi

    if [[ -n "$SSH_KEY" ]]; then
        opts="$opts -i $SSH_KEY"
    fi

    echo "$opts"
}

# Build rsync options
build_rsync_opts() {
    local opts="-ah --progress"

    if [[ "$VERBOSE" == true ]]; then
        opts="$opts -v"
    fi

    if [[ "$QUIET" == true ]]; then
        opts="$opts -q"
    fi

    if [[ "$COMPRESS" == true ]]; then
        opts="$opts -z"
    fi

    if [[ "$DRY_RUN" == true ]]; then
        opts="$opts -n"
    fi

    if [[ "$DELETE_EXTRA" == true ]]; then
        opts="$opts --delete"
    fi

    echo "$opts"
}

# Get user's storage path
get_user_path() {
    local username="$1"
    local subdir="${2:-}"

    local path="$STORAGE_BASE/$username"
    if [[ -n "$subdir" ]]; then
        path="$path/$subdir"
    fi

    echo "$path"
}

# Check if user exists (local check)
check_user_local() {
    local username="$1"

    if ! id "$username" &>/dev/null; then
        echo "[ERROR] User '$username' does not exist" >&2
        return 1
    fi

    local user_path="$STORAGE_BASE/$username"
    if [[ ! -d "$user_path" ]]; then
        echo "[ERROR] User storage directory does not exist: $user_path" >&2
        return 1
    fi

    return 0
}

# Check if user exists (remote check)
check_user_remote() {
    local username="$1"
    local ssh_opts
    ssh_opts=$(build_ssh_opts)

    # shellcheck disable=SC2086
    if ! ssh $ssh_opts "$REMOTE_HOST" "id '$username'" &>/dev/null; then
        echo "[ERROR] User '$username' does not exist on remote server" >&2
        return 1
    fi

    return 0
}

# Format file size
format_size() {
    local size="$1"
    if command -v numfmt &>/dev/null; then
        numfmt --to=iec-i --suffix=B "$size"
    else
        echo "${size} bytes"
    fi
}

# ============================================================================
# Transfer Operations
# ============================================================================

# Upload file to user's storage
do_upload() {
    local username="$1"
    local local_file="$2"
    local remote_dir="${3:-data}"

    # Validate local file exists
    if [[ ! -f "$local_file" ]]; then
        echo "[ERROR] Local file does not exist: $local_file" >&2
        return 1
    fi

    local filename
    filename=$(basename "$local_file")
    local filesize
    filesize=$(stat -f%z "$local_file" 2>/dev/null || stat -c%s "$local_file" 2>/dev/null || echo "unknown")

    if [[ -n "$REMOTE_HOST" ]]; then
        # Remote upload
        echo "[INFO] Uploading to remote server..."
        echo "  File: $local_file ($(format_size "$filesize"))"
        echo "  Destination: $REMOTE_HOST:$(get_user_path "$username" "$remote_dir")/"

        local ssh_opts rsync_opts
        ssh_opts=$(build_ssh_opts)
        rsync_opts=$(build_rsync_opts)

        local dest_path
        dest_path=$(get_user_path "$username" "$remote_dir")

        # shellcheck disable=SC2086
        rsync $rsync_opts -e "ssh $ssh_opts" "$local_file" "$REMOTE_HOST:$dest_path/"
    else
        # Local upload (copy within server)
        check_user_local "$username" || return 1

        local dest_path
        dest_path=$(get_user_path "$username" "$remote_dir")

        echo "[INFO] Copying file to user storage..."
        echo "  File: $local_file ($(format_size "$filesize"))"
        echo "  Destination: $dest_path/"

        if [[ "$DRY_RUN" == true ]]; then
            echo "[DRY-RUN] Would copy: $local_file -> $dest_path/"
        else
            # Ensure destination directory exists
            sudo mkdir -p "$dest_path"
            sudo cp "$local_file" "$dest_path/"
            sudo chown "$username:$DEFAULT_GROUP" "$dest_path/$filename"
            echo "[SUCCESS] File uploaded: $dest_path/$filename"
        fi
    fi
}

# Download file from user's storage
do_download() {
    local username="$1"
    local remote_file="$2"
    local local_dir="${3:-.}"

    # Ensure local directory exists
    mkdir -p "$local_dir"

    if [[ -n "$REMOTE_HOST" ]]; then
        # Remote download
        local src_path
        src_path=$(get_user_path "$username" "$remote_file")

        echo "[INFO] Downloading from remote server..."
        echo "  Source: $REMOTE_HOST:$src_path"
        echo "  Destination: $local_dir/"

        local ssh_opts rsync_opts
        ssh_opts=$(build_ssh_opts)
        rsync_opts=$(build_rsync_opts)

        # shellcheck disable=SC2086
        rsync $rsync_opts -e "ssh $ssh_opts" "$REMOTE_HOST:$src_path" "$local_dir/"
    else
        # Local download (copy within server)
        check_user_local "$username" || return 1

        local src_path
        src_path=$(get_user_path "$username" "$remote_file")

        if [[ ! -e "$src_path" ]]; then
            echo "[ERROR] Remote file does not exist: $src_path" >&2
            return 1
        fi

        echo "[INFO] Copying file from user storage..."
        echo "  Source: $src_path"
        echo "  Destination: $local_dir/"

        if [[ "$DRY_RUN" == true ]]; then
            echo "[DRY-RUN] Would copy: $src_path -> $local_dir/"
        else
            sudo cp "$src_path" "$local_dir/"
            local filename
            filename=$(basename "$src_path")
            # Fix ownership to current user
            sudo chown "$(whoami)" "$local_dir/$filename"
            echo "[SUCCESS] File downloaded: $local_dir/$filename"
        fi
    fi
}

# Sync local directory to user's storage (upload)
do_sync_up() {
    local username="$1"
    local local_dir="$2"
    local remote_dir="${3:-data}"

    # Validate local directory
    if [[ ! -d "$local_dir" ]]; then
        echo "[ERROR] Local directory does not exist: $local_dir" >&2
        return 1
    fi

    # Ensure trailing slash for rsync
    local_dir="${local_dir%/}/"

    local rsync_opts
    rsync_opts=$(build_rsync_opts)

    if [[ -n "$REMOTE_HOST" ]]; then
        # Remote sync
        local dest_path
        dest_path=$(get_user_path "$username" "$remote_dir")

        echo "[INFO] Syncing to remote server..."
        echo "  Source: $local_dir"
        echo "  Destination: $REMOTE_HOST:$dest_path/"

        local ssh_opts
        ssh_opts=$(build_ssh_opts)

        # shellcheck disable=SC2086
        rsync $rsync_opts -e "ssh $ssh_opts" "$local_dir" "$REMOTE_HOST:$dest_path/"
    else
        # Local sync
        check_user_local "$username" || return 1

        local dest_path
        dest_path=$(get_user_path "$username" "$remote_dir")

        echo "[INFO] Syncing to user storage..."
        echo "  Source: $local_dir"
        echo "  Destination: $dest_path/"

        sudo mkdir -p "$dest_path"

        # shellcheck disable=SC2086
        sudo rsync $rsync_opts "$local_dir" "$dest_path/"
        sudo chown -R "$username:$DEFAULT_GROUP" "$dest_path"

        echo "[SUCCESS] Sync complete"
    fi
}

# Sync from user's storage to local directory (download)
do_sync_down() {
    local username="$1"
    local remote_dir="$2"
    local local_dir="${3:-.}"

    # Ensure local directory exists
    mkdir -p "$local_dir"

    local rsync_opts
    rsync_opts=$(build_rsync_opts)

    if [[ -n "$REMOTE_HOST" ]]; then
        # Remote sync
        local src_path
        src_path=$(get_user_path "$username" "$remote_dir")

        echo "[INFO] Syncing from remote server..."
        echo "  Source: $REMOTE_HOST:$src_path/"
        echo "  Destination: $local_dir/"

        local ssh_opts
        ssh_opts=$(build_ssh_opts)

        # shellcheck disable=SC2086
        rsync $rsync_opts -e "ssh $ssh_opts" "$REMOTE_HOST:$src_path/" "$local_dir/"
    else
        # Local sync
        check_user_local "$username" || return 1

        local src_path
        src_path=$(get_user_path "$username" "$remote_dir")

        if [[ ! -d "$src_path" ]]; then
            echo "[ERROR] Remote directory does not exist: $src_path" >&2
            return 1
        fi

        echo "[INFO] Syncing from user storage..."
        echo "  Source: $src_path/"
        echo "  Destination: $local_dir/"

        # shellcheck disable=SC2086
        sudo rsync $rsync_opts "$src_path/" "$local_dir/"
        sudo chown -R "$(whoami)" "$local_dir"

        echo "[SUCCESS] Sync complete"
    fi
}

# List files in user's storage
do_list() {
    local username="$1"
    local subdir="${2:-}"

    if [[ -n "$REMOTE_HOST" ]]; then
        # Remote list
        local path
        path=$(get_user_path "$username" "$subdir")

        local ssh_opts
        ssh_opts=$(build_ssh_opts)

        echo "=== Files in $REMOTE_HOST:$path ==="
        # shellcheck disable=SC2086
        ssh $ssh_opts "$REMOTE_HOST" "ls -lah '$path' 2>/dev/null" || echo "Directory not found or empty"
    else
        # Local list
        check_user_local "$username" || return 1

        local path
        path=$(get_user_path "$username" "$subdir")

        echo "=== Files in $path ==="
        if [[ -d "$path" ]]; then
            ls -lah "$path"
        else
            echo "Directory not found: $path"
        fi
    fi
}

# Show disk usage for user
do_usage() {
    local username="$1"

    if [[ -n "$REMOTE_HOST" ]]; then
        # Remote usage
        local path
        path=$(get_user_path "$username")

        local ssh_opts
        ssh_opts=$(build_ssh_opts)

        echo "=== Disk Usage for $username on $REMOTE_HOST ==="
        # shellcheck disable=SC2086
        ssh $ssh_opts "$REMOTE_HOST" "du -sh '$path'/* 2>/dev/null | sort -h"
        echo ""
        # shellcheck disable=SC2086
        ssh $ssh_opts "$REMOTE_HOST" "du -sh '$path' 2>/dev/null"
    else
        # Local usage
        check_user_local "$username" || return 1

        local path
        path=$(get_user_path "$username")

        echo "=== Disk Usage for $username ==="
        echo ""
        echo "By subdirectory:"
        sudo du -sh "$path"/* 2>/dev/null | sort -h || echo "No subdirectories"
        echo ""
        echo "Total:"
        sudo du -sh "$path"
        echo ""

        # Show quota if available
        if command -v xfs_quota &>/dev/null; then
            echo "Quota:"
            sudo xfs_quota -x -c "quota -h -u $username" / 2>/dev/null || true
        fi
    fi
}

# Generate share command
do_share() {
    local username="$1"
    local file="$2"
    local expiry_hours="${3:-24}"

    local full_path
    full_path=$(get_user_path "$username" "$file")

    echo "=== Share Instructions ==="
    echo ""
    echo "File: $full_path"
    echo "Expires: $expiry_hours hours (manual enforcement)"
    echo ""

    if [[ -n "$REMOTE_HOST" ]]; then
        echo "Download command (run on destination machine):"
        echo ""
        echo "  scp $REMOTE_HOST:$full_path ./"
        echo ""
        echo "Or with rsync:"
        echo ""
        echo "  rsync -avz $REMOTE_HOST:$full_path ./"
    else
        echo "This file is on the local server at:"
        echo "  $full_path"
        echo ""
        echo "To download from a remote machine:"
        echo "  scp user@$(hostname -I | awk '{print $1}'):$full_path ./"
    fi
}

# ============================================================================
# Main
# ============================================================================

main() {
    local command=""
    local args=()

    # Options
    REMOTE_HOST=""
    SSH_PORT=""
    SSH_KEY=""
    DRY_RUN=false
    VERBOSE=false
    QUIET=false
    COMPRESS=false
    DELETE_EXTRA=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            upload|download|sync-up|sync-down|list|usage|share)
                command="$1"
                shift
                ;;
            -r|--remote)
                REMOTE_HOST="$2"
                shift 2
                ;;
            -p|--port)
                SSH_PORT="$2"
                shift 2
                ;;
            -k|--key)
                SSH_KEY="$2"
                shift 2
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            --compress)
                COMPRESS=true
                shift
                ;;
            --delete)
                DELETE_EXTRA=true
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
                echo "[ERROR] Unknown option: $1" >&2
                usage
                exit 1
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    # Validate command
    if [[ -z "$command" ]]; then
        echo "[ERROR] No command specified" >&2
        usage
        exit 1
    fi

    # Execute command
    case "$command" in
        upload)
            if [[ ${#args[@]} -lt 2 ]]; then
                echo "[ERROR] upload requires: <username> <local_file> [remote_dir]" >&2
                exit 1
            fi
            do_upload "${args[0]}" "${args[1]}" "${args[2]:-data}"
            ;;
        download)
            if [[ ${#args[@]} -lt 2 ]]; then
                echo "[ERROR] download requires: <username> <remote_file> [local_dir]" >&2
                exit 1
            fi
            do_download "${args[0]}" "${args[1]}" "${args[2]:-.}"
            ;;
        sync-up)
            if [[ ${#args[@]} -lt 2 ]]; then
                echo "[ERROR] sync-up requires: <username> <local_dir> [remote_dir]" >&2
                exit 1
            fi
            do_sync_up "${args[0]}" "${args[1]}" "${args[2]:-data}"
            ;;
        sync-down)
            if [[ ${#args[@]} -lt 2 ]]; then
                echo "[ERROR] sync-down requires: <username> <remote_dir> [local_dir]" >&2
                exit 1
            fi
            do_sync_down "${args[0]}" "${args[1]}" "${args[2]:-.}"
            ;;
        list)
            if [[ ${#args[@]} -lt 1 ]]; then
                echo "[ERROR] list requires: <username> [subdir]" >&2
                exit 1
            fi
            do_list "${args[0]}" "${args[1]:-}"
            ;;
        usage)
            if [[ ${#args[@]} -lt 1 ]]; then
                echo "[ERROR] usage requires: <username>" >&2
                exit 1
            fi
            do_usage "${args[0]}"
            ;;
        share)
            if [[ ${#args[@]} -lt 2 ]]; then
                echo "[ERROR] share requires: <username> <file> [expiry_hours]" >&2
                exit 1
            fi
            do_share "${args[0]}" "${args[1]}" "${args[2]:-24}"
            ;;
        *)
            echo "[ERROR] Unknown command: $command" >&2
            usage
            exit 1
            ;;
    esac
}

main "$@"
