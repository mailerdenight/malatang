#!/bin/zsh
set -euo pipefail

PLIST_PATH="$HOME/Library/LaunchAgents/com.malatanglog.autobuild.plist"
SERVICE="gui/$(id -u)/com.malatanglog.autobuild"

if launchctl print "$SERVICE" >/dev/null 2>&1; then
  launchctl bootout "$SERVICE"
fi
if [[ -f "$PLIST_PATH" ]]; then
  rm -f "$PLIST_PATH"
fi

print "LaunchAgentを解除しました。"
print "APIキーと設定は ~/Library/Application Support/MalatangLogCI に残しています。"

