# svcify

Turn any Node.js app or shell script into a systemd service.

## Install

### Quick Install

Run the installer directly with a single command:

```bash
curl -sSL https://raw.githubusercontent.com/noodlescripter/svcify/main/svcify.sh | sudo bash
```

### Manual Installation

If you prefer to review the script before running:

```bash
# Download the script
curl -sSL -o svcify.sh https://raw.githubusercontent.com/noodlescripter/svcify/main/svcify.sh

# Review it
cat svcify.sh

# Make it executable and install
chmod +x svcify.sh
sudo ./svcify.sh setup
```

## Supported App Types

| Type | Extensions | Executor |
|------|------------|----------|
| Node.js | `.js` | `node` |
| Shell script | `.sh` | `bash` |

## Usage

### Node.js App

```bash
# Create a service from current directory
cd /path/to/your/node-app
sudo svcify install myapp

# Or specify the path
sudo svcify install myapp --app-dir /path/to/your/node-app

# Specify a custom entry point
sudo svcify install myapp --entry server.js

# Use a specific node binary
sudo svcify install myapp --node /usr/local/bin/node
```

### Shell Script

```bash
# Create a service from a shell script
sudo svcify install myworker --app-dir /path/to/scripts --entry worker.sh

# Or if the directory has run.sh, start.sh, app.sh, or main.sh
cd /path/to/scripts
sudo svcify install myworker
```

### Preview Before Installing

```bash
# See the generated service file without installing
sudo svcify install myapp --dry-run
```

## Commands

```bash
sudo svcify install <name>      # Create and start service
sudo svcify uninstall <name>    # Remove service
sudo svcify start <name>        # Start service
sudo svcify stop <name>         # Stop service
sudo svcify restart <name>      # Restart service
sudo svcify status <name>       # Show status
sudo svcify logs <name>         # Follow logs
sudo svcify list                # List all svcify services
svcify monitor                  # Live dashboard (like pm2 monit)
```

## Monitor Dashboard

Real-time monitoring of all svcify services, similar to `pm2 monit`.

```bash
svcify monitor                  # Start the dashboard
svcify monitor --interval 5     # Refresh every 5 seconds (default: 2)
```

The dashboard displays:
- **Service name** and **status** (color-coded: green=active, yellow=inactive, red=failed)
- **Memory usage** per service
- **CPU %** of the running process
- **PID** of the main process
- **Restart count** since service creation
- **Uptime** since last state change
- **Summary** with totals for active/inactive/failed and total memory

Press `Ctrl+C` to exit.

## Options

| Option | Description |
|--------|-------------|
| `--app-dir <path>` | Path to application (default: current directory) |
| `--entry <file>` | Entry file (default: auto-detect) |
| `--node <path>` | Path to node binary (Node.js apps only) |
| `--dry-run` | Preview service file without installing |

## How It Works

1. **Detects app type** from the entry point file extension (`.js` or `.sh`)
2. **Creates a systemd service file** in `/etc/systemd/system/`
3. **Runs as your user** (not root)
4. **Loads `.env` file** if present in the app directory
5. **Sets `NODE_ENV=production`** for Node.js apps
6. **Auto-restarts on failure** with a 5-second delay

### Auto-Detection

If no `--entry` is specified, svcify looks for files in this order:

**Node.js apps:**
1. `main` field in `package.json`
2. `start` script in `package.json` (if it uses `node`)
3. Common entry points: `index.js`, `main.js`, `app.js`, `server.js`, `src/index.js`, `dist/index.js`

**Shell scripts:**
1. `run.sh`, `start.sh`, `app.sh`, `main.sh`

## Uninstall svcify

```bash
sudo rm /usr/local/bin/svcify
sudo rm -rf /usr/local/share/svcify
```

## Web UI

svcify also ships a browser UI for managing services — dashboard, create/install, start/stop/restart, uninstall, and live logs.

### Start the web UI

```bash
sudo svcify web
```

Then open <http://127.0.0.1:8088>. The server binds to localhost only and must run as root (so it can call `svcify install/uninstall/start/stop/restart`). Press `Ctrl+C` to stop.

