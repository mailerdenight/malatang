#!/bin/zsh

CI_SCRIPT_DIR="${0:A:h}"
if [[ "${CI_SCRIPT_DIR:t}" == "lib" ]]; then
  CI_SCRIPT_DIR="${CI_SCRIPT_DIR:h}"
fi
CI_DEFAULT_REPO_ROOT="${CI_SCRIPT_DIR:h}"
CI_CONFIG_FILE="${MALATANG_CI_CONFIG:-$HOME/Library/Application Support/MalatangLogCI/config.env}"

load_ci_config() {
  if [[ -f "$CI_CONFIG_FILE" ]]; then
    # The config file is local-only and must be readable only by this user.
    source "$CI_CONFIG_FILE"
  fi

  : "${REPO_PATH:=$CI_DEFAULT_REPO_ROOT}"
  : "${PROJECT_PATH:=MalatangLog.xcodeproj}"
  : "${SCHEME:=MalatangLog}"
  : "${CONFIGURATION:=Release}"
  : "${REMOTE_NAME:=origin}"
  : "${BRANCH:=main}"
  : "${AUTO_UPLOAD:=true}"
  : "${TEAM_ID:=3U97PCNG99}"
  : "${BUNDLE_ID:=com.malatanglog.app}"
  : "${TESTFLIGHT_INTERNAL_ONLY:=true}"
  : "${SKIP_GIT_SYNC:=false}"

  if [[ "$PROJECT_PATH" != /* ]]; then
    PROJECT_PATH="$REPO_PATH/$PROJECT_PATH"
  fi
  if [[ "${ASC_KEY_PATH:-}" == "~/"* ]]; then
    ASC_KEY_PATH="$HOME/${ASC_KEY_PATH#\~/}"
  fi

  LOG_DIR="${LOG_DIR:-$REPO_PATH/logs}"
  ARTIFACTS_DIR="${ARTIFACTS_DIR:-$REPO_PATH/artifacts}"
  RUNTIME_DIR="${RUNTIME_DIR:-$REPO_PATH/.ci-runtime}"
  DERIVED_DATA_DIR="${DERIVED_DATA_DIR:-$ARTIFACTS_DIR/DerivedData}"

  mkdir -p "$LOG_DIR" "$ARTIFACTS_DIR" "$RUNTIME_DIR" "$DERIVED_DATA_DIR"
}

timestamp() {
  date '+%Y-%m-%d %H:%M:%S %z'
}

section() {
  print
  print "[$(timestamp)] $1"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    print "ERROR: 必要なコマンドが見つかりません: $1"
    return 1
  fi
}

notify_user() {
  local title="$1"
  local message="$2"
  /usr/bin/osascript - "$title" "$message" >/dev/null 2>&1 <<'APPLESCRIPT' || true
on run argv
  display notification (item 2 of argv) with title (item 1 of argv)
end run
APPLESCRIPT
}

configure_xcode_auth_args() {
  XCODE_AUTH_ARGS=()
  if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_KEY_PATH:-}" ]]; then
    if [[ ! -r "$ASC_KEY_PATH" ]]; then
      print "ERROR: App Store Connect APIキーを読み込めません: $ASC_KEY_PATH"
      return 1
    fi
    XCODE_AUTH_ARGS=(
      -authenticationKeyPath "$ASC_KEY_PATH"
      -authenticationKeyID "$ASC_KEY_ID"
      -authenticationKeyIssuerID "$ASC_ISSUER_ID"
    )
  fi
}

ensure_clean_tracked_files() {
  if ! git -C "$REPO_PATH" diff --quiet ||
     ! git -C "$REPO_PATH" diff --cached --quiet; then
    print "ERROR: Mac側の追跡ファイルに未コミット変更があります。"
    print "自動取得による上書きを避けるため処理を停止しました。"
    return 1
  fi
}

sync_latest_code() {
  if [[ "$SKIP_GIT_SYNC" == "true" ]]; then
    print "Git同期をスキップしました (SKIP_GIT_SYNC=true)。"
    return 0
  fi

  require_command git
  if ! git -C "$REPO_PATH" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    print "ERROR: REPO_PATH はGitリポジトリではありません: $REPO_PATH"
    return 1
  fi
  if ! git -C "$REPO_PATH" remote get-url "$REMOTE_NAME" >/dev/null 2>&1; then
    print "ERROR: Git remote '$REMOTE_NAME' が設定されていません。"
    return 1
  fi

  ensure_clean_tracked_files

  local current_branch
  current_branch="$(git -C "$REPO_PATH" branch --show-current)"
  if [[ "$current_branch" != "$BRANCH" ]]; then
    print "ERROR: 現在のブランチは '$current_branch' です。自動化対象 '$BRANCH' に切り替えてください。"
    return 1
  fi

  git -C "$REPO_PATH" fetch --prune "$REMOTE_NAME" "$BRANCH"
  if ! git -C "$REPO_PATH" merge-base --is-ancestor HEAD "$REMOTE_NAME/$BRANCH"; then
    print "ERROR: ローカルと $REMOTE_NAME/$BRANCH が分岐しています。"
    print "自動的なresetは行いません。手動で履歴を整理してください。"
    return 1
  fi
  git -C "$REPO_PATH" pull --ff-only "$REMOTE_NAME" "$BRANCH"
}

failure_guidance() {
  local stage="$1"
  print
  print "=== ${stage} Failed ==="
  print "停止工程: $stage"
  case "$stage" in
    "Git Sync")
      print "原因候補: GitHub認証切れ、remote/branch設定違い、未コミット変更、履歴の分岐"
      print "修正案: git status と git remote -v を確認し、SSH接続またはKeychain認証を更新してください。"
      ;;
    "Build")
      print "原因候補: コンパイルエラー、依存解決失敗、署名設定またはBundle IDの不一致"
      print "修正案: logs/build.log の最初の error: を確認し、Xcode > Settings > Accounts と Signing & Capabilities を確認してください。"
      ;;
    "Archive")
      print "原因候補: Apple Distribution証明書/プロファイル不足、App IDのCapabilities不一致、Version設定不備"
      print "修正案: Xcodeで一度Archiveを実行し、自動署名とDeveloper Program契約状態を確認してください。"
      ;;
    "Export")
      print "原因候補: App Store Connect認証未設定、Apple Distribution証明書/配布プロファイル不足、App Store Connectにアプリ未登録"
      print "修正案: APIキーをconfig.envへ設定し、XcodeのAccountsとApp Store Connect上のBundle IDを確認してください。"
      ;;
    "Upload")
      print "原因候補: APIキー/Issuer ID不一致、権限不足、App Store Connectのアプリ未登録、契約未同意、Build番号重複"
      print "修正案: App Store ConnectのUsers and Access、アプリのBundle ID、契約状態を確認してください。"
      ;;
    *)
      print "原因候補: ログに表示された直前のエラーを確認してください。"
      print "修正案: 該当ログを修正後、Scripts/pipeline.sh を手動実行して再試行できます。"
      ;;
  esac
}
