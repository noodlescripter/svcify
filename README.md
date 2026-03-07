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
```

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
```

## Requirements

- Linux with systemd
- Node.js (for Node.js apps)
- Bash (for shell scripts)
