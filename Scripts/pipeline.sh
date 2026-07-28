#!/bin/zsh
set -euo pipefail

source "${0:A:h}/lib/common.sh"
load_ci_config

PIPELINE_LOG="$LOG_DIR/pipeline.log"
exec > >(tee -a "$PIPELINE_LOG") 2>&1

LOCK_DIR="$RUNTIME_DIR/pipeline.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  if [[ -r "$LOCK_DIR/pid" ]] && kill -0 "$(<"$LOCK_DIR/pid")" 2>/dev/null; then
    print "別のパイプラインが実行中のため終了します。"
    exit 0
  fi
  rmdir "$LOCK_DIR" 2>/dev/null || true
  mkdir "$LOCK_DIR"
fi
print -r -- "$$" > "$LOCK_DIR/pid"
trap 'rm -f "$LOCK_DIR/pid"; rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

CURRENT_STAGE="Build"
on_error() {
  local exit_code="$1"
  trap - ERR
  notify_user "麻辣湯ログ CI Failed" "$CURRENT_STAGE で停止しました。ログを確認してください。"
  exit "$exit_code"
}
trap 'on_error $?' ERR

section "自動パイプライン開始"
if git -C "$REPO_PATH" rev-parse HEAD >/dev/null 2>&1; then
  git -C "$REPO_PATH" rev-parse HEAD > "$RUNTIME_DIR/last-attempted-commit"
fi

CURRENT_STAGE="Build"
"$CI_SCRIPT_DIR/build.sh"

CURRENT_STAGE="Archive"
"$CI_SCRIPT_DIR/archive.sh"

if [[ "$AUTO_UPLOAD" == "true" ]]; then
  CURRENT_STAGE="Upload"
  "$CI_SCRIPT_DIR/upload.sh"
else
  section "Uploadをスキップ (AUTO_UPLOAD=false)"
fi

if git -C "$REPO_PATH" rev-parse HEAD >/dev/null 2>&1; then
  git -C "$REPO_PATH" rev-parse HEAD > "$RUNTIME_DIR/last-successful-commit"
fi

section "パイプライン完了"
if [[ "$AUTO_UPLOAD" == "true" ]]; then
  notify_user "麻辣湯ログ CI" "Build / Archive / Upload Success"
else
  notify_user "麻辣湯ログ CI" "Build / Archive Success（Uploadは無効）"
fi
