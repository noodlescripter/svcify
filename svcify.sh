#!/usr/bin/env bash
set -euo pipefail

# svcify - Turn any application into a systemd service
# https://github.com/noodlescripter/svcify

SCRIPT_NAME="svcify"

print_usage() {
  echo "Usage: sudo $SCRIPT_NAME <command> [service_name] [options]"
  echo ""
  echo "Commands:"
  echo "  setup       Install svcify to /usr/local/bin"
  echo "  install     Install and start the service"
  echo "  uninstall   Stop and remove the service"
  echo "  start       Start the service"
  echo "  stop        Stop the service"
  echo "  restart     Restart the service"
  echo "  status      Show service status"
  echo "  logs        Show service logs (follow mode)"
  echo "  list        List all services created by svcify"
  echo ""
  echo "Install options:"
  echo "  --app-dir <path>      Path to Node.js app (default: current directory)"
  echo "  --entry <file>        Entry file (default: auto-detect)"
  echo "  --node <path>         Path to node binary (default: auto-detect)"
  echo "  --dry-run             Generate service file without installing"
  echo ""
  echo "Examples:"
  echo "  sudo $SCRIPT_NAME list"
  echo "  sudo $SCRIPT_NAME install myapi"
  echo "  sudo $SCRIPT_NAME install myapi --app-dir /home/user/my-api --entry server.js"
  echo "  sudo $SCRIPT_NAME stop myapi"
  echo "  sudo $SCRIPT_NAME uninstall myapi"
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This command requires root privileges. Re-run with sudo."
    exit 1
  fi
}

require_systemctl() {
  if ! command -v systemctl &> /dev/null; then
    echo "Error: systemctl not found. This script requires systemd."
    exit 1
  fi
}

get_service_file() {
  echo "/etc/systemd/system/${1}.service"
}

# Auto-install when piped (curl | bash)
if [ -z "${1:-}" ] && [ ! -t 0 ]; then
  INSTALL_DIR="/usr/local/bin"
  SCRIPT_PATH="${INSTALL_DIR}/svcify"
  REPO_URL="https://raw.githubusercontent.com/noodlescripter/svcify/main/svcify.sh"

  echo ""
  echo "================================"
  echo "  svcify installer"
  echo "================================"
  echo ""
  echo "This will install svcify to ${INSTALL_DIR}"
  echo ""
  echo "Review the source code at:"
  echo "  https://github.com/noodlescripter/svcify"
  echo ""

  read -r -p "Proceed with installation? [y/N]: " confirm < /dev/tty
  case "$confirm" in
    [yY][eE][sS]|[yY])
      ;;
    *)
      echo "Installation cancelled."
      exit 0
      ;;
  esac

  if [ "$(id -u)" -ne 0 ]; then
    echo "Error: Installation requires root. Run with: curl ... | sudo bash"
    exit 1
  fi

  echo ""
  echo "Installing..."

  # Download the script to install path
  if command -v curl &> /dev/null; then
    curl -fsSL "$REPO_URL" -o "$SCRIPT_PATH"
  elif command -v wget &> /dev/null; then
    wget -qO "$SCRIPT_PATH" "$REPO_URL"
  fi

  chmod +x "$SCRIPT_PATH"
  echo ""
  echo "Done! Run 'svcify --help' to get started."
  exit 0
fi

