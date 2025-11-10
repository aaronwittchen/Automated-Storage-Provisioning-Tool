#!/bin/bash
#
# sync_vm.sh — Sync project files between local machine and remote VM.
#
# Supports two-way sync:
#   ./sync_vm.sh push  → sync local → remote
#   ./sync_vm.sh pull  → sync remote → local
#
# Optionally override default paths:
#   ./sync_vm.sh push /path/to/local user@vm:/remote/path
#
# Requirements:
#   - rsync installed locally and on the VM
#   - SSH key-based authentication configured
#

# === Default Configuration ===
DEFAULT_LOCAL_DIR="$(pwd)"
DEFAULT_REMOTE_TARGET="rocky-vm@192.168.68.105:/home/rocky-vm/storage-provisioning/"
CONFIG_FILE="$HOME/.sync_vm.conf"
LOG_FILE="./sync.log"

# === Files & directories to exclude ===
EXCLUDES=(
  ".git"
  "logs"
  "*.tmp"
  "*.bak"
  "__pycache__"
)

# === Colors for readability ===
GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m' # no color

# === Functions ===
usage() {
  echo -e "${YELLOW}Usage:${NC}"
  echo "  $0 push [local_dir] [user@host:/remote/path]"
  echo "  $0 pull [local_dir] [user@host:/remote/path]"
  echo "  $0 --setup-config  # Generate sample ~/.sync_vm.conf"
  echo
  echo "Examples:"
  echo "  $0 push ./project rocky-vm@192.168.68.105:/home/rocky-vm/storage-provisioning/"
  echo "  $0 pull ./project rocky-vm@192.168.68.105:/home/rocky-vm/storage-provisioning/"
  echo
  echo "Config: Edit ~/.sync_vm.conf for personal defaults."
  echo
  exit 1
}

setup_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    echo -e "${YELLOW}Config already exists at $CONFIG_FILE. Backing up...${NC}"
    cp "$CONFIG_FILE" "${CONFIG_FILE}.backup"
  fi
  cat > "$CONFIG_FILE" << EOF
# ~/.sync_vm.conf — Personal defaults for sync_vm.sh
# Edit these to match your setup; args will override.

# Default local project directory
LOCAL_DIR="$(pwd)"

# Default remote VM target (user@host:/path)
REMOTE_TARGET="rocky-vm@192.168.68.105:/home/rocky-vm/storage-provisioning/"
EOF
  echo -e "${GREEN}Sample config created at $CONFIG_FILE${NC}"
  echo "Edit it with your paths, then run: $0 push"
  exit 0
}

print_header() {
  echo -e "${BLUE}-------------------------------------------${NC}"
  echo -e "${BLUE} Automated Storage Provisioning Tool Sync${NC}"
  echo -e "${BLUE}-------------------------------------------${NC}"
  echo -e "Mode  : ${YELLOW}$MODE${NC}"
  echo -e "Local : ${GREEN}$LOCAL_DIR${NC}"
  echo -e "Remote: ${GREEN}$REMOTE_TARGET${NC}"
  echo -e "Config: ${YELLOW}$CONFIG_FILE${NC}"
  echo
}

log_msg() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

# === Pre-flight checks ===
if ! command -v rsync >/dev/null 2>&1; then
  echo -e "${RED}rsync not found! Please install rsync first.${NC}"
  exit 1
fi

# === Parse Arguments ===
if [[ "$1" == "--setup-config" ]]; then
  setup_config
fi

MODE="$1"
LOCAL_DIR="${2:-}"
REMOTE_TARGET="${3:-}"

if [[ -z "$MODE" ]]; then
  usage
fi

if [[ "$MODE" != "push" && "$MODE" != "pull" ]]; then
  echo -e "${RED}Invalid mode: '$MODE' (use push or pull).${NC}"
  usage
fi

# === Load Config if Exists ===
if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
  echo -e "${YELLOW}Loaded config from $CONFIG_FILE${NC}"
fi

# === Set Paths (config/args/defaults fallback) ===
LOCAL_DIR="${LOCAL_DIR:-$DEFAULT_LOCAL_DIR}"
REMOTE_TARGET="${REMOTE_TARGET:-$DEFAULT_REMOTE_TARGET}"

if [[ ! -d "$LOCAL_DIR" ]]; then
  echo -e "${RED}Local directory not found: $LOCAL_DIR${NC}"
  exit 1
fi

# === Prepare exclude arguments ===
EXCLUDE_ARGS=()
for item in "${EXCLUDES[@]}"; do
  EXCLUDE_ARGS+=(--exclude "$item")
done

# === Print summary ===
print_header

# === Confirm before proceeding ===
read -p "Proceed with sync? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" ]]; then
  echo "Aborted."
  exit 0
fi

# === Perform Sync ===
if [[ "$MODE" == "push" ]]; then
  echo -e "${YELLOW}Pushing local → remote...${NC}"
  rsync -avz --delete "${EXCLUDE_ARGS[@]}" "$LOCAL_DIR/" "$REMOTE_TARGET" | tee -a "$LOG_FILE"

elif [[ "$MODE" == "pull" ]]; then
  echo -e "${YELLOW}Pulling remote → local...${NC}"
  rsync -avz --delete "${EXCLUDE_ARGS[@]}" "$REMOTE_TARGET" "$LOCAL_DIR/" | tee -a "$LOG_FILE"
fi

# === Final status ===
if [[ $? -eq 0 ]]; then
  echo -e "${GREEN}Sync completed successfully.${NC}"
  log_msg "Sync ($MODE) completed successfully."
else
  echo -e "${RED}Sync encountered errors.${NC}"
  log_msg "Sync ($MODE) encountered errors."
fi