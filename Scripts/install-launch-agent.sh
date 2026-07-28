#!/bin/zsh
set -euo pipefail

REPO_ROOT="${0:A:h:h}"
SUPPORT_DIR="$HOME/Library/Application Support/MalatangLogCI"
CONFIG_PATH="$SUPPORT_DIR/config.env"
PRIVATE_KEYS_DIR="$SUPPORT_DIR/private_keys"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$LAUNCH_AGENTS_DIR/com.malatanglog.autobuild.plist"
LOG_DIR="$REPO_ROOT/logs"
INTERVAL="${POLL_INTERVAL_SECONDS:-300}"
DOMAIN="gui/$(id -u)"
SERVICE="$DOMAIN/com.malatanglog.autobuild"

mkdir -p "$SUPPORT_DIR" "$PRIVATE_KEYS_DIR" "$LAUNCH_AGENTS_DIR" "$LOG_DIR"
chmod 700 "$SUPPORT_DIR" "$PRIVATE_KEYS_DIR"

if [[ ! -f "$CONFIG_PATH" ]]; then
  sed \
    -e "s|__REPO_ROOT__|$REPO_ROOT|g" \
    -e "s|__SUPPORT_DIR__|$SUPPORT_DIR|g" \
    "$REPO_ROOT/Scripts/config.example.env" > "$CONFIG_PATH"
  chmod 600 "$CONFIG_PATH"
  print "設定ファイルを作成しました: $CONFIG_PATH"
  print "APIキー情報を編集し、.p8を private_keys に配置してから再実行してください。"
  exit 2
fi

if grep -q 'REPLACE_WITH_' "$CONFIG_PATH"; then
  print "ERROR: 設定ファイルのREPLACE_WITH_*を実値に置き換えてください: $CONFIG_PATH"
  exit 2
fi

source "$CONFIG_PATH"
if [[ "${ASC_KEY_PATH:-}" == "~/"* ]]; then
  ASC_KEY_PATH="$HOME/${ASC_KEY_PATH#\~/}"
fi
if [[ -z "${ASC_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" || -z "${ASC_KEY_PATH:-}" ]]; then
  print "ERROR: App Store Connect APIキー設定が不足しています: $CONFIG_PATH"
  exit 2
fi
if [[ ! -r "$ASC_KEY_PATH" ]]; then
  print "ERROR: App Store Connect APIキーを読み込めません: $ASC_KEY_PATH"
  exit 2
fi
chmod 600 "$ASC_KEY_PATH"

if launchctl print "$SERVICE" >/dev/null 2>&1; then
  launchctl bootout "$SERVICE"
fi
rm -f "$PLIST_PATH"
plutil -create xml1 "$PLIST_PATH"
plutil -insert Label -string "com.malatanglog.autobuild" "$PLIST_PATH"
plutil -insert ProgramArguments -xml \
  "<array><string>/bin/zsh</string><string>$REPO_ROOT/Scripts/check-for-updates.sh</string></array>" \
  "$PLIST_PATH"
plutil -insert WorkingDirectory -string "$REPO_ROOT" "$PLIST_PATH"
plutil -insert RunAtLoad -bool true "$PLIST_PATH"
plutil -insert StartInterval -integer "$INTERVAL" "$PLIST_PATH"
plutil -insert ProcessType -string "Background" "$PLIST_PATH"
plutil -insert StandardOutPath -string "$LOG_DIR/launchagent.log" "$PLIST_PATH"
plutil -insert StandardErrorPath -string "$LOG_DIR/launchagent.log" "$PLIST_PATH"
plutil -insert EnvironmentVariables -xml \
  "<dict><key>MALATANG_CI_CONFIG</key><string>$CONFIG_PATH</string></dict>" \
  "$PLIST_PATH"

plutil -lint "$PLIST_PATH"
launchctl bootstrap "$DOMAIN" "$PLIST_PATH"
launchctl enable "$SERVICE"
launchctl kickstart -k "$SERVICE"

print "LaunchAgentを有効化しました。"
print "状態確認: launchctl print $SERVICE"
print "ログ:     $LOG_DIR/launchagent.log"
