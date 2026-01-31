# svcify

Turn any Node.js app into a systemd service.

## Install

### Quick Install

Run the installer directly with a single command:

```bash
curl -sSL https://raw.githubusercontent.com/your-username/svcify/main/svcify.sh | sudo bash
```

### Manual Installation

If you prefer to review the script before running:

```bash
# Download the script
curl -sSL -o svcify.sh https://raw.githubusercontent.com/your-username/svcify/main/svcify.sh

# Review it
cat svcify.sh

# Make it executable and install
chmod +x svcify.sh
sudo ./svcify.sh setup
```

## Usage

```bash
# Create a service from current directory
cd /path/to/your/node-app
sudo svcify install myapp

# Or specify the path
sudo svcify install myapp --app-dir /path/to/your/node-app

# Specify a custom entry point
sudo svcify install myapp --entry server.js
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
| `--app-dir <path>` | Path to Node.js app (default: current directory) |
| `--entry <file>` | Entry file (default: auto-detect) |
| `--node <path>` | Path to node binary (default: auto-detect) |
| `--dry-run` | Preview service file without installing |

## How it works

- Creates a systemd service file in `/etc/systemd/system/`
- Runs as your user (not root)
- Loads `.env` file if present
- Sets `NODE_ENV=production`
- Auto-restarts on failure

## Uninstall svcify

```bash
sudo rm /usr/local/bin/svcify
```

## Requirements

- Linux with systemd
- Node.js
