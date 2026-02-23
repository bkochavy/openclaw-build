#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
BIN_DIR="$OPENCLAW_HOME/bin"
MONITOR_SRC="$ROOT_DIR/scripts/ralph-monitor.sh"
MONITOR_DEST="$BIN_DIR/ralph-monitor.sh"
CONFIG_DEST="$OPENCLAW_HOME/ralph-monitor.json"
CONFIG_EXAMPLE="$ROOT_DIR/ralph-monitor.example.json"

mkdir -p "$BIN_DIR"
cp "$MONITOR_SRC" "$MONITOR_DEST"
chmod +x "$MONITOR_DEST"

if [ ! -f "$CONFIG_DEST" ]; then
  cp "$CONFIG_EXAMPLE" "$CONFIG_DEST"
fi

if [ "$(uname -s)" = "Darwin" ]; then
  LAUNCH_DIR="$HOME/Library/LaunchAgents"
  PLIST_PATH="$LAUNCH_DIR/ai.openclaw.ralph-monitor.plist"

  mkdir -p "$LAUNCH_DIR"

  cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>ai.openclaw.ralph-monitor</string>

    <key>ProgramArguments</key>
    <array>
      <string>/bin/bash</string>
      <string>$MONITOR_DEST</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>StartInterval</key>
    <integer>600</integer>

    <key>StandardOutPath</key>
    <string>$OPENCLAW_HOME/ralph-monitor.log</string>

    <key>StandardErrorPath</key>
    <string>$OPENCLAW_HOME/ralph-monitor.log</string>
  </dict>
</plist>
PLIST

  launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
  launchctl load "$PLIST_PATH"
elif [ "$(uname -s)" = "Linux" ] && command -v systemctl >/dev/null 2>&1; then
  SYSTEMD_DIR="$HOME/.config/systemd/user"
  SERVICE_PATH="$SYSTEMD_DIR/ai.openclaw.ralph-monitor.service"
  TIMER_PATH="$SYSTEMD_DIR/ai.openclaw.ralph-monitor.timer"

  mkdir -p "$SYSTEMD_DIR"

  cat > "$SERVICE_PATH" <<SERVICE
[Unit]
Description=OpenClaw Ralph tmux monitor

[Service]
Type=oneshot
ExecStart=/bin/bash $MONITOR_DEST
SERVICE

  cat > "$TIMER_PATH" <<TIMER
[Unit]
Description=Run OpenClaw Ralph monitor every 10 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=10min
Unit=ai.openclaw.ralph-monitor.service
Persistent=true

[Install]
WantedBy=timers.target
TIMER

  systemctl --user daemon-reload
  systemctl --user enable --now ai.openclaw.ralph-monitor.timer
else
  echo "Warning: automatic scheduler setup only supports macOS launchd and Linux systemd-user." >&2
fi

echo "✅ Ralph monitor active. Watches tmux sessions at ~/.tmux/sock"