Options via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `SVCIFY_WEB_PORT` | `8088` | Port to listen on |
| `SVCIFY_WEB_HOST` | `127.0.0.1` | Bind address (change with care — no auth) |
| `SVCIFY_BIN` | `svcify` (on `PATH`) | Path to the `svcify` binary the server shells out to for every state change |

```bash
sudo SVCIFY_WEB_PORT=9000 svcify web
```

### Requirements

- The web UI needs the `web/` directory. After cloning the repo, run `sudo ./svcify.sh setup` from the repo root — this copies the script to `/usr/local/bin/svcify` and the web files to `/usr/local/share/svcify/web`.
- Node.js must be installed (the `web` command runs `npm install` on first start if `node_modules` is missing).
- The `curl | bash` quick-install path installs **only** the CLI script, not the web UI. Use the manual setup from a repo clone to get the web UI.

### Install the web UI

From a repo clone (gets both the CLI and the web UI):

```bash
cd /path/to/svcify
echo y | sudo ./svcify.sh setup   # `setup` is interactive; pipe `y` to accept the prompt
sudo svcify web                    # starts the UI on 127.0.0.1:8088
```

`setup` copies the script to `/usr/local/bin/svcify` and the `web/` directory to `/usr/local/share/svcify/web`. After `setup`, the `web` command resolves its files from the share path, so the repo is no longer required at runtime.

To uninstall:

```bash
sudo rm /usr/local/bin/svcify
sudo rm -rf /usr/local/share/svcify
```

### Run the web UI in development (no root, no systemd)

For UI work, you can run the Node server directly against a fake `svcify` binary so mutations succeed without touching real services. The server only needs root for the actual `svcify install/uninstall/start/stop/restart` calls; reads and the WebSocket work fine unprivileged.

```bash
# 1. Create a fake svcify that just echoes commands
cat > /tmp/fake-svcify <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  install)    echo "installed ${2}";;
  uninstall)  echo "uninstalled ${2}";;
  start|stop|restart) echo "${1} ${2}";;
  *)          echo "fake $*";;
esac
EOF
chmod +x /tmp/fake-svcify

# 2. Start the server pointed at the fake binary
cd web
npm install                       # only needed once
SVCIFY_BIN=/tmp/fake-svcify \
  SVCIFY_WEB_PORT=8089 \
  SVCIFY_WEB_HOST=127.0.0.1 \
  node server.js

# 3. Probe it
curl http://127.0.0.1:8089/api/services                  # []
curl -X POST -H 'Content-Type: application/json' \
  -d '{"name":"demoapp","appDir":"/tmp","entry":"server.js"}' \
  http://127.0.0.1:8089/api/services                      # {"ok":true,...}
```

The dashboard is at <http://127.0.0.1:8089>. Polling: dashboard every 3s, detail every 4s, with a WebSocket for live logs. Press `Ctrl+C` to stop the server.

### API

The server also exposes a small JSON API at the same address:

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/` | Serves the dashboard UI (`web/public/index.html`) |
| `GET` | `/api/services` | List all svcify-marked services with live props |
| `GET` | `/api/services/:name` | Service detail (status, props, raw unit file) |
| `POST` | `/api/services` | Install — body: `name`, `appDir`, `entry?`, `node?`, `java?` |
| `DELETE` | `/api/services/:name` | Uninstall |
| `POST` | `/api/services/:name/{start\|stop\|restart}` | Control (other actions return `400`) |
| `GET` | `/api/services/:name/logs/history?n=200` | Last N log lines via `journalctl --no-pager -n N -o cat` |
| `WS` | `/api/services/:name/logs/ws` | Live log stream — JSON frames `{"type":"log","line":"…"}` |

State-changing endpoints (`POST`, `DELETE`) shell out to the `SVCIFY_BIN` binary. On failure they return HTTP 400 with `{"error":"<message>"}`; success returns `{"ok":true,"output":"<stdout+stderr>"}`. Read endpoints always return 200 with an empty list/`-` props for unknown services.

## Requirements

- Linux with systemd
- Node.js (for Node.js apps)
- Bash (for shell scripts)
