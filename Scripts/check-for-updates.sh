#!/bin/zsh
set -euo pipefail

source "${0:A:h}/lib/common.sh"
load_ci_config

WATCH_LOG="$LOG_DIR/watcher.log"
exec > >(tee -a "$WATCH_LOG") 2>&1

require_command git

if ! git -C "$REPO_PATH" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  print "[$(timestamp)] Gitリポジトリ未設定のため待機: $REPO_PATH"
  exit 0
fi
if ! git -C "$REPO_PATH" remote get-url "$REMOTE_NAME" >/dev/null 2>&1; then
  print "[$(timestamp)] remote '$REMOTE_NAME' 未設定のため待機"
  exit 0
fi

if ! git -C "$REPO_PATH" fetch --quiet --prune "$REMOTE_NAME" "$BRANCH"; then
  print "[$(timestamp)] GitHubの更新確認に失敗しました。Git認証とネットワークを確認してください。"
  exit 1
fi

REMOTE_HEAD="$(git -C "$REPO_PATH" rev-parse "$REMOTE_NAME/$BRANCH")"
LAST_ATTEMPTED=""
if [[ -r "$RUNTIME_DIR/last-attempted-commit" ]]; then
  LAST_ATTEMPTED="$(<"$RUNTIME_DIR/last-attempted-commit")"
fi

if [[ "$REMOTE_HEAD" == "$LAST_ATTEMPTED" ]]; then
  exit 0
fi

section "新しいコミットを検知: $REMOTE_HEAD"
print -r -- "$REMOTE_HEAD" > "$RUNTIME_DIR/last-attempted-commit"
"$CI_SCRIPT_DIR/pipeline.sh"

