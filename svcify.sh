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
  echo "  monitor     Live dashboard for all svcify services"
  echo ""
  echo "Install options:"
  echo "  --app-dir <path>      Path to application (default: current directory)"
  echo "  --entry <file>        Entry file (default: auto-detect)"
  echo "  --node <path>         Path to node binary (Node.js apps only)"
  echo "  --dry-run             Generate service file without installing"
  echo ""
  echo "Supported app types:"
  echo "  Node.js (.js)         Runs with node"
  echo "  Shell scripts (.sh)   Runs with bash"
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

# Handle monitor command (live dashboard)
if [ "$COMMAND" = "monitor" ]; then
  require_systemctl

  # Colors
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BLUE='\033[0;34m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  DIM='\033[2m'
  NC='\033[0m' # No Color

  # Parse monitor options
  MONITOR_INTERVAL=2
  while [ $# -gt 0 ]; do
    case "$1" in
      --interval|-i)
        MONITOR_INTERVAL="$2"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done

  # Convert bytes to human readable
  format_bytes() {
    local bytes=$1
    if [ "$bytes" = "[not set]" ] || [ -z "$bytes" ] || [ "$bytes" = "0" ]; then
      echo "0B"
      return
    fi
    if [ "$bytes" -ge 1073741824 ]; then
      echo "$(awk "BEGIN {printf \"%.1f\", $bytes/1073741824}")GB"
    elif [ "$bytes" -ge 1048576 ]; then
      echo "$(awk "BEGIN {printf \"%.1f\", $bytes/1048576}")MB"
    elif [ "$bytes" -ge 1024 ]; then
      echo "$(awk "BEGIN {printf \"%.1f\", $bytes/1024}")KB"
    else
      echo "${bytes}B"
    fi
  }

  # Format uptime from timestamp
  format_uptime() {
    local timestamp="$1"
    if [ -z "$timestamp" ] || [ "$timestamp" = "n/a" ]; then
      echo "-"
      return
    fi
    local start_sec
    start_sec=$(date -d "$timestamp" +%s 2>/dev/null) || { echo "-"; return; }
    local now_sec
    now_sec=$(date +%s)
    local diff=$((now_sec - start_sec))

    if [ "$diff" -lt 0 ]; then
      echo "-"
    elif [ "$diff" -lt 60 ]; then
      echo "${diff}s"
    elif [ "$diff" -lt 3600 ]; then
      echo "$((diff / 60))m $((diff % 60))s"
    elif [ "$diff" -lt 86400 ]; then
      echo "$((diff / 3600))h $((diff % 3600 / 60))m"
    else
      echo "$((diff / 86400))d $((diff % 86400 / 3600))h"
    fi
  }

  # Get status color
  status_color() {
    case "$1" in
      active)   echo -e "${GREEN}" ;;
      inactive) echo -e "${YELLOW}" ;;
      failed)   echo -e "${RED}" ;;
      *)        echo -e "${DIM}" ;;
    esac
  }

  # Render the dashboard
  render_dashboard() {
    clear
    local now
    now=$(date '+%Y-%m-%d %H:%M:%S')

    echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║${NC}                        ${BOLD}SVCIFY MONITOR${NC}                                     ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}╠════════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}${CYAN}║${NC} ${DIM}Updated: ${now}${NC}                            ${DIM}Refresh: ${MONITOR_INTERVAL}s | Ctrl+C to exit${NC} ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Table header
    printf "${BOLD}%-18s %-10s %10s %8s %8s %10s %12s${NC}\n" \
      "SERVICE" "STATUS" "MEMORY" "CPU%" "PID" "RESTARTS" "UPTIME"
    echo -e "${DIM}──────────────────────────────────────────────────────────────────────────────${NC}"

    local found=false
    local total_mem=0
    local active_count=0
    local failed_count=0
    local inactive_count=0

    for file in /etc/systemd/system/*.service; do
      [ -f "$file" ] || continue
      if grep -q "Description=svcify:" "$file" 2>/dev/null; then
        found=true
        local name
        name=$(basename "$file" .service)

        # Get service properties in one call
        local props
        props=$(systemctl show "$name" -p ActiveState,MainPID,MemoryCurrent,CPUUsageNSec,NRestarts,StateChangeTimestamp 2>/dev/null)

        local status pid mem_bytes cpu_ns restarts timestamp
        status=$(echo "$props" | grep "^ActiveState=" | cut -d= -f2)
        pid=$(echo "$props" | grep "^MainPID=" | cut -d= -f2)
        mem_bytes=$(echo "$props" | grep "^MemoryCurrent=" | cut -d= -f2)
        cpu_ns=$(echo "$props" | grep "^CPUUsageNSec=" | cut -d= -f2)
        restarts=$(echo "$props" | grep "^NRestarts=" | cut -d= -f2)
        timestamp=$(echo "$props" | grep "^StateChangeTimestamp=" | cut -d= -f2-)

        # Format values
        local mem_human uptime_human cpu_pct color
        mem_human=$(format_bytes "$mem_bytes")
        uptime_human=$(format_uptime "$timestamp")
        color=$(status_color "$status")

        # CPU percentage (rough estimate based on recent usage)
        if [ -n "$cpu_ns" ] && [ "$cpu_ns" != "0" ] && [ "$cpu_ns" != "[not set]" ]; then
          # Get CPU % from ps if process is running
          if [ "$pid" != "0" ] && [ -n "$pid" ]; then
            cpu_pct=$(ps -p "$pid" -o %cpu= 2>/dev/null | tr -d ' ') || cpu_pct="0.0"
          else
            cpu_pct="0.0"
          fi
        else
          cpu_pct="0.0"
        fi

        # Display PID or dash if not running
        [ "$pid" = "0" ] && pid="-"

        # Count stats
        case "$status" in
          active)   ((active_count++)) ;;
          inactive) ((inactive_count++)) ;;
          failed)   ((failed_count++)) ;;
        esac

        # Add to total memory
        if [ "$mem_bytes" != "[not set]" ] && [ -n "$mem_bytes" ]; then
          total_mem=$((total_mem + mem_bytes))
        fi

        printf "${color}%-18s %-10s${NC} %10s %8s %8s %10s %12s\n" \
          "$name" "$status" "$mem_human" "$cpu_pct" "$pid" "$restarts" "$uptime_human"
      fi
    done

    if [ "$found" = false ]; then
      echo ""
      echo -e "  ${DIM}No svcify services found.${NC}"
      echo -e "  ${DIM}Create one with: sudo svcify install <name>${NC}"
    else
      echo -e "${DIM}──────────────────────────────────────────────────────────────────────────────${NC}"
      local total_mem_human
      total_mem_human=$(format_bytes "$total_mem")
      echo ""
      echo -e "${BOLD}Summary:${NC} ${GREEN}${active_count} active${NC} | ${YELLOW}${inactive_count} inactive${NC} | ${RED}${failed_count} failed${NC} | Total memory: ${BOLD}${total_mem_human}${NC}"
    fi
  }

  # Trap to restore terminal on exit
  cleanup() {
    tput cnorm 2>/dev/null  # Show cursor
    echo ""
    exit 0
  }
  trap cleanup EXIT INT TERM

  # Hide cursor
  tput civis 2>/dev/null

  # Main loop
  while true; do
    render_dashboard
    sleep "$MONITOR_INTERVAL"
  done
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
APP_TYPE=""  # "node" or "shell", detected from entry point

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

# Auto-detect entry point if not provided
if [ -z "$ENTRY_POINT" ]; then
  if [ -f "${APP_DIR}/package.json" ]; then
    ENTRY_POINT=$(grep -oP '"main"\s*:\s*"\K[^"]+' "${APP_DIR}/package.json" 2>/dev/null || true)
    if [ -z "$ENTRY_POINT" ]; then
      ENTRY_POINT=$(grep -oP '"start"\s*:\s*"node\s+\K[^"]+' "${APP_DIR}/package.json" 2>/dev/null || true)
    fi
  fi
  if [ -z "$ENTRY_POINT" ]; then
    # Try Node.js files first
    for candidate in index.js main.js app.js server.js src/index.js dist/index.js; do
      if [ -f "${APP_DIR}/${candidate}" ]; then
        ENTRY_POINT="$candidate"
        break
      fi
    done
  fi
  if [ -z "$ENTRY_POINT" ]; then
    # Try shell scripts
    for candidate in run.sh start.sh app.sh main.sh; do
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

# Detect app type from entry point extension
case "$ENTRY_POINT" in
  *.sh)
    APP_TYPE="shell"
    ;;
  *)
    APP_TYPE="node"
    ;;
esac

# Validate Node.js is available for Node.js apps
if [ "$APP_TYPE" = "node" ] && [ ! -x "$NODE_EXEC" ]; then
  echo "Error: Node.js not found at '$NODE_EXEC'."
  exit 1
fi

ENV_FILE="${APP_DIR}/.env"
RUN_USER="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"

echo "Installing service '${SERVICE_NAME}'..."
echo "  App directory: ${APP_DIR}"
echo "  Entry point:   ${ENTRY_POINT}"
echo "  App type:      ${APP_TYPE}"
if [ "$APP_TYPE" = "node" ]; then
  echo "  Node binary:   ${NODE_EXEC}"
fi
echo "  Run as user:   ${RUN_USER}"

# Generate ExecStart based on app type
if [ "$APP_TYPE" = "shell" ]; then
  EXEC_START="/usr/bin/env bash ${ENTRY_FILE}"
else
  EXEC_START="${NODE_EXEC} ${ENTRY_FILE}"
fi

SERVICE_CONTENT="[Unit]
Description=svcify: ${SERVICE_NAME}
After=network.target

[Service]
Type=simple
User=${RUN_USER}
WorkingDirectory=${APP_DIR}"

# Add NODE_ENV for Node.js apps only
if [ "$APP_TYPE" = "node" ]; then
  SERVICE_CONTENT="${SERVICE_CONTENT}
Environment=NODE_ENV=production"
fi

SERVICE_CONTENT="${SERVICE_CONTENT}
EnvironmentFile=-${ENV_FILE}
ExecStart=${EXEC_START}
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