# Parse command
if [ -z "${1:-}" ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  print_usage
  exit 0
fi

COMMAND="$1"
shift

# Handle list command (doesn't require service_name)
if [ "$COMMAND" = "list" ]; then
  require_systemctl
  echo "svcify services:"
  echo ""
  found=false
  for file in /etc/systemd/system/*.service; do
    [ -f "$file" ] || continue
    if grep -q "Description=svcify:" "$file" 2>/dev/null; then
      found=true
      name=$(basename "$file" .service)
      status=$(systemctl is-active "$name" 2>/dev/null || echo "unknown")
      printf "  %-20s [%s]\n" "$name" "$status"
    fi
  done
  if [ "$found" = false ]; then
    echo "  No services found."
  fi
  exit 0
fi

# Handle setup command (install svcify itself)
if [ "$COMMAND" = "setup" ]; then
  require_root
  INSTALL_DIR="/usr/local/bin"
  SCRIPT_PATH="${INSTALL_DIR}/${SCRIPT_NAME}"

  echo ""
  echo "================================"
  echo "  svcify installer"
  echo "================================"
  echo ""
  echo "This will install svcify to ${INSTALL_DIR}"
  echo ""
  echo "Review the source code at:"
  echo "  https://github.com/noodlescripter/svcify"
  echo ""

  read -r -p "Proceed with installation? [y/N]: " confirm
  case "$confirm" in
    [yY][eE][sS]|[yY])
      ;;
    *)
      echo "Installation cancelled."
      exit 0
      ;;
  esac

  echo ""
  echo "Installing..."
  cp "$0" "$SCRIPT_PATH"
  chmod +x "$SCRIPT_PATH"
  echo ""
  echo "Done! Run 'svcify --help' to get started."
  exit 0
fi

if [ -z "${1:-}" ]; then
  echo "Error: service_name is required."
  print_usage
  exit 1
fi

SERVICE_NAME="$1"
shift

SERVICE_FILE="$(get_service_file "$SERVICE_NAME")"

# Handle simple commands first
case "$COMMAND" in
  stop)
    require_root
    require_systemctl
    echo "Stopping ${SERVICE_NAME}..."
    systemctl stop "$SERVICE_NAME"
    echo "Service stopped."
    exit 0
    ;;
  start)
    require_root
    require_systemctl
    echo "Starting ${SERVICE_NAME}..."
    systemctl start "$SERVICE_NAME"
    echo "Service started."
    exit 0
    ;;
  restart)
    require_root
    require_systemctl
    echo "Restarting ${SERVICE_NAME}..."
    systemctl restart "$SERVICE_NAME"
    echo "Service restarted."
    exit 0
    ;;
  status)
    require_systemctl
    systemctl status "$SERVICE_NAME" --no-pager || true
    exit 0
    ;;
  logs)
    journalctl -u "$SERVICE_NAME" -f
    exit 0
    ;;
  uninstall)
    require_root
    require_systemctl
    echo "Uninstalling ${SERVICE_NAME}..."
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    if [ -f "$SERVICE_FILE" ]; then
      rm -f "$SERVICE_FILE"
      echo "Removed ${SERVICE_FILE}"
    fi
    systemctl daemon-reload
    echo "Service '${SERVICE_NAME}' uninstalled."
    exit 0
    ;;
  install)
    # Continue below
    ;;
  *)
    echo "Error: Unknown command '${COMMAND}'"
    print_usage
    exit 1
    ;;
esac

# Parse install options
APP_DIR="$(pwd)"
ENTRY_POINT=""
NODE_EXEC=""
DRY_RUN=false

while [ $# -gt 0 ]; do
  case "$1" in
    --app-dir)
      APP_DIR="$2"
      shift 2
      ;;
    --entry)
      ENTRY_POINT="$2"
      shift 2
      ;;
    --node)
      NODE_EXEC="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    *)
      echo "Error: Unknown option '$1'"
      exit 1
      ;;
  esac
done

# Resolve paths
APP_DIR="$(cd "$APP_DIR" && pwd)"
NODE_EXEC="${NODE_EXEC:-$(command -v node || echo /usr/bin/node)}"

if [ "$DRY_RUN" = false ]; then
  require_root
  require_systemctl
fi

if [ ! -d "$APP_DIR" ]; then
  echo "Error: Directory '$APP_DIR' does not exist."
  exit 1
fi

if [ ! -x "$NODE_EXEC" ]; then
  echo "Error: Node.js not found at '$NODE_EXEC'."
  exit 1
fi

# Auto-detect entry point if not provided
if [ -z "$ENTRY_POINT" ]; then
  if [ -f "${APP_DIR}/package.json" ]; then
    ENTRY_POINT=$(grep -oP '"main"\s*:\s*"\K[^"]+' "${APP_DIR}/package.json" 2>/dev/null || true)
    if [ -z "$ENTRY_POINT" ]; then
      ENTRY_POINT=$(grep -oP '"start"\s*:\s*"node\s+\K[^"]+' "${APP_DIR}/package.json" 2>/dev/null || true)
    fi
  fi
  if [ -z "$ENTRY_POINT" ]; then
    for candidate in index.js main.js app.js server.js src/index.js dist/index.js; do
      if [ -f "${APP_DIR}/${candidate}" ]; then
        ENTRY_POINT="$candidate"
        break
      fi
    done
  fi
  if [ -z "$ENTRY_POINT" ]; then
    echo "Error: Could not detect entry point. Use --entry to specify."
    exit 1
  fi
fi

ENTRY_FILE="${APP_DIR}/${ENTRY_POINT}"
if [ ! -f "$ENTRY_FILE" ]; then
  echo "Error: Entry point '${ENTRY_FILE}' does not exist."
  exit 1
fi

ENV_FILE="${APP_DIR}/.env"
RUN_USER="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"

echo "Installing service '${SERVICE_NAME}'..."
echo "  App directory: ${APP_DIR}"
echo "  Entry point:   ${ENTRY_POINT}"
echo "  Node binary:   ${NODE_EXEC}"
echo "  Run as user:   ${RUN_USER}"

SERVICE_CONTENT="[Unit]
Description=svcify: ${SERVICE_NAME}
After=network.target

[Service]
Type=simple
User=${RUN_USER}
WorkingDirectory=${APP_DIR}
Environment=NODE_ENV=production
EnvironmentFile=-${ENV_FILE}
ExecStart=${NODE_EXEC} ${ENTRY_FILE}
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target"

if [ "$DRY_RUN" = true ]; then
  echo ""
  echo "=== DRY RUN - Service file content ==="
  echo "$SERVICE_CONTENT"
  echo "=== End of service file ==="
  echo ""
  echo "Run without --dry-run to install."
else
  echo "$SERVICE_CONTENT" > "$SERVICE_FILE"
  systemctl daemon-reload
  systemctl enable --now "$SERVICE_NAME"
  echo ""
  echo "Service '${SERVICE_NAME}' installed and started."
  echo ""
  echo "Manage with:"
  echo "  sudo $SCRIPT_NAME status $SERVICE_NAME"
  echo "  sudo $SCRIPT_NAME logs $SERVICE_NAME"
  echo "  sudo $SCRIPT_NAME restart $SERVICE_NAME"
  echo "  sudo $SCRIPT_NAME stop $SERVICE_NAME"
  echo "  sudo $SCRIPT_NAME uninstall $SERVICE_NAME"
fi
