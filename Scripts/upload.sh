#!/bin/zsh
set -euo pipefail

source "${0:A:h}/lib/common.sh"
load_ci_config

UPLOAD_LOG="$LOG_DIR/upload.log"
exec > >(tee -a "$UPLOAD_LOG") 2>&1

CURRENT_STAGE="Upload"
on_error() {
  local exit_code="$1"
  trap - ERR
  failure_guidance "$CURRENT_STAGE"
  exit "$exit_code"
}
trap 'on_error $?' ERR

require_command xcrun

if [[ -z "${ASC_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" || -z "${ASC_KEY_PATH:-}" ]]; then
  print "ERROR: ASC_KEY_ID、ASC_ISSUER_ID、ASC_KEY_PATH を設定してください。"
  return 1
fi
if [[ ! -r "$ASC_KEY_PATH" ]]; then
  print "ERROR: App Store Connect APIキーを読み込めません: $ASC_KEY_PATH"
  return 1
fi

if [[ -z "${IPA_PATH:-}" ]]; then
  if [[ ! -r "$RUNTIME_DIR/latest-ipa-path" ]]; then
    print "ERROR: アップロード対象IPAがありません。先に Scripts/archive.sh を実行してください。"
    return 1
  fi
  IPA_PATH="$(<"$RUNTIME_DIR/latest-ipa-path")"
fi
if [[ ! -r "$IPA_PATH" ]]; then
  print "ERROR: IPAを読み込めません: $IPA_PATH"
  return 1
fi

AUTH_ARGS=(
  --api-key "$ASC_KEY_ID"
  --api-issuer "$ASC_ISSUER_ID"
  --p8-file-path "$ASC_KEY_PATH"
)

section "IPAを検証"
xcrun altool \
  --validate-app -f "$IPA_PATH" \
  "${AUTH_ARGS[@]}"

section "App Store Connectへアップロード"
xcrun altool \
  --upload-app -f "$IPA_PATH" \
  "${AUTH_ARGS[@]}"

print
print "Upload Success"
print "Apple側での処理完了後、TestFlightに表示されます。"
